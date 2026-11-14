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
| Platinum | Rev 0 `ce81046e`, Rev 1 `0862ec35` (USA) | (Europe) CPUP | No dump or symbols to map it against |
| HeartGold | (USA) IPKE `4fcded0e` | (Europe) IPKP | pokeheartgold builds the US version only |
| SoulSilver | (USA, Australia) IPGE `f8dc38ea` | (Europe) IPGP | Same as HeartGold |
| Black | (USA, Europe) IRBO `26ad0b99` | none known | n/a |
| White | (USA, Europe) IRAO `bc696a0d` | none known | n/a |

LeafGreen (`574fa542`, Rev 1 `7862c67b`, Switch `62b9fc77`) is recognised by
hash and named, but this build does not import LeafGreen at all.

No revision moved from "refused" to "accepted" in this pass. Each candidate
either has no extractor mapping to back it (FireRed Rev 1, Crystal AU) or has
neither a dump nor a symbol table to check against (the European DS carts).

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
