#!/usr/bin/env python3
"""Run owned-window VSync pacing measurements through the local QA guard."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
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
    try:
        from qa_storage import qa_source, qa_cache, qa_profile, qa_run
    except ImportError:
        parser.error('QA storage guard is required; provide --qa-tools')
    qa_source(root)
    qa_source(args.love.resolve())
    qa_cache(args.report.parent)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    identity = 'oasc-gen2recomp-qa-frame-pacing-' + str(time.time_ns())
    qa_profile(Path.home() / 'Library/Application Support/LOVE' / identity)
    result = qa_run([str(args.love.resolve()), str(root / 'tools/frame-pacing-check')],
                    cwd=root, env=dict(os.environ, POKEPORT_IDENTITY=identity,
                                       FRAME_PACING_REPO=str(root), FRAME_PACING_QA_GUARDED='1'),
                    capture_output=True, text=True, timeout=90)
    args.report.with_suffix('.log').write_text(result.stdout + result.stderr)
    records = [line.removeprefix('P1_NATIVE_RESULT ') for line in result.stdout.splitlines()
               if line.startswith('P1_NATIVE_RESULT ')]
    if result.returncode or len(records) != 1:
        raise RuntimeError('native pacing probe failed; see ' + str(args.report.with_suffix('.log')))
    report = json.loads(records[0])
    report['source'] = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    files = ('main.lua', 'src/core/FrameCap.lua', 'src/core/FrameProfile.lua',
             'tools/frame-pacing-check/main.lua', 'tools/frame-pacing-check/conf.lua')
    report['sha256'] = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in files}
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
