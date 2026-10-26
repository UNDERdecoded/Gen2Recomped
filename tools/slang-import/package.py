#!/usr/bin/env python3
"""Build and install an optional, architecture-checked desktop converter bundle."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import struct
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / 'tools/slang-import'
NAME = 'gen2-slang-import'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def binary_kind(path):
    data = path.read_bytes()
    cpu = {0x01000007: 'x86_64', 0x0100000C: 'aarch64'}
    if data[:4] == b'\x7fELF' and len(data) >= 64 and data[4:6] == b'\x02\x01':
        arch = {62: 'x86_64', 183: 'aarch64'}.get(struct.unpack_from('<H', data, 18)[0])
        if arch:
            return 'linux', {arch}
    if data[:2] == b'MZ' and len(data) >= 64:
        pos = struct.unpack_from('<I', data, 60)[0]
        if pos + 6 <= len(data) and data[pos:pos+4] == b'PE\0\0':
            arch = {0x8664: 'x86_64', 0xAA64: 'aarch64'}.get(struct.unpack_from('<H', data, pos+4)[0])
            if arch:
                return 'windows', {arch}
    if data[:4] in (b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf') and len(data) >= 32:
        endian = '<' if data[0] == 0xCF else '>'
        arch = cpu.get(struct.unpack_from(endian+'I', data, 4)[0])
        if arch:
            return 'macos', {arch}
    if data[:4] == b'\xca\xfe\xba\xbe' and len(data) >= 8:
        count = struct.unpack_from('>I', data, 4)[0]
        if count not in (1, 2) or len(data) < 8 + count*20:
            raise ValueError('Invalid universal Mach-O header')
        arches = set()
        for i in range(count):
            kind, _, offset, size, _ = struct.unpack_from('>IIIII', data, 8+i*20)
            if kind not in cpu or offset+size > len(data) or size < 32:
                raise ValueError('Invalid universal Mach-O slice')
            arches.add(cpu[kind])
        if len(arches) == count:
            return 'macos', arches
    raise ValueError('Unsupported converter executable format/architecture')


def verify(bundle, system, arch):
    if bundle.is_symlink():
        raise ValueError('Symlink bundle refused')
    receipt=bundle/'manifest.json'
    if receipt.is_symlink() or receipt.stat().st_size>2*1024*1024:
        raise ValueError('Invalid bundle receipt')
    manifest = json.loads(receipt.read_text())
    if manifest.get('format') != 1 or manifest.get('tool') != NAME:
        raise ValueError('Unknown converter bundle')
    expected = manifest.get('files')
    if not isinstance(expected, dict) or not expected or len(expected) > 4096:
        raise ValueError('Invalid bundle file manifest')
    actual = {}
    for path in bundle.rglob('*'):
        if path.is_symlink():
            raise ValueError('Symlink bundle resource refused')
        if path.is_file() and path.relative_to(bundle).as_posix() != 'manifest.json':
            actual[path.relative_to(bundle).as_posix()] = digest(path)
    if actual != expected:
        raise ValueError('Converter bundle is incomplete, changed or contains unlisted files')
    if manifest.get('platform') != system:
        raise ValueError('Converter platform mismatch')
    executable = bundle/(NAME + ('.exe' if system == 'windows' else ''))
    found_system, arches = binary_kind(executable)
    required = {'x86_64', 'aarch64'} if arch == 'universal' else {arch}
    if found_system != system or not required <= arches:
        raise ValueError(f'Converter architecture mismatch: expected {system}/{arch}, found {found_system}/{sorted(arches)}')
    if manifest.get('platform') != found_system or sorted(arches) != manifest.get('architectures'):
        raise ValueError('Converter architecture metadata differs')
    if not any(p.startswith('notices/') for p in actual) or 'DEPENDENCIES.json' not in actual:
        raise ValueError('Converter notices are missing')
    return executable


def install(bundle, destination, system, arch, optional=False):
    if not bundle.exists() and optional:
        print('Optional shader converter unavailable; local presets remain usable')
        return False
    verify(bundle, system, arch)
    if destination.exists():
        raise ValueError('Converter destination already exists')
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.shader-package-', dir=destination.parent) as temp:
        staged = Path(temp)/'shader-tools'
        shutil.copytree(bundle, staged)
        executable = verify(staged, system, arch)
        executable.chmod(0o755)
        staged.rename(destination)
    return True


def notices(metadata, output):
    dependencies = []
    for package in metadata['packages']:
        if package['name'] == NAME:
            continue
        source = Path(package['manifest_path']).parent
        copied = []
        for path in source.rglob('*'):
            if not path.is_file() or path.is_symlink():
                continue
            parts = path.relative_to(source).parts
            if any(p in ('.git', 'target') for p in parts):
                continue
            lower = path.name.lower()
            license_dir = any(p.lower() == 'licenses' for p in parts[:-1])
            if license_dir or lower.startswith(('license', 'licence', 'copying', 'notice', 'copyright')):
                # Registry archives contain bounded license text, never build output.
                if path.stat().st_size > 1024*1024:
                    raise ValueError(f'Oversized notice: {package["name"]}/{path.name}')
                relative = Path('notices')/(package['name']+'-'+package['version'])/path.relative_to(source)
                target = output/relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
                copied.append(relative.as_posix())
        # Ship the exact source archive pinned by Cargo.lock, including MPL source form.
        source_root=source.parent.parent.parent/'cache'/source.parent.name
        archive=source_root/(package['name']+'-'+package['version']+'.crate')
        lock=(TOOL/'Cargo.lock').read_text()
        checksum=None
        for block in re.split(r'(?m)^\[\[package\]\]\s*$',lock):
            fields=dict(re.findall(r'(?m)^(name|version|checksum) = "([^"\n]+)"$',block))
            if fields.get('name')==package['name'] and fields.get('version')==package['version']:
                checksum=fields.get('checksum');break
        if not checksum or digest(archive)!=checksum:
            raise ValueError('Source archive missing or differs from Cargo.lock: '+package['name'])
        original=Path('sources')/archive.name
        (output/'sources').mkdir(exist_ok=True)
        shutil.copyfile(archive,output/original)
        dependencies.append({key: package.get(key) for key in ('name', 'version', 'license', 'repository','authors') } | {'notices': copied,'source_archive':original.as_posix(),'source_sha256':checksum})
    # Some registry archives omit their repository's license files. Keep exact pinned originals too.
    extra=TOOL/'licenses'
    provenance=json.loads((extra/'provenance.json').read_text())
    for entry in provenance:
        if digest(extra/entry['file'])!=entry['sha256']:
            raise ValueError('Pinned upstream notice changed')
    shutil.copytree(extra,output/'notices/upstream')
    (output/'DEPENDENCIES.json').write_text(json.dumps(dependencies, indent=2)+'\n')
    for name in ('LICENSE', 'LICENSE.MD'):
        if (ROOT/name).is_file():
            shutil.copyfile(ROOT/name, output/('PROJECT-'+name))


def build(output, universal=False):
    cargo = os.environ.get('CARGO', 'cargo')
    host = next(line.split(': ', 1)[1] for line in subprocess.check_output(['rustc', '-vV'], text=True).splitlines() if line.startswith('host: '))
    if universal and platform.system() != 'Darwin':
        raise ValueError('Universal macOS builds require macOS')
    targets = ['aarch64-apple-darwin', 'x86_64-apple-darwin'] if universal else [host]
    metadata = json.loads(subprocess.check_output([cargo, 'metadata', '--manifest-path', str(TOOL/'Cargo.toml'), '--locked', '--format-version', '1'], text=True))
    binaries = []
    for target in targets:
        command = [cargo, 'build', '--manifest-path', str(TOOL/'Cargo.toml'), '--locked', '--release']
        if target != host:
            command += ['--target', target]
        env=os.environ.copy()
        if 'windows' in target:
            env['RUSTFLAGS']=(env.get('RUSTFLAGS','')+' -C target-feature=+crt-static').strip()
        subprocess.run(command, check=True,env=env)
        directory = Path(metadata['target_directory'])
        if target != host:
            directory /= target
        binaries.append(directory/'release'/(NAME+('.exe' if 'windows' in target else '')))
    if output.exists():
        raise ValueError('Converter bundle output already exists')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.shader-build-', dir=output.parent) as temp:
        stage = Path(temp)/'shader-tools'
        stage.mkdir()
        executable = stage/binaries[0].name
        if universal:
            subprocess.run(['lipo', '-create', *map(str, binaries), '-output', str(executable)], check=True)
        else:
            shutil.copyfile(binaries[0], executable)
        executable.chmod(0o755)
        system, arches = binary_kind(executable)
        notices(metadata, stage)
        files = {p.relative_to(stage).as_posix(): digest(p) for p in sorted(stage.rglob('*')) if p.is_file()}
        commit = subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip()
        manifest = {'format': 1, 'tool': NAME, 'platform': system, 'architectures': sorted(arches), 'source_commit': commit, 'lock_sha256': digest(TOOL/'Cargo.lock'), 'files': files}
        (stage/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        verify(stage, system, 'universal' if universal else next(iter(arches)))
        stage.rename(output)
    print(f'Converter bundle built: {output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    b = sub.add_parser('build')
    b.add_argument('--output', type=Path, default=ROOT/'shader-tools')
    b.add_argument('--universal-macos', action='store_true')
    for command in ('install', 'verify'):
        p = sub.add_parser(command)
        p.add_argument('--bundle', type=Path, default=ROOT/'shader-tools')
        p.add_argument('--platform', choices=['macos', 'windows', 'linux'], required=True)
        p.add_argument('--arch', choices=['universal', 'x86_64', 'aarch64'], required=True)
        if command == 'install':
            p.add_argument('--destination', type=Path, required=True)
            p.add_argument('--optional', action='store_true')
    args = parser.parse_args()
    if args.command == 'build':
        build(args.output.resolve(), args.universal_macos)
    elif args.command == 'install':
        install(args.bundle, args.destination, args.platform, args.arch, args.optional)
    else:
        verify(args.bundle, args.platform, args.arch)


if __name__ == '__main__':
    main()
