"""Masked code signatures: relocation-invariant fingerprints of GB routines."""
import lr35902

# 16-bit operands that carry an ADDRESS and therefore move between builds.
# Everything else -- opcodes, 8-bit immediates, and especially ldh [$ffXX]
# hardware registers -- is identical in a hack and is what makes a signature
# distinctive.
def masked(rom, off, base, ninstr):
    """(pattern, holes) where pattern has None for wildcard bytes.

    holes: list of (index_in_pattern, gold_value) for each masked 16-bit
    operand, so a match in the target ROM can be read back for its own value.
    """
    pat, holes = [], []
    pc = off
    for _ in range(ninstr):
        if pc >= len(rom): break
        op = rom[pc]
        try:
            text, length, _ = lr35902.decode(rom, pc, base)
        except Exception:
            break
        wide16 = (op & 0xCF) == 0x01 or op in (0x08, 0xC3, 0xCD, 0xEA, 0xFA) \
                 or (op & 0xE7) == 0xC2 or (op & 0xE7) == 0xC4
        rel8 = op == 0x18 or (op & 0xE7) == 0x20
        pat.append(op)
        if wide16 and length == 3:
            holes.append((len(pat), rom[pc+1] | (rom[pc+2] << 8)))
            pat += [None, None]
        elif rel8 and length == 2:
            pat.append(None)            # jr displacement shifts with layout
        else:
            pat += list(rom[pc+1:pc+length])
        pc += length
    return pat, holes, pc - off

def needle(pat):
    """Longest contiguous run of solid bytes, as (index, bytes)."""
    best_i = best = None
    i = 0
    while i < len(pat):
        if pat[i] is None:
            i += 1; continue
        j = i
        while j < len(pat) and pat[j] is not None: j += 1
        if best is None or (j - i) > len(best):
            best_i, best = i, bytes(pat[i:j])
        i = j
    return best_i, best

def find(hay, pat, lo=0, hi=None, limit=4, pre=None):
    """Every offset in hay matching pat (None = wildcard)."""
    hi = len(hay) if hi is None else hi
    n = len(pat)
    anchor = [(i, b) for i, b in enumerate(pat) if b is not None]
    if not anchor: return []
    ni, nb = pre if pre else needle(pat)
    if not nb: return []
    out = []
    start = lo
    while True:
        i = hay.find(nb, start, hi)
        if i < 0: break
        o = i - ni
        if o >= lo and o + n <= hi and all(hay[o+j] == b for j, b in anchor):
            out.append(o)
            if len(out) >= limit: break
        start = i + 1
    return out
