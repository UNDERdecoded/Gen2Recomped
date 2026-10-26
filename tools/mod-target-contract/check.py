"""Compare edition claims using the identical consumer on independent hosts."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
try:
    from qa_storage import qa_source, qa_run
except ImportError:
    # Standalone hosts need only Python and Lua; managed local hosts retain leases.
    qa_source = lambda path: path
    qa_run = subprocess.run

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--reference", required=True, type=Path)
parser.add_argument("--lua", default="luajit")
parser.add_argument("--report", type=Path)
args = parser.parse_args()
reference = args.reference.resolve()
consumer = ROOT / "tests/mod_targets/consumer.lua"
qa_source(ROOT)
qa_source(reference)
runtime = Path(args.lua)
if runtime.is_absolute():
    qa_source(runtime.parent)
catalogues = {}
for name, root in (("reference", reference), ("native", ROOT)):
    run = qa_run([args.lua, str(consumer), "--catalog"], cwd=root, text=True,
                 capture_output=True, timeout=60)
    lines = [line[len("TARGET_CATALOG "):] for line in run.stdout.splitlines()
             if line.startswith("TARGET_CATALOG ")]
    if run.returncode or len(lines) != 1:
        raise SystemExit(f"{name} catalogue failed:\n{run.stdout}{run.stderr}")
    catalogues[name] = json.loads(lines[0])
versions = [version for version in catalogues["native"] if version in catalogues["reference"]]
if not versions:
    raise SystemExit("Hosts share no known editions")
values = {}
for name, root in (("reference", reference), ("native", ROOT)):
    run = qa_run([args.lua, str(consumer), *versions], cwd=root, text=True,
                 capture_output=True, timeout=60)
    lines = [line[len("TARGET_CONTRACT "):] for line in run.stdout.splitlines()
             if line.startswith("TARGET_CONTRACT ")]
    if run.returncode or len(lines) != 1:
        raise SystemExit(f"{name} consumer failed:\n{run.stdout}{run.stderr}")
    values[name] = json.loads(lines[0])
if values["reference"] != values["native"]:
    raise SystemExit("Edition-claim results differ:\n" + json.dumps(values, indent=2))
report = {"consumerSha256": hashlib.sha256(consumer.read_bytes()).hexdigest(),
          "versions": versions, "comparisons": len(values["native"]),
          "referenceCommit": subprocess.check_output(["git", "-C", str(reference), "rev-parse", "HEAD"], text=True).strip(),
          "results": values["native"]}
if args.report:
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
print(f"PASS: {len(values['native'])} identical edition decisions across {len(versions)} shared games")
