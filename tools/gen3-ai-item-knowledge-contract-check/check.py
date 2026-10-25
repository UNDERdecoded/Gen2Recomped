#!/usr/bin/env python3
"""Compare native GBA AI item queries and actual observation producers through both engines."""
import argparse
import json
import os
from pathlib import Path
import subprocess

REFERENCE = "12c9e5b5a2325470d6bb266c9a1f37b7954b698e"


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
            run = subprocess.run([args.lua, str(host / "tests/gen3_ai_item_knowledge/worker.lua"), str(host),
                                  backend, version], cwd=engine, capture_output=True, text=True, timeout=30)
            prefix = "GEN3_AI_ITEM_KNOWLEDGE "
            lines = [line.removeprefix(prefix) for line in run.stdout.splitlines() if line.startswith(prefix)]
            if run.returncode or len(lines) != 1:
                detail = "\n".join(line for line in run.stdout.splitlines() if not line.startswith(prefix))
                raise RuntimeError(f"{backend}/{version}: {detail[:3000]}{run.stderr[:3000]}")
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
    report = {"reference_ref": REFERENCE, "reference_repository": "Roxas2712/gen1recomp-Mac-fix",
              "reference_base_ref": "535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91", "host_ref": git(host, "rev-parse", "HEAD"),
              "host_dirty": bool(git(host, "status", "--porcelain")), "runs": runs,
              "differences": differences}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    if differences:
        raise SystemExit(f"{len(differences)} differing GBA AI item observations")


if __name__ == "__main__":
    main()
