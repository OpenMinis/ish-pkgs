#!/bin/sh
# Assemble the relocatable toolchain. The musl sysroot is merged into the prefix:
#   bin/                swift, swiftc (wrappers), swift-frontend, swift-driver, SwiftPM, clang, lld, llvm-ar ...
#   include/            musl + libc++ headers            (sysroot)
#   lib/*.a, lib/*.o    musl libc, libc++, crt files ... (sysroot)
#   lib/swift           compiler resource directory (clang headers, shims, SwiftPM runtime)
#   lib/swift_static    static Swift runtime for the musl target (patched archives)
#   lib/clang/<v>       -> swift/clang
#   share/swift         diagnostics data, BUILD_INFO
#   SDKSettings.json
# The wrapper passes the prefix itself as SDK / sysroot.
. "$PKG/stages/common.sh"
R=${STAGE:-$W/stage/swift}
STRIP=$NATIVE/bin/llvm-strip
"$PKG/stages/patch-sdk.sh" $SDK/usr/lib/swift_static/linux-static
rm -rf "$R"; mkdir -p "$R/bin"
say "sysroot + runtime"
cp -a $SDK/usr/include "$R/include"
cp -a $SDK/usr/lib "$R/lib"
cp -a $SDK/SDKSettings.json "$R/"
rm -rf "$R/lib/cmake" "$R/lib/pkgconfig"
# the static resource dir is passed explicitly (-resource-dir lib/swift_static); it has no shims of its own
[ -e "$R/lib/swift_static/shims" ] || ln -s ../swift/shims "$R/lib/swift_static/shims"
say "tools"
cp "$SWIFT/bin/swift-frontend" "$R/bin/"
cp "$B/swift-driver-static/out/Products/$PRODUCTS/swift-driver" "$R/bin/"
cp "$B/macros-plugin-static/out/Products/$PRODUCTS/swift-builtin-macros" "$R/bin/"
cp "$B/swiftpm-static/out/Products/$PRODUCTS/swift-package-manager" "$R/bin/"
CLANG=$(basename "$(ls "$LLVM"/bin/clang-[0-9]* | head -1)"); CLANGV=${CLANG#clang-}
cp "$LLVM/bin/$CLANG" "$LLVM/bin/lld" "$LLVM/bin/llvm-ar" "$R/bin/"
for b in swift-frontend swift-driver swift-builtin-macros swift-package-manager; do
  if grep -q "Unable to obtain Swift runtime path" "$R/bin/$b"; then echo "$b was linked against the UNPATCHED runtime"; exit 1; fi
done
"$STRIP" "$R/bin/swift-frontend" "$R/bin/swift-driver" "$R/bin/swift-builtin-macros" "$R/bin/swift-package-manager" \
         "$R/bin/$CLANG" "$R/bin/lld" "$R/bin/llvm-ar"
for l in swift-autolink-extract swiftc-legacy-driver swift-legacy-driver; do ln -s swift-frontend "$R/bin/$l"; done
for l in swift-build swift-package swift-run swift-test swift-sdk; do ln -s swift-package-manager "$R/bin/$l"; done
ln -s "$CLANG" "$R/bin/clang"; ln -s "$CLANG" "$R/bin/clang++"; ln -s lld "$R/bin/ld.lld"
# clang loads <triple>-clang.cfg from its own directory: -static, lld, libc++, compiler-rt
cp /usr/bin/$TRIPLE-clang.cfg /usr/bin/$TRIPLE-clang++.cfg "$R/bin/"
cp "$PKG/files/wrappers/swiftc" "$PKG/files/wrappers/swift" "$PKG/files/wrappers/swiftc-info" "$R/bin/"
chmod 755 "$R/bin/swiftc" "$R/bin/swift" "$R/bin/swiftc-info"
# The legacy driver runs `ar` for static libraries. Shipping bin/ar would clash
# with binutils when the toolchain is installed into /usr, so keep it in a
# private directory that the swiftc wrapper appends to PATH.
mkdir -p "$R/lib/swift/toolbin"; ln -s ../../../bin/llvm-ar "$R/lib/swift/toolbin/ar"
say "resource directory"
cp -a "$LLVM/lib/clang/$CLANGV/include/." "$R/lib/swift/clang/include/"
mkdir -p "$R/lib/clang"; ln -s ../swift/clang "$R/lib/clang/$CLANGV"
mkdir -p "$R/share/swift"; cp -a "$SWIFT/share/swift/diagnostics" "$SWIFT/share/swift/compatibility-symbols" "$R/share/swift/" 2>/dev/null || true
say "swift-testing, SwiftPM runtime, reduced ICU data"
cp -a "$B/testing-install/usr/lib/swift_static/linux-static/." "$R/lib/swift_static/linux-static/"
# Binary .swiftmodule files ONLY (here and for the SwiftPM runtime below). With a
# .swiftinterface next to it the compiler validates the binary module against
# build-machine paths, finds it "out of date" and recompiles the interface on
# the device for every new module cache.
for m in Testing _TestDiscovery _TestingInterop _Testing_Foundation; do
  cp "$B/testing-linux-static-aarch64/swift/$m.swiftmodule" "$R/lib/swift_static/linux-static/$m.swiftmodule/$TRIPLE.swiftmodule"
  rm -f "$R/lib/swift_static/linux-static/$m.swiftmodule"/*.swiftinterface
done
mkdir -p "$R/lib/swift/pm"; cp -a "$B/pmruntime-install/usr/lib/swift/pm/." "$R/lib/swift/pm/"
find "$R/lib/swift/pm" \( -name '*.abi.json' -o -name '*.swiftsourceinfo' -o -name '*.swiftinterface' \) -delete
mkdir -p "$R/lib/swift_static/icu-data"; cp "$B/icudata/icudata-small.o" "$B/icudata/icudata-tiny.o" "$R/lib/swift_static/icu-data/"
say "slimming"
find "$R/lib" -path '*.swiftmodule/x86_64*' -delete
# lib/swift must be a complete resource dir too: the legacy driver's merge-modules
# job (-g) does not pass the static resource dir
rm -rf "$R/lib/swift/linux-static"
for d in "$R"/lib/swift_static/*/; do
  n=$(basename "$d"); [ -e "$R/lib/swift/$n" ] || ln -s "../swift_static/$n" "$R/lib/swift/$n"
done
find "$R/lib" -name '*.a' -exec "$STRIP" --strip-debug {} +
find "$R/lib" -name '*.o' -size +0 -exec "$STRIP" --strip-debug {} +
echo "$TAG $TRIPLE" > "$R/share/swift/BUILD_INFO"
du -sh "$R" "$R/bin" "$R/lib" "$R/include" "$R/share"
