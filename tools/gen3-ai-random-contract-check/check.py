#!/usr/bin/env python3
"""Compare real GBA AI VM random branches without ROMs or a graphics runtime."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

REFERENCE = "535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91"


def git(root, *args):
    return subprocess.check_output(["git", "-C", str(root), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gen1", type=Path, required=True)
    parser.add_argument("--gen2", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--report", type=Path)
    parser.add_argument("--emerald-rom", type=Path, help="optionally compare native Emerald AI subroutines")
    args = parser.parse_args()
    source, host = args.gen1.resolve(), args.gen2.resolve()
    if git(source, "rev-parse", "HEAD") != REFERENCE or git(source, "status", "--porcelain"):
        parser.error("reference must be clean at " + REFERENCE)
    rom, rom_sha1 = None, None
    if args.emerald_rom:
        rom = args.emerald_rom.resolve()
        rom_sha1 = hashlib.sha1(rom.read_bytes()).hexdigest()
        for engine in [source, host]:
            manifest = json.loads((engine / "tools/rom_manifest_emerald.json").read_text())
            if rom_sha1 != manifest["romSha1"]:
                parser.error("Emerald ROM must match both native manifests; no import was started")
    runs, differences = [], []
    for version in ["firered", "emerald"]:
        observations = []
        for backend, engine in [("gen1", source), ("gen2", host)]:
            run = subprocess.run([args.lua, str(host / "tests/gen3_ai_random/worker.lua"), str(host),
                                  backend, version], cwd=engine, capture_output=True, text=True, timeout=30)
            prefix = "GEN3_AI_RANDOM "
            lines = [line.removeprefix(prefix) for line in run.stdout.splitlines() if line.startswith(prefix)]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            value = json.loads(lines[0])
            observations.append(value)
            runs.append({"backend": backend, "version": version, "observations": value})
        if len(observations[0]) != len(observations[1]):
            differences.append({"version": version, "error": "observation count"})
        for index, (left, right) in enumerate(zip(*observations)):
            if left != right:
                differences.append({"version": version, "row": index, "reference": left, "host": right})
        print("PASS" if observations[0] == observations[1] else "FAIL", version)
    native = None
    if rom:
        by_backend = {}
        for backend, engine in [("gen1", source), ("gen2", host)]:
            run = subprocess.run([args.lua, str(host / "tests/gen3_ai_random/native_worker.lua"),
                                  str(host), backend, str(rom)], cwd=engine,
                                 capture_output=True, text=True, timeout=60)
            prefix = "GEN3_AI_RANDOM_NATIVE "
            lines = [line.removeprefix(prefix) for line in run.stdout.splitlines() if line.startswith(prefix)]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/native Emerald: {run.stdout}{run.stderr}")
            rows = json.loads(lines[0])
            by_backend[backend] = {(row["pc"], row["raw"]): row for row in rows}
        left, right = by_backend["gen1"], by_backend["gen2"]
        common = sorted(left.keys() & right.keys())
        if not common:
            raise RuntimeError("native importers have no common RNG-only entry points")
        native_differences = [{"pc": key[0], "raw": key[1], "reference": left[key], "host": right[key]}
                              for key in common if left[key] != right[key]]
        # Importers split bodies differently: report every unpaired entry explicitly.
        reference_only = sorted({key[0] for key in left.keys() - right.keys()})
        native = {"rom_sha1": rom_sha1, "paired_observations": len(common),
                  "paired_subroutines": len({key[0] for key in common}),
                  "reference_only": reference_only,
                  "host_only": sorted({key[0] for key in right.keys() - left.keys()}),
                  "observations": [left[key] for key in common],
                  "differences": native_differences}
        differences.extend({"native_emerald": row} for row in native_differences)
        if reference_only:
            differences.append({"native_emerald_missing_reference_entries": reference_only})
        print("PASS" if not native_differences and not reference_only else "FAIL", "native Emerald",
              len(common), "paired observations")
    assert not git(source, "status", "--porcelain"), "reference changed"
    report = {"reference_ref": REFERENCE, "host_ref": git(host, "rev-parse", "HEAD"),
              "host_dirty": bool(git(host, "status", "--porcelain")), "runs": runs,
              "differences": differences, "native": native}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    if differences:
        raise SystemExit(f"{len(differences)} differing AI VM observations")


if __name__ == "__main__":
    main()
