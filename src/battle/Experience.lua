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
  if consts and consts.gen==2 and not consts.gen3Bag then
    return require('src.pokemon.Gen2Progression').award(defeatedDef,level,numParticipants,
      isTrainer,{traded=traded},consts.exp)
  end
  local divisor, tradedMult, trainerMult = 7, nil, nil
  local tuning = consts and consts.exp
  if tuning then
    divisor = tuning.divisor or divisor
    tradedMult = tuning.tradedMult
    trainerMult = tuning.trainerMult
  end
  local base = math.floor(defeatedDef.baseExp / math.max(1, numParticipants or 1))
  local exp = math.floor(base * level / divisor)
  if consts and (consts.gen == 3 or consts.gen3Bag) then
    -- Emerald computes baseExp * level / 7 before dividing participants.
    exp = math.floor(math.floor(defeatedDef.baseExp * level / divisor)
      / math.max(1, numParticipants or 1))
  end
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
                          numParticipants, traded, opts)
  opts=opts or{}
  local speciesDef = require('src.pokemon.Gen4Forms').definition(data,mon)
  local gsc=require('src.core.GameVersion').isGen2()and not (data.constants and data.constants.gen3Bag)
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
  elseif not gsc then
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
  local lucky=gsc and HeldItems.itemKey(data,mon)=='LUCKY_EGG'
  local function gain(c)
    if gsc then
      return require('src.pokemon.Gen2Progression').award(c.defeatedDef,c.level,c.participants,c.isTrainer,
        {traded=c.traded,halved=c.halved,luckyEgg=c.luckyEgg},consts and consts.exp)
    end
    return Experience.gainFor(c.defeatedDef,c.level,c.isTrainer,c.participants,c.traded,consts)
  end
  if Runtime.wantsHook("exp.gain") then
    local context={defeatedDef=defeatedDef,level=level,isTrainer=isTrainer,
      participants=numParticipants,traded=traded,mon=mon}
    if gsc then
      context.halved=opts.halved or false;context.luckyEgg=lucky
      context.battle,context.loser=opts.battle,opts.loser
    end
    gained = Runtime.call("exp.gain",gain,context)
  else
    gained=gain{defeatedDef=defeatedDef,level=level,isTrainer=isTrainer,participants=numParticipants,
      traded=traded,halved=opts.halved,luckyEgg=lucky}
  end
  -- Lucky Egg is a per-recipient x1.5 held-item boost in Generation II.
  if not gsc then gained = HeldItems.modifyExperience(data, mon, gained)end
  if gsc and not Stats.isGen3(speciesDef)then
    -- Source GiveExperiencePass resolves exp.gain first, then awards effort
    -- before the level/stat recalculation. Hook edits must be visible here.
    require('src.pokemon.Gen2Progression').nativeStatExp(mon,defeatedDef,numParticipants,
      require('src.pokemon.Gen2PokerusByte').doublesStatExp(mon),opts.halved)
  end
  return Experience.add(data, mon, gained)
end

-- Shared absolute award: scripted rewards use native growth, stats and events.
-- Defeat-only EVs, held boosts and exp.gain remain in apply above.
function Experience.add(data, mon, gained)
  assert(type(gained)=='number'and gained==gained and gained>=0 and gained%1==0,'invalid experience award')
  local speciesDef=require('src.pokemon.Gen4Forms').definition(data,mon)
  local consts=data.constants
  if require('src.core.GameVersion').isGen2()and not Stats.isGen3(speciesDef)
      and not (consts and consts.gen3Bag)then
    local result=require('src.pokemon.Gen2Progression').gainExperience(mon,gained,data,
      {native=true,cap=consts and consts.levelCap or 100})
    local levels={};for level=(result.from or 0)+1,result.to or 0 do levels[#levels+1]=level end
    return levels,gained
  end
  mon.exp = mon.exp + gained

  local cap = consts and consts.levelCap or 100
  local levels = {}
  local newLevel = Growth.levelForExp(speciesDef.growthRate, mon.exp, cap,
                                      data.growth_rates)
  while mon.level < math.min(newLevel, cap) do
    mon.level = mon.level + 1
    local old = mon.stats
    if Stats.isGen3(speciesDef) then
      mon.stats = Stats.calcGen3(speciesDef, mon.level, mon.ivs, mon.evs,
                                 mon.nature)
    else
      mon.stats = Stats.calc(speciesDef, mon.level, mon.dvs, mon.statExp)
    end
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
