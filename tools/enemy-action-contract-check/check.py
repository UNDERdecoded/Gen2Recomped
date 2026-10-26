#!/usr/bin/env python3
"""Compare portable mod and native runtime contracts with a clean read-only Gen1 reference."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

GEN1_REF = "535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91"


MODES = [
    (3, 'native_bgm_options'),
    (3, 'native_bgm_hooks'),
    (3, 'native_bgm_devices'),
    (3, 'native_fanfare_commands'),
    (3, 'native_bgm_commands'),
    (3, 'native_bgm_policy'),
    (3, 'native_bgm_symbols'),
    (3, 'native_cry_lifecycle'),
    (3, 'native_cry_commands'),
    (3, 'native_cry_pcm'),
    (3, 'native_sound_script_waits'),
    (3, 'native_sound_lifecycle'),
    (3, 'substitute_fade'),
    (3, 'battle_effect_presentation'),
    (3, 'native_sound_pan'),
    (3, 'substitute_multi_hit'),
    (3, 'substitute_presentation'),
    (3, 'mirror_move'),
    (3, 'mirror_move_content'),
    (3, 'mirror_move_chained'),
    (3, 'assist'),
    (3, 'assist_content'),
    (3, 'assist_held'),
    (3, 'assist_failed_callers'),
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


def same_observations(left, right):
    """Compare JSON values without Python's Boolean/number coercion."""
    if isinstance(left, bool) or isinstance(right, bool):
        return type(left) is bool and type(right) is bool and left == right
    if isinstance(left, dict):
        return (isinstance(right, dict) and left.keys() == right.keys()
                and all(same_observations(value, right[key]) for key, value in left.items()))
    if isinstance(left, list):
        return (isinstance(right, list) and len(left) == len(right)
                and all(same_observations(a, b) for a, b in zip(left, right)))
    if isinstance(left, (int, float)):
        return isinstance(right, (int, float)) and left == right
    return type(left) is type(right) and left == right


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
    paths.extend(sorted((host / "tests/native_sound").glob("*.lua")))
    paths.extend(sorted((host / "tests/native_cry").glob("*.lua")))
    paths.extend(sorted((host / "tests/native_bgm").glob("*.lua")))
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
                # These exhaustive matrices resolve thousands of complete scripts.
                # Keep a bounded three-minute budget for their native work,
                # including low-priority local runs, rather than a 60s cutoff.
                timeout = 180 if mode in {"post_hit_items_execution", "assist", "assist_content", "assist_held", "nature_power"} else 60
                timed_out = None
                started = time.monotonic()
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
                elapsed = time.monotonic() - started
                rows = [json.loads(line.removeprefix("ENEMY_ACTION_OBSERVATIONS "))
                        for line in run.stdout.splitlines() if line.startswith("ENEMY_ACTION_OBSERVATIONS ")]
                # The native VM catches task errors and wait caps internally.
                # A zero worker exit must not turn an aborted animation into an oracle.
                diagnostics = [line for line in run.stdout.splitlines()
                               if line.startswith("[battle.anim]")]
                report["runs"].append({"backend": backend, "version": version, "api": api, "mode": mode,
                                       "exit": run.returncode, "stdout": run.stdout, "stderr": run.stderr,
                                       "timeout": timed_out, "wall_seconds": round(elapsed, 4),
                                       "native_vm_diagnostics": diagnostics})
                if run.returncode or len(rows) != 1 or diagnostics:
                    failed = True
                else:
                    values[backend] = rows[0]
            equal = len(values) == 2 and same_observations(values["gen1"], values["gen2"])
            failed |= not equal
            report["comparisons"].append({"version": version, "api": api, "mode": mode, "equal": equal,
                                           "observations": values})
            print(f"{'PASS' if equal else 'FAIL'} {version}/API {api}/{mode}: identical complete contract observations")
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
