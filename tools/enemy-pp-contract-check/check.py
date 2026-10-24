#!/usr/bin/env python3
"""Compare native Gold-family enemy PP, actual AI depletion and a public API-3 observer."""
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
    p.add_argument("--report", type=Path)
    a = p.parse_args()
    gen1, gen2 = a.gen1.resolve(), a.gen2.resolve()
    if git(gen1, "rev-parse", "HEAD") != GEN1 or git(gen1, "status", "--porcelain"):
        p.error("Gen1 must be clean at " + GEN1)
    results = []
    for version in ("gold", "silver", "crystal"):
        pair = []
        for backend, engine in (("gen1", gen1), ("gen2", gen2)):
            run = subprocess.run([a.lua, str(gen2 / "tests/enemy_pp/worker.lua"), str(gen2),
                                  backend, version], cwd=engine, text=True, capture_output=True, timeout=30)
            lines = [line.removeprefix("ENEMY_PP_CONTRACT ") for line in run.stdout.splitlines()
                     if line.startswith("ENEMY_PP_CONTRACT ")]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            rows = json.loads(lines[0])
            pair.append(rows)
            results.append({"backend": backend, "version": version, "observations": rows,
                            "checks": run.stdout.splitlines()[-1]})
        assert pair[0] == pair[1], f"enemy PP mismatch: {version}"
        print(f"PASS {version}: {len(pair[0])} matching native enemy PP observations")
    assert not git(gen1, "status", "--porcelain"), "reference changed"
    report = {"gen1_ref": GEN1, "gen2_ref": git(gen2, "rev-parse", "HEAD"), "results": results,
              "consumer_sha256": hashlib.sha256(
                  (gen2 / "examples/portable_enemy_pp/main.lua").read_bytes()).hexdigest()}
    if a.report:
        a.report.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
