#!/usr/bin/env python3
"""Candidates for the hand table of tools/gen4_battle_text_map.py.

    python tools/gen4_battle_text_map_cand.py <USA cache> <fuzzer --trace de log>

Lists the engine templates that matched a line the German fuzz still printed in
English, with the nearest bank-368 entries by wording."""
import difflib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen4_battle_text_map as M


def main():
    bank = M.load_bank(sys.argv[1])
    lines = open(sys.argv[2], encoding="utf8", errors="replace").read().split("\n")
    resid = {}
    i = 0
    while i < len(lines) - 1:
        a, b = lines[i].lstrip(), lines[i + 1].lstrip()
        if a.startswith("[msg]") and b.startswith("[txt]"):
            m, t = a[6:], b[6:]
            if m == t:
                flat = re.sub(r"\s*/\s*", " ", m).strip()
                resid[flat] = resid.get(flat, 0) + 1
            i += 2
        else:
            i += 1
    groups = {}
    for idx in sorted(bank):
        text, ids, sides = M.bank_key(bank[idx])
        if text and text not in groups:
            groups[text] = idx
    templ = {}
    for lit in M.engine_templates():
        flat = M.flat_engine(lit)
        if M.PH not in flat or flat in groups:
            continue
        parts = [re.escape(p) for p in flat.split(M.PH)]
        rx = re.compile("^" + "(.+?)".join(parts) + "$")
        n = sum(c for r, c in resid.items() if rx.match(r))
        if n:
            templ[flat] = n
    keys = sorted(templ, key=lambda k: -templ[k])
    texts = list(groups.items())
    for k in keys:
        probe = k.replace(M.PH, "\x01")
        best = sorted(texts, key=lambda t: -difflib.SequenceMatcher(None, probe, t[0]).ratio())[:2]
        print("%5d  %s" % (templ[k], k.replace(M.PH, "%s")))
        for t, idx in best:
            print("         -> %d %s" % (idx, t.replace(M.PH, "%s")))
    # lines no template reaches at all
    reached = 0
    print("--- residual lines with no source template ---")
    allr = list(templ)
    for r, c in sorted(resid.items(), key=lambda kv: -kv[1]):
        hit = False
        for k in allr:
            parts = [re.escape(p) for p in k.split(M.PH)]
            if re.match("^" + "(.+?)".join(parts) + "$", r):
                hit = True
                break
        if not hit and re.search(r"\b(the|is|was|of|to|its|and|a)\b", r):
            print("%5d  %s" % (c, r))


if __name__ == "__main__":
    main()
