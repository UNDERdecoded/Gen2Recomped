# Pokemon Platinum / Gen 4 — what is built, what is not

Tracking document for Gen 4 support. Updated as work lands; the "Status" table
is the short answer and everything below it is the reasoning.

---

## Status

| Stage | State |
|---|---|
| Cartridge recognised and hashed | **Done** |
| Registered in the launcher (tab, panel, accent) | **Done** |
| NDS filesystem reader (`NdsRom`) | **Done** |
| NARC archive reader (`NarcArchive`) | **Done** |
| Script command table, 840 opcodes (`Gen4ScriptOps`) | **Done** |
| Nine variable-length script commands | **Deliberately unresolved** |
| Text decode (`pl_msg.narc`, `Gen4Text`) | **Done** — 46,053/46,053 strings |
| Species records (`Gen4Species`) | **Done** — 508 records |
| Graphics: containers, LZ77, palettes, tiles, tilemaps (`Gen4Graphics`) | **Done** |
| Battle sprites — cipher **solved**, sprites decode | **Done** |
| Moves (`Gen4Moves`) — 471 records | **Done** |
| Items (`Gen4Items`) — 446 records | **Done** |
| Learnsets and evolutions (`Gen4Species`) | **Done** |
| Wild encounters (`Gen4Encounters`) — 183 areas | **Done** |
| Trainers and parties (`Gen4Trainers`) — 928 | **Done** |
| Packed trainer names (`Gen4Text`) | **Done** |
| Map matrix + land chunks + permissions (`Gen4Maps`) | **Done** |
| Map events: NPCs, warps, signs, triggers (`Gen4Events`) | **Done** |
| Map names (`Gen4Maps.mapNames`) — 593 | **Done** |
| Map 3D meshes (NSBMD) and BDHC height | Not started |
| Map header table (`Gen4MapHeaders`) — 593 in the ARM9 | **Done** |
| Script decoding (`Gen4Script`) — bytes to instructions | **Done** |
| Script lowering (`Gen4ScriptVM`) — 97.8% of instructions | **Done** |
| Archive member names, 68 archives (`Gen4Archives`) | **Done** — 9,511 names |
| Screen composition: NSCR+NCGR+NCLR (`Gen4Graphics.compose`) | **Done** |
| Battle presentation tables (`Gen4Battle`) | **Done** — 23 backgrounds, 24 terrains |
| UI screen recipes (`Gen4Screens`) | **Done** — 16 archives |
| NCER cell banks (`Gen4Cells`) | **Done** — 135 banks, 1,184 cells |
| NFGR fonts (`Gen4Font`) | **Done** — 4 fonts, 509 glyphs each |
| Extractor: cartridge to cache (`RomExtractorGen4`) | **Done** — 13 tables |
| Wiring the extractor into `RomImporter` | **Done** |
| Registering scripts per map (`Gen4ScriptVM.register`) | **Done** — 374 maps |
| Script lowering to engine commands | Not started |
| Graphics extraction stage (`extractGraphics`) | **Done** — 1,405 PNGs |
| Font extraction stage (`extractFonts`) | **Done** — sheets + width tables |
| Fonts published as `data.font` (engine shape) | **Done** — 1 page, 3 faces, 484 charmap entries |
| Per-map regions cut from shared grids (`Gen4Maps.extents`/`crop`) | **Done** — 72 regions |
| Map defs with events attached (`extractRegions`) | **Done** — 593 defs, 5,636 events |
| Tile behaviours, named (`Gen4Behaviors`) | **Done** — 256 values, all 75 in use named |
| Stand-in tileset (`Gen4Tileset`) | **Done** — 15 terrain classes, no renderer changes |
| Type chart from the battle overlay (`Gen4TypeChart`) | **Done** — 110 rows, 2 sections |
| `constants`, `type_chart`, flat `text` | **Done** — all 11 SHARED modules present |
| Gen 4 branch in `Data.lua` module lists | **Done** — Gen 1/2/3 proven unchanged |
| A Gen 4 cache satisfies every required module | **Done** — 15 of 15, 0 missing |
| Overworld NPC sprites (`Gen4Models`) | **Done** — 421 sets, 3,567 frames |
| NPC sprites published as `data.sprites` | **Done** — 421 entries, keyed by member |
| `graphicsId` → sprite, through the overlay-5 table | **Done** — 3,128 resolve, 427 have no billboard by design, 0 broken |
| Script ids classified into their bands | **Done** — 30 bands from the cartridge's own dispatcher |
| Every pickup resolved to its item (`Gen4Pickups`) | **Done** — 329 balls + 262 hidden = 591 of 591, across 140 maps |
| Every map trainer resolved to its trainer record | **Done** — 417 of 417, class names from the ROM's own bank |
| Map height field (`Gen4Bdhc`) | **Done** — 666 of 666 chunks, 8,974 plates, 0 failures |
| Map meshes (NSBMD) | **Read and seen** — 666 terrain + 590 building meshes exact, rendered as recognisable Sinnoh; per-map texture sets unfinished; the ENGINE draws none of it |
| Species battle pictures (`Gen4Pokegra`) | **Done** — 493/493, front/back/shiny/shiny-back + 2-frame strips |
| Species pictures stamped onto `data.pokemon` | **Done** — the Gen 3 field names, no Gen 4 branch |
| Form sprites (`Gen4Otherpoke`) | **Done** — 78 forms, 463 images, Substitute + shadows |
| Form *switching* (weather, plate, appliance, letter) | Not started — engine logic, not extraction |
| Battle *engine* running on Gen 4 data | Not started |
| Summary/party screens running on Gen 4 data | Not started |
| Title sequence running | Not started |
| Dual-screen + Poketch presentation | Designed, not built |
| Start-menu style switch | Designed, not built |
| `importable` flipped to `true` | **Yes** — the launcher imports Platinum; the pill still says WIP |

The cartridge is **recognised but withheld**. A player who owns it can reach
Platinum's panel in the launcher and read exactly what is and is not ready,
rather than meeting "Not supported yet", which reads as "your dump is wrong"
and sends people hunting for another one.

---

## The cartridge, measured

Every figure here was read from the project's own dump, not copied from a
format note.

```
title        POKEMON PL          game code  CPUE      maker 01
unit 0       version 1 (Rev 1)   size       134,217,728 bytes (128 MiB)
used                             104,607,804 bytes
sha1         0862ec35b24de5c7e2dcb88c9eea0873110d755c
md5          ab828b0d13f09469a71460a34d0de51b

ARM9   rom 0x00004000  size 1,057,784  ram 0x02000000  entry 0x02000800
ARM7   rom 0x00409800  size   161,788
FNT    0x00431000 (7,092)      FAT  0x00432C00 (3,696) -> 462 entries
overlays  122 on the ARM9, 0 on the ARM7
filesystem  340 files in 89 directories
```

462 FAT entries = 122 overlays + 340 files, and the last byte any file
occupies is 104,607,804 — the used-size the header itself reports. The
filesystem walk accounts for the cartridge exactly.

Rev 0 (`ce81046eda7d232513069519cb2085349896dec7`) is registered as an
alternate hash. pokeplatinum builds both and the filesystem layout is the same
in each, which is what the extractor reads.

### Files that will matter

| Path | Bytes | What |
|---|---|---|
| `/fielddata/land_data/land_data.narc` | 16,125,840 | map terrain |
| `/poketool/pokegra/pl_pokegra.narc` | 11,778,676 | species sprites |
| `/msgdata/pl_msg.narc` | 4,351,320 | all text — 724 banks, 46,053 strings |
| `/data/mmodel/mmodel.narc` | 1,465,988 | overworld models |
| `/itemtool/itemdata/pl_item_data.narc` | 440,460 | items |
| `/fielddata/script/scr_seq.narc` | 304,476 | 1,124 script files |
| `/fielddata/encountdata/` | 237,324 | wild encounters |
| `/poketool/personal/pl_personal.narc` | 105,920 | 508 species records, 44 B each |

Message banks located by looking rather than assumed: **412** is species names
(entry 1 BULBASAUR, entry 25 PIKACHU), **706** is Pokedex entries.

Platinum keeps Diamond/Pearl's un-prefixed files beside its own `pl_`-prefixed
ones. The `pl_` file is the one to read; the other is the older game's.

---

## Staying legal

Identical to every other version here, and the reason the two new readers came
first.

* **No cartridge data is committed.** Not a table, not a tile, not a string.
* The ROM stays where the player keeps it. The importer reads it, writes a
  cache under `platinum/` (`cachePrefix`), and that cache is what the game
  loads through `CacheFs.mountVersion`.
* What lives in this repository is **scaffolding**: readers, tables of
  *offsets and shapes*, and code that knows how to ask the cartridge a
  question. Gen 4 does not change the rule; it only changes the question from
  "what is at address X" to "what is inside file Y".
* `Gen4ScriptOps.lua` is opcode numbers, command names and operand widths
  derived from pret/pokeplatinum — a description of the format, the same thing
  `Gen3ScriptOps.lua` is for Emerald. No script bytes from the cartridge.

---

## What is built

### `src/core/GameVersion.lua`

`platinum` registered: generation 4, both revision hashes, `cachePrefix
"platinum/"`, `saveSuffix "_platinum"`, `importable = true` (see *Turning it
on*), `experimental`,
and a new `dualScreen = true`. Two new predicates, `GameVersion.isGen4(id)`
and `GameVersion.isDualScreen(id)` — the second asked of the *version* rather
than computed from the generation, because "is Gen 4" and "has two screens"
are not the same claim and field code should say which one it means.

`GameVersion.ORDER` puts platinum after emerald and before the hacks:
cartridges in generation order, then romhacks.

### `src/import/RomImporter.lua`

Platinum has a chip in the tab row. **This is the only navigation into a
version's panel** — Prism was once registered without one and was hashed,
counted and completely unreachable, and the code comment saying so is still
there. Also:

* 128 MiB added to the accepted ROM sizes, `.nds` to the accepted extensions,
  and to all five native file pickers (macOS, Windows, zenity, kdialog, and
  the multi-select variants) plus the drag-and-drop hint.
* A `pokemon_platinum.nds` name for the panel, via a generation-4 branch.
* Chip colour `#a6b0d8 → #4a5286`: the metal with the cool cast the box art
  has, kept clear of Silver's near-white, Crystal's cyan and Polished
  Crystal's purple, because all four sit in one row.
* **A bug fixed on the way.** The "recognised, not playable yet" panel had one
  hardcoded sentence — *"Prism imports its data, but its scripts still
  misbehave"* — shown for **every** withheld game, under a comment reading
  "ONE SENTENCE PER GAME". Prism is importable now, so Platinum was about to
  become the only withheld game and its panel would have explained Prism.
  Replaced with `RomImporter.WITHHELD_REASON`, keyed by version.

### `src/import/NdsRom.lua`

The DS filesystem. `open` / `header` / `list` / `stat` / `read(path)` /
`readId` / `arm9` / `overlay(n)`.

A DS cartridge is a **filesystem, not an address space**, which is the single
biggest structural break from every generation above. `rom:u16(0x3DF884)` has
no meaning here; `rom:read("/poketool/personal/pl_personal.narc")` does.

It never loads the cartridge into memory. 128 MiB as one Lua string is a
number this engine has to run alongside on a phone, and nearly every stage
wants one file. The handle stays open and ranges are read on demand.

Two traps it avoids on purpose: the FNT is walked **by directory id**, not
linearly, because the subtables are not stored in tree order and a forward
walk builds a plausible tree with the wrong parents; and an overlay's bytes
come from the **file id at +0x18** of its table entry, not from the overlay
index, which are different numbers that look interchangeable.

### `src/import/NarcArchive.lua`

`parse(data)` / `count` / `range(i)` / `get(i)` / `all()`. Chunks are located
by walking, not by fixed offset — the header size is a field precisely because
it varies. Verified on two archives of very different shape: `scr_seq.narc`
(1,124 members) and `pl_personal.narc` (508 members of 44 bytes, which is
Platinum's species count and its personal-record size).

### `src/import/Gen4ScriptOps.lua`

All 840 opcodes, `$000`–`$347`, with names and operand specs.

Gen 4 reads its opcode as a **halfword**, not a byte — 840 commands do not fit
in one — so the smallest instruction is two bytes and a Gen 3 decoder fed Gen
4 bytes desyncs on the first command.

**Where the widths come from, and why that is the whole story.**
`Gen3ScriptOps.lua`'s header records what guessing cost: Emerald's `$E0` was
reasoned out from handler call shapes, came out two bytes short, and produced
not garbage but the Sootopolis cutscene playing twice with no warp home —
because a two-byte slip lands on a plausible opcode and the walk sails on. So:

* opcode numbers are the **order of the `ScriptCommand()` lines** in
  pokeplatinum's `include/data/scripts/scrcmd.h`. Position *is* the opcode,
  so all 840 are listed including dummies. Two of those lines are spelled in
  mixed case (`SCRCMD_GetExchangeServiceCornerItemAndCost` at `$2A2`,
  `ScrCmd_GETRANDOMBATTLEGROUNDTRAINERS` at `$2FB`); a reader matching only
  `[A-Z_]` silently drops them and shifts **every opcode after `$2A2` down by
  one** — the same class of failure, one level up. This was hit and fixed.
* operand widths are the stream reads in each handler body, in source order.
  The five primitives consume fixed widths (`ReadByte` 1, `ReadHalfWord` 2,
  `ReadWord` 4, and the inlines `GetVar`/`GetVarPointer` 2 each, both
  `ReadHalfWord` underneath).

**The two ways that could still be wrong, both measured:**

1. A handler reading inside an `if` has no fixed width. Nine do. They are
   marked `*` and listed in `VARIABLE_LENGTH` — **not guessed**.
2. A handler delegating its read to a helper would hide operands. Every
   function in pokeplatinum taking a `ScriptContext *` and transitively
   reaching a stream read was collected, and every handler body checked
   against that set: **zero** handlers delegate.

**Corroboration, which is not proof.** Walking all 1,124 members of
`scr_seq.narc` from all 4,079 entry points decodes 50,835 instructions across
381 distinct opcodes and reaches a clean `end` **4,070 times with no unknown
opcode**; 8 stop at a variable-length command and 1 runs past its member's end
(one member's header parse, listed under open questions). Gen3ScriptOps
explains precisely why this is corroboration and not proof. The proof is the
handler source; the corpus only shows nothing contradicts it.

### `src/import/Gen4Text.lua`

All of Platinum's text: 724 message banks, 46,053 strings. Each bank is
encrypted **twice** — once on its table of offsets and lengths, again with a
different key on the characters:

```
entry table:  k = (seed * 765 * (i+1)) & 0xFFFF;  k |= k << 16
              offset ^= k;  length ^= k          (length counts CHARACTERS)
characters:   key = ((i+1) * 596947) & 0xFFFF
              each u16 ^= key;  key = (key + 18749) & 0xFFFF
```

Both keys stay in 16 bits. In pokeplatinum's C the character key is a **u16
parameter** immediately overwritten by a 32-bit product, so the truncation is
the declaration doing it — and a 32-bit key decodes the first character
correctly and then drifts, which reads as a charmap problem rather than a
cipher one.

**Why this one is known to be right, unlike a script table.** All 46,053
strings decrypt and all 46,053 end in the `0xFFFF` terminator. A wrong key
does not land on a terminator by accident forty-six thousand times, and text
either reads or it does not — there is no plausible-but-wrong here. A second,
independent Python implementation was run over the whole cartridge and
compared line for line against the Lua: **zero differences**.

Escapes: `0xFFFE` introduces `command, argc, args...`; if the command's high
byte is a STRVAR base its low byte is the variable index. 68 distinct escape
commands occur in the cartridge and **every one is covered** — no unknown
control codes anywhere. `0xF100` starts a bit-packed trainer name terminating
on `0x01FF` (885 strings); not decoded yet, marked and stopped rather than
printed as characters.

### `src/import/Gen4Graphics.lua`

Nitro containers and the LZ77 the cartridge wraps most of them in. Magics are
stored reversed, like NARC's chunk tags: `RLCN` = NCLR (palette, section
`TTLP`), `RGCN` = NCGR (tiles, `RAHC`), `RCSN` = NSCR (tilemap, `NRCS`),
`RECN` = NCER (cells). Sections are found by walking from `headerSize` for
`sectionCount` chunks — both fields exist because they vary.

Two things believed from arithmetic rather than from a field:

* **Bit depth**, because `tilesX * tilesY * 32 == dataSize` settles 4bpp
  outright and cannot be misread.
* **Colour count**, as `dataSize / 2`. The palette depth field is the one
  field here whose meaning did not survive inspection — a 16-colour Platinum
  palette carries `4` where the published tables say `3` — and since the byte
  count is unambiguous, nothing needs the enum to be right.

`tilesX`/`tilesY` are `0xFFFF` on an **unsized** sheet (every party icon is
one); the tile count always comes from the byte count instead.

**Validated by looking, not counting.** All 540 party icons in
`pl_poke_icon.narc` render as recognisable Pokémon in the right colours. The
LZ was run over every compressed member of four graphics archives: **125 of
125** decompress to exactly their declared size and each one turns out to be a
valid Nitro container (48 NCGR, 27 NSCR, 23 NCER, 23 NANR). And a second,
independent Python implementation was compared pixel for pixel across all 540
icons — 1,105,920 pixels, **zero differences**.

That cross-check earned its keep immediately: it caught a real bug in the Lua,
where the tile `dataOffset` (which is relative to the start of the section's
*fields*) had the 8-byte tag/size header added a second time. That does not
crash — it produces recognisable shapes displaced by a quarter tile, which is
exactly the kind of wrong that survives a glance.

### `src/import/Gen4Species.lua`

508 records of 44 bytes from `pl_personal.narc`, with names from bank 412.
The 44 summing exactly is the check that the layout is read right, and the
values agree with the published tables (Pikachu 35/55/30/90/50/40 with
Static; Giratina 150/100/120/90/100/120; Arceus 120 across).

**One trap worth naming:** the stat order is hp, attack, defense, **speed**,
spAttack, spDefense. Speed is fourth, not last. Reading it in the display
order every stat screen uses swaps Speed with Special Attack and produces a
table that looks entirely plausible and is wrong for every species.

This stage also proves the floor: cartridge → `NdsRom` → `NarcArchive` →
record + `Gen4Text`, four modules and no special cases.

### `src/import/Gen4Moves.lua` and `src/import/Gen4Items.lua`

471 moves of 16 bytes from `pl_waza_tbl.narc`; 446 items of 34 bytes from
`pl_item_data.narc`. Names come from message banks 647 and 392, both found by
looking rather than assumed.

**Priority is signed.** Quick Attack is +1 and Roar is −6, and reading that
byte unsigned turns every negative-priority move into one that goes first —
no crash, no visual glitch, nothing a battle looks obviously wrong for. It
just quietly plays a different game. Verified: Quick Attack +1, Roar −6.

Item record checks against the published tables: Master Ball 0, Ultra Ball
1200, Poké Ball 200, Potion 300, HP Up 9800. Moves: Pound 40/100/35 normal
physical, Thunderbolt 95/100/15 electric special, Hyper Beam 150/90/5,
Struggle 50 power with 0 accuracy and 1 PP.

### Learnsets and evolutions (in `Gen4Species`)

`wotbl.narc` holds one **variable-length** learnset per species — 24 to 36
bytes, terminated by `0xFFFF`. Each entry is a u16 packing the move in the low
**9** bits and the level in the high **7**. That split is forced: 467 moves
need 9 bits and level 100 needs 7. Reading it the other way round gives move
ids under 128 at levels in the hundreds — a table that still looks plausible.

The structural check is what confirms it: across all 493 species, **6,598
learnset entries, zero move ids out of range and zero levels outside 1–100**.

`evo.narc` holds seven `{method, param, target}` slots per species in 44 bytes.
**Every method number was derived from the cartridge and checked against a
species that can be named**, because the enum lives in a generated header
pokeplatinum builds and does not ship — there was nothing to copy. Grouping
all 246 evolutions by method identified each one: 1 friendship (Golbat,
Chansey, Pichu), 4 level (162 of them), 8/9/10 Tyrogue's three branches,
11/12 Wurmple's personality split, 15 Feebas at beauty 170, 18 Happiny by day
and 19 Gligar by night, 20 knows-move (Aipom/Double Hit), 21 species-in-party
(Mantyke/Remoraid), 24 magnetic field, 25/26 the mossy and icy rocks.

`param` means a different thing per method — a level, an item, a move, a
species, or nothing — so `paramKind` says which. A caller that treats it as
one thing gets Pikachu evolving at level 83.

### `src/import/Gen4Encounters.lua`

183 areas of exactly 424 bytes — and that 424 is the check, because
pokeplatinum's `WildEncounters` struct sums to 424 to the byte.

Two things that look like mistakes and are not. **Species ids are four bytes
here**, not the two they are everywhere else in the cartridge, with three
bytes of padding after each one-byte grass level; reading them as u16 halves
the stride and walks the table into itself. And **a water slot stores maximum
level first, then minimum** — the cartridge really does put the larger number
first, and reversing it prints "Lv55-30", which reads as a display bug rather
than a parse one.

Twelve of the 183 areas have a grass rate of 0 with the whole grass table
zeroed: water-only routes, where level-0 slots are correct data. Validated on
that basis — 2,196 grass slots, zero species out of range, and **zero
out-of-range levels in any area whose rate is non-zero**. The first land area
comes out Geodude, Zubat and Onix at levels 4–8, which is Oreburgh Gate.

### `src/import/Gen4Trainers.lua`

`trdata.narc` (928 × 20-byte headers) and `trpoke.narc` (928, variable) share
an index and are meaningless apart.

**The header's `monDataType` sets the party stride, and it must be read rather
than inferred by dividing the party file by the party size.** Dividing works
for 887 of the 928 and then quietly does not: 39 party files carry trailing
padding, so the division lands on 12 or 20 where the real stride is 10 or 18,
and every mon after the first comes out shifted. Reading `partySize` entries
at the type's own stride and ignoring the remainder is correct for all 928.

`species` also carries the form in its high bits, so the id is the low 10 —
which matters for Wormadam cloaks and Rotom appliances.

Validated across the whole archive: **1,878 party members, zero species,
level, move or item values out of range.** Roark comes out Geodude 12 / Onix
12 / Cranidos 14 with Stealth Rock; Cynthia's six are right down to Garchomp
at 62 holding a Sitrus Berry.

### Packed trainer names (closing the last text gap)

Bank 618 has exactly 928 entries — which is how it was identified as the
trainer-name bank — and 885 of them use the `0xF100` sub-format that was
deferred earlier.

A packed name is **nine bits per character inside fifteen usable bits** of
each halfword, not sixteen, so characters straddle halfword boundaries and one
bit per halfword is skipped. It terminates on `0x01FF`, not `0xFFFF`. Both
oddities matter: packing into 16 bits decodes the first character correctly
and then drifts (which reads as a charmap problem), and watching for `0xFFFF`
means never stopping, so the name runs on into whatever follows.

All 885 decode with no unmapped character, every gym leader resolves, and the
full 46,053-string corpus was re-diffed against the independent Python
implementation afterwards — still zero differences.

### `src/import/Gen4Maps.lua`

**This is where Gen 4 stops resembling every generation above it.** Gen 1–3
give you a map: a grid of metatile ids plus a tileset, and the renderer draws
it. Gen 4 gives you a *matrix* of fixed 32×32 chunks, and each chunk carries a
movement-permission grid, a list of placed building models, a **3D mesh**, and
a separate height structure. The picture is a mesh, not a tilemap — but the
permission grid is a plain 32×32 array of u16, and that alone is enough to
know where the player may walk.

**The matrix** (`map_matrix.narc`, 289 members):

```
u8 width, u8 height, u8 hasHeaders, u8 hasAltitude, u8 nameLength, char name[]
u16 headers[w*h]    -- only when hasHeaders
u8  altitudes[w*h]  -- only when hasAltitude
u16 mapIds[w*h]     -- always; indexes land_data.narc
```

The two optional blocks are why this has to be parsed rather than indexed: a
reader that assumes they are present takes the map ids out of the header table
and builds the world from the wrong chunks. **All 289 members account for
their length exactly** under this layout — that is the check. Matrix 0 is
30×30 and named `map`: the Sinnoh overworld.

**The chunks** (`land_data.narc`, 666 members): four u32 sizes, then
permissions, objects, an `BMD0` NSBMD mesh, and a `BDHC` height block. All 666
satisfy `16 + the four sizes == file length`, all 666 have a 2048-byte
permission block, all 666 carry a BMD0 model.

**Permissions**: one u16 per tile. Bit 15 marks a tile that is not part of the
map — the void around the land — and the low byte is the terrain behaviour.
Across the whole overworld only 54 distinct values occur and only **two**
distinct high bytes, which is what says bit 15 is a flag and not part of a
number.

**Validated by looking.** The 30×30 matrix assembled into a 960×960 permission
image is recognisably Sinnoh: Mt. Coronet running north–south through the
middle, the three lakes as enclosed pockets, the Great Marsh's grid at
Pastoria, Route 223's water column up the east coast to the Battle Zone. A
layout error anywhere in the matrix or the chunk header would have scrambled
that beyond recognition. The Lua render was then compared pixel-for-pixel with
an independent Python one: the only differences are the 432 empty matrix cells
where one drew black and the other drew the void colour — **every real
permission value agrees**.

**Objects** are 48 bytes each, and the offsets were not read off one sample:
every field of all 3,476 placed objects was tabulated. That is what pins the
scale at +28/+32/+36 rather than the +24/+28/+32 a hand-read hex dump
suggested — an error that silently produced `scale 0.0`. Fields +16/+20/+24
are **always 0** and are left unnamed on purpose: they are almost certainly a
rotation, but with every object in the game at zero there is nothing to tell a
rotation from a reserved field, and naming one would be a guess dressed as a
fact. All 360 distinct model ids fall inside `build_model.narc`.

### `src/import/Gen4Events.lua`

`zone_event.narc`, 534 members — who stands on a map, where its exits go, and
what watches the player.

**The counts are interleaved**, not four counts up front: each block is a u32
count immediately followed by its own records.

```
u32 n; Sign[n]     20 bytes      u32 n; Warp[n]     12 bytes
u32 n; Npc[n]      32 bytes      u32 n; Trigger[n]  16 bytes
```

Reading four counts first looks right on member 0 — sixteen zero bytes, which
is an empty map either way — and then falls apart on every populated map. The
interleaved layout accounts for **all 534 members exactly**, and it is the
only combination in a search over every stride from 8 to 40 that does; the
next best fits fewer than 15.

**Which block is which was settled by measurement, not by position:**

* **NPCs** — all 3,555 records have a model id below 470, exactly the member
  count of `mmodel.narc`, the overworld model archive.
* **Warps** — 1,207 of 1,213 have a destination below 593, the number of names
  in `mapname.bin`; the other six are 4095, a "nowhere" sentinel. The fields
  at +0/+2 reach 909, so they cannot be map ids and are coordinates.
* **Triggers** — **all 186** carry a value at +14 of `0x4000` or above, which
  is Gen 4's variable space. A trigger is a variable, a value to match, an
  area and a script.
* **Signs** — the remaining block, and the one identification here that is
  inference rather than proof. Its records carry a script id, a position (+4
  and +8 are u32: the halves at +6 and +10 are zero in all 682) and a small
  type field, which is the shape of an interactable. Labelled as such, with
  that caveat kept in the source.

Validated across every zone: 534 parsed exactly, zero failures, zero NPC
models outside `mmodel`, zero warp destinations outside the name table, zero
triggers below the variable base. Spot-checking one city's warps resolves them
to its two routes and its Pokémon Center by name.

`Gen4Maps.mapNames` reads `mapname.bin` — 593 sixteen-byte zero-padded ASCII
names, which is the count every warp destination stays below.

### `src/import/Gen4MapHeaders.lua`

Every other Gen 4 table lives in the filesystem and opens by name. This one
does not — it is compiled into the **ARM9 binary**, and it is the record that
ties a map to its matrix, area data, script file, text bank, wild encounters,
events and music. Without it the other modules each read correctly and none of
them knows which map it belongs to.

593 records of 24 bytes, matching pokeplatinum's `MapHeader`.

**Found by searching, not by a hardcoded offset.** In this cartridge it sits
at ARM9 offset `0x0E601C` (RAM `0x020E601C`), but that is a fact about one
build — Rev 0 is a different binary, and a fixed offset there would read
whatever happens to live at that address and hand back 593 confident, wrong
records. `find` scans for a run of 24-byte records whose every field indexes
*inside* the archive it names: matrix < 289, events < 534, scripts < 1124,
messages < 724, encounters < 183 or the 0xFFFF sentinel, area < 75.

**Why 593 and not 594.** A loose filter finds 594 consecutive plausible
records; the 594th is not a map. Tightened against the area-data archive it
fails immediately, while all of 0..592 pass **every** cross-check against six
separate archives. 593 is also exactly the number of entries in
`mapname.bin`. Taking the loose answer would have added one phantom map — the
kind of off-by-one that only surfaces when something walks the whole table.

The strongest confirmation is coverage rather than shape: the 593 headers
between them reference **all 534** members of `zone_event.narc`, highest index
533, none left over and none out of range.

#### A join that succeeded and was wrong

`mapLabelTextID` indexes **message bank 433** — 126 display names, "Jubilife
City", "Old Chateau", "Rock Peak Ruins". It does *not* index `mapname.bin`,
which is a separate table of 593 **internal** identifiers keyed by the header
id itself: `C01`, `C05GYM0113`, `D25R0106`.

Both tables have an entry for every map, so joining `labelText` to
`mapname.bin` never errors and never looks broken — it just quietly reports
that Jubilife City is called "C01PC0101". The bound that made it look correct,
`labelText < 593`, holds trivially: `labelText` never exceeds 125. This was
caught by checking a name against the game rather than against a range.

With both joins right the chain reads: header 3 is **Jubilife City** (`C01`)
on the 30×30 overworld matrix with 33 NPCs and 14 warps, bike, run and fly all
allowed; header 100 is **Hearthome City**'s gym (`C05GYM0113`), 1×1, none of
the three allowed; header 300 is the **Old Chateau** (`D25R0106`) with
encounter table 130.

#### And the event structs corrected an axis mistake

pokeplatinum's `MapHeaderData` names its four event arrays `bgEvents`,
`objectEvents`, `warpEvents`, `coordEvents` — in exactly the order the file
stores them, which confirmed the block identification including the one that
had only been inferred. The structs also showed that measuring alone had
produced the right fields with the **wrong axes**: Gen 4 is 3D, so the two
horizontal axes are X and **Z**, and **Y is height**. The byte census found
the height fields sitting at zero on most events and filed them as padding;
they are not, and an object event's height is a 20.12 fixed-point value at +28
rather than the u16 at +30 a census suggested. A census tells you which bytes
vary. It cannot tell you what they mean.

### `src/import/Gen4Script.lua`

`Gen4ScriptOps` says how wide every command is; this walks a real script file
with it and produces instructions — opcode, name, operands, and for a jump the
absolute target rather than the relative offset the cartridge stores. Lowering
sits on top of this; nothing here decides what a command *means*.

**A member is not a script.** Each of `scr_seq.narc`'s 1,124 members holds
several scripts behind a header of u32 offsets that are relative *to the
position after the offset word*. The header ends either at the halfword
`0xFD13` or, more often, simply where the first script begins — there is no
count. So the walk stops when the cursor reaches the lowest target seen, the
only rule that works for both shapes. Reading a count that isn't there takes
the first script's opcodes as more offsets.

**Jumps are signed and relative to the end of the instruction.** `goto` and
`call` measure from the byte *after* the operand, and the offset is negative
for every backward jump, which is most loops. Reading it unsigned sends a loop
several gigabytes forward and the decode just stops — which looks like a short
script, not a misread operand.

**How the jump formula was checked**, since a decoder that reads its own output
will agree with itself all day: starting at every entry point and following
every jump **transitively** reaches 8,567 basic blocks and 78,093 instructions
— twice what a linear walk sees — and of the **15,002 jump operands in them,
zero point outside their own member**. 8,549 of those blocks then decode to a
clean `end`.

That tests two things at once. A wrong sign or base would scatter targets to
negative numbers and gigabyte offsets; a wrong operand width anywhere earlier
in an instruction would shift the jump operand itself and produce the same
mess. Neither happens. Four blocks of 8,567 stop unexpectedly — two run off the
end, two reach an opcode not in the table — which is 0.05%, recorded rather
than smoothed over.

**Coverage, which is what makes lowering plannable:** 4,079 scripts from the
entry points, 50,835 instructions, 381 distinct opcodes.

| commonest N opcodes | share of instructions | scripts fully covered |
|---|---|---|
| 20 | 87.3% | 58.3% |
| 40 | 95.9% | 78.4% |
| 80 | 98.3% | 88.7% |
| 150 | 99.3% | 94.5% |

The top of that list is the shape of a conversation — `lockall`, `faceplayer`,
`message`, `closemessage`, `releaseall` — so a lowering that starts there gets
NPCs talking before anything else works. Decoding a real one gives a Poké Mart
clerk: `playse / lockall / faceplayer / callcommonscript / closemessage /
pokemartcommon / releaseall / end`.

### `src/script/Gen4ScriptVM.lua`

A sibling of `Gen3ScriptVM` by design: `ScriptRunner` and `Commands.resolve`
are generation-agnostic, so a fourth generation needs a lowering and a verb
set, not a fourth script subsystem. Shared verbs (`jump`, `label`,
`show_text`, `ask`, `set_flag`, `play_sound`) are emitted as-is; anything Gen 4
does that no earlier generation has gets a `g4_` verb, exactly as Gen 3 uses
`g3_`.

**Measured against the whole cartridge** — 4,079 scripts, 50,843 instructions —
it lowers **97.8% of instructions** and leaves **85.7% of scripts** with
nothing unimplemented in them at all.

It got there in three passes, and their shape is the useful part:

| pass | instructions | whole scripts |
|---|---|---|
| the conversation set | 87.8% | 52.7% |
| + 8 (trainer preamble, signposts) | 97.3% | 82.4% |
| + 10 load-bearing | 97.8% | 85.7% |

The conversation set alone reached 87.8% of instructions but only 52.7% of
whole scripts, because **a script is only as lowered as its worst command**.
The eight added next were the four generated trainer-battle commands — each
occurring exactly 928 times, once per trainer in `trdata.narc` — and the four
that drive a signpost, which have to lower together or a sign opens and never
closes.

The last ten occur twenty-odd times each and are load bearing anyway: `warp`,
without which the player cannot leave a map; `starttrainerbattle`, without
which the trainer preamble runs and nothing happens; `pokemartcommon`, without
which the clerk says hello and sells nothing. **Frequency is a good guide to
what to lower first and a poor guide to what to stop at.**

What remains is a flat tail of side systems — TV interviews, the journal, the
Battle Tower, Turnback Cave, the Poketch — at a few dozen occurrences each,
left as explicit `g4_unimplemented` rows rather than dropped. A silently
dropped command is a script that runs and quietly does the wrong thing, which
is much harder to find than one that reports what it could not do.

The Poké Mart clerk now lowers completely:

```
{ play_sound, 1500 } { g4_lock_all } { g4_face_player } { g4_common, 2019 }
{ g4_close_message } { g4_pokemart, 1 } { g4_release_all } { jump, end }
```

**What is not here:** this is the lowering half. The extractor half — writing
a script pool into `data/generated` and registering a contribution per map
through `MapScripts` — is not built, so nothing calls this in a running game
yet.

### `src/import/RomExtractorGen4.lua`

Eleven modules read Platinum correctly and none of them wrote anything. This
is the stage runner that puts them in order and lands their output in
`data/generated`, which is what `CacheFs.mountVersion` serves to a running
game.

**It takes a path, not the ROM's bytes** — the one place it deliberately does
not look like `RomExtractorGen2` and `RomExtractorGen3`. Those are handed the
whole cartridge as a Lua string, which is fine at 32 MiB. Platinum is 128 MiB,
the engine has to run alongside it on a phone, and almost every stage wants
*one file* out of a filesystem. `NdsRom` reads ranges on demand; handing it a
128 MiB string would undo that before the first stage ran.

**Measured end to end against the cartridge: 4.2 seconds, 12 tables.**

| table | entries | | table | entries |
|---|---|---|---|---|
| `gen4_text` | 724 banks | | `gen4_map_headers` | 593 |
| `gen4_species` | 508 | | `gen4_map_matrices` | 289 |
| `gen4_moves` | 471 | | `gen4_map_permissions` | 666 |
| `gen4_items` | 446 | | `gen4_map_objects` | 387 |
| `gen4_encounters` | 183 | | `gen4_events` | 534 |
| `gen4_trainers` | 928 | | `gen4_scripts` | 873 / 8,567 blocks |

Every count matches what the individual modules measured independently, and
the spot checks land: Pikachu with 90 base speed, 13 learnset moves and one
evolution; Thunderbolt at 95; Potion at 300; Roark with three Pokémon;
map header 3 as Jubilife City (`C01`) on matrix 0.

Two shape decisions worth naming. Permissions are stored as **one binary
string per chunk** rather than 1,024 numbers — the same choice Gen 3's map
grids make, because a 666-entry table of thousand-element arrays is slow to
load and enormous on disk while a string is neither. And **lowering does not
happen here**: the pool holds decoded instructions and `Gen4ScriptVM` lowers
at load time, so a lowering fix does not require re-importing the cartridge.

The script pool follows jumps as well as entry points — a block reached only
by a `goto` is still a block the runner needs — which is why it holds 8,567
blocks rather than the 4,079 a linear walk finds.

### Wiring it into `RomImporter`

The extractor dispatch already anticipated this. Its comment reads *"Adding a
fourth generation should be a line here, not a bug"* — and it very nearly was
one line:

```lua
[4] = { module = "src.import.RomExtractorGen4", takesVersion = true,
        takesPath = true },
```

`takesPath` is the part that made it more than a line. `startData` now takes an
optional `sourcePath`, and `startPath` passes the whole path rather than
reducing it to a basename. Verification is unchanged — hashing a cartridge
means hashing its bytes and there is no way around that — but the moment the
SHA-1 matches, a Gen 4 import releases the 128 MiB string and hands the
extractor a path instead. Dropping the bytes *there* rather than after the run
is the entire point; keeping them live through extraction would have gained
nothing.

**A dropped file may have no path.** `love.filedropped` gives a File whose
`getFilename` is a real path on desktop and need not be anywhere else, and the
Android save-directory scan reads through `love.filesystem` rather than the
disk. A Gen 4 import that gets that far without a path now fails with a
sentence telling the player to use the Import button, instead of passing `nil`
into `new` and failing inside `NdsRom` with something about a missing ROM
path.

### Registering scripts per map

`Gen4ScriptVM` gained `store`, `compile` and `register`, following the Gen 3
contract exactly — including the `source` guard, because a cache built by a
different generation's extractor has a pool of the same *name* and a
completely different shape.

**Gen 4 has no TEXT constant.** Gen 2 and Gen 3 key a map's `talk` table by
one, and the overworld looks a script up with `talkScript(mapId, npc.def.text)`.
A Gen 4 object event carries a script id and nothing else, so the key is the
script's own label — `M0002/S1321` — and both the extractor and the VM derive
it from `Gen4ScriptVM.label`, so they cannot drift apart.

Map ids are the cartridge's **internal** names from `mapname.bin` — `C01`,
`C05GYM0113`, `D25R0106`. Unique, stable, and readable in a log. The
player-facing name is a different table and several maps share one, so it
would not do as a key.

End to end: extraction 3.9s, **478 maps linked, 374 attached** with talk
tables, and Jubilife City's 21 scripts lower to real conversations and
signposts.

#### A failure count that was wrong

The first run reported 1,887 scripts linked and **2,350 "missing"** — more
misses than hits, which should never be believed without checking what the
misses are. They were not missing. Classified:

| script id | events | what it is |
|---|---|---|
| `0` | 202 | no script |
| `1 .. entry count` | 1,887 | a real entry in this map's member |
| `>= 10000` | 796 | another namespace (590 are the single value 10001) |
| anything else larger | 1,352 | also another namespace |

The values in that last band are plainly not indices: script `9300` in a
member holding 28 entries, `2035` in a member holding 4. Both large bands are
ids the **field engine interprets directly**, so they are now recorded as
`special` rather than counted as failures — and kept rather than dropped,
because knowing an object *has* one is worth more than silence. What each band
means is not claimed anywhere, because nothing has established it yet.

---

## Presentation: battles, stats, menus, the title sequence

Everything in this section was *decodable* before and none of it could be
**seen**. That gap is the whole subject: a Gen 1–3 screen is one picture at one
address, and a Gen 4 screen is three files at three unrelated indices in an
archive that records no relationship between them.

### The thing that unlocked it: member names

A NARC has no directory. Members are addressed by index and nothing inside the
file says what any of them is. pokeplatinum ships **71 `.order` files** — the
build's record of which source asset became which index — and matching them to
archives by member count resolves **68 of them, 9,511 names**, now in
`src/import/Gen4Archives.lua`. Names only; every byte still comes from the
player's own cartridge.

Three are deliberately unresolved: `anim_ncer.order` and `anim_ncgr.order` both
match `wecell.narc` and nothing distinguishes them by count, and
`species_icons.order` has no archive of its length here. Guessing would put
wrong names on real members, which is worse than having none.

**Why this is not a convenience.** In `pl_winframe.narc`, `message_box_00`'s
tiles are member 3 and its palette is member 26. Pairing members positionally —
in threes, or by adjacency — puts the wrong palette on every window frame in
the game. That does not fail; it produces a picture, in the wrong colours. The
names are what make the pairing checkable.

### Composition

`Gen4Graphics.compose` takes a tilemap, a tile sheet and a palette and returns
RGBA. `composeGroup` does the same from a named archive group. The tilemap
supplies, per 8×8 cell, a tile index, two flip bits and a 4-bit sub-palette;
4bpp sheets take their sixteen colours from that sub-palette, 8bpp sheets
ignore it.

Verified by rendering, not by counting: the **Pokémon Platinum logo** comes out
pixel-correct from `titledemo.narc`, and the summary screen's **condition page
renders its COOL / BEAUTY / CUTE / SMART / TOUGH pentagon**. A tilemap walk
that were subtly wrong would not produce readable lettering.

### Battle backgrounds — arithmetic, not names

`pl_batt_bg.narc` is the one archive here with **no** `.order` file. Its 342
members are an irregular run — 171 compressed, then 91 palettes, then 4
tilemaps, then 76 more palettes — with no stride to find. The indices come from
what the game itself computes (`battle_display.c`):

```
tilemap = 2                                   -- shared by every background
tiles   = 3   + background
palette = 172 + background * 3 + timeOfDay
```

Three facts, checked against the cartridge rather than taken on faith:

* member 2 really is an NSCR and members 3…25 really are NCGR;
* members 172…240 really are NCLR — 23 backgrounds × 3 times of day;
* **all 138 member references resolve to the right kind of file, 0 wrong.**

The count 23 is confirmed a second, independent way: `sFadeTargets` is a
per-background table with exactly 23 entries, and the only three that fade to
black instead of white are entries 9, 10 and 11 — which is precisely where the
three caves fall in the enum order derived separately from
`sTerrainForBackground`. Two unrelated tables agreeing on both the length and
the interior ordering is worth more than either one alone.

**The tilemap is shared.** Every background reuses member 2, so a background is
a tile sheet plus one of sixty-nine palettes over a common arrangement. Looking
for a per-background tilemap that does not exist is the obvious wrong turn, and
it at least fails loudly — it produces nothing rather than something wrong.

### Terrain platforms

The ground each battler stands on is chosen from **the tile the player was
walking on**, not from the map — grass, sand, ice, snow, mud, cave and surfable
water each override the map's own background. 24 terrains, two sides, three
palettes; all 144 lookups resolve against `pl_batt_obj.narc`.

Four terrains borrow another's art rather than having their own, and **BRIDGE
borrows a different one per side** — `path_puddles` for the player, `mud` for
the enemy. Collapsing that to one name per terrain would put a puddle under the
enemy on every bridge in Sinnoh, so `Gen4Battle.TERRAIN_ART` keeps the split.

### Two naming conventions, and the planner that needed both

The UI archives are named two incompatible ways, and a planner that knows only
one silently drops half the game's screens:

* **Subject-named** — `logo.NCGR`, `logo.NCLR`, `logo.NSCR`. Grouping by base
  name is exactly right.
* **Role-named** — `shop_gra` is `tiles.NCGR`, `default.NCLR`, `tilemap.NSCR`.
  Every base name differs, so base-name grouping yields four groups of one and
  not a single composable screen.

A third case sits between them: `pl_bag_gra` names its sheet
`bag_ui_main_tileset.NCGR` and its tilemap `bag_ui_main.NSCR`. `Gen4Screens`
normalises away the role suffixes and then lets a group missing a part fall
back to the archive's own sheet — preferring **the sheet a tilemap already
points at**, because in `pl_bag_gra` the first NCGR is the player's bag *sprite*
and the screen sheet is the twelfth member. Taking the first one put the bag
sprite's pixels behind the bag's own UI, which is what the first run did.

Borrowing is recorded on each job rather than hidden: a borrowed palette is a
guess, and a guess that is not marked is indistinguishable from a fact.

### What the stage writes

`RomExtractorGen4:extractGraphics` renders **416 images in under 2 seconds** and
writes them under `assets/generated/gen4/`, indexed by `gen4_graphics`:

| Group | Contents |
|---|---|
| `battle/background/` | 23 backgrounds × 3 times of day, 512×256 |
| `battle/terrain/` | platforms, both sides, per time of day where it varies |
| `battle/` | healthboxes, type icons, interface, ball throws, trainer backs |
| `title/` | logo, "Developed by GAME FREAK inc.", screen borders |
| `menu/` `windows/` `touch/` `options/` | start-menu icons, window frames, touch buttons |
| `summary/` | all ten summary pages over one shared 480-tile sheet |
| `party/` `bag/` `trainer_card/` `poketch/` `shop/` `town_map/` `pokedex/` `mail/` `berry_tag/` `font/` | the rest of the interface |

**Screens are final; sheets are provisional.** A group with a tilemap is drawn
as the game draws it. A group without one is an OAM sheet whose true
arrangement lives in an NCER cell bank, and it is laid out at a stated width so
it can at least be looked at. Every such image is flagged `provisionalLayout`
in the index rather than passed off as finished — correct pixels, placeholder
arrangement.

---

### NCER: where a sprite's shape actually lives

A tilemap says where every 8×8 cell of a *background* goes. A sprite has no
tilemap — it is drawn by the object engine from a handful of OAM entries, each
a rectangle of tiles at a signed offset from the sprite's centre — and its NCGR
records no width at all. `tilesX` and `tilesY` are `0xFFFF`.

That is why a sheet laid out at a guessed width looks like the right picture
cut into strips and stacked wrongly: **the pixels were never wrong, the
arrangement simply was not in the file being read.** `src/import/Gen4Cells.lua`
reads the file it is in.

Three things in the format are easy to get wrong and none of them fails loudly:

* **The mapping mode is not decoration.** An OAM tile index is counted in units
  of `32 << mappingMode` bytes, not in tiles. Platinum's banks use mode 1, so a
  4bpp index steps *two* tiles at a time. Reading it as tiles halves every
  offset and assembles a real sprite out of the wrong halves of itself.
* **Positions are signed and centred** — Y is 8 bits, X is 9, both two's
  complement. Unsigned puts everything above or left of centre at the far side
  of a 256-pixel field.
* **Flipping a multi-tile entry mirrors the whole rectangle**, so the tile that
  lands in a slot comes from the opposite corner *and* is itself drawn
  mirrored. Doing only one of the two scrambles the sprite instead of
  mirroring it.

### Finding the bank for a sheet

A bank is almost never named after the sheet it serves, because one bank
usually serves many. `Gen4Archives.cellBank` tries the spellings the cartridge
actually uses, strongest first, and **reports which one matched** so a weak
match is never presented as a fact:

| Match | Example | Meaning |
|---|---|---|
| `named` | `healthbox/short` → `healthbox/short_cell` | its own bank |
| `folder` | `type_icons/fire` → `type_icons/cell` | one bank per folder |
| `folder` | `ball_throws/poke` → `ball_throws/shared_cell` | a named shared bank |
| `folder` | `terrain/grass/player` → `terrain/player_cell` | folder dropped, leaf kept |
| `prefix` | `bag_sprite_male` → `bag_sprite_cell` | the bank names a set |
| `sole` | `cheri` → `berry_cell` | one bank in the archive, many sheets |

The terrain case is why this is a list and not a rule: **the bank is named for
the side and the terrain is the folder in between**, so nothing about the
sheet's own name predicts it. `sole` is a judgement rather than a reading, and
is recorded as such.

Result: **302 of 458 sheets resolve to a bank.** The 156 that do not are in
archives holding no NCER at all — window frames, mail backgrounds, fonts —
which are tilesets rather than sprites, so there may be no bank to find.

### What the banks corrected

The platform sheets were being written 64×128, stacked eight tiles wide. The
banks say what they are:

* `terrain/player_cell` — four OAM entries of 64×32 → the **256×32** player
  platform
* `terrain/enemy_cell` — two entries of 64×64 → the **128×64** enemy platform

All 24 terrains share those two banks, which is the reason every platform sheet
is exactly 128 tiles — a fact that had been noted and not explained.

The stage now writes **1,405 images in 4.1 seconds, 0 skipped**: 69
backgrounds, 88 platforms, 326 battle objects and 922 interface images, with
type icons, healthboxes, bag sprites, menu icons and Poketch digits all at
their real sizes rather than at a guessed width.

**A bug in this work worth recording.** The first run assembled nothing in the
battle-object loop and every sheet quietly took the fallback path. The cause
was `local sheet, pal = palette and self:partsFor(...)` — in Lua, `x and f()`
is adjusted to **one** value, so `pal` was always `nil`. It did not error; it
produced the old behaviour, which is exactly the kind of regression that hides
behind a passing run.

---

### NFGR: the fonts, and therefore every word the game says

An NFGR is **not a Nitro container**. No `RGCN`-style magic, no tagged
sections — a 16-byte header, a run of glyphs, a table of widths:

```
u32 size              offset where glyph data starts (0x10)
u32 widthTableOffset  one byte per glyph
u32 numGlyphs
u8  maxWidth, maxHeight
u8  glyphWidth, glyphHeight   -- in TILES, 1 or 2, not pixels
```

All four fonts account for themselves **exactly** — `16 + numGlyphs × 16 × gw ×
gh + numGlyphs == the member's length` — which is a far stronger identity test
than a four-byte tag, and the only one available since they carry no magic.
509 glyphs each; system and message are 16×16 with mean advance 7.4px,
subscreen 9.1px, unown 12×16 with 399 zero-width glyphs (it defines only the
Unown alphabet).

**The first trap is that these look compressed and are not.** Every NFGR begins
`10 00 00 00` — `0x10` is the font's own data offset, not a compression tag. A
decompressor that tests only the first byte accepts it, reads a declared output
size of **zero** from the next three bytes, and returns an empty string. Not an
error, not garbage: the file simply vanishes, and the caller sees a zero-length
member rather than a bad one.

`Gen4Graphics.isCompressed` now also requires a non-zero declared size. Scanning
every named member in the cartridge, **9 of 9,511 would have been silently
emptied** by the old test — the four fonts, four `mmodel` animation files, and
`scripts_hearthome_city_dp_gym_leader_room`, a real script member.

**The second trap is the bit order.** Glyph pixels are 2bpp packed
**MSB-first** — the opposite of the 4bpp graphics everywhere else in this
cartridge, where the low nibble is the first pixel. And within each two-byte
row the **high byte holds the first four pixels**, because the game reads the
row as a `u16` and looks up `row >> 8` before `row & 0xFF`. Getting either
backwards yields legible-looking glyphs mirrored in fours, which reads as a
font problem rather than a bit-order one.

**The third is that a pixel is a role, not a colour.** The two bits select from
{ nothing, foreground, shadow, background }, and
`Text_GenerateFontHalfRowLookupTable` builds that lookup from three colours the
caller supplies **per text box**. So a glyph has no palette; the same glyph is
white-on-dark in a battle and dark-on-light in a menu. The cache keeps the
roles rather than baking one colouring in, which would freeze menu text into
battle colours.

The default colouring leaves the **background role transparent**, and that is
worth stating because the alternative fails in an instructive way: on hardware
the background fills the whole 16×16 cell while a glyph only *advances* by its
width — six or seven pixels for most letters. Painting it opaque makes each
cell overwrite most of the one before it, and a line of text comes out as a row
of blocks with the letters crushed together. Legible, wrong, and easy to
mistake for a bad width table.

**End-to-end proof.** Taking the string `PLATINUM 493!`, mapping each character
through `Gen4Text.CHARS` to its charcode, reaching the glyph by the game's own
rule (charcode 1 is glyph 0), unpacking the 2bpp bitmap and advancing by the
width table gives an 89-pixel line that renders as the words themselves in
Platinum's message font. That exercises the charmap, the glyph indexing, the
bit order and the widths in one test — any of them wrong and it does not read.

---

### Publishing the fonts where the engine already looks

`src/render/Font.lua` is generation-agnostic and already takes everything Gen 4
needs: a page table, named faces beside it, per-glyph widths, and a charmap. So
the font stage writes `data.font` in **that** shape rather than a `gen4_`
spelling. A Gen 4-shaped font table would have meant a generation branch in
every screen that draws a word.

```
pages   = { message = <the dialogue font> }
faces   = { system, subscreen, unown }
charmap = 484 entries
frame   = "drawn"          -- Gen 4's window frames come from pl_winframe
```

**One page, three faces** — not four pages. All four fonts number their glyphs
from the same base, so registering them all as pages would leave the
code-to-page lookup answering with whichever sorted first. That is the exact
problem `Font.lua`'s own comment describes for Emerald's five Latin faces, and
its answer — a face is chosen by name, not resolved from a glyph id — is the
one taken here.

**`base = 1`, not 0.** The cartridge reaches a glyph by subtracting one from the
character code, so code 1 is glyph 0. `Font.lua` indexes quads by `code - base`
and widths by `code - base + 1`; with base 1 both land on exactly the arrays the
stage writes, so neither side adjusts for the other. Verified end to end: code
299 → quad 298, width 6, character `A`.

**The charmap is inverted from the text decoder**, so the two cannot disagree
about what a character is. Only codes the font actually *has* are included:
`Gen4Text` knows 2,876 characters and this cartridge's font holds 509 glyphs, so
the remainder are Japanese codes with nothing to draw and mapping them would put
a character on screen as whatever happened to sit at that quad. 484 of the 509
are spoken for, and **none of them is a ligature** — no entry in range covers
more than one character — so there is no multi-letter sequence to mis-match
ordinary text the way Gen 3's `PK`/`MN` pair does.

**The tone order is fixed by a shader, not by taste.** `Font.lua` recolours a
pre-tinted page by telling the two tones apart by **luminance** — `lum < 0.5` is
the ink, anything brighter is the shadow. A sheet baked light-on-dark would look
correct until the first `{COLOR}` swap, which would then paint the letter with
the shadow's colour and vice versa. So the sheet bakes the letter dark and the
shadow light, which also matches the Gen 3 page and the light boxes this engine
draws — one sheet, right for both paths.

---

### A Gen 4 map is a region of a shared grid

This is the structural break that everything downstream had to absorb, and it
does not exist in Gen 1–3 at all.

A Gen 1–3 map **is** a grid. **84 of Platinum's 593 headers name matrix 0** —
the 960×960 Sinnoh overworld — and each one is a *piece* of it. Jubilife,
Route 201 and Oreburgh are regions of one seamless world, each contributing its
own NPCs and warps at coordinates measured from the **matrix's** corner rather
than their own.

What says which piece is the matrix's per-cell header array — and only **2 of
the 289 matrices carry one**. For the other 287 the matrix is the map, which is
the ordinary case and needs nothing.

`Gen4Maps.extents` reads that array into a bounding box per header, and
`Gen4Maps.crop` cuts the region out of the layout. Two things worth stating:

* **Header 0 is excluded.** It owns 731 of the overworld's 900 chunks — ocean,
  border, the space between routes — and giving it a box would produce one
  "map" the size of Sinnoh overlapping every other.
* **A region is a bounding box, so four of the sixty-six are not solid
  rectangles.** That is flagged as `regionSolid` rather than quietly squared
  off.

**Cutting is smaller, not larger.** The overworld's regions total 0.34 MB
against the layout's 1.76, precisely because header 0 is not a map.

### Events, made map-local

The events live per event-archive and their coordinates are matrix-global,
which is consistent: on the overworld the matrix is the only thing all 84 maps
share. **All 5,636 events in the cartridge fall inside their own map's matrix
grid** — that is what establishes the coordinate space rather than assuming it.
Subtracting the region origin makes them local, so a Gen 4 map's objects sit at
the same kind of coordinates a Gen 1–3 map's do and nothing downstream needs to
know the difference.

**Gen 4 is 3D: X and Z are the two horizontal axes and Y is height.** So the
engine's `y` takes the cartridge's `z`, and the cartridge's `y` becomes
elevation. Reading them in the order they appear puts every object on the map's
top edge.

Attached: 3,555 objects, 1,213 warps, 682 signs, 186 triggers. Warp
destinations are resolved from header id to internal map name at extraction, so
no two consumers can resolve them differently — **0 dangling**. 61 events (1.1%)
fall outside their map's bounding box, all of them in the four L-shaped
regions; they are counted and kept rather than dropped, because a strict bounds
test would silently delete real NPCs.

**Verified by looking.** Rendering Jubilife's cropped grid with its events
overlaid puts every NPC on walkable ground, every warp on a building entrance,
and the triggers along the map edges where route transitions belong. A wrong
axis or a wrong origin would put them inside buildings.

### One size trap, caught by measuring

The first version inlined each map's grid into its def and the cache came to
**33.75 MB**. The twelve headers that name the overworld *without* claiming
chunks in it were each carrying the full 1.76 MB layout — 21 MB of one grid
repeated. A def now inlines `blocks` only when it owns that grid (it was
cropped, or no other header uses that matrix) and otherwise references
`layout`. **33.75 MB → 1.55 MB**, with 302 maps owning a grid and 291
referencing a shared one.

---

### Naming the ground: tile behaviours

A Platinum permission cell is one `u16` — bit 15 says the cell is not part of
the map, and the **low byte is a behaviour**. Nothing in the cartridge says what
those 256 values mean, and only 75 of them ever occur, so colouring them by
value would have been guesswork dressed as data.

pokeplatinum names all 256 and ships a flag table with them.
`src/import/Gen4Behaviors.lua` carries both. Two checks that make it more than
a transcription:

* **All 75 behaviours that occur in this cartridge have a real name — zero land
  on an `UNUSED_xNN` slot.** A single off-by-one in the enum ordering would
  have broken that, so it is the ordering's proof as well as the table's.
* The flags matter more than the names, and are not derivable from them: the
  cartridge marks six `UNUSED` behaviours as encounter tiles and eight as
  surfable. Both come from `sTileBehaviorFlags`, not from reading names.

Weighted by cells: **21.2% of walkable ground can start a wild battle, 12.1% is
surfable.** Grass is 4 behaviours, encounters 19, surfable 16, jumps 8 (with
direction), doors 1, warps 11.

### A stand-in tileset, so a map can be built at all

Gen 4's world is 3D — an NSBMD mesh and a texture set per chunk — and there is
no tileset in the Gen 1–3 sense anywhere in the cartridge. `MapLoader` pairs
every map def with one regardless, so until the mesh pipeline exists a Platinum
map could not be **built**, never mind drawn.

`src/import/Gen4Tileset.lua` synthesises one: a flat colour per terrain class,
keyed by the behaviour byte every cell already carries.

**It is shaped like a Gen 3 tileset, and that is the whole trick.**
`TileRenderer.gen3SheetsFor` takes any tileset whose `blockTiles` is 2 and hands
it to `Gen3Tiles`, which reads four plain binaries — 4bpp `tiles`, 16-byte
`metatiles`, 2-byte `attributes`, a `palettes` array. Producing those four is
cheaper than teaching the renderer a fifth kind of map, so **a Gen 4 map now
takes the same code path Hoenn does, with no renderer change at all.** Two
records are written, exactly as Gen 3 writes: the raw tileset in
`map_tilesets`, the pair record a def names in `tilesets`.

256 metatiles, one per behaviour, so a metatile's `attributes` behaviour *is*
its own index — which is what makes `behaviourBytes` true here and lets
everything that asks a cell what kind of ground it is keep working. Two
palettes, base and darkened, checkered across each metatile's four tiles, so
the 16-pixel grid has a visible edge rather than reading as a silhouette.

**Anything unclassified draws magenta on purpose.** The first pass left 0.50%
of cells magenta — but nearly all of them were *named* things the rules simply
did not cover: `BIKE_BRIDGE_*`, `SLIDE_*`, `REFLECTIVE`,
`DYNAMIC_HEIGHT_COLLISION`, `PASTORIA_GYM_*_GROUND`, `MART_SHELF_1`. Adding
those rules is reading, not guessing, and it took magenta down to **14 cells in
346,819 — 0.004%, every one a value the cartridge itself calls `UNKNOWN_xNN`.**
Magenta now means genuinely unknown rather than "no rule written yet".

Cell-weighted census of Sinnoh: ground 74.9%, water 12.1%, cave 4.7%, grass
3.2%, snow 1.5%, mud 1.2%, sand 0.7%, bridge 0.6%, shallow 0.5%, ice 0.25%,
door 0.23%. The water figure lands on 12.07% against the 12.1% of cells the
flag table calls surfable — two independent routes to the same number.

**Verified through the engine's own compositor.** `Gen3Tiles` was run against
the synthesised record directly: it reports 256 metatiles, resolves behaviour 2
to the grass tile, 21 to water, 105 to the door colour and 56 to the ledge
colour, and bakes a 256×256 sheet in 30 colours (15 classes × 2 palettes).
Jubilife then renders from its own map def through that sheet — street grid,
building footprints, orange doorways — and all **593 map defs resolve a tileset
with 0 failures**.

**What this is not:** an attempt at Platinum's art. It draws a legible plan, not
Sinnoh. The value is that the map, its collision, its warps and its NPCs can all
be exercised while the mesh pipeline is still missing.

---

### The real reason nothing runs: the cache spoke the wrong names

Every "Running: No" row in the tracker below had **one shared cause**, and it
was not in the extraction at all.

`src/core/Data.lua` requires its modules by exact name — `constants`, `maps`,
`tilesets`, `text`, `text_pointers`, `pokemon`, `moves`, `items`, `type_chart`,
`trainers`, `encounters` — and the Gen 4 extractor was writing `gen4_species`,
`gen4_moves`, `gen4_maps` and the rest. **Of the eleven modules Data requires,
a Gen 4 cache provided one.** An import would have died at the first module
check with "missing generated data module 'data/generated/constants.lua'",
before a single byte of all that verified extraction was read.

`data.constants.gen` alone is read in **seventy-one places**. It is the value
the whole engine branches on.

Seven tables were renames — the shapes already matched, because they were built
to the engine's shape from the start. Four were genuinely missing:

* **`constants`** — `gen = 4`, the eighteen type names, the twenty-five
  natures, and the id-order lists. Types come from **message bank 624** and
  natures from **bank 202**, both found by searching the banks rather than
  assumed, which is also how the type *numbering* was established: bank 624 is
  exactly `NORMAL … DARK` with the unused `???` at slot 9. Leaving that slot
  out would shift every type above it.
* **`type_chart`** — see below.
* **`text`** — the same 46,053 strings, flat, keyed `TEXT_B<bank>_<index>`.
  Gen 1–3 address a string by one id; Gen 4 needs a bank and an index, so the
  label carries both. `Gen4Text.label` owns the spelling so the writer and
  whatever lowers a `message` command cannot drift — the same discipline the
  script labels already use.
* **`text_pointers`** — required by `Data.lua` and read by nothing. Written
  empty, because Gen 4 has no equivalent and inventing entries would put names
  in the cache that resolve to nothing.

### The type chart has two terminators

It is not an 18×18 grid but a list of exceptions — attacker, defender,
multiplier in tenths — and everything unlisted is 1×. It lives in **overlay
16**, the battle overlay, *not* the ARM9; a search that only looks there comes
back empty.

**108 rows, then `0xFE`, then two more rows — Normal vs Ghost and Fighting vs
Ghost, both immune — then `0xFF`.** The game's own damage routine loops until
`0xFF` and applies all 110; other code stops at `0xFE` deliberately, because
those last two are the immunities Foresight and Scrappy lift. A reader that
stops at the first terminator produces a chart in which **Normal does neutral
damage to Ghost** — nothing errors, the game is just wrong in a way that takes
a battle to notice.

**A bug in my own search, worth recording.** The first version walked forward
and returned the first position that started a long enough run. That is wrong
twice: a coincidental triple just before the table can start a run one byte out
of phase, and skipping past a short run can step *over* the true start. It
locked onto 0x33B97 instead of 0x33B94 — row **two** — silently dropping
"normal vs rock, half damage" and reporting 109 rows. No count would have
caught that without knowing the answer first. The fix is to keep the **longest**
run and then extend it backward while the preceding triple is also valid, which
makes the answer independent of where the scan happened to lock on.

Verified against known matchups: fire→grass 2×, water→fire 2×, electric→ground
0×, normal→ghost 0×, ghost→normal 0×, dragon→dragon 2×, fighting→dark 2×. And
exactly one binary in the whole cartridge carries a table of that shape.

### Where the boot now stands

All **11 SHARED modules are present**. What remains is that `Data.lua` has no
Gen 4 branch: it detects Gen 3 by the presence of `save_layout` and otherwise
assumes Gen 1/2, so a Gen 4 cache is asked for `trainer_headers`, `sprites`,
`field` and `battle_anims` — four Gen 1/2-shaped modules it has no business
having.

That change is **deliberately not made yet**. It edits the module lists every
generation boots through, and unlike everything above it cannot be checked
offline — the constraint that Gen 4 work must not break Crystal, Gold, Silver
or Prism applies most sharply to exactly this file. It wants a `GEN4_MODULES`
list and a marker (`gen4_map_headers` is written by the Gen 4 extractor and
nothing else), made with the engine in front of you.

---

### The Gen 4 branch in `Data.lua`, and how it was proven safe

`Data.requiredModules` decides which module set a cache must provide. It knew
two answers — Gen 3 if `save_layout` loads, Gen 1/2 otherwise — so a Platinum
cache was being asked for `trainer_headers`, `sprites`, `field` and
`battle_anims`, four Gen 1/2-shaped modules it has no business having.

The change adds a `GEN4_MODULES` list and a third answer. What is in it is
short, because a Gen 4 map def carries its own grid, warps and objects:
`map_layouts`, `map_tilesets`, `map_scripts`, `font`. What is *not* in it
matters as much:

* **`save_layout` is deliberately absent.** It is the Gen 3 marker, and writing
  one would make a Gen 4 cache claim to be Gen 3.
* `sprites`, `icons`, `scenes`, `songs`, `audio` are stages the Gen 4 extractor
  does not have yet, and requiring a file nothing writes would refuse every
  import. They sit in `OPTIONAL`, so a cache that gains one later picks it up
  with no change here.

A Gen 4 cache is also **blocked from the `CLASSIC_ONLY` modules**, exactly as a
Gen 3 one is and for the same reason: the version overlay is additive, so any
module Platinum did not write still resolves — to the root cache, which is
Red's. That is how NEW GAME on Emerald once opened Red's intro in Red's house,
and Gen 4 writes fewer of these than Gen 3 does.

**This file is every generation's boot path, so it was not changed on
judgement.** Both the old and the new `requiredModules` were extracted and run
against four synthetic caches:

| Cache | Old | New | |
|---|---|---|---|
| no marker (Gen 1/2) | gen3=false, 16 modules | gen3=false gen4=false, 16 modules | **identical** |
| `save_layout` (Gen 3) | gen3=true, 22 modules | gen3=true gen4=false, 22 modules | **identical** |
| `gen4_map_headers` | gen3=false, 16 modules | gen4=true, 15 modules | changed, as intended |
| both markers | gen3=true | gen4=true | gen4 wins |

**Crystal, Gold, Silver, Prism and Polished Crystal take the first row;
Emerald and FireRed take the second. Both are byte-identical to before.** The
only behaviour that changed belongs to caches carrying a marker no existing
cache has. (The fourth row cannot occur — the Gen 4 extractor does not write
`save_layout` — and is listed because a precedence that is never exercised
should still be a decision rather than an accident.)

Run against the real thing: the cache writes **23 tables**, is detected as
gen4, and satisfies all **15 required modules with 0 missing**.

---

### The overworld NPCs did not need the 3D pipeline

`mmodel.narc` reads as a wall. Gen 4's overworld is 3D, so the people in it
must be models, and models mean NSBMD, a mesh pipeline and a long detour.

**They are not models.** 421 of its 470 members are **BTX0 — Nitro *texture*
archives** — and only 24 are BMD0. A Gen 4 NPC is a flat quad wearing a
texture: the geometry is shared and the per-character art is a texture set. The
member names say so outright — `youngster.nsbtx`, `lass.nsbtx`, `hiker.nsbtx`.

> **This paragraph used to end "…and every object event in the map defs already
> carries a `graphicsId` that indexes this archive."** It does not index this
> archive, and believing it meant that not one of the 3,555 map objects was
> drawing its own art. See *The lookup that could not miss*.

So the entire overworld cast comes out by reading textures, and the mesh work
is not on the path to it.

**What a texture entry says.** Eight bytes: `{ u32 texImageParam, u32
extraParam }`. The parameter is the **first** word — offset in bits 0–15 (in
units of 8 bytes), width and height exponents in bits 20–25, format in 26–28,
colour-0-transparency in bit 29.

> **This section previously said the second word, and everything that followed
> from that is corrected below.** The full account is in *The dictionary that
> was only right for two* further down; the short version is that the reader
> was *also* four bytes short of the records, and on a two-texture member the
> two errors cancel exactly. 208 of the 421 texture members have two textures,
> which was enough to make the pair look right and to make every claim about
> "empty slots", exotic formats and enormous reserved regions below it false.

Counted over all 3,567 entries, once both were fixed: **3,564 are format 3 (16
colours) and 3 are format 2 (4 colours)**. That is the entire list. This
archive holds nothing but paletted sprite frames — no A3I5, no A5I3, no 4x4
block compression, and not one empty slot. The other formats are still
**reported, not silently skipped**, in case a mod adds one.

**A member is not only its character** — but it is much closer to it than this
document used to claim. Frame sizes across the archive are 32×32 (3,158),
16×32 (385), 64×64 (9), 16×16 (7), 64×32 (5), 128×64 (2) and 128×32 (1). A
member holds 1, 2, 3, 4, 7, 12, 13, 16, 17, 24 or 32 frames: **16 for a
standard NPC, 32 for the player, 1 for an item ball.** The strip is still
built from the **modal frame size** — whichever size the most decodable
textures in that member agree on — because a member can legitimately mix sizes,
but it is no longer separating art from reserved space, because there is no
reserved space.

Result: **421 sprite sets, 3,567 frames** — every `BTX0` member in the archive,
none skipped, nothing undecodable.

Two small things worth keeping, because both were caught by a number looking
wrong rather than by an error: `2^n` in Lua is a **float**, so every size
reported as `32.0x32.0` and any key built from it failed to match the integer
one a caller would write. And the palette dictionary's offsets *appeared* to
read implausibly — one entry claiming 3,064 bytes into a 32-byte region — which
was the same records bug; with it fixed, all 618 palette entries land inside
their own region. The range check stays as a cheap guard that now never fires,
rather than as the thing doing the work.

---

### Publishing the sprites, and the bug that would not have errored

`data.sprites` is a flat map of key to sheet in every generation, and a Gen 3
entry carries exactly the fields a Gen 4 one needs — `image`, `frames`,
`frameWidth`, `frameHeight`, `walker`, `trueColor`. So the sheets publish under
that name with no Gen 4 spelling, and map objects gain a `sprite` key derived
from their `graphicsId` the way Gen 3 derives `SPRITE_G3_026` from 26. Both the
sprite table and the objects pointing into it come from one
`RomExtractorGen4.spriteKey`, so they cannot drift.

`trueColor` is true because these are real colours from the cartridge's own
palettes rather than a four-shade Game Boy set the renderer has to map — it is
what makes `SpriteRenderer` use the PNG as it is.

**Frames stack downward, not across.** `SpriteRenderer` cuts frame *f* with
`newQuad(0, f * frameHeight, ...)`, so a sheet is a **column**. A horizontal
strip is the obvious thing to build and it would have loaded without
complaint — every quad lands inside the image — but every frame after the first
would then be cut out of empty space beside the strip, so an NPC would stand
correctly and **vanish the moment it took a step**. Gen 3's own sheets are 16
wide and 288 tall for exactly this reason; Gen 4's are the same shape, 32×512
for a standard NPC and 32×1024 for the player.

`walker` is `true` only when a member has more than one frame, so the fifteen
single-frame props — the item ball, the cut tree, the boulder — are not handed
to the renderer as a walk cycle with nothing to step through.

Result: **421 sprite entries, and 3,555 of 3,555 map objects resolve one.**

---

### The dictionary that was only right for two

Everything above about the overworld archive was written from a reader with two
compensating off-by-four errors, and the compensation held on exactly the
members common enough to make it look correct. This is the account, because the
wrong version was published and because the shape of the mistake is worth more
than the fix.

**The structure.** A Nitro 3D dictionary is a 4-byte header, an 8-byte block, a
4-byte patricia node per entry, and then a 4-byte sub-header holding
`{ u16 sizeUnit, u16 namesOffset }`. The fixed-size records start immediately
after that sub-header. `namesOffset` is measured **from the sub-header**, and it
points at the **names**, not at the records.

**The two errors.** The reader derived the records from `namesOffset` measured
from the *dictionary* start, which puts them at `base + 4 + n·unit` instead of
`base + 16 + 4n`. And it then read `texImageParam` from the record's *second*
word instead of its first. Set the two equal and they cancel when

```
n·(unit − 4) = 12      →   with unit = 8, n = 2
```

**208 of mmodel's 421 texture members have exactly two textures.** On every one
of them the pair of errors produced byte-identical, entirely correct output. On
everything else it read the middle of a name, or a patricia node, or the next
record, and called the result a texture.

**How it announced itself — and how it didn't.** It never errored. It produced
plausible-looking data: sizes of 8×8 and 1024×512, a format field of 0, blank
names. Each of those was then written into this document as a fact about the
cartridge — "621 empty slots", "181 A3I5", "82 4x4-compressed", "120 of 120
large slots decode to fully transparent", "nine 32×32 frames per NPC". Every one
of those was a misread, and the transparency measurement in particular is a
caution worth keeping: **decoding a region that is not texture data and finding
it blank is not evidence that the region is blank.** It is what you should
expect.

The thread that led back to it was not any of those numbers. It was
`pokeball.nsbtx` — 308 bytes, present in the archive, clearly not empty — sitting
under a claim that its art "is not in `mmodel.narc` at all". A 308-byte file
that the reader says holds one 8×8 texture of format 0 is a file the reader is
wrong about.

**The check that settles it.** For each member, decode every texture entry under
both readings and ask whether *all* of them come out as a format this decoder
handles:

| textures in member | members | old reading OK | new reading OK |
|---:|---:|---:|---:|
| 1 | 15 | 0 | 15 |
| 2 | 208 | **208** | 208 |
| 3 | 1 | 0 | 1 |
| 4 | 5 | 4 | 5 |
| 7 | 2 | 0 | 2 |
| 12 | 4 | 1 | 4 |
| 13 | 2 | 0 | 2 |
| 16 | **177** | **4** | 177 |
| 17 | 1 | 0 | 1 |
| 24 | 2 | 0 | 2 |
| 32 | 4 | 0 | 4 |
| **total** | **421** | **217** | **421** |

The `n = 2` row is the whole story: perfect under both, and half the archive.

**What changed in the output.** 208 members decode byte-identically, 192
decode differently, 21 appear that did not exist before, and none was lost.
**1,310 frames the old reader never produced** — a standard NPC went from nine
frames to sixteen, the player from nine to thirty-two.

And the eleven "missing" field objects were never missing. Their texture names
match pokeplatinum's `field_sprites.order` basenames exactly, which is
independent confirmation that the new reading is right rather than merely
different:

| object | member | decoded | texture name | pokeplatinum basename |
|---|---:|---|---|---|
| `strength_boulder` | 82 | 16×16, 1 frame | `rock` | `rock` |
| `rock_smash` | 83 | 16×16, 1 frame | `breakrock` | `breakrock` |
| `cut_tree` | 84 | 32×32, 1 frame | `tree` | `tree` |
| `pokeball` | 85 | 16×16, 1 frame | `monstarball` | `monstarball` |
| `surf_wake` | 89 | 32×96, 3 frames | `shibuki.1`–`.3` | — |
| `briefcase` | 153 | 32×32, 1 frame | `bag` | `bag` |
| `vent` | 161 | 32×32, 1 frame | `venthole` | `venthole` |
| `regigigas` | 162 | 64×64, 1 frame | `sppoke12` | `sppoke12` |
| `moss_rock` | 168 | 16×16, 1 frame | `moss` | `moss` |
| `ice_rock` | 169 | 16×16, 1 frame | `freezes` | `freezes` |
| `bollard` | 170 | 32×32, 1 frame | `pole` | `pole` |

`build_model.narc` — the place this document said to look next — turned out to
hold doors, counters, stairs and furniture, and nothing on that list. The
search for where the art lived was the right instinct aimed at the wrong
question: the art was where the names said it was, and the reader was lying
about it.

**The rule this leaves behind.** A parser that is wrong only for some inputs
will be validated against whichever inputs are commonest, and two-thirds of
this archive's members are its most-common shape. Checking that *every* member
of a corpus parses — not that a sample renders — is what found it, and the
"all entries decodable" test above is cheap enough to keep.

---

### Species pictures, and the sixteen with no male sheet

`pl_pokegra.narc` is 2,964 members: **494 species slots of six**, in the order
pokeplatinum's own packer writes them (`tools/scripts/make_pl_pokegra.py`,
`for face in back, front / for gender in female, male`):

```
+0 back female   +1 back male   +2 front female   +3 front male
+4 normal palette (NCLR)        +5 shiny palette (NCLR)
```

Positional, with no name table — `pl_pokegra` has no `.order` file for
`Gen4Archives` to match — so that ordering is the only thing saying which
member is which, and it comes from the packer rather than from a guess at the
pattern.

**Sixteen species have an empty male slot.** The obvious read is "the male
sheet is the sprite, the female sheet is the optional variant". For a
female-only species it is the other way round, and reading only `+3` leaves
Nidoran♀, Nidorina, Nidoqueen, Chansey, Kangaskhan, Jynx, Smoochum, Miltank,
Blissey, Illumise, Latias, Wormadam, Vespiquen, Happiny, Froslass and Cresselia
**with no picture at all** — and not as an error, because an empty member is a
perfectly legal member. `Gen4Pokegra.sheet` falls back and reports which slot
it used.

A second archive confirms it without being asked to. `height.narc` is 1,976
one-byte members — four per species, same slot order — and for exactly those
sixteen the two *male* bytes are zero-length while the female ones carry real
offsets. Two unrelated archives agreeing on which slot is empty is better
evidence than either alone.

**The pixels are encrypted and not tiled.** Every sheet is 20×10 "tiles" at
4bpp, but the NCGR's layout flag says LINEAR BITMAP — rows of the picture, not
8×8 cells in reading order. Read as tiles it still produces *a* picture: the
right pixels in 8×8 blocks shuffled across the frame, which reads as a palette
bug rather than a layout one. `Gen4Graphics.tiles` already reports `bitmap`,
and the pixels go through `Gen4Graphics.decryptSprite` first.

**20×10 tiles is 160×80, which is two 80×80 frames side by side** — and that is
already the shape `PicAnim` reads, so nothing is restacked. Measured across the
477 species with a male front sheet: 475 have two genuinely different frames, 2
are identical and 2 have an empty second frame. It is a real two-frame
animation, and the shiny strip is decoded a second time through the shiny
palette rather than reusing the normal one — the cartridge loads **one** palette
for the battler and draws every frame through it, and the Gen 3 version of this
stage had the still pic shiny and the animation not, so a shiny lost its colours
for the two frames it was moving.

**The filename carries both the id and the name.** Gen 3 names its files by the
species slug alone, which it can because a Gen 3 row is keyed by a `SPECIES_*`
constant. A Gen 4 row is keyed by its integer id and **the names collide** —
`NIDORAN♀` and `NIDORAN♂` slug identically — so a slug-only path would have one
species quietly overwrite the other's picture. `029_nidoran` and `032_nidoran`
are unique by construction and still readable to whoever writes an override.

**What it writes.** The same field names Gen 3 writes, onto the same species
rows: `spriteFront`, `spriteBack`, `spriteShiny`, `spriteShinyBack`,
`spriteFrontFemale`/`spriteBackFemale` where the female art actually differs,
and `picAnim = { sheet, count, width, height, play, shinySheet }`. `Sprites.path`
reads the first two for every generation and `PicAnim` reads the last, so a Gen
4 spelling of either would mean a generation branch in every screen that draws a
Pokémon.

| | |
|---|---|
| species with a front **and** a back | **493 of 493** |
| reached through the female slot | 32 (16 species × 2 faces) |
| distinct female variants written | 175 (89 front, 86 back) |
| two-frame strips, normal **and** shiny | 493 |
| species missing a picture | **0** |
| images this stage writes | 2,640 |

The 322 species whose female member repeats the male art byte for byte get no
second file; writing it would double the stage's output for nothing.

The `play` pattern — two beats out and back, then a settle — is **this port's,
not the cartridge's**. Platinum times the pair from a per-species animation
script that is not extracted, so the timing is deliberately identical to Gen 3's
rather than invented, so that a Pokémon does not move at one speed in Hoenn and
another in Sinnoh for no reason anyone chose.

---

### The archive with two orderings inside it

`pl_otherpoke.narc` holds the alternate forms, and it is the one piece of this
cartridge's graphics with no pattern at all. pokeplatinum's own build says so
out loud — `otherpoke_index = {} # otherpoke uses a unique, non-uniform
structure` — and the index is assembled from the per-species `meson.build`
files that populate it rather than inferred from the archive.

**The shape**, from `make_pl_otherpoke.py` and the `154`/`94` counts the build
passes it:

```
0..153    sprites  (NCGR), 20×10 tiles at 4bpp — the same shape as pl_pokegra
154..247  palettes (NCLR), 16 colours
248..250  the Substitute doll: back, front, palette
251..252  the in-battle shadows and their palette
```

Checked against the cartridge rather than taken on faith: every member in
0–153 *is* an NCGR of that shape and every member in 154–247 *is* a 16-colour
NCLR — 154 and 94, 0 wrong.

**Two orderings coexist, and neither announces itself.**

| ordering | species |
|---|---|
| **interleaved** — back, front, back, front, one pair per form | Deoxys, Unown, Burmy, Wormadam, Arceus, Shaymin, Rotom, Giratina |
| **grouped** — *every* back, then *every* front | Castform, Shellos, Gastrodon, Cherrim |

Castform's four backs are 64–67 and its four fronts are 68–71. Read as
interleaved, sunny Castform's "back" is rainy Castform's back and its "front" is
base Castform's front: four perfectly plausible pictures, all of the wrong
forms, and nothing anywhere reports an error. The palettes split the same way —
Castform and Cherrim group normal-then-shiny while everyone else alternates — so
the same guess also hands sunny Castform snowy's colours. This is why the index
is a table and not arithmetic.

**Thirty forms have no palette of their own.** Deoxys's three alternate formes
and Unown's twenty-seven letters are drawn through their species' *base*
palette; only the sheets differ. `palette` is nil on those rows and
`Gen4Otherpoke.palettes` falls back to the base form's, returning a `borrowed`
flag so a record can say so rather than imply the form has its own.

**The egg is not a Pokémon here.** Members 132/133 are the ordinary egg and the
Manaphy egg — a front picture and a normal palette each, no back and no shiny,
because an egg is never sent out and never sparkles. They carry `species = 0`.

Every `base` form duplicates what `pl_pokegra` already holds for that species.
That is the cartridge's doing, not a mistake: the form-switching code reads one
archive rather than two.

| | |
|---|---|
| form records written | **78**, across 12 species |
| images | 463 |
| forms borrowing the base palette | 30 (Deoxys ×3, Unown ×27) |
| forms with a two-frame strip | 78 (76 also in shiny — the two eggs have none) |
| forms with a back picture | 76 (the two eggs have none) |
| species rows carrying `.forms` | 12 |

Plus the three that belong to no species: the Substitute doll's front and back,
and the in-battle shadow sheet. Both are wanted the moment a battle runs — the
doll as soon as something uses Substitute, the shadow under every battler.

Verified by looking at all 78: Castform's four weathers are the right four
colours, Shellos and Gastrodon are pink and blue the right way round, Cherrim is
closed then open, Arceus's eighteen plates each recolour correctly, Unown's
twenty-eight letters are twenty-eight distinct shapes sharing one palette, and
Rotom's five appliances are five appliances. The four grouped species are
exactly the ones a wrong reading would have scrambled, which is what makes
looking at them the test rather than a formality.

---

### Thirty bands, and the lookup that could not miss

Two things were settled at once here, and neither would have been settled alone.

#### What a script id means

The old note in this file said 2,148 events carried an id past the end of their
map's script list, called them `special`, and stopped: *"what each band means is
not claimed here, because nothing has established it yet."* The cartridge
establishes it. `ScriptContext_LoadAndOffsetID` is a linear scan from the
highest threshold down:

```
if      id >= 10490 -> scratch-off cards,  entry id - 10490
else if id >= 10450 -> frontier records,   entry id - 10450
...
else if id >=  2000 -> common scripts,     entry id - 2000
else if id >=     1 -> THIS MAP's own file, entry id - 1
else                -> the dummy script
```

Thirty bands, each naming a file in `scr_seq.narc` and a text bank. An id in a
band is not special — it is an ordinary entry point in a shared script file.
**1,885 of the 1,920 land inside the file their band names.** The 35 that do
not are all the single value 65535, which is the "no script" sentinel wearing
the top band's clothes.

The battle bands are worth a line of their own: **3000 and 5000 point at the
same file**, and which one an id came through is what tells the engine singles
from the second half of a double. `Script_GetTrainerID` subtracts the band's own
threshold either way, so the trainer number is identical and the *band* carries
the battle kind.

**A bug fell out of writing this.** The link stage kept its unresolved ids in one
table keyed by an object's `localId` *and* by a sign's index — both small
integers — so a sign with index 1 silently replaced the object with `localId` 1.
**228 of 2,148 entries, better than one in ten, were being overwritten**, and
nothing counted them because the count was taken before the write. Objects and
signs have a table each now, and all 2,101 survive.

#### The lookup that could not miss

Classifying the bands made a second table available: what each object *is*. So
cross-tabulate it against what each object is *drawn as*. That table read:

> `berry_tree_interactions` — 118 objects, every one drawn as **Team Galactic's
> Mars**. `mystery_gift_deliveryman` — 13 objects, every one drawn as a
> **blooming Lum berry**. `tv_reporter_interviews` — 12 objects, drawn as
> **Teala**, the Pokémon Centre attendant.

A map object's `graphicsId` **does not index `mmodel.narc`.** It is a key into
`gObjectEventGfxTexturesTable`, a flat list of `{ u32 graphicsID, u32 narcIndex }`
pairs that the field engine searches linearly and that ends at `0xFFFF`. Reading
the id as a member number resolved for every single object — every id in range
names *a* member — and was wrong for all 3,555 of them:

| id | count | what it is | what it was drawing |
|---:|---:|---|---|
| 85 | 591 | `ROCK_SMASH` | `pokeball` |
| 87 | 331 | `POKEBALL` | `unused_woman_1` |
| 27 | 101 | `TEALA` | `scientist_m` |
| 124 | 77 | `GRUNT_M` | `mira` |
| 84 | 50 | `STRENGTH_BOULDER` | `cut_tree` |
| 86 | 49 | `CUT_TREE` | `unused_woman_0` |

**Zero of 3,555 objects had the right art**, and the earlier line in this
document — "3,555 of 3,555 map objects resolve one" — was not evidence of
anything. A lookup that cannot miss cannot tell you it is wrong.

**The table is read from the cartridge**, not transcribed: found by its own
shape, 441 rows at overlay 5 + 0x2BC34, matching pokeplatinum's table row for
row. Only the *names* come from pret. Finding it took three attempts and each
failure is worth keeping:

1. **First match is the wrong match.** The same overlay holds
   `gObjectEventGfxModelsTable`, identical row shape, also starting at id 0, and
   it sits *earlier*. A first-match scan returns 18 rows instead of 441 and
   answers every id it knows with a member from the wrong archive. This is the
   second time in this project a first-match scan locked onto the wrong run —
   the type chart did it too.
2. **Longest match is not enough either.** The table maps `gfx1`–`gfx6` to
   members 0–5, so reading it twelve bytes late — one column out — *also* sees
   `0,1,2,3,4,5` ascending at a stride of eight, and then runs 1,320 rows past
   the end because the real terminator is in the other column.
3. **An invariant separates them, but only the right invariant.** The second
   column is an `mmodel.narc` member index, so every value must be in range for
   that archive; read one column late it is the next row's `graphicsId`, and the
   berry ids (4096+) are far out of range. The obvious companion check — that
   the ids ascend — *rejects the real table*, because the berry block is spliced
   into the middle rather than appended and the run breaks three times. An
   invariant that is almost true is worse than none: it throws away the right
   answer and keeps a plausible wrong one.

**An id with no row is not a missing sprite.** 427 objects carry one and they
are objects with no billboard of their own, recorded with a reason rather than
as a failure:

| reason | objects | what they are |
|---|---:|---|
| `signpost` | 212 | signboards, arrow signs, gym signs — part of the map |
| `berry_soil` | 118 | the planting spot; what grows on it is a berry id above 4095 |
| `runtime_variable` | 62 | `VAR_0`–`VAR_C`, substituted at run time exactly as Gen 2 substitutes its `$F0+` sprites |
| `map_prop` | 35 | the Snowpoint snowball, the Elite Four doors, a readable book, the wall across Rotom's room |

After the fix: **3,128 resolved, 427 no-billboard-by-design, 0 broken** — and
the cross-tabulation now reads the way it should.

| band | objects | the art they wear |
|---|---:|---|
| `field_moves` | 688 | `rock_smash` ×590, `strength_boulder` ×49, `cut_tree` ×49 |
| `visible_items` | 329 | `pokeball` ×329 |
| `berry_tree_interactions` | 118 | `berry_soil` ×118 |
| `pokemon_center_2f_common` | 54 | `teala` ×54 |
| `mystery_gift_deliveryman` | 13 | `mystery_gift_deliveryman` ×13 |
| `tv_reporter_interviews` | 12 | `reporter` ×12 |
| `follower_partners` | 4 | `cheryl`, `marley`, `buck` — the three dungeon partners |
| `day_care_common` | 2 | `expert_m`, `expert_f` — the Day Care couple |

Each of those is two independent tables agreeing. That is the check; one table
looking plausible never was.

---

### What is in the balls, and under the ground

591 of the map's events are a pickup, and the cache recorded only that they had
a script. The item each one holds is knowable — and the two kinds are knowable
in completely different ways, which is the whole content of this.

**A visible item carries its item in the script.** Id `7000+n` reaches entry `n`
of `scripts_visible_items`, and every entry is the same three instructions:

```
setvarfromvalue 0x8008, <item id>
setvarfromvalue 0x8009, <quantity>
goto <the shared pick-up-a-ball routine>
```

327 of that file's 328 entries are exactly that; the odd one out is the last.
Every quantity in the game is 1.

**A hidden item does not.** All 284 entries of `scripts_hidden_items` point at
**one offset** — they are literally the same routine 284 times — and it reads
its item out of script variables the engine fills in beforehand. Those come
from `gHiddenItems` in the ARM9: 257 rows of

```
u16 item, u8 quantity, u8 searchRange, u16 padding (always 0), u16 script
```

**searched by `script == id - 8000`, not indexed by it.** The script numbers are
derived from flag ids and are not consecutive, so a lookup by row position is
wrong for most of the table.

Both tables are read from the cartridge. The hidden one is found by shape —
and the padding halfword is what finds it, because two zero bytes in the middle
of every row is not what code or a string table looks like. Measured: the same
address comes back with the item ceiling anywhere from 468 to 65535, so the
shape identifies it and the ceiling is only a bound.

**Which is exactly where this went wrong once.** Bounding the item id by
`pl_item_data.narc`'s member count looks like the careful choice — use the
cartridge's own number rather than a magic constant — and it is wrong. The data
archive has **446** members and item ids run past it; the real table holds one
of **451**. So the run breaks in the middle, the finder returns **216 rows
instead of 257**, and 41 hidden items vanish with no error anywhere. The item
*name* bank (468) is the id space; a plain large bound is safer still. Third
time in this document that an invariant which is *almost* true did more damage
than no invariant at all.

| | |
|---|---:|
| item balls resolved | **329 of 329** |
| hidden items resolved | **262 of 262** |
| maps holding at least one | 140 |
| commonest | Rare Candy ×32, Ultra Ball ×30, Star Piece ×20 |

Spot-checking against the game rather than against the tables: Route 228 comes
out holding PP Max, Protector, Shiny Stone, Shed Shell and TM37, and the water
route W220 holds a Splash Plate. Those are the right items on the right routes.

---

### The trainer field that is not the class

Same audit, applied to the 417 map objects whose script id is in a battle band.
The trainer number comes out of the band exactly as the cartridge derives it —
`id − 3000 + 1` or `id − 5000 + 1` — and all **417 land inside the 928-entry
trainer table**. That part was right.

What was not: a trdata header is

```
u8 monDataType, u8 trainerType, u8 sprite, u8 partySize,
u16 items[4], u32 aiMask, u32 battleType
```

and the obvious reading is that `sprite` says which trainer to draw. Measured
across all 928 trainers, **`sprite` is zero for every single one.** The class is
`trainerType` — 102 distinct values in 0–102, against a 105-entry class list —
and the game agrees: `TRDATA_CLASS` reads `trainerType`. Cross-checking the
wrong field made every trainer in Sinnoh a Player (Male).

**The check that says the join is right** is again two tables that know nothing
about each other. Of the 63 trainer classes that appear on a map, **60 are drawn
as exactly one overworld sprite**, and the three that are not are pair classes
fought by two visible people:

| class | drawn as |
|---|---|
| `belle_and_pa` | `rancher` ×2, `cowgirl` ×2 |
| `double_team` | `ace_trainer_f` ×3, `ace_trainer_m` ×3 |
| `young_couple` | `pokemon_breeder_f`, `beauty`, `pokemon_breeder_m`, `guitarist` |

A wrong join does not produce a 60-out-of-63 one-to-one mapping with its
exceptions all being couples.

Map objects now carry `trainer = { id, class, className, name, partySize,
battler }`. `battler` is which half of a double this object is, and it comes
from the **band** rather than from the number, because 3000 and 5000 reach the
same file and only the band tells them apart. Class names come from message bank
**619**, found by looking rather than assumed: it has 105 entries and answers
"Youngster" and "Lass" at 2 and 3, exactly where the class list puts them.

**One thing that looks broken and is not.** Sixteen class names come out as
`₧₦ Trainer`, `₧₦ Breeder`, `₧₦ Ranger`. Those are character codes `0x01E0` and
`0x01E1`, and rendering the two glyphs out of the message font settles what they
are: they draw **`Pĸ`** and **`Mɴ`**, the double-width PK/MN ligature pair, 12
pixels each against 6 for an ordinary letter. The cache is correct and the font
draws the real thing; `₧₦` is only the ASCII stand-in, and it is deliberately
*one character each* so the charmap still round-trips. Do not "fix" it into
`Pokémon` — that changes every measured line width in the game for a difference
no player sees.

---

### The height field, and the two checks that make it believable

A Gen 3 map is flat and its one elevation byte per tile is the whole story. A
Gen 4 map is a mesh: a bridge crosses a path and the two share an (x, z), a
slope rises between two tiles that are both "ground". The `BDHC` block in each
land chunk is the cartridge's own answer, and it is small, self-checking and
independent of the mesh — so it comes out now while the NSBMD does not.

**The layout**, read strictly in file order from `BDHC_LoadHeader` and
`BDHC_PrepareBuffers`:

```
"BDHC"                                            4 bytes
u16 points, normals, constants, plates, strips, access
point    { fx32 x, z }                            8 bytes each
normal   { fx32 x, y, z }                        12 bytes each
constant   fx32                                   4 bytes each
plate    { u16 first, second, normal, constant }  8 bytes each
strip    { fx32 scanline, u16 count, u16 start }  8 bytes each
accessList u16                                    2 bytes each
```

**Check one — the identity test**, because "BDHC" is four bytes and four bytes
is a weak promise: `16 + 8p + 12n + 4c + 8P + 8s + 2a` must equal the declared
block size exactly. **666 of 666 chunks pass**, none empty, none failing. A
layout that is right for most files and wrong for some is the failure mode this
catches, and it catches it per chunk rather than on average.

**Check two — reproduce the cartridge's index and compare it to brute force.**
The game does not test every plate: it binary-searches the strips by scanline,
then tests only the plates in that strip's slice of the access list. That search
is transcribed including its off-by-one shape (on the "go higher" branch it
answers `mid + 1`), because reproducing the *search* rather than the intent is
the point — if the cartridge picks strip *n*, an extractor that picks *n−1*
disagrees with the game about where the ground is. Then: sample 56,832 points
and compare the strip-indexed answer against testing all 8,974 plates.
**56,830 agree exactly.** The two that differ are points where brute force finds
an extra coincident plate the strip does not name, and the height is the same
either way. That one test exercises the header, all six blocks, the fixed-point
conversion, the plate geometry, the plane equation, the binary search and the
access list at once.

**The units, which the data states rather than the docs.** `fx32` is 1:19:12 —
divide by 4096. A land chunk is 32×32 tiles, and a flat chunk's single plate
spans **−256..256**, so a tile is **16 world units and the chunk is centred on
the origin, not cornered at it**. Measured: 49 of the 54 single-plate chunks
cover all 1,024 of their tiles under exactly that mapping. Getting the origin
wrong first put coverage at 17%.

**And a negative result worth as much as the positives: this is not a
walkability map.** Tiles the permission grid calls void are covered by a plate
**75.6%** of the time; real ground, **72.3%**. That is no correlation at all,
and the reason is in the engine: where no plate covers a point,
`CalculateObjectHeight` returns FALSE and the height is *left alone*. Plates are
the exceptions, not the surface. The permission grid and the height field answer
different questions and neither can be derived from the other — which also means
this was never going to be a cross-check, and saying so is better than quietly
reporting the 72% as if it confirmed something.

| | |
|---|---:|
| chunks with a BDHC | **666 of 666** |
| plates | 8,974 |
| points / normals / constants | 15,464 / 1,275 / 2,227 |
| strips / access-list entries | 3,569 / 24,838 |
| normals that are exactly (0,1,0) | 666 — one flat normal per chunk |
| parse failures | **0** |

Heights come out quantised to multiples of 8 — 8, 16, 32, 48, 64, 80, 96, 112 —
which is what a tile-based game's elevation steps look like, and is the cheapest
sanity check that the fixed-point conversion is right.

### The crash that proved the cache was reading Red's world

The first New Game on an imported Platinum died in `MapLoader.lua:66` with
`unknown map: REDS_HOUSE_2F`. Nothing in the Gen 4 extractor mentions Red's
house, and that is exactly the point.

`Game:bootConfig()` reads `self.data.field.boot` to learn where a new game
starts. The Gen 4 extractor wrote 28 tables and `field` was not one of them.
`Data.lua`'s overlay is **additive**: a module the current cache does not
provide is not an error, it is inherited from the classic data that ships with
the engine. So the boot config resolved, cleanly and silently, to Red's — and
the first thing the engine did with a Platinum cache was ask a Platinum map
registry for a Kanto map name.

This was predicted in writing and still happened. `Data.lua`'s own comment on
the module says `field` is where `boot.startMap` and `boot.screens` live, and
notes that this is how NEW GAME on Emerald once opened Red's intro in Red's
house. `field` had been unblocked from `CLASSIC_ONLY` when Gen 3 learned to
write one; Gen 4 inherited the permission without inheriting the stage. **A
documented trap is not a fixed trap.**

#### Two tables, and the one that anchors the other

Platinum keeps the answer in two ARM9 tables that have to agree.

*Location pairs* — 20-byte records of `{ mapId, x, z, facing, warpId }`,
holding the new-game start and the post-blackout respawn. Searching for the
shape alone found three candidates, then two after the obvious junk was
dropped, and a shape search that returns two answers has told you nothing.

*`sSpawnLocations`* — 16-byte rows mapping a fly/heal destination to its map
and coordinates. Row 0 is Twinleaf Town, which is also where a new game starts
and where the player wakes after a blackout.

So the pairs table is not identified by its own shape at all. It is identified
by **agreeing with row 0 of the other table**: the respawn record must name the
same fly map and the same coordinates that spawn row 0 does. One candidate
survives, and it survives for a reason that is about the cartridge rather than
about the search.

#### Two almost-true rules, one kept and one thrown out

Finding `sSpawnLocations` by longest run of plausible rows landed on a bogus
26-row table at `arm9+0xEA548`. The rule that killed it is a real invariant: a
blackout position has to fall **inside the map definition it names** — every
respawn in this game is indoors (a Pokémon Centre or a bedroom), so each row's
`(x, z)` must sit within its own map's bounds. That is a property of what the
data *means*, and it holds for all 20 real rows.

The rule that had to be thrown out was mine. "First-arrival ids increase down
the table" looked true, matched the first sixteen rows, and truncated the table
to sixteen — row 16's value is 5, after row 15's 17. It was a pattern in the
data, not a constraint on it, and it cost four heal locations.

That is the fourth time this session a nearly-true invariant has been the bug
(the type chart's first terminator, ascending object-graphics ids, the hidden-
item ceiling taken from an archive's size, and now this). The distinction that
matters each time: an invariant derived from *what the field is for* holds; one
derived from *what the values happen to look like* does not.

#### What the stage writes

```
start T01R0202 (4,6) facing up      heal locations 20
boot.startMap    = T01R0202
boot.startFacing = up
boot.lastHeal    = T01R0201 (8,8)
boot.screens.newGame = false
source = ROM:Platinum (locations arm9+0xEA12C, spawns arm9+0xE97B4)
`maps` contains T01R0202 : YES
heal rows with both maps named  : 20 of 20
```

`src/import/Gen4Field.lua` holds the reader; `extractField` is the 29th stage.
The two checks that make the result believable are the cross-table anchor above
and the fact that every map either table names is a map the `maps` stage
independently produced — 20 of 20, with no name invented by the field reader
itself.

#### The half of the fix that is not a fix

An **existing** Platinum cache has no `field.lua` and nothing would make it
re-import: the boot would keep resolving to Red's forever, and the only symptom
is a crash that names a Kanto map. So `"data/generated/field.lua"` is now in
`REQUIRED_FILES_GEN4` in `RomImporter`. It is not one of `Data.lua`'s required
fifteen — it is listed because a *missing* one is invisible rather than fatal,
which is the property that makes it dangerous. Naming it turns an old cache
into a reported gap and an offer to re-import.

The same list had a second hole found on the way in: `requiredFiles` had no Gen
4 case at all and fell through to the Gen 1 list, so a *successful* Platinum
import would report five phantom missing files for ever after.

**Platinum must be re-imported for this to take effect.**

### The title, the card and the menu — and the eighteen tiles that decide them

The second half of the crash report was that nothing appeared: no Platinum
intro, no main menu, no menu graphics behind NEW GAME, CONTINUE or OPTION. The
art for all of it was extracted months of work ago. What did not exist was
anything that drew it — and, underneath that, anything that knew what shape a
Gen 4 window *is*.

#### Boot screens are named data, and Gen 4 named none of them

`Game:init` does not decide which intro or title to show. It reads
`field.boot.screens.splash` and `.title`, and `Data.lua` overrides each one only
while it still equals the default — Gen 2 takes `Gen2Intro`, Gen 3 takes
`Gen3Title`, and a generation that names nothing keeps **Red's**. That is the
same additive-overlay failure as the start map, one field along, and the fix is
the same shape: the field stage now writes

```
screens = { splash = "Gen4Intro", title = "Gen4Title", newGame = false }
```

Every override in `seedDefaults` is guarded by `== BOOT_DEFAULTS.screens.x`, so
a value stated here is left alone by all of them. `newGame = false` stays
deliberate: `OakSpeech` replays a professor's intro out of text Platinum does
not have, and Platinum's own opening is Rowan's, which is a script on the intro
map rather than a screen.

#### The frame is eighteen tiles and the arrangement is not guessable

Everything a menu draws goes through `Font.drawBox`, and `Font.drawBox` wants a
frame. Platinum has two kinds in `pl_winframe`:

* **`standard_system` / `standard_field`** — nine tiles, and a genuine
  nine-slice. `DrawStandardWindowFrame` places `+0..+8` row-major with `+4`
  never drawn, because the interior is the window's own text bitmap. That is
  exactly the engine's existing nine-slice contract, so these needed **no new
  drawing code at all** — only the sheet composed three tiles across instead of
  eight, which is the same pixels at a different stride.
* **`message_box_00` … `19`** — eighteen tiles each, with their own palette
  each, and **not** a 3×3.

Eighteen reads equally well two ways. As 3 wide by 6 tall it is two stacked
frames; as 6 wide by 3 tall it is one frame with fat caps. **Both draw a
rectangle.** Rendered at three across, the result is a plausible tall box with a
brown smear down its middle — the kind of output that gets accepted because it
is not obviously broken.

It is 6×3, and the cartridge says so outright rather than leaving it to be
inferred from what the tiles look like. `DrawMessageBoxFrame` places them
against a window at `(x, y)` sized `(width, height)`:

```
row y-1        +0 at x-2   +1 at x-1   +2 across width   +3 +4 +5 at x+width..+2
rows y..y+h-1  +6 at x-2   +7 at x-1   [window content]  +9 +10 +11
row y+height   +12 +13     +14 across width              +15 +16 +17
```

One rule for all three rows: row bases 0, 6, 12, and within a row the columns
are `+0, +1, +2` repeated, `+3, +4, +5`. The caps are **unequal** — two tiles
left, three right — which is why it reaches past both sides of the box and why
no symmetric reading of it is right.

`+8`, the middle row's repeating tile, is the one member of the eighteen the
cartridge never places, because the window's text bitmap covers exactly that
region. This engine draws text straight onto the box, so it *does* place that
tile and gets the same picture. It is also the only solid tile in the sheet,
which makes it the honest place to read the interior colour from for a box too
narrow to have a middle.

A first pass here also produced a *wrong* invariant worth recording: measuring
whether the four "middle" tiles of each frame were identical, 19 of 20 said no —
which looked like proof the frame was **not** a nine-slice. It was proof the
grid was six wide, not three. **A test that rejects your hypothesis has not
told you which of your assumptions it rejected.**

Both records go into `data.font`, which is the table `Font.lua` already reads:

```
frames        = { image, count = 2,  cell = 24, tile = 8 }
dialogueFrame = { image, count = 20, tiles = 18, layout = "gen4", fill }
```

`Font.lua` gained one guarded branch. Its existing dialogue reader is FireRed's
— five-tile rows mirrored back down — so a Gen 4 strip run through it would draw
a box that is merely wrong instead of failing; `layout = "gen4"` is what stops
that, and the quad builder now indexes one row per frame, which for FireRed's
single-frame strip is bit-for-bit what it built before. Nothing on the Gen 1, 2
or 3 path changes. **The payoff is that every box in the game is Platinum's in
one step** — menus, choice boxes and dialogue — instead of twenty screens each
drawing their own slightly different rectangle.

#### The menu is the cartridge's, including its numbers and its words

`main_menu.c` states the layout outright and it is transcribed rather than
eyeballed: options are windows at **x = 3, width 26 tiles**, the first at
**y = 1**, each next one `height + 2` below ("Add 2 to account for the window
border"), `height` being `TEXT_LINES_TILES(n)` = `n × 2`. CONTINUE is five lines
because it carries the save summary *inside its own window* rather than opening
a panel; everything else is one. Labels sit 32 px in, values right-aligned to
the same 32 px — one constant, `CONTINUE_WINDOW_MARGIN`, used on both sides.

The words come from **message bank 550**, read out of this cartridge and
confirmed entry by entry: 21 strings, 0 = CONTINUE, 1 = NEW GAME, 12 = PLAYER,
13 = TIME, 14 = POKéDEX, 15 = BADGES — exactly the order
`sOptions` and `sContinueOptionStringsIDs` expect. The NEW GAME warning
("there is already another saved game file") is bank 14 entry 5.

Two honest departures, both marked in the data rather than buried in the screen:

* **Six of Platinum's eight rows are not offered** — Mystery Gift, the Ranger
  link, GBA migration, both Wii rows and the Wi-Fi settings. None of them can do
  anything here, and a row that does nothing is worse than a row that is absent.
* **OPTION is this engine's, not the cartridge's.** On the DS, text speed and
  the message frame live in the in-game START menu, so a player who has not
  started a game cannot reach them. Every other title this engine boots offers
  the row; the record says `fromCartridge = false` so it cannot later be
  mistaken for extracted data. EXIT GAME is the launcher's, on the same terms.

The dex row is **skipped, not blanked**, the way `RenderContinueOption`
`continue`s past it — so the summary is four rows or three, never four with a
hole.

#### Where the artwork actually is

The title archive's sheets are 256×192 or 256×256 and mostly empty. Drawn at
0,0 on the sheet size, the logo lands forty rows low and "VERSION" is cut off at
the screen seam — which looks like a layout choice rather than a measurement
nobody took. So the menus stage measures each picture's content box off the
composed pixels:

| | content box |
|---|---|
| `logo` | x 15, y 27, 225 × 122 |
| `copyright` | x 64, y 64, 128 × 56 |
| `gf_presents` | x 5, y 181, 151 × 9 |
| `top_screen_border` | the full 256 × 192 |

Two different kinds of background occur here and only one of them is
transparency: the logo is on a transparent sheet, the copyright is white text on
an **opaque black** 256×256 sheet where alpha finds everything. Treating "fully
transparent **or** exactly the top-left pixel's colour" as background covers
both without the measurer needing to know which kind it has.

`Gen4Title` then splits the screen by what has to fit in each half — the logo's
height above, the copyright block's below, the fourteen spare rows shared — and
centres each in its band. Nothing in the file is a magic number.

#### What the three screens are, and what they are not

* **`Gen4Intro`** — the GAME FREAK card, faded up and away, skippable from the
  first frame. The cartridge's opening is that card, then Giratina turning
  through a portal, then the title; the middle one is `giratina.nsbmd`, a 3D
  model, and there is no 3D path yet. So the card plays and **nothing invents a
  substitute for the portal.** When the mesh pipeline lands it belongs exactly
  here.
* **`Gen4Title`** — `top_screen_border` with the logo faded up on it, the
  copyright block on the dark strip below. A DS title is two panels and this
  engine draws one surface, so the two are composed into one 256×192 screen
  rather than the copyright being dropped; when the second screen exists, the
  file splits along the seam the two borders already mark. "PRESS START" is this
  port's — Platinum simply waits, and a window with no hardware START button has
  to say which key opens the menu.
* **`Gen4MainMenu`** — the rows above, drawn in Platinum's own window frame and
  its own font, with the save summary inside the CONTINUE window.

One detail that would otherwise have read as a font bug: the menu draws its text
at **white, not black**. Platinum's font page is pre-tinted — the sheet bakes the
letter dark and its shadow light — so multiplying it by black, which is what
every Game Boy screen in this engine does because its glyphs are a mask, would
paint the shadow black too and thicken every letter.

`gen4_menus.lua` joins `field.lua` in `REQUIRED_FILES_GEN4`, for the same reason
that one is there: a cache with the boot screens and without the record boots to
a black title with nothing on it, which looks like a broken screen rather than a
missing table.

### OPTIONS, and the row that would have stored the opposite of what you picked

`boot.screens.options` was still the default, so OPTION on the new main menu
opened the **Game Boy** screen: Gen 1's rows, and a FRAME row that cannot reach
Platinum's twenty message boxes. The record now names `Gen4Options`.

The vocabulary is **message bank 220**, read out of this cartridge and checked
entry by entry — 53 strings: 0 = OPTIONS, 3–8 the six row names, 10–21 their
values, 22–41 the twenty frame names spelled out one per entry, 43–48 a
one-line description per row, 52 = "Return to the game."

**The reason this is not the Gen 3 screen with different words** is one line of
`constants/game_options.h`:

```
OPTIONS_SOUND_MODE_STEREO = 0,
OPTIONS_SOUND_MODE_MONO
```

Platinum lists **STEREO first**. Emerald lists MONO first. Reusing Gen 3's row
would have put the right two words on screen in the wrong order, stored the
opposite of what the player chose, and looked completely correct doing it —
there is no symptom until someone notices the sound did not change. BUTTON MODE
differs the same way: Emerald's middle setting is LR, Platinum's is START = X.
Every row's values are the enum's order, not a reading of what looks natural.

Which rows actually bite, stated rather than implied:

| row | what it does here |
|---|---|
| TEXT SPEED / BATTLE SCENE / BATTLE STYLE / SOUND | map onto options this port already honours |
| **FRAME** | **live** — picks one of Platinum's twenty message boxes, which `Font.drawBox` now reads |
| BUTTON MODE | stores all three; only `L = A` bites, because `START = X` is a DS mapping with no counterpart here |

FRAME is the interesting one: it is inert on the Game Boy screens and real
here, because the dialogue-frame work above gave it twenty things to choose
between. It writes `options.gen3Frame` — the field `Font.lua`'s frame chooser
reads on every generation. The name is Gen 3's because that is where the
chooser was written; renaming it would mean editing `Font.lua` for nothing, and
a save carried between cartridges keeping one frame choice is what a player
would expect anyway.

**CONFIRM is extracted and deliberately not offered.** Platinum stages the
changes and applies them when you pick CONFIRM; this engine applies each change
as it is made, the way every other OPTION screen in it does. A CONFIRM row here
would either do nothing or promise a staging model that does not exist. The
strings are kept for the day it does.

**The engine's own rows follow the cartridge's**, through the `ui.options.rows`
hook rather than straight from `buildRows` — the same argument, and the same
bug-avoidance, as the Gen 3 screen. Platinum has no volume sliders, no video
mode, no key bindings and no mod manager; a player on Platinum who could not
reach those would have lost every setting the other versions have because a DS
had no menu for them. Going through the hook is what stops a mod's rows being
present on every version but this one.

### The opening, read out of the cartridge — and four things the log said

Platinum booted, the menus drew, and a New Game opened straight into the
bedroom with no intro at all. Five separate faults, and the running game's own
log named four of them outright.

#### `player sheet: SPRITE_RED -> ninja_boy`

One line, and the most visible bug in the build. With no `field.playerSprites`
the avatar falls back to a **Game Boy sprite id**, which a Gen 4 cache then
resolves through its own sprite table to whatever happens to sit there.
`ninja_boy` is mmodel member 1; the player is member 0. So the hero walked
Sinnoh as a passer-by, and nothing anywhere reported an error — the lookup
succeeded, at the wrong thing.

The field stage now writes both shapes `Player:refreshForm` reads —
`playerSprites` for the default pair and `playerForms[gender]` for the override
the intro's answer selects — for walking, cycling, surfing, fishing and the
Poké Ball pose, for both characters. Found **by name**: `player_m` and
`player_f` are what the object-graphics table calls them, and a name cannot be
off by one the way an id can, which is exactly the mistake being fixed. The
result cross-checks itself: boy 90 / girl 91, bikes 92 / 93, surf 159 / 160 —
adjacent pairs throughout, which is what a hero pair looks like and what a
mis-resolved lookup does not.

#### The opening: a television, then Rowan

`boot.screens.newGame` was `false`, and that was the whole of "New Game has no
intro". OakSpeech replays a professor's intro out of text Platinum does not
have, so there was nothing to put there.

There is now. Two archives, **neither of which has a name table** — ten members
and fifty, none named — so the generic screen planner cannot touch either and
every member index is arithmetic. Arithmetic is the thing this project has been
burned by most, so none of it is inferred: all of it is transcribed from the
cartridge's own loaders (`RowanIntroTv_InitGraphics`,
`RowanIntro_LoadInitialTilemaps` / `_LoadLayer3Tilemap` / `_LoadTilemap`), and
every composed picture is then looked at.

Which caught the television immediately. Its palette is **two loads, and the
picture is in the second one**:

```
Graphics_LoadPalette(..., 6, PAL_LOAD_MAIN_BG, 0, 0, ...)
Graphics_LoadPaletteWithSrcOffset(..., 9, ..., 0x20*2, 0x20*2, 0x20*14, ...)
```

Member 6 fills the whole background palette; member 9 then overwrites colours
32 upwards, and the broadcast is drawn almost entirely out of those. Composed
with member 6 alone it is a black rectangle with coloured noise in it — which
reads as a decoder bug rather than as a half-loaded palette, and would have
sent the next hour into the tile reader. With both loads applied it is a
Sinnoh town under a blue sky, which is what the news report shows.

The set is three background layers, back to front: the broadcast (tiles 8,
tilemap 7, 256-colour), a scanline overlay (2 / 5), and the bezel (1 / 4).
`BG_LAYER_MAIN_2` is initialised and then cleared — it is the CRT band the app
scrolls at run time, not a picture, so there is nothing to extract for it.

Rowan's scene is one tile sheet and five tilemaps for the backdrop, and **ten
figures that are all full-screen pictures rather than sprites**: each is a
(tiles, palette) pair laid out with the *same* tilemap, member 23, which is why
the cartridge's table is a list of pairs and nothing else. They come out as
Rowan, four poses of Lucas, four of Dawn, and Barry — everything the intro
needs, including both characters for the boy-or-girl question.

A figure's palette is loaded into row 7 or 8 and the app then rewrites its
tilemap's cells to point there. Extracting one picture at a time there is no
second layer to keep out of the way, so the sixteen colours are replicated
across every row instead: whatever palette index a cell carries, it lands on
that figure's own colours. Same picture the hardware draws, no cell rewriting.

The script is **bank 389**, 45 entries, checked against every id in
pokeplatinum's own text file — and the page breaks were already in it. Gen 4
writes `0x25BC` for "wait, then clear" and `0x25BD` for "wait, then scroll",
and the decoder renders them as CR and FF, so a page is a split on those
characters rather than something the screen has to count. The television's line
is **bank 607**, one entry.

`Gen4RowanIntro` plays the main line: the greeting, who you are, your name,
your friend's name, the send-off. **CONTROL INFO and ADVENTURE INFO are
extracted and not offered** — they are tutorials about a touch screen and a
+Control Pad this port does not have, and a lecture describing hardware the
player is not holding is worse than one they never saw. Both are in
`gen4_intro` so a mod can put them back.

Gender writes `save.player.gender` **and calls `refreshForm`**, because New Game
pushes the overworld first and this screen on top of it: the Player object
already exists and has already chosen its sheets, so writing the save alone
changes what the *next* one would wear. That is the bug that sent a player who
chose the girl out of the bedroom as the boy on Gen 3, and it is the same bug
here.

#### The black screen was the studio card

"Developed by GAME FREAK inc." occupies rows 181–189 of a 256×192 sheet — the
bottom-left corner — because on the hardware it is the **bottom** screen and
the credit sits under the picture on the top one. Drawn as it stands on one
screen it is a black field with a line of type in the corner, which reads as a
screen that failed to load. It is centred now, using the content box the menus
stage already measures.

#### "The tiles are too small"

The main menu's geometry was the cartridge's and still looked wrong, for a
reason the cartridge never has to think about: its menu is **eight** rows, six
of them link features this port does not offer, and CONTINUE's window alone is
ten tiles. With no save and no link rows the stack is three short windows,
which at the cartridge's own `y = 1` sit in the top third of the screen and
leave the rest empty. The window sizes and spacing are still `main_menu.c`'s;
only where the block starts is this port's.

#### OPTION in the START menu was still Kanto's

The boot record named `Gen4Options`, but **only the main menu reads that
record** — every other call site in the engine hardcodes the Game Boy id, which
is the same gap `GEN3_ALIASES` exists to close. There is now a `GEN4_ALIASES`
beside it, and it has exactly one entry, because Platinum's bag, party screen,
summary pages and trainer card are all *extracted* and none of them has a
screen to draw with yet. Those ids still open the Game Boy ones. Adding an
alias for a screen nobody has written would open a module that is not there.

#### And one thing that was not a bug

"I spawn in a weird area that isn't my bedroom." `T01R0202` **is** the bedroom,
and the map loader put the player on the right tile of it. What is wrong is
that it does not look like one: Gen 4's world is 3D and has no 2D tileset, so
every map is drawn with the synthesised stand-in — one flat colour per terrain
class — and a bedroom floor and a meadow are both "walkable", so both are
green. The map meshes are the fix, and they are still the largest thing
outstanding.

### The mesh reader, and the one number that could not be argued with

"Make sure the starter select box animation and 3D models working" turned out
to be the same job as the map meshes, Giratina on the title, and every field
effect: **Platinum's starter selection is real 3D.** `choose_starter_app.c`
loads six NSBMD models and four NSBCA animations out of
`/graphic/ev_pokeselect.narc` — the briefcase with its opening animation, three
Poké Balls each with their own, and a ground plane — and renders them with the
DS geometry engine. Nothing in this engine could read an NSBMD at all.

`Gen4Models` reads NSBTX, the *texture* archives the overworld sprites turned
out to be, and stops there on the grounds that the sprite question did not need
a mesh pipeline. It did not. Everything else does.

#### Why a display-list decoder cannot be checked by looking at it

A decoder that is subtly wrong does not fail. It emits *some* vertices and
*some* triangles, and the result is a mesh — crumpled, inside out, or missing a
limb, but a mesh. A wrong entry in the command-length table desynchronises the
stream and it keeps decoding, into geometry-shaped garbage. There is no error
to catch and no exception to report.

The cartridge settles it. Every model header states **`numVertex`,
`numPolygon`, `numTriangle` and `numQuad` outright**, and not one of those
numbers is used to decode anything — they are the file saying what a correct
decoder should have found. So the test is exact equality on all four, for every
model in the cartridge:

```
214 archives scanned, 24 hold models
1,030 models decoded -- 1,030 exact, 0 mismatched
```

Including `build_model.narc`'s **590 buildings**, `mmodel`'s 24, `fldeff`'s 145
field effects, `titledemo`'s 3 (Giratina), and `ev_pokeselect`'s 6. A wrong
command length, a missed primitive type, an off-by-one in the strip winding —
any of them moves at least one of those four numbers on at least one model out
of a thousand, and none of them moved.

This is the best verification this project has had, and it is the same shape as
every other one that worked: **two tables that cannot borrow from each other.**

#### What the shape record actually is

Sixteen bytes, of which the two that matter are the display list's offset —
relative to the *record*, not the file — and its size. Both were measured, and
each confirms the other. On `pmsel_bg` the offset lands exactly on a
`40 22 21 24` packet (BEGIN_VTXS, TEXCOORD, NORMAL, VTX_10, which is how every
display list in this cartridge opens), and record + offset + size lands exactly
on the first byte of TEX0. Neither of those is likely by accident and both had
to hold.

#### What comes out

| | |
|---|---:|
| `psel_all` (the briefcase) | 12 bones, 15 materials, 29 shapes, 2,430 vertices |
| `psel_mb_a` (a Poké Ball) | 4 bones, 3 materials, 3 shapes, 328 vertices |
| `pmsel_bg` (the ground) | 1 bone, 1 material, 24 quads |

Rendered offline from the decoded triangles, the briefcase has its handle and
clasps, the ball has its open-lid flap, and the ground is a flat quad grid. The
material names are the cartridge's own — `trank_a` … `trank_i` for the trunk,
`op_mb` for the ball, `op_grand` for the ground — which is what pairs each
shape with a texture out of the same file's TEX0.

The strip winding is worth naming as a trap that this check caught rather than
a detail: a triangle strip alternates its winding, and getting that wrong turns
every other face inside out. It is invisible on a wireframe and invisible on a
flat fill; it shows up the moment the model is lit, by which time the decoder
has been trusted for weeks. The quad count would have been unaffected. The
triangle count would not.

#### What is NOT done, stated plainly

The reader is done and the **renderer is not**. Reading geometry and drawing it
are separate problems, and this engine has no 3D path of its own yet:

* **Somewhere to put the field animations.** All five formats decode their
  values now and all 378 check out, but the 98 texture scrolls and 72 flipbooks
  in `bm_anime` are laid over **map meshes that are not built**. They are
  extracted, verified and carried; nothing draws them until the terrain and
  building geometry exists.
* **The 2D side.** 796 `NANR` cell animations over 810 `NCER` cell banks are
  counted but not decoded — those are the sprite and UI animations, a separate
  format from the five 3D ones.
* **Seeing it run.** The starter select has still never been on a screen. The
  placement is the cartridge's own now rather than mine, which removes the part
  most likely to be wrong, but the camera distance and pitch are chosen rather
  than derived and that is what a single screenshot settles fastest.
* **The terrain meshes** are not in the sweep above: they are embedded in
  `land_data`'s chunk records rather than being narc members, so they are found
  a different way. The reader does not care — an NSBMD is an NSBMD — but the
  1,030 is honest about what it covers.

### Two more places the pairing is stored somewhere other than where it is used

The mesh reader decoded geometry. Getting a *picture* out of it needed two more
bindings, and both of them are recorded backwards from where you would look —
which is the same trap as `pl_winframe`'s palettes, one layer down.

#### Which material a shape is drawn with

A model's shapes and its materials are two independent dictionaries and neither
says how they pair. The pairing is in a third place: a little bytecode, the
**SBC**, that the hardware walks to draw the model. `0x04 n` binds material n,
`0x05 n` draws shape n, and a shape takes whatever material was bound last.

Its operand widths were derived from the streams rather than assumed —
`NODEDESC` takes three, plus one for each of the two low flag bits, which is
why `26 00 00 00 00` is four operands and `06 00 00 00` is three — and then
held to an invariant: **no shape drawn twice, every material index in range, no
unknown opcode.** A desynchronised walk breaks all three at once.

That check found two real opcodes the first table was missing (`0x07`
billboard, `0x0D` projection map) and one variable-width one (`0x09`, skinning,
whose width has to be read from its own operands). It also found `kurotama` in
`demo_tengan_gra`, which draws 38 of its 40 shapes — each exactly once, with
materials 0–6 out of seven, no unknown opcode. That is not what a desync looks
like; a cutscene model carrying two shapes its commands never reach is ordinary
content. So "every shape is drawn" was dropped as a clause and is **counted**
instead — a relaxation stated here rather than quietly made.

#### Which texture a material wears

Also backwards. A texture entry does not say "material n uses me" by sitting at
index n; it carries a list of the material indices that use it, packed as bytes
just before the material records, at an offset measured from the **section**
rather than from the dictionary.

And the order is not the same. On the briefcase, texture 1 (`op_mb`) belongs to
material 2 and texture 2 (`op_mb_a`) to material 1; `trank_a` and `trank_a_`
are swapped the same way. Walking the two dictionaries in step — the obvious
reading, and correct on every *simple* model in the cartridge — gives those
four the wrong picture and reports nothing.

#### The invariant that made "untextured" an answer instead of an excuse

Requiring every material to have a texture failed on **122 of 1,030** models —
always one or two materials on an otherwise complete model, never a whole one,
which is not the shape a wrong base address produces. A DS polygon can have no
texture at all, and this cartridge has plenty that do not.

What turns that from an excuse into a fact is the material record's own
**texture-scale field**: zero on exactly the materials the name lists leave
unbound, non-zero on exactly the ones they bind. Two records that know nothing
about each other, agreeing on every material in the cartridge. So the invariant
is not "everything is textured" but **"a material is bound to a texture if and
only if it declares one"**, and that holds everywhere.

Final state of the reader, all three checks at once:

```
1,030 models -- 1,030 exact, 0 mismatched
  geometry:  vertices, triangles, quads, polygons == the header's own counts
  draws:     no shape twice, materials in range, no unknown opcode
  binding:   bound <-> declares a texture scale, all indices in range
```

`Gen4Models.parse` gained a section argument for this. It read `u32(data, 16)`
to find TEX0, which is right for a texture archive and **wrong for a model
file**, where that word is the MODEL section — a parse that succeeds and builds
a texture table out of geometry. This format's recurring hazard, avoided by
passing the offset rather than re-deriving it.

Rendered end to end, the briefcase comes out with its leather straps, buckles
and handle, and the Poké Ball with its shadow: geometry from the display lists,
textures resolved through the name lists, colours from each material's own
palette.

### The animations, all five formats of them

A Nitro model does not animate itself. Everything that moves in Platinum's 3D
is a **separate file** that names what it drives. There are five formats and
the cartridge holds 378 of them:

| | | | |
|---|---|---:|---|
| `BCA0` | `JNT0` | 181 | joints move, rotate, scale |
| `BTA0` | `SRT0` | 98 | a texture scrolls or spins |
| `BTP0` | `PAT0` | 72 | the texture itself is swapped per frame |
| `BMA0` | `MAT0` | 24 | a material's colour changes |
| `BVA0` | `VIS0` | 3 | a shape appears or vanishes |

Plus 796 `NANR` cell animations on the 2D side, over 810 `NCER` cell banks.

#### The size rule, fitted rather than assumed

A joint's animation block is a flags word and seven channels — three scale,
one rotation, three translation — eight bytes each when animated, four when
the channel holds one value for the whole animation. Which are which is the
flags word, and **nothing states the block's size.** Get it wrong and the walk
desynchronises, exactly like a bad display-list command length.

But the file does state it, indirectly: each block runs to the next joint's
offset. So there are 1,090 known sizes and 64 distinct flag words, and the
rule can be *solved for*:

```
size = 60 - 12*bit1 - 24*bit9 - 4*(bit3 + bit4 + bit5 + bit6 + bit8)
       bits 0, 11, 12, 13 cost nothing
```

Maximum error over all 1,090 blocks: **zero**. A fit that is wrong anywhere is
wrong by four bytes somewhere, and there is nowhere. Sixty bytes is exactly
4 + 7×8, which is what says the seven-channel reading is right rather than a
coincidence that happens to add up.

#### The cross-check: an animation names something in another file

An animation header states no counts of its own, so there is nothing inside it
to reproduce. The check has to come from outside: **a joint animation must
have as many blocks as some model in the same archive has joints, and every
other format's target names must be joint or material names of a model there.**

```
BCA0  joint             181 animations, 181 structurally exact
BTP0  texture pattern    72 animations,  72 structurally exact
BMA0  material colour    24 animations,  24 structurally exact
BTA0  texture SRT        98 animations,  98 structurally exact
BVA0  visibility          3 animations,   3 structurally exact
cross-check against models in the same archive: 279 of 280 resolve
```

That is **378 of 378**, and it was 367 until two more of my own tests turned
out to be the thing that was wrong:

* *"A material name cannot contain a colon."* Eight SRT animations — the Wi-Fi
  lobby's fireworks and three gym pieces — drive materials called
  `water:lambert5` and `hanabi2:main1`. A character class I wrote by looking at
  the names I happened to have seen rejected every one of them.
* *"Every non-joint format hangs its targets off a dictionary."* Visibility does
  not. It is a bit per node per frame with no names at all, positional the way a
  joint animation is, and demanding a dictionary reported all three of them as
  unreadable. See *Visibility has no names, and that is the format*.

Both were caught the same way: a failure that lands on **every file of one
kind** is a bad test, not a bad cartridge.

Two of the three checks that were tried and **rejected** earlier are worth
keeping for the same reason:

* *"A dictionary record is four bytes."* True in the model section, where a
  record is a bare offset. False here: a texture SRT record is **forty**, with
  its scale, rotation and translation descriptors inline. Requiring four
  rejected all 98 SRT and all 24 material-colour animations — every file of two
  whole formats at once, which is a bad test, not a bad cartridge.
* *"A dictionary has at least one entry."* Nine of the ninety-eight SRT
  animations have **none** — a file that drives nothing. A wrong offset does
  not produce a clean zero; it produces a large arbitrary count.

#### The other four formats, with their numbers

The joint format got its values first because the briefcase needed them. The
other four are what animates the **world** rather than a skeleton, and almost
all of them live in one archive — `/arc/bm_anime.narc`, the field's own — which
holds **no models at all**: 98 texture scrolls, 72 flipbooks and a pile of door
and machinery animations laid over map meshes that are not built yet.

**Texture SRT (`BTA0`)** is five channels per material — scale S, scale T,
rotation, translate S, translate T — at eight bytes each: a frame count, a flag
word, and then either the value or an offset to one per frame. `0x2000` means
the value is in the record; `0x1000` means the array is `fx16` rather than
`fx32`. Rotation is a sine and a cosine, so its "value" is a pair. `funsui` —
the fountain — is identity scale, identity rotation, no S scroll, and a T
scroll that counts steadily downward. That is water, in five numbers.

The check here is a **budget rather than a tiling**, and the difference is worth
naming because every other format tiles exactly. A constant channel also gets a
four-byte array written for it, which the record then duplicates inline, so the
arrays cannot all be placed from the records alone. What can be demanded is that
every animated array sits inside the animation, that none overlap, and that the
leftover is exactly four bytes per constant channel. **All 98 satisfy that.**

On top of the placement, every rotation frame in the cartridge is a unit pair —
sin² + cos² = 1 — which is an independent way of saying the pair is read in the
right order and at the right scale.

**Texture pattern (`BTP0`)** is the flipbook: a material swaps which picture and
which palette it wears at named frames. The animation carries its own two name
lists, and the layout tiles to the byte — dictionary, then each target's
keyframes, then the texture names and the palette names, which end exactly at
the animation's last byte. **All 72.** Every keyframe is in frame order, inside
the frame count, and indexes a name the animation actually carries.

**Material colour (`BMA0`)** is five channels of four bytes: diffuse, ambient,
specular, emission and alpha. The four colours are 15-bit `GX_RGB` at two bytes
a frame and the alpha is a single byte — and it is the alpha being one byte
wide that makes the tiling come out exact rather than nearly. **All 24**, with
no colour ever setting bit 15 and no alpha ever exceeding 31.

#### Visibility has no names, and that is the format

`BVA0` is three files and it had been reported as three failures for as long as
the reader has existed, because the check insisted on a target dictionary. There
isn't one. The animation is a header and then **one bit per node per frame**,
positional exactly like a joint animation, with the node count in the header.

The header proves the reading by itself: twelve bytes plus one bit per node per
frame is the animation's exact length, in all three.

The packing direction is settled by the data rather than by convention.
`kurotama` is 42 nodes over 601 frames:

```
read frame-major : 80 visibility changes in total, mean run 393 frames
read node-major  : 3,497 changes, mean run 35 frames
```

Nobody authored the second one. And the count is checkable from outside the
file: `kurotama` has 42 nodes and `ari_start` has 9, which is exactly what the
models of those names carry — two files agreeing on a number neither derived
from the other.

#### A rule about what goes in the cache

`bm_anime` has no models, so its joint animations have nothing in the archive
that can wear them. Writing their matrices anyway cost **2.2 MB** of runtime
cache for poses nothing could apply.

So the extractor now writes a joint animation's matrices **only where a model in
the same set has that many nodes** — the same pairing `Gen4Anim.resolve` checks.
The texture scrolls and flipbooks, which are what make water move and are 200 KB
rather than 2.2 MB, are written regardless. When the map meshes land, their
joint animations come with them.

#### What the starter select actually is

With the reader in place, `ev_pokeselect` reads out exactly as
`choose_starter_app.c` loads it, and every animation's name matches its
model's:

```
0  joint anim   "psel_all"    41 frames, 12 joints   <-> model psel_all    (12 bones, 2,430 verts)
2  joint anim   "psel_mb_a"   73 frames,  4 joints   <-> model psel_mb_a   (4 bones,  328 verts)
4  joint anim   "psel_mb_b"   73 frames,  4 joints   <-> model psel_mb_b
6  joint anim   "psel_mb_c"   73 frames,  4 joints   <-> model psel_mb_c
8  model        "psel_trunk"  3 bones, 12 materials, 20 shapes -- the open case
9  model        "pmsel_bg"    the ground
```

**The box animation is 41 frames over 12 joints**, and the three balls are 73
frames each. Names and joint counts agreeing across two independent files is
the cross-check at its sharpest.

#### What is still not done

The keyframe **values** are not decoded, and that is deliberate rather than
unfinished. A value decoder for these formats cannot be checked the way the
mesh reader could — no header states a count for it to reproduce — so guessing
at which of the seven channels is which would produce numbers that animate
something, plausibly, and wrongly. The structural pass is what makes the value
pass checkable: it establishes exactly where each channel's data begins and
ends, and a decode that runs off the end of one now has somewhere to be caught.

### The renderer, and getting geometry into the cache without it becoming a megabyte

Reading a model and drawing one are separate problems, and the second one had
no home: the engine core has exactly one mesh in it (the tilt ground quad) and
one shader. The voxel 3D lives in a mod. So Platinum's 590 buildings, Giratina,
the field effects and the briefcase all had geometry decoded and nothing able
to put it on screen.

#### Two binary strings, not 2,430 tables

`Gen4Nsbmd` hands back a model as Lua tables — one per vertex, one per
triangle. That is the right shape to *check*, because the corpus test reads it,
and the wrong shape to ship: the briefcase alone is 2,430 vertex tables and
1,644 triangle tables, and written as Lua source that is a megabyte of
`{ x = ..., y = ... }` for one model out of six.

So a packed shape is two binary strings, the same trick the map grids already
use (`def.blocks` is a 2 KB string, not 1,024 tables):

```
vertex  14 bytes   x, y, z, u, v as s16;  r, g, b as u8;  one byte of pad
index    2 bytes   u16 into this shape's own vertex array
```

**The precision is the cartridge's own**, which is what makes this lossless
rather than a compromise. A Gen 4 coordinate *is* fx16 — a signed 16-bit number
over 4096 — so the raw fixed-point value keeps every position exactly as the
display list gave it. Texture coordinates are already integers in sixteenths of
a texel. Nothing here rounds anything that was not already round.

The whole cartridge packs to **3.97 MB across 238,372 vertices**, which is
small enough that publishing all 1,030 models is a choice rather than a
constraint. Only the starter selection's six are published so far, because a
model in the cache is worth having only when something draws it, and exactly
one screen will.

#### The check the pack needed

The mesh reader's own corpus test proves the *decode*. It says nothing about
the *pack*, and a packer that drops a field, swaps two, or mis-signs a negative
produces a model that still draws — inside out, or with a wall missing — which
nothing else would notice.

So the stage packs each model and **unpacks it again**, requiring every
coordinate and every index back unchanged to within half a fixed-point step,
which is the only rounding the format does. Run over the cartridge:

```
1,030 models packed, 0 failed round-trip
```

#### What the renderer is, and what it deliberately is not

`src/render/Gen4Model.lua`: a vertex shader with a model-view-projection
matrix, a `discard` on transparent texels, LÖVE meshes with an index buffer,
and a depth canvas.

It does **not** register a pipeline, touch the world pass, or ask the Renderer
for anything. A screen makes one, draws it into its own canvas, and throws it
away. That is because the first thing to use it is the starter select — a menu
with three Poké Balls in a briefcase, with no world behind it and no business
being in the world's pipeline. The map meshes will want the pipeline; a menu
does not, and building for the harder case first would have meant neither
worked.

Three decisions in it that are the cartridge's rather than mine:

* **Transparent texels `discard` rather than blend.** A Gen 4 texture keeps
  colour 0 transparent, and a transparent texel must not write depth — or the
  hole punched through a strap occludes what is behind it.
* **Back faces are not culled.** A DS polygon carries its own front/back flags
  in its material, and plenty of Gen 4 geometry is single-sided sheets meant to
  be seen from both. Culling uniformly loses the far wall of the briefcase;
  with a depth buffer, drawing both costs a few overdrawn pixels.
* **Nearest filtering, always.** These are 16- and 64-pixel textures on a model
  drawn several times its own size. Smoothing turns a Poké Ball's seam into a
  smear.

The depth mode and cull mode are both saved and restored around the draw,
unconditionally. This runs inside somebody else's `draw`, and a depth test left
switched on makes the next ordinary 2D blit vanish in a way that looks like a
bug in whatever came after it.

The starter set as published:

```
psel_all    29 shapes,  2,430 verts,  1,644 tris   (the closed briefcase)
psel_trunk  20 shapes,  1,450 verts,    828 tris   (the open one)
psel_mb_a/b/c  3 shapes,  328 verts,   272 tris each
pmsel_bg     1 shape,      62 verts,    48 tris   (the ground)
59 shapes, every one textured -- 86.9 KB of packed geometry
```

with the four joint animations carried beside them rather than folded in,
because an animation names what it drives and the pairing is by name — which is
the cross-check, and merging them would throw it away.

### The starter select, and the three lists that had to agree

`Gen4StarterSelect` draws Professor Rowan's briefcase from the cartridge's own
geometry: the open case and the three Poké Balls are NSBMD models out of
`ev_pokeselect`, decoded, packed, textured and drawn by the mesh renderer. It
is the first 3D this port draws itself.

#### Three lists, none of which knows about the others

The species ids come from `choose_starter_app.c`
(`STARTER_OPTION_0 = SPECIES_TURTWIG`), the offer lines from **message bank
360**, and the ball models from `ev_pokeselect`'s members 3, 5 and 7. Nothing
links them — they are three parallel orderings that happen to line up, and if
they ever stopped lining up the briefcase would hand over the wrong Pokémon
with nothing to report.

So the stage checks them against each other: the species the id names must be
the one the offer line is about. All three agree.

```
TURTWIG   387  psel_mb_a  "Tiny Leaf Pokémon TURTWIG!  Will you take this Pokémon?"
CHIMCHAR  390  psel_mb_b  "Chimp Pokémon CHIMCHAR!  Do you choose this Pokémon?"
PIPLUP    393  psel_mb_c  "Penguin Pokémon PIPLUP!  Is this Pokémon for you?"
```

A `mismatch` field is written when they do not, and nothing should ever read
it — it exists so that if the three ever drift, the drift is in the data rather
than in somebody's memory.

#### The placement was never mine to invent — it is in the model's nodes

The first version of this screen placed the three balls itself. It measured the
case's inside floor (41 vertices cluster at y = 0, the outer base at −30, the
lid to 98), divided the case's own 152 of width into three, and set named
constants `FLOOR_Y`, `FRONT_Z` and `SPREAD_X` with a paragraph explaining which
of them were measured and which were arithmetic.

All of it was wrong, and honestly explained wrongness is still wrongness. The
positions are **data**, and they were sitting in a part of the model file this
reader had never opened.

Every NSBMD carries a node list beside its shapes, and a shape's vertices are in
**its node's** space rather than the model's. On most of this cartridge the
nodes are identity and nothing is lost by ignoring them — which is exactly why
ignoring them survived 1,030 models of corpus testing without a complaint. On
`psel_all`, the model that holds the case *and* the three balls *and* their
shadows, the nodes are the only record of where anything is:

```
node  4 psel_mb_a    T = (-30, 50, 0)
node  6 psel_mb_b    T = (  0, 44, 0)
node  8 psel_mb_c    T = ( 30, 50, 0)
node 10 tran_down    identity      (the case body)
node 11 tran_top     identity      (the lid)
```

Thirty apart, not forty-two; the middle ball six units lower than the other
two, which no amount of dividing a width was ever going to produce.

A node block is a flags word, a spare `fx16` belonging to the rotation, and then
only the parts that are not the default: three `fx32` of translation unless
bit 0, a rotation unless bit 1 (a pivot pair under bit 3, otherwise the other
eight elements of a 3×3, the first being that spare word), and three scales with
their reciprocals unless bit 2. **Every node block in the cartridge ends exactly
where the next one begins under that reading**, which is what makes the widths
right rather than plausible.

Arranging them is the SBC again — the same little bytecode that says which
material a shape wears. `renderCommands` had been reducing it to that one fact;
posing needs the *order* as well, because a node descriptor multiplies onto
whatever matrix is current, may restore from a saved slot first, and may save
its result for a later shape to come back to. `poseCommands` keeps the sequence
and `pose` replays it. The rest pose is that walk with the model's own node
matrices; an animated pose is the same walk with a joint animation's frame.

That is the whole reason the animation was worth decoding as matrices rather
than as keyframes: **the two are the same walk over different numbers.**

#### The opening animation, decoded

A joint block is four bytes of header and then seven channels in this order —
translation x, y, z, the rotation, scale x, y, z. Each is absent, constant or
animated:

| | absent | constant | animated |
|---|---|---|---|
| translation | bit 1 | bits 3, 4, 5 — one `fx32` each | 8 bytes |
| rotation | bit 6 | bit 8 — a `u16` index | 8 bytes |
| scale | bit 9 | bits 11, 12, 13 — **8 bytes**, a value and its reciprocal | 8 bytes |

Scale is the one that hides: constant and animated are the same width, so bits
11–13 cost nothing and are the *only* way to tell them apart. That is why the
earlier fitted per-bit size rule could be exact and still not say what a block
contained.

An animated channel is a start frame (zero in all 1,287 of them), a word holding
the frame count with `0x2000` meaning the values are `fx16` rather than `fx32`,
and an offset.

**The invariant.** Walking every joint channel by channel lands exactly on the
block's stated end **1,099 times out of 1,099**. Then the value arrays, the two
rotation tables and nothing else **tile every one of the 183 joint animations**
from the end of its joint blocks to its last byte — no gap past three bytes of
alignment, no overlap anywhere. An element size read wrong leaves a hole
somewhere, and there is nowhere. That check ships as `Gen4Anim.checkValues`.

The half-precision bit got its own confirmation for free: of 418 full-precision
translation channels, **not one** stays inside the `fx16` range, and of 123
half-precision channels, **not one** leaves it (the largest is 7.650 against a
limit of 8). The two encodings are the same units, and the flag means exactly
what it looks like.

#### Two rotation tables that had to agree with each other

A rotation frame is a `u16` whose top bit picks the table: set for the pivot
table at +0x0C, clear for the compressed 3×3 table at +0x10. That is not a
convention borrowed from elsewhere — in `psel_all` the indices with the top bit
set are exactly 0..90 and the ones without are exactly 0..139, while the tables
hold exactly **91** six-byte records and exactly **140** ten-byte records. Two
counts, neither derived from the other, partitioned with nothing left over and
nothing out of range.

**A pivot record** is a rotation one of whose rows is an axis: a ±1 at position
`flags & 0x0F`, its row and column zero, and the remaining 2×2 holding a cosine
and a sine — which is why a² + b² is 1 in all 24,538 of them. The sign of the
±1 follows the parity of the position, and bit 6 flips it.

That last bit is where the first attempt was wrong, and where the check caught
it. Where an animation crosses between the two tables mid-channel, the pivot
frame and the compressed frame beside it are **the same rotation described twice
by two encodings that share nothing**. Under a parity-only rule, six of the
fifteen flag words that occur disagreed with their neighbours by a whole unit —
and they had to, because negating the ±1 alone turns a rotation into a
reflection. Flipping the 2×2 with it — `(a, b / b, −a)` rather than
`(a, b / −b, a)` — restores the determinant and the agreement.

**A compressed record** is five numbers for a nine-number matrix: the first row,
then the first two of the second. The rest follows from the matrix being a
rotation. The obvious closed form — solve perpendicularity for the missing
element — divides by the first row's third element, which is a rounding error
from zero in **727 of the 6,876 records here**; it produces components past 11,
which is not a rotation at all. Taking the magnitude from unit length and only
the *sign* from perpendicularity is stable everywhere and agrees with the
division wherever the division means anything. All 6,876 come out orthonormal
with determinant +1.

Across the cartridge, 406 of the 419 table crossings are smooth relative to
their own channel's typical motion. The 13 that are not sit in four animations —
the Spear Pillar cutscene and one Mime Jr. animation — and mostly at frame 2,
which is what a deliberate cut looks like. That is reported as a counted
statistic rather than as a pass, for the same reason the SBC walker reports
"38 of 40 shapes drawn" instead of claiming every shape.

#### What the briefcase actually does

```
tran_down   identity → −90° about X by frame 30, overshooting around 15–25
tran_top    tilts and returns to identity — so the lid opens 90° relative to it
psel_mb_a   (−30, 50, 0) tumbling to (−44, −4, 32), at a constant 0.8 scale
psel_mb_b   (  0, 44, 0) → (0, −4, 62)
psel_mb_c   ( 30, 50, 0) → (38, −4, 26)
```

The case starts closed and upright, rotates down, the lid swings open, and the
three balls tip out and settle in a row in front of it. **Frame 0 of every ball
joint equals that ball's own node transform in the model** — a third independent
agreement, between a file that says where things rest and a file that says how
they move.

A track is packed at 48 bytes a frame: the top three rows of the matrix at the
cartridge's own 1/4096, so the round trip can demand the values back *unchanged*
rather than close. All 1,099 joint tracks in the cartridge round-trip exactly.

That number was 30 bytes in the first version, which stored the rotation as
`s16` on the grounds that a rotation element cannot leave −1..1 and the scale
beside it never left 0.8..1.25. True of the briefcase, false of the cartridge:
41 tracks carry scales past 8 and Giratina's pillars reach 18.4. The round trip
said so — which is the only reason it is not still wrong — and the fix was to
stop assuming a range rather than to widen the one I had assumed.

#### What the screen invents now

Two things, down from four:

* **The lift on the selected ball.** The cartridge has a 73-frame animation per
  ball for this and all three are extracted; what the app does with them is code
  rather than data, so this raises the chosen one instead.
* **The camera.** Distance and pitch frame the posed model; the cartridge's
  camera comes from its own movement steps.

One more thing had to be said out loud rather than assumed: `psel_all` is
**Z-up**. It was exported with the vertical axis last — its lid reaches 116 in
what the case model calls depth — while the engine's camera assumes y is up. The
screen applies that rotation to the *scene* rather than to the geometry, so the
cartridge's numbers stay the cartridge's numbers.

#### A bounding box that does not agree with its own geometry

While measuring the framing: the model header's stated box matches the decoded
geometry on only **312 of 1,032 models**, under any reading of it I could find
that works on the rest. (It reads as a corner and a size at 1/2048, which is
right on the simple models and wrong on the ones with real hierarchies.)

Rather than ship a camera that trusts it, `Gen4Model:framing` now measures each
shape's own box while the vertices are still in hand and unions them **through
the pose** — which it has to do anyway, since the three balls are only 60 apart
once their nodes have placed them. The header box is left unread. It is listed
under open questions rather than called a bug, because a reading that works on
a third of the corpus is more likely to be an incomplete reading than a broken
file.

---

## The map meshes, and the block that agrees with them

The 3D half of the world is two archives and they both read now.

**Terrain.** Every land chunk's fourth block is an ordinary NSBMD, and all
**666 of them decode exactly** against their own headers' vertex, polygon,
triangle and quad counts — 7,547 shapes and 1,066,987 vertices of Sinnoh.

**Buildings.** `/fielddata/build_model/build_model.narc` is 590 models, **all
590 exact**, 1,362 shapes and 89,253 vertices. 568 of them carry their own
textures; the other 22 do not, which is the first hint that where a picture
lives is a separate question from where a mesh lives.

### Where the ground is, checked against a block that was not used to find it

A land chunk holds four things: a permission grid, the objects standing on it,
the mesh, and a `BDHC` height field. The height field was decoded long before
the mesh, from the cartridge's own `BDHC_LoadHeader`, and it measured a tile at
**sixteen world units with the chunk centred on the origin** off nothing but
its plate extents.

The mesh, read independently, spans −256..256 on both horizontal axes. Same 512
units over 32 tiles, same centring. Two blocks of the same file, neither read
from the other, agreeing about the size of a tile.

Then the harder question: do they agree about the *height*? Sample every fourth
tile of every chunk, keep only the tiles the permission grid calls land rather
than void — a third block, used to decide where the comparison is even
meaningful — and ask the mesh how high its surface is under that point:

```
331 of 666 chunks agree with the BDHC at every sampled point
8,505 of 11,356 points agree to within 0.1 units -- not close, exact
1,655 more within four units; 55 further than sixty-four
```

**The agreement being exact where it happens is what makes this a check rather
than a correlation.** A wrong scale, a flipped axis or a missed `posScale`
produces a cloud of near-misses; it does not put three quarters of the points
on the answer to a tenth of a unit. All four axis flips were tried and every
one of them made it worse.

And the tail says something specific rather than being noise: **9,497 walkable
tiles have no land-mesh triangle beneath them at all.** The land mesh is not
the whole floor. Indoor chunks are a shell, and their floors are building
models — which is the next thing to establish, not a disagreement about this
one.

### Looking at it

The permission grid was validated by drawing it and recognising Sinnoh. The
meshes were validated the same way, and the second picture is the one that
settles the whole chain at once.

The first picture (rendered from a ROM, so not kept in the repo) is the entire 30×30 overworld matrix —
900 chunks, one pixel a tile — rasterised top-down from the decoded geometry,
with every texture sampled through the interpolated UVs and a depth test
keeping whatever is highest. The second is three chunks of
one town at eight pixels a tile, with its buildings placed from the chunk's own
object records.

Mt. Coronet runs north to south through the middle in bare rock; the three
lakes sit in their pockets; the snow starts at the top of the map; the Great
Marsh, the east-coast water column and the Battle Zone are all where the
permission grid put them — **and the permission grid was never consulted to draw
this.** Two independent blocks of the same 666 files producing the same Sinnoh
is the strongest statement available about either of them.

The town picture says more about the details: the plaza's paving, hedges,
benches, the fountain, a bridge and the roofs all land in the right places at
the right sizes, which exercises the node transforms, the SBC pose walk, the
`posScale` on every model, the 16-units-per-tile chunk placement, the object
records' fixed-point positions and the texture binding, all at once. A mistake
in any of them is visible immediately.

Two things are visible and honest to name: the black areas are chunks with no
mesh at all, and a few faces come out untextured white where a material's
texture is not in the library.

WHAT THIS RENDERER IS NOT. It is a throwaway top-down rasteriser in the
harness, not the engine — no perspective, no lighting, no alpha, no animation.
It exists to answer "is the geometry right", and it does.

### Which pictures a map wears

A land mesh carries no textures — all 666 of them — so `areaDataArchiveID` in
the map header is what says where the pictures are. The area record is eight
bytes:

| | | |
|---|---|---|
| `+0` | buildings | `area_build.narc` **and** `areabm_texset.narc` together |
| `+2` | mapTexture | `map_tex_set.narc` |
| `+4` | lighting | 0..9 |
| `+6` | flags | 0..2 |

The ranges pin the fields. Over all 75 areas `+2` reaches 73 against a
74-member archive, so it can only be the map textures; `+0` reaches 70 against
two archives of 71 each, and those two are parallel — one names the building
models an area uses, the other holds their textures. `+4` never passes 9 and
`+6` never passes 2, so neither indexes anything here; both are named for what
they are not. All 71 area build lists end exactly on their own leading count,
and all 2,818 model ids they contain are inside `build_model.narc`.

The pictures above resolve every texture through a **library of all 74 map
sets plus all 71 building sets, first match by name** — which is why they look
right and is not what the cartridge does.

**What does not resolve yet, stated plainly.** Of the 2,307 distinct texture and
palette names the terrain meshes ask for, **2,287 exist in some `map_tex_set`
member** — the twenty that do not are the Underground and a handful of gym
objects, which are elsewhere. But matching each map to *its* set is not
finished: attributing chunks to maps through the matrix's own header grid, 729
of 867 chunk-and-map pairs find every name they need in that map's set, and 138
do not. The names they miss are the commonest ones in the game (`ngrass`,
`grass`, `tshadow`), each of which appears in around 23 of the 74 sets, so this
reads like a second set being loaded alongside the first rather than a wrong
index — and "reads like" is exactly why it is written down here instead of
being coded.

---

## The item table was wrong for two thirds of its rows

Building the Gen 4 bag started with a simple question — which pocket does an
item live in — and the answer came back nonsense: the Bicycle, the Town Map and
the Old Rod all claimed the same pocket as TM79.

**The name bank has 468 entries and the data archive has 446.** The difference
is the twenty-two unused ids 113..134, which the names keep as `???`
placeholders and the data archive simply does not have. A member index is
therefore item `i` up to 112 and item `i + 22` after that — and this reader had
the comment "member index is the item id" written at the top of it.

Every item from Adamant Orb onward — **333 of the 446** — carried the price,
pocket, hold effect, fling data and party-use block of an item twenty-two
places further on. Twenty-two more items (ids 446..467, up to the Secret Key)
did not exist in the table at all.

**Why it survived.** The note above that code listed its own verification:
"Master Ball 0, Ultra Ball 1200, Poké Ball 200, Potion 300, HP Up 9800". All
five are below the gap. So are the balls, the medicines and the battle items,
which is why every pocket anyone had thought to look at came out right.

**What found it** was asking a question that covers the whole table instead of
the start of it: group every item by the pocket its own record claims, and
print the id runs.

```
pocket 2  ids   1..16   (16)   Master Ball .. Cherish Ball
pocket 1  ids  17..54   (38)   Potion .. Old Gateau
pocket 6  ids  55..67   (13)   Guard Spec. .. Red Flute
pocket 5  ids 115..126  (12)   ??? .. ???
pocket 4  ids 127..190  (64)   ??? .. Kebia Berry
pocket 3  ids 306..405  (100)  Sky Plate .. TM78
pocket 7  ids 406..445  (40)   TM79 .. Old Rod
```

Every run is exactly the right SIZE — 16 balls, 38 medicines, 13 battle items,
12 mail, 64 berries, 100 TMs and HMs, 40 key items — and every run from the
mail onward sits twenty-two ids too low. **Eight independent counts agreeing
while eight independent positions disagree is one offset, not eight
coincidences.**

The fix ships with the check rather than instead of it. `Gen4Items.POCKET_RANGES`
is the cartridge's own id ranges, written down separately from the record field
that is decoded — so the two can disagree — and `Gen4Items.checkPockets`
requires every item in a range to claim that range's pocket and every item
outside them to claim ITEMS. Under the old reading it fails 333 times. Under
the new one:

```
pocket check: 445 of 445 items sit in the pocket their id range says
```

## The trainer card

The second of the four screens reported as falling back to Kanto's art. It has
two pages, as Platinum does.

The **badge case** is entirely the cartridge's: the "LEAGUE BADGES" panel
composed from its own tilemap, the eight badge sprites, and where they go —
measured off the panel rather than guessed, since the sockets are the only
shapes on it darker than its own background and come out at x = 43, 99, 155,
211 and y = 59, 115. Each badge's art sits in the top-left 40×40 of its 64×64
frame, so a badge drawn twenty pixels up and left of a socket's centre lands in
it.

The **card face** is not the cartridge's, and the file says so at the top rather
than leaving it to be discovered. Platinum draws the card's background and its
field labels as background tiles; `trainer_card/trainer_card` is that strip,
extracted at 64×240 and uncomposed, because nothing in that archive pairs it
with a tilemap the way the badge case is paired with its own. The portrait is
the same story. Both are one tilemap away, and finding it is the work — not
drawing something close enough over the gap.

---

## The bag

The third of the four screens reported as falling back to Kanto's, and the one
the item fix above was really for.

**Eight pockets, not five.** Gen 1–3 have four or five; Platinum has ITEMS,
MEDICINE, POKé BALLS, TMs & HMs, BERRIES, MAIL, BATTLE ITEMS and KEY ITEMS.
Every one of those words is bank 395's, and the bank's order is exactly the
order an item record's own `fieldPocket` numbers them — so the bank index *is*
the pocket number and nothing pairs the two by hand. The counts agree item for
item: 163 / 38 / 16 / 100 / 64 / 12 / 13 / 40.

The art is the cartridge's: `bag/bag_ui_main` is the screen, and the pocket
icons are one 64×64 sheet whose top eight sixteen-pixel cells are the icons and
whose bottom eight are the small markers that sit under an unselected one. That
split was measured, not assumed — on a sixteen-pixel grid the top eight cells
carry 160 opaque pixels each and the bottom eight carry 40.

**What an item does is not reimplemented here.** Using, giving and tossing live
in `BagMenu.useItem`, which is published for exactly this reason and is what
Emerald's bag calls too. This screen is Platinum's list and Platinum's words.

And it declines what it cannot answer: a push carrying `sell`, `itemPc` or
`store` falls through to the screen that has those flows, the same way the Gen 3
aliases have always worked. Better a Kanto shop counter than a Platinum bag
that cannot sell.

---

## The party screen, and where it stops

The last of the four. The six panels' positions are measured off `party/menu`
rather than guessed: the panels are one teal, striped every other row, so the
stripes give the bands away — on the left half they run 5..47, 53..95 and
101..143, and on the right half 13..57, 61..107 and 109..151. Two columns of
three, a pitch of 48 on both sides, the right one starting eight pixels lower,
which is the stagger Platinum's screen has. The cursor art being 128 wide is the
third independent way of saying a column is half the screen.

**Where it stops is the interesting part**, and it is in the alias rather than
buried in the screen:

| push carries | screen | why |
|---|---|---|
| `onCancel` alone — the field menu | Gen 4 | this is the reported bug |
| `pickOnly` / `forceSwitch` | Gen 4 | a pick with no submenu to draw |
| `battle` | Gen 3 | SHIFT, forced switches and item targets already work there, in Emerald's own words |
| `tmhm` | Gen 3 | ABLE / NOT ABLE are cartridge words this cache does not carry |
| `chooseOrder` / `onOrder` | Gen 3 | the Frontier's four sentences, likewise |

A declined push is Hoenn's screen doing the job. A served one that cannot finish
it is a dead end, and a dead end in a party menu is a save the player cannot get
out of.

The one thing the field menu does not offer is GIVE/TAKE an item.
`BagMenu.giveItem` is published and would serve it; what is missing is
Platinum's own word for it, and a menu entry in the engine's English on a screen
that is otherwise the cartridge's is exactly the seam this port does not leave.

---

## The summary pages, and the bank that had to be found by a phrase

The party menu's SUMMARY had nowhere to go, so this is the fifth screen.

**Bank 455 is the whole screen's vocabulary** — the six page titles, every
field label, the twenty-five nature lines and the twenty-five characteristic
lines, 187 strings that are this screen and nothing else. Finding it is the
part worth recording.

Searching for the obvious words found the wrong banks twice. Bank 326 carries
"Exp. Points", "ID No.", "Nature" and "Item"; bank 336 carries "Exp. Points",
"Held item", "Ribbons" and "Ability". Both are **debug menus** — the giveaway
is what sits beside those words: "Random value", "HP rnd", "Set Ribbons", "msg
location", "Player's side 1".

What found the right one was searching for the phrase nothing else in the
cartridge says. **"To Next Lv." occurs exactly once in all 1,127 banks.** Three
common words in common is not an identification; a phrase that occurs once is.

```
  7 "POKéMON INFO"      109 "POKéMON SKILLS"    128 "BATTLE MOVES"
  8 "Pokédex No."       110 "HP"                135 "PP"
 10 "Name"              111 "Attack"            147 "POWER"
 12 "Type"              112 "Defense"           148 "ACCURACY"
 13 "OT"                113 "Sp. Atk"           149 "CATEGORY"
 15 "ID No."            114 "Sp. Def"           152 "SWITCH"
 17 "Exp. Points"       115 "Speed"             24..48  the 25 natures
 19 "To Next Lv."       116 "Ability"           76..100 the 25 characteristics
```

**The rows are measured off the pages themselves.** Each page is a panel of
stripes and a stripe boundary is a row: on `page_info` the colour changes at
y = 40, 56, 72, 88, 104, 120, 136 — a sixteen-pixel pitch, one row per label,
and there are exactly seven labels. On `page_battle_moves` the changes come at
50, 82, 114, 146: four move rows at a pitch of thirty-two. The white value
boxes sit at x = 180, which is where the values go.

**Three pages, not six.** CONDITION, CONTEST MOVES and RIBBONS are named in the
bank and are not drawn. Contest stats and ribbons are not modelled by this
engine, and an empty page carrying the cartridge's own title would claim they
were. The move-learn screen's "which move to forget" is likewise not served —
the alias does not list `choose`, so that push keeps the Gen 3 screen.

---

## Two screens that were "missing a tilemap" had one all along

The trainer card's face and the Poketch's twenty-five app screens were both
written up here as blocked on a tilemap nobody could find in their archive.
Both archives have one. What was wrong was the pairing.

`/graphic/poketch.narc` has **27 NSCRs**, named `calculator.NSCR`,
`digital_watch.NSCR`, `coin_toss.NSCR` — one per app. `/graphic/trainer_case.narc`
has ten, including `trainer_card_front.NSCR`, `lucas.NSCR` and `dawn.NSCR`.

**Three separate pairing faults, each of which composed something rather than
failing:**

1. **`_bg_tiles` was not a role suffix.** Every Pokétch app names its
   background `<app>_bg_tiles.NCGR` beside `<app>.NSCR`. The suffix list had
   `_tiles` but not `_bg_tiles`, so the two never grouped, and every app's
   tilemap fell through to the archive's shared sheet — the device border.
   Composing the border's tiles through the calculator's map is what produced
   the repeating tile soup. Adding the suffix **before** `_tiles` (so the
   longer one matches first) fixes twenty of the twenty-five.
2. **A base can own two sheets.** `stopwatch_bg_tiles.NCGR` and
   `stopwatch.NCGR` normalise to the same name; the first is the app's
   background and the second is its sprite sheet, and the merge took whichever
   came first in the archive. A sheet whose own name carries a role suffix is
   the background, and now wins.
3. **Some screens name their sheet after something else entirely.** Both
   watches draw on `watch_bg_tiles`; the card's front and back both draw on
   `trainer_card_tiles`; Lucas and Dawn both draw on `player_tiles`. No rule
   over the names finds those — `lucas` and `player` share nothing — so they
   are written down per archive as `tilesFrom`, and the suffixes handle the
   rest.

The calculator now composes as a calculator keypad and Lucas composes as Lucas.

**What is still wrong: the palettes.** Most Pokétch apps carry no `NCLR` of
their own and take the archive's shared one, and several then compose black on
black. The Pokétch's display colour is a runtime setting on the hardware — the
Color Changer app sets it — so "which palette" may not have a static answer,
and that is the next thing to establish rather than to guess at.

Checked for regressions: the badge case, the bag, the party screen and the
summary pages all compose exactly as before, and the party panels' measured
bands are unchanged to the pixel (5..47, 53..95, 101..143 and 13..57, 61..105,
109..151), so the party menu's slot layout still holds.

## The Poketch's apps, from two banks that disagree about order

Twenty-five apps, and neither bank knows everything about them.

Bank 29 entries 11..35 are the descriptions the Pokétch Company's receptionist
reads, **in app order** — which is what an app id means. What they do not do is
say where a name ends: "The Digital Watch displays the current time" is one
sentence.

Bank 213 entries 83..107 are the same twenty-five written for the underground
shop, and there each name is wrapped in a colour code:
`The {COLOR 2}Digital Watch{COLOR 0} app displays...`. So the names come from
213 and the order from 29 — and 213 is in a **different order** (Calculator
second, Memo Pad third), so pairing them is by text, not in step.

The pairing is the check. Matching "The `<name>`" against the start of each
description paired twenty-four of twenty-five and left the Calendar out,
because its description is the one that does not begin that way: "Use the
monthly Calendar to make a note of important dates." Matching anywhere instead
needs the LONGEST name, because "Counter" occurs inside "Trainer Counter" — and
then the twenty-five assignments have to be a permutation, which is what says
the looser match did not fold two apps onto one name.

```
poketch: 25 apps, 0 unpaired
art keys that do not exist in the cache: 0
apps with no face of their own: Friendship Checker, Pokémon History, Dot Artist
```

Those three have no screen of their own in the archive and fall back to the
cartridge's own `unavailable` picture rather than to a blank one this port
drew.

---


## Eight faults from play, and what each one actually was

Reported after a session on the imported cache:

> the intro and intro animation is still missing from the main menu just shows
> a black screen on startup with press start at the bottom, the new game menu
> is still not correct the boxes surrounding the text are still too small thry
> should match the rom, the options menu is missing gen4 platinum game
> options, and when i load in it looks like the screenshot and when i try and
> walk my character spins in circles, the trainer card still isnt correct and
> neither is the pokedex, or the pokemon party menu or the bag theyre looking
> like gen1 still. Also talking to npcs does nothing.

Eight complaints. They are **not** eight bugs. The log from that session is
what separated them, and it is worth saying how, because the screenshots and
the descriptions on their own pointed at the wrong places entirely.

### What the log said, and what it ruled out

`AppData/Roaming/LOVE/Gen2Recomp/log.txt`, one boot, in order:

```
[debug] state stack: push Gen4Intro (depth 1)
[warn]  state stack: popping Gen4Intro emptied the stack
[debug] state stack: push TitleState (depth 1)
[debug] state stack: push Gen4MainMenu (depth 2)
[debug] state stack: push Gen4Options (depth 3)
...
[warn]  gen4 bag: this cache carries no pocket names -- falling back to the engine's own
[debug] state stack: push Gen4BagMenu (depth 2)
[warn]  gen4 trainer card: this cache carries no badge case art -- the badge page
        will be drawn in the engine's own frame
[debug] state stack: push Gen4TrainerCard (depth 2)
[info]  gen2 script vm: 0 maps attached (talk)
[info]  gen2 script vm: 478 maps attached (scenes)
[warn]  gen4 intro: this cache carries no `gen4_intro` record; skipping the opening
[warn]  no text for Twinleaf Town/nil        (x10)
```

Three things fall out of that immediately.

**The Gen 4 screens were not falling back to Gen 1 at all.** `Gen4BagMenu`,
`Gen4TrainerCard` and `Gen4Options` are on the stack by name. The alias table
in `Screens.lua` worked, `data.isGen4Cache` was set, and every push routed
correctly. What was wrong was one layer in: each screen found its cartridge
record missing and drew itself in the engine's own frame, which is what "looks
like gen1" was describing. Chasing the alias table would have found nothing,
for as long as it took to stop and read the two warnings above the pushes.

**`TitleState` on the stack is `Gen4Title`.** `Game:makeTitleState` ends with
`title.screenId = title.screenId or "TitleState"`, and the stack logs
`screenId` first. The proof it is the Gen 4 one is the next line: `Gen4Title`
is the only screen that pushes `Gen4MainMenu`. So the black screen was not the
wrong screen; it was the right screen with no pictures.

**`gen2 script vm: 478 maps attached (scenes)` should not exist in a Platinum
log at all.**

### Fault 1 — one missing list, five faults

`Data:load` builds its module list from three tables and never named a single
`gen4_` module. `gen4_map_headers` is loaded once, as the probe that decides
the cache is Gen 4, and its result is thrown away. So `gen4_menus`,
`gen4_graphics`, `gen4_intro` and `gen4_models` — all four written by the
extractor, all four present on disk, all four read by name from `game.data` by
the screens that need them — were never on the table.

Every consumer is written to degrade when its record is absent. That is why it
failed silently and completely:

| Reported as | Actually |
|---|---|
| "black screen on startup with press start" | `Gen4Title` drew its border field with no logo, because `gen4_menus.title` was nil |
| "the intro animation is still missing" | `Gen4RowanIntro` said so in the log: no `gen4_intro` record |
| "the boxes surrounding the text are still too small" | `Gen4MainMenu` sized its boxes from the engine's defaults, not `gen4_menus.layout` (`optionWidth = 26`, `margin = 32`, `lineTiles = 2`) |
| "the options menu is missing gen4 platinum game options" | `gen4_menus.options` holds seven real rows — TEXT SPEED, BATTLE SCENE, BATTLE STYLE, SOUND, BUTTON MODE, FRAME (20 values), CLOSE — and none of them was read |
| "the trainer card / party menu / bag look like gen1" | `gen4_graphics.screens` holds 922 composed pictures including all of `bag/`, `party/`, `summary/`, `trainer_card/` and `pokedex/`; the screens found nil and used the engine's frame |

Fixed in `src/core/Data.lua`: a `GEN4_PREFIXED` list, loaded by name and only
on a Gen 4 cache, each one optional with its own log line. The prefix stays
deliberately — an un-prefixed `menus` or `graphics` would resolve through the
additive cache overlay to the **root** cache, which is Red's, which is the
exact trap `CLASSIC_ONLY` exists to close.

The other nine `gen4_` modules on disk (`gen4_text`, `gen4_events`,
`gen4_map_permissions`, `gen4_overworld`, …) are extractor **input**: they are
lowered into `text`, `map_scripts`, `maps` and `sprites` before the cache is
written, and no running screen reads them. They are deliberately not in the
list.

### Fault 2 — "my character spins in circles"

`SpriteRenderer` has read every sheet in every generation with six fixed
slots: `stand down, stand up, stand left, walk down, walk up, walk left`, with
east drawn by mirroring west because no Game Boy or GBA cartridge has east
art. A Platinum sheet out of `mmodel.narc` is a stack of textures in the
**archive's** order and is not in that layout at all. On a sixteen-texture NPC,
the slot the renderer takes for "standing south" holds a **back** view and the
one it takes for "stepping south" holds a **left** view. Walking therefore
changed the apparent facing on every step. The description was exact.

**The order is in the cartridge, in the same archive as the sheets.** The last
twenty-five members of `mmodel.narc` are not models: they are the
`BillboardGfxSequence` tables, four fields back to back —

```
u32 seqCount
u16 startFrame[seqCount]
u8  textureIdx[seqCount]
u8  plttIdx[seqCount]
```

— and a frame's texture is the last segment whose `startFrame` is `<=` it,
exactly as `billboard_gfx_sequence.c` reads it. The grouping into animations
is code rather than data (`object_event_gfx_data.c`): a walker's animation *N*
covers frames 16N..16N+15, and the direction picks *N* through `{0,1,2,3}`
with `DIR_NORTH 0, DIR_SOUTH 1, DIR_WEST 2, DIR_EAST 3`.

So each direction is four segments of four frames, and a cycle is
**stand, step, stand, step**.

Read that way out of the ROM:

| sequence | up | down | left | right |
|---|---|---|---|---|
| `generic_walk` (16, every NPC) | 0, 8, 10 | 11, 12, 14 | 15, 1, 3 | 4, 5, 7 |
| `walk_and_run` (32, the player) | 0, 11, 26 | 27, 28, 30 | 31, 1, 3 | 4, 5, 7 |
| `bike` (24) | 0, 11, 18 | 19, 20, 22 | 23, 1, 3 | 4, 5, 7 |
| `pokecenter_nurse` (17) | 0, 9, 11 | 12, 13, 15 | 16, 1, 3 | 4, 5, 7 |

as `{ stand, step, step }`.

**Checked against the pictures, not against itself.** Laying the player's 32
frames out in that grouping gives four rows of one consistent direction each —
back, front, left, right — and the same grouping on `lass` and `prof_rowan`
does too. A lookup that cannot miss cannot tell you it is wrong; a picture can.

Three further checks are in the reader itself, so a member that is not one of
these tables cannot be mistaken for one: the four fields must account for the
member's length **exactly**, the start frames must begin at zero and ascend,
and every texture index must be inside the sheet it is read against. Walking
the archive backwards from the end, 25 members parse and the 26th does not,
which is the count the table of names says there should be.

The sequence **names** are pret's (`field_sprites.order`); every number is the
cartridge's. A sheet is matched to a sequence by texture count — 16 is
`generic_walk`, 32 is `walk_and_run` — with the player's own variants matched
by name first. The only other 16-entry sequences are `contest` and `fishing`,
and both produce **identical** cycles to `generic_walk`, so the ambiguity
cannot produce a wrong answer.

New file `src/import/Gen4Facings.lua`; the extractor writes `facings` onto
every sheet in `sprites.lua`; `SpriteRenderer.facingFrames` uses it when it is
there and **never mirrors**, because Platinum draws a real east side and
mirroring it would put the bag on the wrong shoulder. Gen 1, Gen 2 and Gen 3
take a byte-identical path — checked by running `poseFrame` over a six-frame
and a nine-frame def and comparing every slot.

### Fault 3 — "talking to npcs does nothing"

Two causes, and the second was hiding behind the first.

**`Gen2ScriptVM` was claiming Platinum's script pool.** Its ownership test was
a refusal list with one entry: `if pool.source == "RomExtractorGen3" then
return nil end`. It has to be a refusal list rather than an allow list, because
a Gen 1 cache and a hand-built developer pool both carry no `source` at all.
Gen 4 was simply missing from it. So the Johto VM lowered Platinum's decoded
instructions with Gen 2 semantics and attached the result to 478 maps as their
scene and coord-event wiring — which is what `gen2 script vm: 478 maps
attached (scenes)` in a Platinum log means, and it is a plausible source of the
warp-in-warp-out thrash also visible in that log.

**Nothing ever called `Gen4ScriptVM`.** `data/scripts/init.lua` has a Gen 2 arm
and a Gen 3 arm and had no fourth. Platinum's 4,079 decoded scripts sat in the
cache unlowered.

**And a Gen 4 object has no TEXT constant.** `OverworldState:talkTo` reads
`npc.def.text`; a Gen 4 object event carries a **script id**, an index into its
map's own entry-point list, and that list does not exist until the scripts have
been decoded — which is after the maps table has been written. Hence
`no text for Twinleaf Town/nil`: the field was simply not there.

`Gen4ScriptVM.bindObjects` stamps the link stage's own label back onto each
object record at registration time. Both halves derive the label from
`Gen4ScriptVM.label`, so they cannot drift; and it costs no rewrite of a
nine-megabyte maps table to add one string per object.

Measured on the current cache: **1,908** objects and signs take a label, 374
maps attach talk contributions, and Twinleaf Town's five scripted objects
lower to real rows (`M1052/S05D5` → 8 rows opening on `play_sound 1500`).

**A localId is not a key.** The link stage filed object scripts under the
object's `localId`, and the cartridge **reuses one inside a map**: 40 objects
across 28 maps share a localId with another object on the same map. Twinleaf
Town's arrow signpost, which carries the no-script sentinel, was answering with
the guitarist's dialogue. Filed by the event's position instead, which the maps
stage already writes onto the record as `index`, so both sides of the join name
the same thing. This is the third time in this port that a small integer used
as a key turned out not to be unique.

### Fault 5 — "the boxes surrounding the text are still too small"

This one survived the module-list fix, and it had to: the fallback layout in
`Gen4MainMenu` is character-for-character the cartridge's own numbers
(`optionX = 3`, `optionWidth = 26`, `firstY = 1`, `gap = 2`, `lineTiles = 2`,
`linePixels = 16`, `margin = 32` — `OPTION_WINDOW_WIDTH`,
`CONTINUE_WINDOW_MARGIN`, `TEXT_LINES_TILES` and `RenderOptions`' own
`nextOptionY` in `main_menu.c`). The numbers were right the whole time. They
were being drawn as the wrong rectangle.

**A Platinum window's frame is outside it.** `Window_DrawStandardFrame` →
`DrawStandardWindowFrame` (`render_window.c`) fills

```
x - 1 .. x + width      and      y - 1 .. y + height
```

— one tile beyond the window on every side — and `RenderOptions` advances by
`option->height + 2`, with the cartridge's own comment: *"Add 2 to account for
the window border"*. So the window the player sees is `(width + 2)` by
`(height + 2)` tiles, anchored at `(x - 1, y - 1)`.

`Font.drawBox` is the opposite convention: `sheetFrame` lays a `tw × th` grid
with the border on its outer ring, so the rect you pass IS the visible box.
Passing the cartridge's content rect straight through therefore drew:

| | drawn | the cartridge's |
|---|---|---|
| column width | 208 px, x 24–232 | **224 px, x 16–240** (centred on 256) |
| one-line option | 16 px tall | **32 px** |
| CONTINUE | 80 px tall | **96 px** |

Half the height on every one-line row, 16 px narrow, and off-centre. Fixed by
drawing `(optionX - 1, y - 1, optionWidth + 2, th + 2)` and putting the label
back at the content origin `optionX * 8`, which is where
`MainMenuUtil_ShowWindowAtPos` prints it. The CONTINUE summary moves with it:
its labels are at `+ CONTINUE_WINDOW_MARGIN` from the content origin and its
figures right-aligned at the same margin from the content's right edge, on
`TEXT_LINES(i)` — all three now literal rather than compensated with ±8 for a
frame that was in the wrong place.

Two things fall out and both are the cartridge's behaviour:

* **The vertical centring is gone.** It was added last round in answer to "the
  tiles are too small" — three short windows at `y = 1` sat in the top third
  and left the rest empty. At their real height they do not: CONTINUE plus
  NEW GAME, OPTION and EXIT is 0–96, 96–128, 128–160, 160–192 — exactly 192,
  the whole screen, at the cartridge's own `y = 1`.
* **The column scrolls instead of being cut off.** It can be taller than the
  screen on the cartridge too — CONTINUE alone is 12 tiles and the real menu
  has eight options, which is what Platinum's scroll arrows are for. The old
  code `break`ed at the bottom edge, which would make EXIT unreachable the
  moment a mod or a link row pushed it past 24 tiles. Now the selected window
  is kept on screen and anything wholly off either edge is not drawn.

**Full-screen was already right and is left alone.** Every one of the ten Gen 4
screens declares `uiSize() = 256 × 192`, `wantsFillScale() = true` and
`wantsEdgeBleed() = false`; `Game:draw` resolves the surface from the topmost
state that declares one (`nativeSurfaceInStack` → `Renderer:setUISize`, which
accepts anything between 160×144 and 640×576), and `Renderer:endFrame` honours
`uiFill` with `Up = min(ph / uih, pw / uiw)` — the window filled, aspect kept,
no integer-scale letterbox and no edge smear. On the reporter's 1024×768 that
is a scale of exactly 4 in both axes. So the menus are laid out in the DS's own
256×192 pixels and then scaled to fill the window, which is what was asked for;
what was wrong was the rectangle inside those pixels.

### Fault 4 — the cache has to be rebuilt to get any of the sprite work

`facings` is a new field on an existing file and the object-script key changed
shape. Neither adds a **file**, so `readyReport`'s missing-file gate cannot see
it. `CACHE_FORMAT` is bumped to `rom-cache-v338:`, which is the mechanism for
exactly this.

### Still open from this report

* **The world is drawing `TILESET_GEN4_STANDIN`** — flat colour per terrain
  class, which is the screenshot. The map meshes and textures are read (see
  above); the field renderer does not use them yet.
* **The Pokedex has no Gen 4 screen at all** — no `Gen4Pokedex.lua` and no
  `GEN4_ALIASES` entry, so `PokedexMenu` opens Kanto's. And a screen is not
  the next thing to build, because **the Pokedex art composes blank**. Checked
  pixel by pixel rather than by looking at the index: `scroll_main_background`
  is 256×192 of solid black, and `info_main`, `page_panel`, `banner_sinnoh`,
  `info_entry_window`, `info_species_window` and `info_footprint_window` are
  every one of them a single fully transparent colour. 275 of the 282 files
  under `pokedex/` are under 400 bytes. Every one of those records carries
  `borrowedPalette` or `borrowedTiles`, which is the composer saying it could
  not find the pairing — the same fault as the Poketch faces, one archive
  along. **Fix the composition before writing the screen**: a Gen 4 Pokedex
  drawn on this art would be a black screen where Kanto's at least shows
  something.

  The same check on the art the four working screens DO use says they are
  fine, which is what makes the contrast meaningful: `bag/bag_ui_main` has 25
  colours over 45% of its area, `summary/page_info` 16, `party/menu` 5,
  `trainer_card/badge_case` 10 over the whole panel, and `title/logo` 255.
  None of those is blank, so the module-list fix above puts real art on
  screen rather than exchanging Kanto's for black.
* **The start menu is still the engine's** — `push StartMenu` in the log. The
  two-style switch from the original brief is designed, not built.

## Boot to main menu: the cartridge's own sequence, frame by frame

Read out of `game_opening/ov77_021D25B0.c` and `applications/title_screen.c`
rather than from watching the game, so the numbers below are the cartridge's
and not an impression of them. This is the spec the port is built against; what
is built is marked.

### 1. The opening cutscene — `gOpeningCutsceneAppTemplate`

Three phases back to back, then a hold until frame **2430** (about 40.5 s at
60 fps), then it enqueues the title screen. **A or START at any point** sets
`unk_08`, clears `gSystem.showTitleScreenIntro`, fades both screens to black
and exits immediately — so a skipped opening also skips the title's own intro,
which is the detail that makes the two read as one sequence.

It draws out of `/demo/title/op_demo.narc`: **116 members — 16 map models,
4 texture sets, 33 tile sheets, 21 palettes, 24 tilemaps, 9 cell banks and 9
cell animations.** The models are a flythrough (`op_map01_00_00`,
`op_map02_00_00`, `titlemap05_20`, …), 500 to 2,100 triangles each, and they
carry no textures of their own — the four BTX0 members beside them are the
sets. **Not built. The archive is now extracted** (`MODEL_ARCHIVES` entry
`opening`), so the assets are in the cache and what is missing is the
camera track and the shot list.

### 2. The title screen — `gTitleScreenAppTemplate`

`TitleScreen_Main` is a seven-state machine:

| state | what happens |
|---|---|
| `INIT_RESOURCES` | loads the gfx; branches on `showTitleScreenIntro` |
| `SHOW_INTRO` | the eleven-state intro below — only when the opening ran |
| `INIT_SOUND` | `Sound_SetSceneAndPlayBGM(SOUND_SCENE_TITLE_SCREEN, SEQ_TITLE01_sseq)` |
| `MAIN` | blinks the text; watches for input |
| `EXIT_NORMAL` | A/START was pressed |
| `EXIT_REPLAY_OPENING` | nothing was pressed for 900 frames |
| `CLEANUP` | releases the gfx |

Coming **from** the opening, `showTitleScreenIntro` is true and the intro
plays. Coming **back** (from the main menu, or from the field's QUIT) it is
false, Giratina is already on screen, and **input is dead for 30 frames**
(`TITLE_SCREEN_INPUT_DISABLE_FRAMES`) so a held button cannot fall straight
through the title.

In `MAIN`:

* **A or START** → next app is the main menu; BGM fades over 60 frames;
  **Giratina's cry plays** (`Sound_PlayPokemonCry(SPECIES_GIRATINA)`); a blur
  effect is drawn; after `TITLE_SCREEN_EXIT_FADE_DELAY_FRAMES` (10) both
  screens fade to **WHITE**, not black; the app waits for the cry to finish
  before handing over.
* **B + UP + SELECT held** → the clear-save-file app. This is the erase
  combination the NEW GAME warning text refers to, and the port does not have
  it.
* **900 frames with no input** (`TITLE_SCREEN_REPLAY_OPENING_FRAMES`, 15 s)
  → `showTitleScreenIntro = TRUE` and the opening replays. The title is an
  attract loop, not a still.

### 3. The title intro — eleven states

`TitleScreen_ShowIntro`, in order:

1. `FADE_FROM_BLACK` — Giratina's layer on, fade in from black over 15 frames
   at step 3, then **hold 267 frames (~9 s) while the portal animation plays**
2. `WAIT_FOR_FADE` — counts that delay down, then arms **two white flashes**
3. `WAIT_AND_FADE_TO_WHITE` / `..._FROM_WHITE` — each flash is a 10-frame
   brightness ramp to white and a 10-frame ramp back, twice
4. `RESET_COUNTER`, `WAIT_AND_FADE_TO_WHITE_2` — a third fade OUT to white
   over 5 frames at step 2
5. `WAIT_AND_FADE_MAIN_FROM_WHITE` — the logo's BG2 layer on, **Giratina's
   animation starts**, main screen fades in from white over 16 at step 3
6. `WAIT_FOR_DELAY` — Giratina marked shown, main screen to black, 10 frames
7. `FADE_MAIN_FROM_BLACK` — Giratina's BG layer on, main fades in from black
   over **48 frames at step 1** — the slow reveal
8. `MOVE_IN_TITLE_CAMERA` — the title camera moves in over
   `TITLE_CAM_MOVE_IN_FRAMES`, then the logo layer comes on, the top-screen
   background loads, the SUB screen fades in from white over 16 at step 3, and
   the copyright and logo BG layers come on

Which is why the title is a *sequence* and not a picture: the logo and the
copyright are the LAST things to appear, after nine seconds of portal and a
camera move.

### What the port has, and what it does not

**Has.** The two panels and their measured content boxes, the logo fade
(`T_FADE`), the blinking prompt, and — as of this round — a footer band of the
title's own so PRESS START stops being drawn across the fourth copyright line.
That overlap was the visible fault in the last two screenshots: the comment
claimed the prompt sat "in the copyright strip where nothing else is", which
was true of the strip and false of the copyright, whose four lines are 56 rows
centred in it. Fourteen rows is exactly what the screen has spare —
122 (logo) + 56 (copyright) + 14 = 192 — so both panels keep every row they
need.

**Built this round.**

1. **Giratina.** `titledemo.narc` member 1 is `title_gira`: four shapes, 996
   triangles, its own TEX0, with a **121-frame joint animation** (BCA0) in
   member 2. Loaded by name — the model and the animation sit in different
   members and nothing but the name says they belong together, the same rule
   the starter case is loaded under — and drawn into a depth target of its
   own, because the UI surface has no depth buffer and 996 triangles without
   one come out inside out.
2. **The camera, at both ends.** `Gen4Model.lookAt` is new: `orbit` is the
   right shape for a turntable and the wrong one for a scripted shot, and
   Platinum's title camera is two POINTS that interpolate — eye
   (0, 192, 600) to (-64, 192, 484) over sixty frames, target fixed at
   (0, 100, -18), FOV 15.996 degrees. Checked by mapping both eyes through the
   matrix: each lands on the origin and its target on -Z at exactly the right
   distance.
3. **The eleven-state intro**, as a timeline of the cartridge's own delays --
   461 frames, 7.68 s. Every beat is a ramp between the picture and either
   white or black, so the whole sequence drives one signed `veil` number
   rather than a set of flags. Giratina's animation starts where
   `GIRATINA_ANIM_STATE_PLAY` is set (frame 327), not at the top; the logo and
   the copyright appear only when the camera move ends, which is what makes
   the title a sequence rather than a picture.
4. **The layer order is the cartridge's**: the field is the backdrop,
   Giratina draws into it, the logo goes over both --
   `ToggleGiratinaBgLayer` before the camera move and `ToggleLogoLayer` at the
   end of it.
5. **The attract loop** -- 900 idle frames and the intro replays.
6. **The 30-frame input lockout** on a title arrived at from the menu, so a
   held button cannot fall straight back through it.

One deliberate departure, marked in the file: **the cartridge does not let you
out of the title intro at all** -- only the opening cutscene before it is
skippable -- and a window the player has just come back to is not an attract
cabinet, so A or START during the intro jumps to the end of it.

**Still missing.**

1. **The opening cutscene**, its camera track through the sixteen map models.
   The archive is extracted (`MODEL_ARCHIVES` entry `opening`); the shot list
   is not written.
2. **`op_ana` and `op_kao`** -- the portal (240 frames) and the face (174) are
   extracted and not yet drawn, so the nine-second portal hold is currently
   nine seconds of Giratina alone.
3. **The erase combination** -- B + UP + SELECT. Left for its own pass rather
   than bolted on: it destroys a save file, and the cartridge's confirmation
   screens are part of the feature rather than decoration around it.
4. **Giratina's cry and `SEQ_TITLE01_sseq`**, which need the audio stage that
   does not exist for Gen 4 at all.

## Boot to the bedroom: the whole chain, and what runs

The app chain, read out of `game_start.c`, `main_menu.c` and
`applications/title_screen.c`:

```
  opening cutscene  gOpeningCutsceneAppTemplate     NOT BUILT
        |             3 phases, holds to frame 2430 (~40 s)
        |             A/START skips it AND clears showTitleScreenIntro
        v
  title screen      gTitleScreenAppTemplate         BUILT (intro, Giratina,
        |             7 states, 11-state intro       attract loop, lockout)
        v
  main menu         CONTINUE / NEW GAME / OPTION    BUILT
        |  NEW GAME
        v
  StartNewSave      gGameStartRowanIntroAppTemplate BUILT (SaveData.newGame)
        v
  Rowan's intro     gRowanIntroAppTemplate          NOT BUILT -- 112 states
        v
  InitializeNewSave gGameStartNewSaveAppTemplate    partly (no PlayTime start)
        v
  the field         gFieldSystemNewGameTemplate     BUILT -- the bedroom
```

### The 112 states of Rowan's intro

`enum RowanIntroState`, in order, because "the intro is missing" is really
this list:

1. **The TV**, with its CRT overlay drifting — `RowanIntroTv_*`, a sibling app
   in the same folder, and the "tv screen" reported missing two rounds ago
2. fade from black; Rowan fades in and speaks
3. a choice box offering the **control info**; its pages, the X/Y icons, the
   DS icon, and a yes/no that can repeat
4. the **adventure info** — six screens of text
5. "widely inhabited"
6. the **Poké Ball**: pushed in, four flashes, the Pokémon spawns, rises,
   bounces down, and is put away — **built**; see *The release, frame by
   frame*
7. "about yourself"
8. the **gender choice** — both avatars fading and centring, with a confirm —
   **built**; see *The gender choice, and the four poses that were a run
   cycle*
9. the player's **name**: dialogue, keyboard, confirm
10. "so you're"
11. the **rival**: tilemap swap, a name choice box with presets, keyboard,
    confirm
12. Rowan's closing lines, then the **avatar shrink** that hands over to the
    field

`gen4_intro` is extracted and carries the backdrops, the figures, the rival
names, the control info and the adventure info. `Gen4RowanIntro` reads it and
plays the main line, the release (6) and the gender choice (8); the two
lectures (3, 4) are deliberately not offered, and the closing avatar shrink
(12) is not built.

## The release, frame by frame

Reported from play: *"in the intro rowan isnt thorwing out a pokemon like he
does in the rom"*. He does, and the port did not — the step was not in the
script table at all. Text id 17, `havePokeBall`, was extracted and never read.

**It is a Buneary**, and that answer costs nothing to act on:
`RowanIntro_LoadBunearySprite` builds an ordinary `PokemonSpriteTemplate` for
`SPECIES_BUNEARY`, `FACE_FRONT`, so the picture is the species' own battle
front sprite — already in this cache since the species-sprite stage. Nothing
had to be extracted for the Pokémon itself.

**The ball is three pictures, not one.** `/demo/intro/intro.narc` members 32,
33 and 34 are loaded into the same place in turn over one tilemap (40) and one
palette (41): that is the button being pushed in. The animation is not a
transform of the art — it *is* three pieces of art, which is why treating it as
one and moving it would have produced something that looked deliberate and was
wrong. Those three are now extracted as `intro/ball_0..2`.

**The palette is the third row of member 41**, and nothing states it: the app
loads three rows of that member starting at background row 7 and then points
the tilemap's cells at row 9. So the ball's sixteen colours are member 41's
colours 32–47. Composing with its first sixteen gives a picture, and a wrong
one — this archive's standing hazard.

**The flash is four brightness ramps.**
`BrightnessController_StartTransition(stepCount, target, start, …)` puts the
*target before the start*, which is exactly the argument order a reader assumes
and gets backwards. The calls are `(1, 16, 0)`, `(1, 0, 16)`, `(4, 16, 0)` and
then `(16, 0, 16)` as the Pokémon spawns: white in one frame, out in one, in
over four, and out over sixteen *while the Pokémon is already on screen*. Its
plane mask is BG0|BG1|BG3 and the Pokémon is on BG2 — so the flash deliberately
does not whiten it. Its palette is blended toward `0x6a3c` (BGR555 28, 17, 26 —
a pink-white) with weight `counter / 3` out of 16 counting down from 48, so it
is a solid silhouette for three frames and has its colours back after
forty-eight.

**The arc is a parabola in integer arithmetic**, three phases of

```
y = base + coeff * 9 * t - floor(9 * t * t / divisor)
```

ending the first frame `y` comes back down through zero having been positive,
at which point the app *snaps* the offset to zero rather than letting the
integer arithmetic land where it will — which is why it finishes exactly on the
ground each time. A background offset is not a position: the hardware scrolls
the view, so a larger offset moves the picture **up**, and every reader is
`MON_Y - offset`.

Reimplemented and checked against a trace of the C, the three phases come out
at 17, 9 and 9 frames, and the sprite's screen position walks

```
(82,176) (81,124) (80,86) (79,52) (78,23) (77,-2) … (72,-58) … (65,72)
(67,72) (69,48) (71,30) (73,18) (75,12) (77,12) (79,18) (81,30) (83,48) (83,72)
(79,72) (75,48) … (47,48) (47,72)
```

— rise, settle, hop right, hop left. Every number is the app's.

**The port has one screen and the cartridge has two, and here that costs
something.** Before the arc, the app spends three frames moving a *second* copy
of the Pokémon up the **bottom** screen; the arc then plays on the top one,
starting from below its own screen. On hardware that reads as one continuous
rise across the gap. On one screen it is the same motion twice — the Pokémon
would leave upward and re-enter from below — so the port keeps only those three
frames' horizontal drift and plays the arc, which already begins off the
bottom. That is a port decision, stated rather than smuggled.

The whole step, measured in a harness that runs the real file against stubbed
graphics: 11 frames of push-in, 6 of flash, 38 of arc, 40 of settle, then the
"they live alongside us" line, then a 16-frame fade and a 30-frame pause. Rowan
is never faded out for any of it — on hardware he is simply on the other screen
— so the ball covers him while it is pushed in and he is back underneath the
moment the Pokémon is out.

The tint is two draw passes rather than one, because multiplying a sprite by a
colour can only darken it and the cartridge is *replacing* its palette: a
scaled-down normal pass plus an additive glow pass gives
`pixel * (1 - w) + glow * w` exactly, with the sprite's own alpha as the mask
both times.

## The gender choice, and the four poses that were a run cycle

Reported in the same message: *"the players sprites when selecting boy or girl
arent animated like they should be"*.

`Gen4IntroScene` already extracted `boy_1..boy_4` and `girl_1..girl_4` and
described them as four poses of the same character. They are not poses. They
are a **four-frame run cycle**: `RowanIntro_AnimateAvatarRun` cycles the
selected side through intro members 9, 10, 11, 12 (boy) or 14, 15, 16, 17
(girl), five frames each — and those are exactly the members the figure table
already names. **Nothing had to be added to the cache to play it; the data was
right and the reading of it was wrong.**

The rest of the screen follows from the same function:

* **Both avatars are on screen at once.** The boy's layer is offset −48 and the
  girl's +48, and an offset moves the picture the other way, so the boy stands
  48 pixels *right* of centre and the girl 48 *left*. The old port showed one
  at a time and called that the honest version of two buttons; it was a guess,
  and the cartridge's answer was sitting in those two offsets.
* **Only the selected one moves.** The other holds whatever frame it is on and
  is blended to 6/16 (`G2_SetBlendAlpha(…, 6, 10)`), which is what makes one of
  them read as chosen.
* **On confirm the other fades out** over sixteen frames and the chosen one
  slides back to the middle four pixels a frame — twelve frames from either
  side — and then the confirm line and a YES/NO box. NO fades the chosen one
  out and brings the pair back, which is why `{YESNO 0}` is stripped from the
  text upstream: the box is drawn, not printed.

Measured in the same harness: 32 frames of fade-in (one each), the run cycle at
`2,2,2,2,2,3,3,3,3,3,4,4,4,4,4,1,…`, 16 frames of fade-out, 12 of centring, and
the NO path returning to the start with the spread reset.

Still not built from this list: the **control** and **adventure** lectures,
which are extracted and deliberately not offered — they describe a touch screen
and a +Control Pad the player is not holding — and the **closing avatar
shrink** that hands over to the field.

**`CACHE_FORMAT` is now `rom-cache-v340`**, because the ball art is a new
extraction output: a Platinum cache has to be re-imported before the ball
appears. The release plays without it — the Pokémon is the species' own sprite
and does not come from that archive — so an old cache gets the sequence with
Rowan's backdrop where the ball should be, rather than nothing at all.

## The world: the ground pipeline, measured end to end

`TILESET_GEN4_STANDIN` is what the player sees, and the reason is not that the
data is missing. Every piece is in the cartridge and every piece reads. This
section is the measurement, chunk by chunk, so the renderer can be built
against numbers rather than against hope.

### The chain, and what each link answers

```
map header  --areaData-->  area_data.narc  --mapTexture-->  map_tex_set.narc
     |                                                            |
     +--matrix--> map_matrix.narc --> land_data.narc member  <-----+
                                        |         |        |
                                  permissions   NSBMD    BDHC
```

**land_data.narc: 666 members, and all 666 carry both a mesh and a BDHC.**
Nothing is optional here, which the earlier note ("three of the four blocks
are routinely empty on indoor chunks") got wrong for the two that matter.

**All 666 meshes decode.** `Gen4Nsbmd.parse` returns a model set, not a model
— the chunk's mesh is `set.models[1]` — and chunk 0 comes out as 19 shapes
against 19 materials whose texture names (`conttree_b`, `hage`, `imped`) are
real. Across the archive that is **7,547 shapes**, 13.6 MB of NSBMD.

**All 666 pack and unpack unchanged.** `Gen4ModelPack.pack` followed by
`verify` — the same round trip the starter models go through — is **0 failures
in 666**, 17.7 MB of packed geometry, 7.9 seconds to read and pack the lot. So
the geometry can go into the cache in the form the renderer already draws.

**A chunk's local origin is its CENTRE.** `posScale` is 32 and chunk 235's
vertices run x = −8..5, so world units are `value * posScale` and the chunk
spans −256..+256 of its 512-unit square. Reading it as 0..512 puts seven
eighths of the mesh off the edge — 236 triangles of 2,667 landed before this
was fixed, which is the sort of error that looks like a broken decoder and is
arithmetic.

**All 3,130 map textures decode**, which they did not before: 198 A3I5 and 40
A5I3 — 7.6% — were being skipped, and they are the shadows, the water edges
and the cloud layers, so the missing tenth was the tenth you notice. Both are
one byte per pixel split between a palette index and an alpha (five bits of
index under three of alpha; three under five), added as
`Gen4Models.ALPHA_FORMATS`. The proof they are right is that the alpha is
PARTIAL: `area4_gate_b` comes out with 176 semi-transparent pixels and `elev_e`
with 217, where a wrong split gives all-or-nothing.

**And it draws.** Chunk 235 with texture set 28, rasterised top-down at one
pixel per world unit with a height buffer, is a Battle Frontier interior:
Poké Ball arena floors, the rope runs, the benches, the sand outside. That is
Platinum's own ground art, from the cartridge, in one 512×512 image. Nothing
in the pipeline is unproven any more.

### Which texture set a chunk wears: settled, and it is exact

A chunk's mesh names its textures; it does not say which of the 74 sets to
look them up in. The header does — `areaData` → `area_data.narc` (75 records,
8 bytes) → `mapTexture`.

Asked the wrong way first, and the wrong way is worth recording because the
number it produced looked like a real gap. Taking every map header, then every
cell of its whole matrix, and asking whether the header's set holds that
chunk's texture names gives **32,307 of 40,333 pairs, 80.1%** — and the
failures all cluster on the Sinnoh overworld, one header with a 30×30 matrix
whose single area record obviously cannot cover 900 chunks. The question was
wrong: that header does not OWN most of those cells.

**A matrix says who owns each cell.** `Gen4Maps.extents` already reads the
`headers` block for its bounding boxes — one header id per cell, zero where
nothing claims it — so the right question is per cell, of its owner. Asked
that way:

* **175 of 175 owned cells resolve. 100%.**
* 745 cells name no owner, and those are textured by whichever map the player
  is standing in, which is the answer the cartridge gives too.

So there is no attribution gap. The 80.1% was an artefact of asking every
header about cells it does not own, and the figure quoted before that
(729 of 867) was a third measurement again; none of the three were comparable
and only this one asks the cartridge's own question.

### The stage, built

`src/import/Gen4Terrain.lua` and a `terrain` stage, measured on the cartridge:

| | |
|---|---|
| chunks packed and verified | **666 of 666, 0 refused**, 7,547 shapes |
| packed geometry | 17.7 MB, 8.5 s |
| BDHC heights | 301 KB, in the cartridge's own form |
| texture atlases | **74 of 74, 0 textures undecoded**, 16.7 MB raw, 1.2 s |
| matrices gridded | 289, 1,604 chunk cells |

Three decisions worth stating.

**The geometry is a side-car binary.** 17.7 MB of packed vertices and indices
is nearer 50 MB as escaped Lua source and would add minutes to every cache
load. `CacheFs.write` takes raw bytes — it is what every PNG already goes
through — so `terrain/chunks.bin` and `terrain/heights.bin` are files and
`gen4_terrain.lua` is an index of offsets into them.
`RomExtractorGen4:saveBinary` is the second half of `ImageWriter.save` with the
encoder taken out.

**The atlases are trimmed to what they hold.** Every set packs into the same
512-wide sheet, tallest texture first with ties broken by NAME so a rebuild
from the same cartridge produces the same file — then the empty shelves below
the last one are cut off. The smallest set is 36 textures on two shelves; a
full-height sheet for it was ten times the pixels for nothing, and trimming
took the 74 sets from 74 MB to 16.7 MB.

**No pictures are baked at import.** A chunk is drawn top-down into a canvas at
run time, once, the way `Gen3Tiles` already bakes its metatile sheets — so the
cache carries the mesh and the textures rather than 666 rendered images that
would have to be re-rendered the first time the camera moved anyway.

`CACHE_FORMAT` is `rom-cache-v339`, because the terrain's files are new but
live under `assets/` and behind a new module, so the missing-file gate cannot
see them either.

### The renderer, built

`src/render/Gen4Ground.lua`, and one guarded branch at the top of
`TileRenderer:drawWindow`. Nil for every other generation and for a Platinum
cache imported before the terrain stage, so everything below that branch is
untouched and still runs when the ground is absent.

**A chunk is baked once, top-down, into a 512×512 canvas**, and the canvas is
what the map draws. That is not a shortcut around a 3D view: it is what
`Gen3Tiles` already does with its metatile sheets, for the same reason — the
geometry does not change, so rasterising it every frame is work repeated to
arrive at the same picture. When a real camera exists the meshes are already
here and this becomes the flat case of it.

**One pixel per world unit**, which is what makes the rest line up: a tile is
16 units and the engine draws tiles at 16 pixels, so the collision grid, the
warps and the sprites land on the ground with no second scale to keep in step.

**The projection is orthographic and checked**: `topDown(256)` maps the
chunk's north-west corner to clip (−1, +1) and its south-east to (+1, −1) with
w = 1 throughout, and ground 84 units up comes out at clip z −0.0205 against
the floor's 0 — so with the depth test on `less` the hill wins, which is the
whole reason the bake needs a depth buffer.

**No nodes and no pose, and that is measured.** A model's shapes are placed by
the matrix slot each is bound to, and across all 666 chunks — **7,547 shapes —
every one is bound to slot 0**. Thirty-three chunks do carry more than one node
and 207 node matrices are not the identity, so the nodes are not absent;
nothing places a shape with them. The vertices are already in the chunk's own
space.

**The store is read in ranges, not whole.** `File:seek` plus `File:read` is the
difference between 17.7 MB resident for every Platinum session and the few
hundred kilobytes a map actually touches. Sixteen baked chunks are kept, oldest
evicted first — a player walks in one direction, so the chunk longest unused is
behind them — and at most one chunk is baked per frame, because baking four at
once on a map entry is a visible hitch.

**An atlas was tried and rejected**, which is why the stage writes 3,130
individual texture PNGs (12 MB raw, 0 undecoded) rather than 74 sheets. A map
texture is TILED: a chunk's UVs run from about −196 to +228 texels on a
64-texel picture, the same grass laid down seven times. That needs a sampler
set to repeat, and a sub-rectangle of an atlas cannot repeat — the wrap applies
to the whole sheet, so every tiled face would smear its neighbours across
itself. `Gen4Model.new` already loads a shape's texture by path and already
sets `repeat` on it, so the honest version costs a file count and no code.

### The height under the ground, read

`Gen4Ground:heightsAt(tileX, tileY)` -> a list of world heights, highest
first, in the same map tile coordinates collision and the events use. A list
rather than a number, and the measurement is why.

Over all **681,984 tile centres in the cartridge**, with all 666 BDHCs parsed
(0 refused, 8,974 plates between them):

* **76.4%** have a plate under them
* **0.48% have more than one, up to four deep** — the bridge case, and the
  reason a single number would be wrong
* about **14% of walkable tiles have none**, and that is not a gap: a tile with
  no plate is flat ground at the chunk's own base

**It walks every plate rather than using the scanline index, and that is a
correction.** The BDHC carries a strip index for finding plates quickly.
Checked against brute force over 98,304 tiles it agrees on **99.59%** and
**drops a plate on 404 of them — never the other way round**. Thirteen plates
per chunk is nothing to walk, and a height that is silently absent four times
in a thousand is a player falling through a bridge. The index stays in
`Gen4Bdhc` (`heightsVia`) and is not what the ground asks.

The two-table check that did NOT come out clean is worth recording as well: the
permission grid's blocked bit and "has a plate" agree on only 51% of tiles.
That is the right answer rather than a fault — 37% are blocked *and* have a
height, which is exactly what scenery you can see and not walk on looks like,
and the plates cover the mesh rather than the walkable area — but it means the
permission grid cannot be used to verify the height field, and a check that
looked like one would have been worse than none.

### The bit this project had been calling "void"

That paragraph used to say *void bit*, and so did `Gen4Maps`, and both were
wrong about what the bit means. The behaviour was right by luck — "not part of
the map" and "you cannot stand here" both make a tile impassable — but the
**name** sent every later reader looking for a wall table that does not need to
exist. It is why this file carried a standing caveat reading *"which of the 54
behaviour values are walls is NOT established ... a player dropped into one of
these maps would walk through fences."* **That caveat was false.** Fences carry
the bit and already block.

`TERRAIN_ATTRIBUTES_COLLISION_MASK` is `0x8000` and
`TerrainCollisionManager_CheckCollision` reads that bit and nothing else. Then
measured against this cartridge's own 681,984 tiles, three ways that cannot
borrow from each other:

* **335,165 tiles have it set — 49.1% of Sinnoh.** Half a region is not
  missing. That is walls, cliffs, building footprints and sea.
* **The per-chunk share is spread across every decile** — 88 chunks under 10%,
  107 at 10–20%, 101 above 90%, and every band in between occupied. "Off the
  map" would be bimodal: a chunk is either land or it is not. Per-tile
  collision is not.
* **26 behaviour values occur both blocked and open.** A tile that is not part
  of the map does not also carry a behaviour that is walkable elsewhere, so the
  bit is an independent fact about the tile rather than a consequence of what
  the tile is.

And the rest of the high byte carries nothing: **bits 8–14 are clear on every
one of the 681,984 tiles**, and the highest word in the cartridge is `0x80E5`.
So a permission word is exactly a collision bit and a behaviour byte, and the
behaviour byte says what a tile *is* — grass, water, a doorway — not whether
you may stand on it. There are **94** distinct behaviour values in this
cartridge, not 54.

`Gen4Maps.COLLISION` and `Gen4Maps.blocks` are the names now; `VOID` and
`isVoid` remain as aliases so nothing that reads them breaks. **No cache output
changed** — the map def's bytes are identical — so this needs no re-import; it
closes an open item and removes a false one.

The elevation field is still zero, and that one is a real gap: the BDHC is
parsed (`Gen4Ground:heightsAt`) and nothing writes it into the grid, so a
bridge and the path under it are one cell.

### The white overworld, and the two numbers behind it

Reported from play, with a screenshot: *"the overwolrd still isnt right its
appearing as white mostly with some weird tiles in one area"*. One picture, two
independent faults, and neither of them was in the geometry — the chunks that
did draw drew correctly.

**The white was an early return.** `TileRenderer:drawWindow` opened with

```lua
if self.gen4Ground and self.gen4Ground:draw(camX, camY, vw, vh) then
  return
end
```

The intent was reasonable: the Gen 4 ground IS the map's picture, so there is
no point building the stand-in tile batch underneath it. The flaw is in the
word **any**. `Gen4Ground:draw` returns true when it drew *something*, and a
screen holds up to four chunks while `BAKES_PER_FRAME` was **one** — so on a
map entry the first chunk baked, reported success, and the early return
cancelled the stand-in for the other three, which had nothing of their own yet.
The result is exactly the screenshot: one region of real ground, and white
everywhere else, because white is what is left when nothing at all is drawn.

The fix is to stop treating the two as alternatives. The stand-in costs one
batch draw and is already built; it now draws first and the real ground draws
over whatever is ready:

```lua
self:drawAnimated(camX, camY)
if self.gen4Ground then self.gen4Ground:draw(camX, camY, vw, vh) end
```

A floor under the picture rather than a replacement for it, and the screen can
no longer be empty. `BAKES_PER_FRAME` went 1 → **4** as well, so the visible
set is ready after one frame instead of four: a map entry pays one hitch and
then nothing.

**The striped region was z-fighting, and it was a precision choice made
carelessly.** `DEPTH_RANGE = 4096` was a first guess picked for headroom. It
maps the whole height field into the depth buffer, and Platinum's heights span
tens of units, not thousands — so nearly every surface in a chunk landed in a
sliver at one end of the range. Two near-coplanar surfaces (a floor and the mat
on it) came out a couple of millionths apart in clip space, which is inside the
depth buffer's resolution, and a depth buffer that cannot separate two surfaces
shows alternating rows of each. That is the striped teal.

`DEPTH_RANGE` is now **1024** — still far past anything the cartridge has
(Mount Coronet is hundreds), with four times the resolution to tell two floors
apart. **Headroom taken "just in case" is not free; in a fixed-point buffer it
is paid for in precision you were using.**

### What is left

1. **Wiring the height into movement.** The query is built and nothing calls
   it: the player still walks a flat plane. That is the engine's elevation
   concept, not the extractor's, and it needs the "which surface am I on"
   choice the multi-plate tiles exist for.
2. **The field animations** — and what they animate is not what this file used
   to say. See *What `bm_anime` actually animates* below.
3. **Buildings — built.** See *The houses on the ground* below.

## The Pokédex, and the composition that could not be expressed

The last screen on the reported fault list — *"neither is the pokedex, or the
pokemon party menu or the bag theyre looking like gen1 still"*. The other two
were fixed by the module list. This one was left alone on purpose, and the note
saying so was right: **the art composed blank**, and a Gen 4 Pokédex drawn on it
would have been a black screen where Kanto's at least showed something.

### Why it was blank

Not a decoder bug. `zukan.narc` does not name its parts to match. The palettes,
the tile sheets and the tilemaps are three separate name spaces, and a handful
of sheets and palettes serve dozens of tilemaps: **`info_main.NSCR` has no
`info_main.NCGR` and no `info_main.NCLR` anywhere in the archive.** Grouping by
base name — which is exactly right for every other screen archive — gives it a
tilemap with no tiles and no colours, so it borrows the archive's first of each
and paints nothing. Hence 275 of 282 pictures under 400 bytes, every one
carrying `borrowedTiles` or `borrowedPalette`.

And the entry page is not one tilemap. It is **four**, laid into one 32×24 grid.
`ov21_021E96A8` is the whole of it in a single function:

```
Graphics_LoadPaletteFromOpenNARC(narc, banner_sinnoh_NCLR, 0, 0, 0)
Graphics_LoadTilesToBgLayerFromOpenNARC(narc, entry_main_NCGR_lz, bg, 3)
info_main.NSCR             -> rect (0,  0)
info_species_window.NSCR   -> rect (0,  3)
info_footprint_window.NSCR -> rect (12, 8)
info_entry_window.NSCR     -> rect (0, 16)
```

**The palette is `banner_sinnoh.NCLR`** — the entry page's colours are filed
under the banner, which no amount of looking at names would have produced.
`info.NCLR` exists and is a *sprite* palette for the page buttons. Pairing
`info_main` with `info` would give a picture, and a wrong one.

### Checked three ways

A wrong member index in an archive like this still decodes, so the pairing is
checked against three tables that cannot borrow from each other:

1. `res/graphics/pokedex/pokedex.order`, the file pokeplatinum's build feeds its
   archiver, gives the indices: 6, 24, 33, 50, 51, 52, 54, 57.
2. The name table this port already carries in `Gen4Archives` agrees with every
   one of them, index for index.
3. The **rect sizes** are checked against the widths and heights the graphics
   stage already recorded for those five members: `info_main` 32×24 at (0,0),
   `info_species_window` 12×12 at (0,3), `info_footprint_window` 6×6 at (12,8),
   `info_entry_window` 32×8 at (0,16) — which ends exactly on the bottom row.
   Every rect fits inside the screen and the two full-width ones *are* the
   screen.

Members are looked up **by name** at extraction time; the indices are recorded
so a reader can check the claim rather than take it.

### `Gen4Graphics.stamp`, and what it says about the planner

The missing capability was one function: lay one tilemap into another at a tile
offset, which is `Bg_LoadToTilemapRect`. Cells carry their own tile index, flip
bits and sub-palette, so a stamped grid composes exactly like any other tilemap.
Anything that would land outside the base is **dropped rather than wrapped** — a
rect that does not fit is a wrong offset, and wrapping would hide it. Verified
against a hand-computed coverage: 332 + 144 + 36 + 256 = 768 cells, no overlap
unaccounted for, and an out-of-bounds stamp clipped rather than wrapped.

The new `dex` stage does not replace the graphics stage. It adds the
composition the planner cannot express and leaves the per-member pictures alone,
so nothing that reads them today changes.

### Height, weight and category are STRINGS

The species table carries none of the three, and the art has slots for all
three. Platinum does not store them as numbers: height, weight and the category
line are one **pre-formatted string per species**, which is why `infomain.c`
renders them with a `MessageLoader` and no formatting of its own. Banks 709,
707 and 711; the "HT" and "WT" labels are entries 9 and 10 of bank 697.

Those bank ids come from pokeplatinum's `generated/text_banks.txt`, whose
zero-based line numbers *are* the cartridge's bank ids — checked against every
bank this project had already found by looking: 202 nature, 391/392 item,
619/620 trainer class, 646/647/648 move, and 706, which that list names
`TEXT_BANK_SPECIES_POKEDEX_ENTRY_EN`. **Nine out of nine, so the tenth is not a
guess.**

### The screen

`Gen4Pokedex`, with the `PokedexMenu` alias that had never existed. Two pages:
the list, and the entry that A opens. Every position on the entry page is a
literal out of `infomain.c` — the sprite at (48, 72), the name and number at
(172, 32), the category box's text at (114, 44), HT at (152, 88) with its value
at (184, 88), WT at (152, 104)/(184, 104), and the entry text centred on x = 128
at y = 136, dropping to x = 8 when it is wider than 240, which is the
cartridge's own overflow rule rather than a clamp invented here.

**The list page is this port's**, and says so: `scroll_main_background` and the
scroll wheel are a third composition again — a wheel of sprites over a scrolling
background — and are not composed. So is the **Sinnoh dex order**
(`/poketool/pl_pokezukan.narc`, not extracted), which is why the listing is
national order only; for Gen 4 that needs no sort at all, since Platinum numbers
its species 1..493 in national order and the species id *is* the number.

`CACHE_FORMAT` is now **`rom-cache-v342`**.

## The keyboard, part two: the archive nobody had opened

The section below fixed the alignment. It did not fix the screen, and the
reason is worth stating on its own: **every number in it was invented.** The
grid was 13×6 on 16-pixel square cells at (24, 64) because that fitted; the
boxes were the engine's; the home row was inside the grid. All of it was
self-consistent and none of it was Platinum's, because `/data/namein.narc` had
never been opened.

It is open now, as `Gen4Naming` plus a `naming` extraction stage, and the
screen is rebuilt on what it says.

**The archive has no name table**, like the intro's, so every member index is
arithmetic — and arithmetic is what this project has been burned by most. None
of it is inferred. The order comes from
`res/graphics/naming_screen/naming_screen.order`, the file pokeplatinum's build
feeds its archiver, which reproduces this cartridge byte for byte; every index
is then cross-checked against the symbol `NamingScreen_LoadGraphicsFromNarc`
uses for it. **Two independent statements of the same fact** is the only kind
of check worth having in an archive where a wrong index still decodes.

| member | what |
|---|---|
| 0 | `naming_screen.NCLR` — the background palette |
| 2 | `naming_screen_main_tiles.NCGR` — tiles for both backgrounds |
| 4 | `naming_screen_bg.NSCR` — the full-screen backdrop |
| 6–9 | `naming_screen_chars_bg_0..3.NSCR` — one keyboard panel per page |
| 10, 12, 14 | the sprite sheet, cell bank and animations |

### What the cartridge actually does, against what the port had

* **The panel's position is a background offset, not a coordinate.**
  `NamingScreen_InitializeCharsPosition` parks the active layer at (−11, −80).
  The hardware scrolls the *view*, so −11 puts the picture eleven pixels to the
  **right**: the panel sits at screen (11, 80).
* **The character grid is 13 × 5, not 13 × 6, in cells 16 × 19, not 16 × 16.**
  `Window_Add(…, BG_LAYER_MAIN_1, 2, 1, 26, 12, 1, …)` gives the rectangle —
  tile (2, 1), 26 × 12 tiles, palette row 1 — and
  `NamingScreen_InitializeCharsGraphics` gives the pitch: **five**
  `PrintChars` calls at `i * 19 + 4`, spacing 16. Twenty-six tiles is 208,
  which is thirteen columns of sixteen; twelve tiles is 96, which is five rows
  of nineteen with a pixel over. So the grid's origin is (27, 88) and nothing
  about it had to be chosen.
* **The home row is not in that window at all.** It is six sprites at
  `y = 0x44` and `x = 4, 36, 68, 101, 136, 176`. Six buttons — which is the six
  the navigation model already had, and their spacing *confirms* that model
  rather than merely being consistent with it: laid out from x = 4 on the
  keyboard's own 16-pixel pitch at spans 2, 2, 2, 2, 3, 2, they would start at
  4, 36, 68, 100, 132, 180. Against the cartridge's anchors that is exact on
  three and within 1, 4 and 4 pixels on the rest — the difference being that a
  sprite's x is its art's anchor, not its cell's edge.
* **The keyboard is a checkerboard, and it is painted by code.** Two palette
  indices per page — `sCharsBgColor = {4, 7, 13, 10}` and
  `sCharsAltBgColor = {3, 6, 12, 9, 9}` — with 16×19 rectangles over the odd
  columns of rows 0, 2, 4 and the even columns of rows 1, 3. **Extracting the
  pictures alone would have produced a frame with nothing inside it**, which is
  exactly the kind of half-answer that looks finished. The stage therefore
  carries the window's palette row out of the cache as sixteen colours, because
  the two the checkerboard uses are indices into it and nothing else in the
  cache can resolve them.

### The consequence for the section below

The nineteen-pixel row is why the "every number is a multiple of eight" fix
could only ever be a patch on a guess. `Font.drawBox` takes tiles and the
cartridge's rows are not a whole number of tiles, so the choice was between
rounding the layout to suit the drawing or drawing in pixels. **Rounding the
layout to suit the drawing is what made it wrong in the first place**, so the
tile boxes are gone: the frames are drawn in pixels and nothing rounds.

### Still not the cartridge's

The home row's **button art** and the **cursor**, both in the sprite cell bank
at members 10/12/14. Composing a cell bank is a different job from composing a
tilemap, and until it is done the buttons are the engine's frames at the
cartridge's own positions — with short words on them (`A-Z`, `a-z`, `SYM`,
`SPC`, `BACK`, `OK`) that are the port's, because the cartridge's buttons are
wordless pictures and something has to be written. They are short because a
label that does not fit its own button is the fault this screen was reported
for.

The **prompt and the typed name** are the bottom screen's on hardware — the
keyboard is the top screen and `LoadMessageBoxGraphics` puts the message box on
`BG_LAYER_SUB_0`. With one screen they go above the keyboard, and those two
positions are the only ones on this screen that are still the port's.

`CACHE_FORMAT` is now **`rom-cache-v341`**.

## The keyboard, and boxes measured in two different units

Reported from play: *"the keyboard for gen3 still needs a lot of work before it
matches the platinum rom text is outside of boxes etc"*. (Gen 3 in the report;
the screen is `Gen4NamingScreen`, reached from the Gen 4 new-game flow.)

The layout was right — six rows of thirteen, the home row's repeated buttons,
the three English pages, all read out of `naming_screen.c`. What was wrong is
that it was expressed in **two units at once**. `Font.drawBox` takes TILE
coordinates; `Font.draw` takes PIXELS. The grid was laid out on 20-pixel rows
starting at y = 62, so every box was rounded to a tile and every label was not:

```lua
Font.drawBox(math.floor(y / 8), ...)   -- 62 / 8 -> 7, i.e. 56 px
Font.draw(label, x + 2, y + 4)         -- 66 px
```

Ten pixels of drift on the home row, and more further down, because the error
compounds with every 20-pixel row against an 8-pixel grid. The `math.floor`
calls are what made it look deliberate; they were rounding away the evidence.

**The fix is not to nudge the text.** A box can only land on a multiple of
eight, so the layout has to be made of multiples of eight — then both units
agree and no rounding happens at all:

| | was | now |
|---|---|---|
| `GRID_Y` | 62 | **64** (tile 8) |
| `CELL_H` | 20 | **16** (2 tiles) |
| `TITLE_Y` | 10 | **8** |
| `ENTRY_Y` | 34 | **32** (tile 4) |

Thirteen 16-pixel columns from x = 24 is tiles 3 → 29 of 32; the home row is
tiles 8 → 10 and the five character rows are tiles 10 → 20 of 24. Every
`math.floor` in the drawing code is gone, because there is nothing left to
round. A `GLYPH_INSET` of 3 centres a 12-pixel glyph in a 16-pixel row.

Three smaller things came out of the same read:

* **The selection was a `">"` prefix** on the label, which pushed every home-row
  word one glyph right — out of its own button, and on the longest labels out
  of the screen's share of it entirely. So the marker that was supposed to show
  where you are was itself putting text outside the boxes. It is a **highlight
  drawn behind the cell** now, and the label no longer moves. Labels are also
  clipped to their own button's width rather than running into the next one.
* **The character cursor drew on top of the letter it was pointing at** —
  `Font.drawCode(Theme.cursor, x, y)` in the same cell as the glyph. Same
  highlight, drawn first, glyph second.
* **The five character rows had no panel behind them**, so the letters floated
  on the screen's background. The cartridge draws a slab with letters on it;
  there is one `Font.drawBox` behind all five rows now, not sixty-five little
  windows.

Still not the cartridge's: the **art**. `/data/namein.narc` is not extracted
(task #103), so the frame is this port's own Gen 4 window. The layout and the
characters are Platinum's; the pictures are not, and that stays said plainly
rather than quietly passing.

## The houses on the ground

A chunk's mesh is its **floor**, and the check that established that is the one
that also made this necessary: **9,497 walkable tiles have no land-mesh triangle
beneath them at all**, because indoor chunks are a shell and their floors are
building models. So Sinnoh drawn from the chunks alone is Sinnoh with no houses
in it — which is what the ground pipeline shipped.

Three small pieces, and none of them needed new decoding.

**The models were already readable.** `/fielddata/build_model/build_model.narc`
is 590 models, all 590 decoding exactly — 1,362 shapes, 89,253 vertices — and
**568 of them carry their own textures**. That last number is why this is an
archive added to `MODEL_ARCHIVES` rather than a stage of its own: for 568 of
590 the picture is inside the model file, and the stage that already reads a
model's own TEX0 reads it without a new line. The other 22 come out untextured
and are drawn that way, because **a wrong picture on a building looks
deliberate and a flat one does not.**

**The placements were already parsed and thrown away.** A land chunk's second
block is its object list, and `Gen4Maps.objects` has decoded it — model index,
position and scale, all out of 20.12 fixed point — since the map work. Nothing
carried it into the cache, so the renderer had the ground and no idea what
stood on it. It rides in the chunk index rather than the geometry blob: a
handful per chunk at six numbers each, where a side-car offset would cost more
to read than the numbers.

**The projection needed nothing reconciled.** `Gen4Maps.objects` has already
divided the fixed point out, and `Gen4Model` has already multiplied the model's
own `posScale` into its vertices — so both sides are in world units and the
placement is an ordinary scale-then-translate composed onto the same top-down
matrix the floor uses. Checked numerically before it was committed: a building
at the chunk's centre lands at (256, 256) of the 512-pixel canvas, one 100
units east and 50 north at (356, 306), one at the far corner at (512, 0).

Two things that would each have been a silent wrong picture:

* **A scale of zero is not a scale.** Some records leave the three scale fields
  empty. Read as zero they collapse the model to a point, which draws nothing
  and looks exactly like a building that failed to load. Absent means one.
* **The buildings bake into the floor's own depth buffer**, not over the
  finished picture. That is what keeps a house drawn after the ground but
  *below* it — a basement, the underside of a bridge — correctly hidden;
  painting in order would not manage it.

They bake with the floor rather than drawing every frame, for the reason the
floor does: the geometry does not change, and a town with forty houses would
otherwise be forty model draws a frame to arrive at the picture that was
already there.

**`CACHE_FORMAT` is now `rom-cache-v344`** — the terrain index gains its object
lists and there is a new model set, so a Platinum cache has to be re-imported
before a single house appears.

## What `bm_anime` actually animates

This file has said, in several places, that `bm_anime.narc`'s animations "are
what make Platinum's water move, and a baked chunk is still by definition", and
that re-baking a chunk on the animation clock was the shape of the answer. That
is close enough to sound right and wrong about the mechanism — which is the
kind of wrong that sends the next person to rebuild the terrain renderer.

**They animate the props standing on the ground, not the ground.** Measured
against this cartridge, of the 95 animations in `bm_anime`:

| | |
|---|---|
| name a **build model**, by the model's own name | **68** |
| name a texture in the area building texture sets | 3 |
| name any material, shape or texture of a **land chunk** | **0** |

Zero. Not few — none. And the names say it out loud once you read them rather
than counting them: `door_op`, `pc_door_op`, `stair_pc_u01d`, `funsui` (a
fountain), `machine_l02`, `treeeff01`. Doors opening, fountains running, tree
tops moving, PC doors, stairs. Some of those props *are* water — `l_lake`,
`wfall`, `r04_w` — which is exactly why the water intuition was nearly right
and its mechanism was not: the lake is a model standing on the chunk, not a
patch of the chunk's own mesh.

This lands well, because the buildings were wired in one section ago and these
are the same objects. The two archives are separate, so the models stage's
per-archive animation pairing cannot see across them; there is now **one
cross-archive pass** that links each build model to its animations by name, so
nothing at run time searches 95 animations per building per frame.

### The scrolls play

Both halves are built, and the units were measured rather than assumed.

**The units.** `Gen4Anim` decodes a BTA0 into per-frame scale, rotation and
translate channels, and nothing in pret says what a translate of `1.0` means —
the application lives inside NitroSDK, which is not in the decompilation. The
*data* says it outright:

```
funsui       16 frames   tT  0.0000 .. -1.0000   scale const 1.0
r04_w       121 frames   tS and tT  0.0000 .. -1.0000
wfall        61 frames   tT  0.0000 .. -2.0000
l_lake       61 frames   tS and tT  0.0000 .. -1.0000
machine_l04  60 frames   tS -0.0166 .. -1.0000
```

Every scroll runs to **exactly** −1.0 over its own frame count, and the
waterfall to −2.0, which is two cycles in the same time. A translate landing on
whole units is one full wrap of the texture; texel units would have run to 16
or 64. This port's UVs are already divided by the texture's size when the mesh
is built, so the transform applies with nothing to convert.

**The shader** takes a 2×2 and an offset now, alongside the MVP. Sent on
*every* shape, including the overwhelming majority that are identity — a
declared uniform that is not sent reads as zero, and a zero texture matrix
collapses every coordinate onto one texel, which is a model drawn in a single
flat colour. `Gen4Model` was also dropping each shape's **material name**,
which is what a texture animation names; nothing could have driven one even
once the animation was decoded.

**The split** puts the moving props on a second canvas per chunk, rebuilt when
the clock moves; the static floor and the static buildings stay baked. Two
details in it are the difference between working and nearly working:

* **The terrain is drawn into that canvas with the colour mask off**, filling
  the depth buffer without painting anything. That is what keeps a lake behind
  a cliff behind it — the canvas comes out transparent everywhere the props are
  not and correctly occluded everywhere they are. Props drawn alone would have
  floated in front of the terrain above them.
* **That chunk's terrain mesh is held**, not rebuilt. `modelFor` reads geometry
  out of the side-car file and builds a LÖVE mesh per shape; calling it once a
  frame for every chunk with a fountain on it would cost more than the
  animation it pays for. Only chunks that have moving props hold one.

**The clock is deliberately not wrapped.** The obvious wrap is a round number,
and this archive's periods — 16, 20, 21, 25, 60, 61, 91, 121 among them — do
not all divide into any of them, so a wrap would jump the phase of every
animation coprime to it. A Lua number counts frames exactly past any session
anyone will play.

### The flipbooks play too

BTP0 was the open half: its keys name a texture by NAME out of the animation's
own list, and where that name resolved to was not established. It is now, and
the answer is as tidy as it could be — **of the 16 build models carrying a
BTP0, all 16 have every one of that animation's texture names in their OWN
TEX0.** No misses, and not one of them lacking a TEX0. The alternate frames sit
inside the model file beside the picture they replace.

Which exposed why they could not have been played anyway: **the models stage
writes the texture each SHAPE references**, and for an animated material that
is frame zero and nothing else. A door's other three pictures were decoded,
named, and never written to disk. They are now, under the same
`<model>/<texture>` key as everything else, and recorded on the model as
`patternImages`.

Two details that decide whether a flipbook runs right or merely runs:

* **The keys are sparse, and key N is not frame N.** `c1_s02` holds frame 0 for
  ten frames, then the next for twenty, then thirteen, then nine. Indexing the
  key list by the frame counter would run every flipbook at the wrong speed and
  the wrong rhythm. The lookup walks to the last key at or before the frame.
* **A material can carry both a scroll and a flipbook**, so the evaluator
  merges into the material's entry rather than assigning a fresh table —
  otherwise whichever was evaluated first is silently dropped.

A BTP0 counts as animated only when the model actually carries the pictures its
keys name. An older cache has the animation and not the frames, and re-baking a
chunk every frame to redraw an unchanging door is pure cost.

`CACHE_FORMAT` is now **`rom-cache-v346`** — the flipbook frames are new files
and `patternImages` is a new field, so doors need a re-import. The scrolls do
not; they were three renderer files.

`CACHE_FORMAT` is now **`rom-cache-v345`** — build models carry their
animations.

## Sinnoh makes a sound

Platinum's audio is `/data/sound/pl_sound_data.sdat` — 7.9 MB of SDAT: SYMB
names, INFO records, FAT, and one FILE block holding everything. Most of it is
SSEQ sequences over SBNK banks over SWAR wave archives, which is a
**synthesiser** and not a decoder. That is the music, and it is not this.

**The cries are not that**, and the gap between the two is what makes this a
stage rather than a project. Measured across the cartridge:

| | |
|---|---|
| species whose bank points at wave archive **index == species id** | **493 of 493** |
| those archives holding exactly one sample | **493** |
| those samples that are **PCM8** | **493** |
| sample rates | 10512 Hz (388), 13379 Hz (105) |

No ADPCM, no multi-sample instruments, no sequencing. A cry is one 8-bit
recording, and 493 of them come to 4.6 MB of WAV.

### The trap, which was a good one

The wave archives are **named** `WAVE_ARC_PV001`..`PV518`, 493 present. Read
the numbers out of those names and 387–411 are missing while 494–518 are
spare — which looks *exactly* like a block of 25 species relocated by +107, and
is a coherent enough story that I wrote it down as the answer before checking
it.

It is wrong. **The names are shuffled; the indices are the species.** Species
387's bank is called `BANK_PV432` and its wave archive index is 387. The
cartridge says the same thing in one line —
`NNS_SndArcPlayerStartSeqEx(handle, -1, waveID, -1, SEQ_PV001_sseq_1)` with
`waveID = species`: one sequence for every cry, and the bank number *is* the
species. Two statements that cannot borrow from each other, agreeing on all
493.

Following the names would have given 25 species the wrong cry — audible,
plausible, and attributable to nothing.

### Two small things that are the whole difference

* **SWAV PCM8 is signed and WAV PCM8 is unsigned.** One addition, and the
  difference between a cry and a burst of noise. The check is that a decoded
  cry's mean byte lands on 128.0 — Pikachu's does, across 8,236 samples, with
  the range running 3 to 252.
* **A SWAV's length is in 32-bit words** counted from the end of its own
  twelve-byte header. `WAVE_ARC_PV001` is 8,260 bytes and
  `0x3C + 4 + 12 + 2046 × 4` is 8,260 — the layout and the file agreeing to the
  byte, which is what makes the reading a check rather than an assumption.

### What it cost the engine: nothing

`Sound.playCry(data, species)` already reads `data.audio.cries[<NAME>]` and
already accepts `{ file = ... }`, because that is the shape Gen 1, 2 and 3
write. The stage fills the same table with the same shape, so **not one line
of the engine's audio path needed a Gen 4 branch.** Cries are keyed by species
name, as everywhere else.

`CACHE_FORMAT` is now **`rom-cache-v347`**.

**The music is still silent**, and that is the honest line: it needs an SSEQ
player — a sequencer over sampled banks — and nothing here is a step toward
one. What this stage establishes is only that the archive is readable and the
file table is right, which a sequencer would need first anyway.

## The split that was being thrown away

Generation 4 is the one that abolished the type-based physical/special rule.
That is the defining mechanical change of the generation, and this port was
discarding it — not in the battle engine, which is not wired for Platinum yet,
but one field earlier, where it would have poisoned every fight the moment it
was.

`Damage.categoryOf` reads `move.category`. The Gen 4 extractor writes the split
as **`class`**. So every Platinum move fell straight through to
`TypeChart.category(move.type)` — the pre-Gen-4 rule the cartridge exists to
replace.

**Measured against this cartridge's own 471 moves: 92 of the 301 damaging ones
disagree with the type rule — 31%.**

| move | class | type rule would say |
|---|---|---|
| Fire Punch, Ice Punch, ThunderPunch | physical | special |
| Hyper Beam, Gust, SonicBoom, Razor Wind | special | physical |
| Bite, Razor Leaf, Vine Whip | physical | special |
| Acid, Night Shade | special | physical |

Nearly a third of Sinnoh's attacks on the wrong stat, both ways. **A battle
would have run to the end and simply been wrong** — wrong numbers, right
structure, reading as bad luck rather than as a bug. This is the cheapest
moment to find it: before anything depends on it.

The fix is `move.category or move.class or TypeChart.category(move.type)`, in
the engine rather than by renaming the field in the extractor, so it needs **no
re-import**; and `class` is what the cartridge's own move record calls it.
Gen 1, 2 and 3 write `category` on their moves and nothing else in the project
puts a `class` on one, so their precedence is unchanged — checked against all
four cases.

The same field is read a second time where a **status** move must not roll
damage at all. Platinum has 170 of them and every one carries its class under
the other name; asking only for `category` there left each of them saved by
`power == 0`, which is true today and is not the thing being asserted.

## The ruleset that was written and never used

Looking at what a Platinum battle would run under turned up something that is
not about Platinum at all.

`BattleState` picks its rules as `constants.defaultRuleset or "gen1_faithful"`.
**Nothing has ever written that constant** — not the Gen 3 extractor, not the
Gen 4 one. Checked against the caches rather than the code: neither Emerald's
`constants.lua` nor Platinum's contains the string anywhere.

So on a fresh save, **Hoenn has been fought under Generation One's rules**:

* the 1/256 miss on a hundred-percent-accuracy move
* crit rate derived from speed rather than the 1/16 stage ladder
* a crit that doubles the **level** inside the formula rather than the damage
  — which also doubles the formula's `+2` and re-floors, so it is a different
  number, not a reformulation
* the random factor read as 217..255 out of **255** instead of 85..100 out of
  **100**
* Gen 1's sleep turns, status divisors, Focus Energy bug, and unlimited enemy PP

And `src/battle/rulesets/gen3_emerald.lua` — which states every one of those
differences, each with a disassembly address — has been sitting beside it,
registered in `Builtins`, referenced by nothing. Its own opening comment is
*"the mechanics were already right and every constant was Gen 1's, which is the
kind of wrong that looks fine until you count."* That was written about the
status constants inside it. It turned out to describe the file's own fate.

The one thing that worked is the OPTIONS row, which cycles the merged registry
— so a player who happened to flip it got the right rules and had no way to
know the default was wrong.

`src/battle/RulesetDefaults.lua` is the fallback now, in one place because two
files need it and a second copy is how they disagree later. A cartridge that
names its own still wins; nothing about the mod registry or the options row
changes; **no cache output changed, so no re-import.**

Two deliberate non-changes:

* **Gen 2 stays on Gen 1's.** There is no Gen 2 ruleset in this repo and
  Johto's constants differ from Kanto's in ways nobody here has measured.
  Moving it onto a ruleset written for Hoenn would trade a known wrong answer
  for an unknown one.
* **Gen 4 took Gen 3's, and that was a judgement rather than a reading.** It is
  a reading now — see the next section. The judgement was *nearly* right, and
  wrong in exactly one place, which is the interesting part.

## `gen4_platinum`, measured rather than assumed

The caveat above named three things nobody had checked: the damage formula's
internal rounding, the sleep counter, and the hooks Gen 4 added. Two of them
are now read out of pokeplatinum with the line beside each, and the third —
abilities and held items — is not a ruleset field in this engine and so is not
pretended at in one.

**The result is not what the caveat expected.** Of every constant this engine
models, **exactly one moved.**

### The one that moved: spread damage

Emerald halves a spread move, and only a move whose target byte is *exactly*
`MOVE_TARGET_BOTH`. Earthquake, Explosion, Self-Destruct and Teeter Dance are
target `$20` on that cartridge and are **not reduced at all** — they hit three
Pokémon for full.

Platinum, `battle_lib.c:7035-7044`, is **two consecutive blocks**:

```c
if (DOUBLES && range == RANGE_ADJACENT_OPPONENTS
    && CountAliveBattlers(TRUE,  defender) == 2) damage = damage * 3 / 4;
if (DOUBLES && range == RANGE_ALL_ADJACENT
    && CountAliveBattlers(FALSE, defender) >= 2) damage = damage * 3 / 4;
```

Three quarters, not a half — and the two blocks **count different things**.
`BattleSystem_CountAliveBattlers` (`battle_lib.c:2825`) branches on its
`sameSide` argument: `TRUE` (`:2840`) counts the living on the **defender's
side**, `FALSE` (`:2833`) counts **every living battler except the defender**,
across both sides.

So Blizzard is reduced only while both foes are up — Emerald's condition, kept.
But **Earthquake is reduced whenever two others are still standing**, including
when the defender is the last foe alive, because the user's own ally is taking
the hit too. Reading the second gate as the first gives Earthquake full damage
in exactly the case the cartridge reduces it.

### The range byte, measured off the ROM

`Gen4Moves.parse` already reads `range` at offset 8, but nothing had ever
checked what the values were. Across all 471 members of
`/poketool/waza/pl_waza_tbl.narc` the field only ever takes 0, 1, 2, 4, 8, 16,
32, 64, 128, 256, 512 and 1024 — bit positions, one for one with
pokeplatinum's `generated/move_ranges.txt`. Spot-checks against that list:
Blizzard, Rock Slide and Hyper Voice read **4** (`RANGE_ADJACENT_OPPONENTS`);
Surf, Earthquake, Explosion, Self-Destruct and Teeter Dance read **8**
(`RANGE_ALL_ADJACENT`).

**`0x08` does not mean the same thing in the two generations** — it is
`MOVE_TARGET_BOTH` in Hoenn and `RANGE_ALL_ADJACENT` in Sinnoh — and a Gen 3
move record calls the field `target` while a Gen 4 one calls it `range`. That
is why the test could not stay a literal in the engine.

`BattleState:computeDamage` used to carry `move.target == 0x08` itself, which
meant **Emerald's rule was the only rule any ruleset could have**, measurement
or no measurement. It is now two fields on the ruleset:

| Field | `gen3_emerald` | `gen4_platinum` |
|---|---|---|
| `spreadField` | `"target"` | `"range"` |
| `spreadRanges` | `{ [0x08] = "defenderSide" }` | `{ [0x04] = "defenderSide", [0x08] = "othersOnField" }` |
| `spreadNum` / `spreadDen` | 1 / 2 | 3 / 4 |

`gen1_faithful` and `modern_clean` have neither field, never set `spread`, and
are untouched — Gold, Silver, Crystal and Prism see no change from any of this.

### The sleep counter, which needed reading to come back the same

`subscript_fall_asleep.s:59` is `Random 3, 2`. That reads as 2..4 and **is
not**: `BtlCmd_Random` (`battle_script.c:3200`) reads the bound, **adds one**,
and then adds the offset — `(rand % 4) + 2`, so **2..5**, identical to
Emerald's `sleepTurnsMin = 2, sleepTurnsMax = 5`. The only way to know that was
to go and look, which is the whole argument for writing the matching constants
down rather than inheriting them silently.

### Everything else that was checked and did not move

| Constant | Platinum | Source |
|---|---|---|
| Crit ladder | 1/16, 1/8, 1/4, 1/3, 1/2, stage clamped to 4 | `sCriticalStageRates[]`, `battle_lib.c:7097`, clamp `:7130`, roll `:7134` |
| Crit multiplier | ×2 (×3 with Sniper, not modelled) | `:7139`, `:7142` |
| Random factor | 85..100 out of **100** | `:7084` — `damage *= (100 - RandNext() % 16); damage /= 100;` |
| Screens in doubles | `damage * 2 / 3`, else `/ 2` | Light Screen `:7023`, Reflect `:6982`, both on `CountAliveBattlers(TRUE) == 2`, both skipped on a crit |
| Burn | halves the running damage unless Guts | `:6978` |
| Burn / poison residual | maxHP/8 | `subscript_burn_damage.s`, `subscript_poison_damage.s` |
| Toxic | maxHP/16 × counter, counter is a 4-bit field so stops at 15 | `MON_CONDITION_TOXIC_COUNTER` |
| Freeze thaw | 1 in 5 per turn | `RandNext() % 5 != 0` keeps it |
| Poison immunity | POISON, STEEL | `subscript_poison.s:34-37`, `subscript_badly_poison.s:22-25` |
| 1/256 miss | gone | accuracy is a percentage out of 100 |

Every one of those is written out in `gen4_platinum.lua` **anyway** rather than
left to be inherited, because an absent field reads as *nobody looked* and a
field with a citation reads as *somebody did*.

### What this changes for a player

`RulesetDefaults.DEFAULT_BY_GENERATION[4]` is `"gen4_platinum"`, and
`Builtins`' `rulesets` registrant lists the file alongside the other three, so
the OPTIONS row cycles it like any other. **No cache output changed, so no
re-import.** A player on the old default was playing something very close to
right — and wrong in every double battle.

Gen 2 is still on Gen 1's, and stays there until somebody does to Johto what
this did to Sinnoh.

## Sinnoh was drawn upside down

Reported from play: *"The map is rendering in flat 2d and also seems like its
upside down and maps arent properly aligned nor walkable areas the pokeball
screen where your supposed to touch the pokeball isnt rendering properly as
well."* Three complaints, two of them one bug, and the third is real but is not
a bug.

### The flip

`Gen4Ground.topDown` built its orthographic matrix with `ndc.y = -z/half`. A
custom `position()` in a LÖVE shader returns clip coordinates **directly**,
which bypasses the projection LÖVE would set up for the target — and **a
canvas's framebuffer counts its rows the opposite way from the screen**. Every
chunk in Sinnoh baked mirrored top to bottom.

This trap is already written up in this repo. `Gen4Title` carries it — *"CLIP Y
POINTS THE OTHER WAY INTO A CANVAS … Reported: Giratina is showing upside
down"* — along with the `FLIP_Y` matrix that fixes it. `Gen4Ground` was written
without the compensation and nothing connected the two.

**Measured on Twinleaf Town** (T01, matrix 0, chunk cell 3,27) rather than
eyeballed, because "looks wrong" and "is mirrored" are different claims:

* the four houses' **collision footprints** are 5×5 at the top-left and
  bottom-right and 4×4 at the top-right and bottom-left. Segmenting the
  screenshot's four teal roofs gives 135×89 px at **bottom-left and top-right**
  and 99×65 px at **top-left and bottom-right** — the pair is swapped, which is
  a mirror in one axis.
* which axis is settled by the town's **asymmetric border**: the collision grid
  has extra gaps at rows 1–2 only, never at rows 29–30. The screenshot has them
  along the **bottom**, at image y 700–820, which back-projects to rows ~1–3 —
  a vertical flip. Under a horizontal flip the same pixels land on rows 26–29,
  where the grid is solid.
* all four of the map's **warps** sit on the bottom row of their own house's
  footprint, which is where a door is; the door model (`build_model` 67, placed
  four times) sits at `z = house z + 13`. So `+z` is south in the grid's terms
  as well as the cartridge's, and the mailboxes at (13,11) and (18,21) sit
  beside their doors on the same rows.
* `Gen4Ground:heightsAt` **already** reads tile y as `+z`. The height lookup and
  the picture disagreed about which way south was.

One character: `0, 0, -1/half, 0` became `0, 0, 1/half, 0`.

The second half of the report follows from the first. *"Maps arent properly
aligned nor walkable areas"* is what a mirrored ground **is**: the collision
grid was never flipped, so a house visible at the bottom of the screen had its
walls at the top and its door on the wrong side. Nothing about collision itself
was wrong.

A vertical flip also reverses triangle winding. That costs nothing here because
`Gen4Model:draw` sets cull mode `"none"` — noted in the file so that turning
culling on for the ground does not quietly break it again.

### The Poké Ball was the exact inverse of a Poké Ball

The intro's ball step was composing member 40's tilemap against the 16-tile
sheet at member 32/33/34 **with no tile base**, and a tilemap indexes VRAM
rather than the member it shipped beside.

Decoded, member 40 is 32×24 cells of which **736 are tile 0** and 32 are
`0x20..0x2F` — sixteen indices for a sixteen-tile sheet, with `flipX` doing the
ball's right-hand side, and palette row 2 (which is why `paletteFirst = 32` was
already right). The app loads those sixteen tiles at **tile 32** of the
background's character base.

Composed without the base, tile 32 begins at byte 1024 of a 512-byte sheet, so
`Gen4Graphics.compose`'s own bounds check left every ball cell transparent —
while all 736 empty cells drew the sheet's tile 0. The result on disk was a
full screen of one repeated glyph with a 48×48 hole punched where the ball
goes, **identical across all three frames**, which is what shipped and what the
screenshot shows.

`Gen4Graphics.compose` now takes a `firstTile`, and this was checked for every
other pairing in the archive rather than assumed: the five backdrops run to
tile 121 and the figures' tilemap to 127, both inside their own 128-tile
sheets. **Only the ball is loaded high.**

Re-composed with the base, the three frames are a 42×42 button centred on the
screen: pale blue, pressed, then **yellow** — the ball's button being pushed in
and lighting up, which is precisely what `Gen4RowanIntro`'s three-picture
animation was written for.

That also corrected a reading in the screen. `drawScene` drew the ball picture
and **returned**, on the argument that it "owns the screen because on the
cartridge it owns a screen". That argument only survived because the picture
was a full-screen field of garbage; the real picture is a small button on
transparency, and drawn alone it is a black screen with a button on it. It now
draws **last, over Rowan and his backdrop**.

`CACHE_FORMAT` goes to `rom-cache-v348:` so the three ball PNGs are rebuilt.
The ground flip is runtime-only and needs no re-import.

### "Flat 2d" is not a bug, and here is what it would take

`Gen4Ground` bakes each 32×32-tile chunk **orthographically, top down, once**,
into a 512×512 canvas, and the map draws canvases. That is a deliberate choice
and the file says so: the geometry does not change, so rasterising it every
frame arrives at the same picture. It is also why walls and house fronts are
invisible — an orthographic top-down view of a 3D town shows roofs.

The DS draws Sinnoh with a **tilted perspective camera**. Getting there is not
a fix to this file so much as the next stage of it, and the meshes are already
in the cache:

1. a per-frame camera (`Gen4Model.perspective` + `lookAt`, both of which exist)
   in place of `topDown`, drawing the visible chunks' models directly rather
   than their baked canvases
2. sprites billboarded into that camera instead of blitted at tile positions,
   which is where the player and every NPC currently live
3. the cache's own `lighting` value per map (already extracted — `T01R0202`
   carries `lighting = 3`), which is what makes an indoor room read as indoors

Until then the bake is the flat case of the same data, and it is now the right
way up.

### The bedroom in a green field

The second screenshot — a small room drawn in the corner of a large green
field — was measured too, and it is **not** a collision fault.

`T01R0202` is the player's bedroom. Its chunk's permission grid is 1,024 tiles
of which only the top-left 12×12 carry anything: 936 tiles read `0x0000`
(walkable, behaviour 0) and the 83 that carry `0x8000` form a **sealed** box —
rows 0–3 solid, `x = 0` and `x = 11` solid down the sides, row 11 solid across
the bottom. The player cannot leave the room. That is the cartridge's own
arrangement, not a gap in the import.

What is wrong is that **nothing knows the map is smaller than its chunk**. The
map def is 32×32 because the matrix is 1×1 and a chunk is 32 tiles; the mesh
covers only the room; the stand-in fills the other 900 tiles with its
walkable-behaviour colour; and the camera is free to show all of it. The fix is
a camera clamp and a void fill derived from the terrain's own coverage rather
than from the grid's declared size — filed rather than guessed at.

## Platinum's field camera, transcribed

`overlay005/field_camera.c` holds the whole thing: **seventeen** cameras, one
per `CAMERA_TYPE_*`, each `{ distance, cameraAngle, projection, verticalFov,
near, far }`. `MapHeader.cameraType` — the byte at offset 21, which
`Gen4MapHeaders` has parsed since it was written and which nothing has ever
carried into a map def — picks one.

Over all 593 headers in this cartridge:

| Camera | Headers | | Camera | Headers |
|---|---:|---|---|---:|
| `INTERIOR_ORTHOGRAPHIC` | 300 | | `SPEAR_PILLAR` | 4 |
| `DEFAULT` | 189 | | `SLIGHTLY_ZOOMED_OUT` | 3 |
| `CAVE` | 60 | | `OREBURGH_GYM` | 2 |
| `ZOOMED_IN` | 19 | | `HALL_OF_ORIGIN` | 2 |
| `IRON_ISLAND_CAVE` | 6 | | `LAKE_ACUITY` | 2 |
| | | | six others | 1 each |

**Three hundred of the 593 are orthographic on the cartridge** — every
ordinary room, the player's bedroom included. So "flat" was never the mistake.
*Flat and straight down* was: all seventeen are **tilted**, between 40.6° and
78.4°.

### One world unit is one screen pixel, and that is the cartridge's number

`Camera_ComputeProjectionMatrix` builds the orthographic box as
`top = tan(fovY) × distance`. For `INTERIOR_ORTHOGRAPHIC` that is
`tan(3.5211181640625°) × 1563.537841796875 = 96.209` — **half of the DS's
192-row screen**. So `verticalFov` is the *half* vertical FOV, and the scale is
1:1 at the target plane.

Run the same product over all seventeen and fifteen of them land between
94.815 and 96.228 — within 1.3% of one pixel per unit. (`STARK_MOUNTAIN_ROOM_2`
is 115.1 and `UNUSED_16` is 91.6; both are the cartridge's own values.) That
independently confirms the `pixelsPerUnit = 1` the terrain import already
assumed.

`Camera_AdjustPositionAroundTarget` puts the camera at
`target + (sin(y)·d·cos(x), sin(−x)·d, cos(y)·d·cos(x))`, and `y` is zero for
all seventeen — the camera is always due **south** of its target and above it.
For `DEFAULT`: 571.97 up, 342.98 south.

### What this port draws, and how far off it is

The engine's world is a grid of 16-pixel tiles, and *everything* else in it —
collision, warps, sprites, the tile window, encounters — is laid out in those
pixels. A true perspective camera moves the ground relative to that grid, so
adopting one means projecting every sprite through it as a billboard in the
same pass. That is the right end state and it is not this change.

What `Gen4Ground` does now is an **oblique** projection at the cartridge's own
pitch:

```
screenX = x                screenY = z − y · cot(pitch)
```

The ground plane maps **one to one**, so the tile grid, the collision and every
sprite stay exactly where they were and nothing above that file changes.
Height leans up the screen, which is the whole point: a house shows its front,
a cliff shows its face, a bridge stands off the path beneath it. At pitch 90°
the lean is zero and this is byte-for-byte the straight-down bake that came
before — which is why the OPTIONS row can offer that as one of its values
without a second code path.

**How far that is from the cartridge, measured:**

* the cartridge scales ground depth by `sin(pitch)` and height by `cos(pitch)`;
  this scales them by 1 and `cot(pitch)`. That is the cartridge's own picture
  stretched vertically by `1/sin(pitch)` — **16.7%** for `DEFAULT` — and the
  stretch is the price of keeping a tile 16 pixels tall.
* the remaining difference is the perspective itself, and on this cartridge
  that is small: a half-FOV of 8.09° at 666.9 units is a very long lens.
  Ray-traced against the ground plane, `DEFAULT` sees from **101.87** units in
  front of the target to **120.86** behind it — 222.73 units of ground over 192
  rows, against **223.87** for an orthographic camera at the same scale. That
  is **0.51%** on the total and **+9.9% / −7.4%** on the two halves: the near
  and far *edges* of the screen are wrong by about a tenth, the centre is right.
* for the 300 `INTERIOR_ORTHOGRAPHIC` headers there is no perspective error at
  all — the cartridge is orthographic there too.

The chunk canvas grows **upwards** by `leanPx = ceil(cot(pitch) × 384)`,
because that is where the leaning geometry goes; the blit takes the same
`leanPx` back off, so the ground lands where it always did. Chunks are drawn
north to south, which was already the loop's order and is the order that has to
hold once one chunk's towers overlap the next one's ground. Terrain that climbs
more than 384 units inside one chunk loses its top rows rather than drawing
over its neighbour.

### The OPTIONS row

`CAM TILT` cycles `CARTRIDGE / 90° / 80° / 70° / 60° / 50° / 40°`. `CARTRIDGE`
is the map header's own type — the answer this work exists to give. Changing it
ticks `Gen4Camera.generation`; `Gen4Ground:draw` compares the counter and drops
its bakes, because the pitch is baked *into* them. One frame's hitch, then
nothing.

Held in the module rather than read from the save, for the reason
`TileRenderer.setTileAnim` is: `MapLoader.load(data, mapId)` is never handed a
game. Two callers take the saved value up — the OPTIONS list as it is built,
and `OverworldState:enter`, which is the one place every path into the world
goes through (boot, a warp, the map editor's Play). The second is what makes
the choice survive a restart.

### Whoever is standing on the ground has to lean with it

The tile grid is untouched by the tilt — that is the whole reason the oblique
projection was chosen — but a character on a hill, a bridge or a flight of
steps was still drawn at the *grid's* height rather than the terrain's, so they
walked through what they were meant to be standing on.

`Gen4Ground:rise(px, py)` is that lift in pixels: the BDHC height under a tile,
times `cot(pitch)` — the same `z − y·cot(pitch)` the chunk bake uses, applied
to one point. It takes **map pixels** rather than tiles so a sprite's own
position gives an answer that changes as it walks. Heights are cached per tile,
and the *raw* height is cached rather than the lifted pixels, because the tilt
can change under it and the terrain cannot.

Applied as a **shifted camera** rather than a shifted position, which is what
keeps it to one seam: every sprite path in this engine ends in `py − camY`, so
`e:draw(cam.x, cam.y + riseOf(e))` lifts the sprite and nothing else has to
learn about elevation. Zero on every Gen 1/2/3 map and on any Gen 4 map drawn
straight down — `gen4Ground` is nil in the first case and `lean` is 0 in the
second — so it costs one nil test a frame for everything that is not Sinnoh.

Measured, the heights are sane world units: Twinleaf's chunk runs 8–16, the
player's bedroom −24–0 (the floor sits below the chunk origin, and the mesh
moves down with it, so the two stay together), and across all 666 chunks
−96–480.

It is still a **step per tile** rather than a ramp. The BDHC's plates are per
region, so the ground itself steps there too; a true ramp wants the plate's own
plane evaluated at the exact point, which `Gen4Bdhc` can already do and this
does not ask for yet.

#### ...and it found a bug that had never fired

`Gen4Ground:heightsAt` sorted its results with `table.sort(list, a > b)`, and
`Gen4Bdhc.heightsAt` answers `{ index, height }` **records**, not heights. Lua
will not order two tables, so that call raises — and `heightAt` was handing its
caller a record where it promised a number.

Neither had ever gone off, because nothing called either function: the movement
grid still reads elevation 0 (#98). The moment something did, it would have
raised on the first tile with two surfaces under it. Sampled over 42,624 tiles
spread across all 666 chunks, **652 of them (1.5%) have more than one plate** —
which is every bridge in Sinnoh, and therefore exactly where a player walks.
`heightsAt` now returns plain numbers, highest first.

## Sinnoh was wearing one palette

Reported: *"much of the tileset didnt seem properly colored especially when
outside."* It was outside, and only outside, and the reason is one line.

`Gen4Terrain.textures` decoded **every** texture against **palette 1**. The
note beside it said why: *"a texture's own palette is named by the material
that wears it, which is a fact about the chunk rather than about the picture,
and the great majority of these sets pair one palette with one texture
anyway."* The first half is true. The second half is false.

Twinleaf Town's set (member 6) holds **78 textures and 74 palettes**. Palette 1
of that set is `apeak` — a mountain top. So `ngrass`, which is grass, came out
in browns; so did the sand, the flowers and the lake. Every outdoor map in the
game was painted in one palette.

**The join was already in the cache and always was.** Every chunk shape carries
`material`, `texture` *and* `palette`, because `Gen4Nsbmd` reads the material
that names both — `ngrass` is worn with palette `grass`. Nothing used it. The
*model* path never had this problem; it has always looked `shape.palette` up in
the member's own dictionary, which is exactly why the buildings were the right
colour standing on ground that was not.

**Name-matching is not a substitute**, which is worth saying because it is the
obvious shortcut. Over all 7,547 chunk shapes there are 1,149 distinct texture
names, and **553 of them are worn with a palette of a different name** —
`ngrass02` wears `grass02`, `bf_symbol2` wears `symbol`, `ginga2` wears
`dun26_092`. Across the archives as a whole, 1,293 of 3,130 map textures and
2,104 of 3,063 building textures have no palette of their own name at all.

Twenty-nine textures are worn with **more than one** palette (`wcliff` is
`criff` on 76 shapes and `wcriff` on 7); those get a second picture filed under
`<texture>#<palette>`, and `Gen4Ground:modelFor` asks for that key first. Every
other texture is filed once, so the file count barely moves — set 6 goes from
78 pictures to 88.

### ...and 355 textures were not decoded at all

`Gen4Models.DECODABLE` listed formats 2, 3 and 4. Counted over both texture
archives, that left out **259 a3i5 and 96 a5i3** pictures — 238 of them in the
map sets. Those are the textures with soft edges: cliff tops, tree canopies,
the lake surface. The holes were exactly where a map most looks wrong.

Neither format is a paletted texture with an alpha bit bolted on; the texel
*is* a pair — three bits of alpha over a five-bit index, or five over three —
and the alpha is the texel's own rather than the palette's. `transparent0` does
not apply to either: index 0 is an ordinary colour there, and treating it as a
hole punches the middle out of every soft edge.

Recounted with both added: 4,306 `palette16`, 1,484 `palette4`, 48
`palette256`, 259 `a3i5`, 96 `a5i3`, and **nothing else** — no 4×4-compressed
and no direct colour. Set 6 now decodes 88 of 88 with none refused, against 9
refused before.

## Sinnoh's scripts had no handlers at all

Reported: *"npcs are appearing for the events but not triggering, npcs are
still missing text."* The log says it outright:

```
[warn] script: unknown command 'g4_lock_all' (skipped)
[warn] script: unknown command 'g4_face_player' (skipped)
[warn] script: unknown command 'g4_buffer' (skipped)
... show_text ...
[warn] script: unknown command 'g4_wait_button' (skipped)
[warn] script: unknown command 'g4_check_flag' (skipped)
[warn] script: unknown command 'g4_compare_var_value' (skipped)
```

`Gen4ScriptVM` has lowered Platinum's bytecode into 61 distinct `g4_*` rows
since it was written, and **nothing has ever registered a handler for one**.
Every row went through `ScriptRunner`'s unknown-command path, which logs and
steps over it.

The box opened and shut without waiting; the name placeholders stayed empty;
and — the one that matters most — every `checkflag` and `comparevar` left the
comparison register untouched, so each branch after it read whatever the
*previous* script had put there. A script that is 90% correct and branches at
random is not 90% of a conversation.

`src/script/Gen4Commands.lua` is the other half. It follows `Gen3Commands`'
shape — add `g4_*` functions to the shared `Commands` table, register them in
`Commands.registerInto` — but the two share no state: Hoenn's vars live in
`save.gen3Vars` and Sinnoh's in `save.gen4Vars`, because one save can hold
both.

The comparison register is the cartridge's, transcribed. `Compare` (`scrcmd.c`
:879) returns 0 for `<`, **1 for `==`** and 2 for `>`; `ScrCmd_GoToIf` (:1065)
indexes `sConditionTable[condition][result]`:

```
//   <      ==     >
{ TRUE,  FALSE, FALSE },  // 0  <        { TRUE,  TRUE,  FALSE },  // 3  <=
{ FALSE, TRUE,  FALSE },  // 1  ==       { FALSE, TRUE,  TRUE  },  // 4  >=
{ FALSE, FALSE, TRUE  },  // 2  >        { TRUE,  FALSE, TRUE  },  // 5  !=
```

`ScrCmd_CheckFlag` writes the **flag's own value** into that register rather
than a comparison (:1105), which is what makes `checkflag` then `gotoif 1` read
as "if the flag is set". Vars are ids from `0x4000` (`VARS_START = 16384`) and
anything below is a literal — the same rule Hoenn uses.

### Eight lowering entries that named opcodes the decoder never produces

Cross-checking the lowering table's keys against `Gen4ScriptOps`' 840 opcode
names turned up **eight dead entries** — code that has never once run:

| Written as | The cartridge's name |
|---|---|
| `giveitem` | `additem` |
| `takeitem` | `removeitem` |
| `lock` / `release` | `lockobject` / `releaseobject` |
| `bufferpokemonname` | `bufferpartymonspecies` / `bufferpartymonnickname` |
| `message2` | `messageinstant` / `messagenoskip` / `messagesynchronized` |
| `trainerbattle` | `starttrainerbattle` |
| `closemenu` | *(no such opcode)* |

**No item gift in Sinnoh was being lowered at all.** The dead-key count is now
zero, and six more buffers (`buffermovename`, `buffernumber`,
`buffercounterpartname`, `messagevar` …) are lowered while the names were
being checked.

### ...and four that dropped operands

* **`warp` is five operands, not three.** `ScrCmd_Warp` (`scrcmd.c`:3566) reads
  `(mapHeaderID, unused, x, z, direction)`. The lowering passed args 1–3, so
  the runner got the header, the *padding* and the X coordinate as if they were
  map, x and y. Every scripted warp went somewhere wrong or nowhere. It also
  names a **map header**, not a map, so `g4_warp` builds the header→map-id
  index once from the defs and looks through it.
* **All four bag commands are `(item, count, destVar)`** (`scrcmd_item.c`) and
  every one writes whether it succeeded into that var, which the script then
  compares. The destination was being dropped.
* **`showyesnomenu <destVar>` puts the answer somewhere.** The row asked the
  question and threw the answer away, so every yes/no in Sinnoh branched on
  stale state.
* `starttrainerbattle` takes two operands and was passed one.

### What is honestly not built

Sixteen verbs are registered as named, log-once no-ops rather than left to the
unknown-command path: the trainer-battle handoff, the shop screen, the sign-box
state machine, the scripted menu, the common-script archive. Each says once per
session what system it is waiting on. The remaining 45 do the cartridge's work.

Verified by construction: every one of the 61 `g4_*` verbs the VM emits now has
a handler, and every one of the 83 lowering keys matches a real opcode.

## Half the maps had no collision at all

Reported: *"collisions dont seem to be correct in the overworld."* Not a wrong
grid — an absent one.

Gen 4 splits its collision the way Gen 3 splits its layouts. A grid is built
once per **matrix** and a map that does not own its matrix outright references
it instead, because the 30×30 Sinnoh overworld is 921,600 cells and inlining it
once per building standing on it took the extraction from 4 seconds to 22. The
extractor writes both halves: the shared grids into `map_layouts`, the
reference as `def.layout`.

**Nothing ever read the other half.** `Map` reads `def.blocks` and nothing
else, and at run time `data.map_layouts` is touched by exactly one Gen 3 script
command. Counted over the cache: **291 of the 593 Gen 4 maps have no `blocks`
string**, including `T01R0201` — the player's own house, the map in the
screenshot.

`MapLoader.resolveBlocks` is the missing read: when a def has no blocks, take
them out of `map_layouts[def.layout]`, cropping to `originX/originY` and the
map's own width and height when the map is a region of a bigger grid. Done
where the def and the dataset are both in hand, and written **back onto the
def** rather than onto a copy — half the engine compares `map.def` against
`data.maps[id]` by identity, and a copy would quietly become a second map. It
is idempotent, so a reload costs nothing.

Checked against the cartridge rather than assumed: all 291 resolve, none comes
out the wrong size, and the resolved grid for `T01R0201` matches that chunk's
own permission bytes in `gen4_map_permissions` cell for cell.

### One thing that is *not* a collision bug

With the camera tilted, a wall's base is drawn at its collision cell and its
top up to `height × cot(pitch)` pixels higher. Bumping into a wall whose top is
drawn well above the player reads as "collision is wrong" and is the oblique
projection working: the cell you cannot enter is the one under the wall's
**foot**, not under its cap. Setting `CAM TILT` to 90° puts them back on top of
each other, which is the quickest way to tell the two apart.

## The checkerboard was the stand-in, and the ROM has no border

Reported: *"i still see it surrounded by checkerboard instead of what the rom
uses as a border."*

The checkerboard **is** the stand-in tileset. `Gen4Tileset.metatiles` lays every
cell down as a two-by-two checker of a class colour and a darkened copy of it,
deliberately, so a map drawn in flat colours still shows its 16-pixel grid. And
behaviour 0 — ordinary ground — is 940 of Twinleaf Town's 1,024 cells. Once the
mesh draws the map, the only stand-in left visible is the part the mesh does
*not* cover: the void around it, in green.

**The cartridge has no border block.** Gen 1–3 tile a border metatile outside
the map; Sinnoh's overworld is one seamless matrix and its interiors are sealed
rooms inside a 32×32 chunk, so what the DS shows beyond the geometry is the
backdrop and nothing else.

So `TileRenderer:drawWindow` now fills the viewport with the stand-in palette's
own colour 0 — `{24, 26, 34}`, the backdrop every class colour was always drawn
against — and lays the ground over it, instead of drawing the tile window
underneath. The stand-in still runs when there is no ground (a cache imported
before the terrain stage), which is the case it was written for. It used to
draw underneath because a chunk bakes over several frames and the screen would
otherwise be blank; a flat backdrop covers that just as well, and is what a map
transition looks like on the cartridge anyway.

## Every warp in Sinnoh was one door early

Reported: *"warps seem to be bugged, when i go through them im coming out in
the wrong place."* The log says it without ambiguity — `map: T01 at (20,11)`
into Twinleaf's third house, `map: T01 at (20,21)` on the way back out, and
that is the **second** house's door.

`Warp.lua` indexes `destDef.warps[warpDef.destWarp]`, which is a Lua array.
Gen 3's extractor writes `destWarp = rom:u8(o + 5) + 1` and says why in a
comment at `RomExtractorGen3.lua:11652`; Gen 2 clamps at one. The Gen 4
extractor wrote the cartridge's zero-based anchor straight through.

Checked against the cache, all four of Twinleaf's houses:

| Interior | `destWarp` | lands on | its own door is at |
|---|---:|---|---|
| `T01R0101` | 0 | *nothing* (`warps[0]` is nil) | (9, 11) |
| `T01R0201` | 1 | (9, 11) | (20, 21) |
| `T01R0301` | 2 | (20, 21) | (20, 11) |
| `T01R0401` | 3 | (20, 11) | (10, 21) |

With `+ 1` every one lands on its own door exactly.

**This is also why the player kept appearing outside the rooms.** `T01R0201 →
T01R0202` is `destWarp = 0`, which resolved to `warps[0]` — nil. Arriving at a
nil warp puts the player at an undefined position, and a bedroom is a sealed
12×12 box inside a 32×32 chunk: land outside the seal and you can roam the void
freely, which is the screenshot.

## Blank text boxes: the bank was never carried

Reported: *"talking to people brings up a text box but its blank."*

A Gen 4 `message` command names an **entry**, not a string. The bank is the map
header's `msgArchiveID`, and the pair is what addresses a line — which is why
the extractor keys `data.text` as `TEXT_Bnnnn_nnnnn` rather than by a single
id, and says so where it writes it.

The lowering emitted `{ "show_text", <entry> }` on the reading that "the row
carries the entry and the runner resolves the bank". **Nothing resolved it.**
`Commands.show_text` looked a bare index up in `data.text`, found nothing, and
degraded to an empty box — which is exactly the behaviour it documents for an
unusable id, and exactly what was on screen.

Two halves, both missing:

* the map def never carried `messages` (`h.messages` has been parsed since
  `Gen4MapHeaders` was written and was dropped on the floor);
* `message` now lowers to **`g4_message`**, which joins the def's bank to the
  row's entry through `Gen4Text.label`. It has to be its own verb because a
  Gen 1–3 `show_text` takes a whole id and a Gen 4 one takes half of one.

Falls back to the bare id when a map has no bank, so a cache imported before
this gets the same empty box it had rather than a crash.

## A Gen 4 map has no border to walk on

Reported: *"im able to walk outside of the boundaries still."*

Gen 1–3 tile a border metatile outside the map and let the player stand on it
for a step, because that is how a map **connection** works — you walk onto the
border and the seam hands you to the neighbour. Gen 4 has neither.
`Gen4Maps.mapDef` sets `borderBlock = 0` with the note *"every cell outside the
map reads as void, which is what the border is"*.

Block 0 is not void. On the stand-in tileset it is ordinary ground, and
ordinary ground is walkable — so the player walked off the edge of Twinleaf and
kept going, over terrain the ground renderer draws quite happily (it draws
whole chunks of the shared matrix, not the map's 32×32 crop) and nothing owns.

`Map:isWalkableCell` now refuses an out-of-bounds cell on a Gen 4 map, beside
the `patchedImpassable` test that already guards that function for the same
class of reason.

**That was the edge, not the destination** — and the destination is below.

`CACHE_FORMAT` goes to `rom-cache-v349:` for the warp and the message bank; the
boundary is engine-side.

## Sinnoh's overworld is one grid, and a map is a window onto it

84 headers name matrix 0, the 960×960 overworld, and each takes a rectangle out
of it. There are **no warps between them**: the player walks from Twinleaf Town
to Route 201 and the header changes underfoot. Nothing in this port knew that,
so sealing the boundary — correct in itself — turned every town into a box.

**The engine already has the machinery.** Gen 1–3 maps connect at their edges,
and `OverworldState:checkEdgeExit` walks the player across a seam with no warp,
reading the neighbour's own collision as it goes. It runs *before* the ordinary
walkability test, which is why the sealed boundary does not block it. A
connection is `{ map, offset }` where `offset` is how far the neighbour is
shifted along the seam, and the landing is `destX = cellX − offset`.

For two windows onto the same grid that offset is exactly the difference of
their origins, which makes this a derivation rather than a guess:

```
up / down     offset = destOriginX − originX
left / right  offset = destOriginY − originY
```

**Adjacency is tested, not assumed.** `connectionLanding` puts an upward step on
the destination's *bottom* row, which is only right when the destination's
bottom edge **is** this map's top edge — so two regions that overlap, or sit
corner to corner, get no connection rather than a wrong one.
`Map:connectionFor` already narrows a multi-neighbour edge to the one covering
the player's position along it, using the same origin arithmetic, so a long
route with three maps down its side needs nothing extra.

Measured over this cartridge: **40 layouts are shared, 69 maps come out with at
least one connection, and there are 140 edges between them.** Spot-checked
against Sinnoh's actual geography:

| Map | Connections |
|---|---|
| Twinleaf Town | `up → Route 201` (offset 0) |
| Route 201 | `down → Twinleaf`, `left → Verity Lakefront` (−32), `right → Sandgem Town` |
| Jubilife City | `right → Route 203`, `left → Route 218`, `down → Route 202` (32), `up → Route 204` (32) |

One supporting fix: the seam reads the *neighbour's* collision, and a Gen 4 map
that references a shared grid has no `blocks` until it is loaded — so
`connectionLanding` now runs `MapLoader.resolveBlocks` on the destination
before testing it. Idempotent, and a no-op on every other generation.

## `callcommonscript` is a real call now

`g4_common` was the one verb still logging *"decoded and lowered but the
common-script archive is not built yet"*, and it is the busiest thing on that
list: **668 call sites** in this cartridge — 652 into `scripts_common`, 14 into
`pokedex_ratings`, 2 into `pokemon_center_2f_common`.

The lowering left it as an unexecutable row on the reading that common scripts
*"are not in the map's own member, and inlining would need the whole common
archive resolved before a single map could lower"*. Both halves of that turned
out to be already done, or nearly:

* `extractScripts` walks **every** member of `scr_seq.narc` — all 1,124 of them
  — decoding each entry point and every block a `goto` reaches. Member 211,
  `scripts_common`, already has **231 blocks in the pool**. The common scripts
  were never missing; nothing could name them.
* a band id is an index into that member's **entry-point list**, exactly as a
  map's own script id is into its own — and `extractScripts` already builds
  that list. Only the thirty band members' lists are written into the pool, so
  it costs nothing.
* which member a band's file is comes from `Gen4Archives.names`, so
  `scripts_common` → member 211 is *derived*, not written down.

So `callcommonscript` lowers to the ordinary call it always was —
`g4_call <ret>` / `jump <label>` / `label <ret>` — into a label in the same
table `goto` and `call` already jump to.

Verified against the cartridge before committing: **all 30 bands resolve, and
all 668 call sites resolve to a block that exists in the pool** — zero
unresolved.

### The third column of the dispatcher

`SCRIPT_RANGE_TABLE` (`script_manager.c`:36) is `Entry(offset, scriptFile,
textBank)`, and `ScriptContext_Load` takes **both** the file and the bank. A
block that lives in a shared file does not read the current map's message
archive — it reads its band's. A common script's `message 3` is entry 3 of
`TEXT_BANK_COMMON_STRINGS` wherever the player happens to be standing, and
resolving it against the town's bank would print some other map's line.

`Gen4ScriptBands.TEXT_BANK` is that column, all thirty bands, resolved to
indices from `generated/text_banks.txt` (line minus one) and cross-checked
against two the port already knew independently — `TEXT_BANK_ROWAN_INTRO` is
line 390 against the 389 `Gen4IntroScene` uses, and the move-name banks are
lines 648/649 against 647/648.

The lowering knows which member a block came from — the label carries it,
`M0211/S0017` — so `message` inside a band emits `g4_message_bank <bank>
<entry>` and needs no map at all.

Spot-checked by reading bank 213 out of the ROM: entry 0 is *"Hello, and
welcome to the Pokémon Center…"*, 1 is *"OK, I'll take your Pokémon for a few
seconds."*, 3 is *"We hope to see you again!"* — the shared lines, which is
exactly what a common script says.

`CACHE_FORMAT` goes to `rom-cache-v350:` so the band tables are written.

## Platinum's second bytecode, and the 3,025 sites that ignored it

`applymovement <localID> <offset>` is every cutscene walk in Sinnoh, every
turn-to-face, every "!" over a trainer's head. The port lowered all of them to
"make the object face the player", because the movement data itself was never
read — the lowering saw an offset and had nowhere to look.

**There is no archive to look in.** `ScrCmd_ApplyMovement` (scrcmd.c) does

```c
MapObject_StartAnimation(object, (MapObjectAnimCmd *)(ctx->scriptPtr + movementOffset))
```

so the commands sit **inside the script member**, at a displacement from the
byte after the instruction — the same way a `goto` target does. That is also
why it has to be decoded during the import: the member's bytes are in hand
then and never again.

A command is four bytes, `{ u16 movementAction, u16 count }`
(`map_object_anim_cmd.h`), and a list ends at `MOVEMENT_ACTION_END`, which
`generated/movement_actions.txt` gives explicitly as **254** — the only entry
in that file with a value written beside it, everything else being its own line
number minus one.

**Measured over all 1,124 members of scr_seq**, following `goto` targets as
well as entry points:

| | |
|---|---|
| `applymovement` sites | 3,025 |
| distinct movement lists | 1,881 |
| members that contain any | 162 |
| lists that decode to a `254` terminator | **3,025 — all of them** |
| refusals | 0 |
| steps | 7,028 |
| distinct actions | 58 |
| list length | 1 to 24 commands |
| repeat count | 1 to 38 |

A format that terminates cleanly three thousand times out of three thousand is
being read correctly. The commonest actions say the decode table is pointed at
the right things: WALK_FAST_SOUTH (723), WALK_FAST_EAST (656), WALK_FAST_NORTH
(641), DELAY_8 (568), WALK_FAST_WEST (543), WALK_ON_SPOT_NORMAL_SOUTH (413).
Walking, turning on the spot, and waiting — which is what a cutscene is.

**The displacement is signed.** Read unsigned, a backward offset becomes four
billion and the list is looked for past the end of the file. `addressOf`
subtracts `0x100000000` above `0x80000000`, and positions are **one-based**
throughout, the way `Gen4Script` counts them — its own `entries` refuses a
target below 1, which is what says so. The first probe read them zero-based
and produced plausible garbage: actions of 256 and 0, counts in multiples of
256.

`Gen4Movement.ACTIONS` maps the 122 named actions to what this engine can
actually do — a direction and a tile count, a facing, a beat, a bubble. The
five walking speeds collapse to one, because the port has one walk speed and
the thing a cutscene is built out of is *where the character ends up*.

**What the 7,028 steps break down into**, and what each now does:

| kind | steps | what runs |
|---|---|---|
| walk | 3,351 | `Commands.walkEntity` — the same claim/yield path `move_npc` uses |
| spot | 1,705 | facing set, then a beat of the entity's own `stepFrames` |
| wait | 893 | `Commands.wait` at the action's own frame count |
| face | 503 | `entity.facing` |
| none | 201 | warp in/out, lock/unlock facing, pause/resume animation — the script's own verbs already do these |
| emote | 178 | `Commands.emote` with the shock bubble |
| hide / show | 177 | `entity.hidden`, which `drawEntity` already honours for the player as well as NPCs |
| unnamed | 20 | skipped |

The twenty unnamed steps are four actions — 106 (×3), 107 (×2), 117 (×11) and
153 (×4) — in the stretch between the player's hand-out animation and the
Distortion World's jumps. `action()` answers nil and the executor skips the
step, which is the one honest thing to do with an animation nobody decoded.

**Two things this gets wrong on purpose, and they should be written down.**

`ScrCmd_ApplyMovement` *starts* an animation and lets the script carry on until
`waitmovement`, so two objects told to move in consecutive rows move together.
Here the second waits for the first. That is a timing difference in a cutscene
rather than a wrong one, and the alternative is a scheduler this engine's
script runner has no seam for — worth knowing before a scene with a crowd looks
stilted.

`objectById` now falls back to `e.def.localId`. The extractor writes the local
id on the **def**, and the lookup only read `e.localId`, which is nil on every
Gen 4 object — so before this, `applymovement` could not have found its target
even with the steps in hand.

A cache written before `rom-cache-v351:` has no `movement` field at all. The
executor detects that and falls back to turning the object to face the player,
which is exactly what it did before — an old cache degrades to the old
behaviour rather than to nothing.

## Signposts were printing nothing at all

`ScrCmd_DrawSignpostInstantMessage` reads `(messageID, signpostType,
narcMember, unused)` and **prints `messageID`**. The lowering was emitting
`g4_signpost_draw` — a placeholder for a sign-box state machine — and dropping
the message on the floor. 159 instant sites and 26 scrolling ones, every one of
them silent.

They now lower to an ordinary message, because that is what they are: the
cartridge draws a wooden frame and prints a line, and this port has a message
box built out of the cartridge's own art. The scrolling variant additionally
emits `g4_signpost_input` for the choice it offers, which writes the chosen
line into the var the script compares — a branch on a register the last script
happened to leave behind is the failure `Gen4Commands` exists to stop.

`g4_signpost_command` and `g4_signpost_wait` are now plain no-ops rather than
`pending()` log lines: with the words printed by the message box, what is left
of that state machine is the frame, and the frame already exists.

## The scripted menu had no destination and no bank

A Platinum field menu is three commands (scrcmd.c):

```
init(global|local)textmenu  anchorX anchorY cursor canExitWithB destVar
addmenuentryimm             entryStringID entryIndex        (once per line)
showmenu                                                     -- blocks
```

and `ResumeOnMenuSelection` waits for `destVar` to stop being
`LIST_MENU_NO_SELECTION_YET`. The port lowered only the middle two. **The
destination var — the entire output of the menu — was dropped**, so every
script that then branched on it read whatever the previous command had left
behind. 161 of the 186 menus write var `0x800C`, which is the same register
`showyesnomenu` uses, so the stale value was usually the last yes/no answer.

**The init also picks the text bank, and the two spellings disagree.**
`ScrCmd_InitLocalTextMenu` hands `FieldMenuManager` the script's own
`ctx->loader`; `ScrCmd_InitGlobalTextMenu` hands it `NULL`, and the manager then
opens `TEXT_BANK_MENU_ENTRIES` itself (field_menu.c). **90 of the 151 field
menus are the global kind** — a port that used the script's bank for all of them
would print the wrong word nearly two times in three. The bank is 361
(`generated/text_banks.txt` line 362 minus one, the same derivation the band
table uses), and reading it out of the cartridge settles it: entry 5 is `EXIT`,
17–21 are `COOL`/`BEAUTY`/`CUTE`/`TOUGH`/`SMART`, 22 is `TRADE`, 23 is `CANCEL`.

What the menu family adds up to across `scr_seq`:

| command | sites |
|---|---|
| `initglobaltextmenu` / `initlocaltextmenu` | 90 / 61 |
| `initglobaltextlistmenu` / `initlocaltextlistmenu` | 29 / 6 |
| `addmenuentryimm` | 487 |
| `addmenuentry` (operands from vars) | 80 |
| `addlistmenuentry` | 164 |
| `showmenu` | 154 |
| `showlistmenu` | 19 |
| `showmenumulticolumn` | 1 |

Menus run 1 to 11 entries, most often 3. `canExitWithB` is set on 169 of 186 —
the other 17 make the player choose, and `src/ui/Menu`'s `cancelable` is exactly
that switch. The initial cursor is row 0 in 184 of 186.

Read end to end out of the cartridge, the department-store lift in member 18
now resolves to `4F=0 | 3F=1 | 2F=2 | 1F=3 | EXIT=4`, picking `1F` writes **3**
into `0x800C`, and B writes `MENU_CANCEL` — `-2` (constants/menu.h), 65534 as a
u16.

**Three things are deliberately not carried.** `anchorX`/`anchorY` are DS tile
coordinates on a 256×192 screen (`anchorX` is 1 in 126 cases and 30 or 31 — the
right-hand edge — in 56 more); this port's menu places itself by its own rules
on a screen of a different size, and passing a foreign coordinate through would
put the box off the edge. `showmenumulticolumn`'s column count is one site in
the whole cartridge and opens as the single column everything else uses. And a
list menu's middle operand is a **second column of text** this port has nowhere
to draw, so the line and the value it stands for are kept and the alt column is
not.

Over every instruction the decoder produces from the archive — 78,093 of them,
following `goto` targets — the share with no lowering handler goes from 7.13% to
6.55%.

## 12.5% of every string in the cartridge was printing its own markup

`Gen4Text.render` spells a Gen 4 text escape as `{STRVAR_1 1 0 0}` or
`{COLOR 0}`. Nothing in the engine read either. The `{RAM:wStringBufferN}` pass
in `show_text` is Gen 1–3's spelling and matched none of it, so **5,747 of the
cartridge's 46,053 strings (12.5%) reached the player with a variable still in
braces** — every "*<mon>* used *<move>*!", every line that says the player's
name — and another **2,068 (4.5%) with a formatting marker**, 4,044 of those
`{COLOR}`. `g4_buffer` had been filling `game.stringBuffers` correctly the whole
time; nothing was reading it.

**Which number is the slot** is the part worth writing down, because three of
the four numbers in that token are not it. `StringTemplate_Format`
(string_template.c) substitutes an escape only when its type's high byte is
`0x100`, `0x500` or `0x600`, and what it substitutes is
`CharCode_FormatArgParam(c, 0)` — the **first parameter**, not the type's low
byte.

Measured over all 46,053 strings, this cartridge uses exactly four escape
families:

| high byte | occurrences | what it is | substituted? |
|---|---|---|---|
| `0x0100` | 8,377 | string template argument | **yes** |
| `0xFF00` | 4,083 | `COLOR` / `SIZE` | no |
| `0x0200` | 191 | `YESNO`/`PAUSE`/`WAIT`/`CURSOR`/`ALN_*` | no |
| `0x0600` | 131 | string template argument | **yes** |

`0x0300`, `0x0400`, `0x0500` and `0x3400` never occur, so three entries in
`Gen4Text.STRVAR_BASES` describe nothing and the one the cartridge does test for
is not in it — harmless, because the substitution is decided here by the
measured families rather than by that table. Within the two that are
substituted, the first parameter runs 0–18 (an argument index, mostly 0–3) while
the low byte takes 53 distinct values, which is the printer's own formatting.
Substituting `0x0200` or `0xFF00` would put a Pokémon's name where a control
code belongs.

The slot numbering needs no adjustment: `bufferplayername <slot>` calls
`StringTemplate_SetPlayerName(template, slot, …)`, `Format` reads
`args[param0]`, and `g4_buffer` files the value at `stringBuffers[slot + 1]`
because Lua counts from one. `Gen4RowanIntro:fill` had already worked this out
for two names — *"the middle number is the variable slot"* — and nothing
generalised it; the general rule now agrees with both that screen and the
cartridge.

Two deliberate choices. **An unfilled slot stays visible** rather than being
blanked: a token in a line nobody buffered for is a bug report, and an empty gap
is silence. **The formatting markers are dropped, not printed** — they are
instructions to a renderer this port does not have — with `PAUSE` and `WAIT` the
exception worth naming: 73 occurrences between them, and dropping them makes
those lines advance without their beat. Everything not on the drop list is left
exactly as it is, which is what keeps `{RAM:…}` intact for the Gen 1–3 pass and
leaves the decoder's own `{TRUNCATED}` and `{UNKNOWN_xxxx}` diagnostics legible.

This one touches shared code — `Commands.show_text` — so it is worth saying why
Gold, Silver, Crystal and Prism cannot see it: `{STRVAR_` and the marker names
are produced by `Gen4Text.render` and by nothing else in the repo, the pass is
an explicit allow-list of those names, and a token it does not recognise is
returned untouched. A Gen 1–3 line reaching it is one `find` and no change.

## Half of Sinnoh was walkable, and the reason was one `%`

Reported from play: *"still able to walk out of bounds"*, with a screenshot of
the player standing in the black above a bedroom. One bug, and it was not in the
collision data — that had been read correctly months ago.

`Gen4Maps.mapDef` packs each cell into the same 16-bit word Gen 3 uses, and it
put the collision flag at **bit 10** — `behaviour + collision * 1024` — because
that is where Gen 3 keeps its own collision bits. But Gen 3 does not read them
from there. `RomExtractorGen3` splits the word at import into `blocks`,
`collisionCells` and `elevationCells`, so the engine's shared decoder,
`Map.blockArray`, ends with

```lua
out[i] = (lo + hi * 256) % 1024
```

— it is extracting Gen 3's metatile id and deliberately discarding everything
above it. Every Gen 4 collision bit was masked off between the importer and the
map.

Measured through the real decoder over 200,000 cells of the overworld matrix:
**the grid marked 199,560 of them blocked and the engine concluded zero.** All
335,165 blocked tiles in Sinnoh — 49.1% of the region, every wall, cliff,
building footprint and stretch of sea — arrived walkable. The `voidOutsideMap`
guard added earlier was doing its job; it just had nothing to guard, because the
black area in that screenshot is *inside* the map rectangle and every cell in it
said "ordinary ground".

The fix is to stop encoding it as a flag and give a blocked cell its own
**reserved cell value inside the ten bits that survive**. 255 is free and
provably so: across all 681,984 tiles the behaviour byte takes 94 distinct
values topping out at 229 (0xE5), the highest word in the cartridge is 0x80E5,
and the stand-in tileset's walkable set is 0..254 — so 255 is a value the
cartridge never emits *and* one the engine already refuses. The border block
goes the same way; it had been 0, an ordinary walkable behaviour, which was the
second way out of bounds.

Checked afterwards by decoding each matrix through `Map.blockArray` and
comparing against the cartridge's own bit, cell for cell:

| matrix | engine blocked | cartridge blocked | |
|---|---|---|---|
| 0 (the overworld) | 837,002 / 921,600 | 837,002 / 921,600 | match |
| 1 | 1,008 / 1,024 | 1,008 / 1,024 | match |
| 2 | 156,142 / 230,400 | 156,142 / 230,400 | match |
| 3 | 870 / 1,024 | 870 / 1,024 | match |
| 10 | 1,486 / 2,048 | 1,486 / 2,048 | match |
| 40 | 1,013 / 1,024 | 1,013 / 1,024 | match |

Nothing in Gen 1, 2 or 3 is touched: the encoding and the reserved value live in
`Gen4Maps` and `Gen4Tileset`, and `Map.blockArray` is unchanged.

## Nobody a script dismissed ever stayed dismissed

Reported from play: *"im seeing characters that are supposed to be parts of
later events/flags."*

Every Gen 4 object event carries a `hiddenFlag`, and `sub_020620C4`
(map_object.c) spawns one only when

```c
ObjectEvent_HasNoScript(e) || FieldSystem_CheckFlag(e->hiddenFlag) == FALSE
```

— so an object **with** a script is absent exactly while its flag is set, and an
object without one (script `0xFFFF`) ignores the field entirely. The other half
is `ScrCmd_RemoveObject`, which calls `MapObject_SetFlagAndDeleteObject`: it
**sets** the flag and then deletes the live actor, which is what makes a
dismissal permanent.

The extractor wrote the field as `flag` and nothing read it; the port's
`g4_hide_object` wrote only the live half. So every character a script sent away
was standing there again on the next visit. **1,566 of the cartridge's 3,555
object events (44.1%) carry such a flag**, across 688 distinct flags; the other
47 flagged objects are scriptless and the cartridge ignores their flag too.

The def now also carries `eventFlag`, spelled by `Gen4ScriptVM.flagName` — the
same name `setflag` and `checkflag` use — and `OverworldController.objectVisible`
already reads `obj.eventFlag` out of `save.flags` with the same "flag set means
hidden" polarity Gen 2 has. So the visibility code needed no new branch;
`g4_hide_object` and `g4_show_object` write the flag as well as the actor.

## The rival's name was filed under a key nothing writes

Reported from play, as a screenshot of a text box reading
`that to my /STRVAR_1 3 1 0/./`.

Two faults stacked. `g4_buffer`'s rival branch read
`save.rivalName or save.player.rivalName`, and neither exists — `Gen4RowanIntro`
stores the answer as `save.player.rival`, which is the field `BirchSpeech`, the
FireRed speech, `Gen2Commands` and `BattleState` all use. So slot 1 was never
filled.

And then the substitution pass, added the same day, **left an unfilled slot
visible** on the theory that a token on screen is a bug report. It is — but it is
a bug report delivered to the player, mid-sentence, in a font that has no braces.
An unfilled slot is now dropped and the report goes to the log, once per slot per
session. A malformed token with no slot number at all is still left alone,
because that is a decoder fault rather than an unfilled one.

## How Platinum actually draws the field, read end to end

Asked for directly: *"find out how its supposed to draw the world in 3d as well
as the map boundaries."* This is the whole chain out of pokeplatinum and the
cartridge, because the port is going to be rebuilt against it.

**The unit.** `MAP_OBJECT_TILE_SIZE` is `16 * FX32_ONE` and an object's position
is `MAP_OBJECT_COORD_CENTER_TO_FX32(c) = (c << 4) * FX32_ONE + 8` — **one tile
is 16 world units**, and a thing standing on a tile stands at its centre.

**The chunk.** `MAP_TILES_COUNT_X` and `_Z` are 32, so a land chunk is a
512-unit square. `LandDataManager_CalculateRenderingPosition` places its model
at

```c
position.x = 16 * MAP_OBJECT_TILE_SIZE + mapMatrixX * 32 * MAP_OBJECT_TILE_SIZE;
position.z = 16 * MAP_OBJECT_TILE_SIZE + mapMatrixZ * 32 * MAP_OBJECT_TILE_SIZE;
position.y = MapMatrix_GetAltitudeAtCoords(...) * (MAP_OBJECT_TILE_SIZE / 2);
```

— the mesh's own origin is the chunk **centre**, which is what `Gen4Terrain`
already found from the other end (`posScale` 32, vertices running −8..+8), and
the matrix carries a per-chunk **altitude** in half-tiles that the port does not
yet apply. `LandDataManager_RenderLoadedMaps` loops `QUADRANT_COUNT` — **four
chunks are resident and drawn at a time**, not nine.

**The camera.** `Camera_AdjustPositionAroundTarget` puts the eye at

```
eye = target + ( sin(yaw)·d·cos(ax), sin(−ax)·d, cos(yaw)·d·cos(ax) )
```

with `ax = −pitch`, and `yaw` is 0 for all seventeen field types — so the eye is
always due south of its target and above it, with `up` = +Y. The screen axes
that fall out are `right = (1,0,0)` and `up = (0, cos p, −sin p)`, giving

```
screenX =  dx
screenY = −dz·sin(pitch) − dy·cos(pitch)
```

**Ground depth scales by sin(pitch); height scales by cos(pitch).** At pitch 90
— straight down — that is ground 1:1 and no height, which is the flat bake.

**The projection.** `Camera_ComputeProjectionMatrix` is `NNS_G3dGlbPerspective`
with aspect 4/3, near 150, far 900 (`CAMERA_DEFAULT_NEAR_CLIP` / `FAR_CLIP`) and
`sin`/`cos` of `verticalFov`, which is the **half** FOV. The orthographic branch
builds its box as `top = tan(fovY)·distance`, and that product is 94.82 for
DEFAULT, 96.21 for INTERIOR, 96.13 for CAVE and 95.15 for ZOOMED_IN — all half
of the DS's 192-row screen. **One world unit is one screen pixel at the target
plane**, on every camera in the table.

**What the port's stand-in costs, exactly.** `Gen4Ground` draws an oblique: it
scales ground by 1 and height by cot(pitch). Since cot = cos/sin, that is the
cartridge's own picture **stretched vertically by 1/sin(pitch)** — 16.6% at
DEFAULT, 30.4% at INTERIOR's 50.09°, 12.0% in caves. Shapes are right; the world
is too tall, and a too-tall world reads as a flat one.

**And what perspective would add on top of that**, measured on the ground plane
rather than waved at: at the top and bottom edges of the screen the scale
differs from the orthographic one by 14.2% (DEFAULT), 16.7% (CAVE) and 18.5%
(ZOOMED_IN). An earlier note in `Gen4Camera` put this at "about a tenth"; that
figure was measured on the depth the screen covers rather than on the scale at
its edges, and these are the numbers that describe what a player sees. For
INTERIOR it is moot — the cartridge is orthographic there, as it is for **300 of
the 593 map headers**.

**The geometry is all present.** Re-checked this pass: all 666 land chunks pack
cleanly, 7,547 shapes and 599,389 triangles between them, every one with a BDHC
beside it. Nothing is missing from the extraction; what is missing is the draw.

**So the step is this, and it is not small.** Replace the oblique with the
cartridge's own orthographic camera — ground × sin(pitch), height × cos(pitch)
— which means the ground plane stops mapping one to one, which means every
sprite has to be placed through the same projection instead of blitted at its
map pixel. `Gen4Camera.project` / `unprojectGround` are that projection, added
and tested this pass; the wiring is `Gen4Ground`'s bake matrix and blit
position, the overworld's camera origin, and the per-entity seam that `riseOf`
already uses. Perspective proper, and depth-sorted billboards, sit on top of
that once the orthographic form is correct.

## Every map has a second script, and the port read only the first

Three reports from play, one cause: *"theres a woman thats part of a script
blocking the door and mom does nothing as i come down stairs and my rival
doesnt talk to me as i approach the stairs."*

A Gen 4 map header names **two** members of `scr_seq`. `scriptsArchiveID` is
the one everything has read — what an object or a sign runs when you talk to
it. `initScriptsArchiveID` is the map's own entry conditions: what runs when
you walk in, and what the cartridge watches every idle frame while you stand
there. `Gen4MapHeaders` has parsed the field since the day it was written and
**nothing ever read it**.

The table is five-byte records terminated by a zero type byte
(`FieldSystem_GetFixedInitScriptID`, script_manager.c), with the four payload
bytes read according to the type:

| type | | payload | when |
|---|---|---|---|
| 2 | `ON_TRANSITION` | u16 scriptID | walking in |
| 3 | `ON_RESUME` | u16 scriptID | coming back to the field |
| 4 | `ON_LOAD` | u16 scriptID | the map being built |
| 1 | `ON_FRAME_TABLE` | u32 offset | a second list, below |

The frame table sits at that offset from the byte *after* its own u32 and is
rows of `u16 a; u16 b; u16 scriptID` ending at a zero `a`. `field_control.c`
asks it from three places in the input loop, every idle frame, and the first
row whose two sides are equal starts its script.

**Both sides go through `FieldSystem_TryGetVar`**, which answers a var's value
when the id names one and **the id itself** when it does not. So a row is not
"var equals var": it is "whatever these two resolve to, compared". Reading the
right-hand side as a literal always happens to be right for all 207 rows in
this cartridge and is wrong in principle, so the port applies the rule rather
than the shortcut — `Gen4Commands.valueOf` on both sides.

Measured over all 594 headers: **291 carry a table** — 236 `ON_TRANSITION`, 46
`ON_LOAD`, 36 `ON_RESUME`, and 105 frame tables with 207 rows between them.
Every one of the 525 script ids they name resolves: 343 to an entry in the
map's own script member, 182 to a block in a shared band, none dangling. One
record in the cartridge has a type byte of 14, which is not one of the four; it
is counted and skipped rather than guessed at.

**Twinleaf, exactly.** Header 414 (`T01R0201`) is the player's house, and its
table is

```
on_transition  -> script 1
frame: var 0x40A4 == 0 -> script 2
frame: var 0x410F == 1 -> script 11
frame: var 0x40A4 == 3 -> script 3
```

Entry 2 of its script member decodes to `lockall / applymovement 0xFF /
applymovement 0 / waitmovement / setflag 0x87 / bufferplayername /
bufferrivalname / message 0 / ... / setvarfromvalue 0x40A4 1 / releaseall`, and
message 0 of bank 557 is *"Mom: {player}! {rival} already left. I don't…"* —
the scene that was reported as not happening. Entry 3 ends with
`giverunningshoes`. With nothing reading the table, `0x40A4` stays 0 for ever:
Mom never moves, the scene that would clear the doorway never runs, and the
actor standing in it stays standing in it. Checked on a fresh save, exactly one
of those three rows fires and the other two correctly stay quiet.

**It needed no new engine seam.** `MapScripts` has declared `onEnter` and
`onFrame` since Gen 3 — Emerald has the same mechanism — and the overworld
already asks for both. So the Gen 4 side produces the shapes `Gen3ScriptVM`
already produces: entry scripts are *queued* rather than run (a map load can
happen mid-warp, while the warp's own runner is still suspended-alive), and a
frame row that has fired is not asked again until its two sides stop matching
— on the cartridge nothing stops a row re-firing, because a scene all but
always rewrites the var it is gated on, but one that did not would otherwise
run every frame, which is a hang rather than a glitch.

## The third thing on a map that runs a script

Reported from play, once the init tables were in: *"she doesnt say anything
unless i talk to her but mom is talking to me when i come down the stairs."*
Both halves of that sentence are one table.

A Gen 4 map has **three** sources of script: the object and sign scripts an
event carries, the init-script member the header names, and the map's
**coordinate events** — triggers that fire when the player stands inside a
rectangle and a var holds a value. `def.coordEvents` has been written by the
maps stage since that stage was written, and read by nothing.

`sub_0203CC14` (unk_0203C954.c) is the whole test:

```c
(x >= e.x) && (x < e.x + e.width) && (z >= e.z) && (z < e.z + e.length)
    && (FieldSystem_TryGetVar(fieldSystem, e.var) == e.value)
```

Two things in it are worth writing down, because both are easy to get wrong
from the shape of the record alone:

- **The extent is a rectangle**, tested half-open. 114 of the cartridge's 186
  coord events are a single cell; the other 72 are not — up to 8×1 and 1×6.
  Taking the corner as the whole trigger silently loses most of a doorway.
- **Only the var side goes through `TryGetVar`.** The value is compared raw.
  That is the opposite of the init frame table, two functions away, where
  *both* sides are resolved — they look like the same test and they are not.
  No coord event in this cartridge has a value at or above 0x4000, so the
  distinction never bites here; it is written the cartridge's way anyway.

186 triggers across 76 maps, every one gated on a real var (all 186 `variable`
fields are at or above 0x4000).

**Twinleaf, again, exactly.** `T01R0201` has one coord event:

```
(6,10)  1x1  var 0x40A4 == 1  ->  script 5
```

and warp 1 of that map is at **(6,10) as well** — the exit tile. The object the
player reported as "blocking the door" stands on it because the cartridge means
you to walk into her and have the scene play; her *object* script (entry 6,
*"{rival}'s mom: Let me think... Knowing my boy…"*) is a different thing
entirely, which is why pressing A on her worked and walking into her did
nothing. And the var it wants is the one Mom's frame-table scene sets: come
downstairs, Mom talks and writes `0x40A4 = 1`, and the door trigger is live.

It needed no new seam either: `MapScripts` already declares `onStep`, and the
memory that keeps one row from running twice per visit — keyed on
`overworld.cellSerial` as well as the cell, because a script that walks the
player back off a trigger does not report a step — is Gen 3's, unchanged.

**Three object verbs went in with it**, because the same map calls all three
and only one was lowered. `setobjecteventdir` and `setposition` write the live
actor *and* its def, so a scene that turns somebody to face the stairs has them
still facing the stairs the next time you walk in.
`setobjecteventmovementtype` is deliberately partial and says so: Gen 4's
movement types are their own numbering and this engine's NPC only knows Gen 3's,
so the value is recorded on the def and the behaviour is not derived — mapping
one onto the other because both are small integers is how an NPC ends up
spinning on the spot. Unhandled instructions across the archive: 6.55% → 6.27%.

## One character was two of the text bugs

Reported from play: *"still seeing weird \ symbols in text and the text is
auto scrolling instead of having me hit a when the box is filled."* One
character, both symptoms.

`TextBox` has three markers: `\n` (second line), `\v` (wait for A, scroll one
line up) and `\f` (wait for A, clear the box). `Gen4Text` decoded the
cartridge's three control characters as `\n` (0xE000), **`\r` (0x25BC)** and
`\f` (0x25BD) — and `\r` is not one of them. So every scroll-and-wait fell
through as an ordinary character: a stray glyph on screen, and no wait.

It is **13,576 occurrences across 7,407 of the cartridge's 46,053 strings** —
every line long enough to need a second box. Mom's own line in Twinleaf carries
three of them:

```
Mom: {STRVAR_1 3 0 0}!<WAIT>{STRVAR_1 3 1 0} already left.<WAIT>I don't know
what it was about, but\nhe sure was in a hurry!<WAIT>
```

`Gen4RowanIntro` and `Gen4StarterSelect` split their pages on `[\r\f]` and now
split on `[\v\f]`. Corroboration from the cartridge, incidentally:
`FieldMessage_Print` calls `RenderControlFlags_SetAutoScrollFlags(AUTO_SCROLL_DISABLED)`
— a field message is *never* meant to scroll on its own.

## The dialogue box was the Game Boy's

*"the textbox should fit the bottom of the screen currently text is spilling
outside of it."* It was `Theme`'s default — 20×6 tiles at row 12, wrapping at
18 **characters** — with a DS font printing into it, because nothing ever told
the theme otherwise. Gen 3 has had its own since its message window was
measured; Gen 4 had not.

`FieldMessage_AddWindow` (field_message.c) is the whole answer:

```c
Window_Add(bgConfig, window, BG_LAYER_MAIN_3, 2, 19, 27, 4, 12, ...);
```

— left 2, top 19, **27 tiles wide and 4 tall**, which is the text interior with
the frame drawn round it by `Window_DrawMessageBoxWithScrollCursor`. On a
32×24-tile screen that is x 16..232, y 152..184.

Two things had to follow it. **`maxPixels`, not `maxCols`**: wrapping by
character count is right for a fixed-width Game Boy face and meaningless for the
DS's proportional one, and `TextBox` already knows how to wrap to a pixel width —
27 tiles is 216 pixels. And **the surface**: `Theme.uiSize` picks the smallest
real screen the box fits on, and its list stopped at the GBA's 240×160. Sinnoh's
box needs 192 rows. The list now has the DS on the end, so the same rule that
has always given Gen 1 and 2 the Game Boy screen and Gen 3 the GBA one gives
Gen 4 the DS one:

| box | needs | surface |
|---|---|---|
| Gen 1/2 — 0,12,20,6 | 160 × 144 | 160 × 144 |
| Gen 3 — 1,14,28,6 | 232 × 160 | 240 × 160 |
| Gen 4 — 1,18,29,6 | 240 × 192 | 256 × 192 |

## `addobject` could not add an object

Found while checking Barry's scene rather than reported. His arrival in the
player's bedroom is

```
clearflag 0x173 / addobject 0 / applymovement 0 ... / message / ...
```

and he is hidden when the map loads — 0x173 is one of the 112 flags the
new-game script sets. So by the time `addobject` runs there is no live actor
with localId 0 to find, and `g4_show_object` looked only among the spawned
entities. The `clearflag` in front of it happens to re-sync him, so this
particular script worked; one that called `addobject` without a `clearflag`
would have found nothing. It now falls back to the map definition and asks the
overworld to spawn from the object's own record — the same call `clearflag`
makes, so there is one mechanism rather than two.

## Two that are not fixed, and what they need

**Masking.** *"Certain tiles that would mask my character arent masking it."*
Correct: the ground is drawn in one pass before the sprites, so nothing
overdraws them. Under the oblique projection the rule that would be right is
painter's order by row — geometry whose foot is SOUTH of a character leans up
the screen and should cover them — which means interleaving the ground with the
sprite pass by tile row rather than drawing it whole. The bake makes that
awkward: a chunk is one canvas. The two routes are a per-row slice of that
canvas, or a height-clipped second pass (a `heightClip` uniform in
`Gen4Model`'s shader, drawing everything below a threshold before the sprites
and everything above after). Neither is a small change and neither is guessed
at here.

**"Still not showing the world in 3d like it should."** What is on screen is
the oblique projection working — a house shows its door and its front wall,
which a straight-down view cannot. What it does not have is *perspective*:
parallel lines stay parallel and nothing converges with distance. Getting there
means abandoning the bake-and-blit entirely and drawing the chunk meshes
through `Gen4Camera`'s real perspective matrix every frame, with every sprite
billboarded into the same camera — because the moment the projection stops
being affine, the tile grid and the ground stop agreeing and every sprite has
to be projected rather than blitted. The measurement in the camera section
stands: on this cartridge the perspective is worth about a tenth at the top and
bottom of the screen, and nothing at the centre.

## Completion tracker — the systems by name

Two separate questions per system, and conflating them is how a project
convinces itself it is further along than it is. **Extracted** means the data
and art are out of the cartridge and in the cache. **Running** means the engine
draws it and the player can use it.

| System | Extracted | Running | What is missing |
|---|---|---|---|
| Battle backgrounds | **Done** — 69 images, all 23 × 3 | No | battle scene renderer |
| Battle terrain platforms | **Done** — assembled from the cell banks, exact | No | battle scene renderer |
| Healthboxes / type icons / interface | **Done** — assembled, real sizes | No | HP-bar logic |
| Battle *engine* (turns, damage, AI) | n/a | No | turn loop and AI; the damage **constants** are now `gen4_platinum`, measured — what is left is the ability/held-item hooks |
| Move data and effects | **Done** — 471 moves | Partly | effects not lowered to engine verbs |
| Species, stats, learnsets, evolutions | **Done** — 508 species | No | stat calc uses Gen 4 stat order already |
| Trainers and parties | **Done** — 928 | No | needs the battle engine |
| Wild encounters | **Done** — 183 areas | No | needs the field + battle handoff |
| Summary / stats screen | **Done** — 10 pages | No | page wiring, text placement, fonts |
| Party screen | **Done** | No | same |
| Start menu (icons, frames) | **Done** | No | the two-style switch is designed, not built |
| Message-box art (the other 25 pieces) | **Done** | Partly | the scroll cursor and wait dial are not animated |
| Bag | **Done** | No | item-use plumbing |
| Trainer card | **Done** | No | badge state |
| Poketch | **Done** — pieces assembled per cell | **Partly** — the watch opens on the second screen and 7 of 25 apps are live | the other eighteen apps' logic |
| Town map / Pokedex / mail / berry tag | **Done** | No | screen logic |
| Title screen | **Done** — art, and `titledemo.narc`'s 3D is now extracted (`title_gira`, `op_ana`, `op_kao` with their animations) | **Yes** | the eleven-state intro, Giratina and its camera, the attract loop, the erase combination, the cry and the BGM |
| Main-menu intro (`gf_presents`, logo, borders) | **Done** | **Yes** | the portal between card and title is the NSBMD |
| Main menu (CONTINUE / NEW GAME / OPTION) | **Done** — bank 550, real layout | **Yes** | windows now drawn frame-inclusive (224x32 per row, centred); scrolls rather than cutting off |
| Window frames / dialogue frames | **Done** — 2 standard, 20 dialogue | **Yes** | wired into `Font.drawBox`, so every box in the game |
| OPTIONS screen | **Done** — bank 220, 53 strings | **Yes** | BUTTON MODE's `START = X` stores and does nothing |
| Trainer card | **Done** — badge case + badges are the cartridge's; the face is this port's | **Yes** | the card's own art composes now; the screen does not use it yet |
| Bag | **Done** — 8 pockets, bank 395, the cartridge's screen and icons | **Yes** | shop and PC pushes still go to the Gen 3 screen |
| Poketch app table | **Done** — 25 apps, names and order from two banks, permutation-checked | Loadable | no screen yet; the app faces' palettes are unresolved |
| Screen tilemap pairing | **Fixed** — `_bg_tiles`, two-sheet bases, and per-archive `tilesFrom` | **Yes** | several Poketch faces still compose black on black |
| Summary pages | **Done** — INFO / SKILLS / BATTLE MOVES, bank 455, rows measured off the art | **Yes** | condition, contest moves and ribbons are not drawn |
| Gen 4 cache modules reaching `game.data` | **Done** | **Yes** | `GEN4_PREFIXED` in `Data:load`; four modules, each optional |
| Overworld sprite facings | **Done** — read from `mmodel.narc`'s own 25 frame-sequence tables | **Yes** | needs a re-import (`rom-cache-v338`); run frames 4-7 are decoded but the renderer has no dash pose |
| NPC dialogue | **Done** — 1,908 objects and signs carry their script label, 374 maps attach | **Yes** | 2.2% of instructions lower to `g4_unimplemented`; the trainer-battle handoff, the shop screen and the scripted menu are still `pending()` |
| Coordinate triggers | **Done** — 186 across 76 maps, rectangles and var gates | **Yes** — `onStep` | — |
| Map init scripts | **Done** — 291 of 594 headers, 318 callbacks, 207 frame rows, 0 dangling | **Yes** — `onEnter` and `onFrame` | — |
| Map collision | **Done** — 681,984 tiles, matches the cartridge bit for bit | **Yes** | elevation (bridges) is still flat |
| Object visibility flags | **Done** — 1,566 of 3,555 object events | **Yes** | — |
| Cutscene movement | **Done** — 3,025 `applymovement` sites, 1,881 lists, 7,028 steps, 0 refusals | **Yes** — walks, turns, beats, emotes and hide/show all execute | the cartridge runs a movement list asynchronously; here the script waits for it |
| Scripted menus | **Done** — 186 menus, 731 entry rows, both text banks | **Yes** — words, destination var, cursor row and the B rule | the anchor coordinates and the list menu's second text column |
| Text variables and markup | **Done** — every bank flattened | **Yes** — `{STRVAR_1/6}` filled from the string buffers, formatting markers dropped | `PAUSE`/`WAIT` timing (73 occurrences) is dropped rather than honoured |
| Pokedex | **Done** — the entry page is composed from four stamped tilemaps over `entry_main` + `banner_sinnoh.NCLR`; height/weight/category from banks 709/707/711 | **Yes** | the list page's own art (`scroll_main_background` + the sprite wheel), the Sinnoh dex order, the search and area pages |
| Field tiles / world art | **Done** — 666/666 packed chunks, 3,130/3,130 texture PNGs, 289 matrix grids, attribution 175/175 owned cells, 590/590 building models | **Yes** — `Gen4Ground` bakes a chunk top-down per map with its buildings on it, behind one branch in `TileRenderer:drawWindow` | the BDHC height under the player, and the field animations |
| Party menu | **Done** — field list, panels measured off the art, SUMMARY/SWITCH | **Yes** | battle, TM teaching and team order stay on the Gen 3 screen; no GIVE |
| Item table alignment | **Fixed** — 445 of 445 items in the right pocket (was 112) | **Yes** | 22 items existed only after the fix |

| Opening: TV broadcast + Rowan | **Done** — banks 389/607, 3 TV layers, 5 backdrops, 10 figures | **Yes** | the control/adventure lectures are extracted, not offered |
| Player's own overworld sheets | **Done** — walk/bike/surf/fish/ball, both characters | **Yes** | nothing; found by name, pairs cross-check |
| NSBMD geometry (models) | **Done** — 1,030 of 1,030 exact | **Yes** | — |
| NSBMD materials + textures | **Done** — shape→material→texture→palette, all 1,030 | No | same: nothing draws it |
| 3D animation structure (5 formats) | **Done** — 378 of 378, 279/280 resolve | No | — |
| Texture SRT / pattern / colour / visibility values | **Done** — 98 + 72 + 24 + 3, all decode and check | Loadable | nothing draws them: the map meshes they belong to are not built |
| Joint animation values (NSBCA) | **Done** — 1,099 blocks walked, 183 tile exactly, 1,099 tracks round-trip | **Yes** | the other four formats are structure only |
| Node transforms + SBC pose | **Done** — every node block tiles; pose replayed, not baked | **Yes** | header bounding box left unread, see open questions |
| Model packing for the cache | **Done** — 1,030 round-trip exactly | n/a | starter set published; the rest on demand |
| 3D mesh renderer | **Done** — shader, depth, index buffers, per-shape pose | **Yes** | one screen calls it; the world pass still does not |
| Starter select (briefcase + balls) | **Done** — `psel_all` + its 41-frame opening, bank 360 | **Yes** | the chosen ball is lifted rather than animated; never seen on a screen |
| Fonts | **Done** — published as `data.font`, the shape `Font.lua` reads | Loadable | nothing Gen 4-specific; the screens above must call it |
| Boot / start position / heal points | **Done** — 1 start, 20 heal rows | **Yes** | nothing — this is the first Gen 4 table the engine actually consumes |

Honest reading of that table: **the cartridge side of presentation is
finished and the engine side has started at the front door.** The boot,
the title, the main menu and every window frame in the game now draw; the
summary screen, the party screen, the bag and the battle still do not. That is the
intended order — nothing can be drawn before it can be read — but it means
"Platinum boots into a battle" is still several systems away, and the tracker
should not be read as though it were close.

Two known gaps inside the "Done" column, stated so they are not discovered
later as surprises:

* **The renderer exists; most of the screens still do not.** `Font.lua` loads
  Gen 4's fonts, lays out a line proportionally and now draws Platinum's own
  window frames, all with no Gen 4 branch in the text path. The main menu, the
  title and the intro call it. Nothing else does yet: no Gen 4 field text box,
  no start menu, no summary screen.
* **The title sequence's Giratina is an NSBMD** — a 3D model, not a tilemap.
  The stills around it extract; the animated centrepiece needs the same 3D path
  the map meshes do.

---

## What remains, in dependency order

1. **Actually booting a Platinum map.** Module loading passes, the import
   runs, the boot config is now Platinum's own rather than Red's, and the
   intro, title, main menu, OPTIONS screen and now the television-and-Rowan
   opening in front of it are Platinum's too, and the player wears Platinum's
   own sprite. A map loads, and it is the right map. What is still missing is
   what it LOOKS like:
   a Gen 4 tileset, the permission grid, the warp table. This is different work
   from everything above it — the extraction side has been checkable offline
   and this is not, so expect the surprises here, one at a time.
   `importable` is now `true`, so no `POKEPORT_UNLOCK` is needed to try it.
2. **What switches a form.** Every form picture is extracted now, but nothing
   chooses between them: Castform still needs the weather, Cherrim the sun,
   Rotom its appliance, Arceus the held plate, and Unown a letter from its
   personality value. Battle and party logic rather than extraction — which is
   why `def.forms` is written and not yet read.
3. **Map meshes** — still the single biggest thing between this and something
   that looks like Platinum, but the reading is done: all 666 terrain meshes
   and all 590 building models decode exactly, and the terrain agrees with the
   height field it was never read from (see *The map meshes, and the block that
   agrees with them*). What is left is which texture set each map wears, where
   the floor comes from on the 9,497 walkable tiles the land mesh does not
   cover, and a way to draw any of it. Every map
   currently draws as the synthesised stand-in: one flat colour per terrain
   class, so a bedroom and a meadow are the same green and the world is
   navigable but unreadable. Reported from play as "I spawn in a weird area
   that isn't my bedroom" — the spawn was right and the picture was not. The
   `BDHC` height half is extracted and the permission grid works, so this is
   the art half alone.
4. **The dual-screen UX and the two start-menu styles** — the Poketch/bottom-
   screen toggle, the corner overlay with its hotkey and resize, and the choice
   between a main-screen start menu and the bottom-screen one. Designed and
   documented in this file, not yet built; it is engine work rather than
   extraction work, so it sits behind booting a map.

**Closed since the last revision.** *What the special script-id bands mean* —
all thirty of them, read out of the cartridge's own dispatcher; see *Thirty
bands, and the lookup that could not miss*. *Where the field objects' art
actually lives* — it was in `mmodel.narc` the whole time, under the names the `.order`
file gives, and the reader was wrong; see *The dictionary that was only right
for two*. *A3I5 and the 4x4 block texture formats* — there are none in this
archive; the 279 entries that appeared to use them were the same misread.
*Species sprites through the extractor* — done as its own stage; see *Species
pictures, and the sixteen with no male sheet*. *Form sprites* — all 78 of them,
plus the Substitute doll and the battle shadows; see *The archive with two
orderings inside it*. *Where a new game starts* — and why it was silently
starting in Kanto; see *The crash that proved the cache was reading Red's
world*. *The intro, the title and the main menu* — with the eighteen-tile
dialogue frame that decides every box in the game; see *The title, the card and
the menu*. *The OPTIONS screen* — including the value order that would have
silently stored the wrong sound mode; see *OPTIONS, and the row that would have
stored the opposite*. *The opening*, both halves of it, and the player's own
sprite; see *The opening, read out of the cartridge*.

### Turning it on

**`importable` is now `true`, and `experimental` is still `true`. Those are two
separate claims and both are meant.**

The flag was held while the extractor could not fill a cache the engine would
mount. It can: a Platinum import writes **28 tables and satisfies all 15
modules `Data.lua` requires, none missing**, and the cache identifies itself as
Gen 4 rather than falling through to the Gen 3 branch. Holding it past that
point stops being caution and becomes the reason nobody can find the next bug —
everything left is on the far side of a boot, and a boot is the one thing that
cannot be checked offline.

**What is proven:** the cartridge reads, the tables extract, the art decodes and
the cache loads. **What is not:** anything after that. No Gen 4 map has been
walked, no Gen 4 battle has run, no Gen 4 text box exists. So the launcher
offers the import and says, in the same breath, that nobody has played the
result — which matters *more* now that the button works, not less.
`POKEPORT_UNLOCK=platinum` is no longer needed.

**One thing had to be fixed before the flag could be trusted.**
`requiredFiles` in `RomImporter` had no generation-4 case and fell through to
the **Gen 1** list. A Platinum import that had produced everything it can would
have been measured against `field.lua`, `battle_anims.lua`, Pikachu's battle
sprite, two move animations and the audio program bank — none of which Gen 4
produces or needs. The launcher would have reported the same five gaps after
every successful import and offered to spend the minutes again, for ever. The
failure mode is the nastiest kind: *the import works*, and the only symptom is
the game asking for it again. `REQUIRED_FILES_GEN4` is the fifteen modules the
Gen 4 branch actually requires.

The import route itself was already wired: the extractor table's fourth entry,
with `takesPath` because `NdsRom` opens the cartridge and reads ranges rather
than being handed 128 MB as a Lua string — and the bytes are dropped *before*
the run rather than after, which is the whole point of taking a path.

**And the first thing the flag found, immediately.**

```
Import failed
src/import/RomImporter.lua:1739: ROM import metadata is missing:
Could not open file tools/rom_manifest_platinum.json. Does not exist.
```

`GameVersion` had named a manifest since the day Platinum was registered and
the file had never been written — invisible for as long as the import could not
be started. `decodeManifest` runs before anything else and reads exactly one
field from it, `romSha1`, so the gate was failing on a file whose only job is to
be openable.

**Why `tools/rom_manifest_platinum.json` is 2.5 KB and Crystal's is 3.7 MB.** A
Gen 1–3 manifest is an *address book*: those cartridges are flat arrays and the
importer cannot find anything without being told where it is. A DS cartridge is
a *filesystem* — 340 files in 89 directories behind an FNT/FAT pair — and every
Gen 4 stage opens a file by name. There is no address to record, so an address
table here would be **invented rather than measured**, which is worse than not
having one.

So the manifest carries what it can honestly carry: which dumps are this game,
and what the cartridge says about itself — title, game code, ARM9/ARM7 extents,
FNT/FAT positions, 122 overlays, 340 files — every value read out of the
cartridge, not copied from this document. `RomExtractorGen4` reads none of it.

The few Gen 4 numbers that *are* addresses deliberately stay out of it: the type
chart in overlay 16 and `gObjectEventGfxTexturesTable` in overlay 5 are both
found by structural search, because Rev 0 is a different binary and a
hard-coded offset would silently read the wrong bytes out of it.

Verified by decoding the committed file with the engine's own `Json` and running
the real gate: `acceptsSha1` passes for both revisions.

**Still stale, and harmless only because it is unreachable:**
`RomImporter.WITHHELD_REASON.platinum` still says Gen 4 extraction is "still
being built". It is read only for a version with `importable = false`, so
nothing shows it now — but it is wrong, and it is the sort of string that comes
back if the flag is ever flipped off.

**What was checked before the button was trusted.** An import runs for minutes
and fails at whatever it reaches first, so the cheap failures were taken off the
board offline. Each of these is a whole-corpus check, not a sample:

| check | why it is not covered by the run passing | result |
|---|---|---|
| every image's payload is exactly `w × h × 4` | `love.image.newImageData` raises otherwise | 5,427 of 5,427 |
| no image has a **zero** dimension | `#bytes == w*h*4` is trivially true when either is 0, so the harness's own assert cannot catch it — but LÖVE still raises | 0 found |
| no image is absurdly large | `image:encode("png")` on one would stall the import | largest is 512×512 |
| no two images share a path | a duplicate silently overwrites and the loss is invisible | 0 found |
| every table re-`load()`s after encoding | a table can write fine and be too big to read back; `map_layouts` is 13 MB | 28 of 28 |
| every path is legal on **Windows** | these filenames come from cartridge strings; `<>:"\|?*`, trailing dots, `CON`/`NUL` | 5,455 of 5,455 clean, longest 73 chars |

**What to expect on the first run.** 28 tables and 5,427 images; the progress
bar names each stage, and BootTrace records one line per stage with the live Lua
figure, which is what to look at if it dies below Lua rather than raising. The
generated Lua is **53.7 MB** across the 28 tables — `map_layouts` 13 MB,
`map_scripts` 11 MB, `maps` 9 MB — plus the PNGs. That is a large cache, and
loading it is the next thing nobody has measured.

When it finishes the cache is mounted, and everything past that is unexplored
ground — the interesting failures start there, which is the point of the flag
being on.

---

## The start menu, and the second screen it no longer has to live on

The other half of the original brief, and the half that had stayed a design
through every round:

> "instead of showing the start menu on the bottom screen have a start menu on
> the main screen like the other games have the choice to switch between the two
> styles."

Both styles exist now, and the switch is a row on OPTIONS rather than a boot
flag, so it changes mid-game.

### What the cartridge says

* **The rows and their order come from `StartMenu_MakeOptionList`, not from the
  enum** — and the two differ, which is the trap. The list is built RETIRE,
  CHAT, POKéDEX, POKéMON, BAG, TRAINER CASE, SAVE, OPTIONS, EXIT, each added
  only if its hide flag is clear; in the ordinary field the first two are
  hidden, so a player sees the last seven. Taking the enum's order instead
  would have put RETIRE and CHAT at the top of every menu.
* **There is no POKéTCH row**, which is worth saying because it is the first
  thing a reader looks for. The Poketch is always on the bottom screen in
  Platinum and is never a start-menu entry.
* **TRAINER CASE is the player's name.** Its bank entry is `{STRVAR_1 3, 0, 0}`
  — a template, not a word — filled by `StringTemplate_SetPlayerName`. Printing
  it raw puts a control code on the menu.
* **Which icon belongs to which row** is `animIdx = option * ICON_ANIM_COUNT`,
  with `ICON_ANIM_COUNT = 3`: each group of three animations (none / swell /
  wiggle — they are scale animations of one picture, not three pictures)
  belongs to one option, in enum order. The single exception is stated in the
  same function: **a female player's BAG is group 9.**

  That also explains why the icon sheet has **ten** cells for **nine** options,
  which is a second table agreeing rather than the same one restated: nine
  options plus the second satchel is exactly ten.
* **The geometry**: the panel at tile (20, 1), eleven tiles wide and three per
  row; icons centred at x = 174 and the cursor at x = 204, both at
  `y = 20 + 24 * i`. Three tiles per row is the 24-pixel pitch the sprite
  columns already use — the window and the sprites stating the same number.

### What is not the cartridge's, and why

**Which rows are available.** Platinum gates each row behind a save flag this
port's Gen 4 save does not carry yet. Reading a flag that is always false would
hide the Pokédex and the party forever, so those two use the same conditions
the engine's own start menu uses — the dex having been handed over, and the
party not being empty — which answer the same question from data that exists.

**SAVE stays the engine's, deliberately and not by omission.** It is the one row
with a consequence: the panel, the confirmation, the "now saving" beat, the
write and the failure message. All of that is already correct in one place, so
the Gen 4 menu fetches that row *from* the engine's menu by its label and runs
its action. Re-implementing it would give this port two save flows that can
disagree, and the one that disagrees would be the one nobody tests.

## Dual screen and the Poketch

`SecondScreen` is built; the Poketch's own app logic is not.

The module answers one question — *where is the bottom screen right now* — in
the same 256×192 space every Gen 4 screen already draws in, and wraps a draw so
a screen can be written once and appear in either place. Three modes: **swap**
(the bottom screen takes the window), **inset** (a panel in the top-right
corner, raised with a hotkey, resizable through a `2ND SIZE` row that cycles
35 / 45 / 55 / 70 %), and **off**.

**It does not own the stack**, and that is the design decision worth recording.
A screen that wants to be a bottom-screen screen asks for the transform and
draws itself; nothing in `SecondScreen` pushes, pops, or knows what is on the
stack. The alternative — a manager that decides which screens are "bottom
screen" ones — puts a second, invisible stack beside the real one, and the first
disagreement between them is a screen that cannot be closed.

Two things it does own because nothing else can:

* **The transform is pushed and popped around the caller's draw**, not left for
  the caller to undo. A screen that forgets to undo it moves everything drawn
  after it, including screens that have nothing to do with it.
* **Pointer routing.** A click inside the panel arrives in the *bottom screen's*
  coordinates, not the window's, which is the whole of "interact with it there".
  Outside the panel it returns nil, so the caller falls through to the field.

`SecondScreen.available` is the single gate, and it answers false for Gen 1–3 —
so no Gen 1–3 options list gains a row and no Gen 1–3 draw path gains a branch.

The start menu is its first real client: on `bottom` style the menu goes through
the surface, so on **inset** it appears in the corner panel and is clickable
there, and on **swap** it takes the window — and `Gen4StartMenu` does not have
to know which.

### The Poketch, seven apps of twenty-five

`Gen4Poketch` is the second-screen surface's other client, and the first line
of the original brief — *"Instead of having two screens for the poketch and
bottom screen allow users to switch between the two with a button"*.

**All twenty-five apps appear and wear their own face; seven of them do
something.** The `menus` stage already pairs each app's name with its
description and its picture and marks the live ones, so the split is data, not
a list in the screen. The other eighteen draw the cartridge's own
`unavailable` panel and say so on screen — because **an app that is drawn and
inert is visibly unfinished, and an app silently missing from the list is
not.**

The seven are the seven because each needs only what this port already has — a
clock, the party, a step count, a number to keep:

| app | what drives it |
|---|---|
| Digital Watch | the system clock, drawn with the cartridge's own digit cells |
| Analog Watch | the same time; the hour hand reads the minute too, so it creeps rather than jumping on the hour |
| Calendar | `os.date`, including which weekday the first falls on — a hand-rolled day-of-week is a bug waiting for a leap year |
| Counter | a number on the save; A adds, SELECT zeroes |
| Coin Toss | `love.math.random`, the engine's generator everywhere else |
| Pedometer | a step counter incremented in `onStepComplete`, gated on the cartridge having a second screen at all |
| Pokémon List | the party with HP bars, green/amber/red — a one-colour bar tells you nothing at a glance, which is the whole point of the app |

The four that were tempting and are deliberately absent: the **Marking Map**
wants the Sinnoh map and roamer positions, the **Berry Searcher** the berry
plots, the **Dowsing Machine** hidden-item placement, the **Matchup Checker**
the type chart applied to a live opponent. None of those is a drawing problem,
and starting them would have put four half-features on the watch instead of
seven whole ones.

**The keys are the port's**, stated rather than implied: Platinum changes app
by tapping arrows on the touch screen, so there is no L/R binding to copy. Here
**L** raises the watch and lowers it again, and **R** (or LEFT/RIGHT) cycles the
app. Both are ordinary actions, so both are rebindable through the controls
menu. L rather than SELECT because SELECT is already the registered key item,
and the whole branch is gated on `SecondScreen.available` so no Gen 1–3 press
changes behaviour.

The watch is pushed by its own id rather than through `GEN4_ALIASES`: there is
no Game Boy Poketch for an alias to stand in front of, so an alias would be a
redirect from a screen that does not exist.

### Still designed, not built

**The eighteen remaining apps.** **The "both screens stacked" mode** — offered in the original design,
left out here because at typical window sizes it makes both screens small and
neither of the two modes that are built has that problem. **A drag handle** on
the inset panel's corner; the size is a settings row for now.

---

### The design this replaces

Design; not built. The requirement is that the second screen is **never a
second window** — the game runs in one window like every other version here,
and the player chooses how the bottom screen reaches them.

### Second-screen modes (switchable at runtime, and in Options)

**1. Swap (default).** One screen is drawn at full size; a key toggles which.
Simple, works at any window size, works on a phone. The DS's own split is
approximated by the fact that the bottom screen is almost never needed
*during* an action — the Poketch and the bag are things you stop to look at.

**2. Inset.** The bottom screen is drawn as a panel in the **top-right
corner** over the main screen, shown and hidden with a hotkey. It is
**interactive in place** — clicks and taps inside the panel go to the bottom
screen's own coordinate space, so the Poketch's buttons, the bag and the touch
controls work without swapping away. Its **size is adjustable** (a scale
setting, and a drag handle on its corner), and it remembers where and how big
it was per version.

**3. Both.** Stacked as the hardware had them, for players who want the
authentic layout and have the window height for it. Offered but not the
default, because at typical window sizes it makes both screens small.

Notes for implementation: the inset panel needs its own input routing (a hit
test before the field's, and pointer coordinates transformed into
bottom-screen space) and its own render target, so field rendering does not
have to know it exists. `GameVersion.isDualScreen(id)` is the gate; nothing
about this should be reachable for Gen 1–3, and no Gen 1–3 draw path should
gain a branch.

### The Poketch

The Poketch is one of the things the bottom screen *shows*, not a third
screen. It gets a slot in the second-screen surface alongside the bag, the
map and the touch controls, and the same hotkey that raises the bottom screen
raises whatever that surface is currently showing. A separate direct hotkey to
raise the Poketch specifically is worth having, since it is the thing players
check most often.

### Start menu

Two styles, player's choice, default to the first:

**1. Main-screen menu (default).** The start menu appears on the main screen
exactly as it does in Red through Emerald — same position, same behaviour,
same keys. This makes Platinum feel continuous with the rest of the launcher's
library and means muscle memory carries over.

**2. Bottom-screen menu.** The authentic DS arrangement, for players who want
it. Uses whichever second-screen mode is active, so on Inset the menu appears
in the corner panel and is clickable there.

The setting belongs with the other per-version options and should be
switchable mid-game, not only at boot.

---

## Mod compatibility

Gen 4 must not disturb the four generations already working. Where things
stand:

* Everything added so far is **new files plus additive registration**. The
  only edits to shared code are in `RomImporter` (one chip, the accepted
  sizes and extensions, one bug fix) and `GameVersion` (one entry, two new
  predicates). No Gen 1–3 branch changed behaviour.
* Mods reach content through the same registries regardless of version, so a
  mod that adds text or sprites should work once Gen 4 populates those
  registries. Mods that hard-code Gen 3 asset ids will not, and should not —
  they are version-specific by construction.
* **A known, pre-existing hazard to keep in mind:** `DRAMATIC_SHAPE` asks for
  `TILESET_03DF704` (Emerald's primary) during FireRed sessions — a mod
  carrying state across a version switch. Gen 4 will make that class of bug
  more visible, not less. Worth fixing before Platinum is playable.

---

## The battle sprites (solved)

`pokegra` and `otherpoke` needed **two** things, and each one disguises the
other.

**1. They are encrypted.** The keystream is the series' usual LCG:

```
key = the FIRST halfword of the tile data
each halfword:  plain = cipher ~ key;  key = (key * 0x41C64E6D + 0x6073) mod 2^16
```

Only the low 16 bits of the state ever matter, so no 32-bit arithmetic is
needed. The first halfword being the key is the same statement as "the picture
starts with transparent pixels", since anything XORed with itself is zero —
the stream is self-seeding and there is no key table anywhere.

**2. They are linear bitmaps, not tiles.** The NCGR layout flag (low byte of
the field at section+20) is `1`, meaning rows of pixels rather than 8×8 tiles.
Measured across every NCGR in the cartridge: 3,872 tiled against 4,160 linear,
and the split is not arbitrary — every sprite archive (pokegra, otherpoke and
the trainer sheets `trfgra`/`trbgra`) is linear; fonts, icons and backgrounds
are tiled. The trainer sheets are linear but **not** encrypted (raw entropy
4.8–5.3), which is how the two properties were separated.

Decrypt without un-tiling and you get real Pokémon colours smeared into
horizontal bands, which reads as "the cipher is nearly right". Un-tile without
decrypting and you get noise, which reads as "the layout is fine, the cipher is
wrong". Neither is a clue about the other.

**How it was found, because the wrong way round wasted real time.** The
published constants were tried and appeared to fail; then all eight
combinations of seed source, direction and key half; then a brute force over
all 65,536 seeds. Every one of those was scored against **member 0 of
pl_pokegra — a placeholder that decrypts to noise no matter what you do to
it.** The algorithm had been right from the first attempt and the test subject
was the problem.

What settled it was not another guess. Assume the leading plaintext is zero,
read the leading ciphertext *as* the keystream, and solve
`k[i+1] = (k[i]*A + C) mod 2^16` for `A` and `C` from the values themselves.
34 of 38 sprites gave `A = 0x4E6D`, `C = 0x6073` — exactly the published LCG —
and the four that disagreed are the ones whose first tile is not blank, so the
"keystream" read from them included picture. **Solving beats searching when
the unknown is small, and a failing test needs its subject checked before its
hypothesis.**

Result: 194 of 194 front sprites decode, none blank, mean transparency 77.3%,
and the rendered sheet is correct Kanto through the legendary birds. The icon
path was re-diffed after the change — zero pixel differences, so the tiled
path did not regress.

## Open questions and known gaps

* **The NSBMD header's bounding box** matches the decoded geometry on only 312
  of 1,032 models. It reads as a corner and a size at 1/2048 — exact on models
  with identity nodes, wrong on the ones with real hierarchies, and not fixed by
  applying the node transforms either. `Gen4Model:framing` measures the box
  itself instead, so nothing depends on the answer; a reading right on a third
  of the corpus is more likely incomplete than the files being wrong.
* **Thirteen of 419 rotation-table crossings** in joint animations are not
  smooth relative to their own channel's motion. They sit in four animations
  (the Spear Pillar cutscene, one Mime Jr. animation) and mostly at frame 2,
  which is what a deliberate cut looks like — but "looks like a cut" is a guess,
  and the only way to settle it is to watch those animations.
* **The sign of the missing element in a compressed rotation** is undetermined
  by the data when the first row's third element is exactly zero. The decoder
  picks one; both choices keep the matrix orthonormal, and the two differ by a
  reflection of one axis. It has never mattered on anything drawn so far.
* **Nine variable-length script commands** (`DOSTRENGTHFUNC`, `DOFLASHFUNC`,
  `DODEFOGFUNC`, `DOGROUPCONNECTIONACTION`, `CALLTVBROADCAST`,
  `CALLTVINTERVIEW`, `MYSTERYGIFTGIVE`, `$27C`, `GIVEPOFFIN`). Each needs its
  handler read individually. The decoder should **refuse** a command it cannot
  size rather than walk past it — a guessed width here is the Sootopolis bug
  again.
* **One script entry point of 4,079** runs past the end of its member. Almost
  certainly one member whose header is parsed slightly wrong rather than a
  table error, since no opcode desynced. Needs a look.
* **`RomImporter:startData` takes the whole ROM as a Lua string** and hashes
  it. At 128 MiB that is tolerable while the import is refused anyway, but the
  real Gen 4 extractor must not go through it — it needs a path-based route
  into `NdsRom`, which already reads on demand. **Design this before writing
  the extractor, not after.**
* **Rev 0 is registered but untested** — no dump on hand. The layout should be
  identical; it has not been confirmed.
* Gen 4's save format is untouched. `saveSuffix "_platinum"` reserves the
  slot and nothing else.
* **`RomImporter.WITHHELD_REASON.platinum` is stale** — it still says Gen 4
  extraction "is still being built". It is unreachable now that `importable`
  is `true` (the panel only reads it for a version it refuses), so it is dead
  text rather than a wrong message on screen, but it will read as current to
  the next person in that file.

## Shadows, and telling a flat world apart from a flat-looking one

Reported from play: *"im only seein the shadows under the player and not for the
object also the shadows under the player arent smooth theyre jumping per tile
barry is still there and the 3d still doesnt seem like its working"*. Four
complaints, and they turned out to be four different kinds of thing.

**The jumping was real and is fixed.** `Gen4Shadows:draw` placed the shadow at
`cellX * 16 + 8` — the tile the entity is *considered* to be on, which only
changes when a step completes. The sprite above it was drawn from `px`/`py`
plus `shiftPx`, the interpolated position the walk animation carries. So the
sprite slid and the shadow teleported. It now reads the same three terms the
terrain height does, so the two agree by construction rather than by care.

**The missing NPC shadows are not root-caused yet**, and the table is not the
problem: graphics 148 carries `shadow = 1`, and the LuaWriter round-trip keeps
all 259 rows with their numeric keys intact. The lookup now accepts
`graphicsId`, `graphics` and `graphicsID`, because a def reaches this from three
places — the extractor's record, the copy `objectHome` hands out, and whatever a
mod or the map editor builds — and asking for all three costs a nil test. If it
still misses, the first miss now logs the def's actual field names, which is the
evidence that was absent.

**Barry needs a new game, not a re-import.** The Gen 4 extractor writes no
`initialFlags`, so the `boot.initialFlags == nil` guard is not blocking
anything; the 112 opening flags are applied at new-game time only. From inside
the game a save that predates them looks exactly like flags that do not work,
which is why this has now been reported three times. `SaveData` logs the count
it applied, so the log settles it in one line.

**The 3D is a measurement problem, not obviously a bug.** The whole path is
live: chunk meshes bake through the projection matrix into a colour canvas with
a real depth buffer, buildings bake into the same buffer, and the blit
compresses by `sin(pitch)`. Two things make it hard to judge from a screenshot:

* **The screenshots are interiors.** `INTERIOR` is camera type 4 — pitch 50.09°,
  *orthographic on the cartridge too*. A Platinum room is a flat floor with flat
  walls; there is almost nothing in one for perspective to act on. Outdoors is
  where the default camera's 59.05° and its leaning houses show. **Judge it in
  Twinleaf, not in the bedroom.**
* **`CAM TILT` at 90° is a flat world on purpose.** Index 2 of `Gen4Camera.TILTS`
  is a straight-down bake with `sin = 1`, which is the 2D picture exactly. It is
  indistinguishable on screen from the camera failing.

`Gen4Ground:applyCamera` now logs the camera id, its pitch, whether it came from
the map header or the OPTIONS row, and both scale factors, once per change.

### The depth format was a single ask

`Gen4Model.newTarget` asked for `depth24` and nothing else. That is the common
desktop format, but drivers that expose only the packed `depth24stencil8` — Intel
integrated parts, anything going through ANGLE — and mobile-derived ones that
offer only `depth16` would have failed it, and failing it turns the **entire** 3D
path off: `bake` returns nil, `noDepth` latches, and `Gen4Ground:draw` returns
false forever after. It now consults `love.graphics.getCanvasFormats` and tries
`depth24`, `depth24stencil8`, `depth32f`, `depth16` in that order, once, and
names the one it got.

This was not confirmed as the cause — the screenshots show real baked art, so
depth is working on *this* machine — but it is a whole class of machine on which
the world would have been silently flat.

### Worth fixing next, found while reading

`TileRenderer:drawWindow` returns immediately after `gen4Ground:draw`, whatever
that call reports. When `draw` returns false — `noDepth`, or every visible chunk
still unbaked — the frame is the backdrop colour and nothing else, and the 2D
stand-in that exists for precisely this case never runs. The `return` should be
conditional on the draw having painted something.

## The opening flags: a seam that was written at both ends and joined at neither

Reported from play four times, finally as *"i cant get out of the house because
his mom is blocking my path"*. That last report is the one that made it
findable, because it is not a cosmetic complaint — it is unwinnable, and it
says exactly where to look.

**The cartridge puts her on the door on purpose.** In
`events_twinleaf_town_player_house_1f.json`, `LOCALID_RIVAL_MOM` sits at
`x 6, z 10` — the same tile as the warp to Twinleaf Town and the same tile as
the map's one coord event. She is meant to be standing in the doorway when she
is visible, and she is meant to be invisible until the story puts her there.
What keeps her away is `FLAG_HIDE_TWINLEAF_TOWN_PLAYER_HOUSE_1F_RIVAL_MOM`,
which `scripts_init_new_game.s` sets along with 111 others.

**Both ends of the port were right.** `RomExtractorGen4` decodes that script
and writes `constants.gen4NewGame = { flags = {...112}, vars = {...3} }`;
`SaveData.newGame` applies `boot.initialFlags` and `boot.initialVars`. The
extractor's own comment says `boot.initialFlags` "is a seam that already
exists" — and then writes `gen4NewGame` instead. **Nothing carried one to the
other.** `Data:seedDefaults` now does, in the Gen 4 branch.

Verified against the cartridge, id by id: the extractor's `FLAG_G4_0173` is
`FLAG_HIDE_TWINLEAF_TOWN_PLAYER_HOUSE_2F_RIVAL` (Barry in the bedroom) and
`FLAG_G4_01F1` is the rival mother, both in the right positions in the list,
and the map object in `maps.lua` carries `eventFlag = FLAG_G4_01F1`,
`flag = 497`, at `x 6, y 10` — the cartridge's own coordinates.

### Why a new game was not enough to say it was fixed

New-game state only reaches a new game. A save written while the seam was open
has none of those flags and never will, so every later fix looked like no fix
at all from inside the running game — which is most of why this took four
rounds.

`SaveData.repairOpeningFlags` closes that. It restores an opening flag **only
where the save has never recorded a value for it**, and that test is only
answerable because `Flags.clear` writes `false` rather than erasing the key —
it exists so that "a script cleared this" can be told from "no script has ever
had an opinion here". A story the player has genuinely advanced past leaves
`false` behind and is left alone; only the flags whose scripts have never run
are put back. That makes it safe on every load rather than once behind a
stamp, and a stamp is the thing most likely to be wrong in a save that is
already wrong. Gen 4 only, so Crystal, Gold/Silver and Prism are untouched.

### What the opening scripts actually needed, measured

The player house 1F is script member **1055**, and its blocks line up with
pret's entries one for one — `OnTransition` is
`comparevartovalue callif checkflag callif end` (pret's `CallIfEq` +
`CallIfSet`), `HideRivalsMom` is `setflag return`, and
`OnFrame_RivalAlreadyLeft` is the full mother-walks-over sequence. Of that
whole member, **six** commands do not lower — `getrandom`,
`giverunningshoes`, `healparty`, `getsetnationaldexenabled`, `gettimeofday`,
`givejournal` — and **none of them is in the opening path**. The opening was
never missing an implementation. It was missing its flags.

### Script coverage across the whole game

Measured over all 8,567 decoded blocks: **73,199 of 78,093 instructions lower
— 93.73%**, across 97 of 718 distinct commands. The 621 that do not are the
long tail, 4,894 instructions between them; the largest are
`getpartymonribbon` (178), `callbattletowerfunction` (146),
`getpartymonfriendship` (143), `waitabpress` (95) and `createjournalevent`
(75). `loaddooranimation` (52) and `playdooropenanimation` (28) are why doors
do not animate. This is the list to work down, by frequency, and it is now
reproducible rather than anecdotal.

### Working the coverage list down: the first batch

An unlowered command is **not a stall**. `Gen4ScriptVM.lower` emits
`g4_unimplemented` and the block carries on, so the 621 were inert rather than
blocking — which is also why they are easy to leave: nothing ever breaks
loudly. Taken in frequency order, which is the only honest priority:

| command | sites | what it really does |
|---|---|---|
| `waitabpress` | 95 | `ScriptContext_Pause(CheckABPress)` — the wait `waitbutton` already had |
| `getcurrentmapid` | 62 | writes the **header** id, not the engine's map key |
| `getrandom` | 56 | `LCRNG_Next() % bound`; the bound may itself be a var |
| `checkmoney` | 66 | writes a **boolean**, not the balance; amount is a literal word |
| `hidemoney` / `showmoney` | 66 / — | a HUD this port does not draw — an honest no-op |
| `getpartymonspecies` | 51 | **both** arguments are var ids; the slot is the value in the first |
| `checkpartyhasspecies` | 44 | skips eggs, like the cartridge does |
| `removemoney` | 41 | literal word |
| `healparty` | 39 | `Party_HealAllMembers` — the engine's existing verb, same meaning on all five cartridges |
| `getplayerstarterspecies` | 32 | from the system vars, not derived from the party — the party can lose the starter |
| `createjournalevent` / `givejournal` | 75 / — | Platinum's diary screen, which this port has none of |

Every one was read from its own `ScrCmd_*` rather than from its name, and the
names mislead in both directions — `getpartymonspecies` takes its slot *in a
var*, and `checkmoney` answers yes/no.

**A species key is not a species number.** The party stores `mon.species` as
the cache's own key (`"SPECIES_025"`), because that is what indexes
`data.pokemon`; every script command compares a number. `speciesNumber` is the
one place that conversion happens, so the four commands that need it cannot
drift apart.

Coverage after this batch: **94.56%**, 110 of 718 commands, 4,246 instructions
still unlowered — 648 fewer than before.

**No re-import is needed for any of this.** `Gen4ScriptVM.compile` lowers at
runtime from the raw instructions the cache stores, and caches the result per
entry point; the cache holds decoded opcodes, not lowered rows. A new lowering
takes effect on the next launch.

## Two coordinate spaces, and an object that was removed but still in the way

Three reports from one session outside the house, and they turned out to be two
bugs.

### The scripts speak the matrix's coordinates; the engine speaks the map's

Sinnoh is ONE grid. `PlayerAvatar_GetXPos` answers in matrix coordinates, every
event in the cartridge is stored in them, and every script compares against
them. Twinleaf's guitarist scene is the proof:

```
    GetPlayerMapPos VAR_0x8004, VAR_0x8005
    GoToIfEq VAR_0x8004, 108, TwinleafTown_GuitaristStopPlayerX108
    GoToIfEq VAR_0x8004, 109, ...
    ...
    GoTo TwinleafTown_GuitaristStopPlayerX115
```

108 to 115 are numbers **no 32-wide map could ever produce**. The import makes
events map-local by subtracting the region origin, which is right — the engine
walks one map at a time — but that leaves the two sides speaking different
numbers and **nothing was converting between them**. So all eight branches
failed and every approach fell through to the last one, applying the push-back
written for x=115 wherever the player actually stood. Reported as *"the player
that's supposed to stop me doesn't walk up to me and push me back I just keep
walking backwards 1 block like 5 times"*.

Twinleaf's origin is (96, 864). An interior's is (0, 0), which is exactly why
this was invisible indoors for as long as the player could not get out of the
house — and why adding the conversion cannot change any indoor behaviour.
`mapOrigin` / `toMatrix` / `toLocal` are now the one place it happens, used by
`getplayermappos` (local → matrix), `setobjecteventpos` and `setposition`
(matrix → local).

### A removed object was invisible and still standing there

`hidden` was read by the DRAW pass and by nothing else. So a script's
`RemoveObject` took a character off the screen and left their tile blocked for
the rest of the session — and left them answering when you pressed A at it.

The cartridge puts `LOCALID_RIVAL` at x 105, z 875, which is **the same tile as
the warp into his own house**, because he is meant to block that doorway during
his scene. `TwinleafTown_CoordEvent_RivalThud` ends with `RemoveObject
LOCALID_RIVAL`, and the log proves the scene ran to completion — it sets
`VAR_TWINLEAF_TOWN_RIVAL_TRIGGER_STATE` to 1, two rows after the removal, and
the coord event declines from then on. He went invisible; the doorway stayed
shut. *"he greets me at the door but it won't let me in his house after"*, and
the same wall is where `no text for Twinleaf Town/nil` came from — pressing A at
the door talked to somebody no longer in the game, who has no talk script
because his `script` field is 0.

Fixed in `Collision.occupied` and `OverworldState:npcAtCell`, one rule in both:

**Buried is the exception and it is not an edge case.** Route 113's trainers are
under the ash — invisible and genuinely in the way, rising when they spot you.
`buried` is kept precisely so "a script hid this" can be told from "this is
covered up", so it is the one hidden thing that still blocks and still answers.
The engine already took this view in one place (a seam proxy is built with
`passable = body.passable or body.hidden`), so this is that rule applied where
it was missing rather than a new one. Flag-hidden objects are never spawned at
all (`objectVisible` gates the spawn), so they were never invisible walls.

### On the buildings: the data is all there, so the next run has to say

Checked rather than assumed: `gen4_models.sets.buildings` carries **590 models**
with real shapes and textures, and the terrain has **387 of 666 chunks carrying
objects, 3,476 placements**. `bake` draws them into the same canvas and depth
buffer as the floor. At Twinleaf's camera (type 0, pitch 59.05°) the numbers
also work out: `canvasPx` is 637 with `leanPx` 198, so there is headroom for a
384-unit rise and nothing is being clipped.

Which leaves a measurement problem rather than a reading problem, because **a
flat floor drawn through a correct oblique matrix looks exactly like a correct
floor drawn through a flat one**. So `bake` now reports, once per map, how many
buildings it placed and how many it could not resolve. If a chunk with objects
reports 0 placed, the fault is the model lookup; if it reports its buildings and
they still look flat, the fault is the camera, and the camera line already says
which pitch it used.

`TileRenderer` also no longer swallows `Gen4Ground.forMap`'s error. That `pcall`
falls back to one flat colour per terrain class, so a Gen 4 map whose ground
raised looked like a Gen 4 map with no 3D rather than like a crash — the same
silent shape that hid `module 'src.core.Assets' not found` for a whole session.

## The invisible wall was one word

`OverworldState:checkEdgeExit` asks `self.map:connection(COMPASS[dir])`, and
`COMPASS = { up = "north", down = "south", left = "west", right = "east" }`.
The Gen 4 extractor keyed its region edges by the **walking** direction —
`up`, `down`, `left`, `right`. So every lookup answered nil, and **every Gen 4
map with a neighbour ended at an invisible wall**. Reported from play as
*"after talking to my rival I'm supposed to walk out of town but there's an
invisible wall"*.

Twinleaf has carried `connections.up = { map = "R201", offset = 0 }` the whole
time — a correct edge under a key nothing reads. 69 maps carry one, 140 edges
between them. Gen 3 has written north/south/west/east all along, which is why
nothing else in the engine ever noticed.

Fixed at both ends: the extractor writes compass names now, and
`Data:seedDefaults` renames the ones already in the cache — so **this lands
without a re-import**, and a cache that already speaks compass is left alone.

Worth recording for its own sake: the north corridor was walkable all along.
Decoding T01's collision properly (it is **two bytes per cell**, 2,048 bytes
for a 32×32 map — reading it as one byte per cell produces a convincing
`#0#0#0` stripe that looks like real data) shows x 12–19 clear from y 3 up to
y 0. The player could always reach the edge. There was simply nothing on the
other side of it.

## What the log settled

The diagnostics from the previous pass all reported, and between them they
answered three open questions at once:

```
[info] new game: applied 112 opening flag(s) and 3 var(s)
[info] gen4 save repair: restored 112 opening flag(s) and 3 var(s) this save never recorded
[info] gen4 model: depth buffer format depth24
[info] gen4 camera: default at 50.00 deg (chosen in OPTIONS) -- ground x0.766, height x0.643
[info] gen4 ground: chunk 0 baked 8 building(s), 0 unresolved (canvas 512x640, lean 247)
```

* **The save repair works.** 112 flags restored on a save that never had them,
  and the player is out of the house — the log's map trail runs T01R0202 →
  T01R0201 → T01 → T01R0101 → T01R0102, which is bedroom, hall, town, rival's
  house, rival's room. The collision fix opened that door.
* **The 3D pipeline is live and is not the problem.** Real depth buffer, ground
  compressed to 0.766, height at 0.643, and **8 to 12 buildings baked per chunk
  with none unresolved**. Whatever "no height" is, it is not a camera that
  failed to apply or models that failed to load.
* **`CAM TILT` is set to 50° in OPTIONS**, which overrides every map's own
  camera — that is what "chosen in OPTIONS" means on that line. Twinleaf's
  authored camera is `default` at 59.05°; interiors are 50.09°. Setting the row
  back to `cartridge` restores the per-map cameras. (50° shows *more* height
  than 59°, not less, so this is not the cause of the complaint — but it does
  mean nothing seen so far has been the cartridge's own framing.)

### Still open: a movement applied to nobody

`[warn] input has been gated for 10s on T01 with nothing on screen -- held by:
a script is running, 1 scripted move(s) queued`, immediately after the
guitarist's coord event fires. `Commands.g4_move` returned silently when
`objectById` found no entity, and the script then reaches `WaitMovement` — so a
cutscene missing half its cast holds the gate with nothing on screen. It now
names the id it could not find and lists the localIds that are live, which
turns the next run into a lookup.

Two things are already known about that scene and are worth having written
down. The guitarist's push-back is **correct behaviour**, not a loop: he blocks
the north exit while `VAR_TWINLEAF_TOWN_GUITARIST_TRIGGER_STATE` is 1, which
`InitNewGame` sets, and the **only** place in the cartridge that clears it is
`scripts_twinleaf_town_rival_house_2f.s`, which sets it to 2. You are meant to
be stopped until you have been up to Barry's room. And Twinleaf's object table
carries **two objects with localId 3** — the guitarist and the arrow signpost —
though the signpost sits at local y = -8, off its own map, so it is never
spawned and cannot currently win the lookup.

## The height was always there. Nothing could stand in front of you.

Reported four times, most recently as *"continue with investigating and fixing
the lack of height and depth of the world (3d)"*. So this time it was measured
end to end rather than reasoned about, and the answer was not where anyone was
looking.

**The models have height.** Decoding the vertex buffers directly — 14 bytes a
vertex, position as three `s16`s over `FX16` times the model's `posScale` —
**527 of the 590 building models have a real Y extent**. Twinleaf's own:

| model | height (units) |
|---|---|
| `t1_h01` (house) | 71.0 |
| `t1_s01` | 90.8 |
| `c1_b01a` | 102.2 |
| `pc` (Pokémon Center) | 62.8 |
| `gym00` | 79.0 |
| `tree01` | 77.5 |

**And the projection puts it on screen.** Running chunk 0's eight placements
through the same matrix the bake uses, at the camera the log reports (50°,
`sin` 0.766, `cos` 0.643, canvas 512×640, lean 247.8):

```
  t1_s01    y=16.0 h=90.8   base clipY  0.1222  top clipY -0.0601  -> RISE 58.4 px
  t1_h01    y=16.0 h=71.0   base clipY  0.1413  top clipY -0.0013  -> RISE 45.6 px
  t1_door1  y=16.6 h=29.0   base clipY  0.1703  top clipY  0.1120  -> RISE 18.6 px
```

A Twinleaf house rises **45 screen pixels** on a 192-pixel-tall screen — a
quarter of the view. The shader is `mvp * vertex_position` with a real `mat4`,
the depth buffer is real, and the log says every chunk bakes 8–12 buildings
with none unresolved. There was never anything wrong with the height.

**What was missing is that nothing in the world ever passed in front of the
player.** Every sprite drew over every building, so walking "behind" a house
put you on its roof. And a world that can never occlude you reads as flat no
matter how much geometry it has — which is why four rounds of looking at the
camera found nothing: the camera was right every time.

### The canopy pass

`Gen4Model`'s shader now carries the model-space height of each fragment as a
varying and drops the ones at or below a `yCut` uniform. That makes it possible
to draw a building **twice**: once whole, under the sprites, and once with
everything below head height cut away, over them. The roof and upper walls
paint after the sprite; the ground floor does not; somebody standing at the
front door is still drawn in front of it.

`Gen4Ground:bakeCanopy` is `bake` minus the ground floor — the terrain goes in
first **with the colour mask off** so the depth buffer still hides what a hill
should hide (the same trick `bakeAnimated` already used), then each building is
drawn with `yCut = (CANOPY_Y - object.y) / scaleY`. `CANOPY_Y` is 32 units: a
tile is 16 and an overworld sprite stands about two of them, so anything above
that is over everybody's head.

It is **approximate on purpose**. The exact cut depends on how far north of the
building the character is standing, which is a per-sprite comparison this does
not make. What it buys instead is occlusion at all, for one extra bake and one
extra blit, with no per-frame model draws — the thing the whole bake
architecture exists to avoid.

Routed through `TileRenderer:drawAbove`, which is already the pass that runs
after the entity loop and already carries Hoenn's treetops. Going through the
renderer rather than the overworld means the canopy is handed **exactly** the
camera the ground was drawn with: `renderer:draw(cam.x, bgY, …)` and
`renderer:drawAbove(cam.x, bgY, …)` are the same two numbers, and the two
pictures have to line up to the pixel.

Canopies are budgeted, evicted and released alongside the bakes they belong to
— a third canvas per chunk, and just as much of a leak if forgotten.

### The fallback that matters

A `varying` is the one part of that shader a driver can reasonably refuse:
GLES wants a precision qualifier and some older GL profiles dislike a
declaration outside the stage blocks. `ensureShader` now falls back to the
original cut-free shader and says so, because `draw` bails on a nil shader —
**losing walk-behind is a much smaller loss than every model in the game going
black**. `Gen4Model.cutsHeight()` reports which one was compiled, and
`bakeCanopy` refuses to run without the cut: a canopy that cannot cut would
paint whole buildings over the sprites and make characters vanish into
doorways, which is worse than no canopy at all.

## Four more, each traced to the cartridge

### The invisible wall, properly this time

Renaming the connection keys was necessary and not sufficient — the log shows
`renamed 139 region edge(s) on 69 map(s)` and the seam was still shut. The
crossing calls `Map.defPassable` on the neighbour's cell, which calls
`Map.defCellTile`, which opens with:

```lua
if not (def and tilesetDef and tilesetDef.blocks) then return nil end
```

`blocks` is the **Game Boy metatile table**, and it is read by the LAST of the
three branches in that function. Demanding it up front refused the other two
for any tileset that does not carry one — which is every Gen 4 tileset, because
Sinnoh's collision is per CELL: the stand-in carries a `collision` table and
`blockCells = 1` instead, and the `collision` branch returns long before the
`blocks` code. So `defCellTile` answered nil, `defPassable` read nil as a wall,
and every seam in Sinnoh was shut. It is the same shape as the
Littleroot/Route 101 bug the comment directly above `defPassable` describes,
one layer further down.

Verified offline against the cache before committing — stepping north off T01,
R201's bottom row:

```
  T01 x=13 -> R201 (13,31)  tile=255  walkable=false
  T01 x=14 -> R201 (14,31)  tile=0    walkable=true
  T01 x=15 -> R201 (15,31)  tile=0    walkable=true
  T01 x=16 -> R201 (16,31)  tile=0    walkable=true
  T01 x=17 -> R201 (17,31)  tile=0    walkable=true
  T01 x=18 -> R201 (18,31)  tile=255  walkable=false
```

A four-tile exit corridor, which is what a town exit looks like. Before the fix
every one of those was nil.

### The black house shadows are a polygon alpha nobody read

Measured, not guessed. `funsui` carries three materials, and the `polyAttr`
u32 at material record `+0x0C` has a 0..31 alpha in bits 16..20:

```
  c1_fun1   polyAttr=001F8081   alpha 31/31
  c1_fun2   polyAttr=001F8088   alpha 31/31
  h_kage    polyAttr=00090081   alpha  9/31
```

**9 of 31 — 29%.** Nothing read `polyAttr`, so every building's ground shadow
drew at full strength. And its texture makes that fatal rather than merely
wrong: `h_kage.png` is a 16×16 of palette index 0, and on this material index 0
is not transparent, it is **black**. So the port drew a solid black quad where
the cartridge draws a 29% shadow. Reported exactly as *"there are shadows for
the houses but they're showing as black not how they look in the actual rom"*.

`Gen4Nsbmd` now reads the attribute, `Gen4ModelPack` stores the alpha on the
shape when it is not 31, and `Gen4Model` sets the draw colour per shape —
per shape because a model mixes opaque walls with a translucent shadow and one
colour for the whole model would make one of them wrong.

**It works before a re-import.** `h_kage` is the cartridge's one shadow texture
and it is 9/31 on every material that wears it, so a cache written before
`alpha` existed is drawn correctly by name. That fallback is a measurement, not
a default; a cache that carries the real value never consults it.

### The player was not centred, and the camera was right for a flat world

`Camera:follow` centres on `py - (viewH/2 - 8)`. But a Gen 4 walker is drawn at
`(py - cam.y) * sin(pitch)` — `riseOf` folds the ground's foreshortening into
the sprite — so the player landed at `(viewH/2 - 8) * sin` down the screen
instead of `viewH/2 - 8`. At Twinleaf's 59.05° that is **75 pixels instead of
88**, and the shallower the pitch the worse it gets.

Dividing by the same scale is the whole correction and it cancels exactly:
`((viewH/2 - 8) / sin) * sin`. `groundScale` is nil on every other generation
and defaults to 1, so Gen 1, Gen 2, Gen 3 and their hacks keep their framing to
the pixel.

### The stuck move now names itself

`g4_move`'s "no object with localId" warning **never fired**, which rules out
the lookup: the guitarist's movement is queued against a real entity and simply
does not finish. "1 scripted move(s) queued" is the same line whether the
walker never started, never finished, or is waiting on a pause that cannot tick
— three different bugs wearing one message. The watchdog now prints each
queued move's entity, direction, `remaining`, `pause`, `moving` and its cell
and target.

Also worth having written down, because it looks like a bug and is not: the
guitarist's push-back is **correct**. He blocks the north exit while
`VAR_TWINLEAF_TOWN_GUITARIST_TRIGGER_STATE` is 1, and the only place in the
cartridge that clears it is `scripts_twinleaf_town_rival_house_2f.s`, which
sets it to 2. Being turned back until you have been up to Barry's room is the
cartridge's own design; being turned back by an invisible guitarist is not.

## The watchdog named the guitarist, and it was not the guitarist

```
1 scripted move(s) queued: [1] T01_obj_8 dir=up remaining=0 pause=nil
moving=true cell=16,-16 target=16,-17
```

`T01_obj_8` is the **arrow signpost**, and it was walking north out of the
world for ever. Twinleaf carries the guitarist at object index 4 and the
signpost at index 8, and **both have localId 3** — that is what the cartridge
stores, read straight off an `ObjectEvent` struct whose layout matches pret's
field for field. Hardware resolves the clash by searching its object array in
order and taking the first match, so the guitarist wins and the signpost is
never addressed by anything; its script id is 0xFFFF, it has none.

`objectById` walked `overworld.entities`, which is **not** in map-object order —
it is the live cast, pooled and rebuilt, with the player in it — so the
signpost won. `ApplyMovement LOCALID_GUITARIST` then walked a signpost that
sits at local y = -8, off its own map. It never arrived, `WaitMovement` never
returned, and the input gate stayed shut with nothing on screen. Now ordered by
the def's own index, which is the cartridge's rule rather than a tie-break
invented here.

## Why the shadow alpha changed nothing

It was read off the cartridge correctly, stored correctly, applied correctly —
and thrown away one function before it was used. `Gen4Ground:building`
**rebuilds** the shape list rather than passing it through, and the rebuilt
table carried `name`, `index`, `vertices`, `indices`, the counts and `image`.
Not `material`. Not `texture`. Not `alpha`. So the renderer, which decides a
shape's translucency from exactly those three, had nothing to decide with and
drew every one opaque. A good reminder that "the value is correct" and "the
value arrives" are two separate claims.

## The canopy was missing the geometry people actually walk behind

It only drew `record.objects` — the props. But a Gen 4 chunk mesh is not just a
floor: **interior walls, cliff faces and the trees that are part of the land**
all live in the terrain model. So the canopy left out exactly the things a
player most obviously passes behind. Reported as *"indoor tiles don't have my
character walk behind them and mask the character neither do trees, it shows me
as walking on top of their tiles"*.

The terrain is now drawn a second time with the same height cut the buildings
get, over the depth the masked pass just laid down. And `bakeCanopy` no longer
refuses a chunk with no props — that guard skipped every interior, which is the
case with no props and all of the masking geometry.

## Lake Verity: two findings, one of them not a bug

**The Galactic grunts are supposed to be there.** `VarsFlags_Init` memsets every
flag to zero, `FieldSystem_InitNewGameState` runs exactly one script, and
`FLAG_HIDE_LAKE_VERITY_TEAM_GALACTIC` (0x1C0) is set by **no script in the
cartridge** — so it is clear at a new game and the grunts spawn.
`LakeVerity_OnTransition` confirms the intent: its default branch is
`CallIfUnset FLAG_TEAM_GALACTIC_LEFT_LAKE_VERITY,
LakeVerity_SetPositionsDuringTeamGalactic`. Platinum puts Team Galactic at the
lake from the start. That report was the port being right.

**Dawn is missing because her sprite is a variable.** `LOCALID_COUNTERPART`
carries `OBJ_EVENT_GFX_VAR_0`, and `MapObject_GetFieldSystemGraphicsID` resolves
the range `OBJ_EVENT_GFX_VAR_0 .. OBJ_EVENT_GFX_VAR_F` through a var:

```c
if (graphicsID >= OBJ_EVENT_GFX_VAR_0 && graphicsID <= OBJ_EVENT_GFX_VAR_F) {
    graphicsID -= OBJ_EVENT_GFX_VAR_0;
    graphicsID = FieldSystem_GetGraphicsID(fieldSystem, graphicsID);
}
```

and `LakeVerity_OnTransition` sets it from the player's gender —
`SetVar VAR_OBJ_GFX_ID_0, OBJ_EVENT_GFX_PLAYER_F` for a male player, `_M` for a
female one. The port stores the sentinel as a literal graphics id and never
resolves it, so the counterpart has no sprite.

**The constants, derived and cross-checked.** Walking `generated/vars_flags.txt`
as an enum (a bare name consumes the next id, `A = B` aliases B) reproduces the
flag ids exactly — `FLAG_HIDE_TWINLEAF_TOWN_PLAYER_HOUSE_1F_RIVAL_MOM` = 497 and
`FLAG_HIDE_LAKE_VERITY_TEAM_GALACTIC` = 448, both matching the cache. The vars
come out **0x3000 low** against two known values (`VAR_PLAYER_HOUSE_STATE`
0x10A4 computed against 0x40A4 observed, `VAR_TWINLEAF_TOWN_GUITARIST_TRIGGER_STATE`
0x1070 against 0x4070), so a script var id is the table id plus 0x3000. That
gives:

* `OBJ_EVENT_GFX_VAR_0` = **101**, through `OBJ_EVENT_GFX_VAR_F` = 116
* `VAR_OBJ_GFX_ID_0` = 0x1020 + 0x3000 = **0x4020 (16416)**
* so the var for a sentinel is `0x4020 + (graphicsId - 101)`

The cache's counterpart record carries `gfx = 101`, which confirms the sentinel
end to end. Implementing it needs one more piece: the def also carries a
resolved `sprite` key (`graphicsId 140 -> SPRITE_G4_119`), so the resolution has
to remap that too rather than the id alone.

## What is still incomplete, as of this pass

**Known broken, cause understood, not yet written**

* **Variable object graphics** (above). Blocks Dawn/Lucas anywhere a
  counterpart appears — Lake Verity, Sandgem, Jubilife, Canalave.
* **Barry does not follow you out of Twinleaf.** A follower is a live object the
  cartridge drives with its own movement; the port has a Gen 2 follower
  (`PikachuFollower`) and nothing equivalent wired for Gen 4.
* **`setwarpeventpos` (38 sites) and `setbgeventpos` (7)** are unlowered, and
  when written must take the matrix-to-local conversion the other coordinate
  commands now use.

**Known broken, cause not yet established**

* Whether the canopy actually masks correctly at the cut height — the value
  (`CANOPY_Y = 32`, two tiles) is reasoned from sprite height, not measured
  against a scene.

**Measured coverage gaps**

* **Script commands: 94.56% of instructions lower** (73,847 of 78,093), 110 of
  718 distinct commands. The largest unlowered: `getpartymonribbon` 178,
  `callbattletowerfunction` 146, `getpartymonfriendship` 143,
  `createjournalevent` 75, `getitempocket`/`checkpockethasitems` 72 each.
* **Door animations**: `loaddooranimation` 52, `playdooropenanimation` 28,
  `playdoorcloseanimation` — why doors do not animate.
* **Trainer battles**: 221 `pending()` sites behind the Gen 4 battle handoff.
* **Shops**: 19 `pokemartcommon` sites; the item tiers are extracted, the screen
  is not wired.

**Older items, unchanged**

Trainer card main page; the remaining Poketch apps; summary pages; BDHC
elevation into the movement grid; the opening cutscene; the title save-erase
combination; the Gen 4 battle engine; music (SSEQ); Pokedex list-page art;
naming-screen button art; true perspective (the committed camera is the
cartridge's orthographic form, exact on the 300 orthographic headers and off by
14-18% at screen edges on the perspective ones).

## Variable object graphics, written

Sixteen of the cartridge's graphics ids are not pictures: they name a VAR that
holds the real id, and a map's entry script fills it in.
`MapObject_GetFieldSystemGraphicsID` is the whole rule, and Lake Verity's
counterpart is the one that matters first — the character beside Rowan is
whichever of Dawn and Lucas the player is not, chosen by
`LakeVerity_OnTransition` from the player's gender.

**The constants, derived and then closed against a third source.** Walking
`generated/vars_flags.txt` as an enum — a bare name takes the next id, `A = B`
aliases B — reproduces the flag ids exactly, so the walk is right. The vars then
come out a uniform `0x3000` low against two known values, giving
`VAR_OBJ_GFX_ID_0 = 0x4020`. And `Gen4ObjectGfx.name(101)` answers `"var_0"`
with `name(116)` answering `"var_f"`, which closes the range independently of
the var arithmetic. The same table answers `name(148) = "barry"` and
`name(140) = "mom"`, both matching the object records in the cache.

**A resolved id is not a sprite**, and that is the part that would have made a
half-fix look like a whole one. The def carries both and they do not coincide:
a graphics id is a key into the cartridge's own lookup table, while the sprite
is named after the archive MEMBER it lands on — `140 -> mom -> SPRITE_G4_119`.
Both hops are needed, and both are the extractor's own, so the resolver reuses
`Gen4ObjectGfx.name` and `gen4_overworld.sprites[name].member` rather than
inventing a second mapping that could drift.

Two details that would otherwise have bitten later:

* **The pool had to learn to give up.** `pooledNPC` is keyed by map and object
  index, which is right for everything whose art is fixed. An object drawn from
  a graphics var is not — the same index is legitimately Dawn on one visit and
  Lucas on another — so a pooled NPC whose sprite no longer matches is now
  rebuilt rather than handed back with the placeholder.
* **An unfilled slot is left alone and says so.** If the var is still empty the
  object keeps what it had and logs once, naming the id, the var and what the
  slot holds. That is an ORDERING fault — the map's entry script not having run
  before the spawn — and it looks identical to a missing sprite from outside.
  Guessing a stand-in would put the wrong character next to Rowan, which is
  worse than an empty space and much harder to notice.

## The graphics var was resolved one beat too early

The resolver hung off `objectHome`, which runs at SPAWN — and a Gen 4 map's
entry script does not. It is **queued**: `setMap -> onEnter` can happen
mid-warp while the warp command's own runner is still suspended-alive, and
starting a second runner there trips `ScriptRunner:run`'s assert, so the
overworld drains the queue once the world is idle. The cast is therefore built
*before* `LakeVerity_OnTransition` writes `VAR_OBJ_GFX_ID_0`, and the var was
empty every time it was read. The fix as committed would have logged its own
failure and changed nothing on screen.

So the write pushes back. `g4_set_var` and `g4_copy_var` now re-sync any object
on the map whose graphics id is the matching sentinel, which is the same shape
as `syncFlagObjects` — already there, already re-syncing an object when its
hide flag is written, for exactly the same reason: a script changing state that
the spawn has already consumed. With `pooledNPC` rebuilding an NPC whose
resolved sprite no longer matches, a re-sync is enough to replace the
placeholder with the real character.

Worth keeping in mind as a general shape: **anything resolved at spawn from
save state is racing the map's entry script**, and in this engine the entry
script loses. Flags already had the push-back; graphics vars now do too.

## `setwarpeventpos` and `setbgeventpos`

`(index, x, z)`, every argument through `ScriptContext_GetVar` so any of them
may be a var, and the index is the event's zero-based position in the map's own
list. Both move an event rather than a character — a warp or a sign — and both
speak the matrix's coordinates, so both go through `toLocal` like everything
else. 45 sites between them; coverage is now **94.62%**.

One divergence stated rather than hidden: on hardware `MapHeaderData` is
rebuilt on every map load, so a moved warp lasts until you leave. Here
`data.maps` is loaded once and shared, so the move persists for the session.
Nothing in the corpus moves a warp and then relies on it moving back — but that
is an observation about 38 sites, not a guarantee.

## The guitarist, finally: he was walking off the map

The queue watchdog named him this time — `T01_obj_4`, the guitarist himself, so
the index-order lookup fixed the wrong-target half. What it also said is where
he was:

```
[1] T01_obj_4 dir=up remaining=0 pause=nil moving=true cell=15,-3 target=15,-4
```

**Cell y = -3, on a 32-tile map, still heading north.** Repeated triggers had
walked him three tiles north at a time off the top of the world, and off the
map is where an entity stops being updated: its step never completes, `moving`
stays true for ever, and the `scriptMoves` queue it sits in never drains. That
is the held input gate with nothing on screen.

The crossing in `updateScriptMoves` is deliberately the player's alone — the
comment there says so, and the cartridge rebuilds its object array per map load
for the same reason — but nothing then stopped a non-player walker being
stepped off the edge anyway. It is refused now, and the move is retired rather
than stranded, so the scene finishes and the guitarist runs his own walk-back.

**A caution, recorded because it cost real time here.** The movement data
looked missing: a probe reported 3,025 `applymovement` sites and zero carrying
a decoded list, which pointed straight at a re-import. It was wrong. The file
being probed was a copy staged hours earlier — 11.0 MB against the live cache's
11.76 MB, and the difference was precisely the movement data. **Re-stage before
concluding anything about a cache.** Against the live file it is 3,025 of
3,025, and decoding member 1052 straight off the ROM gives 211 of 211.

And the decoded steps are right. Twinleaf's `GuitaristStopPlayerX112` is
`WalkFastNorth 3, WalkFastEast 4, WalkOnSpotFastSouth, WalkNormalSouth`, and
the cache holds `walk:up/1t x3 | walk:right/1t x4 | spot:down x1 |
walk:down/1t x1`. The data was never the problem.

## Every scripted walk in Sinnoh ran at one speed

A Gen 4 movement action names a **speed** as well as a direction, and the table
dropped it — the comment said so outright: *"the port has one walk speed, so
the speed is dropped"*. The engine has carried `mv.rate` since the Gen 3 work,
where dropping it was what made Birch stroll through a rescue written entirely
in `walk_fast`; `scriptMove` has accepted a rate all along. Nothing needed
building. The value simply was not being read.

Every id checked name by name against `generated/movement_actions.txt`
(0-based, north/south/west/east in each group): 4 `WALK_SLOWER`, 8 `WALK_SLOW`,
12 `WALK_NORMAL`, 16 `WALK_FAST`, 20 `WALK_FASTER`, 24–43 the same five on the
spot, 76 `WALK_SLIGHTLY_FAST`, 80 `WALK_SLIGHTLY_FASTER`, 84 `WALK_FASTEST`,
88 `RUN`, 96 `WALK_EVER_SO_SLIGHTLY_FAST`.

`rate` is the walker's step duration scaled, so **bigger is slower**. The DS
ladder is pixels per frame across a 16-pixel tile — normal 1, fast 2, faster 4,
fastest 8, slow 1/2, slower 1/4 — which inverts to the multipliers used, and
matches the halving Gen 3 already uses. The two "slightly" classes are
**interpolated, not measured**: they sit between normal and fast in the
cartridge's ordering and no frame table has been read to pin them. Said plainly
in the source rather than left looking like the rest.

Measured over the whole corpus afterwards, by walk step:

| rate | steps |
|---|---|
| 1.0 (normal) | 7,482 |
| 0.5 (fast) | 2,332 |
| 0.25 (faster / run) | 873 |
| 2.0 (slow) | 149 |
| 0.75 (slightly fast) | 12 |
| none (the four jump actions) | 12 |

**3,366 of 10,860 walk steps — 31% — were playing at the wrong pace.** The
on-spot beats take the same speeds, so a fast mark-time is now a short beat
rather than a full one.

## The partner: 242 is not a local id

The log from the last play session named it exactly:

```
gen4 move: no object with localId 242 on L01 -- the movement is dropped and
whatever waits on it will wait forever (live localIds: 0)
```

Verity Lakefront's event file carries **one object**: a Trainer Tips signpost
at local id 0. There is no object 242 on that map and there never was, because
242 is not a local id at all. `constants/scrcmd.h`:

```c
#define LOCALID_CAMERA   0xF1
#define LOCALID_FOLLOWER 0xF2
#define LOCALID_PLAYER   0xFF
```

`GetLocalMapObjByIndex` branches on all three **before** it searches the object
array, so none of them is ever compared against a real `localID`. Only
`LOCALID_PLAYER` was known here, and only inside `g4_move`; every other command
that takes an object id — turn, place, show, hide — searched for an object
numbered 242 and found nobody.

That is the whole of the reported *"when we get to lake verity dawn and
professor are supposed to be there but they aren't"*. The coord event at
(48,44) is

```
VerityLakefront_CoordEvent_WereAtTheLake:
    LockAll
    ApplyMovement LOCALID_FOLLOWER, VerityLakefront_Movement_RivalWalkOnSpotNorth
    ApplyMovement LOCALID_PLAYER,   VerityLakefront_Movement_PlayerFaceRival
    WaitMovement
```

— the movement to the follower is dropped, the `WaitMovement` behind it never
returns, and the input gate stays shut.

### What the follower actually is, in three separable pieces

The scripts set them separately and clear them separately, so the port has to
keep them separate too.

| piece | command | cartridge | what it does |
|---|---|---|---|
| trailing | `setmovementtype <id>, 48` | `MapObject_SwitchMovementType` | the **live** actor starts following the player |
| crossing maps | `setobjectflagispersistent <id>, 1` | `MAP_OBJ_STATUS_PERSISTENT` | `sub_0206184C` deletes every object whose header id is not the new map's **unless this bit is on** |
| the save's memory | `sethaspartner` | `FLAG_HAS_PARTNER` (0x961) | what other systems read, and what `clearhaspartner` alone ends |

`MOVEMENT_TYPE_FOLLOW_PLAYER` is **48**, from the zero-based enum walk over
`generated/movement_types.txt` (`MOVEMENT_TYPE_NONE` is 0, so line N is N − 1);
`MOVEMENT_TYPE_FOLLOW_PARTNER_TRAINER` is 50. `FLAG_HAS_PARTNER` is **0x961**,
from the same enum walk over `generated/vars_flags.txt` that every other Gen 4
flag id in this port comes from — spelled `FLAG_G4_0961`, the way
`Gen4ScriptVM.flagName` spells one, so `checkflag` and this agree.

### Two commands one letter apart, and the port had the wrong one

```
setobjecteventmovementtype   90 sites   MapHeaderData_SetObjectEventMovementType
                                        -> rewrites the map's stored TEMPLATE
setmovementtype              30 sites   MapObject_SwitchMovementType
                                        -> rewrites the LIVE actor, now
```

They are adjacent in the command table. Only the template one was lowered, so
all thirty live rows went through the unknown-command path — and **eight of
those thirty are `MOVEMENT_TYPE_FOLLOW_PLAYER`**. Those eight are the entire
partner system: Barry out of Twinleaf, Cheryl through Eterna Forest, Riley on
Iron Island, Marley through Victory Road, Mira in Wayward Cave, Buck up Stark
Mountain, and Amity Square's pet.

The release matters as much as the adoption. `clearhaspartner` appears at 22
sites and at some of them it is the **only** thing that ends the escort — Lake
Verity Low Water clears it and never touches the movement type, because Barry
is a real object event on that map and the scene addresses him by his local id
from there on. A release keyed only on the movement type would have left him
trailing through the Cyrus scene.

### `src/world/Gen4Follower.lua`

The trail is `PikachuFollower`'s, which is already proven here: the follower is
sent to the cell the player is **vacating** the frame the player commits a
step, not the frame it lands, so it rests exactly one cell behind instead of
two. Everything Yellow-specific is dropped — ledge hops, idle rolls, happiness,
emotion bubbles.

Three rules that are this port's rather than the cartridge's, each for a
reason:

- **The map's own object wins.** Lake Verity Low Water carries Barry as a real
  object event and its entry scene addresses him by his local id there; so does
  Route 201 when you walk back onto it. On arrival the follower record looks
  for a live, unhidden object with its local id and *adopts* it rather than
  standing a second copy beside it.
- **Not persistent means it does not cross.** Amity Square's pet is a partner
  for one map, and the cartridge deletes it at the door.
- **Passable.** The cartridge's partner is a solid map object that shuffles out
  of the way when you walk into it; the shuffle is a behaviour this engine has
  no seam for, and without it a solid follower in a corridor is a softlock.
  Walk into it and it simply trails to the cell you vacated, as Yellow's
  Pikachu does.

Committed: `src/world/Gen4Follower.lua` (new), plus the seams —
`Gen4Movement.CAMERA`/`.FOLLOWER`, `objectById` learning all three special ids,
`g4_switch_movement` / `g4_set_object_persistent` / `g4_set_partner` /
`g4_check_partner`, five new VM lowerings, and the two
`OverworldController` hooks beside `PikachuFollower`'s.

Seventy-eight script rows that used to be skipped now lower —
`setmovementtype` 30, `clearhaspartner` 22, `sethaspartner` 16,
`setobjectflagispersistent` 8, `checkhaspartner` 2 — which is a small number
with the opening of the game behind it.

### `LOCALID_CAMERA` is named, not built

One script site (`ApplyFreeCameraMovement`'s neighbour in Lake Verity Low
Water). The scripted free camera pans the view rather than walking a body, and
this engine has no such object, so 0xF1 now logs once and drops the row instead
of searching for an object numbered 241. A dropped camera pan looks exactly
like a dropped character from the outside; saying which it is turns the next
report into a lookup.

## The name that was buffered and still printed as a gap

Two lines in the same log:

```
[warn] gen4 text: string slot 1 was never buffered; the line prints with a gap
[warn] gen4 text: string slot 0 was never buffered; the line prints with a gap
```

The buffer **was** called. Reading the save settled it in one step:

```lua
player = { name = "CED", rival = "", ... }
```

`g4_buffer` files `text or ""`, and `gen4Markup` treats `""` as a miss — so an
empty buffer and an unfilled one are indistinguishable downstream, and every
`{STRVAR_1 3 0 0}` in Twinleaf printed as a gap mid-sentence. The save was
written before Rowan's intro asked for a rival name, and this port will keep
meeting files like it for as long as anybody continues an old one.

The fallback is the **cartridge's own default**, not one invented here.
`gen4_intro.rivalNames` is the preset list the naming screen offers, ripped
from the ROM; its first entry is the "New name!" prompt rather than a name, so
the first non-custom label is the game's own default:

```
New name! / Barry / Nolan / Roy / Gavin / Clint / Ralph / Lewis / Tommy
```

The player's own name falls back the same way through
`field.boot.namePresets`. Read-side only — nothing is written back to the save,
because a file that never recorded a rival name should keep saying so, and
repairing it here would overwrite a choice the player might yet make in a fresh
intro. Said once per name per session in the log, so the fact stays visible
without filling it.

`NamingScreen:confirm` already refuses an empty entry and falls back to
`presets[1]`, so this only ever fires for a save that skipped the step
entirely.

## Measuring the opening instead of the corpus

Corpus-wide script coverage is a useful number and a poor priority list: it
weights the Battle Tower and the Underground exactly as heavily as the first
five minutes. So the reachable set was walked instead — every script block
reachable from Twinleaf Town, the three houses, Route 201, Verity Lakefront,
the two Verity Cavern rooms, Sandgem and Route 202, following every `goto`,
`call` and conditional branch, and asked `Gen4ScriptVM.lowered` about each row.

**301 blocks. 29 unlowered rows, 22 distinct opcodes.** That is a list short
enough to finish, and finishing it is worth more than a percentage point
anywhere else.

| what | rows | why it matters |
|---|---|---|
| `startchoosestarterscene` / `savechosenstarter` / `givepokemon` | 3 | **the starter** |
| `bufferrivalstarterspeciesname` | 1 | Barry's Pokémon, named in his dialogue |
| `addfreecamera` / `restorecamera` / `addcameraoverrideobject` / `removecameraoverrideobject` | 4 | every scripted camera pan |
| `giverunningshoes`, `gettimeofday`, `countbadgesacquired`, `checkpoketchappregistered`, `getsetnationaldexenabled` | 12 | each writes a var |
| `playmusic` / `playdefaultmusic` | 2 | verbs this engine already has |
| door animations (`loaddooranimation` and friends) | 4 | cosmetic |
| `setmenuxoriginside`, `checktvintervieweligible` | 2 | cosmetic, and a question |

The var-writing ones are worse than they look. An unlowered command does not
merely fail: the comparison register keeps whatever the **last** command left
in it, so the `gotoif` behind an unlowered `countbadgesacquired` branches on
something unrelated. A script that is 99% correct and branches at random is
not 99% of a scene.

## The briefcase was built and nothing ever opened it

`src/ui/Gen4StarterSelect` draws Rowan's case from the cartridge's own
`psel_all` model and its 41-frame animation, reads the three species out of
`gen4_menus.starter`, and had been finished for some time. A search of the
whole tree for its name found the file and **no callers**.

The seam is five rows of Route 201's script:

```
startchoosestarterscene          <- opens the app and PAUSES the script
savechosenstarter                <- writes VAR_PLAYER_STARTER
returntofield
getplayerstarterspecies 0x8000
givepokemon 0x8000, 5, 0, 0x800C
```

The first, third and fifth were unlowered. Without them the case never opens,
the var stays zero, and no Pokémon is handed over.

`VAR_PLAYER_STARTER` is **0x4030**, from the same enum walk over
`generated/vars_flags.txt` that puts `VAR_OBJ_GFX_ID_0` at 0x4020 — which the
overworld already relies on, so the walk is not being trusted for the first
time here. The three species are 387 / 390 / 393, read off
`gen4_menus.starter.rows[i].species` rather than typed in.

**The rival's and the counterpart's starters are derived, not stored.**
`SystemVars_GetRivalStarter` and `SystemVars_GetPlayerCounterpartStarter` are
two `if` ladders over the one var and no state at all:

| you choose | Barry takes (beats yours) | Dawn/Lucas takes (yours beats) |
|---|---|---|
| Turtwig | Chimchar | Piplup |
| Chimchar | Piplup | Turtwig |
| Piplup | Turtwig | Chimchar |

Measured end to end offline: choosing Chimchar writes 390 to 0x4030, hands over
a level-5 Chimchar with the success var set to 1, and buffers PIPLUP for Barry
and TURTWIG for the counterpart.

`givepokemon` passes `skipNickname` deliberately —
`Pokemon_GiveMonFromScript` adds the mon and returns; Gen 4 asks about a
nickname from a separate script path, and the starter is not one of the times
it asks.

## A camera pan is an invisible object being walked

`ScrCmd_AddFreeCamera(x, z)` stands a map object at those ground coordinates
with `OBJ_EVENT_GFX_INVISIBLE`, hides it, and points `Camera_TrackTarget` at
its position. `ScrCmd_RestoreCamera` deletes it and tracks the player again.
And `ApplyFreeCameraMovement` turns out not to be an opcode at all — the
assembler macro expands to:

```
ApplyMovement LOCALID_CAMERA, \movementOffset
```

So the whole feature is an entity the script can already walk, plus one
decision about who the camera follows. `OverworldState:cameraTarget()` returns
`self.gen4Camera or self.player`, the two `camera:follow` calls read it, and
`setMap` clears it — the cartridge is no kinder, since a free camera's object
is deleted with the rest on a map change.

13 `addfreecamera` sites and 14 `restorecamera`. The first one the player meets
is Lake Verity Low Water's arrival: the view leaves the player, finds Cyrus at
the water, and comes back.

## Where the opening stands

**Zero unlowered opcodes across all 301 reachable blocks.** Corpus coverage
rose from 94.62% to **95.26%** (3,698 unlowered rows of 78,093), and the
remaining bulk is where it should be — `getpartymonribbon` 178,
`callbattletowerfunction` 146, `getpartymonfriendship` 143.

Four of the six rows that finished the sweep are honest stand-ins rather than
features, and are marked as such in the source:

- **Door animations** (`loaddooranimation`, `playdooropenanimation`,
  `playdoorcloseanimation`, `unloadanimation`, `waitforanimation`) are a
  one-shot NSBCA animation on the door's own NSBMD map prop with a sound
  effect. This port reads NSBMD but not NSBCA, bakes the ground's props into a
  flat canvas, and has no Gen 4 SE bank — three separate stages, none close.
  Named so the log says which feature is absent instead of printing an opcode
  nobody can look up. The wait is a no-op too: with nothing animating there is
  nothing to wait for, and holding the script would be a frozen pause rather
  than a door opening.
- **`checktvintervieweligible`** gets a new kind of handler, `g4_no_feature`,
  distinct from both `g4_noop` (a row that does nothing on screen) and
  `pending()` (a verb whose feature is on the way). It writes **zero** to the
  destination var, because a command that writes a var has to write one — and
  zero is both the truthful answer and the one that keeps the branch on its
  ordinary path.

## Building any Sinnoh Pokémon took the game down

This was found by measuring rather than by playing, and it sat directly under
the starter handed over in the previous pass. Against the live cache:

```
Pokemon.new(data, 387, 5)
  -> Stats.lua:68: attempt to perform arithmetic on a nil value (local 'base')
Pokemon.movesAtLevel(def, 5)
  -> attempt to index a nil value
```

Not a wrong stat — a raise. Every starter, every wild encounter and every
trainer party would have crashed at the moment of creation.

A Gen 4 species record is the right data under the wrong names, four times
over:

| the cache writes | the engine reads | consequence |
|---|---|---|
| `baseStats.spAttack` / `spDefense` | `spatk` / `spdef`, and `special` on the Gen 1 path | `base[key]` is nil, arithmetic raises |
| `evYields` | `evYield` (singular) | `Stats.isGen3` says no |
| `learnset` alone | `level1Moves` | `ipairs(nil)` raises |
| `expRate`, a number | `growthRate`, a curve name | no curve at all |

The `evYield` one is the quiet one. It is read by exactly one thing —
`Stats.isGen3`, as a **presence test** that decides which stat model a record
implies. Failing it put Sinnoh on the Gen 1 model: four DVs of 0–15 fed to the
Gen 1 formula, no natures, no abilities, no EVs. For a Gen 4 cartridge the
Gen 3 model is closer in every respect, and it is the one the record actually
describes.

Fixed in `Data:seedDefaults`'s Gen 4 branch, beside the connection rename and
for the same reason: it lands without a re-import, and a record that already
carries the engine's spelling is left alone. 508 records adapted at load.

`expRate` maps through `generated/exp_rates.txt` (zero-based): 0 MEDIUM_FAST,
1 ERRATIC, 2 FLUCTUATING, 3 MEDIUM_SLOW, 4 FAST, 5 SLOW. Turtwig is 3, and
Turtwig is Medium Slow. **ERRATIC and FLUCTUATING are named rather than
mapped to a curve that happens to exist** — neither is closed-form, so
`Growth.expForLevel` warns once and falls back to MEDIUM_FAST. The exact
answer is a NARC (`poketool/personal/pl_growtbl`, one 101-entry member per
rate) and belongs in the extractor; naming the curve means the warning says
which one is missing instead of the game quietly levelling on the wrong one.

### The nature was going into the EVs slot

`Stats.calc(speciesDef, level, dvs, statExp, evs, nature)` takes six. The three
calls in `Pokemon.lua` passed five, so `nature` landed in `evs`, `evs` landed in
`statExp`, and the Gen 3 branch's `evs or statExp` then picked the nature over
the real EVs. The two callers outside that file — `Gen3Commands` and
`Gen3SpecialsFRLG` — have always passed all six; `Pokemon.lua` was the outlier.

It went unnoticed because a Gen 3 nature is a **string** and Lua lets you index
a string: `evs[key]` answered nil, EVs read as zero, and a freshly built
Pokémon has zero EVs anyway. A Gen 4 nature is a **number**, and indexing a
number raises. That is the `Stats.lua:105` half of the crash.

> **Corrected below.** The paragraph that stood here said natures had never
> affected a stat in this engine and that the change was inert on every
> cartridge. Both halves were wrong, and the regression that "proved" it was
> measuring nothing. See *The regression that measured nothing*.

### Measured after

| | |
|---|---|
| `Pokemon.new` over the whole dex, levels 1/5/25/50/100 | 2,475 builds, **0 failures** |
| every slot of every trainer party in the cache | 1,878 builds, **0 failures** |
| the three starters at level 5 | Turtwig 20 HP, Tackle/Withdraw; Chimchar 19 HP, Scratch/Leer; Piplup 21 HP, Pound/Growl — with natures, ability slots and 0–31 IVs |

Natures also now carry their **names**: the Gen 4 extractor writes
`natureOrder = {1..25}` with `natures` as a list of names, so a Pokémon was
carrying a bare integer. `natureOrder` is pointed at the names at load, which
is the only form `Stats.calcGen3`'s lookup could ever resolve.

## Chapter two, measured the same way

Walking every script block reachable from Sandgem through Jubilife to the
Oreburgh gym — 327 blocks — left **16 unlowered rows, and exactly one of them
stopped anything**: `givebadge`, in the gym leader's own script. Without it the
Coal Badge is never awarded and every later gate that counts badges reads one
short for the rest of the game.

Badges are written two ways on purpose. `save.badges` is the record
`g4_count_badges` reads; `save.inventory` is where every other generation in
this engine keeps one, because `makeBattler` walks `badgeBoosts` and asks the
**bag**. Gen 4 awards no stat boost either way, but a badge that is not in the
bag is a badge the trainer card and the save editor cannot see.

**Trainer class names were already in the cache and needed inverting.** The
cartridge reads them from a message bank this port has not indexed by class —
but all 979 trainer rows carry both `class` and `className`, so the map is
derivable from data already extracted. `buffertrainerclassnamewitharticle` is
real now; `buffertrainerclassfromappearance` is not, because it wants the
player's own class from the appearance system, which does not exist here.

Chapter two now has **7 unlowered rows**, all of them the Jubilife NPC trade
and Mystery Gift — optional side interactions, nothing on the critical path.

### What is actually in the way now

Not scripts. `starttrainerbattle` lowers; its handler is a `pending()` stub
behind the Gen 4 battle handoff, and that is the single thing standing between
the opening and the first gym. What the measuring above establishes is that the
data side is ready:

- `trainers.lua` carries id, name, `className`, `class`, `battleType`, `aiMask`
  and a party of `{species, level, moves, form, ivScale}` on every row.
- Every one of those 1,878 party slots now builds a Pokémon without raising.
- `BattleState.newTrainer(game, oppClass, partyIndex)` wants
  `trainers[key].parties[i]`; the Gen 4 record has a flat `party`. That is a
  view, not a conversion.

## The battle handoff was one shape mismatch

`starttrainerbattle` has been lowering for a long time; its handler was a
`pending()` stub, and 221 script sites sat behind it. What was actually
missing turned out to be smaller than "the Gen 4 battle engine".

`BattleState.newTrainer(game, oppClass, partyIndex)` reads
`trainers[key].parties[i]`, because Gen 1 and Gen 2 put **several trainers in
one class** — `TrainerGroups`' "YOUNGSTER" holds a dozen parties, so the class
is the key and the index picks the person. Gen 4 numbers every trainer
individually and gives each one party. The record is right; it sits one level
shallower than the reader.

So `Data:seedDefaults` exposes `parties = { party }` — **a view, not a
conversion**: `parties[1]` *is* `party`, nothing is copied and nothing can
drift. Three things the slots need on the way through, each the cartridge's
own rule:

- **Move slot 0 is empty, not move 0.** `trdata` stores four move ids and pads
  with zero; `buildTrainerParty` would have handed the battler four moves, one
  of which does not exist. 102 slots in the cartridge are padded. A party whose
  moves are *all* zero is a `TRDATATYPE_BASE` row with no move list at all, and
  keeps nil so the level-up set applies.
- **IVs come from one byte.** `TrainerData_BuildParty`:
  `ivs = trmon[i].ivScale * MAX_IVS_SINGLE_STAT / MAX_IV_SCALE` — 31/255 of the
  scale, **the same value in all six stats**. Written to `dvs`, which is the
  parameter `Stats.calc` passes on as `ivs` for a Gen 3-model species, and
  `buildTrainerParty` already prefers a slot's own over the fixed fallback.
- **A double battle is the trainer's own byte.** `Script_IsTrainerDoubleBattle`
  is `battleType != BATTLE_TYPE_SINGLES`, and `BattleState` reads
  `trainer.doubleBattle` — the same field Gen 3 uses, so the battle builder
  needs no Gen 4 branch at all. 28 trainers are doubles.

**The object already knows who it is.** A trainer's object event carries a
script id in the `single_battles` band (3000+) or `double_battles` (5000+), and
`Script_GetTrainerID` is `scriptID - offset + 1`. The extractor resolved that
at import and hung the answer on the def:

```lua
script = 3231, scriptBand = "single_battles",
trainer = { id = 232, name = "David", class = 14,
            className = "Black Belt", partySize = 2 },
```

so `gettrainerid` is a field read rather than arithmetic repeated on this side.

### The five handlers

`g4_start_battle` resolves both operands (the second is `TRAINER_NONE` for an
ordinary fight, non-zero for two opponents at once, which `start_battle`
already knows how to build through `trainerBKey`) and hands off. It guards on
`parties[1][1]`, not `parties[1]`: an empty party is a live table that passes a
truthiness test and then takes the game down in `makeBattler` with
`data.pokemon[nil]`. Exactly one trainer in the cartridge is empty — id 0,
`TRAINER_NONE`, which is the value the *second* operand carries every single
battle.

`g4_check_won_battle` reads `ctx.lastBattleResult` rather than keeping a second
copy, and marks the trainer beaten on the way past. That has to happen here:
the cartridge sets the defeated flag in the **battle teardown**, not the
script — no Sinnoh script runs `settrainerflag` after a fight — so a port
waiting for one would have every trainer in the region challenge you again for
ever. Same shape as the Gen 3 fix already in `start_battle`.

`g4_check_lost_battle` is its twin and **not its negation**:
`CheckPlayerLostBattle` reads a different bit of the same result mask, so a
battle that ended some third way answers no to both.

`g4_get_trainer_id` and `g4_check_trainer_double` read the object's own
`trainer` record; `g4_check_two_alive` is `Party_HasTwoAliveMons`, which is
what gates a double battle — you cannot be asked into one with a single
Pokémon standing.

### Measured

| | |
|---|---|
| trainers given a `parties` view | 928 |
| slots whose padded move zeros were stripped | 102 |
| slots given IVs from `ivScale` | 1,878 |
| `buildTrainerParty`'s exact body over every trainer | **1,878 mons built, 0 failed** |
| double-battle trainers | 28 |

The first gym leader, built from the cache end to end:

```
Leader Roark (id 246, class 62, single):
  GEODUDE  lv12 (hp 32, iv 6) [Stealth Rock, Rock Throw]
  ONIX     lv12 (hp 31, iv 6) [Stealth Rock, Rock Throw, Screech]
  CRANIDOS lv14 (hp 43, iv 6) [Headbutt, Pursuit, Leer]
```

Script coverage 95.26% → **95.36%**, and the four `pending()` stubs left are
`g4_pokemart` (the shop screen, 19 sites), `g4_get_movement_type`, `g4_common`
and `g4_unimplemented`. The battle ones are gone.

What this does **not** claim: the battle that runs is this engine's, not
Platinum's. The trainer, the party, the levels, the moves, the IVs and the
single/double shape are the cartridge's; the damage model, the AI and the
screen are the port's. Trainer pictures come back nil — Gen 4 trainer sprites
are not extracted yet — and `getImage` returns nil on a nil path, so the
battle runs without one rather than failing.

## A Sinnoh mart's stock is decided by your badge count, not by the town

`ScrCmd_PokeMartCommon` ignores its one operand entirely. It counts the badges
in the save, turns that into a **tier**, and walks one shared table taking every
row whose `requiredBadges` is at or below it. Every ordinary Poké Mart in the
region sells the same list; what changes is how far down it goes.

The switch is transcribed rather than smoothed, because it is not `tier =
badges` and not monotonic in the obvious way — zero badges and one badge give
different tiers, then the pairs share:

```
0 -> 1     1,2 -> 2     3,4 -> 3     5,6 -> 4     7 -> 5     8 -> 6
```

`constants.martCommon` was already extracted and had never been read: 19 rows
of `{ badges, item }`. Run against the live cache at every badge count:

| badges | items | what opens up |
|---|---|---|
| 0 | 4 | Poké Ball, Potion, Antidote, Parlyz Heal |
| 1–2 | 10 | Super Potion, Awakening, Burn Heal, Ice Heal, Escape Rope, Repel |
| 3–4 | 13 | Great Ball, Revive, Super Repel |
| 5–6 | 17 | Ultra Ball, Hyper Potion, Full Heal, Max Repel |
| 7 | 18 | Max Potion |
| 8 | 19 | Full Restore |

The first four are the Poké Ball and the Potion, which is the whole reason this
had to be wired before anyone could play past Jubilife.

**`pokemartspecialties` is deliberately not wired.** It indexes
`PokeMartSpecialties[martID]` — a *second* table, one stock list per counter,
which this cache does not carry. 22 sites, all the Veilstone department store
and the Game Corner. Opening a common mart in their place would sell the wrong
things under the right sign, so the counter is skipped and the log says which
table is missing.

The screen itself needed nothing: `martText` reads `constants.gen3MartText`,
which a Gen 4 cache does not have, so `gen3Counter` answers nil and
`ShopMenu.classic` runs — and its stock is a plain list of item keys, which is
exactly what `martCommon` yields.

### Where the `pending()` stubs stand

Three left, and none is a feature the player meets head-on:

- `g4_get_movement_type` — one site.
- `g4_common` — the FALLBACK for a cache with no band table. The live cache has
  one, so all 668 `callcommonscript` sites resolve to a real label and this
  never fires.
- `g4_unimplemented` — the decoder's own marker for an opcode the cartridge
  itself leaves unbuilt.

### The next extractor stage, named rather than guessed

Opponent trainer sprites. `gen4_graphics` carries 40 **trainer backs** (the
player's own) and no fronts at all — the `trfgra` archive has not been ripped.
So `BattleState.trainerPicPath` answers nil for every Sinnoh trainer, and
`getImage` returns nil on a nil path, so the battle runs without a portrait
rather than failing. That is an extraction stage, not a wiring one, and
inventing a stand-in portrait would be worse than the gap.

## The face across the field

Battles ran without one for as long as they ran at all:
`BattleState.trainerPicPath` reads `trainer.pic`, nothing wrote it, and
`getImage` answers nil on a nil path — so every Sinnoh trainer fought you as a
name and a party with no portrait. `src/import/Gen4Trgra.lua` and a
`trainer_sprites` stage close that.

**`/poketool/trgra/trfgra.narc` is 525 members = 105 classes of five**, and the
cycle was confirmed by counting every member's magic off the cartridge rather
than by trusting the build file: 105 RLCN, 105 RECN, 105 RNAN, 210 RGCN.

```
+0 NCGR  the cell-based sprite     +1 NCLR  the class palette
+2 NCER  its cell bank             +3 NANR  its animation
+4 NCGR  the LINEAR sheet
```

**105 is the trainer CLASS count, not the trainer count.**
`generated/trainer_classes.txt` has exactly 105 rows and
`SpriteSystem_SetTrainerClassGraphicsIndex(trainerClass, FACE_FRONT, …)` is
what indexes the archive — so every Youngster in the region shares one face,
and the path is stamped on every trainer row carrying that class. That is also
why the stage rewrites `trainers` rather than writing a table of its own for a
reader to join, the same shape the species-sprite stage uses for `pokemon`.

Verified by rendering rather than by reading the index: class 0 is the male
player, 2 a Youngster, 9 a Hiker, 12 a male Cyclist on a bicycle, 61 a female
School Kid, 62 Leader Roark — `trainer_classes.txt` line for line.

### Three things that each look like a different fault

**Which NCGR.** Member +0 carries *no dimensions* — `tilesX`/`tilesY` come back
nil, which is what `-vram -clobbersize` produces: its size lives in the NCER
beside it and the hardware assembles it from cells. Member +4 declares 20×10
tiles. So +4 is the one a reader can use without a cell walk, and it is the
same artwork.

**The pixels are encrypted, like the species sheets — and this is the one that
misleads.** Read raw, member +4 is 81% zero bytes and renders as coloured
static, which reads as a palette or layout fault rather than an encryption one.
`decryptSprite` first, then `indices`, and the figures appear.

**The palette is 256 entries and the sheet is 4bpp.** Only the first sixteen
are non-zero and the decrypted indices span exactly 0–15, so sub-palette 0 is
the whole of it. Stated rather than searched for, because a 4bpp sheet whose
palette bank is picked wrong still renders a *recognisable figure in the wrong
colours* — which is a far harder fault to notice than static. (It showed up
here first as every trainer rendered in cyan.)

### Frame 1 is the picture, and that is the opposite of the species rule

20×10 tiles is 160×80 — two 80×80 frames side by side, the same shape
`pl_pokegra` uses. But the proportions invert. Measured across all 105 classes:

| | |
|---|---|
| two genuinely different frames | 25 |
| second frame **empty** | 80 |
| identical frames | 0 |

A species sheet is 475-of-477 two-frame, so the strip is emitted whole and
`picAnim` cuts it. Here four classes in five have a blank right half, and a
whole strip would draw every one of those trainers in the left half of a
double-width picture. So frame 1 is emitted as the picture, and the second
frame is recorded as `frames` for an animation stage that does not exist yet.

Measured after: **105 of 105 classes render at 80×80**, none missing a sheet or
a palette.

**This one needs a re-import.** Everything else in the last few passes lands at
load time on the cache you already have; pictures cannot be conjured from a
cache that never held them. Until then `trainer.pic` stays nil and battles run
without a portrait, which is exactly what they do now — so nothing regresses by
waiting.

## The regression that measured nothing

The previous pass reported "Crystal 753 builds, Emerald 1,200 builds, **0
differ**" for the `Stats.calc` argument fix, and concluded that natures had
never affected a stat in this engine. That was wrong twice over, and the two
faults pushed the same way.

**The harness compared the new file against itself.** Its "before" side loaded
from an overlay directory that an earlier `rm -rf` in the same session had
deleted, so both sides fell through to the same file on disk — which by then
was the *fixed* one. Identical inputs, identical outputs, zero differences, and
none of it meant anything.

**And it never loaded the natures.** `Data:load` calls
`Stats.setNatures(constants.natures)` before `seedDefaults`; the harness built
its `data` table straight from the cache files and skipped that. So even a
correct comparison would have run with `natures` nil and `natureMod` defaulting
to 100 — which is precisely the conclusion it then reported as a finding.

That is the same failure recorded earlier in this file about a stale staged
cache, in a new place: **a measurement that cannot fail is not a measurement.**
The canary that caught it was one line — print whether the build succeeded and
what nature it got. It printed `built=false`, and every "identical" row turned
out to be two copies of the same error string.

### Measured properly

Against a reconstructed pre-fix file, with the natures loaded the way
`Data:load` loads them:

| | |
|---|---|
| crystal (gen 2) | 753 builds, **0 differ** |
| emerald (gen 3) | 900 builds, **900 differ** |

Gen 1 and Gen 2 are untouched because `Stats.isGen3` is false for them and the
nature never reaches the formula. Gen 3 changes on every build — and changes
*correctly*. Over 600 seeded Emerald builds:

| | |
|---|---|
| neutral nature (Hardy, Docile, Serious, Bashful, Quirky) | 108 builds, **0 changed** |
| modifying nature | 492 builds, **all changed** |

A Naughty Abra at level 70 goes from 39 Attack / 89 Sp.Def to 42 / 80 — plus
ten percent on the raised stat, minus ten on the lowered one, and nothing
anywhere else.

**So this completes a feature that was written and never took effect, rather
than only removing a crash.** `gen3Seed`'s own comment calls the absence a bug —
*"nothing in the game ever got the ten percent its nature is supposed to
move"* — and it was still describing an open one. Emerald and FireRed will now
compute the stats the cartridge computes. That is a real change to a shipped
game's numbers, arriving as a side effect of a Gen 4 crash fix, and it is worth
knowing before it is noticed.

## Sinnoh natures were worth nothing, and the table is a rule

Same seam, the other end. `Data:load` hands `constants.natures` to
`Stats.setNatures`, which wants it **keyed by name** with a `modifiers`
record — the shape Gen 3's extractor writes from `gNatureStatTable`. Gen 4's
extractor writes a flat **list** of 25 names, so the lookup found nothing and
every Sinnoh Pokémon carried a nature that moved no stat.

It does not need extracting, because the cartridge derives it too.
`sNatureStatAffinities` (`src/pokemon.c`) is the 25×5 pattern every generation
uses:

```
raised = nature / 5     lowered = nature % 5
```

over `[attack, defense, speed, spAtk, spDef]` — and the two are equal for
exactly five natures, which is what makes Hardy, Docile, Serious, Bashful and
Quirky neutral. `Pokemon_GetNatureStatValue` then multiplies by 110 or 90 over
100, and 110/90/100 is already the percentage `Stats.calcGen3` expects, so
there is no conversion either.

Cross-checked row by row against pret's own table rather than assumed — Lonely
is nature 1, so raised = 0 (Attack) and lowered = 1 (Defense), which is what
`sNatureStatAffinities[NATURE_LONELY]` says; same for Brave, Adamant, Naughty,
Bold and five more. **0 of 10 spot-checked rows wrong**, 20 natures move a stat,
5 are neutral. Turtwig at 50 with flat 20 IVs: Hardy 83 Atk / 60 SpA, Adamant
91 / 54, Bold 74 Atk / 86 Def, Modest 74 / 66.

## Two curves with no formula

`Growth` carries the six polynomials Gen 1 and Gen 2 get away with. Gen 3 added
ERRATIC and FLUCTUATING, which are piecewise and have no closed form at all, so
`Growth.expForLevel` warns once and falls back to MEDIUM_FAST. The gap is not
small:

| at level 100 | experience |
|---|---|
| MEDIUM_FAST (the fallback) | 1,000,000 |
| ERRATIC | 600,000 |
| FLUCTUATING | 1,640,000 |

**36 of Sinnoh's 508 species** were levelling on a curve 40% too slow or 64%
too fast for their whole run.

`Pokemon_LoadExperienceTableOf` reads a whole NARC member:

```c
NARC_ReadWholeMemberByIndexPair(monExpTable,
    NARC_INDEX_POKETOOL__PERSONAL__PL_GROWTBL, monExpRate)
```

so `/poketool/personal/pl_growtbl.narc` is one member per rate, indexed by the
same `expRate` byte a species record carries — 8 members of 101 u32, levels
0–100. The order is `generated/exp_rates.txt`, which is the **same order** Gen
3's extractor uses for `gExperienceTables`, so the shape `Growth.setTables`
already reads needs no translation and `Data:load` already calls it.

**Checked against the formulas rather than trusted.** MEDIUM_SLOW and FAST
match their polynomial at all 100 levels. MEDIUM_FAST and SLOW match at 99 of
100 — and the single disagreement is *level 1*, where the table says 0 and the
formula says 1. The cartridge is right: level 1 costs no experience. So the
table is not only exact for the two curves that had none, it is a correction
for two that already worked. All six are monotonic.

### A stage that would have taken the import down

The first draft of this block ended with `Logger.info(...)` to report how many
curves were read. **`RomExtractorGen4.lua` requires no Logger at all** — it
reports through `self.<stage>Report` fields and `index.counts`, which is why
every other stage in the file does. A nil index there would have killed the
import at the one moment nobody is watching it. Caught by grepping the file for
the symbol before committing, not by running it; the same check is worth making
for any helper assumed to be in scope in a 200 KB file nobody reads end to end.

Both this and the trainer pictures land on the **next re-import**, and they are
the only two things in this stretch of work that do.

---

## Chapter three: the Oreburgh gate to Gardenia's gym

Walked the same way the opening and chapter two were — from every entry point
in the maps the critical path crosses, following every `goto`, `call` and
conditional, and stepping into `callcommonscript`'s own member rather than
counting the call and stopping. **191 entry points, 610 blocks, 5,230
instructions.**

Maps in the set: Oreburgh Gate 1F/B1F, Route 207, Route 203, Jubilife City
(plus its mart, Centre and the Poketch Co.), Route 204 south and north, the
Ravaged Path, Floaroma Town, the Meadow and its house, the Valley Windworks
inside and out, Route 205 south and north, Eterna Forest and its gate, Eterna
City, the gym, the Cycle Shop and all four floors of the Galactic building.

**176 unlowered rows across 42 commands → 11 rows across 4.**

And the walk was worth running backwards over ground already covered, because a
wider net over the opening found things the first, narrower measurement had
missed:

| set | blocks | before | after |
|---|---|---|---|
| chapter one (Twinleaf → Sandgem → Route 202) | 484 | 132 rows / 20 commands | **1 row / 1 command** |
| chapter two (Sandgem → Oreburgh gym) | 503 | 169 / 37 | **8 / 4** |
| chapter three (Oreburgh gate → Eterna gym) | 610 | 176 / 42 | **11 / 4** |
| whole corpus | 8,567 | 95.36% of 78,093 instructions | **96.07%** |

Fully-lowered blocks went 82.15% → **85.07%**. What is left across all three
chapters is **the contest system** — accessories, contestant names, backdrops —
plus one nickname prompt in Rowan's lab. None of it is on the critical path and
all of it is one absent feature rather than a tail.

### The earlier "the opening is at zero" was a narrower set, not a finish line

Worth stating plainly because it is the kind of claim that ages badly: the first
opening measurement used a smaller map list and did not step into the common
scripts, and it reported zero. The same route with the houses, Rowan's lab and
`scripts_common` included reports 132. **Both numbers are correct for what they
measured, and only the second one is about the game.** The check that this is a
widening rather than a regression was to run the *pre-change* lowering against
the *new* set: 132 before, 1 after.

### What the item-pickup line cost

96 of chapter three's 176 rows were four commands in `scripts_common`, which is
to say **every item the player picks up anywhere in the region**:
`getitempocket` (46), `bufferpocketname` (36), `bufferitemnameplural` (9),
`checkitemisplate` (5). `getitempocket` is the dangerous kind of gap — it writes
a var, and an unlowered var-writer leaves the comparison register holding the
*previous* command's answer, so the pocket name after it printed whatever that
happened to be.

All four were already answerable from the cache and nothing had asked:

- the pocket is the item row's own `fieldPocket`, on all 446 rows (counted:
  163 ITEMS, 38 MEDICINE, 16 POKE_BALLS, 100 TM_HM, 64 BERRIES, 12 MAIL,
  13 BATTLE_ITEMS, 40 KEY_ITEMS);
- the pocket *name* is `gen4_menus.bag.pockets`, eight entries in exactly that
  order, which the menu stage extracts from message bank 395 (bank 396 is the
  same eight with a colour code and a glyph in front, which a text box here
  cannot print);
- the plural is **a bank of its own**, 394 — "Poké Balls" and "TMs & HMs" are
  both in it and neither is the singular with a letter added;
- the plate test is a contiguous run of item ids, derived from the rows whose
  names end in " Plate" rather than from two hard-coded numbers.

### The Jubilife tag battle, and what this port actually fields

`starttagbattle <partner> <enemy1> <enemy2>` is the mandatory scene where Dawn
or Lucas fights two Galactic grunts beside you. Leaving it stubbed is worse than
skipping a fight: the very next row is `CheckWonBattle`, and the branch on FALSE
is `JubilifeCity_BlackOut` — **an unlowered battle blacks the player out in the
middle of a cutscene.**

Stated plainly, because it is not the cartridge's fight: the two foes are real
and it is a real double battle, but **the ally trainer is not on the field**.
Both of the player's flanks come from the player's own party, because an
AI-driven battler on the player's side is a battle-engine feature this port does
not have. The seam for it is small and identified — `chooseAction` would fill
`pendingActions[PLAYER_RIGHT]` from `enemyAction` instead of asking the menu,
and `choosingSlotNow` would skip that slot — but it is a battle-engine change,
not a script one, and it is on the list rather than in this pass. The fight as
it stands is harder than Sinnoh's and winnable, which is the trade that keeps
the scene finishable.

### The first battle in the game was not lowered either

`startfirstbattle` — Barry's challenge on Route 201, six sites, one per starter
per gender — is an ordinary trainer battle with **one rule changed: losing it
must not black you out.** The script says so itself; `Route201_RivalWonLetsGoHome`
exists only because the story continues either way. The port already has that
rule as `opts.canLose` (the Battle Tower's), which `afterBattle` reads before
the blackout, so this is the existing battle path with a flag rather than a
second one.

### The Pokédex was never handed over

`givepokedex` sets `Pokedex_ObtainPokedex`. `Flags.hasPokedex` reads
`EVENT_GOT_POKEDEX`/`ENGINE_POKEDEX` off the save and gates the start menu's
Pokédex row and the main menu's continue panel — **and no Gen 4 script set
either**, so the row was missing for the whole game. One line, and it plugs into
a gate that has been there since Gen 1.

### The Poketch could be read and never written

`checkpoketchappregistered` has been lowered since the small-state pass and
answers from `save.poketch.registered`. Nothing in the port had ever written it,
so every app read as unregistered for ever. `enablepoketch` and
`registerpoketchapp` now do — and the watch arrives with the Digital Watch
already on it, which the cartridge registers in the same handler rather than
from the script.

**The two Poketch numberings are not the same one, and they agree at 0.** A
script's operand is a `POKETCH_APPID_*`: 0 DIGITAL WATCH, 1 CALCULATOR, 2 MEMO
PAD, 3 PEDOMETER — which is exactly the order of message bank 457. The cache's
`gen4_menus.poketch.apps[].id` is a *different* index: the Poketch Co.
description bank's order, where 1 is the Analog Watch and the Calculator is 6,
because that stage pairs descriptions with names and numbers them as it goes.
Both joins succeed and only one is right, and they diverge from index 1 — the
worst possible way to be wrong. Bank 457 is the script's own vocabulary and is
what the buffer reads.

**Still open:** `src/ui/Gen4Poketch` lists every app regardless of registration,
so the registration is recorded and not yet visible. The filter needs the
reverse join (a record's name back to its app id) and a fallback for a save
written before any of this, so it is its own small change.

### The Eterna Gym clock: measured, and not a blocker

On the cartridge the gym's flower clock has two hands that are walkways, and
advancing the clock rotates them — that is how you cross to Gardenia. So
`advanceeternagymclock` looked like the chapter's blocker.

**It is not, and the reason is in the map rather than the script.** Dumping the
gym's own permission grid — header 67, matrix 220, chunk 294 — gives **775 cells
of behaviour NONE, one warp entrance, and not a single blocked or
dynamic-collision cell.** The floor is one open disc. The obstruction never
existed in the map data at all; it lives in `PersistedMapFeatures` and the
`gym_features` overlay, neither of which this port has. And the five
`advanceeternagymclock` rows all fire *after* a trainer is beaten, and not one
of them gates a branch — the script counts its own progress in
`VAR_ETERNA_GYM_TRAINERS_BEATEN`.

So the puzzle is **absent, not impassable**: Gardenia is reachable by walking
straight at her. That is a fidelity gap and it is on the list; it is not a
stall, and the measurement is what told the two apart.

### `blackoutfrombattle` is a no-op because the work is already done

All eight sites are the same three rows: `BlackOutFromBattle / ReleaseAll /
End`. The cartridge hands a lost scripted battle back to the script and lets the
script order the blackout. This port does not — `OverworldState:afterBattle`
heals the party, halves the money and warps to the heal point the moment a
battle is lost, as it does for Gen 1-3 — so by the time the script resumes the
player is already standing in the Centre. **Implementing it for real would halve
the money a second time.**

### The TM/HM move table, and a join that was measured and thrown away

`buffertmhmmovename` needs to know which move a TM teaches. That pairing exists
in exactly one place: `sTMHMMoves`, a flat ARM9 table of 100 u16 in TM01..TM92
then HM01..HM08 order.

The tempting shortcut is that a TM's own item description *is* the move's
description. It was tried and measured: **0 of 100 matched raw, 61 of 100 after
normalising the line breaks.** Sixty-one per cent is not a table.

So the ARM9 is read instead, and **found by the HM tail rather than by an
address**, because Rev 0 is a different binary: the eight HMs are a fixed,
distinctive run (Cut 15, Fly 19, Surf 57, Strength 70, Defog 432, Rock Smash
249, Waterfall 127, Rock Climb 431), so the search is for that sequence and the
table is the 92 entries in front of it.

**Two matches in the ARM9 and only one is the table** — the same shape as the
type chart's two terminators, and the same lesson. The second candidate
(0xF1BF8) is mostly zeros and is rejected by requiring every entry to be
non-zero and unique; the real one is at 0xF0BFC. The check that says the search
worked is that the answer is recognisable: **TM01 Focus Punch, TM02 Dragon
Claw, TM03 Water Pulse, TM04 Calm Mind, TM05 Roar, TM86 Grass Knot** — which is
the TM Gardenia hands over — **and TM92 Trick Room.**

Written as `constants.tmhmMoves`, and **the runtime indexes it from the item's
name** ("TM86" is 86, "HM02" is 92 + 2) rather than from an item-id anchor, so
nothing has to know where `ITEM_TM01` sits.

**This needs a re-import.** It joins the trainer class pictures and the
experience curves, so one re-import now pays for three stages.

### Five commands pret has not named, read one at a time

`2CD`, `32D`, `32E`, `331`, `332` — five rows in Eterna City and the Galactic
building. "Unnamed" is not a category, so they were read individually rather
than lumped: `2CD` starts a weather task, and the other four walk the map-object
list turning a status flag on or off (the cutscenes hiding and showing their
cast). **Not one of them writes a var**, which is the only thing that would have
made a no-op dangerous.

### Everything else in this pass

| command | what it does now | why |
|---|---|---|
| `setblackoutwarpid` | records the id on the save | the port answers the heal point from `save.lastHeal`, which a Centre already writes; guessing a map from an unextracted table index would be worse than the answer it has |
| `getpartycount` / `countpartynoneggs` | real counts | eggs included and excluded respectively, which is why the cartridge has both |
| `setplayerstate` | dismount on WALKING | the operand is a **bitmask**, not an enum — `player_transitions.txt` names two of its entries `x0008` and `x0200`, which is the table telling you its own numbering. Only WALKING (6 sites) and HEALING (3) are ever passed |
| `setplayerbike` | sets `save.onBike` | safe with no bike art: `Player:spriteFor` falls through to the walking sheet when `bikeSprite` is nil |
| `getdayofweek` | 0 Sunday … 6 Saturday | the Windworks' Drifloon check |
| `startlegendarybattle` | wild battle, legendary flag | not only legendaries — the one site here is the Friday **Drifloon** |
| `giveegg` | an egg, level 1, no nickname prompt | Cynthia's Togepi; dropped on a full party, as the cartridge does |
| `startcatchingtutorial` | no-op | a scripted demonstration nobody plays; the scene continues |
| `startdestroyobstacleanimation` | no-op that still writes its var | Roark's Rock Smash flourish — the rock is removed by the `RemoveObject` on the next row, which was always lowered |
| `buffermapname` | the header's `label` | the player-facing name from bank 433, already on every header |
| `getlocaldexseencount` | the real seen count | the port keeps the dex whole rather than per-region, which is right for every script that asks |
| `setstepflag` / `clearstepflag` | no-op | the bit freezes the step counter during a cutscene; a script here already owns the input gate |
| `calculatetrainerinfoappearance` | writes zero | no appearance system — the same reason `loadtrainerappearances` is already a no-op |
| `getswarmmapandspecies` | writes **both** vars | a var-writer that skips one leaves the comparison behind it reading the last command's answer |
| `setbgm` | `play_music` | the same verb `playmusic` already uses; without a Gen 4 sequence bank there is nothing on either side of "play now" against "play from now on" |
| `showstartmenu` | no-op | the port's start menu is Gen 1/2's, and opening Kanto's menu in Sinnoh is worse than opening none. A Gen 4 start menu is its own task |

### Still open after this pass

- **The contest system** — accessories, contestant names, backdrops. One absent
  feature, 11 rows, nothing on the path.
- **`openpokemonnamingscreen`** in Rowan's lab — a prompt, not a gate.
- **An ally-trainer battler**, which is what a real tag battle needs.
- **The Poketch registration filter** in the UI.
- **The Eterna Gym clock as a puzzle**, which needs dynamic map features.

---

## Chapter four: the Cycling Road to Veilstone's gym

**271 entry points, 835 blocks, 6,876 instructions** — Route 206 and both
Cycling Road gates, Route 207, Mt. Coronet's south end, Route 208, Hearthome
(city, all four gym rooms, the Fan Club, the contest hall and Amity Square),
Route 209 and the Lost Tower, Solaceon, Route 210, Route 215 and Veilstone.

**138 unlowered rows across 52 commands → 7 across 3.**

Running the same walk over the earlier chapters with the new lowering:

| set | blocks | start of this pass | now |
|---|---|---|---|
| chapter one | 484 | 1 row | **1** |
| chapter two | 503 | 8 | **4** |
| chapter three | 610 | 11 | **3** |
| chapter four | 835 | 138 | **7** |
| whole corpus | 8,567 | 96.07% | **96.57%** (2,676 rows left) |

Fully-lowered blocks 85.07% → **86.41%**.

What is left in all four chapters is now three things: **contests**
(`buffercontestantmonname`, `givepoffin`, contest-photo `27c`), and the nickname
prompt in Rowan's lab. The two `27c`/`givepoffin` rows are *variable-length*
opcodes, which a linear walk cannot size anyway.

### The Cycling Road could have stopped the player leaving Eterna

Both gate coord events are the same three rows:

```
CheckPlayerOnBike VAR_RESULT
GoToIfEq VAR_RESULT, TRUE, ...ForceBikingInGateCoordEvent
Message ...Text_OpenOnlyToCyclists
```

With the check unlowered, `VAR_RESULT` holds whatever the previous command left
behind, and the gate either turns the player away from the only road south out
of Eterna or waves them through on foot — decided by a value that has nothing to
do with the bicycle.

**And the bike itself was answering the wrong question.** `bikeAllowed` has an
arm for Gen 2 (map environment), one for Gen 3 (`gMapHeader.allowCycling`) and
then a Gen 1 fallback built on a table of **Kanto** map ids and tileset names. A
Platinum cache writes no such table, so Sinnoh fell through to "is this map
outdoors?".

The exact answer was already in the cache and nothing asked for it:
`Gen4MapHeaders.parse` has always read `allowBike` out of the header flags word,
and `maps.lua` carries it on **all 593 rows**. One arm, the precise mirror of the
Gen 3 one directly above it.

### Every Sinnoh gym puzzle is a runtime overlay, not map collision

Eterna's flower clock made this look like a one-off. It is not. Dumping each
gym's own permission grid:

| gym | header | matrix | chunk | grid |
|---|---|---|---|---|
| Eterna | 67 | 220 | 294 | 775 open, 1 warp |
| Hearthome (entrance + trainer rooms) | 88, 89 | 222, 223 | 230, 231 | open |
| Veilstone | 133 | 115 | 235 | open |

**2,504 cells of behaviour NONE across the three, three warp entrances, one warp
panel, and not a single blocked or dynamic-collision cell.** Gardenia's rotating
clock hands, Fantina's quiz doors and Maylene's punching bags all live in
`PersistedMapFeatures` and the `gym_features` overlay, which this port does not
have.

So all three gyms are **absent puzzles, not impassable ones** — each can be
crossed by walking straight at the leader. That is a fidelity gap on the
tracker, and it is emphatically not a stall; only the measurement separates the
two, and guessing would have got it backwards.

### `getpartymonfriendship` was the third commonest gap in the whole cartridge

143 sites — every "your Pokémon looks happy" line in Sinnoh. Four party queries
went in together, and **the destination is the first operand on three of the
four**, which is the opposite of how they read aloud:

```
getpartymonfriendship <destVar> <slot>
getpartymontype       <type1Var> <type2Var> <slot>
checkpartymonhasmove  <destVar> <move> <slot>
checkpartyhasspecies2 <species> <destVar>      <- and this one is the other way
```

They were lowered one at a time against `scrcmd_party.c` rather than by pattern,
because the pattern is not a pattern.

**Friendship is not kept for Gen 4 yet**, and the command says so once rather
than answering zero: `mon.friendship or mon.happiness` is the spelling Gen 3
already uses, a Gen 4 mon carries neither, so the species' `baseFriendship` is
the answer — which is exactly the value a freshly caught Pokémon has on the
cartridge, and therefore right until something starts moving the counter.

### Four name banks were in the cache for systems that are not

`bufferitemnamewitharticle`, `bufferaccessoryname`, its with-article twin, and
the two Underground goods buffers all read a message bank keyed by their
operand — and every one of those banks is already extracted. They are lowered
through a single `bank:<n>` buffer kind rather than five near-identical
branches.

The bank ids are the line number in `generated/text_banks.txt` minus one, and
that is **checked rather than assumed each time**: bank 626 reads "PC" and 627
reads "a {COLOR}PC{COLOR}", which is the pair the right way round. Sitting one
off would have printed the article version wherever the plain one belonged, in
both directions, with no error.

The systems behind those names still do not exist. What this buys is that the
line reads properly instead of printing a raw token.

**`buffercontestantmonname` is deliberately left unlowered.** A contestant is a
live entrant, not a table row, so there is no bank to read — and filling the
slot with a blank would hide an absent system instead of reporting it.

### `getselectedpartyslot` answers "cancelled", not "slot 0"

`PARTY_SLOT_NONE` is `0xFF`. While the menus in front of it — the move tutor's —
are not built, cancelled is the honest answer; **answering 0 would name the
first Pokémon and send the script down a branch the player never chose.**

### Everything else in this pass

| command | now | why |
|---|---|---|
| `forcebicycling` | sets `save.forcedBike` | the port already has the idea for Kanto's Route 17, armed by a tile rather than a script |
| `getpreviousmapid` | the previous map's header id | one site, the Cycling Road asking which end you came in from |
| `startwildbattle` | a real wild battle | `startlegendarybattle` without the flag that makes it unfleeable; two sites at the Route 209 Spiritomb well |
| `getnationaldexseencount` | the real seen count | the port keeps the dex whole |
| `getfirstnonegginparty` | the **slot**, not the Pokémon | |
| the Underground, contests, accessories, the move tutor, Amity Square's berry man, the News Press | grouped no-ops and zero-writing var stubs | six absent systems, lowered by feature rather than by opcode, because that is how they will be built |
| `27c`, `0A8`, `338`, `339` | read one at a time | `0A8` writes a var (contest photos) so it must write zero; `338`/`339` walk the map-object list in Amity Square and write nothing |

### Still open

- **Contests** — the last thing standing in every chapter walked so far.
- **`openpokemonnamingscreen`** in Rowan's lab.
- **A friendship counter** for Gen 4, which is what would make those 143 sites
  say something that changes.
- **An ally-trainer battler** for real tag battles.
- **Gym puzzles as puzzles**, which needs dynamic map features — now known to
  affect at least three gyms rather than one.
- Three extractor stages still waiting on a re-import: trainer class pictures,
  the experience curves, and the TM/HM move table.

---

## Chapters five and six, and a correction to the last one

Two more walks: **Veilstone through Route 214, the Valor Lakefront, Route 213
and the Great Marsh to Crasher Wake's gym** (131 roots, 456 blocks, 3,735
instructions), and **Lake Valor through Route 212 to Fantina, then Route 218 to
Canalave and Byron** (157 roots, 418 blocks, 4,182 instructions). The
chapter-four work had already covered most of both.

| set | blocks | before | after |
|---|---|---|---|
| chapter one | 484 | — | **1** |
| chapter two | 503 | — | **4** |
| chapter three | 610 | — | **3** |
| chapter four | 835 | — | **7** |
| chapter five (Veilstone → Pastoria) | 456 | 27 rows / 14 cmds | **3 / 1** |
| chapter six (Lake Valor → Canalave) | 418 | 26 / 20 | **3 / 1** |
| whole corpus | 8,567 | 96.57% | **96.81%** (2,492 rows left) |

Fully-lowered blocks 86.41% → **87.45%**. Chapters five and six are now down to
`buffercontestantmonname` alone — the one that is deliberately left unlowered.

### The correction: "every Sinnoh gym puzzle is a runtime overlay" was too strong

That claim was made in the last section from **three** gyms — Eterna, Hearthome
and Veilstone — all of which measure as one open floor with nothing blocked.
Measuring the rest shows it is **false for three others**, and the behaviour
that makes the difference has a name: **`0x59 DYNAMIC_HEIGHT_COLLISION`**, which
means "ask the height system".

Censused over all 666 land chunks and 346,819 non-void cells:

| chunk(s) | map | cells |
|---|---|---|
| 225 | `C02GYM0101` Canalave gym | 293 |
| 223, 224 | `C06GYM0101` Pastoria gym | 356, plus 10 `H_GROUND` / 6 `M_GROUND` / 10 `L_GROUND` |
| 296, 297, 298 | `C08GYM0101/2/3` Sunyshore gym | 293 |

**942 cells, 6 of 666 chunks, 0.272% of the world — and nowhere else.** Not on a
route, not in a cave, not in a building.

So the honest statement is: Eterna, Hearthome and Veilstone keep their whole
puzzle in the `gym_features` overlay; Canalave, Pastoria and Sunyshore put
*part* of theirs in the map, and Pastoria's three water levels even carry
behaviours of their own.

**What this port does with it:** `Gen4Maps.mapDef` turns every non-void cell
into collision 0, so a `DYNAMIC_HEIGHT_COLLISION` cell is ordinary floor. Those
three gyms stay crossable — still no stall — but the player walks over water in
Pastoria and across the gaps in Canalave and Sunyshore rather than solving them.

The census is what makes leaving it alone defensible: because the behaviour
never appears outside a gym, treating it as floor cannot let anyone walk off a
cliff somewhere else. That was the question worth asking, and three samples
could not answer it.

### Two default values that are not zero

Both would have been silent, plausible bugs:

- **`findpartyslotwithmove` misses with 6, not 0.** The cartridge seeds the
  destination with `MAX_PARTY_SIZE` and only overwrites it on a hit, so "nobody
  knows this move" and "the lead knows it" are 6 and 0. Answering 0 on a miss
  names the lead Pokémon.
- **`getpcboxesfreeslotcount`** is asked by the Great Marsh gate so it can
  refuse you when there is nowhere to put a catch. A flat zero there is not
  "absent", it is "your boxes are full" — actively wrong rather than merely
  missing. It is answered from the port's own `Boxes` module, which already
  knows the running cartridge's box shape, so no constant is hard-coded.

### `getoverworldweather` answers from the map, not from an invented save field

`applyMapWeather` is Gen 3 only, and adding a `save.gen4Weather` that one
command writes and nothing else reads would be worse than not having it. The
map's own `weather` byte is extracted on 592 of 593 rows and is what the
cartridge seeds the saved value *from* on every load — so on the map you are
standing on, the two agree, and both of Route 213's sites are asking about the
beach they are on.

### The rest, grouped by the system they belong to

| system | commands | treatment |
|---|---|---|
| Great Marsh / safari | `startendsafarigame`, `startgreatmarshlookout`, `getcurrentsafarigamecaughtnum`, `setspeciallocation` | no-ops and zero-writing stubs |
| the shard move tutor (Route 212 house) | seven commands | same — and `checkcanaffordmove` must still write, or a script could charge for a move it never taught |
| dex milestones | `getunownformsseencount`, `checknationaldexcompleted`, `checkgamecompleted`, `turnonpokedexformdetection`, both diplomas | nothing here is tracked per-region or per-form |
| presentation | `stopse`, `startlibrarytv`, `playboatcutscene` | no Gen 4 SE bank at all; the set-pieces have their own screens |
| `2B5`, `29F` | read individually | `2B5` is `SetExitLocation` and writes no var; `29F` reads one and returns |

### Still open

- **Contests** — now the only thing left in five of the six chapters walked.
- `openpokemonnamingscreen`, and the two variable-length contest opcodes.
- **Dynamic-height gym floors** — three gyms, bounded and measured.
- A friendship counter; an ally-trainer battler.
- Three extractor stages waiting on one re-import.

---

## Chapters seven and eight: Snowpoint, Spear Pillar and the end of the game

The last two walks. **Chapter seven** — Canalave, Iron Island, Celestic, the
Galactic HQ, Routes 216 and 217, Snowpoint and Lake Acuity — came in at 196
roots, 560 blocks and only **16** unlowered rows; the earlier chapters had
already covered it. **Chapter eight** — Mt. Coronet's summit, Spear Pillar, the
Distortion World, Sunyshore, Victory Road and the whole Pokémon League — is 129
roots, 421 blocks and **128** rows, and it contains the end of the game.

**The whole main story is now walked.**

| chapter | blocks | unlowered |
|---|---|---|
| one — Twinleaf → Route 202 | 484 | 1 |
| two — Sandgem → Oreburgh | 503 | 4 |
| three — Oreburgh → Eterna | 610 | 3 |
| four — Cycling Road → Veilstone | 835 | 7 |
| five — Veilstone → Pastoria | 456 | 3 |
| six — Lake Valor → Canalave | 418 | 3 |
| seven — Byron → Candice | 560 | **16 → 3** |
| eight — Spear Pillar → Champion | 421 | **128 → 3** |
| whole corpus | 8,567 | 96.81% → **97.35%** (2,066 rows left) |

Fully-lowered blocks 87.45% → **89.76%**. Seven of the eight chapters are down
to `buffercontestantmonname` alone.

### The game can now be finished

`cleargame` is `ClearGame(task)`: the induction, the credits, the autosave and
the return to the title. The port has had that whole flow since Gen 1 as
`record_hall_of_fame` — Gen 2 lowers its own `HallOfFame` special to the same
verb — so **the last three rows of the Sinnoh story were one line.**

### The one genuine hard blocker in the whole walk: the Distortion World

Everything else found across eight chapters was a missing scene, a missing
name, or an absent side system. This is different, and it is measured.

`adddistortionworldmapobject` does not build anything — `DistWorld_AddMapObject
WithLocalID(localID)` **spawns an object the map already carries**, by the same
local id every other object command uses. So those 14 add and 10 delete rows
lower straight onto the port's existing show and hide, and the Distortion
World's cast now appears where it should.

**That is not the same as making it crossable.** Running the port's own
collision rule (void ⇒ blocked, everything else ⇒ passable) over the floors and
counting connected components:

| map | size | walkable cells | components | largest |
|---|---|---|---|---|
| Distortion World 1F | 64×64 | **92** | 9 | 57 |
| Distortion World B1F | 64×32 | **102** | 12 | 25 |

Ninety-two walkable cells out of four thousand. The floor *is* the platforms,
and an object in this port is an actor, not ground. Making them visible is real
progress and it is not the fix — the Distortion World needs objects that
contribute walkable cells, which is a collision feature the engine does not
have. It is mandatory main story, so this is the one place a player would stop.

### The near-miss that says what a measurement has to be

Iron Island's B1F-right, B2F-left and B3F each split into **two** connected
components, which reads exactly like a wing the lift is needed to reach — and
`triggerplatformlift` was unlowered.

Dumping B3F cell by cell says otherwise. Component 2 is the room: **150
`CAVE_FLOOR` cells and its three warps** — east, west and north. Component 1 is
**606 cells of behaviour `NONE`**, the map's unused surround. The room is
entered and left by warp and is walkable throughout, and `PlatformLift_Trigger`
moves a platform between two *floor heights* in the same room — a height
feature, in a port that walks without height.

**A component count is not a measurement; what the components contain is.** That
is the whole difference between this no-op and the Distortion World above, and
the same probe produced both numbers.

### Reading four unnamed commands one at a time, and why it mattered

A first pass had `18C`, `20D`, `2FB` and `2B6` as no-ops on the strength of
"they are Spear Pillar set-piece effects". Checking each definition exactly:

```
18C  GetVar localID, GetVar dir     -- writes nothing
2B6  GetVar localID, ReadByte       -- writes nothing
2FB  no operands at all             -- writes nothing
20D  ReadByte, then GetVarPointer   -- WRITES A VAR
```

The grep behind the first pass had landed on a **neighbouring function** for two
of them: `ScrCmd_2FB` reads nothing, but the lines printed under it belong to
`ScrCmd_CheckABPress`, which takes a var pointer. Anchoring the match on the
exact definition line separated them — and `20D` would otherwise have left its
five Spear Pillar sites branching on the previous command's answer.

### The corpus's single biggest gap, and two schemes that do not line up

`getpartymonribbon` was the **most common unlowered command in the entire
cartridge at 178 sites**. The port already has a ribbon store — but it is
Hoenn's: `mon.ribbons` keyed by name with rank counters, because that is what
the contest screen reads. A Gen 4 script addresses a ribbon by *number*.

Gen 4 ribbons are stored under their own numeric keys in the same table. They
round-trip exactly, they cannot collide with Hoenn's string keys, and
`Contest.ribbonCount` walks named keys only, so a Sinnoh ribbon does not
silently inflate a Hoenn count. What it does **not** do is appear on the ribbon
screen — that needs the id map, and inventing one would put the wrong picture on
the right Pokémon.

### The rest

| command | now | why |
|---|---|---|
| `getbattleresult` | the result mask | not the single won/lost bit the other two commands read; rebuilt from `ctx.lastBattleResult` rather than adding a fourth context field |
| `getgameversion` | 12 | counted off `versions.h`, which has three UNUSED holes in it |
| `getleaguevictories` | `#save.hallOfFame` | `record_hall_of_fame` already appends one entry per induction |
| `checkpartyhashelditem` | real | Mt. Coronet's summit asking for the Adamant or Lustrous Orb |
| `setspeciesseen` | real | Spear Pillar marks both legendaries seen before either is fought |
| `showobject` / `hideobject` | the port's show and hide | the *other* pair beside `addobject`/`removeobject`; simply never lowered |
| `startgiratinaoriginbattle` | the legendary battle path | same call shape, with a form this port does not model |
| `waitabpadpress` | no-op | Gen 3 lowers its own `waitbuttonpress` to nothing for the same reason: the text boxes already wait, so a second wait with no box is a hang |
| `pokemartseal` (35 sites) | refused, with the warning | indexes `SunyshoreMarketDailyStocks`, a second stock table that is not extracted — the same shape as `pokemartspecialties` |
| Sunyshore gym buttons | no-op | one of the three dynamic-height gyms; its floor reads as ordinary ground here |
| lake guardian containment, Giratina forms, hidden locations, subscenes | no-ops read individually | |

### What is left after eight chapters

- **Contests** — `buffercontestantmonname` in seven of eight chapters, plus
  `givepoffin`, `27C` and `openpokemonnamingscreen`.
- **The Distortion World floor** — the one hard blocker.
- **Dynamic-height gym floors** — Canalave, Pastoria, Sunyshore.
- A friendship counter; an ally-trainer battler; the Gen 4 ribbon id map.
- Three extractor stages waiting on one re-import.
- **Nothing has been played.** Every number here is offline.

---

## Correction: the Distortion World objects are its cast, not its platforms

The chapter-eight section above said `adddistortionworldmapobject` "does not
build anything — it spawns an object the map already carries", and lowered it
and its delete twin onto the port's existing show and hide. **That was wrong,
and it shipped for about twenty minutes.**

The check that settled it was to look at the map:

```
Distortion World 1F  (header 573, events member 524):  0 objects
Distortion World B1F (header 574, events member 0):    0 objects
```

The event table is **empty**. `AddMapObjectWithLocalID` walks `sMapObjectEvents`,
a table inside **overlay 9**, and the 42 ids in `constants/distortion_world.h`
start at `DIST_WORLD_MAP_OBJECT_BASE_LOCAL_ID = 128` and are named
`CYNTHIA_PORTAL`, `CYNTHIA_ELEVATOR`, `MESPRIT`, `CYRUS`, `UXIE`, `AZELF` and
the boulder-pit text triggers.

So those commands spawn the Distortion World's **cast**, from an overlay this
port does not extract — not its platforms. Pointing them at show/hide asks the
overworld for local id 128 on a map whose object list is empty; it finds nothing
and says so. They are no-ops now, and extracting `sMapObjectEvents` is the real
fix.

**What this does not change:** the floor measurement stands, and so does the
blocker. Distortion World 1F is 92 walkable cells on a 64×64 map in nine
disconnected pieces; B1F is 102 in twelve. What it changes is the *shape* of the
fix — the Distortion World needs two things, not one:

1. **its cast**, from `sMapObjectEvents` in overlay 9; and
2. **its floor**, which is a bespoke floating-platform system
   (`ov9_02249960.c` — `DistWorldBounds`, `sFloatingPlatformJumpPointHandlers`,
   per-platform avatar distortion states), not map collision and not objects.

The second is why it is still the one hard blocker on the main path.

### Why the wrong reading was plausible

`DistWorld_AddMapObjectWithLocalID` is a three-line wrapper that reads exactly
like the ordinary object commands, and the word "MapObject" in its name is the
cartridge's own. Reading the wrapper was not enough; the table it walks is one
call deeper, and the map it is supposed to be reading from was the thing to
check. **A command's name describes what it produces, not where it gets it.**

---

## Auditing what eight chapters of lowering actually do

The Distortion World correction was not a one-off kind of mistake: it came from
reading a wrapper and believing its name. Every command lowered this session was
written the same way — pret and the port side by side — so the same class of
error could be sitting in any of the forty-odd others.

Reading finds a misunderstood cartridge rule. It does not find a Lua scoping
error or a field spelled two ways. So: **`tools/gen4_command_audit.lua`** — run
every new command against the real Platinum cache with a fixture party, and
check that it runs *and* writes the var it promises.

**43 checks. Two real bugs on the first run, both mine, both from this session.**

### A crash in every TM message

```
g4_buffer  RAISED  Gen4Commands.lua:488: attempt to call a nil value (global 'itemKey')
```

`itemKey` is defined at line 531, with the bag commands, where it belongs.
`g4_buffer` is at line 342 and reaches up for it — in the `itemPlural` fallback
and in `tmhmMove`. **A file-local referenced above its `local function` line is
not that local at all**: Lua resolves the name as a global, finds nil, and the
call raises. The `tmhmMove` site hits it unconditionally, so every
`buffertmhmmovename` — including Gardenia handing over TM86 — would have thrown.

Fixed by declaring the local above `g4_buffer` and assigning to it below, so both
sites share one upvalue. Then the same scan over both files for the whole class:

```
Gen4Commands: itemKey defined 531, used 427 and 488   (the two above)
Gen4ScriptVM: none
```

Two sites, bounded, and the scan is the check that says so.

### A defensive default that was the harmful answer

`g4_pc_free_slots` wrapped its `require` in a `pcall` and fell back to **zero
free slots**. Zero is not "I could not tell" — it is "your boxes are full", and
it is the one answer that makes the Great Marsh gate turn the player away. The
careful-looking version was worse than no version.

`src.pokemon.Boxes` is a core module every generation loads, so a failure to
require it is a real fault and should be loud rather than quietly locking someone
out of the marsh. The `pcall` is gone. Verified: 12 boxes × 20 = **240**.

### The harness had to be taught to see a pass

The first run reported **25 commands as "NO VAR WRITTEN"** — and every one of
them was fine. The harness looked in `save.vars`; the port keeps script vars in
`save.gen4Vars`.

That is the familiar trap wearing the other face. A measurement that cannot fail
proves nothing; **a measurement that cannot pass condemns everything**, and it is
more tempting to believe because it looks like diligence finding problems. The
harness now asserts it can watch a var being written before it trusts a single
result, the same way the chapter walkers assert the newest lowering is loaded.

A second false alarm followed the same shape: `g4_pc_free_slots` still read 0
after the fix because I had replaced the harness's package path and the real
`Boxes` module was no longer reachable. In isolation the same code answered 240.
**Two of the four findings were the harness, not the code** — which is the ratio
to expect, and the reason each one gets confirmed in isolation before anything is
called a bug.

### What passed, with values worth checking by eye

| command | answered | why that is right |
|---|---|---|
| `g4_item_pocket(TM86)` | 3 | `TM_HM` is `fieldPocket` 3 |
| `g4_item_is_plate(298)` | 1 | Flame Plate opens the run |
| `g4_game_version` | 12 | `VERSION_PLATINUM`, holes counted |
| `g4_mon_types(Turtwig)` | 12 | grass |
| `g4_mon_friendship(Turtwig)` | 70 | its `baseFriendship`, no counter kept yet |
| `g4_selected_party_slot` | 255 | `PARTY_SLOT_NONE`, i.e. cancelled |
| `g4_mon_ev_total` | 10 | 4 HP + 6 Attack |
| `g4_party_count` / `non_eggs` | 2 / 1 | one of the two is an egg |
| `g4_get_battle_result` | 5 | the fixture caught it |
| `g4_did_not_capture` | 0 | …so it did not fail to |
| `g4_league_victories` | 2 | two Hall of Fame entries |
| `g4_pc_free_slots` | 240 | 12 boxes × 20, none used |
| `g4_buffer_map_name(3)` | "Jubilife City" | header 3's label |
| the six buffer banks | "TMs & HMs", "Master Balls", "CALCULATOR", "Yellow Fluff", "PC", "a {COLOR}TURTWIG{COLOR}" | each from the bank it claims |

A value being *produced* and a value being *right* are two claims, and a table
like this is the only place the second one gets tested.

### What the audit does not cover

It exercises each command once, against one fixture, in isolation. It does not
run a script, does not touch the battle or screen paths (`g4_start_battle`,
`g4_pokemart`, `g4_choose_starter` all push screens and block), and cannot see
anything that only goes wrong in sequence or on a real save. **It is a floor, not
a ceiling — and the floor was lower than reading suggested.**

---

## The lowering→dispatch seam, and a fade that never faded

The audit checked that each command runs. It did not check the seam *above* it:
a lowering that emits a verb name no handler answers to logs
`unknown command 'x' (skipped)` and the row silently does nothing — the exact
failure this file's own header warns about.

That is exhaustively checkable, so it now is. Lower **every block in the corpus**
and collect every verb emitted, then look each one up in the real `Commands`
table:

```
lowered the whole corpus: 84,519 rows, 150 distinct verbs
150 verbs have a handler, 0 DO NOT
```

(With a canary first, because a check against an empty table passes everything:
the run asserts the table actually holds both a `g4_` verb and a shared one
before it believes a single lookup.)

### Then argument counts, which is where the real bug was

A verb can exist and still be called wrongly. `debug.getinfo(fn, "u").nparams`
gives a Lua function's declared parameter count, so every emitted row can be
checked against the signature it calls. Most flagged rows were zero-parameter
handlers that ignore their arguments on purpose — stubs, waits, `label`. One was
not:

```
g4_fade   passes 2 arg(s), takes 1   x736 rows   [EXTRA DROPPED]
```

### `fadescreen` has four operands and the direction is the third

```c
ScrCmd_FadeScreen:  transition, frames, type, color
StartScreenFade(FADE_BOTH_SCREENS, type, type, color, transition, frames, ...)
StartScreenFade(mode,             typeMain, typeSub, color, steps, framesPerStep, ...)
```

So operand 1 is the **step count** and the direction is operand 3. The lowering
passed operands 1 and 2; the command read operand 1 and applied *Hoenn's* rule
("odd darkens"). Gen 4's `generated/fade_types.txt` alternates OUT then IN in
pairs — 0 `BRIGHTNESS_OUT`, 1 `BRIGHTNESS_IN`, 16 `CIRCLE_OUT`, 17 `CIRCLE_IN`,
40 `CLAMP_OUT`, 41 `CLAMP_IN` — so **even darkens and odd restores**, the
opposite convention, on a different operand.

Censusing all 736 reached sites makes the consequence exact:

| steps | framesPerStep | type | colour | sites |
|---|---|---|---|---|
| 6 | 1 | 1 | 0 | 355 |
| 6 | 1 | 0 | 0 | 336 |
| 6 | 3 | 0 | 0 | 14 |
| 6 | 3 | 1 | 0 | 10 |
| 6 | 6 | 0/1 | 32767 | 4 / 4 |
| 6 | 1 | 20 | 0 | 4 |

**Every site passes `steps = 6`.** Six is even, the old rule answered "in" for
all 736, and so *the fade to black before a warp or a cutscene never happened
anywhere in the game*. Against the cartridge's own `type` parity the old reading
was wrong on **362 of 736 — 49.2%**, which is what reading a constant instead of
a variable looks like: not random, just uniformly one answer.

Fixed, and the other two operands carried now that they are in hand: total length
is `steps × framesPerStep` (6, 18 or 36 frames across the corpus), and the colour
is BGR555 where the only values that occur are 0 (black) and 32767 = 0x7FFF
(white) — so the handful of white fades stop being black ones. Re-measured:
**736 of 736 agree, 0 wrong.**

**This one was not written this session** — `fadescreen` came in with the original
conversation set. It took three checks stacked on each other to surface: the
chapter walks said it was lowered, the command audit said it ran, and only the
arity comparison noticed that the lowering and the command disagreed about how
many operands there were.

### Expect this to be visible

Roughly half of 736 sites will now fade out where they previously did nothing.
That is the correct behaviour and it is a real change in what the screen does —
scenes that used to cut will now black out first, and `Commands.fade` yields
until the ramp finishes, so those scenes get slightly longer. If a cutscene looks
wrong after this, this is the change to look at first.

### What these two checks still do not cover

Verb exists, and the operand count matches. **Not** that the operands are in the
right ORDER — `g4_fade` would have passed an arity check happily while reading
`steps` as a direction, because one is one. Order is still only as good as the
reading, and `scrcmd_party.c`'s four party queries putting the destination first
on three of them and second on the fourth is the reminder of how little pattern
there is to lean on.

---

## The check underneath all the others: opcode widths against pret

Every coverage figure in this document, every reachability walk and every "this
command is lowered" claim rests on the decode being right — and the decode rests
on one number per opcode: how many bytes its operands take. Get one wrong and
every instruction after it in that block is garbage, silently, with no error, and
the garbage still counts as decoded.

That was taken on trust for the whole of this work. It is not any more.

**pret states the answer without meaning to.** A handler's operand list *is* the
sequence of primitives it calls, and each consumes a known width:

| primitive | bytes |
|---|---|
| `ScriptContext_ReadByte` | 1 |
| `ScriptContext_ReadHalfWord` | 2 |
| `ScriptContext_GetVar` | 2 |
| `ScriptContext_GetVarPointer` | 2 |
| `ScriptContext_ReadWord` | 4 |

`GetVar` and `GetVarPointer` are inlines in `include/inlines.h` that call
`ReadHalfWord`, which is why both are two — worth checking rather than assuming,
since a var *id* being two bytes is not obvious from the name.

So `tools/gen4_opcode_widths.py` extracts all 833 `ScrCmd_*` bodies, reads their
primitives in order, and compares against `Gen4ScriptOps`.

### 825 of 840 verified, 0 disagreements

The 30 that *did* disagree were **all** `ScrCmd_Unused_*`, all given zero operands
by this port where pret reads one to four:

```
0x004 unused_004  mine=''  pret='bb'      0x00A unused_00a  mine=''  pret='dd'
0x013 unused_013  mine=''  pret='w'       0x1E7 unused_1e7  mine=''  pret='wwwb'
...30 in total, every one an Unused_*
```

**And not one of them occurs anywhere in the corpus** — checked across all 78,093
reachable instructions. So the decode every measurement in this document relied
on was sound, and the fix was for a latent desync rather than a live one. Proof
that the edit was inert where it should be: after rewriting 30 table rows the
corpus figures are byte-identical — 8,567 blocks, 78,093 instructions, 97.35%,
2,066 unlowered.

### The heuristic that decided whether the check was any use

A read inside a loop or a conditional is not positionally fixed, so a linear
count of primitives is wrong for those and has to be excluded. The first version
excluded any body that *contained* a loop — which buried **54 opcodes that were
perfectly fine**, nearly all of them `count*` and `findpartyslotwith*` handlers
that read their operands once and then walk the party.

Tracking brace depth and asking whether each read sits inside a conditional
*block* took the uncomparable set from 56 down to 15. A check that excuses itself
too easily is only slightly better than no check: it would have reported "784
agree" while quietly declining to look at 54 live opcodes.

### The residual, named

15 opcodes are still not compared, 14 of which occur (28 instructions in total):

- **8 this port deliberately marks variable-length** — `dostrengthfunc`,
  `doflashfunc`, `dodefogfunc`, `dogroupconnectionaction`, `calltvbroadcast`,
  `calltvinterview`, `mysterygiftgive`, `givepoffin`. The decoder *stops* at
  these rather than guessing a width, which is why their blocks are only partly
  walked — safe, and visible in the numbers.
- **6 whose handler bodies are not in `src/`** (overlay or inlined):
  `checkforjubilifelotterywinner`, `27c`, `2b8`,
  `showmovetutormoveselectionmenu`, `closeshardcostwindow`,
  `savetvsegmentpokemonstoragebulletin` — 17 instructions between them, all side
  systems. **These six widths are the only ones in the table still taken on
  trust.**

### And the tool caught a stale copy on its first real run

Run against the staged tree immediately after committing the fix, it reported the
old 30 disagreements — because the staged copy predated the commit. Re-staging
gave 825/0. The check works, and it found the session's most repeated process
mistake one more time.

---

## Which operand is which: two dropped destinations

The previous three checks each stop one step short of the same question. The
chapter walks say an opcode is lowered. The command audit says the command runs
and writes its var. The seam check says the verb resolves and the operand *count*
matches. **None of them knows which operand is which** — and I wrote that gap down
twice without closing it.

pret closes it. `ScriptContext_GetVarPointer` reads a **destination**, a var the
command writes; `GetVar`, `ReadByte`, `ReadHalfWord` and `ReadWord` read inputs.
So a command's operand roles, in order, are the sequence of primitives its handler
calls — and that can be compared against the `ins.args[N]` indices the lowering
actually passes. `tools/gen4_operand_roles.py`.

**Destinations specifically, because a dropped input is usually deliberate** — a
no-op ignores everything, `goto` takes its offset from `ins.target` rather than
`args`. A dropped destination never is: the var goes unwritten and the `gotoif`
behind it branches on whatever the previous command left in the comparison
register.

### Two, and both are mine from this session

```
0x32B checkpartyhasfatefulencounterregigigas   operand 1 of 1 is a DESTINATION ['dest']
0x31C findpartyslotwithfatefulencounterspecies operand 1 of 2 is a DESTINATION ['dest','in']
```

Both lowerings passed `ins.args[2]`.

- `checkpartyhasfatefulencounterregigigas` takes **one** operand and it is the
  destination. Passing `args[2]` handed the command **nil**, so nothing was
  written at any of its **9 sites**.
- `findpartyslotwithfatefulencounterspecies` reads destination then species.
  Passing `args[2]` made the **species** the destination — so the port wrote its
  zero into a var id taken from an input. **That is worse than not writing:** it
  clobbers an unrelated var instead of merely failing.

Both are the "destination comes first" shape that `scrcmd_party.c`'s four party
queries already demonstrate — which is written up two sections above this one,
with a table, as the thing to watch for. I then walked into it twice anyway, on
the two commands whose names both contain "fatefulencounter". **Reading carefully
is not a substitute for a check that cannot be talked out of.**

Fixed; the checker now reports none, and the corpus is unchanged (8,567 blocks,
97.35%, chapters 3 and 3) because `g4_no_feature` writes a zero either way — which
is exactly why neither of these would ever have shown up in a coverage number.

### The five checks, and what each one alone would miss

| check | answers | would miss |
|---|---|---|
| chapter walks | is this opcode lowered at all? | a lowering that emits nonsense |
| `gen4_command_audit.lua` | does the command run and write? | a lowering that calls it wrongly |
| `gen4_seam_check.lua` | does the verb exist, with the right arity? | which operand is which |
| `gen4_operand_roles.py` | is every destination passed? | whether an *input* is in the right slot |
| `gen4_opcode_widths.py` | is the decode itself right? | everything above it |

The bug each one caught was invisible to all the others: a crash (`itemKey`), a
never-fading fade (`fadescreen`), and now two unwritten vars. That is the argument
for stacking them rather than picking the best one.

### Still not checked

**Input operand order.** `getpartymontype <type1Var> <type2Var> <slot>` would pass
every check above with its two destinations swapped, because both are
destinations; so would any command whose inputs are in the wrong order. The
remaining defence there is reading `scrcmd_*.c` operand by operand, which is
exactly the defence that failed twice today.

---

## Input operand order, after all — the names are a shared vocabulary

The previous section ended by calling input order unfixable: *"the only defence
there is reading `scrcmd_*.c` operand by operand, which is exactly the defence
that failed twice today."*

**That was wrong, and the way it was wrong is worth keeping.** pret's handler
assigns every read to a *named local*:

```c
u16 *destVar = ScriptContext_GetVarPointer(ctx);
u16 species  = ScriptContext_GetVar(ctx);
```

and this port's commands have named parameters. Compose the two through the
lowering's emit row — which `args[N]` lands in which parameter slot — and the
names either correspond or they do not. **1,037 of pret's 1,129 operands (91.9%)
carry a usable name.** `tools/gen4_operand_names.py`.

### The refinement that decided whether it was worth having

The first run reported **52 disagreements, and every single one was correct
code.** `g4_buffer(ctx, slot, kind, value)` serves about twenty opcodes, so its
parameters are deliberately non-specific, and comparing `"value"` against pret's
`"item"`, `"move"` and `"number"` is pure noise.

Excluding generically named parameters — and *counting* them rather than hiding
them — took 52 complaints down to **6**. This is the third time in this session
the same lesson has arrived: the width checker's loop heuristic buried 54 live
opcodes by being too cautious, this one buried its signal by being too eager.
**A check that cries wolf on a list nobody will read is not a check.**

### The six, all synonyms

| opcode | port | pret | verdict |
|---|---|---|---|
| `setplayerbike` | `on` | `rideBike` | same thing |
| `starttrainerbattle` | `enemy1`, `enemy2` | `enemyTrainer1/2` | same thing |
| `starttagbattle` | `enemy1`, `enemy2` | `enemyTrainer1/2` | same thing |
| `setposition` | `height` | `y` | correct — in Gen 4 **y is the vertical axis**, x and z are the ground plane |

**61 specifically-named operand pairs compared, 0 real disagreements.** A name
difference is evidence to read, not proof of a bug, so the tool exits clean and
prints what to look at.

### What it still does not reach

77 pairs are skipped because this port's parameter is generic. That is a design
choice rather than a defect — `g4_buffer` is deliberately one command for twenty
opcodes — but it does mean those twenty get no order check from this tool. For
them the discriminator is the per-opcode `kind` string in the emit row
(`"pocket"`, `"itemPlural"`, `"tmhmMove"`…), which was chosen individually and
read individually. And 43 lowerings are not comparable at all.

### Six checks

| check | answers |
|---|---|
| chapter walks | is the opcode lowered? |
| `gen4_command_audit.lua` | does the command run and write? |
| `gen4_seam_check.lua` | does the verb exist, with matching arity? |
| `gen4_operand_roles.py` | is every destination operand passed? |
| `gen4_operand_names.py` | are the inputs in the right order? |
| `gen4_opcode_widths.py` | is the decode itself right? |

Between them they found a crash, a fade that never faded, two unwritten vars and
thirty latent width errors — **and no two of those were catchable by the same
check.** Five of the six were built after the code they check was already written
and believed correct, which is the honest summary of how much reading is worth
on its own.

---

## The Distortion World, cracked: its floor is nine warp pairs

The one hard blocker of eight chapters. Every previous pass ended with the same
two sentences — *the Distortion World needs (1) its cast from `sMapObjectEvents`
in overlay 9 and (2) its floor, a bespoke floating-platform system in
`ov9_02249960.c`* — and treated (2) as the wall. It is not a wall. This pass
read both halves out of the cartridge and measured what they are.

### Where the floor actually lives

Every other Sinnoh map answers *can I stand here* from its `land_data`
permission grid. The Distortion World's grids are nearly empty, and that is the
design rather than corruption:

| map | floor | own non-void cells | of which water | components |
|-----|-------|-------------------|----------------|------------|
| 573 | 1F | 92 | 0 | 9 |
| 574 | B1F | 102 | 0 | 12 |
| 575 | B2F | 196 | 0 | 8 |
| 576 | B3F | 3,161 | 2,773 | 25 |
| 577 | B4F | 493 | 30 | 4 |
| 578 | — | 3,910 | 3,769 | 2 |
| 579 | B5F | 408 | 119 | 5 |
| 580 | B6F | 251 | 0 | 1 |
| 581 | B7F | 92 | 0 | 1 |
| 582 | Giratina room | 19 | 0 | 2 |
| 583 | Turnback Cave room | 272 | 0 | 16 |

The rest of the floor comes from two places, and **both are in the cartridge**:

* `/fielddata/tornworld/tw_arc.narc` and `tw_arc_attr.narc` — per-map floating
  platforms, their jump points, camera angles, and one 32×32 terrain-attribute
  grid per platform.
* **ARM9 overlay 9** — 41,856 bytes at `0x02249960`, *uncompressed* — the cast,
  the coordinate events, the moving platforms and the elevator paths.

### 578 IS NOT A FLOOR

Map headers 573..583 are eleven maps and the Distortion World has ten. 578
appears in **no** Distortion World table: not the map-info file, not the
connection list, not the events, not the cast. It is a spare with 3,910 cells,
almost all water. `header - 573` as an index therefore lands one floor out from
B5F onward, which is why every lookup in the new module searches. The check
asserts its absence rather than assuming it.

### A platform is a 32×32 grid glued to a plane

`tw_arc` member 0 is the map-info file: `int count` then 12-byte records of
`u32 mapHeaderID, u16 mapFileIndex, s16 offsetTileX, s16 offsetAltitude,
s16 offsetTileZ`. 4 + 12 × 10 = 124 = the member's length, exactly.

Member `mapFileIndex + 1` is that map's own file: a five-int header of **section
sizes**, then the sections in that order. 20 + the four sizes equals the member
length for all ten files, and 4 + recordBytes × count equals the section size in
all thirty non-empty sections — so the record widths are confirmed by
arithmetic, not read off one sample.

`kind` says which plane the grid lies in, and the attribute lookup is
`attr[vertical + horizontal * 32]`:

| kind | | vertical | horizontal |
|---|---|---|---|
| 0 | FLOOR | `x - startX` | `z - startZ` |
| 1 | WEST_WALL | `sizeY - (y - startY)` | `z - startZ` |
| 2 | EAST_WALL | `y - startY` | `z - startZ` |
| 3 | CEILING | `sizeX - (x - startX)` | `z - startZ` |
| 4 | INVALID | — a jump TARGET, never a platform | |

**All four share `horizontal = z - startZ`**, which is what lets one grid serve
four orientations; the two inverted kinds are inverted in the vertical axis
only. The attribute words have the same layout as a `land_data` permission word
— bit 15 collision, low byte behaviour — and the behaviours that occur are
0 NONE, 8 CAVE_FLOOR, 21 WATER_SEA and 90..93 JUMP_{NORTH,SOUTH,WEST,EAST}_TWICE.
**All ordinary Gen 4 behaviours.** The Distortion World needs no bespoke
behaviour table.

Totals: **10 platforms, 20 jump points, 26 camera angles, 12 attribute grids.**
Six grids are dense walls (874–1,011 passable of 1,024); four are the small 5×5
slabs of B2F; two are referenced by nothing.

### Five overlay tables, each found by its fingerprint

None of them is at a knowable offset, so each is found by the **exact set of
Distortion World maps it names**. The four sets are distinct, which is what makes
this identification rather than guessing:

| table | maps | site | rows |
|---|---|---|---|
| `sMapObjectEvents` (cast) | all ten | +0x09554 | 45 |
| `sMapEvents` | eight; Giratina room is **582** | +0x093D8 | 45 |
| `sMovingPlatformsMapTemplates` | eight; B6F is 580, no 582 | +0x092D8 | 34 |
| `sSimplePropsMapTemplates` | four: 1F, B5F, 582, 583 | +0x08BE8 | 4 |

A candidate is a run of 8-byte `{u32 mapHeaderID, u32 pointer}` records whose
pointers land inside the overlay's own RAM range. 37 individual pairs in the
overlay pass that test and there are exactly four runs. **A prefix match would
not do**: the ten-entry cast table and the eight-entry events table share their
first five ids, so the matcher also requires that the record *after* the run does
not continue it.

`sElevatorPlatformPaths[22]` is found a different way because it is an array of
values, not pointers: 32 bytes each, first field is the record's own index, so a
run of 22 records where `index == position` is the signature — then every
`nextIndex` must be a real path or the `INVALID` sentinel 22, and every flag a
real flag or *its* sentinel 11. Found at +0x09ED0.

### The result that matters: 18 of 34 moving platforms are warp pairs

The 34 moving platforms fall into exactly two groups, and the split is proved
rather than assumed. Follow each platform's elevator-path chain from its own
altitude; require a platform at the **same (x, z)** on the altitude it lands on
whose index equals this platform's `destIndex`.

**18 of 34 pass, and they form nine symmetric pairs:**

```
1F  <-> B1F  at (40, 54)      B3F <-> B4F  at (95, 70)
B1F <-> B2F  at (33, 45)      B3F <-> B5F  at (96, 43)
B2F <-> B3F  at (65, 31)      B4F <-> B5F  at (78, 77)
B3F <-> B4F  at (79, 62)      B5F <-> B6F  at (87, 67)
                              B6F <-> B7F  at (85, 86)
```

Altitudes: 1F 289, B1F 257, B2F 225, B3F 193, B4F 161, B5F 129, B6F 115, B7F 65.

**In a port with no vertical axis, a shuttle pair is a warp.** And it is a
*placeable* warp: subtract each floor's own offsets from the shuttle's world
coordinate and **all 18 ends land on a walkable cell of that floor's permission
grid — 14 of them on a tile explicitly marked CAVE_FLOOR**, which is the 5×5 pad
with an `8` at its centre that shows up in every floor's grid dump. The nine
pairs are the Distortion World's traversal spine and this port can build them
today.

The other **16 are all on B2F**: propKind 5 MEDIUM_MOVING_PLATFORM_1, persisted
flag INVALID, driven by that floor's own 24 coordinate events. 48 of the world's
111 event commands are `MOVE_PLATFORM` and **all 48 are B2F's**, each carrying a
±8 Z offset. That every non-pairing platform sits on one floor is the check that
says the two groups are real: were the pairing test merely failing, the failures
would be spread.

### Three traps, two of which I walked into

**`elevatorPathIndex` is meaningless on sixteen platforms and reads as valid.**
It is 0 on every B2F horizontal platform — and 0 is the *1F→B1F* elevator. Taking
it at face value for all 34 sends every B2F platform to a lift on another floor.
The fields that separate the groups are `propKind`, `persistedFlag`, and whether
the followed chain lands on a real floor altitude.

**`persistedFlag` is not part of a shuttle's identity.** My first classifier
required a real flag and reported **11 shuttles instead of 18**. The flag records
that a platform *has been moved* and **only one end of each pair owns it**; the
other end carries `DIST_WORLD_PLATFORM_FLAG_INVALID`. Requiring it drops exactly
one end of every pair — and calls half a working lift a horizontal platform. The
test is the pairing.

**A value array does not end where a pointer array does.** The simple-prop lists
terminate at `PROP_KIND_INVALID` (= `PROP_KIND_COUNT` = 25). My first reader
broke on "all fields zero" and ran off the end of each list into the next map's,
reporting **60 props instead of 4** — and every extra row looked like data
because the fields it read were plausible. The real answer is one portal on 1F,
one waterfall on B5F, one portal in the Giratina room, one in the Turnback Cave
room.

One arithmetic correction to the earlier notes: the cast is **45 members, not
42**, and the world's events are **45 events / 111 commands**.

### The negative result, recorded because it cost a plan

Before finding the shuttles I tested whether the 2-tile `JUMP_*_TWICE` ledges
reconnect the fragmented floors. Under both possible north/south conventions,
across all eleven maps: **not one component merged.** The landing cell two tiles
away is void at every one of those tiles. Then I tested the floating platforms
and jump points: 574 went 12 components → 11, 583 went 16 → 14, and **575 got
worse**, 8 → 13, because the platform cells it adds are themselves separate
islands. Platforms and jump points are the *wall-walking* half of the dungeon,
not the connector. The connector is the moving platforms, and that is why the
shuttle pairing was worth proving.

### Committed

* `src/import/Gen4DistWorld.lua` — both halves: the NARC (map infos, platforms,
  jump points, camera angles, attribute grids, the four-kind `attrAt` lookup) and
  overlay 9 (the five tables, found by fingerprint), plus `classify` which
  separates the shuttles from the B2F horizontals and proves each pair.
* `src/import/RomExtractorGen4.lua` — a `distortion` stage writing
  `gen4_distortion_world.lua`, last in the run because it joins to the rest of
  the cache only by map header id. Four edits, verified as four diff opcodes.
* `tools/gen4_distworld_check.lua` — **the seventh standing check**, and the
  first about a READ rather than a script. It exists because every number above
  is found by searching: **57 checks, 0 failures**, including the four
  fingerprint sites being distinct, the nine pairs being symmetric (a one-way
  lift is a softlock), and all 18 ends standing on real ground.

### Still open on the Distortion World

The nine warp pairs make the floors reachable; they do not finish the dungeon.
Remaining, now each with a known shape rather than a shrug:

* **Wall-walking.** Six dense attribute grids on five floors. In 2D these can be
  separate grids the player is warped onto at a jump point and off at its return
  — the 20 jump points carry the trigger box, the required facing, the
  displacement and the target platform, and the camera templates carry the view.
* **B2F's 16 horizontal platforms**, and the 24 events that drive them.
* **The 45 cast members** — the Cynthia/Cyrus/Uxie/Azelf/Mesprit line, spawned by
  `addmapobjectwithlocalid` from local id 128 up. Their coordinates and graphics
  ids are now extracted.
* **The B5F/B6F boulder puzzle**, which is 6 of the 45 events plus the three
  `SHOW_*_BOULDER_TUTO` commands.
* Nothing here has been played. Every figure above is offline.

---

## The nine lifts are wired: the Distortion World's floors now connect

The read is done; this is the wiring. And one measurement made it necessary
rather than merely useful.

### Measured over all 593 maps: there is no other way between the floors

| what | count |
|---|---|
| warp events in the whole Distortion World | **1** (1F → Turnback Cave `D05R0109`, anchor 2) |
| warps anywhere in Sinnoh that target a Distortion World map | **0** |
| its eleven maps sharing `zone_event` member 0, the empty one | **9** |

You do not walk between its floors and you do not open a door between them. You
are put on 1F by a script, and everything after that is the moving platforms.
So the nine shuttle pairs are not a convenience — without them the dungeon is
nine disconnected rooms, which is where a player stops.

(1F's single warp sits on a **void cell** at local (31, 53). That is the
cartridge's own data and nothing warps into it; the floor's real exit is the
`PROP_KIND_PORTAL` and the `CYNTHIA_PORTAL` cast member, which stands on a
walkable tile at local (34, 30).)

### The offset rule, confirmed twice more

A Distortion World world-coordinate becomes map-local by subtracting that
floor's own `offsetTileX` / `offsetTileZ` from the map-info file — **not** the
matrix origin, which is 0 for a dungeon matrix. Two independent confirmations
beyond the 18 shuttle ends:

* cast member 128 on 1F, world (55, 289, 40) → local (34, 30) — walkable
* cast member 129 on 1F, world (39, 289, 52) → local (18, 42) — walkable

### Where the wiring went, and why not in the extractor

`Data:seedDefaults`, Gen 4 branch — the same place the connection rename and the
new-game flag bridge live, for the same reason: the pairing is **derived**, so it
is recomputed from the extracted tables on every boot and lands without a
re-import of anything but the Distortion World stage itself.

**Nothing is written down in the engine.** Every coordinate comes from
`gen4_distortion_world`, which is now registered in `GEN4_PREFIXED` so
`Data:load` actually puts it on the table. A cache imported before that stage
existed has no such record, and then the arm logs one line and leaves the floors
alone — cartridge data does not belong in the engine, and the licence says so.

Three things the arm has to get right, each of them a real failure mode:

* **Two passes.** A warp's anchor is an index into the *destination* map's warp
  list, and on the first pass half of those warps do not exist yet. Pass one
  places the eighteen and remembers each slot; pass two joins each end to its
  partner.
* **Idempotent.** `seedDefaults` runs again after the mod merge. Without a guard
  the eighteen are appended twice, and `Map:new` keys `warpAt` by coordinate — so
  the duplicate silently wins or loses by table order. The arm bails if any def
  already carries a `distortionLift` warp.
* **A one-way lift is a softlock**, so an end with no partner is *removed* rather
  than shipped with a guessed anchor, highest slot first so the removal does not
  shift the next one, and the remaining indices are renumbered. The extractor's
  own check says there are none; this is what happens if a different build
  disagrees.

Both `pairs` walks are sorted before use, because the slot numbers this writes
are the anchors a save will carry.

### The behaviour it produces, checked against the engine's own rules

* A Gen 4 tileset sets `warpsAreEvents`, and for a non-FireRed Gen 4 cache
  `Map:isDoorTileCell` reduces to `warpAtCell(...) ~= nil` — so a lift pad fires
  **on the completed step onto it**, which is what standing on a platform should
  do.
* `OverworldState:refreshStandingOnWarp` plus the `if entry then -- still
  standing on the warp we arrived through` branch means the arrival tile does not
  re-fire, so a pair cannot bounce the player back and forth. Stepping off and
  back on takes the lift again, which is correct.
* `Warp.onArrive` returns `dw.x, dw.y` — the partner lift's own cell, which is
  one of the 18 verified-walkable pads.

### Proved offline, and the probe cannot drift from the code

The probe **slices the shipped block straight out of `Data.lua`** by its comment
markers and `load`s it, rather than restating the logic — so it tests what was
committed, not a copy of it. It builds the record from the ROM the way the stage
does, builds the eleven map defs with their real permission grids, and runs the
block **twice**:

```
record: 10 maps, 18 shuttles
sliced 6371 bytes of the shipped block
  ok  lift warps placed (after TWO seedDefaults runs)   18
  ok  lifts whose destWarp resolves to another lift     18
  ok  lifts whose partner points back at them          18
  ok  lifts standing on a walkable cell                18
  ok  lifts sharing a cell with another warp            0
  ok  warps whose index is not its slot                 0
  log: gen4 distortion world: 18 lift(s) wired as warps across 9 floor pairs
       -- the only route between its floors
6 checks, 0 failures
```

The cell-clash check is there because `Map:new` builds `warpAt` keyed by
coordinate: a lift landing on an existing warp's tile would not error, it would
quietly replace it. On 1F the real warp is at (31, 53) and the lift at (19, 44),
so nothing collides — but that is a fact about this cartridge, not a guarantee,
which is why it is a check.

### Committed

* `src/core/Data.lua` — `gen4_distortion_world` added to `GEN4_PREFIXED`, and the
  lift-wiring arm at the end of the Gen 4 `seedDefaults` branch. Two edits,
  verified as two diff opcodes.

### What this does and does not do

It connects the nine floor pairs, which is the traversal spine. It does not give
the Distortion World its wall-walking, B2F's sixteen horizontal platforms, its 45
cast members or the boulder puzzle. **And the lifts are instant warps, not the
cartridge's rising platform** — there is no animation, no camera move and no
sound, because this port has no Gen 4 SE bank at all. A player will arrive on the
next floor correctly and without ceremony.

Still offline: nothing here has been played. The lifts need a re-import to exist
at all, since the extractor stage that writes their coordinates is new this
session.

---

## The first real play report on Sinnoh, measured

Everything before this was offline. Cedric played it and reported five things:
the world does not look 2.5D; he reached the next town with no starter; the
Twinleaf guitarist stands in the wrong place and pushes him back repeatedly;
Barry does not follow him out of Twinleaf; and at the lake there is no Rowan and
no Dawn. The log and the cache answer some of it outright, correct one of the
expectations, and narrow the rest to a single missing number.

### First, the cache is not the problem

`gen4_terrain.lua` (3.7 MB) and `gen4_models.lua` (8.6 MB) are both in the live
cache, imported 17 hours before this session. Two things in it ARE stale and the
log says so itself — the tileset-animation stage ("no water, waterfall or flower
bed will move until the ROM is imported again") and, now, the Distortion World
stage. Neither is why the world looks flat.

### Rowan, Dawn and the briefcase are on Route 201, not at the lake

Lake Verity's map (`L01`) carries **exactly one object in the cartridge, a
signpost**. The whole opening cast is on **Route 201**:

| object | localId | cell | hide flag |
|---|---|---|---|
| Barry | 2 | (16,23) | `FLAG_G4_0172` |
| Prof. Rowan | 5 | (9,21) | `FLAG_G4_0178` |
| the counterpart (Dawn/Lucas) | 6 | (9,21) | `FLAG_G4_0179` |
| the briefcase | 12 | (16,22) | `FLAG_G4_017D` |

All four start hidden — they are among the 112 flags the new-game script sets —
and Route 201's own script is what reveals them: `clearflag 376` (0x178, Rowan)
followed by `addobject 5`. So "no Rowan or Dawn at the lake" is the right
observation about the wrong map; the scene that produces them is on Route 201
and it is not completing.

### Why there is no starter: one branch that never fires

Route 201's opening is coord row 1, gated on `VAR 0x4086 == 0`. The log:

```
gen4 coord: R201 (15,25) row 1 fired (var 16518 == 0)
   push TextBox / pop TextBox
gen4 coord: R201 (15,25) row 1 fired (var 16518 == 0)
   push TextBox / pop TextBox
gen4 coord: R201 (19,21) row 5 declined -- var 16518 is 0, wants 3
```

It fires, shows **one** message, and stops. Rows 3 and 5 want the var at 3, so
nothing downstream ever runs — and nothing else gates the walk to Sandgem, which
is why Cedric reached the next town with no Pokémon.

The script says exactly where it gives up:

```
0073  lockall
0075  applymovement 2, 1512        -- Barry
007D  waitmovement
007F  message 0                    <- the one TextBox in the log
0084  getplayermappos 0x8004, 0x8005
008A  comparevartovalue 0x8004, 110 / gotoif
0097  comparevartovalue 0x8004, 111 / gotoif
00A4  comparevartovalue 0x8004, 112 / gotoif
00B1  comparevartovalue 0x8004, 113 / gotoif
00BE  end                          <- and it lands here
```

**Every branch of the scene is behind a comparison on the player's matrix x**,
and there is no fallthrough: miss all four and the script simply ends, the var
stays 0, and the trigger fires again on the next step. Twinleaf's guitarist is
the same shape with eight branches — except his script DOES have a fallthrough,
which is why he plays a scene at all, and why the scene he plays is the one
written for a player standing somewhere else.

**The arithmetic itself is not the bug, and that was worth proving rather than
assuming.** Run offline against the real command module:

```
player local (15,25) + origin (96,832) -> 0x8004 = 111, 0x8005 = 857
compare 0x8004 (=111) vs 110 -> g4Compare=2  lastCheck=false
compare 0x8004 (=111) vs 111 -> g4Compare=1  lastCheck=true   <- matches
```

111 is inside the script's 110..113, the compare returns "equal", and all 15
instructions in the block lower. So the conversion, the compare and the lowering
are all correct in isolation, and the failure is somewhere between them at
runtime. Rather than guess further, the two lines that would have answered it in
one play session are now in the code (below).

### Three things measured about the live game

**Objects: 2,634 of 3,555 face the wrong way.** `NPC.new` picks a facing with

```lua
self.facing = (g3 and g3.facing) or FACING_FROM_RANGE[objDef.range] or "down"
```

`g3` is **Hoenn's** movement-type table, and a Platinum cache has no
`constants.gen3MovementTypes` at all — checked: the cache's constants carry 18
keys and that is not one of them. `range` is nil too, because a Gen 4 template
spells its wander box `movementRangeX`/`movementRangeZ`. So every object in
Sinnoh fell through to `"down"`.

The answer was already on the def. `ObjectEvent.dir` is a `FaceDirection`
(`include/location.h`: **FACE_UP 0, FACE_DOWN 1, FACE_LEFT 2, FACE_RIGHT 3**) —
the same four-value order `Gen4Movement.DIR` already uses. Censused over all
3,555 object events, and the census is what says it is an enum rather than a
number: **exactly four values occur — 1,836 up, 921 down, 415 left, 383 right**,
and nothing else. So 74% of Sinnoh's cast stood facing the wrong way, including
every shopkeeper behind a counter and the guitarist who is meant to be watching
Twinleaf's north exit. Fixed, Gen 4 only by construction: `direction` is written
by `RomExtractorGen4` and by no other extractor.

**The guitarist's scene, decoded.** His approach movement (729) is `spot up,
emote, wait, wait` — **net displacement zero**; he turns and shows a "!". Then
one of eight lists walks him to the player's own column on row 3, each with
`dy -2`, while the player gets movement 424 — `wait ×6, lock facing, walk down
×1, unlock, spot up`, **one tile south**. The log has him at cell (13,0) and the
player five tiles south of the trigger, so neither of those is what ran. His
template says (12,5) in both the cartridge and the cache, so it is the walk and
not the placement.

**Every land chunk has a mesh, and the routes are not flat.** 666 of 666 chunks
carry geometry; **279 carry no prop models at all**, and Route 201's chunks 4 and
6 are two of them — so `gen4 ground: chunk 4 baked 0 building(s)` in the log is
correct data, not a failure. Their trees and cliffs are in the chunk mesh itself.

Unpacking the meshes and measuring their vertical extent — a number nobody had
taken, because the earlier 527-of-590 measurement was for *building* models
only:

| chunk | | posScale | rise (units) | rise × scale | ≈ tiles |
|---|---|---|---|---|---|
| 4 | Route 201 | 64 | 0.66 | 42.2 | 2.6 |
| 6 | Route 201/202 | 64 | 0.66 | 42.2 | 2.6 |
| 0 | Twinleaf | 64 | 1.16 | 74.2 | 4.6 |
| 540 | the lake area | 64 | 1.66 | 106.2 | 6.6 |
| 225 | Canalave gym | 128 | 6.25 | 800 | 50 |

**The route geometry has two to seven tiles of real height in it.** And the
projection is not flat either: `Gen4Ground:applyCamera` builds the view from the
map's own pitch and the log confirms it — `59.05 deg, ground x0.858, height
x0.514`. 106 world units of rise at that camera is **54 screen pixels**, which is
more than the 45.6 px a Twinleaf house was measured to rise.

So the geometry has height and the projection applies height, and the picture is
still flat. That reduces "add 2.5D rendering" — or routing Sinnoh through the Gen
3 diorama renderer, which builds voxels from tiles and would be a step *down*
from meshes that already exist — to one narrow question: **where does a measured
42 to 106 units of mesh rise become zero on the way to the screen?** That is the
next thing to measure, and it is a much smaller job than it looked.

### Committed

* `src/world/NPC.lua` — a Gen 4 object takes its facing from its own
  `direction`. One edit, verified as one diff opcode.
* `src/script/Gen4Commands.lua` — two diagnostics, both for faults that are
  currently *silent*:
  * `g4_player_pos` now logs the map, the local cell, the origin and the matrix
    answer. Half of Sinnoh's cutscenes are `getplayermappos` followed by six or
    eight comparisons on the result, and all of them failing is indistinguishable
    from the scene not being implemented.
  * `g4_move` now logs who is walking, from which cell, how many steps and the
    net displacement — so a walk that ends in the wrong place separates "the list
    was read wrong" from "the walker was not where the cartridge thought". It
    also warns once per map when the cache carries no movement list at all, which
    on a stale cache silently replaces all 3,025 scripted walks with a turn.

All seven standing checks still pass: 150/0 verbs, 43/0 audit, no dropped
destinations, 61 operand pairs with 6 synonyms, 825/0 widths, 57/0 Distortion
World.

---

## Every branch in Platinum was being deleted at compile time

The play report's symptoms — no starter, the guitarist in the wrong place,
Barry not following, no Rowan or Dawn — are one bug, and it is one line.

### What it is

`Gen4ScriptVM` resolves a branch target to a label and looks it up in the
script pool:

```lua
local function labelFor(instruction)
  local t = instruction.target
  if type(t) ~= "number" then return nil end
  return ("S%04X"):format(t)            -- "S00C0"
end
```

The pool is keyed by `Gen4ScriptVM.label(member, at)` — **`"M0427/S00C0"`** —
because a script file is one member of `scr_seq` and an offset means nothing
without one. So `s.has(label)` was **false for every branch in the cartridge**,
`branch()` answered nil, and `goto`, `gotoif`, `call` and `callif` each emitted
**nothing at all**.

### Measured, over all 8,567 blocks, compiling each one before and after

| | rows | jump/call rows | labels |
|---|---|---|---|
| before | 63,629 | 6,385 | **0** |
| after | 599,532 | 169,017 | 74,825 |

**Zero labels is the tell.** Not one branch target was emitted anywhere in
Platinum, and the 6,385 surviving jump rows are all `jump end` — the one
control-flow lowering that does not go through `branch`, because its label is
the literal string `"end"`. The only control flow the game had was *stop*.

Route 201's opening, compiled, before and after:

```
before, 11 rows                        after, 236 rows
  g4_lock_all                            g4_lock_all
  g4_move            2, {2 steps}        g4_move            2, {2 steps}
  g4_wait_move                           g4_wait_move
  g4_message         0                   g4_message         0
  g4_close_message                       g4_close_message
  g4_player_pos      0x8004, 0x8005      g4_player_pos      0x8004, 0x8005
  g4_compare_var_value 0x8004, 110       g4_compare_var_value 0x8004, 110
  g4_compare_var_value 0x8004, 111       g4_jump_if         1, M0427/S00C0
  g4_compare_var_value 0x8004, 112       g4_compare_var_value 0x8004, 111
  g4_compare_var_value 0x8004, 113       g4_jump_if         1, M0427/S00EC
  jump               end                 ... and 226 more, every branch block
                                             emitted with its label
```

Four comparisons in a row with nothing between them, then stop. That is exactly
what the log showed: the trigger fires, one text box, the var never advances,
and the player walks over it again on the next step.

### Why all seven checks were blind to it

`g4_jump_if` resolves to a handler. Its arity matches. Its operands are the
right ones in the right order. Its width agrees with pret. The opcode counts as
lowered, so coverage says 97.35% — and it *was* lowered. **Every one of those
questions is about a row that was emitted.** None of them can see a row the
lowering decided not to emit.

Run after the fix, the seven report *identical* numbers to before it: 1/4/3/7/3/3/3/3,
97.35%, 43/0, 150/0, none, 61 pairs with 6 synonyms, 825/0, 57/0. That is the
argument for the eighth.

### And a second, smaller one it found

With the labels right, the new check reported **878 jumps to a label that was
never emitted** — every one of them a block jumping to *itself*. The compile
loop skipped the entry block's own label:

```lua
if label ~= entry then emit(state, { "label", label }) end
```

on the reading that execution starts there anyway. True, and beside the point:
`ScriptRunner.scanLabels` only treats a row as a jump target if it is a `label`
row, so a script that loops back to its own first block had nowhere to land.
878 sites in the cartridge do exactly that. A `label` row costs one row of
storage and is skipped at execution, so every block now emits its own.

### tools/gen4_branch_check.lua — the eighth check

It asks the one question the other seven cannot: **does a jump land anywhere.**
Four rules, each a different way for control flow to be quietly absent rather
than wrong:

1. every emitted jump target is an emitted label (a jump to a missing label runs
   off the end of the row list, which stops the script exactly like a
   successful `end`);
2. every block whose own instructions branch compiles to at least one branch row
   — this is what catches a whole class going missing, because rule 1 passes
   trivially when there are no jumps at all;
3. no block compiles to a single unconditional stop when its instructions say
   otherwise;
4. the corpus totals, stated as numbers, so a change of method cannot be read as
   a change of code.

It builds the pool exactly as `RomExtractorGen4:extractScripts` does — entry
points and every block a jump reaches — and canaries the harness first, because
a pool that came out empty would pass all four by having nothing to test. That
trap has already been paid for once, when the command audit read the wrong var
store.

**6 checks, 0 failures.**

### What this does not fix

The compiled rows are right now; nothing here has been played. In particular the
guitarist's walk was measured from the ROM as ending two tiles north of his post
and the log had him five, so there may still be something wrong in the executor
— but with his eight branches restored he will at least be running the scene
written for where the player is standing, which he never was before.

The cache does not need re-importing for this: the pool it already holds is
keyed correctly, and it was the lookup that was wrong.

### Committed

* `src/script/Gen4ScriptVM.lua` — the branch label carries its member, and every
  block emits its own label. Four diff opcodes.
* `tools/gen4_branch_check.lua` — the eighth standing check.
