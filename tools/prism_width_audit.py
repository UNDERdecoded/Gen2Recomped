#!/usr/bin/env python3
"""Audit Prism's script-command operand widths against the CARTRIDGE.

tools/derive_args.py derives these from Prism's .asm source, which is the right
primary method -- but the source is a separate download, and a scoring bug there
is invisible from inside the result. This is the independent check: it reads the
same answer out of the ROM players actually run, by disassembling each handler
and counting its calls to the stream-reading primitives BY ADDRESS.

That matters because the failure being chased is an UNDER-COUNT.
tools/prism_desync_probe.py found 73 of 236 commands recorded as taking no
operands, 25 of them named as if they read one, and two of those sitting
immediately before a desync. A handler that calls GetScriptByte but was scored 0
consumes one byte fewer than the ROM does, and every byte after it is off --
which is exactly the ">= 232 opcode" garbage the probe sees.

    python3 tools/prism_width_audit.py --rom pokeprism.gbc \\
        --sym tools/pokeprism.sym --ops tools/prism_ops.lua

Reports, per command, the width the table claims versus the width the handler's
own calls imply, and lists the disagreements. It does NOT rewrite the table:
confirm a disagreement by reading the handler before changing anything, because
a WRONG width is worse than a missing one -- it decodes to plausible garbage
instead of failing loudly.
"""

from __future__ import annotations

import argparse
import re
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lr35902  # noqa: E402

ARG_BYTES = {"b": 1, "w": 2, "p": 2, "t": 2, "d": 2, "M": 2,
             "f": 3, "T": 3, "D": 3, "m": 3}

# Same primitives derive_args.py scores, by NAME here and resolved to addresses
# below. GetScriptPerson and GetHalfwordVar really are 0 -- they read a register
# or a RAM variable, not the stream -- and that is the correct call that makes
# the zero-width set plausible enough to hide a real bug inside it.
READS = {
    "GetScriptByte": 1, "GetScriptByteOrVar": 1, "GetScriptByteOrVar_FF": 1,
    "GetScriptHalfword": 2, "GetScriptHalfword_de": 2,
    "GetScriptHalfwordOrVar": 2, "GetScriptHalfwordOrVar_HL": 2,
    "GetScriptThreeBytes": 3,
    "GetScriptPerson": 0, "GetHalfwordVar": 0,
    "SkipTwoScriptBytes": 2,
}

SYM = re.compile(r"^([0-9A-Fa-f]{2,4}):([0-9A-Fa-f]{4})\s+(\S+)\s*$")
ROW = re.compile(r'\{\s*"([^"]*)"\s*,\s*"([^"]*)"\s*\}')


def offset(bank, addr):
    return addr if addr < 0x4000 else bank * 0x4000 + (addr - 0x4000)


def load_syms(path):
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = SYM.match(line.strip())
        if m:
            out[m.group(3)] = (int(m.group(1), 16), int(m.group(2), 16))
    return out


def load_ops(path, table):
    src = open(path, encoding="utf-8").read()
    m = re.search(r"Gen2ScriptOps\.%s = \{(.*?)\n\}" % table, src, re.S)
    if not m:
        raise SystemExit(f"{path}: no {table}")
    return ROW.findall(m.group(1))


def handler_width(rom, start_off, bank, read_addrs, limit=160):
    """Sum the stream bytes one handler takes, following the fall-through path
    and counting `call`s to the primitives.

    STOPS AT THE FIRST CONDITIONAL BRANCH, which is what makes the number
    meaningful. A walk that runs past `jr cc, X` counts BOTH arms and inflates
    wildly -- the first version of this reported setevent as reading four
    2-byte event ids because it summed four mutually exclusive paths. A
    straight-line PREFIX is a true lower bound; a greedy walk is nothing.

    Deliberately NOT a full control-flow walk -- derive_args.py already does
    that against the source. This is the corroborating floor: if the prefix
    alone already reads more than the table claims, the table is wrong no
    matter what the branches do.
    """
    pc = start_off
    total = 0
    seen = []
    for _ in range(limit):
        if not (0 <= pc < len(rom)):
            break
        try:
            text, length, word = lr35902.decode(rom, pc, 0)
        except Exception:
            break
        if text.startswith("call") and word is not None:
            hit = read_addrs.get((bank, word)) or read_addrs.get((0, word))
            if hit is not None:
                total += READS[hit]
                seen.append(hit)
        # PRISM'S HANDLERS USE RST VECTORS WITH INLINE ARGUMENTS. `rst $20`
        # (and $08, $10) is followed by operand BYTES, not instructions, so a
        # linear disassembly is invalid from there on -- it decodes the operands
        # as code and, if they happen to look like `call GetScriptHalfwordOrVar`,
        # invents stream reads that do not exist. That is exactly what made the
        # first run report setevent as reading three event ids: one real read,
        # then two hallucinated out of rst operands. Stop at the first rst.
        if text.startswith("rst"):
            break
        # Any branch at all ends the prefix -- conditional ones because the
        # other arm is unknown, unconditional ones because we would have to
        # follow them to stay honest.
        if text.startswith(("ret", "jp", "jr", "call")) and "," in text:
            break
        if text.startswith(("ret", "jp", "jr")):
            break
        pc += length
    return total, seen


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", required=True)
    ap.add_argument("--sym", required=True)
    ap.add_argument("--ops", required=True)
    ap.add_argument("--table", default="COMMANDS_PRISM")
    ap.add_argument("--command-table", default="ScriptCommandTable")
    args = ap.parse_args()

    rom = open(args.rom, "rb").read()
    syms = load_syms(args.sym)
    ops = load_ops(args.ops, args.table)

    if args.command_table not in syms:
        raise SystemExit(f"{args.command_table} is not in the symbol table")
    tbank, taddr = syms[args.command_table]
    base = offset(tbank, taddr)

    read_addrs = {}
    for name in READS:
        if name in syms:
            b, a = syms[name]
            read_addrs[(b, a)] = name
            if a < 0x4000:
                read_addrs[(0, a)] = name
    print(f"resolved {len(set(read_addrs.values()))} of {len(READS)} primitives")
    print(f"{args.command_table} at {tbank:02x}:{taddr:04x}\n")

    disagree, checked = [], 0
    for op, (name, argstr) in enumerate(ops):
        claimed = sum(ARG_BYTES.get(k, 0) for k in argstr)
        ptr = base + op * 2
        if ptr + 1 >= len(rom):
            break
        target = rom[ptr] | (rom[ptr + 1] << 8)
        if target < 0x4000:          # a home-bank handler
            hbank, hoff = 0, target
        else:
            hbank, hoff = tbank, offset(tbank, target)
        found, seen = handler_width(rom, hoff, hbank, read_addrs)
        checked += 1
        if found > claimed:
            disagree.append((op, name, claimed, found, seen))

    print(f"checked {checked} handlers\n")
    print("COMMANDS WHOSE HANDLER READS MORE THAN THE TABLE CLAIMS")
    print("(straight-line PREFIX only -- stops at the first branch, so each")
    print(" number is a floor the table already fails to meet)\n")
    if not disagree:
        print("  none -- the table's widths are at least as large as the")
        print("  straight-line reads, so an under-count is not visible here.")
    for op, name, claimed, found, seen in disagree:
        print("  $%02X %-26s claims %d, reads >= %d   [%s]"
              % (op, name, claimed, found, ", ".join(seen)))


if __name__ == "__main__":
    main()
