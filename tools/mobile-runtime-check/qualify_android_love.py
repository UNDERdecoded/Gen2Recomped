#!/usr/bin/env python3
"""Build and execute isolated capacity probes in the actual Android LÖVE app."""
# Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import argparse
import atexit
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time
import uuid
import zipfile

ROOT = Path(__file__).resolve().parents[2]
HEADERS = ('lua.h', 'luaconf.h', 'lauxlib.h', 'lualib.h', 'luajit.h')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('build', 'run'))
    parser.add_argument('--build', type=Path, required=True,
                        help='VM candidate directory for build; app candidate directory for run')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--serial')
    parser.add_argument('--adb', default='adb')
    args = parser.parse_args()
    if args.mode == 'run' and not re.fullmatch(r'emulator-[0-9]{4,5}', args.serial or ''):
        parser.error('Run requires an explicit owned emulator serial')
    source = args.build.resolve(strict=True)
    output = args.output.resolve()
    if source == output or source in output.parents or output in source.parents:
        parser.error('Candidate inputs and owned output must be separate directories')
    adb = Path(shutil.which(args.adb) or args.adb).resolve(strict=True) if args.mode == 'run' else None
    run = subprocess.run
    if not os.getenv('GITHUB_ACTIONS'):
        sys.path.insert(0, str(ROOT/'tools'))
        from qa_storage import Storage
        storage = Storage(ROOT)
        atexit.register(storage.close)
        for path in (ROOT, source, adb):
            if path is not None:
                storage.source(path)
        storage.cache(output.parent)
        storage.copy(output)
        run = storage.run
    output.mkdir(parents=True, exist_ok=False)

    def command(label, argv, *, cwd=None, required=True, timeout=120):
        result = run([str(x) for x in argv], cwd=cwd, capture_output=True,
                     text=True, timeout=timeout)
        (output/(label+'.log')).write_text(result.stdout+result.stderr)
        if required and result.returncode:
            print((result.stdout+result.stderr)[-12000:], flush=True)
            result.check_returncode()
        return result

    manifest = source/'report.json'
    manifest_hash = sha(manifest)
    report = json.loads(manifest.read_text())
    results = {}
    if args.mode == 'build':
        head = command('source-commit', ['git', 'rev-parse', 'HEAD'], cwd=ROOT).stdout.strip()
        paths = command('tracked-mobile', ['git', 'ls-files', '-z', '--', 'mobile/android'], cwd=ROOT).stdout.split('\0')
        paths = [Path(name) for name in paths if name]
        if not paths or any(not (ROOT/path).is_file() or (ROOT/path).is_symlink() for path in paths):
            raise ValueError('Use a complete materialized mobile/android source checkout')
        mobile_hashes = {str(path): sha(ROOT/path) for path in paths}
        probe_names = ('tools/mobile-runtime-check/android-love-main.lua',
                       'tools/runtime-upvalue-check/love-thread.lua',
                       'tools/runtime-upvalue-check/check.lua', 'src/link/Json.lua',
                       'LICENSE', 'LICENSE.MD', 'LICENSE-ROXAS2712.md')
        probes = {name: (ROOT/name).read_bytes() for name in probe_names}
        token = uuid.uuid4().hex
        host = output/'host'
        host.mkdir()
        for path in paths:
            target = host/path.relative_to('mobile/android')
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT/path, target)
        library_gradle = host/'love/build.gradle'
        text, count = re.subn(r"abiFilters 'armeabi-v7a', 'arm64-v8a'", "abiFilters 'x86_64'", library_gradle.read_text())
        if count != 1:
            raise ValueError('Android ABI declarations changed; audit the owned host configuration')
        library_gradle.write_text(text)
        properties = (host/'gradle.properties').read_text()
        android_manifest = (host/'app/src/main/AndroidManifest.xml').read_text()
        candidate_inputs = {}
        authority = 'com.underdecodedhd.gen2recomp.seconddisplay'
        if android_manifest.count(authority) != 1:
            raise ValueError('Android provider authority changed; audit the owned app identity')
        for variant, capacity in (('stock', 60), ('extended', 120)):
            entry = report['results'][variant+'-x86_64']
            if not entry['buildPassed'] or entry['capacityRequested'] != capacity:
                raise ValueError('VM candidate is not built')
            folder = source/'artifacts'/variant/'x86_64'
            for name in ('libluajit.a', *HEADERS):
                data = (folder/name).read_bytes()
                if hashlib.sha256(data).hexdigest() != entry['files'][name]:
                    raise ValueError('VM candidate bytes changed: '+name)
                candidate_inputs[folder/name] = entry['files'][name]
                (host/'love/src/jni/LuaJIT-2.1/android/x86_64'/name).write_bytes(data)
                if name in HEADERS:
                    (host/'love/src/jni/LuaJIT-2.1/src'/name).write_bytes(data)
            package = 'com.roxas2712.runtimeqa.r'+token+'.'+variant
            identity = 'oasc-gen2recomp-qa-android-runtime-'+token+'-'+variant
            owned_properties = properties
            for key, value in (('app.application_id', package), ('app.name', 'Runtime QA '+variant)):
                owned_properties, count = re.subn(r'^'+re.escape(key)+r'=.*$', key+'='+value, owned_properties, flags=re.M)
                if count != 1:
                    raise ValueError('Android app property changed: '+key)
            (host/'gradle.properties').write_text(owned_properties)
            (host/'app/src/main/AndroidManifest.xml').write_text(android_manifest.replace(authority, package+'.seconddisplay'))
            payload = host/'app/src/embed/assets/game.love'
            payload.parent.mkdir(parents=True, exist_ok=True)
            config = {'capacity': capacity, 'identity': identity,
                      'report': '/data/user/0/'+package+'/files/runtime-capacity-result.json'}
            with zipfile.ZipFile(payload, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
                for target, original in (('main.lua', probe_names[0]), ('thread.lua', probe_names[1]),
                                         ('check.lua', probe_names[2]), ('src/link/Json.lua', probe_names[3])):
                    archive.writestr(target, probes[original])
                archive.writestr('config.lua', 'return {capacity='+str(capacity)+',identity='+
                                 json.dumps(identity)+',report='+json.dumps(config['report'])+'}\n')
                archive.writestr('conf.lua', 'function love.conf(t) t.identity='+json.dumps(identity)+
                    ";t.version='11.5';t.window=false;t.modules.graphics=false;t.modules.audio=false;"+
                    't.modules.joystick=false;t.modules.physics=false end\n')
                for name in ('LICENSE', 'LICENSE.MD', 'LICENSE-ROXAS2712.md'):
                    archive.writestr(name, probes[name])
                archive.writestr('LUAJIT-COPYRIGHT', (ROOT/'mobile/android/love/src/jni/LuaJIT-2.1/COPYRIGHT').read_bytes())
            command(variant+'-app-build', ['bash', './gradlew', '--no-daemon', ':love:clean',
                    ':app:assembleEmbedNoRecordDebug'], cwd=host, timeout=2400)
            apks = list((host/'app/build/outputs/apk/embedNoRecord/debug').glob('*.apk'))
            if len(apks) != 1:
                raise ValueError('Expected one owned test APK')
            apk = output/(variant+'.apk')
            shutil.copyfile(apks[0], apk)
            with zipfile.ZipFile(apk) as archive:
                if 'lib/x86_64/liblove.so' not in archive.namelist():
                    raise ValueError('Actual x86-64 LÖVE host is absent from APK')
                love_hash = hashlib.sha256(archive.read('lib/x86_64/liblove.so')).hexdigest()
            results[variant] = {'capacity': capacity, 'package': package, 'identity': identity,
                                'apk': apk.name, 'apkSha256': sha(apk), 'libloveSha256': love_hash,
                                'runtimeArchiveSha256': entry['files']['libluajit.a']}
            print(variant, capacity, 'ACTUAL LOVE APK BUILD PASS', flush=True)
        if any(sha(ROOT/name) != digest for name, digest in mobile_hashes.items()):
            raise RuntimeError('Mobile source changed during host qualification build')
        if any((ROOT/name).read_bytes() != data for name, data in probes.items()):
            raise RuntimeError('Probe source changed during host qualification build')
        if any(sha(path) != digest for path, digest in candidate_inputs.items()):
            raise RuntimeError('VM candidate changed during host qualification build')
        report = {'engineCommit': head, 'mobileSourceSha256': mobile_hashes,
                  'probeSha256': {name: hashlib.sha256(data).hexdigest() for name, data in probes.items()},
                  'vmBuildReportSha256': manifest_hash, 'results': results,
                  'loveHostAbiQualified': False}
    else:
        def device(label, args, **kwargs):
            return command(label, [adb, '-s', args_serial, *args], **kwargs).stdout.strip()
        args_serial = args.serial
        if device('emulator', ['shell', 'getprop', 'ro.kernel.qemu']) != '1':
            raise ValueError('Target is not an owned emulator')
        if device('user', ['shell', 'am', 'get-current-user']) != '0':
            raise ValueError('The owned test APK report path requires emulator user zero')
        if 'x86_64' not in device('abi', ['shell', 'getprop', 'ro.product.cpu.abilist']).split(','):
            raise ValueError('Actual host qualification requires the x86-64 emulator')
        for variant, capacity in (('stock', 60), ('extended', 120)):
            entry = report['results'][variant]
            package = entry['package']
            if not re.fullmatch(r'com\.roxas2712\.runtimeqa\.r[0-9a-f]{32}\.'+variant, package):
                raise ValueError('Refuse an application outside the owned test namespace')
            apk = source/entry['apk']
            if apk.parent != source or sha(apk) != entry['apkSha256'] or entry['capacity'] != capacity:
                raise ValueError('Owned app candidate changed')
            if device(variant+'-existing', ['shell', 'pm', 'path', package], required=False):
                raise ValueError('Refuse to replace an existing app, even in the test namespace')
            installed = False
            try:
                device(variant+'-install', ['install', str(apk)])
                installed = True
                device(variant+'-start', ['shell', 'am', 'start', '-W', '-n', package+'/org.love2d.android.GameActivity'])
                deadline = time.monotonic()+180
                result = None
                while time.monotonic() < deadline:
                    value = device(variant+'-result', ['shell', 'run-as', package, 'cat',
                                   'files/runtime-capacity-result.json'], required=False)
                    if value.startswith('{'):
                        try:
                            result = json.loads(value)
                        except json.JSONDecodeError:
                            pass
                        else:
                            break
                    time.sleep(2)
                if not result or result.get('passed') is not True:
                    raise RuntimeError('Actual Android LÖVE host gate failed: '+str(result))
                for key in ('jitActive', 'ffiCallbackPassed', 'threadVmPassed', 'filesystemPassed'):
                    if result.get(key) is not True:
                        raise ValueError('Actual host proof missing: '+key)
                if result.get('capacity') != capacity or result.get('identity') != entry['identity'] or result.get('arch') != 'x64':
                    raise ValueError('Actual host identity/capacity mismatch')
                details = result.get('closureReport', {})
                if details.get('passed') is not True or details.get('minimum') != capacity:
                    raise ValueError('Actual host closure report is missing or mismatched')
                boundary = next((case for case in details.get('cases', []) if case.get('upvalues') == capacity), {})
                if not all(boundary.get(key) is True for key in ('compiles', 'interpreter', 'jit')):
                    raise ValueError('Actual host closure boundary was not exercised')
                if sha(apk) != entry['apkSha256']:
                    raise RuntimeError('APK changed during actual host execution')
                results[variant] = result
                print(variant, capacity, 'ANDROID LOVE/JNI/THREAD/FFI PASS', flush=True)
            finally:
                if installed:
                    device(variant+'-device-log', ['logcat', '-d', '-t', '300',
                           '-s', 'SDL', 'love', 'AndroidRuntime', 'GameActivity'], required=False)
                    device(variant+'-stop', ['shell', 'am', 'force-stop', package], required=False)
                    device(variant+'-uninstall', ['uninstall', package])
        report = {'appBuildReportSha256': manifest_hash, 'results': results,
                  'passed': True, 'abi': 'x86_64', 'emulator': True, 'loveHostAbiQualified': True}
    if sha(manifest) != manifest_hash:
        raise RuntimeError('Candidate manifest changed during qualification')
    report.update(playerProfilesUsed=False, minimumFreeGiB=20, releaseSelectable=False,
                  scope='Actual vendored Android LÖVE/JNI host, owned ROM-free test APKs. ARM, other devices and full game/mod acceptance remain separate requirements.')
    (output/'report.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    main()
