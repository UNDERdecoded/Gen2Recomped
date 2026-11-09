# The Minish Cap (USA): how the port works and where it stands on parity

Module: `src/zelda/tmc/` (`init.lua` is the contract entry point). Progress
and open requests: `docs/zelda/PROGRESS-minishcap.md`.

The player imports their own cartridge (`BZME`, 16 MiB, SHA-1
`b4bd50e4131b027c334547b4524e2dbbd4227130`). Nothing from the cartridge is in
the repository: `Layout.lua` holds only addresses and structure sizes, the
importer reads everything else from the player's ROM into the cache.

The reference is the zeldaret/tmc decompilation (cloned read-only outside the
repo, never built). Below, "decomp" means that source.

## Files

| File | What it is |
|---|---|
| `Layout.lua` | USA addresses of every table root the importer follows, header detection |
| `Rom.lua` | bus-address reads on top of `src/import/RomGba.lua`; MapDataDefinition, Transition, EntityData readers |
| `Extract.lua` | the importer (resumable, idempotent) |
| `Store.lua` | cache I/O: the foundation's ZeldaCache (files under `data/generated/`) or an absolute folder (tests, harness) |
| `Assets.lua` | runtime loaders: palettes, metatile atlases, room maps, sprites, text |
| `Room.lua` | a room: layers, collision, exits |
| `Field.lua` | the game world: Link, entities, scripts, exits, camera, HUD, flags |
| `Player.lua` / `Anim.lua` | Link; the cartridge's keyframe animation player |
| `Script.lua` | the cartridge script interpreter |
| `RoomCode.lua` | hand ports of native per-room code |
| `TextBox.lua` | message windows over the cartridge's text |
| `Audio.lua` / `audio_worker.lua` | M4A music and SFX through `src/core/M4ASynth.lua` |
| `Kinstone.lua` / `Net.lua` | Kinstone rules and world events; online presence and fusion |
| `Objects.lua` | ground items, drops, chests, signs, lift/throw, cutting, item get, portals |
| `Items.lua` | the sword's tile probes and hitboxes, the Gust Jar |
| `Enemies.lua` | enemy definitions, the collision matrix, AI, death and drops |
| `Menu.lua` | the pause menu's ITEMS page |
| `Font.lua` / `Hud.lua` | the cartridge font; hearts and rupees from the cartridge's BG0 tiles |
| `Game.lua` | title, file select, the field, runtime hooks |

## ROM survey (how each root was found and checked)

Annotated in the decomp and confirmed by reading the ROM:
`gAreaRoomHeaders` `0x0811E214` (entry 0 -> `0x0811C488`, Minish Woods,
1008 px wide), `gAreaTileSets` `0x0810246C`, `gAreaRoomMaps` `0x08107988`,
`gAreaTiles` `0x0810309C`, `gAreaTable` `0x080D50FC`, `gMapData` `0x08324AE4`,
`gGlobalGfxAndPalettes` `0x085A2E80`, `gSpritePtrs` `0x080029B4`,
`gFrameObjLists` `0x082F3D74`, the text table `0x089B1D90`,
`gFixedTypeGfxData` `0x08132B30`.

