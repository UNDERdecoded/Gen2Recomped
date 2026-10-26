#!/usr/bin/env python3
"""Compare the unchanged API-2 NPC consumer on both pinned native backends."""
import argparse
import hashlib
import json
from pathlib import Path
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference', type=Path, required=True)
    parser.add_argument('--lua', required=True)
    parser.add_argument('--report', type=Path, required=True)
    parser.add_argument('--qa-tools', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(args.qa_tools or root/'tools'))
    from qa_storage import qa_source, qa_cache, qa_run
    reference = args.reference.resolve()
    qa_source(root); qa_source(reference); qa_source(args.lua)
    qa_cache(args.report.parent)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    ref = qa_run(['git','rev-parse','HEAD'], cwd=reference, capture_output=True, text=True, check=True).stdout.strip()
    status=qa_run(['git','status','--porcelain','--untracked-files=no'],cwd=reference,
                  capture_output=True,text=True,check=True).stdout
    if status.strip(): raise RuntimeError('pinned reference has tracked modifications')
    if ref != '535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91':
        raise RuntimeError('reference does not match the pinned NPC contract')
    files=root/'tests/fixtures/legacy_npc_controls/mods/legacy'
    hashes={p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in files.iterdir() if p.is_file()}
    worker = root/'tests/fixtures/legacy_npc_controls/worker.lua'
    records=[]
    for version in ('red','blue','yellow','gold','silver','crystal','firered','emerald'):
        results={}
        for backend, engine in [('gen1',reference),('gen2',root)]:
            result=qa_run([args.lua,str(worker),str(root),backend,version],cwd=engine,
                          capture_output=True,text=True,timeout=60)
            lines=[line[len('LEGACY_NPC_RESULT '):]for line in result.stdout.splitlines()
                   if line.startswith('LEGACY_NPC_RESULT ')]
            if result.returncode or len(lines)!=1:
                raise RuntimeError(f'{backend}/{version}:\n{result.stdout}{result.stderr}')
            results[backend]=json.loads(lines[0])
        if results['gen1']!=results['gen2']:
            raise RuntimeError(f'{version}: NPC contract differs: {results}')
        records.append({'version':version,'result':results['gen2']})
        print('PASS '+version,flush=True)
    if {p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in files.iterdir() if p.is_file()} != hashes:
        raise RuntimeError('NPC consumer bytes changed during the comparison')
    args.report.write_text(json.dumps({'reference':ref,'consumerSha256':hashes,'comparisons':records},indent=2)+'\n')


if __name__=='__main__':
    main()
