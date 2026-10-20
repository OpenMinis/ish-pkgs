#!/bin/zsh
# build.sh — 交叉编译 idevice-tools 到 aarch64-linux-musl(给 iSH 用),产物结构对齐上游 CI。
#
# 用法:  ./build.sh <上游 tag,如 v0.1.68> [输出目录]
# 在哪跑: macOS(已装 rustup + zig),或任何装了 rustup + zig 的 Linux。
#         iSH 里的 cargo 太老(edition 2024 需要 ≥1.85),编不了,所以要在别处交叉编译。
#
# 产物(与上游 Release 对齐):
#   <输出目录>/idevice-tools-ish-arm64-<tag>.zip     平铺的可执行文件 + PROVENANCE.txt
#   <输出目录>/idevice-tools-ish-arm64-<tag>/        解开后的同样内容(给 mkapk 用)
#   <输出目录>/SHA256SUMS
set -eu

TAG="${1:?用法: $0 <上游 tag,如 v0.1.68> [输出目录]}"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${2:-$HERE/dist}"
UPSTREAM_URL="$(sed -n 's/^url=//p' "$HERE/UPSTREAM")"
TARGET=aarch64-unknown-linux-musl          # Rust 目标
ZIG_TARGET=aarch64-linux-musl              # zig 自己的写法,和 Rust 的不一样
NAME="idevice-tools-ish-arm64"             # 上游是 idevice-tools-linux / -macos-arm 等,这里沿用同一前缀
WORK="${WORK:-${TMPDIR:-/tmp}/ish-pkgs-build}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "缺少 $1: $2" >&2; exit 1; }; }
need cargo "安装 rustup: https://rustup.rs"
need rustup "安装 rustup: https://rustup.rs"
need zig   "macOS: brew install zig"
need git   "安装 git"
need zip   "安装 zip"
need file  "安装 file"
need strings "安装 binutils / Xcode 命令行工具"

echo "== 1/6 准备 Rust 目标"
rustup target add "$TARGET" >/dev/null

echo "== 2/6 取上游源码 $UPSTREAM_URL @ $TAG"
# 每次都从干净状态开始:复用旧的 target/ 会把"旧编译参数"编出的 .o 混进来
# (实测:改了 C 编译参数后复用缓存,aws-lc 的旧 .o 仍带 UBSan 引用,链接时 undefined symbol)。
# 可复现构建不能依赖缓存。要加速调试可设 KEEP_TARGET=1(仅限本地调试,发布必须干净)。
if [ "${KEEP_TARGET:-0}" != "1" ]; then rm -rf "$WORK/target" "$WORK/cargo-home"; fi
rm -rf "$WORK/src" && mkdir -p "$WORK"
git clone --quiet --depth 1 --branch "$TAG" "$UPSTREAM_URL" "$WORK/src"
COMMIT="$(git -C "$WORK/src" rev-parse HEAD)"
echo "   提交: $COMMIT"

echo "== 3/6 应用补丁(patches/ 里的 *.patch,按文件名顺序)"
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

echo "== 4/6 交叉编译(zig cc 当 C 编译器和链接器)"
ZC="$WORK/zigcc"; mkdir -p "$ZC"
# 包装器:cc-rs 会传 Rust 风格的 --target=…,zig 不认,要丢掉;统一用 zig 自己的目标名
# -fno-sanitize=undefined: zig cc 默认给 C 代码开 UBSan,它会把源文件绝对路径编进 .rodata(泄漏用户名),
#   而且让 aws-lc 等 C 代码更大更慢;上游用普通 cc 编译,本来就没有。关掉它再配合 prefix-map 才能彻底干净。
cat > "$ZC/cc" <<EOF
#!/bin/sh
args=""
for a in "\$@"; do
  case "\$a" in
    --target=*|-target=*) ;;
    *) args="\$args '\$(printf %s "\$a" | sed "s/'/'\\\\\\\\''/g")'" ;;
  esac
