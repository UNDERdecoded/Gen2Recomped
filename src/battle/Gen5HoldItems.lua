-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK AND WHITE'S HELD ITEMS IN BATTLE.
--
-- A BW item record keeps its hold effect as the cartridge's NUMBER (+0x02,
-- parameter +0x03), and the engine's rules (src/battle/HoldItems.lua) ask
-- for NAMES, so no BW held item did anything: no Leftovers, no berries, no
-- Choice Band, no Focus Sash. The numbering is Platinum's (Leftovers 69,
-- Shell Bell 88, Life Orb 98 ... Gen4HoldEffects.PRET names every one) and
-- Black and White put all of their own new items on ONE effect, 147, told
-- apart by item id: Eviolite 538, Float Stone 539, Rocky Helmet 540, Air
-- Balloon 541, Red Card 542, Ring Target 543, Binding Band 544, Absorb Bulb
-- 545, Cell Battery 546, Eject Button 547, the gems 548..564.
--
-- This module answers for a battler whose held item is a BW record (one with
-- `bwPocket`); everything else keeps HoldItems / HeldItems. The seams:
--   HoldItems.attackMultiplier / defenceMultiplier / accuracyMultiplier /
--     critStages / quickClawChance / flinchChance   -> the same names here
--   Damage.compute, on the finished damage          -> modifyDamage
--   TurnOrder.effectiveSpeed                         -> speed
--   BattleState:holdItemTrigger ("hit" / "turn")     -> trigger
--   BattleState:focusBandHolds                       -> focusBand
--   BattleState:shellBellDrain (after every hit)     -> afterHit
--   BattleState:abilitySwitchIn (BW branch)          -> onSwitchIn
--   HeldItems.canEscape                              -> canEscape
-- Text is the cartridge's (bank 14 / 15, src/battle/Gen5BattleText.lua).
--
-- Gen V numbers: type items, plates and incenses +20% (their parameter),
-- Muscle Band / Wise Glasses +10%, Expert Belt +20% on a super-effective
-- hit, Life Orb x1.3 and a tenth of the user's HP, gems x1.5 (spent), Choice
-- Band / Specs x1.5, Choice Scarf speed x1.5, Eviolite x1.5 both defences,
-- resist berries halve a super-effective hit (Chilan any Normal one),
-- Leftovers / Black Sludge 1/16 (Black Sludge 1/8 off a non-Poison holder),
-- Sticky Barb 1/8, Rocky Helmet 1/6 of the attacker's, Shell Bell 1/8 of the
-- damage, Sitrus a quarter, Oran 10, flavour berries 1/8 (confusing a nature
-- that dislikes them), pinch berries at a quarter, Focus Sash at full HP,
-- Metronome +20% per repeat to x2, Wide Lens +10% / Zoom Lens +20% (moving
-- after the target) accuracy, BrightPowder / Lax Incense -10%.
-- The Choice lock, weather rocks, Binding Band / Grip Claw, Power Herb, Float
-- Stone, Ring Target, Destiny Knot, Shed Shell, Custap / Micle and Quick
-- Claw's line are answered at the bottom of this file and used by
-- src/battle/Gen5MoveRules.lua (the turn, the menu, the moves).

local G = {}

-- PLATINUM / HGSS RIDE THIS FILE TOO (battle parity pass, 2026-11-02).
-- A Gen 4 item keeps its hold effect as pokeplatinum's NAME
-- (src/import/Gen4HoldEffects.lua) and only 33 of the 146 had an engine rule:
-- Sitrus, Life Orb, Choice Specs / Scarf, Focus Sash, Expert Belt, King's
-- Rock, Quick Claw, the resist berries, half the type items and every plate
-- did nothing. The numbering above IS Platinum's, so a Gen 4 name is turned
-- back into its number (gen4Number) and the same rules answer; Gen 4's own
-- numbers where they differ from Gen V (Life Orb x130/100 before the roll,
-- Metronome +10% a use, type items on the power) are applied by
-- src/battle/Gen4Damage.lua, which is Gen 4's damage formula. Gen 4 has no
-- BW text banks, so the lines fall back to the English in Gen4ItemText.
local T = require("src.battle.Gen4ItemText").wrap(require("src.battle.Gen5BattleText"))
G.T = T

local G4NUM
function G.gen4Number(name)
  if type(name) ~= "string" then return nil end
  if not G4NUM then
    G4NUM = {}
    local H = require("src.import.Gen4HoldEffects")
    for i, n in ipairs(H.PRET) do G4NUM[n] = i end
    for id, row in pairs(H.ENGINE) do G4NUM[row[1]] = id end
  end
  return G4NUM[name]
end

