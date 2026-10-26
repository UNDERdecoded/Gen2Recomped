#!/usr/bin/env python3
"""Run owned native UI quad draws in an isolated QA profile."""
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
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--qa-tools', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(args.qa_tools or root / 'tools'))
    from qa_storage import qa_source, qa_cache, qa_profile, qa_run
    qa_source(root)
    qa_source(args.love.resolve())
    qa_cache(args.report.parent)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    names = ['src/core/Performance.lua', 'src/render/UiQuad.lua', 'src/render/TextBox.lua',
             'src/ui/Gen3BagMenu.lua', 'src/ui/Gen3BoxMenu.lua',
             'tools/low-tier-check/main.lua', 'tools/low-tier-check/conf.lua']
    hashes = {n: hashlib.sha256((root / n).read_bytes()).hexdigest() for n in names}
    identity = f'oasc-low-tier-qa-{time.time_ns()}'
    qa_profile(Path.home() / 'Library/Application Support/LOVE' / identity)
    result = qa_run([str(args.love.resolve()), str(root / 'tools/low-tier-check')],
                    cwd=root, env=dict(os.environ, LOW_TIER_QA_GUARDED='1',
                    LOW_TIER_QA_ROOT=str(root), LOW_TIER_QA_OUT=str(args.report.parent.resolve()), POKEPORT_IDENTITY=identity),
                    capture_output=True, text=True, timeout=90)
    args.report.with_suffix('.log').write_text(result.stdout + result.stderr)
    rows = [s.removeprefix('LOW_TIER_RESULT ') for s in result.stdout.splitlines()
            if s.startswith('LOW_TIER_RESULT ')]
    if result.returncode or len(rows) != 1:
        raise RuntimeError('native LOW tier probe failed; see its log')
    if any(hashlib.sha256((root / n).read_bytes()).hexdigest() != h for n, h in hashes.items()):
        raise RuntimeError('measured source changed during the probe')
    report = json.loads(rows[0])
    report.update(sha256=hashes, playerProfilesUsed=False)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
