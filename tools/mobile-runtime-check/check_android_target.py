#!/usr/bin/env python3
"""Execute matching stock/extended boundary probes on an owned Android emulator."""
# Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import argparse
import atexit
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
ABIS = ('arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64')


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--adb', default='adb')
    p.add_argument('--serial', required=True)
    p.add_argument('--abi', choices=ABIS, required=True)
    p.add_argument('--build', type=Path, required=True)
    p.add_argument('--output', type=Path)
    a = p.parse_args()
    if not re.fullmatch(r'emulator-[0-9]{4,5}', a.serial): p.error('Choose an explicit owned emulator serial')
    adb = Path(shutil.which(a.adb) or a.adb).resolve(strict=True)
    build = a.build.resolve(strict=True); source = build/'report.json'
    report = json.loads(source.read_text()); source_hash = sha(source)
    selected = {}
    for variant,capacity in (('stock',60),('extended',120)):
        entry = report['results'][variant+'-'+a.abi]
        if not entry['buildPassed'] or entry['capacityRequested'] != capacity: raise ValueError('Candidate build failed')
        folder = build/'artifacts'/variant/a.abi
        for name in ('luajit','c-api-upvalues','check.lua','src/link/Json.lua'):
            if sha(folder/name) != entry['files'][name]: raise ValueError('Candidate bytes changed: '+name)
        selected[variant] = (folder,entry['files'])
    output = (a.output or ROOT/'.local/qa'/('gen2-android-target-'+str(time.time_ns()))/'candidate').resolve()
    run = subprocess.run
    if not os.getenv('GITHUB_ACTIONS'):
        sys.path.insert(0,str(ROOT/'tools'))
        from qa_storage import Storage
        storage=Storage(ROOT);atexit.register(storage.close)
        for path in (ROOT,build,adb): storage.source(path)
        storage.cache(output.parent);storage.copy(output)
        run=storage.run
    output.mkdir(parents=True,exist_ok=False)
    sequence=0

    def command(label,args):
        nonlocal sequence
        sequence+=1
        result=run([str(adb),'-s',a.serial,*args],capture_output=True,text=True,timeout=120)
        (output/('%02d-'%sequence+label+'.log')).write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr,flush=True)
        result.check_returncode();return result.stdout.strip()

    if command('emulator',['shell','getprop','ro.kernel.qemu']) != '1': raise ValueError('Target is not an emulator')
    supported=command('abi',['shell','getprop','ro.product.cpu.abilist']).split(',')
    if a.abi not in supported: raise ValueError('Emulator does not support the selected ABI')
    remote='/data/local/tmp/gen2-runtime-'+uuid.uuid4().hex
    command('mkdir',['shell','mkdir',remote])
    results={}
    try:
        for variant,capacity in (('stock',60),('extended',120)):
            folder,expected_hashes=selected[variant]
            command('push-'+variant,['push',str(folder/'luajit'),str(folder/'c-api-upvalues'),str(folder/'check.lua'),remote+'/'])
            command('json-dir',['shell','mkdir','-p',remote+'/src/link'])
            command('json',['push',str(folder/'src/link/Json.lua'),remote+'/src/link/Json.lua'])
            for name in ('luajit','c-api-upvalues','check.lua','src/link/Json.lua'):
                observed=command('sha',['shell','sha256sum',remote+'/'+name]).split()[0]
                if observed!=expected_hashes[name] or sha(folder/name)!=expected_hashes[name]:raise RuntimeError('Emulator transfer changed '+name)
            command('chmod',['shell','chmod','700',remote+'/luajit',remote+'/c-api-upvalues'])
            command('jit-'+variant,['shell',remote+'/luajit -e '+shlex.quote('assert(jit.status())')])
            text=command('closures-'+variant,['shell','cd '+remote+' && ./luajit check.lua '+str(capacity)])
            line=next((s for s in text.splitlines() if s.startswith('RUNTIME_UPVALUES ')),None)
            if not line:raise RuntimeError('Missing target closure report')
            details=json.loads(line[len('RUNTIME_UPVALUES '):])
            if details.get('passed') is not True or details.get('minimum')!=capacity:raise RuntimeError('Target closure gate failed')
            c_api=command('c-api-'+variant,['shell',remote+'/c-api-upvalues',str(capacity)])
            if c_api!='C_API_UPVALUES '+str(capacity)+' PASS':raise RuntimeError('Target C API gate failed')
            results[variant]={'passed':True,'capacity':capacity,'closureReport':details,'cApiPassed':True}
            print(variant,a.abi,capacity,'ANDROID EXECUTION PASS',flush=True)
    finally:
        # Only the explicitly named files created in this fresh test directory.
        command('cleanup',['shell','rm','-f',remote+'/luajit',remote+'/c-api-upvalues',remote+'/check.lua',remote+'/src/link/Json.lua'])
        command('cleanup-dirs',['shell','rmdir',remote+'/src/link',remote+'/src',remote])
    if sha(source)!=source_hash:raise RuntimeError('Build receipt changed during target execution')
    for folder,expected in selected.values():
        for name in ('luajit','c-api-upvalues','check.lua','src/link/Json.lua'):
            if sha(folder/name)!=expected[name]:raise RuntimeError('Candidate changed during target execution')
    (output/'report.json').write_text(json.dumps({'passed':True,'abi':a.abi,'buildReportSha256':source_hash,
        'results':results,'emulator':True,'playerProfilesUsed':False,'loveHostAbiQualified':False,'releaseSelectable':False,
        'scope':'Android interpreter/JIT, debug/bytecode/GC and C API boundary execution. Actual LOVE/JNI/thread/FFI host and other architectures require separate acceptance.'},indent=2)+'\n')
    print('report',output/'report.json',flush=True)


if __name__=='__main__':main()
