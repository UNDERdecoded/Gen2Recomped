"""Gen2 (pokegold/pokesilver) script bytecode tables and validation harness.

`CMDS` is the ScriptCommandTable at 25:6BE4 -- 162 commands, $00-$A1, names
straight out of the ROM symbol table.  The argument specs were derived by
counting `GetScriptByte` calls in each handler and then validated by
disassembling every script reachable from every map's scenes, callbacks and
object/bg/coord events.

Run with no arguments to validate; run with `tune` to sweep alternative specs
for the commands that still precede a desync.

Spec letters:
  b  one byte                    w  two byte little-endian value
  p  two byte script pointer     t  two byte text pointer (not code)
  d  two byte data pointer       f  three byte far script pointer (bank, addr)
  T  three byte far text pointer D  three byte far data pointer
  m  three byte money value      M  two byte movement-data pointer
"""
import collections
import json
import sys

MAN = r"g:\Github Desktop\ComputerBuilderInt\gen2recomp\tools\rom_manifest_gold.json"
ROM = r"g:\Github Desktop\ComputerBuilderInt\gen2recomp\Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc"

CMDS = [
    ("scall", "p"), ("farscall", "f"), ("memcall", "p"), ("sjump", "p"),
    ("farsjump", "f"), ("memjump", "p"), ("ifequal", "bp"),
    ("ifnotequal", "bp"), ("iffalse", "p"), ("iftrue", "p"),
    ("ifgreater", "bp"), ("ifless", "bp"), ("jumpstd", "w"), ("callstd", "w"),
    ("callasm", "D"), ("special", "w"), ("memcallasm", "D"),
    ("checkmapscene", "bb"), ("setmapscene", "bbb"), ("checkscene", ""),
    ("setscene", "b"), ("setval", "b"), ("addval", "b"), ("random", "b"),
    ("checkver", ""), ("readmem", "w"), ("writemem", "w"), ("loadmem", "wb"),
    ("readvar", "b"), ("writevar", "b"), ("loadvar", "bb"), ("giveitem", "bb"),
    ("takeitem", "bb"), ("checkitem", "b"), ("givemoney", "bm"),
    ("takemoney", "bm"), ("checkmoney", "bm"), ("givecoins", "w"),
    ("takecoins", "w"), ("checkcoins", "w"), ("addcellnum", "b"),
    ("delcellnum", "b"), ("checkcellnum", "b"), ("checktime", "b"),
    ("checkpoke", "b"), ("givepoke", "bbbbbD"), ("giveegg", "bb"),
    ("givepokemail", "T"), ("checkpokemail", "T"), ("checkevent", "w"),
    ("clearevent", "w"), ("setevent", "w"), ("checkflag", "w"),
    ("clearflag", "w"), ("setflag", "w"), ("wildon", ""), ("wildoff", ""),
    ("xycompare", "d"), ("warpmod", "bbb"), ("blackoutmod", "bb"),
    ("warp", "bbbb"), ("getmoney", "bb"), ("getcoins", "b"), ("getnum", "bb"),
    ("getmonname", "bb"), ("getitemname", "bb"), ("getcurlandmarkname", "b"),
    ("gettrainername", "bbb"), ("getstring", "bd"), ("itemnotify", ""),
    ("pocketisfull", ""), ("opentext", ""), ("reanchormap", "b"),
    ("closetext", ""), ("writeunusedbyte", "b"), ("farwritetext", "T"),
    ("writetext", "t"), ("repeattext", "bb"), ("yesorno", ""),
    ("loadmenu", "d"), ("closewindow", ""), ("jumptextfaceplayer", "t"),
    ("jumptext", "t"), ("waitbutton", ""), ("promptbutton", ""),
    ("pokepic", "b"), ("closepokepic", ""), ("_2dmenu", ""),
    ("verticalmenu", ""), ("loadpikachudata", ""), ("randomwildmon", ""),
    ("loadtemptrainer", ""), ("loadwildmon", "bb"), ("loadtrainer", "bb"),
    ("startbattle", ""), ("reloadmapafterbattle", ""), ("catchtutorial", "b"),
    ("trainertext", "b"), ("trainerflagaction", "b"), ("winlosstext", "tt"),
    ("scripttalkafter", ""), ("endifjustbattled", ""), ("checkjustbattled", ""),
    ("setlasttalked", "b"), ("applymovement", "bM"),
    ("applymovementlasttalked", "M"), ("faceplayer", ""), ("faceobject", "bb"),
    ("variablesprite", "bb"), ("disappear", "b"), ("appear", "b"),
    ("follow", "bb"), ("stopfollow", ""), ("moveobject", "bbb"),
    ("writeobjectxy", "b"), ("loademote", "b"), ("showemote", "bbb"),
    ("turnobject", "bb"), ("follownotexact", "bb"), ("earthquake", "b"),
    ("changemapblocks", "bbb"), ("changeblock", "bbb"), ("reloadmap", ""),
    ("refreshmap", ""), ("writecmdqueue", "d"), ("delcmdqueue", "b"),
    ("playmusic", "w"), ("encountermusic", ""), ("musicfadeout", "wb"),
    ("playmapmusic", ""), ("dontrestartmapmusic", ""), ("cry", "w"),
    ("playsound", "w"), ("waitsfx", ""), ("warpsound", ""),
    ("specialsound", ""), ("autoinput", "D"), ("newloadmap", "b"),
    ("pause", "b"), ("deactivatefacing", "b"), ("sdefer", "p"),
    ("warpcheck", ""), ("stopandsjump", "p"), ("endcallback", ""), ("end", ""),
    ("reloadend", ""), ("endall", ""), ("pokemart", "bw"), ("elevator", "d"),
    ("trade", "b"), ("askforphonenumber", "b"), ("phonecall", "T"),
    ("hangup", ""), ("describedecoration", "b"), ("fruittree", "b"),
    ("specialphonecall", "w"), ("checkphonecall", ""),
    ("verbosegiveitem", "bb"), ("swarm", "bb"), ("halloffame", ""),
    ("credits", ""), ("warpfacing", "bbbbb"),
]
assert len(CMDS) == 162, len(CMDS)

