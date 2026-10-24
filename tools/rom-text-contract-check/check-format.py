#!/usr/bin/env python3
"""Compare native GB/Gen-2 prose formatting before wiring the public registry."""
import argparse
import json
import os
from pathlib import Path
import subprocess

REFERENCE = '535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91'


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--gen1', type=Path, required=True)
    p.add_argument('--gen2', type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument('--lua', default=os.environ.get('LUA', 'luajit'))
    p.add_argument('--report', type=Path)
    a = p.parse_args()
    source, host = a.gen1.resolve(), a.gen2.resolve()
    if git(source, 'rev-parse', 'HEAD') != REFERENCE or git(source, 'status', '--porcelain'):
        p.error('Gen1 must be clean at ' + REFERENCE)
    results = []
    for version in ['red', 'gold', 'silver', 'crystal']:
        paired = []
        for backend, engine in [('gen1', source), ('gen2', host)]:
            r = subprocess.run([a.lua, str(host / 'tests/rom_text/format_worker.lua'), str(host), version],
                               cwd=engine, text=True, capture_output=True, timeout=30)
            rows = [x[len('ROM_PROSE_FORMAT '):] for x in r.stdout.splitlines()
                    if x.startswith('ROM_PROSE_FORMAT ')]
            if r.returncode or len(rows) != 1:
                raise RuntimeError(f'{backend}/{version}: {r.stdout}{r.stderr}')
            observation = json.loads(rows[0])
            paired.append(observation)
            results.append({'backend': backend, 'version': version, 'observations': observation})
        assert paired[0] == paired[1], f'native prose-format mismatch for {version}'
        print(f'PASS {version}: {len(paired[0])} native prose-format observations')
    if a.report:
        a.report.write_text(json.dumps({'reference_ref': REFERENCE, 'host_ref': git(host, 'rev-parse', 'HEAD'),
            'host_dirty': bool(git(host, 'status', '--porcelain')), 'results': results}, indent=2) + '\n')


if __name__ == '__main__':
    main()
