#!/usr/bin/env python3
"""Qualify a candidate library inside a copied, hash-pinned LOVE12 host."""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import platform
import shutil
import subprocess
import sys
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
PIN = 'a4c064539ea931274d407e1249b4bb575424a0f4'
RUNTIMES = {
    'Windows': ('1f4c6997bd93502f986f5187d877da84247617eede89d8140bcbf570bd07ea22', 'love-12.0-win64.zip'),
    'Darwin': ('f70f60d162eda6931b0b28e2b094b83b741986f0feac08d33a10be7c57e724f8', 'love-macos.zip'),
}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_archive(archive):
    for name in archive.namelist():
        path = PurePosixPath(name.replace('\\', '/'))
        if path.is_absolute() or '..' in path.parts or (path.parts and ':' in path.parts[0]):
            raise ValueError('unsafe runtime archive path')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime-archive', required=True, type=Path)
    parser.add_argument('--qualification', required=True, type=Path)
    parser.add_argument('--library', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    host = platform.system()
    if host not in RUNTIMES:
        parser.error('this copied-host gate supports Windows and macOS')
    archive, qualification, library, output = [path.resolve() for path in
        (args.runtime_archive, args.qualification, args.library, args.output)]
    expected, inner_name = RUNTIMES[host]
    if digest(archive) != expected:
        parser.error('runtime archive differs from the pinned LOVE12 artifact')
    qualified = json.loads(qualification.read_text())
    extended = next((row for row in qualified.get('variants', []) if row['name'] == 'extended'), {})
    if not (qualified.get('passed') and qualified.get('luaJitSource') == PIN
            and qualified.get('platform') == host and extended.get('capacity') == 120
            and extended.get('engineSuites', 0) > 0 and extended.get('librarySha256') == digest(library)):
        parser.error('a passing same-platform engine qualification for this library is required')
    if output.exists():
        parser.error('output already exists; use a new disposable candidate directory')
    run = subprocess.run
    profile = None
    if os.name != 'nt' and not os.getenv('GITHUB_ACTIONS') and (ROOT / 'tools/qa_storage.py').is_file():
        sys.path.insert(0, str(ROOT / 'tools'))
        from qa_storage import qa_source, qa_copy, qa_cache, qa_profile, qa_run
        for source in (ROOT, HERE, archive, qualification, library, Path(sys.executable)):
            qa_source(source)
        qa_cache(output.parent)
        qa_copy(output)
        run, profile = qa_run, qa_profile
    output.mkdir(parents=True, exist_ok=False)
    project = output / 'probe'
    project.mkdir()
    for source, target in (('love-conf.lua', 'conf.lua'), ('love-main.lua', 'main.lua'),
                           ('love-thread.lua', 'thread.lua'), ('check.lua', 'check.lua')):
        shutil.copy2(HERE / source, project / target)
    (project / 'src/link').mkdir(parents=True)
    shutil.copy2(ROOT / 'src/link/Json.lua', project / 'src/link/Json.lua')
    with zipfile.ZipFile(archive) as packed:
        safe_archive(packed)
        if packed.namelist().count(inner_name) != 1:
            raise ValueError('pinned inner runtime is absent or ambiguous')
        inner = output / inner_name
        inner.write_bytes(packed.read(inner_name))
    unpacked = output / 'runtime'
    unpacked.mkdir()
    with zipfile.ZipFile(inner) as packed:
        safe_archive(packed)
        if host == 'Windows':
            packed.extractall(unpacked)
    if host == 'Darwin':
        run(['unzip', '-q', str(inner), '-d', str(unpacked)], check=True)
        apps = list(unpacked.rglob('love.app'))
        if len(apps) != 1:
            raise ValueError('expected one copied LOVE app')
        app = apps[0]
        executable = app / 'Contents/MacOS/love'
        target = app / 'Contents/Frameworks/Lua.framework/Versions/A/Lua'
    else:
        executables = list(unpacked.rglob('love.exe'))
        if len(executables) != 1:
            raise ValueError('expected one unfused LOVE executable')
        executable = executables[0]
        target = executable.parent / 'lua51.dll'
        # The console wrapper forwards stdout/stderr and the child exit status.
        executable = executable.with_name('lovec.exe')
        if not executable.is_file():
            raise ValueError('pinned Windows console host is absent')
    original = digest(target)
    results = []
    for label, minimum in (('stock', 60), ('extended', 120)):
        if label == 'extended':
            shutil.copyfile(library, target)
            if host == 'Darwin':
                run(['install_name_tool', '-id', '@rpath/Lua.framework/Versions/A/Lua', str(target)], check=True)
                run(['codesign', '--force', '--deep', '--sign', '-', str(app)], check=True,
                    capture_output=True, text=True)
                run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        identity = 'oasc-native-runtime-qa-' + uuid.uuid4().hex
        if profile:
            profile(Path.home() / 'Library/Application Support/LOVE' / identity)
        env = {key: value for key, value in os.environ.items() if not key.startswith('POKEPORT_')}
        env.update(UPVALUE_TEST_IDENTITY=identity, UPVALUE_TEST_MINIMUM=str(minimum))
        result = run([str(executable), str(project)], env=env, cwd=project,
                     capture_output=True, text=True, timeout=60)
        (output / (label + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
        if result.returncode:
            print((result.stdout + result.stderr)[-6000:], flush=True)
        result.check_returncode()
        if 'LOVE_RUNTIME_ABI_PASS ' + str(minimum) + ' ' not in result.stdout:
            raise RuntimeError('LOVE host/thread/FFI qualification marker missing')
        closure = json.loads(next(line.removeprefix('RUNTIME_UPVALUES ') for line in result.stdout.splitlines()
                                 if line.startswith('RUNTIME_UPVALUES ')))
        if not closure.get('passed'):
            raise RuntimeError('host closure probe did not complete')
        results.append({'variant': label, 'capacity': minimum, 'checks': closure['checks'],
                        'librarySha256': digest(target), 'identity': identity})
        print('LOVE_ABI_QUALIFIED', label, minimum, flush=True)
    report = {'passed': True, 'experimental': True, 'platform': host, 'machine': platform.machine(),
              'baseLoveCommit': '937eb3b21f973607ab080aa26b7ef2a6b3b2b663',
              'originalArchiveSha256': expected, 'originalLibrarySha256': original,
              'inputCandidateLibrarySha256': digest(library), 'qualificationSha256': digest(qualification),
              'scope': 'headless LOVE12 boot, closure/JIT/GC/bytecode, FFI callback and thread VM; not GPU/gameplay',
              'variants': results}
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(report), flush=True)


if __name__ == '__main__':
    main()
