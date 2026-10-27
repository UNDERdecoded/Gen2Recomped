#!/usr/bin/env python3
"""Compare compatibility cell semantics against a clean pinned reference."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

PIN = '37a49b31f458d51ea9e00b90f2a247272ad09cb8'


def run(args, cwd):
    return subprocess.check_output(args, cwd=cwd, text=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--reference', required=True, type=Path)
    p.add_argument('--engine', type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument('--lua', default='luajit')
    p.add_argument('--report', type=Path)
    args = p.parse_args()
    reference, engine = args.reference.resolve(), args.engine.resolve()
    git = lambda *a: run(['git', *a], reference).strip()
    if git('rev-parse', 'HEAD') != PIN or git('status', '--porcelain'):
        p.error('reference must be clean at ' + PIN)
    folder = engine / 'tools/metatile-compat'
    metadata = run([args.lua, str(folder / 'export.lua')], reference)
    committed = (engine / 'src/compat/gen1/MetatileNames.lua').read_text()
    if committed.split('\n', 2)[2] != metadata:
        raise RuntimeError('public identifier metadata differs from reference')
    expected = run([args.lua, str(folder / 'consumer.lua'), 'reference'], reference)
    actual = run([args.lua, str(folder / 'consumer.lua'), 'native'], engine)
    if json.loads(actual) != json.loads(expected):
        raise RuntimeError(f'cell semantics differ: reference={expected.strip()} native={actual.strip()}')
    result = json.loads(actual)
    assert result['checks'] > 500000
    if git('status', '--porcelain'):
        raise RuntimeError('reference changed during check')
    paths = [*sorted((engine / 'src/compat/gen1').glob('Metatile*.lua')),
             engine / 'src/compat/gen1/CollisionClass.lua',
             engine / 'tests/engine/compatibility_cell_semantics.lua', *sorted(folder.glob('*.*'))]
    report = dict(referenceCommit=PIN, comparison=result,
                  nativeGridModified=False, playerProfilesUsed=False,
                  nativeMapViewInstalled=False, fullCompatibility=False,
                  sourceSha256={str(f.relative_to(engine)): hashlib.sha256(f.read_bytes()).hexdigest()
                                for f in paths if f.is_file()})
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS', result['checks'], 'cell-semantics comparisons per host')


if __name__ == '__main__':
    main()
