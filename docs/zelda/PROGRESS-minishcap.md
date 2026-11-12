# Zelda progress: minishcap

Owner: Minish Cap agent. Contract: `docs/zelda/CONTRACT.md`. Parity notes:
`docs/zelda/minishcap.md`. Code: `src/zelda/tmc/`.

(This file was rebuilt on 2026-11-08 after a script of mine truncated it
while editing; the content below is the full record of rounds 1 and 2.)

## Milestones (round 1)

- [x] **M1 ROM survey + detection.** `Layout.detect` checks the header title
      `GBAZELDA MC` and game code `BZME`; SHA-1 of the USA ROM is
      `b4bd50e4131b027c334547b4524e2dbbd4227130` (matches zeldaret/tmc's
      `tmc.sha1`). Every table root the importer follows is a USA address in
      `src/zelda/tmc/Layout.lua`, taken from the decomp's annotations or found
      by searching the ROM for the decomp's structure, and re-checked against
      the ROM (see minishcap.md "ROM survey").
      Reused from the Pokemon Gen 3 port: `src/import/RomGba.lua` (LZ77,
      reads) and `src/core/M4ASynth.lua` (the M4A/Sappy engine).
- [x] **M2 Importer** (`Extract.lua`, `extract(romPath, root, progress, ctx)`):
      areas/rooms (92 areas, 738 rooms), tilesets (BG VRAM images), metatiles
      + tile types, room maps (bottom/top + collision override + special maps),
      exits (gExitLists), entity lists (per room and the whole entity_headers
      region so room code/scripts can load any list by address), raw room
      property pointers [8..15], collision lookups + partial-tile shapes,
      palettes + palette groups, 326 sprites (gSpritePtrs + gMoreSpritePtrs:
      animations, frames, OAM lists, swap gfx), fixed object gfx, object
      palettes, NPC / object / enemy definitions, 2910 messages, 545 songs +
      the M4A sound bank, script region, Kinstone tables, tileset-manager
      swaps, font, HUD tiles, rupee digits, item metadata, common OBJ VRAM,
      tile-interaction tables, sword tables, collision matrix, drop tables.
      Resumable (`steps.lua`), idempotent (`complete.txt` with cacheVersion,
      now 2), accepts the foundation's ZeldaCache object (files under
      `data/generated/`) or an absolute folder, uses `ctx.bytes` when there is
      no rom path, honours `ctx.fresh`. About 8 s headless (LuaJIT).
- [~] **M3 Engine** -- a playable early-game slice, not the whole game:
  - [x] rooms at 240x160: both BG layers from metatile atlases decoded from
        the imported VRAM image + palettes, camera clamped to the room,
        y-sorted sprites between the layers, tileset-manager graphics swaps
        (Hyrule Town, Festival Town, Minish Village) by camera region.
  - [x] collision per pixel exactly as `IsTileCollision` (quarters, shapes).
  - [x] exits: area warps (IsPosInTransitionRect), border warps
        (IsPosInBorderTransitionRegion) incl. "keep world coordinate" ends,
        stairs/doors (ACT_TILE_40/41) and door-less adjacent rooms.
  - [x] Link: walk 1.25 px/frame, facing, cartridge sprite + animations,
        palette $16 (GetPlayerPalette), the no-cap set until EZERO_1ST,
        Minish set when a warp's spawn type or a portal says so; item buttons
        A/B, action button R, Kinstone L; player scripts drive him in
        cutscenes.
  - [x] cartridge script interpreter (`Script.lua`): all 0x8B commands of
        `gScriptCommands` have a handler except native `Call`s, which are
        skipped cleanly (their length is in the opcode).
  - [x] NPCs from `gNPCDefinitions`, objects from `gObjectDefinitions`,
        enemies from `gEnemyDefinitions`, with their sprites/palettes/anims.
  - [x] text boxes from the cartridge's messages in the cartridge's font,
        HUD from the cartridge's tiles, title / file select (our layout over
        a pan of the player's Hyrule Town), saves in our format.
  - [x] music + SFX: M4A songs through M4ASynth on a worker thread.
- [x] **M4 Parity notes**: `docs/zelda/minishcap.md`.
- [x] **M5 Online (fit to Minish Cap)**: `Net.lua` + `Kinstone.lua`:
      friends as coloured Links (green/red/blue/purple tunic by player id),
      emotes (SELECT), Kinstone fusion with a friend's Link (L facing them)
      granting a cartridge shared fusion (GetRandomSharedFusion rules, shape
      match from gKinstoneWorldEvents). Figurine/shell trading: not done.
- [x] **M6 Tests**: `tests/zelda_tmc_*_test.lua` (see "Verified").

## Round 2

- [x] **R2.1 Minish Village graphics bug.** Cause: the smeared block in
      `mvil_02_end.png` was the area's default tileset VRAM showing where the
      Minish Village tileset manager swaps in house graphics; that shot was
      taken before the swap was wired (16:30 vs 16:32). Not a sprite slot or
      OAM size. Checked by stitching whole rooms from 240x160 windows, each
      with the swap the camera picks there (`harness/modes/swapmap.lua`):
      Minish Village, Hyrule Town, Festival Town are clean
      (`shots/swapmap_*.png`); the other rooms rendered so far use no tileset
      manager. Hardening (not cartridge behaviour): if the camera starts
      outside every region, the nearest region's group is loaded instead of
      leaving default VRAM. The title screen's Hyrule Town pan had the same
      smear and now runs the same swap logic.
- [x] **R2.2 Objects and items** (`Objects.lua`, `Items.lua`, `Menu.lua`,
      `Font.lua`, `Hud.lua`):
  - ground items and drops: `gObjectDefinitions[0][item]` sprites (the item
    sprites 322/323 live in `gMoreSpritePtrs`, now imported), animation =
    item id; random drops as `CreateRandomItemDrop` (droptable + low-health /
    low-rupee bonuses, weighted pick from a random slot) and
    `CreateItemDrop`'s gates;
  - chests (`ACT_TILE_26`, `OpenSmallChest`: tile entity item + local flag,
    tile $74, re-shown open on reload) and signs (`ACT_TILE_58/91`, the
    SIGN tile entity's message), both facing north;
  - lifting/throwing pots (object 5 and liftable tiles), cutting
    grass/bushes with the sword's per-frame tile probes (`gUnk_08129072`)
    through `DoTileInteraction` (`gUnk_080046A4` / `gUnk_080047F6`,
    filter 0);
  - item get: Link holds the item up while its `gItemMetaData` message
    shows; new button items are equipped automatically (B first);
  - Smith's Sword (cut + per-frame hitboxes `gUnk_08129096`), shield (hold,
    0.75 speed, blocks from the front), Gust Jar (simplified, see
    minishcap.md);
  - Minish portals: `MINISH_PORTAL_MANAGER` zones; R shrinks / grows Link
    (needs EZERO_1ST);
  - START opens the ITEMS page (menu slots, icons, names $04xx, A/B
    assignment with the swap rule);
  - the cartridge font (8x16 nibble glyphs from `0x08692F60`) and the HUD
    from the cartridge's own BG0 tiles (gfx group 16, palette 12): hearts
    with quarters, wallet icon, outlined rupee digits (white / yellow at
    full wallet), counting one step a frame;
  - Mole Mitts: not reachable in the slice (after Cave of Flames), not
    ported.
- [x] **R2.3 Enemies and combat** (`Enemies.lua`): `gEnemyDefinitions` stats
      and sprites; every contact resolved through `gCollisionMtx`
      (`0x080B7B74`, `[hitType*34+hurtType]`: Octorok touch = 2 damage, 30
      invulnerability frames; the Smith's Sword deals 2); knockback; home
      rectangles (`gUnk_080D3D94` or the room entry); death + drops by
      `DeathFx_EnemyDroptables`; out of hearts returns Link to the room's
      entrance. Octorok is ported in full (idle / walk / turn / rock
      projectile); ChuChu, Sluggula, Pesto, Puffstool, Mulldozer, Rope,
      Keese, Peahat use a shared wait/hop/charge model (simplified). Minish
      Woods (Octoroks, ChuChus) and Deepwood Shrine's rooms (Sluggulas,
      Mulldozers, Pestos, Puffstools, pots) load and run.
- [x] **R2.4 Per-room NPC setup + intro**: ports of
      `sub_StateChange_HyruleTown_0` (Hyrule Town and the Festival),
      `_MinishWoods_Main`, `_HyruleField_SouthHyruleField`; the
      `DELAYED_ENTITY_LOAD_MANAGER` ($16: NPCStruct lists by story stage --
      the Festival goes from 4 to 34 entities and its prologue scene
      starts); `UpdateGlobalProgress` from flags; `gArea.queued_bgm`. The
      new-file wake-up: `script_PlayerIntro` (`0x08009B30`) runs with Link
      asleep in bed, then he wakes and gets control -- a new game now runs
      from the title screen.
- [~] **R2.5 Optional**:
  - Kinstone fusions now change the world (world-event types 1, 3, 7, 8, 9,
    15, 17, 24, 25). Checked: fusing 0x0D makes Mt. Crenel's Golden
    Tektite appear.
  - Deepwood Shrine: rooms, enemies and pots work; not completable (no
    Big Green ChuChu boss, no keys / locked doors, no Gust Jar puzzles).
  - Figurine/shell trading online: not done.

## Round 3

- [x] **R3.1 Deepwood Shrine complete** (`Dungeon.lua`, `Boss.lua`).
  - The dungeon runs on the cartridge's own flag graph. Flag specs follow
    `CheckFlags`.
  - Objects: LOCKED_DOOR (shutters that open, shutters that close behind,
    small-key locks), BOSS_DOOR (big key), BUTTON (latching and held),
    CHEST_SPAWNER (small chests that appear, big chests with the
    BIG_CHEST item), PUSHABLE_STATUE, LILYPAD_LARGE, HEART_CONTAINER,
    FOUR_ELEMENTS, WARP_POINT.
  - Projectiles: SPIDER_WEB and REMOVABLE_DUST.
  - Managers: REGION_TRIGGER, FIGHT, TILE_CHANGE_OBSERVE, BRIDGE,
    FLAG_AND_OPERATOR, SECRET, ENTITY_SPAWN, FALLING_ITEM, MOVEABLE_OBJECT,
    CAMERA_TARGET (camera pans).
  - Dungeon inventory per area location: small keys, big key, map,
    compass; `CheckInventory1` sees them.
  - Gust Jar: pulls pots, tears webs by grabbing and walking back, sucks
    dust, pushes lily pads.
  - Link falls into water/holes without flippers.
  - The importer adds projectile definitions and OAM-only sprites past
    the sprite table (doors use sprite 477).
  - The room code (`sub_StateChange_DeepwoodShrine_*`) is mostly empty
    for Deepwood. The rooms that do something (StairsToB1, Barrel,
    Madderpillar, Boss) work through their managers, except the two
    noted under Open issues.
  - Bosses (simplified rules, see `Boss.lua`): the Madderpillar (only the
    tail takes damage) and the Big Green ChuChu (Gust Jar on its base
    topples it, then the sword).
  - **Checked by a scripted playthrough** (`harness/modes/route.lua`,
    log `G:/Gen2Recomped/scratch_claude/zelda/tmc/route_log.txt`): 24/24
    checks pass in 4727 frames.
    - Madderpillar → flag `$17` → Gust Jar chest;
    - map;
    - statues on buttons → key;
    - four buttons → camera pan → key;
    - the room-8 fight → falling key;
    - the Gust Jar pulls a pot onto a button → key;
    - compass;
    - four key doors;
    - big key;
    - web torn;
    - boss door;
    - Big Green ChuChu → `LV1_CLEAR`;
    - Earth Element;
    - heart container (+8 max health);
    - warp point out to the shrine entry.

    Screenshots: `shots/route_*.png`. The bot positions Link with
    teleports between puzzle spots; every puzzle step goes through the
    game's code.

- [x] **R3.2 Cutscene native calls** (`Native.lua`).
  - Natives are ported by address. A scratch tool
    (`tools/callmap.py`) matched the decomp's script sources to their
    assembled bytes by full opcode sequence, giving 148 unambiguous
    name -> address pairs. `sub_XXXXXXXX` names carry their own address,
    and script.c neighbours were placed by thumb function starts.
  - Ported:
    - camera to an entity; waiting for the camera;
    - fades;
    - Link's !/? bubbles;
    - die/hop animations, EquipItem;
    - walk-to-x/y, wait for animation, random facing, look at Link,
      checks on Link's x/y, the respawn point;
    - pause-menu and priority calls;
    - the NPCs' MakeInteractable and animation helpers.

    Unported calls are counted (`Script.missing`). The intro, smithy,
    festival and South Hyrule Field scenes run with none missing
    (`harness/modes/scenes.lua`).
  - Script commands now do what the cartridge does:
    - fades with colour (white for FADE_BLACK_WHITE) and SetFadeTime
      speed;
    - InitScreenShake;
    - camera moves that scroll at SetScrollSpeed instead of jumping, with
      WaitFor_1 / WaitForCameraTouchRoomBorder waiting on them;
    - CameraTargetManager pans;
    - THOUGHT_BUBBLE sprites for "!" / "?" (`shots/cut_*`,
      `crop_bub.png`). The red mark itself is drawn with the cartridge
      font: in the sprite it sits on a shared frame not split out.
  - Not ported: player input macros (SetPlayerMacro: cutscenes that walk
    Link by recorded input), iris fades as circles (plain fades instead),
    the Zelda follower (festival).

- [x] **R3.3 Enemies and game over** (`Enemies.lua`, `Field.lua`).
  - Ported from their decomp state machines:
    - Keese (fly / rest / sleep tables, wakes within $70);
    - ChuChu type 0 (puddle until Link is within $48, rises, hops
      re-aimed every 8 frames, jumps inside $38, rests, sinks; no damage
      as a puddle);
    - Sluggula (drops from the ceiling within $20, crawls and turns by
      the decomp's rules);
    - Rope (wanders at $80, charges at $1A0 when Link lines up, 30-frame
      cool-down).
  - Simplified, with their defeat rules kept:
    - Peahat (only hurt when landed);
    - Mulldozer (aims and charges);
    - Puffstool (Gust Jar strips its spores, then 180 frames of being
      hittable).
  - Pesto keeps the shared model. Bosses are in `Boss.lua`.
  - Game over: GAME OVER with CONTINUE (three hearts, the room's
    entrance) and SAVE AND QUIT (runtime save, title screen)
    (`shots/gameover.png`, `harness/modes/gameover.lua`).
  - The Deepwood run still passes 24/24.
- [x] **R3.4 Menus and HUD** (`Menu.lua`, `Field.lua`, `Assets.lua`,
  `Room.lua`, `Dungeon.lua`).
  - Pause screen pages ITEMS / QUEST / KINSTONES / MAP, turned with L / R.
    - QUEST shows the elements, the sword, heart pieces, shells, kills and
      play time.
    - KINSTONES shows the pieces by type and the fusions made.
    - MAP draws the area's rooms from the room headers: visited rooms are
      filled; with the dungeon map every room is outlined; the compass
      marks unopened chests and the boss room.
    - Our own layout drawn with the cartridge font, not the cartridge's
      art.
  - B / A / R buttons at InitUI's positions ($B8 / $D0 / $D8). They show
    the equipped item icons and the R action (Talk / Lift / Throw / Open /
    Shrink / Grow). They are our circles, not the cartridge's button
    sprites.
  - BG tile animations (water) from `gUnk_080B755C` / `gUnk_080B7278`. The
    importer writes `bganim.bin`; each animation is drawn as an overlay
    batch and stepped by its frame timers (`shots/water*.png`, frames
    differ). Palette-type animations are skipped.
  - Ezlo's hints:
    - EZLO_HINT manager (0x0A): types 0/2 make Ezlo speak once in the
      region and set the done flag; type 3 sets the SELECT hint.
    - SELECT asks Ezlo offline (the area hint, or 0x0B01).
    - Seen in Deepwood: the entrance hint, and the key-door comment in
      room $10.
- [~] **R3.5 Extras.**
  - Done: shell gifting online (R in the Kinstone offer window gives 10
    shells, `gift_shells`).
  - Not done: figurine trading, the Mt. Crenel path to the second
    dungeon.

Final check (round 3):
- Route `harness/modes/route.lua`: **24/24, 4537 frames**.
  - The bot now lets Ezlo's text finish before it warps or uses a key,
    as a player would.
- Tests: core 42, online 23, rom 47, round2 27, round3 47, all passing.
- The two-process ENet harness: rc=0.

## Round 4

- [~] **R4.1 Cartridge menu art** (`Ppu.lua`, `Ui.lua`, `Menu.lua`,
  `TextBox.lua`, `Field.lua`, `Extract.lua`, `Layout.lua`).
  - `Ppu.lua` is a small GBA picture unit:
    - 96 KB VRAM, the EWRAM BG buffers, 512 palette entries and an OAM
      list;
    - text-mode BGs and OBJs composed by priority;
    - LoadGfxGroup / LoadPaletteGroup;
    - DrawDirect from gFrameObjLists;
    - ShowTextBox, DispMessageFrame and the border tiles (text.c,
      message.c).
  - The importer (cache version 4, step `menus`) writes:
    - every gfx group, with LoadGfxGroup's language rule (USA = 1; the old
      filter skipped the English menu text);
    - the menu tables (`Layout.MENU_DATA`);
    - OAM-only sprite frames up to 255, sprite 0, and the whole frame
      table of sprite 322.
  - Pause menu:
    - ITEMS and QUEST STATUS are the cartridge's screens: backdrop,
      frames, tabs, cursor, item icons and ammo digits, equipped markers,
      SAVE, the description box, the quest items, heart pieces and shells.
    - Pages turn by each screen's {START, L, R, B} table, with the
      BG1 / BG2 alpha fade.
  - HUD: the A / B / R buttons, the items on them, the R action label
    and the beating heart are the ui.c elements (`Ui.lua`). They hide
    while a message is up.
  - Message window: the cartridge's frame, border tiles, glyph canvas,
    colours, page cursor and grow/shrink.
  - Game over (`GameOver.lua`): letters, the Save / Don't Save popup and
    the Continue / Quit popup (`shots/go4_*.png`).
  - The KINSTONE PIECES page, opened with A on the bag in QUEST STATUS.
  - What is still ours is listed in minishcap.md under "Not cartridge art
    yet": the map pages' contents, sword techniques and the save screens,
    the Kinstone fusion window, title and file select, bubble marks, iris
    fades and palette animations.
  - The dungeon key counter (DrawKeys) is now drawn
    (`shots/crop_keys.png`).
  - Shots: `shots/menu4_*.png`, `msg4_*.png`, `ppu_sheet.png`,
    `crop_hud.png`.
  - Checks:
    - `tests/zelda_tmc_round4_test.lua`: 20 checks;
    - the Deepwood route still passes 24/24;
    - core 42, round2 27, round3 47, online 23 and rom 47 all pass.
- [ ] R4.2 Boss and puzzle parity: not started.
- [ ] R4.3 Windcrests, Mt. Crenel, Cave of Flames: not started.
- [ ] R4.4 Figurine trading online: not started.

## Round 5

Setup:
- Cache version 5.
- `Layout.MENU_DATA` has one anchor per screen family.
- `Layout.R5_EXTRACT` lists importer modules that run at the end of the
  `menus` step.
- Scratch check script: `tools/r5check.sh` (every src file, every
  `tests/zelda_tmc_*` file, then the Deepwood route).

- [x] **R5.1a Map pages** (`MapMenu.lua`, `ExtractMaps.lua`).
  - Screens 4, 5 and 6 of pauseMenu.c / pauseMenuScreen6.c on Ppu.lua.
  - **World map:**
    - the regions;
    - clouds over unvisited regions (OBJ-window OBJs, WINOUT $3D3F);
    - the cursor and the region name;
    - A opens the region's area map if `gSave.windcrests` has its bit.
  - **Area map:**
    - gfx group $5F + region and palette group $BA + region;
    - scrolls with up / down;
    - Link's and the fusion markers;
    - BG3's per-scanline priority window.
  - **Dungeon map:**
    - DrawDungeonFeatures from `gDungeonLayouts`;
    - room outlines from gMapData (importer: `dmap.bin`), drawn as 4bpp
      pixels into gDungeonMap at $06006000;
    - map-only rooms in colour 2, visited rooms in colour 3, the current
      room in colour 8 (palette 200-207 rotating);
    - the floor list, Link's floor and the cursor;
    - the map, big key and compass icons;
    - with the compass: chest and boss markers.
  - **Field side:**
    - UpdatePlayerMapCoords and UpdateWindcrests run every 8 frames;
    - on room entry: LoadRoomVisitTile's local flag and the dungeon
      entrance.
  - **Fixes after the fork was cut off:**
    - LoadDungeonMap is asynchronous, so the outline copy now lands after
      gfx group $81;
    - the map and big-key item ids were swapped ($50 is the map, $52 the
      big key).
  - **Checks:**
    - `tests/zelda_tmc_r5_maps_test.lua`: 12 checks;
    - scratch mode `r5_maps`, shots in `r5/maps/shots/`: world, area,
      area scrolled with Link's marker, and the Deepwood B1 map with rooms
      and chests.
- [x] **R5.1b Effects** (`ExtractFx.lua`, Field / Ppu / Script / Assets).
  - The "!" / "?" / sleep bubbles are the THOUGHT_BUBBLE sprite's own
    frames:
    - the mark is the frame's first OAM piece;
    - timer 45; kind 2 stays;
    - SFX $74 / $F3.
  - **Iris fades** (script SetFadeIris / IrisInOut 0x40 / 0x41):
    - a circle around the camera target, at the cartridge's
      per-scanline spans (sub_0801E24C);
    - closing from $96 or opening past 150.
  - **Palette BG animations** (BG_ANIM_PALETTE): the frames load
    palettes, and the metatiles using those banks are redrawn per frame.
    Example: the Cave of Flames lava.
  - **Ppu** gained:
    - the OBJ window (WINOUT);
    - affine OBJs.
  - **Checks:**
    - `tests/zelda_tmc_r5_fx_test.lua`: 34 checks;
    - scratch mode `r5_fx`, shots in `r5/fx/shots/`.
  - Iris fades are started only by script commands 0x40 / 0x41. Room
    transitions keep the plain black fade, and have not been checked
    against the cartridge for iris use.
- [x] **R5.1c Title screen and file select** (`Title.lua`,
  `FileSelect.lua`, plus Ppu, Game and Layout).
  - **Ppu** gained:
    - affine BGs (mode 1 BG2 / mode 2): BgAffineSet output, wrap,
      256 colours;
    - BLDCNT alpha blending (`p.blend = {t1, eva, evb}`): the first
      target, when it is the top pixel, mixes with the pixel under it;
    - `drawGlyphs` fixed-width cells (WStruct.unk1 = 1).
  - **Title** (title.c, USA path):
    - gfx groups 2 and 3, palette group 4;
    - BG0 blended over BG1 at the light-ray alphas
      (`sLightRaysAlphaBlends`, ROM `0x08107C30`), rotating palette
      groups 5-8 every 8 frames;
    - the affine sword zooming from ratio $10 to $100, the white
      fades;
    - the TITLE_SCREEN_OBJECT pieces: object $BD forms 0 / 1 / 2 / 4,
      their fixed gfx and object palettes, positions from
      `gUnk_08125014`, and the sparkle's timing;
    - PRESS START (DrawDirect $1FF 0 and 1), A / START to the file
      select.
    - The attract demo is not ported: when the timer runs out, the
      title stays up.
  - **File select** (fileselect.c and FILE_SCREEN_OBJECTS, sprite $145):
    - gfx groups 5, 6, $F and 7, palette groups 9 and $C;
    - BG2 blended over BG3 at 15/10;
    - the sparkle palettes from `gUnk_080FC8DE`, every 16 frames;
    - the three file plates, which slide (`sub_0808EF6C`) to each
      state's spot, with the names drawn into OBJ VRAM $06014000 in the
      cartridge font;
    - the hearts in BG1 (`sub_08050B3C` tile codes) and the element
      icons;
    - Start / Copy / Erase buttons;
    - copy (targets numbered as `sub_08051738`);
    - erase (Quit / Erase);
    - name entry: gfx group 8, keyboard pages 9 / 10 copied from
      gBG3Buffer to BG1, every glyph rendered into BG VRAM; the key under
      the cursor read from gBG3Buffer as the cartridge does; L / R pages;
      B back; START to END; the row-5 buttons; the cursor; the bobbing
      caret;
    - the cartridge's dialogs (CreateDialogBox: font `gUnk_080FC844`,
      text, palette and sound from `gUnk_080FC85C`) for "Saving",
      "Erasing" and "copied".
  - **Three files in one slot.** The runtime gives one save slot, so the
    three files live inside it:
    - the active file is the save table;
    - the others sit in its `fileSlots` (`"active"` marks its own
      place);
    - copy, erase and new files are written back through
      `host:requestSave()`.
  - Not ported: the Link preview (type 23), the sword icon (24), the
    staff-roll mark (25), the R options screen and the language row.
  - **Checks:**
    - `tests/zelda_tmc_r5_title_test.lua`: 16 checks (file packing, the
      blend, the affine BG);
    - scratch modes `r5_title` + `r5_fsflow` (`TMC_TITLE_SAVE=1
      TMC_TITLE_EXTRA=r5_fsflow`), shots in `r5/title/shots/`: fade, sword
      zoom, logo, PRESS START, the list, name entry with "BOo" typed, the
      saving dialog, view, erase and its dialog, copy, and the started
      game.
- [x] **R5.1d Kinstone fusion window** (`KinstoneMenu.lua`, with Kinstone,
  Script and Layout).
  - kinstoneMenu.c Types 0-5 on Ppu:
    - the pause menu's base gfx, palette group $CB, gfx group $75;
    - Link's name and the fuser's name into OBJ tiles $80 / $A0, and the
      name plate gfx group $76 + n by the name's width;
    - the wheel of seven pieces at sine positions, easing by
      `gUnk_081280EE`;
    - the counts (digit tiles $2E0 + slot * 2) and piece art in 16 OBJ
      slots;
    - the arrows, the header and the name plates (sprites $1FB / $1FA);
    - the target half spinning through OAM affine matrix 0
      (`gUnk_08128120`);
    - the slide-in, the shape check, the bounce (Type4), the WIN0
      brightness flash, the fused stone, message $0702, the spin, and the
      exit with fusion state 5 / 6;
    - the fuser drawn at ($CC, $60), a white fade in, and the cartridge's
      sound ids.
  - **The fuse flow.** InitializeFuseInfo / PerformFuseAction
    (Fuse_Action0-3) are ported:
    - script command 0x57 (ScriptCommand_0807EA4C) starts it;
    - UpdateFusion (0x56) steps it, instead of always answering
      "fused".
  - **Online:**
    - the opener picks a piece in the same window and waits;
    - the friend's window shows the opener's piece as the half on
      offer;
    - the answer plays the fusion or the bounce on both sides.
  - L alone opens the window with nothing on offer, to browse the bag.
  - Headless tests keep the old plain flow (`Kinstone:useWindow`).
  - Not ported:
    - the KINSTONE_SPARK object (the spark frames are silent: only the
      timing and SFX_1CA);
    - native NPC code that calls InitializeNPCFusion: most NPC fusers
      are native code, which this port runs only for scripted fusers.
  - **Checks:**
    - `tests/zelda_tmc_r5_kinstone_test.lua`: 23 checks (the whole flow,
      the bounce, cancel);
    - online 23/23;
    - scratch mode `r5_kinstone`, shots in `r5/kinstone/shots/`: wheel,
      bad piece, sliding, bounce, good piece, flash, fused message.
