-- CalculateBaseDamage reads each holder once, then reuses those answers for
-- type and species/stat items. Never retain an answer across native commands.
local HoldItems = require("src.battle.HoldItems")
local D = {}
local function species(battler, battle)
  local id = battler.species or battler.mon.species
  local def = battle and battle.data and battle.data.pokemon and battle.data.pokemon[id]
  return tonumber(id) or tonumber(def and (def.index or def.dex)), id
end
local function isSpecies(battler, battle, numbers, names)
  local number, name = species(battler, battle)
  return numbers[number] or names[name]
end
function D.held(attacker, defender, move, special, attack, defense, battle)
  local aEffect, parameter = HoldItems.effectOf(attacker, "damage")
  local dEffect = HoldItems.effectOf(defender, "damage")
  local kind = require("src.battle.Abilities").normalizeType(move.type)
  if HoldItems.TYPE_POWER[aEffect] == kind then
    attack = math.floor(attack * (100 + (parameter or 0)) / 100)
  end
  if not special then
    if aEffect == "CHOICE_BAND" then
      attack = math.floor(attack * 3 / 2)
    end
    if
      aEffect == "THICK_CLUB"
      and isSpecies(attacker, battle, { [104] = true, [105] = true }, { CUBONE = true, MAROWAK = true })
    then
      attack = attack * 2
    end
    if dEffect == "METAL_POWDER" and isSpecies(defender, battle, { [132] = true }, { DITTO = true }) then
      defense = defense * 2
    end
  else
    local dewNumbers, dewNames = { [407] = true, [408] = true }, { LATIAS = true, LATIOS = true }
    if aEffect == "SOUL_DEW" and isSpecies(attacker, battle, dewNumbers, dewNames) then
      attack = math.floor(attack * 3 / 2)
    end
    if dEffect == "SOUL_DEW" and isSpecies(defender, battle, dewNumbers, dewNames) then
      defense = math.floor(defense * 3 / 2)
    end
    if aEffect == "DEEP_SEA_TOOTH" and isSpecies(attacker, battle, { [373] = true }, { CLAMPERL = true }) then
      attack = attack * 2
    end
    if dEffect == "DEEP_SEA_SCALE" and isSpecies(defender, battle, { [373] = true }, { CLAMPERL = true }) then
      defense = defense * 2
    end
    if aEffect == "LIGHT_BALL" and isSpecies(attacker, battle, { [25] = true }, { PIKACHU = true }) then
      attack = attack * 2
    end
  end
  return attack, defense
end
return D
