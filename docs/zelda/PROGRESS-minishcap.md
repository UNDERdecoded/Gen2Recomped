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

## Round 29

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r29/` (scenes run through
`r27b/scene.sh` from checkpoint `a_end`; `audit29.sh` = audit only).  Bugs
the user hit while playing.  **Cache version: 22** (unchanged).

- [x] **Walking through walls and furniture in Link's house ($22:$15) and
  every house** (`Room.lua`): LoadRoomGfx ends with `sub_0807C5B0` for the
  house-type areas (HOUSE_INTERIORS_1-4, TREE_INTERIORS, DOJOS,
  MINISH_CRACKS, WIND_TRIBE_TOWER, EZLO_CUTSCENE = $21-$25, $27, $28, $30,
  $38): the top map's collision is merged into the bottom one (top < $10 ORs
  into bottom < $10, top >= $10 replaces it).  It was never ported, so Link
  (layer 1) only saw the bottom map, where the floor runs on under the beds,
  tables, stools, boxes and walls drawn on BG1.  Not a round 23-28
  regression.  `Room.MERGE_TOP_AREAS`; scene `r29/house.lua` (walking into
  each side and the furniture now stops at the beds / table / stools /
  boxes; before: Link walked into the bed), `r29/house2.lua` ($22:$06: pot
  gap 10 px, NPC gap 14 px, the four walls).
- [x] **Every pot looked wrong** (`Field.lua`, `Objects.lua`, new
  `PotCarry.lua`): pot.c Pot_Init does `y += 3` and
  `InitializeAnimation(super, 5)` (sprite 167 frame 5: two mirrored 8x16
  halves at VRAM 240); the port drew animation 0 (a 16x16 piece: a scroll
  over a box) on the ground, over Link's head and in the air, and used the
  room-less palette for the carried one.
- [x] **Lifting**: itemTryPickupObject.c sub_08076088 / sub_08076488:
  ANIM_PICKUP plays out (Link stands still, no throw) before carrying; the
  port cut to the carry walk at once and drew the pot over his head at once.
  The carried object follows sub_08078D60 (gUnk_0811C0E8[carryFlags >> 4]
  at Link's keyframe flags & $7F: x / z, x mirrored facing left), so it
  rises from the ground in front / below as in the cartridge.
- [x] **Throwing** (playerItemHeldObject.c): released on ANIM_THROW's
  keyframe with frame & 1, speed $400 (4 px), zVelocity 0, z = carried z + 8,
  gravity Q_8_8(32); walls stop it without breaking it (ProcessMovement10);
  landing on act tile 13 / 16 / 17 / 19 / 90 gives the fall / splash / lava
  FX and no shards, else BreakPot.  The port threw at 2.5 px from z 14 and
  broke the pot on the first wall.  Measured: a pot thrown east lands 48 px
  away (`r29/pot.lua`, Deepwood $48:03; the pot comes back on re-entry).
  Bombs and hook-carried entities (Rollobite, Bob-omb, skulls) keep their
  own paths.
- Walk-into check (scenes or code): house furniture / walls fixed (merge);
  pots (entity box on the whole tile, 10 px gap), NPCs (Hitboxes push-out,
  14 px gap) fine; chests / signs are tiles (in houses fixed by the merge);
  statues (Dungeon tile blockers), ice blocks (ToDObjects SPECIAL tile
  writes), throne (round 28) unchanged, not re-run.
- **Final check:** all 61 `tests/zelda_tmc_*_test.lua` pass (new
  `zelda_tmc_r29_test.lua`, 44 checks); audit 605/605 (`r29/out_a_rooms.txt`).
- [ ] Left: thrown pot shadow; the cartridge's pot is a solid tile
  (SPECIAL_TILE_0) while the port blocks with the entity box; PL_FROZEN,
  steam / light-shaft BG3, Gleerok lava tiles, Gyorg eye spin, Rupee Like,
  red ChuChu, cave / crypt fallbacks.

## Round 30

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r30/` (scenes through
`r27b/scene.sh` from checkpoint `a_end`; `check30.sh` = cache rebuild +
audit; `sweep30.lua` = the collision sweep, MODE=census / walk / grid).
**Cache version: 23** (manifest.r26b gains `shadowFrames30`).

- [x] **Pots are their tile** (new `Pot30.lua`, hooks in Field.lua spawn /
  prune / update, Objects.lua tryAction / dropCarried / shatter,
  PotCarry.release): pot.c Pot_Init: unk_70 = the tile under it,
  SetTile(SPECIAL_TILE_0) (collision $1D from the special table: Link,
  enemies and thrown things meet the tile; Field:entityBlocks no longer
  boxes a pot that has its tile); a second pot on a SPECIAL_TILE_0 is
  deleted; type2 1 with its flag set is deleted.  The tile goes back when
  the pot is lifted / deleted (Field's prune), slides after a push
  (Pot_Action4 puts SPECIAL_TILE_0 on the new tile), is pulled by the Gust
  Jar or hopped by the Cane; a tile written under a resting pot breaks it
  (SPECIAL_TILE_5) or deletes it (SPECIAL_TILE_103), FX_FALL_DOWN first on
  ACT_TILE_13.  The room-data fields were never read: unk_7d = paramB byte
  1 (the item's param), type2 = paramB & $FF, flag = paramC >> 16.
- [x] **BreakPot** (Objects:shatter + Pot30.shatterFx): FX_POT_SHATTER is
  drawn for every pot break (the port only rolled the drop, no shards on
  screen); form != 0/$FF -> GROUND_ITEM(form, unk_7d); type2 1 sets the
  flag (stays broken); type2 2 gives the item kind 5 + the pot's flag
  (stays taken).  A lifted pot carries unk_7d / type2 / flag to the throw.
- [x] **Thrown pot shadow** (Pot30.drawShadows, hook at the top of
  Field:drawSpriteList): arm_DrawEntities / sub_080B255C queues a shadow
  for spritePriority.b1 = 3 objects (the thrown object, the Cane-hopped
  pot) while z < 0: frame spriteSettings.shadow of ram_0x80b2bd8 (USA ROM
  $080B2B3F, four 1-piece OAM frames read at import, tiles of OBJ VRAM,
  OBJ palette 5) at the ground y, under the sprites.  Shots
  `r30/shots/101958_p30_hop.png` (+ `hop_zoom.png`), `101903_p30_shadow6.png`.
- [x] **Big chests are tiles** (new `Collide30.lua`, one Field:update
  hook): chestSpawner.c sub_080842D8 -- SPECIAL_TILE_34..42 round the
  chest by x & 8 / y & 8 (gUnk_0811F854/866/880/88A, from the .c source);
  the port boxed it 10 x 7, Link walked 8 px into its sides / top (sweep
  `sw_walk1.txt`: 7 fails, now 0; `r30/chest.lua`, shot
  `r30/shots/102022_p30_bigchest.png`); opening still works.
- [x] **Rupee Like drop**: RupeeLike_OnDeath -> EnemyCreateDeathFX($FF,
  gUnk_080CCC34[unk_84 * 3 + type]) -> DeathFx CreateItemDrop(item); the
  port rolled the generic table.  `e.deathItem30` (EnemyCoF3) read by the
  death path in Enemies:update.
- **Collision sweep** (`sweep30.lua`): census of all 605 rooms (0 Lua
  errors; 470 pots all on SPECIAL_TILE_0; 358 chest + 29 sign tiles all
  solid; 19 big chests, 23 statues, 20 ice blocks, 124 solid NPCs, 3 carts,
  12 obj $9F); walk test (23 rooms: houses, Deepwood, CoF, ToD, PoW, DHC,
  town / fields) 303 walks into pots, statues, ice, carts, chests, signs,
  NPCs, obj $9F from 4 sides: 0 pass-throughs after the big chest fix (a
  0.3-2.8 px overlap is the tile shape vs the sweep's rectangle); grid test
  (Link's house $22:$15, town houses, Deepwood, ToD, the DHC throne room)
  368 walks, Link never inside a solid tile.  Pots: `r30/pot30.lua` 9/9
  (tile, 4-side walk-in, lift clears the tile, shadow, shatter FX, push
  moves the tile).
- SIMPLIFIED: the shadow is drawn opaque (no OBJ blend), only for thrown /
  hopped objects (no generic shadow for Link or enemies); Minish Link is
  stopped by a pot's tile but cannot push it (pushedObject $C0 not ported);
  the sweep skipped 153 starts that were inside walls.
- [ ] Left: PL_FROZEN, red ChuChu move types, Gyorg male eye spin, steam /
  light-shaft BG3, Gleerok lava tiles, cave / crypt fallbacks; Minish pot
  push; barrels / rolling objects not in the sweep.
- **Final check:** all 62 `tests/zelda_tmc_*_test.lua` pass (new
  `zelda_tmc_r30_test.lua`, 43 checks); audit 605/605 (`r30/out_a_rooms.txt`).

## Round 31

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r31/` (scenes through
`r27b/scene.sh` from checkpoint `a_end`; `census31.lua` = every object of every
room with its tile collision; `sweep31.lua` = walks into the tile-writing
objects (OFF=1 = before, MINI=1 / small = the Minish entrances);
`scene31.lua`, `status.lua`, `grave31.lua`; `audit31.sh` = audit only).
**Cache version: 23** (unchanged: no new extracted tables).

- [x] **Object tiles: the second half of the collision sweep** (new
  `Collide31.lua`, one line in Collide30.sync).  The census (`census31.txt`)
  found the objects whose Init writes solid tiles but that the port only
  drew: FURNITURE 223 (69 on a solid BG tile), PUSHABLE_FURNITURE 22,
  PUSHABLE_GRAVE 13, GIANT_TWIG 16, HUGE_ACORN 12, CABIN_FURNITURE 3,
  BAKER_OVEN, HUGE_SHOES, the mine cart (an entity box).  Ported:
  furniture.c FurnitureInit (sub_08090B6C width rows with the 36 / 37 half
  tiles and sub_08090CDC's merge, the height rows, flags $40 / $80 ladders
  incl. FurnitureUpdate $80, $2 shelves, WOODEN_TABLE / LOW_BOOKSHELF /
  STAIRCASE), CabinFurniture_Init, bakerOven sub_0809CDF0, macroAcorn
  sub_0809E5F0, giantTwig sub_08093A1C / sub_08093984, MacroShoe_Init,
  minecart.c's SPECIAL_TILE_34 (Init / Action6, gone while ridden).  Sweep
  (`sw31_off.txt` -> `sw31_on.txt`): furniture 77 pass-throughs of 361
  walks -> 1 of 278 (the ladder furniture of $20:09, which Link climbs, as
  on the cartridge); acorns 16/16 -> 0; cabin, oven, shoes, carts 0.  The 40
  twig "passes" are the cartridge's: twig types $40 / $41 have no tiles,
  type 2 is SPECIAL_TILE_116 (collision 0), type 0 leaves its middle
  column free (SPECIAL_TILE_61).  Grid test (`grid31.txt`, 13 house /
  Minish rooms, step 24): 1156 walks, Link never inside a solid tile.
- [x] **Royal Valley graves** (new `Grave31.lua`, from Collide31.sync;
  Link's push in `Push31.full` from PushAnim.update): pushableGrave.c
  Init (PushableGrave_Tiles 34 / 62 / 62, the big grave's two tiles and
  y + 2, type2 2's SPECIAL_TILE_61 ring, pushedFlag = paramC >> 16, already
  moved when the flag is set), Action1 (SPECIAL_TILE_63 or the flag ->
  slide 64 frames at $40 with the nine tiles back; the big grave on its
  flag: 60 + 120 frames, 96 frames north), sub_080977F4 (tile 34 at the new
  spot, the flag); UpdatePlayerCollision SPECIAL_TILE_62 (facing north,
  moving, frame bit 1 -> 63).  Scene `grave31.lua` 6/6 ($09:00: 12/12
  graves solid, a grave pushed 16 px, the big grave 24 px on its flag);
  shot `r27b/shots/125257_r31_grave.png`.
- [x] **Minish Link pushes pots** (new `Push31.lua`, one line in
  PushAnim.update): UpdatePlayerCollision SPECIAL_TILE_0 with sub_0801A4F8's
  Minish rule (ITEM_POWER_BRACELETS == 1, the stick held toward the pot,
  blocked on that side, no frame flag), pushedObject $C0 (64 frames at
  kPushSpeed / 2: Link follows the pot 16 px).  Scene `scene31.lua`
  ($48:03: no bracelets no push; with them the pot's SPECIAL_TILE_0 moves
  up one tile, Link 18 px); shot `r27b/shots/124933_r31_minish_push.png`.
- [x] **PL_FROZEN and PL_BURNING** (new `R31.lua`, in R27B.MODULES; one
  line in Enemies:update's touch, one in Player:draw): the matrix handlers
  12 (sub_08017C40) and 11 (CollisionFire) -- hitTypes $0B (freeze), $0A /
  $2D / $3E / $73 (fire).  Frozen: damage 4, ANIM_FROZEN, SFX_195,
  COLLISION_OFF, 120 frames minus 3 per press (directions / A / B / R, the
  shake), break_out: 160 iframes, FX_ICE.  Burning: LINK_FIRE type 1 over
  Link (offsets {0, -6, 0, 6}, 5 up facing down), kWalkSpeedBurning 3 px,
  running the facing way with the stick released, no items / lifting,
  out after $F0 frames or 31 presses.  Scene `status.lua` 14/14; shots
  `r27b/shots/124434_r31_frozen.png`, `124434_r31_burning.png`.
- [x] **Gyorg male eye spin**: SwordSkills.hitBox now hands the spin's
  hurtType ($08-$0A) to the boss parts (`f.swordHurt31`); BossGyorg.swordHit
  uses it for the matrix (male eye hitType $30: sword orgDmg 2, spin 6) and
  the female eyes' contact.
- [x] **Cave of Flames steam overlay** (new `Steam31.lua` through R31's
  spawnManager / frame and one line in Field:drawWorld):
  steamOverlayManager.c -- the BLDALPHA ramp gUnk_08108588 every 4 frames
  in rooms 0 / 8 / 9 / $17, fade out elsewhere, deleted in room 7 (and room
  1 with local $16 set), the $808 / $907 / $A06 / $907 shimmer every 32
  ticks, bg3Offset -= $1000 a frame, the per-scanline sine wave
  (sub_0805A114), the BG3 picture from VRAM $F000 (Bg3.build).  Scene:
  $50:00 blend $808-$A06, $50:02 fades to $1000; shot
  `r27b/shots/124933_r31_steam.png`.
- Checked, unchanged: barrels (Barrel.lua already writes bigBarrel's
  TILE_TYPE_118), lava platforms and pillar blocks (round 25's tiles /
  CoFObjects), Minish-size entrances (the cartridge's per-state collision
  tables: full-size Link never entered a solid tile in the grid test).
- SIMPLIFIED: shelves' SetActTileAtTilePos and the $400 furniture's flame
  not created; the big grave's camera pan not done; the steam blend is
  love's alpha; the frozen shake moves the sprite.
- **Final check:** all 63 `tests/zelda_tmc_*_test.lua` pass (new
  `zelda_tmc_r31_test.lua`, 44 checks); audit 605/605
  (`r31/out_a_rooms.txt`); r30 pot scene 9/9 and r30 walk sweep (36 walks,
  0 fails) re-run.
- [ ] Left: PUSHABLE_FURNITURE (pushableFurniture.c + its manager: still
  drawn only, no tiles, not pushable -- the house wardrobes over Minish
  cracks), DOUBLE_BOOKSHELF's child shelf, red ChuChu ProcessMovement2 / 5
  (the per-collisionType tile tables of CalculateEntityTileCollisions),
  light rays (LIGHT_RAY_MANAGER $01), Gleerok's lava-tile restore
  (GLEEROK_PARTICLE type 1 $80), cave / crypt fallbacks, figurines,
  kinstone fusion cutscenes.

## Round 32

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r32/` (scenes through
`r27b/scene.sh` from checkpoint `a_end`: `furn32.lua` 18/18, `fig32.lua`
11/11, `fuse32.lua` 2/2, `grave32.lua` 7/7; `dump32.lua` = every
PUSHABLE_FURNITURE / manager $26 / DOUBLE_BOOKSHELF / FIGURINE_DEVICE in the
room data; `extract32.sh` = harness cache rebuild, `audit32.sh` = audit).
**Cache version: 24** (new `ExtractR32.lua`: `figurines.bin` +
`manifest.r32`; scenes on an older cache read the ROM through
`R26_DEV_ROM`, as `ExtractR26.tables` does).

- [x] **Pushable furniture** (new `Furniture32.lua`, in R27B.MODULES; one
  line each for full-size and Minish Link in PushAnim.update):
  pushableFurniture.c + pushableFurnitureManager.c.  The manager ($26, 15
  house rooms: $22:01-$14, $23:01, $28:00-$05) was never ported, so those
  wardrobes were missing; its property list (8-byte {flag, type, type2,
  timer, x, y}) is read from the entity region.  Init tiles (sub_0808FF50:
  SPECIAL_TILE_43 + 44 / 45 halves by x & 8, merged with a neighbour
  (sub_08090094), the wall row two up (sub_0809028C, 38 / 101 / 102);
  one-tile pieces SPECIAL_TILE_74), sub_0808FDE8 (44 / 45 <-> 46 / 47 by
  the neighbour), UpdatePlayerCollision cases 43..45 (sub_0801A370) and 74
  (sub_0801A458) with sub_0801A4F8 (full size: the push ANIM frame; Minish:
  the Power Bracelets), PlayerPush walking Link pushedObject & $7F frames
  at kPushSpeed ($80 / Minish $40), Action2 (LinearMoveUpdate 16 / 32
  frames for two-tile pieces, 32 / 64 for boxes, SFX_10F), the target
  ((s8)timer + x, type 1 type2 1: + y; $80 = already there) with its flag
  (CheckFlags(paramC >> 16), the manager's local flag or its bit) -> done
  (34 / 36 / 37, no more pushing) and SFX_BUTTON_PRESS, re-entry at the
  target; the manager's priority swap (sub_0805C7CC / sub_08090514);
  types 2 / 4 bonked by the boots (frame 1, OBJECT_63: a random drop or a
  heart).  Scenes: $22:03 wardrobe pushed 8 px onto its target reveals the
  ladder, stays there on re-entry; $22:04 left push; $25:0A box 16 px; Minish
  Link in $23:01 (no bracelets: nothing; with them two 8 px pushes).
  Shots `r32/shots/140642_r32_pushed_2203.png`, `140642_r32_minish_2301.png`.
- [x] **DOUBLE_BOOKSHELF** (Furniture32): the type 0 shelf makes its type 1
  child at (+16, +16) (flag set: (0, +16)), the parent's tiles (34 x3, 38
  x3 two rows up), the child's 130 / 34 / 95 rows, sub_0809B274's tiles as
  Link walks behind it (RestorePrevTileEntity back).  The child never
  slides: DoubleBookshelf_Action1 only reads a tile type (checked on the
  ROM at $0809B034), SPECIAL_TILE_95 -> 116 has no taker.
  `140642_r32_bookshelf_2207.png`.
- [x] **Furniture flame**: furniture.c $400 -> sub_08090E64 (FLAME type 0
  at x + type2 - 2, z 16, layer 2, SFX_124; type2 != 0: spriteOffsetX 1).
  $2E:00 three candles (`140642_r32_flames_2E00.png`).
- [x] **Carlov's figurines** (new `Figurines.lua`, the R27A module name
  R27A.MODULES already listed): FIGURINE_DEVICE types 0-3 (viewer,
  machine, capsule, shell counter), sub_080880D8 / sub_08088160 (the
  available figurines by stage sub_0808804C, bank flags, fused Kinstones,
  the special cases), sub_0808826C, FigurineDevice_ChangeShellAmount (R =
  10), FigurineDevice_Draw (Random & $7F < 100 against the chance floored
  15 / 12 / 9 / 6, the next available one not owned / owned), the counter
  box (ShowTextBox CARLOV $18 with the cartridge's Font, `$06 01` / `$06
  02` = shells / chance), script_Carlov2's natives ($0808861C lever,
  $08088658 door, $08088478 / $08088504 / $08088544 / $08088574 / $080885B0
  messages, the Carlov Medal at 136), and the figurine menu (subtask 7)
  on Ppu.lua: pause base gfx, palette 206 / gfx 89, the figurine picture
  (sprite $1F8 frame n - 1, gFigurines palette into OBJ banks 6-14, gfx at
  OBJ tile $200), sprite $1FC frame / scroll bar / arrows, the number
  digits, five name rows (text $800 + n, "- - -" $889 not owned), the
  description (text $900 + n, BG1 in WIN0 y 120..152, Left / Right
  scroll), the reveal (brightness ramp over $80 frames, the bit written at
  $40, SFX_ITEM_GET / SFX_MENU_ERROR for a duplicate) and browse (Up /
  Down, L / R 5, B / START).  The lever itself is PULLABLE_LEVER (room
  flag 0); the scene sets that flag.  Shots `135906_r32_fig_counter.png`,
  `135941_r32_fig_reveal.png`, `135941_r32_fig_browse2.png`.
- [x] **Fusion world events** (new `Fusion32.lua`, in R27B.MODULES; one line
  in KinstoneMenu's KM:exit): KinstoneMenu_Type2 -> SUBTASK_WORLDEVENT for
  the 91 Kinstones whose event is subtask 8: the event's room (its maps,
  backdrop) at origin + (offsetX, offsetY), fade in, type 0 message
  TEXT_EMPTY $01, other types a white flash + the event's entity (frame 0)
  + SFX_SECRET_BIG for the tile types, 180 / 120 frames, fade back; then
  the fuser's "fusing" message as before.  (The fusion window itself was
  already ported in KinstoneMenu.lua.)  `140312_r32_fuse_type1.png`.
- [x] **Big grave camera pan** (Grave31): camera_target = the grave after
  60 frames (scrollSpeed 2), back on Link when it settles.
- SIMPLIFIED: Link walking with the furniture stands in for sub_0800445C;
  shelves' SetActTileAtTilePos still not written; the menu capsule
  (OBJECT_A2: fall, bounces, FX_BIG_EXPLOSION2) is a 60-frame wait,
  MenuFadeIn an 8-frame fade, no KeyButtonLayout hints; the world-event
  view draws the room's maps only (no entities running, no per-type
  animation such as a growing beanstalk) and skips the map hints
  (SUBTASK_MAPHINT / LOCALMAPHINT).
- **Final check:** all 64 `tests/zelda_tmc_*_test.lua` pass (new
  `zelda_tmc_r32_test.lua`, 67 checks); audit 605/605
  (`r32/out_a_rooms.txt`).
- [ ] Left: red ChuChu ProcessMovement2 / 5, light rays (LIGHT_RAY_MANAGER),
  Gleerok's lava-tile restore, cave / crypt fallbacks, the shelves' act
  tiles, the world events' per-type animations and map hints, the figurine
  menu's capsule object.

## Round 33

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r33/` (scenes through
`r27b/scene.sh` from checkpoint `a_end`: `fig33.lua` 13/13, `fuse33.lua` 5/5,
`lray33.lua` 7/7, `lray33b.lua` 2/2; probes `figprobe.lua` (the menu's layers
one by one, `shots/layer_bg*.png`), `weprobe.lua`, `hint33.lua`,
`lray_probe.lua`; `extract33.sh` = harness cache rebuild, `audit33.sh`).
**Cache version: 25** (new `ExtractR33.lua`: `r33.bin` + `manifest.r33` =
gWorldEvents raw, worldEvent5's tables, gUnk_085B4180 and the two light-ray
rooms' zone lists; served through `Ppu:table`'s fallback, dev scenes on an
older cache through `R26_DEV_ROM`).

- [x] **Figurine menu background** (Figurines.lua): the probe showed BG2's
  tiles 0-$3F (VRAM $0000-$07FF) were zero.  sub_080A4DB8 sets
  `gScreen.bg0.updated` but never its control, which keeps the field's
  $1F0C (common.c / ui.c); the port's menu Ppu had control 0, so the BG0
  buffer's copy landed on screen base 0 = BG2's stone texture (the grey /
  white blocks).  Fixed shot `r33/shots/161410_r33_fig_reveal.png`.
- [x] **The capsule in the menu** (OBJECT_A2, objectA2.c): animation 0 at
  (40, 72) z -80, flipX on Random & $10, palette gUnk_08124704[type];
  BounceUpdate(32.0) (z -= zVelocity, zVelocity -= $20), the USA landing
  (language < 2) ends it: animation 1 + SFX_186; animation 2, frame byte 9
  -> FX_BIG_EXPLOSION2 and gMenu.field_0x0 (the brightness ramp starts),
  $80 -> gone.  Drawn as OAM from the tiles gfx group 89 put at OBJ $200.
  `161410_r33_fig_capsule_land.png`, `_open.png`.
- [x] **The B "Return" hint**: gUnk_0812813C (KeyButtonLayout from the .c
  source) through Ui.lua at FigurineMenu1_Type0 / the end of the reveal.
- [x] **Kinstone chests and blockers in the field** (new `Fusion33.lua`, one
  line in Kinstone:applyWorldEvents): sub_0801876C's tile parts that were
  missing -- type 2 (25 Kinstones: sub_08018BB4, the small chest of
  gUnk_080FEAC8[id] at the event's tile, TILE_TYPE_115 unless its flag is
  set, added to a copy of the room's chest list; the round 32 test fusion's
  chest appears in $05:04 and opens), type 4 / 6 / 7 ($80) not fused (the
  TILE_TYPE_562 / 488+500 / 479+483+475 blocks the fusion clears), type 5
  fused (512 / 537 5 x 5).
- [x] **World-event view per type** (Fusion32.lua rewritten): the room as
  sub_0801876C(id, 0) leaves it, then the type's pattern from
  src/worldEvent/*.c: types 4 / 6 / 7 / 8 / 9 fade out to white, reload the
  room (the change), FX_BIG_EXPLOSION2 at the event, SFX_SECRET_BIG, back
  from white; type 1 a white flash + the entity; 2 the chest tile + FX; 3 /
  11 / 24 the entity + FX; 25 the entity; 10 WorldEvent_Beanstalk: its flag
  and BEANSTALK type 0 -- beanstalk.c ported for the growth (sprout x3,
  animation 1 with SFX_198 every 17 frames, stalk + climbing top, leaves
  from gUnk_08120DFC on frame bit 0, a section every cycle, $38 up; types
  1-6 drawn from gfx group $11's tiles at OBJ $1C0); 390 frames.  Shots
  `162414_r33_we_beanstalk_sprout/_grow/_tall.png`, `_chest_after.png`,
  `_type7_before/_after.png`.
- [x] **Local map hint** (subtaskLocalMapHint.c): every subtask-8 Kinstone
  has a marker, so every world event ends with it: the region of the
  event's world position (_c / _e, GetOverworldLocation's windcrestId) as
  pause screen 6 draws it (MapMenu, new exports regionPos / showAreaName /
  region6), BG3 $5001, colours 0 / $5F $475F, Link's and the event's
  markers, scroll y - $3C (max unk2), 30 frames (SFX_103 at 1), then the
  blinking markers and A / B / START.  `_chest_hint2.png`,
  `_beanstalk_hint2.png`.  The pause map's fused-Kinstone markers now find
  their table too (MapMenu read `worldEvents`, which no cache had).
- [x] **Light rays** (new `R33.lua` in R27B.MODULES, one line in
  Field:drawWorld): LIGHT_RAY_MANAGER $01 ($00:00 property 17, $20:09
  property 8): the zone list {mode, x, y, w, h}, fades by gUnk_08107C1C every
  8 frames, gfx groups $24 / $25; mode 2 (sub_080573AC: half-speed scroll,
  bg3Offset drift, the per-line sine HOFS wobble, the gUnk_08107C30 cycle),
  mode 4 (sub_08057450: x $10, y / 4 down the 64-row gBG3Buffer map, colours
  $87-$8A / $8C-$8F from gUnk_085B4180 every 8 frames).  Shots
  `162840_r33_lray_barrel.png`, `_woods.png`, `163638_r33_lray_woods_mode2.png`.
- [x] **Red ChuChu move types** (new `Collide33.lua`): IsTileCollision for
  every collisionType (value 0 / quarters / $FF from the .c source, $10-$6F
  from the 13 lookups coll.bin already held); EnemyCoF3's jump
  (ProcessMovement2) and sliding under the floor (ProcessMovement5) use
  types 2 / 5.
- Checked: Gleerok's lava-tile restore (GLEEROK_PARTICLE type 1 $80,
  sub_08094708) is RestorePrevTileEntity on the top layer -- back to the
  ROM map; nothing in the boss room writes that layer before (gleerok.c,
  roomInit.c sub_StateChange_CaveOfFlamesBoss_Main), so it changes nothing
  in the port either; not added.
- Fixed in passing: `zelda_tmc_r12_test.lua` failed in Furniture32's push
  check (a stand-in player without `probe`).
- SIMPLIFIED: the world-event view runs no object code except the
  beanstalk's (entities play animation 0); worldEvent5's BG3 cloud fade and
  the rooms' init code are not run; light-ray blends are love's alpha.
- **Final check:** all 65 `tests/zelda_tmc_*_test.lua` pass (new
  `zelda_tmc_r33_test.lua`, 41 checks); audit 605/605 (`r33/out_a_rooms.txt`);
  harness cache rebuilt at 25.
- [ ] Left: the cave / crypt object and manager fallbacks of the round 27
  survey (CaveObjects / CaveManagers: managers $03 / $06 / $09 / $0F / $16 /
  $27, the objects listed in `r27b/sv/out_sv_dun.txt`; a fresh survey would
  show which remain), Link pushed out by moving furniture (sub_0800445C /
  CalcCollisionStaticEntity: Link still walks with it), the shelves' act
  tiles, BEANSTALK in the field (types 7-9, the climb), worldEvent5's overlay.

## Round 34

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r34/` (scenes through
`r27b/scene.sh` from checkpoint `a_end`: `survey34.lua` (the fresh survey,
`out_survey34.txt` before / `out_survey34b.txt` after), `bean34*.lua`,
`dig34.lua`, `misc34.lua`, `we5.lua`, `obj34.lua`, `vortex34.lua`,
`shelf34.lua`, `probe34.lua`; `py/sfxcheck.py` = the SFX / BGM constant
check; `audit34.sh`).  Shots in `r27b/shots/*_r34_*.png`.
**Cache version: 25** (unchanged: no new extracted tables; the dig-cave
entrances and the vortex exits are written out from the .c source, as
earlier rounds did for small tables).

- [x] **Fresh survey** (`survey34.lua`: every room, 30 frames; for each
  object the Dungeon dispatch refuses, what Field's fallback did with it --
  ground / pot / script / static frame / zero frame / animation 0 /
  invisible).  605 / 605 rooms without a Lua error; 0 enemy fallbacks.
  Before: 225 object id.type keys in the fallback (34 invisible), 30
  manager keys unhandled (not 03 / 06 / 16), 6 script natives missing.
  The most visible holes: DIGGING_CAVE_ENTRANCE_MANAGER $04 (17 rooms: no
  Mole Mitts cave could be entered), BEANSTALK $2C types 7 / 8 (10 + 5
  rooms), CLOUD_OVERLAY_MANAGER $18 (all of Hyrule Field),
  WEATHER_CHANGE_MANAGER $10, BIG_VORTEX $82 (4 rooms: the way to the
  Cloud Tops / Palace of Winds), BACKGROUND_CLOUD $4A, FIREPLACE $8D (7
  houses), STEAM / SMOKE / BELL / GIANT_ROCK / GIANT_LEAF /
  HIDDEN_LADDER_DOWN.  After this round: 210 object keys, 27 manager keys.
- [x] **R34.lua** (one line in R27B.MODULES, one in Field:drawWorld):
  sub-dispatcher for this round's modules; the room-load music rules:
  LoadRoomBgm's LV6_KANE_START -> BGM_FIGHT_THEME2, the MUSIC_SETTER tile
  entity (type 7, `queued_bgm = t->_3`; the beanstalk rooms' BGM_BEANSTALK),
  both before the room code (only when no room code set a song);
  weatherChangeManager.c sub_08059608 (Mt. Crenel summit: east of x $200
  BGM_CRENEL_STORM, else BGM_MT_CRENEL, $78 frames after a stop).
- [x] **The beanstalk** (`Beanstalk34.lua`): beanstalk.c type 7 (the stalk:
  waits for its fused Kinstone's local flag; sections every $38 px with
  three leaves of gUnk_08120DFC each; SPECIAL_TILE_23 ladder column on both
  layers from the room top to its y; leaves shake / loop), type 8 (the
  cloud top: SPECIAL_TILE_23 at its tile, the CHUCHU_BOSS_PARTICLE stalk
  piece, type 9), type 9 (SPECIAL_TILE_20 under the top while Link is on a
  ladder, the kept tile back otherwise), BACKGROUND_CLOUD (drifting clouds,
  gUnk_08121EB0 speeds, wrap with a random wait).  Climbed with real keys:
  Mt. Crenel's stalk ($06:00, flag $AF) -> climb room $0D:10 -> north
  border -> cloud top $0D:00 (88, 104) -> down onto the stalk -> area warp
  -> $0D:10 (120, 24) -> south border -> $06:00 (`out_bean34c/e.txt`).
  Shots `171619_r34_cr_fixed.png` (climbing), `171301_r34_top.png`,
  `171923_r34_crenel_stalk.png`.
  INFERRED (not found in the decomp): the climb rooms' picture
  (map_top_special on BG1) is drawn at priority 3 so the stalk (OAM 2) and
  Link show over it, as on the cartridge; the way UP from a field stalk
  into its climb room is the reverse of the climb room's south exit (the
  field rooms list no exit into area $0D).
- [x] **Dig caves** (`DigCave34.lua`): diggingCaveEntranceManager.c (the
  entrance table, Init's SPECIAL_TILE_128 row in a cave,
  CheckEnterEntrance both ways), EnterEntrance's offsets, sub_0807C810
  placement, sub_08080368 (the field's dug tiles back on return),
  sub_0805E248 (the hole's tiles at the target, Veil Falls' own set), the
  window closing / opening by 6.  Scene: Eastern Hills $03:04, the rock at
  (3, 11) dug with ItemMitts.digWall, walked into -> $13:00 -> walked out
  -> $03:04 (`out_dig34.txt`, `172022_r34_dig_iris.png`).
- [x] **Cloud overlay** (`Cloud34.lua`): cloudOverlayManager.c -- the
  BLDALPHA ramp $F01 / $E02 / $E03 / $E04, bg3Offset drift, persistent
  across the area's rooms, BG3 from the room's $F000 map / $4000 tiles;
  blended as the GBA does ((BG3 * EVA + below * EVB) / 16, two passes).
  `172126_r34_clouds_on.png` / `_off.png`.
- [x] **worldEvent5** (`WorldEvent34.lua`, hooks in Fusion32; Bg3.build
  takes a gfx group): the cloud BG3 (gfx group 18 / 19 of gUnk_080FF1D4
  over the room's tiles, its BG3 offsets), BLDALPHA $10, the fused room
  under it, 60 frames, SFX_EVAPORATE, the gUnk_080FF204 fade every 8
  frames, SFX_SECRET_BIG, 120 frames.  `172340_r34_we5_clouds.png`,
  `_fading.png`.
- [x] **BIG_VORTEX + parachute 6 / 7** (`Vortex34.lua`, small hooks in
  Whirlwind.lua): bigVortex.c (hidden until its flag, FX + 45 frames, the
  child sprites, Link caught within 8 x 8 -> PLAYER_PARACHUTE with
  field_0x38 1 / field_0x39 type2, TATSUMAKI for type2 1); PlayerParachute
  states 6 / 7 (spin, sink to z -16, 30 frames, rise 60 frames) ->
  DoExitTransition(gUnk_0813AD88[type2]) or InitParachuteRoom (Cloud Tops
  whirlwinds: the room above).  Scene: Wind Ruins $1A:00 vortex -> Cloud
  Tops $08:02 (`out_vortex34.txt`, `173204_r34_vortex_up.png`).
- [x] **Furniture pushes Link out** (`Push34.lua`, one line in Furniture32
  Action2): sub_0800445C / CalcCollisionStaticEntity (arm_sub_080B227C)
  with the furniture's ROM hitbox.  **Act tiles**: SetActTileAtTilePos for
  the shelves (ACT_TILE_0 on the row under them) and the staircase top
  (ACT_TILE_63) kept per cell (Push34.actTile, read by Climb.actAt).  The
  probe found the shelves' row already act 0 in both shelf rooms, so the
  visible change is the staircase's auto-ladder top.  r32 furniture scene
  re-run 18 / 18.
- [x] **Small objects** (`Objects34.lua`): GIANT_ROCK, GIANT_LEAF (its 13
  SPECIAL_TILE_116), BELL, HIDDEN_LADDER_DOWN (shown on its flag or on tile
  $1A6), FIREPLACE (tile $30B + SPECIAL_TILE_97, put out -> $30C / 98 +
  flag), SMOKE (puffs), STEAM (alpha-blended, the sway table, rising past
  x $1F0; Field draws an OBJ with `e.drawAlpha`).
  `172532_r34_fireplace.png`, `_steam.png`.
- [x] **Sound check.**  The song table (Layout.gSongTable $08A11DBC) is the
  cartridge's: all 548 decomp entries line up with the ROM's music-player
  indices (the EU `#ifdef` entry accounted for); SoundReq numbers are song
  numbers, as the port plays them.  Every named SFX_ / BGM_ constant in
  src/zelda/tmc was checked against include/sound.h (`py/sfxcheck.py`): 184
  match, 2 differ in name only (BusinessScrub's SFX_EM_DEKUSCRUB_HIT and
  chuchu's SFX_12B under other local names) and one was wrong: the ghini's
  touch played SFX_PLY_JUMP ($7C) instead of SFX_PLY_VO6 ($7A) -- fixed in
  EnemyField1.  Missing music rules added (above).  Not done: the
  music-player channels (an SFX on the same player as another cuts it on
  the cartridge; the port mixes them) and SONG_FADE_OUT_BGM (a stop).
- SIMPLIFIED: dig-cave window = the field's circular iris (WIN1 draws an
  ellipse) and gCaveBorderMapData's border maps are not loaded during the
  window; the vortex / parachute arrival (PL_SPAWN_PARACHUTE_FORWARD) is a
  plain arrival; KINSTONE_SPARK's script in worldEvent5 is a 60-frame wait;
  weatherChangeManager's palette mix and rain are not ported; STEAM's
  blend is love's alpha.
- **Final check:** all 66 `tests/zelda_tmc_*_test.lua` pass (new
  `zelda_tmc_r34_test.lua`, 68 checks; 3156 checks in all,
  `r34/out_tests.txt`); audit 605 / 605 (`r34/out_a_rooms.txt`).
- [ ] Left (from `out_survey34b.txt`): the Minish Paths / rafters parallax
  backgrounds (managers $02 / $08 / $09), RAINFALL $1C, HYRULE_TOWN_TILESET
  $12, HOUSE_SIGN $13, MINISH_VILLAGE $07, MISC_MANAGER types 0 / 7 / 9 / 10
  / 12 / 13, ARMOS_INTERIOR_MANAGER $27 (the 11 Armos rooms $2C:xx, with
  their FLAME $2A type 4); objects PRESSURE_PLATE type 2 ($47:02),
  GIANT_BOOK_LADDER, HOUSE_DOOR_INT, LILYPAD_SMALL, PINWHEEL,
  WIND_TRIBE_FLAG, TREE_HIDING_PORTAL, the shop items of $23:03; script
  natives $0806757D, $0806ADFD / AEE5 (8 rooms), $0806DAAD / DAD1 (6),
  $0806DB85; the world-event view still runs no object code except the
  beanstalk's (event entities play animation 0).

## Round 35

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r35/` (`data_audit.txt` =
the audit; `py/scan.py` / `py/spans.py` = the scanner, `eval.lua` = the
literal evaluator, `py/match.py` = the ROM search, `py/apply.py` /
`py/man.py` + `man_*.txt` = the rewrites (each compared against the old
literal before writing), `verify*.lua` = old literal vs ROM decode,
`py/audit.py` = the audit writer, `tests.sh` = all TMC tests through
run_lua_check, `check35.sh` = harness cache rebuild + room audit,
`bak_src/` = the source before the round).
**Cache version: 26** (new `r35.bin` + `manifest.r35`, written by
`RomTables.run`).

**Rule of the round: no game data ships.**  Every table of values taken from
the game is read from the player's ROM at import time.

- [x] **RomTables.lua + RomTablesCat.lua**: the catalogue holds, per table,
  only its USA bus address (mostly the decomp symbol), the read layout
  (`"u8"`.. `"s32"`, `"b8"`, `"{name:type,xN,...}"` rows with skips, count,
  base / step / rowbase / stride, groups, pointer tables of lists ended by a
  terminator or by the next list, KeyValuePair lists as sets / maps / keys,
  pointers to single rows) and a Fletcher-32 of its bytes.  `RT.build` (the
  import step `r35`, after `r33` in Extract.run) copies every range into
  `r35.bin` and **fails the import loudly** when a range is outside the ROM or
  its checksum differs (`"ROM tables do not look right (not the USA ROM?)"`).
  Modules ask `require("src.zelda.tmc.RomTables").t("File.NAME")`: the same
  table object for the module's lifetime, filled in place when Assets.new
  attaches the cache (`RT.attach`); reading one before that raises an error
  (no silent empty tables); `RT.fresh` gives a copy for constructors that ran
  inside functions.  Tests and dev scenes attach from the ROM file
  (`RT.attachForTests`, `RT.devRom`).
- [x] **Audit** (`data_audit.txt`): 1157 table constructors of the old source
  (>= 4 numbers or strings) evaluated and searched in the ROM.  **Migrated:
  412 tables + 33 whose parts were migrated, 487 catalogue entries** (hitboxes
  from src/data/hitbox.c and others' Hitbox records, all screen
  transitions, the dig-cave entrance lists (diggingCaveEntrances, round 34's
  copy), the vortex exits (gUnk_0813AD88, round 34's copy), postman routes,
  cucco minigame levels, Gyorg spawn sets, Octorok attack patterns, Darknut /
  door mimic hitbox pointer tables, minecart / ledge-face KeyValuePair lists,
  the town's Dialog arrays (Pina, carpenter, teachers, Hagen, Brocco, stamps,
  hurdy-gurdy man, Mama), message id lists, enemy timers, speeds, offsets ...).
  BossMazaal's copied enemy definitions are gone (the cache has them; tests
  read them from the ROM through `Extract.extractEnemyDefs` /
  `extractProjectiles`), ItemBow / ItemBoomerang's gItemMetaData fallback reads
  the ROM.  Old literal == ROM decode for every one (verify.lua 320 + 17 + 28,
  man.py checks for the rest; SQ27Cucco's level table now reads the full
  zero-padded rows, same behaviour).
- Kept, with the verdict per line in the audit: logic (runtime records,
  function tables, code immediates / switches the port wrote as tables:
  BombableWallManager_DestroyWall0..4, sub_0805E248's dig-hole tiles, twig /
  frozen-element tile loops ...), id constants (enum names of include/*.h:
  SFX / ITEM / ID records, the code's immediates), ROM / RAM addresses,
  the port's own fallbacks and UI constants.  129 small tables are marked
  "logic / derived": not present as such in the ROM (switch cases, offsets
  in code); 7 of those are unverified guesses.
- [ ] **Left (game data, not migrated, each with its reason in the audit):**
  ToDObjects ICE_VEL (asm ice_velocities, layout not found) and LEVER_OFFS
  (pattern ambiguous), Story27Town2's positional Dialog rows (FARMER /
  GHOST / PERCY / NORMAL_TINGLE: bit-field layout not supported yet) and
  BB_MACROS (ragged PlayerMacro lists), EnemyDHC SLASH_T0 (two-level pointer
  table), CoFObjects PILLAR_KIND (single KeyValuePair list), EnemyField2
  ARROW (merged record), EnemyTraps WM (rebuilt from
  gWallMasterScreenTransitions), Figurines KEY_LAYOUT, and the two
  frame-flag test fallbacks (ItemLantern / ItemMitts FALLBACK).
- [x] **Tests**: every `tests/zelda_tmc_*_test.lua` attaches the tables from
  the ROM first (SKIP without it).  r11's copied R11 tables are now built by
  ExtractR11 from the ROM; r28's transition expectations are read from the
  ROM.  Borderline kept: r22's 4-row item-get animation fixtures.  New
  `zelda_tmc_r35_test.lua` (catalogue holds places only, checksums, a changed
  byte fails the import, every entry decodes, shape checks, every key the
  sources ask for is catalogued; no table values).
- Shared Zelda files (src/zelda/*.lua) hold no TMC game data (checked).
- Dev scenes on the old r27b runtime cache (no r35.bin) attach from the ROM
  named by `TMC_DEV_ROM` (or `_G.R26_DEV_ROM`); the shipped game sets
  neither and re-imports on the cacheVersion change.
- **Final check:** all 67 `tests/zelda_tmc_*_test.lua` pass (7943 checks,
  `r35/out_tests_final.txt`; new `zelda_tmc_r35_test.lua` 4682 checks);
  verify.lua 320 equal + 1 superseded (SQ27Cucco.B -> DEFS), verify2 17,
  verify3 28; harness cache rebuilt at 26 (r35.bin 14423 bytes) and the room
  audit 605 / 605 (`r35/out_a_rooms.txt`); real runtime scene
  (`r35/scene35.lua`: round 34's vortex + dig-cave scenes on the ROM-read
  tables) 5 / 5 (`r35/out_scene35.txt`).
- Not done this round (goal 4, polish): Minish Paths / rafters parallax, rain
  manager, pressure plate $47:02, giant book ladder, house doors.

## Round 36

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r36/` (`data_audit.txt` =
the audit, r35's updated; `py/research.py` = the whole-ROM re-search of the
small tables, `py/decompidx.py` = every numeric array of the decomp matched
against them, `py/ids.py` = the id-constant lists in source order,
`py/addcat.py` + `cat36*.txt` = the catalogue additions (checksums filled by
`cklua.lua`), `regress.lua` = the extended reader against all 487 r35 entries,
`verify36a/b/c/d.lua` = old literal vs ROM decode, `cachecheck.lua` = the
rebuilt cache decodes as the ROM, `fbsim.lua` = the old frame-flag fallbacks
vs Link's ROM animations, `plate36.lua` = the pressure plate scene,
`tests.sh` / `check36.sh`, `bak_src/` + `bak_tests/` = the source before the
round).  **Cache version: 27** (r35.bin gains this round's 63 entries; a cache
that lacks a catalogue entry now counts as no cache).

- [x] **RomTables reader extended**: packed bit-fields
  (`"[u32|flag=0.12|ftype=12.4]"`, one column per bit range), terminated
  plain lists and KeyValuePair maps (`term` / `as` without a pointer table),
  `"ptr"` fields / rows decoded through a nested `sub` descriptor (two-level
  pointer tables), `far` (the bytes are gathered by following the pointers
  at import and kept in r35.bin as {address, length, bytes} segments; the
  decode reads by address) and `lit` (the table's address is read from the
  literal-pool word of the code that references it).  All 487 r35 entries
  decode exactly as before (`regress.lua`).
- [x] **The 14 left-over tables migrated**: Story27Town2 FARMER_DIALOG /
  GHOST_DIALOGS (with NORMAL_TINGLE, $08110280) / PERCY_DIALOGS (bit-field
  Dialog rows; the DIALOG_CALL_FUNC rows keep the function address, mapped to
  the port's function) / BB_MACROS (BladeBrothers_PlayerMacros $081115EC,
  far lists to $C000); EnemyDHC SLASH_T0 (two-level Hitbox pointers);
  CoFObjects PILLAR_KIND (KeyValuePair map); ToDObjects ICE_VEL (lit
  $08008A74 -> ice_velocities) and LEVER_OFFS (resolved through
  PushableLever_CalculateSpriteOffsets' literal pool $080984C8 -> $081234A4,
  the one of the 6 byte matches the code references); EnemyField2 ARROW
  (records with a Hitbox pointer); EnemyTraps WM (gWallMasterScreenTransitions
  by dungeon_idx = location - 23: the same exits for Deepwood / Cave of
  Flames, the cartridge's own for the other dungeons); Figurines KEY_LAYOUT
  (the 9 bytes + the element list to $FF, joined at use).  ItemLantern /
  ItemMitts FALLBACK removed: stand-in assets (tests) read Link's animation
  from the ROM (`RomTables.devSprite`); the written flags were port
  approximations, not ROM values (`fbsim.lua`), so two item tests now step
  until the flag acts instead of counting frames.
- [x] **Re-search of the 136 "not found" small tables** (whole ROM, every
  width / signedness / padding / mixed columns / column-major / KeyValuePair,
  each hit's u32 references; plus the decomp array index): ROM tables found
  behind 53 rows, each checked against the decomp and a literal-pool
  reference from its code, migrated: gBombBagSizes / gQuiverSizes, the
  Octorok boss leg / timer / turn / wait weights and values, the octorok's
  walk / spit / nut tables, gUnk_08123184, gUnk_080B4468 (Link's probe),
  gUnk_080B4490, gUnk_080B4488 (Vaati 2 / 3 tile offsets), sAnims1,
  offsetCoords, sTileTable (ledges), sValues x 2, sOffsets (portal exit,
  script jitter), sensor blade speeds, wall master breathing, mulldozer
  timers, pita's prize chances and kinstones, gUnk_08108C28 (static BG3),
  CuccoMinigameRupees, Mazaal's attack-pattern pointers, the pot throw
  speeds (Q8.8 / Q16.16, scaled at use), gUnk_08123750, the sword beam's
  animations / palettes, gPeahatFlightHeights, gUnk_0811F690 (door art),
  Mutoh's and the smith's Dialogs, sClearFlags, gMapSpecialTileToActTile,
  gUnk_08120E14, projectileSpeeds, gUnk_080D1414, the acro bandits' timers,
  the flying pot's offsets, sLinkFire_PositionOffsets.  The 7 unverified:
  3 were ROM tables (STATIC_TAB, PROBE, TIMER_FLAGS), 4 are code (wizzrobe
  timers, the cucco pen SetTileType calls, the sword beam Init switch,
  vaati.c's switch).  79 rows stay "logic / derived" (key lists, module
  lists, runtime / UI records, switch values; no array in the decomp, no
  referenced bytes).  The 51 id-constant lists are enum names (none is a ROM
  table in source order).  Every migrated value equals the old one
  (verify36a-d: 11 + 33 + 22 + 7 equal, 0 differ).
- [x] **PRESSURE_PLATE $24** (new `Objects36.lua` in R34.MODULES):
  pressurePlate.c -- weight = puzzle entities + Link + Four Sword clones on
  it (spriteOffsetY by sSpriteOffsets), animation by weight (weight + 1 for 4
  frames at type + 1), SetFlag + SFX_PRESSURE_PLATE at type + 2, canToggle
  clears.  $47:02's type 2 plate pressed by Link + 3 clones sets flag $B1
  (`plate36.lua` 6 / 6, `r36/shots/202707_r36_plate_pressed.png`).
- SIMPLIFIED: the plate's puzzle entities are the port's `f.r27puzzle` list
  (gRoomVars.puzzleEntities); the clones are tested with FourSword's state 5
  set directly in the scene.
- **Final check:** all 68 `tests/zelda_tmc_*_test.lua` pass (8563 checks,
  `r36/out_tests_final.txt`; new `zelda_tmc_r36_test.lua` 35 checks);
  harness cache rebuilt at 27 (`cachecheck.lua`: 550 entries decode as from
  the ROM) and the room audit 605 / 605 (`r36/out_a_rooms.txt`).
- [ ] Left (polish): the Minish Paths / rafters parallax (managers $02 / $08
  / $09), RAINFALL $1C ($12:02: needs WATER_DROP $19, not ported), the giant
  book ladder, house interior doors.

## Round 37

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r37/` (scenes through
`r27b/scene.sh` with `TMC_DEV_ROM` set: `plate37.lua` (the $47:02 plate with a
real split charge), `probe47*.lua` / `solid47.lua` / `door47.lua` (the room's
types, solidity, door), `scene37a.lua` (every new module in place),
`lily37.lua`, `we37.lua` (the world-event view), `survey37.lua` (round 34's
survey re-run, `out_survey37.txt`), `pre37.lua` + `out_route37.txt` (the
early-game route check), `tests.sh` / `check37.sh`).  Shots in
`r27b/shots/*_r37_*.png`.  **Cache version: 28** (r35.bin gains 16 catalogue
entries; Extract keeps room properties 8..31, was 8..15).

- [x] **Pressure plate $47:02, on screen.**  Findings: AREA_47 is an unused
  test area; room 2 names tileset 1 of a one-entry gAreaTileSets_45, so the
  cartridge reads $8008D160 (no valid address) as its tileset: the picture is
  undefined, but the tile types (gAreaTiles) load as usual.  The port drew
  nothing AND had no collision (no atlas -> no types).  `Room.load` now takes
  the types from the area's gAreaTiles when the tileset is missing
  (`R37.areaTypes`; the picture stays black; audit unchanged).  The room has
  two rows of four clone tiles.  The door (LOCKED_DOOR type 6) is kind 1: it
  **shuts** behind Link once $B1 is set -- it never "opens".
  Real input (`plate37.lua`): B held 251 frames -> split charge (action 4);
  walking right over the four clone tiles made three clones and split on the
  fourth; the spin -> clones follow (action 5).  **Port bug fixed**
  (FourSword.cloneTile): the old code split on the n-th clone tile; the
  cartridge (SurfaceAction_CloneTile) only splits on a clone tile stepped on
  with every slot full (n + 1 tiles); r26a test updated.  With real clones
  the plate cannot get weight 4 in this room: the clones stand 16 px apart in
  a row and the only way down (row 14, columns 12..14) puts the left clones
  in the wall, so they are boxed in and vanish -- a room geometry fact (it
  is a test room).  Weight 4 placed as in round 36 sets $B1 and the door
  shuts (checked).  The door's OBJ palette is the room's BG palette 4, which
  this room does not have: it is drawn invisible (cartridge: stale palette).
- [x] **Minish Paths / rafters parallax** (`PathBg37.lua`, managers $02 /
  $08 / $09; one hook line in Priority.compose -> `R37.bgPass`): the room
  code's gfx groups (roomInit.c: $11:00 30, $11:01 33, $11:02 31, $11:03 /
  $11:04 32, $12:00 / $12:01 35 (+ priority 0 for $12:00), $12:02 / $12:03
  34), BG3 blended (9, 6) under BG1, both priority 1 (vertical: strips by d +
  (d >> 3) / d + (d >> 2); horizontal: blocks side by side, $400-centred);
  rafters BG1 priority 3 from gfx group $36 + type and palette group $86 +
  type, scrolled by gUnk_081081EC; the room's BG1 off (bgSettings 0).  Shots
  `205310_r37_path1100.png` (foreground leaves), `_rafters2e00.png`.
- [x] **Rain** (`Rain37.lua`): RAINFALL_MANAGER $1C (a drop every 15 frames
  at scroll + ($78, $50) + table offsets, z -200), WATER_DROP $19 (gravity
  Q_8_8(40), west drift, splash animation, SFX_WATER_SPLASH, collision off
  while the horizontal path's BG1 covers Link's head, layer by BG1 cover
  under z -8), WATER_DROP_OBJECT $66 (the affine shadow; Field's affine draw
  takes a separate y scale).  `205310_r37_rain.png`.
- [x] **Objects37.lua**: GIANT_BOOK_LADDER $46 (drawn, the SPECIAL_TILE_142 /
  143 / 108 / 109 / 114 ladder tiles -- Climb reads 142 / 143), HOUSE_DOOR_INT
  $5D (frames by type, own-hitbox push-out, 8 frames pushing -> walks out,
  SFX_111, gone on its flag), LILYPAD_SMALL $73 (rail from the room property
  or, type2 >= $80, gLilypadRails; frame turn every 90; affine pulse; Minish
  Link carried and held up -- one line in Dungeon:checkFall), PINWHEEL $BE
  (gPinwheelFlags), WIND_TRIBE_FLAG $94 (flipX by type), HOUSE_SIGN_MANAGER
  $13 (the 12 / 10 HOUSE_SIGNs), HYRULE_TOWN_TILESET $12 / MINISH_VILLAGE $07
  claimed (their swaps are Field.updateTileSwap since round 14 / 15).
  Kinstone world event 11 (fused: the lily pads on gLilypadRails) now loads
  in the field (one line in Kinstone:applyWorldEvents).
- [x] **Armos37.lua**: ARMOS_INTERIOR_MANAGER $27 (bank-3 flag $67 + type;
  palette groups gUnk_08108D20 every 20 frames through Room:applySwap,
  SFX_EM_ARMOS_ON) and FLAME type 4 (shown while its flag is set).
- [x] **World-event view** (`WorldEvent37.lua`, 4 hook lines in Fusion32):
  WATERFALL_OPENING runs waterfallOpening.c (120 frames, SFX_EVAPORATE, gfx
  $18C 32 frames, gfx $18D 45 frames, SFX_SECRET_BIG, then WorldEvent_25_2's
  120 frames -- the view holds its timer until then), the type-11 lily pads
  ride their rails, the type-1 golden enemies (kind 3, skipped before) are
  shown.  `205913_r37_we25_b.png`, `205913_r37_we1_a.png`.
- [x] **ROM tables**: 16 catalogue entries (addresses checked against the
  decomp and a literal-pool reference: spriteDefs $08121C40,
  HouseDoorInteriorFrameIndices $081227B4, gPinwheelFlags $08125050,
  WaterfallOpening_FrameIndices $08124868, ...); no values in the source.
- **Survey** (`out_survey37.txt`, 605 / 605 rooms, 0 errors): object
  fallback keys 210 -> 198 (invisible 10: shop items of $23:03, $48:20's
  objects $26 / $36), manager keys 27 -> 6 (only MISC_MANAGER $0F types 0 /
  7 / 9 / 10 / 12 / 13), script natives missing 6 (unchanged).
- **Final check:** all 69 `tests/zelda_tmc_*_test.lua` pass
  (`r37/out_tests.txt`; new `zelda_tmc_r37_test.lua` 57 checks); harness
  cache rebuilt at 28, room audit 605 / 605 (`r37/out_a_rooms.txt`).
- **Route check** (real keys, round 10's segments f..l from checkpoint
  `e_end` = North Hyrule Field next to the town, `out_route37.txt`,
  `route_log.txt`): PASS North Field -> Lon Lon Ranch -> Eastern Hills ->
  Minish Woods, Ezlo + Octoroks, shrinking at the stump, the Minish Paths
  (with the new parallax), the Minish Village intro, Festari.  FAIL J2: in
  the barrel Minish's house $20:09 the bot's planner found no free side next
  to the Jabber Nut at (48, 64) ("talkTo: no side reachable"); without the
  nut the Elder ($20:00) repeats message 2122 and the run timed out at
  120000 frames.  Not yet known whether this is the bot or the room's
  collision -- the next thing to check (a placed-Link scene in $20:09).
- SIMPLIFIED: house signs made all at once (no on-screen culling); the
  pinwheel's gUnk_020342F8 bit; armos_data.field_0xac and the palette
  groups' OBJ part; the drop touches Link only near the ground; the golden
  enemies stand still in the view.
- [ ] Left: MISC_MANAGER types, TREE_HIDING_PORTAL $9C (PLAYER_BOUNCE into a
  tree -> Minish entrance), OBJECT_A8 in the view, the $23:03 shop items,
  $48:20's objects, the 6 script natives.

## Round 38

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r38/` (`scene.sh` = r27b's
scene runner with the dev ROM, r38 checkpoints and a wait while any other
LOVE process runs; `pre38.lua` = checkpoints in `r38/ck` (+ `FULLHP=1`
refills hearts on load); `hurtdbg.lua` = hurt traces + the Pesto button
mash; `nut38b.lua` (the Jabber Nut with real keys), `seg_j38.lua` (round
10's J segment with the crate push), `br03*.lua` / `potdbg.lua` (Deepwood
$03's pot), `water38.lua` (continue / game over / drowning in water rooms),
`tests.sh`, `check38.sh`; route logs `route_log*.txt`, outputs `out_*.txt`).
**Cache version: 29** (r35.bin gains `Objects38.BUSH_OFFS`).

- [x] **J2 Jabber Nut blocker ($20:09) -- not a port bug in the room.**  The
  grey square next to Link is the room's own BG picture (a hatch under the
  LADDER furniture $4D type 11), not a drawing error.  The nut
  (CUTSCENE_MISC_OBJECT 7 at (48, 64)) lies on the top walkway, reached only
  through the middle corridor, which five PUSHABLE_FURNITURE type 1 crates
  close (SPECIAL_TILE_74 at (6,5) (6,6) (8,5) (8,6) (7,7); solid since round
  32).  On the cartridge Link is full size inside the Minish houses (the
  transition's spawn type is not PL_SPAWN_MINISH), so he pushes the
  southernmost crate aside (sub_0801A458 needs the Power Bracelets only
  for PL_MINISH) -- as every guide says.  Real keys (`nut38b.lua`): up the
  corridor, right into the crate -> it slides to (8,7), up, left, A: the
  nut (`r27b/shots/213034_r38_crate_pushed.png`, `_r38_nut_got.png`).  The
  bot's planner treated the crates as walls: `r38/seg_j38.lua` pushes the
  crate first.  J2 PASS in the route.
- [x] **Barrel Minish room code**: the DRUG lists (Pico Blooms of the side
  beds and the top row) by DRUG_1..3 / DRUG_COUNT + sub_08060354 (kills since
  the bottle, room flag 0); native sub_08060340 (drug_kill_count).
- [x] **Deepwood $03 pot broke on return (route blocker R1)**: the
  MOVEABLE_OBJECT_MANAGER puts the pot back on its button; the port's button
  then wrote its pressed tile type over the pot's SPECIAL_TILE_0 and the pot
  broke, so the bridge never came back.  button.c sub_08081CB0 / F7C keep
  the pressing object's tile (unk_70) and write it back: done in
  `Dungeon:updateButton` (pressTile).
- [x] **USER BUG: continue over water, drowning forever.**  Causes: (1)
  `Game:save` wrote Link's current position into the save and the game-over
  CONTINUE used the room's arrival point -- the cartridge continues at
  `gSave.saved_status`, which UpdatePlayerRoomStatus copies only when Link
  enters a new location (gArea.locationIndex), i.e. the location's entrance;
  (2) the drown / pit respawn used the room's arrival point as the first
  "safe" spot even when Link arrived over water (on a lily pad), and later
  the last pixel before the water's edge.  Fix: `Field:enterRoom` keeps
  `save.status` by the location rule; `Game:save` no longer overwrites it;
  game-over CONTINUE uses it; `Field:safeContinue` moves an old save's spot
  off water; `Dungeon:checkFall` records only tile centres that are not
  water / a hole / a wall, and `Dungeon:respawnSpot` (also PlayerFall)
  falls back to the nearest safe tile.  Real runtime (`water38.lua`, rooms
  $48:14 / $48:15 / $48:12): a save over water continues on the floor, one
  fall into the water costs 2 and puts Link back on the floor (no loop),
  game-over CONTINUE lands on the floor.  The user's own save was not found
  on this PC (only an old slot in AppData/LOVE/Gen2Recomp).
- [x] **TREE_HIDING_PORTAL $9C** (`Objects38.lua`): sparkles near Link
  (EZERO_1ST), a PLAYER_BOUNCE into ACT_TILE_84 -> 15 + 60 frames,
  CreateMinishEntrance (tile types $185.. 5 x 4), 19 FX_BUSH at
  gUnk_08124364 (ROM), SetFlag, SFX_SECRET_BIG.  Not yet seen in the
  runtime (unit-tested).
- [x] **MISC_MANAGER types 0 / 9 / $C** (`Objects38.lua`).  Left: 7 (light
  regions), $A (text index), $D (player script); the 6 script natives.
- **Route** (real keys, checkpoints in `r38/ck`): e_end -> F..I -> J (crate
  pushed, nut) -> K (Elder, Festari) -> L (Deepwood) -> M, N, O, P, Q, R1-R17
  (Madderpillar, Gust Jar), S1-S8 (barrel web, B1, lily pad), B1.  Bot
  problems met: Puffstools / a Pesto drain the bot (FULLHP on checkpoint
  load; the bot now mashes when a Pesto holds Link); once Link arrived in
  $48:01 at (8, 145) inside the wall (not reproduced from the checkpoint).
  B2: knocked off the lily in $48:15 by the Pesto -> the drown loop above
  (fixed).  Then B2-B18 (`r38/seg_b1b38.lua`: the bot now waits for the
  pickup phase before throwing the corner pot), the Big Green ChuChu, the
  Earth Element, the heart container, the blue warp, Ezlo's words, back in
  the Minish Woods and the village (C1-C7, E1-E3; checkpoint `pre_boss`,
  hearts refilled there).  **Stopped at E4**: the village's south way is
  closed by three SPROUT_CART furniture + a Minish (gUnk_080DC470, loaded
  with the Gust Jar and without M_ELDER_TALK2ND; the carts' tiles fill
  columns 30-34 of rows 54-55 exactly as furniture.c writes them, so the
  cartridge closes it too); round 17 passed only because the furniture had
  no tiles before round 31.  The way in should be Festari's back door from
  the woods (K2/K3), but the bot found no Minish path from the shrine
  courtyard (456, 626) to it (~(464, 830)); not yet known whether that
  needs the stump (grow / shrink) or is a collision issue.  Not reached:
  the Elder after Deepwood, Hyrule Town.
- Checkpoints changed meaning: `Game:save` now writes the location entry, so
  the r38 checkpoint writer stores Link's current place itself.
- **Final check:** all 70 `tests/zelda_tmc_*_test.lua` pass (`r38/out_tests.txt`
  + r11 / round3 re-run after the last fix; new `zelda_tmc_r38_test.lua` 36
  checks); harness cache rebuilt at 29, room audit 605 / 605
  (`r38/out_a_rooms.txt`).

## Round 39

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r39/` (`pre39.lua` =
checkpoints in `r39/ck` (falls back to `r38/ck`) + the bot talking on R;
`flood39.lua` / `flood39b.lua` = whole-room reachability maps, `tiles39.lua`
= tile type / act / collision dumps; segments `seg_e39.lua` (E1-E5),
`seg_c39.lua` + `seg_c39b.lua` (Belari, out of the woods, the town),
`seg_k39.lua` (the Kinstone tutorial), `seg_s39.lua` (Swiftblade, the west
guard, Trilby, Mt. Crenel), `seg_m39a.lua` / `seg_o39.lua` / `seg_m39o.lua` /
`helma39.lua` (round 20's Crenel segments with the mushroom fling and the
Helmasaurs); `cont39.lua` (continue checks), `tree39.lua` (TREE_HIDING_PORTAL),
`kin39dbg.lua`, `tests.sh`, `check39.sh`).  Outputs `r27b/out_r39_*.txt`,
shots `r27b/shots/*`.  **Cache version: 30** (r35.bin gains
`Objects39.LIGHT_REGIONS` / `Objects39.WALKIN`).

- [x] **E4 (round 38's blocker) -- not a port bug.**  M_ELDER_TALK2ND is set
  only by script_GregalHealthy and a Kinstone fusion, so the sprout carts
  (gUnk_080DC470) close the village's south way for most of the game, as on
  the cartridge.  The cartridge's way back from Deepwood: the courtyard's
  tree passage (ACT_TILE $20 MINISH_DOOR_BACK at tile (28, 46), $1F
  MINISH_DOOR_FRONT at (28, 50): Minish Link walks hidden through three
  solid tiles; MinishTunnel.lua since round 18) into the pocket behind
  Festari's house, the special-warp region (464, 836) (room property $A ->
  $20:02), Festari's front door (0x258, 0x58) into the village's north.  The
  bot's planner did not know tunnels.  Real keys: E1-E5 pass (Gentari steps
  aside, local flag $83; `r27b/shots/012617_e_pocket.png`, `_e_village.png`).
- [x] **Out of the woods after the Elder** (the carts again): the Elder's
  back room -> village west border -> the hollow log -> Belari (Bomb Bag) ->
  the clearing's MINISH_PORTAL (296, 880): grow -> a bomb on the debris
  (tile type $177 x 3, row 54) -> the woods' south-west lane -> Eastern
  Hills $03:02 -> $03:03 -> $03:04's lower lane -> west into South Hyrule
  Field -> Hyrule Town.  All real keys.
- [x] **The first-Kinstone scene in Hyrule Town** (script_Npc4EFirstKinstone,
  the Hurdy-Gurdy Man, three kids) -- three port bugs fixed:
  (1) `Hitboxes.update`: most solid NPCs call sub_0806ED78 only on their
  unscripted path; scripted ones (the kids) pushed Link out of the man's box
  -> "Where are you going?" forever.  Now a scripted NPC pushes only when
  its id is in `HB.SCRIPTED_PUSH` (festari, postman, guard, npc9, mailbox,
  stockwell, epona, milk cart, npc23, Castor Wilds statue, cat, cow, dog,
  syrup, rem, cucco chick: no ENT_SCRIPTED split or a scripted call).
  (2) `Field:runPlayerScript`: the end of a player script gave control back
  at once; StartPlayerScript leaves gPlayerState.controlMode alone, so Link
  stays disabled after SetPlayerIdle until the NPC script's
  EnablePlayerControl (`player.ctlMode`, kept by Script $43-$45).
  (3) `Field:giveItem`: GiveItem case $D (ITEM_KINSTONE_BAG, item meta
  unk1): AddKinstoneToBag($72) -- the tutorial piece was missing.
  (4) `Story27Town`: HurdyGurdyMan_MakeInteractable recomputes
  GetFusionToOffer (he had no offer when he spawned).  Real keys: bag,
  piece, L in front of him, the fusion (KINSTONE_32)
  (`r27b/shots/020544_k39_fuse.png`).
- [x] **The west guard** (script_GuardWest) wants the Spin Attack: Swiftblade
  ($28:01, BladeBrothers type 1) teaches it (item $48), talk to the guard,
  spin in his box -> MACHI_02_HEISHI, he steps to (0x18, 0x108).  Trilby
  Highlands, Mt. Crenel's entrance: pass.
- [x] **Mt. Crenel** (round 18-20 segments, real keys): M1-M17 (Trilby's
  cave bomb wall, the scrub's bottle, water, the bean's vine, the ladder
  cave, the spring rock, the stone portal, the Mineral Water) pass; A0-A3
  (Rupee fountain, the cracked wall), then **$26:0B**: the gap is ACT_TILE_13
  (SURFACE_PIT since round 22 -- round 20's bot had walked over it); the
  cartridge's way is the PULLABLE_MUSHROOM south of it, flung north: pass.
  $26:0A: masked Helmasaurs (Gust Jar on the mask, then the sword;
  `helma39.lua`) -- passed once to the pocket (checkpoint `r20_m_pocket`),
  then N1-N4 (whirlwind glide), H1-H3, I1-I4 (the heart-piece cave chest),
  O1-O2 (bomb scrub) pass; on the way back through $26:0A the bot died to the
  Helmasaurs (bot fighting, not a port bug found).  Not reached this round:
  the Grip Ring wall, the summit, Melari, the Cave of Flames entrance.
- Bot fix: `H.talkTo` pressed A ("return"); with nobody answering A uses the
  A item -- bombs at Link's feet (7 bombs, 28 hp at the guard).  `pre39.lua`
  talks on R.
- [x] **Continue checks** (`cont39.lua`, real runtime): town save -> town
  arrival; a town house (location 0) -> the town's entrance; Deepwood rooms
  $48:0B/$14/$15 and the boss area $49 (same location 24) -> the dungeon
  entrance $48:0B, Minish (load and game-over CONTINUE); woods Minish ->
  Minish; Minish Paths (location 0) -> the woods' entry; the village and
  the Elder's house -> the village arrival; Cloud Tops -> its arrival, safe
  (load and game over).  **Bug found and fixed:** Hyrule Field's area
  location is 0 -- each field room sets its own with a LOCATION_CHANGER tile
  entity ($0C, LoadLocationTile) -- so a save in the field continued in the
  last town/house.  `Field:enterRoom` now takes the room's changer.
- [x] **MISC_MANAGER types 7 / $A / $D** (`Objects39.lua`, R37.MODULES):
  Royal Valley's light regions (gUnk_08108354, ROM), the text-index flag,
  the fight walk-in player scripts (gUnk_08108380, ROM; Deepwood's
  Madderpillar room, DHC Darknut rooms).  The DARKNESS tile entity is now
  honoured outside ToDObjects.DARK_AREAS (Royal Valley, Minish rafters,
  Deepwood's torch room, Lon Lon's secret cave, Veil Falls caves, the
  Grimblade dojo ...).  Test `zelda_tmc_r39_test.lua`.
- [x] **TREE_HIDING_PORTAL in the runtime** (`tree39.lua`): PLAYER_BOUNCE
  comes only from the Pegasus Boots; a dash into the trees of $03:01 /
  $03:05 / $03:06 -> bushes, the Minish entrance tiles ($185..), the flag
  (`r27b/shots/022634_tree_0301_open.png`).
- [ ] Left: the bot vs the Helmasaurs, then round 21's segments (Grip Ring,
  summit) and Melari / the Cave of Flames; the 6 script natives.
- **Final check:** all 71 `tests/zelda_tmc_*_test.lua` pass (`r39/out_tests.txt`;
  new `zelda_tmc_r39_test.lua` 22 checks); harness cache rebuilt at 30, room
  audit 605 / 605 (`r39/out_a_rooms.txt`).  Checkpoints in `r39/ck`: `e2_woods`,
  `e_end` (Elder after Deepwood), `c39_bombs`, `c39_hills`, `c39_town`,
  `k39_fused`, `s39_spin`, `c39_trilby`, `c39_crenel_in`, `r19_m_mineral`,
  `r20_m_pocket` (latest).

## Round 40

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r40/` (`scene.sh` = r38's
runner with `pre40.lua` (checkpoints in `r40/ck`, falling back to r39 / r38);
`go.sh <out> <checkpoint> <segments>` = one LOVE run with `FULLHP=1`, the
check lines printed; `lib_helma40.lua` (`H.helma40`, the Helmasaur controller),
`helma40.lua`, `seg_o40.lua` / `seg_o40b.lua` (round 39's O with it),
`seg_gr40.lua` (the Grip Ring with the Rupee top-up), `seg_e40.lua` (E2 as
information), `seg_g40.lua` (the Cave of Flames Helmasaur room),
`hurtdbg40.lua` / `trace06.lua` (per-frame hurt and $50:06 traces),
`tests.sh`, `check40.sh`).  Outputs `r27b/out_r40_*.txt`, shots
`r27b/shots/*`.  **Cache version: still 30** (no import change).

- [x] **Route with real keys, Mt. Crenel -> the Cave of Flames' Helmasaur
  room** (checkpoint chain, hearts refilled at each checkpoint load):
  - `r20_m_rupees` -> O (the scrub's bombs, the mushroom fling, **the
    Helmasaur hallway $26:0A with the new controller: 4 masks pulled, 4 kills,
    0 damage**) -> pocket (`out_r40_o1.txt`, 4/4).
  - b, c, d, m19f, e, f: the whirlwind glide, the ladder, the dust, the
    Minish rock, the bean, the Mineral Water, up the vine (14/14,
    `out_r40_b1.txt`); then j0, j, k, l, m (the fairy fountain, the two
    caves, the block puzzle, the whirlwinds to the Cave of Flames ledge)
    (`out_r40_c2.txt`).
  - The Grip Ring, the climbs, the summit (`out_r40_g3.txt`): N0-N3, P1,
    Q1-Q2, R1-R2 pass.
  - Summit -> Melari -> the Cave of Flames door in one run (`out_r40_s1.txt`,
    **32/32**): the mushroom fling, the stone portals, the Minish path $12:02,
    the boulders, the block cave, the bridge bomb, the pillar cave, the chest
    cave, the Minish path $12:03, Melari's mines (the broken sword handed
    over), the mines' west door, the windcrest, the ladder into $50:03.
  - Cave of Flames (`out_r40_f1.txt`, `out_r40_f6.txt`): the Bob-omb room,
    the compass, $50:05, the stairs, the mine cart west, the bombed wall into
    $50:07 and **its four Helmasaurs (new this round: round 25's bot died
    there)**, the Minish portal stone (flag $22).  Checkpoint
    **`r40_cof_helma`** (latest).
- [x] **Port bug fixed: enemies stuck in a tile they overlap.**  In $50:06
  Link pushed a pot (pots slide: pot.c SPECIAL_TILE_1-4) onto a Bob-omb's
  side; the port's ProcessMovement0 (`EnemyDeepwood.move0`) tested all four
  hitbox corners at the new place, so a Bob-omb overlapping the pot's tile
  could not move in any direction and stood there for good, hurting Link
  every 64 frames (13 hits, death; `out_r40_f2.txt` / `out_r40_f4.txt`).
  CalculateEntityTileCollisions tests the side the entity moves toward:
  `move0` now does the same.
- [x] **Port bug fixed: enemy knockback.**  `Enemies:update` moved a knocked
  enemy unless its centre point was solid **on layer 1** -- in the all
  top-layer Cave of Flames every wall was ignored.  Now Knockback1 / 2
  (movement.c): the entity's own layer, the hitbox side it moves toward,
  each axis on its own.
- [x] **Bot: the Helmasaurs** (`r40/lib_helma40.lua`): helmasaur.c's masked
  Helmasaur never walks; it turns to Link when lined up within $10, winds up
  60 frames and charges.  Round 39's bot walked into them (H.goTo engages
  any foe within 48 px with the sword, which bounces off the mask).  The new
  controller plans its own path that keeps 22 px off every masked
  Helmasaur and off the lane of one winding up / charging, stands lined up
  28 px off, faces it, holds the Gust Jar (OnGrabbed: tolerance 60 -> the
  mask comes off), then the sword; it steps sideways out of a charge lane.
  $26:0A: 0 damage; $50:07: 4 damage.
- [~] **Bot skip: Rupees for the Grip Ring.**  The checkpoint chain arrives
  at the Business Scrub with ~27 Rupees (round 21's from-title run had more;
  round 39's chain spent 30 on the bomb refill).  Farming with the bot
  (re-entering $06:02 for Peahat drops, mowing) gave +3 in nine cycles and
  died (`out_r40_g1.txt`, `out_r40_g2.txt`).  CreateRandomItemDrop was
  compared with itemUtils.c (tables, modifiers, the walk) and matches, so
  this is the bot's economy: `seg_gr40.lua` tops the Rupees up to 40
  (printed as `SKIP40`).
- [x] **The last six script natives** (`Natives40.lua`, one line in
  `R37.MODULES`): castorWildsStatue.c sub_080676D8 / sub_0806757C /
  sub_080675D4 (the rock's cracked pictures gUnk_08110E68, the FX at
  gUnk_08110E78 / gUnk_08110E8A, the four tiles walkable again),
  townMinish.c TownMinish_MakeInteractable / sub_0806AEE4 (the head looking
  at Link, gUnk_081125F4), npc4E.c NPC4E_MakeFuserInteractable (the
  clouds' / Source of the Flow's Kinstones), NPC4E_SetPinwheelFlag (the
  gPinwheelFlags flags + SFX_TASK_COMPLETE), sub_0806DB84 (the two
  MINISH_VILLAGE_OBJECT stones with the scripts its literal pool names).
  Tables read from the ROM's npcData window; no values in the source.
- **Darkness check:** the DARKNESS tile entity (room.c LoadDarknessTile ->
  sub_0805BB00(_3, 1)) is only in the rooms listed by the decomp's
  entity_headers.s (Royal Valley, the Minish rafters cafe / Stockwell, Lake
  Hylia's Minish cave, Deepwood's torch room, Droplets, Palace of Winds'
  dark compass hall, DHC, Lon Lon's secret cave, Veil Falls caves, the
  Grimblade dojo); none is on Mt. Crenel or in the Cave of Flames, and no
  route shot this round is darkened.  The level is the byte `_3` (paramB
  $8000 -> $80, half dark), as Objects39 reads it; a room without the tile
  in a dark area lerps to 256 (sub_08052EA0), as on the cartridge.
- SIMPLIFIED: sub_0806DB84's hitbox swap (gUnk_08114154) is not modelled;
  the statue FX are not sorted above the rock.
- [ ] Left (Cave of Flames): the Minish way from $50:07's portal to $50:09
  (MinishLava), the map, both small keys ($50:08 flag $26, $50:01 flag $18),
  the key door to the lever, the Spiny ChuChus and the Cane of Pacci ($50:01
  flag $19), the lower floor ($50:10..$50:17), the big key ($50:17 flag $39),
  Gleerok in a chained run, the Fire Element, back to Melari (the White
  Sword) and Hyrule Town.
- Tests: `tests/zelda_tmc_r40_test.lua` (30 checks: the natives against the
  ROM, the knockback and move0 side tests).
- **Final check:** all 72 `tests/zelda_tmc_*_test.lua` pass (`r40/out_tests.txt`;
  new `zelda_tmc_r40_test.lua` 30 checks); harness cache rebuilt at 30, room
  audit 605 / 605, 0 mismatching (`r40/out_a_rooms.txt`).  Checkpoints in
  `r40/ck` (37): `r40_hall0a`, `r20_m_pocket2` ... `r21_m_grip`,
  `r21_m_summit`, `r22_a_east2` ... `r22_q_cof`, `dev_r24_bobomb`,
  `dev_r24_compass`, `dev_r25_maincart_hp`, `dev_r25_cartwest`,
  **`r40_cof_helma`** (latest: $50:07, the four Helmasaurs beaten, the portal
  stone shown).

## Round 41

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r41/` (`go.sh` / `scene.sh` =
round 40's runner with `pre41.lua` (checkpoints in `r41/ck`, falling back to
r40 / r39 / r38); `lib41.lua` (`H.idle41`, `H.chest41`, `H.map41` = whole-room
picture with entity boxes, `H.axis41`, `H.plat41` / `H.hop41` = lava platform
hops through the overlap of the two boxes); segments `seg_a41` .. `seg_n41`;
diagnostics `diag07*.lua`, `tun41.lua` (tunnel / portal act tiles of the CoF
rooms), `grid.lua` (act / collision grid of a room), `studs*.lua`, `trh.lua`,
`gust41.lua`, `hole08.lua`, `blk08.lua`, `types08.lua`; `tests.sh`,
`check41.sh`).  Outputs `r27b/out_r41_*.txt`, shots `r27b/shots/*`, room
pictures `r41/map08.png`, `r41/map09.png`.  Route reference: thonky.com's
Cave of Flames page (the order of the rooms), checked against the decomp's
entity lists.  **Cache version: 31** (r35.bin gains `Bombs.ARCH_TYPES`).

- [x] **The $50:07 screenshot (`r27b/shots/104251_g_stone.png`).**  (a) The
  black bar near the bottom is the message window growing (TextBox.cartDraw,
  sizeScale 2-3 of 8): the room's TILE_EZLO_HINT (msg $B3B, flag $23) opens as
  the portal appears -- not a bug.  (b) **Port bug fixed:** the flat brown
  patch at the right wall was the bombed wall's centre tile without its
  ARCHWAY.  BombableWallManager_DestroyWall0..4 on the TOP layer (all of the
  Cave of Flames) creates an ARCHWAY getArchwayType() =
  archwayTypes[gArea.dungeon_idx] (read from the ROM, `Bombs.ARCH_TYPES`,
  $08108CFC), type2 6..9 by side, at the side's offset, collision layer 2;
  `Bombs.destroyWall` only did that for the bottom layer.  Now the opening
  shows its rock arch (`r27b/shots/141259_r41_d07_a.png`).
- [x] **Port bug fixed: a portal made of special tiles could not be jumped
  on.**  MINISH_PORTAL_STONE puts SPECIAL_TILE_64..72 down; their act tile
  is gMapSpecialTileToActTile's (all ACT_TILE_61).  `PortalJump.frontAct`
  returned nil for any tile >= $4000, so Link walked against the Cave of
  Flames' portal stones.  It now reads `Climb.SPECIAL_TO_ACT`.
- [x] **Port bug fixed: Minish Link grew back on a room scroll.**
  `Field:transitionSwitch` set `player.minish` from the exit's spawn type for
  every transition; a scroll into the next room of the area (no exit entry,
  scroll.c) never reaches InitializeEntities / InitializePlayer, so Minish
  stays Minish (`adjacentRoom` exits carry `scroll = true`).  Before, Link
  came out of $50:07's crack full size inside $50:06's wall.
- [x] **Port bug fixed: Minish Link could not jump ledges.**  PlayerMinish's
  walk (sub_08073D20) calls sub_08079550 like PlayerNormal; PlayerJumpInit /
  sub_08071130 / sub_08071208 skip the jump / land animations for
  PL_MINISH.  `Ledge.check` refused Minish.  $50:09's raised walkway is left
  only through the gap in its stud barrier (col 5 row 10) and the ledge
  behind it (ACT 2C) -- the stairs are solid for Minish (the Minish table
  maps collision $28 / $29 to the full mask; checked in the ROM).
- [x] **Port bug fixed: a thrown Rollobite stopped at a hole's edge.**
  PlayerItemHeldObject moves a thrown object with ProcessMovement10
  (collision type 10), for which a hole is not solid; the port tested
  collision type 0.  `EnemyBeetle` (the Rollobite carry hook) now uses
  `Collide33.isSolid(..., 10)`: thrown into $50:08's hole it holes up
  (SPECIAL_TILE_52) and Link walks over it.
- [x] **Port bug fixed: a pushed block on the top layer stayed in place
  (and was copied).**  SetTileType with a type the layer's tileset has no
  metatile for leaves the map entry $FFFF (LoadRoomTileSet fills
  tileIndices with $FFFF) but still writes the type's collision / act tile.
  `Objects:setTileType` did nothing, so PUSHED_BLOCK's TILE_TYPE_32 (only in
  the bottom tileset) never replaced the block: the block showed twice and
  still blocked the pillar's way in $50:08.  New `Room:setTypeOnly`
  (map $FFFF, nothing drawn, type / collision kept).  SIMPLIFIED: what the
  cartridge draws for map entry $FFFF is not modelled (the bottom layer shows
  through).
- [x] **Route with real keys** (checkpoints in `r41/ck`, hearts refilled on
  each load): `r40_cof_helma` -> A1 Minish at $50:07's portal (`r41_a_minish07`)
  -> C1-C4 the cracks $50:07 -> $50:06 TL -> TM -> TR -> BR -> $50:09
  (Spiked Beetles wait at the first crack's mouth; `r41_c_09`) -> F1-F2 west
  and south on the walkway, the gap, the Minish ledge jump, east past the
  flames, grown at the portal (`r41_f_09big`) -> G1 up the stairs, the
  dungeon map (`r41_g_map`) -> H1-H3 the lava platforms west, the small chest
  (flag $29), the switch (flag $28) (`r41_h_switch`) -> I1-I2 back to the
  island, the Gust Jar pulls the four pots off the platforms' way, the
  platforms to the bottom floor, west door into $50:08 (`r41_i_island`,
  `r41_i_08`) -> J1 the moving lava platform west (`r41_j_left`) -> K1 a
  Rollobite rolled up, lifted and thrown into the north hole -> L1-L3 the
  pots, the left stairs, the ledge jump into the whirlwind, the glide over
  the second whirlwind to the landing (`r41_l_landing`) -> M1-M2 the
  north-east switch (flag $24), the one-way block pushed up, the pillar block
  pushed west nine tiles into its hole, the small key (flag $26)
  (`r41_m_key1`) -> N1 north into $50:06 with the key (**`r41_n_06key`**,
  latest).  hp never below 20 except in bot mistakes (below).
- Bot issues (not port bugs): the first lava hop crossed at the boxes' edge
  (x first, Link left the platform at x 159: a fall); walking into lava again
  and again after a respawn emptied the hearts twice (the bot kept the key
  down); a checkpoint reload resets the filled hole (no flag, as on the
  cartridge), so the Rollobite step is chained with the next one; the Gust
  Jar needs ~70 frames on the pots.
- Looked at, not changed: the steam haze over $50:09 / $50:08 / $50:00 /
  $50:17 is STEAM_OVERLAY_MANAGER's BG3 at EVA 8-10 / 16 (round 31), from the
  ROM picture and blend table; strong but by the data.
- [ ] Left (Cave of Flames, from `r41_n_06key`): the key door to the lever
  ($50:04 (600,56) / (680,56)), the lever, the cart to $50:02 / $50:01, the
  heart piece, the Spiny ChuChus and the Cane of Pacci ($50:01 flag $19), the
  second small key ($50:01 flag $18), the lower floor ($50:10..$50:17), the
  big key ($50:17 flag $39), Gleerok in a chained run, the Fire Element,
  Melari's White Sword, Hyrule Town; Fortress of Winds not started.  Goal 3
  (round 40's natives in the running game) not reached this round.
- Tests: `tests/zelda_tmc_r41_test.lua` (22 checks: the archway table against
  the ROM and the top-layer archway, the special-tile portal jump, the
  scroll keeping Minish, the Minish ledge jump, SetTileType without a
  metatile).
- **Final check:** all 73 `tests/zelda_tmc_*_test.lua` pass (`r41/out_tests.txt`;
  new `zelda_tmc_r41_test.lua` 22 checks); harness cache rebuilt at 31, room
  audit 605 / 605, 0 mismatching (`r41/out_a_rooms.txt`).  Checkpoints in
  `r41/ck`: `r41_a_minish07`, `r41_c_09`, `r41_f_09big`, `r41_g_map`,
  `r41_h_switch`, `r41_i_island`, `r41_i_08`, `r41_j_left`, `r41_k_hole`
  (hole not kept on reload), `r41_l_landing`, `r41_m_key1`,
  **`r41_n_06key`** (latest).

## Round 42

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r42/` (`go.sh` / `scene.sh` =
round 41's runner with `pre42.lua` (checkpoints in `r42/ck`, falling back to
r41 .. r38); `lib42.lua` (`H.board42` board a cart from a side and ride,
`H.line42` hold a direction to an axis value, `H.release42`, `H.cart42`;
checkpoints now keep `gRoomTransition.minecart_data` in `<name>.cart`);
`lib_spiny42.lua` (Spiny ChuChu bot); segments `seg_a42` .. `seg_s42`;
`static42.lua` (every CoF room: entity lists, tile entities, pictures in
`r42/rooms/`); `README.txt`; `tests.sh`, `check42.sh`).  Outputs
`r27b/out_r42_*.txt`, shots `r27b/shots/*`.  Route order checked against
zeldaxtreme.com's Cave of Flames page and the decomp's room names
(roomInit.c: 00 AfterCane, 01 SpinyChus, 02 CartToSpinyChus, 04 MainCart,
06 CartWest, 10 MinishSpikes, 11 RollobiteSwitch, 12 BeforeGleerok, 17
BossDoor).  **Cache version: 32** (r35.bin gains `Hole42.SURFACE`).

- [x] **Route with real keys** (checkpoints in `r42/ck`, hearts refilled on
  each load): `r41_n_06key` -> A1 cart 1 from $50:06's bottom-right
  compartment east into $50:04's right part (`r42_a_04`) -> B1-B2 the two
  Helmasaurs, the small-key door (680,56)/(600,56) (flag $1D), the lever
  (376,88) from its north side along the rail row (flag $1C) (`r42_b_lever`)
  -> C1 cart 1 rides the turned rails to $50:06's top-middle compartment
  (`r42_c_ride`) -> D1-D2 north out of the top-left compartment into $50:02,
  **through the hole in front of the doorway (PlayerInHole, below)**, across
  the lava on the rail, NE archway into $50:01 (`r42_d_01`) -> E1-E3 the
  ledge into the arena, the REGION_TRIGGER, **the eight Spiny ChuChus**, the
  big chest: **the Cane of Pacci** (flag $19) (`r42_e_cane`) -> F1 the
  arena's west door (flag $16) into $50:00 (`r42_f_00`) -> G1-G3 the lava
  platforms (the Cane flips the upside-down one), the Cane into the hole
  (136,152) and the spring onto the upper passage, the button (flag $15)
  (`r42_g_button`) -> H1-H3 the south door into $50:02, a pot lifted, a bomb
  on the cracked wall (552,168) (flag $1A), **the heart piece** in $50:06's
  hidden part (`r42_h_heart`) -> I1-I2 the Cane flips cart 0 (152,104), the
  ride into $50:01 (`r42_i_cart01`) -> J1 the pillar block pushed six tiles
  north into the hole (264,56): **small key 2** (flag $18) (`r42_j_key2`) ->
  K1-K4 cart 0 back, $50:00's upper passage, the ledge, the small-key door
  (136,56) (flag $14), **the stairs down to $50:10** (`r42_k_10`) -> L1-L3
  Minish at the portal (584,152), the crack (376,152) -> (296,152), the
  block maze to the portal (72,72), full size (`r42_l_west`) -> M1-M3 the
  Cane flips cart 2, the ride east, the lever (568,104) (flag $2B)
  (`r42_m_lever10`) -> N1 cart 2 down the turned rail into $50:11
  (`r42_n_ride`) -> O1 four Rollobites rolled up and thrown into the four
  holes of row 10 (`r42_o_holes`, holes not kept on reload) -> P1 the pillar
  block pulled west over them, pushed north and west into the last hole
  (472,72): it becomes a switch (flag $2F) (`r42_p_block`) -> Q1 the switch
  (flag $2E) lowers the bollards (flag $3D) (`r42_q_switch`) -> R1-S1 the
  stairs (392,120), north into $50:10's south-west part (**`r42_s_10sw`**,
  latest).
- [x] **Port bug fixed: a cart that is not in the room was drawn anyway.**
  minecart.c Minecart_Init DeleteThisEntity()s a MINECART whose
  minecart_data entry names another room (or while Link rides one); the
  port's spawn chain returned false and Field fell back to a plain drawn
  object: a dead cart stood in $50:06's bottom-right compartment while
  cart 1 was in $50:04.  `Dungeon:spawnObject` now returns nil for $55.
- [x] **Port bug fixed: the twin small-key door stayed shut.**
  LockedDoor_Action8 also opens when its flag is set without a key of its
  own; $50:04's (600,56) / (680,56) share flag $1D and only the touched one
  opened (`Dungeon:updateDoor`).
- [x] **Port bug fixed: full-size Link fell into holes.**  The surface comes
  from gMapActTileToSurfaceType (now read from the ROM, `Hole42.SURFACE`,
  $08007CAC): ACT_TILE_25 / $F0 are SURFACE_HOLE, and SurfaceAction_Hole
  gives full-size Link PLAYER_INHOLE (snap to (x|8, y|10), ANIM_FALL_IN_HOLE,
  ANIM_IN_HOLE, a direction held over 7 frames hops out: zVelocity 1.625,
  speed $78, collision on) -- no fall, no damage; Minish Link still falls
  (SurfaceAction_Pit).  The port made every SURFACE_HOLE a pit: $50:02's
  doorway from $50:06 (a hole right in front of it) was a damage loop.  New
  `Hole42.lua`, one line in `Dungeon.checkFall`; `Player:hurt` ignores Link
  in the hole (COLLISION_OFF) and a hit during the hop keeps its gravity.
  SIMPLIFIED: SPECIAL_TILE_112 is not put on the occupied hole.
- [x] **Port bug fixed: the Cane's bolt stopped over lava.**  The
  projectile's wall test is sub_080040D8 with gUnk_08003E44 (the type-1
  tile collision, as the arrows): lava, pits and water let it through.
  `Pacci.updateBolt` used `Room:isSolid`, so $50:00's upside-down platform
  could not be flipped from the other one.
- [x] **Port bug fixed: a ledge jump out of a Minish crack.**  While hidden
  in a crack the surface action wrote the collisions word, so sub_08079550
  sees no ledge; $50:10's crack (376,152) -> (296,152) holds a west ledge
  tile and Link jumped out still hidden and walked through the block maze.
  `Ledge.check` skips while `p.tunnel`.
- [x] **Port bug fixed: a holed-up Rollobite could be knocked out of its
  hole.**  Rollobite_TryToHoleUp is COLLISION_OFF; the port kept it
  hittable and the sword's knockback moved it off the filled hole
  (`EnemyBeetle` holeUp sets `e.mask`).
- [x] **Port bug fixed: the jump out of a mine cart ignored walls.**
  jump_status $41 moves Link by the player's own movement; the port moved
  him 64 px into $50:06's west wall.  The `Minecart` exit hop uses `moveBy`.
- Bot / harness issues (not port bugs): r13's exit guard released a key held
  toward a door act tile ($28/$29: the open key doors) -> `H.freeExit`; the
  checkpoint reload reset minecart_data (the cartridge keeps it while Link
  stays in the dungeon) -> `.cart` files; `H.go25` routes poorly through
  rail-collision ($28) tiles and walked into cart 0 (boarding it); the hole
  hop is hit by $50:02's blade trap (2 hp); the Rollobite bot hit holed-up
  ones; throws land about 48 px ahead.
- Looked at, not changed: the Cane's hole spring height (`Pacci.holeLaunch`
  zVelocity n + 1 against the decomp's ((n << 4) - 4) << 12 for
  sub_0807A2F8's n) -- the landing on $50:00's passage is right, the unit of
  n was not settled.  r41's open question (what the cartridge draws for map
  entry $FFFF after a pushed top-layer block) was not checked (no such block
  on this round's route).
- [ ] Left (Cave of Flames, from `r42_s_10sw`): the Kinstone chests of
  $50:10 (flags $2C / $2D), the spiky platforms, $50:12-$50:14, the lava
  room $50:17 (whirlwinds, Cane holes, 100 Rupees), the big key ($50:17 flag
  $39), Gleerok, the Fire Element, Melari's White Sword, Hyrule Town;
  Fortress of Winds not started; goal 3 (round 40's natives in the running
  game) not reached.
- Tests: `tests/zelda_tmc_r42_test.lua` (23 checks: the deleted cart, the
  twin key door, PlayerInHole and the surface table from the ROM, the bolt
  over lava, no ledge jump in a crack, the holed-up Rollobite).
- **Final check:** all 74 `tests/zelda_tmc_*_test.lua` pass (`r42/out_tests.txt`);
  harness cache rebuilt at 32, room audit 605 / 605, 0 mismatching
  (`r42/out_a_rooms.txt`); D re-run at cache 32 (`out_r42_d2.txt`, 3/3).
  Checkpoints in `r42/ck`: `r42_a_04`, `r42_b_lever`, `r42_c_ride`,
  `r42_d_01`, `r42_e_cane`, `r42_f_00`, `r42_g_button`, `r42_h_heart`,
  `r42_i_cart01`, `r42_j_key2`, `r42_k_10`, `r42_l_west`, `r42_m_lever10`,
  `r42_n_ride`, `r42_o_holes` (holes not kept), `r42_p_block`,
  `r42_q_switch`, `r42_r_stairs`, **`r42_s_10sw`** (latest), plus
  `r41_n_06key.cart` (cart 1 where round 25's ride left it).

## Round 43

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r43/` (`go.sh` / `scene.sh` =
round 42's runner with `pre43.lua` (checkpoints and `.cart` files in `r43/ck`,
falling back to r42 .. r38); `lib43.lua` (`H.reach43` room picture with the
reachable cells, `H.pls43` / `H.onto43` / `H.plog43` moving lava platforms,
`H.fire43`, `H.fly43` / `H.glideTo43` whirlwind glide steering);
`gleebot43.lua` (round 25's Gleerok bot + fireball-aware spot choice),
`glediag.lua`; segments `seg_a43` .. `seg_x43`; diagnostics `grid.lua`,
`actmap.lua`, `exits.lua`, `plats17.lua`, `ledgetab.lua`, `projdbg.lua`,
`animdbg.lua`; `README.txt`; `tests.sh`, `check43.sh`).  Outputs
`r27b/out_r43_*.txt`, shots `r27b/shots/*`.  **Cache version: still 32** (no
import change).

- [x] **Route with real keys -- the Cave of Flames finished** (checkpoints in
  `r43/ck`, hearts refilled on each load; **Gleerok fought with the real
  hearts**): `r42_s_10sw` -> A1 $50:10's stud gap (408,424), the east ledge
  to the lower floor (`r43_a_low`) -> B1 the walkway's north ledge (456,344)
  into the pocket, **Kinstone chest 1** (flag $2C) (`r43_b_chest1`) -> D1 the
  east-only block (504,280) pushed out, east between the torches into $50:17
  (`r43_d_17`) -> E1-E5 the big lava room: over the burning floor, the Cane
  flips platform 3 from the shore, platform 1 -> 3 at its stop, down, the
  Cane flips platform 2 below, the Cane flips platform 4, ride 4 east onto the
  middle strip (`r43_e_strip`) -> F0-F2 the Gust Jar pulls the two north pots
  over the lava, the Cane flips platform 5, ride it into the pot area
  (`r43_f_pots`) -> G1-G3 the Cane flips platform 6; 6 -> 7 -> 8 -> 9 -> 10 at
  their crossing points (the Cane flips 8 from 6 and 10 from 8 as they rise to
  their stops), north into the corridor (`r43_g_corridor`) -> H1 $50:13
  (`r43_h_north`) -> I1 the stairs to the rock path, the east ledge into the
  hole (200,152) (PlayerInHole), east into $50:14 (`r43_i_14`) -> J1 past the
  blade traps, **Kinstone chest** (flag $30) (`r43_j_chest14`) -> K1-K2 the
  Cane into the hole (200,120), the spring west over the wall onto the rock
  path's north pocket, the west ledge into the left room (`r43_k_left13`) ->
  L1 the Cane into the hole (72,168), the spring into the whirlwind (72,152),
  the glide north onto the top corridor (`r43_l_top13`) -> M1 east into
  $50:14, the ledge south (216,56) into the whirlwind (216,104), the glide onto
  the south walkway (`r43_m_walk14`) -> N1-N2 west into $50:13's raised part,
  south onto $50:17's north-east ledge, the ledge jump into the whirlwind
  (616,120), the glide south to the whirlwind (584,344), on to the south-east
  ledge, **100 Rupees** (flag $38) (`r43_n_chestledge`, `r43_n_rupees`) ->
  O1 the ledge north, the Cane into the hole (600,344), the spring into the
  whirlwind (584,344), the glide onto the square island (`r43_o_square`) ->
  P1-P2 the ledge south into the whirlwind (416,376), glides to (296,408) and
  (216,392), north onto the central island, **the big key** (flag $39)
  (`r43_p_island`, `r43_p_bigkey`) -> Q1-Q4 the north ledge onto the upper
  island, the Cane flips platform 3, platform 3 to the boss-door ledge, **the
  boss door** (flag $36) -> $50:12 (`r43_q_doorledge`, `r43_q_12`) -> R1 the
  dark centre -> Gleerok's room $51:00 (`r43_r_boss`) -> S1 **Gleerok beaten
  with real hearts** (32 -> 16; 18 bolts, 62 swings) (`r43_s_gleerok`) -> T1-T2
  **the Fire Element and the heart container** (40 max) (`r43_t_element`) ->
  U1 the warp point -> $06:02 at the Cave of Flames ladder (`r43_u_out`) ->
  W1 the ledge (40,328) down to $06:02's lower slope (**`r43_w_slope`**,
  latest).
- [x] **Port bug fixed: the burning floor and spikes did nothing.**
  gMapActTileToSurfaceType maps ACT_TILE_98 to SURFACE_21 and ACT_TILE_24 to
  SURFACE_16; both run SurfaceAction_16: not in the air (sub_080741C4) or on a
  platform (field_0x14), with iframes 0: ModHealth(-2), SFX_PLY_VO6, iframes
  24, knockback 4 frames away from the tile centre.  $50:17's flames (the west
  strip, the upper island, the ledge by the east hole) were walked through.
  New `Hot43.lua`, one line in `Dungeon:update`.
- [x] **Port bug fixed: a lava platform dropped Link while he swung the
  Cane.**  LavaPlatform_IsPlayerOnPlatform asks PlayerCanBeMoved, a test of
  gPlayerState.flags (busy, falling, in a hole, in a cart ...); the port took
  only the states normal / shield / gust, so the Cane swing (PLAYER_NORMAL on
  the cartridge) left Link standing over the lava while the platform moved
  on.  `CoFObjects` playerOn: sword, Cane, knockback, carry, throw and roll
  keep him carried.
- [x] **Port bug fixed: enemies hit Link high in the air.**  arm_CalcCollision
  also tests z (|dz| <= depthA + depthB, 5 + 5 for flat hitboxes): $50:14's
  blade traps knocked Link out of the whirlwind's glide.  `Enemies` contact
  test: |p.z - e.z| > 10 is no contact.  SIMPLIFIED: Hitbox3D depths are not
  read.
- [x] **Port bug fixed: the glide climbed onto a wall.**  sub_0807A2F8 in a
  dungeon (AreaIsDungeon) steps one tile past the ledge faces and wants
  LAYER_TOP collision 0 there; the port tested the bottom layer, so $50:14's
  glide started the climb in front of the wall column between the two
  walkways and flew on forever.  `Whirlwind.ledgeUp`.
- [x] **Port bug fixed: Gleerok's landed fireballs never went out.**  Field's
  literalAnim pass re-sets any entity that is not an enemy / projectile to its
  objAnim every frame; the fireballs (kind 4, no `projectile` flag) were held
  in animation 0, never reached ANIM_DONE and lay burning on the shore for the
  whole fight (16 hits, death).  `G:panim` sets objAnim too.  Also
  EnemyCreateProjectile takes gProjectileDefinition_A's form by type (type 2
  flies at 384).
- Bot / harness issues (not port bugs): the chest act tile opens only facing
  north (ACT_TILE_26: animationState 0) -- the first tries stood beside it;
  the BFS walks over lava and fire (platform steps are scripted); the first
  Cane shots missed moving platforms (the bolt needs ~35 frames for 64 px);
  go25 walked the burning floor and killed Link once; the boss bot had the
  Gust Jar on B (no sword: 201 swings, no damage) and stood on the fireballs;
  the menu cannot open while Gleerok's intro holds Link.
- Looked at, not changed: Kinstone chest 2 of $50:10 ((488,344), flag $2D)
  sits in a top-layer pocket behind three fixed blocks ($365) whose every edge
  is an outward ledge; no way in was found this round (not opened).
  NOT MODELLED: a landed Gleerok fireball on tile type $13 / $34 sets tile
  $34C (burning floor, sub_080A90D8).  The button (248,104) / warp of $50:17
  were not used.
- [ ] Left: Kinstone chest 2 ($50:10 flag $2D); back to Melari -- the mines'
  west door ($06:02 (200,312), tile $173) is not an entrance; the way is the
  round-22 cave chain to the middle plateau's portal (312,293) and the Minish
  path $12:03 (not run); the White Sword, Hyrule Town, the Fortress of
  Winds; goal 3 (round 40's natives in the game) not reached; r41's open
  question (map entry $FFFF after a pushed top-layer block) not met.
- Tests: `tests/zelda_tmc_r43_test.lua` (21 checks: the hot floor against the
  ROM surface table, iframes and the platform exception, the Cane swing on a
  platform, the contact z test, the dungeon glide climb, the fireball
  animation and form).
- **Final check:** all 75 `tests/zelda_tmc_*_test.lua` pass (`r43/out_tests.txt`);
  harness cache rebuilt at 32, room audit 605 / 605, 0 mismatching
  (`r43/out_a_rooms.txt`).  Checkpoints in `r43/ck`: `r43_a_low`,
  `r43_b_chest1`, `r43_d_17`, `r43_e_strip`, `r43_f_pots`, `r43_g_corridor`,
  `r43_h_north`, `r43_i_14`, `r43_j_chest14`, `r43_k_left13`, `r43_l_top13`,
  `r43_m_walk14`, `r43_n_chestledge`, `r43_n_rupees`, `r43_o_square`,
  `r43_p_island`, `r43_p_bigkey`, `r43_q_doorledge`, `r43_q_12`,
  `r43_r_boss`, `r43_s_gleerok`, `r43_t_element`, `r43_u_out`,
  **`r43_w_slope`** (latest).

## Round 44

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r44/` (`go.sh` / `scene.sh` =
round 43's runner with `pre44.lua` (checkpoints and `.cart` files in `r44/ck`,
falling back to r43 .. r38); `lib44.lua` (`H.reach44` room picture with the
reachable cells and the exits, `H.exits44` exit / special-warp list with
reachability), `lib_scene44.lua` (`H.scene44`); segments `seg_a44` ..
`seg_r44`; probes `probe_*.lua`, `dbg_glow.lua`; `README.txt`; `tests.sh`,
`check44.sh`).  Outputs `r27b/out_r44_*.txt`, shots `r27b/shots/*`.
**Cache version: still 32** (no import change).

- [x] **Route with real keys -- the White Sword, the Sanctuary infusion, the
  first split** (checkpoints in `r44/ck`, hearts refilled on each load):
  `r43_u_out` (the west plateau after the warp; see below) -> A1-A2 Minish at
  the stone portal (56,261), east into the mines' west door (exit region
  (192,312), Minish only) -> $10:00 (`r44_a_mines`) -> B1 Melari's
  ITEM_FIRE_ELEMENT branch (PlayerAtMelari, PlaceBrokenSword, GetWhiteSword:
  texts $125C / $0502 / $125D) -- **the White Sword** (`r44_b_white`) -> C1-C3
  out by the guarded west door, grown at the portal, the ledge (40,328) down
  to the lower slope (`r44_c_slope`) -> D1 the Grip Ring rock wall (552,556)
  into $06:03 (`r44_d_0603`) -> E1 the vine (280,290..368) into $06:04
  (`r44_e_0604`) -> F1 down Mt. Crenel to Trilby Highlands $03:07
  (`r44_f_trilby`) -> G1 **Hyrule Town** (`r44_g_town`) -> H1 North Hyrule
  Field, the castle garden (`r44_h_garden`) -> I1-J1 the castle $80:00, the
  north-west stairs to $80:03 (`r44_i_castle`, `r44_j_castle3`) -> K1 the
  Sanctuary entrance $81:00 (`r44_k_sanctent`) -> L1-L2 Ezlo's TEXT_VAATI $2D
  (CutsceneOrchestratorSanctuaryEntrance, NAKANIWA_00_EZERO), north into the
  hall $78:00 (`r44_l_hall`) -> M1 the Sanctuary $78:01 (`r44_m_sanct`) -> N1
  the pedestal from its north notch (232,292): **the Earth and Fire Elements
  infused, ITEM_RED_SWORD** ($0503) (`r44_n_infused`) -> P1-P2 the clone
  tiles (184,520) / (200,520): charged, a clone, PL_CLONING, Ezlo's
  TEXT_PANEL_TUTORIAL 5, local $7D (`r44_p_split`) -> Q1 the metal door
  (232,584) shut behind Link: a clone left on (200,520), Link split on
  (264,520), the spin, Link on the button (264,552) and the clone on
  (200,552) -> the flag manager opens it (`r44_q_door`) -> O1 out through
  the hall, the castle and the garden to **Hyrule Town** (**`r44_o_town`**,
  latest).
  The route starts from `r43_u_out`, not `r43_w_slope`: from the lower slope
  the west plateau is out of reach (the ledge is one way) and round 43's "the
  mines' west door is not an entrance" was a bot failure (go25 gave up short
  of the door): `gUnk_additional_8_MtCrenel_CaveOfFlamesEntrance` has the
  region (192,312) -> $10:00 for Minish Link, and it works.
- [x] **Port bug fixed: the facing was added to animations that take none.**
  sub_08078FB0 adds animationState / 2 only when the animation's low byte is
  below $58 (no cap), $18 (Minish), $34 (sprite 7) or $B8; the port used a
  hand list (NO_FACING), so ANIM_GET_WHITE_SWORD ($1E2) showed $1E4 (Link
  without the sword at Melari), ANIM_GET_NEW_SWORD ($8BF) played $8C1 and
  the Sanctuary's sword glow (Type31, deleted when Link's animation is not
  $8BF) vanished; the death animations ($1BC / $2BD / $459 / $45A) were also
  off.  `Player:setAnim` (the list is kept as extra no-facing ids).
- [x] **Port bug fixed: the Sanctuary entrance had no room code.**
  sub_StateChange_SanctuaryEntrance_Main: with ITEM_GREEN_SWORD list
  $080F5328 and, until NAKANIWA_00_EZERO (local $14), the cutscene
  orchestrator $080F5308 -- Ezlo's scene never ran.  `DHCObjects` O.ROOMS.
- [x] **Port bug fixed: the infused sword stayed the White Sword on B.**
  NPC4E_RestoreEquippedItems puts back NPC4E_GetItemWithSwordUpgraded (the
  best sword owned); the port restored item 2, so FourSword saw no Red
  Sword and Link could never split (the Sanctuary's door puzzle and every
  later clone puzzle).  `Ceremony.lua` $0806DC58.
- [x] **Port bug fixed: CheckPlayerFlags missed PL_CLONING.**  Script $23
  tested `player.flags` only; the port keeps PL_CLONING as `p.cloning`
  (FourSword) and PL_MINISH as `p.minish`; script_08013F94 (Ezlo's clone
  tutorial, local $7D) waited forever and NPC4EPreventPlayerLeave kept
  sending Link back.  `Script.lua` C[$23].
- [x] **Port bug fixed: the new sword's glow was drawn under the pedestal.**
  CutsceneMiscObject Type31 takes Link's collision layer (CopyPosition ->
  PositionRelative copies collisionLayer); it stayed on layer 1 under the
  pedestal's top layer.  `SanctuaryScripts.lua`.
- [x] **Port gap fixed (goal 3): Gleerok's fireballs burn the floor.**
  gleerokProjectile.c sub_080A90D8: on landing (and while type 2 slides on)
  tile type $13 / $34 under it becomes $34C (ACT_TILE_98: Hot43's damage),
  once per tile.  `BossGleerok2` G:burnTile.  Unit-tested only; the fight was
  not replayed.
- Bot / harness issues (not port bugs): round 43's west door; the vine loop
  ended on the transition frame (Link left hanging at y 8); the pedestal
  from the south is out of reach (Link's north probe y-8 stops him short of
  the interact box: the north notch is the way); the clone tiles need a
  second tile after the first clone; the metal door closes again on a
  checkpoint reload (Q and O run in one process); travel from the top of
  the hall walked back north.
- Looked at, not changed: the port's Link tile box is x-4..x+3 / y-5..y+2;
  sub_080085CC with gPlayerHitbox probes x+-5 at y / y-6 and x+-3 at y+2 /
  y-8, so the port lets Link 3 px closer to north walls (not changed: every
  route checked so far depends on it; worth a separate round).
- [ ] Left: Castor Wilds not reached -- South Hyrule Field's north-west
  passage into the Western Woods ($03:08) is a PUSHABLE_ROCK west of a hole
  (from the field Link drops into the hole and hops out against the rock:
  it opens from the woods' side); the bot found no other way (the field's
  south-west bridge and Trilby's south were out of its reach).  So no
  DASHBOOTS, Pegasus Boots, Wind Ruins or Fortress of Winds this round.
  Kinstone chest 2 ($50:10, flag $2D, tile entity paramD 1 = LAYER_TOP) and
  round 40's natives in the running game not reached.
- Tests: `tests/zelda_tmc_r44_test.lua` (27 checks: the facing threshold, the
  sword upgrade on restore, the Sanctuary entrance's lists, the burning
  floor, the glow's layer).
- **Final check:** all 76 `tests/zelda_tmc_*_test.lua` pass (`r44/out_tests.txt`);
  harness cache rebuilt at 32, room audit 605 / 605, 0 mismatching
  (`r44/out_a_rooms.txt`).  Checkpoints in `r44/ck`: `r44_a_mines`,
  `r44_b_white`, `r44_c_slope`, `r44_d_0603`, `r44_e_0604`, `r44_f_trilby`,
  `r44_g_town`, `r44_h_garden`, `r44_i_castle`, `r44_j_castle3`,
  `r44_k_sanctent`, `r44_l_hall`, `r44_m_sanct`, `r44_n_infused`,
  `r44_p_split`, `r44_q_door`, **`r44_o_town`** (latest).

## Round 45

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r45/` (`go.sh` / `scene.sh` =
round 44's runner with `pre45.lua` (checkpoints and `.cart` files in `r45/ck`,
falling back to r44 .. r38); `lib45.lua` (`H.goSafe45`: go25 off water / holes,
fighting close enemies); `comp45.lua` (`H.comp45`: a room's walkable components
with the edge spans each one touches, as a picture); `ledges45.lua`
(`H.ledges45`, `H.tiles45`); segments `seg_a45` .. `seg_j45`; probes
`probe_a` .. `probe_n`; `README.txt`; `tests.sh`, `check45.sh`).  Outputs
`r27b/out_r45_*.txt`, shots `r27b/shots/*`.  **Cache version: 33**
(r35.bin gains `HeavyBlock45.BOX`).

- [x] **The cartridge's way into Castor Wilds found and walked.**  The Western
  Woods / lower Trilby / Castor Wilds region has two one-way shortcuts (the
  PUSHABLE_ROCKs at Trilby (344,664) and Western Woods North (408,424) are
  pushed into their holes from the woods' side) and one real entrance: the
  cave under Trilby's middle shelf, Caves_TrilbyHighlands $32:0E, whose
  corridor is plugged by a 2 x 2 **heavy block** (ACT_TILE_114) with four clone
  tiles beside it -- the first puzzle for the Sanctuary's split.  Castor Wilds
  borders only Western Woods North (west edge, y 76..96).  The Pegasus Boots
  come later from Rem (DASHBOOTS is set by entering Castor Wilds:
  sub_StateChange_CastorWilds_Main; Rem then falls asleep, the Town Minish
  under his shop ask for the Wake-Up Mushroom (KHOUSE52_KINOKO = local $8F),
  Syrup sells it (ITEM_FOR_SALE in the Witch Hut $24:00), Rem wakes and makes
  the boots).
- [x] **Route with real keys** (checkpoints in `r45/ck`, hearts refilled on
  each load): `r44_o_town` -> A1-A2 Trilby $03:07, the shelf cave $32:0E
  (`r45_a_cave`) -> B1-B2 Link on clone tile (248,88), a clone, PL_CLONING on
  (248,104), both push west: **5 pushes** (block from columns 10-11 to 5-6),
  the west stairs (56,40) -> lower Trilby (`r45_b_lowtrilby`) -> C1-C2 Western
  Woods North: **the takeover scene** (Ezlo TEXT_VAATI $18 / $1F,
  SOUGEN_08_TORITSUKI) (`r45_c_wwn`) -> D1-D2 **Castor Wilds $04:00,
  DASHBOOTS** (`r45_d_castor`) -> E1-E4 back east, the rock pushed east into
  its hole (the shortcut), South Hyrule Field, Hyrule Town (`r45_e_town`) ->
  F1-F2 Rem's Shoe Shop: script_RemFallingAsleep (locals $60 / $62)
  (`r45_f_rem`) -> G1-G3 the jar portal (48,46) (Minish), the desk hole
  (exit region (116,88)) into $2D:12, the Town Minish's TEXT_REM $1C-$1E:
  **local $8F** (`r45_g_minish`) -> H1-H2 grown at the jar, town -> North
  Hyrule Field's east edge -> Lon Lon Ranch's west lane -> Eastern Hills
  North (`r45_h_hillsn`) -> the Minish Woods' upper west lane
  (**`r45_h_woods`**, latest).
- [x] **Port gap fixed: the heavy blocks (ACT_TILE_114) did not move.**
  UpdatePlayerCollision case ACT_TILE_114 + sub_0801A570 (the block's top-left
  and size from the probe tile, the one-way corners $369 / $36A-$36D, the far
  side's collision), sub_08084CAC (n - 1 clones leaning on the same block),
  blockPushed.c types 1-3 (TILE_TYPE_32 / 33 trail, the slide, the block laid
  again with its corner), PlayerPush type 0 ($20 frames at kPushSpeed).
  New `HeavyBlock45.lua`, one line in `PushAnim.update`; the PUSHED_BLOCK
  hitboxes gUnk_0811F62C.. read from the ROM (`RomTablesCat`
  `HeavyBlock45.BOX`, cache 33).
- [x] **Port gap fixed: Western Woods North / Castor Wilds had no room code.**
  sub_StateChange_HyruleField_WesternWoodsNorth (LV2_CLEAR + the Red Sword +
  not SOUGEN_08_TORITSUKI -> the takeover orchestrator gUnk_080F82E0) and
  sub_StateChange_CastorWilds_Main (DASHBOOTS; KINSTONE_5B / windcrest /
  no-boots lists).  New `Story45.lua` (an R27A module).  SIMPLIFIED:
  sub_08053BE8 (the aux-room castle scene of the takeover, King Daltus and
  Vaati, gUnk_080FCDE0 / gUnk_080FCE30) is a fade only, as the intro's aux
  scenes.
- [x] **Port gap fixed: Rem's rooms and the Witch Hut had no room code.**
  sub_StateChange_TownMinishHoles_RemShoeShop ($2D:12: the shoe, the three
  Town Minish by the boots, SPECIAL_TILE_114 x19 on row 5 until local $62),
  _HouseInteriors3_RemShoeShop ($23:02: the Ezlo hint with the mushroom),
  _TreeInteriors_WitchHut ($24:00: the mushroom for sale, KINSTONE_14).
  `Story45.lua`.
- [x] **Port bug fixed: Rem's desk hole was solid.**  FurnitureInit's
  SHOE_DESK case sets tile type 774 on the top layer at +65, and SetTileType
  in a room with scroll_flags & 2 (the merged-collision house areas,
  sub_0807C5B0) copies the new collision ($62, open to Minish Link) into
  gMapBottom; the port did neither, so the exit region (116,88) to the Town
  Minish could not be reached.  `Collide31.furnitureInit` (SHOE_DESK) and
  `Objects:setTileType` (the bottom-map copy for MERGE_TOP_AREAS).
- [x] **Port gap fixed: JAR_PORTAL ($38) was not spawned.**  jarPortal.c Init
  (local flag = type, unk_7c = the data's type2 byte: standing or lying) and
  the standing jar's portal (portal_exit_dir 2, the stump rules of
  PortalJump / Objects:tryPortal).  New `Jar45.lua`.  SIMPLIFIED: the flip by
  a hit of type $1D is not modelled.
- [x] **Port gap fixed: nothing could be bought from a counter.**
  ITEM_FOR_SALE (object 2: the item's ground picture, lifted with A while
  shopItemType is 0, held over Link's head, A / B / R puts it back unless
  someone to talk to is in front, deleted once sold), script command $1E
  BuyItem (GetItemPrice from gUnk_080FD964, ModRupees, InitItemGetSequence)
  and gRoomVars cleared per room.  New `Shop45.lua`.  Unit-tested; not yet
  run in the Witch Hut (see below).
- [x] **Goal 3 (part): round 40's castorWildsStatue natives in the game.**
  Castor Wilds' three statues and the rock spawn with their scripts; no
  script native is missing in the room (`Script.missing` empty;
  `r27b/shots/021047_n_statues.png`).
- Bot / harness issues (not port bugs): round 44's "Trilby's south out of
  reach" -- the middle shelf's south ledge is behind a row of pebbles; the way
  down is the shelf cave.  exitTo picks the nearest border lane: from Hyrule
  Town into Lon Lon Ranch that is a pocket closed by boulders (y 560), and
  from Eastern Hills Center into Eastern Hills South a closed pocket; the
  segments walk to the right lanes.  The BFS treats deep water as open
  (Link drowned in the Minish Woods pond twice): `H.goSafe45`.
- [ ] Left: **the Witch Hut** -- from the Minish Woods' upper west lane the hut
  plateau is reachable only across the pond (deep water); its other side
  (`comp_0000h` comp 1) borders Lake Hylia (north edge 372..472), which
  borders Lon Lon Ranch's east part, closed from the west lane by boulders /
  fences.  The cartridge's way to Syrup was not determined this round (bot
  side).  So no Wake-Up Mushroom, Pegasus Boots, Wind Ruins or Fortress of
  Winds yet; `seg_i45` (buy) and `seg_j45` (Rem) are written and wait for the
  hut.  Kinstone chest 2 ($50:10) not opened.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r45_test.lua` (40 checks: sub_0801A570 from each
  side and its corner / far-side rules, the clone count, the slide and the
  new tiles, the ROM hitboxes, Story45's room code, the SetTileType bottom
  copy, the jar portal's state).
- **Final check:** all 77 `tests/zelda_tmc_*_test.lua` pass (`r45/out_tests.txt`);
  harness cache rebuilt at 33, room audit 605 / 605, 0 mismatching
  (`r45/out_a_rooms.txt`).  Checkpoints in `r45/ck`: `r45_a_cave`,
  `r45_b_lowtrilby`, `r45_c_wwn`, `r45_d_castor`, `r45_e_town`, `r45_f_rem`,
  `r45_g_minish`, `r45_h_ranch`, `r45_h_hillsn`, **`r45_h_woods`** (latest;
  `r45_h_hills` is a dead-end pocket of Eastern Hills South).

## Round 46

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r46/` (`go.sh` / `scene.sh` =
round 45's runner with `pre46.lua` (checkpoints and `.cart` files in `r46/ck`,
falling back to r45 .. r38); `lib46.lua`; `reach46.lua` (`H.map46`: a text room
map at 16 px -- R reachable, B cuttable, S swamp, ~ hazard); segments `seg_a46`
.. `seg_q46`; probes `probe_a` .. `probe_n`; `README.txt`; `tests.sh`,
`check46.sh`).  Outputs `r27b/out_r46_*.txt`, shots `r27b/shots/*`.
**Cache version: still 33** (no import change).

- [x] **The cartridge's way to Syrup's hut (goal 1).**  The hut plateau of the
  Minish Woods is not reached from the woods' west lanes (round 45 tried the
  pond) but from **Lake Hylia's south-west part**, whose only ways in are the
  ranch's lower east lane (its east edge, y 724..776 / 884..936) and the
  rock shortcut opened later from the lake's side.  From the ranch's west
  lane the way is the lost-key quest and the two whirlwinds:
  KHOUSE52_KINOKO (the Town Minish's mushroom request) puts Talon and Malon
  in front of their locked house; the stump portal (344,541) in the pen;
  Minish through the west Minish-sized entrance (316,632) into the house's
  west half $28:02; the jar portal (48,94); Talon's key (ITEM_QST_LONLON_KEY)
  in the upper-right pot; out again as Minish by (56,128); the key to Talon
  (script_TalonGotKey / script_MalonLostKey: INLOCK, the door opens); the
  west door, the inner archway (its HOUSE_DOOR_INT gone with INLOCK), the
  east half $28:03 and its door to the ranch behind the fence; the Cane of
  Pacci on the hole (264,168) launches Link onto the stump plateau; off its
  south ledge at x 392 into the whirlwind (392,120) and the glide onto the
  sprout plateau; off its south ledge at x 616 into the whirlwind (616,392)
  and the glide over the ponds; the east edge into Lake Hylia's south-west;
  its south edge into the Minish Woods' top (416,16), which is the hut
  plateau.  The ranch's east edge from behind the fence (y 416..472) leads
  into Lake Hylia's west part, a dead end for the hut (the rock (40,536) sits
  south of its hole: a one-way shortcut from the south).
- [x] **Route with real keys** (checkpoints in `r46/ck`, hearts refilled on
  each load): `r45_h_hillsn` -> A1-A3 the ranch, Talon and Malon locked out,
  the stump: Minish (`r46_a_stump`) -> B1 the west half (`r46_b_west`) -> C1-C4
  grown at the jar, the key (`r46_c_key`), Minish, out (`r46_c_out`) -> D1-D5
  grown, **INLOCK** (`r46_d_inlock`), through the house to the east door
  (`r46_d_east`) -> E1 Lake Hylia's west part (`r46_e_lake`, the dead end) ->
  G1 the Cane launch (`r46_g_plateau`) -> H1 whirlwind 1 (`r46_h_sprouts`) ->
  I1-I2 whirlwind 2, the lower east lane (`r46_i_lane`), Lake Hylia's
  south-west (`r46_i_lake`) -> J1 the Minish Woods' top (`r46_j_woods`) -> K1
  **the Witch Hut** (`r46_k_hut`) -> L0-L2 **the Wake-Up Mushroom bought**:
  lifted with A (shopItemType $38), Syrup's BuyItem, 60 rupees (the first
  real run of Shop45) (`r46_l_mushroom`) -> M1-M3 back through the woods and
  the lake, the ranch's rock (488,904) pushed west into its hole (the
  shortcut) (`r46_m_rock`) -> N1 North Hyrule Field, Hyrule Town, Rem's shop
  (`r46_n_shop`) -> O1 R facing Rem: script_RemFallingAsleep's mushroom
  branch, **the Pegasus Boots** (`r46_o_boots`) -> P1 Castor Wilds through
  Western Woods North (`r46_p_castor`) -> Q1 **three boots dashes across the
  marsh** to the dry middle (`r46_q_marsh`, latest); Q2 walking into the marsh
  without a dash: slowed, a hit (-4) and back on dry ground.
- [x] **Port gap fixed: Lon Lon Ranch had no room code.**
  sub_StateChange_HyruleField_LonLonRanch: KHOUSE52_KINOKO (bank 2) and not
  INLOCK -> gUnk_080F77C0 (Talon / Malon locked out -- without them the key
  could never be given, INLOCK never set, and the house's inner archway
  stayed shut: the way east was closed); else with the Earth Element
  gUnk_080F77F0; TABIDACHI without it gUnk_080F7810; KINSTONE_29 not fused ->
  gUnk_080F7860 + SPECIAL_TILE_114 / 150 at (8,54) / (8,55) (the Goron cave
  shut); Tingle's list.  New `Story46.lua` (an R27A module).
- [x] **Port gap fixed: the ranch house had no room code.**
  sub_StateChange_HouseInteriors4_RanchHouseWest (not INLOCK: the two
  HOUSE_DOOR_INTs -- the port's house was open; INLOCK and progress < 4:
  Malon inside) and _RanchHouseEast (INLOCK: Talon inside).  `Story46.lua`.
- [x] **Port bug fixed: PlayerSetNormalAndCollide ($0807921C) was missing.**
  script_MalonLostKey ends with it; it calls SetPlayerActionNormal, which
  ends a player script (it only runs in PLAYER_SLEEP).  Without it
  script_PlayerGiveKey (waiting for sync flag 2, which nothing sets) kept
  Link held for good after Talon got his key.  Also RequestPriorityOverPlayer
  / RevokePriorityOverPlayer ($0807FBC4 / $0807FBCC) and goron.c sub_080694EC
  (the punching Goron's animation).  `Story46.lua`.
- [x] **Port gap fixed: Lake Hylia had no room code.**
  sub_StateChange_LakeHylia_Main: the hologram scene (LV4_CLEAR), KINSTONE_12's
  list, Tingle's list and SPECIAL_TILE_145 on the 16-tile ring (16..20,
  22..26) round the frozen block.  `Story46.lua`.
- [x] **Port gap fixed: the marsh (SURFACE_SWAMP) was plain floor.**
  SurfaceAction_Swamp: ACT_TILE_19; full-size Link only when (0,-1), (+2,0)
  and (-2,0) are all swamp; running with the boots (dash_state & $40) crosses
  it; else speed_modifier -$F0, SFX_161, sinking, and at surfaceTimer $F0
  (Minish Link at once) iframes $20, ModHealth(-4), RespawnPlayer; a swamp
  tile is no safe spot (gUnk_0811C268).  Castor Wilds could be walked without
  the boots.  New `Swamp46.lua` (wraps Dungeon.checkFall / unsafeAt and
  Player.walk).  SIMPLIFIED: the sinking sprite offset, OBJECT_70 and
  FX_GREEN_SPLASH are not drawn.
- Bot / harness issues (not port bugs): **the runtime harness ran on a stale
  version-18 import** (`r27b/appdata/LOVE/tmc_bugs1/.../generated`, Nov 11:
  room properties only up to $0F, so the ranch's east Minish entrance (paramB
  $1000: property $10) found no exit; the game tables came from TMC_DEV_ROM).
  It is now a copy of the version-33 `tmc/cache` (the old one kept as
  `generated_v18`).  Round 45's "Syrup across the pond" was the wrong side;
  the bush line in Lake Hylia's west part is not the way (it ends at the
  rock's hole); go25 does not move Link on the frame he enters a room at its
  border (a line42 step first); `H.travel` stalled from the town's north
  entrance to Rem's shop (the door (376,528) is walked to directly); Rem is
  spoken to across his desk from (104,100); a dash onto the marsh's edge at
  row 39 bounces (row 41 is the open edge).
- [ ] Left: **Castor Wilds -> Wind Ruins**: the Ruins entrance is the south-west
  border behind script_CastorWildsStatueRock (40,936), which breaks once the
  three statues are fused with Gold Kinstones (chests in Castor Wilds / its
  caves, one behind a Darknut, the Bow from the north-west); the three items
  at (984,616..680) are sunken (kind 8: diving).  So no Wind Ruins or Fortress
  of Winds this round.  Kinstone chest 2 ($50:10) and the Fortress part of
  Natives40 not reached.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r46_test.lua` (34 checks: the ranch / ranch house /
  lake room code, PlayerSetNormalAndCollide, the priority natives, the
  Goron's animation, SurfaceAction_Swamp: the slow-down, the sinking time,
  the boots, Minish, the edge probes, z, the safe-spot rule, the speed).
- **Final check:** all 78 `tests/zelda_tmc_*_test.lua` pass (`r46/out_tests.txt`);
  harness cache rebuilt at 33, room audit 605 / 605, 0 mismatching
  (`r46/out_a_rooms.txt`).  Checkpoints in `r46/ck`: `r46_a_stump`,
  `r46_b_west`, `r46_c_key`, `r46_c_out`, `r46_d_inlock`, `r46_d_east`,
  `r46_e_lake`, `r46_g_plateau`, `r46_h_sprouts`, `r46_i_lane`, `r46_i_lake`,
  `r46_j_woods`, `r46_k_hut`, `r46_l_mushroom`, `r46_m_rock`, `r46_n_shop`,
  `r46_o_boots`, `r46_p_castor`, **`r46_q_marsh`** (latest).

## Round 47

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r47/` (`go.sh` / `scene.sh` =
round 46's runner with `pre47.lua` (checkpoints and `.cart` files in `r47/ck`,
falling back to r46 .. r38); `lib47b.lua` (doors, `H.goDry47` off the marsh,
`H.gear47`, `H.dash47`, `H.darknut47`), `lib47c.lua` (`H.bfs47`: bfs25 with
one-way ledges, `H.follow47`, `H.bridge47` for the diagonal bridges,
`H.cut47`, `H.pic47`); segments `seg_a47` .. `seg_k47`; probes `probe_a` ..
`probe_r`; `tools/roomcode.py` (Thumb disassembly of a room's code pointers
from the player's ROM); `README.txt`; `tests.sh`, `check47.sh`).  Outputs
`r27b/out_r47_*.txt`, shots `r27b/shots/*`.  **Cache version: still 33** (no
import change; the real-app cache is the v33 copy).

- [x] **Re-verification on the v33 import (real app, real keys)**: Cave of
  Flames cart ride (`r42_b_lever` -> seg_c42) pass; the lava platforms 6 -> 10
  (`r43_f_pots` -> seg_g43) pass; **Gleerok** with real hearts and the Fire
  Element + heart container (`r43_r_boss` -> seg_s43 + seg_t43) pass; Melari's
  **White Sword** (`r44_a_mines` -> seg_b44) pass; the Trilby heavy block with a
  clone (`r45_a_cave` -> seg_b45) pass.  No failure, so no fix needed.
- [x] **Route with real keys** (checkpoints in `r47/ck`, hearts refilled on
  each load): `r46_q_marsh` -> A west along y 624 into the meadow
  (`r47_a_meadow`), the centre door (424,418) -> $2A:03 (`r47_a_2a03`) -> B its
  stairs -> $2B:01 (`r47_b_2b01`) -> C the north door -> $2B:00: **the Darknut**
  (sub_unk3_CastorDarknut_Main's list: OBJECT_69 script $0800B17C shuts the
  door and brings it) beaten with the sword from its side, flag $39, the chest
  spawner's chest: **Gold Kinstone (piece $6C)** (`r47_c_darknut`,
  `r47_c_gold1`) -> D back out (`r47_d_castor`) -> K the dry middle -> E plateau
  B's stairs (630,600), the B-A and A-T bridges, the top lane, door (584,50) ->
  $2A:01's west half (`r47_e_plateauA`, `r47_e_2a01`) -> H out, boots dashes
  over the north-west marsh (west at y 182, down to y 269, west to x 85, up)
  (`r47_h_nw`), the stump (150,190): Minish (`r47_h_minish`) -> I the Minish
  puddle (40,176) -> $11:01, a lily pad blown north with the Gust Jar, out at
  (40,104) (`r47_i_puddle`, `r47_i_north`) -> J the crack (40,72) -> $27:06:
  the managers' five Mulldozers beaten, the big chest: **the Bow**
  (`r47_j_crack`, `r47_j_beaten`, **`r47_j_bow`**, latest).  K..J ran as one
  chain from `r47_d_castor` (`out_r47_chain.txt`), so `r47_j_bow` holds piece
  $6C and the Bow.  (`r47_g_platC` is a side branch from `r46_q_marsh`.)
- [x] **Port gap fixed: Castor Wilds' caves / Wind Ruins had no room code.**
  Read from the ROM's gAreaTable code pointers ([6] sub_unk3, [7]
  sub_StateChange; callees CheckLocalFlag $0807CBD0, CheckGlobalFlag
  $0807CC30, SetLocalFlag $0807CCB4, GetInventoryValue $0807CA84,
  CheckKinstoneFused $0801E7F4, LoadRoomEntityList $0804ADDC):
  $2B:00 not local $39 -> list 0 replaced by gUnk_080DA230 (without it the
  Darknut never came, flag $39 was never set and the Gold Kinstone chest could
  not appear); $27:06 no Bow -> gUnk_080DCB10 (the Mulldozer fight that opens
  the Bow's chest); $05:00 SetLocalFlag($24); $05:02 KINSTONE_41 ->
  gUnk_080DDE88; $05:04 global 4 and not local 3 -> gUnk_080DE008; $05:05
  local $30 / $31 lists.  New `Story47.lua` (an R27A module).  SIMPLIFIED:
  sub_080300E8 (the Wind Ruins' stored respawn spot) and $25:05's state
  change are not ported.
- Bot / harness issues (not port bugs): round 46 left the boots on B, the
  sword's slot (`H.swordKey` pressed the boots: Link "fought" a Rope with
  dashes); bfs25 ignored one-way ledges and treated empty top-layer cells as
  open (`H.bfs47`); go25 cannot take the diagonal bridges (two keys held:
  `H.bridge47`); the sword cannot hurt a flying Peahat (left alone); the
  Darknut faces 0..3, not 0..6; the first lily pad in the list is not the one
  under Link; a dash right after a bounce does not start; the door approach
  must be straight (go25 slid past the door tile onto the stairs above).
- [ ] Left: Gold Kinstone pieces $6A (the chest in $2A:01's **east** half, door
  (648,50): no path found from the top lane) and $6B ($2A:00, door (728,898) in
  the pocket under plateau D); the four Eyegores ($2B, flag 0: asleep until an
  arrow hits the eye) sit at (352,668) -- on the C-west bridge's end --
  (400,140), (624,876) and (960,328), so the way on is most likely the Bow
  against them (not tried).  Open question: an asleep flag-0 Eyegore keeps
  its collision on in the port (Init only turns it off with a flag) and hurt
  Link for 4 when he pressed against it; not checked against the cartridge.
  Statues not fused, Wind Ruins / Fortress of Winds not reached; Kinstone
  chest 2 ($50:10), the Fortress part of Natives40 and the swamp's sinking /
  splash drawing not done.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r47_test.lua` (19 checks: Story47's six rooms, and
  the ROM's own room code -- the [6] / [7] pointers, flag immediates, literal
  pools and gUnk_080DA230's entries -- read back).
- **Final check:** all 79 `tests/zelda_tmc_*_test.lua` pass (`r47/out_tests.txt`);
  harness cache rebuilt at 33, room audit 605 / 605, 0 mismatching
  (`r47/out_a_rooms.txt`).  Checkpoints in `r47/ck`: `r47_a_meadow`,
  `r47_a_2a03`, `r47_b_2b01`, `r47_c_darknut`, `r47_c_gold1`, `r47_d_castor`,
  `r47_e_plateauA`, `r47_e_2a01`, `r47_g_platC`, `r47_h_nw`, `r47_h_minish`,
  `r47_i_puddle`, `r47_i_north`, `r47_j_crack`, `r47_j_beaten`,
  **`r47_j_bow`** (latest).

## Round 48

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r48/` (`go.sh` / `scene.sh` =
round 47's runner with `pre48.lua` (checkpoints and `.cart` files in `r48/ck`,
falling back to r47 .. r38); `lib48.lua` (`H.eyegore48b` the Bow on an Eyegore's
eye from any side, `H.plan48` / `H.go48` plans over dry ground, grass, bushes
and the marsh with boots dashes, `H.via48`, `H.fuse48`, an `H.open24` hook
keeping planners off live Eyegores); segments `seg_a48` .. `seg_o48`; probes
`probe_a` .. `probe_z`; `tools/exits.lua`, `tools/rooms.lua`; `README.txt`;
`tests.sh`, `check48.sh`).  Outputs `r27b/out_r48_*.txt`, shots `r27b/shots/*`.
**Cache version: still 33** (no import change; the real-app cache is the v33
copy).

- [x] **The sleeping Eyegore's collision (goal 1): the port matches the
  cartridge, nothing changed.**  eyegore.c Eyegore_Init clears ENT_COLLIDE
  only when its flag is non-zero; the four Castor Wilds Eyegores have flag 0
  (paramB low half), so asleep (action 1) they keep their collision -- the
  enemy definition's collision bit is set (read from the ROM), hitType 5
  against Link's hurtType gives CollisionDefault with tgtDamage 4 in
  gCollisionMtx, and the definition hitbox (0,-7, 8 x 7) pokes out of the
  2 x 2 SPECIAL_TILE_34 block on its south side.  So pressing against one
  costs 4 per touch on the cartridge too.  (Collision is off only in actions
  2-3 (sub_08031320 after an eye hit, until the wake animation ends) and 6.)
- [x] **Route with real keys** (checkpoints in `r48/ck`, hearts refilled on each
  load; one item chain from `r47_j_bow`): A $27:06's ladder out (Minish), the
  puddle $11:01 and its south lily pad, grown at the stump (`r48_a_out`,
  `r48_a_south`, `r48_a_grown`) -> B four dashes back over the north-west
  marsh, the T-A-B bridges to the dry middle (`r48_b_marsh`, `r48_b_middle`)
  -> C **Eyegore E (960,332) shot in the eye with the Bow** (10 arrows, wakes,
  3 hits) (`r48_c_eyeE`) -> D in the same run (a reload brings every Eyegore
  back, as the room's lists do): its lane north, two dashes over the north-east
  marsh, the dry strip east of plateau T, door (648,50) -> $2A:01's east half:
  **Gold Kinstone 6A** (`r48_d_nemarsh`, `r48_d_strip`, `r48_d_2a01e`,
  `r48_d_gold6a`) -> E the strip's way out: **the pushable rock (696,328)
  pushed south into its hole (696,344)** (a one-way shortcut like the ranch's),
  the bridges to plateau C (`r48_e_rock`, `r48_e_platC`) -> F **Eyegore C
  shot**, the C-west bridge, the west plateau's chest (Kinstone $74)
  (`r48_f_westplat`, `r48_f_chest`) -> G the west plateau's north ledge, the
  south-west marsh (dashes) to the bottom lowland (`r48_g_westlow`,
  `r48_g_dry`, `r48_g_bottom`) -> I **the Cane of Pacci into the pocket's hole
  (680,920)**, Link steps in facing east and springs over the rock and the
  bush (sub_0807A2F8: two tiles) into the pocket, door (728,898) -> $2A:00
  (`r48_i_pocket`, `r48_i_2a00`) -> J two Ropes, the chest: **Gold Kinstone
  6B** (`r48_j_gold6b`) -> K the pocket's rock pushed west into its hole (the
  way back) (`r48_k_rock`) -> L the three statues (64/112/160, 852) fused with
  L (6C, 6B, 6A fit fusers 8, 7, 6): **script_CastorWildsStatueRock's rock
  (40,936) breaks** (`r48_l_statues`, `r48_l_fused`) -> M the south border:
  **the Wind Ruins** $05:00 (`r48_m_ruins`) -> N the Armos in the gap
  (120,232) woken and beaten, the stairs (40,335) to the lower level
  (`r48_n_armos`, **`r48_n_lower`**, latest).  Side branch: H Eyegore SE
  (624,876) shot and the vine (632,~835) up onto plateau SE (`r48_h_platSE`)
  -- not the way into the pocket (the cave's top ledge is on the top layer;
  the bridge foot's ACT $09 puts Link on layer 1, as CheckOnLayerTransition
  does).
- [x] **Port bug fixed: arrows missed enemies whose hitbox is offset.**
  PlayerItemBow's arrow tested a 10 px box round the enemy's feet; an
  Eyegore's awake hitbox (gUnk_080FD308, read from the ROM: 0,-12, 8 x 8) sits
  over its eye, and Eyegore_OnCollision takes an east / west arrow only with
  Link's y in [y-20, y-4] -- every arrow from its side missed, so an awake
  Eyegore could not be beaten from the sides it turns to.  Now IsColliding
  (collision.c): the enemy's hitbox (offset + half sizes) against the arrow's
  4 x 6 / 6 x 4 box; no hitbox: the old box.  `ItemBow.lua` (`M.collide`
  exported for the test).
- [x] **Port bug fixed: a woken Armos froze in action 4.**  Armos_Init left the
  direction unset; an Armos whose chase (sub_080306C4) goes straight to action
  4 (back to a tile centre, sub_080305BC) did `bxor(nil, ..)` every frame (the
  field loop swallowed the error) and stood still, blocking the Wind Ruins'
  gap.  The cartridge's direction is an entity field, 0 until set: init sets
  0.  `EnemyFoW.lua`.
- Bot / harness issues (not port bugs): fusing is L (`q`), not R (R only
  sets interactType 1; ScriptCommand_0807EA4C waits for INTERACTION_FUSE);
  `$27:06` is left by its ladder (152,36); the stump approach from the puddle's
  south exit must keep south of the warp (y 212); grass with ACT $14 that
  Link stands in is walkable (not a cut); a plan's dry run ending at Link's
  cell must not be repeated; dashes need lining up on the plan's row (a
  2 px offset bounced off a corner); planners walked into a sleeping Eyegore
  and lost 32-40 hearts (avoid hook); the first Eyegore fights stood too close
  south of it (it hops onto Link); `r48_c_eyeEdead` is not a usable
  checkpoint (the Eyegore is back after a load).
- [ ] Left: the Wind Ruins' lower level -- the second Armos (136,408) did not
  wake when Link pushed it from the south (not checked against the decomp:
  its form / aWakes rule), so $05:03 .. $05:05 and the Fortress of Winds
  ($05:04's north edge -> $18:00) are not reached; Eyegore T (400,140) not
  fought (not on the way).  Kinstone chest 2 ($50:10), the Fortress part of
  Natives40 and the swamp's sinking / splash drawing not done.  Link's tile
  box not changed.
- Tests: `tests/zelda_tmc_r48_test.lua` (12 checks: the arrow against the ROM's
  awake Eyegore hitbox from the side / below / far, iframes, no-hitbox
  fallback; Eyegore_Init's collision by flag; Armos_Init's direction and
  action 4 running).
- **Final check:** all 80 `tests/zelda_tmc_*_test.lua` pass (`r48/out_tests.txt`);
  harness cache rebuilt at 33, room audit 605 / 605, 0 mismatching
  (`r48/out_a_rooms.txt`).  Checkpoints in `r48/ck`: `r48_a_out`,
  `r48_a_south`, `r48_a_grown`, `r48_b_marsh`, `r48_b_middle`, `r48_c_eyeE`,
  `r48_c_eyeEdead`, `r48_d_nemarsh`, `r48_d_strip`, `r48_d_2a01e`,
  `r48_d_gold6a`, `r48_e_rock`, `r48_e_platC`, `r48_f_westplat`,
  `r48_f_chest`, `r48_g_westlow`, `r48_g_dry`, `r48_g_bottom`,
  `r48_h_platSE`, `r48_i_pocket`, `r48_i_2a00`, `r48_j_gold6b`, `r48_k_rock`,
  `r48_l_statues`, `r48_l_fused`, `r48_m_ruins`, `r48_n_armos`,
  **`r48_n_lower`** (latest).

## Round 49

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r49/` (`go.sh` / `scene.sh` =
round 48's runner with `pre49.lua` (checkpoints and `.cart` files in `r49/ck`,
falling back to r48 .. r38); `lib49.lua` (harness-only `.armos` / `.rmem` files
beside a checkpoint: armos_data and the room tracker of the session it was taken
in), `lib49b.lua` (`H.armosTrip49`: one Armos-interior round trip with real keys;
`H.lanes49`: axis moves for Minish lanes); segments `seg_a49` .. `seg_p49`;
probes `probe_a` .. `probe_q`; `sweep49.lua`; `decomp/` (zeldaret tmc sources,
read only); `README.txt`; `tests.sh`, `check49.sh`).  Outputs
`r27b/out_r49_*.txt`, shots `r27b/shots/*`.  **Cache version: 34** (manifest.r26b
gains the Wind Ruins' Armos transitions); the harness cache and the real-app
cache (`r27b/appdata/LOVE/tmc_bugs1`) were rebuilt / refreshed at 34.

- [x] **The second Armos (136,408): the port did what armos.c says, but the way
  to wake it was missing.**  It is slot 1 (paramB byte 1 = timer); Armos_Init
  gives it unk_84 = (0x47D >> 1) & 1 = 0, and sub_0803030C never wakes an Armos
  whose bit is 0 -- pushing it from any side does nothing on the cartridge
  either.  The bit is set from inside: Minish Link walks in under it
  (sub_0803086C; its type2 room property $B is a Transition into $2C:01), hits
  the HITTABLE_LEVER (AMOS_01_00 = FLAG_BANK_3 + $68), comes back out under it
  (sub_080300E8), grows at the stump and touches it.  Three port gaps stopped
  that, all fixed (below).
- [x] **Port gap fixed: the Wind Ruins' Armos had no Minish entrance.**
  EnemyFoW read Armos transitions only from FoW's range; the Ruins' ($05:00
  props $A / $B, $05:04 prop 8, $05:05 props 8..$B -> $2C:00..07) are now read
  from the ROM at import (`EnemyFoW.ROM_RANGES` ruinsArmosTransitions0/4/5).
- [x] **Port gap fixed: armos_data's round trip** (new `Armos49.lua`, an R27A
  module): sub_080300C4 (no pending Minish entrance -> bits and places cleared;
  before, they were never cleared), Armos_SetFlagFromTransition in $2C:n,
  ArmosInteriorManager's bit following AMOS_00_00 + n every frame,
  sub_080300E8 in $05:00 / $05:04 / $05:05 / $58:02 / $58:04 (Link put at the
  Armos + (0, $C)).
- [x] **Port bug fixed: wrong flag bank.**  gLocalFlagBanks (`Field.BANK_OFFSET`)
  is indexed by LOCAL_BANK_n with LOCAL_BANK_G = 0; Armos37 read entry 3
  (FLAG_BANK_2) for FLAG_BANK_3, so the interiors' lever never lit the room or
  reached the Armos; R34 read entry 10 (FLAG_BANK_9) for LV6_KANE_START
  (FLAG_BANK_10; its test had the same off-by-one and is corrected).
- [x] **Port gap fixed: the room tracker** (new `RoomMemory49.lua`;
  code_08049CD4.c, room.c sub_0804B058, enemyUtils.c EnemyDisableRespawn): the
  eight most recent rooms keep a bit per beaten enemy of the room's property-2
  list; the port respawned them on every visit (a trip into an Armos and back
  brought the Tektites back).  ClearRoomMemory = a fresh field (new game /
  continue).
- [x] **Robustness (goal 2): one object's error no longer stops the game**
  (new `ObjErrors49.lua`; one line each in Field's entity loop and
  Dungeon:update, `Dungeon:updateObject49` split out).  In the real runtime
  (game.opts.host set) each enemy / dungeon object / manager update runs
  guarded; each distinct error is logged once (what, kind, id, form, x / y,
  room, traceback) to Game:log and the host's warning log and kept in
  `f.objErrors` with a repeat count; the object is skipped for that frame.
  Without a host (unit tests) or with TMC_STRICT_ERRORS errors are raised as
  before.  (Round 48's Armos error reached Host:_call, which ends the game on
  the error screen -- the harness kept running, so it looked "swallowed".)
  Checked: probe_q (a forced enemy error in the real app: logged once, 60
  frames went on); **sweep (`sweep49.lua`): all 617 manifest rooms entered
  from `r49_n_1800`, 60 frames each: 0 per-object errors, 0 runtime errors**;
  no object error in any route run of the round.
- [x] **Route with real keys** (checkpoints in `r49/ck`): A $05:00's two
  Tektites, the stump (56,477): Minish, under the second Armos -> $2C:01
  (`r49_a_minish`, `r49_a_2c01`) -> B the lever, back out under it
  (`r49_b_switch`, `r49_b_out`) -> C grown, the Armos touched and beaten
  (`r49_c_grown`, `r49_c_armos2`) -> D the east exit (y 492) -> $05:03
  (`r49_d_0503`) -> E its Tektites, the ladder -> $05:02 (`r49_e_0502`) -> G its
  three Tektites: FIGHT_MANAGER -> local $27 -> MISC_MANAGER 9 opens the ring
  at (88,40), the ladder -> $05:01 (`r49_g_open`, `r49_g_0501`) -> H the stairs,
  east -> $05:04 (`r49_h_0504`) -> J the Armos in its west gap (168,152, slot 7)
  the same way through $2C:07 (Minish lanes round the tall grass)
  (`r49_j_minish`, `r49_j_out`, `r49_j_beaten`) -> K the gap, the corridor ->
  $05:05 (`r49_k_0505`) -> L its three Armos: fight D -> room flag 0 ->
  SECRET_MANAGER local $32 -> CAMERA_TARGET $30 (the gate by the chest)
  (`r49_l_fight`) -> M out and back, **the running Armos (slot 2) switched OFF
  in $2C:02** (its lever starts ON because the bit came in set; OFF -> bit 0 ->
  it no longer slides into the gap (72,166)), down the gap (`r49_m_minish`,
  `r49_m_out`, `r49_m_grown`, `r49_m_gap`) -> O the moat corridor east, fight E
  (two Spiny Beetles lured out, three Ropes) -> room flag 1 -> $33 -> $31, the
  gate (448,24) -> $05:04's east half (`r49_o_moat`, `r49_o_0504e`) -> N the
  stairs, the door -> **$18:00, the Fortress of Winds** (`r49_n_1800`) -> P the
  middle door -> **inside, $58:21** (**`r49_p_fow`**, latest).
- Bot / harness issues (not port bugs): a checkpoint reload loses armos_data
  and the room tracker (`.armos` / `.rmem` added); goDry47 stopped to "fight"
  a statue Armos and walked back into its Minish entrance (`inert` while
  planning); Minish Link cannot cross tall grass (ROM collision table 1) --
  lanes from the solidity maps, or the grass cut full size first; the sword
  cannot cut the tile Link stands in; full-size Link left of x $A8 in $05:05
  makes the running Armos slide (approach the stump from x >= $A8, no fights
  there); idle41 returns at once (the secret / camera managers' delays need
  plain waits); the portal approach must check portalNear; fights on enemies
  out of reach are skipped; the rock (136,88) in $05:04 is a one-way shortcut
  from the east.  The Minish crack (56,8) in $05:03 -> $35:03 is not on the
  route (tall grass round it; `r49_f_minish` is a side branch).
- [ ] Left: inside the Fortress of Winds (keys, the Mole Mitts, Mazaal) not
  played; Kinstone chest 2 ($50:10), the Fortress part of Natives40 and the
  swamp's sinking / splash drawing not done; the guard covers enemies, dungeon
  objects and managers (entity scripts were already guarded) -- the player,
  ground items and the R27A / R27B screen modules still raise to the host.
  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r49_test.lua` (16 checks: the flag-bank index,
  armos_data clear / interior flag / bit back / Link placed, the second
  Armos' saved bit and its Transition read from the ROM, (0x47D >> 1) & 1 = 0,
  the room tracker (skip, eight rooms, reuse), ObjErrors49 once / count /
  traceback / args / strict without a host); `zelda_tmc_r34_test` corrected
  (FLAG_BANK_10).
- **Final check:** all 81 `tests/zelda_tmc_*_test.lua` pass (`r49/out_tests.txt`);
  harness cache rebuilt at 34, room audit 605 / 605, 0 mismatching
  (`r49/out_a_rooms.txt`).  Checkpoints in `r49/ck`: `r49_a_minish`,
  `r49_a_2c01`, `r49_b_switch`, `r49_b_out`, `r49_c_grown`, `r49_c_armos2`,
  `r49_d_0503`, `r49_e_0502`, `r49_f_minish`, `r49_g_open`, `r49_g_0501`,
  `r49_h_0504`, `r49_j_minish`, `r49_j_out`, `r49_j_beaten`, `r49_k_0505`,
  `r49_l_fight`, `r49_m_minish`, `r49_m_out`, `r49_m_grown`, `r49_m_gap`,
  `r49_o_moat`, `r49_o_0504e`, `r49_n_1800`, **`r49_p_fow`** (latest).

## Round 50

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r50/` (`go.sh` / `scene.sh` =
round 49's runner with `pre50.lua` (checkpoints in `r50/ck`, falling back to
r49 .. r38) and `lib50.lua` (`.cart` / `.armos` / `.rmem` from r50 then r49,
`H.pic50`, `H.inv50`); `survey50.lua` (every room of areas $58 / $18 / $59:
objects, enemies, managers, tile entities, exits -> `survey50.txt`);
`exitsA.lua`; `objerr50.lua` (prints `f.objErrors`); segments `seg_a50` ..
`seg_z50`, `seg_a2`; probes `probe_a` .. `probe_u`; `README.txt`; `tests.sh`,
`check50.sh`).  Outputs `r27b/out_r50_*.txt`, shots `r27b/shots/*`.
**Cache version: still 34** (no import change; the real-app cache stays the
v34 copy).

- [x] **The cartridge's Fortress order (decomp + ROM survey):** five 1F doors
  ($58:20 .. $58:24, the outer two reached later); the dungeon item is the
  **Mole Mitts** (big chest in $18:03, item $13); Mazaal ($58:16) gives the
  heart container and the room above ($59:00, FortressOfWindsTop_Main) sets
  LV3_CLEAR and drops the **Ocarina of Wind** (LV3_OCARINA_FALL) -- no
  Element here.  Small keys fall from FALLING_ITEM managers: $58:22 when local
  $20 is set ($58:02's lever), $58:20 when local $24 ($58:04's lever),
  $18:04 when local $65.
- [x] **Route with real keys** (checkpoints in `r50/ck`): A $58:21 stairs ->
  $58:19 -> south door -> the 2F balcony $18:01 (`r50_a_1801`) -> C back out,
  the east door $58:22, stairs -> $58:1D (`r50_c_1d`) -> D a skull lifted, the
  west chest (Kinstone) (`r50_d_chest`) -> G the Stalfos, **the west lever ->
  room flag 0 -> FLAG_AND -> local $3B opens the south shutter**
  (`r50_g_lever`) -> H $18:01 east-centre, the ladder (648) -> 3F balcony
  $18:02 (`r50_h_1801e`, `r50_h_1802`) -> I the door (744) -> **$58:02**
  (`r50_i_5802`) -> L the skulls off the clone tiles, the Armos on (200,264)
  beaten (`r50_l_clear`) -> M **the split charge on the far clone tile, Link
  to the Armos' tile, release: Link and his clone on the two held buttons ->
  local $1E opens the shutters** (`r50_m_open`) -> N the top-right portal:
  Minish (`r50_n_minish`) -> O Minish under the lever's Armos -> $2C:09, its
  lever, back out (`r50_o_2c`, `r50_o_out`) -> P through the pillar's Minish
  crack to the green portal, grown, the east-only block pushed, the Armos
  beaten, **its lever -> room flag 2 -> local $20** (`r50_p_grown`,
  `r50_p_armos`, `r50_p_lever`) -> Q back out and down to $58:22: **the
  fallen small key** (`r50_q_key`) -> R $58:19's west Eyegore (Bow), past the
  blade trap's row, **the locked door (104,24)** -> $58:12 (`r50_r_19`,
  `r50_r_door`) -> S the floating platform ridden up round the floating blocks
  (`r50_s_top`) -> T west -> $58:11 (`r50_t_11`) -> U both west eye switches
  shot -> local $28: the bridge (Wallmaster dodged) (`r50_u_bridge`) -> V
  across -> $58:10 (`r50_v_10`) -> W the region trigger, **the Darknut**,
  south -> $58:15 (`r50_w_darknut`, `r50_w_15`) -> X the blade-trap ring, the
  button, the south shutter -> $58:17 (`r50_x_south`) -> Y the top ledge east
  -> $58:18 (`r50_y_17`, `r50_y_18`) -> Z a skull thrown, **a bomb at the
  middle drawing** (the bombable-wall tile entity) -> $18:03 (`r50_z_1803`)
  -> **the big chest: the Mole Mitts** (**`r50_a2_mitts`**, latest).  Side
  finds on the way: the dungeon map ($58:19's inner-platform big chest), two
  Kinstones ($58:1D).  Chains `r50_i_5802` .. `r50_q_key` and `r50_q_key` ..
  `r50_a2_mitts` re-run in one session each: all steps pass.
- [x] **Port bug fixed: a Four Sword clone died in a one-tile corridor.**
  FourSword's clone ended (30 blinking frames, then the clones went) whenever
  the point under it was solid; PlayerClone_Action2 tests the clone's tile
  collisions (sub_080085B0, Link's own probes): all four sides full -> the
  clones go at once; one PlayerCloneCollisions pattern (a wall against one
  face) -> 30 frames; else it stays.  $58:02's clone must walk through the
  archway corridor (walls only north / south) to its button -- the port lost
  it there, so the shutters never opened.  `FourSword.lua`
  (`M.cloneCollisions`, `M.CLONE_PATTERNS`, collision.h bits).
- [x] **Port bug fixed: timed chests stayed for good.**  Chest spawner types
  1 / 7 (ChestSpawner_Type0Action3) go again once their flag clears, after
  timer * 60 frames (set when they appeared; 0 if the flag was already set at
  init): RestorePrevTileEntity, death FX; an opened chest stays.  The port
  kept the chest, so $18:01's button chest could be opened after stepping off
  the button (the cartridge needs the button held).  New `Button50.lua`,
  three hooks in `Dungeon.lua` (chestInit / updateChest).
- [x] **Port bug fixed: a held button let go at once.**  Button_Action3 / 4:
  released, the flag is cleared after 8 frames (24 while Link carries or
  pushes: heldObject 2 / field_0x35 bit 7 clear), pressed again meanwhile it
  stays down.  `Button50.held` (Dungeon:updateButton); `zelda_tmc_round3_test`
  updated to the delay.
- [x] **ObjErrors:** `objerr50.lua` after both long chains and the chest
  check: **0 per-object errors** logged.
- Bot / harness issues (not port bugs): lifting is R (`e`) facing the skull,
  and a thrown skull must leave Link's hands before he walks (state carry);
  type-2 skulls become Stalfos when Link comes near (fight them before a
  lever); reloading a checkpoint brings skulls / Stalfos back (chain the
  segments in one session); standing on a portal after growing needs one
  direction held 8 frames with input unlocked (taps never hop off), and
  single-frame taps into a portal tile jump back onto it (hold the key);
  $58:02's archway is walkable only at y 329 (its tiles' lower half);
  ladders: hold down until the climb ends before turning; the region trigger
  in $58:10 needs Link inside (136 +- 24, 144 +- 16); some arrows miss the eye
  switches -- retried; the Wallmaster in $58:11 is dodged by stepping away
  while it hangs over Link.
- [ ] Left: the rest of the Fortress after the Mole Mitts (the bridge lever +
  boots, the Wallmaster pedestal, keys 4 / 5 with the mitts, the big key,
  the warp block, Mazaal, the Ocarina of Wind) and everything after it;
  Kinstone chest 2 ($50:10), the Fortress part of Natives40, the swamp's
  sinking / splash drawing, the ObjErrors guard for the player / ground items
  not done.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r50_test.lua` (17 checks: clone collisions in open
  floor / a corridor / against a wall / boxed in, collision.h bits, the held
  button's 8 / 24-frame release and re-press, the timed chest's stay / go /
  timer * 60 / old tile back / opened stays / types 0 / 6 untouched).
- **Final check:** all 82 `tests/zelda_tmc_*_test.lua` pass (`r50/out_tests.txt`);
  harness cache rebuilt at 34, room audit 605 / 605, 0 mismatching
  (`r50/out_a_rooms.txt`).  Checkpoints in `r50/ck`: `r50_a_1801`,
  `r50_c_1d`, `r50_d_chest`, `r50_e_19`, `r50_e_eye`, `r50_g_lever`,
  `r50_h_1801e`, `r50_h_1802`, `r50_i_5802`, `r50_l_clear`, `r50_m_1c`,
  `r50_m_open`, `r50_n_minish`, `r50_o_2c`, `r50_o_out`, `r50_p_grown`,
  `r50_p_armos`, `r50_p_lever`, `r50_q_key`, `r50_r_19`, `r50_r_door`,
  `r50_s_top`, `r50_t_11`, `r50_u_bridge`, `r50_v_10`, `r50_w_darknut`,
  `r50_w_15`, `r50_x_south`, `r50_y_17`, `r50_y_18`, `r50_z_1803`,
  **`r50_a2_mitts`** (latest).

## Round 51

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r51/` (`go.sh` / `scene.sh` =
round 50's runner with `pre51.lua` (checkpoints in `r51/ck`, falling back to
r50 .. r38; `.cart` / `.armos` / `.rmem` from r51, r50, r49) and `lib51.lua`
(`H.pic51`, `H.acts51`, `H.map51` / `H.kinds51` (tile maps: soft walls, heavy
blocks, clone tiles, holes), `H.dig51` (Mole Mitts), `H.skull51`, `H.split51`
(Four Sword split with an offset), `H.push51`, `H.pull51` (statues), `H.keys51`,
`H.loc51`); `survey51.lua`; segments `seg_a51` .. `seg_s51` (+ `seg_k2_51`);
probes `probe_a` .. `probe_o`; `objerr51.lua`; `tests.sh`, `check51.sh`).
Outputs `r27b/out_r51_*.txt`, room pictures `r51/img`.  Route source: the
cartridge's own order (decomp room / object / manager data) cross-checked
with a public walkthrough's step order.  **Cache version: 35** (r35.bin
gains two small tables read from the ROM: `ItemMitts.CLOD_DUR` =
gUnk_0811BE14 and `WallMaster51.CHASE` = gUnk_080CD728; players re-import
once); the harness cache was rebuilt and the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) refreshed at 35.

- [x] **Port bug fixed: the Mole Mitts' dig froze Link for good.**
  ANIM_MOLEMITTS_DIG's dig keyframes hold 255 frames; itemMoleMitts.c
  sub_080772A8 sets `gPlayerEntity.frameDuration = 1` on the dig frame (flags
  $60) and on the end frame of a repeated dig ($10 + timer), and
  sub_080771C8 sets it to gUnk_0811BE14[subtimer] (read from the ROM) after a
  floor clod.  The port
  left the 255 in place: one press of the Mitts and Link stood in the dig pose
  for 4 s with no forward movement.  `ItemMitts.lua` (three anchored lines).
- [x] **Port bug fixed: shut doors were walked through.**  lockedDoor.c /
  bossDoor.c put SPECIAL_TILE_34 ($4022) on a shut door's doorway tile, so the
  doorway's ACT_TILE_DOOR is gone while it is shut; the port's Dungeon:block
  only made the tile solid and Field:doorExit takes a solid $29 tile for a
  door: $58:03's east shutter (two eye switches) and $58:18's west one were
  passable shut.  New `Doors51.lua` (`closedAt`), one line in
  `Field:doorExit`.
- [x] **Port bug fixed: the lever bridge never went back.**
  bridgeManager.c BridgeManager_Action1 (type2 bit 7 clear) takes the bridge
  back a tile every 8 frames while its flag is clear (RestorePrevTileEntity,
  head steps back); $58:12's bridge is held out by the PULLABLE_LEVER, whose
  flag clears once the handle is home -- the cartridge's "dash across with the
  Pegasus Boots".  The port built it and left it.  New `Bridge51.lua`
  (remember / retract), two hooks in Dungeon's bridge manager.
- [x] **Port bug fixed: a floating platform dropped Link while he used an
  item.**  PlayerCanBeMoved (playerUtils.c) is a flags test (PL_BUSY,
  PL_FALLING, PL_CLIMBING ...); the Bow, the sword, knockback and carrying set
  none of them.  FoWObjects' platform test only allowed normal / shield /
  gust, so shooting $58:03's eye switches from the moving platform left Link
  over the pit.  `FoWObjects.playerCanBeMoved` now matches CoFObjects'
  MOVABLE43 plus the Bow / Mitts ext states.
- [x] **Port gap fixed: WALL_MASTER_2 ($23, the blue floor Wallmasters) ran
  the ceiling WALL_MASTER code** -- they hung over Link at z $80 out of the
  sword's reach and $58:13's FIGHT_MANAGER never set local 42 (no Minish
  portal).  New `WallMaster51.lua` = wallMaster2.c: wander (sub_0802CD54),
  chase Link inside the home rectangle at $C0 for gUnk_080CD728[R & 3] frames
  (read from the ROM) turning one
  step every 4 frames (sub_0802CDE8), grab on body contact (OnCollision 0 / 1 /
  $1E) -> carried up -> DoExitTransition(gWallMasterScreenTransitions) (checked:
  a grab sends Link to $58:21, the entrance).  One dispatch line in
  EnemyTraps.
- [x] **Route with real keys** (checkpoints in `r51/ck`): A the Mitts dug east
  to the corner chest (100 rupees, wallet cap) in $18:03 (`r51_a_chest`) -> B
  back to $58:18's corridor (`r51_b_5818`) -> C a skull thrown, east ->
  $58:19's top-left (`r51_c_5819`) -> D two skulls, down, the centre stairs ->
  $58:21 (`r51_d_5821`) -> E $18:00 -> $58:20 -> stairs -> $58:1C
  (`r51_e_5820`, `r51_e_581C`) -> F round the pit, north -> $58:18's lower room
  (`r51_f_5818`) -> G west -> $58:17 -> south -> $18:01 (`r51_g_5817`,
  `r51_g_1801`) -> H the west ladder (296) -> $18:02 (`r51_h_1802`) -> I the
  door (104) -> **$58:03** (`r51_i_5803`) -> J the three floating platforms,
  **both east eye switches shot from the moving one -> local 34**, the shutter
  -> $58:04 west (`r51_j_5804`) -> K Ropes, eight skulls lifted, **split
  (clone 16 below), the big block pushed east to the wall** -> K2 **the lower
  block pushed west, R lets the clone go, split again (clone 16 west), the
  east block pushed north, the West Key Lever -> local 36** (`r51_k_lever`) ->
  L down the pits $58:04 -> $58:1C -> $58:20: **the small key**, -> $58:21 ->
  $58:19: the east Eyegore, **the right locked door (168,24)** -> $58:12
  (`r51_l_key`, `r51_l_19`, `r51_l_door`) -> M **the lever held out until
  the 22-tile bridge is built, let go, a Pegasus dash across before it is
  taken back** (`r51_m_top`) -> N east -> $58:13 (`r51_n_5813`) -> O **the
  three blue Wallmasters beaten -> local 42: the Minish portal**
  (`r51_o_portal`) -> P east -> $58:14 (`r51_p_5814`) -> Q the corridor
  skulls, past the spiked rollers -> the button room (`r51_q_buttons`) -> R
  **the statues pulled / pushed onto the upper-left and lower-right buttons,
  split on the bottom clone tile, walk to the top one (clone at -32, +64), the
  clone through the one-tile way, Link and clone on the last two buttons ->
  local 45: the small key falls** (`r51_r_key`) -> S back past the rollers,
  **the locked door (56,376)** -> **$58:1B** (`r51_s_581B`, latest).
- Bot / harness issues (not port bugs): a dug soft wall with a lip
  (TILE_TYPE_754, collision 3: lower half solid) is entered from y = row + 5
  (the port's box probes y + 2 on the sides, the cartridge y and y - 6 --
  Link's box is left for its own round, see Round 47); dug tiles come back on
  a reload (checkpoints after leaving the room); reloading a checkpoint inside
  $58:04 put Link on layer 2 at the wrong spot (walks through walls) -- chain
  J .. K2 from `r51_i_5803` in one session; $58:17's top corridor has no drop
  into the room (reach it through $58:18 -> $58:1C -> $58:20 / $58:18 lower);
  the H.goDry47 fight logic swings at skulls (lanes instead); statues: lean
  in 6 frames, R, pull one tile, let go; $58:14's edge row (y 272..288,
  ACT_TILE_116, top half solid) is crossed diagonally at x 208..224; the blue
  Wallmasters are fought standing still (a grab ends the run at $58:21).
- [ ] Left: the Minish route ($58:13 portal -> $58:14's arch -> the rollers'
  south door -> $58:1A -> $18:04's key with the Mitts), $18:01's Moldorm part,
  $58:02's east locked door, the big key ($58:1B from above), the warp block
  ($58:04 east), Mazaal, the heart container, $59:00 (LV3_CLEAR, the Ocarina
  of Wind) -- all ported, not yet played with real keys; Kinstone chest 2
  ($50:10), the Fortress part of Natives40, the swamp's sinking / splash
  drawing, the ObjErrors guard for the player / ground items not done.  Link's
  tile box not changed.
- Tests: `tests/zelda_tmc_r51_test.lua` (25 checks: cache version 35, the dig frames end
  (frameDuration 1) and move Link, Doors51 shut / open / gone / boss span,
  Bridge51 remember / retract order, the platform carry states, WallMaster2
  init / chase / grab / give up).
- **Final check:** all 83 `tests/zelda_tmc_*_test.lua` pass (`r51/out_tests.txt`);
  harness cache rebuilt at 35, room audit 605 / 605, 0 mismatching
  (`r51/out_a_rooms.txt`).  ObjErrors (`objerr51.lua`): **0 per-object
  errors** in the sessions J .. L and P .. S (P .. S ran clean in one session).
  After the v35 rebuild A + B and O were re-run in the real runtime on the
  refreshed cache: pass, 0 per-object errors.
  Checkpoints in `r51/ck`: `r51_a_chest`, `r51_b_5818`, `r51_c_5819`,
  `r51_d_5821`, `r51_e_5820`, `r51_e_581C`, `r51_f_5818`, `r51_g_5817`,
  `r51_g_1801`, `r51_h_1802`, `r51_i_5803`, `r51_j_5804`, `r51_k_lever`,
  `r51_l_key`, `r51_l_19`, `r51_l_door`, `r51_m_top`, `r51_n_5813`,
  `r51_o_portal`, `r51_p_5814`, `r51_q_buttons`, `r51_r_key`,
  **`r51_s_581B`** (latest).

## Round 52 (Fortress of Winds -> Mazaal phase 1)

- Route (real input, checkpoints in scratch_claude/zelda/tmc/r52/ck): r52_y_5804 ($18:01 ladder, Mitts dig to $58:04),
  r52_z_warp ($58:04 stone tile $364 pushes east only -> flag 37, warp point), r52_z_5801 (big key boss door),
  r52_a2_5816 (Mazaal room), r52_b2_hands (both hands down by arrows + sword), then Minish at the east portal stone,
  into the mouth ($5A:01), sword on the weak pillar 90 -> 60, carried out, grown back (r52_e2_phase1).
- Fix: ItemBow.collide - the Mazaal-part loop now uses the arrow's own box and the generic enemy loop skips
  Mazaal parts (e.mz); before, the generic loop consumed the arrow and the hands could never be knocked down.
- New Falling52.lua (falling items, kinds 2/3/4/0, ~64-frame fall); Player.hurt during a ledge jump.
- tests/zelda_tmc_r52_test.lua (16 checks).
- Open: Mazaal health (Field r26mazaal.f39) is not saved in checkpoints, so phases 2/3 restart at 90;
  the bot takes ~30 hearts in phase 1 and ignores the heart drop ($5E); once a hand froze in action 7 at z -81 (unconfirmed).
- Next: save r26mazaal in checkpoints, better dodging + heart pick-up, phases 2/3, heart container, $59:00 Ocarina (LV3_CLEAR).

## Round 53 (Mazaal beaten -> heart container -> the Ocarina of Wind)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r53/` (`go.sh` = round 52's runner WITHOUT FULLHP (real
health) and `pre53.lua` (checkpoints in `r53/ck`, falling back to r52 .. r38; a `.mz` side file keeps
Mazaal's gRoomTransition.field_0x38 / 0x39 (f.r26mazaal) and is put back through BossMazaal C.state before
startGame); `lib53.lua` (`H.mz53`: the hands bot with dodging -- slam lock / drop, swipe wind-up / sweep /
open hand, both-hand drops, beams, beetles -- arrow and heart pick-ups, `H.mzLog53`); segments `seg_b53`
(hands), `seg_d53` (inside: room 1 walk, room 0 dig), `seg_e53` (grown at the portal), `seg_f53`, `seg_g53` /
`seg_g2_53` (heart container, north), `seg_h53` (text board -> Ocarina), `seg_i53` (LV3_CLEAR, out);
r52's `seg_c2_52` (Minish, into the mouth) reused; probes `probe_a` .. `probe_h`; `check53.sh` (audit only)).
Outputs `r27b/out_r53_*.txt`, pictures `r53/img` (and `r52/img`).  **Cache version: 35, unchanged** (no import
change: logic only) -- no re-import, the real-app cache stays current.

- [x] **Mazaal's health across a reload:** gRoomTransition is MemClear'd at file load (game.c) and
  sub_StateChange_FortressOfWinds_BeforeMazaal sets field_0x39 = $5A on entering $58:01, so on the cartridge
  a save / game over restarts Mazaal at 90 too -- the port matches.  Only the harness needed it: `.mz` beside
  each checkpoint.  The hands are entities (not gRoomTransition), so a reload in $58:16 rebuilds both: the
  faithful checkpoints are the ones taken right after a transition (`r53_e_phase60/30`, `r53_c_inner*`).
- [x] **Not a port bug: the hand frozen in action 7 at z -81.**  mazaalBracelet.c sub_0803A6E8 clamps the
  chasing hand's y to the head's y + 8 while sub_0803B610 aims at Link.y - 12: with Link right under the head
  the target is above the clamp and the hand holds still (u8 timer wraps at 255, so it keeps turning); the
  port's action 7 / overLink / chase are line for line the same.
- [x] **Port bug fixed: a falling fist hit from too high.**  IsColliding (collision.c) passes only
  |dz| <= depth, depth 5 + 5 (no Mazaal part nor Link sets collisionFlags $10, so no Hitbox3D depth); the
  port's C.touch used 12.  `BossMazaal.lua` (one anchored line).
- [x] **Port bug fixed: the right arm's beetles spawned off the room.**  sub_0803B724 reads
  gUnk_080CFD1B[type] into a `u8 temp`: -$38 becomes $C8 (x 200..312); the port added the signed value
  (x -56..56, never reachable, counted alive for good).  `BossMazaal2.lua`.
- [x] **Port bug fixed: a broken hand's drop.**  CreateObject(GROUND_ITEM, $5E, 0) is ITEM_ARROWS5 (not a
  heart) with timer 0 = ItemOnGround kind 0 (Kindx_Init: the hop, 600 frames, then gone) and direction $90
  (south at $100); the port made a static item that never went.  `BossMazaal2.lua`.
- [x] **Port bug fixed: the Fortress top's text board never answered.**  script_Npc4EWindRuinsTextBoard
  hides its NPC (DoPostScriptAction bit 8: spriteSettings.draw = 0) and registers a box
  (NPC4E_ChangeInteractableHitbox); sub_080784E4 walks the interactable list and never looks at draw, but
  Field:tryInteract skipped hidden entities.  Now an entity with its own interactBox answers while hidden.
  `Field.lua` (anchored).  This is the "Fortress part" that blocked LV3_OCARINA_FALL.
- [x] **Phases 2 / 3 inside (ROOM_INNER_MAZAAL_MAIN, room 0):** the pillars stand in a wall of ACT_TILE_86
  Mole Mitts tiles on the bottom layer (Link enters on layer 1 at ($88,$F8), gUnk_080CED9C); the port's dig
  works as is: up the vulnerable pillar's column (bottom-row pillar) or up the next column and west (top-row
  pillar: the lower pillar blocks its own column), then the sword.  The macro starts at the list spot
  ($88,$58) and moves in its init (sub_08035084) -- read it after action 0.
- [x] **Route with real keys and real health** (checkpoints in `r53/ck`): from `r52_a2_5816` (40/40, 8
  arrows): phase 1 hands (32/40 left, 15 arrows with the drops) -> Minish, mouth, $5A:01 pillar 90 -> 60 ->
  carried out, grown (`r53_e_phase60`) -> phase 2 hands -> mouth -> $5A:00, dig, pillar 60 -> 30 -> grown
  (`r53_e_phase30`, `r53_c_inner30`) -> phase 3 hands (no damage) -> mouth -> dig to the top-row pillar,
  30 -> 0 -> script_MazaalMacroDefeated -> $58:16 (gUnk_0813ABA8), the head's death, MAZAAL_BOSS_OBJECT
  actions 7 / 8 (flag $31, the archway, the room lists) -> **the heart container (max 40 -> 48)**
  (`r53_g_heart`) -> north through the archway -> **$59:00** (`r53_g_top`): LV3_CLEAR -> the text board ->
  TEXT_VAATI -> the bird drops the Ocarina -> **the Ocarina of Wind** (windcrest bit $10000000)
  (`r53_h_ocarina`) -> south back to $58:16 (`r53_i_out`, latest).  The chain `r53_e_phase30` -> B, C, D,
  G, H ran clean in one session (`out_r53_full.txt`).
- Bot notes (not port bugs): stand in the bottom lane; on a swipe wind-up go to the far side, leave the row
  when the sweep comes, keep clear of the open hand ($14..$17); flee a slam on lock (8) / drop (9) using the
  fist's (MAZAAL_HAND) box, not the bracelet's; no shot while a hand slams or swipes.
- [ ] Left: Ezlo / the Ocarina's first play and the wind crests (next story beat toward the Temple of
  Droplets / Cloud Tops) not played; Kinstone chest 2 ($50:10), the swamp's sinking / splash drawing, the
  ObjErrors guard for player / ground items not done.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r53_test.lua` (13 checks: the z depth, the beetles' u8 x, the arrow drop's kind /
  direction / life, the hidden text board answers while a hidden NPC without a box does not).
- **Final check:** all 85 `tests/zelda_tmc_*_test.lua` pass (`r53/out_tests.txt`); room audit 605 / 605,
  0 mismatching (`r53/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-53 session.

## Round 54 (out of the Fortress -> the Ocarina's first warp -> Lake Hylia -> the Flippers quest starts)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r54/` (`go.sh` = round 53's runner (real health) with
`pre54.lua` (checkpoints in `r54/ck`, falling back to r53 .. r38) and `lib54.lua` (`H.pic54`, `H.flags54`, a
`MSG54` message-index log, `H.talk54` (tap through text), `H.edge54` (go48 to a point, hold a direction until
the room changes)); segments `seg_a54` .. `seg_r54`; probes `probe_a` .. `probe_p`; `check54.sh` (audit only);
`findscr.py` (script address search)).  Outputs `r27b/out_r54_*.txt` (`out_r54_chain.txt` = A .. H in one
session, `out_r54_chain2.txt` = I .. N + R in one session), pictures `r54/img`, shots `r27b/shots/*_c54_*` ..
`*_r54_*`.  Route source: the cartridge's scripts / room code (decomp) for the order, a walkthrough's step order
as a cross-check.  **Cache version: 35, unchanged** (no import change: the new tables are read at run time from
ranges the importer already copies -- npcData, the script region) -- no re-import, the real-app cache stays
current.

- [x] **The cartridge's way out of the Fortress:** the WARP_POINT type 2 that the beaten Mazaal leaves in $58:16
  (184,56) (warpPoint.c Action3 -> Action5 -> TRANSITION_FADE_WHITE_SLOW) -> $05:04 (Ruins_FortressEntrance);
  its state change (LV3_CLEAR, not local 3: gUnk_080DE008, script_EzloTalkFoW, already ported in Story47) ->
  TEXT_EZLO_ELEMENTS_DONE 3, local 3.  Played with real keys.
- [x] **Port gap fixed: the Ezlo talk on the first Ocarina warp.**  bird.c Bird_Type9 action 1 -> 2: global
  WARP_1ST ($52) clear -> CreateObject(CUTSCENE_ORCHESTRATOR) + StartCutscene(script_EzloTalkOcarina) +
  SetGlobalFlag(WARP_1ST).  The script (USA $0800B0AC, found by its bytes: EndBlock, SetPlayerIdle, Call
  WaitForPlayerNormalOrTalkEzlo $0807FA41, ... EzloMessage $0B5F) runs from the player's ROM.  New
  `Ocarina54.lua`, one hook line in `ItemOcarina.lua` type9 (its SIMPLIFIED note updated).
- [x] **Port bug fixed: the pause menu reopened on the map after a warp.**  Subtask_FastTravel never touches
  gPauseMenuOptions.screen (subtaskFastTravel.c); the port borrowed the pause menu's map page (screen 4) and left
  it there, so the next START opened on the map (the bot's equip went wrong).  `ItemOcarina.lua`
  openFastTravel / closeFastTravel keep and restore the page.
- [x] **Port bug fixed: a ledge jump could leave Link stuck on layer 2.**  PlayerJump's landing
  (player.c sub_08071130) calls ResetCollisionLayer ($0800455E: `strb 1, [r0, #0x38]`), not
  ResolveCollisionLayer; the port resolved the layer from the top map, and Lake Hylia's canopy tile ($164) under
  the landing spot west of the crest's plateau put Link on layer 2 inside solid top tiles -- he could not move.
  `Ledge.lua` (anchored lines).  The per-frame surface check (Layers.surface, sub_0807A8D8) still lifts him
  where the tile says.
- [x] **Port gap fixed: the Lake Hylia Minish (the Flippers quest's start).**  forestMinish.c sub_08060270
  (script_ForestMinish3, $20:27 MinishHouseInteriors_LakeHyliaOcarina) -- no Flippers: 0 + SetGlobalFlag
  (MIZUKAKI_START $29), then 1; Flippers: 2 + local $76, then 3; MessageNoOverlap(gUnk_0810A35A[i]) -- and
  sub_080601D4 (gUnk_0810A354) were missing (no text, no flag).  New `Story54.lua` (an R37 module, one line in
  `R37.lua`'s list).
- [x] **Port gap fixed: the town Minish talk** (townMinish.c sub_0806AFE8 by type2: sub_0806B004 -- the library
  bookshelf's yellow Minish, MIZUKAKI_KOBITO $6A / the books-back 50 rupees KHOUSE51_00 $78 --, sub_0806B064,
  sub_0806B098 (MIZUKAKI_HARIFALL), sub_0806B0E0 (the dust tiles), sub_0806B134 (POWERGLOVE_HINT), else
  sub_0806AFBC's dialog table $081126F0[type2][progress - 2]); script_TownMinish1 talked to nobody.
  `Story54.lua`; the tables (typeFuncs $08112BF0, the message lists $08112C40 ..) read from the ROM.
- [x] **Port gap fixed: the Flippers quest's room code** (roomInit.c): Library2F / Library1F ($21:02 / $21:03:
  the quest librarian loads with MIZUKAKI_START + KOBITO), MinishRafters_DrLeft ($2E:02), TownMinishHoles
  MayorsHouse / LibraryBookshelf (+ its sub_unk3 list-1 swap to gUnk_080DB910) / LibrariBookHouse ($2D:00 /
  $10 / $11), HouseInteriors2 DrLeft / Romio / Julietta ($22:04 / $06 / $07), HouseInteriors4 MayorLakeCabin
  ($28:05).  None was ported (no librarians at all in the library).  `Story54.lua`.
- [x] **Port gap fixed: BOOK ($8C, book.c)** -- the three library books: type2 0 on a shelf (Minish Link pushes
  it south twice, 22 frames each, then it falls $20 with BounceUpdate(40) and sets its flag), 1 falling in,
  2 on the floor (touch: ITEM_QST_BOOK1 + type), 3 the library's copy (shown once returned).  `Story54.lua`
  (not yet met with real keys).
- [x] **Port gap fixed: the jar portal's flip** (jarPortal.c Action1/3 -> 2/4: the Cane of Pacci's contact $1D,
  the local flag `type` set / cleared by unk_7c, the hop with GravityUpdate(Q_8_8(32)), animations 2 / 3,
  standing = portal).  Round 45 left it out.  New `Jar54.lua`, one line in `Jar45.lua` (onPacciObj).  The library
  yard's jar (368,62) is flipped with real keys and used.
- [x] **Route with real keys and real health** (checkpoints in `r54/ck`; A .. H re-run in one session after all
  fixes, I .. N + R in another): from `r53_i_out` -> A the warp point -> $05:04 (`r54_a_out`) -> B Ezlo
  (`r54_b_ezlo`) -> C the Ocarina from the B button: Zeffa, the fast-travel map, Lake Hylia, **Ezlo's first-warp
  talk** (`r54_c_lake`) -> D the stump portal (184,496), Minish, the house by the crest $20:27 (`r54_d_house`)
  -> E the Lake Hylia Minish: **MIZUKAKI_START** (`r54_e_start`) -> F grown back at the stump (`r54_f_big`) ->
  G the sword cuts the plateau's west bushes, the west ledge (`r54_g_off`) -> H west edge -> Lon Lon Ranch's
  east part $03:05 (`r54_h_west`) -> I Talon's house east door $28:03 (`r54_i_2803`) -> J the inner archway,
  $28:02, out its door into the pen (`r54_j_pen`) -> K west edge (y 132..184) -> north Hyrule Field $03:06
  (`r54_k_0306`) -> L south edge -> **Hyrule Town** (`r54_l_town`) -> M the library $21:03 (`r54_m_lib`) -> N
  its stairs -> Library2F (`r54_n_lib2`) -> R its south door, the yard, **the Cane of Pacci flips the jar**,
  onto it, R: Minish (`r54_r_minish`, latest).  Side checkpoint: `r54_p_minish` (Minish through Rem's jar, a
  dead end: Minish Link cannot use a house door).
- Bot / harness notes (not port bugs): the stump portal's R must wait for the jump onto it to land; the plateau
  of the Lake Hylia crest is left by cutting the bushes at x 136 (row 472) and jumping the west ledge (ACT $2D);
  the library yard's stairs ($52, collision $61) are open only to Minish Link (right half); from $03:05 the
  west edge is open at y 132..184 only; Minish Link through a NORMAL door transition comes out full size
  (DoExitTransition: spawn_type = transition_type), so the Minish way into Library2F is not the 2F door.
- [ ] Left: **the Minish way into Library2F** (its bookshelf region (72,52) -> $2D:10, where the yellow Minish
  sets MIZUKAKI_KOBITO); candidates: the yard's west Minish entrance (props[$E] minish_entrance (292,80) --
  possibly Kinstone-made), the town Minish caves ($62:15 from (224,82)).  Then the librarian (HINT1) and the
  three books (Julietta's shelf $22:07, Dr. Left's rafters $2E:02 / $22:04, the Mayor's lake cabin $28:05),
  Librari's trap door, the Flippers ($62:10), the Temple of Droplets.  Kinstone chest 2 ($50:10), the swamp's
  splash drawing, the ObjErrors guard for player / ground items not done.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r54_test.lua` (39 checks: the ledge landing layer, script_EzloTalkOcarina's bytes and
  the one-time talk, the fast-travel page restore, sub_08060270 / sub_080601D4 / sub_0806B004 / B098 / B134,
  the townMinish tables, the room code lists, BOOK init / push test, the jar flip and its portal).
- **Final check:** all 86 `tests/zelda_tmc_*_test.lua` pass (`r54/out_tests.txt`); room audit 605 / 605,
  0 mismatching (`r54/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-54 session.

## Round 55 (the Minish way into the library -> the bookshelf Minish -> the librarian -> book 1 returned)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r55/` (`go.sh` = round 54's runner with `pre55.lua` (checkpoints in
`r55/ck`, falling back to r54 .. r38) and `lib55.lua` (`H.pic55`, `H.ents55`, a Minish-aware `H.open24` (Link's own
box and collision table, so go48's BFS plans Minish routes right), `H.route55` (lanes with sidesteps)); `run.sh` (waits
for no LOVE, then go.sh); segments `seg_a55` .. `seg_k55`; probes `probe_a`, `probe_grid`, `seg_p55` (flood fills,
collision dumps); `check55.sh` (audit only)).  Outputs `r27b/out_r55_*.txt` (`out_r55_ij.txt` = I + J in one session),
pictures `r55/img`, shots `r27b/shots/*_a55_*` .. `*_k55_*`.  Route source: the decomp's room data (transitions.c,
entity_headers.s, roomInit.c) for the way in; a walkthrough's step order for the books (Romio's fireplace, the
plank, Julietta's shelf).  **Cache version: 35, unchanged** (no import change: the extra room properties are read at
run time from the entity region the importer already copies) -- no re-import, the real-app cache stays current.

- [x] **Solved: the Minish way into Library 2F.**  Hyrule Town's entity list 1 has MINISH_SIZED_ENTRANCE_MANAGER
  ($21, paramA $E); room property $E is a list of MinishEntranceSpawnData {x, y, cond, timer}; its first entry
  (292, 80) beside the yard's Minish stairs spawns a MINISH_SIZED_ENTRANCE whose exit (property $20) is Library 2F
  (0x48, 0x8E), TRANSITION_TYPE_INSTANT_MINISH.  Not Kinstone-made (cond 0 = always).  In 2F, SPECIAL_WARP_MANAGER
  (paramA 9) takes Minish Link from (0x48, 0x34) into the bookshelf $2D:10 (a NORMAL transition: the Minish-scale room,
  Link drawn full size there, as on the cartridge); 2F's own Minish hole (0x48, 0x90, DOWN, property 8) leads back to
  the yard (292, 84).  The town Minish caves ($62) are not the way (their exits stay in the north-west part).
- [x] **Port gap fixed: MINISH_SIZED_ENTRANCE_MANAGER** (minishSizedEntranceManager.c: CheckRectOnScreen
  $0800290E, sub_0805B8CC's conditions (4 = TATEKAKE_HOUSE, 5 / 6 never), one object per entry while on screen, the
  bit cleared off screen, the type-1 object deleted with its bit).  New `Entrance55.lua` (R37 list, one line).
- [x] **Port gap fixed: room properties past 31.**  The importer keeps properties 8 .. 31 (Extract.lua); Hyrule
  Town's header runs to $2F+ (the hole exits are $20 .. $2C).  `Entrance55.extendProps` finds the room header in the
  entity region by its words 8 .. 15 and reads the rest from the player's ROM (no cache change).
- [x] **Port bug fixed: CheckPlayerInRegion's edges** ($0800293E: `(u32)(cx - (px - w)) < 2w`, px in (cx - w, cx + w]);
  `Field:playerInRegion` used `|px - cx| < w`, which left out the far edge -- Minish Link on Romio's roof (y $2BE)
  could never enter Julietta's chimney region (0x352, 0x2BC) +-(8, 2).  `Field.lua` (anchored).
- [x] **Port bug fixed: object / enemy layer in the merged-top interiors.**  LoadRoomEntity (room.c) gives layer 1
  without ResolveCollisionLayer when gRoomControls.scroll_flags & 2 (Room.MERGE_TOP_AREAS: $21 .. $25, $27, $28 ...);
  the port resolved it, so Romio's FIREPLACE ($8D) put its SPECIAL_TILE_97 on layer 2 and the bottle's water (layer 1)
  never put it out.  `Dungeon.lua` spawnObject / `Field.lua` enemy spawn (anchored).
- [x] **Port gap fixed: HUGE_BOOK $88** (macroBook.c, Dr. Left's rafters; not yet met with real keys): the weight
  count (the rafters Minish type2 8, Link in the $20 x $22 rect, the first clone; x <= $15A), the 4 x 5 tiles
  (SPECIAL_TILE_116 / 34) and their restore, actions 1 .. 3 by the frame flags ($20: MIZUKAKI_HARIFALL, the slide;
  $40: tiles back; $80 + frameDuration 0: gone); townMinish.c sub_0806AF70 / AF78 (the Minish hopping off).  New
  `Story55.lua` (R37 list, one line).  SIMPLIFIED: SetPlayerControl($FF), the affine growth and the 1 / 2 px nudges.
- [x] **ObjErrors guard extended:** the player's update and the ground / thrown items now run through
  ObjErrors49.call (`Field.lua`, three anchored lines).
- [x] **Route with real keys and real health** (checkpoints in `r55/ck`): from `r54_r_minish` -> A the Minish hole
  (292, 80) -> Library 2F as Minish (`r55_a_lib2m`) -> B the 2F region -> the bookshelf $2D:10 (`r55_b_shelf`) -> C the
  left end up onto the low shelf, the yellow Minish: **MIZUKAKI_KOBITO** (`r55_c_kobito`) -> D out through the bookshelf
  (back to 2F Minish), 2F's Minish hole to the yard, grown on the jar (PortalStand: hop off south), the 2F door, the
  stairs, **the librarian's hint** (TEXT_LIBRARY 1, local $6B) (`r55_d_hint`) -> P out to town (`r55_p_town`) -> G the
  fairy let out, water from the river (an empty bottle's swing), Romio's door (`r55_g_water`) -> H water on the fireplace
  (flag $85), the Cane of Pacci flips Romio's jar, shrink (`r55_h_minish`) -> F up the cold fireplace onto the roof,
  east over the plank, down Julietta's chimney (`r55_f_jul`) -> I up the Minish ladder, the book pushed off the shelf
  (`r55_i_book1`) -> J back up her chimney, west over the plank, down Romio's, grown on his jar, out of his door, into
  Julietta's: **ITEM_QST_BOOK1** (`r55_j_book1`) -> K the library: **book 1 returned** (BOOK1 = 2) (`r55_k_ret1`, latest).
- Bot / harness notes (not port bugs): Minish Link can't climb the town's road curbs (collision $5F is solid only in his
  table), so the town splits into Minish-unreachable parts (flood fill: `r55/img/fill55s.png`) -- the cartridge's way
  to the south-east houses is through the houses (portals, chimneys); Minish Link can't reach Julietta's door; Minish
  Link can't take the library's 2F stairs (he is stopped at y 34); a checkpoint taken right after the book push
  (`r55_i_book1`) reloads Link inside the shelf -- run I + J in one session.
- [ ] Left: books 2 and 3 (Dr. Left: the café vase, his fireplace, the chimney / roof / yellow house, the cabinets,
  the rafters' dust (Gust Jar, ACT_TILE_87 clone tiles), the split, the HUGE_BOOK; the Mayor's book: his wall masks
  (Pegasus Boots), the Minish Woods tree portal, the cabin's Minish path and lily pad), Librari's trap door, the
  Flippers, the Temple of Droplets.  Kinstone chest 2 ($50:10), the swamp's splash drawing not done.  Open question:
  the bottle's water probe facing left (hflip negates dx; the down swing caught water at the same bank) -- not proven
  either way.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r55_test.lua` (37 checks: the extra room properties from the ROM header, hole exit $20,
  the 10 town holes and their conditions, CheckRectOnScreen's edges, the manager's spawn / bit, HUGE_BOOK's count,
  tiles, actions and flags, sub_0806AF70 / AF78).
- **Final check:** all 87 `tests/zelda_tmc_*_test.lua` pass (`r55/out_tests.txt`); room audit 605 / 605, 0 mismatching
  (`r55/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-55 session.

## Round 56 (Flippers quest, book 2: the cafe portal -> Dr. Left's house -> his fire out -> his roof -> the yellow house)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r56/` (`run.sh` / `go.sh` = round 55's runner with `pre56.lua`
(checkpoints in `r56/ck`, falling back to r55 .. r38) and `lib56.lua` (`H.pic56`, `H.fill56` / `H.has56` (Minish-aware
flood fill), `H.avoid56` (planner keeps off chosen NPCs), `H.path56` (BFS on 4 px cells walked as lanes)); segments
`seg_a56` .. `seg_h56`; probes `probe_a` (town Minish fill), `probe_c` (Dr. Left's tiles), `probe_f`, `probe_g`,
`probe_h`; `py/rd.py` (room-property / Transition reader on the player's ROM); `check56.sh` (audit only)).  Outputs
`r27b/out_r56_*.txt` (`out_r56_fg.txt` = F + G in one session), pictures `r56/img`, shots `r27b/shots/*_a56_*` ..
`*_h56_*`.  Route source: the decomp's room data (entity_headers.s, transitions.c, roomInit.c, the room properties read
from the ROM) and a walkthrough's step order (cafe vase, the dog, the carpenter's portal, the fireplace, the roof plank,
the yellow house, the town Minish caves for the Power Bracelets, then the cabinets and the rafters).  **Cache version:
35, unchanged** (no import change) -- no re-import, the real-app cache stays current.

- [x] **Port bug fixed: the bottle's water probe facing left / right was mirrored.**  playerItemBottle.c
  PlayerItemBottle_UseEmptyBottle negates gUnk_080B7878's x when the BOTTLE's flipX is set, and sub_0801BDE8 (every
  frame from PlayerItemBottle_Action1) sets it to Link's flipX ^ ((animationState >> 1) & 1); the port negated by
  Link's own sprite flip, so facing left / right the probe looked behind Link (round 55's open question: answered).
  `CrenelPath.lua` (`CP.swingFlip56`, one anchored line in useBottle).  Checked with real keys: facing right at the
  river by Dr. Left's house the first swing now catches the water (round 55 needed the down swing).
- [x] **Port bug fixed: Link could walk on at 0 hearts.**  playerUtils.c sub_08079B24 (every frame) kills Link once
  gPlayerEntity.health is 0; the port only died in Player:hurt, so the water / pit / lava respawn (RespawnPlayer +
  ModHealth(-2), `Dungeon.lua`) and PlayerFall's landing damage could take the last hearts and leave Link walking
  (seen: a bot drowning at the town river went 48 -> 0 hearts, still "normal").  New `Story56.lua` (`deathCheck`),
  one anchored line after each of the two ModHealth calls (`Dungeon.lua`, `PlayerFall.lua`).
- [x] **Route facts (decomp + ROM):** Dr. Left's door opens on MIZUKAKI_HINT2 (town bank-2 local $6D, set by the
  librarian's sub_0806BA34 when BOOK1 = 2 and BOOK2 = 0: TEXT_LIBRARY 3; script_DrLeftDoor -> LEFT_DOOR_OPEN); the
  town dog type 2 at the west stairs (dog.c: SPECIAL_TILE_114 under it, always "near Link") blocks the stairs until
  Minish Link talks to it (sub_0806A0A4 -> MACHI_02_DOG $CE) -- both ported already and met with real keys; the
  cafe's south hole (property 9) -> town (0x180,0x2F8), the town hole $26 (0x54,0x248) -> Dr. Left's (0xB0,0x9E);
  the carpenter's Minish door (property 9) -> town (0x8C,0x290) and the town exit region (0x8C,0x29E) back in; Dr.
  Left's FIREPLACE (flag $84) and his fireplace region (0x48,0x4A) -> town (0x34,0x20C) layer 1 (his roof's chimney
  end, then the plank north onto the terrace); the yellow house $22:00: town hole $22 (0x7C,0x168) in, its back
  Minish door (property 9) -> town (0x9C,0x120); the fountain's exit region (0x174,0x192) -> $62:00 (the town Minish
  caves, PacciJump / MulldozerFight -> the Power Bracelets, which Minish Link needs to push Dr. Left's cabinets:
  pushableFurniture.c sub_0801A370).
- [x] **Route with real keys and real health** (checkpoints in `r56/ck`): from `r55_k_ret1` -> A the librarian again:
  **MIZUKAKI_HINT2**, out the library, south through town to the cafe (`r56_a_cafe`) -> B the Cane of Pacci flips the
  cafe vase, shrink, its south Minish hole -> town (`r56_b_town`) -> C west to the dog: **MACHI_02_DOG**, Dr. Left's
  hole -> his house as Minish (`r56_c_drleft`) -> D out of his hole, behind the carpenter's (exit region from above),
  grown on the carpenter's jar (`r56_d_big`) -> E out, **water from the river facing right**, Dr. Left's door (open),
  **water on his fire (flag $84)** (`r56_e_fire`) -> F shrink on the carpenter's jar, his Minish door, Dr. Left's
  hole, **into the cold fireplace -> his roof** (`r56_f_roof`; reloads Link on the ground -- run F + G together) ->
  G north over the plank, the terrace, the yellow house's Minish door (`r56_g_yellow`, latest).
- Bot / harness notes (not port bugs): the town dog stands still until MACHI_02_DOG (cartridge rule); go48 can walk
  into a house door on the way (plan lanes by hand near doors); the river by the west bridge drowns a bot that
  sidesteps; a checkpoint taken on Dr. Left's roof reloads Link on the ground (the save's place is the town's spawn);
  H.open24 (p:blocked at 4 px cells) lets the garden hedges by the fountain (tile $41F) through, the real walk does
  not -- the garden is entered at its east gap (x 360) then the west gap (x 296).
- [ ] Left: **the garden cats (npc $2C, cat.c) are static in the port** -- on the cartridge they walk between x and
  x + paramD (sub_08067904, speed $80), turn, scratch Minish Link (sub_08067D20 / sub_08067A0C hitboxes, hurtType
  $48) and talk; the cat at (0x13C,0x158) stands in the only lane to the bench / vine, so the route stops at
  `r56_g_yellow` (H: the vine and the fountain door not reached).  Port cat.c next (a new module), then: the vine,
  the fountain door -> $62:00, the Mulldozers -> the **Power Bracelets**, back through Dr. Left's chimney, push his
  drawers left 8 and his wardrobe left 16 (flags $37 / $38), the wall hole (0x88,0x28) -> the rafters $2E:02, the
  Gust Jar on the dust (ACT_TILE_87 at (56..72, 184..200)), the split (Red Sword: two Links), HUGE_BOOK, book 2 to
  the library; book 3 (the Mayor), Librari, the Flippers, the Temple of Droplets; Kinstone chest 2 ($50:10), the
  swamp's splash drawing.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r56_test.lua` (22 checks: deathCheck, the bottle's flip for all four facings, the book-2
  route's exits / furniture list read from the ROM).
- **Final check:** all 88 `tests/zelda_tmc_*_test.lua` pass (`r56/out_tests.txt`); room audit 605 / 605, 0 mismatching
  (`r56/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-56 session.

## Round 57 (the town cats ported -> the town Minish caves -> the Power Bracelets -> Dr. Left's furniture -> the rafters' split -> book 2 knocked down and picked up)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r57/` (`run.sh` / `go.sh` = round 56's runner with `pre57.lua`
(checkpoints in `r57/ck`, falling back to r56 .. r38) and `lib57.lua` (`H.cats57`, `H.until57`, `H.tick57` per-frame
hook, `H.layerLog57`, `H.pots57` (lift / throw / collect), `H.path57` (BFS with an extra cell test)); segments
`seg_a57` .. `seg_p57` (`seg_k57` / `seg_l57` / `seg_p57` = r56's B / C / D with round-57 checkpoint names); probes
`probe_b` .. `probe_r`; `rebuild57.sh` (cache 36 rebuild -> harness cache, real-app cache and test cache, then the room
audit; `rebuild57.sh audit` = audit only); `py/cat.py`, `py/ck.py` (table dumps / Fletcher checksums on the player's
ROM)).  Outputs `r27b/out_r57_*.txt`, shots `r27b/shots/*_a57_*` .. `*_p57_*`.  Route source: the decomp's room data
(entity_headers.s: HyruleTownMinishCaves_*, MinishRafters_DrLeft; roomInit.c; transitions.c) and a walkthrough's
step order.  **Cache version: 36** (r35.bin gains the seven `Cat57.*` tables; players re-import once); the harness
cache, the real-app cache (`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt / refreshed at 36.

- [x] **Port gap fixed: the town cats (NPC $2C, src/npc/cat.c).**  The port drew them but ran none of their code.
  New `Cat57.lua`, every function of cat.c: Cat (main; sub_0806ED78's push-out with the cat's current hitbox while
  COLLISION_OFF and type ~= 5), sub_080677EC (init: walk span unk_6c = the spawn x (sub_0805ACC0), unk_6e = + timer),
  sub_08067B08 / B34 (sitting, gUnk_08111104 time, frameDuration (R & $30) + $B4, interact dirs gUnk_0811110C[flipX]),
  sub_080678AC (frame byte 1 and the time out -> walk), sub_08067AAC / 904 (the walk: speed $80, turns at the span
  ends, gUnk_081110FC time, sub_08067B70 stop), sub_0806797C / 99C (talking: back to sitting when the message ends),
  sub_08067B80 / 9C4 / BD4 (watching Minish Link: sub_08067D20's rect with unk_75's cool-down, turn past 4 px),
  sub_08067D74 / C18 / A0C (the strike rect, the scratch: frame & 7 -> COLLISION_ON with gUnk_08111154[n - 1 +
  flipX * 4]), sub_08067C24 / A78 (leave -> walk), sub_08067A98 (fusion), sub_08067C44 (the talk: animation by
  sub_0806FCA0, ShowNPCDialogue(dialogs[type][global_progress]), SFX_VO_CAT).  The tables are read from the ROM
  (`RomTablesCat` `Cat57.BOX / DIALOG / WALK_T / SIT_T / DIRS / IBOX / SCRATCH`).  Hooks: one anchored line in
  Field's entity loop (through ObjErrors49.call), one in Field:delayedEntityLoad (NPCStruct.timer, entity->timer).
  SIMPLIFIED: gEnemyTarget's per-frame cache (no enemies in town), SetEntityPriority, the scratch contact uses
  Enemies.lua's contact rules (gCollisionMtx row $A8 against Link's hurtType).  Seen with real keys: the garden cats
  walk their spans, the cat on the bench row watches Minish Link, scratches him (6) and walks on.
- [x] **Route with real keys and real health** (checkpoints in `r57/ck`): from `r56_g_yellow` -> A / B the yellow
  house's back door, the garden, the cat row (wait for the cat at its east end), down the vine, the fountain's Minish
  door -> $62:00 (`r57_b_caves`) -> C east -> $62:02 (`r57_c_pacci`) -> D the two Mulldozers (sword on B), six pots,
  the Cane of Pacci into the hole (136,104), the spring onto the top floor (`r57_d_top`), north -> $62:03
  (`r57_d_mull`) -> E the REGION_TRIGGER -> FIGHT_MANAGER (four type-1 Mulldozers), the chest: **the Power
  Bracelets** (`r57_e_brace`) -> G the ledge down in $62:02 (off the blade traps' row), west, south -> town
  (`r57_g_town`) -> I the library yard's jar (grow), Library 2F / 1F out (`r57_i_big`) -> J the cafe -> K the vase
  portal, Minish (`r57_k_town`) -> L the dog, Dr. Left's hole (`r57_l_drleft`) -> M **drawers pushed left 8 from the
  gap, wardrobe left 16 (flags $37 / $38)**, the ladder by the fireplace, the wall-top strip (SPECIAL_TILE_38 behind
  the furniture), the wall hole -> $2E:02 (`r57_m_rafters`) -> N **the Gust Jar on the dust** (ACT_TILE_23 $69 / $6A
  -> the clone tiles; the other two patches are plain dust) (`r57_n_dust`; dust comes back on a reload: run N + O
  together) -> O **the Red Sword's split** (charge on the lower clone tile, step up: the clone 16 px below), the walk
  round the beam holes to the HUGE_BOOK (Link and clone at x <= $15A, with the rafters Minish): **MIZUKAKI_HARIFALL**,
  the book falls into the house (`r57_o_book`) -> P out of Dr. Left's hole, the carpenter's back wall, grown on his
  jar, his door, Dr. Left's door, the BOOK ($8C, book.c Action4): **ITEM_QST_BOOK2** (`r57_p_book2`, latest).
- Bot / harness notes (not port bugs): the sword must be equipped (H.gear47) before fighting; the Sluggulas of
  $62:00 drop on a bot that lingers; $62:02's blade traps guard the y 104 row; a checkpoint inside $62:02 reloads Link
  elsewhere (run C + D in one session); the bot drowned crossing the river south of the dog's stairs (go48 plans
  through water); the rafters' holes (act $0D) between the beams drop Link into Dr. Left's house (plan the split walk
  by hand: both Link and the clone off the holes and out of the walls).
- [ ] **Left / next: the town dog's movement (dog.c) is not ported** -- after MACHI_02_DOG the cartridge's type-2
  dog wanders +-$20 round its spot (sub_08069B44 / C40 ...); in the port it stands at the foot of the west stairs,
  the only way for full-size Link between the town's north and its south-west, so book 2 (in hand) can't be carried
  to the library yet.  Port dog.c next (a new module like Cat57), then: book 2 to the library, book 3 (the Mayor:
  wall masks with the Pegasus Boots, the Minish Woods tree portal, the cabin's Minish path and lily pad), Librari's
  trap door, the Flippers; Kinstone chest 2 ($50:10), the swamp's splash drawing.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r57_test.lua` (113 checks: cache version 36, the Cat57 catalogue entries; with the ROM: the
  tables' shapes, then the cat on a stand-in sprite -- init / span, sitting -> walking, the walk's speed and turns,
  the watch rect's edges (both flips, Minish only), watch -> strike -> scratch boxes -> leave, the talk
  (dialogs[type][global_progress], animation, SFX, message wait), type 5 never strikes; no cartridge values in the
  test).
- **Final check:** all 89 `tests/zelda_tmc_*_test.lua` pass (`r57/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r57/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-57 session.

## Round 58 (the dogs ported -> the dog moves -> book 2 returned -> the Mayor's hint -> his mask knocked down with the Pegasus Boots)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r58/` (`run.sh` / `go.sh` = round 57's runner with `pre58.lua`
(checkpoints in `r58/ck`, falling back to r57 .. r38) and `lib58.lua` (`H.dogs58`, a `MSG58` log of every message
shown); segments `seg_a58` .. `seg_e58`; probes `probe_a` .. `probe_f`; `rebuild58.sh` (cache 37 rebuild -> harness
cache, real-app cache and test cache, then the room audit; `rebuild58.sh audit` = audit only); `py/ck.py` (Fletcher
checksums on the player's ROM); `src/` (decomp files read for this round)).  Outputs `r27b/out_r58_*.txt`, shots
`r27b/shots/*_a58_*` .. `*_e58_*`.  Route source: the decomp (dog.c, mask.c, mayorHagen.c, roomInit.c,
entity_headers.s, transitions.c).  **Cache version: 37** (r35.bin gains the five `Dog58.*` tables and
`Story58.MAYOR_BOX`; players re-import once); the harness cache, the real-app cache (`r27b/appdata/LOVE/tmc_bugs1`)
and `testcache` were rebuilt / refreshed at 37.

- [x] **Port gap fixed: the dogs (NPC $35, src/npc/dog.c).**  The port drew them (NpcParts' Dog_Head) but ran none of
  their code: no talk, MACHI_02_DOG never set, the town's type-2 dog a fixed block at the foot of the west stairs.
  New `Dog58.lua`, every function of dog.c: Dog (main), sub_08069B44 (init: the wander box x +-(timer or $20), y +-8
  from sub_0805ACC0's spawn point; type 2 with MACHI_02_DOG clear -> SetTile(SPECIAL_TILE_114, TILE(x, y - 8))),
  sub_08069C40 (standing -> walking, gUnk_08111DA8), sub_08069CB8 (facing Minish Link by gUnk_08111DB0), sub_08069D00,
  sub_08069D54 (the walk: ProcessMovement0, the box clamp, sub_0800417E's bounce), sub_08069DF8, sub_08069E44,
  sub_08069E50 (Stockwell's dog: the food -> action 7, $29), sub_08069ECC (fusion), sub_08069EE0, sub_08069F6C,
  sub_08069F90 (type 2 always "near" until MACHI_02_DOG, else EntityInRectRadius $14), sub_08069FBC, sub_08069FE8,
  sub_0806A028, sub_0806A080 (gUnk_08111E34[type2][progress]), sub_0806A0A4 (type2 2: dialogs 0 .. 4, MACHI_DOG_C,
  MACHI_02_DOG, RestorePrevTileEntity) and sub_0806A144 (type2 3).  The flag numbers come from sub_0806A0A4's
  immediates: **MACHI_02_DOG is local $CF, MACHI_DOG_C $DB** (rounds 56 / 57 printed $CE, MACHI_02_HEISHI, which
  was set for another reason: the dog's talk had never run).  Tables from the ROM (`RomTablesCat` `Dog58.DIRS / ANIM
  / DIALOG / MSG / MSG2`).  Hook: one anchored line in Field's entity loop (through ObjErrors49.call).
- [x] **Port bug fixed: the A press that closed a message re-opened it.**  Field closed the text box and ran Link's
  update in the same frame with the same press, so an NPC without a script answered again at once (the dog: 85
  messages for one talk).  On the cartridge the window's close runs over several frames with Link held.
  `Field.lua`: `textClosedAt` set when the box closes, `Field:inputLocked` true on that frame (two anchored lines).
  Checked with real keys: one talk = one message.
- [x] **Port gap fixed: MASK $5C (src/object/mask.c) and the Mayor's room code.**  The masks were a fixed frame
  (ObjStatic), and sub_StateChange_HouseInteriors1_Mayor (start_pos_y > $40 -> Entities_HouseInteriors1_Mayor_080D6210)
  was not ported, so the Mayor's four masks never appeared.  New `Mask58.lua` (R37 list): Mask_Init (type2 $40 / $80
  flag rules, SPECIAL_TILE_34 on its tile, zVelocity 1.5, the gravity from Random), Mask_Action1 (PLAYER_BOUNCE facing
  up, <= 40 px below, |dx| < timer >> 1 -> its tile and collision back, z - $20, y + $20), Mask_Action2
  (BounceUpdate; landed: $80 -> SFX_SECRET + flag, $40 -> flag; FX_POT_SHATTER, CreateRandomItemDrop(3)),
  Mask_Delete; and the room code.  SIMPLIFIED: gRoomTransition.stairs_idx (f.stairsIdx, 0 when absent).
- [x] **Port bug fixed: Mayor Hagen's interact box.**  MayorHagen_MakeInteractable ($0806CE5C) also calls
  SetInteractableObjectCollision(1, 0, gUnk_08113F44); the port's generic `<Npc>_MakeInteractable` only made him
  talkable, so full-size Link could not reach him across his desk.  New `Story58.lua` (R37 list) registers the
  native with the Rect read from the ROM (`Story58.MAYOR_BOX`).
- [x] **Route with real keys and real health** (checkpoints in `r58/ck`): from `r57_p_book2` -> A out of Dr. Left's,
  the carpenter's jar (shrink), his Minish door, **the dog as Minish: MACHI_02_DOG ($CF), its tile restored**
  (`r58_a_dog`) -> B one more talk (one message), the carpenter's back wall, grown on his jar, out (`r58_b_big`) ->
  C **full size north past the wandering dog** (the stairs, y 504), Library 1F (`r58_c_lib`), the librarian: **book 2
  returned (ITEM_QST_BOOK2 = 2)** (`r58_c_ret2`) -> D the librarian again: **MIZUKAKI_HINT3 ($70)**, the Mayor's door
  (town (712,312)): **MIZUKAKI_HINT3_MAYOR ($71)** (`r58_d_mayor`), the Pegasus Boots north into the $80 mask over his
  Minish entrance: **it falls, SFX_SECRET, flag $1B** (`r58_d_mask`, latest) -> E the Cane of Pacci on his jar,
  shrink (ok) -- **stopped**: Minish Link can't reach his Minish entrance (0x38,0x28).
- [ ] **Left / next: the Mayor's wall hole.**  The entrance sits in the top wall: tile (3,2) collision $46 (the top
  layer's type $300, merged by sub_0807C5B0), the row below (3,3) $0F.  The cartridge's own return
  (gExitList_TownMinishHoles_MayorsHouse) puts Minish Link at (0x38,0x2C) facing down, which the port seals in (probe
  `r58/probe_f.lua`: no way down or up from there) -- so the cartridge must let Minish Link through that wall (most
  likely the Minish-door surfaces / the $46 shape for the Minish collision table, or the hole's act tile); find it
  in the player's collision / surface code, then: $2D:00 (script_TownMinish4 / 5: MIZUKAKI_HINT3_MAP), Lake Hylia's
  exit region (0x2A8,0x31E) -> MinishPaths_MayorsCabin $11:04 (the lily pads, the Minish path), the cabin $28:05
  (gUnk_080F3A48: BOOK type 2 on the shelf), book 3, Librari's trap door, the Flippers; Kinstone chest 2 ($50:10),
  the swamp's splash drawing.  Also seen: the Mayor's MINISH_SIZED_ENTRANCE draws nothing in the port (no hole
  sprite once the mask is down).  Link's tile box not changed.
- Bot / harness notes (not port bugs): after a door the town's entities may not have run their first update when a
  segment prints them (the door walk); the dog's talk needs Link right below it facing up.
- Tests: `tests/zelda_tmc_r58_test.lua` (168 checks: cache version 37, the Dog58 / Story58 catalogue entries, the
  message-close frame; with the ROM: the tables' shapes (the DIALOG_CALL_FUNC rows point at sub_0806A0A4 /
  sub_0806A144), then the dog on a stand-in sprite / room -- init box and tile, sub_08069F90, sub_0806A0A4's dialog
  order / flags / tile restore, sub_0806A144's branches, standing -> walking, the clamp and bounce, near -> stop,
  the dog food; the Mayor's Rect edges; the mask's init, bonk test edges, fall, tile / collision restore and flags;
  no cartridge values in the test).
- **Final check:** all 90 `tests/zelda_tmc_*_test.lua` pass (`r58/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r58/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-58 session.

## Round 59 (the Mayor's wall corridor solved -> his Minish -> MIZUKAKI_HINT3_MAP; the cabin's island mapped: no full-size way in yet)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r59/` (`run.sh` / `go.sh` = round 58's runner with `pre59.lua`
(checkpoints in `r59/ck`, falling back to r58 .. r38) and `lib59.lua` (`H.dry59` dry reach + border edges + exits +
picture, `H.edge59` walk off a border, `H.trek59` waypoints with sword fights, `H.cuttable59` / `H.cutpath59` BFS that
counts sword-cuttable tiles (tile interaction filter 0) as open and swings through them); segments `seg_a59` ..
`seg_r59`; probes `probe_a` .. `probe_t`; `py/sh.py`, `py/sh2.py` (Link's collision masks per state table, read from
the player's ROM); `rebuild59.sh audit`; pictures `r59/img`).  Outputs `r27b/out_r59_*.txt`, shots
`r27b/shots/*_a59_*` .. `*_f59_*`.  **Cache version: 37, unchanged** (no import change) -- no re-import.

- [x] **Solved (no port bug): the Mayor's Minish entrance.**  Link's tile test (asm/src/player.s sub_080085CC picks
  gUnk_0800833C for PL_MINISH; sub_080086D8) gives the shelf's collision $46 a full mask for full-size Link and, for
  Minish Link, a mask open on rows 8..13 only: the shelf (top-layer type $300, merged into gMapBottom by
  sub_0807C5B0) is a **horizontal Minish corridor** (y 40..45), not a way down.  It runs x 48..223 (the $0C cells
  under the drawers are open on their lower half) to the shelf's Minish ladder at column 14 ($62 / $60: open x 224..231
  for table 1 only), down to the floor at (14,4).  The other three masks (x $58, $B8, $D8: type2 $40 / $41) sit on
  the corridor with SPECIAL_TILE_34 (collision $0F) until Mask_Action1 puts their tile and $46 back -- so **all four
  masks are knocked down with the Pegasus Boots**, then the jar, the ladder, west along the shelf, up at
  (0x38,0x28).  The masks are only loaded when start_pos_y > $40 (sub_StateChange_HouseInteriors1_Mayor), so the
  return through the hole ((0x38,0x2C), facing down) finds the corridor open: Minish Link walks east and down the
  ladder.  Port and cartridge agree; Link's tile box not changed.
- [x] **Checked, no change: the MINISH_SIZED_ENTRANCE's hole sprite.**  minishSizedEntrance.c Init writes
  spriteRendering.b3 = 3 (OAM priority 3); house areas run BG2 (gMapBottom, SetBGDefaults $1C42) and BG1 (LoadRoomGfx
  gUnk_080B77C0[2] = $1D46) both at priority 2, and the wall's bottom tile under the hole is opaque on every pixel
  (probe_f: alpha map of the restored metatile), so on the GBA the hole OBJ is behind the wall -- the port's
  Priority.lua draws exactly that (probe_c: forced to priority 0 the frame shows, at 3 it is hidden).  Left as the
  cartridge has it.
- [x] **Route with real keys and real health** (checkpoints in `r59/ck`): from `r58_d_mask` -> A the three other
  masks down with the boots (flags $1C / $1D / $1E), the jar: Minish (`r59_a_minish`) -> B the shelf's ladder, west
  along the shelf, up into the hole: **TownMinishHoles_MayorsHouse $2D:00** (`r59_b_hole`) -> C both Minish
  (script_TownMinish4 / 5, messages $4C07..$4C09, $4C15): **MIZUKAKI_HINT3_MAP ($AE)** (`r59_c_map`) -> D out through
  the MINISH_SIZED_ARCHWAY onto the shelf, east, down the ladder, grown on the jar, out (`r59_h_town` side
  checkpoint in town), the Ocarina -> Lake Hylia (`r59_d_lake`) -> E off the crest's plateau (`r59_e_off`).
- [x] **Route facts (decomp + ROM): the Mayor's cabin island.**  Lake Hylia's exit region $A (0x2A8,0x31E) ->
  MinishPaths_MayorsCabin $11:04 sits under TREE_HIDING_PORTAL $9C (0x2A8,0x2D0) (Pegasus Boots bonk at ACT_TILE_84 ->
  the stump portal, manager 3 at (0x2A8,0x2E0)).  That island, the cabin door (0x2A0,0x378) and Lake Woods Cave's door
  form one dry part of Lake Hylia (x 300..728, y 660..936) that touches no border and no other dry part; the cave
  ($0C, its only exit back to the same spot) is a dead end.  The part's south edge is bushes over Minish Woods' north
  border (NORTH_WEST x 372..472, full size; NORTH_EAST x 724..728, INSTANT_MINISH).  Walked with real keys from town:
  the east gate -> Lon Lon Ranch's south-west is closed by TILE_TYPE_375 rocks (tile interaction filter 3 = bombs
  only); the south gate -> South Hyrule Field $03:01 (the octoroks fought) -> Eastern Hills $03:04 (`r59_j_east`) ->
  **the one bomb under the TILE_TYPE_375 rocks** (`r59_p_bomb`) -> over the bridge -> **Minish Woods (8,422)**
  (`r59_q_woods`, latest).  From there the north-west part of the woods (the path to the lake) is only reached across
  the deep pond at (136..200, 320..370) -- the bot died swimming without the Flippers -- and the Minish woods
  portals (0x128,0x370) / (0x398,0x3B0) are not dry-reachable from the bridge side.  Side checkpoints:
  `r59_i_south`, `r59_k_south` ($03:02), `r59_l_woods` (the woods' south-west pocket from $03:02's east edge: closed).
- [ ] **Left / next: reach the cabin island.**  Find the cartridge's full-size way from the woods' bridge to the
  north-west path (likely Minish Woods' own Minish paths: exit regions $9 .. $C (gUnk_additional_8_MinishWoods_Main)
  and the portal at (0x128,0x370); or Lake Hylia's Minish regions $9 / $B / $D), then: the boots into the
  TREE_HIDING_PORTAL, Minish, region $A -> $11:04 (lily pads), the cabin $28:05 (gUnk_080F3A48: BOOK type 2), book 3
  to the library, Librari's trap door, the Flippers; Kinstone chest 2 ($50:10), the swamp's splash drawing.
- Bot / harness notes (not port bugs): goDry47 / the BFS walkers do not know one-way ledges; H.path56 plans through
  deep water (the bot drowned twice: Lake Hylia's middle, the woods' pond); an octorok row in South Hyrule Field's
  north-east kills a bot that stands still (H.trek59 fights at each waypoint); a $40 mask comes back on every
  room entry that is not from stairs $44D..$44F / $182 (Mask_Init ClearFlag), so knock all masks and shrink in one
  session.  Health floor not used.
- Tests: `tests/zelda_tmc_r59_test.lua` (747 checks: the quarter values and $FF on a stand-in room; with the ROM:
  Room:isSolidPlayer against the masks read independently for all 7 state tables x $60 values x 256 pixels; the
  Minish corridor values exist and let Minish Link (table 1) cross a row full-size Link can't; Player:blocked picks
  table 1 for Minish Link, 0 for full size; no cartridge values in the test).
- **Final check:** all 91 `tests/zelda_tmc_*_test.lua` pass (`r59/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r59/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-59 session.

## Round 60 (the cartridge's way to the Mayor's cabin: ranch field -> Lake Hylia's south-west -> Minish Woods' north -> the Mole Mitts into Lake Woods Cave -> the cabin island -> book 3)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r60/` (`run.sh` / `go.sh` = round 59's runner with `pre60.lua`
(checkpoints in `r60/ck`, falling back to r59 .. r38) and `lib60.lua`: `H.reach60` (directed reach that follows ledge
jumps -- Ledge.lua's sub_08079550 probe points and sub_08079FD4's n -- and, with `cut`, sword-cuttable tiles; with
`minish`, Player:blocked's Minish table and the Minish doors / log tunnels $1F..$22), `H.border60` (the tiles round a
reach), `H.dig60` / `H.digWalk60` (tile walk through ACT_TILE_86 soft dirt with the Mole Mitts, real keys),
`H.mpath60` (2 px BFS on Player:blocked, Minish-size), `H.lineExact60`, `H.ledges60`; a wrap of the harness's
`H.hazard` (it asked inventory $10, the cartridge and Dungeon:checkFall test ITEM_FLIPPERS $46); segments `seg_a60` ..
`seg_o60`; probes `probe_a` .. `probe_af`; `rebuild60.sh audit`; pictures `r60/img`).  Outputs `r27b/out_r60_*.txt`,
shots `r27b/shots/*_f60_*` .. `*_n60_*`.  Route source: the decomp (transitions.c, entity_headers.s,
diggingCaveEntranceManager.c's table, roomInit.c, book.c, cabinFurniture.c) and a walkthrough's step order.
**Cache version: 37, unchanged** -- no re-import.

- [x] **Found (no port bug): the cartridge's way to the cabin island.**  Round 59's "separate dry area" was right for
  walking, wrong for the route: the island (with the garden and Lake Woods Cave's stairs) is entered *through Lake
  Woods Cave from Minish Woods* -- diggingCaveEntrances: Minish Woods tiles (31,15) / (37,19) (soft walls,
  ACT_TILE_86, by Syrup's stairs) -> AREA_LAKE_WOODS_CAVE, whose soft-dirt maze is dug up to the exit
  (0x248,0x188) -> Lake Hylia (0x148,0x358) in the island's garden.  Minish Woods' north-west (Syrup's garden) is
  reached full size from Lon Lon Ranch field $03:05: its south part (from Eastern Hills' north edge x 292..344) ->
  east edge y 884..936 -> Lake Hylia's south-west pocket (Waveblade's tree) -> its south edge (lake x 132..232 = woods
  x 372..472).  The island's other ties are one-way or need the Flippers: the garden's south-west strip (lake x
  288..295 -> woods (528..543, 0..63)) jumps down into Syrup's garden (ledge $2D, n = 4); the woods' NE channel and
  its Minish door ((776,24) -> lake (536,952), MINISH_DOOR_FRONT / BACK) are shallow water at both ends; the docks of
  the woods' pond are SLOPE_GNDWATER steps into deep water.  World offsets: woods x = lake x + 240.
- [x] **Checked, not a port bug: the reach blind spots.**  r59's dry reach did not follow ledges or Minish tunnels
  and its Minish fill used the full-size table (H.open24 passes table 0); `H.reach60` follows both.  r59's "portal
  (920,944) not dry-reachable" tested the stump's own (solid) centre; the tall grass at (56, 50..53) ($5F, ACT $2F) is
  open for full size and solid for Minish Link (ROM table 1, confirmed) and sword-cuttable.
- [ ] **Divergence found, not changed: Minish Link in water.**  player.c SurfaceAction_ShallowWater calls
  SurfaceAction_Water for PL_MINISH, and sub_08079C30 returns TRUE at once for PL_MINISH (unless gPlayerState.field_0x14
  / PL_FLAGS2): without the Flippers Minish Link drowns in shallow *and* deep water.  Dungeon:checkFall skips ACT_WATER
  for Minish Link and never tests ACT_TILE_15.  Not changed this round: the cabin's own Minish arrival
  (MinishPaths_MayorsCabin's south exit, (0xB8,0x48)) lands in its pool, where the clover (LILYPAD_SMALL $73, paramB
  $B, its rail) must be what keeps him up (field_0x14) -- check the clover's start / the arrival before porting the
  drown, or the route breaks there.  In this round's route Minish Link crossed the cabin's pool on foot (the clover
  was seen riding its rail; the cartridge needs it).
- [x] **Route with real keys and real health** (checkpoints in `r60/ck`): from `r59_p_bomb` -> A Eastern Hills' north
  edge -> ranch field (`r60_a_ranch`) -> B east along its south part (bushes cut) -> Lake Hylia's south-west
  (`r60_b_lake`) -> C its south edge -> Minish Woods' north-west (`r60_c_woods`) -> D **the Mole Mitts into the soft
  wall (31,14..15): DIGGING_CAVE_ENTRANCE -> Lake Woods Cave $0C:00** (`r60_d_cave`) -> E **dug up through the
  maze** (column 31 to row 40, row 40 east, column 34 up -- row 36's half tiles clear when row 37 is dug --, column 38
  up to row 25) -> the exit: **the cabin island** (`r60_e_island`) -> F **the Pegasus Boots into TREE_HIDING_PORTAL**
  (PLAYER_BOUNCE on ACT_TILE_84, the 5 x 4 Minish entrance) (`r60_f_portal`) -> G shrunk at the stump, exit region $A
  -> **MinishPaths_MayorsCabin $11:04** (`r60_g_path`) -> H the large lily pad south with the Gust Jar (23 blows) ->
  I **the cabin $28:05** (Minish) -> K the pushable furniture (manager $26) pushed right (Power Bracelets, local flag
  $4F) -> L its Minish ladder, east along the top, **BOOK type 2 pushed down twice (Book_Action1, subtimer 2) off the
  fireplace** (`r60_l_book`) -> M back through the pool, exit region $9, the pad north (`r60_m_lake`) -> N grown at the
  stump, round to the front door, in: **ITEM_QST_BOOK3** (`r60_n_book3`, latest).  Run H .. L in one session from
  `r60_g_path` (checkpoints inside $28:05 / on a pad reload elsewhere).  O (not kept): the Ocarina from the island --
  only the Mt Crenel and Lake Hylia crests are lit (windcrests $1101B7EF), the town crest is not; book 3 goes back by
  the ranch field (island -> the garden's south-west strip -> Syrup's garden -> the lake's south-west -> ranch field
  -> its west edge y 132..184 -> town).
- Bot / harness notes (not port bugs): a dug soft tile under its top tile stays TILE_TYPE_754 (half solid) until the
  one under it is dug -- cross such a row at tile y + 5 exactly; the mitts' dig moves Link forward, line up on both
  axes; checkpoints in the dig cave reload at its entrance with the dirt back; after growing at a portal wait for the
  state to be normal (a held key walked the bot into the lake: one death, reloaded from `r60_m_lake`); Ocarina cursor
  index = crest bit - 24.  Health floor not used.
- [ ] **Left / next:** book 3 to the library (the ranch field way above, or light the town crest), Librari's trap door,
  the Flippers; the Minish water drown (with the cabin clover's start checked); Kinstone chest 2 ($50:10), the swamp's
  splash drawing.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r60_test.lua` (15 checks: CreateMinishEntrance's 5 x 4 block on a stand-in, Ledge.count on a
  stand-in room; with the ROM: ItemMitts.wallAhead's wall / soft wall / floor values on a stand-in, the digging cave
  table's round trips and an overworld room with two entrances into one dig cave room; no cartridge values).
- **Final check:** all 92 `tests/zelda_tmc_*_test.lua` pass (`r60/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r60/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-60 session.

## Round 61 (book 3 home on foot -> all books back -> Librari's trap door -> the Flipper cave -> ITEM_FLIPPERS; the cabin's board and Minish Link's drown ported)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r61/` (`run.sh` / `go.sh` = round 60's runner with `pre61.lua`
(checkpoints in `r61/ck`, falling back to r60 .. r38; `KEEPHP=1 FULLHP=1` keeps the harness refill) and `lib61.lua`:
`H.dig61` / `H.digWalk61` (round 60's dig walk, now also *down* a soft column: a half tile (754) entered from above is
walked into at tile y + 5, not dug), `H.upTo61` (taps to an exact pixel, the diagonal when the 1.25 px step jumps
over a one-pixel window), `H.beetle61` (Scissors Beetle fight: bait the snap 40 px in front, side-step the throw
line, hit the jawless body), `H.clover61` / `H.waitClover61` / `H.held61` / `H.holdUntil61` (the cabin pool);
segments `seg_a61` .. `seg_p61`; probes `probe_a` .. `probe_m`; `py/ck.py`; `rebuild61.sh` (cache 38 rebuild ->
harness cache, real-app cache, test cache, then the room audit)).  Outputs `r27b/out_r61_*.txt`, shots
`r27b/shots/*_e61_*` .. `*_pm61_*`.  Route source: the decomp (trapdoor.c, librari.c, board.c, lilypadSmall.c,
holeManager.c, scroll.c IsPosInTransitionRect, player.c / playerUtils.c surface and drown code, entity_headers.s,
transitions.c, specialWarpManager.c) and a walkthrough's step order for the Flipper cave.  **Cache version: 38**
(r35.bin gains `Board61.SIZES`, board.c Board_Sizes $0812366C); the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 38 -- **players re-import once**.

- [x] **Port gap fixed: TRAPDOOR $86 (src/object/trapdoor.c).**  Not ported: Librari's script (TEXT_TOWN_MINISH1
  $22, condition 1 -> MIZUKAKI_STAIR $74, Link moved onto the trap door, $4A24 .. $4A26, MIZUKAKI_STAIR_WARP_OK $75)
  ran, but nothing opened and nothing dropped Link.  New `Trapdoor61.lua` (R37 list, one line): Trapdoor_Init
  (ITEM_FLIPPERS -> action 4, frameIndex 0; else action 1, animation 0), Action1 (MIZUKAKI_STAIR, GetNextFrame, the
  keyframe flags == 1 -> sub_08099ECC; done -> action 2), Action2 (three loops -> action 3, frameIndex 4), Action3
  (EntityInRectRadius(12, 12): sub_08099ECC once; MIZUKAKI_STAIR_WARP_OK -> CreateHoleManager(7)), sub_08099ECC
  (CopyPosition, PLAYER_FALL, PL_PIT_IS_EXIT).  `PlayerFall.lua` (one anchored line): with PL_PIT_IS_EXIT and no hole
  yet the finished fall waits hidden (PlayerFallUpdate: no respawn) until the hole manager's exit arrives
  (gHoleTransitions[7], from the ROM: $62:11 (0xC8,0x38)).
- [x] **Port gap fixed: BOARD $80 (src/object/board.c) -- the cabin's Minish arrival.**  MinishPaths_MayorsCabin's
  south exit lands Minish Link at (0xB8,0x48) on *deep water*; the cartridge holds him up with the floating board
  (0xB8,0x40) (sub_08098BE8: Minish, inside sub_08098C30's rect (Board_Sizes[type], read from the ROM),
  PlayerCanBeMoved, z 0 -> gPlayerState.field_0x14 = 1 and sub_0807AAF8 (its tile into the path memory)); type 0
  also puts SPECIAL_TILE_116 on the tile above (Board_Init).  The port drew the board only.  New `Board61.lua` (R37
  list for the Init tile + one anchored line in `Dungeon:checkFall`).  (The clover LILYPAD_SMALL was already ported:
  its rail never comes within 8 px of the arrival point -- the board is the arrival's support.)
- [x] **Port divergence fixed: Minish Link drowns without the Flippers.**  player.c SurfaceAction_ShallowWater ->
  SurfaceAction_Water for PL_MINISH; sub_08079C30 TRUE at once for PL_MINISH unless field_0x14 / PL_FLAGS2;
  sub_08074808 without ITEM_FLIPPERS -> PLAYER_DROWN.  New `Drown61.lua` (surface from gMapActTileToSurfaceType:
  SHALLOW_WATER / WATER / $20); `Dungeon:checkFall` (three anchored lines): the drown test, and shallow water is no
  safe respawn tile for Minish Link.  SIMPLIFIED: the Minish drown animation (ANIM_DROWN_MINISH, 60 frames) is the
  port's existing drown (-2, RespawnPlayer); Minish Link with the Flippers does not swim in shallow water.
  **Checked with real keys** (one session from `r60_g_path`: round 60's H, I, then `seg_o61` (on the board, onto the
  clover at (184,88), off at (184,104) onto the pool's ladder, the furniture pushed), round 60's L (book 3 off the
  fireplace), `seg_p61` (back: ladder, clover, board, exit region $9, the lily pad north): **no drown, health
  unchanged**, `r61_p_lake`); probe M: stepping off the board while the clover is away drowns him (-2) and puts him
  back on the board's tile.
- [x] **Not a port bug: Lake Woods Cave is two-way.**  Dug *down* from the island side: the soft tiles under top
  tiles become 754 (bottom half solid) when dug from above and clear when the next one is dug; row 36's built-in
  half tiles are walked into at y + 5 (no dig), row 37 dug from there (ItemMitts.digWall = sub_0807B600).  The
  island's garden strip (lake x 288..295) is reached only from the woods (a one-way ledge into the lake's south-west),
  not from the island.
- [x] **Not a port bug: the green book's door in the bookshelf $2D:10.**  The exit is (0x100,0xC8) with
  TRANSITION_SHAPE_AREA_12x12 = +-6 (scroll.c IsPosInTransitionRect): x 250..262, while the door's gap is x 244..252
  -- Link must push it at x 250..252 (the harness had lined up at 248).  The SPECIAL_WARP region there needs PL_MINISH
  (bits $11), unused at normal size, as on the cartridge.
- [x] **Route with real keys** (checkpoints in `r61/ck`): from `r60_n_book3` -> A out of the cabin (`r61_a_out`) -> B
  the cave's stairs (the cave side is a ladder), dug down the maze, out at Syrup's soft wall (`r61_b_woods`) -> C the
  woods' north edge -> Lake Hylia's south-west (`r61_c_lake`) -> its west edge -> ranch field (`r61_c_ranch`) -> D
  its west edge -> North Hyrule Field (`r61_d_field`) -> E south edge -> town (`r61_e_town`), the library
  (`r61_e_lib`): **book 3 returned (ITEM_QST_BOOK3 = 2, MIZUKAKI_BOOK_ALLBACK)** (`r61_e_ret3`) -> F 2F, the yard's
  jar (Minish), the yard's Minish hole, 2F's warp -> the bookshelf $2D:10 (`r61_f_shelf`) -> G the green book's door
  -> **Librari's book house $2D:11** (`r61_g_librari`) -> H Librari: MIZUKAKI_STAIR, the trap door, the fall,
  MIZUKAKI_STAIR_WARP_OK -> **$62:11** (Ezlo's hint $0B16) (`r61_h_cave`) -> I the two pushable blocks (ACT_TILE_112,
  sub_0801A9F0: $363 west, $362 south) (`r61_i_out`) -> J south -> $62:14 (`r61_j_south`) -> K the Sluggulas, the
  Gust Jar on the PULLABLE_MUSHROOM across the channel, flung west (`r61_k_west`) -> L west -> $62:13
  (`r61_l_cross`) -> M north -> the Flippers room $62:10 (`r61_m_flip`) -> N the region trigger, the FIGHT_MANAGER's
  two Scissors Beetles, the CHEST_SPAWNER: **ITEM_FLIPPERS** (message $0546) (`r61_n_flippers`, latest).
  **Harness aid used on N only:** `FULLHP=1` at the load of `r61_m_flip` (full hearts; the bot came out with 6 hp --
  its beetle fighting is poor; with its real 28 hp it died twice).  All other legs real health.
- Bot / harness notes (not port bugs): Link's 1.25 px step can miss y + 5 of a half tile from some phases
  (H.upTo61's diagonal tap); the beetles' mandibles in areas $60-$62 are EnemyToD's ('jaws'), facing their own
  animationState; the cabin's checkpoints still reload outside.
- [ ] **Left / next:** out of the Flipper cave by water (swim), then the Temple of Droplets' prerequisites; Kinstone
  chest 2 ($50:10), the swamp's splash drawing.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r61_test.lua` (27 checks: EntityInRectRadius edges, Trapdoor_Init / Action1 / Action3 on
  stand-ins, sub_08099ECC + the waiting fall and its transition; with the ROM: Board_Sizes, sub_08098C30's edges,
  Minish-only support and its safe tile, the drown on the ROM's shallow / deep water surfaces with and without the
  Flippers; no cartridge values in the test).
- **Final check:** all 93 `tests/zelda_tmc_*_test.lua` pass (`r61/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r61/out_a_rooms.txt`).  ObjErrors: **0 per-object errors** in every round-61 session.

## Round 62 (out of the Flipper cave by water -> the town stream as Minish -> Lake Hylia -> the frozen block's portal (PT_TOD) -> the Temple of Droplets: entrance, North Split, East Hole, the North Small Key room's small key, the West Hole room -> $60:20)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r62/` (`run.sh` / `go.sh` = round 61's runner with `pre62.lua`
(checkpoints in `r62/ck`, falling back to r61 .. r38) and `lib62.lua`: `H.swimTo62` (8-way hold, works swimming),
`H.mpath62` / `H.mpath62r` (2 px BFS on Player:blocked that plans deep water with the swim table, optional keep-out
discs `H.avoid62`, plans again where it stalls, closes message boxes), `H.ice62` (ice-floor controller: press / brake /
coast per axis from ToDObjects' ice step), `H.heal62` / `H.drops62` (cut grass for drops, pick drops up), **`H.fight62`**
(general sword fight, see below), `H.amap62` / `H.pic62`; segments `seg_a62` .. `seg_r62`, `seg_n62` (round 61's
beetle leg with H.fight62); probes `probe_a` .. `probe_r`; `py/ck.py`; `rebuild62.sh` (cache 39 rebuild -> harness
cache, real-app cache, test cache, then the room audit)).  Outputs `r27b/out_r62_*.txt`, shots `r27b/shots/*_a62_*`
.. `*_r62_*`, pictures `r62/img`.  Route source: the decomp (transitions.c, screenTransitions.c, player.c
PlayerUsePortal / PortalEnterUpdate, minishPortalManager.c, gameUtils.c InitializePlayer, holeManager.c, roomInit.c
sub_StateChange_LakeHylia_Main, entity_headers.s for the temple rooms, lockedDoor.c, pushableLever.c,
beanstalkSubtask.c, templeOfDropletsManager.c).  **Cache version: 39** -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 39 -- **players re-import once**.

- [x] **Port gap fixed: the Temple of Droplets' portal (PT_TOD, portal type 6).**  The frozen block in Lake Hylia's
  middle carries MINISH_PORTAL_MANAGER type 6 (on its ACT_TILE_61 stump, inside the SPECIAL_TILE_145 ring that
  sub_StateChange_LakeHylia_Main lays).  The port treated it as an ordinary portal (Link would have been shrunk next
  to it).  New `PortalToD62.lua` (R37 list + two anchored lines in `Objects.lua`): PortalReadyForMinish is FALSE for
  PT_TOD (`Objects:portalNear`: Minish Link never grows there); after the shrink, PortalEnterUpdate hides Link and
  does DoExitTransition(&gUnk_0813AB58) -- read from the ROM (`RomTablesCat` "PortalToD62.WARP_TOD": $60:03
  (0x108,0xC8), layer 2, TRANSITION_TYPE_DROP_IN, facing 4); roomInit shows Link again.  SIMPLIFIED: the shrink spin
  is the port's existing portal animation / timer.
- [x] **Port divergence fixed: the special-tile collision table was cut at $80.**  coll.bin kept 128 entries of
  gMapSpecialTileToCollisionData (Layout.SPECIAL_TILE_COUNT = $80); SPECIAL_TILE_128 .. 150 read collision 0 (the
  lake ring's SPECIAL_TILE_145 = COLLISION_DATA_34, the giant-book ladder's 142 / 143, the Goron cave's 150, ...).
  Now $97 entries (`Layout`, `Extract` manifest.collision.specialCount, `Assets.loadCollision`).  **Cache 39.**
- [x] **Checked, not port bugs:** the Flipper cave (AREA_HYRULE_TOWN_MINISH_CAVES $62) is a Minish-scale area played
  at normal state; its way out is by water: $62:10 -> $62:13 -> $62:15, whose south border exit is
  TRANSITION_TYPE_INSTANT_MINISH (gameUtils.c InitializePlayer: PL_SPAWN_MINISH -> PLAYER_MINISH) -> **Hyrule Town's
  stream as Minish Link** (0xE2,0x58), swimming with the Flippers; the library garden's pot portal (PT_2, (368,62))
  grows him.  The temple's entrance room has no hole managers (its pits are plain pits); its south door is a
  BOSS_DOOR; the way on is the north door (ACT_TILE_41) -> North Split.  The North Split's west door is a small-key
  lock (LOCKED_DOOR type $B -> type2 2, AddInteractableSmallKeyLock); its east door is open.  The North Small Key
  room's ice is reached only through the East Hole room's LIGHT_DOOR pit (local flag $51 from the room's
  PUSHABLE_LEVER, pushed west: beanstalkSubtask.c SPECIAL_TILE_83 needs field_0x35 == 6) and left through the
  ACT_TILE_112 pushable block at (13,9).
- [x] **Route with real keys and real health** (checkpoints in `r62/ck`): **N (round 61's Flipper fight replayed with
  H.fight62 and real health: 28 -> 18, no FULLHP)** `r62_n_flippers` -> A .. D swim out (pool, $62:13, $62:15),
  the town stream as Minish, grown on the pot portal (`r62_d_grown`) -> E the Ocarina -> Lake Hylia's crest
  (`r62_e_lake`) -> F the plateau's grass cut, off west, the land octorok fought, swim (planned round the water
  octoroks) to the frozen block's ring -> G onto the PT_TOD stump, R: **the Temple of Droplets $60:03**
  (`r62_g_temple`) -> I off the platform, the ice floor, the SMALL_ICE_BLOCK at (8,12) pushed north, the north door ->
  **North Split $60:01** (`r62_i_north`) -> J the four FLYING_POTs, east -> **East Hole $60:02** (`r62_j_east`) -> K the
  three MULLDOZERs, the stairs -> **North Small Key $60:21** (`r62_k_b1`) -> L the PUSHABLE_LEVER (flag $51) -> M up,
  the opened LIGHT_DOOR's pit (hole manager 9) onto the ice -> O the key block (SMALL_ICE_BLOCK type 1) pushed down
  then east into the light region (room property 8) -> melted -> **small key** -> P the pushable block, the stairs
  (`r62_p_key`) -> Q North Split's key door opened -> **West Hole $60:00** (`r62_q_westhole`) -> R its Mulldozers,
  the stairs -> **$60:20** (the room with the lever and the big-key ice block, `r62_r_b1west`, latest; hp 4/48).
  **No health aid on any leg** (no FULLHP / KEEPHP).
- [x] **Fight helper: `H.fight62`** (lib62): dodges incoming projectiles across their line, backs off 20 frames
  after a hit, lines up 18 px on the nearer axis, swings, steps back after a swing; closes message boxes.  Round 61's
  two Scissors Beetles with real health: 28 -> 18 (5 hits taken; `beetle61` died twice from 28); the four flying
  pots: 0 hits; the land octorok: 0 hits; the Mulldozers: 1 hit ($60:02) and 2 x 4 ($60:00 -- weakest spot: their
  charge; it also walked into the stairs mid-fight).
- Bot / harness notes (not port bugs): a checkpoint saved in a doorway reloads a few pixels off (in a wall or on a
  layer-2 tile) -- the segments now step into the room before saving; grass drops are random (the plateau gave one
  heart in two tries); the swim planner's land table walked into rocks until the swim table was used for deep water.
- [ ] **Left / next:** $60:20 (PUSHABLE_LEVER + SMALL_ICE_BLOCK type 2 = the big key into the light), the Flame
  Lantern, the rest of the temple; health first (hp 4/48: fairies / grass); H.fight62 vs Mulldozers (side-step the
  charge); Kinstone chest 2 ($50:10), the swamp's splash drawing, the Minish drown animation, Minish swimming in
  shallow water with the Flippers.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r62_test.lua` (16 checks: PortalReadyForMinish / Objects:portalNear for PT_TOD on
  stand-ins; PortalEnterUpdate's transition = the ROM's gUnk_0813AB58, hidden / shown again; SPECIAL_TILE_COUNT =
  the special act-tile table's length, the ROM's collision entries past $80 not all zero; no cartridge values).
- **Final check:** all 94 `tests/zelda_tmc_*_test.lua` pass (`r62/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r62/out_a_rooms.txt`, at cache 39).  ObjErrors: **0 per-object errors** in every round-62 session.

## Round 63 (the big key (ten ice-block pushes) -> back across the West Hole's light bridge -> healed (North Split pots, the Element room's heart pots) -> the Entrance's big-key door -> the Element room -> WaterfallNortheast / Northwest -> West Waterfall South-west: the dungeon map, the bollards down; the shield against the temple's contact code)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r63/` (`run.sh` / `go.sh` = round 62's runner with `pre63.lua`
(checkpoints in `r63/ck`, falling back to r62 .. r38) and `lib63.lua`: `H.iceRoute63` (tile BFS on an ice floor, pits
avoided, H.ice62 corner to corner), `H.icePush63` (one SMALL_ICE_BLOCK push with real keys), **`H.fight63`** (H.fight62
plus the shield: a MULLDOZER winding up / charging, or any enemy / projectile closing in faster than 0.5 px a frame
within 72 px, is met with the shield held toward it; a reeling / spinning Mulldozer is swung at), `H.pots63` (lift and
throw every POT, drops picked up), `H.hurtLog63` (logs each hurt's source), `H.pic63`; segments `seg_a63` .. `seg_p63`;
probes `probe_a` .. `probe_g`; `py/ice20.py` / `py/ice20b.py` (BFS over the three ice blocks of $60:20);
`rebuild63.sh audit`; pictures `r63/img`).  Outputs `r27b/out_r63_*.txt`, shots `r27b/shots/*_a63_*` .. `*_n63_*`.
Route source: the decomp (entity_headers.s / transitions.c / room_headers.s for the temple, smallIceBlock.c
sub_0809963C, pushableLever.c, lightDoor.c sub_080850FC, collision.c CollisionDefault, itemUtils.c
CreateRandomItemDrop, pot.c sub_0808288C, chestSpawner.c, bollard.c, beanstalkSubtask.c sub_0801A9F0).
**Cache version: 39, unchanged** -- no re-import.

- [x] **Port divergence fixed: the shield did nothing against the temple's own contact code.**  collision.c
  CollisionDefault: with the shield held, a toucher on the shield's side collides with the shield entity
  (PL_ITEM_SHIELD), Link loses no health (iframes $80); the toucher's OnCollision still runs.  The generic contact code
  (Enemies.lua) has that through Player:blocksFrom, but EnemyToD's `T.touch` (FLYING_POT, the Scissors Beetles' jaws,
  the Big Blue ChuChu's drops, ...) hurt Link without asking -- a shielded Link facing a flying pot lost 2 every time.
  New `ShieldToD63.lua` (+ one anchored line in `EnemyToD.T.touch`): blocked -> the touch counts (the pot shatters),
  SFX $118, no damage.  SIMPLIFIED as in Enemies.lua: the shield's own knockback and its matrix row are not modelled.
- [x] **Checked, not port bugs:** the big-key block ($60:20, SMALL_ICE_BLOCK type 2, melt region = room property 8:
  flag $A2 from the ToD manager, (112,80) 48 x 48, sub_0809963C inclusive) is reachable only in ten pushes using a
  type-0 block as a stopper (BFS `py/ice20b.py`): the port's slide / stop / melt / CreateGroundItemWithFlags all
  behaved; the West Hole's LIGHT_DOOR (flag $4E) is a bridge of SPECIAL_TILE_61 over its pit -- with the lever pushed
  ($4E set: light into $60:20) the room's west half (stairs) is cut off, the lever is pushed back (it toggles) to
  cross; the North Split's re-entry reloads its pots and flying pots; pots with paramA $5F carry ITEM_HEART;
  WSW's alcove underpass is ACT_TILE_41 (SURFACE_DOOR) on layer 1 under the floor (Link hidden, as on the
  cartridge); WSW's west ladder is closed from above by an ACT_TILE_112 block of type $361 (north only:
  sub_0801A9F0) -- a shortcut opened from below; WSW's waterfall face (ACT_TILE_17) is solid on layer 2.
- [x] **Route with real keys** (checkpoints in `r63/ck`): from `r62_r_b1west` -> A **ten ice pushes, the big-key
  block melted -> ITEM_BIG_KEY** (`r63_a_bigkey`) -> C the lever pushed back ($4E cleared, the light bridge back), up
  the stairs -> D the West Hole's last MULLDOZER with H.fight63 (0 hits; 2 shield blocks) -> E North Split
  (`r63_e_split`) -> F **healing the cartridge way**: its four flying pots + four pots, out the south door and back in
  (room reload), 16 passes over two sessions (`r63_f_healed`, `r63_f_healed2`: 2 -> 14) -> G/H the Entrance: the
  SMALL_ICE_BLOCK (8,12) pushed south, the west ice lane, **the BOSS_DOOR opened with the big key** -> the Element
  room $60:08 (`r63_h_element`) -> I its flying pots, the row of pots: four heart pots (`r63_i_hearts`, 44/48) ->
  J its south-west flying pots, the west door -> WaterfallNortheast $60:07 (`r63_j_wfne`) -> K/L down to West
  Waterfall South-west $60:0D, the underpass, the CHEST_SPAWNER type 4: **ITEM_DUNGEON_MAP** (`r63_l_map`) -> M/N the
  water channel (spiked rollers), WaterfallNorthwest $60:06, its ice stairs, its lower water east, NE's lower-left
  channel south -> WSW's river (`r63_n_river`, latest; hp 20/48) -> O the river's BUTTON ($3C; manager $2E sets $3D)
  -> the three BOLLARDs down.  **No health aid on any leg** (no FULLHP / KEEPHP); one death in a probe session
  (F, before the shield fix: not kept).
- Bot / harness notes (not port bugs): a checkpoint reload resets the drop RNG to its seed (deterministic retries);
  the spiked rollers in WaterfallNE's channel hit the swimming bot six times (no dodge while swimming yet); torch-trap
  fire in North Split and a Sluggula / Pesto took the rest; pot drops above 8 health were rupees only (40 pots).
- [ ] **Left / next:** from WSW: West Waterfall South-east $60:0C (LILYPAD_LARGE + Gust Jar, BUTTON $3B, six bollards)
  -> the way to WSW's area warp (56,368) -> LilypadB2West $60:31 -> the B1/B2 lily-pad rooms -> BlueChuChuKeyLever $2E
  / BlueChuChuKey $11 (small key) -> Compass $32 -> ToBlueChuChu $0F (key door) -> the Big Blue ChuChu $10 -> the
  Flame Lantern chest (tile entity type 3, item $0F); the ToD light rays' BG3 is still not drawn (SIMPLIFIED since
  r26); H.fight63 needs a swim dodge (rollers) and earlier flying-pot detection; Kinstone chest 2 ($50:10), the
  swamp's splash drawing, the Minish drown animation, Minish swimming in shallow water.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r63_test.lua` (12 checks on stand-ins: ShieldToD63.blocked by facing / side / shield state,
  its SFX; EnemyToD.T.touch: a shielded front touch counts without damage, from behind / unshielded it hurts; no
  cartridge values).
- **Final check:** all 95 `tests/zelda_tmc_*_test.lua` pass (`r63/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r63/out_a_rooms.txt`, at cache 39).  ObjErrors: **0 per-object errors** in every round-63 session.

## Round 64 (the cartridge's lily-pad route found: the map room -> the river's waterfall gate -> swum down the falls -> LilypadWestB2 / MiddleB2 -> the sunken small key -> up the west ladder -> WaterfallNortheast's key door -> West Waterfall South-east's button -> the big lily pad ridden through $0C / $06 / $07 / $0D and down the falls -> LilypadWestB2 on its own pad; the dive, the falls and the pad's $D0 drop ported)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r64/` (`run.sh` / `go.sh` = round 63's runner with `pre64.lua`
(checkpoints in `r64/ck`, falling back to r63 .. r38) and `lib64.lua`: `H.swim64` (H.swimTo62 + the dive: B when an
enemy / projectile is within 20 px, or within 34 px and closing), `H.lily64` / `H.blow64` / `H.center64` /
`H.drift64`, **`H.ride64`** (steers the big lily pad with charge-1 Gust Jar blows: per axis the speed that just stops at
the target, v = sqrt(2 a d), a = $80/65536; foes within 30 px get a swing), `H.madder64` (the Madderpillar on ice: not
good enough yet), `H.rooms64` (room headers), `H.pic64` (pictures into `r64/img` only); segments `seg_a64` ..
`seg_o64`; probes `probe_a` .. `probe_i`; `rebuild64.sh audit`).  Outputs `r27b/out_r64_*.txt`, shots
`r27b/shots/*_f64_*`, `*_l64_*`.  Route source: the decomp (lilypadLarge.c, lilypadLargeFalling.c, player.c
SurfaceAction_14 / sub_080741C4, playerUtils.c sub_08079C30 / PlayerSwimming / ToggleDiving, asm/src/intr.s (the
collision loop), bollard.c, button.c, lockedDoor.c, bigIceBlock.c, holeManager.c, waterfallBottomManager.c,
entity_headers.s for $06 .. $0D, $2E, $31 .. $35) and a public walkthrough's step order for the temple's middle part.
**Cache version: 39, unchanged** -- no re-import.

- [x] **Port gap fixed: down a waterfall (player.c SurfaceAction_14).**  ACT_TILE_17 is SURFACE_14
  (gMapActTileToSurfaceType, from the ROM): not jumping / z 0 (sub_080741C4), sub_08079C30 (not on a board / the big
  pad; the last surface SURFACE_14, or the same surface at (0,-1), (2,0), (-2,0)) -> sub_0807AABC (collision layer 1),
  sub_08074808, Link moved south at $300 (LinearMoveUpdate, input ignored).  The port let Link stand on the current
  at the top of West Waterfall South-west's falls.  New `Waterfall64.lua` (one anchored line in `Player:update`).
  SIMPLIFIED: Link's sprite does not play the swim stroke on the way down.
- [x] **Port divergence fixed: a diving Link was hit like a swimming one.**  PlayerSwimming: swim_state bit $80 ->
  collisionFlags |= 4 (Link's base collisionFlags 0, so collision type 4); the collision loop (intr.s next_other)
  pairs a toucher with Link only if its collisionMask has bit 1 << type -- the spiked rollers' mask ($0B, ROM
  gProjectileDefinitions byte 15), enemies' bodies, rocks: none has $10.  New `Dive64.lua` (one anchored line each in
  `Enemies.lua`'s contact, `EnemyToD.T.touch`, `FoWObjects` touchLink).  WaterfallNortheast's channel: round 63's six
  roller hits -> **0** with H.swim64's dive (4 dives).
- [x] **Port divergence fixed: the big lily pad's fall in the Temple of Droplets** (lilypadLarge.c sub_08085A98 /
  sub_08085B40): for gArea.locationIndex 27 the drop is $D0 (not $40), Link is held $46 frames (not $0F) and local
  flag $73 is set (LilypadWestB2's own pad, type 1 / type2 $73, is there from then on); landed on ACT_TILE_13 (a pit)
  the pad goes (Action4) and Link falls -> the room's hole manager ($C: whole room -> $60:31 (120,168), from the ROM)
  onto the pad below.  LilypadLarge_Init: in the temple a flagged pad whose flag is clear is deleted (elsewhere
  Action5).  New `LilyFall64.lua` (one anchored line in `Dungeon:lilyDrop`, one in `LilyRide.init`).  SIMPLIFIED:
  LILYPAD_LARGE_FALLING (the copy drawn at the top of the falls) and Action4's growing fade are not drawn.
- [x] **Port divergence fixed: swimming onto the big lily pad.**  LilypadLarge_Action1: Link within 24 px, z 0 ->
  swim_state = 0 (collisionFlags &= $FB): he stands on the pad.  The port left him in the swim state on the pad (no
  Gust Jar).  One anchored line in `Dungeon:updateLily` (Swim.stop).
- [x] **Checked, not port bugs:** the river's BUTTON ($3C -> $3D) lowers the waterfall gate, Link swims down the falls
  into the pit (hole $C) -> LilypadWestB2 $31; its BUTTON ($72 -> $A0) opens the east gate; LilypadMiddleB2 $34's "pot"
  of walls holds a sunken GROUND_ITEM (paramB 8): the dive picks up the **small key**; back in $31 the wall at column
  3 is climbed (ACT $53) to WSW's ladder foot (56,360); the ladder's ACT_TILE_112 block ($361, north only) is pushed
  one tile north from below (it becomes $365) and Link walks round it; WSW's top-left floor -> WaterfallNortheast's
  lower-left floor -> its LOCKED_DOOR type $B (key lock, flag $30; the $06 side's type 9 door is deleted by $30) -> the
  fenced pocket in $06 -> West Waterfall South-east $0C's east strip -> its BUTTON ($3B) -> the six BOLLARDs across the
  pool go down -> the pad.  The Element room's BIG_ICE_BLOCK ($31) closes its east lower door (light later).
  `r63_n_river` was made from `r63_j_wfne` (no dungeon map): round 64's route starts from `r63_l_map` (map in hand).
- [x] **Route with real keys** (checkpoints in `r64/ck`): from `r63_l_map` -> E up the underpass, WaterfallNortheast's
  channel (rollers dived under), $06, down $07's channel -> the river (`r64_e_river`, map in hand) -> F the gate
  button, **swum down the falls** -> the pit -> $31 (`r64_f_b2west`) -> G the rollers (dive), the gate button, east ->
  $34 (`r64_g_b2mid`) -> H **the sunken small key** (`r64_h_key`) -> I back west, up the wall into $0D -> J up the
  ladder, the block pushed, $07's **key door ($30) opened** (`r64_j_door`) -> K the pocket, $0C's button, the bollards
  down, **onto the big lily pad** (`r64_k_pad`) -> L **ridden with 109 Gust Jar blows** $0C -> $06 -> $07 -> $0D ->
  the gate -> the current -> **the $D0 drop, flag $73** -> the pit -> $31 **on its own pad** (`r64_l_b2pad`) -> M
  swim (dive) back east, $34's island BUTTON ($79 -> $A1: the gates at x 312 down) (`r64_m_island`, latest; hp
  26/48).  **No health aid on any leg** (no FULLHP / KEEPHP).  Two deaths in exploration sessions (not kept):
  LilypadEastB2's Madderpillar ($35, tail health 32, on ice) killed the bot twice from 26 hp.
- Bot / harness notes (not port bugs): a checkpoint saved over water reloads Link at the room's entry / a safe spot
  (legs G -> J ran as one session); riding the pad down $31's channel past the roller bar costs hits (the bar spans
  the channel) -- the bot left the pad there and swam (dive); a swimmer within the pad's 24 px is put back on it
  (leave it at > 24 px); the $11 water enemies on $34's island hit Link on land (8 hp).
- [ ] **Left / next:** $35's Madderpillar on ice (heal first: hp 26; H.madder64 must keep clear of the body), its
  north door ($7C) -> the Compass room $32; then the walkthrough's order: back on the pad, $34's north fork ->
  LilypadIceBlocks $28 (chests, the ice-block puzzle onto its switch) -> the dark room -> StairsToScissorsMiniboss
  $25 -> ScissorsMiniboss $05 (three Scissors Beetles) -> the big lever with a Four Sword clone (light melts the
  Element room's ice block) -> HoleToBlueChuchu $0B -> BlueChuchuKeyLever $2E -> BigBlueChuchuKey $11 (small key) ->
  ToBigBlueChuchu $0F (key door $41) -> Big Blue ChuChu $10 -> the Flame Lantern.  Not done this round: the light
  rays' BG3, Kinstone chest 2 ($50:10), the swamp's splash, the Minish drown animation, Minish swimming with the
  Flippers in shallow water.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r64_test.lua` (27 checks on stand-ins: Dive64.skips by mask / definition / not diving;
  EnemyToD.T.touch skips a diver; Waterfall64.frame: carried 3 px south on layer 1, not off the falls / in the air /
  on a pad, the side-point and last-surface rules; LilyFall64: centring, the drop by DROP with the flag, the landing,
  the pad gone on a pit, nothing outside the temple; the temple's Init deletion; no cartridge values).
- **Final check:** all 96 `tests/zelda_tmc_*_test.lua` pass (`r64/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r64/out_a_rooms.txt`, at cache 39).  ObjErrors: **0 per-object errors** in every round-64 session
  (25 sessions).

## Round 65 (the Madderpillar on ice beaten -> the Compass room's chest -> LilypadIceBlocks $28: the east button, the pier chest, the pots -> the dark pit room $29 along its left wall -> StairsToScissorsMiniboss $25 -> ScissorsMiniboss $05 reached; the Madderpillar's per-part contact ported)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r65/` (`run.sh` / `go.sh` = round 64's runner with `pre65.lua`
(checkpoints in `r65/ck`, falling back to r64 .. r38) and `lib65.lua` (+ `lib65b` / `lib65c` / `lib65d`): `H.pic65`,
`H.ents65`, `H.iceKeys65` (one frame of H.ice62's ice steering), **`H.madder65`** (the Madderpillar bot v2: a home
lane point next to the water where the head can only come head-on; the head's path predicted 3..5 frames ahead and
swung at when it will be inside the swing's frame-4..6 box (measured, probe_c); stunned: a BFS on a 4 px grid round
every part to a spot 14 px off the tail, swings while it is open; angry: into the water until calm), **`H.heal65`**
(goal 3: the heal-before-fight step -- a healing bottle, floor drops, the room's pots, grass) with `H.fight65` /
`H.madder65h` wrappers, `H.icePots65` (pots on an ice floor), `H.guard65` (stand and swing at flyers: Pestos),
`H.beetle65` (Scissors Beetles with shield + sword: not good enough yet); segments `seg_a65` .. `seg_k65`; probes
`probe_a` .. `probe_i`; `rebuild65.sh audit`).  Outputs `r27b/out_r65_*.txt`, pictures `r65/img/*.png`.  Route source:
the decomp (madderpillar.c, collision / intr.s arm_CalcCollision, asm/src/player.s sub_08008942 (ice), itemUtils.c
CreateRandomItemDrop, entity_headers.s for $25 / $28 / $29, roomid.h names) and a public walkthrough's step order
(zeldaspalace.com).  **Cache version: 39, unchanged** -- no re-import.

- [x] **Port divergence fixed: the Madderpillar's contact with Link** (madderpillar.c: every part is its own enemy
  entity with its own ROM definition; collision.c arm_CalcCollision).  The round-1 port tested a 12 px square round
  every part: the ROM definitions give the head, segments 1-3 and segments 4-6 / the tail different (smaller) boxes, the
  open tail its gUnk_080FD298 box; the hit now uses Link's ROM hitbox (|d| <= wA + wB), the collision matrix's damage,
  iframes and knockback away from the part, the shield in front (no damage, SFX $118), Dive64's skip, no touch from a
  dying pillar.  New `Madder65.lua` (one anchored line in `BossMadderpillar.update`).  SIMPLIFIED: the closing tail
  keeps its definition's box (gUnk_080FD2A0 not read; the same size on the USA cartridge).
- [x] **Checked, not port bugs:** the ice floor (sub_08008942: ice_velocities 10 a frame, clamp $180, decay 3, the
  jump / carry branches) matches ToDObjects.iceStep; the Madderpillar's head walk / turns / ring / tail timing match the
  decomp; pot drops use CreateRandomItemDrop (Drops.lua) -- 13 pots gave rupees, the $5F pot in $25 a heart (+8).
  The dark pit room $29 ("ROOM_29"): its west pocket (two pots, LIT_AREA) leads north at x 120 to $25; its ice part is
  not on this way.
- [x] **Route with real keys** (checkpoints in `r65/ck`): from `r64_m_island` (hp 34) -> A the Pestos on $34's island
  (-8), east into $35, **the Madderpillar beaten on ice** (H.madder65: 23 swings, 16 tail hits, hp 26 -> 14; flags $7B
  $7C) (`r65_a_madder`) -> B the north door, **the Compass** (big chest, flag $77) (`r65_b_compass`) -> C back through
  $35 / $34, north into $28 (`r65_c_28`) -> D **the east island's BUTTON ($58 -> bollards $9D down)** (`r65_d_btn`) -> E
  up the channel, the north-east islet's six pots (rupees), **the pier chest** (flag $5B) (`r65_e_chest`, hp 10) -> F the
  two Pestos killed (H.guard65) (`r65_f_pots`) -> G the north-west islet's four pots on ice (`r65_g_pots`) -> I swum to
  the north-east passage -> **$29 (dark)**: north along the left wall, its two pots, up at x 120 -> **$25**
  (`r65_i_25`) -> J the floor's two pots (the $5F pot: +8, hp 18), **up the middle stairs (layer 1 -> 2)** -> the exit
  (200,24) -> **ScissorsMiniboss $05** (`r65_j_05`, latest; hp 14/48).  **No health aid on any leg** (no FULLHP /
  KEEPHP).  Deaths in exploration sessions (not kept): F (the Pestos on the pier, hp 10), the first $29 try (pit falls
  on the bot's way to a pot), K twice (the three Scissors Beetles from 14 hp: H.fight63, then H.beetle65).
- Not the walkthrough's way: the block puzzle onto $28's west button and the lily pad round the room were skipped --
  the north-east passage was reached swimming (the port allows it; the cartridge was not checked on this point).
- [ ] **Left / next:** ScissorsMiniboss $05 -- three Scissors Beetles (20 hp each, the sword does 2) from 14 hp:
  more health first (Link has an empty bottle; drops at health <= 8 favour hearts), H.beetle65 to hit only bodies whose
  jaws are away and to keep the shield toward returning jaws; then the warp tile, the big lever with a clone (the light
  melts the Element room's ice block) -> $0B -> $2E -> $11 -> $0F (key door $41) -> Big Blue ChuChu $10 -> the Flame
  Lantern.  Not done: the light rays' BG3, Kinstone chest 2, the swamp's splash, the Minish drown animation, Minish
  swimming in shallow water, $28's ice-block puzzle.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r65_test.lua` (20 checks on stand-ins: the box test, each part's definition box, the open
  tail's box, reach per part, the matrix's damage / iframes / knockback, hit type $6B's row, iframes / shield / dying /
  diving / blown-up parts, the fallback without ROM hitbox data, no cartridge values).
- **Final check:** all 97 `tests/zelda_tmc_*_test.lua` pass (`r65/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r65/out_a_rooms.txt`, at cache 39).  ObjErrors: **0 per-object errors** in every round-65 session.

## Round 66 (the three Scissors Beetles beaten -> the big lever with a clone (the light melts the Element room's ice block) -> IceCorner / IcePitMaze -> $0F -> $0B's stairs -> $2E / $11 levers -> the small key -> the key door $41 -> the Big Blue ChuChu beaten -> the Flame Lantern; the jaws' contact ported, the ToD tile memory fixed)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r66/` (`run.sh` / `go.sh` with `pre66.lua` (checkpoints in `r66/ck`,
falling back to r65 .. r38), `lib66.lua` .. `lib66e.lua`: **`H.beetle66`** (bait the jaws into a snap from 40+ px in
front, step out of the flight lane after the snap's last re-aim, strike the body from behind while the jaws are away;
every frame a BFS on a 4 px grid over a hazard-depth map: bodies, attached jaws (+ snap reach), the flying jaws' next
20 frames, the lane; inside a hazard the nearest clear cell first), `H.reach66`, `H.cross66`, `H.mash66`,
`H.lever66` (PUSHABLE_LEVER either way, a sideways tap against the corner slide), `H.stairs66`, round 17's
`H.fightChuchu17` loaded alone (`lib66e`); segments `seg_k66` .. `seg_y66`; probes `probe_a` .. `probe_v`;
`rebuild66.sh` (`audit` = audit only); `doc66.md`).  Outputs `r27b/out` files `r66_*`, pictures `r66/img`, real-app
shots `r27b/shots/*_k66_*`, `*_n66_*`, `*_x66_*`, `*_y66_*`, `*_pv_beetles*`.  Route source: the decomp
(scissorsBeetle.c, mandiblesProjectile.c, collision.c CollisionDefault / CalculateDamage, intr.s arm_CalcCollision,
gameUtils.c ModHealth, bigPushableLever.c, beanstalkSubtask.c (SPECIAL_TILE_82..89), bigIceBlock.c, warpPoint.c,
lightDoor.c, entity_headers.s for $05 / $08 / $09 / $0A / $0B / $0F / $10 / $11 / $2E) and two public walkthroughs'
step order (zeldaspalace.com, zeldauniverse.net).  **Cache version: 40** (r35.bin gains `Beetle66.FLY_HB`, hitbox.c
gHitbox_0 at $080FD150); the harness cache, the real-app cache (`r27b/appdata/LOVE/tmc_bugs1`) and the test cache
re-imported.

- [x] **Port divergences fixed: the Temple of Droplets' Scissors Beetle jaws** (new `Beetle66.lua`, anchored hooks in
  `EnemyToD.lua` T.jaws / jawAttack / JawImpl): the flying jaws now take gHitbox_0 (read from the ROM) instead of a
  1 x 1 box; contact is arm_CalcCollision's box test with Link's ROM hitbox; MandiblesProjectile_OnCollision case 4:
  any contact (Link, his shield, his sword) sends them home and costs ModHealth(-2) -- on top of the matrix's damage
  for Link himself; a shield block (CollisionDefault, org = the shield) gives Link iframes $80; Link touching idle
  jaws (action 1) starts the snap (sub_080AA320); sub_080AA2E0's sight cone is Direction8Round(dir + 4) and the snap's
  states Direction8Round(dir + 4) >> 2 / DirectionRound(...) >> 2 (the round-26 port added 2: the cone and the bite
  were 22.5 degrees off).  The overworld beetles (EnemyField1, team A) already had the cone / snap / ModHealth right.
  SIMPLIFIED: the sword's own recoil from the jaws (orgKnockback 40 / 12, iframes 240) is not modelled.
- [x] **Port bug fixed: ToDObjects' remembered tiles** were wiped by the room init (`ToDObjects.roomInit` ran after
  the room's own objects had remembered their tiles), so a melted BIG_ICE_BLOCK left its SPECIAL_TILE_34 / 117-124
  behind -- $60:11's chest stayed boxed in.  The memory is now per loaded room (anchored edit in `remember` /
  `roomInit`).
- [x] **Checked, not port bugs:** the beetle body (walk / turn / snap hold $50 / re-aim every 16 / circle), the jaws'
  flight (64 frames, homing on gUnk_08129D14) and the matrix rows ($02 / $03 against Link 2 damage, the sword 2 on the
  body, none on the jaws); the big lever (SPECIAL_TILE_87 / 88 west, Link's x & $F >= 10 on 88, the clone's tile on
  87); $28's north-east passage: the water between the north-west islet and the passage is deep water (ACT $10) up to
  the shallows ($0A) before the doorway ($29) in the ROM's own tile data, and swimming there is PlayerSwim's normal
  rule with the Flippers -- round 65's swim is the cartridge's way too (the lily pad is the alternative), no change.
- [x] **Route with real keys** (checkpoints in `r66/ck`): from `r65_j_05` (hp 14) -> K **the three Scissors Beetles
  beaten** (H.beetle66, 1 hit taken: hp 14 -> 12, flags $2E $9C) (`r66_k_scissors`) -> L the south door -> IceCorner
  $09 (`r66_l_09`) -> M west onto the Element room's east ledge (`r66_m_08`) -> N **the Four Sword split on the clone
  tiles** ((440,184), the clone at +8 / +16), Link on SPECIAL_TILE_88, the clone on 87, both west -> **the big lever
  (flag $34)**: LIGHT_RAY 2, $35, the ice block (352,288) melted ($31) (`r66_n_lever`) -> O back through $09 / $05,
  **the WARP_POINT** -> the Entrance (`r66_o_entrance`) -> P the BOSS_DOOR, the lake, through the melted block's gap,
  east -> HoleToBlueChuchu $0B (`r66_p_0b`) -> Q its west part's north door -> $09's lower floor (`r66_q_09low`) -> R
  the ice east -> IcePitMaze $0A (`r66_r_0a`) -> S the ice maze, **in and out of the BLADE_TRAP ring through its gaps**
  -> west -> ToBigBlueChuchu $0F (`r66_s_0f`) -> T north -> $0B's east part -> the stairs -> BlueChuchuKeyLever $2E
  (`r66_t_2e`) -> U the stairs -> BigBlueChuchuKey $11, its lever ($4B off) (`r66_u_11`) -> V up, across the closed
  light hole, $2E's lever ($6C), down, $11's lever again ($4B): the light thaws the BIG_ICE_BLOCK -> **the chest: the
  small key** ($4C) (`r66_v_key`) -> W up twice, round $0B's open hole, south -> $0F's **key door ($41)** -> $10
  (`r66_w_10`) -> X its lever ($46) -> **the Big Blue ChuChu beaten** (round 17's bot: the Gust Jar on its base, the
  sword on its head; hp 12 -> 8) (`r66_x_chu`) -> Y **the big chest: the Flame Lantern** (`r66_y_lantern`, latest;
  hp 8/48).  **No health aid on any leg** (no FULLHP / KEEPHP).  Deaths in exploration sessions (not kept): $0A's two
  Pestos twice (the swoop takes 2 a hit; the kept S leg met none -- luck of the timing: a chained session met them and
  died, H.guard65 / H.beetle66 do not handle Pestos that dive from z 14).
- Not the walkthroughs' way: the Element room was left by the warp and the Entrance's stairs instead of jumping off the
  ledge; $09 / $0A's two Kinstone chests skipped (optional).
- [ ] **Left / next:** $0F's four BIG_ICE_BLOCKs (the Lantern melts them) and its heart pots, the rest of the temple
  with the Lantern (the dark rooms, the other big lever (88,88) flag $36 -> LIGHT_RAY 3 -> the frozen Water Element),
  the Big Octorok; the Big Blue ChuChu's electricity (type 4's shock) not checked against chuchuBoss.c; a Pesto dodge
  for the bots; the light rays' BG3, Kinstone chest 2 ($50:10), the swamp's splash, the Minish drown animation, Minish
  swimming in shallow water.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r66_test.lua` (31 checks on stand-ins: the sight cone, the snap states, the box test, flying
  jaws' damage + ModHealth(-2) + home, the shield block ($80, -2), the action-1 snap, iframes / distance / no-ROM
  fallback, the sword on flying jaws once per swing, no flying box without a cache, the per-room tile memory, no
  cartridge values).
- **Final check:** all 98 `tests/zelda_tmc_*_test.lua` pass (`r66/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r66/out_a_rooms.txt`, at cache 40).  ObjErrors: **0 per-object errors** in every round-66 session.

## Round 67 (healed with the pots; the Lantern melts $0F's four ice blocks and the Compass room's three -> LanternScissors $33's three beetles in the dark -> LanternMaze $2B: four torches lit, the bombable wall, MulldozerKey $2F's small key, the key door $63 -> FireBars $2A reached; the Pesto's contact height and the Lantern's contact box fixed)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r67/` (`run.sh` / `go.sh` with `pre67.lua` (checkpoints in `r67/ck`,
falling back to r66 .. r38), `lib67.lua`: `H.lantern67` (the Lantern lit / out on its own button), `H.melt67` (an ice
block: stand beside it, face it with the Lantern lit, hold), `H.torch67` (a torch tile: the stand below / beside it,
face it, hold -- the Lantern's own burn check lights it), `H.clear67` (Mulldozers and Pestos fought with round 63's
`H.fight63`, only those inside a BFS reach set), `H.go67` (a guarded walk: an enemy near -> `H.clear67`; a WINDER
segment within 30 px -> the free step farthest from every segment), `H.pestoThreat67` / `H.pestoGuard67` (kept, see
below); segments `seg_a67` .. `seg_n67`, `seg_l2_67` / `seg_l3_67` (healing); probes `probe_a` .. `probe_p`;
`rebuild67.sh`; `tools/ck67.lua` (Fletcher-32 of a ROM range for a RomTablesCat checksum); `doc67.md`).  Outputs
`r27b/r67_*`, pictures `r67/img`, real-app shots `r27b/shots/*_a67_*`, `*_e67_*`, `*_g67_*`, `*_h67_*`, `*_k67_*`,
`*_l67_*`, `*_m67_*`.  Route source: the decomp (entity_headers.s for $0F / $10 / $32 / $33 / $2B / $2F / $2A / $29 /
$25 / $24 / $36 / $08, room.c's tile entities (SMALL_CHEST, BOMBABLE_WALL, DARKNESS), bigIceBlock.c, smallIceBlock.c
sub_0809963C, lightLevelSetManager.c, miscManager.c type 5, playerItemLantern.c, pesto.c, intr.s arm_CalcCollision,
chuchuBoss.c, chuchuBossStartParticle.c, winder.c); the public walkthroughs did not load this round (403 / 404).
**Cache version: 41** (r35.bin gains `Pesto67.HB3D`, hitbox.c gUnk_080FD22C); the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and the test cache re-imported.

- [x] **Port divergence fixed: the Pesto's contact height** (new `Pesto67.lua`, one anchored line in `EnemyToD.lua`'s
  Pesto contact): Pesto_Init sets collisionFlags |= $10, so arm_CalcCollision uses its Hitbox3D depth (gUnk_080FD22C,
  read from the ROM) + Link's 5, and the two touch only when |dz| <= that sum.  The round-26 port let a Pesto at any
  height >= 8 touch Link (a type-1 Pesto at z 48 with its dirt ball, or one risen to 60, hurt him).  A Pesto at its
  hover height (z 16 / 14) does touch Link -- and is in the sword's reach -- as on the cartridge.
- [x] **Port bug fixed: the Lantern's contact box** (anchored edit in `ToDObjects.fireContact`): ItemLantern's hidden
  flame entity clears `hitW` (its 4 x 4 box, playerItemLantern.c width / height 4, is in `.w` / `.h`), so the ice
  blocks met a 6 px half-width; the Lantern's own `.w` is used now.
- [x] **Checked, not port bugs:** the BIG_ICE_BLOCK melt: bigIceBlock.c's (matching) BigIceBlock_Action2 runs to
  SetFlag / action 3 on the contact frame -- the instant melt is the cartridge's; type 1 sets no flag ($32's (104,152)),
  type 0 does ($0F $42-$45, $32 $74 / $75).  The dark rooms' Lantern light (radius $11 -> $48 with the wobble), the
  LIT_AREA windows, LIGHT_LEVEL_SET_MANAGER type 2 (torch lit -> its flag, the light) and MISC_MANAGER type 5 (the
  maze's blocking tiles go after the torch's flag).  **The Big Blue ChuChu's "electricity"**: chuchuBoss.c has no
  shock of its own -- the type-4 forms differ from the green one only in palette ($2C: the parts, the Gust Jar
  particles (ChuchuBossStartParticle type 9: 44 vs 43), the splash) and in sub_080262A8's intro; its damage rows are
  the green one's (base $7D, the helper sub_08026090 $7C; $7E is never set by any path); the port matches.
- [x] **Route with real keys** (checkpoints in `r67/ck`): from `r66_y_lantern` (hp 8/48) -> A north to $0F, the
  Lantern lit, **its four BIG_ICE_BLOCKs melted** ($42-$45), its four heart pots lifted and thrown (hp 8 -> 24)
  (`r67_a_0f`) -> B its stairs (88,88) -> CompassRoom $32 (`r67_b_32`) -> C **the Lantern melts $32's three blocks**
  ($74 / $75; type 1 no flag) (`r67_c_32`) -> I **healing**: $32 <-> $0F by the stairs, $0F's heart pots come back
  each visit (hp 24 -> 48) (`r67_i_healed`) -> D $32's two Mulldozers (shield, sword: no hit) -> east at y 56 ->
  LanternScissors $33 -> E **its three Scissors Beetles in the dark** (H.beetle66; one jaw hit, healed by a drop)
  (`r67_e_33`) -> F its east door ($9F) -> LanternMaze $2B (`r67_f_2b`) -> G the pot at (184,571) lifted, **the torch
  (200,568) lit ($65)** (`r67_g_2b`) -> H **the torch (136,408) ($64)** (hp 48 -> 42) (`r67_h_2b`) -> J **a bomb on
  the BOMBABLE_WALL (24,312) ($60)** -> MulldozerKey $2F (`r67_j_2f`) -> K **its six Mulldozers -> the small key**
  ($6D / $6E, hp 42 -> 26) (`r67_k_key`) -> L back into $2B, **the torches (168,184) ($62) and (40,152) ($61)**
  (`r67_l_2b`, hp 22) -> L2 / L3 **healing**: $2B's heart pot ($5F at (104,155)) and the others, then $2B <-> $2F by
  the bombed wall three times (hp 22 -> 48) (`r67_l2_2b`, `r67_l3_2b`) -> M **the key door (24,104) ($63)** -> west
  into FireBars $2A (`r67_m_2a`, latest; hp 48/48, no small key left).  **No health aid on any leg** (no FULLHP /
  KEEPHP); all healing is pots lifted and thrown with real keys.
- [ ] **Not passed: FireBars $2A** (dark, an ice floor, two WINDERs crawling the lanes between its eight blocks at
  $140, CollisionFire 4 damage / 30 iframes, two Mulldozers): four sessions died between the east door and the west
  exit (y 75-115, x 0-48) -- the bot's ice steps are too loose and the Winders sweep every lane; a timed crossing
  (wait until the west Winder is on the top row y 52 moving east, then the y 88 lane to x 44 and out) is next.  The
  pots (one $5F) in Pit $29 and StairsToScissorsMiniboss $25 are right after it.
- [ ] **Pesto dodge for the bots:** with pesto.c's contact (above) a Pesto at hover height is an ordinary target:
  `H.clear67` fights them with `H.fight63` inside a BFS reach set (the maze's later legs took no Pesto hits);
  `H.pestoGuard67` (step off a diving Pesto, swing at a low one) is kept in lib67 but did not help (they circle at
  12-24 px).
- [ ] **Left / next:** cross $2A -> Pit $29 -> StairsToScissorsMiniboss $25 -> west BlockClonePuzzle $23 ->
  FlameBarBlockPuzzle $36 (TILE_CHANGE_OBSERVE_MANAGER $55 opens its west door) -> BlockCloneIceBridge $24 (a
  BIG_ICE_BLOCK $56 for the Lantern; stairs (136,24) up) -> NorthwestStairs $04 -> south through the archway ->
  WaterfallNortheast $07's north-east ledge -> east -> the Element room's north-west ledge -> **the other big lever
  (88,88) flag $36** with a clone -> LIGHT_RAY 3 -> the frozen Water Element / FROZEN_OCTOROK -> the Big Octorok
  ($0E) and the Water Element.  (Read from the rooms' positions and entity lists; not walked yet.)  The light rays'
  BG3, Kinstone chest 2 ($50:10), the swamp's splash, the Minish drown animation, Minish swimming in shallow water:
  not done.  Link's tile box not changed.
- Harness note: a checkpoint saved in a doorway loads Link ~30 px down inside the wall (on layer 2) -- the segments
  now step in before saving.
- Tests: `tests/zelda_tmc_r67_test.lua` (21 checks on stand-ins: the Lantern's box in fireContact (and other fire's
  hitW / 6), a BIG_ICE_BLOCK melting at the Lantern's touch, Pesto67.reaches with a stand-in depth and without a
  table, EnemyToD asking it, the ROM table declared, no cartridge depth in the source, the Big Blue ChuChu's hit
  types, the cache version).
- **Final check:** all 99 `tests/zelda_tmc_*_test.lua` pass (`r67/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r67/out_a_rooms.txt`, at cache 41).  ObjErrors: **0 per-object errors** in every round-67 session
  (25 sessions).

## Round 68 (FireBars $2A crossed with real keys and no hit; Pit $29 -> $25 -> BlockClonePuzzle $23 (three 2 x 2 blocks with one clone) -> BlockCloneButtonPuzzle $22 (ice block + Link + clone on the three buttons, flag $54) -> FlameBarBlockPuzzle $36 (flag $55) -> BlockCloneIceBridge $24 (the BIG_ICE_BLOCK melted, the clone slabs, the 2 x 2 block pushed three times) -> Lanterns $27 (nine torches inside their burn time, flag $57) -> SpikeBar $26 reached; the Winder's CollisionFire burning ported)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r68/` (`run.sh` / `go.sh` with `pre68.lua` (checkpoints in `r68/ck`,
falling back to r67 .. r38), `lib68.lua` (`H.map68` / `H.tiles68` / `H.reach68` room maps, `H.split68` (the split with an
exact clone offset), `H.ice68` (ice mover, loose stop)), `lib68b.lua` (`H.cross68`: a Winder room crossed by predicting
every possible winder.c head path (each random turn branched, 90 frames, the segments 7 frames apart) and waiting /
dodging until the whole route is clear; `H.path68` / `H.safeGo68` (BFS walks round pits, a Pesto's hold mashed off,
`H.swat68` swings at a Pesto / Mulldozer in reach)); segments `seg_a68` .. `seg_l68`; probes `probe_a` .. `probe_i`;
`rebuild68.sh`; `doc68.md`; decomp sources fetched to `r68/decomp`).  Outputs `r27b/r68_*`, pictures `r68/img`,
real-app shots `r27b/shots/*_a68_*` .. `*_l68_*`.  Route source: the decomp (winder.c, collision.c, linkFire.c,
player.c / asm player.s sub_08008942, intr.s arm_CalcCollision, entity_headers.s for $22 / $23 / $24 / $27 / $36,
roomInit.c) and a public walkthrough's step order (zeldaspalace.com: the $24 / $27 steps).
**Cache version: 41** (no new import data this round; nothing re-imported).

- [x] **Checked against the decomp first:** the Winder (winder.c): head direction Random & $18, speed $140, turns only
  when blocked on its side (COL_*_ANY) or at a railing ($20-$3F ahead, gUnk_080B4488), Random & 1 of the two
  perpendiculars; each segment at the one-ahead's oldest of its 8 positions (7 frames apart, the tail 28 behind) --
  the port matches (watched 600 frames in $2A).  Link's ice (sub_08008942): ice_velocities by direction >> 2, the
  clamp $180, decay 3 a frame (not while jumping), x then y moves, off the ice the sine-table velocity (kept when no
  direction) -- matches ToDObjects.iceStep.  The collision matrix gives hitType $73 handler 11 (CollisionFire) against
  hurtType 0 / 1 and NoOp against 2.
- [x] **Port divergence fixed: the Winder's fire sets Link burning** (new `Fire68.lua`, one anchored line in
  `FoWObjects.fireTouch`): CollisionFire's LINK_FIRE type 1 + PL_BURNING (unless busy / Minish / burning / in a cart)
  now goes through R31.contact, the enemies' CollisionFire (damage 4, knockback 12 frames at 384, 30 iframes, the
  flame's $F0 timer, 31 presses end it).  The round-26 port gave only the damage.
- [x] **Port divergence fixed: a burning Link on the ice** (one anchored line in `R31.burnFrame`): PlayerNormal's ice
  branch (v13 = 1) never calls UpdatePlayerMovement, so the burning run (kWalkSpeedBurning, the facing kept with the
  stick released) does not move him on SURFACE_ICE -- only the stick feeds the ice velocity.  `Fire68.iceHold`.
- [x] **Route with real keys** (checkpoints in `r68/ck`): from `r67_m_2a` (hp 48) -> A **FireBars $2A crossed** with
  H.cross68 (east door -> dodges -> the y 104 / 124 lanes -> the west door; no hit) -> Pit $29 (`r68_a_29`) -> B round
  the pits on the ice to the north passage at x 200 (the Pestos swatted, no hit) -> $25 (`r68_b_25`) -> C the
  layer-1 way (east corridor, the y 60 passage, the ice column) to the west door at y 76 -> $23 (`r68_c_23`) -> E
  **BlockClonePuzzle**: the split on its clone tiles (clone 16 below Link), both lean west on the any-way 2 x 2 block
  (one push), a second split (clone 8 left), both lean south on the south-only block (two pushes), west round to the
  passage at x 136 (`r68_e_23`) -> D north into $22 (`r68_d_22`) -> F **BlockCloneButtonPuzzle**: the small ice block
  pushed down and west onto the button (88,152), the other block pushed east out of the bottom lane, the split on the
  clone tiles with the clone 48 px below Link, Link along the lanes round the stone at (21,3) -> Link on (88,56), the
  clone on (88,104): FLAG_AND -> **$54** (`r68_f_22`) -> G / H its south door -> **FlameBarBlockPuzzle $36** (two
  Winders, H.cross68): the north-only block ($361) at tile (10,5) pushed up -> TILE_CHANGE_OBSERVE -> **$55** -> the
  west door -> **BlockCloneIceBridge $24** (`r68_h_24`) -> I a Mulldozer fought (-4), **the BIG_ICE_BLOCK melted by
  the Lantern ($56)**, the split on its clone slabs (clone 16 below), both lean east on the 2 x 2 block three times
  (`r68_i_24`) -> J down between the torches, west up the left stairs (layer 1 -> 2) -> **Lanterns $27**
  (`r68_j_27`) -> K **the nine LIGHT_LEVEL_SET_MANAGER type-3 torches lit in 671 frames** (each burns field_0x36 * 60
  = 720 frames; two tries timed out at 815 / 875 with slower moves) -> **$57**, the west door (`r68_k_27`) -> L west
  -> **SpikeBar $26** (`r68_l_26`, latest; hp 44/48).  **No health aid on any leg** (no FULLHP / KEEPHP).
- Harness notes: a checkpoint saved near a door still loads Link shifted (up to ~30 px, sometimes onto layer 2) --
  the segments step further in before saving; tile changes (pushed blocks) reset when a checkpoint loads (the
  checkpoints after a block puzzle stand past it).  The 8 px maps' edge rows outside the walls read as free.
- [ ] **Left / next:** SpikeBar $26 (water: swim south, then right; the SPIKED_ROLLERS, four Scissors Beetles on
  layer 2) -> the switch for the second warp tile, the bombable top wall -> the two Madderpillars -> right / up ->
  stairs -> the big lever with a clone (light the second half) -> the Big Octorok -> the Water Element (walkthrough
  order; not walked yet).  Round 67's guess ($04 / $07 ledges) was not the way.  The light rays' BG3, Kinstone chest
  2, the swamp's splash, the Minish drown animation, Minish swimming in shallow water: not done.  Link's tile box not
  changed.
- Tests: `tests/zelda_tmc_r68_test.lua` (18 checks on stand-ins: the fire touch -> burning / damage 4 / 30 iframes /
  12 frames / facing, no second fire while burning, Minish declined, iceHold on / off the ice and in the air, the
  burning run kept off the ice and dropped on it, the two hooks, no ROM values in Fire68).
- **Final check:** all 100 `tests/zelda_tmc_*_test.lua` pass (`r68/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r68/out_a_rooms.txt`, at cache 41).  ObjErrors: **0 per-object errors** in every round-68 session.

## Round 69 (SpikeBar $26 crossed under the spiked rollers (dives) -> its four Scissors Beetles -> BombWall $30 (heart pots, bombed top wall flag $71, the button $70 for the second WARP_POINT) -> Madderpillars $2C (both beaten, doors $9E) -> AfterMadderpillars $2D -> BlockCloneIceBridge $24's north stairs -> NorthwestStairs $04 -> WaterfallNortheast $07 -> the Element room's west ledge: the big lever with a clone (flag $36 -> OUGONTEKI_G $37) -> the ice melts -> FROZEN_OCTOROK swallows the Water Element and dives ($9B) -> back by the $30 warp to the Entrance $03 -> down into the Element room's centre -> its south warp region -> BigOcto $0E reached; the Big Octorok fought to its last frozen phase (not beaten yet); FROZEN_OCTOROK ported, five port divergences fixed)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r69/` (`run.sh` / `go.sh` with `pre69.lua` (checkpoints in `r69/ck`,
falling back to r68 .. r38), `lib69.lua` (`H.barTable69` / `H.hitAt69`: the rollers predicted with
FoWObjects.rollerStep on copies; `H.diveKeep69`: dive, surface and re-dive at a safe frame; `H.blk69`), `lib69b.lua`
(`H.beetle69`: beetle66 with water as a wall), `lib69c.lua` (`H.madder69`: madder65 for two Madderpillars),
`lib69d.lua` (`H.octo69`: the Big Octorok bot), segments `seg_a69` .. `seg_s69`, probes `probe_a` .. `probe_m`,
`rebuild69.sh`, `doc69.md`, decomp sources in `r69/decomp`).  Outputs `r27b/r69_*`, pictures `r69/img`, real-app
shots `r27b/shots/*_a69_*` .. `*_s69_*`.
**Cache version: 42** (r35.bin gains FrozenOcto69.ANIM / LEG / LEG2 = frozenOctorok.c gUnk_08123DDC / 08123E18 /
08123E1C, read from the ROM, checksummed); the harness cache, the real-app cache (r27b tmc_bugs1) and the test cache
were re-imported (`rebuild69.sh`).

- [x] **Checked against the decomp:** spikedRollers.c (the port's motion matches: watched 200 frames, +-96 px at
  $100), the collision loop's layer test (intr.s: `this.collisionLayer & other.collisionLayer`), playerUtils.c
  PlayerSwimming / ToggleDiving (dive $78 frames; a diver's collision type 4 is outside the rollers' mask $11),
  madderpillar.c sub_08029F48, specialWarpManager.c, beanstalkSubtask.c ACT_TILE_40 + PlayerRoomExit (player.c),
  frozenWaterElement.c, frozenOctorok.c, octorokBoss.c's rock knock-back (the shield or the sword).
- [x] **Port divergence fixed: list entries with no layer** (new `ToD69.lua`): room.c LoadRoomEntity gives an entry
  without a layer ResolveCollisionLayer; FoWObjects' SPIKED_ROLLERS / WINDER spawners took layer 1 (SpikeBar $26 lies
  on the top map: the rollers were drawn under BG1, invisible).  `ToD69.listLayer` (two anchored lines in
  FoWObjects); in the ToD areas the other list projectiles too (`ToD69.projLayer`, one line in Field: Madderpillars'
  SPIDER_WEBs).
- [x] **Port divergence fixed: the Madderpillar's tile test on its own layer** (BossMadderpillar:free took layer 1;
  in $2C (top map) the two Madderpillars walked through the walls and out of the room).
- [x] **Port divergence fixed: stairs doors (ACT_TILE_40) only when Link is blocked on that side** (sub_08079778;
  `ToD69.stairsBlocked`, one line in Field.doorExit): the 5-frame PLAYER_ROOM_EXIT started 8 px early, so Link coming
  up $24's ice bridge stopped short of the transition at (136,24) and slid back.
- [x] **Port divergence fixed: SPECIAL_WARP regions' normal-size bit is $10** (specialWarpManager.h unk2; the port
  read $04): the Element room's south region (264,414) (bits $11) now takes Link down to BigOcto $0E.
- [x] **Ported: FROZEN_OCTOROK $91** (new `FrozenOcto69.lua`, one line in ToDObjects.spawnFrozenElement): body
  halves (types 0 / 6, scale $A0), four legs, mouth (sub_0809CB70 orbits, the leg wiggle sub_0809CBE4), sub-actions
  0-7 (the element rises and bobs, Ezlo $0B43, two thuds with the shake, $78 frames, thawed gfx $115 / palette $EF,
  the mouth throbbing, the element sucked in and hidden (SFX_ED), the dive south at $C0 past y $1C8, flag $9B, the
  camera back, Ezlo $0B44).  SIMPLIFIED: the sparkles and OCTOROK_BOSS_OBJECT's steam / suck particles not drawn.
- [x] **Route with real keys** (checkpoints in `r69/ck`; the r68_l_26 doorway checkpoint loaded unshifted this time):
  from `r68_l_26` (hp 44) -> A/B **SpikeBar $26**: into the water, dive ($78 frames, re-dived at a predicted safe
  frame) under rollers 1 / 2 to (100,184), out across roller 3's dry strip at a predicted gap, back in and under roller
  4, out at (44,340): **no roller hit** (`r69_b_26`; two Scissors-Beetle jaw hits while surfacing, hp 40) -> C the four
  **Scissors Beetles** (H.beetle69: 10 hp lost, hp 30, `r69_c_26`) -> D south-east water, the east door at y 536 ->
  **BombWall $30** (`r69_d_next`) -> E the Pestos, three heart pots (hp 44), **a bomb on the top wall ($71)**, the
  **button (184,152) -> $70: the second WARP_POINT** (stepping on it once by mistake warped Link to the Entrance $03:
  checked), north -> **Madderpillars $2C** (`r69_e_next`) -> F the Lantern lit, **both Madderpillars beaten**
  (H.madder69; flags $66 / $9E; hp 44 -> 20, `r69_f_2c`) -> G healed on $30's heart pots twice (hp 48, `r69_g_2c`)
  -> H east -> **AfterMadderpillars $2D** (`r69_h_2d`) -> I north -> $24's south end (`r69_i_next`) -> J up the ice
  bridge, **its north stairs -> NorthwestStairs $04** (`r69_j_next`) -> K the Mulldozers (-4), the south door ->
  **WaterfallNortheast $07** (`r69_k_next`) -> L its east door -> **the Element room's west ledge** (`r69_l_08`) -> M
  **the Four Sword split on the clone tiles (88,184), Link on the big lever's top row, the clone below, both push west
  -> flag $36 -> LIGHT_RAY 3 -> OUGONTEKI_G $37** (`r69_m_lever`) -> N **the ice melts, FROZEN_OCTOROK's cutscene ->
  $9B** (`r69_n_08`) -> O back west / north / down the stairs / $24 / $2D / $2C / $30 and **its WARP_POINT -> the
  Entrance $03** (`r69_o_03`) -> P the centre ring -> **down into the Element room's centre** (`r69_p_08`) -> R the
  south corridor -> **the warp region -> BigOcto $0E** (the boss intro, `r69_r_0e`, hp 42) -> S **the Big Octorok**
  (H.octo69): phase 0 (3 rocks back off the shield), phase 1 (the Lantern flame on the frozen tail end -> burning),
  phase 2 (3 more rocks) all done with real keys; **phase 3 (frozen, spinning faster) not finished**: the bot never
  got the flame onto the moving tail end (two runs, hp 14 -> 8-10 when stopped; one variant died).
  **No health aid on any leg** (no FULLHP / KEEPHP).
- [x] Real-app runs (the r27b runtime on the tmc_bugs1 cache, cache 42) with shots: `r27b/shots/134739_pc_26b.png`
  (the rollers now drawn, Link swimming), `143349_n69_sub2.png` (FROZEN_OCTOROK in the melting ice),
  `144330_r69_0e.png` (BigOcto $0E), `142627_m69_melt.png` (the light melting the Water Element's ice).
- [ ] **Left / next:** the Big Octorok's phase 3 (frozen, faster spin: wait for the spin to run down, then the flame
  on the tail end) and phase 4 (charges + patterns; 3 rocks), then the heart container, FOUR_ELEMENTS $AC (the Water
  Element, gUnk_additional_9) and the warp out; the story after the temple.  The bot's phase 2 costs ~24 hp (vacuum /
  rock hits while repositioning).  $2D's east (layer-1) part with the BIG_ICE_BLOCK over a chest (flag $7E) not
  visited.  Still not done: the light rays' BG3, Kinstone chest 2, the swamp's splash, the Minish drown animation,
  Minish swimming in shallow water.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r69_test.lua` (30 checks on stand-ins: listLayer / projLayer, stairsBlocked, the
  Madderpillar's layer, FrozenOcto69's radii / wiggle / polar, SpecialWarp's bit, the hooks, no ROM tables in the
  new module, RomTablesCat entries, cache 42).  Updated: `zelda_tmc_r26b_fowobj_test.lua` (the wall test names its
  winder's layer 1), `zelda_tmc_r26b_todobj_test.lua` (the frozen element's child may now be FrozenOcto69's).
- **Final check:** all 101 `tests/zelda_tmc_*_test.lua` pass (`r69/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r69/out_a_rooms.txt`, cache 42).  ObjErrors: **0 per-object errors** in every round-69 session.

## Round 70 (the Big Octorok beaten with real keys (all five phases, hp 42 -> 32, no aid) -> FOUR_ELEMENTS $AC: the Water Element -> the heart container (max 48 -> 56) -> the WARP_POINT to the Entrance $60:03 -> the entrance light (TEMPLE_OF_DROPLETS_MANAGER 6) -> Lake Hylia: Link grows out of the PT_TOD portal, script_CutsceneOrchestratorAfterToD + script_KingGustafHologram, the map hint; the parts' contact, the flame box, the fade mask, LoadMenu's map hint and PL_SPAWN_9 ported)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r70/` (`run.sh` / `go.sh` with `pre70.lua` (checkpoints in `r70/ck`,
falling back to r69 .. r38), `lib70.lua` (`H.pic70`, `H.octoBoss70`, `H.hurt70`: the hurt source among the boss's
parts), `lib70b.lua` (`H.octo70`: the Big Octorok bot; `H.octoRest70` runs the frozen spin down on copies of the tail
chain (sub_08036FE4 + sub_08036AF0), `H.octoLeft70` = the frames left in the attack), segments `seg_a70` .. `seg_e70`,
probes `probe_a` .. `probe_i`, `rebuild70.sh` (room audit), `doc70.md`, decomp sources in `r70/decomp`).  Outputs
`r27b/r70_*`, pictures `r70/img`, real-app shots `r27b/shots/*_a70_*` .. `*_d70_*`.
**Cache version: still 42** (no import change: the map-hint bits are read from the pause-menu data the cache already
holds).

- [x] **Checked against the decomp, phase by phase:** octorokBoss.c (AimTowardsPlayer: frozen window 0..31, angular
  speed +1 / +2 a frame in phases 1 / 3 up to $280; Attack_Type2_0 resets it to $100 and sub_08036FE4 runs the spin
  down by 1 / 2 a frame only while the attack lasts -- in phase 3 the tail end rests only for the end of a FREEZE
  attack and the 10 frames of WaitForAttack; sub_08036AF0 the frozen chain, joints within $10; the TAIL_END contact
  test (contactFlags & $7F) == 7; Hit_SubAction0-6, Burning, SetAttackTimer, the phase-4 patterns / charges, the dark
  room's constant charging), octorokBossProjectile.c, octorokBossObject.c (type 4 brings the light back after $30C
  frames), playerItemLantern.c, collision.c CollisionDefault, entitySpawnManager.c, fightManager.c, warpPoint.c,
  templeOfDropletsManager.c type 6, roomInit.c (LakeHylia_Main, TempleOfDroplets_BigOcto), the AfterToD /
  KingGustafHologram / PlayerAfterToD scripts, kingGustaf.c, script.c LoadMenu, subtaskMapHint.c, player.c
  PlayerMinish (PL_SPAWN_9).  The port's spin, attack timing and the frozen chain matched.
- [x] **Port divergence fixed: the parts' contact with Link** (new `Octo70.lua`, one line in BossOctorok): the boss's
  touchLink hurt Link for 1 on a tgtDamage-0 part (the legs, hit type $60: CollisionDefault only knocks him back,
  iframes s8 240 = -16), used +5 / +6 instead of Link's hitbox (offset 0,-3, 6 x 6), ignored the shield, and hit Link
  while swallowed or being spat out (the vacuum clears ENT_COLLIDE before sub_080792BC).  Phase 2 cost the round-69
  bot ~24 hp; now 0-4.
- [x] **Port divergence fixed: the Lantern on the tail end** (Octo70): the flame's 4 x 4 box against the tail end's
  own 16 x 16 definition box (|d| <= wA + wB), not a 16 px square round its centre.
- [x] **Port divergence fixed: SetFadeMask** (new `Fade70.lua`; Script C[$39], one line each in Priority.compose and
  Field:drawOverlay): script_KingGustafHologram fades only BG palettes 0-14 ($00007FFF) -- the hologram, Link and the
  text window stay; the port blacked out the whole screen, text included.  SIMPLIFIED: during such a fade the sprites
  are drawn after all BG layers.
- [x] **Port gap fixed: LoadMenu** (new `MapHint70.lua`, one line in Native): SUBTASK_MAPHINT sets gSave.map_hints |=
  gUnk_08128F4C[hint] (Gustaf's hint 2) and shows the world map (the pause menu's map page, which already draws
  save.mapHints).  SIMPLIFIED: closed with START like the pause menu.
- [x] **Port divergence fixed: PL_SPAWN_9** (new `Spawn70.lua`, one line in Field:transitionSwitch): sub_08073C80 makes
  spawn type 9 grow out of the portal (PL_MINISH cleared, ANIM_GROW at gArea.portal_x / y); the port left Link Minish
  on the frozen block (PT_TOD does not let Minish Link grow, deep water all round: stuck).  Plus ComparePlayerAction:
  growing / using a portal is not PLAYER_NORMAL (one line in Script C[$26]).
- [x] **Checked, not port bugs:** a reload in the boss room after the fight has no element (EntitySpawnManager deletes
  itself when LV4_CLEAR is already set -- as on the cartridge; the route plays the fight and the pickup in one
  session); the boss's WARP_POINT goes to the Entrance $60:03 (its EntityData), the way out is the entrance light;
  the freeze breath (hit type $86) only hurts (no freeze handler in the matrix).
- [x] **Route with real keys** (checkpoints in `r70/ck`): from `r69_r_0e` (hp 42) -> A **the Big Octorok**
  (H.octo70): phase 0 three rocks back off the shield, phase 1 the flame on the frozen tail end, phase 2 three rocks,
  phase 3 (spinning faster: Link goes round the boss opposite the front's sweep to where the tail end comes to rest,
  stands on it, the fuse burns), phase 4 (charges dodged out of their lane, falling stones dodged, three rocks) --
  **beaten, hp 32** -> B **FOUR_ELEMENTS $AC: the Water Element** (its text closes, list a: heart container + warp)
  -> **the heart container** (max 56) (`r70_b_element`) -> C the WARP_POINT -> **$60:03** (`r70_c_03`) -> D the
  entrance light -> **Lake Hylia**: Link grows out of the frozen block's portal, Ezlo (TEXT_EZLO_ELEMENTS_DONE),
  King Gustaf's hologram (TEXT_GUSTAF 1-3), the map hint (save.mapHints $20) (`r70_d_lake`, latest; full size on the
  stump).  **No health aid on any leg** (no FULLHP / KEEPHP).  The bot beat the boss in 3 of 5 runs (the two
  failures were before the lane / stone dodges of the final version; that version won its run).
- [ ] **Left / next:** the walk from Lake Hylia to the Elemental Sanctuary (only the Mt. Crenel and Lake Hylia wind
  crests are active; H.travel did not find the way off the lake -- the octoroks hurt the planner) and the Water
  infusion (ITEM_BLUE_SWORD), then the story on.  King Gustaf's alpha blend (layerFXControl $3F40) is drawn opaque.
  Still not done: the frozen octorok's sparkles / steam / suck particles, $2D's ice-block chest ($7E), the light rays'
  BG3, Kinstone chest 2, the swamp splash, the Minish drown animation, Minish swimming in shallow water.  Link's tile
  box not changed.
- Tests: `tests/zelda_tmc_r70_test.lua` (38 checks on stand-ins: the contact verdicts, touchLink (hurt / knock-only /
  no box / swallowed / spat out), the flame box, Fade70's mask, MapHint70, Spawn70, the hooks, no ROM tables, cache 42).
- Real-app shots (r27b runtime, tmc_bugs1 cache): `r27b/shots/173327_a70_tail3.png` (phase 3, the flame at the tail
  end), `173719_a70_burn3.png` (phase 3 burning), `171511_d70_msg3.png` (King Gustaf over the BG-only fade),
  `174014_d70_maphint.png` (the map hint).
- **Final check:** all 102 `tests/zelda_tmc_*_test.lua` pass (`r70/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r70/out_a_rooms.txt`, cache 42).  ObjErrors: **0 per-object errors** in every round-70 session.

## Round 71 (Lake Hylia -> the Ocarina to Mt. Crenel -> down the mountain -> Hyrule Town -> the castle garden past the patrolling guards (ported) -> the north-west ladder -> $43:00 / $43:01 -> the castle -> the Elemental Sanctuary: the Water Element infused, ITEM_BLUE_SWORD, three Links -> out to town -> North Hyrule Field's broken bridge -> the waterfall cave; King Gustaf's blend ported)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r71/` (`go.sh` / `run.sh` with `pre71.lua` (checkpoints in `r71/ck`,
falling back to r70 .. r38), `lib71.lua` (`H.reach71`, `H.mreach71`, `H.holeGuard71`, `H.noSwim71`, `H.danger71`,
**`H.sneak71`**: the stealth walker), segments `seg_c71` .. `seg_r71` (+ round 44's D-G / H-Q kept as `seg_*2_71`),
probes, `rebuild71.sh`, `doc71.md`, garden / sanctuary scripts in `r71/decomp`).  Outputs `r27b/r71_*`, pictures
`r71/img`, real-app shots `r27b/shots/*71*`.  Route order: a walkthrough (Zelda Universe, chapter 9) checked against
the decomp (roomInit.c sub_StateChange_CastleGarden_Main / Sanctuary_Main, guard.c, guardLineOfSight.c, npcUtils.c,
hiddenLadderDown.c, npc4E.c, the garden / sanctuary scripts, diggingCaveEntranceManager.c).
**Cache version: 43** (r35.bin gains Guard71.PATHS / LOS_DIRS / RAY_HB / TR_ABF8) -- the harness cache, the real-app
cache (`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 43 -- **players re-import once**.

- [x] **Port gap fixed: the castle garden's patrolling guards** (new `Guard71.lua`, one line in Field's entity loop):
  guard.c's unscripted GUARD_1 (types 0 .. 3) stood still where the entity list put them (the maze guard at the west
  entrance blocked the only way in) and nobody ever saw Link.  Now sub_08063D44 / sub_08063DC8 / sub_08063E54 with
  npcUtils.c's program runner (sub_0806EE20 / sub_0806EF88, ops 0 .. 8: walk to a point with the direction aimed
  every 9th frame, waits, facings, speed, the loop mark) on the ROM's gUnk_0810F6BC programs, and
  GUARD_LINE_OF_SIGHT (rays every 4th frame along facing * 8 + gUnk_081299C8[i], 18 frames at $800, stopped by
  walls, box gUnk_080FD1E4): a ray on Link -> the guard turns to him, 30 frames, SetRoomFlag($F).  SIMPLIFIED: the
  rays are not entities (never drawn on the cartridge either); the tile test is the room's solid test; talking to
  these guards (action 3) is not ported.
- [x] **Port gap fixed: caught in the garden** (Guard71.registerTransition): script_GuardGarden7 (the garden's NPC4E)
  ends with NPC4E_DoScreenTransition 3; the port's NPC4E transition list had no index 3 (gNpc4ETransitions[3] =
  gUnk_0813ABF8, read from the ROM), so a caught Link stayed put.  Now he is put back at the maze's entrance.
- [x] **Port divergence fixed: King Gustaf drawn opaque** (new `Gustaf71.lua`, one line in Field): kingGustaf.c's
  alphaBlend = (s << 8) | (16 - s), s = ($100 * speed + zVelocity) >> 16 clamped 4 .. 16: invisible until the
  script's SetEntityVelocity -$8000 (after TEXT_GUSTAF 1), fades in to EVA 12 in 12 frames, out with +$10000; drawn
  with the sprite alpha EVA / 16 (EVA + EVB = 16).
- [x] **Checked, not port bugs:** the lake (with Lon Lon Ranch's east enclosure, its caves and the Lake Woods Cave's
  door, which is one way out) is closed on foot -- the cartridge's way off is the Ocarina, and only the Mt. Crenel /
  Lake crests were lit (the town crest has to be touched); the castle's front door is guarded (Vaati holds the
  castle) and the garden's top path is blocked by a scripted guard -- the way is the maze; the NW ladder's 3 x 3 bush
  hole (TILE_TYPE_418 .. 426, ACT_TILE_63 in the centre) is entered from the north through the left strip
  (x 80 .. 87), as gMapTileTypeToCollisionData says; the sword's up-swing probe is (0, -22); the Sanctuary's Water
  list (gUnk_080F5558) needs local $7A.
- [x] **Route with real keys** (checkpoints in `r71/ck`): `r70_d_lake` -> C the Ocarina -> Mt. Crenel's crest
  (`r71_c_crenel`) -> D the crest's ledge (a hole hop, the slope's tektites fought) (`r71_d_slope`) -> round 44's
  rock wall / vine / mountain foot (`r71_d_0603`, `r71_e_0604`, `r71_f_trilby`) -> **Hyrule Town** (`r71_g_town`) ->
  North Hyrule Field -> **the castle garden** (`r71_h_garden`) -> I **through the maze unseen** (H.sneak71: four
  patrolling guards, no catch), the bush over the NW ladder cut (bottom, centre, left strip, top), down the ladder
  -> **$43:00** (`r71_i_43`) -> J its beetles, **$43:01** (`r71_j_4301`) -> K the floor switch, the door -> **the
  castle $80:03** (`r71_k_castle3`) -> the Sanctuary entrance (`r71_k_sanctent`), the hall (`r71_l_hall`) -> **the
  Sanctuary** (`r71_m_sanct`) -> N the pedestal: script_Npc4ESecondSanctuary, **the Water Element infused:
  ITEM_BLUE_SWORD**, local $7B (`r71_n_infused`) -> Q **three Links** (clone tiles (184,520), (200,520), (264,520):
  two clones, PL_CLONING), two on the buttons -> the metal door (`r71_q_door`) -> O out through the castle and the
  garden to **Hyrule Town** (`r71_o_town`, hp 28/56) -> R North Hyrule Field's broken bridge, into the river, swum
  north -> **the waterfall cave $32:15** (`r71_r_cave`, latest).
- **Aids:** no FULLHP / KEEPHP on any leg (56 -> 30 on Mt. Crenel, 28 at the end).  **One flag aid:** local $7A
  (bank 4) put back before the Sanctuary (`seg_m71`): round 44's `r44_n_infused` was saved ~150 frames after the
  first infusion, before script_Npc4ESpawnTextBoard reached SetLocalFlag $7A (replayed from `r44_m_sanct`: the scene
  sets it ~200 frames after the infusion), so every later save lacked it and the Water list could not load.
- [ ] **Left / next:** the waterfall cave's heart piece and its bats (the bot lost 22 hp to them; not kept), the block
  pushes / the bridge lever, the Royal Valley (Lantern, the sign maze, Dampe's Graveyard Key, the crow), the Royal
  Crypt; the town crest; the Lon Lon Ranch cave's 2 x 2 block (three Links).  Still not done: the frozen octorok's
  particles, $2D's ice-block chest ($7E), the light rays' BG3, Kinstone chest 2, the swamp splash, the Minish drown
  animation, Minish swimming in shallow water; talking to the patrolling guards.  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r71_test.lua` (28 checks: Gustaf's blend on a stand-in, the guard program on stand-in
  words (facing, speed, waits, the loop mark, a walk at $80), ops 3 / 8, the hooks, the RomTablesCat entries, no
  number tables, cache 43; with the ROM: the programs' shapes, the ray's box, TR_ABF8 an area warp, the line of
  sight on a stand-in room (seen in front -> room flag $F after 30 frames; a wall stops it), transition 3
  registered).  The r69 / r70 tests' cache check is now "42 or later".
- Real-app shots (r27b runtime, tmc_bugs1 cache 43): `r27b/shots/202417_i71_sneak1100.png` (the maze, a patrolling
  guard), `201946_g71_gustaf.png` (King Gustaf at EVA 12), `201726_q71_three.png` / `201726_q71_buttons.png` (three
  Links, the Blue Sword on B).
- **Final check:** all 103 `tests/zelda_tmc_*_test.lua` pass (`r71/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r71/out_a_rooms.txt`, cache 43).  ObjErrors: **0 per-object errors** in every round-71 session.

## Round 72 (round 44's Sanctuary leg made again without the $7A aid; the waterfall cave (heart piece, three Links push the 3 x 3 block) -> the Royal Valley -> its forest maze (ported) -> Dampe (ported into his house) -> the crow scene and the crow in the tree (ported) -> the key back with the Pegasus Boots -> the gate -> the graveyard's three-Link buttons -> the King's tombstone -> the Royal Crypt $68:08)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r72/` (`go.sh` / `run.sh` with `pre72.lua` (checkpoints in `r72/ck`,
falling back to r71 .. r38), `lib72.lua` (`H.hold72`, `H.swat72`, `H.lift72`, `H.cut72`, `H.reach72`, `H.tiles72`),
`diff72.lua`, segments `seg_a72*` (goal 1) and `seg_b72` .. `seg_m72`, probes, `py/` (ROM reads for checksums and the
formation searches), `rebuild72.sh`, `doc72.md`, `decomp/tmcsrc` (a sparse clone of zeldaret/tmc)).  Outputs
`r27b/r72_*`, pictures `r72/img`, real-app shots `r27b/shots/*72*`.  Route order: a walkthrough (Zelda Universe,
chapter 9) checked against the decomp (roomInit.c, movement.c sub_080AF250, playerUtils.c sub_0807BD14 /
sub_0807BEEC, keyStealingTakkuri.c, graveyardKey.c, script.c, the graveyard scripts, playerClone.c).
**Cache version: 44** (r35.bin gains Valley72.* and Takkuri72.*) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 44 -- **players re-import once**.

- [x] **Goal 1 -- round 71's $7A aid: the leg made again; the full re-chain not done.**  From `r44_m_sanct` with real
  keys: the pedestal, the infusion, and the scene left to run: script_Npc4ESpawnTextBoard sets local $7A itself
  (`r72_a44_infused`).  With $7A set the cartridge behaves differently from round 44's run: script_PlayerTextBoardAppears
  leaves Link on the raised walk at (232,168) and script_NPC4EPreventPlayerLeave (local $7A, Red Sword, no $7D) turns
  him back below y $D0 (TEXT_PANEL_TUTORIAL 8) -- the clone tutorial has to be done on the walk's own pads (216,184) /
  (248,184) (script_08013F94: TEXT_PANEL_TUTORIAL 5, local $7D) (`r72_a44_split`); round 44 had used the floor pads
  because the flag was missing.  Then the floor's pads, the metal door (`r72_a44_door`) and out to Hyrule Town
  (`r72_a44_town`).  `diff72.lua` on `r44_o_town` vs `r72_a44_town`: **2 differences -- playTime and local $7A**.
  NOT done: re-running rounds 45 .. 71 (about 360 checkpoints, ~250 legs; rounds 45 .. 60 carry their own FULLHP aids)
  on top of it; this round's route (from `r71_r_cave`) still descends from round 71's aided chain.
- [x] **Port gap fixed: the Royal Valley's room init and its forest maze** (new `Valley72.lua`, one line in
  Field:spawnRoomEntities, one in Field:adjacentRoom).  sub_StateChange_RoyalValley_Main was missing: the graveyard
  gate stood open (TILE_TYPE_378 .. 381 never laid), the crow / key lists (gUnk_080D90C8 / gUnk_080D9108) and Dampe at
  the gate (gUnk_080D9098) never loaded; SPECIAL_TILE_114 at (7,41) / (7,49), the MAZE_CLEAR arrival sound.  The maze
  ($09:01) had only its south exits: now gArea.unk_0c_0's fake scroll (every other edge scrolls into the maze room
  again, the room's map position moved one room that way), sub_0804C128 / sub_0804C258 (the two step counters on the
  ROM's gUnk_080D9338 / gUnk_080D9340; in from the north = step 7), sub_080AF250 (the room's exits swapped for
  gUnk_08135190, the way out), sub_0804C290 (the step's sign tile from gUnk_080D9348), the secret way's chest
  (gUnk_080D9328, HAKA_01_T0).  sub_StateChange_HouseInteriors2_Dampe: Dampe was missing from his house
  (gUnk_080F2FD4 until DANPEI_TALK1ST, or with the key back (2)).  SIMPLIFIED: AR_HAS_NO_ENEMIES is not applied; the
  fake scroll reloads the room's entities.
- [x] **Port gap fixed: the key-stealing crows and the dropped key** (new `Takkuri72.lua`, one line in Field's entity
  loop): KEY_STEALING_TAKKURI type 3 (the crow on its tree: Init from gUnk_08124132 / 2D / 28; sub_0809E2C4's four
  boxes from gUnk_08124158 / 78 -- PLAYER_BOUNCE with the box's facing drops the key, near without it the crow flies
  after 10 frames, off screen it comes back at gUnk_08124146's next tree), type 1 (the key in its beak), GRAVEYARD_KEY
  ($96, graveyardKey.c types 2 .. 6 from gUnk_08123FB0: the fall, the bounces, FX_DASH + SFX_SECRET, the item and
  HAKA_KEY_FOUND on touch), script.c sub_0807FBD4 (the first crow's flight off screen; the scene stopped there).
- [x] **Port divergences fixed: the crow scene never ended** -- the scene's dropped key (type 5) stood still while
  script_PlayerGetKeyStolen ran (the port's tracked objects wait while a player script runs; the cartridge's entities
  do not): it now steps from the entity loop then; round 27A's sub_0809E0D4 steered the second crow with a 32-step
  direction, so it circled the key's row for ever -- CalculateDirectionFromOffsets is 8-bit (`Takkuri72.dir256`, an
  anchored edit in Story27Town.lua).
- [x] **Checked, not port bugs:** the cave's Keese die to one Blue Sword hit (round 71's bot missed them); the
  graveyard's rocks are TILE_TYPE_85 / 91 rocks (lifted, not cut); the clones keep Link's offset and end at once when
  boxed in, after 30 frames against a wall (playerClone.c) -- the way to the buttons is a tight one; lifted rocks come
  back with the room, so the rocks, the pads and the buttons are one session (`r72_i_pads` is not a resume point).
- [x] **Route with real keys** (checkpoints in `r72/ck`): `r71_r_cave` -> B the bats (one killed), the **heart piece**
  (pieces 1 -> 2), $32:01: **three Links** on (216, 72 / 88 / 104), the 3 x 3 block pushed west three times
  (`r72_b_pushed`) -> the west ladder -> North Hyrule Field (`r72_b_ladder`) -> C north, west into **the Royal Valley**
  (`r72_c_valley`) -> D **the forest maze** N W W N E (the ROM's way, as its signs read), north out (`r72_d_maze`) -> E
  **Dampe: the Graveyard Key** (`r72_e_key`) -> F **the crow scene** (HAKA_KEY_LOST, TEXT_DAMPE 9) (`r72_f_stolen`) ->
  G the Pegasus Boots west into the crow's tree (56,584): the key falls, taken (HAKA_KEY_FOUND, Ezlo's TEXT_DAMPE $A,
  HAKA_KEY_GET) (`r72_g_keyback`) -> H Dampe at the gate: key 2, **the gate opens** (`r72_h_gate`) -> I/K (one session)
  the graveyard's Ghini (a heart: hp 8 -> 16), eight rocks lifted, the pads (22,16) / (23,17) / (25,17), **three Links**
  walked to the three buttons (13,9) / (14,10) / (16,10) (`r72/py/form72f.py`'s way, a pixel or two inside the
  passages) -> the FLAG_AND manager's local $56 -> **the King's tombstone slides** (`r72_k_tomb`) -> L **the Royal
  Crypt $68:08** (`r72_l_crypt`) -> M one of its two Gibdos beaten (`r72_m_room1`, hp 8/56, latest).
- **Aids:** none -- no FULLHP / KEEPHP, no flags (side: eight passes of Dampe's pots gave rupees only, not kept).
  hp 28 -> 22 (bats) -> 8 (the valley's Ghinis) -> 16 (a Ghini's heart) -> 8 (the Gibdos).
- [ ] **Left / next:** the crypt (the second Gibdo and the small key, the mushroom room, the three doors, the moving
  platforms with three Links, the blade-trap room, the fire pits, King Gustaf's Golden Kinstone), Veil Falls, then
  Cloud Tops; health is low (8/56) -- heal before the crypt's fights.  Still not done: the bridge lever, the waterfall
  cave's moat route, the maze's secret chest by its own way, the town crest, the Lon Lon Ranch cave's 2 x 2 block,
  the frozen octorok's particles, $2D's ice-block chest, the light rays' BG3, Kinstone chest 2, the swamp splash, the
  Minish drown animation, Minish swimming in shallow water; the re-chain of rounds 45 .. 71 on `r72_a44_town`.  Link's
  tile box not changed.
- Tests: `tests/zelda_tmc_r72_test.lua` (53 checks: the maze's counters, way-out exits, signs and fake scroll on stand-in
  tables; the valley's init lists and gate, Dampe's house; the crow's Init, boxes, ram, flight and next tree, the key's
  fall and pickup on stand-ins; the hooks, the RomTablesCat entries, no number tables, cache 44; with the ROM: the
  tables' shapes).
- Real-app shots (r27b runtime, tmc_bugs1 cache 44): `r27b/shots/223739_b72_three.png` (three Links at the cave's
  block), `225430_d72_maze0.png` (the maze), `230946_f72_stolen.png` (after the crow scene), `234854_k72_buttons.png`
  (three Links on the graveyard's buttons), `234854_l72_crypt.png` (the Royal Crypt's first room).
- **Final check:** all 104 `tests/zelda_tmc_*_test.lua` pass (`r72/out_tests.txt`); room audit 605 / 605, 0
  mismatching (`r72/out_a_rooms.txt`, cache 44).  ObjErrors: **0 per-object errors** in every round-72 session.

## Round 73 (the Royal Crypt with real keys: the second Gibdo burnt with the Lantern (ENEMY_ITEM's small key, ported), the mushroom fling, the hall's two three-Link button puzzles (FALLING_ITEM keys), the key blocks (ported), the Ropes, the torch room (TORCH_TRAP ported, the FIGHT_MANAGER's Gibdos -> Stalfos), King Gustaf's scene -> the Golden Kinstone -> out to the graveyard)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r73/` (`go.sh` / `run.sh` with `pre73.lua` (checkpoints in `r73/ck`,
falling back to r72 .. r38), `lib73.lua`, segments `seg_a73` .. `seg_n73` (+ `seg_k73b_env`), probes `probe_a` ..
`probe_q`, `py/` (entity lists by address, the clone formation BFS `form73.py` over `room4_codes.txt`, checksums),
`rebuild73.sh`, `doc73.md`).  Outputs `r27b/r73_*`, pictures `r73/img`, real-app shots `r27b/shots/*73*`.
**Cache version: 46** (r35.bin gains TorchTrap73.TIMERS / SPEEDS and Crypt73.TR_1) -- the harness cache, the real-app
cache (`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 46 -- **players re-import once**.

- [x] **Port gap fixed: the Royal Crypt's room init and ENEMY_ITEM** (new `Crypt73.lua`, one entry in R27B.MODULES).
  sub_StateChange_RoyalCrypt_Entrance (TILE_TYPE_786 at (8,4), EnableRandomDrops, gUnk_080E718C / gUnk_080E71AC by
  local $C4 / $C5), sub_StateChange_RoyalCrypt_MushroomPit (EnableRandomDrops), sub_StateChange_RoyalCrypt_KingGustaf
  (gUnk_080E693C until local $32).  enemyItem.c: the item rides the enemy of id type2 within 16 px (PositionRelative
  +4/+1, z - 4), DisableRandomDrops; the enemy gone -> GROUND_ITEM timer 5 with the flag (sub_080A2508), none in range
  -> timer 4 (sub_080A2534).  Before: the entrance's Gibdos carried nothing -- no small key, the crypt was a dead end.
  script_KingGustav's NPC4E_DoScreenTransition 1: gNpc4ETransitions[1] (ROM, "Crypt73.TR_1") added to the port's NPC4E
  list (Link stayed in the crypt).
- [x] **Port gap fixed: the lit Lantern against enemies** (new `Lantern73.lua`, one line in ItemLantern's frame):
  PlayerItemLantern's 4 x 4 hitbox (hurtType 7) now meets enemies through the collision matrix (handlers 1 / 2 skip)
  -> OnCollision $87 -- gibdo.c's burn (action 8, the flames, a Stalfos 60 frames later).  Only the Big Octorok read
  that hitbox before; no Gibdo could be burnt.
- [x] **Port gap fixed: the small-key block** (new `KeyBlock73.lua`, one line in Objects:tryAction): ACT_TILE_113 in
  front + a dungeon key + A / R -> sub_0804B388 (TILE_TYPE_38 / 52, FX_DEATH, ModDungeonKeys(-1)); the block's
  DESTRUCTIBLE_TILE tile entity keeps it open (checked after a reload).
- [x] **Port gap fixed: TORCH_TRAP and TORCH_TRAP_PROJECTILE** (new `TorchTrap73.lua`, one line each in EnemyTraps /
  EnemyPoW): Init from the EntityData copy (tilePos / direction from yPos, flag2 = xPos, flag1 = type2, speed from the
  spritePtr field), actions 1 .. 3, TorchTrap_Reset (gTorchTrapTimerLengths, ROM), the projectile (30 frames, then
  ProcessMovement3 + LinearMoveUpdate; gTorchTrapProjectileSpeeds, ROM).  Round 17 had left them inert.
- [x] **Port divergence fixed: FIGHT_MANAGER and a replaced enemy** (anchored edit in Dungeon.lua): EnemyCopyParams ->
  ReplaceMonitoredEntity -- a burnt Gibdo's Stalfos is watched in its place (the fight ended at the burn before).
- [x] **Checked, not port bugs:** the valley is dark (gArea.lightLevel 0): Ghinis only show to the Lantern
  (sub_0806FD54); the hall's west pit -- the clones ride over the pit at Link's offset, the clone collision bands
  decide the line (x <= 149 over the lower band, x >= 165 past the wall under the floating block, then x <= 162); the
  middle mushroom's flight in $68:07 stops at the block row and drops into the pit (the west one is the way); the
  torch room's torches go out again once the fight's flag ($19) is set (sub_0803D0B0).
- [x] **Route with real keys** (checkpoints in `r73/ck`): `r72_m_room1` -> D the Lantern lit, the second Gibdo burnt
  from behind, its ENEMY_ITEM small key taken (`r73_d_key`) -> E north to $68:07 (`r73_e_room7`) -> F the west mushroom
  pulled, Link flung over the pit, the locked door (`r73_f_room4`) -> G east: the sword charged on the pads (424,344)
  / round the wall / (488,344) / (488,328): three Links walked to the buttons, the FALLING_ITEM key (`r73_g_eastkey`)
  -> H west: three Links from (88,328) / (88,344) / (152,344), Link rides the x 152 FLOATING_PLATFORM, the buttons,
  the second key (`r73_h_westkey`) -> I back over the pit on the platform, both key blocks opened, north
  (`r73_i_room2`) -> J the three Ropes (a heart: hp 2 -> 10), swum north (`r73_j_room1`) -> K the four torches lit,
  the fight (two Gibdos) at 10 hp: **GAME OVER** -> L **CONTINUE** (the cartridge's three hearts, 24 hp, Link at
  saved_status in $68:01) (`r73_l_continue`) -> K again: both Gibdos burnt, both Stalfos beaten, local $19
  (`r73_k_fight`) -> M north to King Gustaf's room (`r73_m_kingroom`) -> N 12 pots (no hearts), the King's scene
  (TEXT_GUSTAF2 1 / 2, **the Golden Kinstone $6D**, Ezlo 3, local $32), gNpc4ETransitions[1] -> the graveyard (240,188)
  (`r73_n_golden`, latest).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  One game over + CONTINUE in the torch room (the cartridge's refill to
  three hearts).  hp 8 -> 6 (D) -> 6 -> 2 (Ropes) -> 10 (a heart) -> 0 (game over) -> 24 -> 16 (K) -> 16.  Side legs
  not on the route: `seg_a73` (the graveyard path's Ghini with the lantern, no drop), `seg_b73` / `seg_c73` (the lower
  valley: Link died to its Ghini / crows twice).
- [ ] **Left / next:** fuse the Golden Kinstone (the cartridge's order) toward Veil Falls / Cloud Tops; health is low
  (16/56).  Not done this round: the bridge lever, the town wind crest, the Lon Lon Ranch cave's 2 x 2 block, the
  frozen octorok's particles, $2D's ice-block chest, the light rays' BG3, Kinstone chest 2, the swamp splash, the
  Minish drown animation, Minish swimming in shallow water; the re-chain of rounds 45 .. 71 on `r72_a44_town`.
  Seen, not chased: a Gibdo's hold while the Lantern's burn state (PL "ext") is on left Link held at hp 0 without a
  game over in one try (`r73_k2` first run).  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r73_test.lua` (49 checks: the crypt's room init and ENEMY_ITEM, the lantern contact, the key
  block, TORCH_TRAP's init / actions / reset on stand-in values; the hooks, the RomTablesCat entries, no number tables,
  cache 46; with the ROM: the tables' shapes, TR_1 leads to the valley).
- Real-app shots (r27b runtime, tmc_bugs1 cache 46): `r27b/shots/101635_d73_key.png` (the entrance after the burnt
  Gibdo's key), `102411_g73_three.png` / `103221_h73_buttons.png` (three Links on the hall's west buttons, the key
  falling), `104925_k73_torches.png` (the torch room after the fight), `104948_m73_king_room.png`,
  `105331_n73_after_king.png` (out at the graveyard with the Golden Kinstone).

## Round 74 (HandlePlayerLife's death check every frame (the Gibdo hold at 0 hp); healed on North Hyrule Field's grass; the north-east rocks bombed -> Veil Falls' bridge: the King's Golden Kinstone fused with the Source of the Flow (the stones' scripts ported) -> the Veil Falls caves -> the climb wall, the Veil Falls Wind Crest (room code ported) -> the caves' upper rooms -> Veil Falls top -> the BIG_VORTEX -> Cloud Tops (the parachute arrival hop ported))

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r74/` (`go.sh` / `run.sh` with `pre74.lua` (checkpoints in `r74/ck`,
falling back to r73 .. r38), `lib74.lua`, segments `seg_a74` .. `seg_q74`, probes `probe_a` .. `probe_r`, `py/ck74.py`,
`rebuild74.sh`, `doc74.md`).  Outputs `r27b/r74_*`, pictures `r74/img` (+ `r71/img/*74*` swim floods), real-app shots
`r27b/shots/*74*`.
**Cache version: 47** (r35.bin gains Veil74.STONE_SCRIPTS) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 47 -- **players re-import once**.

- [x] **Port divergence fixed: no death check outside Player:hurt** (new `Life74.lua`, one line at the top of
  Player:update; one anchored edit in EnemyPoW's Gibdo action 6).  interrupts.c HandlePlayerLife runs
  playerUtils.c sub_08079B24 every PlayerUpdate: health 0 (not PLAYER_MINISHDIE) -> wait while z < 0, else
  sub_08079708 (PL_STATE_DIE).  The port died only inside Player:hurt and a few hand-made checks; gibdo.c
  sub_08037B10 (the bite while held) only called ModHealth: at 0 the Gibdo let go (sub_08037A58) and Link walked on at
  0 hp, and the Gibdo's action 6 re-set Link's "ext" hold every frame (it overrode a "dead" state).  Round 73's "held
  at 0 hp with the Lantern's burn state" was this.  Now: the per-frame check (skipped in a player script /
  transition / game over, while falling, swimming (the water respawn path decides) or in the air), and the hold
  never overrides PL_STATE_DIE.  Bug probe `probe_r` (aid: hp set to 6 by hand; not a route leg) -> the death ->
  the game over 8 frames later.
- [x] **Port gap fixed: the Source of the Flow's stones** (new `Veil74.lua`, one anchored line in Natives40's
  sub_0806DB84): its literal pool ($0806DBEC) is code, outside scripts.bin -- both MINISH_VILLAGE_OBJECT stones got
  script 0, never slid apart, and script_NPC4ESouurceOfTheFlowOpening waited on sync flag $C for ever.  The two
  script words are read from the ROM at import (RomTables "Veil74.STONE_SCRIPTS", checksummed).  After the fusion:
  SetSyncFlag 3, the stones walk $80 west / east, the shake, SFX_SECRET, Ezlo's $0B1F; the door to $33:03 opens.
- [x] **Port gap fixed: Veil Falls had no room code** (Veil74.roomInit, one entry in R27B.MODULES):
  sub_StateChange_VeilFalls_Main / sub_unk1: WINDCREST_VEIL_FALLS clear -> gUnk_080F9304 (the WINDCREST).  The crest
  was never there (windcrests $1101BFFF -> $1301BFFF with real keys).
- [x] **Port divergence fixed: a door's warp deeper than 16 px** (anchored line in Field:doorExit): the area-exit
  search ahead of a door tile now runs to 28 px.  Veil Falls' cave door (280,66) sits 24 px into its doorway; at 16 the
  fallback took the room's north border -- Link went over the cliff straight to Veil Falls top.
- [x] **Port gap fixed: PL_SPAWN_PARACHUTE_FORWARD / _UP** (new `Vortex74.lua`, two lines in Vortex34): PlayerWarp
  sub_0807B144 / sub_0807B178 -- the arrival is a hop (zVelocity 4.0, kGravityRate, jump_status $81 = COL_NONE,
  direction = facing << 2 at $A0: 64 frames, ~40 px).  The port set Link down on the arrival point: the Veil Falls
  vortex's exit (gUnk_0813AD88[1]) is a Cloud Tops hole pad, so Link fell straight back to Veil Falls top.
- [x] **Checked, not port bugs:** Malon's milk (gUnk_080EEA7C) loads only with global INLOCK (and global_progress
  > 3) -- not set on this save, so no milk; North Hyrule Field's top-left plateau (the valley's east border) is a dead
  end from the west (Caves_ToGraveyard's clone tiles are on the east side only) -- the way out of the valley is its
  south border (Trilby, a ledge jump, town); Lon Lon Ranch's Pacci hole (88,120) springs Link onto the north-west
  plateau and on to Veil Falls' bottom, which does not reach the bridge (the bridge is reached from North Hyrule
  Field's north-east after bombing the two TILE_TYPE_375 rocks, as the walkthroughs say); ROCK_CHUCHUs take bombs /
  $1C or the sword with the Rock Breaker only (sword hits do nothing, as rockChuchu.c).
- [x] **Route with real keys** (checkpoints in `r74/ck`): `r73_n_golden` -> A the maze south, the lower valley's
  crows / Ghinis, the south border (`r74_a_trilby`) -> C Trilby's ledge (ACT $2A), Hyrule Town (`r74_c_town`) -> D the
  town's north gate, 39 grass cuts on North Hyrule Field (hp 14 -> 38) (`r74_d_healed`) -> G the two rocks bombed,
  the plateau, the east border (`r74_g_bridge`) -> H **the Source of the Flow fused** ($6D, KINSTONE_SOURCE_FLOW;
  the stones slide to 32 / 80) (`r74_h_fused`) -> I / J the caves $33:03 (Lantern, round the cracks) (`r74_i_cave`,
  `r74_j_room4`) -> K $33:04's pots, out south (`r74_k_ledge`) -> M the climb wall (Grip Ring), **the Veil Falls Wind
  Crest**, the door (280,66) (`r74_m_room1`) -> N the ladder, the upper-left plateau, the door (168,34)
  (`r74_n_room0`) -> O $33:00's bottom path, out south-east (`r74_o_ledge`) -> P the climb to Veil Falls top
  (`r74_p_top`) -> Q **the BIG_VORTEX** (type2 1: TATSUMAKI) -> Cloud Tops $08:02 (400,489) (`r74_q_cloud`, latest).
  Side legs (not on the route): `seg_a74` (`r74_a_nhf`, the dead-end plateau), `seg_e74a` / `seg_f74` (`r74_e_ranch`,
  `r74_f_veil`: the ranch's Pacci hole), `seg_l74` (the rock ChuChus, 101 swings, unbroken).
- **Aids:** none on the route -- no FULLHP / KEEPHP, no flags; no game over.  hp 16 -> 14 (valley) -> 38 (grass) ->
  36 / 34 (keese, a bomb peahat) -> 22 (keese in $33:00) -> 22 at Cloud Tops.  $33:00's chest not opened (keese hits
  broke the stand; the wallet is full).  `probe_r` (bug check) set hp by hand -- not a route leg.
- [ ] **Left / next:** Cloud Tops (the five Mysterious Clouds' golden fusions, the whirlwinds / holes, the cloud
  sharks, the giant whirlwind) -> the Wind Tribe's house -> the Palace of Winds (Roc's Cape).  Not done this round:
  the bridge lever, the town wind crest, the Lon Lon Ranch cave's 2 x 2 block, the frozen octorok's particles, $2D's
  ice-block chest, the light rays' BG3, Kinstone chest 2, the swamp splash, the Minish drown animation, Minish swimming
  in shallow water; the re-chain of rounds 45 .. 71.  Swimming at 0 hp is left to the water-respawn path (the
  cartridge respawns, then dies).  Link's tile box not changed.
- Tests: `tests/zelda_tmc_r74_test.lua` (32 checks: the per-frame death check's cases, the Gibdo release then the
  death, Veil Falls' room init, the arrival hop (64 frames, ~40 px), the hooks, the catalogue entry, cache 47; with
  the ROM: the two stone scripts).  All 106 `tests/zelda_tmc_*_test.lua` pass (`r74/out_tests.txt`); room audit 605 /
  605, 0 mismatching (`r74/out_a_rooms.txt`); ObjErrors 0 in all 21 sessions.
- Real-app shots (r27b runtime, tmc_bugs1 cache 47): `r27b/shots/132438_h74_fused.png` (Link at the Source of the
  Flow), `135009_m74_crest.png` (the Veil Falls Wind Crest), `135126_p74_top.png` (Veil Falls top),
  `135556_q74_cloud.png` (Cloud Tops after the vortex hop).
- Estimates: ~92.6% of the story verified with real input, ~94.4% of the port (old scale).

## Input round (2026-11-18): controls like the Pokemon games, START

- Keyboard / controller / touch reach the game through the Pokemon games' own
  tables (src/core/Input.lua, GamepadMap): Z/Enter/pad A = A (talk / A item),
  X/pad B = B (B item), E/RB = R (roll, lift, the action), Q/LB = L
  (Kinstones), Tab/Back = SELECT (Ezlo), pad Start / numpad Enter = START
  (pause menu). The game's reads already match the cartridge; unchanged.
- Fixed in the runtime (`src/zelda/ZeldaControls.lua`): Escape used to open the
  system menu and never reached the game, so a keyboard without a numeric
  keypad had no START (no pause menu). Escape is START now, as in the Pokemon
  games, and START held 0.5 s opens the system menu (SAVE, OPTIONS, QUIT TO
  LAUNCHER) from anywhere -- a tap is still the cartridge's pause; the guide
  button, SELECT+START held and touch MENU still open it.
- Test: `tests/zelda_input_test.lua`. Kit: `scratch_claude/zelda/input/`.

## Widescreen (2026-11-18)

- Request: "no black bars on the sides of the screen". OURS (the GBA is
  240 x 160): the play field widens to the window's sides, nothing is
  stretched. Runtime side `src/zelda/ZeldaWide.lua` + small hooks in
  `ZeldaRuntime` (`viewSize(scale, wide)`; the HUD / text / menus overlay stays
  the centred 240 x 160; filled rectangles against its edges -- fades, the
  iris, game over, toasts, the credits' backdrop -- continue over the margins).
- TMC: `Game:viewSize` returns the wide field in the field state (not the
  credits); `View.lua` draws it through its zoom path at step 1: the view is
  centred on the cartridge's own camera (camX / camY, room clamping and all
  gameplay unchanged), the rooms around are drawn at their map positions
  (overworld areas, the dungeon floor), elsewhere the room's backdrop colour
  fills the sides; tile-swap rooms (Hyrule Town) use View.drawLayer's
  per-240x160 swaps. BG3 overlays cover the whole field: Cloud34 (Cloud Tops),
  R33 light rays, PathBg37 parallax (the field's width), Bg3 around a lone
  room (`View.screen(f)` = field size + offset from the cartridge camera).
- Option: system menu WIDESCREEN ON / OFF (`options.zelda.game.minishcap.widescreen`,
  default ON). The zoom steps still work on top of it.
- Test: `tests/zelda_widescreen_test.lua`. Kit / shots:
  `scratch_claude/zelda/wide/` (`run.sh minishcap s_tmc.lua <out> [W H]`,
  `shots/tmc_1280x720_*`, `tmc_1920x1080_*`). Left: a lone room smaller than the field (240 px caves,
  houses) shows its backdrop colour at the sides (black in caves); a dungeon room with no room
  beside it on the floor map likewise.

## Round 75 (the festival bell-scene report: four script / menu gaps fixed (WaitForPlayerNormal's framestates, CheckInitPauseMenu's gates, field82 pushes, the map hint's keys), no freeze reproduced in 13 real-runtime variants with the new controls and widescreen; Cloud Tops with real keys: the east chest, cloud 1 fused (pinwheel 1), the north Cloud Piranhas -> the bulge cleared (CLOUD object + room code ported), two more golden Kinstones, the closed west area, cloud 3 fused (pinwheel 3); the NPC4E natives' addresses, scripted whirlwinds and hidden fusers fixed)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r75/` (`go.sh` with `pre75.lua` (checkpoints in `r75/ck`, falling back to
r74 .. r38), `lib75.lua` / `lib75b.lua` (H.whirl75, H.hole75, H.chestUnder75, H.dig75, H.digRow75, H.cloud75, H.ledgeGlide75,
H.steer75), segments `seg_a75` .. `seg_l75`, probes `probe_a` .. `probe_n`, `py/ck75.py`, `rebuild75.sh`; the bell kit
`run.sh` (the REAL runtime at 1280 x 720, widescreen on) + `p75_bell.lua`, `s75_cloud.lua`).  Outputs `r27b/r75_*`,
`r75/out/*`, pictures `r75/img`, real-app shots `r27b/shots/*r75*`.
**Cache version: 48** (r35.bin gains Cloud75.TILES / SPEEDS) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 48 -- **players re-import once**.

- [x] **Bell scene (Pina's stall, script_Npc4EIntroTown) -- the report "Link walks into walls and freezes"**: not
  reproduced.  13 variants in the real runtime (ZeldaRuntime + ZeldaControls, widescreen 1280 x 720) from
  `bell/ck/bell_town`: plain; Escape (= START) at 14 points of the scene; Escape every 7 frames; Escape held 0.5 s (the
  system menu over the scene, RESUME); the pad's Start held (system menu, closed with pad B); a direction held through
  the bell walk (right / down / left, with Escape taps); random keys during the TryOutShield macro; pad buttons mashed.
  All reach MACHI_01_DEMO with Link free and the shield, ObjErrors 0.  The castle garden ceremony and the throne-room
  assembly (bell kit p_garden / p_court) also finish.  Gaps found against the decomp, fixed (new `Bell75.lua`, one-line
  hooks):
  - (a) **WaitForPlayerNormal** ($0807F9A4) waited for state "normal" and no message; the cartridge (script.c) waits only
    on THROW / SWIM / PARACHUTE / FALL / JUMP / USEPORTAL / DIE / TALKEZLO / CAPE / ITEMGET / DROWN / HOLE / CLIMB /
    STAIRS ... and never on the window.  A cutscene trigger met while carrying (SetPlayerIdle locks the throw) waited
    for ever -- a real hang (e.g. the festival's "don't leave" region, script_CutsceneOrchestratorIntroTown).  The
    OrTalkEzlo copy ($0807FA40) listed state names the port never uses; both now read the port's fields.
  - (b) **DisablePauseMenu** (menuDisabled) was never read: START opened the pause menu inside cutscenes.  Now
    CheckInitPauseMenu's gates: no fade, not disabled, health > 0, a sword (gSave.inventory[0]: START does nothing in
    the whole festival intro), control enabled, no player script / macro; GameMain_ChangeRoom re-enables it.
  - (c) **DoPostScriptAction $0A / $0B** (field82 bit 2): HandleEntity0x82Actions -> sub_0806ED78 -> sub_0800445C: a
    scripted NPC with the bit pushes Link out (Pina, Zelda, the kids, townspeople, Cloud Tops' Wind Tribe ...).  The
    port ignored it (those NPCs could be walked through).  The festival tour now walks round them, as on the cartridge.
  - (d) **the map hint** (Subtask_MapHint_1): 60 frames, then A, B or START close it (was START only, with L / R paging).
- [x] **Port gap fixed: Cloud Tops' room code and the CLOUD object** (new `Cloud75.lua`, one entry in R27B.MODULES):
  sub_StateChange_CloudTops_Bottom (KUMOTATSUMAKI / KUMOUE_02_00 / _02 -> sub_0809F814's 3 x 3 tile patch, else the
  bulges' lists gUnk_080DD7E0 / 080DD840), _House (the Cloud Tops Wind Crest, gUnk_080DD364); cloud.c: a bulge waits for
  its room flag (the Cloud Piranhas), holds Link, camera, puffs, the local flag (type2), SFX_11D + the patch, back to
  Link, SFX_SECRET_BIG; type2 0 (after the fifth pinwheel) -> KUMOTATSUMAKI + gUnk_080DD750 (the great whirlwind).  The
  tile table (gUnk_081247D0) and the puff speeds (gUnk_081247C8) are read from the ROM (RomTables, checksummed).
- [x] **Port bug fixed: the NPC4E natives one function off** (Natives40): the USA scripts call $0806DAAC
  (NPC4E_IsKinstoneFused), $0806DAD0 (MakeFuserInteractable), $0806DAE8 (SetPinwheelFlag), $0806DB44
  (IsEveryPinwheelActivated); the port had MakeFuser at $DAAC and SetPinwheelFlag at $DAD0, so every Mysterious Cloud
  set its pinwheel flag on arrival (all five spun, no fusion counted) -- round 74's Cloud Tops save had all five set.
  OURS: a save repair on entering Cloud Tops' bottom tier clears a pinwheel flag whose cloud is not fused.
- [x] **Port gap fixed: a scripted WHIRLWIND** (ENT_SCRIPTED: the hidden whirlwinds, script_HiddenWhirlwind1 / 2) was
  made a bare script holder -- the revealed red whirlwind never lifted Link.  It is a whirlwind now (catches only while
  drawn).
- [x] **Port divergence fixed: hidden fusers** (Kinstone / FuseBubble): the Mysterious Clouds hide their sprite
  (DoPostScriptAction 8) and fuse through their interact box (NPC4E_ChangeInteractableHitbox); the port skipped hidden
  entities and measured only the distance.
- [x] **Route with real keys** (checkpoints in `r75/ck`): `r74_q_cloud` -> A the red whirlwind (776,408) -> Cloud
  Middles (`r75_a_mid`) -> B the east chest (KUMOUE_01_T0, from the half-tile strip under it: golden $65), the rightmost
  hole (`r75_b_bot`) -> C north past a Cloud Piranha (one hit), the red whirlwind (904,280) (`r75_c_mid`) -> D the Mole
  Mitts 3 tiles north through the cloud-stone, west, the hole (824,72) (`r75_d_bot`) -> E **Mysterious Cloud 1 fused**
  ($65), pinwheel 1 (`r75_e_cloud1`) -> F the red whirlwind (824,72), off the ledge into the whirlwind (792,160), glide
  west, the hop up the top-middle cloud's face, the hole (584,64) (`r75_f_north`) -> G **the two north Cloud Piranhas
  beaten -> the bulge cleared** (KUMOUE_02_00) (`r75_g_bulge`) -> H the golden Kinstone under it ($66), the revealed
  whirlwind (584,72) (`r75_h_mid`) -> I the Mole Mitts west through the cloud-stone, the whirlwinds (392,224) ->
  (280,288), a glide into the closed west area (`r75_i_west`) -> J its chest (KUMOUE_01_T2, golden $67)
  (`r75_j_chest`) -> K dug north, the whirlwinds (184,160) -> (280,288) -> (168,416), up against the west cloud's south
  face, the hole (65,325) (`r75_k_west`) -> L past the Lakitu (one hit), **Mysterious Cloud 3 fused** ($67), pinwheel 3
  (`r75_l_cloud3`, latest; golden $66 still in the bag).
- **Aids:** none on the route -- no FULLHP / KEEPHP, no flags; no game over.  hp 22 -> 20 (piranha) -> 28 (drops) -> 27
  (Lakitu).  `probe_m` (a bug probe) placed Link by hand -- not a route leg.
- [ ] **Left / next:** Cloud Tops' clouds 2, 4, 5 (golden $66 is in the bag), the south bulge's piranhas, the shell
  chests, the great whirlwind -> the Wind Tribe's tower (its room code, roomInit.c sub_StateChange_WindTribeTower_*,
  is not ported yet) -> the Palace of Winds.  Divergence noted, not changed: a horizontal Mole Mitts tunnel
  (TILE_TYPE_754, collision 3) is solid to the port's Link box at the dig's lined-up y (tile + 6); the route steps one
  pixel up between digs (Link's box left as it is).  The HUD stays up in cutscenes (DisablePauseMenu also sets
  gHUD.hideFlags).  Round 74's leftovers (swimming at 0 hp, the bridge lever, ...) not done.
- Tests: `tests/zelda_tmc_bell_test.lua` (52 checks), `tests/zelda_tmc_r75_test.lua` (48 checks);
  `zelda_tmc_r40_test` updated to the natives' USA addresses.  Room audit 605 / 605, 0 mismatching; ObjErrors 0 in
  every session.
- Real-app shots (the r75 runtime = ZeldaRuntime at 1280 x 720, widescreen on, tmc_bugs1 cache 48):
  `r27b/shots/152344_r75_bell_plain.png` (the bell scene), `r75_bulge_wide.png` (the cleared bulge),
  `r75_cloud3_wide.png` (Mysterious Cloud 3), `r75_middles_wide.png`.
- Estimates: ~93.0% of the story verified with real input, ~94.7% of the port (old scale).

## Round 76 (game speed measured in the real runtime: TMC's loop is right (59.5 - 60 logic ticks a second, 1.25 px a walking tick = the cartridge's kWalkSpeed); the glide was half speed in Cloud Tops and hopped / landed on layer 2 where the cartridge does not (Glide76); the Wind Tribe tower's room code ported (WindTribe76); Cloud Tops with real keys: the Middle Jagged chest, Mysterious Cloud 2, the south Cloud Piranhas and their golden Kinstone, the T6 shell chest, Mysterious Cloud 4)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r76/` (`go.sh` + `pre76.lua` (checkpoints in `r76/ck`, falling back to r75 ..
r38), `lib76.lua`, segments `seg_a76` .. `seg_p76`, probes `probe_a` .. `probe_r` (+ `probe_ob`), the speed kit `rt/` + `run76.sh`
+ `spd76.lua` (REALDT=1: the real frame dt and main.lua's love.run pacing; VSYNC / CAP / FULLBUF knobs), the real-app run
`s76.lua`, `rebuild76.sh` (audit)).  Outputs `r27b/r76_*`, `r76/out/*`, pictures `r76/img`, real-app shots `r27b/shots/r76_*`.
**Cache version: 48** (unchanged -- no new import data; no re-import needed).

- [x] **Game speed (goal 1), measured.**  `spd76.lua` holds each direction for 2 wall seconds and records Link per logic tick
  (Host:_tick).  Real runtime (ZeldaRuntime, widescreen 1280 x 720, real dt, main.lua's 60 fps pacing): 59.5 - 60.0 ticks a
  second (vsync on or off; at a 30 fps cap 2 ticks a frame, still 59.5 - 60 / s), 1.25 px per moving tick straight = 74.7 px / s
  while moving; update 0.3 - 1 ms, draw 0.5 - 1 ms a frame; a room-change frame ~36 ms (caught up by the accumulator).
  Harness (fixed 1 / 59.7275 per frame): exactly one tick per frame, the same 1.25 px a tick (wall time uncapped, ~225 ticks
  / s).  Cartridge: kWalkSpeed = Q_8_8(1.25) at 16777216 / 280896 = 59.7275 Hz = 74.66 px / s.  TMC's own loop and
  ZeldaRuntime's accumulator are right.  Notes for the shared runtime (not edited, the ALttP agent owns it): Host:update caps
  dt at 0.25 s and runs at most 8 ticks a frame, so a game slows only below ~7.5 fps and drops time after a > 0.25 s hitch.
  The multi-second stalls first seen in the probe were the harness's unbuffered stdout through the PowerShell redirect (gone
  with FULLBUF), not the game.
- [x] **Port bug fixed: the glide in Cloud Tops** (new `Glide76.lua`, three one-line hooks in Whirlwind.lua):
  - sub_08073584 sets super->speed = 0x100 when gArea.locationIndex == 16 (Cloud Tops), else 0x80; the port glided at 0x80
    everywhere -- half the cartridge's speed and range in Cloud Tops.  The location comes from f.curLocation / the area
    header (ROM).
  - sub_0807A2F8 (the hop up a ledge face while gliding) returns 0 at once when gRoomControls.area == 8: no hop in Cloud Tops.
  - the fall at the glide's end keeps the collision layer (the whirlwind set 1); the port took ResolveCollisionLayer, so a
    landing on a hard cloud's rim in Cloud Middles put Link on layer 2, where the room has no collision (he walked over the
    void).  Area 8 keeps the layer; elsewhere (Mt. Crenel, the Fortress of Winds) the old landing stays (verified routes).
  - NOTE: round 75's legs F / I / K used the port-only hop ("the hop up the top-middle cloud's face"); their checkpoints stand
    as states; the cartridge reaches those places by the walkthrough's order.
- [x] **Port gap fixed: the Wind Tribe tower's room code** (new `WindTribe76.lua`, one entry in R27B.MODULES):
  sub_unk3_WindTribeTower_Entrance (KUMOTATSUMAKI + bank-1 KUMOUE_00_CAP_0 -> WARP_EVENT_END),
  sub_StateChange_WindTribeTower_Entrance (local $90, KINSTONE_F's list gUnk_080F61BC, SPECIAL_TILE_114 at (7, 19) / (7, 20)
  until WARP_EVENT_END), _Floor2 (gUnk_080F62E4 before WARP_EVENT_END, gUnk_080F6324 after SORA_ELDER_RECOVER), _Floor3
  (nothing), _Floor4 (local $B1: gUnk_080F6564 / gUnk_080F6584), sub_StateChange_WindTribeTowerRoof_Main
  (LoadStaticBackground(5), LV5_CLEAR's gUnk_080F66AC, AR_ALLOWS_WARP).  SIMPLIFIED: SetWorldMapPos (no port field).  Not
  reached with real keys yet (the great whirlwind needs the fifth pinwheel).
- [x] **Route with real keys** (checkpoints in `r76/ck`): `r75_l_cloud3` -> A the whirlwind (72,328) -> Middles' west area, off
  the south ledge into (168,416), glide (248,504) -> (296,616) -> the T1 island's north rim (`r76_a_midw`, layer 1) -> B the
  Mole Mitts down 2 tiles + 1 east, the Middle Jagged chest KUMOUE_01_T1 from below (golden $67) (`r76_b_t1`) -> C the hole
  (376,712) -> **Mysterious Cloud 2 fused** ($66), pinwheel 2 (`r76_c_cloud2`) -> D the whirlwind (392,904) (`r76_d_mids`) -> E
  the hole (488,920) (`r76_e_bulge`) -> F **the south Cloud Piranhas beaten -> the bulge cleared** (KUMOUE_02_02)
  (`r76_f_bulge`) -> G the golden Kinstone under it ($66), the whirlwind (616,728) (`r76_g_mid`) -> H the T6 shell chest
  KUMOUE_01_T6 (50 shells) (`r76_h_t6`) -> I back: the holes / whirlwinds (608,728) (488,920) (392,904) (376,712) (`r76_i_t1`)
  -> J the Mole Mitts west under T1's rim, north into it (act $41): the ledge jump into (296,616), glide (280,288) -> (392,224)
  -> (544,176) -> (680,232) -> the island of the hole (776,408) (`r76_j_isl`) -> K the hole (`r76_k_bot`) -> L **Mysterious
  Cloud 4 fused** ($67), pinwheel 4 (`r76_l_cloud4`) -> N the red whirlwind, the hole (920,424), the whirlwind (904,280), the
  Mole Mitts north (`r76_n_ne`, latest on the main line; golden $66 in the bag for cloud 5).  Side branch from `r76_h_t6` (the
  walkthrough's order): P off T6's south rim into (616,816), glide onto the south-east-bottom cloud area (P76a ok); the dig east
  at y 920 towards the hidden pit (776,920) stalls (below).
- **Aids:** none -- no FULLHP / KEEPHP, no flags; no game over.  hp 27 -> 26 (Lakitu) -> 25 -> 19 (piranhas) -> 16 (Lakitu,
  piranha) -> 14 (piranha).  Probes only read (two set Link's layer / z for a picture and put them back).
- [ ] **Left / next:** Mysterious Cloud 5 (bottom-right, $66 in the bag).  The connectivity (probe_o / probe_ob: ground and
  air components of Cloud Middles / Bottoms) says its cluster (Middles' south-east island + Bottoms' cloud-5 and south-east-
  bottom islands + the corridor whirlwinds (648,544) (840,584) (904,672)) is entered as the walkthrough does: T6 -> (616,816)
  -> the south-east-bottom cloud area -> dig east through the cloud-stone at y 920 to the hidden pit (776,920) -> Bottoms'
  south-east-bottom island -> (888,920) -> Middles' south-east island -> the hole (824,744).  Blocker: a dug cloud-stone tile
  (coll 3) lets the port's Link box through only at y = row + 5 and Link could not step onto that line there (round 75's
  noted divergence; Link's box not changed).  From `r76_l_cloud4` / `r76_n_ne` T6 is far (the glide chain from (296,616)
  cannot pass T1's hard cloud).  Next round: the tunnel line-up, the branch from `r76_h_t6` (cloud 5, then cloud 4 as the
  walkthrough's loop does) -> the great whirlwind -> the tower (WindTribe76 with real keys) -> the Palace of Winds.  Also
  found, not changed: landing on a cloud rim (act $40 - $43 = SurfaceAction_ConveyerSouth / North / East / West) does not
  push Link off as the cartridge would.  Goal 3's list (HUD in cutscenes, swimming at 0 hp, ...) not done.
- Tests: `tests/zelda_tmc_r76_test.lua` (32 checks); all 109 `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) +
  `zelda_widescreen_test` (101) pass.  Room audit 605 / 605, 0 mismatching.  ObjErrors 0 in every session.
- Real-app shots (the r76 runtime, real dt + 60 fps pacing, 1280 x 720 widescreen, tmc_bugs1 cache 48):
  `r27b/shots/r76_cloud4_wide.png` (Mysterious Cloud 4's island), `r76_island_wide.png` (the island of the hole (776,408)),
  `r76_glide_wide.png` (a real-key glide at 59.7 ticks / s).
- Estimates: ~93.4% of the story verified with real input, ~94.9% of the port (old scale).

## Round 77 (cloud 5 without touching Link's box: the dig's tile logic checked against the decomp (sub_0807B600's edge blending ported, Dig77), the tunnel lined up with real ticks; Mysterious Clouds 5 and 4 fused in the walkthrough's order -> the great whirlwind -> Cloud Tops' top tier -> the Wind Tribe tower (WindTribe76 in play: the door, the elder, the guard) -> the roof's whirlwind -> the Palace of Winds)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r77/` (`go.sh` + `pre77.lua` (checkpoints in `r77/ck`, falling back to r76 ..
r38), `lib77.lua` (r76's helpers + `alignH77`, `stairs77`, `switch77`, `tbText77` / `through77`), segments `seg_a77` ..
`seg_n77`, probes `probe_a` .. `probe_u`, `rebuild77.sh` (cache rebuild + room audit), the real-app kit `rt/` + `run77.sh` +
`s77.lua`, the decomp sources read for the round in `r77/ref` (zeldaret/tmc: playerUtils.c, itemMoleMitts.c, movement.c,
player.s)).  Outputs `r27b/r77_*`, `r77/out/*`, pictures `r77/img`, real-app shots `r27b/shots/r77_*`.
**Cache version: 49** (r35.bin gains Dig77.EDGE_BOTTOM / EDGE_TOP / TOP_ROWS) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 49 -- **players re-import once**.

- [x] **Goal 1 (a): the dig vs the decomp.**  sub_08077130 lines Link up at `y = (y & ~15) | 6` (east / west) or
  `x = (x & ~15) | 8` (north / south) before an ACT_TILE_86 dig -- the port does the same.  sub_0807B600 gives the dug tile
  TILE_TYPE_754 under a top tile (756 when collision 3 is below it, the tile above becoming 756 when it was 754) -- the
  port does the same; gMapTileTypeToCollisionData[754] = 3 (the bottom half solid: an 8-px tunnel under the cloud).
  **Port gap fixed: the edge blending** (new `Dig77.lua`, one hook in ItemMitts.digWall): sub_0807B600's tail --
  sub_0807B55C on the bottom layer at tilePos +- 1 and tilePos - $40 (gUnk_0811C2AC, when the top tile above was a soft wall
  and was cleared) and sub_0807B480 on the top layer around tilePos - $40 (gUnk_0811C2CC + the {type, edges, bits} rows of
  gUnk_0811C2EC) -- the soft walls beside a new tunnel took the edge pieces that open toward it (they kept their old
  types).  The tables are read from the ROM (RomTablesCat, checksummed).  The blending changes types, not the tunnel's
  collision (the walls beside it stay $0F).
- [x] **Goal 1, the cause and the line-up (b).**  The cartridge's tile sensors are gPlayerHitbox ({0, -3, {5, 3, 3, 5}}:
  sub_080085CC tests x +- 5 at y - 6 and y for east / west, x +- 3 at y - 8 and y + 2 for north / south): at the dig's
  y = row | 6 = 918 both east sensors (912, 918) are in the open half -- the cartridge's Link walks the tunnel there.  The
  port's box (y - 5 .. y + 2, NOT changed per the standing rule) fits the 8-px tunnel only at y = row + 5.  With real ticks:
  outside the tunnel one tick up (-1.25) then one tick down-right (+0.88 down, x held by the wall) puts Link on 917.6; inside
  the tunnel after a dig (y 918, embedded) one tick up snaps to 917 (`H.alignH77`).  Divergence noted, box unchanged.
- [x] **Route with real keys** (checkpoints in `r77/ck`; branch from `r76_h_t6`, hp 19 throughout): A off T6's south rim into
  (616,816), glide to the south-east-bottom area, the Mole Mitts east at y 917 through the cloud-stone (2 digs) into the
  hidden pit (776,920) -> Cloud Bottoms' south-east-bottom island (`r77_a_seb`) -> B the whirlwind (888,920) -> Middles' south-
  east island (`r77_b_mse`) -> C the hole (824,744) -> **Mysterious Cloud 5 fused** ($66), pinwheel 5 (`r77_c_cloud5`) -> D the
  whirlwind (824,744), along the 8-px strip north of the cloud-stone to x 904, off the rim into the whirlwind (904,672), glide
  by (840,584) and (648,544) north until the hard cloud's face stops it on the small island west of the hole's island
  (`r77_d_wisl`) -> E the Mole Mitts north twice (row 21 / 20), west along row 20 (6 digs) to the west rim (act $43), off it
  into the whirlwind (520,320), glide by (680,232) onto the island of the hole (776,408) (`r77_e_isl`) -> F the hole -> Cloud
  Bottoms (`r77_f_bot`) -> **Mysterious Cloud 4 fused** ($67), all five pinwheels -> KUMOTATSUMAKI, the big bulge cleared
  (`r77_f_cloud4`) -> G round the pinwheel posts by lanes into the great whirlwind (BIG_VORTEX (488,440)) -> Cloud Tops' top
  tier (`r77_g_top`) -> H west of its hole, Ezlo's remark ($0B22), the tower door -> **the Wind Tribe tower**, WARP_EVENT_END
  set by WindTribe76 (`r77_h_tower`) -> I / J the stairs to floors 2, 3, 4 (`r77_i_f2`, `r77_j_f4`) -> K the elder (NPC $49
  type 4, $2F0B: "You may continue to the roof"), the guard (type 3) talked to steps aside, the stairs -> the roof $31:00
  (`r77_k_roof`) -> L the roof's great whirlwind -> **the Palace of Winds** $70:31 (Ezlo $0B19) (`r77_l_pow`) -> M north
  into $70:30 (`r77_m_r30`, latest).
- **Aids:** none on any route leg -- no FULLHP / KEEPHP, no flags, no game over.  Probes only read.  Two exploratory runs of
  $70:30 (seg_n77, not saved) died: the path planner walked Link off the platforms' sky edges (and the Peahats hit him,
  hp 19 -> 13); no checkpoint came from them.
- Not changed, found: the port's harness `go25` / `stairs66` keep walking after a stair warp (Link chained rooms 1 -> 2 -> 3);
  real-key stairs (`stairs77`) take one floor at a time -- a harness issue, not the game.
- [ ] **Left / next:** $70:30's LIGHTABLE_SWITCH puzzle (one shared flag: lit = the north-south bridges, unlit = the east-
  west ones; the (72,168) switch sits behind the three blocks of the south-west platform; the Peahats; hp 19 / 56 -- heal
  first), then the Palace of Winds on to Roc's Cape.  Goal 3's list (cloud rims' SurfaceAction_Conveyer*, HUD in cutscenes,
  swimming at 0 hp, the bridge lever, the town wind crest, Lon Lon's 2x2 block, frozen octorok particles, $2D's ice-block
  chest, BG3 light rays, Kinstone chest 2, swamp splash, Minish drown / shallow-water swimming) not done.  The rounds 45-71
  re-chain (the hand-set $7A) still stands.
- Tests: `tests/zelda_tmc_r77_test.lua` (15 checks, stand-in tables); all 110 `tests/zelda_tmc_*_test.lua` +
  `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605, 0 mismatching.  ObjErrors 0 in every
  session.  Regression: round 76's dig legs J (T1's tunnel west) and N (the north-east dig) re-run from their checkpoints
  with the blending: both pass.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, real dt, tmc_bugs1 cache 49): `r27b/shots/r77_cloud5_wide.png`
  (Mysterious Cloud 5), `r77_dig_wide.png` (the dig north on the small island, real keys), `r77_tower_wide.png` (the tower's
  floor 4), `r77_vortex_wide.png` (the roof's great whirlwind), `r77_pow_wide.png` (the Palace of Winds' landing).
- Estimates: ~94.6% of the story verified with real input, ~95.0% of the port (old scale).

## Round 78 (healed on $70:31's heart pots; $70:30 solved with real keys: arrows light the LIGHTABLE_SWITCHes across the sky (Arrow78, ported), the Stalfos, the Flying Skulls lifted off the clone tiles, the blue sword's split, three Links push the 3 x 3 block north; $70:2E's floating platforms past the Bombarossas and the solid floating-block rows; $70:2D's grates (Winders, Bob-ombs); $70:2C: the bridge switch by arrow / sword, the Flying Skulls' drops (Skull78, ported), three waves of Wind Wizzrobes -> the chest -> **Roc's Cape**; the HUD hidden in cutscenes (Hud78, ported))

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r78/` (`go.sh` + `pre78.lua` (checkpoints in `r78/ck`, falling back to r77 ..
r38), `lib78.lua` (r77's picture helpers + `mpath78` (the planner keeps Link's box off pit and hot / spike act tiles),
`pots78`, `towardX78`, `skull78`, `bowFight78`, `wizSword78`), segments `seg_a78` .. `seg_t78` (+ `seg_efg78`, `seg_ps78`, the
legs that must run in one visit), probes `probe_a` .. `probe_r`, `rebuild78.sh` (room audit), the real-app kit `rt/` +
`run78.sh` + `s78.lua`).  Outputs `r27b/r78_*`, `r78/out/*`, pictures `r78/img`, real-app shots `r27b/shots/r78_*`.
**Cache version: 49** (unchanged -- the new code reads tables the cache already holds: colmtx.bin, manifest.drops.fxTable;
no re-import).

- [x] **Goal 1: healed with real keys.**  $70:31's two pots of form $5F leave a heart each (BreakPot -> GROUND_ITEM $5F);
  the room reloads them each visit: three visits ($70:31 -> $70:30 -> back) took hp 19 -> 56 (`r78_a_heal`).
- [x] **Port gap fixed: arrows and LIGHTABLE_SWITCH** (new `Arrow78.lua`, one line in LightableSwitch.contact):
  collision.c resolves a player item (org) on an object (tgt) through gCollisionMtx[tgt->hitType * 34 + org->hurtType];
  the switch's hitType $28 row has plain ColSettings at the arrow's hurtType $15 (and the light arrow's $0E) with
  COL_FLAG_8 (the HIT_SWITCH spark): the switch takes CONTACT_NOW and the arrow its contact (gone).  The port only counted
  the sword, a bomb's blast and thrown objects, so an arrow flew through every switch.  The entry is read from the cache's
  colmtx.bin (the player's ROM); $FF handler entries are no contact; IsColliding with the arrow's 4 x 6 / 6 x 4 box, the
  layer bits and |dz| <= 10.  SIMPLIFIED: the HIT_SWITCH spark object is not created.
- [x] **Port gap fixed: the Flying Skull's drop** (new `Skull78.lua`, one line in EnemyFoW's skullBreak):
  sub_0803A0E0 is CreateFx(FX_BONE, sub_0808288C(super, type2, 0, 0)): type2 0 -> $80 (FX_BONE's random-drop row of
  gUnk_0811F960, as a pot's FX_POT_SHATTER), another value -> that GROUND_ITEM, $FF nothing.  The port made the bone only.
  $70:2C's skulls dropped rupees and a heart ($5F) with real keys.
- [x] **Goal 3 (a): the HUD in cutscenes** (new `Hud78.lua`, three lines in Field.lua): script.c DisablePauseMenu (and
  DisablePauseMenuAndPutAwayItems) set gHUD.hideFlags = HUD_HIDE_ALL, EnablePauseMenu sets HUD_HIDE_NONE; ui.c DrawUI then
  erases the hearts / charge bar (bit $10), rupees ($40) and keys ($80), and the A / B / R buttons slide off (bit 1 <<
  type).  The three natives are wrapped (they keep their old effects); hideFlags is its own field (a room change does not
  clear it, unlike gPauseMenuOptions.disabled).  Checked with script_EzloTalkOcarina started by hand in a probe (hidden from
  its DisablePauseMenuAndPutAwayItems to its EnablePauseMenu, 400 frames).  Goal 3 (b), the cloud-rim conveyor push
  (SurfaceAction_Conveyer*), is not done.
- [x] **Route with real keys** (checkpoints in `r78/ck`): A the pots (`r78_a_heal`, hp 56) -> B $70:30: the sword lights
  (392,264), north over the east bridge, south over the west one, the sword unlights (248,280), west to the south-west
  platform (`r78_b_sw`) -> C the bow from the menu, **an arrow east along the bridge row lights (248,280)**, north over
  (120) (`r78_c_nw`) -> D **an arrow east across the gap unlights (280,56)**, the top bridge east (`r78_d_nm`) -> E the two
  Stalfos (sword) -> F the four Flying Skulls lifted off the clone tiles (120 .. 168, 40) and thrown -> G the blue sword's
  split on three clone tiles (two clones), the three Links along row 6 under the 3 x 3 block (ACT_TILE_114), pushed north
  (`r78_g_block`; E-G in one visit, seg_efg78) -> H the top door -> $70:2E (`r78_h_next`) -> I one arrow up the shaft sets
  off the two Bombarossas in the platform's path (`r78_i_mines`) -> J onto the FLOATING_PLATFORM at its low point, west of
  row 31's floating blocks, east of row 28's, west onto the middle landing under row 25 (`r78_j_mid`) -> K the next pass
  up, east of the blocks of rows 12 - 21, west onto the top landing (`r78_k_top`) -> L west -> $70:2D (`r78_l_next`) -> M
  the landing's Stalfos (`r78_m_land`) -> O down the stairs onto the grates (layer 2), north, west -> $70:2C (`r78_o_next`)
  -> P an arrow down from the north-east neck lights (296,360), south over (376), the sword unlights it, west over the
  bridge with the spiked roller away, an arrow east lights it, the south-west platform's skulls (two drops of rupees and
  a heart), north over (120) (`r78_p_nw`, seg_ps78) -> R the region trigger: **three waves of Wind Wizzrobes** (2, 4, 4)
  with the sword from beside them (out of their shot lines), local flag $70 (`r78_r_wiz`) -> T the CHEST_SPAWNER's chest:
  **Roc's Cape** ("Jump with the greatest of ease!") (`r78_t_cape`, latest, hp 4 / 56, arrows 11).
- **Aids:** none -- no FULLHP / KEEPHP, no flags set on the route.  Practice deaths, not kept (no checkpoint from them):
  1 in A (the old planner walked off $70:31's top edge), 1 in P (planned through the north-east neck into the sky), 3 in
  R (the bow-in-line and two sword tries before the planner learned the spike strips).  Harness notes: a checkpoint load
  re-enters the room, so room-local state resets (the bridges' flag $8000, the pushed block, the Bombarossas, the skulls):
  legs that need the state run in one visit (seg_efg78, seg_ps78); D spent two arrows re-toggling after such a load, J / K
  took 4 + 4 hp from respawned mines.  One verification probe (probe_r) cleared global flag $52 to start
  script_EzloTalkOcarina by hand -- not a route leg, its state was not saved.
- Found, explained (not changed): the "unseen" hits on $70:2C's platforms were the ACT_TILE_24 strips (surface $16,
  Hot43: 2 every 24 frames) -- spikes round the chest, the skull field and the south-east platform; correct per the ROM's
  surface table.
- [ ] **Left / next:** the Palace of Winds on from Roc's Cape (hp 4 -- heal first; the cloud stack at (320,224) is the
  cape's first use), the boss key, Gyorg.  Goal 3 (b) the cloud-rim conveyor push; the rest of round 77's list (swimming
  at 0 hp, the bridge lever, the town wind crest, ...).  The rounds 45-71 re-chain (the hand-set $7A) still stands.
- Tests: `tests/zelda_tmc_r78_test.lua` (23 checks, stand-in matrix / fields); all 111 `tests/zelda_tmc_*_test.lua` +
  `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605, 0 mismatching.  ObjErrors 0 in
  every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 49): `r27b/shots/r78_arrow_wide.png` (an arrow
  across $70:30's gap toggles (280,56)), `r78_platforms_wide.png` ($70:2E's middle landing by the floating platform),
  `r78_cape_wide.png` (Roc's Cape's chest opened, the spike strips beside it).
- Estimates: ~95.6% of the story verified with real input, ~95.3% of the port (old scale).

## Round 79 (Roc's Cape's air control from the cartridge (Cape79: velocities, ROM tables, cache 50); a room scroll keeps Link's collision layer (Scroll79: the $70:2C -> $70:2D grate corridor); healed by real re-entries; up $70:2C's cloud stack to floor 2; $70:21 by cape over the gaps and the Bombarossas; $70:22's block field ("down, up, up, right"), the split, the clones' spin lights the four switches (Clone79), the two Spiked Beetles, the shutters -> the fan corridor)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r79/` (`go.sh` + `pre79.lua` (checkpoints in `r79/ck`, falling back to r78 ..
r38), `lib79.lua` (`crop79`, `acts79`, `cape79`, `capeTo79` -- a cape jump steered the way a player does with the new air
control: walk-up frames, then forward / back so the predicted landing meets a target), `lib79b.lua` (the $70:2C pieces),
segments `seg_a79` .. `seg_j79`, probes `probe_a` .. `probe_p` (probe_i / probe_j: a read-only survey of every $70 room,
pictures `r79/img/room_*.png`), `sok*.py` (the block field searched), `cklua.lua` (catalogue checksums), `rebuild79.sh`,
the real-app kit `rt/` + `run79.sh` + `s79.lua`; checkpoints made with the old air control are in `r79/old` (not used)).
**Cache version: 50** (r35.bin gains Cape79.AIR_VEL / AIR_BACK) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 50 -- **players re-import once**.

- [x] **Port gap fixed: Roc's Cape in the air** (new `Cape79.lua`, one line at the end of ItemCape.lua): ItemCape walked
  Link at kWalkSpeed toward the pad and stopped him when it was let go.  The cartridge (player.c PlayerNormal with
  jump_status set -> sub_08008926 / sub_08008942 in asm/src/player.s; DoJump state 1 -> CheckPlayerVelocity): the jump
  starts at vel = the pad's direction * $100 (0 standing), each frame a held direction adds velocities1[dir8] (forward and
  the sides) or velocities3[facing / 2] (the three backward directions), each axis clamped to +-$180, Link moves by the
  velocity, and nothing decays in the air (he keeps flying with the pad let go).  The two tables come from the literal
  pool ($08008A78 / $08008A7C) of the player's ROM.  A standing double jump now carries ~54 px, a running one up to ~134 px
  (before: 120 px either way).  Also ported: the cape pressed in the landing state (jump_status & 7 == 3) starts the next
  jump at once (ItemRocsCape).  SIMPLIFIED: the facing stays the one Link jumped with.
- [x] **Port gap fixed: the collision layer across a room scroll** (new `Scroll79.lua`, two lines in
  Field:transitionSwitch): sub_0807BD14 / Scroll2 only move the camera and Link -- InitializePlayer is not called, so
  collisionLayer is kept.  enterRoom reset it to 1: walking $70:2C's east grate corridor (layer 2) into $70:2D left Link in
  the door's wall on layer 1, unable to go on or back (a practice death came from it).  Warps and mine carts unchanged.
- [x] **Port gap fixed: the clones' swords on switches** (new `Clone79.lua`, one line in LightableSwitch.contact): each
  PLAYER_CLONE's PLAYER_ITEM_SWORD is a player item resolved on objects through gCollisionMtx like Link's own; FourSword only
  copied Link's sword box to the clones for enemies.  $70:22: three Links between the four type-1 switches, one spin ->
  all four lit inside their 16 frames, latched, two Spiked Beetles, the shutters open.
- [x] **Route with real keys** (checkpoints in `r79/ck`; from `r78_t_cape`, hp 4): A a running cape jump east between the
  statues onto the north-east platform, its pots (`r79_a_ne`) -> B west and south by cape, the six Flying Skulls (hp 4 ->
  20) (`r79_b_sw`) -> D (same visit) back up, **out of the east grate door into $70:2D and straight back** (the room
  reloads its pots and skulls), pots + skulls, three such visits: hp 52 / 56 (`r79_d_heal`) -> E **up the cloud stack
  (320,224)**: six jumps in place, the CLOUD_STAIRCASE manager -> floor 2, $70:21's arrival cloud (`r79_e_up`) -> F (same
  visit) a cape hop east onto the floor, a running jump between the statues to the small platform (96 frames, landed 549
  for 552), another over the two Bombarossas to the east corridor -> $70:22 (`r79_f_22`) -> G the block field: (2,11) down
  from (2,10) (Link along the corridor's top rail), (3,10) up, (4,9) up into the sky, (6,9) east (`r79_g_blocks`) -> H the
  blue sword's split on (6,12) (8,12) (10,12), the three Links south through the row-15 gaps to (72 / 104 / 136, 344), one
  spin: the four switches lit and latched (`r79_h_switches`) -> I the two Spiked Beetles (shield flips, sword), the door
  at (200,312) open (`r79_i_beetles`) -> J east through both shutters, Ezlo's gale warning ($0B49) -> the fan corridor
  (`r79_j_fans`, latest, hp 52 / 56).
- **Aids:** none on the route -- no FULLHP / KEEPHP, no flags.  Probes only read (probe_i / probe_j entered every $70 room
  by hand for the survey; nothing saved).  Practice deaths, not kept: 1 in the first heal loop (the scroll put Link on
  layer 1 in $70:2D's door: the Scroll79 gap), 1 in a heal loop started from a checkpoint (the load respawned the skulls
  around Link; the legs then ran in one visit).  Hurt but not kept: 2 hp from a spike column on a landing with the old
  air control.  Harness: a checkpoint load in $70:21 puts Link on the floor at (360,216) (the arrival cloud is not under
  him at load), so E and F ran in one visit.
- Found, not changed: $70:21's two blue Chuchus did not hop into the hole while Link waited on the arrival cloud (600
  frames; the walkthrough says they do) -- not needed for the route, worth a look.  The cracked floor tiles (act $08) of
  $70:22 did nothing under Link.
- [ ] **Left / next:** the fan corridor of $70:22 (fans stop / start; the Cane of Pacci on the hole), then the grates and
  platforms to the next cloud climb, the small-key door, ... the Big Key (top floor $70:01's big chest, flag $34), the two
  big doors, Gyorg Pair.  Goal 3 (the cloud-rim conveyor push) not done; round 77's other list items unchanged.  The
  rounds 45-71 re-chain (the hand-set $7A) still stands.
- Tests: `tests/zelda_tmc_r79_test.lua` (39 checks, stand-in tables); all 112 `tests/zelda_tmc_*_test.lua` +
  `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605, 0 mismatching (after the rebuild
  and again at the end).  ObjErrors 0 in every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, real dt, tmc_bugs1 cache 50): `r27b/shots/r79_cape_wide.png`
  (a running cape glide over $70:2C's gap), `r79_stack_wide.png` (on the third cloud of the stack),
  `r79_switches_wide.png` ($70:22 after the four switches and the beetles).
- Estimates: ~96.0% of the story verified with real input, ~95.6% of the port (old scale).

## Round 80 (Link's tile collision is the cartridge's: sub_080085CC's eight sensors from gPlayerHitbox / sMinishHitbox, CalcCollisionDirectionOLD's 1 px corner slide, LinearMoveDirectionOLD's direction mask, sub_0807A5B8's push-out (Collide80, cache 51); the dug tunnel passes without alignment; $70:22's fan corridor between gusts, a cape jump over the gap, the Cane of Pacci's hole spring over the wall onto the grate walkway -> $70:21's grates)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r80/` (`go.sh` + `pre80.lua` (checkpoints in `r80/ck`, falling back to r79 ..
r38), `lib80.lua` (re-runs of older segments save as `rr80_<name>`; `coll80` (the sensor bits), `mpath80` (mpath62 with Minish
swimming planned like the Flippers), **`mpath80b`** (the planner for the new sensors: a step needs only the sensors on its
side; `H.mpath78` now points to it), `fans80` / `fanIdle80` / `holdUntil80`), segments `seg_a80` (r77 A without
`alignH77`), `seg_d80`, `seg_g80`, `seg_k80` .. `seg_o80`, probes `probe_a` .. `probe_j`, `cklua.lua`, `rebuild80.sh`, the
real-app kit `rt/` + `run80.sh` + `s80.lua`, decomp sources read for the round in `r80/ref` (zeldaret/tmc asm/src
code_08001A7C.s (LinearMoveDirectionOLD, CalcCollisionDirectionOLD), include/player.h; r77/ref has player.s / playerUtils.c)).
Outputs `r27b/r80_*`, `r80/out/*`, real-app shots `r27b/shots/r80_*`.
**Cache version: 51** (r35.bin gains Collide80.HITBOX / HITBOX_MINISH / DIR_MASK) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 51 -- **players re-import once**.

- [x] **Goal 1: Link's tile collision from the cartridge** (new `Collide80.lua`; hooks: Player:blocked / leadFree / moveBy
  (one line each; the old box stays for an older cache or a stand-in player without a field), Cape79.air and
  ToDObjects.iceStep take the collisions once for both axes as sub_08008942 does; 3 RomTablesCat entries; CACHE_VERSION 51).
  - sub_080085CC (before every move, at the CURRENT position): cx = x + offset_x, cy = y + offset_y of entity->hitbox
    (gPlayerHitbox $08114F88, Minish sMinishHitbox $0811BC80, read at import); east (cx + u0, cy +- u1) $4000 / $2000, west
    (cx - u0, ..) $0400 / $0200, south (cx +- u2, cy + u3) $0040 / $0020, north (cx +- u2, cy - u3) $0004 / $0002 -> Link:
    x +- 5 at y and y - 6, x +- 3 at y + 2 and y - 8; Minish: x +- 3 at y + 1 / y - 3, x +- 2 at y + 2 / y - 4.  The table
    order (swim, jump / parachute, Minish, gust jar, carried, beetles) and sub_080086D8's point test (quarters < $10, $FF
    solid, the state's shape table; swimming off SURFACE_SHALLOW_WATER every value < $10 counts as $0F).
  - LinearMoveDirectionOLD: a blocked cardinal move turns into a 1 px a frame slide along the free side
    (CalcCollisionDirectionOLD's bit tests); coll &= gUnk_0800275C[dir] ($0800275C, read at import); x moves only when
    coll & $EE00 == 0, y when coll & $00EE == 0; the full step is taken (a sensor may end inside a wall).
  - sub_0807A5B8 / sub_0807A750 after the move (not swimming / hidden): the centre side points (x +- u0, y + offset_y) for
    a non-vertical move, (x, y + offset_y +- u3) for a non-horizontal one; a solid point walks the mask back to the run's
    edge and moves Link by the difference (pixels 0 / 15 left alone; table order Minish, jump, carried / gust, beetles).
  - What the port did: a feet box x - 4 .. x + 3, y - 5 .. y + 2 tested at the destination, a one-axis snap to the last
    free whole pixel, a +-1 px corner nudge, an "embedded" escape.  Entity blocking (Field:entityBlocks) stays per axis and
    separate (the cartridge keeps entity hitboxes separate).  Ladders keep the port's Climb.enterable exception;
    out-of-room points stay solid (the cartridge wraps at 64 tiles; the edge exits come first).  `H.alignH77` (harness
    only) is retired: the tunnel needs no alignment.
- [x] **Goal 2: verification.**  `tests/zelda_tmc_r80_test.lua` (49 checks, stand-in hitboxes / masks / rooms): sensors,
  point test, slides, masks, push-out, whole moves (a wall, the 8 px tunnel at row + 6 / + 7 and the slides into it from
  row + 1 / + 12, a corner, a 6 px gap Minish passes and Link does not, the cape's shared collisions).  Real-input re-runs
  (checkpoints `rr80_*` / `r80_*`):
  - r77 A (the dug tunnel to cloud 5) **without alignment**: the digs line Link up at y 918 (row | 6), both east sensors in
    the open half; Link walks the tunnel and drops into the hidden pit -> Cloud Bottoms (`r80_a_tunnel`, hp 19 as in r77).
    Changed: the glide's landing (731,974) leaves the east sensors on the cloud-stone's pixel 0, so the planner's start
    cell failed -- one 3-frame step west first (held key).
  - r62 A .. D (swimming, the town stream as Minish, grown at the portal): passes (`r80_d_grown`).  Changed: with the
    cartridge's swim rule land is solid to a swimming Minish, the harness planner needed `mpath80` (planning only); two
    lane stalls on the way, same end.
  - r77 H .. K (the Wind Tribe tower: doors, stairs, the elder, the guard): pass unchanged.
  - r79 E / F (cape: the cloud stack, the jumps over the gaps) pass unchanged; r79 G .. J (the block field, the split, the
    beetles, the shutters) pass after `seg_g80`: the corridor's top rail (Link's north sensors settle in the $0C tile) is
    walked with held keys -- the old planner's all-sensors-free grid had no cell there (`r80_g_blocks`, then
    `rr80_r79_j_fans`, hp 52 as in r79).
  Tests: all 113 `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit
  605 / 605, 0 mismatching (after the rebuild and at the end).  ObjErrors 0 in every session.
- [x] **Goal 3: route with real keys** (from `rr80_r79_j_fans`, hp 52 / 56): K the fans (FAN $9F, one timer: 60 frames
  idle, 240 blowing east; their wind boxes reach only x 272 .. 320) -- up the west strip column in dashes between gusts,
  onto the top strip, a running cape jump east over the sky gap (x 336 .. 367) (`r80_k_topright`) -> L down the right-hand
  corridor to the bottom strip, **the Cane of Pacci west into the hole (280,424)**, walked in: the spring jumps 2 tiles west
  over the wall onto the grate walkway (layer 2) (`r80_l_walkway`) -> M west along the walkway -> **$70:21's lower grates**
  (`r80_m_grate21`, latest, hp 52 / 56).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  Practice, not kept: one fall into the sky in K's first try (a cape jump
  from the wrong row while the fans blew; hp 52 -> 50; the checkpoint came from the later run at 52).  Probes only read.
  The real-app run loads checkpoints without their `.layer` file (Link on layer 1 at $70:21) -- shots only, not route.
- [ ] **Left / next:** $70:21's grates (layer 2): the east section's west rail ($0A, left half) closes it at y 424; the
  FLOATING_PLATFORM (type2 8) shuttles x 96 .. 240 at y 384 between the west and middle sections; the middle section holds
  five rupees; the stairs (tx 4) and the cloud stack (AMBIENT_CLOUDS type 8 at (128,224)) look like the next climb.  How
  the east section reaches the middle one is the next thing to find; then the small-key door, the Big Key ($70:01), Gyorg
  Pair.  Not changed: FourSword's clones still use the old box (their own entity code, not checked); the diagonal walk is
  1.25 * 0.7071 (the cartridge's FixedMul with gSineTable gives $E2 / 256 = 0.883 vs 0.884).
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 51): `r27b/shots/r80_fans_wide.png` ($70:22's fan
  corridor, the fans blowing), `r80_walkway_wide.png` (on the grate walkway after the Pacci spring; real keys south stop at
  its edge, y 446, the south sensors), `r80_grates_wide.png` ($70:21's grates).
- Estimates: ~96.3% of the story verified with real input, ~96.0% of the port (old scale).

## Round 81 ($70:21's grates solved: the square hatches are ROTATING_TRAPDOORs (Trapdoor81, ported: a cape jump on one drops Link under the grates, a jump under one lifts him through); EntityInRectRadius's layer test (a platform no longer carries Link on another layer); the east hatch -> under the grates -> the middle hatch -> section 2's hatch onto the FLOATING_PLATFORM -> the west hatch -> the stairs -> the cloud stack (128,224) -> 3F ($70:16) -> the platform ride to its south-east floor)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r81/` (`go.sh` + `pre81.lua` (checkpoints in `r81/ck`, falling back to r80 ..
r38; re-runs of older segments save as `rr81_<name>`; `lib80b.lua` = lib80 without its rr80 save wrapper), `lib81.lua`,
segments `seg_a81` .. `seg_f81`, probes `probe_a` .. `probe_j` (room dumps in `r81/out/room21_coll.txt` / `room22_coll.txt` /
`room16_coll.txt`, `show.py` prints them), `rebuild81.sh` (audit only this round), the real-app kit `rt/` + `run81.sh` +
`s81.lua` (it now applies each checkpoint's `.layer` file after the load -- round 80's kit did not), pictures `r81/img`
(floor 2 / floor 3 composites)).  Outputs `r27b/r81_*`, `r81/out/*`.  Decomp sources read: the r49 repo
(src/object/rotatingTrapdoor.c, src/playerUtils.c sub_08077F84 / sub_0807A2B8 / sub_0807A8D8, src/player.c
SurfaceAction_1B / sub_08073AD4 / sub_08073924, src/item/itemRocsCape.c, asm EntityInRectRadius, src/object/
floatingPlatform.c, src/manager/holeManager.c) and r70/decomp/entity_headers.s (GratesTo3F, PlatformCloneRide).
**Cache version: 51** (no import change this round; nothing re-imported).

- [x] **Goal 1: how $70:21's east grate section reaches the middle.**  The room data matches the cartridge (one
  FLOATING_PLATFORM, rails 9 / 10 belong to the two Bombarossas, the five rupees + a RUPEE_LIKE lie on layer 1 UNDER the
  middle grates).  The white square frames on the grates are TILE_TYPE_835 .. 838 ($343 .. $346): the hatches of
  ROTATING_TRAPDOOR ($44), which the port did not have.  Four hatches: east (576,384), middle (432,384), section 2
  (240,384), west (96,384); the floating platform shuttles under the last two on layer 1.
- [x] **Port gap fixed: ROTATING_TRAPDOOR** (new `Trapdoor81.lua`, one line at the end of ItemCape.lua):
  sub_08077F84 (the cape's jump on layer 1 with a hatch quarter on the top layer at (x, y - 12): layer 2, jump_status | 8,
  the hatch at (x, y - 12), Link y - 12); sub_0807A2B8 at the landing ((jump_status & $C8) == 0, layer != 1: a hatch at
  Link); RotatingTrapdoor_Init (layer 2, the quarter's offset to the hatch centre, the four top tiles -> $347 .. $34A) /
  Action1 (GetNextFrame, SFX_18B on flag 1, ANIM_DONE -> $343 .. $346 back, deleted); the turning tiles' act $61 ->
  SURFACE_1B (y + 12, z 12 up unless Minish, layer 1) and sub_08073924's $40 fall.  Tile types, act tiles and the
  animation (24 frames) come from the ROM.  SIMPLIFIED: the floor test runs in the hatch's frame (one frame after the
  landing); the Down Thrust's landing hook is not ported.
- [x] **Port gap fixed: EntityInRectRadius's layer test** (FoWObjects' inRect, used by the FLOATING_PLATFORM and the
  MINISH_SIZED_ENTRANCE): the cartridge first tests (a.layer & b.layer & 3) != 0; the layer-1 platform under the grates
  carried Link standing on the grate above it (an entity without a layer counts as both).
- [x] **Route with real keys** (checkpoints in `r81/ck`; A-D in ONE session from `r80_m_grate21`, hp 52 / 56):
  A onto the east hatch, a standing cape jump: the hatch turns, Link drops under the grates (layer 1) (`r81_a_under`) ->
  B south, west along the floor under the grates (one rupee), under the middle hatch, a cape jump: up through it onto
  the middle grates (layer 2) (`r81_b_middle`) -> C west along the corridor onto section 2's hatch, a cape jump timed to
  the platform heading east (x 212): Link drops onto it, rides west to (96,384), a cape jump up through the west hatch
  (`r81_c_west`) -> D north up the stairs (tx 4) to the west floor (the Flying Skulls stay asleep), six jumps up the
  cloud stack (128,224) -> **3F, $70:16** (`r81_d_up`) -> E (from the checkpoint) onto the FLOATING_PLATFORM at its west
  stop from the clone tiles, standing on its west half (x - 20) past the solid column x 400 .. 415, off south at its
  south-west stop (360,216) (`r81_e_ride`, latest, hp 52 / 56).
- **Aids:** none -- no FULLHP / KEEPHP, no flags; probes only read.  No practice deaths.  Harness: a checkpoint load in
  $70:21 / $70:16 does not always put Link where it was saved (`r81_c_west` loaded at (104,312), `r81_d_up` at (168,72)
  for (128,80)): A-D were run as one session; E starts from the load spot, which is on the same arrival floor.
- Regression: r78 J ($70:2E's platform to the middle landing) passes with the layer test; r78 K failed on the arrow at
  the last Bombarossa (it reached the top and blew up; the ride itself carried Link) -- not investigated (timing after
  round 80's collision change; K was not re-run in round 80).
- Found, not changed: under the grates Link and the layer-1 rupees draw OVER the mesh in the real app (the cartridge's
  sub_0807AABC / UpdateSpriteForCollisionLayer put layer-1 sprites under the top BG); $70:16: the lit floor's east part
  is closed from its west part (the stairs, tx 5) by the 3 x 3 clone block (act $72 at tx 7 .. 9, rows 9 .. 11) -- the
  room is "PlatformCloneRide": the six clone tiles (act $57) are at the arrival, so the split is made there and the three
  Links ride the platform (clones keep their offsets, PlayerClone_Action2) to push the block; the lit strip's bottom
  (tx 10 .. 14) is closed on layer 2.
- [ ] **Left / next:** $70:16: the split on the arrival's clone tiles, ride with the clones, push the act-$72 block, the
  west stairs (tx 5) down into $70:18; then 3F -> 4F ($70:1E's stairs -> $70:15), the small-key door, the Big Key
  ($70:01), the two big-key doors, Gyorg Pair.  Goal 3 not done (the Four Sword clones on the Collide80 sensors, the
  cloud-rim conveyor push -- note: the conveyor act tiles $2A .. $2D are also the ledges of gUnk_0811C1E8 --, $70:21's
  blue Chuchus).  The rounds 45-71 re-chain still stands.
- Tests: `tests/zelda_tmc_r81_test.lua` (45 checks, stand-in rooms / animations / objects); all 114
  `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605,
  0 mismatching.  ObjErrors 0 in every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, real dt, tmc_bugs1 cache 51): `r27b/shots/r81_hatch_wide.png`
  (the east hatch turning, Link dropping under the grates), `r81_under_wide.png` (under the grates: the middle hatch,
  the rupees and the Rupee Like), `r81_3f_wide.png` ($70:16, the 3F arrival).
- Estimates: ~96.6% of the story verified with real input, ~96.2% of the port (old scale).

## Round 82 ($70:16 PlatformCloneRide solved: the blue sword's split in a column on the arrival's clone tiles, the three Links ride the FLOATING_PLATFORM, four pushes of the 3 x 3 block west, the west stairs -> $70:18 PlatformCrowRide: the middle block pushed off the ledge falls into the sky (PushBlock82, ported), down the sky by cape jumps between the two columns of platforms -> the island under the grate, up through its hatch -> $70:19 GratePlatformRide (hatch A down onto the platform, up B, down C, up D) -> $70:1A PotPush; the clones' collisions on the cartridge's sensors (Clone82, cache 52); r78 K's failure explained (bot timing))

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r82/` (`go.sh` + `pre82.lua` (checkpoints in `r82/ck`, falling back to r81 ..
r38; re-runs of older segments save as `rr82_<name>`; **the checkpoint's `.layer` is applied before Field.new's safeContinue**,
see below), `lib80b.lua`, `lib82.lua`, `lib82b.lua` (`H.hop82` / `H.hopX82` cape jumps to moving platforms, `H.ride82`, `H.on82`),
segments `seg_a82` .. `seg_j82`, `seg_k82` (r78 K with the bot fixes), probes `probe_a` .. `probe_o` (room dumps in `r82/out`,
`show.py` prints them; floor composites `r82/img/f2.png`, `f3.png` with the room ids), `rebuild82.sh`, the real-app kit `rt/` +
`run82.sh` + `s82.lua` (loads pre82 and runs the segments B, F, H with real keys; no checkpoint written)).  Outputs `r27b/r82_*`,
`r82/out/*`, real-app shots `r27b/shots/r82_*`.  Decomp read: the r49 repo (src/object/playerClone.c, asm/src/player.s
sub_080085B0, src/object/blockPushed.c, asm/src/code_080043E8.s GetTileHazardType / sub_0800442E, asm/src/code_08003FC4.s
CreatePitFallFx .., src/object/lockedDoor.c, src/playerUtils.c SetTileType / the tileIndices fill, include/roomid.h).
**Cache version: 52** (r35.bin gains Clone82.HITBOX and PushBlock82.HAZARDS) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 52 -- **players re-import once**.

- [x] **Goal 1: the route with real keys** (checkpoints in `r82/ck`; hp 52 / 56 throughout the kept runs):
  A from `r81_e_ride` back onto the platform at its south-west stop, ridden east / north / west on its west half, off at
  the west stop onto the clone tiles (`r82_a_back`) -> B the sword equipped on B from the menu (the cape stays on A),
  charged on (12,6), up the column (12,6) -> (12,5) -> (12,4): two clones below Link; the charge held until the platform
  comes west, released at x <= 258: action 5 (800 frames); onto the platform, the ride (the clones keep Link + offset,
  over the sky), off south at (360,216), up the stairs (tx 16-17, layer 2), west along row 14, north along tx 10, the
  three Links lean on the block: **four pushes west** (corner $36C tx 7 -> 3), 61 frames of the split left
  (`r82_b_push`) -> C down tx 6, the west stairs, south -> $70:18 (`r82_c_18`) -> D/F **$70:18 PlatformCrowRide**: the
  middle ACT_TILE_112 block of the ledge pushed south: it falls into the sky, the gap is floor (TILE_TYPE_32); onto the
  x 184 platform at its top stop; the two columns of FLOATING_PLATFORMs (x 88 / x 184, two stacked each, in step, 0.5 px a
  frame, 104 .. 392 / 152 .. 440) pass the solid floating-block rows 12 / 18 / 23-24 / 29 on alternate sides: cape jumps
  west at the top stop, east between rows 12 and 18, west between rows 18 and 23, onto platform 2 to its bottom stop,
  south-east onto the island (`r82_f_island`) -> G a standing cape jump under the island's hatch (176,576) lifts Link
  onto the grate, east -> $70:19 (`r82_g_19`) -> H **$70:19 GratePlatformRide**: hatch A at the platform's west stop
  (Link dropped onto it), up through hatch B (the floating blocks under the grate between B and C), over the grate to
  hatch C, dropped onto the platform heading east, its east stop, up through hatch D, east -> **$70:1A** (`r82_h_1A`) ->
  I down through $70:1A's hatch (112,240) into the room under the grate (`r82_i_room`, latest).
- [x] **Goal 2: the Four Sword clones on the cartridge's sensors** (new `Clone82.lua`; FourSword.cloneCollisions asks it
  first, cloneUpdate passes Link): sub_080085B0 on the clone = sub_080085CC with the clone's own hitbox (PlayerCloneHitbox
  $08120574, read at import), its layer (Link's), gPlayerState's table; the PlayerCloneCollisions patterns unchanged.  Port
  gap fixed: the old probes used the feet box one pixel out, with $0200 / $2000 (upper side sensors in the cartridge) and
  $0400 / $4000 swapped.  The clones need nothing for platforms: they sit at Link + offset (PlayerClone_Action2) and never
  fall.
- [x] **Port gap fixed: a pushed block over a pit falls in** (new `PushBlock82.lua`, one line in PushBlock.update):
  blockPushed.c sub_080830B8 type 0 -> sub_0800442E: GetTileHazardType's hazard_list ({act, kind}, $08004418, read at
  import) -> CreatePitFallFx / CreateDrownFx / CreateLavaDrownFx / CreateSwampDrownFx (FX $00 / $0B / $0C / $52), the block
  deleted, no tile laid.  The port laid $365 anywhere: $70:18's ledge block stood in the sky and walled its gap.
  (Noted, not changed: ToDObjects' own hazard test uses act $19 for the pit; hazard_list has $0D.)
- [x] **Goal 3: draw order under the grates -- no mismatch found.**  Harness and real-app (widescreen) shots of Link and the
  rupees under $70:21's grates (`r27b/shots/r82a_mesh_wide.png`, crops in `r82/img`): the mesh (BG1, priority 1) is drawn
  over layer-1 sprites (OBJ priority 2) as UpdateSpriteForCollisionLayer / sub_0807AABC give; the studs and the floor
  under the grates are BG2 (`r82/img/room21_top.png` / `_bottom.png`), so Link over them is right.  Round 81's note was a
  misreading of the downscaled shot; nothing changed.
- [x] **Goal 4: r78 K re-run** (J + K in one session from `r78_i_mines`, as round 81 did): **not a game bug** -- (1) the
  harness planner's lane at x 59 stalls (sub-pixel x after J's ride, the north sensors on the wall), so Link waits
  elsewhere and boards later; (2) the bot fired when the Bombarossa was within 6 px of Link's x without leading it (it
  moves 0.5 px a frame; the arrow needs ~27 frames): 15 px off; (3) at the top Link stood 10 px south of round 78's spot
  and walked west off the landing's edge.  `seg_k82.lua` (a fallback step, a lead on the mine, a step north at the top)
  passes in one session: the arrow kills the mine, the top landing (`r82_k78_top`, harness re-run).
- [x] **Harness quirk fixed** (round 81's "a checkpoint load in $70:21 / $70:16 puts Link elsewhere"): Field.new runs
  safeContinue on Link's spot with the default layer 1; under a grate that is the sky, so Link was moved to the nearest
  safe floor before the `.layer` file was applied.  pre82 sets the layer inside Field.new (harness only).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  Practice, not kept: B's first try had no sword equipped (fell into the
  sky, -2); E (cape-jump trials, 2 falls) and three F tries (4 falls) before the horizontal-only jumps; J's tries in
  $70:1A (the spiked rollers, -4); all kept checkpoints come from clean runs at hp 52.  Probes only read (probe_o reads
  room entity lists through Room.load, no visit).
- [ ] **Left / next:** $70:1A (POT_PUSH) from the grate side is closed to full-size Link: the room under the grate leads on
  by a Minish door (ACT_TILE_31 north -> $70:20), Minish holes (SURFACE_HOLE: full-size Link sits in them) to 2F, a
  Minish tunnel under the raised corridor (collision $14) and the key door west (LOCKED_DOOR type2 2, shared with $70:19's
  upper floor and its AMBIENT_CLOUDS stack); the room's MINISH_PORTAL_STONE, clone tiles and lightable switches are in its
  north-east part.  No small key is held.  Room names (include/roomid.h) give the order: $70:20 KEY_ARROW_BUTTON (a
  lightable switch drops a key) -> $70:17 PIT_CORNER_AFTER_KEY (its LOCKED_DOOR is the $20 / $17 door) -> $70:1A's
  north-east part (portal) ...; $70:20 has stairs at local (55,50), as $70:2A GIBDO_STAIRS on 2F; $70:2B
  SPIKE_BAR_SMALL_KEY (2F) has a small chest (tile entity, flag 111); 1F's $70:32 DARK_COMPASS_HALL is unvisited.  Next:
  find the way into 2F's inner rooms ($70:28 / $2A stairs, from 1F $70:32 or $70:22's shutters), then $70:20 -> $17 ->
  $1A's portal, $1D / $1C / $1B -> $70:1E's stairs -> $70:15 (4F), the Big Key ($70:01), Gyorg Pair.
- Tests: `tests/zelda_tmc_r82_test.lua` (31 checks, stand-in rooms / hitboxes / hazard lists); all 115
  `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605,
  0 mismatching (after the cache-52 rebuild).  ObjErrors 0 in every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 52; B, F and H re-run there with real keys, all
  passing): `r27b/shots/r82_clones_ride_wide.png` (the three Links on the platform), `r82_block_wide.png` (the block
  pushed to the west wall), `r82_crow_ride_wide.png` ($70:18, on the x 184 column after the second cape jump),
  `r82_grate_ride_wide.png` ($70:19, on the platform under the grate after hatch C).
- Estimates: ~96.9% of the story verified with real input, ~96.4% of the port (old scale).

## Round 83 (the way on from $70:1A found in the cartridge's room data: the NW room's holes take the Cane of Pacci's spring over the corridor wall; $70:1A NE: the blue sword's split on the C of clone tiles, one spin lights the three switches (the spin's second half had no hitbox: the import read 64 of gUnk_08129096's 147 entries, cache 53) -> the portal -> Minish down the crack, POT_PUSH (pots may now be pushed off a ledge: sub_0801A458's collisionType 2) -> the tunnel -> the Minish door -> $70:20's fenced column -> $70:1D's portal: full size -> the arrow over the fence lights KEY_ARROW_BUTTON's switch -> the small key -> $70:17 PIT_CORNER by cape -> the NW key door -> $70:19's cloud stack -> 4F ($70:14))

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r83/` (`go.sh` + `pre83.lua` (checkpoints in `r83/ck`, falling back to r82 ..
r38; `lib83a.lua` = lib82 with r83 names), segments `seg_a83` .. `seg_k83` (`seg_f83b` = F's second half), probes `probe_a` ..
`probe_k` (`probe_a`: every $70 room's header / exits / entities / tile entities -> `r83/out/rooms70.txt`; `probe_b`: floor
composites `r83/img/f1.png` (1F), `f4.png`, `f5.png`; `probe_c` / `probe_d`: collision + act dumps `r83/out/roomXX_coll.txt`,
`grid.py` prints them; `probe_f`: tile types, hatch tiles), `sokoban.py` (the pot field's BFS), `rebuild83.sh`, the real-app
kit `rt/` + `run83.sh` + `s83.lua` (B, F2, I, J, K with real keys, no checkpoint written)).  Outputs `r27b/r83_*`, `r83/out/*`.
Decomp read: the r49 repo (src/manager/holeManager.c gHoleTransitions, src/data/transitions.c, src/common.c dungeon layouts,
src/object/lockedDoor.c, pot.c, whirlwind.c, lightableSwitch.c, src/playerItem/playerItemSword.c gUnk_08129096,
src/player.c PlayerInHole / SurfaceAction_*, src/playerUtils.c sub_0807A2F8 / sub_08079550 / the ledge tables,
src/collision.c IsColliding + asm/src/intr.s arm_CalcCollision, src/beanstalkSubtask.c sub_0801A458, src/data/hitbox.c,
src/roomInit.c).
**Cache version: 53** (manifest.sword.boxes holds all 147 entries) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 53 -- **players re-import once**.

- [x] **Goal 1: the route on to the key (from the cartridge's data).**  Every small key of the palace ($03, $07, $08's
  falling key, $20's falling key, $2B, $32's middle column) lies behind the 2F ring / 3F middle / 5F, and the 2F ring, 1F's
  $32 and the 3F middle are entered only by 4F's holes ($15 -> $1B / $1D / $1F, gHoleTransitions $26 .. $28), the
  $1C / $1F holes, $32's stairs or $2F's archway -- so the way on is inside $70:1A itself: collision $14 / $15 are
  Minish-only (player shape tables 1 / 2); the NW room's four act-$19 holes are the Cane of Pacci's springs (sub_0807A2F8:
  the corridor wall's act $2D faces east, the landing tile's top layer is free -> layer 2); the corridor's middle has
  stairs (acts $27 / $52) down to the NE room (clone tiles, three type-1 LIGHTABLE_SWITCHes latched by a
  FLAG_AND_OPERATOR into flag $52 -> the MINISH_PORTAL_STONE); the NE room's crack (tx 26) leads Minish Link into the pot
  field (POT_PUSH), its row-14 tunnel back under the corridor, the NW room's Minish door (tx 5) into $70:20's stud-fenced
  east column (act $74 fence: the column, the $70:1D portal nook, the key's spot (200,56) between three Flying Skulls and
  the $87 shutter east), where full-size Link shoots KEY_ARROW_BUTTON's switch (104,72) over the fence: flag $58 ($17's
  shutter), SECRET_MANAGER -> $87 ($20's shutter), FALLING_ITEM -> the key.  No missing exit or object was found (the
  port's exit lists equal transitions.c).
- [x] **Port gap fixed: the sword's hitbox table** (Extract.lua, one loop bound): gUnk_08129096 has 147 entries (frameIndex
  $6A .. $FC); the import read 64, so frames $AA .. $AD -- the spin attack's north-west .. east half -- and the later sword
  moves had no box.  $70:1A's three switches sit north-west / south-west / south-east of the C's corners: the clone at
  (296,56) never lit (280,40).
- [x] **Port gap fixed: a pushed pot's free tile** (PushAnim.beyondFree, one line): sub_0801A458 tests the tile beyond with
  IsTileCollision(.., collisionType 2) at the tile's corner (Collide33), not the walking test; the sky's pit value ($21) is
  free to type 2, so the field's first pot can be pushed off the ledge (it falls: Pot_Action4 -> sub_0800442E).
- [x] **Route with real keys** (checkpoints in `r83/ck`; hp 52 / 56 throughout the kept runs):
  A from `r82_i_room` north into the NW room behind the spiked roller (x 39 .. 136, the whole room's height; the hole
  (104,104) as cover), the Cane east into the hole (136,72), in from the west: the spring over the wall onto the raised
  corridor, layer 2 (`r83_a_corridor`) -> B east down the stairs, the sword charged off the tiles, clone 1 on (18,3),
  clone 2 on (18,5), Link on (20,5); the split's spin lights all three, latched (`r83_b_portal`) -> C the portal (392,72),
  R: Minish (`r83_c_minish`) -> D down the crack, 23 pot moves (one pot pushed off the south edge) (`r83_d_pots`) -> E the
  tunnel, up the gap behind the roller, the Minish door -> $70:20 (`r83_e_20`) -> F along the fenced strip, up the column
  into $70:1D's nook, R at the portal: full size (`r83_f_big`) -> F2 down the column at x 168, the bow west over the fence:
  the switch, flags $58 / $87, the key falls (`r83_f_switch`) -> G the skull west of it lifted and thrown, the key
  (`r83_g_key`) -> I east through the $87 shutter -> $70:17, one running cape jump over the pit corner (96 frames)
  (`r83_i_corner`), south -> $70:1A NE (`r83_i_ne`) -> J up the stairs, a ledge jump west into the hole (136,72) behind the
  roller, out, into the hole (72,72) while it rolls back, out -> the key door west -> $70:19's NE floor (J + K in one
  session) -> K four cape jumps up the seven-cloud stack -> **4F, $70:14 TO_FAN_BRIDGE (112,160)** (`r83_k_4f`, latest,
  hp 52 / 56).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  Practice, not kept: A's first tries (the roller, -10), C's first try
  (R pressed mid-jump onto the portal, then walked north into $70:1A's sky: **one practice death**), J's first try (the
  roller at the landing, -2).  Harness note: a checkpoint load reloads the room (the thrown skull is back; Link at
  (472,104) in $70:19), so G + H and J + K ran as one session each.
- Regression: r79 H ($70:22's four switches, one spin) passes with the full sword table.
- [ ] **Left / next:** 4F: $14 -> $13 FAN_BRIDGE / $15 RED_WARP_HALL (holes into $1B / $1D / $1F, the stairs to $1E, two
  key doors 4A / 4B to $0D's stairs), the map ($1C, a FIGHT_MANAGER chest), the Floormaster lever ($1B), 5F ($0F's /
  $10's cloud staircases -> $02 / $03), keys $03 / $07 / $08, the Big Key ($01), the big-key doors, Gyorg Pair.  No key
  is held.  Found, not changed: the hole spring is still the port's simplified scan (Pacci ledgeAhead: any solid tile,
  zv n + 1, layer kept) -- the cartridge uses sub_0807A2F8(1) (zv = n - 0.25, layer 2 in dungeons): 4 px further here;
  LIGHTABLE_SWITCH's box is gHitbox_0 = offset (0,-3), 6 x 6 in the cartridge (port: 8 x 8 at 0) and arm_CalcCollision
  is inclusive (port: strict).  Goal 3 not reached (the cloud-rim conveyor push, $70:21's blue Chuchus).
- Tests: `tests/zelda_tmc_r83_test.lua` (17 checks: stand-in manifests / rooms / lookups); all 116
  `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605,
  0 mismatching (after the cache-53 rebuild).  ObjErrors 0 in every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 53; B, F2, I, J, K re-run there with real keys,
  all passing): `r27b/shots/r83_b_switches_wide.png` (the three Links after the spin, the portal up),
  `r83_key_drop_wide.png` (the key fallen between the skulls), `r83_pit_corner_wide.png` ($70:17 after the cape jump),
  `r83_4f_wide.png` ($70:14, 4F).
- Estimates: ~97.4% of the story verified with real input, ~96.7% of the port (old scale).

## Round 84 (4F and 5F with real keys: $70:13 FAN_BRIDGE (the fans' wind now crosses the sky: IsTileCollision type 9; it carries a cape jump), the west room's ACT_TILE_112 blocks, the yellow ChuChus, the west fan's wind glide over the sky row, $70:11's islands by cape, $70:0F CLOUD_JUMPS (glides off the cloud stacks keep the cape's gravity), the 8-cloud stair -> 5F; $70:08's Ball and Chain Soldiers (the sword's hurtType per sword, Sword84, cache 54) -> the small key -> $70:07 -> $70:06 FOUR_BUTTON_STALFOS (a pushed pot + the three Links) -> $70:05 -> its fan's wind down to the bottom floor; the Cane of Pacci's spring and LIGHTABLE_SWITCH's box as the cartridge has them)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r84/` (`go.sh` + `pre84.lua` (checkpoints in `r84/ck`, falling back to r83 ..
r38), `lib84a.lua` (checkpoint names), `lib84.lua` (`H.fanWait84`, `H.steer84` / `H.steerTo84` (walk leaning against a
gust), `H.push84`, `H.bowTop84`, `H.bcs84` (the Ball and Chain Soldier bait / dodge / rest-window bot)), segments
`seg_a84` .. `seg_r84` (`seg_m84b` = M's second half, run in one session with M), `seg_k80b` / `seg_l80b` (r80 K / L
re-run), `regress84.sh`, probes `probe_a84` .. `probe_i84` (`probe_d84`: collision + act dumps of every 5F room ->
`r84/out`; `probe_e84` / `probe_i84` were diagnostics that moved Link: not route), `rebuild84.sh`, the real-app kit
`rt/` + `run84.sh` + `s84.lua` (B, E, G, H and r80 L re-run with real keys, no checkpoint written), floor crops in
`r84/img`).  Decomp read: the r49 repo (src/object/fan.c / fanWind.c / ambientClouds.c / button.c / pot.c,
src/movement.c IsTileCollision, src/playerUtils.c PlayerCanBeMoved / sub_0807A2F8, src/player.c sub_08072B5C / the
clone count, src/playerItem.c ItemInit, src/playerItemDefinitions.c, src/playerItem/playerItemSword.c, src/collision.c,
asm/src/code_080043E8.s sub_08004542, src/enemy/ballChainSoldier.c, include/roomid.h).
**Cache version: 54** (r35.bin gains Sword84.DEFS) -- the harness cache, the real-app cache
(`r27b/appdata/LOVE/tmc_bugs1`) and `testcache` were rebuilt at 54 -- **players re-import once**.

- [x] **Port gap fixed: a FAN's wind box** (PoWObjects solid9): fan.c sub_0809EFB0 / fanWind.c stop at
  IsTileCollision(.., 9) (Collide33); the port used the walking test, so the sky's pit value ended the box: $70:13's
  bridge fans had length 0 and its sky-row fan could not carry Link.  $70:22's boxes now span the room as well.
- [x] **Port gap fixed: the wind moves Link in a Roc's Cape jump** (PoWObjects canBeMoved): PlayerCanBeMoved has no
  jump flag; the port excluded every jump.  $70:13's west-blowing fan carries the glide over the 14-tile sky row.
- [x] **Port gap fixed: a glide off a cloud stack** (PoWObjects dropTick): AmbientClouds_Action2 only raises Link's z;
  in a jump the drop's own gravity came on top of the cape's (Link fell 150 px in 30 frames): $70:0F's stack glides.
- [x] **Port gap fixed: the sword swing's hurtType** (new `Sword84.lua`; Items / FourSword / Enemies:swordHits pass it):
  ItemInit takes it from gPlayerItemDefinition_0[sword - 1] (read from the ROM, RomTablesCat "Sword84.DEFS"); the port
  swung every sword with row 4 (the Smith's).  The Blue Sword's row hits a Ball and Chain Soldier for 3, not 2.
- [x] **Goal 2: the Cane of Pacci's spring** (new `Pacci84.lua`; Whirlwind.ledgeUp gains param 1): sub_0807A2F8(1) is
  the whirlwind's ledge scan without its blocked test; zVelocity n - 0.25, speed 1, layer 2 outside the overworld
  (sub_08004542).  **LIGHTABLE_SWITCH's box** (new `Switch84.lua`, LightableSwitch asks it first): gHitbox_0 (offset
  (0,-3), 6 x 6, the ROM table Beetle66.FLY_HB) with arm_CalcCollision's inclusive test.
- [x] **Regressions** (`regress84.sh`): r79 H (four switches, one spin), r83 A (the Pacci spring onto the corridor, now
  x 180 / layer 2), r83 B (three switches) pass.  r80 K / L failed with the cartridge's wind (and round 42's holes
  catch Link at (18,13) on r80's line): re-run with real keys as `seg_k80b` (up col 19, one idle window for rows
  12-13, col 17 to the top strip, the cape east) and `seg_l80b` (down the right-hand corridor leaning on the gusts,
  row 27 as shelter, the bolt, the hole in an idle window; the spring lands at (236,426) layer 2) -> `r84_k80_topright`,
  `r84_l80_walkway`; r80 M then passes from the new walkway checkpoint (`rr84_r80_m_grate21`).
- [x] **Route with real keys** (checkpoints in `r84/ck`): B $70:14 west -> $70:13's bridges leaning against the fans,
  a cape jump over the 3-tile gap (`r84_b_bridge`) -> C up the stairs (11,4) into the west room (layer 2), its
  ACT_TILE_112 blocks (8,6) west and (9,7) east, down to the middle corridor (`r84_c_corridor`) -> D cape jumps over
  the spike pairs, one arrow each for the two yellow ChuChus as they rise, the stairs (25,12) (`r84_d_se`) -> E the
  sky-row fan (440,256): a cape jump west in its wind, 300 px to the west carpet (`r84_e_west`) -> F north into
  $70:11 CRACKED_FLOOR_LAKITU, three cape jumps island to island (`r84_f_islandB`, `r84_f_north`) -> G $70:0F: up the
  3-cloud stack, the glide east along the torch lane (`r84_g_B`) -> H a running cape jump, the 4-cloud stack's glide,
  the 8-cloud stack: CLOUD_STAIRCASE -> **5F $70:02** (`r84_h_5f`, hp 52) -> I south into $70:08: the two Ball and
  Chain Soldiers (bait a throw, step off its line, slash while it rests with the ball pulled in) -> the falling key
  (`r84_i_fight`, **hp 12**) -> J the west key door -> $70:07 (`r84_j_07`) -> L its two Stalfos, west -> $70:06
  (`r84_l_06`) -> M a pot lifted away, the pot (4,8) pushed north onto (4,6), the sword charged, clones left on (9,4)
  and (11,4), Link on (11,6), the three Links 80 px west: four buttons, flag $3B (`r84_m_buttons`) -> N west through
  the shutter -> $70:05 (`r84_n_05`) -> O the pot with the heart (hp 20), the button (4,3) -> flag $38, a cape jump
  into the south-blowing fan's wind from beside its box -> $70:05's bottom floor (`r84_o_bottom`, latest, **hp 20 /
  56, no key**).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  Diagnostics that set Link's position (probe_e84) are not route.
  **Practice deaths, not kept: 7** -- $70:08's fight (5: the bot in the ball's path, arrows (1 damage), the sword key
  not pressed, a bait-offset variant), $70:05's Spear Moblin ambush (2, at hp 20).  Practice falls (not kept):
  $70:13's planner walking back over the bridges, $70:22's / $70:05's gusts while testing, $70:11 (a Lakitu turn).
- [ ] **Left / next:** $70:05's bottom floor is MOBLIN_AND_WIZZROBE_FIGHT: stepping into its east half spawns two
  Spear Moblins (8 a hit) and two Wizzrobes and shuts the east door; at hp 20 the bot loses -- heal first ($70:06's pots
  gave nothing, $70:05's heart pot is used; re-entered rooms' pots or fairies), then the fight -> the east door ->
  $70:06 bottom (a cape jump over cols 7-8) -> $70:07 bottom: the button (184,440) (flag $3D) -> the north-blowing fan
  (128,392): a glide into the nook (rows 8-9, cols 6-9) -> push (10,8) east, (10,7) north, (5,8) west -> the small
  chest (5,7) from below (facing north) -> the key (flag $3E) -> the north key door ($3C) -> **$70:01 the Big Key** ->
  $70:08's BOSS_DOOR south -> $0A / $0C (Darknut) -> ... -> $03 -> Gyorg Pair ($00).  Seen, not changed: $70:11's
  Lakitus once turned a cape jump south (a fresh room does not); Goal 3 not reached.
- Tests: `tests/zelda_tmc_r84_test.lua` (36 checks: stand-in rooms / tables / matrices); all 117
  `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605,
  0 mismatching (after the cache-54 rebuild).  ObjErrors 0 in every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 54; B, E, G, H and r80 L re-run there with
  real keys, all passing): `r27b/shots/r84_b_west_wide.png` (past the fan bridge), `r84_e_west_wide.png` (after the
  wind glide), `r84_g_stacktop_wide.png` (on the 3-cloud stack in $70:0F), `r84_h_5f_wide.png` (5F, $70:02).
- Estimates: ~97.9% of the story verified with real input, ~97.1% of the port (old scale).

## Round 85 (healed on $70:05's heart pot (it comes back with the room); $70:05's Spear Moblin / Wizzrobe ambush won at full health; $70:06 -> $70:07's bottom floor, its button + the north fan's wind glide into the nook, three block pushes, the chest -> the small key -> the north key door -> $70:01: **the Big Key**; $70:08's BOSS_DOOR -> $70:0A (Flying Skulls' hearts) -> the fall to $70:0C: the **Dark Nut** won with the shield (no damage) -> the bridge -> $70:2F's archway -> $70:32 (1F); the respawn search no longer drops Link outside the walls onto an empty top layer (Respawn85))

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r85/` (`go.sh` + `pre85.lua` (checkpoints in `r85/ck`, falling back to r84 ..
r38), `lib85a.lua`, `lib85.lua` (`H.sky85` / `H.safeDir85` (never step toward the sky), `H.dn85` (side-hit bot: not
used, see the practice death), `H.dn85b` (the Dark Nut shield bot)), segments `seg_a85` .. `seg_n85` (`seg_m85` = the
westward glide attempts on $70:0F (practice), `seg_m85b` = the ledge test), probes `probe_e85` / `probe_l85` (the layer
flip), `probe_j85` (the Dark Nut fight's spawn, practice), `probe_n85` (ledge tables), `probe_r85` (the respawn fix),
`probe_w85` (warp flags), `rebuild85.sh` (audit only), the real-app kit `rt/` + `run85.sh` + `s85.lua`,
`f4_top_small.png` (4F composite crop)).  Decomp read: the r49 repo (src/enemy/darkNut.c,
src/projectile/darkNutSwordSlash.c, src/collision.c sub_08017D6C, src/object/chestSpawner.c, src/object/warpPoint.c,
src/manager/holeManager.c (gHoleTransitions $20 .. $23, DoHoleTransition), src/manager/secretManager.c,
src/playerUtils.c sub_0807A8D8, include/manager.h).
**Cache version: 54, unchanged** (no import change) -- no re-import.

- [x] **Goal 1: healed with real input.**  `seg_a85` from `r84_n_05` ($70:05 top, hp 12): the pot (184,56) holds a
  heart (paramA $5F, no flag -- it is back each time the room reloads, as on the cartridge); lift + throw, east into
  $70:06 (its pots: random drops), west again: five rounds -> **hp 56 / 56** (`r85_a_healed`).  Then r84 O at full
  health: the button, the cape jump into the south fan's wind -> the bottom floor (`r85_b_bottom`).
- [x] **Goal 2: the route with real keys** (checkpoints in `r85/ck`):
  C the ambush (two Spear Moblins, two Wizzrobes): H.fight63 (shield toward chargers, swing when lined up) wins at full
  health, hp 36 (`r85_c_fight`) -> D east door, $70:06's bottom (the cape jump over cols 7-8; two Stalfos hits)
  (`r85_d_07b`, hp 32) -> E $70:07's bottom: the pots, the button (184,440) (flag $3D), a cape jump from beside the
  north fan's box (x 112 .. 144, y 128 .. 384) -> carried into the nook (`r85_e_nook`) -> F pushes (10,8) east, (10,7)
  north, (5,8) west, the chest (5,7) from below with R -> **the small key** (flag $3E) (`r85_f_key`) -> G out by
  (10,7) / (11,7), the north key door (flag $3C) -> $70:01 (`r85_g_01`) -> H the big chest (CHEST_SPAWNER type 4) from
  below -> **the Big Key**; back south, east into $70:08, its BOSS_DOOR south (flag $42) -> $70:0A (`r85_h_0a`) -> I the
  four Flying Skulls lifted and thrown (three hearts: hp 56), Ezlo's hint, a step off the south edge (HOLE_MANAGER $23:
  no hole box, the whole room) -> $70:0C (no fall damage) (`r85_i_0c`) -> J the REGION_TRIGGER, FIGHT_MANAGER's **Dark
  Nut** (type 2, 20 hp): `H.dn85b` -- face it with the shield up (every slash type is blocked when Link faces its Dark
  Nut); when it is open (hitType $51 after the combo's frame 4 / the sweep / the spin with no live slash child, or
  recoiling) the shield comes down, a step to 18 px and a swing: 15 swings, **no damage taken** (flags $7E, $84: the
  WARP_POINT on, the bridge) (`r85_j_darknut`) -> K the bridge north -> $70:2F (`r85_k_north`) -> N its archway ->
  **$70:32 (1F)** (`r85_n_32`, latest of the Dark Nut branch, hp 56 / 56, Big Key, no small key).
  Also L from `r85_h_0a` (the main branch): the skulls (hp 56), north through the BOSS_DOOR, $70:08 -> $70:02, east into
  its 4 x 4 sky hole (HOLE_MANAGER $20, relative + (480,112)) -> $70:0F's east island (`r85_l_0f`, hp 56, Big Key).
- [x] **Port gap fixed: the respawn-spot search** (new `Respawn85.lua`; Dungeon:respawnSpot asks it, one line):
  Field:safeContinue's fallback (the saved spot is solid -- Link saved in $70:07's west door tile (8,410)) took the
  nearest "good" tile centre (8,440): column 0, outside the wall frame, tile type $0310 with surface flag 4, so
  sub_0807A8D8 put Link on layer 2 where the room's top map is empty -- he walked through the walls (an r85 E/F run
  went through $70:07's east wall into $70:08 that way; discarded).  The search now skips the outer ring of tiles and
  any tile whose bottom flags would move Link onto an empty top layer: the same load now puts him at (56,408), layer 1.
- [ ] **Blocked: the way on to Gyorg.**  The boss door is $70:03's BOSS_DOOR (flag $36) -> $70:00; $70:03 is reached
  only from 4F $70:10's 8-cloud stack (its holes $21 / $22 fall back to $10) or from $70:09 (5F east: $0B / $0E / $0D,
  whose stairs come up from $70:15 behind key doors 4A / 4B), and $70:10 only from $70:15 (4F, RED_WARP_HALL).  From 5F
  there is no way back down to $15: $70:02's hole lands on $70:0F's east island, whose south ledge (act $2B, rows
  14-15) is a north-only jump (the right tower comes UP there from $15), and the glide west from the 8-cloud stack's
  4th level (the 5th is the CLOUD_STAIRCASE) lands at x ~444 (the small platform ends at 432; cape air speed is clamped
  to $180) -- three practice falls (-2 each), not kept.  The cartridge's way back is the warp pair: the Dark Nut's
  WARP_POINT ($0C, type 0, flag $84) <-> $70:31 (1F, (520,88)); $31's type-1 pad <-> $15's (0x288,0x48), which needs
  flag $86 (SECRET_MANAGER on flag $4D, set in $15 by the manager at (0x268,0x48)) -- $15 was never visited (r83/r84
  went $14 -> $13), so dungeon warp bit 1 is off (`warps` = 1).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  **Practice deaths, not kept: 1** (the first Dark Nut bot
  `H.dn85`: side hits during its attacks, hp 56 -> 0 with the Dark Nut at 8 / 20).  Practice falls: the three $70:0F
  glides.  Discarded (harness artefacts): E + F + G from a checkpoint load that put Link on the empty top layer (the
  bug above), G from a reloaded room (the pushed blocks were back).
- Seen, not changed: the real-app J ended on the warp pad (the drop pick-up walked onto it) -> $70:31 (520,88), the
  warp's decoded destination.  Goal 3 not reached (cloud-rim conveyor, $70:21's blue ChuChus, $70:11's Lakitus).
- Tests: `tests/zelda_tmc_r85_test.lua` (15 checks: stand-in rooms / flags, respawnSpot end to end); all 118
  `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605,
  0 mismatching.  ObjErrors 0 in every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 54; C, E + F, H, J re-run there with real
  keys, all passing): `r27b/shots/173226_r85_c_fight_wide.png` (the ambush won), `173226_r85_f_key_wide.png` (the
  nook, the key), `173226_r85_h_bigkey_wide.png` (the Big Key), `173226_r85_j_darknut_wide.png` (after the Dark Nut,
  through the warp to $70:31).
- [ ] **Next:** from `r85_n_32` / the warp ($70:31) climb back to 4F $70:15 (1F -> 2F -> 3F -> $19's cloud stack ->
  $14 -> $15, or $32's stairs to $28 if shorter), activate $15's warp (flag $4D -> $86), north into $70:10, its 8-cloud
  stack -> $70:03, the BOSS_DOOR -> $70:00 -> Gyorg Pair (BossGyorg.lua is ported; a fair real-input fight), the Wind
  Element.
- Estimates: ~98.2% of the story verified with real input, ~97.2% of the port (old scale).

## Round 86 (from $70:32 (1F) up the cartridge's middle route to 4F $70:15 RED_WARP_HALL with real keys: $32's stairs -> $28 -> $23 PEAHAT_SWITCH (Peahats by Gust Jar + sword, the pots off the clone tiles, the blue sword's split, the three Links' spin lights all four type-1 switches -> $69) -> $2B (cape jumps over the spiked rollers, **a small key**) -> $23's key door ($6A) -> $24 (a cape jump into a whirlwind, the parachute glide over two more whirlwinds) -> $2A (Gibdos) -> $20 west -> $1D -> $1C (Wizzrobes, **the map**) -> $1B (Floormasters, the lever -> $54) -> $1E -> **$70:15** (its west half); cracked floor ported (Cracked86), the rollers' z test (Roller86))

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r86/` (`go.sh` + `pre86.lua` (checkpoints in `r86/ck`, falling back to r85 ..
r38), `lib86a.lua`, `lib86.lua` (`H.out86` / `H.hold86` (stairs need the key held), `H.flags86`, `H.spin86`, `H.lane86`
(walk with the sword held), `H.clones86`, `H.sws86`, `H.rollerWalk86` (v3: jump when an approaching roller would touch
Link in 10 frames -- the cape keeps z > 10 for frames 7 .. 28 --, wait while one ahead rolls away, cross a roller's
line only when walking clears it)), segments `seg_a86` .. `seg_n86` (C + D + E run in one session: $23 reloads with its
Peahats), probes `probe_a86` .. `probe_k86` (b: the crack, c: tile flags, d: spin reach, e: cape z profile, f: an edge
test that walked off (practice fall), g: a jump at $15's bottom hole (practice, -4), h / i / j: $15 / $0F tiles and the
tunnel shutters, k: a cape jump at $20's fence (blocked)), `rebuild86.sh` (audit only), the real-app kit `rt/` +
`run86.sh` + `s86.lua`, crops `f15_left.png` / `f15_right.png`).  Decomp read: the r49 repo (src/player.c
SurfaceAction_7 / sub_080741C4, src/object/crackingGround.c, src/playerUtils.c GetSurfaceCalcType / RespawnPlayer /
sub_0807AAF8 / sub_0807A8D8, src/enemy/peahat.c, src/manager/flagAndOperatorManager.c, lightLevelSetManager.c,
src/object/lockedDoor.c, whirlwind.c, src/collision.c IsColliding, asm/src/intr.s arm_CalcCollision, src/data/hitbox.c,
include/room.h (tile entity types), include/roomid.h, include/enemy.h).
**Cache version: 54, unchanged** (no import change) -- no re-import.

- [x] **Goal 1: the way to $70:15, from the room data.**  The 2F / 3F middle rings are a chain: $32's stairs (184,216)
  -> $28 TO_PEAHAT_SWITCH -> south -> $23 PEAHAT_SWITCH (four type-1 LIGHTABLE_SWITCHes (56..152,216) latched by a
  FLAG_AND_OPERATOR into $69 = the west shutter; the east door is key door $6A) -> $2B SPIKE_BAR_SMALL_KEY (the small
  chest (6,1) on the raised top) -> back, $6A -> $24 WHIRLWIND_BOMBAROSSA -> its north doorway -> $2A GIBDO_STAIRS ->
  stairs (56,40) -> $20's west part -> column 8 north -> $1D CORNER_TO_MAP -> west -> $1C MAP (FIGHT_MANAGER chest) ->
  west -> $1B FLOORMASTER_LEVER (PULLABLE_LEVER -> room flag $8000 -> FLAG_AND -> $54, the south shutter) -> $1E
  STAIRS_AFTER_FLOORMASTER -> stairs (184,40) -> $15 (184,232).
- [ ] **Found: $15 is two halves.**  The stairs from $1E arrive in the WEST half (left ring, top-left, bottom-left, the
  $12 door island).  The torches (LIGHT_LEVEL_SET_MANAGER type 2 at (616,72) -> $4D -> SECRET_MANAGER -> $86, the warp
  pad (648,72); (680,72) -> $4E), the tunnel switch (440,56) ($4C opens the tower tunnel's shutters (312,72) /
  (408,72)), the key doors 4A ($10, the boss route) and 4B ($0D's stairs) are all in the EAST half.  Between them: the
  central tower, the bottom sky hole (cols 20-24, its east side the bombable cracked blocks (25,15-16), act $2E) and
  the closed tunnel (probe_j86).  The cartridge's way into the east half, from the room data: $0F's layer-2 grate
  walkway (rows 16-19, cols 15-37) joins the LEFT tower top (reached from $0F's west island (cols 13-18, rows 7-13) by
  the stairs (16,14-15), act $26) to the RIGHT tower top (cols 35-37) -> south through $12 (cols 20-22) onto $15's
  central tower (layer 2, rows 0-11) -> its east walls (cols 24-25, act $2C) are a ledge jump east into the east half.
  r84 G stood on that island ("the torch lane") and went up the cloud stair to 5F instead.  The $12 door of the west
  half leads only to HEART_PIECE_BRIDGE (the heart piece (424,276) on $0F's layer 1; not taken).  $20's fence blocks a
  cape jump (probe_k86); $15's bottom hole has a wall on its east side.
- [x] **Port gap fixed: cracked floor** (new `Cracked86.lua`, an R27A module wrapping Dungeon.checkFall; R27A one
  line): GetSurfaceCalcType's surfacePositionSameTimer (frames on one tile position + type; cleared off the ground),
  SurfaceAction_7 at exactly 15 (not Minish) -> CRACKING_GROUND on Link's tile -> 21 frames later the tile becomes
  TILE_TYPE $35 (a pit through the room's tables), FX_FALL_DOWN, SFX_126.  The path memory (sub_0807A8D8) only takes
  tiles with flag bit $20 -- a cracked tile has none (probe_c86) -- so the respawn spot never becomes a cracked tile
  (before the fix Link was put back on the new pit over and over).  $23 / $11's cracked floors now crumble; r84 F
  ($11's islands) still passes.
- [x] **Port gap fixed: the rollers' z test** (new `Roller86.lua`; FoWObjects touchLink one line): arm_CalcCollision
  also needs |dz| <= 5 + 5 for flat hitboxes (gPlayerHitbox, the rollers' gUnk_080FD4B8); touchLink had no z test, so
  a cape jump could not clear a SPIKED_ROLLER (Enemies' contact has had it since round 43).
- [x] **Route with real keys** (checkpoints in `r86/ck`): A $32 -> the stairs (`r86_a_28`) -> B $28 south (`r86_b_23`)
  -> C the three Peahats (H.pea21: the Gust Jar while they hover / charge, the sword on the downed ones; -6) -> D the
  pots (136,43) / (200,43) / (168,43) lifted off the clone tiles, the split charge, clones on (8,2) and (12,2), Link on
  (10,2) (the third tile sets PL_CLONING), released; the second charge held while the three Links walk down (x 104
  through the row-8 posts, x 120 through row 11, x 104 into row 13's gaps): one spin, all four switches lit -> $69 -> E
  west (`r86_e_2b`) -> F three rollers by cape jumps, the stairs (11,4), the chest -> **the small key** ($6F,
  `r86_f_key`, no damage) -> G back over the rollers (-2), through $23 to the key door ($6A) (`r86_g_24`) -> H a cape
  jump straight south from (88,136) into the whirlwind (88,208) (caught with z >= 16), the glide via the whirlwinds
  (184,120) and (280,104) to the north floor (`r86_h_north`) -> I north (`r86_i_2a`) -> J the Gibdos, the stairs
  (`r86_j_20`) -> K row 5 around the KEY_ARROW_BUTTON switch, column 8 north, $1D, west (`r86_k_1c`) -> L the three
  Wizzrobes (-2), **the map** ($57) (`r86_l_1b`) -> M the two Floormasters, the lever pulled (the FLAG_AND latch)
  (`r86_m_1e`) -> N the stairs -> **$70:15** (`r86_n_15`, latest, **hp 26 / 56**, Big Key, map, no small key; the
  real-app run of M + N arrived with hp 46).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  **Practice deaths: none.**  Practice (not kept): a Floormaster's
  grab sent Link to $70:31 (the M bot with the shield; won without it), probe_b86's crack (-4), probe_f86's walk off
  $24's floor (a fall), probe_g86's jump at $15's hole (-4), the first rollerWalk bots (-10, -6), the first whirlwind
  jumps (fell, -2 each).
- [ ] **Left / next:** the east half of $15.  From `r86_n_15` the way back to $0F's west island is long (3F middle ->
  2F -> $22 / $21 -> 3F $16 .. $1A -> $19's stack -> 4F $14 -> $13 -> $11 -> $0F); from a fresh climb the order is
  r84 E/F/G -> the island (cols 13-18) -> the stairs (16,14) -> the left tower top -> east along the walkway (layer 2,
  rows 17-18) -> the right tower -> $12 -> $15's tower -> the east ledge -> the torch (616,72) with the Lantern ($4D ->
  $86, warp on) -> key door 4A (a small key: $32's middle-column chest (22,2) or $03's) -> $10 -> its 8-cloud stack ->
  $03 -> $00 Gyorg Pair.  Not tested yet: the walkway's layer change at the tower ends, the east ledge from layer 2.
  Goal 3 not reached.
- Tests: `tests/zelda_tmc_r86_test.lua` (66 checks: stand-in rooms / acts / timers, the z test, the seams); all 119
  `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605,
  0 mismatching.  ObjErrors 0 in every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 54; C + D, F, H, M + N re-run there with real
  keys, all passing): `r27b/shots/205917_r86_d_switches_wide.png` (three Links, four lit switches),
  `205917_r86_f_key_wide.png` (the key), `205917_r86_h_north_wide.png` (after the whirlwind glide),
  `205917_r86_n_15_wide.png` ($70:15).
- Estimates: ~98.4% of the story verified with real input, ~97.4% of the port (old scale).

## Round 87 ($70:15's east half traced in the cartridge's room data: the grate walkway is a dead end (a Kinstone chest between two torches; the right tower's lane is closed by the walkway's rim on the top layer) and the whole east cluster ($15 east, $10, $03, $09, $0B, $0E, $0D, $00) has no way in from where the Big Key branch stands; two port mismatches fixed on the way: a room-placed ground item's collision layer (Pickup87) and no room change in the middle of a jump (Edge87); the walkway + chest with real keys)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r87/` (`go.sh` + `pre87.lua` (checkpoints in `r87/ck`, falling back to r86 ..
r38), `scene87.sh` / `run87.sh` (outputs in `r87/out`, harness shots in `r87/shots`), `lib87.lua` (empty), `render.awk`
(collision / act maps of the `out/roomXX.txt` dumps), segments `seg_a87` / `seg_b87` / `seg_w87`, probes `probe_a87` ..
`probe_m87` (a / b / f / i / j / l: room dumps, headers, entity data, tile flags, hatch scan; c / e / k / m: practice
moves, see below; g / h: the sword key), the real-app kit `rt/` + `run87rt.sh` + `s87.lua` / `s87b.lua`).  Decomp read: the
r49 repo (src/data/transitions.c (the PoW exit lists), include/roomid.h (room names), src/manager/holeManager.c
(gHoleTransitions $20 .. $28), src/room.c LoadDestructibleTile, src/manager/destructibleTileObserveManager.c,
src/player.c PlayerNormal / PlayerRoomTransition / PlayerWaitForScroll / the conveyor surfaces, src/playerUtils.c
GetSurfaceCalcType / sub_0807A8D8 / sub_0807BD14 / CreateCollisionDataBorderAroundRoom, src/beanstalkSubtask.c
UpdatePlayerCollision, src/scroll.c UpdateDoorTransition, src/collision.c IsColliding, asm/src/intr.s arm_CollideAll /
sub_080B1B84, asm/src/code_080043E8.s sub_0800451C, include/tiles.h, include/item.h, include/room.h).
**Cache version: 54, unchanged** (no import change) -- no re-import.

- [ ] **Goal 1: not reached -- the walkway does not lead to $70:15's east half.**  From the room data: $0F's stairs
  (16,14-15) (act $26 -> layer 3, the walkway's act $0C -> layer 2) put Link on the grate walkway (top layer, rows
  17-18, cols 15-37); its north rim is collision $0C (row 16) / the torches + the chest (35..37,16), its south rim is
  collision $03 (row 19, act $74 SURFACE_EDGE) across BOTH tower lanes, its ends are ledge tiles (act $2D west / $2C
  east) whose jump lands in the sky (tried: -2).  The tower tops below are tile type $310 (flags $84: layer 2), so
  Link on a lane is always on layer 2 and the rim stops him; there is no ROTATING_TRAPDOOR hatch ($343 .. $346) in
  $0F (only $18 / $19 / $1A / $21 / $2D have them).  The chest (36,16) holds a Kinstone piece.  So the lanes in $12 /
  $15 (the central tower, jumps off east / west by act $2C / $2D) are not reached from the walkway either.
  The east cluster: $15 east (torches $4D / $4E, warp pad $86, key doors 4A -> $10 and 4B -> stairs to $0D, the tunnel
  switch $4C, the bombable DESTRUCTIBLE_TILEs (25,15-16)), $10 BLOCK_MAZE_TO_BOSS_DOOR (two 8-cloud stacks ->
  $03), $03 GYORG_BOSS_DOOR (BOSS_DOOR $36 -> $00, a small-key chest, holes $21 / $22 -> $10, a door down to $09),
  $09 BOMBAROSSA_PATH -> $0B TO_BOMBAROSSA_PATH (hole $24 -> $15 east) -> $0E BOMB_WALL_OUTSIDE -> $0D
  BOMB_WALL_INSIDE -> stairs -> $15 east (536,232).  Its only links to the rest found so far are the warp pad ($31's
  type-1 pad, flag $86 -- set only by $15 east's torch) and the room border between $0F's east island and $10 (80 px
  of sky).  The border cannot be crossed in a jump on the cartridge (fixed below), and a bomb thrown from $15's west
  corridor does not reach the cracked blocks (speed 4, first landing 39 px out, over the pit; probe_m87: the bomb went
  off in the hands, -6, practice).  **Open question for the next round:** the cartridge's first way into the east
  cluster.  Not yet examined: $10's south-east opening (row 28, cols 15-23), $15's hole managers $26 .. $28 boxes,
  $0F's bottom-layer bridge end under the walkway (row 16, cols 25-27), whether Link on a $310 lane really stays on
  layer 2 at the rim, and a walkthrough of the cartridge's intended order.
- [x] **Port gap fixed: a room's ground item has a collision layer** (new `Pickup87.lua`; Field:spawn one line,
  Objects:updateGround one condition): LoadRoomEntity gives a room-placed GROUND_ITEM the kind byte's layer
  ((kind >> 4) & 3: 1 / 2, else ResolveCollisionLayer) and arm_CollideAll pairs Link with it only when the two
  collision layers share a bit.  The port took $0F's heart piece (424,276) -- kind bits 1, on the bottom-layer bridge
  under the grate -- from the walkway above it (layer 2).  Drops made at run time keep no layer (taken on either).
- [x] **Port gap fixed: no room change in a jump** (new `Edge87.lua`; Field:checkExits one line after the special
  warps): PlayerNormal calls UpdatePlayerCollision (the border scroll sub_0807BD14 and the exit lists) only while
  jump_status == 0, UpdateDoorTransition returns while jump_status != 0, and CreateCollisionDataBorderAroundRoom makes
  the column past the room collision $FF -- a Roc's Cape jump stops at the edge and comes down in the same room.  The
  port took the border mid-air and dropped Link's z (a running jump from $0F's east island landed in $10's sky at
  x 8, then the respawn put him on $10's floor: a way into the east cluster the cartridge does not have).  Now the
  same jump stops at x 716 and falls back into $0F (probe_k87, -2).
- [x] **Route with real keys** (checkpoints in `r87/ck`): the Big Key branch: A $70:15 (west) back down the stairs ->
  $1E -> its north shutter -> $1B (`r87_a_1b`, hp 26) -> B east -> $1C -> $1D (`r87_b_1d`, hp 26 / 56, Big Key, map).
  The walkway on the r84 branch (before 5F, no Big Key): W from `r84_g_B` (the west island): the stairs, layers 1 -> 3
  -> 2, past the two Bow Moblins (one arrow, -2), east to the right tower top, the chest from below (R) -> **a
  Kinstone piece** (`r87_w_chest`, hp 50 / 56).  From $1D the Big Key branch cannot reach $0F's west island without the
  Minish routes of round 83 (the $1D portal nook and $20's column are fenced; $20 / $1A's door at (5,8) / (5,0-1) is a
  Minish door) -- the long way is 1F $2C's cloud stack -> 2F $21 -> 3F $16 .. $1A -> $19 -> 4F $14 -> $13 -> $11 -> $0F,
  and the west island does not lead on anyway (above).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  Harness note: `H.keyFor25(3)` equips the sword (item 4) through the
  menu but returns false on a save with item 4, so `H.fight63` started before it swung nothing (probe_e87's Bow Moblin
  fight, practice); `seg_w87` equips first.  Practice, not kept: the walkway's east ledge jump into the sky (-2), the
  8-cloud stack glide (probe_c87: off the cloud Link is layer 1 and the island's south wall stops him), the jump into
  $10 before and after the fix (-2 each), the bomb (-6), the Bow Moblins without the sword (-18).
- Seen, not changed: $1E's fire bars hit Link once in the real app (A: hp 26 -> 22; the harness run took no hit).  The
  conveyor surfaces (acts $2A .. $2D -> SURFACE_E / D / 10 / F, conveyer_push) are not ported -- on the PoW cloud rims
  they sit on solid tiles (used as ledge jumps), so no route has needed them yet; Goal 3 not reached.
- Regression (r87 kit, Edge87 + Pickup87 in): r86 H (the whirlwind glide), r83 I (the pit corner + south exit), r84 H
  (the cloud glides -> 5F), r85 L ($02's hole -> $0F) pass.
- Tests: `tests/zelda_tmc_r87_test.lua` (21 checks: stand-in rooms / entity data, the seams); all 120
  `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  ObjErrors 0 in every
  session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 54; W, the edge jump, A + B re-run there
  with real keys, all passing): `r87/shots/141628_r87_w_chest_wide.png` (the walkway chest, the rim studs below),
  `141628_pk87_wide.png` (the jump stopped at $0F's east edge), `142056_r87_b_1d_wide.png` ($70:1D).
- [ ] **Next:** find the cartridge's way into the east cluster (above), then $15's torch (Lantern) -> $86, a small key
  ($03's chest or $32's (22,2)), 4A -> $10 -> the 8-cloud stack -> $03 -> BOSS_DOOR -> Gyorg Pair.
- Estimates: ~98.4% of the story verified with real input (unchanged), ~97.5% of the port (old scale).

## Round 88 (the way into $70:15's east half found: an arrow at the Bombarossa circling the bottom hole -- its blast breaks the cracked blocks (25,15-16) -- and a Roc's Cape glide east over the hole; then with real keys: the torches with the Lantern -> the red warp ($86), the warp pair to fetch $70:32's small key (fall through $70:26's hole onto the raised platform), key door 4B -> 5F $70:0D -> the bombed walls ($0D, $0E) -> $0B's cracked blocks -> $09's Bombarossa field (no touch, the two blocks) -> $03's small key -> back through $09 (arrows down column 3) -> $0B's cracked floor -> $15 east -> key door 4A -> $70:10's block maze (blocks pushed off the edge, the short cape jump) -> the 8-cloud stack -> $03 -> the BOSS_DOOR -> $70:00; conveyor surfaces ported (Conveyor88))

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r88/` (`go.sh` + `pre88.lua` (checkpoints in `r88/ck`, falling back to r87 ..
r38), `scene88.sh` / `run88.sh` (outputs in `r88/out`, harness shots in `r88/shots`), `lib88.lua` (`H.walk88`: one-frame
taps along one axis), segments `seg_a88` .. `seg_u88`, probes `probe_a88` .. `probe_i88` (a: tile types / flags / collision
masks at $15's lane; b / c: the Bombarossa arrow (practice); d: room dumps; e: the warp pad's state; f: $09's collision +
hitboxes; g: $09's blocks after a reload; h: a thrown bomb (practice); i: $10's runtime map with blocks / enemies,
`out/map10.txt` + a BFS), the real-app kit `rt/` + `run88rt.sh` + `s88.lua` / `s88b.lua`).  Decomp read: the r49 repo
(src/common.c gDungeonLayouts_PalaceOfWinds_*F (which room is on which floor), src/data/transitions.c, include/roomid.h,
src/manager/holeManager.c gHoleTransitions $20 .. $32, src/scroll.c DoExitTransition, src/playerUtils.c sub_0807A2F8 /
sub_0807A8D8 / gUnk_0811C1D8 / gUnk_0811C1E8 / gSurfaceActions, src/player.c PlayerInHole / SurfaceAction_Conveyer* /
conveyer_push / sub_080741C4, src/movement.c IsTileCollision, asm/src/script.s CheckOnLayerTransition / gTransitionTiles,
asm/src/veneer.s gMapDataPtrs, asm/src/intr.s sub_080B1B84, src/object/lightableSwitch.c, warpPoint.c,
src/enemy/bombarossa.c, src/data/mapActTileToSurfaceType.c, include/tiles.h / item.h / object.h / manager.h / enemy.h).
The cartridge's order was checked against a public walkthrough (thonky.com, "Palace of Winds"), then every step was read
in the room data and played.
**Cache version: 54, unchanged** (Conveyor88 reads the existing Hole42.SURFACE table) -- no re-import.

- [x] **Goal 1: how the east half is entered (evidence).**  $15's entity list has a BOMBAROSSA ($33, type 8: on rail 8 of
  the room's properties, layer 2) circling the bottom hole (19..25 x 14..17; HOLE_MANAGER $28 -> $1F); the hole's east
  wall (25,15-16) is two DESTRUCTIBLE_TILEs (act $2E, tile entities type $A, flags $50 / $51).  An arrow from the west rim
  ((300,248), facing east) when the Bombarossa is on its east leg (x 392, y ~234) sets it off (bombarossa.c OnCollision:
  anything but the six pass-through contacts -> SMOKE_PARTICLE, the blast) and the blast breaks both blocks (collision
  $0F -> $00, tile type $26); a Roc's Cape glide from x 313 lands at x 442 in the east half (~88 frames in the air).
  Ruled out on the way: the lanes (act $0C on L1 / L2, tile type $310 flags $84 -> layer 2) are tower tops that only
  lead OUT of rooms (their rims $2A .. $2D are ledge keys facing INTO the rooms, gUnk_0811C1E8); $15's holes $26 / $27 /
  $28 only go down (to $1B / $1D / $1F); a Pacci spring from the bottom hole has no ledge face (the hole is act $0D, and
  the north rim needs Link in row 14, which the wall at (19,14) keeps him out of); $10's south-east "opening" is walls
  ($0F00); no warp starts active ($31's pads need $84 / $86).  So the port was missing nothing for the entry -- round 87
  had overlooked the Bombarossa.
  The floors (gDungeonLayouts): 5F = $00 .. $0B, $0D, $0E; 4F = $0F .. $15; 3F = $16 .. $20; 2F = $21 .. $2B; 1F = $0C,
  $2C .. $32.  The east half: two torches (LIGHT_LEVEL_SET_MANAGER type 2, $4D / $4E) -> SECRET_MANAGER -> $86 -> the
  red WARP_POINT (648,72) <-> $31's type-1 pad; key door 4B (536,216) -> stairs -> 5F $0D; the pocket under key door 4A
  (cols 32-34, rows 2-5, walled off by hole $27) is reached only by $0B's hole $24 (cracked floor (2..4,3..5), +480).
- [x] **Route with real keys** (checkpoints in `r88/ck`, from `r86_n_15`): A the Stalfos, the arrow, the glide
  (`r88_a_east`, hp 26) -> B the two Gibdos (sword, no damage), the Lantern on both torches -> $86 (`r88_b_torches`) ->
  C the red warp -> $31 (`r88_c_31`) -> D its two heart pots (paramA $5F) -> north into $30 (`r88_d_30`, hp 42) -> E back,
  the blue warp ($84) -> $0C -> its bridge -> $2F -> the archway -> $32 (`r88_e_32`) -> F the stairs (184,216) -> $28 ->
  $25 (along row 3: row 4 runs past its hole) -> $26 (`r88_f_26`) -> G into the hole (7..8,4..5) (HOLE_MANAGER $2E, layer
  2, +240) -> $32's raised platform -> the chest (22,2) -> **a small key** ($7A) (`r88_g_key`) -> H down off the platform,
  the archway, $2F -> $0C's blue warp -> $31 (the pots again) -> the red warp -> $15 east (`r88_h_15e`, hp 48) -> I key
  door 4B (flag $4B) -> the stairs -> 5F $0D (`r88_i_0d`) -> J the Gibdos, a bomb at the cracked wall (13,3) -> east ->
  $0E (`r88_j_0e`) -> K a bomb at (1,5) -> west -> $0B (`r88_k_0b`) -> L a bomb at the cracked blocks (7,3-4) -> north ->
  $09 (`r88_l_09`) -> M the Bombarossa field without a touch (every lane 16 px from them: row 7, column 8, row 4,
  column 10, row 6, column 12, row 2, column 6, row 5, column 4), the block (4,3) pushed north, (3,3) west -> the north
  door -> $03 west (`r88_m_03`) -> N the chest (7,1) -> **a small key** ($35) (`r88_n_key`) -> O back into $09 (its blocks
  are back): (4,3) south, (3,3) west, two arrows down column 3 ((3,4), then (3,6): its row goes off in a chain) ->
  south -> $0B (`r88_o_0b`) -> P standing on the cracked floor (3,4) -> $15's pocket -> key door 4A (flag $4A) -> $10
  (`r88_p_10`, hp 42) -> Q up column 4, through the maze (a BFS over the room's tiles), down columns 15-16, the bottom
  corridor, the two skulls (25,26-27) lifted, the blocks (26,26-27) pushed east into the sky (`r88_q_blocks`, **hp 12**:
  the Spear Moblins and Stalfos hit hard) -> S a short cape jump (take-off x 428, no glide) over (27-28) onto the ledge
  (29-30), north, the 8-cloud stack (360,256): 7 jumps -> $03 middle (`r88_s_03`) -> T a cape jump north off the top
  cloud (it stands over the holes $21 / $22), the BOSS_DOOR (360,40) with the Big Key (flag $36) -> **$70:00
  GYORG_TORNADO** (`r88_t_00`) -> U two heart skulls lifted -> hp 20 (`r88_u_hearts`, **latest**: $70:00 (387,321), hp
  20 / 56, Big Key, no small key, flags $4A / $4B / $86 set).
- **Aids:** none -- no FULLHP / KEEPHP, no flags.  **Practice deaths, not kept: 2** ($0E: a bot fighting the Fire
  Wizzrobes on the cracked floor while the Stalfos from the skulls hit (seg K's first version); $10: a fight bot against
  the Spear Moblins at hp 42 (seg Q's second version)).  Practice, not kept: probe_b/c88's arrows (-6), probe_h88's thrown
  bomb (-4), seg M's first walk (it touched a Bombarossa, -8), seg F's first walk (row 4 -> $25's hole -> $32, -2).
- [x] **Port gap fixed: conveyor surfaces** (new `Conveyor88.lua`, an R27A module wrapping Dungeon.checkFall, guard
  Dungeon.conveyor88Installed; R27A one line): gMapActTileToSurfaceType (the ROM's, Hole42.SURFACE) -> SURFACE_D / E / F
  / 10 -> SurfaceAction_ConveyerNorth / South / West / East: not when sub_080741C4 (jump / z) or Minish: Link faces the
  conveyor's way and moves 1.25 px a frame (kWalkSpeed, LinearMoveUpdate, no tile test).  On the PoW cloud rims (acts
  $2A .. $2D) they carry a Link who ends up on a rim back onto the cloud; the conveyor acts $40 .. $4B move him too.
  SIMPLIFIED: ResetActiveItems is not done.
- Seen, not changed: a checkpoint saved in a door tile ($09 -> $03, (56,152)) reloads through Respawn85 onto $03's lane
  (1,8) on layer 2 (a harness continue only; M + N run in one session).  A heart from a $70:00 skull fell where no path
  reaches.  The Bombarossas' chain reaction works (a row of five went off together).
- Regression (Conveyor88 in): r88 A + S, r86 H (the whirlwind glide), r84 H (the cloud glides -> 5F) pass.
- Tests: `tests/zelda_tmc_r88_test.lua` (17 checks: stand-in acts / surface map, the four pushes, jump / z / Minish /
  layer, the seams); all 121 `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101)
  pass.  ObjErrors 0 in every session.
- Real-app shots (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 54; A + B, M, S + T + U re-run there with real
  keys, all passing): `r88/shots/191938_r88_a_east_wide.png` (over the hole), `191938_r88_b_torches_wide.png` (both
  torches lit, the red warp), `191938_r88_m_03_wide.png` ($09's blocks -> $03), `192115_r88_t_00_wide.png` (through the
  boss door, $70:00).
- [ ] **Next:** from `r88_u_hearts`: more hearts first (the two upper heart skulls (392,264) / (552,264): mpath found no
  path), then the giant whirlwind (object $82 at (472,199)) -> Gyorg Pair (BossGyorg.lua is ported; a fight bot is
  needed), the Wind Element; $70:21's Chuchus (Goal 3) not reached.
- Estimates: ~98.9% of the story verified with real input, ~97.6% of the port (old scale).

## Round 89 (the upper heart skulls of $70:00 reached (each sitting Flying Skull makes its own tile solid: lifted from the stair ledge, side on); the hearts again after a room re-entry (56 / 56); the giant whirlwind -> **the Gyorg Pair beaten with real keys** (all eight phases: the blue sword's split on her back's clone tiles under the open eyes, the ride on the blue male, the red male's zig-zag boarded by a cape hop); **the Wind Element** + heart container (max 64) -> the blue warp -> Ezlo: "Let's go revive the sacred blade!"; two Four Sword port gaps fixed (FourSword89: clone tiles free again, the clones' spin hits as a spin))

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r89/` (`go.sh` + `pre89.lua` (checkpoints in `r89/ck`, falling back to r88 ..
r38), `scene89.sh` / `run89.sh` (outputs in `r89/out`, harness shots in `r89/shots`), `lib89.lua` (the fight bot: `H.femRound89`
(one eye pattern: split on the pattern's three clone tiles, the three Links 64 px onto the eyes, spins while the eyes are
all open), `H.board89` / `H.ride89` / `H.unride89` (the male phases), `H.board5_89` (male phase 3), `H.danger89` /
`H.avoid89` / `H.shotSoon89` (energy shots, children, a male's pass), `H.hop89` (a steered Roc's Cape hop), `H.fight89`
(all phases by the boss object's action)), segments `seg_a89` .. `seg_i89` (`seg_c89` .. `seg_f89` = development runs,
`seg_g89` = the fight), probes `probe_a89` .. `probe_o89` (a / c / h / j: room / top-map / tile dumps; b: the north shot;
d: skull drops; e / f / g: the arrival trace; i / n: the spin's and the charge's sword boxes per facing; k: the charge
state; l: the cape's air time; m: an eye's block animation per facing (state poked); o: male phase 3 / female phase 4
reached by poking healths (development only, not a play)), the real-app kit `rt/` + `run89rt.sh` + `s89.lua`).  Decomp
read: the r49 repo (src/object/gyorgBossObject.c, src/enemy/gyorgFemale.c / gyorgFemaleEye.c / gyorgFemaleMouth.c /
gyorgMale.c / gyorgMaleEye.c / gyorgChild.c, src/projectile/gyorgTail.c / gyorgMaleEnergyProjectile.c, include/enemy/
gyorg.h, src/object/playerClone.c, src/playerUtils.c RespawnPlayer / field_0x14, src/player.c PlayerFall, src/interrupts.c,
include/tiles.h).
**Cache version: 54, unchanged** (no import change) -- no re-import.

- [x] **Goal 1: the upper heart skulls.**  $70:00's room data: the four upper skulls stand on the stair ledge (row 16, cols
  24-25 / 33-34) between the two stairs (col 29, collision $29 / act $26 -> layer 3); a sitting FLYING_SKULL makes its own
  tile solid (collision $0F under (392 / 408 / 536 / 552, 267)), which is what round 88's mpath read as walls -- the port
  was right.  `seg_a89` (from `r88_u_hearts`, hp 20): up the stairs (472), along the ledge, (408) lifted from the east
  (facing left), thrown east, then (392); (536) / (552) from the west -> two hearts -> hp 36 (`r89_a_hearts`).  `seg_b89`:
  down the ledge, out through the south door to $70:03 and back (the skulls are back, as on the cartridge), the west lower
  skull (296,411) and the ledge pairs again -> **hp 56 / 56** (`r89_b_hearts`).
- [x] **Goal 2: the Gyorg Pair with real keys** (`seg_g89` from `r89_b_hearts`, one session, 30 174 frames ~ 8.4 min of game
  time, hp 56 -> 48, no aid).  What the fight takes, read in the decomp and checked in play:
  - Arrival: the BIG_VORTEX drops Link onto male 1 (type 0); it swims north over her (b3 2), turns at y $130 and dives
    under her (b3 3) -- sub_08048004 then holds a rider at her edge and the dive leaves him over the sky (he falls,
    respawn at startPos with kFallDamage).  The bot steps off WEST onto her back while the male crosses her (no fall).
  - Her phases (8 / 24 / 24 / 12 health): ChooseEyePattern opens 3 of the 8 eyes ($16 / $92 / $94 / $86); a hit counts only
    when three eyes are struck within 4 frames (ProcessEyeHit's timer) -- one spin cannot reach eyes 48 px apart, but her
    back carries four clone tiles laid out exactly like eyes 1 / 2 / 4 / 7, 64 px behind them along her axis: the blue
    sword's split on the pattern's three tiles, the three Links walk 64 px onto the three open eyes and spin together.  The
    first hit sets every eye open ($FF) for 240 frames: more spins do up to 12 a cycle.  The charged sword (Link's and the
    clones') is pointed back at the tiles while walking (a held sword touching another open eye is a lone hit: the eye
    blocks, Link is thrown back); no sidestep near the eyes; the male's energy shot is let go at the tiles first (the
    charged sword stopping a shot ends the charge).
  - Male phases 1 / 2 (12 health): the male circles her and swims to her centre ($200,$210): a Roc's Cape hop as it comes
    (walking into it only pushes Link out to 36 px) -> action 6 to a far corner, its eyes ($62) open 45 frames every $F0 at
    +-24 / +-16..18: Link steps in line with the eye on its back and swings (3 a hit); the tail's whip (every $B4 / $168)
    is jumped with the cape when the tip comes; at 0 it swims back to her, under her (a rider is held off her body):
    a cape hop onto her floor out of its $20 reach (else it carries Link on and the phase waits).
  - Male phase 3 (male 2 again, 12): the zig-zag round her body (east over her head, west along her tail end at y ~$23C):
    Link stands on its west-bound line and hops straight up 80 px before it arrives -- it swims under him; the ride as
    above; its death -> a hop back onto her floor.
  - Female phase 4 (12): children every 360 frames (rows of five, 40 px apart, straight at Link): sidestepped like the
    shots.  FightEnd: the explosions, the drift north, the white fade, LV5_CLEAR / $7B -> $70:00 (472,216) (`r89_g_gyorg`).
- [x] **The Wind Element + heart container** (`seg_h89`, `r89_h_element`): FOUR_ELEMENTS $AC at (472,200): "You got the Wind
  Element!" + its two lines; the heart container (504,264): **max 56 -> 64** (hp 64).
- [x] **Goal 3 (start): out of the palace** (`seg_i89`, `r89_i_out`, **latest**): the blue WARP_POINT (440,264) -> area $31
  (120,120), Ezlo: "At last, we've got all four elements! / Let's go revive the sacred blade!".  Not done: the way back to
  Hyrule Castle's Elemental Sanctuary; $70:21's Chuchus.
- [x] **BossGyorg.lua checked against the cartridge** (gyorgBossObject.c: SetupStart / the eight phase functions / sub_080A1DCC
  / sub_080A20B8 / sub_080A1C9C; gyorgFemale.c Action1-3, ProcessEyeHit, ChooseEyePattern, sub_080465C8; gyorgFemaleEye.c
  all actions + OnCollision; gyorgFemaleMouth.c; gyorgMale.c actions 1, 2, 5, 6, 7, sub_08047D88 / DF0 / E58 / EA4 / F68 /
  08048004; gyorgMaleEye.c; gyorgChild.c; gyorgTail.c Action1 / 2): phases, health, riding (carry, turn, hold at her edge,
  push-out), damage per eye hit, the eye cycle (120 / 1080 / 1320 / 1440), the whip / eye / children timers match.  No
  BossGyorg change was needed; the two gaps were in the Four Sword's clones:
- [x] **Port gaps fixed: the Four Sword's clones** (new `FourSword89.lua`, wraps FourSword.frame / FourSword.deleteClones,
  guard `FourSword.tiles89Installed`, listed in R27A; FourSword.lua's cloneSwords: two anchored lines):
  - playerClone.c puts the clone tile back (CloneTile TILE_TYPE_789) when the clone leaves PlayerClone_Action1 (out with
    Link at chargeState 5, or deleted); the port kept every used tile marked for the rest of the room visit, so a room
    allowed ONE split per tile (Gyorg's back -- a split per eye pattern -- was unwinnable after the first).
  - the clones' sword boxes hit with the swing's hurtType (Sword84) and without f.swordHurt31, so during a spin the boss
    parts read HURT_SWORD: the clones' boxes did nothing to Gyorg's eyes.  The clone's sword child does Link's move:
    `FourSword89.cloneHurt` gives the spin's hurtType (SwordSkills.spinHurt) while Link spins.
- **Aids:** none -- no FULLHP / KEEPHP, no flags, no state pokes in the kept route.  Development runs with real keys (the
  bot being built, not kept): about twelve fight attempts (two deaths: phase 4 with the first bot (energy shots), phase 7 before the
  zig-zag hop); `probe_m89` / `probe_o89` poke state (eye flags, healths) to reach a phase -- development only.
- Seen, not changed: the arrival's fall (above) is the decomp's logic, not a port slip; the female's tail and the males'
  bodies touch Link on her rim; children can only be stepped out of.  The bot loses rounds to late patterns and shots
  (the fight could be shorter).
- Tests: `tests/zelda_tmc_r89_test.lua` (19 checks: tile release on leaving action 1 / deletion, deleteClones, cloneHurt
  per move, the seams); all 122 `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101)
  pass.  ObjErrors 0 in every session.
- Regression (FourSword89 in): r86 C + D (the clone split and the four switches -> $69) passes.
- Real-app replay (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 54, `s89.lua` / `run89rt.sh`): B from
  `r89_a_hearts` (hp 56), then G + H + I from `r89_b_hearts` -- the fight frame for frame as the harness run (every phase /
  hurt line identical, hp 48 at the end), the Wind Element, max 64, the warp to $31; all passing, ObjErrors 0.  Shots:
  `r89/shots/000907_s89_spin_wide.png` (three Links spin on the three open eyes), `000907_s89_ride_wide.png` (riding the
  blue male over her), `000609_i89_out_wide.png` (out of the palace after the Wind Element).
- [ ] **Next:** from `r89_i_out` ($31 (120,120), max 64, all four elements): back down from Cloud Tops to Hyrule Castle's
  Elemental Sanctuary (the Four Sword); $70:21's Chuchus (round 79's Goal 3) still open.
- Estimates: ~99.1% of the story verified with real input, ~97.8% of the port (old scale).

## Round 90 (from Cloud Tops back to the castle with real keys: the Ocarina to Mt. Crenel, down the mountain, Trilby Highlands, Hyrule Town, the castle garden past the four patrolling guards unseen, the north-west ladder, the castle, the Elemental Sanctuary: **the Wind Element infused -> the Four Sword** (script_Npc4EThirdSanctuary, the charge macro, the rumble, the doorway) -> the stained glass: **the story panels ported** (cutscene.c's aux cutscene, Story90) -> Vaati's reveal (it played on a black screen before) -> the four Links on the metal door's buttons -> the hall's door now leads to **Dark Hyrule Castle** (Exits90) -> the Four Sword's spiral beam breaks the curse on Minister Potho and the two guards -> DHC $88:1C -> $88:37)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r90/` (`go.sh` + `pre90.lua` (checkpoints in `r90/ck`, falling back to r89 ..
r38; loads `r71/lib71.lua` and `lib90.lua`), `scene90.sh` / `run90.sh` (outputs in `r90/out`, harness shots in `r90/shots`,
pictures in `r90/img`), `lib90.lua` (`H.pts90` / `H.path90` / `H.path90r` / `H.exitBy90`: a 4 px BFS planner on
`H.mfree71`; **`H.path` falls back to it** (round 18's 8 px planner finds no way through 8 px gaps since Link's collision
became the cartridge's sensors in round 80 -- every `H.travel` / `H.goTo` / `H.sneak71` that failed this round failed
there); `H.danger71` + a facing cone (`H.cone90`); `H.scanUnk90` / `H.missing90`: unknown script commands and
`Script.missing` natives), segments `seg_a90`, `seg_b_*` (round 71's D / D2 / E2 copied + `seg_b_d1b90` / `seg_b_e1_90`),
`seg_c90`, `seg_d90`, `seg_e_*` (round 71's H2 / I / J / K / K2 / L2 / M2 copied; I with the 4 px sneak), `seg_f90` ..
`seg_l90`, `seg_i0_90`, `seg_q90` (round 71's Q with the Four Sword), probes `probe_a90` .. `probe_m90` (read-only),
`rebuild90.sh` (cache 55 + the room audit), `ck90.lua` (the RomTablesCat checksums), the real-app kit `rt/` +
`run90rt.sh` + `s90.lua` + `rtall90.sh` (the replay piece by piece, outputs `r90/out/rt_*.txt`)).  Decomp read: the r72
sparse clone (data/scripts/sanctuary/*, cutscene/reveal/*, dhc/script_GuardStone1/2, script_MinishterPothoStone,
src/cutscene.c sub_080536B8 / sub_0805373C / sub_08053758 .. sub_08053A90 / gUnk_080FCCB4, src/subtask.c MenuFadeIn /
sub_080A71C4 / Subtask_FadeOut, src/subtask/subtaskAuxCutscene.c, src/data/data_080046A4.c gPlayerMacroSanctuary,
src/object/sanctuaryStoneTablet.c / metalDoor.c), the r49 repo (src/roomInit.c Sanctuary_Hall / CastleGarden_Main /
DarkHyruleCastleOutside_Garden, src/movement.c sub_080AF2E4 / sub_080AF284, src/data/transitions.c,
asm CheckPlayerInRegion).
**Cache version: 55** (was 54): manifest.r26b gains Story90's ranges (gUnk_080FCC84 / gUnk_080FCC9C, gUnk_080FCCB4) and
r35.bin gains Exits90.HALL / GARDEN / GARDEN_SOUTH (gUnk_0813A76C / gUnk_08134FBC / gUnk_08135048, addresses +
checksums in RomTablesCat) -- the harness cache, the real-app cache (`r27b/appdata/LOVE/tmc_bugs1`) and `testcache`
were rebuilt (`rebuild90.sh`; room audit 605 / 605, 0 mismatching) -- **players re-import once**.

- [x] **Goal 1: Cloud Tops -> the Sanctuary with real keys** (checkpoints in `r90/ck`): `r89_i_out` -> A the Ocarina
  (from $31) -> Mt. Crenel's crest (`r90_a_crenel`) -> B the crest's ledge (`r90_b_d_slope`), the climbable face at x 88
  (`r90_b_d_slope2`), the rock wall into $06:03 (`r90_b_d_0603`), the face at x 937 onto the lower band, down into $06:04
  (`r90_b_e_0604`) -> C east into Trilby Highlands $03:07 (`r90_c_trilby`) -> D the gap in the town wall -> Hyrule Town
  (`r90_d_town`) -> E North Hyrule Field -> the castle garden (`r90_e_h_garden`), through the maze unseen (the four
  patrolling guards; the last leg waits until the x 72 guard is at his lane's south end facing down), the north-west
  ladder -> $43:00 (`r90_e_i_43`) -> $43:01 (`r90_e_j_4301`) -> the castle $80:03 (`r90_e_k_castle3`) -> the Sanctuary
  entrance (`r90_e_k_sanctent`), the hall (`r90_e_l_hall`) -> the Sanctuary $78:01 (`r90_e_m_sanct`).
- [x] **The Four Sword** (`seg_f90`, `r90_f_foursword`): the pedestal (script_Npc4EThirdSanctuary): the sword in the
  pedestal, the Wind Element floating, the charges, script_PlayerPickUpFinalSword -> "The power of the Wind Element
  has infused your blade! / ... your blade has become the Four Sword! ..." (ITEM_FOURSWORD), EquipItem + SetPlayerMacro
  gPlayerMacroSanctuary (up, B held 120 frames, the spin) -> room flag 4 -> script_Npc4EFinalSwordRumble (the
  exclamation, the camera up to the north doorway, gUnk_080F55D8, Ezlo's TEXT_PANEL_TUTORIAL 2), local $7C.  Every
  command and native of the chain is ported (0 Script.missing, 0 unknown commands); the camera path (y 212 -> 136 ->
  0 -> Link) is the script's.
- [x] **The stained glass** (`seg_g90`, `seg_h90`, `r90_g_glass` -> `r90_h_reveal`): north through the opened doorway
  -> $78:02 (gUnk_080F5660: script_MinishVillageObjectPictureBackRoom) -> Link in its region (152, 56) +- (32, 96) ->
  Ezlo's TEXT_VAATI2 1 -> the story panels (below) -> the fake King Daltus becomes Vaati (TEXT_VAATI2 2, 3), Vaati's
  attack, Link faints (script_PlayerFaintAgain), the screen black but the text window (SetFadeMask $FFFF7FFF, below),
  Ezlo: "A! Wake up!" / "Vaati disguised himself as the king ..." (TEXT_VAATI2 4, 5), local $78, BGM_CASTLE_COLLAPSE,
  SEIIKI_BGM.
- [x] **Port gap fixed: the Sanctuary's story panels** (new `Story90.lua`, in R27B.MODULES; `N[$080536B8]`):
  sub_080536B8 = sub_080A71C4(5, 3, FADE_INSTANT, 4): the aux cutscene sCutsceneData[3] (CutsceneMain_Update ->
  sub_0805373C): six panels (gUnk_080FCCB4 read from the ROM: Font, WIN0 width x height, timer, fade speed) -- palette
  group $8A + i, gfx group $3A + i (the stained-glass pictures, BG2 256 colours), ShowTextBox(TEXT_PICORI 1 + i) into BG1,
  BLDALPHA $10 then the alpha steps (EVB n, EVA 16 - n / 2) that bring the text up outside WIN0, BGM_STORY; then
  DispReset, 60 frames, TEXT_PICORI 7 ("Heh heh heh... So that's what it means...") at window row 8, the fade out;
  Subtask_FadeOut -> the room fades in at speed 4.  The port had sub_080536B8 as a plain fade OUT: no panels, and the
  room stayed black until the script's next SetFade4 -- **the whole Vaati reveal played on a black screen**.  On Ppu.lua
  (Staffroll's fades); the field is frozen while it runs (R27B frame hook); drawn at the cartridge's 240 (View.wideOk).
  TextBox takes a script's window row (`self.posY`, one anchored line).
- [x] **Port gap fixed: the "all but the text window" fade mask** (`Story90.textKept`, one anchored condition in
  Field:drawOverlay): SetFadeMask $FFFF7FFF fades every palette but BG palette 15 -- the room, the sprites and the HUD go
  black, the message window stays (Fade70 handles the BG-only masks only; this one faded the text box too:
  TEXT_VAATI2 4 was unreadable).  The fade is drawn by R27B's draw hook, just under the text box.
- [x] **Port gap fixed: the Four Sword's exit lists** (new `Exits90.lua`, in R27B.MODULES; RomTablesCat Exits90.*):
  sub_StateChange_Sanctuary_Hall -> sub_080AF2E4: with ITEM_FOURSWORD the hall's exits are gUnk_0813A76C (its south door
  -> DARK_HYRULE_CASTLE_OUTSIDE_GARDEN); sub_StateChange_CastleGarden_Main -> sub_080AF284: Link in (0x78, height - 0x50)
  +- (0x78, 0x50) (CheckPlayerInRegion's unsigned test) -> gUnk_08135048, else with ITEM_FOURSWORD gUnk_08134FBC (the
  castle door -> DHC 1F entrance).  The port kept the rooms' own lists (Link walked back into the old castle).
- [x] **Out to Dark Hyrule Castle** (`seg_i0_90` + `seg_q90` + `seg_i90` in one session -- the buttons' room flag does
  not survive a reload -- `r90_i_dhcout`): $78:01's METAL_DOOR shuts as Link comes in from the north; the Four Sword's
  split on the three clone tiles (184 / 200 / 264, 520): four Links, two on the buttons -> the door slides away -> the
  hall -> its south door -> **DHC outside garden $89:01**.
- [x] **Vaati's curse broken** (`seg_k90`, `r90_k_cured`): gUnk_080EAE60's stone Minister Potho and two guards
  (script_MinishterPothoStone / script_GuardStone1 / 2: SANCTUARY_STONE_TABLET on each, room flags 0 / 1 / 2): a sword
  swing at each (the Four Sword's spiral beam) -> FX_MAGIC_STORM, the shake, the colours back, TEXT_BREAK_VAATI_CURSE,
  locals $93 / $94 / $95 -> the gate guard steps aside ($73).  South -> **DHC $88:1C** (`r90_j_dhc`) -> south -> **$88:37**
  (`r90_l_dhc2`, **latest**: an 816 x 416 hall with its enemies, hp 54 / 64).
- **Aids:** none -- no FULLHP / KEEPHP, no flags, no state pokes.  Health 64 -> 54 (tektites / peahats on Mt. Crenel).
  Harness only: the 4 px planner fallback (H.path), the sneak's cone.
- Not done: Dark Hyrule Castle itself (only its first two rooms entered); $70:21's Chuchus; the Gyorg bot's speed.
  Seen, not changed: the stone NPCs' gate guard stands in the doorway until the three are cured (as the script has it).
- Tests: `tests/zelda_tmc_r90_test.lua` (34 checks: wiring, no number tables, the Font / panel readers on a made-up
  reader, the whole sequence on a stand-in field (BGM_STORY, panel windows / timers, the 30-frame hold, the alpha ramp,
  TEXT_PICORI 7 at row 8, the end: fade in at speed 4), the native, wideOk, the $FFFF7FFF mask); all 123
  `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) + `zelda_widescreen_test` (101) pass.  Room audit 605 / 605.
  ObjErrors 0 in every session.
- Real-app replay (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 55, `rtall90.sh`: each piece from the
  checkpoint its harness segment started from -- one long session drifts (the tektites on Mt. Crenel)): A, B1, B2, C, D,
  E1-E3, F, G, H, I (I0 + Q + I), K, J, L all pass, ObjErrors 0 (`r90/out/rtall90.txt`).  Shots:
  `r90/shots/140032_f90_msg0505_wide.png` (the Four Sword infused), `140157_h90_story1530_wide.png` (a story panel),
  `140301_k90potho_cut180_wide.png` (the curse broken in the DHC garden), `140401_l90_at_wide.png` (inside DHC).
- [ ] **Next:** Dark Hyrule Castle from `r90_l_dhc2` ($88:37); $70:21's Chuchus; the Gyorg bot's speed; the intro's
  legend panels (cutscene.c sub_080536D4, the same panel code as Story90) if the new-game intro lacks them.
- Estimates: ~99.4% of the story verified with real input, ~98.0% of the port (old scale).

## Round 91 (Dark Hyrule Castle B1 / B2 with real keys: the entrance's pink rooms are drop-in pits, the way on is $88:35's west doorway; $88:33's GURUGURU_BARs (a space-time walker on the bars' own formula), $88:30's Stalfos skulls, a bomb through the east wall, $88:31's MINISH_PORTAL_STONE -> Minish back through $88:30 and $88:33 into the pit (HOLE_MANAGER $36) -> B2 $88:3A past the SPARK -> $88:38's crawlspace -> the prison's west cell -> the portal: full size -> the button -> the jail bars -> **King Daltus' curse broken -> a small key** -> back up through the bars -> $88:35's key door -> $88:37's west corridor (Wind Wizzrobes, Stalfos), the bottom room's Moldorms -> **the map** -> the stairs -> 1F $88:00 -> $88:29; two port gaps fixed: the cartridge's ProcessMovement0 for the SPARK (Move91) and the Moldorm's tail parts going with their head)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r91/` (`go.sh` + `pre91.lua` (checkpoints in `r91/ck`, falling back to r90 ..
r38; loads `lib91.lua` last), `scene91.sh` / `run91.sh` (outputs in `r91/out`, harness shots in `r91/shots`, pictures in
`r91/img`), `lib91.lua` (`H.loc91` / `H.ents91` / `H.settle91` / `H.chest91` / `H.bomb91` / `H.msg91` (a message's text by id,
read at runtime); `H.bars91` / `H.ballsAt91` / `H.hot91`: the GURUGURU_BARs' balls t frames ahead (DHCObjects' barUpdate
formula); **`H.stplan91` / `H.stwalk91`: a space-time BFS (8 px cells, a move per 7-10 frames, hole tiles kept 7 px away)
that walks Link through the bars' sweep, replanning on drift or a hit**; `H.sparkSim91` / `H.sparkDanger91`: SPARK futures by
running EnemyFoW.spark on copies), segments `seg_a91` .. `seg_w91` (`seg_c91w` = $1C west), probes `probe_a91` .. `probe_h91`
(a: every DHC room's header / exits / entity lists / tile entities (`out/pa91n.txt`, names by `tools/names.py` from the
decomp's enums); b / c / e: collision + act dumps, char maps; d: hint texts; f: the SPARK trace; g / h: the King's script state
and bytes), the real-app kit `rt/` + `run91rt.sh` + `s91.lua` + `rtall91.sh`).  Decomp read: the r49 repo (src/roomInit.c
DarkHyruleCastle_*, include/roomid.h / flags.h (LV6_*) / item.h / enemy.h / object.h / npc.h / room.h, asm/src/script.s
gTransitionTiles, src/playerUtils.c sub_08079550 / gUnk_0811C1E8, src/beanstalkSubtask.c (ACT_TILE_40: no Minish), src/scroll.c
UpdateDoorTransition / FindApplicableAreaTransition, src/manager/holeManager.c gHoleTransitions, ezloHintManager.c,
src/object/chestSpawner.c / lockedDoor.c / minishPortalStone.c, src/enemy/spark.c / doorMimic.c / moldorm.c, src/movement.c
CalculateEntityTileCollisions / ProcessMovement0 / MoveNorth .. MoveNorthWest), the r72 clone (data/scripts/dhc/
script_KingDaltusStone.inc).
**Cache version: 55, unchanged** (no import change) -- no re-import.

- [x] **Goal 1: Dark Hyrule Castle, B1 / B2 / into 1F, with real keys** (checkpoints in `r91/ck`, from `r90_l_dhc2`):
  - The entrance ($88:1C, Ezlo's "Whoa...! Is this really Hyrule Castle?") and its three neighbours ($37's top room, $35 / $36's
    east boxes) are low pink floors (act $0A) walled by the ledge acts $2A .. $2D that jump INTO them (gUnk_0811C1E8) -- the
    escape route's drop-ins.  The way on: $35's doorway at (9..10, 4) (L1 collision $29 / act $27, L2 act $52: layer 3, then
    act $0C: layer 2) onto its west corridor.  ($37's top room looked like a dead end the round before.)
  - Route: `r90_l_dhc2` -> B north to $1C -> C west to $35 -> D the doorway, the Spear Moblin (one hit taken) (`r91_d_35`,
    hp 46) -> E north to $33 -> F **the GURUGURU_BARs** (eight bars, 36 balls) by the space-time walker, no hit -> $30
    (`r91_f_30`) -> I the skulls woken and the Stalfos cut down (no hit), a bomb at the east wall (232,136) (BOMBABLE_WALL,
    flag $66) -> $31 (`r91_i_31`) -> J into the stone's ACT_TILE_61 (6 frames up) onto the MINISH_PORTAL_STONE, R: Minish
    (`r91_j_minish`) -> L back west through $30, south into $33, the bars again (Minish), into the pit (HOLE_MANAGER $36 ->
    gHoleTransitions: B2 $3A) (`r91_l_3a`) -> M past the SPARK (simulated), north to $38, the crawlspace (row 5, collision $14)
    east -> the prison $39's west cell (`r91_m_39`) -> N the cell's portal: full size (`r91_n_cell`) -> O the button (flag $6D)
    -> SECRET_MANAGER ($8F) -> the camera -> both JAIL_BARS open ($81) (`r91_o_bars`) -> P the Four Sword's beam at the stone
    King Daltus (room flag 0) -> his script: the curse broken (LV6_39_KING $96), "Take this key. You can use it to get out of
    the castle from the basement." -> **a small key** (LV6_1d_KEYGET $71) (`r91_p_key`) -> Q $39 -> $38 -> the stairs up ->
    $30 -> $33 (the bars, full size, no hit) -> $35 -> its key door (flag $6A) -> $37's west corridor (`r91_q_37`) -> R the
    Wind Wizzrobes and the Stalfos (no hit, hp 54 from drops) (`r91_r_west`) -> S the bottom room's two Moldorms (`r91_s_mold`,
    hp 46) -> T up the stairs: the big chest (408,152) -> **the dungeon map** (`r91_t_map`) -> U the west stairs (264,216) -> 1F
    $88:00 (`r91_u_1f`) -> V north -> $88:29 (`r91_v_29`, **latest**: $88:29 (133,200), hp 46 / 64, the map, no key).
  - Ruled out on the way: Minish Link cannot take $30's stairs (beanstalkSubtask.c ACT_TILE_40 returns at once for PL_MINISH --
    the port agrees), so B2 is reached as Minish through $33's pit; the left cell is entered only by the crawlspace.
- [x] **Port gap fixed: ProcessMovement0 for the SPARK** (new `Move91.lua`; EnemyFoW's spark: one anchored line):
  movement.c's ProcessMovementInternal -> MoveNorth .. MoveNorthWest on the COL bits of CalculateEntityTileCollisions (a side
  free: the step; one corner of it blocked and the other way free: a `speed` px slide, the collisions again, the step; a
  diagonal: each free axis its sine part).  The port moved enemies with its own corner test (EnemyDeepwood's solidBox), so a
  SPARK whose COL bits were clear could still be refused the step: $3A's sat 120 frames on a block's corner each lap (its
  wall-following switch never ran) -- now it runs round the blocks without a stop, as spark.c does.  (Only the SPARK uses it;
  the decomp's COL names on the east / west sides are kept as they are -- `$2000` is the upper probe.)
- [x] **Port gap fixed: the Moldorm's tail parts** (EnemyTraps: one anchored line): sub_08022D90 deletes a part when its head
  is gone (parent->next == NULL); the port deleted them only from the head's own update, which no longer runs once it dies --
  the six parts stayed in $37 as solid, harmful bodies.
- Checked against the cartridge and unchanged: the King's script (all commands ported; WaitPlayerGetItem's 45-frame wait sets
  KEYGET after the key), the JAIL_BARS / SECRET_MANAGER / CAMERA_TARGET_MANAGER / BUTTON chain, MINISH_PORTAL_STONE's tiles,
  BOMBABLE_WALL tile entities, CHEST_SPAWNER type 4 (always shown), LOCKED_DOOR type $0A (a key lock), the Flying Skulls ->
  Stalfos, the GURUGURU_BARs (DHCObjects' rotation matched the walker's prediction frame for frame), HOLE_MANAGER $36, the
  DOOR_MIMIC (it never woke: Link never stood at its point).
- **Aids:** none -- no FULLHP / KEEPHP, no flags, no state pokes.  Harness only: the space-time walker, the SPARK futures.
  **Practice death, not kept: 1** ($29: the fight bot pinned against the junction wall by a Spear Moblin's thrusts, 46 -> 0;
  the checkpoint before it, `r91_v_29`, is the latest).  Practice, not kept: I's first version (walking into the skulls, -12),
  S's first version (the bot chasing the invulnerable tail parts; the kept S fights the heads only), Q's first version (the walker stepped into $33's pit -> B2; hole tiles are now kept out).
- Tests: `tests/zelda_tmc_r91_test.lua` (22 checks: Move91 on stand-in rooms -- open floor, a full wall, the one-corner
  slides both ways, north past a corner, a diagonal, DIR_NOT_MOVING; the wiring; a Moldorm part with / without its head; a
  stand-in SPARK round a block without a stop; no ROM addresses); all 124 `tests/zelda_tmc_*_test.lua` + `zelda_input_test`
  (109) + `zelda_widescreen_test` (101) pass.  ObjErrors 0 in every session.
- Real-app replay (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 55, `rtall91.sh`, each piece from the checkpoint its
  harness segment started from): a (B + C west + D), b (E + F), c (I + J), d (L + M), e (N + O + P), f (Q), g (R + S), h (T + U +
  V) all pass, ObjErrors 0 (`r91/out/rtall91.txt`, `rtall91b.txt`).  Two pieces needed a harness fix first: J's blind 24-frame
  walk into $31 (now: walk until x 86), S's bot chasing the tail parts (now heads only).  The Moldorms' Random() differs in the
  real app: piece g ended at hp 12 there (48 in the harness).  Shots: `r91/shots/151345_o91_bars_wide.png` (the prison's bars
  open), `151345_p91_king_wide.png` (King Daltus cured), `151843_t91_map_wide.png` (the map's big chest in $88:37).
- [ ] **Next:** from `r91_v_29` ($88:29, hp 48 / 64, the map): the 1F loop -- $29's Spear Moblins (a bot that keeps out of the
  spear's line; the 4-px planner pinned Link at the junction), $2A -> $27 (four buttons: the Four Sword's clones, a small key),
  $28 / $26 (the cannon statues: reflect the cannonballs, Ezlo's hint), $23 / $24 (the tile puzzle) / $25, $20's compass, the
  throne $1F (OBJECT_BLOCKING_STAIRS after a Darknut), the four 3F tower keys ($01 .. $04), 2F's Darknut rooms, the big key
  ($88:09), 3F $06 (three Darknuts) -> Vaati; the intro's legend panels (sub_080536D4, gUnk_080FCCFC -- Native $080536A8 is
  still a plain fade); $70:21's Chuchus; the Gyorg bot's speed.
- Estimates: ~99.5% of the story verified with real input, ~98.1% of the port (old scale).

## Round 93 (Dark Hyrule Castle B1 east -> 1F north -> 2F with real keys: $36's Keese -> $34 **the second cannon room: the Four Sword's split in a column on the clone ring, the column into the four statue lanes, one spin of the four Links sends all four balls home** -> $32's Keatons, a bomb through the west wall -> $31's Winders -> $2F's blade traps (port gap fixed, Trap93) -> $22 -> **the throne room $1F: the Darknut won with the shield bot** -> the throne pushed east -> B1 $2D -> a game over at 2 health (Continue: 3 hearts in the same room, as the cartridge does) -> $1F -> $20 **the compass** -> $2D (the Gobdo burnt with the Lantern) -> $2E's Gobdos -> $20's east part -> $21 past the Moldorms -> **2F $0D**)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r93/` (`go.sh` + `pre93.lua` (checkpoints in `r93/ck`, falling back to r92 ..
r38; loads `lib93.lua` last), `scene93.sh` / `run93.sh` (outputs in `r93/out`, shots in `r93/shots`, pictures in `r93/img`),
`lib93.lua` (`H.mreach93` / `H.pic93` into r93/img; **`H.dodge93`: a path walk that holds / steps away from moving hazards**
(Winders, Moldorms); `H.burnGibdo93`: round 73's Lantern burn that stops on a room change and keeps east of a given x), segments
`seg_a93` .. `seg_q93`, probes `probe_a93` .. `probe_h93` (inventory / bottles, the coll/act dump, the $34 volley timeline,
the drop odds at Link's health (Drops.table), the game over's Continue, free-cell maps), the real-app kit `rt/` + `run93rt.sh`
+ `s93.lua` + `rtall93.sh`).  Decomp read: the r49 repo (src/manager/angryStatueManager.c, src/object/angryStatue.c,
src/projectile/cannonballProjectile.c, src/enemy/flyingSkull.c / keaton.c / sensorBladeTrap.c / gibdo.c / darkNut.c,
src/object/objectBlockingStairs.c / pot.c, src/itemUtils.c CreateRandomItemDrop, src/movement.c ProcessMovement12 /
IsTileCollision, src/gameOverTask.c GameOver_Init, src/game.c / src/gameUtils.c UpdatePlayerRoomStatus, include/item.h).
**Cache version: 55, unchanged** (no import change) -- no re-import.

- [x] **Goal 2: Dark Hyrule Castle with real keys** (checkpoints in `r93/ck`):
  - A `r92_o_8836` ($36, hp 10): the four Keese (no drops) -> B north up the corridor -> **$34** (`r93_b_34`).
  - C **$34's FLYING_SKULLs** (type 2: a STALFOS when Link comes within 48 px, flyingSkull.c sub_08039DD8): woken two at a
    time from below, cut down (no hit).  (No checkpoint after C: a reload re-enters $34 and the skulls are back.)
  - D **$34 the cannon statues** (ANGRY_STATUE_MANAGER: the west pair fire east in lanes y 106 / 138, the east pair west in
    lanes 122 / 154, all four at the manager's subtimer 1; a statue knocked out keeps its bit 30 frames, all four bits in one
    frame -> flag $68 -> the bollards ($69)).  The clone ring (act $57, rows 13-16) has a 4-tile column once the skulls are
    gone: the split down (6,13) .. (6,16) -> four Links in a column, Link at the bottom; east to x 128 under the lanes, up to
    y 152 once Link's own lane is clear (the balls touch Link only -- the clones stand in the lanes), the spin charged, Link
    facing **west**, released when the next volley's balls are 30 px from the column: the four Links' spin sends each ball
    straight back to its statue (from the Link in its own lane) -> SFX_SECRET, flag $68, the bollards down.  Facing up / right
    / down the upper Links' diagonal sweep met the middle lanes' balls first (sent off at a slant, never home); a plain swing
    cannot do it (the two pairs come from both sides at once).  -> E north -> **$32** (`r93_e_32`, hp 10).
  - F **$32's eight KEATONs** (fight bot; two contacts while shielding, 10 -> 6) -> G the four pots (random drops: none),
    **a bomb at the west wall** (BOMBABLE_WALL flag $67) -> **$31** (`r93_g_31`, hp 6).
  - H **$31's two WINDERs** by `H.dodge93` (no touch) -> the north archway -> **$2F** -> I straight up between the four
    SENSOR_BLADE_TRAPs (they rush at Link's row and go back to their walls) onto the stairs -> 1F **$22** (`r93_i_22`, hp 6).
  - J north -> **the throne room $1F**: REGION_TRIGGER -> FIGHT_MANAGER's Darknut (type 2, 20 hp) -> the shield bot
    (`H.dn85b`, 10 swings, one hit taken: its long slash, 6 -> 2) -> flag $5E -> SECRET_MANAGER: the east door ($8E)
    (`r93_j_1f`, hp 2).
  - K **the throne** (OBJECT_BLOCKING_STAIRS, its flag set): pushed east from its west side -> it slides 32 px (SFX_SECRET,
    its bank flag) -> the stairs -> **B1 $2D** (`r93_k_2d`).
  - L / M **a game over at 2 health** (the Keese fight for drops; at health <= 8 CreateRandomItemDrop adds 5 to the hearts
    slot, still ~9% a kill in DHC's tables) -> **Continue**: GameOver_Init sets health 24, the game restarts from
    gSave.saved_status, which UpdatePlayerRoomStatus copies at every room entry: **$2D's entrance with 3 hearts**, nothing
    lost (the port does the same) -> the Keese -> up the stairs -> $1F (`r93_m_1f`, hp 24).
  - N east through the opened door -> **$20** (its west part): the big chest (CHEST_SPAWNER type 4, local flag $5F) ->
    **the compass** (TEXT 0551) (`r93_n_20`, hp 24).
  - Ruled out: $20's west part does not reach its east part (a wall; the east part is $2E's stairs and $21's door); $0D's
    stairs up to 3F $02 stand on the raised floor west of the blocks, reached from its west door (LOCKED_DOOR, flag $4B) --
    not from $21's stairs.
  - P back to $1F -> the throne's stairs -> $2D: the Keese, **the Gobdo burnt with the Lantern from behind** (gibdo.c contact
    $87 -> action 8 -> a STALFOS) and the Stalfos cut down (24 -> 18, two pit falls) (`r93_p_2d`) -> Q east -> **$2E's two
    Gobdos** (fight bot, 18 -> 14; the bot backed out west into $2D once and went straight back in) -> the stairs up ->
    **$20's east part** (`r93_q_20e`) -> O east -> **$21**: past the two MOLDORMs by `H.dodge93` (no touch) -> the stairs ->
    **2F $0D** (`r93_o_0d`, **latest**: $88:0D (168,72), hp 14 / 64, the map, the compass, no key).
- [x] **Port gap fixed: SENSOR_BLADE_TRAP on its own layer** (new `Trap93.lua`; EnemyTraps' sensorBlade: three anchored lines):
  sub_0802BA8C / sub_0802BAFC move by ProcessMovement12 (IsTileCollision's lookup row for type 12 is type 0's -> Move91's
  ProcessMovement0 move) on the trap's collisionLayer; sub_0802BB2C reads gMapTop for a layer-2 trap.  The port moved it by
  its own corner test and probed **layer 1**: in DHC (all on layer 2, layer 1's collision empty) a trap that had rushed went
  back **through its wall and on out of the room** ($2F: x 88 -> 21, x 184 -> 250, still moving), and its probe never saw a
  wall.  Now each goes back to its wall and waits again.
- Checked against the cartridge and unchanged: ANGRY_STATUE_MANAGER / ANGRY_STATUE / the cannonball (DHC92) in a second
  layout, FLYING_SKULL type 2, KEATON, WINDER, BOMBABLE_WALL, FIGHT_MANAGER + SECRET_MANAGER + LOCKED_DOOR, the Darknut,
  OBJECT_BLOCKING_STAIRS' push and slide, CHEST_SPAWNER type 4, GOBDO (the Lantern burn, the grab and bites), MOLDORM,
  CreateRandomItemDrop (Drops.lua: +5 hearts at <= 8 health), the game over's health 24 and room-entry restart.
  Seen, not changed: two Keaton contacts while Link shielded toward them (not traced); the harness loader moves Link off a
  doorway onto a "safe" spot ($2F: onto the blade traps' row), so no checkpoint was kept in $2F.
- Not done: the four tower keys / the big key / 3F / Vaati (goal 2's rest; next: $0D's west door (flag $4B, $0C's light
  puzzle) or 2F from $00's wings $2B / $2C); the intro's legend panels (goal 3: a new import range and a cache bump).
- **Aids:** none -- no FULLHP / KEEPHP, no flags, no state pokes.  Harness only: the bots, the volley timeline, the hazard
  walk.  **A game over kept: 1** ($2D, at 2 health; Continue = the cartridge's 3 hearts in the same room -- used as the heal,
  no heart pot being in reach).  Practice deaths, not kept: 3 (D's first try from a $34 checkpoint whose reload brought the
  Stalfos back; Q's first two tries: the Lantern bot walked out west into $2D onto the burnt Gobdo's Stalfos, then a Gobdo's
  grab and bites).  Practice, not kept: the spin's facing / release-distance scan in $34 (up / right / down, 22 .. 38 px).
- Tests: `tests/zelda_tmc_r93_test.lua` (17 checks: Trap93 on a stand-in room with a layer-2-only wall -- west / east stops,
  the layer deciding, DIR_NOT_MOVING, the probe by layer; through EnemyTraps: the way back ends at the wall (action 3 -> 1),
  a rush ends at its range; the wiring; no ROM addresses); all 126 `tests/zelda_tmc_*_test.lua` + `zelda_input_test`
  (109) + `zelda_widescreen_test` (101) pass (`r93/out/tests93.txt`).  ObjErrors 0 in every session.
- Real-app replay (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 55, `rtall93.sh`, each piece from its segment's
  checkpoint): a (A + B), b (C + D + E), c (F + G), d (H + I), e (J), f (K), g (L + M: the game over at 2 health happens
  there too, then Continue), h (N), i (P), j (Q), k (O) all pass, ObjErrors 0 (`r93/out/rtall93.txt`).  Shots:
  `r93/shots/184103_d93_column_wide.png` (the four Links in a column in $34), `184103_d93_after_wide.png` (the statues out),
  `184208_k93_throne_wide.png` (the throne pushed aside, the stairs), `184226_n93_compass_wide.png` (the compass).
- [ ] **Next:** from `r93_o_0d` (2F $0D, hp 14 / 64): heart pots first ($16 / $09 / $06); $0D's raised floor (its west door,
  flag $4B from $0C's light puzzle) and its stairs to 3F $02 (a tower key), or 2F from $00's wings ($2B -> $19, $2C -> $1D);
  the four tower keys, the big key ($09), 3F $06 -> Vaati; the intro's legend panels (a cache bump); $70:21's Chuchus.
- Estimates: ~99.65% of the story verified with real input, ~98.25% of the port (old scale).

## Round 94 (Dark Hyrule Castle 2F's east branch with real keys: $0D's south stairway -> the east rampart 89:03: **three cape jumps into the whirlwinds, one glide over the Bow Moblin's platform to the third platform** -> 89:04's upper part (two Spear Moblins by the shield bot) -> $88:12's middle band -- a dead end from this side (below); port gap fixed: **the Keaton's dagger ignored Link's shield** (Keaton94); **the new file's legend panels** (Legend94: cutscene.c sub_080536D4 on Story90's panel code, no new import); no heal reached, no tower key)

Scratch: `G:/Gen2Recomped/scratch_claude/zelda/tmc/r94/` (`go.sh` + `pre94.lua` (checkpoints in `r94/ck`, falling back to r93 ..
r38; loads `lib94.lua` last), `scene94.sh` / `run94.sh` (outputs in `r94/out`, shots in `r94/shots`, pictures in `r94/img`),
`lib94.lua` (`H.mreach94` / `H.pic94` into r94/img, `H.inv94`, **`H.ww94`: a cape jump into a WHIRLWIND, then the glide steered
through waypoints** (each whirlwind passed lifts Link again: z ~30 -> ~55)), segments `seg_a94` / `seg_b94` / `seg_c94` /
`seg_l94` (the legend from a fresh file), probes `probe_a94` .. `probe_l94` (a: $0D -> 89:03 look; b: border tiles; c: 89:04
look; d / e / j: $12's collision / act grid, edge and cape tries; f: $12's reach per layer from both doors and the north door
(Link placed by hand, look only); g: a room's grid; h: the Four Sword's split on $12's clone tiles; i: the light-blue square;
**k: 2F connectivity from the collision only, per layer, over the whole floor** (`img/pk94_L1.png`); l: the legend), the
real-app kit `rt/` + `run94rt.sh` + `s94.lua` + `rtall94.sh`).  Decomp read: the r49 repo (src/roomInit.c
DarkHyruleCastle_2F* / 3F* (room names, the Darknut lists), include/roomid.h / room.h (TileEntityType) / tiles.h (ACT_TILE_116
SURFACE_EDGE, ACT_TILE_87 SURFACE_CLONE_TILE), src/room.c (TILE_ENTITY_D = the fight BGM), src/object/bossDoor.c,
src/object/lockedDoor.c sub_08083734, src/manager/lightLevelSetManager.c, src/manager/angryStatueManager.c,
src/object/playerClone.c, src/playerUtils.c gUnk_0811C1E8 (the ledge jumps), src/player.c SurfaceAction_6,
src/enemy/keaton.c, src/projectile/keatonDagger.c, src/playerItem/playerItemShield.c, src/cutscene.c sub_080536D4 /
gUnk_080FCCFC / sub_08053758 .. sub_080539BC).
**Cache version: 55, unchanged** (no import change: the legend uses Story90's imported range) -- no re-import.

- [ ] **Goal 1: heal** -- not reached.  The heart pots ($16 (184,88) / (216,104), $09 (56,72) / (56,88), $06, and 89:02's
  two) are all off the branch Link stands on (below).  Health 14 -> 12 this round (one Spear Moblin thrust).
- [x] **Goal 2 (part): the east branch with real keys** (checkpoints in `r94/ck`):
  - A `r93_o_0d` ($0D (168,72), hp 14) -> the south stairway (136,192) -> **89:03, the east rampart** (89:03's exit) -> walk off
    the first platform's south edge, the cape (A) -> caught by the WHIRLWIND (136,280) -> the glide: (184,328) -> (216,408) ->
    (152,488) (each whirlwind lifts Link again), over the Bow Moblin's platform without landing -> **the third platform**
    (`r94_a_8903`, (124,552), hp 14, no hit).
  - B south -> **89:04's upper part** -> its upper west door (56,92) past the two Spear Moblins (no hit) -> **$88:12** (`r94_b_12`,
    (222,94), layer 1, hp 14).
  - C (from `r94_a_8903`, the other branch) 89:04's upper part: **the two Spear Moblins by `H.mob92`** (4 shield blocks, one
    thrust taken: 14 -> 12) (`r94_c_8904`, **latest**: 89:04 (98,73), hp 12 / 64, the map, the compass, no key).
  - **Why no further:** 89:04's upper and lower parts are split by a solid wall (rows 9-10, both layers; the lower part holds
    the three Keatons, the lower door into $12 and the way south to 89:07 / $1D); $12's upper door leads onto its middle band
    (the GURUGURU_BAR, the four clone tiles), which ACT_TILE_116 rails (SURFACE_EDGE = SurfaceAction_6, the cucco-pen fence's
    surface: half-tile collisions) cut off from the north strip (the door to $10) and from the south part.  Tried and ruled
    out: the ledge acts ($2A .. $2D only jump INTO the floor from the doors, gUnk_0811C1E8), cape jumps at the rails, the Four
    Sword's split on the clone tiles (the clones are rigid offsets of Link, playerClone.c), the light-blue square (solid).
    The collision-only 2F map (probe k) agrees: the band is a component of its own.  Not settled: whether something
    (a flag) opens the band on the cartridge -- the clone tiles suggest a use not found.
  - **The 2F plan read from the cartridge** (roomid.h names, roomInit.c, the room entity lists): $0A BLUE_WARP's fight sets
    flag $86; only then do the four Darknut rooms ($0E / $10 / $13 / $15, sub_StateChange_DarkHyruleCastle_2F*Darknut*) load
    their Darknuts, and their BOSS_DOOR type-1 shutters close behind Link (lockedDoor.c sub_08083734) until 88 / 89 / 8A / 8C.
    $0C's eight LIGHT_LEVEL_SET_MANAGER type-3 torches (they go out after a time) -> FLAG_AND_OPERATOR $4A -> SECRET $4B
    opens $0C's north door and $0D's west door (the raised floor, the stairs to 3F $02).  $09's four DESTRUCTIBLE_TILE tile
    entities (flags $44 .. $47, a column left of the big chest, flag $43 = the big key) are where the four tower keys go
    (3F $01 .. $04's small chests, flags $3E .. $41).  The towers: $07 (TL), $0D (TR, raised), $19 (BL), $1D (BR, a BUTTON
    opens its stairs door, flag $5D).  The ramparts: 89:03 -> 89:04 -> 89:07 (-> $1D) -> 89:06 (-> $17 / $1A) -> 89:05 (-> $19);
    89:02 (two heart pots) hangs off $07 only.  Way on from here: back over 89:03's whirlwinds to $0D -> $21 -> B1 -> 1F $00
    -> the wings $2B -> $19 (tower $03, 89:05) / $2C -> $1D (the button, tower $04, 89:07 -> 89:04's lower part -> $12's
    south part / $15).
- [x] **Port gap fixed: the Keaton's dagger and Link's shield** (new `Keaton94.lua`; EnemyField1's Keaton action 4: one
  anchored line): on the cartridge the charging Keaton's dagger is a projectile (KEATON_DAGGER) and a shield held toward it is
  an entity of its own in front of Link (PLAYER_ITEM_SHIELD, gUnk_08127240) that takes the hit -- no damage, and the
  Keaton's body meeting the shield stops the charge (Keaton_OnCollision, contact $CC -> sub_0803275C).  The port tested the
  dagger against Link's body only and always hurt him (and stole rupees): **the two hits in $88:32 while shielding (round
  93)**.  Now a dagger touch from Link's shielded front clanks (SFX $118), the charge stops, no damage, no theft.
  SIMPLIFIED: "the front" is Player:blocksFrom (the port's shield cone, as for body contacts), not the shield's own hitbox.
- [x] **Goal 3: the intro's legend panels** (new `Legend94.lua`, in R27B.MODULES after Story90): sub_080536D4 = the aux
  cutscene sCutsceneData[0] (gUnk_080FCCFC): sub_08053758, then panels 0 .. 4 of gUnk_080FCCB4 (sub_08053800 / sub_08053894:
  palette group $8A + i, gfx group $3A + i, TEXT_PICORI 1 + i, the window, the alpha ramp), the fifth panel's hold fading out
  at speed 1 (sub_08053904), then the game (sub_08053974).  It is Story90's panel code with five panels; the table is the one
  imported in round 90, so **no new ROM range and no cache bump** (round 92's note that it needed one was wrong:
  gUnk_080FCCFC is a function table).  It plays once for a fresh file (Game.newSave: progress 1, no items, Link's room, under
  a second of play; `save.legend94` marks it), then Link's room fades in (speed 4) with its music.  SIMPLIFIED: the
  cartridge's scenes after the panels (Zelda through town to the Smith's house, gUnk_080FCBC4 / gUnk_080FCC14) are not
  played -- the port's new file starts in Link's room as before.
- Checked against the cartridge and unchanged: WHIRLWIND (the lift, the parachute glide), ANGRY_STATUE_MANAGER type 8 in 89:03
  (it always makes four statues from the room property; 89:03's list has two, so statues 3 / 4 land off the room at the
  following data's positions -- as the cartridge does), BOW_MOBLIN / SPEAR_MOBLIN, GURUGURU_BAR ($12: three balls, 4 damage a
  touch), the clone tiles' split, the ledge acts, BOSS_DOOR / LOCKED_DOOR types.
- **Aids:** none -- no FULLHP / KEEPHP, no flags, no state pokes on the route, no game over.  Harness only: the whirlwind glide
  steering, the moblin shield bot.  Look-only probes placed Link by hand (probe f) or reloaded checkpoints (e, j); none of
  that is on the route.  Practice, not kept: the first jump (from inside the platform: no catch), the route through $12's
  band (the GURUGURU_BAR: 14 -> 2 in a probe), the Keaton fight in 89:04 (the Keatons are behind the wall: the bot stood).
- Tests: `tests/zelda_tmc_r94_test.lua` (29 checks: Keaton94 on stand-in players (front / behind / no shield / up / no
  player), the hook's place before daggerHit; Legend94: listed after Story90, five of six panels, no ROM addresses, nothing
  new imported, the fresh-file test (progress / items / play time / room / once), the whole sequence on a stand-in field with a
  made-up panel table (BGM_STORY, five panels, the last fade out at speed 1, four at speed 8, no TEXT_PICORI 7, the fade in at
  speed 4, the room's music back, no second start)); all 127 `tests/zelda_tmc_*_test.lua` + `zelda_input_test` (109) +
  `zelda_widescreen_test` (101) pass (`r94/out/tests94.txt`).  ObjErrors 0 in every session.
- Real-app replay (ZeldaRuntime 1280 x 720, widescreen on, tmc_bugs1 cache 55, `rtall94.sh`, each piece from its segment's
  checkpoint): a (A), b (B), c (C), l (a fresh file: the legend's five panels, then Link's room -- asleep in bed, the room's own
  wake-up scene) all pass, ObjErrors 0 (`r94/out/rtall94.txt`, `rtall94b.txt`: piece l's first check wrongly wanted Link to walk
  at once; the replay of a / l with the shots).  Shots: `r94/shots/195849_a94_glide_wide.png` (the glide over 89:03),
  `195849_a94_landed_wide.png` (the third platform), `195859_l94_panel1_wide.png` / `195859_l94_panel3_wide.png` (the
  legend), `195859_l94_room_wide.png`.
- [ ] **Next:** from `r94_c_8904` (89:04, hp 12) back north over 89:03's whirlwinds to $0D -> $21 -> B1 -> 1F $00 (hearts on
  the way?) -> $2C -> $1D (the button, tower $04's key) -> 89:07 -> 89:04's lower part -> $12's south part / $15; $2B -> $19
  (tower $03); $0A's fight (flag $86) -> the Darknut rooms -> $0C's torches (flag $4B) -> $0D's raised floor -> tower $02;
  $07 -> tower $01 and 89:02's heart pots; the four keys into $09's key blocks -> the big key -> 3F $06 -> Vaati; what (if
  anything) opens $12's middle band; $70:21's Chuchus.
- Estimates: ~99.66% of the story verified with real input, ~98.3% of the port (old scale).
