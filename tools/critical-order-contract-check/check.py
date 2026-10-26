#!/usr/bin/env python3
"""Compare the unchanged public critical-hit consumer through both SDKs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

REFERENCE = "535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91"
VERSIONS = ("firered", "emerald")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gen1", type=Path, required=True)
    parser.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--host-api", type=int, choices=(2, 3), default=3)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    source, host = args.gen1.resolve(), args.gen2.resolve()
    if git(source, "rev-parse", "HEAD") != REFERENCE or git(source, "status", "--porcelain"):
        parser.error("reference must be clean at " + REFERENCE)
    paths = ["examples/portable_critical_order/manifest.json", "examples/portable_critical_order/main.lua"]
    paths += ["tests/critical_order/" + name for name in ("cases.lua", "worker.lua")]
    hashes = {name: hashlib.sha256((host / name).read_bytes()).hexdigest() for name in paths}
    runs, differences = [], []
    for version in VERSIONS:
        pair = []
        for backend, engine in (("gen1", source), ("gen2", host)):
            result = subprocess.run(
                [args.lua, str(host / "tests/critical_order/worker.lua"), str(host), backend, version, str(3 if backend == "gen1" else args.host_api)],
                cwd=engine, capture_output=True, text=True, timeout=45,
            )
            lines = [line.removeprefix("CRITICAL_ORDER ") for line in result.stdout.splitlines()
                     if line.startswith("CRITICAL_ORDER ")]
            if result.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {result.stdout}{result.stderr}")
            rows = json.loads(lines[0])
            pair.append(rows)
            runs.append({"backend": backend, "version": version, "observations": rows})
        if pair[0] != pair[1]:
            differences.append({"version": version, "reference": pair[0], "host": pair[1]})
        print("FAIL" if pair[0] != pair[1] else "PASS", version)
    assert not git(source, "status", "--porcelain"), "reference changed"
    assert hashes == {name: hashlib.sha256((host / name).read_bytes()).hexdigest() for name in paths}, "fixtures changed"
    report = {"reference_ref": REFERENCE, "host_ref": git(host, "rev-parse", "HEAD"),
              "host_dirty": bool(git(host, "status", "--porcelain")), "reference_api": 3, "host_api": args.host_api,
              "format": "unified", "files_sha256": hashes, "runs": runs, "differences": differences}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    if differences:
        for difference in differences:
            print(json.dumps(difference, sort_keys=True))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
