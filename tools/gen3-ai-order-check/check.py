#!/usr/bin/env python3
"""Compare real Gen2 VMs/comparators with pinned native C, without ROM assets.

Read-only source inputs are pret/pokefirered@ce6406d8 and
pret/pokeemerald@731ad5bf src/battle_main.c. No Gen1 patches are required.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

PINS = {
    "firered": "af41c49b333346e1f06f0f028a425aaf84d2920c499a75d4e366ebef8991155f",
    "emerald": "38813182841cab356c5d6400e160333996195c362960237ae3b4573980642a47",
}


def native_function(path, profile):
    text = Path(path).read_text()
    start = text.index("u8 GetWhoStrikesFirst(u8 battler1, u8 battler2, bool8 ignoreChosenMoves)\n{")
    end = text.index("\n}", start) + 2
    function = text[start:end]
    digest = hashlib.sha256(function.encode()).hexdigest()
    if digest != PINS[profile]:
        raise SystemExit(f"Unverified {profile} function: {digest}")
    assert function.count("return strikesFirst;") == 1
    # Observe local arithmetic immediately before the original return.
    return function.replace("return strikesFirst;", "oracleSpeed1 = speedBattler1; oracleSpeed2 = speedBattler2; return strikesFirst;")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--firered-main", required=True)
    parser.add_argument("--emerald-main", required=True)
    parser.add_argument("--lua", default=os.environ.get("LUA", "luajit"))
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    cc = shutil.which(os.environ.get("CC", "cc"))
    if not cc:
        raise SystemExit("A C99 compiler is required")
    report = {"profiles": {}, "errors": []}
    for profile in PINS:
        result = subprocess.run([args.lua, "tests/gen3_ai_order/worker.lua", ".", profile],
                                cwd=root, text=True, capture_output=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        match = re.search(r"^GEN3_AI_ORDER (.+)$", result.stdout, re.M)
        if not match:
            raise SystemExit("Missing worker records")
        rows = json.loads(match[1])
        if len(rows) < 250:
            raise SystemExit("Incomplete scenario matrix")
        with tempfile.TemporaryDirectory(prefix="native-gba-order-") as directory:
            tmp = Path(directory)
            (tmp / "native-function.c").write_text(native_function(getattr(args, profile + "_main"), profile))
            executable = tmp / "oracle"
            subprocess.run([cc, "-std=c99", "-Wall", "-Wextra", "-Werror", "-I", str(tmp),
                            str(root / "tools/gen3-ai-order-check/oracle.c"), "-o", str(executable)], check=True)
            inputs = "".join(" ".join(map(str, row["native"])) + "\n" for row in rows)
            output = subprocess.run([str(executable)], input=inputs, text=True, capture_output=True, check=True)
        native_rows = output.stdout.splitlines()
        if len(native_rows) != len(rows):
            raise SystemExit("Incomplete native records")
        for row, line in zip(rows, native_rows):
            native = list(map(int, line.split()))
            result, sa, sb, query_draws, actual_result, actual_draws, sort_draws = native[:7]
            errors = []
            if row["speeds"] != [sa, sb]:
                errors.append(f"speeds {row['speeds']} != {[sa, sb]}")
            for observation in row["observations"]:
                expected = 105 if ((result == observation["wanted"]) != observation["inverse"]) else 100
                if observation["score"] != expected or observation["draws"] != [[0, 65535]] * query_draws:
                    errors.append(f"native VM result {result}: {observation}")
            actual = row["actual"]
            expected_actual = {"first": actual_result == 0, "draws": [[0, 1]] * actual_draws,
                               "order": native[7:], "sortDraws": [[0, 1]] * sort_draws}
            if actual != expected_actual:
                errors.append(f"actual comparator/sort {actual} != {expected_actual}")
            if errors:
                report["errors"].append({"profile": profile, "name": row["name"], "errors": errors})
        report["profiles"][profile] = {"cases": len(rows), "vmQueries": len(rows) * 10,
                                      "comparators": len(rows), "sorts": len(rows), "functionSha256": PINS[profile]}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return int(bool(report["errors"]))


if __name__ == "__main__":
    raise SystemExit(main())
