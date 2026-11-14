#!/usr/bin/env python3
"""Align the engine's English battle templates with Platinum's battle bank.

    python tools/gen4_battle_text_map.py <USA platinum cache> [--report]

Writes src/battle/Gen4BattleTextMap.lua: for every template the engine writes
(a Lua string literal under src/) whose wording is also a line of text bank 368
on the USA cartridge, the bank entry numbers (one per wild / foe / ally variant)
and which placeholder (type, slot) each %s of the template stands for.  The file
holds the engine's own English and entry NUMBERS only -- no cartridge text.  At
run time src/battle/Gen4BattleText.lua prints the same entry of a non-English
cache with the nicknames, moves, items ... filled in.

  --report   also print the templates that found no entry (the manual list in
             Gen4BattleText.lua covers the rest)
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BANK = 368


def load_bank(cache):
    path = os.path.join(cache, "data", "generated", "text.lua")
    out = {}
    pat = re.compile(r'^__t\["TEXT_B%04d_(\d+)"\] = "((?:[^"\\]|\\.)*)"$' % BANK, re.M)
    with open(path, encoding="utf8", errors="replace") as f:
        for m in pat.finditer(f.read()):
            s = m.group(2)
            s = re.sub(r"\\(\d{1,3})", lambda x: chr(int(x.group(1))), s)
            s = s.replace("\\n", "\n").replace('\\"', '"').replace("\\\\", "\\")
            out[int(m.group(1))] = s
    return out


PH = "\x01"


def norm_text(s):
    s = s.replace("\u2019", "'").replace("\u2018", "'").replace("\u201c", '"').replace("\u201d", '"')
    s = re.sub(r"\s+", " ", s).strip()
    return s


def bank_key(raw):
    """-> (normalised text with PH for each placeholder, [placeholder ids],
    [side letters of the type-1 placeholders]) """
    s = raw
    s = re.sub(r"\{WAIT \d+\}|\{YESNO \d+\}|\{COLOR \d+\}", "", s)
    s = s.replace("\x0b", " ").replace("\x0c", " ")
    s = s.replace("\u2019", "'")
    # a trainer class + name pair is one composite placeholder
    s = re.sub(r"\{STRVAR_1 14 (\d+) 0\} \{STRVAR_1 3 (\d+) 0\}", lambda m: "\x02%s.%s\x03" % (m.group(1), m.group(2)), s)
    ids, sides = [], []

    def ph(m):
        return m.group(0)

    # side prefixes in front of a pokemon placeholder
    def side_sub(m):
        pre = m.group(1) or ""
        sides.append("w" if pre.lower().startswith("the wild") else "f" if pre.lower().startswith("the foe") else "a")
        return "\x04"
    # replace "[the wild |the foe's ]{STRVAR_1 1 s 0}" -> \x04 (side noted in order of appearance)
    # keep appearance order across all placeholders: walk once
    out, pos = [], 0
    tok = re.compile(r"(?i:(the wild |the foe's )?)\{STRVAR_1 (\d+) (\d+) 0\}|\x02(\d+)\.(\d+)\x03")
    for m in tok.finditer(s):
        out.append(s[pos:m.start()])
        pos = m.end()
        if m.group(4) is not None:
            ids.append("14.%s+3.%s" % (m.group(4), m.group(5)))
            out.append(PH)
            continue
        t, sl = m.group(2), m.group(3)
        ids.append("%s.%s" % (t, sl))
        if t == "1":
            pre = (m.group(1) or "").lower()
            sides.append("w" if pre.startswith("the wild") else "f" if pre.startswith("the foe") else "a")
        out.append(PH)
    out.append(s[pos:])
    s = "".join(out)
    s = re.sub(r"\{[^}]*\}", "", s)
    return norm_text(s), ids, "".join(sides)


# ---------------------------------------------------------------------------
# THE HAND TABLE: lines the engine prints whose wording differs from the
# cartridge's English (the engine's are Red/Blue and Black/White phrasings) but
# which have a cartridge equivalent.  Each row: the line as it is PRINTED
# (newlines flattened to spaces, a %s for each name / number the engine fills
# in), the bank-368 entry (the ally variant, or the only one), and
#   args    what each %s is, in the engine's order: a "type.slot" placeholder
#           of the entry, "side" (only says which variant to use) or "-"
#           (dropped)
#   fixed   placeholders the engine prints as its own constant: "move:<id>"
#           (the cache's name of that move), "ability:<LABEL>"
#   entries explicit { sides = entry } where the bank does not group the
#           variants itself (team lines: your side = "a", the foe's = "f")
#   part    1 / 2: only that page of a two-page entry
#   raw     match with the engine's own line breaks kept (\n in the template)
# ---------------------------------------------------------------------------
HAND = []


def H(tmpl, entry, args=None, fixed=None, entries=None, part=None, raw=False):
    HAND.append(dict(tmpl=tmpl, entry=entry, args=args, fixed=fixed, entries=entries, part=part, raw=raw))


# the trainer's win / loss, the money
H("%s defeated %s!", 785, ["-", "3.0"])
H("%s got $%s for winning!", 33, ["3.0", "54.1"])
H("The trainer blocked the %s!", 859, ["-"])
H("%s used\n%s!", 857, ["3.0", "8.1"], raw=True)
H("%s with- drew %s!", 990, ["3.0", "1.1"])
H("%s is about to use %s!", 835, ["14.0+3.1", "1.2"], part=1)
H("Will %s change %s?", 835, ["-", "-"], part=2)
H("Use next %s?", 11, ["-"])
H("Do it! %s!", 981)
H("Get'm! %s!", 979)
H("The enemy's weak! Get'm! %s!", 982)
H("%s, come back!", 985)
H("%s went back!", 985)
# failing, nothing happening
H("But, it failed!", 796)
H("Nothing happened!", 795)
H("No effect!", 607)
H("No %s left for this move!", 823, ["-"])
H("Hit %s times!", 46, ["50.0"])
H("Hit the enemy %s times!", 46, ["50.0"])
H("It doesn't affect %s!", 27)
H("You missed the %s!", 862, ["-"])
H("Darn! The %s broke free!", 863, ["-"])
H("Shoot! It was so close too!", 866)
H("Aww! It appeared to be caught!", 864)
H("All right! %s was caught!", 867)
H("New %s data will be added for %s!", 871, ["-", "1.0"])
# status
H("%s's hurt by poison!", 73)
H("%s's hurt by the burn!", 95)
H("%s's fully paralyzed!", 130)
H("%s's paralyzed! It may not attack!", 120)
H("%s's badly poisoned!", 79)
H("%s is fast asleep!", 299)
H("%s was defrosted!", 114)
H("%s's hit with recoil!", 279)
H("%s is hit with recoil!", 279)
H("Sucked health from %s!", 82)
H("%s's getting pumped!", 276)
H("%s's RAGE is building!", 363)
H("%s's HP is full!", 187, ["1.0"])
H("%s was subjected to TORMENT!", 494)
H("%s's disabled no more!", 369)
H("%s got an ENCORE!", 372)
H("%s's ENCORE ended!", 375)
H("%s restored health!", 184)
H("%s ran from battle!", 469)
H("%s can't run away!", 43)
H("%s restored health using its %s!", 899)
H("%s's status returned to normal using its %s!", 896)
H("%s boosted the accuracy of its next move using %s!", 1157)
H("%s used its %s to get pumped!", 597)
H("%s was badly poisoned by its %s!", 1168)
H("%s was burned by its %s!", 1171)
H("%s took %s with it!", 391)
H("%s can't use the same move twice in a row due to the TORMENT!", 612)
H("%s cut its HP and maximized ATTACK!", 449, ["1.0"])
H("%s switched items with its opponent!", 510)
H("%s's STURDY made the move fail!", 734, ["1.0"], fixed={"5.1": "ability:STURDY"})
H("%s can't get it going!", 1112, ["1.0"], fixed={"5.1": "ability:SLOW START"})
H("%s shuddered!", 1106, ["1.1"], fixed={"5.0": "ability:ANTICIPATION"})
H("%s acquired %s!", 1021, ["1.0", "5.1"])
H("%s TRACED %s's %s!", 679, ["1.0", "1.1", "5.2"])
H("%s SKETCHED %s!", 385)
H("LEECH SEED saps %s!", 296)
H("%s shrouded itself with MAGIC COAT!", 571)
H("%s's %s was bounced back by MAGIC COAT!", 574)
H("%s is protected by MIST!", 273)
H("%s STOCKPILED %s!", 317, ["1.0", "50.1"])
H("%s's PERISH count fell to %s!", 439, ["1.0", "50.1"])
H("The SUBSTITUTE took damage for %s!", 354)
H("%s was transferred to someone's PC!", 869, ["1.0"])
H("%s was transferred to Bebe's PC!", 870, ["1.0"])
H("All %s changes are eliminated!", 817, ["-"])
# weather
H("%s is pelted by HAIL!", 285, ["1.1"], fixed={"6.0": "move:258"})
H("%s is pelted by SANDSTORM!", 285, ["1.1"], fixed={"6.0": "move:201"})
H("The SANDSTORM hits %s!", 285, ["1.1"], fixed={"6.0": "move:201"})
H("The HAIL hits %s!", 285, ["1.1"], fixed={"6.0": "move:258"})
H("AQUA RING restored %s's HP!", 1030, ["1.0"], fixed={"6.1": "move:392"})
H("INGRAIN restored %s's HP!", 1030, ["1.0"], fixed={"6.1": "move:275"})
H("A SANDSTORM brewed!", 804)
H("The SANDSTORM rages.", 805)
H("The SANDSTORM subsided.", 806)
H("The sunlight got bright!", 807)
# the two sides' screens and hazards
H("REFLECT raised your team's DEFENSE!", 194, [], fixed={"6.0": "move:115"})
H("REFLECT raised the foe's team's DEFENSE!", 195, [], fixed={"6.0": "move:115"})
H("LIGHT SCREEN raised your team's SP. DEF!", 190, [], fixed={"6.0": "move:113"})
H("LIGHT SCREEN raised the foe's team's SP. DEF!", 191, [], fixed={"6.0": "move:113"})
H("Your team's %s wore off!", 288, ["6.0"])
H("The foe's team's %s wore off!", 289, ["6.0"])
H("%s's taunt wore off!", 1060, ["1.0"], fixed={"6.1": "move:269"})
H("%s's party is covered by a veil!", 198, ["side"], entries={"a": 198, "f": 199})
H("%s's party is no longer protected!", 203, ["side"], entries={"a": 203, "f": 204})
H("%s's shrouded in mist!", 271, ["side"], entries={"a": 271, "f": 272})
H("%s's tailwind petered out!", 1232, ["side"], entries={"a": 1232, "f": 1233})
H("Your team's tailwind petered out!", 1232)
H("The foe's team's tailwind petered out!", 1233)
H("The tailwind blew from behind your team!", 1230)
H("The tailwind blew from behind the foe's team!", 1231)
H("Poison spikes were scattered all around your team's feet!", 1063)
H("Poison spikes were scattered all around the foe's team's feet!", 1064)
H("SPIKES were scattered all around the foe's side!", 428)
H("SPIKES were scattered all around your side!", 427)
H("Pointed stones float in the air around your team!", 1077)
H("Pointed stones float in the air around the foe's team!", 1078)
H("The Lucky Chant shielded your team from critical hits!", 1241)
H("The Lucky Chant shielded the foe's team from critical hits!", 1242)
H("The foe's team's Lucky Chant wore off!", 1086)
H("Your team's Lucky Chant wore off!", 1085)
H("%s's SUBSTITUTE broke!", 357, ["1.0"])
H("%s has a SUBSTITUTE!", 351, ["1.0"])
H("%s's QUICK CLAW activated!", 1254, ["1.0"], fixed={"8.1": "item:217"})
H("All %s that hear the song will faint in three turns!", 822, ["-"])
H("The wall shattered!", 606)
H("%s's FIRE moves were powered up!", 656, ["1.0"], fixed={"5.1": "ability:BLAZE"})
H("%s weakened ELECTRIC's power!", 587, ["-"])
H("%s weakened FIRE's power!", 588, ["-"])


def lua_literals(text):
    """Every quoted string literal of a Lua source, comments skipped."""
    i, n = 0, len(text)
    lits = []
    while i < n:
        c = text[i]
        if c == "-" and text.startswith("--", i):
            if text.startswith("--[[", i) or text.startswith("--[=", i):
                m = re.compile(r"--\[(=*)\[").match(text, i)
                if m:
                    end = text.find("]" + m.group(1) + "]", m.end())
                    i = n if end < 0 else end + len(m.group(1)) + 2
                    continue
            nl = text.find("\n", i)
            i = n if nl < 0 else nl
            continue
        if c == "[" and re.compile(r"\[=*\[").match(text, i):
            m = re.compile(r"\[(=*)\[").match(text, i)
            end = text.find("]" + m.group(1) + "]", m.end())
            i = n if end < 0 else end + len(m.group(1)) + 2
            continue
        if c in "\"'":
            q, j, buf = c, i + 1, []
            while j < n and text[j] != q:
                if text[j] == "\\" and j + 1 < n:
                    e = text[j + 1]
                    if e == "n":
                        buf.append("\n"); j += 2
                    elif e == "t":
                        buf.append("\t"); j += 2
                    elif e.isdigit():
                        m = re.compile(r"\d{1,3}").match(text, j + 1)
                        buf.append(chr(int(m.group(0)))); j = m.end()
                    elif e == "x":
                        buf.append(chr(int(text[j + 2:j + 4], 16))); j += 4
                    elif e == "z":
                        j += 2
                        while j < n and text[j] in " \t\r\n":
                            j += 1
                    else:
                        buf.append(e); j += 2
                elif text[j] == "\n":
                    break
                else:
                    buf.append(text[j]); j += 1
            lits.append("".join(buf))
            i = j + 1
            continue
        i += 1
    return lits


def engine_templates():
    seen = {}
    for base, _, files in os.walk(os.path.join(ROOT, "src")):
        if os.sep + "translation" in base:
            continue
        for fn in files:
            if not fn.endswith(".lua") or fn in ("Gen4BattleTextMap.lua",):
                continue
            with open(os.path.join(base, fn), encoding="utf8", errors="replace") as f:
                for lit in lua_literals(f.read()):
                    if len(lit) < 4 or not re.search(r"[A-Za-z]{2}", lit):
                        continue
                    seen[lit] = True
    return list(seen)


def flat_engine(lit):
    s = lit.replace("%%", "\x05")
    s = re.sub(r"%(?:\d+\$)?[sd]", PH, s)
    s = s.replace("\x05", "%")
    s = s.replace("\x0b", " ")
    return norm_text(s)


def main():
    cache = sys.argv[1]
    report = "--report" in sys.argv
    bank = load_bank(cache)
    groups = {}   # (text, ids) -> {"ids": [...], "entries": {sides: id}}
    by_text = {}  # text -> the first group with that text
    for idx in sorted(bank):
        text, ids, sides = bank_key(bank[idx])
        if not text:
            continue
        g = groups.setdefault((text, tuple(ids)), {"ids": ids, "entries": {}})
        g["entries"].setdefault(sides, idx)
        by_text.setdefault(text, g)
    rows, missed = [], []
    done = set()
    for lit in engine_templates():
        flat = flat_engine(lit)
        if flat in done:
            continue
        g = by_text.get(flat)
        nph = flat.count(PH)
        if g is None or len(g["ids"]) != nph:
            if report and ("\n" in lit or "!" in lit or "%s" in lit) and nph <= 4:
                missed.append(lit)
            continue
        done.add(flat)
        rows.append((flat, g))
    rows_hand = []
    for h in HAND:
        text, ids, sides = bank_key(bank[h["entry"]])
        g = groups.get((text, tuple(ids)), {"ids": ids, "entries": {sides: h["entry"]}})
        entries = h["entries"] or g["entries"]
        args = h["args"]
        nph = h["tmpl"].count("%s")
        if args is None:
            args = list(g["ids"])
        if len(args) != nph:
            print("HAND row has %d args for %d %%s: %s" % (len(args), nph, h["tmpl"]))
            continue
        if h["entries"] is None and args != list(g["ids"]):
            # reorder the side letters from the bank's pokemon order to the engine's
            bank_t1 = [i for i in g["ids"] if i.startswith("1.")]
            eng_t1 = [i for i in args if i.startswith("1.")]
            if len(bank_t1) > 1 and sorted(bank_t1) == sorted(eng_t1) and bank_t1 != eng_t1:
                perm = [bank_t1.index(i) for i in eng_t1]
                entries = {"".join(k[p] for p in perm): v for k, v in entries.items() if len(k) == len(perm)}
            elif len(bank_t1) > len(eng_t1):
                # an unused pokemon slot: keep the sides of the ones the engine names
                keep = [bank_t1.index(i) for i in eng_t1]
                entries = {"".join(k[p] for p in keep): v for k, v in entries.items() if len(k) == len(bank_t1)}
        rows_hand.append((h, args, entries))
    rows.sort(key=lambda r: (-len(r[0].replace(PH, "")), r[0]))
    out = [
        "-- GENERATED by tools/gen4_battle_text_map.py -- do not edit by hand.",
        "--",
        "-- The engine's English battle templates that are also lines of Platinum's",
        "-- battle text bank (368), with the entry number of each wild / foe / ally",
        "-- variant and the (type.slot) placeholder each %s stands for.  Entry numbers",
        "-- only; the cartridge's own text is read from the cache at run time.",
        "--   { template, { arg ids }, { [\"sides\"] = entry } }",
        "-- sides: one letter per pokemon placeholder, a ally / w wild / f foe.",
        "return {",
    ]
    for flat, g in rows:
        tmpl = flat.replace(PH, "%s").replace("\\", "\\\\").replace('"', '\\"')
        ids = ", ".join('"%s"' % i for i in g["ids"])
        ents = ", ".join('[%s] = %d' % ('"%s"' % k, v) for k, v in sorted(g["entries"].items()))
        out.append('  { "%s", { %s }, { %s } },' % (tmpl.replace("%", "%%") if False else tmpl, ids, ents))
    out.append("}")
    # the hand rows go first, their own lines being the more specific
    hand_out = []
    rows_hand.sort(key=lambda r: -len(r[0]["tmpl"].replace("%s", "")))
    for h, args, entries in rows_hand:
        tmpl = h["tmpl"].replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
        ids = ", ".join('"%s"' % i for i in args)
        ents = ", ".join('[%s] = %d' % ('"%s"' % k, v) for k, v in sorted(entries.items()))
        extra = []
        if h["fixed"]:
            extra.append("fixed = { %s }" % ", ".join('["%s"] = "%s"' % kv for kv in sorted(h["fixed"].items())))
        if h["part"]:
            extra.append("part = %d" % h["part"])
        if h["raw"]:
            extra.append("raw = true")
        hand_out.append('  { "%s", { %s }, { %s }, { %s } },' % (tmpl, ids, ents, ", ".join(extra)))
    at = out.index("return {") + 1
    out[at:at] = hand_out
    dest = os.path.join(ROOT, "src", "battle", "Gen4BattleTextMap.lua")
    with open(dest, "w", encoding="utf8", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("%d templates aligned -> %s" % (len(rows), dest))
    if report:
        for m in missed:
            print("UNMATCHED:", repr(m))


if __name__ == "__main__":
    main()
