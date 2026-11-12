-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHERE THINGS ARE in "The Legend of Zelda: A Link to the Past & Four Swords"
-- (USA, AZLE01, 8 MiB). This is a map of the cartridge, not its contents: every
-- entry is an OFFSET (or a count), and every table it points at is read from
-- the player's own ROM at import time. No cartridge bytes live in this file.
--
-- How each offset was found (no GBA decomp exists; all of this was reverse-
-- engineered from the ROM, cross-checked against snesrev/zelda3's SNES logic):
--
--   gfxSheets      a 235-entry pointer table to BIOS-LZ77 4bpp sheets of 64
--                  tiles; the SNES "graphics packs", re-encoded 4bpp on GBA.
--   mainTilesets   kMainTilesets[37][8]: the SNES table, byte for byte, found by
--                  value; auxTilesets / spriteTilesets follow it with 0xFF in
--                  place of the SNES 0 ("keep the main set's sheet").
--   owBgMap/owBg1  2 x 160 pointers to LZ77 64x64 tilemaps (four 32x32 GBA
--                  screenblocks): the GBA keeps each 512x512 overworld screen
--                  PRE-RENDERED as map8 words instead of SNES map32/map16.
--   owParent       the "which screen owns this one" table (large areas are
--                  2x2 screens); found right before owBgMap.
--   palBlob        4096 BGR555 colours the game copies to EWRAM 0x02030000 at
--                  boot (function at 0x08130D9C) and indexes with the
--                  palIndex* tables below (loaders at 0x081305E0 OWBGMain,
--                  0x0813068C/0x0813076C OWBG1/OWBG2, 0x0813084C
--                  Overworld_LoadPalettes).
--   owBgPalInfo    kOwBgPalInfo, stride 4 (SNES stride 3 + 0xFF pad).
--   owBgPalettes*  the per-screen BG palette set; the game copies one of three
--                  64-byte Light World tables by story phase, plus the Dark
--                  World one, into RAM 0x02002DC0 (function at 0x0807499C).
--   tileAttr       kMap8DataToTileAttr: 512 bytes, read by the GBA's
--                  Overworld_GetTileAttributeAtLocation (0x080691xx) as
--                  attr[word & 0x1FF], hflip (bit 10) ORed in for 0x10..0x1B.
--   linkGfx        Link's 4bpp sheet in the SNES layout (16 tiles a row, a
--                  16x16 cell = 2 tiles + 2 tiles 0x200 further on), the DMA
--                  base used by the OAM upload at 0x080A6DD0.
--   linkDma*/linkOam*  kLinkDmaSources1/2, kLinkDmaGraphicsIndices,
--                  kLinkSpriteBodys, kPlayerOamOtherOffs: the SNES tables,
--                  found by value in the GBA ROM.
--   speedMod/animTab*  kSpeedMod[27] and the walk-cycle timing tables of
--                  Link_HandleMovingAnimation_StartWithDash.
--   songTable      the M4A (MusicPlayer2000) song table, 545 entries; found by
--                  a structural scan (see Extract.findSongTable) and checked.

local M = {}

M.GAME_CODE = "AZLE"
M.GAME_TITLE = "GBAZELDA"
M.SHA1 = "a272055abbbf6c26b0cd54c87395d01699589161"
M.SIZE = 8 * 1024 * 1024

M.gfxSheets      = 0x22B150   -- u32 pointers
M.gfxSheetCount  = 235
-- r15: animated BG tiles (water, lava, ...). Overworld: 0x0812FD88(sheet)
-- loads sheet (0x58 Death Mountain 3/5/7, else 0x5A) 64 tiles + sheet+1 32
-- tiles to EWRAM 0x02009A00 = 3 frames of 32 tiles; dungeons: 0x0812FCDC(a)
-- interleaves 16 tiles of sheet a and 16 of 0x5C per frame. Each VBlank
-- (0x080A7048) copies frame [+0xCD2] (0, 0x400, 0x800; 0x0812D1A0 steps it
-- every 9 frames) to VRAM +[0xA3A]: 0x3800 (tile 0x1C0) outdoors, 0x3600
-- (tile 0x1B0) indoors. Sheet a = this table [main tileset].
M.dungAnimTiles  = 0x14CE1C   -- u8 [mainTilesetCount]
M.mainTilesets   = 0x22B4FC   -- [37][8] bytes
M.mainTilesetCount = 37
M.spriteTilesets = 0x22B624   -- [144][4] bytes
M.spriteTilesetCount = 144
M.auxTilesets    = 0x22B864   -- [82][4] bytes, 0xFF = keep main
M.auxTilesetCount = 82

M.palBlob        = 0x3BD758   -- 4096 u16 colours
M.palBlobColors  = 4096
M.palIndexMain   = 0x22BC38   -- u16 per overworld_palette_mode, + 0xD00
M.palIndexAux12  = 0x22BC44   -- u16 per aux1/aux2 set, + 0xE00
M.palIndexAux3   = 0x22BB64   -- u16 per aux3 set, + 0xC00
M.palIndexSprAux = 0x22BBB4   -- u16 per sprite aux set (blob 0x200 + n)
M.owBgPalInfo    = 0x22BD1C   -- [31][4] (aux1, aux2, aux3, pad); 0xFF = keep
M.owBgPalInfoCount = 31
M.owSprPalInfo   = 0x22BD98   -- [20][2]
M.backdropLW     = 0x130A54   -- literal-pool words holding the backdrop
M.backdropDW     = 0x130AA4   -- colours (grass green / dark world /
M.backdropDM     = 0x130A68  -- death mountain), read from the code itself

M.owParent       = 0x14FC30   -- 160 bytes
M.owBgMap        = 0x14FCC0   -- 160 x u32 -> LZ77 8192-byte tilemap (BG2)
M.owBg1Map       = 0x14FF40   -- 160 x u32 -> LZ77 8192-byte tilemap (BG1)
M.owScreens      = 160
M.owAuxTileset   = 0x14C868   -- 128 bytes, per screen
M.owSprPalettes  = 0x14C8E8   -- 128 bytes, per screen: r15: the BG palette set (kOverworldBgPalettes; old misnomer kept for the cache)
M.owBgPalLW      = { 0x14D8A4, 0x14D8A4, 0x14D8E4, 0x14D924 } -- phase 0..3; r15: SPRITE palette sets (RAM 0x02002DC0), misnamed
M.owBgPalDW      = 0x14D964
M.owSprGfxLW     = { 0x14D7A4, 0x14D7A4, 0x14D7E4, 0x14D824 }
M.owSprGfxDW     = 0x14D864

M.tileAttr       = 0x15DF14   -- 512 bytes

