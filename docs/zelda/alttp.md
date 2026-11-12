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
| Per-screen SPRITE palette set (round 15: was read as the BG set) | `0x14D8A4`/`0x14D8E4`/`0x14D924` (LW by story phase), `0x14D964` (DW) | copied to RAM `0x02002DC0` by `0x0807499C`; passed as r0 to `0x0813084C` (kOwSprPalInfo) |
| Aux tileset / BG palette set per screen | `0x14C868` / `0x14C8E8` | round 15: `0x14C8E8` is kOverworldBgPalettes (r1 of `0x0813084C`, kOwBgPalInfo); the cache keeps the old name `owSprPalettes` |
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

(Updated round 7.) The pause/item menu and map screens, the file select,
items other than the sword, RNG, SFX, Link's sword sprite, the music table.
Round 7 added the escape's sprite graphics, the rain and night colours, dark
rooms, game over and the castle's big door (see "Sprites (round 7)"). In-room layer stairs, keys and locked doors,
chests, the castle escape's sprites, the sword and damage are in (round 6,
see "The castle escape"); interiors, entrances and exits, the HUD, the title
and dialogue were in before.

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
* `tests/zelda_alttp_drops_test.lua` (round 9) and
  `tests/zelda_alttp_combat_test.lua` (round 10: nudging, knockback,
  trapdoors and kill tags, spiral landing layer, the shelf, secret enemies,
  heart / shadow chars) -- full import into memory; skip without the ROM.
* `tests/zelda_alttp_layers_test.lua` (round 11): the two attribute tables,
  door slots / marks / doorways / pictures, layer toggles, the south
  straight stairs, an indoor ledge hop, the adjacent key door, the cucco's
  hops -- full import into memory; skips without the ROM.
* `tests/zelda_alttp_view_test.lua` (round 14): OBJ / BG priorities and
  the draw order, the door's outer row on the high map, zoom steps and
  input, connected rooms, seamless vs cartridge transitions, the menu
  rows, the guard parry and the knife guard -- full import; skips without
  the ROM.
* `tests/zelda_alttp_roomobj_test.lua` (round 16): push blocks (drawn,
  pushed, fixed), rupee floors (drawn, taken in play, remembered), large
  blocks, bomb floors, Blind's light, doors' final types and closed
  shutters, the push-block tag.
* `tests/zelda_alttp_people_test.lua` (round 16): the overworld sprite lists
  by phase, the townsfolk's tables, the elder's wife / Kakariko's people /
  Sahasrahla talking, the ball-and-chain guard's states and ball.
* `tests/zelda_alttp_r19_test.lua` (round 19): what it checks.
  - The stair mask in 99: a key lock, its open attributes, its stairs to DA,
    and a key opening it.
  - BA's pot key actor.
  - A8's south-west doorway trigger.
  - The held sword: the hold, the slow walk, the pose, letting go, and a
    Stalfos staying put.
  - The dash: no boots, the charge, letting go, the run's speed, the wall
    rebound.
  - The boots byte 0x39.
  - The HUD item box.
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
* (Round 5: Link now reappears where the cartridge's exit table or cached
  entry puts him, see "Room to room"; the door-based spot is a fallback for
  rooms the table lacks.)
* Our Link stops 16-48 px short of the door row the cartridge tests (the
  door-frame collision and corner nudging are not ported), so the door check
  also looks up to 3 rows of 16 px ahead; the door tile pair check guards it.
  101 of the 118 doors that have an overworld spot are entered by walking
  straight up at them; the rest (big castle gates, caves without door tiles,
  special doors 0xE9/0x149/0x169) are not.
* The walkable set of attribute values (`Interior.WALKABLE`) covers the SNES
  values met so far. Chests and pots do nothing yet. (Round 5: room-to-room
  doors and stairs are in, see "Room to room".)
* Rooms do not survive a save (saving inside writes where the room's exit
  puts Link).
* (Round 6: the escape's mechanics are in -- layer stairs, keys, locks,
  soldiers, the uncle, Zelda, the shelf, the switch, the priest; the route
  bot verifies the bed to the castle hall, see "The castle escape" and
  PROGRESS-alttp.md 6.6 for what is not yet verified end to end.)

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

Not ported in the text: the item chooser (Item prints but picks nothing),
the scroll animation (lines jump up), text sound effects. (Round 22: the
choice cursors Choose / Choose2 / Choose3 / Selchg are ported, see "Round
22".)

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

## Room to room, exits and stairs (round 5)

| What | Where | Notes |
|---|---|---|
| Exit table | rooms `0x1501C0` (u16 x 79), screens `0x15025E` (u8 x 79), then 7 u16 arrays from `0x1502AE` (`+k*158`) | SNES kExitData: Map16LoadSrcOff, ScrollY, ScrollX, Link Y, Link X, CameraY, CameraX; searched from the end for the room. Link's house: 0x8B8,0xAE8 on screen 0x2C; sanctuary 0x758,0x414 on 0x13 |
| Room layout | byte 1 of the room's object list (`0x162768`) | SNES dung_layout_and_starting_quadrant; GBA RAM: layout `+0xAB4`, quadrant x/y `+0x9E3`/`+0x9E4`, composite `+0x9E2` (users `0x0806F344`...) |
| kLayoutQuadrantFlags | `0x14CDDC` (32 bytes, found by value) | a CLEAR bit = that axis is open (quadrant_fullsize = 2, the camera sees all 512 px): layout 0 = four quadrants, layout 7 = one room |
| Door positions | left `0x1677A8`, right `0x1677C0` | after up/down (`0x167778`/`0x167790`) |
| Third room layer | `0x161D98` (u32 x 304 -> LZ77 map, loaded to `0x0201A000`) | the lower floor of two-level rooms (castle wings 0x60/0x62); filler elsewhere |
| Object lists | `0x162768` | SNES 3-byte objects; on the GBA each of 3 layers ends with `0xFFF0`, then its door words to `0xFFFF`. Stair objects: subtype 2 `0x2D-0x2F`, `0x38-0x3B`; subtype 3 `0x1E-0x21` |

What the port does (`Interior.lua`, `Game.lua`):
* Leaving to the overworld: rooms below 0x100 and 0x104 use the exit table;
  other rooms 0x100-0x17F put Link back where he came in, 16 px higher
  below 0x124 (SNES LoadCachedEntranceProperties); the cached spot is the
  cartridge's trigger row (door y + 8), not where our Link stopped.
* The exit spot is inside the doorway (under the roof layer); Link then
  walks 16 px down. **Ours**: the cartridge's walk-out routine is not
  located; 16 px is chosen so he stands on the door step.
* Camera area per room/quadrant from the layout flags; walking out of it is
  an intra-room (quadrant) or inter-room (room +-1 / +-16) transition: the
  camera pans (4 px a frame, at least 16 frames) while Link walks 16 px.
  **Ours**: pan speed and step length approximate the SNES
  HandleEdgeTransitionMovement* steps; the GBA's own transition timing is
  not decoded.
* Doorways: the pre-rendered maps draw doors, but their tile attributes are
  wall; the door list opens the two middle cells across the wall for open
  kinds (0, 2, 6, 8, 20, 22, 24, 26, 64, 70, 72, 74). Key doors, locked
  stair masks, bombable/slashable walls and closed shutters stay shut.
* Stairs: stair objects write the SNES attributes (0x26/0x38/0x39/0x5E/0x5F
  and the stair number 0x30+, down stairs from 0x34) in the SNES category
  order; Dungeon_DetectStaircase sends Link to header byte 10 + (n & 3).
  **Ours**: Link keeps his room position and steps 24 px off the stairs;
  the spiral/straight stair animations and the destination's arrival spot
  are not ported.
* NOT done: in-room layer stairs (0x31/0x32, Link on the upper BG1 floor),
  BG1 collision (the secret passage 0x55 has a wall row across its south
  corridor in BG2 attributes, so the bot cannot leave it), pits/holes
  (header byte 9), teleport doors (0x89).

Checked by `tests/zelda_alttp_extract_test.lua` (exit table, cached exit,
hall layout and doorways, 0x61 -> 0x60 transition, house quadrant, room 0x80
stair attributes and destination) and the route bot
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r5/harness/route.lua`.

## The castle escape (round 6)

Found this round (all in `RomMap.lua`, read by `Extract.readRooms`,
cacheVersion 7); the SNES names are zelda3's, the tables were located by
value or by disassembly:

| What | Where | Notes |
|---|---|---|
| Room sprite lists | `0x228DF0` (u32 x rooms) | SNES kDungeonSprites: sort byte, then `y|floor<<7|sub`, `x|sub`, type to 0xFF; type 0xE4 with y 0xFE/0xFD = the previous sprite drops a small/big key; x >= 0xE0 overlord |
| Chest contents | `0x1532FE`, 168 x 3 bytes | u16 room (0x8000 big), u8 SNES receipt item; searched in order per room |
| Overworld pits | areas `0x1537B8` (u16 to 0xFFFF), keys `0x1536F8` (8 u16 per area, 0xFFF0 = any), entrances `0x1537D2` | the GBA's Overworld_GetPitDestination at `0x0808B55C`; area 0x1B -> entrance 0x7D (the secret passage) |
| Overworld secrets | `0x22C624`, u32 x 129 -> 4-byte entries `{u16 pos, u8 type, 0}` to 0xFFFF | pos = (y/16)*128 + (x/16)*2 in the area; 0x80 hole (map16 0xDCC), 0x82 0x212, 0x86 0xDB4 (SNES Overworld_RevealSecret); the castle bush is pos 0x570 type 0x80 |
| Dungeon secrets | `0x2264C8`, u32 x 320 | pots/floors (reader `0x080928F0`, RAM +0x9DA is the room); not used yet |
| map16 -> map8 | `0x155B4E`, 4 words per map16 | the SNES map16 definitions kept for run-time changes: bush 0x36 -> 0xDC7, hole 0xDCC |
| Combat tables | health `0x22769D`, bump `0x227796`, flags4 `0x227988` (243 types); hit boxes `0x171FF4`... (32); kPlayerDamages `0x171E70`; kEnemyDamages `0x17E924`; sword boxes X/W/Y/H `0x171EAB`/`0x171EEC`/`0x171F2D`/`0x171F6E` (65), Tab4 `0x171E9E`; kSpinAttackDelays `0x16808C`; sword OAM offsets Y/X `0x16AB08`/`0x16AD0D` (517) | the sword box is the SNES Player_SetupActionHitBox + CalculateSwordHitBox |
| Entrance planes | entrance `+0x22` (startingBg), `+0x20` palace | Link's level = startingBg >> 4 |

Checked by `tests/zelda_alttp_extract_test.lua` (sprite lists, chests, pit
and secret tables, stair attributes in 0x61/0x62/0x55, lifting the castle
bush and falling into the passage, the uncle's sword, the sword beating the
cell-block guard and its big key) and the route bot
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r6/harness/` (SCENE=route6).

What the port does (`Interior.lua`, `Actors.lua`, `Escape.lua`):
* **Two levels**: the second attribute table (SNES dung_bg1_attr_table) is
  built from the GBA's third map where it holds a floor (two-level rooms such
  as the castle wings), else it is the room's own table. Doors, exits and
  inter-room stairs are written on both.
* **In-room stairs** (SNES Dungeon_LoadObjectAttribute): subtype-2 0x31/0x32
  (north, 0x1E/0x1D) and subtype-3 0x1B/0x1C/0x1D (south, 0x3F/0x3E/0x3D),
  the stair value on both tables, side walls, top/bottom rows per level.
  Walking onto them climbs (Module07_08/10: 0x38 frames up, 0x3C down) and
  swaps the level as the SNES does. **Ours**: the climb moves 0.5 px a frame.
* **Inter-room stairs** keep the level the header's plane bits name; the
  throne room's lower-level stairs (subtype-3 0x29) are handled like 0x21.
* **Locks**: small-key doors (0x1C, 0x1E) open when Link walks into them
  with a key; shutters (0x44) open on the room's tag (1-10 kill enemies, 0x14
  the switch); chests (0x19, big 0x31) get 0x58 + n and give the n-th chest
  table entry with A; the cell lock (0x18) opens with the big key. Each room
  remembers opened doors and chests (`save().rooms`).
* **Sprites** from the cartridge lists with their health, hit box, bump
  damage and key drops; Link's sword uses the cartridge's swing steps and
  hit boxes; the uncle gives the sword (message 14), Zelda follows after the
  cell opens (message 33), the shelf slides, the switch opens the shutter,
  the priest ends the escape (message 23).
* **Overworld**: A lifts a bush, the sword cuts one at swing step 5 (map16
  0x36 -> 0xDC7, or the secret's tile); a pit under Link uses the pit table.

**Ours (honest list)**: the soldier AI (patrol along the subtype's
direction, chase when Link is ahead within 80 px; 0.5 / 1 px a frame), the
sword's damage class (1 for every enemy: enemy_damage_data is not located),
recoil (8 frames at 2 px) and Link's blink (58 frames), A to pull the switch
and to push the shelf (32 px), the 0x4B knights appearing only once Zelda
follows, Zelda's follow delay (20 positions). (Round 7: the castle gate is
entered by the cartridge's big-door rule; game over, dark rooms and the rain
are in, see "Sprites (round 7)".) Not done: carrying/throwing bushes, the
in-bed pose and the uncle walking out, soldiers outside, the music cues.

## Sprites (round 7)

Found by disassembly and by value (all in `RomMap.sprites`, read by
`SprExtract.lua`, import stage "sprites", cacheVersion 8):

| What | Where | Notes |
|---|---|---|
| Sprite sheets | `0x22B324`, 118 u32 -> LZ77 (2 or 4 KiB) | indexed by the SNES sprite-gfx number; not the BG sheet table `0x22B150` |
| OBJ VRAM fill | `0x0812E7B0` (common), `0x0812E8DC` (spriteset) | 2D mapping, 32 tiles a row: rows 0-3 cols 0-15 Link/follower (DMA); rows 4-7 cols 0-15 the misc sheet (RAM +0xC9C, 10 indoors); sheets 6/7 at rows 0-3/4-7 cols 16-31; the spriteset's sheets (kSpriteTilesets[header byte 3 + 0x40], `0x22B624`) at rows 8-11/12-15, cols 0-15/16-31 |
| OAM char | GBA tile = (flags & 1) * 256 + char | flags stay SNES vhoopppN; an SNES page-1 char c becomes (c & 0x8F) or (c & 0x40) >> 2 or (c & 0x30) << 1 |
| Sprite palettes | OBJ rows 0-7 = SNES sprite palettes 0-7 | row 0: blob 0x100 + `0x22BB84`[sp0l], 0x400 + `0x22BC10`[main]; rows 1-4: blob `0x22BBB2`[world] (0x00 LW, 0x40 DW); row 5: 0x200 + `0x22BBB4`[sp5l], sword 0x300 + `0x22BBF4`, shield 0x300 + `0x22BBFE`; row 6: 0x200 + `0x22BBB4`[sp6l], 0x108 + `0x22BB64`[10]; row 7 Link 0xB0. Rows 8-15 are GBA-only (`0x3BF858`) |
| kSpriteInit_Flags3 | `0x22788F` | low nibble = OAM flags (palette, page) |
| Single-sprite chars | tab1 u16 `0x2273B8`, tab2 `0x2272A8` | the GBA's own kSprite_PrepAndDrawSingleLarge tables |
| Guards | head `0x176958`/`0x17695C`/`0x176A58`, body `0x176A8C`-`0x176D00`, weapon `0x176D68`-`0x176DF8`, gfx `0x176918` | Guard_HandleAllAnimation |
| Knife guard | `0x177404`/`0x177414`/`0x17741C`, gfx `0x1773EC` | Recruit_Draw |
| Rat / rope | `0x17CEF8`-`0x17CF20` / `0x17CF3A`, `0x17CF42` | |
| Uncle, priest, Zelda | DMD `0x1792D4` (48), `0x179490` (20), `0x1795B0` (16) + dma `0x179630` | DMD = {s16 x, s16 y, u8 char, u8 flags, u8 0, u8 big} |
| Zelda's tiles | follower table `0x22BB1C`; sheet 0x64 + v >> 11, offset v & 0x7FF (`0x0812F9A8`) | two 0x200-byte rows; head/body by dma_var6/7 |
| Shelf, lever | `0x16FE3A`-`0x16FE4C`; `0x17CEE3` | the lever chars are the SNES 0xEE/0xCE renumbered |

**Ours (honest list)**: the uncle's sword and shield parts and the guards'
page-0 char 0x40 parts (Link's DMA'd weapon tiles) are not drawn; shadows
are not drawn; the 0x6A ball-and-chain guard uses the guard routine (its own
ball-and-chain drawing is not ported); the rope's animation index; walk
frames come from our actors' movement; Zelda following Link uses her
CrystalMaiden frames (the tagalong tables are not read).

