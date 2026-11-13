#!/bin/sh
# iSH-like hostile environment, run inside an Alpine container:
#   hostile.sh <toolchain-prefix> <tests-dir>
# Copies the toolchain into a chroot WITHOUT /proc (so readlink("/proc/self/exe"),
# /proc/self/maps and /proc/<tid>/stat all fail) and runs selftest.sh there.
# Start the container with --security-opt seccomp=tests/seccomp-nofutexpi.json to
# also make the PI futex operations return ENOSYS.
set -e
PREFIX=$1; TESTS=$2; R=/hostile-root
mkdir -p $R/bin $R/lib $R/opt $R/tmp $R/dev $R/t
cp /bin/busybox $R/bin/busybox
for a in sh ls cat head tail grep env dirname readlink pwd cksum id mkdir mv rm sed basename tr printf stat cp chmod sort wc true; do ln -s busybox $R/bin/$a; done
cp /lib/ld-musl-*.so.1 $R/lib/
mknod -m 666 $R/dev/null c 1 3; mknod -m 666 $R/dev/urandom c 1 9
cp -a "$PREFIX" $R/opt/swift; cp "$TESTS"/*.swift "$TESTS"/selftest.sh $R/t/
[ -e $R/proc ] && { echo "chroot unexpectedly has /proc"; exit 1; }
exec chroot $R /bin/env PATH=/bin TMPDIR=/tmp /bin/sh /t/selftest.sh /opt/swift /t
