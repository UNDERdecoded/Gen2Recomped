#!/usr/bin/env python3
"""Batch driver for tools/gen4_field_sweep_harness (the Gen 4 overworld/menu sweep).

Runs the harness over every map of an imported cache in batches, restarts the
process after a hard crash or a hang (marking the map it died on as a failure),
and merges the SWEEP_* lines into one report.

    python tools/gen4_field_sweep.py --install "<cache>/platinum" --out sweep.txt
    python tools/gen4_field_sweep.py --install ... --maps T01,R201 --profile rich
    python tools/gen4_field_sweep.py --install ... --prefix D --menus map

Everything the harness reads from the environment can be given as `--env K=V`
(repeatable): LOAD_FRAMES, WALK_FRAMES, TALK_BUDGET, MAX_NPCS, SEED, PHASES ...
See the header of tools/gen4_field_sweep_harness/main.lua.

The report ends with a per-kind count and the failing maps; exit status is 1
when anything failed, so it can gate a check.
"""
import argparse
import collections
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_LOVE = r"C:\Program Files\LOVE\lovec.exe"


def run_harness(love, env, timeout):
    """Run the wrapper once; return (stdout lines, timed_out)."""
    cmd = [love, os.path.join("tools", "gen4_hgss_overworld_harness")]
    try:
        proc = subprocess.run(cmd, cwd=ROOT, env=env, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, timeout=timeout)
        out = proc.stdout
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout or b""
        timed_out = True
    text = out.decode("utf-8", errors="replace")
    return [ln for ln in text.splitlines() if ln.startswith("SWEEP_")], timed_out


