local Rules = {}
local function vanilla()
  return require("src.pokemon.Gen2Breeding").isVanilla()
end

-- ApplyMusicEffectOnEncounterRate precedes Cleanse Tag; SLA wraps a byte.
function Rules.rate(data, save, rate, song)
  if vanilla() then
    if song == "Music_PokemonMarch" or song == "Music_RuinsOfAlphRadio" then
      rate = (rate * 2) % 256
    elseif song == "Music_PokemonLullaby" then
      rate = math.floor(rate / 2)
    end
  end
  return require("src.battle.HeldItems").cleanseTagRate(data, save.party, rate)
end

-- ChooseWildEncounter's four immediate comparisons, not rounded percentages.
function Rules.waterLevel(data, enc, rng)
  if not enc or not vanilla() then return enc end
  local def = data.field and data.field.gen2EncounterRules
  local thresholds = def and def.waterLevelThresholds or {89, 165, 216, 242}
  local roll = (rng or love.math.random)(0, 255)
  local extra = 0
  for _, threshold in ipairs(thresholds) do
    if roll < threshold then break end
    extra = extra + 1
  end
  local result = {}
  for key, value in pairs(enc) do result[key] = value end
  result.level = (enc.level + extra) % 256
  return result
end

function Rules.repelAllows(save, enc)
  if not enc then return false end
  if (save.repelSteps or 0) <= 0 then return true end
  local lead = require("src.pokemon.Party").firstHealthy(save.party or {})
  return not lead or enc.level >= lead.level
end

return Rules
