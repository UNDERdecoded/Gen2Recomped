#!/usr/bin/env python3
"""Qualify native PCM writes without opening a user's audio/save profile."""
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
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--qa-tools',type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    sys.path.insert(0,str(args.qa_tools or root/'tools'))
    from qa_storage import qa_source,qa_cache,qa_profile,qa_run
    qa_source(root);qa_source(args.love.resolve())
    qa_cache(args.report.parent);args.report.parent.mkdir(parents=True,exist_ok=True)
    names=('src/core/AudioPcm.lua','src/core/ChipSynth.lua','src/core/M4ASynth.lua','src/core/chip_worker.lua','src/core/ChipAudio.lua',
           'src/core/Sound.lua','src/core/Music.lua','src/core/Performance.lua',
           'src/audio/NitroAudio.lua','src/audio/NitroTransport.lua','src/audio/NitroSequence.lua',
           'src/audio/NitroWorker.lua','tools/audio-profile-check/NitroFixture.lua','tools/audio-profile-check/NitroCheck.lua',
           'tools/audio-profile-check/main.lua','tools/audio-profile-check/conf.lua')
    hashes={name:hashlib.sha256((root/name).read_bytes()).hexdigest()for name in names}
    identity='oasc-audio-pcm-qa-'+str(time.time_ns())
    qa_profile(Path.home()/'Library/Application Support/LOVE'/identity)
    run=qa_run([str(args.love.resolve()),str(root/'tools/audio-profile-check')],cwd=root,
               env=dict(os.environ,AUDIO_PROFILE_QA_GUARDED='1',AUDIO_PROFILE_ROOT=str(root),POKEPORT_IDENTITY=identity),
               capture_output=True,text=True,timeout=90)
    args.report.with_suffix('.log').write_text(run.stdout+run.stderr)
    records=[line.removeprefix('AUDIO_PCM_RESULT ')for line in run.stdout.splitlines()if line.startswith('AUDIO_PCM_RESULT ')]
    if run.returncode or len(records)!=1:raise RuntimeError('native PCM probe failed; see its log')
    if any(hashlib.sha256((root/name).read_bytes()).hexdigest()!=value for name,value in hashes.items()):
        raise RuntimeError('measured source changed during the probe')
    report=json.loads(records[0]);report.update(sha256=hashes,playerProfilesUsed=False)
    args.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))


if __name__=='__main__':main()
