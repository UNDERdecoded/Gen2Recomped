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
