-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MENU SCREENS IMPORT (round 8, import stage "menus"). Reads what the GBA's
-- own menu code loads (RomMap.menu and friends) from the player's ROM:
--
--   assets/generated/alttp/menus.bin   the blobs below, back to back
--   data/generated/alttp_menus.lua     { blobs = { name = { off, len } },
--                                        windows = { { lo, hi, off } } }
--
-- A "window" is a run of the cartridge's own word tables kept as they are
-- in the ROM, so the runtime reads them by their ROM address (Menu.lua
-- ports the routines that read them). Nothing here is invented.

local R = require("src.zelda.alttp.RomMap")

local X = {}

X.FILES = {
  blob = "assets/generated/alttp/menus.bin",
  info = "data/generated/alttp_menus.lua",
}

local function check(c, fmt, ...)
  if not c then error("ALttP import (menu screens): " .. fmt:format(...), 0) end
end

-- the blobs: name -> how to read it
function X.blobs()
  local m = R.menu
  local lang = R.ui.lang
  return {
    { "itemMap", function(rom) return rom:lz77(m.itemMap) end, 0x800 },
    { "itemLang", function(rom) return rom:lz77(rom:ptr(m.itemLang + lang * 4)) end, 0x1000 },
    -- the overworld map (RomMap.owmap): raw copies, as the GBA loads them
    { "owTiles", function(rom) return rom:sub(R.owmap.tiles, R.owmap.tilesBytes) end, R.owmap.tilesBytes },
    { "owMapLw", function(rom) return rom:sub(R.owmap.map.lw, R.owmap.mapBytes) end, R.owmap.mapBytes },
    { "owMapDw", function(rom) return rom:sub(R.owmap.map.dw, R.owmap.mapBytes) end, R.owmap.mapBytes },
    { "owPalLw", function(rom) return rom:sub(R.owmap.pal.lw, R.owmap.palColours * 2) end, R.owmap.palColours * 2 },
    { "owPalDw", function(rom) return rom:sub(R.owmap.pal.dw, R.owmap.palColours * 2) end, R.owmap.palColours * 2 },
  }
end

function X.windows()
  return { R.menu.window, R.owmap.window }
end

function X.run(rom, cache, tick)
  local S = require("src.zelda.alttp.Serialize")
  local parts, info, off = {}, { blobs = {}, windows = {} }, 0
  local list = X.blobs()
  for i, b in ipairs(list) do
    local data, why = b[2](rom)
    check(data, "%s: %s", b[1], tostring(why))
    if b[3] then check(#data == b[3], "%s is %d bytes, expected %d", b[1], #data, b[3]) end
    parts[#parts + 1] = data
    info.blobs[b[1]] = { off, #data }
    off = off + #data
    if tick then tick(i, #list + 1) end
  end
  for _, w in ipairs(X.windows()) do
    local lo, hi = w[1], w[2]
    local data = rom:sub(lo, hi - lo)
    parts[#parts + 1] = data
    info.windows[#info.windows + 1] = { lo, hi, off }
    off = off + #data
  end
  -- structure checks: the map's frame uses the HUD's blank tile; the grid
  -- positions are in the map's item box
  local map = parts[1]
  check(map:byte(1) + map:byte(2) * 256 == 0x7F, "item menu map does not start blank")
  local p0 = rom:u16(R.menu.gridPos)
  check(p0 >= 0x1000 and p0 < 0x1800, "item grid position %04X", p0)
  assert(cache:write(X.FILES.blob, table.concat(parts)))
  assert(cache:write(X.FILES.info, S.encode(info)))
  if tick then tick(#list + 1, #list + 1) end
end

function X.files()
  return { X.FILES.blob, X.FILES.info }
end

-- runtime accessor over the imported blob
local Acc = {}
Acc.__index = Acc

function X.open(blob, info)
  return setmetatable({ blob = blob, info = info }, Acc)
end

function Acc:get(name)
  local b = self.info.blobs[name]
  if not b then return nil end
  return self.blob:sub(b[1] + 1, b[1] + b[2])
end

-- byte at ROM address a (file offset or 0x08xxxxxx) inside a kept window
function Acc:u8(a)
  if a >= 0x08000000 then a = a - 0x08000000 end
  for _, w in ipairs(self.info.windows) do
    if a >= w[1] and a < w[2] then return self.blob:byte(w[3] + a - w[1] + 1) end
  end
  error(("ALttP menus: ROM address %06X is not imported"):format(a))
end

function Acc:u16(a) return self:u8(a) + self:u8(a + 1) * 256 end
function Acc:u32(a) return self:u16(a) + self:u16(a + 2) * 65536 end
function Acc:ptr(a) return self:u32(a) - 0x08000000 end

return X
