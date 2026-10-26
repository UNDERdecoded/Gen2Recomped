#!/usr/bin/env python3
"""Build isolated Android LuaJIT candidates and target-side boundary probes."""
# Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import argparse
import atexit
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
ABIS = {
    'arm64-v8a': ('aarch64-linux-android', 'aarch64-linux-android', 64, 'AArch64'),
    'armeabi-v7a': ('armv7a-linux-androideabi', 'arm-linux-androideabi', 32, 'ARM'),
    'x86': ('i686-linux-android', 'i686-linux-android', 32, 'Intel 80386'),
    'x86_64': ('x86_64-linux-android', 'x86_64-linux-android', 64, 'Advanced Micro Devices X86-64'),
}
HEADERS = ('lua.h', 'luaconf.h', 'lauxlib.h', 'lualib.h', 'luajit.h')
RELVER = '1700008891'  # Matches the vendored Android public headers.


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--ndk', type=Path, required=True)
    p.add_argument('--source', type=Path, default=ROOT/'mobile/android/love/src/jni/LuaJIT-2.1')
    p.add_argument('--abi', action='append', choices=ABIS)
    p.add_argument('--api', type=int, default=23)
    p.add_argument('--jobs', type=int, default=4)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    if platform.system() not in ('Linux', 'Darwin'):
        p.error('Use a POSIX host toolchain; Linux multilib is required for 32-bit targets')
    if not 23 <= a.api <= 35 or not 1 <= a.jobs <= 8:
        p.error('API must be 23..35 and jobs must be 1..8')
    abis = a.abi or (list(ABIS) if platform.system() == 'Linux' else ['arm64-v8a', 'x86_64'])
    if len(abis) != len(set(abis)):
        p.error('Choose each ABI once')
    if platform.system() == 'Darwin' and any(ABIS[x][2] == 32 for x in abis):
        p.error('32-bit targets require a Linux multilib host')
    source, ndk = a.source.resolve(strict=True), a.ndk.resolve(strict=True)
    host = 'linux-x86_64' if platform.system() == 'Linux' else 'darwin-x86_64'
    binaries = ndk/'toolchains/llvm/prebuilt'/host/'bin'
    for name in ('llvm-ar', 'llvm-readelf', 'llvm-strip'):
        if not (binaries/name).is_file(): p.error('Missing NDK tool: '+name)
    for abi in abis:
        if not (binaries/(ABIS[abi][0]+str(a.api)+'-clang')).is_file(): p.error('Missing NDK compiler for '+abi)
        header = source/'android'/abi/'luajit.h'
        if header.exists() and ('luaJIT_version_2_1_'+RELVER) not in header.read_text():
            p.error('Vendored Android header version changed; audit the source/version binding')
    inputs = [source/'Makefile', source/'COPYRIGHT']
    for directory in ('src', 'dynasm'):
        inputs.extend(path for path in (source/directory).rglob('*') if path.is_file())
    if any(path.is_symlink() for path in inputs): p.error('Source inputs must not be symlinks')
    if any(path.suffix in ('.o', '.a', '.so', '.dll', '.exe') for path in inputs):
        p.error('Use an unbuilt source tree; generated binaries are not source inputs')
    hashes = {str(path.relative_to(source)): sha(path) for path in inputs}
    probe_names = ('tools/runtime-upvalue-check/check.lua', 'tools/runtime-upvalue-check/c_api.c',
                   'src/link/Json.lua', 'LICENSE', 'LICENSE.MD', 'LICENSE-ROXAS2712.md')
    probe_inputs = {name: (ROOT/name).read_bytes() for name in probe_names}
    limit = (source/'src/lj_def.h').read_text()
    if len(re.findall(r'^#define LJ_MAX_UPVAL\s+60\s', limit, re.M)) != 1:
        p.error('Expected the vendored stock 60-upvalue source')
    output = (a.output or ROOT/'.local/qa'/('gen2-mobile-runtime-'+str(time.time_ns()))/'candidate').resolve()
    run = subprocess.run
    if not os.getenv('GITHUB_ACTIONS'):
        sys.path.insert(0, str(ROOT/'tools'))
        from qa_storage import Storage
        storage = Storage(ROOT); atexit.register(storage.close)
        for path in (ROOT, source, ndk): storage.source(path)
        storage.cache(output.parent); storage.copy(output)
        run = storage.run
    output.mkdir(parents=True, exist_ok=False)
    results = {}

    def command(label, argv, cwd):
        result = run([str(x) for x in argv], cwd=cwd, capture_output=True, text=True, timeout=300)
        (output/(label+'.log')).write_text(result.stdout+result.stderr)
        if result.returncode: print((result.stdout+result.stderr)[-12000:], flush=True)
        result.check_returncode()
        return result.stdout

    for variant, capacity in (('stock', 60), ('extended', 120)):
        for abi in abis:
            triple, prefix, bits, machine = ABIS[abi]
            label = variant+'-'+abi
            build = output/'build'/variant/abi; build.mkdir(parents=True)
            for relative in hashes:
                target = build/relative; target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source/relative, target)
            (build/'.relver').write_text(RELVER+'\n')
            if capacity == 120:
                changed, count = re.subn(r'(^#define LJ_MAX_UPVAL\s+)60(?=\s)', r'\g<1>120', limit, flags=re.M)
                assert count == 1
                (build/'src/lj_def.h').write_text(changed)
            cc = binaries/(triple+str(a.api)+'-clang')
            host_cc = 'clang' if platform.system() == 'Darwin' else 'gcc -m'+str(bits)
            command(label+'-build', ['make', '-j'+str(a.jobs), 'BUILDMODE=static', 'TARGET_SYS=Linux',
                'HOST_CC='+host_cc, 'CROSS='+shlex.quote(str(binaries/(prefix+'-'))),
                'STATIC_CC='+shlex.quote(str(cc))+' -fPIC', 'DYNAMIC_CC='+shlex.quote(str(cc))+' -fPIC',
                'TARGET_LD='+shlex.quote(str(cc)), 'TARGET_AR='+shlex.quote(str(binaries/'llvm-ar'))+' rcus',
                'TARGET_STRIP='+shlex.quote(str(binaries/'llvm-strip')), 'XCFLAGS=-DLUAJIT_ENABLE_LUA52COMPAT'], build)
            artifact = output/'artifacts'/variant/abi; artifact.mkdir(parents=True)
            for name in HEADERS: shutil.copy2(build/'src'/name, artifact/name)
            for name in ('libluajit.a', 'luajit'): shutil.copy2(build/'src'/name, artifact/name)
            shutil.copy2(source/'COPYRIGHT', artifact/'COPYRIGHT')
            (artifact/'check.lua').write_bytes(probe_inputs['tools/runtime-upvalue-check/check.lua'])
            (artifact/'c_api.c').write_bytes(probe_inputs['tools/runtime-upvalue-check/c_api.c'])
            (artifact/'src/link').mkdir(parents=True)
            (artifact/'src/link/Json.lua').write_bytes(probe_inputs['src/link/Json.lua'])
            for name in ('LICENSE', 'LICENSE.MD', 'LICENSE-ROXAS2712.md'):
                (artifact/name).write_bytes(probe_inputs[name])
            command(label+'-c-api-build', [cc, '-I'+str(artifact), artifact/'c_api.c',
                artifact/'libluajit.a', '-lm', '-ldl', '-o', artifact/'c-api-upvalues'], build)
            elf = command(label+'-elf', [binaries/'llvm-readelf', '-h', artifact/'luajit', artifact/'c-api-upvalues'], build)
            machines = re.findall(r'^\s*Machine:\s*(.+)$', elf, re.M)
            if machines != [machine, machine]: raise RuntimeError('Unexpected target machine: '+repr(machines))
            results[label] = {'abi': abi, 'api': a.api, 'capacityRequested': capacity, 'buildPassed': True,
                'targetExecutionQualified': False, 'cApiLinked': True, 'machine': machine,
                'files': {str(p.relative_to(artifact)): sha(p) for p in artifact.rglob('*') if p.is_file()}}
            print(label, 'BUILD/LINK PASS; target execution pending', flush=True)
    if any(sha(source/name) != digest for name,digest in hashes.items()):
        raise RuntimeError('Source changed during runtime build')
    if any((ROOT/name).read_bytes() != data for name,data in probe_inputs.items()):
        raise RuntimeError('Probe inputs changed during runtime build')
    report = {'sourceRelease': RELVER, 'sourceSha256': hashes,
        'probeInputSha256': {name: hashlib.sha256(data).hexdigest() for name,data in probe_inputs.items()},
        'ndkPropertiesSha256': sha(ndk/'source.properties'), 'results': results,
        'scope': 'Isolated stock/extended Android libraries, matching headers, interpreter and C API executables. Build/link/architecture evidence; execution on Android and actual LOVE host ABI remain required before release selection.',
        'playerProfilesUsed': False, 'minimumFreeGiB': 20, 'releaseSelectable': False}
    (output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
    print('report', output/'report.json', flush=True)


if __name__ == '__main__': main()
