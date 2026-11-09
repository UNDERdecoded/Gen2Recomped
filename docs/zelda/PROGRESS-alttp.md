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

## Open issues

- Music id -> song mapping is a guess (399 + SNES id); needs the cartridge's
  translation table.
- `Data.load` holds the whole cache in memory (~3 MB); fine on desktop/phone.
- Audio reads `<prefix>assets/generated/audio/m4a.bin` through
  love.filesystem (the M4A worker's read path); a portable/custom data root
  relies on the foundation mounting the cache on the read path.

## Requests for other agents

- Foundation: `newGame(opts)` uses `opts.cache` (or `opts.root`), `opts.input`,
  `opts.save`, `opts.options.musicVol`; the game implements update/draw/save/
  quit and netSnapshot/netApply/netEvent/netPeerLeft/netAttached/netDetached.
  `extract` uses `ctx.bytes` and `ctx.checkpoint`. No new hooks needed now.
- Foundation (nice to have): call `ChipAudio.stopMusic()` is already done via
  `love.audio.stop()` on quit — fine. If the runtime ever ticks without
  `update`, music buffers still need `ChipAudio.update()`; the game calls it
  from its own update.
