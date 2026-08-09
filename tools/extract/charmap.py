"""Extract the Gen1 text byte <-> glyph/token charmap.

Source: pokered/constants/charmap.asm -- `charmap "TOKEN", $NN` lines (one
byte value per token; TOKEN is a printable glyph for ordinary characters,
or a bracketed control token like "<PLAYER>"/"@" for terminators and
runtime substitutions). This is the encoding fixed-length name fields
(sPlayerName, sRivalName, party/box OT names, nicknames) use -- NOT the
same thing as data/generated/text.lua, which holds already-decoded
dialogue strings extracted from asm source text and never needed a raw
byte<->glyph table of its own.

Several byte VALUES are deliberately reused across different on-screen
graphics contexts later in the file (font_extra.png bold letters, then
font_battle_extra.png, then misc one-off glyphs, THEN the real A-Z table
at $80-$99, which unused Japanese katakana entries further down redefine
again at the same range) -- legal for RGBDS charmap (it only needs
token->byte to be unambiguous for encoding source text; nothing in this
English-only source ever assembles the literal token "ア", so its
redefinition is inert for the actual ROM). For our purposes it means:
- byToken[token] = byte is unambiguous either way (last-definition-wins,
  matching RGBDS's own semantics), used to ENCODE a name.
- byByte[byte] = token needs the FIRST definition of each byte, not the
  last, to DECODE a byte back to the international glyph that's actually
  in the shipped font at that position instead of a later vestigial
  redefinition (confirmed against the file: Latin "A".."Z" at $80-$99 are
  defined once, early, cleanly, before later `charmap "ア", $80` etc.
  entries that reuse those same bytes for characters this ROM's font
  never draws there).

Output: src/save_convert/data/charmap.lua (committed; independent of ROM
import, like data/palettes_gbc.lua)
  byByte[byte] = token   (first definition per byte -- see above)
  byToken[token] = byte  (last definition per token -- see above)
"""

import argparse
import os
import re
import sys

from . import util


def extract(pokered, out_path):
    path = os.path.join(pokered, "constants/charmap.asm")
    by_byte = {}
    by_token = {}
    for lineno, line in util.read_asm(path):
        s = line.strip()
        m = re.match(r'charmap\s+"((?:[^"\\]|\\.)*)"\s*,\s*(\S+)', s)
        if not m:
            continue
        token = m.group(1)
        value = util.parse_number(m.group(2))
        if not (0 <= value <= 255):
            util.die(f"{path}:{lineno}: byte value {value} out of range for {token!r}")
        if value not in by_byte:  # first definition wins for decoding
            by_byte[value] = token
        by_token[token] = value  # last definition wins for encoding

    if not by_byte:
        util.die(f"{path}: parsed 0 charmap entries")

    util.write_lua(
        out_path,
        {"source": "pokered constants/charmap.asm",
         "byByte": by_byte,
         "byToken": by_token},
        header="Gen1 text byte <-> glyph/token charmap (fixed-length name\n"
               "fields: player/rival/OT names, nicknames -- box/party mon\n"
               "names are NUL-free, '@' ($50) terminated, space-padded).\n"
               "byToken's key is the literal glyph for ordinary characters\n"
               "(\"A\", \"é\", ...) or a bracketed control token\n"
               "(\"<PLAYER>\", \"@\") for terminators/substitutions -- only\n"
               "the plain single-glyph entries are meaningful inside a name.")
    return by_byte, by_token


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--pokered", required=True)
    parser.add_argument("--out", default="src/save_convert/data/charmap.lua")
    args = parser.parse_args(argv)
    extract(args.pokered, args.out)
    return 0


if __name__ == "__main__":
    if __package__ is None:
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
        __package__ = "extract"
        from extract import util as util  # noqa: F811
    raise SystemExit(main())
