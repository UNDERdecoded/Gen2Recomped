#!/usr/bin/env python3
"""Compare the RS task/step in a local matching ELF and owned retail ROM.

No ROM, ELF, extracted bytes or absolute input paths are included in the report.
The independent C task model is the two-lap sub_80E0CD0 in pokeruby dark.c.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct


def symbols(raw):
    assert raw[:6] == b'\x7fELF\x01\x01', 'Expected little-endian ELF32'
    shoff = struct.unpack_from('<I', raw, 32)[0]
    size, count = struct.unpack_from('<HH', raw, 46)
    sections = [struct.unpack_from('<10I', raw, shoff + i * size) for i in range(count)]
    result = {}
    for section in sections:
        if section[1] != 2:
            continue
        strings = sections[section[6]]
        names = raw[strings[4]:strings[4] + strings[5]]
        for pos in range(section[4], section[4] + section[5], section[9]):
            name, address, length, info, other, index = struct.unpack_from('<IIIBBH', raw, pos)
            label = names[name:names.index(b'\0', name)].decode('utf8')
            if label not in ('sub_80E0A4C', 'sub_80E0CD0'):
                continue
            owner = sections[index]
            address &= ~1
            offset = owner[4] + address - owner[3]
            result[label] = (address, raw[offset:offset + length])
    assert len(result) == 2, 'Matching RS MetallicShine symbols not found'
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--rom', type=Path, required=True)
    p.add_argument('--elf', type=Path, required=True)
    p.add_argument('--report', type=Path)
    args = p.parse_args()
    rom, elf = args.rom.read_bytes(), args.elf.read_bytes()
    code = rom[0xAC:0xB0].decode('ascii')
    assert code in ('AXVE', 'AXPE'), 'US Ruby/Sapphire ROM required'
    functions = symbols(elf)
    report = dict(gameCode=code, revision=rom[0xBC], romSHA1=hashlib.sha1(rom).hexdigest(),
                  elfSHA256=hashlib.sha256(elf).hexdigest(), functions={})
    for name, (address, data) in functions.items():
        actual = rom[address - 0x08000000:address - 0x08000000 + len(data)]
        assert actual == data, f'{name}: ELF is not this retail ROM build'
        report['functions'][name] = dict(address=f'{address:08X}', bytes=len(data),
                                        sha256=hashlib.sha256(data).hexdigest(), retailExact=True)
    step = functions['sub_80E0CD0'][1]
    halfwords = struct.unpack('<' + 'H' * (min(260, len(step)) // 2), step[:min(260, len(step)) // 2 * 2])
    def count(op, value):
        return sum((word & 0xF800) == op and (word & 0xFF) == value for word in halfwords)
    counts = dict(add4=count(0x3000, 4), compare128=count(0x2800, 128),
                  add124=count(0x3000, 124), compare2=count(0x2800, 2))
    assert all(counts.values()), counts
    # C model: data10 += 4; BG1_X -= 4; at 128 reset data10 and add 128;
    # destroy when ++data11 == 2. Both ELF builds fuse the scroll/wrap into ADD124; the lap count differs.
    scroll = counter = laps = 0
    positions = [0]
    for frame in range(1, 65):
        counter += 4
        scroll -= 4
        if counter == 128:
            counter = 0
            scroll += 128
            laps += 1
        positions.append(scroll)
        assert scroll == -((frame * 4) % 128)
    assert laps == 2 and scroll == 0
    report.update(status='pass', signature=counts, taskFrames=64, laps=2,
                  frame31=positions[31], frame32=positions[32], frame63=positions[63], frame64=positions[64])
    text = json.dumps(report, indent=2) + '\n'
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text)
    print(text, end='')


if __name__ == '__main__':
    main()
