#!/usr/bin/env python3
"""Compare the actual Music owner on the fork and unchanged Gen1Recomp."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

REFERENCE = "535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gen1", required=True, type=Path)
    parser.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    assert git(args.gen1, "rev-parse", "HEAD") == REFERENCE, "wrong reference commit"
    assert not git(args.gen1, "status", "--porcelain"), "reference must be unchanged"
    fixture = args.gen2.resolve() / "tests/engine/music_map_owner.lua"
    results = {}
    for name, engine in (("gen1", args.gen1), ("gen2", args.gen2)):
        run = subprocess.run([args.lua, str(fixture)], cwd=engine,
                             capture_output=True, text=True, timeout=60, check=True)
        rows = [line.removeprefix("MUSIC_MAP_OWNER ") for line in run.stdout.splitlines()
                if line.startswith("MUSIC_MAP_OWNER ")]
        assert len(rows) == 1, f"missing result from {name}"
        results[name] = json.loads(rows[0])
    assert results["gen1"] == results["gen2"], "native music owner results differ"
    report = {"referenceCommit": REFERENCE,
              "hostCommit": git(args.gen2, "rev-parse", "HEAD"),
              "hostTrackedChanges": bool(git(args.gen2, "status", "--porcelain", "--untracked-files=no")),
              "fixtureSha256": hashlib.sha256(fixture.read_bytes()).hexdigest(),
              "results": results}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS: {results['gen2']['assertions']} actual-owner checks on each engine; eight games agree")


if __name__ == "__main__":
    main()