- [x] **R5.1e Sword techniques, sleep and save screens** (`SaveMenu.lua`,
  Menu).
  - Screen 8 (sword techniques):
    - the cursor, the learnt scroll icons, the big scroll and the
      description (`gUnk_08128D70`, font `gUnk_08129004`).
  - Screen 9 (sleep):
    - popup type 2, then a white fade and back. GBA sleep mode itself
      is not emulated.
  - Screens 10 / 11 (save, from QUEST STATUS / ITEMS):
    - popup type 0;
    - "Saving..." (CreateDialogBox 8) while the runtime saves;
    - back to page 2 / 1.
  - SAVE on the ITEMS page now opens screen 11, as `sub_080A4E84($B)`
    does.
  - **Checks:** scratch mode `r5_save`, shots in `r5/save/shots/`: the
    save popup, No, the saving dialog, back to items (the host's
    requestSave was called once), the sword techniques (from QUEST
    STATUS), the unlearnt scroll, the sleep popup and the white.
- [~] **R5.2 Boss and puzzle parity.**
  - [x] **Madderpillar** (`BossMadderpillar.lua`): madderpillar.c ported
    whole.
    - The head walks the tile grid at $A0, choosing turns from
      `gUnk_080CCDC8` (sub_08029E0C).
    - Six segments follow through the cartridge's 14-entry step rings
      (13 frames late).
    - A sword on the head:
      - the head stops (hit type $6B, palette $7F, SFX_HIT);
      - a grey wave runs down the body (`gUnk_080CCDA0`);
      - the tail opens after 71 frames and is hittable (hit type $6C,
        hitbox `gUnk_080FD298`) for 120 frames;
      - then it closes, and the head turns angry: speed $108,
        animations + 4, 360 frames of palette flicker
        (`gUnk_080CCDD4`), SFX_19D / SFX_182.
    - Tail health 0: the segments explode one by one
      (FX_GIANT_EXPLOSION3) and the head goes after 105 frames.
    - The Deepwood bot now hits the head, then the open tail, and stands
      clear of the body in between (tp is its positioning shortcut, as
      elsewhere in the route).
    - **Checks:**
      - `tests/zelda_tmc_r5_boss_test.lua`: 21 checks;
      - scratch mode `r5_boss`, shots in `r5/boss/shots/`: walking,
        stunned wave, tail open, angry, exploding;
      - the route stays at 24/24.
  - [ ] Big Green ChuChu (chuchuBoss.c, 1857 lines): still the round-3
    simplification.
  - [x] **SetPlayerMacro / WaitForPlayerMacro** (`PlayerMacro.lua`,
    Native $0807F29C / $0807F2A8).
    - UpdatePlayerInput's macro branch: hold / IGNORE / JUMPTO / END,
      with `playerMacroWaiting` wrapping as on the cartridge.
    - The importer finds each macro a script passes to SetPlayerMacro
      (three in the USA ROM) and copies its entries into
      `manifest.playerMacros`.
    - While a macro runs it replaces the pad for Link, even with player
      control off.
    - `tests/zelda_tmc_r5_macro_test.lua`: 16 checks.
  - [ ] Barrel room $20, lily pad currents, Pesto, the Zelda follower: not
    started this round.
- [ ] **R5.3 Windcrests, Mt. Crenel, Cave of Flames:** not done.
  - `Crenel.lua` holds the windcrest bit reader and empty hooks (object,
    enemy, item, hole) that a cut-off fork had already wired into
    Dungeon / Enemies / Player / RoomCode.
  - The map pages set the region bits of `gSave.windcrests`.
    Activations (bits 24-31) are read, but nothing sets them yet.
  - Cave of Flames' palette animation (lava) is in (R5.1b).
- [ ] **R5.4 Figurine trading online:** not done.
- **Final check (round 5):**
  - tests: core 42, online 23, rom 47, round2 27, round3 47, round4 20,
    r5_fx 34, r5_maps 12, r5_title 16, r5_kinstone 23, r5_boss 21,
    r5_macro 16; all pass;
  - Deepwood route: 24/24, 6097 frames.
- After R5.1a/b, all of these pass:
  - tests: core 42, online 23, rom 47, round2 27, round3 47, round4 20,
    r5_fx 34, r5_maps 12;
  - the Deepwood route: 24/24, 4553 frames.

## Round 6

Setup:
- Scratch outputs under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r6/`;
  `r6/r6check.sh` runs every src file, every `tests/zelda_tmc_*` file and
  the Deepwood route.

- [x] **R6.1a Native NPC fusers** (`Fusers.lua`, hooks in Field / Kinstone).
  - GetFuserId: the cartridge's 6-byte lists (enemies 0x0800232E + 6, NPCs
    0x08002342 + 6; $FF type / type2 match anything), read from the
    player's ROM (menudata.bin range `fusers`).
  - GetFusionToOffer, as common.c: the Kinstone Bag, the fuser's lowest
    global progress (data[0]), its list (data[5..], $FF = a random shared
    fusion via GetRandomSharedFusion), `gSave.kinstones.fuserOffers` /
    `fuserProgress` ($F1 needs replacement, $F2 just fused, $F3 done), and
    the stability roll (data[1] percent) on every load.
  - Every NPC the list names rolls its offer when it spawns (its native
    init); L in front of the nearest interactable with an offer in 1..100
    starts InitializeNPCFusion with the NPCData texts (gUnk_08001A7C), the
    fuser's name from GetFuserId's text id goes on the window's name plate,
    and the NPC runs UpdateFuseInteraction until the fusion ends (its script
    is paused, as the NPC's action 3). No pieces at all: Ezlo's hint
    TEXT_EZLO $65. Scripted fusers (no list entry) keep the script path.
  - NotifyFusersOnFusionDone on every fusion; MarkFuserDone is available.
  - Checks: `tests/zelda_tmc_r6_fusers_test.lua` 38 checks (synthetic
    table + the ROM's lists: 124 NPC entries resolve); scratch mode
    `r6_fusers` (`TMC_GFLAGS=2`), shots in `r6/fusers/`: in Hyrule Town at
    progress 2, 22 fusers load with names (Anton, Sheila, Brocco...),
    Sheila offers #83, her text, the window with "Sheila" on the plate, the
    fusion, and her offer goes to $F2.
  - Not ported: the fusion bubble over a fuser's head (CAMERA_TARGET);
    enemy fusers (Business Scrubs) are not rolled. Townspeople (NPC 6)
    are still invisible (their LoadExtraSpriteData parts are not drawn):
    a pre-existing gap, they fuse but cannot be seen.
- [x] **R6.1b Windcrests** (`Crenel.lua`, Native).
  - Windcrest_Unlock ($080A2138, called by script_Windcrest): SFX_SECRET,
    `gSave.windcrests |= 1 << (type2 + 24)`, FX_GIANT_EXPLOSION. The map
    pages and the room code already read those bits.
  - Native.call loads the modules that register ports (Crenel.lua) on its
    first call.
  - Checks: scratch mode `r6_windcrest`, shots in `r6/windcrest/`: the
    Hyrule Town crest, Tingle's text, windcrests $00000200 -> $08000200
    (WINDCREST_HYRULE_TOWN).
  - Not ported: the Ocarina of Wind warp (the bird and the fast-travel
    menu). The Ocarina comes long after Mt. Crenel, so it is not reachable
    in what is ported.
- [x] **R6.2a Large lily pad** (`Dungeon.lua`, lilypadLarge.c).
  - Drawn with its own animation 9 as an affine OBJ: the scale bob
    (sub_08085F48: the squash when Link steps on, the slow breathing with
    and without him) and the swing between -$1000 and $1000 while it
    moves (Field draws `e.affine`).
  - Momentum: the Gust Jar's release frame (PL_JAR_3) kicks it against
    Link's facing by the charge (held > $77 / > $EF frames) from
    `gUnk_08120620`, read from the ROM (new MENU_DATA `lilyKick`); each
    axis clamped to 1 px a frame, slowing by $80 a frame, a quarter
    bounce off the bank.
  - Currents: ACT_TILE_17 under the front edge takes it (Action2: to the
    channel's middle, down at 2 px, the $40 drop with SFX_12D, Link
    paused on it). Deepwood has no such tiles; the code is there for the
    later dungeons.
  - Not ported: the jar's suction pulling the pad while Link is ashore;
    ripples.
  - Checks: scratch mode `r6_lily` (room $48/$12), shots in `r6/lily/`:
    the pad drawn under Link, the kick (facing up: +$10000 clamp), the
    bounce, the drift.
- [x] **R6.2b Rolling barrel** (`Barrel.lua`, Dungeon / Field / Ppu).
  - ROLLING_BARREL_MANAGER ($0C) in room $20 ported whole except the
    fall through the open bottom: OnEnterRoom's palettes and gfx groups,
    BG2 redrawn every frame with one BgAffineSet a scanline (Ppu affine
    layers take `affineLines`), the quadrant start angle, Link sliding to
    the bottom row, the roll (speed by Link's row, SFX_BARREL_ROLL each
    16 px), the 45-frame locks at $48 / $A0 / $F0, and the four doorways
    (angle ranges, the per-angle boxes, the exit spot, dws_barrel_state,
    SFX_STAIRS). Tables read from the ROM (new MENU_DATA `barrelTables`).
  - BIG_BARREL outside (room 6): Type0 frame = dws_barrel_state (+1 with
    LV1TARU_OPEN), Type1 rims, Type2 webs while local flags $15 / $16 are
    clear. The web burning (Type3 / Type4) is not ported.
  - Cache version 6 (the two new MENU_DATA ranges).
  - Checks: `tests/zelda_tmc_r6_barrel_test.lua` 21 checks; scratch mode
    `r6_barrel`, shots in `r6/barrel/`: the inside (cartridge art, the
    cylinder), rolled after holding up, door 0 -> room 6 at ($B8, $80),
    state 0, the barrel outside.
- [x] **R6.2c Zelda follower** (`ZeldaFollower.lua`, Field / Native).
  - zeldaFollower.c: the 20-entry history of Link, pushed on change and
    while Link is over 24 px from the oldest, Zelda on the oldest,
    walking / standing animations (4 / 0 + facing) with the 30-frame
    hold, the straight-line refill when she is shown.
  - CreateZeldaFollower: while ZELDA_CHASE ($1C) is set she stands on Link
    when a room loads (and persists across rooms).
  - zelda.c $08066D04 / $08066D14 / $08066D4C: the scripted Zelda NPC
    takes the follower's place (follower hidden) and hands back (follower
    shown where the NPC stood, NPC hidden), replacing round 3's stubs.
  - Not ported: hiding while Link falls or warps (framestates $0A / $16);
    her height on Link's jumps.
  - Checks: scratch mode `r6_zelda` (Hyrule Town with ZELDA_CHASE), shots
    in `r6/zelda/`: she trails Link by about 24 px with the walk
    animation (index 7 left, 4 up) and stands (2) when he stops.
- [x] **R6.2d Madderpillar cost for the bot** (scratch `route.lua` only).
  - The damage was the bot's own play: it stood 14 px under the open tail,
    touching the segment before it (17 hits of 2, logged with
    `TMC_MPDBG=1`). It now comes at the tail from the far side of the
    body, 18 px out, and meets the head from beside its path.
  - Madderpillar: 64 -> 62 HP and 1493 frames (was 64 -> 30, 2071).
- [ ] Big Green ChuChu (chuchuBoss.c) and Pesto: still the round-3
  simplifications.
- Route after R6.2: 24/24, 5513 frames.
- [~] **R6.3 Mt. Crenel and the Cave of Flames:** started, far from done.
  - Room code (`RoomCode.lua`, roomInit.c): MountainTop's list unless
    ENDING; CaveOfFlamesEntrance's after-the-dungeon list, the windcrest
    list until WINDCREST_MT_CRENEL, WHITE_SWORD_END with the green sword;
    the Entrance's TILE_TYPE_374.
  - Bot route mode `crenel` (scratch harness), log in
    `r6/crenel/crenel_log.txt`: 10 pass, 6 fail. It passes: Mt. Crenel's
    five rooms load; the windcrest is there and touching it sets
    WINDCREST_MT_CRENEL (through script_Windcrest); the Cave of Flames'
    18 rooms load; a mine cart stands in room $02; Gleerok's room loads.
    It fails, on purpose, on what is not ported: Melari's mine and the
    Grip Ring, the bean and Mineral Water, riding the mine cart, the
    Cane of Pacci, Gleerok's fight, the Fire Element.
  - Survey (`r6_crenel_survey`, `r6/crenel/survey.txt` + a shot per
    room): every room's entities; no room's scripts call an unported
    native in their first 30 frames. Objects there: ARCHWAY, MINECART,
    WHIRLWIND, BOLLARD, WARP_POINT, BOSS_DOOR, CRENEL_BEAN_SPROUT; enemies
    Rollobite, Tektite, Spiny / Spiked Beetle, Helmasaur, Bobomb, Chaser,
    Blade traps, Rupee Like, Falling Boulder, Small Pesto (shared model).
  - Next, in order: MINECART (minecart.c 369 lines + the player's
    minecart state), the Cane of Pacci (itemPacciCane / playerItemPacciCane
    / its projectile, flipping pots and spring holes: `Crenel.holeLaunch`
    is already hooked), Gleerok (gleerok.c, 1588 lines), then the mountain
    path (Melari's mine, the bean, the Grip Ring).
- [ ] **R6.4** Figurine trading, the file-select leftovers, the attract
  demo: not started.
- **Final check (round 6):** tests core 42, online 23, rom 47, round2 27,
  round3 47, round4 20, r5_fx 34, r5_maps 12, r5_title 16, r5_kinstone 23,
  r5_boss 21, r5_macro 16, r6_fusers 38, r6_barrel 21; all pass. Deepwood
  route 24/24, 5513 frames. Crenel route 10/16 (the 6 fails are the
  unported pieces listed above).

## Round 7

Setup:
- Scratch outputs under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r7/`;
  `r7/r7check.sh` runs every src file, every `tests/zelda_tmc_*` file, the
  Deepwood route and the Crenel bot (log in `r7/crenel/crenel_log.txt`).
