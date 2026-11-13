#!/bin/sh
# Clone swiftlang/swift at $TAG and let update-checkout fetch every sibling
# repository pinned to the same tag.
. "$PKG/stages/common.sh"
mkdir -p "$W/src"; cd "$W/src"
[ -d swift/.git ] || git clone --depth 1 --branch "$TAG" https://github.com/swiftlang/swift.git swift
cd swift
utils/update-checkout --clone --tag "$TAG" --skip-history -j 4
# record what was checked out (PROVENANCE.txt)
cd "$W/src"
for d in */; do d=${d%/}; [ -d "$d/.git" ] && echo "$d $(git -C "$d" rev-parse HEAD)"; done | sort > COMMITS
