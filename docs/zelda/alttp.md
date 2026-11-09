# A Link to the Past & Four Swords (GBA) — port notes

Version id `alttp`, module `src/zelda/alttp/`. Cartridge: USA, game code
`AZLE01`, 8 MiB, SHA-1 `a272055abbbf6c26b0cd54c87395d01699589161`.

Everything the game shows or plays comes from the player's own ROM at import
time. The repo holds only code: `RomMap.lua` lists *where* things are, the
importer decodes and checks them, and the runtime ports the cartridge's logic.

## How the cartridge is laid out (what we found)

There is no GBA decomp. The layout below was reverse-engineered from the ROM
with a Thumb disassembler (capstone, in scratch), checked against the SNES
logic in snesrev/zelda3 (read-only reference, never built or copied).

| What | Where | Notes |
|---|---|---|
| Graphics sheets | ptr table `0x22B150`, 235 entries | BIOS LZ77, 64 4bpp tiles each — the SNES 3bpp packs re-encoded 4bpp (high/low halves baked in) |
| `kMainTilesets` / sprite / aux tilesets | `0x22B4FC` / `0x22B624` / `0x22B864` | the SNES tables; 0xFF replaces SNES 0 ("keep") |
| Overworld tilemaps | ptr tables `0x14FCC0` (BG2) and `0x14FF40` (BG1), 160 each | **pre-rendered 64x64 map8 maps per 512x512 screen**; the GBA dropped SNES map32/map16. BG1 is the high-priority layer (canopies, roofs) |
| Area parent table | `0x14FC30` | large areas are 2x2 screens |
| Palette blob | `0x3BD758`, 4096 colours | copied to EWRAM `0x02030000` at boot (`0x08130D9C`, through a brightness table that is identity at the default setting) |
| Palette loaders | `0x081305E0` (OWBGMain), `0x0813068C`/`0x0813076C` (OWBG1/2), `0x0813084C` (Overworld_LoadPalettes) | index tables `0x22BC38`, `0x22BC44`, `0x22BB64`; `kOwBgPalInfo` at `0x22BD1C` (stride 4) |
| Per-screen BG palette set | `0x14D8A4`/`0x14D8E4`/`0x14D924` (LW by story phase), `0x14D964` (DW) | copied to RAM `0x02002DC0` by `0x0807499C` |
| Aux tileset / sprite palette per screen | `0x14C868` / `0x14C8E8` | |
| Backdrop colours | literal pool `0x130A54`/`0x130AA4`/`0x130A68` | grass / Dark World / Death Mountain |
| Tile attributes | `0x15DF14`, 512 bytes | `kMap8DataToTileAttr`; the GBA reads `attr[word & 0x1FF]`, hflip bit 10 ORed in for 0x10–0x1B (`0x080691xx`) |
| Link's sheet | `0x22C82C`, raw 4bpp, SNES layout | DMA base in the OAM upload at `0x080A6DD0` |
| Link pose tables | `0x22AB3C`, `0x22ADA6` (DMA sources, 309 each on GBA), `0x1697A0` (`kLinkDmaGraphicsIndices`), `0x169180` (`kLinkSpriteBodys`), `0x16B118` (`kPlayerOamOtherOffs`) | |
| Link green-mail palette | palette blob row `0xB0` | |
| `kSpeedMod`, walk timing | `0x167DEA`, `0x167DB6`, `0x167DC6` | |
| M4A song table | `0x3C3BBC`, 545 songs | MusicPlayer2000, the same engine as Pokemon Gen 3; every track walks clean with `M4ASynth.walk` |
| Four Swords | code/data from about `0x62F000`, text at `0x641000` (plain ASCII) | not decoded yet |

Dungeon room tilemaps are also pre-rendered (LZ77 64x64 maps, pointer table
around `0x1618D8`, 928 entries); not wired up yet.

## What matches the cartridge, and how it was checked

* **Overworld pictures**: both layers, tilesets and palettes of every Light and
  Dark World screen are built by porting the GBA routines above. Checked by
  rendering screens (Link's house 0x2C, Skull Woods 0x40, castle, pyramid,
  Kakariko) and comparing them against the known game; screenshots in
  `G:/Gen2Recomped/scratch_claude/zelda/alttp/shots/` (never in the repo).
* **Walking speed**: `kSpeedMod` from the ROM, 8.8 fixed point as in
  `Link_MovePosition`: 1.5 px a frame straight, 1 px per axis diagonally.
  Test: `tests/zelda_alttp_extract_test.lua` (8 frames = 12 px; diagonal 8 px).
