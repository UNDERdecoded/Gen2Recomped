"""Extract wEventFlags' bit-index -> EVENT_* name table.

Source: pokered/constants/event_constants.asm -- an RGBDS const block using
`const_def` / `const NAME` / `const_skip N` / `const_next N` (jump the
counter to an absolute bit position; N is usually `$hex` but occasionally
a small arithmetic expression like `$F0 - 2`). This is NOT the same shape
tools/extract/util.py's parse_const_block handles (that one only knows
const_def/const/const_skip), so this file gets its own small tracker
rather than stretching a shared helper to fit one caller.

wEventFlags (ram/wram.asm) is a flat NUM_EVENTS-bit array; each EVENT_*
constant IS its bit index. NUM_EVENTS is set by the file's own trailing
`const_next $A00` (2560 bits = 320 bytes), matched by `flag_array
NUM_EVENTS` at the wEventFlags declaration.

Output: src/save_convert/data/event_flags.lua (committed; independent of ROM
import, like data/palettes_gbc.lua)
  byName[EVENT_NAME] = bit index (int)
  byBit[bit index] = EVENT_NAME
  count = total bit width of wEventFlags (NUM_EVENTS)
"""

import argparse
import os
import re
import sys

from . import util


def _eval_next(expr):
    """`$XX` or `$XX - N` / `$XX + N` -> int."""
    m = re.match(r"^(\S+)\s*([+-])\s*(\S+)$", expr)
    if m:
        base = util.parse_number(m.group(1))
        n = util.parse_number(m.group(3))
        return base + n if m.group(2) == "+" else base - n
    return util.parse_number(expr)


def extract(pokered, out_path):
    path = os.path.join(pokered, "constants/event_constants.asm")
    by_name = {}
    by_bit = {}
    value = None
    count = None
    for lineno, line in util.read_asm(path):
        s = line.strip()
        if not s:
            continue
        m = re.match(r"const_def(?:\s+(\S+))?$", s)
        if m:
            value = util.parse_number(m.group(1)) if m.group(1) else 0
            continue
        m = re.match(r"const\s+(\w+)", s)
        if m:
            if value is None:
                util.die(f"{path}:{lineno}: const before const_def")
            name = m.group(1)
            if name in by_name:
                util.die(f"{path}:{lineno}: duplicate flag {name}")
            by_name[name] = value
            by_bit[value] = name
            value += 1
            continue
        m = re.match(r"const_skip(?:\s+(\S+))?$", s)
        if m:
            if value is None:
                util.die(f"{path}:{lineno}: const_skip before const_def")
            value += util.parse_number(m.group(1)) if m.group(1) else 1
            continue
        m = re.match(r"const_next\s+(.+)$", s)
        if m:
            value = _eval_next(m.group(1).strip())
            continue
        m = re.match(r"DEF\s+NUM_EVENTS\s+EQU\s+const_value\s*$", s)
        if m:
            if value is None:
                util.die(f"{path}:{lineno}: NUM_EVENTS before any const_def")
            count = value
            continue

    if count is None:
        util.die(f"{path}: NUM_EVENTS EQU const_value not found")
    if count % 8 != 0:
        util.die(f"{path}: NUM_EVENTS={count} is not byte-aligned")
    if not by_name:
        util.die(f"{path}: parsed 0 EVENT_* flags")

    util.write_lua(
        out_path,
        {"source": "pokered constants/event_constants.asm",
         "count": count,
         "byName": by_name,
         "byBit": by_bit},
        header="wEventFlags bit index <-> EVENT_* name (see ram/wram.asm\n"
               "wEventFlags, a flat NUM_EVENTS-bit / (NUM_EVENTS/8)-byte\n"
               "array). byBit only has entries for bits with a name --\n"
               "reserved/padding bits are intentionally absent.")
    return by_name, by_bit, count


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--pokered", required=True)
    parser.add_argument("--out", default="src/save_convert/data/event_flags.lua")
    args = parser.parse_args(argv)
    extract(args.pokered, args.out)
    return 0


if __name__ == "__main__":
    if __package__ is None:
        sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
        __package__ = "extract"
        from extract import util as util  # noqa: F811
    raise SystemExit(main())