def run_regressions(args, env):
    """Each regress/*.lua is a PROBE: it runs inside the booted harness and prints
    REGRESS_OK <name> or REGRESS_FAIL <name>: <why>."""
    folder = os.path.join(ROOT, "tools", "gen4_field_sweep_harness", "regress")
    failed = 0
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".lua"):
            continue
        penv = dict(env, PROBE=os.path.join("tools", "gen4_field_sweep_harness", "regress", name))
        cmd = [args.love, os.path.join("tools", "gen4_hgss_overworld_harness")]
        try:
            proc = subprocess.run(cmd, cwd=ROOT, env=penv, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT, timeout=args.timeout)
            text = proc.stdout.decode("utf-8", errors="replace")
        except subprocess.TimeoutExpired:
            text = ""
        lines = [ln for ln in text.splitlines() if ln.startswith(("REGRESS_", "PROBE FAILED"))]
        ok = any(ln.startswith("REGRESS_OK") for ln in lines) and not any(
            ln.startswith(("REGRESS_FAIL", "PROBE FAILED")) for ln in lines)
        print(("ok   " if ok else "FAIL ") + name)
        if not ok:
            failed += 1
            for ln in lines or ["(no result: the probe hung or died)"]:
                print("     " + ln)
    print(f"{failed} regression(s) failed")
    return 1 if failed else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--install", required=True, help="the imported version folder (e.g. .../Gen2Recomp/platinum)")
    ap.add_argument("--version", default="platinum")
    ap.add_argument("--identity", default="pl_field", help="POKEPORT_IDENTITY for the run")
    ap.add_argument("--love", default=DEFAULT_LOVE)
    ap.add_argument("--maps", help="comma list of map ids (default: every map)")
    ap.add_argument("--prefix", help="only maps whose id starts with this")
    ap.add_argument("--batch", type=int, default=100, help="maps per harness process")
    ap.add_argument("--timeout", type=int, default=900, help="seconds per batch before it is killed")
    ap.add_argument("--profile", default="new", choices=["new", "rich"])
    ap.add_argument("--state", default="none", choices=["none", "flags", "chaos"])
    ap.add_argument("--menus", default="once", choices=["once", "map", "off"])
    ap.add_argument("--seed", default="1")
    ap.add_argument("--env", action="append", default=[], help="extra K=V for the harness")
    ap.add_argument("--out", default="field_sweep_report.txt")
    ap.add_argument("--regress", action="store_true",
                    help="run the probes in tools/gen4_field_sweep_harness/regress/ (one fixed bug each) "
                         "instead of a sweep; exit status 1 if any fails")
    args = ap.parse_args()

    env = dict(os.environ)
    env.update({
        "POKEPORT_IDENTITY": args.identity,
        "INSTALL": args.install,
        "VERSION": args.version,
        "HARNESS": "gen4_field_sweep_harness",
        "PROFILE": args.profile,
        "STATE": args.state,
        "SEED": args.seed,
        "MENUS": args.menus,
    })
    for kv in args.env:
        k, _, v = kv.partition("=")
        env[k] = v

    if args.regress:
        return run_regressions(args, env)

    # the map list, from the harness itself so it always matches the engine's view
    list_env = dict(env, LIST="1")
    if args.maps:
        list_env["MAPS"] = args.maps
    if args.prefix:
        list_env["MAP_PREFIX"] = args.prefix
    lines, _ = run_harness(args.love, list_env, 300)
    ids = [ln.split("|", 1)[1] for ln in lines if ln.startswith("SWEEP_LIST|")]
    if not ids:
        print("no maps listed; is --install a Platinum cache?", file=sys.stderr)
        return 2
    print(f"{len(ids)} maps", flush=True)

    all_lines = []
    t0 = time.time()
    pending = list(ids)
    crashes = []
    menus_pending = args.menus == "once"
    while pending:
        batch = pending[: args.batch]
        benv = dict(env, MAPS=",".join(batch))
        # the list was cut once, by the listing run; a batch is an explicit list
        for key in ("SHARD", "SKIP", "LIMIT", "MAP_PREFIX"):
            benv.pop(key, None)
        if args.menus == "once":
            benv["MENUS"] = "once" if menus_pending else "off"
        lines, timed_out = run_harness(args.love, benv, args.timeout)
        done = {ln.split("|")[1] for ln in lines if ln.startswith("SWEEP_MAP|")}
        if any(ln.startswith("SWEEP_MAP|") for ln in lines):
            menus_pending = False
        all_lines.extend(ln for ln in lines if not ln.startswith(("SWEEP_START", "SWEEP_DONE")))
        missing = [m for m in batch if m not in done]
        if missing:
            culprit = missing[0]
            why = "hung past the batch timeout" if timed_out else "the process died (hard crash)"
            crashes.append(culprit)
            all_lines.append(f"SWEEP_FAIL|{culprit}|-|process|{why}")
            all_lines.append(f"SWEEP_MAP|{culprit}|fail|crashed")
            # carry on after the culprit
            pending = missing[1:] + pending[len(batch):]
        else:
            pending = pending[len(batch):]
        print(f"  {len(ids) - len(pending)}/{len(ids)} maps, {time.time() - t0:.0f}s", flush=True)

    fails = [ln for ln in all_lines if ln.startswith("SWEEP_FAIL|")]
    loops = [ln for ln in all_lines if ln.startswith("SWEEP_LOOP|")]
    maps = [ln for ln in all_lines if ln.startswith("SWEEP_MAP|")]
    bad_maps = sorted({ln.split("|")[1] for ln in fails})
    kinds = collections.Counter(ln.split("|")[3] for ln in fails)
    with open(args.out, "w", encoding="utf-8") as fh:
        for ln in all_lines:
            fh.write(ln + "\n")
        fh.write(f"SWEEP_SUMMARY|maps={len(maps)} failed_maps={len(bad_maps)} fails={len(fails)} "
                 f"loops={len(loops)} crashes={len(crashes)} secs={time.time() - t0:.0f}\n")
        for k, n in kinds.most_common():
            fh.write(f"SWEEP_KIND|{k}|{n}\n")
    print(f"maps={len(maps)} failed_maps={len(bad_maps)} fails={len(fails)} loops={len(loops)} "
          f"crashes={len(crashes)}")
    for k, n in kinds.most_common():
        print(f"  {k}: {n}")
    print(f"report: {args.out}")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