-- a Platinum / HGSS battle (any battle on a Gen 4 cartridge)
function G.gen4()
  return require("src.core.GameVersion").isGen4() == true
end

local floor = math.floor
local function ME() return require("src.battle.MoveEffects") end
local function Abil() return require("src.battle.Abilities") end

-- hold effects, by Platinum's number
G.HE = {
  HP_RESTORE = 1, PRZ = 5, SLP = 6, PSN = 7, BRN = 8, FRZ = 9, PP_RESTORE = 10,
  CONFUSE_RESTORE = 11, STATUS_RESTORE = 12, HP_PCT = 13,
  ACC_REDUCE = 48, WHITE_HERB = 49, QUICK_CLAW = 52, MENTAL_HERB = 54, CHOICE_ATK = 55,
  FLINCH = 56, MONEY_UP = 58, SOUL_DEW = 60, CLAMPERL_SPATK = 61, CLAMPERL_SPDEF = 62,
  FLEE = 63, FOCUS_BAND = 65, CRIT_UP = 67, LEFTOVERS = 69, LIGHT_BALL = 71,
  SHELL_BELL = 88, LUCKY_PUNCH = 89, METAL_POWDER = 90, THICK_CLUB = 91, STICK = 92,
  WIDE_LENS = 93, MUSCLE_BAND = 94, WISE_GLASSES = 95, EXPERT_BELT = 96, LIGHT_CLAY = 97,
  LIFE_ORB = 98, TOXIC_ORB = 100, FLAME_ORB = 101, QUICK_POWDER = 102, FOCUS_SASH = 103,
  ZOOM_LENS = 104, METRONOME = 105, IRON_BALL = 106, LAGGING_TAIL = 107,
  BLACK_SLUDGE = 109, CHOICE_SCARF = 115, STICKY_BARB = 116, BIG_ROOT = 124,
  CHOICE_SPATK = 125, ENIGMA = 43, JABOCA = 46, ROWAP = 47, GEN5 = 147,
  MICLE = 44, CUSTAP = 45, POWER_HERB = 99, DESTINY_KNOT = 108, ICY_ROCK = 110,
  SMOOTH_ROCK = 111, HEAT_ROCK = 112, DAMP_ROCK = 113, GRIP_CLAW = 114, SHED_SHELL = 123,
}
local HE = G.HE

-- the BW-only items on effect 147, by item id
G.ID = { EVIOLITE = 538, FLOAT_STONE = 539, ROCKY_HELMET = 540, AIR_BALLOON = 541,
         RED_CARD = 542, RING_TARGET = 543, BINDING_BAND = 544, ABSORB_BULB = 545,
         CELL_BATTERY = 546, EJECT_BUTTON = 547 }
local ID = G.ID

local TYPES16 = { "FIRE", "WATER", "ELECTRIC", "GRASS", "ICE", "FIGHTING", "POISON",
                  "GROUND", "FLYING", "PSYCHIC", "BUG", "ROCK", "GHOST", "DRAGON",
                  "DARK", "STEEL" }

-- the type items and incenses (STRENGTHEN_*) and the plates (126..141)
G.BOOST = { [57] = "BUG", [68] = "STEEL", [72] = "GROUND", [73] = "ROCK", [74] = "GRASS",
            [75] = "DARK", [76] = "FIGHTING", [77] = "ELECTRIC", [78] = "WATER",
            [79] = "FLYING", [80] = "POISON", [81] = "ICE", [82] = "GHOST",
            [83] = "PSYCHIC", [84] = "FIRE", [85] = "DRAGON", [86] = "NORMAL" }
for i, t in ipairs(TYPES16) do G.BOOST[125 + i] = t end
-- the resist berries (WEAKEN_SE_*, 19..34) and Chilan (35)
G.RESIST = { [35] = "NORMAL" }
for i, t in ipairs(TYPES16) do G.RESIST[18 + i] = t end
-- the gems, 548..564, by item id
G.GEM = {}
for i, t in ipairs(TYPES16) do G.GEM[547 + i] = t end
G.GEM[564] = "NORMAL"
-- the pinch berries (36..40) and the flavour berries (14..18)
G.PINCH = { [36] = "attack", [37] = "defense", [38] = "speed", [39] = "spatk", [40] = "spdef" }
G.FLAVOUR = { [14] = "attack", [15] = "spatk", [16] = "speed", [17] = "spdef", [18] = "defense" }
G.CURE = { [5] = "PAR", [6] = "SLP", [7] = "PSN", [8] = "BRN", [9] = "FRZ" }
G.CURE_LINE = { PAR = 920, SLP = 923, PSN = 917, BRN = 929, FRZ = 926 }

