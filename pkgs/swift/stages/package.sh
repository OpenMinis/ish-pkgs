#!/bin/sh
# Write PROVENANCE.txt into the staged toolchain and zip it.
#   $OUTC  output directory (mounted), $ZIPNAME  file name of the zip
. "$PKG/stages/common.sh"
R=${STAGE:-$W/stage/swift}
get() { sed -n "s/^$1=//p" "$PKG/UPSTREAM"; }
url=$(get url); license=$(get license)
cd "$R"; rm -f PROVENANCE.txt
{
  echo "name: swift"
  echo "upstream: $url"
  echo "tag: $TAG"
  echo "license: $license"
  echo "target: $TRIPLE (statically linked host tools; produces statically linked $TRIPLE executables)"
  echo "built: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "toolchain:"
  echo "  bootstrap compiler: $(swiftc -version 2>/dev/null | head -1)"
  echo "  static linux sdk: $(basename "$(find /root/.swiftpm/swift-sdks -maxdepth 1 -name '*.artifactbundle' | head -1)")"
  echo "  build image base: $(. /etc/os-release && echo "$PRETTY_NAME"), $(clang --version | head -1), cmake $(cmake --version | head -1 | awk '{print $3}')"
  echo "  extra static libraries (Alpine): $(tr '\n' ' ' < "$EXTRA/VERSIONS" 2>/dev/null || echo unknown)"
  echo "commits:"
  if [ -f "$W/src/COMMITS" ]; then sed 's/^/  /' "$W/src/COMMITS"; else echo "  (not recorded)"; fi
  echo "modifications:"
  for p in "$PKG"/patches/*/*.patch; do echo "  patches/$(basename "$(dirname "$p")")/$(basename "$p")  sha256=$(sha256sum "$p" | cut -d' ' -f1)"; done
  echo "  runtime archive members replaced (built from the patched sources above):"
  echo "    lib/swift_static/linux-static/libswiftCore.a: Paths.cpp.o CommandLine.cpp.o"
  echo "    lib/swift_static/linux-static/libdispatch.a: lock.c.o workqueue.c.o"
  echo "    lib/swift_static/linux-static/libCoreFoundation.a: CFPlatform.c.o"
  echo "  added: swift-testing static libraries, reduced ICU data objects, static SwiftPM runtime, wrapper scripts"
  echo "  all archives: debug info stripped; x86_64 swiftmodules removed"
  echo "files (sha256):"
  find . -type f ! -name PROVENANCE.txt | sort | while read -r f; do echo "  $(sha256sum "$f" | cut -d' ' -f1)  ${f#./}"; done
  echo "symlinks:"
  find . -type l | sort | while read -r f; do echo "  ${f#./} -> $(readlink "$f")"; done
} > "$W/PROVENANCE.txt.tmp"
mv "$W/PROVENANCE.txt.tmp" PROVENANCE.txt
mkdir -p "$OUTC"; rm -f "$OUTC/$ZIPNAME"
zip -q -r -y -9 "$OUTC/$ZIPNAME" .
( cd "$OUTC" && sha256sum "$ZIPNAME" > SHA256SUMS && cat SHA256SUMS && ls -la "$ZIPNAME" )
