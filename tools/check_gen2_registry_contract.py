#!/usr/bin/env python3
"""Compare the five public Gen2 registry descriptors with a pinned backend."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--lua', required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--qa-tools', type=Path)
    parser.add_argument('--love', type=Path)
    parser.add_argument('--baseline', help='local commit for the optional native validation profile')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    sys.path.insert(0,str(args.qa_tools or root/'tools'))
    from qa_storage import qa_source, qa_cache, qa_profile, qa_run
    reference=args.reference.resolve()
    qa_source(root); qa_source(reference); qa_source(args.lua)
    if args.love:
        if not args.baseline: parser.error('--love requires --baseline')
        qa_source(args.love.resolve())
    qa_cache(args.report.parent)
    args.report.parent.mkdir(parents=True,exist_ok=True)
    ref=qa_run(['git','rev-parse','HEAD'],cwd=reference,capture_output=True,text=True,check=True).stdout.strip()
    status=qa_run(['git','status','--porcelain','--untracked-files=no'],cwd=reference,
                  capture_output=True,text=True,check=True).stdout
    if status.strip() or ref!='535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91':
        raise RuntimeError('reference must be the clean pinned contract')
    worker=root/'tools/gen2-registry-contract/fields.lua'
    digest=hashlib.sha256(worker.read_bytes()).hexdigest()
    results=[]
    for engine in (reference,root):
        run=qa_run([args.lua,str(worker)],cwd=engine,capture_output=True,text=True,timeout=60)
        records=[line.removeprefix('REGISTRY_CONTRACT ') for line in run.stdout.splitlines()
                 if line.startswith('REGISTRY_CONTRACT ')]
        if run.returncode or len(records)!=1:
            raise RuntimeError(run.stdout+run.stderr)
        results.append(json.loads(records[0]))
    if results[0]!=results[1]:
        raise RuntimeError('public registry descriptors differ: '+json.dumps(results,sort_keys=True))
    if hashlib.sha256(worker.read_bytes()).hexdigest()!=digest:
        raise RuntimeError('contract consumer changed during the comparison')
    report={'reference':ref,'consumerSha256':digest,'registries':results[1]}
    if args.love:
        baseline=qa_run(['git','show',args.baseline+':src/mods/Schemas.lua'],cwd=root,
                        capture_output=True,check=True).stdout
        path=args.report.parent/'baseline-schemas.lua'
        path.write_bytes(baseline)
        identity='oasc-gen2-registry-qa-'+str(time.time_ns())
        qa_profile(Path.home()/'Library/Application Support/LOVE'/identity)
        run=qa_run([str(args.love.resolve()),str(root/'tools/gen2-registry-contract')],cwd=root,
                   env=dict(os.environ,GEN2_REGISTRY_QA='1',GEN2_REGISTRY_ROOT=str(root),
                            GEN2_REGISTRY_BASELINE=str(path.resolve()),POKEPORT_IDENTITY=identity),
                   capture_output=True,text=True,timeout=60)
        args.report.with_suffix('.log').write_text(run.stdout+run.stderr)
        profiles=[line.removeprefix('REGISTRY_PROFILE ')for line in run.stdout.splitlines()
                  if line.startswith('REGISTRY_PROFILE ')]
        if run.returncode or len(profiles)!=1:raise RuntimeError('native registry probe failed')
        report['profile']=json.loads(profiles[0])
        report['baseline']=args.baseline
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print('PASS: five identical Gen2 registry descriptors')


if __name__=='__main__':
    main()
