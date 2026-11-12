-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ALTTP IMPORTER. Runs inside the import worker (no love.graphics), reads
-- the player's own cartridge and writes everything the runtime needs into the
-- game's cache subtree. Nothing here holds cartridge data: RomMap says where
-- to look, this file decodes and verifies.
--
-- Stages (each writes its own files, then a stage stamp; a re-run skips the
-- stages whose stamp is present, so an interrupted import resumes):
--
--   tables   data/generated/alttp_tables.lua   tilesets, palette indexes,
--                                              per-screen tables, tile
--                                              attributes, Link OAM tables,
--                                              speeds
--   palette  assets/generated/alttp/pal.bin     4096 BGR555 colours
--   sheets   assets/generated/alttp/sheets.bin  235 x 2048 bytes of 4bpp tiles
--   link     assets/generated/alttp/link.bin    Link's 4bpp sheet
--   maps     assets/generated/alttp/ow.bin      unique 8192-byte tilemaps
--            data/generated/alttp_maps.lua      screen -> map index
--   music    assets/generated/audio/m4a.bin     the M4A span (songs, voices,
--            data/generated/alttp_songs.lua     samples) + song headers
--
-- Every structure is checked as it is read (pointer ranges, LZ77 sizes,
-- palette words < 0x8000, tile attribute range, every music track walked to its
-- end); a ROM that does not match fails the import loudly instead of shipping
-- a cache built from a misreading.

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local R = require("src.zelda.alttp.RomMap")
local S = require("src.zelda.alttp.Serialize")

local E = {}

E.STAGES = { "tables", "palette", "sheets", "link", "maps", "music", "fs", "rooms", "ui", "sprites", "menus", "front" }
E.FILES = {
  tables  = "data/generated/alttp_tables.lua",
  palette = "assets/generated/alttp/pal.bin",
  sheets  = "assets/generated/alttp/sheets.bin",
  link    = "assets/generated/alttp/link.bin",
  maps    = "assets/generated/alttp/ow.bin",
  mapsIdx = "data/generated/alttp_maps.lua",
  music   = "assets/generated/audio/m4a.bin",
  songs   = "data/generated/alttp_songs.lua",
  rooms   = "assets/generated/alttp/rooms.bin",
  roomsIdx = "data/generated/alttp_rooms.lua",
}
E.SHEET_BYTES = 2048
E.MAP_BYTES = 8192

local function stampPath(stage) return "data/generated/alttp_stage_" .. stage .. ".done" end
E.stampPath = stampPath

-- ------------------------------------------------------------- reading

local Rom = {}
Rom.__index = Rom

