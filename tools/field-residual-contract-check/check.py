#!/usr/bin/env python3
"""Compare one unchanged public field-residual consumer through both native residual phases."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

GEN1 = "79ea62f45fb2ea8f65d081a109431e4eb1bbdb36"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--gen1", type=Path, required=True)
    p.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    p.add_argument("--api", type=int, choices=[1, 2, 3], default=3)
    p.add_argument("--format", choices=["native", "unified"], default="unified")
    p.add_argument("--report", type=Path)
    a = p.parse_args()
    gen1, gen2 = a.gen1.resolve(), a.gen2.resolve()
    if git(gen1, "rev-parse", "HEAD") != GEN1 or git(gen1, "status", "--porcelain"):
        p.error("Gen1 must be clean at " + GEN1)
    results = []
    versions = ["red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald"]
    for version in versions:
        observations = []
        for backend, engine in [("gen1", gen1), ("gen2", gen2)]:
            run = subprocess.run([a.lua, str(gen2/"tests/field_residual/worker.lua"), str(gen2),
                                  backend, version, str(a.api), a.format], cwd=engine,
                                 text=True, capture_output=True, timeout=30)
            lines = [line[len("FIELD_RESIDUAL_CONTRACT "):] for line in run.stdout.splitlines()
                     if line.startswith("FIELD_RESIDUAL_CONTRACT ")]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            rows = json.loads(lines[0])
            observations.append(rows)
            results.append({"backend": backend, "version": version,
                            "scope": "native field residual decision",
                            "observations": rows, "checks": run.stdout.splitlines()[-1]})
        assert observations[0] == observations[1], f"field residual mismatch: {version}"
        print(f"PASS {version}: {len(observations[0])} matching native field residual observations")
    assert not git(gen1, "status", "--porcelain"), "reference changed"
    report = {"gen1_ref": GEN1, "gen2_ref": git(gen2, "rev-parse", "HEAD"), "api": a.api,
              "gen2_worktree_dirty": bool(git(gen2, "status", "--porcelain")),
              "format": a.format, "results": results,
              "consumer_sha256": hashlib.sha256(
                  (gen2/"examples/portable_field_residual/main.lua").read_bytes()).hexdigest()}
    if a.report:
        a.report.write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    main()
