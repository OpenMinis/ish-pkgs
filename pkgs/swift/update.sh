#!/bin/sh
# Read-only check: is there a newer upstream release tag than the one in UPSTREAM?
# Prints the result; never modifies anything. Exit status: 0 up to date,
# 10 newer release available, 1 error.
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
get() { sed -n "s/^$1=//p" "$DIR/UPSTREAM"; }
name=$(get name); url=$(get url); tag=$(get tag)
latest=$(git ls-remote --tags --refs "$url.git" 'refs/tags/swift-*-RELEASE' 2>/dev/null \
  | sed -n 's|.*refs/tags/\(swift-[0-9][0-9.]*-RELEASE\)$|\1|p' \
  | sed 's/^swift-//; s/-RELEASE$//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
[ -n "$latest" ] || { echo "$name: could not list upstream tags from $url" >&2; exit 1; }
latest_tag="swift-$latest-RELEASE"
if [ "$latest_tag" = "$tag" ]; then
  echo "$name: up to date ($tag)"
  exit 0
fi
echo "$name: packaged $tag, latest upstream release is $latest_tag"
echo "  to update: add the Static Linux SDK checksum for $latest to docker/static-sdk-checksums,"
echo "  run ./build.sh $latest_tag, fix patches that no longer apply, then bump 'tag' in UPSTREAM."
exit 10
