#!/bin/sh
# swift-testing as static libraries for the musl target (the official Static
# Linux SDK ships no Testing module). The macros used while compiling the
# library itself come from the build machine's libTestingMacros.so.
. "$PKG/stages/common.sh"
T=$B/testing-linux-static-aarch64; I=$B/testing-install
# Testing imports Synchronization/Foundation/Dispatch non-publicly; clients that
# link the STATIC library need them on the link line, so record them as public
# autolink libraries (a test file that only does `import Testing` must link).
AL=""
for l in swiftSynchronization swift_Concurrency swift_StringProcessing swift_RegexParser swiftMusl fts resolv \
         Foundation FoundationEssentials FoundationInternationalization _FoundationICU _FoundationCShims _FoundationCollections \
         CoreFoundation swiftDispatch dispatch BlocksRuntime; do
  AL="$AL -Xfrontend -public-autolink-library -Xfrontend $l"
done
# -enable-library-evolution for EVERY module: upstream's CMake only sets it for
# Testing itself. Without it the binary _Testing_Foundation.swiftmodule (loaded
# as a cross-import overlay when a file imports both Testing and Foundation, as
# SwiftPM test targets do) requires the internal C module _TestingInternals,
# which is not installed: "missing required modules: '_TestingInternals'".
SWFLAGS="-sdk $SDK -resource-dir $SDK/usr/lib/swift_static -static-stdlib -use-ld=lld -enable-library-evolution -Xcc -I$PKG/files/testing-shim $AL"
mkdir -p "$T"; cd "$T"
if [ ! -f CMakeCache.txt ]; then
run testing-configure cmake -G Ninja "$W/src/swift-testing" \
  -DCMAKE_TOOLCHAIN_FILE="$PKG/files/swift-toolchain.cmake" -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_Swift_COMPILER=/usr/bin/swiftc \
  -DCMAKE_CXX_FLAGS="-mno-outline-atomics -I$PKG/files/testing-shim" -DCMAKE_Swift_FLAGS="$SWFLAGS" \
  -DBUILD_SHARED_LIBS=OFF -DSwiftTesting_MACRO=/usr/lib/swift/host/plugins/libTestingMacros.so \
  -DCMAKE_INSTALL_PREFIX="$I/usr"
fi
run testing-build ninja
rm -rf "$I"; run testing-install ninja install
[ -f "$I/usr/lib/swift_static/linux-static/libTesting.a" ]
