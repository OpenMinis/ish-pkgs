"""Extract the embedded ICU common data (.dat) from swift-foundation-icu's chunked .inc.h files."""
import re
import sys
from pathlib import Path

try:
    from tqdm import tqdm
except ImportError:  # progress bars are optional
    def tqdm(iterable, **_kwargs):
        return iterable

src = Path(sys.argv[1])
out = Path(sys.argv[2])
buf = bytearray()
for i in tqdm(range(4), desc="📦 chunks"):
    text = (src / f"icu_packaged_main_data.{i}.inc.h").read_text()
    body = text[text.index("__ICU_PACKAGED_MAIN_DATA_CHUNK_"):]
    buf += bytes(int(x, 16) for x in re.findall(r"0x([0-9a-fA-F]{1,2})", body))
out.write_bytes(buf)
print(f"✅ wrote {out} ({len(buf)} bytes)")
