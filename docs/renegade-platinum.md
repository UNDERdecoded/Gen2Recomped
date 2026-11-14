# Renegade Platinum

Drayano's **Renegade Platinum** is a ROM hack of Pokemon Platinum (USA) Rev 1.
It imports as its own version, `renegadeplatinum`. It has its own cache
(`renegadeplatinum/`), its own saves (`save_renegadeplatinum.lua`) and its own
launcher card ("RP", under *Pokemon ROM hacks*). It runs on the Platinum
engine: `GameVersion.family("renegadeplatinum") == "platinum"`, and
`GameVersion.isPlatinumFamily()` is what Platinum-only paths check.

Stage: **PRE-ALPHA**, the same as Platinum. It imports, boots to the field
and fights battles, but nobody has played it through.

## The accepted file

| | |
|---|---|
| SHA-1 | `381f9eef44564602a5f6469ee8c390fbb8ebac3a` |
| Size | 104,922,516 bytes (trimmed) |
| Header | `POKEMON PL`, game code `CPUE`, revision 1 (the base cartridge's) |
| Base | Platinum (USA) Rev 1, `0862ec35b24de5c7e2dcb88c9eea0873110d755c` |

The header is the retail one, so the hack can only be told apart by its hash.
A different build of the hack has a different hash. The launcher then
describes it as a modified Platinum dump, and it does not import.

## What the hack changes, measured against Platinum Rev 1

Filesystem: the paths are all the same. One DP leftover,
`/poketool/personal/personal.narc`, is gone, and nothing reads it. The
archives that differ:

| Archive | Change | Handled by |
|---|---|---|
| `pl_personal.narc` | 507 of 508 records (stats, types, abilities) | the species stage, unchanged |
| `wotbl.narc`, `evo.narc` | learnsets (503), evolutions (40) | unchanged |
| `pl_waza_tbl.narc` | 117 moves (type, power, new Fairy moves in old slots) | unchanged |
| `pl_item_data.narc` | 108 items | unchanged |
| `pl_enc_data.narc` | 118 of 183 encounter tables | unchanged |
| `trdata.narc` / `trpoke.narc` | 928 -> **1066** trainers, 698 parties rewritten | already sized by the archive; `constants.trainerOrder` now is too |
| `scr_seq.narc`, `zone_event.narc` | 215 scripts, 163 event files | unchanged (no new script commands: the ARM9 command table is untouched) |
| `pl_msg.narc` | 222 banks, trainer names 928 -> 1201 | unchanged |
| `pl_poke_icon.narc` | 539 icons redrawn | see *Icon palettes* |
| `pl_batt_obj.narc` | `type_icons/mystery` redrawn as FAIRY, `type_icons/shared.NCLR` | see *Fairy* |
| `zukan.narc` | a 19th Pokedex type icon | see *Fairy* |

Code: the ARM9 differs in 266 bytes, and overlays 11, 16, 21 and 73 differ.
No overlay was added and none changed its load address.

## Fairy

Renegade turns the unused `???` type (slot 9) into **FAIRY**. Everything the
extractor reads agrees on that:

- The type-name bank (624) says `FAIRY` at 9. `Gen4Versions.TYPE_SLOTS`
  renames slot 9 in `Gen4TypeChart.TYPES` for this version. Species types,
  move types and the chart's matchups are therefore written as `"FAIRY"`, not
  as `"MYSTERY"` (Gen4Damage treats `MYSTERY` as typeless and deals it no
  damage).
- 20 species carry the type: the Clefairy, Jigglypuff, Togepi, Marill,
  Snubbull and Ralts lines, Mr. Mime, Mime Jr. and Mawile. 8 moves carry it:
  Play Rough, Draining Kiss, Sweet Kiss, Charm, Moonlight, Dazzling Gleam,
  Disarming Voice and Moonblast.
- **The chart moved.** Overlay 16 still holds Platinum's 110-row chart, but
  every literal that pointed at it (`0x0226ECD4/5/6`) now points at
  `0x021E9F80/1/2`. That address is a dense 18x18 chart, Fairy row and
  column included, which the hack appended to overlay 21. The chart also has
  Gen 6's Steel changes, so Ghost and Dark now hit Steel neutrally.
  `Gen4TypeChart.follow` handles this generically. If the overlay no longer
  references the chart `find` located, it resolves the `X, X+1, X+2` literal
  triple, parses there (1x rows allowed) and drops the neutral rows. On
  retail cartridges the pointer is still present, so nothing changes.
- Icons: the battle and summary extractors also save the slot-9 member under
  the slot's name (`type_icons_fairy`, `type_fairy`). The Pokedex maps FAIRY
  to the hack's new 19th type-icon sequence (18), as the hack's overlay 21
  switch does.
- Move buttons: overlay 11's `sMovePaletteTable` entry for slot 9 is
  re-coloured. It is read by type id, so Fairy moves get the hack's colours
  without any code change.
- The AI: `Gen4AI.TYPE.FAIRY = 9` resolves the chart's names to ids.
  Hidden Power still skips slot 9. The hack changes nothing in overlay 16
  except the chart pointers, so its Hidden Power can never be Fairy either.

Verified in the battle harness: Moonblast against Dragonair is "super
effective", and Dragon Pulse against Clefairy "doesn't affect" it.

## Other ARM9 / overlay changes and how each is handled

| Where | What | Status |
|---|---|---|
| ARM9 `0x02075E5x` | `Pokemon_IsPersonalityShiny` compares against 128, not 8 (1/512) | extracted as `constants.shinyUnder` (found by its instruction run); `Stats.setShinyUnder` applies it |
| ARM9 `sPokemonIconPaletteIndex` | 86 icon palette assignments changed for the new icon art | `Gen4Icons.VERIFIED_BY_VERSION.renegadeplatinum`: the table is where Platinum keeps it, and 11 of the 14 anchors still hold |
| ARM9 `sGameCornerPrizeData` | the first prize (Silk Scarf) replaced; others re-priced | `Gen4GameCorner.SIGNATURE_ROW1` finds the table by rows 1..3 |
| ARM9 TM/HM table | several TMs changed | already found by its HM tail |
| ARM9 mart tables | Veilstone floors restocked | already found by shape (`martSpecialties`) |
| ARM9 map headers | flags / weather bytes on some maps | read at import, as before |
| Overlay 16 | the chart pointers, nothing else | handled (above) |
| Overlay 21 | the appended chart, the Pokedex type-icon switch | handled (above) |
| Overlay 11 | the Fairy move-button palette | read by type id |
| Overlay 73 | two literals change species 427 (Buneary) to 133 (Eevee) | **not handled**: probably Amity Square's walking partners; `PtMiscCommands.AMITY_POOL_OF` is still Platinum's list |

## Not verified yet

- Nothing has been played past the first battles. Scripts, events and the
  1066 trainers import, and the overworld harness boots Twinleaf. The
  hack's own story edits (rewritten scripts and new trainers 928..1065)
  have not been walked.
- Overlay 73 (above).
- Trainer dialogue: `trtblofs` was not extended. Trainers 928..1065 have no
  dialogue records, and the hack's scripts may give them lines another way.
- Data that is not read from these tables was not checked against the hack.
  This covers hardcoded vanilla tables in the engine, for example the Battle
  Hall's type grid, which still has no slot-9 column.

## Checking it

```
POKEPORT_IDENTITY=pl_rp POKEPORT_VERSION=renegadeplatinum \
  POKEPORT_IMPORT_ROM=<renegade_platinum.nds> POKEPORT_IMPORT_ONLY=1 \
  POKEPORT_NO_BOOT_REPORT=1 lovec .
INSTALL=<cache>/renegadeplatinum VERSION=renegadeplatinum MAP=T01 \
  lovec tools/gen4_hgss_overworld_harness
POKEPORT_DATA_DIR=<cache>/renegadeplatinum/data/generated \
  POKEPORT_ASSET_ROOT=<cache>/renegadeplatinum VERSION=renegadeplatinum \
  SPECIES=148 LEVEL=30 PARTY=282 PARTYLEVEL=50 SLOT=2 TICKS=1500 PRESS=15 \
  MSGTRACE=1 lovec tools/gen4_battle_harness
python tools/run_lua_check.py tools/rom_revisions_check.lua
```

The battle harness's `SLOT=n` keeps the cursor on move *n*, so a chosen
matchup can be fought.

A Platinum USA import made with these changes is byte-identical to one made
without them, apart from the new `constants.shinyUnder = 8`.
