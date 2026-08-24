#!/usr/bin/env python3
"""Build tools/rom_manifest_polishedcrystal.json from a Polished Crystal build.

Polished Crystal is the opposite of Prism: it is a full public disassembly that
BUILDS ITS OWN ROM, so there is nothing to recover by signature matching. The
build emits a real rgblink symbol file with every label in it, which is why this
script is thirty lines of parsing rather than tools/prism_symbols.py's search.

    git clone --depth 1 https://github.com/Rangi42/polishedcrystal.git
    git clone --depth 1 --branch v1.0.0 https://github.com/gbdev/rgbds.git
    make -C rgbds && PATH=$PWD/rgbds:$PATH make -C polishedcrystal

    python3 tools/polished_symbols.py \\
        --sym polishedcrystal/polishedcrystal-3.2.3.sym \\
        --rom polishedcrystal/polishedcrystal-3.2.3.gbc \\
        --charmap polishedcrystal/constants/charmap.asm \\
        --out tools/rom_manifest_polishedcrystal.json \\
        --sym-out tools/pokepolished.sym

THE BUILD IS REPRODUCIBLE, which is the whole reason the hash below can be
trusted. `COPYRIGHT = @$(shell date '+%Y')` in the Makefile looks like it stamps
the build year into the ROM -- it does not reach the image: forcing
gfx/title/version.2bpp to regenerate with a different year produced a
byte-identical ROM (verified 2026-08-19, 0 of 2097152 bytes changed). So a build
made today has the same sha1 as the released 3.2.3 cartridge.

Everything ROM-POSITIONAL other than the symbols is left EMPTY on purpose. See
the `notes` field in the output and [[polished-crystal-support]] in project
memory for what an import still needs.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re


def sha1_file(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def md5_file(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


SYM_LINE = re.compile(r"^([0-9A-Fa-f]{2,4}):([0-9A-Fa-f]{4})\s+(\S+)\s*$")


def parse_sym(path):
    """rgblink .sym -> {name: [bank, addr]}.

    Later definitions win, matching how the rest of the toolchain reads these:
    a bank's local label can repeat a name that also exists globally, and the
    global one is written last.
    """
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        line = line.strip()
        if not line or line.startswith(";"):
            continue
        m = SYM_LINE.match(line)
        if not m:
            continue
        bank, addr, name = m.group(1), m.group(2), m.group(3)
        out[name] = [int(bank, 16), int(addr, 16)]
    return out


# `charmap "X", $YY` -- the plain entries. The ctxtmap macro's are Huffman leaf
# characters and are deliberately NOT folded in here: they are only meaningful
# with the tree, and a reader that treated them as ordinary bytes would decode
# compressed text into noise. See the note in the manifest.
CHARMAP_LINE = re.compile(r'^\s*charmap\s+"((?:[^"\\]|\\.)*)"\s*,\s*\$([0-9A-Fa-f]+)')


def parse_charmap(path):
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = CHARMAP_LINE.match(line)
        if not m:
            continue
        text, byte = m.group(1), int(m.group(2), 16)
        out[str(byte)] = text.replace("\\\\", "\\").replace('\\"', '"')
    return out


def rom_header(path):
    with open(path, "rb") as f:
        b = f.read(0x150)
    return {
        "title": b[0x134:0x13F].decode("latin1").rstrip("\0"),
        "manufacturer": b[0x13F:0x143].decode("latin1"),
        "cgb": b[0x143],
        "licenseeNew": b[0x144:0x146].decode("latin1"),
        "sgb": b[0x146],
        "cartridge": b[0x147],
        "romSize": b[0x148],
        "ramSize": b[0x149],
        "destination": b[0x14A],
        "licenseeOld": b[0x14B],
        "romVersion": b[0x14C],
    }


NOTES = (
    "Polished Crystal 3.2.3, a CRYSTAL hack built from Rangi42/polishedcrystal "
    "with rgbds v1.0.0. UNLIKE PRISM, NOTHING HERE IS GUESSED: the symbol table "
    "is the build's own rgblink output, so every address is exact. "
    "Every other ROM-positional table is deliberately EMPTY -- copying "
    "Crystal's would feed Crystal addresses into a Polished Crystal import, "
    "which is the failure mode this file exists to prevent. "
    "TEXT NEEDS A HUFFMAN DECODER: Polished Crystal replaced Gen 2's "
    "charmap+ngram scheme with Huffman-compressed text, so the charmap below "
    "covers the plain control and literal bytes only. The `textCompression` "
    "block carries the full decoder spec, read out of home/text.asm's "
    "ReadHuffmanChar -- it is about thirty lines to implement, not a research "
    "problem."
)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--sym", required=True, help="polishedcrystal-<v>.sym from the build")
    ap.add_argument("--rom", required=True, help="polishedcrystal-<v>.gbc from the build")
    ap.add_argument("--charmap", help="constants/charmap.asm from the source tree")
    # THE CHARMAP IS SOURCE-DERIVED, THE SYMBOLS ARE BUILD-DERIVED, and they do
    # not have to be regenerated together. Rebuilding the manifest against a
    # different build of the SAME version needs the new .sym and the new .gbc
    # and nothing else -- but without this the charmap parsed out of a source
    # tree that is no longer on the machine would be silently dropped, and a
    # manifest with an empty charmap decodes every plain-text byte as noise.
    ap.add_argument("--charmap-from", metavar="MANIFEST",
                    help="reuse the charmap from an existing manifest JSON "
                         "when the source tree is not to hand")
    ap.add_argument("--out", required=True, help="manifest JSON to write")
    ap.add_argument("--sym-out", help="also copy the .sym here (tools/pokepolished.sym)")
    ap.add_argument("--version", default="3.2.3")
    args = ap.parse_args()

    symbols = parse_sym(args.sym)
    charmap = parse_charmap(args.charmap) if args.charmap else {}
    if not charmap and args.charmap_from:
        with open(args.charmap_from, encoding="utf-8") as f:
            charmap = json.load(f).get("charmap") or {}
    sha1 = sha1_file(args.rom)

    data = {
        "format": 3,
        "generation": 2,
        "base": "crystal",
        "version": "polishedcrystal",
        "gameVersion": args.version,
        "stub": True,
        "phase": "polishedcrystal-symbols",
        "romSha1": sha1,
        "romMd5": md5_file(args.rom),
        "romHeader": rom_header(args.rom),
        "symbolSource": (
            "rgblink output of a reproducible rgbds v1.0.0 build of "
            f"Rangi42/polishedcrystal v{args.version} ({len(symbols)} symbols)"
        ),
        "symbols": symbols,
        "charmap": charmap,
        # The whole decoder, from home/text.asm's ReadHuffmanChar. Recorded as
        # data rather than prose because the next reader needs to WRITE this,
        # and every constant below is one the code asserts on.
        "textCompression": {
            "scheme": "huffman",
            # Flat array of child node ids, indexed tree[node * 2 + branch].
            # Bank 0, so the file offset is the address.
            "treeSymbol": "TextCompressionHuffmanTree",
            "tree": symbols.get("TextCompressionHuffmanTree"),
            "rootNodeId": 0x00,
            # A node id below this is a parent: keep walking.
            "firstLeafNodeId": 0x7F,
            # At or above this, the leaf id is SHIFTED: the character is
            # id - (firstShiftedLeafNodeId - firstShiftedLeafCharId).
            "firstShiftedLeafNodeId": 0xEC,
            "firstShiftedLeafCharId": 0x4D,
            # Bits are consumed MSB first (`sla c`), eight per stream byte.
            "bitOrder": "msb",
            # CheckTerminatorChar (00:$1290), READ OUT OF THE ROM rather than
            # off the source: `cp $53 / ret z / cp $52 / ret z / cp $54 / ret`.
            # THREE bytes, not the two the source reading gave -- and the two
            # it did give were named ("@", "<DONE>") rather than numbered,
            # which is not something a decoder can act on.
            "terminatorChars": [0x53, 0x52, 0x54],
            # ReadHuffmanChar, verbatim, as the byte ranges it tests:
            #   [$00,$7f)  a parent -- the value is the next node index
            #   [$7f,$ec)  a leaf -- the character IS the value
            #   [$ec,$100) a leaf -- the character is value - $9f
            # The walk accumulates `a = a * 2 + bit` and indexes the tree by
            # that, which is the same thing as tree[node * 2 + bit].
            "leafShiftSubtrahend": 0x9F,
        },
        "notes": NOTES,
        # Everything below is ROM-POSITIONAL and stays empty until it is
        # actually derived. An empty table reads as "not done"; a copied one
        # reads as done and is wrong.
        "audio": {}, "battleAnimations": {}, "constants": {},
        "dexEntryLabels": {}, "dexOrder": [], "field": {}, "fontCharmap": {},
        "growthRates": {}, "hms": [], "iconOrder": [], "items": [],
        "layout": {}, "maps": {}, "moveEffects": [], "paletteOrder": [],
        "pokemonAssets": {}, "sfxKeys": {}, "sprites": {}, "text": {},
        "tileAnimations": [], "tilesets": {}, "tmhmMoves": [], "tms": [],
        "wildTables": [],
    }

    with open(args.out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {args.out} ({len(symbols)} symbols, {len(charmap)} charmap entries)")
    print(f"  romSha1 {sha1}")

    if args.sym_out:
        with open(args.sym, "rb") as src, open(args.sym_out, "wb") as dst:
            dst.write(src.read())
        print(f"wrote {args.sym_out} ({os.path.getsize(args.sym_out)} bytes)")


if __name__ == "__main__":
    main()
