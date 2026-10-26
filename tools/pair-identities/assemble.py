#!/usr/bin/env python3
"""Assemble semantic pair metadata from the pinned reference census export."""
import argparse
import json
from pathlib import Path

EDITIONS = ('firered', 'leafgreen', 'emerald', 'ruby', 'sapphire')


def assemble(directory):
    output = ['-- Public semantic names and source addresses; no cartridge content.',
              '-- Reference: 37a49b31f458d51ea9e00b90f2a247272ad09cb8',
              '-- Regenerate with tools/pair-identities/export.lua and assemble.py.', 'return {']
    for edition in EDITIONS:
        rows = json.loads((directory / (edition + '.json')).read_text())
        pairs, names, maps, banks = {}, {}, set(), {}
        for row in rows:
            assert row['id'] not in maps, 'Duplicate census map'
            maps.add(row['id'])
            key = row['primary'], row['secondary']
            assert all(type(n) is int and 0 <= n < 0x2000000 for n in key)
            value = row['pair'], row['primaryName'], row['secondaryName'], row['tileset']
            assert all(type(n) is str and n for n in value)
            assert key not in pairs or pairs[key] == value, 'Ambiguous source pair'
            assert row['pair'] not in names or names[row['pair']] == key, 'Ambiguous semantic name'
            for role, address, name in [(False, row['primary'], row['primaryName']), (True, row['secondary'], row['secondaryName'])]:
                bank = role, name
                assert bank not in banks or banks[bank] == address, 'Ambiguous source bank name'
                banks[bank] = address
            pairs[key], names[row['pair']] = value, key
        output.append('  ' + edition + ' = {')
        for key, names in sorted(pairs.items()):
            output.append('    {%d, %d, %s},' % (*key, ', '.join(json.dumps(v) for v in names)))
        output.append('  },')
    output.append('}')
    return '\n'.join(output) + '\n'


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('exports', type=Path)
    p.add_argument('--output', required=True, type=Path)
    a = p.parse_args()
    a.output.write_text(assemble(a.exports))


if __name__ == '__main__':
    main()
