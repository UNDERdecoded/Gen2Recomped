-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM / HEARTGOLD / SOULSILVER'S DAMAGE FORMULA, in the cartridge's order.
--
-- Damage.compute is Gen 1's formula grown sideways: it quartered both stats
-- once either passed 255 (GetDamageVars .scaleStats, a Game Boy byte limit),
-- capped the base at 997, applied the weather AFTER the +2, the random roll
-- AFTER STAB and the type chart, the type items to the finished number, and
-- knew none of Sinnoh's formula abilities (Technician, Adaptability, Sniper,
-- Filter / Solid Rock, Tinted Lens, Heatproof, Dry Skin, Iron Fist, Rivalry,
-- Normalize, Scrappy, Simple, Unaware, Solar Power, Flower Gift, Slow Start,
-- Plus / Minus, Super Luck) or items (plates, orbs, Muscle Band, Wise
-- Glasses, Choice Specs, Life Orb, Metronome, Expert Belt). On a level 50+
-- Pokemon every one of those is a visible number.
--
-- READ FROM CODE (pokeplatinum; pokeheartgold's battle_command.c /
-- overlay_12 carry the same routines):
--   BattleSystem_CalcMoveDamage (src/battle/battle_lib.c)   -> base()
--   BattleScript_CalcMoveDamage (battle_script.c): x criticalMul, Life Orb
--     x(100+30)/100, Metronome x(10+n)/10, Me First x15/10
--   BattleSystem_CalcDamageVariance: x(100 - rand%16)/100, at least 1
--   BattleSystem_ApplyTypeChart: STAB x15/10 (Adaptability x2), each chart
--     row damage*mul/10 (BattleSystem_Divide: never below 1), Wonder Guard,
--     Filter / Solid Rock x3/4, Expert Belt x(100+param)/100, Tinted Lens x2
--   BattleSystem_CalcCriticalMulti: stages 1/16 1/8 1/4 1/3 1/2, Focus
--     Energy +2, Scope Lens +1, Super Luck +1, Lucky Punch / Stick +2;
--     Battle Armor / Shell Armor / Lucky Chant refuse; Sniper makes it x3
-- INFERRED: the resist berries (WEAKEN_SE_*) halve the damage after the type
-- chart; no C routine in either decomp names them (they live in code still
-- in asm), so the placement is Gen 5's (src/battle/Gen5HoldItems.lua).
--
-- The contract is Damage.compute's: returns damage, { crit, typeMult[,
-- ability] }, damage 0 with typeMult 0 for an immunity.

local Abilities = require("src.battle.Abilities")
local TypeChart = require("src.battle.TypeChart")
local Runtime = require("src.mods.Runtime")

local G = {}

local floor = math.floor

local function H() return require("src.battle.Gen5HoldItems") end
local function norm(t) return Abilities.normalizeType(t) end

-- sStatStageBoosts: { num, den } for -6..+6
local STAGE = {
  [-6] = { 10, 40 }, [-5] = { 10, 35 }, [-4] = { 10, 30 }, [-3] = { 10, 25 },
  [-2] = { 10, 20 }, [-1] = { 10, 15 }, [0] = { 10, 10 }, [1] = { 15, 10 },
  [2] = { 20, 10 }, [3] = { 25, 10 }, [4] = { 30, 10 }, [5] = { 35, 10 }, [6] = { 40, 10 },
}
G.STAGE = STAGE
local function clampStage(s) return math.max(-6, math.min(6, s or 0)) end
local function staged(stat, s)
  local f = STAGE[clampStage(s)]
  return floor(stat * f[1] / f[2])
end

-- sCriticalStageRates
local CRIT_DEN = { [0] = 16, 8, 4, 3, 2 }
G.CRIT_DEN = CRIT_DEN

-- sPunchingMoves (Platinum move ids); a BW record says so in its flags
local PUNCH = { [8] = true, [7] = true, [9] = true, [183] = true, [264] = true, [146] = true,
                [223] = true, [359] = true, [5] = true, [4] = true, [309] = true, [325] = true,
                [409] = true, [418] = true, [327] = true }
G.PUNCH = PUNCH

local STRUGGLE, SOLAR_BEAM = 165, 76
local PIKACHU, CUBONE, MAROWAK, CLAMPERL, LATIAS, LATIOS, DITTO = 25, 104, 105, 366, 380, 381, 132
local DIALGA, PALKIA, GIRATINA = 483, 484, 487

local function hasType(b, t)
  for _, x in ipairs(b and b.curTypes or {}) do if norm(x) == t then return true end end
  return false
end
local function species(b) return tonumber(b and b.mon and b.mon.species) end
local function maxHP(b)
  local m = b and b.mon
  return (m and m.stats and m.stats.hp) or (m and (m.maxHP or m.maxHp)) or 1
end
local function stage(b, stat)
  local st = b and b.stages
  if not st then return 0 end
  if st[stat] then return st[stat] end
  if stat == "spatk" or stat == "spdef" then return st.special or 0 end
  return 0
end
local function statOf(b, stat)
  local cs = b.curStats or (b.mon and b.mon.stats) or {}
  return cs[stat] or cs.special or 1
end

-- the held item's Platinum hold effect and parameter (Klutz / Embargo aware)
local function item(b)
  local he, param = H().held(b)
  return he, param or 0
end

local function genderOf(data, b)
  local ok, g = pcall(function() return require("src.pokemon.Pokemon").genderOf(data, b.mon) end)
  if ok then return g end
  return b.mon and b.mon.gender
end

-- Battler_IgnorableAbility: the defender's ability, unless the attacker has
-- Mold Breaker
local function ignorable(attacker, defender)
  if Abilities.of(attacker) == "MOLD_BREAKER" then return nil end
  return Abilities.of(defender)
end
G.ignorable = ignorable

