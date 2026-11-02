-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ABYSSAL RUINS' STEP COUNT: the water that rises the longer you stay.
--
-- READ FROM CODE (Black):
--   * every step of the field (ov21 0x0218A9F2 -> 0x0218AC08), in a zone of
--     arm9 0x0209DFB8 {245, 246, 247, 248} (the Ruins' floors, 0x02013FFC):
--     the count -- u16 +0x7E of save block 0x1C (0x02008990 / 0x02008988) --
--     is first compared with ov21's table 0x021DD6BC {0, 100, 300, 450, 500}
--     and on a match the paired common script {10461 .. 10465} runs
--     (0x021D220C), then it grows by one
--   * a map load into any other zone sets it back to 0 (ov10 0x02164448)
--   * script 0x0E9 <dest> reads it (ov21 0x021CFA88)
-- Kept as save.gen5RuinsSteps.

local M = {}

M.ZONES = { [245] = true, [246] = true, [247] = true, [248] = true }
M.TRIGGERS = { [0] = 10461, [100] = 10462, [300] = 10463, [450] = 10464, [500] = 10465 }

local function zoneOf(ow)
  local def = ow and ow.map and ow.map.def
  return def and def.gen5 and tonumber(def.header) or nil
end

function M.count(save) return tonumber(save and save.gen5RuinsSteps) or 0 end

-- a map load (OverworldState:setMap's Gen 5 path): outside the Ruins, 0
function M.onMap(ow, save)
  local z = zoneOf(ow)
  if z and not M.ZONES[z] and save then save.gen5RuinsSteps = 0 end
end

local function runCommon(ow, id)
  local data = require("src.core.Game").data
  local VM = require("src.script.Gen4ScriptVM")
  local pool = VM.store(data)
  local kind, name, index = require("src.import.Gen4ScriptBands").classify(id)
  local band = pool and pool.bands and kind == "band" and pool.bands[name]
  local label = band and band.entries and band.entries[index + 1]
  local rows = label and VM.compile(data, label)
  if rows and ow.runner and not ow.runner:isRunning() then
    ow.runner:run(rows, { mapId = ow.map.id })
    return true
  end
  return false
end

-- one step of the player
function M.onStep(ow, save)
  local z = zoneOf(ow)
  if not (z and save) then return end
  if not M.ZONES[z] then save.gen5RuinsSteps = 0 return end
  local n = M.count(save)
  local id = M.TRIGGERS[n]
  if id then runCommon(ow, id) end
  save.gen5RuinsSteps = math.min(0xFFFF, n + 1)
end

return M
