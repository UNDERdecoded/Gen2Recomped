local Rules = {}
local function vanilla()
  return require("src.pokemon.Gen2Breeding").isVanilla()
end

-- CanEncounterWildMon: CheckGrassCollision is skipped in caves/dungeons,
-- but CheckIceTile and STATUSFLAGS_NO_WILD_ENCOUNTERS_F apply everywhere.
-- The live map supplies its imported/authored encounter-class verdict. The
-- default is the cartridge's list for callers holding only a collision byte.
local ENCOUNTER_COLLISION = {
  [0x08]=true, [0x18]=true, [0x14]=true, [0x28]=true, [0x29]=true,
  [0x48]=true, [0x49]=true, [0x4a]=true, [0x4b]=true, [0x4c]=true,
}
function Rules.canEncounterWildMon(environment, collision, disabled, encounterCollision)
  if disabled or type(collision)~="number" or collision<0 then return false end
  collision=collision%256
  if collision==0x23 or collision==0x2b then return false end
  if environment==4 or environment==7 or environment=="CAVE" or environment=="DUNGEON" then return true end
  if encounterCollision~=nil then return encounterCollision==true end
  return ENCOUNTER_COLLISION[collision]==true
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
