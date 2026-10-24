#!/usr/bin/env python3
"""Compare native importer results using synthetic cartridge bytes, no ROM assets."""
import argparse
import json
import os
from pathlib import Path
import subprocess

REFERENCE = "535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--gen1", type=Path, required=True)
    p.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    p.add_argument("--report", type=Path)
    a = p.parse_args()
    source, host = a.gen1.resolve(), a.gen2.resolve()
    if git(source, "rev-parse", "HEAD") != REFERENCE or git(source, "status", "--porcelain"):
        p.error("reference must be clean at " + REFERENCE)
    runs, count = [], 0
    for kind, version in [("gen2", "gold"), ("gba", "firered"), ("gba", "emerald")]:
        observations = []
        for backend, engine in [("gen1", source), ("gen2", host)]:
            run = subprocess.run([a.lua, str(host / "tests/trainer_ai_metadata/worker.lua"), str(host),
                                  backend, kind, version], cwd=engine,
                                 capture_output=True, text=True, timeout=60)
            lines = [l.removeprefix("TRAINER_AI_METADATA ") for l in run.stdout.splitlines()
                     if l.startswith("TRAINER_AI_METADATA ")]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            value = json.loads(lines[0]); observations.append(value)
            runs.append({"backend": backend, "kind": kind, "version": version, "observations": value})
        if observations[0] != observations[1]:
            for i, (left, right) in enumerate(zip(*observations)):
                if left != right:
                    raise AssertionError(f"{version}/{i}: reference={left!r}, host={right!r}")
            raise AssertionError(f"{version}: different observation counts")
        count += len(observations[0])
        print(f"PASS {version}: {len(observations[0])} matching native metadata records")
    assert not git(source, "status", "--porcelain"), "reference changed"
    if a.report:
        a.report.write_text(json.dumps({"reference_ref": REFERENCE,
            "host_ref": git(host, "rev-parse", "HEAD"), "host_dirty": bool(git(host, "status", "--porcelain")),
            "paired_records": count, "runs": runs}, indent=2) + "\n")


if __name__ == "__main__":
    main()
