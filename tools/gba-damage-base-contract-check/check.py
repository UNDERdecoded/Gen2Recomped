#!/usr/bin/env python3
"""Compare ordinary GBA damage through both actual engine calculators, without ROMs."""
import argparse
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
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    source, host = args.gen1.resolve(), args.gen2.resolve()
    if git(source, "rev-parse", "HEAD") != REFERENCE or git(source, "status", "--porcelain"):
        parser.error("reference must be clean at " + REFERENCE)
    runs, differences = [], []
    for version in ["firered", "emerald"]:
        observations = []
        for backend, engine in [("gen1", source), ("gen2", host)]:
            run = subprocess.run([args.lua, str(host / "tests/gba_damage_base/worker.lua"), str(host),
                                  backend, version], cwd=engine, capture_output=True, text=True, timeout=30)
            prefix = "GBA_DAMAGE_BASE "
            lines = [line.removeprefix(prefix) for line in run.stdout.splitlines() if line.startswith(prefix)]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            value = json.loads(lines[0])
            observations.append(value)
            runs.append({"backend": backend, "version": version, "observations": value})
        if len(observations[0]) != len(observations[1]):
            differences.append({"version": version, "error": "observation count"})
        for index, (left, right) in enumerate(zip(*observations)):
            if left != right:
                differences.append({"version": version, "row": index, "reference": left, "host": right})
        print("PASS" if observations[0] == observations[1] else "FAIL", version)
    assert not git(source, "status", "--porcelain"), "reference changed"
    report = {"reference_ref": REFERENCE, "host_ref": git(host, "rev-parse", "HEAD"),
              "host_dirty": bool(git(host, "status", "--porcelain")), "runs": runs,
              "differences": differences}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    if differences:
        raise SystemExit(f"{len(differences)} differing ordinary GBA damage observations")


if __name__ == "__main__":
    main()
