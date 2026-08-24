"""BPS patch reader -> the exact source->target offset mapping.

A BPS patch says, for every byte of the target, where it came from:
  0 SourceRead  copy from source at the SAME offset
  1 TargetRead  literal new bytes
  2 SourceCopy  copy from source at an arbitrary offset  <- the relocations
  3 TargetCopy  copy from earlier in the target
So it is a complete relocation map, which is exactly what a symbol table needs.
"""
import struct, zlib

def _varint(buf, pos):
    data, shift = 0, 1
    while True:
        x = buf[pos]; pos += 1
        data += (x & 0x7F) * shift
        if x & 0x80: break
        shift <<= 7
        data += shift
    return data, pos

def parse(patch):
    assert patch[:4] == b"BPS1", "not a BPS1 patch"
    pos = 4
    src_size, pos = _varint(patch, pos)
    dst_size, pos = _varint(patch, pos)
    meta_size, pos = _varint(patch, pos)
    meta = patch[pos:pos+meta_size]; pos += meta_size
    end = len(patch) - 12
    src_crc, dst_crc, patch_crc = struct.unpack("<III", patch[end:])
    actions = []
    out = 0; srel = 0; trel = 0
    while pos < end:
        data, pos = _varint(patch, pos)
        cmd, length = data & 3, (data >> 2) + 1
        if cmd == 0:
            actions.append((0, out, out, length)); out += length
        elif cmd == 1:
            actions.append((1, out, pos, length)); pos += length; out += length
        elif cmd == 2:
            raw, pos = _varint(patch, pos)
            srel += (-(raw >> 1) if (raw & 1) else (raw >> 1))
            actions.append((2, out, srel, length)); srel += length; out += length
        else:
            raw, pos = _varint(patch, pos)
            trel += (-(raw >> 1) if (raw & 1) else (raw >> 1))
            actions.append((3, out, trel, length)); trel += length; out += length
    return dict(src_size=src_size, dst_size=dst_size, meta=meta, actions=actions,
                src_crc=src_crc, dst_crc=dst_crc, patch_crc=patch_crc)

def apply(patch_info, source, patch_bytes):
    out = bytearray(patch_info["dst_size"])
    for cmd, o, arg, length in patch_info["actions"]:
        if cmd == 0:   out[o:o+length] = source[o:o+length]
        elif cmd == 1: out[o:o+length] = patch_bytes[arg:arg+length]
        elif cmd == 2: out[o:o+length] = source[arg:arg+length]
        else:
            for k in range(length): out[o+k] = out[arg+k]
    return bytes(out)
