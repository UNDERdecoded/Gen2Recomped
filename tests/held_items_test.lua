-- Generation II held-item runtime regression tests.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 held items")
local check, eq = S.check, S.eq
local HeldItems = require("src.battle.HeldItems")
local TurnOrder = require("src.battle.TurnOrder")
local Damage = require("src.battle.Damage")
local Encounter = require("src.world.Encounter")
local ruleset = require("src.battle.rulesets.gen1_faithful")

local function item(key, effect, param)
  return { key = key, heldEffect = effect or 0, heldParam = param or 0 }
end

local data = {
  constants = { generation = 2 },
  items = {
    QUICK_CLAW = item("QUICK_CLAW", 74, 60),
    BRIGHTPOWDER = item("BRIGHTPOWDER", 77, 20),
    SCOPE_LENS = item("SCOPE_LENS", 73, 0),
    STICK = item("STICK", 0, 0),
    LUCKY_PUNCH = item("LUCKY_PUNCH", 0, 0),
    THICK_CLUB = item("THICK_CLUB", 0, 0),
    LIGHT_BALL = item("LIGHT_BALL", 0, 0),
    METAL_POWDER = item("METAL_POWDER", 42, 10),
    MYSTIC_WATER = item("MYSTIC_WATER", 59, 10),
    DRAGON_SCALE = item("DRAGON_SCALE", 64, 10),
    DRAGON_FANG = item("DRAGON_FANG", 0, 0),
    FOCUS_BAND = item("FOCUS_BAND", 79, 30),
    KINGS_ROCK = item("KING_S_ROCK", 75, 30),
    LEFTOVERS = item("LEFTOVERS", 3, 10),
    BERRY = item("BERRY", 1, 10),
    GOLD_BERRY = item("GOLD_BERRY", 1, 30),
    BERRY_JUICE = item("BERRY_JUICE", 1, 20),
    PSNCUREBERRY = item("PSNCUREBERRY", 10, 0),
    BITTER_BERRY = item("BITTER_BERRY", 16, 0),
    MIRACLEBERRY = item("MIRACLEBERRY", 15, 0),
    MYSTERYBERRY = item("MYSTERYBERRY", 6, -1),
    LUCKY_EGG = item("LUCKY_EGG", 0, 0),
    AMULET_COIN = item("AMULET_COIN", 76, 10),
    SMOKE_BALL = item("SMOKE_BALL", 72, 0),
    CLEANSE_TAG = item("CLEANSE_TAG", 8, 0),
    BERSERK_GENE = item("BERSERK_GENE", 0, 0),
  },
  moves = { TACKLE = { pp = 35 }, SKETCH = { pp = 1 } },
  pokemon = {
    SENTRET = { heldItemCommon = "BERRY", heldItemRare = "GOLD_BERRY" },
    EEVEE = {},
  },
}

local function mon(species, held, hp, maxhp)
  hp, maxhp = hp or 100, maxhp or 100
  return {
    species = species or "EEVEE", item = held, hp = hp,
    stats = { hp = maxhp }, moves = {}, status = nil,
  }
end

local function battler(species, held, speed, hp, maxhp)
  return {
    mon = mon(species, held, hp, maxhp), species = species,
    curStats = { attack = 100, defense = 100, speed = speed or 50,
                 special = 100, spatk = 100, spdef = 100 },
    curTypes = { "NORMAL" }, stages = { accuracy = 0, evasion = 0 },
    isPlayer = true, name = species or "MON",
  }
end

-- Quick Claw: priority still wins; equal priority checks serially and stops on
-- the first successful holder instead of rolling both.
do
  local a = battler("EEVEE", "QUICK_CLAW", 10)
  local b = battler("RATTATA", nil, 100)
  local calls = 0
  local rng = function() calls = calls + 1; return 0 end
  check(TurnOrder.firstMover(a, { priority = 0 }, b, { priority = 0 }, rng, nil, data),
        "Quick Claw can move a slower holder first")
  eq(calls, 1, "Quick Claw consumes one roll when the first holder succeeds")
  calls = 0
  check(not TurnOrder.firstMover(a, { priority = 0 }, b, { priority = 1 }, rng, nil, data),
        "Quick Claw never crosses move-priority classes")
  eq(calls, 0, "different move priority does not roll Quick Claw")

  local qa = battler("EEVEE", "QUICK_CLAW", 10)
  local qb = battler("RATTATA", "QUICK_CLAW", 100)
  calls = 0
  check(TurnOrder.firstMover(qa, {}, qb, {}, rng, nil, data),
        "first checked Quick Claw holder wins immediately")
  eq(calls, 1, "two holders do not pre-roll both claws")
