#!/usr/bin/env python3
"""Compare complete held-effect command reads and calculated damage, without ROMs."""
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
    parser.add_argument("--gen1", type=Path, required=True)
    parser.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    source, host = args.gen1.resolve(), args.gen2.resolve()
    if git(source, "rev-parse", "HEAD") != REFERENCE or git(source, "status", "--porcelain"):
        parser.error("reference must be clean at " + REFERENCE)
    paths = [host / "tests/held_item" / name for name in ("fixture.lua", "damage.lua", "damage_worker.lua")]
    report = {"reference_ref": REFERENCE, "host_ref": git(host, "rev-parse", "HEAD"),
              "host_dirty": bool(git(host, "status", "--porcelain")), "runs": [], "differences": [],
              "fixture_sha256": {str(p.relative_to(host)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in paths}}
    failed = False
    for version in ("firered", "emerald"):
        observations = []
        for backend, engine in (("gen1", source), ("gen2", host)):
            run = subprocess.run([args.lua, str(host / "tests/held_item/damage_worker.lua"), str(host),
                                  backend, version], cwd=engine, capture_output=True, text=True, timeout=60)
            lines = [line.removeprefix("HELD_DAMAGE ") for line in run.stdout.splitlines()
                     if line.startswith("HELD_DAMAGE ")]
            value = json.loads(lines[0]) if len(lines) == 1 else None
            failed |= run.returncode != 0 or value is None
            observations.append(value)
            report["runs"].append({"backend": backend, "version": version, "exit": run.returncode,
                                   "stdout": run.stdout, "stderr": run.stderr, "observations": value})
        if all(value is not None for value in observations):
            left, right = observations
            if len(left) != len(right):
                report["differences"].append({"version": version, "error": "row count"})
            for index, (reference, host_value) in enumerate(zip(left, right)):
                if reference != host_value:
                    report["differences"].append({"version": version, "row": index,
                                                   "reference": reference, "host": host_value})
        equal = observations[0] is not None and observations[0] == observations[1]
        failed |= not equal
        print("PASS" if equal else "FAIL", version)
    if git(source, "status", "--porcelain"):
        raise RuntimeError("reference changed")
    report["passed"] = not failed
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
