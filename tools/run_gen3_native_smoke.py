#!/usr/bin/env python3
"""Run a committed native edition candidate in a fresh, isolated macOS QA save.

The caller supplies a local cartridge and LÖVE binary. Nothing is uploaded.
The shared lock serializes native runs; a migration marker is written before
the first boot so no personal save is copied by SaveIdentity.
"""
import argparse
import ctypes
import errno
import gc
from datetime import datetime, timezone
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tarfile
from qa_storage import qa_cache, qa_run, qa_source

ROOT = Path(__file__).resolve().parents[1]


def freeze_engine(archive, destination, reference):
    """Freeze committed bytes; a working file is only a checked clone source."""
    hashes={};cloned=logical=0
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar:
            path=PurePosixPath(member.name)
            assert not path.is_absolute() and '..'not in path.parts
            target=destination/member.name
            if member.isdir():
                target.mkdir(parents=True,exist_ok=True);continue
            assert member.isfile(),'Unexpected non-regular Git archive member'
            data=tar.extractfile(member).read();digest=hashlib.sha256(data).hexdigest()
            target.parent.mkdir(parents=True,exist_ok=True)
            source=reference/member.name;copied=False
            if(os.uname().sysname=='Darwin'and len(data)>=16384 and source.is_file()
               and not source.is_symlink()and source.stat().st_size==len(data)
               and hashlib.sha256(source.read_bytes()).hexdigest()==digest):
                clone=ctypes.CDLL(None,use_errno=True).clonefile
                clone.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_int];clone.restype=ctypes.c_int
                if clone(os.fsencode(source),os.fsencode(target),0)==0:
                    assert target.stat().st_ino!=source.stat().st_ino
                    copied=True;cloned+=1;logical+=len(data)
                else:
                    error=ctypes.get_errno()
                    if error not in(errno.EXDEV,errno.ENOTSUP,errno.ENOSYS,errno.EINVAL):raise OSError(error,'clonefile')
            if not copied:
                with target.open('xb')as output:output.write(data)
            os.chmod(target,member.mode)
            assert hashlib.sha256(target.read_bytes()).hexdigest()==digest,'Frozen Git bytes changed'
            hashes[member.name]=digest
    return hashes,dict(independentClonedFiles=cloned,clonedLogicalBytes=logical,mutableHardlinks=False)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('edition', choices=['firered', 'leafgreen', 'ruby', 'sapphire', 'emerald'])
    p.add_argument('--rom', type=Path, required=True)
    p.add_argument('--love', type=Path, required=True)
    p.add_argument('--lock', type=Path, required=True)
    p.add_argument('--driver', default='tests/leafgreen_native_driver.lua')
    p.add_argument('--cache-identity')
    p.add_argument('--timeout', type=int, default=1200)
    p.add_argument('--speed', type=int, default=1)
    args = p.parse_args()
    assert not subprocess.check_output(['git', 'status', '--porcelain', '--untracked-files=no'], cwd=ROOT).strip(), 'Commit candidate and driver first'
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    identity = 'gen2recomp-qa-' + args.edition + '-' + datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S%f')
    if args.cache_identity:qa_source(Path.home()/'Library/Application Support/LOVE'/args.cache_identity)
    out = qa_cache(ROOT / '.local/qa' / identity)
    out.mkdir(parents=True)
    engine = out / 'engine'
    engine.mkdir()
    archive = subprocess.check_output(['git', 'archive', commit], cwd=ROOT)
    archive_sha256=hashlib.sha256(archive).hexdigest()
    hashes,allocation=freeze_engine(archive,engine,ROOT)
    # Nothing below executes from these in-memory buffers. Release them
    # before the native importer/renderer allocates its own cartridge data.
    del archive
    gc.collect()
    driver = engine / args.driver
    assert driver.is_file(), 'Driver must be committed in the source snapshot'
    # The Metal renderer is a QA host configuration for this macOS runtime.
    # All game, extractor and edition code comes from the immutable commit.
    host = out / 'host'
    host.mkdir()
    for file in engine.iterdir():
        if file.name not in ('conf.lua', 'main.lua'):
            (host / file.name).symlink_to(file, target_is_directory=file.is_dir())
    (host / 'engine-conf.lua').symlink_to(engine / 'conf.lua')
    (host / 'engine-main.lua').symlink_to(engine / 'main.lua')
    (host / 'main.lua').write_text("io.stdout:setvbuf('no')\nassert(love.filesystem.load('engine-main.lua'))()\nlove.errorhandler=function(e) print(debug.traceback(tostring(e),2));return function() return 1 end end\n")
    (host / 'conf.lua').write_text("love.filesystem.setSymlinksEnabled(true)\nassert(love.filesystem.load('engine-conf.lua'))()\nlocal base=love.conf\nfunction love.conf(t)base(t);t.version='12.0';t.graphics.renderers={'metal'}end\n")
    save_root = Path.home() / 'Library/Application Support/LOVE'
    save = save_root / identity
    save.mkdir()
    (save / 'migrated-from-pokemon-love2d.txt').write_text('Fresh own QA. Do not migrate player data.\n')
    with args.lock.open('a+') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.cache_identity:
            assert re.fullmatch(r'gen2recomp-qa-' + args.edition + r'-[0-9]+', args.cache_identity)
            cache = save_root / args.cache_identity / args.edition
            assert (cache / 'data/generated/pokemon.lua').is_file()
            previous = ROOT / '.local/qa' / args.cache_identity / 'engine'
            inputs = [engine / f'tools/rom_manifest_{args.edition}.json']
            inputs.extend((engine / 'src/import').rglob('*.lua'))
            for file in inputs:
                old = previous / file.relative_to(engine)
                assert old.is_file() and old.read_bytes() == file.read_bytes(), 'Cache extraction inputs changed; use a fresh import: ' + str(file.relative_to(engine))
            shutil.copytree(cache, save / args.edition)
        env = dict(os.environ, POKEPORT_IDENTITY=identity, POKEPORT_VERSION=args.edition,
                   POKEPORT_IMPORT_ROM=str(args.rom.resolve()), POKEPORT_DRIVER=str(driver),
                   POKEPORT_SPEED=str(args.speed),
                   POKEPORT_NO_MODS='1', POKEPORT_NO_BOOT_REPORT='1')
        receipt = dict(identity=identity, sourceCommit=commit,engineArchiveSHA256=archive_sha256,frozenInputAllocation=allocation,
                       cartridgeSHA1=hashlib.sha1(args.rom.read_bytes()).hexdigest(),
                       loveSHA256=hashlib.sha256(args.love.read_bytes()).hexdigest(),
                       driverSHA256=hashlib.sha256(driver.read_bytes()).hexdigest(),
                       qaRenderer='metal', qaHostConfigChanged=True, physicalIOSDeviceTested=False)
        (out / 'verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print('NATIVE_QA', out, flush=True)
        with (out / 'native.log').open('w') as log:
            run = qa_run([str(args.love.resolve()), str(host)], env=env,
                                 stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
        print('NATIVE_EXIT', run.returncode, flush=True)
        for file in save.iterdir():
            if file.suffix == '.png' or file.name == 'edition-result.json':
                shutil.copy2(file, out / file.name)
        assert run.returncode == 0, (out / 'native.log').read_text(errors='replace')[-8000:]
        for name,digest in hashes.items():
            assert hashlib.sha256((engine/name).read_bytes()).hexdigest()==digest,name
        receipt['engineFilesUnchanged']=len(hashes)
        (out/'verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
        report = json.loads((out / 'edition-result.json').read_text())
        assert report['status'] == 'pass'
        print('PASS_NATIVE_EDITION', out, flush=True)


if __name__ == '__main__':
    main()
