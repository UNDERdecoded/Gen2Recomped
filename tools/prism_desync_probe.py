#!/usr/bin/env python3
"""Find WHICH Prism script command is under-counted, by looking at what runs
immediately before each desync.

Prism's script extraction desyncs 1047 times against Crystal's baseline of 16,
which is why Prism is gated behind COMING SOON: NPC dialogue and map events
misbehave often enough that the game is not worth handing to a player.

The shape of the failure is already known and is the useful clue: **every
failing opcode is >= 232**, past the end of a 232-command table. A byte past the
end of the table is not a mis-decoded command -- it is not a command at all. So
the walker is not misreading commands, it is arriving at the wrong ADDRESS: some
earlier command consumed the wrong number of operand bytes and every byte after
it is off.

Which means the interesting question is not "what is opcode $F0" but "what ran
just before we started reading garbage". This walks every script reachable from
a `*Script` symbol, and when it falls off the table it reports the command
sequence that led there -- then ranks commands by how often they appear in that
position. A command that is under-counted will sit at the top of that ranking
far more often than chance.

    python3 tools/prism_desync_probe.py \\
        --rom pokeprism.gbc --sym tools/pokeprism.sym --ops tools/prism_ops.lua

The static walker cannot size VARIABLE-WIDTH commands by construction, so those
are the prior suspects: anything whose operand count depends on a byte it just
read. Confirming which ones actually cost desyncs is the point of running this
rather than guessing from the list.
"""

from __future__ import annotations

import argparse
import collections
import re

# The one-letter operand widths src/import/Gen2ScriptOps.lua uses.
ARG_BYTES = {"b": 1, "w": 2, "p": 2, "t": 2, "d": 2, "M": 2,
             "f": 3, "T": 3, "D": 3, "m": 3}

ROW = re.compile(r'\{\s*"([^"]*)"\s*,\s*"([^"]*)"\s*\}')
SYM = re.compile(r"^([0-9A-Fa-f]{2,4}):([0-9A-Fa-f]{4})\s+(\S+)\s*$")


def load_ops(path, table="COMMANDS_PRISM"):
    src = open(path, encoding="utf-8").read()
    m = re.search(r"Gen2ScriptOps\.%s = \{(.*?)\n\}" % table, src, re.S)
    if not m:
        raise SystemExit(f"{path}: no {table}")
    return [(n, a) for n, a in ROW.findall(m.group(1))]


def load_syms(path):
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = SYM.match(line.strip())
        if m:
            out[m.group(3)] = (int(m.group(1), 16), int(m.group(2), 16))
    return out


def offset(bank, addr):
    """(bank, addr) -> file offset. Bank 0 is flat; the rest are windowed at
    $4000, which is the one arithmetic slip that would make every result
    nonsense rather than merely wrong."""
    if addr < 0x4000:
        return addr
    return bank * 0x4000 + (addr - 0x4000)


# Prism's `sif` family guards exactly ONE following command; `sif ... then`
# opens a block that runs to `sendif`. See Gen2ScriptOps.SIF_COMMANDS_PRISM.
SIF = {"siftrue", "siffalse", "sifeq", "sifne", "sifgt", "siflt"}


