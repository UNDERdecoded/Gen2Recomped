#!/usr/bin/env python3
"""Check native checkpoint RNG continuation inside an isolated actual LÖVE host."""
import argparse
import atexit
import hashlib
import json
import os
from pathlib import Path
import sys
import time


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--love',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--qa-tools',type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    sys.path.insert(0,str(args.qa_tools or root/'tools'))
    from qa_storage import Storage
    storage=Storage(root)
    atexit.register(storage.close)
    qa_source,qa_cache=storage.source,storage.cache
    qa_profile,qa_run=storage.destination,storage.run
    binary=args.love.resolve(strict=True)
    for path in (root,binary):qa_source(path)
    sources={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in (root/'src').rglob('*.lua')}
    output=args.output.resolve()
    # These are generated reports, not disposable frozen engine copies.
    qa_cache(output.parent);output.mkdir(parents=True,exist_ok=False)
    identity='oasc-gen2recomp-qa-checkpoint-rng-'+str(time.time_ns())
    qa_profile(Path.home()/'Library/Application Support/LOVE'/identity)
    source=qa_run(['git','rev-parse','HEAD'],cwd=root,check=True,capture_output=True,text=True).stdout.strip()
    assert not qa_run(['git','status','--porcelain'],cwd=root,check=True,capture_output=True,text=True).stdout.strip()
    result=qa_run([str(binary),str(root/'tools/checkpoint-runtime/host')],cwd=root,
      env=dict(os.environ,POKEPORT_IDENTITY=identity,CHECKPOINT_ENGINE=str(root),CHECKPOINT_REPORT=str(output/'result.json')),
      capture_output=True,text=True,timeout=120)
    (output/'run.log').write_text(result.stdout+result.stderr)
    result.check_returncode()
    report=json.loads((output/'result.json').read_text())
    assert report['passed'] and report['realLoveMath'] and len(report['cases'])==6
    assert all(hashlib.sha256((root/p).read_bytes()).hexdigest()==digest for p,digest in sources.items())
    assert source==qa_run(['git','rev-parse','HEAD'],cwd=root,check=True,capture_output=True,text=True).stdout.strip()
    assert not qa_run(['git','status','--porcelain'],cwd=root,check=True,capture_output=True,text=True).stdout.strip()
    report.update(sourceCommit=source,sourceSha256=sources,minimumFreeGiB=20,scope='Actual LÖVE RNG and native settled GB checkpoint transactions over synthetic content with substituted graphics; no GPU/gameplay/later-generation acceptance.')
    (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print('NATIVE_CHECKPOINT_RNG_PASS',report['loveVersion'],report['checks'])


if __name__=='__main__':main()
