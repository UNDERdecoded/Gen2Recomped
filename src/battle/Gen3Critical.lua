-- Native critical command guards, shared by ordinary and scripted GBA hits.
local Version = require("src.core.GameVersion")
local C = {}
local function inflicted(battle)
  return math.floor(tonumber(battle.oakMsgFlags) or 0) % 2 == 1
end
function C.stage(battle, attacker, highCrit)
  local stage = highCrit and 1 or 0
  if battle and Version.isGen3() then
    if attacker.focusEnergy or attacker.expFocusEnergy then
      stage = stage + 2
    end
    -- Native critcalc checks physical item IDs and the current battler species,
    -- independently of mutable held-effect metadata or the retained party mon.
    local item = tonumber(attacker.item)
    if item == nil then
      item = require("src.battle.Gen3AIItemKnowledge").item(battle, attacker)
    end
    local id = attacker.species or (attacker.mon and attacker.mon.species)
    local def = battle.data and battle.data.pokemon and battle.data.pokemon[id]
    local species = tonumber(id) or tonumber(def and (def.index or def.dex))
    if item == 198 then
      stage = stage + 1
    end
    if item == 222 and species == 113 or item == 225 and species == 83 then
      stage = stage + 2
    end
  else
    if attacker.focusEnergy then
      stage = stage + 2
    end
    stage = stage + (attacker.critStage or 0) + require("src.battle.HoldItems").critStages(attacker)
  end
  return math.max(0, math.min(4, stage))
end
function C.roll(battle, draw, ruleset, attacker, moveId, rng, highCrit, data)
  if not battle or not Version.isGen3() then
    return draw(ruleset, attacker, moveId, rng, highCrit, data)
  end
  -- Oak and Emerald's first/tutorial kinds return before consuming RNG.
  if battle.firstBattle and not inflicted(battle) then
    return false
  end
  local kinds = battle.kinds or {}
  if
    Version.get() == "emerald"
    and (battle.firstBattleKind or kinds.firstBattle or battle.wallyTutorial or kinds.tutorial == "wally")
  then
    return false
  end
  local critical = draw(ruleset, attacker, moveId, rng, highCrit, data, battle)
  -- Teachy TV still consumes critcalc's draw, then discards its result.
  if battle.pokedudeDemo or battle.pokedude then
    return false
  end
  return critical
end
function C.noteHit(battle, user, target, dealt, substitute)
  if
    Version.isGen3()
    and battle.firstBattle
    and not substitute
    and dealt > 0
    and user.isPlayer
    and not target.isPlayer
    and not inflicted(battle)
  then
    -- The native HP-damage command updates this after the public hit event.
    battle.oakMsgFlags = (tonumber(battle.oakMsgFlags) or 0) + 1
  end
end
return C