**The big door** (`0x0808C044` -> `0x0808BE18`, SNES
Overworld_HandleEntrances / Module09_0C_OpenBigDoor): Link facing up at the
16x16 tile under (x, y + 7) whose top-right map8 cell (& 0x7FF) is 0x149 or
0x169 (or the next tile's top-left 0x549/0x569, block one tile left) opens a
big door; 0x169 only while the story byte RAM +0x165E is 2 or less. The
castle's front gate is 0x169 at (2032, 1792): during the rain it opens when
Link walks into its left half -- the cartridge's way from the courtyard
into the castle. Ours: only the last door frame (map16 0xDBA-0xDBD through
the cartridge's map16 table) is drawn, after the SNES step count.

**Rain** (SNES Overworld_LoadOverlays, OverworldOverlay_HandleRain): overlay
screen 0x9F is the cartridge's rain picture (map 0x9F of the GBA table),
half-added over the field while the escape is on (that is the night
colour), full add on frames 3/36/88 (lightning), half-speed parallax and
256 px jumps every 4 frames. Ours: the GBA's blend registers for it are not
read (LOVE alpha 0.5 and an additive draw stand for the SNES colour math).

**Dark rooms, game over**: header byte 0 bit 0 darkens the BG layers (75 %,
a 40 px light round Link with the lamp); out of hearts fades out and
continues at the entrance with 3 hearts. Ours: the darkness and lamp light,
the death spin and the game-over menu are not the cartridge's.

## Item menu (round 8)

Found by disassembly and checked by running the cartridge's own routines in
a scratch Thumb interpreter (`r8/py/thumb.py`, never in the repo):

| What | Where | Notes |
|---|---|---|
| Main module table | `0x14CA5C` (30 u32) | the SNES kMainRouting order; 0x0E interface `0x0806A719`, two GBA-only modules 0x1C/0x1D |
| Interface submodules | `0x14DADC` | 1 item menu `0x080AA809`, 3 dungeon map `0x080B6409`, 7 overworld map `0x080B33C9` |
| Item menu states | `0x16E004` (8) | load `0x080AABC0`, draw `0x080AAC24`, pick `0x080A9EA8`, slide `0x080A9F20`, wait `0x080A9F5C`, choose `0x080AA4F8`, close `0x080AA920`/`0x080AA688` |
| Menu map | LZ77 `0x3BFC58` -> `0x06009000` | pre-rendered 32x32 HUD-layer map (frames, boxes); language tiles `0x16BE94`[lang] -> tile 0x180 |
| Upload list | RAM `0x02000400` | {u16 VRAM offset, u16 count \| 0x8000 down \| 0x4000 fill, words}, drawn by `0x08068E7C` |
| Grid | positions `0x16DEE0` (24 u16), icons per slot (RomMap.menu.gridTab), bottles `0x16B9B8` | slot n = save byte `0x0200231F + n` (the GBA keeps the items in grid order); bombs draw level 1 when non-zero |
| Names | `0x16DF40`[lang] (24 x 16 words) | exceptions: bottles `0x16DF5C`, powder `0x16DF78`, slot 23 `0x16DF94`, bow `0x16DFCC` |
| Boxes | equipment `0x080A97F8`, ability `0x080A8D70`, pendants `0x080A93B8` | word tables `0x16BA50`-`0x16BB58` |
| Keys | RAM +0x534 newly pressed GBA keys | SELECT (4) opens it from play (`0x0806CE54`); A/B/SELECT close; L (0x200) opens the dungeon map |

`Menu.lua` ports the states, the grid moves (6 x 4, skipping empty slots,
the SNES new-style wrap), the chosen item's icon and name, the blinking
cursor (`timer & 0x10`) and the slide (BG3 y 4 -> -184, 8 px a frame).
Checked against the interpreter for 6 inventories and input sequences:
identical map words (harness `SCENE=menucmp`). Not ported: crystals,
dungeon map/compass/big key in the equipment box, the ability box's
language labels, the HUD item box and using the chosen item.

## Overworld map (round 8)

Module 0x0E/7, states `0x16ED14`; load `0x080B1DB4`, control
`0x080B1EFC`, centre `0x080B198C`. Mode 1, BG2 affine: tiles `0x28A7E0`
(0x4000 bytes of 8bpp), map `0x3BFEF8` (LW) / `0x3C0EF8` (DW), 64x64 bytes,
128 colours `0x3BFA58` / `0x3BFB58`. The HBlank handler `0x08068B7C` (RAM
+0x982 == 3) sets per line PA = s, BG2X = X0*256 - 120*s, BG2Y = Y0*256 +
1.5*s*line from the zoom table (`0x16EB34` zoomed in, `0x16E974` out, 230
u16 each). Scroll steps/limits `0x16ECF4`/`0x16ED04`, zoomed-out centre
(0xFA, 0x6E). `OwMap.lua` draws it per scanline. Ours: the Link marker (his
head cell, placed by inverting the line formula) and no fade.

## Teleport doors (round 8)

Door type 0x46 (SNES kDoorType_WarpRoomDoor, attribute 0x89 in its doorway):
leaving west through one goes to header byte 12, east to byte 13, not to the
next room. The castle's 0x50/0x52 <-> 0x01 are such doors; 0x01's spiral
stairs (subtype-2 0x3B) go down to 0x72 (header byte 10). `Interior:cross`
and the harness planner use them.

**The east wing question (round 7)**: 0x60 and 0x62 share one header
(`0x163A44`) and have no stair objects; 0x62's south door (type 0, pos 6)
is what leads down to 0x72's north (a 0x1C key door), and the way from the
hall to the basement is 0x61 -> 0x51 -> 0x52 -(teleport)-> 0x01 -(spiral)->
0x72. Still open: how 0x72 joins 0x71/0x70 (0x72's top chamber has side
and bottom door pictures that are not in its door list `0x16123A`, only
`0x1C70`), so the bot does not reach the cell block yet.

## Bug round (user report): sword, chests, pots

**Link's sword and shield** (`Weapon.lua`, tables `RomMap.weapon`, read at
import into `t.weapon`). The SNES LinkOam_Main the GBA kept (zelda3
`player_oam.c`) with the GBA's own tables, found by value: the pose index
`r2 = playerOamOffs[dir * 40 + yt] + rt` (yt 0 walk, 0x27 sword swing with
rt = the swing step 0-8, 0x10 lift, 0x0D carry, 0x0E throw); the GBA's pose
tables have 517 entries (SNES 511: it inserts 6 poses), so
`linkGfxIndices` is now read with 517 entries too (with 511, poses 511-516,
e.g. some right-facing swing frames, had no body). Sword: selector
`swordSel[r2]` (0xFF none; >= 29 are rods etc., not drawn), three OAM words
`swordTiles[j * 3 ..]` (SNES `vhoopppc cccccccc`; the GBA's second OBJ row is
char + 0x20) at `(swordX[r2], swordY[r2])`, 16x16 when `swordSize[j]` = 2,
tiles DMA'd from the weapon strip at `swordDma[swordDmaSel[j] / 2]`
(0x22A9DC, GBA strip base 0x8380 = SNES 0x9000). Shield: `shieldSel`,
`shieldTiles`, `(shieldX, shieldY - 1)`, `shieldDma` (0x22A9EC), one 16x16.
Draw order by the OAM slot tables (`spriteLocs[r2]` -> sword / body /
shield slot; lower slot in front). The strip itself is built the SNES way
(DecompressSwordGraphics): sprite sheets 0x5E-0x5F of the GBA's sheet
table, the sword's 12 tiles from its type offset plus the 12 under them,
the shield's 6 + 6 (offsets kSwordTypeToGfxOffs / kShieldTypeToGfxOffs,
3bpp bytes / 24). Colours: sprite palette 5 columns 8-11 (sword) and 12-15
(shield) from the sprite palette loader's sword/shield tables. The sword
shows only while swinging (PlayerOam_WantInvokeSword), the shield whenever
Link has it. The uncle's sword and shield: his draw list's page-0 chars
below 0x40 from the same strip, frames `uncleDma3/4[dir * 2 + frame]`
(0x179454 / 0x17945C, the GBA's kUncleDraw_Dma3/4).

**Chests** (`Interior:openChest`, `Escape.lua` receipt). The dungeon
object tile table (SNES kDungeonObjectTiles in GBA map words; the closed
chest at SNES offset 0x149C is GBA 0x1659BC) gives the open chest
(SrcPtr 0x14A4: 4 words column-major UL LL UR LR) and the open big chest
(0x14C4: 4 columns of 3); opening patches the room's BG2 words (also when a
remembered chest is reloaded). The item (zelda3 AncillaAdd_ItemReceipt,
method 1): Link stands still while it rises from the chest (y velocity -1
a frame to -8/16 px while the 0x38-frame timer is above 24), then the
cartridge's message (kReceiveItemMsgs at 0x17F288, 76 u16, values through
`Text.bmgIndex`: the lamp -> "You got the Lamp!"); the item goes when the
text closes. OURS: the rising item is its item-menu icon (black left out);
the receipt sprite sheet (kReceiveItemGfx) and the chest offsets
kReceiveItem_Tab2/3 are not ported.

**Pots, bushes, rocks** (`Carry.lua`, `Interior:markPots`). Pots are the
subtype-3 object 0x2F (RoomDraw_SinglePot): their 2x2 cells get attribute
0x70 + n (manipulable). A in front (kDungeon_QueryIfTileLiftable: (7,3)
up, (7,24) down, (-3,14) left, (16,14) right) lifts: the cells get the
routine's replacement words (literals 0x0807CBCC.., GBA 0x310E 0x311E
0x350E 0x351E) and become floor, the room's secrets entry at the pot's
tilemap position * 2 (+0x2000 on BG1; table 0x2264C8, now read into
`roomIdx.secrets`) is what it hid (a small key, byte 8, appears as the key
sprite; others are counted only, drops are not ported). Outdoors A lifts
the small objects the cartridge replaces (bush 0x36 -> 0xDC7 ..., with the
secret under them) on liftable attributes 0x50-0x5D, with the gloves
kGetBestActionToPerformOnTile_a asks for (0x52/0x53 rocks the Power
Glove, ...). Lift: 6 + 7 + 7 frames on lift poses 0-2 (kLiftTab2, row
0x10); carry row 0x0D; A throws (row 0x0E, 2 x 4 frames). OURS: the thrown
object (the SNES's thrown-terrain sprite is not ported) is the tile's own
16x16 picture, held 14 px above Link, thrown 4 px a frame from 14 px up
falling 0.25 px/frame per frame until it lands or meets a wall; no shatter
pieces, no damage to enemies. Lifted pots are remembered per room.

**View cache** (`View.lua`): screens are evicted least recently used, and
a screen dropped from outside (a cut bush) leaves no stale entry behind
(before, its stale entry could later release the reloaded pictures of a
screen still in use).

## Castle stairs and the way to the cell block (round 9)

The round-8 question ("0x72's top chamber shows door pictures that are not
in its door list") is settled: there are no missing doors. The side
pictures in 0x72's top chamber (and along 0x81/0x82's walls) are wall
torches drawn into the pre-rendered maps; the chamber's bottom door is the
mirror of 0x1C70 (a key door between quadrants, drawn on both sides as the
SNES draws doors on inner quadrant edges). The real connections, all from
the cartridge's own lists:

| From | To | How |
|---|---|---|
| 0x61 hall | 0x51 throne room | straight stairs 0x38 (row 4) -> 0x51's 0x39 (row 58) |
| 0x51 | 0x50 / 0x52 | room edges |
| 0x50 / 0x52 | 0x01 | teleport doors (round 8) |
| 0x01 | 0x72 top chamber | spiral stairs 0x3B -> header byte 10 |
| 0x72 top chamber | 0x72 corridor | key door 0x1C70 (the guard 0x41 at 272,96 drops the key) |
| 0x72 corridor | 0x72 lower floor | in-room stairs 0x31 (0x1E, swaps the level) |
| 0x72 lower floor | 0x82 -> 0x81 | room edges |
| 0x81 | 0x71 | 0x81's top passage (door 0x4030) up into 0x71's lower-left chamber |
| 0x71 | 0x70 | key door 0x1C60, then spiral stairs 0x3B -> header byte 10 |
| 0x70 | 0x80 | spiral stairs 0x39 -> header byte 11 |

Two engine fixes found on the way (`Game:startRoomScroll`,
`Interior:spiralLanding` / `straightLanding`):
* straight stairs 0x38 / 0x39 are an inter-room transition (SNES
  Dungeon_StartInterRoomTrans_Up/Down): Link comes out past the
  destination's own stairs (the bottom of the room above / the top of the
  room below), not 24 px from where he was (that put him at the top of the
  throne room);
* spiral stairs 0x5E / 0x5F land Link below the destination's spiral stair,
  facing down (SNES RepositionLinkAfterSpiralStairs). OURS: the landing walk
  (SpiralStairs_FindLandingSpot) is not stepped frame by frame.

In the two-level basement rooms the GBA's BG2 attributes are 0x1C
(TileBehavior_OverlayMask_1C, walkable) wherever the lower floor shows
through; the lower floor's walls, floor and pits (0x20) are on the third
layer. Link only reaches the lower floor through the in-room stairs.

## Drops (round 9)

What a cut or lifted bush / grass / rock or a lifted pot leaves behind
(`Drops.lua`, tables `RomMap.drops` read into `t.drops`, cacheVersion 11).
Ported from the GBA's own routines, checked by running them in the scratch
Thumb interpreter (`r9/py/golden_drops.py`) for 1000 random inputs: 1000 /
1000 identical (`tests/zelda_alttp_drops_test.lua`).

| Routine | GBA | What it does |
|---|---|---|
| GetRandomNumber | `0x080CEFE0` | r = VCOUNT + frame counter (RAM +0x996) + seed (RAM +0x15DE); seed = r |
| throwable-terrain tail | `0x080C2A6A` | secret 0xFF (a hole/stairs) -> nothing; outdoors with no secret and terrain kind 2 (bush) or 3 (thick grass) -> the substitution |
| Overworld_SubstituteAlternateSecret | `0x080CA754` | rng & 1 -> keep; > 3 active sprites (not 0x6C, the terrain piece counts) -> keep; story progress <= 1 -> keep; counter (RAM +0xEC9) + 1, j = counter & 7 (+8 Dark World); secret = `0x172888`[j] unless `0x172848`[area & 63] & `0x172898`[j] |
| Sprite_SpawnSecret | `0x080C2534` | outdoors rng & 8 -> nothing; secret 4 -> 19 + (rng & 3); type = `0x171DCB`[secret - 1]; ai / x offset / z velocity from `0x171DE1` / `0x171DF7` / `0x171E23`; pickup delay 0x20 |
| (GBA only) | `0x080C382C` | no bow (inventory 0x02002320 = 0): arrows 0xE1 / 0xE2 become green / blue rupees 0xD9 / 0xDA |

Differences from the SNES found this way: the substitution counter is
pre-incremented, its area/mask tables moved up four bits, the z-velocity
table's entry 12 is 0x10, and the bow rule.

The secret: outdoors the overworld secrets table (`0x22C624`, values below
0x80 are what the tile hides, 0x80+ a hole/stairs); indoors the pot's entry
in `0x2264C8`. Terrain kinds: the sword cuts 0x36 bush (2), 0x72A dark bush
(4), 0x37E thick grass (3) only; lifting uses kLink_Lift_tab by attribute
(0x50 bush 2, 0x52 rock 1, 0x54 pot 0, ...). Before Zelda reaches the
sanctuary (progress <= 1) an empty bush never drops anything.

The dropped items (0xD8-0xE6) move and are picked up as zelda3
Sprite_Absorbable_Main / Sprite_D8_Heart / Sprite_HandleAbsorptionByPlayer:
z velocity in 1/16 px, -2 a frame, bounces at half speed until below 9;
the heart rises and sways down; pickup after the 0x20-frame delay; the
lifetime 255 counts down every other frame, blinks below 0x28, gone at 0.
Drawn with the cartridge's absorbable tables (`0x1720D4` kind, `0x1720E3`
numbered, `0x1720F2`.. numbered X/Y/char/ext) and the single-sprite char
tables; the rupee's two DMA'd chars (0x0B / 0x2B) come from sprite sheet 96
with the SNES shimmer timing (frames 0,1,2,0,1,2 for 14,4,6,16,6,8).
OURS: VCOUNT is modelled ((frame * 37 + call * 73) % 228); the pickup
boxes are ours (Link 10x12, item 8x8). Round 10: the heart (sheet 0 tile
0x29) and the small shadow are drawn, and the enemies a secret holds spawn
(see "Enemies a secret holds" below; 0xD3/0xD4 still do not).

## Combat, doors and stairs (round 10)

What changed in the engine while the route bot went from the 0x82 guards to
the sanctuary. Each item is the cartridge's rule (zelda3 names, GBA tables
found by value) unless marked OURS.

