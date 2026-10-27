#!/usr/bin/env python3
"""Relocate a Gen3 sibling manifest using matching, cartridge-verified ELFs.

Only symbol addresses and verification hashes are emitted. Supply your own
cartridges and matching pret builds; no ROM bytes or generated assets are saved.
"""
import argparse
import bisect
import copy
import hashlib
import json
from pathlib import Path
import re
import struct

BASE = 0x08000000


class Symbols:
    def __init__(self, elf, rom):
        data = Path(elf).read_bytes()
        assert data[:7] == b'\x7fELF\x01\x01\x01', 'Expected ELF32 little-endian'
        header = struct.unpack_from('<HHIIIIIHHHHHH', data, 16)
        assert header[1] == 40, 'Expected an ARM ELF'
        off, stride, count = header[5], header[10], header[11]
        sections = [struct.unpack_from('<10I', data, off + i * stride) for i in range(count)]
        self.by_name, self.by_address, self.starts = {}, {}, []
        self.rom = rom
        checked = 0
        for section in sections:
            _, kind, flags, address, pos, length, link, _, _, entry_size = section
            if flags & 2 and kind != 8 and BASE <= address < BASE + len(rom) and length:
                assert rom[address - BASE:address - BASE + length] == data[pos:pos + length], ('ELF differs from cartridge', hex(address))
                checked += length
            if kind != 2:
                continue
            strings = sections[link]
            names = data[strings[4]:strings[4] + strings[5]]
            filename = ''
            for i in range(pos, pos + length, entry_size):
                name_at, value, size, info, _, index = struct.unpack_from('<IIIBBH', data, i)
                name = names[name_at:names.find(b'\0', name_at)].decode()
                symbol_type = info & 15
                if symbol_type == 4:
                    filename = name
                if not name or name.startswith(('.', '$')) or not BASE <= value < BASE + len(rom) or index >= len(sections):
                    continue
                value = (value & ~1) if symbol_type == 2 else value
                row = dict(name=name, file=filename, at=value - BASE, size=size, type=symbol_type, binding=info >> 4)
                self.by_name.setdefault(name, []).append(row)
                self.by_address.setdefault(row['at'], []).append(row)
        assert checked > 1024 * 1024, 'No substantial cartridge-verified ROM sections'
        self.starts = sorted(self.by_address)
        self.checked_bytes = checked

    def owners(self, at):
        if at in self.by_address:
            return self.by_address[at]
        # The existing FRLG manifest deliberately points some scripts/texts
        # at the preceding terminator (frlgScriptStart skips that byte).
        # Preserve that explicit native convention, never a nearest-address
        # guess into an unrelated function or an unlabeled byte range.
        if self.rom[at] in (2, 3, 0xFE, 0xFF):
            boundary = [r for r in self.by_address.get(at + 1, [])
                        if 'EventScript_' in r['name'] or 'Text_' in r['name']]
            if boundary:
                return boundary
        i = bisect.bisect_right(self.starts, at) - 1
        if i < 0:
            return []
        return [r for r in self.by_address[self.starts[i]] if r['size'] and at < r['at'] + r['size']]


