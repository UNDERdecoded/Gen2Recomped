#!/usr/bin/env python3
"""Compare all public GBA map identities on two real native checkouts."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

REFERENCE = '535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91'


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--gen1', type=Path, required=True)
    parser.add_argument('--gen2', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--lua', default=os.environ.get('LUA', 'luajit'))
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    ref, native = args.gen1.resolve(), args.gen2.resolve()
    if git(ref, 'rev-parse', 'HEAD') != REFERENCE or git(ref, 'status', '--porcelain'):
        parser.error('use a clean separate reference at ' + REFERENCE)
    capture = native / 'tools/gba-map-check/capture.lua'
    result = subprocess.run([args.lua, str(capture), str(ref)], cwd=ref,
                            capture_output=True, text=True, timeout=60, check=True)
    observed = json.loads(result.stdout)
    records = []
    with tempfile.TemporaryDirectory(prefix='native-map-catalog-') as directory:
        path = Path(directory) / 'observations.json'
        path.write_text(json.dumps(observed))
        for version in ('firered', 'leafgreen', 'emerald', 'ruby', 'sapphire'):
            outputs = {}
            counts = {}
            for backend, engine in (('gen1', ref), ('gen2', native)):
                run = subprocess.run([args.lua, str(native / 'tests/gba_maps/worker.lua'),
                                      str(engine), str(native / 'tests/gba_maps/consumer.lua'),
                                      str(path), version, backend], cwd=engine,
                                     capture_output=True, text=True, timeout=60)
                if run.returncode:
                    raise RuntimeError(f'{backend}/{version}:\n{run.stdout}{run.stderr}')
                payloads = [line.removeprefix('GBA_MAP_CONTRACT ') for line in run.stdout.splitlines()
                            if line.startswith('GBA_MAP_CONTRACT ')]
                assert len(payloads) == 1
                outputs[backend] = json.loads(payloads[0])
                summary = re.search(r'(\d+)/(\d+) checks passed', run.stdout)
                assert summary and summary.group(1) == summary.group(2)
                counts[backend] = int(summary.group(1))
            assert outputs['gen1'] == outputs['gen2'], version
            records.append(dict(version=version, slots=len(observed[version]), checks=counts))
            print('PASS', version, len(observed[version]), 'native map identities', counts)
    report = dict(reference=REFERENCE, nativeSource=git(native, 'rev-parse', 'HEAD'),
                  nativeTrackedChanges=bool(git(native, 'status', '--porcelain', '--untracked-files=no')),
                  observationsSha256=hashlib.sha256(json.dumps(observed, sort_keys=True).encode()).hexdigest(),
                  profiles=records, playableProfilesAdded=False)
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
