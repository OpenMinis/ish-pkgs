#!/bin/sh
# SwiftPM: (1) the manifest/plugin runtime libraries as STATIC archives,
# (2) the multi-call swift-package-manager executable.
. "$PKG/stages/common.sh"
"$PKG/stages/patch-sdk.sh" check
# (1) PackageDescription imports Foundation implementation-only, so a manifest
# linked statically against it gets no autolink entries for Foundation; record
# them as public autolink libraries of the modules.
AL=""
for l in swiftMusl fts resolv swift_Concurrency swift_StringProcessing swift_RegexParser swift_Builtin_float swiftObservation \
         Foundation FoundationEssentials FoundationInternationalization _FoundationICU _FoundationCShims _FoundationCollections \
         CoreFoundation swiftDispatch dispatch BlocksRuntime swiftSynchronization; do
  AL="$AL -Xfrontend -public-autolink-library -Xfrontend $l"
done
R=$B/pmruntime-linux-static-aarch64; I=$B/pmruntime-install
mkdir -p "$R"; cd "$R"
if [ ! -f CMakeCache.txt ]; then
run pmruntime-configure cmake -G Ninja "$W/src/swiftpm/Sources/Runtimes" \
  -DCMAKE_TOOLCHAIN_FILE="$PKG/files/swift-toolchain.cmake" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_Swift_COMPILER=/usr/bin/swiftc -DBUILD_SHARED_LIBS=OFF \
  -DCMAKE_Swift_FLAGS="-sdk $SDK -resource-dir $SDK/usr/lib/swift_static -static-stdlib -use-ld=lld $AL" \
  -DCMAKE_INSTALL_PREFIX="$I/usr"
fi
run pmruntime-build ninja
rm -rf "$I"; run pmruntime-install ninja install
[ -f "$I/usr/lib/swift/pm/ManifestAPI/libPackageDescription.a" ]
# (2) SWIFTCI_INSTALL_RPATH_OS=android: the manifest asks pkg-config for sqlite3,
# which would add the build machine's glibc lib dir to the link; this is the
# manifest's only switch for turning that off (its extra rpath flags are no-ops
# for a static executable).
# stack-size: musl gives secondary threads 128 KB; SwiftPM overflows that while
# parsing arguments on a libdispatch worker. musl uses PT_GNU_STACK (<= 8 MB) as
# the default thread stack size.
cd "$W/src/swiftpm"
rm -f "$B/swiftpm-static/out/Products/$PRODUCTS/swift-package-manager"
SWIFTCI_USE_LOCAL_DEPS=1 SWIFTCI_INSTALL_RPATH_OS=android run swiftpm swift build -c release --swift-sdk $TRIPLE \
  --product swift-package-manager --scratch-path "$B/swiftpm-static" $XFLAGS -Xlinker -z -Xlinker stack-size=8388608
[ -x "$B/swiftpm-static/out/Products/$PRODUCTS/swift-package-manager" ]