* **Walk cycle**: steps 1..8, each lasting `animTab3[step]` frames (ROM).
* **Link's sprite**: head/body cells, offsets and flips from the cartridge's
  own pose tables, Link's sheet and palette from the ROM.
* **Collision**: tile attributes from the ROM table, read off the BG2 map as the
  GBA does. Behaviour classes follow `TileDetect_ExecuteInner` (walls,
  liftables, chests, deep water, slopes solid; ledges hop). Tests: house walls
  solid, yard walkable, lake = deep water (0x08), bush stops Link.
* **Area layout / camera**: parent table from the ROM; the camera is clamped to
  the area, crossing an edge scrolls to the next area.

## What differs / is approximate

* Probe points are a simplification of `TileDetect_Movement_X/Y`; the
  cartridge's corner nudging (sliding round wall corners) is not ported.
* Ledge hops land on the first standable tile, not via the exact `LinkHop_*`
  arcs; diagonal ledges hop straight.
* Scroll between areas is a 40-frame camera pan; the cartridge also walks Link a
  few pixels and swaps the area graphics mid-scroll.
* Music: song = 399 + SNES music number (LW 2, Lost Woods 5, Kakariko 7, DW 9).
  The BGM block of the song table starts at 400, but the cartridge's own
  id-to-song translation is not located yet, so the mapping is **unverified**.
* Peer Links (online) are tinted copies of Link's green palette, not the
  cartridge's Four Swords palettes.
* Title: the cartridge's title screen (round 4b); the intro, file select
  and name entry are not ported (see "Not cartridge art yet").

## Not ported yet

(Updated round 4b.) Room-to-room doors and stairs, sprites/enemies/NPCs,
the pause/item menu and map screens, the file select, items and sword,
damage, RNG, SFX, most of the opening. Interiors, overworld entrances and
exits, the HUD, the title and dialogue are in (see their sections).

## Online

`Online.lua` runs on the foundation's `ZeldaSession`: presence co-op, each
player's Link shown in the others' Hyrule in the session colour (1 green, 2 red,
3 blue, 4 purple). Snapshot `{ v=1, w, x, y, z, f, s }`, ~30 Hz, clamped on
receipt; event `{ t="hi" }` on attach. Four Swords proper will reuse these
shapes once its stages are decoded.

## Tests and harness

* `tests/zelda_alttp_logic_test.lua` — no ROM needed (serializer, palette row
  walk, detection, movement, collision, ledges, online clamps).
* `tests/zelda_alttp_extract_test.lua` — full import into memory + overworld,
  Link, music and online checks; skips when the ROM is absent.
  Run: `python tools/run_lua_check.py tests/<file>`.
* Scratch harness (outside the repo):
  `G:/Gen2Recomped/scratch_claude/zelda/alttp/harness/` — imports into memory,
  drives the game, writes PNGs to `.../zelda/alttp/shots/`.

## Four Swords (round 2)

Four Swords is not a separate image: the one program at `0x08000000-0x08140000`
runs both games, and the Four Swords side is Capcom's engine, the ancestor of
The Minish Cap's (the same 12-byte gfx-group items, 4-byte palette-group
items and 64x64 map-layer structs as `zeldaret/tmc`, used read-only as a
reference). Found by disassembly:

| What | Where | Notes |
|---|---|---|
| FS init | `0x0800B084` | stores palette base `0x0844DD74` and graphics base `0x0854F7E8` |
| LoadGfxGroup | `0x0801484C`, table `0x146060` | `{u32 off|more, u32 dst, s32 size (<0 = LZ77)}`; dst 0 = palette group |
| LoadPaletteGroup | `0x0800B890`, table `0x429750` | `{u16 byte off, u8 dst pal, u8 count|0x80 more}` |
| LoadAreaTileset | `0x08015DD8` | gfx group `6 + area`; camera clamp 0..`0x3F0`-screen |
| LoadFloorMap | `0x08015F74` | gfx group `12 + map`: two 63x63 u16 metatile layers (7938 bytes) to `0x02038000`/`0x0203A000`; maps 51/72/93 also load BG tiles |
| Collision fill | `0x080160F8`, table `0x14AB24` | `coll[tileType[metatile]]` per layer, borders 0xFF |
| Floor loader | `0x08012EB4` | floor struct: map, area, ..., `+0x18` 8-byte objects to `0xFFFFFFFF` |
| World tables | `0x42B8A8` -> 6 tables of `(floor ptr, flags|index)` | `0xC0000000` entries are padding |
| Animated BG tiles | `0x08015D50`, lists `0x146060`, anims `0x138BB4` | frames of `{u16 dst, u8 n-1, u8 flags, u32 off}` |
| Link palettes | `0x44DD74`, 4 x 16 | green, red, blue, purple |
| Sound dispatcher | `0x0800D3xx-0x0800D4xx`, m4aSongNumStart `0x08134708` | songs 400-499 are BGM |