M.linkGfx        = 0x22C82C   -- raw 4bpp, SNES layout
M.linkGfxBytes   = 0x8000
M.linkDmaSrc1    = 0x22AB3C   -- u16 [309] head cell (minus 0x8000)
M.linkDmaSrc2    = 0x22ADA6   -- u16 [309] body cell
M.linkDmaCount   = 309  -- GBA: 309 (SNES 303); tables are 0x26A apart
M.linkGfxIndices = 0x1697A0   -- u16 [511]
M.linkGfxIndexCount = 517   -- the GBA's 517-entry copy (SNES 511; bug round)
M.linkSpriteBodys= 0x169180   -- [309] { s8 y, s8 x, u8 tile }
M.playerOamOffs  = 0x16B118   -- u16 [160]
M.playerOamOffsCount = 160
-- Round 14: BG / OBJ priority (Layers.lua). The GBA keeps SNES-format OAM
-- flags and converts them in 0x080A452C: GBA OBJ priority =
-- oamPrioMap[SNES priority] & 3 (+1 while CGADSUB is 0xB3 and the palette
-- bit 4 is clear). Link's SNES priority is linkFloorPrio[link_is_on_lower_level]
-- (kPlayerOam_FloorOamPrio, read at 0x080A3F92 into RAM +0x1724), a
-- sprite's is spritePrios[floor] (kSpritePrios, 0x080C1F32).
M.layers = {
  oamPrioMap    = 0x16B38E,   -- u8 [5]
  linkFloorPrio = 0x16B326,   -- u16 [4], SNES 0x1000-0x3000
  spritePrios   = 0x171DBC,   -- u8 [4], SNES 0x10-0x30
}

M.speedMod       = 0x167DEA   -- u8 [27]
M.animTab2       = 0x167DB6   -- u8 [16]
M.animTab3       = 0x167DC6   -- u8 [24]

M.songTable      = 0x3C3BBC
M.songCount      = 545

-- INTERIORS (round 3). The room loader at 0x0807FF10 decompresses, for
-- dungeon_room_index (RAM 0x03002230+0xA1E), a pre-rendered 64x64 map8
-- tilemap from roomBg2 into 0x02018000 and one from roomBg1 into 0x0201C000
-- (rooms are 512x512; the third table holds an optional extra layer). Room
-- 0x97 swaps in other maps by a flag. The dungeon BG palette is 96 colours at
-- palette-blob colour 0x400 + dungPalIndex[palette_main_indoors] (loader
-- 0x0813041C, RAM +0xCAE), copied to colours 0x20-0x7F.
M.roomBg2        = 0x1618D8   -- u32 x roomCount -> LZ77 8192-byte map
M.roomBg3        = 0x161D98
M.roomBg1        = 0x162258
M.roomCount      = 304
M.dungPalIndex   = 0x22BC10   -- u16 per dungeon palette set
M.dungPalCount   = 48