-- species the species-locked items care about (national dex numbers)
local PIKACHU, CUBONE, MAROWAK, CLAMPERL, LATIAS, LATIOS = 25, 104, 105, 366, 380, 381
local DITTO, CHANSEY, FARFETCHD = 132, 113, 83

-- ---------------------------------------------------------------------------
-- WHO HOLDS WHAT
-- ---------------------------------------------------------------------------

local function itemsOf(b)
  if b.items then return b.items end
  local battle = b.bwBattle or G.current
  return battle and battle.data and battle.data.items
end

-- the held item's record and id, when it is a BW record
-- BW_NO_HELD=1 (debugging): every BW held item answers as nothing
G.disabled = os.getenv("BW_NO_HELD") ~= nil

function G.defOf(b)
  if G.disabled or type(b) ~= "table" or type(b.mon) ~= "table" then return nil end
  local id = b.mon.item or b.mon.heldItem
  if id == nil or id == 0 or id == false then return nil end
  local items = itemsOf(b)
  local def = items and items[id]
  if type(def) ~= "table" then return nil end
  if def.bwPocket == nil then
    -- a Gen 4 record: its pret name must resolve to a Platinum number
    if not (G.gen4() and G.gen4Number(def.holdEffect)) then return nil end
  end
  return def, id
end

function G.owns(b) return G.defOf(b) ~= nil end

-- (hold effect number, parameter, def, id)
local function held(b)
  local def, id = G.defOf(b)
  if not def then return nil end
  local he = tonumber(def.holdEffect) or G.gen4Number(def.holdEffect) or 0
  if he == 0 then return nil end
  -- Embargo on the holder, Magic Room on the field (the battle may not have
  -- been stamped on the battler yet: G.current answers then)
  local room = b.bwBattle or G.current
  if b.bwEmbargo or (tonumber(b.g4Embargo) or 0) > 0 or (room and room.bw and room.bw.field and (room.bw.field.magicRoom or 0) > 0) then
    return nil
  end
  if Abil().of(b) == "KLUTZ" then return nil end
  return he, tonumber(def.holdEffectParam) or 0, def, tonumber(id) or id
end
G.held = held

local function species(b) return tonumber(b and b.mon and b.mon.species) end
local function maxHP(b)
  local m = b and b.mon
  return (m and m.stats and m.stats.hp) or (m and (m.maxHP or m.maxHp)) or 1
end
local function norm(t) return Abil().normalizeType(t) end
local function itemName(def) return (def and def.name) or "item" end
local function battleOf(b) return (b and b.bwBattle) or G.current end
local function turnOf(battle) return battle and battle.turnCount or 0 end

local function consume(b)
  local mon = b.mon
  b.lastConsumedItem = mon.item or mon.heldItem
  b.bwConsumedItem = b.lastConsumedItem
  mon.item, mon.heldItem = nil, nil
end
G.consume = consume

local function say(battle, text)
  if battle and text and text ~= "" then battle:sayNext(text) end
end

local function heal(battle, b, amount)
  local max = maxHP(b)
  if b.mon.hp >= max or b.bwHealBlock then return 0 end
  local before = b.mon.hp
  b.mon.hp = math.min(max, b.mon.hp + math.max(1, floor(amount)))
  battle:drainNext(b, b.mon.hp)
  return b.mon.hp - before
end

local function hurt(battle, b, amount)
  if not (b and b.mon and b.mon.hp > 0) then return end
  if Abil().of(b) == "MAGIC_GUARD" then return end
  battle:applyDamage(b, math.max(1, floor(amount)))
  if b.mon.hp <= 0 then battle:onFaint(b) end
end

local function hasType(b, t)
  for _, x in ipairs(b and b.curTypes or {}) do if norm(x) == t then return true end end
  return false
end

