-- Real interpreters, party records and native status producers in both engines.
local C = {}
function C.run(backend, version)
  local T, source = require("tests.modkit"), backend == "gen1"
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set(version)
  local VM = source and require("src.core.game3.battle.ai_vm")
  local AI = not source and require("src.battle.Gen3AI")
  local Adapter = source and require("src.core.game3.battle.adapter")
  local copy = require("src.mods.Merge").deepCopy
  local rows = {}
  local function mon(status, extra)
    local m = {
      species = 25,
      speciesNumbering = "internal",
      hp = 100,
      maxHp = 100,
      nickname = "TEST",
      level = 30,
      moves = { 33 },
      pp = { 10 },
      stats = { hp = 100 },
      status = status,
    }
    for k, v in pairs(extra or {}) do
      m[k] = v
    end
    return m
  end
  local function fresh()
    local b = {
      battlers = {},
      playerParty = {},
      foeParty = {},
      double = true,
      turn = 1,
      playerSide = { hazards = {} },
      enemySide = { hazards = {} },
      absent = {},
      over = false,
      data = {
        constants = {},
        pokemon = { TEST_SPECIES = { index = 25 } },
        moves = { TEST = { index = 33 } },
      },
      trainer = { aiFlags = 1 },
      queue = {},
      game = { save = { options = { animations = false } } },
      ruleset = { sleepTurnsMin = 2, sleepTurnsMax = 5 },
    }
    for id = 0, 3 do
      b.battlers[id] = {
        id = id,
        position = id,
        side = id % 2 == 0 and "player" or "enemy",
        isPlayer = id % 2 == 0,
        type1 = 0,
        curTypes = { "NORMAL" },
        ability = 0,
        stages = {},
        mon = mon(),
        partyIndex = math.floor(id / 2) + 1,
        name = "TEST",
        item = 0,
      }
      local p = id % 2 == 0 and b.playerParty or b.foeParty
      p[#p + 1] = b.battlers[id].mon
    end
    b.player, b.enemy, b.enemyParty = b.battlers[0], b.battlers[1], b.foeParty
    b.sides =
      { { battlers = { b.battlers[0], b.battlers[2] } }, { battlers = { b.battlers[1], b.battlers[3] } } }
    local draws = {}
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return lo
    end
    if not source then
      setmetatable(b, { __index = require("src.battle.BattleState") })
    end
    return b, draws
  end
  local function query(b, userId, targetId, which, wanted)
    local user, target = b.battlers[userId], b.battlers[targetId]
    if source then
      local scores = { 100 }
      VM.run(
        VM.new({
          st = b,
          user = user,
          target = target,
          scores = scores,
          movesetIndex = 1,
          rng = b.rng,
          pack = {
            scripts = {
              main = {
                { op = "if_status_in_party", battler = which, status = wanted, target = "yes" },
                { op = "end" },
              },
              yes = { { op = "score", delta = 5 }, { op = "end" } },
            },
          },
        }),
        "main"
      )
      return scores[1]
    end
    local p = {
      entries = { [0] = 1 },
      code = {
        { name = "if_status_in_party", args = { which, wanted, 3 }, next = 2 },
        { name = "end", args = {} },
        { name = "score", args = { 5 }, next = 4 },
        { name = "end", args = {} },
      },
    }
    b.data.constants.gen3BattleAI = p
    T.eq(AI.runs(p, 1), true, "party status opcode is reachable")
    local scores = AI.scoreMoves(b, user, target, { { id = "TEST", pp = 10 } })
    return scores and scores[1] or false
  end
  local function check(b, draws, name, userId, targetId, which, wanted, expected)
    local before = copy({ b.playerParty, b.foeParty, b.battlers })
    local n = #draws
    local score = query(b, userId, targetId, which, wanted)
    T.eq(score, expected and 105 or 100, name)
    T.same({ b.playerParty, b.foeParty, b.battlers }, before, name .. " is read-only")
    T.eq(#draws, n, name .. " consumes no RNG")
    rows[#rows + 1] = { name = name, score = score, rngCount = #draws }
  end
  -- Full equality, including zero and high bits; never an ANY/subset test.
  for status = 0, 255 do
    local b, d = fresh()
    b.foeParty[6] = mon(status)
    for _, other in ipairs({ 0, 0xFF, 0x88, status }) do
      check(b, d, "word-" .. status .. "/" .. other, 1, 0, 1, other, status == other or other == 0)
    end
  end
  for _, status in ipairs({ 0x180, 0xF80, 0x80000000, 0xFFFFFFFF }) do
    local b, d = fresh()
    b.playerParty = { [6] = mon(status) }
    check(b, d, "wide-exact-" .. status, 1, 0, 0, status, true)
    check(b, d, "wide-no-low-byte-" .. status, 1, 0, 0, status % 256, false)
  end
  do
    local b, d = fresh()
    b.playerParty, b.foeParty, b.enemyParty = nil, nil, nil
    check(b, d, "missing-party-does-not-match-zero", 1, 0, 0, 0, false)
    b.playerParty = { [6] = mon(-1) }
    check(b, d, "unsigned-status-word", 1, 0, 0, 0xFFFFFFFF, true)
  end
  -- FireRed selects a fixed party; Emerald selects the user/target's side.
  for userId = 0, 3 do
    for targetId = 0, 3 do
      for _, which in ipairs({ 0, 1, 2, 3, 7 }) do
        local b, d = fresh()
        b.playerParty[6], b.foeParty[6] = mon("BRN"), mon("PAR")
        local enemy = which == 1
        if version == "emerald" then
          enemy = (which == 1 and userId or targetId) % 2 == 1
        end
        local name = "side-" .. userId .. "/" .. targetId .. "/" .. which
        check(b, d, name .. "-burn", userId, targetId, which, 16, not enemy)
        check(b, d, name .. "-paralysis", userId, targetId, which, 64, enemy)
      end
    end
  end
  for _, spec in ipairs({
    { name = "fainted", fields = { hp = 0 }, match = false },
    { name = "empty-species", fields = { species = 0 }, match = false },
    { name = "egg-species", fields = { species = 412 }, match = false },
    { name = "bad-egg", fields = { isBadEgg = true }, match = false },
    { name = "numeric-bad-egg", fields = { isBadEgg = 1 }, match = false },
    { name = "normal-egg-underlying-species", fields = { isEgg = true }, match = true },
    { name = "normal-egg-alias", fields = { egg = true }, match = true },
    { name = "zero-bad-egg-flag", fields = { isBadEgg = 0 }, match = true },
    { name = "healthy-reserve", fields = {}, match = true },
  }) do
    local b, d = fresh()
    b.foeParty = { [6] = mon("BRN", spec.fields) }
    b.enemyParty = b.foeParty
    check(b, d, spec.name, 1, 0, 1, 16, spec.match)
  end
  do
    local b, d = fresh()
    b.foeParty = { [7] = mon("BRN") }
    b.enemyParty = b.foeParty
    check(b, d, "only-six-native-slots", 1, 0, 1, 16, false)
    b.foeParty[1] = b.enemy.mon
    b.enemy.mon.status = "BRN"
    check(b, d, "includes-active-mon", 1, 0, 1, 16, true)
    b.enemy.status = "PAR"
    check(b, d, "party-not-battler-cache", 1, 0, 1, 16, true)
    b.enemy.mon.status = nil
    check(b, d, "party-cleared-not-stale-cache", 1, 0, 1, 64, false)
  end
  for _, status in ipairs({
    "PSN",
    "POISON",
    "BRN",
    "BURN",
    "FRZ",
    "FREEZE",
    "PAR",
    "PARALYSIS",
    "TOX",
    "TOXIC",
  }) do
    local bits = ({
      PSN = 8,
      POISON = 8,
      BRN = 16,
      BURN = 16,
      FRZ = 32,
      FREEZE = 32,
      PAR = 64,
      PARALYSIS = 64,
      TOX = 128,
      TOXIC = 128,
    })[status]
    local b, d = fresh()
    b.foeParty[1].status = status
    check(b, d, "named-" .. status, 1, 0, 1, bits, true)
  end
  for turns = 1, 7 do
    local b, d = fresh()
    b.foeParty[1].status, b.foeParty[1].sleep = "SLP", turns
    check(b, d, "sleep-exact-" .. turns, 1, 0, 1, turns, true)
    check(b, d, "sleep-not-any-mask-" .. turns, 1, 0, 1, 7, turns == 7)
  end
  -- Use actual infliction and attack-canceller producers, never set their
  -- expected status/counter in lieu of executing them.
  local restores = {}
  local function patch(t, key, value)
    local old = t[key]
    t[key] = value
    restores[#restores + 1] = function()
      t[key] = old
    end
  end
  if source then
    local Moves, Pokemon = require("src.core.game3.battle.moves"), require("src.core.game3.pokemon")
    local moves = {
      [33] = {
        effect = 0,
        power = 35,
        type = 0,
        accuracy = 100,
        pp = 35,
        flags = 0,
        target = 0,
        priority = 0,
      },
    }
    patch(Moves, "_rom", moves)
    patch(Moves, "_romLoaded", true)
    patch(Moves, "_linkRows", nil)
    patch(Moves, "BY_NUM", { [33] = "TACKLE" })
    patch(Moves, "_numByName", { TACKLE = 33 })
    patch(Pokemon, "_battleMoves", moves)
    patch(Pokemon, "_moveNames", { [33] = "TACKLE" })
    patch(Pokemon, "_romMoveNames", { [33] = "TACKLE" })
  end
  local oldSink = source and Adapter.textSink
  if source then
    Adapter.textSink = function(id)
      return id
    end
  end
  for _, status in ipairs({ "BRN", "PAR", "PSN", "TOX", "SLP" }) do
    local b, d = fresh()
    local target = b.enemy
    if source then
      T.eq(Adapter.new(b):applyStatus(target, status, b.player), true, "native status producer lands")
    else
      local actual = status == "TOX" and "PSN" or status
      local msgs =
        require("src.battle.StatusRegistry").inflict(b, target, actual, { toxic = status == "TOX" })
      T.check(#msgs > 0, "native status producer lands")
    end
    local wanted = ({ BRN = 16, PAR = 64, PSN = 8, TOX = 128, SLP = 2 })[status]
    check(b, d, "produced-" .. status, 1, 0, 1, wanted, true)
    T.same(d, status == "SLP" and { { 0, 3 } } or {}, "native producer RNG")
    rows[#rows + 1] = { name = "producer-rng-" .. status, draws = copy(d) }
    if status == "SLP" then
      if source then
        local Engine = require("src.core.game3.battle.engine")
        local M = Engine.newContext(target, b.player, 33, 1, Adapter.new(b), b, {}, { hits = {} }, {})
        Engine.canceller(M)
      else
        b:statusInterrupt(target, b.player)
      end
      check(b, d, "produced-sleep-decrement", 1, 0, 1, 1, true)
      local ready
      if source then
        local Engine = require("src.core.game3.battle.engine")
        local M = Engine.newContext(target, b.player, 33, 1, Adapter.new(b), b, {}, { hits = {} }, {})
        ready = Engine.canceller(M)
      else
        ready = not b:statusInterrupt(target, b.player)
      end
      T.eq(ready, true, "native waking permits the pending move")
      check(b, d, "produced-sleep-woke", 1, 0, 1, 1, false)
    end
    if source then
      Adapter.new(b):clearStatus(target)
    else
      b:abilitySwitchOut(
        setmetatable(
          { mon = target.mon, curAbility = "NATURAL_CURE", abilityOverride = "NATURAL_CURE" },
          { __index = target }
        )
      )
    end
    check(b, d, "produced-cured-" .. status, 1, 0, 1, wanted, false)
  end
  do
    local b, d = fresh()
    local target = b.enemy
    local ready
    if source then
      target.ability = 48
      Adapter.new(b):applyStatus(target, "SLP", b.player)
      local Engine = require("src.core.game3.battle.engine")
      ready =
        Engine.canceller(Engine.newContext(target, b.player, 33, 1, Adapter.new(b), b, {}, { hits = {} }, {}))
    else
      target.abilityOverride = "EARLY_BIRD"
      require("src.battle.StatusRegistry").inflict(b, target, "SLP", {})
      ready = not b:statusInterrupt(target, b.player)
    end
    T.eq(ready, true, "Early Bird decrements twice and permits waking move")
    check(b, d, "early-bird-woke", 1, 0, 1, 0, true)
    check(b, d, "early-bird-cleared-sleep", 1, 0, 1, 2, false)
    T.same(d, { { 0, 3 } }, "Early Bird does not reroll sleep duration")
  end
  if source then
    Adapter.textSink = oldSink
  end
  for i = #restores, 1, -1 do
    restores[i]()
  end
  return rows
end
return C
