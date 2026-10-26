#!/usr/bin/env python3
"""Verify original terrain-flag metadata against a local cartridge and pinned source."""
import argparse
import hashlib
import json
from pathlib import Path
import re

PROFILES = {
    'emerald': ('f3ae088181bf583e55daf962a92bb46f4f1d07b7', 0x486efc,
                '7aa89d639517803972b2b59ae36ab2852ea3eb22582a2908c15d6adb5c375471',
                'https://github.com/pret/pokeemerald/blob/3ec4d98de95a2aeb12f3c738b3496d0b3a830793/src/metatile_behavior.c'),
    'ruby': ('f28b6ffc97847e94a6c21a63cacf633ee5c8df1e', 0x308e2c,
             '62453418a51baf12a356300d843e88adb5a3e94f92e29b8ca71a0b5bef40d922',
             'https://github.com/pret/pokeruby/blob/5784633ce4ef7ade1a7f2d2d0c288e3d5e6cdd7f/src/metatile_behavior.c'),
    'sapphire': ('3ccbbd45f8553c36463f13b938e833f652b793e4', 0x308dbc,
                 '62453418a51baf12a356300d843e88adb5a3e94f92e29b8ca71a0b5bef40d922',
                 'https://github.com/pret/pokeruby/blob/5784633ce4ef7ade1a7f2d2d0c288e3d5e6cdd7f/src/metatile_behavior.c'),
}


def source_metadata(game, rom, source, offset=None):
    sha1, address, source_hash, url = PROFILES[game]
    assert hashlib.sha1(rom).hexdigest() == sha1, 'Wrong cartridge revision'
    assert hashlib.sha256(source).hexdigest() == source_hash, 'Wrong source revision'
    if offset is not None:
        assert offset == address, 'Matching symbol identity disagrees with public metadata'
    block = re.search(rb'sTileBitAttributes\[\]\s*=\s*\{(.*?)\};', source, re.S)
    assert block, 'Source flag table declaration changed'
    values = []
    for row in re.findall(rb'TILE_ATTRIBUTES\s*\(\s*(TRUE|FALSE)\s*,\s*(TRUE|FALSE)\s*,\s*(TRUE|FALSE)\s*\)', block[1]):
        values.append(sum(weight for value, weight in zip(row, [4, 2, 1]) if value == b'TRUE'))
    assert len(values) == 240, 'Unexpected source flag count'
    raw = rom[address:address + 240]
    assert raw == bytes(values), 'Cartridge flags differ from source semantics'
    assert rom[address + 1:address + 241] != raw, 'Shifted-range negative control did not differ'
    return dict(offset=address, count=240, sha256=hashlib.sha256(raw).hexdigest(),
                sourceSha256=source_hash, source=url)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('edition', choices=PROFILES)
    p.add_argument('--rom', type=Path, required=True)
    p.add_argument('--source', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    a = p.parse_args()
    metadata = source_metadata(a.edition, a.rom.read_bytes(), a.source.read_bytes())
    a.output.write_text(json.dumps(metadata, indent=2) + '\n')
    print('VERIFIED_SOURCE_FLAGS', a.edition, metadata['count'], metadata['sha256'])


if __name__ == '__main__':
    main()
