#!/usr/bin/env python3
"""Compare the same render-data consumer on Gen2 and a pinned Gen1 reference adapter."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

GEN1_REF = "79ea62f45fb2ea8f65d081a109431e4eb1bbdb36"
VERSIONS = ("firered", "emerald", "red", "gold")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--gen1", type=Path, required=True)
    p.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    p.add_argument("--api", type=int, choices=(2, 3), default=2,
                   help="3 requires the separate API-3 entry PR to be integrated")
    p.add_argument("--report", type=Path)
    a = p.parse_args()
    gen1, gen2 = a.gen1.resolve(), a.gen2.resolve()
    if git(gen1, "rev-parse", "HEAD") != GEN1_REF:
        p.error(f"Gen1 must be pinned to {GEN1_REF}")
    if git(gen1, "status", "--porcelain", "--untracked-files=normal"):
        p.error("Gen1 reference must be clean; use an isolated checkout")
    results = []
    for version in VERSIONS:
        values = []
        for backend, engine in (("gen1", gen1), ("gen2", gen2)):
            run = subprocess.run([a.lua, str(gen2 / "tests/render_contract/worker.lua"),
                                  str(gen2), backend, version, str(a.api)], cwd=engine,
                                 capture_output=True, text=True, timeout=60)
            reports = [line[len("RENDER_CONTRACT "):] for line in run.stdout.splitlines()
                       if line.startswith("RENDER_CONTRACT ")]
            if run.returncode or len(reports) != 1:
                raise RuntimeError(f"{backend}/{version} failed:\n{run.stdout}{run.stderr}")
            values.append(json.loads(reports[0]))
        if values[0] != values[1]:
            raise RuntimeError(f"render-data mismatch for {version}")
        results.append({"version": version, "checks_per_engine": values[0]["checks"],
                        "result_sha256": hashlib.sha256(json.dumps(values[0], sort_keys=True).encode()).hexdigest()})
        print(f"PASS {version}: identical public observations ({values[0]['checks']} checks/engine)")
    if git(gen1, "status", "--porcelain", "--untracked-files=normal"):
        raise RuntimeError("Gen1 reference changed during the contract run")
    files = [gen2 / "src/mods/RenderData.lua", gen2 / "src/mods/Loader.lua"]
    for directory in ("tests/render_contract", "tools/gen3-render-contract"):
        files.extend(path for path in sorted((gen2 / directory).rglob("*"))
                     if path.is_file() and "__pycache__" not in path.parts)
    report = {"gen1_ref": GEN1_REF, "gen2_ref": git(gen2, "rev-parse", "HEAD"),
              "gen1_surface": "test-only reference extension; not an upstream Gen1 public API",
              "api": a.api, "gen2_tracked_changes": bool(git(gen2, "status", "--porcelain", "--untracked-files=no")),
              "source_sha256": {str(path.relative_to(gen2)): hashlib.sha256(path.read_bytes()).hexdigest()
                                for path in files}, "comparisons": results,
              "total_checks": 2 * sum(row["checks_per_engine"] for row in results)}
    if a.report:
        a.report.write_text(json.dumps(report, indent=2) + "\n")
    print(f"Render data v1: {len(results)} comparisons / {len(results) * 2} isolated loader runs / "
          f"{report['total_checks']} checks passed")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
