#!/usr/bin/env python3
"""Exercise native mod jobs with real LOVE threads in an owned data identity."""
# Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import argparse
import atexit
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import sys
import time
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PAYLOAD = {
    'main.lua': 'tests/native_jobs_runtime/main.lua',
    'conf.lua': 'tests/native_jobs_runtime/conf.lua',
    **{name: name for name in ('src/mods/job_worker.lua', 'src/mods/JobData.lua',
                              'src/import/PackData.lua', 'src/import/LuaWriter.lua')},
}


def qualify(executable, output, run=subprocess.run, profile=None):
    inputs = set(PAYLOAD.values()) | {
        'src/mods/Job.lua', 'src/mods/JobCache.lua', 'src/mods/Manifest.lua',
        'src/mods/Loader.lua', 'src/mods/ImportAccess.lua', 'src/mods/Storage.lua',
        'src/import/PackPublish.lua', 'src/import/Importers.lua', 'src/import/CacheFs.lua',
    }
    snapshots = {name: (ROOT / name).read_bytes() for name in sorted(inputs)}
    output.mkdir(parents=True, exist_ok=False)
    identity = 'oasc-native-mod-workers-qa-' + uuid.uuid4().hex
    if profile:
        profile(Path.home() / 'Library/Application Support/LOVE' / identity)
    payload = output / 'native-jobs.love'
    with zipfile.ZipFile(payload, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
        for target, source in PAYLOAD.items():
            archive.writestr(target, snapshots[source])
    env = {key: value for key, value in os.environ.items() if not key.startswith('POKEPORT_')}
    env.update(JOB_ENGINE_ROOT=str(ROOT), JOB_QA_IDENTITY=identity)
    result = run([str(executable), str(payload)], cwd=ROOT, env=env,
                 capture_output=True, text=True, timeout=35)
    log = result.stdout + result.stderr
    (output / 'runtime.log').write_text(log, encoding='utf-8')
    print(log, end='', flush=True)
    result.check_returncode()
    match = re.search(r'Native mod workers: ([0-9]+) checks PASS;', result.stdout)
    if not match:
        raise RuntimeError('real worker qualification marker missing')
    version = run([str(executable), '--version'], capture_output=True, text=True,
                  timeout=10, check=True).stdout.strip()
    if any((ROOT / name).read_bytes() != data for name, data in snapshots.items()):
        raise RuntimeError('worker qualification inputs changed during the run')
    report = {'passed': True, 'checks': int(match[1]), 'runtime': version,
              'platform': platform.system(), 'machine': platform.machine(),
              'scope': 'real headless CPU workers, scoped I/O and cancellation; no GPU or gameplay',
              'inputsSha256': {name: hashlib.sha256(data).hexdigest()
                               for name, data in snapshots.items()}}
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--love', type=Path, required=True, help='LOVE executable (lovec.exe on Windows)')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--qa-tools', type=Path, help='directory containing the local qa_storage helpers')
    args = parser.parse_args()
    executable = args.love.resolve(strict=True)
    output = (args.output or ROOT / '.local/qa' /
              ('gen2-native-mod-workers-' + str(time.time_ns())) / 'candidate').resolve()
    run, profile = subprocess.run, None
    if os.name != 'nt' and not os.getenv('GITHUB_ACTIONS'):
        if args.qa_tools:
            sys.path.insert(0, str(args.qa_tools.resolve(strict=True)))
        from qa_storage import Storage
        manager = Storage(ROOT)
        atexit.register(manager.close)
        qa_source, qa_cache, qa_copy = manager.source, manager.cache, manager.copy
        qa_profile, qa_run = manager.destination, manager.run
        for source in (ROOT, executable, Path(sys.executable)):
            qa_source(source)
        qa_cache(output.parent)
        qa_copy(output)
        run, profile = qa_run, qa_profile
    print(json.dumps(qualify(executable, output, run, profile)), flush=True)


if __name__ == '__main__':
    main()