function E.rom(bytes)
  assert(type(bytes) == "string", "ALttP import needs the cartridge bytes")
  return setmetatable({ data = bytes, size = #bytes }, Rom)
end

local sbyte = string.byte
function Rom:u8(o)
  local b = sbyte(self.data, o + 1)
  if not b then error(("ALttP: read past the end of the ROM at %06X"):format(o), 0) end
  return b
end
function Rom:s8(o) local v = self:u8(o) return v >= 128 and v - 256 or v end
function Rom:u16(o)
  local a, b = sbyte(self.data, o + 1, o + 2)
  if not b then error(("ALttP: read past the end at %06X"):format(o), 0) end
  return a + b * 256
end
function Rom:u32(o)
  local a, b, c, d = sbyte(self.data, o + 1, o + 4)
  if not d then error(("ALttP: read past the end at %06X"):format(o), 0) end
  return a + b * 256 + c * 65536 + d * 16777216
end
function Rom:ptr(o)
  local v = self:u32(o)
  if v < 0x08000000 or v >= 0x08000000 + self.size then return nil end
  return v - 0x08000000
end
function Rom:sub(o, n) return self.data:sub(o + 1, o + n) end
function Rom:bytesU8(o, n)
  local t = {}
  for i = 0, n - 1 do t[i + 1] = self:u8(o + i) end
  return t
end
function Rom:bytesU16(o, n)
  local t = {}
  for i = 0, n - 1 do t[i + 1] = self:u16(o + i * 2) end
  return t
end

-- GBA BIOS LZ77 (type 0x10) into a string. Returns data, compressedLength or
-- nil, why. The back-reference may overlap the write head, so the copy is a
-- byte at a time.
function Rom:lz77(o)
  local d = self.data
  local h0, h1, h2, h3 = sbyte(d, o + 1, o + 4)
  if h0 ~= 0x10 then return nil, ("no LZ77 header at %06X"):format(o) end
  local size = h1 + h2 * 256 + h3 * 65536
  local out, n, pc = {}, 0, o + 5
  while n < size do
    local flags = sbyte(d, pc); pc = pc + 1
    if not flags then return nil, "LZ77 ran off the ROM" end
    for b = 7, 0, -1 do
      if n >= size then break end
      if band(flags, lshift(1, b)) ~= 0 then
        local b0, b1 = sbyte(d, pc, pc + 1); pc = pc + 2
        local len = rshift(b0, 4) + 3
        local disp = bor(lshift(band(b0, 15), 8), b1) + 1
        if disp > n then return nil, ("LZ77 reference before start at %06X"):format(o) end
        for _ = 1, len do
          n = n + 1
          out[n] = out[n - disp]
        end
      else
        n = n + 1
        out[n] = sbyte(d, pc); pc = pc + 1
      end
    end
  end
  for i = size + 1, n do out[i] = nil end
  local parts = {}
  for i = 1, size, 4096 do
    parts[#parts + 1] = string.char(unpack(out, i, math.min(size, i + 4095)))
  end
  return table.concat(parts), pc - (o + 1)
end

-- ------------------------------------------------------------- checks

function E.detect(header)
  local code, title = R.headerCode(header)
  return code == R.GAME_CODE and (title == nil or title == R.GAME_TITLE or title == "")
end

local function check(cond, fmt, ...)
  if not cond then error("ALttP import: " .. fmt:format(...), 0) end
end

-- ------------------------------------------------------------- stages

function E.readTables(rom)
  local t = {}
  t.mainTilesets, t.auxTilesets, t.spriteTilesets = {}, {}, {}
  for i = 0, R.mainTilesetCount - 1 do
    t.mainTilesets[i + 1] = rom:bytesU8(R.mainTilesets + i * 8, 8)
  end
  for i = 0, R.auxTilesetCount - 1 do
    t.auxTilesets[i + 1] = rom:bytesU8(R.auxTilesets + i * 4, 4)
  end
  for i = 0, R.spriteTilesetCount - 1 do
    t.spriteTilesets[i + 1] = rom:bytesU8(R.spriteTilesets + i * 4, 4)
  end
  -- r15: the animated BG tiles' sheet per main tileset (SNES
  -- kDungAnimatedTiles; GBA 0x0806AC3C reads it into 0x0812FCDC)
  t.dungAnim = rom:bytesU8(R.dungAnimTiles, R.mainTilesetCount)
  for _, s in ipairs(t.dungAnim) do check(s < R.gfxSheetCount, "animated tile sheet %d", s) end
  -- the overworld rows: Light World main set 0x20, Dark World 0x21, each
  -- naming 8 sheets below the sheet count
  for _, row in ipairs({ t.mainTilesets[0x21], t.mainTilesets[0x22] }) do
    for _, s in ipairs(row) do check(s < R.gfxSheetCount, "main tileset sheet %d", s) end
  end

  t.palIndexMain = rom:bytesU16(R.palIndexMain, 6)
  t.palIndexAux12 = rom:bytesU16(R.palIndexAux12, 20)
  t.palIndexAux3 = rom:bytesU16(R.palIndexAux3, 20)
  t.palIndexSprAux = rom:bytesU16(R.palIndexSprAux, 24)
  t.owBgPalInfo = {}
  for i = 0, R.owBgPalInfoCount - 1 do
    t.owBgPalInfo[i + 1] = rom:bytesU8(R.owBgPalInfo + i * 4, 3)
  end
  t.backdrop = { lw = rom:u32(R.backdropLW), dw = rom:u32(R.backdropDW),
                 dm = rom:u32(R.backdropDM) }
  for k, v in pairs(t.backdrop) do check(v < 0x8000, "backdrop colour %s = %X", k, v) end

  t.owParent = rom:bytesU8(R.owParent, R.owScreens)
  for s = 0, 127 do
    local p = t.owParent[s + 1]
    check(p <= s and t.owParent[p + 1] == p and band(p, 0x40) == band(s, 0x40),
          "overworld parent table: screen %02X -> %02X", s, p)
  end
  t.owAuxTileset = rom:bytesU8(R.owAuxTileset, 128)
  t.owSprPalettes = rom:bytesU8(R.owSprPalettes, 128)
  t.owBgPalLW = {}
  t.owSprGfxLW = {}
  for phase = 1, 4 do
    t.owBgPalLW[phase] = rom:bytesU8(R.owBgPalLW[phase], 64)
    t.owSprGfxLW[phase] = rom:bytesU8(R.owSprGfxLW[phase], 64)
  end
  t.owBgPalDW = rom:bytesU8(R.owBgPalDW, 64)
  t.owSprGfxDW = rom:bytesU8(R.owSprGfxDW, 64)
  -- round 10: kOwSprPalInfo (sp5l, sp6l per overworld sprite palette set)
  t.owSprPalInfo = rom:bytesU8(R.owSprPalInfo, 40)
  for _, list in ipairs({ t.owBgPalDW, t.owBgPalLW[1], t.owBgPalLW[4] }) do
    for _, v in ipairs(list) do check(v < R.owBgPalInfoCount, "bg palette set %d", v) end
  end
  for _, v in ipairs(t.owAuxTileset) do check(v < R.auxTilesetCount, "aux tileset %d", v) end

  t.tileAttr = rom:bytesU8(R.tileAttr, 512)
  -- the open-water tile (map8 0x1FE) is deep water on every overworld; a
  -- shifted table fails here
  check(t.tileAttr[0x1FE + 1] == 0x08, "tile attribute table: water is %02X",
        t.tileAttr[0x1FE + 1])

  t.linkDmaSrc1 = rom:bytesU16(R.linkDmaSrc1, R.linkDmaCount)
  t.linkDmaSrc2 = rom:bytesU16(R.linkDmaSrc2, R.linkDmaCount)
  t.linkGfxIndices = rom:bytesU16(R.linkGfxIndices, R.linkGfxIndexCount)
  t.linkSpriteBodys = {}
  for i = 0, R.linkDmaCount - 1 do
    local o = R.linkSpriteBodys + i * 3
    t.linkSpriteBodys[i + 1] = { rom:s8(o), rom:s8(o + 1), rom:u8(o + 2) }
  end
  t.playerOamOffs = rom:bytesU16(R.playerOamOffs, R.playerOamOffsCount)
  for _, v in ipairs(t.linkGfxIndices) do check(v < R.linkDmaCount, "link dma index %d", v) end
  for _, v in ipairs(t.linkDmaSrc1) do check(v >= 0x8000 and v < 0x8000 + R.linkGfxBytes, "link head src %X", v) end
  for _, v in ipairs(t.playerOamOffs) do check(v < R.linkGfxIndexCount, "player oam offs %d", v) end

  -- round 14: the OBJ priority tables (RomMap.layers, Layers.lua)
  t.layers = { oamPrioMap = rom:bytesU8(R.layers.oamPrioMap, 5),
               linkFloorPrio = rom:bytesU16(R.layers.linkFloorPrio, 4),
               spritePrios = rom:bytesU8(R.layers.spritePrios, 4) }
  for i = 1, 4 do
    check(t.layers.oamPrioMap[i] <= 3, "oam priority map %d", t.layers.oamPrioMap[i])
    check(band(t.layers.linkFloorPrio[i], 0xCFFF) == 0, "link floor priority %X", t.layers.linkFloorPrio[i])
    check(band(t.layers.spritePrios[i], 0xCF) == 0, "sprite priority %X", t.layers.spritePrios[i])
  end
  t.speedMod = rom:bytesU8(R.speedMod, 27)
  t.animTab2 = rom:bytesU8(R.animTab2, 16)
  t.animTab3 = rom:bytesU8(R.animTab3, 24)
  t.weapon = E.readWeapon(rom)
  t.items = E.readItems(rom)
  t.drops = E.readDrops(rom)
  -- round 16: people (overworld sprite lists, townsfolk draw tables)
  t.npc = require("src.zelda.alttp.Npc").extract(rom, R, check)
  t.desert = require("src.zelda.alttp.Desert").extract(rom, R, check)   -- r23
  t.dpal = require("src.zelda.alttp.DesertPalace").extract(rom, R, check)   -- r24
  t.owe = require("src.zelda.alttp.OwEnemies").extract(rom, R, check)   -- r25
  t.oldman = require("src.zelda.alttp.OldMan").extract(rom, R, check)   -- r25
  require("src.zelda.alttp.ExtractA26").extract(t, rom, R, check)   -- r26a: Dark World, gear, items (team A)
  t.d26 = require("src.zelda.alttp.Dungeons26").extract(rom, R, check)   -- r26b: the later palaces (team B)
  require("src.zelda.alttp.ExtractA27").extract(t, rom, R, check)   -- r27a: world, items, people, sound (team A)
  return t
end

-- round 9: the drop tables (RomMap.drops)
function E.readDrops(rom)
  local D = R.drops
  local n = D.secretCount
  local d = {
    secretItems = rom:bytesU8(D.secretItems, n), secretFlag = rom:bytesU8(D.secretFlag, n),
    secretXLo = rom:bytesU8(D.secretXLo, n), secretIgnore = rom:bytesU8(D.secretIgnore, n),
    secretZVel = rom:bytesU8(D.secretZVel, n),
    substArea = rom:bytesU8(D.substArea, 64), substSecret = rom:bytesU8(D.substSecret, 16),
    substMask = rom:bytesU8(D.substMask, 16),
    prizeItems = rom:bytesU8(D.prizeItems, 56), prizeZ = rom:bytesU8(D.prizeZ, 15),
    absorbKind = rom:bytesU8(D.absorbKind, 15), absorbNum = rom:bytesU8(D.absorbNum, 19),
    numX = {}, numY = {}, numChar = rom:bytesU8(D.numChar, 18), numExt = rom:bytesU8(D.numExt, 18),
  }
  d.debrisX, d.debrisY = {}, {}
  for i = 0, 63 do
    local x = rom:u16(D.debrisX + 2 * i)
    d.debrisX[i + 1] = x >= 0x8000 and x - 0x10000 or x
    d.debrisY[i + 1] = rom:s8(D.debrisY + i)
  end
  d.debrisChar, d.debrisFlags = rom:bytesU8(D.debrisChar, 64), rom:bytesU8(D.debrisFlags, 64)
  d.kindFlags = rom:bytesU8(D.kindFlags, 12)
  for i = 0, 17 do
    local x, y = rom:u16(D.numX + 2 * i), rom:u16(D.numY + 2 * i)
    d.numX[i + 1] = x >= 0x8000 and x - 0x10000 or x
    d.numY[i + 1] = y >= 0x8000 and y - 0x10000 or y
  end
  -- structural: the last secret item is "none", the absorbables are 0xD8+
  check(d.secretItems[n] == 0 and d.secretItems[1] >= 0xD8, "secret item table")
  for _, v in ipairs(d.prizeItems) do check(v >= 0xD8 and v <= 0xE6, "prize item %X", v) end
  for _, v in ipairs(d.substSecret) do check(v >= 1 and v <= n, "substituted secret %d", v) end
  return d
end

-- bug round: Link's sword/shield tables (RomMap.weapon)
function E.readWeapon(rom)
  local W = R.weapon
  local n = W.poseCount
  local function s8s(o, k) local out = {} for i = 0, k - 1 do out[i + 1] = rom:s8(o + i) end return out end
  local w = {
    swordSel = rom:bytesU8(W.swordSel, n), shieldSel = rom:bytesU8(W.shieldSel, n),
    swordY = s8s(W.swordY, n), swordX = s8s(W.swordX, n),
    shieldY = s8s(W.shieldY, n), shieldX = s8s(W.shieldX, n),
    spriteLocs = rom:bytesU8(W.spriteLocs, n),
    swordTiles = rom:bytesU16(W.swordTiles, W.swordSelCount * 3), shieldTiles = rom:bytesU16(W.shieldTiles, 54),
    swordSize = rom:bytesU8(W.swordSize, W.swordSelCount), swordDmaSel = rom:bytesU8(W.swordDmaSel, W.swordSelCount),
    shieldDmaSel = rom:bytesU8(W.shieldDmaSel, 18),
    swordOamIdx = rom:bytesU8(W.swordOamIdx, 12), bodyOamIdx = rom:bytesU8(W.bodyOamIdx, 12),
    shieldOamIdx = rom:bytesU8(W.shieldOamIdx, 12),
    swordDma = rom:bytesU16(W.swordDma, 8), shieldDma = rom:bytesU16(W.shieldDma, 3),
    stripBase = W.stripBase,
    uncleDma3 = rom:bytesU8(W.uncleDma3, 8), uncleDma4 = rom:bytesU8(W.uncleDma4, 8),
  }
  -- structural checks: the first sword OAM words are chars 5/6 in palette 5,
  -- the DMA sources sit in the strip, the shield's first word is char 7
  check(band(w.swordTiles[1], 0x1FF) == 5 and band(w.swordTiles[2], 0x1FF) == 6, "sword tile data")
  check(band(w.shieldTiles[1], 0x1FF) == 7, "shield tile data")
  check(w.swordDma[1] == W.stripBase and w.shieldDma[1] == W.stripBase + 0x300, "weapon strip DMA sources")
  for _, v in ipairs(w.spriteLocs) do check(v < 12, "sprite loc %d", v) end
  for _, v in ipairs(w.swordSel) do check(v == 0xFF or v < W.swordSelCount, "sword selector %d", v) end
  return w
end

-- bug round: chest pictures, item messages, the pot's floor
function E.readItems(rom)
  local it = {
    chestClosed = rom:bytesU16(R.chestTiles, 4), chestOpen = rom:bytesU16(R.chestTiles + 8, 4),
    bigChestOpen = rom:bytesU16(R.bigChestOpen, 12),
    receiptMsgs = rom:bytesU16(R.receiptMsgs, R.receiptCount),
    potHole = {},
  }
  for k = 1, 4 do it.potHole[k] = rom:u32(R.potHole[k]) end
  -- round 11: the cucco's hop velocities (two s8 tables of 16)
  it.cuccoVel = {}
  for k = 0, 31 do
    local v = rom:u8(R.cuccoVel + k)
    it.cuccoVel[k + 1] = v >= 128 and v - 256 or v
  end
  check(it.cuccoVel[1] == 0 and it.cuccoVel[5] == 16 and it.cuccoVel[17] == -16, "cucco velocities")
  check(it.chestClosed[3] == it.chestClosed[1] + 0x400 and it.chestOpen[1] == it.chestClosed[1] + 1,
        "chest tiles")
  check(it.receiptMsgs[1] == 0xFFFF and it.receiptMsgs[0x12 + 1] > 15, "receipt messages")
  for k = 1, 4 do check(it.potHole[k] < 0x10000, "pot floor word") end
  check(it.potHole[3] == it.potHole[1] + 0x400, "pot floor words")
  return it
end

function E.readPalette(rom)
  local parts = {}
  for i = 0, R.palBlobColors - 1 do
    local c = rom:u16(R.palBlob + i * 2)
    check(c < 0x8000, "palette word %d = %04X", i, c)
  end
  parts[1] = rom:sub(R.palBlob, R.palBlobColors * 2)
  return table.concat(parts)
end

function E.readSheets(rom, tick)
  local out = {}
  local blank = string.rep("\0", E.SHEET_BYTES)
  for i = 0, R.gfxSheetCount - 1 do
    local p = rom:ptr(R.gfxSheets + i * 4)
    check(p, "sheet %d pointer", i)
    local data
    if rom:u8(p) == 0x10 then
      local why
      data, why = rom:lz77(p)
      check(data, "sheet %d: %s", i, tostring(why))
    else
      -- the slots the SNES left unused all point at one raw block (Link's
      -- sheet); keep them blank rather than aliasing it
      data = blank
    end
    out[#out + 1] = (data .. blank):sub(1, E.SHEET_BYTES)
    if tick then tick(i + 1, R.gfxSheetCount) end
  end
  return table.concat(out)
end

function E.readLink(rom)
  return rom:sub(R.linkGfx, R.linkGfxBytes)
end

function E.readMaps(rom, tick)
  local byOffset, blobs, idx = {}, {}, { bg2 = {}, bg1 = {} }
  local total = R.owScreens * 2
  local done = 0
  for _, layer in ipairs({ { "bg2", R.owBgMap }, { "bg1", R.owBg1Map } }) do
    for s = 0, R.owScreens - 1 do
      local p = rom:ptr(layer[2] + s * 4)
      check(p, "%s map pointer for screen %02X", layer[1], s)
      local n = byOffset[p]
      if not n then
        local data, why = rom:lz77(p)
        check(data and #data == E.MAP_BYTES, "%s map %02X: %s", layer[1], s,
              tostring(why or (data and #data)))
        blobs[#blobs + 1] = data
        n = #blobs
        byOffset[p] = n
      end
      idx[layer[1]][s + 1] = n - 1
      done = done + 1
      if tick then tick(done, total) end
    end
  end
  return table.concat(blobs), idx
end

-- The M4A image: every song's tracks walked with the same walker the synth
-- uses, every voicegroup to its highest voice, every sample by its own length;
-- one span of the cartridge that covers all of it.
function E.readMusic(rom)
  local M4A = require("src.core.M4ASynth")
  local function read(o)
    if not o or o < 0 or o >= rom.size then return nil end
    return sbyte(rom.data, o + 1)
  end
  local function ptrAt(o)
    if not o or o < 0 or o + 4 > rom.size then return nil end
    return rom:ptr(o)
  end
  local songs = {}
  local lo, hi
  local function cover(a, b)
    if not (a and b) or b <= a then return end
    lo = (lo and lo < a) and lo or a
    hi = (hi and hi > b) and hi or b
  end
  local topVoice = {}
  for i = 0, R.songCount - 1 do
    local header = rom:ptr(R.songTable + i * 8)
    check(header, "song %d header pointer", i)
    local count = rom:u8(header)
    local row = { index = i, trackCount = count, priority = rom:u8(header + 2),
                  reverb = rom:u8(header + 3), player = rom:u16(R.songTable + i * 8 + 4) }
    if count > 0 then
      row.voicegroup = rom:ptr(header + 4)
      row.tracks = {}
      for k = 1, count do
        local tr = rom:ptr(header + 4 + k * 4)
        check(tr, "song %d track %d pointer", i, k)
        row.tracks[k] = tr
        local last = tr
        local ok, at, why = M4A.walk(read, tr, function(_, cmd, argsAt, nxt)
          if nxt > last then last = nxt end
          if cmd == 0xBD and row.voicegroup then
            local v = read(argsAt)
            if v and v > (topVoice[row.voicegroup] or -1) then topVoice[row.voicegroup] = v end
          end
        end, ptrAt)
        check(ok, "song %d track %d does not walk (%s at %06X)", i, k, tostring(why), at or 0)
        cover(tr, last)
      end
    end
    songs[i + 1] = row
  end
  local seen, waves = {}, {}
  local function group(at, slots)
    if not at or seen[at] then return end
    seen[at] = true
    cover(at, at + slots * 12)
    for v = 0, slots - 1 do
      local o = at + v * 12
      local kind, wav = read(o), ptrAt(o + 4)
      if kind and wav then
        if kind == 0x40 or kind == 0x80 then
          group(wav, 128)
          local split = ptrAt(o + 8)
          if split then cover(split, split + 128) end
        elseif kind % 8 == 0 then
          waves[wav] = true
        end
      end
    end
  end
  for _, s in ipairs(songs) do
    if s.voicegroup then group(s.voicegroup, math.min(128, (topVoice[s.voicegroup] or 0) + 1)) end
  end
  for wav in pairs(waves) do
    local size = (wav + 16 <= rom.size) and rom:u32(wav + 12) or 0
    if size > 0 and size < 4 * 1024 * 1024 and wav + 16 + size <= rom.size then
      cover(wav, wav + 16 + size)
    end
  end
  check(lo and hi, "no music found")
  return rom:sub(lo, hi - lo), { base = lo, songs = songs }
end

-- Interior room maps: the BG2 and BG1 tables, unique maps stored once.
-- The stair objects of a room's object list (SNES room data, 3 bytes an
-- object; on the GBA each of the 3 layers ends with the word 0xFFF0, then
-- its door words up to 0xFFFF). Returns { { id, pos }, ... } in list order:
-- id = 0x100 + subtype-2 id (0x2D-0x2F floor stairs, 0x38-0x3B wall
-- spiral stairs) or 0x200 + subtype-3 id (0x1E-0x21 straight stairs), pos =
-- the object's map8 cell (y * 64 + x), as RoomData_DrawObject decodes it.
local STAIR2 = { [0x2D] = true, [0x2E] = true, [0x2F] = true, [0x38] = true, [0x39] = true,
                 [0x3A] = true, [0x3B] = true }
local STAIR3 = { [0x1E] = true, [0x1F] = true, [0x20] = true, [0x21] = true, [0x29] = true }
function E.roomStairs(rom, p)
  local out, o = {}, p + 2
  for _ = 1, 3 do
    for _ = 1, 400 do
      local b0, b1, b2 = rom:u8(o), rom:u8(o + 1), rom:u8(o + 2)
      if b0 == 0xF0 and b1 == 0xFF then o = o + 2 break end
      if b0 == 0xFF and b1 == 0xFF then o = o + 2 break end
      o = o + 3
      if bit.band(b0, 0xFC) == 0xFC then
        local id = bit.band(b2, 0x3F)
        local x = bit.lshift(bit.band(b0, 3), 4) + bit.rshift(b1, 4)
        local y = bit.lshift(bit.band(b1, 15), 2) + bit.rshift(b2, 6)
        if STAIR2[id] then out[#out + 1] = { 0x100 + id, y * 64 + x } end
      elseif b2 >= 0xF8 then
        local id = bit.lshift(bit.band(b2, 7), 4) + bit.lshift(bit.band(b1, 3), 2) + bit.band(b0, 3)
        if STAIR3[id] then out[#out + 1] = { 0x200 + id, bit.rshift(b1, 2) * 64 + bit.rshift(b0, 2) } end
      end
    end
    -- the layer's door words
    for _ = 1, 64 do
      local w = rom:u16(o)
      o = o + 2
      if w == 0xFFFF then break end
    end
  end
  return out
end

-- Round 6: the objects the runtime acts on (SNES room data): in-room stairs
-- (subtype 2 0x31/0x32 north, subtype 3 0x1B/0x1C/0x1D south), chests
-- (subtype 3 0x19, big 0x31), the cell lock (0x18), the throne-room stairs
-- down (0x29 lower); { s = 2|3, id, x, y (map8 cells), layer 1-3 }
local SPECIAL2 = { [0x31] = true, [0x32] = true }
local SPECIAL3 = { [0x1B] = true, [0x1C] = true, [0x1D] = true, [0x19] = true, [0x31] = true,
                   [0x18] = true, [0x17] = true, [0x29] = true,
                   [0x2F] = true,    -- bug round: 0x2F the pot (RoomDraw_SinglePot)
                   -- round 16 (RoomObjects.lua): rupee floor, large pick-up
                   -- block, bomb floor, Blind's floor light
                   [0x12] = true, [0x2C] = true, [0x47] = true, [0x71] = true }
function E.roomSpecials(rom, p)
  local out, o = {}, p + 2
  for layer = 1, 3 do
    for _ = 1, 400 do
      local b0, b1, b2 = rom:u8(o), rom:u8(o + 1), rom:u8(o + 2)
      if b0 == 0xF0 and b1 == 0xFF then o = o + 2 break end
      if b0 == 0xFF and b1 == 0xFF then o = o + 2 break end
      o = o + 3
      if bit.band(b0, 0xFC) == 0xFC then
        local id = bit.band(b2, 0x3F)
        if SPECIAL2[id] then
          out[#out + 1] = { s = 2, id = id, layer = layer,
                            x = bit.lshift(bit.band(b0, 3), 4) + bit.rshift(b1, 4),
                            y = bit.lshift(bit.band(b1, 15), 2) + bit.rshift(b2, 6) }
        end
      elseif b2 >= 0xF8 then
        local id = bit.lshift(bit.band(b2, 7), 4) + bit.lshift(bit.band(b1, 3), 2) + bit.band(b0, 3)
        if SPECIAL3[id] then
          out[#out + 1] = { s = 3, id = id, layer = layer, x = bit.rshift(b0, 2), y = bit.rshift(b1, 2) }
        end
      end
    end
    for _ = 1, 64 do
      local w = rom:u16(o)
      o = o + 2
      if w == 0xFFFF then break end
    end
  end
  return out
end

-- Round 6: a room's sprite list (RomMap.roomSprites, SNES Dungeon_LoadSprites):
-- { type, x, y (room pixels), lower (floor bit), sub, drop = 1 small key /
-- 2 big key }; overlords are skipped.
function E.roomSprites(rom, p, room)
  local out = {}
  local o = p + 1
  for _ = 1, 64 do
    local y, x, t = rom:u8(o), rom:u8(o + 1), rom:u8(o + 2)
    if y == 0xFF then break end
    o = o + 3
    if t == 0xE4 and (y == 0xFE or y == 0xFD) then
      if out[#out] then out[#out].drop = (y == 0xFE) and 1 or 2 end
    elseif x < 0xE0 then
      out[#out + 1] = { type = t, x = bit.band(x, 0x1F) * 16, y = bit.band(y, 0x1F) * 16,
                        lower = y >= 0x80,
                        sub = bit.rshift(bit.band(y, 0x60), 2) + bit.rshift(x, 5) }
    end
  end
  return out
end

-- round 17: the overlords of a room's sprite list (x >= 0xE0; SNES
-- Dungeon_LoadSingleOverlord: x, y = (byte << 4) & 0x1FF, floor = y >> 7)
function E.roomOverlords(rom, p)
  local out = {}
  local o = p + 1
  for _ = 1, 64 do
    local y, x, t = rom:u8(o), rom:u8(o + 1), rom:u8(o + 2)
    if y == 0xFF then break end
    o = o + 3
    if not (t == 0xE4 and (y == 0xFE or y == 0xFD)) and x >= 0xE0 then
      out[#out + 1] = { type = t, x = bit.band(x, 0x1F) * 16, y = bit.band(y, 0x1F) * 16, lower = y >= 0x80 }
    end
  end
  return out
end

function E.readRooms(rom, tick)
  local byOffset, blobs, idx = {}, {}, { bg2 = {}, bg1 = {}, bg3 = {} }
  -- round 5: the third layer too (the lower floor of two-level rooms)
  for li, layer in ipairs({ { "bg2", R.roomBg2 }, { "bg1", R.roomBg1 }, { "bg3", R.roomBg3 } }) do
    for r = 0, R.roomCount - 1 do
      local p = rom:ptr(layer[2] + r * 4)
      check(p, "room %03X %s pointer", r, layer[1])
      local n = byOffset[p]
      if not n then
        local data, why = rom:lz77(p)
        check(data and #data == E.MAP_BYTES, "room %03X %s: %s", r, layer[1], tostring(why))
        blobs[#blobs + 1] = data
        n = #blobs
        byOffset[p] = n
      end
      idx[layer[1]][r + 1] = n - 1
      if tick and r % 32 == 0 then tick((li - 1) * R.roomCount + r, 3 * R.roomCount) end
    end
  end
  idx.dungPal = rom:bytesU16(R.dungPalIndex, R.dungPalCount)
  -- room headers, palette sets, entrances, tile attributes (RomMap round 4)
  idx.headers = {}
  for r = 0, R.roomCount - 1 do
    local p = rom:ptr(R.roomHeader + r * 4)
    check(p, "room %03X header pointer", r)
    idx.headers[r + 1] = rom:bytesU8(p, R.roomHeaderLen)
  end
  idx.palSets = rom:bytesU8(R.roomPalSets, R.roomPalSetCount * 4)
  idx.entrances = {}
  for i = 0, R.entranceCount - 1 do
    local o = R.entrances + i * R.entranceLen
    idx.entrances[i + 1] = { room = rom:u16(o), y = rom:u16(o + 0x16),
                             x = rom:u16(o + 0x18), main = rom:u8(o + 0x1E) }
  end
  -- room door lists and the door position tables (RomMap round 4b)
  idx.doors = {}
  for r = 0, R.roomCount - 1 do
    local p = rom:ptr(R.roomDoors + r * 4)
    check(p, "room %03X door list pointer", r)
    local list = {}
    for k = 0, 31 do
      local w = rom:u16(p + k * 2)
      if w == 0xFFFF then break end
      list[#list + 1] = w
    end
    check(#list < 32, "room %03X door list does not end", r)
    idx.doors[r + 1] = list
  end
  idx.doorPosUp = rom:bytesU16(R.doorPosUp, 12)
  idx.doorPosDown = rom:bytesU16(R.doorPosDown, 12)
  idx.doorPosLeft = rom:bytesU16(R.doorPosLeft, 12)
  idx.doorPosRight = rom:bytesU16(R.doorPosRight, 12)
  -- round 11: the doorway attributes by door type (kTileAttrsByDoor)
  idx.doorAttrs = rom:bytesU16(R.doorAttrsByType, 40)
  check(idx.doorAttrs[1] == 0x8080 and idx.doorAttrs[6] == 0x8E8E and idx.doorAttrs[36] == 0x8888,
        "door attribute table")
  -- round 11: door pictures (12 map words a type and direction) and the
  -- opened-door type remap
  idx.doorTiles, idx.doorRemap = {}, rom:bytesU16(R.doorRemap, 40)
  for dir, spec in ipairs({ { R.doorTilesN, 52 }, { R.doorTilesS, 48 }, { R.doorTilesW, 48 }, { R.doorTilesE, 47 } }) do
    local t = {}
    for i = 0, spec[2] - 1 do
      local p = rom:ptr(spec[1] + i * 4)
      check(p ~= nil, "door picture pointer %d/%d", dir, i)
      t[i + 1] = rom:bytesU16(p, 12)
    end
    idx.doorTiles[dir - 1] = t
  end
  check(idx.doorRemap[15] == 0x50 and idx.doorRemap[35] == 0x58, "door type remap")
  -- overworld doors -> entrance numbers (RomMap round 4b)
  idx.owDoorTab0 = rom:bytesU16(R.owDoorTab0, R.owDoorTabCount)
  idx.owDoorTab1 = rom:bytesU16(R.owDoorTab1, R.owDoorTabCount)
  idx.owEntArea = rom:bytesU16(R.owEntArea, R.owEntCount)
  idx.owEntPos = rom:bytesU16(R.owEntPos, R.owEntCount)
  idx.owEntId = rom:bytesU8(R.owEntId, R.owEntCount)
  check(idx.owEntArea[1] < 0x80 and idx.owEntId[1] < R.entranceCount, "overworld entrance table")
  -- room layouts (object list byte 1), the quadrant flag table and the
  -- exit table (RomMap round 5)
  idx.layout, idx.stairs = {}, {}
  for r = 0, R.roomCount - 1 do
    local p = rom:ptr(R.roomObjects + r * 4)
    check(p, "room %03X object list pointer", r)
    idx.layout[r + 1] = rom:u8(p + 1)
    idx.stairs[r + 1] = E.roomStairs(rom, p)
  end
  -- round 6: special objects, sprite lists, chests, entrance planes
  idx.specials, idx.sprites = {}, {}
  for r = 0, R.roomCount - 1 do
    idx.specials[r + 1] = E.roomSpecials(rom, rom:ptr(R.roomObjects + r * 4))
    idx.sprites[r + 1] = E.roomSprites(rom, rom:ptr(R.roomSprites + r * 4), r)
  end
  check(#idx.sprites[0x55 + 1] >= 1 and idx.sprites[0x55 + 1][1].type == 0x73, "room sprite lists")
  -- round 16: the objects the GBA draws over its pre-rendered maps
  idx.roomObj = require("src.zelda.alttp.RoomObjects").extract(rom, R, check)
  -- round 17: overlords (cannons, the Armos coordinator) and the Eastern
  -- Palace's sprite tables (Palace.lua)
  idx.overlords = {}
  for r = 0, R.roomCount - 1 do
    idx.overlords[r + 1] = E.roomOverlords(rom, rom:ptr(R.roomSprites + r * 4))
  end
  idx.palace = require("src.zelda.alttp.Palace").extract(rom, R, check)
  -- round 18: the items' tables (Items.lua: bow, bombs, lamp, torches, damage)
  idx.items = require("src.zelda.alttp.Items").extract(rom, R, check)
  idx.chests = {}
  for i = 0, R.chestCount - 1 do
    local o = R.chests + i * 3
    local w = rom:u16(o)
    idx.chests[i + 1] = { room = bit.band(w, 0x7FFF), big = w >= 0x8000, item = rom:u8(o + 2) }
  end
  check(idx.chests[3].room == 0x71, "chest table")
  -- bug round: dungeon secrets (SNES kDungeonSecrets; RevealPotItem): per
  -- room { pos = tilemap position * 2 (+0x2000 lower layer), item }
  idx.secrets = {}
  for r = 0, R.roomCount - 1 do
    local p = rom:ptr(R.dungeonSecrets + r * 4)
    local list = {}
    if p then
      for _ = 1, 64 do
        local pos = rom:u16(p)
        if pos == 0xFFFF then break end
        list[#list + 1] = { pos = pos, item = rom:u8(p + 2) }
        p = p + 3
      end
    end
    idx.secrets[r + 1] = list
  end
  for i = 0, R.entranceCount - 1 do
    local o = R.entrances + i * R.entranceLen
    idx.entrances[i + 1].plane = rom:u8(o + 0x22)
    idx.entrances[i + 1].palace = rom:u8(o + 0x20)
  end
  idx.holes = {}
  for i = 0, 31 do
    local a = rom:u16(R.holeAreas + i * 2)
    if a == 0xFFFF then break end
    idx.holes[i + 1] = { area = a, ent = rom:u8(R.holeEntrances + i),
                         keys = rom:bytesU16(R.holeKeys + i * 16, 8) }
  end
  check(#idx.holes >= 8, "hole table")
  -- the map16 tiles that change at run time (SNES Overworld_ToolAndTileInteraction:
  -- bush 0x36 -> 0xDC7, 0x72A -> 0xDC8, 0x20F/0x239 -> 0xDCA, 0x101 -> 0xDC6;
  -- RevealSecret: 0xDCC hole, 0x212, 0xDB4), 4 map8 words each
  idx.map16 = {}
  -- round 17: + 0xDBA-0xDBD (the opened big door, Module09_0C_OpenBigDoor's
  -- last frame; the castle gate never redrew without them)
  for _, m in ipairs({ 0x36, 0x101, 0x20F, 0x239, 0x72A, 0xDC6, 0xDC7, 0xDC8, 0xDCA, 0xDCC, 0x212, 0xDB4,
                       0xDBA, 0xDBB, 0xDBC, 0xDBD,
                       -- r21: the big rock piles and what a dash leaves of them
                       -- (SmashRockPile_fromLift: kDoorAnimTiles[20..23] / [40..43])
                       0x226, 0x227, 0x228, 0x229, 0xDCD, 0xDCE, 0xDCF, 0xDD0,
                       0x918, 0x919, 0x91A, 0x91B,
                       -- r25: the big rocks (Overworld_HandleLiftableTiles: light, heavy; BigRock.lua)
                       0x36D, 0x36E, 0x374, 0x375, 0x23B, 0x23C, 0x23D, 0x23E }) do
    idx.map16[m] = rom:bytesU16(R.map16 + m * 8, 4)
  end
  check(idx.map16[0x36][1] == 0x6180, "map16 table")
  idx.owSecrets = {}
  for i = 0, R.owSecretCount - 1 do
    local p = rom:ptr(R.owSecrets + i * 4)
    local list = {}
    for k = 0, 63 do
      local pos = rom:u16(p + k * 4)
      if pos == 0xFFFF then break end
      list[#list + 1] = { pos = bit.band(pos, 0x7FFF), type = rom:u8(p + k * 4 + 2) }
    end
    idx.owSecrets[i + 1] = list
  end
  local C = R.combat
  local function s8s(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
  local function s16s(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
  idx.combat = {
    health = rom:bytesU8(C.health, C.spriteTypes), bump = rom:bytesU8(C.bump, C.spriteTypes),
    flags4 = rom:bytesU8(C.flags4, C.spriteTypes),
    hitXLo = s8s(rom:bytesU8(C.hitXLo, 32)), hitXHi = s8s(rom:bytesU8(C.hitXHi, 32)), hitXSize = rom:bytesU8(C.hitXSize, 32),
    hitYLo = s8s(rom:bytesU8(C.hitYLo, 32)), hitYHi = s8s(rom:bytesU8(C.hitYHi, 32)), hitYSize = rom:bytesU8(C.hitYSize, 32),
    playerDamage = rom:bytesU8(C.playerDamage, 30), enemyDamage = rom:bytesU8(C.enemyDamage, 128),
    swordX = s8s(rom:bytesU8(C.swordX, 65)), swordW = rom:bytesU8(C.swordW, 65),
    swordY = s8s(rom:bytesU8(C.swordY, 65)), swordH = rom:bytesU8(C.swordH, 65),
    swordTab4 = rom:bytesU8(C.swordTab4, 13), swordDelays = rom:bytesU8(C.swordDelays, 18),
    swordClass = rom:bytesU8(C.swordClass, 12), spinGfx = rom:bytesU8(C.spinGfx, 48),
    spinDelays = rom:bytesU8(C.spinDelays, 12),
    actTileX = s16s(rom:bytesU16(C.actTileX, 4)), actTileY = s16s(rom:bytesU16(C.actTileY, 4)),
    swordOamY = s8s(rom:bytesU8(C.swordOamY, C.swordOamCount)), swordOamX = s8s(rom:bytesU8(C.swordOamX, C.swordOamCount)),
    recoilMasks = rom:bytesU8(C.recoilMasks, 6),
    throwChar = rom:bytesU8(C.throwChar, 12), throwFlags = rom:bytesU8(C.throwFlags, 6),
    -- round 13: the guards' AI and the sprite tile collision (RomMap.combat)
    guardTowardsX = s8s(rom:bytesU8(C.guardTowardsX, 4)), guardTowardsY = s8s(rom:bytesU8(C.guardTowardsY, 4)),
    guardXvel = s8s(rom:bytesU8(C.guardXvel, 4)), guardYvel = s8s(rom:bytesU8(C.guardYvel, 4)),
    guardDelay = rom:bytesU8(C.guardDelay, 4), probeStagger = rom:bytesU8(C.probeStagger, 4),
    probeXvel = s8s(rom:bytesU8(C.probeXvel, 64)), probeYvel = s8s(rom:bytesU8(C.probeYvel, 64)),
    sprTileSolid = s8s(rom:bytesU8(C.sprTileSolid, 256)), sprSimple = rom:bytesU8(C.sprSimple, 256),
    flags5 = rom:bytesU8(C.flags5, C.spriteTypes), deflBits = rom:bytesU8(C.deflBits, C.spriteTypes),
    prizeMasks = rom:bytesU8(C.prizeMasks, 7),
    sprPointX = s16s(rom:bytesU16(C.sprPointX, 54)), sprPointY = s16s(rom:bytesU16(C.sprPointY, 54)),
    parryF = rom:bytesU8(C.parryF, 8), parryLink = rom:bytesU8(C.parryLink, 8),
    recruitXvel = s8s(rom:bytesU8(C.recruitXvel, 8)), recruitYvel = s8s(rom:bytesU8(C.recruitYvel, 8)),
    recruitHeadDir = rom:bytesU8(C.recruitHeadDir, 8),
  }
  for i = 1, 8 do
    check(math.abs(idx.combat.recruitXvel[i]) < 32 and math.abs(idx.combat.recruitYvel[i]) < 32
          and idx.combat.recruitHeadDir[i] < 4, "knife guard tables")
  end
  for i = 1, 8 do
    check(idx.combat.parryF[i] > 0 and idx.combat.parryF[i] < 64 and idx.combat.parryLink[i] > 0
          and idx.combat.parryLink[i] < 64, "parry tables")
  end
  check(idx.combat.guardXvel[1] == 8 and idx.combat.guardDelay[3] == 0xFF and idx.combat.probeXvel[1] == -16
        and idx.combat.probeYvel[17] == 16 and idx.combat.sprTileSolid[0x1E + 1] == 1
        and idx.combat.flags5[0x41 + 1] == 0x91 and idx.combat.prizeMasks[4] == 0
        and idx.combat.sprSimple[0x1E + 1] == 3 and idx.combat.sprSimple[0x0A + 1] == 3
        and idx.combat.sprPointX[25] == 8 and idx.combat.sprPointY[26] == 16, "guard AI tables")
  check(idx.combat.playerDamage[1] == 2 and idx.combat.swordDelays[6] == 3, "combat tables")
  -- r20: the sword's damage classes and the spin attack (RomMap.combat)
  check(idx.combat.swordClass[1] == 1 and idx.combat.swordClass[5] == 2 and idx.combat.swordClass[9] == 1
        and idx.combat.spinDelays[2] == 5 and idx.combat.spinDelays[12] == 5 and idx.combat.spinGfx[1] == 10
        and idx.combat.spinGfx[48] == 14, "sword class / spin tables")
  check(idx.combat.actTileX[3] == -3 and idx.combat.actTileY[2] == 24, "action tile offsets")
  -- round 16: the ball-and-chain guard 0x6A (BallChain.lua)
  idx.combat.flail = require("src.zelda.alttp.BallChain").extract(rom, R, check)
  -- r21: the death puff, the dash dust, the item strip's DMA (Effects.lua)
  idx.combat.fx = require("src.zelda.alttp.Effects").extract(rom, check)
  check(idx.combat.recoilMasks[5] == 0x0C, "recoil masks")
  check(idx.combat.throwChar[3] == 0x86 and idx.combat.throwFlags[1] == 0x0C, "thrown object tables")
  idx.quadFlags = rom:bytesU8(R.layoutQuadFlags, 32)
  check(idx.quadFlags[1] == 0x0F and idx.quadFlags[32] == 0x05, "layout quadrant flags")
  local n = R.exitCount
  idx.exits = { rooms = rom:bytesU16(R.exitRooms, n), screens = rom:bytesU8(R.exitScreens, n) }
  for k, name in ipairs({ "loadOff", "scrollY", "scrollX", "y", "x", "camY", "camX" }) do
    idx.exits[name] = rom:bytesU16(R.exitArrays + (k - 1) * n * 2, n)
  end
  check(idx.exits.rooms[1] == 0x104 and idx.exits.screens[1] == 0x2C, "exit table")
  -- round 12: the exits' door words and the starting points (RomMap)
  idx.exits.normalDoor = rom:bytesU16(R.exitNormalDoor, n)
  idx.exits.fancyDoor = rom:bytesU16(R.exitFancyDoor, n)
  check(idx.exits.normalDoor[1] == 0x816 and idx.exits.fancyDoor[4] == 0x87BE, "exit doors")
  idx.startPoints = {}
  for i = 0, R.startPointCount - 1 do
    local o = R.startPoints + i * R.entranceLen
    idx.startPoints[i + 1] = { room = rom:u16(o), y = rom:u16(o + 0x16), x = rom:u16(o + 0x18),
                               main = rom:u8(o + 0x1E), palace = rom:u8(o + 0x20),
                               plane = rom:u8(o + 0x22), startPoint = i }
  end
  check(idx.startPoints[3].room == 0x80 and idx.startPoints[2].room == 0x12, "starting points")
  idx.attrBase = rom:bytesU8(R.dungAttrBase, 0x140)
  idx.attrTail = rom:bytesU8(R.dungAttrTail, 0x40)
  idx.attrAux = {}
  for a = 0, R.dungAttrAuxCount - 1 do
    local p = rom:ptr(R.dungAttrAux + a * 4)
    check(p, "attribute set %d pointer", a)
    idx.attrAux[a + 1] = rom:bytesU8(p, 0x80)
  end
  return table.concat(blobs), idx
end

-- ------------------------------------------------------------- driver

-- cache: anything with write(rel, data) / read(rel) / exists(rel)
function E.run(bytes, cache, progress, opts)
  opts = opts or {}
  progress = progress or function() end
  local rom = E.rom(bytes)
  check(rom.size == R.SIZE, "this is not the 8 MiB AZLE cartridge (%d bytes)", rom.size)
  check(E.detect(rom:sub(0, 0x200)), "header game code is not %s", R.GAME_CODE)

  local weights = { tables = 0.04, palette = 0.02, sheets = 0.24, link = 0.02,
                    maps = 0.19, music = 0.15, fs = 0.18, rooms = 0.10, ui = 0.02, sprites = 0.02, menus = 0.01, front = 0.01 }
  local base = 0
  local function stage(name, label, fn)
    local w = weights[name]
    if not opts.force and cache:exists(stampPath(name)) then
      base = base + w
      progress(base, label .. " (kept)")
      return
    end
    progress(base, label)
    fn(function(i, n) progress(base + w * (i / n), label) end)
    assert(cache:write(stampPath(name), "ok"))
    base = base + w
    if opts.checkpoint then opts.checkpoint(name) end
  end

  stage("tables", "Reading the tables", function()
    assert(cache:write(E.FILES.tables, S.encode(E.readTables(rom))))
  end)
  stage("palette", "Reading the palettes", function()
    assert(cache:write(E.FILES.palette, E.readPalette(rom)))
  end)
  stage("sheets", "Decoding graphics", function(tick)
    assert(cache:write(E.FILES.sheets, E.readSheets(rom, tick)))
  end)
  stage("link", "Reading Link", function()
    assert(cache:write(E.FILES.link, E.readLink(rom)))
  end)
  stage("maps", "Decoding Hyrule", function(tick)
    local blob, idx = E.readMaps(rom, tick)
    assert(cache:write(E.FILES.maps, blob))
    assert(cache:write(E.FILES.mapsIdx, S.encode(idx)))
  end)
  stage("music", "Reading the music", function()
    local image, info = E.readMusic(rom)
    assert(cache:write(E.FILES.music, image))
    assert(cache:write(E.FILES.songs, S.encode(info)))
  end)
  stage("fs", "Reading Four Swords", function(tick)
    require("src.zelda.alttp.FsExtract").run(rom, cache, tick)
  end)
  stage("rooms", "Reading the interiors", function(tick)
    local blob, idx = E.readRooms(rom, tick)
    assert(cache:write(E.FILES.rooms, blob))
    assert(cache:write(E.FILES.roomsIdx, S.encode(idx)))
  end)
  stage("ui", "Reading the menus", function(tick)
    require("src.zelda.alttp.UiExtract").run(rom, cache, tick)
  end)
  stage("sprites", "Reading the sprites", function(tick)
    require("src.zelda.alttp.SprExtract").run(rom, cache, tick)
  end)
  -- round 8: the menu screens (item menu, maps, file select)
  stage("menus", "Reading the menu screens", function(tick)
    require("src.zelda.alttp.MenuExtract").run(rom, cache, tick)
  end)
  -- round 13: the front end's screens (file / name / game choice)
  stage("front", "Reading the file screens", function(tick)
    require("src.zelda.alttp.FrontExtract").run(rom, cache, tick)
  end)
  progress(1, "Done")
  return true
end

function E.isReady(cache)
  for _, st in ipairs(E.STAGES) do
    if not cache:exists(stampPath(st)) then return false, "stage " .. st .. " missing" end
  end
  for _, rel in pairs(E.FILES) do
    if not cache:exists(rel) then return false, rel .. " missing" end
  end
  for _, rel in ipairs(require("src.zelda.alttp.FsExtract").files()) do
    if not cache:exists(rel) then return false, rel .. " missing" end
  end
  for _, rel in ipairs(require("src.zelda.alttp.SprExtract").files()) do
    if not cache:exists(rel) then return false, rel .. " missing" end
  end
  for _, rel in ipairs(require("src.zelda.alttp.MenuExtract").files()) do
    if not cache:exists(rel) then return false, rel .. " missing" end
  end
  for _, rel in ipairs(require("src.zelda.alttp.UiExtract").files()) do
    if not cache:exists(rel) then return false, rel .. " missing" end
  end
  for _, rel in ipairs(require("src.zelda.alttp.FrontExtract").files()) do
    if not cache:exists(rel) then return false, rel .. " missing" end
  end
  return true
end

return E
