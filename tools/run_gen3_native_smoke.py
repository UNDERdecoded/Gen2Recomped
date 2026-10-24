#!/usr/bin/env python3
"""Run a committed native edition candidate in a fresh, isolated macOS QA save.

The caller supplies a local cartridge and LÖVE binary. Nothing is uploaded.
The shared lock serializes native runs; a migration marker is written before
the first boot so no personal save is copied by SaveIdentity.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tarfile

ROOT = Path(__file__).resolve().parents[1]


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
    archive = subprocess.check_output(['git', 'archive', commit], cwd=ROOT)
    identity = 'gen2recomp-qa-' + args.edition + '-' + datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S%f')
    out = ROOT / '.local/qa' / identity
    out.mkdir(parents=True)
    engine = out / 'engine'
    engine.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        tar.extractall(engine, filter='data')
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
        receipt = dict(identity=identity, sourceCommit=commit,
                       cartridgeSHA1=hashlib.sha1(args.rom.read_bytes()).hexdigest(),
                       loveSHA256=hashlib.sha256(args.love.read_bytes()).hexdigest(),
                       driverSHA256=hashlib.sha256(driver.read_bytes()).hexdigest(),
                       qaRenderer='metal', qaHostConfigChanged=True, physicalIOSDeviceTested=False)
        (out / 'verification.json').write_text(json.dumps(receipt, indent=2) + '\n')
        print('NATIVE_QA', out, flush=True)
        with (out / 'native.log').open('w') as log:
            run = subprocess.run([str(args.love.resolve()), str(host)], env=env,
                                 stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
        print('NATIVE_EXIT', run.returncode, flush=True)
        for file in save.iterdir():
            if file.suffix == '.png' or file.name == 'edition-result.json':
                shutil.copy2(file, out / file.name)
        assert run.returncode == 0, (out / 'native.log').read_text(errors='replace')[-8000:]
        report = json.loads((out / 'edition-result.json').read_text())
        assert report['status'] == 'pass'
        print('PASS_NATIVE_EDITION', out, flush=True)


if __name__ == '__main__':
    main()