Worlds by tileset: area 2 forest (Sea of Trees), 1 ice (Talus Cave), 3 lava
(Death Mountain), 0 palace, 4 the GBA-only Realm of Memories/Hero's Trial
dungeon set. World table 4 (Lua index) starts on floor map 52.

**What the port does (`FsExtract.lua`, `Fs.lua`, `FourSwords.lua`):** imports
all 6 areas and 123 floor maps; renders a floor exactly from the cartridge
tables (both layers, area palettes, first frame of animated tiles); collision
from the cartridge table (solid when either layer's byte is non-zero); 1-4
Links in the cartridge's four palettes; rupees, scores and results; online on
ZeldaSession with the host deciding every pickup.

**Ours, not the cartridge's (honest list):**
* Link's sprite is ALttP Link's sheet recoloured index-by-nearest-colour into
  each Four Swords palette; the FS sprite frames are not decoded.
* Rupees: 30 per floor at seeded, reachable cells (70% green 1, 23% blue 5,
  7% red 20). The cartridge's rupees come from grass, pots, enemies and
  chests, none of which are ported. Rupee shape is drawn, not ROM art.
* Two-minute stage timer, results screen and "A: next floor" are ours. The
  cartridge's medal/end-of-level tally and the Force Gem rules are not ported.
* Spawn: the floor's type-4 object sits on the entrance wall; players spawn on
  nearest reachable cells (the walk-in is not ported).
* Both BG layers are drawn under the players (tree canopies do not cover
  Links); animated tiles are frozen on frame 1 (palette animation skipped);
  padding cells around a floor are drawn as backdrop when they match the far
  corner, otherwise the cartridge's unrelated VRAM shows (the cartridge's
  camera would not go there; ours clamps only to 1008 px).
* Movement uses the ALttP Link code (speeds, probes), not FS's.
* Camera: each player's screen follows their own Link (as each GBA did) --
  there is no shared camera in Four Swords to port.

## Music table (round 2, unresolved)

`m4aSongNumStart` (`0x08134708`) has three callers, all in the sound command
dispatcher at `0x0800D3xx-0x0800D4xx`, which treats songs 400-499 as BGM.
The ALttP side's area -> music-id -> song path was not located this round, so
`Audio.lua` still uses `399 + SNES id` (unverified).

## Interiors (rounds 3-4)

Found: the room loader `0x0807FF10` takes `dungeon_room_index` (RAM
`0x03002230+0xA1E`) and decompresses a pre-rendered 64x64 map8 tilemap per
layer: BG2 from `0x1618D8`, BG1 from `0x162258` (304 rooms each; a third table
`0x161D98` is an extra layer, filler in the rooms checked). Room `0x97` swaps
maps by a flag. GBA RAM is SNES WRAM + `0x1F8` for these variables
(`palette_main_indoors` `0x0AB6` -> `+0xCAE`, aux tileset `0x0AA2` -> `+0xC9A`).

Round 4, all from the cartridge and checked against Link's house:
* **Room header** `0x164020` (u32 per room -> 14 bytes, headers overlap as on
  the SNES), read by `0x08080D00`, which is the SNES `Dungeon_LoadHeader`: +0 bg2
  mode/collision/lights, +1 palette set, +2 aux tileset, +3 spriteset, +4 bg
  move, +5/+6 tags, +7 stair planes, +8..+13 stair and hole targets.
* **Palette sets** `0x22BC6C`, 4 bytes each (44 sets); byte 0 is
  `palette_main_indoors`, which picks the 96 colours at blob colour
  `0x400 + table0x22BC10[...]` (loader `0x0813041C`).
* **Entrances** `0x150EC4`, `0x2C` bytes each, `0x89` entries (loader
  `0x08078AC8`): +0 room, +0x16 Link Y, +0x18 Link X (world pixels), +0x1E
  main tileset. Entrance 0 is Link in bed, entrance 1 is Link at his door.
