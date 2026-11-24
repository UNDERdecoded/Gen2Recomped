-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 57: the water ladders (subtype-2 object 0x35) in every room.
--
-- RoomDraw for subtype-2 0x35 (GBA 0x0807C778; Link's block 0x03002230):
-- when dung_hdr_tag[1] (+0x9E7) is 0x1B and the room's save_dung_info word
-- (0x02002000 + room * 2) lacks 0x100 (the dam shut) it is drawn as the
-- inactive ladder (0x0807C72C, list +0xAEE); otherwise its position goes on
-- the active list (+0xC2A[+0xAE8], 0x0807C7C0..0x0807C7DE; room 0xDD also
-- sets +0x1812). Dungeon_LoadObjectAttribute (0x08082200..0x080822FC) then
-- writes, for each active ladder at cell p: upper p..p+3 = 03 00 00 03,
-- lower p..p+3 = 03 0A 0A 03 (0x0A, the short water ladder Swim54 climbs
-- out on), for each inactive one 03 0A 0A 03 on both levels and 03 08 08 03
-- on the upper row below.
-- The port wrote these only in the rooms whose water a switch or the dam
-- changes (Mech27.stairsAtLoad: 0x28, 0x35, 0x37, 0x76 ...), and drew 0x37's
-- ladder inactive before its flood; room 0x16's five ladders (its pool, the
-- one way out of the water) had no 0x0A: Link could swim in and not out.
-- M.atLoad runs after Mech27's room load and applies the cartridge's rule
-- to the rooms Mech27 leaves alone (no flood / drain object, not the dam).
-- Seen, not changed: Mech27 still draws 0x37's ladder inactive before the
-- flood (the GBA: active; the upper row below keeps 03 08 08 03).

local M = { NAME = "ladder57" }
M.DAM_TAG = 0x1B
M.ACTIVE_UP, M.ACTIVE_LO = { 0x03, 0x00, 0x00, 0x03 }, { 0x03, 0x0A, 0x0A, 0x03 }

local function put(inside, lower, cell, vals)
  local at, gr = inside.attrs, inside.grid
  if lower then at, gr = inside.attrsLo, inside.gridLo end
  if not at then return end
  local W = require("src.zelda.alttp.Interior").WALKABLE
  for i, v in ipairs(vals) do
    local c = cell + i - 1
    if c >= 0 and c <= 4095 then at[c] = v; gr[c] = not W[v] end
  end
end

-- is the ladder drawn active? (0x0807C784..0x0807C7A2)
function M.active(game, inside)
  local tag1 = (inside.hdr or {})[7] or 0
  if tag1 ~= M.DAM_TAG then return true end
  return require("src.zelda.alttp.Mech27").damOpen(game)
end

-- after the room's attribute tables (Mech27's afterLoad): info = the room's
-- Mech27 object record (info.ladder: the 0x35 objects, x / y in cells)
function M.atLoad(game, inside, info)
  if not (info and info.ladder) or not M.active(game, inside) then return 0 end
  if info.flood or info.drain or ((inside.hdr or {})[7] or 0) == M.DAM_TAG then return 0 end
  local n = 0
  for _, o in ipairs(info.ladder) do
    local j = o.y * 64 + o.x
    put(inside, false, j, M.ACTIVE_UP)
    put(inside, true, j, M.ACTIVE_LO)
    n = n + 1
  end
  inside.ladders57 = n
  return n
end

return M
