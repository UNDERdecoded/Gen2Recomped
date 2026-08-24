"""Relaxed signatures that also wildcard `ld a,n` bank bytes, plus lockstep
read-back of BANK/address pairs.

Gen 2 reaches data in another bank as:
    ld a, BANK(Table)     ; 3E nn   <- the bank byte MOVES in a hack
    ld hl, Table          ; 21 nnnn <- so does the address
Keeping the 8-bit immediate solid (as the strict mask does) rejects precisely
the routines that reference relocated data.  Wildcarding it recovers the FULL
(bank, address) pair instead of just the address.
"""
import lr35902

def _bank_idiom(rom, pc, lookahead=3):
    """True when `ld a,n` at pc is followed within `lookahead` instrs by
    `ld hl,nn` -- i.e. it is a BANK() byte rather than an ordinary constant."""
    p = pc + 2
    for _ in range(lookahead):
        if p >= len(rom): return False
        op = rom[p]
        if op == 0x21: return True
        try: _, ln, _ = lr35902.decode(rom, p, 0)
        except Exception: return False
        p += ln
    return False


def masked_far(rom, off, base, ninstr):
    pat, slots = [], []          # slots: (pat_index, kind, value) kind in 'b8','a16'
    pc = off
    for _ in range(ninstr):
        if pc >= len(rom): break
        op = rom[pc]
        try: _, length, _ = lr35902.decode(rom, pc, base)
        except Exception: break
        wide16 = (op & 0xCF) == 0x01 or op in (0x08, 0xC3, 0xCD, 0xEA, 0xFA) \
                 or (op & 0xE7) == 0xC2 or (op & 0xE7) == 0xC4
        rel8 = op == 0x18 or (op & 0xE7) == 0x20
        pat.append(op)
        if wide16 and length == 3:
            slots.append((len(pat), 'a16', rom[pc+1] | (rom[pc+2] << 8)))
            pat += [None, None]
        elif op == 0x3E and length == 2 and _bank_idiom(rom, pc):
            # ld a,n ONLY where it is followed closely by `ld hl,nn` -- the
            # BANK()+address idiom.  Wildcarding every ld a,n instead destroys
            # the distinctiveness the match depends on (tried: 94 matches vs
            # 1279 strict).
            slots.append((len(pat), 'b8', rom[pc+1]))
            pat.append(None)
        elif rel8 and length == 2:
            pat.append(None)
        else:
            pat += list(rom[pc+1:pc+length])
        pc += length
    return pat, slots, pc - off

def pairs(slots):
    """(bank_slot, addr_slot) where a `ld a,n` precedes an `ld hl,nn` closely."""
    out = []
    for i, (idx, kind, val) in enumerate(slots):
        if kind != 'b8': continue
        for j in range(i + 1, min(i + 4, len(slots))):
            if slots[j][1] == 'a16':
                out.append((i, j)); break
    return out
