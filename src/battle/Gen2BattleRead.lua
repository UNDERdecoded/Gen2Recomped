-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Pure reads at native calculation sites. Wrappers, PP, volatile state and
-- checkpoint tables retain their identity and original serializable fields.
local Model = require('src.battle.gen2.Battle')
local Read = {}
local owners = setmetatable({}, { __mode = 'kv' })
local nativeStat, nativeDef = Model.battleStat, Model.speciesDef

function Read.bind(battler, screen)
  if battler and screen and screen.battle and screen.battle ~= screen then
    owners[battler] = screen
  end
  return battler
end

local function modelOf(battler)
  local screen = owners[battler]
  local model = screen and screen.battle
  -- Non-Gen2 screens use themselves as their model and keep direct reads.
  return model ~= screen and model or nil
end

function Read.stats(battler)
  local stats = battler and battler.curStats
  if Model.battleStat == nativeStat then return stats end
  local model = battler and modelOf(battler)
  if not model then return stats end
  local values = {}
  for key in pairs(stats or {}) do
    values[key] = model:battleStat(battler.mon, key)
  end
  return values
end

function Read.types(battler)
  local types = battler and battler.curTypes
  if Model.speciesDef == nativeDef then return types end
  local model = battler and modelOf(battler)
  if not model then return types end
  -- Conversion/Transform own an explicit native type list. A species reader
  -- must not erase a move's live volatile override, or mutate its source row.
  if not battler.def or types ~= battler.def.types then return types end
  local def = model:speciesDef(battler.mon)
  return def and def.types or types
end

return Read