-- any living battler on `b`'s side (b included) with `ability`
local function sideHas(battle, b, ability)
  if not battle then return Abilities.of(b) == ability end
  local list = {}
  if battle.sides then
    local side = battle.sides[b.isPlayer and 1 or 2]
    for _, x in ipairs(side and side.battlers or {}) do list[#list + 1] = x end
  end
  if #list == 0 then list = { b } end
  for _, x in ipairs(list) do
    if x and x.mon and (x.mon.hp or 0) > 0 and Abilities.of(x) == ability then return true end
  end
  return false
end
local function allyHas(battle, b, ability)
  if not (battle and battle.sides) then return false end
  local side = battle.sides[b.isPlayer and 1 or 2]
  for _, x in ipairs(side and side.battlers or {}) do
    if x ~= b and x.mon and (x.mon.hp or 0) > 0 and Abilities.of(x) == ability then return true end
  end
  return false
end

-- The move's type as the formula sees it (Normalize makes everything Normal)
function G.moveType(attacker, move)
  if Abilities.of(attacker) == "NORMALIZE" then return "NORMAL" end
  return norm(move.type)
end

-- BattleSystem_CalcCriticalMulti: 1, 2 or 3 (Sniper)
function G.critMul(ruleset, attacker, defender, move, opts)
  local crit = opts.forceCrit
  local dab = ignorable(attacker, defender)
  if dab == "BATTLE_ARMOR" or dab == "SHELL_ARMOR" then crit = false end
  if crit == nil then
    local rng = opts.rng or love.math.random
    local high = move.highCrit
    if opts.highCrit ~= nil then high = opts.highCrit end
    if Runtime.wantsHook("battle.crit") then
      crit = Runtime.call("battle.crit", function(c)
        return require("src.battle.Damage").critRoll(c.ruleset, c.attacker, c.moveId, c.rng, c.highCrit, c.data)
      end, { ruleset = ruleset, attacker = attacker, moveId = move.id, rng = rng,
             highCrit = high, data = opts.data })
    else
      local s = 0
      if high then s = s + 1 end
      s = s + (tonumber(move.critStage) or 0)
      if attacker.focusEnergy then s = s + 2 end
      if attacker.critStage then s = s + attacker.critStage end
      s = s + require("src.battle.HoldItems").critStages(attacker)
      if Abilities.of(attacker) == "SUPER_LUCK" then s = s + 1 end
      local den = CRIT_DEN[math.max(0, math.min(4, s))]
      crit = rng(1, den) == 1
    end
  end
  if not crit then return 1 end
  if Abilities.of(attacker) == "SNIPER" then return 3 end
  return 2
end

-- BattleSystem_CalcMoveDamage, returning (damage incl. the +2, info)
function G.base(attacker, defender, move, mtype, critMul, opts)
  local battle = opts.g4Battle or opts.battle or require("src.battle.Gen45Abilities").battle or H().current
  local data = opts.data or (battle and battle.data)
  local aab, dab = Abilities.of(attacker), ignorable(attacker, defender)
  local ahe, apow = item(attacker)
  local dhe, dpow = item(defender)
  local asp, dsp = species(attacker), species(defender)
  local cls = move.class or move.category
  local special = cls == "special"
  local typeless = opts.typeless

  local atk, def = statOf(attacker, "attack"), statOf(defender, "defense")
  local spa, spd = statOf(attacker, "spatk"), statOf(defender, "spdef")
  local atkS, defS = stage(attacker, "attack"), stage(defender, "defense")
  local spaS, spdS = stage(attacker, "spatk"), stage(defender, "spdef")
  local level = (attacker.mon and attacker.mon.level) or 1

  local power = tonumber(move.power) or 0
  if opts.powerMultiplier and opts.powerMultiplier ~= 1 then
    power = math.max(1, floor(power * opts.powerMultiplier))
  end
  if attacker.charged and mtype == "ELECTRIC" then power = power * 2 end
  if opts.helpingHand or require("src.battle.Gen4MoveEffectsExtra").helped(battle, attacker) then
    power = floor(power * 15 / 10)
  end
  if aab == "TECHNICIAN" and move.id ~= STRUGGLE and power <= 60 then power = floor(power * 15 / 10) end

  if aab == "HUGE_POWER" or aab == "PURE_POWER" then atk = atk * 2 end
  if aab == "SLOW_START" and (attacker.g4SlowStart or 0) > 0 then atk = floor(atk / 2) end

  if not typeless then
    local boost = H().BOOST[ahe]
    if boost and boost == mtype then power = floor(power * (100 + apow) / 100) end
  end
  if ahe == H().HE.CHOICE_ATK then atk = floor(atk * 150 / 100) end
  if ahe == H().HE.CHOICE_SPATK then spa = floor(spa * 150 / 100) end
  local frontier = battle and battle.frontier
  if ahe == H().HE.SOUL_DEW and not frontier and (asp == LATIOS or asp == LATIAS) then spa = floor(spa * 150 / 100) end
  if dhe == H().HE.SOUL_DEW and not frontier and (dsp == LATIOS or dsp == LATIAS) then spd = floor(spd * 150 / 100) end
  if ahe == H().HE.CLAMPERL_SPATK and asp == CLAMPERL then spa = spa * 2 end
  if dhe == H().HE.CLAMPERL_SPDEF and dsp == CLAMPERL then spd = spd * 2 end
  if ahe == H().HE.LIGHT_BALL and asp == PIKACHU then power = power * 2 end
  if dhe == H().HE.METAL_POWDER and dsp == DITTO then def = def * 2 end
  if ahe == H().HE.THICK_CLUB and (asp == CUBONE or asp == MAROWAK) then atk = atk * 2 end
  if ahe == 3 and asp == DIALGA and (mtype == "DRAGON" or mtype == "STEEL") then power = floor(power * (100 + apow) / 100) end
  if ahe == 4 and asp == PALKIA and (mtype == "DRAGON" or mtype == "WATER") then power = floor(power * (100 + apow) / 100) end
  if ahe == 2 and asp == GIRATINA and not attacker.transformed and (mtype == "DRAGON" or mtype == "GHOST") then
    power = floor(power * (100 + apow) / 100)
  end
  if ahe == H().HE.MUSCLE_BAND and cls == "physical" then power = floor(power * (100 + apow) / 100) end
  if ahe == H().HE.WISE_GLASSES and special then power = floor(power * (100 + apow) / 100) end

  if dab == "THICK_FAT" and (mtype == "FIRE" or mtype == "ICE") then power = floor(power / 2) end
  if aab == "HUSTLE" then atk = floor(atk * 150 / 100) end
  local astatus = attacker.mon and attacker.mon.status
  if aab == "GUTS" and astatus then atk = floor(atk * 150 / 100) end
  if dab == "MARVEL_SCALE" and defender.mon and defender.mon.status then def = floor(def * 150 / 100) end
  if (aab == "PLUS" and sideHas(battle, attacker, "MINUS")) or (aab == "MINUS" and sideHas(battle, attacker, "PLUS")) then
    spa = floor(spa * 150 / 100)
  end
  for _, muted in pairs(opts.sports or {}) do
    if muted == mtype then power = floor(power / 2) end
  end
  local pinch = Abilities.PINCH[aab]
  if pinch and pinch == mtype and (attacker.mon.hp or 0) <= floor(maxHP(attacker) / 3) then
    power = floor(power * 150 / 100)
  end
  if mtype == "FIRE" and dab == "HEATPROOF" then power = floor(power / 2) end
  if mtype == "FIRE" and dab == "DRY_SKIN" then power = floor(power * 125 / 100) end

  if aab == "SIMPLE" then atkS, spaS = clampStage(atkS * 2), clampStage(spaS * 2) end
  if dab == "SIMPLE" then defS, spdS = clampStage(defS * 2), clampStage(spdS * 2) end
  if dab == "UNAWARE" then atkS, spaS = 0, 0 end
  if aab == "UNAWARE" then defS, spdS = 0, 0 end

  if aab == "RIVALRY" and data then
    local ga, gd = genderOf(data, attacker), genderOf(data, defender)
    if ga and gd and ga ~= "none" and gd ~= "none" then
      if ga == gd then power = floor(power * 125 / 100) else power = floor(power * 75 / 100) end
    end
  end
  if aab == "IRON_FIST" and (PUNCH[tonumber(move.id)] or move.punch) then power = floor(power * 12 / 10) end

  local weather = opts.weather
  if weather == "SUN" and aab == "SOLAR_POWER" then spa = floor(spa * 15 / 10) end
  if weather == "SANDSTORM" and hasType(defender, "ROCK") then spd = floor(spd * 15 / 10) end
  if weather == "SUN" and sideHas(battle, attacker, "FLOWER_GIFT") then atk = floor(atk * 15 / 10) end
  if weather == "SUN" and aab ~= "MOLD_BREAKER" and sideHas(battle, defender, "FLOWER_GIFT") then
    spd = floor(spd * 15 / 10)
  end
  if opts.explode then def = floor(def / 2) end

  local A, As, D, Ds
  if special then A, As, D, Ds = spa, spaS, spd, spdS else A, As, D, Ds = atk, atkS, def, defS end
  local d
  if critMul > 1 and As <= 0 then d = A else d = staged(A, As) end
  d = d * power
  d = d * (floor(level * 2 / 5) + 2)
  local divisor
  if critMul > 1 and Ds >= 0 then divisor = D else divisor = staged(D, Ds) end
  d = floor(d / math.max(1, divisor))
  d = floor(d / 50)

  if not special and astatus == "BRN" and aab ~= "GUTS" then d = floor(d / 2) end
  if critMul == 1 and not opts.breaksScreens then
    local screens = opts.screens
    if screens == nil and not typeless then screens = defender end
    local up = screens and ((special and screens.lightScreen) or (not special and screens.reflect))
    if up then
      if opts.doublesScreens then d = floor(d * 2 / 3) else d = floor(d / 2) end
    end
  end
  if opts.spread then d = floor(d * 3 / 4) end

  if weather and not typeless then
    if weather == "RAIN" then
      if mtype == "FIRE" then d = floor(d / 2) elseif mtype == "WATER" then d = floor(d * 15 / 10) end
    end
    if (weather == "RAIN" or weather == "SANDSTORM" or weather == "HAIL") and tonumber(move.id) == SOLAR_BEAM then
      d = floor(d / 2)
    end
    if weather == "SUN" then
      if mtype == "FIRE" then d = floor(d * 15 / 10) elseif mtype == "WATER" then d = floor(d / 2) end
    end
  end
  if attacker.flashFire and aab == "FLASH_FIRE" and mtype == "FIRE" then d = floor(d * 15 / 10) end
  return d + 2
end

-- Metronome (the item): +10% a consecutive use of the same move, at most x2
-- (BattleSystem_UpdateMetronomeCount: the counter starts at 0)
local function metronomeTurns(attacker, move, battle)
  local m = attacker.g4MetronomeItem
  local turn = battle and battle.turnCount or 0
  if not (m and m.id == move.id) then
    m = { id = move.id, turn = turn, n = 0 }
  elseif m.turn ~= turn then
    m.n, m.turn = math.min(10, m.n + 1), turn
  end
  attacker.g4MetronomeItem = m
  return m.n
end

-- one type matchup, the way ApplyTypeChart walks it: the multiplier each of
-- the defender's types gives, with the rows the field / Foresight lift
local function rowsFor(attacker, defender, mtype, opts)
  local out, seen = {}, {}
  local scrappy = Abilities.of(attacker) == "SCRAPPY"
  local identified = defender.identified or defender.g4Foresight
  for _, t in ipairs(defender.curTypes or {}) do
    local dt = norm(t)
    if dt and not seen[dt] then
      seen[dt] = true
      local m = TypeChart.effectiveness(mtype, { t })
      if m == 0 then
        if dt == "GHOST" and (mtype == "NORMAL" or mtype == "FIGHTING") and (identified or scrappy) then
          m = nil
        elseif opts.liftImmunity and ((dt == "FLYING" and mtype == "GROUND") or (dt == "DARK" and mtype == "PSYCHIC")) then
          m = nil
        end
      end
      if m and m ~= 10 then out[#out + 1] = m end
    end
  end
  return out
end

function G.compute(ruleset, attacker, defender, move, opts)
  opts = opts or {}
  if (tonumber(move.power) or 0) == 0 or move.category == "status" or move.class == "status" then
    return 0, { crit = false, typeMult = 10 }
  end
  local battle = opts.g4Battle or opts.battle or require("src.battle.Gen45Abilities").battle or H().current
  local rng = opts.rng or love.math.random
  local mtype = opts.typeless and norm(move.type) or G.moveType(attacker, move)
  local typed = not opts.typeless and tonumber(move.id) ~= STRUGGLE
  local view = move
  if mtype ~= norm(move.type) then
    view = setmetatable({ type = mtype }, { __index = move })
  end

  -- immunities the ability gives (Levitate, the absorbs) and Magnet Rise /
  -- Gravity / Iron Ball (src/battle/Gen4MoveEffects.lua liftsImmunity)
  local lift, grounded = false, false
  if typed and battle then
    local l, gnd, immune = require("src.battle.Gen4MoveEffects").liftsImmunity(defender, view, battle)
    if immune then return 0, { crit = false, typeMult = 0 } end
    lift, grounded = l, gnd
  end
  if typed and Abilities.of(attacker) ~= "MOLD_BREAKER" and Abilities.blocks(defender, view)
     and not (grounded and Abilities.of(defender) == "LEVITATE") then
    return 0, { crit = false, typeMult = 0, ability = Abilities.of(defender) }
  end

  -- Brick Break: BATTLE_EFFECT_REMOVE_SCREENS skips the screens
  if type(move.effect) == "string" and move.effect:find("BRICK_BREAK", 1, true) then
    opts.breaksScreens = true
  end
  local critMul = G.critMul(ruleset, attacker, defender, move, opts)
  local d = G.base(attacker, defender, move, mtype, critMul, opts)
  d = d * critMul

  local ahe, apow = item(attacker)
  if not opts.typeless then
    if ahe == H().HE.LIFE_ORB then
      d = floor(d * (100 + apow) / 100)
      if not opts.dryRun then attacker.bwLifeOrbHit = true end
    end
    if ahe == H().HE.METRONOME then
      local n = opts.dryRun and ((attacker.g4MetronomeItem or {}).n or 0) or metronomeTurns(attacker, move, battle)
      d = floor(d * (10 + n) / 10)
    end
    if opts.meFirst then d = floor(d * 15 / 10) end
  end

  -- BattleSystem_CalcDamageVariance
  if d ~= 0 then
    local r = rng(ruleset.randMin or 85, ruleset.randMax or 100)
    d = floor(d * r / 100)
    if d == 0 then d = 1 end
  end
  if not typed then
    return math.max(1, d), { crit = critMul > 1, typeMult = 10 }
  end

  -- BattleSystem_ApplyTypeChart
  local aab = Abilities.of(attacker)
  if hasType(attacker, mtype) then
    if aab == "ADAPTABILITY" then d = d * 2 else d = floor(d * 15 / 10) end
  end
  local rows = rowsFor(attacker, defender, mtype, { liftImmunity = lift })
  local mult = 10
  for _, m in ipairs(rows) do
    if m == 0 then return 0, { crit = false, typeMult = 0 } end
    mult = floor(mult * m / 10)
    d = math.max(1, floor(d * m / 10))
  end
  local dab = ignorable(attacker, defender)
  if dab == "WONDER_GUARD" and mult <= 10 then
    return 0, { crit = false, typeMult = 0, ability = "WONDER_GUARD" }
  end
  if mult > 10 then
    if dab == "FILTER" or dab == "SOLID_ROCK" then d = math.max(1, floor(d * 3 / 4)) end
    if ahe == H().HE.EXPERT_BELT then d = floor(d * (100 + apow) / 100) end
  elseif mult < 10 then
    if aab == "TINTED_LENS" then d = d * 2 end
  end
  -- INFERRED placement: the resist berries
  d = H().resistBerry(attacker, defender, view, mult, d, opts.dryRun)
  -- the after-hit seam (Shell Bell, Life Orb's recoil, Jaboca...) reads these
  -- (not for the trainer AI's estimate, opts.dryRun: src/battle/Gen3AI.lua)
  if not opts.dryRun then
    attacker.bwLastTarget, attacker.bwLastMove, attacker.bwLastMult = defender, move, mult
  end
  return math.max(1, d), { crit = critMul > 1, typeMult = mult }
end

-- ===========================================================================
-- BLACK / WHITE (INFERRED: no BW decomp; the well-established Gen 5 formula)
-- ===========================================================================
-- Every multiplier is a 4096ths fraction; a chain of them is folded with
-- (m * x + 2048) >> 12 and applied with "pokeRound" (round half down). Order:
--   power  x chain(Technician, Flare / Toxic Boost, Analytic, Reckless, Iron
--          Fist, Sand Force, Rivalry, Heatproof, Dry Skin, type items /
--          plates / orbs, Muscle Band, Wise Glasses, gems, Solar Beam in
--          non-sun weather, the sports)  (Sheer Force, Helping Hand and Me
--          First already ride in opts.powerMultiplier, from G5.damage)
--   attack x chain(Thick Fat, Guts, Flash Fire, Plus / Minus, Solar Power,
--          Flower Gift, Defeatist, Slow Start, Choice Band / Specs, Light Ball,
--          Thick Club, DeepSeaTooth, Soul Dew), Huge Power / Hustle on the stat
--   defence x chain(Marvel Scale, Flower Gift, Eviolite, Metal Powder,
--          DeepSeaScale, Soul Dew); sand gives Rock x1.5 Sp. Def
--   base = floor(floor(floor(2L/5+2) * P * A / D) / 50) + 2
--   spread x3072, weather x6144 / x2048, crit x2, random 85..100 / 100,
--   STAB x6144 (Adaptability x8192), each type row, burn / 2 (physical, no
--   Guts), final chain(screens 2048 / 2703, Multiscale 2048, Tinted Lens
--   8192, Friend Guard 3072, Sniper 6144, Filter / Solid Rock 3072,
--   Metronome 4096 + 819n, Expert Belt 4915, Life Orb 5324), resist berry.
local function pokeRound(x)
  local f = floor(x)
  if x - f > 0.5 then return f + 1 end
  return f
end
G.pokeRound = pokeRound
local function chain(list)
  local m = 4096
  for _, x in ipairs(list) do m = floor((m * x + 2048) / 4096) end
  return m
end
local function applyMod(v, m)
  if m == 4096 then return v end
  return pokeRound(v * m / 4096)
end
G.chain, G.applyMod = chain, applyMod

local MOLD = { MOLD_BREAKER = true, TERAVOLT = true, TURBOBLAZE = true }
local function ignorable5(attacker, defender)
  if MOLD[Abilities.of(attacker)] then return nil end
  return Abilities.of(defender)
end

function G.critMul5(ruleset, attacker, defender, move, opts)
  local crit = opts.forceCrit
  local dab = ignorable5(attacker, defender)
  if dab == "BATTLE_ARMOR" or dab == "SHELL_ARMOR" then crit = false end
  if crit == nil then
    local rng = opts.rng or love.math.random
    local high = move.highCrit
    if opts.highCrit ~= nil then high = opts.highCrit end
    if Runtime.wantsHook("battle.crit") then
      crit = Runtime.call("battle.crit", function(c)
        return require("src.battle.Damage").critRoll(c.ruleset, c.attacker, c.moveId, c.rng, c.highCrit, c.data)
      end, { ruleset = ruleset, attacker = attacker, moveId = move.id, rng = rng,
             highCrit = high, data = opts.data })
    else
      local s = tonumber(move.critStage) or 0
      if high and s == 0 then s = 1 end
      if attacker.focusEnergy then s = s + 2 end
      if attacker.critStage then s = s + attacker.critStage end
      s = s + require("src.battle.HoldItems").critStages(attacker)
      if Abilities.of(attacker) == "SUPER_LUCK" then s = s + 1 end
      crit = rng(1, CRIT_DEN[math.max(0, math.min(4, s))]) == 1
    end
  end
  return crit and true or false
end

function G.computeGen5(ruleset, attacker, defender, move, opts)
  opts = opts or {}
  if (tonumber(move.power) or 0) == 0 or move.category == "status" or move.class == "status" then
    return 0, { crit = false, typeMult = 10 }
  end
  local battle = opts.bwBattle or opts.battle or require("src.battle.Gen45Abilities").battle or H().current
  local data = opts.data or (battle and battle.data)
  local rng = opts.rng or love.math.random
  local turn = battle and battle.turnCount or 0
  local G45 = require("src.battle.Gen45Abilities")
  -- TELEPATHY: a partner's attack misses it (INFERRED)
  if not opts.typeless and G45.telepathyBlocks(attacker, defender) then
    return 0, { crit = false, typeMult = 0, ability = "TELEPATHY" }
  end
  local typeless = opts.typeless
  local mtype = typeless and norm(move.type) or G.moveType(attacker, move)
  local typed = not typeless and tonumber(move.id) ~= STRUGGLE
  local view = move
  if mtype ~= norm(move.type) then view = setmetatable({ type = mtype }, { __index = move }) end
  local aab, dab = Abilities.of(attacker), ignorable5(attacker, defender)
  local HI = H()
  local ahe, apow, adef, aid = HI.held(attacker)
  local dhe, _, _, did = HI.held(defender)
  apow = apow or 0
  local asp, dsp = species(attacker), species(defender)
  local cls = move.class or move.category
  local special = cls == "special"
  local weather = opts.weather

  -- immunities (Ring Target, Gravity, Smack Down, an Iron Ball lift them)
  local lift, grounded = false, false
  if typed then
    lift, grounded = HI.liftsImmunity(defender, view, battle)
    if Abilities.blocks(defender, view) and not MOLD[aab]
       and not (grounded and Abilities.of(defender) == "LEVITATE") then
      return 0, { crit = false, typeMult = 0, ability = Abilities.of(defender) }
    end
  end

  local crit = G.critMul5(ruleset, attacker, defender, move, opts)

  -- power
  local power = tonumber(move.power) or 0
  if opts.powerMultiplier and opts.powerMultiplier ~= 1 then
    power = math.max(1, floor(power * opts.powerMultiplier))
  end
  if attacker.charged and mtype == "ELECTRIC" then power = power * 2 end
  local bp = {}
  local astatus = attacker.mon and attacker.mon.status and tostring(attacker.mon.status):upper()
  if aab == "TECHNICIAN" and power <= 60 then bp[#bp + 1] = 6144 end
  if aab == "FLARE_BOOST" and astatus == "BRN" and special then bp[#bp + 1] = 6144 end
  if aab == "TOXIC_BOOST" and (astatus == "PSN" or astatus == "TOX") and not special then bp[#bp + 1] = 6144 end
  if aab == "ANALYTIC" and defender.bwMovedTurn == turn then bp[#bp + 1] = 5325 end
  if aab == "RECKLESS" and (tonumber(move.recoil) or 0) > 0 then bp[#bp + 1] = 4915 end
  if aab == "IRON_FIST" and (move.punchMove or PUNCH[tonumber(move.id)]) then bp[#bp + 1] = 4915 end
  if aab == "SAND_FORCE" and weather == "SANDSTORM"
     and (mtype == "ROCK" or mtype == "GROUND" or mtype == "STEEL") then bp[#bp + 1] = 5325 end
  if aab == "RIVALRY" and data then
    local ga, gd = genderOf(data, attacker), genderOf(data, defender)
    if ga and gd and ga ~= "none" and gd ~= "none" then bp[#bp + 1] = ga == gd and 5120 or 3072 end
  end
  if dab == "HEATPROOF" and mtype == "FIRE" then bp[#bp + 1] = 2048 end
  if dab == "DRY_SKIN" and mtype == "FIRE" then bp[#bp + 1] = 5120 end
  if not typeless then
    if HI.BOOST[ahe] == mtype then bp[#bp + 1] = 4096 + floor(4096 * apow / 100) end
    if ahe == 3 and asp == DIALGA and (mtype == "DRAGON" or mtype == "STEEL") then bp[#bp + 1] = 4915 end
    if ahe == 4 and asp == PALKIA and (mtype == "DRAGON" or mtype == "WATER") then bp[#bp + 1] = 4915 end
    if ahe == 2 and asp == GIRATINA and (mtype == "DRAGON" or mtype == "GHOST") then bp[#bp + 1] = 4915 end
    if ahe == HI.HE.MUSCLE_BAND and not special then bp[#bp + 1] = 4505 end
    if ahe == HI.HE.WISE_GLASSES and special then bp[#bp + 1] = 4505 end
    if HI.GEM[aid] and HI.GEM[aid] == mtype then
      bp[#bp + 1] = 6144
      if not opts.dryRun then HI.consume(attacker) end
      if battle and battle.sayNext and not opts.dryRun then
        local line = HI.T.std(battle, 182, { (adef and adef.name) or "Gem", move.name })
        if line and line ~= "" then battle:sayNext(line) end
      end
    end
    if tonumber(move.id) == SOLAR_BEAM and weather and weather ~= "SUN" then bp[#bp + 1] = 2048 end
    for _, muted in pairs(opts.sports or {}) do if muted == mtype then bp[#bp + 1] = 2048 end end
  end
  power = math.max(1, applyMod(power, chain(bp)))

  -- attack / defence, stages first (a crit ignores the bad ones)
  local atkStat, defStat = special and "spatk" or "attack", special and "spdef" or "defense"
  local aS, dS = stage(attacker, atkStat), stage(defender, defStat)
  if aab == "SIMPLE" then aS = clampStage(aS * 2) end
  if dab == "SIMPLE" then dS = clampStage(dS * 2) end
  if dab == "UNAWARE" then aS = 0 end
  if aab == "UNAWARE" then dS = 0 end
  if crit and aS < 0 then aS = 0 end
  if crit and dS > 0 then dS = 0 end
  local A = staged(statOf(attacker, atkStat), aS)
  local D = staged(statOf(defender, defStat), dS)
  if not special and (aab == "HUGE_POWER" or aab == "PURE_POWER") then A = A * 2 end
  if not special and aab == "HUSTLE" then A = floor(A * 3 / 2) end
  local am = {}
  if dab == "THICK_FAT" and (mtype == "FIRE" or mtype == "ICE") then am[#am + 1] = 2048 end
  if aab == "GUTS" and astatus and not special then am[#am + 1] = 6144 end
  if attacker.flashFire and aab == "FLASH_FIRE" and mtype == "FIRE" then am[#am + 1] = 6144 end
  -- Gen 5 (INFERRED): Plus and Minus answer to an ally with EITHER of the two,
  -- not only the opposite one (Platinum's CountAbility rule is above, Gen 4)
  if special and (aab == "PLUS" or aab == "MINUS")
     and (allyHas(battle, attacker, "PLUS") or allyHas(battle, attacker, "MINUS")) then
    am[#am + 1] = 6144
  end
  if special and aab == "SOLAR_POWER" and weather == "SUN" then am[#am + 1] = 6144 end
  if not special and weather == "SUN" and sideHas(battle, attacker, "FLOWER_GIFT") then am[#am + 1] = 6144 end
  if aab == "DEFEATIST" and (attacker.mon.hp or 0) * 2 <= maxHP(attacker) then am[#am + 1] = 2048 end
  if not special and aab == "SLOW_START" and (attacker.g4SlowStart or 0) > 0 then am[#am + 1] = 2048 end
  if ahe == HI.HE.CHOICE_ATK and not special then am[#am + 1] = 6144 end
  if ahe == HI.HE.CHOICE_SPATK and special then am[#am + 1] = 6144 end
  if ahe == HI.HE.LIGHT_BALL and asp == PIKACHU then am[#am + 1] = 8192 end
  if ahe == HI.HE.THICK_CLUB and (asp == CUBONE or asp == MAROWAK) and not special then am[#am + 1] = 8192 end
  if ahe == HI.HE.CLAMPERL_SPATK and asp == CLAMPERL and special then am[#am + 1] = 8192 end
  if ahe == HI.HE.SOUL_DEW and (asp == LATIAS or asp == LATIOS) and special then am[#am + 1] = 6144 end
  A = math.max(1, applyMod(A, chain(am)))
  if weather == "SANDSTORM" and special and hasType(defender, "ROCK") then D = floor(D * 3 / 2) end
  local dm = {}
  if dab == "MARVEL_SCALE" and defender.mon.status and not special then dm[#dm + 1] = 6144 end
  if special and weather == "SUN" and not MOLD[aab] and sideHas(battle, defender, "FLOWER_GIFT") then dm[#dm + 1] = 6144 end
  if did == HI.ID.EVIOLITE then
    local def = data and data.pokemon and data.pokemon[defender.mon.species]
    if type(def) == "table" and type(def.evolutions) == "table" and next(def.evolutions) ~= nil then dm[#dm + 1] = 6144 end
  end
  if dhe == HI.HE.METAL_POWDER and dsp == DITTO and not special and not defender.transformed then dm[#dm + 1] = 8192 end
  if dhe == HI.HE.CLAMPERL_SPDEF and dsp == CLAMPERL and special then dm[#dm + 1] = 8192 end
  if dhe == HI.HE.SOUL_DEW and (dsp == LATIAS or dsp == LATIOS) and special then dm[#dm + 1] = 6144 end
  D = math.max(1, applyMod(D, chain(dm)))

  local level = (attacker.mon and attacker.mon.level) or 1
  local d = floor(floor(floor(level * 2 / 5 + 2) * power * A / D) / 50) + 2

  if opts.spread then d = applyMod(d, 3072) end
  if weather and not typeless then
    if (weather == "RAIN" and mtype == "WATER") or (weather == "SUN" and mtype == "FIRE") then d = applyMod(d, 6144)
    elseif (weather == "RAIN" and mtype == "FIRE") or (weather == "SUN" and mtype == "WATER") then d = applyMod(d, 2048) end
  end
  if crit then d = d * 2 end
  if not typeless then
    local r = rng(ruleset.randMin or 85, ruleset.randMax or 100)
    d = floor(d * r / 100)
  end
  local mult = 10
  if typed then
    if hasType(attacker, mtype) then d = applyMod(d, aab == "ADAPTABILITY" and 8192 or 6144) end
    local rows = rowsFor(attacker, defender, mtype, { liftImmunity = lift })
    for _, m in ipairs(rows) do
      if m == 0 then return 0, { crit = false, typeMult = 0 } end
      mult = floor(mult * m / 10)
      d = floor(d * m / 10)
    end
    if dab == "WONDER_GUARD" and mult <= 10 then
      return 0, { crit = false, typeMult = 0, ability = "WONDER_GUARD" }
    end
  end
  if not special and astatus == "BRN" and aab ~= "GUTS" then d = floor(d / 2) end

  local fm = {}
  if not crit and not opts.breaksScreens and not G45.infiltrates(attacker) then
    local screens = opts.screens
    if screens == nil and not typeless then screens = defender end
    local up = screens and ((special and screens.lightScreen) or (not special and screens.reflect))
    if up then fm[#fm + 1] = opts.doublesScreens and 2703 or 2048 end
  end
  if typed then
    if dab == "MULTISCALE" and (defender.mon.hp or 0) >= maxHP(defender) then fm[#fm + 1] = 2048 end
    if aab == "TINTED_LENS" and mult < 10 then fm[#fm + 1] = 8192 end
    if allyHas(battle, defender, "FRIEND_GUARD") then fm[#fm + 1] = 3072 end
    if crit and aab == "SNIPER" then fm[#fm + 1] = 6144 end
    if mult > 10 and (dab == "FILTER" or dab == "SOLID_ROCK") then fm[#fm + 1] = 3072 end
    if ahe == HI.HE.METRONOME then
      local m = attacker.bwMetronome
      if not (m and m.id == move.id) then m = { id = move.id, turn = turn, n = 1 }
      elseif m.turn ~= turn then m = { id = m.id, turn = turn, n = m.n + 1 } end
      if not opts.dryRun then attacker.bwMetronome = m end
      fm[#fm + 1] = math.min(8192, 4096 + 819 * (m.n - 1))
    end
    if ahe == HI.HE.EXPERT_BELT and mult > 10 then fm[#fm + 1] = 4915 end
    if ahe == HI.HE.LIFE_ORB then
      fm[#fm + 1] = 5324
      if not opts.dryRun then attacker.bwLifeOrbHit = true end
    end
  end
  d = applyMod(d, chain(fm))
  if typed then d = HI.resistBerry(attacker, defender, view, mult, d, opts.dryRun) end
  if not opts.dryRun then
    attacker.bwLastTarget, attacker.bwLastMove, attacker.bwLastMult = defender, move, mult
  end
  if d == 0 and typed and mult > 0 then d = 1 end
  return math.max(1, d), { crit = crit, typeMult = mult }
end


-- ===========================================================================
-- RUBY / SAPPHIRE / EMERALD / FIRERED / LEAFGREEN
-- ===========================================================================
-- READ FROM CODE (pokeemerald src/pokemon.c CalculateBaseDamage,
-- src/battle_script_commands.c Cmd_critcalc / Cmd_damagecalc / Cmd_typecalc /
-- Cmd_adjustnormaldamage; pokefirered's CalculateBaseDamage is the same body):
--   * the split is by TYPE (IS_TYPE_PHYSICAL: Normal..Steel physical, Fire..
--     Dark special); a ??? move does nothing
--   * Huge / Pure Power x2; the badge boosts x110/100 (Stone / Boulder Badge
--     Attack, Balance / Soul Defense, Mind / Volcano both specials) for the
--     player's side outside link / Frontier / a secret base
--   * the type items x(100+param)/100 on the ATTACK STAT (Sp. Atk for a
--     special type), then Choice Band x150/100, Soul Dew, DeepSea Tooth /
--     Scale, Light Ball (Sp. Atk x2), Metal Powder, Thick Club
--   * Thick Fat halves Sp. Atk vs Fire / Ice, Hustle / Guts x150/100 Attack,
--     Plus / Minus, Marvel Scale; Mud / Water Sport and the four pinch
--     abilities on the power; Explosion halves Defense
--   * the stage ratios; a crit ignores a lowered attack and a raised defence
--   * physical: / D / 50, burn / 2 (not Guts), Reflect / 2 (2/3 in a double
--     with both foes up, not on a crit), the both-foes move / 2, at least 1
--   * special: the same with Light Screen, then rain / sun / Solar Beam, then
--     Flash Fire x15/10 -- and then +2 for both
--   * x crit (2), Charge x2, Helping Hand x15/10
--   * STAB x15/10, each type row x mul / 10 (at least 1), Levitate, Wonder
--     Guard; random x(100 - rand%16)/100 last
-- No 255 quartering, no 997 cap (both Gen 1's), no weather after the +2.

local GEN3_SPECIAL = { FIRE = true, WATER = true, GRASS = true, ELECTRIC = true, ICE = true,
                       PSYCHIC = true, DRAGON = true, DARK = true }
G.GEN3_SPECIAL = GEN3_SPECIAL

local GEN3_BADGES = {
  emerald = { atk = 0x867, def = 0x86B, spc = 0x86D },
  ruby = { atk = 0x807, def = 0x80B, spc = 0x80D },
  sapphire = { atk = 0x807, def = 0x80B, spc = 0x80D },
  firered = { atk = 0x820, def = 0x824, spc = 0x826 },
  leafgreen = { atk = 0x820, def = 0x824, spc = 0x826 },
}
-- the badge flag, by the save's flag naming (FLAG_G3_0867)
local function hasBadge(battle, which)
  local V = require("src.core.GameVersion")
  local rows = GEN3_BADGES[V.get()] or GEN3_BADGES.emerald
  local save = battle and battle.game and battle.game.save
  if not (save and rows[which]) then return false end
  if battle.frontier or battle.link or battle.secretBase or battle.gen3Frontier then return false end
  local ok, set = pcall(function()
    return require("src.script.Flags").get(save, ("FLAG_G3_%04X"):format(rows[which]))
  end)
  return ok and set == true
end
G.gen3HasBadge = hasBadge

-- the Gen 3 held item's name and parameter (HoldItems' names)
local function item3(b)
  local HI = require("src.battle.HoldItems")
  local e, p = HI.effectOf(b)
  return e, p or 0
end

function G.computeGen3(ruleset, attacker, defender, move, opts)
  opts = opts or {}
  if (tonumber(move.power) or 0) == 0 or move.category == "status" or move.class == "status" then
    return 0, { crit = false, typeMult = 10 }
  end
  local battle = opts.battle or opts.g4Battle or require("src.battle.Gen45Abilities").battle
  local rng = opts.rng or love.math.random
  local typeless = opts.typeless
  local mtype = norm(move.type)
  if mtype == "???" or mtype == "MYSTERY" or mtype == "CURSE" then return 0, { crit = false, typeMult = 10 } end
  local struggle = tonumber(move.id) == STRUGGLE or move.id == "STRUGGLE"
  local typed = not typeless and not struggle
  local special = GEN3_SPECIAL[mtype] == true
  local aab, dab = Abilities.of(attacker), Abilities.of(defender)

  -- what the ability simply does not feel (Levitate, the absorbs)
  if typed and Abilities.blocks(defender, move) then
    return 0, { crit = false, typeMult = 0, ability = dab }
  end

  -- Cmd_critcalc (Damage.critRoll's stage table is this one)
  local crit = opts.forceCrit
  if dab == "BATTLE_ARMOR" or dab == "SHELL_ARMOR" then crit = false end
  if crit == nil then
    local high = move.highCrit
    if opts.highCrit ~= nil then high = opts.highCrit end
    local Dmg = require("src.battle.Damage")
    if Runtime.wantsHook("battle.crit") then
      crit = Runtime.call("battle.crit", function(c)
        return Dmg.critRoll(c.ruleset, c.attacker, c.moveId, c.rng, c.highCrit, c.data)
      end, { ruleset = ruleset, attacker = attacker, moveId = move.id, rng = rng, highCrit = high, data = opts.data })
    else
      crit = Dmg.critRoll(ruleset, attacker, move.id, rng, high, opts.data)
    end
  end
  crit = crit and true or false

  local atk, def = statOf(attacker, "attack"), statOf(defender, "defense")
  local spa, spd = statOf(attacker, "spatk"), statOf(defender, "spdef")
  local ahe, apow = item3(attacker)
  local dhe = item3(defender)
  local asp, dsp = attacker.def and attacker.def.name or "", defender.def and defender.def.name or ""
  asp, dsp = tostring(asp):upper(), tostring(dsp):upper()
  local power = tonumber(move.power) or 0
  if opts.powerMultiplier and opts.powerMultiplier ~= 1 then
    power = math.max(1, floor(power * opts.powerMultiplier))
  end

  if aab == "HUGE_POWER" or aab == "PURE_POWER" then atk = atk * 2 end
  if attacker.isPlayer and hasBadge(battle, "atk") then atk = floor(110 * atk / 100) end
  if defender.isPlayer and hasBadge(battle, "def") then def = floor(110 * def / 100) end
  if attacker.isPlayer and hasBadge(battle, "spc") then spa = floor(110 * spa / 100) end
  if defender.isPlayer and hasBadge(battle, "spc") then spd = floor(110 * spd / 100) end

  local boosted = require("src.battle.HoldItems").TYPE_POWER[ahe]
  if boosted and norm(boosted) == mtype then
    if special then spa = floor(spa * (apow + 100) / 100) else atk = floor(atk * (apow + 100) / 100) end
  end
  if ahe == "CHOICE_BAND" then atk = floor(150 * atk / 100) end
  local frontier = battle and (battle.frontier or battle.gen3Frontier)
  if ahe == "SOUL_DEW" and not frontier and (asp == "LATIAS" or asp == "LATIOS") then spa = floor(150 * spa / 100) end
  if dhe == "SOUL_DEW" and not frontier and (dsp == "LATIAS" or dsp == "LATIOS") then spd = floor(150 * spd / 100) end
  if ahe == "DEEP_SEA_TOOTH" and asp == "CLAMPERL" then spa = spa * 2 end
  if dhe == "DEEP_SEA_SCALE" and dsp == "CLAMPERL" then spd = spd * 2 end
  if ahe == "LIGHT_BALL" and asp == "PIKACHU" then spa = spa * 2 end
  if dhe == "METAL_POWDER" and dsp == "DITTO" then def = def * 2 end
  if ahe == "THICK_CLUB" and (asp == "CUBONE" or asp == "MAROWAK") then atk = atk * 2 end

  if dab == "THICK_FAT" and (mtype == "FIRE" or mtype == "ICE") then spa = floor(spa / 2) end
  if aab == "HUSTLE" then atk = floor(150 * atk / 100) end
  if (aab == "PLUS" and sideHas(battle, attacker, "MINUS") ) or (aab == "MINUS" and sideHas(battle, attacker, "PLUS")) then
    spa = floor(150 * spa / 100)
  end
  local astatus = attacker.mon and attacker.mon.status
  if aab == "GUTS" and astatus then atk = floor(150 * atk / 100) end
  if dab == "MARVEL_SCALE" and defender.mon and defender.mon.status then def = floor(150 * def / 100) end
  for _, muted in pairs(opts.sports or {}) do
    if muted == mtype then power = floor(power / 2) end
  end
  local pinch = Abilities.PINCH[aab]
  if pinch and pinch == mtype and (attacker.mon.hp or 0) <= floor(maxHP(attacker) / 3) then
    power = floor(150 * power / 100)
  end
  if opts.explode then def = floor(def / 2) end

  local A, As, D, Ds
  if special then A, As, D, Ds = spa, stage(attacker, "spatk"), spd, stage(defender, "spdef")
  else A, As, D, Ds = atk, stage(attacker, "attack"), def, stage(defender, "defense") end
  local level = (attacker.mon and attacker.mon.level) or 1
  local d
  if crit and As <= 0 then d = A else d = staged(A, As) end
  d = d * power
  d = d * (floor(2 * level / 5) + 2)
  local helper
  if crit and Ds >= 0 then helper = D else helper = staged(D, Ds) end
  d = floor(d / math.max(1, helper))
  d = floor(d / 50)
  local screens = opts.screens
  if screens == nil and not typeless then screens = defender end
  if not special then
    if astatus == "BRN" and aab ~= "GUTS" then d = floor(d / 2) end
    if screens and screens.reflect and not crit and not opts.breaksScreens then
      if opts.doublesScreens then d = 2 * floor(d / 3) else d = floor(d / 2) end
    end
    if opts.spread then d = floor(d / 2) end
    if d == 0 then d = 1 end
  else
    if screens and screens.lightScreen and not crit and not opts.breaksScreens then
      if opts.doublesScreens then d = 2 * floor(d / 3) else d = floor(d / 2) end
    end
    if opts.spread then d = floor(d / 2) end
    local weather = opts.weather
    if weather and not typeless then
      if weather == "RAIN" then
        if mtype == "FIRE" then d = floor(d / 2) elseif mtype == "WATER" then d = floor(15 * d / 10) end
      end
      if (weather == "RAIN" or weather == "SANDSTORM" or weather == "HAIL")
         and (tonumber(move.id) == SOLAR_BEAM or move.id == "SOLAR_BEAM") then
        d = floor(d / 2)
      end
      if weather == "SUN" then
        if mtype == "FIRE" then d = floor(15 * d / 10) elseif mtype == "WATER" then d = floor(d / 2) end
      end
    end
    if attacker.flashFire and aab == "FLASH_FIRE" and mtype == "FIRE" then d = floor(15 * d / 10) end
  end
  d = d + 2

  -- Cmd_damagecalc
  if crit then d = d * 2 end
  if attacker.charged and mtype == "ELECTRIC" then d = d * 2 end
  if opts.helpingHand or require("src.battle.Gen4MoveEffectsExtra").helped(battle, attacker) then
    d = floor(d * 15 / 10)
  end

  -- Cmd_typecalc
  local mult = 10
  if typed then
    if hasType(attacker, mtype) then d = floor(d * 15 / 10) end
    local identified = defender.identified
    local seen = {}
    for _, t in ipairs(defender.curTypes or {}) do
      local dt = norm(t)
      if dt and not seen[dt] then
        seen[dt] = true
        local m = TypeChart.effectiveness(move.type, { t })
        if m == 0 and dt == "GHOST" and (mtype == "NORMAL" or mtype == "FIGHTING") and identified then m = nil end
        if m and m ~= 10 then
          if m == 0 then return 0, { crit = false, typeMult = 0 } end
          mult = floor(mult * m / 10)
          d = floor(d * m / 10)
          if d == 0 then d = 1 end
        end
      end
    end
    if dab == "WONDER_GUARD" and mult <= 10 then
      return 0, { crit = false, typeMult = 0, ability = "WONDER_GUARD" }
    end
  end
  -- ApplyRandomDmgMultiplier
  if d ~= 0 and not typeless then
    local r = rng(ruleset.randMin or 85, ruleset.randMax or 100)
    d = floor(d * r / 100)
    if d == 0 then d = 1 end
  end
  return math.max(1, d), { crit = crit, typeMult = mult }
end

return G
