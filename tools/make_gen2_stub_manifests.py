#!/usr/bin/env python3
"""Write Phase 2 stub manifests for Pokemon Gold/Silver from ROM files.

These stubs lock canonical SHA-1 values and version ids so the project can
track Gen2 targets before the full metadata extractor is implemented.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os


def sha1_file(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def write_stub(out_path, version, rom_sha1):
    data = {
        "format": 3,
        "generation": 2,
        "notes": (
            "Phase 2 stub manifest. Replace with real "
            f"{version.capitalize()} metadata before running "
            "build_rom_data.py for Gen2."
        ),
        "romSha1": rom_sha1,
        "stub": True,
        "version": version,
    }
    with open(out_path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gold-rom", required=True)
    parser.add_argument("--silver-rom", required=True)
    parser.add_argument("--out-dir", default=os.path.dirname(__file__))
    args = parser.parse_args()

    out_dir = os.path.abspath(args.out_dir)
    os.makedirs(out_dir, exist_ok=True)

    gold_sha1 = sha1_file(os.path.abspath(args.gold_rom))
    silver_sha1 = sha1_file(os.path.abspath(args.silver_rom))

    gold_manifest = os.path.join(out_dir, "rom_manifest_gold.json")
    silver_manifest = os.path.join(out_dir, "rom_manifest_silver.json")

    write_stub(gold_manifest, "gold", gold_sha1)
    write_stub(silver_manifest, "silver", silver_sha1)

    print(f"wrote {gold_manifest} ({gold_sha1})")
    print(f"wrote {silver_manifest} ({silver_sha1})")


if __name__ == "__main__":
    main()
