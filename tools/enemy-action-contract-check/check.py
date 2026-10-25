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


MODES = [
    (3, 'nature_power'),
    (3, 'nature_power_content'),
    (3, 'nature_power_chained'),
    (3, 'post_hit_items_command'),
    (3, 'post_hit_items_execution'),
    (3, 'move_used_pp'),
    (2, 'choices'),
    (3, 'choices'),
    (3, 'arguments'),
    (3, 'records'),
    (3, 'targets'),
    (3, 'follow_me'),
    (3, 'helping_hand'),
    (3, 'spit_up'),
    (3, 'beat_up'),
    (3, 'beat_up_content'),
    (3, 'beat_up_adjustment'),
    (3, 'beat_up_side_party'),
    (3, 'critical_context'),
    (3, 'constrained_party'),
    (3, 'accuracy'),
    (3, 'accuracy_execution'),
    (3, 'secondary'),
    (3, 'secondary_execution'),
    (3, 'party_codec'),
    (3, 'party_codec_hooks'),
    (3, 'lock_on'),
    (3, 'baton_pass'),
    (3, 'encore'),
    (3, 'disable'),
    (3, 'multi_hit'),
    (3, 'rage'),
    (3, 'triple_kick'),
    (3, 'sleep_talk'),
    (3, 'sleep_talk_content'),
    (3, 'choice_band_command'),
    (3, 'choice_band_selection'),
    (3, 'choice_band_planning'),
    (3, 'choice_band_wild'),
    (3, 'choice_band_calls'),
    (3, 'choice_band_content'),
    (3, 'choice_band_baton'),
    (3, 'choice_band_call_failure'),
]


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gen1", required=True, type=Path)
    parser.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--report", required=True, type=Path)
    parser.add_argument("--mode", action="append", choices=sorted({name for _, name in MODES}),
                        help="Run selected modes; omission runs every contract")
    args = parser.parse_args()
    source, host = args.gen1.resolve(), args.gen2.resolve()
    if git(source, "rev-parse", "HEAD") != GEN1_REF or git(source, "status", "--porcelain"):
        parser.error(f"Gen1 must be clean at {GEN1_REF}; the checker never patches it")
    paths = [*sorted((host / "examples/portable_enemy_action").glob("*")),
             *sorted((host / "tests/post_hit_items").glob("*.json")),
             *sorted((host / "tests/enemy_actions").glob("*.lua")), Path(__file__).with_name("worker.lua")]
    report = {"source_ref": GEN1_REF, "host_ref": git(host, "rev-parse", "HEAD"),
              "host_dirty": bool(git(host, "status", "--porcelain")),
              "fixture_sha256": {str(p.relative_to(host)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in paths}, "runs": [], "comparisons": []}
    failed = False
    for version in ("firered", "emerald"):
        for api, mode in MODES:
            if args.mode and mode not in args.mode:
                continue
            values = {}
            for backend, root in (("gen1", source), ("gen2", host)):
                cmd = [args.lua, str(host / "tools/enemy-action-contract-check/worker.lua"),
                       str(host), backend, version, str(api), mode]
                # This matrix executes thousands of complete scripts per worker.
                # Retain a real failure on timeout, including partial raw output.
                timeout = 180 if mode == "post_hit_items_execution" else 60
                timed_out = None
                try:
                    run = subprocess.run(cmd, cwd=root, text=True, capture_output=True, timeout=timeout)
                except subprocess.TimeoutExpired as error:
                    def captured(value):
                        return value.decode("utf-8", errors="replace") if isinstance(value, bytes) else value or ""
                    timed_out = {"seconds": timeout,
                                 "stdout_hex": error.stdout.hex() if isinstance(error.stdout, bytes) else None,
                                 "stderr_hex": error.stderr.hex() if isinstance(error.stderr, bytes) else None}
                    run = subprocess.CompletedProcess(cmd, 124, captured(error.stdout),
                                                      captured(error.stderr) + "\nWorker timed out and was terminated.\n")
                rows = [json.loads(line.removeprefix("ENEMY_ACTION_OBSERVATIONS "))
                        for line in run.stdout.splitlines() if line.startswith("ENEMY_ACTION_OBSERVATIONS ")]
                report["runs"].append({"backend": backend, "version": version, "api": api, "mode": mode,
                                       "exit": run.returncode, "stdout": run.stdout, "stderr": run.stderr,
                                       "timeout": timed_out})
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
