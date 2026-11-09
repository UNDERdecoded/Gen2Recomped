-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ZELDA SAVES, through the same slot registry the Pokemon games use
-- (src/core/SaveData.lua): saves/<version>/<slotId>.lua, the .bak/.tmp
-- recovery discipline, the launcher's SAVE SLOT card, cloud sync and the
-- backups all work on them unchanged. The file is a plain Lua table in our
-- own format (SaveSerializer), never cartridge SRAM.
--
-- What a game puts in its table is its own business. Three optional keys are
-- read by the launcher:
--   name      the slot's display name (file name / hero name)
--   playTime  seconds played (number)
--   summary   { line = "3 hearts - Kakariko Village" }  one short line

local GameVersion = require("src.core.GameVersion")

local Saves = {}

-- The launcher's row text for a Zelda save (SaveData.slotSummary hook).
function Saves.summary(save, version)
  if type(save) ~= "table" then return nil, nil end
  local SaveData = require("src.core.SaveData")
  local t = math.floor(SaveData.playSeconds(save))
  local timeText = ("%d:%02d"):format(math.floor(t / 3600), math.floor(t / 60) % 60)
  local line = type(save.summary) == "table" and save.summary.line or nil
  line = line and (tostring(line) .. " - " .. timeText) or timeText
  local name = save.name
  if name == nil and type(save.player) == "table" then name = save.player.name end
  return name and tostring(name) or nil, { line = line, timeText = timeText, badges = 0, dexCount = 0 }
end

-- The active slot id for a version, creating slot1 if none exists yet.
function Saves.activeSlot(version)
  local SaveData = require("src.core.SaveData")
  local id = SaveData.activeSlot(version)
  if not id then
    id = SaveData.createSlot(version)
    if id then SaveData.setActiveSlot(version, id) end
  end
  return id
end

-- The decoded save table in a slot, or nil (new game).
function Saves.load(version, slotId)
  local SaveData = require("src.core.SaveData")
  slotId = slotId or Saves.activeSlot(version)
  if not slotId then return nil end
  for _, row in ipairs(SaveData.listSlots(version) or {}) do
    if row.id == slotId and not row.exists then return nil, slotId end
  end
  -- the same fs (portable folder or save dir) and the same recovery order
  -- (main, .tmp witness, .bak, stamped backups) SaveData itself uses
  local main = "saves/" .. version .. "/" .. slotId .. ".lua"
  local fs = SaveData.persistenceFs()
  local ok, data = pcall(require("src.core.SaveSafety").loadBest, fs, main, main .. ".bak", nil)
  if ok and type(data) == "table" then return data, slotId end
  return nil, slotId
end

-- Write a save table into a slot (atomic, previous copy kept). ok, err.
function Saves.write(version, slotId, tbl)
  assert(GameVersion.isZelda(version), "not a Zelda version")
  if type(tbl) ~= "table" then return false, "save() must return a table" end
  local SaveData = require("src.core.SaveData")
  slotId = slotId or Saves.activeSlot(version)
  if not slotId then return false, "no save slot" end
  -- the stamp SaveSafety.looksLikeSave accepts (a save, not a stray table)
  tbl.zelda = { version = version, format = 1 }
  tbl.savedAt = os.time()
  return SaveData.writeSlot(version, slotId, tbl)
end

return Saves
