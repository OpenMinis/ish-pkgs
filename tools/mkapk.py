#!/usr/bin/env python3
"""mkapk.py — 不依赖 abuild,用纯 Python 构造一个 apk 2.x 能安装的 .apk。

格式(从官方包拆出来的):
  .apk = [可选签名段] + 控制段(.PKGINFO) + 数据段,三段 gzip 串联
  - 数据段每个文件前有一个 PAX 头,携带  APK-TOOLS.checksum.SHA1=<文件内容 sha1 的 hex>
  - 控制段 .PKGINFO 里 datahash = 数据段"压缩后字节"的 sha256
"""
import gzip, hashlib, io, os, sys, tarfile, time


def _tar_bytes(entries):
    """entries: [(tarinfo, bytes|None)]  -> 未压缩的 tar 字节(PAX 格式)"""
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.PAX_FORMAT) as t:
        for ti, data in entries:
            t.addfile(ti, io.BytesIO(data) if data is not None else None)
    raw = buf.getvalue()
    # 去掉 tarfile 末尾的两个全零块(apk 的段不以 EOF 块结尾,控制段尤其如此)
    end = len(raw)
    while end >= 512 and raw[end - 512:end] == b"\0" * 512:
        end -= 512
    return raw[:end]


def build(root, name, ver, arch, desc, license_, out, url="", origin=None, depends=()):
    # ---- 数据段:遍历 root 目录
    entries = []
    size = 0
    for dp, dns, fns in os.walk(root):
        dns.sort()
        rel = os.path.relpath(dp, root)
        if rel != ".":
            ti = tarfile.TarInfo(rel.replace(os.sep, "/"))
            ti.type = tarfile.DIRTYPE
            ti.mode = 0o755
            ti.mtime = 0
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = "root"
            entries.append((ti, None))
        for fn in sorted(fns):
            p = os.path.join(dp, fn)
            data = open(p, "rb").read()
            ti = tarfile.TarInfo(os.path.relpath(p, root).replace(os.sep, "/"))
            ti.size = len(data)
            ti.mode = os.stat(p).st_mode & 0o7777
            ti.mtime = 0
            ti.uid = ti.gid = 0
            ti.uname = ti.gname = "root"
            ti.pax_headers = {"APK-TOOLS.checksum.SHA1": hashlib.sha1(data).hexdigest()}
            entries.append((ti, data))
            size += len(data)
    data_tar = _tar_bytes(entries)
    data_gz = gzip.compress(data_tar, 9, mtime=0)
    datahash = hashlib.sha256(data_gz).hexdigest()

    # ---- 控制段
    info = "\n".join([
        f"pkgname = {name}", f"pkgver = {ver}", f"pkgdesc = {desc}", f"url = {url}",
        f"builddate = {int(time.time())}", "packager = ish-pkgs", f"size = {size}",
        f"arch = {arch}", f"origin = {origin or name}", f"license = {license_}",
        *[f"depend = {d}" for d in depends],
        f"datahash = {datahash}", ""]).encode()
    ti = tarfile.TarInfo(".PKGINFO")
    ti.size = len(info)
    ti.mode = 0o644
    ti.mtime = 0
    ctrl_tar = _tar_bytes([(ti, info)])
    ctrl_gz = gzip.compress(ctrl_tar, 9, mtime=0)

    with open(out, "wb") as f:
        f.write(ctrl_gz + data_gz)     # 无签名段
    return datahash


if __name__ == "__main__":
    root, name, ver, arch, desc, lic, out = sys.argv[1:8]
    deps = sys.argv[8].split(",") if len(sys.argv) > 8 and sys.argv[8] else []
    print(build(root, name, ver, arch, desc, lic, out, depends=deps))
