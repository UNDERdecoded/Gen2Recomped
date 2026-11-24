# Zelda progress: alttp

Owner: ALttP agent. Contract: `docs/zelda/CONTRACT.md`. Details and parity
notes: `docs/zelda/alttp.md`.

## Milestones

- [x] M1 ROM survey + detection: header `AZLE`/`GBAZELDA`, SHA-1 recorded in
      `RomMap.lua`; graphics, palettes, overworld maps, tile attributes, Link,
      tilesets, M4A song table located (see alttp.md table). Dungeon room maps
      located, not decoded. Text: Four Swords text found (plain ASCII); ALttP
      text (compressed) not located yet.
- [x] M2 Importer (`Extract.lua`): six stages (tables, palette, sheets, link,
      maps, music), stage stamps make it resumable, progress 0..1, structural
      checks on every table, writes only through the cache object (CacheFs
      under the foundation's prefix). Music reuses `src/core/M4ASynth.lua`
      (walker + synth) from the Gen 3 port.
- [~] M3 Engine — overworld vertical slice playable:
  - [x] Light World + Dark World overworld, both BG layers, per-screen
        tilesets/palettes, camera at 240x160 clamped to areas, area scroll
  - [x] Link: walking (ROM speeds), walk cycle, collision, ledge hops, sprite
        from ROM pose tables
  - [x] music via the M4A synth (song mapping unverified, see alttp.md)
  - [x] save/restore position (`game:save()` table)
  - [ ] title/file select from the cartridge (placeholder title card now)
  - [ ] dungeons/interiors, entrances (Link's house -> castle escape)
  - [ ] enemies, NPCs, text boxes, HUD, item/map menus, sword/items, SFX
- [~] M4 Parity: speeds, walk timing, Link poses, tile attributes, palettes,
      maps match the ROM (tests + screenshots). Corner nudging, exact hop arcs,
      scroll details, RNG, damage, drops not done.
- [~] M5 Online: presence co-op on ZeldaSession (coloured Links in your Hyrule,
      snapshots/events, clamped).
- [~] R2.1 FOUR SWORDS (round 2): decoded the FS engine (gfx/palette groups,
      area tilesets, 123 floor maps, collision, world tables, animated tiles,
      the four Link palettes -- see alttp.md "Four Swords"). Playable: any
      world floor, 1-4 players online (host-authoritative rupees, scores,
      results, late join), solo from the title menu. Ours: Link sprite
      (recoloured ALttP Link), rupee layout/shape, timer, results, spawn.
      Not ported: FS objects/enemies/grass/pots, Force Gems, sword, walk-in,
      canopy priority, tile animation.
- [ ] R2.2 Interiors/dungeons: not started this round (ALttP room maps at
      ~0x1618D8 located in round 1, not decoded).
- [ ] R2.3 Music table: dispatcher found (0x0800D3xx, songs 400-499 BGM); the
      ALttP area -> song mapping is still the 399+id guess.
- [ ] R2.4 HUD/text/enemies/sword/title: not started.
- [~] R3.1 Interiors: room map tables decoded (BG2 0x1618D8, BG1 0x162258,
      304 rooms, loader 0x0807FF10; dungeon palette loader 0x0813041C);
      import stage "rooms" (cacheVersion 3). Link's house enter/exit works.
      Room header (tileset/palette), dungeon tile attributes, entrance tables,
      doors/stairs NOT decoded; castle/sewers/sanctuary/Eastern Palace not
      wired. See alttp.md "Interiors".
- [x] R4.1 Room headers (0x164020, = SNES Dungeon_LoadHeader 0x08080D00),
      palette sets 0x22BC6C, entrances 0x150EC4 (0x2C each), tile
      attributes 0x15E114/0x15E794/0x15E254 imported (cacheVersion 4).
      Link's house tileset/palette/collision now from the cartridge; guesses
      removed. Room objects/doors/stairs, entrance and exit tables NOT read.
- [~] R4.2 Cartridge art: title, HUD, text boxes done in round 4b; file
      select, menus, maps and Four Swords art not yet (alttp.md).
- [ ] R4.3 Opening (rain, uncle, passage, sword, soldiers, sewers): not started.
- [ ] R4.4 Music table / FS visual fixes: not started.
- [ ] R3.2 HUD/text/sword/uncle: not started.
- [ ] R3.3 Enemies: not started.
- [ ] R3.4 Real title/file select/new game in bed: not started.
- [ ] R3.5 Music table / FS visual fixes: not started.
- [x] M6 Tests: `tests/zelda_alttp_logic_test.lua` (no ROM, 15 checks),
      `tests/zelda_alttp_extract_test.lua` (ROM, 159 checks, skips without ROM).
      Scratch harness renders to `G:/Gen2Recomped/scratch_claude/zelda/alttp/shots/`.

## Verified (2026-11-08)

- `python tools/run_lua_check.py tests/zelda_alttp_logic_test.lua` -> 15/0
- `python tools/run_lua_check.py tests/zelda_alttp_extract_test.lua` -> 159/0
- LÖVE harness (scratch): title, Link's house, walking, red friend Link,
  2C -> 1B area scroll after 91 frames on the path, Dark World pyramid,
  Kakariko — PNGs in scratch, all visually correct.

## Verified (round 2, 2026-11-08)

- `tests/zelda_alttp_fs_test.lua` -> 18/0 (import, 6 worlds, floor 52 forest,
  4 tunic palettes, 18 floors with open start + walls, seeded rupees off
  walls, ranking ties, layer decode, host+guest: follow, contested rupee to
  host, guest pickup confirmed, snapshot, results, late join with taken list)
- logic 15/0, extract 159/0 still pass.
- Multi-process (real ENet on 127.0.0.1, real LINK PLAY menu):
  `G:/Gen2Recomped/scratch_claude/zelda/alttp/fs_tp/run.sh 4` -> 27 ok, rc=0
  (4 players in the room, every Link seen by every player, every player's
  rupee counted identically on all four, results on all four, clean close);
  2 players -> 13 ok. Shots in `.../alttp/fs_tp/out/`.

## Verified (round 3, 2026-11-08)

- extract 165/0 (adds 304 rooms imported, house spawn open, north wall,
  interior draws, enter by walking up, leave by walking down), fs 18/0,
  logic 15/0.
- LOVE harness shots 12-14 in `G:/Gen2Recomped/scratch_claude/zelda/alttp/shots/`.

## Verified (round 4, 2026-11-08)

- extract 169/0 (adds header/entrance values for Link's house, door spawn,
  chest attribute 0x63, table blocks, floor open), fs 18/0, logic 15/0.
- Harness shot `13_house_walk.png` shows the cartridge colours (wood floor).

## Round 4b (2026-11-08)

- [x] 4b.1 HUD from the cartridge: the GBA's own HUD routines (0x080A7xxx)
      found and ported (`Hud.lua`): 6x32 template, hearts (capacity then
      health, 10 a row), magic column, rupee/bomb/arrow/key digits (palette 8
      when full), the HUD charblock of the language (0x0812EED8, US English),
      HUD palettes (0x08130384). Drawn in the overworld and in rooms.
- [x] 4b.2 Title screen from the cartridge: logo (BG1) over the castle and
      lake (BG2), English subtitle strips, palettes and scroll from the title
      loader (0x0812D430/0x0812D4CC). The game choice under it is written with
      the cartridge's menu letters; its placement is ours (see alttp.md).
- [x] 4b.3 Dialogue: the text is a Nintendo BMG file, scrambled per byte by
      offset (reader 0x08129E0C, key table 0x180CD0) -- decoded, 455
      messages. Cartridge font (0x3B5758, 8x16 4bpp, widths 0x195D98),
      window border tiles/position (0x081290B4), SNES text commands (line,
      scroll, wait, speed, wait-for-key, name, window type). `Text.lua`.
- [x] 4b.4 Doors: overworld entrances from the cartridge's door tables
      (door tile pair 0x1537DE/0x153836, area/pos/id 131 entries at
      0x15388E/0x153994/0x153A9A, GBA routine 0x0808BB88); exits from room
      door lists (0x162C28, SNES door format; ExitToOw/entrance doors get
      attribute 0x8E). The hand-placed rectangles are gone. 101 of 118
      overworld doors are entered by walking straight up at them.
- [~] 4b.5 Opening: a new file starts at entrance 0 (Link's bed, room
      0x104), Zelda's telepathy (message 31, borderless) then the uncle's
      message 13. Not ported: rain, night palette, bed pose, uncle sprite,
      secret passage, sword, soldiers, castle, sewers, sanctuary.
- [ ] 4b.6 Pause/item menu, map screens, file select/name entry, Four
      Swords art, music table: not done (see alttp.md "Not cartridge art yet").
      Found but not used yet: per-language item-name strips (0x16DF40 ->
      0x16C428 etc., HUD-charblock words) for the item menu.
- [ ] 4b.7 Four Swords canopy: tried drawing layer A over the players;
      layer A also holds ground in places (Links vanished), so it was
      reverted. Needs the per-tile BG priority, not decoded.

Verified (round 4b): logic 28/0, extract 188/0, fs 18/0
(`python tools/run_lua_check.py tests/zelda_alttp_<x>_test.lua`). Harness
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r4b/harness/` (SCENE=scenes,
text, opening), shots in `.../alttp/r4b/shots/` (r4b_01..15), looked at:
title, HUD outdoors/indoors with values, uncle/hint/telepathy text, the
opening in bed, leaving the house, entering a cave by the table.

## Round 5 (2026-11-08)

- [x] 5.1 Exit table: the cartridge's kExitData (rooms `0x1501C0`, 79
      entries, screens, Link X/Y, scroll) read at import (cacheVersion 6);
      leaving a dungeon or Link's house puts Link where the cartridge does
      (house: 0x8B8,0xAE8), other houses use the SNES cached-entry rule.
      Link then walks 16 px out of the doorway (ours: the walk-out routine
      is not located).
- [x] 5.2 Room to room: room layout byte + kLayoutQuadrantFlags
      (`0x14CDDC`) give the camera area (quadrant or 512 px); walking out of
      it is an intra-room (quadrant) or inter-room (room +-1/+-16)
      transition with a camera pan and a 16 px walk; doorways opened from
      the door lists (left/right position tables `0x1677A8`/`0x1677C0`);
      the third room layer (lower floor of two-level rooms) is imported and
      drawn. Castle 1F 0x61 <-> 0x60 / 0x62 verified by a BFS route bot.
- [x] 5.3 Stairs between rooms: the object lists (`0x162768`, SNES 3-byte
      objects, GBA layers end with 0xFFF0 + door words) are parsed for stair
      objects (106 rooms, 143 stairs); their attributes are written as the
      SNES does (0x26/0x38/0x39/0x5E/0x5F + stair number 0x30-0x37), and
      Dungeon_DetectStaircase sends Link to header destination 10 + n.
      Verified: Zelda's cell block 0x80 -> 0x70 (bot + test). Link keeps his
      spot and steps 24 px off (the spiral/straight stair animations are not
      ported). NOT done: in-room layer stairs (0x31/0x32, Link on BG1), so the
      castle hall's upper floor (stairs to the throne room 0x51) is not
      reachable; key doors, shutters, bombable walls stay shut.

- [ ] 5.4 Menus in cartridge art (pause/item menu, map screens, file
      select, name entry, copy/erase, title sprites): NOT done this round.
      Display-register findings for the text window and telepathy recorded in
      alttp.md "Display registers"; the 50 % fill and black overlay remain ours.
- [ ] 5.5 Opening completion (rain, night palette, bed pose, uncle sprite,
      sword, soldiers, sewers, sanctuary), music table, FS sprites, canopy
      priority: NOT done this round.

Verified (round 5): logic 28/0, extract 201/0, fs 18/0. Harness
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r5/harness/` (SCENE=route is the
scripted bot: title -> opening texts -> BFS walk out of the house -> exit
table spot -> castle hall 0x61 -> west wing 0x60 -> east wing 0x62 -> cell
block 0x80 stairs -> 0x70, "ROUTE PASS"; the castle and cell block are
reached by teleport, no overworld route bot). Shots looked at in
`.../alttp/r5/shots/`: r5_01/03 house exit, r5_10-13 castle hall and wings
(lower floor layer), r5_20/21 stairs 0x80 -> 0x70, r5_31 out of the house,
r5_33 east wing.

## Round 6 (2026-11-08)

- [x] 6.1 Escape data from the cartridge (cacheVersion 7, alttp.md "The
      castle escape"): room sprite lists `0x228DF0`, chest table `0x1532FE`,
      overworld pit table (`0x0808B55C`: area 0x1B -> entrance 0x7D),
      overworld secrets `0x22C624` (the castle bush hides hole 0x80), map16
      table `0x155B4E`, combat tables (health, bump, hit boxes, kPlayerDamages,
      kEnemyDamages, sword boxes + OAM offsets, swing delays), entrance planes.
- [x] 6.2 Two levels and in-room stairs (SNES Dungeon_LoadObjectAttribute,
      Module07_08/10): lower table from the GBA third map; stairs 0x31/0x32
      and 0x1B/0x1C/0x1D; inter-room stairs keep the header's plane; throne
      room stairs 0x29.
- [x] 6.3 Locks and chests: small-key doors, shutters (room tags), chests
      with the cartridge's contents, the cell lock (big key), per-room memory
      saved.
- [x] 6.4 Sword and actors: B swings with the cartridge's steps and hit
      boxes; sprites from the room lists with cartridge health/hit boxes/bump
      damage and key drops; uncle (sword, message 14), Zelda (follows,
      message 33), shelf, switch, priest (message 23). AI, recoil, damage
      class, drawing are ours (alttp.md).
- [x] 6.5 Overworld: A lifts bushes, the sword cuts them, secrets reveal
      holes, pits use the cartridge's pit table. Castle front gate entered by
      its door position (ours).
- [~] 6.6 Escape end to end: the bot plays a new file from the bed through
      the house, the overworld (lifting the castle's hole bush), the secret
      passage (uncle, sword, its wet stairs) and the courtyard (cutting
      bushes) with no teleports and no position pokes (0 snaps): 12 PASS,
      then FAIL at the castle's front gate (the bot gets stuck south of the
      courtyard; `r6/out/route_log.txt`). An earlier run, which still snapped
      Link onto its 4 px grid (38 snaps), went through the gate into the hall
      and its planner walked 0x61 -> 0x51 -> 0x52 -> 0x62 -> 0x72 -> 0x71 ->
      0x70 -> 0x80. Caveat: the GBA map draws the front gate CLOSED in this
      phase; entering it (Interior.BIG_DOORS) is ours -- the cartridge's way
      from the courtyard into the castle is not identified (the east wing
      door, entrance 5, is not reachable from the courtyard on our
      collision). The cell block, Zelda, the
      shelf, the sewers and the sanctuary are scripted in
      `r6/harness/route6d.lua`/`route6e.lua` but were NOT reached by the bot
      in a single run this round; tests cover the guard, big key, uncle and
      hole directly. Rain and the night colours outside: NOT done.
- [ ] 6.7 Menus in cartridge art: NOT done this round (see "Not cartridge
      art yet").
- [ ] 6.8 Music table, Four Swords sprites and canopy priority: NOT done.

Verified (round 6): logic 32/0, extract 218/0, fs 18/0
(`python tools/run_lua_check.py tests/zelda_alttp_<x>_test.lua`). Route bot:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r6/harness/` SCENE=route6
(route6.lua + route6b..e.lua, bot.lua, plan.lua), log in
`.../r6/out/route_log.txt`, shots `.../r6/shots/r6_*.png` (looked at:
r6_05 outside, r6_10 bush, r6_11 the revealed hole, r6_12 the passage, r6_13
uncle, r6_14 courtyard, r6_15 hall). The harness keeps its import in
`.../r6/out/store.bin` (scratch, G:).

## Round 7 (2026-11-08)

- [x] 7.1 Sprite graphics from the cartridge (cacheVersion 8, import stage
      "sprites", `SprExtract.lua` + `Sprites.lua`, alttp.md "Sprites"): the
      GBA's own sprite sheet table `0x22B324` (118 LZ77 sheets), its OBJ VRAM
      layout (loaders `0x0812E7B0`/`0x0812E8DC`), the sprite palette loaders
      (OBJ rows 0-7 from the palette blob, `0x08130030`...`0x081332F0`),
      kSpriteInit_Flags3 `0x22788F` and the per-sprite draw tables (found by
      value; the GBA widened x/y to s16 and renumbered chars). Drawn with
      them: blue/green guards (head, body, weapon), the knife guard 0x4B,
      the ball-and-chain guard 0x6A (with the guard routine, see below),
      rats, ropes, keese, the small key (thin-and-tall), the uncle, the
      priest, Zelda (her tiles from the follower sheet the GBA copies,
      kCrystalMaiden tables; also used for Zelda following Link), the shelf
      and the pull switches. Plain rectangles stay only as the fallback for a
      cache without the stage.
- [ ] 7.1b NOT done: Link's sword sprite (still the hit-box outline), the
      uncle's sword and shield (DMA'd from Link's weapon graphics), shadows,
      hearts/rupee drops (no drops yet), opened chest and opened door
      pictures (the doorway is still a black fill, the chest keeps its closed
      picture).
- [x] 7.2 Into the castle the cartridge's way: the GBA's big-door rule
      (`0x0808C044` -> `0x0808BE18`, SNES Overworld_HandleEntrances): Link
      walking up at a 16x16 tile whose top-right map8 cell is 0x149 or
      0x169 (0x169 only during the escape) opens the door; the castle's
      front gate is such a door (0x169 at 2032,1792). It is the cartridge's
      way from the courtyard into the hall; `Interior.BIG_DOORS` (entering
      the closed gate by position) is removed. The open gate is drawn with
      map16 0xDBA-0xDBD (the last kDoorAnimTiles frame) from the cartridge's
      map16 table; the intermediate frames are not drawn (ours).
- [~] 7.3 Route bot: bed -> house -> overworld -> hole bush -> passage ->
      uncle/sword -> courtyard (bushes cut, the bot now lines up with the
      16 px bush grid) -> the gate opens -> the hall 0x61: 14 PASS, no
      teleports, 0 snaps. It then FAILS: the harness room planner cannot
      find the way from the hall to the cell block (with its edge bug fixed
      it reaches 0x40-0x43/0x50-0x53/0x60-0x63 only: 0x62 shows no stair
      attributes and its header reads `C0 00 00 04 00 00 00 C0 ...`, so the
      east wing's stairs down to 0x72 are not in our room model). Cell block,
      Zelda, the shelf, the sewers and the sanctuary are NOT reached by the
      bot in one run.
- [x] 7.4 Rain and the night colours outside: overlay screen 0x9F (the
      cartridge's rain picture, map 0x9F of the GBA overworld table)
      half-added over the Light World while the escape is on, lightning on
      the SNES frames, the SNES scroll jumps (alttp.md "Rain").
- [x] 7.5 Game over: out of hearts -> a fade, then Continue at the
      entrance with 3 hearts (SNES rule). The death spin and the cartridge's
      game-over menu art are NOT drawn (ours: the fade).
- [x] 7.6 Dark rooms (header byte 0 bit 0: the passage 0x55, sewers 0x41,
      0x42, 0x32, 0x22, 0x21): the BG layers are darkened, sprites stay lit;
      the lamp gives a light round Link. The GBA's darkness/lamp-cone
      registers are not decoded (ours).
- [ ] 7.7 Menus in cartridge art (pause/item, maps, file select, name
      entry, copy/erase, title sprites, text-window/telepathy blends): NOT
      done this round.
- [ ] 7.8 Music table, Four Swords sprites and canopy priority: NOT done.

Verified (round 7): logic 32/0, extract 229/0 (adds sprite import, guard /
uncle / Flags3 / palette tables, the OBJ VRAM layout, the castle gate's
big-door rule and its escape-only condition, game over and continue), fs
18/0. Route bot `G:/Gen2Recomped/scratch_claude/zelda/alttp/r7/harness/`
SCENE=route6: log `.../r7/out/route_log.txt` (14 PASS, then FAIL at the
cell block). Shots looked at in `.../r7/shots/`: `r7_spr_55/80/61/12/51/
21/32/02` (sprites in each room: uncle, Zelda, guards, ball-and-chain
guard, priest, shelf, rats, keese, ropes, switches; SCENE=sprshot),
`r7_20_gate_open` (the open castle gate), `r7_15_hall`, `r7_30_rain`,
`r7_31_lightning` (SCENE=rainview). The harness keeps its import in
`.../r7/out/store.bin` (scratch, G:).

## Round 8 (2026-11-08)

- [x] 8.1 The item menu in cartridge art (`Menu.lua`, `MenuExtract.lua`,
      import stage "menus", cacheVersion 9; alttp.md "Item menu (round
      8)"). Ported from the GBA's own module 0x0E/1 (state table
      `0x16E004`): the pre-rendered menu map `0x3BFC58` on the HUD layer
      with the language tile block, the box titles, the 24-slot item grid
      and its word tables, the bottle/bomb rules, the chosen item's icon and
      name (with the bottle/powder/mirror/bow name tables), the blinking
      cursor, sword/shield/mail, the ability box (gloves, boots, flippers,
      pearl), pendants, the slide down/up (BG3 y scroll 4 -> -184, 8 px a
      frame) and the d-pad rules (6 x 4 grid, skipping empty slots). SELECT
      opens it (the GBA's 0x0806CE54); A, B or SELECT close it.
      Checked: the GBA's own routines were run in a scratch Thumb
      interpreter (`r8/py/thumb.py`, `golden.py`) for 6 inventories and
      input sequences (60 frames each); `Menu.lua` produces the same 32x32
      map words in all 6 (`SCENE=menucmp`: 0 differing words). Shots looked
      at: `r8/shots/r8_menu_slide.png`, `r8_menu_new.png`,
      `r8_menu_down.png`.
      NOT done: crystals (shown after Agahnim), the dungeon map/compass/big
      key in the equipment box, the ability box's language-specific labels
      (0x16BE30.. tables, drawn only with some items), the HUD's item box
      showing the chosen item, using the chosen item.

- [x] 8.2 The overworld map screen in cartridge art (`OwMap.lua`; alttp.md
      "Overworld map (round 8)"): the GBA's 512x512 map (8bpp tiles, one-
      byte map and 128 colours per world, the Light and the Dark World),
      drawn per scanline the way its HBlank handler 0x08068B7C sets the
      affine registers from the per-line zoom tables (the mode-7 tilt), the
      zoom in/out, the d-pad scroll limits and the Link-centred start
      (0x080B198C), window 0 lines 2-157. L opens it outside, B leaves,
      L/R/A switch the zoom. Shots looked at: `r8/shots/r8_owmap_in.png`,
      `r8_owmap_out.png`, `r8_owmap_dw.png` (SCENE=owmap).
      Ours: the Link marker is his head cell placed by inverting the line
      formula (the GBA's marker routine 0x080B23F8 is not ported); the fade
      in/out is not drawn.
- [ ] 8.2b The dungeon map screen (GBA submodule 3, 0x080B6409): NOT done.
- [x] 8.3 Text window and telepathy blends settled: the GBA's text routines
      (0x08127E00-0x08129FFF) write no blend/window register; the window's
      centre word 0x107F is the blank tile and the glyph tiles are cleared
      to colour 0 (0x08129BC4), so the inside is clear (our 50 % fill is
      gone). 0x081271C8 (BLDCNT 0x3048, alpha 15/15, BG1/BG2 off, BG3 on)
      belongs to the rescued-maiden sequence (dungeon submodule 0x19's step
      10, table 0x14CDB0); the opening telepathy now uses that setting (room
      layers off: backdrop, sprites and text) instead of our 80 % black
      overlay. Ours: the GBA routine that blanks the room for the opening
      telepathy itself is not located (the maiden's is used).

- [~] 8.4 The escape: the room model for the way down. Found: 0x60 and
      0x62 share one header and have no stair objects; the castle's way to
      the basement is teleport doors (door type 0x46, SNES WarpRoomDoor:
      leaving west -> header byte 12, east -> byte 13), 0x52 -> 0x01 and
      0x50 -> 0x01, then 0x01's spiral stairs down to 0x72. Ported in
      `Interior:cross`/`warpDoor` (tests: 0x52 west -> 0x01, 0x01 east ->
      0x52). The harness planner now reaches 0x01, 0x72 and 0x82 from the
      hall, but NOT 0x71/0x70/0x80: 0x72's top chamber shows side/bottom
      door pictures that are not in its door list (only 0x1C70). Route bot
      (`r8/harness`, SCENE=route6, log `r8/out/route_log.txt`): 14 PASS, 0
      snaps, then FAIL "through the castle to the cell block". The cell
      block, Zelda, the throne room and shelf, the sewers and the sanctuary
      are NOT reached by the bot this round.
- [ ] 8.5 NOT done this round: file select (three files, hearts, name),
      name entry, copy and erase; the title sprites (sword, PRESS START,
      copyright) and the GBA's own ALttP / Four Swords choice screen; the
      dungeon map screen; Link's sword sprite per pose; the uncle's sword
      and shield; shadows; the ball-and-chain; heart/rupee drops; opened
      chest and door pictures; the music table; Four Swords sprites; canopy
      priority.

Verified (round 8): logic 32/0, extract 246/0 (adds the menus stage, the
item menu's titles, equipment, grid, moves and names, the overworld map's
tables and centring, the castle's teleport doors), fs 18/0. Harness
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r8/harness/` (store in
`r8/out/store.bin`): SCENE=menu, menucmp (6/6 identical to the cartridge
routines), owmap, route6, reach8, stairscan. Scratch research tools (not in
the repo): `r8/py/thumb.py` (Thumb interpreter), `menu4.py`, `golden.py`,
`owmap.py`, `objs.py`, `poolref.py`.

## Bug round (user report) (2026-11-09)

Report: "cant open chests, pickup pots etc and crashes when i reach the
border of a town to another area when i walk through it and dont have the
sword animation or sprite". Reproduced through the REAL runtime path:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/bugs1/` -- `harness/` (MODE=
import through RomImporter into a scratch APPDATA/identity, MODE=play boots
ZeldaRuntime like main.lua's bootGame) and `realmain/` (the repo's own
main.lua, booted with POKEPORT_VERSION=alttp, scenes drive love.keypressed /
love.gamepadpressed). Scenes in `harness/scene_*.lua`, logs in `out/`,
shots in `shots/`, montages `out/m_*.png`.

- [x] Sword: Link's sword sprite and swing for every pose and the shield
      (cartridge tables + weapon strip, `Weapon.lua`; alttp.md "Bug
      round"). Was: a hit-box outline. Also the uncle's sword and shield.
      Found on the way: `linkGfxIndices` was read with 511 entries; the
      GBA's has 517 (poses 511-516 had no body -> a draw error for them).
      Checked: `out/m_sword.png` (all 4 directions, swing steps 0-8),
      `out/m_uncle.png`; gamepad B swings (`scene_pad`).
- [x] Chests: A (keyboard Z/Enter/Space, pad A) opened the chest logically
      but nothing showed. Now the chest shows the cartridge's open-chest
      words, the item rises out of it and the cartridge's receipt message
      opens ("You got the Lamp!"); remembered chests reload open.
      Checked: `scene_chest`, `out/m_chest.png`, `scene_pad`.
- [x] Pots / bushes / rocks: pots (object 0x2F) were not modelled at all
      indoors; outdoors A deleted the bush. Now lift (with the secrets
      table 0x2264C8), carry and throw, indoors and out, with the gloves
      rule for rocks (`Carry.lua`). Checked: `scene_pots`, `out/m_pots.png`.
- [~] Border crash: NOT reproduced. Through the real path: every Light
      World and Dark World area border pair with a clear path (195 LW + 281
      DW crossings, music on, keys held), all Kakariko edges at 8 px steps
      (213 crossings), walking out of Kakariko each way, all 118 overworld
      doors in and out, save -> continue -> walking, 2 x 20000 + 30000 frames
      of random input with random teleports: no Lua error, no crash. The
      runtime's error screen was checked in the real main.lua path (an
      injected error in update shows "... stopped (update)" with the
      traceback, the app keeps running: `shots/errscreen.png`). Fixed what
      could plausibly do it: the overworld view cache kept a stale entry
      for a screen redrawn after a bush was cut or a gate opened, which
      later evicted (released) the reloaded pictures of a screen still in
      use; it now evicts least recently used without stale entries; a
      carried bush's picture is its own copy; the 517-pose fix above.
- [x] Tests: `tests/zelda_alttp_extract_test.lua` 261/0 (adds weapon
      tables, swing poses, chest open + receipt message, pots lift / carry /
      throw / memory; the hole test waits for the 20-frame lift), logic
      32/0, fs 18/0. Import cacheVersion 10 (re-import needed).

Ours, still: the receipt sprite (menu icon instead), thrown-object
physics, no shatter pieces or damage from thrown objects, no item drops,
shadows.

## Round 9 (2026-11-09)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r9/` (`harness/`,
store `out/store.bin`, shots `shots/`, research `py/`) and the real-runtime
path `bugs1/realmain` with new scenes `scene_r9drops`, `scene_r9stairs`.

- [~] 9.1 The castle escape. FOUND: 0x72's "extra door pictures" are wall
      torches in the pre-rendered maps plus the mirror of its key door
      0x1C70 (doors on inner quadrant edges draw both sides); there are no
      missing doors. The real way is 0x72 (key door, in-room stairs) ->
      0x82 -> 0x81 -> up into 0x71 -> key door 0x1C60 -> spiral to 0x70 ->
      spiral to 0x80 (alttp.md "Castle stairs ... (round 9)"). FIXED in the
      engine: straight stairs 0x38/0x39 are an inter-room transition (Link
      came out at the TOP of the throne room; now past 0x51's own stairs at
      its bottom), spiral stairs land below the destination's spiral stair
      facing down (`Interior:spiralLanding` / `straightLanding`). Harness
      planner fixes (stepping onto in-room stairs always climbs, stair
      directions, room whitelist, state cap) make it find 0x61 -> 0x80
      (784 steps, `reach9`). Route bot (`SCENE=route6`, log
      `r9/out/route_log_r9.txt`): 16 PASS, 0 snaps, no teleports: new game
      -> ... -> hall -> throne room -> 0x50 -> teleport door -> 0x01 ->
      spiral -> 0x72, the guard's small key PASS; it then FAILS in 0x82:
      the bot keeps dying to the three blue guards there (game over ->
      continue in the hall; `r9/out/leg72_log.txt`). NOT reached by the bot
      this round: 0x71, 0x70, 0x80 (cell, Zelda), throne room shelf,
      sewers, sanctuary, priest. Real runtime: `scene_r9stairs` (hall stairs
      -> bottom of 0x51 by key presses) 2/0.
- [ ] 9.2 File select / name entry / copy / erase, title sprites, the
      ALttP / Four Swords choice screen: NOT done this round.
- [x] 9.3a (user request, top priority) Drops from cut / lifted grass,
      bushes, rocks and pots with ROM parity (`Drops.lua`, alttp.md "Drops
      (round 9)", cacheVersion 11). The GBA's own routines (RNG 0x080CEFE0,
      SubstituteAlternateSecret 0x080CA754, SpawnSecret 0x080C2534, the
      terrain tail 0x080C2A6A, the GBA-only bow rule 0x080C382C) were run
      in the scratch Thumb interpreter for 1000 random inputs
      (`r9/py/golden_drops.py`): `tests/zelda_alttp_drops_test.lua` replays
      them through Drops.terrain, 1000/1000 identical (1007 checks, 0
      failures). Story rule: no substitution before Zelda is rescued.
      Drops move, bounce, blink and go as the cartridge's absorbables and
      are picked up (rupees, hearts, bombs, arrows, magic, fairy, key).
      Real runtime: `scene_r9drops` 3/0 (cut bushes with the B key, a
      green rupee drops and is picked up; `bugs1/shots/r9_real_drop1.png`).
      OURS: VCOUNT model; hearts not drawn (their chars are in the DMA'd
      area); enemies held by a secret are not spawned; pickup boxes.
- [x] 9.3b Debris and damage: a cut bush and a broken thrown pot/bush
      scatter the cartridge's debris (Garnish16 tables 0x172BD0..,
      `r9/shots/r9_debris_bush_x3.png`); a thrown object hurts enemies
      (class 1 outdoor bush, else 3; a thrown pot kills a blue guard in the
      house test, harness `debris`). The sword now cuts only bushes / thick
      grass (0x36, 0x72A, 0x37E), as the SNES; rocks and signs are lifted.
- [x] 9.3c Shadows: Link (the GBA's kLinkShadows_Chardata 0x169774, offsets
      0x16AAF0/0x16AAFC), sprites with flags3 & 0x10 and drops (the big
      shadow 0xCC); `r9/shots/r9_shadow_z10_x4.png`. OURS: the small shadow
      (DMA'd chars) is not drawn; the shadow palette is row 4.
- [x] 9.3d The uncle's sword and shield on all four facings: checked
      against the cartridge's kUncleDraw table (`r9/shots/r9_uncle_dirs.png`):
      down, left and the lying pose draw sword and shield; facing up the
      table itself has no weapon entries (parity, not a gap).
- [ ] 9.3e NOT done: the chest's receipt sprite (still the menu icon), the
      dungeon map screen (0x080B6409), the music table, Four Swords sprites
      and canopy priority.

Verified (round 9): logic 32/0, fs 18/0, extract 268/0 (adds the hall
stairs, the spiral landing, pot drop, pickup, lifetime, the story rule),
drops 1007/0. Import cacheVersion 11 (re-import needed).

## Round 10 (2026-11-09)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r10/` (`harness/`,
`run.sh`, store `out/store.bin`, shots `shots/`, logs `out/`), the
real-runtime path `r10/real/` (`runreal.sh SCENE`, own scratch appdata,
`reimport.sh`), research `r10/py/`.

- [~] 10.1 The castle escape, route bot (`SCENE=route6`, log
      `r10/out/route6.log`): PAST the three blue guards in 0x82 (no damage
      there: the knockback port plus the new fighting). The best one-go run
      from a new game (this round, before the shelf rule was ported) passed
      29 steps: the lamp, ..., 0x72's key, 0x82 -> 0x81 -> 0x71 (quadrant
      kill tag, the boomerang room guard's key), spiral 0x70 -> 0x80, the
      ball-and-chain guard, the big key, the cell, "Zelda follows Link
      (message 33)", back up 0x80 -> 0x70 -> 0x71 -> ... -> 0x01 -> 0x52 ->
      0x51 with Zelda, the shelf found; it then failed to move the shelf
      (the A-button rule was ours). After porting Sprite_EE_MovableMantle
      the checkpoint leg `legsewer` (throne room, Zelda, lamp; iteration
      aid) pushes the shelf aside in 289 frames (34 px,
      `r10/shots/r10_30b_shelf.png`) and walks into the sewers 0x41
      (`r10_31_sewers.png`). NOT reached in one go: the sewers 0x42 ->
      0x32 -> 0x22 -> 0x21 -> 0x11 -> 0x02 (switch) -> 0x12, the priest and
      the save at the sanctuary (the save / continue step is written,
      `route6e.lua`, not reached). The last full runs lose time and hearts
      when the planner takes lower-layer edges outside 0x71 / 0x72's walls
      (see Open issues) and in 0x41 (lower-layer corridor, planner bounce).
      Engine fixes found on the way (alttp.md "Combat, doors and stairs
      (round 10)"): corner nudging (`Link:nudge`); the cartridge's sword
      knockback (0x50/0x40, sprite_F 15, masks `0x171DC0` read at import, a
      16-frame stun) and Link's (19 frames at 24); kill tags by quadrant
      (tags 1-9); trapdoors that are up when Link comes in through them and
      go down behind him (0x81 -> 0x71); lower-level door cells; the
      spiral landing's layer (0x72 -> 0x01 walled Link in on 0x01's lower
      layer); a crash drawing Zelda facing left/right; the shelf moves as
      Sprite_EE_MovableMantle (push right with Zelda and the lamp); A acts
      only on Link's level. Bot (scratch): fights by the sword's measured
      reach (`harness/reach.lua`), waits for a chasing guard to walk into
      the swing, backs off when too close, closes in on a stunned one; the
      lamp from the house chest; checkpoint legs `fight82`, `leg71`,
      `leg80`, `legshelf` for iteration only.
- [x] 10.1b 0x01's spiral stairs by key presses: not a stairs bug. The
      cartridge reads the cell at `link_x & 0x1F8`, so only x 248..263
      climb; at x 236..244 Link stopped at the wall row beside them because
      corner nudging was missing. With the nudge, x 244..260 climb (real
      runtime `scene_stairs01`, X0=244: 2/0; x 264 does not, as on the
      cartridge).
- [x] 10.2a Hearts: sprite sheet 0 is copied to OBJ rows 0-3 by
      `0x0812EED8`; GBA char 0x49 = sheet 0 tile 0x29. Hearts (and the
      small shadow 0x68 = tile 0x38) are drawn in cartridge art
      (`r10/shots/r10_drops_heart_x4.png`, real runtime
      `r10/real/shots/r10_real_heart_x3.png`).
- [x] 10.2b Enemies a secret holds spawn: soldiers 0x41/0x42, the bee
      0x79, the hoarder 0x3E, the cucco 0x0B, indoors into the room's
      actors, outdoors through `OwActors.lua` with the area's own sprite
      set and palettes (kOwSprPalInfo read at import). Real runtime
      `scene_r10secrets` 7/0: the castle area's bee bush (area 0x1B pos
      0x10B4, secret 3) lets out a bee that stings Link
      (`r10_real_bee_x3.png`); a soldier from a bush (secret 17 put there
      by the scene) is beaten with the sword (`r10_real_soldier_x3.png`); a
      heart (secret 6) is picked up. 0xD3/0xD4 still not spawned.
- [ ] 10.3 File select, name entry, copy/erase, title sprites, the
      ALttP / Four Swords choice screen: NOT done. Findings only (below).
- [x] 10.4b The lifted / thrown object is the cartridge's sprite 0xEC
      (kThrowableScenery_Char `0x1778B4`, Flags `0x1778C0`; big rocks keep
      the tile picture) (`r10/shots/r10_lift_bush_x4.png`).
- [ ] 10.4 NOT done: the chest receipt sprite, the dungeon map screen, the
      music table.

Findings for 10.3 (not ported): the GBA's main module table `0x14CA5C`
has modules 2 (copy) and 3 (erase) as stubs that only advance the module
(`0x0806BEB5`, `0x0806BEFD`); module 1 is `0x0806BEA5` (calls
`0x0806A1C4`, init, and `0x0806A318`), module 4 `0x0806A411`, module 5
`0x0806A475`; module 0 (`0x0812DA15`) runs the title through the state
table `0x22B0D4` (14 states: `0x0812D431`, `0x0812D4CD`, `0x08125EC1`,
`0x08126D5D`, ..., `0x0812E4C9`) indexed by RAM +0x9AD and draws the
blinking prompt from frame counter +0x9F6 & 0x30 (`0x0812DAE2`); module
0x1D (`0x0812E411`) calls `0x08126D5C`, `0x0812E0A0`, `0x081295CC`. The
GBA's front end (game choice, files) lives around `0x08125EC0-0x0812E4C9`
and is the next place to read.

Real-runtime scenes (r10/real, all through love.keypressed into the
repo's main.lua): `stairs01` 2/0, `r10secrets` 7/0, `r10castle` 5/0
(two of 0x82's guards beaten by key presses with knockback,
`r10_real_knockback_x3.png`; the 0x81 -> 0x71 trapdoor up on the way in and
down behind, `r10_real_71_trapdoor_up_x3.png`, `r10_real_71_inside_x3.png`),
the older `smoke`, `savecont` 1/0, `r9drops` 3/0.

Verified (round 10): logic 32/0, fs 18/0, drops 1007/0, extract 268/0,
and the new `tests/zelda_alttp_combat_test.lua` 28/0 (projection, nudge onto
0x01's stairs, guard knockback and stun, Link's knockback, the 0x81 -> 0x71
trapdoor and the quadrant tag, the spiral landing layer, the shelf with and
without the lamp, the four secret enemies, the heart / small shadow chars). Import cacheVersion 12
(re-import needed).

## Round 11 (2026-11-09)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r11/` (`harness/`,
`run.sh`, store `out/store.bin`, shots `shots/`, logs `out/`), the
real-app path `r11/real/` (`runreal.sh SCENE`, own scratch appdata,
`reimport.sh`), research `r11/py/` (`fsel.py`, `title.py`: the front end
in the Thumb interpreter).

- [x] 11.1 Layers and collision, the cartridge's way (alttp.md "Layers,
      doors and stairs (round 11)"): the two attribute tables are the GBA's
      `0x0808273C` (upper from the map at `0x02018000`, lower from
      `0x0201A000` = our bg3, slope flip bits); door attributes and slots
      are Dungeon_LoadSingleDoorAttribute's (kTileAttrsByDoor `0x16784C`,
      mirror slots, high-range doors on the lower table, 0xF0 + slot marks
      on locked doors) instead of our wall scan; layer-toggle doorways
      (0x16 -> 0x90-0x9F) swap the level at inter-room transitions; indoor
      ledges (0x28 / 0x2A / 0x2B, 20-frame timer) hop Link onto the lower
      level; the south straight stairs (number above the 0x39 row) take
      Link down; spiral stairs land on the header plane's level; a key
      door opened from the next room is open from this side
      (Dungeon_CheckAdjacentRoomsForOpenDoors); Link snaps against walls
      (HandlePushingBonkingSnaps). Knockback no longer carries Link across
      in-room stairs (ours). Result: no walking in the empty space outside
      room walls on the lower level; 0x41's corridor is walked on its upper
      level; the 0x71 stall is gone (the bot came there through the void
      beside 0x81 / 0x82; it now comes in through 0x71's south trapdoor).
      The harness's r10 0x71 <-> 0x72 planner guard is removed; the planner
      follows the engine's rules (stairs always taken, in-room stairs'
      level by rule, layer toggles on edges).
- [ ] 11.1b The escape in one run: see "Verified" below.
- [~] 11.2 Start-up screens: NOT ported. Findings (interpreter runs,
      `r11/py/title.py`): the title is module 0's state table `0x22B0D4`
      (states 1-2 load, 3-4 intro, 6-7 title, 12 after START); START then
      runs modules 1 (`0x0806BEA5`, the file's RAM from the save), 2 and 3
      (stubs), 4 (`0x0806A411`) one frame each and module 0x14
      (`0x080B7ACD`) starts the game: the GBA's ALttP has no SNES-style
      file select, copy or erase screen between its title and the game.
      Where the GBA picks the file and its name (its shared front end) is
      not located. The ALttP / Four Swords choice screen and the title
      sprites are not ported.
- [x] 11.3a Opened doors in cartridge art (no black rectangles): the
      opened type (kDoorTypeRemap `0x1677FC`) drawn with the GBA's door
      pictures (`0x16798C` / `0x167A5C` / `0x167B1C` / `0x167BDC`) on the
      room maps, high-range doors' inner part on the lower layer's map
      (`r11/shots/r11_door71key_x2.png`).
- [x] 11.3b The cucco's calm hops: the GBA's Cucco_Calm `0x080EA700`
      (velocity tables `0x177D54` / `0x177D64`, the cartridge RNG
      `0x080CEFE0`), Chicken_Hopping's timing.
- [ ] 11.3c NOT done: the chest receipt sprite (found: kReceiveItemGfx is
      at `0x16E23C`, used by `0x080AC..`-`0x080AE4..`; the GBA's
      DecodeAnimatedSpriteTile is not ported), secrets 0xD3 (Stal) / 0xD4
      (landmine).
- [ ] 11.4 NOT done: the dungeon map screen, the music table, Kakariko /
      Sahasrahla's hint path.

## Round 12 (2026-11-09)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r12/` (`harness/`,
`run.sh`, `lowprio.sh` (below-normal priority), store `out/store.bin`, shots
`shots/`, logs `out/`), the real-app path `r12/real/` (`runreal.sh SCENE`
moves the scratch save aside before each run; `realmain` sleeps 1 ms a
frame), research `r12/py/` (`boot.py`: the cartridge from AgbMain).

- [x] 12.1 The real-app failure at Zelda's cell: not an input bug.
      `src/core/Input` latches a press until the next fixed step, so a
      one-frame X tap reaches the sword even on a LOVE frame with no game
      tick. Real-app scene `scene_r12cell` (key events only): 8 swings from 9
      one-frame taps beat the ball-and-chain guard, the big key is taken, the
      cell opens and Zelda follows (4/0; `real/shots/r12_real_cell.png`,
      `r12_real_zelda_follows.png`). The round-11 run's 6006-frame fight
      (no damage either way) was not reproduced in three later real runs
      (the guard died in 222 / 567 / 590 frames).
- [x] 12.2 "Back up to 0x51 with Zelda": the bot died to 0x82's respawned
      blue guard on the way back and the engine continued at the hall's
      front door (entrance 4), whose next step out left the castle. ENGINE
      FIXES: the cartridge's starting points (`0x150D24`, Death_Func:
      with Zelda following Link continues in the prison 0x80) and its save /
      continue rule (`save().alttp.resume`: the starting point); the exit's
      fancy door (`kExitData_FancyDoor 0x1508DA`: the castle door opens and
      Link walks 36 + 3 px; before he was left 20 px inside the castle wall).
      The step now also checks Zelda's follower is with Link. Bot: fights a
      foe it gave up on once that foe hits Link; goRoom plans again after a
      failed leg. Step 8 (the hole bush): Link walks 1 or 2 px a frame, so
      the bot's exact-pixel settle could fail; within 2 px is now "there".
- [x] 12.3 (user report, top priority) Doors: `Doors.lua`, the cartridge's
      indoor walking, doorway slide, perpendicular door movement, corner
      nudge, diagonal limits, door transitions (+28 / -18 / +21 / -8, GBA
      `0x0809B0DC` read), open room edges, the landing (kStaircaseTab2), the
      exit by 0x8E. Overworld doors: the look-ahead cut from 48 px to the
      doorstep's one tile, no facing rule. `tests/zelda_alttp_doors_test.lua`
      21/0 (every 2 px across 5 doors: through inside the door, stopped
      outside, slide 1 px a frame, fired at the page test; the landing; the
      house from outside). Real app `scene_r12doors` 6/0 (off-centre down:
      slides 11 px and leaves at y 482 + 28; outside x 2232 does not enter,
      x 2244 enters as Link touches the door; diagonal; shots
      `r12_real_door_*.png`). alttp.md "Starting points, continues and exits
      (round 12)".
- [~] 12.3b The escape in one run. Before the door port: the harness ran
      it in ONE run from a new game, 43/43 PASS (title ... cell, Zelda, the
      shelf, the sewers, the priest, the save, the continue in the
      sanctuary; one death in the sewers continued at the throne room's
      starting point; that run's log was overwritten by later runs). Real app,
      checkpoint legs by key events: from the cell with Zelda to the priest,
      the save by the runtime's menu, a relaunch and START: 15/15
      (`scene_r12legz`); the cell itself 4/0 (`scene_r12cell`); save /
      continue in the sanctuary 4/0 (`scene_r12savecont`,
      `real/shots/r12_real_continue_sanct.png`). The real app's full run
      from a new game failed at the shelf (run 3, before the door port) and
      was not rerun after it. AFTER the door port the harness run reaches
      "Zelda follows Link" (26 PASS, `r12/shots/r12_215_cell_open.png`) and
      then loses Link in a loop at 0x71's in-room stairs: the lower level's
      guard stands on the stairs' foot where Link lands, knocks him back onto
      the stairs, the bot's swings do not hit, he dies and continues in the
      prison, and the loop repeats (bot weakness or an engine gap at the
      stairs' foot; not diagnosed). Bot changes for the new doors: no
      steering against the corner nudge, a new plan after a quadrant
      transition, axis-by-axis steps into one-column gaps, hearts after a
      fight, back behind the shelf after a death.
- [~] 12.4 Front end: findings only (alttp.md, the front end): AgbMain
      `0x0800B084`, the top-level task table `0x0842731C`, the SRAM mirror
      `0x02002000` (flag `0x02002434`), EEPROM routines `0x08135DC4` /
      `0x08135E74`, module 4's file branch. The boot runs in the scratch
      interpreter with EEPROM / VCOUNT HLE but reached no drawn frame. NOT
      ported: the game choice screen, title sprites, name entry; where the
      name and slot live in EEPROM.
- [ ] 12.5 NOT done: the chest receipt sprite, secrets 0xD3 / 0xD4, the music
      table, the dungeon map, Kakariko.

Import cacheVersion 14 (the exit door words and the starting points).

## Round 13 (2026-11-09)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r13/` (`harness/`,
`run.sh`, `lowprio.sh`, store `out/store.bin`, shots `shots/`, logs `out/`),
the real-app path `r13/real/` (`runreal.sh SCENE`), research `r13/py/`
(`boot.py` now runs the cartridge from AgbMain to its front end: VBlank
stood in for at the main loop's wait, `armhle.py` for the object loop's ARM
routines; `fe_an.py` / `fe_gen.py` match its VRAM and OAM to the ROM).

- [x] 13.1 The 0x71 loop, diagnosed (round-12 log `r12/out/route6.log`):
      ENGINE, three gaps, none of them the round-12 door port.
      (1) Our round-6 guard AI noticed Link on the other level: 0x71's
      lower-level guard 0x42 (spawn 96,384, 24 px from the stairs' foot)
      followed Link while he was on the upper level and waited at the foot
      of the in-room stairs (cells 15-16, rows 44-45). The cartridge's
      guards see Link only through their probes or by touching him, both
      on their own level (Probe, Sprite_CheckDamageToLink_same_layer).
      (2) Link's knockback (ours since round 11) refused any move that
      touched in-room stair cells, so Link, pushed onto the stairs' edge
      (120,354), could not be knocked back at all; the guard stood 1 px
      above him and hit him every 58 frames (the blink time).
      (3) In-room stairs are walls to sprites on the cartridge
      (kSprite_Func5_Tab3[0x1D-0x1F] = 1); our guards walked on them.
      The bot's swings "missed" because each swing knocked the guard back
      against the stairs and it walked straight back in.
      FIXES: `Guard.lua` (new) ports the guard routine for 0x41-0x43
      indoors (Guard_Main states 0-4, probes, Soldier_Func12,
      Guard_ApplySpeedInDirection, the wall-following subtypes 5-7, the
      sprite tile collision with the cartridge's probe points and table;
      tables read at import, RomMap.combat guard* / probe* / sprTile* /
      sprPoint* / sprSimple); the other soldiers' stand-in AI only notices
      Link on its own level; the sword hits only sprites on Link's level
      (Sprite_CheckDamageFromLink); knockback is refused only when it would
      newly enter stairs. Also ported: the kill memory of the last 4 rooms
      (Dungeon_ResetSprites, Sprite_ManuallySetDeathFlagUW; cleared on
      entering a palace or continuing) and enemy prize drops
      (Sprite_DoTheDeath / ForcePrizeDrop: flags5 prize pack, kPrizeMasks,
      the per-pack counter). A latent draw crash this exposed (a dropped
      rupee's shimmer reset hit a string key in the sprite cache, the
      runtime then stopped the game: the round-11 "6006-frame fight" in the
      real app was this kind of stop) is fixed in `Sprites.lua`.
      Stairs and landings are unchanged by the door port: `climb72` gives
      the r11 (pre-port) log byte for byte, the spiral landings in the
      route (0x72 at 248,74, 0x80 at 80,50) are the r11 ones.
      `tests/zelda_alttp_guard_test.lua` 21/0.
- [x] 13.2 The escape in ONE run, final code. Harness (`route6`, a new
      game through the front end, the uncle, the castle, the cell, Zelda,
      the shelf, the sewers, the priest, the save and the continue in the
      sanctuary): 50 PASS / 0 FAIL in one run, no death (`r13/out/
      route6_final.log`, shots `r13/shots/r13_*.png`). Real app, real key
      events (`real/harness/scene_r13escape.lua`: the same bot on key
      presses from a new game through the front end, the save by the
      runtime's menu, a relaunch, START, the saved file and the continue in
      the sanctuary): 49 PASS / 0 FAIL, 38107 frames, no runtime error
      (`real/out/real_r13escape.log`, shots `real/shots/r13_*.png`). An
      earlier real run stalled because a window focus change resets the
      runtime's held keys (Host:focus -> Input:reset) while the bot kept
      "holding" right; the real adapter now presses a held key again when
      the game no longer sees it (logged: 2 re-presses in the final run).
      Real scenes with the final code: `scene_r12doors` 6/0 (its new-game
      helper now goes through the front end), `scene_r12cell` 4/0. After
      the harness run only two lines changed (the file panel's hearts text
      moved 12 px right; the import progress weights).
- [x] 13.3 Front end. EEPROM layout found (RomMap.front comment; alttp.md
      "The front end (round 13)"): 3 ALttP files of 0x480 bytes (RAM
      0x02002000), 3 front-end file records of 0x40 bytes (RAM 0x0200B250,
      the player's name = 6 bytes at +8), settings, a signature, checksummed
      headers, a second copy at +0x1000. The boot now runs in the scratch
      interpreter to drawn frames: logos, the shared title, CHOOSE A FILE,
      ENTER A NAME, the save, CHOOSE A GAME (`r13/py/boot/b4_*.png`,
      `b6_*.png`). PORTED (`FrontExtract.lua`, `FrontEnd.lua`): START at the
      title -> CHOOSE A FILE -> (new file) ENTER A NAME -> CHOOSE A GAME ->
      A Link to the Past or Four Swords; every BG map, tile block, OBJ
      tile and palette is the cartridge's (checked equal to the VRAM the
      cartridge built), the OBJ layouts are the cartridge's OAM. The name
      is saved through ZeldaSaves (`save().name`, shown by the launcher) and
      used in messages. OURS: one file (the launcher slot), the letters
      (HUD menu letters: A-Z, 0-9, '-'), the file panel's text, alpha for
      the GBA blending, no "Now saving" box, no transitions.
      `tests/zelda_alttp_front_test.lua` 20/0.
- [ ] 13.4 NOT done: the after-escape "Link's house / sanctuary" continue
      choice (not looked for on the GBA), the chest receipt sprite, secrets
      0xD3 / 0xD4, the music table, the dungeon map, Kakariko.

Import cacheVersion 16 (15: the guard / prize tables; 16: the front end).

## Round 14 (2026-11-09)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r14/` (`harness/`,
`run.sh`, `lowprio.sh`, store `out/store.bin`, shots `shots/`, logs `out/`;
`prio.lua`, `lower.lua`, `zoom.lua`, `layershot.lua`, `t71.lua`, `route6`
with `CART=1` for the cartridge transitions), real app `r14/real/`
(`runreal.sh r14`, `runreal.sh r13escape`; `H.winshot` captures the whole
window for zoomed views), research `r14/py/` (`common.py`: literal-pool
xrefs and Thumb disassembly).

- [x] 14.1 (user bug) Link drew over door frames. The GBA's BG / OBJ
      priorities are ported (alttp.md "Layers and priority (round 14)"):
      room maps on GBA BG1-3 with the entrance's priorities and the
      per-room setup 0x0806D598 (property 3 / 4 / 2 / 7 cases), OBJ priority
      through the cartridge's SNES->GBA table (0x16B38E), Link's and the
      sprites' SNES priorities by level (0x16B326, 0x171DBC). New
      `Layers.lua` draws each priority's maps then its sprites; Link on the
      upper level passes under the high-priority map (door frames, wall
      tops), on the lower level under the upper map too; the room maps are
      transparent over a backdrop fill; dark rooms darken each BG layer.
      Opened doors also write their outer row / column to the high map
      (the GBA's door drawers). Outdoors: Link over the overlay during a
      ledge hop. Shots (new vs old, mid-doorway): `r14/out/cmp_n62.png`
      (north door 0x62), `cmp_w61.png` (west door), `cmp_s61.png` (the
      hall's front door), `cmp_s104.png` (the house's exit),
      `cmp_lower.png` (lower level, 0x80 "on top"); real app
      `real/shots/r14_real_house_exit_mid.png`.
- [x] 14.2 (user request) Zoom and the whole map (`Zoom.lua`): wheel, R3,
      L3, L3+R3 through the shared Input actions; integer steps 1 .. 2 S,
      saved (options.zelda.game.alttp.zoom); default = the cartridge's
      240 x 160 path; HUD at the normal scale. Overworld: every screen in
      view (`shots/r14_zoom_ow_m3.png`, real `real/shots/r14_real_zoom_out3.png`);
      indoors the connected rooms of the floor (`shots/r14_zoom_room61_m3.png`).
      ZeldaRuntime got small optional hooks (see Requests).
- [x] 14.3 (user request) Seamless transitions (`Seamless.lua`, default
      on; CARTRIDGE TRANSITIONS in the system menu restores round 13):
      overworld areas switch without stopping Link (camera glide); rooms
      keep the cartridge's walk-in and landing (same spot and level, test)
      with Link back sooner and the camera gliding; entrances, exits and
      stairs crossfade 12 frames (`real/shots/r14_real_enter_fade.png`).
      The full escape bot: harness 49 PASS / 0 FAIL in BOTH modes
      (`out/route6_seam.log`, `out/route6_cart.log`; the same steps as
      round 13's 50-line log minus nothing: one line is printed once
      fewer). Bot changes for seamless timing (harness only): plan again
      when the room changed under a settle / walk, fight guards that are
      "looking", strike the other side after a parry.
- [x] 14.4a Guard sword parry (`Guard.parry`, GBA 0x080C39C0; tables
      0x171E60 / 0x171E68). Not for 0x6A (its ball is not ported).
- [x] 14.4b The green knife guard 0x4B on the cartridge's routine
      (`Guard.updateRecruit`; tables 0x1773F4 / 0x1773FC / 0x178400).
- [ ] 14.4c NOT done: the ball-and-chain guard 0x6A's AI and ball
      (ChainBallTrooper_Draw), the front-end font / files 2 and 3 / copy /
      erase, the chest receipt sprite (kReceiveItemGfx needs the GBA's
      DecodeAnimatedSpriteTile and sheets 0x5A-0x5D; found, not ported),
      Kakariko and Sahasrahla's path.

Tests: `tests/zelda_alttp_view_test.lua` (new, 52 checks). Import
cacheVersion 17 (the priority tables, parry and knife guard tables).

## Round 15 (2026-11-09)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r15/` (`harness/`
incl. the new `audit.lua`, `run.sh`, `lowprio.sh`, `out/`, `shots/`), the
cartridge side `r15/py/cart.py` (the GBA's own tileset / animated-tile /
room / palette / overworld loaders in the Thumb interpreter),
`dump_ow.py` / `dump_rooms.py` (dumps to `r15/out/cart/`), real app
`r15/real/` (`runreal.sh r15`, `runreal.sh r13escape`).

- [x] 15.1 (user report) "Some maps are still showing scrambled tiles and
      art". Audit tool (`AUDIT=mains|ow|rooms sh run.sh audit`, `BEFORE=1`
      reproduces the round-14 pictures): every overworld area (80, Light
      and Dark World) and every room reachable from an entrance or starting
      point (279 of 304; room -> main tileset by a breadth-first walk over
      door pairs and header stair targets) is decoded by the port and by
      the cartridge's own loaders, and compared pixel by pixel (colour
      through each side's palette), with map-word and tile/palette
      classification. Causes and fixes (alttp.md "Map graphics audit
      (round 15)"): (1) the overworld BG palette set was read from the
      per-phase SPRITE table (77 / 80 areas wrong, the Dark World worst);
      now `0x14C8E8` (Palette.lua; OwActors uses the per-phase table for
      the sprites); (2) the animated tiles (water, lava, torches...) were
      never loaded (151 rooms, most areas showed the static sheet under
      them): new `AnimTiles.lua` (cartridge sheets, frames and 9-frame
      clock, cells repainted in place; overworld, rooms, zoomed-out
      neighbours); (3) indoor BG palettes 0-1 = the HUD's; (4) a closed key
      door draws its own words (room 0x11 showed an open doorway).
      RESULT: overworld 80 / 80 pixel-equal, rooms 279 / 279 with no
      graphics difference (`r15/out/audit/ow_after.txt`,
      `rooms_after.txt`; before: `ow_before.txt` 77 differ,
      `rooms_before.txt` 151 graphics-differ). Contact sheets:
      `r15/out/audit/ow_sheet_cart.png` vs `ow_sheet_port_before.png` /
      `ow_sheet_port_after.png`; `rooms_sheet_cart.png` vs
      `rooms_sheet_port_before.png` / `rooms_sheet_port_after.png`;
      per map `ow_before_XX.png` / `room_before_XXX.png` (cartridge left,
      port right) and `cmp_room006_cart_before_after.png`. Real app
      (`real/shots/r15_real_*.png`, `scene_r15` 7/0): the house area in
      the rain, Lake Hylia's water animating (two shots 9 frames apart
      differ only in the water), Skull Woods, the pyramid, the Village of
      Outcasts, zoomed out in both worlds, a Swamp Palace room.
      The special rooms 0x0D / 0x90 / 0xA4 / 0xAC have no graphics
      difference either (their layer cases stay open). Left: map words the
      GBA room loader draws that the port does not (door states, pushable
      blocks, floor rupees; 83 rooms) -- objects, not graphics.
      `tests/zelda_alttp_gfx_test.lua` (new, 14 checks);
      `zelda_alttp_layers_test` updated (a closed key door now has its
      closed words).
- [x] 15.2 Regression: all `zelda_alttp_*` tests pass (logic 32, extract
      274, layers 24, combat 28, doors 21, drops 1007, guard 21, front 20,
      fs 18, view 52, gfx 14; 0 failures). The full escape: harness
      `route6` ROUTE PASS (49 PASS, 0 FAIL, `r15/out/route6.log`); real
      app `runreal.sh r13escape` (real keys, new game through the front
      end to the save / relaunch / continue in the sanctuary) ROUTE PASS,
      49 PASS / 0 FAIL, 45403 frames, no runtime error
      (`r15/real/out/real_r13escape.log`).
- [ ] 15.3 NOT done this round: the ball-and-chain guard 0x6A, the
      front-end font / files 2-3 / copy / erase, the chest receipt sprite,
      Kakariko and Sahasrahla's path (all still as after round 14).

Import cacheVersion 18 (the animated tile sheet per main tileset,
`RomMap.dungAnimTiles` 0x14CE1C).

## Round 16 (2026-11-09)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r16/` (`harness/`
incl. `audit.lua`, `route6` + `route16k` (KAK=1 chains the Kakariko leg
after the escape's continue), `bncfight`, `kak`, `push6b`, `rup`,
`owreach`; `run.sh`, `runtests.sh` (every `zelda_alttp_*` test at
below-normal priority), `lowprio.sh`, `out/`, `shots/`), the cartridge side
`r16/py/` (`cart.py` now with the new-game push-block / torch tables in
RAM, `dump_rooms.py`, `objtrace.py` / `srctrace.py` / `doorsurvey.py` /
`doorwr.py`: what the room loader draws over its pre-rendered maps and from
which ROM words, `findowspr.py`, `dmdsearch.py`, `tabsearch.py`: the people's
and the flail guard's tables), real app `r16/real/` (`runreal.sh r16`,
`KAK=1 runreal.sh r13escape`).

- [x] 16.1 Room objects in the 83 rooms the round-15 audit flagged
      (alttp.md "Room objects over the pre-rendered maps"). The GBA room
      loader draws, over its three pre-rendered maps: every door by its
      final type (0x36 / 0x38 / 0x48 / 0x4A remapped per drawer; the
      high-range north / west / east doors draw nothing, a south one writes
      its rows to the lower map only, stair-mask doors 0x24 / 0x26 two rows
      on the lower map), the new-game push blocks (ROM 0x163430, 104 of
      them), rupee floors, large pick-up blocks, bomb floors, Blind's floor
      light. Ported (`RoomObjects.lua` new; `Interior.lua` predrawDoors /
      finalType / drawDoor load rules; the attribute tables now read the
      drawn words). Behaviour: two-way shutters 0x18 and trap shutters are
      closed at load (round-6 OURS "kept open" gone), up for the entry and
      down behind Link; blocks are pushed (21 frames into one, 16 px at
      12/16 px a frame, fixed afterwards, pits take them), room tags 0x0A
      and 0x0B-0x13 (push-block doors) open the shutters; floor rupees give
      5 each and the room remembers. Audit: **304 / 304 rooms with 0
      map-word and 0 graphics differences** (`r16/out/audit/
      rooms_after.txt`; the 25 rooms no entrance reaches included, loaded
      with a neighbour's main tileset); overworld still 80 / 80
      (`ow_after.txt`). The escape's sewer room 0x11 has a push block in
      the way on the cartridge: the route bot pushes it (`B.pushFor`).
      Tests: `tests/zelda_alttp_roomobj_test.lua` (new, 36 checks). Real
      app (`real/shots/r16_real_block_before/after.png`,
      `r16_real_rupees_before/after.png` (0 -> 15 rupees walking with the
      right key), `r16_real_shutter06.png`).
- [x] 16.2 Kakariko and Sahasrahla's path (alttp.md "People: Kakariko and
      Sahasrahla"). New `Npc.lua`: the overworld sprite lists by story
      phase (0x080CB140, tables 0x227D70 / 0x227E70 / 0x2280B0), the
      townsfolk's draw tables (GBA copies of the SNES DrawMultipleData,
      found by `dmdsearch.py`), the elder's wife (0x78: 0x2B, 0x2C, 0x2D),
      Sahasrahla (0x16: 0x32, 0x33 marks the map), the sweeping lady (0xA5),
      the trough boy (0x147 / 0x148), the snitch ladies (indoors 0xAD); they
      block Link and talk with A. Houses are the existing interiors
      (entrance 0x0E -> room 0xF3, 0x45 -> 0x105). Route bot (`route16k`):
      from the sanctuary continue out of the sanctuary, across to Kakariko,
      into the elder's house, the wife's hint, the sweeping lady and the
      trough boy, east into Sahasrahla's hideout, his message and map mark,
      and on to the Eastern Palace's door (Link at the top of its stairs,
      3920,1576; the palace's door does not take him in from there -- see
      open issues). Harness: the escape + Kakariko in one run **ROUTE PASS,
      60 PASS / 0 FAIL** (`r16/out/route6_kak_final.log`, shots
      `r16/shots/r16_k*.png`). Real app scene `r16` 16 / 0
      (`real/out/real_r16.log`: the elder's house, the wife, Kakariko's 4
      people, the sweeping lady, the trough boy, the hideout, Sahasrahla,
      talking with the real A key; shots `real/shots/r16_real_*.png`).
      Real app, real keys, the whole escape and this leg in one run
      (`KAK=1 runreal.sh r13escape`: a new game through the front end, the
      escape, the save, a relaunch, the continue, Kakariko, Sahasrahla, the
      palace's door): **ROUTE PASS, 59 PASS / 0 FAIL, 58940 frames, no
      runtime error** (`real/out/real_r13escape_kak_final.log`, shots
      `real/shots/r16_k*.png`, `r16_real_route_sheet.png`).
      Tests: `tests/zelda_alttp_people_test.lua` (new, 21 checks).
- [x] 16.3 The ball-and-chain guard 0x6A (alttp.md "The ball-and-chain
      guard"): new `BallChain.lua`, the GBA's routine 0x080E2D4C (states
      0-3, the angle step quirk of the GBA, the throw), its drawing (head,
      body, chain links, ball from the GBA's tables and OAM literals), the
      ball's 16 x 16 hit box (hurts Link, parries the sword). The route bot
      beats it by striking while it walks / stands and keeping away while
      the ball is out (`B.fightFlail`). Real app: `r16_real_flail_state0-3`.
      `zelda_alttp_extract_test`: the big key it drops may be picked up in
      the same loop now (the guard stands its ground).
- [x] 16.5 Regression: every `zelda_alttp_*` test passes (logic 32,
      extract 274, layers 24, combat 28, doors 21, drops 1007, guard 21,
      front 20, fs 18, view 52, gfx 14, roomobj 36, people 21; 0
      failures); the round-15 audit: overworld 80 / 80, rooms 304 / 304.
- [ ] 16.4 NOT done: the front-end font / files 2-3 / copy / erase, the
      chest receipt sprite, the 0x17-frame overlay step, the "keep" palette
      rows (all as after round 15).

Import cacheVersion 19 (room objects, people, the flail guard's tables).

## Round 17 (2026-11-10)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r17/`:

- `harness/`:
  - `route6` + `route16k`: KAK=1 adds the Kakariko leg; EP=1 adds the
    palace leg, `epleg.lua`. route16k writes the checkpoint
    `out/ep_save.txt` inside the palace.
  - `ep17`: the palace leg from that checkpoint.
  - `doorwalk`: walks into every overworld door from the passage under it.
  - `zoo` / `zoo2`: the palace sprites in their rooms.
  - `audit.lua`: reads the cartridge dumps from `r16/out/cart`.
- `run.sh`, `runtests.sh`, `lowprio.sh`, `out/`, `shots/`.
- `r17/py/`:
  - `tabfind.py`: finds the GBA copies of SNES constant tables by value.
  - `findb10.py`: finds the GBA's writes to the trapdoor flag.
  - `rep.py`: anchored edits that keep CRLF.
- Real app: `r17/real/`.

- [x] 17.1 The Eastern Palace's door. Traced the GBA's entrance check
      (0x0808BEE0 -> 0x0808C044 / 0x0808BB88). After its big-door tests it
      recomputes the position with `x - (base - 0x10)`. The entrance tile is
      therefore the 16 x 16 tile under (link_x + 16, link_y + 7): the tile
      right of Link's own column.
      - One exception keeps Link's own column: area 0x18 with
        link_x == 0x288 and link_y <= 0x917 (Kakariko's entrance 0x43).
      - The door tables agree. Their positions sit 8-16 px right of the
        walkable passage under each door, and the palace's stairs end one
        tile left of its door tile (3936, 1568).
      - Ported in `Interior.owEntranceAt` (in the engine, not the bot).
      - `doorwalk` result: 56 of 59 doors enter from their passage. Before,
        0 did; the old rule only worked because the bot stood on the
        door's column. The 3 left need bombs or an opened cave (entrances
        0x25, 0x4E, 0x5B).
      - The castle's opened big door now redraws. Map16 0xDBA-0xDBD were
        missing from the cache, so the gate never drew open.
      - Shots: `r17/shots/r17_ep_inside_-16.png`, `r17_k09_eastern_in.png`.
      - The test still runs only while Link walks up, and the doorstep
        allowance stays. Both are ours; see the open issues.
- [~] 17.2 The Eastern Palace. New `Palace.lua` ports the cartridge's
      routines (zelda3 names). Every table is read from the GBA ROM at
      import; the offsets are in the module. Sprites:
      - Popo 0x4E / 0x4F.
      - The anti-fairy 0x15.
      - The cannonball 0x50, with the cannon overlords 0x02 / 0x03.
      - The Stalfos 0xA7: it jumps away when Link faces it, walks in steps,
        and some throw bones. The GBA's kStalfos_Delay is {10, 20, 40, 20}
        where the SNES has {16, 32, 64, 32}.
      - The Eyegores 0x83 / 0x84: asleep, then the eye opens, then they
        chase. The sword hurts the green one only while its eye is open;
        the red one only takes arrows.
      - The Armos Knights 0x53 and their coordinator overlord. They wake
        after 255 frames and form a ring of six (kSinusLookupTable, radius
        64 <-> 32), march to the back wall and cascade forward. The last
        knight turns red with 48 health and crushes.
      - The heart container 0xEA: one more heart, and the boss is beaten.
      Room tags:
      - 0x25 drops the pendant. Picking it up gives the pendant of Courage
        (bit 4, the menu's pendant byte) and takes Link out of the palace.
      - 0x15 opens the boss shutter once Link has the pendant.
      - 0x16 / 0x17 are the switch tags. The GBA's switch test (0x080798DC)
        looks for a pair of switch attributes with the same pair below.
      - 0x27: a switch reveals the chests.
      Room data:
      - Overlords are now in the cache (`idx.overlords`).
      - The entrance room's corridor pot hides a floor switch (secret
        0x88). The GBA's words are 0x310B / 0x311B / 0x350B / 0x351B
        (0x080929E8). As Dungeon_Store2x2 does, all four cells take the LR
        word's attribute, 0x23.
      - Floor switches 0x23 / 0x24 are walkable.
      The way north from the entrance: lift that pot, step on the switch
      (both two-way shutters open), then cross the bridge around its own
      toggle switch.
      Route: the escape, Kakariko, Sahasrahla, up the palace's stairs, the
      pot, the switch, the bridge, then the cannonball room 0xB9 (see
      17.5).
      NOT done:
      - The bot does not climb 0xB9's cannonball track. It must hide in
        the track's alcoves, and `climbTrack` in ep17.lua does not time the
        gaps yet. So the rest of the palace is not walked through: the map,
        the compass, the big key, the Bow's big chest, the dark rooms, the
        red Eyegores and the boss.
      - The Armos fight, the heart container and the pendant are tested in
        place (`zelda_alttp_palace_test`); the route does not reach them.
      - No arrows or item use (the red Eyegores need the Bow). The lamp
        does not light torches.
      - The falling-Stalfos overlord 0x05 and the anti-fairy circle are not
        spawned.
      - Sahasrahla's next hint is not wired.
      Shots:
      - `r17_show_C8.png`: the Armos Knights on their ring.
      - `r17_show_99.png`: Eyegores awake, Popos, a dark room.
      - `r17_show_A8.png`: Stalfos.
      - `r17_show_D8.png`: red Eyegores.
      - `r17_ep01_pot_switch.png`, `r17_ep02_shutter_open.png`,
        `r17_ep03_B9.png`.
- [ ] 17.3 World interactions: not done. That covers large blocks, bomb
      floors, outdoor enemies and vendors from the sprite lists, shops, the
      legend's yes/no cursor, the snitch ladies and people activating by
      the camera.
- [ ] 17.4 Not done: the front-end font and files 2-3, the chest receipt
      sprite, the 0x17-frame overlay step and the "keep" palette rows.
- [x] 17.5 Regression:
      - Every `zelda_alttp_*` test passes, 0 failures: logic 32, extract
        275, layers 24, combat 28, doors 22, drops 1007, guard 21, front 20,
        fs 18, view 52, gfx 14, roomobj 36, people 21, palace 30 (new).
      - The audit: rooms 304 / 304 (0 map-word and 0 graphics differences),
        overworld 80 / 80 (`r17/out/audit_rooms_r17.log`,
        `audit_ow_r17.log`).
      - The whole route in the harness (`KAK=1 EP=1 sh run.sh route6`):
        new game, the escape, the save / continue, Kakariko, Sahasrahla,
        up the palace's stairs, the pot switch, the bridge, room 0xB9.
        ROUTE PASS, 63 PASS / 0 FAIL (`r17/out/route6_r17_full.log`; shots
        `r17/shots/route_r17_*.png`). The run without the palace leg also
        passed with the door change alone: 60 / 0
        (`out/route6_kak_door_pass.log`).
      - The same route in the real app with real keys
        (`KAK=1 EP=1 runreal.sh r13escape`): new game through the front
        end, the save, a relaunch, the continue, Kakariko, the palace and
        room 0xB9. ROUTE PASS, 63 PASS / 0 FAIL, 81078 frames, no runtime
        error (`r17/real/out/real_r17_escape_kak_ep_final.log`; shots
        `r17/real/shots/real_r17_*.png`).

Import cacheVersion 20: the opened big door's map16, the overlords and the
palace sprite tables.

## Round 18 (2026-11-10)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r18/`:

- `harness/`: `items.lua` (bow, bombs on the bomb caves, lamp and torches,
  keys, big chest; `ITEM=bow|bombs|lamp|keys`), `epfx.lua` (the anti-fairy
  circle, the falling Stalfos), `b9climb.lua` + `b9test.lua` (the
  cannonball track), `epleg18.lua` (the palace leg after `epleg.lua`,
  chained by `route16k` with `EP=1`), `ep18.lua` (from the checkpoint),
  `bombprobe*.lua`, `b9probe.lua`, `b8plan.lua`, `glyph.lua`, `btn.lua`.
- `py/`: `ybtn.py` / `ybtn2.py` (the GBA's button bytes), `maptab.py`
  (char / int16 table search), `rep18.py` (anchored edits keeping line
  endings).
- Real app: `real/harness/scene_r18items.lua`; `real/out`, `real/shots`.

- [x] 18.1 Items (alttp.md "Items (round 18)"). New `Items.lua`:
  - The GBA's buttons: A is the item, R the action (lift, talk, open,
    read). Proved by 0x0806995C and by the messages' button glyphs; the
    glyph table in `Text.lua` was off by one (the sword showed "L").
    `Game.lua` reads the action from R now. **Controls change.**
  - Bow and arrows (LinkItem_Bow, AncillaAdd_Arrow, Ancilla09/0A, Arrow_
    Draw, all GBA tables); arrow count; red Eyegores take arrows only
    (enemy_damage_data located at 0x17D924; arrows and bombs use it).
  - Bombs (LinkItem_Bombs, Ancilla07_Bomb, Bomb_Draw, explosion tables):
    damage to sprites and Link, door types 0x28 / 0x2A / 0x2E, bushes and
    the overworld bomb caves (secret 0x86 -> map16 0xDB4 / 0xDB5; kept in
    the save). The three light-world bomb caves 0x4A (Kakariko's bomb hut),
    0x6C and 0x84 open and are entered; the round-17 list (0x25, 0x4E,
    0x5B) was wrong. The doorstep allowance no longer reaches over an
    unbombed wall (`Interior.owBombWall`).
  - Lamp: magic cost, message 123, the flame, torches (room list ROM
    0x1635D2, words 0xEC2 / 0xECA), the burn timer, tags 0x33 / 0x3E, dark
    rooms lit by torches.
  - Keys per palace, big key per palace, the big-key door 0x1E (was a
    small-key door), the big chest wants the big key.
  - Tests: `tests/zelda_alttp_items_test.lua` (new, 38 checks). Harness
    `items.lua` 38 / 0 (`r18/out/items.log`; shots `r18/shots/i_r18_*`).
    Real app scene `r18items` 16 / 0 with real keys (`r18/real/out/
    real_r18items.log`; shots `r18/real/shots/r18real_*`, sheet
    `r18real_sheet.png`).
- [~] 18.2 The Eastern Palace.
  - B9's cannonball track: the bot climbs it from the balls' own timing
    (`b9climb.lua`). In the whole route the climb takes about 200 frames
    and 0-1 hits.
  - New in Palace.lua: the anti-fairy circle 0x82, the falling Stalfos
    (overlord 0x05 -> 0x85 after the big chest; their pictures and thrown
    head are ours / not ported), Sahasrahla's boots (0x38, the Pegasus
    Boots, 0x37). Tag 0x14 is not in this palace.
  - The route: new game -> escape -> Kakariko -> the palace -> C9's pot
    switch -> B9's track -> A9 (the big chest room). Harness `KAK=1 EP=1
    route6`: **ROUTE PASS, 66 PASS / 0 FAIL** (`r18/out/
    route6_r18_full.log`; shots `r18/shots/ep18_ep10_b9_top.png`,
    `ep18_ep14_a9.png`).
  - The same route in the real app with real keys (`KAK=1 EP=1
    runreal.sh r13escape`, R pressed as the "e" key): **ROUTE PASS, 66
    PASS / 0 FAIL, 61074 frames, no runtime error** (`r18/real/out/
    real_r13escape_r18.log`; shots `r18/real/shots/
    r18real_route_b9_a9.png`). Earlier attempts failed on bot flakes, not
    the engine: the ball-and-chain guard fight timed out (`_try1`), Link was
    knocked onto C9's bridge toggle switch (`_try2`; `epleg.lua` now steps
    on a switch again when the shutters went back down), the window lost
    focus at boot (`_try3_focus`).
  - NOT done: the bot finds no way from B9 to B8 (the big key), so the
    walk stops in A9. The big key -> big chest -> Bow, the falling Stalfos,
    the dark rooms with the lamp, the anti-fairy circle and the red Eyegores
    with arrows are proved in place (tests, `items.lua`, `epfx.lua`, the
    real-app scene); the basement, the Armos Knights in the route, the
    heart container and the pendant only by `zelda_alttp_palace_test`.
- [ ] 18.3 World interactions: only the bomb caves and the bomb wall
  doorstep (above). Not done: large blocks indoors (glove rule), outdoor
  enemies from the sprite lists, shops, the yes/no cursor, the snitch
  ladies, camera activation, the every-frame door test.
- [ ] 18.4 Not done: the front-end font, files 2-3, copy / erase, the
  chest receipt sprite, the HUD item box icon.
- [x] 18.5 Regression: every `zelda_alttp_*` test passes (combat 28, doors
  22, drops 1007, extract 275, front 20, fs 18, gfx 14, guard 21, items 38,
  layers 24, logic 32, palace 30, people 21, roomobj 36, view 52; extract
  and people now press R for actions). The audit: rooms 304 / 304 (0
  map-word and 0 graphics differences), overworld 80 / 80
  (`r18/out/audit_rooms_r18.log`, `audit_ow_r18.log`).

Import cacheVersion 21: the item tables (`idx.items`) and the palace's
anti-fairy circle / falling Stalfos tables.

## Round 19 (2026-11-10)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r19/` (copied from
r18; LÖVE runs at below-normal priority, one at a time):

- `harness/epleg19.lua`: A9 to the Bow, chained by `EPLEG18B`.
- `harness/epleg19b.lua`: after the Bow, chained by `EPLEG19B`. Its starts
  are selected with `START19`: `bigkey`, `a9`, `99`, `da`, `d8`, `c8`.
- `harness/ep19ck.lua`: runs a leg from a mid-palace checkpoint
  (`out/ck_<CK>.txt`).
- `harness/epplace19.lua`: the palace's end in place.
- `harness/sasha19.lua`: Sahasrahla's boots and a dash.
- Probes: `epconn.lua`, `epitems.lua`, `b8plan.lua` (the planner across the
  palace; `OPEN=1 POTS=… ALLOWALL=1 GRID=…`), `mask99.lua`, `dbgchest.lua`,
  `pokes.lua`, `r80.lua`.
- Planner (`plan.lua`) additions:
  - Indoor ledge hops (`B.ledges`, opt-in).
  - `B.liftPots`.
  - `B.avoidFoes`.
  - Stepping out of a spot the 16 px body does not fit.
  - Big chests are opened from their third row.

- [~] 19.1 The Eastern Palace (alttp.md "The Eastern Palace in one run").
  - **Why the walk stopped (round 18):** B9's west door is on an
    upper-level ring that only B9's west door and BA's key door reach. The
    cartridge's way to B8 is A9's switch, A8's south-west trigger from its
    west doorway, the lower level through A8, A9 and AA, BA's switch and
    key pot, BA's key door, the ring, then B8.
  - **Engine gaps fixed (cartridge rules):**
    - Stair masks 0x20-0x26 are small-key locks, and opening one restores
      the spiral stairs' floor (99 -> DA was impossible).
    - A pot's small key crashed the actor update (BA).
    - Chests on the lower layer and the big chest's three rows (A9's big
      chest could not be opened).
    - The held sword: Stalfos stay put, and it pokes.
    - A room's placed prizes (0xD8-0xE3).
  - **The route** (see 19.5):
    - In one harness run: the escape, Kakariko, the palace, B9's track,
      A9's switch, A8, the lower level, BA's key, the ring, B8's big key,
      back to A9, the Bow, the falling Stalfos, A9's arrows, then into 99.
    - From the 99 checkpoint: 99 (the green Eyegore's key, by arrows), the
      stair mask, DA's pot switch, D9.
    - In the real app: up to B8's entry.
  - **NOT done in one run:** D9's column of three green Eyegores. The bot
    kills one or two with arrows, then dies; the run stops at D9 (`D9FIGHT=1`
    runs the attempt). D8's red Eyegores, C8's Armos Knights, the heart
    container and the pendant are only proved by `zelda_alttp_palace_test`
    (the engine). The bot's Armos fight from `epplace19.lua` loses: 5 arrow
    hits, no knight down, Link dies in about 1300 frames.
- [~] 19.2 HUD and poses (alttp.md "The HUD item box and Link's poses").
  - Done:
    - The item box shows the chosen item (`Hud.itemIcon`, the GBA's box
      word 60).
    - The held sword (pose row 2 / 3; the poke; Stalfos stay put).
    - The bow pose row 7 (Link's body).
    - The Pegasus Boots dash (`Dash.lua`): the charge, the run, the run's
      hit box, the rebound, breakable walls 0x28.
  - Shots:
    - `r19/shots/r19_pose_held_sword.png` and `r19_pose_held_walk.png`:
      the sword held out, walking.
    - `r19_pose_bow.png`: the bow pose, body only, with the bow in the HUD
      box.
    - `r19s_ep42_dash.png`: the dash.
    - `r19f_ep28_da.png`: the bow in the item box.
  - NOT done:
    - The bow's own picture (link_dma_var5 item graphics).
    - Lifting and throwing bombs.
    - The falling Stalfos' own pictures and their thrown head.
    - The spin attack.
- [ ] 19.3 World interactions: not done (large blocks indoors with the glove
  rule, outdoor enemies from the sprite lists, shops, the yes/no cursor, the
  snitch ladies, camera activation, the every-frame door test).
- [ ] 19.4 Not done: the Desert Palace path, the front-end font, files 2-3,
  copy / erase, the chest receipt sprite.
- [x] 19.6 The boots' inventory byte. Round 18 set GBA byte 0x35, which is
  item slot 22 (the magic cape): the menu and the new item box would show a
  cape. The boots are 0x39: SNES link_item_boots 0x55 - 0x1C, like the
  gloves 0x38 and the sword 0x3D, and the menu's ability box lists 0x39,
  0x38, 0x3A, 0x3B. `Npc.lua` gives 0x39 and moves an old 0x35.
  `Dash.hasBoots` reads 0x39.
- [~] 19.5 Regression:
  - **Tests:** every `zelda_alttp_*` test passes, 0 failures: combat 28,
    doors 22, drops 1007, extract 275, front 20, fs 18, gfx 14, guard 21,
    items 38, layers 24, logic 32, palace 30, people 21, roomobj 36, view 52,
    and the new `zelda_alttp_r19_test` with 30 checks
    (`r19/out/alltests_final.txt`).
  - **Audit:** rooms 304 / 304 (0 map-word and 0 graphics differences),
    overworld 80 / 80 (`r19/out/audit_rooms_r19.log`, `audit_ow_r19.log`).
  - **Harness route** (`KAK=1 EP=1 EPLEG18B=…/epleg19.lua
    EPLEG19B=…/epleg19b.lua sh run.sh route6`):
    - It runs from a new game through the escape, Kakariko, the palace,
      B9, A8, BA, B8 (big key), A9 (the Bow) and into 99. The best run had
      81 PASS and then died to 99's Eyegore. The last run had 78 PASS: one
      B8 sprite was left (the big key still came), and Link died to A9's
      falling Stalfos after the Bow (`r19/out/route6_r19_final.log`). The
      bot's fights are what vary from run to run.
    - From the checkpoint in 99 (`CK=r99 START19=99 ep19ck`), 99 -> DA -> D9
      passes (`r19/out/ep19ck.log`; shots `r19/shots/r19f_ep27_99_key.png`,
      `r19f_ep28_da_switch.png`, `r19f_ep29_d9.png`).
    - Shots of the walk: `r19/shots/r19route_ep19_a9_switch.png`,
      `ep20_a8_shutters`, `ep20_ba`, `ep21_ba_switch`, `ep21_ba_key`,
      `ep22_b8`, `ep23_b8_chest`, `ep24_b8_bigkey`, `ep25_a9_after`,
      `ep26_99`.
    - Two bot changes keep the escape's own route: ledge hops are opt-in
      (they had moved the walk through 0x72 and lost the guard fight), and a
      lost ball-and-chain fight is fought again after the continue
      (`route6d.lua`).
  - **In place:**
    - `sashaplace`: SASHA PASS. Outside the palace with the pendant, to the
      hideout, the boots (message 0x38), and a dash of 40 px in 6 frames
      after the charge (`r19/shots/r19s_ep40_sasha_text.png`,
      `r19s_ep42_dash.png`).
  - **Real app** (`KAK=1 EP=1 EPLEG18B=… EPLEG19B=… real/runreal.sh
    r13escape`, real keys, R pressed as "e"):
    - The furthest run (try 6, `r19/real/out/real_r13escape_r19_try6.log`,
      93027 frames, no runtime error) went from a new game through the front
      end and the escape. It lost the ball-and-chain fight once and won the
      retry. Then the save and continue, Kakariko, Sahasrahla, the palace,
      C9, B9's track, A9's switch, A8's doorway trigger, the lower level, BA
      (switch, key pot), BA's key door, B9's upper ring and into B8: 74
      steps up to the B8 entry.
    - It stopped in B8: the drop collector walked back into BA (its goal
      had no room test; fixed in `epleg19.lua`). Try 7 died to B8's sprites.
    - Real shots: `r19/real/shots/r19real_ep19_a9_switch.png`,
      `ep20_a8_shutters`, `ep20_ba`, `ep21_ba_switch`, `ep21_ba_key`,
      `ep22_b8`.
    - NOT reached in the real app: the big key, the Bow, 99 and the rest.
    - The earlier tries are kept as `_try1` to `_try7`. Tries 1-2 lost the
      ball-and-chain fight with no retry. Tries 3-5 stopped at A9's switch;
      the bot now presses the nearer of its two switches.

## Round 20 (2026-11-10)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r20/` (copied from
r19; L�VE at below-normal priority, one at a time):

- `harness/fight20.lua`: the general fight helper (alttp.md "The route
  bot's fight helper"). `bot.lua` loads it; the ball-and-chain fight uses it.
- `harness/fight20s.lua` + `fightall.sh`: win rates in place,
  `FIGHT=bnc|b8|a9|99|d9|d8|c8 SEEDS=n HP= ARROWS= NOBOW=1`.
- `harness/epleg20.lua` / `epleg20b.lua`: the palace legs with the helper
  (D9's floor switch, D8's order, the 99 key count); `ep20ck.lua` runs a leg
  from `out/ck_<CK>.txt`; `sasha19.lua` steps off the palace doorstep first.
- Scenes: `dash20.lua` (outdoor dash), `stalfos20.lua` (falling Stalfos),
  `bomb20.lua` (bomb lift / throw, spin pose), `d9door.lua` (probe).
- `real/imp` copied back (the real app's re-import).

- [x] 20.1 The fights, engine side (alttp.md "Fights, the cartridge's way").
  Fixed to the cartridge: Link's body box (x + 4, y + 8, 8 x 8) and the
  touching-boxes rule; touch damage every 4th frame by slot, not during the
  sprite's hit timer, the box lifted by the sprite's height; the sword's
  damage class (kSprite_Func14_Damage + enemy_damage_data: an Armos Knight
  takes 4 a swing, not 2); the hit timer (0x9D: one sword hit per 29
  frames, the damage taken at 24); the tink's push-back; the held sword's
  speed 12 and its put-away after a poke; **the spin attack** (charge 48,
  12 steps, the 44 x 45 box, LinkOam row 0x0F); a hit resets the sword and
  hops Link (z speed 12); **the palace sprites' recoil** (the shared recoil
  step ran instead of their routines: a stunned Armos Knight hung in the
  air and snapped back to its ring); **the falling Stalfos** (the fighter
  sword neutralises it for 255 frames, then it rises; its own pictures;
  the head it throws, sprite 0x02). Compared and matching: the Eyegores'
  timing, the Armos rules, arrow damage, the ball-and-chain guard.
  - Tests: `tests/zelda_alttp_r20_test.lua` (new, 40 checks); four older
    checks updated to the hit timer / speed 12 (guard, items, view, r19).
- [x] 20.2 The fight helper and win rates (in place, 5 seeded tries each,
  Link at 16 hp, 10 arrows; `r20/out/fightall_final.txt`, the final code):
  ball-and-chain guard 3 / 5, B8 3 / 5 (2 timeouts, no damage), A9's
  falling Stalfos 5 / 5, 99 4 / 5, D9's three Eyegores 5 / 5, D8 3 / 5 (2
  timeouts), C8's Armos Knights 4 / 5. Earlier runs of the same scenarios
  at 24 hp / 12 arrows were 35 / 35 (`fightall_b.txt`) and the guard alone
  8 / 8 at 16 hp before the last D8 changes; the D8 changes (Eyegore
  danger weight, charge cut-off, planner step check) cost the guard and B8
  some wins and were not tuned back.
- [~] 20.3 The Eastern Palace in one run.
  - **Harness, from a new game** (`route6_r20_final.log`, 88 PASS): the
    escape (the ball-and-chain guard by the helper), Kakariko, the palace,
    B9, A8, BA, B8 (the helper clears it, the big key), A9 (the Bow, the
    falling Stalfos), 99 (the key), DA, D9 (three green Eyegores, then the
    floor switch they stood on: the way west), then **died in D8** (the red
    Eyegores).
  - **Harness, from the DA checkpoint** (`ep20ck_da_try3.log`, CK PASS, an
    earlier D8 order): DA, D9, D8 (3 of 3 red Eyegores), C8 (the Armos
    Knights by the helper), the heart container (24 -> 32), the pendant, out
    of the palace, Sahasrahla's boots and a dash. Shots
    `r20/shots/r20ck_ep29_d9_switch.png`, `ep30_d8_reds`, `ep33_c8_after`,
    `ep34_c8_heart`, `ep35_pendant`, `ep41_boots`, `ep42_dash`.
  - **Real app, real keys, from a new game** (`real/out/
    real_r13escape_r20_try1.log`, 131245 frames, no runtime error): the
    escape (the guard fight lost once, won on the retry), Kakariko, the
    palace, B8's big key, the Bow, 99's key, DA, D9's Eyegores and switch,
    into D8; it stopped in D8 (the helper stalled with the red Eyegores
    asleep, then died fetching pots). Shots `r20/real/shots/
    r20real_ep22_b8.png`, `ep24_b8_bigkey`, `ep25_a9_after`, `ep27_99_key`,
    `ep28_da_switch`, `ep29_d9_switch`, `ep29_d8`.
  - D8 is the weak fight: the red Eyegores take arrows only (two each) and
    the arrows run short; the last D8 changes (no charging near an awake
    Eyegore, two arrows before waking a red, a danger check on the
    planner's steps) were not re-run through the whole route.
- [~] 20.4 Poses and the outdoor dash.
  - Done: the spin pose; the held-sword walk at speed 12; the dash
    outdoors (Link_BonkAndSmash on bushes, the hop, the shake timer;
    `r20/shots/dash20_02_run.png`, `dash20_03_hop.png`, `dash20_04_after.png`:
    the castle bush smashed into its hole); bombs lifted and thrown
    (`bomb20_01_lifted.png`, `bomb20_02_thrown.png`, `bomb20_03_boom.png`;
    spin `bomb20_spin_8.png`, `_16`); the falling Stalfos' own pictures and
    thrown head (`st20_01_landed.png`, `st20_02_head.png`, `st20_03_heap.png`).
  - NOT done: the bow's own picture (link_dma_var5 item strip; the item
    tiles are sheet 0 tiles 8-10 in LoadItemGFXIntoWRAM4BPPBuffer, the DMA
    table kLinkDmaSources6 not located on the GBA), the dash dust and
    sound, the rock piles 0x226-0x229, the spin attack outdoors.
- [ ] 20.5 World interactions, the Book of Mudora: not done
  (Sprite_DashItem 0x3B wants the dash's tremor, which is now kept in
  `game.tremor`).
- [x] 20.6 Regression: every `zelda_alttp_*` test passes (r20 40, the rest
  as round 19); the audit: rooms 304 / 304 (0 map-word, 0 graphics
  differences), overworld 80 / 80 (`r20/out/audit_rooms_r20.log`,
  `audit_ow_r20.log`).

Import cacheVersion 22: the sword's damage classes, the spin tables, the
action-tile offsets, the falling Stalfos' draw tables.

## Round 21 (2026-11-10)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r21/`. Copied from
r20. Every harness frame now sleeps 1 ms. LOVE runs at below-normal
priority, one process at a time.

- `harness/fight21.lua`: the fight helper. It is r20's helper plus these
  changes:
  - It does not walk out of a room's outer doors.
  - It can wake a sleeping sprite from inside an alcove.
  - `maxY` keeps a fight to one half of a room.
  - It ignores sprites outside the room.
  - It waits for the death puffs to end before it returns.
- `harness/d8_21.lua`: D8 in phases.
- Scenes:
  - `fx21.lua`: the bow, the death puff, the dust, the shake.
  - `spin21.lua`, `stalfos21.lua`, `rock21.lua`, `book21.lua`.
  - `d8info.lua`: a dump of the rooms' sprites, prize packs, pots and
    secrets.
- `fight20s.lua` / `fightall.sh`: these now use `FH=fight21` by default.

- [x] 21.1 Where D8's arrows come from, read from the cartridge (alttp.md
  "Round 21"):
  - Five pots hold five arrows each (secret 9 -> sprite 0xE1).
  - The Eyegores' prize pack 5 is mostly arrows.
  - On the cartridge, a pot's item comes back after Link leaves the palace
    (pots_revealed_in_room is cleared only by Dungeon_LoadEntrance).

  The supply was never short. The bot ran short because it fought
  everything at once. `d8_21.lua` now clears the room in phases: the south
  half, its arrow pot, the north half's Popos, then the reds with arrows,
  then the remaining pots.
- [x] 21.2 Win rates, in place. All tries use 8 seeds, Link at 16 hp with
  10 arrows unless noted. Log: `r21/out/fightall_r21a.txt`.

  | Fight | Win rate |
  |---|---|
  | Ball-and-chain guard | 6 / 8 |
  | Ball-and-chain guard at 24 hp | 7 / 8 |
  | B8 | 5 / 8, then fixed (see below) |
  | A9 | 8 / 8 |
  | 99 | 8 / 8 |
  | D9 | 7 / 8 |
  | D8 | 7 / 8 |
  | C8 | 5 / 8 |

  - D8's 7 / 8 comes from `r21/out/d8_r21_e.log`, with the final D8 code.
    It was 2 / 8 at the start of the round.
  - The B8 fix came after `fightall_r21a.txt` was run, so it is not in that
    table. B8's losses were stalls and a walk out of its east door. The door
    rule fixed seed 5 (`fight20s` seed 5 WIN); seeds 4 and 7 won in single
    runs.
  - The ball-and-chain guard was not brought back to 8 / 8. Every change
    tried made it worse and was reverted (the r20 settings stay in place):
    - a longer lead before the throw (F21THROW): 1 / 8 and 3 / 8;
    - a throw box aimed the way the guard faces: timeouts;
    - "flee the furthest when every move is dangerous": 1 / 8 and 2 / 8;
    - a 136 px sweep box: 0 / 8.

    The 35 / 35 at 24 hp from r20 was not reproduced.
- [x] 21.3 **The route from a new game, in the harness** (route6 with
  KAK=1 EP=1, the epleg20 / epleg20b / sasha19 legs;
  `r21/out/route6_r21_try3.log`): **ROUTE PASS, 98 PASS lines**. It covers:
  - the escape (the guard lost once and won on the retry);
  - Kakariko and the palace;
  - B8's big key and the Bow;
  - 99's key;
  - D9;
  - D8 (all three reds);
  - C8, the Armos Knights;
  - the heart container (24 -> 32) and the pendant;
  - Sahasrahla's boots and a dash.

  Shots: `r21/shots/route_try3/r21route3_ep30_d8_reds.png`, `ep33_c8_after`,
  `ep34_c8_heart`, `ep35_pendant`, `ep41_boots`, `ep42_dash`.
  - Two route fixes were needed: the retry now waits for the game over's
    continue, and the key pick-up waits for the death puff.
- [~] 21.3b **The route in the real app, with real keys** (seven tries,
  logs `r21/real/out/real_r13escape_r21_try1..7.log`). The best is try 7
  (89 PASS lines, no runtime error):
  - the escape (the guard won on its 5th try);
  - the palace, B8's big key, the Bow, 99, DA, D9;
  - **D8: all three red Eyegores fall to arrows**, with 24 arrows kept;
  - then into C8, where Link **died to the Armos Knights**.

  Shots: `r21/real/shots/try7/real7_montage.png`, `r21real7_ep30_d8_reds.png`,
  `ep32_c8_armos`.
  - Issues the tries found, all fixed:
    - B8's last sprite stuck between the anti-fairy circle and a pot
      (`epleg20.clearRoom` now lifts the two side pots and runs a second
      pass);
    - the big chest's open was interrupted (it is retried);
    - in A9, a fight walked out after a sprite outside the room.
  - Not yet understood: in C8, the real app's helper "shot" 132 times
    without an arrow leaving.
  - The pendant, the boots and the dash were not reached in the real app
    this round.
- [x] 21.4 Visuals, ported from the ROM (Effects.lua, OwSword.lua,
  Weapon.lua; alttp.md "Round 21"):
  - the death puff (kPerishOverlay, 31 / 15 frames at 3 / 4 speed; the
    prize, key and kill memory at its end; the kill tags wait for it);
  - the dash dust (charging and running) and the drawn screen shake;
  - the spin attack outdoors (TileDetect_MainHandler(8) cuts round Link),
    plus the held sword outdoors;
  - the swing's cut point from the cartridge's table (it was ours);
  - the falling Stalfos' head now takes the sword (255 health: it recoils);
  - the Bow's own picture (item strip, kLinkDmaSources6 at 0x22A9F2).

  Shots: `r21/shots/fx21_montage_bow.png` and `fx21_bow_zoom.png` (4
  facings), `fx21_montage_puff.png`, `fx21_dust_zoom.png` (charge dust, run
  dust, two shake frames), `spin21_montage.png` (the bush to Link's left cut
  by the spin), `st21_04_head_hit.png`.
  - Not done: the sounds (there is no SFX player; the dash's sfx is SNES
    sfx2 #35).
- [~] 21.5 Milestone 4 (towards the Desert Palace):
  - Done:
    - the big rock piles smashed by a dash (Dash.rockPile; 8 piles in the
      Light World; `r21/shots/rock21_p7_pair.png`);
    - the dash item 0x3B: the library's Book of Mudora falls when Link
      bonks the bookcase and is taken; bonk keys
      (`r21/shots/book21_trio.png`).
  - Not done: the Power Glove and heavy rocks, outdoor enemies, shops, the
    yes / no cursor, and the path to the Desert Palace.
  - The yes / no cursor is researched but not ported. On the cartridge the
    cursor is a second message drawn over the first (message t + 1 or
    t + 9), chosen with up / down (RenderText_Draw_Choose*).
- [x] 21.6 Regression:
  - every `zelda_alttp_*` test passes, including the new
    `tests/zelda_alttp_r21_test.lua` (50 checks);
  - the extract, guard and r20 tests were updated for the death puff and
    the cache version;
  - audit: rooms 304 / 304 (0 / 0) and the overworld 80 / 80
    (`r21/out/audit_rooms_r21.log`, `audit_ow_r21.log`).

Import cacheVersion 23: the death puff, dash dust, item strip DMA and
sword-tile tables (combat.fx), plus map16 0x226-0x229, 0xDCD-0xDD0 and
0x918-0x91B.

## Round 22 (2026-11-11)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r22/` (copied from
r21; one LOVE process at a time, below-normal priority, 1 ms a frame).
Real-app legs need `EPLEG18B=harness/epleg20.lua EPLEG19B=harness/epleg20b.lua
EPLEG19C=harness/sasha19.lua` (with `KAK=1 EP=1`), or the route stops in A9.

- [x] 22.1 **The real-app bow bug: root cause found and fixed (engine).**
  Link carried D8's last pot into C8. While carrying, the item button does
  nothing (as on the cartridge), but our port let only R throw, so B (sword)
  and A (bow) were both swallowed: "swings 127, shots 132", no arrow. Shot
  `r22/shots/r22_try7_c8_carry_zoom.png` (from r21 try 7: Link's arms up,
  the pot over his head). Cartridge rules now ported (Carry.lua, alttp.md
  "Round 22"): B or R throws (CarriedSprite_CheckForThrow, GBA 0x080C3280,
  the GBA joypad builder 0x08069AA8); a hit throws it at once; a room
  change ends the carry (Dungeon_ResetSprites). Why only the real app: the
  bot's second R came one frame inside the 20-frame lift, which drops the
  press; the bots now wait out the lift (`R22_LIFT_THROW`, bot.lua) and the
  fight helper empties Link's hands first. Test: `tests/zelda_alttp_r22_test.lua`
  sections 1-3.
- [~] 22.1b The real app from a new game (logs
  `r22/real/out/real_r13escape_r22_try1..5.log`): **not through the palace this round.** Five tries, none reached C8:
  - try 1 stopped in C9: the planner reloaded C9 for planning, the pot
    came back over the switch in its copy ("no plan") -- fixed (plan.lua);
  - tries 2 and 3 died on B9's cannonball track (the climb is risky at
    low health; the same climb wins 3 / 3 in a real-app scene,
    `real/out/real_r22b9_b9a.log`) -- the leg now retries after a game over;
  - tries 4 and 5 (70 PASS lines each, past B9, A9's switch and A8's
    shutters) died in A8 to its four Stalfos while the bot walks the
    doorway with fighting off (trace `real_r13escape_r22_try5.log`, TRACE=A8);
    not fixed. The harness route (`r22/out/route6_r22_try2.log`) showed a
    bot bug at A9 (Link not healed stays in the south doorway, the switch
    walk-off took him into B9): fixed (epleg19.lua), not re-run.
  The C8 Armos fight itself is 8 / 8 at the route's state, and the carry
  fix removes the round-21 failure; the pendant / boots / dash in the real
  app were not reached.
- [x] 22.2 Win rates (8 seeds; `r22/out/fightall_r22a.txt`, 16 hp / 10
  arrows as in round 21): ball-and-chain guard 6 / 8, B8 6 / 8 (both losses
  are 8000-frame stalls: a Stalfos in the pot corner, a green Eyegore with
  its eye shut; the route's B8 leg lifts the side pots first), C8 5 / 8.
  C8 at the route's own state (24 hp, 24 arrows; `fightall_r22c8route.txt`):
  **8 / 8**.
- [x] 22.2b **Pots come back** when the room reloads (Interior.lua): drawn
  again on every load; what they hid comes out once per palace visit
  (pots_revealed_in_room, cleared by a new entrance); the pot key keeps its
  room flag (mem.potKey); a pot switch shows again. The route planner keeps
  the live room's lifted pots (plan.lua; a load cleared them and C9's
  switch looked covered: real try 1 stopped there).
- [~] 22.3 Milestone 4:
  - **The yes / no cursor: done** (Text.lua): the choice commands 0x68 /
    0x6F / 0x71 / 0x72, cursor messages 1-2 / 11-12 / 6-8 / 9-10 drawn over
    the text, up / down, the 28-frame wait, `game.lastChoice`; the cursor is
    font tile 0x00. Mrs Sahasrahla repeats the legend on "Not at all".
    Shots `r22/shots/choice22_pair.png` (`choice22_01_yes.png`,
    `choice22_02_no.png`). The bots' text drivers confirm a ready choice.
  - **Shops: done for the clerk and his wares** (Shop.lua): Kakariko
    (0x11F) potion 150 / heart 10 / bombs 50, the 0x10F / 0x110 wares,
    prices, the cartridge's checks and messages, the cartridge's art (the
    GBA's kShopkeeper_Dmd 0x17D2C4 and kShopKeeper_ItemWithPrice_Dmd
    0x17D0E4). Scene `harness/shop22.lua` (SHOP PASS); shots
    `shop22_02_wares.png`, `shop22_02_zoom.png`, `shop22_03_heart_bought.png`.
  - Not done: the Power Glove (it is the Desert Palace's big chest, so it
    comes after the palace), heavy rocks (the outdoor rule for 0x52 / 0x53
    with the glove level is already in Carry.lua), outdoor enemies, the
    walk to the Desert and the Book's opening (Link_PerformDesertPrayer:
    the Book used while byte_7E02ED is set by a trigger tile, then module
    14 / 5 and the entrance animation), the Desert Palace.
- [ ] 22.4 Sound effects: not built. What is needed: (1) the ALttP code that
  turns `sound_effect_1` / `sound_effect_2` / ambient into song numbers --
  the GBA's sound command dispatcher is at 0x0800D2A0 (commands 0x8004xxxx
  .. 0x800Dxxxx, the song id at 0x0201EDA8 + 2; 0x800B starts a song through
  m4aSongNumStart 0x08134708); the per-effect song table is not located;
  (2) `ChipAudio.newM4AEffect` already renders an M4A song once as a static
  Source, so the player itself is small; (3) the call sites (dash 35 on
  sfx2, the sword swing, hits, the text's 36 / 32 / 43).
- [x] 22.5 Regression: every `zelda_alttp_*` test passes (people test's text
  driver now confirms the legend's choice; new `zelda_alttp_r22_test.lua`,
  47 checks); audits rooms 304 / 304 and overworld 80 / 80
  (`r22/out/audit_rooms_r22.log`, `audit_ow_r22.log`).

Import cacheVersion 24 (the two shop draw tables).

## Round 23 (2026-11-11)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r23/` (copied from
r22; one LOVE process at a time, below-normal priority, 1 ms a frame).
New rule this round: **no runs from a new game**. Every run starts from a
checkpoint (`r23/out/ck_<name>.txt`); `harness/ckrun23.lua` loads one in
the harness (`runck.sh`) and `real/harness/scene_r23ck.lua` in the real app
(it swaps the host's game for one made from the checkpoint's save with the
host's own options and drives it on real key events). `FULL=1` runs a leg's
main body, otherwise `SEG=<leg>`; `CKTAG` suffixes the checkpoints a run writes.

Checkpoint chain (newest last): `ep_save` (EP entrance, r17) -> `a9start`
(made once this round from ep_save: A9 on arrival from B9's track) ->
`bow` / `a9arrows` / `r99` / `da` / `d8` (real app) / `c8` -> `boots_real`
(real app, in Sahasrahla's hideout with the boots) -> `book_h` (library,
Book taken) -> `dp_h` / `dp_real` (Desert Palace hall 0x84).

- [x] 23.1 **A8's four Stalfos (real-app tries 4-5 of round 22).** The bot
  walked into A8's west doorway with fighting off while the four Stalfos
  chased it. Fix (epleg20.lua): wait out the room scroll, beat the Stalfos
  with the fight helper (`clearRoom`), then walk into the doorway. A second
  bot fault showed next: A9's lower level (green Eyegore + Stalfos by the
  way east) killed Link on the planner's own fight -- the leg now reaches
  the lower level first and clears it with the fight helper. Round 22's A9
  south-doorway switch fix (epleg19.lua) was not in epleg20.lua (the leg the
  route actually runs); ported. D9's switch step accepts shutters already
  opened by the fight (3 / 3). D8: after the phases the bot fights again
  while reds live and arrows remain (the real app ended its phases with a
  red left and 16 arrows).
  - Harness from `a9start`: `r23/out/ck_a9start_h4.log` -- A9 -> A8 (4 -> 0
    Stalfos) -> BA -> B8 -> Bow -> 99 -> DA -> D9 -> D8 -> C8 -> heart ->
    pendant -> boots -> dash, all PASS except D9's switch wording (fixed).
  - **Real app**, from `a9start`: `r23/real/out/real_r23ck_a9start_try1.log`
    (A9 heal 4 -> 20, A9 switch, A8 Stalfos 4 -> 0, ... through D9 into
    D8; failed only D8's last red: fixed), then from the real run's own
    `d8` checkpoint: `real_r23ck_d8_try2.log` -- **D8 reds 3 / 3, C8 Armos
    Knights, heart container 24 -> 32, the pendant, Sahasrahla's boots, the
    dash: CK PASS**. Shots `r23/real/shots/r23real2_ep35_pendant.png`,
    `r23real2_ep41_boots.png`. (The A9 heal / switch fix ran in the same
    real-app leg: "A9: the hearts under the pots (hp 20 / 24)", the switch
    pressed once.)
- [x] 23.2 **The library and the Book (route).** `harness/desert23.lua`
  from `boots_real`: out of the hideout, across the map to entrance 0x49,
  the dash into the bookcase drops the Book (DashItem.lua), Link takes item
  0x1D (`r23/out/desert_h1.log`, shots `r23/shots/r23d1_d01..d03`).
  Checkpoint `ck_book_h`.
- [x] 23.3 **The Desert of Mystery's door (Desert.lua, new).** Area 0x30's
  sprite list holds three desert statues 0x57 and the plaque 0xB3. The
  plaque (Sprite_B3_PedestalPlaque, area 48): R alone -> message 0xBC (the
  Hylian you can't read); A with the Book chosen while facing up touching
  it -> 0xBD ("To open the way forward... make your wish here"), then the
  prayer (Module0E_05_DesertPrayer: darken, the iris of radius 0x26 on Link,
  wait for a button, open 8 a frame to 0xC0, byte_7E02F0 = 1); the statues
  (Sprite_57_DesertStatue) shake 128 frames, then slide 1 px a frame
  turning at walls (kDesertBarrier_NextD) for 130 counts while Link is
  held; the area reloading stands them again (Sprite_ResetAll). Statue art
  = kDesertBarrier_Dmd (GBA 0x178A20) with sp0l outdoors (Sprites.lua: the
  overworld sprite palette row 0 was left black). Scene
  `harness/desert23s.lua` (13 PASS; shots `desert23s_01_statues.png`,
  `_05_iris.png`, `_07_moved.png`, `_08_inside.png`); route from `book_h`:
  harness `r23/out/desert_h2.log`, **real app
  `r23/real/out/real_r23ck_desert_try1.log` (CK PASS: plaque, prayer,
  statues, in through entrance 9 to room 0x84)**, shots
  `r23/real/shots/r23real3_d05_prayer.png`, `_d07_statues_moved.png`,
  `_d08_desert_palace.png`.
- [~] 23.4 **The Desert Palace (in place, `harness/dp23.lua`, DP23 PASS).**
  Its rooms load from entrance 9 with their cartridge sprite lists (0x84:
  six Leevers + a Beamos; 0x73: the big chest, Beamos, Leevers, a
  Debirando, the bonk key). New sprites (Desert.lua, run through
  Palace.lua): **Leever 0x71** (under the sand / surface 127 / attack
  160-223 / sink 127, hurts and is hurt only above the sand) and **Beamos
  0x61** (64-direction probes, 16 flashing frames, the laser: 4 moves a
  frame at 0x20, damage class 4, at most 4 live), drawn from the GBA's own
  tables. The big chest (0x73, with the palace's big key) gives the
  **Power Glove** (item 0x1B, glove level 1), and a gray rock (attr 0x52)
  outdoors is then lifted (Carry.lua's existing kGetBestActionToPerformOnTile
  rule). Shots `dp23_02_leevers.png`, `dp23_04_glove.png`,
  `dp23_05_rock_lift.png`. **Not done:** walking the palace (keys, the big
  key room 0x75, the torches / bonk key in 0x73), Debirando 0x63 / 0x64,
  the wall cannons 0x66 / 0x67, Popos there are ported, Lanmolas, the back
  half (0x63 / 0x53 / 0x43 / 0x33), the big boulders' strain-lift (attr
  0x5A-0x5D, player_handler_timer 1); dark rocks need the Titan's Mitt
  (level 2) as on the cartridge.
- [ ] 23.5 Outdoor enemies on the route: **not ported** (no overworld
  enemy spawns from the area lists yet; the route meets none). The lists
  were read (r23/py/owspr.py): the desert has Geldman 0x4C, Vulture 0x01,
  ground bombs 0xD4; the way from the hideout passes soldier / archer areas.
- [ ] 23.6 Sound effects: not started.
- [x] 23.7 Regression: see "Tests and audits" below.

Import cacheVersion 25 (Desert.extract: the statue / prayer / Leever /
Beamos tables; the statue draw table in Npc's dmd list).

Tests and audits: every `zelda_alttp_*` test passes (new
`tests/zelda_alttp_r23_test.lua`, 38 checks: the desert tables, the
statues' spawn / direction / barrier, the plaque without and with the Book,
the prayer's stages, the statues' shake / slide / hold / stop / respawn,
0x84's sprites, the Leever's states and hit rule, the Beamos' probe /
flash / laser, the glove rule); audits rooms 304 / 304 and overworld 80 / 80
(`r23/out/audit_rooms_r23.log`, `audit_ow_r23.log`).

## Round 24 (2026-11-11)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r24/` (copied from
r23 with the paths moved; one LOVE process at a time, below-normal
priority, 1 ms a frame). No run from a new game: every run starts from a
checkpoint (`r24/out/ck_<name>.txt`) through `harness/ckrun23.lua`
(`runck.sh`) or the real app's `real/harness/scene_r23ck.lua`
(`real/runreal.sh r23ck`). The palace walk is `harness/dp24.lua`
(`SEG=.../dp24.lua STAGE=A..F`); each stage writes its checkpoint.

Checkpoint chain (newest last): `dp_h` (r23, hall 0x84) -> `dp_key`
(0x73, the torch key) -> `dp_bigkey` (0x75, big key) -> `dp_glove`
(0x73, Power Glove) -> `dp_back` (0x63, in through the back door) ->
`dp_63key` (0x63, its pot key) -> `dp_boss` (0x33, past the big key
door) -> **`dp_done` (outside the palace, Pendant of Power taken, 5
hearts)**. Real-app copies end in `_real`.

- [x] 24.1 **New module `DesertPalace.lua`** (run by Palace.lua through
  small hooks; tables read from the GBA at import, `data.t.dpal`):
  - Debirando pit 0x63 and Debirando 0x64 (a 0x64 in the room list is the
    fire kind: SpritePrep_FireDebirando, G 0, oam flags 6, fireballs
    0x55 every 32 frames while up). The open pit holds Link
    (link_prevent_from_moving unless GBA R is newly pressed; the GBA input
    builder 0x08069AA8 puts R in SNES filtered_joypad_L 0x10) and drags
    him 1 px per 256 of its speed (drag_player_x / y). The pit dies with
    its Debirando.
  - Wall cannons 0x66-0x69 (slide 128 frames each way, fire 0x6B every
    32 frames) and their cannonballs.
  - Lanmolas 0x54 (three, kLanmola_InitDelay, mound, shrapnel 0xC2, the
    wavy flight, the dive, the 64-spot body, the sword's throw-back,
    state 5, the heart container from the last one).
  - The moving wall (tags 0x1C-0x1F; GBA 0x0807AF80, kMovingWall_Tab0 at
    0x167924 holds 0x41.. and is compared >=, so 0x49 px), collision
    mode 2 (Link meets BG1 at x + offset), the wall stays moved
    (room state bit), Link held while it moves.
  - The palace's own pendant: kDungeonCrystalPendantBit (0x14CADC) and
    kBossFinishedFallingItem (0x152AAC) -> kFallingItem_Type (0x16E5D4):
    the Desert Palace gives bit 2, item 0x39 ("You won the Pendant of
    Power!"); the Eastern Palace stays bit 4 / 0x37 (Palace.takePrize).
- [x] 24.2 **The Desert Palace walked** (harness, `r24/out/dpA10.log`,
  `dpB1`, `dpC2`, `dpD1`, `dpEF1`): 0x84 (Leevers, the pot in the west
  corridor) -> 0x74 (the fire Debirando's pocket) -> 0x73's torch room
  (dash into the torch: the bonk key) -> 0x85's compass room (the key
  door, the Popos -> the north shutter, the compass) -> 0x75 (the big
  key) -> 0x73's pot room (in through the one-sided shutter, the pot
  switch) -> the big chest (Power Glove) -> 0x83 -> out of the west door
  -> a gray rock lifted -> the back door (entrance 0x0C) -> 0x63 (push
  block -> shutter, pot key, the stair mask) -> 0x53 (SW quarter
  cleared -> shutter, pot key) -> 0x43 (pot key, magic from the pots, the
  lamp on four torches, the wall slides 73 px) -> the big key door ->
  0x33 Lanmolas (beaten, heart container 32 -> 40) -> the pendant ->
  outside. Shots `r24/shots/dp24_a02..f05`.
  - **Real app**: stage F from `dp_boss` (`real/out/real_r23ck_F1.log`,
    CK PASS: Lanmolas, heart, pendant, out) and stage E from `dp_63key`
    (`real_r23ck_E1.log`: block, keys, torches, wall, boss door; its only
    FAIL was the already-taken key, fixed). Shots
    `r24/real/shots/r24real_E_*`, `r24real_F_*`.
  - **Harness aid (bot, not engine):** the runs use `HPFLOOR=8`: a hit
    never takes Link below one heart; the absorbed damage is counted
    (`ASSIST` lines: about 300 health over the walk, most of it in 0x43
    / 0x33). The bot is a poor fighter (Beamos lasers, fireballs, the red
    Eyegore it walks past, Lanmola contact).
- [ ] 24.3 Outdoor enemies (Geldman, Vultures, Debirando outdoors):
  not ported.
- [ ] 24.4 Sound effects: not started.
- [x] 24.5 Regression: see below.

Import cacheVersion 26 (DesertPalace.extract).

Tests and audits: every `zelda_alttp_*` test passes (21 files; new
`tests/zelda_alttp_r24_test.lua`, 39 checks: the tables, the pits and
their Debirandos, fireballs, the drag, the wall cannons, the moving wall
and its collision / hold / state bit, the Lanmolas' rise, shrapnel, sword
throw-back, state 5 and heart, the two palaces' prizes); audits rooms
304 / 304 and overworld 80 / 80 (`r24/out/audit_rooms_r24.log`,
`audit_ow_r24.log`). Real app also ran stages A-D from `dp_h`
(`real/out/real_r23ck_AD1.log`: every step but the bot's first Debirando
fight in 0x74, which it walks past; shots `r24real_AD_*`).

## Round 25 (2026-11-11)

Harnesses: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r25/` (copied from
r24, paths moved; one LOVE process at a time, below-normal priority, 1 ms
a frame). No run from a new game: `harness/ck25.lua` (`runck.sh`, CK=<name>)
loads a checkpoint in a room or (new) on the overworld; the leg is
`harness/dm25.lua` (`SEG=.../dm25.lua STAGE=A|B|C`), the chain
`chain25.sh`; the real app runs the same leg through
`real/harness/scene_r23ck.lua` with `ROUTE=.../ck25.lua` (`real/runreal.sh
r23ck`, CKTAG=_real).

Checkpoint chain (r25/out, newest last): `dp_done` (r24) -> **`oldman_cave`**
(stage A: room 0xF0, the old man's cave, from the Desert Palace's door
through the desert, the south road, Kakariko and the mountain foot; the big
rock lifted) -> **`oldman_out`** (stage B: the old man found, following,
through 0xF1, out on Death Mountain, area 3) -> **`mirror`** (stage C: by
his house he turns back into the sprite, gives the Magic Mirror and walks
home; Link free on Death Mountain). Real-app copies end in `_real`. The real app ran
all three stages from the same checkpoints (`real/out/real_r23ck_A1.log`,
`_B1`, `_C2`: every step PASS, no runtime error; shots
`r25/real/shots/r25realA_*`, `r25realB_*`, `r25realC_*`).

- [x] 25.1 **Outdoor enemies** (new `OwEnemies.lua`, see alttp.md "Round
  25"): the area lists load by the cartridge's proximity rule and are
  released outside the camera's box; Raven, Vulture, Buzzblob (the zap),
  Deadrock (stone), Geldman, Tektite, the land mine and its sprite bomb.
  No overworld Debirando exists in any list (all three phases scanned).
  Shots `r25/shots/owe25_*`, `sword25_*`.
- [x] 25.2 **Big rocks and the gloves** (new `BigRock.lua`): the GBA's
  kTile50data / kGetBestActionToPerformOnTile_a rule (Carry.lua's pair rule
  was wrong for 0x53 / 0x55 / 0x56); the 32 x 32 rock in front of the old
  man's cave lifts with the Power Glove. Shot `rock25_1`.
- [x] 25.3 **The old man** (new `OldMan.lua`): lost in 0xF0 (0x9C), follower
  4 (speed 12, the trail, the GBA's trigger tables: 0xF1's 0x99 / 0x9B
  seen), back to a sprite by his house (0x9D), the Magic Mirror (0x1A,
  message 0x6E), walks home; at home his message and the hearts. Shots
  `r25/shots/dm25_b*`, `dm25_c*`, `omdraw`.
- [x] 25.4 **Desert statues are not barriers** (GBA 0x080EE1D0 calls no
  barrier routine): round 23's box trapped Link on the palace stairs once
  the statues were back after leaving the palace (`zelda_alttp_r23_test`
  updated: "a statue is not a barrier").
- [~] 25.5 Death Mountain: walked from the old man's cave exit to his house
  (Deadrocks, Tektites). **Not done**: the warp tile, the Dark World as a
  bunny, the mirror's world crossing (Module09_MirrorWarp), the Tower of
  Hera (rooms 0x77.. : Mini Moldorms, crystal switches, Kodongos, Hardhat
  Beetles, Sparks, Bumpers, the fire bar, Moldorm), the Moon Pearl, the
  third pendant. Finding: from the warp tile's landing in the Dark World a
  flood fill (ledges excluded) does not reach the spot under Hera's plateau:
  the Dark World leg needs ledge hops.
- [ ] 25.6 Sound effects: not started.
- [x] 25.7 Fight bot (harness aid only): `harness/owfight25.lua` swings at
  an enemy whose hit box (y - z) comes within 26 px (fliers too), never at
  Buzzblobs / sunk Geldmen / stone Deadrocks / mines, picks up hearts when
  hurt, and the follower re-plans after every fight (`bot.lua` B.onStep).
  **HPFLOOR use: none this round** -- stage A ran with HPFLOOR=8 and
  absorbed 0 damage (ASSIST 0 0), and passes without the floor too
  (`out/dmA_nofloor.log`: 6 hits, 23 swings, 3 kills, ends at 12 / 40);
  stages B and C run without it. (Round 24's Desert Palace needed ~300
  health of floor; that leg was not re-run.)

Import cacheVersion 27 (OwEnemies / OldMan tables, the big rocks' map16).

Tests and audits: every `zelda_alttp_*` test passes (22 files; new
`tests/zelda_alttp_r25_test.lua`, 50 checks); audits rooms 304 / 304 and
overworld 80 / 80 (`r25/out/audit_rooms_r25.log`, `audit_ow_r25.log`).

## Round 26 (team A) (2026-11-11)

No route or bot runs this round (user rule: wait to playtest until every
area is in). Checked by `tests/zelda_alttp_r26a_test.lua` (43 checks) and
in-place harness scenes in `G:/Gen2Recomped/scratch_claude/zelda/alttp/r26a/`
(`harness/dw26.lua`, `swim26.lua`, `tools26.lua`, `ev26.lua`; shots in
`r26a/shots`). Every table is the GBA's own (offsets in each module's OFF)
or a named zelda3 constant where no GBA copy could be told apart by value.

- [x] 26A.1 **Dark World mechanics** (new `DarkWorld.lua`): the warp tiles
  (attribute 0x4B, TileDetect_MainHandler(0)'s alignment rule; the ones
  under rocks come from secret 0x82), Module09_MirrorWarp (the white
  filter and the HDMA wave's timing, about 170 frames), the Magic Mirror
  (Dark World -> Light World; in a palace, back to its entrance), the
  mirror portal 0x6C (GBA vortex flags 0x1750AC; made again on every Light
  World load from a building), TileCheckForMirrorBonk (the bump back), the
  bunny without the Moon Pearl (yt 0x21, palette row 0xE0, no sword / lift
  / dash, only the mirror and the bottles, song 4).
- [x] 26A.2 **Gear** (new `Gear.lua`): every receipt goes through the GBA's
  kMemoryLocationToGiveItemTo / kValueToGiveItemTo (0x16E344 / 0x16E4A4),
  with the special cases of AncillaAdd_ItemReceipt: swords 1-4, shields
  1-3, mails (Link's palette rows 0xB0 / 0xC0 / 0xD0, drawn), the Power
  Glove / Titan's Mitt, flippers, Moon Pearl, medallions, the flute, the
  pieces of heart (four make a container), bottles and potions.
- [x] 26A.3 **Deep water** (new `Swim.lua`): Link hops in; without the
  flippers he is put back on land (Module09_2A, no damage, blinking);
  swimming uses the cartridge's momentum (kSwimmingTab1-4, GBA 0x167E0A..),
  strokes and poses; he leaves by shallow water or hops out onto land.
- [x] 26A.4 **Tools** (new `Tools.lua`): the Fire Rod (lights torches,
  damage, the burst), the Ice Rod, the hammer (pegs 0x21B -> 0xDCB, a
  sprite hit), the shovel (diggable tiles, buried secrets, the flute in area
  0x2A), both boomerangs (return, catching drops), the hookshot (GBA
  AncillaAdd_Hookshot 0x080ADBF0; pulls Link to attribute 0x27; he swims if
  he lands in water). The item-in-hand pictures come from the item strip
  (rod, hammer, shovel, hookshot, net, cane and book blocks were added to
  Weapon.ITEM_BLOCKS).
- [x] 26A.5 **Medallions and the sealed entrances** (new `OwEvents.lua`):
  Ether / Bombos / Quake (GBA animation tables 0x167FE4.., damage to every
  sprite on screen); Misery Mire (Ether) and Turtle Rock (Quake) open at
  kEntranceTrigger (GBA 0x1719D8..) with the cartridge's map16 sequences;
  Skull Woods' back door opens to the Fire Rod on 0x43; the event bit keeps
  them open. The Ether / Bombos tablets (sprite 0xF2: R shows "can't read",
  the Book with A reads, and with the Master Sword the cutscene gives the
  medallion).
- [x] 26A.6 **The Magic Cape and the bottles** (new `Cape.lua`): the cape's
  magic drain (kCapeDepletionTimers) and no damage under it; red, green
  and blue potions and a bottled fairy.
- [ ] 26A.7 Sound effects: researched only. The GBA renumbers sound ids at
  every call site (the hookshot's Ancilla_Sfx2_Pan passes 0x28 where the
  SNES passes 0x0A). GBA 0x0812A324 plays id n from the u32 table
  0x08198C94 (low 16 bits = m4a song, bits 16-23 = channel). No SNES -> GBA
  id table exists, so each event's id must be read from its call site.
- [ ] 26A.8 Not started: the flute's bird travel and the weathervane, Cane
  of Somaria, Cane of Byrna, magic powder / mushroom / the witch, the bug
  net, the Master Sword pedestal (special area 0x80 is not imported), the
  smiths, the fat fairy, Zelda's capture / Agahnim's cutscenes, Kakariko /
  Dark World people, the dig and chest games, the dungeon map screen, the
  Dark World's own enemies (Moblin 0x12, Ropa 0x22, Stal 0xD3, Hinox 0x11,
  Snapdragon 0x0E, Zora 0x55, Lynel 0xD0...) and the overlords.

- [x] 26A.9 **Team A's items on team B's bosses** (new `BossHooks.lua`,
  installed after Dungeons26): the hammer's impact reaches
  PalaceOfDarkness.hammerHit (HelmasaurKing_CheckMaskDamageFromHammer, the
  king's box + 8); the hookshot catches an Arrghus puff and carries it back
  (SwampPalace.hookPuff); Fire Rod shots and Bombos melt Kholdstare's shell
  (IcePalace.fireHit, classes 11 / 13); the rods reach Trinexx's heads
  (TurtleRock.rodHit, 11 / 12); arrows reach Ganon (Ganon.arrowHit; silver
  = GBA bow byte 0x20 >= 3, receipt 0x3B). Ancillae now meet any sprite of
  those palaces (Ancilla_CheckSpriteCollision takes every sprite in state
  >= 9, the BG-drawn shell too); a part that refuses the hit lets the shot
  go on. The Moon Pearl (Hera's big chest, 0x1F) ends the bunny at once.
  Checked by real item use in place (r26a/harness/bh26.lua, 9 new checks in
  zelda_alttp_r26a_test). Not done: the fat fairy (silver arrows come only
  from receipt 0x3B), the Cane of Somaria, the Master Sword grove.

Import cacheVersion 29 (`ExtractA26.lua`: t.dw, t.gear, t.swim, t.tools,
t.events). Shared-file edits (anchored): Game.lua (7 install lines; in
drawLink the Link palette key, the weapon types and the item-in-hand flag),
Extract.lua (1 line), init.lua (cacheVersion).

Tests and audits: every `zelda_alttp_*` test passes except one check in
`zelda_alttp_combat_test` ("guard stunned about 16 frames": 41). It fails
with this round's team-A modules switched off too, so another change this
round caused it, not team A. Audits: rooms 304 / 304, overworld 80 / 80
(`r26a/out/audit_rooms_r26a.log`, `audit_ow_r26a.log`).

## Round 26 (team B) (2026-11-11)

User rule this round: port as much as possible, no route or bot playtests;
check with unit tests, audits and short in-place scenes only (Link put
straight into a room). Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r26b/`
(`lua/boot.lua` headless probes with `STORE=`, `harness/shots26.lua` room
shots, `py/dmd26.py` / `bfind.py` table finders).

- [x] 26B.1 **Dungeon-wide mechanics** (new `Dungeons26.lua`, the hub that
  registers the palace modules into `Palace.register` and imports
  `data.t.d26`): crystal switch 0x1E and the blue / orange pegs (attributes
  0x66 / 0x67 flipped, the 16-frame peg update with the four peg frames of
  bg sheet 0x0F, state reset per entrance and applied on every room load);
  star tiles and the room overlays (tags 0x21, 0x23, 0x24, 0x34-0x37, 0x39,
  0x3A; GBA overlay table 0x1633C8, kPredefinedTileData 0x164520, star CHR
  from bg sheet 5 tiles 48 / 49); pits (0x20, 0xB0-0xBD: pulled in, the
  fall, header byte 9 = the room below, kDungeonPitsHurtPlayer 0x1676FE);
  the boss death (state 4 explosions, the heart).
- [x] 26B.2 **Tower of Hera** (`Hera.lua`): Giant Moldorm (tail-only damage,
  body tink + throw-back, the segment explosions), Mini Moldorm, Hardhat
  Beetle, Mini Helmasaur, Sparks, Firebars, Kodongo + fire, Bumpers; the
  Pendant of Wisdom (item 0x38) falls by room tag 0x25; the Moon Pearl is
  0x27's big chest (item 0x1F; the item itself is team A's).
- [x] 26B.3 **Agahnim** (`Agahnim.lua`): 0x7A (balls 0x7B sent back only by
  the sword, lightning 0xBF, the Ganon's Tower clones, the altar cutscene
  0xC1 in 0x30), Agahnim 1's death -> the warp into the Dark World pyramid
  (team A's world); Agahnim 2 -> the phantom-Ganon flag.
- [x] 26B.4 **Helmasaur King** (`PalaceOfDarkness.lua`): mask (test hammer
  hook), tail, fireballs, death.
- [x] 26B.5 **Arrghus** (`SwampPalace.lua`): 13 puffs on their ring, the
  hookshot test hook, the jump and the swim, death.
- [x] 26B.6 **Mothula + spike blocks** (`SkullWoods.lua`), **Blind** with
  heads, laser and fireballs (`ThievesTown.lua`, maiden = test hook).
- [x] 26B.7 **Kholdstare** shell / split / falling ice (`IcePalace.lua`, fire
  test hook), **Vitreous** and its eyes (`MiseryMire.lua`).
- [x] 26B.8 **Trinexx** body, fire / ice heads, snake phase
  (`TurtleRock.lua`, rod test hook); **Ganon** states 0-19, bats, dark phase,
  silver arrows (`Ganon.lua`, arrow test hook), death -> `progress.ganonBeaten`
  / `game.endingPending`.
- [ ] 26B.9 Not done: the swamp water levels, Ganon's falling floor
  (overlords 0x0C-0x0F), the Triforce room and the ending, the Somaria
  platforms, conveyors, Wallmasters, water Zoras indoors, most common
  enemies of the later palaces (Bari, Medusa / shooters, Terrorpin, Gibdo,
  Stalfos Knight, Pengator, Freezor, Wizzrobe, Firesnake, Hover, Kyameron,
  Zol, Gibo, rollers, pipes, Chain Chomp, Pokey, laser eyes, Lanmola 0x80
  ...), the maiden follower, sound.

Import cacheVersion 31 (28 / 30 / 31 are team B's; 29 is team A's).

Tests and audits: every `zelda_alttp_*` test passes (27 files; new
`zelda_alttp_r26b_test.lua` 34 checks, `_b2` 34, `_b3` 29, `_b4` 36);
`zelda_alttp_combat_test` moved its guard scene 4 px down (at -20 Link's
head stood over 0x82's lower-floor pit, which now pulls him in). Audits
rooms 304 / 304 and overworld 80 / 80 (`r26b/out/audit_rooms_r26b.log`,
`audit_ow_r26b.log`).

## Round 27 (team A) (2026-11-11)

Cut short: the usage limit hit twice and the round was wrapped up early.
No route or bot runs (user rule). What landed is the module scaffold plus
GBA research, plus two helper modules written but not yet scene-checked
(27A.7).

- [x] 27A.0 **Scaffold**: new `ExtractA27.lua` (one extract call in
  Extract.lua, one install line in Game.lua after BossHooks) imports and
  installs `Grove`, `FatFairy`, `Smiths`, `Flute`, `Items27`, `Story27`,
  `OwEnemies27`, `DungeonMap` and `Sfx` (installed last: it will wrap the
  other modules' call sites). All nine are stubs (empty t.<key> tables,
  no-op installs). `OwEnemies.lua` exports its sprite helpers as `OE.H`
  for OwEnemies27. `tests/zelda_alttp_r27a_test.lua` (26 checks).
- [ ] 27A.1 Master Sword grove (research done, not ported): enter
  special area 0x80 when map8 0x105 (word & 0x1FF at Link + (8, 12)) is
  under Link in area 0 going up (kSpecialSwitchArea_* GBA 0x14CEBC /
  0x14CEC4 / dir u16 0x14CECC / exit 0x14CED4); back out on map8 0x17C
  going down (kSpecialSwitchAreaB GBA 0x150D10 / 0x150D16 / 0x150D1C).
  kSpExit_Top 0x150C80, LeftEdge 0x150CA0, Dir 0x150CC0, SprGfx 0x150CD0
  (grove 0x0C), AuxGfx 0x150CE0 (0x2F), PalBg 0x150CF0 (0x0A), PalSpr
  0x150D00 (1); the GBA's Bottom/Left/Right/Tab4-7 differ (240x160 view).
  Maps 0x80 exist in the import (bg2 map 128, bg1 247); owAuxTileset has
  only 128 entries, so sheets/palette/sprite set for 0x80+ must come from
  kSpExit_*. Pedestal = sprite 0x62 (MasterSword_Main: R facing up with
  pendants & 7 == 7; states 240 / 192 / 8 / 16 frames; Link pose yt 0x17
  rt 9/10; receipt 1; event bit 0x40 of area 0x80). GBA tables:
  kMasterSword_Gfx1 0x174FE4, NumLightBeams 0x174FED, light-ball DMD
  0x174FF8 (12 x 8 bytes, GBA chars 0x82 / 0xC0 / 0x80), beam Xv/Yv
  0x175058, beam gfx/flags 0x175068, pendant Xv/Yv 0x175070,
  MasterSword_Draw X/Y/chars 0x175084 / 0x17508A / 0x175090 (GBA chars
  93 94 B3 B4 D0 F0). The plan: world "sp" (Overworld.screenAt + 0x80,
  G:visibleScreens / Zoom's list + 0x80, P.selection / O.sheets /
  owSpriteSet from kSpExit_*).
- [ ] 27A.2 Sound (research, not wired): play-by-id 0x0812A324, table
  0x08198C94 has 133 entries (0x00-0x84). Wrappers: Ancilla_Sfx2_Near
  0x0809E43C, Sfx3_Near 0x0809E49C, SfxN_Pan 0x080C19F8,
  SpriteSfx_QueueSfx1/2/3WithPan 0x080CF018 / 0x080CF0AC / 0x080CF140
  (GBA ids per SNES bank; no constant offset). Ids read at call sites:
  sword 1-4 = 0..3 (0x16809E), spin charge 0x19, tink 0x71, shield 0x09,
  enemy hit 0x53 (0x56 / 0x57), Link hurt 0x07, item get 0x7A, Master
  Sword 0x0F, heart piece 0x47, pickups 0x70 / rupee 0x74 / key 0x12
  (kAbsorptionSfx 0x173034), debris 0x6D / 0x72 (0x1720BC), jump 0x04,
  land 0x0D, pit 0x0E, swim 0x3A, hookshot 0x28, magic 0x6B, error 0x40,
  cape 0x14 / 0x15. Probable: dash 0x11, bonk 0x05. Notes in
  `r27a/sfx/` (table.txt, gba.txt, snes.txt).
- [ ] 27A.3 Smiths / flute (research, not ported): frog sprite 0x1A in
  DW area 0x69; smithy room 0x121 (entrance 100); draw tables 0x174DF4 /
  0x174D64 / 0x174DAC / 0x174EA4; followers 7 / 8 (0x17EA0E, 0x17EA3E,
  0x17EBFE, 0x17EC3A); msgs 0xE4 / 0xDB / 0xE0 / 0xE7 (GBA = SNES + 3).
  Flute kid 0x174C6C (area 0x2A), stump 0x174CEC (0x6A); weathervane
  overlay 0x0808FD34 (map16 0xE21-0xE25 at 0xC3E..0xCC2), debris
  0x1803E0..; bird draw 0x1803D0; flute menu 0x080B2F18 (9 spots, area 7
  after Turtle Rock), landing table 0x150B18 (20 bytes each), markers
  0x16EED0. Notes in `r27a/world/`.
- [ ] 27A.5 People / story (research, not ported): chest-game prizes
  0x1534F6 / 0x1534FE, dig-game items 0x1690CC, fortune teller 0x174F0C /
  prices 0x174ED4, talking tree 0x1798A0..0x1798C4, shop rooms 0x17D020,
  people draw tables (innkeeper 0x175FE0, storyteller 0x1763C0, thief
  0x17768C, dig-game guy 0x17A2B0, Kiki 0x17A55C, barrier 0x179E18 ...);
  dig-game msgs BMG 0x18F-0x194; minigame chests attribute 0x63 in rooms
  0x100 / 0x106 / 0x118. Zelda's capture is team B's altar scene. Bug
  seen: Drops.lua G:storyProgress wants p.agahnim, Agahnim.lua sets
  p.agahnim1 / p.sramProgress = 3, so phase-3 overworld lists never load.
  Notes in `r27a/story/`.
- [ ] 27A.6 Dungeon map (research, not ported): L opens it (0x0806CE90)
  when cur_palace (+0xAB2) != 0xFF and +0x9DA != 0; module 0x0E sub 3,
  state +0xA4C / init +0xA5A; tables 0x0816F06C (9 states) / 0x0816F058;
  data 0x16EF90-0x16FDE8 (floors kDungMap_Tab5 0x16F702, 14 floor-layout
  ptrs 0x16FCF4, room-tile lists 0x16FDE8, Tab23 words 0x16F132: blank
  0x2200, needs-map bit 0x4000); room memory 0x02002000, map bits
  0x02002348, BG buffer 0x02003080. `r27a/dmap/ref3.py`/`ref6.py` run the
  cartridge's map module in the scratch emulator (floor boxes and frame).
- [~] 27A.7 **Written but NOT yet checked in a scene or test** (they load;
  every zelda_alttp test passes with them installed):
  `OwEnemies27.lua` -- Octorok 0x08 / 0x0A + stone 0x0C, Snapdragon 0x0E,
  Octoballoon 0x0F + babies 0x10, Hinox 0x11 + bomb 0x4A, Moblin 0x12 +
  spear 0x1B, Ropa 0x22, River Zora 0x55 + fireball, Crab 0x58, sword
  guards 0x41-0x43 outdoors via Guard.update (tables in M.OFF,
  0x177424..0x17A3xx; rough spots: bomb doesn't bounce, Zora surface probe,
  Octoballoon_Find skipped). `Items27.lua` -- magic consumption byte
  (Magic Bat halves costs; Tools.magic routes through it), magic powder,
  bug net (msgs 0xC8-0xCA), Cane of Byrna, Cane of Somaria (block on
  switches via Palace.roomTags wrapper, pits / water, 4 bullets), Turtle
  Rock's Somaria platforms (no team-B hook existed), the Lost Woods
  mushroom, the witch (drawn from disassembly constants: no GBA copy
  found), the powder in 0x109, the Magic Bat in 0xE3. Kill switch: empty
  M.install. Missing: block carry/throw/push, TR pipes, Mad Batter
  lightning, sound.
- [ ] 27A.4 Not started / not landed: fat fairy, story scenes and
  people, dig and chest games, DW shops, Stal / Lynel / Pikit / Zirro /
  Poe / Swamola / Toppo / Thief / Armos / soldiers 0x45-0x4B outdoors, the
  overlords, the dungeon map screen (partial research in `r27a/items`,
  `r27a/story`, `r27a/enemies`, `r27a/dmap`).

cacheVersion stays 31 (the stubs import empty tables). Tests: every
`zelda_alttp_*` test (see `r27a/out/test_*.log`).

## Open issues

- Round 26 (team A):
  - **Still open:** see 26A.7 / 26A.8 in "Round 26 (team A)".
  - **Ours:** the mirror wave is not drawn (timing only); the white filter
    is a "lighten" fill; no poofs, splashes, hit stars, wall clinks; stun /
    freeze codes hold a sprite 64 frames (no ice blocks); the hammer's
    sprite box is 16 x 16 at its tile point; spells are a 96-frame flash;
    the dug flute is received at once; potions fill at once; the cape
    draws Link at half alpha.
- Round 25:
  - **Still open:** the warp tile and the Dark World (Module09_MirrorWarp,
    the bunny without the Moon Pearl), the mirror's crossing and its portal
    sprite 0x6C, the Tower of Hera and Moldorm, the Moon Pearl, the third
    pendant; the area lists' other types (soldiers 0x41-0x4B outdoors,
    Octoroks, Crabs, Toppo, Hinox...) and their overlords (0xF4+, the
    falling rocks); sound effects.
  - **Ours:** see alttp.md "Round 25" (the follower's picture and trail
    reset, the land mine's bomb, sloped tiles for sprites, the big rock's
    carried picture).
- Round 16 (round 17: tags 0x15-0x17, 0x25 and 0x27 are ported in
  Palace.lua): room tags 0x14 (water puzzle) and 0x33 (torches) are not
  ported; the large blocks cannot be lifted (no glove), bomb floors are not
  bombed, torches are not lit. People: only the townsfolk listed in
  alttp.md are spawned outdoors (no soldiers / octoroks / vendors from the
  lists yet), the snitch ladies do not call the guards, message 0x2C's
  choice cursor is not drawn ("yes"), no shops. (The Eastern Palace's
  door: fixed in round 17 by the GBA's x + 16 column rule.)
- Round 17: the overworld door test runs only while Link walks up and
  keeps the one-row doorstep allowance (OURS). The GBA runs it every
  frame; doing that here makes the walk-out from the castle's hall onto
  its opened big door re-enter at once, so the GBA's exit positions there
  are not matched yet. House doors have attribute 0x02 under their door
  tile and our Link stops one tile short.
- Round 17: small keys are one counter for every palace. The big chest
  does not check for the palace's big key yet. The Eastern Palace past
  room 0xB9 is not walked by the route (see 17.2). (Round 18: keys and big
  keys are per palace, the big chest and door 0x1E want the big key, tag
  0x33 / 0x3E torches are ported; the route climbs B9 and reaches A9.)
- Round 18: the route bot finds no way from B9 to B8 (the big key room):
  B9's west door is on the upper level's outer ring, which our collision /
  the planner do not connect to the entrance or the track (not traced on
  the cartridge yet). So the walk stops in A9; the big key, the Bow from
  the big chest, the dark rooms, the red Eyegores, the basement and the
  Armos Knights are tested in place only.
- Round 18: the HUD's item box does not show the chosen item (the GBA's
  Hud_RefreshIcon is not ported); large blocks indoors cannot be lifted
  (the glove rule is ported outdoors only); bomb floors are not broken;
  the falling Stalfos' head and their own pictures are not ported; Link's
  bow / lamp poses are not drawn.
- Round 19:
  - **Still open:**
    - The route bot does not get past D9's column of three green
      Eyegores, so D8, C8, the heart container, the pendant and
      Sahasrahla's boots are not walked in one run.
    - The bot's 99 Eyegore fight is close: it wins with 4-20 hp left.
    - The bot loses C8's Armos fight in place.
    - The bow's own picture (link_dma_var5).
    - Lifting and throwing bombs.
    - The falling Stalfos' own pictures and their thrown head.
    - The spin attack.
    - The overworld dash (Link_BonkAndSmash).
    - Every round-18 world interaction (19.3).
  - **Ours:**
    - The held sword walks every other frame.
    - The dash has no dust, sound or hop.
    - Room prizes rest where the list puts them.
  - **Fixed** (the round-18 "B9 -> B8" issue): the ring is reached from BA's
    key door, as on the cartridge.
- Round 20:
  - **Still open:** D8's red Eyegores in the route (arrows run short; the
    bot's last D8 order not re-run end to end), the bow's picture, the dash
    dust / sound, rock piles, the spin outdoors, the Book of Mudora
    (Sprite_DashItem), every round-18 world interaction.
  - **Ours:** a thrown bomb flies the pot's arc; the falling Stalfos' head
    cannot be hit; a dead sprite vanishes at once (no death puff); the dash
    shake is not drawn.
- Round 21:
  - **Still open:**
    - the bot's Armos fight in the real app (and C8 5 / 8 in place);
    - the ball-and-chain guard's rate (6-7 / 8; the real app needed up to 5
      tries);
    - no sound effects at all;
    - the yes / no cursor;
    - shops, the glove, outdoor enemies, the Desert path.
  - **Ours:**
    - lifted pots stay lifted;
    - the book's drop from the shelf (y + 64) and its icon picture;
    - the rock pile's debris kind;
    - the shake is not zeroed at the overworld's scroll edges;
    - only the bow's block of the item strip is drawn.
- Round 24:
  - **Still open:** outdoor enemies (none spawn from the area lists),
    sound effects, the bot needs an HP floor in the Desert Palace (Beamos,
    fireballs, Lanmola contact), the yes / no item chooser.
  - **Ours:** see alttp.md "Round 24" (garnishes, Lanmola bursts as
    puffs, cannonballs and the kill tags).
- Round 23:
  - **Still open:** walking the Desert Palace (keys, big key 0x75, the
    0x73 torches / bonk key), Debirando, the wall cannons, Lanmolas, the
    back half; outdoor enemies (none spawn from the area lists); the big
    boulders' strain-lift; sound effects; the bot's long overworld legs use
    a full-map BFS (slow, harness only).
  - **Ours:** the prayer's veil and iris shapes, no praying poses; the
    statues' wall probe uses the indoor solidity table on overworld
    attributes; the Leever's sand-char palette mask (GBA chars >= 0x48); the
    laser's char 0x3C inferred; no laser sparkle; no sounds.
- Round 22:
  - **Still open:** the real-app route dies in A8 (four Stalfos, the bot
    walks with fighting off) and sometimes on B9's track; the
    ball-and-chain guard 6 / 8, B8 6 / 8 (stalls), C8 5 / 8 at 16 hp; no
    sound effects; the Power Glove, heavy rocks, outdoor enemies, the
    Desert path and palace; the chest games / thieves (other 0xBB
    subtypes); the item chooser (text command 0x69).
  - **Ours:** the shop's "touching" (Link's box + 2 px); the cursor glyph
    picked by its shape (font tile 0x00).
- Music id -> song mapping is a guess (399 + SNES id); needs the cartridge's
  translation table (still open after round 10).
- Round 11 fixed the round-10 layer issues (the cartridge's two tables,
  door attributes and toggles; see Round 11). Still ours: the layer-toggle
  latch (cells checked along Link's way out), the ledge hop's arc and
  length, the south straight stairs starting at the 0x39 row, knockback
  not crossing in-room stairs, the adjacent-room key-door pairing by
  column / row, the shutters 0x18 / 0x48 / 0x4A kept open (round 16: closed as on the cartridge), and
  kind_of_in_room_staircase taken from the room's last in-room stair.
- The GBA's file / name front end: ported in round 13 (alttp.md "The front
  end (round 13)"), letters ours.
- Round 12 doors: the overworld doorstep allowance (one tile above Link) is
  ours; a diagonal into a doorway follows the code (not checked on hardware);
  the 0x71 loop is fixed (round 13.1).
- Round 13 leftovers after round 14: the parry and the knife guard 0x4B
  are ported; the ball-and-chain guard 0x6A keeps the stand-in AI (and no
  parry); the front end's font (names, letter grid) is not decoded.
- Round 14: zoom-out indoors follows doors only (no open edges); dark
  rooms' 0xB3 colour math and rooms 0x0D / 0x90 / 0xA4 / 0xAC's layer
  cases are not ported; the rising chest item's OAM priority is not traced.
- `Data.load` holds the whole cache in memory (~3 MB); fine on desktop/phone.
- Audio reads `<prefix>assets/generated/audio/m4a.bin` through
  love.filesystem (the M4A worker's read path); a portable/custom data root
  relies on the foundation mounting the cache on the read path.

## Requests for other agents

- Foundation (round 14, done by the ALttP agent as small anchored edits in
  `src/zelda/ZeldaRuntime.lua`, please keep): optional game hooks
  `viewSize(scale)` + `drawOverlay()` (a zoomed play field in its own
  canvas, the HUD on top at the normal scale; 240 x 160 = unchanged path),
  `menuOptions()` / `menuOption(id, dir)` (extra system-menu rows),
  `wheelmoved(x, y)` forwarded to the game, and `Host:gameOption(key,
  value)` (persistent per-game options in options.zelda.game[version]).
  Minish Cap can use the same hooks.

- Foundation: `newGame(opts)` uses `opts.cache` (or `opts.root`), `opts.input`,
  `opts.save`, `opts.options.musicVol`; the game implements update/draw/save/
  quit and netSnapshot/netApply/netEvent/netPeerLeft/netAttached/netDetached.
  `extract` uses `ctx.bytes` and `ctx.checkpoint`. No new hooks needed now.
- Foundation (nice to have): call `ChipAudio.stopMusic()` is already done via
  `love.audio.stop()` on quit — fine. If the runtime ever ticks without
  `update`, music buffers still need `ChipAudio.update()`; the game calls it
  from its own update.

## Round 27 (team B) (2026-11-11)

No playtests (user rule): unit tests and short in-place scenes only. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r27b/` (`BRIEF.txt`, `run1.sh` =
lock-serialised headless runner, group folders a-f, `lua/cov.lua` coverage scan).
Six new modules, all loaded by `Dungeons26.lua` (D.MODULES); no shared file
edited except Dungeons26 (module list), init.lua (cacheVersion 32) and one
line in Ganon.lua (the falling floor).

- [x] 27B.1 `Enemies27A.lua`: Red/Blue Bari (zap, split), Blob/Zol + spawner
  overlord 0x08, Gibdo, Stalfos Knight (collapse, bomb rule), Green Stalfos,
  Firesnake, Hover, Sluggula (+ sprite bomb), Gibo, Zazak blue/red (fire).
- [x] 27B.2 `Enemies27B.lua`: Pengator, Freezor (fire hook), Kyameron,
  Terrorpin (hammer hook), Wizzrobe + spawner, Babasu, Pirogusu + spawners.
  Zoro spawner partly (waits for attribute 0x82 nothing sets yet).
- [x] 27B.3 `Traps27.lua`: Medusa, 4-way shooter, laser eyes 0x95-0x98, eye
  statue, big spike, rollers, Chain Chomp, Pokey, Wallmaster + overlord 0x09,
  movable statue, pull switches 0x04/0x06 (good/bad), overlords 0x06/0x1B
  snake / bomb traps, 0x18 pot trap, 0x19 invisible Stalfos, bunny beam (flag
  only), room tags 0x14 / 0x16 / 0x1C-0x1F by the state-change flag.
- [x] 27B.4 `Mech27.lua`: Swamp water switch 0x21, flood / drain / water gate
  tags 0x18-0x1A, dam side of room 0x28; conveyors 0x68-0x6B; moving floor
  overlord 0x07; spike floor 0x0D / spike tile 0x44; bomb floors (0x62 -> pits,
  Blind's light in 0x65); Kholdstare's shell picture cleared.
- [x] 27B.5 `Floors27.lua`: falling-square overlords 0x0A-0x10 (7 on the
  GBA), Ganon's falling floor (0x0C-0x0F), the tile room (overlord 0x15 +
  flying tiles 0x94), Turtle Rock pipes 0xAE-0xB1, Somaria platforms (hooks
  for team A's cane: somariaBlock / somariaBlockCreated / somariaPoof /
  somariaPlatform).
- [x] 27B.6 `Ending27.lua`: falling / rising crystal, crystal maiden
  cutscenes (all seven Dark World palaces, progress.crystals), Blind maiden
  0xB7 follower -> Blind, Ganon door, Triforce room, the 16 ending scenes'
  order / timing / texts and the staff roll from the ROM, THE END.
- [ ] 27B.7 Not done: Link cannot swim indoors; the water switch cannot be
  pushed with real inputs (Link walks through the handle, as on the GBA
  code -- unexplained); Zoro spawner trigger; bunny beam does not make Link a
  bunny; ending cinematics (people, pans, dungeon scenes black), 3D crystal /
  Triforce shapes; room 0x58 exploding-wall tag 0x28; switch attributes
  missing in rooms 0x1A/0x26/0x2B/0x57; no sound; nothing of this round
  seen on screen except group f's shots.

Import cacheVersion 32. Sprite coverage (every room list): palace rooms
101 of 106 sprite types run (left: 0x37 waterfall, 0x40 barrier, 0xC8 big
fairy, 0xF5 / 0xF6); all rooms incl. caves / houses 106 of 133 (the rest are
team A's people). Tests: see the round 27B entry in alttp.md.

## Round 28 (2026-11-11)

No route or bot runs: unit tests and short in-place scenes with real inputs
(`tests/zelda_alttp_r28_test.lua`, 64 checks). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r28/` (`run1.sh` lock-serialised
headless runner, `probe.sh`, `runtests.sh`, probes `lua/p*.lua`). cacheVersion
stays 32 (no extracted data changed).

- [x] 28.1 **OwEnemies27 checked** in their own areas (LW 0x0F / 0x15 / 0x1E /
  0x3F, DW 0x40 / 0x42 / 0x53): Octorok spits, Moblin spear, Hinox bomb,
  Octoballoon babies, Zora surfacing + fireball, Snapdragon / Ropa hops, sword
  guards outdoors, sword kills. Fixed: `spawn` wrote the spawner's values
  (sprite_A / sprite_D) before `OE.prep` zeroed them, so the Moblin's spear had
  A 0 (stuck in walls instead of breaking) and D 0 (wrong picture); the
  overworld sprite list was dropped as soon as its last sprite died, so the
  Octoballoon's six babies (and any last enemy's prize) went into a dead list
  (`OwActors.lua`: kept while `Effects.dying`). Hinox's bomb X table
  {8, -8, -13, 0} is the GBA's own (zelda3 has 13 for the last).
- [x] 28.2 **Items27 checked**: powder (Cukeman + its R talk, magic 8), the
  Lost Woods mushroom, the witch (item button held), the shop's powder bag,
  the Magic Bat (consumption 1, powder then costs 4), the net + fairy into an
  empty bottle (bottle 2 -> 6), Byrna (four sparks, drain, no damage, press to
  end), Somaria block + fission into four bullets. Fixed: the shop bag and the
  bat were set up in `G:enterRoom` before the room's sprites exist; now on
  `Actors:enterRoom` (idempotent).
- [x] 28.3 **Hooks28.lua** (installed by ExtractA27.install, after BossHooks):
  Fire Rod shot on a Freezor -> `Enemies27B.fireHit` (else "pass"); Bombos on
  a Freezor; the shot's 31-frame burst runs Ancilla_CheckBasicSpriteCollision
  ((slot ^ frame) & 3, 16 x 16 box): a Firesnake turns (`Enemies27A.ancillaHit`),
  a Freezor melts; the hammer's impact -> `Enemies27B.hammerAt` (Terrorpin
  flips by the real swing); the bunny beam's `game.tempBunny` ->
  Link_HandleBunnyTransformation (20 frames held, no sprite damage, a
  perma-bunny clears it) then LinkState_TemporaryBunny (256 frames,
  `DarkWorld.isBunny` true), cleared on the overworld / a pit with the pearl.
  Items27's Somaria block now calls `Floors27.somariaBlockCreated` /
  `somariaBlock` in a cane-ride room (Floors27's poof + platform; Items27's
  own platform only when Floors27's tables are missing): checked in 0x24 and
  ridden in 0xC6 with the d-pad.
- [x] 28.4 **Water switch handle**: PushSwitch_Draw's Sprite_NullifyHookshotDrag
  puts Link back on link_x / y_coord_prev; Mech27 now does that (OURS: one frame
  later, the sprites run before Link moves, so he jitters 1 px at the handle).
  Walking left into it holds him, 48 frames push, the flood starts.
- [x] 28.5 **Zoro spawner**: nothing was missing -- the overlords (rooms 4 /
  0x92) sit on bombable doors 0x28 / 0x2E whose opened doorway attribute is 0x82
  (kTileAttrsByDoor); a real bomb opens the door and the Zoros come out.
- [x] 28.6 **"Missing" switches**: 0x26 / 0x2B / 0x57's switches are under pots
  (secret 0x88, RevealPotItem, round 17); lifting 0x2B's pot shows attribute
  0x23 and standing on it holds the shutter open. 0x1A has no shutter door
  (key doors 0x1C and a bombable 0x2E), so its tag 0x16 has nothing to hold.
- [ ] 28.7 Master Sword grove: not started this round (usage). Plan as in
  27A.1: world "sp" (O.screenAt / O.area / O.sheets / Palette from
  kSpExit_* for 0x80; owParent / owAuxTileset have no entry for 0x80), the
  map8 0x105 / 0x17C switch tiles, then sprite 0x62.

Also left: the burst does not damage other sprites; Enemies27A's swordHit
wrapper turns a Firesnake on arrows / bombs too (zelda3 only does it in
Ancilla_CheckBasicSpriteCollision: fire burst, Somaria block); Drops.lua's
storyProgress reads p.agahnim (Agahnim.lua sets p.agahnim1).

Tests: all 36 `zelda_alttp_*` files pass (r27b_c's bunny check now accepts the
count-down); audits 304/304 rooms, 80/80 overworld areas.

## Round 29 (2026-11-12)

No route or bot runs: unit tests and short in-place scenes with real keys
(`tests/zelda_alttp_r29_test.lua`, 44 checks) and two LÖVE scenes
(`r29/harness/grove1.lua`, `grove2.lua`; shots `r29/shots/g1..g6`).
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r29/` (`run.sh` LÖVE
scene runner and `run1.sh` / `probe.sh` headless probes share one mkdir lock;
`runtests.sh`; `cdis.py` = compact Thumb disassembly of a function; probes
`lua/g*.lua` grove, `lua/f*.lua` pond, `lua/c*.lua` collision).
**cacheVersion 33** (Grove and FatFairy now import their tables: data.t.grove,
data.t.fairy).

- [x] 29.1 **Master Sword grove** (`Grove.lua`, plan 27A.1 / 28.7). The switch
  test is the GBA's 0x08071D7C (called by the transition handler 0x08071E7C
  every frame Link is not at an edge): map8 under (link_x, link_y) -- no +8 /
  +12 -- against kSpecialSwitchArea (0x14CEBC, area 0x14CEC4, exit 0x14CED4).
  Area 0's tile 0x105 row is at y 160 above the tunnel (x 160..175): Link
  enters while his y is 160..167. Room 0x180 is an exit-table entry (area
  0x80, Link at (128, 488)). The special area setup is 0x08078274:
  kSpExit_Dir / SprGfx / AuxGfx / PalBg / PalSpr are BYTE tables indexed by
  room - 0x180 (grove: facing 0 = up, sprite set 0x0C, aux 0x2F,
  Overworld_LoadPalettes(1, 0x0A)), area origin kSpExit_Top / LeftEdge
  (0, 0). Way back: 0x08078708, kSpecialSwitchAreaB (0x17C in area 0x80,
  direction 4). Our world "sp": `Overworld.screenAt` / `attrAt` / `area` /
  `sheets`, `Palette.selection`, `G:visibleScreens` / `viewScreens`,
  `G:owSpriteSet` are wrapped (one module, no edits elsewhere). Sprite 0x62
  (0x080D52D0, subtypes 0x174FB4, pedestal states 0x174FCC): the pull needs
  Link touching it, FACING DOWN (+0x16D5 == 2: the sword's hit box is at the
  pedestal's top, Link stands behind it), the three pendants and R; states
  0xF0 / 0xC0 / 8 / 0x10 frames, then event bit 0x40 of area 0x80 and receipt
  1 (sword level 2). Pendants (subtype 3: spawned at (link_x, link_x + 8) --
  the GBA reads link_x twice --, velocities 0x175070 / 0x175074, delays 0xE4 /
  0xD0 / 6 with doubling 8-bit speeds, palette flash), light ball (subtype 4)
  and light well (subtype 1) from the 0x174FF8 entries, MasterSword_Draw
  (six 8x8, 0x175084..). Checked: walking in and out with real keys, the
  pull, the receipt, the empty pedestal after (test + LÖVE scene shots).
  OURS: instant switches (the 0x17 / 0x24 fades are not traced); on the way
  out Link goes back to the spot he left the Lost Woods from and walks 16 px
  down (the GBA's restore is not traced); the 32 px under the grove map are
  walkable (our down probe is y + 23, the 0x17C row is at y 496); the light
  beams (subtype 2, 0x080D4AC4 / 0x080D4998), Link's pull poses (+0x1809
  0x0A / 0x0B) and the music cue are not done. The grove's other sprites
  (0x59 / 0x5A animals, 0x2B, the plaque 0xB3) are still not spawned.
- [x] 29.2 **The pond fairy** (`FatFairy.lua`): sprite 0x72 (0x080DF44C)
  runs table 0x176608 in rooms 0x114 (Waterfall of Wishing, entrances 92 /
  98) and 0x116 (the pyramid, entrance 99); 0x115 (low byte 0x15, Lake Hylia)
  runs 0x1765CC (not ported). All 14 states (message numbers are the
  cartridge's, BMG = n - 3): contact message 0x14D, throw / don't, 0x8D and
  the item menu, the item leaves the inventory (receipt id from kPondItems
  0x17653C [inventory offset][value - 1]), the fairy, 0x8E "Did you drop
  this?", the swap (Dark World = +0x165C: bow 0x3A -> Silver Arrows 0x3B
  with message 0x152, Tempered Sword 2 -> Golden Sword 3, bottle 0x16 ->
  0x2C; Light World: boomerang 0x0C -> 0x2A, shield 4 -> 5, bottle), "Are you
  sure?" / "don't tell lies" (same item back), the receipt, the kind's
  message (0x17669C). Checked in place with real keys: Golden Sword, Silver
  Arrows, a lie returning the shield. OURS: the throw menu is our item menu
  (A / SELECT = the chosen item, B = the sword, R = the shield: the GBA's
  own throw menu is not traced); the fairy's picture / dust, the thrown
  item's flight (ancilla 0x28), the palette filter (counted, 31 steps of 8
  frames, not drawn) and music 0x14 are not done.
- [x] 29.3 **Collision pass** (`Barrier29.lua`, installed by
  ExtractA27.install). The GBA's Sprite_BehaveAsBarrier is 0x080C5080; its
  callers are the routines of 0x16, 0x1A, 0x28, 0x29, 0x2A, 0x30, 0x32, 0x35,
  0x39, 0x3A, 0x3C, 0x40, 0x73, 0x74, 0x76, 0x78, 0xB2, 0xB5, 0xBB, 0xBC, 0xBF,
  0xD5, 0xE9, 0xF1. Indoors only Npc.TYPES, the uncle and Zelda blocked Link:
  **Link walked through** the inn's people (0x103: 0x29, 0x35), the
  storytellers 0x28 (0x10E / 0x112 / 0x114 / 0x11A), 0x29 (0x119), the bomb
  seller 0xB5 (0x11C), the smith 0x1A (0x121), the potion shop's 0xE9
  (0x109), 0x32 (0xF4 / 0xF5) -- and the crystal switch 0x1E (0x0810FC0C
  calls Sprite_NullifyHookshotDrag 0x080AF16C on contact: a wall) in 0x77 /
  0xEF. They now block Link with their cartridge hit box on the same level.
  Sweeps (probes `c1` / `c3` / `c4` / `c5`): every entrance x 4 directions
  (528 walks, no wall entered), every overworld area x 3 spots x 4
  directions (960 walks: only deep water 0x08 is entered, which is the
  no-flippers splash), every barrier sprite from 4 sides. Not changed: the
  Mad Batter 0x3A (its barrier call is in one state, not traced); the
  statue 0x1C is pushed (Traps27) so its box is entered for a frame by
  design; 0x72 / 0x62 are not barriers on the GBA either.
- [ ] 29.4 **Smiths / frog** (research only, not ported): sprite 0x1A
  (0x080D36DC, subtypes 0x174D3C: 0 smith 0x080D3064, 1 0x080D35C4, 2 the
  frog 0x080D2FA0, 3 0x080D3708, 4 0x080D2EE8, 5 0x080D374C). Frog: a barrier,
  hops (z - 2 a frame, z velocity 0x10 on landing), solicited message 0xE4
  -> follower 7 (+0x1663, 0x0812F9A8 follower graphics, 0x081146A4), dies.
  Smith (states 0x174DC4; hammer animation 0x174DB4 / 0x174DBC, spark
  0x080D3650 + sound 0x71 at step 3): 0: follower 8 and link_y low byte <=
  0xC1 -> 0xE3, state 10 (the brother joins: 0x080D347C spawns 0x1A, state
  4); a dash into him (0x080D383C: +0xA4E == 0x0E and the +0x1788 test) ->
  0xE7, delay 0x60; else reunited (+0x1662 & 0x20) ? solicited 0xDB : 0xE2;
  1: choice -> 0xDF (state 0) or 0xDC (2); 2: choice -> 0xDF, or sword
  (0x0200233D) > 2 -> 0xDE (state 0), else 0xDD (3); 3: yes and >= 10
  rupees (0x080AA868) -> pay 10 (0x080AA83C), 0xE0, both smiths state 5,
  +0xCB4 = 0, sword byte = 0xFF, +0x1662 |= 0x80; else 0xDF; 4 / 5
  (0x080D3384): dash -> 0xE7; +0xCB4 == 0 -> solicited 0xE5, else solicited
  0xE1 -> next state; 6 (0x080D390C): receipt 2 (the Tempered Sword), +0x1662
  &= 0x7F; 11: 0xE6. +0xCB4 is set to 1 by the overworld code at 0x08072470
  (8 at 0x080735D2) -- tempering ends once Link has been elsewhere. Still to
  find: the smiths' SpritePrep (where +0x1662 & 0x80 puts them back in state
  5), followers 7 / 8 (the frog turns into the dwarf in the Light World) and
  the smith / frog draw tables (0x174DF4 / 0x174D64 / 0x174DAC / 0x174EA4).
- [ ] 29.5 Flute bird travel and the weathervane: not started (research in
  27A.3).

Tests: all 37 `zelda_alttp_*` files pass; audits 304/304 rooms, 80/80
overworld areas (r26b `run.sh audit`, AUDIT=rooms|ow, store rebuilt).

## Round 30 (2026-11-12)

No route or bot runs: unit tests and short in-place scenes with real keys
(`tests/zelda_alttp_r30_test.lua`, 75 checks) and L�VE scenes
(`r30/harness/folk1.lua`, `folk2.lua`, `smith1.lua`, `flute1.lua`,
`vane.lua`; shots in `r30/shots`, montages `proof_folk.png`,
`proof_smiths.png`, `proof_flute.png`). Townsfolk30 is imported / installed
through `ExtractA27.EXTRA` (the r27a test pins MODULES at 9). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r30/` (same kit as r29: `run.sh`,
`run1.sh`, `probe.sh`, `runtests.sh`, one mkdir lock). **cacheVersion 34**
(data.t.people30 new; data.t.smith and data.t.flute were empty stubs).

- [x] 30.1 **The townspeople indoors** (`Townsfolk30.lua`, in ExtractA27's
  list). A scan of every entrance's room (`harness/undrawn.lua`) listed the
  sprites `drawActor` did not draw: 0x1A, 0x1F, 0x28, 0x29, 0x31, 0x32,
  0x33, 0x35, 0x65, 0x72, 0xB2, 0xB5, 0xBC, 0xC8, 0xE9, 0xF3/F5/F7. Now drawn
  from the GBA's own DrawMultipleData copies (found with the SNES -> GBA char
  map; offsets in the module's OFF) and talking with their solicited
  messages (SNES numbers = GBA - 3): the sick kid 0x1F (0x104; with a bottle
  the perk animation from kBugNetKid_Gfx / Delay, 0x105, the bug net, 0x106),
  the storytellers 0x28 (subtype from kStoryTellerRooms; 0xFE, 20 Rupees ->
  0xFF / 0x101 / 0x102 / 0x103 and hearts filled, else 0x100; 0x11A's 0x149
  and flip; 0x114's bob), Sprite_HumanMulti_1 0x29 by kHumanMultiTypes (the
  flute boy's father 0xA1 / 0xA4 / 0xA2 when the flute is played touching
  him / 0xA3; the hideout guy 0x171 with Thief_Draw's head char; Blind's hut
  guy 0x172), the fortune teller 0x31 (prices / readings from the GBA, the
  first two unmet goals alternating, 0xF2 / 0xF3 / reading / 0xF4, price
  taken, hearts filled), the brothers 0x32 (head to Link; 0x131 / 0x12F),
  the innkeeper 0x35 (0x182 / 0x183), the gallery host 0x65 (his X / Y /
  char / flags / big tables; 0x85), the bomb shop 0xB5 (the clerk's
  breathing delays; 0x117 / 0x118; the bombs at (-24, -24): 100 Rupees, +27,
  0x119 / 0x17C / 0x16E; the super bomb drawn once crystals 5 & 6 and the
  smiths reunited), the drunkard 0xBC (0x175). OURS: talking = R while the
  point in front of Link is within 4 px of the hit box (the cartridge needs
  contact + facing); the fortune's price is not printed ({number} not
  ported); no gallery game, super bomb purchase (follower 13), clerk puffs,
  brothers' door check, sound. Not drawn yet: 0x33 (invisible on the SNES
  too), 0x72 / 0xC8 fairies, 0xB2 (good bee), 0xE9 (potion shop helper),
  0xF3 / 0xF5 / 0xF7.
- [x] 30.2 **The smiths and the frog** (`Smiths.lua`, was a stub; 29.4
  research). Frog (subtype 2) from Dark World area 0x69's list (gone once
  reunited or while someone follows): hops, blocks, 0xE1 -> follower 7. A
  world switch toggles 7 <-> 8 (the dwarf). Follower drawn by
  Tagalong_Draw's GBA tables (kTagalongDmaAndFlags 0x17EA0E, SprXY
  0x17EA3E, Offs 0x17EBFE, Pals 0x17EC3A) from the follower sheet; trail as
  OldMan.lua. Smithy 0x121: SpritePrep (+2, -3; the partner at +0x2C when
  reunited; both state 5 while tempering), Smithy_Main's hammer phases
  (kSmithy_Gfx / _B, hop at phase 1, spark at 3 with kSmithySpark tables),
  states 0-11 as the GBA (the dash into him -> 0xE4, where the SNES listened
  for the hammer), 0xE0 with follower 8 and Link's y low byte < 0xC2 -> the
  partner (subtype 3, kReturningSmithy_Delay / Dir / Xvel / Yvel, his tile
  from follower 8's sheet by kReturningSmithy_Dma) walks home -> 0xE3,
  reunited (progress.smith & 0x20); 0xD8 / 0xD9 / 0xDA / 0xDD (10 Rupees,
  no sword, & 0x80) / 0xE2 until Link has been in another area
  (flag_overworld_area_did_change) / 0xDE -> receipt 2 (Tempered Sword,
  level 3). The spark and the walking partner are not barriers (Barrier29
  `noBarrier`). OURS: talk = R facing; dash = our dash touching his box;
  the dumb barrier 0x31 is not spawned; the area-change flag is RAM (not
  saved); no sound.
- [x] 30.3 **The flute** (`Flute.lua`, was a stub). Digging it up stays
  Tools.lua's (given at once; AncillaAdd_DugUpFlute's item and receipt
  message are not ported: an r26a test digs and moves on). Item slot 15 =
  "flute" (GBA byte 0x2E: 2 / 3). LinkItem_Flute: 128-frame countdown;
  flute 2 in Kakariko's rectangle (0x1CF..0x230, 0x760..0x7E0) -> the
  weathervane: 0x280 + 128 + 10 frames held, then the GBA's 0x0808FD34
  (literals read at import: map16 0xE21 / E22 / E21 / E23 at 0xC3E / C40 /
  C42 / CBE, E25 at 0xCC2, each through 0x0808F5C0 which also blanks the BG1
  overlay cells (0x01E3) -- the rooster is on BG1 on the GBA --, and map16
  0xE24's lower row on BG2 / upper row on BG1 at 0xCC0),
  save_ow_event_info[0x18] |= 0x20 (re-applied on area load), 96 frames
  later flute 3. Flute 3 in the Light World: 48 frames, then the flute menu
  (Module0E_0A / the GBA's 0x080B2F18) on the Light World map (OwMap zoomed
  out): spots from 0x16EED0 (x_lo / x_hi / y_lo / y_hi, 9 each), left / up
  -1, right / down +1 with wrap, 9 spots once save_ow_event_info[0x47] &
  0x20 (the GBA's 0x020022C7 test: Turtle Rock open), B cancels, A / R
  chooses; landing from the GBA's 20-byte entries 0x150B18 (screen +0,
  Link y +10, Link x +12): all 8 land in their areas (3, 0x16, 0x18, 0x2C,
  0x2F, 0x30, 0x3B, 0x3F). The stump kid (0x2E, DW 0x6A,
  kFluteAardvark_Dmd 0x174CEC, Gfx / Delay 0x174C44 / 0x174C58): 0xE5 ->
  0xE6 + the shovel / 0xE7; 0xE8; 0xE9, the tune -> his dance -> stump
  (progress.stumpy). The father hears it (0xA2). OURS: no sound / tune pose;
  debris, the birds and Link's ride not drawn (hold times are the
  cartridge's; ride 48 frames, landing instant); markers are numbered boxes;
  the stump kid's byte rules use our separate shovel / flute bytes (GBA
  routine not traced); the LW flute boy (0x2E subtype 0, 0x2A) not spawned.
- [ ] 30.4 Grove light beams / pull poses: not started.

Tests: all 38 `zelda_alttp_*` files pass (new `zelda_alttp_r30_test`, 75
checks); audits 304/304 rooms, 80/80 overworld areas (r26b `run.sh audit`,
AUDIT=rooms|ow, store rebuilt).


## Round 31 (2026-11-12)

No route or bot runs: unit tests and short in-place scenes with real keys
(`tests/zelda_alttp_r31_test.lua`, 69 checks) and a LÖVE scene
(`r31/harness/s31.lua`, shots `r31/shots/r31_*.png`, montages
`montage1.png` / `montage2.png`). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r31/` (the r30 kit: `run.sh`,
`run1.sh`, `probe.sh`, `runtests.sh`, one mkdir lock; probes `lua31/s*.lua`;
`msgscan.py` lists a Thumb range's message / receipt calls with their
numbers). **cacheVersion 35** (data.t.spr31, data.t.games31 new; data.t.dmap
was an empty stub). Sprites31 and Games31 are in `ExtractA27.EXTRA`.

Messages: the GBA numbers are the SNES ones + 3 (`G:showMessage` takes the
SNES number; GBA-only messages are passed as n - 3). The GBA's message call
is 0x080C9164 (Sprite_ShowSolicitedMessage) / 0x080C9564
(ShowMessageUnconditional); the routine table is 0x174138, the SpritePrep
table 0x17451C; the init-flag tables have 249 entries (types up to 0xF8:
flags3 0x22788F + t, flags4 0x227988 + t).

- [x] 31.1 **The last invisible sprites** (`Sprites31.lua`). Re-running the
  r30 scan (`r31/harness/undrawn.lua`, every entrance) now lists nothing.
  - 0x72: the pond draws nothing (cartridge); the fairy it raises is
    FaerieQueen_Draw (LW: X / Y / char / flags / big 0x176748..0x1767A8, DW:
    kFaerieQueen_Dmd 0x1766A8) with its sparkles (kWishPond_X / Y 0x1765BC /
    0x1765C4). Room 0x115 now runs the **happiness pond** (Sprite_HappinessPond,
    GBA table 0x1765CC): 0x89, the cost choice (0x176688 / 0x17668C), paid into
    the pond, 0x94 + the luck (0x176690 / 0x176698) under 100, at 100 the fairy,
    0x95, bomb (0x96) or arrow (0x97) upgrade, 0x98 at the top.
  - 0xC8 the fountain fairy: kBigFaerie_Dmd (0x1762C8), 0x15A, the cloud
    homes in (target link_y + 8), hearts filler, then she blinks away (the
    slot-0 delay_aux2 "bug" applies: she is slot 0 in all three fountains).
  - 0xB2 the good bee: becomes a golden bee 0x79 (head_dir 1, kSpawnBee_InitVel
    0x174A28) unless a bottle holds one; netted -> bottle value 8 (Items27
    "goldbee").
  - 0xE9 the potion shop: the assistant (kShopkeeper_Dmd, 0x4D / 0x4E, hearts
    after talking) and SpritePrep_PotionShop's three cauldrons (0x17D328 /
    0x17D340 / 0x17D360; 60 / 160 / 120 Rupees, 0x4F / 0x17C / 0x50, receipts
    0x2F / 0x30 / 0x2E).
  - 0x33 the rupee pull (room 0x101): draws nothing; R facing up touching it
    -> RupeePull_SpawnPrize (0x174D30) by the kill / hurt counters.
  - The GBA's own sprites: 0xF3 (Link's house: SpritePrep 0x081115C0 kills
    itself and puts the riddle carvings, 0x17D5EC / 0x17D590, by the riddle
    count), 0xF5 (room 0x88: the Palace of the Four Sword's door keeper,
    20 Rupees, 0x1A5 or -- with the Four Swords flags -- 0x1A6 and he leaves),
    0xF7 (room 0x11F: the riddle carver; SpritePrep 0x081140B8 by riddle /
    basket / net / Four Swords flag; states 0x17D8D0; riddles 0x17D900; the
    basket, the right / wrong answer, the last prize).
  OURS: progress.fsCleared stands for the GBA's Four Swords save flags (not
  linked), so 0xF5 / 0xF7 stay in their first state in a normal game; netting
  the riddle answers into the basket is not ported (progress.riddle.basket is
  the hook); the hearts filler is 1 health a frame; the cloud's / fairy's
  sparkle garnishes and the palette filters are not drawn; the pond's
  {number} words are not printed; talking = R in front (Townsfolk30's rule).
- [x] 31.2 **Minigames and shops** (`Games31.lua`).
  - The shooting gallery (0x111): ArcheryGame_Host's states (0x85 / 0x86 /
    0x87 / 0x88), 20 Rupees, five arrows, the arrows-left display (0x1767F2..),
    SpritePrep_ArrowGame's seven targets (0x1767C0.., own hit boxes 0x1C /
    0x15), wall wrap after 16 frames, the streak prize (0x17683A), 99 after five
    hits on one target; arrows are not spent in a game and the bow shoots
    nothing outside one.
  - The super bomb: R at the ware (100 Rupees, 0x11A) -> follower 13; R
    outdoors sets it down (count 3, first tick 0xBB, then 62); Link near it
    after 64 frames picks it up; at 0 with Link away: 9 blasts (Ancilla3A)
    and the destructibles at the centre; **only it opens the pyramid's crack**
    (screen 0x5B: plain bombs are refused, Overworld_RevealSecret).
  - The brothers' door: an opened door of index 8+ in the odd room -> 0x130.
  - The Light World flute boy (area 0x2A): kFluteBoy_Dmd 0x174C6C, quavers,
    Link within 48 -> held 176 frames, fades, gone; absent with the flute.
  - The dug-up flute: AncillaAdd_DugUpFlute / Ancilla36_Flute -- pops out at
    (0x490, 0xA8A), bounces (0x18 / 0x10 / 0x0A), Link touches it -> receipt
    0x14. Tools.lua calls `Games31.dugUpFlute`; the r26a test now waits for
    the flute to rest and walks Link onto it. Menu.RECEIPT_SLOT[0x14] is now
    {15, 2} (value 1 is a blank icon on the GBA).
  OURS: no gallery prize picture / sounds; the super bomb is drawn as an
  unlit bomb (follower 13's sheet not traced), its HUD countdown is not drawn;
  the flute boy's fade is a flicker; the flute is drawn as its menu icon.
- [x] 31.3 **The dungeon map** (`DungeonMap.lua`, was a stub): L in a palace.
  Cartridge data: kDungMap_FloorLayout (pointers 0x16FCF4), kDungMap_Tiles
  (0x16FDE8), the room pictures Tab23 (0x16F132, 744 GBA BG words), floors
  Tab5 (0x16F702), remaps Tab21 / 22, boss room / floor Tab25 / 28 (0x16F020 /
  0x16F03C). Seen rooms (progress.dmapSeen) or the map show rooms, the compass
  the boss room on its floor; Link's marker at his room + (x & 0x1E0) >> 5.
  OURS: rooms are shaded blocks shaped by their Tab23 quarters (the map's own
  tileset / palettes not traced), one floor at a time (up / down also for two
  floors), plain-text labels; map / compass ownership is read from the item
  log (a receipt in a room of that palace).
- [ ] 31.4 Grove light beams / pull poses, flute-playing pose, bird ride
  visuals: not started.

Found, not fixed: a test / harness teleport across a room's x 256 line starts
the quadrant scroll, which later lands Link back (the r31 test lets it land,
then places him again).

Tests: all 39 `zelda_alttp_*` files pass (new `zelda_alttp_r31_test`, 69
checks; r26a's flute check now picks the flute up); audits 304/304 rooms,
80/80 overworld areas (r26b `run.sh audit`, AUDIT=rooms|ow, store rebuilt).

## Round 32 (2026-11-12)

No route or bot runs: unit tests and short in-place scenes with real keys
(`tests/zelda_alttp_r32_test.lua`, 31 checks) and a LOVE scene
(`r32/harness/s32.lua`; shots `r32/shots/r32_*.png`, montages
`montage_grove.png`, `montage_vane_bomb.png`). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r32/` (the r31 kit; `all.txt` =
every sound call site of the cartridge with its function and id, built by
`py/idx.py`; `seq_dis.txt` / `noteon_dis.txt` = the sound driver's sequencer
and note-on). **cacheVersion 36** (data.t.sfx filled, data.t.cut32 new,
data.t.grove.beams).

- [~] 32.1 **Sound effects** (`Sfx.lua`, was a stub). Nothing is heard yet.
  KEY FINDING: ALttP's sounds are NOT M4A. The MusicPlayer2000 song table
  (0x3C3BBC, 545 songs, `Extract.readMusic`, played by `Audio.lua`) is the
  Four Swords half's bank: its song n is not the ALttP bank's sound n (the
  ALttP bank's 19 / 20 / 21 are one sword swing in three variants, the M4A
  songs 19 / 20 / 21 are unrelated; many ids name empty M4A songs). So the
  engine's M4A synth cannot play them -- and `Audio.lua`'s ALttP music
  (song 399 + SNES number) very likely plays Four Swords music too (not
  checked further).
  The chain, ported as data and read at import: call site (`movs rN, #id`
  before a bl to one of the wrappers 0x0809E43C / 0x0809E49C / 0x080C19F8
  (id in r1) / 0x080C1A8C / 0x080CF018 / 0x080CF0AC / 0x080CF140 (id in r1) /
  0x080CF1D4, or 0x0812A324 itself) -> the u32 table 0x198C94 (133 ids: low
  16 = sound number, bits 16-23 = channel, bit 27 = variant: +1 / +2 for the
  2nd / 3rd start in a frame, counter 0x03000105; bits 25 / 28 = channel
  priority rules, not ported) -> command 1 (channel, sub-bank 0, number) into
  the ring 0x030003C0 (0x0812C73C) -> 0x0812CC24 runs it through the handler
  table 0x198EC8 -> 0x0812C494 looks it up in the bank 0x198C30 (+0x0C:
  sub-bank offsets; sub-bank 0 = 0x199340 = the 142 sound effects, u16
  offsets; sub-bank 1 = 0x19A540) -> 0x0812C548 / 0x0812BD50 start the
  sequence. Sequence format (0x0812BE54): 00-5F note with the last length /
  velocity; 60-BF note + varlen length (0x0812C30C) + velocity; C0 rest,
  C1 rest + varlen; Dx slide (2 bytes, +1 if x & 1); C2-FF by table
  0x0812BF98 (C2 instrument, C7 instrument set, C3 / C4 / CA / E0-E3 /
  E5-E7 / E9 / EA one byte, E4 varlen tempo, F0 jump / F4 call (u16 from the
  sub-bank base), F8 open track (track + u16), FF return / end). All 142
  sequences walk to their end with these lengths (import check).
  Events (data.t.sfx.ev, each read from its call site's movs): sword swing
  by level (0x16809E), spin charge 0x19, spin / medallion 0x6B, tink 0x71,
  clink 0x09, hurt 0x07, item get 0x7A, Master Sword 0x0F, heart piece 0x47,
  pickups (kAbsorptionSfx 0x173034: heart 0x70, rupee 0x74, key 0x12),
  debris (0x1720BC), explosion 0x29, bomb lands 0x0D, lift 0x6C, throw 0x6E,
  arrow in a wall 0x1C, hookshot 0x28, cape 0x14 / 0x15, error 0x40, jump
  0x04, land 0x0D, pit 0x0E, swim 0x3A, enemy hit 0x53. Wired (G:sfx, the
  update / hurtLink / getItem / Actors.takeDamage wrappers): swing, spin
  charge, spin, tink, hurt, item get / Master Sword / heart piece, pickups,
  enemy hit; `game.sfxLog` keeps the last 64 starts, `Sfx.backend(game,
  sound, channel, id)` is the seam a synthesizer plugs into.
  NOT DONE -- what a synthesizer needs (next round, ALttP-local module):
  the voice side of the driver: instrument lookup 0x0812AB30 (records in
  the bank's +4 table: type 0x00 direct, 0x10 key range, 0x11 per-key
  table (drums), 0x12 key split by upper bound; +2 / +4 u16 offsets to the
  wave / envelope), voice allocation 0x0812BC64 (pool by type via
  0x198EAC), note-on 0x0812B7B4 (pitch 0x081361C0, envelope setup
  0x0812AE7C from instrument byte 7, slide from Dx), the per-frame track
  step (0x0812BE54, tempo +0x30 from E4, 0x96 = 150 ticks a unit), the
  sample format behind bank +8 (0x2163FC) and the mixer (not located; GB
  channels for type 3?). The format is close to NITRO's SSEQ/SBNK
  (src/audio/NitroAudio.lua may be a starting point). Also not wired yet:
  explosion, lift / throw, arrows, doors, chests, text blip, menu, enemy
  death, low health (their GBA call sites are not matched yet; `all.txt`
  lists every site).
- [x] 32.2 **Grove light beams and pull poses** (`Grove.lua`). Beams =
  subtype 2 (MasterSword_SpawnLightBeam / Sprite_MasterSword_LightBeam;
  the GBA's table 0x175058: Xv0..3 / Yv0..3 / Gfx0 / Gfx2 / Flags0 / Flags2):
  four from (x - 4, y + 4) at states 2 -> 3 (set 0) and 3 -> 4 (set 1), and
  from the light fountain by kMasterSword_NumLightBeams[cnt >> 5]; a moving
  beam leaves a 3-frame copy every 4th frame and counts its life only then;
  drawn as SpriteDraw_SingleLarge. Spawns fail at 16 live sprites (OURS:
  slot order not modelled). Poses: +0x1809 = link_unk_master_sword 0x0A /
  0x0B -> LinkOam row 0x17 at step pose - 1 (G:linkPose wrapper).
- [x] 32.3 **Weathervane debris** (`Cutscenes32.lua`): Ancilla37's 12 wood
  pieces from the GBA's tables 0x1803E0 / 0x1803EC / 0x1803F8 / 0x180404 /
  0x180410, chars 0x18041C (0x8E / 0x8F, flags 0x3C), started with the blast
  (0x280 + 128 frames into Flute.lua's vane), MoveY / X / Z with ONE shared
  set of sub-pixels (one ancilla slot), picture flip every other frame,
  gone when z wraps under 0.
- [x] 32.4 **Super bomb picture and HUD count** (`Cutscenes32.lua`): follower
  13 drawn by Tagalong_Draw (body only, char 0x22 / dma7, kTagalongDraw
  tables from Smiths' import, sheet 0x58 + (v >> 11) per the GBA's
  0x0812F9A8; palette frame & 7 at count 1) -- replaces Games31's unlit
  Bomb_Draw. HUD: the GBA's Hud_SuperBombIndicator 0x080AB04C writes
  kDungFloorIndicator_Gfx0 / Gfx1 (0x16E024 / 0x16E03A) at HUD word 120 / 121
  (+32 for the lower row; the literal 0x0200B270 read at import), ones
  [n - 1, 0 -> 9], tens [n - 1, 0 -> blank].
- [ ] 32.5 Not done: the flute-playing pose (the SNES has none --
  LinkItem_Flute sets no pose bit, kPlayerOam_Tab2 / Tab3 have no flute
  entry; the GBA routine was not located, so nothing is drawn), the bird
  (cutscene duck 0x38 and the travel bird 0x27: motion tables found at
  0x1803CA.. / 0x1803D0 (Draw_Char 0x0C / 0x00 / 0x02, Flags 0x22 / 0x2E,
  Y, X) / 0x1803DC (DmaStuffs) / 0x18041E (intro tabs), but its picture is
  DMA'd by flag_travel_bird from a source not traced), the dungeon map's
  real tiles (31.3 still shaded blocks), the x 256 teleport / quadrant
  scroll note from r31 (not looked at).

Tests: all 40 `zelda_alttp_*` files pass (new `zelda_alttp_r32_test`, 31
checks; r31's cacheVersion pin relaxed to 35+); audits 304/304 rooms, 80/80
overworld areas (r26b `run.sh audit`, AUDIT=rooms|ow, store rebuilt).

## Round 33 (2026-11-12)

No route or bot runs: unit tests, headless renders and one in-place LOVE scene
(`r33/harness/s33.lua`: the grove pull, and the live LOVE sound path with the
master volume at 0). Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r33/`
(the r32 kit; `py/dz.py` / `py/hx.py` / `py/callers.py` disassemble / dump /
find callers; `lua/p1.lua` renders every sound effect, `lua/p2.lua` every song,
`lua/p4.lua` writes the WAVs in `r33/wav/`). **cacheVersion 37**
(`assets/generated/alttp/snd.bin` new, `data.t.sfx.entMusic` new).

- [x] 33.1 **The ALttP sound driver** (`AlttpSynth.lua`, new). Sound effects
  and music are now HEARD. The importer copies the driver's bank out of the
  ROM (`AlttpSynth.image`: 0x198C30..0x203290 = tables, instrument sets,
  envelopes, the 3 sample sub-banks (48 + 9 PCM samples), plus the 34 songs
  from 0x2163FC; 580 KB, nothing in the repo). Ported from the cartridge:
  - bank pointers +0 samples / +4 instrument sets / +8 songs / +0xC sfx
    sub-banks / +0x10 set -> sample sub-bank / +0x14 song info / +0x18 sfx
    info (an info list maps C7 n to an instrument set);
  - sample header {length, rate (48000 / 44100 / 10512), loop start, loop
    end (0 = none)}, signed 8-bit data from +0x10;
  - instrument records (0x0812AB30): {type, flags, u16 sample, u16 envelope,
    release, root key}; type 0x10 key range (drums: key forced to 0x30, pan
    from the table), 0x11 per-key sample (envelope 0x198EB4), 0x12 key split;
    every instrument in the bank is PCM (type 0; no GB channels are used);
  - pitch (0x0812AE7C): table 0x199040 [key + 0x30 - root], 0x8000 = the
    sample's own rate; mix step = pitch / 0x8000 x rate / 10512 (0x0812B328);
  - envelope (0x0812AEEC): (u16 frames, s16 level) pairs, a negative count
    holds the last pair; release (not key-on): x (release byte + 0xE6) / 512
    a frame; volume (0x0812B01C) = velocity x player 0x34 / 0x40 / 0x41 x
    track E0 / 0x4E x envelope, x 3 / 512; pan 0..0x7F (0x0812A964);
  - sequencer (0x0812BE54): ticks x 150, tempo E4 (default 150 = a tick a
    frame); notes 00-5F / 60-BF, rests C0 / C1, slide Dx (0x0812B194 +
    note-on), C2 instrument, C3 pan, C4 priority, C5 / C6 hold, C7 set, C8 /
    C9 note-wait (the sfx default: a note also waits its length), E0 volume,
    E1 / E2 bend / range, E4 tempo, E5-E7 vibrato (sine 0x199220), E8 slide
    off, E9 transpose, EA player volume, F0 / F4 / FF jump / call / return,
    F8 open a track (copies the parent's set, instrument, pan, volumes);
  - the cartridge mixes 176 samples a frame at 10512 Hz (timer 0 reload
    0xF9C4); ours renders 2x (21024 Hz) with linear interpolation.
  Checks: all 142 effects of sub-bank 0 render, none silent, 133 end by
  themselves (9 are loops: rain / wind style ambients), the swing is 25
  frames and decays; all 34 songs sound in their first 10 s.
  OURS: one engine per stream (music; each effect rendered once into a
  SoundData) instead of the cartridge's single pool of 7 voices shared by
  music and effects (so effects never steal music voices); voice stealing is
  "free, else quietest released, else lowest priority" (0x0812BC64 not
  ported); the echo buffer (track +0x4C / E3, ring 0x03000C1C) and the CA /
  note hooks are not modelled; the final 16 -> 8 bit conversion (a RAM
  routine) is replaced by a fixed gain (1 / 20000 effects, 1 / 26000
  music); sub-bank 1 (54 effects, sample sub-bank 1) is not used by the
  cartridge's id table and does not render (its instrument set reads past
  sample sub-bank 1's 9 samples).
- [x] 33.2 **Music** (`Audio.lua`, rewritten). Before: M4A song 399 + SNES
  number = the Four Swords half's bank -- wrong songs; that path is gone.
  Now: songs stream from the ALttP driver through a LOVE QueueableSource
  (main thread, 6 x 4-frame buffers, `A:update`). Music ids are the GBA's
  own u16 (RAM 0x03002230 + 0xA3C; 0xFFFF / 0xFFF2 keep, 0xFFF1.. fade ->
  OURS: stop) and song = table 0x198C50 [id] (0x0812A044). Matched from the
  cartridge's code: overworld 0x080732FC (LW 7, DW 0x0E, area & 0x3F == 0:
  LW Lost Woods 0x0B / DW 0x0F, areas 0x80 / 0x2A / 0x0F keep), Kakariko 8
  while the progress indicator <= 2 (0x08072748), rooms = the entrance
  table's +0x28 (0x0806A7F8; 3 skipped while the indicator <= 1), the Master
  Sword pull 0x19 (0x080D46B4, the pull start). Found, not wired: the fairy
  queen 0x14 (0x080DFF0E). The port's older SNES-numbered calls go through
  `A.SNES` (castle 9 and sanctuary 0x0A from the entrances).
  OURS: the Lost Woods' "keep" flag (0x02002300 & 0x40) is read as "the
  Master Sword is held"; the progress indicator is derived from the port's
  flags (AlttpSound.progressIndicator); the bunny (SNES 4) is not matched
  and plays the Dark World song; fades are cuts; music ids for bosses,
  victory, crystals, the ending, the title / file select are not wired
  (the GBA ids appear at the A3C writers listed by `py/mus.py`).
- [x] 33.3 **More sound events** (`Sfx.lua` + `AlttpSound.lua`): explosion
  (the bomb's explosion counter), lift (`G:startLift`), throw
  (`G:throwCarried`), chest (0x0808469C, the chest opener that tests tile
  attributes 0x58.. / 0x63: id 0x10), the item menu (0x080AA522 id 0x44 on
  `G:openMenu`; its second sound 0x45 = the cursor, read, not wired). The
  backend (`Sfx.backend` = `AlttpSound.backend`): render once per sound
  number, one static source per channel (a new start stops the channel's
  old sound, as the GBA's player per channel does), `options.sfxVol`.
  NOT FOUND this round: door open (0x7B is the most common id in the room
  tag / door code but unproven), arrow shot (only the arrow-in-wall 0x1C is
  matched), enemy death (0x080C4208's 0x53 / 0x56 / 0x57 are the damage
  sound by class, not the death), low-health beep, text: ALttP has no
  per-letter blip.
- [x] 33.4 **The yellow line over the grove** (r32 `montage_grove.png`, last
  frame): a DRAWING BUG. It was the message box's border for one frame:
  message 112 (Sahasrahla's telepathy) starts with the window command 2
  (borderless), which was only read when the text reached it. `Text.open`
  now applies a window command that comes before the first character, so
  the border never shows (`r33/shots/r33_grove_456.png`).
- [ ] 33.5 The x 256 teleport / quadrant scroll from r31: not looked at.

Tests: all 41 `zelda_alttp_*` files pass (new `zelda_alttp_r33_test`, 40
checks; r32's cacheVersion pin relaxed to 36+); audits 304/304 rooms, 80/80
overworld areas (r26b `run.sh audit`, AUDIT=rooms|ow, store copied from r33).

## Round 34 (2026-11-12)

No route or bot runs: unit tests, headless scenes and two in-place LOVE scenes
(`r34/harness/s34.lua`: the live music path with the master volume at 0 --
the Eastern Palace song, the Armos room's boss song, the 40-frame fade, the
low-health beep, the fanfare; `s34b.lua`: the travel bird). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r34/` (the r33 kit; `py/mus34.py`
lists every writer of the music id with its code, `py/cg.py` builds a call
graph, `py/anc*.py` find callers by argument; `lua/p34.lua` writes the WAVs in
`r34/wav/`; shots `r34/shots/r34_*.png`, `montage_bird.png`).
**cacheVersion 38** (`data.t.mus34`, `data.t.bird34`).

- [x] 34.1 **Music for the remaining events** (`Music34.lua`, new; installed
  from ExtractA27's EXTRA list). Every GBA music id was found at its writer of
  RAM 0x03002230 + 0xA3C and matched to the SNES routine by shape (same
  tests, tables, calls), and is read at import from that writer's `movs`
  (a wrong ROM fails the import check). The GBA numbering is its own (only 3
  equals the SNES's): 1 title (0x0812E47C, the title module), 3 rain /
  curfew (0x080F3882), 5 palace, 6 Zelda's rescue (0x080F3EB0, after her
  message), 9 castle (Zelda follows: 0x080F4336; room 2), 0x0A sanctuary
  (room 0x12), 0x0C bunny (0x080736C0; `A.SNES[4]` now 0x0C), 0x0D boss (the
  GBA's boss-room list 0x14CB74, 17 rooms incl. Agahnim's 0x20, with a live
  sprite on screen -- Dungeon_PlayMusicIfDefeated 0x0806D2A0; room 7 by
  Dungeon_SetBossMusicUnorthodox; a boss's own start 0x08070C74), 0x0E Dark
  World, 0x0F Skull Woods / Dark Death Mountain, 0x11 the crystal (0x08118844:
  the crystal's ancilla once no song plays), 0x12 Agahnim's theme (rooms 0x10 /
  0x30), 0x15 minigames, 0x16 the Kakariko chase, 0x17 the fanfare (receipt of
  0x20 / 0x37-0x39 at 0x080ACE44; Ganon's death 0x080CE856), 0x18 mirror warp,
  0x1A file select (GameOver_Finalize 0x080B1020), 0x1B Ganon's reveal
  (Agahnim 2's bat, 0x080DA928), 0x1C Ganon's room (SpritePrep_Ganon
  0x0810A440), 0x1D Ganon's fight (state 0, delay 32: 0x0810A620), 0x1E the
  Triforce room (Module19 step 4, 0x0806B58C), 0x1F the ending (step 11,
  0x0806B74C), 0x20 the staff roll (EndSequence_32 0x080B8A48; 0x21 for an
  end-sequence index past 0x27 -- a second table at 0x08170ADC, unused).
  Wired: the room rules after doorways / stairs / falls (with the GBA's
  pendant gate for rooms 7 / 0x17, the 0x8A fade, the 0xEC skip), Zelda's
  message / follower, the uncle's curfew, the pendants' and crystal's
  fanfare then the crystal song, Agahnim 2's bat, Ganon (room, fight, win),
  the Triforce room / ending / staff roll (Ending27's phases), the title
  (and, OURS, the front end), the mirror warp (0x18, then the destination's
  rule 0x08073644: bunny without the pearl, DDM / Skull Woods 0x0F), game
  over (fade). Not wired: 0x16 (the chase, needs BoltGuard), 0x14 the fairy
  queen (the fountain's entrance song covers it), 0x18 for Agahnim 1's warp
  (the port leaves the room at once), 0x1A at game over (no continue menu).
- [x] 34.2 **Fades** (`Audio.lua`): the request codes are the cartridge's
  (0x08068502): 0xFFF1 fades the music player's volume linearly to 0 over
  0x28 = 40 frames (0x0812A0A0 -> driver sub-op 2, 0x0812C5F0), then stops;
  0xFFF2 / 0xFFF3 step the player volume 4 a frame to 0x30 / back to 0x80
  (0x08129FAC / 0x08129FF8). OURS: applied to the stream's LOVE volume (heard
  at once, not after the 24 queued frames). `A:idle()` = the engine has
  nothing left (0x0812A0B8's -1).
- [x] 34.3 **More sounds** (ids read at their call sites): door / shutter open
  0x37 and shutter close 0x38 (OperateShutterDoors 0x080810AC; key doors
  0x08085D08; not while a room loads), arrow 0x1B and "no arrows" 0x40
  (LinkItem_Bow 0x080A1D1C, after AncillaAdd_Arrow 0x080AD3CC, which itself
  plays nothing), enemy killed 0x54 (the GBA's damage routine 0x080C2160 --
  found by its 0xFD / 0xFB tests -- health <= 0, not type 0x1B), low health
  0x50 (Hud_RefillLogic 0x080A7228: health < table 0x16B645 [max >> 3] = 9 /
  17 / 25, timer 0x20: a beep every 32 frames), rupee count 0x73 (every 8th
  counted frame; OURS: the port adds rupees at once, the count runs on its
  own counter), stairs 0x34 / 0x32 (Module07_08_00 0x0806DDF4; OURS: 0x5E /
  0x38 sound up, 0x5F / 0x39 down), the menu cursor 0x45 (r33's id). Also
  identified, not wired: magic refill 0x26, hearts refill 0x6F, the puzzle
  chime 0x7B (the SNES's sfx2 0x1B: room tags, the most common id).
- [x] 34.4 **The travel bird** (`Bird34.lua`, new). Its picture was traced:
  the GBA's LoadItemGFXIntoWRAM4BPPBuffer tail (0x0812FDEC) decompresses sprite
  sheet 0x58 and copies its first 0x400 bytes to RAM 0x0200A8C0 (the SNES's
  0x7EB540 that flag_travel_bird DMAs from), so a wing frame is sheet 0x58's
  tiles t, t+1, t+16, t+17 with t = DmaStuffs[j] / 16; tables 0x1803D0..
  (Draw_Char {0x0C, 0, 2}, flags {0x22, 0x2E, 0x2E}, Y {0, 12, 20}, X {0, -9,
  -9}, DmaStuffs {0, 0x20, 0x40, 0xE0}). Ancilla27_Duck ported: the take-off
  (0x78 frames at the screen's left edge - 16, x speed 56, a wing frame every
  4th frame, touch -> Link carried, the bird climbs, off-screen at 0x130 ->
  the flute menu) replaces Flute.lua's 48-frame ride; the landing
  (AddBirdTravelSomething: z -51, z speed 40, wings held 48 px before, Link
  let go at his x). OURS: Link carried is drawn with the port's LinkOam pieces
  at row 0x23 (SNES pose_for_item 1 = 0x1D + the GBA's 6 extra rows, as the
  tablet's 0x1E -> 0x24), the collision is the bird's x reaching Link's - 8,
  no shadows / flap sound / after-drop blink. r30's flute test now waits for
  the bird (400 frames).
- [ ] 34.5 Not done: the flute-playing pose (no GBA routine found; the SNES
  has none), the dungeon map's real tiles / palette (31.3: still shaded
  blocks), the cutscene duck (Ancilla38) picture.
- [x] 34.6 The x 256 teleport / quadrant scroll (r31): it cannot happen in
  normal play. Every in-room jump of Link's position either re-derives the
  quadrant (stairs: Game.lua 526 / 542; falls: Dungeons26 539; entrances and
  starting points: Interior.new) or stays in the quadrant (the pit's return
  to link_x/y_prev, the wall master's carry, the hookshot's repel, the pull
  switch) -- walking always crosses 256 through I:edge, which starts the
  cartridge's scroll. Only a harness teleport skips it; no change.

WAVs (for checking the id matching by ear): `r34/wav/music_*_idXX.wav`
(boss, fanfare, crystal, Triforce, ending, staff, Ganon's room / fight /
reveal, title, bunny, file select, rescue, Agahnim, dark mountain) and
`r34/wav/sfx_*_idXX.wav` (door, shutter, arrow, enemy killed, low health,
rupee count, stairs).

Tests: all 42 `zelda_alttp_*` files pass (new `zelda_alttp_r34_test`, 49
checks; r30's flute check waits for the bird); audits 304/304 rooms, 80/80
overworld areas (r26b `run.sh audit`, AUDIT=rooms|ow, store copied from r34).

## Round 35 (2026-11-12)

The user's rule for this round: game data comes from the import, none of it
ships. Source keeps ROM offsets, patterns and logic; data values taken from
the game (tables from the ROM, the disassembly or the decomp, and values
written by hand from them) are read from the player's ROM at import and
cached. No route or bot runs: tests, the room / overworld audits and one
in-place LÖVE scene (`r35/harness/s35.lua`). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r35/` (the r34 kit; `py/scan.py`,
`py/cands.py`, `py/near.py` flag literal tables and search the ROM for them
by value near each module's own offsets; `py/f.py` / `py/hx.py` find / dump;
`batch/*.py` + `py/mig.py` apply a migration; `lua/cmp35.lua` extracts the
new tables and compares them with the old literals kept in scratch
`lua/old35.lua` / `old35d.lua`; `py/audit.py` writes the audit).
**cacheVersion 39** (`data.t.rt35`).

- [x] 35.1 **Audit**: `r35/data_audit.txt` lists every literal table left
  in `src/zelda/alttp` (file, lines, what it is, verdict, status), the
  migrated ones, what was not located, the code-immediate values, the
  import spot checks, tests, docs and the shared `src/zelda` files. The
  line drawn: a table the cartridge keeps as data (a decomp `static const
  k...` table, a GBA table found by value) is game data; a value the
  cartridge has as a code immediate (a compare, a call argument) is logic
  like the rest of the port, flagged borderline where it is content
  (messages, prices).
- [x] 35.2 **RomTables.lua / RomTablesSpec.lua** (new): 67 small tables
  read at import into `data.t.rt35` (offset, count, kind, base, row width /
  columns / keys / inversion / scale; every one range-checked, the import
  fails loudly otherwise) and poured into the modules' live tables when the
  cache loads (`RT.bind` from `Data.load`); `RT.get(name)` hands a module
  its table at load, so the code indexes it as before; `RT.onBind(fn)`
  builds tables from another module's import. Migrated: Guard (kSoldierB_*,
  kSoldier_HeadDirs), Tools (kRodAnimDelays, kFireRod_X/Y, the ice rod's,
  kBoomerang_Tab6/7/X0/Y0, the hookshot's), Doors (HandleNudging tabs,
  kStaircaseTab2), Carry (lift query by facing, gloves, kLiftTab2), Dash
  (kPlayerActionBoxRun), Drops (kLink_Lift_tab, inverted), DesertPalace
  (kMovingWall_Tab1), Dungeons26 (kFallHolePitDirs / Dirs2), Escape
  (kOverworld_DrawBadWeather X/Y, << 8 words on the GBA), Games31 (super
  bomb explosion, bounce), Gear (kBottleList / kPotionList), Mech27
  (kTurnOn/OffWater), Items27 (kCaneSpark_Magic, Somaria platform
  velocities / poof / junction masks, Witch_Draw rows -- the GBA's chars, 0x70
  above the port's layout, the cover probes), Sprites (rupee shimmer,
  kOffsToShadowGivenDir), Shop (shop rooms, wares' x), Townsfolk30 (Thief's
  head = the guards' head tables), Agahnim (levitate frames). Built at bind:
  `Menu.RECEIPT_SLOT` (from kMemoryLocationToGiveItemTo / kValueToGiveItemTo,
  `data.t.gear`), `Audio.ID` / `Audio.SNES` / fade / low volume (from
  Music34's import, six new call sites: the overworld rule 0x080732FC's
  light / dark / Skull Woods / Lost Woods songs, the Master Sword 0x080D46B8,
  the fairy queen 0x080DFA34), DungeonMap layout sizes (25 bytes x the floors
  word's two nibbles), `G.START` (exit 0 + (8, 48): the same point).
  Music34's 30-id EXPECT table is gone (structural check: ids 1..0x22, the
  sites that share a song agree).
- [x] 35.3 **Before / after**: every migrated table equals the literal it
  replaced (`cmp35.lua`), except where the GBA's own copy differs from the
  SNES values the port had -- now the GBA's: kStaircaseTab2[10] 12 -> 16,
  kPotionList[3] 0xFF -> 0x51, kTurnOnWater_Tab1[3] -1 -> 0, the mirror's
  receipt value 1 -> 2.
- [x] 35.4 **Tests** no longer carry copies: r33 (overworld songs from the
  import), r34 (music / sound ids: distinct, in range, Audio bound to the
  import; low-health table rising; 17 boss rooms), r27b_f (maiden messages
  = the imported kCrystalMaiden_Msgs, one new crystal bit each), r30 (each
  townsperson says a cartridge message, ten different), r31 (cauldrons:
  paid, filled, three different potions; FLOOR_BYTES), logic (synthetic
  animTab3). Borderline, kept: single message ids as assertions, entrance /
  room numbers that set up a scene, dispatch type lists, small fixtures.
- [ ] 35.5 **Not migrated** (listed in the audit): the front end's OBJ
  layouts and BG words (FrontEnd.lua, ~1,840 numbers off a scratch
  interpreter run; the GBA builds that OAM at run time and its frame data
  was not found -- the largest block left), Somaria platform DMD,
  kByrnaDelays, kShovelAnimDelay, the item strip blocks (kIntro_LoadGfx_Tab),
  kSword/ShieldTypeToGfxOffs, Moldorm tail spacing, BigRock's gloves map,
  the kStaircaseTab4-derived walk, throw times, the action query. Code
  immediates left as code: ~70 message call sites + 25 MSG constants,
  prices, the palace openings' map16 writes, map16 compares, new-file
  stats; 180 small import spot checks (1-6 values each).
- [ ] 35.6 Polish (dungeon map tiles, opening rain / night palette): not
  started this round.

Tests: all 42 `zelda_alttp_*` files pass (2,814 checks); audits 304/304
rooms, 80/80 overworld areas (r26b `run.sh audit`, AUDIT=rooms|ow, store
copied from r35); `r35/harness/s35.lua` (start point, music ids, a palace
room) runs clean.

## Round 36 (2026-11-12)

The data cleanup left by round 35, under the same rule (game data comes from
the import; source keeps addresses, shapes and logic). No route or bot runs:
tests, the room / overworld audits and one in-place LOVE scene
(`r36/harness/s36.lua`: the four front-end screens rendered from the new
import, `r36/shots/r36_*.png`, `montage_front.png`). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r36/` (`py/oamtrace.py` = the r13
interpreter with OAM / object / ROM-read tracing and per-frame dumps,
`py/findmatch.py` finds the frames equal to a layout, `py/msgsites.py` lists
every message call with its r1, `py/blimm.py` / `py/xr.py` find code by
immediates / literal loads, `lua/fr1.lua` / `lua/strip.lua` / `lua/cmp36.lua`
compare the new imports with the old literals, `py/audit.py` writes
`data_audit.txt`). **cacheVersion 40** (`alttp_front.lua` gains `layouts`,
`data.t.strip36`, 14 more RomTables specs).

- [x] 36.1 **The front end's sprite layouts** (`FrontRun.lua`, new;
  FrontEnd.lua's ~1,840 numbers gone). Traced: the screens are objects of
  the shared object system (type 6, kind 0x3B: panels, name plates, hearts,
  the fairy cursor, buttons, cards), each placed relative to its parent
  (+0x54) by its own code with code-immediate offsets and animated (+0x21);
  the OAM builder 0x08000CFC draws them from the frame lists at 0x0862F52C
  ([set +0x1B] -> [frame +0x21] -> a count and 5-byte pieces {x, y,
  shape / size / flips / tile high, tile, palette}) with the object's
  position (+0x32 / +0x36), tile base, palette and priority. Because the
  positions are computed by many small pieces of code, the import runs that
  code: FrontRun is a Thumb interpreter (the r13 scratch one in Lua: BIOS
  LZ77 / CpuSet / CpuFastSet / Div, DMA at once, a stepping VCOUNT, the
  VBlank handler 0x0800B701 at the wait 0x0800B550, blank EEPROM through
  0x08135DC4 / 0x08135E74, the two IRAM ARM routines -- object loop and
  overlap list -- in Lua). It boots from AgbMain, presses START (frame 290),
  A (424), A (500), START (520), A (540), A (960) and keeps the OAM and the
  display registers at frames 419 / 484 / 820 / 1150 (CHOOSE A FILE empty,
  ENTER A NAME, the used file, CHOOSE A GAME; `FrontExtract.PLAN`, ours:
  chosen so each snapshot is the animation phase shown since round 13). The
  result equals the old literals row for row and word for word; the blend
  (12/16) and the unselected card's dim (4/16) now come from BLDCNT /
  BLDALPHA. 1,150 frames = 14.4 M Thumb instructions: 0.6 s (JIT), 3.6 s
  (JIT off). The import fails if a screen is missing, on the wrong task
  (8 / 6) or nearly empty. OURS kept: which layers the port draws (BG1 holds
  the cartridge's own-font letters) and the name screen's map slots.
- [x] 36.2 **The item strip** (TL.STRIP / W.ITEM_BLOCKS, kIntro_LoadGfx_Tab,
  gone). The GBA's LoadItemGFXIntoWRAM4BPPBuffer is 0x0812E554 (strip at RAM
  0x02008800, the base of kLinkDmaSources6 / 7 at 0x0812D096): it
  decompresses sprite sheets (0x08135B90, pointers 0x0822B324) and copies runs
  of tiles (CpuFastSet 0x08135B78). `FrontRun.itemStrip` runs it with both
  helpers recorded and skipped -> strip tile -> {sheet, tile}
  (`data.t.strip36`, 24 copies, 104 tiles); `Weapon.itemTile` looks it up.
  CHANGE: the hammer's tiles 5-6 (lower 12-13) are sheet 0 tiles 32-33 /
  48-49 on the GBA (the old list continued linearly into 16-17 = the rod's
  lower halves), the net's 13 / 27 likewise (sheet 96 tile 32 / 48).
- [x] 36.3 **The small tables** (RomTablesSpec, round 36 block):
  kByrnaDelays 0x1690EF (LinkItem_CaneOfByrna 0x080A3040; 3 bytes, index 3
  reads the next table: 4 instead of 32, unused as the item ends on that
  step), kShovelAnimDelay / 2 0x1690D6 / 0x1690DC (CHANGE: the GBA digs with
  {7, 12, 10}, the port had the SNES {7, 18, 16}), sword / shield picture
  tiles 0x22BA48 / 0x22BA52 (u16 halfwords into the decompressed sheet; tile
  = / 16, the shield + 64 in the port's sheet 0x5E), the Somaria platform
  DMD 0x17D510 (rows {x, y, char | flags << 8, size}), BigRock's gloves =
  kGetBestActionToPerformOnTile_a [_b [attr & 15]] (_b 0x16826F), the
  cauldron's prices (rows of 8 at 0x17D378, u16 at +6). Moldorm's look-backs
  are code on the GBA (`subs r1, #n` at 0x080D98B4 / D8DC / D916 / D962).
  Re-classified: Carry THROW_TIMES and Escape FRONT are port timings / probes
  (no cartridge table). Found, NOT used: the GBA kStaircaseTab4 is at
  0x14CAFA = {36, 36, 57, 58} (s16), so Doors.MOVED needs the GBA scroll's
  step count (not traced; left).
- [x] 36.4 **Code immediates** (RomTables kinds `imm` and `msg`). `imm`
  reads `movs / cmp / adds / subs rN, #imm8` (a movs + `lsls #s` < 16
  scales; `lsls #24` casts are not scales) or an `ldr rN, [pc]` literal;
  `msg` checks a `bl` to the message routines 0x080C9164 / 0x080C9564 and
  walks back to what sets r1 (movs / ldr, through lsls / adds), minus 3.
  A site of the wrong form fails the import. Migrated: shop prices of wares
  7-12 (`bl 0x080AA868; subs r0, #price`; the fire shield's 500 is its
  wrapper's movs + lsls at 0x0810F3AA), 38 message numbers (flute boy and
  his father, the fat fairy's intro / refusal / choice / drop, Zelda's
  telepathy, the uncle, the priest, Ganon, the ending's two, bee / fairy /
  no bottle, the witch, the Magic Bat, Sahasrahla and his wife, the shop's
  have / bottle / full / poor, the bomb shop, the pond's, the cauldron's).
  Not done (audit C): ~47 message names reached through other routines,
  the bee's price (table 0x17D0BC, entry not tied down), the new-file stats
  (the interpreter stops in the game task on a hardware wait at 0x080683A8).
- [ ] 36.5 Polish (dungeon map tiles, opening rain / night palette): not
  started.

Tests: all 43 `zelda_alttp_*` files pass (new `zelda_alttp_r36_test`, 31
checks; front_test checks the imported layouts; r25 checks the glove rule
against the imported tables); audits 304/304 rooms, 80/80 overworld areas
(r26b `run.sh audit`, store copied from r36). Audit:
`r36/data_audit.txt` (A specs, A2 round-36 migrations, C what is left and
why, F value changes).

## Round 37 (2026-11-12)

The rest of the data cleanup (round 36's audit section C), under the same
rule (game data comes from the import; source keeps addresses, shapes and
logic). No route or bot runs: tests, the room / overworld audits and one
in-place LÖVE scene (`r37/harness/s37.lua`: the Dark World shop with the
bee, `r37/shots/r37_shop.png`; the hammer and the bug net swung in four
directions, `r37/shots/montage_tools37.png`). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r37/` (the r36 kit;
`py/c95c0.py` resolves the register a call passes for any list of
routine:register pairs, `py/argat.py` is its walk, `py/immfind.py` finds the
instructions that load a number in a code range, `py/u16find.py` finds u16
runs, `py/lits.py` finds literal-pool loads, `py/sprtab.py` names the sprite
routine of an address (table 0x174138), `py/msgtext.py` prints the text of
every message spec's call, `lua/rt37.lua` runs `RomTables.extract` alone and
prints the specs, `py/audit.py` + `py/audit_tail.py` write `data_audit.txt`).
**cacheVersion 41**.

- [x] 37.1 **Message entry points** (`RomTables.lua`). The message number is
  now found by `RT.regAt`, a walk back from the call that stops at every
  Thumb instruction writing the register (loads, ALU ops, hi-register moves,
  pop / ldmia, a call for r0-r3) and at any branch -- r36's walk stepped over
  loads. `RT.MSG_CALLS` maps six routines to their register: 0x080C9164 /
  0x080C9564 (r1), 0x080C94F4 (r1, the solicited form with a wait),
  0x080E1058 (r1, the room-sprite wrapper), 0x080C95C0 (r0, the dialogue
  start) and 0x080AF4FC (r0, the player's text: the big key door, no magic,
  the Triforce room). A table spec can carry `ref = { {site, delta} }`: the
  code at site must load the table's address from its literal pool, so each
  table is tied to the routine that reads it.
- [x] 37.2 **84 more message numbers** read at import (122 in all), every
  one at the call of the routine that shows it: Agahnim (4), Ganon (2), the
  story (big key, no magic, Triforce, blind maiden, Thieves' Town light,
  uncle, old man), the archery keeper (4), Npc (6), the smiths (13),
  Sprites31 (14: the happiness pond, the cauldron, the Four Sword keeper,
  the riddle carver), Townsfolk30 (22), FatFairy (9), and 8 numbers a
  routine keeps in a register before a shared call (kind `imm`: cukeman,
  quarrelling brothers, cauldron, keeper, carver). Message tables, each with
  its reader: the tablets (0x1797C8), the Desert book (0x1796E0), the bomb
  guy (0x17645C), the innkeeper (0x175FDC), the clerk's hello (0x17D080),
  kShopKeeper_GiveItemMsgs (0x17D0CC), and the follower's text triggers
  (0x17EC56: rows {y, x, bit, message, follower}, rooms 0x17EC48, first rows
  0x17ED06) for Zelda's three. FIXES: r36's `msg.fairy` had taken four calls
  of other states (their numbers equalled FatFairy's GBA-numbered literals,
  so nothing showed wrong); Ganon's two messages were the thieves' house
  man's and the Triforce's -- now his own (his fight's state 0, 0x0810A664;
  the dark phase, 0x08109134).
- [x] 37.3 **The bee's price**: the GBA's ware 13 (0x17D034 [13] =
  0x0810F3B8) calls the bottle ware 0x0810EDB4 with index 0; that charges
  s16 0x17D0BC [index * 4] (read at 0x0810EE20) and gives byte 0x17D0C4
  [index * 4] (the bee). The shop scene shows the cartridge's own price
  sprites drawing the same one-digit price. CHANGE: the GBA's price, not the
  SNES's.
- [x] 37.4 **The doors' walk with the scroll** (`Doors.MOVED`, built at
  bind). DungeonTransition_ScrollRoom (0x0806C6F0) scrolls the camera by the
  step table 0x14CAF2 until it reaches the bound set at the transition's
  start (vertical 0x14CE14 at 0x0806FBD0, horizontal 0x14CE0C at
  0x0806F6E2); Link moves the step on every frame from the counter's
  kStaircaseTab4 value (0x14CAFA) on. The GBA's 240 x 160 view scrolls less
  vertically than the SNES's and its table is lowered to match. CHANGE: the
  vertical and right walks (the port had assumed a 64-step scroll for every
  direction); it only moves the landing probe -- audits unchanged.
- [x] 37.5 **The new-file stats** (`Hud.newStats`): the new game routine
  0x0806BDB8 (called at 0x0812D9B6 once the file is made) fills the save
  area 0x02002000 with one value (`movs r4` 0x0806BDBE) and stores one
  `movs r1` (0x0806BDE8) to the health capacity and the health (0x0200234C /
  D, checked). Equal to the port's; keys 0xFF (outside a dungeon) stays port
  logic -- an entrance sets it.
- [x] 37.6 Also read: the smiths' tempering price, the bomb guy's big bag
  price and count (kind `imm`).
- [x] 37.7 **The hammer and the bug net** (r36's strip-tile fix) rendered
  in place in four directions (`montage_tools37.png`): heads and handles
  whole, no rod tiles.
- [ ] 37.8 Left (audit C): five message literals (Sahasrahla's boots pair,
  the old man's revert, the fortune teller's "no", the carver's fallback),
  two 20-rupee fees as code.
- [ ] 37.9 Polish not done: the dungeon map's real tiles / palette (leads:
  its submodule table 0x16F058; submodule 1 0x080B38BC decompresses the
  frame map 0x083BFDC4 to BG map 0x0600F000; the charset and palette
  loaders were not tied down); the opening's night palette (the GBA's
  blend registers come from mirrors written in VBlank 0x08068A8A; the
  intro's setting was not found).

Value changes are listed in `r37/data_audit.txt` section F. Tests: all 44
`zelda_alttp_*` files pass (new `zelda_alttp_r37_test`, 26 checks; r29's
fairy checks use FatFairy.MSG; 2,877 checks); audits 304/304 rooms, 80/80
overworld areas (r26b `run.sh audit`, store copied from r37).

## Round 38 (2026-11-12)

The first checkpoint-chained route check with real input (key events in the
real app, `r38/real`: the repo's main.lua booted into alttp, scenes drive
`love.keypressed`; never from the title: a new file starts in bed through
`newGame{skipTitle, noFrontEnd}` + `startChosen`), the last data literals,
and the user's "Link walks into the left walls" report. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r38/` (the r25 route kit with
r38 paths; `waitfree.sh` waits for any other LOVE process, every run script
calls it; `real/harness/ck38.lua` writes `out/ck_r38_*.txt` checkpoints after
chosen route steps; `real/harness/scene_r38.lua` new file -> route,
`scene_r38ck.lua` checkpoint -> route (a later `H.new` is the real
save-by-menu + relaunch); `harness/seg_*.lua` legs; `harness/wallsweep.lua`,
`walk60.lua`, `dbgpit.lua`, `words.lua` probes; `harness_head` + `head/` =
the committed code for before / after comparisons). **cacheVersion 42**.

- [x] 38.1 **Route check** (real input). Passed: bed -> lamp -> out of the
  house in the rain -> the castle's hole bush -> the passage, the uncle's
  sword -> courtyard bushes, the big door -> hall -> 0x72 key -> 0x82 / 0x81
  / 0x71 -> 0x70 -> 0x80, the ball-and-chain guard, big key, Zelda -> throne
  room, the shelf -> the sewers 0x41 ... 0x11 -> 0x02 (the lever) -> the
  sanctuary, the priest -> save by menu, relaunch, continue in the
  sanctuary -> Kakariko (elder's wife, sweeping lady, trough boy) ->
  Sahasrahla (0x32 / 0x33, the map mark) -> up the Eastern Palace's stairs
  -> C9 pot switch, shutters -> B9 cannonball track climbed. Not passed: B9
  -> A9 (the bot, at 8 hearts' worth of health from the castle, died to
  cannonballs; game over -> C9 as the cartridge does), and from the old
  palace checkpoints D8's Popos killed the bot (r23 passed the same leg with
  6 spins to 1 now; the spin itself is unchanged, checked against the
  committed code). Sahasrahla after the pendant checked from the
  `r38_sasha` checkpoint (pendant set by the scene): the boots message read
  from the import, the boots, then the ice rod hint.
  Blockers found:
  * **FIXED (game)**: a hurting pit (kDungeonPitsHurtPlayer) at <= 8 health
    left Link standing at 0 hearts for good -- `Dungeons26.pitFrame` now ends
    in the game over as RecoverPositionAfterDrowning's `if
    (!link_health_current)` -> module 18 (0x72's east pit, reached by the
    bot at 4 health).
  * route bot (scratch only): its planners walked over pits (attribute 0x20,
    ported in round 26 after the bot was written) -- `bot.lua` / `plan.lua`
    keep off them; the sanctuary lever (0x04) is pulled the cartridge's way
    (hold R + down, Traps27 / PullSwitch_HandleDownPulling; the bot still
    pressed R once, as before round 27).
  * harness only: room checkpoints loaded through `enterRoom(4)` +
    `loadRoom` can lose the castle's opened doors (`no plan` from 0x80 /
    0x41); the overworld / sanctuary / Sahasrahla / palace-entrance ones
    load fine. The real app's `H.shot` (host canvas) is blank in zoomed
    real-app frames -- `RH.winshot` shows the window (the room is drawn).
  Checkpoints for the next round (`r38/out/ck_r38_*.txt`): house_out,
  sword, hall, cell, zelda, sewers, sanct, kak, sasha, ep_in (C9).
- [x] 38.2 **"Link walks into the left walls"** (the user's screenshot: the
  Eastern Palace's entrance room C9, west wing, Link against the left wall,
  his body over the wall's inner strip and his shield over the bricks).
  Reproduced with real keys from `ck_r38_ep_in`: Link stops at x 104. Cause:
  NOT a regression -- the committed code (before rounds 35-37) stops him at
  the same pixel; the cartridge's own data puts him there: the strip is
  tile 0xAD (h-flipped on the right), attribute 0 (floor) in the GBA's
  dungeon attribute table (0x15E114 [0xAD]), the wall 0xA4 next to it is
  attribute 4, and the GBA's tile detection is the SNES's (kDetectTiles
  tab0..3 at 0x16812C = {8, 24, 0, 15} ...: x + 0 going left, x + 15 going
  right). The same 8 px overlap happens on the right wall (x 136); facing
  left, Link's shield is drawn beyond x + 0, which makes the left side read
  as "inside the wall". Checked: a stale cache cannot run silently (RT.bind
  asserts every spec; the cacheVersion bump re-imports). New
  `zelda_alttp_walls_test`: 670 indoor walks (22 castle / sewer rooms, 10
  palace rooms, both levels, four directions, 90 frames held) and 784
  overworld walks (15 Light World areas): none ends with the cartridge's
  probe points for the move on a blocked cell (ledge jumps and layer
  passages excluded), plus the C9 stops at 104 / 136 and the table entries.
- [x] 38.3 **Data cleanup** (round 37's audit C, all done; `r38/data_audit_r38.txt`):
  `msg.sashaBoots` (Sasha_Idle's u16 table 0x176428, tied to 0x080DE524),
  `msg.sasha38` (his last branch, NEW behaviour: with boots and the ice rod,
  all pendants -> Lost Woods / "can't grip the hilt" by the sword byte, else
  the other sages' relatives -- the port gave the ice rod hint forever),
  `msg.oldManRevert` (`cmp r2, #0xA0` in Follower_HandleTrigger 0x08115DDA),
  `fee20` (the shared fee routine 0x080DE0DC: `movs #20` / `cmp #19`, the
  storytellers and the Four Sword keeper). The fortune teller's "no": the
  GBA (0x080D3A7C, choice byte != 0 -> state 2) shows NO message -- the
  port's 0xF5 was the SNES's, removed. The riddle carver's fallback uses the
  imported table's entry.
- [ ] 38.4 Polish (dungeon map tiles / palette, the intro night palette):
  not started (route + the walls report took the round). Leads unchanged:
  submodule 0 0x080B3770 (CpuSet 0x08135B7C into 0x0600E000 / 0x0600F000,
  then 0x0812ECDC / 0x08133304 / 0x08130260 / 0x08130384 / 0x08133644),
  submodule 1 0x080B38BC (LZ 0x083BFDC4 -> 0x0600F000; tables 0x16EFA4 /
  0x16EF84 / 0x16EF94 / 0x16EF58).

Tests: all 46 `zelda_alttp_*` files pass (new `zelda_alttp_r38_test`, 20
checks: no literals left, the specs, Sahasrahla's five branches, the old man's
trigger, the fee, the pit game over; new `zelda_alttp_walls_test`, 7
checks); audits 304/304 rooms, 80/80 overworld areas (r26b `run.sh audit`,
store copied from r38).

## Round 39 (2026-11-13)

The user's wall report checked on the DRAWING side (round 38 had shown the
collision is the cartridge's), and the route with real input from
`ck_r38_ep_in` through the Eastern Palace to the Desert Palace's door.
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r39/` (the r38 kit
with r39 paths; `harness/wall39.lua` the C9 wall walk, `harness/ep39.lua`
C9 -> pendant chain (`START19=d8` starts mid-palace), `harness/ow39.lua`
Sahasrahla -> library -> plaque -> Desert Palace, `harness/dbga9*.lua`,
`popo39.lua` probes; `py/linkoam.py` = the cartridge's view of a room with
Link (GBA room loader + the GBA's LinkOam_Main run in the r13 Thumb
interpreter), `py/sbs.py` the side by side; `real/harness/ck38.lua` writes
the new `out/ck_r39_*.txt`). **cacheVersion 42** (no game code changed).

- [x] 39.1 **"Link inside the left wall" -- the drawing matches the
  cartridge.** Traced on the GBA: LinkOam_Main is 0x080A3EE0; it takes
  xcoord = link_x - BG2HOFS (0x16C4 - 0x952) and ycoord = link_y - BG2VOFS
  (0x16C0 - 0x958) with no constant (0x080A3F40-6C); the head is drawn at
  kLinkSpriteBodys' (x, y) from there (0x080A5648), the body at (xcoord,
  ycoord + 8) (0x080A577C), the shield at (shieldX, shieldY + ycoord -
  (z + 1)) (0x080A50B0-C0). The BG side: the dungeon VBlank (0x08068794)
  writes BG2HOFS / BG1HOFS from the mirrors 0xA2C / 0xA2E, which the room
  scroll sets from 0x952 plus the shake (0x0806B8F2, 0x0806B3F0); the room
  maps go to VRAM by whole screen blocks (0x0807922E ...) -- so neither Link
  nor the BG has an offset. Run, not only read: `py/linkoam.py` loads C9
  with the GBA's room loader, sets Link at the stop (104, 360, facing left)
  and the camera the port uses (0, 292), calls 0x080A3EE0 and renders the
  BGs by priority plus the OAM it wrote: head (105, 68), body (104, 76),
  shield (96, 72), shadow (103 / 111, 85) -- the port's pieces exactly, and
  (104, 67) / (104, 76) / (96, 70) in the walking step 3. The side by side
  (`r39/shots/r39_wall_sbs_push.png`, `_stand.png`: the real app's frame at
  the stop | the cartridge's | the differing pixels) differs only where the
  composite outlines the shield and shadow OAMs (their pictures are not
  decoded there): 0 BG pixels differ. So on the GBA, too, Link's body
  overlaps the wall's inner strip (tile 0xAD, floor) by 8 px and his shield
  overlaps the bricks when he faces left. The user's screenshot is the
  zoomed view (zoom level 1, `Zoom.lua`): the view is centred on the
  cartridge camera and both layers use the same origin, so it changes the
  scale only. New `zelda_alttp_r39_test` (12 checks): the GBA instructions
  above (the subtraction, the +0x800 body pair, the shield's - (z + 1), the
  VBlank / scroll mirrors) and the port's head / body / shield offsets for
  every direction and walk step against the ROM's own tables.
- [x] 39.2 **Route check, real input** (full health at checkpoint loads).
  Passed: `ck_r38_ep_in` -> C9 pot switch, shutters -> B9 cannonball track
  climbed -> A9 -> A9 switch -> A8 Stalfos, west doorway -> A9 lower -> AA
  -> BA switch, key pot -> BA's key door -> B9 upper ring -> B8 (Popos,
  Stalfos, green Eyegore) -> pot switch -> big key chest -> A9 big chest
  (the Bow) -> falling Stalfos, arrow pots -> big-key door -> 99 (Eyegore's
  key) -> stair mask -> DA (pot switch) -> D9 (switch under the Eyegores,
  arrows) -> D8 (Stalfos, Popos, three red Eyegores with arrows) -> C8
  Armos Knights -> heart container (24 -> 32) -> pendant of Courage, out ->
  Sahasrahla (Pegasus Boots, dash) -> library (dash into the bookcase, the
  Book of Mudora) -> desert plaque (Book, prayer, statues) -> into the
  Desert Palace (entrance 9, room 0x84). Blockers, all in the route bot
  (scratch), none in the game:
  * A9's floor switch is walled in by its heart pot (0x70 at 432,320) and a
    pot above it (0x71 at 448,304): the bot lifted the heart pots only when
    hurt; now it always lifts them (`epleg20.lua` heal "force").
  * D8's Popos took the bot's 24 health (r38's "D8's Popos killed the bot";
    the sword kills them in one swing, checked with `popo39.lua`): the
    fight helper (`fight21.lua`) predicted a Popo moving at its stored
    velocity every frame; Sprite_4E_Popo moves only in ai 2 and then on one
    frame in B + 1 (B = 7 / 15) -- the prediction now does the same. D8
    then passes at 24 -> 20 and the Armos at 20 -> 16. The north Popo phase
    also stops at 2,500 frames (was 5,000) and leaves stragglers to the
    reds' phase.
  Checkpoints (`r39/out/ck_r39_*.txt`): b9, b9top, a9, b8, bigkey, bow, da,
  d8, c8, heart, pendant, boots, book, plaque, dp_in. Note: Link reached the
  desert at 8 / 32 health (overworld enemies on the way), the next leg
  should start with a refill.
- [ ] 39.3 Polish (the dungeon map's tiles / palette, the intro's night
  palette): not started; leads as in 38.4.

Tests: all 47 `zelda_alttp_*` files pass (new `zelda_alttp_r39_test`, 12
checks; `zelda_alttp_walls_test` 7 checks); audits 304/304 rooms
(graphics too), 80/80 overworld areas (r26b `run.sh audit`, the r38 / r39
store, cacheVersion 42).

## Round 40 (2026-11-13)

The route with real input from `ck_r39_dp_in` (inside the Desert Palace)
through the Desert Palace, Death Mountain and into the Tower of Hera, and
the dungeon map's real art. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r40/` (the r39 kit with r40
paths; `harness/seg40.lua` chains legs after a checkpoint load with full
health (`LEGS=file.lua:STAGE,...`, not a game change); `harness/hera40.lua`
the Death Mountain -> Hera leg (stages HA / HB); `harness/hera_geo.lua` the
mountain's flood fill (both worlds, ledge hops, the route to the warp tile,
the mirror spot); probes `dpc85*.lua`, `dpc73*.lua`, `dp53.lua`,
`dpout.lua`, `hera77.lua`, `hera87.lua`, `herafit.lua`, `dwprobe.lua`;
`harness/dmap40.lua` the map screen in place; `py/dmap.py` runs the GBA's
dungeon map submodules (table 0x16F058) in the r13 Thumb interpreter and
dumps VRAM / palette, `py/dmrender.py` renders the dump, `py/dmsub.py`
times each loader; `real/harness/scene_r38ck.lua` TRACE lines now carry the
locks, the room-clear flag and the death puffs). **cacheVersion 43**.

- [x] 40.1 **Route check, real input** (the real app's key events; full
  health at each checkpoint load). Passed:
  * Desert Palace: 0x84 west corridor pot -> 0x74 -> 0x73 torch key (dash)
    -> 0x85 compass room (key door, Popos, compass) -> 0x75 big key ->
    back through 0x85 -> 0x73 pot room (pot switch) -> the big chest, the
    **Power Glove** -> 0x83 out the west door -> the rocks -> the back door
    (entrance 0x0C) -> 0x63 block, pot key -> 0x53 SW (Popos) -> pot key ->
    0x43 pot key, lamp on four torches, the wall slides -> big key door ->
    **Lanmolas** (57 swings) -> heart container (32 -> 40) -> **Pendant of
    Power**, out by the back door (the entrance Link used last).
    Harness aid: `HPFLOOR=8` (health never below one heart, every absorbed
    point counted): 424 health absorbed over the palace (A-B 80, C-D 72,
    E-F 272) -- the bot's fights in 0x84 / 0x74 / 0x53 lose hearts to the
    Leevers, Popos and Beamos; without the floor it died in 0x84 (game
    over -> continue, as the cartridge does).
  * Death Mountain (no health aid): the back door's plateau (lift the
    rocks, hop the ledges) -> the desert -> south road -> Kakariko -> the
    mountain foot -> the big rock -> the old man's dark cave (0xF0, he
    follows) -> 0xF1 -> out on the mountain -> his house: the **Magic
    Mirror**.
  * Tower of Hera: up the mountain's paths (they loop west by the cave
    exit and back east) -> the **warp tile** (2304,368) -> the Dark World as
    the **bunny** -> (2104,352) -> the **mirror** -> Spectacle Rock's top in
    the Light World -> the Hera door (entrance 0x33, room 0x77) -> 0x77's
    crystal switch -> the left stairs to 0x87 -> 0x87's crystal switch ->
    the **small key** (sprite 0xE4) inside the peg ring.
  Not passed (bot, not game): 0x87's big key chest. The way is 0x77's NW
  key door -> stairs down to 0x87 NW -> its shutter (tag 1) -> NE -> SE;
  from the left stairs' landing in 0x77 Link is ringed by pegs and the
  bot's planner sees the other rooms' pegs in their load state, not the
  live crystal state, so it finds no way. Then the Moon Pearl (0x27's big
  chest), 0x17, Moldorm (0x07), the third pendant and the Master Sword
  pedestal were not reached.
  Checkpoints (`r40/out/`): `ck_r40_dp_key`, `_dp_bigkey`, `_dp_glove`,
  `_dp_back`, `_dp_boss`, `_dp_done`, `ck_oldman_cave_r40`,
  `ck_oldman_out_r40`, `ck_mirror_r40`, `ck_r40_dw_land` (Dark World,
  bunny), `ck_r40_hera_in`, `ck_r40_hera_b1`, `ck_r40_hera_b1key`.
  Blockers, all in the route bot (scratch), none in the game:
  * stage C restarted in 0x85 with `B.lastFightRoom` still 0x85 from stage
    B, so the Popos that shut the north shutter behind Link were never
    fought: clear them when no plan is left (`dp24.lua`);
  * 0x73's pot room: the goal spot (y 360..380) let the bot stop above the
    one-way doorway's rows (384..399); y 372..380 puts Link in them and the
    quadrant transition takes him through;
  * 0x53 SW: the shutter opens a few frames after the last Popo dies (the
    death puff counts, Sprite_CheckIfScreenIsClear), the bot checked after a
    fixed 30 frames: it now waits for the shutter;
  * after the pendant Link leaves by the back door (0x0C; round 24's
    checkpoint run had loaded entrance 9): `dm25.lua` leaves its plateau
    through the planner, which now lifts the rocks and **hops ledges** in
    their direction (`bot.lua` `B.hops`, also over the cliff face below a
    diagonal ledge), and steps off the doorstep first;
  * the bunny cuts / lifts nothing (plan around the Dark World's bushes);
    the mirror portal Link lands on crosses back when touched again (the
    planner keeps the cartridge's boxes apart: `Actors.linkBox` /
    `Actors.hitbox`; Link steps off it left and up before planning);
  * the planner sees the live crystal pegs in the current room (`plan.lua`
    `B.liveGrid`: Dungeons26 flips the pegs' attributes on the live room
    only); the crystal-switch loop (`hera40.lua` `goWithSwitches`).
- [x] 40.2 **The dungeon map's own art** (`DungeonMap.lua`, `M.ART`, read
  at import into `data.t.dmap.art`). Traced by running the GBA's map
  submodules (0x080B3770 / 0x080B38BC / 0x080B3E84 / 0x080B4B04 / 0x080B4C64)
  in the interpreter: BG chars at char base 0x06004000 -- 0x0812FB90 LZ77s
  chrA[lang] (0x0822B9C8) to 0x06007000 (the frame), 0x0812ECDC LZ77s
  chrB[lang] (0x0822B9AC) to 0x06008000 (grid, box, floor labels) and the
  three sheets of sprite set 0x80 | palace (0x0822B624 [set * 4] + 1..3,
  pointers 0x0822B324) to 0x06008800 / 9000 / 9800 (the room pictures,
  kDungMap_Tab23's words); the frame map LZ77 0x083BFDC4 -> BG3 0x0600F000;
  palette rows 0-1 by 0x08130384 (0xCAA = 1: 8 runs of 4 colours, 0x20
  apart, from the blob 0x3BD758 + 0x610 + 2 * u16 0x0822BC0C[1]), rows 2-7 by
  0x08133304 (the blob + 0x1700); the floor box words 0x16EFD8 / 0x16EFE0
  (bottom row = top | v-flip), the label digits 0x16EFE6, 'B' / 'F' from the
  literal pools at 0x080B42BC / 0x080B4310, the rooms panel's grid from the
  literals at 0x080B3E70 / 78 / 7C. The screen now shows the cartridge's
  frame, grid, floor boxes with their labels and room pictures (seen rooms
  palette row 2, mapped-only row 3, as the cartridge's dim rooms), two
  floors at once. Compared with the cartridge's own composite
  (`r40/out/dmap_dp.png` vs `r40/shots/dmap40_r40_dp_back_map.png`).
  OURS: the BG scroll offsets (boxes at tile column 16, rooms 2 x 2 tiles
  from the box corner), the left panel's floor list (text, not the
  cartridge's floor boxes and gradient), the markers.
- [ ] 40.3 Not done: Hera after B1's small key (above), the pedestal; the
  intro's night palette (leads as in 38.4).
- Seen, not followed up: on the frame the old man's 0x9D box opens
  (`real/shots/dm40_c02_mirror.png`) the box is a yellow outline over the
  house with no text yet; the next frames read normally.

Tests: all 48 `zelda_alttp_*` files pass (new `zelda_alttp_r40_test`, 17
checks: the map art in the cache, the frame / chars / sheets / palette /
box words, the laid-out screen with and without the map; 2,933 checks in
all). `zelda_alttp_r21_test` had been printing 2 failures since round 36
(its bow-block checks ran before the import binds the cartridge's strip
map; the runner's rc stayed 0): the checks now run after the load, and its
"rod / hammer not listed" check is gone (round 36 loads them). Audits
304/304 rooms (graphics too), 80/80 overworld areas (r26b `AUDIT=rooms|ow
run.sh audit`, the r40 store, cacheVersion 43; note: a bare `run.sh audit`
is `AUDIT=mains` and rewrites `mains.txt` without the three hand-guessed
mains of 0x065 / 0x129 / 0x12B -- restored from r26a's copy).

## Round 41 (2026-11-13)

The Tower of Hera with real input from `ck_r40_hera_b1key`, the two visual
reports from round 40, and one Hera game fix. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r41/` (the r40 kit with r41
paths; `harness/hera41.lua` the Hera leg, stages C (big key), D (Moon
Pearl), E (Moldorm), F (heart, pendant); `harness/pegplan41.lua` the
crystal-switch search; `harness/moldorm41.lua` a Moldorm fight bot (not
reached); probes `hera41p.lua`, `roommap41.lua` (ASCII room maps,
`out/map_<room>.txt`), `nw87.lua`, `reach27.lua`, `ov27.lua`, `ov17.lua`,
`p17.lua`, `walk17.lua`, `mir41*.lua`, `anim41.lua`; `py/fbar.py` the GBA
Firebar routine). **cacheVersion 44**.

- [x] 41.1 **Route check, real input** (the real app's key events,
  `real/runreal.sh r38ck` with `SEG=seg40.lua LEGS=hera41.lua:C`; health
  floor `HPFLOOR=8`, 24 health absorbed in the real-input run). Passed:
  `ck_r40_hera_b1key` (0x87 SW, small key) -> 0x87's switch -> up to 0x77,
  0x77's south switch -> the NW key door -> down to 0x87 NW -> the NW
  switch behind its pots (one pot lifted, one thrown onto the switch) ->
  the shutter -> 0x87 NE, its switch -> down the corridor to the SE
  quarter -> two pots for magic (0 -> 128) -> the **lamp on the four
  torches** (room tag 0x3E, RoomTag_TorchPuzzleChest: the hidden chest
  appears) -> the **big key** (`ck_r41_hera_bigkey`, real input). The
  cartridge's mechanics on the way all worked as the cartridge's: the
  barrier state global per palace, the switch hit by a thrown pot, the
  torch chest, the torch timers (one torch went out before the fourth was
  lit in the harness run; the bot relit it).
  Not passed (bot, harness only): the Moon Pearl. The way is the
  cartridge's (traced): 0x77 -> 0x31 (the big key door) -> 0x27 (pots on
  the way) -> up to 0x17 -> 0x17's 0x3B star (room tag 0x35, overlay 9)
  opens holes at x 240-271 y 144-168 -> the drop lands on the foot of
  0x27's chest island (in 0x27 neither star state joins the island to the
  floor: overlay 10 has holes at y 176-200, overlay 11 at y 112-136). The
  bot reached the star and the overlay changed, but 0x17's four Hardhat
  Beetles (32 health, the sword throws Link back 32) and its bumpers kept
  pushing Link into the old holes (drop to 0x27, up the stairs: 0x17
  reloads without the star's holes, as on the cartridge). Moldorm (0x07),
  the pendant, the pedestal and Agahnim were not reached. The planner
  does reach 0x07 from 0x27 in both overlays once the pots are lifted.
  Bot work (scratch, none of it game code):
  * `plan.lua`: every room loads with the live barrier state
    (`r.pegState`, Dungeons26's loadRoom flips 0x66 / 0x67); `B.pegOverride`;
    `opts.start` (plan from another spot); the live-room copy re-opens the
    locks and re-lifts planned pots (it had brought the closed shutter
    back: NE of 0x87 looked unreachable); big key doors open in a plan only
    with the big key; pits are every Dungeons26.PIT attribute (0x20 and
    0xB0-0xBD; the planner had walked over the 0xBx holes); `B.pitDrops`
    (a step onto a pit drops to the header's hole room, hdr[10], plane
    hdr[8] & 3); `B.pitMargin`; `B.fightPitMargin` (no fight step towards
    a hole).
  * `pegplan41.lua`: BFS over (spot, barrier state); the switches from the
    room sprite lists (0x1E), a hit = a node with the state flipped.
  * `hera41.lua`: pots on the planned way lifted first, a pot under a
    switch's hit spot lifted, "unstick" steps when knocked onto a switch.
- [x] 41.2 **Game fix: the Firebar balls** (`Hera.lua`). Traced on the GBA:
  Firebar_Main 0x080D891C draws the outer ball at the full
  GuruguruBarSin value (0x080D8A50) and the inner three at
  (|v| * scale >> 8) with v's sign (0x080D8A90; scales {64, 128, 192} at
  0x1757F8, read at import into `hera.barScale`), the touch test reads
  those OAM positions. The port floored v * (i + 1) / 4, one pixel further
  out on the negative side in both the drawing and the touch test.
  `Hera.barOff` now places them as the cartridge does.
- [x] 41.3 **"An empty yellow box over the old man's house"** (round 40's
  `dm40_c01_trigger.png` / `dm40_c02_mirror.png`): both shots are the first
  drawn frame of a new message. The message routines draw the window
  before any letter (zelda3 messaging.c: Text_Initialize, then
  RenderText_Draw_Border / BorderIncremental, then
  RenderText_Draw_CharacterTilemap, then the characters), and the window's
  inside is clear on the GBA (round 8). Not changed. (The GBA's own text
  state machine was not traced this round.)
- [x] 41.4 **"Sparkles away from Link after the mirror landing"** (round
  40's `hera40_ha04_spectacle.png`): not the portal. The portal sits under
  Link at (2104, 360) = bird_travel[15] + 8 (Sprite_InitializeMirrorPortal),
  drawn before Link. The sparkles are the BG: screen 4's BG2 cells 0x51D5 /
  0x51DE (animated tiles 0x1D5 / 0x1DE, Death Mountain's sheet 0x58,
  palette 5); they are there with no mirror at all (`mir41b_plain.png`),
  and their pixels equal the cartridge's own VRAM (r15 `cart.py` dump
  `ow_03.bin`, compared by `anim41.lua`). Not changed.
- [ ] 41.5 Polish (intro night palette, the dungeon map's floor list /
  markers): not started (leads as in 38.4 / 40.2).

Checkpoints (`r41/out/`): `ck_r41_hera_b1se` (0x87 SE, harness),
`ck_r41_hera_bigkey` (real input), `ck_r41_hera_27`, `ck_r41_hera_17`
(harness; 0x17 at the west stairs). The checkpoints now carry the barrier
state (`peg`, restored by `ck25.lua`; a harness aid, a cartridge save does
not keep it either).

Tests: new `zelda_alttp_r41_test` (the ball scales in the cache, no
floored offsets, the cartridge's rule for every sine value).

## Round 42 (2026-11-13)

The Tower of Hera from `ck_r41_hera_17` to the third pendant with real input,
and one game rule behind 0x17's trouble: the sprites and the pits. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r42/` (the r41 kit with r42
paths; `harness/hera42.lua` the Hera leg (stages D / E / F as in r41, D
rewritten), `harness/moldorm42.lua` (moldorm41 + the way back into the
arena), probes `reach42.lua` (the planner's reach in the live room as ASCII),
`attr42.lua` (a room's attributes as hex); `py/gdis.py` / `calls.py` /
`scanlit.py` (Thumb disassembly, BL callers, literal-pool search)).
**cacheVersion 45**.

- [x] 42.1 **Game fix: sprites fall into pits** (new `SpritePit.lua`; hooks
  in `Hera.lua`, `Palace.lua`). Traced on the GBA:
  * Sprite_CheckTileProperty's pit rule (0x080C7760): tile 0x20 is a wall
    to every sprite, except a sprite whose kSpriteInit_Flags (0x227A81,
    sprite 0xD84) has bit 0 set while it recoils (sprite_F 0x1072 != 0).
    The port had it the other way round (`not (b == 0x20 and not
    a.recoil)`): every palace sprite walked over pits, and none was knocked
    in. The pit-fallers by that bit: 0x0B, 0x13, 0x26, 0x41-0x4B.
  * The floor probe (Sprite_CheckTileCollision 0x080C6F48 -> SingleLayer
    0x080C7014 -> 0x080C70E8): no flier (flags5 & 0x80), z 0, the tile at
    probe byte 0x68 (kSprite_Func5 entry 0x34) is 0x20 and flags bit 0 ->
    indoors sprite_state 5, delay 0x3F for the Hardhat Beetle / Mini
    Helmasaur (OAM name bit cleared), else 0x5F. Sprite_ReturnIfRecoiling
    (0x080C1FD0) runs the same collision (0x080C79D0) on its move frames.
  * SpriteModule_Fall2 (state 5, 0x080C8784; state table 0x171D88): delay 0
    -> gone, Sprite_ManuallySetDeathFlagUW (no prize); below 0x40 the
    picture kFall_Gfx[delay >> 1] (0x172558; the beetle's / Mini
    Helmasaur's OAM entries 0x17258C / 0x1725BC, drawn by 0x080C8B2C) and a
    drift at the recoil / 4 on frames where (frame & mask[delay >> 3]) == 0
    (0x172578), the recoil zeroed once the probe is off the pit. The tables
    are read at import (`data.t.d26.hera.fallGfx / fallMask / fallHH /
    fallHelm`).
  OURS: the probe is checked every recoil frame (the cartridge: its move
  frames); no sounds (0x65 / 0x6C); only the beetle and the Mini Helmasaur
  use the fall so far (the soldiers' Guard.lua and the cucco do not, the
  other sprites' shrinking picture 0x080C8998 is not drawn); a
  non-faller's recoil step (`Actors.recoilStep`) still crosses pits.
- [x] 42.2 **The prize's spot** (`Palace.lua`, RoomTag_GetHeartForPrize):
  OURS, not traced. The port dropped the prize at the SNES quadrant + 120 /
  + 96; in Moldorm's room (0x07) all four such spots are over the pit ring
  or a wall, so the pendant could not be taken. It now falls at the camera
  + 112 / + 64 (the middle of the GBA's 240 x 160 screen). To trace: the
  GBA's falling-prize ancilla (not found this round; 0x0809E43C is a
  sound call, not it).
- [x] 42.3 **Route check, real input** (`real/runreal.sh r38ck`, `SEG=seg40.lua
  LEGS=hera42.lua:DEF`, `HPFLOOR=8`). Passed:
  `ck_r41_hera_17` -> 0x17: the beetles stop at the holes' edges now (pits
  are walls to them; the bot holds the west alcove and strikes the ones
  that come) -> the 0x3B **star** pressed from the north with the Firebar on
  its east half (overlay 9) -> east along y 136 into the star's holes ->
  0x27's **chest island** (the drop missed three times -- knocked into the
  old holes on the way, 0x17 then reloads without the star's holes, as on
  the cartridge -- and landed on the fourth) -> the Spark round the chest
  -> the **Moon Pearl** (`ck_r42_hera_pearl_real`) -> off the island into a
  hole (0x31) -> 0x27 (pots lifted) -> 0x17 -> 0x07 (`ck_r42_hera_moldorm_real`)
  -> the south passage's north ledge (0x28) into the arena ->
  **Moldorm** (47 swings, five falls to 0x17 and back) -> heart container
  (40 -> 48) -> the **Pendant of Wisdom**, the third (pendants 6
  -> 7) -> out on Death Mountain (`ck_r42_hera_done_real`). Two runs: rh42b
  (0x17 -> Moldorm's room; its Moldorm bot gave up after 14 falls: it never
  hopped back into the arena) and rh42c (from rh42b's Moldorm checkpoint).
  Health floor: 64 + 120 absorbed. Also run in the harness (hd42*, he42*).
  Not reached: down Death Mountain, the Lost Woods, the pedestal,
  Agahnim's tower.
  Bot work (scratch only): the 0x17 hold spot and the edge-aware strikes;
  the star run timed on the Firebar's angle (`Hera.barSin`, its step);
  the island's Spark timing and the big chest opened with R; the
  island-exit drop; the room-by-room way to 0x07 (one search over all of
  them found no way); the arena's ledge hop (also after each fall).
- [ ] 42.4 Polish (intro night palette, the dungeon map's floor list and
  markers): not started (leads as in 38.4 / 40.2).
- Seen, not followed up: real-app shots (`real/shots/rh42*`) show the HUD
  over a white field (r41's did too): the harness shots are the ones to
  look at (`shots/hd42l_d01_pearl.png`, `shots/he42f_e02_moldorm_done.png`).

Checkpoints (`r42/out/`): harness `ck_r42_hera_17`, `_hera_island`,
`_hera_pearl`, `_hera_31`, `_hera_moldorm`, `_hera_done`; real input
`ck_r42_hera_island_real`, `_hera_pearl_real`, `_hera_31_real`,
`_hera_moldorm_real`, `_hera_done_real` (Death Mountain, three pendants).

Tests: all 50 `zelda_alttp_*` files pass (new `zelda_alttp_r42_test`, 19
checks: the fall tables in the cache, the pit rule both ways, the floor
probe, the fall to its end and the kill flag). Audits 304/304 rooms, 80/80
overworld areas (`AUDIT=rooms|ow run.sh audit` in r42, the r42 store,
cacheVersion 45; `mains.txt` copied from r26b).

## Round 43 (2026-11-13)

The boss prize's spot traced, the route with real input from
`ck_r42_hera_done_real` down Death Mountain to the Master Sword and on to
Hyrule Castle's upper terrace, and the real app's "white screen" shots.
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r43/` (the r42 kit with
r43 paths; `harness/ped43.lua` the leg, stages A (Hera's door -> the return
cave E7), B (E7 -> E6 -> out, area 0x0A), C (the cliff hop -> the Lost
Woods -> the grove), D (the pedestal), E (out of the grove, the telepathy,
-> the castle's hole bush -> 0x55), F (0x55 -> courtyard -> hall 0x61), G
(0x61 -> 0x60 -> its south edge -> the upper terrace), H (the tower door);
probes `dmdown43.lua` (overworld flood with ledge hops, entrances in reach,
routes, attribute dumps, owEvents), `find40.lua` (sprite 0x40, castle
entrances, pits); `py/ffind.py`, `py/cmpscan.py`; bot: `B.hopMax` for tall
cliffs). **cacheVersion 46**.

- [x] 43.1 **Game fix: the boss prize's spot and fall** (new `Prize43.lua`,
  hook in `Palace.lua`; replaces r42's OURS guess). Traced on the GBA:
  AncillaAdd_FallingPrize is 0x080ADD38. With i = kBossFinishedFallingItem
  [palace >> 1]: i 0 / 5 -> Link's spot; the Tower of Hera (palace 0x14,
  0x080ADE88) -> the room's middle, ((link & 0xFE00) + 0x100) on both axes;
  else (0x080ADEE4) BG2VOFS + kFallingItem_Y[i] (0x16E5E2) / BG2HOFS +
  kFallingItem_X[i] (0x16E5F0) -- the GBA's own tables, read at import
  (`data.t.prize43`); z = kFallingItem_Z[i] (0x16E5DB), z speed 0xD0. The
  fall (Ancilla29_MilestoneItemReceipt, as Ending27's crystal): 128 frames
  still, z falls at -48/16, one bounce (0x18), taken while z < 24. Moldorm's
  room centre (256, 256) is arena floor. Not traced on the GBA: the update
  routine (zelda3's); the picture stays the item's menu icon (now the
  palace's own pendant, not always the green one).
- [x] 43.2 **Game fix: the Master Sword could not be pulled** (`Grove.lua`).
  SpritePrep_MasterSword (GBA 0x080D52A4, prep table 0x17451C entry 0x62):
  sprite x / y low bytes + 6. The port left it out: the sword's 4 x 8 hit box
  sat 6 px up-left, Link in the stone's notch (the only spot facing down,
  facing 2 = the cartridge's rule) did not touch it. The drawing moves 6 px
  with it, as on the cartridge.
- [x] 43.3 **Game fix: Zelda's telepathy after the Master Sword** (new
  `Telepathy43.lua`). Traced: Ancilla22_ItemReceipt (0x081183F0..) sets
  follower_indicator (+0x1663) = 0x0E (`movs r0, #0x0E`, 0x08118438) for item
  1; Follower_HandleTrigger (0x08115D30) with OldMan.lua's trigger rows:
  area 0's row {y 0xE8, x 0x90, msg 0x2B, follower 0x0E}; message 0x2B
  (`cmp r2, #0x2B`, 0x08115DE2) clears the follower (0x08115E0A). The two
  immediates read at import (`data.t.tele43`). The port never armed it: no
  telepathy. OURS: the follower is set as the receipt starts (cartridge: at
  receipt timer 0x11).
- [x] 43.4 **Game fix (flag only): the priest's castle event** (`Escape.lua`).
  The GBA's priest (0x080F2F30, Zelda following) sets save_ow_event_info
  [0x1B] |= 0x20 (0x0200229B); the port did not. Its effect, the area's
  event overlay (zelda3 Overworld_LoadEventOverlay case 0x1B: the castle's
  front gate opened, map16 at (30..33, 39..40)), is NOT ported: the GBA
  routine was not found (not a table of (pos, id) pairs, the ids are not
  code literals; see 43.6).
- [x] 43.5 **Route check, real input** (`real/runreal.sh r38ck`, `SEG=seg40.lua
  LEGS=ped43.lua:ABCDEFGH`, no health aid). Passed: Hera's door -> down the
  mountain's paths -> the return cave (entrance 0x2F, E7 -> E6) -> out on
  area 0x0A's ledge -> the tall cliff hop -> the Lost Woods -> the grove
  (area 0x80) -> the **pedestal** (R in the notch facing down; the three
  pendants, the light well, the beams) -> the **Master Sword** (sword level
  2) -> out of the grove -> **Zelda's telepathy** (message 0x28 ours = GBA
  0x2B, follower cleared) -> south-east to the castle -> the hole bush
  (lifted with R) -> the secret passage 0x55 -> the courtyard (bushes cut)
  -> the hall 0x61 (the big door) -> the west wing 0x60 (the corridor, its
  stairs, the south edge) -> the castle's **upper terrace**.
  Not passed (game, open): the tower door (entrance 0x24, room 0xE0). Link
  stops at y 1640, the doorway row is solid (0x02) in the port's map; the
  barrier sprite 0x40 (area 0x1B's list, cell (31, 6)) is not spawned (no
  overworld actor for it). Likely the same missing event overlay as the
  front gate (43.4) -- not traced; Agahnim not reached.
  Bot work (scratch only): off the doorsteps first (the planner's body does
  not fit the exit spots; its align / escape steps walked back in);
  `B.hopMax` (area 0x0A's cliff is ~90 px); the pedestal spot and R (the
  GBA's action button); the 0x60 exit (no exit tiles: the room's south
  edge); the front gate is shut so the leg goes in by the hole bush.
  Harness-only: an overworld checkpoint loaded on a doorstep cannot move
  (no exit walk) -- run G and H together.
- [x] 43.6 **"HUD on a white screen" in the real app's shots: the screenshot
  method, not the game.** ZeldaRuntime's Host:draw draws a zoomed play field
  into its own `zoomCanvas` and only the HUD (G:drawOverlay) into
  `host.canvas`, cleared to transparent; the real harness saved
  `host.canvas` (transparent = white in viewers). The window shots taken in
  the same run (`WINSHOTS=1`, `real/shots/*_win.png`) show the full picture.
  Nothing changed in src.
- Seen, not followed up: in the zoomed window the telepathy text draws
  without its window and the first letter shows as "a" in one window shot
  (`rp43_e01_telepathy_win.png`; the native canvas reads "Link!").
- [ ] 43.7 Polish (intro night palette, the dungeon map's floor list and
  markers): not started.

Checkpoints (`r43/out/`, real input): `ck_r43_ped_e7`, `_ped_out`,
`_ped_grove`, `_ped_sword`, `_ped_55`, `_ped_hall`, `_ped_terrace`.

Tests: new `zelda_alttp_r43_test` (the prize tables in the cache, Hera's
middle, camera + table elsewhere, the wait / fall / bounce, the sword's
prep, the telepathy trigger).
All 51 `zelda_alttp_*` files pass (r29's pedestal position check now expects
the prepped + 6). Audits 304/304 rooms, 80/80 overworld areas (`AUDIT=rooms|ow
run.sh audit` in r43, cacheVersion 46; `mains.txt` copied from r42).

## Round 44 (2026-11-14)

The castle after the escape (the front gate, Agahnim's barrier, the tower
door), Agahnim's tower from its door to room 0xB0 with real input, three
dungeon rules the tower needs, and the text glitch from r43. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r44/` (the r43 kit with r44
paths; `harness/tower44.lua` the terrace -> barrier -> door leg (stage H, run
after `ped43.lua:G`), `harness/agah44.lua` the tower leg (stage T, TSEQ =
the rooms in order; quadrant fights only for key carriers / kill tags,
`crossShutter`, `unpit`, the C0 waypoints, HPFLOOR aid), `ag.sh <log> <ck>
<rooms>` its harness runner; probes `door44.lua` (area 0x1B's map16 /
attributes / sprite lists, the gate), `locks44.lua` (a room's door slots,
locks, chests, actors), `e0dbg.lua` / `e0east*.lua` / `trans44.lua`
(transitions, lock opens with tracebacks), `hplog44.lua` (every health
change), `text44.lua` (a message's tokens and rows), `nlscan.lua` (what
follows every newline in all 455 messages)). **cacheVersion 47**.

- [x] 44.1 **Game fix: the castle's event overlay -- the front gate opens**
  (new `Castle44.lua`). Traced: Overworld_HandleOverlaysAndBombDoors is the
  GBA's 0x08076F30 (area < 0x80 and save_ow_event_info 0x02002280[area] &
  0x20 -> 0x080925E4 = Overworld_LoadEventOverlay, which calls the area's
  routine from the pointer table 0x153C04; 0x1B / 0x1C / 0x23 / 0x24 share
  0x0808FDD8). The routine stores map8 words of map16 0xDC1.. (the map16 ->
  map8 table 0x155B4E) straight into the BG2 map 0x02018000 (32 x 32 blocks,
  the index layout of 0x0809265C). It is straight-line Thumb: the import
  runs it with a small evaluator (ldr literal, mov, add/sub, lsl/lsr, ldrh
  from the ROM, strh) and keeps the 32 words it stores with their cells
  (`data.t.castle44.gate`, map16 (30..33, 39..40)). Applied when area 0x1B
  loads with the bit (set by the priest, r43). OURS: a save from before r43
  (escaped, bit clear) gets the bit when the area loads.
- [x] 44.2 **Game fix: Agahnim's barrier, sprite 0x40** (`Castle44.lua`; it
  was never created). SpritePrep_AgahnimsBarrier 0x080F81BC (prep table
  0x17451C): outdoors, event bit 0x40 -> graphics 4; x + 8, y + 8 - 12.
  Sprite_EvilBarrier 0x080F7F8C: draw 0x080F8108 (cur_y + 8; broken frame
  0x179EF8, else 0x179F30 / 0x179F40 / 0x179F60 by frame counter, read at
  import); Sprite_CheckDamageFromLink with sword type <= 1 -> 0x080F821C
  (Link hurt, electrocute); Sprite_BehaveAsBarrier 0x080C5080 (hit box 0);
  the zone (link_y - cur_y + 8 < 24, link_x - cur_x + 32 < 64, not walking
  down) zaps Link: damage 2, pushed down at 48 for 12 frames. Its death
  (0x080C2382): event bit 0x40, graphics 4, it stays. OURS: the damage is
  taken at once (the hit timer only stops a second hit per swing); no zapped
  pose, sounds or poof; the Byrna exception (0x080F825C) not ported.
- [x] 44.3 **Game fix: the tower door (big door 0x169) stayed shut**
  (`Game.lua`, one line). The GBA's 0x0808BE18 opens a 0x169 big door while
  the story byte (+0x165E) is 2 or less; the port opened it only before the
  escape (`not progress.escaped`). Now `storyProgress() <= 2`.
- [x] 44.4 **Game fix: the shutters on a transition inside a room** (new
  `Shutters44.lua`). The GBA's kDungeon_IntraRoomTrans (0x14CB54): state 2
  DungeonTransition_Subtile_ResetShutters 0x0806CFC0 (trapdoors flag +0xB10
  = 0, step 7, OperateShutterDoors 0x080810AC: every shut 0x44 / 0x18 door
  opens), state 7 DungeonTransition_Subtile_TriggerShutters 0x0806D264 (the
  flag back to 1: every open one shuts). The port never did either: a
  two-way shutter between quadrants (room 0xE0: the way north from the
  entrance quadrant) stayed shut and Link could not get in. The room tags
  may open them again (the port's `cleared` latch is reset). OURS: no
  animation / sounds; the shutting waits until Link's body is off the
  shutters' cells (the cartridge shuts them after the landing; its doorway
  collision there is not traced).
- [x] 44.5 **Game fix: where a hurting pit puts Link back** (new
  `RoomCache44.lua`). ResetThenCacheRoomEntryProperties (0x08070A80, from
  TriggerShutters and the room-to-room transition's end) runs
  CacheRoomEntryProperties 0x0808B1FC (link_y +0x16C0, link_x +0x16C4);
  DungeonPitDoDamage + RecoverPositionAfterDrowning put Link back there. The
  port used the last spot off the pit (Dungeons26's pitSafe, OURS): in room
  0xC0 the pit's pull took him in again and again to the game over. OURS:
  the spot is kept when the port's transition ends.
- [x] 44.6 **Game fix: the curtain door 0x32** (new `Curtain44.lua`; not
  reached yet on the route). The GBA's 0x08086218: B down, button_b_frames
  == 4, the cells at link + player_oam offsets (and right / below) in the
  attribute table 0x0200CBA0; a door mark 0xF0 + k whose type & 0xFE is 0x32
  opens (dung_door_opened |= kUpperBitmasks[k] 0x081676B2, 0x08086140 the
  attributes). The port's "other" locks never opened. OURS: no sound.
- [x] 44.7 **Game fix: a message's first row was overwritten -- "aink!"**
  (`Text.lua`). The GBA copies a message into its buffer 0x02005480 and skips
  0x0A there (0x08127494 / 0x0812755E): rows come only from the line /
  scroll commands. The port turned a newline into "next row": the ~15
  messages that start with one (Zelda's telepathy 0x2B: `{window 2}{speed
  3} NL {name}! Help! The soldiers NL {line 2} are coming ...`) put their
  first row on row 1, and the line-2 command then wrote over it letter by
  letter ("aink! Help!"). All 2961 newlines checked (`nlscan.lua`): every
  one is followed by a positioning / wait / end command or is leading.
  **No text box** in the telepathy: the cartridge's own -- the message
  selects the borderless window 2 (r33). Not a bug.
- [x] 44.8 **Route check, real input** (`real/runreal.sh r38ck`,
  `SEG=seg40.lua`). Passed: `ck_r43_ped_hall` -> `ped43.lua:G` -> the upper
  terrace -> `tower44.lua:H`: walking into the barrier zaps Link (hp - 2,
  pushed down) -> one Master Sword swing breaks it -> up into the tower door
  (the 0x169 big door opens) -> room 0xE0 (`ck_r44_tower_e0`). Then
  `agah44.lua:T` (HPFLOOR=16, a harness aid; PM=0): E0 (SW -> the NW shutter
  opens and shuts behind Link -> the ball-and-chain guards -> NE -> the
  revealed chest's key -> the stair key block) -> D0 (dark, the lamp) ->
  C0 (dark, pits that hurt; SW -> NW -> NE, the archer's key, the stair
  key block) -> **room 0xB0** (`ck_r44_tower_b0`; the C0 leg failed once in
  the real app -- the bot walked into C0's pits -- and passed on the rerun
  with corrected waypoints, no health aid used on it).
  Not reached: B0's key (the red spear guard inside the south-west ring:
  the bot's fight helper never got a swing in), rooms 0x40 / 0x30 (the
  curtain) / 0x20, Agahnim, the Dark World.
  Bot work (scratch only): the planner reads a closed two-way shutter as a
  wall (`crossShutter` walks its doorway), cannot start on a pit's edge
  (`unpit`), fights only key carriers / kill-tag quadrants, C0's waypoints;
  the fight helper is weak against two ball-and-chain guards (health floor
  absorbed ~390 in E0).
- [ ] 44.9 Polish (intro night palette, the dungeon map's floor list and
  markers): not started.

Checkpoints (`r44/out/`, real input): `ck_r43_ped_terrace` (rewritten),
`ck_r44_tower_e0`, `ck_r44_tower_d0`, `ck_r44_tower_c0`, `ck_r44_tower_b0`.

Tests: new `zelda_alttp_r44_test` (the Thumb runner, the block index, the
overlay's 32 words on the gate cells and the four screens, the barrier's
draw tables, prep, zap zone, Master Sword break and fighter's-sword zap, the
event bit, the 0x169 rule, the telepathy message's first row, the shutters'
reset / trigger; 21 checks).
All 52 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80 overworld
areas (`AUDIT=rooms|ow run.sh audit` in r44, cacheVersion 47; `mains.txt`
copied from r43).

## Round 45 (2026-11-14)

The ball-and-chain guards against the cartridge, a new fight helper for the
bot, and the rest of Agahnim's tower with real input: room 0xB0's key, rooms
0x40 / 0x30 (the curtain) / 0x20, Agahnim, the warp to the pyramid. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r45/` (the r44 kit with r45
paths; `harness/agah45.lua` the tower leg (stage T; checkpoints
`ck_r45_*`), `harness/bnc45.lua` the new fight helper, `harness/bnc45t.lua`
its seed test (`SEG=bnc45t.lua CK=r45_e0_nw SEEDS=n`), `harness/agfight45.lua`
Agahnim (stage A, then the warp), `harness/pitdbg.lua` (pit falls with their
spots), `ag.sh <log> <ck> <rooms>` the harness runner (LEGS default
`agah45.lua:T`)). **cacheVersion 47** (no import change).

- [x] 45.1 **Game fix: the ball-and-chain guard's ball vs Link's sword**
  (`BallChain.lua`). The GBA's Sprite_6A (0x080E2D4C) calls
  Guard_ParrySwordAttacks (0x080C3964) from 0x080E2D7E: nothing while
  link_incapacitated_timer (+0x16F8) or +0x1702 runs; Link's action box on
  the ball parries first (0x080C3A1C) and the ball does no damage that frame;
  only without it Link_SetupHitBox meets the ball (0x080C39E2 -> 0x080C3AC8,
  the shared damage + recoil). The port hurt Link even when his swing met the
  ball. Damage (8 with the green mail, bump class of 0x6A), Link's 58 blink
  frames and the chain lengths (16..48) were already the cartridge's.
- [x] 45.2 **Game fix: the whirl keeps going while the guard recoils**
  (`BallChain.recoilTick`, one line in `Actors.lua`'s recoil branch). The
  angle step and the parry / ball check run before Sprite_ReturnIfRecoiling
  (0x080E2DAC) and the sprite timers count down in the shared loop; the port
  froze the guard's whole cycle during its knockback. The ball check is
  skipped while the hit timer runs (sign8 of +0x10C2 at 0x080C3996; the
  port's `a.inv`, OURS).
  Finding: the ~390 HP the r44 bot lost in room 0xE0 was the bot (it never
  struck in the safe window), not the guards.
- [x] 45.3 **Bot: a new fight helper** (`bnc45.lua`, scratch only). The ball's
  next 20 frames from BallChain's own routine on a copy (fight21's simBall),
  Link's 9 moves from the engine's walk; the spin attack (8 damage on 0x6A vs
  2 for a swing, hp 16) charged out of reach and let go when the guard is
  walking / standing / whirling with time left and its body is in the spin
  box; out of the throw's reach (70 px) when one comes; walking distances by a
  BFS around pillars; pits cost 1e6; an `area` and a `stay` mode. Seeds from
  `ck_r45_e0_nw`: 4 / 4 wins, **0 HP lost, 0 absorbed by the health floor**
  (r44: ~390 absorbed). Real app, room 0xE0: both guards, 0 HP lost.
  Also fixed in fight21 (scratch): `F.linkPath` walked a copy of Link through
  `Doors.move`, whose pit check started a REAL fall in the game when a
  predicted step touched a pit (room 0x40: Link "fell" from a standstill,
  again and again to the game over; likely r44's C0 trouble too). It now
  restores the game's state after the prediction. simBall no longer parries
  (stub `swing = false`) and follows the recoil tick.
- [x] 45.4 **Route check, real input** (`real/runreal.sh r38ck`,
  `SEG=seg40.lua LEGS=agah45.lua:T,agfight45.lua:A`, HPFLOOR=16, PM=0; three
  segments from checkpoints, full health at each load as before).
  Passed: `ck_r44_tower_e0` -> E0 (the two ball-and-chain guards, no damage)
  -> D0 -> C0; `ck_r45_tower_c0` -> C0 -> **B0** (the key guard stands in two
  rings of pots, attributes 0x70..0x7D between solid 0x27 blocks: lift the
  outer ring's west pot from x 48, the inner ring's from the corridor, fight
  inside; the key, the key door) -> **0x40** (16 px paths between pits);
  `ck_r45_tower_40` -> 0x40 -> **0x30** (Agahnim's altar scene: messages
  0x13D / 0x13E, Zelda sent away, Agahnim flies off; the **curtain door
  0x32** opens to one sword swing from below, r44's Curtain44) -> **0x20**
  (message 0x13F; six returned energy balls, 16 each, hp 96) -> the warp ->
  **the pyramid** (area 0x5B, Dark World). No game bug found on this stretch
  beyond 45.1 / 45.2.
  Health floor (harness aid) absorbed: E0 0, B0 12, Agahnim 68 (the bot only
  deflects plain balls and dodges seekers; it was hit by the split balls and
  the lightning). Pit damage is not covered by the floor: one real attempt
  ended in a game over in room 0x40 (the bot knocked into the pits), and
  several room 0x40 attempts failed before the walk below.
  Bot work (scratch only): room 0x40's waypoints with a retreat to the wide
  floor when a guard comes near, a floor fight there, resume at the waypoint
  Link stands on; exact spots by one-tick taps and a back-off when the walk's
  1 / 2 px rhythm keeps jumping over the spot (the real app can run several
  ticks in one window frame); the curtain slash; Agahnim: a swing when a
  plain ball will meet the swing's boxes.
- Seen, not followed up: in room 0x30 the two altar messages draw their
  window over Link (he stands low on the screen); the cartridge's window
  position rule was not traced.
- [ ] 45.5 Polish (intro night palette, the dungeon map's floor list and
  markers): not started (the time went to the route).

Checkpoints (`r45/out/`, real app): `ck_r45_e0_nw`, `ck_r45_tower_d0`,
`ck_r45_tower_c0`, `ck_r45_tower_b0`, `ck_r45_b0_sw`, `ck_r45_tower_40`,
`ck_r45_tower_30`, `ck_r45_tower_20`, `ck_r45_pyramid`.

Tests: new `zelda_alttp_r45_test` (no ROM: the ball hurts without a sword,
a swing on the ball parries with no damage, nothing while Link is
incapacitated, the recoil tick keeps the timers / whirl / ball and skips the
ball while the hit timer runs; 9 checks).
All 53 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80 overworld
areas (`AUDIT=rooms|ow run.sh audit` in r45, cacheVersion 47; `mains.txt`
copied from r44).

## Round 46 (2026-11-14)

The message window's top / bottom rule, Kiki the monkey and the Palace of
Darkness's door (new `Kiki46.lua`), and the Dark World from the pyramid to
area 0x5E with real input. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r46/`
(the r45 kit with r46 paths; `harness/dw46.lua` the Dark World legs (stage
letters, `KLEGS_<stage>` waypoints, `CKAT_<stage>` checkpoint, HPFLOOR /
HURTLOG, the text / rupee hooks), `harness/farm46.lua` the rupee farm,
`harness/door46.lua` Kiki at the door -> the door event -> the entrance,
`harness/rupcheat.lua` TEST ONLY (sets 150 rupees, used for the logic smoke
test, never for a route checkpoint), probes `dwmap46.lua` (attribute map),
`dwreach46.lua` / `trigreach.lua` (planner reach), `kiki46p.lua`;
`py/gdis2.py` a resyncing Thumb disassembler; `out/kiki_all.txt` Kiki's
routines). **cacheVersion 48**.

- [x] 46.1 **The message window over Link in room 0x30: the cartridge's
  rule, not a bug.** Traced 0x08129C58: `(link_y (+0x16C0) - BG2VOFS
  (+0x958)) & 0xFFFF > 0x5B` -> window 0 (0x18097C[0] = map byte 0x1CA:
  rows 7..14, y 56..119), else window 1 (0x308: rows 12..19, y 96..159).
  Text.lua had the same rule, the same table and the same camera; in room
  0x30 Link stands at screen y ~111 (the camera is held at the room's
  bottom), so window 0 is chosen and its lower rows cover his head -- the
  GBA does the same (the "top" window sits in the middle of the 160 px
  screen; the SNES's is likewise rows 9..16 with its 0x78 threshold).
  One fix: the compare is unsigned (Link above the screen's top also takes
  window 0).
- [x] 46.2 **Game fix: Kiki the monkey, sprite 0xB6, was not ported**
  (new `Kiki46.lua`; area 0x5E's list holds him at cell (21, 17); the
  port dropped the type). Traced: main 0x080FAFCC by subtype2 (0x17A4DC):
  0 Kiki_LyingInWait 0x080FA724 (not drawn; touching him -> follower 10,
  0x0812F9A8 / 0x08114600; not while blinking / damage-off / follower 10 /
  the area's bit 0x20), 1 Kiki_OfferEntrance 0x080FA7CC (ai table
  0x17A504: 0x11E, then 100 Rupees (0x0810EF98) -> 0x120, Link held, the
  walk 0x17A538 / 0x17A532 at 9, the hops 0x17A530, the walk list 0x17A53E
  / 41 / 43 / 47, overworld event 1; refused -> 0x11F, subtype2 3), 2
  Kiki_OfferInitialService 0x080FA53C (ai table 0x17A4F0: 0x121, 10 Rupees
  -> 0x122, tagalong_event_flags |= 3; refused -> 0x123, follower 0, he
  runs to (0xCF5, 0x6FE) and hops away, Link held meanwhile), 3 Kiki_Flee
  0x080FA36C (hops at 16 x 2 towards (0xCF5, 0x6FE), gone off the screen or
  landed inside the box 0xC98 / 0x6A5 + 0..0xCF). Kiki_Draw 0x080FACFC
  (0x17A54B DMA bytes + 0x17A55C for D 0..7: follower 10's sheet 0x59 +
  for D 0..3, the sprite sheet for 4..7; 0x17A65C for D >= 8; the shadow).
  The follower: Follower_HandleTrigger 0x08115CA4 / 0x08115D30 on area
  0x5E's outdoor rows (y, x, bit, 0xFFFF, 10): the two rows with bits 1 / 2
  spawn subtype2 2 (unless save_ow_event_info[0x5E] & 1), the bit-0 row at
  the door spawns subtype2 1 and ends the follower (0x08115FA8); Link hurt
  (link_auxiliary_state +0x1702 and countdown_for_blink +0x17AA) while he
  follows -> subtype2 3 (0x08114E1C). Messages / prices / flee spot / box
  are read at import from the code (call sites, `movs` / `ldr` / `cmp`).
- [x] 46.3 **Game fix: the Palace of Darkness's door (overworld event 1)**
  (`Kiki46.lua`). Kiki's walk ends with +0xB6E = 1; the overworld module
  (0x08072594) runs 0x0808F148 -> 0x153BF0[0] = 0x0808F2F0, steps
  0x153B3C: 0x40 frames, then save_ow_event_info[0x5E] |= 0x20 and map16
  changes, three steps of 0x20, the end 0x0808D788 (Link free). The opened
  door is the area's event overlay 0x153C04[0x5E] = 0x08092038 (shared by
  0x5E / 0x5F / 0x66 / 0x67), run at import with Castle44's Thumb
  evaluator (16 map8 words), drawn whenever the area loads with the bit.
  Entrance 38 (3936, 1584) then leads into room 0x4A.
  OURS: the four map16 steps are drawn as the finished overlay at the first
  step; no sounds; +0x176C (Kiki_LyingInWait's first test) is read as the
  bunny (not traced); "hurt" = the port's recoil while the blink runs.
- [ ] 46.4 **Route check, real input (harness from checkpoints;
  HPFLOOR=16 harness aid).** Passed: `ck_r45_pyramid` -> down the
  pyramid (two ledge hops) -> east along y ~2200 through area 0x65 (the
  ledges there are one-way) -> area 0x5E (`ck_r46_dw_5e`) -> Kiki's cell
  (3408, 1808): touching the invisible Kiki makes him follower 10
  (`ck_r46_kiki_joined`, `ck_r46_kiki_door`) -> north into the bit-1 trigger
  (3450, 1714): message 0x11E "ten Rupees?", yes, 79 -> 69 Rupees, he stays
  (`ck_r46_kiki_paid10`; the same leg passed in the real app with window
  shots, `real/shots/r46real_*_win.png`).
  Not passed: the door. Kiki wants 100 more and Link has 69 (78 at the
  pyramid; the save never had more). The rupee farm bot (`farm46.lua`,
  enemies near Link, waypoints 3194,1650 <-> 3200,2200) made +6 in ~25
  rounds (~20 min) and was stopped. The palace, Helmasaur King and the
  crystal were not reached.
  Logic smoke test (NOT route; `rupcheat.lua` sets 150 Rupees first):
  `ck_r46_kiki_door` -> pay 10 -> the door trigger (3920, 1629): Kiki
  appears (subtype2 1), 0x11E... 0x120, 100 paid, Link held, his walk and
  two hops onto the ledge, the door event (bit 0x20 after 0x40 frames, the
  overlay: the stairs open), Link free -> entrance 38 -> room 0x4A. Its
  checkpoints are kept as `cktest_r46_pod_open_testrupees` /
  `cktest_r46_pod_in_testrupees` (not route checkpoints).
  Health floor (harness aid) absorbed: pyramid -> 0x5E 84, 0x5E -> Kiki 48,
  the paid-10 leg 0 (route total 132); the farm runs absorbed ~230 more
  (Hinox bombs 0x4A and Moblin spears).
- Bot work (scratch only): owfight25 struck at Kiki's invisible sprite (an
  `owe` actor) and the bot stood still -- it now skips `a.kiki`; the fight
  helper does not dodge the Hinox's bombs (0x4A, 8 damage each) or the
  Moblins' spears, which is where the health floor went; targets the
  planner cannot stand on (3448, 1740; the closed door's tiles) replaced by
  reachable spots (3450, 1714; 3920, 1629); the rupee farm.
- Dark World state on the way: Link keeps his form (Moon Pearl), music id
  14 outdoors and 16 in room 0x4A, the Dark World palettes and sprite sets
  in every shot. Not compared frame by frame with the cartridge.
- Seen, not followed up: Kiki's D >= 8 / D 4..7 poses (sprite-sheet chars
  0x9A..0xDE) draw in a blue palette while his follower picture is brown;
  the palette row comes from flags3 as on the GBA, not checked further
  (OURS?).
- [ ] 46.5 Polish (intro night palette, the dungeon map's floor list and
  markers): not started.

Checkpoints (`r46/out/`, harness, real input): `ck_r46_dw_5e`, `ck_r46_kiki_joined`,
`ck_r46_kiki_door` (the same spot, Kiki following), `ck_r46_kiki_paid10`.

Tests: new `zelda_alttp_r46_test` (the window rule incl. unsigned, Kiki's
code numbers and tables, the door overlay's 16 words, joining on touch, the
10-rupee offer paid / refused, the 100-rupee offer, the walk, the door
event's bit 0x20 and its length, refusing at the door, fleeing when Link is
hurt; 25 checks). All 54 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80 overworld
areas (`AUDIT=rooms|ow run.sh audit` in r46, cacheVersion 48; `mains.txt`
copied from r45).

## Round 47 (2026-11-14)

The enemy prize drops against the cartridge, Kiki's 100 Rupees with real
input, the Palace of Darkness's door and its first rooms. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r47/` (the r46 kit with r47
paths; `harness/dropprobe47.lua` logs every death's prize check and every
pickup, `harness/owlist47.lua` every area's sprite list with its prize
pack, `harness/farm47.lua` the new rupee farm (waypoints over area 0x5E's
Ropas / Snapdragons, house 104 in and out to reload the area), `harness/
pod47.lua` (pod copy of agah45's helpers) + `harness/pod47b.lua` (a step
list: rooms, chests, keys, lifts, switches, holds), `podreach.lua` (the
rooms the planner reaches), `pod47map.lua` (chests / locks / secrets per
PoD room), `real/` the real app). **cacheVersion 48** (no import change).

- [x] 47.1 **The prize drops are the cartridge's.** Traced
  Sprite_DoTheDeath's prize part 0x080C6980: pack = flags5 (+0x11B2) & 15,
  0 none; item_drop_luck (+0xECB) / its kill counter (+0xECC, 10) not used
  on this save; GetRandomNumber 0x080CEFE0 & kPrizeMasks[pack - 1]
  (0x17216F) == 0 -> ForcePrizeDrop 0x080C6F08: kPrizeItems[pack * 8 +
  the pack's counter (+0x1611 + pack, & 7)] (0x17217A) -> the spawn
  0x080C66A4 (kPrizeZ 0x172160). Actors.died had all of it. Measured on
  the farm (dropprobe47): 14 kills, 7 drops (masks 1: 50 %), rupee values
  1 / 5 / 20 (D9 / DA / DB). Area 0x5E's Moblins (0x12) carry pack 1
  (hearts only), the Ropas (0x22) and the Dark World Ravens pack 2
  (rupees), the Snapdragons (0x0E) pack 7: the r46 farm fought Moblins and
  Hinoxes. The r46 "+6 in 20 min" was the bot (few kills, the wrong
  enemies, killed enemies never coming back), plus 47.2.
- [x] 47.2 **Game fix: leaving a house / cave reloads the area's sprites**
  (`Game.lua` G:leaveRoom). Module08 (0x080743AC; module table 0x814CA5C
  entries 8 and 0xA) submodule 0 (0x08073C74) calls 0x080CBCC8 =
  Sprite_DisableAll (0x080CAD30: every sprite slot off, the mirror portal
  0x6C kept) + Sprite_OverworldReloadAll (0x080CBCB4: 0x080CB01C clears
  the grid's loaded flags 0x02006B80 / 0x02007B80, 0x080CB0EC loads the
  list, 0x080CA934 activates what is near). The port kept the overworld
  list and its loaded-cell memory: killed enemies never came back after a
  house trip, and drops lay where they were. Now the list, the grid state
  and the drops go, so the area loads fresh.
- [x] 47.3 **Game fix: an enemy's arrows without the bow** (`Actors.lua`
  A:died). The prize spawn 0x080C66A4 passes the type through 0x080C382C
  too (GBA only): no bow (0x02002320 = 0) -> 0xE1 / 0xE2 become 0xD9 /
  0xDA, as the bush drops already did. (Not hit on this route: Link has
  the bow.)
- Not changed (OURS, noted): the port's VCOUNT stand-in ((frame * 37 +
  calls * 73) % 228) makes bit 0 of every random number a function of the
  call count alone (frame * 37 + frame is even): the "& 1" tests (the 50 %
  prize mask, the bush substitution) follow a 0,1,1,0 pattern in the calls
  rather than the scanline. The measured rate was 50 %; changing the model
  would shift every earlier checkpoint's replays, so it stays.
- [x] 47.4 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r46_dw_5e` (79 Rupees, before Kiki) -> farm47: area 0x5E's Ropas /
  Ravens / Moblins, bushes, two trips into house 104 and out (47.2 brings
  them back) -> 110 Rupees (`ck_r47_farm_done`; 14 kills, 7 drops: 2 blue,
  1 red, 1 green rupee and hearts; health floor absorbed 692, mostly the
  Dark World Ravens 0x00 (24 a hit, bump class 8) and Ropas (16)) ->
  Kiki's cell (`ck_r47_kiki_joined`) -> the bit-1 trigger: 10 paid
  (`ck_r47_kiki_paid10`) -> door46: the door trigger, 0x11E... 100 paid
  (100 -> 0), Kiki's walk and hops, the door event (bit 0x20), Link free
  (`ck_r47_pod_open`) -> entrance 38 -> **room 0x4A** (`ck_r47_pod_in`).
  The Palace of Darkness so far: 0x4A's right stairs -> 0x09 (east half);
  the bot then took the left way: 0x4A's south-west arm, its two-way
  shutter 0x18 up into the west section, its stairs -> **0x09 west half,
  the small key** (chest 192,176; `ck_r47_pod_09key`) -> back up: the west
  section's shutter is shut and room tag 0x17 (RoomTag_SwitchTrigger_
  ToggleDoor) opens it from a floor switch: the pot at (48,80) hides
  secret 0x88 (a switch, Interior.potSwitch); lift it, step on the switch
  (the cartridge's 2x2 probe at ((x - 1) & 0x1F8, (y + 14) & 0x1F8)), the
  shutters open -> down the arm -> the key door north -> **0x3A**
  (`ck_r47_pod_3a`) -> its north-west way -> **0x2A** (`ck_r47_pod_2a`).
  Stopped in 0x2A: its two key chests sit past a block puzzle (blocks at
  (160,304) / (176,288) beside the stairs 0x3D) the bot did not solve; the
  Hardhat Beetles push Link about. No game bug found on this stretch.
  Not reached: the big key (0x3A), the Magic Hammer (0x1A's big chest),
  Helmasaur King (0x5A), the crystal.
  Real app (`real/runreal.sh r38ck`, window shots in `real/shots/`):
  `ck_r47_farm_done` -> Kiki joins, 10 paid (110 -> 100), then on the
  walk to the door Link was hit once and Kiki fled (the cartridge's rule,
  46.2) -- the bot's dodging, not a bug; the 100 were not paid in the real
  app. `ck_r47_pod_in` -> 0x4A's west arm and shutter -> 0x09's key chest:
  passed (`r47realpod_*_win.png`). Loading `ck_r47_kiki_paid10` asks for
  the 10 again: Kiki46 clears its trigger bits (tagalong_event_flags) when
  the module changes, as traced in r46; whether a cartridge continue keeps
  them was not traced (OURS?).
- Bot work (scratch only): farm47 (targets only rupee packs, waypoints
  kept off Kiki's cell -- one early run walked over it and paid the 10
  Rupees unplanned), house trips; pod47b's tokens; the switch step aims at
  the cartridge's probe point (first try stood 4 px low and missed it).
- [ ] 47.5 The door's four map16 steps and sounds, Kiki's blue / brown
  palette: not done (the time went to the farm and the palace).

Checkpoints (`r47/out/`, harness, real input): `ck_r47_farm_done`,
`ck_r47_kiki_joined`, `ck_r47_kiki_paid10`, `ck_r47_pod_open`,
`ck_r47_pod_in`, `ck_r47_pod_r09`, `ck_r47_pod_09key`, `ck_r47_pod_3a`,
`ck_r47_pod_2a`, `ck_r47_pod_2a_ch` (0x2A after the block pushes).

Tests: new `zelda_alttp_r47_test` (leaving a room drops the overworld
list, the grid state and the drops; the prize's arrows become rupees
without the bow and stay with it; 7 checks).
All 55 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80 overworld
areas (`AUDIT=rooms|ow run.sh audit` in r47, cacheVersion 48;
`out/audit/mains.txt` copied from r46).

## Round 48 (2026-11-14)

The Palace of Darkness past room 0x2A with real input: the arena's key, the
Stalfos basement's key, the dungeon warp tile (new `Warp48.lua`). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r48/` (the r47 kit with r48 paths;
`harness/pod48.lua` / `pod48b.lua` the step list (new tokens: `N<f>` wait, `BL`
blocks, `R` / `A` / `B` buttons, `WD` warp probe, `X<dx>` / `XT<x>` steps,
`OUT` leave the palace; `@` also outdoors), `look48.lua` (attribute map,
blocks, actors, chests, `VIEWS` look-only shots), `ledge48.lua`, `hdr48.lua`
(headers, hole rooms, special tiles per PoD room), `locks48.lua`,
`packs48.lua` (prize packs), `farm48.lua` (farm47 with `FARMBOMBS`);
`py/amap.py` (attribute map as text), `py/blto.py` (calls to a function),
`py/litref.py` (literal references); `real/` the real app).
**cacheVersion 49** (Warp48's import).

- [x] 48.1 **Room 0x2A's "block puzzle" is a one-way shortcut, not a bug.**
  The new-game block table (0x163430) holds one block for 0x2A, (160,304);
  (176,288) is a fixed block (attribute 0x27). From the south-west stairs
  the block only moves east, onto the cell beside the fixed one, and blocks
  are pushed once: from that side the way stays shut (from the arena side a
  push west opens it). The two key chests are reached otherwise: the
  "bridge" chest (368,352) from room 0x3A's north-east door, the "ledge"
  chest (448,360) from room 0x2B's side behind a bombable door (0x2E).
  Enemies: six Hardhat Beetles (0x26; one with 32 hp / ai 1), the bumper
  0x93, the crystal switch 0x1E.
- [x] 48.2 **The west ledge of 0x2A (attribute 0x2A at column 15) lands in
  the pit on the cartridge too.** Traced the horizontal ledge hop: TileDetect's
  jump table 0x0816832C (0x2A / 0x2B -> 0x080A0B78: +0x1800 |= bit), the
  X-collision 0x08095D88 (RunLedgeHopTimer 0x0809A5BC, sound 4, state 0xC),
  the landing search 0x08093128 (8 steps of 8 px, kStep 0x167C9C; a spot is
  landable when the second-half table sets +0x17D2 / +0x17EC / +0x17E8 /
  +0x17D0 / +0x1714 for all three probes; else +32; then +16; speeds by
  distance 0x167CA8 / 0x167CC0) and the landing 0x08099598 (a pit under
  Link -> state 1, the fall). The pit handler 0x080A0718 sets +0x1714, so a
  pit cell IS a landing spot: from the ledge Link lands in the pit (0x2A's
  pits hurt: 8 damage, back on the ledge). The port's OURS hop (first spot
  8-64 px on) gives the same result here; left as it is (OURS: the hop's
  arc and length are still not the cartridge's tables).
- [x] 48.3 **Game fix: the dungeon warp tile (attribute 0x4B) did nothing**
  (new `Warp48.lua`). Traced: 0x4B -> 0x080A0C90 (+0x17E8 = bit << 4); the
  nearby probe 0x0809EEB4(0) (Link + kNearbyX/Y[0], 0x081681D4 / 0x0816817C)
  -> 0x0809EFCA: +0x17E8 & 0x10 and Link on the tile's grid ((y + 8) & 15
  and x & 15 not 4..11), no blink (+0x17AA), no auxiliary state (+0x1702),
  indoors -> sound 0x4C (0x0809F028), +0x1719 = 0, module 7 submodule 0x16
  (0x080713A0, steps 0x0814CD50: step 2 loads the room), the new room =
  (room & 0xFF00) | +0xCF0 (header byte 9, the holes' room: 0x08080F18).
  Link keeps his spot. The PoD rooms with warps: 0x0A -> 0x09, 0x09 ->
  0x4B, 0x4B -> 0x09, 0x0B -> 0x6A (0x7B also has one). Probe offsets and the sound id are
  read at import. OURS: the fade (16 frames to black and back).
- [x] 48.4 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r47_pod_2a` -> back down to 0x3A (`ck_r48_pod_3a_push`) -> the
  north-east column's block (384,224) pushed east into the pit (21 frames,
  then it slides and falls) -> north through the door -> 0x2A's bridge strip
  (`ck_r48_pod_2a_bridge`) -> the **bridge chest: small key**
  (`ck_r48_pod_2a_key1`) -> back to 0x3A, into the pit where the block fell
  -> **0x0A, the Stalfos basement: small key** (`ck_r48_pod_0a_key2`, 2
  keys) -> lift the pot south of the warp, step on it -> **0x09**
  (`ck_r48_pod_09_warp`) -> 0x09's warp -> **0x4B's north-east quarter**
  (`ck_r48_pod_4b_in`). 0x4B's way on (its south door, type 0x28) is a
  bombable door: 0x08086054 treats 0x28 / 0x2A / 0x2E as bomb doors; the
  0x3A floor (0x62) and the 0x2A ledge chest also need bombs. Link has 0
  bombs and 0 Rupees (Kiki took them). Back out (0x4B's block east, its warp
  -> 0x09 `ck_r48_pod_09_back` -> 0x4A `ck_r48_pod_4a_back` -> outside
  `ck_r48_pod_out`); a bomb farm on area 0x5E's three Hinoxes (0x11, pack 4
  = bombs) made no kill in 10 rounds and was stopped. Not reached: the big
  key, the Magic Hammer, the dark rooms, Helmasaur King, the crystal.
  Real app (`real/runreal.sh r38ck`, current import, window shots
  `real/shots/r48real_*_win.png`): `ck_r48_pod_0a_key2` -> the pot, the
  warp -> 0x09: passed.
  Health floor (harness aid) absorbed: 72 + 40 (0x3A's Terrorpins 0x8E and
  0x24s), 116 (the OUT planner's detour), 380 (the Hinox farm); route
  total ~230 without the farm.
- Bot work (scratch only): the planner says "no plan" from some spots on
  narrow strips (0x2A's bridge, 0x3A's column after the push; worked
  round with held keys); `B.openChest` failed there (opened with `R` by
  hand); the planner does not push blocks into pits, take warps or know
  bomb doors; one `OUT` run walked through 0x3A into a pit (0x0A).
- Seen, not followed up: the port's door type 0x28 is kind "other" (drawn
  closed); its bombing open is not checked (no bombs). Room 0x0A's tag 0x27
  (TriggerChest): the chest is in the GBA's pre-rendered map, the port
  shows it from the start as well.
- [ ] 48.5 The PoD door's four map steps and sounds, Kiki's palette, Kiki's
  paid state over a cartridge continue: not done.

Checkpoints (`r48/out/`, harness, real input): `ck_r48_pod_3a_push`,
`ck_r48_pod_2a_bridge`, `ck_r48_pod_2a_key1`, `ck_r48_pod_0a_key2`,
`ck_r48_pod_09_warp`, `ck_r48_pod_4b_in`, `ck_r48_pod_09_back`,
`ck_r48_pod_4a_back`, `ck_r48_pod_out`.

Tests: new `zelda_alttp_r48_test` (the warp tile: on / off the grid, the
probe point, the header's room, Link's spot, the level, the fade's length;
11 checks). All 56 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80
overworld areas (`AUDIT=rooms|ow run.sh audit` in r48, cacheVersion 49;
`out/audit/mains.txt` copied from r47).

## Round 49 (2026-11-14)

Bombs for the Palace of Darkness, the big key, the map, the Arena's ledge key.
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r49/` (the r48 kit with r49
paths; `p.sh <log> <ck> "<steps>"` runs `harness/pod49.lua` + `pod49b.lua` from a
checkpoint; new tokens: `POTS` (pots and their secrets), `LP<i>[dir]` (lift pot i),
`PICK` (walk over the drops), `MENU<slot>` (SELECT menu, cursor to a slot),
`BOMB<dir><n>` (lay a bomb with A, walk off, wait out the blast), `WT<x>,<y>`,
`WARPTRY<x>,<y><dir>` (knock foes off a warp tile, step on), `EYE` (Eyegores:
green by sword with the eye open, red by arrows); `dbg49*.lua`, `hop49.lua`
probes; `py/lit16.py`; `real/` the real app). **cacheVersion 49** (no import
change).

- [x] 49.1 **The bombs: no loss, Link never had any.** Every checkpoint since
  round 19 has bombs = 0; nothing on the route ever added one (no save loss, no
  max-bomb rule involved: the bag holds kMaxBombs[0] = 10). The cheapest honest
  source is the palace itself: pot secret 0x0A (kSpawnSecretItems -> 0xDC, one
  bomb) under 4 pots of 0x4A (3 on the east side), 1 in 0x0A's west corridor, 2
  in 0x2B's lower hall (plus 2 arrow pots), 2 in 0x0B, 4 in 0x1A. They come back
  on every palace entry (pots_revealed_in_room is cleared by
  Dungeon_LoadEntrance; Interior.revealed). No farm needed.
- [x] 49.2 **Game fix: a bomb / arrow pick-up never fills past the bag**
  (`Drops.lua` absorb). Traced: the absorb 0x080CF5C8 adds 1 / 4 / 8 (0x173083)
  to the bomb filler 0x02002355 (arrows 0x02002356, 0x080CF5A0 path); the HUD's
  refill 0x080A72F4 moves it into the count one a frame and stops at
  kMaxBombs[0x02002350] (0x16B588; arrows 0x16B598 / 0x02002351). The port
  added the whole pack (13 bombs in a 10 bag was possible). OURS: the count
  moves at once, not one a frame.
- [x] 49.3 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r48_pod_4a_back` -> 0x4A's east pots: 3 bombs (`ck_r49_pod_4a_bombs`) ->
  0x09 -> warp -> 0x4B (`ck_r49_pod_4b_in`) -> 0x4A -> 0x3A's west column:
  bomb on the cracked floor 0x62 (Mech27.bombFloor; the hole) (`ck_r49_pod_3a_floor`)
  -> fall into **0x0A's west corridor** (`ck_r49_pod_0a_west`) -> its bomb pot ->
  the locked stairs (key door 0x20, 1 key) -> **0x3A's centre: the big key**
  (`ck_r49_pod_3a_center`, `ck_r49_pod_3a_bigkey`) -> hop the centre's east
  ledge (0x2A) into the pit -> 0x0A's main room (`ck_r49_pod_0a_main`) -> lift
  the pot, past the two Terrorpins onto the warp -> 0x09 (`ck_r49_pod_09_warp2`)
  -> 0x4A -> 0x3A -> 0x2A (`ck_r49_pod_2a_back`) ... the Arena's middle is not
  reachable from its south-west side (49.5), so -> 0x3A -> 0x4A (`ck_r49_pod_4a_top`)
  -> 0x09 -> 0x4B (`ck_r49_pod_4b_in2`) -> **bomb door 0x28 east** (`ck_r49_pod_4b_u`)
  -> the U corridor -> **bomb door 0x28 west** (`ck_r49_pod_4b_nw`) -> the
  Eyegores (two green by sword, the red one by 10 arrows; tag 1 opens the north
  shutter) -> 0x3B (`ck_r49_pod_3b`) -> 0x2B's lower hall (`ck_r49_pod_2b`) ->
  2 bomb pots, 2 arrow pots, **the map** (`ck_r49_pod_2b_items`) -> **bomb door
  0x2E west** -> **0x2A's ledge chest: small key** (`ck_r49_pod_2a_ledge`; 2
  keys, big key, map, 2 bombs, 10 arrows). Bombs used: 4 (two 0x4B doors, the
  0x3A floor, the 0x2B door). Health floor absorbed ~744 (344 + 276 crossing
  0x3A twice: Terrorpins 0x8E / Hardhat Beetles; 92 at 0x0A's warp; 24 + 8 on the
  way). No other game bug found on this stretch.
  Real app (`real/runreal.sh r38ck`, current import, window shots
  `real/shots/r49real_*_win.png`): `ck_r49_pod_3a_floor` -> the menu, the bomb,
  the floor's hole, the fall into 0x0A: passed.
- Bot / harness (scratch only): r48's health floor cut a hit to 0 damage, which
  left no blink: Terrorpins then hit every frame (2500 "absorbed" in one run);
  now the hit lands in full and health is put back to the floor. The bomb
  wait was too short (the blast at itl 7 comes ~200 frames after the lay). The
  planner still does not take warps, bomb doors or ledge hops (scripted).
- [ ] 49.4 Not reached: the Magic Hammer (0x1A's big chest), the dark maze
  (0x19, lamp), Helmasaur King (0x5A), the crystal.
- [ ] 49.5 **Open: how the Arena's middle (0x2A) is entered.** From the known
  part every way into {0x2A middle / right platform / top corridor, 0x2B upper
  hall, 0x1A, 0x1B, 0x0B, 0x6A} is one-way: the south-west nook's block (one
  push east keeps it shut, r48), the west ledge (0x2A, floor arrow "->"), the
  bridge's north ledge (0x28, arrow "^"), 0x2B's upper hall (ledge 0x28 down
  only). The port's hops land in the pits after 24 px (`hop49.lua`: bridge
  north 312 -> 287; west ledge 104 -> 128), and 0x2A is in
  kDungeonPitsHurtPlayer (0x1676FE): 8 damage, back. Traced so far: the
  horizontal search 0x08093128 (8 steps of kStep 0x167C9C, stops when all three
  probes of TileDetect_X 0x0809EB58 set one of +0x17D2 / +0x17EC / +0x17E8 /
  +0x17D0 / +0x1714, then +16; else orig +32 +16), the vertical one 0x080932C8
  (no step limit, same flags, TileDetect_Y 0x0809EA40); indoor attribute
  handlers 0x0816832C (0x00 -> 0x080A0678 `bx lr`: plain floor sets none of
  them; 0x20 pit -> +0x1714 unless +0x1783 (Somaria) ; 0x0A / 0x48 / 0x4A /
  0x8E / 0x8F -> +0x17D2; 0x40 -> +0x17E8; 0x08 -> +0x17D0). Read literally the
  vertical search would never end over plain floor, so a piece is missing (which
  layer's table the probes read during a hop, +0xA10 at 0x080A04AC, or another
  flag); the speed tables 0x167CA8 / 0x167CC0 go to 184 px, so long hops exist.
  The floor arrows say the hops cross the pits. Not changed (not traced to the
  end); next round: finish this trace, then hop into the Arena, hit the crystal
  switch (0x1E at 256,368; the blue pegs 0x67 are up, the orange 0x66 down), up
  to the top corridor -> 0x1A.
- [ ] 49.6 The PoD door's map steps and sounds (r46): not done.

Checkpoints (`r49/out/`, harness, real input): `ck_r49_pod_4a_bombs`,
`ck_r49_pod_4b_in`, `ck_r49_pod_3a_floor`, `ck_r49_pod_0a_west`,
`ck_r49_pod_3a_center`, `ck_r49_pod_3a_bigkey`, `ck_r49_pod_0a_main`,
`ck_r49_pod_09_warp2`, `ck_r49_pod_2a_back`, `ck_r49_pod_4a_top`,
`ck_r49_pod_4b_in2`, `ck_r49_pod_4b_u`, `ck_r49_pod_4b_nw`, `ck_r49_pod_3b`,
`ck_r49_pod_2b`, `ck_r49_pod_2b_items`, `ck_r49_pod_2a_ledge`.

Tests: new `zelda_alttp_r49_test` (pick-ups stop at the bag: bombs by upgrade,
arrows, a count already above the bag; 7 checks). All 57 `zelda_alttp_*` files
pass. Audits 304/304 rooms, 80/80 overworld areas (`AUDIT=rooms|ow run.sh
audit` in r49, cacheVersion 49).

## Round 50 (2026-11-14)

The Arena's ledge hops, the Magic Hammer, the way to Helmasaur King's door.
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r50/` (the r49 kit with r50
paths; `p.sh <log> <ck> "<steps>"`; new tokens in `harness/pod49b.lua`:
`G<dir><n>` (walk, the sword at foes within 40 px), `T<dir><n>` (walk until
the room changes: stairs), `YT<y>`, `TERR` (Terrorpins: hammer flip, sword),
`HAMK<type>` (foes struck with the selected item), `HOPTRY<x>,<ymin>` (hop
again until Link lands past ymin), `CLR<x>,<y>,<r>`, `SHOOTD<type>`, `PEG`,
`ITEM<id>` (unreliable: curItem changes on close; use `MENU<slot>`);
`harness/walk50.lua` (hold a way, log Link / ledge timer / foes),
`dbg50*.lua` (locks, warp cells, `DUMP=1` attribute dump to `out/attr_<room>.txt`,
headers), `py/hopsim.py` (the state-6 flight); `real/` the real app).
**cacheVersion 50** (Hop50's import).

- [x] 50.1 **Game fix: the indoor ledge hop is a fixed flight, not a landing
  search** (new `Hop50.lua`). The search r48 / r49 traced (0x08093128,
  0x080932C8, 0x08093604, 0x0809A338) is the OUTDOOR hop: the X collision
  0x080962E0 calls 0x08095AD4 (-> 0x08095D88) only when +0x9B2
  (player_is_indoors) is 0, the Y collision 0x08094DC0 calls 0x08094538 (->
  0x080948A0) likewise; indoors plain floor 0x00 sets no TileDetect flag
  (0x0816832C[0] = 0x080A0678 `bx lr`; outdoors 0x0816872C[0] = 0x080A0A98
  sets +0x17D2), which is why those searches never ended "over floor".
  Indoors: X 0x0809675A ([+0x1800] & 7 == 7, all three probes on 0x2A /
  0x2B), Y 0x080952EE ([+0x17FF] & 7 == 7, on 0x28), RunLedgeHopTimer
  0x0809A5BC, +0xB22 += 1, +0x1702 = 2, sound 4, then 0x0809A670 (x) /
  0x0809A24C (y): index +0x9B5 but 0 while +0xB22 != 0 (just raised), speed =
  tab[i] (0x08167F99 x / 0x08167ED0 y, 1/16 px, negative left / up), z speed
  tab[3 + i], +0x16F8 timer tab[6 + i], state 6. State 6 (0x08099C90): gravity
  2 (0x0809E624 / 0x0809A138, `movs r2, #2` at 0x0809E626), timer down, then
  landing when (z & 0xFE) - 1 > 0x7E with z speed < 0; the move 0x080978AC
  (speed >> 4 + the carry of (speed & 15) << 4); z <= 0 clamps to 0
  (0x0809A08E, the pit check 0x0809EDA4 there). Both hops fly about 52 px:
  the Arena's bridge north ledge 312 -> 259 (floor past the pits), the top
  corridor's 0x28 down onto the middle platform, the 0x3A centre's east
  ledge 283 -> 333 (still the pit to 0x0A). Tables (literal pools at
  0x0809A6AC / 0x0809A288) and the gravity immediate are read at import.
  OURS: the sub-pixel bytes start at 0; the recoil state's wall bounce
  (0x0809A7C4) is not used for hops; the trigger (20 frames, round 11) kept.
- [x] 50.2 **Game fix: a bombed wall stayed shut from the other room**
  (`Interior.adjacentOpened`). GBA 0x08081308 (with 0x0808125C: the
  neighbour's save word & 0xF000) marks every matching door slot open except
  type 0x30 and the shutters 0x18 / 0x44; the port only did key doors. The
  Arena's east nook (0x2E) is open again from 0x2A after the bombing in 0x2B.
- [x] 50.3 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r49_pod_2a_ledge` -> 0x2B -> 0x3B (`ck_r50_pod_3b`) -> 0x4B, its block,
  the warp -> 0x09 -> 0x4A (`ck_r50_pod_4a`) -> 0x3A (`ck_r50_pod_3a`): the
  north-east block pushed into the pit, up the column -> 0x2A's bridge
  (`ck_r50_pod_2a_bridge`) -> **the north hop over the pits**
  (`ck_r50_pod_2a_hop`) -> the in-room stairs, the top corridor
  (`ck_r50_pod_2a_top`) -> the key door -> **0x1A** (`ck_r50_pod_1a_in`):
  the bridge crumbles (overlord 0x0A, 160 frames then a tile each 16): one pot
  lifted at the foot, the Mini Helmasaurs swatted, up to the top area
  (`ck_r50_pod_1a_top`, 4 bombs) -> the west key door -> **0x19, the dark
  maze** (`ck_r50_pod_19_in`) -> its east bomb wall -> 0x1A's nook
  (`ck_r50_pod_1a_nook`) -> **the big chest: the Magic Hammer**
  (`ck_r50_pod_1a_hammer`) -> back through 0x19 (`ck_r50_pod_1a_back`) -> the
  top-right area, the Terrorpins flipped with the hammer and killed, the
  spiral stairs -> **0x6A** (dark, `ck_r50_pod_6a_in`): Helmasaur King's big-key
  door is at the top of 0x6A's middle, which is walled off (0x27) from the
  stairs' sides; 0x0B's warp tile leads into it (0x0B's header byte 9 =
  0x6A, the only room with that). 0x0B is reached from 0x1B, 0x1B from
  0x2B's upper hall, that from 0x2A's east door behind the blue pegs, which
  the crystal switch lowers. So back: 0x6A -> 0x1A (`ck_r50_pod_1a_ret`) ->
  the crumbling bridge down -> 0x2A (`ck_r50_pod_2a_ret`) -> the top
  corridor's ledge hop onto the middle platform (`ck_r50_pod_2a_mid`).
  Stopped there: the Hardhat Beetles (0x26) knock Link into the hurting pits
  and the bumper (0x93) sits between him and the crystal switch; the arrow
  shots at the switch (256,368) did not land before the round ended.
  Health floor absorbed on the kept route ~380 (108 in 0x4B, 168 crossing
  0x3A, 8 the dark maze, 8 0x1A's Terrorpins, 88 the platform hops and the
  beetles there); discarded bot runs not counted (one that shot arrows at
  beetles absorbed 384).
  Real app (`real/runreal.sh r38ck`, `real/reimport.sh` first: cache
  `zelda-cache:alttp:v50`, hop50 in the generated tables; window shots
  `real/shots/r50real_*_win.png`): `ck_r50_pod_2a_bridge` -> the north hop
  391 -> 240, the stairs: passed (same positions as the harness). Seen, not
  followed up: from that checkpoint the real app's window shows the view of
  another part of the map (the camera one screen off; the r49 checkpoint
  `ck_r49_pod_3a_floor` draws right) -- likely the checkpoint scene's
  adapter, not traced.
- Bot / harness (scratch only): the planner has no plan through 0x1A's 0x81
  corridor and 0x2A's narrow strips (walked by hand); loading a checkpoint
  respawns the room's foes (1A's Terrorpins); holding up past a stair
  transition takes the stairs back (`T` token stops at the room change); the
  r47 attribute dump of 0x2A is one column off (dump again with `DUMP=1`).
  Arrows: Hardhat Beetles ignore them (15 arrows spent in one discarded run).
- Seen, not traced (OURS?): Link is hit by ground foes during the hop (the
  SNES Link hit box has no z, so likely right).
- [ ] 50.4 Not reached: the crystal switch, 0x2B's upper hall, 0x1B, 0x0B,
  0x6A's middle, Helmasaur King, the crystal.
- [ ] 50.5 The PoD door's map steps and sounds (r46), the filler counting one
  a frame (r49): not done.

Checkpoints (`r50/out/`, harness, real input): `ck_r50_pod_3b`, `ck_r50_pod_4a`,
`ck_r50_pod_3a`, `ck_r50_pod_2a_bridge`, `ck_r50_pod_2a_hop`,
`ck_r50_pod_2a_top`, `ck_r50_pod_1a_in`, `ck_r50_pod_1a_top`,
`ck_r50_pod_19_in`, `ck_r50_pod_1a_nook`, `ck_r50_pod_1a_hammer`,
`ck_r50_pod_1a_back`, `ck_r50_pod_6a_in`, `ck_r50_pod_1a_ret`,
`ck_r50_pod_2a_ret`, `ck_r50_pod_2a_mid` (latest: on the Arena's middle
platform with the hammer, 5 bombs, 15 arrows, 0 keys).

Tests: new `zelda_alttp_r50_test` (the hop's flight: one axis only, lands at
z 0 after the timer, 1/16 px with the carry, left / right / up / down; no
tables no hop; doors opened next door: key, bombed wall, not a shutter, not
an unopened wall; 16 checks). All 58 `zelda_alttp_*` files pass. Audits
304/304 rooms, 80/80 overworld areas (`AUDIT=rooms|ow run.sh audit` in r50,
cacheVersion 50).

## Round 51 (2026-11-15)

The Arena's crystal switch, 0x2B -> 0x1B -> 0x0B, Helmasaur King, the first
crystal. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r51/` (the r50
kit with r51 paths; checkpoints now `ck_r51_pod_*`; new legs:
`harness/arena51.lua` (walk to TX,TY avoiding pits and the bumper, sword a
Hardhat Beetle only when the push-back lands on floor), `shoot51.lua` (face
SDIR, fire, log arrows / switch), `push51.lua` / `pushh51.lua` (the movable
statue), `boss51.lua` (Helmasaur King: hammer on the mask, then the sword),
`collect51.lua` (heart container, prize), `legs51.lua` (PODSTEPS2/3/4: a
step list after other legs), `cam51.lua`, `chests51.lua`, `hdr51.lua`,
`box51.lua`, `arrdbg51.lua`; `py/amap51.py` (attribute map as ASCII);
`s2b2.sh` (the 2B -> 0B chain)). **cacheVersion 50** (no import change:
Arena51's extract reads nothing; no re-import needed).

- [x] 51.1 **Game fix: arrows / the tools' ancillae hit crystal switches**
  (new `Arena51.lua`). GBA Ancilla_CheckSpriteCollision (loop 0x080C09FC):
  every sprite in state > 8 ([+0xFA2]) on the ancilla's floor ([+0x10F2] ==
  [+0xE47]); arrows (type 9) and the hookshot (0x1F) every frame, others on
  (frame ^ slot) & 3 == 0; defl bit 2 ([+0xE75]) or ancilla [+0xA74] == 0.
  No "is an enemy" test; the hit (0x080C0AE8 -> 0x080C0B7C -> damage
  0x080C4E94) toggles the switch (Dungeons26.hitSwitches). The port's arrow
  (Items.arrowFrame) and Tools.spriteHit only looked at Actors.fights types,
  so arrows flew through the switch. Arena51 wraps both and, while they run,
  Actors.fights also answers true for 0x1E. The Arena's switch (256,368)
  sits across the pits from the middle platform: one arrow from (256,296).
- [x] 51.2 **Game fix: no sprite contact during a ledge hop.** GBA
  Sprite_CheckDamageToLink 0x080C46EC: after the box test, no contact while
  +0x1702 (link_auxiliary_state) != 0 (0x080C47F4); the hop sets 2
  (0x0809A5BC), a hit sets 1 (Sprite_AttemptDamageToLinkPlusRecoil
  0x080C3BD0: incapacitated 19, recoil 24, aux 1); harmless sprites (flags2
  bit 7: bumper, switch) return the box test before it (0x080C47E2).
  `Actors.lua` generic contact tests lk.hop; Arena51 wraps Dungeons26.contact.
  The beetles knocked Link into the pits mid-hop (r50 "seen, not traced").
  Checked, unchanged: Hardhat Beetle (HelmasaurHardHatBeetleCommon
  0x080D84B0: inactive / sub2++ / ReturnIfRecoiling 0x080C1FD0 /
  CheckDamageToAndFromLink 0x080C5044 / move / tile collision / target every
  32) and the bumper (0x080D8C24: harmless touch, cancel dash 0x08093078,
  projection 0x30 + kBumper vels by joypad 0x545, incapacitated 0x14, sound
  0x79) match the port; the knockback into the pits is the cartridge's.
- [x] 51.3 **Game fix: walking down onto down stairs** (`Interior.lua`
  staircase). GBA Dungeon_DetectStaircase 0x08084A20: the first tile at
  ((y + kTab[dir]) & 0x1F8) << 3 | x >> 3, + 0x80 (two rows) walking down;
  the second tile at 0x0200CBE0 + the position BEFORE the two-row step
  (0x08084A92: r4 = r1), i.e. one row above the stair tile walking down. The
  down stairs 0x12E / 0x12F write their number over the 0x26 row (0x08081E86
  .. 0x08081EDE, the 0x3434 restart), so the port (reading the row below)
  never took them: 0x1B's stairs to 0x0B. Round 11's 0x39 special case is now
  what the rule does anyway (kept, harmless). Up stairs unchanged; walking
  down onto up stairs no longer takes them (the GBA does not either).
- [x] 51.4 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r50_pod_2a_mid` -> arena51 to (256,296), one arrow: the switch
  (blue pegs down) -> 0x2B's upper hall (`ck_r51_pod_2b_upper`) -> its
  shutter is tag 0x16 (hold): the three pots of the right alcove lifted, pot
  4 hides the switch (secret 0x88, 176,80), the movable statue (0x1C) pushed
  right then up onto it (`ck_r51_pod_2b_statue`) -> 0x1B (`ck_r51_pod_1b_in`):
  Eyegores (greens by sword, the red by 4 arrows shot only with its eye
  open) -> the shutter -> the crystal switch (112,64) by sword (pegs back) ->
  an arrow on the eye statue (0x38, 256,64): the moving wall (tag 0x1C,
  ~1000 frames) -> the down stairs -> **0x0B** (`ck_r51_pod_0b_in`). There:
  0 keys and the only way on is a key door (288,136): the r50 route had
  skipped two keys (0x19's maze chest 448,424, 0x6A's 448,368). Taken
  again from `ck_r50_pod_6a_in`: 0x6A's chests (key, rupees) -> 1A
  (`ck_r51_pod_1a_ret2`) -> the pots at the crumbling bridge's top and foot
  -> 0x2A (`ck_r51_pod_2a_ret2`) -> the hop (`ck_r51_pod_2a_mid2`) -> the
  switch -> 0x2B (`ck_r51_pod_2b_upper2`) -> statue -> 0x1B (`1b_in2`,
  `1b_switch2`) -> 0x0B (`ck_r51_pod_0b_in2`, 1 key) -> an arrow east from
  between the peg rows on 0x0B's switch (448,64) -> the key door
  (`ck_r51_pod_0b_key`) -> the dark west side down into the Terrorpin room
  (hammer flips + sword; tag 3 opens the shutters) -> east -> the warp ->
  **0x6A's middle** (`ck_r51_pod_6a_mid`) -> the big-key door -> **0x5A**
  (`ck_r51_pod_5a_in`) -> **Helmasaur King**: hammer on the mask, sword
  after (788 frames, no health floor needed) -> heart container (48 -> 56)
  -> the crystal -> **the Dark World** (`ck_r51_pod_dw_pod_done`, area 0x5E).
  Health floor absorbed on the kept segments ~80 (16 1A, 40 2B/1B, 16 0x0B,
  8 0x6A); discarded runs not counted (one 0x0B run with the wrong item
  selected absorbed ~6000 to Terrorpins). Note: every checkpoint load refills
  health (seg40, as before).
  Real app (`real/runreal.sh r38ck`, current cache v50, window shots
  `real/shots/r51real*_win.png`): `ck_r51_pod_1b_switch2` -> the eye arrow,
  the wall, the down stairs into 0x0B: passed; `ck_r51_pod_0b_in2` -> the
  arrow on 0x0B's switch, pegs toggle: passed.
- [x] 51.5 **The real-app camera one screen off (r50): harness only.**
  `harness/ck25.lua` entered the entrance room, drew a frame (real app), then
  loadRoom'ed the checkpoint's room without clearing `g.roomImages`: the old
  room's pictures under the new camera. Game code clears it on every room
  change; ck25 now does too (`real/shots/r51cam2_p01_2A_win.png` right,
  `r51cam_p01_2A_win.png` the old fault).
- Bot / harness (scratch only): `MENU<n>` wants the menu cursor value
  (hammer = 14, bow = 1), `ITEM` stays unreliable; the planner cannot path
  into door cells or up the 0x1B stairs (use H tokens); checkpoint loads
  respawn foes and forget room state (0x1B's moved wall, Eyegores), so the
  kept route is run in continuous chains; pit damage bypasses hurtLink, so
  arena51 floors it itself (counted).
- Seen, not changed (OURS): the port freezes everything during Link's fall
  into a pit (D.pitFrame returns before sprites / ancillae); on the GBA the
  fall is a Link state while sprites run. The moving wall's speed (0x2200
  sub-px a frame, ~17 s for 0x1B) was not re-traced.
- [ ] 51.6 The PoD door's map steps and sounds (r46), the bomb filler one a
  frame (r49): not done.

Checkpoints (`r51/out/`, harness, real input): `ck_r51_pod_2a_plat`,
`ck_r51_pod_2b_upper`, `ck_r51_pod_2b_statue`, `ck_r51_pod_1b_in`,
`ck_r51_pod_1b_eyes`, `ck_r51_pod_1b_switch`, `ck_r51_pod_1b_wall`,
`ck_r51_pod_0b_in`, `ck_r51_pod_1a_ret2`, `ck_r51_pod_2a_ret2`,
`ck_r51_pod_2a_mid2`, `ck_r51_pod_2b_upper2`, `ck_r51_pod_1b_in2`,
`ck_r51_pod_1b_switch2`, `ck_r51_pod_0b_in2`, `ck_r51_pod_0b_key`,
`ck_r51_pod_0b_terr`, `ck_r51_pod_6a_mid`, `ck_r51_pod_5a_in`,
`ck_r51_pod_dw_pod_done` (latest: Dark World outside the Palace of Darkness,
crystal 1, 56 max health, hammer, 7 bombs, 8 arrows).

## Round 52 (2026-11-15)

Towards the Swamp Palace: the cartridge wants the flippers first (King Zora,
500 rupees), so the round went after rupees and met four port gaps on the
way. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r52/` (the r51 kit
with r52 paths; checkpoints now `ck_r52_*` (pod49.lua's `CKPFX`); new:
`o.sh <log> <ck> "<seg> ; <seg>"` with `harness/ow52.lua` -- segments run as
pod49b room tokens while Link is in a room, else overworld tokens `G<x>,<y>`
(planner walk), `E<n>` (entrance), `M` (mirror), `HAM` (hammer), `PAD<x>,<y>`,
`X<dx>`, `Y<dy>`, `MENU<n>`, `H<d><n>`, `@name`, `SH<name>`; `pr.sh <log> <ck>
<probe>`; probes `route52.lua` (BFS waypoints, `PEGS=1` real pegs only),
`owmap52.lua` (reach map PNG), `m16scan52.lua` / `m16at52.lua` (map16 tiles),
`attrbox52.lua`, `iattr52.lua`, `imap52.lua` (room walk map), `objs52.lua`,
`find2c52.lua`, `kzlist52.lua`, `fall52.lua`, `bombdbg52.lua`,
`liftdbg52.lua`, `probe52a/b/c.lua` (chests, rupee rooms, entrances);
`py/ptrfind.py`, `py/findlit2.py`, `py/findstate.py`). **cacheVersion 51**
(Zora52 / Receipt52 read tables at import): harness store re-imported
(REIMPORT=1) and the real app cache re-imported (`real/reimport.sh`).

- [x] 52.1 **Game fix: the room keeps running while Link falls into a pit**
  (new `Fall52.lua`). The fall is a Link state, not a submodule:
  LinkState_FallingIntoHole is entry 1 (0x0809AD6C) of the player handler
  table 0x081680AC, called by Link_ControlHandler 0x0809DA4C (table call
  0x0809DBA6) from Link_Main 0x0809E2FC, from the dungeon's submodule 0
  (0x0806CE1C, table 0x0814CE34). Module07_Dungeon calls Sprite_Main
  0x080C1B40 after the submodule every frame (0x08070890); the sprites'
  pause test reads the submodule (+0x9AD), 0 during the fall. The port's
  D.pitFrame returned before the actors and ancillae: everything froze for
  the fall's 60 frames. Now they run during the six steps (not while Link
  drops into the room below). Link_ControlHandler still applies
  link_give_damage (+0x1805) in any state (0x0809DA5E..0x0809DB86); OURS: a
  knockback taken mid-fall is dropped when the fall lands in another room.
  Harness: the Arena's Hardhat Beetles move during the fall (fall52.lua).
- [x] 52.2 **Game fix: chests with rupees, bombs and arrows gave nothing**
  (new `Receipt52.lua`). Sahasrahla's 2 x 50 rupees left the count at 92.
  G:getItem only handled the positive kValueToGiveItemTo writes (Gear.lua)
  and wrote receipt 0x43 / 0x44's value into the menu byte 0x56. GBA:
  AncillaAdd_ItemReceipt 0x080AC8AC (positive values stored; 0x43 / 0x44
  store 1 / 10 at the arrow filler 0x02002356; 0x27 / 0x28 / 0x31 add 1 / 3
  / 10 to the bomb filler 0x02002355, at most 0x63, 0x080ACB94..0x080ACBCE);
  the rupees 0x080AD05C (switch on item - 0x34, jump table 0x080AD08C):
  0x16E525[item - 0x34] for 0x34..0x36, [(item + 0xC3) & 0xFF] for 0x40 /
  0x41, [2] for 0x47, 0x12C for 0x46 (0x080AD0F4 / 0x080AD0FC), then
  AddRupees 0x080AA83C (the goal 0x02002340). Hud_RefillLogic 0x080A72F4 /
  0x080A7316: the fillers count down one a frame and the bombs / arrows go
  up to kMaxBombs / kMaxArrows[upgrade] (this is the r49 "one a frame"
  item for receipts; pick-ups in Drops.lua still add at once).
- [x] 52.3 **Port: King Zora and the flippers he throws** (new `Zora52.lua`,
  sprite 0x52; not reached in play, see 52.6). Prep 0x080E9998 (gone with
  the flippers), main 0x080E99CC (draw 0x080E9718, states 0x08177AB4: wait
  0x080E9268 -- Link within (x - kx + 16) < 32, (y - ky + 48) < 80, other
  sprites killed; rumble 0x080E937C -- Link held (+0x1770); rise
  0x080E93F4; talk 0x080E945C -- messages 0x145 / 0x146 / 0x147 / 0x148 /
  0x149 at timer 0x50..0x4D, the price from the literals at 0x080E94F0 /
  0x080E9508; dive 0x080E9568), the gift 0x080E9900 (sprite 0xC0 with
  sprite_E 0x1E: z speed 0x20, y speed 0x10) and its bounce in 0x080F7558
  (0x08179C3C, picked up on the ground: Link_ReceiveItem). OURS: no sound,
  shake, splash sprites or ripple; the flippers drawn as their menu icon.
- [x] 52.4 **Port: the big gray blocks lift with the Power Glove** (new
  `Lift52.lua`). The lift query 0x0808176C: (attribute & 0xF0) == 0x70 ->
  dung_replacement_tile_state (+0x195C); a big block's segment
  ((state & 0xF0F0) == 0x2020) counts as attribute 0x55 (0x080817DA); the
  replacement 0x08081730..0x08081752 draws the room's own words back. The
  port only lifted pots indoors (Interior.potAt). Rooms with such blocks
  (object 0x2C): 0x3F, 0x44, 0x45, 0x93, 0x9E, 0xCE, 0x117 (Thieves' Town
  later); none was on this round's route, so it is checked by the test only.
- [x] 52.5 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r51_pod_dw_pod_done` -> the mirror at the palace's door -> the Light
  World (`ck_r52_lw_mirror1`) -> Sahasrahla's hut (`ck_r52_hut_in`): two
  pots lifted, the back wall bombed (door 0x28 at 128,304), the third pot,
  the three chests (`ck_r52_hut_chests`: 50 + 3 bombs + 50, 192 rupees,
  9 bombs) -> the Eastern Palace (`ck_r52_ep_in`): the entrance hall's tag
  0x17 floor switch (240,144) toggles the shutters, so walked past it; the
  Popos fought; 0xB9 (`ck_r52_ep_b9in`) -> the cannonball chest, 100 rupees
  (`ck_r52_ep_chest`: 292 rupees, 9 bombs, 8 arrows, 56 max health).
  Also kept (side checkpoints): the Sanctuary -> 0x02 -> the stairs into
  0x11 (`ck_r52_sanct_in`, `ck_r52_sew_02`, `ck_r52_sew_11`): the sewer
  secret room's 300 rupees are behind its bomb walls, but from the
  stairs side the corridor's push block (376,96) can only go down, onto the
  one opening (its neighbours are attribute 0x27, not big gray blocks: the
  GBA's DrawBigGraySegment 0x080805E0 is only object 0x2C, table entry
  0x08153160), so not taken; and the Dark World way south (`ck_r52_dw_pegs`:
  the 3 x 3 hammer pegs at 2816..2848, 2832..2864 hammered; the Village of
  Outcasts and its 300-rupee chest are NOT reachable from there without the
  hookshot or the Titan's Mitt -- only 0x21B pegs and bushes passable, BFS).
  Health floor: 0 on the kept chain (lw_mirror1 -> ep_chest); the side
  branch to the pegs absorbed 156 (Ropas 0x22 and Ravens 0x00 by the
  pyramid), not counted on the route.
  Real app (`real/runreal.sh r38ck`, cache `zelda-cache:alttp:v51` after
  `real/reimport.sh`; window shot `real/shots/r52real_p11_B9_win.png`):
  `ck_r52_ep_in` -> past the switch, 0xB9's chest: 100 rupees, the HUD
  shows 292: passed (same as the harness).
- [ ] 52.6 **Blocked: Zora's waterfall (special area 0x81) is not ported.**
  Grove.lua's world "sp" maps only the Master Sword grove (area 0x80); the
  special exits 0x181 / 0x182 / 0x189 are not followed, so King Zora (list
  phase 2/3, area 0x81 at 944,80) cannot be met even with 500 rupees.
  Without the flippers the Swamp Palace cannot be done (indoor swimming is
  also not ported: Swim.lua is outdoors only; the GBA's swim handler is
  entry 4, 0x08097F64, and the landing check 0x0809B3D8 counts the
  deep-water bits (+0x17D0) and needs 0x0200233A).
- [ ] 52.7 Not done: the 0x1B moving wall speed, the PoD door's map steps
  and sounds; pick-ups' (Drops.absorb) bombs / arrows still add at once.

Checkpoints (`r52/out/`, harness, real input): `ck_r52_lw_mirror1`,
`ck_r52_hut_in`, `ck_r52_hut_chests`, `ck_r52_ep_in`, `ck_r52_ep_b9in`,
`ck_r52_ep_chest` (latest on the route: Eastern Palace 0xB9 by the
cannonball chest, 292 rupees), side: `ck_r52_dw_pegs`, `ck_r52_sanct_in`,
`ck_r52_sew_02`, `ck_r52_sew_11`.

Tests: new `zelda_alttp_r52_test` (the fall runs the sprites, not the drop,
knockback dropped on landing; receipts: rupee amounts, 300, the bomb / arrow
fillers one a frame up to the bag, no menu byte; King Zora: wait, rumble,
hold, talk, 500 paid, refusal, too poor, the thrown flippers bounce, stop
and are taken, gone when owned; big block segments: query, level, lift;
36 checks). All 60 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80
overworld areas (`AUDIT=rooms|ow run.sh audit` in r52, cacheVersion 51; the
r51 reference set copied to `r52/out/audit/`).

## Round 53 (2026-11-15)

Zora's waterfall, the flippers, the dam. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r53/` (the r52 kit with r53
paths; checkpoints now `ck_r53_*`; harness additions: `ck25.lua` skips the
Eastern Palace legs with `NOEP=1`; ow52 tokens `LR` (lift rocks while
walking) and `DASH<dir><n>`; pod49b token `PULL<n>` (action + down held: a
pull switch from below); `route52.lua` / `owmap52.lua` take `HOPS=1`
(one-way ledge hops), `ROCKS=5255..` (passable lift attributes), `ROCKLOG=1`
and `CROP=x,y,w,h`; new probes `sp53*.lua` (special-area tables, map8 /
attribute map of area 0x81), `warp53.lua` (Light World warp secrets),
`ent53.lua`, `ch53.lua`, `rup53.lua` (rupee chests by room / entrance),
`spr53.lua`, `act53.lua`, `fl53.lua`, `g53.lua`, `m16q53.lua`,
`owpic53.lua` (overworld picture); `py/sp53.py`). **cacheVersion 52**
(Generous53 reads tables at import): harness store re-imported (REIMPORT=1)
and the real app cache re-imported (`real/reimport.sh`, key
`zelda-cache:alttp:v52`).

- [x] 53.1 **Port: special area 0x81, Zora's waterfall** (`Grove.lua`
  generalised). Overworld_CheckSpecialSwitchArea 0x08071D7C: the switch
  table's entry 2 is area 0x0F's map8 0xAD -> exit 0x182 (screen 0x81,
  Link at (0x29E, 0x3E8)); the way back 0x08078708: kSpecialSwitchAreaB
  entry 2 (map8 0xAD in area 0x81, direction 4). The special areas lie on
  their own 8-wide grid of 512 px screens from 0x80; kSpExit_Top /
  LeftEdge [room - 0x180] are the area's origin (0x182 -> (0x200, 0)); the
  parent table 0x14FC30 makes 0x81 a large area (0x82 / 0x89 / 0x8A ->
  0x81), drawn from the four screens' own maps. The per-area tables
  (sprite set, aux graphics, palettes, facing) are indexed by the entry
  room (0x08078274), not the area: Grove.idxOf. `world "sp"` now resolves
  screens through Grove.cur (the area Link is in), walls outside it, keeps
  the 32 px walkable strip under it; Grove.PORTED = { 0x180, 0x182 }
  (0x181 under the bridge and 0x189 not followed). Zora52's King Zora is
  now met. OURS (as for the grove): the switch is instant, the way back
  puts Link on the spot he left from (16 px walk down), the music is
  Audio.musicFor's rule (the special-area cue not traced).
- [x] 53.2 **Port: the shopkeeper kind 2, the man who gives 300 rupees**
  (new `Generous53.lua`, Hype Cave 0x11E / Mini Moldorm cave 0x123 / room
  0x127). SpritePrep_Shopkeeper 0x0810E1AC: kShopKeeperWhere 0x17D020 ->
  prep 0x17CFE8 [i]; indices 6 / 9 / 12 share 0x0810F1C8 (subtype2 = 2).
  Main 0x0810E4B4 (0x17D034 [2]), states 0x17D090: 0 0x0810F51C
  Sprite_ShowSolicitedMessage(0x179) -> 1; 1 0x0810E540: the room's save
  bit 0x4000 set -> 0, else set it, Link_ReceiveItem(0x46) (300 rupees,
  Receipt52) -> 2; 2 0x0810F554 -> 0. Draw 0x080E67E8: 0x17768C +
  graphics * 16 (graphics 2), the head's char / flip by the direction to
  Link (0x17774C / 0x177750, up shown as down). Read at import: the kinds
  per room, the message, the item, the draw tables. Before, this sprite was
  drawn and handled as the standard clerk (Shop.lua: "only talks").
- [x] 53.3 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r52_ep_chest` (NOEP) -> out of the Eastern Palace (`ck_r53_out` was
  overwritten by a later OUT; the same steps are in the z1 log) -> south
  and round by the witch's hut, the glove rocks lifted (`ck_r53_z_a`,
  `ck_r53_z_b`) -> area 0x17 -> area 0x0F (`ck_r53_z_c`, `ck_r53_z_d`) ->
  map8 0xAD -> **Zora's waterfall** (`ck_r53_zora_in`) -> King Zora (292:
  too poor, `ck_r53_kz_near`) -> out (`ck_r53_zora_out`) -> the east warp
  rock in its peg ring (area 0x2F, `ck_r53_port_ring`: hammer, lift) -> the
  Dark World (`ck_r53_dw_in`, `ck_r53_dw_out`) -> the r52 pegs
  (`ck_r53_dw_pegs2`) -> the Hype Cave's crack bombed (`ck_r53_hype_door`,
  `ck_r53_hype_in`) -> the man: **300 rupees** (`ck_r53_hype_gen`, 592) ->
  the inner wall bombed, four chests (`ck_r53_hype_chests`, 672) -> the
  mirror (`ck_r53_lw_hype`) -> back to the waterfall (`ck_r53_z2_b`,
  `ck_r53_zora_in2`, 675) -> **King Zora: 500 paid, the flippers caught**
  (`ck_r53_kz_paid`, 175 rupees) -> out (`ck_r53_zora_out2`) -> south
  (`ck_r53_lw_mid`) -> the dam (`ck_r53_dam_door`, `ck_r53_dam_in`): the
  block puzzle (centre block up, left block left), the pull switch 0x04 from
  below (A + down) -> **the dam opened** (`ck_r53_dam_pulled`: memory[0x28]
  .dam, progress.swampDam) -> out (`ck_r53_dam_out`). Stopped at the south
  warp rock (area 0x33, `ck_r53_dw_south2`): the bot could not get onto the
  tile under enemy hits.
  Health floor on the kept chain: 220 (184 in the Dark World leg past the
  Palace of Darkness's south, 0x6F / 0x5E, as r52's 156 there; 4 + 8 + 8 +
  16 elsewhere). Rupees now 177.
  Real app (`real/runreal.sh r38ck`, cache v52 after `real/reimport.sh`,
  `WINSHOTS=1`): `ck_r53_z_d` -> map8 0xAD -> area 0x81, walking in the
  river (`real/shots/r53real_zora3_win.png`): passed; `ck_r53_hype_in` ->
  the man, 292 -> 592: passed (`real/shots/r53real_p05_11E_win.png`);
  after the draw was added and the cache re-imported again, the man drawn
  from 0x17768C (`real/shots/r53real2_p04_11E_win.png`; his colours not
  checked against the GBA).
- Seen, not changed: from (3792, 1300) the planner reached (3928, 1148)
  without breaking the rock piles 0x57 the BFS needed (our collision lets
  Link through there; not traced). ow52's `M` uses the selected item
  (MENU23 first); pod49b's `OUT` writes `ck_r53_out` each time.
- [ ] 53.4 Not done: indoor swimming (GBA 0x08097F64, landing 0x0809B3D8),
  so the Swamp Palace (entrance 37, Dark World (1920, 3808)) was not
  entered; the 0x1B moving wall's speed; the PoD door's map steps and
  sounds; floor pick-ups of bombs / arrows still add at once.

Checkpoints (`r53/out/`, harness, real input): `ck_r53_z_a`, `ck_r53_z_b`,
`ck_r53_z_c`, `ck_r53_z_d`, `ck_r53_zora_in`, `ck_r53_kz_near`,
`ck_r53_zora_out`, `ck_r53_port_ring`, `ck_r53_dw_in`, `ck_r53_dw_out`,
`ck_r53_dw_pegs2`, `ck_r53_hype_door`, `ck_r53_hype_in`, `ck_r53_hype_gen`,
`ck_r53_hype_chests`, `ck_r53_hype_out`, `ck_r53_lw_hype`, `ck_r53_z2_b`,
`ck_r53_zora_in2`, `ck_r53_kz_paid`, `ck_r53_zora_out2`, `ck_r53_lw_mid`,
`ck_r53_dam_door`, `ck_r53_dam_in`, `ck_r53_dam_lever`, `ck_r53_dam_pulled`,
`ck_r53_dam_out` (latest on the route: outside the dam, flippers, dam
open, 177 rupees, 8 bombs, 8 arrows), side: `ck_r53_dw_south`,
`ck_r53_dw_south2`.

Tests: new `zelda_alttp_r53_test` (the special grid, the ported exits; kind
2 on a fake game: talk, 300 once, the room bit, a second talk, facing away;
with the ROM: Zora's switch tables, kSpExit index by room, 0x81 large, the
kinds / message / item, walking up 0xAD into area 0x81 at (0x29E, 0x3E8),
1024 x 1024 at (512, 0), the sprite set, only the area's screens drawn,
walls / the strip under it, walking down back to area 0x0F, the grove
unchanged; 25 checks). All 61 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80
overworld areas (`AUDIT=rooms|ow run.sh audit` in r53, cacheVersion 52; the
r52 reference set copied to `r53/out/audit/`).


## Round 54 (2026-11-15)

Indoor swimming, the way to the Swamp Palace, into its first three rooms.
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r54/` (the r53 kit with
r54 paths; checkpoints `ck_r54_*`; new probes `swmap54.lua` (a room's
attribute maps, both levels: `ROOMS=28,38 HEX=x0,y0,x1,y1 HALF=1`),
`locks54.lua` (locks, actors), `spr54.lua` (sprite lists, pot secrets),
`blk54.lua`, `lift54.lua`, `up54.lua`, `trace54.lua` (`TRON=1`: Link's
position every 4 frames), `swdbg54.lua` (water state changes), `rbox54.lua`
(route52 that prints the region's bounding box and edge attributes when no
path); ow52's HURTLOG now names indoor actors too; route52 / owmap52 /
rbox54's `ROCKS=` is now read as hex pairs (r53's `find` matched single
digits, e.g. "2" in "5255", so walls looked passable)). **cacheVersion 53**
(Swim54 reads tables at import): harness store re-imported (REIMPORT=1)
and the real app cache re-imported (`real/reimport.sh`, key
`zelda-cache:alttp:v53`).

- [x] 54.1 **Port: swimming indoors** (new `Swim54.lua`; hook lines in
  Swim.lua (`lk.swimMove`, `SW.swimFrame`) and Doors.lua (checkY / checkX
  exported)). Traced on the GBA (Link's block 0x03002230):
  the swim handler 0x08097F64 (state 4 at +0x1718; +0x1702 aux -> recoil;
  flippers 0x0200233A) is Swim.lua's swimFrame, now run indoors with the
  room's tables for the move. Indoor TileDetect (table 0x0816832C): 0x08
  deep water (+0x17D0, 0x080A07DC), 0x0A the short water ladder = the only
  "normal tile" indoors (+0x17D2, 0x080A07FC; floor 0x00 sets nothing,
  0x080A0678), 0x01-0x04 walls (0x080A067C). Y collision 0x08095358: three
  probes on deep water, not in it: dash cancelled (0x08093078); TS (+0x9B5)
  0 -> Dungeon_HandleLayerChange 0x0808B1A8 and the hop, else +0x17D4 = 1
  and the hop 0x0809A24C (index TS; 0 while +0xB22). In the water the
  middle probe on 0x0A (0x080953F8): +0x17D4 = 0, AncillaAdd_Splash
  0x080AD1EC (indoors and not in deep water it clears
  link_is_on_lower_level +0xA10, 0x080AD22C..0x080AD24A), the hop out.
  The X side as zelda3's (all three for in, all three on 0x0A for out,
  the partial test on the third probe). Hop tables: Y 0x08167ED0 (speed,
  z speed, timer by index), X 0x08167F99 (read through the literals at
  0x0809A288 / 0x0809A6AC). Landing 0x08099E9C..0x08099F06: state 4 when in
  deep water, then indoors, not from state 2, with the flippers +0xA10 = 1
  (the water is the second table). TS = kSpiralTab1 0x0814CAD4 [bg2
  property] (literal at 0x0806D48E; -1 -> 0, property 2 -> 3). Deep water
  is no wall to Link's own probes; sprites keep the grid. OURS: no splash /
  ripple drawn, no sounds; without the flippers Link goes back to the room's
  entry spot at once (CheckAbilityToSwim -> Module07_14); the layer change's
  room + 16 not ported.
- [x] 54.2 **Fix: the stair numbers 0x30-0x37 were solid indoors.** Handler
  0x080A06F8 (0x22 / 0x30-0x37) only sets tiledetect_stair_tile (+0x1713).
  In room 0x28 the spiral stair behind the key door (object 0x139: 0x5E
  row, number row, the door) could not be taken.
- [x] 54.3 **Fix: floor pick-ups of bombs / arrows** (Drops.absorb) now go
  into the fillers (0x080CF5C8: += kBombsAbsorption [type - 0xDC] at
  0x02002355; 0x080CF66C: += 5 / 10 at 0x02002356), counted in one a frame
  by Receipt52.refill (Hud_RefillLogic 0x080A72F4).
- [x] 54.4 **The 0x33 warp rock.** r53's spot (1874, 3208) is a pocket
  between the statues: the rock's lawn is closed by the statue V, the cliff
  and three hammer pegs (0x27 at 1968, 3200..3247). From the south: the
  pegs hammered from below, the rock lifted from (1856, 3160) (the lift
  reads (x + 6, y + 4)), up onto the warp. The Dark World side has the
  same pegs (hammered from the left).
- [x] 54.5 **Traced, not a leak (r53's "collision leak").** From (3792,
  1300) to (3928, 1148) Link does not pass the 0x57 piles: the planner
  went left, hopped the ledge down to (3760, 1423), took the stairs (0x22)
  at x 3848 up to 1355 and walked up the grass at x 3936 (trace54). r53's
  BFS had no hops.
- [x] 54.6 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r53_dam_out` -> the pegs south of the rock (`ck_r54_swp_pegs`) -> the
  rock lifted, the warp (`ck_r54_dw_swamp1`, area 0x73) -> the Dark World
  pegs (`ck_r54_dw_swpegs`) -> the Swamp Palace's door (`ck_r54_dw_swdoor`)
  -> in (`ck_r54_sw_in`, room 0x28): up the wet stair, the hop in, swim to
  the north ladder, out (`ck_r54_sw_28lad`) -> the chest's key
  (`ck_r54_sw_28key`) -> the key door, the spiral stair down to 0x38
  (`ck_r54_sw_38in`) -> the west wall bombed (0x2E) -> room 0x37
  (`ck_r54_sw_37in`: the map chest) -> back to 0x38, pot 4's key
  (`ck_r54_sw_38key`) -> the key door (0x1C) to 0x37's south part
  (`ck_r54_sw_37b`). Health floor on the kept chain: 8 (the Kyamerons
  0x9A in 0x38). Every leg starts with the health refilled (seg40, as
  before).
  Real app (`real/runreal.sh r38ck`, cache v53, `WINSHOTS=1`):
  `ck_r54_sw_in` -> the hop in, swimming, the ladder, out on the walkway:
  passed (`real/shots/pod49_p07_28_win.png`: the hop out).
- [ ] 54.7 Not done: the rest of the Swamp Palace (0x37's switch and
  flood, the waterfall corridor's key (0x37 pot at 240, 96), 0x36's key
  (pot 456, 256), the Hookshot, Arrghus, crystal 2); the 0x1B moving
  wall's speed; the PoD door's map steps and sounds.

Checkpoints (`r54/out/`): `ck_r54_swp_pegs`, `ck_r54_swp_rock` (rock state
not kept), `ck_r54_dw_swamp1`, `ck_r54_dw_swpegs`, `ck_r54_dw_swdoor`,
`ck_r54_sw_in`, `ck_r54_sw_28lad`, `ck_r54_sw_28key`, `ck_r54_sw_38in`,
`ck_r54_sw_37in`, `ck_r54_sw_38key`, `ck_r54_sw_37b` (latest: Swamp
Palace 0x37 south part, 0 keys, 7 bombs).

Tests: new `zelda_alttp_r54_test` (TS from kSpiralTab1, the hop records by
index; with the ROM: the tables, 0x0A / 0x30-0x37 walkable, room 0x28
flooded: the hop in, swimming on the lower level, the hop length, the
ladder out to the upper level, one swim / two landings, no flippers: back
on the entry spot; 18 checks). All 62 `zelda_alttp_*` files pass. Audits
304/304 rooms, 80/80 overworld areas (`AUDIT=rooms|ow run.sh audit` in r54,
cacheVersion 53).

## Round 55 (2026-11-15)

The Swamp Palace's west half with real input: both floodgates, the block
puzzle, the big key and the Hookshot. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r55/` (the r54 kit with r55
paths; checkpoints `ck_r55_*`; new pod49b tokens `XE<x>` / `YE<y>` (walk to
an exact pixel: the walk moves 1 / 2 px a frame by its sub-pixel, so a
step away re-phases it), `SQ<x>,<y>[,<tol>]` (swim by taps: let the glide
stop, tap toward the spot), `SP` / `SX` / `SY` (swim with braking; not
used, the glide outlasts them); new probes `sw55.lua` (the water switch
0x21 per frame: `SWSTEPS="l60 u20 n100"`, `EVERY=1`), `hx55.lua` (the live
room's attributes in a box, both levels: `HX=x0,y0,x1,y1`), `swd55.lua`
(the switch's draw call, its tiles' sheet, the room's four sprite sheets
to `shots/sheets55.png`), `so55.lua` (blocked / solid actors in a box),
`dr55.lua` (Doors.move / doorTransition per frame), `hk55.lua` (the
hookshot ancilla per frame), `dm55.lua` (a palace's dungeon-map floors from
the cartridge's layout table: the Swamp Palace is 1F 0x54 / 0x28, B1 06 16
26 / 34-38 / 46, B2 66 / 76)). cacheVersion stays 53 (no new import
tables): no re-import.

- [x] 55.1 **Port: what the hookshot catches indoors** (new `Hook55.lua`,
  one hook line in Tools.lua's hookTiles). The hookshot's tile test
  (0x0809F8DC: two points from 0x081682B6 / 0x081682C6, each through
  TileDetection_Execute 0x080A0454 and the indoor handler table
  0x0816832C) is read by the ancilla at 0x0811CE24..0x0811CEE2: +0x97C
  (| its high nibble | +0x1713 | +0x978) & 3 is a wall (the hook turns
  back), +0x1784 & 3 (tiledetect_misc_tiles) holds the hook (+0x1810 = 1).
  The handlers that OR the point's bit into +0x1784: 0x27 (0x080A0950),
  chests 0x58-0x5D (0x080A008C, first step: BL 0x080A08B0), 0x63
  (0x080A02F0), 0x67 (0x080A0298, the raised peg), pots and liftables'
  map tiles 0x70-0x7F (0x080A0030), 0xC0-0xCF (0x080A07B0). The port held
  the hook on 0x27 only. Not added: 0x60 (0x080A0220, other bits), 0xF0-0xFF
  (0x080A0974, bits << 4), 0x50-0x56 (0x080A0358, one branch only).
  Outdoors (the overworld table) unchanged.
- [x] 55.2 **Traced, no change: the moving walls' speed.** Both tag
  routines (0x1C 0x0807ABA4 at 0x0807ABEA, 0x1D 0x0807AF50 at 0x0807AF82)
  add 0x2200 (0x88 << 6) to the 16-bit sub-pixel each frame, a pixel on the
  carry, as DesertPalace.wallFrame does; the start test (0x0807AA0C) counts
  the lit torches (> 3). r51's "~17 s for 0x1B" is the cartridge's speed.
- [x] 55.3 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r54_sw_37b` -> 0x37's corridor pot key (240, 96: lifted from below,
  `ck_r55_sw_37key`) -> back down, the channel, the stairs at x 160 up to
  the south-west strip, the key door (128, 300) -> the north-west part
  (`ck_r55_sw_37nw`) -> the stalfos, round below the switch, **the push
  switch 0x21 from its right, 48 frames** -> **the flood** (RoomTag_WaterOn,
  `ck_r55_sw_37flood`) -> the key door again, the stairs at 160 into the
  water (`ck_r55_sw_37stair`), swim to the short ladder (104, 360: 0x0A
  between two 0x03), out (`ck_r55_sw_37ladder`) -> the west door -> 0x36
  (`ck_r55_sw_36in`; its channels are shallow 0x09, property 4) -> the
  stairs and channels to its south-west door -> 0x35 (`ck_r55_sw_35in`) ->
  the bottom: pot (304, 448) lifted, stairs at 240, the corridor pot key
  (240, 96; `ck_r55_sw_35key`) -> back to 0x36, its north-west platform,
  the key door (24, 128) -> 0x35's north-east part (`ck_r55_sw_35ne`) ->
  **0x35's push switch, its flood** (`ck_r55_sw_35flood`) -> back through
  the same door (the doorway walk is slow: `T` tokens) to 0x36, its
  south-west door (`ck_r55_sw_36nw`, `ck_r55_sw_35se`) -> 0x35's bottom,
  the pot, swim from the stairs at 240 to the ladder at 112, out, the west
  door -> 0x34 (`ck_r55_sw_34in2`) -> **the block puzzle** (blocks move once:
  D (152, 400) left, C (152, 384) up, then along y 376 to the stairs at
  112) -> the bottom-left -> the spiral stair (120, 296) up to 1F 0x54
  (`ck_r55_sw_54in2`) -> through the shallow pool, the block (296, 128)
  pushed up, **the hole (328, 120) down into 0x34's north-east pocket**
  (`ck_r55_sw_34ne2`) -> the pot (368, 128) lifted, the orange pegs down
  (state 0), the east door -> 0x35's north-west (`ck_r55_sw_35nw`) -> **the
  big key** (chest 184, 128; `ck_r55_sw_35bk`) -> 0x34's pocket, the ledge
  hop west (0x2A at x 288) into its channel, down, the south-east door ->
  0x35 (`ck_r55_sw_35w2`) -> the stairs at 112, swim to 240, the pot, the
  east door -> 0x36 (`ck_r55_sw_36w2`) -> the centre platform from below
  -> **the big chest: the Hookshot** (`ck_r55_sw_36hook`) -> the channel
  beside the east bay (`ck_r55_sw_36bay`). Health floor on the kept chain:
  100 (36 in 0x37's south-east part: the firesnake 0x80, the four-way
  shooter 0xC6 and its fireballs; 56 + 8 in 0x36: the Kyamerons 0x9A,
  0x94). Every leg starts with the health refilled (seg40).
  A side branch (`ck_r55_sw_35peg`, `_35bot`, `_35swim`, `_34in`, `_34blk`,
  `_54in`, `_34ne`) hit 0x35's crystal switch (352, 96) first: that lowers
  0x35's blue pegs but raises 0x34's orange ones in front of the pocket's
  door -- a dead end; the kept chain leaves the crystal switch alone.
  Real app (`real/runreal.sh r38ck`, cache v53, `WINSHOTS=1`):
  `ck_r55_sw_37nw` -> the stalfos, the push switch, the flood: passed
  (`real/shots/pod49_p08_37_win.png`: the corridor full).
- [ ] 55.4 **Stopped: 0x36's key pot (456, 256).** It sits in the east
  bay (floor x 360-455, rows 248-279, alcove 440-471), a raised platform:
  its edges are 0x2A / 0x28 ledges (hop out) behind 0x01 / 0x04 walls,
  the shallow channel all round; nothing above it (1F has only 0x54 and
  0x28). The hookshot from the channel (x 320, y 243, facing right) meets
  the 0x04 at x 336 first (the wall branch, +0x1784 clear) and turns back
  -- on the GBA too by the trace above. The bay's way in is not found
  (the north key door to 0x26 wants this key; 0x46 south is a swim ring).
  Next: check the bay's edge attributes against the cartridge's own
  attribute table for these objects (the room audit compares pictures,
  not attributes), and the 0x36 east wall's bombable lock 0x2E (472, 128)
  to the north-east platform.
- Seen, not changed: the push switch 0x21 is drawn from sheet 83 tiles
  10 / 28 / 29 (page 1, subset 4 of the room's set 31 / 32 / 34 / 83),
  which hold other pictures (the switch is nearly invisible; GBA VRAM for
  it not traced). The route planner (`W`, room-hex) fails in these rooms
  (doorway columns, sunken channels); the bot's `F` wanders into the
  firesnake; `C` (openChest) walks among Kyamerons.
- [ ] Not done: indoor splash / ripple drawing and swim sounds; the PoD
  door's map steps and sounds.

Checkpoints (`r55/out/`): `ck_r55_sw_37key`, `ck_r55_sw_37nw`,
`ck_r55_sw_37flood`, `ck_r55_sw_37stair`, `ck_r55_sw_37ladder`,
`ck_r55_sw_36in`, `ck_r55_sw_35in`, `ck_r55_sw_35key`, `ck_r55_sw_35ne`,
`ck_r55_sw_35flood`, `ck_r55_sw_36nw`, `ck_r55_sw_35se`, `ck_r55_sw_34in2`,
`ck_r55_sw_54in2`, `ck_r55_sw_34ne2`, `ck_r55_sw_35nw`, `ck_r55_sw_35bk`,
`ck_r55_sw_35w2`, `ck_r55_sw_36w2`, `ck_r55_sw_36hook`, `ck_r55_sw_36bay`
(latest: 0x36 beside the east bay, Hookshot, Swamp big key, both
floodgates open, 0 keys); side: `ck_r55_sw_35peg`, `_35bot`, `_35swim`,
`_34in`, `_34blk`, `_54in`, `_34ne`.

Tests: new `zelda_alttp_r55_test` (the Hook55 set indoors / outdoors,
Tools.lua's hook line; with the ROM: the handler table's pointers for
0x27, pots, chests, 0xC0-0xCF, 0x63, 0x67, each sets +0x1784 (a BL to
0x080A08B0 or the literal), the walls' 0x080A067C does not; in a room the
hookshot holds on a chest and pulls Link to it; 10 checks). All 63
`zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80 overworld areas
(`AUDIT=rooms|ow run.sh audit` in r55, cacheVersion 53).

## Round 56 (2026-11-15)

The Swamp Palace's east bay key and the way north, with real input.
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r56/` (the r55 kit with
r56 paths; checkpoints `ck_r56_*`; new probes `bay56.lua` (frame-by-frame
walk with hp / position / foes: `BAYKEYS="right:20 down:6"`), `lift56.lua`
(the lift query point and the pot under it), `drops56.lua` (drops, live
actors, keys), `kill56.lua` (stand still and sword a foe type in reach:
`KILLT=81 KILLF=900`), `doors56.lua` / `ikeys56.lua` (the room's tables,
stair and door cells), `hdr56.lua` (the room header bytes); `hk55.lua` now
prints the hook's ledge counter and the sprites near the hook when it
turns; `lua/dump56.lua` (attribute maps without LOVE)). cacheVersion stays
53 (no new import tables): no re-import.

- [x] 56.1 **Port: the hookshot flies over raised edges indoors** (new
  `Hook56.lua`, one line in Tools.lua's hookTiles). Ancilla1F_Hookshot
  (GBA 0x0811CCB6..0x0811CE0E) runs a ledge counter before its wall test:
  the indoor ledge handlers (0x28 0x080A0B40, 0x29 0x080A0B08, 0x2A / 0x2B
  0x080A0B78, 0x2C / 0x2E 0x080A0BB0, 0x2D / 0x2F 0x080A0BE8) fill +0x17FF /
  +0x1800 / +0x1801; on a ledge the hook counts edges in +0x1818[k] (cooldown
  +0x1827[k], set to -1 by AncillaAdd_Hookshot 0x080ADC50; first attribute
  +0x1813[k]) and skips its tile test (walls and hooks) while the count is
  not 0 or the cooldown runs (0x0811CDEA). So a hook fired from a raised
  platform crosses its own edge, the walls and channel beyond and the next
  platform's edge, and holds on what lies there.
  **How the east bay is reached (answer to r55's 55.4): it was a port bug.**
  From the big chest's platform (Link 264, 244 facing right) the hook passes
  the platform's 0x2A edge, the 0x01 / 0x04 walls and the channel, and holds
  on the bay's pot 7 (376, 248); the port had no ledge counter, so the 0x04
  wall turned the hook back.
- [x] 56.2 **Port: water sprites stay in water** (new `Sprite56.lua`, one
  line in Palace.lua's solidAt). Sprite_CheckTileProperty (GBA 0x080C7640):
  with flags5 & 0x40 (runtime +0x11B2[k], tested at 0x080C769C) type 0xD2 /
  0x8A pass attribute 9 (0x080C76AE..BA), type 0x94 with sprite_E 0 and
  0xE3 / 0x8C / 0x9A / 0x81 are walled by every attribute but 8 / 9
  (0x080C76C6..0x080C7704); after the table 0xA7 is walled by 8 / 0x0A
  (0x080C7718..24). The port had the water rule only for the Kyameron and
  the Pirogusu (Enemies27B.collide); the Hover 0x81 (flags5 0xC2) used the
  generic table, crossed walls and ledges onto 0x36's raised platforms and
  sat on the north platform's west edge, in the hook's line (the hook hit
  it and turned back).
- [x] 56.3 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r55_sw_36hook` -> the hook east from the big chest's platform into the
  bay (`ck_r56_sw_36east`; do not use `ck_r56_sw_36key`: Link at 290, 136
  with hp 16 after the bot's planner walked him among the Hovers) -> **the
  bay's key pot**: YE248 (at y 250+ the 0x02 below the alcove blocks),
  lift / throw pot 7 (376, 248) from 360, XE440, lift / throw pot 8
  (456, 256), the key (sprite 0xE4) picked up walking right, keys 1
  (`ck_r56_sw_36k`) -> off the bay's south edge at x 380 (hop 0x28) -> the
  channels: x 312 north (x 326 meets the 0x02 pillar), y 156 west, x 176
  south, y 204 west to the north-west stairs (`ck_r56_sw_36ch`) -> stairs at
  x 82, the platform to (120, 84) (round the pot at 104, 88), **the hook east
  onto the north platform's pot (240, 88)** (`ck_r56_sw_36top`) -> y 60, x 248,
  north through the key door (key used) -> **0x26** (`ck_r56_sw_26in`) -> its
  channel, the south-east part, the stairs 0x34 at (440, 288) -> **0x76**
  (`ck_r56_sw_76in`, Link 440, 306 on the south-east ring). Health floor on
  the kept chain: 0 (damage taken: 24 in 0x36's channels from the Kyameron
  0x9A / Pirogusu 0x94, 16 in 0x26's south-east part).
- [ ] 56.4 **Stopped: 0x76's drain switch not reached.** 0x76 (B2): the
  south-east ring leads by the ladder (360, 432) into the inner pool (deep
  water, lower level; the chests sit in it); the pool's west side is a 0x2A
  ledge under the bridge (rows 384-399, x 232-311) to the west channel: a
  one-way drop from the bridge, no way up from the pool. The drain switch
  (sprite 0x21, 408, 56) is in the north-east part, which the stairs at the
  top of 0x26's north-east corridors (0x35 at 312, 32 / 0x36 at 424, 32)
  most likely reach; those corridors are behind 0x26's shutter 0x18
  (376, 296). 0x26's tag is 0x16 RoomTag_SwitchTrigger_HoldDoor; its switch
  is under pot 3 (88, 312: secret 0x88) in the south-west part, beside the
  other shutter (120, 296). Next: lift pot 3, the hold-switch rule (what
  keeps the shutters open: GBA tag 0x16 routine), then the corridors and
  stairs to 0x76's north-east part, the switch, 0x66, 0x16, Arrghus.
- Seen, not changed: the `F` fight bot loses badly to the Pirogusu (0x94
  keep coming out of the walls) and to the Firesnake 0x80 (hp 16 floor, 392
  health-floor points in a discarded test run); route legs use exact walks
  instead.

Checkpoints (`r56/out/`): `ck_r56_sw_36east`, `ck_r56_sw_36k`,
`ck_r56_sw_36ch`, `ck_r56_sw_36top`, `ck_r56_sw_26in`, `ck_r56_sw_76in`
(latest: 0x76's south-east ring, Hookshot, Swamp big key, both floodgates
open, 0 keys). Bad: `ck_r56_sw_36key`.

Screenshots (`r56/shots/`): `r56_36_top_platform_after_hook.png`,
`r56_26_arrival.png`, `r56_76_arrival.png`, `r56_76_inner_pool.png`.

Tests: `zelda_alttp_r56_test` (Hook56's counter with and without a first
edge, the up hook's 0x28 set, Tools.lua's line; with the ROM: the ledge
handler pointers and targets, the hook's literals, AncillaAdd_Hookshot's
0xFF; Sprite56: a Hover passes water only, 0x94 by sprite_E, 0x8A on 9,
0xA7, Palace.lua's line, the GBA's type list at 0x080C76C6..FE and the
Hover's flags5 0xC2; in 0x36 the hook from the big chest's platform holds
on the bay's pot and pulls Link over, from the channel the 0x04 wall turns
it back; 19 checks). All 64 `zelda_alttp_*` files pass. Audits 304/304
rooms, 80/80 overworld areas (`AUDIT=rooms|ow run.sh audit` in r56,
cacheVersion 53).

## Round 57 (2026-11-16)

The Swamp Palace from 0x26 to Arrghus's door, with real input. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r57/` (the r56 kit with r57
paths; checkpoints `ck_r57_*`; new pod49b tokens `ST<dir><v>` (push / pull
the statue 0x1C until its x or y is v), `HH<dirs><n>` (hold several
directions: diagonal walls, swimming), `KA<type>[,n]` / `KW` / `KB` (walk at
/ stand and sword the nearest foe of a type within `KAR` px; `KB` swings
without turning), `WF<type>:<x>,<y>,<r>[;...]` (wait until those foes are r
px from a spot), `WATCH<n>`, `DBGLIFT`, `ARR[n]` (the Arrghus fight bot:
hookshot puffs, sword the freed ones; not good enough yet); `STPOS=1|all`
prints the statue / nearby actors after each token, `STWATCH=1` every statue
move, `HURTLOG` now names the nearest actor; probes `blk57.lua` (blocks,
pots, tags, switch cells), `map57.lua` (the live room's attribute map, both
levels, and actors: `out/map26.txt`, `map76`, `map66`, `map16`, `map06`);
`py/objs57.py <room>` (a room's object list); `lua/lad57.lua`,
`lua/chests57.lua` (rooms' ladder cells, chests, pot secrets and locks
without LOVE, through tools/run_lua_check.py); `realp.sh <ck> "<steps>"`
(a leg in the real app, full-window shots)). cacheVersion stays 53 (no new
import tables): no re-import.

- [x] 57.1 **Traced: what holds 0x26's shutters (tag 0x16).**
  RoomTag_SwitchTrigger_HoldDoor (0x08079CCC, kDungTagroutines 0x152AC4):
  v = !(+0xBC4 somaria) && !(+0xBC0 dung_flag_statechange_waterpuzzle) &&
  !RoomTag_CheckForPressedSwitch; 0x26's answer is the movable statue 0x1C
  (Traps27, already ported): pot 3 (88, 312) lifted shows the switch, the
  statue (96, 375) pushed left to x 88 and up to y 312 (its four points
  kMovableStatue_SwitchX / Y on 0x23) sets the flag: both shutters open.
- [x] 57.2 **Port: a push block on a hold switch** (new `Block57.lua`, one
  line in Actors.lua's tag call, one in RoomObjects.stepBlock). The same tag
  first looks for a replacement-object state 5 (+0x195C[i], 0x08079CE0..FA)
  and then uses +0xB0E instead of the switch test; the push block's landing
  (0x0808373C, called for state 3 at 0x08083936) sets +0xB0E = +0xB10 ^ 1
  and state 4 when the attribute under it is 0x23 (0x080837C8..E6), the push
  code steps it to 5 (0x080AF96C). So a block pushed onto the switch flips
  the shutters once and latches them. The port only read Link / the flag /
  the somaria block. (Not on the route: 0x26 has no push block.)
- [x] 57.3 **Port: the water ladders in every room** (new `Ladder57.lua`,
  one line at the end of Mech27's afterLoad). RoomDraw for subtype-2 0x35
  (0x0807C778): inactive only when dung_hdr_tag[1] (+0x9E7) is 0x1B and the
  dam is shut (save_dung_info & 0x100), else on the active list (+0xC2A /
  +0xAE8); Dungeon_LoadObjectAttribute's active loop (0x0808227E..) writes
  upper 03 00 00 03, lower 03 0A 0A 03. Mech27 wrote ladder attributes only
  in the switch / dam rooms, so room 0x16's five ladders (its pool's only
  ways out) had no 0x0A and Link could swim in and never out. Seen, not
  changed: Mech27 still draws 0x37's ladder inactive before its flood (GBA:
  active).
- [x] 57.4 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r56_sw_26in` -> the Bari 0x23 in the channel (sword) -> pot 3 lifted
  (88, 312) -> **the statue onto the switch** (left from its right side to
  x 88, up from below to y 312; both shutters open) -> the channel east,
  wait for the Kyameron / Firesnake / Biri (`WF`), the south-east part, up
  through the open shutter (376, 296) -> the north-east corridor, its Bari
  (sword), the stairs (424, 32) -> **0x76's north-east part** (`ck_r57_sw_76ne`)
  -> **the drain switch** (Link at y 64, left 80 frames; the room's water
  bit set) (`ck_r57_sw_76drain`) -> down the north-middle stairs (344),
  west over the bridge (y 120), the Hovers (sword), the west channel north
  past the Pirogusu -> **0x66** (`ck_r57_sw_66in`) -> the Hovers, the pool
  east (x 300 -> 376), the Pirogusu (sword), north through x 376 to the
  stairs (383, 144) (`ck_r57_sw_66up`) -> the stairs (376, 24) -> **0x16**
  (`ck_r57_sw_16in`) -> the diagonal corridor (held diagonals), down the
  middle (336), to the south strip (376, 314) -> into the pool, right, up
  the ladder (408, 344) -> the pot (448, 312): **the small key** (keys 1) -> the ladder down, swim west along y 351 (no hits), up
  the ladder (112, 344) -> the key door (120, 296) opens (`ck_r57_sw_16door`)
  -> north through the key door and the north door -> **0x06, Arrghus's
  room** (`ck_r57_sw_06in2`, Link 120, 448). Health floor on the kept chain:
  0 (damage taken: 24 in 0x26, 16 in 0x76's west channel, 12 in 0x16; every
  leg starts with the health refilled (seg40)).
- [ ] 57.5 **Stopped: Arrghus.** The `ARR` bot clears the puff ring (13
  puffs hooked and sworded) and lands sword hits on Arrghus (32 -> 24) but
  takes 16-point hits all the way (health floor 296..936 in three discarded
  runs): mostly from hooked puffs (0x8D ai 1) right after they reach Link,
  and from the boss pinning Link at the south wall. Next: trace
  Sprite_8D_Arrghi's hook branch on the GBA (when contact comes back after a
  puff is let go; the port: delay 32 from the last hook frame), then a fight
  routine that slashes a puff the frame it arrives and keeps north of the
  boss.
- Seen, not changed: indoor diagonal walls (attributes 0x10-0x13 with the
  solid 0x18-0x1B) do not slide Link along (Doors.lua "OURS: no slopes"):
  walking straight into 0x16's diagonal corridor stops him; held diagonals
  pass. The checkpoint at 0x06's doorway (`ck_r57_sw_06in`, deleted) left
  Link frozen in the door: checkpoints are taken a step into the room. A
  checkpoint after the statue push (deleted) does not keep the statue: the
  room's sprites reload; one on a lifted pot's spot (`ck_r57_sw_16key`,
  deleted) puts Link inside the pot again (the pot comes back on load).
  Real app (`realp.sh r57_sw_16in "<0x16 leg>"`, cache v53, full-window
  shots): the pool, the ladder (408, 344), the key pot, the swim west and
  the ladder (112, 344) out, the key door opens: passed
  (`real/shots/real57_p40_16_win.png`; that run's floor absorbed 20 -- the
  Hovers' timing differs from the harness run, not kept).

Tests: new `zelda_alttp_r57_test` (Block57's latch on a fake room: no block
-> tags as before, a block on the switch hides the hold tag from the inner
tags, flips closed shutters open once and keeps them; the three hook lines;
with the ROM: tag 0x16's routine, its state-5 / +0xB0E reads, the landing's
0x23 compare and latch, the 0x35 ladder's 0x1B test and active list, the
active loop's 0x0A; every active ladder outside the switch rooms has its
0x0A pair after load (rooms and cells from the import at run time); 15
checks). All 65 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80
overworld areas (`AUDIT=rooms|ow run.sh audit` in r57; the r56 `out/audit`
baseline copied in), cacheVersion 53.

Checkpoints (`r57/out/`): `ck_r57_sw_76ne`, `ck_r57_sw_76drain`,
`ck_r57_sw_66in`, `ck_r57_sw_66up`, `ck_r57_sw_16in`,
`ck_r57_sw_16door`, `ck_r57_sw_06in2` (latest: Arrghus's room, Hookshot,
Swamp big key, 0x76 drained, 0 keys). Side: `ck_r57_sw_16out` (0x16's
south-west strip without the key: the door stays locked).

## Round 58 (2026-11-16)

Arrghus beaten with real input, crystal 2, out of the Swamp Palace; the way
to Skull Woods traced but not found. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r58/` (the r57 kit with r58
paths; checkpoints `ck_r58_*`; new pod49b tokens `ARRB[n]` (the Arrghus
fight bot, `harness/arr58.lua`: hooks ring puffs from a line through the
boss, keeps the ring radius + 28 px off (104 px while the ring widens),
strikes a target only when the sword's measured box meets its predicted
box before its contact, dodges by a 9-move look-ahead, flees the landing
spot), `SWBOX<d>` (the sword's box per frame of a swing), `RINGP<n>` (puff
distances from the boss), `ACTS` (live actors); `HURTTB=1` prints the
caller of a hit; `ARRTR=1` traces freed puffs; probes `ents58.lua`
(entrances / holes of a DW area range), `route58.lua` (BFS with walking,
ledge hops, hookshot pulls onto 0x27, `PEGS=1` real pegs, `SWIM=1`,
`EDGES=1`, `SX`/`SY`/`WORLD`), `reachpt58.lua`, `owat58.lua` (attribute
grid), `p27_58.lua`, `pegs58.lua`, `sec58.lua` (overworld secrets >= 0x80),
`door58.lua`, `warps58.lua`). cacheVersion stays 53 (no new import
tables): no re-import.

- [x] 58.1 **Port: Arrghus and its puffs touch Link only through their own
  code** (new `Arrghus58.lua`, one line at the end of SwampPalace.prep).
  Traced (sprite routine table 0x08174138): Sprite_8D_Arrghi 0x0810CAD0
  rides the hook while sprite_B (+0xF72) holds the ancilla (position from
  the ancilla, oam flags 5, defl bit 6 cleared, return; 0x0810CC04..62);
  the hook gone (+0xE15[j] == 0) -> ai 1, sprite_B 0, delay_main (+0xFC2)
  0x20 (0x0810CBDC..F2); Sprite_CheckDamageToLink (0x080C4F98) only while
  delay_main is 0 (0x0810CC6C..74); with ai != 0 Sprite_CheckDamageFromLink
  (0x080C4948) every frame; on its spot again ai 0, oam 0x0D, defl |= 0x40.
  Ancilla_CheckSpriteCollision: hookshot (0x1F) on 0x8D -> sprite_B =
  ancilla + 1, no damage (0x080C0C14..72). Sprite_8C_Arrghus 0x0810BEB0:
  contact once a frame (0x0810BF30) after Sprite_ReturnIfRecoiling; its
  states (table 0x0817CD78: approach / decelerate / ring widen / jump /
  fall / swim) checked against SwampPalace.lua: same. **The port bug:**
  both types were also open to Actors.lua's generic contact, which knows
  nothing of the 32-frame grace -- a puff the hook had just brought in hurt
  Link at once (16 points; r57's "hooked puffs hurting Link"), and the
  swimming boss was touched twice a frame. Both now take noTouch like the
  other palace bosses.
- [x] 58.2 **Route, real input (harness from checkpoints; HPFLOOR=16).**
  `ck_r57_sw_06in2` -> **Arrghus** (`ARRB`: 26 hooks, 34 swings, 4638
  frames; the 13 puffs, then 8 sword hits on the swimming boss; health
  floor absorbed 0, no damage taken) -> the heart container (56 -> 64) ->
  **crystal 2** (crystals 0x12) -> out to the Dark World by the Swamp
  Palace (`ck_r58_sw_done`, area 0x7B, 1920, 3847). Then north / west:
  0x6C -> 0x6B -> 0x73 -> 0x72 (`ck_r58_dw_w3`, 1290, 3200; the bot
  planner fails from x 1280, a step right first) -> 0x6A -> 0x69
  (`ck_r58_dw_69`, 924, 2872, below the cliff south of the Village of
  Outcasts). Health floor on that walk: 12 (overworld foes 0x12 / 0x1B /
  0x41). Real app (`realp.sh r57_sw_06in2 "P ARRB9000 N90 P"`, cache v53,
  full-window shots): Arrghus beaten (`real/shots/real58_p04_06_win.png`,
  the boss exploding); that run's floor absorbed 56 (the ring phase pinned
  Link at the top wall, timing differs from the harness).
- [ ] 58.3 **Stopped: the way to Skull Woods.** Skull Woods (area 0x40;
  doors 0x28-0x2B -> rooms 0x56-0x59, holes 0x76-0x79 -> 0x58 / 0x67 /
  0x68 / 0x56, palace 16) lies in the DW north-west. With the Hammer, the
  Power Glove, the Hookshot and the Flippers the import's attribute maps
  give one closed region for the DW south and east (the Swamp, PoD, 0x69;
  `route58.lua`, 144k / 191k cells with swimming): 0x69's way north is a
  cliff row (y 2760) whose stairs (0x22 at 856, 2732) start in a pocket
  closed by 0x27 posts (816, 2832: not pegs, map16 not 0x21B) and a heavy
  rock 0x56 (896, 2768). The north-west (village, Skull Woods) joins the
  pyramid side by a hookshot pull onto posts west of the pyramid (~1552 ->
  1424, y 1444; route58 from 1968, 1448 reaches Skull Woods' south edge),
  and the pyramid is one-way down to the south (r46). The LW Kakariko
  portal (secret type 0x82 at 368, 1376 under a light rock) is fenced by
  posts and a heavy rock 0x56 (Titan's Mitt). No DW cell holds the peg
  map16 0x21B. Next: find on the GBA how the pyramid side is reached from
  the Light World at this point (suspect: the Hyrule Castle top / tower
  door after Agahnim -- the port leads entrance 0x24 into room 0xE0 again,
  per 0x0808BE18's "story byte > 2 -> ordinary entrance"), or a DW peg /
  overlay the import does not show.
- [ ] Not done (goal 3): indoor diagonal walls -- the GBA's slope code is
  found (0x0809407C calls 0x08093EB0, which runs 0x08093CF8 / 0x08093B68:
  diagonal kind +0x172E from 0x081682F6 by the tile handlers 0x080A0698
  (0x10-0x13) / 0x0809FE64 (0x18-0x1B, +0x16E4), offsets 0x08167D02, flags
  0x08167D22, pushes 0x08167D26 / 30 / 3A / 44 into link_x / link_y,
  +0x172B / +0x172D results) but not ported; the 0x21 switch's sheet; indoor
  splash / swim sounds; the PoD door's map steps and sounds.

Checkpoints (`r58/out/`): `ck_r58_sw_done` (DW 0x7B outside the Swamp
Palace: crystals 0x12, 64 max health, Hookshot), `ck_r58_dw_w3` (0x72),
`ck_r58_dw_69` (latest: 0x69 below the cliff, 924, 2872).

Screenshots: `r58/shots/r58arr_p03_06.png` (the heart container after
Arrghus, harness), `r58/real/shots/real58_p04_06_win.png` (real app).

Tests: new `zelda_alttp_r58_test` (Arrghus58 on boss / puff / other / dead
sprites, the SwampPalace hook line, Actors.lua's noTouch test; with the ROM:
the routine pointers of 0x8C / 0x8D, the puff's delay_main gate before
0x080C4F98, the hook-gone ai 1 / 0x20, Arrghus's own contact, the
hookshot's 0x8D / sprite_B; in room 0x06 a puff just let go on Link: no hit
in the grace, its own contact after; 13 checks; fails with noTouch
cleared). All 66 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80
overworld areas (`AUDIT=rooms|ow run.sh audit` in r58; the r57 `out/audit`
baseline copied in), cacheVersion 53.

## Round 59 (2026-11-16)

The way to Skull Woods found: it is the Light World's Kakariko portal (hammer
pegs + Power Glove), reached from the Lost Woods through an area edge the
port could not cross. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r59/`
(the r58 kit with r59 paths; checkpoints now `ck_r59_*` (o.sh / p.sh / pr.sh
export CKPFX=r59_); new: `harness/reach59.lua` (BFS from SX,SY with walking,
ledge hops as Link.lua does them, hookshot pulls (`HOOKOW=1` the outdoor
ledge counter), `SWIM=1`, `PEGS=1`, `ROCKS=52,54,55` (the glove's rocks);
`SX2/SY2` a second region, `RMAP` maps, `COMPS=1` the unreached components,
`FRONT=1` frontier attributes, `HOOKMISS=1`, `MIRPT=1` mirror-safe spots),
`route59.lua` (route58 + hops, `NOHOOK=1`, `ALL27=1`), `walk59.lua` + ow52
token `WK<x>,<y>` (BFS walk with real input, cuts bushes when stuck),
`tp59.lua` (probe: hold keys from a spot), `mw59.lua` (bg1 / bg2 map words +
attribute), `owpic53.lua` shots `shots/owpic_*`). **cacheVersion 54** (new
RomTables `edge59.*`): the harness re-imports by itself the first time
(r59 has no `out/store.bin` from r58; use REIMPORT=1 if one is stale); the
real app needs `real/reimport.sh` before its next run.

- [x] 59.1 **Checked (goal 1's doubts), not port bugs.** Dark World pegs use
  the same map16 0x21B words as the Light World (63 DW cells, hammered in
  r52 / r54); the overworld attribute read is the GBA's (0x080691D8:
  tileAttr 0x0815DF14[map8 & 0x1FF], + hflip for 0x10-0x1B); the 0x27 cells
  south of the Village of Outcasts (0x69) are a fence, not pegs; light rocks
  for the Power Glove are 0x52 / 0x55 (BigRock.NEED), 0x53 / 0x56 the Mitt.
  The rando logic (EntranceShuffle / Rules) confirms the vanilla Dark World
  graph: East DW -> Northeast DW by the broken-bridge pass, Northeast ->
  West by the Hookshot gap; the port's maps give the same one-way ledges
  (the pyramid moat region is reached by neither side).
  r58's "closed region" also came from route58's BFS, which could not hop a
  ledge with its cliff face behind it (reach59 / route59 now model hops).
- [x] 59.2 **Port: the overworld edge walk** (new `OwEdge59.lua`, one line in
  Game.lua before Link's overworld update). The edge test 0x08071E7C (every
  frame Link moves): d = link - the area's origin (top 0x0814D37A / left
  0x0814D3FA by area); up d <= imm (0x08071ECE), down d >= +0xC96, left d <=
  imm (0x08071F34), right d >= +0xC96 + imm (0x08071EF8); +0xC96 = the
  area's size word (0x0814D2FA, set at 0x0806A106) | imm (0x08076D26).
  The transition 0x08072748 then walks Link imm (0x0807274E) px a frame,
  through anything, until the coordinate's low byte is
  kOverworld_TransEnd[dir] (0x14D5C4). The port switched areas at
  (x + 8, y + 16) and kept collision on, reading the next area's first row:
  the Lost Woods' path south (area 0x00 -> 0x10 at x 376-391, row y 1024 is
  0x02 under the tree canopy) stopped Link, and with it the only way to
  Kakariko's portal clearing. Numbers read at import (RomTablesSpec
  `edge59.imm`, `edge59.end`). OURS: swimming / hopping / dashing Link keep
  the old switch; in cartridge-transition mode the walk ends after our
  scroll. A walk left behind by a warp / room / load is dropped.
- [x] 59.3 **Port: the hookshot's ledge counter outdoors** (new `Hook59.lua`,
  one line in Tools.lua's hookTiles). Ancilla1F_Hookshot outdoors
  (0x0811CD28): ((+0x1800 & 3) | +0x17FF | +0x1802) & 0x33 from the overworld
  handlers (table 0x0816872C: 0x28 / 0x29 / 0x2A-0x2B as indoors, 0x4C-0x4D
  0x080A0C21 and 0x4E-0x4F 0x080A0C59 into +0x1802; the diagonal ledges do
  not count); +0x960 is 0 outdoors, so the same ledge kind counts up again
  (0x0811CD84) and another kind counts down; count != 0 or cooldown -> no
  tile test. Hook56 covered only the indoor branch.
- [x] 59.4 **Route, real input (harness from checkpoints; HPFLOOR=16, absorbed
  0).** `ck_r58_dw_69` -> the mirror (MENU23; 12 px right of 924 to a
  Light World spot that does not bonk) -> 0x29 -> Kakariko (`ck_r59_lw_kak`,
  900, 2000) -> north (0x11, 0x12, 0x0A: `ck_r59_lw_n1`, `ck_r59_lw_n2`) ->
  the Lost Woods (`ck_r59_lw_n3`, `ck_r59_lw_n4`) -> the path's top
  (`ck_r59_lw_woods`, 376, 964) -> **down across the area edge (59.2) into
  0x10** -> the corridor to the fence (`ck_r59_lw_pegs`) -> **the two hammer
  pegs (400 / 416, 1344)** -> the clearing (`ck_r59_lw_clear`) -> **the
  light rock (368, 1376) lifted with the Power Glove** -> the portal ->
  **the Dark World, Village of Outcasts' north-west clearing**
  (`ck_r59_dw_village`, area 0x50, 406, 1398).
- [ ] 59.5 **Stopped: Skull Woods (area 0x40) not entered.** route59 from
  `ck_r59_dw_village` reaches the woods' west strip (472, 576) only through
  many hookshot pulls onto 0x27 tree outlines (dubious; not walked); the
  skull doors 0x28 (240, 512), 0x29 (592, 576), 0x2A (752, 592) are not
  reached by walking + hops + hooks in the BFS, and the bot planner finds no
  path (E41). Also found: the overworld holes (idx.holes with ordinary
  keys, e.g. Skull Woods' 0x76-0x79) are not followed -- Escape.lua only
  takes holes keyed 0xFFF0; the GBA's hole position test is not ported.
  Next: trace the hole test (the keys look like map16 offsets
  ((y >> 4) << 7 | (x >> 4) << 1): 0x76 = (768, 976)), check whether
  outdoor tree outlines are really hookable on the GBA, and walk from
  `ck_r59_dw_village` to a Skull Woods door or hole.
- [ ] Not done (goal 2): the indoor slope code (0x0809407C -> 0x08093EB0 ->
  0x08093CF8 / 0x08093B68, TileDetect_Movement 0x0809EB58 / 0x0809EA40,
  handlers 0x080A0698 / 0x0809FE64 set +0x978 |= bit and +0x172E =
  0x081682F6[attr & 3], 0x18-0x1B also +0x16E4) -- traced further, not
  ported. Goal 3 (0x21 sheet, indoor splash / swim sounds, PoD door steps)
  not started.

Checkpoints (`r59/out/`): `ck_r59_lw_kak`, `ck_r59_lw_n1`..`n4`,
`ck_r59_lw_woods`, `ck_r59_lw_pegs`, `ck_r59_lw_clear`, `ck_r59_dw_village`
(latest: DW 0x50, 406, 1398, after the Kakariko portal).

Screenshots (`r59/shots/`): `r59_dw_portal_arrival.png` (harness, the Dark
World after the portal), `r59_lw_portal_rock.png` (the clearing, the rock
lifted), `owpic_*` (map renders used for the trace). No real-app run this
round (cache 54 needs `real/reimport.sh` first).

Tests: new `zelda_alttp_r59_test` (Hook59 on stand-in attribute runs: a
ledge starts the skip, walls / water keep it, the other kind ends it, the
diagonals do not count, 0x4C does; the two hook lines; OwEdge59 on stand-in
tables: each edge at its threshold and not before, the size word, the four
ends, unbound tables -> no walk; with the ROM: the five sites' forms, the
tables' users (0x0814D37A / D3FA / D5C4 / D2FA), the feet still inside the
area when the down walk starts, each end past the edge, the hook's 0x33
mask and handler table; 50 checks). All 67 `zelda_alttp_*` files pass
(zelda_alttp_walls caught a stale edge walk across teleports: fixed).
Audits 304/304 rooms, 80/80 overworld areas (`AUDIT=rooms|ow run.sh audit`
in r59, the r58 `out/audit` baseline copied in), cacheVersion 54.

## Round 60 (2026-11-16)

Skull Woods entered with real input through its holes; the indoor diagonal
walls ported. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r60/`
(the r59 kit with r60 paths; checkpoints `ck_r60_*`; new: `py/holes60.py`
(the hole tables), `lua/pits60.lua` / `lua/hole60.lua` (pits of an area
with their keys, Hole60 on the Skull Woods pits, no LOVE),
`lua/owattrs60.lua` / `lua/owlift60.lua` (outdoor attributes in the hook
set), `harness/owpic60.lua` (owpic53 + `MARKS=x,y,c;..` boxes),
`harness/lift60.lua` (what tryLift sees), `harness/sl60.lua` (hold KEYS N
frames, print Link's slope state), pod49b token `FBW<x>,<y>,<r>` (wait until
every firebar ball is r px from a spot and moving away); pod49.lua's
checkpoints now keep the live entrance (`g.interior.entranceId`): the r59
chain carried entrance 37 (Swamp) into Skull Woods, so a Wallmaster sent
Link to room 0x28 and the key count was booked to the Swamp; the r60 room
checkpoints were corrected to entrance 119 / keyPalace 16).
**cacheVersion 55** (new RomTables `hole60.*`, `slope60.*`); harness store
re-imported (REIMPORT=1), real app re-imported (`real/reimport.sh`).

- [x] 60.1 **Port: the overworld hole keys** (new `Hole60.lua`, one line in
  Escape.lua's pit test). Overworld_GetPitDestination is 0x0808B4AC (called
  at 0x0809AA64; r59's 0x0808B55C is its loop). The key is the area's map8
  cell of (link_x & ~7, link_y & ~7), the same index the attribute read
  builds (0x080691D8): r = (y - top +0xC88) & mask +0xC8A, c likewise with
  +0xC8C; (r & 0xF8) << 2 | (r & 0x200) << 4 | (r & 0x100) << 3 | (c & 0xF8)
  >> 3 | (c & 0x200) << 3 | (c & 0x100) << 2; mask 0x0806A15A (large) /
  0x0806A162 (small). Entries: first key 0xFFF0 = any pit, else keys to
  0xFFFF; the entrance to +0xA1C. The link_y it reads is lifted first
  (0x0809A93A..E6: +0x960 = (link_y - BG2 scroll) & 0xFF, + `adds #n`
  0x0809A9D2, link_y -= it: the drop from the top of the screen), so the
  keys sit some 88 px above the pits on the map (r59's "map16 offsets" were
  a wrong guess). OURS: no pit pull; the key is taken with Link on the pit
  block's top-left and the port's centring camera; a pit with no key does
  not drop Link. Skull Woods: pits (632, 712) -> 0x77, (792, 680) -> 0x78,
  (488, 360) -> 0x79, the bush secret 0x80 at (768, 528) -> 0x76; three of
  the table's seven keys match no pit on the map.
- [x] 60.2 **Checked: outdoor tree outlines are hookable on the GBA.** The
  overworld handler table 0x0816872C sends 0x27 to 0x080A0950 (+0x97C |=
  bit, then 0x080A08B0: +0x1784 |= bit), and the hook holds on +0x1784 & 3
  (0x0811CED4). The table also holds 0x58-0x5D / 0x63 / 0x67 / 0x70-0x7F /
  0xC0-0xCF like indoors, but no overworld map has those attributes (both
  worlds scanned); the liftables' handler (0x080A0358) compares the map
  word with 0x50-0x56, which no overworld liftable has. The port (0x27
  only outdoors) is right: no change.
- [x] 60.3 **Fix: the firebar touched Link from 256 px away.** Firebar_Main
  compares 16-bit sums (0x080D8B7E..84, 0x080D8B9E..A4); Hera.lua masked
  with 0xFF, so Skull Woods 0x67's bar at (384, 320) hurt Link landing at
  (128, 104) from the hole. Now 0xFFFF (Hera.lua, one line).
- [x] 60.4 **Port: the indoor diagonal walls** (new `Slope60.lua`; hooks in
  Doors.lua: detect, probesY / probesX, the end of checkY / checkX, the two
  CalculateSnapScratch paths, D.move). The handlers of 0x10-0x13
  (0x080A0698) and 0x18-0x1B (0x0809FE64) set no wall bit: +0x978 |= the
  probe's bit, 0x18-0x1B also +0x16E4, kind +0x172E = 0x081682F6[attr & 3].
  The indoor Y check (0x080950A0..D6) runs FlagMovingIntoSlopes_Y
  (0x08093B68) when (+0x97C & 7) == 0 and +0x978 & 5: depth
  0x08167D02[kind * 4 + (x & 7)] against the probe row (+0x1708) & 7, Link
  pushed back, +0x172B = 8 / 4 | 0x08167D22[side] | 0x10; the X check
  (0x08096540..76) FlagMovingIntoSlopes_X (0x08093CF8) with 2 / 1 | .. |
  0x20; both clear +0x172B otherwise, and the doorway snaps clear it
  (0x08094FBC / 0x0809649C). Player_LimitDirections (0x0809380C) ends with
  link_direction = +0x172B & 0xF (0x08093AE0): Link walks along the slope;
  the cardinal checks (0x0809E650) skip Y / X on 0x20 / 0x10. Diagonal keys
  run 0x08093EB0 first (from 0x0809407C unless +0x172B & 0x30): X probe +
  flag, Y probe + flag, pushes 0x08167D26 / 30 / 3A / 44 by the changes.
  All tables read at import (RomTablesSpec `slope60.*`, each tied to its
  user by `ref`). Result: holding only down from 0x16's stairs (376, 50)
  takes Link along the diagonal corridor, down the middle and through the
  door to the pool (r57 needed held diagonals).
- [x] 60.5 **Route, real input (harness from checkpoints; HPFLOOR=16,
  absorbed 0 on the kept chain).** `ck_r59_dw_village` -> north at x 376
  across the area edge into Skull Woods (`ck_r60_dw_sw_in`, 376, 938; a
  pocket) -> the bush at (448, 944) cut, the light rock (480, 944) lifted
  (R) and thrown -> `ck_r60_dw_sw_rock` -> north-east to the pit
  (`ck_r60_dw_sw_pit`, 640, 725) -> **the hole (632, 712): entrance 0x77,
  room 0x67** (`ck_r60_sw_67in`) -> the two 0x24 (sword), the beetles 0x26
  into the pits, down the west strip past the bumper and the firebar 0x7F
  (`FBW`) -> the east half (`ck_r60_sw_67e`) -> **the compass** (chest
  384, 224; `ck_r60_sw_67comp`) -> the north door (376) -> **room 0x57**
  (`ck_r60_sw_57in`, 376, 392) -> the pot (304, 432) lifted -> **a small
  key** (chest 304, 320; `ck_r60_sw_57key`, keys 1) -> the Gibdo below it
  (`KA8B`, 302 frames), the pot (304, 432) lifted and thrown, round the
  bottom, the east key door (472, 384) -> **room 0x58**, the big chest's
  room (`ck_r60_sw_58in`, 54, 376, keys 0). Damage on the way was falls
  into 0x67's pits (8 each), the beetles (16) and Gibdos 0x8B (16).
- [ ] 60.6 **Stopped in 0x58.** Its south-west quarter holds the big chest
  (112..143, 344..367, inside a U of 0x27 blocks open at the top; the Fire
  Rod), the south-east quarter a chest at (456, 320); 0x57's big key chest
  (128, 112, item 0x32) is in that room's north-west quarter behind the key
  door (120, 296) from its south-west quarter, which this route has not
  reached (0x57's south-east quarter leads only back to 0x67 and east to
  0x58). The Wallmaster (0x90, overlord 9) takes Link back to the hole
  (now correctly: entrance 0x77) some 250 frames after he enters 0x57.
  Next: 0x58's west door / the holes 0x79 / 0x76 to the other quarters,
  the big key, the Fire Rod, the skull door at the back; Mothula not
  reached.
- Seen, not changed: a straight key held after a slide keeps walking along
  the slope until a probe leaves it (the override has no other reset on the
  GBA either: +0x172B is cleared by the checks, the snaps and diagonal keys
  (0x08094290)). Not done (goal 5): the 0x21 push switch's sheet, indoor
  splash / swim sounds, the PoD door's steps and sounds.

Real app (cache v55 after `real/reimport.sh`, full-window shots):
`CK=r60_dw_sw_pit OWSTEPS="SHpit WK628,700 N20 SHfall N60 SHroom"
LEGS=pod49.lua:X,ow52.lua runreal.sh`: the pit, the drop, room 0x67
(`real/shots/real60_pit_win.png`, `real60_room_win.png`); `realp.sh
r57_sw_16in "Hd30 P Hd30 P Hd40 Hd40 Hd40 P"`: holding down slides along
0x16's diagonal corridor to (376, 295) (`real/shots/real60s_p02_16_win.png`).

Checkpoints (`r60/out/`): `ck_r60_dw_sw_in`, `ck_r60_dw_sw_rock`,
`ck_r60_dw_sw_pit`, `ck_r60_sw_67in`, `ck_r60_sw_67e`, `ck_r60_sw_67comp`,
`ck_r60_sw_57in`, `ck_r60_sw_57key`, `ck_r60_sw_58in` (latest: Skull Woods
0x58, compass, keys 0).

Tests: new `zelda_alttp_r60_test` (hook lines; Hole60's key bits, the
lift, a stand-in pit block, 0xFFFF stops, unbound tables; Slope60 on
stand-in tables: the handlers' bits and kind, the Y / X flags, the
direction override, the diagonal pre-step, unbound tables; with the ROM:
the hole lookup's tables and caller, the slope flags' callers and the kind
writers; after the import: the masks' shape, every keyed hole entry has a
pit on the map that takes Link there and no pit takes him to two; stand-in
rooms with a diagonal band: for each band and key from the free side a
slope attribute slides Link along it without a probe on the walls; 60
checks). All 68 `zelda_alttp_*` files pass. Audits 304/304 rooms, 80/80
overworld areas (`AUDIT=rooms|ow run.sh audit` in r60, the r59 `out/audit`
baseline copied in), cacheVersion 55.

## Round 61 (2026-11-16)

Skull Woods' big key with real input (the 0x57 statue puzzle under
Wallmasters); the big chest (Fire Rod) not reached. No port change this
round. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r61/` (the r60
kit with r61 paths; checkpoints `ck_r61_*`; o.sh / p.sh / pr.sh / realp.sh /
ag.sh now export NOREFILL=1: a checkpoint load keeps the saved health instead
of refilling it). New in the kit: `harness/wm61.lua` (a leg wrapping H.run:
dodges falling / landed Wallmasters 0x90 by walking away, drops keys that
lead back into one, counts dodges / grabs; `WMR`, `WMDBG`, `WMSHOT`,
`HPLOGT=<type>` hp / recoil log, `TRACEF=n`; `PROBEwmoff61` / `PROBEwmon61`
switch it off / on), `harness/gf61.lua` (pod49b / ow52 token `GF<type>,<n>`:
sword fight against the foes of a type in Link's quadrant -- line up on an
axis, step into range, swing, back off; BFS walk to a far foe; outdoors the
foes within 160 x 120), `harness/stgo61.lua` (tokens `WI<x>,<y>` indoor BFS
walk with the statue as a wall, `STGO<x>,<y>[,order]` statue mover: push from
the far side, pull (R held) from the near side when the push spot is a wall,
an upper-case axis forces a pull; the statue's hit box is (x - 3, y - 4,
20 x 21), Link's (x + 4, y + 8, 8 x 8)), `harness/sw57.lua` (token `SW57`:
the whole 0x57 south-west puzzle with retries), probes `locks61.lua` (locks,
header, actors, attributes), `chest61.lua`, `ent61.lua` (entrance records),
`doors61.lua` (door slots), `ovl61.lua` (overlays), `reachin61.lua` (indoor
BFS map; `POTS=1`, `EXTRA=<attrs>`), `hd61.lua`, `trk61.lua`, `stbox61.lua`,
`fit61.lua`; pod49b tokens `PROBE<name>`, `GF..`, `WI..`, `STGO..`, `SW57`;
walk59 `NODOOR=x,y;..` + `NODOORM` (keep a WK walk off an entrance door),
`WKDBG=1`. cacheVersion stays 55 (no import change): no re-import.

- [x] 61.1 **Route, real input (harness from checkpoints, HPFLOOR=16).**
  `ck_r60_dw_sw_pit` (outside, before the holes; the r60 room chain is not
  reused) -> the skull door 0x29 (592, 576; the walk kept off door 0x2A at
  (752, 592), which leads into 0x58's south-west) -> **room 0x57's
  south-west quarter** (`ck_r61_sw_57door`, entrance 41 checked).
  The quarter's shutter 0x18 at (120, 296) is held open by tag 0x16 (hold
  switch). Traced: the switch is under the pot at (120, 352) (pot secret 0x88
  -> attribute 0x23, port right); the statue 0x1C (176, 391) is the weight
  (Statue_CheckForSwitch, port right); the pocket under the shutter
  (112..143, 312..335) is walled by 0x27 columns, so Link must be in the
  pocket when the statue reaches the switch: the statue is pushed down to row
  430, left to x 120, then pulled up through the 16-px gap onto the switch
  with Link backing into the pocket (`SW57`: the Baris 0x24 and Gibdos 0x8B
  first, the pot, then the statue; Wallmasters every 510 frames dodged, no
  grab on the kept run) -> through the shutter (`ck_r61_sw_57top`, 80, 115)
  -> the spike block's row (0x8A, 2 px a frame, x 44..199) crossed behind it
  -> **the big key** (chest 128, 112; opened from below, facing up;
  `ck_r61_sw_57bk`, bigKey[16] saved) -> out by a Wallmaster (back to
  entrance 0x29, as on the cartridge) -> outside -> door 0x2A ->
  **room 0x58's south-west** (`ck_r61_sw_58sw`, entrance 42) -> the bush hole
  (768, 528) cut and taken -> **0x58's north-east, inside the skull-pot ring**
  (`ck_r61_sw_58ne`, entrance 118 = 0x76) -> pots lifted, the bombable wall
  0x2E at (288, 136) bombed open (Bomb_CheckForDestructibles 0x08085FAC from
  the bomb ancilla 0x0811B220: door types 0x28 / 0x2A / 0x2E, port right)
  -> the strip west of it (`ck_r61_sw_58nw`, 192, 120).
  Health floor absorbed: 80 on the 0x57 puzzle run (mostly the two Gibdos),
  32 + 8 at the big key, 24 + 24 waiting for the Wallmaster / the overworld
  Gibdo by door 0x2A, 56 in 0x58's north-east (Baris, Stalfos): ~224 in all;
  the checkpoints hold 16 / 64 health.
- [ ] 61.2 **Stopped: the big chest (Fire Rod, 0x58 at 112, 344).** It sits in
  0x58's south-west top (40..215, 312..343 + the 0x27 U around the chest);
  that area joins the rest of the room only across the pits 0x20 at
  (40..71, 344..375) and (184..215, 344..375) (0x58 is in
  kDungeonPitsHurtPlayer: a fall hurts 8 and puts Link back). Every other
  part was walked / BFS'd from the north hole's landing: the north-east, the
  bombed wall's strip, the north-west (its pits toggled by tag 0x21's overlays
  1 / 2 from the corridor switches 0x3A / 0x3B: 0x0807B755 -> 0x0807B074(1),
  RoomTag_CheckForPressedSwitch 0x08079A10 -> +0xB62 = kind + 1, submodule
  3; ported as Dungeons26 OVERLAY_TAG), the one-way corridor to the
  south-east, the south-west bottom. The randomizer data (Archipelago
  worlds/alttp: 'Skull Woods First Section Hole (North)' -> 'Skull Woods
  First Section (Top)', which holds 'Skull Woods - Big Chest'; a separate
  'Bomb Jump' edge "represents bomb jumping to big chest") says the north
  hole's region reaches the chest in vanilla; the port's hole entrance 0x76
  lands at (400, 105) (entrance record 4496, 2665) in the north-east, from
  where no walk reaches the chest. Not resolved: either a connection the
  port does not draw / allow (north-west <-> south-west top), the landing
  spot, or tag 0x28 (0x0807B635: with +0xBC0 set, 0x0807A178 opens the
  room's type-0x30 door; not ported, and 0x58 has no 0x30 door in its slots)
  -- next round: trace 0x58 on the GBA (the room's object / door lists, the
  0x76 landing) and port what differs.
- [ ] Not done (goal 4): the 0x21 push switch's sheet, indoor splash / swim
  sounds, the PoD door's map steps / sounds.

Real app (cache v55, appdata from r60, full-window shots): `RUNID=real61
LEGS=pod49.lua:X,wm61.lua,pod49b.lua realp.sh r61_sw_58ne "N10 P R N30 R N30
WI300,128 P"`: Link in 0x58's skull-pot ring after the north hole
(`real/shots/real61_p02_58_win.png`). A real-app replay of the big-key leg
went another way (the Wallmaster timing differs: grabbed early).

Checkpoints (`r61/out/`): `ck_r61_sw_57door`, `ck_r61_sw_57top`,
`ck_r61_sw_57bk` (big key), `ck_r61_sw_58sw`, `ck_r61_sw_58ne`,
`ck_r61_sw_58nw` (latest). Mid-room checkpoints reload the room (statue,
foes back); 57gib is not usable.

Screenshots: `r61/shots/r61_57_bigkey.png` (0x57's north-west quarter, the
big key chest opened from below, harness), `r61/real/shots/real61_p02_58_win.png`
(real app), `r61/shots/r61_room58.png` (room 0x58 with its attribute
overlays: the big chest's pocket and the two pits).

Tests: no port change this round, so no `zelda_alttp_r61_test` (nothing new
to check). All 68 `zelda_alttp_*` files pass (`r61/out/alltests61.txt`).
Audits 304/304 rooms, 80/80 overworld areas (`AUDIT=rooms|ow run.sh audit` in
r61, the r60 `out/audit` baseline copied in), cacheVersion 55.

## Round 62 (2026-11-16)

Skull Woods' Fire Rod with real input, after porting the exploding wall that
joins room 0x58's north-west to the big chest's pocket; the back section
(fire on the skull's weeds) opened and entered. Mothula not reached.
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r62/` (the r61 kit with
r62 paths; checkpoints `ck_r62_*`). New in the kit: pod49b tokens
`AW<type>,<x>,<y>,<r>` (wait until every foe of a type is r px away) and
`AIN<type>,x0,y0,x1,y1` (wait until one is inside a box: the spark 0x5B's
loop), ow52 `PROBE<name>`; stgo61 `WISTEP=2` (2 px BFS grid: 1-row doorways
and corridors at odd y), `DOORFREE=1` (door attributes 0xF0-0xFF walkable),
star tiles 0x3A / 0x3B walkable; walk59 `WKDBG=1` prints the BFS extent and
the nearest node; probes `blast62p.lua` (the tables, `DRAWOPEN=1`),
`fit62.lua` / `fitlo62.lua` (attribute windows, `PTS=` fit test), `owreach62.lua`
(overworld 16 px reach map, `BUSH=1`), `a43.lua`, `owat62.lua`, `ev62.lua`,
`items62.lua`, `lk62.lua`, `ch62.lua`, `sp62.lua` (spark track), `py/sec62.py`
(room secrets), `py/crop.py` (pure-python PNG crop). **cacheVersion 56**
(new data.t.blast62): harness store re-imported (REIMPORT=1), real app
re-imported (`real/reimport.sh`).

- [x] 62.1 **Traced: why the big chest was out of reach.** The entrance
  table is right on the GBA and the port: 0x76 -> 0x58 (400, 105), 0x77 ->
  0x67 (128, 104), 0x78 -> 0x68 (256, 150), 0x79 -> 0x56 (320, 104); 0x58 is
  in kDungeonPitsHurtPlayer (pits hurt, no drop). Room 0x58's door list
  (0x162C28) starts with 0x3000: door type 0x30 (the exploding wall), which
  Interior's door parse skips; its header tags are 0x21 (holes) and 0x28.
  The tag table (`ldr` 0x0807B564 -> 0x08152AC4) sends 0x28 to 0x0807B634:
  +0xBC0 (dung_flag_statechange_waterpuzzle, set by the north-west lever,
  sprite 0x04 at (128, 160), already ported in Traps27) -> 0x0807A178. The
  wall's own position table (0x081677D8 via 0x0807E7B4, not the up-door
  one) puts it at (40, 216): opened, rows 27-38, columns 5-26 -- the sand
  gap between the north-west quarter and the chest's pocket becomes floor.
- [x] 62.2 **Port: the exploding wall** (new `Blast62.lua`, one line in
  ExtractA27's EXTRA list; all values from the code at import, see the
  module head): RoomTag_PullSwitchExplodingWall (tag found by its routine in
  the tag table), the opener 0x0807A178 (first slot with (type & 0xFE) ==
  0x30, the blast spot from the slot offset + `adds #20` 0x0807E7D4 and
  0x08152A98 / 0x08152AA2 by (link_y >> 8) & 1, sound `movs #0x7B`
  0x0807A22E, the tag cleared), Ancilla33_BlastWall 0x08123D00's two-blast
  state machine (step 3 frames, explosions to state 7, end 11, the idle one
  starts at the other's state 6 / timer 2, six starts, four spots from
  0x0818045C moving 13 px apart; sound 0x29), the wall step 0x080892CC (from
  the dungeon frame 0x080707DC while +0xAFC; Link held, +0x1770): each frame
  the first blast is at state 6 the offset moves a column left and the
  12-row picture (0x08167650, 49 words: 2 columns, +0xAFC - 1 fill columns,
  2 columns, 0x08089110) is drawn, +0xAFC += 2 from 1 to 21, then the door
  bit (0x081676B2) and the attributes; a room loaded with the wall open
  draws RoomDraw door 0x30 (0x0807E7B0 / 0x0807E604: two 6-row pieces from
  the pointers at 0x08167A5C / 0x0816798C + 0xA8, 18 fill columns, the
  second 0x300 bytes down). OURS: the blasts use the bomb's explosion
  picture (no damage), the debris ancilla 0x32 is not drawn, the open state
  is the room's memory (mem.blast62).
- [x] 62.3 **Route, real input (harness from checkpoints, HPFLOOR=16).**
  `ck_r61_sw_58nw` -> through the bombed wall into the north-east, Mini
  Helmasaur 0x13 / 0x26 fought (GF), wait for the spark's loop to be on the
  ring's far side (`AIN5B,345,80,360,100`), the star 0x3B (overlay 2: the
  north-west's pits close) -> the north-west, the lever pulled (A + down) ->
  **the wall blows open** (~110 frames) -> Mini Moldorms fought in the gap ->
  **the big chest: Fire Rod** -> back up, east, the spark timed again, down
  the corridor (star 0x3A / 0x3B), the south-east, the west door, out
  (`ck_r62_out` was first written here at (744, 603), then overwritten by
  the 0x56 OUT below) -> skull door 0x29 (584, 606) -> 0x57's south-west
  (`ck_r62_sw_57sw`, entrance 41) -> its west door (exact y 376) -> **room
  0x56** (`ck_r62_sw_56in`) -> its south-west, Gibdo-like 0x26 fought,
  Wallmasters dodged (wm61) -> out by door 0x28 into the fenced west
  forest (`ck_r62_dw_swwest`, 232, 544) -> walked to (144, 283) (NODOOR to
  keep off door 0x28), Fire Rod (menu slot 7) fired up at the weeds 0x43
  (152..167, 264): **Skull Woods' back opens** (event bit 0x20 of area 0x40;
  `ck_r62_dw_swfire`) -> **room 0x59** (`ck_r62_sw_59in`, entrance 43).
  Health floor absorbed per leg: 0x58 leg 0 (the first tries took 32-48:
  the spark, the 0x18s at the lever), 0x57 -> 0x56 4 (a Bari), 0x56 -> west
  0, west -> fire -> 0x59 0 (8 on one try at the door).
- [ ] 62.4 **Stopped in 0x59.** Its small key is the chest (160, 368) on the
  lower level of the west half, in a pocket walled by 0x27 on the west and
  top and open only east through the 0x85 doorway (rows 48-49); the west
  stairs (0x3E at (80, 408)) reach the rest of the lower west half, not the
  pocket. The east half (the doorway's other side) was not reached; the key
  door (128, 48) to 0x49 needs that key. Mothula not reached.
- [ ] Not done (goal 4): the 0x21 push switch's sheet, indoor splash / swim
  sounds, the PoD door's map steps / sounds.

Real app (cache v56 after `real/reimport.sh`, full-window shots):
`RUNID=real62 WISTEP=2 DOORFREE=1 realp.sh r61_sw_58nw "<the 0x58 leg>"`:
the lever, the blast, the chest (`real/shots/real62_p17_58_win.png` the
explosions with the wall opening below, `real62_p24_58_win.png` the Fire Rod
chest opened), 0 floor.

Checkpoints (`r62/out/`): `ck_r62_out` (outside door 0x29, Fire Rod),
`ck_r62_sw_57sw`, `ck_r62_sw_56in`, `ck_r62_dw_swwest`, `ck_r62_dw_swfire`,
`ck_r62_sw_59in` (latest). Not usable: `ck_r62_sw_58blast`,
`ck_r62_sw_58frod` (mid-room 0x58 reloads put the star overlay back to 1
and the pocket's Mini Moldorms back).

Tests: new `zelda_alttp_r62_test` (the ExtractA27 hook; Blast62's pieces on
stand-ins (6- and 12-row layouts), the door lookup, the whole blast on a
stand-in room (flag + tag gate, ten steps from the middle to columns 5-26,
seven blasts, Link held only while the wall opens, no second blast); with
the ROM: the call sites, the imported tag's routine, the shapes (49 / 25
words, one fill word, the second piece six rows down), every room with the
tag has a type-0x30 door whose opening is walkable; the game: the flag in
the tagged room opens the wall, Link held then free, a reload draws it
open; 33 checks). All 69 `zelda_alttp_*` files pass (`r62/out/alltests62.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`AUDIT=rooms|ow run.sh audit` in r62), cacheVersion 56.

## Round 63 (2026-11-16)

Skull Woods finished with real input: room 0x59's key, the star-tile pit
room 0x49 and its torch shutter, 0x39, the drop to Mothula, Mothula beaten
with the sword, heart container, crystal 3, out. Two ports: the burn (damage
code 0xFD, the Fire Rod on Gibdos) and room tag 0x20 (a floor switch blows
the exploding wall). Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r63/`
(the r62 kit with r63 paths; checkpoints `ck_r63_*`). New in the kit:
pod49b tokens `FR<type>[/type..],<n>` (`fr63.lua`: the selected item at the
foes of those types on Link's level, `FRV=1` vertical shots only, `FRMIN`
stand-off, no step into a pit), `LT<dir>` (lift / throw where Link stands),
`HOLD<types>,<n>` (stay, swing at what comes), `WMW<n>` (wait, dodging, until
a Wallmaster has come and gone), `KEYGET`, `MF<n>` (`mf63.lua`: Mothula,
stand below its body at y - z, swing up), `STDBGON`; stgo61 `WITOL=1`
(the last path node within 1 px: the 2 px oscillation that cost up to 600
frames a walk is gone); gf61 `GFNEAR=<px>` (foes by distance, not quadrant);
pod49's health floor also counts the pit falls' 8 (Dungeons26, not
hurtLink); probes `at63.lua` (hex attribute window, upper / lower),
`dmg63.lua` (hp and damage per class), `burnp63.lua`, `push63p.lua`,
`tag63.lua`, `act63.lua`, `torch63.lua`, `fc63.lua` (frame, Wallmasters),
`hits63.lua`, `lq63.lua`, `prog63.lua`, `spr63.lua`; scripts `ch59.sh`
(0x59 to the key door), `bl49.sh` (0x49 south-west), `e49.sh` (0x49 east
cross). **cacheVersion 57** (new data.t.burn63, data.t.push63): harness
store re-imported (REIMPORT=1), real app re-imported (`real/reimport.sh`).

- [x] 63.1 **Port: the burn** (new `Burn63.lua`, one line in ExtractA27's
  EXTRA list; all values read at import, see the module head). The port held
  every damage code 251-255 as a 64-frame stun (Tools.spriteHit), so the
  Fire Rod only froze Skull Woods' Gibdos (32 hp, 4 a sword swing). GBA:
  Sprite_ApplyCalculatedDamage 0x080C414C keeps the code in +0xEB5; the
  hit-timer step 0x080C2160 compares it (`cmp #n` 0x080C2190) and sets
  sprite state 7 (`movs #n` 0x080C219C) with sprite_delay_main `movs #n`
  0x080C21A6 (0x70), sound `movs r1, #n` 0x080C2196 (sprite pan 0x080CF140),
  flags2 += 2; the module table (literal 0x080C33E2) entry 7 is
  SpriteModule_Burn 0x080CA688: hit timer 0; while the delay is above
  `cmp #n` 0x080CA6DC the sprite's own routine runs (0x080C33FC: it keeps
  walking and touching), at `cmp #n` 0x080CA6B6 it dies with its drop
  (0x080C6DA8 -> 0x080C6818, no puff); the flames: sprite_graphics =
  0x081791D4[delay >> 3] (literal 0x080CA712), flags `movs #n` 0x080CA720,
  Sprite_DrawMultiple of two entries from 0x081791F4 (literal 0x080F2422).
  Hooks by wrapping (install): Tools.spriteHit (a stun whose code is the
  burn code becomes the burn), Actors.update (the countdown, hold, death),
  Sprites.drawActor (flames; the sprite hidden below the threshold).
  OURS: below the threshold the sprite is put back where it stood and kept
  from touching Link (its timers still run).
- [x] 63.2 **Port: room tag 0x20** (new `PushWall63.lua`, one line in
  ExtractA27; Blast62 lends its opener, one line `M.startBlast`). The tag's
  routine 0x0807B61C: bl 0x080798DC (RoomTag_CheckForPressedSwitch), `cmp
  #1`, bl 0x0807A178 (Blast62's opener). 0x080798DC: nothing while Link is
  held (+0x1770) / in an aux state (+0x1702); tile ((x - `subs #n`
  0x08079890) & 0x1F8) >> 3 | ((y + `adds #n` 0x080798A8) & 0x1F8) << 3 (the
  lower table when +0xA10); the pair at p, p + 64, p + 1, p + 65 both
  `cmp #n` 0x08079906 or 0x08079914 (0x23 / 0x24, not the 0x3A / 0x3B of
  0x08079A10 the overlay tags use), the row below repeating the left or the
  right one. Rooms with the tag: 0x7C (Ganon's Tower), which has the type-0x30
  door; the test opens it by standing on its switch.
- [x] 63.3 **Route, real input (harness from checkpoints, HPFLOOR=16).**
  `ck_r62_sw_59in` (entrance 43, keyPalace 16) -> the west stairs 0x3E up to
  the lower level -> north, through the 0x85 doorway (rows 16-17) to the
  east half's lower floor (the two spike blocks 0x8A timed: `AIN`) -> the
  Gibdos 0x8B burned with the Fire Rod from the middle (two shots; the
  bumpers 0x93 block shots on the sides) -> back west through the 0x85
  doorway (rows 48-49) into the pocket -> **the small key** (chest 160, 368;
  `ck_r63_sw_59key`) -> back the same way, down the stairs, the walkway ->
  the key door (128, 48) -> **room 0x49** (`ck_r63_sw_49in`). 0x49's
  south-west is a star-tile room: 0x3A turns on pit set B, 0x3B set A (the
  entrance stands on a 0x3B); the way: pot 0x73 lifted, up onto the 0x3A
  (B), the west strip, the bottom-left 0x3B (A, a heart pot), up the west
  column (pots: nothing, small magic), three Baris 0x23 / 0x24 burned with
  the rod, along the top, onto the middle 0x3A (B), up, onto the top 0x3B
  (A), its pot (heart) lifted, down the right column, the east door ->
  the east cross (`ck_r63_sw_49e`): four Gibdos with the sword (`GF`), the
  two small-magic pots, then **tag 0x33's four torches** inside one 768-frame
  burn (the lamp on C3 / C2 / C1, the Fire Rod across the pits on C0) ->
  the shutter (288, 136) -> the north-west (`ck_r63_sw_49tl`): a Gibdo and
  Mini Moldorms, the slashable curtain door 0x32 (112, 32) cut -> **room
  0x39** (`ck_r63_sw_39in`): the Gibdo 0x8B drops the key -> the key door
  (208, 376) -> the south-east (`ck_r63_sw_39br`): the pot (400, 352)
  lifted (small magic), the spike block's lane timed, the pit (368..399,
  376..407; header hole warp 0x29) -> **Mothula's room 0x29**
  (`ck_r63_sw_29in`) -> **Mothula beaten with the sword** (`MF`, 31 swings,
  ~1150 frames) -> **the heart container (64 -> 72)** -> **crystal 3**
  (crystals 0x12 -> 0x52, bossBeaten 41) -> outside the back entrance
  (`ck_r63_dw_sw_done`, area 0x40 (160, 231), 9 hearts). Wallmasters (0x90)
  every 510 frames in 0x49 / 0x39: the walks are timed after one (`WMW`).
  Health floor absorbed per leg: 0x59 88 (the spark 16, the burning Gibdos
  16, the walkway's Mini Moldorms / fire snake 56), 0x49 south-west 8, east
  40 (the Gibdos), north-west 24, 0x39 56, Mothula 88: ~304.
- [ ] 63.4 **Stopped before Thieves' Town.** The back entrance's ground
  (x 96..528, y 96..560 of area 0x40) is closed (`owreach62.lua` with
  bushes): the way out is back through door 0x28 and room 0x56 / 0x57 to the
  front woods, then south to the village (Thieves' Town: the statue court,
  about (516, 1986) in the Dark World's west column). Not walked.
- Seen, not changed: in the real app Mothula's heart container is drawn as
  broken pieces (`real63b_p04_29_win.png`; Palace draws 0xEA with
  spr:single from the room's sheets: Mothula's room does not hold its chars)
  -- next round: trace HeartContainer's draw on the GBA. 0x49's star tiles,
  torches, curtain, 0x39's key drop and hole warp: port right as met.
- [ ] Not done (goal 4): the 0x21 push switch's sheet, indoor splash / swim
  sounds, the PoD door's map steps / sounds.

Real app (cache v57 after `real/reimport.sh`, full-window shots):
`RUNID=real63b realp.sh r63_sw_29in "MF600 MF1500 N60 P .. Hd16 .. R x6"`:
Mothula beaten, heart container taken (72), crystal, out to area 0x40
(`real/shots/real63_p03_29_win.png` the fight, `real63b_p08_29_win.png`
nine hearts after the container, `real63b_p04_29_win.png` the container
drawn broken).

Checkpoints (`r63/out/`): `ck_r63_sw_59key`, `ck_r63_sw_49in`,
`ck_r63_sw_49e`, `ck_r63_sw_49tl`, `ck_r63_sw_39in`, `ck_r63_sw_39br`,
`ck_r63_sw_29in`, `ck_r63_dw_sw_done` (latest: outside, crystal 3). All
entrance 43, keyPalace 16. Mid-room ones reload the room (foes and the
Wallmaster timer back).

Tests: new `zelda_alttp_r63_test` (the ExtractA27 / Blast62 hooks; Burn63
on stand-ins: the start, the sprite running above the threshold, held at it,
dying at the end with its key and no puff, the flames' picture by delay >> 3
with the module's flags, only the burn code burns; PushWall63 on stand-ins:
the tile from Link's spot, the p / p + 64 / p + 1 / p + 65 order, the row
below, mixed pairs, the lower table, the tag gate, Link held, once; with the
ROM: the call sites, the compared code, the module table's entry, a flame
picture for every delay step, the imported tag's routine; the game: a room
sprite set on fire by the rod's hit burns and dies without a puff, the push
tag's room opens its wall with Link on its switch; 66 checks). All 70
`zelda_alttp_*` files pass (`r63/out/alltests63.txt`). Audits 304/304 rooms,
80/80 overworld areas (`AUDIT=rooms|ow run.sh audit` in r63), cacheVersion 57.

## Round 64 (2026-11-17)

Mothula's heart container drawn right (the animated sprite tile slot), the
way back out of Skull Woods and south to the Village of Outcasts with real
input, the Thieves' Town grate ported (the gargoyle's door was shut for
good), into Thieves' Town: the map and the big key. Blind's maiden, the
Titan's Mitt and Blind not reached. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r64/` (the r63 kit with r64
paths; checkpoints `ck_r64_*`). New in the kit: ow52 token `HK<key+key>,<n>`
(hold several keys: `HKr+down,2` is the grate pull), probes `hc64.lua` /
`hc64b.lua` (the animated tile table; the heart container shot off Link),
`owreach64.lua` (owreach62 bounded by the current area: any area, absolute
coordinates), `owat64.lua` (overworld attributes round a spot), `owact64.lua`,
`owlist64.lua` (an area's sprite list, all phases), `ents64.lua` (overworld
doors by entrance in a box), `gr64.lua` (the grate's import, spot, hit box);
`guard64.lua` (`WIGUARD=1`: a fight guard in the WI / WK walkers -- fight a
sword foe within `GUARDE` px with gf61 for up to `GUARDF` frames, wait /
back off from hazards within `GUARDR`; `PROBEguardoff64` / `PROBEguardon64`
per segment); gf61 now finds overworld foes (owActors) too; scripts
`chain64.sh` (the whole kept route, `P=<prefix>` for the checkpoint names),
`guardab.sh` (legs with and without the guard). **cacheVersion 58** (new
data.t.anim64, data.t.grate64): harness store re-imported (REIMPORT=1), real
app re-imported (`real/reimport.sh`).

- [x] 64.1 **Port: the heart container's picture** (new `AnimTile64.lua`,
  one line in ExtractA27's EXTRA list). Traced: Sprite_HeartContainer
  0x080F2808 on its first frame calls DecodeAnimatedSpriteTile_variable
  0x0812FBC4 with `movs r0, #n` 0x080F2832, then draws with
  Sprite_PrepAndDrawSingleLarge 0x080C6240 (char = Tab2[Tab1[type] (u16) +
  gfx]); that char is on OBJ page 0, row 2 -- the slot the decoder
  writes: u16 table (literal 0x0812FBC8)[var] -> sheet (w >> 11) + `adds
  #n` 0x0812FBD8 from the sheet pointers (literal 0x0812FBD6, LZ77), two
  tile rows (0x200 apart, literals 0x0812FBE0 / 0x0812FBF4) of `movs r2, #n`
  0x0812FBEE words from w & 0x7FF to RAM 0x0200B0C0 / 0x0200B100, which the
  frame's VRAM list (pairs at 0x080A6E58 / 0x080A6E60) copies to OBJ chars
  (VRAM - 0x06010000) / 32 and 32 below. The port drew the slot's chars from
  sheet 0's lower half (broken pieces). Ported by wrapping Sprites:
  tileSource (the slot's 2 x 2 chars from the decoded variant once a decode
  has happened in the current sprite layout; a layout change in setRoom
  brings the plain tiles back) and drawActor (the heart container decodes
  its variant). Every boss room's container goes through drawActor
  (Palace / Dungeons26 / DesertPalace spawn 0xEA), so all are fixed.
  OURS: the other decoder callers (keys 0x1E, the book 0x0E, 0x11, 0x1C,
  0x22, 0x28, ...) keep their own drawing.
- [x] 64.2 **Route, real input (harness from checkpoints, HPFLOOR=16).**
  `ck_r63_dw_sw_done` (area 0x40, 160, 231) -> door 0x28 (`E40`) -> room
  0x56 (walked 1 px grid: its corridor needs an even y) -> the east door
  (y 376) -> 0x57 -> its skull door out (`ck_r64_u_swfront`, 584, 587) ->
  `WK904,1000` with NODOOR=584,590 (the walk otherwise steps back into the
  skull's mouth) -> area 0x51 (`ck_r64_u_51`) -> `WK792,1508` -> the Village
  of Outcasts 0x58 (`ck_r64_u_58`) -> entrance 52's door (504, 1992): shut
  (see 64.3) -> the pull -> **Thieves' Town, room 0xDB** (`ck_r64_u_ttin`,
  entrance 52, keyPalace 22) -> the map (chest 128, 160; lower level) ->
  the lower tunnel north (x 244) -> 0xCB (`ck_r64_u_ttcb`; its chest: 20
  rupees) -> east on the lower level -> 0xCC (`ck_r64_u_ttcc`) -> south at
  x 120 -> 0xDC (`ck_r64_u_ttdc`) -> west at y 360 -> 0xDB's south-east
  house -> **the big key** (chest 392, 352; `ck_r64_u_ttbk`, bigKey[22]).
  Health per leg (start 72): 0x56 / 0x57 out 16 taken (Ropa on the way to
  door 0x28), area 0x40 -> 0x51 16, 0x51 -> 0x58 0, the grate 0, 0xDB / map
  / 0xCB 0, 0xCB -> 0xCC 0, 0xCC -> 0xDC 16 (spark 0x5B, 0xA6), 0xDC -> big
  key 8 taken + **8 floor**: the whole kept chain absorbed 8 (r63: ~304).
  Also seen: 0xDC's upper level (stairs 0x3E at (128, 216) from the lower
  houses, `ck_r64_tt_dcup`) and 0xDB's east corridor via the 0xDC west door
  (a dead end on the upper level).
- [x] 64.3 **Port: the Thieves' Town grate** (new `Grate64.lua`, one line
  in ExtractA27). The grate (sprite 0x14 in area 0x58's list) was never
  loaded, so the statue's door could not open. Traced: its routine 0x080D2CE8
  (the routine table, literal 0x080C3412, gives the type at import): prep
  0x080D2C7C gone if save_ow_event_info[0x58] & 0x20 (literal 0x080D2C82,
  `movs #n` 0x080D2C86), else x - `subs #n` 0x080D2CA4 (+0xEE2 / +0xF02,
  the SNES 0x0D10 / 0x0D30); touching Link (0x080C500C) sets
  link_need_for_pullforrupees_sprite (+0x188F) and its mark (+0xF62); not
  touching with the mark and Link pulling (+0x1791 & 1): sound `movs r1,
  #n` 0x080D2D4A, Overworld_AlterGargoyleEntrance 0x0808F1C4 (bl at
  0x080D2D50), debris 0x080F4CB8, gone. The alter: map16 position (literal
  0x0808F1C8) <- tile (literal 0x0808F1D6 = map16 * 4: 0x0808B8B8 indexes
  the map16 table 0x08155B4E by it), then from tile (literal 0x0808F1E2) on
  one map16 per call, the position + 2 (0x0808B9F8 / 0x0808B948): positions
  (`movs; lsls` 0x0808F1DC) x1, (literal 0x0808F1F0) x2, (literal
  0x0808F204) x2; save_ow_event_info[area] (literal 0x0808F218) |= `movs #n`
  0x0808F21C; sound `movs r0, #n` 0x0808F222. The draws' call sites checked
  at import. Ported: the grate where the list puts it, its hit box, the
  pull, the six tiles (owSetMap16, map16 pictures merged), the event bit
  (drawn again whenever the area loads), both sounds, the dash cancelled on
  contact. OURS: the pull is R held with up / down facing the grate (the
  cartridge's pull state is not ported) and opens at the pull; no debris.
- [x] 64.3b **Fighting (goal 3).** `guard64.lua` (`WIGUARD=1`): A / B on
  four legs (`guardab.sh`, damage taken + floor): Skull Woods front -> 0x51
  16 -> 0, 0x51 -> 0x58 16 -> 0, 0xCC -> 0xDC 24 -> 10, 0xDC -> big key
  0 -> 16. The whole chain with the guard on (P=g_, not kept) took more
  (40 taken + 112 floor: the guard fights 0xA5 / 0xA6 in Thieves' Town's
  tunnels and loses to the sparks) than without (40 + 8): the kept chain is
  unguarded; the guard is an opt-in for overworld legs.
- [ ] 64.4 **Stopped in Thieves' Town with the big key.** The big-key door
  is 0xCC's north door (384, 48) on the upper level; 0xCC's upper corridor
  was not reached (the upper corridors are pieces joined by the houses'
  stairs and the lower tunnels; 0xDB's / 0xDC's pieces walked so far do not
  lead there). Blind's maiden, the Titan's Mitt, Blind: not reached.
- [ ] Not done (goal 4): the 0x21 push switch's sheet, indoor splash / swim
  sounds, the PoD door's map steps / sounds.

Real app (cache v58 after `real/reimport.sh`, full-window shots):
`RUNID=real64 realp.sh r63_sw_29in "MF600 MF1500 Hl16 P N4 P N10 P"`:
Mothula beaten, **the heart container whole** (`real/shots/real64_p06_29_win.png`);
`RUNID=real64g LEGS=pod49.lua:X,ow52.lua OWSTEPS="E52 SHa HKr+down,2 N10 SHb E52 ; N10 P" realp.sh r64_u_58 ""`:
the grate pulled, the gargoyle's door open (`real64g_b_win.png`), into 0xDB
(`real64g_p02_DB_win.png`).

Checkpoints (`r64/out/`): the kept chain `ck_r64_u_swfront`, `ck_r64_u_51`,
`ck_r64_u_58`, `ck_r64_u_ttin`, `ck_r64_u_ttcb`, `ck_r64_u_ttcc`,
`ck_r64_u_ttdc`, `ck_r64_u_ttbk` (latest: big key, room 0xDB lower, 395,
360, 16 health); from earlier piecewise runs `ck_r64_dw_swfront`,
`ck_r64_dw_51`, `ck_r64_dw_58`, `ck_r64_tt_in`, `ck_r64_tt_cb`,
`ck_r64_tt_cc`, `ck_r64_tt_dc`, `ck_r64_tt_bk`, `ck_r64_tt_dcup` (0xDC
upper level). Entrance 52, keyPalace 22 checked on `ck_r64_u_ttbk`.

Screenshots: `r64/shots/r64_hc_big.png` (Mothula's room, the heart
container drawn whole, harness), `r64/shots/r64_grate.png` (the statue
before / after the pull), `r64/shots/r64_tt1f.png` (Thieves' Town's 1F
rooms 0xCB / 0xCC / 0xDB / 0xDC), `r64/real/shots/real64_p06_29_win.png`,
`r64/real/shots/real64g_b_win.png` (real app).

Tests: new `zelda_alttp_r64_test` (the ExtractA27 hooks; AnimTile64 on
stand-ins: the slot's 2 x 2 chars, rows a rowStep apart, others / page 1 /
unknown variants left alone, the decode's cache drop, the installed
tileSource / setRoom / drawActor wrappers; Grate64 on stand-ins: the spot
with the prep's x adjust, contact mark and flag, facing needed, the flag
cleared off it, the pull draws every tile at its byte position, map16
merged, the event bit, drawn again on re-entry only, Dark World only; with
the ROM: the call sites, the heart container's char is the slot, the
variant's sheet / alignment / picture, six placements with their map16, the
imported type runs the grate routine; the game: the heart container's draw
switches its char, Link's pull opens the grate and changes the door's
tiles; 50 checks). All 71 `zelda_alttp_*` files pass (`r64/out/alltests64.txt`).
Audits 304/304 rooms, 80/80 overworld areas (`AUDIT=rooms|ow run.sh audit` in
r64: `out/audit_rooms64.log`, `out/audit_ow64.log`), cacheVersion 58.

## Round 65 (2026-11-17)

Thieves' Town finished with real input: the big-key door, the attic floor
bombed (light onto Blind's room), Blind's maiden out of her cell as a
follower, the Titan's Mitt, Blind beaten, the heart container, crystal 4,
out to the Village of Outcasts. Two ports: the thrown bomb's tile test
(the ancillae's own collision classes: the attic's rail stopped the bomb)
and the maiden drawn by Tagalong_Draw. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r65/` (the r64 kit with r65
paths; checkpoints `ck_r65_*`). New in the kit: `chain65.sh` (the kept
route, 19 legs, each from the checkpoint the last one wrote; `P=<prefix>`,
`FROM=<leg>`; prints the floor's assist per leg), pod49b tokens
`GO<room>,<x>,<y>[u|l]` (planner walk to a spot / level), `BOMBTH<dir>`
(lay, lift, throw a bomb), `PR[n]` (the action button), `PA[n]`, `TXT`
(close the text box), `GT<x>,<y>` (hold the keys towards a spot:
conveyors), `STEER<u|d><x>,<y>` (hold up / down steering back to x),
`STAIRU<room>,<x>,<y>` (stairs with knock-back retries), `GTA<type>` (walk
to a live actor: the prize); stgo61 `WIFREE=<hex,..>` (more free
attributes: pegs 0x66, conveyors 0x68-0x6B); gf61 `GFBODY=1` (skip
sprite_A != 0: Blind's flying heads); probes `ttmap65.lua` (attribute maps
of a block of rooms per level, PNG + text), `path65.lua` (the planner's
path with its transitions), `sec65.lua` (secrets, chests, locks, sprites
per room), `lock65.lua`, `mem65.lua`, `blind65.lua`, `bfdbg65.lua`.
**cacheVersion 59** (new data.t.anc65): harness store re-imported
(REIMPORT=1), real app re-imported (`real/reimport.sh`).

- [x] 65.1 **0xCC's upper corridor (goal 1): nothing missing.** The
  attribute maps of 0xCB / 0xCC / 0xDB / 0xDC per level
  (`shots/ttmap65_1f_U.png` / `_L.png`) and the planner (`reach63.lua`,
  `path65.lua`) show the way: 0xDB lower -> the tunnels -> 0xDC -> 0xCC's
  upper ring -> the big-key door. r64's walker never asked for it (B.allow
  was the Palace of Darkness list: `PODALLOW`). The door's cells are
  (376..391, 40..63): Link at x 376 facing up opens it (r64 tried x 384).
- [x] 65.2 **Port: the thrown bomb's tile test** (new `AncColl65.lua`, one
  line in ExtractA27's EXTRA list; values read at import). The port flew a
  thrown bomb until Interior:blocked (Link's walls) met it, so a bomb
  thrown at room 0x65's low rail (attribute 0x02, round the cracked floor)
  dropped at Link's feet and the attic could not be lit. Traced:
  Ancilla07_Bomb 0x0811AC24 -> Ancilla_CheckTileCollision 0x080BFE6C (bl at
  0x0811ACF4, r1 = 0) -> Ancilla_CheckTileCollisionOneFloor 0x080BFFFC (bl
  at 0x080BFF70): probe = spot + kAncilla_Y / Xoffs[dir] (lo / hi tables,
  literals 0x080C0018 / 0x080C002A / 0x080C0048 / 0x080C005A), the floor's
  attribute (0x080C781C), class = table (literal 0x080C011A)[attr]: 0
  none, 1 wall, 2 the slope test (0x080C7948), 3 wall while +0x1860, 4
  (ledges) the floor flag +0xA74, no wall. 0x02 is class 0 (for Link 0x02
  is a wall: the indoor handler table 0x0816832C gives 0x01 and 0x02 the
  same routine). Hooks: G:bombFrame marks the flying bomb, G:carryBlocked
  uses the classes for it. OURS: the port's probe point (+ the offsets),
  class 2 = wall, class 3 = free; other ancillae keep their tests.
- [x] 65.3 **Port: the blind maiden as a follower** (new `Tagalong65.lua`,
  one line in Ending27's drawLink). Round 27 drew follower 6 with the
  crystal maiden's sprite pictures; Tagalong_Draw (0x0811571C; literals
  0x081158CC pals, 0x08115958 / 0x081159EC offs, 0x08115964 / 0x081159F8
  SprXY, 0x08115994 / 0x08115A2C DmaAndFlags; follower 0x0C / 0x0D
  branches 0x0811594E / 0x08115944) draws every follower from one set of
  tables, which Smiths.lua already imports (followers 7 / 8): the maiden
  now uses them (Smiths.drawFollower, follower 6). Also: ThievesTown.lua's
  head comment said the maiden was not ported (stale since r27).
- [x] 65.4 **Route, real input (harness from checkpoints, HPFLOOR=16;
  Link has 16 / 72 the whole dungeon, so the floor takes every hit).**
  `chain65.sh` (P=c, all 19 legs re-run from `ck_r64_u_ttbk`): 01 0xDB ->
  0xCC's upper ring -> the big-key door (376, 48) -> 0xBC
  (`ck_r65_cttbc`; floor 156: Zazaks 0xA5 / 0xA6, fire snake 0x80) -> 02
  the Stalfos 0xA7, the pot (408, 64) lifted from the left: key
  (`cttbckey`, 8) -> 03 down the hall, the key door (280, 384), 0xBC west
  -> 0xBB (`cttbb`, 0) -> 04 0xBB's conveyor column up -> 0xAB (`cttab`, 8)
  -> 05 the pot (80, 384): key, the spike lanes timed (`AW8A`), the stair
  mask (120, 296), the spiral up -> attic 0x64 (`ctt64in`, 8) -> 06 the pot
  (192, 448) lifted, its switch (tag 0x17) opens the shutter -> 0x65
  (`ctt65in`, 2) -> 07 the rats, **the bomb thrown over the rail: the floor
  bombed, room 0x65's light on** (`ctt65lit`, 4; the chest: 3 bombs) ->
  08 back west, 0x64's shutter opens on the quadrant crossing, the spiral
  -> 0xAB (`ctt65ab2`, 8) -> 09 the spikes, 0xBB (`cttbb2`, 24) -> 10 0xBB's
  top -> 0xBC's north-west (`cttbc2`, 0) -> 11 the spiral -> 0x45
  (`ctt45in`, 32) -> 12 the big gray block 0x2C (two segments lifted with
  the glove) -> 0x45's south (`ctt45bot`, 16) -> 13 the three cell locks
  (big key, `PR`), the key chest (432, 88), **the maiden: message, follower
  6** (`ctt45maid`, 176: Zazaks / Zols in the cells) -> 14 west -> 0x44
  (`ctt44in`, 112) -> 15 the key door (280, 384), **the big chest: the
  Titan's Mitt** (gloves 2; `ctt44mitt`, 0) -> 16 the conveyor cross
  (`STEER`) -> 0x45 -> the spiral -> 0xBC (`cttbc3`, 20) -> 17 the conveyor
  room, the pot (200, 56) lifted, its switch (tag 0x17) opens the shutter
  -> 0xBC's hall -> 0xAC (`cttacin`, 4) -> 18 the maiden into the light:
  "Too bright!", Blind (`cttblind`, 0) -> 19 **Blind beaten with the sword
  (three heads, `GFBODY`), the heart container (72 -> 80), crystal 4
  (crystals 0x52 -> 0x72, bossBeaten 0xAC)**, out to area 0x58 (512, 1999)
  (`cttdone`, 152). Health floor absorbed per leg: 156, 8, 0, 8, 8, 2, 4,
  8, 24, 0, 32, 16, 176, 112, 0, 20, 4, 0, 152 = **730** (r64: 8, r63:
  ~304) -- Link entered with 2 hearts. Entrance 52, keyPalace 22 checked on
  `cttacin` / `cttdone`.
- [ ] Seen, not changed: the cell locks are drawn shut again after a
  checkpoint reload (their memory says open, Link walks through); the
  maiden's "don't go this way" message plays when a checkpoint loads on its
  trigger; in the real app's crystal scene a second, darkened Link is drawn
  at the room's top-left (`real65c_p21_AC_win.png`); Blind's transform
  picture (gfx 21) looks broken for a few frames.
- [ ] Not done (goal 3): the 0x21 push switch's sheet, indoor splash / swim
  sounds, the PoD door's map steps / sounds.

Real app (cache v59 after `real/reimport.sh`, full-window shots):
`RUNID=real65a realp.sh r65_ctt65in "... BOMBTHu ..."`: the attic floor
bombed through the rail (`real/shots/real65a_p11_65_win.png`);
`RUNID=real65b realp.sh r65_ctt45c3 "C WI400,112 ..."`: the maiden
following, Tagalong_Draw's pictures (`real65b_p06_45_win.png`);
`RUNID=real65c realp.sh r65_cttacin "..."`: Blind (`real65c_p10_AC_win.png`),
crystal 4's maiden (`real65c_p21_AC_win.png`), out to area 0x58.

Checkpoints (`r65/out/`): the kept chain `ck_r65_cttbc`, `cttbckey`,
`cttbb`, `cttab`, `ctt64in`, `ctt65in`, `ctt65lit`, `ctt65ab2`, `cttbb2`,
`cttbc2`, `ctt45in`, `ctt45bot`, `ctt45c3`, `ctt45maid`, `ctt44in`,
`ctt44mitt`, `cttbc3`, `cttbc4`, `cttacin`, `cttblind`, `cttdone`
(latest: outside Thieves' Town, crystal 4, 10 hearts); the piecewise
first runs `ck_r65_tt*` (same legs).

Screenshots: `r65/shots/ttmap65_1f_U.png` (0xCB / 0xCC / 0xDB / 0xDC upper
attributes), `r65/shots/r65_maiden_follow.png` (the maiden follower,
harness), `r65/shots/r65_blind_spawn.png` (the maiden turns into Blind),
`r65/real/shots/real65a_p11_65_win.png`, `real65b_p06_45_win.png`,
`real65c_p10_AC_win.png` (real app).

Tests: new `zelda_alttp_r65_test` (the ExtractA27 / Ending27 hooks, the
cacheVersion; AncColl65 on stand-ins: the class per attribute, the probe
offsets per direction, class 1 / 2 walls, 3 / 4 free, the install only
for a flying bomb indoors; Tagalong65 on stand-ins: follower 6 at the
trail's spot, its facing, walking / standing, no tables -> the old
picture; with the ROM: the call sites, 256 classes 0-4, a low wall like
the floor and a wall not, Tagalong_Draw's tables imported; the game: a
bomb thrown at a thin 0x02 wall in a room found at run time flies over
it; 29 checks). All 72 `zelda_alttp_*` files pass (`r65/out/alltests65.txt`).
Audits 304/304 rooms, 80/80 overworld areas (`AUDIT=rooms|ow run.sh audit` in
r65: `out/audit_rooms65.log`, `out/audit_ow65.log`), cacheVersion 59.

## Round 66 (2026-11-17)

Round 65's four leftovers fixed against the cartridge, then the route on
from Thieves' Town to the Ice Palace's door with real input (the Magic
Mirror, Lake Hylia swum, the island's heavy rock lifted with the Titan's
Mitt, its warp, entrance 45). Stopped in room 0x0E: its shutter wants the
Freezor dead and the Fire Rod wants 16 magic (Link has 12). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r66/` (the r65 kit with r66
paths; checkpoints `ck_r66_*`). New in the kit: `chain66.sh` (the kept
route, 6 legs, `P=<prefix>`, `FROM=<leg>`, ow52 legs through `o.sh`),
`harness/swim66.lua` (`SWIM66="x,y[v];..."`: hold the keys towards each
point, x first, or y first with `v`: swimming), probes `lock66.lua` /
`lockw66.lua` (chests, locks, their map words), `blind66s.lua` /
`blind66d.lua` (Blind's picture 21), `trig66.lua` (kTagalong_IndoorInfos),
`owgrid66.lua` / `owasc66.lua` (overworld attributes as hex / ASCII),
`lift66.lua`, `ent66.lua` (entrance, keyPalace, magic), `acts66.lua`,
`tag66.lua`, `acount66.lua` (attribute histogram per room),
`potmag66.lua` (rooms whose pots hide magic), `owsec66b.lua`,
`owspr66b.lua`, `inv66.lua`. ow52's walker now also picks up magic jars
(and with `PICKALL=1` hearts, bombs, arrows). ck25.lua (the checkpoint
loader) holds the follower while it passes the entrance (see 66.2).
**cacheVersion 60** (new data.t.cell66): harness store re-imported
(REIMPORT=1), real app re-imported (`real/reimport.sh`, v60).

- [x] 66.1 **Port: the opened big-key lock's floor** (new `Cells66.lua`,
  one line in ExtractA27's EXTRA list; values read at import). The port
  opened a cell lock (subtype-3 0x18) by clearing its attributes only, so
  the pre-rendered map kept the lock: Thieves' Town's three cells showed
  shut locks after a reload. OpenChestForItem (0x08084008), its lock
  branch (0x08084080: dung_chest_locations bit 15, the big key, the state
  bit kChestOpenMasks 0x081676F2) writes four words of the dungeon object
  tile table (base literal at 0x080840A8 = SNES kDungeonObjectTiles) at
  word (dung_floor_2_filler_tiles >> 1) + 2 / 3 / 0 / 1 to the BG2 map at
  the lock's cell, below, right, below-right; RoomDraw_BigKeyLock
  (0x0807D7F0, literal 0x0807D880) draws the same at load when the bit is
  set. dung_floor_2_filler_tiles (+0xB12) = (the room object list's first
  byte & 0x0F) << 4 (0x0807FEE0). Ported: the 16 filler sets and every
  room's nibble; Interior:openChest (live and at load) draws them for a
  lock.
- [x] 66.2 **The maiden's "don't go this way" on a checkpoint load.** It
  was message 0x127 of kTagalong_IndoorInfos' room 0xDB entry: the
  checkpoint loader runs two frames in the entrance room (0xDB, the
  trigger at the door) before it moves Link -- a harness artefact (ck25.lua
  now holds the follower for those frames). The port's own part: the
  trigger flags lived on the trail, which restarts in every room, so
  walking back into 0xDB / 0xAB replayed the message. tagalong_event_flags
  are RAM cleared only going in or out of doors (as OldMan.lua): Ending27
  keeps them on the game (game.maidenFlags, cleared on a state change).
- [x] 66.3 **The crystal scene's second Link** (Ending27's drawRoom wrap):
  the lit Link, the maiden and the crystal outline were drawn with the
  room camera, the room with the view's origin (Zoom.lua: the real app's
  field can be wider than 240 x 160), so the darkened real Link and a lit
  copy ~30 x 21 px off showed. Now both use G:viewOrigin and the darkness
  covers viewW x viewH.
- [x] 66.4 **Port: Blind's picture 21** (new `Blind66.lua`, no ROM reads).
  Blind_SpawnFromMaiden starts Blind with graphics 21; Blind_Draw draws
  pictures >= 15 from kBlindPoof_Dmd (0x17B1AC): 21 is two 16x16 entries,
  chars 0x40 / 0x42 on OBJ page 0 (flags 0x0B xor Blind's 1). Those are
  the follower slot: Tagalong_Draw (0x0811571C) puts every follower's head
  at char 0x40 (0x081159CE: (flags << 8) | 0x40) and its body at 0x42,
  DMA'd from the follower sheet (kTagalongDmaAndFlags dma6 / dma7). The
  slot keeps the maiden's last frame, so Blind shows her; the port drew
  Blind's sheet chars (broken). Ported: the slot's frame is kept each
  frame (Ending27.followerFrame wrapped; Smiths.drawFollower records what
  it drew), picture 21's entries draw follower 6's tiles with the entries'
  flags.
- [x] 66.5 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain66.sh` (P=c): 01 `MENU23 M`: the Magic Mirror from area 0x58 to
  the Light World (`ck_r66_cmir`, Kakariko 0x18, 512, 1999) -> 02
  `WK2904,3232`: to Lake Hylia's north-west shore (`cl1shore`, area 0x35)
  -> 03 swum south and east round the west islet (`cs2isl`, 3096, 3542) ->
  04 to the middle island's south steps (`cs3isl`, 3264, 3608) -> 05 up
  the steps, the heavy rock (attribute 0x53 at 3248, 3552; map16 0x239)
  lifted with the Titan's Mitt (R), thrown, the warp tile (0x4B) -> the
  Dark World's ice lake, area 0x75 (`cs5dw`, 3247, 3546) -> 06 the palace
  door -> **room 0x0E, entrance 45, keyPalace 18** (`cipin`). Health floor
  absorbed per leg: 0, 0, 0, 0, 0, 0 = **0** (r65: 730); no hits. Health
  80 / 80 throughout (Blind's heart container had refilled it); magic 12.
- [ ] 66.6 **Stopped: magic.** Room 0x0E has tag 8 (the south half's
  enemies open its shutters): the Freezor 0xA1 (352, 296) only dies to
  fire (Enemies27B.fireHit); the Fire Rod costs kLinkItem_MagicCosts[0] =
  16, Link has 12 ("short on magic power"). The key door (120, 296) and
  the stairs down are behind that shutter. Magic sources checked: outdoor
  secrets give no jars (type 4 = rupee / fairy / heart / nothing); pots
  hiding magic (0x0C small, 0x0D full) are in dungeon rooms only (e.g.
  Skull Woods 0x56: six, 0x57: a full jar at 368, 112; Thieves' Town 0x45,
  0x64); a few octoroks by the lake dropped rupees. The bottle merchant
  and the potion shop's bottle wares are not ported (Shop.lua: "needs an
  empty bottle (none ported)").
- [ ] Traced, not ported: **the Ice Palace's slippery floors.** The indoor
  TileDetect handlers (table 0x0816832C): 0x0E -> 0x080A076C
  (tiledetect_icy_floor +0x17D8 |= the probe's bit), 0x0F -> 0x080A078C
  (bit << 4), 0x0C -> 0x080A074C (+0x17AC). 0x0809EEB4 (tail at
  0x0809F2C0) turns (+0x17D8 & 0x11) into link_flag_moving (+0x17DA = 1
  / 2, speeds 0x180 at +0x17CA, then 0x0809E2CC); +0x17DA is read by
  0x08092E50, 0x0809380C, 0x08096F30, 0x08097024, 0x080975B4, 0x08097A74.
  Ice rooms (both tables): 0x0F in 0x0E, 0x1F, 0x2E, 0x4F, 0x6E, 0x9F,
  0xAF, 0xBF; 0x0E in 0x5E, 0x7E; 0x0C in 0x3E.
- [ ] Not done (goal 4): the 0x21 push switch's sheet, indoor splash /
  swim sounds, the PoD door's map steps / sounds.

Real app (cache v60 after `real/reimport.sh`, full-window shots):
`RUNID=real66a realp.sh r65_cttacin "..."`: Blind's picture 21 is the
maiden (`real/shots/real66a_p06_AC_win.png`), the crystal scene with one
Link (`real66a_p21_AC_win.png`; that demo re-ran Blind: floor 80);
`RUNID=real66b realp.sh r65_ctt45maid "N10 P ..."`: loaded on the maiden's
spot, no message, the cell locks drawn open (`real66b_p02_45_win.png`,
`real66b_p05_45_win.png`); `RUNID=real66c` (LEGS=pod49.lua:X,ow52.lua)
from `ck_r66_cs3isl`: the heavy rock lifted (`real66c_lift_win.png`), the
warp, the Ice Palace's room 0x0E (`real66c_p02_0E_win.png`; entrance 45,
keyPalace 18).

Checkpoints (`r66/out/`): the kept chain `ck_r66_cmir`, `cl1shore`,
`cs2isl`, `cs3isl`, `cs5dw`, `cipin` (latest: the Ice Palace's room 0x0E,
entrance 45, keyPalace 18, 10 hearts full, magic 12); the piecewise first
runs `ck_r66_mir`, `l1shore`, `s2isl`, `s3isl`, `s5dw`, `ipin`.

Screenshots: `r66/shots/lock66_cells_open.png` (the cells open after a
reload, harness), `r66/shots/r66_blind_p21.png` (picture 21, before the
fix), `r66/shots/owmap_lake_crop.png` (Lake Hylia's attributes),
`r66/shots/ttmap65_ip0e_U.png` (rooms 0x0E / 0x1E), and the real-app shots
above.

Tests: new `zelda_alttp_r66_test` (the hooks and the cacheVersion;
Cells66 on stand-ins: the word order, the four cells, chests untouched,
the openChest wrap; Blind66 on stand-ins: the slot's head / body on page
0, page 1 left alone, the trail frame; Ending27: a new trail starts with
the shown flags, kept in one state, cleared out of the door; with the ROM:
the two routines' starts, data.t.cell66, picture 21's two slot entries, a
room with a big-key lock found at run time drawn with the filler when
opened and when loaded open; 28 checks). All 73 `zelda_alttp_*` files
pass (`r66/out/alltests66.txt`). Audits 304/304 rooms, 80/80 overworld
areas (`r66/out/audit_rooms66.log`, `out/audit_ow66.log`), cacheVersion
60.

## Round 67 (2026-11-17)

Magic for the Ice Palace, the cartridge's way: the bottle merchant was
ported, Link left the palace, bought a bottle in Kakariko and a green
potion at the potion shop, came back and burned the Freezor. The ice
floors were ported from round 66's trace. Route on to room 0x1E with real
input. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r67/` (the r66
kit with r67 paths; checkpoints `ck_r67_*`). New in the kit: `chain67.sh`
(the kept route, 7 legs, `P=<prefix>`, `FROM=<leg>`, all through `o.sh`),
`harness/walk67.lua` + ow52 token `WW<x>,<y>` (walk59's BFS with deep /
shallow water passable: swims), `harness/swim67.lua` (`SWIM67=`, as swim66
but "stuck" = no progress for 90 frames: strokes pause), probes
`owacts67.lua` (overworld actors), `ice67p.lua` (`ICEKEYS="left:40,none:30"`:
log the slide), `rasc67.lua` (room attributes as ASCII, `RBOX=`),
`attr67.lua`, `portal67.lua`, `ent67.lua`, `q67.lua`. gf61.lua's own wall
test now lets the ice through. **cacheVersion 61** (data.t.bottle67,
data.t.ice67): harness store re-imported (REIMPORT=1), real app re-imported
(`real/reimport.sh`, v61).

- [x] 67.1 **Choice: port the bottle merchant, buy the green potion.** The
  potion shop (Sprites31, room 0x109) and drinking (Cape.lua) were ported;
  only a bottle was missing (Shop.lua: "none ported"). Skull Woods' pots
  would have meant a Dark World trek and a refill of 16-32 at most;
  Kholdstare's shell wants 8 Fire Rod hits = 128 magic, which a green
  potion (full magic) covers. Link had 205 rupees: bottle 100 + green
  potion 60.
- [x] 67.2 **Port: Sprite_75_BottleVendor** (new `Bottle67.lua`, one line in
  ExtractA27's EXTRA list). GBA sprite routine table 0x08174138 [0x75] =
  0x080D15C0 -> main 0x080D10E4; states 0x08174A58: 0 0x080D1198 (sold flag
  +0x1662 & 2 -> "sold out" (bl 0x080D11CE), else the offer with a choice
  (bl 0x080D11EA) -> 1), 1 0x080D1220 (another choice or rupees <= the cmp
  at 0x080D125C -> "no" (0x080D123C / 0x080D1266), else thanks
  (0x080D127E) -> 2), 2 0x080D15D0 (Link_ReceiveItem(the movs at
  0x080D15E2), the flag |= the movs at 0x080D15EE, rupees - the movs at
  0x080D15F4). BottleVendor_Draw 0x080D161C: two entries a picture from
  the literal at 0x080D1640; the blink (GetRandomNumber() == 0 -> picture
  1 for the movs at 0x080D1144 frames). All values read at import. Spawned
  through Npc.spawnArea (Kakariko, phases 2 / 3), a barrier; talking is R
  against his kSpriteHitbox (Npc.lua's 16 x 16 box missed by a pixel). Not
  ported: the fish (states 3 / 4).
- [x] 67.3 **Port: the slippery ice** (new `Ice67.lua`; `Doors.lua` exports
  checkY / checkX / limitDirections in one line). TileDetect 0x0816832C:
  0x0E -> 0x080A076C, 0x0F -> 0x080A078C (+0x17D8 bits); the nearby probe
  0x0809EEB4's tail 0x0809F2C0 sets link_flag_moving (+0x17DA) = 1 (0x0E)
  / 2 (0x0F) on stepping on (the first type is kept), resets the momentum
  words (0x0809E2CC -> 0x08092B0C: +0x17B2 .. +0x17CC) on and off.
  PlayerHandler_00_Ground 0x080981D0: keys -> var9 = 0x180 (movs at
  0x080982D2), Link_SetMomentum 0x08097A74 (var3 = kSwimmingTab2[flag - 1]
  on ice, 0x20 off it), Link_SetTheMaxAccel 0x08097D70 does nothing on ice;
  Link_HandleVelocity 0x080975B4 -> 0x0809834C (HandleSwimStrokeAndSubpixels
  with kSwimmingTab4[var5 + flag * 4], 3/4 on diagonal keys +0x172A, var11
  0 negative). Then the walls as walking. And: Interior.WALKABLE held
  neither 0x0E nor 0x0F -- **the ice was a wall to Link** (the Baris'
  floor in 0x0E could not be entered). Both are floor now.
- [x] 67.4 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain67.sh` (P=c) from `ck_r66_cipin`: 01 out of the palace, the Mirror
  (area 0x75 -> 0x35, `ck_r67_cmir`) -> 02 swum to Lake Hylia's north-west
  shore (`cshore`, 2904, 3237) -> 03 Kakariko, the merchant: the bottle
  (`cbottle`, rupees 105, bottle 0x25 = 2) -> 04 across the Light World
  (swimming the river) to the potion shop (entrance 76, room 0x109), the
  green potion (`cpotion`, rupees 45, bottle = 4) -> 05 back to the lake
  island (`cisl`) -> 06 the heavy rock, the warp, the palace door (`cipin`,
  room 0x0E, entrance 45, keyPalace 18) -> 07 the green potion drunk
  (magic 12 -> 128), the Freezor burned (two shots, magic 96), the shutter
  open, the ice (slid), the three Baris swordsed, their key, the key door
  (120, 296), the stairs -> **room 0x1E** (`c1e`, entrance 45, keyPalace
  18, hp 24 / 80, magic 96). Health floor absorbed per leg: 0, 0, 0, 0, 0,
  0, 0 = **0**. Hits: the Freezor's touch (32), the Baris' shocks, a few
  outdoor foes.
- [ ] Note: a checkpoint load drops the Mirror's portal (game.portalPos is
  not in the save -- nor is it on the cartridge); the route takes the
  heavy rock again. A checkpoint inside a room reloads its enemies (the
  Freezor, the Baris), so leg 07 is one leg.
- [ ] Next: the Ice Palace from 0x1E (Pengators, the moving floor 0x0C in
  0x3E, the big key, Kholdstare: 8 Fire Rod hits = 128 magic; Link has 96,
  an empty bottle and 45 rupees -- pots with magic in 0x3E / 0x4E, enemy
  drops; health 24 / 80 needs hearts first). Not done (goal 3): the 0x21
  push switch's sheet, indoor splash / swim sounds, the PoD door's map
  steps / sounds.

Real app (cache v61 after `real/reimport.sh`, full-window shots):
`RUNID=real67a` (LEGS=pod49.lua:X,ow52.lua) from `ck_r67_t_kak`: the bottle
merchant's offer (`real/shots/real67a_bv1_win.png`), bought (`real67a_bv2_win.png`,
rupees 105, bottle 2); `RUNID=real67b` from `ck_r67_cipin`: the potion, the
Freezor, the ice room's doorway (`real67b_p13_0E_win.png`,
`real67b_p16_0E_win.png`, `real67b_p25_0E_win.png`).

Tests: new `zelda_alttp_r67_test` (the hooks and the cacheVersion; Bottle67's
talk on stand-ins: offer, thanks + receipt + price + flag, sold out, "no",
too poor; Ice67 on stand-ins: SetMomentum, the ice rows' acceleration / cap
/ deceleration, 3/4 diagonal, the turn (var5 2, var9 240), the reset, the
probe's flags; 0x0E / 0x0F walkable; with the ROM: the routines' starts,
TileDetect's two handlers, data.t.bottle67 / ice67, the merchant in
Kakariko's list, a room with ice found at run time is floor; 31 checks).
All 74 `zelda_alttp_*` files pass (`r67/out/alltests67.txt`).
Audits 304/304 rooms, 80/80 overworld areas (`r67/out/audit_rooms67.log`,
`out/audit_ow67.log`; the rooms audit takes r66's `audit/mains.txt` with its
guessed main sets), cacheVersion 61.

## Round 68 (2026-11-17)

The Ice Palace's damage checked against the cartridge, Link's armour put
into every touch, the swim / hop / fall sounds played, and the route on from
room 0x1E through the octagon's bomb floor, the Stalfos Knights and the
conveyor room's key to room 0x4E (and its heart) with real input. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r68/` (the r67 kit with r68 paths;
checkpoints `ck_r68_*`; `doc/round68.md`). New in the kit: `chain68.sh` (4
legs, `P=<prefix>`, `FROM=<leg>`; exports HURTLOG only), `harness/sk68.lua` +
pod49b token `SK<frames>` (Stalfos Knights: sword until it collapses, then a
bomb beside it; `SKNOWAKE=1`), probes `pots68` / `rooms68` / `spr68` /
`locks68` / `sw68` / `peg68`, `py/ttshow.py` (a room's attributes as ASCII).
**cacheVersion 61** (no new import data: both new modules read no ROM), so no
re-import; the harness store and the real app stay on v61.

- [x] 68.1 **Freezor / Ice Palace damage vs the cartridge.** GBA
  Sprite_AttemptDamageToLinkPlusRecoil 0x080C3BD0: blink (+0x17AA) |
  link_disable_sprite_damage (+0x180D) -> return; +0x16F8 = 0x13,
  Sprite_ApplyRecoilToLink(k, 0x18); link_give_damage (+0x1805) =
  kPlayerDamages (literal 0x080C3C78) [(sprite_bump_damage (+0xEA5) & 0x0F) *
  3 + link_armor (literal 0x080C3C7C -> 0x0200233F)]. The Freezor's bump class
  (read at import) gives 32 with the green mail: **32 is the cartridge's**
  (Pengator, Stalfos Knight, Babasu 16; red Bari 8; blue Bari 4 -- all from
  the ROM's tables). The difference found: every port contact site read
  `playerDamage[3 * class + 1]`, the green column only, so the Blue Mail (the
  Ice Palace's big chest) and the Red Mail would not have lowered a touch.
  **Port: Damage68.lua** (one line in ExtractA27's EXTRA list): the combat
  table's kPlayerDamages gets a proxy, index i reads raw[i + armour] (armour =
  inventory byte 0x3F, Gear.armor; 0..2), attached per game in Game:update.
- [x] 68.2 **Port: Sfx68.lua** (one line in ExtractA27): Sfx.lua imported the
  ids of the swim stroke (0x0809B62E), ledge hop (0x080946DC) and pit fall
  (0x0809AC3E) but nothing played them, indoors or out. Played now from the
  port's counters (game.swimStrokes -- Swim.lua's stroke start, also Swim54's
  indoor swim --, game.ledgeHops / hops50, game.pitFalls). Not wired: the
  landing (0x0809969A) and the splash into water (no site found yet).
- [x] 68.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain68.sh` (P=c) from `ck_r67_c1e`:
  01 room 0x1E: the left switch (tag 0x17 toggles the 0x18 shutters; a
  quadrant crossing shuts them again, Shutters44), the middle room's ice
  block pushed east, south to 0x2E and back north (the room reloads: the
  block pushed north from below), the middle switch, east into 0x1F (six
  Pengators swordsed, the pot switch at 112,400 lifted and stepped on), back
  west into 0x1E's east arm (its switch opens all three shutters), the block
  pushed west, north to the octagon: the crystal switch (blue pegs down),
  up the east edge, **a bomb laid at the pipe's top edge toggles the switch
  below it** (orange pegs down), a bomb on the cracked floor, the hole ->
  **room 0x3E** (`c3e`, entrance 45, keyPalace 18; hp 16 / 80).
  02 0x3E: the heart pot (352,160), the bomb pot, both Stalfos Knights (one
  bomb each while collapsed), the shutter, south onto the moving floor
  (`cb3e`). 03 the blue Baris (the one with the key), the key door at
  (120,472) -> **room 0x4E** (`c4e`, 120,55). 04 the pot at (48,120), the
  heart pot (112,192) -> `c4eh` (hp 24 / 80, magic 120, bombs 4, keys 0,
  entrance 45, keyPalace 18). Health floor absorbed per leg: **96, 16, 296,
  24 = 432** (Pengators and Babasus 16 a touch, the Baris' shocks, the
  firebar; the harness's sword fights take many hits). Hearts found: 0x3E's
  and 0x4E's heart pots (+8 each); no heart drops.
- [ ] Notes: 0x1E's big-key room 0x1F: the chest (360,432) sits behind two
  skull pots (344,416 / 344,432) reached only from the top-right area, whose
  stairs come from 0x3F (stairs 2667) -- the big key waits for 0x3F. The
  0x1F anti-fairy (0x15) drains magic: keep that visit short. A checkpoint in
  0x3E respawns the Stalfos Knights in the top half (harmless below).
  Entering 0x4E from the north: hold down only through the door -- the floor
  under the door is one strip (cols 13-14), the rest is pit.
- [ ] Next: 0x4E on (pits, the pot switch 48,184, the stairs to 0x6E, the
  fairy room 0x4F behind a key door: three fairies), the keys (0x5F chest,
  0xAE chest, 0x9F pot), 0x5E -> 0x7E -> 0x9E (big chest: Blue Mail -- the
  armour column now counts), the big key via 0x3F / 0x1F, Kholdstare (0xCE's
  hole -> 0xDE; full-magic pots in 0xBE). Goal 4 leftovers: the 0x21 push
  switch's sheet, the splash sound, the PoD door's map steps / sounds.

Real app (cache v61, full-window shots): `RUNID=real68a` from `ck_r68_c3e`:
a Stalfos Knight blown up while collapsed (`real/shots/real68a_p12_3E_win.png`);
`RUNID=real68b` from `ck_r67_c1e`: the octagon after the bomb floor broke
(`real68b_p49_1E_win.png`), Link landed in 0x3E's pot ring
(`real68b_p53_3E_win.png`).

Tests: new `zelda_alttp_r68_test` (the hooks; Damage68 on stand-ins: green /
blue / red columns, clamp, one proxy per table following the game,
Game:update attaches it; Sfx68: the counters' events, Game:update plays
them, Sfx.SITES names them; with the ROM: the routine's start, its
kPlayerDamages literal = the imported table, the armour byte 0x3F, the
class * 3 + armour shape, each class green >= blue >= red, the game's blue
mail reads the second column; 28 checks). All 75 `zelda_alttp_*` files pass
(`r68/out/alltests68.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r68/out/audit_rooms68.log`, `out/audit_ow68.log`; r66's `audit/mains.txt`),
cacheVersion 61.

## Round 69 (2026-11-17)

A better fighting bot (the health floor absorbed 92 over round 68's four
legs instead of 432), and the Ice Palace on from room 0x4E with real input:
0x4E's pot switch and pits, the stairs to 0x6E, the Pengator line, 0x5E's
crumbling floor down to 0x7E, its pots and switch, the hole to 0x9E, the
Freezor, and 0x9F's key pot and hearts. The ledge hop's landing sound. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r69/` (the r68 kit with r69 paths;
checkpoints `ck_r69_*`; `doc/round69.md`). New in the kit: `chain69.sh` (legs
01-11, `P=<prefix>`, `FROM` / `TOLEG`; kept set P=b, `out/chain69_b.txt`),
`harness/gf69.lua` (the fighter + DODGE / FBGUARD guards, HURTDUMP,
ASSISTMAX), probes `gfstat69` / `hexa69` / `multi69` / `dn69` /
`h[udlr]room69` / `lkdump69`, `peng69.sh`. **cacheVersion 61** (Sfx69 reads
no ROM), so no re-import; the harness store and the real app stay on v61.

- [x] 69.1 **The bot fights better** (harness only, real input; `gf69.lua`,
  loaded first in LEGS). GF61 replaced: an electrified Bari (ai 1 -- the
  cartridge's Sprite_AttemptZapDamage zaps a sword hit) is never swung at
  and Link keeps >= 30 px from it; a Bari is swung at only while aux1 > 8
  (its charge roll comes when aux1 runs out); hit and run; foes coming along
  an axis are met with the sword, others dodged (predicted from their last
  frame's motion). DODGE=1: a per-frame guard on H.run while walking (an
  imminent touch -> sidestep / swing; never press into a spike block 0x44 on
  the cartridge's y & 4 test (Mech27.spikeTiles); a guard that only holds Link
  lets him through after 20 frames). FBGUARD=1: the firebars timed (each
  ball's place k frames on from Hera.barSin / barOff and the bar's observed
  step, against Link going on / waiting / stepping back). Found on the way:
  round 68's "Bari" damage in 0x3E's south half was mostly the spike blocks
  on the moving floor (Link + 8, + 12 sources, 8 each) and the Babasus.
  Round 68's legs replayed (P=b): **48, 16, 28, 0 = 92** (was 96, 16, 296, 24
  = 432; DODGE=0: 24, 8, 88, 8 = 128).
- [x] 69.2 **Heal / fairy room.** 0x4E: the pot switch (48,184; Link at
  48,172 so D.pressedSwitch's probe finds the top row) opens the 0x18
  shutter (tag 0x17); the heart pot; the pot at (192,160) lifted to pass.
  Hearts found this round: 0x4E, 0x5E (left), 0x7E, 0x9F x2 (+8 each); magic
  pots 0x5E (368,64), 0x7E (328,416). **The fairy room 0x4F was not
  reached**: its only door is the west key door at (16,376), whose other side
  (0x4E's bottom-right quadrant) is solid in the port's attributes, and 0x4E
  lists no east door; 0x4F's top-right (the three 0xE3 fairies) has no door
  (header hole 0xBE). **Bottle catching** is ported already (round 27,
  Items27 LinkItem_Net: the net's box catches Sprite_E3_Fairy -> the first
  empty bottle = 6); the cartridge catches with the Bug-Catching Net only,
  and Link has no net (slot 16 / 0x2F empty), so nothing to port.
- [x] 69.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain69.sh` (P=b) from `ck_r68_c4eh`'s route replayed (`ck_r69_b4eh`):
  05 0x4E: the switch pot, the heart pot, the pot at (192,160), the open
  shutter, past the Zols, the stairs -> **0x6E** (`b6e`); 06 the five
  Pengators (all swordsed), north -> **0x5E** (`b5e`); 07 the left heart pot,
  a magic pot, the crumbling floor at (432,72) -> **0x7E** (`b7e`); 08 the
  Pengators, the heart pot (344,240), the magic pot (328,416), the switch
  pot lifted (`b7e2`); 09 the pot switch (400,404: the shutter at 280,384
  opens), west, the hole (184,384) -> **0x9E** (`b9e`); 10 the Freezor burned
  (Fire Rod, three shots, magic 96 -> 48), around the block -> **0x9F**
  (`b9f`); 11 the key pot (40,344; the key picked at 42,336), two heart pots
  -> `b9fk` (room 0x9F, entrance 45, keyPalace 18, keys 1, hp 32 / 80, magic
  40, bombs 3; verified on load). Health floor absorbed per leg: **48, 16,
  28, 0, 16, 24, 24, 48, 32, 0, 0 = 236** (one pit fall in leg 05).
- [x] 69.4 **Port: Sfx69.lua** (one line in ExtractA27's EXTRA list): the
  ledge hop's land sound (Sfx.SITES land 0x0809969A) when any hop ends,
  indoors or out, and the jump sound (0x080946DC) when an outdoor hop
  starts; Sfx68's `ledgeHops` entry was dropped (Game.lua steps that counter
  when an indoor hop ENDS, so it played "jump" at the landing). Not done: the
  splash into water (no GBA site found), the 0x21 push switch's sheet, the PoD
  door's map steps / sounds.
- [ ] Notes: 0x5E's floor crumbles behind Link along the ring (the second
  heart pot (448,128) is lost once it goes); the anti-fairy in 0x9F drains
  magic on touch (magic 96 -> 40 there). 0x7E's chest (112,384, item 0x28)
  sits by two Freezors: skipped. A checkpoint in a room reloads its enemies
  (0x7E's Pengators come back at `b7e2`).
- [ ] Next: from `ck_r69_b9fk` with the key: 0x9E north -> 0x8E -> the key
  door to 0x7E -> the stairs to 0x5E -> the key door east -> 0x5F (chest key)
  -> stairs 0x3F -> 0x1F (big key) -> back to 0x9E's big chest (Blue Mail);
  then 0x9E's pits -> 0xBE (full-magic pots 0x0D), 0xCE's hole -> 0xDE
  (Kholdstare: magic 40 now; the anti-fairies drain it). 0xAE's chest key.

Real app (cache v61, full-window shots): `RUNID=real69a` from `ck_r69_b4eh`
(leg 05 replayed, same frames): Link on 0x4E's pot switch by the firebar
(`real/shots/real69a_p07_4E_win.png`), 0x6E's Pengator line on arrival
(`real69a_p32_6E_win.png`); `RUNID=real69b` from `ck_r69_b5e`: 0x5E's
crumbling floor (`real69b_p25_5E_win.png`), dropping into 0x7E
(`real69b_p27_7E_win.png`).

Tests: new `zelda_alttp_r69_test` (the hook and the cacheVersion; Sfx69's
events on stand-ins: outdoor start jump, indoor start nothing, any end land;
Sfx68's ledgeHops dropped, hops50 -> jump kept, patching twice; Game:update
plays them; with the ROM: both sites are movs #imm, the import's two ids are
the sites' immediates and differ, a game runs Sfx68 without ledgeHops; 22
checks). All 76 `zelda_alttp_*` files pass (`r69/out/alltests69.txt`). Audits
304/304 rooms, 80/80 overworld areas (`r69/out/audit_rooms69.log`,
`out/audit_ow69.log`; r66's `audit/mains.txt`), cacheVersion 61.

## Round 70 (2026-11-17)

The fairy room 0x4F's way in, the hidden chests (a port fix), and the Ice
Palace with real input from room 0x9F round to the big key and back down to
the big chest room 0x9E. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r70/`
(the r69 kit with r70 paths; checkpoints `ck_r70_*`; `doc/round70.md`). New in
the kit: `chain70.sh` (legs 01-12, `P=<prefix>`, `FROM` / `TOLEG`; kept set
P=b, `out/chain70_b.txt`), `harness/tok70.lua` (pod49b asks `_G.TOK70` first:
`IC<x>,<y>[,tol][yx]` an ice-aware walk -- one axis at a time, released when
the measured slide (Ice67's v7 / v3; 0x0E +4/-6, 0x0F +10/-16 a frame) covers
the rest; `FBA<lo>,<hi>` wait for a firebar angle; `SWT<x>,<y>,<backy>` a
toggle switch until the shutters are open; `SHOOT<dir><n>` the selected
item), `d.sh` (one try with the chain's env), probes `walkdbg70`, `slide70`
/ `slide70b`, `icdbg70`, `fbspeed70`, `chestst70`, `drops70`, `fdmg70`,
`py/doors70.py` (door lists, layer door words, stair objects from the ROM),
`py/av.py` (attribute maps as ASCII). **cacheVersion 61** (Chest70 reads no
ROM), so no re-import; the harness store and the real app stay on v61.

- [x] 70.1 **The fairy room 0x4F (checked against the cartridge).** Its west
  key door (16,376) sits in a quadrant (the T room with six pots) that no
  room reaches: 0x4E's lower half is solid and has no east door in the
  cartridge's own data too (0x4E's door list: W pos6 shutter 0x18, N pos0
  key door; the 3 layers' door words are empty). The way in is a fall:
  room 0xBE's header hole target (byte 9) is 0x4F, and 0xBE's top quadrant
  has two 2x2 pits (attribute 0x20, under its two urns); 0x4F's hole target
  is 0xBE and its pool holds the warp tile (attribute 0x4B, 2x2, 368,160)
  back (Warp48, round 48); the dungeon map draws 0x4F as 0xBE
  (kDungMap_Tab21 / 22, DungeonMap.lua). The port already does all this:
  nothing to fix (the round-70 test checks the relation from the ROM).
- [x] 70.2 **Port: the hidden chests (new `Chest70.lua`, one line in
  ExtractA27's EXTRA list).** The GBA's Dungeon_LoadAttribute chest part
  (0x08082500..0x08082548) skips every chest attribute when either header
  tag is 0x27, 0x3C, 0x3E or 0x29..0x32 (`cmp #0x27 / #0x3C / #0x3E`,
  `(tag - 0x29) <= 9`); the pre-rendered maps hold no chest picture there.
  RoomTag_OperateChestReveal (0x0807A478) writes the closed chest's four
  words (the chest tile table, Extract's `items.chestClosed`) and the
  0x5858 attribute pair. Tag 0x27 (0x0807B71C: not blinking + a switch) ->
  the reveal; tags 0x29..0x2E share tags 1..6's routines (kDungTagroutines
  0x152AC4) and RoomTag_QuadrantTrigger (0x0807B43C) reveals for tag > 0x28
  when the screen is clear (0x080CAEC0); 0x0807D3E4 clears a revealed
  room's tag at load. The port marked every chest at load, and
  `Palace.roomTags` called an `inside:revealChests()` that did not exist:
  a hidden chest could be opened or hookshot before it was there. Now
  Interior:markChests hides them (attributes and grid back to what was
  under them), `I:revealChests` draws / marks them, and tags 0x29..0x32 run
  tags 1..10's kill rule (Palace.roomTags wrap). Found because round 70's
  first route hooked across 0x7E's pit onto the invisible Freezor chest.
- [x] 70.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain70.sh` P=b from `ck_r69_b9fk`: 01 0x9F: the four Babasus swordsed,
  the pot (160,336) lifted, its switch (tag 0x17) opens both shutters,
  west round the firebar, the south shutter -> **0xAF** (`baf`); 02 the
  ice path between the pits past the firebar (started at bar angle
  0xF8..0x108) -> **0xAE** (`bae`); 03 the Baris, the pot (304,192) lifted,
  its switch reveals the chest (key; keys 2), the stairs up -> **0x8E**
  (`b8e`); 04 round the pipe, the key door (keys 1) -> **0x7E** (`b7e`); 05
  0x7E: the magic pot (328,416; magic 24 -> 40), the switch pot (400,416)
  opens the shutter (280,384), west into the pit corridor, one Fire Rod
  shot melts both Freezors (they had walked into one spot), tag 0x2B
  reveals the chest, the hookshot onto it across the pit, the chest (three
  bombs), the stairs up -> **0x5E** (`b5e`); 07 the ice room past the
  firebar, the east key door (keys 0) -> **0x5F** (`b5f`); 08 the hookshot
  onto the switch pot across the spikes, the pot lifted, the switch (tag
  0x27) reveals the chest, the hookshot back onto it, the chest (key), the
  spikes, the stairs up -> **0x3F** (`b3f`); 09 two quarters of the centre
  block lifted, the pull switch (tag 0x14) opens the shutter, the floor
  stairs (352,328) -> **0x1F** (`b1f`); 10 two pots lifted, **the big key**
  (360,432), the stairs down -> 0x3F (`b3fb`); 11 the other pull switch,
  the stairs down to 0x5F, the spikes, the open key door -> **0x5E**
  (`b5eb`); 12 the ice room past the firebar, the stairs down to 0x7E's
  pit corner, the pit -> **0x9E** (`b9e`: room 0x9E, entrance 45, keyPalace
  18, keys 1, big key, hp 16 / 80, magic 24, bombs 6; verified on load).
  Health floor absorbed per leg: **56, 0, 0, 0, 40, 16, 56, 18, 0, 12, 16 =
  214** (Babasus 16 a touch in 0x9F, the spikes in 0x5F).
- [ ] **Not reached: the big chest (0x9E, 48,320).** 0x9E's lower-left
  quadrant: the chest is west of two pillar columns (attribute 0x27, x
  96-111 and 128-143); the only gap in the west column is rows 47-48, where
  the middle push block (0x75, 112,376) sits; the top / bottom blocks
  (0x74 144,312, 0x76 144,456) close the middle column's ends. Pushed from
  the east the middle block moves one tile into the gap and becomes a fixed
  block (RoomObjects.lua: a pushed block is redrawn fixed, 0x27). With one push per block nothing
  opens the west part from the east, so either the cartridge's push rule
  differs here (to check: the GBA's push-block handler and how the pushed
  block's tile is written) or the way in is elsewhere. Blue Mail, 0xBE
  (full-magic pots, the 0x4F pits), 0xCE and Kholdstare wait on it.
- [ ] Notes: a checkpoint inside 0x7E's lower-left quadrant reloads the
  Freezors (asleep in the wall), so leg 05 runs from 0x7E's door to 0x5E in
  one go. Freezors wake on the low byte of Link's x (Sprite_A1: (dx + 16) &
  0xFF < 32): Link at x 351-383 in the right half wakes the left half's.
  The real-app checkpoint loader leaves magic at 0 (harness only; the
  harness store's checkpoints keep it).

Real app (cache v61, full-window shots): `RUNID=real70b` from `ck_r70_bae`
(leg 03): the switch pot lifted, no chest yet
(`real/shots/real70b_p07_AE_win.png`); on the switch, the chest drawn
(`real70b_p10_AE_win.png`); the chest opened (`real70b_p13_AE_win.png`).

Tests: new `zelda_alttp_r70_test` (the hook; the hiding tags; hide / reveal
/ kept-revealed / opened / other tag on a stand-in room; tag 0x2B's kill
rule; with the ROM: both `cmp #0x27` sites, tags 0x29..0x2E share tags
1..6's routines, every hidden-chest room hides and reveals, an untagged
room keeps its chest, the pit room falling into 0x4F and 0x4F's warp tile
back; 43 checks). All 77 `zelda_alttp_*` files pass (`r70/out/alltests70.txt`).
Audits 304/304 rooms, 80/80 overworld areas (`r70/out/audit_rooms70.log`,
`out/audit_ow70.log`; r66's `audit/mains.txt`), cacheVersion 61.

## Round 71 (2026-11-17)

The Ice Palace finished with real input: 0x9E's big chest (Blue Mail), the
crystal switch in 0xBF, the fairy room 0x4F, the block holes of 0x9E and 0xCE,
Kholdstare, the heart container and crystal 5. Port fixes: the hammer pegs
indoors, the hammer breaking pots, the big block lifted whole with what it
hides. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r71/` (the r70 kit
with r71 paths; checkpoints `ck_r71_*`; `doc/round71.md`). New in the kit:
`chain71.sh` (legs 09-26, `P=<prefix>`, `FROM` / `TOLEG`; kept set P=b,
`out/chain71_b.txt`), probes `man71`, `attr71`, `blk71`, `dmg71`, `fz71`,
`fairy71`, `pullu71`, `txtall71`, `cr71`, `py/ice71.py` / `spr71.py` /
`keys71.py`; gf69's guard no longer dodges keys (0xE4) and crystal switches.
**cacheVersion 62** (Manip71 reads the ROM): harness store re-imported
(REIMPORT=1) and the real app re-imported (`real/reimport.sh`).

- [x] 71.1 **0x9E's big chest: the push rule is the cartridge's; the way in
  is 0x7E's bomb floor.** The push blocks behave as on the GBA (one push,
  any direction, the block becomes fixed). The chest quarter is reached from
  above: 0x7E's lower-left holds a bomb floor (subtype-3 0x47 at 48,368;
  attribute 0x62 at 56..71, 376..391) and 0x7E's header hole target (byte 9)
  is 0x9E; a bomb there opens the floor and Link falls next to the chest.
  Inside, the middle block is pushed east into the middle column's gap and
  the top block east, which opens the way out. Blue Mail checked in game:
  the armour byte 0x3F = 1 and Damage68's column 1 (a Freezor touch 32 ->
  16 in the HURT log).
- [x] 71.2 **Port: Manip71.lua (one line in ExtractA27's EXTRA list).**
  RoomDraw_HammerPegSingle (subtype-3 0x16, 0x0807CF78): state 0x4040, four
  replacement words (literals of 0x0807D004 / 0E / 18 / 22). Dungeon_
  LoadAttribute (0x08082360..CC) gives every manipulable slot but a bomb
  floor attribute 0x70 + k: the port never marked the pegs, Link walked
  through them (0x3F's key block, 0xBE / 0xCE). Dungeon_ToolAndTileInteraction
  (0x08081928), the hammer's first step: a peg (0x4040) gets its replacement
  words and the LR word's tile attribute (0x08083AE4 / 0x08083974) and the
  sound of the movs at 0x080819D0; a pot (0x1010) is broken (RevealPotItem
  0x080928F0, the secret 0x080C34C4, debris 0x08116C98). The big block
  (0x2020): the lift (0x08081740 -> 0x080815E4) runs RevealPotItem on the
  FIRST segment and replaces all four segments: the block comes off whole.
  The port took one quarter a lift and revealed nothing, so 0x3F's key and
  the holes under 0x9E's / 0xCE's blocks never came out. RevealPotItem's
  hole case (secret >= 0x80, not 0x88; 0x08092A34): the four segments'
  words from the table its literal 0x08092AFC points to, sound movs
  0x08092A6A. All read at import (data.t.manip71: peg words / states /
  sounds, the hole words, the pegs per room).
- [x] 71.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain71.sh` P=b from `ck_r70_b3f`: 09 0x3F: the right pegs hammered, the
  block lifted whole -> the key (keys 2), the left pegs, the pull switch ->
  0x1F (`b1f`); 10 the big key again (`b3fb`); 11 down to 0x5E (`b5eb`); 12
  the stairs to 0x7E, a bomb on the bomb floor -> **0x9E** (`b9e`, keys 2);
  13 **Blue Mail**, the middle and top blocks pushed east (`b9ex`); 14 the
  big key door, the key door, the stairs -> **0xBE** (`bbe`); 15 the east
  key door -> **0xBF**, its crystal switch (pegs state 1), back and up the
  stairs -> 0x9E's top right (`b9eu`); 16 0x9E's left pit (its raised pegs
  now down) -> 0xBE's urn pit -> **0x4F**, two fairies (hp 16 -> 80), the
  warp tile -> 0xBE (`bbew`); 17 -> 0x9E, the east door -> 0x9F (`b9f`;
  with pegs state 1 the bottom right's two parts are apart: the block is
  reached from 0x9E's west part); 18-21 round 70's legs 01-04 again (0x9F ->
  0xAF -> 0xAE -> 0x8E -> 0x7E); 22 0x7E's pit -> 0x9E's west part
  (`b9e2`); 23 the Freezor burned (Fire Rod), the big block lifted whole:
  the hole -> **0xBE's U** (`bbeu`); 24 the full-magic pot (magic 0 -> 128),
  the south door -> **0xCE** (`bce`); 25 the two pots, the statue pulled up
  (R + up), round it, the peg hammered, the big block lifted: the hole ->
  **0xDE** (`bde`); 26 **Kholdstare**: the Fire Rod on the shell (8 shots,
  magic 128 -> 0), the three Kholdstares swordsed, the heart container (hp
  88 / 88), **crystal 5** (crystals 114 -> 118), the maiden, out on the
  overworld (area 0x75; `bdone`). Entrance 45 / keyPalace 18 verified on
  every load. Health floor absorbed per leg: **16, 0, 12, 16, 0, 16, 0, 8,
  0, 52, 0, 0, 0, 40, 0, 0, 0, 312 = 472** (312 in Kholdstare's room: Link
  came in at 16 hp; 0x9E's Baris took 44 real hp in leg 17).
- [x] 71.4 **The real-app checkpoint loader and magic: no bug.** The
  checkpoints from round 70 on hold magic 0 because Link had none (0x9F's
  anti-fairy drained it in round 70's leg 01); the real app loads
  `ck_r71_bce` with magic 128 (`real/out/real_r38ck.log`).
- [ ] Not done: the splash sound, the 0x21 push switch's sheet, the PoD
  door's map steps / sounds (round 69's list).
- [ ] Notes: 0x9E's pegs decide the way: state 0 joins the bottom right's
  two parts (the big key door side), state 1 frees the big block (its hole
  to 0xBE) and the top right's pits. The lifted block is carried as the
  touched quarter's picture. In the real app the Kholdstare leg was run to
  the last Kholdstare (the heart and crystal fall where the harness picked
  them).

Real app (cache v62, full-window shots): `RUNID=real71d` from `ck_r70_b3f`:
the right pegs driven in (`real/shots/real71d_p14_3F_win.png`), the block
lifted, the key out (`real71d_p21_3F_win.png`); `real71a` from
`ck_r71_b9e2`: 0x9E's block lifted, the hole (`real71a_p15_9E_win.png`);
`real71b` from `ck_r71_bde`: the Fire Rod on Kholdstare's shell
(`real71b_p04_DE_win.png`), the three Kholdstares (`real71b_p10_DE_win.png`).

Tests: new `zelda_alttp_r71_test` (the hook; cacheVersion; pegs marked with a
free number, driven in once with the replacement words and the LR word's
attribute; a big block's four segments; the hole words / attribute; a key
once; with the ROM: the import, every peg room marks its pegs, the rooms
whose block hides 0x80 open a pit; 25 checks). All 78 `zelda_alttp_*` files
pass (`r71/out/alltests71.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r71/out/audit_rooms71.log`, `out/audit_ow71.log`; r66's `audit/mains.txt`),
cacheVersion 62.

## Round 72 (2026-11-17)

The way to Misery Mire with real input: off the Ice Palace island, the stump
kid's shovel, the grove's flute, the weathervane, a green potion, Ether from
the Tower of Hera tablet, the Desert's heavy-rock portal, the Mire's area in
the rain, Ether at the entrance, in (room 0x98). Port: the Mire's rain and the
thunder (Rain72), the lifted big gray block carried whole (Block72). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r72/` (the r71 kit with r72 paths;
checkpoints `ck_r72_*`; `doc/round72.md`). New in the kit: `chain72.sh` (legs
01-16, `P=<prefix>`, `FROM` / `TOLEG`; kept set P=b, `out/chain72_b*.txt`),
probes `owinfo72`, `shore72`, `reach72`, `near72`, `hex72`, `cut72`, `lk72`,
`hold72`, `dig72`, `fly72` (the flute menu), `farm72` (bushes for drops),
`bot72`, `ent72`, `hurt72`, `reach48`, `rain72p`. **cacheVersion 63**
(Rain72 reads the ROM): harness store re-imported (REIMPORT=1), real app
re-imported (`real/reimport.sh`).

- [x] 72.1 **Port: the Mire's rain and the thunder (new `Rain72.lua`, one
  line in ExtractA27's EXTRA list).** OverworldOverlay_HandleRain
  (0x0807407C): no rain when overworld_screen_index (+0x9C6) != 0x70 (`cmp
  r1, #0x70` at 0x08074088) and sram_progress_indicator (+0x165E) > 1, or
  when save_ow_event_info[0x70] (0x020022F0) & 0x20 (Ether opened the Mire):
  the Dark World's area 0x70 rains until Ether, whatever the story. Frame
  counter == 3 (0x080740AA): the thunder (sound player 0x0812A324, the id of
  the movs at 0x080740B2) and the flash; == 0x5C (0x080740D4): the flash;
  the flash sets +0x998 / +0x999 to the movs at 0x080740DC and falls by one
  on odd frames down to the `cmp #0x0A` at 0x080740FE. The port rained only
  in the escape (Escape.lua, round 7) with a one-frame flash at 3 / 36 / 88
  and no thunder: G:raining now also covers 0x70 until the event bit (and
  stops the escape rain once the bit is set, as the GBA's shared test), the
  overworld frame plays the thunder on frame 3, the draw adds the
  cartridge's falling flash. Area, frames, sound id and levels read at
  import (data.t.rain72). OURS: the flash is an additive pass of the rain
  picture with alpha (v - floor) / (peak - floor) (the GBA's blend
  registers for it are not read).
- [x] 72.2 **Port: the lifted big gray block whole (new `Block72.lua`, no
  ROM reads).** Round 71 made the lift take all four segments; Link still
  carried / threw the touched 16 x 16 quarter. Lift52.remove is wrapped to
  draw the four segments' room words (before they are replaced) into one 32
  x 32 picture; G:startLift / drawCarried / drawThrown carry it centred like
  BigRock.lua's outdoor rocks. Checked in the real app (0x9E's block).
- [x] 72.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain72.sh` P=b from `ck_r71_bdone` (0x75): 01 the mirror -> the Light
  World island (`bmir`); 02 down past the heavy rock, off the island's south
  path, swim west (`blake`); 03 WW to the north-west shore water (`bnw`);
  04 up the stairs at x 2906 (`bnshore`); 05 to 0x33: the three pegs
  hammered from below, onto the warp -> **DW 0x73** (`bdw73`); 06 the DW
  pegs from the left, west to 0x72 (`bw72`); 07 the bushes cut with the
  sword, north into 0x6A, the stump kid (R): **the shovel** (`bshovel`); 08
  to the dig spot's twin in 0x6A, the mirror -> the grove 0x2A, the shovel
  at map16 0x492: **the flute** (2) (`bflute`); 09 Kakariko, into the
  weathervane's square, the flute: the vane blows up, **flute 3** (`bvane`);
  10 Kakariko's bushes cut (farm72) for rupees 47 -> 62 (`bfarm`); 11 the
  flute to spot 2, the potion shop 0x109: **the green potion** (60), drunk:
  magic 0 -> 128 (`bgreen`); 12 the flute to Death Mountain, up the paths
  to the warp tile -> 0x43 (`bdw43`); 13 the mirror -> Spectacle Rock's
  top, Hera's door in and out, west over the bridge, the tablet with the
  Book: **Ether** (`bether`); 14 the flute to the Desert (spot 6), the heavy
  rock lifted: the portal -> **0x70** (`bmire0`); 15 north in the rain to
  the entrance trigger (owfight25's sword reach 44: the Raven that dives
  from behind is cut down) (`bmire1`); 16 **Ether**: the rain stops, the
  entrance opens (event 0x70 = 0x20), in: **room 0x98, entrance 39,
  keyPalace 14** (`bmirein`, verified on load).
  Health floor absorbed per leg: **0 on all 16 legs** (real damage only: hp 88 -> 76 on the lake, 72 by 0x72, 65 after Kakariko, 57 on Death Mountain, healed by hearts to 88, 68 at the Mire after the Raven) (no boss room reached; the
  real damage: the Zora / Raven hits on the lake and in 0x70).
- [ ] **Stopped in 0x98:** the gap east of the entrance corridor (pit 0x20 at
  x 288..335, the hookable block at 352, 312). Link hooked from (272, 304)
  is pulled to x 324 and stops over the pit (Tools.lua's pullFrame stops when
  the hook's out-count itl runs out); he falls back to the entrance (header
  hole target 0). To check against the GBA's LinkState_Hookshotting where
  the pull ends; the cane, Vitreous and crystal 6 wait on it.
- [ ] Not done: the splash sound, the 0x21 push switch's sheet, the PoD door's
  map steps / sounds.
- [ ] Notes: the mirror portal Link lands on crosses back when he leaves and
  touches it again: in 0x6A the stump's twin spot under the LW flute boy
  (who holds Link 672 frames) sent Link back; mirroring from the dig spot's
  twin (1164, 2690) avoids both. Talk / lift are R, the item button A.
  Magic was 0 after Kholdstare (Ether costs 32): the green potion is the
  cartridge's way; the Desert Palace plaque / Hera basement pots were tried
  (not kept).

Real app (cache v63, full-window shots): `RUNID=real72a` from `ck_r72_t_mire1`:
the rain over 0x70 (`real/shots/real72a_rain2_win.png`), Ether, the Mire's
entrance open and dry (`real72a_open2_win.png`); `real72b` from `ck_r71_b9e2`:
0x9E's big block carried whole (`real72b_p15_9E_win.png`).

Tests: new `zelda_alttp_r72_test` (the hooks; cacheVersion; the flash level
on stand-in frames / levels; the event bit; raining by world / area / story;
one thunder on frame A; with the ROM: the import, the area is OwEvents' Mire
area, the levels, the thunder is a sound id; 23 checks). All 79
`zelda_alttp_*` files pass (`r72/out/alltests72.txt`). Audits 304/304 rooms,
80/80 overworld areas (`r72/out/audit_rooms72.log`, `out/audit_ow72.log`;
r66's `audit/mains.txt`), cacheVersion 63.

## Round 73 (2026-11-18)

Misery Mire with real input from the entrance: the hookshot gap of 0x98, the
stairs to 0xD2, its Wizzrobes and Snapdragons, the main hall 0xC2 (the
switch pot: the key chest shows) and west into 0xC1. Port: the hookshot's
arrival checked against the GBA (Hook73), the kill-room tags' flags4 skip
(Clear73), the splash sound (Splash73 + Sfx site). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r73/` (the r72 kit with r73 paths;
checkpoints `ck_r73_*`; `doc/round73.md`). **cacheVersion 64** (the splash
id is a new import site): harness store re-imported (REIMPORT=1), real app
re-imported (`real/reimport.sh`, rom-cache v64).

- [x] 73.1 **The 0x98 gap (goal 1).** LinkState_Hookshotting (GBA
  0x0809BBD0) and Ancilla1F_Hookshot (0x0811CBA0) traced: while pulled
  (related_to_hookshot +0x1810 != 0) the ancilla only draws (0x0811CBD4);
  the state takes ancilla_item_to_link[k] (+0xE29, k = +0x1831) - 1 a frame
  and ends below 0 (0x0809BD0C), so the pull lasts as many frames as the
  hook flew; the velocities are kHookshotArrC / D (0x08167FDC / E0) while
  the hook + kHookshotArrA / B is > 1 px away (`cmp r0, #1; ble` at
  0x0809BDCC / 0x0809BDFC); Link_HandleVelocity (0x080978AC) moves vel >> 4
  px a frame with the sub-pixel carry; no pit test while pulled. The grab
  (0x0811CF10) needs +0x1784 & 3 and a count > 3. The port's pullFrame
  already did all this: Link ends kHookshot_Xd (11 px) short of the hook,
  at x 335 in 0x98, his left points over the pit. The arrival
  (0x0809BE14): Player_TileDetectNearby (0x0809EDA4, points x + 0 / 15,
  y + 8 / 23 from 0x08168134 / 0x08168144), deep water -> AncillaAdd_Splash
  (0x080AD1EC) + swimming, else a pit bit -> state 1
  (LinkState_FallingIntoHole, the edge drag), else the spot is kept. The
  drag is beaten by holding the direction: the round-72 bot let go of the
  pad after the shot. With right held Link walks off the edge to x 336.
  Fixed: the outdoor arrival tested deep water at the SNES's x + 2 / 13,
  y + 10 / 21; now the GBA's points (new `Hook73.lua`, one line in
  Tools.lua's pullFrame).
- [x] 73.2 **Port: Clear73 (new module, two one-line hooks in Actors.lua).**
  Sprite_CheckIfRoomIsClear (0x080CAF64, tag 0x0A) and
  Sprite_CheckIfScreenIsClear (0x080CAEC0, tags 1..9) skip sprites whose
  flags4 (+0x1132) has 0x40; the port counted every fighting sprite. The
  flags4 bytes are the import's (no ROM reads).
- [x] 73.3 **Port: the splash sound (goal 4; new `Splash73.lua`, Sfx.SITES
  `splash` = 0x080AD20A, ExtractA27's EXTRA list).** AncillaAdd_Splash
  starts sound `movs r0, #id` at 0x080AD20A through the Link-panned wrapper
  0x080C1A8C; its 13 callers (bl at 0x080947B4 .. 0x0809BF80) are the
  moments Link lands in deep water. Played when Link starts swimming
  (lk.swim outdoors, lk.inDeep indoors) or drowning. Checked: one splash
  entering the lake from `ck_r72_bmir`.
- [x] 73.4 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain73.sh` P=b from `ck_r72_bmirein` (0x98, entrance 39, keyPalace 14,
  verified on load at every leg): 01 to (272, 304), the hookshot right with
  the direction held: across the pit (`bgap`); 02 round the block, the
  spiral stairs at x 392 -> **0xD2** (`bd2`); 03 the four Wizzrobes (WZ:
  beside each, the swing as it phases in), the Snapdragons, tag 0x0A opens
  the north shutter -> **0xC2** (`bc2`); 04 the pot at (208, 120) lifted, its
  switch (tag 0x27): **the key chest shows** (288, 64), the west door ->
  **0xC1** (`bc1`).
  Health floor absorbed per leg: **0 / 0 / 20 / 4** (real damage: hp 68 ->
  16 in 0xD2: three Wizzrobe beams of 16, two Snapdragon bites, the Beamos'
  laser; 0xC2's Sparks).
- [ ] **Stopped in 0xC1:** C2's key chest stands behind the raised blue pegs
  (a crystal switch must flip them: C1's bottom-right 1E, or 0x91 / 0x92);
  C1's top-right quadrant has no way down to that switch and its Stalfos
  (0xA7) beat the bot's sword fight (the floor absorbed > 400 in tries).
  Next: the C1 shutters (tag 0x33) / the north door to 0xB1, the crystal
  switch, C2's key, then the keys of 0xB3 / 0xA2 / the pots of 0xA1 / 0xB3,
  the big key (0xD1), the Cane (0xC3's big chest), the torches, Vitreous.
- [ ] Notes: in the real app Link standing on C2's switch under the lattice
  (lower level) was not visible in the shot (`real73c_p09_C2_win.png`): to
  check whether the cartridge draws him over the grate. Not done: the 0x21
  push switch's sheet, the PoD door's map steps / sounds.

Real app (cache v64, full-window shots): `RUNID=real73a` from
`ck_r72_bmirein`: the hookshot pull over 0x98's pit
(`real/shots/real73a_p10_98_win.png`), past it (`real73a_p12_98_win.png`),
0xD2 (`real73a_p17_D2_win.png`); `real73c` from `ck_r73_bc2`: the switch
under the pot and the pegs (`real73c_p09_C2_win.png`).

Tests: new `zelda_alttp_r73_test` (the hooks; cacheVersion; Hook73's points
on a stand-in map and the arrival; Clear73 on stand-in flags; Splash73's
events and one sound; with the ROM: the splash id, flags4 0x40 marks some
types only, the hookshot tables bound the pull; 27 checks). All 80
`zelda_alttp_*` files pass (`r73/out/alltests73.txt`). Audits 304/304 rooms,
80/80 overworld areas (`r73/out/audit/rooms_r73.txt`, `ow_r73.txt`; r66's
`audit/mains.txt`), cacheVersion 64.

## Round 74 (2026-11-18)

Rule fix (literals to import), the Misery Mire pot / level bug behind the
r73 "invisible Link", and the Mire with real input from 0xC2 to the big key
room 0xD1. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r74/` (the r73
kit with r74 paths; checkpoints `ck_r74_b*`; `doc/round74.md`).
**cacheVersion 65** (new import data tab74): harness store re-imported
(REIMPORT=1), real app re-imported (`real/reimport.sh`, rom-cache v65).

- [x] 74.1 **Literals moved to import (new `Tables74.lua`, ExtractA27 EXTRA
  `tab74`, live tables filled on RomTables.onBind).** Read from code sites,
  none shipped: Player_TileDetectNearby's (0x0809EDA4) four points (the
  tables loaded by `ldr` at 0x0809EDC4 / 0x0809EDDE; Hook73.POINTS and
  Dungeons26.pitBits now use them); RevealPotItem's (0x080929C8) four switch
  words (`ldr` at 0x080929E8 / F2 / FC / 0x08092A06; Interior.POT_SWITCH);
  Follower_CheckBlindTrigger's spot and reach (`ldr` 0x08115C52, `movs;
  lsls` 0x08115C64, `cmp` 0x08115C5C / 70; ThievesTown.TRIGGER, the reach
  was a literal 24 too); kAgahnim_OamFlags (`ldr` 0x080DB514; Agahnim.OAM);
  kGibo_OamFlags2 (`ldr` 0x080FF5F0; Enemies27A.GIBO_FLAGS2). Comments that
  quoted the values were reworded. Left as they are (import-time offsets or
  logic, not data): Ending27.DOOR_TAB (offsets into the predefined tile
  data, read at import), Manip71 CELLS, the bit weights. Still literal, next:
  Dungeons26.CRYSTAL_PAL, Cape.DEPLETE (sites not found yet).
- [x] 74.2 **The draw priority (goal 2) and Pots74 (new module, two hooks in
  Interior).** Link's OBJ priority matches the GBA: lower level -> 3, under
  the upper map (BG2, priority 2), so through the lattice's holes he shows
  (harness shot). The real bug: the port marked a pot's 0x70 + n attribute
  (and the secret-0x88 switch) on BOTH tables; the cartridge writes the
  pot's own level only (pos | 0x2000 = the lower table, which
  TileDetectNearby's indoor path 0x080A0454 reads while +0xA10 is set). In
  0xC2 the r73 bot went down the in-room stairs, walked UNDER the lattice on
  the lower floor and lifted the upper level's pot (layer 3) -> Link hidden
  under the switch tile. Now the pot is only liftable from the lattice
  (upper), where the pegs enclose it: a crystal switch first (C1 BR).
  r73's leg 04 (`ck_r73_bc1`) is therefore not a valid route state; this
  round restarts from `ck_r73_bc2`.
- [x] 74.3 **Chest74 (new module, one hook in Chest70.hide).** A revealed
  hidden chest seen again (revisit / checkpoint) had its attributes but no
  picture: the closed chest's words go into the map as
  RoomTag_OperateChestReveal (0x0807A478) writes them.
- [x] 74.4 **Bot: Stalfos (tok74 SK).** Stalfos_Skellington jumps away while
  Link faces it unless the sword is held (swordHeld 9..0x8F): face it, hold
  B, walk at it, release for the spin within 20 px. 0xB3's three Stalfos in
  1050 frames, 8 hp absorbed (GF69 had 460 absorbed in 4000 frames and one
  left).
- [x] 74.5 **Route, real input (harness from checkpoints, HPFLOOR=16,
  DODGE=1):** `chain74.sh` P=b from `ck_r73_bc2` (entrance 39, keyPalace 14
  verified on load at every leg, CKV74): 01 C2's north-right door -> **0xB2**
  (`bb2`); 02 the Snapdragons, the block pushed (tag 0x0E opens the
  shutters), east -> **0xB3** (`bb3`); 03 SK (three Stalfos), pot 1: **small
  key**, back through B2 -> C2 (`bc2k`); 04 C2's west key door -> **C1 BR**
  (`bc1`); 05 the **crystal switch** (sword): pegs flipped, back east
  (`bpeg`); 06 C2's lattice on the upper level: the pot lifted, its switch
  -> the key chest shows (`bsw`); 07 the chest (288,64) from below: **small
  key** (`bkey`); 08 C1 BR -> south -> **0xD1** (`bd1`); 09 D1's bottom-right
  quadrant (`bbr`).
  Health floor absorbed per leg: **32 / 72 / 120 / 96 / 64 / 16 / 0 / 96 /
  24** (real hp stays 16/88 all along: Sparks, the Medusa / 4-way shooters'
  fireballs, Beamos lasers, C1 BR's Green Stalfos / Anti-fairy). No heal
  found with real input in reach (pots gave a key, magic; no heart drops).
- [ ] **Stopped in 0xD1 BR:** the big key chest (376,376) stands on a
  platform across a 16-px pit; the hookshot down grabs it but the pull ends
  with Link's top points over the pit and the edge drag pulls him back /
  in. Next: check the down pull's end against LinkState_Hookshotting
  (kHookshotArr* for down) or reach the platform from D1 BL's shutter; then
  the big key, 0xC3's Cane (big chest), the torches (C1 BL, tag 0x33),
  Vitreous (0x90 via 0xA0), crystal 6; B3's chest across its spikes (pot 3's
  switch); heal first.

Real app (cache v65, full-window shots): `RUNID=real74a` from `ck_r74_bpeg`:
Link visible on C2's lattice with the pot (`real/shots/real74a_p04_C2_win.png`),
the key chest opened from below (`real74a_p10_C2_win.png`); `real74b` from
`ck_r74_bsw`: the revealed chest drawn after a reload (Chest74,
`real74b_p03_C2_win.png`).

Tests: new `zelda_alttp_r74_test` (the hooks; cacheVersion; Tables74 bind on
stand-ins, pitBits / Hook73.bits on stand-in points; Pots74's tables; with
the ROM: tab74's shapes bound into every user, every two-level room's pots
on one table only; 29 checks); r73's test now uses stand-in points. All 81
`zelda_alttp_*` files pass (`r74/out/alltests74.txt`). Audits 304/304 rooms,
80/80 overworld areas (`r74/out/audit/rooms_r74.txt`, `ow_r74.txt`; r66's
`audit/mains.txt`), cacheVersion 65.

## Input round (2026-11-18): controls like the Pokemon games, START

- Reported: "I have to click the right bumper to use what should be set to
  A", and no START route to the launcher. Cause: since round 18 the port reads
  the action (talk, lift, open, read, dash) from R and the item from A -- the
  cartridge's control mode 0. The cartridge has other modes: its button builder
  `0x0806995C` switches on `+0x548` (RAM `0x03002778`): mode 1 = action A,
  item R (`0x08069D00` writes it, from the restart routine `0x08068D60`);
  mode 2 = item A, action A+B. New `Controls.lua`: the app defaults to mode 1
  (A action, R item, B sword, L map, SELECT items, START menu), the system
  menu's CONTROLS row switches back to the GBA's mode 0 (kept as
  `options.zelda.game.alttp.controls`); the messages' A / R glyphs swap with
  it (`Text.BUTTON`). Tests / harnesses without a host keep mode 0.
- START: the GBA swaps the SNES START / SELECT (`0x08069AA8`: GBA SELECT ->
  SNES START bit 0x10, GBA START -> SNES SELECT 0x20), so GBA START is the
  save / quit dialogue: START in play now opens the runtime's system menu
  (SAVE, OPTIONS, QUIT TO LAUNCHER). Runtime-wide (`src/zelda/ZeldaControls.lua`):
  Escape is START as in the Pokemon games, START held 0.5 s opens the system
  menu anywhere; guide, SELECT+START held and touch MENU still do.
- Test: `tests/zelda_input_test.lua`. Kit: `scratch_claude/zelda/input/`
  (`run_all.sh`, `shot/` touch-overlay shots).

## Widescreen (2026-11-18)

- Request: "no black bars on the sides of the screen". OURS (the GBA is
  240 x 160): the play field widens to the window's sides, nothing is
  stretched. Runtime side `src/zelda/ZeldaWide.lua` + small hooks in
  `ZeldaRuntime` (`viewSize(scale, wide)` gets the width the window wants =
  window width / scale, even, 240..512; a third return value = the width the
  field spans; the HUD overlay stays the centred 240 x 160, and filled
  rectangles the overlay draws against its left / right edge -- fades, game
  over, the iris -- are continued over the margins).
- ALttP: `src/zelda/alttp/Wide.lua` (installed last in Game.lua) on Zoom's
  seams: wider field in play / room states incl. the item menu and text
  (menus, HUD, text stay 240 wide in the middle); the overworld map, dungeon
  map, Four Swords, front end and ending stay 240 x 160. The cartridge's
  camera, room / area bounds and gameplay are unchanged (G.W / G.H,
  Interior:camera); only drawing widens. Outdoors the neighbouring screens are
  drawn from the ROM maps and the view is held inside the 4096 px world (or
  the special area). Indoors the room's other quadrants and connected rooms
  show (Zoom's neighbours); on a side with no connected room the view is held
  inside the room's 512 px map; anything left is the room's backdrop colour. Arrows /
  boomerang / rods now leave at the cartridge's 240 x 160 screen
  (Items.lua / Tools.lua used the drawn view's size).
- Option: system menu WIDESCREEN ON / OFF (`options.zelda.game.alttp.widescreen`,
  default ON). Zoom (wheel / L3 / R3) still works on top of it.
- Test: `tests/zelda_widescreen_test.lua`. Kit / shots:
  `scratch_claude/zelda/wide/` (`run.sh alttp s_alttp.lua <out> [W H]`,
  `shots/alttp_1280x720_*`, `alttp_1920x1080_*`).

## Round 75 (2026-11-18)

Rule fix (the last two literals to import), the D1 big-key question settled
against the cartridge, and the Mire with real input from D1 to the moving-wall
room 0x97. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r75/` (the r74
kit with r75 paths; checkpoints `ck_r75_a*`; `doc/round75.md`).
**cacheVersion 66** (new import data tab75): harness store re-imported
(REIMPORT=1), real app re-imported (`real/reimport.sh`, rom-cache v66).

- [x] 75.1 **Literals moved to import (new `Tables75.lua`, ExtractA27 EXTRA
  `tab75`, live tables filled on RomTables.onBind).** kCrystalSwitchPal: the
  table Sprite_CrystalSwitch (type 0x1E, main 0x0810FC0C, found through the
  sprite main table at 0x081741B0) loads with `ldr r4` at 0x0810FC2E and
  indexes with the barrier state & 1 (Dungeons26.CRYSTAL_PAL).
  kCapeDepletionTimers: LinkItem_Cape's `ldr r1` at 0x080A37C8 (put on) and
  the drain's at 0x080A3836 (reload), indexed by link_magic_consumption
  (inventory 0x5B, GBA 0x0200235B) -- the port used entry 0 always; now
  Cape.timer reads the consumption as the cartridge does (Cape.DEPLETE).
  Grep of the other literal tables in src/zelda/alttp: what is left is logic
  / shape (bit weights 8 4 2 1, direction maps, quadrant orders, OAM / BG
  slot numbers, item-slot numbers). Candidates still literal, not moved this
  round (code sites not identified yet): Carry.THROW_TIMES, Hera kodongo's
  velocity tables (Sprite 0x86 main 0x08110109: no direct table load found),
  Tools.MAP16 / DIGGABLE (the shovel's map16 list), Items.lua's arrow recoil
  RX / RY, Menu.RECEIPT_ITEMS.
- [x] 75.2 **D1's big key chest and the hookshot pull (checked, no port
  change).** LinkState_Hookshotting (0x0809BBD0) loads kHookshotArrA / B
  (0x08167FD4 / D8) with `ldrb` (unsigned) and adds them to the hook's 16-bit
  spot, so for up / down / right the "close enough" test (|d| > 1) never
  stops the pull: Link moves ancilla_item_to_link frames at kHookshotArrC / D
  (vel >> 4 = 4 px), i.e. exactly the hook's flight. The port's signed table
  stops when |hook + A - Link| < 2, which for those directions only happens
  on the frame the count runs out: the same end spot (hook y - 20 for down).
  The arrival's TileDetectNearby pit bits -> state 1 (drag) also match. So
  from D1 BR's stub the pull ends with Link's top points over the pit on the
  GBA too. The cartridge's way: room header bytes (hdr75): D1's stair goes to
  0x97 and **0x97's hole destination is D1**; 0x97 holds a region (x 344-455)
  with a hole at (400-431, 376-407), right over D1 BR's platform, behind a
  moving wall (room tag 0x1C, RoomTag_MovingWall_East) that 4 lit torches
  start.
- [x] 75.3 **Route, real input (harness from checkpoints, HPFLOOR=16,
  DODGE=1; control mode 0 in the harness):** `chain75.sh` P=a from
  `ck_r74_bd1` (D1 top-right; same save as `ck_r74_bbr`, entrance 39,
  keyPalace 14 verified on load at every leg, CKV74): 01 D1 -> C1 BR (Green
  Stalfos / Bari), **C1 BR's west key door** (the last small key) -> C1 BL
  (`ac1bl`); 02 C1 BL south -> D1 TL along the conveyor, the pot at
  (192,64): **full magic** (its secret 0xD) (`ad1tl`); 03 D1 TL's stairs ->
  **0x97** (`ar97`); 04 0x97: the push-block alcoves opened (each block moves
  once: the bottom and top blocks sideways, the middle one into the freed
  place), **the lamp lights the 4 torches** (16 magic) -> **the moving wall
  starts** (tag 0x1C) (`alit`; a reload puts blocks and wall back, as the
  cartridge's room reload).
  Health floor absorbed per leg: **56 / 0 / 0 / 32** (Green Stalfos, the
  Wizzrobes in 0x97). Heal: not reached with real input -- kills in C1 BR /
  D1 TL / 0x97 (Green Stalfos pack 7, Bari pack 6, Wizzrobe pack 1, read with
  `prize75`) gave one heart that dropped where Link could not reach it in
  time; enemies in the rooms just left stay dead (kill memory). Pot hearts
  (secret 0xB) are in 0xA1 (5), 0x91, 0x93, 0xB1, 0xB2 (`pots75`).
- [ ] **Stopped in 0x97 with the wall moving:** the region stays hidden and
  walled in the port. 0x97 is collision mode 0 (header 0x20; the Desert's
  wall rooms are mode 2); its region is covered by the upper map (words
  0x7015) and closed by bg2 words 0x24A5 / 0x2499 at x 328-343, while
  DesertPalace.wallFrame slides the lower ("bg3") map, empty in 0x97. Next:
  RoomTag_MovingWall_East's mode-0 path (0x0807AF80 .. 0x0807AAC4: every
  step +0x9B4 = 0x16, +0x514 |= 3, +0xB14 = 0) -- which layer moves and
  which attributes open; then the hole -> D1 BR's platform: the big key,
  0xC3's Cane, C1 BL's torches, B3's spike chest, Vitreous, crystal 6.

Real app (cache v66, widescreen ON, 1280 x 720 window, **control mode 1**:
the app's default A action / R item; the real-app adapter sends the bot's
action on A and its item on R in play, raw A / B in menus and text):
`real75b` / `real75d` from `ck_r75_ar97`: 0x97 in widescreen with the pushed
blocks and the lamp (`real/shots/real75b_p89_97_win.png`), torches lit with
R in mode 1 (`real75d_p91_97_win.png`, TORCH63 lit 3 with magic 128 -> 112;
the real app's slower walk lets the first torch burn out before the fourth),
the lamp on R (`real75c`: magic 128 -> 124).

Tests: new `zelda_alttp_r75_test` (the hooks; cacheVersion; Tables75 bind on
stand-ins; Cape.timer by consumption; the extract on a stand-in ROM incl.
refusals; with the ROM: tab75's shapes bound into Dungeons26 / Cape; 20
checks). All 82 `zelda_alttp_*` files plus `zelda_input_test` and
`zelda_widescreen_test` pass (`r75/out/alltests75.txt`). Audits 304/304
rooms, 80/80 overworld areas (`r75/out/audit/rooms_r75.txt`, `ow_r75.txt`;
r66's `audit/mains.txt`), cacheVersion 66.

## Round 76 (2026-11-18)

Walk speed measured (no slowdown), the Misery Mire's moving wall room ported
(Wall76), more literals moved to import (Tables76), and the Mire with real
input from 0x97 through the big key to B1 and C1. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r76/` (the r75 kit with r76
paths; checkpoints `ck_r76_a*`; `doc/round76.md`). **cacheVersion 67** (new
import data wall76 + tab76): harness store re-imported (REIMPORT=1), real app
re-imported (`real/reimport.sh`, rom-cache v67).

- [x] 76.1 **Walk speed / tick rate (no port change).** Link moves 1.5 px a
  tick straight (kSpeedMod 24/16, alternating 1 / 2 px), identical per tick in
  the harness and the real app (`spd76`: the same per-frame positions).
  ZeldaRuntime ticks at 16777216 / 280896 = 59.7275 Hz with a fixed step and
  an accumulator (max 8 steps, dt capped 0.25); measured in the real app with
  LOVE's own dt (1280 x 720 widescreen, window shown, vsync requested): 241
  draws/s, 59.53 ticks/s -- the cartridge's rate. The draw rate does not touch
  the logic (`det76`: the same actors / Link / hp at every 100th tick with 1
  and ~4 draws per tick). The real-app harness fed 1/60 per update and so
  skipped one tick every ~224 updates (0.45%): kit fix (DT 0.0167428).
  Round 75's "slower walk" was a Wizzrobe hit (assist 32 -> 48) knocking Link
  6 px off line so the next XT stuck and the lamp missed; with the same steps
  the real app lights the 4 torches at frame 2275 (harness 2273).
- [x] 76.2 **0x97's moving wall (new `Wall76.lua`, ExtractA27 EXTRA
  `wall76`).** Tag 0x1C's handler (0x0807ABA4, the entry before 0x1D's
  0x0807AF50 in the tag table) starts with `cmp r0, #0x97` (0x0807ABB6, the
  room read at import) and runs its own path for that room (0x0807AD84): the
  torch check and the 0x2200 step as usual, but BG1's scroll (+0x950) is not
  written -- the room shakes, it does not slide (Link held); at the stop
  (kMovingWall_Tab1, both compares) the map swap: an LZ77 map (`ldr` at
  0x0807AE4E) unpacked and its screen blocks 1 and 3 copied over the upper
  map (0x02018800 / 0x02019800), another LZ77 map (`ldr` 0x0807AE7C) over
  the high-priority map 0x0201C000, then the upper attribute table opened
  along the old wall (`movs r4, #n` 0x0807AEAE times two cells and the two
  below, from the literal at 0x0807AEB4, step `adds r1, #0x80` 0x0807AEC4).
  A later load with the wall's bit (the room maps loader 0x0807FF10, `cmp` at
  0x0807FF30) takes both LZ77 maps whole. The common per-step 0x0807AAC4
  (TM 0x16, BG1 priority 3, +0xB14 = 0) is display only. OURS: the room
  shake is not drawn (the port's shake only moved the lower map), no sound
  0x7B.
- [x] 76.3 **Literals moved to import (new `Tables76.lua`, `tab76`).**
  Kodongo (Hera.lua): kKodondo_Xvel / _Yvel (`ldr` 0x0810FE28 / 0x0810FE34),
  Kodongo_SetDirection's speeds (0x0810FE78 / 0x0810FE82, again 0x0810FECE /
  0x0810FEDE), Kodongo_SpawnFire's spot (16-bit lo / hi tables: 0x0811005A,
  0x08110064, 0x08110084, 0x0811008E) and the flame speed (0x081100B0 /
  0x081100BE). The arrow in a sprite (Items.lua): Ancilla_CheckSpriteCollision's
  recoil by ancilla direction & 3 (0x080C0CAE -> x recoil +0x1112,
  0x080C0CBC -> y recoil +0x1102). Not moved: Carry.THROW_TIMES (code site
  not found), Tools.MAP16 / DIGGABLE (no table in the ROM: the shovel's list
  is code compares, not located), Menu.RECEIPT_ITEMS (the port's choice of
  which receipts take the grid path; their slots / values are already
  imported from data.t.gear).
- [x] 76.4 **Route, real input (harness from checkpoints, HPFLOOR=16,
  DODGE=1; entrance 39 / keyPalace 14 verified on every load, CKV74):**
  `chain76.sh` P=a from `ck_r75_ar97`: 01 0x97: the blocks, the lamp lights
  the 4 torches, the wall's tag runs ~1030 frames, the maps swap, BL's east
  door -> the corridor -> over the opened wall line -> the hole -> **D1's
  platform** (`ad1p`); 02 **the big key** (chest 376,376 from below) (`abk`);
  03 the platform's walkway west -> D1 BL (`ad1bl`); 04 D1 BL's warp tile
  (0x4B) -> B1 BL (`ab1`); 05 B1 BL -> BR -> the neck -> TR: **the skull pot
  (304,64) gives a heart: hp 16 -> 24** (a Medusa fireball takes it back
  later) (`ab1tr`); 06 back down -> B1 BR's south door -> C1 TR (`ac1tr`).
  Health floor absorbed per leg: **64 / 0 / 0 / 16 / 48 / 24** (Wizzrobes
  while Link is held in 0x97; B1's Medusa fireballs and spike traps).
- [ ] Next: C1 TR -> C2 (east door y 128: the room's foes pushed Link back),
  B2's lower-level heart pot (304,144), B3 (the block again) and its spike
  chest (small key 144,384), C3's Cane of Somaria (big chest 368,56),
  Somaria blocks on switches, Vitreous (0x90 via 0xA0), crystal 6. B1 TR: a
  fireball's recoil pushed Link into the top wall row at (296,48) (port's
  recoil vs walls). 0x97's room shake while the wall runs.

Real app (cache v67, widescreen ON, 1280 x 720, control mode 1):
`real76a` from `ck_r75_ar97`: torches lit with R (lit 4 at frame 2275), the
wall's swap, the opened corridor and the hole, the fall to D1
(`real/shots/real76a_s74_02_win.png` .. `_05_win.png`); `real76b` from
`ck_r76_ab1`: B1 TR's skull pot lifted with A, the heart picked (16 -> 24,
`real76b_s74_01_win.png` / `_02_win.png`).

Tests: new `zelda_alttp_r76_test` (hooks; cacheVersion; Tables76 / Wall76
extract on stand-in ROMs incl. refusals; Wall76's map append / right-half mix
/ apply / reload hook on stand-ins; with the ROM: wall76 and tab76 bound; 31
checks). All 83 `zelda_alttp_*` files plus `zelda_input_test` and
`zelda_widescreen_test` pass (`r76/out/alltests76.txt`). Audits 304/304
rooms, 80/80 overworld areas (`r76/out/audit/rooms_r76.txt`, `ow_r76.txt`;
r66's `audit/mains.txt`), cacheVersion 67.

## Round 77 (2026-11-20)

Link's knockback indoors now runs the walking collision (Recoil77), and the
Misery Mire with real input from C1 through C2, B2, A2, B3, C3's Cane of
Somaria, back to 0x93's switch (a Somaria block on it) and into 0x92.
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r77/` (the r76 kit with
r77 paths; checkpoints `ck_r77_a*`; `doc/round77.md`). **cacheVersion 67**
(no new import data; no re-import needed).

- [x] 77.1 **Port fix: knockback into walls (new `Recoil77.lua`, one-line
  hook in Escape.lua's indoor recoil).** Link_HandleRecoilAndTimer
  (0x08099D98; landing 0x08099E9C) ends with `bl 0x0809407C` (0x0809A07E),
  the movement routine the walking state runs: velocity, then the cardinal
  checks 0x0809E650 (StartMovementCollisionChecks_Y 0x08094DC0 unless
  +0x172B & 0x20, _X 0x080962D0 unless & 0x10) with Link incapacitated
  (door bits count as walls, no doorway state, HandlePushingBonkingSnaps
  snaps him to the wall's edge). The port moved Link in recoil when four
  probes 1 px inside his box (x + 1 / x + 14) were free, so a fireball could
  leave him 1 px inside a side wall (B1 TR: x 295 against the column
  288-295) where the walking probes (x + 0 / x + 15) already hit it. Now the
  recoil step is Doors.checkY / checkX (incap) -- the same probes and snaps
  as walking; the round-11 in-room stairs guard stays. (y 48 in B1 TR is a
  legal spot: the head probe y + 8 sits on the floor row 56.) The overworld
  recoil is unchanged.
- [x] 77.2 **Heal with real input:** B2's lower-level heart pot (304,144):
  hp 16 -> 24; 0x93's heart pot (384,112): +8 (Medusa fireballs took 8 on
  the way). Anti-fairies (0x15) drained magic 112 -> 16 on the way (no magic
  pot on the route yet).
- [x] 77.3 **Route, real input (harness from checkpoints, HPFLOOR=16,
  DODGE=1; entrance 39 / keyPalace 14 verified on every load, CKV74):**
  `chain77.sh` P=a from `ck_r76_ac1tr`: 01 C1 TR east door -> C2 (`ac2`);
  02 C2's chest is already open (r74) (`ac2key`); 03 C2's upper ring ->
  north door x 120 -> B2 BL (`ab2`); 04 B2 BR's block pushed right (tag 0x0E,
  SE push opens the shutter 376,296; pushed up it plugs the neck) -> the
  corridor -> A2 (`aa2`); 05 A2's right bridge: chest 376,144 = small key
  (`aa2key`); 06 back to B2, the block pushed down out of the neck (`ab2n`);
  07 B2 east door -> B3 BL -> the key door 120,296 -> B3 TL (`ab3tl`); 08 B3
  TL's stairs 0x1E down -> lower west door -> B2 lower (`ab2lo`); 09 the
  heart pot (`aheal`); 10 the Wizzrobe, under the pot column, the big key
  door 248,40 -> A2's left bridge -> 0x93 (`ar93`); 11 0x93's heart pot
  (`aheal2`); 12 back down to B3 BL (`ab3bl`); 13 B3 BL south door -> C3 TL
  (`ac3`); 14 C3 TL's ledge 0x28 into the recessed middle -> BL -> the BR
  crossing (two-way shutter) (`ac3br`); 15 **the Cane of Somaria**: the
  hookshot from (300,408) to the post 0x27 (440,416) beats the crumbling
  walkway (overlord 0x0B at 368,416: 160 frames, then a 16-px tile every 17
  frames bottom to top), up the walkway, big chest 368,56 (`acane`); 16 back
  to 0x93 (`ar93c`); 17 0x93: the pot over the floor switch lifted, a
  **Somaria block on the switch** (120,120; tag 0x16 holds the shutter
  120,216 open) -> BL (`ar93bl`); 18 BL west door -> **0x92** (`ar92`).
  Health floor absorbed per leg: **16 / 0 / 8 / 24 / 0 / 0 / 24 / 0 / 0 /
  0 / 56 / 0 / 12 / 8 / 0 / 8 / 16 / 0** (Medusa fireballs and the B3 Stalfos;
  none from pits on the kept legs). Real hp at
  the end 16/88, magic 8.
- [ ] Next: 0x92 BR is penned by peg columns (x 336..432, every 24 px); its
  crystal switches (1E) are at (384,144) on an island in TR's pits and
  (48,192) in TL -- toggle them (arrow / boomerang / Somaria bullets), then
  0x92 -> 0x91 (heart pot 336,64) -> stairs -> A0 -> big key door ->
  Vitreous (0x90), crystal 6. Magic is low (8): a magic pot (A1 0x0C x2, B3
  192,320) or fairies first. Not done (goal 4): 0x97's room shake (the GBA's
  RoomTag_MovingWallShakeItUp 0x0807AB2C writes +0xA28 / +0xA2A from the
  tables at 0x08152ABA / 0x08152ABE by frame & 1) and sound 0x7B (`movs r0,
  #0x7B` at 0x0807AE14, played once at the stop), Carry.THROW_TIMES, the
  0x21 switch sheet, PoD door steps.

Real app (cache v67, widescreen ON, 1280 x 720, control mode 1, DT
0.0167428): `real77a` from `ck_r77_ac3br`: the hookshot to the post over the
crumbling walkway (`real/shots/real77a_s74_01_win.png`), the big chest opened
(`real77a_s74_03_win.png`, inventory 0x33 = 1); `real77b` from
`ck_r77_ar93c`: the Somaria block on 0x93's switch, the shutter open
(`real77b_s74_02_win.png`), through to BL (`real77b_s74_03_win.png`).

Tests: new `zelda_alttp_r77_test` (the hook; Recoil77 on a stand-in room:
left / up / right knockbacks stop flush with the walls, a free move is whole,
a door counts as a wall while recoiling, the stairs guard; 15 checks). All 86 test files:
`zelda_alttp_*` files plus `zelda_input_test` and `zelda_widescreen_test`
pass (`r77/out/alltests77.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r77/out/audit/rooms_r77.txt`, `ow_r77.txt`; r66's `audit/mains.txt`),
cacheVersion 67.

## Round 78 (2026-11-20)

The Misery Mire finished with real input from 0x92 to crystal 6: the peg pen
left through a skull pot, the crystal switches and bomb walls of 0x92, 0x91's
pots, A0, Vitreous. Two port fixes (Belt78: conveyor push vs walls; Shake78:
the moving wall's shake and stop sound from the ROM). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r78/` (the r77 kit with r78 paths,
`t.sh`, `tok78.lua`; checkpoints `ck_r78_b*`; `doc/round78.md`).
**cacheVersion 68** (new import data shake78): harness store re-imported
(REIMPORT=1), real app re-imported (`real/reimport.sh`, rom-cache v68).

- [x] 78.1 **Port fix: the conveyor's push runs the walking collision (new
  `Belt78.lua`, one-line hook in Mech27.conveyLink).** Link_ApplyConveyor
  (GBA 0x080973A8, called at the end of Link_HandleVelocity, `bl` at
  0x08097A42 / 0x0809912C) adds the belt step (kMovingBeltY / X) straight
  into Link's y / x (+0x16C0 / +0x16C4) and ORs kMovePosDirFlag into +0x1727,
  so the cardinal checks after it also test the belt's way and snap Link to
  the wall's edge. The port moved Link on a belt only when four probes 1 px
  inside his box were free, after the walk's collision: 0x92 TR's right belt
  left him at x 457 (x + 15 = 472 inside the east wall) and walking up the
  up-belt he bounced 199 / 200 forever. Now the belt step is Doors.checkY /
  checkX (as Recoil77); in a doorway the old test stays.
- [x] 78.2 **The moving wall's shake and stop sound (new `Shake78.lua`,
  ExtractA27 EXTRA `shake78`).** RoomTag_MovingWallShakeItUp (0x0807AB2C,
  called each moving frame at 0x0807ABE0 / 0x0807ADA0 -- the Mire room's own
  path -- / 0x0807AF78): +0xA28 = tableA[frame & 1] (`ldr` 0x0807AB44),
  +0xA2A = tableB[frame & 1] (`ldr` 0x0807AB5C; the same tables at 0x0808E16A
  / 0x0808E182, checked equal); the frame's scroll copy (0x0806A78A..) adds
  +0xA2A to BG1's / BG2's horizontal scroll (+0x950 / +0x956) and +0xA28 to
  their vertical (+0x952 / +0x958): both room maps ("bg3" BG1, "bg2" BG2)
  shake, the high-priority map and the sprites do not. The stop plays
  `movs r0, #id` at 0x0807AC66 / 0x0807AE14 / 0x0807AFF8 (checked equal) via
  Sfx.start. Before: only the lower map shook by literal +-1 (invisible in
  0x97, whose lower map is empty) and the stop was silent. Checked in the
  harness: 0x97's wall shakes by the imported pairs and the sound plays once
  at its stop (frame ~1029).
- [x] 78.3 **Route, real input (harness from checkpoints, HPFLOOR=16,
  DODGE=1; entrance 39 / keyPalace 14 on every load):** `chain78.sh` P=b
  from `ck_r77_ar92` (magic there is 0, not 8): 01 the pen's top row has a
  spike block (8A) running x 368-444: timed (WAT), into slot x 392, the
  skull pot (392,368) lifted from above, down the slot, out west and up the
  west column (`bt01`) -- the pegs were not the pen, the pots are; 02 TR's
  bottom belt under the pit's island, an arrow up: the island's crystal
  switch, pegs 1 -> 0 (`bt03`); 03 BR's west column -> BL's east door (the
  orange column down) (`bt04`); 04 a bomb on BL's north bomb wall (0x2E,
  120,296) -> TL's lower strip (`bt05`); 05 TL's crystal switch (48,192) with
  the sword: pegs 0 -> 1 (`bt06`); 06 back down, BL's west part over the
  lowered blue column -> **0x91** (`b91`); 07 0x91: the magic pot (416,64)
  from the right column (magic 0 -> 32), the heart pot (336,64) from the left
  (hp 16 -> 24) (`bheal91`); 08 the spike block on row 224 and the Medusa
  timed, up the gap x 376 -> the stairs -> **A0** (`ba0`); 09 A0's fire snake
  (0x80) round the ring timed, the big key door (120,40) -> **0x90** walking
  in (`b90`); 10 **Vitreous**, the heart container (hp 96/96), **crystal 6**
  -> the overworld (area 0x70, crystals 118 -> 119) (`bcrys6`).
  Health floor absorbed per leg: **8 / 0 / 0 / 0 / 0 / 0 / 0 / 8 / 8 /
  ~1000** (the spike block, a Medusa fireball, the fire snake; the Vitreous
  leg ran with ASSISTMAX=3000: the bot's fight takes ~40 hits of 24 from the
  small eyes; a cartridge player with 16/88 would not survive it). Magic: the
  pot gave 32, anti-fairies (0x15) drained it to 0 by A0. Not used: TR->TL
  bomb wall (280,128) (only TL's rupee strip behind it).
- Harness notes: a checkpoint in a boss room reloads with the boss / shutter
  back (save `@` after walking in, finish the room in one leg); DR stops
  input after the scroll (hold on with H). rch77's 'o' marks Link's y + 0..15
  box; the walking box is y + 8..23 (0x91 / A0 gaps are 8 px tighter).
- [ ] Not done: Somaria block pick-up / throw / push (Items27 "NOT PORTED";
  the route did not need it), Carry.THROW_TIMES, the 0x21 switch sheet, PoD
  door steps. Next: from `ck_r78_bcrys6` (Mire entrance, hp 96/96, magic 0,
  crystals 6 of 7 -- Turtle Rock left) -> Turtle Rock (Quake medallion
  needed for its entrance) or Ganon's Tower prerequisites.

Real app (cache v68, widescreen ON, 1280 x 720, control mode 1): `real78a`
from `ck_r78_bt01`: the arrow at 0x92's island switch from the belt
(`real/shots/real78a_s74_02_win.png`); `real78b` / `real78c` from
`ck_r78_b90`: Vitreous (`real78b_s74_02_win.png`), the heart container
(`real78b_s74_03_win.png`), the maiden's crystal (`real78c_s74_01_win.png`),
outside the Mire (`real78c_s74_03_win.png`).

Tests: new `zelda_alttp_r78_test` (hooks; cacheVersion; Belt78 on a stand-in
room: belt into a wall stops flush, walking on works, up belt, free step,
doorway fallback; Shake78's extract on a stand-in ROM incl. refusals, offsets
by frame parity, the hooks (slide-only lower offset, both maps shake, one
stop sound); with the ROM: shake78's shapes; 26 checks). All 87 test files
(`zelda_alttp_*` plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r78/out/alltests78.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r78/out/audit/rooms_r78.txt`, `ow_r78.txt`; r66's `audit/mains.txt`),
cacheVersion 68.

## Round 79 (2026-11-20)

The Quake medallion with real input: from the Mire (crystal 6) through the
Light World, the hammer-peg portal south-east of the Eastern Palace, the
Palace of Darkness's surroundings and the north-east Dark World to the
catfish's pond. Two ports (the catfish; the throw's speeds and flight).
Turtle Rock not reached: magic is 0 (Quake costs 32) and the bot's bush
farming hangs in Kakariko. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r79/` (the r78 kit with r79
paths; checkpoints `ck_r79_c*`; `doc/round79.md`). **cacheVersion 69** (new
import data cat79, throw79): harness store re-imported (REIMPORT=1), real app
re-imported (`real/reimport.sh`).

- [x] 79.1 **Port: the catfish (new `Catfish79.lua`, ExtractA27 EXTRA
  `cat79`).** Sprite 0xC0 with sprite_E 0 (GBA main 0x080F7558, shared with
  King Zora's thrown flippers): prep y - 12 (0x080F7B3C); state 0
  0x080F76F0 waits for any sprite drowning (state 3) with (cat - x + 0x20)
  and (cat - y + 0x20) below 0x40; 1 the rumble (Link held from timer 0xBF,
  +0x1770; shake pair at the literal 0x080F7814); 2 the emergence (z speed
  0x30, - 2 a frame, splash at 0xD0, graphics table 0x080F7906); 3 the talk
  (graphics 0x080F79C6 by timer >> 3, ripples at 0xA0 / 0xFC / 4, Link let
  go and message 0x12D (+1 with Quake) at 0x60, at 0x50 the medallion:
  sprite 0xC0 with sprite_E 0x11, x speed 0x18, z speed 0x30 -- it lands and
  bounces through Zora52's item code); the ripple sprite (sprite_E 0x80,
  timer 0x1F, DrawMultiple 0x080F7C9C). What is thrown and lands on deep
  water drowns (the ground check 0x080C7DF0: state 3, timer 0x0F) instead
  of breaking. All tables / timers / speeds / message / receipt read at
  import through the code's literals and opcodes (refused otherwise).
  OURS: no splash sprites, sounds or BG shake; the second visit's gift
  (Quake owned) is message only.
- [x] 79.2 **Port fix: the throw (new `Throw79.lua`, EXTRA `throw79`).**
  Carry.lua threw at 4 px a frame with a made-up fall: ~42 px, the
  cartridge's ~68. CarriedSprite_CheckForThrow (0x080C32B0..): x / y / z
  speeds from the tables at the literals 0x080C331E / 0x080C332C /
  0x080C3334 by facing (-62 / 63, z 4); ThrownSprite_TileAndSpriteInteraction
  (0x080C7BC0): MoveXyz in 1/16 px, z speed - 2 (0x080C7C1C), landing once
  z - 1 >= 0xF0 (0x080C7C2E); the carried spot y + 1 + bob (0x080C82C4), z
  the lift table's last step (0x080C8292), the probe Sprite point 0x68/2
  (0x080C7BC6). In flight the cartridge tests no walls (only the pit type
  and sprite damage), so outdoors the object now flies over walls and the
  catfish's ring of posts; indoors Carry.lua's wall test is kept (OURS).
- [x] 79.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  from `ck_r78_bcrys6`: 01 down the Mire's plaza, the mirror -> LW 0x30, the
  flute to spot 5 (0x2F) (`c02f5`); 02 the west peg hammered, the light rock
  (3984,2928) lifted and thrown, the portal -> **DW 0x6F** (`c03dw`); 03 the
  north peg hammered out of the ring (`c04out`); 04 north to the PoD area
  (`c05pod`); 05 west / north round the Palace of Darkness (`c06w`) to the
  catfish's pond, 0x4F (`c06pond`); 06 the rock (3776,752) lifted from below,
  carried into the shallows (3743,697), thrown west into the ring: the
  catfish, its message, **the Quake medallion** (inventory 0x2A = 1)
  (`c07quake`); 07 the mirror -> LW 0x0F (`c08lw`); 08 the flute to
  Kakariko (`c09kak`). Health floor absorbed per leg: **0 / 0 / 0 / 0 / 16 /
  8 / 0 / 0 / 0** (Ravens 16 a hit at 0x6F, Hinox bombs, Moblins; real hp
  96 -> 16/96 at the pond). Magic 0 throughout. Not kept: farming 0x4F's
  bushes (the Zoras: ~200 absorbed), Kakariko farming (the bot's walker
  hangs at the second bush).
- [ ] Next: magic (>= 32 for Quake) and hp: farm / buy the green potion (60
  rupees, have 34); then the flute to Death Mountain, the DW warp, the mirror
  to Hera's plateau, east over the hammer bridge to the upper east DM, the
  portal under the heavy rock (secret 0x82 at 3152, 928 in area 0x05) ->
  DW 0x45 -> Turtle Rock (0x47, Quake). Somaria block carry / throw / push:
  the GBA's Ancilla2C main is 0x0811DCA8 (table 0x1717C4, type - 1),
  fizzle 0x0811F56C, fission 0x0811F2F8 -- traced to the entry only.

Real app (cache v69, widescreen ON, 1280 x 720, control mode 1): `real79a`
from `ck_r79_c06pond`: the throw (`real/shots/real79a_throw_win.png`), the
catfish out of the ring and its message (`real79a_cat3_win.png`), the Quake
medallion's receipt (`real79a_cat4_win.png`).

Tests: new `zelda_alttp_r79_test` (hooks, cacheVersion; Catfish79 and
Throw79 extracts on stand-in ROMs incl. refusals; the catfish's states on
stand-in tables: window, rumble / hold, emergence, one message, medallion
speeds, ripples, Quake-owned message, text box; drowning vs debris; the
throw's flight outdoors over a wall / indoors stopped; with the ROM: shapes;
38 checks). All 88 test files (`zelda_alttp_*` plus `zelda_input_test` and
`zelda_widescreen_test`) pass (`r79/out/alltests79.txt`). Audits 304/304
rooms, 80/80 overworld areas (`r79/out/audit/rooms_r79.txt`, `ow_r79.txt`).

## Round 80 (2026-11-21)

Link's walking collision outdoors now runs the cartridge's path (new
`Walk80.lua`); magic 128 with real input (bush rupees, the witch's green
potion); the route from Kakariko over Death Mountain to the Dark World's lower
east Death Mountain through the portal under the rock. Turtle Rock not
reached: the Superbunny cave's F8 block puzzle is not solved. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r80/` (the r79 kit with r80 paths;
checkpoints `ck_r80_*`; `chain80.sh`; `doc/round80.md`). **cacheVersion 70**
(new import data walk80): harness store re-imported (REIMPORT=1), real app
re-imported (`real/reimport.sh`, rom-cache v70).

- [x] 80.1 **Collision audit (Link vs tiles), port fix outdoors (new
  `Walk80.lua`; one-line hook in Link.update; Doors.lua's probes / diagonal
  points / masks read the import).** Traced: StartMovementCollisionChecks_Y
  (0x08094DC0) / _X (0x080962D0) run TileDetect_Movement_Y (0x0809EA40) /
  _X (0x0809EB58) in both worlds and only then branch on +0x9B2; the
  outdoor handlers (0x08094538 / 0x08095AD4) end in the same
  HandlePushingBonkingSnaps (0x080957E8) and FlagMovingIntoSlopes
  (0x08093B68 at 0x08094AE4) as indoors; Player_LimitDirections_Inner
  (0x0809380C) with TileDetect_Diagonal (0x0809EC40 / 0x0809ECF8) and the
  masks at 0x08167CFE is shared. The outdoor tile handlers (table
  0x0816872C via 0x080A05A8): walls 0x01-0x03, 0x26, 0x27, 0x42, 0x43,
  0x46, 0x50-0x5D, 0x63, 0x67, 0x70-0x7F, 0xC0-0xCF, 0xF0-0xFF; 0x10-0x13 /
  0x18-0x1B the diagonals (+0x978, no wall bit). Findings: **indoors**
  (Doors.lua, r12/r35/r60/r67/r77/r78) matches -- probes y + 8 / 24 at x +
  0 / 8 / 15 and x + 0 / 15 at y + 8 / 16 / 23, snaps, nudge, doorways,
  slopes, limit-directions; only its offsets were literals (now read).
  **Outdoors** (Link.lua, r2/r10/r11) did not: probes y + 23 going down and
  y + 15 mid-side (cartridge y + 24 / y + 16), x then y moved and tested
  separately, no LimitDirections (a diagonal along a wall slid at the
  diagonal speed, 1 px a frame, instead of the straight 1.5), walls
  approached pixel by pixel instead of the 8-px grid snap, its own corner
  nudge (exactly one outer probe), and every diagonal tile (~18,000 8-px
  cells of cliffs / Death Mountain) a wall. Now the overworld walk is
  Doors.move on the overworld attributes (walls = Overworld.SOLID, ledges
  block unless their hop starts, no doorway attributes: none occur on the
  overworld maps, histogram over both worlds): the same probes, the
  diagonal drop to straight speed, the snap, HandleNudging and the slopes.
  Import (EXTRA `walk80`): the four movement tables through the literals at
  0x0809EA60 / 0x0809EA8C / 0x0809EAA8 / 0x0809EAC4 (checked equal to
  _X's 0x0809EB78..), the three diagonal tables (0x0809EC5A.., checked equal
  to 0x0809ED14..) and the four mask bytes (0x0809395C); refused on other
  shapes. OURS / not traced: the ledge trigger and hop stay Link.lua's (the
  outdoor ledge search 0x08093128 / 0x080932C8); attribute 0x44's state
  test (+0x1649 / +0xAA8; walkable here), 0x4C-0x4F (ledge flags +0x1802 on
  the cartridge, walls here); the overworld door test is unchanged; Hop50's
  indoor ledge still uses Link.PROBES (y + 23). Door entering, deep water and
  NPC barriers are unchanged.
- [x] 80.2 **The farming walker:** r79's hang was B.owGo (200 re-plans x
  6000-frame follows on an unreachable bush). New `harness/farm80.lua`
  (columns of bushes, bounded walks, up / down modes, picks the drops) and
  `harness/plan80.lua` (bounded B.owGo: 30 re-plans, 1500-frame follows,
  gives up after 6 without progress; OWP80=1: the planner with the r80
  walking box and diagonal corners). Findings: outdoor bushes never hide
  magic (the overworld secrets have no 0x0C / 0x0D; the substitution table
  gives green rupees, a soldier, a bee) -- magic comes from enemies, pots
  or potions; cut bushes never grow back in the port (data.mapPatch is
  never cleared; the cartridge reloads the area's map) -- NOT PORTED. Real
  input: Kakariko's bushes x 5 passes with the flute to the witch's hut
  and back between them (34 -> 60 rupees), the green potion bought and
  drunk (magic 0 -> 128); a fairy from a DW bush on Death Mountain (hp 16 ->
  72).
- [x] 80.3 **Route (harness from checkpoints, HPFLOOR=16):** `chain80.sh`
  from `ck_r79_c09kak`: 01-03 Kakariko farming (`k1`..`k3`, then
  `k4`/`k5`), 04 the potion shop (`green`, magic 128), 05 the flute to DM,
  the warp (`dw43`), 06 the mirror -> Spectacle Rock, Hera's door in and
  out (`hera`), 07 east over the upper bridge, its two pegs hammered
  (`updm`), 08 the Paradox cave from the top (room DF stairs -> EF) ->
  lower east DM (`lowdm`; the flute does not answer on DM; the summit's
  rock pile (map16 0x226-0x229) smashed with the boots hides nothing in the
  LW), 09 the rock 0x53 at (3152,928) lifted with the Titan's Mitt (secret
  0x82: the portal) -> DW 0x45 (`dw45`), 10 to the Superbunny cave's door
  (`sbdoor`). Health floor absorbed per leg (01, 02, 03, the two extra
  farming passes, 04 .. 10): **16 / 12 / 12 / 12 / 12 / 0 / 12 / 0 / 0 / 0 /
  0 / 0** (soldiers from Kakariko's bushes, at hp 16; a Deadrock on DM); the
  Paradox cave leg took real damage (hp 64 -> 36) with no floor. Inside
  the cave (not kept): E8's west column -> its pit -> F8's column; F8's two
  push blocks (120,72) / (136,80) move once each and every order tried
  shuts the band to the stairs (296,32) -> E8's exit (entrance 20, the DW
  upper east DM, where Turtle Rock's plateau is reachable: owmap52 from
  (3440,240)). Quake's medallion effect and the Turtle Rock trigger are
  ported (OwEvents.lua, r27A).
- [ ] Next: F8's blocks (check the 0x04 cells right of B at (152,88) and
  the GBA's push rules for these 0x71 / 0x72 blocks), E8's exit -> DW upper
  east DM -> TR (0x47, Quake at the trigger), the Somaria block carry /
  throw / push (0x0811DCA8 / 0x0811F56C / 0x0811F2F8) when TR needs it;
  bush regrowth on area change.

Real app (cache v70, widescreen ON, 1280 x 720, control mode 1): `real80a`
from `ck_r80_lowdm`: the rock lifted, the portal under it
(`real/shots/real80a_portal_win.png`), DW 0x45 (`real80a_dw_win.png`);
`real80c` from `ck_r80_hera`: the bridge's pegs hammered
(`real80c_pegs_win.png`), the upper east DM (`real80c_updm_win.png`).

Tests: new `zelda_alttp_r80_test` (hooks; cacheVersion; Walk80's extract on
stand-in ROMs incl. refusals; the walk on a stand-in world with stand-in
offsets: snaps down / up / right, the diagonal along a wall at the straight
speed, the corner slide, other Links and old caches left to Link.lua; with
the ROM: shapes; 28 checks). `zelda_alttp_walls_test`'s overworld check now
lets a probe rest on a diagonal (0x10-0x13 / 0x18-0x1B). All 89 test files
(`zelda_alttp_*` plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r80/out/alltests80.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r80/out/audit/rooms_r80.txt`, `ow_r80.txt`), cacheVersion 70.

## Round 81 (2026-11-21)

The Superbunny cave solved (the port's push blocks already matched the
cartridge: the route goes round through the other floor), the Light World's
Turtle Rock peg puzzle ported, Quake at the trigger, Turtle Rock entered and
its first two Somaria rooms crossed (a pit-timing fix lets Link board the
platform). Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r81/` (the
r80 kit with r81 paths; `chain81.sh` legs 11-17, final run `ck_r81_f*`;
new BFS walker `harness/bfs81.lua`; `doc/round81.md`). **cacheVersion 71**
(new import data peg81): harness store re-imported (REIMPORT=1), real app
re-imported (`real/reimport.sh`).

- [x] 81.1 **Superbunny cave F8: the port matches the cartridge.** Push
  attempt (GBA 0x0809F3EC, from the push init 0x080AF71C): two points ahead
  of the block (x + 4 / 12 at y - 4 up, y + 20 down; x - 4 / x + 20 at y + 4
  / 12 sideways; tables 0x08168238..0x08168250), each through 0x080A0610:
  the attribute's class in 0x08168B2C must be 0, or the attribute 9 -- the
  same set as RoomObjects.FREE (0x04 is class 2: it stops a block). The map
  position moves 16 px (state 1: +0x199C += 0x081532F6[dir], -256 / 256 /
  -4 / 4); the slide sprite stops at a 16-px boundary; the landing
  (0x0808373C) sets the state to 0xFFFF: once per room load, as ours.
  Link's indoor handler for 0x04 is the wall handler (table 0x0816832C).
  The way through: fall from E8's column pit into F8's column, push block A
  (120,72) UP, walk up-left into the band's west half (rows 9-10 are left
  free), F8's stairs (72,32) -> E8's top band -> its pit -> F8's band east
  of the blocks -> stairs (296,32) -> E8's east room -> its pit -> F8's chest
  corridor -> stairs (248,144) -> E8's middle stairs -> E8's door (DW 0x45
  upper). No code change.
- [x] 81.2 **Port: the Turtle Rock peg puzzle (new `Peg81.lua`, EXTRA
  `peg81`).** HandlePegPuzzles (GBA 0x0808D3EC, called by the hammer's peg
  change): screen 7 (`cmp r0, #7` 0x0808D3F6), nothing once the event bit
  (0x20, 0x0808D3FE) is set; counter +0xB70 against the positions table
  (literal at 0x0808D420; count `cmp r4, #6` 0x0808D432); a wrong peg ->
  0xFFFF and sound 0x40 until the area's reload (counter zeroed by overworld
  submodules 6 / 0x14 at 0x080744EC), a right one sound 0x47, the last one
  sound 0x7B, the event bit and submodule 0x2F, whose step 0 (0x08073594)
  flips the world bit: Link is carried to the Dark World at his spot (the
  top of Turtle Rock). All values read at import, refused on other shapes.
  OURS: the crossing is the port's warp-tile crossing (DarkWorld.start
  "tile"), not submodule 0x2F's own fade steps; the screen-0x62 22-peg branch
  (+0xC04 / +0xC0A) is not ported.
- [x] 81.3 **Port: bush regrowth (new `Regrow81.lua`, no ROM reads).** The
  cartridge rebuilds an area's map16 tilemap on every load; the port kept
  owTileChange's patches for good. Cells G:owTileChange writes (plus the big
  rock's / rock pile's other quarters G:owSetMap16 writes in the same frame)
  are dropped from data.mapPatch when another area, the other world, or the
  same area after a room is loaded (after the scroll / crossing); overlay
  patches (OwEvents, Castle44, Kiki46, Grate64, bombed walls, gates) are
  untouched; the peg counter is zeroed. The first area a game sees is not
  reloaded (the castle bush test lifts the bush before the first frame).
- [x] 81.4 **Port fix: the pit's one-frame delay (new `Pit81.lua`, no ROM
  reads).** The cartridge's LinkState_Default (0x0809D5CC; state table
  0x081680AC) moves Link, and its collision (0x0809407C) only hands him to
  the pit state; state 1 (0x0809AD6C) reads the four points again on the
  next frame BEFORE moving him (0x0809AEC4 -> `cmp r1, #0xF` 0x0809AF44).
  The sprites run in between, so the Somaria platform (Sprite_ED 0x08110914,
  contact 0x080C46EC: hit box 0x1B = x - 12, y - 12, 24 x 16 vs Link's x + 4,
  y + 8, 8 x 8) takes him first. The port fell in the same frame: room D6's
  track end sits two pit rows above the ledge and every boarding fell. Now
  the first frame over a pit only enters the state; later frames decide the
  fall / pull at the frame's first position.
- [x] 81.5 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain81.sh` from `ck_r80_sbdoor`: 11 the Superbunny cave (`sbexit`);
  12 the mirror -> LW, the BFS walker round to the heavy rock (3840,352),
  lifted / thrown, up into the turtle ring, the pegs east / north / west:
  carried onto Turtle Rock (`trtop`); 13 Quake at the trigger (3848,244):
  the entrance opens, magic 128 -> 96 (`trquake`); 14 off the shell's west
  ledge, into the mouth: **room D6** (`trin`); 15 a pot lifted, the cane at
  the track end, the platform ride north -> **C6** (`trc6`); 16 the cane on
  C6's south-east spur, the ride round the grid to the north-east ledge
  (`trc6n`); 17 the north doorway -> **B6** (`trb6`, latest). Health floor
  absorbed per leg: **0 / 4 / 0 / 0 / 0 / 4 / 0** (one earlier try of 17
  took ~100: at the floor the zero-damage hits from the Stalfos 0xA7 / the
  0x7C roller skip the blink; the final run took 0). hp 36 -> 16 (real
  damage, the Superbunny cave's sprites 0x26), magic 112 at B6.
- [ ] Next: hp (16/96: fairies / potions before going deeper), B6 onward
  (chain chomps, keys; C6's west locked door 0xF0 at (120,40)), the Somaria
  block carry / throw / push (0x0811DCA8 / 0x0811F56C / 0x0811F2F8) where a
  room needs it; the screen-0x62 peg field; the Hop50 indoor ledge point.

Real app (cache v71, widescreen ON, 1280 x 720, control mode 1): `real81a`
from `ck_r81_ctrtop`: Quake cast, Turtle Rock open
(`real/shots/real81a_tropen_win.png`); `real81b` from `ck_r81_ctrin`: the
Somaria platform ride in D6 (`real81b_s74_01_win.png`); `real81c` from
`ck_r81_lwrockb`: the pegs (`real81c_pegs_win.png`), the carry onto Turtle
Rock (`real81c_trtop_win.png`). The real app caught an install-guard clash
(G.peg81 = true shadowed the game's counter): the guards are now
G.*Installed and the counter game.pegCount81.

Tests: new `zelda_alttp_r81_test` (hooks; cacheVersion; Peg81's extract on
stand-in ROMs incl. refusals; the puzzle in order / out of order / reload /
other area / other world / no import; Regrow81's reload rules; Pit81's
delay, the fall at the frame's first position, the platform; with the ROM:
shapes; 45 checks). All 90 test files (`zelda_alttp_*` plus `zelda_input_test` and
`zelda_widescreen_test`) pass (`r81/out/alltests81.txt`).
Audits 304/304 rooms, 80/80 overworld areas (`r81/out/audit/rooms_r81.txt`,
`ow_r81.txt`), cacheVersion 71.

## Round 82 (2026-11-21)

Turtle Rock's first floor: health back from a fairy, the torch room solved
from the Somaria platform, the map and two keys, B6's south-west and the
door to the chain chomps' quadrant. Ported: the Somaria block's push /
launch / lift / carry / throw, riding the platform while using an item, a
zero-damage touch without the blink. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r82/` (the r81 kit with r82
paths; `chain82.sh` legs 18-25, checkpoints `ck_r82_*`; `doc/round82.md`).
**cacheVersion 72** (new import data somaria82): harness store re-imported
(REIMPORT=1), real app re-imported (`real/reimport.sh`, rom-cache v72).

- [x] 82.1 **Port: the Somaria block moved by Link (new `Somaria82.lua`,
  EXTRA `somaria82`).** SomariaBlock_HandlePlayerInteraction (GBA 0x0811E908):
  on the ground, touching it (Ancilla_CheckLinkCollision 0x080BF880, box 4)
  on its level, the d-pad pushes it at the push speed (table via lit
  0x0811EB58; right dir 3, left dir 2, down dir 0, up dir 1 -- the GBA's
  order, so a vertical push tests the tile on Link's side, kept), the tile
  test by that dir, the push sound every 8th step, drag state 0x81,
  link_speed_setting 0x12; running with the boots (link_dash_ctr != 0x40)
  launches it (the dash ends, sound, y / x / z speeds from the tables via
  lits 0x0811EAAE / 0x0811EABE / 0x0811EACE), gravity 2, landing when z is
  0 or above 0xFB, the next bounce from the z table, speeds halved, rest at
  the 4th landing. Ancilla_HandleLiftLogic (0x0811A234): box 0 and the
  facing rule (lit 0x0811A3C2), R lifts it: stages K 0..3 with the delays
  (lit 0x0811A3F0) at Link + kAncilla_Func3_X / Y (lits 0x0811A11A /
  0x0811A0F6), stage 3 z = 0x11 (0x0811A4C2), then carried at (Link x + 8,
  Link y - z + 0x12 + Func2_Y[steps]) (0x0811A158); the throw: dir = facing,
  z speed 0x18, y / x speeds (lits 0x0811A542 / 0x0811A550), gravity 2,
  two landings with halved speeds and the bounce z (lit 0x0811A6BC); a wall
  in the air: one bounce (0x0811E09C..0x0811E124 immediates). The fission's
  bullets only when the block is on screen (0x0811EDE0, called at
  0x0811F336) -- the port always spawned them. Everything read at import,
  refused on other shapes. OURS: Items27's switch / pit / platform / sprite
  tests are skipped while it is carried or in the air; Link's lift / throw
  poses are Carry.lua's; the wall tests use AncColl65's class table and
  probes; no pushing pose; the fission window is the 240 x 160 ancilla
  camera.
- [x] 82.2 **Finding: i-frames.** The port's G:hurtLink starts the 58-frame
  blink on every touch; with damage this matches the cartridge (0x0809DADE).
  But the cartridge's damage handler (0x0809DA4C) does nothing when
  link_give_damage is 0 (`cmp r3, #0` at 0x0809DA58): a 0-damage touch
  (kPlayerDamages classes 2 / 11, mail columns) knocks Link back with NO
  blink. The port blinked -- **fixed** (new `Hurt82.lua`, no ROM reads).
  r81's "zero-damage hits without the blink" at HPFLOOR were a harness
  artefact: ow52's floor cut the damage to 0 (blinked in the old port, would
  not now); ow52 now defers to pod49's floor (the full hit lands with its
  blink, then health is put back). The ~100 aid of r81's try was repeated
  real hits at ~1/58 frames on a bot standing in harm.
- [x] 82.3 **Port fix: riding the platform while using an item (new
  `Ride82.lua`, no ROM reads).** The cartridge gates only Link's velocity
  (`cmp r0, #2` at 0x0809792E) and walk animation (0x080970FC) on
  player_on_somaria_platform (+0x1783 = 2, set at 0x081109CC); the port
  took the platform's drag only in Doors.move, which an item use skips, so
  the platform stopped and let Link go, and the d-pad could not turn him.
  Now the pending drag is taken at the start of his room frame and the
  d-pad sets the facing (OURS: the facing write itself not traced). Room
  0xC7 (tag 0x33, RoomTag_TorchPuzzleDoor) is solvable: the fire rod from
  the platform lights the four torches beside the track.
- [x] 82.4 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain82.sh` from `ck_r81_ftrb6`: 18 B6 NE: the pot (magic jar), the
  room's fairy chased (`b6heal`, hp 16 -> 72); 19 C6: the cane at the NE
  junction, the ride to the east ledge (`c6east`); 20 C7: the platform at
  the stop (14,17), down / right / up the east loop, the four torches lit
  from the platform (fire rod, 4 shots), back to the stop, the shutter
  (128,48) -> B7 (`b7in`); 21 B7: the two spike rollers (0x5D / 0x5F, one
  phase, 224 frames) timed, key (144,80) and map (96,80) chests (`b7keys`);
  22 back down B7 (one roller hit), C7 (`c7back`); 23 C6: the ride from the
  east ledge to the north-west stop, the key door -> B6 SW (`b6sw`); 25 the
  blobs, the Pokey 0xC7 (its key), the key door north -> **B6 NW**
  (`b6nw`, latest: hp 48/96, magic 40, 0 keys). Health floor absorbed per
  leg: **0 / 0 / 0 / 0 / 0 / 0 / 0** (real damage: Stalfos on C6's NE ledge
  4, B7's roller 16, C6 4). Discarded tries: the planner through B7 (108
  aid), the chomps' quadrant at hp 48 (two chomp hits 24 each, then 64 aid).
- [ ] Next: B6 NW at full health (A7 has two fairies; potions: 5 rupees,
  one empty bottle): the chest (120,80) between the chain chomps (24 a
  touch), its key -> the north door (0x18) -> A6; then B1 (Somaria pipes,
  the big chest), Trinexx (A4); the Dark World 22-peg field; the Hop50
  indoor ledge point.

Real app (cache v72, widescreen ON, 1280 x 720, control mode 1): `real82a`
from `ck_r82_c6east`: the block pushed and lifted in C7
(`real/shots/real82a_carry_win.png`); `real82b`: the torch ride
(`real82b_torchride_win.png`) and B7 behind the opened shutter
(`real82b_b7_win.png`).

Tests: new `zelda_alttp_r82_test` (hooks; cacheVersion; Somaria82's extract
on stand-in ROMs incl. refusals; the push / launch / lift / throw / wall
bounce / screen test on stand-in rooms; Hurt82; Ride82; with the ROM:
shapes; 54 checks). Audits 304/304 rooms, 80/80 overworld areas
(`r82/out/audit/rooms_r82.txt`, `ow_r82.txt`), cacheVersion 72. All 91 test files (`zelda_alttp_*` plus `zelda_input_test` and `zelda_widescreen_test`) pass (`r82/out/alltests82.txt`).

## Round 83 (2026-11-21)

Turtle Rock's chain chomp room solved with real input (a ported room tag), the
first basement floor entered (the pipe rooms 0x15 / 0x14, the Mirror Shield
room 0x24 seen), Ride82's inferred facing traced and corrected. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r83/` (the r82 kit with r83
paths; `chain83.sh` legs 26-31, final run `chain83f.sh` -> `ck_r83f_*`;
`doc/round83.md`). **cacheVersion 73** (new import data chest83): harness
store re-imported (REIMPORT=1), real app re-imported (`real/reimport.sh`,
rom-cache v73).

- [x] 83.1 **Port: the push-block chest (new `Chest83.lua`, EXTRA
  `chest83`).** B6 (tag 0x3C) kept its key chest hidden for good: Chest70
  hid the chests of tags 0x27 / 0x29-0x32 / 0x3C / 0x3E but nothing revealed
  0x3C's. Traced: the tag routine table (0x08152AC4; the entry pointing at
  0x0807B6FC is the tag, read at import) -> 0x0807B6FC: `ldr =0xBBF`
  (dung_flag_movable_block_was_pushed), `cmp #0`, `bl`
  RoomTag_OperateChestReveal (0x0807A478) -- no other condition; the block's
  landing (0x0808373C) toggles +0xBBF (`eors` with 1 at 0x08083764: the
  port's inside.blockPushed, so a second push before the reveal turns it
  off). The reveal ends with `movs r0, #imm` / `bl 0x0812A324` (0x0807A6FC):
  its sound, now played for every chest reveal (the port's were silent).
  Tag and sound read at import, refused on other shapes.
- [x] 83.2 **Trace: Ride82's facing (new `Ride83.lua`, no ROM reads).**
  LinkState_Default (0x0809D5CC): while Link is busy the d-pad is not read
  (recoil +0x16F8 -> 0x08099D98; `b 0x0809D92E` past the read for +0x1809,
  +0x176D, +0x1808 & ~2, +0x1791 & 0x7F (item in hand), +0x178A (item
  position mode), +0x180C (lift), a sword swing (+0x176C <= 8 and +0x16E8 &
  0xA0 == 0x80)); otherwise a held direction becomes link_direction_last
  (+0x16CC, 0x0809D8F0); Link_HandleMovingAnimation_FullLongEntry
  (0x08096F30, called at 0x0809D95E) sets the facing (+0x16D5) from it: a
  vertical bit wins (down if 4 else up), else right if 1 else left
  (0x08096FC8..0x08097016). Nothing there tests +0x1783 (only the velocity
  0x0809792E and the animation 0x080970FC do). **Differs from Ride82:** it
  turned Link during an item use and kept a held facing on diagonals. Now:
  no turn while busy (toolUse / bowUse / hookUse / swing / recoil / lift /
  climb / receipt), vertical first otherwise; the drag is still taken every
  frame. r82's torch ride (leg 20) re-run: still solves C7.
- [x] 83.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain83.sh` from `ck_r82_b6sw`: 26 B6 SW's blobs / Pokey (key), C6 (the
  cane at the NW stop, the ride released at the NE junction 0xBC), B6 SE /
  NE, the pot, the room's fairy (`h1`: hp 48 -> 96, magic 128); 27 back:
  the Green Stalfos 0x7C lured (it only creeps while Link faces away) and
  killed on C6's NE floor, the ride to the NW stop, B6 SW again (blobs /
  Pokey), the key door -> B6 NW (`nw1`, hp 52); 28 the chain chomps
  (chseq83, timed on their lunge cycle): an arrow on the left crystal
  switch (pegs flip; ancilla class 0 for 0x67: arrows fly over raised
  pegs), the left block pushed right (Chest83: the chest appears), an arrow
  (pegs back), the chest (small key), the key-locked stairs north -> **room
  0x15** (`b1in`, 0 chomp hits); 29 0x15's lower floor, the Pokey burned
  with the fire rod (4 shots, 0 damage), the in-room stairs to the
  south-east ledge, the pipe 0xB1 through the whole pipe net to the west
  ledge, its pots (`b1left`); 30 the west door -> **room 0x14** (pipe
  maze over pits), the pipe at (50,17) -> the south-west ledge (`p14a`); 31
  its south door -> **room 0x24** (Mirror Shield big chest room, two
  Pokeys) and back (`p14b`, latest: hp 52/96, magic 0, 0 keys).
  Final run `chain83f.sh` (`ck_r83f_*`, `out/chain83f.txt`): health floor
  absorbed per leg **0 / 0 / 0 / 0 / 0 / 0** (real damage: leg 27 44 --
  Stalfos 0xA7 4 x 3, the Green Stalfos 16, the Pokey 16 -- the others
  none; the chomps 0 hits). Discarded tries: the walk back without the lure
  (C6's Green Stalfos 3-4 hits on the platform), greedy chomp dodgers (2
  hits each), a first chomp plan that waited where the lunges end. The
  first trip to the fairy and back is a wash for health (48 -> 96 -> 52).
- [ ] Next: hp 52 / magic 0 (pots in 0x15's north-east, room drops): room
  0x14's island chest (0x32 big key) -- find the pipe whose far end waits
  on the island (AF / AE there); 0x24's big chest (item 6) and its Pokeys
  (fire rod); then B2 / Trinexx (0xA4). The Dark World 22-peg field and the
  Hop50 indoor ledge point remain. Port gap seen: none new in 0x14 / 0x15.

Real app (cache v73, widescreen ON, 1280 x 720, control mode 1): `real83`
from `ck_r83_nw1`: the chomp room with the block pushed
(`real/shots/real83_pushed_win.png`), the revealed chest opened, key held
(`real83_keychest_win.png`), room 0x15 (`real83_b1_win.png`). The real run
took one chomp hit (24, no aid; the harness run none).

Tests: new `zelda_alttp_r83_test` (hooks / order; cacheVersion; Chest83's
extract on stand-in ROMs incl. 4 refusals; the reveal on a stand-in room:
no push / push / once / toggled off / other tag / no import / other tags'
reveal sound; Ride83's facing rule, busy cases, carry, stopped platform,
install; with the ROM: shapes; 37 checks). All 92 test files (`zelda_alttp_*`
plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r83/out/alltests83.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r83/out/audit/rooms_r83.txt`, `ow_r83.txt`), cacheVersion 73.

## Round 84 (2026-11-21)

Turtle Rock's first basement: the big key (room 0x14's island) and the
Mirror Shield (room 0x24's big chest) with real input, and the shield
branch of the sprite damage check ported: the laser eyes' beams stop on
the Mirror Shield. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r84/`
(the r83 kit with r84 paths; `chain84.sh` legs 32-39, final run
`out/chain84f.txt` -> `ck_r84f_*`; `doc/round84.md`). **cacheVersion 74**
(new import data shield84): harness store re-imported (REIMPORT=1), real
app re-imported (`real/reimport.sh`, rom-cache v74).

- [x] 84.1 **Port: the shield in Sprite_CheckDamageToLink (new
  `Shield84.lua`, EXTRA `shield84`).** Dungeons26.contact never looked at
  Link's shield. Traced: Sprite_CheckDamageToLink_same_layer (0x080C46EC,
  called by the layer test 0x080C500C and the beam at 0x0810418C): after
  the hit-box test, when +0x176C is 0 (read as the bunny, as Kiki46),
  +0x1791 bit 7 is clear (read as the cape, as the fireball's test), the
  sprite's flags5 (+0x11B2) has bit 0x20 (`movs r0, #0x20` 0x080C482A) and
  link_shield_type (0x0200233E) is not 0: sprite_state = 0 (gone, blocked
  or not); Link's facing (+0x16D5), through the table at 0x081720B8 while
  button_b_frames (+0x16EA) is set, against the table at 0x081720B4
  [sprite_D]: blocked -> the sound (`movs r1` 0x080C4878, pan 0x080CF0AC),
  the repulse spark (0x080C444C), then 0x95 (the laser beam) its own sound
  (0x080C4902), 0x9B turns round (speeds inverted, D ^ 1, alive), 0x1B the
  arrow deflection, 0x0C broken and the check answers true; else the
  damage as before. LaserEye_FireBeam (0x081042B4) gives the beam flags5
  0x20 only when link_shield_type equals `cmp r0, #imm` (0x081043A0): only
  the Mirror Shield, and only for beams fired after Link has it. Both
  tables, the bit, the level, the sounds and the four type numbers read at
  import (data.t.shield84); the extract refuses other shapes. OURS: the
  beam's sprite_D is never written (LaserEye_FireBeam / the spawn
  0x080C9AAC / 0x080CEB84 leave the slot's stale value): the port uses the
  eye's D; the spark is counted, not drawn; 0x1B's deflection not ported
  (gone); only the dungeon check is wrapped. Verified: room 0x23's five
  eyes, Link facing up under them -- 12 beams blocked in 300 frames, no
  damage (harness), 7 in the real app.
- [x] 84.2 **Finding: room 0x14's pipes and room 0x24's shutters.**
  pipesim84 rides every waiting pipe on copies: the island (big key chest
  0x32) is reached only from the west ledge (pipe 0xB0 at (104,388)) or the
  east ledge (0xB1 at (407,388)); the west ledge from room 0x13 (key door
  0xF0 on its east wall, the Pokey's key), 0x13 from 0x14's west column
  (pipe 0xAE at (444,192) from the NE corner). Room 0x24: its three
  shutters are door 0x38 (one-sided: 0x18 on the NW / NE side, a plain
  door on the other); the room's only tag is 1 (NW, 0x0807B850 ->
  RoomTag_QuadrantTrigger 0x0807B43C); the intra-room transition shuts
  every open 0x18 (0x0806D264 / OperateShutterDoors 0x080810AC, 12 slots
  incl. mirrors), so NE -> SE is shut once Link crosses from NW -- the
  port agrees with the cartridge. The big chest is reached from outside:
  room 0x23's bombable south wall (door 0x2A) -> the Dark World ledge (area
  0x45) -> entrance 0x19 -> 0x24's south pocket -> the hookshot onto the
  chest across the pit. The pit's 0xB6 spot makes a Somaria platform
  (0xED) Link could not board from either side (not traced).
- [x] 84.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain84.sh` from `ck_r83f_p14b`: 32 0x14 SW ledge -> pipe -> NE, 0x15:
  pipe to the SE ledge, stairs, the NE pot ledge (5 pots: heart, magic),
  the SE ledge pipe, the west ledge pots -> 0x14 NE (`ne`, hp 60, magic
  32); 33 the pipe to the west column, the west door -> **0x13** (`in13`);
  34 0x13: an arrow on the crystal switch (av84: off the antifairies), the
  two Green Stalfos fought facing them (face84), the Pokey (sword; its
  key), the key door -> 0x14 west ledge, the pipe to the island, **the big
  key** (`bk`); 35 the island's south pipe -> 0x14 east ledge -> 0x15 SW
  ledge -> the pipe to 0x15's middle island (pot: magic 128), the hop
  down, the NE pots again, the SE ledge pipe, the west ledge pots, 0x14 NE,
  the pipe to the SW ledge, the south door -> **0x24** (`in24`); 36 the two
  Pokeys burned (fire rod), the shutter south, the west door -> **0x23**
  (`in23`); 37 a pot lifted under the eyes, bombs on the south wall -> the
  ledge (`ledge`); 38 entrance 0x19, the hookshot, **the Mirror Shield**
  (`mirror`); 39 the pit (back to the pocket), out, entrance 0x15 ->
  0x23: the lasers on the shield (`lasers`, latest: hp 16/96, magic 24,
  0 keys). Health floor absorbed per leg **0 / 0 / 4 / 0 / 16 / 40 / 0 /
  8** (68; real damage 34: Stalfos / Pokey / laser 48, 36: fireballs from
  the statues 24, 37: three laser hits 48 before the shield, 39: the pit
  8). Leg 37's 40 is the largest (the laser room without the shield at hp
  24). Discarded tries: the lure/GF61 fights in 0x13 (148 / 132 aid), the
  NE -> SE shutter in 0x24 (shut, see 84.2).
- [ ] Next: hp 16 / 96 (fairy or potions first: 24 rupees); from the
  ledge, entrance 0x18 (3360,448 DW) / 0x13 / 0x14 / 0x3A -- the eye bridge
  and B2 (dark rooms, the laser bridge 0xD5) to Trinexx (0xA4); the bunny
  beam 0xD1 still does not turn Link into a bunny (game.tempBunny unused);
  the 0xB6 platform in 0x24's pit; the Dark World 22-peg field; the Hop50
  indoor ledge point.

Real app (cache v74, widescreen ON, 1280 x 720, control mode 1): `real84a`
from `ck_r84_r84mirror`: the opened big chest, Mirror Shield held
(`real/shots/real84a_mirror_win.png`), room 0x23 facing the eyes with the
shield, 7 beams blocked, no damage (`real84a_block1_win.png`,
`real84a_block2_win.png`).

Tests: new `zelda_alttp_r84_test` (hooks; cacheVersion; Shield84's
extract on stand-in ROMs incl. 6 refusals; the check on stand-ins: no
flag, blocked beam (gone, two sounds, spark), wrong side (gone, hurt), no
shield, bunny, cape, sword-out remap, a type's default flag, the stone
(true), the turning type, no contact, harmless, ledge hop, no import; the
beam's flag at firing; the install; with the ROM: shapes; 41 checks). All
93 test files (`zelda_alttp_*` plus `zelda_input_test` and
`zelda_widescreen_test`) pass (`r84/out/alltests84.txt`). Audits 304/304
rooms, 80/80 overworld areas (`r84/out/audit/rooms_r84.txt`, `ow_r84.txt`),
cacheVersion 74.

## Round 85 (2026-11-21)

Turtle Rock from the laser room 0x23 down to B2: the big key door, the
Crystaroller room 0x04 (key, key-blocked stairs), the dark maze B5 on the
Somaria platform, the laser walkway C5, the eye bridge D5 (small key) and
the final peg room C4 entered, all with real input; the fireball's own
shield test ported (the Medusa statues' fireballs stop on the shield).
Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r85/` (the r84 kit
with r85 paths; `chain85.sh` legs 40-48, final run `out/chain85f.txt` ->
`ck_r85f_*`; `doc/round85.md`). **cacheVersion 75** (new import data
fire85): harness store re-imported (REIMPORT=1), real app re-imported
(`real/reimport.sh`, rom-cache v75).

- [x] 85.1 **Port: the fireball's shield test indoors (new `Fire85.lua`,
  EXTRA `fire85`).** Room 0x24's Medusa statue (0xC5) hit Link with every
  fireball whatever shield he held: OwEnemies27 ported the Zora
  fireball's shield test outdoors, DesertPalace.lua's indoor fireball
  (the same routine) had none. Traced: Sprite_SpawnFireball (0x080E89E4)
  gives 0x55 sprite_E / flags4 from `movs r1, #imm` (0x080E8A6A) and
  flags5 0 (so Shield84's branch never sees it); the fireball
  (0x080E8334): contact (0x080C4F98), move, the indoor tile check, then
  +0x176C / +0x180D zero, +0x1791 bit 7 clear, link_shield_type above the
  immediate of `cmp r0, #1` (0x080E83FC, `bhi`: the Red Shield or
  better), Link's level = the sprite's (+0x10F2), Link's box by facing >> 1
  (remapped while button_b_frames, table `ldr` 0x080E8430; x lo / hi, y,
  w, h tables at 0x080E8446 / 50 / 6C / 86 / A0), overlap (0x080C466C)
  -> repulse spark (0x080C444C), gone, sound (`movs r1` 0x080E84C8). All
  read at import (data.t.fire85), refused on other shapes. OURS: the
  spark is counted (Shield84's spark84), not drawn. Verified: harness
  14 fireballs blocked in the 0x24 fight (fb85 guard, 5 hit), real app
  7 blocked.
- [x] 85.2 **Traces (no port change).** The bunny beam 0xD1
  (Sprite_D1_BunnyBeam 0x080DC478, from the sprite table 0x08174138):
  ai 0 waits while the tile check answers a wall, 128 frames, bump 0x30,
  a touch sets +0x188C (link_timer_tempbunny) = 0x100, a wall kills it
  (poof, sound). The port's Traps27 / Hooks28 do this (r84's "unused"
  was wrong): room 0x24's beam sits on the pot at (192, 192) and dies on
  its first step, room 0x13's on a wall, so no bunny on this route; the
  bunny frames are unit-tested. Sprite_CheckTileCollision's core
  (0x080C7014) has a third branch the port lacks: flags4 bit 7 clear and
  the room's two-layer collision (+0xB14) != 0 -> all four directions
  (0x080C7A80), not only the velocity's (next round). The un-boardable
  pit platform of r84 does not occur in B5: the 0xB6 under the landing
  takes Link (contact from y 88, pits partial from 74, Pit81's frame).
- [x] 85.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain85.sh` from `ck_r84f_lasers`: 40 0x23: pot 5 lifted (shield up
  to the eyes), the east door -> 0x24 SW (`in24sw`); 41 SW -> NW, the
  Pokeys (sword) with the fireball guard (fb85), NE past the roller, the
  big key door -> 0x14's SE pocket (`in14se`); 42 the pipe -> 0x14 NW,
  north door -> **0x04** (`in04`); 43 the Pokey, a bomb on the cracked
  door 0x28 (Zoro spawner behind it: waited out), -> NW (`in04nw`); 44 the
  peg ring: arrow on the switch (roller timed), the chest (small key),
  second arrow, the key-blocked stairs 0x22 -> **B5** (`inB5`); 45 B5
  (dark): the cane's block on the 0xB6 under the landing, three platform
  rides (rd85: keys at the T junctions; crosses 0xBD go straight), the
  middle box's pot (switch 0x88: the south shutter opens), the east box
  (two hearts, full magic), off onto the SW ledge -> **C5** (`inC5`); 46
  the walkway (0x13), the dog-leg -> **D5** (`inD5`); 47 the Hardhat
  Beetle slashed off the bridge, the west alcove's chest (small key), the
  west eye's beams blocked twice on the way back -> C5 (`inC5b`); 48 the
  key door -> **C4** (`inC4`, latest: hp 16/96, magic 128, 0 keys, 27
  arrows, 5 bombs). Health floor absorbed per leg **0 / 48 / 16 / 24 / 0 /
  16 / 0 / 4 / 12** (120; 41: fireballs 5 x 8 + roller, 42: the 0x04
  Pokey at the door, 43: Pokey 16 + Zoros, 45: the firebar twice, 48:
  the Mini Helmasaur). No large single aid, but Link stays at the floor
  the whole round: **goal 1 (refill) not met** -- the balcony is an
  island (mirror -> LW Mimic Cave ledge only; the fairies of room 0x10C are
  the hookshot-fairy side; the flute does not answer on Death Mountain),
  pots on the way gave 3 hearts, eaten by later hits.
- [ ] **Blocker: Trinexx needs the Ice Rod** (grid slot 8 empty; receipt
  0x08 never taken): the fire head is hurt only after an Ice Rod hit
  (TurtleRock.lua). The Ice Rod cave is in the Light World; from TR the
  way out is D5's bombable south wall -> the DW eye-bridge ledge (entrance
  0x18) -> the mirror -> the LW Fairy Ascension ledge (cave 0x1B / 0x1A:
  room FD has two fairies) -> lower east DM, and back in via the TR
  portal / Superbunny cave / peg puzzle / main entrance (r80-r84 legs).
- [ ] Next: C4's peg grid (py85/c4bfs4.py: arrows at (448,360) down,
  (304,320) left, (248,264) down; the two Mini Helmasaurs pin Link --
  side / back hits or bombs), the stairs to B4, the big key door -> 0xA4.
  Then the Ice Rod detour (above). The Mirror Shield spark drawing, the
  arrow deflection (0x1B), the 22-peg field, the Hop50 indoor ledge point
  and the tile-collision branch remain.

Real app (cache v75, widescreen ON, 1280 x 720, control mode 1): `real85b`
0x24 fight from `ck_r85f_in24sw` (7 fireballs blocked; real-time runs take
more hits than the harness: aid 120 there), `real85c` the whole B5 leg
(platform rides, pot switch, east box, -> C5; aid 16 as in the harness,
`real/shots/real85c_real85c_b5ride_win.png`, `real85c_real85c_c5_win.png`),
`real85d` C5 -> C4 (`real85d_real85d_c4_win.png`).

Tests: new `zelda_alttp_r85_test` (hooks / order; cacheVersion; Fire85's
extract on stand-in ROMs incl. 6 refusals; the box by facing / sword out;
the test: blocked (gone, spark, sound, flags4 put back), behind, Red
Shield, first shield, bunny, cape, other level, sword out, no import, a
gone fireball; the install wrapper; the bunny beam's timer and Hooks28's
frames; with the ROM: shapes; 43 checks). All 94 test files
(`zelda_alttp_*` plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r85/out/alltests85.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r85/out/audit/rooms_r85.txt`, `ow_r85.txt`), cacheVersion 75.

## Round 86 (2026-11-21)

Out of Turtle Rock for the Ice Rod and back in, all with real input: D5's
bombable wall, the mirror to the Fairy Ascension ledge, the cave's fairies
(hp 16 -> 96), the flute to Lake Hylia's east bank, the bombed cave wall,
the Ice Rod; the flute to Turtle Rock's summit, the Paradox cave down, the
Fairy Ascension cave up (fairies again), the mirror portal back onto the
eye-bridge ledge, D5 -> C5 -> C4 (peg grid solved) -> B4 (Somaria track,
magic jar) -> A4. Trinexx: the fire head killed (Ice Rod + sword); the ice
head brought to 8/40 before the magic ran out. Port: Sprite_CheckTileCollision's
two-layer branch (new `Tile86.lua`). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r86/` (the r85 kit with r86
paths; `chain86.sh` legs 49-58, final run `out/chain86f.txt` ->
`ck_r86f_*`; `doc/round86.md`). cacheVersion stays 75 (no import change:
no re-import needed).

- [x] 86.1 **Port: the sprites' four-direction tile test in two-layer rooms
  (new `Tile86.lua`, hooked in Palace.lua's tileCollision).**
  Sprite_CheckTileCollision's core (0x080C7014): after the single-point
  branch (+0x1132 & 0x20), +0x1132 (sprite_flags4) bit 7 clear and the
  halfword +0xB14 (the header collision mode, dung_hdr_collision: compared
  with 0..4 across the code) not 0 -> 0x080C7A80: the vertical test
  0x080C7384 for down then up, the horizontal test 0x080C7278 for right
  then left, then 0x080C70E8 -- whatever the speed; else (0x080C7090) only
  the speed's directions (the port's old rule). Each test sets the wall bit
  and pushes one step (three while recoiling). Rooms with a non-zero mode
  (header byte 0 bits 2-4): 0x16, 0x1B, 0x29, 0x3E, 0x43, 0xDD. Verified:
  room 0x3E (7 sprites take the branch, 40 pushes in 600 frames), 0x16
  (163); real app 0x3E (57 pushes). OURS: the push's "& 7 <= 4" guard
  (0x080C73C0) is not modelled (as before).
- [x] 86.2 **Route facts.** The DW eye-bridge ledge (area 0x45, D5's south
  wall 0x2A) mirrors to the LW Fairy Ascension ledge (3352,472); entrance
  0x1B -> room ED's east column; its north spiral stairs <-> FD's fairy box
  (two fairies, two pots); ED's east pits drop into FD's corridor (two
  pots, the ledge hop west) -> FD's south door = entrance 0x1A's spot on
  lower east DM. From below: 0x1A (heavy rocks 0x53 in front, Titan's
  Mitt) -> FD's square room -> stairs -> FD west -> spiral stairs -> ED west
  -> the pit at the end of its north arm -> FD's fairy box -> stairs -> ED
  east -> the ledge, where the mirror portal waits (re-made on the exit,
  DarkWorld.lua) -> the DW ledge -> entrance 0x18 -> D5. The flute works on
  LW Death Mountain (spot 9, Turtle Rock's summit, is open). The Ice Rod
  cave: entrance 0x84 (3664,3136) behind a bombable overworld wall west of
  the Good Bee cave (0x56); room 0x120 SW -> NW, the chest box (receipt
  0x08). The plateau is reached from flute spot 8 by the dock stairs
  (3850,3768) and the east bank. Ice / Fire Rod cost 16 magic (the
  cartridge's kLinkItem_MagicCosts[0]).
- [x] 86.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain86.sh` from `ck_r85f_inC4`: 49 C4 -> C5 -> D5, the Hardhat Beetle,
  a bomb on the south wall -> DW ledge (`dwledge`); 50 the mirror, 0x1B,
  ED -> FD's fairies (hp 96), down the pit, the pots, the hop, out
  (`lowdm`); 51 the flute (spot 8), the dock stairs, the bombed wall, 0x84,
  **the Ice Rod** (`icerod`); 52 out, the flute (spot 9), Paradox cave down
  (`lowdm2`); 53 the heavy rocks, 0x1A (`inFD`); 54 FD -> ED west -> the pit
  -> the fairy box (hp 78 -> 96) -> ED east -> the portal -> 0x18 (`inD5b`);
  55 D5 north, C5 (the Mini Helmasaur waited out), -> C4 (`inC4`); 56 the
  peg grid: arrows at (444,360) down, (304,324) left, (244,264) down; both
  Mini Helmasaurs shot (one arrow each, hunt86) -> B4 (`inB4`); 57 the cane
  on the track's end, the two pots (heart, big magic jar: magic full), the
  ride -> A4 (`inA4`: hp 88/96, magic 128, 20 arrows, 3 bombs, 30 rupees);
  58 Trinexx (tri86 bot, `trinexx`). Health floor absorbed per leg **8 / 0
  / 0 / 0 / 0 / 0 / 0 / 0 / 0 / 368** -- legs 49-57 take real damage only
  (8 is the D5 laser at hp 16); **leg 58 (Trinexx) passes only with a large
  aid** (368: shell contact 8 a hit, the heads, flames).
- [ ] **Blocker: Trinexx's ice head.** The heads (hp 40) take only the
  sword while open (ai 4, 128 frames after a rod hit); the bot lands 2-3
  slashes per opening (the "is_many" throw-back of 32 px and the head's hit
  timer: ~54 frames a slash), so each head needs 4-5 openings; 128 magic =
  8 rod shots. The fire head died after 4 openings (10 slashes); the ice
  head reached 8/40 when the magic ran out (all 8 shots hit). Needs a
  magic potion (green potion 60 rupees, Link has 30 and two empty
  bottles), the Tempered Sword, or a tighter slash rhythm (first slash at
  the opening's first frames, standing out of the shell's x band). The
  spin attack did no damage in the bot's tries (not traced).
- [ ] Next: magic for the ice head (rupees -> green potion in a bottle),
  then the snake phase (untested), crystal 7. Also: the Mirror Shield /
  fireball spark drawing, the arrow deflection (0x1B), the 22-peg field,
  Hop50, sprite_state 11 (frozen sprites as ice blocks).

Real app (cache v75, widescreen ON, 1280 x 720, control mode 1): `real86a`
Trinexx from `ck_r86f_inA4` (the fire head killed with the Ice Rod and the
sword in 1800 frames: `real/shots/real86a_p04_A4_win.png`), `real86b` leg
51 (the flute, the bombed wall, the Ice Rod chest:
`real/shots/real86b_p06_120_win.png`), `real86c` room 0x3E (Tile86: 57
four-direction pushes, `real/shots/real86c_p05_3E_win.png`).

Tests: new `zelda_alttp_r86_test` (the hook's place in Palace.lua;
cacheVersion; no data in Tile86; the collision mode from header bytes;
flags4 per type / own / bit 7; single-layer rooms; the four tests' order,
wall bits, pushes, recoil; 23 checks). All 95 test files (`zelda_alttp_*`
plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r86/out/alltests86.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r86/out/audit/rooms_r86.txt`, `ow_r86.txt`), cacheVersion 75.

## Round 87 (2026-11-22)

Trinexx beaten with real input, crystal 7 taken. The harness run from
`ck_r86f_inA4` needs no aid (health floor absorbed 0; hp 88 -> 40, 8 rod
shots, heart container -> 104 max); the real app beats it too, with an aid
of 8. Two port fixes (the sword swing while recoiling, the snake's ai 2) and
a new Trinexx bot. Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r87/`
(the r86 kit with r87 paths; `chain87.sh` leg 59, final run
`out/chain87f_leg59.log` -> `ck_r87f_crys7`; `doc/round87.md`).
cacheVersion stays 75 (no import data: no re-import needed).

- [x] 87.1 **Check against the cartridge (no change needed).** The shell
  (Trinexx_HandleShellCollision): 8, recoil 32, incapacitated 16, no armour
  column -- the port matches. The heads: open 128 frames (ai 4) after a
  rod hit, the sword only then (defl bit 4 cleared in ai 4); the
  Master Sword's slash is class 2 (4 damage), the spin class 3 (8), the
  held sword class 1 (0: a tink); a sword hit blocks the next for 29 frames
  (hit timer 0x9D & 0x80) and throws Link back 32 ("is_many"). The rods cost
  16 (kLinkItem_MagicCosts[0]: 8 shots from 128). The rod hit's leftover
  sprite_give_damage (4) equals the slash's, so it changes nothing. The
  sword on a closed head already pushes at 32 (TurtleRock.install).
  Finding: most of r86's 368 aid was the rock head's own contact during
  its lunge (bump damage 24 with the Blue Mail), not the shell (8).
- [x] 87.2 **Port: the swing goes on while Link recoils (new `Sword87.lua`,
  EXTRA `sword87`, one call in Escape.lua's indoor recoil block).**
  LinkState_Default (0x0809D5CC) runs Link_HandleSwordCooldown
  (0x080A3D38, 0x0809D6A4) before the link_incapacitated_timer test
  (+0x16F8 at 0x0809D70E -> 0x08099D98); the port returned at the recoil
  first, so a swing that hit an is_many sprite froze for 16 frames and
  finished with Link standing still. Now the plain swing's steps and box run
  during the recoil. OURS: the held sword / spin are not stepped there, a
  new swing cannot start during a recoil, the overworld block is unchanged.
- [x] 87.3 **Port: the snake never enters ai 2 (TurtleRock.lua).** The port
  turned any hit on the snake's head in ai 0 into ai 2 (no case: it kept
  its speed and slid out of the room, y > 2000). Cartridge: a hit sets
  sprite_F 15 and nothing decrements it for the active snake (no
  Sprite_ReturnIfRecoiling in Sprite_Trinexx_FinalPhase), so the
  `cmp r0, #0xe` at 0x08108436 never passes; the GBA's ai jump table
  (0x0817C1EC) has only cases 0 and 1 (its third word is table data). The
  hit now sets sprite_F 15 and the snake keeps bouncing / homing.
- [x] 87.4 **Bot: `harness/tri87.lua`.** Every frame it simulates 9 moves
  over 72 frames against the shell box, the rock head's box (walk, wind-up,
  the 48-speed lunge aimed at Link's predicted spot), the heads (wider
  margin while their necks move), the fire breath and its flame trail, the
  snake's head (homing model) and body; hits within 20 frames are hard
  constraints, later ones soft. Keys into spike tiles (0x44: room A4's top
  corners) are dropped. Rods are fired from a wall-backed slashing spot
  (the left / right wall or the spikes behind Link block the 32-px recoil:
  4 slashes an opening instead of 2-3), else from below; no shot when the
  next lunge would start within 100 frames. The snake: its head while ai 0,
  then the flashing segment from a spot on the recorded path.
- [x] 87.5 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain87.sh` leg 59 from `ck_r86f_inA4`: Trinexx (openings fire head 3 /
  4 / 3 slashes, ice head 2 / 3 / 2 / 2 / 1; 8 rod shots, magic 128 -> 0),
  the snake (head, then the flashing segment), the heart container (max
  104), crystal 7 -> the Dark World ledge (area 0x45, `ck_r87f_crys7`:
  hp 104/104, magic 0, 30 rupees, crystals 127). Health floor absorbed
  **0** (real damage 48: the fire head's neck 24, the walking rock head 24). Tuning history: wall slashing and the
  lunge gate were needed; earlier sets left the ice head at 4-12 hp.
- [ ] Next: Ganon's Tower (7 crystals now: the DW Death Mountain top,
  entrance from the summit); magic / hearts first (the crystal refilled
  health, magic is 0). Open items as before: the Mirror Shield / fireball
  spark drawing, the arrow deflection (0x1B), the 22-peg field, Hop50,
  sprite_state 11 (frozen sprites as ice blocks).

Real app (cache v75, widescreen ON, 1280 x 720, control mode 1): the real
app (Game:update) does not replay the harness fight frame for frame, so
the bot was tuned there separately (`out/rsweep87*.txt`): `real87w` from
`ck_r86f_inA4` (TRI87H/EV 56, INV 6) beats Trinexx and takes crystal 7
(`ck_r87real_crys7`) with an aid of **8** (the same set without the
screenshot pauses: 40; other sets left the ice head at 4-8 hp). Shots:
`real/shots/real87w_tri87_wallhit_win.png` (a slash on the fire head with
the wall behind Link), `real87w_tri87_snake_win.png` (the snake phase),
`real87w_crys7out_win.png` (outside after crystal 7).

Tests: new `zelda_alttp_r87_test` (the hook's place in the recoil block,
EXTRA entry, no data in Sword87; the swing's steps, box, delays, end,
held / spin / no-swing cases; the install; TurtleRock's snake rule; 27
checks). All 96 test files (`zelda_alttp_*` plus `zelda_input_test` and
`zelda_widescreen_test`) pass (`r87/out/alltests87.txt`). Audits 304/304
rooms, 80/80 overworld areas (`r87/out/audit/rooms_r87.txt`, `ow_r87.txt`),
cacheVersion 75.

## Round 88 (2026-11-22)

Ganon's Tower opened and entered with real input: from crystal 7's ledge
back up to the Dark World Death Mountain top, the crystals' seal (ported:
new `Gt88.lua`, the entrance routine run at import), the tower's foyer
0x0C, Bob's torch (0x8C: the dash, the key) and room 0x8B. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r88/` (the r87 kit with r88
paths; `chain88.sh` legs 60-66, final run `out/chain88f.txt` ->
`ck_r88f_*`; `doc/round88.md`). **cacheVersion 76** (new import data
gt88): harness store re-imported (REIMPORT=1), real app re-imported
(`real/reimport.sh`, rom-cache v76).

- [x] 88.1 **Port: Ganon's Tower's seal (new `Gt88.lua`, EXTRA `gt88`).**
  The port had no trigger: the sealed doors stayed shut with 7 crystals.
  Traced: area 0x43's lists hold sprite 0x37 under the doors; its routine
  (0x0810BD5C, per-kind table 0x0817CBAC) on contact
  (Sprite_CheckDamageToLink_same_layer 0x080C500C) in the area of `cmp`
  0x0810BD82 calls AncillaAdd_GTCutscene (0x08124178): nothing when +0x1791
  bit 7 | +0x1702, crystals (0x0200235A) & mask != mask (0x0812419A /
  0x0812419E) or save_ow_event_info[area] & bit (0x081241A8); else ancilla
  0x43 (0x0812430C, type array +0xE15), the 0x37 sprites gone, Link held.
  The ancilla's last part counts 0x02006892 (immediate 0x08124270) to 0 ->
  trigger_special_entrance +0xB6E = 5 (0x08124568). Overworld_AnimateEntrance
  (0x0808F148, table 0x08153BF0[trigger - 1]) -> the tower's 13 steps
  (table 0x08153BBC by +0x9E8): three whitenings (0x08132B4C, sound, step
  counter +0xCF8), the event bit, then draw steps every 32-52 frames (two
  sounds, map16 tiles via 0x0808B8B8 / 0x0808B948 at area positions
  converted by 0x08092568), the end 0x0808D788 (sound, trigger 0). The
  import runs those steps in FrontRun's Thumb interpreter (draw / sound
  routines hooked) and keeps them frame by frame (data.t.gt88.seq: 616
  frames, 8 tiles); the opened entrance on a later visit is the last tile
  at each position, checked at import against the area's event overlay
  (Overworld_LoadEventOverlay 0x153C04[area], Castle44.runThumb): the same
  map8 words. All six immediates read at import, refused on other shapes.
  OURS: the crystals are not drawn (their rise / circle / close-in parts:
  the interpreter cannot run the ancilla without the overworld module's
  submodules), Link waits only the ancilla's last timer (240); the veil is
  white, timed by +0xCF8; the contact is tested every frame and harmless.
  Verified: harness and real app -- Link onto the trigger, held 240 + 616
  frames, the stairs drawn, entrance 0x37 -> room 0x0C.
- [x] 88.2 **Route facts.** From the TR eye-bridge ledge (crystal 7's exit,
  entrance 0x18): the mirror only from the ledge's portal spot (3352,472;
  from (3360,487) the LW spot bonks back), 0x1B -> ED / FD -> lower east DM
  (r86 leg 50), the heavy rock portal -> DW 0x45 (r80 leg 09), the
  Superbunny cave up (r81 leg 11) -> the DW Death Mountain top; west along
  y 208 / 120 to area 0x43 (the planner needs waypoints: G3250,272
  G2640,208 G2660,150 G2560,120 G2450,120 G2290,200). The trigger sprite
  sits at (2288,192). Room 0x0C: the entry box drops onto the foyer floor;
  the centre north door is shut (big key, not tried); the NW stairs ->
  0x8C's NW quarter. Bob's torch: the dash from (144,50) down; the Spark
  circling the torch cancels a dash it touches (timed: 60 frames after it
  passes below y 140); the key falls to (144,92). The west door is open ->
  0x8B's NE quarter (pits, 7 pots elsewhere in the room).
- [x] 88.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain88.sh` from `ck_r87f_crys7`: 60 the mirror, 0x1B, ED / FD (two
  pots: 5 rupees) -> lower east DM (`lowdm`); 61 the heavy rock, the
  portal (`dw45`); 62 the Superbunny cave's door (`sbdoor`); 63 the cave up
  (`sbexit`, hp 92); 64 west to the tower, the seal, entrance 0x37 ->
  0x0C (`gtin`); 65 the NW stairs -> 0x8C, two Stalfos (sword), the dash,
  the key (`bobkey`, hp 76); 66 the west door -> **0x8B** (`in8B`, latest:
  hp 64/104, magic 0, 1 key, 20 arrows, 4 bombs, 35 rupees). Health floor
  absorbed **0** on every leg (real damage 40: the Superbunny cave 12,
  Stalfos / Spark 16, a Stalfos at 0x8B's door 12). **Goal 1 (refill) not
  met**: magic still 0 -- the pots on the way gave rupees, 0x8B's pots
  are across pits from the NE quarter.
- [ ] Next: GT from 0x8B (its pots for magic, the hookshot over the pits,
  the chest under the firebar), the foyer's east stairs, the big key; the
  crystals' cutscene picture (ancilla 0x43). Open items as before: the
  Mirror Shield / fireball spark drawing, the arrow deflection (0x1B), the
  22-peg field, Hop50, sprite_state 11 (frozen sprites as ice blocks).
  Real app vs harness: the harness's DODGE input stops dashes; in the real
  app (control mode 1) a probe faking wasPressed("r") presses the item
  (the Mirror) -- dash88 now picks the mode's action button. The fight
  divergence itself was not traced this round.

Real app (cache v76, widescreen ON, 1280 x 720, control mode 1): `real88a`
from `ck_r88f_sbexit`: the walk west, the seal (the veil
`real/shots/real88a_gtflash_win.png`, the opened stairs
`real88a_gtopen_win.png`), entrance 0x37 -> 0x0C; `real88b` from
`ck_r88f_gtin`: 0x8C (Stalfos, the dash, the key falling
`real/shots/real88b_p14_8C_win.png`) -> 0x8B (`ck_r88real_in8B`: hp 76,
no aid).

Tests: new `zelda_alttp_r88_test` (hooks / order; cacheVersion; no number
tables, install guard; the extract on stand-in ROMs incl. 4 refusals;
finals and the veil; the run time: spot, start, hold, timer, event bit,
draws / sounds / map16 merge / veil, the end, a later visit, refusals
(crystals, world, area, cape, indoors, leaving); the install; with the
ROM: the run and shapes; 43 checks). All 97 test files (`zelda_alttp_*`
plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r88/out/alltests88.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r88/out/audit/rooms_r88.txt`, `ow_r88.txt`), cacheVersion 76.

## Round 89 (2026-11-22)

Ganon's Tower 1F, right side, with real input: 0x8B's key pot, back through
Bob's torch room to the foyer, the foyer's east stairs to the Hope room
(0x8C NE: both chests, the magic pot, the Cane of Somaria's block on the
switch to hold the shutter), into the tile room 0x8D (key chest, the Gibdo,
the full magic jar). The harness / real-app divergence traced to the kit,
not the port: harness replays now reproduce in the real app frame for
frame. No port change this round. Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r89/` (the r88 kit with r89
paths; `chain89.sh` legs 67-69, final run `CKPFX=r89f_` -> `ck_r89f_*`;
`real89.sh`; `doc/round89.md`). cacheVersion stays 76 (no import change:
no re-import needed).

- [x] 89.1 **Finding: why real-app fights did not replay the harness.**
  A per-frame trace (`harness/tr89.lua`: frame, RNG seed / calls, Link,
  every actor's x / y / ai / timers) of the same checkpoint and steps in
  both showed two kit differences and none in the game:
  (1) the real scene (`real/harness/scene_r38ck.lua`) ticked the
  checkpoint's game twice (`RH.wait(2)`) before the leg; the harness did
  not, so `g.frame` was 2 ahead; Drops.rng mixes the frame counter into
  every draw (`G:dropRng`), so the first sprite prep after the load (the
  Bari timers in 0x8D: 188 / 159 vs 164 / 147) and every later roll
  differed. With the same start frame the two runs were identical for 528
  frames. (2) Input: the harness's `H.run(n, keys)` held keys without a
  press edge and kept an unread `H.press` until some later frame; the
  real app (src/core/Input via the adapter's key events) makes a key
  that goes down a press on that step only, held on its step too. At
  frame 529 a held button started a dash in the real app and nothing in
  the harness. Fixes (kit): `CKWAIT=0` (realo.sh default) and the
  harness's `INPUT89=1` (t.sh default); realo.sh now loads the same legs
  as t.sh. Verified: 1084 traced frames identical (Link, health, RNG
  calls, all actors), a key door, the Gibdo spin fight and a Wallmaster
  grab included; legs 67-69 replay in the real app with the same results
  (the Gibdo: 8 spins in 1042 frames, 24 damage, both). Game:update,
  draw and the host's tick do not change game state (no RNG in draw).
- [x] 89.2 **Route facts (GT 1F).** Pot secrets: 0x0B heart, 0x0C small
  magic, 0x0D full magic, 8 key, 0x88 switch. 0x8B NE: the key pot
  (448,192) lifts only from its left (Link at 432,184); the NE quarter's
  west door is a shutter (tag 0x0C: the centre push block, boxed in by
  four other objects -- not solved); the SW / SE key door W8. The foyer's
  stairs land right below 0x8C's: holding up after the landing walks back
  down (UNTILu). 0x8C NE (Hope room): chests 3 bombs / 10 arrows; tag
  0x16 (HoldDoor): the switch under the pot (304,192) holds every shutter
  of the room open (the east one to 0x8D and the Bob's torch / big chest
  one) only while pressed; a Somaria block on it keeps them open; the
  block is gone once Link crosses into another quarter (the key door to
  Bob's torch room), so that shortcut closes. 0x8D: Bari, flying tiles,
  4-way shooters, a Wallmaster every ~510 frames at Link's spot (descends
  ~40 frames, 63 on the floor); the key chest (128,64); key door east;
  a Gibdo (hp 32: arrows 0, sword 4, spin 8, fire rod kills) in the
  32-px corridor, whose two pots block it (the second: full magic jar);
  the lane spike (0x8A, x 294..447 at y 255); tag 0x33 = torch door: four
  torches (NE top, the east strip, two in the SE) for the S8 shutter to
  0x9D, each lit 0xC0 * 4 frames.
- [x] 89.3 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain89.sh` from `ck_r88f_in8B`: 67 the key pot, back east, the two
  Stalfos, the NW stairs -> foyer (`foyer2`, keys 2); 68 the east stairs,
  the Hope room (chests, magic pot, switch pot, the cane's block) -> 0x8D
  (`in8D`); 69 the key chest, the key door, the Gibdo (spin attacks), the
  two corridor pots (magic 128) (`pot8D`, latest: room 0x8D, hp 40/104,
  magic 128, 2 keys, 30 arrows, 7 bombs, 35 rupees). Health floor absorbed
  **0** on every leg (real damage 24: the Gibdo). Real app (cache v76,
  widescreen ON, 1280 x 720, control mode 1): `real89.sh` legs 67-69 from
  `ck_r88real_in8B` -> `ck_r89real_pot8D` (hp 76 -> 52, magic 128), aid 0.
  Shots: `real/shots/real89a_p05_8B_win.png` (the key pot),
  `real89b_p18_8C_win.png` (the Somaria block on the Hope room switch,
  the east shutter open), `real89c_p08_8D_win.png` (0x8D after the Gibdo).
- [ ] Next: 0x8D's torch door (fire rod: four torches inside 768 frames;
  the lane spike and the Stalfos between), 0x9D / 0x9C, the big chest
  room (0x8C SW) and its stairs to 0x1C (big key, Armos Knights); the
  left side (0x8B's block puzzle, the map chest under the firebar). Open
  items as before: the crystals' picture in the seal cutscene (ancilla
  0x43), spark drawing, arrow deflection (0x1B), the 22-peg field, Hop50,
  sprite_state 11. Not checked against the cartridge: the Somaria block's
  end on a quarter crossing, the Wallmaster's vz (-66 after the -3 steps).

Tests: no new module (no new test file). All 97 test files (`zelda_alttp_*`
plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r89/out/alltests89.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r89/out/audit/rooms_r89.txt`, `ow_r89.txt`), cacheVersion 76.

## Round 90 (2026-11-23)

Ganon's Tower 1F with real input: 0x8D's torch door (all four torches lit
inside the 768 frames, the S8 shutter) into 0x9D (the compass room), and
0x9D's peg / crystal-switch puzzle (a Somaria block thrown over a rail onto
a conveyor that carries it into the switch). Two port gaps met on the way
and ported (new `Holes90.lua`, `Belt90.lua`). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r90/` (the r89 kit with r90
paths; `chain90.sh` legs 70-71, final run `CKPFX=r90f_` -> `ck_r90f_*`;
`real90.sh`; `doc/round90.md`). **cacheVersion 77** (new import data
holes90 / belt90): harness store re-imported (REIMPORT=1), real app
re-imported (`real/reimport.sh`).

- [x] 90.1 **Port: the chest-hole room tags 0x22 / 0x3B (new `Holes90.lua`,
  EXTRA `holes90`).** kDungTagroutines (0x08152AC4): 0x22 -> 0x0807B2D0,
  0x3B -> 0x0807B33C, the same shape: the room's save bits (+0xAA8) & 0x100
  (`movs` / `lsls` at +0x0C) -- kChestOpenMasks (0x081676F2)[0], the bit
  OpenChestForItem sets for the room's first chest -- then the overlay
  index +0xB62 (0x22: 0, 0x3B: `movs r0, #n` at 0x0807B358), sound, the
  overlay submodule (+0x9AD = 3) and the tag slot cleared. The bit stays,
  so the holes come back on every load. The port had no case: 0x9D's first
  chest (96,96) left the floor whole. Mask -> chest index and the overlay
  immediates are read at import (refused on other shapes); the overlay is
  Dungeons26.drawOverlay (0x9D: overlay 18, seven holes in the NW quarter;
  0x9D's hole warp is 0x7B). OURS: no sound, the overlay drawn in one frame.
- [x] 90.2 **Port: the Somaria block on a conveyor (new `Belt90.lua`, EXTRA
  `belt90`).** Ancilla2C_SomariaBlock on the ground: floor attribute
  0x68..0x6B (`cmp` 0x0811E1D8 / 0x0811E1DC) -> 0x0811B934
  (Ancilla_ApplyConveyor): y / x speed from the 4-byte tables at the
  literals 0x0811B952 / 0x0811B960 (1/16 px), Ancilla_MoveY / MoveX; the
  pit / water tests are skipped that frame. Items27 had it as "not
  ported". The tables and the attribute base are read at import. OURS: the
  move runs after the block's own frame.
- [x] 90.3 **Checks against the cartridge (no change needed).** Room tag
  0x33 (0x08079F04): the shutter follows "lit >= 4" every frame (+0xB10),
  so it shuts again when a torch goes out -- the port matches. The
  Wallmaster's descent (0x080FDFB4): z speed -= 3 while (zvel + 0x40) & 0x80
  == 0, so it ends at -66 -- the port matches (r89's open question). The
  Somaria block on a quarter crossing: the GBA has
  Ancilla_TerminateSelectInteractives (0x080AB73C: every ancilla but a
  carried one goes, the Somaria switch flag is cleared; 7 callers, one is
  0x0807166C which has 13); the port has no equivalent and nothing in its
  intra-room scroll removes ancillae. Which transitions reach it was not
  confirmed this round (open).
- [x] 90.4 **Route facts.** 0x8D: tag 0x33, four torches NE (448,64), the
  east strip (456,224), SE (448,400), the railed nook (304,432); the fire
  rod passes the 0x02 rails (ancilla class 0). Order that fits 768 frames:
  push the strip's block (440,168) right first; the NE torch from the
  corridor top (fired as the Wallmaster spawner fires: it then lands behind
  Link); the conveyor east, the strip torch fired down from (456,193); the
  spike lane behind the spike block (wait until it runs west below x 424);
  the SE torches from (336,396) right and (304,400) down; the S8 shutter
  from (376,466). The Wallmaster spawner fires every 510 frames at Link's
  spot (gen2 counts every other frame; the menu pauses it). 0x9D: three
  Gibdos (the fire rod one-shots when it lands), blue pegs (0x67) shut the
  lane's foot, orange (0x66) the left passage up to the NW door; the
  crystal switch (448,96) tops a 0x68 conveyor behind a 0x02 rail: a block
  made at the rail from (392,184) facing right, lifted, thrown right, rides
  up and toggles the pegs (it keeps touching the switch: a toggle every ~30
  frames). The NW quarter: four chests; chest 0 opens the holes (-> 0x7B).
- [x] 90.5 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain90.sh` 70 from `ck_r89f_in8D` (r89's leg 69 replayed first: a
  reload inside 0x8D brings the Gibdo back): the Stalfos (SK), the block,
  the four torches, the shutter -> 0x9D (`in9D`, hp 24); 71 the lane Gibdo,
  the Somaria block onto the belt, the pegs toggle (`belt9D`, latest: room
  0x9D at (392,184), hp 16/104, magic 40, 2 keys, 30 arrows, 7 bombs, 35
  rupees). Health floor absorbed **0** (real damage: the replayed r89
  Gibdo 24, the spike after the Stalfos 8, a fireball 8, the lane Gibdo 8).
- [ ] Next: 0x9D with the pegs cycling: west along the foot when blue is
  down, up the left when orange is down (two Gibdos there), the NW door
  (Link at y 120), the chests (compass), chest 0's holes -> 0x7B; hearts
  first (hp 16: 0x8D's SW pots hold hearts behind blocks, 0x8B 304,448,
  0x7B 240,64). The big chest room (0x8C SW) via 0x9C, its stairs -> 0x1C
  (big key, Armos). Open: TerminateSelectInteractives' callers; the
  crystals' picture (ancilla 0x43); the left side (0x8B block puzzle, map
  chest); spark drawing, arrow deflection (0x1B), the 22-peg field, Hop50,
  sprite_state 11.

Real app (cache v77, widescreen ON, 1280 x 720, control mode 1):
`real90.sh` legs 70-71 from `ck_r89real_in8D` -> `ck_r90real_in9D` (hp 36)
-> `ck_r90real_belt9D` (hp 28, the pegs toggled), aid 0. Shots:
`real/shots/real90a_p43_8D_win.png` (0x8D, the four torches lit, a
Wallmaster coming down), `real90b_p10_9D_win.png` (0x9D, the thrown block
on the belt), `real90b_p15_9D_win.png` (after the switch).

Tests: new `zelda_alttp_r90_test` (EXTRA entries / order, cacheVersion, no
number tables, install guards; both extracts on stand-in ROMs incl.
refusals; the tag frame: before / other chest / fired / once per load /
again after a load / slot 1 / other tags; the belt frame: directions,
carried / flying / hidden / other ancillae, the wrapper; with the ROM:
both extract; 34 checks). All 98 test files (`zelda_alttp_*` plus
`zelda_input_test` and `zelda_widescreen_test`) pass
(`r90/out/alltests90.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r90/out/audit/rooms_r90.txt`, `ow_r90.txt`; mains.txt carried over from
r89 for its hand-made guesses), cacheVersion 77.

## Round 91 (2026-11-23)

Ganon's Tower 1F, 0x9D finished with real input (the pegs cycling, both
Gibdos burnt, the magic pot, the two Hardhat Beetles, all four chests with
the compass, out of the chest-0 holes) and back up into 0x8D. Three port
gaps met on the way and ported (new `Burn91.lua`, `Fall91.lua`,
`Shutter91.lua`). Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r91/`
(the r90 kit with r91 paths; `chain91.sh` leg 72, final run `CKPFX=r91f_`
-> `ck_r91f_back8D`; `real91.sh`; `doc/round91.md`; new tokens in
`harness/tok91.lua`). cacheVersion stays 77 (the three modules read no ROM
data: no re-import).

- [x] 91.1 **Port: a burning sprite is not met by Link's ancillae (new
  `Burn91.lua`).** Ancilla_CheckSpriteCollision (loop 0x080C09FC) tests a
  sprite only while its state (+0xFA2) is above 8 (`cmp r0, #8` / `bls`
  0x080C0A58); the burn (Burn63: state 7) is below. The port's tool and
  arrow loops (Tools.spriteHit, Game:arrowFrame) skipped only dead sprites:
  a second Fire Rod shot burst on the first Gibdo's flames (16 magic lost).
  The burning sprites are hidden for the call and put back.
- [x] 91.2 **Port: a pit fall waits while the pegs move (new `Fall91.lua`).**
  The fall is Link's state run from submodule 0; a crystal switch hit sets
  submodule 0x16 (UpdatePegs), and the sprites' pause test reads the
  submodule (0x080C1B8C): nothing else runs. Fall52 ran the actors during
  the fall before Dungeons26's peg test, so in 0x9D (a Somaria block keeps
  touching the switch) the switch counter ran through the peg frames, a new
  toggle came every 15 frames and Link stood on the hole forever. Fall52's
  "falling" test is now false while the pegs move.
- [x] 91.3 **Port: a room tag does not shut the shutter Link is walking in
  through (new `Shutter91.lua`).** RoomTag_TorchPuzzleDoor (0x08079F04):
  down = lit <= 3, compared with +0xB10 (set by the transition's end after
  the walk-in) -> submodule 5 only on a change. The port's torch tag starts
  from no state and closed every open shutter on the first frame, the one
  Link stood in: back up from 0x9D into 0x8D (S8 torch door, torches out)
  Link was shut inside the door. closeShutters now leaves a shutter his
  body overlaps open as his entry (Escape closes it once he is past).
- [x] 91.4 **Checks against the cartridge.** 0x9D is in
  kDungeonPitsHurtPlayer: chest 0's holes (overlay 18) hurt and put Link
  back, they do not drop to 0x7B (r90's note was wrong); 0x9D's top half is
  a dead end (compass). A press during the peg update (Module07_16) is lost
  on both (no input read). Ancilla_TerminateSelectInteractives (0x080AB73C):
  its caller 0x0807166C is reached from the intra-room transition
  (submodule 1, sub-submodule table 0x0814CB54 entry 4 = 0x08070D28), so the
  Somaria block on the Hope room switch dies on a quarter crossing there too
  (r89's observation matches); the other 12 callers of 0x0807166C were not
  named and the routine was not ported (the port keeps a block for a few
  frames into the next room). The crystals' picture (ancilla 0x43) not done.
- [x] 91.5 **Route facts.** Fire Rod 16 magic; a Gibdo burns ~200 frames.
  0x9D: Gibdos burnt from the lane foot (386,177 / 386,168, shots left); the
  pegs: blue down (1) -> west along the foot, orange down (0) -> up the left
  passage; pot (336,64) small magic from (335,72) after holding up; the
  Gibdos' magic drops at (372,164); NW: Beetles by the sword (FM / spin),
  chests 144,160 / 96,160 / 144,96 / 96,96 (compass last), then the block
  (80,144) pushed left from (96,136), the pot (160,144) lifted from
  (160,152), the door at y 120. GT 1F graph (doors read from the rooms):
  0x8C SW (big chest, stairs -> 0x1C) <- 0x8C NW's bottom shutter (Hope
  switch held) or <- 0x9C's top door; 0x9C <- 0x9B's east door <- 0x8B SW's
  bottom door; 0x8B NE's west shutter (tag 0x0C, the centre block boxed by
  blue pegs: down at pegState 1, as leg 72 leaves it). Hearts: 0x8D SW pots
  (block puzzle under a firebar: 256-frame turn, wide), 0x8B 304,448, 0x7B
  240,64, 0x7C 112/128,64, 0x7D 448,96. A Wallmaster in 0x8D carries Link
  to the foyer 0x0C.
- [x] 91.6 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain91.sh` 72 from `ck_r90f_in9D` (r90's leg 71 replayed first): -> 0x8D
  (`back8D`, latest: room 0x8D at (376,441), hp 16/104, magic 40, 2 keys,
  30 arrows, 7 bombs, 56 rupees; pegState 1). Health floor absorbed **0**
  (real damage: the replayed r90 lane Gibdo 8). **Goal 1 (heal) not met**:
  no bottle potion (one empty bottle); the 0x8D SW hearts were reached in
  probes (full magic + one heart) but the firebar / Wallmaster / fireballs
  cost more than they gave -- not in the final leg.
- [ ] Next: from `back8D`: either the 0x8D SW hearts (FBPLAN timing from a
  spot out of the firebar's reach) or a Wallmaster ride to the foyer, then
  the foyer's NW stairs -> 0x8C NW -> 0x8B NE (the centre block with the
  pegs down) -> NW (hookshot over the pits; 0x7B hearts up the top door) ->
  SW -> 0x9B -> 0x9C -> 0x8C SW (big chest) -> 0x1C (big key, Armos).
  Open: TerminateSelectInteractives' other callers; ancilla 0x43's picture;
  spark drawing, arrow deflection (0x1B), the 22-peg field, Hop50,
  sprite_state 11.

Real app (cache v77, widescreen ON, 1280 x 720, control mode 1):
`real91.sh` leg 72 from `ck_r90real_in9D` -> `ck_r91real_back8D` (hp 28,
magic 40), aid 0. Shots: `real/shots/real91a_p13_9D_win.png` (the Gibdos
burning), `real91a_p44_9D_win.png` (the compass, the holes open),
`real91a_p74_8D_win.png` (back in 0x8D, the torch door shut behind Link).

Tests: new `zelda_alttp_r91_test` (EXTRA entries / order, no number
tables, install guards, empty extracts; Burn91 hide / restore / error /
wrappers; Fall91 with and without pegs; Shutter91 entry kept, others shut,
closed once clear, entry ways; 31 checks). All 99 test files
(`zelda_alttp_*` plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r91/out/alltests91.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r91/out/audit/rooms_r91.txt`, `ow_r91.txt`; mains.txt from r89),
cacheVersion 77.

## Round 92 (2026-11-23)

Ganon's Tower 1F with real input: out of 0x8D without a hit (the Stalfos,
the lane spike timed, the corridor's pots), through the NW quarter into
the Hope room, its stairs to the foyer, the NW stairs to Bob's torch room
(two Stalfos) and into 0x8B NE, where the hammer drives two of the four
pegs round the centre block and the block, pushed down, opens the west
shutter (r89's "not solved"). One port gap met and ported (new
`Wm92.lua`). **Goal 1 (heal) not met**: hp stays 16 (no damage taken this
round). Scratch: `G:/Gen2Recomped/scratch_claude/zelda/alttp/r92/` (the
r91 kit with r92 paths; `chain92.sh` legs 73-74, final run `CKPFX=r92f_`
-> `ck_r92f_foyer3`, `ck_r92f_push8B`; `real92.sh`; `doc/round92.md`;
new tokens in `harness/tok92.lua`). cacheVersion stays 77 (Wm92 reads no
ROM data: no re-import).

- [x] 92.1 **Port: the screen stays put while a Wallmaster carries Link
  off (new `Wm92.lua`).** Sprite_90_Wallmaster (0x080FDE80..): while it
  holds Link it writes his y (+0x16C0) = its y - z + 3 and sends him to
  the entrance when (y - +0x958 - 0x10) as an unsigned halfword is above
  0xFF (`cmp r1, #0xff` / `bls` at 0x080FDF34 -> 0x08092D18). +0x958 is the
  BG2 vertical scroll, moved by the dungeon camera only with Link's own
  walking; a held Link does not walk. The port's camera is computed from
  Link's position every frame, so where the camera area is 512 px high
  (0x8D's east side) it followed him up: he never left the screen, the
  Wallmaster flew off at z 256 and dropped him at the top of the room
  (probe: Link left at (379,69) in 0x8D). The grab now keeps the spot the
  camera is computed from until the hold ends (the send's new Interior
  drops it; a Wallmaster gone without a send clears it). Verified: the
  same probe now ends in the foyer 0x0C at (248,472).
- [x] 92.2 **Checks / findings.** A Wallmaster ride is a
  Dungeon_LoadEntrance: the pegs go back to 0 (Dungeons26's enterRoom) and
  pots_revealed is cleared -- so it was not used (0x8B's block needed the
  pegs at 1 by r91's reading; in fact it needs the hammer, see below). The
  four objects round 0x8B NE's centre block are hammer pegs (Manip71), not
  crystal pegs. The shutter's patch (296..319, 128..143) is cut off from
  the NE by pits and the hookshot block (attribute 0x27) at (320,128); the
  bridge over those pits is room tag 0x3A's overlay 17 (Dungeons26
  OVERLAY_TAG), switched by the star tiles 0x3B / 0x3A at (384,368) /
  (384,400) in 0x8B SE -- the left side's side of the room. 0x7D SE (from
  0x8D's top door): a warp tile (0x4B, 416,320) inside a rail (0x02) box.
  0x1C holds four fairies (0xE3) in its NW quarter. Out of the tower, the
  Superbunny cave's top door is a one-way ledge from the DW summit (no way
  back down found).
- [x] 92.3 **Route facts.** 0x8D SE -> passage without damage: draw the
  Wallmaster spawner's drop off first (it fires every 510 frames at Link's
  spot), wait at (376,284) until the lane spike runs east past x 358, up
  to the lane, west to (304,242), lift the corridor pot (304,232) and carry
  it up, throw it, lift the second pot (from 304,200), the passage west at
  y 124. The Hope room's spike block shuttles x 350..398 at y 127: the x
  320 lane down and the x 416 lane to the east door miss it. 0x8B NE: the
  Bari (FM), the hammer (MENU14) on the south peg from (384,154) facing up
  and on the north peg from (384,86) facing down, step into the north slot
  and push down. NOTE (checkpoint artefact): the first corridor pot gave
  its full magic jar (40 -> 128) because a checkpoint load starts a new
  pots_revealed; in one continuous visit r89 had already taken it.
- [x] 92.4 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain92.sh` 73 from `ck_r91f_back8D` -> foyer (`foyer3`); 74 the NW
  stairs, 0x8C NW, 0x8B NE, the pegs, the block (`push8B`, latest: room
  0x8B at (384,86), hp 16/104, magic 128, 2 keys, 30 arrows, 7 bombs, 56
  rupees, pegState 1, the west shutter open). Health floor absorbed **0**
  on both legs; no damage taken.
- [ ] Next: heal (hp 16): the 0x1C fairies are the nearest real heal but
  sit past the big chest room; 0x8B's left side (NW / SW / SE: the star
  tiles for the NE bridge, the crystal switches, the 0x8B SE heart pot)
  is reached from 0x7B (its bottom shutter), 0x7B from 0x7C, 0x7C from
  0x7D's SW / NW, whose way in is not found yet (0x7D SE's warp box,
  0x8B NE's bridge). Then 0x8B SW -> 0x9B -> 0x9C -> 0x8C SW (big chest)
  -> 0x1C (big key, Armos). Open: the crystals' picture (ancilla 0x43),
  TerminateSelectInteractives' other callers, spark drawing, arrow
  deflection (0x1B), the 22-peg field, Hop50, sprite_state 11; checkpoint
  loads do not keep pots_revealed (harness artefact).

Real app (cache v77, widescreen ON, 1280 x 720, control mode 1):
`real92.sh` legs 73-74 from `ck_r91real_back8D` -> `ck_r92real_foyer3`
-> `ck_r92real_push8B` (hp 28, magic 128, the shutter open), no hit, aid
0. Shots: `real/shots/real92a_p11_8D_win.png` (the corridor pot lifted at
the lane), `real92a_p36_8B_win.png` (0x8B NE on entry),
`real92a_p51_8B_win.png` (the block pushed, the west shutter open).

Tests: new `zelda_alttp_r92_test` (EXTRA entry / order, no number tables,
install guard, empty extract; camPos; the hold: grab, spot kept, send
pending, ended without a send, another Wallmaster; the install's wrappers
on stand-in Traps27 / Interior; 23 checks). All 100 test files (`zelda_alttp_*` plus `zelda_input_test` and
`zelda_widescreen_test`) pass (`r92/out/alltests92.txt`). Audits 304/304
rooms, 80/80 overworld areas (`r92/out/audit/rooms_r92.txt`, `ow_r92.txt`;
mains.txt from r89),
cacheVersion 77.

## Round 93 (2026-11-23)

Ganon's Tower 1F, the left side found and played with real input: 0x8B NE's
centre block hides a star tile -- its bridge leads through the west shutter
into the hookshot room (0x8B NW), then SW, 0x9B (crystal switches, key, trap
room), the 0x7D / 0x9B warp maze, 0x9C, the big chest room (0x8C SW) and
0x8C SE, whose cracked floor drops Link into 0x1C (the Armos room). One port
gap met and ported (new `Push93.lua`). Checkpoints now keep the palace
visit's pots_revealed bits (harness). Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/alttp/r93/` (the r92 kit with r93
paths; `chain93.sh` legs 75-88, final run `CKPFX=r93f_` -> `ck_r93f_*`;
`real93.sh`; `doc/round93.md`; new tokens in `harness/tok93.lua`; planners
`py/tplan.py`, `py/reach.py`). cacheVersion stays 77 (Push93 reads no ROM
data: no re-import).

- [x] 93.1 **How the cartridge reaches the left side (evidence).** Room 0x8B's
  header tags are 0x3A (slot 6: star tiles -> overlay 16 / 17) and 0x0C
  (slot 7: the push block opens the west shutter). The words kept under
  0x8B's only push block (384,128) are 0x31EE / 0x39EE / 0x35EE / 0x3DEE,
  whose tile attribute is 0x3B: a star tile. Overlay 17 (read at import)
  draws floor over (304,96) and (304,144) -- the pits between the shutter's
  patch and the NE conveyors -- and pits at four spots in 0x8B SE; overlay
  16 the reverse. So the route is: hammer two pegs, push the block, step on
  the star it uncovered, walk round the hookshot block on the new floor,
  through the shutter. The public walkthrough's order (hammer pegs, block,
  "star switch fills the holes", hookshot room, map room, crystal switch
  room, trap room, winder corridors, warp maze, secret passage room, big
  chest room; the big key from 0x1C reached by bombing a cracked floor)
  was checked room by room against the port's room data (doors, locks,
  warp destinations from header byte 9: 0x9B -> 0x7D, 0x7D -> 0x9B; the
  bomb floor objects in 0x8C SE; the push block of 0x8C SW's stairs nook).
  0x7D SE's rail box is entered by 0x9B's warp tile at (416,336) and left
  by its own at (416,320) (no hookshot or jump over the 0x02 rails needed).
- [x] 93.2 **Port: a push block leaves the attribute of what lay under it
  (new `Push93.lua`).** The push block's state 1 (0x080838C0 -> 0x08083AE4)
  draws the four kept words back and writes the room tile attribute table
  (0x02002E40) entry of the last word & 0x1FF to the block's four cells
  (0x08083974). RoomObjects.startPush wrote 0 (floor): 0x8B's star tile was
  lost and the bridge could never be drawn (r92's "cut off" patch). The
  wrapper runs after startPush (Interior.attributes, the grid from
  WALKABLE). Verified: stepping into the block's old spot draws overlay 17.
- [x] 93.3 **Checkpoints keep pots_revealed_in_room (harness).** pod49.lua's
  checkpoint stores `g.interior.revealed` and ck25.lua (also the real app's
  loader) puts it back on the new Interior (CKREVEAL=0 skips): a pot's drop
  is no longer given twice by a reload. Other per-room state: room memory
  was already in the save; the peg state in `peg`. Not kept: moved push
  blocks / drawn overlays (the cartridge redraws a room on every load too)
  and 0x9B's double switch toggle (below).
- [x] 93.4 **Route facts.** 0x8B NW: hookshot landings are the head's
  contact spot + the arrival offset (pits round the targets): west from x
  200 (pressing at 203), y 120; south from x 80; east from y 184; south
  from x 192; the SW skull from (128,253). 0x8B SW: the Stalfos (SK1 from
  146,330), a bomb by the crystal switch, the pegs (down at pegState 1) and
  the south door before it goes off -> 0x9B with pegState 0 (its entry
  pocket open). 0x9B NW: one bomb hits both switches (two toggles, one
  attribute flip: the blue pegs drop while pegState stays 0); key under
  the lower-right skull (192,192); the key door east. 0x9B NE: seven spike
  traps; along the top (y 48) to x 448, down at frame 255 after the load,
  the warp tile at y 120 (Warp48's alignment) -> 0x7D NE. 0x7D: four
  winders (frame 72), the block (224,144) pushed left reveals the tag-0x3C
  chest (112,128), hooked from x 187 (landing x 128): small key; the key
  door down; warps 0x7D (144,328) -> 0x9B, the two skulls, (96,392) ->
  0x7D, (40,448) -> 0x9B pit field, (416,336) -> 0x7D's rail box, (416,320)
  -> 0x9B east, its door -> 0x9C. 0x9C: the left catwalks, the leftmost
  passage, the north door -> 0x8C SW (big chest (112,376); the stairs nook
  is shut by a push block from this side: one-way from 0x1C). Back down,
  0x9C's rail crossed by the hookshot at (200,72) -> its NE door -> 0x8C SE:
  the pot (416,416) lifted from above (frees an anti-fairy: -16 magic), the
  chest (448,432), a bomb on the cracked floor (416..447,432..463), out
  before the blast, the fall -> 0x1C (Armos Knights).
- [x] 93.5 **Route, real input (harness from checkpoints, HPFLOOR=16):**
  `chain93.sh` 75 from `ck_r92f_in8B2` (r92's 0x8B NE leg replayed with the
  star tile) -> `nw8B`, 76 `isle8B`, 77 `sw8B`, 78 `in9B2`, 79 `ne9B`, 80
  `in7D`, 81 `chest7D`, 82 `sw7D`, 83 `w2_7D`, 84 `east9B`, 85 `in9C`, 86
  `in8C`, 87 `se8C`, 88 `in1C` (latest: room 0x1C at (398,448), hp 16/104,
  magic 88, 2 keys, 30 arrows, 5 bombs, 56 rupees). Health floor absorbed
  **8** (two Hardhat Beetle touches, 4 each: 0x9C's catwalk, 0x9C NE after
  the hookshot); every other hit was timed out of the route.
- [ ] Next: 0x1C: the six Armos Knights with hp 16 (the fairies are behind
  the cracked north wall, reached after the fight), the big key (north
  room), back up the 0x1C stairs into 0x8C SW (push the nook's block
  right), the big chest (red mail). Map chest (0x8B SE, two firebars) not
  taken. Open: 0x9B's double toggle (the cartridge's own order?), the
  crystals' picture (ancilla 0x43), TerminateSelectInteractives' other
  callers, spark drawing, arrow deflection (0x1B), the 22-peg field.

Real app (cache v77, widescreen ON, 1280 x 720, control mode 1):
`real93.sh` legs 75-88, leg by leg from the real app's own checkpoints,
`ck_r92real_in8B2` -> ... -> `ck_r93real_in1C` (hp 28 -> 20: the same two
beetle touches; aid 0, the floor was never reached). Shots:
`real/shots/real93_75_bridge_win.png` (Link on the uncovered star tile,
0x8B NE), `real93_80_traps_win.png` (0x9B's trap room from the top),
`real93_86_bigchest_win.png` (0x8C SW, the big chest room on entry),
`real93_88_armos_win.png` (0x1C after the fall, the Armos Knights).

Tests: new `zelda_alttp_r93_test` (EXTRA entry / order, no number tables,
install guard, empty extract; attrUnder: the fourth word, the 9-bit mask,
the aux table, missing data; afterStart: four cells, grid, floor left
alone, lower table, no move record; the install's wrapper; with the ROM:
the three routines start with push; 26 checks). All 101 test files
(`zelda_alttp_*` plus `zelda_input_test` and `zelda_widescreen_test`) pass
(`r93/out/alltests93.txt`). Audits 304/304 rooms, 80/80 overworld areas
(`r93/out/audit/rooms_r93.txt`, `ow_r93.txt`; mains.txt from r89),
cacheVersion 77.