-- ---------------------------------------------------------------------------
-- THE STAT MULTIPLIERS (HoldItems' seams)
-- ---------------------------------------------------------------------------

function G.attackMultiplier(attacker, move, special)
  local he = held(attacker)
  if not he then return 1, 1 end
  local sp = species(attacker)
  if he == HE.CHOICE_ATK and not special then return 3, 2 end
  if he == HE.CHOICE_SPATK and special then return 3, 2 end
  if he == HE.LIGHT_BALL and sp == PIKACHU then return 2, 1 end
  if he == HE.THICK_CLUB and (sp == CUBONE or sp == MAROWAK) and not special then return 2, 1 end
  if he == HE.CLAMPERL_SPATK and sp == CLAMPERL and special then return 2, 1 end
  if he == HE.SOUL_DEW and (sp == LATIAS or sp == LATIOS) and special then return 3, 2 end
  return 1, 1
end

local function canEvolve(b)
  local battle = battleOf(b)
  local data = battle and battle.data
  local def = data and data.pokemon and data.pokemon[b.mon.species]
  return type(def) == "table" and type(def.evolutions) == "table" and next(def.evolutions) ~= nil
end

function G.defenceMultiplier(defender, move, special)
  local he, _, _, id = held(defender)
  if not he then return 1, 1 end
  local sp = species(defender)
  if id == ID.EVIOLITE and canEvolve(defender) then return 3, 2 end
  if he == HE.METAL_POWDER and sp == DITTO and not special and not defender.transformed then return 2, 1 end
  if he == HE.CLAMPERL_SPDEF and sp == CLAMPERL and special then return 2, 1 end
  if he == HE.SOUL_DEW and (sp == LATIAS or sp == LATIOS) and special then return 3, 2 end
  return 1, 1
end

-- percent, on the attacker's accuracy
function G.accuracyMultiplier(attacker, defender)
  local pct = 100
  local he = held(attacker)
  if he == HE.WIDE_LENS then pct = pct * 110 / 100 end
  if he == HE.ZOOM_LENS then
    local battle = battleOf(attacker)
    if defender and defender.bwMovedTurn and defender.bwMovedTurn == turnOf(battle) then
      pct = pct * 120 / 100
    end
  end
  local dhe, dparam = held(defender)
  if dhe == HE.ACC_REDUCE then pct = pct * (100 - dparam) / 100 end
  return floor(pct)
end

function G.critStages(b)
  local he = held(b)
  if he == HE.CRIT_UP then return 1 end
  if he == HE.LUCKY_PUNCH and species(b) == CHANSEY then return 2 end
  if he == HE.STICK and species(b) == FARFETCHD then return 2 end
  return 0
end

function G.quickClawChance(b)
  local he, param = held(b)
  if he == HE.QUICK_CLAW then return param end
  return 0
end

function G.flinchChance(attacker, move)
  local he, param = held(attacker)
  if he ~= HE.FLINCH then return 0 end
  if move and (move.class == "status" or (tonumber(move.power) or 0) == 0) then return 0 end
  if move and (tonumber(move.flinch) or 0) > 0 then return 0 end
  return param
end

-- the speed TurnOrder compares
function G.speed(b, spd)
  local he = held(b)
  if not he then return spd end
  -- (LAGGING TAIL is an ORDER rule, not a speed: TurnOrder.firstMover via
  -- Gen4MoveEffectsExtra.lagging -- the old speed 0 inverted under Trick Room)
  if he == HE.CHOICE_SCARF then return floor(spd * 3 / 2) end
  if he == HE.IRON_BALL or (he >= 117 and he <= 122) then return math.max(1, floor(spd / 2)) end
  if he == HE.QUICK_POWDER and species(b) == DITTO and not b.transformed then return spd * 2 end
  return spd
end

function G.canEscape(b)
  return held(b) == HE.FLEE
end

-- ---------------------------------------------------------------------------
-- THE FINISHED DAMAGE (Damage.compute, after the type chart)
-- ---------------------------------------------------------------------------

function G.modifyDamage(attacker, defender, move, mult, d, special)
  if not (attacker and defender and move) then return d end
  local ahe, aparam, adef, aid = held(attacker)
  local dhe, _, ddef, did = held(defender)
  if not (ahe or dhe) then return d end
  local battle = battleOf(attacker) or battleOf(defender)
  local mtype = norm(move.type)
  attacker.bwLastTarget, attacker.bwLastMove, attacker.bwLastMult = defender, move, mult
  if ahe then
    if G.BOOST[ahe] and G.BOOST[ahe] == mtype then
      d = floor(d * (100 + aparam) / 100)
    elseif ahe == HE.MUSCLE_BAND and not special then
      d = floor(d * 110 / 100)
    elseif ahe == HE.WISE_GLASSES and special then
      d = floor(d * 110 / 100)
    elseif ahe == HE.EXPERT_BELT and (mult or 10) > 10 then
      d = floor(d * 120 / 100)
    elseif ahe == HE.LIFE_ORB then
      d = floor(d * 5324 / 4096)
      attacker.bwLifeOrbHit = true
    elseif ahe == HE.METRONOME then
      local m = attacker.bwMetronome
      local turn = turnOf(battle)
      if not (m and m.id == move.id) then m = { id = move.id, turn = turn, n = 1 }
      elseif m.turn ~= turn then m.n, m.turn = m.n + 1, turn end
      attacker.bwMetronome = m
      d = floor(d * math.min(20, 10 + 2 * (m.n - 1)) / 10)
    elseif G.GEM[aid] and G.GEM[aid] == mtype then
      d = floor(d * 3 / 2)
      consume(attacker)
      say(battle, T.std(battle, 182, { itemName(adef), move.name }))
    end
  end
  return G.resistBerry(attacker, defender, move, mult, d)
end

-- the resist berries (WEAKEN_SE_*) and Chilan: half a super-effective hit
-- of their type (any Normal one for Chilan), then eaten. Also asked by
-- src/battle/Gen4Damage.lua's Gen 4 path.
function G.resistBerry(attacker, defender, move, mult, d, dry)
  local dhe, _, ddef = held(defender)
  if not (dhe and G.RESIST[dhe]) then return d end
  local mtype = norm(move.type)
  if G.RESIST[dhe] == mtype and ((mult or 10) > 10 or dhe == 35) and not defender.substituteHP then
    local battle = battleOf(defender) or battleOf(attacker)
    d = math.max(1, floor(d / 2))
    if dry then return d end   -- an estimate (the trainer AI): nothing eaten
    consume(defender)
    say(battle, T.set(battle, 219, defender, { nil, itemName(ddef) }))
  end
  return d
end

-- ---------------------------------------------------------------------------
-- ON THE FIELD
-- ---------------------------------------------------------------------------

function G.onSwitchIn(battle, b)
  if not (battle and b) then return end
  G.current = battle
  b.bwBattle = battle
  local he, _, def, id = held(b)
  if not he then return end
  if he == HE.MONEY_UP and b.isPlayer then battle.amuletCoin = true end
  if id == ID.AIR_BALLOON then
    b.bwBalloon = true
    b.bwMagnetRise = b.bwMagnetRise or 9999
    say(battle, T.set(battle, 408, b))
  end
  if he == HE.IRON_BALL then b.bwGrounded = true end
end

-- the balloon is gone: whatever kept it up comes down
local function popBalloon(battle, b)
  if b.bwBalloon then
    b.bwBalloon = nil
    if (b.bwMagnetRise or 0) > 999 then b.bwMagnetRise = nil end
  end
end

local function statLine(battle, b, stat, n, def)
  local order = T.STAT_ORDER[stat]
  if not order then return nil end
  local base = n >= 2 and 959 or 938
  return T.set(battle, base + 3 * order, b, { nil, itemName(def) })
end

local function raise(battle, b, stat, n, def)
  b.stages = b.stages or {}
  local cur = b.stages[stat] or 0
  if cur >= 6 then return false end
  b.stages[stat] = math.min(6, cur + n)
  say(battle, statLine(battle, b, stat, n, def))
  return true
end

-- the berries and herbs, asked after a hit lands on the holder and at the
-- end of every turn. Returns true when something went off.
local function berries(battle, b, he, param, def)
  local max, hp = maxHP(b), b.mon.hp
  local name = itemName(def)
  local unnerved = false
  for _, other in ipairs({ battle.player, battle.enemy }) do
    if other and other ~= b and other.isPlayer ~= b.isPlayer and Abil().of(other) == "UNNERVE" then
      unnerved = true
    end
  end
  local isBerry = def and type(def.name) == "string" and def.name:find("Berry", 1, true) ~= nil
  if isBerry and unnerved then return false end
  -- HP
  if (he == HE.HP_RESTORE or he == HE.HP_PCT) and hp * 2 <= max then
    local amount = he == HE.HP_PCT and floor(max * param / 100) or param
    if heal(battle, b, amount) > 0 then
      say(battle, T.set(battle, 908, b, { nil, name }))
      consume(b)
      return true
    end
  end
  if G.FLAVOUR[he] and hp * 2 <= max then
    if heal(battle, b, max / math.max(1, param)) > 0 then
      say(battle, T.set(battle, 908, b, { nil, name }))
      consume(b)
      if require("src.battle.HoldItems").dislikesFlavour(b, G.FLAVOUR[he]) and not b.confusedTurns then
        b.confusedTurns = battle.rng(2, 5)
        say(battle, T.set(battle, "confused", b))
      end
      return true
    end
  end
  -- statuses
  local st = b.mon.status and tostring(b.mon.status):upper()
  if st == "TOX" then st = "PSN" end
  if G.CURE[he] and st == G.CURE[he] then
    b.mon.status, b.toxicCounter = nil, nil
    if battle.syncShownStatus then battle:syncShownStatus() end
    say(battle, T.set(battle, G.CURE_LINE[st], b, { nil, name }))
    consume(b)
    return true
  end
  if he == HE.STATUS_RESTORE and (st or b.confusedTurns) then
    b.mon.status, b.toxicCounter, b.confusedTurns = nil, nil, nil
    if battle.syncShownStatus then battle:syncShownStatus() end
    say(battle, T.set(battle, 1010, b, { nil, name }))
    consume(b)
    return true
  end
  if he == HE.CONFUSE_RESTORE and b.confusedTurns then
    b.confusedTurns = nil
    say(battle, T.set(battle, 932, b, { nil, name }))
    consume(b)
    return true
  end
  if he == HE.PP_RESTORE then
    for _, mv in ipairs(b.curMoves or b.mon.moves or {}) do
      if mv.pp == 0 then
        local md = battle.data.moves[mv.id]
        local cap = md and tonumber(md.pp) or param
        mv.pp = math.min(cap, param)
        say(battle, T.set(battle, 911, b, { nil, name, md and md.name or "" }))
        consume(b)
        return true
      end
    end
  end
  -- pinch berries: a quarter of the HP (half for a Gluttony holder)
  local pinch = Abil().of(b) == "GLUTTONY" and 2 or 4
  if hp * pinch <= max then
    if G.PINCH[he] then
      if raise(battle, b, G.PINCH[he], 1, def) then consume(b) return true end
    elseif he == 41 and not b.focusEnergy then
      b.focusEnergy = true
      say(battle, T.set(battle, 1001, b, { nil, name }))
      consume(b)
      return true
    elseif he == 42 then
      local list = { "attack", "defense", "speed", "spatk", "spdef" }
      local open = {}
      for _, s in ipairs(list) do if ((b.stages or {})[s] or 0) < 6 then open[#open + 1] = s end end
      if #open > 0 then
        raise(battle, b, open[battle.rng(1, #open)], 2, def)
        consume(b)
        return true
      end
    elseif he == HE.MICLE and not b.bwMicle then
      -- MICLE: the holder's next move is x1.2 accurate (read by
      -- Gen5MoveRules.accuracy, spent by that move)
      b.bwMicle = true
      say(battle, T.set(battle, 1028, b, { nil, name }))
      consume(b)
      return true
    end
  end
  -- herbs
  if he == HE.WHITE_HERB then
    local any = false
    for stat, v in pairs(b.stages or {}) do
      if v < 0 then b.stages[stat] = 0; any = true end
    end
    if any then
      say(battle, T.set(battle, 1010, b, { nil, name }))
      consume(b)
      return true
    end
  end
  if he == HE.MENTAL_HERB and (b.infatuated or b.tauntTurns or b.encoreTurns or b.bwDisabled) then
    b.infatuated, b.tauntTurns, b.encoreTurns, b.encoreMove = nil, nil, nil, nil
    say(battle, T.set(battle, 935, b, { nil, name }))
    consume(b)
    return true
  end
  return false
end

-- BattleState:holdItemTrigger's BW arm
function G.trigger(battle, b, when)
  if not (b and b.mon and b.mon.hp > 0) then return false end
  G.current = battle
  b.bwBattle = b.bwBattle or battle
  local he, param, def = held(b)
  if not he then return false end
  if berries(battle, b, he, param, def) then return true end
  if when ~= "turn" then return false end
  local name = itemName(def)
  local max = maxHP(b)
  if he == HE.LEFTOVERS or (he == HE.BLACK_SLUDGE and hasType(b, "POISON")) then
    if heal(battle, b, max / 16) > 0 then
      say(battle, T.set(battle, 914, b, { nil, name }))
      return true
    end
    return false
  end
  if he == HE.BLACK_SLUDGE or he == HE.STICKY_BARB then
    say(battle, T.set(battle, 1038, b, { nil, name }))
    hurt(battle, b, max / 8)
    return true
  end
  if he == HE.TOXIC_ORB and not b.mon.status and not hasType(b, "POISON") and not hasType(b, "STEEL") then
    b.mon.status, b.toxicCounter = "PSN", 1
    if battle.syncShownStatus then battle:syncShownStatus() end
    say(battle, T.set(battle, 240, b, { nil, name }))
    return true
  end
  if he == HE.FLAME_ORB and not b.mon.status and not hasType(b, "FIRE") then
    b.mon.status = "BRN"
    if battle.syncShownStatus then battle:syncShownStatus() end
    say(battle, T.set(battle, 258, b, { nil, name }))
    return true
  end
  if he == HE.LIGHT_CLAY and battle.bw then
    local s = battle.bw.sides[b.isPlayer and 1 or 2]
    for _, key in ipairs({ "reflect", "lightScreen" }) do
      local mark = "bwClay_" .. key
      if (s[key] or 0) > 0 and not s[mark] then s[key] = s[key] + 3; s[mark] = true
      elseif (s[key] or 0) <= 0 then s[mark] = nil end
    end
  end
  return false
end

-- BattleState:focusBandHolds's BW arm: true when the holder is left on 1 HP
function G.focusBand(battle, b, incoming)
  local he, param, def = held(b)
  if not he then return false end
  if he == HE.FOCUS_SASH and b.mon.hp >= maxHP(b) then
    consume(b)
    b.bwHungOn = itemName(def)
    return true
  end
  if he == HE.FOCUS_BAND and battle.rng(0, 99) < param then
    b.bwHungOn = itemName(def)
    return true
  end
  return false
end

-- BattleState:shellBellDrain's BW arm: everything that answers a hit
function G.afterHit(battle, attacker, dealt)
  G.current = battle
  local target = attacker and attacker.bwLastTarget
  local move = attacker and attacker.bwLastMove
  local mult = attacker and attacker.bwLastMult or 10
  attacker.bwLastTarget, attacker.bwLastMove, attacker.bwLastMult = nil, nil, nil
  local lifeOrb = attacker.bwLifeOrbHit
  attacker.bwLifeOrbHit = nil
  -- a contact move may have just infatuated either side (Cute Charm)
  for _, who in ipairs({ target or false, attacker }) do
    if who then say(battle, G.destinyKnot(battle, who)) end
  end
  if (dealt or 0) <= 0 then return end
  local ahe, aparam, adef = held(attacker)
  -- the attacker's own: Shell Bell, Big Root, Life Orb
  if attacker.mon.hp > 0 then
    if ahe == HE.SHELL_BELL and aparam > 0 and heal(battle, attacker, dealt / aparam) > 0 then
      say(battle, T.set(battle, 914, attacker, { nil, itemName(adef) }))
    end
    if ahe == HE.BIG_ROOT and move and (tonumber(move.recoil) or 0) > 0 then
      local extra = floor(floor(dealt * move.recoil / 100) * 3 / 10)
      if extra > 0 then heal(battle, attacker, extra) end
    end
    if lifeOrb and ahe == HE.LIFE_ORB then
      say(battle, T.set(battle, 1013, attacker))
      hurt(battle, attacker, maxHP(attacker) / 10)
    end
  end
  if not (target and target.mon) then return end
  local the, tparam, tdef, tid = held(target)
  if not the then return end
  local tname = itemName(tdef)
  -- the balloon pops on any damaging hit
  if tid == ID.AIR_BALLOON then
    consume(target)
    popBalloon(battle, target)
    say(battle, T.set(battle, 411, target))
    return
  end
  -- Rocky Helmet: a sixth of the attacker's own, on contact
  if tid == ID.ROCKY_HELMET and move and move.makesContact and attacker.mon.hp > 0 then
    say(battle, T.set(battle, 424, attacker))
    hurt(battle, attacker, maxHP(attacker) / 6)
  end
  -- Jaboca / Rowap: an eighth of the attacker's, physical / special
  if move and attacker.mon.hp > 0
     and ((the == HE.JABOCA and move.class == "physical") or (the == HE.ROWAP and move.class == "special")) then
    consume(target)
    say(battle, T.pair(battle, 1031, attacker, target, { nil, nil, tname }))
    hurt(battle, attacker, maxHP(attacker) / 8)
    return
  end
  if target.mon.hp <= 0 then return end
  local mtype = move and norm(move.type)
  -- Enigma: a quarter back from a super-effective hit
  if the == HE.ENIGMA and mult > 10 and heal(battle, target, maxHP(target) / 4) > 0 then
    say(battle, T.set(battle, 908, target, { nil, tname }))
    consume(target)
    return
  end
  if tid == ID.ABSORB_BULB and mtype == "WATER" then
    if raise(battle, target, "spatk", 1, tdef) then consume(target) end
    return
  end
  if tid == ID.CELL_BATTERY and mtype == "ELECTRIC" then
    if raise(battle, target, "attack", 1, tdef) then consume(target) end
    return
  end
  local G5 = require("src.battle.Gen5MoveEffects")
  if tid == ID.RED_CARD and attacker.mon.hp > 0 and attacker ~= target then
    consume(target)
    say(battle, T.pair(battle, 417, target, attacker))
    for _, m in ipairs(G5.forceOut({ battle = battle, user = target, target = attacker }, true) or {}) do
      say(battle, m)
    end
    return
  end
  if tid == ID.EJECT_BUTTON then
    consume(target)
    say(battle, T.set(battle, 414, target))
    G5.switchOut({ battle = battle, user = target })
    return
  end
end

-- "X hung on using its FOCUS BAND!" in the item's own name
function G.hungOnLine(battle, b)
  local name = b and b.bwHungOn
  if not name then return nil end
  b.bwHungOn = nil
  return T.set(battle, 1007, b, { nil, name })
end

-- ---------------------------------------------------------------------------
-- THE REST: asked by src/battle/Gen5MoveRules.lua and the seams it names
-- ---------------------------------------------------------------------------

-- CHOICE BAND / SPECS / SCARF: the holder is held to the first move it uses
function G.choiceItem(b)
  local he = held(b)
  return he == HE.CHOICE_ATK or he == HE.CHOICE_SPATK or he == HE.CHOICE_SCARF
end

-- the weather rocks: the turns a weather MOVE gains (the parameter, 3: 5 -> 8)
G.ROCK = { [HE.DAMP_ROCK] = "RAIN", [HE.HEAT_ROCK] = "SUN", [HE.SMOOTH_ROCK] = "SANDSTORM",
           [HE.ICY_ROCK] = "HAIL" }
function G.weatherTurns(b, weather)
  local he, param = held(b)
  if he and G.ROCK[he] == weather then return param > 0 and param or 3 end
  return 0
end

-- GRIP CLAW: a binding move holds for seven turns (Gen V; 5-6 = four or five
-- turns of damage otherwise). BINDING BAND: an eighth a turn, not a sixteenth.
function G.bindTurns(battle, user)
  if held(user) == HE.GRIP_CLAW then return 8 end
  return battle.rng(5, 6)
end
function G.bindDivisor(user)
  local _, _, _, id = held(user)
  return id == ID.BINDING_BAND and 8 or 16
end

-- POWER HERB: a charge move fires on the turn it is chosen; the line, or nil
function G.powerHerb(battle, b)
  local he, _, def = held(b)
  if he ~= HE.POWER_HERB then return nil end
  consume(b)
  return T.set(battle, 1022, b, { nil, itemName(def) })
end

-- FLOAT STONE: half the weight
function G.weight(b, w)
  local _, _, _, id = held(b)
  if id == ID.FLOAT_STONE then return math.max(1, floor(w / 2)) end
  return w
end

-- the immunities that go: RING TARGET lifts every type immunity of its
-- holder; a Ground move reaches a Flying type (and a Levitate) under GRAVITY,
-- and a Flying type pulled down by Smack Down or an Iron Ball (bwGrounded).
-- Returns lifted, and whether Levitate is lifted too.
function G.liftsImmunity(defender, move, battle)
  if not (defender and move) then return false, false end
  if battle then G.current = battle end
  local _, _, _, id = held(defender)
  if id == ID.RING_TARGET then return true, false end
  if norm(move.type) == "GROUND" then
    battle = battle or battleOf(defender)
    local gravity = battle and battle.bw and battle.bw.field and (battle.bw.field.gravity or 0) > 0
    if gravity then return true, true end
    if defender.bwGrounded then return true, false end
  end
  return false, false
end

-- SHED SHELL: the holder can always be switched out
function G.shedShell(b) return held(b) == HE.SHED_SHELL end

-- QUICK CLAW (its parameter, 20%) and CUSTAP (a quarter of the HP), asked as
-- the turn opens for a Pokemon about to use a move: the line, or nil
function G.moveFirst(battle, b)
  if not (b and b.mon and b.mon.hp > 0) then return nil end
  G.current = battle
  local he, param, def = held(b)
  if he == HE.QUICK_CLAW and param > 0 and battle.rng(0, 99) < param then
    return T.set(battle, 1025, b, { nil, itemName(def) })
  end
  if he == HE.CUSTAP then
    local pinch = Abil().of(b) == "GLUTTONY" and 2 or 4
    local unnerved = false
    for _, other in ipairs({ battle.player, battle.enemy }) do
      if other and other.isPlayer ~= b.isPlayer and Abil().of(other) == "UNNERVE" then unnerved = true end
    end
    if b.mon.hp * pinch <= maxHP(b) and not unnerved then
      consume(b)
      return T.set(battle, 1025, b, { nil, itemName(def) })
    end
  end
  return nil
end

-- DESTINY KNOT: the holder fell in love, and the one it fell for does too
function G.destinyKnot(battle, holder)
  if not (holder and holder.infatuated and holder.mon and holder.mon.hp > 0) then return nil end
  local he, _, def = held(holder)
  if he ~= HE.DESTINY_KNOT or holder.bwKnotFor == holder.infatuated then return nil end
  holder.bwKnotFor = holder.infatuated
  local src = holder.infatuated
  if not (src and src.mon and src.mon.hp > 0) or src.infatuated
     or Abil().of(src) == "OBLIVIOUS" then return nil end
  src.infatuated = holder
  return T.set(battle, 330, src, { nil, itemName(def) })
end

-- SMOKE BALL: "X fled using its Smoke Ball!"
function G.smokeBallLine(battle, b)
  local he, _, def = held(b)
  if he ~= HE.FLEE then return nil end
  return T.set(battle, 1004, b, { nil, itemName(def) })
end

return G