BY_NAME = {name: i for i, (name, _) in enumerate(CMDS)}
SPEC_LEN = {"b": 1, "w": 2, "p": 2, "t": 2, "d": 2, "M": 2,
            "f": 3, "T": 3, "D": 3, "m": 3}
TERMINATORS = {
    BY_NAME[n] for n in ("sjump", "farsjump", "memjump", "jumpstd", "jumptext",
                         "jumptextfaceplayer", "stopandsjump", "endcallback",
                         "end", "reloadend", "endall", "halloffame", "credits",
                         "fruittree")
}
FOLLOW = set("pf")

rom = open(ROM, "rb").read()
sym = json.load(open(MAN))["symbols"]


def off(bank, addr):
    return bank * 0x4000 + (addr - 0x4000) if addr >= 0x4000 else addr


def seeds():
    """Every script entry point reachable from map headers and map events."""
    out = []
    for name, (b, a) in sym.items():
        if name.endswith("_MapScripts"):
            o = off(b, a)
            n = rom[o]; o += 1
            for _ in range(n):
                out.append((b, rom[o] | (rom[o + 1] << 8), "scene"))
                o += 4
            n = rom[o]; o += 1
            for _ in range(n):
                out.append((b, rom[o + 1] | (rom[o + 2] << 8), "callback"))
                o += 3
        elif name.endswith("_MapEvents"):
            o = off(b, a) + 2
            n = rom[o]; o += 1 + n * 5
            n = rom[o]; o += 1
            for _ in range(n):
                out.append((b, rom[o + 4] | (rom[o + 5] << 8), "coord"))
                o += 8
            n = rom[o]; o += 1
            for _ in range(n):
                # bg_event y, x, type, pointer.  BGEVENT_ITEM (7) stores an
                # item id in the pointer slot; BGEVENT_IFSET/IFNOTSET (5/6)
                # point at `dw event, dw script`, not at the script itself.
                kind, ptr = rom[o + 2], rom[o + 3] | (rom[o + 4] << 8)
                if kind in (5, 6):
                    q = off(b, ptr)
                    out.append((b, rom[q + 2] | (rom[q + 3] << 8), "bg"))
                elif kind != 7:
                    out.append((b, ptr, "bg"))
                o += 5
            n = rom[o]; o += 1
            for _ in range(n):
                kind = rom[o + 7] & 0x0F
                ptr = rom[o + 9] | (rom[o + 10] << 8)
                if kind == 2:
                    out.append((b, ptr + 12, "trainer"))
                    after = rom[off(b, ptr) + 10] | (rom[off(b, ptr) + 11] << 8)
                    if 0x4000 <= after <= 0x7FFF:
                        out.append((b, after, "after"))
                elif kind != 1:
                    out.append((b, ptr, "object"))
                o += 13
    return out


SEEDS = seeds()


def validate(cmds=CMDS, report=False):
    seen, prev, trails = set(), collections.Counter(), []
    queue = list(SEEDS)
    desyncs = 0
    while queue:
        bank, addr, src = queue.pop()
        if (bank, addr) in seen or not 0x4000 <= addr <= 0x7FFF:
            continue
        seen.add((bank, addr))
        pc, last, trail = addr, "<entry>", []
        for _ in range(4000):
            op = rom[off(bank, pc)]
            if op >= len(cmds):
                desyncs += 1
                prev[last] += 1
                if report and len(trails) < 10:
                    trails.append("%s %02X:%04X | %s | BAD %02X"
                                  % (src, bank, pc, " ".join(trail[-6:]), op))
                break
            name, spec = cmds[op]
            last = name
            trail.append(name)
            pc += 1
            # Script_givepoke reads species/level/item/trainer, then bails out
            # before the two name pointers when the trainer byte is zero.
            if name == "givepoke" and rom[off(bank, pc + 3)] == 0:
                spec = "bbbb"
            for ch in spec:
                if ch in FOLLOW:
                    o = off(bank, pc)
                    if ch == "p":
                        queue.append((bank, rom[o] | (rom[o + 1] << 8), src))
                    else:
                        queue.append((rom[o], rom[o + 1] | (rom[o + 2] << 8), src))
                pc += SPEC_LEN[ch]
            if op in TERMINATORS:
                break
    if report:
        print("scripts walked:", len(seen), " desyncs:", desyncs)
        for name, n in prev.most_common(12):
            print("  after %-24s %d" % (name, n))
        for t in trails:
            print("  " + t)
    return desyncs, prev


def tune():
    base, prev = validate()
    print("baseline desyncs:", base)
    variants = ["", "b", "bb", "bbb", "bbbb", "bbbbb", "d", "p", "t", "bd",
                "bp", "bt", "f", "D", "T", "bD", "w", "bw", "wb", "bbd", "bbp"]
    for name, _ in prev.most_common(10):
        if name not in BY_NAME:
            continue
        i = BY_NAME[name]
        scored = []
        for spec in variants:
            trial = list(CMDS)
            trial[i] = (name, spec)
            n, _ = validate(trial)
            scored.append((n, spec))
        scored.sort()
        print("%-24s current %-7r -> %s"
              % (name, CMDS[i][1], ", ".join("%r:%d" % (s, n) for n, s in scored[:4])))


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "tune":
        tune()
    else:
        validate(report=True)