done
eval exec zig cc -target $ZIG_TARGET -fno-sanitize=undefined -ffile-prefix-map=$HOME=/home/builder -ffile-prefix-map=$WORK=/build -fdebug-prefix-map=$HOME=/home/builder -fmacro-prefix-map=$HOME=/home/builder \$args
EOF
printf '#!/bin/sh\nexec zig ar "$@"\n' > "$ZC/ar"
chmod +x "$ZC/cc" "$ZC/ar"
export CC_aarch64_unknown_linux_musl="$ZC/cc"
export AR_aarch64_unknown_linux_musl="$ZC/ar"
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_MUSL_LINKER="$ZC/cc"
export CARGO_TARGET_DIR="$WORK/target"
# 不用 Rust 自带的 musl 启动文件,全交给 zig,否则符号重复
# 另外把构建机路径抹掉:Rust 会把每个依赖的源文件绝对路径(含 $HOME 用户名)编进 panic 信息,
# 公开发布前必须替换成中性前缀,同时也让产物与构建机路径无关(更可复现)
# 根因处理:crate 源码路径形如 $CARGO_HOME/registry/src/…,若 CARGO_HOME 在家目录下就会带上用户名。
# 所以构建用一个中性路径的 CARGO_HOME(依赖会重新下载,首次多约 1 分钟)。
# rustup 工具链仍用原来的(只读),不会进产物。
export CARGO_HOME="$WORK/cargo-home"
mkdir -p "$CARGO_HOME"
CARGO_HOME_DIR="$CARGO_HOME"
RUSTUP_HOME_DIR="${RUSTUP_HOME:-$HOME/.rustup}"
export RUSTFLAGS="-C link-self-contained=no \
  --remap-path-prefix=$CARGO_HOME_DIR=/cargo \
  --remap-path-prefix=$RUSTUP_HOME_DIR=/rustup \
  --remap-path-prefix=$WORK/src=/src \
  --remap-path-prefix=$WORK=/build \
  --remap-path-prefix=$HOME=/home/builder"
( cd "$WORK/src/tools" && cargo build --release --target "$TARGET" )

echo "== 5/6 筛选可执行文件(上游 CI 的同一条规则:只拷 ELF 可执行文件,平铺)"
STAGE="$OUT/$NAME-$TAG"
rm -rf "$STAGE" && mkdir -p "$STAGE"
find "$WORK/target/$TARGET/release" -maxdepth 1 -type f -exec sh -c '
  for f in "$@"; do
    if file "$f" | grep -Eq "ELF .* executable"; then cp "$f" "$0/"; fi
  done
' "$STAGE" {} +
ls "$STAGE"/* >/dev/null 2>&1 || { echo "没有产出任何可执行文件" >&2; exit 1; }

# 验证:构建机路径/用户名不能出现在产物里(公开发布的硬性要求)
for f in "$STAGE"/*; do
  if strings -a "$f" | grep -qF -e "$HOME" -e "/Users/$(id -un)" -e "/private/var/folders"; then
    echo "产物里仍含构建机路径: $f" >&2
    strings -a "$f" | grep -F -e "$HOME" -e "/Users/$(id -un)" -e "/private/var/folders" | head -3 >&2
    exit 1
  fi
done

# 说明: 这里不再对二进制做"邮箱/个人信息"通用扫描 —— 二进制里的第三方署名(上游依赖的版权声明、
# 根证书联系人等)属于上游内容,不是我们的隐私。上面的"构建机路径"检查只针对我们自己的构建环境。
# 我们自己写的脚本/文档/笔记是否含隐私,由 tools/scan-sensitive.sh 在发布时检查(见 publish.sh)。

# 验证:架构与静态链接(iSH 是 Alpine aarch64,没有 glibc)
for f in "$STAGE"/*; do
  info="$(file "$f")"
  echo "$info" | grep -q 'ARM aarch64' || { echo "架构不对: $info" >&2; exit 1; }
  echo "$info" | grep -Eq 'statically linked|static-pie linked' || { echo "不是静态链接: $info" >&2; exit 1; }
done

echo "== 6/6 写来源声明并打包"
{
  echo "package:      $NAME"
  echo "version:      $TAG"
  echo "upstream:     $UPSTREAM_URL"
  echo "upstream tag: $TAG"
  echo "commit:       $COMMIT"
  echo "target:       $TARGET (iSH arm64 guest, Alpine/musl, static)"
  echo "license:      MIT (upstream: idevice-tools)"
  echo "built:        $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "toolchain:    $(rustc --version) | zig $(zig version)"
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
  ( cd "$STAGE" && for f in *; do echo "  $(shasum -a 256 "$f" | cut -d' ' -f1)  $f"; done )
} > "$STAGE/PROVENANCE.txt"

rm -f "$OUT/$NAME-$TAG.zip"
( cd "$STAGE" && zip -q -r "$OUT/$NAME-$TAG.zip" . )     # 与上游一致:zip 内平铺,无子目录
( cd "$OUT" && shasum -a 256 "$NAME-$TAG.zip" > SHA256SUMS )

echo
echo "完成:"
ls -la "$OUT/$NAME-$TAG.zip" | awk '{print "  ",$5,$9}'
echo "来源声明:"; sed -n '1,/^files/p' "$STAGE/PROVENANCE.txt" | sed 's/^/  /'
