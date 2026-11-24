-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 64: the animated sprite tile slot (DecodeAnimatedSpriteTile_variable)
-- and the heart container (sprite 0xEA) drawn from it.
--
-- The port drew the heart container with SpriteDraw_SingleLarge's char from
-- the room's OBJ layout; that char (page 0, row 2) is the slot the cartridge
-- overwrites with a decoded 16 x 16 picture, so the port showed sheet 0's
-- lower-half tiles there (broken pieces in Mothula's room and the others).
--
-- GBA, read at import from the code below:
--   * Sprite_HeartContainer 0x080F2808: on its first frame (sprite_D == 0)
--     `movs r0, #n` 0x080F2832, bl 0x0812FBC4 (the decoder), then the draw
--     0x080C6240 (Sprite_PrepAndDrawSingleLarge: char =
--     kSingleLarge_Tab2[kSingleLarge_Tab1[type] (u16) + gfx]);
--   * the decoder 0x0812FBC4 (var in r0): w = u16 table (literal 0x0812FBC8)
--     [var]; sheet = (w >> 11) + `adds #n` 0x0812FBD8 from the sheet
--     pointers (literal 0x0812FBD6, LZ77 0x08135B90 into the buffer, literal
--     0x0812FBE0); the copy (0x08135B78, `movs r2, #n` 0x0812FBEE words)
--     from buffer + (w & mask (literal 0x0812FBD2)) to the RAM tile copy
--     (literal 0x0812FBEA), and from buffer + 0x200 (literal 0x0812FBF4) +
--     (w & mask) to the second (literal 0x0812FBF8): two tile rows;
--   * the frame's VRAM copy list (pairs {RAM, VRAM}, the pair at
--     0x080A6E58 / 0x080A6E60) puts the two rows at OBJ chars
--     (VRAM - 0x06010000) / 32: the first and the one 32 below (2D layout).
--
-- Ported: Sprites' tile lookup returns the decoded picture for the slot's
-- chars once a decode has happened in the current sprite layout (a layout
-- change brings back the plain tiles, as the room loader's copy does); the
-- heart container decodes its variant when it is first drawn.
--
-- OURS: the decode happens at the first draw, not the sprite's first frame
-- (the same frame in practice); the other decoders' callers (keys, the
-- book, ...) keep their own drawing.

local M = {}

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

M.FN = 0x0812FBC4
M.HC_TYPE = 0xEA
M.SITES = {
  tabLit = 0x0812FBC8, maskLit = 0x0812FBD2, sheetsLit = 0x0812FBD6, base = 0x0812FBD8,
  bufLit = 0x0812FBE0, dstLit = 0x0812FBEA, words = 0x0812FBEE, buf2Lit = 0x0812FBF4,
  dst2Lit = 0x0812FBF8, vramPair = 0x080A6E58, vramPair2 = 0x080A6E60,
  hcVar = 0x080F2832, hcCall = 0x080F2834,
}
M.VARS = 48            -- entries read (the callers use 0x03..0x28)
M.OBJ_VRAM = 0x06010000

-- ------------------------------------------------------------ import
function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function imm(at, want)
    local v, form = RT.codeImm(rom, at)
    if want and form ~= want then return nil end
    return v
  end
  local t = {}
  local tab = imm(S.tabLit, "ldr")
  t.mask = imm(S.maskLit, "ldr")
  local sheets = imm(S.sheetsLit, "ldr")
  t.base = imm(S.base, "adds")
  local buf, buf2 = imm(S.bufLit, "ldr"), imm(S.buf2Lit, "ldr")
  local dst, dst2 = imm(S.dstLit, "ldr"), imm(S.dst2Lit, "ldr")
  local words = imm(S.words, "movs")
  t.rowStep = buf and buf2 and (buf2 - buf) or nil
  t.tiles = words and math.floor(words * 4 / 32) or nil
  -- the VRAM spot of each RAM copy
  local v1 = dst and rom:u32(S.vramPair - 0x08000000) == dst and rom:u32(S.vramPair + 4 - 0x08000000)
  local v2 = dst2 and rom:u32(S.vramPair2 - 0x08000000) == dst2 and rom:u32(S.vramPair2 + 4 - 0x08000000)
  t.char = v1 and math.floor((v1 - M.OBJ_VRAM) / 32) or nil
  t.char2 = v2 and math.floor((v2 - M.OBJ_VRAM) / 32) or nil
  t.vars = {}
  local count = R.sprites.sheetCount
  if tab and t.mask and t.base then
    for i = 0, M.VARS - 1 do
      local w = rom:u16(tab - 0x08000000 + i * 2)
      local sh = rshift(w, 11) + t.base
      if sh < count then t.vars[i] = { sheet = sh, off = band(w, t.mask) } end
    end
  end
  -- the heart container's decode
  t.hcVar = RT.blTarget(rom, S.hcCall) == M.FN and imm(S.hcVar, "movs") or nil
  local hcChar
  if t.hcVar then
    local i1 = rom:u16(R.sprites.singleTab1 + M.HC_TYPE * 2)
    hcChar = rom:u8(R.sprites.singleTab2 + i1)
  end
  check(sheets == 0x08000000 + R.sprites.sheets and t.rowStep and t.rowStep > 0 and t.tiles and t.tiles >= 1
        and t.char and t.char2 and t.char2 == t.char + 32 and t.hcVar and t.vars[t.hcVar] ~= nil
        and band(t.vars[t.hcVar].off, 31) == 0 and hcChar == t.char,
        "animated tile slot (char %s, var %s, hc char %s)", tostring(t.char), tostring(t.hcVar), tostring(hcChar))
  return t
end

local function tab(data) return data and data.t and data.t.anim64 end
M.tab = tab

-- the sheet / tile in sheet a slot char shows for a decoded variant (nil
-- when t is not one of the slot's chars)
function M.source(T, var, t)
  local e = T and T.vars[var]
  if not e or t >= 256 then return nil end
  local d = t - T.char
  if d < 0 then return nil end
  local dr, dc = math.floor(d / 32), d % 32
  if dr > 1 or dc >= T.tiles then return nil end
  return e.sheet, math.floor(e.off / 32) + dc + dr * math.floor(T.rowStep / 32)
end

-- the decoder: the slot now shows variant var
function M.decode(spr, var)
  if spr.animTile64 == var then return end
  spr.animTile64 = var
  spr.cache = {}
end

-- ------------------------------------------------------------ install
function M.install(G)
  local Spr = require("src.zelda.alttp.Sprites")
  if Spr.animTile64Installed then return end
  Spr.animTile64Installed = true
  local ts0 = Spr.tileSource
  function Spr:tileSource(t)
    local v = self.animTile64
    if v then
      local s, i = M.source(tab(self.data), v, t)
      if s then return s, i end
    end
    return ts0(self, t)
  end
  local sr0 = Spr.setRoom
  function Spr:setRoom(...)
    local k0 = self.key
    local r = sr0(self, ...)
    if self.key ~= k0 then self.animTile64 = nil end
    return r
  end
  local da0 = Spr.drawActor
  function Spr:drawActor(a, ...)
    if a.type == M.HC_TYPE then
      local T = tab(self.data)
      if T and T.hcVar then M.decode(self, T.hcVar) end
    end
    return da0(self, a, ...)
  end
end

return M
