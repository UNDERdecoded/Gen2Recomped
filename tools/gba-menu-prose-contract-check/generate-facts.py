#!/usr/bin/env python3
"""Record native public label/table metadata without copying cartridge prose."""
import argparse
import json
import os
from pathlib import Path
import subprocess

from check import REFERENCE, git

ROOT = Path(__file__).resolve().parents[2]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--gen1", type=Path, required=True)
    p.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    p.add_argument("--check", action="store_true")
    a = p.parse_args()
    source = a.gen1.resolve()
    if git(source, "rev-parse", "HEAD") != REFERENCE or git(source, "status", "--porcelain"):
        p.error("Gen1 must be clean at " + REFERENCE)
    facts = {"reference_ref": REFERENCE, "profiles": {}}
    for version in ["firered", "emerald"]:
        run = subprocess.run([a.lua, str(ROOT / "tools/gba-menu-prose-contract-check/export-facts.lua"), version],
                             cwd=source, text=True, capture_output=True, timeout=30)
        lines = [s.removeprefix("GBA_MENU_FACTS ") for s in run.stdout.splitlines() if s.startswith("GBA_MENU_FACTS ")]
        if run.returncode or len(lines) != 1:
            raise RuntimeError(run.stdout + run.stderr)
        facts["profiles"][version] = json.loads(lines[0])
    assert not git(source, "status", "--porcelain"), "reference changed"
    content = json.dumps(facts, sort_keys=True, indent=2) + "\n"
    path = ROOT / "tests/gba_menu_prose/label-facts.json"
    if a.check:
        assert path.read_text() == content, "stale native menu label facts"
    else:
        path.write_text(content)
    print("PASS pinned native menu label/table provenance")


if __name__ == "__main__":
    main()
