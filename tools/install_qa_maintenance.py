#!/usr/bin/env python3
"""Install the tested cleanup as a reversible, user-only macOS LaunchAgent."""
import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

FILES = ('qa_storage.py', 'qa_legacy_storage.py', 'qa_preserved.py', 'qa_maintenance.py')
LABEL = 'com.maarten.origami-qa-cleanup'


def application(home, source):
    app=home/'Applications/Origami QA Cleanup.app'
    contents=app/'Contents';resources=contents/'Resources';macos=contents/'MacOS'
    resources.mkdir(parents=True,exist_ok=True);macos.mkdir(exist_ok=True)
    swift=source/'qa_maintenance_app.swift';saved=resources/'runner.swift';binary=macos/'OrigamiQACleanup'
    if not saved.exists() or saved.read_bytes()!=swift.read_bytes() or not binary.exists():
        subprocess.run(['xcrun','swiftc','-swift-version','5','-O',str(swift),'-o',str(binary)],check=True)
        saved.write_bytes(swift.read_bytes())
        info=dict(CFBundleIdentifier=LABEL,CFBundleExecutable='OrigamiQACleanup',CFBundleName='Origami QA Cleanup',
                  CFBundleDisplayName='Origami QA Cleanup',CFBundleVersion='1',CFBundlePackageType='APPL',LSUIElement=True,
                  NSDocumentsFolderUsageDescription='Alte QA-Testkopien in den bekannten Projektordnern automatisch aufräumen; Quellcode und Modelle sichern, Spielstände behalten.')
        (contents/'Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['codesign','--force','--sign','-',str(app)],check=True,capture_output=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    return app


def install(roots, *, home=None, load=True, python=None):
    home = Path(home or Path.home()).resolve();roots = [Path(root).resolve() for root in roots]
    if not roots or any(not root.is_relative_to(home) or not root.is_dir() for root in roots):
        raise ValueError('Provide existing local user project roots')
    source = Path(__file__).resolve().parent
    contents = {name:(source/name).read_bytes() for name in FILES}
    version = hashlib.sha256(b''.join(contents.values())).hexdigest()[:16]
    destination = home/'.local/lib/origami-qa-storage'/version
    destination.parent.mkdir(parents=True, exist_ok=True)
    if not destination.exists():
        with tempfile.TemporaryDirectory(dir=destination.parent, prefix='.install-') as tmp:
            staged = Path(tmp)/'package';staged.mkdir()
            for name, data in contents.items():(staged/name).write_bytes(data)
            staged.rename(destination)
    interpreter = python or ('/usr/bin/python3' if Path('/usr/bin/python3').exists() else shutil.which('python3'))
    subprocess.run([interpreter, '-c', 'import sys; assert sys.version_info >= (3,9); import qa_storage, qa_maintenance'], cwd=destination, check=True)
    state = home/'.cache/origami-qa-storage';state.mkdir(parents=True, exist_ok=True)
    plist_path = home/'Library/LaunchAgents'/f'{LABEL}.plist';plist_path.parent.mkdir(parents=True, exist_ok=True)
    arguments=[str(interpreter),str(destination/'qa_maintenance.py'),'--root',str(roots[0])]
    if load:
        app=application(home,source)
        arguments=['/usr/bin/open','-W','-g','-n','-a',str(app),'--args',str(destination/'qa_maintenance.py'),'--root',str(roots[0])]
    plist = dict(Label=LABEL, ProgramArguments=arguments,
                 StartInterval=900,RunAtLoad=True,ProcessType='Background',Nice=10,LowPriorityIO=True,
                 StandardOutPath='/dev/null',StandardErrorPath='/dev/null')
    with (state/'collection.lock').open('a+') as lock:
        # Avoid stopping a previous maintenance version halfway through a copy.
        fcntl.flock(lock,fcntl.LOCK_EX)
        if load:subprocess.run(['launchctl','bootout',f'gui/{os.getuid()}/{LABEL}'],capture_output=True)
        for root in roots:
            pointer = state/(hashlib.sha256(os.fsencode(str(root))).hexdigest()+'.inputs')
            temporary = pointer.with_suffix('.install.tmp');temporary.write_text(str(root));temporary.replace(pointer)
        temporary = plist_path.with_suffix('.tmp');temporary.write_bytes(plistlib.dumps(plist));temporary.replace(plist_path)
    if load:subprocess.run(['launchctl','bootstrap',f'gui/{os.getuid()}',str(plist_path)],check=True)
    return plist_path, destination


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',action='append',type=Path,required=True)
    args=parser.parse_args();plist,package=install(args.root)
    print('Installed',plist,'using',package)
