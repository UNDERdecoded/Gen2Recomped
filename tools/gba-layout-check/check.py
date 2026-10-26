#!/usr/bin/env python3
"""Run one unchanged layout consumer in two separate native Lua processes."""
import argparse
import hashlib
import json
import os
import re
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
    fixture = gen2 / 'tests/gba_layout'
    comparisons = []
    runs = []
    for version in ('firered', 'emerald'):
        results = {}
        for backend, engine in (('gen1', gen1), ('gen2', gen2)):
            run = subprocess.run([args.lua, str(fixture / 'worker.lua'), str(engine),
                                  str(fixture / 'consumer.lua'), version, backend],
                                 cwd=engine, capture_output=True, text=True, timeout=60)
            rows = [line.removeprefix('GBA_LAYOUT_CONTRACT ') for line in run.stdout.splitlines()
                    if line.startswith('GBA_LAYOUT_CONTRACT ')]
            if run.returncode or len(rows) != 1:
                raise RuntimeError(f'{backend}/{version}:\n{run.stdout}{run.stderr}')
            results[backend] = json.loads(rows[0])
            summary = re.search(r'(\d+)/(\d+) checks passed', run.stdout)
            if not summary or summary.group(1) != summary.group(2):
                raise RuntimeError(f'{backend}/{version}: missing passing assertion count')
            runs.append(dict(backend=backend, version=version, checks=int(summary.group(1))))
            print(f'PASS native layout consumer: {backend}/{version}')
        if results['gen1'] != results['gen2']:
            raise RuntimeError(f'{version} differs: {results}')
        comparisons.append(dict(version=version, result=results['gen2']))
    paths = list(fixture.glob('*.lua')) + [gen2 / 'src/core/game3/layout_native.lua',
                                         gen2 / 'src/world/Map.lua']
    report = dict(gen1_ref=GEN1_REF, gen2_ref=git(gen2, 'rev-parse', 'HEAD'),
                  gen2_tracked_changes=bool(git(gen2, 'status', '--porcelain', '--untracked-files=no')),
                  file_sha256={str(p.relative_to(gen2)): hashlib.sha256(p.read_bytes()).hexdigest()
                               for p in sorted(paths)}, runs=runs, comparisons=comparisons)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
