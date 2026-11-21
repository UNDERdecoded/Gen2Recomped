# ROM revisions: what each game accepts

The importer accepts a cartridge by **SHA-1 only** (`GameVersion.acceptsSha1`,
`sha1` + `sha1Alt`). Every extractor reads fixed addresses, symbol tables or
code patterns that were proven against one exact dump. A hash match is the
only promise that those addresses still mean what the extractor thinks.

A dump that is not accepted goes through `src/import/RomRevisions.lua`, which
reads the header (game code, region letter, mask-ROM revision byte) and the
pret-published hashes, and names what it found. Before this change, a clean
FireRed Rev 1 was told it was "patched, trimmed or fixed". Now it is told
"This is Pokemon FireRed (USA, Europe) (Rev 1). This build imports Pokemon
FireRed (USA, Europe) only; that revision is not supported yet because ...".
The batch picker's "not recognised" list shows the same thing per file.

`tests/rom_revisions_test.lua` keeps `RomRevisions.ACCEPTED` identical to
GameVersion and keeps every KNOWN-unsupported hash refused. It also reads the
header of each dump in the repo root and checks the messages for synthetic
other revisions.

## Per game

| Game | Accepted (before = after) | Known retail English builds not accepted | Why not |
|---|---|---|---|
| Red | (USA, Europe) `ea9bcae6` | none (one English release; VC uses the same ROM plus a patch) | n/a |
| Blue | (USA, Europe) `d7037c83` | none | n/a |
| Yellow | (USA, Europe) `cc7d0326` | none | n/a |
| Gold | (USA, Europe) `d8b8a360` | none | n/a |
| Silver | (USA, Europe) `49b163f7` | none | n/a |
| Crystal | Rev 0 (USA) `f4cd194b`, Rev 1 (USA, Europe) `f2f52230` | (Australia) BYTU `a0fc810f` | It is built with `_CRYSTAL_AU`, which rewrites the Celadon/Goldenrod Game Corner and Buena scripts (15 sites in 5 files). The map-script banks then no longer match `pokecrystal11.sym`, and no AU symbol table has been built. |
| Prism | the one mapped release `75207669` | other Prism releases | Romhack tables were found one by one for this file |
| Polished Crystal | 3.2.3 `6930b48a` | other releases | Same reason as Prism |
| Renegade Platinum | the trimmed patched Rev 1 file `381f9eef` (header CPUE rev 1) | other builds of the hack | Measured against this one file ([renegade-platinum.md](renegade-platinum.md)); a different build reads as a modified Platinum dump |
| FireRed | Rev 0 (USA, Europe) `41cb23d8` | Rev 1 `dd5945db`, Switch Online build (header rev 10) `baa452d0` | See below |
| Emerald | (USA, Europe) `f3ae0881` | none (one release) | n/a |
| Platinum | Rev 0 `ce81046e`, Rev 1 `0862ec35` (USA); (Europe) CPUE rev 10 `8d15cd44`; (Germany) CPUD `5d009a17` | French, Italian, Spanish (CPUF/CPUI/CPUS) | No dump to map against; see below for how the German one was mapped |
| HeartGold | (USA) IPKE `4fcded0e` | (Europe) IPKP | pokeheartgold builds the US version only |
| SoulSilver | (USA, Australia) IPGE `f8dc38ea` | (Europe) IPGP | Same as HeartGold |
| Black | (USA, Europe) IRBO `26ad0b99` | none known | n/a |
| White | (USA, Europe) IRAO `bc696a0d` | none known | n/a |

LeafGreen (`574fa542`, Rev 1 `7862c67b`, Switch `62b9fc77`) is recognised by
hash and named, but this build does not import LeafGreen at all.

Platinum (Europe) and (Germany) moved from "refused" to "accepted" once the
user's own dumps were there to map against (next section). The rest still
either have no extractor mapping to back them (FireRed Rev 1, Crystal AU) or
have neither a dump nor a symbol table to check against (the other European
DS carts).

## Platinum (Europe) and (Germany)

Both import as `platinum`, into the same cache folder and with the same save
(`_platinum`). A save started on one cartridge's cache keeps working on
another's: the only language-bearing value a Gen 4 mon stores that the engine
computes with is its nature NAME, and `SaveData` re-derives an unknown one from
the personality (`personality % 25`) against the loaded cache.

**(Europe), English, `8d15cd44`.** The header says CPUE, revision 10. The
ARM9 and all 122 overlays are byte-identical to US Rev 1, and so is every file
but five. Member by member:

