#!/usr/bin/env python3
"""Exercise the production native HTTP adapters with owned protocol fixtures."""
# Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
import argparse,atexit,hashlib,json,os,re,subprocess,sys,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
INPUTS=('mobile/ios/native/GRHTTPBridge.swift',
        'mobile/android/love/src/main/java/org/love2d/android/BoundedHttp.java',
        'tests/native_http/android/util/Base64.java','tests/native_http/main.swift',
        'tests/native_http/BoundedHttpCheck.java')
JSON_SHA256='3cf6cd6892e32e2b4c1c39e0f52f5248a2f5b37646fdfbb79a66b46b618414ed'
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for name in ['swiftc','sdk','ios-sdk','java-home','json-jar']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--output',type=Path);p.add_argument('--qa-tools',type=Path)
    a=p.parse_args();swift=a.swiftc.expanduser().absolute();java=a.java_home.resolve(strict=True)
    sdk=a.sdk.resolve(strict=True);ios=a.ios_sdk.resolve(strict=True);jar=a.json_jar.resolve(strict=True)
    if not swift.is_file() or hashlib.sha256(jar.read_bytes()).hexdigest()!=JSON_SHA256:raise ValueError('compiler or pinned test dependency invalid')
    output=(a.output or ROOT/'.local/qa'/('gen2-native-mod-http-'+str(time.time_ns()))/'candidate').resolve()
    run=subprocess.run
    if not os.getenv('GITHUB_ACTIONS'):
        if a.qa_tools:sys.path.insert(0,str(a.qa_tools.resolve(strict=True)))
        from qa_storage import Storage
        manager=Storage(ROOT);atexit.register(manager.close)
        for source in (ROOT,swift,java,sdk,ios,jar):manager.source(source)
        manager.cache(output.parent);manager.copy(output);run=manager.run
    inputs={name:(ROOT/name).read_bytes() for name in INPUTS}
    output.mkdir(parents=True,exist_ok=False)
    for name,data in inputs.items():(output/Path(name).name).write_bytes(data)
    def command(name,args):
        r=run([str(v) for v in args],cwd=ROOT,capture_output=True,text=True,timeout=120)
        (output/(name+'.log')).write_text(r.stdout+r.stderr)
        if r.returncode:print(r.stdout+r.stderr,flush=True)
        r.check_returncode();return r.stdout
    command('swift-build',[swift,'-swift-version','5','-sdk',sdk,'-module-cache-path',output/'mac-modules',
      output/'GRHTTPBridge.swift',output/'main.swift','-o',output/'http-swift'])
    command('ios-typecheck',[swift,'-swift-version','5','-sdk',ios,'-target','arm64-apple-ios14.0',
      '-module-cache-path',output/'ios-modules','-typecheck',output/'GRHTTPBridge.swift'])
    command('java-build',[java/'bin/javac','-cp',jar,'-d',output/'classes',
      output/'BoundedHttp.java',output/'Base64.java',output/'BoundedHttpCheck.java'])
    s=command('swift-test',[output/'http-swift'])
    j=command('java-test',[java/'bin/java','-cp',str(output/'classes')+os.pathsep+str(jar),'org.love2d.android.BoundedHttpCheck'])
    if any((ROOT/name).read_bytes()!=data for name,data in inputs.items()):raise RuntimeError('native HTTP sources changed during qualification')
    report={'passed':True,'checks':{'swift':int(re.search(r'Native HTTP Swift: (\d+) PASS',s)[1]),
      'java':int(re.search(r'Native HTTP Java: (\d+) PASS',j)[1])},'iosTypechecked':True,
      'sourceSha256':{name:hashlib.sha256(data).hexdigest() for name,data in inputs.items()},
      'jsonTestDependencySha256':JSON_SHA256,
      'scope':'Production Foundation/URLConnection adapter logic with owned URLProtocol/URLConnection fixtures; no real mobile TLS, JNI, phone or console proof.'}
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'output':str(output),**report}),flush=True)
if __name__=='__main__':main()
