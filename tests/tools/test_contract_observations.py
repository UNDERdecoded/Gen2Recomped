"""Exercise real contract CLI admission/reporting with synthetic worker output."""
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


DEFAULT_CHECKER = Path(__file__).resolve().parents[2] / "tools/enemy-action-contract-check/check.py"
CHECKER = Path(os.environ.get("POKEPORT_CONTRACT_CHECKER", DEFAULT_CHECKER)).resolve()
SPEC = importlib.util.spec_from_file_location("contract_check_under_test", CHECKER)
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class ContractObservations(unittest.TestCase):
    def run_cli(self, native, host, *, broken=None):
        with tempfile.TemporaryDirectory(prefix="contract-json-unit-") as directory:
            output = Path(directory) / "report.json"
            source = (Path(directory) / "gen1").resolve()
            source.mkdir()
            root = CHECKER.parents[2]

            def git(checkout, *args):
                if args == ("rev-parse", "HEAD"):
                    return CHECK.GEN1_REF if checkout == source else "b" * 40
                self.assertEqual(args, ("status", "--porcelain"))
                return ""

            def worker(command, *, cwd, text, capture_output, timeout):
                self.assertTrue(text and capture_output)
                self.assertIn(timeout, (60, 180))
                backend = command[3]
                self.assertEqual(cwd, source if backend == "gen1" else root)
                line = "ENEMY_ACTION_OBSERVATIONS " + json.dumps(native if backend == "gen1" else host)
                if backend == "gen2":
                    if broken == "exit":
                        return subprocess.CompletedProcess(command, 17, line + "\n", "owned worker error")
                    if broken == "missing":
                        line = "owned worker without an observation"
                    elif broken == "duplicate":
                        line += "\n" + line
                    elif broken == "diagnostic":
                        line += "\n[battle.anim] owned aborted task"
                    elif broken == "timeout":
                        raise subprocess.TimeoutExpired(command, timeout, output=b"owned partial", stderr=b"owned error")
                return subprocess.CompletedProcess(command, 0, line + "\n", "")

            argv = [str(CHECKER), "--gen1", str(source), "--gen2", str(root),
                    "--mode", "arguments", "--report", str(output)]
            with patch.object(CHECK, "git", side_effect=git), \
                    patch.object(CHECK.subprocess, "run", side_effect=worker), \
                    patch.object(sys, "argv", argv), redirect_stdout(io.StringIO()):
                code = CHECK.main()
            return code, json.loads(output.read_text())

    def assert_comparison(self, native, host, expected):
        code, report = self.run_cli(native, host)
        self.assertEqual(code, 0 if expected else 1)
        self.assertIs(report["passed"], expected)
        self.assertEqual(len(report["runs"]), 4)
        self.assertTrue(all(run["exit"] == 0 and run["timeout"] is None for run in report["runs"]))
        self.assertEqual(len(report["comparisons"]), 2)
        for row in report["comparisons"]:
            self.assertIs(row["equal"], expected)
            self.assertEqual(set(row["observations"]), {"gen1", "gen2"})

    def test_boolean_numeric_drift_is_rejected_at_every_depth(self):
        for boolean, number in ((False, 0), (True, 1)):
            for wrap in (lambda value: value,
                         lambda value: [value],
                         lambda value: [{"state": {"enabled": value}}]):
                for a, b in ((boolean, number), (number, boolean)):
                    with self.subTest(boolean=boolean, number=number, shape=wrap(a)):
                        self.assert_comparison(wrap(a), wrap(b), False)

    def test_equal_booleans_and_other_json_values_are_admitted(self):
        self.assert_comparison([{"enabled": False, "ready": True, "value": None,
                                 "name": "same", "count": 2, "list": []}],
                               [{"enabled": False, "ready": True, "value": None,
                                 "name": "same", "count": 2, "list": []}], True)

    def test_equivalent_json_numbers_and_object_key_order_are_admitted(self):
        self.assert_comparison([{"zero": 0, "count": 1, "ratio": .5}],
                               [{"ratio": .5, "count": 1.0, "zero": -0.0}], True)

    def test_other_structural_and_value_differences_remain_failures(self):
        cases = [([1, 2], [2, 1]), ({}, {"enabled": False}), (None, False),
                 ([], {}), ("1", 1), ([False], [False, False]),
                 ({"name": "A"}, {"name": "B"})]
        for native, host in cases:
            with self.subTest(native=native, host=host):
                self.assert_comparison(native, host, False)

    def test_worker_failures_cannot_be_hidden_by_matching_payloads(self):
        for broken in ("exit", "missing", "duplicate", "diagnostic", "timeout"):
            with self.subTest(broken=broken):
                code, report = self.run_cli([{"enabled": True}], [{"enabled": True}], broken=broken)
                self.assertEqual(code, 1)
                self.assertIs(report["passed"], False)
                self.assertTrue(all(row["equal"] is False for row in report["comparisons"]))
                rejected = [row for row in report["runs"] if row["backend"] == "gen2"]
                self.assertEqual(len(rejected), 2)
                if broken == "timeout":
                    self.assertTrue(all(row["exit"] == 124 for row in rejected))
                    self.assertTrue(all(row["timeout"]["stdout_hex"] == b"owned partial".hex() for row in rejected))
                    self.assertTrue(all(row["stdout"] == "owned partial" for row in rejected))
                elif broken == "diagnostic":
                    self.assertTrue(all(row["native_vm_diagnostics"] == ["[battle.anim] owned aborted task"] for row in rejected))


if __name__ == "__main__":
    unittest.main()
