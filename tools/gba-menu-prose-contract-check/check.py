#!/usr/bin/env python3
"""Compare the same installed consumer through the two real mod SDKs."""
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
    results, pairs = [], 0
    for version in ["firered", "emerald"]:
        observed = []
        for backend, engine, api in [("gen1", source, 3), ("gen2", host, a.host_api)]:
            run = subprocess.run([a.lua, str(host / "tests/gba_menu_prose/worker.lua"),
                                  str(host), backend, version, str(api), "unified"],
                                 cwd=engine, text=True, capture_output=True, timeout=45)
            lines = [s.removeprefix("GBA_MENU_PROSE ") for s in run.stdout.splitlines()
                     if s.startswith("GBA_MENU_PROSE ")]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            rows = json.loads(lines[0])
            observed.append(rows)
            results.append({"backend": backend, "version": version, "api": api, "observations": rows})
        if observed[0] != observed[1]:
            raise AssertionError(f"{version}: native menu observations differ")
        count = sum(len(r["actions"]) + 1 + len(r.get("itemPc", [])) for r in observed[0])
        pairs += count
        print(f"PASS {version}: {count} paired native menu values")
    assert not git(source, "status", "--porcelain"), "reference changed"
    if a.report:
        a.report.write_text(json.dumps({"reference_ref": REFERENCE,
            "host_ref": git(host, "rev-parse", "HEAD"), "host_worktree_dirty": bool(git(host, "status", "--porcelain")),
            "host_api": a.host_api, "paired_values": pairs, "results": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
