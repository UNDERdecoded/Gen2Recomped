-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE COMMANDS THAT EDIT THE ZONE'S LOADED EVENT DATA.
--
-- 0x1EA <sign, x, level, z>  moves a "sign" (BW's interactable record, the
--   first list of the zone's event file -- Gen5Events) to a new cell.
--   READ FROM CODE (ov10 0x0215B214): four var-or-values, then 0x02162A74
--   on the field's event data (0x02012844): if sign < the record count
--   (+0x12) and the record's +6 (its rail flag) is 0, x goes to +8, z to
--   +0xC and level << 4 to +0x10 -- exactly the fields Gen5Events reads as
--   x / y / height. The change is to the RAM copy: a zone load re-reads the
--   file, which is why the cartridge's own ON_LOAD re-applies it.
--   Nacrene Gym (Z018): when the hidden staircase opens (0x408A = 7, M0036
--   S1203) and on every later load (S00A0) the four bookshelf records
--   22-25 follow the bookcase three cells right, (11..14, 10) -> (14..17,
--   10). Before this the shelves still answered on their old cells, in
--   front of the staircase.
--
-- Here the Map's own lookup (`signAt`, built per load) is edited, with a
-- copy of the record, so the map def -- shared by every load of the zone --
-- keeps the file's positions, as the cartridge's file does.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

local function G4() return require("src.script.Gen4Commands") end

function M.moveSign(map, index, x, y, level)
  if not (map and map.def and map.signAt) then return false end
  local w = map.widthCells or 0
  for _, s in ipairs(map.def.signs or {}) do
    if s.index == index then
      local old
      -- the record now at its cell may already be a moved copy
      for k, v in pairs(map.signAt) do
        if v == s or (v.g5MovedFrom == s) then old = k break end
      end
      if old then map.signAt[old] = nil end
      local copy = {}
      for k, v in pairs(s) do copy[k] = v end
      copy.x, copy.y, copy.gen5Level, copy.g5MovedFrom = x, y, level, s
      map.signAt[y * w + x] = copy
      return true
    end
  end
  return false
end

function Commands.g5_set_sign_pos(ctx, index, x, level, z)
  local ow = ctx and ctx.overworld
  if not (ow and ow.map) then return end
  local G = G4()
  local i = math.floor(tonumber(G.valueOf(ctx, index)) or -1)
  local lx, ly = G.toLocal(ctx, G.valueOf(ctx, x), G.valueOf(ctx, z))
  M.moveSign(ow.map, i + 1, math.floor(lx), math.floor(ly), math.floor(tonumber(G.valueOf(ctx, level)) or 0))
end

function M.install(L)
  local function emit(s, row) s.out[#s.out + 1] = row end
  L.bwsetsignpos = L.bwsetsignpos or function(ins, s)
    emit(s, { "g5_set_sign_pos", ins.args[1], ins.args[2], ins.args[3], ins.args[4] })
  end
end

return M
