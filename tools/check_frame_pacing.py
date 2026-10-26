#!/usr/bin/env python3
"""Run owned-window VSync pacing measurements through the local QA guard."""
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
    workload = parser.add_mutually_exclusive_group()
    workload.add_argument('--gc', action='store_true', help='compare fixed-step GC with the P2 idle budget')
    workload.add_argument('--hot-path', action='store_true', help='compare actual native update/draw dependency dispatch')
    workload.add_argument('--world-draw', action='store_true', help='compare native world entity/FX dispatch over synthetic content')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(args.qa_tools or root / 'tools'))
    try:
        from qa_storage import qa_source, qa_cache, qa_profile, qa_run
    except ImportError:
        parser.error('QA storage guard is required; provide --qa-tools')
    qa_source(root)
    qa_source(args.love.resolve())
    files = ('main.lua', 'src/core/FrameCap.lua', 'src/core/FrameProfile.lua',
             'tools/frame-pacing-check/main.lua', 'tools/frame-pacing-check/conf.lua')
    if args.gc:
        files += ('src/core/Performance.lua', 'src/core/GCFrameBudget.lua', 'src/core/Game.lua',
                  'tools/frame-pacing-check/gc.lua')
    if args.hot_path:
        files += ('src/core/Game.lua', 'src/core/HotModules.lua', 'src/core/Performance.lua',
                  'src/render/Renderer.lua', 'src/render/PaletteFX.lua', 'tools/frame-pacing-check/hot.lua')
    if args.world_draw:
        files += ('src/core/Game.lua', 'src/core/Performance.lua', 'src/core/HotModules.lua',
                  'src/world/OverworldController.lua', 'src/render/Renderer.lua',
                  'src/render/PaletteFX.lua', 'src/render/Pipelines.lua',
                  'tests/world_draw/fixture.lua', 'tools/frame-pacing-check/world.lua')
    hashes = {name: hashlib.sha256((root / name).read_bytes()).hexdigest() for name in files}
    source = qa_run(['git', 'rev-parse', 'HEAD'], cwd=root, text=True,
                    capture_output=True, check=True).stdout.strip()
    qa_cache(args.report.parent)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    identity = 'oasc-gen2recomp-qa-frame-pacing-' + str(time.time_ns())
    qa_profile(Path.home() / 'Library/Application Support/LOVE' / identity)
    result = qa_run([str(args.love.resolve()), str(root / 'tools/frame-pacing-check')],
                    cwd=root, env=dict(os.environ, POKEPORT_IDENTITY=identity,
                                       FRAME_PACING_REPO=str(root), FRAME_PACING_QA_GUARDED='1',
                                       FRAME_PACING_GC='1' if args.gc else '0',
                                       FRAME_PACING_HOT='1' if args.hot_path else '0',
                                       FRAME_PACING_WORLD='1' if args.world_draw else '0'),
                    capture_output=True, text=True, timeout=90)
    args.report.with_suffix('.log').write_text(result.stdout + result.stderr)
    prefix = 'P4_NATIVE_RESULT ' if args.world_draw else 'P3_NATIVE_RESULT ' if args.hot_path else 'P2_NATIVE_RESULT ' if args.gc else 'P1_NATIVE_RESULT '
    records = [line.removeprefix(prefix) for line in result.stdout.splitlines() if line.startswith(prefix)]
    if result.returncode or len(records) != 1:
        raise RuntimeError('native pacing probe failed; see ' + str(args.report.with_suffix('.log')))
    report = json.loads(records[0])
    if any(hashlib.sha256((root / name).read_bytes()).hexdigest() != digest for name, digest in hashes.items()):
        raise RuntimeError('Measured source changed during the pacing probe')
    if qa_run(['git', 'rev-parse', 'HEAD'], cwd=root, text=True,
              capture_output=True, check=True).stdout.strip() != source:
        raise RuntimeError('Measured commit changed during the pacing probe')
    report['source'] = source
    report['sha256'] = hashes
    report['minimumFreeGiB'] = 20
    report['playerProfilesUsed'] = False
    args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__':
    main()
