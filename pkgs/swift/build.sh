#!/bin/sh
# Build the statically linked Swift toolchain for iSH (Alpine/musl, arm64).
#
#   ./build.sh <tag> [outdir] [options]
#       <tag>      upstream tag, e.g. swift-6.4.2-RELEASE (see UPSTREAM)
#       [outdir]   where the zip and SHA256SUMS go (default: ./out)
#   options
#       --from <stage>   redo <stage> and everything after it
#       --only <stage>   run just this stage (ignores stamps)
#       --list           list the stages and their state, then exit
#       --hostile        also run the self test in a chroot without /proc and
#                        with PI futexes disabled (the iSH failure modes)
#   environment
#       WORK     build directory (default: ./work); needs ~40 GB free
#       JOBS     parallel jobs (default: 8; LLVM links need ~1.5 GB each)
#       DOCKER   docker command (default: docker)
#       IMAGE    name for the build image (default: swift-ish-builder:<version>)
#
# Requirements: an arm64 (aarch64) host with Docker — Linux, or macOS with
# Docker Desktop / OrbStack. About 40 GB of disk in $WORK (plus ~7 GB for the
# image), 12 GB of RAM available to containers, 2-3 hours on 8-12 cores.
# Every stage leaves a stamp in $WORK/.stamps; a failed build resumes at the
# stage that failed, and `--from <stage>` forces a restart from there.
set -eu

STAGES="image checkout deps patch native llvm runtime swift driver macros testing swiftpm icu assemble selftest package"
PKGDIR=$(cd "$(dirname "$0")" && pwd)
usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

TAG=""; OUT=""; FROM=""; ONLY=""; LIST=""; HOSTILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --from) FROM=$2; shift 2 ;;
    --only) ONLY=$2; shift 2 ;;
    --list) LIST=1; shift ;;
    --hostile) HOSTILE=1; shift ;;
    -h|--help) usage 0 ;;
    -*) echo "unknown option: $1" >&2; usage 1 ;;
    *) if [ -z "$TAG" ]; then TAG=$1; elif [ -z "$OUT" ]; then OUT=$1; else usage 1; fi; shift ;;
  esac
done
[ -n "$TAG" ] || usage 1
case "$TAG" in swift-*-RELEASE) ;; *) echo "tag must look like swift-<version>-RELEASE" >&2; exit 1 ;; esac
VERSION=${TAG#swift-}; VERSION=${VERSION%-RELEASE}
OUT=${OUT:-$PWD/out}; WORK=${WORK:-$PWD/work}
DOCKER=${DOCKER:-docker}; IMAGE=${IMAGE:-swift-ish-builder:$VERSION}; JOBS=${JOBS:-8}
ZIPNAME="swift-ish-arm64-v$VERSION.zip"
CW=/w            # mount point of $WORK inside the containers (CMake caches record it: keep it stable)
for s in $FROM $ONLY; do case " $STAGES " in *" $s "*) ;; *) echo "unknown stage: $s (stages: $STAGES)" >&2; exit 1 ;; esac; done

mkdir -p "$WORK/.stamps" "$WORK/logs" "$OUT"
WORK=$(cd "$WORK" && pwd); OUT=$(cd "$OUT" && pwd)
stamp() { echo "$WORK/.stamps/$1-$TAG"; }

if [ -n "$LIST" ]; then
  for s in $STAGES; do [ -f "$(stamp "$s")" ] && echo "done     $s" || echo "pending  $s"; done; exit 0
fi

