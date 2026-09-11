-- Experience gain (engine/battle/experience.asm):
--   exp = floor(baseExp * enemyLevel / 7) for a single participant
--   (trainer battles multiply by 1.5 in Gen 1)
-- Stat experience: the defeated species' base stats are added to each
-- participant's stat exp.

local Growth = require("src.pokemon.Growth")
local Runtime = require("src.mods.Runtime")
local Stats = require("src.pokemon.Stats")
local HeldItems = require("src.battle.HeldItems")

local Experience = {}

-- engine/battle/experience.asm order: baseExp is divided by the
-- participant count FIRST, then *level/7, then the traded x1.5
-- (BoostExp) and finally the trainer x1.5.
--
-- EXP.ALL (core.asm .halveExpDataLoop): the base values are halved,
-- GainExperience runs for the participants, then reruns for the whole
-- party -- and because DivideExpDataByNumMonsGainingExp divides the
-- base values IN PLACE, the second pass inherits the participant
-- division: each party member gets (base/2)/participants/partyCount.
-- Sequential floor divisions equal one floor division by the product,
-- so callers pass numParticipants = 2*participants for the first pass
-- and 2*participants*partyCount for the whole-party pass.
--
-- consts is Data.constants; a constants.exp record can retune the
-- divisor and the traded/trainer multipliers, with the values above as
-- the defaults.
function Experience.gainFor(defeatedDef, level, isTrainer, numParticipants,
                            traded, consts)
  local divisor, tradedMult, trainerMult = 7, nil, nil
  local tuning = consts and consts.exp
  if tuning then
    divisor = tuning.divisor or divisor
    tradedMult = tuning.tradedMult
    trainerMult = tuning.trainerMult
  end
  local base = math.floor(defeatedDef.baseExp / math.max(1, numParticipants or 1))
  local exp = math.floor(base * level / divisor)
  if traded then
    exp = math.floor(exp * (tradedMult or 1.5))
  end
  if isTrainer then
    exp = math.floor(exp * (trainerMult or 1.5))
  end
  return math.max(1, exp)
end

-- MonGainEVs (pokemon.c): each stat takes what the defeated species yields,
-- refusing a stat already at 255 and stopping outright at 510 between them.
-- The order matters at the ceiling -- the last stat to be offered is the one
-- that goes without -- and it is the order the yield itself is packed in.
Experience.MAX_EV_PER_STAT = 255
Experience.MAX_EV_TOTAL = 510

function Experience.awardEVs(mon, yield)
  if type(yield) ~= "table" then return end
  mon.evs = mon.evs or {}
  local total = 0
  for _, key in ipairs(Stats.ORDER_GEN3) do
    total = total + (mon.evs[key] or 0)
  end
  for _, key in ipairs(Stats.ORDER_GEN3) do
    local gain = tonumber(yield[key]) or 0
    if gain > 0 and total < Experience.MAX_EV_TOTAL then
      local have = mon.evs[key] or 0
      gain = math.min(gain, Experience.MAX_EV_PER_STAT - have,
                      Experience.MAX_EV_TOTAL - total)
      if gain > 0 then
        mon.evs[key] = have + gain
        total = total + gain
      end
    end
  end
end

-- Applies exp/stat exp; returns the list of levels gained plus the raw
-- exp delta (wExpAmountGained, printed by _ExpPointsText -- captured
-- before the max-level cap, experience.asm:92-100).
function Experience.apply(data, mon, defeatedDef, level, isTrainer,
                          numParticipants, traded)
  local speciesDef = data.pokemon[mon.species]
  if Stats.isGen3(speciesDef) then
    -- GEN 3 DOES NOT AWARD STAT EXPERIENCE, it awards EFFORT VALUES, and the
    -- two are not the same thing wearing a different name: stat exp is the
    -- defeated mon's whole base stat, divided among the participants, into a
    -- 65535-wide slot; an EV is the one to three points its evYield names,
    -- given in full to everybody who fought, into a slot 255 wide with 510
    -- to share between the six.
    --
    -- Nothing awarded them.  Every Pokemon in Hoenn stayed at zero EVs for
    -- its whole life -- worth up to 63 points of a stat at level 100, and
    -- the difference between a raised Pokemon and a wild one at every level
    -- before that.
    Experience.awardEVs(mon, defeatedDef.evYield)
  else
    -- stat exp is divided among participants too
    -- (DivideExpDataByNumMonsGainingExp divides wEnemyMonBaseStats)
    local statShare = math.max(1, numParticipants or 1)
    for _, key in ipairs(Stats.ORDER) do
      local gain = math.floor(defeatedDef.baseStats[key] / statShare)
      mon.statExp[key] = math.min(65535, (mon.statExp[key] or 0) + gain)
    end
  end
  local consts = data.constants
  local gained
  if Runtime.wantsHook("exp.gain") then
    gained = Runtime.call("exp.gain", function(c)
      return Experience.gainFor(c.defeatedDef, c.level, c.isTrainer,
                                c.participants, c.traded, consts)
    end, { defeatedDef = defeatedDef, level = level, isTrainer = isTrainer,
           participants = numParticipants, traded = traded, mon = mon })
  else
    gained = Experience.gainFor(defeatedDef, level, isTrainer,
                                numParticipants, traded, consts)
  end
  -- Lucky Egg is a per-recipient x1.5 held-item boost in Generation II.
  gained = HeldItems.modifyExperience(data, mon, gained)
  mon.exp = mon.exp + gained

  local cap = consts and consts.levelCap or 100
  local levels = {}
  local newLevel = Growth.levelForExp(speciesDef.growthRate, mon.exp, cap,
                                      data.growth_rates)
  while mon.level < math.min(newLevel, cap) do
    mon.level = mon.level + 1
    local old = mon.stats
    mon.stats = Stats.calc(speciesDef, mon.level, mon.dvs, mon.statExp)
    mon.hp = math.min(mon.stats.hp, mon.hp + (mon.stats.hp - old.hp))
    table.insert(levels, mon.level)
    if Runtime.wants("pokemon.level_up") then
      Runtime.emit("pokemon.level_up", {
        mon = mon, level = mon.level, prevLevel = mon.level - 1,
        learnable = Experience.movesLearnedAt(speciesDef, mon.level),
      })
    end
  end
  return levels, gained
end

-- Moves learned when reaching exactly `level`.
function Experience.movesLearnedAt(speciesDef, level)
  local out = {}
  for _, entry in ipairs(speciesDef.learnset) do
    if entry.level == level then
      table.insert(out, entry.move)
    end
  end
  return out
end

return Experience
