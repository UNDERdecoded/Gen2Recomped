-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S BOULDER HOLES (Ice Path B1F).
--
-- The Strength push task (pokeheartgold asm/overlay_01_021F1AFC.s,
-- ov01_021F1ECC) ends, on MAP_ICE_PATH_B1F (header 0xED) only, with
-- ov01_021F2004 -> ov01_021F1F8C, which walks the four rows of
-- ov01_02206A14 { map, x, z, object id, flag }:
--
--   (11,10) object 0 -> FLAG_HIDE_ICE_PATH_BOULDER_1_FALLEN 0x1EE
--   (10,18) object 1 -> 0x1EF
--   (18, 7) object 2 -> 0x1F0
--   (19,19) object 3 -> 0x1F1
--
-- When the pushed boulder IS that object and stands on that cell, its own
-- event flag (FLAG_HIDE_ICE_PATH_BOULDER_n_INIT) is set, the object is
-- deleted, the row's FALLEN flag is cleared -- its twin appears on B2F --
-- and std_boulder_fell_down (10015: the thud, the shake, "The boulder fell
-- through!") runs. Any other boulder, or the right one on the wrong hole,
-- just stands there, as on the cartridge. Without this the boulders rolled
-- over the holes and B2F's way on (the fallen boulders are its stepping
-- stones) could never open.

local M = {}

M.HEADER = 0xED          -- MAP_ICE_PATH_B1F
M.STD_FELL = 10015       -- std_boulder_fell_down
M.HOLES = {
  { x = 11, y = 10, object = 0, fallen = 0x1EE },
  { x = 10, y = 18, object = 1, fallen = 0x1EF },
  { x = 18, y = 7,  object = 2, fallen = 0x1F0 },
  { x = 19, y = 19, object = 3, fallen = 0x1F1 },
}

local function isHgss(data)
  local v = data and data.gen4_version
  return data and data.isGen4Cache and v and v.family == "hgss" or false
end

local function flagKey(id) return ("FLAG_G4_%04X"):format(id) end

-- a shared band's label (Gen4ScriptBands' dispatcher arithmetic)
local function stdLabel(data, id)
  local ms = data and data.map_scripts
  local bands = ms and (ms.bands or ms.shared)
  local okB, Bands = pcall(require, "src.import.Gen4ScriptBands")
  if not (okB and bands) then return nil end
  local kind, name, index = Bands.classify(id)
  local band = kind == "band" and bands[name]
  return band and band.entries and band.entries[(index or 0) + 1]
end

-- after a push has landed: true when `npc` fell through (and is gone)
function M.fell(ow, npc)
  local Game = package.loaded["src.core.Game"]
  local data = Game and Game.data
  local def = ow and ow.map and ow.map.def
  if not (isHgss(data) and def and tonumber(def.header) == M.HEADER and npc) then return false end
  local lid = npc.localId or (npc.def and npc.def.localId)
  for _, h in ipairs(M.HOLES) do
    if lid == h.object and npc.cellX == h.x and npc.cellY == h.y then
      local Flags = require("src.script.Flags")
      local own = npc.def and tonumber(npc.def.flag)
      if own and own > 0 then Flags.set(Game.save, flagKey(own)) end
      Flags.clear(Game.save, flagKey(h.fallen))
      for _, list in ipairs({ ow.npcs or {}, ow.entities or {} }) do
        for i = #list, 1, -1 do
          if list[i] == npc then table.remove(list, i) end
        end
      end
      local label = stdLabel(data, M.STD_FELL)
      local rows = label and require("src.script.Gen4ScriptVM").compile(data, label)
      if rows and ow.queueScript then ow:queueScript(rows, { mapId = def.id }) end
      return true
    end
  end
  return false
end

return M