- Cache version 7 (new MENU_DATA ranges, every sprite's full frame list).

- [x] **R7.1a Multi-part NPCs** (`NpcParts.lua`, hooks in Field / Assets /
  Extract).
  - LoadExtraSpriteData (up to four 4-byte SpriteLoadData entries: palette,
    tile offset, sprite, per-frame gfx bit), SetExtraSpriteFrame,
    SetSpriteSubEntryOffsetData1/2 with GetSpriteSubEntryOffsetDataPointer
    over gExtraFrameOffsets, and the ARM drawer's part loop ($080B2718:
    the entity's own frame is skipped, parts 3..0 drawn so part 0 is on
    top, the part's flip byte XORed in, x offset mirrored with the flip).
  - Every `_Head` function ported by NPC id: Townsperson (incl. the held
    keyframe = gUnk_0810B680.unk2), Kid, Guard / Guard_1, Maid / Maid_1,
    Forest Minish, Minish Ezlo (with its palette switch), Beedle, Sitting
    Person, Sturgeon, Talon, Smith, Mutoh, Carpenter, Mountain Minish,
    Melari, Gorman, Dog, Syrup, Town Minish, Percy, Farmers, Mama,
    Teachers, Wind Tribespeople, NPC_UNK_58. Tables read from the ROM
    (MENU_DATA `npcData` $0810A300..$08114800, `extraFrameOffsets`).
  - Extract: sprites now keep every frame gFrameObjLists holds (a table
    runs to the next sprite's table), not only frames an animation names:
    the head sprites are only ever named by `_Head` code.
  - Palettes: a multi-slot object palette keeps its extra slots; a frame
    piece's attr2 high nibble picks slot +k, and bitfield bit 0 makes it
    the fixed OBJ slot itself (Assets.spriteFrame).
- [x] **R7.1b Fixed-frame objects** (`ObjStatic.lua`): FURNITURE (frame and
  sprite offset from FurnitureCfg gUnk_08121EF8 and its nine per-type2
  tables, read from the ROM: MENU_DATA `furnitureCfg`), PUSHABLE_FURNITURE,
  MINISH_SIZED_ENTRANCE (+4 in dungeons), ARCHWAY / MINISH_SIZED_ARCHWAY
  (drawn over Link: collision layer 2), MASK, DOUBLE_BOOKSHELF, BOARD,
  WINDCREST, MINISH_LIGHT. HANGING_SEED (Minish Village) hangs with
  frameIndex = type and only waits to be cut.
- [x] **R7.1c Fusion bubble** (`FuseBubble.lua`, cameraTarget.c): over the
  current interactable with an offer in 1..100, after the 4-frame timer,
  animation 0 / +8 or 1 / -8 by the fuser's side of Link, y -18, hidden
  by a message, the Kinstone window or a running fusion. Its tiles are the
  two gfx slots the object loads (the piece icon gUnk_0811F744[bubbleIcon],
  then the bubble at $027820 of gGlobalGfxAndPalettes; MENU_DATA
  `fuseBubble` / `fuseBubbleIcons`): heart, rupee, "?", bottle.
- Checks: `tests/zelda_tmc_r7_parts_test.lua` 32 checks; scratch mode
  `r7_survey` (`TMC_ROOMS` / `TMC_AREAS`, `TMC_NPCSHOTS=1` shoots next to
  every NPC kind), sheets in `r7/survey/` and `r7/survey3/`: Hyrule Town's
  townspeople, kids, guards, maid, teacher, Festival crowd, Mountain Minish
  in Melari's mine, furniture in the house interiors (`r7/survey/crop2.png`);
  `r7_fusers`: Sheila's bubble (`r7/fusers/z.png`, the four icons in
  `icons.png`). Survey of areas $15 $01 $06 $10 $20-$23 $28 $26 $02: no
  NPC draws nothing; leftovers are CUCCO_CHICK_AGGR (minigame), FAIRY
  type $60, REMOVABLE_DUST (Mt. Crenel, R7.2), CABIN_FURNITURE,
  BAKER_OVEN, PAPER, LIGHTABLE_SWITCH, DUST.
- Not done: Business Scrub fusions (no scrub stands in the ported areas;
  businessScrub.c is not ported).
- [x] **R7.2a Mine carts** (`Minecart.lua`, minecart.c + the player's
  PL_ENTER_MINECART / PL_IN_MINECART).
  - gRoomTransition.minecart_data from sMinecartData ($080FCAF8, MENU_DATA
    `minecartData`), reset when Link comes into the Cave of Flames from
    outside; a MINECART object shows only in its entry's room, on the layer
    its rails are on.
  - Action1-7 as minecart.c: boarding after 8+ frames of pushing (not
    Minish, not carrying), the jump in (zVelocity 2.0, 1 px), landing when
    falling (SFX_137), riding at $700 on the frames Link's ANIM_MINECART
    byte has a non-zero low nibble, the per-direction act-tile lists
    (gUnk_081223D8: turn back on anything else), corners 103-106
    (Action4), ACT_TILE_100 ends it (Link jumps out forward, the cart turns
    round, its data saved), the room edge 8 px ahead takes Link and the
    cart into the next room (Action5; the cart persists), the Cane's hit
    hops it over (Action7, type2 ^= 4, SFX_13B / SFX_13C). The riding cart
    hits enemies it meets (damage 8); Link cannot be hurt in it.
  - Sprites on collision layer 2 now draw over the top BG layer
    (UpdateSpriteForCollisionLayer): Link and the cart on the rail bridges.
- [x] **R7.2b Cane of Pacci** (`Pacci.lua`): ANIM_CANE with the cane sprite
  (20, frame = Link's frameIndex + $6F, OBJ palette 4), the bolt on frame
  bit $40 (sprite 166, common OBJ tiles 57, animations 17 / 18 with the
  per-direction flips, start 18 / 14 px ahead, 2 px for $40 frames, hits
  with hurtType $1D, ends with animation $13 / SFX_199); a hole
  (ACT_TILE_25) holds the bolt for up to $1E0 frames.
  - Simplified: the spring out of a charged hole (40 frames in the hole,
    then over the ledge ahead or straight up; the ledge test is a short
    solid-tiles scan, not sub_0807A2F8's act-tile lists); not checked in a
    real room yet. Flipping pots (DoTileInteractionOffset type 10 /
    OBJECT_53) is not ported; enemies get the matrix's $1D hit only.
- Crenel bot (`crenel`, now drives the real B button and D-pad in room
  $02): 15 pass / 4 fail. New passes: the cane fires its bolt; the bolt
  flips the upside-down cart; Link boards it by pushing; the ride crosses
  into room $01; it ends at a track end with Link jumping out. Shots:
  `r7/crenel/crenel_cof_02_flipped.png`, `crenel_cof_ride.png`,
  `crenel_cof_ride_end.png`; `r7/cart/` (mode `r7_cart`: the swing, the
  bolt, the flipped cart, the ride over the lava).
  - Placement: Link is put beside the cart inside room $02 (the bot still
    warps between rooms to reach it; no end-to-end walk yet).
- Checks: `tests/zelda_tmc_r7_cart_test.lua` 17 checks (synthetic rails:
  hop, boarding, the corner, the end, Action6).
- [ ] Still failing in the Crenel bot, not ported: Melari's mine and the
  Grip Ring, the bean and Mineral Water, Gleerok (gleerok.c), the Fire
  Element after him. Not ported either: the Mole Mitts, the Cave of
  Flames' per-room code beyond what round 6 had, REMOVABLE_DUST.
- [ ] R7.3 (ChuChu boss phases, Pesto, barrel webs, follower hiding, lily
  pad suction / ripples) and R7.4 (figurine trading, file-select
  leftovers, attract demo): not started this round.
- **Final check (round 7):** tests core 42, online 23, rom 47, round2 27,
  round3 47, round4 20, r5_fx 34, r5_maps 12, r5_title 16, r5_kinstone 23,
  r5_boss 21, r5_macro 16, r6_fusers 38, r6_barrel 21, r7_parts 32,
  r7_cart 17; all pass. Deepwood route 24/24, 5513 frames. Crenel bot
  15/19.

## Round 8

Setup:
- Scratch outputs under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r8/`;
  `r8/r8check.sh` runs every src file, every `tests/zelda_tmc_*` file, the
  Deepwood route and the Crenel bot (log `r8/crenel/crenel_log.txt`).
  Scratch mode `r8_extract` rebuilds the harness cache.
- Cache version 8 (MENU_DATA `scrubTables`).

- [x] **R8.1a Climbing** (`Climb.lua`, hooks in Player): PlayerClimb with
  ladders ($53 / $F1), ladder tops ($3F, ANIM_CLIMB_FROM_TOP / _TO_TOP), climb
  walls ($50 / $51) behind the Grip Ring (without it Link is held at the
  tile's edge). Ladder tiles are solid in the collision data: Link lined up
  with one walks in (sub_0807AC54 snaps x). Shots `r8/climb/`.
- [x] **R8.1b Business Scrub** (`BusinessScrub.lua`, enemy $16): hide / pop
  out / seed / bounce back off the shield / stars / talk / buy, sales from
  the ROM. TextBox: `$06 $01` prints the price, `$07` continues with
  another message, `$05` markers make the yes / no choices. Scratch mode
  `r8_scrub`, shots `r8/scrub/` (the cartridge's texts, 40 Rupees, the
  Grip Ring get).
- [x] **R8.1c Bottles, Mineral Water, the Crenel bean** (`CrenelPath.lua`):
  ITEM_BOTTLE1..4 with contents (`save.bottles`), the swing catches
  MINERAL_WATER_SOURCE / water, pouring swaps SPECIAL_TILE_59 -> 60 and
  50 -> 51; CRENEL_BEAN_SPROUT types 0 / 1 / 2 / 3 (lift in 12:00, the
  bean in Link's hands outside, the throw into the hole, the 192-frame
  wait, the vine). Special tiles keep the cell's graphic (Room.setTile).
  Scratch mode `r8_bean`, shots `r8/bean/`.
- [x] **R8.1d Melari's Mines** (RoomCode $10:00 and $12:03, natives in
  CrenelPath): Melari's list, the Minish at the exit, the look-at and
  story lines, Melari's head, the broken sword (ITEM_QST_BROKEN_SWORD = 2),
  townMinish / drLeft animation calls, kid.c's calls, ShowNPCDialogue.
  Scratch mode `r8_melari`, shots `r8/melari/`: the scene from the
  cartridge's scripts with no missing native.
- [x] **R8.1e The Grip Ring** is the Business Scrub's in 26:04; the first
  bottle is the scrub's in 32:14 (Caves).
- [~] **The Mole Mitts** are not on the Crenel path: they are the big chest
  in the Outer Fortress of Winds (TileEntities_OuterFortressOfWinds_MoleMitts).
  Not ported (item use, digging).
- [x] **R8.2 Gleerok, simplified** (`BossGleerok.lua`, enemy $24): see
  minishcap.md "What differs". Gleerok's room draws BG1 (the lava) under
  the sprites and fades it at his death; lava (ACT_TILE_90 on either
  layer) sends Link back to safe ground. The fight manager's lists then
  give the Fire Element (LV2_CLEAR) and the heart container + warp point.
  Scratch mode `r8_gleerok`, shots `r8/gleerok/`.
- [x] **R8.3 (part)**: a scene cut off by a room change no longer leaves its
  script animation on Link (Field:enterRoom clears scriptAnim /
  scriptWalking when no player script runs).
- Crenel bot (`crenel`): 28 pass / 0 fail. New: the ladder climbed with
  the d-pad, the bottle and the Grip Ring bought from the scrubs (seed
  shielded back), Mineral Water caught, the bean lifted / thrown / watered
  / grown, the vine climbed into the room above through the real border
  exit (no warp), the climb wall scaled, Melari's scene, Gleerok beaten,
  the Fire Element, the heart container. Rooms are still reached by warp
  elsewhere (no path-finding bot yet).
- Checks: `tests/zelda_tmc_r8_crenel_test.lua` 43 checks.
- [ ] Not done this round: the Cave of Flames' per-room code and puzzles
  beyond round 6, flipping pots with the Cane, the charged-hole spring in
  a real room, gleerok.c's full neck / angle chain; R8.3's other leftovers
  (Big Green ChuChu / Pesto, barrel webs, follower hiding, lily pad suction
  and ripples, the objects that draw nothing); R8.4 (scrub fusions, online
  figurines, file-select leftovers, attract demo).
- **Final check (round 8):** tests core 42, online 23, rom 47, round2 27,
  round3 47, round4 20, r5_fx 34, r5_maps 12, r5_title 16, r5_kinstone 23,
  r5_boss 21, r5_macro 16, r6_fusers 38, r6_barrel 21, r7_parts 32,
  r7_cart 17, r8_crenel 43; all pass. Deepwood route 24/24, 5513 frames.
  Crenel bot 28/28.

## Bug round (user report)

Report: "can't open chests, pick up pots etc, crashes when I reach the
border of a town to another area when I walk through it, and don't have
the sword animation or sprite". Reproduced through the REAL runtime path:
a scratch identity imported through the launcher's worker (`launch/`
MODE=import, WANT=minishcap), then `ZeldaRuntime.boot("minishcap")` driven
only by `host:keypressed/keyreleased` and `host:gamepadpressed/released`
(title, name entry, file select, field). Harness, scripts and shots:
`G:/Gen2Recomped/scratch_claude/zelda/tmc/bugs1/` (`rt/` = the runtime
driver, `run.sh <script>`; scratch only, ROM-rendered).

- [x] **Chests (and talking, signs) with A.** Cause: `Player:update` sent
      interactions only through R (`Field:tryAction`); A only used the A
      item. The cartridge's `sub_080782C0` runs before the item buttons and
      takes `INPUT_ACTION | INPUT_INTERACT` (R or A). Fix:
      `Field:tryInteractA` (talk, dungeon big chest / key doors, chests,
      signs) called on an A press before the item loop
      (`Player.lua`, `Field.lua`, `Objects:tryAction(p, interactOnly)`).
      Lifting (`IsTryingToPickupObject`, `INPUT_LIFT_THROW`), portals and
      rolling stay on R, as on the cartridge. Verified in the runtime: A
      (Enter / gamepad A) opens a small chest in South Hyrule Field (item
      get + "You got..."), A talks to Zelda in the intro ("Hurry! Let's
      go!"), R (E / right shoulder) lifts a pot in a town house and throws it.
- [x] **Sword blade not drawn.** Cause: the port assumed the blade was part
      of Link's frames; it is the PLAYER_ITEM_SWORD entity attached to Link.
      Fix (`Player:swordPart/drawSword`): sprite by sword level
      (`gPlayerItemDefinition_0`: SPRITE_14 Smith's, 15 White/Red/Blue, 16
      Four Sword), OBJ palette 1, frame = Link's frameIndex - $6A
      (`sub_080A78B8`), flipX = Link's entity flipX XOR (facing sideways),
      over Link when Link's frame byte unk_1 is set, behind otherwise
      (`sub_08078E84`). Shots of all four swings (`shots/sd_all.png`).
- [x] **Link never faced left** (found with the sword shots): the side
      animations carry the keyframe flip for both sides; `sub_08079064`
      also sets the entity's `spriteSettings.flipX` when animationState >= 5
      and the drawer XORs the two. `Player:setAnim` now keeps `entFlip`,
      `Player:hflip()` draws with it. The sword's tile probe mirrors on the
      entity flipX (`sub_080A7A84`), so cutting grass to the RIGHT used to
      probe the left; its hitbox mirrors only for a right swing (the table's
      side frames face left) (`Items.lua`). Verified: grass cut to the right,
      up, down and left in South Hyrule Field / Minish Woods.
- [x] **Could not leave Link's house on a new game.** The door tile is
      solid and there is no area warp beyond it; the room's exit is a south
      BORDER warp to South Hyrule Field ($03:$01 at (656, 412)).
      `Field:doorExit` now falls back to the border warp on the side Link
      pushes. Verified: new game from the title -> upstairs -> downstairs ->
      out the door -> Zelda's "A! Over here!" -> town.
- [x] **A pot carried through a door stayed over Link's head forever**
      (state back to normal, `carried` kept). `ClearPlayerState` drops the
      held object on a room change; `Field:enterRoom` clears `carried`.
- [ ] **Border crash: not reproduced in The Minish Cap.** Scripted
      crossings of every open lane on every edge with a border warp, walking
      with real key events, `host.error` checked after each:
      new-game flags 104/108 lanes, mid-game (sword, EZERO_1ST, TABIDACHI)
      103/108, after the intro walk-out (incl. Festival Town $15) 46/53,
      after SAVE GAME from the runtime menu + reboot + CONTINUE 48/49, with
      audio on (music change at the area border) and while carrying a pot.
      0 errors; the misses are walls/ledges (Mt. Crenel ledges, beanstalks).
      Interiors/dungeons ($0E-$8F) found 0 errors too but most lanes there
      are behind room-code input locks, so that sweep is thin. The crash
      may be the ALttP one; if it is Minish Cap, a save file or the exact
      spot would pin it.
- [x] **Errors keep the app alive** (real path): an error raised inside
      `Field:enterRoom` during a border crossing lands on the runtime's
      error screen ("The Legend of Zelda: The Minish Cap stopped (update)"
      + traceback), Enter returns to the launcher (`shots/err_screen.png`).
      `love.threaderror` in main.lua already logs worker errors (audio).
- Shared runtime: no change needed; keyboard A = Z/Enter/Space, B = X/
  Backspace, R = E, L = Q, gamepad shoulders = L/R, all reach the game as
  fresh presses (checked).
- Tests: `tests/zelda_tmc_bugs1_test.lua` (19 checks, fake data); all
  `zelda_tmc_*` tests pass; Deepwood route bot 24/24, Crenel bot 28/28
  (`r8/r8check.sh`).

## Round 9

Setup: scratch outputs under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r9/`.
Real-runtime driver `r9/run.sh <script>` (the bugs1 `rt/` boot, real key
events, shots in `r9/shots/`), route log `r9/route_log.txt`, checkpoints
`r9/ck/*.lua` (save tables written by the route, loaded with
`Game:startGame`). `r9/import.sh` re-imports the scratch identity through
the launcher worker. Patches go through `r9/sp.py` (safepatch).
Cache version 10.

- [x] **R9.1a Zelda follows into town.** Cause: sub_unk3_HyruleTown_0 was
  not ported. At global progress 1 Hyrule Town is swapped for the festival
  town ($15) before the room loads, ZELDA_CHASE is set, Link starts at the
  middle of the room's width, and the festival room takes the town's world
  position (map_x + $130) so its border exits land right (`Field:enterRoom`).
  "Hurry! Let's go!" (TEXT_PROLOGUE $14) itself only sets SOUGEN_01_ZELDA on
  the cartridge; ZELDA_CHASE comes from that room swap. The festival tour
  (script_ZeldaIntroTown / Npc4EIntroTown, Pina, the shield) now runs to its
  end and hands Zelda back to the follower.
- [x] **R9.1b USA flag ids.** flags.h has EU/JP-only entries under `#if`;
  several ids had been counted with them: SOUGEN_01_ZELDA $6D (was 112, so
  Zelda's list reloaded forever), SOUGEN_08_TORITSUKI $9C (was 160:
  progress 4 never came), SEIIKI_STAINED_GLASS $78, SOUGEN_05_BOMB_00 $79,
  MORI_ENTRANCE_1ST $3E, MORI_00_KOBITO $3B, MACHI_07_BELL $D0. Checked
  against the scripts' SetLocalFlag bytes (`r9/flagval.py` counts the USA
  enum).
- [x] **R9.1c Draw order.** ResolveOamDrawPriority (asm/src/intr.s): key =
  (~spritePriority.b0 & 7) << 29 | (y + $80000000) >> 3; b0 4 by default.
  `Field:drawEntities` sorts on it with a fixed tie order (the old
  `table.sort` on y alone was unstable: Link and Zelda on one line flickered).
- [x] **R9.1d The red rupees by Link's house** are on the cartridge
  (Entities_HyruleField_SouthHyruleField_0: six RUPEE20 at $278-$298 /
  $188-$198) but they are ItemOnGround kind 7, buried (draw 0, shown once
  the tile under them is dug). The port showed them as loose rupees; it now
  reads the kind (entity->timer = paramB >> 8): buried and sunken items are
  hidden.
- [x] **R9.1e Script MoveTo arrival** (ScriptCommand_MoveTowardsTarget)
  compares whole pixels; with sub-pixels script_PlayerIntro4 circled its
  spot forever. **The message box reads the pad, not a player macro**
  (the TryOutShield macro runs under message $2C).
- [x] **R9.1f Link's own collision** (asm/src/player.s sub_080085CC /
  sub_080086D8): seven state tables ($080082DC normal, Minish, swimming,
  jumping, carrying, beetles) into 40 masks (gUnk_0800823C), bit 15 - x.
  The port used IsTileCollision's type-0 table, which made the town /
  festival castle stairs (value $29) solid and some walkable values ($30)
  solid. `Room:isSolidPlayer`, used by `Player:blocked`.
- [x] **R9.1g Castle Garden room code** (sub_StateChange_CastleGarden_Main).
- [x] **R9.1h The sword ceremony** (`Ceremony.lua`): the C helpers the
  castle scripts call (guard.c sub_08064050, the guards' / maid's wander
  sub_0806407C / sub_080646A4, sub_08064180, the cutscene objects
  sub_08095244 / 08095330 / 08095364 / 08095420 / 0809545C / 08095810 with
  their ROM scripts, CheckEntityOnScreen, CheckAnyKeyPressed, the white
  fill sub_0807FB28, NPC4E Save/RestoreEquippedItems, DeleteHitbox,
  sub_0804BCDC = the warp to Hyrule Castle room 4); HyruleCastle_4 (Link
  wakes up, script_PlayerWakingUpInHyruleCastle) and HyruleCastle_2 room
  code. The tournament, Vaati and Link fainting run to the end from the
  cartridge's scripts (texts PROLOGUE $36-$4A).
- [~] **R9.1i New-game route, real runtime** (`r9/s9_route.lua`, segments
  `seg_a/b/c.lua`, log `r9/route_log.txt`): 10 PASS / 1 FAIL in one run
  from the title with real key events: new file, Link's house, Zelda's walk
  in South Hyrule Field, the festival town with ZELDA_CHASE, the festival
  tour to Pina and the shield, the castle stairs, North Hyrule Field, the
  Castle Garden, the ceremony, waking in the castle, getting up.
  **Blocker:** Hyrule Castle room 4 has no exit list (gExitList_NoExitList)
  and its walls are closed for Link; the way out to the assembly (room 2)
  is not found yet (maybe the door on the east wall, act tile $2D). Not
  reached: the assembly and the Smith's Sword, the Minish Woods, Ezlo, the
  Minish Village, Deepwood (the direct-harness Deepwood route still runs
  from a mid-game save). Natives still missing on the way (counted, no
  flow stop): $08063C14/2C/44/5C/74 (Pina scene visuals), $0807F584,
  $0807F5B0, $08094CDC/D10/D34.
- [x] **R9.2 Drops follow the cartridge** (`Drops.lua`, user request):
  - CreateRandomItemDrop with every table kind: enemy 1-12, area 15,
    object 16-23 (object table + area table), health 24/25; the s16 sums,
    the low-health / no-bombs / no-arrows / low-rupee bonuses, the
    all-figurines / all-fusions modifiers, the clamp, the walk from slot
    (r >> 24) & 15.
  - Random() is the cartridge's (ror32(s * 3, 13) >> 1, seed $1234567).
  - CreateItemDrop's gates (bag, bow, Earth Element, Kinstone bag, more than
    3 Kinstone drops the frame before, beetles as an enemy with the Smith's
    Sword), Kinstone pieces from gUnk_080FE1DD.
  - The area table honours LOCATION_CHANGER / GRASS_DROP_CHANGER tile
    entities; DisableRandomDrops / EnableRandomDrops are natives.
  - Sources: grass is FX_GRASS_CUT (table 16 after its Random() & 3
    variant), bushes FX_BUSH (17), pots FX_POT_SHATTER (19) or their fixed
    item, thrown bushes FX_BUSH; was the area table (15) for all of them.
  - The ground item: rise (zVelocity 1.875, gravity 40/256) to the apex,
    BounceUpdate with the item's bounce sound, collision on only from the
    apex, 600 frames then gone, blinking every frame under 90, paused while
    a message / scene runs; pickup box 8 px each way and 10 px of height,
    then the 14-frame hop over Link's head.
  - Checked: `tests/zelda_tmc_r9_drops_test.lua` (41 checks: Random
    against Python values, 14400 seeded rolls against a line-by-line
    transcription of the C, gates, tile entities, the item's timings), and
    the real runtime `r9/s9_grass.lua`: 20 tiles cut with the sword key,
    drops seen, a blue rupee picked up (0 -> 5), every drop gone after 600
    frames; shots `r9/shots/g_drop_air.png`, `g_pickup_hop.png`.
  - Not exact: the cartridge also calls Random() from everything else each
    frame, so a given cut's result is not the same as on hardware; the
    odds and rules are. Picolytes and figurine completion are not ported.
- New tests: `tests/zelda_tmc_r9_coll_test.lua` (10 checks: Link's tile
  tables, whole-pixel MoveTo).
- Bots and tests after these changes: all `zelda_tmc_*` tests pass,
  Deepwood route 24/24, Crenel bot 28/28 (`r9/r8check_out.txt`).

## Round 10

Setup: scratch outputs under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r10/`.
`r10/run.sh <script>` is the real-runtime driver (a copy of bugs1 `rt/`
with vsync off, real key events, shots in `r10/shots/`); `r10/import.sh`
re-imports the scratch identity through the launcher worker;
`r10/r10check.sh` runs every src file, every `tests/zelda_tmc_*` file, the
harness cache rebuild, the Deepwood route and the Crenel bot.
The route is `r10/s10_route.lua` (segments `seg_a.lua` .. `seg_l.lua`,
checkpoints `r10/ck/*.lua`, log `r10/route_log.txt`); `lib_r10.lua` adds
a room-to-room navigator (exits, border lanes, map adjacency and doors,
SPECIAL_WARP regions), cut-aware path finding (4 px grid at Minish size),
fighting at full size and enemy avoidance at Minish size.
**Cache version 11** (`ExtractR10.lua`: manifest.r10).

- [x] **R10.1a Leaving the castle bedroom.** Room 4's west wall has a door
  (metatile $3C1, ACT_TILE_41) at row 8; the room has no exit list
  because the door leads to the next room of the area by map position
  (room 2 ends where room 4 begins). The port already handled that
  (`Field:doorExit` -> `adjacentRoom`); round 9's bot looked for an open
  lane. The assembly then runs from the cartridge's scripts.
- [x] **R10.1b The assembly.** `$0807F238` SetPlayerAnimation2,
  `$0807F918` PutItemAnySlot (addresses read from the ROM's thumb code),
  kingDaltus.c sub_0806673C, npc4E.c sub_0806DCC0. GiveItem now calls
  the cartridge's PutItemOnSlot (A if empty, else B, else the button with
  the same menu slot; only items 1-$1F): the festival shield lands on A,
  the Smith's Sword on B, and ITEM_QST_BROKEN_SWORD ($35) is never
  equipped (it used to take the A button, leaving the sword unequipped).
- [x] **R10.1c Whole-pixel walls.** A blocked step moves Link to the last
  free whole pixel (`Player:moveBy`): he no longer stops at y 524.75 a
  pixel short of the Castle Garden's south border.
- [x] **R10.1d Out of the castle to the woods.** Hyrule Town stays the
  festival town (north exit only) until LV1_CLEAR, so the route goes North
  Hyrule Field -> Lon Lon Ranch -> Eastern Hills North -> Minish Woods (the
  west way has the broken bridge).
- [x] **R10.1e Ezlo.** CUTSCENE_MISC_OBJECT $13 / $14 (the Octoroks' rocks,
  offsets gUnk_08122AF8 from the ROM), SetAnimation reaches dressed objects,
  scripted objects animate, SetPlayerActionNormal ends a player script,
  ezlo.c sub_0806D8A0 / D908 / D944 / D96C / D9A4, npc4E.c sub_0806DC7C /
  DCA0 (the Octorok pen, gUnk_081141F4 from the ROM), DeleteAllEnemies,
  WaitForPlayerNormalOrTalkEzlo, sub_0807F5B0, ResetPlayerFlag ($0807F6F8,
  PL_NO_CAP -> Ezlo worn), NPC flipX drawn.
- [x] **R10.1f Portals.** `PortalJump.lua`: 6 frames into ACT_TILE_61 jump
  onto the portal, R shrinks there; Minish Link uses the manager's 64x64
  box (portal_mode 3) and grows standing on the stump; a held direction
  hops off.
- [x] **R10.1g The Minish Village.** `SpecialWarp.lua`
  (SPECIAL_WARP_MANAGER: the Minish Paths, the village and the Deepwood
  Shrine Entry regions), Forest Minish scripts by type2
  (gUnk_08109D18 from the ROM), forestMinish.c sub_08060158 (facing only),
  the barrel Minish's room code (`RouteRooms.lua`), CUTSCENE_MISC_OBJECT
  type 7 (the Jabber Nut: Ezlo's hint, then the item get), the Minish
  houses' 256-colour special BG screens (`SpecialBg.lua`), Minish Link's
  smaller box against NPCs, a game saved at Minish size continues at
  Minish size, checkable objects answer A from 24 px.
- [x] **R10.1h The route, one run from the title** (`r10/s10_route.lua`,
  real key events): see the final check below for the PASS / FAIL list.
  Shots: `r10/shots/d1_throne.png`, `d2_assembly_end.png`,
  `e1_north_field.png`, `f1_woods.png`, `g1_first_look.png`,
  `g3_ezlo.png`, `h0_on_stump.png`, `h1_minish.png`, `h3_village.png`,
  `i1_village_intro.png`, `j1_festari.png`, `j3_jabbernut.png`,
  `k1_gentari.png`, `k2_festari.png`, `l1_grown.png`, `l3_entry.png`,
  `l4_deepwood.png`.
- [ ] **R10.1i Ceremony visuals**: not done (the cutscene objects' own
  movement, Zelda's magic, the flash as the cartridge draws it).
- [~] **R10.2 Cave of Flames**: only the Cane's pot flip (pot.c
  Pot_Action1 contact $1D / Pot_Action5: hop at zVelocity 2.625, gravity
  1/8, upside down on the way down, BreakPot on landing); real-runtime
  shots `r10/shots/pf_air.png`, `pf_turned.png`, `pf_after.png`
  (`r10/p_potflip.lua`). Not done: the per-room code and puzzles, the
  charged-hole spring as player.c does it, mine-cart links, gleerok.c.
- [~] **R10.3 Leftovers**: the Zelda follower re-joins Link where he comes
  back from a fall (sub_08068318's FALL / DROWN reset). Not done: Big
  Green ChuChu phases, Pesto, burnable webs, lily pads, objects that draw
  nothing, Picolytes (and the barrel Minish's DRUG lists).
- [ ] **R10.4**: not started.
- Tests: `tests/zelda_tmc_r10_test.lua` (33 checks, fake data).
- Also fixed on the way: special BG screens wider than 256 px use the two
  side-by-side screen blocks (Festari's house, 464 px wide).
- **Final check (round 10):** all 21 `tests/zelda_tmc_*` files pass
  (r10 33 checks); every `src/zelda/tmc` file compiles; harness cache
  rebuilt at version 11; Deepwood route bot 24/24 (5513 frames); Crenel
  bot 28/28 (8084 frames) (`r10/r10check_out.txt`). The new-game route
  `r10/s10_route.lua`, one run from the title with real key events:
  **28 PASS / 0 FAIL**, 39081 frames, no runtime error
  (`r10/route_log.txt`, `r10/out_s10_route.txt`). Round 9's
  `r9/s9_route.lua` is superseded by it (its C3 step searched the west
  wall for an open lane and so could not find the door).

## Round 11

Setup: scratch outputs under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r11/`.
`r11/run.sh <script>` is the real-runtime driver (round 10's `rt/`, real
key events, shots in `r11/shots/`); `r11/import.sh` re-imports the scratch
identity; `r11/r11check.sh` runs every src file, every `tests/zelda_tmc_*`
file, the harness cache rebuild and the old Deepwood / Crenel bots.
The route is `r11/s11_route.lua` (round 10's segments a..k, then r11's
`seg_l.lua`, `seg_m.lua`, `seg_n.lua`; `lib_r11.lua` + `lib_dw.lua`;
checkpoints `r11/ck/*.lua`; log `r11/route_log.txt`).  `s_m.lua` /
`s11_seg.lua` run segments from a checkpoint (`CK=... SEGS=...`).
**Cache version 12** (`ExtractR11.lua`: manifest.r11).
Gotcha: a probe that dies and taps through the game-over screen saves the
scratch identity's slot 1, and the next route run then continues that
file instead of a new one (`r11/savebak/` holds the one moved aside).

- [x] **R11.1a Minish Link's sword.** The decomp settles it the other way:
  itemSword.c sub_08075338's PL_MINISH branch only sets ANIM_SWORD_MINISH
  and returns; sub_08077B98 (which makes PLAYER_ITEM_SWORD) is never
  called, so Minish Link's swing has no hitbox and cuts nothing.  The
  port now matches (`Items:swordFrame`).  What does change as Minish is
  the contact rule: PlayerMinish sets hurtType 1, and gCollisionMtx's
  hurtType-1 row is CollisionNoOp for most enemies (Link passes through
  them) while an idle ChuChu (hitType 92) only pushes (handler 16,
  sub_08018228).  ChuChus hurt Link only while they jump (chuchu.c
  hitType 90), Minish or not.  So clearing the corridor's ChuChus at full
  size (L2) is what a player does; it is not a workaround and stays.
- [x] **R11.1b Hitboxes from the ROM** (`ExtractR11.lua`,
  `Hitboxes.lua`): gPlayerHitbox $08114F88, sMinishHitbox $0811BC80,
  gNPCHitboxes $08114EE4, gObjectHitboxes $08125104, the statue's
  $080FD1F4.  Solid NPCs are the 39 ids whose code calls sub_0806ED78;
  they push Link out (CalcCollisionStaticEntity: smaller overlap, <= 4 px
  a frame, PlayerCanBeMoved) instead of blocking him.  Forest Minish,
  Gentari, Zelda, Ezlo are not solid.  Real runtime: walked through a
  Forest Minish, stopped by Festari exactly at the boxes' edge (14 px).
- [x] **R11.1c The A interaction test** (sub_080784E4): Link's position +
  gPlayerInteractHitboxOffsetNormal / Minish ($0811C00C / $0811C014) must
  fall in the candidate's box (no hitbox offset, -w <= d < w).  The Jabber
  Nut (CUTSCENE_MISC_OBJECT 7, gHitbox_3 12x12) is an INTERACTION_CHECK:
  full size only.  The bot's talkTo now picks spots by this test.
- [x] **R11.1d The portal jump's steps** (`PortalJump.lua`): DoJump's
  sub_08073968 (ANIM_HOP, SFX_PLY_JUMP), sub_080739EC (GravityUpdate,
  kGravityRate), sub_08073AD4 (ANIM_LAND, SFX_PLY_LAND), sub_08073A94
  (stand once ANIM_LAND is done); the move toward the portal follows
  CalculateDirectionTo at kJumpSpeedForward.  The hop off
  (sub_080740D8) moves while the probe on the hitbox edge ahead is on the
  solid stump, then probes behind (subtimer 1) until Link is clear.
  Real runtime (`r11/p_m1.lua`): z 2.0 -> apex 17 -> landing at frame 40,
  ANIM_LAND 6 frames, stand; the hop off ends 27 px south.  Shots
  `r11/shots/m1_jump_air.png`, `m1_jump_land.png`, `m1_hopped.png`.
- [x] **R11.1e The Forest Minish look table** gUnk_08109C98 ($08109C98)
  in sub_08060158: the head / body frame bytes are set directly
  (frameDuration $F0), the body turns on frameIndex bit 7.  Shots
  `m1_minish_look_w.png`, `m1_minish_look_e.png`.
- [x] **R11.1f PlayerFall** (`PlayerFall.lua`): SnapToTile, ANIM_FALL
  (Minish / no-cap variants), SFX_PLY_VO7 + SFX_FALL_HOLE, respawn when the
  animation is done, iframes 32, kFallDamage 2; the Zelda follower keeps
  taking Link's position while he falls (framestate FALL) and re-joins
  him after.  Checked in `tests/zelda_tmc_r11_test.lua`; a real-runtime
  fall was not shown (no plain pit was found on the route's rooms; the
  Cave of Flames pit found is a Cane hole with a repeating hint).
- [x] **R11.1g Route** (`r11/s11_route.lua`): see the final check.
- [~] **R11.2 Deepwood Shrine through the real runtime** (`seg_m.lua`,
  `seg_n.lua`), from the round-10 end:
  - M1 the entrance statue pushed aside (pushableStatue.c: speed $80 for
    $20 frames, pushing Link out of gUnk_080FD1F4; it used to slide over
    Link and trap him), north into room $10;
  - M2 the four buttons -> flag $4D -> the small key (chest from the
    south);
  - M3 the key door north into room $0A (Lever);
  - N1 the PULLABLE_LEVER ($54, `Lever.lua`) pulled 32 px -> room flag 0 ->
    FLAG_AND -> local $32 -> the BRIDGE manager lays the bridge to the
    island (shots `m3_lever_pulled.png`, `m3_bridge.png`);
  - N2 the PULLABLE_MUSHROOM ($32, `Mushroom.lua`) on the island: R to
    grab, pull east to a $40 stretch, let go: Link flies back over it and
    west over the water (zVelocity $40 << 12, speed $200) and lands on the
    west bank (shots `m3_mush_pull.png`, `m3_mush_fly.png`);
  - N3 the north door into room $06 (Barrel).
  Also ported on the way: pushable block tiles (ACT_TILE_112, $360-$364
  with their one-way rules, PUSHED_BLOCK, `PushBlock.lua`); collision
  layer changes (gTransitionTiles $08016AB4, `Layers.lua`: Link on the
  barrel room's raised alcoves collides with and draws over the top
  layer; he used to be hidden under it); the barrel room's side buttons
  while Link is in the room (bigBarrel.c Type4 tile, the web / log
  timings); a door with no warp of its own leads on only through the edge
  it sits on (the door Link came in by sent him straight through the next
  room); the bot's path finder keeps off water, holes and lava.
  **Not done:** the rest of Deepwood (the barrel interior and quadrants,
  Madderpillar and the Gust Jar, the B1 lily-pad rooms, the keys, the big
  key, the webs, the boss door), the Big Green ChuChu port (chuchuBoss.c:
  four affine parts, twelve sub-actions, three phases; still the round-3
  simplification), the Earth Element, back to the Elder, the Crenel
  route.  The bot also lacks a safe fight / avoid plan for Puffstools and
  Sluggulas at three hearts (it died to a Puffstool in room $06).
- [ ] **R11.3 Cave of Flames**: not started.
- [ ] **R11.4 Leftovers**: not started (the barrel webs now burn on the
  button, see R11.2).
- Tests: `tests/zelda_tmc_r11_test.lua` (43 checks, fake data);
  `tests/zelda_tmc_r10_test.lua`'s portal checks updated for the landing
  animation and the hop's probe.
- **Final check (round 11):** all 22 `tests/zelda_tmc_*` files pass (r11
  43 checks); every `src/zelda/tmc` file compiles; harness cache rebuilt
  at version 12; old Deepwood route bot 24/24 (5561 frames), Crenel bot
  28/28 (8084 frames) (`r11/r11check_out.txt`).  The new-game route
  `r11/s11_route.lua`, one run from the title with real key events:
  **34 PASS / 0 FAIL**, 57538 frames, no runtime error, ending in Deepwood
  room $06 (`r11/out_s11_d.txt`, `r11/route_d_summary.txt`; shots
  `r11/shots/m2_room10.png`, `n2_flung.png`).

## Round 12

Setup: scratch outputs under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r12/`.
`r12/run.sh <script>` is the real-runtime driver (round 11's `rt/` with a
1 ms sleep a frame; lovec runs at below-normal priority, one at a time,
and the scratch identity's slot 1 is reset to `r12/slot1_pristine.lua`
before every run, so a probe that died through game over cannot leak into
the next run).  `r12/import.sh` re-imports the scratch identity.  The
route is `r12/s12_route.lua`: round 11's 34 steps with round 11's helpers,
then `seg_o.lua`, `seg_p.lua`, `seg_q.lua` with the round-12 bot
(`lib_r12.lua`, `lib_fight.lua`, `lib_dw12.lua`); `s12_seg.lua` runs
segments from a checkpoint (`CK=... SEGS=...`); checkpoints in `r12/ck/`
now keep Link's collision layer (`*.layer`).
**Cache version 13** (`ExtractR12.lua`: manifest.r12).

- [x] **R12.1a Deepwood enemies from the decomp** (`EnemyDeepwood.lua`):
  Puffstool (puffstool.c, all 13 actions, the spot search, the double hop
  that withers grass, the Gust Jar draining spores, bare / spored hit
  types $82 / $83 and palettes $28 / $7C), Sluggula (sluggula.c: hanging,
  the drop, the landing frames, type 1 crawling with slime and turns,
  type 2 slime), Mulldozer (mulldozer.c: stand, walk, wind-up, $1E0 charge
  with the weave, the turn after a hit, the spin off a shield).  Damage,
  knockback and iframes come from the collision matrix (spored Puffstool
  hurts 2, shrugs the sword off with SFX_186; bare it only pushes Link
  and dies to one hit; Sluggula 2 hits; Mulldozer 3).  Drops are the
  existing DeathFx tables.  Pesto and ChuChu (type 0) keep the earlier
  models.
- [x] **R12.1b The bot fights and avoids** (`r12/lib_fight.lua`): paths
  around unbeatable foes (spored Puffstools without the Gust Jar) and under
  hanging Sluggulas, re-plans every 30 frames, swings at beatable ones,
  never steps into water or toward a doorway / room edge by accident
  (exits go through `H.exitTo` / `H.walk` only), picks up drops.
  Real runtime: room $06's three Puffstools passed at no damage, room $05's
  Mulldozer killed at no damage (`out_s12_route.txt`).  Not solved: room
  $03's two Sluggulas drop on the way in and still cost 2-4 hits.
- [~] **R12.2 Deepwood through the real runtime** (thonky.com's route
  order; `seg_o/p/q.lua`):
  - O1 room $06 east button -> fuse; O2-O3 into the barrel by its SE door
    and out NW (the barrel lines the NW door up without rolling); O4 the
    west alcove statue pushed onto one button, Link on the other (flag
    $15); O5 both webs burnt, the barrel rolled (bot `H.barrelExit`,
    rollingBarrelManager.c's ranges and boxes) and left by the SW door; O6
    west into $05.  Shots `o1_fuse_east`, `o2_barrel_in`, `o4_fuse_west`,
    `o5_sw`.
  - P1 Mulldozer; P2 the mushroom flings Link north over both pools; P3 the
    map from the big chest (up the raised walkway, layer 2); P4 the
    walkway's south end is a ledge: Link jumps off it (`Ledge.lua`); P5 a
    short fling lands on the strip between the pools; P6 west into $03.
    Shots `p3_map`, `p4_ledge_air`.
  - Q1 room $03's pot pushed eight tiles east onto the held button lays
    the bridge; Q2 south into $04; Q3 the west statue pushed onto its
    button, the east one pulled out, then pulled back in twice from inside
    (`StatuePull.lua`); Q4 the small key.  Shots `q1_pot`, `q3_pulled`,
    `q4_key`.
  **Not done:** the rest of Deepwood (the key door east of $06, rooms
  $07-$09 and their fight key, $01/$02, Madderpillar and the Gust Jar
  through the real runtime, the barrel web and B1's lily pads, the big
  key, the entrance webs, the boss door), the Earth Element through the
  real runtime, back to the Elder.
- [ ] **R12.2b chuchuBoss.c**: not ported (read through; the four parts,
  the Helper struct, sub-actions 0-11 and the affine jelly are mapped in
  this round's notes but no code was written).  The round-3 simplification
  stays.
- [x] **R12.3a Push / pull frame flags** (`PushAnim.lua`): walking into
  a wall for 7 frames starts ANIM_PUSH (sub_080790E4); blocks, statues and
  pots move only on its keyframes with flag bit 0 (sub_0801A4F8); the lever
  and statue pulls only on ANIM_PULL's keyframes with flag bit 1
  (pullableLever.c reads frame & 2).  Pots are pushable (Pot_Action1 /
  Pot_Action4: $80 for 32 frames) and Link leans on a pot's whole tile.
- [x] **R12.3b Also ported on the way:** ledge jumps (gUnk_0811C1E8,
  PlayerJump, ResetCollisionLayer), statue pulling, ResolveCollisionLayer
  for room objects with no layer of their own (the room $06 alcove statue
  sits on the raised floor), the statue's per-area gfx (gUnk_08120CCC; its
  OBJ palette 5 is still black, see minishcap.md).
- [ ] **R12.3c** The mushroom stem, the ceremony objects' motion and the
  real white flash: not done.  Fuse flames: not drawn (timings kept).
- [ ] **R12.4** Mt. Crenel route, Cave of Flames, Pesto / lily pads /
  Picolytes: not started.
- Tests: `tests/zelda_tmc_r12_test.lua` (37 checks, fake data);
  `tests/zelda_tmc_r11_test.lua`'s lever check now feeds ANIM_PULL's frame
  flag.
- **Final check (round 12):** all 23 `tests/zelda_tmc_*` files pass (r12
  37 checks); every `src/zelda/tmc` file compiles; harness cache rebuilt
  at version 13; old Deepwood route bot 24/24 (5449 frames), Crenel bot
  28/28 (8084 frames) (`r12/r12check.sh`).  The new-game route
  `r12/s12_route.lua`, one run from the title with real key events:
  **50 PASS / 0 FAIL** (round 11's 34 + O1-O6, P1-P6, Q1-Q4), 66537
  frames, no runtime error, ending in Deepwood room $04 with the second
  small key, 14/24 health (`r12/out_s12_route.txt`,
  `r12/route_log_final.txt`).

## Round 13

Setup: scratch outputs under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r13/`.
`r13/run.sh <script>` (round 12's driver: one LÖVE at a time, below-normal
priority, 1 ms sleep a frame, slot 1 reset), `r13/import.sh`,
`r13/r13check.sh` (harness cache rebuild, old Deepwood bot, Crenel bot).
Helpers: `lib_r13.lua` (= r12's libs + `lib_fight13.lua` + `lib_r13x.lua`:
checkpoints in `r13/ck` falling back to `r12/ck`, `H.grid` / `H.roomPng`
dev views, `H.equipItem` (pause menu with real keys), `H.madder`,
`H.smashPots`, `H.barrelTo`, `H.jarBlow`, fixed `barrelExit` / `fling2`).
`s13_seg.lua` runs segments from a checkpoint (`CK=… SEGS=…`, dev-only
`CKPOS` / `CKHP`).  The route is `r13/s13_route.lua`.
**Cache version 14** (`ExtractR13.lua`: manifest.r13, the hole table).

- [x] **R13.1 Object palettes.**  LoadRoomTileSet copies BG palette 3 into
  OBJ palette 5 after every tileset load
  (`MemCopy(&gPaletteBuffer[0x30], &gPaletteBuffer[0x150], 0x20)`), and
  LoadMapData follows each tileset palette group with sub_080533CC (OBJ
  palette 2's colours 0-4 into BG palette 2).  `Assets:areaPalettes` now
  does both; `Assets:objPalette` takes id 5 from the room's buffer, id $15
  as the MemFill16 of BG 3's 12th colour (it was black), ids 6-$14 from
  the room's BG palettes, and the field's current room when a caller
  passes none.  Room-dependent palettes carry a key so sprite images are
  not reused across areas.  Statues (and every object / NPC with palette
  5: object ids 7, $0F, $11, $1B, $1C, NPCs 7, $1B, $27, $2B, projectile
  $1F) are no longer black.  Shot `r13/shots/pal_room04.png`.
- [x] **R13.2 The Gust Jar from the decomp** (`GustJar.lua`, the cone is
  gone): itemGustJar.c's states (pull-out, charge SMALL / MID after $77 /
  BIG after $EF, blow, end), the PLAYER_ITEM_GUST chain (type 0 at
  gUnk_08126EE4, types 1-3 running out 12 / 16 / 16 px, boxes 4 / 9 / 9 /
  14, stopped by walls, not by water), contact through the collision
  matrix (gust hurtType $13, handler 4 = sub_08017B58: tolerance by the
  charge, then sub_0806F3E4's pull to the mouth; gustJarFlags 2 enemies
  are caught and carried by PLAYER_ITEM_GUST_BIG, 86 frames at $400),
  the charged puff (timer $10 / $20 / $40, damage 2 / 3 / 6), Link pushed
  back at $80 while blowing (not on a lily pad), the wind sounds.  Webs,
  the barrel's web and lily pads now need a gust box to touch them.  Real
  runtime: web in room $00 torn (`gust_web.png`), puff (`gust_puff.png`).
- [x] **R13.3 HOLE_MANAGER and the barrel's bottom** (`Holes.lua`,
  `Barrel.lua`): gHoleTransitions ($08108764) from the ROM; a pit inside
  a hole manager's box is an exit (PL_PIT_IS_EXIT): PlayerFall ends in a
  transition to the table's room / position / layer.  BARREL_SPIDERWEB
  ($36): y = $170 - the barrel's angle, 120 frames of suction set
  LV1TARU_OPEN (gfx $4A / $49 swapped while sucked), then pulled to Link;
  sub_08058A04's open-bottom test drops Link into B1 room $14 at ($E8,
  $C8), layer 2.  Shots `s4_suck.png`, `s5_b1.png`.
- [x] **R13.4 Also:** locked doors of type $80 shut again when their flag
  clears and Link is inside (LockedDoor_Action7 / Action3, room $09's
  north door); lily pads float, drift and ride currents on their own
  collision layer (B1's pools are on BG1) and are sucked toward the jar
  from the bank (lilypadLarge.c, $200 / $300 / $400 by the charge).
- [~] **R13.5 Deepwood through the real runtime** (`seg_r1..r5`,
  `seg_s1..s2`), continuing from round 12's room $04:
  - R1-R2 back through $03 (the pot comes back on its button: room $04's
    region trigger sets local $26 for moveableObjectManager), $05 (the
    pushable block in the east column's neck), the barrel from its SW
    door to NE, the east key door (flag $2A) into $07;
  - R3-R6 room $07: a short mushroom fling over the upper pool (lands at
    about twice the stretch), the button lays the bridge (local $2D), a
    second fling over the lower pool, pots for hearts, east into $09;
  - R7-R10 room $09: the corridor is one tile tall and the ring joins its
    ends: the east statue pulled three tiles past the button, round the
    ring, the west statue pushed five tiles onto it, Link ends under the
    north door; room $08: the region trigger starts the fight, two
    Mulldozers, the falling key (local $2F, $53);
  - R11-R14 out by $08's west door, up $07's stairs onto the bridge into
    $02 (top layer), the ledge jump off the bridge's platform, west to
    $01, the key door (flag $1E) into $00;
  - R15-R17 Madderpillar beaten with real keys (`H.madder`: the head hit
    in line, the tail while open), the Gust Jar from the big chest;
  - S1-S6 the jar equipped from the pause menu, room $01's button (local
    $1C) opens the door south, into the barrel by its NE door, the web
    sucked off, the open bottom, B1 room $14, the lily pad sucked to the
    bank.
  **Not done:** stepping from the bank onto the pad (the pool rim is
  solid to the port's player collision; the cartridge's way on is not
  found yet), the rest of B1 ($14's channels, $15, $12's key and compass,
  $11's big key), the entrance webs and the boss door through the real
  runtime.
- [ ] **R13.6 chuchuBoss.c**: not ported (read through Init / the four
  parts / the Helper struct; still the round-3 simplification).
- [ ] **R13.7** stem, ceremony motion, white flash, fuse flames, Puffstool
  particles, Pesto / ChuChu models, Mt. Crenel: not started.
- Tests: `tests/zelda_tmc_r13_test.lua` (25 checks, fake data);
  `tests/zelda_tmc_round3_test.lua`'s web check now places the gust box.
- Not cartridge yet: the jar's own sprite (PLAYER_ITEM_GUST_JAR) and the
  GUST_JAR_PARTICLE / bush pieces are not drawn; the puff's sprite frame
  did not show in the shot; Link's drop-in after a hole (PL_SPAWN_DROP) is
  a plain arrival.
- **Final check (round 13):** all 24 `tests/zelda_tmc_*` files pass (r13
  25 checks); every `src/zelda/tmc` file compiles; harness cache rebuilt at
  version 14; old Deepwood route bot 24/24 (5617 frames; its web step now
  stands where the gusts reach and its room $12 step holds the button,
  since the cartridge's jar breaks pots instead of sliding them), Crenel
  bot 28/28 (8084 frames).  The new-game route `r13/s13_route.lua`, one
  run from the title with real key events (`MAXFRAMES=200000`):
  **73 PASS / 0 FAIL** (round 12's 50 + R1-R17 + S1-S6), 90761 frames, no
  runtime error, ending in B1 room $14 with the lily pad at the bank,
  18/24 health (`r13/out_s13_route.txt`, `r13/route_log_final.txt`).

## Round 14

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r14/`.
`r14/run.sh <script>` (round 13's driver: one LÖVE at a time, below-normal
priority, 1 ms sleep a frame, slot 1 reset), `r14/lib_r14.lua` (round 13's
libs + `H.layerPngs`, checkpoints in `r14/ck` falling back to r13 / r12),
probes `p_door` / `p_walk` / `p_seam` / `p_mush` / `p_invis` / `p_lily`,
`route13.lua` (round 13's 73-step route) and `route13_cart.lua` (the same
with CARTRIDGE TRANSITIONS on), `r14check.sh` (cache rebuild, old bots).
**Cache version: still 14** (no import change this round).

- [x] **R14.1 Link over doorways (user bug).**  Two causes, both fixed:
  - the port warped as soon as a door tile was *in front of* Link.  On the
    cartridge ACT_TILE_41 ($29) is a walkable threshold: Link walks on to
    the room edge, under the door's ARCHWAY object (house interiors; the
    archway is collision layer 2, so OAM priority 1, over Link).  Only
    ACT_TILE_40 ($28) with an area transition ahead starts a warp, and
    then as PLAYER_ROOM_EXIT: lined up with the transition, 5 frames of
    walking in at $140 with collision off (beanstalkSubtask.c,
    sub_08078AC0(4, 0, 1)); Link arriving on a $29 tile walks out
    (sub_080724DC / sub_0807258C).  `DoorWalk.lua`, `Field:doorExit`.
  - the draw order is now the GBA's (`Priority.lua`): BGs and OBJs in
    priority passes 3..0, OBJ over BG at the same priority, BG1 over BG2;
    rooms run BG1 at 1 and BG2 at 2 ($1C01 / $1D02); an entity's OAM
    priority comes from its layer (UpdateSpriteForCollisionLayer: 0 / 1 ->
    2, 2 / 3 -> 1) or its own b3 (ARCHWAY 1, MINISH_SIZED_ENTRANCE 3).
    Layer 3 (stairs) now draws over BG1 as on the cartridge.
  Shots: `r14/shots/walk/sheet_shop2_1.png` (Link walking out of the shop,
  hidden by the archway), `sheet_shop2_2.png` (into a town house door),
  `sheet_dw_1.png` / `dw_2_100.png` (Deepwood doorways), `mse2_1_002.png`
  (Link under the ranch gate's BG1 arch).
- [x] **R14.2 Zoom and the whole map (user request)** (`View.lua`): mouse
  wheel, R3 in, L3 out, L3+R3 reset -- the Pokemon games' Input actions
  ("zoomin" / "zoomout"); steps 2x .. 1/16x; the default is the cartridge
  picture.  Zoomed, the world is drawn into the runtime's zoom canvas
  (`Game:viewSize` / `Game:drawOverlay`, hooks the ALttP agent added to
  ZeldaRuntime this round) and the HUD stays at the normal scale.  Rooms
  around are drawn from the ROM at their map positions: on the overworld
  every room of the overworld areas (area flag $80), in a dungeon the
  rooms of Link's floor (gDungeonMaps); rooms with a tileset manager
  (Hyrule Town, Minish Village) are stitched from 240x160 windows each
  with its own swap (`Field.swapFor`).  The step is kept with
  `Host:gameOption("zoom")`.  Shots `r14/shots/seam/sheet_zoom.png`,
  `sheet_seam2.png`, `seam2_zoomout6.png`.
- [x] **R14.3 Seamless transitions (user request)** (`Seamless.lua`):
  border warps / adjacent rooms whose landing is where Link stands on the
  map switch rooms at once (Field:enterRoom as before: room code,
  entities, flags, follower, scripts) and the camera eases from where it
  was; Link then walks on to the spot the cartridge sets him down on
  (the room's enemies run meanwhile: holding them, as the cartridge's
  scroll does, was tried and dropped -- it reshuffled the route bot's
  Puffstool fights in room $06 into a death in $09).  Other warps
  (doors, stairs, holes, portals, special warps) crossfade in 12 frames.
  "CARTRIDGE TRANSITIONS" (runtime menu, off by default, kept with
  `Host:gameOption`) restores the fades.  Neighbour rooms are preloaded
  near an edge.  Shots `r14/shots/seam/seam2_036..052.png` (field ->
  Hyrule Town), `r14/shots/walk/sheet_xf.png` (the crossfade).
- [x] **R14.U User bug: mushrooms invisible until pulled.**  The port's
  Anim starts blank ($FF) and the mushroom's spawn never set animation 0
  (only the wobble after a release did).  `Mushroom.spawn` now sets it;
  outside dungeons palette 0 (ChangeObjPalette); the stem follows
  sub_0808ABC4 more closely (half turn for states 0 / 3, the y offset of
  the long vertical stem, drawn under the cap and body: b0 5).  Shots
  `r14/shots/mush/sheet.png` (idle, mid-pull, released).  An audit of
  every room (`p_invis.lua`) listed other objects that drew nothing while
  idle; PUSHABLE_GRAVE, STONE_TABLET, FLOATING_BLOCK, LIGHTABLE_SWITCH and
  TREE_THORNS set frameIndex in their Init and now get it (ObjStatic).
  Still blank: HOUSE_DOOR_EXT (needs its room-property door list and the
  push-to-open; not ported), GIANT_TWIG / HUGE_* Minish-size decorations,
  WATERFALL_OPENING, BAKER_OVEN, CABIN_FURNITURE, FIGURINE_DEVICE and a
  few others whose frames are set by their own state code.
- [~] **R14.4 Deepwood, continued**:
  - the lily pad: the cartridge counts Link as on a pad within 24 px of
    its centre (sub_0806FC80 / CalcDistance), so a pad sucked to the bank
    takes Link standing on the rim and carries him over it when blown
    (sub_08085F1C sets his position, in whole pixels so he stays on); a
    layer-2 pad puts Link on layer 2 (sub_08004542), a layer-1 pad and the
    landing after the drop on layer 1 (ResetCollisionLayer $0800455E);
    the pad has spritePriority.b0 6 (under Link).  The current tile was
    looked up as act $17 -- ACT_TILE_17 is $11 (the enum is decimal) -- so
    the pad never took the outflow; fixed.  Real runtime from round 13's
    `s6` checkpoint (`r14/p_lily2.lua`): the pad sucked to the bank, Link
    steps on from the rim (S7), is carried off, rides it by blowing, and
    the current drops it into the lower channel with him (S8).  Shots
    `r14/shots/sheet_lily3.png` (on, centred, dropped, landed).
  - pots and the Gust Jar (`PotGust.lua`, pot.c Pot_Action3): wiggle with
    tolerance 48, pulled to the mouth (its tile freed), caught and held,
    broken when the contact is lost, the jar is put away, or the blown
    shot ends.
  - NOT done: B1's channels past the first drop, rooms $15 / $12 /
    $11 (key, compass, big key), the entrance webs and the boss door
    through the real runtime, the chuchuBoss.c port (still the round-3
    simplification), the heart container, the Earth Element, the exit and
    the Elder.
- Tests: `tests/zelda_tmc_r14_test.lua` (42 checks, fake data).
- Runtime hooks used (no edit of mine to ZeldaRuntime): the ALttP agent's
  round-14 `viewSize` / `drawOverlay` (zoom canvas), `wheelmoved`,
  `menuOptions` / `menuOption`, `Host:gameOption`.
- **Final check (round 14):** all 25 `tests/zelda_tmc_*` files pass; every
  `src/zelda/tmc` file compiles; harness cache rebuilt (still version 14);
  old Deepwood route bot 24/24 (5617 frames), Crenel bot 28/28 (8036
  frames; its mine cart crossing rooms needed the seamless walk-in skipped
  while the cart drives Link).  Round 13's 73-step new-game route with
  real key events: **73 PASS / 0 FAIL** in the default seamless mode
  (89653 frames, ends in B1 room $14 at 2/24 health -- the bot's fights in
  rooms $06 / $09 / $00 cost more than with fades, `r14/out_route13_final.txt`,
  `r14/route13_final_log.txt`), and 73 / 0 with CARTRIDGE TRANSITIONS on
  (87541 frames, 14/24; run before the lily fixes,
  `r14/route13_cart_log.txt`).  The lily steps S7-S8 pass from round 13's
  `s6` checkpoint (`r14/p_lily2.lua`), not yet inside the route.

## Round 15

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r15/`.
`r15/run.sh <script>` (real runtime, one LÖVE at a time, below-normal
priority, 1 ms a frame, slot 1 reset), `r15/hx.sh <mode>` (a harness whose
modes are in `r15/hx/modes`), `r15/import.sh`, `r15/r15check.sh` (harness
cache rebuild, old Deepwood bot, Crenel bot).  The audit's reference is
`r15/ref15.lua`: the decomp's loaders (LoadGfxGroups, LoadRoomTileSet,
LoadRoomGfx, the tileset managers, sub_0807C5F4) applied to the ROM
directly, not to the port's cache.
**Cache version 16** (tileset loads in load order, `tshi_*.bin` BG3 maps,
`swap_oracle.bin`, `ExtractR15.lua`: manifest.r15 house doors).

- [x] **R15.1 Scrambled rooms (user report).**  Audits:
  `hx/modes/a_vram.lua` (data: every room's metatile characters / palette
  banks against what its loads write), `hx/modes/a_rooms.lua` (every room
  drawn by the port vs the reference, pixel for pixel), `p_audit.lua`
  (real runtime: every room entered with Field:enterRoom, room code and
  managers run, drawn by the field's BG passes at every 240x160 camera
  window, against the reference with the managers' swap chosen
  independently).  Causes found and fixed:
  - the tileset was assembled sorted by offset, keeping the earlier bytes
    where defs overlap; the cartridge copies in order, so the dig caves'
    ($0C, $0F, $13, $14, $16, $17, $19) and the Outer Fortress of Winds'
    ($18) $2000-byte overlays at $1000 / $9000 were lost: 14 rooms
    scrambled (`Extract.layVram`);
  - the backdrop: LoadGfxGroups ends with SetColor(0, 0) (black); the port
    kept group 11's teal: house / dungeon margins, transparent pixels
    (120 rooms differed by it alone);
  - special 8x8 screens: 8bpp was guessed from the palette bits; it is the
    area ($20, $2D: BG2 control | $80); the beanstalk screens ($0D:$10-$14)
    are 4bpp on BG1 (map def to gMapDataTopSpecial $02002F00, characters
    at $4000) and were drawn as garbage; rooms wider and taller than $FF
    have four blocks ($2D:$10, $2D:$12 lost their lower half);
  - BG3 backgrounds were never drawn (`Bg3.lua`: animated / POW / static
    background managers): the beanstalk tops, Cloud Tops, the Palace of
    Winds, Mt. Crenel's peak, Veil Falls' top showed black;
  - Hyrule Town: BuildSecondOracleHouse (the red house by TATEKAKE_TOCHU /
    TATEKAKE_HOUSE, with its $800 bytes at VRAM $1800) and the USA tile
    at (43, 25) were missing;
  - rooms reused their cached map table, edited in place (`Room.load`
    copies it now);
  - house-type areas run BG1 at priority 2 ($1D46) (Priority.lua).
  Result: static audit 605 / 605 rooms equal to the reference (570 tiled
  + 35 special screens), was 464 / 605 (134 tiled + 7 special wrong); runtime audit 2665 windows, the
  only differences left are save-state tiles (an opened chest, pressed
  buttons, a lit torch in Deepwood from the checkpoint's flags), Mt.
  Crenel's USA sign tile (cartridge room code) and the barrel room $20
  (the port's barrel draws BG2).  Before / after sheets:
  `r15/shots/before_after_0..3.png` (before | after | ROM reference),
  room sheets `r15/shots/rooms/` (before), `r15/shots/after/`, runtime
  windows `r15/shots/rt2/`; the red house `r15/shots/oracle_sheet.png`;
  zoomed out with BG3 `r15/shots/zoom_sheet3.png`.
- [x] **R15.2 Invisible objects** (`p_invis.lua`): a zeroed entity shows
  frame 0, so objects whose Init sets no frame now draw it (Field
  `zeroFrame`); ObjStatic rules from the Inits of GIANT_TWIG (parts $40 /
  $41, palettes $7A / $7B), HUGE_DECORATION (palettes, flips, the
  parallax of sub_08097F34), HUGE_ACORN (parts), HUGE_SHOES,
  WATERFALL_OPENING, BAKER_OVEN, CABIN_FURNITURE, FIGURINE_DEVICE;
  HOUSE_DOOR_EXT (`HouseDoor.lua`, the room-property door lists read at
  import): drawn closed, solid, opened by 8 frames of UP against it
  (frame 1, SFX $111, a 16-frame walk in).  Shots `r15/shots/door_sheet.png`.
- [x] **R15.3 Seamless fights.**  After a seamless border change the new
  room's enemies are held for the cartridge's scroll time (Scroll2Sub2:
  $3C frames left / right, $28 up / down) -- no movement and no contact.
  Why round 14's freeze went wrong could not be read back (its code was
  not kept), but the logs show it: in room $09 Link's walk-in ends on a
  Sluggula and takes five hits in a row at distance 1.7 (contact while
  overlapping); with the hold skipping the whole enemy update (contact is
  inside Enemies:update), $09 costs 2 hearts' worth (24 -> 22) and the
  route reaches Madderpillar at 22/24 (round 14: 2/24 at the end).
  Neighbour rooms zoomed out step their BG animations and draw their BG3;
  their entities are still not loaded.
- [~] **R15.4 Deepwood, continued**: the lily pad steps are part of the
  route (`r15/seg_s3.lua`: S7 on from the bank, S8 down the current).
  NOT done: B1 rooms $15 / $12 / $11, the entrance webs, the boss door,
  chuchuBoss.c (1857 lines; still the round-3 simplification), the heart
  container, the Earth Element, the exit and the Elder.
- Tests: `tests/zelda_tmc_r15_test.lua` (40 checks, fake data).
- `p_invis` after the round: the seven objects of the round-14 list draw;
  HOUSE_DOOR_EXT draws everywhere but room $09:00, whose door is scripted
  (pool $40: the script path, not ported).  Still blank, outside this
  round's list: enemies drawn by their own state code (blade traps,
  wall masters, torch traps, the Moldorm, aggressive cucco chicks),
  SPECIAL_FX, CARLOV_OBJECT, MINISH_VILLAGE_OBJECT, the fountain fairies
  (FAIRY form $60), PAPER, OBJECT_BLOCKING_STAIRS, LADDER_HOLE,
  MAZAAL_BOSS_OBJECT, TREE_HIDING_PORTAL, the PHONOGRAPH NPC
  (`r15/out_p_invis3.txt`).
- **Final check (round 15):** all 26 `tests/zelda_tmc_*` files pass (r15:
  40 checks); every changed `src/zelda/tmc` file compiles; the harness
  cache rebuilt at version 16; old Deepwood route bot 24/24 (5617
  frames), Crenel bot 28/28 (8036 frames); static audit 605 / 605,
  runtime audit 2665 windows with the 5 explained rooms
  (`r15/out_p_audit_list.txt`).  The new-game route with real key events
  in the default seamless mode (`r15/route15.lua` = round 13's route with
  Madderpillar's bot budget raised + `seg_s3`): **75 PASS / 0 FAIL**,
  93418 frames, ends on B1 room $14's lower channel after the lily ride at
  12/24 health (`r15/out_route15.txt`, `r15/route15_log.txt`).  (With the
  old budget of 15000 frames the bot's Madderpillar fight timed out twice
  in the full route -- the fight is random -- while the same segment from
  checkpoints r10 / r14 wins in about 11800 frames.)

## Round 16

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r16/`.
`r16/run.sh <script>` (real runtime, one LÖVE at a time, below-normal
priority, 1 ms a frame, slot 1 reset), `lib_r16.lua` (round 13's libs +
checkpoints in `r16/ck`) and `lib_r16x.lua` (the round's helpers only, safe
to load mid-route: `rideTo` / `lilyGuard` / `jarFling` / `fightChuchu`),
segments `seg_b1a..i.lua`, `seg_boss.lua`, `seg_e.lua`, the whole route
`route16.lua`. **Cache version: still 16** (no import change).

- [x] **R16.1 Deepwood B1 through the real runtime** (in one run from the
  title up to the boss room, see the final check):
  - the lily pad crosses rooms (`LilyRide.lua`, lilypadLarge.c
    sub_08085D60 / sub_08085E74 / Action3): the room's edge 24 px ahead
    (COLLISION_DATA_255) starts the scroll, the pad keeps Link on it and
    runs on for the scroll's frames at $100 / $120 / $138; the next room's
    own pad is the duplicate (EntityHasDuplicateID; type 1 pads wait in
    Action5 and set their flag, $12's flag $40); type $FF pads go once
    Link has the Flippers. Pads are stopped by solid tiles objects put down
    (bollards).
  - `Bollard.lua` (bollard.c): $15's four bollards go down while room flag 0
    (the button by the stairs) is set.
  - $15: a pot of the corner block lifted away, the next pushed four tiles
    onto the button (pots now have their collision layer: Pot_Init /
    ResolveCollisionLayer -- the raised floor's pots were drawn under BG1);
    the moveable-object manager puts its pot on its own layer.
  - $12: the region trigger sets flag $44 as the pad comes in (on the way
    back the pot already stands on $15's button); the compass corridor's
    two $360 blocks (east one up, west one west), the ring's east pot
    pushed onto the button (flag $43), the key from the niche reached by pad.
  - back by pad through $15 into $14, up the east channel and west along
    the top one to the key door's ledge; the key door; $11.
  - $11: the mushrooms -- the Gust Jar on a mushroom now flings Link
    (pullableMushroom.c Action1 case $13 / Action3: the cap creeps to the
    jar's mouth at $40, then PLAYER_08072C9C); pulled north, then jar flings
    east, east, west to the big key's island; the big key.
  - `WarpPoint.lua` (warpPoint.c types 0 / 1, and 2 when its data names the
    way out): $11's button wakes its warp (flag $3E, EnableDungeonWarp), the
    96-frame spin, the warp to $0B; the arriving spin.
  - the entrance webs torn with the jar, the east stairs to $17, the
    island mushroom flings Link west then north to the boss door, opened
    with the big key; north into the boss room.
  Shots `r16/shots/b1a_cross30.png` (the pad carried into $15),
  `b15_button.png` (bollards down), `b1c_cross.png` (into $12),
  `b1d_compass.png`, `b1d_key.png`, `b1e_ledge.png`, `b1g_m2.png` ..
  `b1g_bigkey.png`, `b1h_spin.png`, `b1i_webs.png`, `b1i_pool.png`,
  `b1i_bossdoor.png`.
- [~] **R16.2 Big Green ChuChu: chuchuBoss.c ported** (the port is complete;
  the route bot does not win it reliably -- see the final check) (`BossChuchu.lua`,
  replaces the round-3 model): the four affine parts (base, lower, middle,
  head; scales unk_74 / unk_78, the swing angles and the hanging chain of
  sub_08027870 / sub_0802757C, the swing tables gUnk_080CC27C / 29C / 2BC),
  every subAction of the base (intro 0..9 with the drop timings, idle,
  creep, squash / stretch, jump zVelocity 7 / speed $180 / gravity $4000,
  landing, topple 10 -> 6 (lean, fall, lie 150..250 frames), 7 up again,
  8 phase check, 9 the last blow, 11 the angry double bounce, 12 death:
  120 frames of explosions, SFX_BOSS_DIE), the damage rules (48 Gust Jar
  contacts on the base with iframes 3, the swell of 8 every third; the
  head open to the sword only while it lies; phases end under (u8)-7 / -9
  / -7 of $FF; the third phase faster, multi-jumps), its art from the ROM
  (the enemy definitions' sprites, CHUCHU_BOSS_PARTICLE $C9 on fixed gfx $3E
  palette $2B). Simplified: the goo drops of the intro are drawn as dots;
  the hitbox proxy (type 8) is not an entity; the jar's blow does not knock
  it back. Shots `r16/shots/c_intro_drops.png`, `c_intro_land.png`,
  `c_ready.png`, `c_p0_sa2.png` (creeping), `c_p*_sa4.png` (jump),
  `c_p*_sa10.png` (to the middle), `c_p*_sa6.png` (toppled), `c_p*_sa11.png`
  (angry), `c_p3_sa12.png` (death), `boss_p1_sa6.png`.
  - after it: the Earth Element (fourElements.c timings: down from 192, the
    bob, SFX_178, BGM_ELEMENT_GET, the item text after 45 + $1A4 frames,
    room flag 0; ELEMENTS_BACKGROUND and the white flash not ported), the
    heart container, the type-2 warp now data-driven ($4A:00 at (120, 120);
    the Cave of Flames' at $06:02 (104, 152) -- WARP_OUT kept as fallback),
    Deepwood Shrine Entry's room code (script_EzloTalkDWS until
    LV1_CLEAR_MES), `seg_e.lua` to the Elder.
- [~] **R16.3 Invisible objects**: ObjStatic rules for MINISH_VILLAGE_OBJECT
  (types 0 / 7 / 8), CARLOV_OBJECT type 1, PAPER types 0..2. Explained (drawn
  0 by their own code in the listed state, so blank on the cartridge too):
  TREE_HIDING_PORTAL, MAZAAL_BOSS_OBJECT, OBJECT_BLOCKING_STAIRS, SPECIAL_FX
  type 2. Not done: the enemies drawn by their own state code (blade traps,
  sensor blade traps, torch traps, wall masters, the Moldorm, aggressive
  cucco chicks: their enemy code is not ported), FAIRY $60, LADDER_HOLE (asm
  only), the PHONOGRAPH NPC, HOUSE_DOOR_EXT's scripted door in $09:00.
- [ ] R16.4 effects (Minish Paths' blended BG, light rays, clouds / steam,
  rain, neighbours' backgrounds) and Mt. Crenel: not started.
- Fixes: Dungeon:checkFall tested the lit lantern ($10) for the Flippers
  ($46).
- Tests: `tests/zelda_tmc_r16_test.lua` (46 checks, fake data).
- Old bots: the teleport bot (`harness/modes/route.lua`) keeps the round-3
  ChuChu (`Boss.simpleChuchu`, set only there) and waits for the element's
  $1A4 frames; the Crenel bot waits for room flag 0 the same way.
- **Final check (round 16):** all 27 `tests/zelda_tmc_*` files pass (r16: 46
  checks); every changed `src/zelda/tmc` file compiles; harness cache rebuilt
  (still version 16); old Deepwood bot 24/24 (5897 frames), Crenel bot 28/28
  (8500 frames); static room audit 605 / 605, runtime audit 2665 windows with
  the same 5 explained rooms as round 15 (`r16/out_p_audit_list.txt`).
  - The new-game route with real key events (`r16/route16.lua`, MAXFRAMES
    260000, `r16/out_route16.txt`, `r16/route16_log.txt`): **every Deepwood
    step passes in one run from the title to the boss room** (round 15's 75
    + B1..B18: $15, $12, the key, the compass, $14's ledge and key door, $11's
    mushrooms and big key, the warp, the webs, the boss door; the boss room at
    frame 116989 with 8/24 health). **The fight is lost in that run**: C1
    (the intro) passes, C2..C7 and E1..E4 fail (94 pass / 10 fail).
  - The boss itself, from the boss-room checkpoint at full health with the
    same bot: won twice (all three phases, LV1_CLEAR, the Earth Element, the
    heart container 24 -> 32, the warp to $4A:00 -- C1..C7 7/7, shots
    `r16/shots/c_*.png`, `boss_*.png`), lost in most other tries (the bot
    stands under the base and gets pinned against the south wall as the
    boss creeps; five bot variants were tried, `lib_r16x.lua` keeps the one
    that won). At 8 health it loses even after the corner pots' hearts.
  - After the shrine, from a dev state (LV1_CLEAR set, Link put on $4A:00):
    Ezlo's words (E1), the woods and the stump (E2), the Minish Paths into the
    village (E3) pass; the walk into the Elder's house fails (`exitTo
    20:00`: no path), so the Elder's talk and the story beat after it are
    NOT verified.

## Round 17

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r17/`.
`r17/run.sh <script> [out]` (real runtime, one LÖVE at a time, below-normal
priority, 1 ms a frame, slot 1 reset), `lib_r17.lua` / `lib_r17x.lua`
(round 16's libs; checkpoints in `r17/ck`; **every shot is named
`<RUNID>_<name>`**, so no run overwrites another's), `route17.lua` (the whole
route; `CRENEL=1` adds `seg_c17.lua`), `r17check.sh` (harness cache, old
Deepwood bot, Crenel bot), `hx.sh` (static audit).
**Cache version: still 16** (no import change).

- [x] **R17.1 The boss in the one-run route.**  Diagnosed from data first
  (the collision matrix rows in the cache, chuchuBoss.c, enemy.c's
  gEnemyDefinition_13, arm_CalcCollision): the port's contact was wrong in
  four ways, all fixed in `BossChuchu.lua`:
  - the lower and middle parts hurt Link -- their definitions have the
    collision bit clear (only the head is switched on, while it lies, with
    collisionMask bit 0 cleared so Link's body ignores it);
  - the base's own hit type is $7D (gCollisionMtx[$7D][0] = CollisionNoOp);
    the damage comes from the hitbox helper (type 8, sub_08026090): the
    base's box with hit type $7C, [$7C][0] = 2 damage, 60 iframes, Link
    knocked at $280 for 6 frames;
  - the box is gUnk_080FD238, offset (0, **+4**) (the port had -4: the
    danger zone sat 8 px too far north);
  - contact while it rose (collision is off from the fall, sub_080269CC,
    until the phase check, sub_08026E1C); the |dz| test is 5 + 5;
  - missing: the base and the lying head are static solids on the ground
    (sub_0800445C -> CalcCollisionStaticEntity: Link pushed out).
  Also: the head is hurt type $7B (form 1): [$7B][4] = 2 damage, 30 iframes
  (the port read $7E -> fallback 20 iframes); FX_GIANT_EXPLOSION3 is $48
  (effects.h; $49 is FX_GREEN_ORB -- also in BossMadderpillar.lua).  Creep
  speed ($C0 / $100), scale bounce (rate / 16) and the jump were checked
  against the decomp and were right.
  The bot (`lib_r17x.lua` H.fightChuchu17): boxes it routes round (the
  base's danger box, the lying head's static box), a stance side chosen
  toward the room's middle with hysteresis, **the Gust Jar held while it
  walks (facing locked) to keep 22..52 px from the base's box** instead of
  letting go and re-aiming, a side-step across the jump's line, the lying
  head approached on a free side (not inside a wall), a wall detour when
  Link does not move.  From the boss checkpoint at 8 health it wins with
  10 / 16 left (`out_p_boss_b9.txt`).
- [x] **R17.2 The Elder.**  "no path" was the **bot planner**: round 13's
  H.path refuses every cell inside an area-exit region (Room:areaExitAt)
  unless Link is within 24 px -- the goal's own region too, so the
  Elder's door ($01 -> $20:00 at (120, 136)) could never be the goal.
  Engine collision was fine (H.reach reached it).  `lib_r17x` lets the
  goal's own region through.  (Link is full size in the Minish Village:
  that is the cartridge -- the paths -> village border is
  TRANSITION_TYPE_NORMAL, PLAYER_INIT.)  Gentari after the Earth Element
  (script_Gentari 0800C824): TEXT_FINDING_EZLO $35, MoveTo (0x38, 0x44),
  local flag $83, SFX_SECRET, $36 "If your conviction holds strong, head to
  Mount Crenel. There, you will find a man named Melari.", Ezlo's $37.
- [~] **R17.3 Mt. Crenel through the real runtime** (`seg_c17.lua`): back
  out through the village and the Minish Paths, grown at the stump, out of
  the woods by the bridge lane into the Eastern Hills (the lower lane is a
  pocket of trees), Lon Lon Ranch, North Hyrule Field, Hyrule Town (the
  field's west bridge to Trilby is broken; the town's west-north border
  leads there), Trilby Highlands, Mt. Crenel's entrance ($06:04) and up its
  first vines (PlayerClimb with UP held).  Further up (the scrub's bottle,
  Mineral Water, the bean, the Grip Ring wall, Melari) is only covered by
  the old teleport Crenel bot.
- [x] **R17.4 The boss's simplified parts**: the intro's goo drops
  (CHUCHU_BOSS_START_PARTICLE type 0: z -$C0, gravity $2000, spread / shrink
  scales, the particle object's own sprite, animation 3; the type 2 mark
  under it); the hitbox helper's rules (above; still not a separate entity);
  the Gust Jar puff knocks the base back (case 27: 16 / 20 / 26 frames at
  1 / 1.5 / 1.75, iframes 30; ChuchuBoss_OnKnockback holds the subAction);
  the Earth Element: **it was invisible** (its animation is its type,
  sub_08080CB4 -- the port played animation 0, frame $FF), now drawn, with
  ELEMENTS_BACKGROUND (`ElementFx.lua`: frame 4 of its sprite, affine scale
  |z| + $100, EVA ((($1C0 - s) * 10) / s)) and the white flash
  (SetFade(FADE_BLACK_WHITE | FADE_INSTANT, 2): 128 frames; Action4 waits
  for it, so the text comes 128 + $1A4 frames after the touch).
- [~] **R17.5 Still-blank objects** (`p_blank.lua`, `shots/bl2_*`):
  - drawn and moving by their own code (`EnemyTraps.lua`): BLADE_TRAP
    (rails from room properties, UpdateRailMovement), SENSOR_BLADE_TRAP
    (sub_0804A024 line of sight, rush / return), WALL_MASTER /
    WALL_MASTER_2 (hidden, then over Link at z $80, the fall, the grab),
    CUCCO_CHICK_AGGR (hops, then at Link within 36 px), MOLDORM (head + three
    tail parts 8 frames apart, frames 8 / 9 / 10 + state);
  - `ObjBlank17.lua`: FAIRY $60 (animation = type, the wander round home,
    caught -> circles Link, six hearts), LADDER_HOLE (frame 0, layer 2 / 1);
  - PHONOGRAPH: frame 0 (phonograph.c sets frameIndex 0);
  - REMOVABLE_DUST in $06:04 draws (it already did; the survey's flag was
    the frame index, the piles are visible in `shots/bl2_blank_dust_b.png`);
  - explained: TORCH_TRAP has no sprite on the cartridge (its definition does
    not draw; only TORCH_TRAP_PROJECTILE is seen -- not ported).
  - NOT done: the $09:00 door's script (drawn at frame 0, its scripted
    opening not checked).
- [ ] R17.6 effects (Minish Paths' blended BG, light rays, clouds / steam,
  rain, neighbours' backgrounds): not started.
- Tests: `tests/zelda_tmc_r17_test.lua` (36 checks, fake data).
- **Final check (round 17):** all 28 `tests/zelda_tmc_*` files pass (r17: 36
  checks); every changed `src/zelda/tmc` file compiles (`r17/compile17.lua`);
  harness cache rebuilt (still version 16); old Deepwood bot 24/24 (5985
  frames), Crenel bot 28/28 (8580 frames); static room audit 605 / 605,
  runtime audit 2665 windows with the same 5 explained rooms as round 15.
  - The new-game route with real key events (`r17/route17.lua`, `CRENEL=1`,
    MAXFRAMES 300000, run R2: `r17/out_route17_R2.txt`,
    `r17/route17_R2_log.txt`): **111 PASS / 0 FAIL** in one run from the
    title: Deepwood, the boss room at frame 116989 with 8/24 health (the
    corner pots -> 16), **the Big Green ChuChu beaten** (three phases, no
    hit taken), LV1_CLEAR, the Earth Element, the heart container (24 ->
    32), the warp out, Ezlo, the village, the Elder's words and his step
    aside, then out to Mt. Crenel's entrance and up its first vines (frame
    138085).  Run R1 (without Crenel) also passed 105 / 105.
  - Shots (all `r17/shots/`, named per run): `R2_c_intro_drops.png`,
    `R2_c_p1_sa2.png`, `R2_c_p3_sa12.png` (death), `R2_c_element.png`
    (element + glow), `R2_c_element_get.png` (white flash),
    `R2_c_heart.png`, `R2_c_outside.png`, `R2_e_ezlo.png`,
    `R2_e_elder_p6.png` ("head to Mount Crenel"), `R2_e_elder.png`,
    `R2_c_hills.png`, `R2_c_town.png`, `R2_c_trilby.png`,
    `R2_c_crenel_entrance.png`, `R2_c_crenel_vines.png`; contact sheet
    `R2_sheet.png`; the element's fall `el2_elem_t*.png`; the blank objects
    `bl2_blank_*.png` / `bl2_sheet.png`.
  - Seen in the shots, not fixed: the item get pose shows no Earth Element
    held over Link's head; Gentari's side walk frame looks stretched.

## Round 18

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r18/`.
`r18/run.sh <script> [out]` (real runtime, one L�VE at a time, below-normal
priority, 1 ms a frame, slot 1 reset), `lib_r18.lua` / `lib_r18x.lua`
(round 17's libs; checkpoints in `r18/ck`, Minish state kept; shots
`<RUNID>_<name>` in `r18/shots`; new bot pieces: ledge-aware `H.path` /
`H.reach` (Ledge.lua tables, diagonal jumps), ladder waypoints snapped to
the tile's middle, `H.goNear`, `H.bombFrom`, `H.mow`, `H.collectAll`,
`H.offLadder`, `H.reachPng`, `H.survey18`), segments `seg_belari.lua`,
`seg_c18.lua` (round 17's segment C), `seg_m18a..d.lua`, the whole route
`route18.lua`; survey probes `p_survey*.lua`, `p_world.lua` (a multi-room
flood fill over the overworld with ledges and bomb tiles).
**Cache version: still 16** (no import change).

- [~] **R18.1 Mt. Crenel through the real runtime** (as far as the Mineral
  Water; see the final check):
  - Bombs first, from the data: Mt. Crenel's base needs them (the rock
    before the spring YAMA_04_HIBI_1, the walls YAMA_04_04/05/06/BOMBWALL0,
    the hermit's "Bombs are the answer!"); the Bomb Business Scrub only
    refills a bag (BusinessScrub_CheckRefillFitsBag, GiveItem case 9); the
    first bag is Belari's (script_BombMinish: TEXT_BELARI 1, ITEM_BOMBBAG).
    The way to him (gExitList_MinishVillage_Main BORDER_WEST_NORTH ->
    the woods at (424, 840), INSTANT_MINISH): the Elder's back room ($20:01)
    opens on the village's west pocket, whose west border is open at tile
    row 6; west through the hollow log into his clearing.  (Its south rocks,
    HIBI_2..4, are the "debris" he talks about; its north ones open by a
    fusion.)
  - `MinishTunnel.lua`: SurfaceAction_MinishDoorFront / _Back / _A / _B --
    hidden (type2 $80), sub_0800857C skips the tile collision, only the free
    axis moves, until a door tile shows Link again.
  - `Bombs.lua`: ItemBomb (offsets, three at most, ModBombs, SFX_PLACE_OBJ),
    PlayerItemBomb (150 + 80 frames, the blink and the affine pulse), the
    blast (sub_0801B418, SMOKE_PARTICLE: its box per frame byte, enemies
    hit with hurtType $16, Link by [$A9][his hurt type], sub_080878CC:
    ACT_TILE_46 -> SPECIAL_TILE_34), BombableWallManager (from tile
    entities and from entity lists: manager $24 with its data at +$30),
    DestroyWall0..4, the flag, SFX_SECRET after 90 frames;
    DestructibleTileObserveManager; the Bomb Bag (GiveItem case 8) and
    ITEM_BOMBS10 / 30 refills.
  - `LadderUp.lua` (ladderUp.c): the cave ladders' special tiles (23 / 20 /
    35, RestorePrevTileEntity); the way out at the top is simplified (see
    minishcap.md "What differs").
  - Ground items are picked up by whole pixels (x.HALF.HI): Link at y
    364.25 missed the red rupee at 356.
  - The route: the red rupee (YAMA_04_R00, 20); Trilby's cave $32:0E (the
    hint scrub's "friend in a cave just east of here"), its east wall
    bombed, east into $32:14, the Business Scrub's seed shielded back, the
    bottle bought (20 Rupees); water from the lake, poured on the planted
    bean (type 2, YAMA_04_01): the vine; the bomb wall to the ladder cave
    $26:0C (YAMA_04_05), its ladder onto the portal's plateau, the rock
    before the spring bombed (YAMA_04_HIBI_1), Minish at the stone portal,
    $12:01 past the Mulldozers, the Mineral Water, back out, grown again.
  - NOT done: the Minish path's bean ($12:00, reached by a Minish passage
    not found yet -- the rock with spikes at (265, 195), ENTHOUSHI /
    ANAHOUSHI suggest the Gust Jar), the bean's vine to $06:03, the Grip
    Ring cave, the wall climb, Melari's mine, the Cave of Flames' entrance;
    Mt. Crenel's enemies' own code (Tektites, falling boulders, Spiny
    Beetles, Peahats).
- [ ] R18.2 Cave of Flames: not reached.
- [ ] R18.3 round 17 leftovers (item-get pose, Gentari's frame, Wallmaster
  destinations, HUD under the flash, particle types, the $09:00 door): not
  done.
- [ ] R18.4 effects: not started.
- Tests: `tests/zelda_tmc_r18_test.lua` (45 checks, fake data).
- **Final check (round 18):** all 30 `tests/zelda_tmc_*` files pass (r18: 45
  checks); every changed `src/zelda/tmc` file compiles (`r18/compile18.lua`);
  harness cache rebuilt (still version 16); old Deepwood bot 24/24 (5985
  frames), Crenel bot 28/28 (8580 frames) (`r18/r18check.sh`); static room
  audit 605 / 605 (`r18/out_a_rooms.txt`); runtime audit 2665 windows: the
  same 5 explained rooms as round 15 plus $03:06's two windows, explained:
  its DESTRUCTIBLE_TILE bushes (flags $81..$84 set in the audit's save) are
  now laid by LoadDestructibleTile as the cartridge does, the reference
  renderer does not run it (`r18/out_p_audit.txt`,
  `r18/shots/rt/rt_03_06_*.png`).
  - The new-game route with real key events (`r18/route18.lua`, MAXFRAMES
    420000, run R3: `r18/out_route18_R3.txt`): **135 PASS / 1 FAIL** in one
    run from the title: round 17's 111 steps (Deepwood, the Big Green
    ChuChu, the Elder), then Belari (B0..B6: the Elder's back room, the
    village's west border, the hollow log hidden, the Bomb Bag with 10
    bombs), round 17's segment C to Mt. Crenel's entrance (C1..C6), and
    Mt. Crenel's base M1..M14 (the red rupee, Trilby's bombed cave wall, the
    bottle, the lake's water, the bean's vine, the ladder cave's bomb wall
    and ladder, the plateau, the spring rock, Minish at the stone portal,
    into $12:01 at frame 168640).  The failed step was M15 (the bot did not
    get off the spring path's bottom edge); with the bot fix, segment D run
    from that run's own checkpoint (`route_r18_m_spring`,
    `r18/out_p_m18_R3d.txt`) passes M15..M17: the Mineral Water, back out
    Minish, grown again.  Runs R1 / R2 failed earlier on bot issues fixed
    since (Link arriving on a cave ladder; the cave's opened east doorway).
  - Shots (`r18/shots/`): `R3_bel_woods_in.png`, `R3_bel_log_out.png`,
    `R3_bel_house.png`, `R3_bel_bag.png`, `R3_m_cave_wall.png` (the opened
    wall), `R3_m_scrub_room.png`, `R3_m_scrub_hit.png`, `R3_m_bottle.png`,
    `R3_m_water.png`, `R3_m_pour.png`, `R3_m_vine.png`, `R3_m_vine_top.png`,
    `R3_m_wall_0c.png`, `R3_m_plateau.png`, `R3_m_spring_rock.png`,
    `R3_bomb_blink.png` / `R3_bomb_blast.png` (sheet `R3_bomb_sheet.png`),
    `R3_m_minish.png`, `R3_m_spring_path.png`, `R3d_m_mineral.png`,
    `R3d_m_grown2.png`; sheets `bel_sheet.png`, `m_sheet1..3.png`.
  - Seen in the shots, not fixed: the blast's smoke is not visible
    (SMOKE_PARTICLE's sprite draws nothing in the port; the rock breaks and
    its drop appears); room-placed rupees come back after a checkpoint
    reload.

## Verified (and how)

Round 2:
- `tests/zelda_tmc_round2_test.lua` (27 checks): font width rule,
  collision-matrix decode and special handlers, enemy spawn/home/damage/
  death/knockback, drop tables incl. low-health bonus and item gates, tile
  interaction filters and replacement, chest item + flag, equip swap.
  `tests/zelda_tmc_rom_test.lua` now has 47 checks (adds item-get text, item
  sprite 323, Octorok health, matrix damage, font, HUD tiles, tile acts,
  festival NPC list).
- Harness runs, PNGs in `G:/Gen2Recomped/scratch_claude/zelda/tmc/shots/`:
  `swapmap_*.png` (clean stitched rooms), `title2_*` (title backdrop with
  swaps), `chest_01` (the smithy chest: "You got 20 Rupees!" in the
  cartridge font, rupees 0 -> 20), `pot_*` (lift + throw), `woods_*` (a
  sword swing kills an Octorok, it drops a green rupee), `portal_*` +
  `crop_minishlink.png` (shrinking at the Minish Woods stump), `dw*_01_end`
  (Deepwood rooms), `rc_*` (Festival with 34 entities and its prologue
  scene; South Hyrule Field starts its scene), `intro2_*` / `intro_04`
  (the new-file wake-up), `crop_rupee.png` (HUD digits); Kinstone 0x0D
  fused -> Golden Tektite in Mt. Crenel.
- The foundation's two-process ENet harness (copy in
  `G:/Gen2Recomped/scratch_claude/zelda/tmc/twoproc`, `MODULE=src.zelda.tmc
  GAME=minishcap`): the module boots in the real ZeldaRuntime, two players
  see each other's snapshots and events, host close reaches the guest
  (rc=0, round 1 and again after round 2).

Round 1:
- `tests/zelda_tmc_core_test.lua` (42 checks), `tests/zelda_tmc_online_test.lua`
  (21 checks: Kinstone fusion over a loopback session pair).
- Rendered rooms and sprite sheets with the scratch LÖVE harness
  (`G:/Gen2Recomped/scratch_claude/zelda/tmc/harness`, modes rooms /
  sprites / play / audio / crop / swapmap / objsheet / tiles).
- Walk speed: 40 frames = 50 px (kWalkSpeed 1.25). The smithy prologue runs
  from the cartridge's scripts. Music renders (Minish Woods theme, peak
  0.72).
- Note: `/tests/*` is git-ignored in this repo, so the test files live on
  disk only.

## Open issues

- Native room code: Link's house x3, Minish Village, Minish Woods, South
  Hyrule Field, Hyrule Town / Festival are ported; other rooms load only
  their base lists, delayed-load NPCs and Kinstone events.
- Native calls: the scene helpers are ported by address (`Native.lua`).
  Unported addresses are counted in `Script.missing`. Not ported:
  SetPlayerMacro, the Zelda follower; iris fades are drawn as plain fades.
- Deepwood (round 3):
  - not ported: barrel rotation (room $20, `dws_barrel_state`);
  - simplified: the lily pad (moved while gusting), Madderpillar and Big
    Green ChuChu (their behaviour is simplified; the defeat rules are
    kept).
- Enemies: Pesto keeps the shared model. Peahat, Mulldozer and Puffstool
  are simplified.
- Art not taken from the cartridge:
  - the bubble's "!" / "?" mark is drawn with the font;
  - the A / B / R buttons and the menu pages are our own layout.
- Not done: figurine trading, the Mt. Crenel path, windcrests (their lists
  always load), palette-type BG animations.

## Requests for other agents

- (resolved) ZeldaSession API: Net uses `sendEventTo(id, ev)` /
  `sendEvent(ev)` / `sendSnapshot` via the runtime, and the player id as the
  colour slot, as documented in `src/online/zelda/ZeldaSession.lua`.
- Foundation: the game receives `opts.root` = ZeldaCache; `extract` gets the
  same object plus `ctx.bytes`. Both are handled.

## Round 19

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r19/`.
`r19/run.sh <script> [out]` (real runtime, one LOVE at a time, below-normal
priority, 1 ms a frame, save dir `r19/appdata` on G:, slot 1 reset),
`lib_r19.lua` / `lib_r19x.lua` (round 18's libs; checkpoints in `r19/ck`;
shots `<RUNID>_<name>` in `r19/shots`; new: the edge-band waypoint filter,
`H.gustable`, `H.gustClear`, `H.gustWalk`), `p_seg.lua` (checkpoint + any
segments), `route19.lua` (the whole route; round 18's segments with
`seg_m19d.lua` for part D), `r19check.sh` (harness cache, old Deepwood bot,
Crenel bot, APPDATA on G:), `hx.sh` (static audit), `p_audit.lua` (runtime
audit); data probes `p_rock.lua`, `p_grid.lua`, `p_flags.lua`, `p_types.lua`,
`p_masks.lua`, `p_region.lua`, `p_reach.lua`, `p_world19.lua` (multi-room
flood fill over Mt. Crenel and its caves), `p_pathdbg*.lua`, `p_collpng.lua`.
**Cache version: still 16** (no import change).

- [x] **R19.1 The M15 stall, properly.**  Diagnosed from the run's own
  state (`diag.lua`: Link's fields, `seg_m15orig.lua` from the route's
  checkpoint reproduces it): H.path let Link's own 16-px neighbourhood
  through the 10-px edge band, so the path out of $12:01 (Link at y 792 of
  800) began (132, 796) -> (124, 796) and the bot pushed DOWN into the $FF
  bottom row.  Two fixes:
  - engine (`Field.lua` checkExits): the cartridge's border rule
    (UpdatePlayerCollision + sub_0807BDB8, offsets from ROM $080B4490): a
    move towards an edge within 10 px of it with collision $FF on the tile
    just ahead takes the border exit (DOWN at y 792 now leaves $12:01, as on
    the GBA; the old "height - 3" test never fired there);
  - bot (`lib_r19x.lua`, opt-in `H.edgeFilter`, set only around M15 in
    `seg_m19d.lua`): leading waypoints in the edge band nearer the edge than
    Link are dropped.  A global filter broke $32:0E's east doorway (F2:
    M5-M17 failed); opt-in, F5 (route_r18_crenel_in -> m18a/b/c + m19d)
    passes all 18 Crenel checks.  F2 passed everything before M5 with the
    engine border rule (title -> Deepwood -> boss -> Belari -> Crenel).
    NOTE: F2 overwrote r19/ck/route_r18_m_bottle .. route_r18_m_mineral with
    stuck states; F5's good ones are r19/ck/r18_m_bottle etc. (no prefix).
    A full route19.lua rerun was not done after the opt-in change.
- [~] **R19.2 Mt. Crenel past the Mineral Water.**
  - REMOVABLE_DUST ported (`RemovableDust.lua`, removableDust.c): the
    "rock with spikes" is nine dust spikes on the rock's tile types (387,
    1018..1025; SPECIAL_TILE_104 under each); the Gust Jar's first contact
    (or the bomb blast, matrix [$6E][$16] is not $FF) grabs one, its tile
    becomes 388 / 1026..1033 (ACT_TILE_62); the last one lays all nine back,
    loads the rock's MINISH_PORTAL_MANAGER (type 1, type2 $102) and sets
    YAMA_04_ENTHOUSHI ($53); on load with the flag set the middle dust
    (index 4) brings the portal back.  The lone dust at (344, 88) (flag $54,
    ANAHOUSHI) covers the Minish crack $27:03.
  - Mt. Crenel's white dust piles are tile type 111 (interaction mask
    $C028: bomb + Gust Jar); the orange tufts are type 112, collision $0F.
  - The bean chain with real keys (`seg_m19f/g/h.lua`), from a placement on
    the rock plateau (CKPOS, not a route): the nine spikes sucked, the
    portal (`R1_m_rock_portal`), the dust piles cleared to the hole, Minish
    at the rock, the hole at (210, 92) into $12:00 (Link full size there:
    TRANSITION_TYPE_NORMAL), the bean (type 3) lifted with R, carried out
    (WATERBEAN_OUT; outside it is the type-0 bean in his hands), thrown into
    the hole at tile (17, 2) (WATERBEAN_PUT), grown again at the rock
    (`G7`), then from the planted bean's checkpoint the Mineral Water poured
    (bottle $27 -> $20), 192 frames still, YAMA_04_00, the vine, up into
    $06:03 (`H1_m_bean_vine`, `H1_m_center`).
  - NOT found: the way onto the upper-west plateau in a real run.  From
    the base, the stone-portal plateau, the cave pocket by $26:0A (reached
    by bombing the cracked wall at (312, 312) and walking $26:0B -> $26:0A,
    `E1`) the tufts, cliffs and one-way ledges close it off, even with every
    dust pile and bomb tile counted as open (`p_world19.lua` over $06:00-$04,
    the $26 caves and $35:00: from the base only $06:04, $26:09, $26:0B,
    $26:0C, $26:0D, $26:0F are reached).  The tile flag table at ROM
    $08000360 (sub_080B1B84: bit 2 -> layer 1, bit 4 -> layer 2) gives no
    layer-2 tiles on that plateau.  Not tried: Minish-only gaps elsewhere,
    the vine at (456, 24) to $35:00, the north side ($06:03 down).
  - NOT done: the Grip Ring cave and wall climb, Melari's mine, the Cave of
    Flames entrance in one run; the ladder top's real exit (the cave's top
    row is collision $0F, so the border rule does not fire; PlayerClimb's
    top not traced).
  - Mt. Crenel's enemies on their own code (`EnemyCrenel.lua`): TEKTITE
    (tektite.c: the hop timers, gravity Q_8_8(24 / 40), jump 2.5 / 3.0,
    BounceUpdate, wall bounce, aim by home / Link), FALLING_BOULDER
    (fallingBoulder.c: hidden until Link is $38 px into the room, the
    bounce tables gUnk_080CD568 / 580 / 58C by the tile under it, collision
    only 12 frames after a bounce, back to its start off the bottom edge),
    SMALL_PESTO (smallPesto.c: z 12 / 13 flicker, home / random headings).
    The boulder is seen rolling in `S1_smoke_*`.  Spiny Beetle, Rollobite,
    Spiked Beetle, Peahat, Helmasaur, Keese keep the older models.
- [ ] R19.3 Cave of Flames: not reached in one run (the round-7/8 harness
  bot still covers carts, the cane and the simplified Gleerok).
- [~] **R19.4 Leftovers.**
  - the rupee "taken" key: a list without a ROM address keys each entity by
    its data (area:room:kind:id:params:x:y), so it is the same after a
    reload (test);
  - bomb smoke: SMOKE_PARTICLE does draw (`S1_smoke_3/8/14`: the spark, the
    flash, the fade, animation 1 frames 0..8); round 18's shot was taken on
    its first, nearly empty frame;
  - the item-get pose: Objects:drawItemIcon falls back to LINK_HOLDING_ITEM
    ($0B) and FOUR_ELEMENTS ($AC) frames (animation = item) when GROUND_ITEM
    has none (the elements);
  - Wall Masters: gWallMasterScreenTransitions for Deepwood ($48:0B at
    ($A8, $B8)) and the Cave of Flames ($50:04 at ($98, $A8)) (test);
  - NOT done: lifting / throwing bombs, remote bombs, Gentari's frame, the
    HUD under the flash, particles, the $09:00 door script.
- [ ] R19.5 effects: not started.
- Tests: `tests/zelda_tmc_r19_test.lua` (30 checks, fake data).

## Round 20

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r20/`.
`r20/run.sh <script> [out]` (real runtime, one LOVE at a time, below-normal
priority, 1 ms a frame, save dir `r20/appdata` on G:, slot 1 reset),
`lib_r20.lua` / `lib_r20x.lua` (round 19's libs with checkpoints and shots
in r20; new: `H.glideTo` (steers a glide with real keys), `H.whirls`,
`H.smashPots20` (an older lib's `H.smashPots` has another signature -- the
first final run Z1 stopped in the boss segment on that name clash), `H.healFairies`, `H.clearPeahats`), `p_seg.lua` (checkpoint
+ segments), `route20.lua` (the whole route: round 19's segments, then
`seg_m20a0 .. seg_m20m`), probes `p_whirl.lua` (tile grids), `seg_survey.lua`
(exits, entities, reach PNG), `seg_reach*.lua`, `seg_gdbg.lua`,
`r20check.sh`, `hx.sh`, `p_audit.lua`.
**Cache version: still 16** (no import change).

- [x] **R20.1 The whole route in one run.**  A first full run with the
  round-19 fixes was stopped early (the machine ran it at ~30 fps); the
  final clean run (Z3, below) covers it: every round-19 step passes again.
- [x] **R20.2 The real way onto Mt. Crenel's rock plateau.**  Diagnosed
  from the data and a walkthrough (Thonky's Mt. Crenel page, step 4/5): the
  base's two WHIRLWIND objects ($5E at (376, 376) and (296, 352),
  Entities_MtCrenel_Entrance_0) were never spawned -- the **engine** had no
  whirlwind and no PLAYER_PARACHUTE; the round-19 flood fill could not
  know either, and it also ran full-size Link only (Minish Link gets
  through the dust piles' gaps to the bean hole).  The cartridge's way:
  base -> the cracked wall at (312, 312) (flag $51) -> $26:0B -> $26:0A ->
  the pocket at (408, 232) -> the ledge at (376, 336) jumped south through
  the first whirlwind -> Ezlo's cap opens -> glide west through the second
  -> pressed west against the cliff face (act $2C, x 272..287) Link is
  carried up onto the lower-left cliff top (sub_0807A2F8) -> west, up the
  ladder (168, 265) -> the upper plateau.
  - `Whirlwind.lua` (new): whirlwind.c (Init: z -24 unless type2 1;
    Action1 catch rule: not Minish, 12 x 12 box, jumping / parachuting off
    the ground or z <= -16; Action2 waits until Link leaves the box),
    PlayerParachute sub-states 0..5 (ACTIVATE, zVelocity -1.0 then 4.5625,
    gravity / 2, / 4, * 2, the 481-frame glide at speed $80, the 32-way
    direction turning $20 / 256 a frame towards the pad, the facing's 7/32
    hysteresis and TURN / TURN2 animations, z = -8 - timer / 20, R / iframes
    let go -> ANIM_PARACHUTE_FALL), sub_0807A2F8(0) (blocked facing a ledge
    face whose 1 - 2 tiles are gUnk_0811C1D8[facing] act tiles, the tile past
    them open -> up to z -32, across at $80, z += 0.296875, down when the
    axis coordinate & $F == 8 over an open tile), the fall (DoJump with
    jump_status $40: straight down, ANIM_LAND, SFX_PLY_LAND), EZLO_CAP_FLYING
    type 0 (affine scales $180 -> opening -> sub_080936C8's breathing,
    frame 0 / 1, mirrored facing east, sub_0806FCF4's offset).  Hooks:
    Dungeon:spawnObject, Player:hurt (a hit while gliding = the fall).
  - The same mechanism carries Link in Mt. Crenel's middle ($06:03: the
    ledge (680, 72) into the whirlwind (680, 120), the glide through
    (600, 120), up over the face at x 576 to the ladder to $06:02).
  - Room transitions the fill did not model: none needed; ledges: the
    pocket's south ledge is the one jumped; Minish-only gaps: Minish Link
    from the rock portal reaches the hole at (210, 92) on his own
    (`seg_reach2.lua`: `reach 214,100 true`); the vine at (456, 24) is
    $35:00 BEAN_PESTO, a dead end (its only exit is back); coming down from
    $06:03 is the left strip (x ~56), which is how the walkthrough's first
    Piece of Heart cave is reached.
  - Bot: the Minish path's Pestos are fought before the bean is lifted (the
    walkthrough's "kill the Tiny Pestos" step).
  - Also found by data: the rock portal is entered from its south (or north)
    side only (its east / west neighbours are walled), so round 19's
    segment G (west side) became `seg_m20e` (south side, then Minish to the
    hole).
- [~] **R20.3 Mt. Crenel's middle, the caves, the Cave of Flames entrance
  room** (real keys, in the final run): the Water Heart Piece cave $26:08
  (cracked wall (56, 264), the east stone bombed, the east chest: 50
  Rupees), the Bomb Business Scrub $26:0D (offer 2, 10 bombs for 30), the
  center's fairy fountain $26:05 (heals), the pot-and-chest cave $26:07
  (bombed wall (840, 88)), the Spiny ChuChu puzzle $26:06 (the right
  cracked stone bombed, the right block and the top block pushed north,
  out by (760, 56)), the whirlwinds, the ladder into $06:02.
  - NOT done: the Grip Ring.  `seg_m20n` reaches $06:02 with the bomb and
    the 40 Rupees, but the bot does not survive the Peahats on the way to
    the wall at (488, 472) (their home rects cover the whole bottom of the
    room; the gust-jar counter works when aimed -- `seg_gdbg.lua`: grabbed ->
    action 5, hitType $71 -- but the bot's timing loses).  Wall climbing,
    Melari's mine, the Cave of Flames, gleerok.c, the Fire Element and the
    sword upgrade were not reached.
- [~] **R20.4 Leftovers.**
  - Peahat on its own code (`EnemyCrenel.peahat`, peahat.c: fly / charge
    start / charge / charge end, the Gust Jar's OnGrabbed (new hook
    `e.onGrabbed` in GustJar.grabbedUpdate) -> stunned -> repair ->
    takeoff); the old "only grounded Peahats can be hit" rule is gone, the
    collision matrix decides ($70 x sword: no damage, knockback; bombs hurt).
  - Lifting and throwing bombs (`Bombs.tryLift / throw / drop`,
    RegisterCarryEntity's subactions; keeps ticking, timer <= 60 on landing,
    going off in Link's hands clears him).
  - Fixes found on the way: carrying the Crenel bean overwrote Link's
    "hurt" and "dead" states every frame (CP.updateSprout), so a Link hit
    by the Minish path's Pestos while carrying it went on at 0 hearts (seen
    in the stopped run Z2); a touched fairy healed nothing (Field:giveItem
    had no ITEM_FAIRY: gItemMetaData type 1 ModHealth($20)); ground fairies
    gave 6 hearts (now $20); ITEM_BOMBS5 drops ignored the bag size (19 of
    10 were seen) -> Bombs.mod.
  - NOT done: Spiny Beetle (needs OBJECT_ON_BEETLE), Rollobite, the
    ladder-top exit's cartridge rule (traced: UpdateDoorTransition fires on
    act $3F / $F1 / $28 / $29 with only area / type-3 exits; $26:0C's way
    up is a BORDER exit, so it is the border rule's $FF probe -- not
    changed), the dust spikes' priority (removableDust.c type 0 keeps its
    entity-data layer; not traced further, not changed), Gentari's frame, particles, the $09:00 door.
- Tests: `tests/zelda_tmc_r20_test.lua` (42 checks, fake data);
  `zelda_tmc_round3_test.lua`'s Peahat check updated to the matrix rule.

- **Final check (round 20):**
  - The new-game route with real key events (`r20/route20.lua`, MAXFRAMES
    400000, run Z3, `r20/out_route20_Z3.txt`): **187 PASS / 0 FAIL** in one
    run from the title to frame 211327: round 19's steps (Deepwood, the Big
    Green ChuChu, the Elder, Belari, Mt. Crenel's base, the Mineral Water),
    then A0 (the Rupee Fairy Fountain $26:09), A1-A5 (the bombed wall at
    (312, 312), $26:0B, $26:0A, the pocket), N1-N4 (the whirlwinds, the
    glide, carried onto the cliff top), H1-H3 / I1-I4 (the Water Heart Piece
    cave: 50 Rupees), O1-O3 (10 bombs from the Bomb Business Scrub, back to
    the pocket), N1-N4 again, N5-N6 (the ladder, the dust piles), M23-M30
    (the Minish rock's portal, Minish to the hole, the bean carried out and
    thrown in, grown, the Mineral Water, the vine into $06:03), J0 (the
    fairy fountain $26:05: 18 -> 32), J1-J2, K1, L1-L4 (the block puzzle),
    P1-P4 (the middle's whirlwinds, the ladder into the Cave of Flames
    entrance room $06:02).  Runs Z1 (helper name clash) and Z2 (Link went
    on at 0 hearts with the bean -- the CrenelPath fix) were stopped.
  - Shots (`r20/shots/`, all looked at; sheets `Z3_sheet1.png`,
    `Z3_sheet2.png`): `Z3_a0_fountain`, `Z3_a_wall_open`, `Z3_a_pocket`,
    `Z3_n_rise`, `Z3_n_glide` (Ezlo's cap open), `Z3_n_second`,
    `Z3_n_ledge_up`, `Z3_n_cliff_top`, `Z3_h_wall`, `Z3_i_chest`,
    `Z3_o_bombs`, `Z3_n_ladder_top`, `Z3_n_rock_reached`,
    `Z3_m_rock_portal`, `Z3_m_rock_minish`, `Z3_m_bean_lift`,
    `Z3_m_bean_thrown`, `Z3_m_bean_vine`, `Z3_m_center`, `Z3_j0_fountain`,
    `Z3_j_wall`, `Z3_k_pots`, `Z3_l_push2`, `Z3_l_out`, `Z3_p_second`,
    `Z3_p_ledge_up`, `Z3_p_coe_room`; from checkpoint runs: `N1_n_*`
    (the first glide), `C4_p_ledge_up`.
  - All 31 `tests/zelda_tmc_*` files pass (r20: 45 checks).
  - Harness cache rebuilt (still version 16), old Deepwood bot 24/24 (5985
    frames), Crenel bot 28/28 (8580 frames) (`r20/r20check.sh`,
    `r20/out_r20check.txt`); static room audit 605 / 605
    (`r20/out_a_rooms.txt`); runtime audit 2665 windows: the same 6 rooms /
    14 windows as rounds 18 and 19, all explained there
    (`r20/out_p_audit.txt`, identical to `r18/out_p_audit.txt`).

## Round 21

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r21/`.
`r21/run.sh <script> [out]` (round 20's driver with its save dir in
`r21/appdata`), `lib_r21.lua` / `lib_r21x.lua` (checkpoints and shots in r21;
`lib_r21p.lua` = `H.pea21`, the per-frame Peahat / foe / path controller;
`lib_r21c.lua` = `H.climbDodge`, climbing past FALLING_BOULDERs), `p_seg.lua`
(checkpoint + segments), `route21.lua` (route20 + `seg_m21n`, `seg_m21p`,
`seg_m21q`, `seg_m21r`), probes `seg_peatrials.lua` (N crossings of $06:02),
`seg_peacut.lua` (sword on a downed Peahat), `seg_beetle.lua`,
`seg_climbscan.lua`, `seg_survey2.lua`, `p_world21.lua` (round 19's
multi-room flood fill on the r21 libs, several targets), `r21check.sh`,
`hx.sh`.
**Cache version: still 16** (no import change).

- [x] **R21.1 The Peahat fight and the Grip Ring.**
  - The bot's losses were partly ENGINE: Peahat_OnCollision was not ported.
    On the cartridge a flying Peahat that touches Link (contactFlags $80 =
    Link's hurtType 0 | CONTACT_NOW) goes back to Fly with timer 30, speed
    $80, NO direction ($FF: it hovers until the next 16-frame turn) and
    flyTimer 120 (no new charge for 120 frames).  Without it the port's
    Peahat kept charging through Link and hit him again and again.  Now
    `EnemyCrenel.peahatCollision` (also $9B = the Gust Jar's puff: broken
    propeller; $94 = hurtType $14: the sliced propeller -> GravityUpdate(28)
    -> Recover 150 -> Hop 240 -> Takeoff with animation 4) and Stunned moves
    along its direction (ProcessMovement0, the knockback's when it has none).
    The hook is generic: `Enemies` calls `e.onCollision(E, e, hurtType | $80)`
    for Link's body contact and for item hits (after the matrix's iframes).
  - Sword on a downed Peahat (hitType $71): matrix $71 x sword = 2 damage,
    knockback 12 frames, iframes 12 -> two cuts kill (health 4)
    (`out_c1.txt`: 4 -> 2 -> 0); flying ($70 x sword): 0 damage, knockback
    24, iframes -12 -- as the decomp's matrix.
  - Bot (`H.pea21`): during ChargeStart (60 frames still) or the $FF hover
    Link steps onto the Peahat's axis so it sits 20 px past the jar's mouth
    (gUnk_08126EE4: N (0,-32), E (22,-6), S (0,12), W (-22,-6)), faces it and
    holds the Gust Jar: OnGrabbed subaction 0 downs it, the tolerance runs out,
    it is caught and shot out (subaction 5 -> health 0).  6/6 crossings of
    $06:02 from the checkpoint with different idle waits (`out_t1.txt`: 0-3
    hits taken), then the full route.
  - `seg_m21n`: across $06:02, the wall at (488, 472) bombed, $26:04, the
    Business Scrub's Grip Ring for 40 Rupees.  (After the purchase the bot
    closes texts with B: A facing the scrub talks again -- its sold-out text
    $2911, cartridge behaviour.)
- [x] **R21.2 Climbing with the Grip Ring.**  Climb.lua (round 8, PlayerClimb /
  SurfaceAction_ClimbWall / _2C) was checked against player.c and needed no
  change; it is now proven in the real runtime: up the $06:02 east wall into
  the pocket (`K2_climb_mid`, `K2_climb_top`), down the $06:02 south-east
  wall over the border into $06:03 (Thonky step 6), up $06:03's left rock
  wall into $06:01 and up the Crenel Wall (its right column, x ~240) over the
  top border into the summit $06:00.  Border exits fire while climbing (the
  round-19 border rule).  Harness gotchas: lib_fight13's edge guard holds
  back direction keys within 14 px of an edge unless `H.freeExit` is set; a
  seamless room change drops held keys (re-press after it).
  - The FALLING_BOULDERs on the wall only hurt in the 12 frames after a
    bounce: `H.climbDodge` simulates each shown boulder's next landing and
    steps aside (0 hits on the wall in the final runs).
- [~] **R21.3 Melari's mine.**  Not reached.  The route to it is known
  (Thonky's Mt. Crenel page, steps 13-25): from the summit east to a
  mushroom, the Minish portal and the Minish path $12:02, the round-boulder
  puzzles, the caves with block puzzles, the Minish path west to Melari's
  Mines $10:00 (entered as Minish; its exit 2 is the special warp at
  (192, 312) in $06:02's middle-left area, next to the Cave of Flames ladder
  (104, 114) -> $50:03).  Data checked: `out_v1.txt` (room exits), the flood
  fills `out_wf/wg/wh/wi/wj.txt` (the fill cannot model portals / Minish
  paths / the bean vine).
- [~] **R21.4 Cave of Flames.**  The dungeon was not reached; its two missing
  enemies are ported (`EnemyBeetle.lua`, new):
  - Spiny Beetle (spinyBeetle.c) + OBJECT_ON_BEETLE ($7D,
    objectOnSpinyBeetle.c): the tile under it becomes SPECIAL_TILE_34; it pops
    out when Link is lined up within 8 px and $30 px (north only after the
    first time), walks 120 frames carrying its rock (z from gUnk_08123558),
    burrows into the first free tile backwards and waits $78 frames; the rock
    lifted / pulled by the jar / flipped by a blast -> exposed (hitType $19,
    the "!" bubble, runs away from Link).  The rock is liftable, breaks into
    FX_BUSH + type when thrown; the jar holds a rock (gustJarFlags 2) and
    shoots it.  Real runtime in $06:02 (`out_b5.txt`, `B5_beetle_out.png`:
    the beetle with its rock up, popped when lined up; beaten with the sword
    once exposed).  The rock is frame 0 of sprite 167 (frame 1 is another
    object -- the first try drew that).
  - Rollobite (rollobite.c): walk / turn / pick, rolled up by a hit (health
    $FF, hitType 35), BounceUpdate(40), liftable, thrown it lands rolled,
    into a $71 / $72 hole -> SPECIAL_TILE_52, the jar catches and shoots it
    (OnGrabbed subaction 5).  Unit-tested only (it lives in the Cave of
    Flames).
  - Hooks added for them: `e.carryHook` (Objects:tryAction: an entity that
    stays itself while carried), `c.hook.throw / drop` (Objects:throwCarried
    / dropCarried), `e.onJarLost` (GustJar.grabbedUpdate's let-go),
    `e.onShotEnd` (GustJar endShot), Objects:breakThrown for $7D.
  - Not done: the Cane of Pacci in the dungeon, the minecarts route,
    gleerok.c (BossGleerok is still round 8's), the Fire Element, the White
    Sword.
- [~] **R21.5 Leftovers.**
  - Ezlo's cap strings while gliding: EzloCapFlying type 1 (frame
    ((dir + dir / 2) >> 2) + 2, y offset $18 - ($18 * ($10000 / unk_72) >> 8),
    under the cap) are drawn (`G1_n_glide.png`, `G1_zoom.png`).  The camera:
    the cap is the camera target but copies Link's x / y every frame, so the
    port's camera on Link is the same picture.
  - The thrown bomb: PlayerItemHeldObject's throw (sub_080AD27C: carryFlags 0
    -> speed $400, zVelocity 0, z 8 px lower than held; GravityUpdate(32);
    the first landing bounces at half speed with zVelocity 1.0 and
    SFX_PLACE_OBJ $104; SFX_PLY_VO5 on the throw).
  - Not done: Gentari's frame, the particle types, the $09:00 door script;
    the climb step's collision with non-climbable walls (UpdatePlayerCollision)
    is still skipped (Link only leaves a climb surface onto open floor in the
    rooms tried).
- Tests: `tests/zelda_tmc_r21_test.lua` (27 checks, fake data: Peahat
  OnCollision branches, the $FF hover, the sliced fall; Spiny Beetle init /
  pop / exposure / OnCollision; Rollobite roll-up, hole, carry and throw).

- **Final check (round 21):**
  - The new-game route with real key events (`r21/route21.lua`, MAXFRAMES
    420000, run Z1, `r21/out_route21_Z1.txt`): **196 checks, 195 PASS / 1
    FAIL** in one run from the title to Mt. Crenel's summit $06:00 at frame
    228509: all 187 round-20 steps, then N0-N3 (the Peahats crossed, the
    wall bombed, the Grip Ring bought), P1 (down into $06:03), Q1-Q2 (up into
    $06:01), R2 (over the wall into the summit).  The one FAIL was R1, the
    bot's goal tolerance at the Crenel Wall's top (Link at (242, 12) vs goal
    (240, 10), near 4); the bot then stalled 12000 frames there before R2
    took him up anyway.  Fixed (near 8) and re-run from the run's own
    checkpoint `route_r21_m_0601` (`r21/out_z1r.txt`: R1 + R2 pass, 0 boulder
    hits).  The whole route was not run again (about two hours at the
    machine's ~33 fps).
  - Segment runs from checkpoints: `out_chain.txt` (N0-R2, 9/9),
    `out_t1.txt` (6/6 Peahat crossings), `out_c1.txt` (sword on downed
    Peahats), `out_b5.txt` (Spiny Beetle), `out_g1.txt` (glide, 4/4).
  - Shots (`r21/shots/`, looked at): `P1_pea21_end`, `P2_n_grip_ring`,
    `K2_climb_mid`, `K2_climb_top`, `climbtop_reach`, `Q1_q_in_0601`,
    `R2_r_summit`, `R3_r_summit`, `B5_beetle_out`, `B5_beetle_exposed`,
    `rock_sheet_z`, `beetle_sheet_z`, `G1_sheet`, `G1_zoom`.
  - All 32 `tests/zelda_tmc_*` files pass (r19's "$35 not handled" and r20's
    throw speed 2.5 checks updated to the round-21 behaviour).
  - Harness cache rebuilt (still version 16), old Deepwood bot 24/24 (5985
    frames), Crenel bot 28/28 (8580 frames) (`r21/out_r21check.txt`); static
    room audit 605 / 605 (`r21/out_a_rooms.txt`).

## Round 22

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r22/`.
`r22/run.sh <script> [out]` (round 21's driver, save dir `r22/appdata`),
`lib_r22x.lua` (r22 checkpoints falling back to r21's; `H.pushRock`,
`H.pushEnt`, `H.pushBlockTile`, `H.solveBlocks` = a breadth-first search over
PushBlock.lua's block rules, an ACT_TILE_13 pit hazard for the planner),
`p_seg.lua` (checkpoint + segments), `chain.sh` (the round's segments in one
process), `route22.lua` (route21 with `seg_m22j0` / `seg_m22ra` / `seg_m22ro`
in place of r20's J0 / A / O, `seg_m22gr` in place of `seg_m21n`, + segments
A-Q), `route22tail.lua` (the same from a checkpoint of its own run), `r22check.sh` (cache rebuild, old
bots), `hx.sh`.  Development-only checkpoints are named `dev_*`.
**Cache version: still 16** (no import change).

- [x] **R22.1 The Grip Ring text box.**  Not missing text: round 21's shot
  `P2_n_grip_ring` came from the run where the bot kept pressing A at the
  scrub (563 sold-out texts, `r21/out_p2.txt`); the shot caught a window still
  opening (scale < 8, no characters yet).  The item's message $0544 is there
  (`r22/p_msg.lua`).  But the item get itself was not the cartridge's, now
  `ItemGet.lua` (player.c PLAYER_ITEMGET + linkHoldingItem.c):
  - PlayerItemGetInit: IdleSouth, ANIM_GET_ITEM_SMALL $2E0 / _BIG $1B9 (or
    _NOCAP $45E / $45B) by IsMinishItem (gItemMetaData flags & 1) -- the Grip
    Ring is a BIG item (both hands); Minish Link keeps his animation (a timed
    fallback).
  - LINK_HOLDING_ITEM: SFX_ITEM_GET on Link's frame flags $41, the message on
    $42 (8 frames in, not at once), the item drawn only on frames with bit $40
    at Link + GetSpriteSubEntryOffsetDataPointer(sprite, frame).
  - sub_08071038: Link puts the item down when the message is closed AND
    the animation is done, then ResetPlayerAnimationAndAction (round 21 left
    him in the item-get pose until he moved).  `Field:messageActive()` is
    true while the message is due.  Timers 1 (no message; the elements'
    FourElements touch) and 3 (no give / sound / message, value 2 on put-down:
    Melari's broken sword) follow InitItemGetSequence.
  - Real runtime: `r22/out_a2.txt`, `shots/A2_n_grip_text.png` (the ring held
    up with both hands, "You got the Grip Ring!" typed out).
- [x] **R22.2 Melari's mines.**  Thonky's steps 1-30 with real keys, and the
  engine pieces they needed:
  - The summit's mushroom gap: sub_08072D54's ledge tiles $1AC-$1AF (the
    flight goes straight over them, subtimer 0-4) -- Link stopped at the
    edge before.
  - PUSHABLE_ROCK ($2E, `PushableRock.lua`, new) + the SPECIAL_TILE_27 push
    (UpdatePlayerCollision, PlayerPush type 1: sPushFrames = 16 px), its
    sub_0801A2B0 check with IsTileCollision type $B (holes $20 are free);
    over a hole: SPECIAL_TILE_21, the flag, SFX_TASK_COMPLETE.  The summit's
    and the pillar cave's boulders were not spawned at all before.
  - The block cave $26:00 and the chest cave $26:03: `H.solveBlocks` finds
    the pushes (10 / 3; the chest cave's plan is Thonky's).
  - The mushroom room: gusts use IsTileCollision type 1 (pits and walls 1-$F
    do not stop them; round 13's "stops at walls" was wrong), so the jar
    clears the pots across the gap as Thonky says.
  - The bridge room $26:02: LIGHTABLE_SWITCH ($9D, `LightableSwitch.lua`,
    new; type 0 toggle, type 1 16-frame light + FLAG_AND latch); a thrown
    bomb now uses IsTileCollision type 10 (flies over pits $21) and is lost
    in a pit / water / lava (FX); thrown from the bridge stub it hits the
    switch, BRIDGE_MANAGER lays the bridge.  ACT_TILE_13 pits now drop Link
    (SURFACE_PIT, sub_08079C30's three probes) -- he walked over the gap.
    Knock-on: round 20's bot also walked over the Mushroom Keese cave $26:0B's
    pit (segments A and O); its route copies `seg_m22ra` / `seg_m22ro` now use
    the cave's mushroom (pulled south, flung north: `H.keeseFling`).
  - A bottled fairy: drinking (+$20) and the death revive (sub_08071D04: +32,
    bottle empty) -- the route bottles one at $26:05 before the fairies
    heal Link (`seg_m22j0`).
  - Melari ($10:00): his script and round-8 natives ran unchanged once
    reached: texts $123D-$1240, Link on the anvil holding the broken Picori
    Blade (timer 3), item $35 = 2, OYAKATA_DEMO (`shots/O2_o_melari_talk`,
    `O2_o_after`).  Then the guard ($1211), the west door, the portal, the
    windcrest (message $3F32) and the Cave of Flames ladder.
- [~] **R22.3 Cave of Flames.**  Entered ($50:03, `C3_q_cof.png`).  Ported:
  BOBOMB ($22, `EnemyBobomb.lua`, bobomb.c without its Gust Jar grab).  The
  first room ($50:16) shows the remaining gap: the bot cannot fight Bob-ombs
  (the route has the jar and bombs on A/B, no sword) and Spiked Beetle,
  Like Like, Helmasaur and Mulldozer are not ported.  Not done: the Cane of
  Pacci chest, the minecart ride (Minecart.lua is round 7's decomp port, not
  re-checked in place), keys, the big key, the Rollobite rooms, gleerok.c
  (1588 lines; BossGleerok.lua is still round 8's), the Fire Element and the
  White Sword.
- [~] **R22.4 Leftovers.**
  - Done: PeahatPropeller (the sliced propeller flies off as its own sprite,
    animation 3, rising $C000 a frame, blinking its last 60 of 240 frames);
    the Spiny Beetle's line of sight is sub_0804A044 / sub_0804A4BC exactly
    (partial tiles by quarter mask, the target's tile not checked, layers).
  - Not done: Gentari's frame, the particle types, the $09:00 door script;
    the hole / water check under the falling propeller (it never lands).
- Tests: `tests/zelda_tmc_r22_test.lua` (41 checks, fake data).

- **Final check (round 22):**
  - Segment chain from the summit (`dev_summit_fairy` = route_r21_m_summit +
    the fairy that `seg_m22j0` bottles): A-I in one process
    (`r22/out_chain_c2.txt`, 18/18 to I3), J from I's checkpoint
    (`out_j5.txt`: the Peahat at the bridge cave door killed Link once, the
    bottled fairy revived him), K-Q in one process (`out_chain_c3.txt`,
    13/13, Melari, the Cave of Flames at frame 21364).
  - Full route with real key events (`r22/route22.lua`, not complete in one
    run):
    - Run Z1 from the title (`r22/out_route22_Z1.txt`): 143 PASS in one go
      (Deepwood, the boss, Belari, the Mineral Water, into round 20's
      Mushroom Keese cave $26:0B at frame ~162k), then FAIL A4: the cave's
      gap is now a real pit (this round's ACT_TILE_13 fix) and round 20's
      bot had walked over it.  Fixed by `seg_m22ra` / `seg_m22ro`
      (`H.keeseFling`, checked in `out_kc3.txt`, `out_ro.txt`).
    - Run Z4 = `route22tail.lua` from Z1's own checkpoint
      `route_r19_m_mineral` (`out_route22_Z4.txt`): 75 PASS in one go
      through all of rounds 20-21 (the fairy bottled at $26:05, the Grip
      Ring with the new item get: `Z4_n_grip_text.png`, the Crenel Wall, the
      summit) and this round's A-G, then FAIL H2: the bot never reached the
      mushroom's stand point in the mushroom room (Helmasaurs; fixed, H
      passes from that checkpoint in `out_h5.txt`).
    - Run Z5 from Z4's `route_r22_g_mush` (`out_route22_Z5.txt`): H1-H3 PASS,
      then I1 FAIL: no bomb was lifted at the bridge stub in that run
      (`Z5_i_bridge.png`); not diagnosed.  Link reached that point with 14
      of 32 health and an empty bottle (the fairy had revived him at the
      Grip Ring's Peahats).
    - The rest of the route ran as segment chains only (above).
    - Also seen: the Peahat by the bridge cave's door ($06:02, (568, 200))
      knocks Link back in repeatedly; `seg_m22j` now steps back in and waits
      while one is within 72 px, then uses round 20's `H.clearPeahats`.
  - All 33 `tests/zelda_tmc_*` files pass.
  - Harness cache rebuilt (version 16), old Deepwood bot 24/24, Crenel bot
    28/28 (its Melari check now waits for the whole cutscene); static room
    audit 605 / 605 (`r22/out_a_rooms.txt`).

## Round 23

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r23/`.
`run.sh` (round 22's driver, save dir `r23/appdata`, imported at cache 17
by `import.sh`), `lib_r23x.lua` (r23/ck checkpoints, falling back to r22's
loader; a checkpoint is NOT written once a check failed in that run),
`p_seg.lua` (checkpoint + segments), `r23check.sh` / `r23route.sh` /
`r23crenel.sh` (harness cache, old Deepwood bot, Crenel bot), `hx.sh` (room
audit).  No run started from the title except one (see the Zelda bug).
**Cache version: 17** (ExtractR23.lua: the tile-type flags).

- [x] **R23.0 (user bug) Zelda "walks through walls".**  zeldaFollower.c has
  no collision on the cartridge: she walks Link's own 20-entry history.  The
  port's trail left out the item's z and framestate (round 6's note "not
  ported: her z"), so on Link's ledge jumps she slid down the cliff face on
  the ground -- drawn inside the wall -- instead of jumping.  Now the whole
  ZeldaFollowerItem: x, y, z, facing, layer, FALL frames; the oldest entry
  in the air keeps her moving (heapPtr->z < 0); hidden on FALL entries, at
  Link + refilled when the fall ends (sub_08068318's own test); the refill
  (sub_08068578) is FixedDiv >> 8 with HER facing / layer; a new follower
  starts facing south (action 0).  Checked: `r23/out_zl.txt` (scene from
  `zf_town` = round 12's festival-town save: Link walks off the town's
  south ledge at (360, 368), Zelda is in the air 39 frames, max z 31),
  shots `ZL_zfl_56.png` / `ZL_zfl_72.png` (she arcs over the wall behind
  Link); `out_z1.txt` (walls / corners in the town, 0 solid frames),
  `out_zb.txt` (town -> castle stairs -> North Field -> garden, from
  `a_end`, 0 solid frames in 6915).  Other followers: none in the port share
  this code (Ezlo rides the cap; kid.c's follower heap is not ported).
  NOTE: `zf_mk.lua` / `out_zm.txt` was one intro run from the title (before
  the no-title rule reached this agent); it rewrote `r10/ck/a_end.lua`
  with an equivalent save.  `zf_field` is a crafted save (round 12's town
  save moved to South Hyrule Field, SOUGEN_01_ZELDA cleared).
- [x] **R23.1 The bridge-room bomb (round 22's Z5 I1).**  Cause: in the
  mushroom room a Helmasaur ($20, then still the generic model) hit Link
  DURING the mushroom fling;
  the hurt state ended the fling with Link at z 61.5 and `jumping` set, and
  `Bombs.tryLift` refuses any z > 0 -- every later lift failed.  The
  cartridge runs the fling with COLLISION_OFF (sub_08072CC0 until
  sub_08072D54's landing): `Player:hurt` now ignores hits while
  `p.fling.phase < 3`.  Reproduced from `route_r22_g_mush` (`out_d2.txt`:
  z=61.5, jumping=true), fixed (`out_d3.txt`, `out_hj.txt`).
- [x] **R23.2 A clean Cave of Flames entrance checkpoint.**  Chain, real
  keys, no dev fairy: `route_r22_g_mush` (round 22's Z4 route) -> H ->
  `seg_m23i` (I + the sword on B, the ChuChus past the bridge fought:
  14 hp kept) -> `seg_m23j` (J with round 21's jar fighter `H.pea21` at the
  bridge-cave door; round 20's clearPeahats stood under a hovering Peahat
  for 6 hits) [`out_hj.txt`, 7/7] -> K-Q [`out_c5.txt`, 13/13] =
  `r23/ck/r23_cof_entry` ($50:03, 14/32 hp, Gust Jar on A, sword on B,
  bombs 7, empty bottle).
- [x] **R23.3 Link on the Cave of Flames' top layer (ENGINE).**  In the
  Cave of Flames the bottom map is ONE tile type ($310) and everything
  (floor, walls) is on the top map; Link stayed on layer 1: hidden under
  BG1 (invisible in every CoF shot of rounds 8-22) and walking through the
  walls (bottom collision empty; `out_dt2.txt`: x 136 -> 13).  The
  cartridge's sub_0807A8D8 (playerUtils.c, every frame from the interrupt)
  reads the tile under Link on his layer in a per-tile-type flag table
  (sub_080B1B84: gUnk_08000360 / special gUnk_080B7A3E): bit 1 -> layer 1,
  bit 2 -> layer 2.  Ported: `ExtractR23.lua` (manifest.r23.tileFlags),
  `Layers.surface` (called first in Player:update).  Also: room enemies get
  LoadRoomEntity's layer (kind byte, else ResolveCollisionLayer); enemy
  movement (EnemyDeepwood.move0's box) uses the entity's own collision
  layer; `Room:isSolid` falls back to the bottom map when a room has no top
  collision; a room change without a transition layer starts Link on layer
  1 (InitializePlayer), a transition with layer 0 resolves it, a mine-cart
  ride keeps its rails' layer.  `out_dt3.txt` + `DT3_walkleft.png` (Link
  drawn, stopped by the wall at x 52).
- [~] **R23.4 Cave of Flames enemies.**  New `EnemyCoF.lua`:
  SPIKED_BEETLE ($1E, spikedBeetle.c whole: walk / wind-up / charge /
  skid, flipped by the shield or the spin into action 6-8 with hitType 100
  / 99) and HELMASAUR ($20, helmasaur.c both types: pawing, the charge, the
  wall recoil + screen shake, the Gust Jar pulling the mask off (OnGrabbed
  subaction 2 -> GustJar's new `onJarPull` hook), the mask swallowed, the
  unmasked wander).  `Enemies:hit` now runs collision handler 10
  (sub_080180E8, the masked Helmasaur, hitType $6F): blocked within +-$C
  of facing the attacker, else row $352 (hitType $19).  The shield's contact
  reaches these two as hurtType 2.  `EnemyBeetle.linedUp` takes
  sub_0804A024's width.  Scenes (harness state, from `r23_cof_entry`):
  `out_en5.txt` 10/10 (Helmasaur actions 1-5, mask off, front block / back
  damage; Spiked Beetle charge, sword no damage upright, shield flip,
  damage on its back), shots `EN5_hel_400.png`, `EN5_sb_charge.png`,
  `EN5_sb_flipped.png`.  Not done: Like Like (no Like Like is in the CoF
  room lists: Spiny ChuChu $0B, Rupee Like $17, Chaser $1D, blade traps
  are), the Bob-omb's Gust Jar grab.
- [~] **R23.5 The dungeon.**  Survey of all 19 rooms (`out_sv.txt`,
  `shots/cofNN_map.png`, positions `out_sp.txt`: 03 entrance, 16 Bob-ombs
  east, 15 compass north of 16, 05 north entrance (Rupee Like, stairs to
  04), 04/06/07/... one floor down).  Segment CA (`seg_c23a.lua`, sword):
  the Bob-omb room cleared from the hp-8 entrance (`out_ca2.txt`, 2/2,
  checkpoint `r23_cof_bobomb`, 2 hp left); from the hp-14 entrance the bot
  died (`out_c5.txt`); a hit-and-run variant did worse (`out_ca3.txt`).
  Not done: the rest of the rooms, keys, big key, the Cane of Pacci chest,
  the minecarts in place (round 7's Minecart.lua still passes the Crenel
  bot's ride), gleerok.c (BossGleerok.lua is still round 8's), the Fire
  Element / White Sword order.
- [ ] **R23.6 Leftovers** (Gentari's frame, particle types, the $09:00 door
  script, the hole / water check under the falling propeller): not done.
- Tests: `tests/zelda_tmc_r23_test.lua` (22 checks, fake data: the follower
  item, the fling's COLLISION_OFF, the tile-type flags / Layers.surface,
  the Spiked Beetle / Helmasaur collisions).

- **Final check (round 23):** all 34 `tests/zelda_tmc_*` pass; static room
  audit 605 / 605 (`r23/out_a_rooms.txt`); harness cache rebuilt at 17,
  old Deepwood bot 24/24 (`r23route.sh`; it was 18/6 until the room-change
  layer reset), Crenel bot 28/28 (`r23crenel.sh`; 24/4 until the mine-cart
  exception).

## Round 24

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r24/`
(`run.sh` real-runtime driver with its own save dir `r24/appdata`,
`p_seg.lua` + `lib_r24x.lua` (checkpoints in `r24/ck`, never written after a
FAIL; `dev_*` copies kept), `lib_r24b.lua` (round-24 bots: a layer-aware BFS
`H.bfs24` that applies the Layers.surface rule while it searches, `H.go24`,
the Bob-omb fighter `H.bob24`, the shield fighter `H.beetle24`),
`hx.sh` (room audit), `r24crenel.sh`).  NO run from the title or a new
game: every run started from a saved checkpoint (r23_cof_entry first).
**Cache version: 17** (unchanged: no extracted data changed).

- [x] **R24.1 The Bob-omb room, reliably (segment B, `seg_bob24.lua`).**
  Round 23's sword fight died from the hp-14 entrance.  New bot: light one
  Bob-omb (a sword hit = bobomb.c's first hit: lit, $200, 200 frames) and
  run to the reachable spot farthest from every lit Bob-omb / blast until
  it is over, repeat.  From `r23_cof_entry` (14 hp): `out_bob1.txt` 2/2,
  `out_c2.txt` / `out_c4.txt` again (hp 14 -> 10 each time: the runs from
  the same checkpoint are deterministic), and from a different start
  (`dev_r24_bobomb` reloaded, the Bob-ombs back: `out_c3.txt` C0, hp 10 ->
  4).  4 passes in 4.
- [x] **R24.2 The compass (segment C, `seg_c24.lua`).**  The Bob-omb room's
  north wall (BOMBABLE_WALL tile entity $34 at (120, 40)) bombed with
  Link's own bomb, north into $50:15; FIGHT_MANAGER spawns two Spiked
  Beetles; the shield flips them (shield held facing the closest charging
  one, kept up while a flipped one bounces away) and the sword kills them
  on their backs; flag $31 shows the big chest (CHEST_SPAWNER type 2) =
  the COMPASS ($51) and opens the west door.  Chain B+C from
  `r23_cof_entry`: `out_c4.txt` 5/5 -> checkpoint **`r24_compass`**
  ($50:15, 8 hp).  Shots `100719_c_wall.png` (the blown wall),
  `100719_c_compass.png`.
- [x] **R24.3 Down to the main cart room (segment D, `seg_d24.lua`).**
  $50:15 west door -> $50:05 -> the stairs (136, 24) -> $50:04 (504, 72)
  [`out_d1.txt` 2/2] -> checkpoint **`r24_maincart`** (8 hp).  Note: $50:05's
  U of blocks ($362/$363/$364 one-way pushables, $365 fixed) is a dead
  end from the entrance side: the way down is through the compass room.
- [x] **R24.4 The rails (ENGINE, CoFRails.lua).**  MINECART_DOOR $6C,
  RAILTRACK $13, HITTABLE_LEVER $2F, RAIL_INTERSECTION_MANAGER $1F ported
  (see minishcap.md round 24); the carts read special tiles 24 / 25 as act
  tiles 242 / 243.  Scene (placement from `r24_maincart`, enemies removed,
  `seg_e24s.lua`, `out_es1.txt` 4/4): the sword flips the lever (flag $1C),
  both turning rails turn (E-W <-> N-S), the intersection tile follows (858
  <-> 855), a second hit turns them back; Link jumps into the cart at (760,
  104), rides west along the bottom rail, the minecart door at (40, 216)
  opens, the ride crosses into $50:06 and ends at its stop (526, 216).
  Shots `101925_es_ride15.png`, `101925_es_end.png`.  Door art: CoF doors
  are now gUnk_0811F690's $52 (`102646_door_04west.png`).
- [x] **R24.5 Spiny ChuChu and Chaser (EnemyCoF2.lua).**  Scene
  (`seg_en24.lua`, `out_en1.txt` 5/5): Link steps into $50:01's region
  trigger -> room flag 0 -> FIGHT_MANAGER drops 8 Spiny ChuChus from z 128
  one by one (their EntityData timers), spikes out near Link (actions 3/4),
  hops (6/7), the sword hurts one with its spikes in; a Chaser in $50:10
  slides at Link when lined up and bumps the wall.  Shot
  `102340_sc_150.png`.
- [ ] **Not done this round:** the route past $50:04 with real keys (the
  bot reaches the stairs at 8 hp; Bob-ombs / red ChuChus / Helmasaurs on
  the lower floor are too much for it at that hp -- the next step is to
  gather hearts from the pots of $50:03 / $50:05 before the stairs), the
  small keys ($50:01 flag $18, $50:08 flag $26), the map (big chest in
  $50:09), the Cane of Pacci chest ($50:01, flag $19, after the Spiny ChuChu
  fight), the big key ($50:17), RUPEE_LIKE $17, the red ChuChu (chuchu.c
  type 1), LAVA_PLATFORM $59, OBJECT_ON_PILLAR $6D, MINISH_PORTAL_STONE
  $74, **gleerok.c** (BossGleerok.lua is still round 8's simplified
  model), the Fire Element, the exit, the White Sword.  (The Cane itself
  was already ported in round 7: Pacci.lua.)
- Tests: `tests/zelda_tmc_r24_test.lua` (33 checks, fake data: lever,
  turning rail, intersection, minecart door axis / open / shut, the door
  art table, Spiny ChuChu init / collisions, Chaser contact).

- **Final check (round 24):** all 35 `tests/zelda_tmc_*` pass (the round-7
  cart test needed a guard for fake rooms without tileType); static room
  audit 605 / 605 (`r24/out_a_rooms.txt`); Crenel bot 28/0
  (`r24crenel.sh`).  New checkpoints (r24/ck): `r24_compass`,
  `r24_maincart` (+ `dev_r24_bobomb`, `dev_r24_compass`,
  `dev_r24_maincart`).

## Round 25

Setup: scratch under `G:/Gen2Recomped/scratch_claude/zelda/tmc/r25/`
(`run.sh` real-runtime driver with save dir `r25/appdata` (imported at cache
18 by `import.sh`), `p_seg.lua` + `lib_r25x.lua` (checkpoints in `r25/ck`,
never written after a FAIL; `dev_*` copies kept), `lib_r25.lua` (round-25
bots: `H.bfs25` -- a layer-aware BFS whose path follows the (cell, layer)
states; round 24's cell-keyed path mixed layers and walked Link into walls
in $50:04 --, `H.go25` with an avoid set and a stuck-walk fallback,
`H.smash25` / `H.collect25` pots and drops, `H.ride25` the mine cart,
`H.bomb25`, `H.helmaFight25`), `gleebot.lua` (the Gleerok fight bot),
`hx.sh` (room audit), `r25check.sh` (harness cache rebuild + Crenel bot)).
NO run from the title or a new game: every run started from a checkpoint.
**Cache version: 18** (ExtractR25.lua: the Gleerok tables).

- [x] **R25.1 Hearts before the stairs (segment E, `seg_e25.lua`).**  From
  `r24_compass` ($50:15, 8 hp): west into $50:05, the four pots (two heart
  pots, paramA $5F), the drops collected, the Rupee Like avoided (a rupee
  until touched), the stairs: `out_e1.txt` 3/3 -> checkpoint
  **`r25_maincart_hp`** ($50:04, 24 hp).  Shot `115030_e_pots.png` (the
  Rupee Like as a green rupee).
- [x] **R25.2 The mine cart west (segment F, `seg_f25.lua`).**  From
  `r25_maincart_hp`: out of the stairs box through the layer-1 corridor
  under the upper floor (bottom tiles 961 / $310), along the bottom rail to
  the right part, into the cart at (760,104), the ride through the minecart
  door into $50:06's bottom row (stop (500,216)): `out_f1.txt` 1/1 ->
  checkpoint **`r25_cartwest`** (24 hp).  Shot `120807_f_06.png`.
  Map facts: $50:04's lever (376,88) stands on the upper walkway reached
  only through the small-key doors (600,56) / (680,56) (flag $1D); $50:06
  is two rows of three compartments joined only by rails (the top row via
  the minecart doors (440,56) / (504,56) / (648,56)); its bombable walls
  are (40,200) flag $1F -> $50:07 and (552,24) flag $1A -> $50:02.
- [ ] **R25.3 The Helmasaur room (segment G, `seg_g25.lua`): FAIL.**  The
  west wall bombed, $50:07 entered (G1 ok), but the four Helmasaurs killed
  the bot (18 hp on arrival; `out_g1.txt`).  No checkpoint written.  The
  next step: more hearts (the 06 compartments' pots) and a better fighter
  (the Gust Jar needs the Helmasaur lined up 16-48 px; its charge hits
  first).
- [x] **R25.4 LAVA_PLATFORM $59, OBJECT_ON_PILLAR $6D, MINISH_PORTAL_STONE
  $74 (CoFObjects.lua), RUPEE_LIKE $17 and the red ChuChu (EnemyCoF3.lua).**
  Scene (placement, harness state, `seg_obj25.lua`, `out_obj.txt` 10/10):
  $50:07's stone hidden and its portal unusable until flag $22, then the
  fade (Link held), the tiles $4040-$4048, TINY_ENTRANCE, the portal works;
  $50:09: Link on a platform, 20 frames, the wobble, it sinks, the lava
  under it held him up meanwhile (158 frames of field_0x14); $50:00: the
  Cane's bolt flips an upside-down platform (the spawner's flip); $50:01:
  Link pushes the pillar block one tile (tile 54 -> 55 -> 54); $50:05: the
  Rupee Like is a rupee, holds Link, eats 3 rupees in 200 frames, the
  button mash frees him; $50:04: a red ChuChu rises, chases, sinks and
  slides (actions 2/3/4/7/8).  Shots `121859_ob_*.png`.  Survey of the
  rooms (`out_sv.txt`, `out_sv2.txt`): platforms in 00, 08, 09, 17 move on
  their rails.
- [x] **R25.5 Gleerok (BossGleerok2.lua, gleerok.c).**  Scene (placement,
  `seg_gl25b.lua`, the Cane given, Link's hp refilled each frame): the
  intro (Link looks round, shake, the plug grows, the rise, the scripted
  moves), the fight (turn / track / breath / sweep), the Cane knocks the
  plug out, the neck lies down, the sword on the core (2 per hit, 15 / 15 /
  10 to the thresholds), the four lava pools after a phase, three phases,
  the death and the BG blend: `out_gl5.txt` (25 bolts, 63 swings, beaten),
  the element ($AC) appears.  Shots `113148_gl_700.png` (the rise),
  `114357_gl_cooled.png`.  Without the refill (32 hp) the bot dies
  (`out_gl6.txt`: it stands still under the fireballs).  The harness Crenel
  bot now fights the real Gleerok too (hp refilled there as well): 28/0
  (`r25/crenel_out.txt`, `r8/crenel/crenel_log.txt`: Gleerok beaten, Fire
  Element, heart container).
- [ ] **Not done this round:** the Helmasaur room with the bot, the Minish
  way to $50:09, the map, both small keys ($50:08 flag $26 via the pillar
  block in its hole, $50:01 flag $18 via the pillar block -> chest), the
  key door to the lever, the Cane of Pacci chest ($50:01 flag $19 after the
  Spiny ChuChu fight), the lower floor ($50:10..$50:17), the big key
  ($50:17 flag $39), Gleerok in a chained run, the Fire Element / exit /
  the smith and the White Sword.
- Tests: `tests/zelda_tmc_r25_test.lua` (44 checks, fake data).

- **Final check (round 25):** all 36 `tests/zelda_tmc_*` pass
  (`r25/out_tests.txt`); static room audit 605 / 605
  (`r25/out_a_rooms.txt`); harness cache rebuilt at 18, Crenel bot 28 / 0
  with the ported Gleerok.  New checkpoints (r25/ck): `r25_maincart_hp`,
  `r25_cartwest` (+ `dev_*` copies).

## Round 26 (team A)

Scope: overworld, items and side systems (team B did the dungeons at the same
time).  Rule this round: no route or bot playtest; checks are unit tests, the
room audit and short in-place scenes.  Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/tmc/r26a/` (`run.sh`, `p_seg.lua`,
`lib_r26x.lua`, scenes `seg_items26.lua`, `seg_enemies26.lua`,
`seg_survey.lua`, `hx.sh` = the audit).  **Cache version: unchanged by team
A** (team B moved it to 19 for its own tables).

Hooks (one anchored line each): `Crenel.useItem` -> `ItemsR26.use`;
`Field:giveItem` -> `ItemsR26.giveItem`; `Dungeon:checkFall` (deep water) ->
`ItemsR26.water`; top of `Player:update` -> `ItemsR26.frame`; after Link's
draw -> `ItemsR26.draw`; Player's walk animations -> `ItemLantern.walkAnims`;
`Enemies:update` -> `EnemyField.handles/update` (before the generic model);
`Crenel.spawnObject` -> `ItemOcarina.spawnObject` (BIRD $95).

- [x] **Items** (one module each, all through `ItemsR26.lua`):
  Boomerang + Magic Boomerang (`ItemBoomerang.lua`, playerItemBoomerang.c:
  windup, flight $200/$280, steering, tile hits, return, item carrying, hurt
  $14), Bow + Light Arrows (`ItemBow.lua`: pull-out/hold/shoot, arrows $300,
  wall stick, light arrow charge to hurt $0E, quiver/arrow GiveItem cases;
  ammo is `stats.arrowCount`), Roc's Cape (`ItemCape.lua`: DoJump, the held
  cape boost under half gravity, landing, air crossing of pits, Down Thrust
  hand-over), Pegasus Boots (`ItemBoots.lua`: the $1E charge, $300 run,
  steering, PlayerBounce on walls, DASH_SWORD with the Dash Attack scroll),
  Mole Mitts (`ItemMitts.lua`: floor digs through the tile table, soft walls,
  clang), Lantern (`ItemLantern.lua`: on/off, ANIM_LANTERN walk, burning
  torches/tiles), Flippers (`Swim.lua`: PlayerSwimming, A stroke, B dive
  finds sunken items), Ocarina (`ItemOcarina.lua`: ANIM_OCARINA, Zeffa (BIRD
  type 8) picks Link up, Subtask_FastTravel on the world map page with the
  crest markers, YES/NO message $0704, warp gUnk_08128024, type-9 drop),
  sword techniques (`SwordSkills.lua`: charge, spin, Great Spin, Roll Attack,
  Rock Breaker, Sword/Peril Beam, Down Thrust).
- [x] **Overworld enemies** (`EnemyField.lua` dispatcher):
  `EnemyField1.lua` Leever, Rock ChuChu, Acro Bandit, Keaton, Crow, Scissors
  Beetle, Cucco (aggr.), Ghini; `EnemyField2.lua` Spear Moblin (+spear), Bow
  Moblin (+arrows), Takkuri (StealRupees), Lakitu + cloud + lightning, Cloud
  Piranha, Armos.  Survey (`out_survey.txt`, `out_enemies.txt`): every
  overworld room of areas 02-0B, 11, 13, 15, 19, 1A, 06/07 entered, 90
  frames each, no runtime error; still on the generic model: Beetle $07 (one
  form), Moldworm $0F, Like Like $14, Bomb Peahat $1B, Dust $53.
- [x] **Scene** `seg_items26.lua` (`out_items.txt`, 10/10, real runtime from
  checkpoint r25_cartwest, Link placed in Hyrule Field $03:01 / Lake Hylia
  $0B:00): cape jump peak 50 px held, boots dash, boomerang out and back,
  one arrow, lantern lit, mitts dig, charge + spin, swimming, ocarina ->
  bird -> fast-travel map -> Hyrule Town.  Shots `r26a/shots/164947_it_*`.
- Bug found and fixed in the scene: a tracked entity named a field `button`
  (Dungeon:update treats `e.button` as a floor switch) -> renamed
  `useButton`; a room change cut the boots' bounce and left z = 0.01, which
  blocked every later item -> reset in `ItemBoots.frame`.
- [ ] **Not done (team A scope):** Four Sword clones and the spiral beam;
  the Ezlo talk on the first warp (WARP_1ST); Bomb Peahat, Moldworm, Like
  Like (overworld), Dust; the overworld NPC side quests (figurine gallery /
  shells, Carlov, Rem, the Postman, Anju's cuccos, Swiftblade/Smith scroll
  NPCs beyond their ROM scripts), Kinstone world events beyond the native
  fusers, Biggoron, the Wind Tribe and Vaati cutscenes outside dungeons,
  heart pieces that need native code; carrying a cucco.
- Tests: `tests/zelda_tmc_r26a_test.lua` (41: dispatchers, cape, boots,
  ocarina/fast travel/bird), `_r26a_items1_test.lua` (66, boomerang/bow),
  `_r26a_items2_test.lua` (49, swim/mitts/lantern), `_r26a_sword_test.lua`
  (52), `_r26a_enemies1_test.lua` (138), `_r26a_enemies2_test.lua` (107).
- **Final check:** all 51 `tests/zelda_tmc_*_test.lua` pass; static room
  audit 605 / 605 (`r26a/out_a_rooms.txt`).
- [x] **Cross-team wiring (after team B)** -- scenes in `r26a/wire/` run
  through team B's locked runner (`r26b/scene.sh`): `wire_fow.lua` 4/4 (a
  real arrow flying north opens each $58:03 eye switch via
  `FoWObjects.arrowHit` with the decomp's 4 x 6 arrow box; real arrows
  knock a Mazaal hand down via `BossMazaal.hit`; a bomb blast reaches the
  parts, hurt $16), `wire_gyorg.lua` (a real charged spin among the female's
  three open eyes takes a point; the Roc's Cape lands Link on the male,
  action 6), `wire_tod.lua` 7/7 (the real Lantern lights the $60:2B torch ->
  local $61 and widens the light circle, melts a $60:03 ice block, lights
  Big Octo's frozen tail fuse -> BURNING), `wire_clones.lua` 7/7 (new
  `FourSword.lua`: the split charge to 800, three clones on $58:00's clone
  tiles, alive after the release, seen by `Dungeon.somethingOn` /
  `FoWObjects.cloneOn`, R cancels).  Fixes found: arrows / the boomerang now
  stop on GustJar.wall (type-1 collision: pits pass; they used to stop on
  pit tiles); the Lantern's burn consumes its frame (Player read its state
  before the hook, so the walk replaced ANIM_LANTERN_BURN); the spin marks
  `e.spinAttack` for BossVaati2.  Note: team B's EnemyPoW claims Crow and
  Lakitu everywhere (R26 runs before EnemyField), so EnemyField1/2's ports
  of those two are not used.  Item scene re-run 10/10.  All 53 tests pass;
  audit 605 / 605.

## Round 26 (team B)

Dungeons, dungeon enemies and bosses.  Scratch under
`G:/Gen2Recomped/scratch_claude/zelda/tmc/r26b/` (`scene.sh` = the real-runtime
scene runner behind a mkdir lock so only one LOVE process runs at a time;
`lib_r26.lua` scene helpers; `survey.lua` = every dungeon room entered and
every entity that fell to a fallback listed (`out_sv2.txt`); per-group scenes
in `fow/ fowobj/ mazaal/ tod/ todobj/ gyorg/ pow/ dhc/ vaati12/ vaati3/ cof/`;
`check26.sh` = harness cache rebuild + room audit).  The user's rule this
round: no route or bot playtesting -- only unit tests, the audit and short
in-place scenes (Link put straight into the room).
**Cache version: 19** (ExtractR26.lua: manifest.r26b, the modules' ROM_RANGES).

- [x] **R26B.0 Wiring.**  `R26.lua` = one dispatcher, one anchored line per
  hook: Enemies:spawn (first; boss parts $60+), Enemies:update (before the
  generic model), Dungeon:spawnObject / spawnProjectile / spawnManager,
  Field:spawnRoomEntities (roomInit after the lists and room code).
  `ExtractR26.lua` collects every module's `M.ROM_RANGES` (raw bytes,
  readers u8..u32; nil on an old cache -> each module falls back).
- [x] **R26B.1 Cave of Flames, the rest** (scenes `cof/cof_rest.lua` 6/6,
  `cof/gl_exit.lua` 6/6): every room $50:00-$50:17 and $51:00 loads with all
  its entities; the chest spawners show their chests on their flags; the
  Cane of Pacci big chest ($50:01 flag $19 -> item $12), the map ($50:09),
  the big key ($50:17), both small keys ($50:01 / $50:08) and the lower
  floor's chests open and fill the dungeon inventory; key doors and the boss
  door are placed; Gleerok (round 25) is beaten, the Fire Element is given
  on touch, the warp shows and takes Link to $06:02.  Not ported: the
  STEAM_OVERLAY_MANAGER $14 (a blended BG3 haze, cosmetic); no heart
  container entity was seen in $51:00 after the fight (to check).
- [x] **R26B.2 Fortress of Winds** (`EnemyFoW.lua`, `FoWObjects.lua`,
  `BossMazaal.lua` + `2` + `3`): Wizzrobe wind/fire/ice + shots, Eyegore,
  Armos (statue / wake / chase, Minish entry), Stalfos (types 0/1, bones,
  pot/skull heads, the Cane), Flying Skull, Spark; EYE_SWITCH (arrows only,
  as the decomp), FLOATING_PLATFORM (rails, carries Link), MINISH_SIZED_
  ENTRANCE, STONE_TABLET, BIRD (+ Zeffa's Ocarina drop on the top),
  MISC_MANAGER 1/2/3 (falling keys), ENEMY_INTERACTION_MANAGER, WINDER,
  SPIKED_ROLLERS, the clone button hook; Mazaal whole (boss object intro,
  head 14 actions, bracelets 51 actions, hands, beams, the inside-the-head
  pillars, the Vaati projectile carry-out, defeat, flag $31, heart
  container, archway).  Scenes 9/9, 12/12, 24/24, 15/15, 18/18, 6/6.
- [x] **R26B.3 Temple of Droplets** (`EnemyToD.lua`, `ToDObjects.lua`,
  `BossOctorok.lua`): Big Octorok (octorokBoss.c: aim / walk / charge,
  rock / vacuum / smoke / freeze attacks, phases, frozen tail, lantern fuse,
  death, heart container + element), Pesto (+ dirt balls, grabbing),
  Scissors Beetle + mandibles (areas $60-$62 only: team A owns the outdoor
  one), Flying Pot, the Big Blue ChuChu (chuchuBoss type 4 through
  BossChuchu.lua); small / big ice blocks (slide, melt, keys inside),
  frozen flower, the frozen Water Element + light rays, LIGHT_DOOR,
  LIT_AREA, dark rooms (ChangeLightLevel, Link's light circle, lantern
  radius), pushable levers (big ones need a clone), the ToD / light level /
  waterfall / misc managers, the ice floor (sub_08008942 velocities).
  Scenes 14/14, 5/5, 21/21.
- [x] **R26B.4 Palace of Winds** (`EnemyPoW.lua`, `PoWObjects.lua`,
  `BossGyorg.lua`): Bombarossa, Crow, Lakitu + cloud + lightning, Ball and
  Chain Soldier, Gibdo (burns into a Stalfos), yellow ChuChu; fans, ambient
  clouds / cloud floor (land, held up, step off and fall), palace archway,
  floating blocks, floating platform manager, cloud staircase transitions,
  Roc's Cape room code.  The Gyorg Pair whole (boss object phases, the
  female's body = BG2 screen map from the ROM, eyes, mouth, tail, males,
  riding, children, energy shots, the end -> $70:00 with LV5_CLEAR and the
  Wind Element).  Scenes 23/23, 34/34.
- [x] **R26B.5 Dark Hyrule Castle** (`EnemyDHC.lua`, `DHCObjects.lua`,
  `BossVaati.lua`, `BossVaati2.lua`, `BossVaati3.lua` + `Arm` + `Extra`):
  Darknut (20 actions, shield handler 13, slashes), Wisp, Door Mimic,
  ENEMY_50 (the splitting ghost); Spear / Bow Moblin and Keaton are team A's
  ports (EnemyField1/2) and run there; guruguru bars, jail bars, metal door,
  the throne (OBJECT_BLOCKING_STAIRS), angry statues + cannonballs, tile
  puzzle, DHC / outside / Sanctuary room code.  Vaati Reborn (balls, eye,
  dark magic pulled off with the Gust Jar, three phases), Vaati
  Transfigured (eyes, parts, V2 projectiles, the eyes macro inside the arm),
  Vaati's Wrath (14 actions, arms with the Minish entry, eyes, tennis-ball
  reflect, knock-downs, death, ENDING flag) and ENEMY_4D on the bridge.
  Scenes 13/13, 9/10 (+ th.lua 1/1, the throne, see below), 16/16, 13/13,
  4/4, 25/25, 4/4.
- [ ] **Not done / known gaps (team B):**
  - Bow / bomb contacts on boss parts: Mazaal's hands and the eye switches
    need arrows (team A's ItemBow must call `BossMazaal.hit` /
    `FoWObjects.arrowHit`); Mazaal cannot be won in play until then.
  - The Gyorg three-eye combo is a spin attack (works if team A's sword
    skills reach `Enemies:swordHits`); boarding a male needs Roc's Cape.
  - The throne push: Link's collision lets him into the half-solid
    SPECIAL_TILE_44, so his push lands on the wrong tile (works from the
    cartridge's probe spot).
  - The Vaati intro scripts (CUTSCENE_ORCHESTRATOR $69: script_Vaati1Intro,
    script_CutsceneOrchestratorV2Intro) do not run; scenes start the fights
    with room flag 0.  The ending: the garden outro needs natives
    sub_080960C4 / sub_0807F98C / sub_0807F714, then the sync-flag cutscene
    and the credits.
  - Lantern fire contacts ($87), PL_FROZEN, burning Link, Gust Jar grabs of
    most new enemies, FX_STARS, BG3 light shafts / steam / Vaati backdrops
    (cosmetic); the Wisp's jinx is recorded but Player does not apply it.
  - Royal Crypt ($68): its entities are covered (Gibdo, Door Mimic, Flying
    Pot, floating blocks, light managers) but not scene-checked room by room.
- Tests: `tests/zelda_tmc_r26b_test.lua` (dispatcher + ExtractR26, 41) and
  `zelda_tmc_r26b_{fow 87, fowobj 85, mazaal 32, tod 34, todobj 91, gyorg
  54, pow 80, dhc 62, vaati12 67, vaati3 71}_test.lua`.
- **Final check (round 26 team B):** all 53 `tests/zelda_tmc_*_test.lua`
  pass (`r26b/out_tests.txt`, team A's included); static room audit 605 /
  605 (`r26b/out_a_rooms.txt`); harness cache rebuilt at 19
  (`r26b/extract_out.txt`, manifest.r26b present).

## Round 27 (team A)

Overworld story, side systems, leftover enemies.  No route/bot playtest (user
rule): unit tests, the room audit and in-place scenes only.  Scratch:
`G:/Gen2Recomped/scratch_claude/zelda/tmc/r27a/` (`scene.sh` lock runner,
`BRIEF.txt` porting brief, `align27.py` + `cover27.py` + `cover.sh` = the
script-coverage scan, `check27.sh` = cache rebuild + audit, per-group scenes in
`T1/ T2/ SQ/`).  **Cache version: 20** (ExtractR27A.lua: manifest.r27a, the
R27A modules' ROM_RANGES).  The round was cut short by usage limits: 3 of 8
porting groups ran.

- [x] **Wiring.** `R27A.lua` dispatcher (team A's twin of R26.lua):
  spawnEnemy/handles/update, spawnObject/Manager/Projectile, roomInit,
  giveItem, frame, draw, natives; one anchored line each in Enemies.lua,
  Dungeon.lua, Field.lua (roomInit, giveItem, update, draw), Native.lua,
  Extract.lua.  `ExtractR27A.lua`.
- [x] **Crow / Lakitu.** EnemyPoW claims them only in areas $70/$71
  (`M.lastArea` set in its spawnEnemy); elsewhere EnemyField1/2 run them.
- [x] **Script coverage scan.** ROM/decomp Call alignment over the script
  region ($08008B5C.., USA `.ifdef` resolved): 470 call targets, 576 scripts.
  Before: 317/576 scripts fully covered, 132/470 targets.  After: **450/576
  scripts, 327/470 targets** (`r27a/missing_final.txt` lists the rest).
- [x] **Story27Town.lua** (T1, 78 natives: townsperson, guards, Pina,
  carpenter, Sturgeon, house doors, sitting person, librarians, Zelda (not
  outro), Emma, Mama, Dr. Left, Beedle, key-stealing Takkuri, teachers, kid
  follow, Pita, Marcy, Tingle, phonograph, King/Potho/dog/mayor/Brocco/stamp).
  Scenes T1/out_s1..s3 (9/9, 6/6, 8/8); test `_r27a_town_test` (112).
- [x] **Story27Town2.lua + Town2Fairy.lua** (T2, 63 natives: blade brothers +
  LearnSkill/demonstrations, farmers, Gorman, Stockwell, Simon, picolyte chest
  game, Dampe, ghost brothers, Great Fairy object + natives, Percy, Librari).
  Scenes T2/out_s1..s3 (9/9, 9/9, 12/12); test `_r27a_town2_test` (118).
- [x] **SideQuests27.lua + SQ27Cucco.lua** (SQ, 33 natives: Rem + shoes, the
  Postman, Anju's cucco minigame + carrying/throwing cuccos, Mutoh, Smith,
  Talon, Malon, bell heart piece manager, bottle drinks/charms, script cmd
  $1F).  Scenes SQ/out_* (rem 8/8, cucco2 12/12, postman 5/5, bell 5/5,
  bottle 2/2); test `_r27a_sidequests_test` (81).
- SFX: every ported SoundReq goes through f:sound (lists in the module
  headers).
- [ ] **Not done (not started this round):** Minish villages / Wind Tribe /
  Gregal / Biggoron Mirror Shield / Gorons / Wind Ruins tablets / Elemental
  Sanctuary infusion / Ezlo after WARP_1ST (group MN); generic cutscene
  natives script.c / cutscene.c / cutsceneMiscObject / roomInit /
  Vaati_Apparate (CS); Kinstone world-event types 2/4/5/6/7-0x80/11, the
  SUBTASK_WORLDEVENT cutscenes, fuser audit (KS); figurines / Carlov /
  gallery (FG); Bomb Peahat, Moldworm, Like Like, Dust, last Beetle form (EN).
  Module names are already listed in R27A.MODULES and briefs exist in
  r27a/BRIEF.txt; per-group native lists r27a/miss_<GROUP>.txt.  Also
  SIMPLIFIED items in each module header (wanderer homes, chest-game NPC
  drawing, thrown cucco over the fence, picolyte/charm effects).
- Tests: `tests/zelda_tmc_r27a_test.lua` (12) + the three group tests.
- **Final check:** all 57 `tests/zelda_tmc_*_test.lua` pass
  (`r27a/out_tests.txt`); audit 605/605 after the cache-20 rebuild
  (`r27a/out_a_rooms.txt`).

## Round 27 (team B)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r27b/` (`scene.sh` lock runner,
`BRIEF27.txt`, `sv/survey27.lua`, `vaati/` scenes, `check26.sh`).  No route or bot
playtesting: unit tests, the audit, short in-place scenes.
**Cache version: 21** (manifest.r26b now also holds the R27B modules' ranges).

- [x] **Wiring.** `R27B.lua` = sub-dispatcher listed in R26.MODULES (VaatiScripts,
  SanctuaryScripts, Ending, DungeonFix27, CoFRest27, CaveObjects, CaveManagers; missing
  ones skipped), merges ROM_RANGES, adds hooks `frame` (Field:update), `draw`
  (Field:draw) and `playerFrame` (top of Player:update); Native.call loads R26.mods()
  so the modules' natives exist.  Test `zelda_tmc_r27b_test.lua`.
- [x] **Survey / cross-check** (`r27b/sv/out_sv_dun.txt`, `out_sv_ow.txt`): all 605
  rooms entered, 40 frames each, **605 of 605 without a Lua error** (528 non-overworld
  + 77 overworld).  Non-overworld: 0 enemy fallbacks; 192 object id.type entries
  return false from Dungeon:spawnObject (most are then handled by Field: ground items,
  pots, ObjStatic fixed frames); 31 manager id.type unhandled (03/06/16 are handled by
  Field afterwards); 16 script natives missing (one, $0807F8E8, fixed below).
  Overworld (team A): 6 enemy generic, 13 spawn-nil ($65), 58 object, 27 manager,
  13 natives.
- [x] **Vaati intro scripts** (`VaatiScripts.lua`, `SanctuaryScripts.lua`, test
  `zelda_tmc_r27b_vaati_test.lua` 93 checks): vaati.c NPC $27 (Apparate, afterimages),
  vaatiReborn.c NPC $3B (V2 intro), VAATI1_PORTAL $AB, Zelda's stone + VaatiWithZelda,
  the spiral beam that frees the stones, NPC4E transitions 2/4/5, DHC natives (dark nut
  timer, ring tiles, falling rocks, priority sort sub_0807F714/738...), the Sanctuary
  (stone tablet sub_0807F8E8, CutsceneMiscObject $16/$17/$1C-$1F, $3E types, Ezlo
  hint).  Scenes `r27b/vaati/` v1 12/12, v2 14/14, zstone 11/11, rescue 9/9, sanct
  16/16, sanct3 6/6, garden 5/5: each fight starts from its own script (no scene sets
  room flag 0); 0 missing natives / unknown commands.  DHCObjects element item ids
  fixed ($40-$43).  SIMPLIFIED: Vaati apparate BG3 wave, dark nut timer HUD, spiral beam
  vs enemies, stained-glass blends.
- [ ] **Not done (left for a later round):** the ending (garden outro natives
  sub_080960C4 etc., the synced cutscene, Npc4E outro transitions, credits /
  staffroll.c); the dungeon leftovers (Gleerok heart container in $51:00, throne push
  collision, PL_FROZEN, BG3 light shafts, steam overlay $14, Gleerok lava tiles, Gyorg
  male eye spin hit, Rupee Like drop, red ChuChu move types); porting the cave / crypt
  object and manager fallbacks of the survey; room-by-room scenes of the Royal Crypt
  beyond the survey.  The module names are reserved in R27B.MODULES.
- **Final check:** all 59 `tests/zelda_tmc_*_test.lua` pass; audit 605/605
  (`r27b/out_a_rooms.txt`); harness cache rebuilt at 21.

## Round 28

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r28/` (scenes run through
`r27b/scene.sh`; `check28.sh` = cache rebuild + audit).  No route or bot
playtesting: unit tests, the audit, short in-place scenes.
**Cache version: 22** (manifest.r26b gains the Ending ranges staffEN /
staffGfx / outroSparks).

- [x] **The ending** (`Ending.lua`, in R27B.MODULES): the outro scripts
  (data/scripts/cutscene/outro/*.inc) run from the ROM; ported their C side:
  sub_080960C4 (CUTSCENE_MISC_OBJECT $23/$24, Type35), sub_08094B0C /
  sub_08094B3C (the cap's height), sub_080961B0 + Type37 (eight sparkles),
  sub_08066E68 (Zelda anim $54), sub_0807FADC -> WHITE_TRIANGLE_EFFECT
  (whiteTriangleEffect.c: the turning triangle window + brightness, the
  command waits for it), sub_08094B94 / sub_08094BE0 + Type1 (the little hat,
  script $0800AEDC), sub_0806305C, sub_0808D2CC / sub_0808D280 (the portal),
  CreateDeathFx ($080A29BC), Type5 type2 2 (the DHC rubble).
  sub_0807F98C / sub_0807F714 were already in VaatiScripts.  sub_0807F844
  now also snaps the camera (sub_080809D4).  NPC4E_DoScreenTransition
  7..15 (gNpc4ETransitions, white / black fades): garden -> DHC throne ->
  castle throne -> DHC entrance -> castle entrance -> castle hall (staff
  unfrozen) -> Minish Woods -> Mt Crenel -> garden -> Sanctuary entrance.
  Room lists with ENDING ($80:00, $80:01, $00:00, $81:00, $06:00; the others
  were already done).  Scenes `r28/garden.lua` 7/7, `staff.lua` 4/4,
  `sanct.lua` 8/8; 0 missing natives, 0 unknown commands along the chain.
- [x] **The credits** (`Staffroll.lua`, staffroll.c on Ppu.lua): State0
  (saw_staffroll, GAMECLEAR, the English list gUnk_08127644 read from the
  ROM), menuTypes 0-7 (pictures gUnk_08127CEC = palette/gfx groups, text by
  ShowTextBox with gStaffrollFonts, the BG1 alpha ramp, the cartridge's
  palette fades incl. the $FFFF7FFF mask), BGM_CREDITS, then the Save / Don't
  Save popup (GameOver's popup) -> the host's save -> fade -> the title.
  Scene `r28/sanct.lua`: picture + "DIRECTOR" text, the last stained-glass
  page, the popup, Don't Save -> title.  SIMPLIFIED: CreateDialogBox 8/9 not
  drawn; the triangle is drawn over the HUD; Ezlo's affine shrink not drawn.
- [x] **Gleerok heart container ($51:00)**: works -- the round-26 note came
  from a check made before list `a` loads (FIGHT_MANAGER -> LV2_CLEAR, list 9
  element, its text closing sets room flag 0, list a: warp + heart shown on
  LV2_CLEAR).  Scene `r28/heart.lua` 3/3 (max health +8).
- [x] **Throne push ($88:1F)** (`DungeonFix27.lua`): Link's box (x-4..x+3)
  let him 1-2 px further into SPECIAL_TILE_44 than the cartridge's sensor
  (gPlayerHitbox: x+5), so the push probe hit the middle tile; the wrapped
  DHCObjects.tryStairsPush stops him at the cartridge's spot first.  Scene
  `r28/throne.lua` 2/2 (walking right with real input slides the throne).
- **Final check:** all 60 `tests/zelda_tmc_*_test.lua` pass (new
  `zelda_tmc_r28_test.lua`, 98 checks); audit 605/605 (`r28/out_a_rooms.txt`);
  r27b scenes v1 12/12, v2 14/14 re-run after the camera change.
- [ ] Left: PL_FROZEN, steam / light-shaft BG3, Gleerok lava tiles, Gyorg eye
  spin, Rupee Like drop, red ChuChu, cave / crypt fallbacks (CoFRest27,
  CaveObjects, CaveManagers still unwritten); the throne pushed from the
  right side was not re-checked in a scene (unchanged code path).
