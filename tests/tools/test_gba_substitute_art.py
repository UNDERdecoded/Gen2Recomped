"""Reject ambiguous/invalid loader candidates before publishing import symbols."""
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))
from gba_substitute_art import discover
from gen3_discover import Rom, lz77_at


def literal(raw):
    out = bytearray((len(raw) << 8 | 16).to_bytes(4, "little"))
    for i in range(0, len(raw), 8):
        out.append(0)
        out.extend(raw[i:i + 8])
    return out


def loader(data, at=0x100):
    for delta, value in ((0, 0x040000D4), (4, 0x84000200),
                         (-0x5C, 0x08001000), (-12, 0x08002000),
                         (-4, 0x08004000), (-0x58, 0x0202401C), (-8, 0x0202401C)):
        struct.pack_into("<I", data, at + delta, value)


def fixture():
    data = bytearray(0x8000)
    for at, raw in ((0x1000, bytes((0x12, 0x23)) * 1024),
                    (0x2000, bytes((0x21, 0x32)) * 1024),
                    (0x4000, bytes(range(32)))):
        packed = literal(raw)
        data[at:at + len(packed)] = packed
    loader(data)
    return data


class SubstituteDiscovery(unittest.TestCase):
    def test_unique_native_loader(self):
        self.assertEqual(discover(Rom(fixture()), lz77_at),
                         {"front": 0x1000, "back": 0x2000, "palette": 0x4000, "loaderPool": 0x100})

    def test_ambiguous_loaders_are_refused(self):
        data = fixture()
        loader(data, 0x200)
        with self.assertRaisesRegex(ValueError, "found 2"):
            discover(Rom(data), lz77_at)

    def test_buffer_alias_must_match(self):
        data = fixture()
        struct.pack_into("<I", data, 0x100 - 8, 0x02024020)
        with self.assertRaisesRegex(ValueError, "found 0"):
            discover(Rom(data), lz77_at)

    def test_wrong_lz_size_is_rejected_before_decompression(self):
        data = fixture()
        data[0x1000:0x1004] = bytes((16, 0, 0, 255))
        calls = []
        def decode(rom, at):
            calls.append(at)
            return lz77_at(rom, at)
        with self.assertRaises(ValueError):
            discover(Rom(data), decode)
        self.assertEqual(calls, [])

    def test_bad_palette_is_refused(self):
        data = fixture()
        data[0x4006] |= 128
        with self.assertRaises(ValueError):
            discover(Rom(data), lz77_at)

    def test_truncated_lz_is_refused(self):
        data = fixture()
        struct.pack_into("<I", data, 0x100 - 0x5C, 0x08000000 + len(data) - 4)
        data[-4:] = bytes((16, 0, 8, 0))
        with self.assertRaises(ValueError):
            discover(Rom(data), lz77_at)

    def test_identical_sheets_are_refused(self):
        data = fixture()
        data[0x2000:0x2904] = data[0x1000:0x1904]
        with self.assertRaises(ValueError):
            discover(Rom(data), lz77_at)

    def test_unmapped_pointer_is_refused(self):
        data = fixture()
        struct.pack_into("<I", data, 0x100 - 4, 0x02004000)
        with self.assertRaises(ValueError):
            discover(Rom(data), lz77_at)


if __name__ == "__main__":
    unittest.main()
