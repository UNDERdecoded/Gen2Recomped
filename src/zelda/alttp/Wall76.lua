-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 76: the Misery Mire's moving wall room (RoomTag_MovingWall_East's own
-- case for one room).
--
-- Room tag 0x1C's handler (GBA 0x0807ABA4, the entry before 0x1D's
-- 0x0807AF50 in the tag table at 0x08152B34) starts with `cmp r0, #room` (0x0807ABB6) against the current
-- room (+0x9DA) and runs a separate path for that room (0x0807AD84):
--   * the torch check and the 0x2200 sub-pixel step as usual, the offset
--     (+0xAC8) counted down, but BG1's scroll (+0x950) is NOT written: the
--     room does not slide on screen, it shakes (RoomTag_MovingWallShakeItUp)
--     with Link held (+0x1770);
--   * when the offset passes kMovingWall_Tab1 (both compares, as the other
--     rooms): sound 0x7B, the tag cleared, and the room's maps are swapped:
--     an LZ77 map (`ldr` at 0x0807AE4E) is unpacked to 0x0201C000 and its
--     two right-hand screen blocks (+0x800, +0x1800) copied over the upper
--     map's (0x02018800 / 0x02019800); then another LZ77 map (`ldr` at
--     0x0807AE7C) is unpacked over the high-priority map 0x0201C000; all of
--     it to VRAM;
--   * the upper attribute table (0x0200CBA0) is opened along the old wall:
--     `movs r4, #n` (0x0807AEAE) times, the cells at the literal (`ldr` at
--     0x0807AEB4) and the next one, and the same two a row lower (`ldr` at
--     0x0807AEB2: the table + 64), are set to 0; the cell steps by the
--     `adds r1, #step` at 0x0807AEC4.
-- On a later load of the room with the wall's bit set (0x0807FF10, the room
-- maps loader: `cmp r0, #room` at 0x0807FF30) both maps come from those two
-- LZ77 maps (`ldr` 0x0807FF44 high map, 0x0807FF4E upper map) instead of
-- the room tables, and the attribute tables are built from them as usual.
--
-- Only the code sites live here; the room number, the two maps and the
-- attribute cells are read from the player's ROM at import (data.t.wall76).

local bit = require("bit")
local band, bnot = bit.band, bit.bnot

local M = {}

M.SITES = {
  roomCmp = { 0x0807ABB6, 0x0807FF30 },     -- cmp r0, #room
  upperLit = { 0x0807AE4E, 0x0807FF4E },    -- ldr r0 / r7, =the upper map (LZ77)
  highLit = { 0x0807AE7C, 0x0807FF44 },     -- ldr r0 / r7, =the high-priority map (LZ77)
  stripCell = 0x0807AEB4,                   -- ldr r1, =attribute cell (upper table)
  stripRow = 0x0807AEB2,                    -- ldr r5, =the table + one row
  stripN = 0x0807AEAE,                      -- movs r4, #count
  stripStep = 0x0807AEC4,                   -- adds r1, #step
}
M.ATTR_TABLE = 0x0200CBA0          -- the upper attribute table (dung_bg2_attr_table)
M.MAP_BYTES = 8192
-- the copy at 0x0807AE60..: screen blocks 1 and 3 (byte offsets) of the
-- unpacked map over the upper map's
M.RIGHT_BLOCKS = { 0x800, 0x1800 }
M.BLOCK_BYTES = 0x800
M.TAG = 0x1C                       -- the handler's entry in the tag table

local function off(a) return a - 0x08000000 end

local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end

local function imm8(rom, a, op)
  local h = rom:u16(off(a))
  if band(h, 0xFF00) ~= op then return nil end
  return band(h, 0xFF)
end

local function hex(s)
  return (s:gsub(".", function(c) return ("%02X"):format(c:byte()) end))
end
local function unhex(h)
  return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end))
end
M.hex, M.unhex = hex, unhex

