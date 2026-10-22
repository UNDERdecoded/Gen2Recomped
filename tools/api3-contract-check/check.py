#!/usr/bin/env python3
"""Run the identical API-3 mod files on Gen2Recomped and pinned Gen1Recomp."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

GEN1_REF = "79ea62f45fb2ea8f65d081a109431e4eb1bbdb36"
VERSIONS = ("red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald")


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gen1", required=True, type=Path, help="clean checkout at the pinned Gen1 commit")
    parser.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    gen1, gen2 = args.gen1.resolve(), args.gen2.resolve()
    if git(gen1, "rev-parse", "HEAD") != GEN1_REF:
        parser.error(f"Gen1 must be pinned to {GEN1_REF}")
    if git(gen1, "status", "--porcelain", "--untracked-files=normal"):
        parser.error("Gen1 reference has tracked modifications; use an isolated checkout")
    fixtures = gen2 / "tests" / "api3_contract"
    manifest = {}
    for path in sorted((fixtures / "mods").rglob("*")):
        if path.is_file():
            manifest[str(path.relative_to(fixtures))] = hashlib.sha256(path.read_bytes()).hexdigest()
    results = []
    scaffold_temp = tempfile.TemporaryDirectory(prefix="api3-scaffold-")
    scaffold_root = Path(scaffold_temp.name)
    for name, options in (("portable", ["--api", "3"]), ("legacy", [])):
        subprocess.run([sys.executable, str(gen2 / "tools/modkit.py"), "scaffold", name,
                        "--dest", str(scaffold_root / "mods"), "--quiet", *options],
                       cwd=gen2, check=True, capture_output=True, text=True, timeout=60)
    generated = json.loads((scaffold_root / "mods/portable/manifest.json").read_text())
    assert generated["api"] == 3 and "game_version" not in generated
    assert generated["games"] == ["gen1", "gen2", "gen3"]
    legacy = json.loads((scaffold_root / "mods/legacy/manifest.json").read_text())
    assert legacy["api"] == 2 and legacy["game_version"].startswith(">=")
    generated_hashes = {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                        for path in (scaffold_root / "mods/portable").iterdir()
                        if path.is_file()}
    for version in VERSIONS:
        for mode in ("normal", "rollback", "scaffold", "warp", "world_edits", "npcs", "wild_battle"):
            values = {}
            for backend, engine in (("gen1", gen1), ("gen2", gen2)):
                source = scaffold_root if mode == "scaffold" else fixtures
                command = [args.lua, str(fixtures / "worker.lua"), str(source), backend, version, mode]
                run = subprocess.run(command, cwd=engine, text=True, capture_output=True, timeout=60)
                reports = [line.removeprefix("API3_CONTRACT ") for line in run.stdout.splitlines()
                           if line.startswith("API3_CONTRACT ")]
                if run.returncode or len(reports) != 1:
                    raise RuntimeError(f"{backend}/{version}/{mode} failed:\n{run.stdout}{run.stderr}")
                values[backend] = json.loads(reports[0])
            if values["gen1"] != values["gen2"]:
                raise RuntimeError(f"contract mismatch for {version}/{mode}: {values}")
            results.append({"version": version, "mode": mode, "result": values["gen1"]})
            print(f"PASS {version}/{mode}: identical mod and public result")
    report = {"gen1_ref": GEN1_REF, "gen2_ref": git(gen2, "rev-parse", "HEAD"),
              "gen2_tracked_changes": bool(git(gen2, "status", "--porcelain", "--untracked-files=no")),
              "fixture_sha256": manifest, "scaffold_sha256": generated_hashes, "comparisons": results}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    scaffold_temp.cleanup()
    print(f"API 3: {len(results)} cross-engine comparisons, {len(results) * 2} isolated loader runs passed")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, subprocess.SubprocessError, OSError, ValueError, AssertionError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
