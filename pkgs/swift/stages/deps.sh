#!/bin/sh
# Runs in an ALPINE container (not the build image): collect the static musl
# libraries that llbuild / swift's lib/Basic need and the SDK does not ship.
#   OUT_DEPS = destination (…/deps/musl-extra)
set -eu
apk add --no-cache util-linux-dev util-linux-static sqlite-dev sqlite-static ncurses-dev ncurses-static >/dev/null
mkdir -p "$OUT_DEPS/include" "$OUT_DEPS/lib"
cp -a /usr/include/uuid "$OUT_DEPS/include/"
cp /usr/include/sqlite3.h /usr/include/sqlite3ext.h "$OUT_DEPS/include/"
cp /usr/lib/libuuid.a /usr/lib/libsqlite3.a /usr/lib/libncurses.a /usr/lib/libncursesw.a "$OUT_DEPS/lib/"
apk list --installed util-linux-static sqlite-static ncurses-static 2>/dev/null | cut -d' ' -f1 | sort > "$OUT_DEPS/VERSIONS"
ls -la "$OUT_DEPS/lib"
