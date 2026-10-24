#!/usr/bin/env python3
"""Smoke-test the default helper path in an actual fused macOS LÖVE application."""
import argparse
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import zipfile

ROOT=Path(__file__).resolve().parents[3]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--love-app',type=Path,required=True)
parser.add_argument('--bundle',type=Path,required=True)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--intel',action='store_true')
args=parser.parse_args()
if sys.platform!='darwin':
    raise SystemExit('This probe requires macOS')
app=args.output.resolve()
if app.exists():
    raise SystemExit('Probe output must be a new directory')
shutil.copytree(args.love_app,app,symlinks=True)
resources=app/'Contents/Resources'
for old in resources.glob('*.love'):
    old.unlink()
subprocess.run([sys.executable,str(ROOT/'tools/slang-import/package.py'),'install','--bundle',str(args.bundle.resolve()),'--destination',str(resources/'shader-tools'),'--platform','macos','--arch','universal'],check=True)
with zipfile.ZipFile(resources/'game.love','w',zipfile.ZIP_DEFLATED) as archive:
    archive.write(ROOT/'tools/shader-browser-check/main.lua','main.lua')
    conf=(ROOT/'tools/shader-browser-check/conf.lua').read_text().replace('gen2-shader-browser-check','gen2-fused-shader-check-'+str(os.getpid()))
    archive.writestr('conf.lua',conf)
env=os.environ.copy()
env.pop('SHADER_BROWSER_HELPER',None)
env['SHADER_BROWSER_REPO']=str(ROOT)
command=[str(app/'Contents/MacOS/love')]
if args.intel:
    command=['/usr/bin/arch','-x86_64',*command]
process=subprocess.Popen(command,cwd=ROOT,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,start_new_session=True)
try:
    output,_=process.communicate(timeout=180)
except subprocess.TimeoutExpired:
    os.killpg(process.pid,signal.SIGKILL)
    output,_=process.communicate()
    print(output)
    raise SystemExit('Fused browser probe timed out')
print(output)
if process.returncode!=0 or 'native HTTPS/worker/GPU/install/repeat/cancel PASS' not in output:
    raise SystemExit('Fused browser probe failed')
print('Default fused-app helper lookup PASS ('+('Intel/Rosetta' if args.intel else 'native')+')')
