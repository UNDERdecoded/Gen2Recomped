-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The imported ALttP cache, loaded for the runtime: the tables (Lua) and the
-- binary blobs (palette, graphics sheets, Link, overworld tilemaps) as strings
-- with small accessors. Works on any object with read(rel) (a ZeldaCache, or
-- a table-backed fake in tests).

local E = require("src.zelda.alttp.Extract")
local S = require("src.zelda.alttp.Serialize")

local D = {}
D.__index = D

local sbyte = string.byte

local function readLua(cache, rel)
  local src = cache:read(rel)
  assert(type(src) == "string", "ALttP cache is missing " .. rel .. " -- import the ROM again")
  local v, err = S.decode(src)
  assert(v, err)
  return v
end

local function readBin(cache, rel)
  local b = cache:read(rel)
  assert(type(b) == "string", "ALttP cache is missing " .. rel .. " -- import the ROM again")
  return b
end

function D.load(cache)
  local self = setmetatable({}, D)
  self.t = readLua(cache, E.FILES.tables)
  self.mapIdx = readLua(cache, E.FILES.mapsIdx)
  self.pal = readBin(cache, E.FILES.palette)
  self.sheets = readBin(cache, E.FILES.sheets)
  self.link = readBin(cache, E.FILES.link)
  self.maps = readBin(cache, E.FILES.maps)
  local okR, rooms = pcall(readBin, cache, E.FILES.rooms)
  local okI, roomIdx = pcall(readLua, cache, E.FILES.roomsIdx)
  if okR and okI then self.rooms, self.roomIdx = rooms, roomIdx end
  local okS, songs = pcall(readLua, cache, E.FILES.songs)
  self.songs = okS and songs or nil
  -- menus / HUD / title (round 4b); absent in an older cache
  local U = require("src.zelda.alttp.UiExtract")
  local okU, ui = pcall(readLua, cache, U.FILES.info)
  local okC, uiChr = pcall(readBin, cache, U.FILES.chr)
  local okT, title = pcall(readBin, cache, U.FILES.title)
  if okU and okC and okT then self.ui, self.uiChr, self.title = ui, uiChr, title end
  local okX, text = pcall(readBin, cache, U.FILES.text)
  local okF, font = pcall(readBin, cache, U.FILES.font)
  if okX and okF and self.ui then self.text, self.font = text, font end
  -- round 13: the front end's screens; absent in an older cache
  local FX = require("src.zelda.alttp.FrontExtract")
  local okFf, ffile = pcall(readBin, cache, FX.FILES.file)
  local okFg, fgame = pcall(readBin, cache, FX.FILES.game)
  local okFi, finfo = pcall(readLua, cache, FX.FILES.info)
  if okFf and okFg and okFi then self.front = { file = ffile, game = fgame, info = finfo } end
  -- sprite sheets and draw tables (round 7); absent in an older cache
  local SX = require("src.zelda.alttp.SprExtract")
  local okSp, spr = pcall(readBin, cache, SX.FILES.sheets)
  local okSi, sprInfo = pcall(readLua, cache, SX.FILES.info)
  if okSp and okSi then self.spr, self.sprInfo = spr, sprInfo end
  -- the menu screens (round 8); absent in an older cache
  local MX = require("src.zelda.alttp.MenuExtract")
  local okMb, mblob = pcall(readBin, cache, MX.FILES.blob)
  local okMi, minfo = pcall(readLua, cache, MX.FILES.info)
  if okMb and okMi and mblob and minfo then self.menus = MX.open(mblob, minfo) end
  return self
end

-- colour n (0..4095) of the palette blob, BGR555
function D:blobColor(n)
  n = n % 4096
  local a, b = sbyte(self.pal, n * 2 + 1, n * 2 + 2)
  return a + b * 256
end

-- a sheet's 2048 bytes (64 4bpp tiles)
function D:sheet(i)
  local o = i * E.SHEET_BYTES
  return self.sheets:sub(o + 1, o + E.SHEET_BYTES)
end

-- word i (0..4095) of overworld map number n
function D:mapWord(n, i)
  -- round 6: tiles changed at run time (cut bushes) override the map
  local p = self.mapPatch and self.mapPatch[n]
  if p and p[i] then return p[i] end
  local o = n * E.MAP_BYTES + i * 2
  local a, b = sbyte(self.maps, o + 1, o + 2)
  return a + b * 256
end

-- word i (0..4095) of interior room map number n
function D:roomWord(n, i)
  local o = n * E.MAP_BYTES + i * 2
  local a, b = sbyte(self.rooms, o + 1, o + 2)
  return a + b * 256
end

function D:mapNumber(layer, screen)
  return self.mapIdx[layer][screen + 1]
end

return D