* **Tile attributes** (the SNES `attributes_for_tile`, built at `0x02002E40`
  by `0x08092848` / `0x08092874`): `0x140` bytes at `0x15E114`, `0x80` bytes
  from the aux-indexed pointers at `0x15E794` (23 sets), `0x40` bytes at
  `0x15E254`; indexed by tile & `0x1FF`. Walls `0x01`/`0x04`, furniture `0x02`,
  chest `0x63`, floor `0x00`, as on the SNES.
* Room object lists `0x162768` (SNES room data format) and door lists
  `0x162C28` are interpreted at load (`0x0807FD84`, `0x0807FE08`; dispatch
  tables `0x152BD0`, `0x1530B0`, `0x152FB0`, doors `0x1532B0`). Most object
  handlers are empty on the GBA because the maps are pre-rendered. Not decoded.

Link's house now draws with main tileset 3 (entrance 1), aux 3 and palette
set `0x15` -> `palette_main_indoors` 2 (header `01 15 03 0D ...`), i.e. the
cartridge's wood floor and brown walls. The round-3 guess (main 31, aux 2,
palette 6, BG1-fill collision) is gone. Collision is the BG2 tile attributes.
BG1 is the room frame over a transparent tile and is drawn above BG2.

Checked by `tests/zelda_alttp_extract_test.lua` (header/entrance values,
spawn, north wall, chest attribute, table blocks/floor open, enter and leave)
and harness shots `12_house_inside.png`, `13_house_walk.png`,
`14_house_out.png`.

Round 4b replaced the hand-placed rectangles with the cartridge's tables
(see "Doors"). Still ours (honest list):
* Where Link reappears outside: just below the overworld door of the
  entrance he used (from the overworld entrance table). The cartridge's own
  exit table (which also sets the camera) is not located.
* Our Link stops 16-48 px short of the door row the cartridge tests (the
  door-frame collision and corner nudging are not ported), so the door check
  also looks up to 3 rows of 16 px ahead; the door tile pair check guards it.
  101 of the 118 doors that have an overworld spot are entered by walking
  straight up at them; the rest (big castle gates, caves without door tiles,
  special doors 0xE9/0x149/0x169) are not.
* The walkable set of attribute values (`Interior.WALKABLE`) covers the SNES
  values met so far. Chests, pots and stairs do nothing yet; room-to-room
  doors (attributes 0x80-0x8D) and the header's stair targets are not used.
* Rooms do not survive a save (saving inside writes the door outside).
* The Hyrule Castle escape, the sewers, the sanctuary and the Eastern Palace
  are NOT wired: they need room-to-room doors and stairs.

## Menus, HUD, title and text (round 4b)

All read by `UiExtract.lua` (import stage "ui", cacheVersion 5) from the
places below, found by disassembly; nothing on these screens is invented
except where "Not cartridge art yet" says so.

| What | Where | Notes |
|---|---|---|
| Languages | RAM `0x03002230+0x98E` | 0 JP, 1 US, 2 UK, 3 FR, 4 DE, 5 ES, 6 IT; the port uses 1 |
| HUD charblock | `0x22B9E4` (7 x 3 LZ77 pointers), loader `0x0812EED8` | VRAM `0x06004000`; tiles numbered as the SNES BG3 tiles (digits `0x90`, hearts `0xA0`-`0xA2`, letters `0x150`+) |
| HUD template | `0x16B65C`, 6 x 32 words | copied to RAM `0x0200B180` by `0x080A797C`; the layer scrolls 8 px left |
| HUD updates | hearts `0x080A7588`/`0x080A7830` (tables `0x16B7DC`/`0x16B7E2`), magic `0x080A75FC` (`0x16B7E8`, 17 x 4), digits `0x080A78A8`, keys `0x080A77C4` | max bombs/arrows `0x16B588`/`0x16B598`; a full counter uses palette 8 |
| HUD palettes | `0x08130384` | palettes 0/1: blob colour `0x308` + `0x22BC0C[mode]`, 8 rows of 4; palettes 8-15: `0x3BF758` |
| Title | loader `0x0812D430`/`0x0812D4CC`, palettes `0x0812D338` | tiles `0x3B37B4` (+ `0x3B47FC` at `0x3400`, subtitle `0x3C23D4` at `0x2000`), BG1 logo `0x3B5144`, BG2 scenery `0x3B53A0`, subtitle strips `0x22B088` (drawn by `0x08068E7C`), palettes `0x3B556C` (128) and `0x22B048` (16), scroll BG1 x 8, BG2 x 16, y 24 |
| Messages | BMG file `0x180CE8` ("MESGbmg1", INF1/DAT1, 455 messages) | every byte scrambled by its offset: reader `0x08129E0C`, key `0x180CD0`; lookup `0x08129D28`; an SNES index above 15 is stored 3 lower |
| Dialogue font | `0x3B5758` (raw 4bpp, 8x16 glyphs), widths `0x195D98` | renderer `0x08127F00`; English draws codes up to 0x7F from the second half (+ 0x100) |
| Text window | border tiles `0x180CBC`, positions `0x18097C`, waits `0x180C9C` | `0x081290B4` draws 24 x 8 tiles; glyph tiles `0x180`+ with palette 1, 21 x 6 tiles inside; the lower window when Link is high on the screen (`0x08129C58`) |