end

-- BrightPowder: a threshold can reach zero (no artificial 1/256 floor).
do
  local a, d = battler("EEVEE", nil), battler("RATTATA", "BRIGHTPOWDER")
  local hit = Damage.accuracyRoll(ruleset, { accuracy = 100 }, a, d,
    function() return 0 end, 10, data)
  check(not hit, "BrightPowder may reduce the hit threshold to zero")
end

-- Gen II critical ladder plus held stages.
do
  local a = battler("EEVEE", "SCOPE_LENS")
  local seenMax
  local rng = function(lo, hi) seenMax = hi; return 31 end
  check(Damage.critRoll(ruleset, a, "TACKLE", rng, false, data),
        "Scope Lens raises base crit stage to 32/256")
  eq(seenMax, 255, "Gen II crit uses a byte roll")

  a = battler("FARFETCHD", "STICK")
  check(Damage.critRoll(ruleset, a, "TACKLE", function() return 63 end, false, data),
        "Stick gives Farfetch'd two crit stages")
  a = battler("CHANSEY", "LUCKY_PUNCH")
  check(Damage.critRoll(ruleset, a, "TACKLE", function() return 63 end, false, data),
        "Lucky Punch gives Chansey two crit stages")
end

-- Species stat items and type boosters are data-driven.
do
  local a, d = battler("MAROWAK", "THICK_CLUB"), battler("DITTO", "METAL_POWDER")
  local atk, def = HeldItems.modifyBattleStats(data, a, d, "attack", "defense", 100, 100)
  eq(atk, 200, "Thick Club doubles Cubone/Marowak Attack")
  eq(def, 150, "Metal Powder raises untransformed Ditto Defense by 50 percent")

  a = battler("PIKACHU", "LIGHT_BALL")
  atk = HeldItems.modifyBattleStats(data, a, battler("EEVEE"), "spatk", "spdef", 100, 100)
  eq(atk, 200, "Light Ball doubles Pikachu Sp. Atk")

  a = battler("VAPOREON", "MYSTIC_WATER")
  eq(HeldItems.applyTypeBoost(data, a, "WATER", 101), 111,
     "type booster applies x1.10 with its own floor")
  -- The fixture deliberately keeps Crystal's raw ItemAttributes bug so this
  -- verifies the recomp-level correction rather than hiding it in test data.
  a.mon.item = "DRAGON_SCALE"
  eq(HeldItems.applyTypeBoost(data, a, "DRAGON", 101), 101,
     "Dragon Scale does not inherit Crystal's accidental Dragon boost")
  a.mon.item = "DRAGON_FANG"
  eq(HeldItems.applyTypeBoost(data, a, "DRAGON", 101), 111,
     "Dragon Fang is corrected to boost Dragon-type damage")
end

