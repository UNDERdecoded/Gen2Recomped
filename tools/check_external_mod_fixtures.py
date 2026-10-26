#!/usr/bin/env python3
"""Authenticate external packages and exercise their unchanged entrypoints."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--qa-tools', type=Path, help='directory providing qa_storage.py and its companion modules')
    parser.add_argument('--lua', default=os.environ.get('LUA', 'luajit'))
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--phase', choices=('complete', 'aliases'), default='complete')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    reference = args.reference.resolve()
    if args.qa_tools:
        sys.path.insert(0, str(args.qa_tools.resolve()))
    try:
        from qa_storage import qa_source, qa_cache, qa_run
    except ImportError:
        parser.error('local QA storage guard is required; provide --qa-tools')
    qa_source(root)
    qa_source(reference)
    qa_cache(args.report.parent)
    index = json.loads((root / 'tests/fixtures/upstream_mods/index.json').read_text())
    head = subprocess.check_output(['git', '-C', str(reference), 'rev-parse', 'HEAD'], text=True).strip()
    if head != index['reference']:
        parser.error('reference checkout does not match the authenticated commit')
    results = []
    for fixture in index['fixtures']:
        package = reference / 'mods' / fixture['path']
        files = {str(p.relative_to(package)): hashlib.sha256(p.read_bytes()).hexdigest()
                 for p in package.rglob('*') if p.is_file()}
        if files != fixture['files']:
            raise RuntimeError('external package bytes differ: ' + fixture['path'])
        if fixture['path'].startswith('examples/example_'):
            shipped = root / 'mods' / fixture['path']
            for name, digest in fixture['files'].items():
                if hashlib.sha256((shipped / name).read_bytes()).hexdigest() != digest:
                    raise RuntimeError('shipped gallery bytes differ: ' + fixture['path'] + '/' + name)
        versions = (('red', 'firered') if fixture['path'] == 'example_mew_starter' else
                    ('red', 'gold', 'crystal', 'firered') if fixture['path'] == 'mystery_dungeon_follower' else ('red',))
        for version in versions:
            run = qa_run([args.lua, str(root / 'tests/fixtures/upstream_mods/worker.lua'),
                          str(reference), fixture['path'], version], cwd=root,
                         capture_output=True, text=True, timeout=60)
            lines = [line[len('FIXTURE_RESULT '):] for line in run.stdout.splitlines()
                     if line.startswith('FIXTURE_RESULT ')]
            if len(lines) != 1:
                raise RuntimeError(f"{fixture['path']}/{version}: missing worker result\n{run.stdout}{run.stderr}")
            result = json.loads(lines[0])
            result['exit_code'] = run.returncode
            expected = ('Compatibility module src.import.pmd.Sprite is unavailable in this engine; '
                        'affected mods: mystery_dungeon_follower')
            result['accepted_gap'] = (args.phase == 'aliases' and fixture['path'] == 'mystery_dungeon_follower'
                                      and run.returncode == 1 and not result['loaded']
                                      and result['error'].endswith(expected))
            results.append(result)
            print(('EXPECTED GAP ' if result['accepted_gap'] else
                   'PASS ' if result['loaded'] and not run.returncode else 'FAIL ') +
                  fixture['path'] + '/' + version + ': ' + result['error'], flush=True)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps({'reference': head, 'phase': args.phase, 'fixtures': results}, indent=2) + '\n')
    return 0 if all((r['loaded'] and r['exit_code'] == 0) or r['accepted_gap'] for r in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
