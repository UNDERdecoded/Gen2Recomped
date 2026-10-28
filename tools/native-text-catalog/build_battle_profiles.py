"""Regenerate numeric battle interface facts from pinned primary sources.

Only names/numeric values are emitted, never C programs or cartridge prose.
The RS pointer count is the actual BATTLESTRINGS_NO in battle_message.c;
its public header also declares later IDs absent from that cartridge table.
"""
from pathlib import Path
import json
import re
import urllib.request

PROFILES = [
    ("frlg", "pokefirered", "ce6406d8c2eaf46d543c8a2606de0c3cb1951982", 374),
    ("emerald", "pokeemerald", "731ad5bfd6e6f265508d0efcca0ba42f9dcf5881", 369),
    ("rs", "pokeruby", "5784633ce4ef7ade1a7f2d2d0c288e3d5e6cdd7f", 351),
]


def build(destination):
    destination.mkdir(parents=True, exist_ok=True)
    for family, repo, revision, count in PROFILES:
        def read(path):
            url = f"https://raw.githubusercontent.com/pret/{repo}/{revision}/{path}"
            with urllib.request.urlopen(url, timeout=30) as response:
                return response.read().decode()

        path = "include/battle_string_ids.h" if family == "rs" else "include/constants/battle_string_ids.h"
        ids = {name: int(number) for name, number in re.findall(
            r"^#define\s+(STRINGID_\w+)\s+(\d+)\b", read(path), re.M)}
        if family == "rs":
            placeholders = {int(number, 16): "B_" + name for name, number in re.findall(
                r"^#define\s+B_TXT_(\w+)\s+0x([0-9A-Fa-f]+)\b", read("include/battle_message.h"), re.M)}
            assert re.search(r"#define\s+BATTLESTRINGS_NO\s+351\b", read("src/battle_message.c"))
        else:
            placeholders = {int(number, 16): name for name, number in re.findall(
                r"^(B_\w+)\s*=\s*FD\s+([0-9A-Fa-f]+)\b", read("charmap.txt"), re.M)}
            assert max(ids.values()) + 1 == count + 12
        out = (f"-- Cartridge interface facts from pret/{repo} @ {revision}.\n"
               "-- Numeric identifiers only; no program or cartridge text payload.\n"
               f"return {{first=12,count={count},ids={{\n")
        out += "".join(f" [{json.dumps(name)}]={value},\n" for name, value in sorted(ids.items()))
        out += "},placeholders={\n"
        out += "".join(f" [{code}]={json.dumps(name)},\n" for code, name in sorted(placeholders.items()))
        (destination / f"{family}.lua").write_text(out + "}}\n")


if __name__ == "__main__":
    build(Path(__file__).resolve().parents[2] / "src/import/gba/battle_text")
