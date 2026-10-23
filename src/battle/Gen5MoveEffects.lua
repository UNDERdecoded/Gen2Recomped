-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S MOVE EFFECTS.
--
-- !! EVERY BW STATUS MOVE SAID "But, it failed!".
--
-- A BW move record (/a/0/2/1, src/import/Gen5Data.lua) keeps its battle
-- effect as the cartridge's NUMBER and the engine dispatches on a NAME
-- through `effectRecord`, so a number matched nothing: Growl, Leer, Thunder
-- Wave, Protect, Swords Dance... printed the failure line, and every damaging
-- move ran as a bare hit -- no burn from Ember, no flinch from Bite, no
-- recoil, no drain, no multi-hit. The same bug Hoenn and Sinnoh each had
-- once (see Gen4Moves.lua's header); this is Unova's fix.
--
-- WHAT THE NUMBERS ARE. Joined to Platinum's own move table BY MOVE NAME,
-- every BW move Platinum also has carries the SAME effect number except two
-- (Growth 13 -> 316, Tail Glow 53 -> 321, both moves Gen 5 changed), so BW
-- kept Gen 4's numbering (0..276, itself Gen 3's plus 62) and appended its
-- own, 277..337. Checked by tools/gen5_move_effects_check (the join and the
-- outcome of every move in a real battle).
--
-- WHAT BW ADDED, AND WHY THIS IS NOT A NAME TABLE. A BW record also carries
-- the effect as DATA: its class (0 hit, 1 status, 2 stat, 3 heal, 4 hit +
-- condition, 5 status + stat, 6 hit + foe stat, 7 hit + own stat, 8 drain,
-- 9 OHKO, 10 field, 11 side, 12 force switch, 13 unique), the condition and
-- its chance, up to three stat changes with amounts and chances, flinch,
-- crit stage, hit counts, recoil / drain percent, heal percent, target and
-- flags. Most of the cartridge's effects are those fields read by one
-- generic routine, and so are these records: Growl, Coil, Quiver Dance and
-- Shell Smash's siblings all read the stat list; Ember, Bite, Thunder Shock
-- and Water Pulse all read their condition / flinch byte. Only the effects
-- the fields cannot say (Protect, Counter, Baton Pass, Psyshock...) have
-- code of their own, keyed by the effect number.
--
-- HOW IT PLUGS IN.
--   * `attach(battle)` (BattleState's constructor): names every BW move once
--     per dataset (`move.effect` becomes a BW_* name, the number is kept as
--     `move.bwEffect`), stamps the fields the engine reads (multiHit,
--     highCrit, protectAffected, makesContact, range...), gives BW species
--     their ability names and makes `gen5_bw` the default ruleset.
--   * `record(battle, name)` (BattleState:effectRecord): the record for a
--     BW_* name, built once.
--   * `onSwitchIn` (BattleState:abilitySwitchIn): entry hazards and wishes.
--   * a field token ticks the timers at the end of each turn (screens,
--     Tailwind, binding, Aqua Ring, Curse, Nightmare...).
-- Text is the cartridge's own (src/battle/Gen5BattleText.lua).

local Strings = require("src.core.Strings")
local T = require("src.battle.Gen5BattleText")

local G5 = {}

local function Abil() return require("src.battle.Abilities") end
local function ME() return require("src.battle.MoveEffects") end
local function SR() return require("src.battle.StatusRegistry") end
local function TC() return require("src.battle.TypeChart") end
local function Wx() return require("src.battle.Weather") end
local function HI() return require("src.battle.HeldItems") end

G5.STATS = { [1] = "attack", [2] = "defense", [3] = "spatk", [4] = "spdef",
             [5] = "speed", [6] = "accuracy", [7] = "evasion" }
G5.ALL_FIVE = { "attack", "defense", "spatk", "spdef", "speed" }
G5.CONDITION = { [1] = "PAR", [2] = "SLP", [3] = "FRZ", [4] = "BRN", [5] = "PSN" }
G5.TYPES = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK",
             "BUG", "GHOST", "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC",
             "PSYCHIC", "ICE", "DRAGON", "DARK" }

-- the flag bits of a BW move record (+0x20)
G5.FLAG = { contact = 0, charge = 1, recharge = 2, protect = 3, reflectable = 4,
            snatch = 5, mirror = 6, punch = 7, sound = 8, gravity = 9,
            thaw = 10, distance = 11, heal = 12, bypassSub = 13 }

-- Gen 5's abilities past Platinum's 123, in the cartridge's order
G5.ABILITIES_5 = {
  [124] = "PICKPOCKET", "SHEER_FORCE", "CONTRARY", "UNNERVE", "DEFIANT",
  "DEFEATIST", "CURSED_BODY", "HEALER", "FRIEND_GUARD", "WEAK_ARMOR",
  "HEAVY_METAL", "LIGHT_METAL", "MULTISCALE", "TOXIC_BOOST", "FLARE_BOOST",
  "HARVEST", "TELEPATHY", "MOODY", "OVERCOAT", "POISON_TOUCH", "REGENERATOR",
  "BIG_PECKS", "SAND_RUSH", "WONDER_SKIN", "ANALYTIC", "ILLUSION", "IMPOSTER",
  "INFILTRATOR", "MUMMY", "MOXIE", "JUSTIFIED", "RATTLED", "MAGIC_BOUNCE",
  "SAP_SIPPER", "PRANKSTER", "SAND_FORCE", "IRON_BARBS", "ZEN_MODE",
  "VICTORY_STAR", "TURBOBLAZE", "TERAVOLT",
}

local function bit(flags, b) return math.floor((tonumber(flags) or 0) / 2 ^ b) % 2 == 1 end
local function maxHP(b)
  local m = b and b.mon
  if not m then return 1 end
  return (m.stats and m.stats.hp) or m.maxHP or m.maxHp or 1
end
local function hasType(b, t)
  for _, x in ipairs(b and b.curTypes or {}) do if x == t then return true end end
  return false
end
local function abilityOf(b) return Abil().of(b) end
local function itemOf(b)
  local id = b and b.mon and (b.mon.item or b.mon.heldItem)
  if id == 0 or id == false then return nil end
  return id
end
local function itemDef(battle, id)
  return id and battle.data and battle.data.items and battle.data.items[id] or nil
end
local function isBerry(battle, id)
  local d = itemDef(battle, id)
  return d and type(d.name) == "string" and d.name:find("Berry", 1, true) ~= nil
