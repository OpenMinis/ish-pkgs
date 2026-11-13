#!/bin/sh
# Apply patches/<repo>/*.patch (in file-name order) with `git apply` inside
# $W/src/<repo>. Already-applied patches are detected and skipped.
. "$PKG/stages/common.sh"
for d in "$PKG"/patches/*/; do
  repo=$(basename "$d")
  [ -d "$W/src/$repo" ] || { echo "missing repository $W/src/$repo"; exit 1; }
  for p in "$d"*.patch; do
    cd "$W/src/$repo"
    if git apply --reverse --check "$p" 2>/dev/null; then
      echo "    already applied: $repo/$(basename "$p")"
    else
      git apply --whitespace=nowarn "$p" || { echo "FAILED to apply $repo/$(basename "$p")"; exit 1; }
      echo "    applied: $repo/$(basename "$p")"
    fi
  done
done
# build-script caches byte-compiled modules
find "$W/src/swift/utils" -name __pycache__ -type d -exec rm -rf {} + 2>/dev/null || true
