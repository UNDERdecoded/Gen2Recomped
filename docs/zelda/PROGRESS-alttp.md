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