| What | Rule | Where |
|---|---|---|
| Corner nudging | HandlePushingBonkingSnaps_Y/_X + HandleNudging: walking straight into a wall that only one outer probe touches (middle probe free), Link slides 1 px a frame to the free side while his other coordinate is off the 8 px grid; undone if the cells beside him are solid | `Link:nudge` |
| Sword knockback | Sprite_AttemptZapDamage: recoil away from Link at 0x50 (B held < 9 frames) else 0x40, 1/16 px; Sprite_ReturnIfRecoiling: sprite_F = 15 counts down, moves on frames where `frame & masks[F >> 2] == 0` (masks `0x171DC0`, read at import), a wall zeroes that axis, a strong recoil ends stunned 16 frames (F = 144 -> 128); no AI and no contact damage while recoiling | `Actors:recoilStep`, `A.project` (Sprite_ProjectSpeedTowardsLink) |
| Link's knockback | Sprite_AttemptDamageToLinkPlusRecoil: 19 frames at speed 24 (1/16 px) away from the sprite, rooms and overworld | `Escape hurtLink` |
| Kill tags | kDungTagroutines 1-9: the tag's quadrant / half test on Link's position, then RoomTag_QuadrantTrigger opens all trapdoors when Sprite_CheckIfScreenIsClear finds no live sprite on screen. OURS: "on screen" = in Link's 256 x 256 quadrant | `Actors:update` |
| Trapdoors on the way in | Dungeon_CheckAdjacentRoomsForOpenDoors: a 0x44 trapdoor on the door Link comes through starts up; Dungeon_InterRoomTrans_State15 puts them down at the end of the transition. OURS: they go down once Link's body is past the door's cells | `Interior:entryShutters`, `Interior:closeLock`, `Escape` |
| Lower-level doors | OURS (how the two layers' cells are found): a door whose anchor is walkable above and solid below is a lower-level door and scans the lower layer (at most 4 cells; 0x81 -> 0x71's trapdoor); an upper door's lock also takes the lower layer's walls along the span its upper cells cover plus 2 cells (0x71's door between its south quadrants) | `Interior:markRoomDoors` |
| Spiral landing level | OURS: Link lands on the layer of the destination's spiral stair (the upper one when both carry it). The header plane alone (plane 2 for 0x72 -> 0x01) put Link on 0x01's walled-in lower layer; the SNES resolves plane 2 through RepositionLinkAfterSpiralStairs' "3" and the landing walk, not ported | `Interior:spiralLanding`, `Game:updateRoom` |
| Zelda follower crash | the follower's facing is Link's 0/2/4/6; the draw wanted 0-3, so Zelda facing left/right crashed (index nil) | `Escape` drawing |
| The throne room's shelf | Sprite_EE_MovableMantle: it moves only while Link, with Zelda following and the lamp, walks right against it (link_actual_vel_x >= 24): G counts every other frame, from 8 it slides at x velocity 2 (1/16 px) until G = 0x90 (34 px). Was: A next to it with Zelda, 32 px. It blocks with its cartridge hit box. OURS: no layer test (the dais stairs put Link on our lower layer), not solid once moved | `Actors:mantle`, `Actors:solidAt` |
| A on actors | only on Link's level (a lower-floor guard under the shelf took the A press) | `Actors:facing` |

Round 11 replaced two of these rows: "Lower-level doors" (now the
cartridge's door attributes and slots) and "Spiral landing level" (now the
header plane's level, which is right with the cartridge's two tables); the
shelf is pushed on the upper level (see "Layers, doors and stairs (round
11)").

0x01's spiral stairs (round-9 question): `Dungeon_DetectStaircase` reads the
cell at `link_x & 0x1F8`, so the stairs (cells 31-32) take Link only at x
248..263. Walking up at x 236..244 Link stopped at the wall row beside them,
which is why `scene_r9stairs` did not climb; with the nudge, x 244..260 slide
onto them (the cartridge's behaviour); x 264 (on the grid) does not.

## Enemies a secret holds, hearts, shadows, thrown objects (round 10)

* **Enemies** (`Actors.spawnSecret`, outdoors `OwActors.lua`): what
  Sprite_SpawnSecret puts out besides items now spawns: the soldiers 0x41 /
  0x42 (straight into the chase, flashing 32 frames, sprite_hit_timer 160),
  the bee 0x79 (Bee_Main: 16 px up, re-aims at Link + (rng & 3) * 5 every k
  + A frames at speed 20, A 32 -> 16, harmless and immune for its first 32
  frames), the hoarder 0x3E (Sprite_Hoarder_Frantic: flees at 16, turns at
  walls, gone after 192 counts), the cucco 0x0B (calm / hop, flees when hit,
  takes no damage). Indoors they join the room's actors. The overworld
  actors use the room actor code over an adapter (walls from the overworld
  attributes) and are dropped on an area change. OURS: the cucco's calm
  velocities and the frame-seeded random byte (not the cartridge RNG); no
  avenging flock; 0xD3 / 0xD4 still not spawned. Round 11: the cucco's
  calm hops are the cartridge's (tables and RNG, see "Layers, doors and
  stairs (round 11)").
* **Overworld sprite graphics**: the area's sprite set
  (`overworld_sprite_gfx[screen]` from `owSprGfxLW[phase]` / `owSprGfxDW`
  into kSpriteTilesets) and palettes 5/6 (`owSprPalettes[screen]` ->
  kOwSprPalInfo `0x22BD98` -> sprite aux sets) are loaded for drops,
  shadows and actors (`Sprites:setOverworld(dark, gfx, palSet)`).
* **The drop heart** (and the small shadow): sprite sheet 0 is copied to OBJ
  rows 0-3 (cols 0-15) by `0x0812EED8` (four 0x200-byte rows to
  `0x06010000/0400/0800/0C00`); rows 0-1 are overwritten by Link's DMA, rows
  2-3 stay: GBA char 0x49 = sheet 0 tile 0x29 (the heart), 0x68 = tile 0x38
  (the small shadow, 8x8 at y + a + 1, a = 2 for SingleSmall). Hearts now
  draw in cartridge art.
* **Lifted / thrown objects**: drawn as the cartridge's sprite 0xEC
  (Sprite_EC_ThrownItem): char kThrowableScenery_Char `0x1778B4`[what + 6 if
  indoors + Dark World >= 2], palette kThrowableScenery_Flags `0x1778C0`
  (a bush indoors 0x50). The big rocks (6-8) keep the tile picture.

Checked by `tests/zelda_alttp_combat_test.lua` and the real-runtime scenes
`scene_stairs01`, `scene_r10secrets`, `scene_r10castle` in
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r10/real/`.

## Layers, doors and stairs (round 11)

The cartridge's two levels in a room, as the GBA builds them. Everything
here is read from the cartridge or ported from its routines unless marked
OURS.

| What | Rule | Where |
|---|---|---|
| The two attribute tables | `0x0808273C` (SNES Dungeon_LoadBasicAttribute): the upper level (RAM `0x0200CBA0`, SNES dung_bg2_attr_table) from the map loaded to `0x02018000` (RomMap.roomBg2), the lower level (`0x0200DBA0`, dung_bg1_attr_table) from the map at `0x0201A000` (RomMap.roomBg3, our "bg3"); attribute = table[word & 0x3FF], 0x10-0x1B (slopes) take the word's flip bits. The map at `0x0201C000` ("bg1") is drawn but never read for collision. Was: the lower table from bg3 only when it had 3+ kinds of cell, else a copy of the upper one | `Interior:loadRoom` |
| Door attributes | RoomDraw_Door_North/South/West/East + RoomDraw_FlagDoorsAndGetFinalType, then Dungeon_LoadSingleDoorAttribute (the GBA's `0x08082ADC` writes the same cells): door slots in list order (0x12 / 0x14 / 0x16 / 0x30 markers take none), north / west doors at positions 6-11 draw their mirror in slot \| 8; the doorway pairs from kTileAttrsByDoor (`0x16784C`, read at import) over the SNES spans (alpha: regular kinds, beta: long kinds); high-range doors (>= 0x40), south 0x04 / 0x0C and waterfall doors go on the lower level's table; a locked door holds 0xF0 + slot on its middle cells until it opens. Was: our wall scan, on both tables | `Interior:doorSlots`, `doorWrites`, `loadDoorAttributes` |
| Layer toggles | Dungeon_LoadSingleDoorTileAttribute: a type-0x16 marker turns the doorway beside it into 0x90-0x9F (0x14: 0xA0-0xAF); TileBehavior_LayerToggleShutterDoor sets room_transitioning_flags & 1 and Dungeon_StartInterRoomTrans_* swaps link_is_on_lower_level. OURS: the SNES latches the flag while Link is in the doorway; here the cells 32 px behind to 64 px ahead of Link along his way out are checked | `Interior:layerToggleAt`, `Game:startRoomScroll` |
| Indoor ledges | TileDetect: 0x28 is a vertical ledge, 0x2A / 0x2B horizontal; all three probe points on it for 20 frames (RunLedgeHopTimer) hop Link over it, and on landing Dungeon_HandleLayerChange puts him on the lower level unless the room's in-room stairs are of kind 2. OURS: the hop's arc and length (the first spot 8-64 px on that fits on the lower level); kind 0's room + 16 is not ported | `Game:indoorLedge` |
| South straight stairs | The 0x229 / 0x221 stairs put their number ABOVE the 0x39 row, so Dungeon_DetectStaircase never matches walking down; the cartridge's Link walks on through the stair passage (floor only on the lower level) and leaves by the room's bottom edge. OURS: the 0x39 row starts that transition at once (to the header's destination for the number above, the room below for 0x51) | `Interior:staircase` |
| Snap to walls | A move a wall stops still brings Link up against it (HandlePushingBonkingSnaps); here the whole pixels short of the blocked target are walked one by one. Without it Link stopped 1 px short of the throne room's wall and slid under the shelf | `Link:snapTo` |
| Knockback and stairs | OURS: knockback does not carry Link across in-room stairs (the cartridge's recoil runs its tile detection; ours carried him past 0x72's stairs onto the other level's side) | `Escape` recoil |
| Opened doors | The opened door is drawn with kDoorTypeSrcData[kDoorTypeRemap[type]] (the GBA's pointer tables `0x16798C` / `0x167A5C` / `0x167B1C` / `0x167BDC`, remap `0x1677FC`, read at import): north / south 4 columns of 3 words (south from row 1), west / east 3 of 4 (east from column 1), the high-range doors' inner part on the lower layer's map; closing takes the words off again (the pre-rendered map shows the closed door). The two-way and trap shutters we keep open show their opened picture. OURS: the GBA's high-priority copy layer (`0x0201C000`) is not updated | `Interior:drawDoor`, `openLock`, `closeLock` |

What this fixed: Link no longer walks in the empty space outside a room's
walls on the lower level (the old door scan opened walls there and the old
lower table was a copy of the upper one in some rooms); 0x41's corridor is
on the upper level (its lower level is wall); the castle's way down is the
cartridge's: 0x61's west doorway (layer toggle) -> 0x60 on the lower level
-> 0x50 -> teleport door -> 0x01 -> spiral stairs -> 0x72, and the route bot
no longer stalls at 0x71 (it came there through the void beside 0x81 /
0x82; it now comes in through 0x71's south trapdoor).

**The cucco** (round 11): Cucco_Calm is the GBA's `0x080EA700`: when the
timer is out, j = rng & 15 picks the hop's x / y velocities from the
cartridge's tables (`0x177D54` / `0x177D64`, read at import) and the timer
becomes (rng & 0x1F) + 16, both from the cartridge's random routine
(`0x080CEFE0`, `Drops.rng`); Chicken_Hopping moves it every other frame by
slot parity, z velocity 10 falling 2 a frame, a wall ends the hop, and on
landing with the timer out it waits 32 frames.

**The front end** (round 11, findings): the GBA's title runs in module 0
(`0x0812DA15`, state table `0x22B0D4`). Run in the scratch Thumb
interpreter (`r11/py/title.py`, the module dispatcher `0x14CA5C` called once
a frame): states 1-2 load the title graphics, 3-4 are the intro (skipped
with A / START / SELECT once `0x02002434` is set), 6-7 the title (logo over
the castle and the lake), 12 after START; then modules 1 (`0x0806BEA5`: the
file's RAM set up from the save), 2 and 3 (stubs that only advance), 4
(`0x0806A411`) follow one frame each and module 0x14 (`0x080B7ACD`) starts
the game. So the cartridge's ALttP has no SNES-style file select, copy or
erase screen between its title and the game; where the file and its name
come from on the GBA (its shared front end) is not located yet.

Round 12 findings (not ported): AgbMain is `0x0800B084` (from the header's
`0x08000100`); its loop reads keys (`0x0800BBA0`, KEYINPUT into `0x03000510`
/ `0x03000BD0`) and calls the top-level task `0x0842731C[*0x03006D10]` (12
tasks: `0x0800D4F1`, `0x0803815D`, `0x08038169`, `0x080310B5`, `0x080317F5`,
`0x0803006D`, `0x0803074D`, `0x0802DC61`, `0x0800F809`, `0x0802E765`,
`0x08037DE9`, `0x08031FD9`) -- the shared front end (logos, game choice,
files) and the two games. The ALttP game's RAM mirror of the SNES SRAM is
`0x02002000` (SNES `$7EF000`): its init `0x08069140` clears `0x02002000-
0x020025FF` but keeps `0x02002434` (the intro-skip / file flag) and
`0x020023F3`. The save medium is EEPROM (`0x0D000000`, routines read
`0x08135DC4` / write `0x08135E74`, 8 bytes a block; their config at
`*0x03000020`). Module 4 (`0x0806A411`) goes to module 0x14 (new game) when
`0x02002434` is 0, else to module 5 (load) with `+0xB52` = 1. The boot was
run in the scratch interpreter (`r12/py/boot.py`, EEPROM and VCOUNT HLE'd)
but did not reach a drawn frame this round. Where the player's name and the
slot live in EEPROM is not located.

Checked by `tests/zelda_alttp_layers_test.lua` and the route bot and real
app runs in `G:/Gen2Recomped/scratch_claude/zelda/alttp/r11/`.

## Starting points, continues and exits (round 12)

**Starting points** (`RomMap.startPoints` `0x150D24`, 7 records of 0x2C bytes
in the entrance format, read at import as `roomIdx.startPoints`): 0 Link's
house 0x104, 1 the sanctuary 0x12, 2 the prison 0x80 (Link at 352, 69 under
Zelda's cell), 3 the uncle's passage 0x55, 4 the throne room 0x51, 5 the old
man's cave 0xF0, 6 his home 0xE4. `progress.startPoint` follows the SNES
`which_starting_point`: 3 when the uncle gives the sword, 2 when Zelda
follows (TransitionToTagalong), 4 while Link pushes the shelf
(Sprite_EE_MovableMantle), 1 when the priest greets Zelda.

**Game over** (SNES Death_Func, messaging.c): indoors, CONTINUE keeps
death_var4 unless Link is in a palace without Zelda following, so with Zelda
(or outside a palace) Link continues at the starting point
(`G:enterStart`), in a palace without her at the entrance he came in by.
Before round 12 a death with Zelda following sent Link to the hall's front
door (entrance 4) and the next step out took him outside: that was the
harness's "back up to 0x51 with Zelda" failure (the bot died to 0x82's
respawned blue guard on the way back).

**Save and continue**: SAVE AND QUIT clears death_var4/5, so a saved file
continues at the starting point wherever Link saved (`save().alttp.resume`,
`G:resumeIndoors` after START at the title): with Zelda in the prison or
the throne room, after the escape in the sanctuary in front of the priest.
OURS: the SNES location menu after the escape (Link's house / the
sanctuary, `kLocationMenuStartPos`) is not shown; the last starting point is
used. Saves without a starting point keep the old outdoor spot.

**Leaving by an exit door** (SNES OpenSpotlight_Next2,
Module09_09_OpenBigDoorFromExiting, Module09_0A_WalkFromExiting_FacingDown):
the exit table's door words follow its 7 coordinate arrays and two i16
arrays: `kExitData_NormalDoor` `0x15083C`, `kExitData_FancyDoor` `0x1508DA`
(79 u16 each; Link's house 0x816, the castle rooms 0x60 / 0x61 / 0x62
0x8124 / 0x87BE / 0x8158, the sanctuary 0x1AA, 0xE0 0x82BE). Link walks
16 px then 3 more; with a fancy door the door first opens (the map16 block
at `x << 1 | y << 7` in the exit's area; counter from 0x18 for a palace
door, 9 frames, else from 0, 33 frames) and the walk is 36 + 3 px. Before
this the castle's exit left Link 20 px inside the castle's wall above its
door (exit y 1740, door 1776).

**Doors indoors** (`Doors.lua`, user report: doors inconsistent). The
old walker used a boolean grid with Link's centre crossing the camera area,
so doorways had no pull, off-centre approaches stuck on the frame, and room
changes happened at the wrong distance. Ported from the SNES player code
(zelda3 player.c / tile_detect.c / dungeon.c); the GBA's own
HandleDoorTransitions `0x0809B0DC` was read in the ROM and has the same
tests (+28 / -18 / +21 / -8; link_y `+0x16C0`, link_x `+0x16C4`, direction
`+0x16CC`, is_standing_in_doorway `+0x172C`):
- probes: TileDetect_Movement_Y rows y + 8 (up) / y + 24 (down) at x + 0, 8,
  15; _X columns x + 0 / x + 15 at y + 8, 16, 23; both axes move first, then
  Y is checked, then X;
- doorway attributes 0x80-0x8F, 0x90-0xAF set R14 bits 4-6 (some also 8-10);
  a probe in the doorway marks Link as standing in it (1 north/south, 2
  east/west); one outer probe on the wall beside it snaps him back and
  slides him 1 px a frame towards the doorway (CalculateSnapScratch, with
  the x & 7 == 1 snap); all three in it let him through;
- across a doorway (left/right in a north/south one) Link is moved along it
  (ChangeAxisOfPerpendicularDoorMovement_X/_Y, HandleNudgingInADoor);
- elsewhere HandlePushingBonkingSnaps: snap to the wall, the 1 px corner
  slide off the 8 px grid checked by HandleNudging (kLink_Move_Helper6);
- diagonals: Player_LimitDirections_Inner drops the component a wall (slope
  probes y + 7 / y + 24, x - 1 / x + 16) blocks;
- transitions: in a doorway when y + 28 reaches the next page (down), y - 18
  leaves the page (up), x + 21 / x - 8 (right / left), with the start shifts
  (+16 down, +8 right, -8 left); the exit to the overworld is that move with
  0x8E under Link (x + 8, y + 20); not in a doorway, an open room edge at
  y & 0x1FF < 4 / >= 476, x < 8 / >= 489 (Dungeon_TryScreenEdgeTransition);
- landing: SubtileTransitionCalculateLanding + MoveLinkOutDoor: the low byte
  of Link's coordinate from kStaircaseTab2 by the attribute under his centre
  after the scroll's own 4 px steps (kStaircaseTab4: 13 / 13 / 6 / 7 steps,
  52 px vertically, 24 right, 28 left), walked 2 px a frame.
Tested by `tests/zelda_alttp_doors_test.lua` (sweeps every 2 px across the
house exit, the hall's exit and west door, 0x62's north door, 0x81's
trapdoor; the landing; walking across a doorway; the house door from
outside). Diagonal into a doorway: by the code Link either slides past
along the wall or stops at the door's line, depending on his sub-pixel
(not checked on hardware).

**The overworld door** (0x0808C044 / 0x0808BB88, SNES Overworld_UseEntrance):
the 16x16 tile under (link_x, link_y + 7), x from link_x & 0xFFF0 (read in
the GBA code), its bottom map8 pair in the door table, the position in the
entrance table. Link's house door is only its right tile (pair 0xC5/0xC4,
x 2240-2255). The doorstep (attribute 0x02) stops Link one tile below the
door's tile, so the tile above is tested too (OURS: the cartridge's overworld
collision at doorsteps is not traced). Before round 12 the test reached 48 px
ahead (the entrance fired before Link reached the door) and needed Link to
face up (a diagonal approach did not enter).

**Input** (milestone 1 of round 12): the real-app failure at the cell was not
an input bug. `src/core/Input` latches a press until the next fixed step
(`pressQueue`), so a one-frame key tap reaches `wasPressed` even when a
LOVE frame runs no game tick (59.73 Hz game on a 60 Hz loop). A real-key
scene (`r12/real/harness/scene_r12cell.lua`) beats the ball-and-chain guard
with 8 swings from 9 one-frame X taps, takes the big key, opens the cell and
has Zelda follow (4/0). In the round-11 run the fight ran 6006 frames with
no damage either way (the guard was never in reach; its stall give-up does
not apply to a key carrier); the exact cause in that run was not reproduced:
three later real-app runs of the same bot beat the guard (222, 567 and 590
frames).

## Guards, kill memory and prizes (round 13)

**The 0x71 loop** (round 12's open issue): 0x71's lower-level guard 0x42
(spawn 96,384) saw Link on the upper level with our old guard AI, came to
the foot of the in-room stairs (cells 15-16, rows 44-45) and stood on them;
Link, knocked onto their edge, could not be knocked back (our round-11
stairs rule refused every move) and was hit every 58 frames until he died.
Engine gaps, not the bot and not the door port (stairs: `climb72` and the
route's spiral landings are the r11 values).

**Guard.lua**: the sword guards 0x41-0x43 indoors run the cartridge's
routine (zelda3 Guard_Main 0x85C227; every table found by value in the GBA
ROM and read at import into `roomIdx.combat`):
- SpritePrep_StandardGuard: subtype 1-4 picks the patrol direction (D =
  (subtype & 7) - 1 ^ 1), 5-7 the wall-following routes (kSoldierB_*);
- state 0 waits, then picks a direction (subtype: back and forth for
  kSoldier_Delay; else random, 0x28 + (rng & 0x3F) frames); state 1 walks
  at kSoldier_Xvel / _Yvel (8 = 0.5 px a frame, the timer slowed to every
  other frame), turning at walls; state 2 looks round 160 frames
  (kSoldier_HeadDirs);
- every 4 frames by slot it sends a probe from x + 8, y + 4: 16 px a frame
  in one of 64 directions (kSpawnProbe_Xvel / _Yvel, sweeping the half
  circle it faces by kSprite_SpawnProbeStaggered_Tab), gone on a solid cell
  (kSprite_SimplifiedTileAttr >= 1, not 9) or 256 px off the camera; within
  16 px of Link ON THE GUARD'S LEVEL it alerts it (state 3, 16 frames);
- touching Link (every 4th frame by slot, same level) alerts it for 32
  frames; a sword hit (sprite_F >= 4) puts it in state 4 for 128;
- state 3 stands facing Link; state 4 chases at speed 16, aimed every 32
  frames (Sprite_ApplySpeedTowardsLink), along a wall towards Link at 14
  (Guard_ApplySpeedInDirection), for 255 frames, then state 2;
- walls: Sprite_CheckTileCollision for a header collision of 0 (all the
  castle's rooms): the probe point of the velocity's direction (flags 0x60:
  kSprite_Func5_X / _Y 24-27) against kSprite_Func5_Tab3 on the guard's
  level, pushed back 1 px (3 while recoiling); in-room stairs are walls.
OURS: the probe slot limit (10 live sprites over the room's list), the
256 px off-screen test against our 240 x 160 camera, slopes as walls, no
sword parry (Guard_ParrySwordAttacks). The other soldiers keep the round-6
stand-in AI but notice Link only on their own level. The sword hits only
sprites on Link's level (Sprite_CheckDamageFromLink). Link's knockback
(ours) is refused only when it would newly enter in-room stairs.

**Kill memory** (Dungeon_ResetSprites 0x89C114): a killed sprite stays dead
while its room is one of the last 4 rooms entered (a 4-room history);
entering a palace or continuing after a death clears it (Module_PreDungeon /
Death_Func15 -> Sprite_ResetAll; here a new Interior). Sprites with
kSpriteInit_DeflBits & 1 ignore it.

**Prizes** (Sprite_DoTheDeath 0x86F923, ForcePrizeDrop): an enemy without a
key drop leaves kPrizeItems[pack * 8 + the pack's counter] when rng &
kPrizeMasks[pack] == 0 (pack = kSpriteInit_Flags5 & 15, minus 1; the
guards' pack 0 drops every other kill on average), placed by kPrizeZ.

Checked by `tests/zelda_alttp_guard_test.lua` and the r13 route runs.

## The front end (round 13)

The GBA boots into a shared front end before either game (AgbMain
0x0800B084, top-level tasks 0x0842731C): task 0 the Nintendo / Capcom logos
and the shared title ("A Link to the Past" + "Four Swords"), task 8
(0x0800F809) CHOOSE A FILE / ENTER A NAME (with COPY, ERASE, OPTIONS),
task 6 (0x0803074D) CHOOSE A GAME, then the game. Found by running the
cartridge in the scratch interpreter (`r13/py/boot.py`): the main loop
waits at 0x0800B550 for the VBlank IRQ (0x0800B701, IRQ table 0x0842735C)
to clear 0x0300050C; the front end's object loop (0x0800023C via the veneer
0x08137B00, IRAM copy 0x03006740) and its overlap pass (0x080008A8 = IRAM
0x03005AE0) are ARM and are stood in for in Python (`armhle.py`).

**EEPROM** (8 KB, routines 0x08135DC4 read / 0x08135E74 write, 8 bytes a
block; a second copy at +0x1000): records at 0x0814C654 (12 bytes: size,
header A, header B, data, data 2): 0-2 the ALttP files, 0x480 bytes at
0x100 / 0x600 / 0xB00 (the RAM file 0x02002000-0x0200247F, SNES $7EF000;
loaded / saved by 0x08067A04 / 0x080679F0 with the file number at
0x03000004); 3 a 0x20-byte signature at 0; 4-6 the front end's 0x40-byte
file records at 0x580 / 0xA80 / 0xF80 (alternates +0x40; RAM 0x0200B250 +
64 * file; the player's name is 6 bytes at +8, drawn by 0x08010D1C, +0x3F
the file's state); 7 the settings, 0x10 bytes at 0xE0. Each header holds a
checksum (0x080679B0 over the magic "S4FT" and the data) and its negative.
Copy and erase are 0x08011228 / 0x080112B8. Our saves stay ZeldaSaves
tables; the name is `save().name`.

**Ported** (`FrontExtract.lua` at import, `FrontEnd.lua`): START at the
title -> CHOOSE A FILE -> ENTER A NAME for a new file -> CHOOSE A GAME ->
A Link to the Past (the opening, or the continue) or Four Swords. Every
BG map, tile block, OBJ tile block and palette is the cartridge's (RomMap
.front: the LZ77 blocks each screen decompresses, in load order, equal byte
for byte to the VRAM the cartridge built; palettes 0x44F0F4 / 0x44F6F4 /
0x44DD74 for task 8, 0x44EC34 / 0x44EE34 for task 6); the OBJ layouts
(FrontEnd.L) are the cartridge's OAM on each screen; the BG registers are
the cartridge's. OURS: one file (the launcher's save slot; files 2 and 3,
COPY, ERASE and OPTIONS are shown but inactive); the names and the name
grid are written with the HUD menu letters (A-Z, 0-9, '-': the cartridge
renders them with its front-end font, glyph lookup 0x0800EE50 with base
*0x03000030 = 0x0854F7E8, format not decoded), so the accented rows and the
"abc" page are empty; the file panel's contents (hearts, portraits) are a
line of text; the GBA blending is LOVE alpha; no "Now saving" window, no
fades. The after-escape "Link's house / sanctuary" choice is not ported.

Checked by `tests/zelda_alttp_front_test.lua`, the route's front-end steps
(harness and real app) and their screenshots.

## Layers and priority (round 14)

User report: Link drew over the door frames he walks under. Before round
14 every room drew all its maps and then every sprite on top. Found by
disassembly (`r14/py/`), all from the cartridge:

| What | Where | Notes |
|---|---|---|
| Room maps -> BGs | `0x08079220` | map `0x0201C000` (our "bg1", ROM table `0x162258`: the high-priority copy) -> VRAM `0x0600E000` = BG3; `0x02018000` ("bg2", the upper level) -> BG2; `0x0201A000` ("bg3", the lower level) -> BG1 |
| BG priorities | `0x0806A220` defaults BG1 1 / BG2 2 / BG3 3; the dungeon entrance `0x08078864` sets BG1 3, BG3 1 | so indoors: lower map 3, upper map 2, high map 1, HUD (BG0) 0 |
| Per-room layer setup | `0x0806D598` (from the SNES TM / TS / CGADSUB of the header's BG2 property, shadows RAM `+0x9B4/0x9B5/0x9D3/0x9D4`) | default as above; TM 0x17 (property 3, "on top", e.g. Zelda's cell 0x80): BG1 priority 1; CGADSUB 0x62 (property 4): BG2 3, BG1 2, BLDCNT 0x3C42 alpha 8/8; another blend (properties 2, 7): BG1 1, alpha 14/16; lights out (0xB3, `0x0806DF4C`): not ported (our darkness) |
| Overworld | `0x08075C0C` | the ground (BG2 table) on GBA BG2, priority 2; the overlay (BG1 table: canopies, roofs, door tops) on GBA BG1, priority 1 |
| OBJ priority | `0x080A452C` | the GBA keeps SNES OAM flags; GBA priority = `0x16B38E`[SNES priority] & 3 (+1 while CGADSUB is 0xB3 and palette bit 4 is clear) |
| Link's SNES priority | `0x16B326` (kPlayerOam_FloorOamPrio, read at `0x080A3F92` into RAM `+0x1724`) | by link_is_on_lower_level: upper -> GBA 2, lower -> 3, outdoor ledge hop (level 2) -> 1 |
| Sprites' SNES priority | `0x171DBC` (kSpritePrios, `0x080C1F32`) | floor 0 -> GBA 2, floor 1 -> 3 |
| Door drawers | `0x08084CB0`, `0x08084E38`, `0x08084F28`, `0x08085080`, `0x08085128` | each word goes to `0x02018000`; the door's outer row (north top, south bottom) or column (west left, east right) also to `0x0201C000` |

The GBA draws priority 3 first: that priority's BGs (BG3 behind BG2 behind
BG1), then its OBJs (an OBJ is in front of a BG of the same priority), then
priority 2, 1, 0. `Layers.lua` does exactly that for every room in view
(`G:drawRoomField`): on the upper level Link (2) is over both room maps and
under the high map, so he walks under door frames and wall tops; on the
lower level (3) he is also under the upper map (a bridge over him); the
room's own maps are transparent and the backdrop (colour 0) is filled under
them. An opened door's outer row / column is written to the high map too
(`Interior:drawDoor`; before it the high map kept the closed door's top).
Outdoors Link was already between the ground and the overlay; during a
ledge hop he is now over the overlay (GBA OBJ priority 1). The tables are
read at import (`RomMap.layers`, `data.t.layers`; cacheVersion 17).
OURS: dark rooms keep the lower map at the bottom and darken each BG layer
(round 7's darkness, now per layer so the sprites between the layers stay
lit); rooms 0x0D / 0x90 / 0xA4 / 0xAC's special cases; the chest's rising
item is drawn over priority 1 (its OAM priority is not traced).

Checked: `tests/zelda_alttp_view_test.lua` (priorities, draw order, the
door's outer row on the high map); harness `r14/harness/prio.lua` (Link
mid-doorway in 0x62 north, 0x61 west and south, the house 0x104 south,
new vs old drawing: `r14/out/cmp_n62.png`, `cmp_w61.png`, `cmp_s61.png`,
`cmp_s104.png`), `lower.lua` (the lower level, room 0x80); real app
`scene_r14` (`real/shots/r14_real_house_exit_mid.png`).

## Zoom and the whole map (round 14, ours)

The cartridge has no zoom; this is the Pokemon games' survey zoom for
ALttP (`Zoom.lua`). The mouse wheel (ZeldaRuntime now forwards it to the
game), the pad's R3 in / L3 out and both together to reset are the SAME
Input actions as Pokemon (`zoomin` / `zoomout`, HotActions' defaults,
rebindable in CONTROLS), read through ZeldaRuntime.input. Steps are integer
screen pixels per game pixel like `src/render/Zoom.lua`: level 0 is the
window's own scale S and draws exactly the cartridge's 240 x 160 through
the old code path; out to 1 px a game pixel, in to 2 S; saved as the game
option "zoom" (options.zelda.game.alttp). Only while walking around (play
/ room); menus, the front end, Four Swords and the overworld map stay 240 x
160. The view is centred on the cartridge camera's centre; the HUD and
text stay at the normal scale (ZeldaRuntime's drawOverlay).

Overworld: every 512 x 512 screen in view is drawn from the ROM maps
(`G:viewScreens`), so zooming out shows the connected map around Link;
screens outside the cartridge's own 240 x 160 decode at most two a frame
(black until then). Indoors: the rooms that connect to Link's room (doors
on a shared wall at the same place, breadth first, 3 steps;
`Z.edgeDoors` / `G:connectedRooms`) are drawn at their place in the 16 x 16
room grid with their own priorities, one decoded a frame. The castle's
maps are floor even in the void outside the walls, so walls cannot tell a
connection; warp doors (0x46) and exits are not followed; OURS: open edges
without a door are not followed either.

## Seamless transitions (round 14, ours)

`Seamless.lua`, on by default; the system menu's CARTRIDGE TRANSITIONS
(off by default, game option "cartTransitions") brings back the round-13
behaviour. Overworld: the area changes the moment Link crosses (the same
test), Link keeps walking and the camera glides from the old area's bounds
to the new ones (`followCam`, a sixth of the way, at least 2 px a frame).
Rooms and quadrants: the cartridge's walk-in and landing (Doors.lua) run
unchanged, so every door, layer toggle, trapdoor, kill-memory and room tag
rule fires at the same place, but the landing starts at once instead of
after the pan and the camera glides meanwhile (`roomGlide`), the room left
behind drawn while in view. Entrances, exits and stairs to another room: a
12-frame crossfade from the last picture (`drawCrossfade` keeps a copy of
the field each frame). Checked: `tests/zelda_alttp_view_test.lua` (the same
landing spot and level in both modes, control back sooner, no scroll on
the overworld), the escape bot in both modes, real app `scene_r14`.

## Guards: parry and the knife guard (round 14)

`Guard_ParrySwordAttacks` (GBA `0x080C39C0`, `Guard.parry`): Link's sword
box over a guard's weapon box (3 x 3 px at the weapon's last OAM offset,
kSoldier_Draw3_Xd / _Yd [gfx * 2]) parries: no damage, the guard recoils
`parryF[rng & 7]` frames (0x171E60) at 32 / 24 away, Link is knocked back
at 8 / 16 for `parryLink[rng & 7]` frames (0x171E68) and the swing ends;
the body away from the weapon still takes the hit. Not for the
ball-and-chain guard 0x6A (its ball position, ChainBallTrooper_Draw, is not
ported). The green knife guard 0x4B runs `Sprite_4B_GreenKnifeGuard`
(`Guard.updateRecruit`, tables 0x1773F4 / 0x1773FC / 0x178400): stand,
step off the way its head faces at 12, at 18 for 128 frames when that
faces Link within 16 px of his row or column, stop and turn its head.
OURS: the guard's animation frame is the drawing's; no tink spark.

## Map graphics audit (round 15)

User report: "some maps are still showing scrambled tiles and art". Found
by an audit that compares every map the port can draw with what the
cartridge's OWN loaders build, run in the scratch Thumb interpreter
(`r15/py/cart.py`): `0x0812E8DC` (InitializeTilesets: VRAM sheets from
RAM `+0xC99` main / `+0xC9A` aux / `+0xC9B` sprites), `0x0812FD88` /
`0x0812FCDC` (animated tiles), `0x0807FF10` (room loader: header
`0x08080D00` -- reads the room at `+0x9DA`, maps at `+0xA1E` --, maps,
objects, doors), `0x080794F8` (dungeon palettes), `0x0806A0C0` (overworld
area setup), `0x08073B98` (overworld palettes), `0x08077848` (overworld
maps: 4 screens per layer). The audit (`r15/harness/audit.lua`) decodes
the same maps with the port and compares every pixel's colour.

| What was wrong | Cause | Fix |
|---|---|---|
| every overworld area's colours, worst in the Dark World (77 of 80 areas) | `Palette.selection` took the per-phase SPRITE palette table (RAM `0x02002DC0`) as the BG set; the GBA calls `Overworld_LoadPalettes` `0x0813084C` with r0 = that table (kOwSprPalInfo, `0x22BD98`) and r1 = `0x14C8E8[screen]` (kOwBgPalInfo, `0x22BD1C`) | BG set = `0x14C8E8[screen]` (static, every phase); the overworld sprites' palette set = the per-phase table (`OwActors`) |
| water, lava, torches, conveyors: garbage tiles (151 of 279 rooms, most overworld areas) | the 32 animated tiles were never loaded: the static slot-7 sheet showed through | `AnimTiles.lua`: outdoors VRAM tile `0x1C0` = sheet `0x5A` (`0x58` Death Mountain) frames of 32 tiles (tiles 0-31, 32-63, next sheet 0-31); indoors tile `0x1B0` = 16 tiles of `dungAnim[main]` (`0x14CE1C`) + 16 of sheet `0x5C` per frame; the frame steps every 9 frames (`0x0812D1A0`, VBlank copy `0x080A7048`); only the cells using them are repainted (`Image:replacePixels`) |
| indoor maps using BG palette 0-1 (some lower-map fills) | palettes 0-1 were black | the HUD's palettes (Palette_Load_HUD) |
| room 0x11's key door drawn as an open doorway | a closed lock "cleared" the door to the pre-rendered map, which is not always the closed door | a closed lock draws the door type's own words (the GBA's door drawers) |

Result (`r15/out/audit/ow_after.txt`, `rooms_after.txt`): 80 / 80
overworld areas pixel-equal to the cartridge (both layers, animation frame
0); 279 / 279 reachable rooms with no graphics difference (VRAM tiles and
palettes equal wherever the map words agree). Before: 77 / 80 areas and
151 / 279 rooms wrong. Zoomed-out neighbours use the same per-screen /
per-room decoding (each area its own sheets and palettes; rooms the
entrance's main tileset, as the cartridge), the seamless camera keeps the
previous room's own pictures. Sprite sheets per room were checked by
reading the header loader (`+0xC9B` = header byte 3 + 0x40, as
`Sprites:setRoom`), not by the VRAM dump.

Left (not graphics; map WORDS the GBA room loader draws that the port does
not, 83 rooms): door states (shutters the port keeps open, entry trapdoors
before they close), pushable blocks (words 0x31E3...), floor rupees (0x61C4,
caves 0x03 / 0x04 / 0x6A / 0x92 / 0x93 / 0x99), a few torches. 25 rooms are
not reachable from an entrance (not audited). Round 16: all ported, 304 /
304 rooms word-equal (see "Room objects over the pre-rendered maps"). OURS: the 0x17-frame step of
overlays 0xB5 / 0xBC; the overworld palette's aux rows default to 3 / 3 / 0
where a set says "keep" (the cartridge keeps the previous area's).

## Room objects over the pre-rendered maps (round 16)

The 83 rooms left by the round-15 audit differed in map WORDS the GBA room
loader 0x0807FF10 draws after it decompresses its three pre-rendered maps.
Found by hooking its object drawer 0x0807FC20, door drawer 0x0807FBC4,
push-block drawer 0x0807D0EC and torch drawer 0x0807D288 in the scratch
interpreter and diffing the maps between calls (`r16/py/objtrace.py`,
`srctrace.py` for the ROM words each write comes from, `doorsurvey.py` for
the door drawers' write pattern over every room). Ported in
`RoomObjects.lua` and `Interior.lua` (`predrawDoors`, `drawDoor`,
`finalType`); the attribute tables are now built from the drawn words, as
the GBA builds them after drawing.

| Object | Cartridge | Port |
|---|---|---|
| doors | every door is drawn by type; 0x36 / 0x38 / 0x48 / 0x4A take their final type per drawer (SNES `OneSidedShutters_North`, `Door_Draw_Helper4`, `HighRangeDoor_North`, ...); a high-range north / west / east door draws nothing (pre-rendered), a south one (and a north one's mirror) writes its three rows to the lower map only; the stair-mask doors 0x24 / 0x26 two rows to the lower map | `I.finalType`, `predrawDoors`, the `self.loading` rules in `drawDoor` |
| two-way shutter 0x18, trap shutters 0x48 / 0x4A | closed at load (no more OURS "kept open"); the entry trapdoor is up for the entry and goes down behind Link | `LOCKED[0x18] = "shutter"`; entry / tags as before |
| push blocks | the new-game table ROM 0x163430 (room, tilemap pos * 2, 0x2000 = lower map; CpuSet to RAM 0x020029C0 by 0x08078EE2; 104 blocks until room 0xFFFF), words 0x2122 / 0x2123 / 0x2132 / 0x2133 (literal of 0x0807D17C) | drawn, attribute 0x70 + n after the pots; pushed after 21 frames into it (gravestone_push_timeout), 12/16 px a frame for 16 px, then fixed (attribute 0x27); `dung_flag_movable_block_was_pushed` toggles; a pit takes it |
| rupee floor (subtype-3 0x12) | 3 x 3 rupees, words 0x16623C; not drawn after one was taken (dung_savegame_state_bits 0x1000) | drawn; a rupee cell under Link's feet gives 5 rupees, its two cells become the floor word of Dungeon_DeleteRupeeTile (literal of 0x08087FC4); the room remembers |
| large pick-up block 0x2C, bomb floor 0x47 | 4 segments of 2 x 2 words (0x165382 / 0x164740), misc objects 0x70 + n (the bomb floor's not) | drawn, numbered with the pots in list order |
| Blind's floor light 0x71 | 0x08080718: while room 0x65's save word bit 0x100 is clear, the whole lower map is filled with the blank word (`movs r2, #0xF6; lsls 1` = 0x1EC) | the same (memory[0x65].light) |

Tags ported with them: 0x0A (every enemy of the room) and 0x0B-0x13 (a
push in the tag's quadrant opens the shutters, a second push closes them:
`trapdoors_down = !block_was_pushed`). NOT ported: tags 0x14 (water
puzzle; the escape's lever keeps its round-10 path), 0x15 (pendant /
crystal of the palace), 0x16 / 0x17 (floor switches), 0x33 (torches) --
shutters in those rooms stay closed until the entry or a kill tag opens
them; lifting the large blocks (needs the glove), bombing the bomb floor,
lighting torches.

Audit (`r16/harness/audit.lua`, cartridge dumps `r16/py/dump_rooms.py` with
the new-game block and torch tables in RAM, not emptied as in round 15):
**304 / 304 rooms, 0 map-word differences, 0 graphics differences**
(`r16/out/audit/rooms_after.txt`): the 279 reachable rooms and the 25 no
entrance reaches (loaded with a neighbour's main tileset).

## People: Kakariko and Sahasrahla (round 16)

`Npc.lua`. Overworld sprites per area and story phase: the GBA's
0x080CB140 takes one of three pointer tables by the story byte (2 ->
0x227E70, 3 -> 0x2280B0, else 0x227D70, the last one only for the 64 Light
World areas), each area's list { y, x, type } in 16 px from the area's
corner until 0xFF (type 0xFA a counter marker; SNES 0xF4). The townsfolk
are spawned when Link enters the area (OURS: all at once; the SNES
activates them as the camera nears). Their pictures are the GBA's copies of
the SNES DrawMultipleData tables (8 bytes an entry; SNES OBJ char row k ->
GBA row (k & 3) + 4 * (k >> 3 & 1), half (k >> 2 & 1)), found by
`r16/py/dmdsearch.py`; their palettes are the sprite's OAM flags.

| Type | Who | Where | Messages (SNES ids, GBA through `Text.bmgIndex`) |
|---|---|---|---|
| 0x78 | the elder's wife (ElderWife_Draw 0x178E2C) | room 0xF3, entrance 0x0E | 0x2B, the legend 0x2C, 0x2D (OURS: the choice cursor is not ported, "yes") |
| 0x16 | Sahasrahla (Elder_Draw 0x17642C) | room 0x105, entrance 0x45 | 0x32, then 0x33 marks the map (map icons 3) |
| 0x2A | the sweeping lady (0x178E4C) | Kakariko | 0xA5 |
| 0x3C | the boy at the trough (0x178D38), faces Link | Kakariko | 0x147 (map icons 2) / 0x148 |
| 0x34 / 0x3D | the snitch ladies (0x179034 / 0x178E88), face Link | Kakariko, houses | indoors 0xAD; OURS: outdoors they stand (their run to the guards is not ported) |

They block Link (Sprite_BehaveAsBarrier; outdoors through Link's
collision) and talk when he faces them and presses A. NOT ported: the
other overworld sprites of the lists (soldiers, octoroks, the bottle
vendor, the running man, the fairy...), the snitches' calls, shops,
house-specific scripts beyond these.

## The ball-and-chain guard 0x6A (round 16)

`BallChain.lua`, the GBA's routine 0x080E2D4C (SNES Sprite_6A_BallNChain)
and its states through the jump table 0x08176E9C: state 0 walks at Link
(ApplySpeedTowardsLink 8, re-aimed every 16th frame) until he is within
-0x40..0x27 rows / -0x30..0x2F columns, 1 stands 24 frames, 2 whirls 48
frames until its head faces kFlailTrooperAttackDir[(A >> 7 & 1) + B * 2]
(0x176EAC), 3 throws (aux timer 31, chain length 0x1770E0). The flail angle
grows each frame by a byte of 0x08176E98 + state - 2 (GBA quirk: states 0 /
1 read 0x0E / 0x0F, the two bytes before the table; the SNES has 0x0D /
0x60). Drawing: head (0x176EB0 / 0x176EB4), body (num 0x176EB8, x / y s16
0x176EE8 / 0x176F78, char 0x177008, flags 0x177050, big 0x177098), the four
chain links and the ball (sine 0x173F38, ChainBallMult, offsets 0x177100 /
0x177104, spacing 0x177108, OAM words from the literals of 0x080E32CA /
0x080E3352). The ball is a 16 x 16 hit box in states 2-3
(Sprite_DoHitBoxesFast): it hurts Link and parries the sword
(`Guard.parry`, weaponBox). The bot beats it by striking in states 0-1 and
keeping away in 2-3 (harness `B.fightFlail`).

## The Eastern Palace (round 17)

### The overworld door column

The GBA's entrance check runs at 0x0808BEE0. It computes the 16 x 16 tile
under (link_x, link_y + 7) for its big-door tests, the same as the SNES.
These tests (0x0808C044) look at the tile's top-right cell (0xE9 / 0x149 /
0x169) and the next tile's top-left cell (0x4E9 / 0x549 / 0x569).

Then it recomputes the position with `x - (base - 0x10)`. The door-pair and
door-table lookup (0x0808BB88) therefore reads the tile under
(link_x + 16, link_y + 7), the tile right of Link's own column.

There is one exception. In area 0x18, when link_x == 0x288 and
link_y <= 0x917, the GBA keeps Link's own column (Kakariko's entrance
0x43).

The door tables are built for this rule. Each door tile sits 8-16 px right
of the walkable passage under it. The palace's stairs (3920-3935) end one
tile left of its door tile (3936). Port: `Interior.owEntranceAt`.

OURS:

- The test runs only while Link walks up. The GBA runs it every frame.
- The one-row doorstep allowance stays. House doors have attribute 0x02
  under their door tile, and our Link stops one tile short.

### Sprites (Palace.lua)

The SNES routines that the GBA keeps, with tables read from the GBA ROM.
The GBA's rodata holds the SNES tables in the same order; `r17/py/tabfind.py`
finds them by value.

| Sprite | Cartridge rule |
|---|---|
| Popo 0x4E / 0x4F | `Sprite_4E_Popo`: wait 80, wobble 105, then hop in one of 16 directions (kSpriteKeese_Tab2/3 x 4) for 128-191 frames. It moves on frames where (k ^ frame) & B is 0 (B = 7 / 15). Drawn with `Bot_Draw` (SingleLarge, 0x1750B0 / 0x1750B4). |
| Anti-fairy 0x15 | Bounces off walls. Touching Link drains 8 magic. The sword does not hurt it, and it does not count for the screen-clear tags (flags4 0x40). Drawn with kDrawFourAroundOne_Dmd (0x1750BC). |
| Cannonball 0x50 | Moves at its speed. Dies 16 frames after hitting a wall (single collision point 0x35, flags2 0x20). |
| Cannon overlord 0x03 | `Overlord03_VerticalCannon`: one ball down every 57 frames, at x + 0 or + 16. Every 160 counts (every other frame) it fires a big ball at x + 8 instead (kMetalBallLarge, 0x1786A4). |
| Cannon overlord 0x02 | `Overlord02_FullRoomCannons`: every 16 frames, a ball from one of 16 wall spots (0x172A24 / 34 / 44). |
| Stalfos 0xA7 | Jumps away (speed 32, z speed 32) when Link is within 40 x 48 px and facing it (kStalfos_CheckDir). Otherwise `Sprite_Zazak_Main`: walk a kStalfos_Delay step, then turn by kZazak_Dir2, and face Link every 4th turn. The GBA's kStalfos_Delay is {10, 20, 40, 20}, not the SNES {16, 32, 64, 32}. Bone throwers (x & 16) throw on landing. Drawn with kStalfos_Dmd and the head override (0x178298 / 0x1783B8). |
| Eyegore 0x83 / 0x84 | `Eyegore_Main`: asleep until Link is within 48 px, opens its eye for 63 frames, chases for 0x60-0xA0 frames, then closes. While the eye is closed (flags3 0x40) the sword does nothing; the red one is only hurt by arrows (defl bit 4). Drawn with kEyeGore_Dmd (0x178768). |
| Armos Knights 0x53 | Asleep for 255 frames, then wake. While asleep they shake for the last 64 frames and the sword does nothing. Awake, they go to the ring places the coordinator gives (speed 16) and bounce (z speed 48). Six minus kills = the count. At one left, the last knight gets 48 health, turns red (oam flags 7) and crushes (`Sprite_ArmosCrusher`: aim speed 32, hover 16 frames, fall at -104, the room shakes for 32). Drawn from kArmosKnight_Draw_* (0x1785B0..). |
| Coordinator (GBA list 0x1A) | The ring: centre x & 0xFF00 + 120, phases kArmosCoordinator_Tab0 (0x178696), ArmosSin on 0x173F38. It rotates, shrinks to radius 32, grows back to 64, sends the knights to kArmosCoordinator_BackWallX (0x178690) at y 48, then cascades them down until one reaches y 192. The rotation then reverses. |
| Heart container 0xEA | Falls when the last knight dies. Taking it adds a heart (8 health) and marks the boss beaten. |

Room tags (0x15-0x17, 0x25, 0x27):

| Tag | Name | Rule |
|---|---|---|
| 0x17 | `RoomTag_SwitchTrigger_ToggleDoor` | Stepping onto a switch toggles every shutter, once per step. |
| 0x16 | `RoomTag_SwitchTrigger_HoldDoor` | The shutters are open while a switch is held. |
| 0x27 | `RoomTag_TriggerChest` | A switch reveals the room's chests. |
| 0x15 | `RoomTag_PrizeTriggerDoorDoor` | The shutters open once the palace's prize is Link's. |
| 0x25 | `RoomTag_GetHeartForPrize` | Once the boss is beaten and before the prize is taken, the pendant falls. Taking it gives pendant bit 4 (Courage) and the menu's pendant byte, and Link leaves the palace. |

The switch test is the GBA's 0x080798DC. It looks at the cells around
((x - 1) & 0x1F8, (y + 14) & 0x1F8) for a pair of 0x23 or 0x24, with the
same pair below.

The entrance room 0xC9's corridor pot hides secret 0x88, a floor switch.
The GBA writes the words 0x310B / 0x311B / 0x350B / 0x351B (0x080929E8).
Dungeon_Store2x2 gives all four cells the LR word's attribute, 0x23.
Stepping on that switch opens both two-way shutters. The bridge beyond has
its own switch, which closes them again.

OURS:

- The sound effects.
- Sprite slot numbers are list indices.
- The falling pendant (a straight fall) and its picture (the menu icon).
- Not ported: the falling-Stalfos overlord 0x05, the anti-fairy circle,
  arrows and item use, and lighting torches. (Round 18: all four are in;
  see "Items (round 18)".)

## Items (round 18)

New module `Items.lua`, installed after `Layers` (Game.lua's install list).
Every table is the GBA's own copy, read at import into `idx.items` (offsets
in `Items.OFF`, found with `r18/py/tabfind.py` and `r18/py/maptab.py`:
the GBA stores small offset tables as int16 and its OAM char tables with
its own 32-wide OBJ rows, SNES char c -> row (c >> 4) * 32 + (c & 15), rows
8+ in the right half).

### The buttons

The GBA moves the SNES Y item to **A** and the SNES A action (lift, talk,
open a chest, read, dash) to **R**. Two proofs:

- `0x0806995C` builds the item / action bytes from the GBA keys: in the
  default control mode A goes to `+0x53E` / `+0x53A` and R to `+0x53F` /
  `+0x539`.
- The messages' button glyphs: code 0x5B (R) in "press R to lift", "open a
  chest", "dash"; 0x5C (B) the sword; 0x5D (L) the map; 0x5E (A) "press A
  to light torches", "throw it using A"; message 394 leaves sleep mode with
  SELECT + L + R. The font's tiles are 0x0B R, 0x0C B, 0x0D L, 0x0E A
  (`Text.lua`'s glyph table was off by one: it showed L for the sword).

`Game.lua` now reads `inp.a` (the action) from R and `inp.y` (the item) from
A. The text box still advances with A or B. **This changes the controls**:
talking, opening chests and lifting are on R (the "e" key on the keyboard).

### The item routines

- `G:yItem()`: the menu's chosen slot (`progress.curItem`, the GBA's
  0x080A9E38 rule when it is empty or not owned); slot 1 the bow, 4 bombs,
  13 the lamp. Other items do nothing yet.
- **Bow** (LinkItem_Bow): kBowDelays {3, 3, 8}; the arrow leaves on the
  third step when Link has arrows. AncillaAdd_Arrow (kShootBow_X/Y,
  speeds +-48 = 3 px a frame), Ancilla09_Arrow (4 frames held, then flies;
  a sprite under its 1 x 1 hit point takes damage class 6 and holds the
  arrow; a wall stops it, pulled in by kArrow_X/Y), Ancilla0A_ArrowInTheWall
  (8 wobble steps of 2 frames, 128 frames, gone), Arrow_Draw (the GBA's
  char / flag pairs 0x17F3CC and Y/X pairs 0x17F42C).
- **Damage**: arrows and bombs use kEnemyDamages[class * 8 +
  enemy_damage_data[type * 16 + class]]; the GBA keeps enemy_damage_data
  unpacked at 0x17D924. A red Eyegore (0x84) takes 4 from an arrow and 0
  from the sword or bombs. 0 and the special codes 249+ do nothing (ours
  for 249+).
- **Bombs** (LinkItem_Bombs, AncillaAdd_Bomb, Ancilla07_Bomb): two at most;
  kBomb_Place_X0/Y0 when a wall is where the bomb would go, else X1/Y1;
  kBomb_Tab0 (fuse 0xA0, then 10 explosion steps); steps 1-8 hurt sprites
  (48 x 48, class 8, each sprite every 4th frame) and Link (32 x 32,
  kBomb_Dmg_ToLink, speed / delay tables); step 7 breaks door types 0x28 /
  0x2A / 0x2E indoors and runs Overworld_BombTiles32x32 outdoors (bushes,
  and the secret 0x86 -> map16 0xDB4 / 0xDB5: a bomb cave). Opened caves
  are kept in `progress.owBombed`. Bomb_Draw / AncillaDraw_Explosion with
  the GBA's tables (0x17F593-0x17F72D).
- **Bomb caves**: the overworld's 0x86 secrets. The light world's are the
  Kakariko bomb hut (entrance 0x4A), 0x6C and 0x84; the dark world has
  more. The round-17 note that 0x25, 0x4E and 0x5B need bombs was wrong:
  those are not bomb walls. Our doorstep allowance (one tile above Link)
  used to reach over an unbombed wall into the cave; `Interior.owBombWall`
  now stops it.
- **Lamp** (LinkItem_Lamp): kLinkItem_MagicCosts[18] = 4 magic, else
  message 123. AncillaAdd_MagicPowder's probe in front of Link (kMagicPower
  + kAncilla_CheckTileColl0) lights a torch with attribute 0xC0 + n
  (Dungeon_LightTorch). The flame is Ancilla2F (23 frames, kLampFlame_Draw).
