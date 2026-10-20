#!/bin/sh
# update.sh — 检查上游有没有新版本;有就告诉你,并给出重新构建的命令。
# 只读检查,不会改任何文件(改 UPSTREAM 要你自己确认后执行打印出的命令)。
#
# 用法:  ./update.sh            检查
#        ./update.sh --diff     同时列出新旧 tag 之间对"打补丁相关文件"的改动,帮你判断补丁还能不能应用
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
get() { sed -n "s/^$1=//p" "$HERE/UPSTREAM" | head -1; }
URL="$(get url)"; CUR="$(get tag)"
REPO="${URL#https://github.com/}"

command -v gh >/dev/null 2>&1 || { echo "需要 gh(GitHub CLI)" >&2; exit 1; }

LATEST="$(gh api "repos/$REPO/releases/latest" --jq .tag_name)"
PUB="$(gh api "repos/$REPO/releases/latest" --jq '.published_at[:10]')"
echo "上游:      $REPO"
echo "当前基于:  $CUR"
echo "上游最新:  $LATEST ($PUB)"

if [ "$CUR" = "$LATEST" ]; then
  echo "已是最新,无需更新。"
  exit 0
fi

echo
echo "有新版本。两个 tag 之间:"
gh api "repos/$REPO/compare/$CUR...$LATEST" --jq '"  \(.ahead_by) 个提交, \(.files | length) 个文件改动"'

# 我们的补丁会改哪些文件?新旧 tag 之间这些文件有没有变 -> 补丁可能无法直接应用
if ls "$HERE"/patches/*.patch >/dev/null 2>&1; then
  echo
  echo "我们的补丁涉及的文件,在新旧 tag 间是否被上游改动:"
  files="$(cat "$HERE"/patches/*.patch | sed -n 's/^+++ b\///p' | sort -u)"
  changed="$(gh api "repos/$REPO/compare/$CUR...$LATEST" --jq '.files[].filename')"
  hit=0
  for f in $files; do
    if echo "$changed" | grep -qx "$f"; then echo "  ⚠️  $f  (上游改了,补丁可能需要手工调整)"; hit=1; else echo "  ✅ $f  (未变)"; fi
  done
  [ $hit -eq 0 ] && echo "  补丁涉及的文件都没变,大概率可直接应用。"
else
  echo
  echo "当前没有补丁:新版本会是上游的原样编译。"
fi

echo
echo "要升级,依次执行:"
echo "  1) sed -i.bak 's/^tag=.*/tag=$LATEST/' $HERE/UPSTREAM"
echo "  2) $HERE/build.sh $LATEST"
echo "  3) 在手机上实测(至少 pair_host --help 和一次 idevice_id -l)"
echo "  4) $HERE/../../tools/publish.sh $LATEST     # 打 apk 包、更新签名索引、提交"
