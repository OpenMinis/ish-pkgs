#!/bin/sh
# Rebuild the five patched runtime objects with the same settings as the
# official Static Linux SDK build, then replace them in the image's SDK copies.
#   libswiftCore.a        Paths.cpp.o, CommandLine.cpp.o
#   libdispatch.a         lock.c.o, workqueue.c.o
#   libCoreFoundation.a   CFPlatform.c.o
. "$PKG/stages/common.sh"
N=$NATIVE
# --- stdlib objects: a musl-TARGET stdlib build dir (never built completely)
S=$B/stdlib-linux-static-aarch64; mkdir -p "$S"; cd "$S"
if [ ! -f CMakeCache.txt ]; then
run stdlib-configure cmake -G Ninja \
 -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ -DCMAKE_Swift_COMPILER=/usr/bin/swiftc \
 -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
 "-DCMAKE_C_FLAGS=-Wno-unknown-warning-option -fno-stack-protector" "-DCMAKE_CXX_FLAGS=-Wno-unknown-warning-option -fno-stack-protector" \
 -DLLVM_ENABLE_ASSERTIONS=OFF \
 -DSWIFT_HOST_VARIANT=linux -DSWIFT_HOST_VARIANT_SDK=LINUX -DSWIFT_HOST_VARIANT_ARCH=aarch64 \
 -DSWIFT_SDKS=LINUX_STATIC -DSWIFT_MUSL_PATH=/usr/local/musl -DSWIFT_SDK_LINUX_STATIC_ARCHITECTURES=aarch64 \
 -DSWIFT_PRIMARY_VARIANT_SDK=LINUX_STATIC -DSWIFT_PRIMARY_VARIANT_ARCH=aarch64 \
 -DBOOTSTRAPPING_MODE=HOSTTOOLS -DSWIFT_BUILD_SWIFT_SYNTAX=FALSE \
 -DSWIFT_NATIVE_SWIFT_TOOLS_PATH=/usr/bin -DSWIFT_NATIVE_LLVM_TOOLS_PATH="$N/bin" -DSWIFT_NATIVE_CLANG_TOOLS_PATH="$N/bin" \
 -DLLVM_TABLEGEN="$N/bin/llvm-tblgen" \
 -DClang_DIR="$N/lib/cmake/clang" -DLLVM_DIR="$N/lib/cmake/llvm" \
 -DSWIFT_PATH_TO_CMARK_SOURCE="$W/src/cmark" -DSWIFT_PATH_TO_CMARK_BUILD="$B/cmark-linux-aarch64" \
 -DSWIFT_PATH_TO_SWIFT_SYNTAX_SOURCE="$W/src/swift-syntax" \
 -DSWIFT_PATH_TO_STRING_PROCESSING_SOURCE="$W/src/swift-experimental-string-processing" \
 -DSWIFT_PATH_TO_LIBDISPATCH_SOURCE="$W/src/swift-corelibs-libdispatch" \
 -DSWIFT_INCLUDE_TOOLS=FALSE -DSWIFT_INCLUDE_TESTS=FALSE -DSWIFT_INCLUDE_TEST_BINARIES=FALSE -DSWIFT_INCLUDE_DOCS=FALSE \
 -DSWIFT_BUILD_RUNTIME_WITH_HOST_COMPILER=TRUE \
 -DSWIFT_BUILD_DYNAMIC_STDLIB=TRUE -DSWIFT_BUILD_STATIC_STDLIB=FALSE \
 -DSWIFT_BUILD_DYNAMIC_SDK_OVERLAY=TRUE -DSWIFT_BUILD_STATIC_SDK_OVERLAY=FALSE \
 -DSWIFT_BUILD_REMOTE_MIRROR=FALSE -DSWIFT_BUILD_SOURCEKIT=FALSE \
 -DSWIFT_BUILD_PERF_TESTSUITE=FALSE -DSWIFT_BUILD_EXAMPLES=FALSE \
 -DSWIFT_ENABLE_DISPATCH=FALSE -DSWIFT_SHOULD_BUILD_EMBEDDED_STDLIB=FALSE \
 -DSWIFT_STDLIB_BUILD_TYPE=Release -DSWIFT_STDLIB_ASSERTIONS=FALSE \
 -DSWIFT_ENABLE_EXPERIMENTAL_STRING_PROCESSING=TRUE \
 -DSWIFT_ENABLE_EXPERIMENTAL_DIFFERENTIABLE_PROGRAMMING=TRUE -DSWIFT_ENABLE_EXPERIMENTAL_CONCURRENCY=TRUE \
 -DSWIFT_ENABLE_EXPERIMENTAL_CXX_INTEROP=TRUE -DSWIFT_ENABLE_EXPERIMENTAL_DISTRIBUTED=TRUE \
 -DSWIFT_ENABLE_EXPERIMENTAL_OBSERVATION=TRUE -DSWIFT_ENABLE_SYNCHRONIZATION=TRUE -DSWIFT_ENABLE_VOLATILE=TRUE \
 -DSWIFT_ENABLE_BACKTRACING=TRUE -DSWIFT_ENABLE_RUNTIME_MODULE=TRUE \
 -DSWIFT_DARWIN_XCRUN_TOOLCHAIN=default \
 "$W/src/swift"
