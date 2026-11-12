-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SPRITE IMPORT (round 7). Reads the GBA's own sprite sheets (RomMap.sprites:
-- the 0x0822B324 table, LZ77) and the per-sprite drawing tables and sprite
-- palette index tables the GBA routines use, from the player's ROM.
-- Writes:
--
--   assets/generated/alttp/spr.bin     sheets x 4096 bytes (4bpp, 16 tiles a row)
--   data/generated/alttp_spr.lua       the drawing / palette tables
--
-- Nothing here is invented: every table is read at the offset RomMap names.

local R = require("src.zelda.alttp.RomMap")

local X = {}

X.FILES = {
  sheets = "assets/generated/alttp/spr.bin",
  info   = "data/generated/alttp_spr.lua",
}
X.SHEET_BYTES = 4096

local function check(c, fmt, ...)
  if not c then error("ALttP import (sprites): " .. fmt:format(...), 0) end
end

local function s16list(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local v = rom:u16(o + i * 2)
    t[i + 1] = v >= 0x8000 and v - 0x10000 or v
  end
  return t
end

-- DMD entries: { x, y, char, flags, big }
local function dmd(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local p = o + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end

function X.read(rom, tick)
  local S = R.sprites
  local parts = {}
  for i = 0, S.sheetCount - 1 do
    local p = rom:ptr(S.sheets + i * 4)
    check(p, "sheet %d pointer", i)
    local data, why = rom:lz77(p)
    check(data, "sheet %d: %s", i, tostring(why))
    check(#data <= X.SHEET_BYTES, "sheet %d is %d bytes", i, #data)
    parts[i + 1] = data .. string.rep("\0", X.SHEET_BYTES - #data)
    if tick and i % 16 == 0 then tick(i + 1, S.sheetCount + 4) end
  end
  local u8, u16 = function(o, n) return rom:bytesU8(o, n) end, function(o, n) return rom:bytesU16(o, n) end
  local info = {
    flags3 = u8(S.flags3, 243),
    single1 = u16(S.singleTab1, 243), single2 = u8(S.singleTab2, S.singleTab2Len),
    pal = { main = u8(S.sprMain, 2), aux3 = u16(S.sprAux3, 23), aux1 = u16(S.sprAux1, 32),
            misc = u16(S.sprMisc, 16), sword = u16(S.swordPal, 5), shield = u16(S.shieldPal, 4),
            dungMain = u16(R.dungPalIndex, 24) },
    follower = u16(S.follower, 16), followerZelda = S.followerSheetZelda,
    guard = { d1char = u8(S.d1char, 4), d1flags = u8(S.d1flags, 4), d1yd = s16list(rom, S.d1yd, 26),
              d2oam = u8(S.d2oam, 4), d2xd = s16list(rom, S.d2xd, 104), d2yd = s16list(rom, S.d2yd, 104),
              d2char = u8(S.d2char, 104), d2flags = u8(S.d2flags, 104), d2big = u8(S.d2big, 104),
              d3oam = u8(S.d3oam, 4), d3xd = s16list(rom, S.d3xd, 28), d3yd = s16list(rom, S.d3yd, 28),
              d3char = u8(S.d3char, 28), d3flags = u8(S.d3flags, 28),
              gfx2 = u8(S.gfx2, 32), headDirs = u8(S.headDirs, 32) },
    recruit = { x = s16list(rom, S.recruitX, 8), char = u8(S.recruitChar, 8),
                flags = u8(S.recruitFlags, 8), gfx = u8(S.recruitGfx, 8) },
    rat = { tab0 = u8(S.ratTab0, 16), tab1 = u8(S.ratTab1, 16), tab2 = u8(S.ratTab2, 8), tab4 = u8(S.ratTab4, 8) },
    rope = { gfx = u8(S.ropeGfx, 8), flags = u8(S.ropeFlags, 8) },
    switchTab2 = u8(S.switchTab2, 14),
    uncle = dmd(rom, S.uncle, 48), priest = dmd(rom, S.priest, 20),
    maiden = dmd(rom, S.maiden, 16), maidenDma = u8(S.maidenDma, 16),
    mantle = { x = u8(S.mantleX, 6), y = u8(S.mantleY, 6), char = u8(S.mantleChar, 6), flags = u8(S.mantleFlags, 6) },
    spriteTilesets = u8(R.spriteTilesets, R.spriteTilesetCount * 4),
  }
  -- structural checks: the guard body table pairs 16x16 parts, the uncle's
  -- frames start with his head, the main sprite palettes sit in blob page 0
  check(info.guard.d2big[1] == 2 and info.guard.d2big[3] == 0, "guard body sizes")
  check(info.uncle[1][5] == 2 and info.uncle[1][2] < 0, "uncle draw table")
  check(info.pal.main[1] < 0x100 and info.pal.aux1[2] == 0x10, "sprite palette tables")
  check(info.mantle.x[2] == 0x10, "mantle table")
  return table.concat(parts), info
end

function X.run(rom, cache, tick)
  local Sz = require("src.zelda.alttp.Serialize")
  local blob, info = X.read(rom, tick)
  assert(cache:write(X.FILES.sheets, blob))
  assert(cache:write(X.FILES.info, Sz.encode(info)))
  if tick then tick(1, 1) end
end

function X.files() return { X.FILES.sheets, X.FILES.info } end

return X
