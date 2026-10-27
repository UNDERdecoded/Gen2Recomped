#!/usr/bin/env python3
"""Check old require contracts on both engines without rewriting the consumer."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

PIN = '37a49b31f458d51ea9e00b90f2a247272ad09cb8'


def run(command, cwd):
    return subprocess.check_output(command, cwd=cwd, text=True)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--gen1', type=Path, required=True)
    p.add_argument('--gen2', type=Path, default=Path(__file__).resolve().parents[2])
    p.add_argument('--lua', default='luajit')
    p.add_argument('--edition', action='append', choices=['firered', 'leafgreen', 'emerald', 'ruby', 'sapphire'],
                   help='Host editions to compare (default: all five; requires their cartridge support)')
    p.add_argument('--native-cache', type=Path, help='Optional QA-only cache root with edition/data/generated/maps.lua')
    p.add_argument('--native-edition', action='append', choices=['firered', 'leafgreen', 'emerald', 'ruby', 'sapphire'],
                   help='Native cache editions to check (default: all five)')
    p.add_argument('--report', type=Path)
    a = p.parse_args()
    gen1, gen2 = a.gen1.resolve(), a.gen2.resolve()
    git = lambda *args: run(['git', *args], gen1).strip()
    if git('rev-parse', 'HEAD') != PIN or git('status', '--porcelain'):
        p.error('Gen1 must be clean at ' + PIN)
    folder = gen2 / 'tools/gen1-map-compat'
    generated = run([a.lua, str(folder / 'export.lua')], gen1)
    names = (gen2 / 'src/compat/gen1/MapNames.lua').read_text()
    if names.split('\n', 2)[2] != generated:
        raise RuntimeError('committed names differ from original public Gen1 catalog')
    editions = a.edition or ['firered', 'leafgreen', 'emerald', 'ruby', 'sapphire']
    command = [a.lua, str(folder / 'consumer.lua'), str(gen2), ','.join(editions)]
    expected, actual = run(command, gen1), run(command, gen2)
    if expected != actual:
        raise RuntimeError('old map catalog consumer differs between engines')
    checks = {line.split('\t')[0]: int(line.split('\t')[2])
              for line in actual.splitlines() if '\tchecks\t' in line}
    assert len(checks) == len(set(editions))
    native = []
    if a.native_cache:
        for edition in a.native_edition or checks:
            path = a.native_cache.resolve() / edition / 'data/generated/maps.lua'
            output = run([a.lua, str(folder / 'native.lua'), edition, str(path)], gen2)
            version, matched, unknown = output.strip().split('\t')
            native.append(dict(edition=version, matched=int(matched), unknown=int(unknown),
                               mapsSha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    if git('status', '--porcelain'):
        raise RuntimeError('reference changed during check')
    paths = [*sorted((gen2 / 'src/compat/gen1').glob('*.lua')),
             gen2 / 'src/import/gba/map_catalog.lua',
             gen2 / 'tests/engine/gen1_map_identity.lua',
             *sorted(folder.glob('*.lua')), Path(__file__)]
    report = dict(gen1Commit=PIN, checksPerHost=checks,
                  consumerSha256=hashlib.sha256(actual.encode()).hexdigest(),
                  nativeImports=native, mapRecordsRenamed=False, playerSavesUsed=False,
                  originalOrigamiLoads=False, fullLegacyMapContract=False,
                  sourceSha256={str(path.relative_to(gen2)): hashlib.sha256(path.read_bytes()).hexdigest()
                                for path in paths})
    if a.report:
        a.report.parent.mkdir(parents=True, exist_ok=True)
        a.report.write_text(json.dumps(report, indent=2) + '\n')
    print('PASS', sum(checks.values()), 'checks per engine;', len(native), 'native imports')


if __name__ == '__main__':
    main()
