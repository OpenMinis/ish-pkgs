#!/bin/sh
# build-script is used ONLY for: native LLVM (tblgen etc.), cmark for both
# hosts, and to generate the cross (musl-host) LLVM build directory.
# It is stopped as soon as that directory is configured: build-script's own
# handling of the linux-static cross host is wrong for everything after that
# (see NOTES.md), so the later stages drive cmake / SwiftPM directly.
. "$PKG/stages/common.sh"
ready() { [ -x "$NATIVE/bin/llvm-tblgen" ] && [ -x "$NATIVE/bin/clang" ] && [ -x "$NATIVE/bin/llvm-ar" ] && \
          [ -f "$B/cmark-linux-static-aarch64/CMakeCache.txt" ] && [ -f "$LLVM/build.ninja" ]; }
if ready; then say "native LLVM, cmark and the cross LLVM build dir already exist"; exit 0; fi
cd "$W/src/swift"
utils/build-script --release --build-subdir=musl --skip-build-benchmarks \
  --cross-compile-hosts=linux-static-aarch64 --musl-path=/usr/local/musl \
  --build-linux-static --linux-static-archs=aarch64 \
  --extra-llvm-cmake-options="-DLLVM_TARGETS_TO_BUILD=AArch64 -DLLVM_TOOL_LTO_BUILD=OFF -DLLVM_ENABLE_PLUGINS=OFF -DLLVM_BUILD_LLVM_DYLIB=OFF -DLLVM_LINK_LLVM_DYLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF -DLLVM_ENABLE_PIC=OFF -DLIBCLANG_BUILD_STATIC=ON -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DCLANG_ENABLE_ARCMT=OFF -DCLANG_BUILD_EXAMPLES=OFF" \
  --skip-test-swift --skip-test-cmark --skip-test-lldb --skip-test-llvm --skip-test-linux --skip-test-linux-static \
  --skip-build-lldb --skip-build-llbuild --skip-build-xctest --skip-build-foundation --skip-build-libdispatch \
  --jobs "$JOBS" > "$LOGS/native.log" 2>&1 &
pid=$!
while kill -0 $pid 2>/dev/null; do
  if ready; then
    say "prerequisites are in place; stopping build-script"
    pkill -TERM -P $pid 2>/dev/null || true; kill -TERM $pid 2>/dev/null || true
    pkill -TERM ninja 2>/dev/null || true
    break
  fi
  sleep 20
done
wait $pid 2>/dev/null || true
ready || { echo "FAILED: build-script ended without producing the prerequisites (log: $LOGS/native.log)"; tail -30 "$LOGS/native.log"; exit 1; }