class Relocator:
    def __init__(self, source, target, aliases=None):
        self.source, self.target, self.records = source, target, {}
        self.aliases = aliases or {}

    def address(self, at):
        if at in self.records:
            return self.records[at]['target']
        matches = []
        for owner in self.source.owners(at):
            target_name = self.aliases.get(owner['name'], owner['name'])
            candidates = self.target.by_name.get(target_name, [])
            if owner['binding'] == 0:
                candidates = [r for r in candidates if r['file'] == owner['file']]
            for row in candidates:
                if row['type'] != owner['type']:
                    continue
                delta = at - owner['at']
                if delta < 0 and (delta != -1 or self.source.rom[at] != self.target.rom[row['at'] - 1]):
                    continue
                if delta > 0 and (owner['size'] != row['size'] or delta >= row['size']):
                    continue
                matches.append(dict(source=at, target=row['at'] + delta, symbol=owner['name'], targetSymbol=target_name,
                                    sourceFile=owner['file'], displacement=delta))
        targets = {r['target'] for r in matches}
        if len(targets) != 1:
            raise ValueError(f'Unresolved/ambiguous address {at:06X}: {matches[:4]}')
        self.records[at] = matches[0]
        return matches[0]['target']

    def tree(self, value, path=''):
        if isinstance(value, dict):
            return {k: self.tree(v, path + '/' + str(k)) for k, v in value.items()}
        if isinstance(value, list):
            return [self.tree(v, path + '/' + str(i)) for i, v in enumerate(value)]
        if isinstance(value, int) and not isinstance(value, bool) and 0x10000 <= value < 0x1000000:
            try:
                return self.address(value)
            except ValueError as exc:
                raise ValueError(path + ': ' + str(exc)) from exc
        return value


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('source-rom', 'target-rom', 'source-elf', 'target-elf', 'source-manifest', 'extractor', 'output'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--version', required=True)
    p.add_argument('--trade-profile', type=Path)
    p.add_argument('--stage-profile', type=Path)
    args = p.parse_args()
    source_rom, target_rom = args.source_rom.read_bytes(), args.target_rom.read_bytes()
    manifest = json.loads(args.source_manifest.read_text())
    assert hashlib.sha1(source_rom).hexdigest() == manifest['romSha1']
    source, target = Symbols(args.source_elf, source_rom), Symbols(args.target_elf, target_rom)
    aliases = {'sFlames_Gfx': 'sLeaves_Gfx', 'sFlames_Pal': 'sLeaves_Pal'} if args.version == 'leafgreen' else {}
    mapper = Relocator(source, target, aliases)
    result = mapper.tree(copy.deepcopy(manifest))
    result['romSha1'] = hashlib.sha1(target_rom).hexdigest()
    result['version'] = args.version
    result['romHeader'] = dict(title=target_rom[0xA0:0xAC].decode(), gameCode=target_rom[0xAC:0xB0].decode(),
                               makerCode=target_rom[0xB0:0xB2].decode(), revision=target_rom[0xBC])
    if args.stage_profile:
        profile = json.loads(args.stage_profile.read_text())
        if args.version == 'leafgreen':
            # LeafGreen has drifting leaves, no FireRed flame-position run.
            profile['FRLG_TITLE']['FLAME_X'] = False
        overrides = mapper.tree(profile, '/stageOverrides')
        if args.version == 'leafgreen':
            title = overrides['FRLG_TITLE']
            title.update(EFFECT='leaves', CRY='VENUSAUR')
            def target_address(name):
                rows = target.by_name[name]
                assert len(rows) == 1, name
                return rows[0]['at']
            title['STREAK'] = dict(GFX=target_address('sStreak_Gfx'), PAL=title['FLAMES']['PAL'], COLS=4, ROWS=2)
            title['STREAK_Y'] = target_address('sStreakYPositions')
        result.setdefault('stageOverrides', {}).update(overrides)
    if args.trade_profile:
        result['tradeArt'] = mapper.tree(json.loads(args.trade_profile.read_text()), '/tradeArt')
        result['tradeArt']['version'] = args.version
        result['tradeArt']['romKey'] = result['romHeader']['gameCode'] + str(result['romHeader']['revision'])
    # The two callback dispatch tables are keyed to FireRed, not Emerald.
    # Keep the classifier immutable and resolve the native callback per import.
    callbacks = {}
    raw = args.extractor.read_text()
    for name in ('FRLG_TARGET_LOCAL_LINEAR', 'FRLG_CALLBACK_PATH'):
        table = re.search(r'RomExtractorGen3\.' + name + r' = \{(.*?)\n\}', raw, re.S)
        assert table, name
        for token in re.findall(r'\[0x([0-9A-Fa-f]+)\]', table[1]):
            at = int(token, 16)
            callbacks[f'{mapper.address(at):06X}'] = at
    result['callbackAddressMap'] = callbacks
    result['symbolSource'] = 'Matching pret ELF symbols verified byte-for-byte against the supplied cartridges; tools/gen3_sibling_manifest.py'
    result['siblingProvenance'] = dict(sourceManifestSHA256=hashlib.sha256(args.source_manifest.read_bytes()).hexdigest(),
                                     sourceROM=manifest['romSha1'], targetROM=result['romSha1'],
                                     sourceELFSHA256=hashlib.sha256(args.source_elf.read_bytes()).hexdigest(),
                                     targetELFSHA256=hashlib.sha256(args.target_elf.read_bytes()).hexdigest(),
                                     sourceVerifiedBytes=source.checked_bytes, targetVerifiedBytes=target.checked_bytes,
                                     addresses=sorted(mapper.records.values(), key=lambda r: r['source']))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2) + '\n')
    print('VERIFIED_SIBLING_MANIFEST', args.version, len(mapper.records), 'addresses')


if __name__ == '__main__':
    main()