| File | Members | What |
|---|---|---|
| `/data/slot.narc` | 0, 8, 11, 21 | the Game Corner machines' art |
| `/demo/title/op_demo.narc` | 113 | the opening's legal overlay |
| `/fielddata/land_data/land_data.narc` | 164 | Route 225, four collision bytes |
| `/fielddata/script/scr_seq.narc` | 141 | the Veilstone Game Corner's script |
| `/msgdata/pl_msg.narc` | 143, 147, 366, 417, 544, 623 | 28 strings, mostly the Game Corner's |

That is the European Game Corner: its machines are not slots. Its staff talk
about Coins and a TM campaign instead, and the script is the European one. The
importer needs nothing for this cartridge beyond its hash.

**(Germany), Platin Edition, `5d009a17`.** This is a separate build:

- The ARM9 is 416 bytes longer, and every overlay loads 0x1A0 or 0x1C0 higher.
- The 724 text banks keep the US bank numbers and hold German text.
- The 32 language-specific archives moved from paths like `/graphic/box.narc`
  to `/resource/ger/box/box.narc`. The file name never changed. `op_demo.narc`
  is three members shorter because it has no US legal overlay.

What the extractor needed:

- **The archive paths.** `tools/gen4_region_map_gen.py <usa.nds> <de.nds>`
  pairs each US path with the one German file of the same name and writes
  `src/import/Gen4RegionMap.lua`. A name with zero or two candidates stops the
  tool; it does not guess. `NdsRom:index()` then lets the US path name the
  German file, so no stage changed its paths.
- **The code tables.** No address map was needed. Every ARM9 and overlay table
  the extractor reads is found by content (a signature, a structural search
  or a known first row). Two were not, and both were fixed:
  - The area-name popup read the map headers at the fixed US offset
    `0xE601C` and got plausible garbage. It now takes the headers the maps
    stage located.
  - The staff roll's signature included a y coordinate and a row count of
    237. The German roll is spaced differently and has 224 rows.
- **English used as a key.** These were rekeyed to ids:
  - Poketch app pictures and behaviour
  - the starter cross-check
  - TM/HM detection (German HMs are `VM01`)
  - the Plate range
  - the orb flag
  - Repels and Flutes
  - the Journal, Poke Radar, Town Map, Coin, Poffin and Seal Cases, Point Card
    and Fashion Case
  - the Underground's Mystery Zone test, which now uses the label text id
  - Underground treasures into the bag
  - the berry-soil bag pocket
  - the first PC Potion
  - GTS mail
- **File names.** Battle sprites are `001.png` rather than `001_bisasam.png` on
  a non-English cartridge.

`tools/gen4_region_check.lua <us cache> <other cache>` proves the result. It
walks every generated table of both imports and sorts each difference into one
of four kinds:

- **Text:** the cartridge's language.
- **Known:** listed in the tool with the reason.
- **Address:** where a table was found.
- **Data:** anything else. The check fails on any data difference.

Both cartridges pass with zero data differences. The known ones are:

- **Both cartridges:**
  - the Route 225 collision fix
  - the rewritten scripts. German Platinum also rewrites script files 31
    (Trainers' School), 148 (Veilstone Store), 367 and 376..379 (Battle Tower
    and the Frontier facilities) and 500.
  - the slot-machine art
- **German cartridge only:**
  - the Pokedex A-Z order and its initial-letter groups
  - the wallpaper-password word list
  - the in-game trades' language field
  - the title logo
  - the missing legal overlay
  - the staff roll
  - overlay words the trainer-AI reader keeps past its script. They are RAM
    pointers, so they move.

The art with baked-in text is German as well. That covers the summary, Pokedex,
party, box, bag, trainer card, naming, contest and touch screens, the type
icons, the "KP" healthbox, and one map texture set (21, its `m_depanel` signs).

**Fixed since (runtime on a German cache):**

- Pal Park, Poke Transfer and the Monster Walker reach Gen IV items and moves
  by cartridge id through `src/pokemon/Gen4EnglishRef.lua` (the table is
  `Gen4EnglishNames.lua`, written by `tools/gen4_english_ref_gen.lua` from an
  English import). Held items survive a Gen 3 migration.
- The whiteout's nurse/Mom scripts, the loss bank and the scurry line are found
  by shape when the English words are absent.