-- Focus Band is a direct-damage guard; King's Rock is one held-effect roll.
do
  local d = battler("EEVEE", "FOCUS_BAND", 50, 40, 100)
  eq(HeldItems.limitDirectDamage(data, d, 80, function() return 0 end), 39,
     "Focus Band leaves a surviving holder at 1 HP")
  eq(HeldItems.limitDirectDamage(data, d, 80, function() return 30 end), 80,
     "Focus Band fails at/above its 30/256 threshold")

  local u = battler("EEVEE", "KINGS_ROCK")
  local t = battler("RATTATA", nil)
  check(HeldItems.tryKingsRock(data, u, t, { effect = "NO_ADDITIONAL_EFFECT" },
                               function() return 0 end, false),
        "King's Rock can flinch on a NormalHit-script move")
  check(t.flinched == true, "King's Rock sets flinch volatile")
  t.flinched = nil
  check(not HeldItems.tryKingsRock(data, u, t, { effect = "POISON_SIDE_EFFECT1" },
                                   function() return 0 end, false),
        "King's Rock skips move scripts that do not contain kingsrock")
  check(HeldItems.tryKingsRock(data, u, t, { effect = "SNORE_EFFECT" },
                               function() return 0 end, false),
        "King's Rock still runs on Snore's native-flinch script")
  t.flinched = nil
  check(HeldItems.tryKingsRock(data, u, t, { id = "TRIPLE_KICK",
        effect = "NO_ADDITIONAL_EFFECT", multiHit = 3 },
        function() return 0 end, false),
        "King's Rock runs after Triple Kick")
  t.flinched = nil
  check(not HeldItems.tryKingsRock(data, u, t, { effect = "NO_ADDITIONAL_EFFECT" },
                                   function() return 0 end, true),
        "King's Rock does not pass a Substitute")
end

-- Status/confusion consumables.
do
  local b = battler("EEVEE", "PSNCUREBERRY")
  b.mon.status = "PSN"
  local msgs = HeldItems.onStatus({ data = data }, b)
  check(#msgs == 1 and b.mon.status == nil and b.mon.item == nil,
        "PSNCUREBERRY immediately cures poison and is consumed")

  b = battler("EEVEE", "BITTER_BERRY")
  b.confusedTurns = 4
  msgs = HeldItems.onConfusion({ data = data }, b)
  check(#msgs == 1 and b.confusedTurns == nil and b.mon.item == nil,
        "Bitter Berry immediately cures confusion")

  b = battler("EEVEE", "MIRACLEBERRY")
  b.mon.status = "BRN"
  b.confusedTurns = 3
  msgs = HeldItems.onStatus({ data = data }, b)
  check(#msgs == 1 and b.mon.status == nil and b.confusedTurns == nil,
        "MiracleBerry clears primary status and confusion together")
end

