#!/usr/bin/env python3
"""Generate label/address facts without copying any ROM text or importer code."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess

STORAGE_LABELS = [
    "gText_WithdrawPokemon", "gText_DepositPokemon", "gText_MovePokemon", "gText_MoveItems", "gText_SeeYa",
    "gText_WithdrawMonDescription", "gText_DepositMonDescription", "gText_MoveMonDescription",
    "gText_MoveItemsDescription", "gText_SeeYaDescription",
]

REFERENCE = '535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91'
ROOT = Path(__file__).resolve().parents[2]


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()


def header(version):
    return (f'-- Generated label/address facts for {version}; no cartridge prose.\n'
            f'-- Gen1Recomp public import metadata at {REFERENCE}.\n'
            '-- Regenerate with tools/rom-text-contract-check/generate-labels.py.\n')


def encode(name):
    if not re.fullmatch(r'[A-Za-z0-9_:.]+', name):
        raise ValueError('unexpected native symbol name: ' + name)
    return '[' + json.dumps(name) + ']'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--gen1', type=Path, required=True)
    p.add_argument('--lua', default=os.environ.get('LUA', 'luajit'))
    p.add_argument('--check', action='store_true')
    a = p.parse_args()
    source = a.gen1.resolve()
    if git(source, 'rev-parse', 'HEAD') != REFERENCE or git(source, 'status', '--porcelain'):
        p.error('Gen1 must be clean at ' + REFERENCE)
    output = ROOT / 'src/mods/rom_text_labels'
    generated = {}
    for version in ['gold', 'silver', 'crystal']:
        manifest = json.loads((source / 'tools' / ('rom_manifest_' + version + '.json')).read_text())
        labels = manifest['text']['labels']
        assert len(set(labels)) == len(labels)
        generated[version] = header(version) + 'return {\n' + ''.join(
            f'  {encode(label)} = true,\n' for label in sorted(labels)) + '}\n'
        print(version, len(labels), 'native prose labels')
    for version in ['firered', 'emerald']:
        run = subprocess.run([a.lua, str(ROOT / 'tools/rom-text-contract-check/export-labels.lua'), version],
                             cwd=source, text=True, capture_output=True, timeout=30)
        lines = [x[len('ROM_LABEL_FACTS '):] for x in run.stdout.splitlines() if x.startswith('ROM_LABEL_FACTS ')]
        if run.returncode or len(lines) != 1:
            raise RuntimeError(run.stdout + run.stderr)
        facts = json.loads(lines[0])
        facts = {'text': {key: facts['text'][key] for key in STORAGE_LABELS}, 'battle': {}}
        content = header(version) + 'return {\n'
        for kind in ['text', 'battle']:
            if not facts[kind]:
                content += f'  {kind} = {{}},\n'
                continue
            content += f'  {kind} = {{\n'
            for label, offset in sorted(facts[kind].items()):
                assert isinstance(offset, int) and 0 <= offset < 0x1000000, (version, label, offset)
                content += f'    {encode(label)} = 0x{offset:06X},\n'
            content += '  },\n'
        generated[version] = content + '}\n'
        print(version, len(facts['text']), 'text /', len(facts['battle']), 'battle addresses')
    assert not git(source, 'status', '--porcelain'), 'reference changed'
    if not a.check:
        output.mkdir(parents=True, exist_ok=True)
    for version, content in generated.items():
        path = (ROOT / 'tests/rom_text' / ('labels_' + version + '.lua')
                if version in ['firered', 'emerald'] else output / (version + '.lua'))
        if a.check:
            if path.read_text() != content:
                raise AssertionError(f'stale label facts: {path}')
        else:
            path.write_text(content)


if __name__ == '__main__':
    main()
