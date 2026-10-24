#!/usr/bin/env python3
"""Compare the same mod's GBA enemy move choices with a clean read-only Gen1 reference."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

GEN1_REF = "535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gen1", required=True, type=Path)
    parser.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    source, host = args.gen1.resolve(), args.gen2.resolve()
    if git(source, "rev-parse", "HEAD") != GEN1_REF or git(source, "status", "--porcelain"):
        parser.error(f"Gen1 must be clean at {GEN1_REF}; the checker never patches it")
    paths = [*sorted((host / "examples/portable_enemy_action").glob("*")),
             *sorted((host / "tests/enemy_actions").glob("*.lua")), Path(__file__).with_name("worker.lua")]
    report = {"source_ref": GEN1_REF, "host_ref": git(host, "rev-parse", "HEAD"),
              "host_dirty": bool(git(host, "status", "--porcelain")),
              "fixture_sha256": {str(p.relative_to(host)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in paths}, "runs": [], "comparisons": []}
    failed = False
    for version in ("firered", "emerald"):
        for api, mode in ((2, "choices"), (3, "choices"), (3, "arguments"), (3, "records"), (3, "targets")):
            values = {}
            for backend, root in (("gen1", source), ("gen2", host)):
                cmd = [args.lua, str(host / "tools/enemy-action-contract-check/worker.lua"),
                       str(host), backend, version, str(api), mode]
                run = subprocess.run(cmd, cwd=root, text=True, capture_output=True, timeout=60)
                rows = [json.loads(line.removeprefix("ENEMY_ACTION_OBSERVATIONS "))
                        for line in run.stdout.splitlines() if line.startswith("ENEMY_ACTION_OBSERVATIONS ")]
                report["runs"].append({"backend": backend, "version": version, "api": api, "mode": mode,
                                       "exit": run.returncode, "stdout": run.stdout, "stderr": run.stderr})
                if run.returncode or len(rows) != 1:
                    failed = True
                else:
                    values[backend] = rows[0]
            equal = len(values) == 2 and values["gen1"] == values["gen2"]
            failed |= not equal
            report["comparisons"].append({"version": version, "api": api, "mode": mode, "equal": equal,
                                           "observations": values})
            print(f"{'PASS' if equal else 'FAIL'} {version}/API {api}/{mode}: identical public move selections and execution")
    report["passed"] = not failed
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    if git(source, "status", "--porcelain"):
        raise RuntimeError("reference checkout changed during the comparison")
    return int(failed)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