-- Weather/residual seam: an HP item can trigger after damage, but an already
-- fainted battler is never revived.  Healing queues the real HP-bar target.
do
  local queue = {}
  local battle = {
    data = data, result = nil,
    sayNext = function(_, text) queue[#queue + 1] = { text = text } end,
    drainNext = function(_, who, hp) queue[#queue + 1] = { who = who, hp = hp } end,
  }
  battle.player = battler("EEVEE", "BERRY", 50, 49, 100)
  battle.enemy = battler("RATTATA", nil, 50, 100, 100)
  HeldItems.endTurn(battle)
  eq(battle.player.mon.hp, 59, "Berry can trigger after residual damage crosses half HP")
  check(battle.player.mon.item == nil, "healing Berry is consumed")
  check(queue[#queue].hp == 59, "healing item queues HP-bar refresh to healed HP")

  battle.player = battler("EEVEE", "LEFTOVERS", 50, 0, 100)
  HeldItems.endTurn(battle)
  eq(battle.player.mon.hp, 0, "Leftovers never revives a residual KO")
end

-- Berserk Gene, Lucky Egg, Amulet Coin, Smoke Ball and Cleanse Tag.
do
  local rngCalls = 0
  local battle = {
    data = data,
    sayNext = function() end,
    rng = function(lo, hi)
      rngCalls = rngCalls + 1
      eq(lo, 2, "Berserk Gene confusion roll uses the normal Gen II lower bound")
      eq(hi, 5, "Berserk Gene confusion roll uses the normal Gen II upper bound")
      return 4
    end,
  }
  local b = battler("EEVEE", "BERSERK_GENE")
  check(HeldItems.onEntry(battle, b), "Berserk Gene activates on entry")
  eq(b.stages.attack, 2, "Berserk Gene raises Attack two stages")
  eq(b.confusedTurns, 4, "Berserk Gene initializes a normal confusion duration")
  eq(HeldItems.confusionCounter(battle, b), 4, "Berserk Gene stores the new side confusion counter")
  eq(rngCalls, 1, "Berserk Gene rolls confusion duration exactly once")
  check(b.mon.item == nil, "Berserk Gene is consumed")

  battle = {
    data = data,
    sayNext = function() end,
    heldConfusionCounters = { player = 3 },
    rng = function(lo, hi)
      eq(lo, 2, "corrected Berserk Gene reroll lower bound")
      eq(hi, 5, "corrected Berserk Gene reroll upper bound")
      return 5
    end,
  }
  b = battler("EEVEE", "BERSERK_GENE")
  HeldItems.onEntry(battle, b)
  eq(b.confusedTurns, 5, "Berserk Gene replaces a stale same-side confusion counter")
  eq(HeldItems.confusionCounter(battle, b), 5, "Berserk Gene stores the fresh confusion counter")

  local egg = mon("CHANSEY", "LUCKY_EGG")
  eq(HeldItems.modifyExperience(data, egg, 100), 150, "Lucky Egg gives x1.5 EXP")

  battle = { data = data }
  b = battler("MEOWTH", "AMULET_COIN")
  HeldItems.observeParticipant(battle, b)
  eq(HeldItems.modifyPrize(battle, 1000), 2000,
     "Amulet Coin doubles prize after its holder participates")

  b = battler("EEVEE", "SMOKE_BALL")
  check(HeldItems.canEscape(data, b), "Smoke Ball guarantees wild escape")

  local party = { mon("EEVEE", "CLEANSE_TAG"), mon("RATTATA") }
  eq(HeldItems.cleanseTagRate(data, party, 25), 12,
     "Cleanse Tag halves the encounter-rate byte with floor")
  party = { mon("EEVEE"), mon("RATTATA", "CLEANSE_TAG") }
  eq(HeldItems.cleanseTagRate(data, party, 25), 12,
     "Cleanse Tag works from any occupied party slot")
end

-- Encounter.roll applies an already-adjusted rate before the slot RNG.
do
  local calls = 0
  local enc = { grass = { rate = 25, buckets = { 256 }, slots = { { species = "RATTATA", level = 2 } } } }
  local got = Encounter.roll(enc, function() calls = calls + 1; return calls == 1 and 12 or 0 end, 12)
  check(got == nil, "halved encounter rate rejects roll equal to threshold")
  eq(calls, 1, "failed rate check consumes no encounter-slot roll")
end

-- Wild held-item generation: byte boundaries, RNG consumption and
-- BATTLETYPE_FORCEITEM match LoadEnemyMon's Gen II item-selection path.
do
  local function run(species, rolls, forceCommon)
    local index = 0
    local rng = function(lo, hi)
      eq(lo, 0, "wild item RNG lower byte bound")
      eq(hi, 255, "wild item RNG upper byte bound")
      index = index + 1
      local value = rolls[index]
      if value == nil then error("unexpected wild-item RNG call " .. tostring(index)) end
      return value
    end
    local got = HeldItems.rollWild(data, species, rng, forceCommon)
    return got, index
  end

  local got, calls = run("SENTRET", { 191 }, false)
  eq(got, nil, "0..191 chooses no held item")
  eq(calls, 1, "no-item branch consumes one byte roll")

  got, calls = run("SENTRET", { 192, 19 }, false)
  eq(got, "GOLD_BERRY", "second roll 0..19 chooses rare Item2")
  eq(calls, 2, "item branch consumes two byte rolls")

  got, calls = run("SENTRET", { 192, 20 }, false)
  eq(got, "BERRY", "second roll 20..255 chooses common Item1")
  eq(calls, 2, "common branch consumes two byte rolls")

  got, calls = run("SENTRET", {}, true)
  eq(got, "BERRY", "BATTLETYPE_FORCEITEM chooses Item1")
  eq(calls, 0, "BATTLETYPE_FORCEITEM consumes no item RNG")

  got, calls = run("EEVEE", { 192, 0 }, false)
  eq(got, nil, "a species with empty item slots still yields no item")
  eq(calls, 2, "empty item slots still follow the normal item RNG path")
end
S.finish()
