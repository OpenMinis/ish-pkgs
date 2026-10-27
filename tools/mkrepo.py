#!/usr/bin/env python3
"""mkrepo.py — 纯 Python + openssl 生成"带签名的 apk 仓库"(不依赖 abuild)

目录约定(apk 的 -X 指向 <repo>):
  <repo>/aarch64/APKINDEX.tar.gz      签名索引
  <repo>/aarch64/<name>-<ver>.apk     包(包本身不签名,由签名索引里的 C: 校验和兜底)
  <repo>/<keyname>.rsa.pub            公钥,用户放进 /etc/apk/keys/

签名格式(从官方索引拆出来并用官方公钥验证过):
  APKINDEX.tar.gz = [签名段 gzip] + [索引段 gzip]
  签名段是一个 tar,里面只有一个文件 `.SIGN.RSA.<公钥文件名>`,
  内容 = RSA( SHA1( 索引段"压缩后字节" ) )
"""
import glob, gzip, hashlib, io, os, subprocess, sys, tarfile, tempfile, zlib


def sign(data: bytes, privkey: str) -> bytes:
    with tempfile.NamedTemporaryFile() as f:
        f.write(data); f.flush()
        r = subprocess.run(["openssl", "dgst", "-sha1", "-sign", privkey, f.name], capture_output=True)
    if r.returncode:
        raise SystemExit("openssl 签名失败: " + r.stderr.decode())
    return r.stdout


def _targz_no_eof(entries):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as t:
        for name, data in entries:
            ti = tarfile.TarInfo(name); ti.size = len(data); ti.mode = 0o644; ti.mtime = 0
            ti.uid = ti.gid = 0; ti.uname = ti.gname = "root"
            t.addfile(ti, io.BytesIO(data))
    raw = buf.getvalue()
    end = len(raw)
    while end >= 512 and raw[end - 512:end] == b"\0" * 512:
        end -= 512                     # 签名段不带 EOF 块(与官方一致)
    return raw[:end]


def pkginfo_of(apk_path):
    """读 .apk 的控制段,返回 (dict, 控制段压缩后字节)。"""
    b = open(apk_path, "rb").read()
    pos = 0; segs = []
    while pos < len(b):
        d = zlib.decompressobj(31)
        out = d.decompress(b[pos:])
        used = len(b[pos:]) - len(d.unused_data)
        segs.append((b[pos:pos + used], out)); pos += used
    ctrl_raw, ctrl = segs[0] if not segs[0][1].startswith(b".SIGN") else segs[1]
    t = tarfile.open(fileobj=io.BytesIO(ctrl))
    info = t.extractfile(".PKGINFO").read().decode()
    kv = {}
    for line in info.splitlines():
        if " = " in line:
            k, v = line.split(" = ", 1)
            if k == "depend":
                kv.setdefault("depend", []).append(v)    # depend 可重复出现
            else:
                kv[k] = v
    return kv, ctrl_raw


def index_text(apks):
    """生成 APKINDEX 文本。C: = 'Q1' + base64( SHA1(控制段压缩后字节) )"""
    import base64
    out = []
    for p in apks:
        kv, ctrl_raw = pkginfo_of(p)
        c = "Q1" + base64.b64encode(hashlib.sha1(ctrl_raw).digest()).decode()
        out.append("\n".join([
            f"C:{c}", f"P:{kv['pkgname']}", f"V:{kv['pkgver']}", f"A:{kv['arch']}",
            f"S:{os.path.getsize(p)}", f"I:{kv.get('size', '0')}", f"T:{kv.get('pkgdesc', '')}",
            f"U:{kv.get('url', '')}", f"L:{kv.get('license', '')}", f"o:{kv.get('origin', kv['pkgname'])}",
            f"t:{kv.get('builddate', '0')}",
            *([f"D:{' '.join(kv['depend'])}"] if kv.get("depend") else []), ""]))
    return ("\n".join(out) + "\n").encode()


def build_index(repo, arch, privkey, keyname):
    d = os.path.join(repo, arch)
    apks = sorted(glob.glob(os.path.join(d, "*.apk")))
    if not apks:
        raise SystemExit("没有 .apk: " + d)
    desc = b"ish-pkgs repository"
    idx_tar = _targz_no_eof([("DESCRIPTION", desc), ("APKINDEX", index_text(apks))])
    idx_gz = gzip.compress(idx_tar, 9, mtime=0)
    sig = sign(idx_gz, privkey)
    sig_gz = gzip.compress(_targz_no_eof([(f".SIGN.RSA.{keyname}.rsa.pub", sig)]), 9, mtime=0)
    out = os.path.join(d, "APKINDEX.tar.gz")
    open(out, "wb").write(sig_gz + idx_gz)
    return out, [os.path.basename(a) for a in apks]


if __name__ == "__main__":
    repo, arch, privkey, keyname = sys.argv[1:5]
    print(build_index(repo, arch, privkey, keyname))
