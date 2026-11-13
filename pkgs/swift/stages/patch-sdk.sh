#!/bin/sh
# Replace the five patched objects in the Static SDK runtime archives.
# Containers are ephemeral, so every stage that links against the runtime calls
# this first; it is idempotent.
#   patch-sdk.sh            patch both SDK copies inside the image
#   patch-sdk.sh check      same, but explain what to do if the objects are missing
#   patch-sdk.sh <libdir>   patch the archives in <libdir>
. "$PKG/stages/common.sh"
AR=$NATIVE/bin/llvm-ar; NM=$NATIVE/bin/llvm-nm
PATHS=$B/stdlib-linux-static-aarch64/stdlib/public/runtime/CMakeFiles/swiftRuntimeCore-linux-static-aarch64.dir/Paths.cpp.o
CMDLINE=$B/stdlib-linux-static-aarch64/stdlib/public/CommandLineSupport/CMakeFiles/swiftCommandLineSupport-linux-static-aarch64.dir/CommandLine.cpp.o
LOCK=$B/libdispatch-linux-static-aarch64/src/CMakeFiles/dispatch.dir/shims/lock.c.o
WORKQ=$B/libdispatch-linux-static-aarch64/src/CMakeFiles/dispatch.dir/event/workqueue.c.o
CFPLAT=$B/corefoundation-obj/CFPlatform.c.o
[ "${1:-}" = check ] && shift
for f in "$PATHS" "$CMDLINE" "$LOCK" "$WORKQ" "$CFPLAT"; do
  [ -f "$f" ] || { echo "missing $f -- run the 'runtime' stage first"; exit 1; }
done
if [ $# = 0 ]; then
  set -- $SDK/usr/lib/swift_static/linux-static \
         "$(dirname "$(find /root/.swiftpm/swift-sdks -path '*aarch64/usr/lib/swift_static/linux-static/libswiftCore.a')")"
fi
T=$(mktemp -d); cp "$PATHS" "$CMDLINE" "$LOCK" "$WORKQ" "$CFPLAT" "$T/"
one() { # archive member...: each member must exist exactly once before and after
  a=$1; shift
  for m in "$@"; do [ "$("$AR" t "$a" | grep -c "^$m\$")" = 1 ] || { echo "unexpected layout: $m in $a"; exit 1; }; done
  ( cd "$T" && "$AR" r "$a" "$@" )
  for m in "$@"; do [ "$("$AR" t "$a" | grep -c "^$m\$")" = 1 ]; done
}
for d in "$@"; do
  one "$d/libswiftCore.a" Paths.cpp.o CommandLine.cpp.o
  one "$d/libdispatch.a" lock.c.o workqueue.c.o
  one "$d/libCoreFoundation.a" CFPlatform.c.o
  if grep -q "Unable to obtain Swift runtime path" "$d/libswiftCore.a"; then echo "libswiftCore.a still has the fatal path lookup"; exit 1; fi
  if grep -q "registered worker exited prematurely" "$d/libdispatch.a"; then echo "libdispatch.a still has the unpatched workqueue"; exit 1; fi
  echo "    patched $d"
done
rm -rf "$T"
