#!/bin/sh
# build.sh — 交叉编译 ipatool 到 aarch64-linux-musl(给 iSH 用)。
#
# 用法:  ./build.sh <上游 tag,如 v2.7.0> [输出目录]
# 在哪跑: macOS(已装 go >= 1.23 + zig),或任何装了 go + zig 的 Linux。
#
# 产物:
#   <输出目录>/ipatool-ish-arm64-<tag>.zip     平铺的可执行文件 + PROVENANCE.txt
#   <输出目录>/ipatool-ish-arm64-<tag>/        解开后的同样内容(给 mkapk 用)
#   <输出目录>/SHA256SUMS
set -eu

TAG="${1:?用法: $0 <上游 tag,如 v2.7.0> [输出目录]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${2:-$HERE/dist}"
UPSTREAM_URL="$(sed -n 's/^url=//p' "$HERE/UPSTREAM")"
TARGET=aarch64-unknown-linux-musl
ZIG_TARGET=aarch64-linux-musl
NAME="ipatool-ish-arm64"
WORK="${WORK:-${TMPDIR:-/tmp}/ish-pkgs-ipatool-build}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少 $1: $2" >&2; exit 1; }; }
need go    "安装 Go (>=1.23): brew install go"
need zig   "安装 zig: brew install zig"
need git   "安装 git"
need zip   "安装 zip"
need file  "安装 file"
need strings "安装 binutils / Xcode 命令行工具"

echo "== 1/5 取上游源码 $UPSTREAM_URL @ $TAG"
rm -rf "$WORK" && mkdir -p "$WORK"
git clone --quiet --depth 1 --branch "$TAG" "$UPSTREAM_URL" "$WORK/src"
COMMIT="$(git -C "$WORK/src" rev-parse HEAD)"
echo "   提交: $COMMIT"

echo "== 2/5 应用补丁(patches/ 里的 *.patch,按文件名顺序)"
PATCHES=()
if ls "$HERE"/patches/*.patch >/dev/null 2>&1; then
  for p in "$HERE"/patches/*.patch; do
    git -C "$WORK/src" apply --check "$p" || { echo "补丁无法应用到 $TAG: $p" >&2; exit 1; }
    git -C "$WORK/src" apply "$p"
    PATCHES+=("$p")
    echo "   已应用 $(basename "$p")"
  done
else
  echo "   无补丁:产物是上游 $TAG 的原样编译"
fi

echo "== 3/5 交叉编译 (Go + zig cc -dynamic)"
STAGE="$OUT/$NAME-$TAG"
rm -rf "$STAGE" && mkdir -p "$STAGE"

# 必须开 CGO 并动态链接 musl libc (纯静态 musl 下 dlopen 是 stub,加载 Unicorn 会失败)
export CGO_ENABLED=1
export CC="zig cc -target $ZIG_TARGET"
export CXX="zig c++ -target $ZIG_TARGET"
export GOOS=linux
export GOARCH=arm64

(
  cd "$WORK/src"
  go build -trimpath \
    -ldflags "-s -w -linkmode external -extldflags -dynamic -X github.com/majd/ipatool/v2/cmd.version=${TAG#v}" \
    -o "$STAGE/ipatool" .
)

echo "== 4/5 验证架构与安全性"
info="$(file "$STAGE/ipatool")"
echo "$info" | grep -q 'ARM aarch64' || { echo "架构不对: $info" >&2; exit 1; }
echo "$info" | grep -q 'dynamically linked' || { echo "不是动态链接 musl: $info" >&2; exit 1; }

# 验证: 构建机路径/用户名不能出现在产物里
for f in "$STAGE"/*; do
  if strings -a "$f" | grep -qF -e "$HOME" -e "/Users/$(id -un)" -e "/private/var/folders"; then
    echo "产物里仍含构建机路径: $f" >&2
    strings -a "$f" | grep -F -e "$HOME" -e "/Users/$(id -un)" -e "/private/var/folders" | head -3 >&2
    exit 1
  fi
done

echo "== 5/5 写来源声明并打包"
{
  echo "package:      $NAME"
  echo "version:      $TAG"
  echo "upstream:     $UPSTREAM_URL"
  echo "upstream tag: $TAG"
  echo "commit:       $COMMIT"
  echo "target:       $TARGET (iSH arm64 guest, Alpine/musl, dynamic-linked)"
  echo "license:      MIT (upstream: majd/ipatool)"
  echo "built:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "toolchain:    $(go version) | zig $(zig version)"
  echo
  if [ ${#PATCHES[@]} -eq 0 ]; then
    echo "modifications: NONE. These binaries are built from the unmodified upstream source at the tag above."
  else
    echo "modifications: ${#PATCHES[@]} patch(es) applied on top of the upstream tag:"
    for p in "${PATCHES[@]}"; do
      echo "  - $(basename "$p")  sha256=$(shasum -a 256 "$p" | cut -d' ' -f1)"
    done
    echo "These binaries DIFFER from the official upstream release. Do not report issues to upstream."
  fi
  echo
  echo "files (sha256):"
  ( cd "$STAGE" && for f in *; do [ "$f" = PROVENANCE.txt ] && continue; echo "  $(shasum -a 256 "$f" | cut -d' ' -f1)  $f"; done )
} > "$STAGE/PROVENANCE.txt"

rm -f "$OUT/$NAME-$TAG.zip"
( cd "$STAGE" && zip -q -r "$OUT/$NAME-$TAG.zip" . )
( cd "$OUT" && shasum -a 256 "$NAME-$TAG.zip" > SHA256SUMS )

echo
echo "完成:"
ls -la "$OUT/$NAME-$TAG.zip" | awk '{print "  ",$5,$9}'
echo "来源声明:"; sed -n '1,/^files/p' "$STAGE/PROVENANCE.txt" | sed 's/^/  /'
