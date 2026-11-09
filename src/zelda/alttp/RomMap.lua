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
M.owSprPalettes  = 0x14C8E8   -- 128 bytes, per screen
M.owBgPalLW      = { 0x14D8A4, 0x14D8A4, 0x14D8E4, 0x14D924 } -- phase 0..3
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
M.linkGfxIndexCount = 511
M.linkSpriteBodys= 0x169180   -- [309] { s8 y, s8 x, u8 tile }
M.playerOamOffs  = 0x16B118   -- u16 [160]
M.playerOamOffsCount = 160

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

-- Read a header string from the first 0x200 bytes of a cartridge.
function M.headerCode(header)
  if type(header) ~= "string" or #header < 0xB0 then return nil, nil end
  return header:sub(0xAD, 0xB0), header:sub(0xA1, 0xAC):gsub("%z+$", "")
end

return M