-- Room header (round 4). 0x08080D00 is the SNES Dungeon_LoadHeader: it reads
-- 14 bytes at roomHeader[room] (headers overlap, as on the SNES):
--   +0 bg2 mode<<5 | collision<<2 | lights   +1 palette set
--   +2 aux tileset (RAM +0xC9A)               +3 spriteset (+0x40)
--   +4 bg move  +5,+6 tags  +7 stair planes  +8..+13 stair/hole targets
-- The palette set indexes 4-byte rows of roomPalSets; byte 0 is
-- palette_main_indoors (RAM +0xCAE, see dungPalIndex).
M.roomHeader     = 0x164020   -- u32 x roomCount -> 14 bytes
M.roomHeaderLen  = 14
M.roomPalSets    = 0x22BC6C   -- 4 bytes per set
M.roomPalSetCount = 44
-- Entrances (loader 0x08078AC8): 0x2C bytes each. +0 room (u16), +0x16 Link
-- Y, +0x18 Link X (world pixels), +0x1E main tileset (RAM +0xC99).
M.entrances      = 0x150EC4
M.entranceLen    = 0x2C
M.entranceCount  = 0x89
-- Overworld doors (round 4b), the GBA's Overworld_UseEntrance at 0x0808BB88:
-- the two bottom map8 tiles (& 0x1FF) of the 16x16 tile in front of Link must
-- be a pair from owDoorTab0/owDoorTab1 (44 u16 each), then the 131-entry
-- tables owEntArea (u16 area), owEntPos (u16) and owEntId (u8 entrance) are
-- searched from the end. owEntPos is the door's top-left map8 cell as a
-- halfword index into the GBA's area map buffer 0x02018000: one 4096-cell
-- block per 512x512 screen of the area (TL, TR, BL, BR), each block four
-- 32x32 screenblocks.
-- Room doors (round 4b): roomDoors[room] -> u16 words until 0xFFFF, the
-- SNES door format (bits 0-1 direction 0 up/1 down/2 left/3 right, bits 4-7
-- position, high byte type); kDoorPositionToTilemapOffs_Up/_Down (12 u16
-- byte offsets into the 64x64 room map) found by value. A door whose type is
-- an entrance (4, 10, 12, 14, 16) or that shares its place with an
-- ExitToOw (18) marker gets tile attribute 0x8E (RoomDraw_..., SNES
-- dungeon.c), the overworld exit.
M.doorPosUp      = 0x167778
M.doorPosDown    = 0x167790
M.doorPosLeft    = 0x1677A8   -- round 5: _Left / _Right follow (12 u16 each)
M.doorPosRight   = 0x1677C0
-- round 11: kTileAttrsByDoor (40 u16, the attribute pair a door's doorway
-- gets, by door type / 2; the GBA's door attribute loader 0x08082ADC reads
-- it from here)
M.doorAttrsByType = 0x16784C
-- round 11: the door pictures (SNES kDoorTypeSrcData / 2 / 3 / 4 as GBA
-- pointers to 12 map words each, by door type / 2: north and south doors 4
-- columns of 3 words, west and east 3 columns of 4) and kDoorTypeRemap (u16
-- by type / 2: the type an opened door is drawn as)
M.doorTilesN     = 0x16798C   -- u32 x 52
M.doorTilesS     = 0x167A5C   -- u32 x 48
M.doorTilesW     = 0x167B1C   -- u32 x 48
M.doorTilesE     = 0x167BDC   -- u32 x 47
M.doorRemap      = 0x1677FC   -- u16 x 40
M.owDoorTab0     = 0x1537DE
M.owDoorTab1     = 0x153836
M.owDoorTabCount = 44
M.owEntArea      = 0x15388E
M.owEntPos       = 0x153994
M.owEntId        = 0x153A9A
M.owEntCount     = 131
-- Dungeon tile attributes, built like the SNES attributes_for_tile at
-- 0x02002E40 (loader 0x08092848 / 0x08092874): 0x140 common bytes, 0x80
-- bytes chosen by the aux tileset, 0x40 common bytes; indexed by tile & 0x1FF.
M.dungAttrBase   = 0x15E114
M.dungAttrAux    = 0x15E794   -- u32 x dungAttrAuxCount -> 0x80 bytes
M.dungAttrAuxCount = 23
M.dungAttrTail   = 0x15E254
-- Room object lists (SNES room data format) and door lists, interpreted by
-- 0x0807FD84 / 0x0807FE08; most object handlers are empty on the GBA because
-- the maps are pre-rendered. Not decoded yet.
M.roomObjects    = 0x162768
M.roomDoors      = 0x162C28
-- ROOM TO ROOM (round 5). Byte 1 of a room's object list is the SNES
-- dung_layout_and_starting_quadrant (layout = byte >> 2); with Link's
-- quadrant it indexes kLayoutQuadrantFlags (32 bytes, found by value): bit 0/1
-- CLEAR = the camera may cross to the other half horizontally (left/right
-- half), bit 2/3 clear = vertically (top/bottom half); the SNES then sets
-- quadrant_fullsize = 2. A half that may not be crossed is a quadrant of its
-- own: walking out of it is a transition. (The GBA keeps the layout byte at
-- RAM +0xAB4, Link's quadrant x/y at +0x9E3/+0x9E4, the composite at +0x9E2;
-- users 0x0806F344 and on.)
M.layoutQuadFlags = 0x14CDDC
-- The exit table (SNES kExitData*, read by the GBA port of
-- Overworld_LoadExitData; Overworld exit is searched from the end for the
-- room): exitCount u16 rooms, u8 screens, then u16 arrays of exitCount each
-- (aligned): Map16LoadSrcOff, ScrollY, ScrollX, Link Y, Link X, CameraY,
-- CameraX. Rooms 0x100-0x17F other than 0x104 do not use it: Link goes back
-- where he was when he came in, 16 px higher (SNES LoadCachedEntranceProperties).
M.exitRooms      = 0x1501C0
M.exitCount      = 79
M.exitScreens    = 0x15025E
M.exitArrays     = 0x1502AE   -- + k * exitCount * 2 for array k (0..6)
-- round 12: after the 7 u16 arrays come Unk1 / Unk3 (i16 each here) and the
-- SNES kExitData_NormalDoor / kExitData_FancyDoor (u16 x exitCount each):
-- a door's map16 spot (x << 1 | y << 7 in the area), 0x8000 = palace (the
-- castle's big doors; Link's house has a normal door 0x816). Found by value
-- (Link's house's 0x816 and the castle rooms 0x60-0x62's 0x81xx).
M.exitNormalDoor = 0x15083C
M.exitFancyDoor  = 0x1508DA
-- round 12: the starting points (SNES kStartingPoint_*, which_starting_point
-- 0..6: Link's house, sanctuary, the prison 0x80, the uncle's passage 0x55,
-- the throne room 0x51, the old man's cave 0xF0, his home 0xE4), 0x2C-byte
-- records in the entrance format (+0 room, +0x16 Y, +0x18 X, +0x1E main
-- tileset, +0x20 palace, +0x22 plane), found by value just before the
-- entrance table.
M.startPoints     = 0x150D24
M.startPointCount = 7

-- ROUND 6 (the castle escape), found by value/disassembly:
-- Room sprite lists (SNES kDungeonSprites): u32 per room -> { u8 sort, then
-- 3-byte entries y|floor<<7|sub, x|sub, type, to 0xFF }; type 0xE4 with
-- y 0xFE/0xFD gives the previous sprite a small/big key to drop; x >= 0xE0 is
-- an overlord (Dungeon_LoadSprites / Dungeon_LoadSingleSprite).
M.roomSprites    = 0x228DF0
-- Chest contents (SNES kDungeonRoomChests): 168 x { u16 room (0x8000 = big
-- chest), u8 item (the SNES receipt id: 0x24 small key, 0x32 big key, 0x33
-- map, 0x0C boomerang, 0x12 lamp ...) }, searched in order per room.
M.chests         = 0x1532FE
M.chestCount     = 168
-- Falling into a pit on the overworld (the GBA port of
-- Overworld_GetPitDestination, 0x0808B55C): area u16 list to 0xFFFF,
-- per area 8 u16 tile keys (0xFFF0 = any pit of the area), entrance bytes.
M.holeAreas      = 0x1537B8
M.holeKeys       = 0x1536F8
M.holeEntrances  = 0x1537D2
-- The map16 -> map8 table (4 words per map16, the SNES map16 definitions the
-- GBA keeps for tiles that change at run time: bush 0x36 -> 0xDC7 lifted,
-- secret hole 0xDCC).
M.map16          = 0x155B4E
M.map16Count     = 0xEA8
-- Overworld secrets (SNES kOverworldSecrets): u32 per area (129) -> 4-byte
-- entries { u16 pos, u8 type, u8 0 } to 0xFFFF; pos = (y / 16) * 128 +
-- (x / 16) * 2 inside the area; type 0x80 hole (map16 0xDCC), 0x82 0x212,
-- 0x86 0xDB4, below 0x80 an item (SNES Overworld_RevealSecret).
M.owSecrets      = 0x22C624
M.owSecretCount  = 129
-- Dungeon secrets (SNES kDungeonSecrets, pots and floors): u32 per room ->
-- 3-byte entries to 0xFFFF (reader 0x080928F0). Not used yet.
M.dungeonSecrets = 0x2264C8
-- Combat tables (the SNES tables, found by value; RAM-free): per sprite type
-- (243) health, bump damage, flags4 (hitbox index & 0x1F); per hitbox index
-- (32) x/y offset low/high and size; Link's damage from bump class
-- (kPlayerDamages, 3 armour levels); kEnemyDamages (8 per damage type); the
-- sword's hit boxes (kPlayer_SetupActionHitBox X/W/Y/H, 65 = facing * 8 +
-- swing step + 1; Tab4 = steps with no box) and the swing step delays
-- (kSpinAttackDelays).
M.combat = {
  health = 0x22769D, bump = 0x227796, flags4 = 0x227988, spriteTypes = 243,
  hitXLo = 0x171FF4, hitXHi = 0x172014, hitXSize = 0x172034,
  hitYLo = 0x172054, hitYHi = 0x172074, hitYSize = 0x172094,
  playerDamage = 0x171E70, enemyDamage = 0x17E924,
  swordX = 0x171EAB, swordW = 0x171EEC, swordY = 0x171F2D, swordH = 0x171F6E,
  swordTab4 = 0x171E9E, swordDelays = 0x16808C,
  -- r20: kSprite_Func14_Damage (12: the sword's damage class by sword
  -- level - 1, | 4 spin, | 8 held), kLinkSpinGraphicsByDir (48) and
  -- kLinkSpinDelays (12) of LinkState_SpinAttack, found by value
  swordClass = 0x171FE8, spinGfx = 0x168040, spinDelays = 0x16807C,
  -- r20: kGetBestActionToPerformOnTile_y / _x (int16 x 4 by facing >> 1):
  -- the tile ahead of Link (Overworld_GetLinkMap16Coords; the dash's bonk)
  actTileY = 0x168258, actTileX = 0x168260,
  -- player_oam_y/x_offset per Link pose (kSwordOamYOffs/XOffs, the GBA's
  -- 517-entry copies); index = playerOamOffs[facing / 2 * 40 + 39] + step
  -- (SNES CalculateSwordHitBox)
  swordOamY = 0x16AB08, swordOamX = 0x16AD0D, swordOamCount = 517,
  -- round 10: kSprite2_ReturnIfRecoiling_Masks (6 bytes; the only copy in
  -- the ROM, used by the GBA's Sprite_ReturnIfRecoiling)
  recoilMasks = 0x171DC0,
  -- round 10: the lifted / thrown object sprite 0xEC (Sprite_EC_ThrownItem):
  -- kThrowableScenery_Char (12, GBA chars; +6 indoors in the Dark World...)
  -- and kThrowableScenery_Flags (6), found by value
  throwChar = 0x1778B4, throwFlags = 0x1778C0,
  -- round 13: the guards' AI (zelda3 Guard_Main 0x85C227, found by value;
  -- the GBA keeps the SNES values): kSoldier_SetTowardsVel as x[4] / y[4],
  -- kSoldier_Xvel / _Yvel, kSoldier_Delay, kSprite_SpawnProbeStaggered_Tab,
  -- kSpawnProbe_Xvel / _Yvel (64 each); the sprite tile collision
  -- (Sprite_CheckTileProperty): kSprite_Func5_Tab3 (256, int8) and the probe
  -- points kSprite_Func5_X / _Y (54, int16 on the GBA)
  guardTowardsX = 0x176900, guardTowardsY = 0x176904,
  guardXvel = 0x176910, guardYvel = 0x176914, guardDelay = 0x1769C4,
  probeStagger = 0x1769D0, probeXvel = 0x1769D4, probeYvel = 0x176A14,
  sprTileSolid = 0x172270, sprPointX = 0x22A860, sprPointY = 0x22A8CC,
  -- kSprite_SimplifiedTileAttr (256; Probe_CheckTileSolidity)
  sprSimple = 0x172370,
  -- kSpriteInit_Flags5 (& 15 = prize pack), kSpriteInit_DeflBits (& 1:
  -- ignores the kill memory), kPrizeMasks (7)
  flags5 = 0x227B7A, deflBits = 0x227C73, prizeMasks = 0x17216F,
  -- round 14: Guard_ParrySwordAttacks (the GBA's 0x080C3A1C..): the guard's
  -- sprite_F (kSprite_Func1_Tab) and Link's incapacitated timer
  -- (kSprite_Func1_Tab2), 8 each, picked by the RNG
  parryF = 0x171E60, parryLink = 0x171E68,
  -- round 14: the green knife guard 0x4B (Sprite_4B_GreenKnifeGuard, the
  -- GBA's 0x080E4D..): kSprite_Recruit_Xvel / _Yvel (8 each, int8) and
  -- kRecruit_Moving_HeadDir (8)
  recruitXvel = 0x1773F4, recruitYvel = 0x1773FC, recruitHeadDir = 0x178400,
}

-- SPRITE GRAPHICS (round 7). The GBA's sprite sheets are a table of its own
-- (0x0822B324, LZ77, indexed by the SNES sprite-gfx number); the loaders at
-- 0x0812E7B0 / 0x0812E8DC fill OBJ VRAM (2D mapping, 32 tiles a row) as:
--   rows 0-3  cols 0-15   Link / follower (DMA'd each frame)
--   rows 4-7  cols 0-15   misc sheet (RAM +0xC9C; 10 indoors)
--   rows 0-3 / 4-7 cols 16-31  sheets 6 / 7
--   rows 8-11 / 12-15, cols 0-15 / 16-31  the spriteset's 4 sheets
--     (kSpriteTilesets[header byte 3 + 0x40], 0xFF keeps)
-- A sprite's OAM char is a GBA tile number in that layout; the SNES OAM
-- flags byte (vhoopppN) is kept, N (bit 0) adds 256 (rows 8-15).
-- Sprite palettes (OBJ rows 0-7 = the SNES sprite palettes 0-7), from the
-- loaders at 0x0813001C..0x08133290, all into the palette blob (0x3BD758):
--   row 0 cols 0-7   blob 0x100 + sprAux3[sp0l]          (0x08133048)
--   row 0 cols 8-15  blob 0x400 + dungPalIndex[main]      (0x0813041C)
--   rows 1-4         blob sprMain[world] (16 colours each) (0x08130030)
--   row 5 cols 0-7   blob 0x200 + sprAux1[sp5l]           (0x0813090A)
--   row 5 cols 8-11 / 12-15  blob 0x300 + sword/shield idx (0x081330EC / 0x08133148)
--   row 6 cols 0-7   blob 0x200 + sprAux1[sp6l]           (0x081300EC)
--   row 6 cols 8-15  blob 0x108 + sprMisc[sp6r] (10 indoors) (0x081331F4)
--   row 7            blob 0x0B0 + sprMisc[armour] (Link)   (0x081302F0)
-- Per-sprite draw tables (the SNES tables; the GBA widened x/y to s16 and
-- renumbered chars for its VRAM layout; DMD = {s16 x, s16 y, u16 char |
-- flags << 8, u8 0, u8 big}); found by value against snesrev/zelda3.
M.sprites = {
  sheets = 0x22B324, sheetCount = 118,
  flags3 = 0x22788F,                       -- kSpriteInit_Flags3 (243)
  singleTab1 = 0x2273B8, singleTab2 = 0x2272A8, singleTab2Len = 272,
  sprMain = 0x22BBB2, sprAux3 = 0x22BB84, sprAux1 = 0x22BBB4,
  sprMisc = 0x22BB64, swordPal = 0x22BBF4, shieldPal = 0x22BBFE,
  follower = 0x22BB1C,                     -- u16 per follower: sheet << 11 | byte offset
  followerSheetZelda = 0x64,               -- 0x0812F9A8: follower 1 base sheet
  -- Guard_HandleAllAnimation (head, body, weapon)
  d1char = 0x176958, d1flags = 0x17695C, d1yd = 0x176A58,
  d2oam = 0x176A8C, d2xd = 0x176A90, d2yd = 0x176B60, d2char = 0x176C30,
  d2flags = 0x176C98, d2big = 0x176D00,
  d3oam = 0x176D68, d3xd = 0x176D6C, d3yd = 0x176DA4, d3char = 0x176DDC, d3flags = 0x176DF8,
  gfx2 = 0x176918, headDirs = 0x176938,
  recruitX = 0x177404, recruitChar = 0x177414, recruitFlags = 0x17741C, recruitGfx = 0x1773EC,
  ratTab0 = 0x17CEF8, ratTab1 = 0x17CF08, ratTab2 = 0x17CF18, ratTab4 = 0x17CF20,
  ropeGfx = 0x17CF3A, ropeFlags = 0x17CF42,
  switchTab2 = 0x17CEE3,
  uncle = 0x1792D4, priest = 0x179490, maiden = 0x1795B0, maidenDma = 0x179630,
  mantleX = 0x16FE3A, mantleY = 0x16FE40, mantleChar = 0x16FE46, mantleFlags = 0x16FE4C,
}

-- MENUS AND HUD (round 4b). The cartridge carries 7 languages (0 Japanese,
-- 1 US English, 2 UK English, 3 French, 4 German, 5 Spanish, 6 Italian; the
-- language byte is RAM 0x03002230+0x98E). 0x0812EED8 loads, per language,
-- three LZ77 4bpp sheets of 128 tiles from uiLangSheets[lang] (3 x u32) to
-- VRAM 0x06004000/0x5000/0x6000: the BG3-style "HUD charblock", numbered like
-- the SNES BG3 tiles (digits 0x90, hearts 0xA0-0xA2, letters 0x100+).
-- The HUD itself (Hud_Rebuild/Update ported by the GBA at 0x080A7xxx):
--   hudTemplate  6 rows x 32 GBA map words, copied to RAM 0x0200B180 by
--                0x080A797C (magic meter, counters' icons, item box frame)
--   hudMagic     [17][4] words, the meter column by (magic+7)>>3 (0x080A75FC)
--   hudHeartCap / hudHeartCur  3 words each (0x080A7588 -> 0x080A7830)
--   hudPal0      the HUD's 2bpp-style colours: 8 rows of 4 from palette-blob
--                colour 0x308 + hudPal0Index[RAM 0xCAA], stride 16 (0x08130384)
--   hudPalHi     128 colours (BG palettes 8-15) copied by the same loader;
--                the next 128 (hudPalHi + 0x100) are OBJ palettes 8-15
M.ui = {
  langSheets  = 0x22B9E4,  -- [7][3] u32 -> LZ77 4096-byte sheets
  langCount   = 7,
  lang        = 1,         -- US English (this is the USA cartridge)
  hudTemplate = 0x16B65C,
  hudMagic    = 0x16B7E8,
  hudHeartCap = 0x16B7DC,
  hudHeartCur = 0x16B7E2,
  hudPal0Index = 0x22BC0C, -- u16 per HUD palette mode (+ blob colour 0x308)
  hudPal0Blob = 0x308,
  hudPalHi    = 0x3BF758,
  maxBombs    = 0x16B588,  -- u8 [8] by upgrade level
  maxArrows   = 0x16B598,  -- u8 [8]
  -- HUD buffer positions (word index in the 6x32 template) written by the
  -- update routines: hearts 0x0200B1A2, magic column 0x0200B1C4, rupees
  -- 0x0200B1CA, bombs 0x0200B1D2, arrows 0x0200B1D8, keys 0x0200B1DE, key
  -- icon 0x0200B19E, item box 0x0200B1F8.
  hudAt = { hearts = 17, magic = 34, rupees = 37, bombs = 41, arrows = 44,
            keys = 47, keyIcon = 15, itemBox = 60 },
  -- THE TITLE SCREEN (loader 0x0812D430 / 0x0812D4CC, palettes 0x0812D338):
  -- charblock 0 = titleChr (LZ77) + titleChr2 at +0x3400 + the language
  -- subtitle titleSub at +0x2000 (only when the language is not 0); BG1 map
  -- titleBg1 -> 0x0600A000, BG2 map titleBg2 -> 0x0600C000 (one 32x32
  -- screenblock each, LZ77); the subtitle strip list titleStrips (u16 VRAM
  -- offset, u16 count, words..., 0xFFFF) is drawn by 0x08068E7C; palettes:
  -- the HUD loader, then 128 colours titlePal -> BG palette 2, 16 colours
  -- titlePal2 -> BG palette 13. Scroll (RAM +0x950/+0x952/+0x956/+0x958 set
  -- at 0x0812D514): BG1 x 8, BG2 x 16, both y 24.
  titleChr    = 0x3B37B4,
  titleChr2   = 0x3B47FC,
  titleSub    = 0x3C23D4,
  titleBg1    = 0x3B5144,
  titleBg2    = 0x3B53A0,
  titleStrips = 0x22B088,
  titlePal    = 0x3B556C,
  titlePal2   = 0x22B048,
  titleScroll = { bg1x = 8, bg2x = 16, y = 24 },
}

-- THE ITEM MENU (round 8; GBA module 0x0E submodule 1, Hud_Module_Run at
-- 0x080AA808, its state table 0x16E004: 0 load 0x080AABC0, 1 draw
-- 0x080AAC24, 2 pick the item 0x080A9EA8, 3 slide down 0x080A9F20, 4 any
-- items? 0x080A9F5C, 5 choose 0x080AA4F8, 6/7 close 0x080AA920/0x080AA688).
-- The menu is the HUD layer (BG3, charblock 0x06004000) with its own
-- pre-rendered 32x32 map, LZ77 itemMap -> 0x06009000; itemLang[lang] (LZ77,
-- 128 tiles) -> tile 0x180. Every later word goes through the upload list
-- 0x02000400 ({u16 VRAM offset, u16 count | 0x8000 down | 0x4000 fill,
-- words}, drawn by 0x08068E7C). Positions below are those VRAM offsets
-- minus 0x8000 (the map's own byte offset + 0x1000).
--   gridPos    u16 [24] slot -> map offset (0x080A8178 writes the icons)
--   gridTab    per slot: 4 words per item level (a word table in the ROM)
--   bombsSlot  bombs draw level 1 whenever the count is non-zero
--   bottleTab  slots 6/12/18/24 (the four bottles): words by content
--   names      u32 [lang] -> 24 x 16 words (2 rows of 8) at 0x932C/0x936C,
--              written by 0x080A9FCC; bottles/5/23/1 use the extra tables
--   equip      sword/shield/mail (0x080A97F8), ability box (0x080A8D70),
--              pendants (0x080A93B8): {save byte, word table, map offset}
-- Save bytes are offsets from 0x02002300 (the GBA's SRAM mirror; the item
-- bytes are in menu-slot order from 0x02002320, NOT the SNES order).
M.menu = {
  itemMap     = 0x3BFC58,
  itemLang    = 0x16BE94,
  window      = { 0x16B600, 0x16E100 },  -- the menu's word tables
  vofsOpen    = -184,  -- BG3 y scroll when down (0x080A9F20: -8 a frame from 4)
  vofsStart   = 4,
  gridPos     = 0x16DEE0,
  gridTab     = { 0x16B880, 0x16B8A8, 0x16B8C0, 0x16B8D0, 0x16B8E0, false,
                  0x16B8F8, 0x16B908, 0x16B918, 0x16B928, 0x16B938, false,
                  0x16B948, 0x16B958, 0x16B968, 0x16B988, 0x16B998, false,
                  0x16B9A8, 0x16BA00, 0x16BA10, 0x16BA20, 0x16BA30, false },
  bombsSlot   = 4,
  bottleTab   = 0x16B9B8,
  bottleSlots = { [6] = true, [12] = true, [18] = true, [24] = true },
  selIcon     = 0x12B2,  -- the chosen item's icon (copied from its slot)
  nameAt      = { 0x132C, 0x136C },
  names       = 0x16DF40,
  -- name exceptions in 0x080A9FCC: {slot, table, first level}
  nameAlt     = { { 6, 0x16DF5C, 1 }, { 12, 0x16DF5C, 1 }, { 18, 0x16DF5C, 1 },
                  { 24, 0x16DF5C, 1 }, { 5, 0x16DF78, 2 }, { 23, 0x16DF94, 2 },
                  { 1, 0x16DFCC, 2 } },
  cursor      = { 0x9053, 0x9853, 0x9453, 0x9C53 },  -- left / right brackets
  equip       = { { 0x3D, 0x16BAA0, 0x15EC }, { 0x3E, 0x16BAC8, 0x15F2 },
                  { 0x3F, 0x16BAE8, 0x15F8 } },
  ability     = { { 0x39, 0x16BA68, 0x1688 }, { 0x38, 0x16BA50, 0x1690 },
                  { 0x3A, 0x16BA78, 0x1698 }, { 0x3B, 0x16BA88, 0x16A0 } },
  glovesWord  = { 0x165A, 0x8144 },  -- word 0x8144 + glove level
  pendants    = { 0x54, { 0x16BB38, 0x1472 }, { 0x16BB48, 0x14EE }, { 0x16BB58, 0x14F6 } },
  blank       = 0x00F5,
  -- the box titles, written at load by 0x080A7B24 (a switch on the
  -- language; English is the case at 0x080A7F9C, its words are immediates):
  -- {map offset, first word, count of consecutive words} or {offset, {words}}
  labels      = { [1] = { { 0x1246, 0x81F8, 4 }, { 0x1586, { 0x8153, 0x815E } },
                          { 0x15AC, 0x81F0, 8 }, { 0x142C, 0x8010, 8 } } },
}

-- THE OVERWORLD MAP (round 8; module 0x0E submodule 7, 0x080B33C8, state
-- table 0x16ED14; load 0x080B1DB4, control 0x080B1EFC). BG2 affine in mode
-- 1 (DISPCNT 0x3421), 64x64 one-byte map of 8bpp tiles: tiles owTiles
-- (0x4000 bytes, CpuFastSet to 0x06000000), map owMap[world] (0x1000 bytes
-- to 0x0600C000), 128 colours owPal[world]. The SNES mode-7 tilt is done per
-- scanline by the HBlank handler 0x08068B7C (mode RAM +0x982 == 3) from a
-- u16 table per line (owZoom[flags], 230 entries, copied to 0x02001600):
--   PA = s, BG2X = X0 * 256 - 120 * s, BG2Y = Y0 * 256 + (s + s / 2) * line
-- with X0 = RAM +0x950, Y0 = RAM +0x956. Zoomed in (flags 1, the default)
-- 0x080B198C centres on Link: Y0 = (y / 16 + 0x30) & ~1 clamped 80..336,
-- X0 = (x / 16 + 0x80) & ~1 clamped 128..368; zoomed out Y0 = 0x6E,
-- X0 = 0xFA. The d-pad scrolls (zoomed in) by owStep/owLimit (u16 tables
-- indexed by the SNES-style held byte, kOverworldMap_Table3/Table2). B
-- leaves; L/R switch the zoom (8-frame wait). Window 0 shows lines 2-157
-- (WIN0V 0x029E, WINOUT 0).
M.owmap = {
  tiles   = 0x28A7E0, tilesBytes = 0x4000,
  map     = { lw = 0x3BFEF8, dw = 0x3C0EF8 }, mapBytes = 0x1000,
  pal     = { lw = 0x3BFA58, dw = 0x3BFB58 }, palColours = 128,
  zoom    = { [0] = 0x16E974, [1] = 0x16EB34 },  -- u16 [230]: out, in
  step    = 0x16ECF4,   -- s16 [8]
  limit   = 0x16ED04,   -- s16 [8]
  window  = { 0x16E900, 0x16ED20 },
  outY0   = 0x6E, outX0 = 0xFA,
  winTop  = 2, winBottom = 158,
}

-- DIALOGUE (round 4b). The messages are a Nintendo BMG file ("MESGbmg1",
-- big-endian, sections INF1 = u32 offsets, DAT1 = text) per language; the
-- language switch at 0x0812963C picks textBmg for US English. Every byte is
-- scrambled by its offset from the file start; the reader is 0x08129E0C:
--   k = off & 0xFF, j = off & 15
--   v = (k - key[15 - j]) XOR b[off];  if off > 0x2A: v = v - b[off - 0x2B]
--   v = ((v - k) XOR key[j]) & 0xFF          (key = textKey, 16 bytes)
-- Message lookup 0x08129D28 (index > 15 is SNES index - 3, 0x0812740C).
-- Text is ASCII with '\n'; 0x1A starts a command { 0x1A, length, kind, 0,
-- code, args } whose code is the SNES text command (0x67 + n: 0x6A name,
-- 0x73 scroll, 0x74-0x76 line, 0x78 wait, 0x7A speed, 0x7E wait for key,
-- 0x7F end); kind 1 is a glyph from the symbol row.
-- The font (0x08127F00): 4bpp, a glyph is 8x16 = tile (c>>4)*32 + (c&15) and
-- the tile 16 further on; English adds 0x100 to codes <= 0x7F; advance width
-- textWidths[c]. Window (0x081290B4): border tiles textBorder (9 words: top
-- left/middle/right, side/fill/side, bottom) in the HUD charblock, 24 x 8
-- tiles at map byte offset textWindowPos[0 or 1] (Link low on screen -> 0),
-- glyph tiles 0x180+ with palette 1, 21 x 6 tiles, one tile in from the
-- border. Wait durations textWaits (16 u16).
M.text = {
  textBmg   = 0x180CE8,
  key       = 0x180CD0,
  font      = 0x3B5758,
  fontBytes = 0x8000,
  widths    = 0x195D98,
  border    = 0x180CBC,
  windowPos = 0x18097C,
  waits     = 0x180C9C,
}

-- FOUR SWORDS. The same cartridge program (code 0x08000000-0x08140000) also
-- runs Capcom's Four Swords, whose engine is the ancestor of The Minish Cap's
-- (same gfx-group / palette-group / map-layer structures; see
-- docs/zelda/alttp.md "Four Swords"). Found by disassembly:
--   init 0x0800B084 stores the palette base (0x0844DD74) and the graphics
--   base (0x0854F7E8); LoadGfxGroup 0x0801484C; LoadPaletteGroup 0x0800B890;
--   LoadAreaTileset 0x08015DD8 (gfx group 6+area); LoadFloorMap 0x08015F74
--   (gfx group 12+map -> two 63x63 u16 metatile layers); collision fill
--   0x080160F8 (collision = table[tileType[metatile]]); floor loader
--   0x08012EB4 reads a floor struct (map, area, ..., +0x14 lists, +0x18
--   8-byte object records ending in 0xFFFFFFFF).
M.fs = {
  gfxBase     = 0x54F7E8,  -- gGlobalGfx: offsets in gfx groups are from here
  palBase     = 0x44DD74,  -- palette groups' u16 byte offsets are from here
  gfxGroups   = 0x146060,  -- u32 pointers
  palGroups   = 0x429750,  -- u32 pointers
  tilesetGroup0 = 6,       -- area a -> gfx group 6 + a
  mapGroup0   = 12,        -- floor map m -> gfx group 12 + m
  mapCount    = 123,
  areaCount   = 6,         -- areas 0..5 (5 = 3's tileset)
  collision   = 0x14AB24,  -- u8 per tile type
  collisionLen = 0x1000,
  worlds      = 0x42B8A8,  -- u32 pointers to the world floor tables
  worldCount  = 6,
  linkPalettes = 0x44DD74, -- 4 x 16 colours: green, red, blue, purple Links
  -- animated BG tiles (0x08015D50): area -> u16 ids (0xFFFF ends), id ->
  -- animation; an animation is { u32 frame ptr, u32 frames } pairs ending in
  -- a 0 pointer; a frame is { u16 vram offset, u16 tiles - 1, u32 gfx offset }
  animLists   = 0x146060,  -- u32 per area (0 = none)
  animTable   = 0x138BB4,  -- u32 per animation id
  mapW        = 63,        -- layer stride (metatiles)
}

-- BUG ROUND (user report, 2026-11-09). Link's sword and shield, chests, pots.
-- Found by value against the SNES tables (zelda3 player_oam.c / dungeon.c /
-- ancilla.c); the GBA keeps them with 517-entry pose tables (indexed by its
-- own playerOamOffs) and its OBJ rows 32 tiles wide (second-row chars +0x20).
M.weapon = {
  poseCount   = 517,
  swordSel    = 0x169CE2,  -- u8 [517] kPlayerOam_Main_SwordStuff_array1 (0xFF none)
  shieldSel   = 0x169EE7,  -- u8 [517] kPlayerOam_ShieldStuff_array1
  swordY      = 0x16A0EC,  -- s8 [517] kDrawSword_y
  swordX      = 0x16A2F1,  -- s8 [517] kDrawSword_x
  shieldY     = 0x16A6E6,  -- s8 [517] kShieldStuff_y
  shieldX     = 0x16A8EB,  -- s8 [517] kShieldStuff_x
  spriteLocs  = 0x16AF12,  -- u8 [517] kPlayerOamSpriteLocs (r4loc)
  swordSelCount = 79,      -- SNES 76; the GBA adds 3 (its 6 extra poses)
  swordTiles  = 0x16952E,  -- u16 [79 * 3] kSwordTiledata (3 OAM words per sel)
  shieldTiles = 0x169708,  -- u16 [54]  kShieldStuff_OamData
  swordSize   = 0x16B407,  -- u8 [79] kPlayerOam_Main_SwordStuff_array2 (2 = 16x16)
  swordDmaSel = 0x16B3AE,  -- u8 [79] kPlayerOam_Main_SwordStuff_array3 (link_dma_var3)
  shieldDmaSel= 0x16B392,  -- u8 [18] kPlayerOam_ShieldStuff_array2 (link_dma_var4)
  swordOamIdx = 0x16B278,  -- u8 [12] kSwordStuff_oam_index_ptrs_0 (by r4loc)
  bodyOamIdx  = 0x16B284,  -- u8 [12] kLinkBody_oam_index_0
  shieldOamIdx= 0x16B290,  -- u8 [12] kShieldStuff_oam_index_ptrs_0
  -- the weapon strip's DMA sources (SNES kLinkDmaSources4/5): the GBA's
  -- strip starts at 0x8380 (SNES 0x9000): sword 12 tiles + 12 below
  -- (+0x180), shield at +0x300, 6 tiles + 6 below (+0xC0)
  swordDma    = 0x22A9DC,  -- u16 [8]
  shieldDma   = 0x22A9EC,  -- u16 [3]
  stripBase   = 0x8380,
  uncleDma3   = 0x179454,  -- u8 [8] kUncleDraw_Dma3 (sword frame by dir*2+gfx)
  uncleDma4   = 0x17945C,  -- u8 [8] kUncleDraw_Dma4 (shield frame)
}
-- the dungeon object tile table (SNES kDungeonObjectTiles in GBA map words;
-- SNES offset 0x149C = the closed chest): closed chest 4 words, then the
-- open chest 4 words (SNES SrcPtr(0x14A4), column-major UL LL UR LR); the
-- open big chest (SNES SrcPtr(0x14C4)) is 12 words, 4 columns of 3
M.chestTiles     = 0x1659BC
M.bigChestOpen   = 0x1659E4
-- round 11: the cucco's calm hops (GBA Cucco_Calm 0x080EA700: j = rng & 15,
-- x velocity = [j], y velocity = [16 + j], s8 each; SNES kSpriteKeese_Tab2/3)
M.cuccoVel       = 0x177D54
-- kReceiveItemMsgs (76 x u16, the cartridge's message ids: T.bmgIndex)
M.receiptMsgs    = 0x17F288
M.receiptCount   = 76
-- RoomDraw_SinglePot's replacement words (the floor under a lifted pot,
-- UL LL UR LR), literals of the GBA routine at 0x0807CBxx
M.potHole        = { 0x7CBCC, 0x7CBD4, 0x7CBDC, 0x7CBE4 }

-- ROUND 9: what bushes, grass, rocks and pots drop (zelda3 sprite.c
-- Sprite_SpawnSecret / Overworld_SubstituteAlternateSecret, the GBA's own
-- routines at 0x080C2534 / 0x080CA754, its random number routine 0x080CEFE0
-- and the throwable-terrain tail 0x080C2A6A; tables found by value and read
-- by those routines). The GBA keeps the SNES item table but its
-- substitution masks moved up by four bits (tab0/tab1 below) and its
-- counter is pre-incremented.
M.drops = {
  secretItems = 0x171DCB,  -- u8 [22] kSpawnSecretItems (sprite type by secret - 1)
  secretFlag  = 0x171DE1,  -- u8 [22] kSpawnSecretItem_SpawnFlag (ai state)
  secretXLo   = 0x171DF7,  -- u8 [22] kSpawnSecretItem_XLo
  secretIgnore= 0x171E0D,  -- u8 [22] kSpawnSecretItem_IgnoreProj
  secretZVel  = 0x171E23,  -- u8 [22] kSpawnSecretItem_ZVel (GBA: [12] = 0x10)
  secretCount = 22,
  substArea   = 0x172848,  -- u8 [64] by overworld area & 0x3F (kSecretSubst_Tab0)
  substSecret = 0x172888,  -- u8 [16] the substituted secret (kSecretSubst_Tab2)
  substMask   = 0x172898,  -- u8 [16] the area bit each one needs clear (kSecretSubst_Tab1)
  prizeItems  = 0x17217A,  -- u8 [56] kPrizeItems (enemy prize packs, 7 x 8)
  prizeZ      = 0x172160,  -- u8 [15] kPrizeZ (z velocity | x offset, types 0xD8..)
  -- the absorbables' drawing (SpriteDraw_AbsorbableTransient): by type - 0xD8
  absorbKind  = 0x1720D4,  -- u8 [15] kAbsorbable_Tab1 (0 small, 1 thin/tall, 2 large)
  absorbNum   = 0x1720E3,  -- u8 [19] kAbsorbable_Tab2 (numbered: bombs, arrows)
  numX        = 0x1720F2,  -- s16 [18] kNumberedAbsorbable_X
  numY        = 0x172116,  -- s16 [18] kNumberedAbsorbable_Y
  numChar     = 0x17213A,  -- u8 [18] kNumberedAbsorbable_Char (GBA chars)
  numExt      = 0x17214C,  -- u8 [18] kNumberedAbsorbable_Ext (2 = 16x16)
  -- the debris of a cut / thrown bush or pot (Garnish16_ThrownItemDebris,
  -- GBA 0x080CD724: 4 pieces a frame over a 31-frame countdown; kind 4, or
  -- kind 2 outdoors, use the second half (+0x20), kind 0x10 the third
  -- (+0x40, GBA only); a pot (kind 0) is char 0x8E)
  debrisX     = 0x172BD0,  -- s16 [64] kScatterDebris_Draw_X
  debrisY     = 0x172C90,  -- s8 [64] kScatterDebris_Draw_Y
  debrisChar  = 0x172CF0,  -- u8 [64] kScatterDebris_Draw_Char (GBA chars)
  debrisFlags = 0x172D50,  -- u8 [64] kScatterDebris_Draw_Flags
  kindFlags   = 0x1778C0,  -- u8 [12] kThrowableScenery_Flags (OAM flags by kind)
}

-- Read a header string from the first 0x200 bytes of a cartridge.
function M.headerCode(header)
  if type(header) ~= "string" or #header < 0xB0 then return nil, nil end
  return header:sub(0xAD, 0xB0), header:sub(0xA1, 0xAC):gsub("%z+$", "")
end

-- THE FRONT END (round 13, FrontExtract.lua): the shared screens of the
-- top-level tasks 8 (CHOOSE A FILE / ENTER A NAME, 0x0800F809) and 6
-- (CHOOSE A GAME, 0x0803074D), as the cartridge decompresses them (BIOS
-- LZ77 to VRAM, logged in the scratch interpreter): { rom offset, VRAM
-- offset, size } in load order; the name screen's BG0 / BG2 / BG1 maps;
-- the palettes (BG 16 rows, OBJ 16 rows; task 8's OBJ row 7 apart).
M.front = {
  fileLoads = {
    { 0x4F2AA8, 0x10480, 0x1B80 }, { 0x53D91C, 0x11C00, 0x200 }, { 0x4EC414, 0x16000, 0x900 },
    { 0x4ECD4C, 0x0000, 0x1800 }, { 0x4F8A78, 0x8000, 0x5000 }, { 0x4F8288, 0xF000, 0x800 },
    { 0x4EE384, 0x1800, 0x1C00 }, { 0x4F40D0, 0x12000, 0x3000 }, { 0x4F2448, 0xD800, 0x500 },
    { 0x4F2510, 0xE000, 0x500 },
  },
  nameMaps = { { 0x4F282C, 0x100 }, { 0x4F28A8, 0x500 }, { 0x4FC070, 0x500 } },
  gameLoads = {
    { 0x4E3488, 0x0000, 0x4000 }, { 0x4E4560, 0x4000, 0x4000 }, { 0x4E7628, 0x10000, 0x5400 },
    { 0x4EB5C4, 0x16800, 0x800 }, { 0x53D91C, 0x17000, 0x200 }, { 0x4E9B20, 0x10400, 0x1000 },
    { 0x4EA458, 0x12000, 0x400 }, { 0x4EA5A8, 0x13400, 0x2000 }, { 0x4EB9F8, 0x16400, 0x400 },
    { 0x4E6800, 0xD000, 0x800 }, { 0x4E6B6C, 0xD800, 0x800 }, { 0x4E6ED8, 0xE000, 0x1000 },
    { 0x4E7354, 0xF000, 0x1000 },
  },
  filePalBg = 0x44F0F4, filePalObj = 0x44F6F4, filePalObj7 = 0x44DD74,
  gamePalBg = 0x44EC34, gamePalObj = 0x44EE34,
  -- the EEPROM (round 13, findings; saves stay ZeldaSaves tables): 8 KB,
  -- a second copy at +0x1000; records (0x0814C654, 12 bytes: size, header
  -- A, header B, data, data 2): 0-2 the ALttP files (0x480 bytes at 0x100 /
  -- 0x600 / 0xB00 = RAM 0x02002000-0x0200247F), 3 the 0x20-byte signature
  -- at 0, 4-6 the front end's 0x40-byte file records (0x580 / 0xA80 / 0xF80,
  -- alternate 0x5C0 / 0xAC0 / 0xFC0; RAM 0x0200B250 + 64 * file: the
  -- player's name is 6 bytes at +8, +0x3F the file's state), 7 0x10 bytes
  -- of settings at 0xE0; headers hold a checksum (0x080679B0 over "S4FT"
  -- and the data) and its negative
  eepromRecords = 0x14C654,
}

-- Round 16: room objects the GBA room loader draws over its pre-rendered
-- maps (RoomObjects.lua): the new-game push-block table (u16 room, u16
-- tilemap pos * 2 | 0x2000 lower map; until room 0xFFFF; CpuSet by
-- 0x08078EE2 to RAM 0x020029C0), the push block's word (literal of
-- 0x0807D17C), the rupee floor's two words (SNES src 0x1DD6), the large
-- pick-up block's 16 (0xE62..), the bomb floor's 16 (0x220), the floor word
-- of Dungeon_DeleteRupeeTile (literal of 0x08087FC4) and the immediate of
-- the blank word 0x08080718 fills the lower map with (Blind's room light).
-- Round 16: people (Npc.lua): the overworld sprite lists by story phase
-- (0x080CB140: u32 per area -> { y, x, type } x n, 0xFF; the first table
-- only covers the 64 Light World areas) and the GBA copies of the SNES
-- DrawMultipleData tables (8 bytes an entry) of the townsfolk.
-- r23: the desert (Desert.lua): the statues' speeds / turns, the prayer's
-- delays, the Desert Palace's Leever and Beamos tables (file offsets)
M.desert = { barrierXv = 0x178A14, barrierYv = 0x178A18, barrierNext = 0x178A1C, prayDelays = 0x14DAA6,
             leever = 0x175340, leeverX = 0x175374, beamos = 0x179B90 }
M.npc = {
  owSprites = { { 0x227D70, 64 }, { 0x227E70, 144 }, { 0x2280B0, 144 } },
  dmd = { elder = { 0x17642C, 4 }, wife = { 0x178E2C, 4 }, sweep = { 0x178E4C, 4 },
          trough = { 0x178D38, 8 }, snitch = { 0x179034, 16 }, lady = { 0x178E88, 16 },
          shop = { 0x17D2C4, 4 }, shopItems = { 0x17D0E4, 35 },
          statue = { 0x178A20, 4 } },   -- r23: kDesertBarrier_Dmd (Desert.lua)   -- r22: kShopkeeper_Dmd, kShopKeeper_ItemWithPrice_Dmd (Shop.lua)
}

-- Round 16: the ball-and-chain guard 0x6A (BallChain.lua): its routine
-- 0x080E2D4C reads the angle step at 0x08176E98 + state - 2, the
-- animation 0x176E78, the attack directions 0x176EAC, head / body OAM
-- tables (x / y are s16), the chain lengths (kFlailTrooperWeapon_Tab0), the
-- ball offsets per direction (Tab1 / Tab2), the link spacing (Tab4), the
-- sine table and the ball / chain OAM words (literals of 0x080E32CA /
-- 0x080E3352: flags << 8 | GBA char).
M.flail = {
  stateAdd = 0x176E96, gfx = 0x176E78, attackDir = 0x176EAC, headChar = 0x176EB0, headFlags = 0x176EB4,
  num = 0x176EB8, x = 0x176EE8, y = 0x176F78, char = 0x177008, flags = 0x177050, big = 0x177098,
  len = 0x1770E0, offX = 0x177100, offY = 0x177104, link = 0x177108, sine = 0x173F38,
  ballOam = 0x0E3398, chainOam = 0x0E33A4,
}

M.roomObj = {
  blockTable = 0x163430, blockWordLit = 0x07D26C, rupeeWords = 0x16623C,
  bigBlockWords = 0x165382, bombFloorWords = 0x164740, rupeeFloorLit = 0x08806C,
  blindBlankImm = 0x08072C,
}

return M
