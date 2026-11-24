-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE OPENED BIG-KEY LOCK'S FLOOR (round 66). The port opened a cell lock
-- (subtype-3 object 0x18, Interior.markChests' `lock` entries) by clearing
-- its attributes only: the lock stayed drawn on the pre-rendered map, so
-- after a reload (or any room load) Thieves' Town's three cells showed
-- shut locks Link walked through. The cartridge draws the room's floor
-- filler over the lock both when it opens and when the room loads open:
--
--   OpenChestForItem (GBA 0x08084008), the lock branch (0x08084080, the
--   chest location's bit 15 set): with the palace's big key, the room's
--   state bit kChestOpenMasks[n] (0x081676F2) is set, then four words of
--   the dungeon object tile table (base literal at 0x080840A8, GBA
--   0x08164520 = SNES kDungeonObjectTiles) at word (dung_floor_2_filler
--   _tiles >> 1) + 2 / + 3 / + 0 / + 1 go to the BG2 map (0x02018000) at
--   the lock's cell, the cell below, the cell to the right, below-right.
--   RoomDraw_BigKeyLock (0x0807D7F0, table literal 0x0807D880): when the
--   state bit is already set at load, the same four words, the same cells.
--   dung_floor_2_filler_tiles (+0xB12) is set by the room loader (0x0807FEB4
--   ff.: the room object list's first byte & 0x0F, << 4: a byte offset).
--
-- Ported: the filler words per floor nibble and every room's nibble (read
-- at import, data.t.cell66); Interior:openChest (load and live) draws them
-- on the room's BG2 patch for a lock. The attributes stay as before.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.OPEN_FN, M.LOCK_DRAW_FN, M.FLOOR_FN = 0x08084008, 0x0807D7F0, 0x0807FEB4
M.SITES = { openTableLit = 0x080840A8, loadTableLit = 0x0807D880, floorAnd = 0x0807FEE0 }
-- word offsets into the filler block: the lock cell, below, right, below-right
M.ORDER = { 2, 3, 0, 1 }

function M.extract(rom, R, check)
  local RT = require("src.zelda.alttp.RomTables")
  local S = M.SITES
  local function lit(at) local v, form = RT.codeImm(rom, at); if form ~= "ldr" then return nil end return v end
  local base, base2 = lit(S.openTableLit), lit(S.loadTableLit)
  -- the loader's nibble mask: movs r0, #0xF at floorAnd
  local maskOk = rom:u16(S.floorAnd - 0x08000000) == 0x200F
  local t = { fill = {}, floor = {} }
  if base and base == base2 then
    for n = 0, 15 do
      t.fill[n + 1] = rom:bytesU16(base - 0x08000000 + n * 16, 4)
    end
  end
  for r = 0, R.roomCount - 1 do
    local p = rom:ptr(R.roomObjects + r * 4)
    t.floor[r + 1] = p and band(rom:u8(p), 0x0F) or 0
  end
  check(base and base == base2 and maskOk and #t.fill == 16 and #t.floor == R.roomCount,
        "the opened big-key lock's floor filler (OpenChestForItem / RoomDraw_BigKeyLock)")
  return t
end

local function tab(data) return data and data.t and data.t.cell66 end
M.tab = tab

-- the four words for a room (lock cell, below, right, below-right)
function M.words(T, room)
  local n = T.floor[room + 1] or 0
  local f = T.fill[n + 1]
  if not f then return nil end
  return { f[M.ORDER[1] + 1], f[M.ORDER[2] + 1], f[M.ORDER[3] + 1], f[M.ORDER[4] + 1] }
end

-- draw the filler over an opened lock entry (Interior chest entry, lock)
function M.drawOpen(inside, c)
  local T = tab(inside.data)
  if not (T and c and c.lock and inside.patch) then return false end
  local w = M.words(T, inside.room)
  if not w then return false end
  local p = inside.patch
  p[c.y * 64 + c.x] = w[1]
  p[(c.y + 1) * 64 + c.x] = w[2]
  p[c.y * 64 + c.x + 1] = w[3]
  p[(c.y + 1) * 64 + c.x + 1] = w[4]
  inside.cellOpen66 = (inside.cellOpen66 or 0) + 1
  return true
end

function M.install(G)
  local I = require("src.zelda.alttp.Interior")
  if I.cells66 then return end
  I.cells66 = true
  local open0 = I.openChest
  function I:openChest(c)
    local r = open0(self, c)
    if c and c.lock then M.drawOpen(self, c) end
    return r
  end
end

return M
