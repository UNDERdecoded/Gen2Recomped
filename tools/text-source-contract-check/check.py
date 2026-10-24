#!/usr/bin/env python3
"""Compare public source text through both real SDKs and native script readers."""
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
    p.add_argument("--host-api", type=int, choices=[2, 3], default=3)
    p.add_argument("--report", type=Path)
    a = p.parse_args()
    source, host = a.gen1.resolve(), a.gen2.resolve()
    if git(source, "rev-parse", "HEAD") != REFERENCE or git(source, "status", "--porcelain"):
        p.error("Gen1 must be clean at " + REFERENCE)
    results = []
    for version in ["red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald"]:
        observations = []
        for backend, engine, api in [("gen1", source, 3), ("gen2", host, a.host_api)]:
            run = subprocess.run([a.lua, str(host / "tests/text_sources/worker.lua"), str(host),
                                  backend, version, str(api), "unified"], cwd=engine,
                                 text=True, capture_output=True, timeout=45)
            rows = [line.removeprefix("TEXT_SOURCE_CONTRACT ") for line in run.stdout.splitlines()
                    if line.startswith("TEXT_SOURCE_CONTRACT ")]
            if run.returncode or len(rows) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            rows = json.loads(rows[0])
            observations.append(rows)
            results.append({"backend": backend, "version": version, "api": api, "observations": rows})
        if observations[0] != observations[1]:
            for index, (left, right) in enumerate(zip(*observations)):
                if left != right:
                    raise AssertionError(f"{version}/{index}: reference={left!r}, host={right!r}")
            raise AssertionError(f"{version}: different observation counts")
        print(f"PASS {version}: {len(observations[0])} matching native source-text observations")
    assert not git(source, "status", "--porcelain"), "reference changed"
    if a.report:
        a.report.write_text(json.dumps({"reference_ref": REFERENCE,
            "host_ref": git(host, "rev-parse", "HEAD"), "host_api": a.host_api,
            "host_worktree_dirty": bool(git(host, "status", "--porcelain")),
            "results": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
