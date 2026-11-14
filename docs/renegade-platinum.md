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
| Overlay 73 | two literals change species 427 (Buneary) to 133 (Eevee) | the opening's own Pokemon (Rowan's Poke Ball), NOT Amity Square: `Gen4IntroScene.monSpecies` reads it into `gen4_intro.monSpecies` (written only when it is not Buneary) |

## Trainers past the offset table

The hack grows trdata to 1,066 trainers and rewrites 136 `trtbl` records IN
PLACE (blank placeholder lines of dummy trainers become real lines, retagged
with ids 928..1065), but `trtblofs` keeps its 928 entries (the file is
byte-identical to Platinum's). The cartridge's walk reads the offset of
trainer 928 from past the end of that file (zero padding), starts at record 0
and stops at once, so by the letter of the walk those trainers are silent.
`Gen4TrainerMessages.all` therefore also scans the table for the runs of ids
PAST the offset table (`scanUncovered`; records of one trainer are
contiguous). A retail cartridge has no such ids and is unchanged. 135
trainers get lines (e.g. the counterpart's Route 202 battle, trainers
928..933: "Wow! You're that strong already?"). A trainer with no line has no
row: `g4_print_trainer_dialogue` returns without printing, so neither a script
nor a battle end waits on it. It is not known whether the real hack shows
these lines (it reads the same padding); the cache carries what the hack
authored.

## Other differences the survey found

- Route 202: the catching tutorial (`startcatchingtutorial`) is gone. The
  coordinate trigger runs a real trainer battle against the counterpart
  (trainers 928..933, level 9 against a level-5 starter), so a lone starter
  loses and blacks out. The playthrough beat trains the lead up first.
- Jubilife: the Pokétch clowns' quizzes are removed (persons 24 and 25 are
  parked at 0,0 without a script); the president gives the Pokétch himself.

## The story, as the hack changes it

All of these are script and event-data edits; the port runs them with no
engine change. `tools/gen4_playthrough/platinum.lua` walks each one when
`VERSION=renegadeplatinum` (retail's beats are untouched).

- Sandgem: Rowan's first lab scene enables the **National Dex** at once
  (`getsetnationaldexenabled 1`), so Mom's post-game scene takes its National
  Dex branch (flag 0x15C, not 0x15D).
- Floaroma Meadow: the two grunts are one double battle (296 + 297) that
  checks `getpartycount` and pushes a party of one back.
- Pastoria: the Gym Guide (person 29, flag 0xA08) stands on Barry's coord
  cell in front of the gym; Crasher Wake sings on Route 212 south (R212B
  coord (10..13,5), 0x406E): meeting him sets 0xA08 and clears the way.
- Route 218 gate: the Pokédex-upgrade scientist is gone; a thirsty
  policeman's coord trigger ((2,5..9), 0x406C) turns the player back unless
  the bag holds the **Tea** (item 456, the old S.S. Ticket slot). The Tea is
  Pal Park's: talk to Prof. Oak (flag 0xA0B), then Darach battles the player
  (trainer 969) and Caitlin hands it over (flag 0xA0C).
- Iron Island: Riley at the entrance battles the player (trainer 970);
  HM04 Strength comes after his tag battle inside (D24R0105, 0x4092 = 2).
- Mt. Coronet 2F, Victory Road 2F and Stark Mountain's second room: the
  Strength boulders and Rock Smash rocks are parked at (999,999).
- Victory Road 1F: a collector and a coord trigger ((37..39,18), 0x403E)
  hold the way north until the counterpart is beaten on **Route 224**, which
  is open before the League (talk twice, battle 975..977 by starter; flag
  0xA12). The hack also puts two nurses inside Victory Road.
- Route 227: Buck moved to (22,1); his trigger ((22,2..4), 0x403D) wants the
  six **Battle Zone leaders**' unofficial badges first (Heather R225 0x8C9,
  Wyver W226 0x8CA, Slythe R227 0x8CB, Shade R228 0x908, Gene R229 0x909,
  Luna W230 0x8CE), then he battles (trainer 1023) and leaves (flag 0xA18).
  Retail's patrol question (0x4119) is unreferenced.
- Battleground: the room holds the gym leaders; its frame table sets
  FLAG_TALKED_TO_BATTLEGROUND_BUCK (0x125) as the player walks in.
- Trainers are much stronger throughout (full level-appropriate teams with
  coverage, e.g. Volkner's two Rotom, Jupiter's Sableye).
- Evolutions: 40 records change (trade evolutions gain a level, Eevee uses
  Sun/Moon/Ice/Leaf stones, and about a dozen trade-with-item species can also evolve by
  using the item, whose records the hack flags as party items); the cache
  matches the cartridge's `evo.narc` record for record, and
  `Gen45Evolution.itemTarget` evolves Poliwhirl with King's Rock, Rhydon with
  the Protector, Eevee with the Sun/Moon/Ice/Leaf stone.
- Amity Square's accessory pools are ARM9 data (six 10-entry u16 pools at
  `0x020EBF84` on Platinum) and are byte-identical in the hack, so the
  hard-coded `PtMiscCommands.AMITY_POOLS` is right for both.
- Type logic that lives in code the hack leaves alone behaves as retail: the
  Battle Hall's grid and opponent-type table (overlay 104 is identical),
  Hidden Power (never Fairy), Judgment / Natural Gift (no item carries
  Natural Gift type 9; there is no Pixie Plate), Camouflage, Weather Ball,
  the Pokedex search type list and the Pokétch move tester (their overlays
  are identical apart from the icon switch). Natural Gift's type name,
  the Battle Factory's type counts and the Battle Hall's slot-9 cell
  now read slot 9's name from the cache instead of assuming "???".

## ARM9 and overlay differences, all accounted for

The ARM9 differs in 136 runs; every one is inside a table the extractor finds
by content. Map headers `0x020E6BA0..0x020E9468` (weather / flags), the mart
specialty lists `0x020EBA19`, `0x020EBA66` (Veilstone floors), the Game
Corner prize table `0x020EC018` (first prize replaced, TM prizes replaced and
re-priced), the icon palette table `0x020F079D..0x020F096D`, the TM/HM list
`0x020F0C6C..0x020F0CAA`, and the shiny comparison `0x02075E50`. Overlays 11
(Fairy move-button palette), 16 (chart pointers), 21 (appended chart, Pokedex
type-icon switch) and 73 (the intro Pokemon); no other overlay differs, so
overlay-resident tables (move tutors, starters, the Frontier, Pickup, Amity,
trainer prize money) read as in Platinum. Starters are Turtwig, Chimchar and
Piplup in both.

## Not verified yet

- The playthrough walks the whole story to Heatran (100 beats, retail's 91
  plus the hack's nine) with the runner's training cheat (a level-100
  Mewtwo team, healed between Victory Road's legs). Optional content the
  hack adds (gift Pokémon, the Battleground's leaders, new item balls) is
  not walked.
- Whether the real hack prints the lines of trainers 928..1065 (see above).
- Pickup, Pokemart common stock and the Frontier were not diffed at the data
  level, only shown unchanged by the ARM9/overlay survey.

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