end
local function append(into, list)
  for _, x in ipairs(list or {}) do into[#into + 1] = x end
  return into
end
local function roll(battle, pct)
  if pct >= 100 then return true end
  if pct <= 0 then return false end
  return battle.rng(0, 99) < pct
end
local function turnOf(battle) return battle.turnCount or 0 end
local function sideIndex(b) return (b and b.isPlayer) and 1 or 2 end
local function moveName(battle, id)
  local d = battle.data and battle.data.moves and battle.data.moves[id]
  return d and d.name or tostring(id)
end
local function failed(battle) return T.std(battle, "failed", nil, "But it failed!") end
local function fail(ctx, text)
  ctx.battle:cancelMoveAnim()
  return { text or failed(ctx.battle) }
end
local function grounded(b)
  if hasType(b, "FLYING") or abilityOf(b) == "LEVITATE" then return b.bwGrounded == true end
  if b.bwMagnetRise or b.bwTelekinesis then return b.bwGrounded == true end
  return true
end
local function weightOf(b)
  local w = tonumber(b and b.def and b.def.weight) or 1
  w = w - (b.bwWeightLoss or 0)
  if abilityOf(b) == "HEAVY_METAL" then w = w * 2 end
  if abilityOf(b) == "LIGHT_METAL" then w = math.floor(w / 2) end
  return math.max(1, w)
end

-- ---------------------------------------------------------------------------
-- PREPARING A DATASET
-- ---------------------------------------------------------------------------

local prepared = setmetatable({}, { __mode = "k" })

-- a BW move record: the cartridge's own class byte is its signature
local function isBWMove(m)
  return type(m) == "table" and m.effectClass ~= nil and m.statChanges ~= nil
end

function G5.isBW(data)
  local moves = data and data.moves
  if type(moves) ~= "table" then return false end
  local m = moves[1]
  return isBWMove(m) or (type(m) == "table" and m.bwEffect ~= nil)
end

-- the 2..5 roll Gen 5 uses: 35 / 35 / 15 / 15
local TWO_TO_FIVE = { 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 5, 5, 5 }

-- the charge-turn lines, by effect (the template is formatted with the
-- engine's name for the user; Gen5BattleText turns it into the cartridge's)
G5.CHARGE = {
  [39] = { Strings.source("%s\nwhipped up a whirlwind!") }, [75] = { Strings.source("%s became\ncloaked in a harsh light!") },
  [145] = { Strings.source("%s tucked\nin its head!") }, [151] = { Strings.source("%s\nabsorbed light!") },
  [155] = { Strings.source("%s\nflew up high!"), "air" }, [255] = { Strings.source("%s hid\nunderwater!"), "underwater" },
  [256] = { Strings.source("%s burrowed\nits way under the ground!"), "underground" },
  [263] = { Strings.source("%s\nsprang up!"), "air" }, [272] = { Strings.source("%s vanished\ninstantly!"), "vanished" },
  [311] = { Strings.source("%s\nflew up high!"), "air" },
  [331] = { Strings.source("%s became cloaked\nin a freezing light!") }, [332] = { Strings.source("%s became cloaked\nin freezing air!") },
}

local NAMES -- effect id -> record name, filled below

function G5.nameFor(m)
  local e = m.bwEffect or 0
  local name = NAMES[e]
  if not name then
    local k = m.effectClass or 0
    if k == 1 then name = "BW_STATUS"
    elseif k == 2 then name = "BW_STAT"
    elseif k == 3 then name = "BW_HEAL"
    elseif k == 5 then name = "BW_SWAGGER"
    elseif k == 9 then name = "BW_OHKO"
    elseif (m.power or 0) > 0 then name = "BW_HIT"
    else name = ("BW_UNKNOWN_%d"):format(e) end
  end
  if (m.accuracy or 0) > 100 then name = name .. "~SURE" end
  return name
end

local function prepareMove(m)
  m.bwEffect = tonumber(m.effect) or 0
  local heal = tonumber(m.heal) or 0
  if heal > 127 then heal = heal - 256 end
  m.bwHeal = heal
  m.effect = G5.nameFor(m)
  local crit = tonumber(m.critStage) or 0
  if crit >= 1 and crit < 6 then m.highCrit = true end
  local lo, hi = tonumber(m.hitsMin) or 0, tonumber(m.hitsMax) or 0
  if hi > 1 then
    if lo == hi then m.multiHit = hi
    elseif lo == 2 and hi == 5 then m.multiHit = TWO_TO_FIVE
    else
      local d = {}
      for n = lo, hi do d[#d + 1] = n end
      m.multiHit = d
    end
  end
  local f = m.flags
  m.makesContact = bit(f, G5.FLAG.contact)
  m.protectAffected = bit(f, G5.FLAG.protect)
  m.magicCoatAffected = bit(f, G5.FLAG.reflectable)
  m.snatchAffected = bit(f, G5.FLAG.snatch)
  m.mirrorMoveAffected = bit(f, G5.FLAG.mirror)
  m.punchMove = bit(f, G5.FLAG.punch) or nil
  m.soundMove = bit(f, G5.FLAG.sound) or nil
  m.thawsUser = bit(f, G5.FLAG.thaw) or nil
  m.healMove = bit(f, G5.FLAG.heal) or nil
  m.gravityBanned = bit(f, G5.FLAG.gravity) or nil
  m.bypassesSub = bit(f, G5.FLAG.bypassSub) or nil
  -- the spread rows of the Platinum ruleset read Platinum's range bits
  if m.range == nil then
    local t = tonumber(m.target)
    if t == 5 then m.range = 0x04 elseif t == 4 then m.range = 0x08 end
  end
  -- what the engine's older side-effect records read, in 256ths
  local chance = 0
  if (m.condition or 0) ~= 0 then chance = m.conditionChance or 0 end
  if chance == 0 and m.statChanges and m.statChanges[1] then chance = m.statChanges[1].chance or 0 end
  if chance == 0 then chance = m.flinch or 0 end
  if chance > 0 then m.effectChance = math.floor(math.min(100, chance) * 256 / 100 + 0.5) end
  local ch = G5.CHARGE[m.bwEffect]
  if ch then
    m.chargeText = ch[1]
    if ch[2] then m.semiInvulnerable, m.hiddenAs = true, ch[2] end
  end
end

-- the ability NAMES Abilities.lua dispatches on, for BW's numbered species
local function prepareSpecies(data)
  local okG4, G4A = pcall(require, "src.import.Gen4Abilities")
  local function nameOf(id)
    id = tonumber(id)
    if not id or id == 0 then return nil end
    if id <= 123 and okG4 and G4A.NAMES then return G4A.NAMES[id] end
    return G5.ABILITIES_5[id]
  end
  for _, def in pairs(data.pokemon or {}) do
    if type(def) == "table" and def.abilities == nil and type(def.abilityIds) == "table" then
      local a, b = nameOf(def.abilityIds[1]), nameOf(def.abilityIds[2])
      if a then def.abilities = { a, b or a } end
    end
  end
end

function G5.prepare(data)
  if not G5.isBW(data) then return false end
  local moves = data.moves
  if prepared[moves] then return true end
  prepared[moves] = true
  for _, m in pairs(moves) do
    if isBWMove(m) and m.bwEffect == nil then prepareMove(m) end
  end
  pcall(prepareSpecies, data)
  -- the default ruleset: the cartridge's numbers, not Kanto's
  data.constants = data.constants or {}
  if data.constants.defaultRuleset == nil then
    local okR, R = pcall(require, "src.battle.rulesets.gen5_bw")
    if okR then
      if type(data.rulesets) ~= "table" then
        data.rulesets = {
          gen1_faithful = require("src.battle.rulesets.gen1_faithful"),
          modern_clean = require("src.battle.rulesets.modern_clean"),
        }
      end
      if data.rulesets.gen5_bw == nil then data.rulesets.gen5_bw = R end
      data.constants.defaultRuleset = "gen5_bw"
    end
  end
  return true
end

-- called from BattleState's constructor, before the ruleset is chosen
function G5.attach(battle)
  local data = battle and battle.data
  if not G5.prepare(data) then return end
  battle.bw = battle.bw or { sides = { {}, {} }, field = {} }
  -- "X used Move!" is printed with the move's NAME; the line is by id
  local byName = {}
  for id, m in pairs(data.moves) do
    if type(m) == "table" and type(m.name) == "string" and type(id) == "number" then
      byName[m.name] = byName[m.name] or id
    end
  end
  battle.bwMoveIdByName = byName
  battle.bw.struggle = data.moves[165]
end

-- ---------------------------------------------------------------------------
-- PER-BATTLE STATE: the timers, kept on battle.bw and ticked by a field token
-- ---------------------------------------------------------------------------

local function sideState(battle, b) return battle.bw.sides[sideIndex(b)] end

local function activeList(battle)
  local out = {}
  if battle.activeBattlers then
    for _, b in battle:activeBattlers() do if b and b.mon then out[#out + 1] = b end end
  end
  if #out == 0 then
    if battle.player then out[#out + 1] = battle.player end
    if battle.enemy then out[#out + 1] = battle.enemy end
  end
  return out
end

-- the side-wide conditions onto whoever is standing on that side
function G5.sync(battle)
  if not battle.bw then return end
  for _, b in ipairs(activeList(battle)) do
    local s = sideState(battle, b)
    if (s.reflect or 0) > 0 then b.reflect = true elseif b.bwReflectFromSide then b.reflect = nil end
    b.bwReflectFromSide = (s.reflect or 0) > 0 or nil
    if (s.lightScreen or 0) > 0 then b.lightScreen = true elseif b.bwLightFromSide then b.lightScreen = nil end
    b.bwLightFromSide = (s.lightScreen or 0) > 0 or nil
    if (s.mist or 0) > 0 then b.mist = true elseif b.bwMistFromSide then b.mist = nil end
    b.bwMistFromSide = (s.mist or 0) > 0 or nil
    b.bwSpeedMultiplier = (s.tailwind or 0) > 0 and 2 or nil
  end
end

function G5.ensure(battle)
  local bw = battle.bw
  if not bw then return nil end
  if not bw.token and battle.field and battle.field.tokens then
    bw.token = { id = "bw_upkeep", onResidual = function(b) G5.upkeep(b) end }
    table.insert(battle.field.tokens, bw.token)
  end
  return bw
end

local function sayNow(battle, text) if text and text ~= "" then battle:sayNext(text) end end

local function hurt(battle, b, amount)
  if not (b and b.mon and b.mon.hp > 0) then return end
  battle:applyDamage(b, math.max(1, amount))
  if b.mon.hp <= 0 then battle:onFaint(b) end
end

local function heal(battle, b, amount)
  local max = maxHP(b)
  if b.mon.hp >= max then return 0 end
  local before = b.mon.hp
  b.mon.hp = math.min(max, b.mon.hp + math.max(1, math.floor(amount)))
  battle:drainNext(b, b.mon.hp)
  return b.mon.hp - before
end

local function releaseBind(battle, b, quiet)
  local bound = b.bwBound
  if not bound then return end
  b.bwBound = nil
  if b.bwTrappedByBind then b.trapped, b.bwTrappedByBind = nil, nil end
  if not quiet and b.mon and b.mon.hp > 0 then
    sayNow(battle, T.set(battle, "freedFrom", b, { nil, bound.name }))
  end
end

-- the end of a turn
function G5.upkeep(battle)
  local bw = battle.bw
  if not bw or battle.result then return end
  local turn = turnOf(battle)
  for _, b in ipairs(activeList(battle)) do
    local alive = b.mon and b.mon.hp > 0
    if alive and b.bwRoost and b.bwRoost.turn <= turn then
      b.curTypes, b.bwRoost = b.bwRoost.types, nil
    end
    -- binding: a sixteenth, until the counter or the binder runs out
    if alive and b.bwBound then
      local bound = b.bwBound
      local by = bound.by
      if not (by and by.mon and by.mon.hp > 0) or (by ~= battle.player and by ~= battle.enemy
          and not (battle.isDouble and battle:isDouble())) then
        releaseBind(battle, b, true)
      else
        bound.turns = bound.turns - 1
        if bound.turns <= 0 then
          releaseBind(battle, b)
        else
          sayNow(battle, T.set(battle, "hurtBy", b, { nil, bound.name }))
          -- (a Binding Band makes it an eighth: Gen5MoveRules stamps `div`)
          hurt(battle, b, math.floor(maxHP(b) / (bound.div or 16)))
        end
      end
    end
    alive = b.mon and b.mon.hp > 0
    if alive and b.bwAquaRing and b.mon.hp < maxHP(b) then
      sayNow(battle, T.set(battle, "aquaRingHeal", b))
      heal(battle, b, maxHP(b) / 16)
    end
    if alive and b.cursed then
      sayNow(battle, T.set(battle, "curseHurt", b))
      hurt(battle, b, math.floor(maxHP(b) / 4))
    end
    alive = b.mon and b.mon.hp > 0
    if alive and b.nightmare then
      if b.mon.status ~= "SLP" then b.nightmare = nil
      else
        sayNow(battle, T.set(battle, 324, b))
        hurt(battle, b, math.floor(maxHP(b) / 4))
      end
    end
    for _, key in ipairs({ "bwMagnetRise", "bwTelekinesis", "bwEmbargo", "bwHealBlock" }) do
      if b[key] then
        b[key] = b[key] - 1
        if b[key] <= 0 then
          b[key] = nil
          if b.mon and b.mon.hp > 0 then
            local line = ({ bwMagnetRise = "magnetRiseEnded", bwTelekinesis = "telekinesisEnded",
                            bwEmbargo = "embargoEnded", bwHealBlock = "healBlockEnded" })[key]
            sayNow(battle, T.set(battle, line, b))
          end
        end
      end
    end
  end
  -- the side timers
  for i = 1, 2 do
    local s = bw.sides[i]
    local rep = { isPlayer = (i == 1), name = "" }
    for key, line in pairs({ reflect = "reflectEnded", lightScreen = "lightScreenEnded",
                             mist = "mistEnded", tailwind = "tailwindEnded",
                             luckyChant = "luckyChantEnded" }) do
      if (s[key] or 0) > 0 then
        s[key] = s[key] - 1
        if s[key] <= 0 then
          s[key] = nil
          sayNow(battle, T.team(battle, line, rep))
        end
      end
    end
    -- a Pokemon that fainted this turn (Retaliate's question)
    for _, b in ipairs(activeList(battle)) do
      if sideIndex(b) == i and b.mon and b.mon.hp <= 0 then s.faintedTurn = turn end
    end
  end
  for key, line in pairs({ gravity = "gravityEnded", wonderRoom = "wonderRoomEnded",
                           magicRoom = "magicRoomEnded" }) do
    if (bw.field[key] or 0) > 0 then
      bw.field[key] = bw.field[key] - 1
      if bw.field[key] <= 0 then
        bw.field[key] = nil
        sayNow(battle, T.std(battle, line))
      end
    end
  end
  G5.sync(battle)
end

-- a Pokemon arriving on the field (BattleState:abilitySwitchIn)
function G5.onSwitchIn(battle, battler)
  local bw = battle and battle.bw
  if not (bw and battler and battler.mon and battler.mon.hp > 0) then return end
  G5.ensure(battle)
  local s = sideState(battle, battler)
  if s.healingWish then
    local lunar = s.healingWish == "lunar"
    s.healingWish = nil
    battler.mon.hp = maxHP(battler)
    battler.mon.status = nil
    battler.toxicCounter = nil
    if lunar then
      for _, mv in ipairs(battler.curMoves or {}) do
        local d = battle.data.moves[mv.id]
        if d and d.pp then mv.pp = math.max(mv.pp or 0, d.pp) end
      end
    end
    battle:drainNext(battler, battler.mon.hp)
    sayNow(battle, T.set(battle, lunar and "moonlight" or "healingWish", battler))
  end
  if grounded(battler) then
    local layers = s.spikes or 0
    if layers > 0 then
      local div = ({ 8, 6, 4 })[math.min(3, layers)]
      sayNow(battle, T.set(battle, "spikes", battler))
      hurt(battle, battler, math.floor(maxHP(battler) / div))
      if battler.mon.hp <= 0 then return end
    end
    local toxic = s.toxicSpikes or 0
    if toxic > 0 then
      if hasType(battler, "POISON") then
        s.toxicSpikes = nil
        sayNow(battle, T.team(battle, "toxicSpikesGone", battler))
      elseif not battler.mon.status then
        local msgs = SR().inflict(battle, battler, "PSN", { toxic = toxic >= 2 })
        for _, m in ipairs(msgs) do sayNow(battle, m) end
      end
    end
  end
  if s.stealthRock then
    local eff = TC().effectiveness("ROCK", battler.curTypes or {})
    if eff > 0 then
      sayNow(battle, T.set(battle, "stealthRock", battler))
      hurt(battle, battler, math.floor(maxHP(battler) * eff / 10 / 8))
    end
  end
  G5.sync(battle)
end

-- ---------------------------------------------------------------------------
-- SHARED PIECES
-- ---------------------------------------------------------------------------

-- the stat list a record carries (stat 8 is the five main stats at once)
function G5.statList(move)
  local out = {}
  for _, row in ipairs(move.statChanges or {}) do
    local id = tonumber(row.stat) or 0
    local amount = tonumber(row.amount) or 0
    if id == 8 then
      for _, s in ipairs(G5.ALL_FIVE) do out[#out + 1] = { s, amount } end
    elseif G5.STATS[id] and amount ~= 0 then
      out[#out + 1] = { G5.STATS[id], amount }
    end
  end
  return out
end

-- the chance the stat list goes off (one roll for the set, as the cartridge)
local function statChance(move)
  local row = move.statChanges and move.statChanges[1]
  return row and tonumber(row.chance) or 0
end

local NOT_LOWERED = { attack = 201, defense = 204, accuracy = 207 }

-- raise / lower `subject`'s stats; byFoe says the other side did it.
-- Returns the lines and whether anything moved.
function G5.changeStats(battle, subject, list, byFoe)
  local out, any = {}, false
  local ab = abilityOf(subject)
  for _, row in ipairs(list) do
    local stat, amount = row[1], row[2]
    if ab == "SIMPLE" then amount = amount * 2 end
    if ab == "CONTRARY" then amount = -amount end
    if amount < 0 and byFoe and (Abil().refusesStatDrop(subject, stat)
        or (ab == "BIG_PECKS" and stat == "defense")) then
      out[#out + 1] = T.set(battle, NOT_LOWERED[stat] or T.SET.statsNotLowered, subject)
    else
      local applied = ME().applyStage(subject.stages, stat, amount)
      if applied then
        any = true
        subject.hazeStatReset = nil
        out[#out + 1] = T.stat(battle, subject, stat, applied)
        if applied < 0 and byFoe and ab == "DEFIANT" then
          local up = ME().applyStage(subject.stages, "attack", 2)
          if up then out[#out + 1] = T.stat(battle, subject, "attack", up) end
        end
      else
        out[#out + 1] = T.stat(battle, subject, stat, 0, amount)
      end
    end
  end
  return out, any
end

-- the pre-checks a stat drop from the other side has to pass
local function foeStatBlocked(ctx, subject)
  if subject == ctx.user then return nil end
  if subject.substituteHP and not ctx.move.bypassesSub then return failed(ctx.battle) end
  if subject.mist then return T.set(ctx.battle, "mist", subject) end
  return nil
end

-- confuse `target`; `quietFail` keeps a secondary from printing a failure
function G5.confuse(ctx, target, secondary)
  local battle = ctx.battle
  if target.confusedTurns then
    return secondary and {} or { T.set(battle, "alreadyConfused", target) }
  end
  if Abil().refusesStatus(target, "CONFUSION") then
    return secondary and {} or { T.set(battle, "notAffected", target) }
  end
  if target.safeguardTurns and not secondary then
    return { T.set(battle, "safeguarded", target) }
  end
  target.confusedTurns = battle.rng(2, 5)
  HI().setConfusionCounter(battle, target, target.confusedTurns)
  local out = { T.set(battle, "confused", target) }
  append(out, HI().onConfusion(battle, target))
  return out
end

local ALREADY = { PAR = "alreadyParalyzed", SLP = "alreadyAsleep", FRZ = "alreadyFrozen",
                  BRN = "alreadyBurned", PSN = "alreadyPoisoned" }

-- a major status; `secondary` keeps a side effect quiet when it does not land
function G5.inflict(ctx, target, status, opts)
  opts = opts or {}
  local battle = ctx.battle
  if target.mon.status then
    if opts.secondary then return {} end
    if target.mon.status == status then return { T.set(battle, ALREADY[status], target) } end
    return { failed(battle) }
  end
  if target.safeguardTurns and target ~= ctx.user then
    return opts.secondary and {} or { T.set(battle, "safeguarded", target) }
  end
  -- Uproar keeps everybody awake
  if status == "SLP" then
    for _, b in ipairs(activeList(battle)) do
      if b.uproarTurns then return opts.secondary and {} or { failed(battle) } end
    end
  end
  local msgs = SR().inflict(battle, target, status, {
    toxic = opts.toxic, moveType = ctx.move and ctx.move.type, user = ctx.user,
    source = ctx.move and ctx.move.id,
  })
  if #msgs == 0 then
    return opts.secondary and {} or { T.set(battle, "notAffected", target) }
  end
  return msgs
end

-- a BW condition number on `target`
function G5.condition(ctx, target, cond, opts)
  opts = opts or {}
  local status = G5.CONDITION[cond]
  if status then return G5.inflict(ctx, target, status, opts) end
  if cond == 6 then return G5.confuse(ctx, target, opts.secondary) end
  if cond == 7 then
    local fn = ME().primary.ATTRACT_EFFECT
    return fn and fn(ctx.battle, ctx.user, target, ctx.move, ctx.moveInst) or {}
  end
  return {}
end

-- Quick Guard / Wide Guard stand in front of a move this turn
local function guardBlocks(ctx)
  local battle, target, move = ctx.battle, ctx.target, ctx.move
  if not (battle.bw and target) or target == ctx.user then return nil end
  local s = sideState(battle, target)
  local turn = turnOf(battle)
  if s.quickGuard == turn and (move.priority or 0) > 0 then
    return T.team(battle, "quickGuard", target)
  end
  local t = tonumber(move.target)
  if s.wideGuard == turn and (t == 4 or t == 5) then
    return T.team(battle, "wideGuard", target)
  end
  return nil
end

-- what every BW move does on its way in: remember it (Copycat, Payback,
-- Last Resort, Echoed Voice), end a Rage that is not continuing
function G5.noteMove(ctx)
  local battle, user, move = ctx.battle, ctx.user, ctx.move
  local bw = battle.bw
  if not bw then return end
  G5.ensure(battle)
  G5.sync(battle)
  if move.bwEffect ~= 81 then user.bwRage = nil end
  user.bwMovedTurn = turnOf(battle)
  user.bwUsedMoves = user.bwUsedMoves or {}
  user.bwUsedMoves[move.id] = true
  if move.bwEffect ~= 242 then bw.lastMoveUsed = move.id end
end

-- ---------------------------------------------------------------------------
-- DAMAGE: one routine for every BW hit, so the power / type / stat / crit
-- overrides an effect needs are fields of its spec
-- ---------------------------------------------------------------------------

local function view(move, fields)
  return setmetatable(fields, { __index = move })
end

local function immune(ctx, mtype)
  local t = ctx.target
  mtype = mtype or ctx.move.type
  if TC().effectiveness(mtype, t.curTypes or {}) == 0 then
    -- Foresight / Odor Sleuth: a Ghost is hit by Normal and Fighting
    if t.identified and (mtype == "NORMAL" or mtype == "FIGHTING") and hasType(t, "GHOST") then
      return false
    end
    return true
  end
  return false
end

local function hasSecondary(move)
  local k = move.effectClass
  return k == 4 or k == 6 or (k == 7 and statChance(move) < 100 and statChance(move) > 0)
         or (move.flinch or 0) > 0
end

function G5.damage(ctx, spec)
  local battle, user, target, move = ctx.battle, ctx.user, ctx.target, ctx.move
  local mtype = spec.moveType and spec.moveType(ctx) or move.type
  -- Ground moves against something in the air by other means
  if mtype == "GROUND" and (target.bwMagnetRise or target.bwTelekinesis) and not target.bwGrounded then
    return nil, T.set(battle, "notAffected", target)
  end
  if spec.fixed then
    if spec.typeChecked ~= false and immune(ctx, mtype) then
      return nil, T.set(battle, "notAffected", target)
    end
    local dmg, why = spec.fixed(ctx)
    if not dmg then return nil, why or failed(battle) end
    return math.max(1, math.floor(dmg)), { crit = false, typeMult = 10 }
  end
  local fields = {}
  local power = spec.power and spec.power(ctx)
  if power == false then return nil, failed(battle) end
  if power then fields.power = math.max(1, math.floor(power)) end
  if mtype ~= move.type then fields.type = mtype end
  local mv = next(fields) and view(move, fields) or move
  local attacker = spec.attacker and spec.attacker(ctx) or user
  local defender = spec.defender and spec.defender(ctx) or target
  local mult = spec.powerMultiplier and spec.powerMultiplier(ctx) or 1
  if user.bwHelped == turnOf(battle) then mult = mult * 1.5 end
  -- Me First, Wonder Room (src/battle/Gen5MoveRules.lua)
  if G5.adjust then attacker, defender, mult = G5.adjust(ctx, attacker, defender, mult) end
  if abilityOf(user) == "SHEER_FORCE" and hasSecondary(move) then mult = mult * 1.3 end
  local opts = { rng = battle.rng, powerMultiplier = mult ~= 1 and mult or nil }
  if (move.critStage or 0) >= 6 then opts.forceCrit = true end
  if (sideState(battle, target).luckyChant or 0) > 0 then opts.forceCrit = false end
  return battle:computeDamage(attacker, defender, mv, opts)
end

-- ---------------------------------------------------------------------------
-- THE RECORD FACTORIES
-- ---------------------------------------------------------------------------

-- a status move (power 0): `spec.run(ctx)` returns the lines. `foe` marks one
-- aimed at the other side: it rolls accuracy, is stopped by a substitute
-- (unless the flags say otherwise) and can be bounced by Magic Coat.
local function primaryRecord(name, spec, sure)
  local rec = { kind = "primary", bwName = name, status = spec.status, note = spec.note }
  rec.accuracyChecked = (spec.foe and not sure) or nil
  rec.run = function(ctx)
    G5.noteMove(ctx)
    local battle, user, target, move = ctx.battle, ctx.user, ctx.target, ctx.move
    if spec.foe then
      local g = guardBlocks(ctx)
      if g then return fail(ctx, g) end
      -- MAGIC COAT / MAGIC BOUNCE send it back
      if move.magicCoatAffected and target ~= user
         and (target.bwMagicCoat == turnOf(battle) or abilityOf(target) == "MAGIC_BOUNCE") then
        local out = { T.set(battle, 764, target, { nil, move.name }) }
        local swapped = setmetatable({ user = target, target = user }, { __index = ctx })
        return append(out, spec.run(swapped) or {})
      end
      if target.substituteHP and not move.bypassesSub and not spec.ignoresSub then
        return fail(ctx)
      end
    elseif move.snatchAffected then
      -- SNATCH: the other side takes the move for itself
      for _, b in ipairs(activeList(battle)) do
        if b ~= user and sideIndex(b) ~= sideIndex(user) and b.bwSnatch == turnOf(battle)
           and b.mon.hp > 0 then
          b.bwSnatch = nil
          local out = { T.pair(battle, 754, b, user) }
          local swapped = setmetatable({ user = b, target = user }, { __index = ctx })
          return append(out, spec.run(swapped) or {})
        end
      end
    end
    return spec.run(ctx) or {}
  end
  return rec
end

-- the hidden places a move still reaches
local REACH_AIR = { air = true }
local REACH_GROUND = { underground = true }
local REACH_WATER = { underwater = true }

-- a damaging move (or one resolved in `perform`)
local function fullRecord(name, spec, sure)
  local rec = { kind = "full", bwName = name, status = spec.status, note = spec.note,
                charge = spec.charge, hitCount = spec.hitCount, announceAnim = spec.announceAnim,
                neverMiss = (sure or spec.neverMiss) or nil, neverMissInvulnerable = true }
  if spec.perform then
    rec.perform = function(ctx)
      G5.noteMove(ctx)
      return spec.perform(ctx, rec)
    end
  end
  if spec.callsMove then
    rec.callsMove = function(ctx)
      G5.noteMove(ctx)
      return spec.callsMove(ctx)
    end
  end
  rec.gate = function(ctx)
    G5.noteMove(ctx)
    local battle, target = ctx.battle, ctx.target
    if target.invulnerable and not (spec.reaches and spec.reaches[target.hiddenAs]) then
      return false, T.set(battle, "avoided", target)
    end
    local g = guardBlocks(ctx)
    if g then return false, g end
    if spec.gate then
      local ok, msg = spec.gate(ctx)
      if not ok then return false, msg end
    end
    return true
  end
  rec.beforeAccuracy = spec.beforeAccuracy
  rec.onMiss = spec.onMiss
  rec.chooseDamage = function(ctx)
    if spec.chooseDamage then return spec.chooseDamage(ctx) end
    return G5.damage(ctx, spec)
  end
  rec.afterDamage = function(ctx, total)
    local battle, user, target, move = ctx.battle, ctx.user, ctx.target, ctx.move
    total = total or 0
    if total > 0 then
      -- what Counter, Mirror Coat, Metal Burst, Assurance, Revenge read
      target.bwHit = { by = user, damage = total, turn = turnOf(battle),
                       physical = move.class == "physical" }
      -- RAGE: hit while raging, and the Attack climbs
      if target.bwRage and target.mon.hp > 0 then
        local up = ME().applyStage(target.stages, "attack", 1)
        if up then sayNow(battle, T.set(battle, "rageBuilding", target)) end
      end
    end
    if spec.afterDamage then spec.afterDamage(ctx, total) end
    -- recoil (a negative percent of the damage dealt) and drain (a positive one)
    local r = tonumber(move.recoil) or 0
    if total > 0 and r < 0 and user.mon.hp > 0 and not Abil().ignoresRecoil(user) then
      sayNow(battle, T.set(battle, "recoil", user))
      hurt(battle, user, math.floor(total * -r / 100))
    elseif total > 0 and r > 0 and user.mon.hp > 0 then
      local amount = math.max(1, math.floor(total * r / 100))
      if Abil().reversesDrain(target) then
        sayNow(battle, T.set(battle, 457, user))
        hurt(battle, user, amount)
      elseif not user.bwHealBlock and heal(battle, user, amount) > 0 then
        sayNow(battle, T.set(battle, 899, target))
      end
    end
    -- Struggle: a quarter of the user's own maximum
    if total > 0 and (move.bwHeal or 0) < 0 and user.mon.hp > 0 then
      sayNow(battle, T.set(battle, "recoil", user))
      hurt(battle, user, math.floor(maxHP(user) * -move.bwHeal / 100))
    end
    -- the user's own stats (class 7: Superpower, Overheat, Flame Charge...)
    if total > 0 and move.effectClass == 7 and user.mon.hp > 0
       and not (abilityOf(user) == "SHEER_FORCE" and hasSecondary(move)) then
      local c = statChance(move)
      if c == 0 then c = 100 end
      if c < 100 then c = Abil().secondaryOdds(user, nil, c) end
      if roll(battle, c) then
        for _, line in ipairs((G5.changeStats(battle, user, G5.statList(move), false))) do
          sayNow(battle, line)
        end
      end
    end
    -- a Fire move thaws what it hits
    if total > 0 and target.mon.hp > 0 and target.mon.status == "FRZ" and move.type == "FIRE" then
      target.mon.status = nil
      sayNow(battle, T.set(battle, "thawed", target))
    end
  end
  rec.run = function(ctx)
    local battle, user, target, move = ctx.battle, ctx.user, ctx.target, ctx.move
    local out = {}
    if target.substituteHP or ctx.brokeSub then return out end
    local blocked = Abil().refusesSecondary(target)
                    or (abilityOf(user) == "SHEER_FORCE" and hasSecondary(move))
    if not blocked then
      -- the condition (class 4); a chance of 0 is no roll at all (Chatter)
      local cond = tonumber(move.condition) or 0
      if move.effectClass == 4 and cond >= 1 and cond <= 7 and not spec.noCondition then
        local c = Abil().secondaryOdds(user, target, tonumber(move.conditionChance) or 0)
        if c > 0 and roll(battle, c) then
          append(out, G5.condition(ctx, target, cond,
                                   { secondary = true, toxic = spec.toxic }))
        end
      end
      -- the target's stats (class 6)
      if move.effectClass == 6 then
        local c = Abil().secondaryOdds(user, target, statChance(move))
        if c > 0 and roll(battle, c) and not target.mist then
          append(out, (G5.changeStats(battle, target, G5.statList(move), true)))
        end
      end
      -- flinch
      if (move.flinch or 0) > 0 and not Abil().refusesFlinch(target) then
        local c = Abil().secondaryOdds(user, target, move.flinch)
        if roll(battle, c) then target.flinched = true end
      end
    end
    if spec.run then append(out, spec.run(ctx) or {}) end
    return out
  end
  return rec
end

-- ---------------------------------------------------------------------------
-- THE EFFECTS
-- ---------------------------------------------------------------------------

local DEF = {}
G5.DEF = DEF

local function P(spec) spec.kind = "primary" return spec end
local function F(spec) spec.kind = "full" spec = spec or {} return spec end

-- an engine record's callbacks, shimmed onto a BW spec
local function enginePrimary(name)
  return function(ctx)
    local fn = ME().primary[name]
    if not fn then return { failed(ctx.battle) } end
    return fn(ctx.battle, ctx.user, ctx.target, ctx.move, ctx.moveInst)
  end
end
local function engineFull(name)
  return ME().full[name] or {}
end

-- --- the data-driven ones -------------------------------------------------

DEF.BW_HIT = F({})

-- the stat moves: the record's own list, on the user or the target
DEF.BW_STAT = P({ foe = true, run = function(ctx)
  local battle, user, target, move = ctx.battle, ctx.user, ctx.target, ctx.move
  local t = tonumber(move.target)
  local subject = (t == 7 or t == 1 or t == 12) and user or target
  local list = G5.statList(move)
  if #list == 0 then return fail(ctx) end
  local blocked = foeStatBlocked(ctx, subject)
  if blocked then return fail(ctx, blocked) end
  -- GROWTH: twice the stages in sunshine
  if move.bwEffect == 316 and Wx().current(battle) == Wx().SUN then
    for _, row in ipairs(list) do row[2] = row[2] * 2 end
  end
  -- CAPTIVATE: only the other gender
  if move.bwEffect == 265 and not require("src.pokemon.Pokemon").oppositeGenders(battle.data, user.mon, target.mon) then
    return fail(ctx, T.set(battle, "notAffected", target))
  end
  local out, any = G5.changeStats(battle, subject, list, subject ~= user)
  if not any then battle:cancelMoveAnim() end
  -- the move's own extras
  if any and move.bwEffect == 108 then user.bwMinimized = true end
  if any and move.bwEffect == 156 then user.bwCurled = true end
  if move.bwEffect == 174 then
    user.charged = true
    table.insert(out, 1, T.set(battle, "charging", user))
  end
  if move.bwEffect == 284 and any then
    local before = weightOf(user)
    user.bwWeightLoss = (user.bwWeightLoss or 0) + 1000
    if weightOf(user) < before then out[#out + 1] = T.set(battle, "nimble", user) end
  end
  return out
end })
-- the ones aimed at the user never roll accuracy: the record is shared, so
-- the self-targeting ones get their own name
DEF.BW_STAT_SELF = P({ run = DEF.BW_STAT.run })

-- the status moves: the record's own condition
DEF.BW_STATUS = P({ foe = true, run = function(ctx)
  local battle, target, move = ctx.battle, ctx.target, ctx.move
  local cond = tonumber(move.condition) or 0
  -- THUNDER WAVE does not reach a Ground type (the one status move that asks
  -- the type chart in Gen 5)
  if cond == 1 and move.type == "ELECTRIC" and immune(ctx) then
    return fail(ctx, T.set(battle, "notAffected", target))
  end
  local out = G5.condition(ctx, target, cond, { toxic = move.bwEffect == 33 })
  if #out == 0 then return fail(ctx) end
  local first = out[1]
  if first == failed(battle) or first:find("already", 1, true) or first:find("doesn't affect", 1, true)
     or first:find("protected by", 1, true) then
    battle:cancelMoveAnim()
  end
  return out
end })

DEF.BW_SWAGGER = P({ foe = true, run = function(ctx)
  local out = (G5.changeStats(ctx.battle, ctx.target, G5.statList(ctx.move), false))
  return append(out, G5.confuse(ctx, ctx.target, false))
end })

DEF.BW_HEAL = P({ run = function(ctx)
  local battle, user, move = ctx.battle, ctx.user, ctx.move
  if user.bwHealBlock then return fail(ctx, T.set(battle, 887, user)) end
  if user.mon.hp >= maxHP(user) then return fail(ctx, T.set(battle, "hpFull", user)) end
  local pct = (move.bwHeal or 0) > 0 and move.bwHeal or 50
  heal(battle, user, math.floor(maxHP(user) * pct / 100))
  -- ROOST: not a Flying type until the end of the turn
  if move.bwEffect == 214 and hasType(user, "FLYING") then
    local kept = {}
    for _, t in ipairs(user.curTypes or {}) do if t ~= "FLYING" then kept[#kept + 1] = t end end
    if #kept == 0 then kept = { "NORMAL" } end
    user.bwRoost = { types = user.curTypes, turn = turnOf(battle) }
    user.curTypes = kept
  end
  return { T.set(battle, "hpRestored", user) }
end })

DEF.BW_WEATHER_HEAL = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  if user.bwHealBlock then return fail(ctx, T.set(battle, 887, user)) end
  if user.mon.hp >= maxHP(user) then return fail(ctx, T.set(battle, "hpFull", user)) end
  local w = Wx().current(battle)
  local frac = (w == nil) and 1 / 2 or (w == Wx().SUN and 2 / 3 or 1 / 4)
  heal(battle, user, maxHP(user) * frac)
  return { T.set(battle, "hpRestored", user) }
end })

DEF.BW_HEAL_PULSE = P({ foe = true, ignoresSub = true, run = function(ctx)
  local battle, target = ctx.battle, ctx.target
  if target.mon.hp >= maxHP(target) then return fail(ctx, T.set(battle, "hpFull", target)) end
  heal(battle, target, maxHP(target) / 2)
  return { T.set(battle, "hpRestored", target) }
end })

-- --- one-hit KOs ---------------------------------------------------------

DEF.BW_OHKO = F({ neverMiss = true,
  gate = function(ctx)
    local battle, user, target = ctx.battle, ctx.user, ctx.target
    if (target.mon.level or 1) > (user.mon.level or 1) or immune(ctx) then
      return false, T.set(battle, "notAffected", target)
    end
    if Abil().refusesOHKO(target) then return false, T.set(battle, "unaffected", target) end
    local acc = 30 + (user.mon.level or 1) - (target.mon.level or 1)
    if user.lockedOn ~= target and not roll(battle, acc) then
      return false, T.set(battle, "avoided", target)
    end
    user.lockedOn = nil
    return true
  end,
  chooseDamage = function(ctx)
    return math.max(1, ctx.target.mon.hp), { crit = false, typeMult = 10, ohko = true }
  end,
})

-- --- fixed damage --------------------------------------------------------

DEF.BW_SONICBOOM = F({ fixed = function() return 20 end })
DEF.BW_DRAGON_RAGE = F({ fixed = function() return 40 end })
DEF.BW_LEVEL_DAMAGE = F({ fixed = function(ctx) return ctx.user.mon.level or 1 end })
DEF.BW_PSYWAVE = F({ fixed = function(ctx)
  return math.max(1, math.floor((ctx.user.mon.level or 1) * (ctx.battle.rng(0, 100) + 50) / 100))
end })
DEF.BW_SUPER_FANG = F({ fixed = function(ctx) return math.max(1, math.floor(ctx.target.mon.hp / 2)) end })
DEF.BW_ENDEAVOR = F({ fixed = function(ctx)
  local d = ctx.target.mon.hp - ctx.user.mon.hp
  if d <= 0 then return nil end
  return d
end })
DEF.BW_FINAL_GAMBIT = F({ fixed = function(ctx) return ctx.user.mon.hp end,
  afterDamage = function(ctx, total)
    if total > 0 and ctx.user.mon.hp > 0 then
      ctx.battle:applyDamage(ctx.user, ctx.user.mon.hp)
    end
  end })

-- what was done to the user this turn, by the other side
local function hitThisTurn(ctx, wantPhysical)
  local h = ctx.user.bwHit
  if not (h and h.turn == turnOf(ctx.battle) and h.by and h.by ~= ctx.user) then return nil end
  if wantPhysical ~= nil and h.physical ~= wantPhysical then return nil end
  return h
end
DEF.BW_COUNTER = F({ fixed = function(ctx)
  local h = hitThisTurn(ctx, true)
  return h and h.damage * 2 or nil
end })
DEF.BW_MIRROR_COAT = F({ fixed = function(ctx)
  local h = hitThisTurn(ctx, false)
  return h and h.damage * 2 or nil
end })
DEF.BW_METAL_BURST = F({ fixed = function(ctx)
  local h = hitThisTurn(ctx, nil)
  return h and math.floor(h.damage * 3 / 2) or nil
end })

-- --- power from the situation --------------------------------------------

local function ratioPower(ctx, rows, a, b)
  local r = a / math.max(1, b)
  for _, row in ipairs(rows) do if r >= row[1] then return row[2] end end
  return rows[#rows][2]
end

DEF.BW_REVERSAL = F({ power = function(ctx)
  local p = math.floor(48 * ctx.user.mon.hp / maxHP(ctx.user))
  if p <= 1 then return 200 elseif p <= 4 then return 150 elseif p <= 9 then return 100
  elseif p <= 16 then return 80 elseif p <= 32 then return 40 end
  return 20
end })
DEF.BW_RETURN = F({ power = function(ctx)
  return math.max(1, math.floor((ctx.user.mon.happiness or ctx.user.mon.friendship or 0) * 2 / 5))
end })
DEF.BW_FRUSTRATION = F({ power = function(ctx)
  return math.max(1, math.floor((255 - (ctx.user.mon.happiness or ctx.user.mon.friendship or 0)) * 2 / 5))
end })
DEF.BW_ERUPTION = F({ power = function(ctx)
  return math.max(1, math.floor((ctx.move.power or 150) * ctx.user.mon.hp / maxHP(ctx.user)))
end })
DEF.BW_WRING_OUT = F({ power = function(ctx)
  return math.max(1, math.floor(120 * ctx.target.mon.hp / maxHP(ctx.target)))
end })
DEF.BW_BRINE = F({ powerMultiplier = function(ctx)
  return ctx.target.mon.hp <= math.floor(maxHP(ctx.target) / 2) and 2 or 1
end })
DEF.BW_GYRO_BALL = F({ power = function(ctx)
  local TO = require("src.battle.TurnOrder")
  local a = TO.effectiveSpeed(ctx.user, ctx.battle) or 1
  local d = TO.effectiveSpeed(ctx.target, ctx.battle) or 1
  return math.min(150, 1 + math.floor(25 * d / math.max(1, a)))
end })
DEF.BW_ELECTRO_BALL = F({ power = function(ctx)
  local TO = require("src.battle.TurnOrder")
  local a = TO.effectiveSpeed(ctx.user, ctx.battle) or 1
  local d = TO.effectiveSpeed(ctx.target, ctx.battle) or 1
  return ratioPower(ctx, { { 4, 150 }, { 3, 120 }, { 2, 80 }, { 1, 60 }, { 0, 40 } }, a, d)
end })
DEF.BW_HEAVY_SLAM = F({ power = function(ctx)
  return ratioPower(ctx, { { 5, 120 }, { 4, 100 }, { 3, 80 }, { 2, 60 }, { 0, 40 } },
                    weightOf(ctx.user), weightOf(ctx.target))
end })
DEF.BW_LOW_KICK = F({ power = function(ctx)
  local w = weightOf(ctx.target) -- hectograms
  if w < 100 then return 20 elseif w < 250 then return 40 elseif w < 500 then return 60
  elseif w < 1000 then return 80 elseif w < 2000 then return 100 end
  return 120
end })
local function positiveStages(b)
  local n = 0
  for _, v in pairs(b.stages or {}) do if v > 0 then n = n + v end end
  return n
end
DEF.BW_STORED_POWER = F({ power = function(ctx) return 20 + 20 * positiveStages(ctx.user) end })
DEF.BW_PUNISHMENT = F({ power = function(ctx) return math.min(200, 60 + 20 * positiveStages(ctx.target)) end })
DEF.BW_TRUMP_CARD = F({ power = function(ctx)
  local pp = ctx.moveInst and ctx.moveInst.pp or 0
  if pp >= 4 then return 40 elseif pp == 3 then return 50 elseif pp == 2 then return 60
  elseif pp == 1 then return 80 end
  return 200
end })
DEF.BW_FACADE = F({ powerMultiplier = function(ctx)
  local s = ctx.user.mon.status
  return (s == "PSN" or s == "BRN" or s == "PAR") and 2 or 1
end })
DEF.BW_HEX = F({ powerMultiplier = function(ctx) return ctx.target.mon.status and 2 or 1 end })
DEF.BW_VENOSHOCK = F({ powerMultiplier = function(ctx) return ctx.target.mon.status == "PSN" and 2 or 1 end })
DEF.BW_ACROBATICS = F({ powerMultiplier = function(ctx) return itemOf(ctx.user) and 1 or 2 end })
DEF.BW_PAYBACK = F({ powerMultiplier = function(ctx)
  return ctx.target.bwMovedTurn == turnOf(ctx.battle) and 2 or 1
end })
DEF.BW_ASSURANCE = F({ powerMultiplier = function(ctx)
  local h = ctx.target.bwHit
  return (h and h.turn == turnOf(ctx.battle)) and 2 or 1
end })
DEF.BW_REVENGE = F({ powerMultiplier = function(ctx)
  local h = ctx.user.bwHit
  return (h and h.turn == turnOf(ctx.battle) and h.by == ctx.target) and 2 or 1
end })
DEF.BW_RETALIATE = F({ powerMultiplier = function(ctx)
  local s = sideState(ctx.battle, ctx.user)
  return (s.faintedTurn and s.faintedTurn == turnOf(ctx.battle) - 1) and 2 or 1
end })
DEF.BW_PURSUIT = F({ powerMultiplier = function(ctx) return ctx.target.switchingOut and 2 or 1 end })
DEF.BW_SMELLINGSALT = F({
  powerMultiplier = function(ctx) return ctx.target.mon.status == "PAR" and not ctx.target.substituteHP and 2 or 1 end,
  afterDamage = function(ctx, total)
    local t = ctx.target
    if total > 0 and t.mon.hp > 0 and t.mon.status == "PAR" and not t.substituteHP then
      t.mon.status = nil
      sayNow(ctx.battle, T.set(ctx.battle, 279, t))
    end
  end })
DEF.BW_WAKE_UP_SLAP = F({
  powerMultiplier = function(ctx) return ctx.target.mon.status == "SLP" and not ctx.target.substituteHP and 2 or 1 end,
  afterDamage = function(ctx, total)
    local t = ctx.target
    if total > 0 and t.mon.hp > 0 and t.mon.status == "SLP" and not t.substituteHP then
      t.mon.status, t.sleepTurns = nil, nil
      sayNow(ctx.battle, T.set(ctx.battle, "wokeUp", t))
    end
  end })
DEF.BW_ECHOED_VOICE = F({ power = function(ctx)
  local bw, turn = ctx.battle.bw, turnOf(ctx.battle)
  local e = bw.echo
  local n = 1
  if e and e.turn == turn then n = e.count
  elseif e and e.turn == turn - 1 then n = math.min(5, e.count + 1) end
  bw.echo = { turn = turn, count = n }
  return 40 * n
end })
local function rampPower(cap, curl)
  return F({
    power = function(ctx)
      local u = ctx.user
      if u.bwRampMove ~= ctx.move.id or u.bwRampTurn ~= turnOf(ctx.battle) - 1 then u.bwRampRun = 0 end
      local mult = 2 ^ math.min(cap, u.bwRampRun or 0)
      if curl and u.bwCurled then mult = mult * 2 end
      return (ctx.move.power or 10) * mult
    end,
    afterDamage = function(ctx, total)
      local u = ctx.user
      u.bwRampMove, u.bwRampTurn = ctx.move.id, turnOf(ctx.battle)
      u.bwRampRun = total > 0 and math.min(cap, (u.bwRampRun or 0) + 1) or 0
    end,
    onMiss = function(ctx) ctx.user.bwRampRun = 0 end,
  })
end
DEF.BW_FURY_CUTTER = rampPower(3)
DEF.BW_ROLLOUT = rampPower(4, true)
DEF.BW_TRIPLE_KICK = F({ hitCount = function() return 3 end, powerMultiplier = function() return 2 end })
DEF.BW_MAGNITUDE = F({ reaches = REACH_GROUND,
  power = function(ctx)
    local r = ctx.battle.rng(0, 99)
    local rows = { { 5, 10, 4 }, { 15, 30, 5 }, { 35, 50, 6 }, { 65, 70, 7 }, { 85, 90, 8 }, { 95, 110, 9 }, { 100, 150, 10 } }
    for _, row in ipairs(rows) do
      if r < row[1] then
        sayNow(ctx.battle, T.std(ctx.battle, T.STD.magnitude + row[3] - 4))
        return row[2]
      end
    end
    return 150
  end,
  powerMultiplier = function(ctx) return ctx.target.hiddenAs == "underground" and ctx.target.invulnerable and 2 or 1 end })
DEF.BW_PRESENT = F({ chooseDamage = function(ctx)
  local r = ctx.battle.rng(0, 99)
  local power = r < 40 and 40 or (r < 70 and 80 or (r < 80 and 120 or nil))
  if not power then
    local t = ctx.target
    if t.mon.hp >= maxHP(t) then return nil, T.set(ctx.battle, "hpFull", t) end
    heal(ctx.battle, t, maxHP(t) / 4)
    return nil, T.set(ctx.battle, "hpRestored", t)
  end
  return G5.damage(ctx, { power = function() return power end })
end })
DEF.BW_FALSE_SWIPE = F({ chooseDamage = function(ctx)
  local dmg, info = G5.damage(ctx, {})
  if dmg and dmg >= ctx.target.mon.hp and not ctx.target.substituteHP then
    dmg = math.max(0, ctx.target.mon.hp - 1)
  end
  return dmg, info
end })
DEF.BW_SPIT_UP = F({
  gate = function(ctx) return (ctx.user.stockpile or 0) > 0, failed(ctx.battle) end,
  power = function(ctx) return 100 * (ctx.user.stockpile or 1) end,
  afterDamage = function(ctx)
    local u = ctx.user
    local n = u.stockpile or 0
    u.stockpile = 0
    if n > 0 then
      for _, line in ipairs((G5.changeStats(ctx.battle, u, { { "defense", -(u.bwStockDef or 0) }, { "spdef", -(u.bwStockSpd or 0) } }, false))) do
        sayNow(ctx.battle, line)
      end
      u.bwStockDef, u.bwStockSpd = nil, nil
      sayNow(ctx.battle, T.set(ctx.battle, 724, u))
    end
  end })

-- HIDDEN POWER: type and power from the IVs (Gen 3..5's formula)
local HP_TYPES = { "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST", "STEEL",
                   "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON", "DARK" }
local function hiddenPower(mon)
  local iv = mon and mon.ivs
  if type(iv) ~= "table" then return "FIGHTING", 70 end
  local order = { iv.hp, iv.attack, iv.defense, iv.speed, iv.spatk, iv.spdef }
  local t, p = 0, 0
  for i, v in ipairs(order) do
    v = tonumber(v) or 0
    t = t + (v % 2) * 2 ^ (i - 1)
    p = p + (math.floor(v / 2) % 2) * 2 ^ (i - 1)
  end
  return HP_TYPES[math.floor(t * 15 / 63) + 1], math.floor(p * 40 / 63) + 30
end
G5.hiddenPower = hiddenPower
DEF.BW_HIDDEN_POWER = F({
  moveType = function(ctx) return (hiddenPower(ctx.user.mon)) end,
  power = function(ctx) local _, p = hiddenPower(ctx.user.mon) return p end })

local WEATHER_BALL = { RAIN = "WATER", SUN = "FIRE", SANDSTORM = "ROCK", HAIL = "ICE" }
DEF.BW_WEATHER_BALL = F({
  moveType = function(ctx) return WEATHER_BALL[Wx().current(ctx.battle) or ""] or ctx.move.type end,
  powerMultiplier = function(ctx) return Wx().current(ctx.battle) and 2 or 1 end })

DEF.BW_NATURAL_GIFT = F({
  gate = function(ctx)
    local id = itemOf(ctx.user)
    local d = itemDef(ctx.battle, id)
    if not (d and (d.naturalGiftPower or 0) > 0 and not ctx.user.bwEmbargo) then
      return false, failed(ctx.battle)
    end
    return true
  end,
  moveType = function(ctx)
    local d = itemDef(ctx.battle, itemOf(ctx.user))
    return d and G5.TYPES[d.naturalGiftType] or ctx.move.type
  end,
  power = function(ctx)
    local d = itemDef(ctx.battle, itemOf(ctx.user))
    return d and d.naturalGiftPower or 1
  end,
  afterDamage = function(ctx)
    ctx.user.lastConsumedItem = itemOf(ctx.user)
    ctx.user.mon.item = nil
  end })

DEF.BW_FLING = F({
  gate = function(ctx)
    local d = itemDef(ctx.battle, itemOf(ctx.user))
    if not (d and (d.flingPower or 0) > 0) or ctx.user.bwEmbargo then return false, failed(ctx.battle) end
    sayNow(ctx.battle, T.set(ctx.battle, "flung", ctx.user, { nil, d.name }))
    return true
  end,
  power = function(ctx)
    local d = itemDef(ctx.battle, itemOf(ctx.user))
    return d and d.flingPower or 1
  end,
  afterDamage = function(ctx)
    ctx.user.lastConsumedItem = itemOf(ctx.user)
    ctx.user.mon.item = nil
  end })

-- PSYSHOCK, PSYSTRIKE, SECRET SWORD: a special hit on the physical Defense
DEF.BW_PSYSHOCK = F({ defender = function(ctx)
  local t = ctx.target
  local stats, stages = {}, {}
  for k, v in pairs(t.curStats or {}) do stats[k] = v end
  for k, v in pairs(t.stages or {}) do stages[k] = v end
  stats.spdef, stages.spdef = stats.defense, stages.defense
  local proxy = setmetatable({ curStats = stats, stages = stages }, { __index = t })
  -- a screen guards the stat the move is hitting
  proxy.lightScreen = t.reflect
  return proxy
end })
-- FOUL PLAY: the target's own Attack
DEF.BW_FOUL_PLAY = F({ attacker = function(ctx)
  local u, t = ctx.user, ctx.target
  local stats, stages = {}, {}
  for k, v in pairs(u.curStats or {}) do stats[k] = v end
  for k, v in pairs(u.stages or {}) do stages[k] = v end
  stats.attack = t.curStats and t.curStats.attack or stats.attack
  stages.attack = t.stages and t.stages.attack or 0
  return setmetatable({ curStats = stats, stages = stages }, { __index = u })
end })
-- CHIP AWAY, SACRED SWORD: the target's defensive stages do not count
DEF.BW_CHIP_AWAY = F({ defender = function(ctx)
  local t = ctx.target
  local stages = {}
  for k, v in pairs(t.stages or {}) do stages[k] = v end
  stages.defense, stages.spdef, stages.evasion = 0, 0, 0
  return setmetatable({ stages = stages }, { __index = t })
end })
DEF.BW_SYNCHRONOISE = F({ gate = function(ctx)
  for _, a in ipairs(ctx.user.curTypes or {}) do
    if hasType(ctx.target, a) then return true end
  end
  return false, T.set(ctx.battle, "notAffected", ctx.target)
end })
DEF.BW_STRUGGLE = F({ moveType = function() return "TYPELESS" end })

-- --- the hidden-target family ---------------------------------------------

DEF.BW_GUST = F({ reaches = REACH_AIR,
  powerMultiplier = function(ctx) return (ctx.target.invulnerable and ctx.target.hiddenAs == "air") and 2 or 1 end })
DEF.BW_EARTHQUAKE = F({ reaches = REACH_GROUND,
  powerMultiplier = function(ctx) return (ctx.target.invulnerable and ctx.target.hiddenAs == "underground") and 2 or 1 end })
DEF.BW_SURF = F({ reaches = REACH_WATER,
  powerMultiplier = function(ctx) return (ctx.target.invulnerable and ctx.target.hiddenAs == "underwater") and 2 or 1 end })
DEF.BW_SKY_UPPERCUT = F({ reaches = REACH_AIR })
DEF.BW_STOMP = F({ powerMultiplier = function(ctx) return ctx.target.bwMinimized and 2 or 1 end })

-- THUNDER, HURRICANE (rain: never miss, sun: 50%) and BLIZZARD (hail: never
-- miss): the accuracy is rolled here, so the record never misses on its own
local function weatherAccuracy(sureIn, halfIn)
  return function(ctx)
    local battle = ctx.battle
    local w = Wx().current(battle)
    if w and sureIn[w] then return true end
    local raw
    if w and halfIn and halfIn[w] then raw = math.floor(50 * 255 / 100) end
    if not battle:accuracyRoll(ctx.move, ctx.user, ctx.target, raw) then
      return false, T.set(battle, "avoided", ctx.target)
    end
    return true
  end
end
DEF.BW_THUNDER = F({ reaches = REACH_AIR, neverMiss = true,
  gate = weatherAccuracy({ RAIN = true }, { SUN = true }) })
DEF.BW_BLIZZARD = F({ neverMiss = true, gate = weatherAccuracy({ HAIL = true }) })

DEF.BW_SOLARBEAM = F({ charge = { skipInSun = true },
  powerMultiplier = function(ctx)
    local w = Wx().current(ctx.battle)
    return (w == "RAIN" or w == "SANDSTORM" or w == "HAIL") and 0.5 or 1
  end })
DEF.BW_CHARGE = F({ charge = {} })
DEF.BW_FLY = F({ charge = { invulnerable = true }, reaches = {} })
DEF.BW_SHADOW_FORCE = F({ charge = { invulnerable = true },
  afterDamage = function(ctx, total)
    if ctx.target.protecting then
      ctx.target.protecting = nil
      sayNow(ctx.battle, T.set(ctx.battle, "brokeProtection", ctx.target))
    end
  end })
-- SKULL BASH raises Defense on the turn it charges, which the engine's own
-- charge turn has no seam for: it charges itself
DEF.BW_SKULL_BASH = F({ perform = function(ctx, rec)
  local battle, user = ctx.battle, ctx.user
  if not user.bwSkullBash then
    user.bwSkullBash = true
    user.charging, user.chargeReady = ctx.moveInst, true
    battle:cancelMoveAnim()
    sayNow(battle, Strings(G5.CHARGE[145][1], (user.isPlayer and "" or "Enemy ") .. user.name))
    for _, line in ipairs((G5.changeStats(battle, user, { { "defense", 1 } }, false))) do sayNow(battle, line) end
    return
  end
  user.bwSkullBash = nil
  local plain = {}
  for k, v in pairs(rec) do if k ~= "perform" then plain[k] = v end end
  require("src.battle.EffectRegistry").runDamaging(battle, ctx, plain)
end })

DEF.BW_RECHARGE = F({ afterDamage = function(ctx, total)
  if total > 0 then ctx.user.mustRecharge = true end
end })

-- the user faints whatever happens (Gen 5: no Defense halving any more)
DEF.BW_EXPLODE = F({
  gate = function(ctx)
    if Abil().dampens({ ctx.battle.player, ctx.battle.enemy }) then
      return false, failed(ctx.battle)
    end
    return true
  end,
  onMiss = function(ctx) ctx.battle:selfDestruct(ctx.user) end,
  afterDamage = function(ctx) ctx.battle:selfDestruct(ctx.user) end })

DEF.BW_DREAM_EATER = F({ gate = function(ctx)
  if ctx.target.mon.status ~= "SLP" or ctx.target.substituteHP then
    return false, T.set(ctx.battle, "notAffected", ctx.target)
  end
  return true
end })

DEF.BW_JUMP_KICK = F({
  gate = function(ctx)
    if (ctx.battle.bw.field.gravity or 0) > 0 then return false, failed(ctx.battle) end
    return true
  end,
  onMiss = function(ctx)
    local user = ctx.user
    sayNow(ctx.battle, T.set(ctx.battle, "crashed", user))
    hurt(ctx.battle, user, math.floor(maxHP(user) / 2))
  end })

DEF.BW_SNORE = F({ gate = function(ctx)
  if ctx.user.mon.status ~= "SLP" then return false, failed(ctx.battle) end
  return true
end })

DEF.BW_FAKE_OUT = F({ gate = function(ctx)
  if (ctx.user.turnsOut or 1) > 1 then return false, failed(ctx.battle) end
  return true
end })

DEF.BW_FOCUS_PUNCH = F({ gate = function(ctx)
  local h = ctx.user.bwHit
  if (h and h.turn == turnOf(ctx.battle)) or ctx.user.hurtThisTurn then
    return false, T.set(ctx.battle, "lostFocus", ctx.user)
  end
  return true
end })

DEF.BW_SUCKER_PUNCH = F({ gate = function(ctx)
  if ctx.target.bwMovedTurn == turnOf(ctx.battle) then return false, failed(ctx.battle) end
  return true
end })

DEF.BW_LAST_RESORT = F({ gate = function(ctx)
  local used, n = ctx.user.bwUsedMoves or {}, 0
  for _, m in ipairs(ctx.user.curMoves or {}) do
    n = n + 1
    if m.id ~= ctx.move.id and not used[m.id] then return false, failed(ctx.battle) end
  end
  if n < 2 then return false, failed(ctx.battle) end
  return true
end })

DEF.BW_FEINT = F({ beforeAccuracy = function(ctx)
  if ctx.target.protecting then
    ctx.target.protecting = nil
    sayNow(ctx.battle, T.set(ctx.battle, "fellForFeint", ctx.target))
  end
end })

DEF.BW_PAY_DAY = F({ afterDamage = function(ctx, total)
  if total <= 0 then return end
  local battle = ctx.battle
  battle.payDay = (battle.payDay or 0) + 5 * (ctx.user.mon.level or 1)
  sayNow(battle, T.std(battle, "payDay"))
end })

DEF.BW_UPROAR = F({ afterDamage = function(ctx, total)
  local u = ctx.user
  if total > 0 and not u.uproarTurns then
    u.uproarTurns = 3
    sayNow(ctx.battle, T.set(ctx.battle, "uproar", u))
    for _, b in ipairs(activeList(ctx.battle)) do
      if b.mon.status == "SLP" then
        b.mon.status = nil
        sayNow(ctx.battle, T.set(ctx.battle, "wokeUp", b))
      end
    end
  end
end })

DEF.BW_RAGE = F({ afterDamage = function(ctx) ctx.user.bwRage = true end })

DEF.BW_THRASH = F({ afterDamage = function(ctx)
  local fn = engineFull("THRASH_PETAL_DANCE_EFFECT").afterDamage
  if fn then fn(ctx) end
end })

-- BIDE: two turns of taking it, then twice back (BattleState:continueBide)
DEF.BW_BIDE = F({ perform = function(ctx)
  local user = ctx.user
  user.bideTurns, user.bideDamage = 2, 0
  ctx.battle:cancelMoveAnim()
  sayNow(ctx.battle, T.set(ctx.battle, "storingEnergy", user))
end })

DEF.BW_BEAT_UP = F({
  hitCount = function(ctx)
    local party = ctx.user.isPlayer and ctx.battle.game and ctx.battle.game.save
                  and (ctx.battle.playerParty or ctx.battle.game.save.party) or ctx.battle.enemyParty
    local n = 0
    for _, mon in ipairs(party or {}) do
      if (mon.hp or 0) > 0 and not mon.status then n = n + 1 end
    end
    return math.max(1, n)
  end,
  power = function(ctx)
    local base = ctx.user.def and ctx.user.def.baseStats and ctx.user.def.baseStats.attack or 50
    return math.floor(base / 10) + 5
  end })

DEF.BW_FUTURE_SIGHT = F({ perform = function(ctx)
  local battle, target = ctx.battle, ctx.target
  local side = battle.sideOf and battle:sideOf(target)
  if not side or side.futureSight then
    battle:cancelMoveAnim()
    sayNow(battle, failed(battle))
    return
  end
  local dmg = G5.damage(ctx, {})
  side.futureSight = { turns = 3, damage = math.max(1, dmg or 1), move = ctx.move.name }
  sayNow(battle, T.set(battle, ctx.move.bwEffect == 148 and ctx.move.id == 353 and "doomDesire" or "foresaw", ctx.user))
end })

-- --- binding ---------------------------------------------------------------

local BIND_LINE = { [20] = "squeezed", [35] = "wrapped", [128] = "clamped",
                    [83] = "trappedFire", [250] = "trappedVortex", [328] = "trappedSandTomb",
                    [463] = "trappedMagma" }
local function bindAfter(ctx, total)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  if total <= 0 or target.mon.hp <= 0 or target.bwBound or target.substituteHP then return end
  target.bwBound = { turns = battle.rng(4, 5), by = user, name = ctx.move.name }
  if not target.trapped then target.trapped, target.bwTrappedByBind = true, true end
  local key = BIND_LINE[ctx.move.id] or "wrapped"
  if T.PAIR[key] then
    sayNow(battle, T.pair(battle, key, target, user))
  else
    sayNow(battle, T.set(battle, key, target))
  end
end
DEF.BW_BIND = F({ afterDamage = bindAfter })
DEF.BW_WHIRLPOOL = F({ reaches = REACH_WATER, afterDamage = bindAfter,
  powerMultiplier = function(ctx) return (ctx.target.invulnerable and ctx.target.hiddenAs == "underwater") and 2 or 1 end })

DEF.BW_RAPID_SPIN = F({ afterDamage = function(ctx, total)
  local battle, u = ctx.battle, ctx.user
  if total <= 0 or u.mon.hp <= 0 then return end
  if u.bwBound then releaseBind(battle, u) end
  if u.leechSeeded then u.leechSeeded = nil end
  local s = sideState(battle, u)
  if s.spikes then s.spikes = nil sayNow(battle, T.team(battle, "spikesGone", u)) end
  if s.toxicSpikes then s.toxicSpikes = nil sayNow(battle, T.team(battle, "toxicSpikesGone", u)) end
  if s.stealthRock then s.stealthRock = nil sayNow(battle, T.team(battle, "stealthRockGone", u)) end
end })

DEF.BW_BRICK_BREAK = F({ beforeAccuracy = function(ctx)
  local battle, t = ctx.battle, ctx.target
  local s = sideState(battle, t)
  if (s.reflect or 0) > 0 or (s.lightScreen or 0) > 0 or t.reflect or t.lightScreen then
    s.reflect, s.lightScreen = nil, nil
    t.reflect, t.lightScreen = nil, nil
    sayNow(battle, Strings("The wall shattered!"))
  end
end })

-- --- items -------------------------------------------------------------------

local function stealItem(ctx, total)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  local id = itemOf(target)
  if total <= 0 or not id or itemOf(user) or target.substituteHP or ctx.brokeSub
     or Abil().keepsItem(target) or user.mon.hp <= 0 then return end
  target.mon.item, target.mon.heldItem = nil, nil
  user.mon.item = id
  local d = itemDef(battle, id)
  sayNow(battle, T.pair(battle, "stole", user, target, { nil, nil, d and d.name or "item" }))
end
DEF.BW_THIEF = F({ afterDamage = stealItem })
DEF.BW_KNOCK_OFF = F({ afterDamage = function(ctx, total)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  local id = itemOf(target)
  if total <= 0 or not id or target.substituteHP or ctx.brokeSub or Abil().keepsItem(target) then return end
  target.mon.item, target.mon.heldItem = nil, nil
  target.knockedOffItem = id
  local d = itemDef(battle, id)
  sayNow(battle, T.pair(battle, "knockedOff", user, target, { nil, nil, d and d.name or "item" }))
end })
DEF.BW_PLUCK = F({ afterDamage = function(ctx, total)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  local id = itemOf(target)
  if total <= 0 or not id or not isBerry(battle, id) or target.substituteHP or ctx.brokeSub then return end
  target.mon.item = nil
  local d = itemDef(battle, id)
  sayNow(battle, T.set(battle, "ateBerry", user, { nil, d and d.name or "Berry" }))
  local name = d and d.name or ""
  if name == "Oran Berry" then heal(battle, user, 10)
  elseif name == "Sitrus Berry" then heal(battle, user, maxHP(user) / 4) end
end })
DEF.BW_INCINERATE = F({ afterDamage = function(ctx, total)
  local battle, target = ctx.battle, ctx.target
  local id = itemOf(target)
  if total <= 0 or not id or not isBerry(battle, id) or target.substituteHP then return end
  target.mon.item = nil
  local d = itemDef(battle, id)
  sayNow(battle, T.set(battle, "burntUp", target, { nil, d and d.name or "Berry" }))
end })
DEF.BW_SMACK_DOWN = F({ reaches = REACH_AIR, afterDamage = function(ctx, total)
  local battle, t = ctx.battle, ctx.target
  if total <= 0 or t.mon.hp <= 0 then return end
  local wasUp = (t.invulnerable and t.hiddenAs == "air") or hasType(t, "FLYING")
                or abilityOf(t) == "LEVITATE" or t.bwMagnetRise or t.bwTelekinesis
  if t.invulnerable and t.hiddenAs == "air" then
    t.charging, t.chargeReady, t.invulnerable, t.hiddenAs = nil, nil, nil, nil
  end
  t.bwMagnetRise, t.bwTelekinesis = nil, nil
  t.bwGrounded = true
  if wasUp then sayNow(battle, T.set(battle, "fellDown", t)) end
end })
DEF.BW_SECRET_POWER = F({ run = function(ctx)
  if roll(ctx.battle, Abil().secondaryOdds(ctx.user, ctx.target, 30)) then
    return G5.inflict(ctx, ctx.target, "PAR", { secondary = true })
  end
  return {}
end })
DEF.BW_TRI_ATTACK = F({ run = function(ctx)
  if roll(ctx.battle, Abil().secondaryOdds(ctx.user, ctx.target, ctx.move.conditionChance or 20)) then
    local pick = ({ "BRN", "FRZ", "PAR" })[ctx.battle.rng(1, 3)]
    return G5.inflict(ctx, ctx.target, pick, { secondary = true })
  end
  return {}
end })
DEF.BW_POISON_FANG = F({ toxic = true })
DEF.BW_CHATTER = F({ noCondition = true, run = function(ctx)
  local sp = ctx.user.mon and ctx.user.mon.species
  if sp == 441 and roll(ctx.battle, Abil().secondaryOdds(ctx.user, ctx.target, 10)) then
    return G5.confuse(ctx, ctx.target, true)
  end
  return {}
end })
DEF.BW_FLAME_BURST = F({ afterDamage = function(ctx, total)
  local battle = ctx.battle
  if total <= 0 or not (battle.isDouble and battle:isDouble()) then return end
  local partner = battle.partnerOf and battle:partnerOf(ctx.target)
  if partner and partner.mon and partner.mon.hp > 0 then
    sayNow(battle, T.set(battle, 1105, partner))
    hurt(battle, partner, math.floor(maxHP(partner) / 16))
  end
end })
DEF.BW_CLEAR_SMOG = F({ afterDamage = function(ctx, total)
  local t = ctx.target
  if total > 0 and t.mon.hp > 0 and not t.substituteHP and next(t.stages or {}) then
    t.stages = {}
    sayNow(ctx.battle, T.set(ctx.battle, "statsRemoved", t))
  end
end })

-- --- switching ---------------------------------------------------------------

local function benchOf(battle, b)
  local out = {}
  if b.isPlayer then
    local party = battle.game and battle.game.save and (battle.playerParty or battle.game.save.party) or {}
    for _, mon in ipairs(party) do
      if mon ~= b.mon and (mon.hp or 0) > 0 and not mon.isEgg and not mon.egg then
        local onField = false
        for _, a in ipairs(activeList(battle)) do if a.mon == mon then onField = true end end
        if not onField then out[#out + 1] = mon end
      end
    end
  else
    for i, mon in ipairs(battle.enemyParty or {}) do
      if mon ~= b.mon and (mon.hp or 0) > 0 then
        local onField = false
        for _, a in ipairs(activeList(battle)) do if a.mon == mon then onField = true end end
        if not onField then out[#out + 1] = { index = i, mon = mon } end
      end
    end
  end
  return out
end
G5.benchOf = benchOf

-- the foe's side swaps `index` in through the trainer's own switch path;
-- `dragged` rewrites its two lines as the cartridge's "was dragged out"
local function switchEnemy(battle, index, dragged, carry)
  local before = #battle.queue
  local mark = {}
  for i, item in ipairs(battle.queue) do mark[item] = true end
  battle:executeAction(battle.enemy, battle.player, { special = "aiSwitch", index = index })
  local incoming = battle.enemy
  if carry and incoming then
    incoming.stages = carry.stages or incoming.stages
    incoming.confusedTurns = carry.confusedTurns
    incoming.substituteHP = carry.substituteHP
    incoming.leechSeeded = carry.leechSeeded
  end
  if dragged then
    for i = #battle.queue, 1, -1 do
      local item = battle.queue[i]
      if not mark[item] and type(item.text) == "string" then
        if item.text:find("with-\ndrew", 1, true) then
          table.remove(battle.queue, i)
          if battle.nextInsert and i <= battle.nextInsert then battle.nextInsert = battle.nextInsert - 1 end
        elseif item.text:find("sent\nout", 1, true) then
          item.text = T.set(battle, "draggedOut", incoming)
        end
      end
    end
  end
  return #battle.queue >= before
end

-- the player's side: a forced switch picks at random, a chosen one asks
local function switchPlayer(battle, mon, carry)
  local pos = battle.POS and battle.POS.PLAYER_LEFT or 0
  if carry then battle.player.batonPass = carry end
  battle:switchPlayerInto(battle.player and battle.player.position or pos, mon)
end

-- ROAR / WHIRLWIND / DRAGON TAIL / CIRCLE THROW
function G5.forceOut(ctx, quietFail)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  if Abil().refusesPhasing(target) then
    return { T.set(battle, 454, target) }
  end
  if target.ingrained then return { T.set(battle, "anchoredRoots", target) } end
  if battle.kind == "wild" and not (battle.isDouble and battle:isDouble()) then
    if (user.mon.level or 1) < (target.mon.level or 1) then
      return quietFail and {} or { failed(battle) }
    end
    battle.result = "run"
    battle.afterQueue = "finish"
    return { T.set(battle, "fled", target) }
  end
  if battle.isDouble and battle:isDouble() then return quietFail and {} or { failed(battle) } end
  local bench = benchOf(battle, target)
  if #bench == 0 then return quietFail and {} or { failed(battle) } end
  local pick = bench[battle.rng(1, #bench)]
  if target.isPlayer then
    switchPlayer(battle, pick)
  else
    switchEnemy(battle, pick.index, true)
  end
  return {}
end

-- U-TURN / VOLT SWITCH / BATON PASS: the user leaves
function G5.switchOut(ctx, baton)
  local battle, user = ctx.battle, ctx.user
  if battle.isDouble and battle:isDouble() then return false end
  local bench = benchOf(battle, user)
  if #bench == 0 then return false end
  local carry = baton and { stages = user.stages, confusedTurns = user.confusedTurns,
                            substituteHP = user.substituteHP, leechSeeded = user.leechSeeded,
                            perishTurns = user.perishTurns } or nil
  if user.isPlayer then
    if battle.bwAutoSwitch or not battle.game or not battle.game.stack then
      switchPlayer(battle, bench[1], carry)
      return true
    end
    battle:uiNext(function()
      local Gen4Battle = require("src.battle.Gen4Battle")
      return battle:buildScreen(Gen4Battle.partyScreenId and Gen4Battle.partyScreenId(battle) or "PartyMenu", {
        battle = battle, forceSwitch = true,
        onSwitch = function(mon)
          if (mon.hp or 0) <= 0 or mon == user.mon then mon = bench[1] end
          battle.nextInsert = 0
          switchPlayer(battle, mon, carry)
        end,
      })
    end)
    return true
  end
  -- the trainer's AI takes the first able one in party order
  table.sort(bench, function(a, b) return a.index < b.index end)
  switchEnemy(battle, bench[1].index, false, carry)
  return true
end

DEF.BW_FORCE_SWITCH = P({ foe = true, run = function(ctx)
  local out = G5.forceOut(ctx)
  if #out > 0 and out[1] == failed(ctx.battle) then ctx.battle:cancelMoveAnim() end
  return out
end })
DEF.BW_DRAGON_TAIL = F({ afterDamage = function(ctx, total)
  if total > 0 and ctx.target.mon.hp > 0 and not ctx.target.substituteHP and ctx.user.mon.hp > 0 then
    for _, line in ipairs(G5.forceOut(ctx, true)) do sayNow(ctx.battle, line) end
  end
end })
DEF.BW_U_TURN = F({ afterDamage = function(ctx, total)
  if total > 0 and ctx.user.mon.hp > 0 then G5.switchOut(ctx, false) end
end })
DEF.BW_BATON_PASS = P({ run = function(ctx)
  if not G5.switchOut(ctx, true) then return fail(ctx) end
  return {}
end })
DEF.BW_TELEPORT = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  if battle.kind ~= "wild" or user.trapped or user.bwBound then return fail(ctx) end
  battle.result = "run"
  battle.afterQueue = "finish"
  return { T.set(battle, "fled", user) }
end })

-- --- protection ----------------------------------------------------------

local function protection(kind)
  return P({ run = function(ctx)
    local battle, user = ctx.battle, ctx.user
    local turn = turnOf(battle)
    local chain = (user.bwProtectTurn == turn - 1) and (user.bwProtectChain or 0) or 0
    if chain > 0 and battle.rng(1, 2 ^ math.min(chain, 8)) ~= 1 then
      user.bwProtectChain, user.bwProtectTurn = 0, nil
      return fail(ctx)
    end
    -- the last to move this turn has nothing left to protect from
    local foesDone = true
    for _, b in ipairs(activeList(battle)) do
      if sideIndex(b) ~= sideIndex(user) and b.bwMovedTurn ~= turn then foesDone = false end
    end
    if foesDone and kind ~= "endure" and not (battle.isDouble and battle:isDouble()) then
      user.bwProtectChain, user.bwProtectTurn = 0, nil
      return fail(ctx)
    end
    user.bwProtectChain, user.bwProtectTurn = chain + 1, turn
    if kind == "protect" then
      user.protecting = true
      return { T.set(battle, "protected", user) }
    elseif kind == "endure" then
      user.enduring = true
      return { T.set(battle, "braced", user) }
    end
    local s = sideState(battle, user)
    s[kind] = turn
    return { T.team(battle, kind, user) }
  end })
end
DEF.BW_PROTECT = protection("protect")
DEF.BW_ENDURE = protection("endure")
DEF.BW_QUICK_GUARD = protection("quickGuard")
DEF.BW_WIDE_GUARD = protection("wideGuard")

-- --- the side and the field ------------------------------------------------

local function sideTimer(key, turns, line)
  return P({ run = function(ctx)
    local battle, user = ctx.battle, ctx.user
    local s = sideState(battle, user)
    if (s[key] or 0) > 0 then return fail(ctx) end
    s[key] = turns
    G5.sync(battle)
    return { T.team(battle, line, user) }
  end })
end
DEF.BW_REFLECT = sideTimer("reflect", 5, "reflect")
DEF.BW_LIGHT_SCREEN = sideTimer("lightScreen", 5, "lightScreen")
DEF.BW_MIST = sideTimer("mist", 5, "mist")
DEF.BW_TAILWIND = sideTimer("tailwind", 4, "tailwind")
DEF.BW_LUCKY_CHANT = sideTimer("luckyChant", 5, "luckyChant")
DEF.BW_SAFEGUARD = P({ run = function(ctx)
  local user = ctx.user
  if user.safeguardTurns then return fail(ctx) end
  user.safeguardTurns = 5
  return { T.team(ctx.battle, "safeguard", user) }
end })

local function hazard(key, max, line)
  return P({ run = function(ctx)
    local battle, target = ctx.battle, ctx.target
    local s = sideState(battle, target)
    local n = s[key] == true and 1 or (s[key] or 0)
    if n >= max then return fail(ctx) end
    s[key] = max == 1 and true or n + 1
    return { T.team(battle, line, target) }
  end })
end
DEF.BW_SPIKES = hazard("spikes", 3, "spikes")
DEF.BW_TOXIC_SPIKES = hazard("toxicSpikes", 2, "toxicSpikes")
DEF.BW_STEALTH_ROCK = hazard("stealthRock", 1, "stealthRock")

DEF.BW_DEFOG = P({ foe = true, run = function(ctx)
  local battle, target = ctx.battle, ctx.target
  local out = {}
  local blocked = foeStatBlocked(ctx, target)
  if blocked then out[#out + 1] = blocked
  else append(out, (G5.changeStats(battle, target, { { "evasion", -1 } }, true))) end
  local s = sideState(battle, target)
  for key, line in pairs({ reflect = "reflectEnded", lightScreen = "lightScreenEnded",
                           mist = "mistEnded", spikes = "spikesGone", toxicSpikes = "toxicSpikesGone",
                           stealthRock = "stealthRockGone" }) do
    if s[key] then s[key] = nil out[#out + 1] = T.team(battle, line, target) end
  end
  target.safeguardTurns = nil
  G5.sync(battle)
  return out
end })

DEF.BW_HAZE = P({ run = function(ctx)
  for _, b in ipairs(activeList(ctx.battle)) do b.stages = {} end
  return { T.std(ctx.battle, "statsEliminated") }
end })

local function fieldTimer(key, turns, line)
  return P({ run = function(ctx)
    local f = ctx.battle.bw.field
    if (f[key] or 0) > 0 then
      if key == "gravity" then return fail(ctx) end
      f[key] = nil
      return { T.std(ctx.battle, line .. "Ended") }
    end
    f[key] = turns
    return { T.std(ctx.battle, line) }
  end })
end
DEF.BW_GRAVITY = fieldTimer("gravity", 5, "gravity")
DEF.BW_GRAVITY.status, DEF.BW_GRAVITY.note = "partial", "timer, text, Jump Kick / Magnet Rise refused; no accuracy boost, Flying types not grounded"
DEF.BW_WONDER_ROOM = fieldTimer("wonderRoom", 5, "wonderRoom")
DEF.BW_WONDER_ROOM.status, DEF.BW_WONDER_ROOM.note = "partial", "timer and text; Defense / Sp. Def are not swapped"
DEF.BW_MAGIC_ROOM = fieldTimer("magicRoom", 5, "magicRoom")
DEF.BW_MAGIC_ROOM.status, DEF.BW_MAGIC_ROOM.note = "partial", "timer and text; held items keep working"
DEF.BW_TRICK_ROOM = P({ run = function(ctx)
  local f = ctx.battle.field
  if (f.trickRoom or 0) > 0 then
    f.trickRoom = 0
    return { T.std(ctx.battle, "trickRoomEnded") }
  end
  f.trickRoom = 5
  return { T.set(ctx.battle, "trickRoom", ctx.user) }
end })

local function weather(name, line)
  return P({ run = function(ctx)
    local W = Wx()
    if W.current(ctx.battle) == W[name] then return fail(ctx) end
    W.start(ctx.battle, W[name])
    return { T.std(ctx.battle, line) }
  end })
end
DEF.BW_RAIN_DANCE = weather("RAIN", "rain")
DEF.BW_SUNNY_DAY = weather("SUN", "sun")
DEF.BW_SANDSTORM = weather("SANDSTORM", "sandstorm")
DEF.BW_HAIL = weather("HAIL", "hail")

DEF.BW_SPORT = P({ run = function(ctx)
  local f = ctx.battle.field
  local mud = ctx.move.bwEffect == 201
  local key = mud and "mudSport" or "waterSport"
  if f[key] then return fail(ctx) end
  f[key] = mud and "ELECTRIC" or "FIRE"
  return { T.std(ctx.battle, mud and "mudSport" or "waterSport") }
end })

-- --- the user's own conditions --------------------------------------------

DEF.BW_FOCUS_ENERGY = P({ run = function(ctx)
  if ctx.user.focusEnergy then return fail(ctx) end
  ctx.user.focusEnergy = true
  return { T.set(ctx.battle, "pumped", ctx.user) }
end })
DEF.BW_SUBSTITUTE = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  if user.substituteHP then return fail(ctx, T.set(battle, "alreadySubstitute", user)) end
  local cost = math.floor(maxHP(user) / 4)
  if user.mon.hp <= cost or cost < 1 then return fail(ctx, T.std(battle, "tooWeakSub")) end
  user.mon.hp = user.mon.hp - cost
  user.substituteHP = cost
  battle:drainNext(user, user.mon.hp)
  return { T.set(battle, "substitute", user) }
end })
DEF.BW_REST = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  if user.mon.hp >= maxHP(user) then return fail(ctx, T.set(battle, "hpFull", user)) end
  if Abil().refusesStatus(user, "SLP") or user.bwHealBlock then return fail(ctx) end
  for _, b in ipairs(activeList(battle)) do if b.uproarTurns then return fail(ctx) end end
  user.mon.hp = maxHP(user)
  user.mon.status = "SLP"
  user.sleepTurns = 2
  user.toxicCounter = nil
  battle:drainNext(user, user.mon.hp)
  return { T.set(battle, "rested", user) }
end })
DEF.BW_BELLY_DRUM = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  local cost = math.floor(maxHP(user) / 2)
  if user.mon.hp <= cost or (user.stages.attack or 0) >= 6 then return fail(ctx) end
  user.mon.hp = user.mon.hp - cost
  battle:drainNext(user, user.mon.hp)
  user.stages.attack = 6
  return { T.set(battle, "bellyDrum", user) }
end })
DEF.BW_STOCKPILE = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  local n = user.stockpile or 0
  if n >= 3 then return fail(ctx) end
  user.stockpile = n + 1
  local out = { T.set(battle, "stockpiled", user, { count = user.stockpile }) }
  local before = { user.stages.defense or 0, user.stages.spdef or 0 }
  append(out, (G5.changeStats(battle, user, { { "defense", 1 }, { "spdef", 1 } }, false)))
  user.bwStockDef = (user.bwStockDef or 0) + (user.stages.defense or 0) - before[1]
  user.bwStockSpd = (user.bwStockSpd or 0) + (user.stages.spdef or 0) - before[2]
  return out
end })
DEF.BW_SWALLOW = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  local n = user.stockpile or 0
  if n <= 0 or user.mon.hp >= maxHP(user) then return fail(ctx) end
  heal(battle, user, maxHP(user) * ({ 0.25, 0.5, 1 })[math.min(3, n)])
  user.stockpile = 0
  local out = { T.set(battle, "hpRestored", user) }
  append(out, (G5.changeStats(battle, user, { { "defense", -(user.bwStockDef or 0) }, { "spdef", -(user.bwStockSpd or 0) } }, false)))
  user.bwStockDef, user.bwStockSpd = nil, nil
  return out
end })
DEF.BW_AQUA_RING = P({ run = function(ctx)
  if ctx.user.bwAquaRing then return fail(ctx) end
  ctx.user.bwAquaRing = true
  return { T.set(ctx.battle, "aquaRing", ctx.user) }
end })
DEF.BW_MAGNET_RISE = P({ run = function(ctx)
  local u = ctx.user
  if u.bwMagnetRise or u.bwGrounded or (ctx.battle.bw.field.gravity or 0) > 0 then return fail(ctx) end
  u.bwMagnetRise = 5
  return { T.set(ctx.battle, "magnetRise", u) }
end })
DEF.BW_MINIMIZE = DEF.BW_STAT_SELF
DEF.BW_ACUPRESSURE = P({ run = function(ctx)
  local u = ctx.user
  local pool = {}
  for _, s in ipairs({ "attack", "defense", "spatk", "spdef", "speed", "accuracy", "evasion" }) do
    if (u.stages[s] or 0) < 6 then pool[#pool + 1] = s end
  end
  if #pool == 0 then return fail(ctx) end
  return (G5.changeStats(ctx.battle, u, { { pool[ctx.battle.rng(1, #pool)], 2 } }, false))
end })
DEF.BW_SHELL_SMASH = P({ run = function(ctx)
  local out, any = G5.changeStats(ctx.battle, ctx.user,
    { { "defense", -1 }, { "spdef", -1 }, { "attack", 2 }, { "spatk", 2 }, { "speed", 2 } }, false)
  return out
end })
DEF.BW_CURSE = P({ run = function(ctx)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  if hasType(user, "GHOST") then
    if target.cursed or target.substituteHP then return fail(ctx) end
    target.cursed = true
    local out = { T.pair(battle, "cursed", user, target) }
    hurt(battle, user, math.floor(maxHP(user) / 2))
    return out
  end
  return (G5.changeStats(battle, user, { { "speed", -1 }, { "attack", 1 }, { "defense", 1 } }, false))
end })
DEF.BW_DESTINY_BOND = P({ run = enginePrimary("DESTINY_BOND_EFFECT") })
DEF.BW_GRUDGE = P({ run = enginePrimary("GRUDGE_EFFECT") })
DEF.BW_INGRAIN = P({ run = enginePrimary("INGRAIN_EFFECT") })
DEF.BW_WISH = P({ run = enginePrimary("WISH_EFFECT") })
DEF.BW_REFRESH = P({ run = enginePrimary("REFRESH_EFFECT") })
DEF.BW_HEAL_BELL = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  user.mon.status, user.toxicCounter = nil, nil
  local party = user.isPlayer and battle.game and battle.game.save and (battle.playerParty or battle.game.save.party)
                or battle.enemyParty
  for _, mon in ipairs(party or {}) do mon.status = nil end
  return { T.std(battle, ctx.move.id == 312 and "aroma" or "bell") }
end })
DEF.BW_HEALING_WISH = P({ run = function(ctx)
  local battle, user = ctx.battle, ctx.user
  if #benchOf(battle, user) == 0 then return fail(ctx) end
  sideState(battle, user).healingWish = ctx.move.bwEffect == 270 and "lunar" or "wish"
  hurt(battle, user, user.mon.hp)
  return {}
end })
DEF.BW_MEMENTO = P({ foe = true, run = function(ctx)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  local out = {}
  local blocked = foeStatBlocked(ctx, target)
  if blocked then out[#out + 1] = blocked
  else append(out, (G5.changeStats(battle, target, { { "attack", -2 }, { "spatk", -2 } }, true))) end
  hurt(battle, user, user.mon.hp)
  return out
end })
DEF.BW_SPLASH = P({ run = function(ctx) return { T.std(ctx.battle, "nothingHappened") } end })
DEF.BW_FAIL_IN_SINGLES = P({ status = "partial", note = "fails in a single battle as on the cartridge; in a double Helping Hand works, Follow Me / Rage Powder do not redirect, Ally Switch fails",
  run = function(ctx)
  local battle = ctx.battle
  if not (battle.isDouble and battle:isDouble()) then return fail(ctx) end
  local m = ctx.move.bwEffect
  local partner = battle.partnerOf and battle:partnerOf(ctx.user)
  if m == 176 and partner and partner.mon.hp > 0 then
    partner.bwHelped = turnOf(battle)
    return { T.set(battle, 1044, ctx.user, { nil, partner.name }) }
  end
  if m == 172 then return { T.set(battle, "centerOfAttention", ctx.user) } end
  return fail(ctx)
end })
DEF.BW_AFTER_YOU = P({ foe = true, run = function(ctx)
  local battle, target = ctx.battle, ctx.target
  if target.bwMovedTurn == turnOf(battle) then return fail(ctx) end
  return { T.set(battle, ctx.move.bwEffect == 315 and "postponed" or "kindOffer", target) }
end })
DEF.BW_MAGIC_COAT = P({ run = function(ctx)
  ctx.user.bwMagicCoat = turnOf(ctx.battle)
  return { T.set(ctx.battle, "magicCoat", ctx.user) }
end })
DEF.BW_SNATCH = P({ run = function(ctx)
  ctx.user.bwSnatch = turnOf(ctx.battle)
  return { T.set(ctx.battle, 751, ctx.user) }
end })
DEF.BW_IMPRISON = P({ status = "partial", note = "flag only: the sealed moves are not refused at the menu",
  run = function(ctx)
    if ctx.user.bwImprison then return fail(ctx) end
    ctx.user.bwImprison = true
    return { T.set(ctx.battle, "sealed", ctx.user) }
  end })
DEF.BW_ROOST = DEF.BW_HEAL
DEF.BW_CHARGE_UP = DEF.BW_STAT_SELF

-- --- the target's conditions -----------------------------------------------

DEF.BW_LEECH_SEED = P({ foe = true, run = function(ctx)
  local battle, target = ctx.battle, ctx.target
  if target.leechSeeded or hasType(target, "GRASS") then
    return fail(ctx, T.set(battle, "notAffected", target))
  end
  target.leechSeeded = true
  return { T.set(battle, "seeded", target) }
end })
DEF.BW_DISABLE = P({ foe = true, run = function(ctx)
  local battle, target = ctx.battle, ctx.target
  local last = target.lastMove
  if target.disabledSlot or not last then return fail(ctx) end
  for i, mv in ipairs(target.curMoves or {}) do
    if mv.id == last and (mv.pp or 0) > 0 then
      target.disabledSlot, target.disabledTurns = i, 4
      return { T.set(battle, "disabled", target, { nil, moveName(battle, last) }) }
    end
  end
  return fail(ctx)
end })
DEF.BW_SPITE = P({ foe = true, run = function(ctx)
  local battle, target = ctx.battle, ctx.target
  local last = target.lastMove
  for _, mv in ipairs(target.curMoves or {}) do
    if mv.id == last and (mv.pp or 0) > 0 then
      local n = math.min(mv.pp, 4)
      mv.pp = mv.pp - n
      return { T.set(battle, "spite", target, { nil, moveName(battle, last), count = n }) }
    end
  end
  return fail(ctx)
end })
DEF.BW_ENCORE = P({ foe = true, run = function(ctx)
  local battle, target = ctx.battle, ctx.target
  if target.encoreTurns or not target.lastMove then return fail(ctx) end
  target.encoreTurns, target.encoreMove = 3, target.lastMove
  return { T.set(battle, "encore", target) }
end })
DEF.BW_TAUNT = P({ foe = true, run = function(ctx)
  local t = ctx.target
  if t.tauntTurns or abilityOf(t) == "OBLIVIOUS" then return fail(ctx) end
  t.tauntTurns = 3
  return { T.set(ctx.battle, "taunt", t) }
end })
DEF.BW_TORMENT = P({ foe = true, run = function(ctx)
  local t = ctx.target
  if t.tormented then return fail(ctx) end
  t.tormented = true
  return { T.set(ctx.battle, "torment", t) }
end })
DEF.BW_YAWN = P({ foe = true, run = function(ctx)
  local t = ctx.target
  if t.mon.status or t.drowsyTurns or Abil().refusesStatus(t, "SLP") or t.safeguardTurns then
    return fail(ctx)
  end
  t.drowsyTurns = 2
  return { T.set(ctx.battle, "drowsy", t) }
end })
DEF.BW_NIGHTMARE = P({ foe = true, run = function(ctx)
  local t = ctx.target
  if t.mon.status ~= "SLP" or t.nightmare then return fail(ctx) end
  t.nightmare = true
  return { T.set(ctx.battle, "nightmare", t) }
end })
DEF.BW_ATTRACT = P({ foe = true, run = function(ctx)
  local out = G5.condition(ctx, ctx.target, 7)
  if #out == 0 or out[1] == "But, it failed!" then return fail(ctx) end
  return out
end })
DEF.BW_FORESIGHT = P({ foe = true, run = function(ctx)
  ctx.target.identified = true
  if ctx.move.bwEffect == 216 then ctx.target.bwMiracleEye = true end
  return { T.set(ctx.battle, "identified", ctx.target) }
end })
DEF.BW_MEAN_LOOK = P({ foe = true, run = function(ctx)
  local t = ctx.target
  if t.trapped and not t.bwTrappedByBind then return fail(ctx) end
  t.trapped, t.bwTrappedByBind = true, nil
  return { T.set(ctx.battle, "cantEscape", t) }
end })
DEF.BW_PERISH_SONG = P({ run = function(ctx)
  local set = false
  for _, b in ipairs(activeList(ctx.battle)) do
    if b.mon.hp > 0 and not b.perishTurns and abilityOf(b) ~= "SOUNDPROOF" then
      b.perishTurns = 4
      set = true
    end
  end
  if not set then return fail(ctx) end
  return { T.std(ctx.battle, "perishSong") }
end })
DEF.BW_LOCK_ON = P({ foe = true, run = function(ctx)
  ctx.user.lockedOn = ctx.target
  return { T.pair(ctx.battle, "tookAim", ctx.user, ctx.target) }
end })
DEF.BW_EMBARGO = P({ foe = true, status = "partial", note = "bag items are not refused",
  run = function(ctx)
    local t = ctx.target
    if t.bwEmbargo then return fail(ctx) end
    t.bwEmbargo = 5
    return { T.set(ctx.battle, "embargo", t) }
  end })
DEF.BW_HEAL_BLOCK = P({ foe = true, run = function(ctx)
  local t = ctx.target
  if t.bwHealBlock then return fail(ctx) end
  t.bwHealBlock = 5
  return { T.set(ctx.battle, "healBlock", t) }
end })
DEF.BW_TELEKINESIS = P({ foe = true, status = "partial", note = "lifts the target (Ground immunity); moves do not yet always hit it",
  run = function(ctx)
    local t = ctx.target
    if t.bwTelekinesis or t.bwGrounded then return fail(ctx) end
    t.bwTelekinesis = 3
    return { T.set(ctx.battle, "hurled", t) }
  end })
DEF.BW_GASTRO_ACID = P({ foe = true, run = function(ctx)
  local t = ctx.target
  if not abilityOf(t) or abilityOf(t) == "MULTITYPE" then return fail(ctx) end
  t.abilityOverride = false
  return { T.set(ctx.battle, "abilitySuppressed", t) }
end })
local function abilityLabel(name)
  return (tostring(name):lower():gsub("_", " "):gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end
local function setAbility(ctx, who, name)
  local cur = abilityOf(who)
  if cur == name or cur == "MULTITYPE" or cur == "TRUANT" then return fail(ctx) end
  who.abilityOverride = name
  return { T.set(ctx.battle, 405, who, { nil, abilityLabel(name) }) }
end
DEF.BW_WORRY_SEED = P({ foe = true, run = function(ctx)
  local out = setAbility(ctx, ctx.target, "INSOMNIA")
  if ctx.target.mon.status == "SLP" and ctx.target.abilityOverride == "INSOMNIA" then
    ctx.target.mon.status = nil
    out[#out + 1] = T.set(ctx.battle, "wokeUp", ctx.target)
  end
  return out
end })
DEF.BW_SIMPLE_BEAM = P({ foe = true, run = function(ctx) return setAbility(ctx, ctx.target, "SIMPLE") end })
DEF.BW_ENTRAINMENT = P({ foe = true, run = function(ctx)
  local mine = abilityOf(ctx.user)
  if not mine or mine == "TRACE" or mine == "FORECAST" then return fail(ctx) end
  return setAbility(ctx, ctx.target, mine)
end })
DEF.BW_SKILL_SWAP = P({ foe = true, run = enginePrimary("SKILL_SWAP_EFFECT") })
DEF.BW_ROLE_PLAY = P({ foe = true, run = enginePrimary("ROLE_PLAY_EFFECT") })
DEF.BW_SOAK = P({ foe = true, run = function(ctx)
  local t = ctx.target
  if #(t.curTypes or {}) == 1 and t.curTypes[1] == "WATER" then return fail(ctx) end
  t.curTypes = { "WATER" }
  return { T.set(ctx.battle, "typeChange", t, { nil, "Water" }) }
end })
DEF.BW_REFLECT_TYPE = P({ foe = true, ignoresSub = true, run = function(ctx)
  local t, u = ctx.target, ctx.user
  if #(t.curTypes or {}) == 0 then return fail(ctx) end
  u.curTypes = { t.curTypes[1], t.curTypes[2] }
  return { T.pair(ctx.battle, "typeMatch", u, t) }
end })
DEF.BW_CONVERSION = P({ run = function(ctx)
  local battle, u = ctx.battle, ctx.user
  local pool = {}
  for _, mv in ipairs(u.curMoves or {}) do
    local d = battle.data.moves[mv.id]
    if d and d.type and d.bwEffect ~= 30 and not hasType(u, d.type) then pool[#pool + 1] = d.type end
  end
  if #pool == 0 then return fail(ctx) end
  local pick = pool[battle.rng(1, #pool)]
  u.curTypes = { pick }
  return { T.set(battle, "typeChange", u, { nil, abilityLabel(pick) }) }
end })
DEF.BW_CONVERSION_2 = P({ foe = true, ignoresSub = true, run = function(ctx)
  local battle, u = ctx.battle, ctx.user
  local last = ctx.target.lastMove and battle.data.moves[ctx.target.lastMove]
  if not (last and last.type) then return fail(ctx) end
  local pool = {}
  for i = 0, 16 do
    local t = G5.TYPES[i]
    if TC().effectiveness(last.type, { t }) < 10 and not hasType(u, t) then pool[#pool + 1] = t end
  end
  if #pool == 0 then return fail(ctx) end
  local pick = pool[battle.rng(1, #pool)]
  u.curTypes = { pick }
  return { T.set(battle, "typeChange", u, { nil, abilityLabel(pick) }) }
end })
DEF.BW_CAMOUFLAGE = P({ run = function(ctx)
  local u = ctx.user
  if #(u.curTypes or {}) == 1 and u.curTypes[1] == "NORMAL" then return fail(ctx) end
  u.curTypes = { "NORMAL" }
  return { T.set(ctx.battle, "typeChange", u, { nil, "Normal" }) }
end })
DEF.BW_PSYCH_UP = P({ foe = true, ignoresSub = true, run = function(ctx)
  local u, t = ctx.user, ctx.target
  u.stages = {}
  for k, v in pairs(t.stages or {}) do u.stages[k] = v end
  return { T.set(ctx.battle, 1047, u, { nil, t.name }) }
end })
local function swapStages(keys, line)
  return P({ foe = true, ignoresSub = true, run = function(ctx)
    local u, t = ctx.user, ctx.target
    for _, k in ipairs(keys) do u.stages[k], t.stages[k] = t.stages[k], u.stages[k] end
    return { T.set(ctx.battle, line, u) }
  end })
end
DEF.BW_POWER_SWAP = swapStages({ "attack", "spatk" }, "powerSwap")
DEF.BW_GUARD_SWAP = swapStages({ "defense", "spdef" }, "guardSwap")
DEF.BW_HEART_SWAP = swapStages({ "attack", "defense", "spatk", "spdef", "speed", "accuracy", "evasion" }, "heartSwap")
-- the battle copy of the stats: never the party Pokemon's own table
local function ownStats(b)
  if not b.bwOwnStats then
    local copy = {}
    for k, v in pairs(b.curStats or {}) do copy[k] = v end
    b.curStats, b.bwOwnStats = copy, true
  end
  return b.curStats
end
local function split(keys, line)
  return P({ foe = true, run = function(ctx)
    local u, t = ownStats(ctx.user), ownStats(ctx.target)
    for _, k in ipairs(keys) do
      local avg = math.floor(((u[k] or 0) + (t[k] or 0)) / 2)
      u[k], t[k] = avg, avg
    end
    return { T.set(ctx.battle, line, ctx.user) }
  end })
end
DEF.BW_POWER_SPLIT = split({ "attack", "spatk" }, "powerSplit")
DEF.BW_GUARD_SPLIT = split({ "defense", "spdef" }, "guardSplit")
DEF.BW_POWER_TRICK = P({ run = function(ctx)
  local s = ownStats(ctx.user)
  s.attack, s.defense = s.defense, s.attack
  return { T.set(ctx.battle, "powerTrick", ctx.user) }
end })
DEF.BW_PAIN_SPLIT = P({ foe = true, run = function(ctx)
  local u, t = ctx.user, ctx.target
  local each = math.floor((u.mon.hp + t.mon.hp) / 2)
  u.mon.hp = math.min(maxHP(u), each)
  t.mon.hp = math.min(maxHP(t), each)
  ctx.battle:drainNext()
  return { T.std(ctx.battle, "painSplit") }
end })
DEF.BW_PSYCHO_SHIFT = P({ foe = true, run = function(ctx)
  local u, t = ctx.user, ctx.target
  local s = u.mon.status
  if not s or t.mon.status then return fail(ctx) end
  local out = G5.inflict(ctx, t, s, { toxic = u.toxicCounter ~= nil })
  if t.mon.status ~= s then return fail(ctx, out[1]) end
  u.mon.status, u.toxicCounter = nil, nil
  out[#out + 1] = T.set(ctx.battle, "statusNormal", u)
  return out
end })
DEF.BW_TRICK = P({ foe = true, run = function(ctx)
  local battle, u, t = ctx.battle, ctx.user, ctx.target
  local a, b = itemOf(u), itemOf(t)
  if not (a or b) or Abil().keepsItem(t) then return fail(ctx) end
  u.mon.item, t.mon.item = b, a
  local out = { T.set(battle, "trick", u) }
  if b then out[#out + 1] = T.set(battle, "obtained", u, { nil, (itemDef(battle, b) or {}).name or "item" }) end
  if a then out[#out + 1] = T.set(battle, "obtained", t, { nil, (itemDef(battle, a) or {}).name or "item" }) end
  return out
end })
DEF.BW_BESTOW = P({ foe = true, ignoresSub = true, run = function(ctx)
  local battle, u, t = ctx.battle, ctx.user, ctx.target
  local a = itemOf(u)
  if not a or itemOf(t) then return fail(ctx) end
  u.mon.item, t.mon.item = nil, a
  return { T.pair(battle, "received", t, u, { nil, nil, (itemDef(battle, a) or {}).name or "item" }) }
end })
DEF.BW_RECYCLE = P({ run = function(ctx)
  local battle, u = ctx.battle, ctx.user
  local id = u.lastConsumedItem
  if not id or itemOf(u) then return fail(ctx) end
  u.mon.item, u.lastConsumedItem = id, nil
  return { T.set(battle, "found", u, { nil, (itemDef(battle, id) or {}).name or "item" }) }
end })
DEF.BW_TRANSFORM = P({ foe = true, ignoresSub = true, run = function(ctx)
  local fn = ME().primary.TRANSFORM_EFFECT
  if ctx.target.bwTransformed or ctx.user.bwTransformed then return fail(ctx) end
  local out = fn(ctx.battle, ctx.user, ctx.target, ctx.move, ctx.moveInst)
  ctx.user.bwTransformed, ctx.user.bwOwnStats = true, true
  return out
end })
DEF.BW_MIMIC = F({ announceAnim = false, perform = function(ctx)
  ctx.battle:resolveMimic(ctx.user, ctx.target, ctx.move, ctx.moveInst)
end })
DEF.BW_SKETCH = P({ foe = true, ignoresSub = true, run = enginePrimary("SKETCH_EFFECT") })
DEF.BW_SLEEP_TALK = P({ run = function(ctx)
  local battle, u = ctx.battle, ctx.user
  if u.mon.status ~= "SLP" then return fail(ctx) end
  local pool = {}
  local banned = { [214] = true, [118] = true, [119] = true, [274] = true, [383] = true,
                   [264] = true, [253] = true, [117] = true }
  for _, mv in ipairs(u.curMoves or {}) do
    local d = battle.data.moves[mv.id]
    if d and not banned[mv.id] and not (d.flags and bit(d.flags, G5.FLAG.charge)) then pool[#pool + 1] = mv.id end
  end
  if #pool == 0 then return fail(ctx) end
  u.callsMoveId = pool[battle.rng(1, #pool)]
  return {}
end })

-- --- moves that call other moves -----------------------------------------

-- the moves Metronome / Assist never pick (Gen 5's own list)
local NO_CALL = {}
for _, id in ipairs({ 68, 102, 118, 119, 144, 165, 166, 168, 182, 194, 197, 203, 214, 243,
                      264, 266, 267, 270, 271, 274, 289, 343, 364, 382, 383, 415, 448, 469,
                      476, 495, 501, 511, 516, 546, 547, 548, 553, 554, 555, 557, 558, 559 }) do
  NO_CALL[id] = true
end
G5.NO_CALL = NO_CALL

DEF.BW_METRONOME = F({ callsMove = function(ctx)
  local battle = ctx.battle
  local pool = {}
  for id, d in pairs(battle.data.moves) do
    if type(id) == "number" and id >= 1 and id <= 559 and type(d) == "table" and not NO_CALL[id] then
      pool[#pool + 1] = id
    end
  end
  table.sort(pool)
  local pick = pool[battle.rng(1, #pool)]
  sayNow(battle, T.std(battle, "metronome", { moveName(battle, pick) }))
  return pick
end })
DEF.BW_ASSIST = F({ callsMove = function(ctx)
  local battle, u = ctx.battle, ctx.user
  local party = u.isPlayer and battle.game and battle.game.save and (battle.playerParty or battle.game.save.party) or battle.enemyParty
  local pool = {}
  for _, mon in ipairs(party or {}) do
    if mon ~= u.mon then
      for _, mv in ipairs(mon.moves or {}) do
        if mv.id and not NO_CALL[mv.id] and mv.id ~= 274 then pool[#pool + 1] = mv.id end
      end
    end
  end
  if #pool == 0 then
    battle:cancelMoveAnim()
    sayNow(battle, failed(battle))
    return nil
  end
  return pool[battle.rng(1, #pool)]
end })
DEF.BW_COPYCAT = F({ callsMove = function(ctx)
  local last = ctx.battle.bw.lastMoveUsed
  if not last or NO_CALL[last] or last == 383 then
    sayNow(ctx.battle, failed(ctx.battle))
    return nil
  end
  return last
end })
DEF.BW_MIRROR_MOVE = F({ callsMove = function(ctx)
  local last = ctx.target.lastMove
  local d = last and ctx.battle.data.moves[last]
  if not d or d.mirrorMoveAffected == false then
    sayNow(ctx.battle, failed(ctx.battle))
    return nil
  end
  return last
end })
DEF.BW_NATURE_POWER = F({ callsMove = function(ctx)
  sayNow(ctx.battle, T.std(ctx.battle, "naturePower", { moveName(ctx.battle, 89) }))
  return 89
end })
DEF.BW_ME_FIRST = F({ status = "missing", note = "needs the target's chosen move; fails",
  perform = function(ctx)
    ctx.battle:cancelMoveAnim()
    sayNow(ctx.battle, failed(ctx.battle))
  end })

-- --- Sky Drop: carried as a two-turn flight of the user's own ---------------
DEF.BW_SKY_DROP = F({ charge = { invulnerable = true }, reaches = {},
  status = "partial", note = "the user flies alone; the target is not lifted" })


-- the effects carried only in part, said where the report can find them
for name, note in pairs({
  BW_SUCKER_PUNCH = "fails only when the target has already moved (its chosen move is not read)",
  BW_BEAT_UP = "one hit per able party member at the user's own base Attack",
  BW_PURSUIT = "double power against a switching target is the engine's flag; the hit before a switch is not modelled",
  BW_UPROAR = "three turns of uproar; the user is not locked into it",
  BW_ROLLOUT = "power ramps and Defense Curl doubles it; the user is not locked in",
  BW_FUTURE_SIGHT = "damage rolled on the turn it is used",
  BW_MIMIC = "the engine's own Mimic flow",
  BW_NATURE_POWER = "always Earthquake (the terrain table is not read)",
}) do
  if DEF[name] then DEF[name].status, DEF[name].note = "partial", note end
end

-- ---------------------------------------------------------------------------
-- THE TABLE: BW effect number -> record. An id not here takes the generic
-- record its class names (BW_HIT / BW_STATUS / BW_STAT / BW_HEAL ...).
-- ---------------------------------------------------------------------------

NAMES = {
  [1] = "BW_STATUS", [7] = "BW_EXPLODE", [8] = "BW_DREAM_EATER", [9] = "BW_MIRROR_MOVE",
  [25] = "BW_HAZE", [26] = "BW_BIDE", [27] = "BW_THRASH", [28] = "BW_FORCE_SWITCH",
  [30] = "BW_CONVERSION", [32] = "BW_HEAL", [33] = "BW_STATUS", [34] = "BW_PAY_DAY",
  [35] = "BW_LIGHT_SCREEN", [36] = "BW_TRI_ATTACK", [37] = "BW_REST", [38] = "BW_OHKO",
  [39] = "BW_CHARGE", [40] = "BW_SUPER_FANG", [41] = "BW_DRAGON_RAGE", [42] = "BW_BIND",
  [45] = "BW_JUMP_KICK", [46] = "BW_MIST", [47] = "BW_FOCUS_ENERGY", [57] = "BW_TRANSFORM",
  [65] = "BW_REFLECT", [75] = "BW_CHARGE", [79] = "BW_SUBSTITUTE", [80] = "BW_RECHARGE",
  [81] = "BW_RAGE", [82] = "BW_MIMIC", [83] = "BW_METRONOME", [84] = "BW_LEECH_SEED",
  [85] = "BW_SPLASH", [86] = "BW_DISABLE", [87] = "BW_LEVEL_DAMAGE", [88] = "BW_PSYWAVE",
  [89] = "BW_COUNTER", [90] = "BW_ENCORE", [91] = "BW_PAIN_SPLIT", [92] = "BW_SNORE",
  [93] = "BW_CONVERSION_2", [94] = "BW_LOCK_ON", [95] = "BW_SKETCH", [97] = "BW_SLEEP_TALK",
  [98] = "BW_DESTINY_BOND", [99] = "BW_REVERSAL", [100] = "BW_SPITE", [101] = "BW_FALSE_SWIPE",
  [102] = "BW_HEAL_BELL", [104] = "BW_TRIPLE_KICK", [105] = "BW_THIEF", [106] = "BW_MEAN_LOOK",
  [107] = "BW_NIGHTMARE", [109] = "BW_CURSE", [111] = "BW_PROTECT", [112] = "BW_SPIKES",
  [113] = "BW_FORESIGHT", [114] = "BW_PERISH_SONG", [115] = "BW_SANDSTORM", [116] = "BW_ENDURE",
  [117] = "BW_ROLLOUT", [119] = "BW_FURY_CUTTER", [120] = "BW_ATTRACT", [121] = "BW_RETURN",
  [122] = "BW_PRESENT", [123] = "BW_FRUSTRATION", [124] = "BW_SAFEGUARD", [126] = "BW_MAGNITUDE",
  [127] = "BW_BATON_PASS", [128] = "BW_PURSUIT", [129] = "BW_RAPID_SPIN", [130] = "BW_SONICBOOM",
  [132] = "BW_WEATHER_HEAL", [135] = "BW_HIDDEN_POWER", [136] = "BW_RAIN_DANCE",
  [137] = "BW_SUNNY_DAY", [142] = "BW_BELLY_DRUM", [143] = "BW_PSYCH_UP", [144] = "BW_MIRROR_COAT",
  [145] = "BW_SKULL_BASH", [146] = "BW_GUST", [147] = "BW_EARTHQUAKE", [148] = "BW_FUTURE_SIGHT",
  [149] = "BW_GUST", [150] = "BW_STOMP", [151] = "BW_SOLARBEAM", [152] = "BW_THUNDER",
  [153] = "BW_TELEPORT", [154] = "BW_BEAT_UP", [155] = "BW_FLY", [158] = "BW_FAKE_OUT",
  [159] = "BW_UPROAR", [160] = "BW_STOCKPILE", [161] = "BW_SPIT_UP", [162] = "BW_SWALLOW",
  [164] = "BW_HAIL", [165] = "BW_TORMENT", [168] = "BW_MEMENTO", [169] = "BW_FACADE",
  [170] = "BW_FOCUS_PUNCH", [171] = "BW_SMELLINGSALT", [172] = "BW_FAIL_IN_SINGLES",
  [173] = "BW_NATURE_POWER", [175] = "BW_TAUNT", [176] = "BW_FAIL_IN_SINGLES",
  [177] = "BW_TRICK", [178] = "BW_ROLE_PLAY", [179] = "BW_WISH", [180] = "BW_ASSIST",
  [181] = "BW_INGRAIN", [183] = "BW_MAGIC_COAT", [184] = "BW_RECYCLE", [185] = "BW_REVENGE",
  [186] = "BW_BRICK_BREAK", [187] = "BW_YAWN", [188] = "BW_KNOCK_OFF", [189] = "BW_ENDEAVOR",
  [190] = "BW_ERUPTION", [191] = "BW_SKILL_SWAP", [192] = "BW_IMPRISON", [193] = "BW_REFRESH",
  [194] = "BW_GRUDGE", [195] = "BW_SNATCH", [196] = "BW_LOW_KICK", [197] = "BW_SECRET_POWER",
  [201] = "BW_SPORT", [202] = "BW_POISON_FANG", [203] = "BW_WEATHER_BALL", [207] = "BW_SKY_UPPERCUT",
  [210] = "BW_SPORT", [213] = "BW_CAMOUFLAGE", [214] = "BW_ROOST", [215] = "BW_GRAVITY",
  [216] = "BW_FORESIGHT", [217] = "BW_WAKE_UP_SLAP", [219] = "BW_GYRO_BALL",
  [220] = "BW_HEALING_WISH", [221] = "BW_BRINE", [222] = "BW_NATURAL_GIFT", [223] = "BW_FEINT",
  [224] = "BW_PLUCK", [225] = "BW_TAILWIND", [226] = "BW_ACUPRESSURE", [227] = "BW_METAL_BURST",
  [228] = "BW_U_TURN", [230] = "BW_PAYBACK", [231] = "BW_ASSURANCE", [232] = "BW_EMBARGO",
  [233] = "BW_FLING", [234] = "BW_PSYCHO_SHIFT", [235] = "BW_TRUMP_CARD", [236] = "BW_HEAL_BLOCK",
  [237] = "BW_WRING_OUT", [238] = "BW_POWER_TRICK", [239] = "BW_GASTRO_ACID",
  [240] = "BW_LUCKY_CHANT", [241] = "BW_ME_FIRST", [242] = "BW_COPYCAT", [243] = "BW_POWER_SWAP",
  [244] = "BW_GUARD_SWAP", [245] = "BW_PUNISHMENT", [246] = "BW_LAST_RESORT",
  [247] = "BW_WORRY_SEED", [248] = "BW_SUCKER_PUNCH", [249] = "BW_TOXIC_SPIKES",
  [250] = "BW_HEART_SWAP", [251] = "BW_AQUA_RING", [252] = "BW_MAGNET_RISE", [254] = "BW_STRUGGLE",
  [255] = "BW_FLY", [256] = "BW_FLY", [257] = "BW_SURF", [258] = "BW_DEFOG", [259] = "BW_TRICK_ROOM",
  [260] = "BW_BLIZZARD", [261] = "BW_WHIRLPOOL", [263] = "BW_FLY", [266] = "BW_STEALTH_ROCK",
  [267] = "BW_CHATTER", [270] = "BW_HEALING_WISH", [272] = "BW_SHADOW_FORCE",
  [278] = "BW_WIDE_GUARD", [279] = "BW_GUARD_SPLIT", [280] = "BW_POWER_SPLIT",
  [281] = "BW_WONDER_ROOM", [282] = "BW_PSYSHOCK", [283] = "BW_VENOSHOCK", [285] = "BW_TELEKINESIS",
  [286] = "BW_MAGIC_ROOM", [287] = "BW_SMACK_DOWN", [289] = "BW_FLAME_BURST",
  [291] = "BW_HEAVY_SLAM", [292] = "BW_SYNCHRONOISE", [293] = "BW_ELECTRO_BALL", [294] = "BW_SOAK",
  [297] = "BW_FOUL_PLAY", [298] = "BW_SIMPLE_BEAM", [299] = "BW_ENTRAINMENT", [300] = "BW_AFTER_YOU",
  [302] = "BW_ECHOED_VOICE", [303] = "BW_CHIP_AWAY", [304] = "BW_CLEAR_SMOG",
  [305] = "BW_STORED_POWER", [306] = "BW_QUICK_GUARD", [307] = "BW_FAIL_IN_SINGLES",
  [308] = "BW_SHELL_SMASH", [309] = "BW_HEAL_PULSE", [310] = "BW_HEX", [311] = "BW_SKY_DROP",
  [313] = "BW_DRAGON_TAIL", [314] = "BW_INCINERATE", [315] = "BW_AFTER_YOU", [317] = "BW_ACROBATICS",
  [318] = "BW_REFLECT_TYPE", [319] = "BW_RETALIATE", [320] = "BW_FINAL_GAMBIT", [323] = "BW_BESTOW",
  [331] = "BW_CHARGE", [332] = "BW_CHARGE", [337] = "BW_THUNDER",
}
G5.NAMES = NAMES

-- the self-targeting stat moves keep accuracy out of it
local SELF_STAT = { [10] = true, [11] = true, [13] = true, [16] = true, [50] = true, [51] = true,
                    [52] = true, [53] = true, [54] = true, [108] = true, [156] = true, [174] = true,
                    [206] = true, [208] = true, [211] = true, [212] = true, [277] = true, [284] = true,
                    [290] = true, [312] = true, [316] = true, [321] = true, [322] = true, [327] = true,
                    [328] = true }
G5.SELF_STAT = SELF_STAT
for id in pairs(SELF_STAT) do NAMES[id] = "BW_STAT_SELF" end

-- ---------------------------------------------------------------------------
-- LOOKUP
-- ---------------------------------------------------------------------------

local cache = {}

function G5.build(name)
  local sure = name:sub(-5) == "~SURE"
  local base = sure and name:sub(1, -6) or name
  local spec = DEF[base]
  if not spec then return nil end
  if spec.kind == "primary" then return primaryRecord(base, spec, sure) end
  return fullRecord(base, spec, sure)
end

function G5.record(battle, name)
  if type(name) ~= "string" then return nil end
  local rec = cache[name]
  if rec == nil then
    rec = G5.build(name) or false
    cache[name] = rec
  end
  if battle and battle.bw then G5.ensure(battle) end
  return rec or nil
end

-- what is implemented, for the check tool: "full", "partial" or "missing"
function G5.coverage(effect)
  local name = NAMES[effect]
  if not name then return "generic", nil end
  local spec = DEF[name]
  if not spec then return "missing", nil end
  return spec.status or "full", spec.note
end


-- the turn-level rules and the records they complete (src/battle/Gen5MoveRules.lua)
require("src.battle.Gen5MoveRules").install(G5)

return G5
