"""List / subset an ICU common data package (little-endian 'CmnD' .dat)."""
import struct
from collections import defaultdict
from pathlib import Path


def parse(buf: bytes):
    header_size = struct.unpack_from("<H", buf, 0)[0]
    assert buf[2:4] == b"\xda\x27" and buf[12:16] == b"CmnD", "not an ICU common data file"
    base = header_size
    (count,) = struct.unpack_from("<I", buf, base)
    entries = [struct.unpack_from("<II", buf, base + 4 + 8 * i) for i in range(count)]
    items = []
    for i, (name_off, data_off) in enumerate(entries):
        end = buf.index(b"\0", base + name_off)
        name = buf[base + name_off:end].decode()
        nxt = entries[i + 1][1] if i + 1 < count else len(buf) - base
        items.append((name, buf[base + data_off:base + nxt]))
    return buf[:header_size], items


def build(header: bytes, items) -> bytes:
    items = sorted(items, key=lambda it: it[0].encode())
    count = len(items)
    names = b""
    name_offs = []
    toc_fixed = 4 + 8 * count
    for name, _ in items:
        name_offs.append(toc_fixed + len(names))
        names += name.encode() + b"\0"
    pos = toc_fixed + len(names)
    pos = (pos + 15) & ~15
    data_offs = []
    blob = b""
    for _, data in items:
        pad = (-len(data)) % 16
        data_offs.append(pos + len(blob))
        blob += data + b"\0" * pad
    toc = struct.pack("<I", count) + b"".join(struct.pack("<II", n, d) for n, d in zip(name_offs, data_offs))
    body = toc + names
    body += b"\0" * (pos - len(body))
    return header + body + blob


if __name__ == "__main__":
    import sys
    header, items = parse(Path(sys.argv[1]).read_bytes())
    groups = defaultdict(lambda: [0, 0])
    for name, data in items:
        parts = name.split("/")
        key = parts[1] if len(parts) > 2 else "(top) *." + name.rsplit(".", 1)[-1]
        groups[key][0] += 1
        groups[key][1] += len(data)
    print(f"📦 {len(items)} items, header {len(header)} bytes")
    for key, (n, size) in sorted(groups.items(), key=lambda kv: -kv[1][1]):
        print(f"{size:>10}  {n:>5}  {key}")
