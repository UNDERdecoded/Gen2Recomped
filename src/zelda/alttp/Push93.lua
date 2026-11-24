-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 93: a push block leaves the attribute of what lay under it.
--
-- GBA, the push block's state 1 (0x080838C0: state word +0x195C[i] == 1 ->
-- `bl 0x08083AE4`): 0x08083AE4 draws the four words kept under the block
-- (+0x19BC / +0x19DC / +0x19FC / +0x1A1C [i]) back into the map, then reads
-- the attribute of the last one (+0x1A1C, the bottom-right word):
-- `ldrh` / `ands #0x1FF` / `ldrb [0x02002E40 + n]` (0x08083BA4..0x08083BAE,
-- the room's tile attribute table) and 0x08083974 writes that byte to the
-- block's four cells of the attribute table (0x0200CBA0: +0, +1, +0x40,
-- +0x41). The port's RoomObjects.startPush wrote 0 (plain floor) there, so
-- a tile hidden under a block lost its meaning once the block moved:
-- Ganon's Tower 0x8B NE hides a star tile (0x3B, room tag 0x3A) under its
-- centre block -- the switch for overlay 17, the bridge over the pits next
-- to the west shutter -- and the port's floor there did nothing.
--
-- Here startPush is wrapped: after it, the block's old cells get
-- attributes[under[4] & 0x1FF] (the room's own table, Interior.attributes,
-- built at import) and the walk grid follows Interior.WALKABLE.
-- No ROM data: nothing is read (extract returns an empty table).

local bit = require("bit")
local band = bit.band

local M = { NAME = "push93" }

M.SITES = { state1 = 0x080838C0, redraw = 0x08083AE4, attrRead = 0x08083BA4, attrWrite = 0x08083974 }
M.MASK = 0x1FF

function M.extract(rom, R, check) return {} end

-- the attribute the cartridge writes for a block's old cells: the table
-- entry of its bottom-right word (under[4]); nil when it cannot be found
function M.attrUnder(inside, b)
  local w = b and b.under and b.under[4]
  if not w then return nil end
  local I = require("src.zelda.alttp.Interior")
  local idx = inside.data and inside.data.roomIdx
  if not (idx and I.attributes) then return nil end
  inside.push93Attrs = inside.push93Attrs or {}
  local key = inside.aux or 0
  local tab = inside.push93Attrs[key]
  if not tab then
    local ok, t = pcall(I.attributes, idx, key)
    if not ok or type(t) ~= "table" then return nil end
    tab = t
    inside.push93Attrs[key] = tab
  end
  return tab[band(w, M.MASK)]
end

-- after RoomObjects.startPush: the old cells get the attribute under the block
function M.afterStart(inside, b)
  local v = M.attrUnder(inside, b)
  if v == nil or v == 0 then return end
  local m = b.moving
  local cell = m and m.from or b.cell
  local t, g = inside.attrs, inside.grid
  if b.lower then t, g = inside.attrsLo, inside.gridLo end
  if not (t and g) then return end
  local W = require("src.zelda.alttp.Interior").WALKABLE or {}
  for _, d in ipairs({ 0, 1, 0x40, 0x41 }) do
    t[cell + d] = v
    g[cell + d] = not W[v]
  end
  inside.push93 = (inside.push93 or 0) + 1
end

function M.install(G)
  if G.push93Installed then return end
  G.push93Installed = true
  local RO = require("src.zelda.alttp.RoomObjects")
  local start0 = RO.startPush
  function RO.startPush(self, b, dir)
    local r = start0(self, b, dir)
    M.afterStart(self, b)
    return r
  end
end

return M
