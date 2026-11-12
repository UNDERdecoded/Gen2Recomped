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
| `Game.lua` | the runtime object: title -> file select -> the field, runtime hooks |
| `Title.lua` / `FileSelect.lua` | the title screen and the file select (round 5, on Ppu) |
| `MapMenu.lua` / `ExtractMaps.lua` | the pause map pages and their importer step |
| `KinstoneMenu.lua` | the Kinstone fusion window and the fuse-info flow |
| `SaveMenu.lua` | pause screens 8-11: sword techniques, sleep, save |
| `ExtractFx.lua` | BG animation frames, palette frames included |
| `BossMadderpillar.lua` | Madderpillar (madderpillar.c) |
| `Crenel.lua` | the windcrest bits, Windcrest_Unlock (round 6), the round-5 hooks for Mt. Crenel (stubs) |
| `Fusers.lua` | native NPC fusers: GetFuserId, GetFusionToOffer, InitializeNPCFusion (round 6) |
| `Barrel.lua` | Deepwood's rolling barrel: the manager in room $20, BIG_BARREL outside (round 6) |
| `ZeldaFollower.lua` | the Zelda follower and zelda.c's hand-over calls (round 6) |
| `NpcParts.lua` | multi-part NPCs: LoadExtraSpriteData, the `_Head` functions, the part drawer (round 7) |
| `ObjStatic.lua` | fixed-frame objects: furniture (FurnitureCfg), archways, masks... (round 7) |
| `FuseBubble.lua` | the fusion bubble over a fuser (CAMERA_TARGET, round 7) |
| `Minecart.lua` | mine carts (minecart.c) and riding them (round 7) |
| `Pacci.lua` | the Cane of Pacci: swing, bolt, charged holes (round 7) |
| `Climb.lua` | ladders, ladder tops, climb walls and the Grip Ring (PlayerClimb, round 8) |
| `BusinessScrub.lua` | the Business Scrub and its Deku seed; its sales (round 8) |
| `CrenelPath.lua` | bottles, Mineral Water, the Crenel bean, Melari's Mines natives, ShowNPCDialogue (round 8) |
| `BossGleerok.lua` | Gleerok, simplified (round 8); kept as the fallback (`BossGleerok.simple`, a cache without manifest.r25) |
| `BossGleerok2.lua` | round 25: Gleerok, gleerok.c ported (the neck's angle chain, intro, fight, plug, lava pools, death) + gleerokProjectile.c |
| `CoFObjects.lua` | round 25: LAVA_PLATFORM $59, OBJECT_ON_PILLAR $6D, MINISH_PORTAL_STONE $74 |
| `EnemyCoF3.lua` | round 25: RUPEE_LIKE $17, the red ChuChu (chuchu.c type 1) |
| `ExtractR25.lua` | round 25: the Gleerok tables (gleerok.s, manifest.r25; cache 18) |
| `ItemsR26.lua` | round 26A: the item dispatcher (use / frame / draw / water / giveItem hooks) |
| `ItemBoomerang.lua` / `ItemBow.lua` | round 26A: Boomerang + Magic Boomerang; Bow + Light Arrows, quiver and arrow GiveItem cases |
| `ItemCape.lua` / `ItemBoots.lua` | round 26A: Roc's Cape (DoJump, the cape boost); Pegasus Boots (charge, dash, PlayerBounce, DASH_SWORD) |
| `ItemMitts.lua` / `ItemLantern.lua` / `Swim.lua` | round 26A: Mole Mitts digging; the Lantern (burning); swimming with the Flippers (dive) |
| `ItemOcarina.lua` | round 26A: the Ocarina, BIRD $95 (Zeffa), Subtask_FastTravel and the wind-crest warp |
| `FourSword.lua` | round 26A: the split charge and the Link clones (f.playerClones, playerClone.c) |
| `SwordSkills.lua` | round 26A: sword charge, spin, Great Spin, Roll Attack, Rock Breaker, Sword / Peril Beam, Down Thrust |
| `EnemyField.lua` / `EnemyField1.lua` / `EnemyField2.lua` | round 26A: overworld enemies (Leever, Rock ChuChu, Acro Bandit, Keaton, Crow, Scissors Beetle, Cucco, Ghini; Spear / Bow Moblin, Takkuri, Lakitu, Cloud Piranha, Armos) |
| `RouteNatives.lua` | round 10: natives of the Minish Woods / Ezlo / Minish Village scenes, Forest Minish scripts by type2 |
| `RouteRooms.lua` | round 10: room code after the castle (the barrel Minish's house), registered by RoomCode.lua |
| `CutsceneObj.lua` | round 10: CUTSCENE_MISC_OBJECT C types 7 (the Jabber Nut), $13 (the Octoroks' rocks) |
| `SpecialWarp.lua` | round 10: SPECIAL_WARP_MANAGER: Minish-sized warp regions (village, Minish Paths, Deepwood courtyard) |
| `PortalJump.lua` | round 10: jumping onto / standing on / hopping off a portal stump (ACT_TILE_61) |
| `SpecialBg.lua` | round 10: rooms with a special 8x8 BG screen (the Minish houses, 256 colours) |
| `ExtractR10.lua` | round 10: small ROM tables read at import (manifest.r10) |
| `ExtractR11.lua` | round 11: hitboxes, interaction offsets, the Forest Minish look table, the layer-change table, the lever tables (manifest.r11) |
| `Hitboxes.lua` | round 11: Link / NPC / object hitboxes, solid NPCs pushing Link out, the A interaction test, Minish contact rules |
| `PlayerFall.lua` | round 11: PlayerFall (the fall animation, respawn, damage) |
| `Layers.lua` | round 11: CheckOnLayerTransition (stairs between a room's two floors) |
| `PushBlock.lua` | round 11: pushable block tiles (ACT_TILE_112) and PUSHED_BLOCK |
| `Lever.lua` | round 11: PULLABLE_LEVER |
| `Mushroom.lua` | round 11: PULLABLE_MUSHROOM and the fling (PLAYER_08072C9C) |
| `EnemyDeepwood.lua` | round 12: Puffstool, Sluggula and Mulldozer ported from puffstool.c / sluggula.c / mulldozer.c |
| `LilyRide.lua` | round 16: the large lily pad carrying Link from room to room (lilypadLarge.c sub_08085D60 / Action3), pad type rules |
| `Bollard.lua` | round 16: BOLLARD (bollard.c), raised / lowered by its flags, solid while up |
| `WarpPoint.lua` | round 16: WARP_POINT (warpPoint.c): the blue dungeon warps (types 0 / 1, EnableDungeonWarp) and the boss room's way out (type 2) |
| `BossChuchu.lua` | round 16: the Big Green ChuChu, chuchuBoss.c ported (four affine parts, all subActions, three phases); round 17: the cartridge's contact rules (hitbox helper $7C, static pushes), the puff's knockback, the intro's goo drops |
| `ElementFx.lua` | round 17: ELEMENTS_BACKGROUND (the element's glow, elementsBackground.c) and the element get's white flash |
| `Bombs.lua` | round 18: bombs (itemBomb.c, playerItemBomb.c, smokeParticle.c), BombableWallManager (tile entities and entity lists), destructible tiles, the Bomb Bag (GiveItem case 8) |
| `MinishTunnel.lua` | round 18: Minish doors and log tunnels (SurfaceAction_MinishDoorFront / _Back / _A / _B: hidden, no tile collision on the free axis) |
| `LadderUp.lua` | round 18: LADDER_UP (ladderUp.c), the ladders out of caves; the way out at its top is simplified |
| `EnemyTraps.lua` | round 17: blade traps, sensor blade traps, wall masters, aggressive cucco chicks, the Moldorm (their own enemy code); torch traps explained |
| `RemovableDust.lua` | round 19: REMOVABLE_DUST (removableDust.c): the Minish rock's nine spikes and their tiles, the rock's MINISH_PORTAL_MANAGER, lone dust on a Minish hole |
| `EnemyCrenel.lua` | round 19: Mt. Crenel's Tektite (tektite.c), Falling Boulder (fallingBoulder.c), Small Pesto (smallPesto.c), BounceUpdate; round 20: Peahat (peahat.c) |
| `Whirlwind.lua` | round 20: WHIRLWIND (whirlwind.c), PLAYER_PARACHUTE (PlayerParachute, sub_0807A2F8 onto cliff tops), EZLO_CAP_FLYING (the cap's affine scales) |
| `EnemyBeetle.lua` | round 21: Spiny Beetle (spinyBeetle.c) with its OBJECT_ON_BEETLE rock / bush (objectOnSpinyBeetle.c), Rollobite (rollobite.c) |
| `ObjBlank17.lua` | round 17: FAIRY (animation = type, fairy.c) and LADDER_HOLE (ladderHoleInBookshelf.c) |
| `Ledge.lua` | round 12: jumping off a ledge (sub_08079550, PlayerJump) |
| `PushAnim.lua` | round 12: ANIM_PUSH and its frame flag (sub_080790E4 / sub_0801A4F8), pushed pots (Pot_Action4) |
| `StatuePull.lua` | round 12: grabbing and pulling a PUSHABLE_STATUE |
| `ExtractR12.lua` | round 12: the ledge tables, the statue's per-area gfx (manifest.r12) |
| `Priority.lua` | round 14: BG / OBJ priority passes (BGxCNT priorities, UpdateSpriteForCollisionLayer) |
| `DoorWalk.lua` | round 14: walking into ACT_TILE_40 doors (PLAYER_ROOM_EXIT) and out of ACT_TILE_41 thresholds |
| `View.lua` | round 14 (port feature): zoom steps and the rooms drawn around the current one |
| `Seamless.lua` | round 14 (port feature): seamless room changes, crossfades, the CARTRIDGE TRANSITIONS option |
| `PotGust.lua` | round 14: pots in the Gust Jar's gust (pot.c Pot_Action3) |
| `Bg3.lua` | round 15: BG3 backgrounds of the ANIMATED / POW / STATIC background managers (skies, clouds) |
| `HouseDoor.lua` | round 15: HOUSE_DOOR_EXT, the field houses' doors (closed, opened by walking up into them) |
| `ExtractR15.lua` | round 15: the house-door room-property lists (manifest.r15) |

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
- **Link's flip / the sword** (bug round): the drawn flip is the keyframe
  flip XOR the entity flipX that `sub_08079064` sets for facing left; the
  blade is the attached PLAYER_ITEM_SWORD sprite (SPRITE_14/15/16, frame =
  Link's frame - $6A, palette 1, over or behind Link by the frame's unk_1).
  A runs the interaction check (`sub_080782C0`: talk, signs, chests) before
  the A item; lifting stays on R. A house door with no area warp beyond
  uses the room's border warp on that side.
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

### Round 5: the remaining screens, Madderpillar

`Ppu.lua` also does affine BGs, BLDCNT alpha blending, the OBJ window
and affine OBJs, fixed-width glyph cells. With these the cartridge's own
code draws these screens:

- **Pause MAP pages** (`MapMenu.lua`, `ExtractMaps.lua`):
  - the world map with clouds over unvisited regions;
  - the region maps, scrolled, with Link's and the fusion markers;
  - the dungeon maps drawn from `gDungeonLayouts` / gMapData outlines,
    with visited rooms, the current room, the floor list, and compass
    chests / boss.
- **Title screen** (`Title.lua`): the zooming affine sword, the light
  rays, the logo objects and sparkle, PRESS START.
- **File select** (`FileSelect.lua`):
  - the three plates with names, the hearts and elements;
  - Start / Copy / Erase, the copy targets, Quit / Erase;
  - name entry on the cartridge keyboard;
  - the cartridge's dialogs.
  - The runtime gives one save slot, so the three files live inside it
    (`fileSlots`).
- **Kinstone fusion window** (`KinstoneMenu.lua`):
  - the wheel, the names and plates, the slide, the bounce, the flash,
    the fused stone and the spin;
  - the fuse-info flow for scripted fusers;
  - online, both friends see the same window.
- **Sword techniques, sleep and save** (`SaveMenu.lua`): SAVE on ITEMS
  opens the save screen (screen 11).
- **Effects:**
  - the "!" / "?" / sleep bubbles are THOUGHT_BUBBLE's own frames;
  - iris fades (script 0x40 / 0x41);
  - palette BG animations (lava, water colours).

### Round 8: the Mt. Crenel path and Gleerok

Follows the cartridge:
- PlayerClimb and the four climbing surfaces by act tile ($53 / $F1 ladder,
  $3F ladder top, $50 / $51 climb wall and its top with the Grip Ring; the
  wall pushes back without it). The speed comes from Link's frame byte
  (sSpeeds), steps end on bit $40.
- The Business Scrub (businessScrub.c): hiding, popping out between 0x28
  and 0x50 of Link, the seed bounced back by the shield, the stars, the
  sales from gUnk_080CC954 (read from the ROM), its texts with the price
  ($06 $01) and the yes / no window ($07 continues with $2901, $05 choices).
- Bottles: catching Mineral Water from MINERAL_WATER_SOURCE, pouring
  (LinkEmptyingBottle's SPECIAL_TILE_59 -> 60 / 50 -> 51 swaps).
- CRENEL_BEAN_SPROUT: carried out of the Minish path (WATERBEAN_OUT),
  thrown into the hole (WATERBEAN_PUT), watered, grown after 192 frames,
  the vine tiles $1CE / $1CC / $1CB put back once its flag is set.
- Melari's Mines: the room code (lists by WHITE_SWORD_END / YAMAKOBITO_OPEN)
  and the scene's natives (the Mountain Minish look-at and lines from
  gUnk_08111284 / gUnk_0811130E, Melari's head, the broken sword);
  ShowNPCDialogue in full.
- Special tiles set with SetTile keep the cell's graphic.

Simplified (see "What differs"): Gleerok.

### Round 9: the new-game path, drops, Link's collision

- `Drops.lua`: CreateRandomItemDrop / CreateItemDrop / the area table
  (location, LOCATION_CHANGER, GRASS_DROP_CHANGER) / Random(), all tables
  from the ROM (gObjectDroptables $0800181C, gUnk_0800191C, the modifiers
  $08001A1C, SpecialFx gUnk_0811F960 and its variants, ItemOnGround's
  bounce sounds gUnk_0811E84C). Grass, bushes, pots, thrown bushes and
  enemies roll the cartridge's tables; the ground item rises, bounces,
  blinks and times out as itemOnGround.c does. A cut's outcome differs
  from hardware only because the cartridge's Random() is also stepped by
  everything else each frame.
- Link's tile collision uses his own tables (asm/src/player.s): seven state
  tables, 40 masks. Other entities keep IsTileCollision's tables.
- The draw order is ResolveOamDrawPriority's key (priority, then y).
- Hyrule Town at progress 1 is the festival town ($15) at the town's world
  position, with ZELDA_CHASE; the festival tour, the Castle Garden and the
  sword ceremony run from the cartridge's scripts (`Ceremony.lua` holds the
  C helpers they call). Simplified there: the cutscene objects' own
  movement (monsters, the flying sword, Zelda's magic) and the white flash
  are not drawn as on the cartridge; the scripts' flow and texts are.
- Ground items read their kind (paramB >> 8): buried (7) and sunken (8)
  items stay hidden, like the six red rupees by Link's house.

### Round 10: from the castle bedroom to Deepwood Shrine

- Castle room 4 is left through its west door (ACT_TILE_41, the next room
  of the area by map position); the assembly in room 2, the Smith's Sword
  and the map run from the cartridge's scripts. GiveItem / PutItemOnSlot
  are the cartridge's (A first, then B, else the same menu slot; only items
  1-$1F): the shield lands on A, the Smith's Sword on B.
- Hyrule Town stays the festival town (north exit only) until LV1_CLEAR,
  so the way to the Minish Woods is North Hyrule Field -> Lon Lon Ranch ->
  Eastern Hills North -> the woods, as on the cartridge.
- A blocked step ends flush with the obstacle on whole pixels (the
  cartridge works in x.HALF.HI): Link no longer stops 0.25 px short of a
  border lane.
- Ezlo's scene: the Octoroks' rocks (CUTSCENE_MISC_OBJECT $13 / $14),
  scripts can change a dressed object's animation (SetAnimation), scripted
  objects animate, SetPlayerActionNormal ends a player script, Ezlo's
  natives (face / flip / follow beside Link / the angry puff), the Octorok
  pen tiles (gUnk_081141F4), DeleteAllEnemies, ResetPlayerFlag(PL_NO_CAP).
- Portals: walking into a stump (ACT_TILE_61) for 6 frames jumps onto the
  portal; R there shrinks; Minish Link uses a portal from the manager's
  64x64 box and grows standing on the stump; a held direction hops off.
- SPECIAL_WARP_MANAGER regions take Minish Link into the Minish Paths, the
  village and the Deepwood Shrine Entry. The Minish Village intro, Festari,
  the Jabber Nut (CUTSCENE_MISC_OBJECT 7 in the barrel Minish's house),
  the Elder and Festari's back door run from the scripts. Forest Minish
  start their script from gUnk_08109D18[type2].
- The Minish houses are 256-colour special BG screens (SpecialBg.lua).
- A game saved at Minish size continues at Minish size.
- The Cane's bolt flips a pot (Pot_Action5: hop, upside down, breaks).
- The Zelda follower re-joins Link where he comes back after a fall.

### Round 11: hitboxes, the portal jump, falls, Deepwood's first rooms

- Hitboxes come from the ROM: Link (gPlayerHitbox, Minish sMinishHitbox),
  NPCs (gNPCHitboxes), objects (gObjectHitboxes), the pushable statue.
  Only NPCs whose code calls sub_0806ED78 are solid, and they push Link
  out of their box (CalcCollisionStaticEntity: the smaller overlap, at
  most 4 px a frame) instead of blocking him; Forest Minish, Gentari,
  Zelda and Ezlo do not.
- A talks / checks with sub_080784E4's test: Link's position plus the
  facing's interaction offset must fall inside the candidate's box.
  Checkable objects (the Jabber Nut) answer only at full size.
- Contact with enemies uses Link's hurtType (Minish: 1) in the collision
  matrix; CollisionNoOp entries let Link pass, handler 16 only pushes.
  ChuChus hurt only while they jump (hitType 90), as chuchu.c does.
- Minish Link's sword creates no PLAYER_ITEM_SWORD (itemSword.c): his
  swing has no hitbox and cuts nothing, on the cartridge too.
- The portal jump runs DoJump's sub-states (ANIM_HOP, SFX_PLY_JUMP,
  gravity, ANIM_LAND, SFX_PLY_LAND) along CalculateDirectionTo; the hop
  off moves until Link's back edge clears the stump (sub_080740D8).
- Forest Minish look at Link with gUnk_08109C98's head / body frames.
- Falling into a hole is PlayerFall: snap to the tile, ANIM_FALL, the
  respawn when it ends, 2 damage, 32 iframes; the Zelda follower keeps
  taking Link's position while he falls and re-joins him after.
- Link changes collision layer on gTransitionTiles (stairs to a raised
  floor): he collides with and draws over the top layer up there.
- A door with no warp of its own leads on only through the edge it sits
  on (the door under Link's feet no longer sends him across the room).
- Deepwood: the entrance statue (pushableStatue.c speed and push-out),
  pushable block tiles, the pullable lever, the bridge it lays, the
  pullable mushroom's fling, the barrel room's side buttons (Type4 tile
  and the web / log timings).

### Round 16: Deepwood finished, the Big Green ChuChu

- Deepwood B1 plays as on the cartridge through the real runtime: the lily
  pad crosses rooms with Link on it (LilyRide.lua), bollards, the pot pushed
  onto $15's button, $12's region flag $44, the compass corridor's blocks,
  the ring's pot, the jar flings off mushrooms (pullableMushroom.c Action3),
  the blue warps (warpPoint.c), the entrance webs, the boss door.
- The Big Green ChuChu is chuchuBoss.c (BossChuchu.lua): its art from the
  ROM, its sway and squash from the decomp's tables, 48 Gust Jar contacts on
  the base topple it, the sword on the lying head, three phases, the death.
- After it: the Earth Element's timings (fourElements.c), the heart
  container, the warp out from its own data, Ezlo's words outside
  (DeepwoodShrineEntry room code), the way back to the Elder.

### Round 17: the boss in one run, the Elder, toward Mt. Crenel

- The Big Green ChuChu touches Link as the cartridge does: only the hitbox
  helper (type 8, hit type $7C on the base's box, offset (0, +4)) hurts him
  (2 damage, 60 iframes, knocked at 2.5 px for 6 frames); the base itself
  ($7D) and the hanging parts (collision bit clear) never do; collision is
  off from the fall until the phase check; the base and the lying head push
  Link out (sub_0800445C).  The Gust Jar puff knocks the base back
  (sub_08027AA4 case 27); the head takes the sword as hurt type $7B (2
  damage, 30 iframes); the intro's goo drops use the particle object's own
  sprite and fall (chuchuBossStartParticle.c type 0 / 2).
- The Earth Element is drawn (its animation is its type, sub_08080CB4) with
  its glow (ELEMENTS_BACKGROUND, affine scale and EVA from its height) and
  the white flash of the get (SetFade(FADE_BLACK_WHITE | FADE_INSTANT, 2)).
- The new-game route wins the boss in the same run and goes on to the
  Elder: Gentari's words after the Earth Element, he steps aside (local flag
  $83), "head to Mount Crenel ... Melari" -- then back out through the woods,
  the Eastern Hills, Lon Lon Ranch, North Hyrule Field, Hyrule Town and
  Trilby Highlands to Mt. Crenel's entrance and up its first vines.
- Enemies and objects drawn by their own code: blade / sensor blade traps,
  wall masters, the Moldorm and its tail, aggressive cucco chicks, fountain
  fairies, ladder holes, the phonograph.

### Round 18: Belari's bombs and Mt. Crenel's base

- Bombs are cartridge code: placed in front of Link (up to three), 150
  frames, 80 frames of blinking (the last 40 with the affine pulse), then
  the blast (SMOKE_PARTICLE: its growing box hurts enemies and Link through
  the collision matrix, the 3 x 3 tiles get DoTileInteraction(3); bomb
  rocks break, bombable walls become SPECIAL_TILE_34 and their manager lays
  the opening, sets its flag and plays SFX_SECRET).
- Minish doors and hollow logs hide Minish Link and let him through solid
  tiles on one axis, as the cartridge's surface actions do.
- The cartridge's way to the bombs: from the Elder's back room the village's
  west border leads Minish Link into the woods by Belari's clearing, west
  through the hollow log, into his mushroom house: the Bomb Bag (10 bombs).
- Mt. Crenel's base: the red rupee, Trilby's cave (its east wall bombed) and
  the Business Scrub's bottle (shield, talk, 20 Rupees), water from the
  lake, poured on the planted bean, its vine, the bomb wall to the ladder
  cave and its LADDER_UP, the plateau, the rock before the spring bombed,
  Minish at the stone portal, the Mineral Water in the spring's path, grown
  again.

### Round 19: the Minish rock, the bean, Mt. Crenel's enemies

- Border exits use the cartridge's rule (UpdatePlayerCollision +
  sub_0807BDB8): moving towards an edge within 10 px of it, with the tile
  just ahead (N (0,-9), E (6,0), S (0,3), W (-6,0), ROM table $080B4490) of
  collision $FF, takes that border's exit.  (Link standing at y 792 of an
  800-high room on the $FF bottom row now leaves by DOWN, as on the GBA.)
- Round 20: WHIRLWIND ($5E) and PLAYER_PARACHUTE are their own code
  (whirlwind.c, PlayerParachute, sub_0807A2F8, EZLO_CAP_FLYING): a ledge jump
  (or any airborne Link at z <= -16) within 12 x 12 px of a whirlwind opens
  Ezlo's cap; the glide lasts 481 frames at speed $80 with the 32-way
  direction turning $20 / 256 a frame; pressed against a ledge face
  (gUnk_0811C1D8: N {42, 38}, E {45, 39}, S {43, 38}, W {44, 39}) with open
  floor 1 - 2 tiles past it, Link rises to z -32 and is carried over onto the
  cliff top.  Proven in the real runtime with real keys on Mt. Crenel's base
  (the pocket -> the lower-left cliff top) and middle (-> the ladder to
  $06:02).  Peahats run peahat.c; a touched fairy gives ITEM_FAIRY's
  ModHealth($20); bomb pickups respect the bag size; placed bombs can be
  lifted and thrown.
- Round 21: Peahat_OnCollision is ported (touching Link: back to Fly, no
  direction, flyTimer 120; the jar's puff: broken propeller; hurtType $14:
  sliced propeller, Recover, Hop, Takeoff) through a generic
  `e.onCollision(E, e, hurtType | $80)` hook in Enemies; the sword on a
  grounded Peahat is the matrix's ($71: 2 damage).  The Grip Ring is bought
  with real keys, and Climb.lua's climb walls carry Link up / down the rock
  walls of $06:02, $06:03 and $06:01 (the Crenel Wall) to the summit $06:00,
  room changes included.  Spiny Beetle + its rock and Rollobite run their
  decomp code (EnemyBeetle.lua).  Ezlo's cap shows its strings (type 1);
  a thrown bomb follows PlayerItemHeldObject's throw (speed $400, one bounce).
- REMOVABLE_DUST is its own code: the nine spikes on Mt. Crenel's Minish rock
  sit on the rock's tile types (387, 1018..1025), each puts SPECIAL_TILE_104
  on its tile; the Gust Jar's first contact grabs one (or the bomb blast);
  its tile becomes 388 / 1026..1033 (ACT_TILE_62); the last one sets all
  nine back and loads the rock's MINISH_PORTAL_MANAGER (type 1, type2 $102)
  and YAMA_04_ENTHOUSHI.  With the flag set the portal comes back on load.
- Mt. Crenel's white dust piles are tile type 111 (interaction mask $C028):
  the Gust Jar's gusts suck them away (filter 5); the orange tufts (type 112)
  are solid.
- The bean's chain was run with real keys (from a placement on the rock
  plateau): Minish at the rock, the hole at (210, 92) to $12:00, the bean
  lifted (R), carried out, thrown into the hole at tile (17, 2), grown again
  at the rock, the Mineral Water poured, 192 frames still, the vine, up into
  $06:03.
- Tektite, Falling Boulder and Small Pesto run their decomp state machines
  (BounceUpdate, GravityUpdate, the home rectangle helpers sub_08049FA0 /
  EE4 / FDC / F84).
- A room-placed entity from a list without a ROM address is keyed by its own
  data (kind, id, params, position): taken rupees stay taken after a reload.
- LINK_HOLDING_ITEM / FOUR_ELEMENTS frames are used when the GROUND_ITEM
  sprite has none for the item (the elements held up in the item get).

### Round 22: the item get, the summit to Melari, the Cave of Flames door

- The item get is player.c PLAYER_ITEMGET + linkHoldingItem.c (ItemGet.lua):
  IdleSouth, ANIM_GET_ITEM_SMALL $2E0 / _BIG $1B9 (or _NOCAP) by
  gItemMetaData flags & 1; SFX_ITEM_GET on Link's frame flag $41, the
  message on $42 (8 frames in), the item drawn while the frame has bit $40 at
  Link's sub-entry offset; Link puts it down only when the message is closed
  AND the animation is done (ResetPlayerAnimationAndAction).  Timers 1 / 3
  (no message; Melari's broken sword) follow InitItemGetSequence.  (Round
  21's empty text box was the bot re-talking to the scrub 563 times, not
  missing text; Link kept the item-get pose because nothing reset it.)
- PUSHABLE_ROCK ($2E, pushableRock.c) + the SPECIAL_TILE_27 push
  (PlayerPush type 1, 16 px): the round boulders of the summit and the
  pillar cave fall into their holes (SPECIAL_TILE_21, their flag,
  SFX_TASK_COMPLETE); MOVEABLE_OBJECT_MANAGER puts solved ones back.
- LIGHTABLE_SWITCH ($9D, both types) with the bridge room's latch
  (FLAG_AND_OPERATOR_MANAGER) and BRIDGE_MANAGER.
- The mushroom flight passes ledge tiles $1AC-$1AF (sub_08072D54); gusts
  use IsTileCollision type 1 (walls 1-$F and pits do not stop them); a
  thrown bomb uses type 10 (it flies over pits) and is lost in a pit /
  water / lava; ACT_TILE_13 pits drop Link (SURFACE_PIT, sub_08079C30).
- A bottled fairy can be drunk (+$20) and revives Link when he dies
  (sub_08071D04, +32).
- BOBOMB ($22, bobomb.c) except the Gust Jar grab; the sliced Peahat
  propeller is its own flying child (PeahatPropeller); the Spiny Beetle's
  line of sight is sub_0804A044 / sub_0804A4BC exactly.
- Route (real keys): summit mushroom -> portal -> Minish path $12:02 ->
  boulders -> ladder $26:00 -> block puzzle (solved by a breadth-first search
  over PushBlock's rules) -> mushroom room -> bridge room (bomb thrown onto
  the switch from the bridge stub) -> pillar cave (boulder, totem) -> chest
  cave (blocks, blue Kinstone) -> portal -> Minish path $12:03 -> Melari's
  mines $10:00 -> Melari's cutscene (the broken Picori Blade handed over) ->
  the guarded west door -> windcrest -> the Cave of Flames $50:03.

### Round 23: the follower's jumps, Link's layer in the Cave of Flames, its enemies

- The Zelda follower walks the cartridge's whole history item
  (zeldaFollower.c sub_08068318): x, y, z, facing, layer, FALL frames.  She
  has no collision on the cartridge either; without z she slid down cliff
  faces when Link jumped a ledge (drawn inside the wall).  An airborne
  oldest entry keeps her moving; she is hidden on FALL entries and put at
  Link when the fall ends; the refill (sub_08068578) is FixedDiv >> 8 with
  her own facing / layer.  NOT ported: her shadow in the air (sub_0806F854),
  DROWN frames (the port has no drowning framestate).
- The mushroom fling runs with COLLISION_OFF (player.c sub_08072CC0 to the
  landing): no hits mid-flight.  (A hit used to end the fling with Link
  stuck at z > 0: nothing could be lifted afterwards.)
- sub_0807A8D8 (every frame): the tile-type flags (sub_080B1B84, ROM
  gUnk_08000360 / gUnk_080B7A3E, manifest.r23) under Link on his layer:
  bit 1 -> layer 1, bit 2 -> layer 2 (Layers.surface).  The Cave of Flames'
  rooms have one flagged tile type ($310) on the bottom map and everything
  on the top map: Link is on layer 2 there (drawn over BG1, the top map's
  walls).  Room enemies get LoadRoomEntity's layer (kind byte, else
  ResolveCollisionLayer) and move on their own collision layer; a room
  change without a transition layer starts Link on layer 1, layer 0
  resolves it (a mine-cart ride keeps the rails' layer).  SIMPLIFIED: the
  path memory (bit 5) is not kept.
- SPIKED_BEETLE ($1E) and HELMASAUR ($20, both types) are spikedBeetle.c /
  helmasaur.c (EnemyCoF.lua); collision handler 10 (sub_080180E8: an enemy
  facing the attacker within +-$C blocks, else hitType $19's row) runs in
  Enemies:hit; the shield's contact is hurtType 2 for these two.
  SIMPLIFIED: ProcessMovement2 is the port's box test; the Helmasaur's
  dash puffs and the charge's tile interaction (filter 9) are not ported;
  Link's own push back on a blocked hit is not ported.

### Round 24: the Cave of Flames' rails, Spiny ChuChu, Chaser

- CoFRails.lua: MINECART_DOOR $6C (minecartDoor.c: shut doors are
  SPECIAL_TILE_34; a cart moving along the door's axis within 8 px across
  and $30 along opens it, 7 frames at $300 into the wall, SFX_10B; open, it
  shuts again by sub_08083734 / sub_08096D84 / an 8-frame timer), RAILTRACK
  $13 (railtrack.c: a three-tile turning rail, SPECIAL_TILE_24 / 25 = act
  tiles 242 / 243; type 3 follows its flag, 8 frames per quarter turn,
  SFX_151), HITTABLE_LEVER $2F (hittableLever.c: each new contact flips its
  flag, tile type $377 / $378, SFX_117, iframes $18), and
  RAIL_INTERSECTION_MANAGER $1F (the rail tile next to a turning rail:
  gUnk_08108C9C 856/857/854/858/858/855 by type and flag).  The carts read
  special tiles' act tiles (gMapSpecialTileToActTile) for these rails.
- Locked / boss / minecart doors use the whole gUnk_0811F690 art table
  (areas $40-$8F, 8 areas per value): the Cave of Flames' doors are $52
  (they were drawn with Deepwood's $0A).
- EnemyCoF2.lua: SPINY_CHUCHU $0B (spinyChuchu.c whole: the fall from the
  ceiling (z 128, its EntityData timer), spikes out near Link, the hop at
  him, shield / sword / blast contacts) and CHASER $1D (chaser.c: lined up
  -> slides, speeds up by 4 to $220, bumps the wall).  Enemies keep their
  EntityData paramB / paramC (e.spawnB / e.spawnC).
- SIMPLIFIED: the levers take the sword only (Field.swordBoxNow); the door
  puffs and FX_STARS are not drawn; Spiny ChuChu's spiked hitbox is the
  definition box + 4 (gHitbox_32 not read from the ROM).
- NOT DONE: RUPEE_LIKE $17 (rupeeLike.c: the rupee disguise, the grab and
  the rupee drain), the red ChuChu (chuchu.c type 1; still the shared
  model), LAVA_PLATFORM $59, OBJECT_ON_PILLAR $6D, MINISH_PORTAL_STONE $74,
  gleerok.c (BossGleerok.lua is still round 8's simplified model).

### Round 25: lava platforms, pillar blocks, portal stones, Rupee Like, red ChuChu, Gleerok

- Cache version **18**: ExtractR25.lua reads gleerok.s's tables
  (0x080CD7C4..0x080CD8A3: neck priorities, the intro moves, the phase
  health thresholds 240 / 240 / 245, the weighted waits, the plug's palette
  steps) into manifest.r25.
- CoFObjects.lua (hooks: one line in Dungeon:spawnObject; Pacci's bolt asks
  `e.onPacciObj`; on first use it wraps Dungeon.checkFall (a platform's
  field_0x14 keeps the lava from burning), Objects.portalNear (no portal
  before its stone) and PushableRock.tryPush (SPECIAL_TILE_54)):
  - LAVA_PLATFORM $59 (lavaPlatform.c): type 0 reads LavaPlatformEntry lists
    from room property type2 (16 bytes: rail, x, y, layer, type2, wobble,
    respawn) and spawns the platforms; UpdateRailMovement drives them;
    standing on one: 20 frames, the wobble under $8D frames (SFX_LAVA_TILE_*),
    sunk for respawnTime, rises; upside down (odd state) they only flip
    under the Cane's bolt (contact $1D; the spawner shows the flip: zVelocity
    2.75, gravity 36/256, FX_LAVA_SPLASH_HUGE).  Link is carried along the
    rail (SyncPlayerToPlatform) and drawn 3 px up (gPlayerState.spriteOffsetY:
    Player:draw reads `spriteOY` for the frame it was set).
  - OBJECT_ON_PILLAR $6D (objectOnPillar.c): SPECIAL_TILE_54 under it; Link's
    push (the tile beyond free for collision type $B) -> SPECIAL_TILE_55 +
    facing / 2 -> $20 frames at $80; stopped over tile type $71 / $72 /
    SPECIAL_TILE_32: its flag, SFX_10B, then by type: tile 0 / a chest tile
    $73 where an unopened chest is listed / a HITTABLE_LEVER with its hit
    flag; off the pillar tops ($78 / $7A): FX_ROCK, gone.  R grabs it and
    pulling slides it (StatuePull's hold).  Flag set at Init: straight to
    its stored spot (+$7C..+$7F).
  - MINISH_PORTAL_STONE $74 (minishPortalStone.c): hidden until its flag
    (or $FFFF): Link held while it fades in (16 steps of 8 frames), SFX_14A,
    SFX_SECRET, portal tiles SPECIAL_TILE_64..72 (gUnk_08123344 /
    gUnk_0812336A), global TINY_ENTRANCE.
- EnemyCoF3.lua: RUPEE_LIKE $17 (rupeeLike.c: a rupee (the ground item's
  sprite / palette by type) until touched or Link comes back into its home;
  sprite $D1 / fixed gfx $73 and its second part; Link's body -> held
  (COLLISION_OFF for him), every $41 frames -1 / -5 / -20 rupees, more than
  $2D new presses (or no rupees) and its 60-frame timer free him: jump out,
  iframes $A6) and the red ChuChu (chuchu.c type 1, gUnk_080CA25C actions
  0-10: the puddle, rise, chase, the jump at Link, sinking and sliding under
  the floor, the hit).  `e.collideOn` (Enemies' touch test) = an Init's
  COLLISION_ON for a definition without collision; `e.noHit` = COLLISION_OFF
  for the sword.
- BossGleerok2.lua (gleerok.c; Crenel.spawnEnemy picks it): the heap of
  joint words (unk_2c is filler2[5] = the head's elevation: the reach by
  Link's distance), sub_0802E518's layout with the sine table, the joint
  relax / follow helpers, the intro (Link looks round, shake, the plug
  grows, the rise, gUnk_080CD7F8's moves, BGM_BOSS_THEME), subActions 0-5
  (turn, track, breath, sweep, knocked out / lowered / open core / sinking
  / the rain, rise), sub_0802EBC4's weighted attack choice, the plug's
  types 5 -> 6 -> 3 -> 4 (Cane contact $1D, 8 particles, SFX_150), the
  phase change's four lava pools (GLEEROK_PARTICLE type 1: the scale /
  anchor / hitbox math, which also times the recovery), the death (fade,
  Link on the platform, $B4 frames of thrashing, sinking, the head's BG
  blend).  gleerokProjectile.c types 0-3.
- SIMPLIFIED: the pools' tile restore (type 2 0x80) and their affine draw
  (a scaled sprite here), FX_DASH / FX_ROCK / sparkles as the port's addFx,
  the Rupee Like's death drop (the generic table, not gUnk_080CCC34) and
  Link's sprite offset inside it, ProcessMovement2 / 5 as ProcessMovement0
  for the red ChuChu, sub_0800442E for the pillar block.

### Round 15: the room-art audit

- Every room (605, the 35 special 8x8 screens included) is checked against
  an independent reference built straight from the ROM by the decomp's
  loaders (LoadGfxGroups, LoadRoomTileSet, LoadRoomGfx, the tileset
  managers), tile for tile, and in the real runtime at every 240x160
  camera window after the room's code and swaps (2665 windows).
- Tileset loads are laid in load order: the dig caves' and the Outer
  Fortress of Winds' tilesets lay $2000 bytes at $1000 / $9000 over the
  area's base graphics; they were scrambled (14 rooms).
- The backdrop is black (LoadGfxGroups ends with SetColor(0, 0)) unless a
  tileset group reloads BG palette 0: house and dungeon margins and the
  transparent parts of the town's unswapped tiles were teal.
- Special 8x8 screens: 256 colours only in the Minish house interiors
  ($20) and the town's Minish holes ($2D); the beanstalk screens ($0D:$10-
  $14) are 4bpp on BG1 (gMapDataTopSpecial, characters at $4000); a screen
  both wider and taller than 255 px has four blocks (sub_0807C5F4).
- BG3 backgrounds (Bg3.lua): ANIMATED_BACKGROUND_MANAGER (Cloud Tops,
  beanstalk tops), POW_BACKGROUND_MANAGER (Palace of Winds) and
  STATIC_BACKGROUND_MANAGER (Mt. Crenel, Veil Falls' top, ...) with their
  scroll rules; also behind zoomed-out neighbours.
- House-type areas ($21-$25, $27, $28, $30, $38) run BG1 at priority 2
  ($1D46): sprites draw over their top layer.
- Hyrule Town's red house (BuildSecondOracleHouse: TATEKAKE_TOCHU frame,
  TATEKAKE_HOUSE house and its $800 bytes at VRAM $1800) and the USA tile
  at (43, 25) (sub_StateChange_HyruleTown_0).
- Rooms reload their map on every visit (the cached map was edited in
  place: cut bushes stayed cut, special tiles came back as holes).
- Objects whose Init sets no frame show frame 0 (a zeroed entity); giant
  twigs, huge decorations (with their parallax), acorns, shoes, the
  waterfall opening, the baker's oven, cabin furniture and the figurine
  device take their Init's frame, palette and parts; HOUSE_DOOR_EXT doors
  are drawn and open as Link walks up into them for 8 frames.
- Seamless room changes hold the new room's enemies for the cartridge's
  scroll time (60 frames left / right, 40 up / down).

### Round 14: priority, doorways, zoom, seamless rooms

- The picture is composed as the GBA does: BG3..BG0 and OBJs by priority
  (rooms: BG1 at 1, BG2 at 2), OBJs over BGs of the same priority, BG1
  over BG2; an entity's OAM priority is 2 on collision layers 0 / 1 and 1
  on layers 2 / 3, unless it sets its own (ARCHWAY 1,
  MINISH_SIZED_ENTRANCE 3).  Link passes under door frames, archways,
  canopies and arches drawn on BG1 or by archway objects, and over BG1 on
  a raised floor or stairs.
- Doors: ACT_TILE_40 with an area transition ahead lines Link up and
  walks him in for 5 frames (PLAYER_ROOM_EXIT); ACT_TILE_41 thresholds
  are walked through to the room edge (under the archway); arriving on
  one, Link walks out.
- Pullable mushrooms show frame 0 while idle (a fresh entity's frame);
  outside dungeons they use palette 0.  Graves, stone tablets, floating
  blocks, lightable switches and tree thorns show the frame their Init
  sets.
- A lily pad takes Link within 24 px of its centre (so from the bank) and
  carries him over the rim in whole pixels; the current (ACT_TILE_17 =
  $11) takes it down the outflow; Link and the pad land on layer 1
  (ResetCollisionLayer).
- Pots in the Gust Jar's gust wiggle, fly to the mouth, are caught, and
  break when let go or shot.
- Port features (not the cartridge): the zoom (wheel, R3 / L3, L3+R3;
  rooms around drawn from the ROM, tileset-manager rooms stitched per
  240x160 window) and seamless room changes / crossfades, with the
  "CARTRIDGE TRANSITIONS" option for the original fades.

### Round 13: object palettes, the Gust Jar, the barrel's bottom

- OBJ palette 5 is BG palette 3 of the current room (LoadRoomTileSet's
  copy); object palette $15 is BG 3's 12th colour; BG palette 2's first
  five colours come from OBJ palette 2 after each tileset palette group
  (sub_080533CC).  Statues and the other palette-5 objects draw in colour.
- The Gust Jar follows itemGustJar.c / playerItemGust*.c: pull-out, the
  charge (SMALL, MID after $77 frames, BIG after $EF), four gust boxes
  running out from the jar's mouth, the grab through the collision matrix
  (tolerance, pull, catch), the blow with the caught enemy or a puff of air
  for the charge, Link pushed back while blowing.  Webs, the barrel's web
  and lily pads react only to a gust box touching them.
- Pits inside a HOLE_MANAGER's box lead to the room below
  (gHoleTransitions); the barrel's web is sucked off from the inside
  (barrelSpiderweb.c) and its open bottom drops Link into B1.
- Type $80 doors shut again once their flag clears; lily pads use their
  own collision layer and can be sucked across a pool from the bank.

### Round 12: Deepwood's enemies and the first floor's west wing

- Puffstool (puffstool.c): the wander (sub_080256B4 / sub_08025C60, moving
  only on keyframes without flag bit 0, bouncing off walls after 30
  frames), the spot search (gUnk_080CC020) and the double hop that
  withers the grass and puffs brown smoke, the Gust Jar draining 3 spores
  a frame until it is bare (hitType $83, palette $7C, $294 frames,
  blinking at the end); spored it shrugs the sword off (SFX_186), bare one
  sword hit kills it and its contact only pushes Link (handler 16).
- Sluggula (sluggula.c): hanging at z 128 until full-size Link comes
  within $20, the drop (SFX_12D, gravity 24/256, SFX_WATER_SPLASH), the
  landing frames, becoming a type 1 that crawls, leaves slime every 28
  frames and turns toward Link (sub_08023E9C).
- Mulldozer (mulldozer.c): stand / walk / wind-up / charge at $1E0 with
  the 45-degree weave, the slow turn toward Link after a hit, the spin off
  a shield block, the dust puffs.
- Ledges: walking into gUnk_0811C1E8's act tiles for 6 frames jumps
  (PlayerJump: zVelocity from the ledge's depth, kJumpSpeedForward, the
  landing animation, ResetCollisionLayer).
- Pushing waits for ANIM_PUSH's keyframe with flag bit 0 (blocks, statues,
  pots); pulling (the lever, statues) waits for ANIM_PULL's flag bit 1
  (pullableLever.c reads frame & 2).  Pots push a tile at $80 for 32
  frames; Link leans on a pot's whole tile (SPECIAL_TILE_0).
- Statues can be grabbed with R and pulled a tile; they use the area's
  fixed gfx (gUnk_08120CCC), and ResolveCollisionLayer puts room objects
  with no layer of their own on the raised floor when its top tile is
  there.

## Not cartridge art yet

- File select:
  - the Link preview and the sword icon in the preview window (object
    types 23 / 24) and the staff-roll mark (25) are not drawn;
  - the R options screen and the language row are not ported.
- Title: the attract demo is not ported (the title stays up).
- Kinstone window: the KINSTONE_SPARK object's frames (the timing and
  sound are kept).
- The cartridge's message window has no name tags, so there are none to
  port.

## What differs (honest list)

- Round 21:
  - Peahat: the PeahatPropeller child of the sliced branch is a puff, not
    the flying propeller; sub_0800442E (holes / water) is still not run.
  - Spiny Beetle: the line-of-sight test between it and Link reads the tile
    collision (any non-zero value blocks) instead of sub_0804A4BC's quarter
    masks; a bush beetle's bush is not cut by the sword (Mt. Crenel's are
    rocks); the rock's flip-off by a blast is detected by the smoke's
    distance, not the blast's hurtType $0F contact.
  - Rollobite: tested on fake data only; thrown it uses the port's carry arc
    (2.5 px a frame), not PlayerItemHeldObject's.
  - Climbing: a climb step does not run UpdatePlayerCollision against
    non-climbable walls (Link only leaves climb surfaces onto open floor in
    the rooms tried).
  - Not reached: Melari's Mines, the Cave of Flames dungeon (Cane, carts,
    gleerok.c), the Fire Element, the White Sword; Gentari's frame, the
    particle types and the $09:00 door are unchanged.
- Round 20:
  - (fixed) The way onto Mt. Crenel's upper-west plateau: the base's two
    WHIRLWIND objects were never spawned and PLAYER_PARACHUTE was missing
    (Whirlwind.lua now); the round-19 flood fill did not model them nor
    Minish Link's way through the dust piles' gaps.
  - Whirlwind.lua: the cap's type-1 child (its strings) is not drawn; the
    camera follows Link, not the cap; sub-states 6 / 7 (type2 1, the Cloud
    Tops' room change) are not ported.
  - Peahat (peahat.c) runs its own code; the sliced-propeller branch (contact
    $14) and its PeahatPropeller child are not ported; sub_0800442E (holes /
    water under it) is not run; ProcessMovement2 is ProcessMovement0.
  - Bombs can be lifted and thrown; the throw uses the port's pot arc (speed
    2.5, z 14, zVelocity 0.5, gravity 0.25) instead of the carry system's
    ThrowObject; remote bombs are not ported.
  - Still on older models: Spiny Beetle (OBJECT_ON_BEETLE not ported),
    Rollobite, Spiked Beetle, Keese, Helmasaur.
  - LADDER_UP's way out keeps the round-18 rule (traced: UpdateDoorTransition
    fires on act $3F / $F1 / $28 / $29 but only finds area / type-3 exits;
    $26:0C's way up is a border exit, i.e. the border rule's $FF probe).
  - The dust spikes' OAM priority (removableDust.c type 0 keeps its
    entity-data layer) was not traced further; Gentari's side frame, the
    particle types and the $09:00 door script are unchanged.

- Round 19:
  - The way onto Mt. Crenel's upper-west plateau (the Minish rock, the hole
    to $12:00) was not found: from the base, the stone-portal plateau and
    the cave pocket by $26:0A the tufts (type 112, collision $0F), cliffs and
    one-way ledges close it off, even with every dust pile sucked and every
    bomb tile opened (r19/p_world19.lua, a flood fill over $06:00-$04, the
    $26 caves and $35:00).  The rock / bean chain is proven from a placement.
  - REMOVABLE_DUST's DIRT_PARTICLE is drawn as FX_DEATH; the spikes draw
    (frameIndex = type) but the rock's BG1 tiles cover them (their OAM
    priority on the cartridge was not traced).
  - Tektite_OnCollision's hurt-type $14 reset and $E / $15 instant kill are
    not ported; Spiny Beetle (its OBJECT_ON_BEETLE rock), Rollobite, Spiked
    Beetle, Peahat, Keese and Helmasaur keep the round-12 models.
  - LADDER_UP's way out is still the round-18 simplification (the cave's
    top row is collision $0F, not $FF, so the border rule does not fire;
    PlayerClimb's top was not traced).
- Round 18:
  - LADDER_UP's way out: the port's maps give the cave wall above the
    ladder act $2A, so Link stops a pixel short of the exit's 12 x 12 rect;
    the port starts the exit above the ladder (or the room's north border)
    once Link is on the ladder at its top and pushing up.
  - Bombs cannot be lifted or thrown (RegisterCarryEntity is not ported);
    remote bombs and the blast's knockback of objects are not ported; the
    archway a bombed wall gets in areas with enemies is spawned but its
    drawing was not checked; the blast's smoke uses its object definition.
  - (fixed in round 19) Room-placed rupees respawned after a reload (their
    taken key held a table address).
  - (partly fixed in round 19) Mt. Crenel's enemies used the shared model;
    Tektites, falling boulders and small Pestos now run their own code.

- Round 17:
  - Big Green ChuChu: the hitbox helper is not a separate entity (its rules
    run in BossChuchu:touchLink); CHUCHU_BOSS_START_PARTICLE types 1 / 3 /
    5-10 (the ripple under the boss, the swell's bubbles, the head's
    lying sparkle) are not drawn.
  - The element get's white flash fades the whole picture (the cartridge
    fades the palettes in gFadeControl.mask).
  - Wall Master: (round 19) in Deepwood Shrine and the Cave of Flames its
    grab uses gWallMasterScreenTransitions (entrance room $0B at ($A8, $B8) /
    main cart room $04 at ($98, $A8)); elsewhere it still sends Link to the
    room he came in by (field.entry); TORCH_TRAP never draws
    on the cartridge either, but its TORCH_TRAP_PROJECTILE is not ported.
  - The scripted HOUSE_DOOR_EXT in $09:00 draws (frame 0) but its script's
    opening was not checked.
  - Not started: the Minish Paths' blended background, light rays, cloud /
    steam overlays, rain, backgrounds behind neighbour rooms.  Mt. Crenel
    past the entrance's first vines is only covered by the old teleport bot.

- Round 16:
  - Big Green ChuChu: the goo drops of its intro are plain dots, the
    hitbox proxy (type 8) is folded into the head, the Gust Jar's blow does
    not knock it back; Link's contact damage uses the matrix with a box
    check per part (not the cartridge's per-part hitboxes).
  - The Earth Element: ELEMENTS_BACKGROUND and the white flash are not drawn.
  - Still blank (p_invis): blade / sensor blade / torch traps, wall masters,
    the Moldorm, aggressive cucco chicks (their enemy code is not ported),
    FAIRY $60, LADDER_HOLE, the PHONOGRAPH, REMOVABLE_DUST in $06:04, the
    scripted HOUSE_DOOR_EXT in $09:00; TREE_HIDING_PORTAL, MAZAAL_BOSS_OBJECT,
    OBJECT_BLOCKING_STAIRS and SPECIAL_FX type 2 are not drawn by their own
    code in those states on the cartridge either.
  - Not started: the Minish Paths' blended background, light rays, cloud /
    steam overlays, rain, backgrounds behind neighbour rooms, Mt. Crenel.

- Round 15:
  - Not ported BG effects: the Minish Paths' blended parallax BG1 / BG3,
    the rafters' background, light rays, cloud and steam overlays, the
    Temple of Droplets' and Vaati's backgrounds, rainfall.  Those rooms
    show their two map layers over the backdrop.
  - The beanstalk climb rooms ($0D:$07-$0C) point at tileset ids the area
    table does not have; on the cartridge they read past the table.  They
    draw with whatever the port loads (nothing for the missing ids).
  - A tileset-manager slot that never matched keeps the nearest region's
    group (the cartridge would show the default tiles); the zoomed-out
    neighbour copy of Hyrule Town does not build the red house.
  - BG3 is drawn only over the room (and the screen around a smaller
    room), not under the rooms around it; a neighbour's BG3 does not scroll.
  - Rooms' own collision merge for house-type areas (sub_0807C5B0: BG1
    collision into BG2) is not ported.
- Round 14:
  - Seamless room changes are a port feature: the room switches under
    Link (he then walks to the cartridge's landing spot; the room's
    enemies already run, the cartridge holds them during its scroll)
    instead of the cartridge's scroll; other warps crossfade.
    "CARTRIDGE TRANSITIONS" restores the fades (not the cartridge's
    full-screen scroll animation, which the port never had).
  - Zoomed out, neighbour rooms show their BG layers only (no entities, no
    BG animation); rooms with a tileset manager are stitched per 240x160
    window, which approximates the camera-region swap.
  - (round 15) HOUSE_DOOR_EXT and the decorative objects listed here in
    round 14 are drawn now; scripted house doors (type2 3 / a script in the
    record) are drawn and opened like plain ones, their scripts do not run.
  - The mushroom is still not knocked about by the sword (sub_0808ACEC's
    hit cases) or pulled by the Gust Jar (contact $13).

- Round 13:
  - Big Green ChuChu is still the round-3 simplification (chuchuBoss.c not
    ported).
  - The jar's own sprite, its wind particles and the grass pieces it tears
    out are not drawn; Link's drop-in after a hole is a plain arrival.
  - Link cannot yet step from a bank onto a lily pad in B1 (the pool rim is
    solid to the port's collision).
- Round 12:
  - Big Green ChuChu is still the round-3 simplification; chuchuBoss.c is
    not ported (see PROGRESS-minishcap.md, Round 12).
  - Pesto and the ChuChu (type 0) keep the earlier models; (round 13: the
    Gust Jar is the decomp's, not the cone).
  - (Round 13: statues are no longer black: OBJ palette 5 = BG palette 3.)
  - The barrel's fuse flames, the mushroom's stem, the ceremony objects'
    motion and the white flash are still as round 11 left them.
  - Puffstool dirt particles and FX_STARS are drawn as plain SPECIAL_FX;
    enemy movement slides per axis (not ProcessMovement0's wall slide).
- Round 11:
  - Big Green ChuChu is still the round-3 simplification: chuchuBoss.c
    (four affine parts, twelve sub-actions, three phases) is not ported.
  - (Round 12: pushes wait for ANIM_PUSH's frame flag, the lever for
    ANIM_PULL's.)  Link does not play PLAYER_PUSH while a block slides.
  - The mushroom's cap and stem are drawn from its sprite frames with
    the decomp's scales (not an OAM affine matrix); the ledge tiles a
    fling may pass over ($1AC-$1AF) are not checked.
  - The barrel room's fuse flames (FLAME objects) are not drawn; their
    timings are kept.
  - (Round 12: Puffstools, Sluggulas and Mulldozers are ported; the route
    goes on to room $04's key.)
- Round 10:
  - (Round 11: the look table, DoJump's sub-states, the interaction
    test and the hitboxes are ported.  Minish Link's sword has no hitbox
    on the cartridge either, so clearing the corridor's ChuChus at full
    size is what a player does.)
  - The barrel Minish's Picolyte (DRUG_*) lists and Picolytes are not
    ported; the Jabber Nut list is.
  - The sword ceremony's cutscene objects still do not move on their own
    (the monsters, the flying sword, Zelda's magic); the white flash is a
    plain fill.
  - Gleerok: round 25 ported gleerok.c (BossGleerok2.lua); see round 25
    for what is still simplified.  The Cave of Flames' per-room code is
    not ported.
  - (Round 11: the fall is PlayerFall, see above.)
- Round 8, Gleerok (`BossGleerok.lua`): the parts, art, fireballs, the
  plug knocked out by the Cane, the core hit by the sword, the lava
  blending away and the Fire Element / heart container follow the
  cartridge's pieces, but the neck's motion (a sway, not gleerok.c's angle
  chain), the phase timings and the hit count (4 + 4) are ours. Link
  standing on the neck is a position test, not field_0x14.
- Round 8, the Crenel bean carry: Link carries it with his walk animation,
  not the cartridge's held-object animation set. The swing's water probe
  uses frame offsets; the catch shows the item get, not
  sub_0801B9F0's own sequence. Lava (ACT_TILE_90) takes Link back to his
  last safe spot like a hole (PLAYER_LAVA's burn hop is not drawn).
- LV2_CLEAR is set when the Fire Element is taken.

Round 7:
- Multi-part NPCs (townspeople, kids, guards, shopkeepers...) are drawn
  from their parts as the cartridge does (NpcParts.lua); the `_Head`
  functions are ported by NPC id. Furniture, archways, masks, minish
  entrances and similar objects use their init code's fixed frame
  (ObjStatic.lua). The fusion bubble over a fuser is the cartridge's
  CAMERA_TARGET with its own tiles (FuseBubble.lua). Business Scrubs do
  not offer fusions (businessScrub.c is not ported).
- Mine carts follow minecart.c (Minecart.lua). The Cane of Pacci's swing
  and bolt follow the decomp; the spring out of a charged hole is
  simplified (see PROGRESS round 7) and pot flipping is not ported.
- Gleerok, the Fire Element after him, Melari's mine, the Grip Ring, the
  bean and the Mole Mitts are still not ported.

Round 6:
- Native NPC fusers are ported (Fusers.lua); the fusion bubble over a
  fuser's head (CAMERA_TARGET) is not drawn, enemy fusers (Business
  Scrubs) never offer, and townspeople (NPC 6) are still invisible (their
  LoadExtraSpriteData body parts are not drawn), so their fusions work
  but you cannot see who you fuse with.
- Windcrests are set by touching them; the Ocarina of Wind warp (bird,
  fast-travel menu) is not ported.
- The large lily pad follows lilypadLarge.c except the jar's suction
  from the bank and the ripples; currents are in but Deepwood has none.
- The rolling barrel follows rollingBarrelManager.c except the fall
  through its open bottom and the BLDCNT blend; the webs outside are
  drawn but their burning is not ported.
- The Zelda follower does not hide while Link falls or warps.
- Mt. Crenel: its five rooms, room code for rooms 0 / 2 / 4 and the
  windcrest. Not ported: Melari's mine, the Grip Ring, the bean and
  Mineral Water, the Mole Mitts. Cave of Flames: its 18 rooms load with
  their enemies and objects, but mine carts, the Cane of Pacci, Gleerok,
  the heart container and the Fire Element are not ported.
- (Round 16: the Big Green ChuChu is chuchuBoss.c.) Pesto is still simplified.

Round 5:
- Madderpillar is the cartridge's (madderpillar.c, round 5).
- Big Green ChuChu is still the round-3 simplification: 60 frames of Gust
  Jar topple it, then it is hittable for 150 frames.
- (Round 6: native NPC fusers are ported.)
- GBA sleep mode (pause screen 9) is shown as its white fade only.
- (Round 6: windcrest activations are set by touching the crest.)

Round 3:
- (Round 6: the lily pad and the barrel follow the cartridge.)
- Pesto keeps the shared enemy model.
- (Round 6: the Zelda follower is ported; SetPlayerMacro in round 5.)
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

- Round 16: `python tools/run_lua_check.py tests/zelda_tmc_r16_test.lua`
  (fake data); scratch `r16/run.sh route16.lua` (MAXFRAMES=250000: title ->
  Deepwood finished -> the Elder, real key events), segments from
  checkpoints `r16/p_*.lua`

- Round 15 room-art audit (scratch, needs the player's ROM): `r15/hx.sh
  a_rooms` (every room vs the ROM reference `r15/ref15.lua`), `r15/run.sh
  p_audit.lua` (real runtime, every 240x160 window), `r15/run.sh
  p_invis.lua` (objects that draw nothing); `tests/zelda_tmc_r15_test.lua`
- `python tools/run_lua_check.py tests/zelda_tmc_core_test.lua`
- `python tools/run_lua_check.py tests/zelda_tmc_online_test.lua`
- `python tools/run_lua_check.py tests/zelda_tmc_round2_test.lua`,
  `tests/zelda_tmc_round3_test.lua` (fake field, no ROM) and
  `tests/zelda_tmc_round4_test.lua` (Ppu / Ui on fake data)
- Round 5 tests: `tests/zelda_tmc_r5_maps_test.lua`, `r5_title`,
  `r5_kinstone`, `r5_fx`, `r5_boss` (fake data, no ROM)
- Round 5 shots: scratch modes `r5_maps`, `r5_title` (+
  `TMC_TITLE_SAVE=1 TMC_TITLE_EXTRA=r5_fsflow`), `r5_kinstone`, `r5_save`,
  `r5_fx`, `r5_boss`, with `TMC_OUT=.../r5/<topic>/shots`
- Menu shots: scratch harness modes `menu4`, `msg4`, `gameover`, `ppu`
- Deepwood bot: scratch harness mode `route` (`TMC_MODE=route`), log in
  `route_log.txt`, shots `route_*.png`
- Round 25: `python tools/run_lua_check.py tests/zelda_tmc_r25_test.lua`
  (fake data: platforms' support and rails, the pillar block's push / its
  flag spot, the portal stone, the Rupee Like / red ChuChu states,
  Gleerok's joint helpers and tables); real-runtime segments and scenes in
  `r25/` of the scratch folder (`CK=<checkpoint> SEG=r25/<seg>.lua bash
  r25/run.sh p_seg.lua`), the Crenel bot with the real Gleerok in
  `r25/r25check.sh`
- Round 22: `python tools/run_lua_check.py tests/zelda_tmc_r22_test.lua`
  (fake data: the item get, PUSHABLE_ROCK, LIGHTABLE_SWITCH, collision types
  1 / 10, the mushroom's ledge pass, the bottled fairy, Bob-omb, the Spiny
  Beetle's line of sight); the real-runtime route `r22/route22.lua` and the
  segment chain `r22/chain.sh` in the scratch folder
- Round 21: `python tools/run_lua_check.py tests/zelda_tmc_r21_test.lua`
  (fake data: Peahat OnCollision, Spiny Beetle, Rollobite); the real-runtime
  route `r21/route21.lua` in the scratch folder
  (`MAXFRAMES=420000 RUNID=.. r21/run.sh route21.lua`: title -> Mt. Crenel's
  summit $06:00 via the Grip Ring and the Crenel Wall, real key events)
- Round 20: `python tools/run_lua_check.py tests/zelda_tmc_r20_test.lua`
  (fake data: whirlwind, parachute, cliff-top glide, Peahat, bomb carry, the
  carried bean vs a hit); the real-runtime route `r20/route20.lua` in the
  scratch folder (`MAXFRAMES=400000 RUNID=.. r20/run.sh route20.lua`: title
  -> the Cave of Flames entrance room $06:02, real key events)
- Round 11: `python tools/run_lua_check.py tests/zelda_tmc_r11_test.lua`
- Round 13: `python tools/run_lua_check.py tests/zelda_tmc_r13_test.lua`
  (fake data); the real-runtime route `r13/s13_route.lua` in the scratch
  folder (title -> Deepwood B1, real key events)
- Round 12: `python tools/run_lua_check.py tests/zelda_tmc_r12_test.lua`
  (fake data); the real-runtime route `r11/s11_route.lua` in the scratch
  folder (title -> Deepwood room $06, real key events)
- `python tools/run_lua_check.py tests/zelda_tmc_rom_test.lua` (needs the ROM
  in the repo root or `TMC_ROM`; imports into `TMC_TEST_CACHE`, skips cleanly
  without them)
- Scratch harness (outside the repo): `G:/Gen2Recomped/scratch_claude/zelda/tmc/`
  (`harness/` LÖVE modes rooms / sprites / play, `twoproc/`, `tools/`).

## Round 26 (team A): items, overworld enemies

- Every remaining button item now works in the field: Boomerang / Magic
  Boomerang, Bow / Light Arrows, Roc's Cape, Pegasus Boots, Mole Mitts,
  Lantern, Ocarina of Wind (with Zeffa and the fast-travel map), and the
  Flippers (swimming, diving).  The sword has its charge, the spin and the
  Tiger Scroll techniques except the Dash Attack's own scroll check (done in
  the Boots) and the Four Sword clones.
- Parity notes: ported from itemX.c / playerItemX.c / player.c / bird.c /
  subtaskFastTravel.c; the fast-travel warp table (gUnk_08128024) is code
  from the decomp's C source.  Simplified: the Cape's air control (asm
  ice-velocity table) is a plain walk; the hand-held item parts always draw
  over Link; the first-warp Ezlo talk is not run.  Details per module in
  their header comments and in PROGRESS (Round 26 team A).
- The overworld enemies run their own decomp ports (`EnemyField1/2.lua`);
  Beetle (one form), Moldworm, Like Like, Bomb Peahat and Dust still use the
  generic model outside dungeons.

## Round 26 (team B): dungeons, dungeon enemies, bosses

New modules, all reached through `R26.lua` (one hook line each in
Enemies:spawn, Enemies:update, Dungeon:spawnObject / spawnProjectile /
spawnManager and Field:spawnRoomEntities):

| File | What it is |
|---|---|
| `R26.lua` | the round-26 dispatcher: modules export spawnEnemy / handles+update / spawnObject / spawnManager / spawnProjectile / roomInit / ROM_RANGES; `R26.ticker` = a hidden per-frame manager |
| `ExtractR26.lua` | manifest.r26b: raw bytes of every module's ROM_RANGES (cache 19); `tables(f, name)` readers, nil on an old cache |
| `EnemyFoW.lua` | Wizzrobes (wind/fire/ice + shots), Eyegore, Armos, Stalfos (+bone, pot/skull heads), Flying Skull, Spark |
| `FoWObjects.lua` | eye switches, floating platforms, Minish-sized entrance, stone tablet, birds + the Ocarina drop, misc manager 1-3, enemy interaction manager, Winder, spiked rollers |
| `BossMazaal.lua` / `2` / `3` | Mazaal: boss object, head, bracelets + hands, beams, the inside (pillars), the Vaati projectile |
| `EnemyToD.lua` | Pesto (+dirt balls), Scissors Beetle (+mandibles, dungeon areas only), Flying Pot, the Big Blue ChuChu (chuchuBoss type 4 via BossChuchu) |
| `ToDObjects.lua` | ice blocks, frozen flower / water element, light rays, light door, lit areas, dark rooms + Link's light, levers, ToD / light / waterfall / misc managers, the ice floor |
| `BossOctorok.lua` | Big Octorok (octorokBoss.c + its projectiles and objects) |
| `EnemyPoW.lua` | Bombarossa, Crow, Lakitu + cloud, Ball and Chain Soldier, Gibdo, yellow ChuChu |
| `PoWObjects.lua` | fans, cloud floors, palace archway, floating blocks / platforms, floating platform manager, cloud staircases |
| `BossGyorg.lua` | the Gyorg Pair (boss object, female + eyes + mouth + tail, males + eyes, children, shots) |
| `EnemyDHC.lua` | Darknut (+slash), Wisp, Door Mimic, ENEMY_50 |
| `DHCObjects.lua` | guruguru bars, jail bars, metal door, the throne, angry statues + cannonballs, tile puzzle, DHC / Sanctuary room code |
| `BossVaati.lua` / `BossVaati2.lua` | Vaati Reborn; Vaati Transfigured + the eyes macro inside the arm |
| `BossVaati3.lua` / `BossVaati3Arm.lua` / `BossVaati3Extra.lua` | Vaati's Wrath, its arms and eyes, ENEMY_4D, the Vaati 3 managers, the start of the ending |

Every module's header lists what it ports and what is SIMPLIFIED.  Other
shared-file lines from this work: `Enemies.lua` Enemies:hit `e.r26hit`
(per-enemy hit handlers, EnemyDHC), `Dungeon.lua` Dungeon:somethingOn
clone hook (DHCObjects), `Bg3.lua` B.offsets `b.offsetsFn` (Gyorg's sky);
the rest are runtime wraps installed by the modules (Dungeon.checkFall /
somethingOn, PushableRock.tryPush, PushAnim.update, Player.walk for the ice,
Field.drawWorld for the darkness).

What differs: affine / BG3 effects (steam, light shafts, Vaati backdrops)
are not drawn or are approximated; Link's frozen / burning states are not
ported; arrows and bombs do not yet reach boss parts and eye switches (team
A's Bow must call the modules' hit hooks); the Vaati intro scripts and the
ending after the fight do not run.  Status per dungeon: PROGRESS (Round 26
team B).

## Round 27 (team A)

| File | What it is |
|---|---|
| `R27A.lua` | team A's round-27 dispatcher (enemies, objects, managers, projectiles, roomInit, giveItem, frame, draw, natives) |
| `ExtractR27A.lua` | manifest.r27a: the R27A modules' ROM_RANGES (cache 20) |
| `Story27Town.lua` | Hyrule Town / castle NPC natives (townsperson, guards, Pina, Sturgeon, librarians, house doors, kid follow, phonograph...) |
| `Story27Town2.lua` / `Town2Fairy.lua` | blade brothers (LearnSkill, demonstrations), Gorman, Stockwell, Simon, chest game, Dampe, ghost brothers, Great Fairy |
| `SideQuests27.lua` / `SQ27Cucco.lua` | Rem, Postman, Anju's cucco game + carrying cuccos, Mutoh, Smith, Talon, Malon, bell heart piece, bottle drinks/charms |

EnemyPoW handles Crow / Lakitu only in the Palace of Winds ($70/$71); the
overworld ones run EnemyField1/2.  Script coverage (scan in
`scratch_claude/zelda/tmc/r27a/cover.sh`): 450 of 576 cartridge scripts have
every native they call ported (327 of 470 natives).

## Round 27 (team B)

`R27B.lua` (listed in R26.MODULES) forwards the R26 hook set plus `frame`, `draw` and
`playerFrame` to the round-27 team B modules.  `VaatiScripts.lua` gives the DHC script
NPCs/objects their bodies (Vaati $27, Vaati Reborn $3B, Vaati1 portal $AB, Zelda's
stone, the spiral beam) and registers the DHC natives, so the Vaati 1 / 2 fights and the
Zelda-stone sequence start from the cartridge scripts.  `SanctuaryScripts.lua` does the
Sanctuary sword-charge sequences.  Ending/credits, dungeon leftovers and cave objects
are still to do (see PROGRESS, Round 27 team B).  Cache version 21.
