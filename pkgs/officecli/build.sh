#!/bin/bash
# build.sh — 把 OfficeCLI 编译成 linux-musl-arm64 的 ReadyToRun 单文件(给 iSH 用)。
#
# 为什么要自己编: 上游发布的 officecli-linux-alpine-arm64 不带 ReadyToRun 预编译代码,
# 每条命令都要 RyuJIT 现场编译;在 iSH(指令级模拟)里这部分特别慢。
# 加 -p:PublishReadyToRun=true 后单条命令大约快 6 倍,代价是文件大约 3 倍。
#
# 用法:  ./build.sh <上游 tag,如 v1.0.160> [输出目录]
# 在哪跑: 装了 .NET 10 SDK 的 macOS / Linux(交叉发布,不需要 zig)。
#         SDK 不在 PATH 时用 DOTNET=/path/to/dotnet 指定。
#
# 产物:
#   <输出目录>/officecli-ish-arm64-<tag>.zip     officecli + PROVENANCE.txt + NOTICE 等
#   <输出目录>/officecli-ish-arm64-<tag>/        解开后的同样内容
#   <输出目录>/SHA256SUMS
set -eu

TAG="${1:?用法: $0 <上游 tag,如 v1.0.160> [输出目录]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${2:-$HERE/dist}"
UPSTREAM_URL="$(sed -n 's/^url=//p' "$HERE/UPSTREAM")"
RID=linux-musl-arm64
NAME="officecli-ish-arm64"
WORK="${WORK:-${TMPDIR:-/tmp}/ish-pkgs-officecli-build}"
DOTNET="${DOTNET:-dotnet}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少 $1: $2" >&2; exit 1; }; }
need "$DOTNET" "安装 .NET 10 SDK: https://dot.net/v1/dotnet-install.sh --channel 10.0(或设 DOTNET=)"
need git   "安装 git"
need zip   "安装 zip"
need file  "安装 file"
need python3 "安装 python3"

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
  echo "   无补丁"
fi

echo "== 3/5 发布 ($RID, ReadyToRun)"
STAGE="$OUT/$NAME-$TAG"
rm -rf "$STAGE" && mkdir -p "$STAGE"
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
# 包缓存和中间产物都放进 WORK,不碰 ~/.nuget;PathMap 把构建机路径换成 /src
export NUGET_PACKAGES="$WORK/nuget"
( cd "$WORK/src" && "$DOTNET" publish src/officecli/officecli.csproj -c Release -r "$RID" \
    -p:PublishReadyToRun=true -p:DebugType=none -p:DebugSymbols=false \
    -p:ContinuousIntegrationBuild=true -p:Deterministic=true \
    "-p:PathMap=$WORK/src=/src" \
    -o "$WORK/pub" --nologo -v quiet )
install -m755 "$WORK/pub/officecli" "$STAGE/officecli"
for f in NOTICE THIRD-PARTY-NOTICES.txt; do cp "$WORK/src/$f" "$STAGE/$f"; done

echo "== 4/5 验证架构与安全性"
info="$(file "$STAGE/officecli")"
echo "$info" | grep -q 'ARM aarch64' || { echo "架构不对: $info" >&2; exit 1; }
echo "$info" | grep -q 'ld-musl-aarch64' || { echo "不是 musl 动态链接: $info" >&2; exit 1; }
# 构建机路径/用户名不能出现在产物里。.NET 元数据里的字符串是 UTF-16,所以两种编码都查
# (macOS 自带的 strings 没有 -e,这里用 python 直接搜字节)。
python3 - "$STAGE/officecli" "$HOME" "/Users/$(id -un)" "/private/var/folders" "$WORK" <<'PY' || exit 1
import sys
data = open(sys.argv[1], "rb").read()
bad = [(p, e) for p in sys.argv[2:] for e in ("utf-8", "utf-16-le") if p.encode(e) in data]
if bad:
    sys.exit("产物里仍含构建机路径(%d 处模式命中): %s" % (len(bad), ", ".join(e for _, e in bad)))
PY

echo "== 5/5 写来源声明并打包"
{
  echo "package:      $NAME"
  echo "version:      $TAG"
  echo "upstream:     $UPSTREAM_URL"
  echo "upstream tag: $TAG"
  echo "commit:       $COMMIT"
  echo "target:       $RID (iSH arm64 guest, Alpine/musl), self-contained single file, ReadyToRun"
  echo "license:      Apache-2.0 (upstream: iOfficeAI/OfficeCLI); see LICENSE, NOTICE, THIRD-PARTY-NOTICES.txt"
  echo "built:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "toolchain:    .NET SDK $("$DOTNET" --version)"
  echo "build flags:  -c Release -r $RID -p:PublishReadyToRun=true (upstream publishes without ReadyToRun)"
  echo
  if [ ${#PATCHES[@]} -eq 0 ]; then
    echo "modifications: NONE in source. Built from the unmodified upstream source at the tag above, with ReadyToRun enabled."
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
