#!/bin/sh
# Self test, run inside an Alpine container (busybox sh):
#   selftest.sh <toolchain-prefix> <tests-dir>
# Compiles and runs the sample programs; every product is run 20 times.
# Exits non-zero if anything fails.
PREFIX=$1; TESTS=$2
export PATH="$PREFIX/bin:$PATH"
WD=${TMPDIR:-/tmp}/swift-selftest.$$; mkdir -p "$WD"; cd "$WD" || exit 1
cp "$TESTS"/*.swift .
fail=0
t() { # t <count> <cmd...>
  n=$1; shift; ok=0; rcs=""
  i=0; while [ $i -lt "$n" ]; do i=$((i+1)); "$@" >out.txt 2>err.txt; rc=$?; [ $rc = 0 ] && ok=$((ok+1)) || rcs="$rcs $rc"; done
  echo "$ok/$n :: $*$rcs"
  [ "$ok" = "$n" ] || { fail=1; head -5 err.txt; }
}
expect() { # expect <pattern> <cmd...>
  p=$1; shift
  if "$@" 2>&1 | grep -q -- "$p"; then echo "ok   :: $* ~ $p"; else echo "FAIL :: $* (expected: $p)"; fail=1; fi
}
expect "Swift version" swiftc -version
expect "aarch64-swift-linux-musl" swiftc -version
expect "OVERVIEW" swiftc --help
expect "toolchain root" swiftc-info
t 1 swiftc hello.swift -o hello
t 1 swiftc -g hello.swift -o hello_g
t 1 swiftc -O -parse-as-library conc.swift -o conc
t 1 swiftc -g -parse-as-library conc.swift -o conc_g
t 1 swiftc -O -parse-as-library async.swift -o async
t 1 swiftc -g -O -parse-as-library stress.swift -o stress
t 1 swiftc -parse-as-library macro1.swift -o macro1
t 1 swiftc -O -parse-as-library mtest.swift -o mtest
t 1 swiftc -emit-module -emit-library -static -module-name MyLib mylib.swift
t 1 swiftc -I . -L . -lMyLib usemain.swift -o usemain
t 1 swiftc bundle.swift -o bundle
t 1 swiftc -parse-as-library deep.swift -o deep     # needs the 8 MB default thread stack
t 1 env SWIFTC_DRIVER=new swiftc -g hello.swift -o hello_n
t 1 env SWIFTC_ICU=small swiftc -O hello.swift -o hello_small
t 1 env SWIFTC_ICU=tiny swiftc -O hello.swift -o hello_tiny
for b in hello hello_g hello_n conc conc_g async stress macro1 mtest usemain bundle deep hello_small hello_tiny; do t 20 ./$b; done
t 2 swift hello.swift one two
expect "observable: 5 true" ./macro1
expect "Test run with 4 tests" ./mtest
# SwiftPM, offline: executable package with a swift-testing test
mkdir -p pm && cd pm && t 1 swift package init --type executable --name demo
cat > Tests/demoTests/demoTests.swift <<'E'
import Testing
import Foundation   // Testing + Foundation loads the _Testing_Foundation cross-import overlay
@testable import demo
@Test func arithmetic() { #expect(1 + 1 == 2) }
@Test func dates() { #expect(Date().timeIntervalSince1970 > 0) }
E
t 1 swift build
t 20 .build/debug/demo
t 1 swift build -c release
t 1 swift test
expect "Test run with 2 tests" swift test
# a file that imports ONLY Testing must link (Synchronization etc. are autolinked)
cd "$WD"
printf 'import Testing\n@Test func only() { #expect(2 > 1) }\n@main struct R { static func main() async { await Testing.__swiftPMEntryPoint() as Never } }\n' > tonly.swift
t 1 swiftc -parse-as-library tonly.swift -o tonly
t 20 ./tonly
cd "$WD/.." && rm -rf "$WD"
[ $fail = 0 ] && echo "SELFTEST PASSED" || echo "SELFTEST FAILED"
exit $fail
