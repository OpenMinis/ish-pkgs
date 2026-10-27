#!/bin/sh
# publish.sh — 把 build.sh 产出的 zip 变成 apk 仓库内容(aarch64/*.apk + 签名的 APKINDEX.tar.gz)
#
# 用法:  tools/publish.sh <zip 路径> <tag>
#   例:  tools/publish.sh pkgs/idevice-tools/dist/idevice-tools-ish-arm64-v0.1.68.zip v0.1.68
#        tools/publish.sh pkgs/ipatool/dist/ipatool-ish-arm64-v2.7.0.zip v2.7.0
# 私钥:  ISH_PKGS_KEY(默认 ~/.ish-pkgs/ish-pkgs.rsa),绝不进仓库
set -eu
ZIP="${1:?用法: $0 <zip> <tag>}"; TAG="${2:?}"
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(dirname "$HERE")"
KEY="${ISH_PKGS_KEY:-$HOME/.ish-pkgs/ish-pkgs.rsa}"
KEYNAME=ish-pkgs
ARCH=aarch64

case "$ZIP" in
  *ipatool*) PKG_DIR="$REPO/pkgs/ipatool" ;;
  *)         PKG_DIR="$REPO/pkgs/idevice-tools" ;;
esac

# apk 版本约定: <上游版本>-r<修订>。
# r0 = 纯上游源码原样编译(patches/ 为空);有补丁则 >= r1。我们改了补丁或重编时递增。
NPATCH=$(ls "$PKG_DIR/patches/"*.patch 2>/dev/null | wc -l | tr -d " ")
if [ "${NPATCH:-0}" -gt 0 ]; then REV=1; else REV=0; fi
VER="${TAG#v}-r${REV}"

[ -f "$KEY" ] || { echo "缺少签名私钥: $KEY" >&2; echo "生成: mkdir -p ~/.ish-pkgs && umask 077 && openssl genrsa -out $KEY 4096 && openssl rsa -in $KEY -pubout -out $REPO/$KEYNAME.rsa.pub" >&2; exit 1; }
[ -f "$REPO/$KEYNAME.rsa.pub" ] || { echo "缺少公钥 $REPO/$KEYNAME.rsa.pub" >&2; exit 1; }
# 公钥必须与私钥配对,否则发布出去谁都验证不了
[ "$(openssl rsa -in "$KEY" -pubout 2>/dev/null | sha256sum | cut -d' ' -f1)" = "$(sha256sum < "$REPO/$KEYNAME.rsa.pub" | cut -d' ' -f1)" ] \
  || { echo "私钥与仓库里的公钥不配对,停止" >&2; exit 1; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
unzip -q "$ZIP" -d "$T/x"
PROV="$T/x/PROVENANCE.txt"
MOD="$(sed -n 's/^modifications: *//p' "$PROV" | head -1 | cut -c1-60)"
OUT="$REPO/$ARCH"; mkdir -p "$OUT"

mk() {  # mk <包名> <描述> <依赖(逗号分隔,可空)> <文件...>
  name="$1"; desc="$2"; deps="$3"; shift 3
  root="$T/root-$name"; mkdir -p "$root/usr/local/bin" "$root/usr/share/doc/$name"
  for f in "$@"; do install -m755 "$T/x/$f" "$root/usr/local/bin/$f"; done
  cp "$PROV" "$root/usr/share/doc/$name/PROVENANCE.txt"
  if [ -f "$PKG_DIR/LICENSE.upstream" ]; then
    cp "$PKG_DIR/LICENSE.upstream" "$root/usr/share/doc/$name/LICENSE"
  fi
  rm -f "$OUT/$name-"*.apk
  python3 "$HERE/mkapk.py" "$root" "$name" "$VER" "$ARCH" "$desc" MIT "$OUT/$name-$VER.apk" "$deps" >/dev/null
  echo "  $name-$VER.apk ($(wc -c < "$OUT/$name-$VER.apk") 字节)"
}

echo "== 打包 ($TAG, $MOD)"
case "$ZIP" in
  *ipatool*)
    mk ipatool "Command-line tool to search and download App Store IPAs (adapted for iSH arm64)" "" ipatool
    ;;
  *)
    mk pair-host     "idevice pair_host $TAG for iSH arm64: iOS 27 host-side pairing"                 ""          pair_host
    mk idevice-tools "idevice tools $TAG for iSH arm64 (upstream: jkcoxson/idevice); needs pair-host" "pair-host"  idevice-tools idevice_id iproxy pair_apple_tv
    ;;
esac

echo "== 签名索引"
python3 "$HERE/mkrepo.py" "$REPO" "$ARCH" "$KEY" "$KEYNAME" | tail -1
echo
echo "== 发布前隐私扫描(只扫我们自己写的文本: 脚本/README/配置;不扫 .apk 与上游二进制)"
sh "$HERE/scan-sensitive.sh" --own-text "$REPO" || { echo "扫描未通过,请勿提交" >&2; exit 1; }

echo
echo "完成。检查后提交:  git -C $REPO add -A && git -C $REPO commit -m \"package $TAG\""
