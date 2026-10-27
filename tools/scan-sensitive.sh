#!/bin/sh
# scan-sensitive.sh — 发布前扫描"不该公开的个人/环境信息"。命中任何一项就退出码 1,发布脚本据此拦截。
#
# 用法: scan-sensitive.sh <目录或文件...>
# 同时扫文本文件、二进制(strings)、以及 .apk/.zip 里解开后的内容。
#
# 词表分两类:
#   个人词表 — 从私有文件读取(用户名、主机名、内网网段、账号域名、团队 ID 等)
#            注意: 10.7.0.1 是 LocalDevVPN/Surge 约定的公共回环地址,不是个人信息
#   通用模式 — 任何环境都不该出现的:私钥、令牌、邮箱、私有 IP、家目录路径、MAC 地址、UDID
#
# 注意: 个人词表在 ~/.ish-pkgs/private-words.txt,不在本文件里,也不要写进任何会被发布的文件。
set -u
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
OWN_TEXT=0
if [ "${1:-}" = "--own-text" ]; then OWN_TEXT=1; shift; fi
[ $# -ge 1 ] || { echo "用法: $0 [--own-text] <路径...>" >&2; exit 2; }
# --own-text: 只扫我们自己写的纯文本(脚本/README/配置/笔记),跳过二进制与 .apk/.zip。
#   二进制和上游产物里的第三方署名、证书联系人等不是我们的隐私,不在检查范围内。

# ---- 个人词表(不进仓库) ----
# 个人标识(用户名、主机名、账号域名、内网网段、团队 ID 等)不写在本文件里:
# 否则公开本脚本就等于公开了"要保护什么"的清单。它们放在 $ISH_PKGS_PRIVATE_WORDS
# (默认 ~/.ish-pkgs/private-words.txt),每行一个正则,# 开头为注释。
# 文件不存在时只做下面的通用检查,并在输出里明确提示。
WORDS_FILE="${ISH_PKGS_PRIVATE_WORDS:-$HOME/.ish-pkgs/private-words.txt}"
FIXED=""
if [ -f "$WORDS_FILE" ]; then
  FIXED="$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$WORDS_FILE")"
  PRIVATE_NOTE="已加载私有词表 ($(printf '%s\n' "$FIXED" | wc -l | tr -d ' ') 条)"
else
  PRIVATE_NOTE="⚠️ 没找到私有词表,只做了通用检查"
fi

# ---- 通用模式(ERE) ----
GENERIC='-----BEGIN [A-Z ]*PRIVATE KEY-----
ghp_[A-Za-z0-9]{20,}
github_pat_[A-Za-z0-9_]{20,}
AKIA[0-9A-Z]{16}
xox[bp]-[A-Za-z0-9-]{10,}
[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,}
\b(10\.[0-9]{1,3}|192\.168|172\.(1[6-9]|2[0-9]|3[01]))\.[0-9]{1,3}\.[0-9]{1,3}\b
/Users/[A-Za-z0-9._-]+
/home/[A-Za-z0-9._-]+
(^|[^0-9A-Fa-f:])([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}($|[^0-9A-Fa-f:]|:[^0-9A-Fa-f]|:$)
[0-9A-F]{8}-[0-9A-F]{16}\b'
# 例外: /home/builder 与 /Users/builder 是我们故意用来替换的中性占位,不算泄漏;
#       10.7.0.0 / 10.7.0.1 是 LocalDevVPN/Surge/SideStore 约定的公共回环地址(所有人一样),不算个人信息;
#       只放行这两个具体地址,不放行整个 10.x;
#       example.com / localhost / noreply 类邮箱域名也不算。
ALLOW='/home/builder|/Users/builder|10\.7\.0\.[01]([^0-9]|$)|@example\.(com|org)|@localhost|noreply@|@users\.noreply\.github\.com|127\.0\.0\.1|0\.0\.0\.0|02:00:00:00:00:0[01]'

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
n=0
# 把所有输入展开成"可扫描的纯文本流":文本原样、二进制 strings -a、压缩包解开递归
expand() {
  p="$1"
  if [ -d "$p" ]; then
    find "$p" \( -name .git -o -name __pycache__ \) -prune -o -type f -print | while read -r f; do expand "$f"; done
    return
  fi
  [ "$p" = "$SELF" ] && return
  if [ "$OWN_TEXT" = 1 ]; then
    case "$p" in *.apk|*.zip|*.tgz|*.gz|*.rsa.pub) return ;; esac
    grep -Iq . "$p" 2>/dev/null || return          # 非文本(二进制)一律跳过
    sed "s|^|$p:|" "$p"
    return
  fi
  case "$p" in
    *.apk|*.zip)
      d="$TMP/x$$_$(basename "$p")"; rm -rf "$d"; mkdir -p "$d"
      case "$p" in
        *.zip) unzip -q -o "$p" -d "$d" 2>/dev/null ;;
        *.apk) python3 - "$p" "$d" <<'PY'
import sys,zlib,io,tarfile,os
b=open(sys.argv[1],"rb").read(); out=sys.argv[2]; pos=0; i=0
while pos<len(b):
    d=zlib.decompressobj(31)
    try: raw=d.decompress(b[pos:])
    except Exception: break
    used=len(b[pos:])-len(d.unused_data)
    try:
        t=tarfile.open(fileobj=io.BytesIO(raw))
        for m in t.getmembers():
            if m.isfile():
                dst=os.path.join(out,"seg%d"%i,m.name.lstrip("./"))
                os.makedirs(os.path.dirname(dst),exist_ok=True)
                open(dst,"wb").write(t.extractfile(m).read())
    except Exception:
        open(os.path.join(out,"seg%d.raw"%i),"wb").write(raw)
    pos+=used; i+=1
PY
        ;;
      esac
      expand "$d"; return ;;
  esac
  # 二进制用 strings,文本直接 cat;统一前缀文件名,命中时能看到来源
  if grep -Iq . "$p" 2>/dev/null; then
    sed "s|^|$p:|" "$p"
  else
    strings -a "$p" 2>/dev/null | sed "s|^|$p(bin):|"
  fi
}

STREAM="$TMP/stream.txt"
for a in "$@"; do expand "$a"; done > "$STREAM"
echo "扫描输入: $* ($(wc -l < "$STREAM") 行可扫描文本)"
echo "$PRIVATE_NOTE"

hits=0
report() { # report <标签> <正则列表(换行分隔)> <是否忽略大小写 -i>
  label="$1"; pats="$2"; flag="$3"
  echo "$pats" | while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    m="$(grep -E $flag -e "$pat" "$STREAM" 2>/dev/null | grep -Ev -e "$ALLOW" | head -3)"
    [ -n "$m" ] && printf '%s\n' "[$label] 模式 /$pat/ 命中:" "$m" | cut -c1-200
  done
}
OUT="$(report 固定词 "$FIXED" -i; report 通用 "$GENERIC" "")"
if [ -n "$OUT" ]; then
  echo "$OUT"
  echo
  echo "❌ 发现疑似敏感信息,停止。"
  exit 1
fi
echo "✅ 未发现敏感信息"