def walk(rom, ops, start_bank, start_addr, terminators, limit=4000):
    """Walk one script. Returns (trail, outcome).

    `scriptstartasm` IS Prism's `then` marker (the macro says so outright:
    `then_command EQU scriptstartasm_command`), so ONE opcode means two things
    depending on what precedes it. After a `sif` it opens a block; ANYWHERE ELSE
    the bytes that follow are Z80 MACHINE CODE and walking into them produces
    exactly the ">= 232" garbage this probe is chasing.

    RomExtractorGen2:gen2DecodeScript already stops there. This has to as well,
    or the probe manufactures its own desyncs and then blames whatever command
    happened to precede them -- which it did, putting scriptstartasm at the top
    of the ranking on the first run.
    """
    pc = offset(start_bank, start_addr)
    bank = start_bank
    trail = []
    was_sif = False
    for _ in range(limit):
        if not (0 <= pc < len(rom)):
            return trail, "outofrange"
        op = rom[pc]
        if op >= len(ops):
            return trail, "desync"
        name, args = ops[op]
        if name == "scriptstartasm" and not was_sif:
            trail.append(name)
            return trail, "asm"
        was_sif = name in SIF
        pc += 1
        for k in args:
            width = ARG_BYTES.get(k)
            if width is None:
                return trail, "badkind"
            pc += width
        trail.append(name)
        if name in terminators:
            return trail, "end"
    return trail, "runaway"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", required=True)
    ap.add_argument("--sym", required=True)
    ap.add_argument("--ops", required=True)
    ap.add_argument("--table", default="COMMANDS_PRISM")
    ap.add_argument("--terminators", default="TERMINATORS_PRISM")
    ap.add_argument("--top", type=int, default=20)
    args = ap.parse_args()

    rom = open(args.rom, "rb").read()
    ops = load_ops(args.ops, args.table)
    syms = load_syms(args.sym)

    src = open(args.ops, encoding="utf-8").read()
    m = re.search(r"Gen2ScriptOps\.%s = \{(.*?)\n\}" % args.terminators, src, re.S)
    terminators = set(re.findall(r'\["([^"]+)"\]|\b(\w+) = true',
                                 m.group(1))) if m else set()
    terminators = {a or b for a, b in terminators} if terminators else set()
    if not terminators:
        # The Lua table may use bare keys; fall back to the names that end a
        # script in every Gen 2 dialect, so the walk still stops somewhere.
        terminators = {"sjump", "farsjump", "memjump", "jumpstd", "jumptext",
                       "jumptextfaceplayer", "farjumptext", "end", "endall",
                       "endcallback", "reloadend", "stopandsjump"}

    entries = sorted((n, v) for n, v in syms.items() if n.endswith("Script"))
    print(f"table: {len(ops)} commands, {len(terminators)} terminators")
    print(f"walking {len(entries)} *Script entry points\n")

    outcomes = collections.Counter()
    # what ran immediately before we fell off the table
    before = collections.Counter()
    before2 = collections.Counter()
    examples = {}
    for name, (bank, addr) in entries:
        trail, outcome = walk(rom, ops, bank, addr, terminators)
        outcomes[outcome] += 1
        # An "unused" opcode decoding inside a real script means the walk was
        # ALREADY lost before it fell off the table, so its predecessor is
        # noise, not evidence. Counting those was what put paragraphdelay and
        # varblocks in the ranking.
        if any(t.startswith("unused") for t in trail):
            outcomes["desync(already-lost)"] += 1
            outcomes[outcome] -= 1
            continue
        if outcome == "desync" and trail:
            before[trail[-1]] += 1
            if len(trail) >= 2:
                before2[" -> ".join(trail[-2:])] += 1
            examples.setdefault(trail[-1], (name, trail[-6:]))

    total = sum(outcomes.values())
    print("outcomes:")
    for k, v in outcomes.most_common():
        print("  %-11s %5d  (%.1f%%)" % (k, v, 100.0 * v / total))

    print(f"\nCOMMAND IMMEDIATELY BEFORE THE DESYNC (top {args.top}) --")
    print("a command that under-counts its operands lands here far more often")
    print("than its share of the corpus:\n")
    for name, n in before.most_common(args.top):
        where, trail = examples.get(name, ("?", []))
        print("  %-26s %4d   e.g. %s" % (name, n, where))
        if trail:
            print("      ..." + " -> ".join(trail))

    print(f"\nLAST TWO COMMANDS (top {args.top}):\n")
    for pair, n in before2.most_common(args.top):
        print("  %-52s %4d" % (pair, n))


if __name__ == "__main__":
    main()