Not annotated (C data), found by searching the ROM for the decomp's own
structure, each unique:
`gPaletteGroups` `0x080FF850` (a zero then 207 nearby pointers),
`gExitLists` `0x0813A7F0` (0x99 pointers, trailing NoExit run),
`gAreaMetadata` `0x08127D30` (first three AreaHeaders),
`gSongTable` `0x08A11DBC` (pointer to sfxNone's header),
`gNPCDefinitions` `0x08114AE4`, `gKinstoneWorldEvents` `0x080C9CBC`,
`SharedFusions` `0x080CA11C`, `gWorldEvents` `0x080FE320`,
the collision shape lookup `0x08133A67` and masks `0x08133918`,
the tileset-manager region/gfx tables (`0x08108050`, `0x08108398`...).
Collision tables come through the veneer's literal pool (`0x08000214..21C`).
`tests/zelda_tmc_rom_test.lua` re-checks several of these on every run.

## What matches the cartridge (and how it was checked)

- **Maps.** Rooms are built exactly like `LoadRoomTileSet`/`LoadRoomGfx`:
  `gAreaTileSets[area][tileSet_id]` MapDataDefinitions decompressed into a
  48 KiB BG VRAM image plus `LoadPaletteGroup`; `gAreaTiles` give 2048
  metatiles x 4 subtiles and tile types per layer; `gAreaRoomMaps` give the
  room's two layer maps. Bottom layer reads characters at char base 0, top at
  char base 1 (BG control `0x1C42` / `0x1D45`). Checked by rendering Hyrule
  Town, Minish Woods, Festival Town, Minish Village and Link's house to PNG.
- **Tileset managers** (Hyrule Town, Festival Town, Minish Village): the
  `CheckRegionsOnScreen` choice per slot and the same 0x1000-byte blocks into
  the same VRAM offsets; Minish Village's palette group per gfx group.
- **Collision** is `IsTileCollision` for collisionType 0: the quarter
  bitmask for values < 0x10, the cartridge's shape lookup and per-pixel masks
  for the rest, `gMapTileTypeToCollisionData` / special-tile table / a room's
  own collision map. Unit-tested on synthetic grids; the bedroom's walls and
  floor checked against the ROM.
- **Exits**: `IsPosInTransitionRect` (half extents 6x6, 6x14, 14x6, 22x6),
  `IsPosInBorderTransitionRegion` (north/east/south/west halves), end
  coordinates above `0x3FF` keep the world coordinate, `facing_direction` is
  the arrival animationState. Doors/stairs: pushing into an `ACT_TILE_40`
  (stairs) / `ACT_TILE_41` (door) tile with a warp beyond, as in the player's
  tile actions; a door with no warp leads to the adjacent room of the area
  (rooms tile the area map by `map_x/map_y`). Checked: bedroom -> stairs ->
  entrance -> door -> smithy.
- **Entities**: `LoadRoom` order (list [1], then [0], then enemies [2] only
  once `TABIDACHI` is set), `RegisterRoomEntity` placement rules, scripted
  entities when `flags & 0xF0 == 0x40`. NPC sprites/palettes from
  `gNPCDefinitions` (multi-form, swap vs fixed gfx, `LoadObjPalette` ids
  0-5 / BG copies / table).
- **Scripts**: the opcode format (index + length in halfwords), the
  `ExecuteScript` loop (flags bit 0 = continue, bit 1 = block, commandSize 0 =
  retry next frame), and handlers for every entry of `gScriptCommands`
  (0x00-0x8A), including sync flags, waits, jumps/tables, flags, inventory,
  messages, facing, walking, MoveTo/LookAt/MoveTowardsTarget, post-script
  actions and NPC animation choice (`sub_0807DE80`). Player scripts
  (`StartPlayerScript`) drive Link. Checked by disassembling ROM scripts
  (scratch tool) and running them: the Postman deletes himself without the
  Kinstone bag; the smithy prologue plays (Smith walks over, Link is walked
  in by his own script, "Princess Zelda is here..." appears).
- **Link**: `kWalkSpeed` 1.25 px/frame (measured 50 px in 40 frames), the
  cartridge's animation ids and keyframes, sprite frames assembled from the
  frame OAM lists (shape/size/flip/tile bits as `ram_DrawEntities` builds them).
- **Text**: the USA string table, the control codes `tmc_strings` documents.
- **New file**: `FinalizeSave` values (area `0x22` room `0x15`, (0x90, 0x38),
  24/24 health).
- **Kinstones**: fused set, piece/fusion shape matching from
  `gKinstoneWorldEvents`, `GetRandomSharedFusion` order.
- **Music**: songs by `gSongTable` header (tracks + voicegroup) through the
  Emerald port's M4A engine.

### Round 2 additions that follow the cartridge

- **Combat numbers** come from `gCollisionMtx` (`0x080B7B74`, 12-byte
  ColSettings at `[hitType * 34 + hurtType]`, as `asm/src/intr.s` indexes
  it): contact damage, knockback speed/duration and invulnerability for
  Link and for enemies hit by the Smith's Sword (hurt type 4). Enemy stats
  from `gEnemyDefinitions` (`0x080D2C58`), home ranges from `gUnk_080D3D94`.
- **Octorok** follows `src/enemy/octorok.c` (pause 24-80 frames, walk
  30/60/60/90, turn rules, spit when facing Link with the type's chance, the
  rock: speed 640, 48 frames).
- **Drops** follow `CreateRandomItemDrop` / `CreateItemDrop` with the
  cartridge's droptables (`0x0800137C`, `0x080015BC`), slot items
  (`0x080FE1B4`), area selection (`0x080FE1C6`), Kinstone piece table
  (`0x080FE1DD`) and `DeathFx_EnemyDroptables` (`0x0811EC64`).
- **Tiles**: `DoTileInteraction`'s tables (`0x080046A4` / `0x080047F6`)
  decide what the sword cuts (filter 0), what lifts (6), what the Gust Jar
  moves (5), and the replacement tile.
- **Chests / signs / item get / HUD / font / menu data** as listed in
  PROGRESS-minishcap.md R2.2; **room code** ports and the
  **delayed entity load manager** as in R2.4; **Kinstone world events** as
  in R2.5.

### Round 3 additions that follow the cartridge

- **Deepwood Shrine** (`Dungeon.lua`, `Boss.lua`) runs on the cartridge's
  flag graph:
  - CheckFlags / SetFlag specs, and entity lists from room props 8-15;
  - objects: LOCKED_DOOR, BOSS_DOOR, BUTTON, CHEST_SPAWNER,
    PUSHABLE_STATUE, LILYPAD, HEART_CONTAINER, FOUR_ELEMENTS, WARP_POINT;
  - managers: FIGHT, TILE_CHANGE, BRIDGE, FLAG_AND, SECRET, ENTITY_SPAWN,
    FALLING_ITEM, CAMERA_TARGET, MOVEABLE_OBJECT, REGION_TRIGGER,
    EZLO_HINT;
  - projectiles: SPIDER_WEB and REMOVABLE_DUST, from
    `gProjectileDefinitions` (`0x0813210C`);
  - per-room code for rooms 0, 2 and 6, and boss room 0.
  - A scripted bot plays it end to end: Gust Jar, map, keys, compass, the
    four key doors, big key, web, boss door, Big Green ChuChu, the Earth
    Element, the heart container and the warp out. It passes 24/24.
- **Cutscene native calls** (`Native.lua`) are ported by address. The
  call map was built by matching the decomp's script `.inc` files against
  the ROM by full opcode sequence. They cover:
  - camera moves and scroll speed, black/white fades with speed, screen
    shake;
  - speech / emote bubbles (THOUGHT_BUBBLE, the settled keyframe);
  - die / hop animations, EquipItem, look-at-player, priority and layer
    helpers.
- **Enemies** with their own decomp state machines:
  - Keese, ChuChu (type 0), Sluggula and Rope;
  - Peahat, Mulldozer and Puffstool are simplified, with their defeat
    rules kept.
- **Game over**: CONTINUE / SAVE AND QUIT.
- **BG tile animations** (water) from `gUnk_080B755C` / `gUnk_080B7278`.
- **Ezlo hint manager** and the SELECT hint.

### Round 4: the cartridge's own screens (Ppu.lua)

The menus are no longer drawn by us. `Ppu.lua` keeps the cartridge's
video state:
- 96 KB of VRAM, the EWRAM BG buffers, 512 palette entries and the OAM;
- the screens are composed the way the GBA does, by priority.

The menu code is ported to fill that state as the cartridge does:
- LoadGfxGroup and LoadPaletteGroup, the BG controls;
- DrawDirect from gFrameObjLists;
- ShowTextBox, DispMessageFrame and the border tiles (text.c,
  message.c).

So the art, layout and colours come from the ROM. Cartridge art now covers:
- **Pause screen ITEMS** (`pauseMenu.c`):
  - the backdrop, which changes with Link's health ($56-$58);
  - the frame, the page tabs (sprite $1FB) and the blinking cursor;
  - the item icons, with tiles copied from sprite 322, and the ammo
    digits;
  - the A / B markers, SAVE, and the description box (message $04xx).
  - The slot grid comes from gItemMenuTable.
- **Pause screen QUEST STATUS**:
  - the quest items, the Kinstone bag level, heart pieces, sword-skill
    and shell counts, the cursor and the description.
  - A on the bag opens **KINSTONE PIECES** (kinstone art from
    gUnk_080CA06C, counts, the "Return" button).
- **Page turning**: each screen's {START, L, R, B} table and the BG1 / BG2
  alpha fade.
- **HUD buttons** (`Ui.lua`, ui.c):
  - the A / B / R buttons, the items on them, the R action labels and
    the beating heart;
  - the buttons glide 4 px a frame and hide while a message is up.
- **Message window**:
  - frame, border tiles, glyph canvas and text colours;
  - the bank-3 choice marker glyphs and the page cursor;
  - growing and shrinking over 8 frames.
- **HUD counters**: the hearts, rupees and, in dungeons, the key counter
  (DrawKeys: icon tiles $1C-$1F and two white digits) are the cartridge's
  BG0 tiles (`Hud.lua`).
- **Game over** (`GameOver.lua`, gameOverTask.c):
  - the GAME OVER letters (sprite $1FD) rising from y 80 to 37;
  - the Save / Don't Save popup, then the Continue / Quit popup.

## Not cartridge art yet

- Pause **MAP** pages (world map, dungeon map): the cartridge's backdrop,
  frame and tabs are there, but the map itself is not drawn
  (DrawDungeonMap, the world map tiles, the markers).
- Pause **SWORD TECHNIQUES** and the **save** screens (9-11): only the
  backdrop, frame and header. SAVE on the items page asks the runtime to
  save directly.
- **Kinstone fusion window** (kinstoneMenu.c): ours.
- **Title screen, file select, name entry, copy and erase**
  (title.c, fileselect.c): ours.
- **Speech bubbles**: the "!" / "?" mark is drawn with the font.
- **Fades**: iris fades are drawn as plain fades.
- **Tile animations**: colour-only (palette) animations are skipped.
- The cartridge's message window has no name tags, so there are none to
  port.

## What differs (honest list)

Round 3:
- Bosses are simplified:
  - Madderpillar: the tail is the only weak point, health 8.
  - Big Green ChuChu: 60 frames of Gust Jar topple it, then it is
    hittable for 150 frames.
  - Neither has the cartridge's full phases or animations.
- The lily pad is moved directly while gusting (no current or rotation).
  Barrel rotation (room $20) is not ported.
- Pesto keeps the shared enemy model.
- Not ported: SetPlayerMacro, the Zelda follower.
- Iris fades are drawn as plain fades.
- The bubble mark ("!" / "?") is drawn with the font.
- (Round 4: the pause pages, A/B/R buttons, message window and game over
  are now cartridge art; see "Not cartridge art yet" for what is left.)
- Palette-type BG animations are skipped.
- Not done: figurine trading, the Mt. Crenel path to the second dungeon.

Round 2 (some items below are now superseded by round 3: game over, pause
pages, the Gust Jar's shrine puzzles, per-enemy state machines):
- Enemies other than the Octorok (ChuChu, Sluggula, Pesto, Puffstool,
  Mulldozer, Rope, Keese, Peahat) use one shared wait / hop / charge model
  tuned per enemy, not their own decomp state machines; special collision
  handlers (`$FF` matrix entries) use a default entry.
- The Gust Jar pulls and stuns enemies in a cone, catches a small one and
  blows it out at the first enemy in line; it does not suck items, push
  lily pads or work the shrine's puzzles.
- The shield blocks contact and rocks from the front; no bounce-back
  physics.
- Out of hearts returns Link to the room's entrance with three hearts (no
  game-over screen, no fairy revival).
- Grass / pot drops use the area droptable (table 15) for every cut or
  broken pot; the cartridge's objects can use their own tables.
- Delayed-load NPCs appear with the room instead of streaming in as they
  come on screen.
- The new-file intro draws sleeping Link over the bed (the cartridge's
  BED_COVER object is not drawn) and hops him out of bed rather than playing
  script_BedInLinksRoom.
- Portals: R on the portal shrinks / grows Link with the cartridge's
  animations and exit offsets, without the jump-on and zoom subtask.
- The pause menu shows only the ITEMS page, drawn with our frame.
- Windcrests are not tracked (their room lists always load).

Round 1:

- **Native room code** (`sub_StateChange_*`, `sub_unk*`) cannot be read from
  the ROM; only Link's house (3 rooms) and Minish Village main are ported, so
  most rooms show only their base entity lists. Cutscene-only native calls
  inside scripts (`Call` / `CallWithArg`) are skipped (recorded per script).
- **Not implemented yet** (after round 2): Ezlo's hint system, map
  screens, dungeon mechanics (keys, locked doors, switches), bosses, fades
  other than black, BG animations (water), the title/file-select art (ours
  are drawn over the player's own Hyrule Town map), the A/B/R button HUD
  sprites, Mole Mitts and later items.
- Diagonal movement uses sin/cos of 45 degrees rather than the cartridge's
  sine table entries (sub-pixel differences).
- Link's hitbox against tiles is a feet-centred box (8x8, Minish 4x3), not
  the cartridge's per-direction probe points.
- Text box: two lines per page like the cartridge, but LÖVE's font and our
  own window art.
- Saves are our own Lua table (flags as sets, local flags keyed by the
  cartridge's FLAG_BANK bit offsets), not SRAM.

## Online (fit to Minish Cap; the cartridge has no link play)

- Friends appear as coloured Links (player id = colour: green, red, blue,
  purple) in the room they are in, with names and emotes (SELECT).
- **Kinstone fusion with a friend**: face their Link and press L; pick a
  piece; they pick one of theirs. Matching shapes fuse: the answering side
  draws a shared fusion as `GetRandomSharedFusion` does (of that shape, not
  fused by either player) and both games record the same kinstone id and
  lose one piece each; the world event's area is announced.
- Verified with `tests/zelda_tmc_online_test.lua` (loopback session pair) and
  the foundation's two-process ENet harness run with this module (2 players:
  snapshots and reliable events both ways, host close seen by the guest).
- Shell gifting: R in the Kinstone offer window gives the friend 10 shells
  (`gift_shells`, round 3).
- Not done: figurine trading; applying world-event effects in the
  world (the fused set itself is what the cartridge's room code and scripts
  read, so ported room code sees it).

## How to check

- `python tools/run_lua_check.py tests/zelda_tmc_core_test.lua`
- `python tools/run_lua_check.py tests/zelda_tmc_online_test.lua`
- `python tools/run_lua_check.py tests/zelda_tmc_round2_test.lua`,
  `tests/zelda_tmc_round3_test.lua` (fake field, no ROM) and
  `tests/zelda_tmc_round4_test.lua` (Ppu / Ui on fake data)
- Menu shots: scratch harness modes `menu4`, `msg4`, `gameover`, `ppu`
- Deepwood bot: scratch harness mode `route` (`TMC_MODE=route`), log in
  `route_log.txt`, shots `route_*.png`
- `python tools/run_lua_check.py tests/zelda_tmc_rom_test.lua` (needs the ROM
  in the repo root or `TMC_ROM`; imports into `TMC_TEST_CACHE`, skips cleanly
  without them)
- Scratch harness (outside the repo): `G:/Gen2Recomped/scratch_claude/zelda/tmc/`
  (`harness/` LÖVE modes rooms / sprites / play, `twoproc/`, `tools/`).