The text is ASCII with newlines; byte `0x1A` starts a command `{ 0x1A,
length, kind, 0, code, args }` whose code is the SNES text command (`0x6A`
name, `0x6B` window type, `0x73` scroll, `0x74`-`0x76` line, `0x78` wait,
`0x7A` speed, `0x7E` wait for a key, `0x7F` end); kind 1 is a glyph from the
font's symbol row (the button letters, mapped by their shapes).

Not ported in the text: choice cursors (Choose/Choose2/Choose3/Item print
but pick nothing), the scroll animation (lines jump up), text sound effects.

Checked by `tests/zelda_alttp_logic_test.lua` (HUD word logic, message
tokens and the box runner on made-up data) and
`tests/zelda_alttp_extract_test.lua` (HUD tables, hearts and digits for a
new file, title blob, 455 messages, the telepathy and uncle messages, font
pixels), and harness shots `r4b_01`-`r4b_09` in
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r4b/shots/`.

## Doors (round 4b)

| What | Where | Notes |
|---|---|---|
| Overworld door check | `0x0808BB88` | the 16x16 tile at (Link x, Link y + 7): its two bottom map8 tiles (& `0x1FF`) must be a pair from `0x1537DE`/`0x153836` (44 each) |
| Overworld entrances | area `0x15388E`, pos `0x153994` (u16 x 131), entrance `0x153A9A` (u8 x 131) | pos = the door's top-left map8 cell as a halfword index into the area buffer `0x02018000` (4096 cells per 512 px screen of the area, each four 32x32 screenblocks); searched from the end |
| Room doors | `0x162C28` (u32 per room -> u16 words to `0xFFFF`) | the SNES format: bits 0-1 direction, 4-7 position, high byte type |
| Door positions | up `0x167778`, down `0x167790` (12 u16 each) | `kDoorPositionToTilemapOffs_Up/_Down`, found by value |

A door of an entrance type (4, 10, 12, 14, 16), or one sharing its place with
an ExitToOw marker (type 18), gets attribute `0x8E` over its two middle
columns (SNES `dungeon.c`); Link leaves when he walks down onto it.

## The opening (round 4b, partial)

A new file goes from the title to entrance 0 (Link's bed, room `0x104`),
shows Zelda's telepathy (message 31; its Window command asks for no window)
over the room, then the uncle's message 13 in the window, then Link is free.
Not ported: the rain, the night palette and lights, Link's in-bed pose and
getting up, the uncle's sprite and walk out, the music cue, the secret
passage, the sword pickup and its hitboxes, soldiers (damage, knockback,
drops), the castle, the sewers and the sanctuary.

## Not cartridge art yet

Drawn by our code, not from cartridge graphics or layouts:
* **Title**: the game choice under the cartridge's title is our line of
  text (the cartridge's menu letters, our placement and "- -" marks). The
  title's sprites (sword, "PRESS START", copyright) are not drawn, and the
  cartridge's game-select screen is not decoded.
* **File select and name entry**: not ported (no file screen; a new game
  starts from the title; the name in messages is "Link").
* **Text window inside**: the cartridge leaves the window clear and darkens
  the field behind it with a blend that is not decoded; ours is a 50 % black
  fill. The telepathy's dark room is a black overlay, not the cartridge's fade.
* **No pause/item menu and no map screens.**
* **Four Swords** (`FourSwords.lua`): rupees are drawn diamonds (polygon +
  line), the HUD bar, scores and timer are LOVE-font text on a rectangle, the
  "STAGE CLEAR" results box and "waiting for the host" are LOVE-font text, and
  the other players' Links are the ALttP Link recoloured by our palette swap.

Cartridge art in use: the title screen (logo, scenery, subtitle, palettes);
the HUD (template, hearts, magic meter, counters, item box frame, palettes);
dialogue (messages, font, widths, window border); overworld maps, tiles and
palettes; Link's sprite sheet and palette; interiors (tilesets, palettes,
layers); Four Swords floor maps, tiles and palettes.
