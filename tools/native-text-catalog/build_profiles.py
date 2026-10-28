"""Reduce existing GPL address facts to the native named-text import inputs."""
# Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md (generator only).
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path, help="Directory containing the five existing address fact files")
parser.add_argument("destination", type=Path, help="Native text-label profile directory")
args = parser.parse_args()
assignment = re.compile(r'(?:([A-Za-z_]\w*)|\["((?:[^"\\]|\\.)*)"\])\s*=\s*(\d+),')
named = re.compile(r'^[gs]Text_|^gOtherText_|^BattleText_|^BattleStatText_|_Text_|^Text_|Names\[')
args.destination.mkdir(parents=True, exist_ok=True)
for edition in ("firered", "leafgreen", "emerald", "ruby", "sapphire"):
    source = args.source / (edition + ".lua")
    rows = {}
    for line in source.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("--") or line in ("return {", "}"):
            continue
        match = assignment.fullmatch(line)
        if not match:
            raise ValueError(f"Unsupported address fact syntax in {edition}: {line[:80]}")
        label = match[1] or json.loads('"' + match[2] + '"')
        if named.search(label):
            assert label.isascii(), "Unexpected non-ASCII symbol name"
            assert label not in rows, "Duplicate address symbol"
            rows[label] = int(match[3])
    header = [
        "-- Address metadata from Gen1Recomp (GPL-3.0); no cartridge payload.",
        "-- Reduced to named text facts by tools/native-text-catalog/build_profiles.py.",
        "-- Source: Roxas2712/Gen2Recomped @ 2d1d0e85,",
        "-- src/translation/rompack/addresses/" + edition + ".lua. Existing rights remain intact.",
        "return {",
    ]
    body = [f"  [{json.dumps(label)}] = {offset}," for label, offset in sorted(rows.items())]
    (args.destination / (edition + ".lua")).write_text("\n".join(header + body + ["}", ""]))
    print(edition, len(rows))
