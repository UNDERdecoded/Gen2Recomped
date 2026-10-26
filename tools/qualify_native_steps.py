#!/usr/bin/env python3
"""Compile and exercise the real Swift/Java step journal storage sources."""
# Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import argparse
import atexit
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid
import zipfile

ROOT=Path(__file__).resolve().parents[1]
INPUTS=('mobile/ios/native/GRHealthBridge.swift','tests/native_steps_native/main.swift',
        'mobile/android/love/src/main/java/org/love2d/android/StepJournal.java',
        'tests/native_steps_native/StepJournalCheck.java',
        'tests/native_steps_native/android/system/Os.java',
        'tests/native_steps_native/wire.lua','src/core/StepJournal.lua',
        'src/link/Json.lua','src/mods/Steps.lua','src/net/DownloadPublish.lua',
        'tests/native_steps_runtime/main.lua','tests/native_steps_runtime/conf.lua')
JSON_SHA256='3cf6cd6892e32e2b4c1c39e0f52f5248a2f5b37646fdfbb79a66b46b618414ed'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--swiftc',type=Path,required=True)
    p.add_argument('--sdk',type=Path,required=True,help='macOS SDK for the Foundation host probe')
    p.add_argument('--ios-sdk',type=Path,help='also typecheck the actual HealthKit bridge for iOS')
    p.add_argument('--java-home',type=Path,required=True)
    p.add_argument('--json-jar',type=Path,required=True)
    p.add_argument('--lua',type=Path,required=True)
    p.add_argument('--love',type=Path,required=True)
    p.add_argument('--output',type=Path)
    p.add_argument('--qa-tools',type=Path,help='directory containing local qa_storage helpers')
    args=p.parse_args()
    # Swift dispatches by argv[0]; resolving swiftc to swift-frontend changes it.
    swift=args.swiftc.expanduser().absolute();java=args.java_home.resolve(strict=True)
    if not swift.is_file():raise ValueError('Swift compiler missing')
    jar=args.json_jar.resolve(strict=True)
    sdk=args.sdk.resolve(strict=True)
    lua=args.lua.resolve(strict=True)
    love=args.love.resolve(strict=True)
    ios=args.ios_sdk.resolve(strict=True) if args.ios_sdk else None
    if hashlib.sha256(jar.read_bytes()).hexdigest()!=JSON_SHA256:
        raise ValueError('the pinned JSON test dependency checksum does not match')
    output=(args.output or ROOT/'.local/qa'/('gen2-native-mod-step-bridge-'+str(time.time_ns()))/'candidate').resolve()
    run=subprocess.run
    profile=None
    if not os.getenv('GITHUB_ACTIONS'):
        if args.qa_tools:sys.path.insert(0,str(args.qa_tools.resolve(strict=True)))
        from qa_storage import Storage
        manager=Storage(ROOT);atexit.register(manager.close)
        qa_source,qa_cache,qa_copy=manager.source,manager.cache,manager.copy
        qa_profile,qa_run=manager.destination,manager.run
        for source in (ROOT,swift,java,jar,sdk,lua,love):qa_source(source)
        if ios:qa_source(ios)
        qa_cache(output.parent);qa_copy(output)
        run=qa_run
        profile=qa_profile
    inputs={name:(ROOT/name).read_bytes() for name in INPUTS}
    output.mkdir(parents=True,exist_ok=False)
    for name,body in inputs.items():
        path=output/'sources'/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(body)
    reports={}
    def command(name,argv,env=None):
        result=run([str(x) for x in argv],cwd=ROOT,capture_output=True,text=True,timeout=120,env=env)
        (output/(name+'.log')).write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr,flush=True)
        result.check_returncode()
        return result.stdout
    source=output/'sources'
    command('swift-build',[swift,'-sdk',sdk,'-module-cache-path',output/'swift-modules',
        source/INPUTS[0],source/INPUTS[1],'-o',output/'step-swift'])
    text=command('swift-run',[output/'step-swift',output/'swift-data'])
    reports['swift']=int(re.search(r'Native steps Swift: (\d+) PASS',text)[1])
    if ios:
        command('ios-typecheck',[swift,'-sdk',ios,'-target','arm64-apple-ios15.0',
            '-module-cache-path',output/'ios-modules','-typecheck',source/INPUTS[0]])
        reports['iosTypecheck']=True
    command('java-build',[java/'bin/javac','-cp',jar,'-d',output/'java-classes',
        *[source/name for name in INPUTS[2:5]]])
    text=command('java-run',[java/'bin/java','-cp',str(output/'java-classes')+os.pathsep+str(jar),
        'org.love2d.android.StepJournalCheck',output/'java-data'])
    reports['java']=int(re.search(r'Native steps Java: (\d+) PASS',text)[1])
    text=command('lua-wire',[lua,source/INPUTS[5],output/'swift-data/steps_journal.json',
        output/'java-data/steps_journal.json'])
    reports['luaWire']=int(re.search(r'(\d+)/(\d+) checks passed',text)[1])
    identity='oasc-native-steps-qa-'+uuid.uuid4().hex
    if profile:profile(Path.home()/'Library/Application Support/LOVE'/identity)
    with zipfile.ZipFile(output/'steps.love','w',compression=zipfile.ZIP_DEFLATED) as archive:
        for name in INPUTS[6:10]:archive.writestr(name,inputs[name])
        archive.writestr('main.lua',inputs[INPUTS[10]])
        archive.writestr('conf.lua',inputs[INPUTS[11]])
    text=command('love-filesystem',[love,output/'steps.love'],dict(os.environ,STEPS_QA_IDENTITY=identity))
    reports['loveFilesystem']=int(re.search(r'Native steps LOVE: (\d+) PASS',text)[1])
    for name,body in inputs.items():
        if (ROOT/name).read_bytes()!=body:raise RuntimeError('native step source changed during qualification')
    report={'passed':True,'checks':reports,'sourceSha256':{n:hashlib.sha256(b).hexdigest() for n,b in inputs.items()},
        'jsonTestDependencySha256':JSON_SHA256,
        'scope':'real Swift/Foundation and Java journal code; Java POSIX rename uses a host test shim; no sensors, consent, JNI or physical-device proof'}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'output':str(output),**report}),flush=True)

if __name__=='__main__':main()
