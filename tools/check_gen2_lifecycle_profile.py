#!/usr/bin/env python3
"""Measure guarded native lifecycle producers before/after and with observers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import time


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--love',type=Path,required=True)
    parser.add_argument('--baseline',required=True)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--qa-tools',type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    sys.path.insert(0,str(args.qa_tools or root/'tools'))
    from qa_storage import qa_source,qa_cache,qa_copy,qa_profile,qa_run
    qa_source(root);qa_source(args.love.resolve())
    qa_cache(args.report.parent);args.report.parent.mkdir(parents=True,exist_ok=True)
    snapshot=args.report.parent/'baseline'
    qa_copy(snapshot);snapshot.mkdir(parents=True,exist_ok=True)
    paths={'Gen2Friendship':'src/pokemon/Gen2Friendship.lua',
           'RoamMons':'src/world/RoamMons.lua','BugContest':'src/world/BugContest.lua'}
    hashes={}
    for name,path in paths.items():
        data=qa_run(['git','show',args.baseline+':'+path],cwd=root,capture_output=True,check=True).stdout
        (snapshot/(name+'.lua')).write_bytes(data)
        hashes[path]={'before':hashlib.sha256(data).hexdigest(),
                      'after':hashlib.sha256((root/path).read_bytes()).hexdigest()}
    identity='oasc-gen2-lifecycle-qa-'+str(time.time_ns())
    qa_profile(Path.home()/'Library/Application Support/LOVE'/identity)
    run=qa_run([str(args.love.resolve()),str(root/'tools/gen2-lifecycle-profile')],cwd=root,
               env=dict(os.environ,GEN2_LIFECYCLE_PROFILE_QA='1',GEN2_LIFECYCLE_ROOT=str(root),
                        GEN2_LIFECYCLE_BASELINE=str(snapshot.resolve()),POKEPORT_IDENTITY=identity),
               capture_output=True,text=True,timeout=90)
    args.report.with_suffix('.log').write_text(run.stdout+run.stderr)
    profiles=[line.removeprefix('LIFECYCLE_PROFILE ')for line in run.stdout.splitlines()
              if line.startswith('LIFECYCLE_PROFILE ')]
    if run.returncode or len(profiles)!=1:raise RuntimeError('native lifecycle probe failed; see its log')
    for path,digests in hashes.items():
        if hashlib.sha256((root/path).read_bytes()).hexdigest()!=digests['after']:
            raise RuntimeError('measured source changed during the probe')
    report=json.loads(profiles[0]);report.update(baseline=args.baseline,sha256=hashes,playerProfilesUsed=False)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))


if __name__=='__main__':main()
