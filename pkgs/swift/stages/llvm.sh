#!/bin/sh
# Reconfigure ONLY the musl-host LLVM build directory (build-script never
# reconfigures an existing one, and --reconfigure would also rebuild the native
# LLVM), then build clang / lld / llvm-ar and the libraries Swift links.
. "$PKG/stages/common.sh"
cd "$LLVM"
run llvm-configure cmake -DLLVM_TARGETS_TO_BUILD=AArch64 -DLLVM_TOOL_LTO_BUILD=OFF -DLLVM_ENABLE_PLUGINS=OFF \
  -DLLVM_BUILD_LLVM_DYLIB=OFF -DLLVM_LINK_LLVM_DYLIB=OFF -DLLVM_ENABLE_ZSTD=OFF -DLLVM_ENABLE_LIBXML2=OFF \
  -DLLVM_ENABLE_PIC=OFF -DLLVM_INCLUDE_TESTS=ON -DCLANG_INCLUDE_TESTS=ON -DLIBCLANG_BUILD_STATIC=ON \
  -DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF -DCLANG_ENABLE_ARCMT=OFF -DCLANG_BUILD_EXAMPLES=OFF \
  -DLLVM_PARALLEL_LINK_JOBS=2 -DLLVM_ENABLE_ASSERTIONS=OFF -DLLVM_ENABLE_LIBEDIT=OFF -DLLVM_ENABLE_TERMINFO=OFF .
# -k: three test-only shared objects cannot be linked for a static target; they are not needed.
cmake --build . -- -k 50 -j"$JOBS" all LLVMTestingSupport > "$LOGS/llvm-build.log" 2>&1 || true
for t in clang-21 lld llvm-ar; do [ -x "bin/$t" ] || { echo "FAILED: $LLVM/bin/$t missing (log: $LOGS/llvm-build.log)"; tail -30 "$LOGS/llvm-build.log"; exit 1; }; done
[ -f lib/libLLVMTestingSupport.a ] && [ -f lib/cmake/clang/ClangConfig.cmake ]
n=$(grep -c "^FAILED:" "$LOGS/llvm-build.log" || true)
[ "$n" -le 3 ] || { echo "FAILED: $n failed LLVM targets (expected at most the 3 test-only .so files)"; grep "^FAILED:" "$LOGS/llvm-build.log" | head; exit 1; }
