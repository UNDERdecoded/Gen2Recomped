#!/usr/bin/env python3
"""Run owned native shadow geometry in an isolated QA profile."""
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
    names = [f'mods/DRAMATIC_SHAPE/lib/{n}.lua' for n in
             ('ShadowMap', 'WorldShadows', 'VoxelScene', 'Voxel3D', 'Tier')]
    names += ['mods/DRAMATIC_SHAPE/manifest.json', 'mods/DRAMATIC_SHAPE/main.lua',
              'tools/world-shadow-check/main.lua', 'tools/world-shadow-check/conf.lua']
    hashes = {n: hashlib.sha256((root / n).read_bytes()).hexdigest() for n in names}
    identity = f'oasc-world-shadow-qa-{time.time_ns()}'
    qa_profile(Path.home() / 'Library/Application Support/LOVE' / identity)
    result = qa_run([str(args.love.resolve()), str(root / 'tools/world-shadow-check')],
                    cwd=root, env=dict(os.environ, WORLD_SHADOW_QA_GUARDED='1',
                    WORLD_SHADOW_QA_ROOT=str(root), WORLD_SHADOW_QA_OUT=str(args.report.parent.resolve()), POKEPORT_IDENTITY=identity),
                    capture_output=True, text=True, timeout=90)
    args.report.with_suffix('.log').write_text(result.stdout + result.stderr)
    rows = [s.removeprefix('WORLD_SHADOW_RESULT ') for s in result.stdout.splitlines()
            if s.startswith('WORLD_SHADOW_RESULT ')]
    if result.returncode or len(rows) != 1:
        raise RuntimeError('native shadow probe failed; see its log')
    if any(hashlib.sha256((root / n).read_bytes()).hexdigest() != h for n, h in hashes.items()):
        raise RuntimeError('measured source changed during the probe')
    report = json.loads(rows[0])
    report.update(sha256=hashes, playerProfilesUsed=False)
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
