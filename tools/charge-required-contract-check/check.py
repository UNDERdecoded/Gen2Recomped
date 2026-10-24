#!/usr/bin/env python3
"""Compare one public charge-turn consumer through both native battle engines."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

GEN1 = "79ea62f45fb2ea8f65d081a109431e4eb1bbdb36"


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
    p.add_argument("--require-native-policy-parity", action="store_true",
                   help="also compare raw native enemy PP costs, not just preservation")
    a = p.parse_args()
    gen1, gen2 = a.gen1.resolve(), a.gen2.resolve()
    if git(gen1, "rev-parse", "HEAD") != GEN1 or git(gen1, "status", "--porcelain"):
        p.error("Gen1 must be clean at " + GEN1)
    results = []
    versions = ["red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald"]
    for version in versions:
        observations = []
        for backend, engine in [("gen1", gen1), ("gen2", gen2)]:
            run = subprocess.run([a.lua, str(gen2/"tests/charge_required/worker.lua"), str(gen2),
                                  backend, version, str(a.api), a.format], cwd=engine,
                                 text=True, capture_output=True, timeout=30)
            lines = [line[len("CHARGE_REQUIRED_CONTRACT "):] for line in run.stdout.splitlines()
                     if line.startswith("CHARGE_REQUIRED_CONTRACT ")]
            if run.returncode or len(lines) != 1:
                raise RuntimeError(f"{backend}/{version}: {run.stdout}{run.stderr}")
            rows = json.loads(lines[0])
            observations.append(rows)
            results.append({"backend": backend, "version": version,
                            "scope": "native battle charge decision",
                            "observations": rows, "native_policy": json.loads(next(
                                line[len("CHARGE_NATIVE_POLICY "):] for line in run.stdout.splitlines()
                                if line.startswith("CHARGE_NATIVE_POLICY "))),
                            "checks": run.stdout.splitlines()[-1]})
        if a.require_native_policy_parity:
            assert results[-2]["native_policy"] == results[-1]["native_policy"], (
                f"native enemy PP policy mismatch: {version}")
        assert observations[0] == observations[1], f"charge decision mismatch: {version}"
        print(f"PASS {version}: {len(observations[0])} matching native charge observations")
    assert not git(gen1, "status", "--porcelain"), "reference changed"
    report = {"gen1_ref": GEN1, "gen2_ref": git(gen2, "rev-parse", "HEAD"), "api": a.api,
              "format": a.format, "require_native_policy_parity": a.require_native_policy_parity, "results": results,
              "consumer_sha256": hashlib.sha256(
                  (gen2/"examples/portable_charge_required/main.lua").read_bytes()).hexdigest()}
    if a.report:
        a.report.write_text(json.dumps(report, indent=2)+"\n")


if __name__ == "__main__":
    main()
