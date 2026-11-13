# Sourced by every stage script (they all run INSIDE the build container).
#   W    work directory mount (sources in $W/src, build trees in $W/src/build/musl)
#   PKG  this package directory, mounted read-only
set -eu
: "${W:?W (work dir mount) not set}" "${PKG:?PKG (package dir mount) not set}"
B=$W/src/build/musl                       # all build trees
NATIVE=$B/llvm-linux-aarch64              # native (build machine) LLVM: tblgen, llvm-ar, llvm-strip ...
LLVM=$B/llvm-linux-static-aarch64         # musl-host LLVM/clang/lld
SWIFT=$B/swift-linux-static-aarch64       # musl-host swift-frontend
SDK=/usr/local/musl/aarch64               # musl sysroot + static Swift runtime inside the image
TRIPLE=aarch64-swift-linux-musl
EXTRA=$W/deps/musl-extra                  # static libuuid / sqlite3 / ncurses for musl (stage: deps)
LOGS=$W/logs; mkdir -p "$LOGS"
JOBS=${JOBS:-8}
PRODUCTS=Release-staticlinux-aarch64      # SwiftPM (swiftbuild backend) product dir name on the build machine
XFLAGS="-Xcc -I$EXTRA/include -Xcxx -I$EXTRA/include -Xlinker -L$EXTRA/lib"
say() { echo "==> $*"; }
# run <logname> <cmd...>: log to $LOGS, show the tail on failure
run() { l=$LOGS/$1.log; shift; if ! "$@" > "$l" 2>&1; then echo "FAILED: $*  (log: $l)"; sed 's/\x1b\[[0-9;]*m//g' "$l" | grep -a -n -E "(^| )error[: ]|FAILED" | head -30; tail -15 "$l"; exit 1; fi; }
