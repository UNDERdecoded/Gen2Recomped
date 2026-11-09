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

E.STAGES = { "tables", "palette", "sheets", "link", "maps", "music", "fs", "rooms", "ui" }
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

  t.speedMod = rom:bytesU8(R.speedMod, 27)
  t.animTab2 = rom:bytesU8(R.animTab2, 16)
  t.animTab3 = rom:bytesU8(R.animTab3, 24)
  return t
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
function E.readRooms(rom, tick)
  local byOffset, blobs, idx = {}, {}, { bg2 = {}, bg1 = {} }
  for li, layer in ipairs({ { "bg2", R.roomBg2 }, { "bg1", R.roomBg1 } }) do
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
      if tick and r % 32 == 0 then tick((li - 1) * R.roomCount + r, 2 * R.roomCount) end
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
  -- overworld doors -> entrance numbers (RomMap round 4b)
  idx.owDoorTab0 = rom:bytesU16(R.owDoorTab0, R.owDoorTabCount)
  idx.owDoorTab1 = rom:bytesU16(R.owDoorTab1, R.owDoorTabCount)
  idx.owEntArea = rom:bytesU16(R.owEntArea, R.owEntCount)
  idx.owEntPos = rom:bytesU16(R.owEntPos, R.owEntCount)
  idx.owEntId = rom:bytesU8(R.owEntId, R.owEntCount)
  check(idx.owEntArea[1] < 0x80 and idx.owEntId[1] < R.entranceCount, "overworld entrance table")
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

  local weights = { tables = 0.04, palette = 0.02, sheets = 0.25, link = 0.02,
                    maps = 0.22, music = 0.15, fs = 0.18, rooms = 0.10, ui = 0.02 }
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
  for _, rel in ipairs(require("src.zelda.alttp.UiExtract").files()) do
    if not cache:exists(rel) then return false, rel .. " missing" end
  end
  return true
end

return E