function M.extract(rom, R, check)
  local S, t = M.SITES, {}
  local r1, r2 = imm8(rom, S.roomCmp[1], 0x2800), imm8(rom, S.roomCmp[2], 0x2800)
  check(r1 and r1 == r2, "moving wall room compare")
  t.room = r1
  local u1, u2 = lit(rom, S.upperLit[1]), lit(rom, S.upperLit[2])
  local h1, h2 = lit(rom, S.highLit[1]), lit(rom, S.highLit[2])
  check(u1 and u1 == u2 and u1 >= 0x08000000, "moving wall upper map pointer")
  check(h1 and h1 == h2 and h1 >= 0x08000000, "moving wall high map pointer")
  local upper, why = rom:lz77(off(u1))
  check(upper and #upper == M.MAP_BYTES, "moving wall upper map: %s", tostring(why))
  local high, why2 = rom:lz77(off(h1))
  check(high and #high == M.MAP_BYTES, "moving wall high map: %s", tostring(why2))
  t.upper, t.high = hex(upper), hex(high)
  local cell, row = lit(rom, S.stripCell), lit(rom, S.stripRow)
  local n = imm8(rom, S.stripN, 0x2400)
  local step = imm8(rom, S.stripStep, 0x3100)
  check(cell and row and n and step, "moving wall attribute strip")
  cell = cell - M.ATTR_TABLE
  row = row - M.ATTR_TABLE
  check(cell >= 0 and cell < 4096 and row > 0 and row < 4096, "moving wall attribute cells")
  t.cells = {}
  for i = 0, n - 1 do
    local c = cell + i * step
    for _, d in ipairs({ 0, 1, row, row + 1 }) do t.cells[#t.cells + 1] = c + d end
  end
  return t
end

-- ------------------------------------------------------------ run time

local function tab(data) return data and data.t and data.t.wall76 end
M.tab = tab

-- the two maps (and the upper map with only its right half swapped) as room
-- map numbers appended to the rooms blob, once per data
function M.maps(data, room)
  local t = tab(data)
  if not (t and t.upper and data.rooms) then return nil end
  data.wall76 = data.wall76 or {}
  local W = data.wall76
  if not W.upper then
    local B = M.MAP_BYTES
    local n = math.floor(#data.rooms / B)
    local up, hi = unhex(t.upper), unhex(t.high)
    -- the live swap: the room's own upper map with blocks 1 and 3 replaced
    local own = data.roomIdx and data.roomIdx.bg2[room + 1]
    local mix
    if own then
      local o = own * B
      local parts, p = {}, 0
      local blocks = {}
      for _, b in ipairs(M.RIGHT_BLOCKS) do blocks[b] = true end
      for b = 0, B - 1, M.BLOCK_BYTES do
        if blocks[b] then parts[#parts + 1] = up:sub(b + 1, b + M.BLOCK_BYTES)
        else parts[#parts + 1] = data.rooms:sub(o + b + 1, o + b + M.BLOCK_BYTES) end
      end
      mix = table.concat(parts)
    end
    data.rooms = data.rooms .. up .. hi .. (mix or up)
    W.upper, W.high, W.mix = n, n + 1, n + 2
  end
  return W.upper, W.high, W.mix
end

local function isRoom(inside)
  local t = tab(inside and inside.data)
  return t and inside.room == t.room, t
end

-- the room's maps swapped when the wall stops (0x0807AE4E..0x0807AECC)
function M.apply(game)
  local inside = game.interior
  local ok, t = isRoom(inside)
  if not ok then return false end
  local _, high, mix = M.maps(inside.data, inside.room)
  if not high then return false end
  inside.bg2, inside.bg1 = mix, high
  for _, c in ipairs(t.cells or {}) do
    if inside.attrs then inside.attrs[c] = 0 end
    if inside.grid then inside.grid[c] = false end
  end
  game.roomImages = nil
  game.wall76 = (game.wall76 or 0) + 1
  return true
end

function M.install(G)
  local DP = require("src.zelda.alttp.DesertPalace")
  local frame0 = DP.wallFrame
  function DP.wallFrame(game)
    local inside = game.interior
    local w = inside and inside.wall
    local was = w and w.moved
    frame0(game)
    if w and not was and w.moved and w.tag == M.TAG and isRoom(inside) then M.apply(game) end
  end
  -- the room's BG1 scroll is not written (the room shakes, it does not slide)
  local off0 = DP.bg3Offset
  function DP.bg3Offset(game)
    local inside = game.interior
    if inside and inside.wall and inside.wall.tag == M.TAG and isRoom(inside) then return 0, 0, true end
    return off0(game)
  end
  -- a later load with the wall's bit set: both maps from the two LZ77 maps
  local RO = require("src.zelda.alttp.RoomObjects")
  local load0 = RO.load
  function RO.load(inside, ...)
    if inside.mem and inside.mem.wallMoved and isRoom(inside) then
      local upper, high = M.maps(inside.data, inside.room)
      if upper then inside.bg2, inside.bg1 = upper, high end
    end
    return load0(inside, ...)
  end
end

return M
