-- PLATINUM / HEARTGOLD / SOULSILVER TRAINER AI, run rather than approximated.
--
-- Port of pokeplatinum src/battle/trainer_ai/trainer_ai.c (READ FROM CODE,
-- function names below are the decomp's) driving the cartridge's own script,
-- gTrainerAITable, which the importer lifts out of the trainer AI overlay
-- (src/import/Gen4TrainerAI.lua -> data.gen4_trainer_ai).  HeartGold's overlay
-- 10 carries the same 10,607 script words; its interpreter (ov10_0221BE20 ..,
-- pokeheartgold asm/overlay_10_trainer_ai.s) is INFERRED to be the same code,
-- the visible half (src/battle/trainer_ai.c: init, flag table, doubles bit)
-- reads identically.
--
-- WHAT RUNS WHERE (all READ FROM CODE unless marked):
--   TrainerAI_PickCommand -> G.command: TrainerAI_ShouldSwitch (Perish Song,
--     Wonder Guard, only-ineffective moves, absorbing ability on the bench,
--     Natural Cure sleeper, super-effective / boosted stays, immune / resist
--     switch-ins) and TrainerAI_ShouldUseItem (trainer's four item slots,
--     including the "keeps looping and spends every reachable item" quirk).
--   TrainerAI_Main -> G.choose: MainSingles / MainDoubles with the script
--     interpreter (109 opcodes, AICmd_*), s8 move scores, 85..100 damage rolls.
--   BattleAI_PostKOSwitchIn -> G.postKO: which Pokemon replaces a fainted one.
--
-- THE PORT'S STATE IS NOT A BATTLEMON.  The script tests 32-bit masks
-- (MON_CONDITION_*, VOLATILE_CONDITION_*, MOVE_EFFECT_*, SIDE_CONDITION_*,
-- FIELD_CONDITION_*); they are rebuilt here from this engine's battler fields
-- (statusMask, volatileMask, effectMask, sideMask, fieldMask).  Which field
-- stands for which bit is INFERRED from the setters in src/battle/*.lua.
--   Known-ability / known-item bookkeeping (battlerAbilities/battlerHeldItems,
--   filled in the cartridge whenever an ability or item is announced) has no
--   hook in this engine yet: the AI never "knows" a foe's ability beyond the
--   trap abilities and its coin-flip guess, and never knows a foe's item.
--   INFERRED approximation, documented in the battle-ai memory note.

local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot

local G = {}

-- ---------------------------------------------------------------------------
-- constants (pokeplatinum include/constants/..., generated/*.txt)
-- ---------------------------------------------------------------------------

local AI_BATTLER_DEFENDER, AI_BATTLER_ATTACKER = 0, 1
local AI_BATTLER_DEFENDER_PARTNER, AI_BATTLER_ATTACKER_PARTNER = 2, 3

local FLAG_DONE, FLAG_ESCAPE, FLAG_SAFARI, FLAG_BREAK = 1, 2, 4, 8

local AI_FLAG_BASIC = 1
local AI_FLAG_TAG_STRATEGY = 128
local AI_FLAG_ROAMING_POKEMON = 2 ^ 29

local AI_NO_COMPARISON_MADE, AI_NOT_HIGHEST_DAMAGE, AI_MOVE_IS_HIGHEST_DAMAGE = 0, 1, 2
local AI_NOT_HAVE, AI_HAVE, AI_UNKNOWN = 0, 1, 2

local TYPE_MULTI_IMMUNE, TYPE_MULTI_NOT_VERY_EFF, TYPE_MULTI_SUPER_EFF = 0, 5, 20
local TM_QUARTER, TM_HALF, TM_BASE, TM_STAB, TM_DOUBLE, TM_QUAD = 10, 20, 40, 60, 80, 160

local MS_SUPER, MS_NOT_VERY, MS_INEFFECTIVE = 2, 4, 8
-- MOVE_STATUS_IMMUNE = INEFFECTIVE | WONDER_GUARD | LEVITATED | MAGNET_RISE
local MS_WONDER_GUARD, MS_LEVITATED, MS_MAGNET_RISE = 2 ^ 17, 2 ^ 11, 2 ^ 18
local MS_IMMUNE = MS_INEFFECTIVE + MS_WONDER_GUARD + MS_LEVITATED + MS_MAGNET_RISE

local BT_TRAINER, BT_DOUBLES, BT_2VS2, BT_TAG, BT_AI, BT_FRONTIER, BT_ROAMER = 1, 2, 8, 16, 64, 128, 256

-- types by Gen 4 id (MYSTERY is 9)
local TYPE = { NORMAL = 0, FIGHTING = 1, FLYING = 2, POISON = 3, GROUND = 4, ROCK = 5,
  BUG = 6, GHOST = 7, STEEL = 8, MYSTERY = 9, FIRE = 10, WATER = 11, GRASS = 12,
  ELECTRIC = 13, PSYCHIC = 14, ICE = 15, DRAGON = 16, DARK = 17 }
local TYPE_NAME = {}
for k, v in pairs(TYPE) do TYPE_NAME[v] = k end
-- Renegade Platinum names slot 9 FAIRY (its species, moves and chart say so);
-- an alias by name only, so TYPE_NAME[9] stays Platinum's
TYPE.FAIRY = 9
G.TYPE, G.TYPE_NAME = TYPE, TYPE_NAME

local MOVE = { NATURAL_GIFT = 363, JUDGMENT = 449, HIDDEN_POWER = 237, GYRO_BALL = 360,
  DRAGON_RAGE = 82, SEISMIC_TOSS = 69, NIGHT_SHADE = 101, PSYWAVE = 149, RETURN = 216,
  FRUSTRATION = 218, MAGNITUDE = 222, SONIC_BOOM = 49, LOW_KICK = 67, GRASS_KNOT = 447,
  WEATHER_BALL = 311, STRUGGLE = 165, CURSE = 174, PROTECT = 182, DETECT = 197,
  ENDURE = 203 }
G.MOVE = MOVE

-- sNoDamageCalcMoveEffects / sAltPowerMoveEffects (BATTLE_EFFECT_* ids)
local NO_DAMAGE_CALC = { [7] = true, [8] = true, [39] = true, [75] = true, [80] = true,
  [145] = true, [151] = true, [161] = true, [170] = true, [182] = true, [190] = true,
  [248] = true, [269] = true }
local ALT_POWER = { [135] = true, [219] = true, [222] = true, [268] = true, [41] = true,
  [87] = true, [88] = true, [121] = true, [123] = true, [130] = true, [196] = true }
-- MoveIsOnDamagingTurn: the charge-turn effects are not, while the AI thinks
local CHARGE_TURN = { [26] = true, [39] = true, [75] = true, [145] = true, [151] = true,
  [155] = true, [255] = true, [256] = true, [263] = true, [273] = true }

-- hold effects the code reads by number (generated/item_hold_effects.txt)
local HE_POWER_UP_SE, HE_SPEED_DOWN_GROUNDED = 96, 106
local ARCEUS = { [126] = 10, [127] = 11, [128] = 13, [129] = 12, [130] = 15, [131] = 1,
  [132] = 3, [133] = 4, [134] = 2, [135] = 14, [136] = 6, [137] = 5, [138] = 7,
  [139] = 16, [140] = 17, [141] = 8 }

local ITEM_FULL_RESTORE = 23

-- MON_CONDITION_* / VOLATILE_CONDITION_* / MOVE_EFFECT_* / SIDE_ / FIELD_
local MC = { SLEEP = 7, POISON = 8, BURN = 16, FREEZE = 32, PARALYSIS = 64, TOXIC = 128 }
local VC_CONFUSION, VC_TRAPPED_BITS = 7, nil

-- the order the abilities are numbered in (src/import/Gen4Abilities.lua)
local ABILITY_ID
local function abilityId(name)
  if not name then return 0 end
  if not ABILITY_ID then
    ABILITY_ID = {}
    local ok, A = pcall(require, "src.import.Gen4Abilities")
    if ok and A and A.NAMES then
      for i = 0, (A.COUNT or 124) - 1 do
        local n = A.NAMES[i]
        if n then ABILITY_ID[n] = i end
      end
    end
  end
  return ABILITY_ID[name] or 0
end
G.abilityId = abilityId
local AB = setmetatable({}, { __index = function(t, k) local v = abilityId(k) rawset(t, k, v) return v end })

local HOLD_ID
local function holdEffectId(name)
  if not name then return 0 end
  if not HOLD_ID then
    HOLD_ID = {}
    local ok, H = pcall(require, "src.import.Gen4HoldEffects")
    if ok and H and H.name then
      for i = 1, (H.COUNT or 160) do
        local n = H.name(i)
        if n and HOLD_ID[n] == nil then HOLD_ID[n] = i end
      end
    end
  end
  return HOLD_ID[name] or 0
end
G.holdEffectId = holdEffectId

-- ---------------------------------------------------------------------------
-- reading the battle
-- ---------------------------------------------------------------------------

local function moveDef(battle, id)
  local moves = battle.data and battle.data.moves
  return id and moves and moves[id] or nil
end
local function mdEffect(battle, id) local d = moveDef(battle, id) return d and tonumber(d.gen4Effect) or 0 end
local function mdPower(battle, id) local d = moveDef(battle, id) return d and tonumber(d.power) or 0 end
local function mdType(battle, id)
  local d = moveDef(battle, id)
  if not d then return 0 end
  if tonumber(d.typeId) then return tonumber(d.typeId) end
  return TYPE[d.type] or 0
end
local function mdClass(battle, id) local d = moveDef(battle, id) return d and tonumber(d.classId) or 0 end
local function mdRange(battle, id) local d = moveDef(battle, id) return d and tonumber(d.range) or 0 end

local function at(battle, id)
  if id == nil then return nil end
  return battle:battlerAt(id)
end
local function hpOf(b) return (b and b.mon and tonumber(b.mon.hp)) or 0 end
local function maxHpOf(b)
  return (b and ((b.mon and b.mon.stats and b.mon.stats.hp) or (b.curStats and b.curStats.hp))) or 1
end
local function moveAt(b, slot) -- slot is 0-based
  local m = b and b.curMoves and b.curMoves[slot + 1]
  return m and tonumber(m.id) or 0, m
end
local function ppAt(b, slot)
  local m = b and b.curMoves and b.curMoves[slot + 1]
  return m and tonumber(m.pp) or 0
end
local function typesOf(b)
  local t = b and b.curTypes or {}
  local t1 = TYPE[t[1]] or (tonumber(t[1])) or 0
  local t2 = TYPE[t[2] or t[1]] or tonumber(t[2] or t[1]) or t1
  return t1, t2
end
local function hasType(b, typeId)
  local t1, t2 = typesOf(b)
  return t1 == typeId or t2 == typeId
end
local function abilityName(b)
  local ok, A = pcall(require, "src.battle.Abilities")
  if not ok or not b then return nil end
  return A.of(b)
end
-- Battler_Ability: none under Gastro Acid
local function abilityOf(b)
  if not b then return 0 end
  if b.g4Suppressed then return 0 end
  return abilityId(abilityName(b))
end
local function itemIdOf(mon)
  local id = mon and (mon.item or mon.heldItem)
  if id == false then return 0 end
  return tonumber(id) or 0
end
local function itemDef(battle, id)
  local items = battle.data and battle.data.items
  return id and id ~= 0 and items and items[id] or nil
end
local function itemHoldEffect(battle, id)
  local d = itemDef(battle, id)
  return d and holdEffectId(d.holdEffect) or 0
end
-- Battler_HeldItemEffect: nothing under Embargo or Klutz
local function heldEffect(battle, b)
  if not (b and b.mon) then return 0 end
  if (b.g4Embargo or 0) > 0 or abilityName(b) == "KLUTZ" then return 0 end
  return itemHoldEffect(battle, itemIdOf(b.mon))
end
local function heldPower(battle, b)
  local d = b and b.mon and itemDef(battle, itemIdOf(b.mon))
  return d and tonumber(d.holdEffectParam) or 0
end
local function stageOf(b, stat) -- the cartridge's 0..12, 6 neutral
  local st = b and b.stages or {}
  local key = ({ "attack", "defense", "speed", "spatk", "spdef", "accuracy", "evasion" })[stat]
  if not key then return 6 end
  local v = st[key]
  if v == nil and (key == "spatk" or key == "spdef") then v = st.special end
  return 6 + (tonumber(v) or 0)
end
local STAT_KEY = { [0] = "hp", "attack", "defense", "speed", "spatk", "spdef" }

local function statusMask(b)
  local mon = b and b.mon
  local s = mon and mon.status
  if not s or s == "" then return 0 end
  if s == "SLP" then return math.max(1, math.min(7, tonumber(b.sleepTurns or mon.sleepTurns) or 1)) end
  if s == "PSN" then return MC.POISON end
  if s == "BRN" then return MC.BURN end
  if s == "FRZ" then return MC.FREEZE end
  if s == "PAR" then return MC.PARALYSIS end
  if s == "TOX" then return MC.TOXIC end
  return 0
end
G.statusMask = statusMask
local function monStatusMask(mon) return statusMask({ mon = mon }) end

local function on(x) return x ~= nil and x ~= false and x ~= 0 end
local function positive(x) return (tonumber(x) or 0) > 0 end

-- statusVolatile, rebuilt (INFERRED field mapping)
local function volatileMask(b)
  if not b then return 0 end
  local m = 0
  if positive(b.confusedTurns) then m = bor(m, math.min(7, b.confusedTurns)) end
  if b.flinched then m = bor(m, 8) end
  if positive(b.uproarTurns) then m = bor(m, 16) end
  if positive(b.bideTurns) then m = bor(m, 256) end
  if positive(b.thrashTurns) or b.rampMove then m = bor(m, 1024) end
  if positive(b.boundTurns) or b.g4Bound or b.bwBound then m = bor(m, 8192) end
  if on(b.infatuated) then m = bor(m, 65536) end
  if b.focusEnergy then m = bor(m, 2 ^ 20) end
  if b.transformed or b.bwTransformed then m = bor(m, 2 ^ 21) end
  if b.mustRecharge then m = bor(m, 2 ^ 22) end
  if b.rageMove then m = bor(m, 2 ^ 23) end
  if positive(b.substituteHP) then m = bor(m, 2 ^ 24) end
  if b.destinyBond then m = bor(m, 2 ^ 25) end
  if b.trapped then m = bor(m, 2 ^ 26) end
  if b.nightmare then m = bor(m, 2 ^ 27) end
  if b.cursed then m = bor(m, 2 ^ 28) end
  if b.identified or b.g4Foresight then m = bor(m, 2 ^ 29) end
  if b.defenseCurl or b.bwCurled then m = bor(m, 2 ^ 30) end
  if b.tormented then m = bor(m, -2147483648) end
  return m
end
G.volatileMask = volatileMask

-- moveEffectsMask, rebuilt (INFERRED field mapping)
local function effectMask(battle, b)
  if not b then return 0 end
  local m = 0
  if on(b.leechSeeded) then m = bor(m, 4) end
  if on(b.lockedOn) then m = bor(m, 8) end
  if b.perishTurns ~= nil then m = bor(m, 32) end
  if b.invulnerable then m = bor(m, 64) end
  if b.minimized or b.bwMinimized then m = bor(m, 256) end
  if b.charged or b.bwCharged then m = bor(m, 512) end
  if b.ingrained then m = bor(m, 1024) end
  if positive(b.drowsyTurns) then m = bor(m, 2048) end
  if b.g4Imprison or b.bwImprison then m = bor(m, 8192) end
  if b.grudge then m = bor(m, 16384) end
  local f = battle and battle.field or {}
  if f.mudSport then m = bor(m, 65536) end
  if f.waterSport then m = bor(m, 131072) end
  if b.g4Suppressed then m = bor(m, 2 ^ 21) end
  if b.g4MiracleEye or b.bwMiracleEye then m = bor(m, 2 ^ 22) end
  if b.g4PowerTrick then m = bor(m, 2 ^ 23) end
  if b.g4AquaRing or b.bwAquaRing then m = bor(m, 2 ^ 24) end
  if positive(b.g4HealBlock) then m = bor(m, 2 ^ 25) end
  if positive(b.g4Embargo) then m = bor(m, 2 ^ 26) end
  if positive(b.g4MagnetRise) then m = bor(m, 2 ^ 27) end
  return m
end
G.effectMask = effectMask

local function g4side(battle, isPlayer)
  local s = battle.g4fx
  return s and s.sides and s.sides[isPlayer and true or false] or {}
end
-- sideConditionsMask for the side `isPlayer` (INFERRED field mapping)
local function sideMask(battle, isPlayer)
  local s = g4side(battle, isPlayer)
  local m = 0
  if positive(s.reflect) then m = bor(m, 1) end
  if positive(s.lightScreen) then m = bor(m, 2) end
  local engine = battle.sides and battle.sides[isPlayer and 1 or 2]
  if engine and positive(engine.spikes) then m = bor(m, 4) end
  local safe, mist, wish = false, false, false
  for pos = 0, 3 do
    local b = at(battle, pos)
    if b and (b.isPlayer and true or false) == (isPlayer and true or false) then
      if positive(b.safeguardTurns) then safe = true end
      if b.mist then mist = true end
      if positive(b.wishTurns) then wish = true end
      if b.reflect then m = bor(m, 1) end
      if b.lightScreen then m = bor(m, 2) end
    end
  end
  if safe then m = bor(m, 8) end
  if s.futureSight then m = bor(m, 16) end
  if wish then m = bor(m, 32) end
  if mist then m = bor(m, 64) end
  if s.stealthRock then m = bor(m, 128) end
  if positive(s.tailwind) then m = bor(m, 256) end
  if positive(s.toxicSpikes) then m = bor(m, 1024) end
  if positive(s.luckyChant) then m = bor(m, 4096) end
  return m
end
G.sideMask = sideMask

local function weather(battle)
  local ok, W = pcall(require, "src.battle.Weather")
  return ok and W.current(battle) or nil
end
local function fieldMask(battle)
  local m = 0
  local w = weather(battle)
  if w == "RAIN" then m = bor(m, 1) elseif w == "SANDSTORM" then m = bor(m, 4)
  elseif w == "SUN" then m = bor(m, 16) elseif w == "HAIL" then m = bor(m, 64) end
  local s = battle.g4fx and battle.g4fx.field or {}
  if positive(s.gravity) then m = bor(m, 4096) end
  if battle.deepFog and battle:deepFog() then m = bor(m, 32768) end
  local f = battle.field or {}
  if positive(f.trickRoom) or positive(s.trickRoom) then m = bor(m, 65536) end
  for pos = 0, 3 do
    local b = at(battle, pos)
    if b and positive(b.uproarTurns) then m = bor(m, 256) end
  end
  return m
end
G.fieldMask = fieldMask

-- battleType, as the AI reads it (BATTLE_TYPE_*)
function G.battleType(battle)
  local t = 0
  if battle.kind == "trainer" then t = bor(t, BT_TRAINER) end
  if battle:isDouble() then t = bor(t, BT_DOUBLES) end
  if battle.trainerB then t = bor(t, BT_2VS2) end
  if battle.ally then t = bor(t, BT_2VS2 + BT_AI) end
  if battle.trainer and (battle.trainer.battleTower or battle.trainer.frontier) or battle.frontier then
    t = bor(t, BT_FRONTIER)
  end
  if battle.battleType == "roaming" then t = bor(t, BT_ROAMER) end
  return t
end

-- the Pokemon list a battler draws its bench from, and which slots are out
local function partyFor(battle, id)
  return battle:benchFor(id % 2 == 0, id) or {}
end
local function partySlotOf(battle, id)
  local b = at(battle, id)
  if not (b and b.mon) then return -1 end
  for i, mon in ipairs(partyFor(battle, id)) do
    if mon == b.mon then return i - 1 end
  end
  return -1
end
local function isEgg(mon)
  local ok, Party = pcall(require, "src.pokemon.Party")
  return mon == nil or (ok and Party.isEgg and Party.isEgg(mon)) or mon.isEgg
end
local function usable(mon) return mon and (tonumber(mon.hp) or 0) > 0 and not isEgg(mon) end

local function monDef(battle, mon)
  local ok, F = pcall(require, "src.pokemon.Gen4Forms")
  if ok and F.definition then
    local okD, def = pcall(F.definition, battle.data, mon)
    if okD and def then return def end
  end
  return battle.data.pokemon and battle.data.pokemon[mon.species] or {}
end
local function monTypes(battle, mon)
  local def = monDef(battle, mon)
  local t = def.types or {}
  local t1 = TYPE[t[1]] or 0
  return t1, TYPE[t[2] or t[1]] or t1
end
local function monAbility(battle, mon)
  return abilityId(abilityName({ mon = mon, def = monDef(battle, mon) }))
end

-- ---------------------------------------------------------------------------
-- the type chart (BattleSystem_ApplyTypeChart / CalcEffectiveness)
-- ---------------------------------------------------------------------------

local function chartRows(battle)
  local tc = battle.data and battle.data.type_chart
  local cache = battle._g4aiChart
  if cache then return cache end
  local rows, ghost = {}, {}
  if tc and tc.matchups then
    for _, r in ipairs(tc.matchups) do
      rows[#rows + 1] = { TYPE[r.attacker] or -1, TYPE[r.defender] or -1, tonumber(r.multiplier) or 10 }
    end
    for _, r in ipairs(tc.foresight or {}) do
      ghost[#ghost + 1] = { TYPE[r[1]] or -1, TYPE[r[2]] or -1, 0 }
    end
  end
  cache = { rows = rows, ghost = ghost }
  battle._g4aiChart = cache
  return cache
end

local function updateMul(mul, flags)
  if mul == TYPE_MULTI_IMMUNE then
    flags = bor(flags, MS_INEFFECTIVE)
    flags = band(flags, bnot(MS_NOT_VERY)); flags = band(flags, bnot(MS_SUPER))
  elseif mul == TYPE_MULTI_NOT_VERY_EFF then
    if band(flags, MS_SUPER) ~= 0 then flags = band(flags, bnot(MS_SUPER))
    else flags = bor(flags, MS_NOT_VERY) end
  elseif mul == TYPE_MULTI_SUPER_EFF then
    if band(flags, MS_NOT_VERY) ~= 0 then flags = band(flags, bnot(MS_NOT_VERY))
    else flags = bor(flags, MS_SUPER) end
  end
  return flags
end

local function ignorable(battle, attacker, defender, name)
  if abilityName(attacker) == "MOLD_BREAKER" then return false end
  return abilityName(defender) == name and not (defender and defender.g4Suppressed)
end

-- BattleSystem_ApplyTypeChart; `ignoreTypes` is SYSCTL_IGNORE_TYPE_CHECKS
function G.applyTypeChart(battle, move, inType, attacker, defender, damage, ignoreTypes)
  local flags = 0
  if move == MOVE.STRUGGLE then return damage, flags end
  local moveType
  if abilityName(attacker) == "NORMALIZE" then moveType = 0
  elseif inType and inType ~= 0 then moveType = inType
  else moveType = mdType(battle, move) end
  local power = mdPower(battle, move)
  if not ignoreTypes and hasType(attacker, moveType) then
    if abilityName(attacker) == "ADAPTABILITY" then damage = damage * 2
    else damage = math.floor(damage * 15 / 10) end
  end
  local dItem = heldEffect(battle, defender)
  local gravity = band(fieldMask(battle), 4096) ~= 0
  if ignorable(battle, attacker, defender, "LEVITATE") and moveType == TYPE.GROUND
     and dItem ~= HE_SPEED_DOWN_GROUNDED then
    flags = bor(flags, MS_LEVITATED)
  elseif positive(defender and defender.g4MagnetRise) and not (defender and defender.ingrained)
     and moveType == TYPE.GROUND and dItem ~= HE_SPEED_DOWN_GROUNDED then
    flags = bor(flags, MS_MAGNET_RISE)
  else
    local d1, d2 = typesOf(defender)
    local dEffects = effectMask(battle, defender)
    local function applies(row)
      if (dItem == HE_SPEED_DOWN_GROUNDED or band(dEffects, 1024) ~= 0)
         and row[2] == TYPE.FLYING and row[3] == TYPE_MULTI_IMMUNE then return false end
      if defender and (defender.g4Roost or defender.bwRoost) and row[2] == TYPE.FLYING then return false end
      if gravity and row[2] == TYPE.FLYING and row[3] == TYPE_MULTI_IMMUNE then return false end
      if band(dEffects, 2 ^ 22) ~= 0 and row[2] == TYPE.DARK and row[3] == TYPE_MULTI_IMMUNE then return false end
      return true
    end
    local function apply(row)
      -- BattleSystem_Divide: a non-zero product never rounds to 0
      if not ignoreTypes and damage ~= 0 then
        damage = row[3] == 0 and 0 or math.max(1, math.floor(damage * row[3] / 10))
      end
      if row[3] == TYPE_MULTI_IMMUNE then flags = updateMul(TYPE_MULTI_IMMUNE, flags)
      else flags = updateMul(row[3], flags) end
    end
    local chart = chartRows(battle)
    local lists = { chart.rows }
    if not (band(volatileMask(defender), 2 ^ 29) ~= 0 or abilityName(attacker) == "SCRAPPY") then
      lists[2] = chart.ghost
    end
    for _, list in ipairs(lists) do
      for _, row in ipairs(list) do
        if row[1] == moveType then
          if row[2] == d1 and applies(row) then apply(row) end
          if row[2] == d2 and d1 ~= d2 and applies(row) then apply(row) end
        end
      end
    end
  end
  local effect = mdEffect(battle, move)
  if ignorable(battle, attacker, defender, "WONDER_GUARD") and not CHARGE_TURN[effect]
     and (band(flags, MS_SUPER) == 0 or band(flags, MS_SUPER + MS_NOT_VERY) == MS_SUPER + MS_NOT_VERY)
     and power ~= 0 then
    flags = bor(flags, MS_WONDER_GUARD)
  elseif not ignoreTypes then
    if band(flags, MS_SUPER) ~= 0 and power ~= 0 then
      if ignorable(battle, attacker, defender, "FILTER") or ignorable(battle, attacker, defender, "SOLID_ROCK") then
        damage = math.floor(damage * 3 / 4)
      end
      if heldEffect(battle, attacker) == HE_POWER_UP_SE then
        damage = math.floor(damage * (100 + heldPower(battle, attacker)) / 100)
      end
    end
    if band(flags, MS_NOT_VERY) ~= 0 and power ~= 0 and abilityName(attacker) == "TINTED_LENS" then
      damage = damage * 2
    end
  else
    flags = band(flags, bnot(MS_SUPER)); flags = band(flags, bnot(MS_NOT_VERY))
  end
  return damage, flags
end

-- BattleSystem_CalcEffectiveness: a bench Pokemon's move against a battler
-- (or a battler's move against a bench Pokemon), by numbers only
function G.calcEffectiveness(battle, move, inType, atkAbility, defAbility, defItemEffect, d1, d2)
  local flags = 0
  if move == MOVE.STRUGGLE then return flags end
  local moveType
  if atkAbility == AB.NORMALIZE then moveType = 0
  elseif inType and inType ~= 0 then moveType = inType
  else moveType = mdType(battle, move) end
  local gravity = band(fieldMask(battle), 4096) ~= 0
  if atkAbility ~= AB.MOLD_BREAKER and defAbility == AB.LEVITATE and moveType == TYPE.GROUND
     and not gravity and defItemEffect ~= HE_SPEED_DOWN_GROUNDED then
    flags = bor(flags, MS_INEFFECTIVE)
  else
    local function ok(row)
      if defItemEffect == HE_SPEED_DOWN_GROUNDED and row[2] == TYPE.FLYING and row[3] == 0 then return false end
      if gravity and row[2] == TYPE.FLYING and row[3] == 0 then return false end
      return true
    end
    local chart = chartRows(battle)
    local lists = { chart.rows }
    if atkAbility ~= AB.SCRAPPY then lists[2] = chart.ghost end
    for _, list in ipairs(lists) do
      for _, row in ipairs(list) do
        if row[1] == moveType then
          if row[2] == d1 and ok(row) then flags = updateMul(row[3], flags) end
          if row[2] == d2 and d1 ~= d2 and ok(row) then flags = updateMul(row[3], flags) end
        end
      end
    end
  end
  if atkAbility ~= AB.MOLD_BREAKER and defAbility == AB.WONDER_GUARD
     and not CHARGE_TURN[mdEffect(battle, move)]
     and (band(flags, MS_SUPER) == 0 or band(flags, MS_SUPER + MS_NOT_VERY) == MS_SUPER + MS_NOT_VERY) then
    flags = bor(flags, MS_INEFFECTIVE)
  end
  return flags
end

-- BattleSystem_TypeMatchupMultiplier (post-KO scoring)
function G.matchup(battle, atkType, d1, d2)
  local mul = 40
  local chart = chartRows(battle)
  for _, list in ipairs({ chart.rows, chart.ghost }) do
    for _, row in ipairs(list) do
      if row[1] == atkType then
        if row[2] == d1 then mul = math.floor(mul * row[3] / 10) end
        if row[2] == d2 and d1 ~= d2 then mul = math.floor(mul * row[3] / 10) end
      end
    end
  end
  return mul
end

-- ---------------------------------------------------------------------------
-- variable move types and the AI's damage
-- ---------------------------------------------------------------------------

local function ivsOf(mon)
  local iv = mon and mon.ivs or {}
  return { tonumber(iv.hp) or 0, tonumber(iv.attack) or 0, tonumber(iv.defense) or 0,
           tonumber(iv.speed) or 0, tonumber(iv.spatk) or 0, tonumber(iv.spdef) or 0 }
end
local function hiddenPowerType(ivs)
  local r = (ivs[1] % 2) + (ivs[2] % 2) * 2 + (ivs[3] % 2) * 4 + (ivs[4] % 2) * 8
            + (ivs[5] % 2) * 16 + (ivs[6] % 2) * 32
  r = math.floor(r * 15 / 63) + 1
  if r >= TYPE.MYSTERY then r = r + 1 end
  return r
end
local function hiddenPowerPower(ivs)
  local function b2(v) return math.floor(v / 2) % 2 end
  local p = b2(ivs[1]) + b2(ivs[2]) * 2 + b2(ivs[3]) * 4 + b2(ivs[4]) * 8 + b2(ivs[5]) * 16 + b2(ivs[6]) * 32
  return math.floor(p * 40 / 63) + 30
end

-- TrainerAI_MoveType: 0 (TYPE_NORMAL -> "use the move's own") unless variable
local function aiMoveType(battle, b, move)
  if move == MOVE.NATURAL_GIFT then
    local d = b and b.mon and itemDef(battle, itemIdOf(b.mon))
    local t = d and tonumber(d.naturalGiftType) or 0
    return (t and t < 18) and t or 0
  elseif move == MOVE.JUDGMENT then
    return ARCEUS[heldEffect(battle, b)] or 0
  elseif move == MOVE.HIDDEN_POWER then
    return hiddenPowerType(ivsOf(b and b.mon))
  elseif move == MOVE.WEATHER_BALL then
    local w = weather(battle)
    if w == "RAIN" then return TYPE.WATER elseif w == "SANDSTORM" then return TYPE.ROCK
    elseif w == "SUN" then return TYPE.FIRE elseif w == "HAIL" then return TYPE.ICE end
    -- BUG kept: an unset `result` in the C; clear weather reads as 0
    return 0
  end
  return 0
end
G.aiMoveType = aiMoveType

-- Move_CalcVariableType for a bench Pokemon
local function benchMoveType(battle, mon, move)
  if move == MOVE.NATURAL_GIFT then
    local d = itemDef(battle, itemIdOf(mon))
    return d and tonumber(d.naturalGiftType) or 0
  elseif move == MOVE.JUDGMENT then
    return ARCEUS[itemHoldEffect(battle, itemIdOf(mon))] or 0
  elseif move == MOVE.HIDDEN_POWER then
    return hiddenPowerType(ivsOf(mon))
  end
  return 0
end

local function speedOf(battle, b)
  if not b then return 0 end
  local ok, TO = pcall(require, "src.battle.TurnOrder")
  if ok and TO.effectiveSpeed then
    local okS, s = pcall(TO.effectiveSpeed, b, battle)
    if okS and s then return s end
  end
  return (b.curStats and b.curStats.speed) or 1
end

local function rollTop(_, hi) return hi end

-- TrainerAI_CalcDamage (crit x1, the roll applied after the type chart)
function G.calcDamage(ctx, move, attacker, variance, ivsOverride, monOverride)
  local battle = ctx.battle
  local defender = at(battle, ctx.def)
  if not (attacker and defender) or move == 0 then return 0 end
  local def = moveDef(battle, move)
  if not def then return 0 end
  local power, mtype, damage = nil, nil, 0
  local amon = monOverride or attacker.mon
  local ivs = ivsOverride or ivsOf(amon)
  local ab = abilityName(attacker)
  local embargo = (attacker.g4Embargo or 0) > 0
  if move == MOVE.NATURAL_GIFT then
    if ab ~= "KLUTZ" and not embargo then
      local d = itemDef(battle, itemIdOf(amon))
      power = d and tonumber(d.naturalGiftPower) or 0
      mtype = (power ~= 0) and (tonumber(d.naturalGiftType) or 0) or 0
    end
  elseif move == MOVE.JUDGMENT then
    if ab ~= "KLUTZ" and not embargo then
      mtype = ARCEUS[itemHoldEffect(battle, itemIdOf(amon))] or 0
    end
  elseif move == MOVE.HIDDEN_POWER then
    power, mtype = hiddenPowerPower(ivs), hiddenPowerType(ivs)
  elseif move == MOVE.GYRO_BALL then
    power = math.min(150, 1 + math.floor(25 * speedOf(battle, defender) / math.max(1, speedOf(battle, attacker))))
  elseif move == MOVE.DRAGON_RAGE then damage = 40
  elseif move == MOVE.SEISMIC_TOSS or move == MOVE.NIGHT_SHADE then damage = tonumber(amon.level) or 1
  elseif move == MOVE.PSYWAVE then
    damage = math.floor((tonumber(amon.level) or 1) * (ctx.rand() % 11 + 5) / 10)
  elseif move == MOVE.RETURN then power = math.floor((tonumber(amon.friendship) or 0) * 10 / 25)
  elseif move == MOVE.FRUSTRATION then power = math.floor((255 - (tonumber(amon.friendship) or 0)) * 10 / 25)
  elseif move == MOVE.MAGNITUDE then
    local r = ctx.rand() % 100
    power = r < 5 and 10 or r < 15 and 30 or r < 35 and 50 or r < 65 and 70 or r < 85 and 90 or r < 95 and 110 or 150
  elseif move == MOVE.SONIC_BOOM then damage = 20
  elseif move == MOVE.LOW_KICK or move == MOVE.GRASS_KNOT then
    -- sWeightToPower; INFERRED: Platinum's species rows carry no weight in
    -- this engine, so a battler without one reads as the lightest bracket
    local w = tonumber(defender.def and defender.def.weight) or 0
    power = w <= 100 and 20 or w <= 250 and 40 or w <= 500 and 60 or w <= 1000 and 80 or w <= 2000 and 100 or 120
  end
  if damage == 0 then
    local view = def
    if (power and power ~= 0) or (mtype and mtype ~= 0) then
      view = setmetatable({ power = (power and power ~= 0) and power or def.power,
                            type = (mtype and mtype ~= 0) and TYPE_NAME[mtype] or def.type,
                            typeId = (mtype and mtype ~= 0) and mtype or def.typeId }, { __index = def })
    end
    -- the engine's own formula (Gen4Damage, which already applies STAB and
    -- the type chart) with the roll at the top of its range and no crit
    local ok, d = pcall(battle.computeDamage, battle, attacker, defender, view,
                        { dryRun = true, rng = rollTop, forceCrit = false })
    damage = ok and tonumber(d) or 0
  else
    local _, flags = G.applyTypeChart(battle, move, mtype or 0, attacker, defender, damage, true)
    if band(flags, MS_IMMUNE) ~= 0 then damage = 0 end
  end
  if damage == 0 then return 0 end
  damage = math.floor(damage * variance / 100)
  if damage == 0 then damage = 1 end
  return damage
end

local function scoresDamage(battle, move)
  local e = mdEffect(battle, move)
  return ALT_POWER[e] or (mdPower(battle, move) > 1 and not NO_DAMAGE_CALC[e])
end

-- TrainerAI_CalcAllDamage over a move list (move ids by 0-based slot)
function G.calcAll(ctx, attacker, moves, varyDamage, monOverride)
  local vals, best = {}, 0
  for i = 0, 3 do
    local move = moves[i] or 0
    local e = mdEffect(ctx.battle, move)
    if ALT_POWER[e] or (move ~= 0 and not NO_DAMAGE_CALC[e] and mdPower(ctx.battle, move) > 1) then
      local roll = varyDamage and ctx.rolls[i] or 100
      vals[i] = G.calcDamage(ctx, move, attacker, roll, nil, monOverride)
    else
      vals[i] = 0
    end
    if vals[i] > best then best = vals[i] end
  end
  return best, vals
end

local function movesOf(b)
  local out = {}
  for i = 0, 3 do out[i] = (moveAt(b, i)) end
  return out
end
local function monMoves(mon)
  local out = {}
  for i = 0, 3 do
    local m = mon and mon.moves and mon.moves[i + 1]
    out[i] = m and tonumber(m.id) or 0
  end
  return out
end

-- BattleSystem_CompareBattlerSpeed(.., ignoreQuickClaw = TRUE), INFERRED as
-- the effective speeds under Trick Room, ties a tie
local function compareSpeed(battle, a, b)
  local sa, sb = speedOf(battle, a), speedOf(battle, b)
  if sa == sb then return 2 end
  local tr = band(fieldMask(battle), 65536) ~= 0
  if tr then return (sa < sb) and 0 or 1 end
  return (sa > sb) and 0 or 1
end

-- ---------------------------------------------------------------------------
-- the interpreter
-- ---------------------------------------------------------------------------

local function read(ctx)
  local v = ctx.words[ctx.cursor + 1] or 0
  ctx.cursor = ctx.cursor + 1
  return v
end
local function iter(ctx, n) ctx.cursor = ctx.cursor + n end
local function readOffset(ctx, ofs) return ctx.words[ctx.cursor + ofs + 1] or -1 end

local function who(ctx, inBattler)
  if inBattler == AI_BATTLER_ATTACKER then return ctx.atk end
  if inBattler == AI_BATTLER_ATTACKER_PARTNER then return bxor(ctx.atk, 2) end
  if inBattler == AI_BATTLER_DEFENDER_PARTNER then return bxor(ctx.def, 2) end
  return ctx.def
end
local function B(ctx, id) return at(ctx.battle, id) end

local function addScore(ctx, by)
  local s = (ctx.score[ctx.slot] or 0) + by
  s = ((s + 128) % 256) - 128 -- s8
  if s < 0 then s = 0 end
  ctx.score[ctx.slot] = s
end

local function knownMoves(ctx, id)
  local b = B(ctx, id)
  if not b then return {} end
  b.g4aiKnownMoves = b.g4aiKnownMoves or {}
  return b.g4aiKnownMoves
end
local function prevMove(b) return b and tonumber(b.lastMove) or 0 end

-- conditional-jump helper: reads the listed operands, then the jump
local function cond(n, test)
  return function(ctx)
    iter(ctx, 1)
    local a = {}
    for i = 1, n do a[i] = read(ctx) end
    local jump = read(ctx)
    if test(ctx, a[1], a[2], a[3]) then iter(ctx, jump) end
  end
end

local function hpPercent(b) return math.floor(hpOf(b) * 100 / math.max(1, maxHpOf(b))) end

local OP = {}
G.OP = OP
OP[0] = cond(1, function(ctx, v) return ctx.rand() % 256 < v end)
OP[1] = cond(1, function(ctx, v) return ctx.rand() % 256 > v end)
OP[2] = cond(1, function(ctx, v) return ctx.rand() % 256 == v end)
OP[3] = cond(1, function(ctx, v) return ctx.rand() % 256 ~= v end)
OP[4] = function(ctx) iter(ctx, 1) addScore(ctx, read(ctx)) end
OP[5] = cond(2, function(ctx, w, p) return hpPercent(B(ctx, who(ctx, w))) < p end)
OP[6] = cond(2, function(ctx, w, p) return hpPercent(B(ctx, who(ctx, w))) > p end)
OP[7] = cond(2, function(ctx, w, p) return hpPercent(B(ctx, who(ctx, w))) == p end)
OP[8] = cond(2, function(ctx, w, p) return hpPercent(B(ctx, who(ctx, w))) ~= p end)
OP[9] = cond(2, function(ctx, w, m) return band(statusMask(B(ctx, who(ctx, w))), m) ~= 0 end)
OP[10] = cond(2, function(ctx, w, m) return band(statusMask(B(ctx, who(ctx, w))), m) == 0 end)
OP[11] = cond(2, function(ctx, w, m) return band(volatileMask(B(ctx, who(ctx, w))), m) ~= 0 end)
OP[12] = cond(2, function(ctx, w, m) return band(volatileMask(B(ctx, who(ctx, w))), m) == 0 end)
OP[13] = cond(2, function(ctx, w, m) return band(effectMask(ctx.battle, B(ctx, who(ctx, w))), m) ~= 0 end)
OP[14] = cond(2, function(ctx, w, m) return band(effectMask(ctx.battle, B(ctx, who(ctx, w))), m) == 0 end)
local function sideOfId(id) return id % 2 == 0 end -- true = the player's side
OP[15] = cond(2, function(ctx, w, m) return band(sideMask(ctx.battle, sideOfId(who(ctx, w))), m) ~= 0 end)
OP[16] = cond(2, function(ctx, w, m) return band(sideMask(ctx.battle, sideOfId(who(ctx, w))), m) == 0 end)
OP[17] = cond(1, function(ctx, v) return ctx.temp < v end)
OP[18] = cond(1, function(ctx, v) return ctx.temp > v end)
OP[19] = cond(1, function(ctx, v) return ctx.temp == v end)
OP[20] = cond(1, function(ctx, v) return ctx.temp ~= v end)
OP[21] = cond(1, function(ctx, v) return band(ctx.temp, v) ~= 0 end)
OP[22] = cond(1, function(ctx, v) return band(ctx.temp, v) == 0 end)
OP[23] = cond(1, function(ctx, v) return ctx.move == v end)
OP[24] = cond(1, function(ctx, v) return ctx.move ~= v end)
OP[25] = function(ctx)
  iter(ctx, 1)
  local ofs, jump = read(ctx), read(ctx)
  while true do
    local v = readOffset(ctx, ofs)
    if v == -1 then break end
    if ctx.temp == v then iter(ctx, jump) break end
    ofs = ofs + 1
  end
end
OP[26] = function(ctx)
  iter(ctx, 1)
  local ofs, jump = read(ctx), read(ctx)
  while true do
    local v = readOffset(ctx, ofs)
    if v == -1 then break end
    if ctx.temp == v then return end
    ofs = ofs + 1
  end
  iter(ctx, jump)
end
local function hasDamaging(ctx)
  local b = B(ctx, ctx.atk)
  for i = 0, 3 do
    local m = moveAt(b, i)
    if m ~= 0 and mdPower(ctx.battle, m) ~= 0 then return true end
  end
  return false
end
OP[27] = cond(0, function(ctx) return hasDamaging(ctx) end)
OP[28] = cond(0, function(ctx) return not hasDamaging(ctx) end)
OP[29] = function(ctx) iter(ctx, 1) ctx.temp = ctx.turns end
OP[30] = function(ctx)
  iter(ctx, 1)
  local p = read(ctx)
  local a, d = B(ctx, ctx.atk), B(ctx, ctx.def)
  if p == 0 then ctx.temp = (typesOf(d))
  elseif p == 1 then ctx.temp = (typesOf(a))
  elseif p == 2 then ctx.temp = select(2, typesOf(d))
  elseif p == 3 then ctx.temp = select(2, typesOf(a))
  elseif p == 4 then ctx.temp = mdType(ctx.battle, ctx.move)
  elseif p == 5 then ctx.temp = (typesOf(B(ctx, bxor(ctx.def, 2))))
  elseif p == 6 then ctx.temp = (typesOf(B(ctx, bxor(ctx.atk, 2))))
  elseif p == 7 then ctx.temp = (typesOf(B(ctx, bxor(ctx.def, 2)))) -- BUG kept: TYPE_1
  elseif p == 8 then ctx.temp = select(2, typesOf(B(ctx, bxor(ctx.atk, 2)))) end
end
OP[31] = function(ctx) iter(ctx, 1) ctx.temp = mdPower(ctx.battle, ctx.move) end
OP[32] = function(ctx)
  iter(ctx, 1)
  local vary = read(ctx) ~= 0
  if scoresDamage(ctx.battle, ctx.move) then
    local a = B(ctx, ctx.atk)
    local _, vals = G.calcAll(ctx, a, movesOf(a), vary)
    local higher = false
    for i = 0, 3 do if vals[i] > vals[ctx.slot] then higher = true break end end
    ctx.temp = higher and AI_NOT_HIGHEST_DAMAGE or AI_MOVE_IS_HIGHEST_DAMAGE
  else
    ctx.temp = AI_NO_COMPARISON_MADE
  end
end
OP[33] = function(ctx) iter(ctx, 1) ctx.temp = prevMove(B(ctx, who(ctx, read(ctx)))) end
OP[34] = cond(1, function(ctx, v) return v == ctx.temp end)
OP[35] = cond(1, function(ctx, v) return v ~= ctx.temp end)
OP[36] = cond(1, function(ctx, v) return compareSpeed(ctx.battle, B(ctx, ctx.atk), B(ctx, ctx.def)) == v end)
OP[37] = cond(1, function(ctx, v) return compareSpeed(ctx.battle, B(ctx, ctx.atk), B(ctx, ctx.def)) ~= v end)

-- the bench: Pokemon in the battler's party that are neither of the two out
local function benchSlots(ctx, id, pairSlots)
  local battle = ctx.battle
  local s1 = partySlotOf(battle, id)
  local s2 = s1
  if pairSlots then s2 = partySlotOf(battle, bxor(id, 2)) end
  return s1, s2
end
OP[38] = function(ctx)
  iter(ctx, 1)
  local id = who(ctx, read(ctx))
  ctx.temp = 0
  local doubles = band(ctx.btype, BT_DOUBLES) ~= 0
  local s1, s2 = benchSlots(ctx, id, doubles)
  for i, mon in ipairs(partyFor(ctx.battle, id)) do
    if i - 1 ~= s1 and i - 1 ~= s2 and usable(mon) then ctx.temp = ctx.temp + 1 end
  end
end
OP[39] = function(ctx) iter(ctx, 1) ctx.temp = ctx.move end
OP[40] = function(ctx) iter(ctx, 1) ctx.temp = mdEffect(ctx.battle, ctx.move) end

local TRAPPERS = { SHADOW_TAG = true, MAGNET_PULL = true, ARENA_TRAP = true }
local function speciesAbilities(b)
  local list = b and b.def and b.def.abilities or {}
  local a1 = abilityId(list[1])
  local a2 = abilityId(list[2])
  return a1, a2
end
OP[41] = function(ctx)
  iter(ctx, 1)
  local inB = read(ctx)
  local id = who(ctx, inB)
  local b = B(ctx, id)
  if band(effectMask(ctx.battle, b), 2 ^ 21) ~= 0 then ctx.temp = 0
  elseif ctx.atk ~= id and inB ~= AI_BATTLER_ATTACKER_PARTNER then
    local known = b and b.g4aiKnownAbility
    if known and known ~= 0 then ctx.temp = known
    elseif TRAPPERS[abilityName(b) or ""] then ctx.temp = abilityOf(b)
    else
      local a1, a2 = speciesAbilities(b)
      if a1 ~= 0 and a2 ~= 0 then
        if ctx.rand() % 2 == 1 then ctx.temp = a1 else ctx.temp = a2 end
      elseif a1 ~= 0 then ctx.temp = a1 else ctx.temp = a2 end
    end
  else
    ctx.temp = abilityOf(b)
  end
end
OP[42] = function(ctx)
  iter(ctx, 1)
  ctx.temp = TYPE_MULTI_IMMUNE
  local a, d = B(ctx, ctx.atk), B(ctx, ctx.def)
  for i = 0, 3 do
    local move = moveAt(a, i)
    if move ~= 0 then
      local dmg, flags = G.applyTypeChart(ctx.battle, move, aiMoveType(ctx.battle, a, move), a, d, TM_BASE)
      if dmg == TM_STAB * 2 then dmg = TM_DOUBLE
      elseif dmg == TM_STAB * 4 then dmg = TM_QUAD
      elseif dmg == math.floor(TM_STAB / 2) then dmg = TM_HALF
      elseif dmg == math.floor(TM_STAB / 4) then dmg = TM_QUARTER end
      if band(flags, MS_IMMUNE) ~= 0 then dmg = TYPE_MULTI_IMMUNE end
      if ctx.temp < dmg then ctx.temp = dmg end
    end
  end
end
OP[43] = function(ctx)
  iter(ctx, 1)
  local expected, jump = read(ctx), read(ctx)
  local a, d = B(ctx, ctx.atk), B(ctx, ctx.def)
  local dmg, flags = G.applyTypeChart(ctx.battle, ctx.move, aiMoveType(ctx.battle, a, ctx.move), a, d, TM_BASE)
  if dmg == TM_STAB * 2 then dmg = TM_DOUBLE
  elseif dmg == TM_STAB * 4 then dmg = TM_QUAD
  elseif dmg == math.floor(TM_STAB / 2) then dmg = TM_HALF
  elseif dmg == math.floor(TM_STAB / 4) then dmg = TM_QUARTER end
  if band(flags, MS_IMMUNE) ~= 0 then dmg = TYPE_MULTI_IMMUNE end
  if dmg == expected then iter(ctx, jump) end
end
local function partyStatus(ctx, w, mask, want)
  local id = who(ctx, w)
  local doubles = band(ctx.btype, BT_DOUBLES) ~= 0
  local s1, s2 = benchSlots(ctx, id, doubles)
  for i, mon in ipairs(partyFor(ctx.battle, id)) do
    if i - 1 ~= s1 and i - 1 ~= s2 and usable(mon) then
      local has = band(monStatusMask(mon), mask) ~= 0
      if has == want then return true end
    end
  end
  return false
end
OP[44] = cond(2, function(ctx, w, m) return partyStatus(ctx, w, m, true) end)
OP[45] = cond(2, function(ctx, w, m) return partyStatus(ctx, w, m, false) end)
OP[46] = function(ctx)
  iter(ctx, 1)
  local w = weather(ctx.battle)
  ctx.temp = 0
  if w == "RAIN" then ctx.temp = 2 end
  if w == "SANDSTORM" then ctx.temp = 3 end
  if w == "SUN" then ctx.temp = 1 end
  if w == "HAIL" then ctx.temp = 4 end
  if ctx.battle.deepFog and ctx.battle:deepFog() then ctx.temp = 5 end
end
OP[47] = cond(1, function(ctx, v) return mdEffect(ctx.battle, ctx.move) == v end)
OP[48] = cond(1, function(ctx, v) return mdEffect(ctx.battle, ctx.move) ~= v end)
OP[49] = cond(3, function(ctx, w, s, v) return stageOf(B(ctx, who(ctx, w)), s) < v end)
OP[50] = cond(3, function(ctx, w, s, v) return stageOf(B(ctx, who(ctx, w)), s) > v end)
OP[51] = cond(3, function(ctx, w, s, v) return stageOf(B(ctx, who(ctx, w)), s) == v end)
OP[52] = cond(3, function(ctx, w, s, v) return stageOf(B(ctx, who(ctx, w)), s) ~= v end)
local function killDamage(ctx, roll)
  if not scoresDamage(ctx.battle, ctx.move) then return nil end
  return G.calcDamage(ctx, ctx.move, B(ctx, ctx.atk), roll)
end
OP[53] = function(ctx)
  iter(ctx, 1)
  local useRoll, jump = read(ctx), read(ctx)
  local dmg = killDamage(ctx, useRoll == 1 and ctx.rolls[ctx.slot] or 100)
  if dmg and hpOf(B(ctx, ctx.def)) <= dmg then iter(ctx, jump) end
end
OP[54] = function(ctx)
  iter(ctx, 1)
  local useRoll, jump = read(ctx), read(ctx)
  local dmg = killDamage(ctx, useRoll == 1 and ctx.rolls[ctx.slot] or 100)
  if dmg and hpOf(B(ctx, ctx.def)) > dmg then iter(ctx, jump) end
end
local function knows(ctx, inB, test)
  local id = who(ctx, inB)
  local b = B(ctx, id)
  if inB == AI_BATTLER_ATTACKER then
    for i = 0, 3 do if test((moveAt(b, i))) then return true end end
    return false
  elseif inB == AI_BATTLER_ATTACKER_PARTNER then
    if hpOf(b) == 0 then return nil end
    for i = 0, 3 do if test((moveAt(b, i))) then return true end end
    return false
  elseif inB == AI_BATTLER_DEFENDER then
    local km = knownMoves(ctx, id)
    for i = 1, 4 do if test(km[i] or 0) then return true end end
    return false
  end
  return nil
end
OP[55] = cond(2, function(ctx, w, mv) return knows(ctx, w, function(m) return m == mv end) == true end)
OP[56] = cond(2, function(ctx, w, mv) return knows(ctx, w, function(m) return m == mv end) == false end)
local function knowsEffect(ctx, w, e)
  if w ~= AI_BATTLER_ATTACKER and w ~= AI_BATTLER_DEFENDER then return nil end
  return knows(ctx, w, function(m) return m ~= 0 and mdEffect(ctx.battle, m) == e end)
end
OP[57] = cond(2, function(ctx, w, e) return knowsEffect(ctx, w, e) == true end)
OP[58] = cond(2, function(ctx, w, e) return knowsEffect(ctx, w, e) == false end)
OP[59] = cond(2, function(ctx, w, check)
  local b = B(ctx, who(ctx, w))
  if not b then return false end
  if check == 0 then return positive(b.disabledTurns) or b.disabledSlot ~= nil end
  if check == 1 then return positive(b.encoreTurns) end
  return false
end)
OP[60] = cond(1, function(ctx, check)
  local b = B(ctx, ctx.atk)
  if not b then return false end
  if check == 0 then
    local slot = b.disabledSlot
    local m = slot and b.curMoves and b.curMoves[slot]
    return m ~= nil and tonumber(m.id) == ctx.move
  end
  if check == 1 then return positive(b.encoreTurns) and tonumber(b.encoreMove) == ctx.move end
  return false
end)
OP[61] = function(ctx) iter(ctx, 1) ctx.flags = bor(ctx.flags, FLAG_DONE + FLAG_ESCAPE + FLAG_BREAK) end
OP[62] = function(ctx) ctx.stall = true end -- AICmd_Dummy3E: does not advance
OP[63] = function(ctx) ctx.stall = true end
OP[64] = function(ctx)
  iter(ctx, 1)
  local b = B(ctx, who(ctx, read(ctx)))
  ctx.temp = itemIdOf(b and b.mon)
end
OP[65] = function(ctx)
  iter(ctx, 1)
  local id = who(ctx, read(ctx))
  local b = B(ctx, id)
  if ctx.atk ~= id then
    ctx.temp = itemHoldEffect(ctx.battle, b and b.g4aiKnownItem or 0)
  else
    ctx.temp = itemHoldEffect(ctx.battle, itemIdOf(b and b.mon))
  end
end
OP[66] = function(ctx)
  iter(ctx, 1)
  local b = B(ctx, who(ctx, read(ctx)))
  local g = 2
  if b and b.mon then
    local ok, P = pcall(require, "src.pokemon.Pokemon")
    local okG, sex = false, nil
    if ok and P.genderOf then okG, sex = pcall(P.genderOf, ctx.battle.data, b.mon) end
    if okG then
      if sex == "M" or sex == "male" or sex == 0 then g = 0
      elseif sex == "F" or sex == "female" or sex == 1 then g = 1 end
    end
  end
  ctx.temp = g
end
local function sentTurn(ctx, b)
  -- moveEffectsData.fakeOutTurnNumber: the turn the battler came in on
  return b and b.g4aiInTurn or ctx.turns
end
OP[67] = function(ctx)
  iter(ctx, 1)
  local b = B(ctx, who(ctx, read(ctx)))
  ctx.temp = (sentTurn(ctx, b) < ctx.turns) and 0 or 1
end
OP[68] = function(ctx) iter(ctx, 1) local b = B(ctx, who(ctx, read(ctx))) ctx.temp = b and tonumber(b.stockpile) or 0 end
OP[69] = function(ctx) iter(ctx, 1) ctx.temp = ctx.btype end
OP[70] = function(ctx)
  iter(ctx, 1)
  local b = B(ctx, who(ctx, read(ctx)))
  ctx.temp = b and tonumber(b.lastConsumedItem or b.bwConsumedItem) or 0
end
OP[71] = function(ctx) iter(ctx, 1) ctx.temp = mdType(ctx.battle, ctx.temp) end
OP[72] = function(ctx) iter(ctx, 1) ctx.temp = mdPower(ctx.battle, ctx.temp) end
OP[73] = function(ctx) iter(ctx, 1) ctx.temp = mdEffect(ctx.battle, ctx.temp) end
OP[74] = function(ctx)
  iter(ctx, 1)
  local b = B(ctx, who(ctx, read(ctx)))
  local last = prevMove(b)
  if last ~= MOVE.PROTECT and last ~= MOVE.DETECT and last ~= MOVE.ENDURE then ctx.temp = 0
  else ctx.temp = b and tonumber(b.protectRun or b.bwProtectChain) or 0 end
end
OP[75] = function(ctx)
  iter(ctx, 1)
  local jump = read(ctx)
  ctx.stack[#ctx.stack + 1] = ctx.cursor
  iter(ctx, jump)
end
OP[76] = function(ctx) iter(ctx, 1) local jump = read(ctx) iter(ctx, jump) end
OP[77] = function(ctx)
  iter(ctx, 1)
  local back = table.remove(ctx.stack)
  if back then ctx.cursor = back return end
  ctx.flags = bor(ctx.flags, FLAG_DONE)
end
OP[78] = cond(1, function(ctx, op)
  local la = B(ctx, ctx.atk) and B(ctx, ctx.atk).mon.level or 0
  local ld = B(ctx, ctx.def) and B(ctx, ctx.def).mon.level or 0
  if op == 0 then return la > ld elseif op == 1 then return la < ld elseif op == 2 then return la == ld end
  return false
end)
OP[79] = cond(0, function(ctx) local d = B(ctx, ctx.def) return d ~= nil and positive(d.tauntTurns) end)
OP[80] = cond(0, function(ctx) local d = B(ctx, ctx.def) return not (d and positive(d.tauntTurns)) end)
OP[81] = cond(0, function(ctx) return ctx.atk % 2 == ctx.def % 2 end)
OP[82] = function(ctx)
  iter(ctx, 1)
  local w, t = read(ctx), read(ctx)
  ctx.temp = hasType(B(ctx, who(ctx, w)), t) and 1 or 0
end
OP[83] = function(ctx)
  iter(ctx, 1)
  local inB, expected = read(ctx), read(ctx)
  local id = who(ctx, inB)
  local b = B(ctx, id)
  local tmp
  if band(effectMask(ctx.battle, b), 2 ^ 21) ~= 0 then tmp = 0
  elseif inB == AI_BATTLER_DEFENDER or inB == AI_BATTLER_DEFENDER_PARTNER then
    local known = b and b.g4aiKnownAbility
    if known and known ~= 0 then tmp = known ctx.temp = known
    elseif TRAPPERS[abilityName(b) or ""] then tmp = abilityOf(b)
    else
      local a1, a2 = speciesAbilities(b)
      if a1 ~= 0 and a2 ~= 0 then
        if a1 ~= expected and a2 ~= expected then tmp = a1 else tmp = 0 end
      elseif a1 ~= 0 then tmp = a1 else tmp = a2 end
    end
  else
    tmp = abilityOf(b)
  end
  if tmp == 0 then ctx.temp = AI_UNKNOWN
  elseif tmp == expected then ctx.temp = AI_HAVE
  else ctx.temp = AI_NOT_HAVE end
end
OP[84] = cond(1, function(ctx, w) local b = B(ctx, who(ctx, w)) return b ~= nil and on(b.flashFire) end)
OP[85] = cond(2, function(ctx, w, expected)
  local id = who(ctx, w)
  local b = B(ctx, id)
  local held
  if id % 2 == ctx.atk % 2 then held = itemIdOf(b and b.mon)
  else held = b and tonumber(b.g4aiKnownItem) or 0 end
  return held == expected
end)
OP[86] = cond(1, function(ctx, m) return band(fieldMask(ctx.battle), m) ~= 0 end)
OP[87] = function(ctx)
  iter(ctx, 1)
  local id = who(ctx, read(ctx))
  local cond_ = read(ctx)
  local isPlayer = sideOfId(id)
  if cond_ == 4 then
    local engine = ctx.battle.sides and ctx.battle.sides[isPlayer and 1 or 2]
    ctx.temp = engine and tonumber(engine.spikes) or 0
  elseif cond_ == 1024 then
    ctx.temp = tonumber(g4side(ctx.battle, isPlayer).toxicSpikes) or 0
  end
end
OP[88] = cond(1, function(ctx, w)
  local id = who(ctx, w)
  local s = partySlotOf(ctx.battle, id)
  for i, mon in ipairs(partyFor(ctx.battle, id)) do
    if i - 1 ~= s and (tonumber(mon.hp) or 0) ~= ((mon.stats and mon.stats.hp) or 0) then return true end
  end
  return false
end)
OP[89] = cond(1, function(ctx, w)
  local id = who(ctx, w)
  local s = partySlotOf(ctx.battle, id)
  local Moves = nil
  for i, mon in ipairs(partyFor(ctx.battle, id)) do
    if i - 1 ~= s then
      for _, m in ipairs(mon.moves or {}) do
        local maxPP = tonumber(m.maxPP or m.maxpp)
        if not maxPP then
          local d = moveDef(ctx.battle, m.id)
          maxPP = d and tonumber(d.pp) or nil
          if maxPP and m.ppUps then maxPP = maxPP + math.floor(maxPP * m.ppUps / 5) end
        end
        if maxPP and (tonumber(m.pp) or 0) ~= maxPP then return true end
      end
    end
  end
  return false
end)
OP[90] = function(ctx)
  iter(ctx, 1)
  local b = B(ctx, who(ctx, read(ctx)))
  local d = b and b.mon and itemDef(ctx.battle, itemIdOf(b.mon))
  ctx.temp = d and tonumber(d.flingPower) or 0
end
OP[91] = function(ctx) iter(ctx, 1) ctx.temp = ppAt(B(ctx, ctx.atk), ctx.slot) end
OP[92] = cond(1, function(ctx, w)
  local b = B(ctx, who(ctx, w))
  local n = 0
  for i = 0, 3 do if moveAt(b, i) ~= 0 then n = n + 1 end end
  local used = 0
  for _ in pairs(b and (b.g4MovesUsed or b.bwUsedMoves) or {}) do used = used + 1 end
  return used >= n - 1 and n > 1
end)
OP[93] = function(ctx) iter(ctx, 1) ctx.temp = mdClass(ctx.battle, ctx.move) end
OP[94] = function(ctx) iter(ctx, 1) ctx.temp = mdClass(ctx.battle, prevMove(B(ctx, ctx.def))) end
OP[95] = function(ctx)
  iter(ctx, 1)
  local id = who(ctx, read(ctx))
  local n = ctx.battle:isDouble() and 4 or 2
  local order = {}
  for i = 0, n - 1 do order[i] = i end
  for i = 0, n - 2 do
    for j = i + 1, n - 1 do
      local c1, c2 = order[i], order[j]
      if compareSpeed(ctx.battle, B(ctx, c1), B(ctx, c2)) ~= 0 then order[i], order[j] = c2, c1 end
    end
  end
  for i = 0, n - 1 do if order[i] == id then ctx.temp = i break end end
end
OP[96] = function(ctx)
  iter(ctx, 1)
  local b = B(ctx, who(ctx, read(ctx)))
  ctx.temp = ctx.turns - sentTurn(ctx, b)
end
OP[97] = function(ctx)
  iter(ctx, 1)
  local vary, jump = read(ctx) ~= 0, read(ctx)
  local id = ctx.atk
  local a = B(ctx, id)
  local active = G.calcAll(ctx, a, movesOf(a), vary)
  local s = partySlotOf(ctx.battle, id)
  for i, mon in ipairs(partyFor(ctx.battle, id)) do
    if i - 1 ~= s and usable(mon) then
      -- the bench Pokemon's moves, item, IVs and ability on the active
      -- battler's stats (TrainerAI_CalcAllDamage is handed the attacker id)
      local proxy = setmetatable({ mon = setmetatable({ item = mon.item, heldItem = mon.heldItem,
        ivs = mon.ivs, friendship = mon.friendship }, { __index = a.mon }),
        abilityOverride = abilityName({ mon = mon, def = monDef(ctx.battle, mon) }) or false,
        g4Embargo = 0 }, { __index = a })
      local dmg = G.calcAll(ctx, proxy, monMoves(mon), vary)
      if dmg > active then iter(ctx, jump) return end
    end
  end
end
OP[98] = cond(0, function(ctx) return G.hasSuperEffective(ctx.battle, ctx, ctx.atk, true) end)
OP[99] = function(ctx)
  iter(ctx, 1)
  local w, vary, jump = read(ctx), read(ctx) ~= 0, read(ctx)
  local a = B(ctx, ctx.atk)
  local aiDamage = G.calcAll(ctx, a, movesOf(a), vary)
  local id = who(ctx, w)
  local b = B(ctx, id)
  local roll = vary and ctx.rolls[ctx.slot] or 100
  -- BUG kept: the other battler's damage uses the AI's IVs
  local dmg = 0
  if b and prevMove(b) ~= 0 then
    dmg = G.calcDamage(ctx, prevMove(b), b, roll, ivsOf(a and a.mon))
  end
  if dmg > aiDamage then iter(ctx, jump) end
end
OP[100] = function(ctx)
  iter(ctx, 1)
  local b = B(ctx, who(ctx, read(ctx)))
  ctx.temp = 0
  for s = 1, 7 do
    local v = stageOf(b, s)
    if v > 6 then ctx.temp = ctx.temp + v - 6 end
  end
end
OP[101] = function(ctx)
  iter(ctx, 1)
  local w, s = read(ctx), read(ctx)
  ctx.temp = stageOf(B(ctx, who(ctx, w)), s) - stageOf(B(ctx, ctx.atk), s)
end
local function statPair(ctx, id, s)
  local a, b = B(ctx, ctx.atk), B(ctx, id)
  if s == 0 then return hpOf(a), hpOf(b) end
  local key = STAT_KEY[s]
  local function st(x) return x and x.curStats and tonumber(x.curStats[key]) or 0 end
  return st(a), st(b)
end
OP[102] = cond(2, function(ctx, w, s) local x, y = statPair(ctx, who(ctx, w), s) return x < y end)
OP[103] = cond(2, function(ctx, w, s) local x, y = statPair(ctx, who(ctx, w), s) return x > y end)
OP[104] = cond(2, function(ctx, w, s) local x, y = statPair(ctx, who(ctx, w), s) return x == y end)
OP[105] = function(ctx)
  iter(ctx, 1)
  local vary = read(ctx) ~= 0
  if not scoresDamage(ctx.battle, ctx.move) then ctx.temp = AI_NO_COMPARISON_MADE return end
  local id = ctx.atk
  local moveDamage
  for j = 0, 1 do
    local b = B(ctx, id)
    local _, vals = G.calcAll(ctx, b, movesOf(b), vary)
    id = bxor(ctx.atk, 2)
    if j == 0 then moveDamage = vals[ctx.slot] end
    local higher = false
    for i = 0, 3 do if vals[i] > moveDamage then higher = true break end end
    if higher then ctx.temp = AI_NOT_HIGHEST_DAMAGE return end
    ctx.temp = AI_MOVE_IS_HIGHEST_DAMAGE
  end
end
local function switching(ctx, id)
  -- battlersSwitchingMask: INFERRED as "this slot is empty / being replaced"
  local b = B(ctx, id)
  return not (b and hpOf(b) > 0)
end
OP[106] = cond(1, function(ctx, w) return switching(ctx, who(ctx, w)) end)
OP[107] = cond(1, function(ctx, w) return not switching(ctx, who(ctx, w)) end)
OP[108] = function(ctx) iter(ctx, 1) ctx.temp = abilityOf(B(ctx, who(ctx, read(ctx)))) end

G.STEP_CAP = 20000

-- TrainerAI_EvalMoves for one flag's program, all four slots
local function evalMoves(ctx, flagBit)
  local entry = ctx.words[flagBit + 1]
  if not entry then return end
  local a = B(ctx, ctx.atk)
  ctx.slot = 0
  while ctx.slot < 4 do
    ctx.cursor = entry
    ctx.stack = {}
    ctx.move = (ppAt(a, ctx.slot) == 0) and 0 or (moveAt(a, ctx.slot))
    ctx.flags = band(ctx.flags, bnot(FLAG_DONE))
    if ctx.move == 0 then
      ctx.score[ctx.slot] = 0
    else
      local steps = 0
      while band(ctx.flags, FLAG_DONE) == 0 do
        local op = ctx.words[ctx.cursor + 1]
        local fn = op and OP[op]
        steps = steps + 1
        if not fn or steps > G.STEP_CAP or ctx.stall then
          ctx.broken = (ctx.broken or 0) + 1
          ctx.stall = nil
          break
        end
        fn(ctx)
      end
    end
    ctx.slot = ctx.slot + 1
    if band(ctx.flags, FLAG_BREAK) ~= 0 then break end
  end
  ctx.flags = band(ctx.flags, bnot(FLAG_DONE))
end

-- ---------------------------------------------------------------------------
-- the battle's AI memory
-- ---------------------------------------------------------------------------

function G.program(battle)
  local p = battle and battle.data and battle.data.gen4_trainer_ai
  if type(p) == "table" and type(p.words) == "table" and p.words[1] == 32 then return p end
  return nil
end

-- the Gen 4 rules apply to Platinum / HGSS battles (Gen4MoveEffects' state)
function G.applies(battle)
  return battle ~= nil and battle.g4fx ~= nil and not battle.bw
end

local function memory(battle)
  local m = battle.g4ai
  if not m then
    m = { switched = {}, items = {}, itemCounts = {} }
    battle.g4ai = m
    -- BattleControllerPlayer_InitAI: the enemy trainers' items, per enemy
    -- battler (battler >> 1), skipped for NO_AI_ITEMS battles
    local bt = G.battleType(battle)
    if band(bt, BT_TRAINER) ~= 0 and band(bt, BT_FRONTIER + BT_AI) == 0 then
      local function load(slot, trainer)
        local list, n = {}, 0
        for i = 1, 4 do
          local it = trainer and trainer.items and tonumber(trainer.items[i]) or 0
          if it ~= 0 then n = n + 1 list[n] = it end
        end
        m.items[slot], m.itemCounts[slot] = list, n
      end
      load(0, battle.trainer)
      -- battler 3's trainer: the second trainer, or the same record again
      -- when one trainer fights a double (trainerIDs[3] = the same id)
      if battle:isDouble() then load(1, battle.trainerB or battle.trainer) end
    end
  end
  return m
end
G.memory = memory

-- The turn number and each battler's arrival turn, captured before anyone
-- chooses (the engine bumps its counters between the first and the second
-- enemy's choice).
function G.beginTurn(battle)
  if not G.applies(battle) then return end
  local m = memory(battle)
  m.turn = battle.turnCount or 0
  m.switched = {}
  for pos = 0, 3 do
    local b = battle:battlerAt(pos)
    if b and b.g4aiInTurn == nil then b.g4aiInTurn = m.turn end
  end
end

local function rngFor(battle)
  local r = battle.rng or love.math.random
  return function() return r(0, 65535) end
end

local function newCtx(battle, atkId, defId, flags)
  local p = G.program(battle)
  local m = memory(battle)
  return {
    battle = battle, words = p and p.words or {}, atk = atkId, def = defId,
    score = { [0] = 0, 0, 0, 0 }, rolls = {}, flags = 0, temp = 0, stack = {},
    cursor = 0, slot = 0, move = 0, mask = flags or 0,
    turns = m.turn or battle.turnCount or 0, btype = G.battleType(battle),
    rand = rngFor(battle),
  }
end

-- TrainerAI_Init: scores, invalid moves to 0, damage rolls
local function init(ctx, initScore, usableSlots)
  for i = 0, 3 do
    ctx.score[i] = (math.floor(initScore / 2 ^ i) % 2 == 1) and 100 or 0
  end
  for i = 0, 3 do
    if not usableSlots[i] then ctx.score[i] = 0 end
    ctx.rolls[i] = 100 - (ctx.rand() % 16)
  end
  ctx.stack = {}
end

-- TrainerAI_RecordLastMove
local function recordLastMove(ctx)
  local d = B(ctx, ctx.def)
  local last = prevMove(d)
  local km = knownMoves(ctx, ctx.def)
  for i = 1, 4 do
    if km[i] == last then return end
    if km[i] == nil or km[i] == 0 then km[i] = last return end
  end
end

local function aiMaskFor(battle, battler)
  if battle.battleType == "roaming" then return AI_FLAG_ROAMING_POKEMON end
  local trainer
  if battler.isPlayer then
    local id = battle.ally and tonumber(battle.ally.trainer)
    trainer = id and battle.data.trainers and battle.data.trainers[id]
  elseif battler.position == 3 and battle.trainerB then
    trainer = battle.trainerB
  else
    trainer = battle.trainer
  end
  local mask = trainer and tonumber(trainer.aiMask or trainer.aiFlags) or 0
  if battle:isDouble() then mask = bor(mask, AI_FLAG_TAG_STRATEGY) end
  return mask
end
G.aiMaskFor = aiMaskFor

local function runFlags(ctx)
  local mask = ctx.mask
  for b = 0, 31 do
    if mask == 0 then break end
    if band(mask, 1) ~= 0 then evalMoves(ctx, b) end
    mask = bit.rshift(mask, 1)
  end
end

-- the slots the cartridge would score: a move there with PP, not refused
local function usableSlots(battle, battler, usableMoves)
  local set = {}
  for i = 0, 3 do
    local m = battler.curMoves and battler.curMoves[i + 1]
    if m then
      for _, u in ipairs(usableMoves or {}) do
        if u == m then set[i] = true end
      end
    end
  end
  return set
end

local function bestSlot(ctx, battler)
  local maxScore, slots = ctx.score[0], { 0 }
  for i = 1, 3 do
    if moveAt(battler, i) ~= 0 then
      if maxScore == ctx.score[i] then slots[#slots + 1] = i end
      if maxScore < ctx.score[i] then maxScore, slots = ctx.score[i], { i } end
    end
  end
  return slots[(ctx.rand() % #slots) + 1], maxScore
end

-- TrainerAI_Main.  Returns move entry, target battler (doubles), and the ctx
-- (for the tests).  nil when the AI does not apply.
function G.choose(battle, battler, usableMoves)
  if not (G.applies(battle) and battler and battler.position and G.program(battle)) then return nil end
  local atk = battler.position
  local mask = aiMaskFor(battle, battler)
  local set = usableSlots(battle, battler, usableMoves)
  if not battle:isDouble() then
    local foes = battle:foesOf(battler)
    local d = foes[1]
    if not d then return nil end
    local ctx = newCtx(battle, atk, d.position, mask)
    init(ctx, 15, set)
    recordLastMove(ctx)
    runFlags(ctx)
    local slot = bestSlot(ctx, battler)
    return battler.curMoves[slot + 1], d, ctx
  end
  -- TrainerAI_MainDoubles
  local action, maxFor = {}, {}
  local last
  for id = 0, 3 do
    local b = at(battle, id)
    if id == atk or hpOf(b) == 0 then
      action[id], maxFor[id] = -1, -1
    else
      local ctx = newCtx(battle, atk, id, mask)
      init(ctx, 15, set)
      if id % 2 ~= atk % 2 then recordLastMove(ctx) end
      runFlags(ctx)
      local slot, best = bestSlot(ctx, battler)
      action[id], maxFor[id] = slot, best
      if id == bxor(atk, 2) and best < 100 then maxFor[id] = -1 end
      last = ctx
    end
  end
  local maxScore, targets = maxFor[0], { 0 }
  for id = 1, 3 do
    if maxScore == maxFor[id] then targets[#targets + 1] = id end
    if maxScore < maxFor[id] then maxScore, targets = maxFor[id], { id } end
  end
  local r = rngFor(battle)
  local target = targets[(r() % #targets) + 1]
  local slot = action[target]
  if not slot or slot < 0 then return nil end
  local move = moveAt(battler, slot)
  -- RANGE_USER_OR_ALLY aimed at the player's side becomes the user; a
  -- non-Ghost Curse targets the user
  local range = mdRange(battle, move)
  local tb = at(battle, target)
  if range == 0x200 and target % 2 == 0 then tb = battler end
  if move == MOVE.CURSE and not hasType(battler, TYPE.GHOST) then tb = battler end
  return battler.curMoves[slot + 1], tb, last
end

-- ---------------------------------------------------------------------------
-- switching (TrainerAI_ShouldSwitch) and the replacement (PostKOSwitchIn)
-- ---------------------------------------------------------------------------

local function pairSlots(battle, id)
  local bt = G.battleType(battle)
  local s1 = partySlotOf(battle, id)
  local s2 = s1
  if band(bt, BT_TAG + BT_2VS2) == 0 then s2 = partySlotOf(battle, bxor(id, 2)) end
  return s1, s2
end

local function eligible(battle, id, i, mon, s1, s2)
  local m = memory(battle)
  local sw1 = m.switched[id]
  local sw2 = m.switched[(band(G.battleType(battle), BT_TAG + BT_2VS2) == 0) and bxor(id, 2) or id]
  return usable(mon) and i ~= s1 and i ~= s2 and i ~= sw1 and i ~= sw2
end

local function defAbilityItem(battle, d)
  return abilityOf(d), heldEffect(battle, d)
end

function G.hasSuperEffective(battle, ctx, id, flag)
  local me = at(battle, id)
  local r = ctx and ctx.rand or rngFor(battle)
  -- the slot straight across, then (doubles) its partner
  local d = bxor(id, 1)
  local function check(defId)
    local def = at(battle, defId)
    if not (def and hpOf(def) > 0) then return false end
    for i = 0, 3 do
      local move = moveAt(me, i)
      if move ~= 0 then
        local _, flags = G.applyTypeChart(battle, move, aiMoveType(battle, me, move), me, def, 0)
        if band(flags, MS_SUPER) ~= 0 then
          if flag then return true end
          if r() % 10 ~= 0 then return true end
        end
      end
    end
    return false
  end
  if check(d) then return true end
  if not battle:isDouble() then return false end
  return check(bxor(d, 2))
end

local function benchHasSE(battle, id, mon, defId, r, odds)
  local def = at(battle, defId)
  if not (def and hpOf(def) > 0) then return false end
  local dab, dhe = defAbilityItem(battle, def)
  local d1, d2 = typesOf(def)
  for j = 1, 4 do
    local m = mon.moves and mon.moves[j]
    local move = m and tonumber(m.id) or 0
    if move ~= 0 and mdPower(battle, move) ~= 0 then
      local flags = G.calcEffectiveness(battle, move, benchMoveType(battle, mon, move),
                                        monAbility(battle, mon), dab, dhe, d1, d2)
      if odds(flags) then return true end
    end
  end
  return false
end

-- AI_CannotDamageWonderGuard (singles only)
local function wonderGuard(battle, id, r)
  if battle:isDouble() then return false end
  local me, opp = at(battle, id), at(battle, bxor(id, 1))
  if not (opp and abilityName(opp) == "WONDER_GUARD") then return false end
  for i = 0, 3 do
    local move = moveAt(me, i)
    if move ~= 0 then
      local _, flags = G.applyTypeChart(battle, move, aiMoveType(battle, me, move), me, opp, 0)
      if band(flags, MS_SUPER) ~= 0 then return false end
    end
  end
  local s = partySlotOf(battle, id)
  for i, mon in ipairs(partyFor(battle, id)) do
    if usable(mon) and i - 1 ~= s then
      local dab, dhe = defAbilityItem(battle, opp)
      local d1, d2 = typesOf(opp)
      for j = 1, 4 do
        local m = mon.moves and mon.moves[j]
        local move = m and tonumber(m.id) or 0
        if move ~= 0 then
          local flags = G.calcEffectiveness(battle, move, benchMoveType(battle, mon, move),
                                            monAbility(battle, mon), dab, dhe, d1, d2)
          if band(flags, MS_SUPER) ~= 0 and r() % 3 < 2 then return i - 1 end
        end
      end
    end
  end
  return false
end

-- AI_OnlyIneffectiveMoves
local function onlyIneffective(battle, id, r)
  local me = at(battle, id)
  local d1, d2 = 0, battle:isDouble() and 2 or 0
  local n = 0
  for i = 0, 3 do
    local move = moveAt(me, i)
    if move ~= 0 and mdPower(battle, move) ~= 0 then
      n = n + 1
      for _, defId in ipairs({ d1, d2 }) do
        local def = at(battle, defId)
        local flags = 0
        if hpOf(def) > 0 then
          _, flags = G.applyTypeChart(battle, move, aiMoveType(battle, me, move), me, def, 0)
        end
        if band(flags, MS_INEFFECTIVE) == 0 then return false end
      end
    end
  end
  if n < 2 then return false end
  local s1, s2 = pairSlots(battle, id)
  for _, pass in ipairs({ "se", "neutral" }) do
    for i, mon in ipairs(partyFor(battle, id)) do
      if eligible(battle, id, i - 1, mon, s1, s2) then
        for _, defId in ipairs({ d1, d2 }) do
          local hit = benchHasSE(battle, id, mon, defId, r, function(flags)
            if pass == "se" then return band(flags, MS_SUPER) ~= 0 and r() % 3 < 2 end
            return flags == 0 and r() % 2 == 0
          end)
          if hit then return i - 1 end
        end
      end
    end
  end
  return false
end

-- AI_HasAbsorbAbilityInParty
local function absorbOnBench(battle, id, r)
  if G.hasSuperEffective(battle, nil, id, true) and r() % 3 ~= 0 then return false end
  local me = at(battle, id)
  local hit = G.hitBy(me)
  if not hit or hit == 0 then return false end
  if mdPower(battle, hit) == 0 then return false end
  local t = mdType(battle, hit)
  local want
  if t == TYPE.FIRE then want = AB.FLASH_FIRE
  elseif t == TYPE.WATER then want = AB.WATER_ABSORB
  elseif t == TYPE.ELECTRIC then want = AB.VOLT_ABSORB
  else return false end
  if abilityOf(me) == want then return false end
  local s1, s2 = pairSlots(battle, id)
  for i, mon in ipairs(partyFor(battle, id)) do
    if eligible(battle, id, i - 1, mon, s1, s2) and monAbility(battle, mon) == want and r() % 2 == 1 then
      return i - 1
    end
  end
  return false
end

-- AI_HasPartyMemberWithSuperEffectiveMove
local function benchCounter(battle, id, checkFlags, odds, r)
  local me = at(battle, id)
  local hit, hb = G.hitBy(me)
  if not hit or hit == 0 or not hb then return false end
  if mdPower(battle, hit) == 0 then return false end
  local s1, s2 = pairSlots(battle, id)
  for i, mon in ipairs(partyFor(battle, id)) do
    if eligible(battle, id, i - 1, mon, s1, s2) then
      local t1, t2 = monTypes(battle, mon)
      local flags = G.calcEffectiveness(battle, hit, aiMoveType(battle, hb, hit), abilityOf(hb),
                                        monAbility(battle, mon), itemHoldEffect(battle, itemIdOf(mon)), t1, t2)
      if band(flags, checkFlags) ~= 0 then
        local h1, h2 = typesOf(hb)
        local hab, hhe = defAbilityItem(battle, hb)
        for j = 1, 4 do
          local m = mon.moves and mon.moves[j]
          local move = m and tonumber(m.id) or 0
          if move ~= 0 then
            local f = G.calcEffectiveness(battle, move, benchMoveType(battle, mon, move),
                                          monAbility(battle, mon), hab, hhe, h1, h2)
            if band(f, MS_SUPER) ~= 0 and r() % odds == 0 then return i - 1 end
          end
        end
      end
    end
  end
  return false
end

-- AI_IsAsleepWithNaturalCure; 6 means "use the post-KO pick"
local function naturalCure(battle, id, r)
  local me = at(battle, id)
  if band(statusMask(me), MC.SLEEP) == 0 or abilityName(me) ~= "NATURAL_CURE"
     or hpOf(me) < math.floor(maxHpOf(me) / 2) then return false end
  local hit = G.hitBy(me) or 0
  if hit == 0 and r() % 2 == 1 then return 6 end
  if mdPower(battle, hit) == 0 and r() % 2 == 1 then return 6 end
  local s = benchCounter(battle, id, MS_INEFFECTIVE, 1, r)
  if s then return s end
  s = benchCounter(battle, id, MS_NOT_VERY, 1, r)
  if s then return s end
  if r() % 2 == 1 then return 6 end
  return false
end

local function trappedByAbility(battle, me)
  -- BattleSystem_CountAbility over the other side / everyone but me
  for pos = 0, 3 do
    local b = at(battle, pos)
    if b and b ~= me and hpOf(b) > 0 then
      local ab = abilityName(b)
      if b.isPlayer ~= me.isPlayer and (ab == "SHADOW_TAG" or ab == "ARENA_TRAP") then return true end
      if ab == "MAGNET_PULL" and hasType(me, TYPE.STEEL) then return true end
    end
  end
  return false
end

-- TrainerAI_ShouldSwitch -> the party slot (0-based), 6 for the post-KO
-- pick, or nil
function G.shouldSwitch(battle, battler)
  local id = battler.position
  local r = rngFor(battle)
  if band(volatileMask(battler), 8192 + 2 ^ 26) ~= 0 or battler.ingrained or battler.trapped
     or trappedByAbility(battle, battler) then
    return nil
  end
  local s1, s2 = pairSlots(battle, id)
  local alive = 0
  for i, mon in ipairs(partyFor(battle, id)) do
    if eligible(battle, id, i - 1, mon, s1, s2) then alive = alive + 1 end
  end
  if alive == 0 then return nil end
  -- AI_PerishSongKO: never true here either (the counter is read before the
  -- end-of-turn tick), kept for the order
  if battler.perishTurns == 0 then return 6 end
  local s = wonderGuard(battle, id, r)
  if s then return s end
  s = onlyIneffective(battle, id, r)
  if s then return s end
  s = absorbOnBench(battle, id, r)
  if s then return s end
  s = naturalCure(battle, id, r)
  if s then return s end
  if G.hasSuperEffective(battle, nil, id, false) then return nil end
  local boosts = 0
  for st = 1, 7 do local v = stageOf(battler, st) if v > 6 then boosts = boosts + v - 6 end end
  if boosts >= 4 then return nil end
  s = benchCounter(battle, id, MS_INEFFECTIVE, 2, r)
  if s then return s end
  s = benchCounter(battle, id, MS_NOT_VERY, 3, r)
  if s then return s end
  return nil
end

-- BattleAI_PostKOSwitchIn: the party slot (0-based) to send in, or 6
function G.postKO(battle, id)
  local party = partyFor(battle, id)
  local s1, s2 = pairSlots(battle, id)
  local m = memory(battle)
  local function eligibleKO(i, mon)
    return usable(mon) and i ~= s1 and i ~= s2 and i ~= m.switched[id]
  end
  -- BattleSystem_RandomOpponent
  local foes = {}
  for _, pos in ipairs({ bxor(id, 1), bxor(id, 3) }) do
    local b = at(battle, pos)
    if b and hpOf(b) > 0 then foes[#foes + 1] = b end
  end
  local r = rngFor(battle)
  local defender = foes[1]
  if #foes > 1 then defender = foes[(r() % 2) + 1] end
  if not defender then return 6 end
  local d1, d2 = typesOf(defender)
  local dab, dhe = defAbilityItem(battle, defender)
  -- stage 1: best type matchup that also has a super-effective move
  local disregarded = {}
  while true do
    local maxScore, picked = 0, nil
    for i, mon in ipairs(party) do
      if not disregarded[i] and eligibleKO(i - 1, mon) then
        local t1, t2 = monTypes(battle, mon)
        local score = G.matchup(battle, t1, d1, d2) + G.matchup(battle, t2, d1, d2)
        score = score % 256 -- u8 (BUG kept: Post-KO Switch-In AI Scoring Overflow)
        if maxScore < score then maxScore, picked = score, i end
      else
        disregarded[i] = true
      end
    end
    if not picked then break end
    local mon = party[picked]
    local found = false
    for j = 1, 4 do
      local mv = mon.moves and mon.moves[j]
      local move = mv and tonumber(mv.id) or 0
      if move ~= 0 then
        local flags = G.calcEffectiveness(battle, move, benchMoveType(battle, mon, move),
                                          monAbility(battle, mon), dab, dhe, d1, d2)
        if band(flags, MS_SUPER) ~= 0 then found = true break end
      end
    end
    if found then return picked - 1 end
    disregarded[picked] = true
  end
  -- stage 2: the most damage, as the battler that fainted would deal it
  local maxScore, picked = 0, nil
  -- the battler that fainted is still in its slot in a single battle; a
  -- double lifts it off first, and then each candidate stands in for it
  -- (INFERRED)
  local me = at(battle, id)
  local ctx = newCtx(battle, id, defender.position, 0)
  for i = 0, 3 do ctx.rolls[i] = 100 end
  for i, mon in ipairs(party) do
    if eligibleKO(i - 1, mon) then
      for j = 1, 4 do
        local mv = mon.moves and mon.moves[j]
        local move = mv and tonumber(mv.id) or 0
        if move ~= 0 and mdPower(battle, move) ~= 1 then
          local proxy
          if me then
            proxy = setmetatable({ mon = setmetatable({ item = mon.item, ivs = mon.ivs }, { __index = me.mon }) },
                                 { __index = me })
          else
            local def = monDef(battle, mon)
            proxy = { mon = mon, def = def, curStats = mon.stats, curTypes = def.types,
                      stages = {}, isPlayer = id % 2 == 0, curMoves = mon.moves, position = id,
                      statuses = battle.data.statuses, items = battle.data.items }
          end
          local score = G.calcDamage(ctx, move, proxy, 100)
          score = score % 256 -- u8
          if maxScore < score then maxScore, picked = score, i end
        end
      end
    end
  end
  return picked and (picked - 1) or 6
end

-- ---------------------------------------------------------------------------
-- items (TrainerAI_ShouldUseItem)
-- ---------------------------------------------------------------------------

local function param(def)
  local s = def and def.partyUseParam
  if type(s) ~= "string" or #s < 14 then return nil end
  local b = { s:byte(1, 20) }
  local function bitAt(byte, n) return math.floor((b[byte + 1] or 0) / 2 ^ n) % 2 == 1 end
  local function nib(byte, hi) local v = b[byte + 1] or 0 return hi and math.floor(v / 16) or v % 16 end
  return {
    healSleep = bitAt(0, 0), healPoison = bitAt(0, 1), healBurn = bitAt(0, 2),
    healFreeze = bitAt(0, 3), healParalysis = bitAt(0, 4), healConfusion = bitAt(0, 5),
    guardSpec = bitAt(0, 7),
    atk = nib(1, true), def = nib(2, false), spatk = nib(2, true), spdef = nib(3, false),
    speed = nib(3, true), acc = nib(4, false),
    hpRestore = bitAt(5, 2), hpRestored = b[14] or 0,
  }
end
G.itemParam = param

-- returns { item = id, category, condition, slot } or nil
function G.shouldUseItem(battle, battler)
  local id = battler.position
  if battler.isPlayer then return nil end -- the AI partner never uses items
  if positive(battler.g4Embargo) then return nil end
  local m = memory(battle)
  local side = math.floor(id / 2)
  local list = m.items[side]
  if not list or #list == 0 then return nil end
  local alive = 0
  for _, mon in ipairs(partyFor(battle, id)) do if usable(mon) then alive = alive + 1 end end
  local hp, maxHp = hpOf(battler), maxHpOf(battler)
  local status = statusMask(battler)
  local result, use = false, nil
  local count = m.itemCounts[side] or 0
  for i = 0, 3 do
    if i == 0 or alive <= count - i + 1 then
      local item = list[i + 1] or 0
      if item ~= 0 then
        local def = itemDef(battle, item)
        local p = param(def) or {}
        local cat, cond_
        if item == ITEM_FULL_RESTORE then
          if hp < math.floor(maxHp / 4) and hp ~= 0 then cat = "full_restore" result = true end
        elseif p.hpRestore then
          if p.hpRestored ~= 0 and hp ~= 0 and (hp < math.floor(maxHp / 4) or (maxHp - hp) > p.hpRestored) then
            cat = "recover_hp" result = true
          end
        elseif p.healSleep then
          if band(status, MC.SLEEP) ~= 0 then cat, cond_ = "recover_status", "SLP" result = true end
        elseif p.healPoison then
          if band(status, MC.POISON + MC.TOXIC) ~= 0 then cat, cond_ = "recover_status", "PSN" result = true end
        elseif p.healBurn then
          if band(status, MC.BURN) ~= 0 then cat, cond_ = "recover_status", "BRN" result = true end
        elseif p.healFreeze then
          if band(status, MC.FREEZE) ~= 0 then cat, cond_ = "recover_status", "FRZ" result = true end
        elseif p.healParalysis then
          if band(status, MC.PARALYSIS) ~= 0 then cat, cond_ = "recover_status", "PAR" result = true end
        elseif p.healConfusion then
          if positive(battler.confusedTurns) then cat, cond_ = "recover_status", "CONFUSION" result = true end
        elseif (battler.g4aiInTurn or m.turn or 0) - (m.turn or 0) >= 0 then
          -- the X items only on the turn the Pokemon came in
          if p.atk ~= 0 then cat, cond_ = "stat", "attack" result = true
          elseif p.def ~= 0 then cat, cond_ = "stat", "defense" result = true
          elseif p.spatk ~= 0 then cat, cond_ = "stat", "spatk" result = true
          elseif p.spdef ~= 0 then cat, cond_ = "stat", "spdef" result = true
          elseif p.speed ~= 0 then cat, cond_ = "stat", "speed" result = true
          elseif p.acc ~= 0 then cat, cond_ = "stat", "accuracy" result = true
          elseif p.guardSpec and band(sideMask(battle, false), 64) == 0 then cat = "guard_spec" result = true end
        end
        -- BUG kept: once any item qualified, every later reachable slot is
        -- spent too and the LAST one is the item named
        if result then
          use = use or {}
          use.item = item
          if cat then use.category, use.condition = cat, cond_ end
          list[i + 1] = 0
        end
      end
    end
  end
  return use
end

-- TrainerAI_PickCommand: a switch or an item action, or nil for "fight"
function G.command(battle, battler)
  if not (G.applies(battle) and battler and battler.position) then return nil end
  local bt = G.battleType(battle)
  if band(bt, BT_TRAINER) == 0 and not battler.isPlayer then return nil end
  local m = memory(battle)
  local slot = G.shouldSwitch(battle, battler)
  if slot then
    if slot == 6 then
      slot = G.postKO(battle, battler.position)
      if slot == 6 then
        local s1, s2 = pairSlots(battle, battler.position)
        for i, mon in ipairs(partyFor(battle, battler.position)) do
          if (tonumber(mon.hp) or 0) > 0 and i - 1 ~= s1 and i - 1 ~= s2 then slot = i - 1 break end
        end
      end
    end
    if slot and slot ~= 6 then
      m.switched[battler.position] = slot
      return { special = "aiSwitch", g4 = true, index = slot + 1, position = battler.position }
    end
  end
  local use = G.shouldUseItem(battle, battler)
  if use and use.category then
    return { special = "aiItem", g4 = true, item = use.item, category = use.category,
             condition = use.condition, position = battler.position }
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- carrying the actions out
-- ---------------------------------------------------------------------------

function G.trainerLabel(battle, battler)
  local tr = (battler and battler.position == 3 and battle.trainerB) or battle.trainer
  if tr and battle.trainerB and tr == battle.trainerB then
    local cls = tr.className and (tr.className .. " ") or ""
    return cls .. (tr.name or "")
  end
  if battle.trainerLabel_ then return battle:trainerLabel_() end
  return tr and tr.name or "The foe"
end

-- the item's effect on the battler, with the lines it prints
function G.applyItem(battle, user, action)
  local Strings = require("src.core.Strings")
  local def = itemDef(battle, action.item)
  local name = def and def.name or "item"
  local msgs = { Strings("%s used\n%s!", G.trainerLabel(battle, user), name) }
  local mon = user and user.mon
  if not mon then return msgs end
  local p = param(def) or {}
  local cat = action.category
  local maxHp = maxHpOf(user)
  local who = user.name or "The foe"
  if cat == "full_restore" then
    mon.hp = maxHp
    mon.status, user.toxicCounter, user.sleepTurns = nil, nil, nil
    user.confusedTurns = nil
    msgs[#msgs + 1] = Strings("%s's HP was\nrestored.", who)
  elseif cat == "recover_hp" then
    local amount = p.hpRestored or 0
    if amount >= 255 then amount = maxHp end
    mon.hp = math.min(maxHp, (mon.hp or 0) + amount)
    msgs[#msgs + 1] = Strings("%s's HP was\nrestored.", who)
  elseif cat == "recover_status" then
    if action.condition == "CONFUSION" then user.confusedTurns = nil
    else mon.status, user.toxicCounter, user.sleepTurns = nil, nil, nil end
    msgs[#msgs + 1] = Strings("%s's status\nreturned to normal!", who)
  elseif cat == "stat" then
    local key = action.condition
    user.stages = user.stages or {}
    local amount = ({ attack = p.atk, defense = p.def, spatk = p.spatk, spdef = p.spdef,
                      speed = p.speed, accuracy = p.acc })[key] or 1
    if amount == 0 then amount = 1 end
    user.stages[key] = math.min(6, (user.stages[key] or 0) + amount)
    local label = ({ attack = "ATTACK", defense = "DEFENSE", spatk = "SP. ATK",
                     spdef = "SP. DEF", speed = "SPEED", accuracy = "accuracy" })[key] or key
    msgs[#msgs + 1] = Strings("%s's %s\nrose!", who, label)
  elseif cat == "guard_spec" then
    for pos = 0, 3 do
      local b = at(battle, pos)
      if b and b.isPlayer == user.isPlayer then b.mist = true end
    end
    msgs[#msgs + 1] = Strings("%s became\nshrouded in mist!", who)
  end
  return msgs
end

-- a voluntary switch at any slot (the engine's own aiSwitch only knows the
-- left-hand foe)
function G.applySwitch(battle, user, action)
  local BattleState = require("src.battle.BattleState")
  local Strings = require("src.core.Strings")
  local pos = action.position or (user and user.position) or 1
  local party = partyFor(battle, pos)
  local mon = party[action.index]
  if not (mon and usable(mon)) then return false end
  for p = 0, 3 do
    local b = at(battle, p)
    if b and b.mon == mon then return false end
  end
  local previous = at(battle, pos)
  local incoming = BattleState.makeBattler(battle.data, mon, pos % 2 == 0, nil)
  if previous and previous.ally then incoming.ally = true end
  battle:placeBattler(pos, incoming)
  if pos == 1 then battle.enemyIndex = action.index
  elseif pos == 3 then battle.enemyIndexRight = action.index end
  incoming.g4aiInTurn = (memory(battle).turn or 0) + 1
  battle:syncSides()
  local Runtime = require("src.mods.Runtime")
  Runtime.emit("battle.battler_switched", { battle = battle, side = battle.sides[pos % 2 == 0 and 1 or 2],
    battler = incoming, previous = previous })
  battle:abilitySwitchOut(previous)
  -- a foe's Wrap / Bind on the Pokemon that left ends (the engine's aiSwitch
  -- runs clearTrapping on the other side)
  for p = 0, 3 do
    local foe = at(battle, p)
    if foe and foe.isPlayer ~= incoming.isPlayer then
      foe.trappingTurns, foe.trapMove, foe.trapDamage = nil, nil, nil
    end
  end
  local label = incoming.isPlayer and (battle.ally and battle.ally.name or "") or G.trainerLabel(battle, incoming)
  battle:sayNext(Strings("%s withdrew\n%s!", label, previous and previous.name or "?"))
  battle:sayNext(Strings("%s sent\nout %s!", label, incoming.name))
  local HeldItems = require("src.battle.HeldItems")
  HeldItems.onEntry(battle, incoming)
  battle:actNext(function() battle:abilitySwitchIn(incoming) end)
  return true
end

-- the replacement for a fainted AI battler: 1-based party index or nil
function G.replacement(battle, pos)
  if not (G.applies(battle) and battle.kind == "trainer") then return nil end
  local slot = G.postKO(battle, pos)
  local party = partyFor(battle, pos)
  if slot == 6 then
    local s1, s2 = pairSlots(battle, pos)
    for i, mon in ipairs(party) do
      if (tonumber(mon.hp) or 0) > 0 and i - 1 ~= s1 and i - 1 ~= s2 then return i end
    end
    return nil
  end
  return slot + 1
end

-- moveHit / moveHitBattler: the move that last hit a battler and who used
-- it.  INFERRED from the engine's own record (applyDamage's g4HitBy, the
-- attacker, and that attacker's lastMove), which only sees DAMAGING hits.
function G.hitBy(b)
  local by = b and b.g4HitBy
  if not (by and by.lastMove) then return nil end
  return tonumber(by.lastMove) or 0, by
end

return G
