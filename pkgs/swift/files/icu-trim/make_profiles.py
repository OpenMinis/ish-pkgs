"""Build reduced ICU data packages (profiles) from the full swift-foundation-icu data.

small: root + en + zh locale data, zh collation, transliteration, GB18030/GBK/Big5 converters;
       no word-break dictionaries (Foundation on Linux has no by-word enumeration anyway)
tiny : root + en locale data only; no converters, dictionaries, transliteration or stringprep
"""
import re
import sys
from pathlib import Path

try:
    from tqdm import tqdm
except ImportError:  # progress bars are optional
    def tqdm(iterable, **_kwargs):
        return iterable

import icudat

LOCALE = re.compile(r"^([a-z]{2,3})(_[A-Za-z0-9_]+)?$")
PROFILES = {
    "small": dict(langs={"en", "zh"}, dicts=set(), translit=True, spp=True,
                  cnv=("gb18030", "windows-936-", "windows-950-")),
    "tiny": dict(langs={"en"}, dicts=set(), translit=False, spp=False, cnv=()),
}


def keep(name: str, p: dict) -> bool:
    parts = name.split("/")[1:]
    tree = parts[0] if len(parts) == 2 else ""
    stem, _, ext = parts[-1].rpartition(".")
    if ext == "cnv":
        return stem.startswith(p["cnv"]) if p["cnv"] else False
    if ext == "dict":
        return stem in p["dicts"]
    if ext == "spp" or ext == "cfu":
        return p["spp"]
    if tree == "translit":
        return p["translit"]
    if ext != "res":
        return True
    m = LOCALE.match(stem)
    if not m:
        return True
    return m.group(1) in p["langs"]


def main() -> None:
    src, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    header, items = icudat.parse(src.read_bytes())
    for name, p in tqdm(PROFILES.items(), desc="✂️  profiles"):
        kept = [it for it in items if keep(it[0], p)]
        data = icudat.build(header, kept)
        _, check = icudat.parse(data)
        assert [n for n, _ in check] == sorted((n for n, _ in kept), key=str.encode)
        assert all(a[1][:len(b[1])] == b[1] for a, b in zip(check, sorted(kept, key=lambda it: it[0].encode())))
        (out_dir / f"icudt-{name}.dat").write_bytes(data)
        print(f"✅ {name}: {len(kept)}/{len(items)} items, {len(data)} bytes")


if __name__ == "__main__":
    main()
