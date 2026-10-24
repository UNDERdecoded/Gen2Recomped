#!/usr/bin/env python3
"""Compare unchanged Gen-2/3 shiny and gender hooks through native identity producers."""
import argparse
import json
import os
from pathlib import Path
import subprocess

GEN1 = "535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91"


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
    for version in ["red", "gold", "silver", "crystal", "firered", "emerald"]:
        observations = []
        for backend, engine in [("gen1", gen1), ("gen2", gen2)]:
            run = subprocess.run([a.lua, str(gen2 / "tests/pokemon_rolls/worker.lua"), str(gen2),
                                  backend, version, str(a.api), a.format], cwd=engine,
                                 text=True, capture_output=True, timeout=30)
            lines = [line[len("POKEMON_ROLL_CONTRACT "):] for line in run.stdout.splitlines()
                     if line.startswith("POKEMON_ROLL_CONTRACT ")]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            rows = json.loads(lines[0])
            observations.append(rows)
            results.append({"backend": backend, "version": version, "observations": rows})
        assert observations[0] == observations[1], f"Pokemon identity roll mismatch: {version}"
        print(f"PASS {version}: {len(observations[0])} matching native Pokemon identity roll observations")
    assert not git(gen1, "status", "--porcelain"), "reference changed"
    if a.report:
        a.report.write_text(json.dumps({"gen1_ref": GEN1, "gen2_ref": git(gen2, "rev-parse", "HEAD"),
            "api": a.api, "format": a.format, "gen2_worktree_dirty": bool(git(gen2, "status", "--porcelain")),
            "results": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
