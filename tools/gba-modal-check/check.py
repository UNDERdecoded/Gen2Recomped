#!/usr/bin/env python3
"""Compare one unchanged GBA modal consumer on two real native engines."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

GEN1_REF = '535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91'


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gen1', type=Path, required=True)
    parser.add_argument('--gen2', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--lua', default=os.environ.get('LUA', 'luajit'))
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    gen1, gen2 = args.gen1.resolve(), args.gen2.resolve()
    if git(gen1, 'rev-parse', 'HEAD') != GEN1_REF or git(gen1, 'status', '--porcelain'):
        parser.error('use a clean separate Gen1 reference at ' + GEN1_REF)
    fixture = gen2 / 'tests/gba_modal'
    rows = []
    for version in ('firered', 'emerald'):
        results = {}
        for backend, engine in (('gen1', gen1), ('gen2', gen2)):
            run = subprocess.run([args.lua, str(fixture / 'worker.lua'), str(engine), backend,
                                  str(fixture / 'consumer.lua'), version], cwd=engine,
                                 text=True, capture_output=True, timeout=60)
            output = [line[len('GBA_MODAL_CONTRACT '):] for line in run.stdout.splitlines()
                      if line.startswith('GBA_MODAL_CONTRACT ')]
            if run.returncode or len(output) != 1:
                raise RuntimeError(f'{backend}/{version}:\n{run.stdout}{run.stderr}')
            results[backend] = json.loads(output[0])
        if results['gen1'] != results['gen2']:
            raise RuntimeError(f'{version} differs: {results}')
        rows.append(dict(version=version, result=results['gen2']))
        print('PASS identical native GBA modal consumer:', version)
    report = dict(gen1_ref=GEN1_REF, gen2_ref=git(gen2, 'rev-parse', 'HEAD'),
                  gen2_tracked_changes=bool(git(gen2, 'status', '--porcelain', '--untracked-files=no')),
                  fixture_sha256={p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                  for p in sorted(fixture.glob('*.lua'))}, comparisons=rows)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
