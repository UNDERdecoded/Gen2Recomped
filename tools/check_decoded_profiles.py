#!/usr/bin/env python3
"""Measure native script execution with an owned LÖVE window and F11 sections."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--love', type=Path, required=True)
    parser.add_argument('--qa-tools', type=Path)
    parser.add_argument('--baseline', required=True, help='local pre-M5 Git commit')
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(args.qa_tools or root / 'tools'))
    from qa_storage import qa_source, qa_cache, qa_profile, qa_run
    qa_source(root)
    qa_source(args.love.resolve())
    qa_cache(args.report.parent)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    files = ('src/script/ScriptRunner.lua', 'src/script/DecodedScript.lua',
             'src/script/Gen2ScriptVM.lua', 'src/script/Gen3ScriptVM.lua',
             'src/script/Commands.lua', 'src/mods/Loader.lua', 'src/mods/DecodedCallbacks.lua',
             'tools/decoded-profile-check/main.lua', 'tools/decoded-profile-check/conf.lua')
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in files}
    before = qa_run(['git', 'rev-parse', '--verify', args.baseline + '^{commit}'], cwd=root,
                    capture_output=True, text=True, check=True).stdout.strip()
    blob = qa_run(['git', 'show', before + ':src/script/ScriptRunner.lua'], cwd=root,
                  capture_output=True, check=True).stdout
    baseline = args.report.parent / 'baseline-runner.lua'
    baseline.write_bytes(blob)
    identity = 'oasc-gen2recomp-qa-decoded-profile-' + str(time.time_ns())
    qa_profile(Path.home() / 'Library/Application Support/LOVE' / identity)
    result = qa_run([str(args.love.resolve()), str(root / 'tools/decoded-profile-check')],
                    cwd=root, env=dict(os.environ, POKEPORT_IDENTITY=identity,
                                      DECODED_PROFILE_REPO=str(root), DECODED_PROFILE_QA_GUARDED='1',
                                      DECODED_PROFILE_BASELINE=str(baseline.resolve())),
                    capture_output=True, text=True, timeout=90)
    args.report.with_suffix('.log').write_text(result.stdout + result.stderr)
    records = [line[len('M5_NATIVE_RESULT '):] for line in result.stdout.splitlines()
               if line.startswith('M5_NATIVE_RESULT ')]
    if result.returncode or len(records) != 1:
        raise RuntimeError('native profile probe failed; see ' + str(args.report.with_suffix('.log')))
    if any(hashlib.sha256((root / name).read_bytes()).hexdigest() != digest for name, digest in hashes.items()):
        raise RuntimeError('measured source changed during the probe')
    report = json.loads(records[0])
    report.update(baseline=before, baselineRunnerSha256=hashlib.sha256(blob).hexdigest(),
                  sha256=hashes, minimumFreeGiB=20, playerProfilesUsed=False)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