fi
run stdlib-objects ninja \
  stdlib/public/runtime/CMakeFiles/swiftRuntimeCore-linux-static-aarch64.dir/Paths.cpp.o \
  stdlib/public/CommandLineSupport/CMakeFiles/swiftCommandLineSupport-linux-static-aarch64.dir/CommandLine.cpp.o
# --- libdispatch objects (C part only)
D=$B/libdispatch-linux-static-aarch64; mkdir -p "$D"; cd "$D"
if [ ! -f CMakeCache.txt ]; then
run dispatch-configure cmake -G Ninja -DCMAKE_TOOLCHAIN_FILE="$PKG/files/swift-toolchain.cmake" \
 -DCMAKE_C_COMPILER=/usr/bin/clang -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
 -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=NO -DENABLE_SWIFT=NO -DBUILD_TESTING=NO \
 "-DCMAKE_C_FLAGS=-fno-stack-protector -mno-outline-atomics -D_GNU_SOURCE" "-DCMAKE_CXX_FLAGS=-fno-stack-protector -mno-outline-atomics -D_GNU_SOURCE" \
 "$W/src/swift-corelibs-libdispatch"
fi
run dispatch-objects ninja src/CMakeFiles/dispatch.dir/shims/lock.c.o src/CMakeFiles/dispatch.dir/event/workqueue.c.o
# --- CoreFoundation: one file, compiled directly with the flags of the official CMake build
CF=$W/src/swift-corelibs-foundation/Sources/CoreFoundation
O=$B/corefoundation-obj; mkdir -p "$O"
run cfplatform clang --target=$TRIPLE --sysroot=$SDK -O2 -fPIC -fno-omit-frame-pointer -mno-outline-atomics \
  -D_GNU_SOURCE -DDEPLOYMENT_RUNTIME_SWIFT -DCF_BUILDING_CF -DHAVE_STRUCT_TIMESPEC \
  -DHAVE_STRLCAT -DHAVE_STRLCPY -DHAVE_ISSETUGID -DHAVE_SCHED_GETAFFINITY -w \
  -fblocks -fconstant-cfstrings -fdollars-in-identifiers -fno-common -fcf-runtime-abi=swift -fexceptions \
  -I"$CF/include" -I"$CF/internalInclude" -I$SDK/usr/lib/swift_static -I$SDK/usr/lib/swift_static/Block \
  -include "$CF/internalInclude/CoreFoundation_Prefix.h" -c "$CF/CFPlatform.c" -o "$O/CFPlatform.c.o"
"$PKG/stages/patch-sdk.sh"
