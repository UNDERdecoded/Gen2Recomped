-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SINNOH'S AND UNOVA'S ABILITIES IN THE TURN LOOP (battle parity pass).
--
-- src/battle/Abilities.lua answers for Hoenn's 76. A coverage scan of every
-- ability name against src/battle found 44 of Platinum's 123 with no code at
-- all (No Guard, Dry Skin, Motor Drive, Ice Body, Snow Warning, Download,
-- Unburden, Quick Feet, Steadfast, Anger Point, Aftermath, Poison Heal...)
-- and 33 of BW's 41 new ones (Moxie, Regenerator, Prankster, Sap Sipper,
-- Justified, Iron Barbs...). The formula abilities (Technician, Adaptability,
-- Sniper, Filter...) are src/battle/Gen4Damage.lua's; this file is the rest.
--
-- `install(Abilities)` (called at the end of Abilities.lua) wraps the
-- existing questions with the Gen 4 / Gen 5 answers, gated on the cartridge's
-- generation, so an Emerald battle is untouched. The other entry points are
-- asked by BattleState at the seams named on each.
--
-- READ FROM CODE (pokeplatinum battle_lib.c / battle_script.c /
-- battle_controller_player.c): the accuracy routine (HitRateByStage,
-- Compound Eyes x130/100, Sand Veil / Snow Cloak x80/100 in their weather,
-- Hustle x80/100 physical, Tangled Feet x50/100 confused, BrightPowder,
-- Wide Lens / Zoom Lens, Micle x120/100, Gravity x10/6, rand%100+1 > rate),
-- No Guard either side, Motor Drive / Dry Skin absorbs, Dry Skin / Solar
-- Power 1/8 in sun, Dry Skin 1/8 and Hydration in rain, Ice Body 1/16 in
-- hail, Snow Cloak / Ice Body hail immunity, the 1/16 sand / hail damage,
-- Static / Poison Point / Flame Body / Cute Charm / Effect Spore 30%
-- (rand%10 < 3), Rough Skin 1/8, Aftermath 1/4 on a contact KO, Quick Feet
-- x15/10 (and no paralysis quarter), Slow Start (5 turns: speed / 2),
-- Unburden x2, Download (+1 Atk if the foes' Defense < Sp. Def, else +1 SpA),
-- Snow Warning, Skill Link (5 hits), Steadfast, Anger Point, Poison Heal 1/8.
-- INFERRED (BW, no decomp; well-established Gen 5 rules): Sturdy holds at
-- full HP, Lightning Rod / Storm Drain / Sap Sipper immunities, Iron Barbs
-- 1/8, Rough Skin 1/8, Moxie, Justified, Rattled, Weak Armor, Cursed Body
-- (30%), Regenerator 1/3, Prankster +1 status, Sand Rush / Force / Overcoat
-- sand immunity, Victory Star x1.1, Wonder Skin (status moves at 50%).

local Strings = require("src.core.Strings")

local M = {}
local floor = math.floor

local function GV() return require("src.core.GameVersion") end
local function gen()
  local ok, g = pcall(function() return GV().generation(GV().get()) end)
  return ok and tonumber(g) or 0
end
M.gen = gen
local function g4plus() return gen() >= 4 end
local function g5() return gen() >= 5 end

local A -- Abilities, set by install

local function of(b) return A and A.of(b) end
local function norm(t) return A and A.normalizeType(t) or t end
local function maxHP(b)
  local m = b and b.mon
  return (m and m.stats and m.stats.hp) or (m and (m.maxHP or m.maxHp)) or 1
end
local function hasType(b, t)
  for _, x in ipairs(b and b.curTypes or {}) do if norm(x) == t then return true end end
  return false
end
local function who(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end
local function label(ability)
  return (tostring(ability):gsub("_", " "))
end
-- MOVE_FLAG_MAKES_CONTACT is bit 0 of a Platinum / HGSS move's flags byte
-- (generated/move_flags.txt); a BW record carries makesContact itself. A
-- Gen 4 move had neither, and Abilities.onContact read "not false" as
-- contact -- a Thunderbolt into a Pikachu risked Static.
function M.makesContact(move)
  if not move then return false end
  if move.makesContact ~= nil then return move.makesContact == true end
  local f = tonumber(move.flags)
  if f then return f % 2 == 1 end
  return true
end

local function weatherOf(battle)
  return battle and require("src.battle.Weather").current(battle) or nil
end

-- ---------------------------------------------------------------------------
-- THE WRAPPERS
-- ---------------------------------------------------------------------------

local IMMUNE4 = { MOTOR_DRIVE = "ELECTRIC", DRY_SKIN = "WATER" }
local IMMUNE5 = { LIGHTNING_ROD = "ELECTRIC", STORM_DRAIN = "WATER", SAP_SIPPER = "GRASS" }
local BOOST4 = { MOTOR_DRIVE = "speed" }
local BOOST5 = { LIGHTNING_ROD = "spatk", STORM_DRAIN = "spatk", SAP_SIPPER = "attack" }

function M.install(Abilities)
  A = Abilities
  local base = {}
  for _, k in ipairs({ "blocks", "absorbs", "endOfTurn", "ignoresWeatherDamage",
                       "speedMultiplier", "onSwitchIn", "refusesStatus", "onContact",
                       "accuracyMultiplier" }) do
    base[k] = Abilities[k]
  end
  Abilities.SWITCH_IN_WEATHER.SNOW_WARNING = "HAIL"

  function Abilities.blocks(defender, move, typeMult)
    if base.blocks(defender, move, typeMult) then return true end
    if not (g4plus() and move) then return false end
    local ab = of(defender)
    local t = norm(move.type)
    if IMMUNE4[ab] == t and (tonumber(move.power) or 0) > 0 then return true end
    if ab == "MOTOR_DRIVE" and t == "ELECTRIC" then return true end
    if g5() and IMMUNE5[ab] == t then return true end
    return false
  end

  function Abilities.absorbs(defender, move)
    local act = base.absorbs(defender, move)
    if act or not (g4plus() and move) then return act end
    local ab = of(defender)
    local t = norm(move.type)
    if ab == "DRY_SKIN" and t == "WATER" then
      return { kind = "heal", ability = ab, numerator = 1, denominator = 4 }
    end
    if IMMUNE4[ab] == t and BOOST4[ab] then return { kind = "boost", ability = ab, stat = BOOST4[ab] } end
    if g5() and IMMUNE5[ab] == t then return { kind = "boost", ability = ab, stat = BOOST5[ab] } end
    return nil
  end

  function Abilities.endOfTurn(battler, weather)
    local act = base.endOfTurn(battler, weather)
    if act or not g4plus() then return act end
    local ab = of(battler)
    local mon = battler and battler.mon
    if not (ab and mon) then return nil end
    local full = (mon.hp or 0) >= maxHP(battler)
    if ab == "ICE_BODY" and weather == "HAIL" and not full then
      return { kind = "heal", ability = ab, numerator = 1, denominator = 16 }
    end
    if ab == "DRY_SKIN" and weather == "RAIN" and not full then
      return { kind = "heal", ability = ab, numerator = 1, denominator = 8 }
    end
    if (ab == "DRY_SKIN" or ab == "SOLAR_POWER") and weather == "SUN" then
      return { kind = "hurt", ability = ab, numerator = 1, denominator = 8 }
    end
    if ab == "HYDRATION" and weather == "RAIN" and mon.status then
      return { kind = "shedSkin", ability = ab, oneIn = 1 }
    end
    return nil
  end

  function Abilities.ignoresWeatherDamage(battler, weather)
    if base.ignoresWeatherDamage(battler, weather) then return true end
    if not g4plus() then return false end
    local ab = of(battler)
    if weather == "HAIL" and (ab == "ICE_BODY" or ab == "SNOW_CLOAK") then return true end
    if ab == "MAGIC_GUARD" then return true end
    if g5() then
      if ab == "OVERCOAT" then return true end
      if weather == "SANDSTORM" and (ab == "SAND_RUSH" or ab == "SAND_FORCE") then return true end
    end
    return false
  end

  function Abilities.speedMultiplier(battler, weather)
    local n, d = base.speedMultiplier(battler, weather)
    if not g4plus() then return n, d end
    local ab = of(battler)
    local mon = battler and battler.mon
    if ab == "QUICK_FEET" and mon and mon.status then
      -- x15/10, and the paralysis quarter TurnOrder already took is undone
      n, d = n * 3, d * 2
      if tostring(mon.status):upper() == "PAR" then n = n * 4 end
    end
    if ab == "SLOW_START" and (battler.g4SlowStart or 0) > 0 then d = d * 2 end
    if ab == "UNBURDEN" and battler.lastConsumedItem and not (mon and (mon.item or mon.heldItem)) then
      n = n * 2
    end
    if g5() and ab == "SAND_RUSH" and weather == "SANDSTORM" then n = n * 2 end
    return n, d
  end

  function Abilities.onSwitchIn(battler)
    local act = base.onSwitchIn(battler)
    if act or not g4plus() then return act end
    local ab = of(battler)
    if ab == "DOWNLOAD" then return { kind = "download", ability = ab } end
    if ab == "SLOW_START" then return { kind = "slowStart", ability = ab } end
    if ab == "FRISK" or ab == "ANTICIPATION" or ab == "FOREWARN" then
      return { kind = "notice", ability = ab }
    end
    if g5() and ab == "IMPOSTER" then return { kind = "imposter", ability = ab } end
    if g5() and ab == "ILLUSION" then return { kind = "illusion", ability = ab } end
    return nil
  end

  function Abilities.refusesStatus(battler, status)
    if base.refusesStatus(battler, status) then return true end
    if not g4plus() then return false end
    if of(battler) == "LEAF_GUARD" and status ~= "CONFUSION" and status ~= "INFATUATION"
       and weatherOf(M.battle) == "SUN" then
      return true
    end
    return false
  end

  function Abilities.onContact(defender, move)
    if g4plus() and not M.makesContact(move) then return nil end
    local act = base.onContact(defender, move)
    if gen() == 3 and act and act.kind == "statusRoll" then
      local E = require("src.battle.Gen4MoveEffectsExtra").EFFECT_SPORE3
      act.outOf, act.table = E.outOf, E.table
      return act
    end
    if not g4plus() then return act end
    if act then
      -- Gen 4: rand % 10 < 3, not Hoenn's one in three
      if act.kind == "status" or act.kind == "infatuate" then
        act.pct, act.oneIn = 30, nil
      elseif act.kind == "statusRoll" then
        act.table = { [0] = "PSN", [1] = "PAR", [2] = "SLP" }
      elseif act.kind == "recoil" and act.ability == "ROUGH_SKIN" then
        act.denominator = 8
      end
      return act
    end
    if g5() and of(defender) == "IRON_BARBS" then
      return { kind = "recoil", ability = "IRON_BARBS", numerator = 1, denominator = 8 }
    end
    return nil
  end

  function Abilities.accuracyMultiplier(attacker, defender, move, special, weather)
    local m = base.accuracyMultiplier(attacker, defender, move, special, weather)
    if g4plus() and of(attacker) == "COMPOUND_EYES" then m = floor(m * 13 / 10) end
    return m
  end
end

-- ---------------------------------------------------------------------------
-- ACCURACY (BattleControllerPlayer_CheckMoveHitAccuracy / ..Overrides)
-- ---------------------------------------------------------------------------

local HIT_RATE = {
  [0] = { 33, 100 }, { 36, 100 }, { 43, 100 }, { 50, 100 }, { 60, 100 }, { 75, 100 },
  { 1, 1 }, { 133, 100 }, { 166, 100 }, { 2, 1 }, { 233, 100 }, { 133, 50 }, { 3, 1 },
}
M.HIT_RATE = HIT_RATE

-- true = it hits. `accuracyRaw` (0..255) stands in for the move's accuracy
-- when a caller has rewritten it (Thunder in sun).
function M.accuracy(battle, move, user, target, accuracyRaw)
  if not (move and user and target) then return true end
  local aab = of(user)
  local mold = aab == "MOLD_BREAKER" or aab == "TERAVOLT" or aab == "TURBOBLAZE"
  local dab = not mold and of(target) or nil
  if aab == "NO_GUARD" or of(target) == "NO_GUARD" then return true end
  local hitRate = accuracyRaw and floor(accuracyRaw * 100 / 255 + 0.5) or tonumber(move.accuracy) or 0
  if hitRate <= 0 then return true end
  local acc = (user.stages and user.stages.accuracy) or 0
  local eva = -((target.stages and target.stages.evasion) or 0)
  if aab == "SIMPLE" then acc = acc * 2 end
  if dab == "SIMPLE" then eva = eva * 2 end
  if dab == "UNAWARE" then acc = 0 end
  if aab == "UNAWARE" then eva = 0 end
  if (target.identified or target.g4MiracleEye or target.g4Foresight) and eva < 0 then eva = 0 end
  local sum = math.max(0, math.min(12, 6 + eva + acc))
  hitRate = floor(hitRate * HIT_RATE[sum][1] / HIT_RATE[sum][2])
  if aab == "COMPOUND_EYES" or aab == "COMPOUNDEYES" then hitRate = floor(hitRate * 130 / 100) end
  local weather = weatherOf(battle)
  if weather == "SANDSTORM" and dab == "SAND_VEIL" then hitRate = floor(hitRate * 80 / 100) end
  if weather == "HAIL" and dab == "SNOW_CLOAK" then hitRate = floor(hitRate * 80 / 100) end
  if battle and battle.deepFog and battle:deepFog() then hitRate = floor(hitRate * 6 / 10) end
  local cls = move.class or move.category
  if aab == "HUSTLE" and cls == "physical" then hitRate = floor(hitRate * 80 / 100) end
  if dab == "TANGLED_FEET" and target.confusedTurns and target.confusedTurns > 0 then
    hitRate = floor(hitRate * 50 / 100)
  end
  -- INFERRED (Gen 5): Victory Star x1.1 on the side, Wonder Skin halves a
  -- status move aimed at the holder
  if g5() then
    if aab == "VICTORY_STAR" then hitRate = floor(hitRate * 110 / 100) end
    if dab == "WONDER_SKIN" and cls == "status" and hitRate > 50 then hitRate = 50 end
  end
  local H = require("src.battle.Gen5HoldItems")
  local dhe, dpow = H.held(target)
  if dhe == H.HE.ACC_REDUCE then hitRate = floor(hitRate * (100 - (dpow or 0)) / 100) end
  local ahe, apow = H.held(user)
  if ahe == H.HE.WIDE_LENS then hitRate = floor(hitRate * (100 + (apow or 10)) / 100) end
  if ahe == H.HE.ZOOM_LENS and battle
     and (target.actedTurn == battle.turnCount or target.bwMovedTurn == battle.turnCount) then
    hitRate = floor(hitRate * (100 + (apow or 20)) / 100)
  end
  if user.g4Micle or user.bwMicle then
    user.g4Micle, user.bwMicle = nil, nil
    hitRate = floor(hitRate * 120 / 100)
  end
  local fx = battle and battle.g4fx
  if (fx and fx.field and (fx.field.gravity or 0) > 0)
     or (battle and battle.bw and battle.bw.field and (battle.bw.field.gravity or 0) > 0) then
    hitRate = floor(hitRate * 10 / 6)
  end
  local rng = (battle and battle.rng) or love.math.random
  return rng(1, 100) <= hitRate
end

-- ---------------------------------------------------------------------------
-- THE TURN LOOP (asked by BattleState)
-- ---------------------------------------------------------------------------

local function stage(battle, b, stat, delta)
  local ME = require("src.battle.MoveEffects")
  for _, m in ipairs(ME.changeStage(battle, b, stat, delta, false)) do battle:sayNext(m) end
end

local function hurt(battle, b, amount)
  if not (b and b.mon and b.mon.hp > 0) then return end
  if of(b) == "MAGIC_GUARD" then return end
  battle:applyDamage(b, math.max(1, floor(amount)))
  battle:drainNext()
  if b.mon.hp <= 0 then battle:onFaint(b) end
end

local function foes(battle, b)
  local out = {}
  if battle.sides then
    local side = battle.sides[b.isPlayer and 2 or 1]
    for _, x in ipairs(side and side.battlers or {}) do
      if x and x.mon and x.mon.hp > 0 then out[#out + 1] = x end
    end
  end
  if #out == 0 then
    local f = b.isPlayer and battle.enemy or battle.player
    if f and f.mon and f.mon.hp > 0 then out[1] = f end
  end
  return out
end

-- BattleState:abilitySwitchInEffect for the kinds this file adds
function M.switchInEffect(battle, battler, act)
  if act.kind == "download" then
    local def, spdef = 0, 0
    local G4D = require("src.battle.Gen4Damage")
    for _, f in ipairs(foes(battle, battler)) do
      if not f.substituteHP then
        local cs = f.curStats or {}
        local st = f.stages or {}
        local a = G4D.STAGE[math.max(-6, math.min(6, st.defense or 0))]
        local b = G4D.STAGE[math.max(-6, math.min(6, st.spdef or 0))]
        def = def + floor((cs.defense or 0) * a[1] / a[2])
        spdef = spdef + floor((cs.spdef or 0) * b[1] / b[2])
      end
    end
    battle:sayNext(Strings("%s's\n%s!", who(battler), label(act.ability)))
    stage(battle, battler, def < spdef and "attack" or "spatk", 1)
    return true
  end
  if act.kind == "notice" then
    local line = require("src.battle.Gen4MoveEffectsExtra").switchInNotice(battle, battler)
    if line then battle:sayNext(line) end
    return true
  end
  if act.kind == "imposter" or act.kind == "illusion" then
    return M.unovaSwitchIn(battle, battler, act)
  end
  if act.kind == "slowStart" then
    battler.g4SlowStart = 5
    battler.g4SlowStartTurn = battle.turnCount
    battle:sayNext(Strings("%s can't get\nit going!", who(battler)))
    return true
  end
  return false
end

-- BattleState:abilityEndOfTurn, before the single Abilities.endOfTurn act:
-- Slow Start's countdown and Bad Dreams
function M.endOfTurn(battle, battler)
  if not g4plus() or not (battler and battler.mon and battler.mon.hp > 0) then return end
  local ab = of(battler)
  if ab == "SLOW_START" and (battler.g4SlowStart or 0) > 0
     and battler.g4SlowStartTurn ~= battle.turnCount then
    battler.g4SlowStart = battler.g4SlowStart - 1
    if battler.g4SlowStart == 0 then
      battle:sayNext(Strings("%s finally\ngot its act together!", who(battler)))
    end
  end
  if ab == "BAD_DREAMS" then
    for _, f in ipairs(foes(battle, battler)) do
      if tostring(f.mon.status or ""):upper() == "SLP" and of(f) ~= "MAGIC_GUARD" then
        battle:sayNext(Strings("%s is tormented!", who(f)))
        hurt(battle, f, maxHP(f) / 8)
      end
    end
  end
  -- Harvest, Healer, Moody, Zen Mode (BW, INFERRED)
  M.unovaEndOfTurn(battle, battler)
end

-- BattleState:abilityAbsorb's "boost" kind (Motor Drive, Lightning Rod...)
function M.absorbBoost(battle, target, act)
  battle:sayNext(Strings("%s's\n%s!", who(target), label(act.ability)))
  stage(battle, target, act.stat, 1)
  return true
end

-- the flinch line was printed: STEADFAST raises Speed
function M.onFlinch(battle, user)
  if g4plus() and of(user) == "STEADFAST" then
    battle:sayNext(Strings("%s's\n%s!", who(user), label("STEADFAST")))
    stage(battle, user, "speed", 1)
  end
end

-- after a move has dealt `dealt` (BattleState:shellBellDrain, before the
-- held items): reads the target / move / multiplier the damage formula left
-- on the attacker
function M.afterHit(battle, attacker, dealt)
  if not (g4plus() and attacker and attacker.mon) then return end
  local target, move = attacker.bwLastTarget, attacker.bwLastMove
  if not (target and target.mon and move and (dealt or 0) > 0) or target == attacker then return end
  local info = attacker.g45LastInfo or {}
  local tab, aab = of(target), of(attacker)
  local contact = M.makesContact(move)
  local mtype = norm(move.type)
  -- Poison Touch, Mummy, Pickpocket, Illusion breaking (BW, INFERRED)
  M.unovaAfterHit(battle, attacker, target, move, contact)
  if target.mon.hp <= 0 then
    -- AFTERMATH: a contact move that knocked it out costs a quarter (no Damp)
    if tab == "AFTERMATH" and contact and attacker.mon.hp > 0 then
      local damp = false
      for _, b in ipairs({ battle.player, battle.enemy }) do if of(b) == "DAMP" then damp = true end end
      if not damp then
        battle:sayNext(Strings("%s is hurt!", who(attacker)))
        hurt(battle, attacker, maxHP(attacker) / 4)
      end
    end
    -- MOXIE (INFERRED): a knockout raises Attack
    if g5() and aab == "MOXIE" and attacker.mon.hp > 0 then
      battle:sayNext(Strings("%s's\n%s!", who(attacker), label(aab)))
      stage(battle, attacker, "attack", 1)
    end
    return
  end
  -- ANGER POINT: a critical hit maxes Attack
  if tab == "ANGER_POINT" and info.crit and not target.substituteHP then
    target.stages = target.stages or {}
    target.stages.attack = 6
    battle:sayNext(Strings("%s maxed\nits ATTACK!", who(target)))
  end
  if not g5() or target.substituteHP then return end
  -- INFERRED Gen 5 reactions
  if tab == "JUSTIFIED" and mtype == "DARK" then
    battle:sayNext(Strings("%s's\n%s!", who(target), label(tab))); stage(battle, target, "attack", 1)
  elseif tab == "RATTLED" and (mtype == "BUG" or mtype == "GHOST" or mtype == "DARK") then
    battle:sayNext(Strings("%s's\n%s!", who(target), label(tab))); stage(battle, target, "speed", 1)
  elseif tab == "WEAK_ARMOR" and (move.class or move.category) == "physical" then
    battle:sayNext(Strings("%s's\n%s!", who(target), label(tab)))
    stage(battle, target, "defense", -1); stage(battle, target, "speed", 1)
  elseif tab == "CURSED_BODY" and attacker.mon.hp > 0 and not attacker.disabledSlot then
    local rng = battle.rng or love.math.random
    if rng(0, 99) < 30 then
      for i, m in ipairs(attacker.curMoves or attacker.mon.moves or {}) do
        if m.id == move.id then attacker.disabledSlot, attacker.disabledTurns = i, 4 end
      end
      battle:sayNext(Strings("%s's %s\nwas disabled!", who(attacker), move.name or "move"))
    end
  end
end

-- ROUGH SKIN / IRON BARBS: their recoil is the one the Abilities.onContact
-- description carries; this is Gen 5's STURDY (INFERRED): a hit at full HP
-- leaves it on 1
function M.sturdyHolds(battle, b, incoming)
  if not g5() or of(b) ~= "STURDY" then return false end
  if b.mon.hp < maxHP(b) or incoming < b.mon.hp then return false end
  b.g45Sturdy = true
  return true
end
function M.sturdyLine(b)
  if not (b and b.g45Sturdy) then return nil end
  b.g45Sturdy = nil
  return Strings("%s endured\nthe hit!", who(b))
end

-- REGENERATOR (INFERRED): a third back on the way out
function M.onSwitchOut(battle, b)
  if g5() and b and b.mon and b.mon.hp > 0 and of(b) == "REGENERATOR" then
    b.mon.hp = math.min(maxHP(b), b.mon.hp + floor(maxHP(b) / 3))
  end
end

-- PRANKSTER (INFERRED): +1 to a status move's priority
function M.priorityBonus(b, move)
  if g5() and b and move and of(b) == "PRANKSTER"
     and ((move.class or move.category) == "status" or (tonumber(move.power) or 0) == 0) then
    return 1
  end
  return 0
end

-- SKILL LINK: a 2-5 move always hits five times
function M.skillLink(user, dist)
  if g4plus() and of(user) == "SKILL_LINK" and type(dist) == "table" and #dist > 0 then
    local best = 0
    for _, n in ipairs(dist) do if n > best then best = n end end
    return best
  end
  return nil
end

-- POISON HEAL: an eighth back instead of the poison's bite; nil = not it
function M.poisonHeal(battler)
  if not g4plus() or of(battler) ~= "POISON_HEAL" then return nil end
  local mon = battler.mon
  if mon.hp >= maxHP(battler) then return {} end
  mon.hp = math.min(maxHP(battler), mon.hp + math.max(1, floor(maxHP(battler) / 8)))
  return { Strings("%s's\nPOISON HEAL!", battler.name or "?") }
end

-- the sand / hail divisor: 16 from Hoenn on (Gen 4 READ: maxHP / 16)
function M.weatherDivisor(battle)
  local name = battle and battle.ruleset and battle.ruleset.name
  -- (Hoenn too: pokeemerald Cmd_weatherdamage, maxHP / 16)
  if name == "gen4_platinum" or name == "gen5_bw" or name == "gen3_emerald" then return 16 end
  return nil
end


-- ---------------------------------------------------------------------------
-- UNOVA'S REMAINING ABILITIES (INFERRED: no BW decomp; standard Gen 5 rules)
-- ---------------------------------------------------------------------------

local function partyOf(battle, b)
  if b.isPlayer then return battle.game and battle.game.save and battle.game.save.party or {} end
  return battle.enemyParty or {}
end

-- IMPOSTER: transform into the foe opposite on the way in; ILLUSION: wear
-- the last able party member's name until a damaging hit lands
function M.unovaSwitchIn(battle, battler, act)
  if act.kind == "imposter" then
    local foe = foes(battle, battler)[1]
    if not foe or foe.substituteHP or foe.bwTransformed or battler.bwTransformed then return true end
    local fn = require("src.battle.MoveEffects").primary.TRANSFORM_EFFECT
    if fn then
      for _, m in ipairs(fn(battle, battler, foe) or {}) do battle:sayNext(m) end
      battler.bwTransformed, battler.bwOwnStats = true, true
      pcall(function() require("src.battle.Gen5Transform").apply(battle, battler, foe) end)
    end
    return true
  end
  if act.kind == "illusion" then
    local party = partyOf(battle, battler)
    local disguise
    for i = #party, 1, -1 do
      local m = party[i]
      if m ~= battler.mon and (m.hp or 0) > 0 and not m.isEgg then disguise = m break end
    end
    if disguise and disguise.species ~= battler.mon.species then
      local def = battle.data and battle.data.pokemon and battle.data.pokemon[disguise.species]
      battler.g45Illusion = { name = battler.name, sprite = battler.sprite, species = battler.species,
                              picAnim = battler.picAnim, transformed = battler.gen5Transformed }
      battler.name = disguise.nickname or (def and def.name) or battler.name
      -- the picture: Transform's own swap, onto the disguise's species
      pcall(function() require("src.battle.Gen5Transform").apply(battle, battler, { mon = disguise }) end)
    end
    return true
  end
  return false
end

local function breakIllusion(battle, b)
  local il = b and b.g45Illusion
  if not il then return end
  b.g45Illusion = nil
  b.name = il.name
  b.sprite, b.species, b.picAnim, b.gen5Transformed = il.sprite, il.species, il.picAnim, il.transformed
  battle:sayNext(Strings("%s's illusion\nwore off!", who(b)))
end
M.breakIllusion = breakIllusion

-- the BW contact / hit reactions this file did not have yet; called from
-- M.afterHit with the target, the move and whether it touched
function M.unovaAfterHit(battle, attacker, target, move, contact)
  if not g5() then return end
  local tab, aab = of(target), of(attacker)
  if target.mon.hp > 0 and (move.class or move.category) ~= "status" then breakIllusion(battle, target) end
  if not contact or target.substituteHP then return end
  local rng = battle.rng or love.math.random
  -- POISON TOUCH: 30% to poison what it touched
  if aab == "POISON_TOUCH" and target.mon.hp > 0 and not target.mon.status and rng(0, 99) < 30 then
    local msgs = require("src.battle.StatusRegistry").inflict(battle, target, "PSN",
      { secondary = true, user = attacker, source = "POISON_TOUCH" })
    for _, m in ipairs(msgs or {}) do battle:sayNext(m) end
  end
  -- MUMMY: whatever touches it becomes a Mummy too
  if tab == "MUMMY" and aab ~= "MUMMY" and aab ~= "MULTITYPE" and attacker.mon.hp > 0 then
    attacker.abilityOverride = "MUMMY"
    battle:sayNext(Strings("%s's ability\nbecame MUMMY!", who(attacker)))
  end
  -- PICKPOCKET: the holder-less target takes the attacker's item
  if tab == "PICKPOCKET" and target.mon.hp > 0 and not (target.mon.item and target.mon.item ~= 0)
     and attacker.mon.item and attacker.mon.item ~= 0 and of(attacker) ~= "STICKY_HOLD" then
    local id = attacker.mon.item
    target.mon.item, attacker.mon.item = id, nil
    local def = battle.data and battle.data.items and battle.data.items[id]
    battle:sayNext(Strings("%s stole\n%s's %s!", who(target), who(attacker), def and def.name or "item"))
  end
end

local function isBerry(def)
  -- the Berries pocket is the cartridge's own answer in any language; the name is the older test
  return def and (def.pocket == "BERRIES" or (type(def.name) == "string" and def.name:find("Berry", 1, true) ~= nil)) or false
end

-- ZEN MODE: Darmanitan below half HP is Fire / Psychic with its Zen stats,
-- and in its Zen picture (form 1, gen5-form-sprites-v1) -- shown through a
-- copy of the mon so the party's Darmanitan keeps form 0 after the battle
local DARMANITAN = 555
local function zenPicture(battle, b, form)
  local okS, Sprites = pcall(require, "src.pokemon.Sprites")
  if not okS or not b.mon then return end
  local proxy = {}
  for k, v in pairs(b.mon) do proxy[k] = v end
  proxy.form = form
  local okP, path = pcall(Sprites.path, battle.data, DARMANITAN, b.isPlayer and "back" or "front", { mon = proxy, kind = "battle" })
  local okI, img = pcall(require("src.render.Assets").image, okP and path or nil)
  if okI and img then
    img:setFilter("nearest", "nearest")
    b.sprite = img
    b.picAnim, b.monAnim = nil, nil
  end
end
local ZEN_BASE = { hp = 105, attack = 30, defense = 105, spatk = 140, spdef = 105, speed = 55 }
local function zenMode(battle, b)
  if tonumber(b.mon.species) ~= DARMANITAN then return end
  local half = b.mon.hp * 2 <= maxHP(b)
  if half and not b.g45Zen then
    b.g45Zen = { types = b.curTypes, stats = b.curStats }
    b.curTypes = { "FIRE", "PSYCHIC" }
    local Stats = require("src.pokemon.Stats")
    local def = battle.data and battle.data.pokemon and battle.data.pokemon[DARMANITAN]
    if def and Stats.calcGen3 then
      local fake = setmetatable({ baseStats = {
        hp = ZEN_BASE.hp, attack = ZEN_BASE.attack, defense = ZEN_BASE.defense, speed = ZEN_BASE.speed,
        spatk = ZEN_BASE.spatk, spdef = ZEN_BASE.spdef, spAttack = ZEN_BASE.spatk, spDefense = ZEN_BASE.spdef,
      } }, { __index = def })
      local ok, st = pcall(Stats.calcGen3, fake, b.mon.level, b.mon.ivs, b.mon.evs, b.mon.nature)
      if ok and type(st) == "table" then
        local cs = {}
        for k, v in pairs(b.curStats or {}) do cs[k] = v end
        for _, k in ipairs({ "attack", "defense", "spatk", "spdef", "speed" }) do cs[k] = st[k] or cs[k] end
        b.curStats = cs
      end
    end
    zenPicture(battle, b, 1)
    battle:sayNext(Strings("ZEN MODE triggered!"))
  elseif not half and b.g45Zen then
    b.curTypes, b.curStats = b.g45Zen.types, b.g45Zen.stats
    b.g45Zen = nil
    zenPicture(battle, b, 0)
    battle:sayNext(Strings("ZEN MODE ended!"))
  end
end

function M.unovaEndOfTurn(battle, b)
  if not g5() or not (b and b.mon and b.mon.hp > 0) then return end
  local ab = of(b)
  local rng = battle.rng or love.math.random
  if ab == "HARVEST" and not (b.mon.item and b.mon.item ~= 0) and b.lastConsumedItem then
    local def = battle.data and battle.data.items and battle.data.items[b.lastConsumedItem]
    if isBerry(def) and (weatherOf(battle) == "SUN" or rng(0, 1) == 0) then
      b.mon.item, b.lastConsumedItem = b.lastConsumedItem, nil
      battle:sayNext(Strings("%s harvested\none %s!", who(b), def.name))
    end
  end
  if ab == "HEALER" and rng(0, 99) < 30 then
    local ally = battle.partnerOf and battle:partnerOf(b)
    if ally and ally.mon and ally.mon.hp > 0 and ally.mon.status then
      ally.mon.status, ally.toxicCounter = nil, nil
      if battle.syncShownStatus then battle:syncShownStatus() end
      battle:sayNext(Strings("%s's HEALER\ncured %s!", who(b), who(ally)))
    end
  end
  if ab == "MOODY" then
    local stats = { "attack", "defense", "spatk", "spdef", "speed", "accuracy", "evasion" }
    b.stages = b.stages or {}
    local up, down = {}, {}
    for _, s in ipairs(stats) do
      if (b.stages[s] or 0) < 6 then up[#up + 1] = s end
    end
    local raised
    if #up > 0 then raised = up[rng(1, #up)]; stage(battle, b, raised, 2) end
    for _, s in ipairs(stats) do
      if s ~= raised and (b.stages[s] or 0) > -6 then down[#down + 1] = s end
    end
    if #down > 0 then stage(battle, b, down[rng(1, #down)], -1) end
  end
  if ab == "ZEN_MODE" then zenMode(battle, b) end
end

-- TELEPATHY: an ally's attack does nothing to it (computeGen5)
function M.telepathyBlocks(attacker, defender)
  return g5() and attacker and defender and attacker ~= defender
         and attacker.isPlayer == defender.isPlayer and of(defender) == "TELEPATHY"
end
-- INFILTRATOR: through Reflect / Light Screen (computeGen5)
function M.infiltrates(attacker)
  return g5() and of(attacker) == "INFILTRATOR"
end


-- ---------------------------------------------------------------------------
-- HOENN'S HIT RATE (pokeemerald Cmd_accuracycheck, READ): one combined stage
-- (accuracy - evasion; FORESIGHT ignores the evasion entirely), the same
-- sAccuracyStageRatios table, Compound Eyes x130/100, Sand Veil x80/100 in a
-- sandstorm, Hustle x80/100 on a physical TYPE, BrightPowder / Lax Incense,
-- Thunder 50 in the sun; rand%100+1 > rate misses
-- ---------------------------------------------------------------------------
function M.accuracy3(battle, move, user, target, accuracyRaw)
  if not (move and user and target) then return true end
  local hitRate = accuracyRaw and floor(accuracyRaw * 100 / 255 + 0.5) or tonumber(move.accuracy) or 0
  if hitRate <= 0 then return true end
  local acc = (user.stages and user.stages.accuracy) or 0
  local sum
  if target.identified then sum = 6 + acc
  else sum = 6 + acc - ((target.stages and target.stages.evasion) or 0) end
  sum = math.max(0, math.min(12, sum))
  hitRate = floor(HIT_RATE[sum][1] * hitRate / HIT_RATE[sum][2])
  local aab, dab = of(user), of(target)
  if aab == "COMPOUNDEYES" or aab == "COMPOUND_EYES" then hitRate = floor(hitRate * 130 / 100) end
  if dab == "SAND_VEIL" and weatherOf(battle) == "SANDSTORM" then hitRate = floor(hitRate * 80 / 100) end
  local mtype = norm(move.type)
  local physical = not require("src.battle.Gen4Damage").GEN3_SPECIAL[mtype]
  if aab == "HUSTLE" and physical then hitRate = floor(hitRate * 80 / 100) end
  local e, p = require("src.battle.HoldItems").effectOf(target)
  if e == "EVASION_UP" then hitRate = floor(hitRate * (100 - (p or 0)) / 100) end
  local rng = (battle and battle.rng) or love.math.random
  return rng(1, 100) <= hitRate
end

return M