- **Torches**: the room's list from ROM 0x1635D2 (the new-game
  dung_torch_data), drawn with the object tile data's words 0xEC2 (unlit) /
  0xECA (lit) at GBA base 0x164520 (the lit words use the animated tiles
  0x1C0). A lit torch burns 0xC0 x 4 frames (Dungeon_ProcessTorchesAndDoors).
  Tag 0x33 (torch door) and tag 0x3E (torch chest) want 4 lit. A dark room
  with lit torches: OURS 74 / 87 / 100 % light for 1 / 2 / 3 (the
  cartridge's fixed colour 8 / 4 / 0 of 31).
- **Keys**: `progress.keys` is the current palace's (link_num_keys); the
  others are kept in `progress.keysBy`, swapped by `syncKeys` when Link
  enters another palace (the castle and the sewers share). The big key is
  per palace (`progress.bigKey[palace]`, the castle's stays `.castle`).
  Door 0x1E is the big-key door (kDoorType_1E; it was treated as a small-key
  door): it opens with the big key, else message 122. A big chest wants the
  big key; opening it starts the falling Stalfos.
- **Menu**: the bomb slot shows the bomb count; the bow is 1 without arrows
  and 2 with (Hud's link_item_bow rule).

### Palace additions (Palace.lua)

- The anti-fairy circle 0x82 (SpritePrep_AntifairyCircle /
  Sprite_82_AntifairyCircle, kBubbleGroup tables at 0x1751AC): four
  anti-fairies whose speeds swing to +-18; when the room is clear they turn
  into ordinary anti-fairies (0x15). Room B8 has one.
- The falling Stalfos: overlord 0x05 (A9 has four) counts up once the big
  chest is open and at kStalfosTrap_Trigger[k] (0x172A08) drops a Stalfos
  0x85 from z 224 (Sprite_85_YellowStalfos: falls, faces Link 64 frames,
  waits 127, waits 64, rises away). OURS: drawn with the Stalfos' pictures;
  the head it throws is not ported.
- Sahasrahla (Sasha_Idle / Sprite_Sahasrahla): with the pendant of Courage
  and no boots, message 0x38 (0x39 if the map was not marked), the Pegasus
  Boots (Link_ReceiveItem 0x4B, GBA inventory byte 0x39 -- round 19: round 18 wrote 0x35, the cape's item slot 22; see "The Pegasus Boots dash"), then 0x37.
- Tag 0x14 is not used by the Eastern Palace's rooms.

### The cannonball track (B9)

Overlord03_VerticalCannon: a ball every 57 frames in lane x 264 or x 280
(rng & 2), a big ball (32 px, both lanes) when gen2 runs out, 1.5 px a
frame down the lower level's corridor (x 264-295, y 160-343). Alcoves:
left x 248 rows 224 and 288-311, right x 296 rows 256-279. The route bot
(`r18/harness/b9climb.lua`) looks 48 frames ahead along the balls' roll and
takes the first move (up, the other lane, stay, down) that stays clear.

## The Eastern Palace in one run (round 19)

### How the palace connects (read from the room data)

B9's west door is on the upper level's outer ring (rows 12-26: the two side
columns and the band at rows 24-25). Nothing inside B9 reaches that ring:
the ring's only doors are B9's west door (to B8) and its east door, a
small-key door (0x1C) from BA. So the cartridge's way is:

1. A9 (the big chest room): a floor switch at (48, 320) (tag 0x17) opens
   both side shutters.
2. A8 (tag 0x03, the south-west trigger, Dung_TagRoutine_0x2B): Link comes in
   from A9 into the east room (x >= 256). The doorway of the shutter to the
   west room starts at x 216, which is already in the south-west quadrant,
   where no sprite lives. Walking into it opens the trapdoors.
3. The south-west room, its north shutter, then the north-west room. Its
   stairs (0x1E) go down to the lower level. The lower level's doors at row
   15 lead to A9's sunken floor (the big chest), then to AA's lower ring.
   AA's stairs (0x3E) come up into the corridor to BA.
4. BA (dark, tag 0x17): a floor switch at (192, 144) opens the east shutter.
   The pot at (448, 96) hides the small key (secret 8).
5. BA's key door, then B9's upper ring, then B9's west door, then B8.
6. B8 (tag 0x27): the anti-fairy circle sits on the pot at (384, 208)
   until the room is clear (two Popos, two Stalfos, a green Eyegore). The
   pot hides a floor switch (0x88); stepping on it shows the chest with the
   big key.
7. Back through the ring and BA to A9. The big chest holds the Bow; then the
   four falling Stalfos come. A9's lower pots hold arrows (secret 9).
8. A9's big-key door (0x1E), then 99. One green Eyegore drops the small key
   (its sprite list's drop flag).
9. 99: the pot at (160, 320) blocks the corridor west. At its end the stair
   mask (door 0x20) opens with the key, and its spiral stairs lead up to DA.
10. DA (dark, tag 0x17): the pot at (96, 400) hides a switch for the west
    shutter. Then D9, D8 (the red Eyegores, arrows only; tag 0x06), and C8
    (the Armos Knights).

### Engine fixes this needed (cartridge rules)

| What | Rule | Where |
|---|---|---|
| Stair masks | Door types 0x20-0x26 (kDoorType_StairMaskLocked0-3) are small-key locks: Dungeon_ProcessTorchesAndDoors opens any door type >= 0x1C and < 0x2C (except 0x2A) with a key. Opening one runs DrawCompletelyOpenDoor: the wall spiral stairs get 0x5E / 0x5F, 0x30 + n, then two rows of floor. Before, the mask was an unopenable "other" lock and 99 led nowhere | `Interior.LOCKED`, `Interior:openLock` |
| A pot's small key | A key from a pot's secret (Drops `spawnDrop` 0xE4) gets its frame counter (`t = 0`). Before, BA's key pot stopped the actor update with an error | `Drops.lua` |
| Chests on the lower layer | Dungeon_LoadAttribute's chest loop: a chest drawn on BG1 (`dung_line_ptrs_row0` 0x4000) marks the lower table. A big chest (flag 0x8000) marks XY(0..1, 0) and XY(0..3, 1..2): its third row is where Link stands to open it. Before, both went on the upper table at two rows, so A9's big chest (in the sunken floor) could not be opened | `Interior:markChests`, `chestAt`, `openChest` |
| The held sword | LinkItem_Sword: B still held after the swing keeps the sword out (button_b_frames 9; the jerks 10-12 after a hit). Its hit box is kPlayer_SetupActionHitBox row 9 with the held pose's OAM offsets (LinkOam row 2, jerks row 3), so it pokes what it touches. Link walks with it out, facing locked. Stalfos_Skellington does not jump from a held sword (button_b_frames 9..0x8F). Round 20: the walk is link_speed_setting 12 and the spin attack is ported (see "Fights, the cartridge's way") | `Escape.lua`, `Actors.swordBox(…, yt, rt)`, `Game:linkPose` |
| Room prizes | A room's own absorbable sprite (0xD8-0xE3, such as room 0x89's two fairies) is spawned as its prize, with no lifetime | `Actors.lua` |

### The HUD item box and Link's poses

- **The item box** (Hud_RefreshIcon; the GBA's box at `0x0200B1F8`, HUD word
  60). It shows the chosen item's 2 x 2 icon from the item menu's own word
  tables (`RomMap.menu.gridTab` / `bottleTab`, + level * 8). Bombs draw
  level 1 while there are any. With no item, the template's empty box
  stays. See `Hud.itemIcon`.
- **Poses** (LinkOam_Main): the held sword is row 2 (at the walking step),
  its jerks row 3. The bow is row 7 (kPlayerOam_Tab2[link_item_in_hand bit
  4]) at the bow's step. The lamp has no pose on the cartridge
  (LinkItem_Lamp is instant).
- NOT done: the bow's own picture. Weapons with selector >= 29 come from
  `link_dma_var5` -> kLinkDmaSources6 (the item graphics in the weapon
  strip's RAM, SNES 0x9480-0xA100). Only the sword and shield are
  rebuilt. So the bow pose shows Link's body only.

### The Pegasus Boots dash (Dash.lua)

R (the GBA's action button) with nothing to talk to, open or lift, and the
boots owned (inventory byte 0x39: SNES link_item_boots 0x55 - 0x1C, as the gloves 0x38 and the sword 0x3D; the menu's ability box lists 0x39, 0x38, 0x3A, 0x3B. Round 18's 0x35 is item slot 22, the magic cape, so the menu and the HUD box showed a cape; Npc.lua moves an old 0x35 to 0x39), runs Link_PerformDash:

- **Charge:** 29 frames running in place. Letting go of R stops it.
- **Run:** link_speed_setting 16 (kSpeedMod[16] = 64, 4 px a frame) the way
  Link faces. Any other direction ends it.
- **Run's hit box:** kPlayerActionBoxRun, 16 x 16 ahead. It hurts sprites
  (the sword is out).
- **Wall:** a wall ends the run with LinkApplyTileRebound: speed 24 back,
  24 frames.
- **Door 0x28:** a breakable wall ahead breaks while link_dash_ctr < 63.

OURS: the dust, the sound and the running pose. Round 20: the rebound's
hop and the overworld (see "The dash outdoors, lifted bombs").

## Fights, the cartridge's way (round 20)

Checked against the SNES code the GBA keeps (zelda3 sprite.c / player.c);
the tables are read from the ROM (RomMap.combat).

| What | Rule | Where |
|---|---|---|
| Link's body against sprites | Link_SetupHitBox: (x + 4, y + 8), 8 x 8 (was x + 3, 10 x 12). CheckIfHitBoxesOverlap counts boxes that only touch | `Actors.linkBox`, `Actors.overlapCart` |
| Touch damage | Sprite_CheckDamageToPlayer_1: only on frames where (slot ^ frame) & 3 == 0, not while the sprite's hit timer runs, the sprite's box lifted by its height (y - z; none while z < 0). kPlayerDamages[3 * bump class + armour] | `Actors:update` |
| Link hit | Sprite_AttemptDamageToLinkPlusRecoil: 19 frames, recoil speed 24, z speed 24 >> 1 (the hop: Player_ChangeZ - 2 a frame; the timer waits at 1 until he lands); 58 blink frames. Landing resets the sword (Link_HandleRecoilAndTimer: button_b_frames, the spin charge) | `Escape.lua` hurtLink and the recoil step |
| The sword's damage | Sprite_CalculateSwordDamage: class kSprite_Func14_Damage[sword level - 1 OR 4 spinning OR 8 held out] (ROM 0x171FE8; the dash: no flags), then kEnemyDamages[class * 8 OR enemy_damage_data[type * 16 + class]]. Before, every sprite took class 1 column 1 (2). An Armos Knight takes 4 from a swing, 2 from the spin, 16 from an arrow; a green Eyegore 2 / 4 / 64; a Stalfos 2 / 4 | `Actors:swordDamage` |
| The hit timer | Sprite_GiveDamage: sprite_hit_timer 0x9D for the sword (bit 0x80: no second sword hit for 29 frames), 0x20 for arrows and bombs (arrows ignore it, Ancilla_CheckSpriteCollision). The health drops when the timer reaches 24 (Sprite_TimersAndOam -> Sprite_MiniMoldorm_Recoil); the recoil (sprite_F 15) starts at once | `Actors:swordHit`, `Actors:takeDamage` |
| Tinks | A sword on a sprite it cannot hurt (defl bits 4 / flags3 0x40: a closed Eyegore, a sleeping Armos, a red Eyegore) pushes Link back: recoil speed 4 for 16 frames, once per set_when_damaging_enemies (16) | `Actors:tinkLink` |
| The held sword | Player_Sword_SpinAttackJerks_HoldDown: while set_when_damaging_enemies is 0 the charge counts to 64 and Link walks at link_speed_setting 12 (kSpeedMod[12] = 20: 1.25 px a frame; was every other frame); a poke sets it to 16: the jerks run, and at 1 the sword is put away (B must be pressed again) | `Escape.lua` |
| The spin attack | Letting go of B with the charge at 48 or more (HandleSwordControls -> Link_ActivateSpinAttack -> LinkState_SpinAttack): 12 steps (kLinkSpinGraphicsByDir by facing, kLinkSpinDelays, ROM 0x168040 / 0x16807C), about 34 frames, button_b_frames 144: the box (x - 14, y - 10) 44 x 45 all round, damage class OR 4; LinkOam row 0x0F at state_for_spin_attack; a hit on Link ends it | `Escape.lua`, `Game:linkPose` |
| The palace sprites' recoil | Their own routines run first and call Sprite_ReturnIfRecoiling where the cartridge does. Before, the shared recoil step ran instead: a stunned Armos Knight hung in the air and jumped back to its ring spot, and the timers stopped | `Actors:update` |
| The falling Stalfos (0x85) | Sprite_85_YellowStalfos with a sword below level 3: a hit clears the hit timer at once and lays it in a heap for 255 frames (ai 5: no damage taken, it does not hurt Link), then it rises away. Its own pictures (YellowStalfos_Draw, kYellowStalfos_Dmd 22 GBA words, the head by kYellowStalfos_HeadX / Y), and at its delay 48 the head flies off (YellowStalfos_EmancipateHead -> sprite 0x02: homes on Link for 255 frames, then flees) | `Palace.yellowStalfos`, `Palace.stalfosHead` |

Eyegores (Eyegore_Main: 63 frames opening, open 0x60-0xA0 frames by the
RNG, re-facing Link on (slot ^ frame) & 31 == 0, 63 closing, 96 asleep),
the Armos Knights (asleep 255 frames, the ring, the crusher), arrow damage
and the ball-and-chain guard were compared and match.

OURS: a lifted bomb's flight is the pot's arc. (Round 21: the falling
Stalfos' head takes the sword, and dead sprites go through the death
puff; see "Round 21".)

### The dash outdoors, lifted bombs (round 20)

- **The dash outdoors** (`Dash.owAfter`, hooked in the overworld update):
  the same charge and run as indoors. Stopped by something solid,
  Link_BonkAndSmash breaks what he runs into: the 16 x 16 tile at Link +
  kGetBestActionToPerformOnTile[facing] (ROM 0x168258 / 0x168260, int16)
  and the one 8 px lower; a bush 0x36 becomes 0xDC7 with its secret and
  drop, as the sword's cut (the castle's hole bush shows its hole). Then
  RepelDash: the rebound (speed 24), the hop (link_actual_vel_z 36,
  Player_ChangeZ - 2 a frame, the timer held until he lands) and the
  screen shake's 17 frames (`game.tremor`). OURS: the big rock piles
  0x226-0x229 are not smashed; the dust, the sound and the shake's
  drawing are not done; Sprite_DashItem (the Book of Mudora, bonk keys)
  is not ported.
- **Lifted bombs** (`Carry.lua`): R on Link's own bomb before it goes off
  lifts it like a pot; it rides over his head with its fuse running and R
  throws it. OURS: its flight is the pot's arc (the cartridge's thrown
  bomb is not traced).

### The route bot's fight helper (scratch, not in the game)

`r20/harness/fight20.lua` runs every fight of the route. Each frame it:

- predicts each threat for 20 frames from its position and speed, its
  height (Armos, Stalfos), the Eyegore's re-facing rule, the Armos crusher's
  landing spot, and for the ball-and-chain guard its own routine
  (`BallChain.update` on a copy);
- simulates Link's walk for the 9 directions with the engine's own walking
  (`Doors.move` on a copy of Link);
- picks the move with the least predicted contact, then the best spot for
  the weapon, and stays out of pockets (pots, corners);
- strikes when a predicted swing step (`Actors.swordBox`) meets an open
  target, and shoots when the simulated arrow's first sprite is the target
  with its eye still open on arrival;
- charges and spins for Stalfos and Popos (one spin kills them; the held
  sword keeps the Stalfos from jumping);
- wakes sleeping Eyegores from the edge of their 48 px box, keeps away
  while they are shut, and goes for hearts and fairies when low.

## Round 21: arrows, effects, the sword outdoors, the dash items

### Where the arrows come from (D8 and around it)

Read from the cartridge (room secrets, sprite_flags5, kPrizeItems; checked
in `tests/zelda_alttp_r21_test.lua`):

- **Pots.** Secret 9 under a pot is sprite 0xE1, five arrows
  (kSpawnSecretItems). D8 has five: (384, 384) in the south half, and (296,
  168), (296, 200), (456, 136), (456, 168) in the north half. D9 has one (368,
  320), DA two, A9 three. D8's other pots hold hearts (secret 11).
- **Prizes.** The Eyegores (green 0x83 and red 0x84) use prize pack 5:
  0xE1, 0xD8, 0xE1, 0xE2, 0xE1, 0xD8, 0xE1, 0xE2, which is mostly arrows. A
  drop happens half the time (kPrizeMasks).
- **What a pot remembers.** On the cartridge, `pots_revealed_in_room` is
  cleared only by Dungeon_LoadEntrance. A pot's item comes out once per
  palace visit, and the pot itself comes back when the room is entered
  again. OURS: a lifted pot stays lifted.
- **The bot.** With 25 arrows in D8's pots, the bot never had a supply
  problem. It ran short because it fought everything at once. The helper
  now clears D8 in phases (scratch `r21/harness/d8_21.lua`):
  1. The south half's Stalfos.
  2. The south arrow pot.
  3. The south red Eyegore.
  4. Up through the doorway into the north half, and its Popos. Link keeps
     clear of the sleeping reds' wake boxes and stays in the north half.
  5. The two reds, with arrows. The fight's own pot walk refills him if he
     runs short.
  6. The rest of the arrow pots, kept for the Armos Knights.

### The death puff (Effects.lua)

The cartridge's death sequence (SpriteModule_Die / SpriteDeath_DrawPoof):

- A killed sprite enters state 6 with a 31-frame timer after a sword hit
  (the hit timer's bit 0x80), or 15 frames otherwise.
- The timer runs at 3 / 4 speed: it is put back on frames where frame & 3
  is 0.
- The puff is four OAM entries of kPerishOverlay. The GBA tables are at
  0x1721C2 (X), 0x1721E2 (Y), 0x172202 (char) and 0x172222 (flags), with its
  own chars.
- The sprite itself is still drawn while the timer is 10 or more.
- When the timer ends, the prize or key drops and the kill memory is set.
  Until then the room's kill tags do not count the screen as clear.

The Armos Knights keep their own death.

### The dash dust and the shake (Effects.lua)

- **AddDashingDustEx.** Only one dust is out at a time.
  - Charging: three chars per stage at (Link x, Link y + 20). The tables are
    kDashDust_Draw_X / Y / Char at 0x17EDF8 / 0x17EDBC / 0x17EE34, plus the
    facing offset at 0x17EE52. A stage lasts 3 frames; the dust is hidden at
    stage 5 and gone at 6.
  - Running (DashDust_Motive): one char per stage at Link plus 0x16E158 /
    0x16E150 by facing (chars at 0x16E160). It is gone at stage 3.
- **Ancilla1D_ScreenShake.** The shake lasts 16 frames at 3 px, with the
  sign flipped every frame. It is vertical when Link faces up or down,
  horizontal otherwise. The first sign comes from Link's spot on the screen
  (0x80 / 0x78).
  - Module07_Dungeon and the overworld add the shake to the camera for the
    BGs and the sprites. Link is drawn after the camera is put back, so he
    stays still.
  - OURS: outdoors, the shake is not zeroed at the scroll edges.
- No sound effects are played (there is no SFX player yet).

### The bow's picture (Weapon.lua)

- **Selectors.** Selectors 29 and up of the weapon pose tables are items.
  link_dma_var5 is swordDmaSel[j].
- **DMA sources.** The GBA's kLinkDmaSources6 / 7 (0x22A9F2 / 0x22AAF2) hold
  the SNES offsets from the item strip's start
  (LoadItemGFXIntoWRAM4BPPBuffer).
- **Chars.** Chars 9 and 10 show the two tiles at itemDma[var5]. Chars 0x29
  and 0x2A show the two tiles at + itemDma2[var5 >> 3].
- **The bow's block.** At strip offset 0x380: sprite sheet 0 tiles 8-10,
  over tiles 24-26 (checked by picture).
- **Colours.** The OAM word's palette row (row 1) of the room's or the
  overworld's sprite palettes.
- **Not done.** Only the bow's block is listed; the other items are not
  drawn.

### The sword outdoors (OwSword.lua)

- **The swing's cut point.** TileDetect_MainHandler(1) uses the cartridge's
  own table: kDoSwordInteractionWithTiles_x / _y, the GBA's 40 x s16 at
  0x1681D4 / 0x16817C. Up is (6, 4), down (8, 28), left (-1, 16), right
  (22, 16). Before, it was our (8, 4), (8, 26), (-3, 16), (19, 16).
- **The held sword and the spin attack.** They run outdoors as indoors.
  - The held sword walks at speed 12, pokes the overworld's sprites, and is
    put away after a poke.
  - On each of its 12 steps, the spin runs TileDetect_MainHandler(8). For
    a = state_for_spin_attack - 2 (0..7), it takes the point at
    (kDoSwordInteractionWithTiles_o[a] + 0x40) >> 1 (o at 0x16822F) and cuts
    the bush or grass there.
- **Not done.** The wall tap and the sword beam.

### The falling Stalfos' head (Palace.lua)

Sprite 0x02 runs Sprite_CheckDamageToAndFromLink. It touches Link like any
sprite, the sword and arrows hurt it, and it recoils with its speed zeroed.
Its health is 255 (the ROM's table), so it never dies. Its flags4 is 0, so
it counts for room clears. The bot does not target it.

### Rock piles and the dash item

- **Big rock piles (Dash.rockPile).** A pile is map16 0x226-0x229. The dash
  bonk (Link_BonkAndSmash -> Overworld_SmashRockPile ->
  SmashRockPile_fromLift) does the following:
  - It finds the pile's top left (kBigRockTab1).
  - It reveals the secret there.
  - It redraws the four tiles as kDoorAnimTiles[20..23] (0xDCD-0xDD0), or
    [40..43] (0x918-0x91B) when the secret is a hole or stairs.
  - The Light World has 8 piles.
  - OURS: the debris kind; no sound.
- **The dash item 0x3B (DashItem.lua, Sprite_DashItem).**
  - In the library (room 0x107) it is the Book of Mudora. It falls when Link
    faces up within (x - 39 .. + 7, y - 40 .. + 5) while the screen shakes
    from his bonk. It falls with z speed 32, y speed -5 and bounces.
    Touching it gives item 0x1D.
  - Elsewhere it is a bonk key.
  - OURS: the book drops from the shelf's top to the floor in front
    (y + 64); how the cartridge places it on the shelf is not traced. It is
    drawn as its item-menu icon.

## Round 22: carrying, pots that come back, the choice cursor, shops

### The carried pot (Carry.lua)

The real app's "132 presses at the Armos Knights, no arrow" (round 21, try
7) was Link carrying D8's last pot into C8: while something is carried the
item button does nothing (as on the cartridge), and our port let only R
throw it, so B and A did nothing at all. The cartridge
(CarriedSprite_CheckForThrow, GBA `0x080C3280`):

- **B or R throws** it: `(filtered_joypad_H | filtered_joypad_L) & 0x80`.
  The GBA input builder (`0x08069AA8`) sets `+0x547` bit 0x80 (SNES B)
  from a new GBA B press (`+0x540`) and `+0x546` bit 0x80 (SNES A, the
  action) from `+0x53E`. The throw velocities are `0x171E51` / `0x171E55`
  / `0x171E59` (x, y, z by facing).
- **A hit throws it at once** (`link_incapacitated_timer != 0`): every
  recoil frame calls `G:carryRecoilFrame()` (Escape.lua's two recoil
  branches); the thrown pot also flies on during the recoil (it froze
  before).
- **A room change ends it** (Dungeon_ResetSprites -> Sprite_DisableAll,
  `link_state_bits = 0`): `G:startRoomScroll` drops the carry on stairs and
  inter-room transitions (Game.lua).

The bots now wait out the 20-frame lift before the throw press
(`R22_LIFT_THROW` in r22/harness/bot.lua): a press during the lift is lost,
which is how the real app (one frame later than the harness) kept the pot.

### Pots come back (Interior.lua)

On the cartridge every room load draws the room's pots again. What a pot
hid comes out once per palace visit: RevealPotItem keeps one bit per
secrets entry in `pots_revealed_in_room`, cleared only by
Dungeon_LoadEntrance (here `Interior.revealed`, which lives as long as the
Interior made at each entrance). Not in those bits: secret 8 (the small key:
its sprite vanishes once the room's key flag is set, Sprite_E4_SmallKey;
here `mem.potKey`, set when Link picks the key up) and 0x80+ (switches /
holes: a pot switch shows again each time). A save from before round 22
that lists a lifted key pot counts that key as taken.

### The choice cursor (Text.lua)

The choice commands 0x68 (Choose2LowOr3, messages 1 / 2), 0x6F
(Choose2HiOr3, 11 / 12), 0x71 (Choose3, 6 / 7 / 8, wraps) and 0x72
(Choose1Or2, 9 / 10) hold the box on the command. Up / down load the cursor
message, which holds only the arrow (font code 0x44, kind 1) and blanks on
the option lines and ends on the same command; it is drawn over the text (a
glyph now overwrites the columns it covers, as the VWF renderer does). A
confirm closes the box; `box.choice` / `game.lastChoice` is
`choice_in_multiselect_box` (0 = the first option). The 28-frame
`text_wait_countdown2` after the last key press is kept. Mrs Sahasrahla
(Sprite_78 state 2) tells the legend again on "Not at all".

### Shops (Shop.lua)

Sprite 0xBB: SpritePrep_Shopkeeper picks the wares by the room's low byte
(kShopKeeperWhere); the Kakariko shop (0x11F) sells the red potion (150,
needs an empty bottle), the heart (10) and bombs (50); 0x10F / 0x110 sell
the shields, the bee and arrows. The wares sit at the clerk's x - 44 / + 8 /
+ 60, y + 0x27; R while touching one buys it (ShopItem_CheckForAPress):
too few rupees 0x17C, a full bag 0x16E, an owned shield 0x166, no bottle
0x16D, else the ware goes and the clerk thanks (0x168 / 0x167 / 0x16C /
0x169 / 0x16A / 0x16B). The clerk greets once (0x165) when Link is within
his y + 0x60 and on R. The clerk is drawn with the GBA's kShopkeeper_Dmd
(`0x17D2C4`), the wares with their prices with its
kShopKeeper_ItemWithPrice_Dmd (`0x17D0E4`, 35 entries: the GBA's own chars,
so the search by SNES chars missed it; found by x / y / size), xor the
sprite's flags (0xBB's flags3 low nibble 1: page 1). Both tables are new in
the import (cacheVersion 24). OURS: "touching" is Link's box grown by 2 px;
no beep; the chest games and the thieves (the other subtypes) are not
ported. The choice cursor glyph (kind-1 code 0x44) is the font's tile 0x00,
the right-pointing triangle (it drew as "D" before).

## Round 23: the desert, the Desert Palace's first sprites, the glove

### The Desert of Mystery's door (Desert.lua)

Area 0x30's phase-2 sprite list (GBA 0x227E70, Npc.lua's lists) holds three
desert statues (0x57) around the courtyard and the plaque (0xB3) in front of
the palace's steps (entrance 9's door is further north, at 304, 3248).
`Npc.spawnArea` hands the area's list to `Desert.spawnArea`.

- **The plaque** (Sprite_B3_PedestalPlaque, the area-48 branch;
  SpritePrep_PedestalPlaque: x + 7). Link facing up and touching it
  (Link_SetupHitBox against the plaque's box): the action button alone shows
  0xBC (Hylian he cannot read); the item button with the Book of Mudora
  chosen (item slot 17) shows 0xBD and sets Link reading the tablet; when the
  text closes the prayer starts (LinkState_ReadingDesertTablet ->
  Link_PerformDesertPrayer). The plaque reads this frame's buttons from
  `game.owInp` (Game.lua stores them before the overworld sprites run).
- **The prayer** (Module0E_05_DesertPrayer): 31 frames of darkening, the
  iris (DesertPrayer_InitializeIrisHDMA: radius `spotlight_var1` 0x26 round
  Link's x + 8 / y + 12) while the palette lightens back (30 frames), Link
  praying (kPrayingScene_Delays, GBA 0x14DAA6) until a button; then the
  radius halves and grows 8 a frame to 0xC0, and `byte_7E02F0 ^= 1`.
  Everything else is frozen meanwhile (module 14). OURS: the palette filter
  is a dark veil, the iris a filled circle (the GBA's window table is not
  read), no praying poses, the music only stops / restarts.
- **The statues** (Sprite_57_DesertStatue, SpritePrep_DesertStatue: x + 8,
  y + 8; direction by x's low byte: < 0x30 left, < 0xE0 up, else down). They
  wait for `byte_7E02F0`, shake 128 frames (x + ((delay >> 1) & 1)), then move
  16 (1 px a frame) and turn on a wall by kDesertBarrier_NextD (GBA
  0x178A14: Xv, Yv, NextD), counting one every other frame to 130; Link is
  held while any moves (flag_is_link_immobilized). They are barriers to Link
  (Npc.solidAt's `a.box`). Drawn with kDesertBarrier_Dmd (GBA 0x178A20,
  imported with Npc's draw tables) on sprite palette 0, which needed
  **sp0l outdoors** (Overworld_LoadPalettes: palette_sp0l 1, Dark World 3;
  Sprites.setOverworld left that row black). Their wall test is the
  cartridge's probe point (kSpriteInit_Flags -> kSprite_Func5_X/Y) on the
  overworld attribute with kSprite_TileSolidity (OURS: the overworld's own
  sprite solidity is not traced). With that the three statues go round the
  courtyard and end top-left, top-right and on the south steps, the north
  way to the door clear. No flag is saved: a reload of the area stands them
  again (Sprite_ResetAll clears `byte_7E02F0`; the SNES has none either).

### The Desert Palace's sprites (Desert.lua through Palace.lua)

The rooms' cartridge sprite lists (r23/py/roomspr.py): 0x84 six Leevers + a
Beamos; 0x83 / 0x85 / 0x74 / 0x73 / 0x75 Leevers, Beamos, Debirandos
(0x63 / 0x64), Popos, green Eyegores, wall cannons (0x66 / 0x67), the bonk
key (0x3B in 0x73); 0x63 / 0x53 / 0x43 Beamos, Popos, a red Eyegore, Wizzrobe
spawners; 0x33 Lanmolas.

- **Leever 0x71** (Sprite_71_Leever; tables at GBA 0x175340: Emerge, AttackSpd,
  AttackGfx, Submerge, then Leever_Draw's Num / X / Y (s16) / Char / Flags /
  Big). Under the sand it creeps to Link at 16 and can neither hurt nor be
  hurt (`a.untouchable`, checked by the shared contact and sword code); it
  surfaces 127 frames, attacks 160-223 (speed 12 towards Link every 8th
  frame, stops at a wall), sinks 127, waits 64-95. OURS: the sand chars'
  palette mask is taken as GBA chars >= 0x48 (the SNES test is by its own
  char numbers).
- **Beamos 0x61** (Sprite_61_Beamos, Beamos_Draw / SpriteDraw_Beamos_Eyeball
  at GBA 0x179B90): a probe every 4th frame round its 64 directions (the
  guards' probe velocities and rule, Guard.lua); a probe on Link starts 16
  flashing frames, the laser fires at 15 from the eye (four Sprite_MoveXY a
  frame at 0x20 towards Link after 12 frames, a 32-point trail, damage class
  4, stops 16 frames on Link or a wall; at most 4 live), then 80 frames rest.
  Contact hurts by its bump class; it never counts as a foe. OURS: the
  laser's char 0x3C (the SNES 0x5C by the sheet's row shift), no hit sparkle.

### The Power Glove and rocks

The big chest in 0x73 holds item 0x1B: `gloveLevel()` 1. Carry.lua already
had the cartridge's kGetBestActionToPerformOnTile_a: gray rocks (attr
0x52 / 0x53) and big gray boulders (0x5A / 0x5B) want level 1, dark rocks
(0x58 / 0x59) and big dark boulders (0x5C / 0x5D) level 2 (the Titan's Mitt).
Gray rocks lift with the glove (dp23 scene). Not ported: the big boulders'
strain-lift (Link_PerformThrow with x1 5 / 6: player_handler_timer 1).

## Round 24: the Desert Palace walked (DesertPalace.lua)

New module `src/zelda/alttp/DesertPalace.lua`, installed from Game.lua and
run through small hooks in Palace.lua (TYPES / FIGHTS / prep / update /
died / draw, `_h.spawn`, the prize), Extract.lua (`t.dpal`) and Layers.lua
(the BG1 map's offset). GBA tables (file offsets, found by value with
`r24/py/tabfind.py`, the chars are the GBA's):

| What | GBA | Notes |
|---|---|---|
| DebirandoPit opening / closing gfx, Draw X / Y (s16) / Char / Flags / Big | `0x175514` .. `0x1755AC` | chars 4, 0x42, 2, 0x49, 0x69, 0x4A |
| Debirando emerge / submerge, Draw X / Y (s16) / Char / Flags / Big | `0x1755C4` .. `0x175628` | chars 0xB8 / 0xB9 / 0x40 |
| Wall cannon Xvel / Yvel / Gfx / OamFlags, spawn X / Y / speeds | `0x175638` .. `0x17565C` | spawn x / y stored as lo / hi byte rows |
| Lanmola RandB / RandC / InitDelay / ZVel (+ the +-16 turn values) | `0x178BD0`, `0x178BD8`, `0x178BE4`, `0x178C00` | |
| Lanmola Char1 / Char0 / Flags / X4 / Y4 / Char4 / Flags4 / Big4 / Char2 / Flags2 / Idx2 | `0x178C18` .. `0x178C7C` | body 0xC6 -> 0x96, shadow 0x6C -> 0xCC |
| Lanmola shrapnel Yvel / Xvel | `0x177894`, `0x17789C` | |
| kConvertVelocityToAngle Tab0 + Tab1 | `0x172805` | read 96 bytes: the SNES reads past Tab0 |
| kMovingWall_Tab0 | `0x167924` | 0x41, 0x81, .. (SNES 0x42..) compared >= at `0x0807AFDA` |
| kDungeonCrystalPendantBit / kBossFinishedFallingItem / kFallingItem_Type | `0x14CADC`, `0x152AAC`, `0x16E5D4` | |
| moving wall objects | room object lists (type-1 0xCD / 0xCE) | 0x43: 0xCD at (18, 4), height 0 |

Behaviour (SNES names; see the module's header for the details):

* **Debirando** (0x63 pit + 0x64): the list's 0x63 is the plain kind, its
  0x64 the fire kind (fireballs 0x55). The open pit (pictures 0-2) holds
  Link unless R is newly pressed (GBA input builder 0x08069AA8: GBA R ->
  SNES filtered_joypad_L 0x10) and drags him 1 px per 256 of its speed
  16. The pit goes with its Debirando (kill memory on the pit).
* **Wall cannons** 0x66-0x69 slide along their wall and fire 0x6B
  cannonballs (24 a frame /16) every 32 frames when open.
* **Lanmolas** 0x54: mound 127 frames, shrapnel 0xC2 (8 rocks with one
  left, else 4), out at z speed 24, wavy flight to a random spot (speed
  10), dive, 128 frames under. A sword hit throws Link back (recoil 32,
  set_when_damaging_enemies 144). At 0 health state 5 (192 frames, the
  body bursts), then the heart container if the screen is clear.
* **The moving wall** (room 0x43, tag 0x1D): four lit torches start it;
  0x2200 sub-pixels a frame, 0x49 px, Link held; collision mode 2 checks
  the BG1 table at x + offset; the state bit keeps it moved (not drawn,
  collision 0) on later visits.
* **The prize** is the palace's: the Desert Palace gives the Pendant of
  Power (bit 2, item 0x39, its message).

Walked (harness and real app) from checkpoints; see PROGRESS-alttp.md
round 24. Engine findings while walking: 0x73's pot room is entered
through a one-sided shutter (0x38: open from the east, shut behind);
0x53's NW -> SW door is an intra-room door the bot crosses by walking
down; the spiral stairs behind 0x63's stair mask return Link if "up" is
still held on arrival (cartridge behaviour, the bot lets go).

OURS: no sound; the fireball trail, cannonball poof / spark garnishes not
drawn; a Lanmola's bursting segments are death puffs
(SpriteModule_Explode not ported); a live cannonball does not keep a
kill tag's screen from being clear; the pit's OAM region juggling.

## Round 25: outdoor enemies, the old man, the Magic Mirror

### The overworld's own sprites (OwEnemies.lua)

The area lists (Npc.lua's per-phase lists) now load the cartridge's way,
read from the GBA: Overworld_LoadSprites (0x080CB140) puts the list into a
16 px grid (RAM 0x02006B80); Sprite_ActivateAllProxima (0x080CA934) loads
the 22 columns from the camera's x - 16 when the area loads; each frame the
camera moved, Sprite_ActivateWhenProximal / ..Big (0x080CA988 /
0x080CA9F8) load the column at x + 0x110 / x - 0x10 (GBA table 0x1728A8,
rows from y - 0x30) or the row at y + 0x110 / y - 0x10;
Overworld_LoadProximaSpriteIfAlive (0x080CBD44) loads a cell once
(0x02007B80) until Sprite_PrepOamCoordOrDoubleRet (0x080C5ACC: x - cam +
0x40 or y - cam + 0x40 above 0x16F) frees it through Sprite_KillSelf
(0x080CB1E0). A killed sprite's cell stays loaded until the area loads
again. Slots: Overworld_AllocSprite (highest free from 13).

| Type | Routine | GBA tables (file offsets) |
|---|---|---|
| 0x00 Raven | SpritePrep_Raven, Sprite_Raven: wait (0x50 x 0x58 box), rise 24, attack at 32 (kRaven_AscendTime 16 / 248), flee at 48 | 0x177498 (bump 0x81 / health 4 / prize 6 in the Light World), 0x1774B0 |
| 0x01 Vulture | dormant 160, rises, circles at (k & 15) + 24 turned 90 degrees | kVulture_Gfx 0x1774BC, Dmd 0x1774C0 |
| 0x0D Buzzblob | kBuzzBlob_Xvel / Yvel / Delay by rng & 7, bounces off walls; the fighter sword zaps Link (Sprite_AttemptZapDamage, LinkState_Zapped 8 x 3 frames) | 0x177568.. (draw X / Y / chars u16 / flags / ext) |
| 0x27 Deadrock | pick a way (every 4th towards Link) 32-63 frames at 32; the sword: damage 0 with sprite_flags & 4 -> sprite_F 15 -> stone at 14 for 255 (two frames a count), shaking from 0x20; the sword tinks on stone | 0x1777E4 (gfx), 0x1777ED (flags), 0x177804 / 0x177808 (speeds) |
| 0x4C Geldman | home (x + 8), within 0x30 every 8th frame: emerge 31, pursue at 16 for 96 (the only state that hurts or can be hurt), sink 8, home after 16 | 0x177CC4.. (emerge / pursue / submerge gfx, draw X / Y / chars / flags / big) |
| 0xC9 Tektite | SpritePrep_Tektite (kGanonHelpers_* 0x178A40: oam 9 / 7, health 8 / 12, bump 3 / 5 by x bit 4), hops 24-31 high in 1 of 4 ways at 16, every 4th a run of small hops, jumps away (32) when Link comes within 40 not facing it | 0x178A68 (dir), 0x178A6C / 0x178A70, Dmd 0x178A74 |
| 0xD4 Land mine | touching Link: 8 frames blinking (kLandMine_OamFlags), then the sprite bomb (Sprite_SpawnBomb -> SpriteModule_Die -> Sprite_4A_BombGuard C 2: 31 frames, hit box 9, hurts Link) | 0x178CCC, Dmd 0x178CD0; kEnemyBombExplosion 0x1773AC.. |

kSpriteInit_Flags2 is the GBA's 0x2275A4 (three entries differ from the
SNES: 0x40, 0x5B, 0x5C). Hooks: Actors.update / swordHit and
Sprites.drawActor are wrapped from OwEnemies.install; Actors.lua reads
a.bump / a.flags5 (SpritePrep_Raven / _Tektite's own values).

No overworld Debirando: no area list of any phase holds 0x63 / 0x64 (the
three GBA tables 0x227D70 / 0x227E70 / 0x2280B0 were scanned).

OURS: no sound; the lists' overlords (0xF4+: falling rocks) are not
loaded; the list's other types (soldiers, octoroks, crabs...) are still
not spawned; the Cukeman talk, the zap's palette flash; the land mine's
bomb hurts only Link and breaks nothing; sloped tiles count as solid for
the sprites; slot numbers count only these sprites.

### Big rocks and the gloves (BigRock.lua)

The glove a liftable attribute wants is TileDetect's kTile50data (the GBA's
u16 copy at 0x16831E: 0x54, 0x52, 0x50, 0x51, 0x53, 0x55, 0x56) into
kGetBestActionToPerformOnTile_a (0x168268: 0, 1, 0, 0, 2, 1, 2): 0x52 and
0x55 the Power Glove, 0x53 and 0x56 the Titan's Mitt (Carry.lua's pair rule
gave 0x55 / 0x56 nothing and 0x53 the glove; Carry now asks C.need).
Overworld_HandleLiftableTiles: a big rock's map16 (0x36D, 0x36E, 0x374,
0x375 light; 0x23B-0x23E heavy, imported, cacheVersion 27) ->
SmashRockPile_fromLift: the top left by kBigRockTab1, the secret, the four
tiles to kDoorAnimTiles[20..23] (or [40..43] over a hole), Link lifts it
(kind 6 / 7). OURS: the carried rock is the screen's 32 x 32 picture.

### The old man (OldMan.lua)

Sprite_AD_OldMan and follower 4, from the GBA: kOldMountainMan_Dmd0 /
Dmd1 / Dma (0x176180 / 0x176190 / 0x176210), kOldMountainManMsgs
(0x176178: the GBA's 0xA1-0xA3 = BMG 0x9E-0xA0), the follower trigger
tables kTagalong_IndoorRooms / IndoorInfos / OutdoorRooms / OutdoorInfos /
offsets (0x17EC48 / 0x17EC56 / 0x17ECCE / 0x17ECD4 / 0x17ED06 /
0x17ED0E; the GBA's message numbers are the SNES's + 3, Text.bmgIndex).
The follower's tiles: the GBA's 0x0812F9A8 takes base sheet 0x64 for
Zelda, 0x65 for followers 2-8, 0x59 for 9-11, 0x58 else, + the follower
table's sheet bits (0x22BB1C: follower 4 = 0x400).

- Lost in room 0xF0: faces Link; touching him: message 0x9C, follower 4,
  which_starting_point 5. Gone once Link has the mirror (SpritePrep).
- Following: Link walks at speed setting 12; the 20-step trail (lag 20
  walking, closing to 9 standing, every 4th frame); the spots (24 x 28 of
  Link + 12): 0xF1's 0x99 / 0x9A / 0x9B, area 3's 0x9D. tagalong_event_flags
  are cleared going in or out of doors (Dungeon_ResetTorchBackgroundAnd..,
  ResetAncillaAndCutscene).
- 0x9D: OldMan_RevertToSprite at the trail's next spot + 2; then
  Link_ReceiveItem(0x1A) the Magic Mirror (message 0x6E), starting point
  1, Link held; 48 frames at (8, 4); towards the area list's overlord 0xF9
  (his door) at 8; gone; Link free.
- At home (room 0xE4, subtype2 2): kOldMountainManMsgs[moon pearl] and
  the hearts filled (link_hearts_filler 160).

OURS: the follower is drawn with the old man's own picture under Link
(Tagalong_Draw's tables are not ported); his trail restarts at Link's spot
when a room / area loads; the sitting old man is not a barrier.

### Desert statues

The GBA's Sprite_57 (0x080EE1D0) calls Sprite_CheckDamageToLink_same_layer
(0x080C500C), Sprite_NullifyHookshotDrag and Sprite_RepelDash only, as the
SNES: the statues are not barriers. Round 23's 32 x 32 box is removed (it
trapped Link on the palace stairs once the statues were back at their list
spots after leaving the palace).

## Round 26 (team A): the Dark World, gear, deep water, tools, medallions

All in new modules installed from Game.lua; tables read by
`ExtractA26.lua` (cacheVersion 29). zelda3 names; GBA offsets in each
module's OFF table.

### Crossing worlds (DarkWorld.lua)

| What | Source |
| --- | --- |
| Warp tile | attribute 0x4B under (x + 8, y + 20); x & 15 < 4 or >= 12, (y + 8) & 15 < 4 or >= 11; not while blinking; a guard flag (link_triggered_by_whirlpool_sprite) until Link leaves the tile |
| Module09_MirrorWarp | world bit flipped, same x / y; white filter (to white in 31 steps, back to step 66, every 2 frames after 8) and the HDMA wave simulated for its timing (var0..var7 as the SNES); then LinkState_CrossingWorlds |
| Bump back | TileCheckForMirrorBonk points (x+2/13, y+10/21): a top point and two points solid, or deep water without flippers -> cross again |
| Portal 0x6C | at bird_travel[15] + (0, 8); flags `kSprite_WarpVortex_Flags` GBA 0x1750AC (read by 0x080D5526); armed once Link is off it or after 256 frames |
| Bunny | Dark World without the pearl (GBA inventory 0x3B); LinkOam yt 0x21, rt = steps & 3; palette row 0xE0 (LoadGearPalettes_bunny, armour 3); Link_HandleYItem only the bottle and the mirror; song 4 |

OURS: the wave is not drawn; the filter is a "lighten" fill with Link
redrawn on top; no poof; the indoor mirror skips the mosaic.

### Gear (Gear.lua)

GBA receipt tables: addresses (u32, 0x02002300 + n) at 0x16E344, values
(int8) at 0x16E4A4. GBA layout: grid slot n = byte 0x1F + n; 0x38 gloves,
0x39 boots, 0x3A flippers, 0x3B pearl, 0x3D sword, 0x3E shield, 0x3F mail,
0x4B pieces of heart, bottles 0x25 / 0x2B / 0x31 / 0x37 (2 empty, 3 red, 4
green, 5 blue, 6 fairy, 7 / 8 bees). Link's palettes: blob rows 0xB0 green,
0xC0 blue, 0xD0 red, 0xE0 bunny.

### Deep water (Swim.lua)

GBA 0x167E0A kSwimmingTab1, 0x167E10 Tab2 (u16), 0x167E14 Tab3 (u16),
0x167E26 Tab4 (s16), 0x167ED0 / 0x167ED3 kRecoilVelY / Z. The stroke buttons
are B, A and R.

### Tools (Tools.lua)

| Item | GBA tables / constants |
| --- | --- |
| Fire Rod | FireShot_Draw X2 / Y2 0x17EFC8 / 0x17EFD8, chars 0x17EFE8 (0x1D, 0x3D, 0x3C), burst 0x17EFEB; spawn {0,0,-8,16} / {-8,16,3,3}, speed 64 (zelda3) |
| Ice Rod | spread chars / XY 0x17EF70 / 0x17EF80; spawn {0,0,-20,20} / {-16,24,8,8}, speed 48 (zelda3) |
| Hammer | kHammerAnimDelays 0x169098; peg map16 0x21B -> 0xDCB |
| Shovel | delays {7,18,16}; diggable 0x34 0x71 0x35 0x10D 0x10F 0xE1 0xE2 0xDA 0xF8 0x10E -> 0xDC9; flute at area 0x2A spot 0x492 |
| Boomerang | kBoomerang_Tab0..5 0x16E0B4..; flags 0x1803AC, XY 0x1803B4, spin delays 0x1803C8; char GBA 0x46 |
| Hookshot | AncillaAdd_Hookshot 0x080ADBF0: vel 0x16E5BC / C0, spawn 0x16E5C4 / CC; pull 0x167FD4..E0; draw chars / flags 0x17F914 / 0x17F920 |

SNES -> GBA OBJ char numbering for page-0 ancilla chars: GBA = (row & 7) *
32 + (row >> 3) * 16 + col (checked on the arrow, explosion, fire and ice
tables).

### Medallions, tablets, sealed entrances (OwEvents.lua)

Anim states / delays: Ether 0x167FE4 / 0x167FF0, Bombos 0x167FFC /
0x168010, Quake 0x168024 / 0x168030. kEntranceTrigger Y / X 0x1719D8 /
0x1719E0, sizes (u16 on the GBA) 0x1719E8 / 0x1719F0. Misery Mire (area
0x70, trigger 2) map16 0xE48..0xE77, Turtle Rock (0x47, trigger 3)
0xE78..0xE87, Skull Woods (0x40) 0xE06..0xE1A, kept by save_ow_event_info
bit 0x20 (progress.owEvents). Tablets: sprite 0xF2 in the area lists
(Ether area 3, Bombos 0x30), messages 0x10D / 0x10E / 0x10F.

OURS: spell pictures (a flash), 96 frames of spell, no rain / shake /
palette fade in the entrance sequences, no tablet crumble.

### Cape and bottles (Cape.lua)

kCapeDepletionTimers {4, 8, 8} (zelda3); potions and fairy as
LinkItem_Bottle. OURS: Link at half alpha under the cape; instant refills.

### Sound effects (findings)

GBA 0x0812A324 = play sound id n: u32 table 0x08198C94 (low 16 bits the
m4a song, bits 16-23 its channel group, the top byte flags). The GBA's call
sites pass GBA ids (the hookshot's chain: 0x28 where the SNES passes 0x0A),
so the SNES numbers cannot be translated by one table.

## Display registers (round 5, findings, not used yet)

The GBA keeps shadow copies of its display registers in RAM (base
`0x03002230`) and the VBlank routine at `0x08068A0C` writes them: DISPCNT
`+0x50C`, WININ `+0x51A`, WINOUT `+0x51C`, BLDCNT `+0x51E`, BLDALPHA
`(+0x999 << 8) | +0x998`, BLDY `+0x99A & 31`, WIN0H from the HDMA table at
`0x02001400`, WIN0V `0xFF`. `0x081271C8` (called from `0x0807153A`) sets
BLDCNT `0x3048` (BG3 over OBJ + backdrop, alpha 15/15), WININ `0x3F`, BG3 on
and BG1/BG2 off; `0x08131D74` sets BLDCNT `0x2E40`, WININ `0x3F`, alpha 15/15.
Round 8 settled them: the dialogue window uses none of these (the text
code 0x08127E00-0x08129FFF writes no blend or window register; the centre
word 0x107F is the blank tile, the glyph tiles are cleared to 0 by
0x08129BC4), so its inside is clear. 0x081271C8 is the rescued-maiden
screen (dungeon submodule 0x19, step 10 of table 0x14CDB0): BG1/BG2 off,
BG3 alpha 15/15 over OBJ and backdrop. The opening telepathy now uses that
setting (the GBA routine for the opening itself is not located).

## Not cartridge art yet

Drawn by our code, not from cartridge graphics or layouts:
* **Title**: the game choice under the cartridge's title is our line of
  text (the cartridge's menu letters, our placement and "- -" marks). The
  title's sprites (sword, "PRESS START", copyright) are not drawn, and the
  cartridge's game-select screen is not decoded (round 8: still not).
* **File select and name entry**: round 13: CHOOSE A FILE, ENTER A NAME
  and CHOOSE A GAME are cartridge art (see "The front end (round 13)"); the
  letters of the names and of the grid are the HUD's menu letters (ours).
* **Text window** (round 8): the inside is clear as on the cartridge (no
  fill). The opening telepathy hides the room layers with the maiden
  screen's setting (0x081271C8); the opening's own routine is not located.
* **Item menu** (round 8): cartridge art and logic, except crystals, the
  dungeon items in the equipment box and the ability box's labels.
* **Overworld map** (round 8): cartridge picture, palettes and tilt; the
  Link marker (his head cell, our placement) and the fade are ours.
* **No dungeon map screen** (GBA submodule 3 `0x080B6409` not ported).
* **Escape sprites** (round 7, `Sprites.lua`): the actors are cartridge
  art (bug round: Link's sword and shield and the uncle's are cartridge
  art too, `Weapon.lua`); round 9: shadows under Link, sprites and drops
  are the cartridge's big shadow char (round 10: the small one too, sheet
  0); round 16: the 0x6A guard's ball and chain are cartridge art
  (BallChain.lua).
  Round 9: the drops of cut/lifted bushes, grass and pots are cartridge art
  (absorbable tables, rupees from sheet 96 with the shimmer; round 10: the
  heart from sheet 0); the debris of a
  cut bush or broken thrown pot/bush is cartridge art (Garnish16 tables,
  outdoor misc sprite palettes); round 10: the enemies a secret holds spawn
  and draw from the area's sprite set (the cucco and the hoarder only look
  right where the area's set carries them, as on the cartridge). Round 11: an opened key
  door or shutter is drawn with the cartridge's opened-door words (no more
  black rectangles); the castle gate's
  opening frames before the last are not drawn. Bug round: an opened chest
  shows the cartridge's open-chest words; the rising item is its item-menu
  icon; round 10: a lifted/thrown pot, bush or small rock is the
  cartridge's sprite 0xEC (big rocks keep their tile picture).
* **Dark rooms and game over** (round 7): the darkness and lamp light are a
  LOVE overlay; game over is a fade (no death spin, no game-over/continue
  menu).
* **Rain** (round 7): the picture is the cartridge's overlay 0x9F; the
  blend is LOVE alpha/add, not the GBA's registers.
* **Four Swords** (`FourSwords.lua`): rupees are drawn diamonds (polygon +
  line), the HUD bar, scores and timer are LOVE-font text on a rectangle, the
  "STAGE CLEAR" results box and "waiting for the host" are LOVE-font text, and
  the other players' Links are the ALttP Link recoloured by our palette swap.

Cartridge art in use: the item menu and the overworld map screen (round
8); the escape's sprites (guards, knife guard, rats,
ropes, keese, key, uncle, priest, Zelda, shelf, levers), the open castle
gate and the rain overlay (round 7); the title screen (logo, scenery,
subtitle, palettes);
the HUD (template, hearts, magic meter, counters, item box frame, palettes);
dialogue (messages, font, widths, window border); overworld maps, tiles and
palettes; Link's sprite sheet and palette; interiors (tilesets, palettes,
layers); Four Swords floor maps, tiles and palettes.

## Round 26 (team B): the later palaces, their enemies and bosses

New hub `src/zelda/alttp/Dungeons26.lua` (installed from Game.lua, imported
from Extract.lua as `data.t.d26`): `D.MODULES` lists the palace modules
(Hera, Agahnim, PalaceOfDarkness, SwampPalace, SkullWoods, ThievesTown,
IcePalace, MiseryMire, TurtleRock, Ganon; missing files are skipped). Each
module has NAME / TYPES / FIGHTS / extract / prep / update / swordImmune /
died / draw / install and is run by Palace.lua through `Palace.register`
(small hooks in prep, enterRoom, updateOverlords, update, swordImmune, died,
draw). Actors.lua gained `a.noTouch` (the sprite checks its own contact).
Every module header lists its GBA offsets, the zelda3 routines and what is
OURS.

| What | GBA | Notes |
|---|---|---|
| kDungeonPitsHurtPlayer | `0x1676FE` (57 u16) | |
| kSinusLookupTable | `0x173F38` | firebars, Arrghus |
| kDungeonRoomOverlay pointers | `0x1633C8` (21) | read by GBA Module07_03 `0x080886B4` -> Dungeon_DrawRoomOverlay `0x0808812C` |
| kPredefinedTileData | `0x164520` | SrcPtr base (bomb floor = +0x220) |
| peg frames | bg sheet 0x0F tiles 0-15 | VRAM 0x1D0-0x1D7 = slot 7 tiles 16-23 (slot 7 is sheet 0x0F) |
| star tiles | bg sheet 5 tiles 48 / 49 | VRAM 0x1ED / 0x1EE |
| Moldorm / Mini Moldorm | `0x175840`.., `0x17D404`.. | body char 0x1D page 1 (literal 0x11D at `0x081104EA`) |
| Firebar char | literal 0x48 at `0x080D8A6A` | |

* **Pegs**: a hit on 0x1E (B held < 9) sets sprite_F 15; at 11 the state
  flips, the game waits 16 frames while the peg tiles step through the
  frames, then 0x66 / 0x67 swap. Lowered pegs (0x66) are floor.
* **Overlays / star tiles**: Dung_TagRoutine_Func2 (base by tag, +1 on a
  0x3B star) draws the overlay's 4 x 4 holes (0xA4) or floor and rewrites
  BG2's attributes (0xEE / 0xFE floor, else 0x20); the star CHR swaps.
* **Pits**: Player_TileDetectNearby's four points; all four -> the fall (6
  x 10 frames) into header byte 9's room on plane byte 7 & 3, or 8 damage in
  the pit-hurt rooms; some -> pulled in.
* **Bosses** use test-only hooks where an item is team A's: Helmasaur's
  hammer, Arrghus' hookshot, Kholdstare's fire, Trinexx's rods, Ganon's
  silver arrows, Blind's maiden.

OURS (all rounds' modules): no sound; explosions are death puffs; Link
shrinks instead of the falling poses; the pull towards a pit is 1 px a
frame; see each module's header for the rest.

## Round 27 (team A): scaffold and research (cut short)

`ExtractA27.lua` imports / installs nine round-27 modules (Grove,
FatFairy, Smiths, Flute, Items27, Story27, OwEnemies27, DungeonMap, Sfx --
Sfx last); all are stubs this round. The GBA addresses found (Master Sword
grove special-area tables, the Master Sword sprite 0x62 tables, the sound
table 0x08198C94 and its call-site ids, the smiths / frog / flute / bird
travel tables) are listed in PROGRESS-alttp.md, Round 27 (team A).

## Round 27 (team B): later palaces' enemies, mechanics, maidens, ending

New modules (each header lists its GBA offsets, zelda3 routines and OURS):
`Enemies27A.lua`, `Enemies27B.lua`, `Traps27.lua`, `Mech27.lua`,
`Floors27.lua`, `Ending27.lua`, loaded through `Dungeons26.lua` (D.MODULES)
and imported into `data.t.d26[NAME]` (cacheVersion 32).

| What | GBA | Notes |
|---|---|---|
| sprite active / prep routine tables | `0x174138` / `0x17451C` | |
| overlord dispatch | `0x172978` (27) | 0x01-0x09 = zelda3; falling square 0x0A-0x10 (seven); from 0x11 GBA = zelda3 + 1 (Pirogusu 0x11-0x14, tile room 0x15, Wizzrobe 0x16, Zoro 0x17, pot trap 0x18, invisible Stalfos 0x19, Armos 0x1A, snake 0x1B) |
| kDungTagroutines | `0x152AC4` | water off / on / gate = tags 0x18 / 0x19 / 0x1A |
| falling-square paths | `0x172B04`-`0x172B1C` | 7th path is GBA-only (room 0x79) |
| ending scene funcs / lengths | `0x1709AC` / `0x170950` | 16 scenes |
| ending texts / staff roll | `0x1965D4` / `0x197320` (count at `0x1979A4`) | decoded at import |
| kCrystalMaiden_Msgs | `0x17A9EC` | |

Hooks for team A's items: `Enemies27B.fireHit` (Freezor), `.hammerHit` /
`.hammerAt` (Terrorpin); `Enemies27A.ancillaHit` (Firesnake);
`Floors27.somariaBlock` / `somariaBlockCreated` / `somariaPoof` /
`somariaPlatform` / `caneRideRoom`; `Mech27.setFlooded` / `damOpen` /
`spikeFlags`; `Traps27.somariaSwitch` / `bunnyBeamHit` (Link should become a
bunny via `game.tempBunny`, not read by DarkWorld yet). The pull / action
button is the `"r"` key. 0x94 is shared: Floors27's flying tiles
(`a.flyTile`) and Enemies27B's Pirogusu (`a.pirogusu`) hand each other's
sprites over.

OURS (see the headers): no sound; garnishes partly; the water windows are
rectangles; ending scenes show the map with no people / pans and the three
dungeon scenes are black; crystal and Triforce are drawn shapes.

Tests (round 27B): all 35 `zelda_alttp_*` test files pass (new `zelda_alttp_r27b_test` 16 checks, `_a` 70, `_b` 63, `_c` 38, `_d` 40, `_e` 37, `_f` 33); `zelda_alttp_r26b_b4` clears `g.pitFall` in its run helper because Ganon's falling floor now makes real pits. Audits rooms 304 / 304, overworld 80 / 80.