command -v "$DOCKER" >/dev/null 2>&1 || { echo "error: '$DOCKER' not found. Install Docker (or set DOCKER=...)." >&2; exit 1; }
ARCH=$("$DOCKER" info --format '{{.Architecture}}' 2>/dev/null || echo unknown)
case "$ARCH" in aarch64|arm64) ;; *) echo "error: this build needs an arm64 Docker host (found: $ARCH). The build runs the freshly built aarch64 tools natively." >&2; exit 1 ;; esac
if [ ! -f "$(stamp native)" ]; then
  FREE_GB=$(df -Pk "$WORK" | awk 'NR==2 {print int($4/1048576)}')
  if [ "$FREE_GB" -lt 40 ]; then
    echo "error: only ${FREE_GB} GB free in $WORK; a full build needs about 40 GB (sources ~9 GB, two LLVM builds ~20 GB, the rest ~10 GB)." >&2
    echo "       Point WORK at a bigger volume. On macOS a volume that Docker cannot write to can be worked around with a sparse disk image." >&2
    exit 1
  fi
  MEM_GB=$("$DOCKER" info --format '{{.MemTotal}}' 2>/dev/null | awk '{print int($1/1073741824)}')
  [ "${MEM_GB:-0}" -ge 11 ] || echo "warning: Docker has ${MEM_GB:-?} GB of memory; 12 GB or more is recommended (lower JOBS if links get killed)." >&2
fi

if [ -n "$FROM" ]; then
  hit=""; for s in $STAGES; do [ "$s" = "$FROM" ] && hit=1; [ -n "$hit" ] && rm -f "$(stamp "$s")"; done
fi

# run a stage script inside the build image
in_image() {
  "$DOCKER" run --rm -e W=$CW -e PKG=/pkg -e TAG="$TAG" -e JOBS="$JOBS" -e STAGE=$CW/stage/swift \
    -e OUTC=/out -e ZIPNAME="$ZIPNAME" \
    -v "$WORK":$CW -v "$PKGDIR":/pkg:ro -v "$OUT":/out "$IMAGE" sh "/pkg/stages/$1.sh"
}

run_stage() {
  case "$1" in
    image)
      SDK_SUM=$(awk -F= -v v="$VERSION" '$1==v {print $2}' "$PKGDIR/docker/static-sdk-checksums")
      [ -n "$SDK_SUM" ] || { echo "error: no Static Linux SDK checksum for $VERSION in docker/static-sdk-checksums (add it; see README)." >&2; return 1; }
      "$DOCKER" build -t "$IMAGE" --build-arg SWIFT_VERSION="$VERSION" --build-arg STATIC_SDK_CHECKSUM="$SDK_SUM" "$PKGDIR/docker" ;;
    deps)
      mkdir -p "$WORK/deps/musl-extra"
      "$DOCKER" run --rm -e OUT_DEPS=/deps -v "$WORK/deps/musl-extra":/deps -v "$PKGDIR":/pkg:ro alpine:3.21 sh /pkg/stages/deps.sh ;;
    selftest)
      "$DOCKER" run --rm -v "$WORK/stage/swift":/opt/swift:ro -v "$PKGDIR/tests":/t:ro alpine:3.21 sh /t/selftest.sh /opt/swift /t
      if [ -n "$HOSTILE" ]; then
        echo "==> hostile environment (no /proc, no PI futex)"
        "$DOCKER" run --rm --security-opt seccomp="$PKGDIR/tests/seccomp-nofutexpi.json" \
          -v "$WORK/stage/swift":/opt/swift:ro -v "$PKGDIR/tests":/t:ro alpine:3.21 sh /t/hostile.sh /opt/swift /t
      fi ;;
    *) in_image "$1" ;;
  esac
}

for s in $STAGES; do
  [ -n "$ONLY" ] && [ "$s" != "$ONLY" ] && continue
  if [ -z "$ONLY" ] && [ -f "$(stamp "$s")" ]; then echo "=== $s: already done (use --from $s to redo)"; continue; fi
  echo "=== $s"
  if run_stage "$s"; then
    : > "$(stamp "$s")"
  else
    echo "*** stage '$s' failed. Logs: $WORK/logs. Fix the problem and rerun; the build resumes at '$s'." >&2
    exit 1
  fi
done
[ -n "$ONLY" ] || echo "=== done: $OUT/$ZIPNAME"