- The randomizer's protected move/item lists read English names through the
  same reference, and the kept trainer classes are class ids.
- The hero's default names come from the cartridge's name bank (text bank 427).
- A non-English Gen 4 import writes `gen4_language.lua`; the translation layer
  reads it, so German ROM text is not sent for translation as English.
- The battle prints the cartridge's own lines (`src/battle/Gen4BattleText.lua`,
  bank 368 and bank 0) for the common ones: wild/trainer intro, "Go!", move
  use, fainted, effectiveness, critical hit, misses, EXP and level-up, stat
  changes, catch, escape.

**Still English on a German cartridge:**

- the engine's own strings that are not mapped above (the less common battle
  lines: statuses, weather, abilities, items; some menu words the port draws)
- the translation layer's engine-string catalog is English-keyed

Checks that assert English text now take the language from the cache
(`gen4_item_use_check`, `gen4_area_popup_check`, `gen4_underground_check`,
`gen4_machine_check`, `gen4_mining_screen_check`, `gen4_met_location_check`,
`gen4_blackout_check`). Others still assert English (contest, safari, seals,
journal, tablet, tag battle, town map, field queries, fly, daily slots).

## Evidence for the revisions already accepted as alternates

- **Crystal Rev 0 vs Rev 1.** A byte diff of the two dumps in the repo root
  shows 584 differing bytes in 17 spans and no layout shift. The spans fall
  inside Pokedex code (`InitPokedex`, `Pokedex_*`, `DisplayDexEntry`,
  `NewPokedexEntry`), `BattleTowerText`, one mobile function, the
  `Stadium2N64Tilemap` blob and bank-end padding past `OddEggs`. The
  `BattleTowerText` change, for example, is one operand of a `ld hl` (a WRAM
  address). Every span is code or data the extractor never reads, so one
  manifest serves both.
- **Platinum Rev 0 vs Rev 1.** In pret/pokeplatinum, `sbins_rev0.sha1` and
  `sbins_rev1.sha1` differ in exactly one binary, `gts_application.sbin` (the
  GTS overlay). The ARM9, every other overlay and the filesystem
  (`filesys.sha1`) are shared, so the Gen 4 extractor reads identical data
  from both.

## FireRed Rev 1: why it is not accepted yet

From pret `pokefirered.sym` against `pokefirered_rev1.sym`: all 49,229 ROM
symbols exist in both. Rev 1 moves them in ten runs (rev 0 start, delta):

| Rev 0 start | First symbol | Delta |
|---|---|---|
| 0x000000 | Start | 0 |
| 0x0004B0 | UpdateLinkAndCallCallbacks | +20 |
| 0x0ECEA4 | IntroCB_Scene1 | +24 |
| 0x0EDF94 | Scene3_StartGengarAttack | +120 |
| 0x1B7611 | Help_Text_HowToUseHomePC | +115 |
| 0x1C55C8 | Test_Text_Empty | +112 |
| 0x448A7D | gChikoritaPokedexTextUnused | +109 |
| 0x44AFCD | gTyranitarPokedexTextUnused | +97 |
| 0x44E850 | gPokedexEntries | +96 |
| 0xD00000 | gBattleInterface_Textbox_Gfx | 0 |

About 45,000 symbols shift. The address map itself is simple. What blocks it
is that nothing in the FireRed path is keyed by revision:

- `tools/rom_manifest_firered.json` mixes absolute ROM offsets with sizes and
  counts in the same objects (`bagSprite.record` is an address,
  `bagSprite.size` is not).
- `RomExtractorGen3.lua` holds about 800 literals in the shifted range, partly
  Emerald addresses mapped through `addressMap` and partly inline FireRed
  ones (`fireRed and rowsAt(0x4021E8, 3)`). `Gen3TradeArt.lua` holds about 60
  more.
- The extractor decodes Thumb BL targets (`blTargets`, and its own decoder
  near line 18950). A BL between two runs encodes a different displacement in
  Rev 1.
- About 15 stages search `rom.data` directly for byte needles.

There are two ways to support Rev 1:
1. Translate every Rev 0 constant through the table above.
2. Present a Rev 1 ROM to the extractor in Rev 0 layout. Relocate the runs,
   translate pointer reads in `RomGba:u32` and `RomGba:pointer`, and correct
   cross-run BL decoding.

Either way it needs a real Rev 1 dump to check the result. A wrong address
here produces wrong data without an error. Until then, Rev 1 is refused with
the reason given.
