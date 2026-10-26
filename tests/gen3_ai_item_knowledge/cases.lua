-- Real GBA interpreters and native held-effect/damage producers.
local C = {}
function C.run(backend, version)
  local T, source = require("tests.modkit"), backend == "gen1"
  require("src.core.GameVersion").set(version)
  local VM = source and require("src.core.game3.battle.ai_vm")
  local AI = not source and require("src.battle.Gen3AI")
  local HostState = not source and require("src.battle.BattleState")
  local Adapter = source and require("src.core.game3.battle.adapter")
  local NativeHeld = source and require("src.core.game3.battle.held_items")
  local restores, defs, raw = {}, {}, {}
  local function patch(t, key, value)
    local old = t[key]
    t[key] = value
    restores[#restores + 1] = function()
      t[key] = old
    end
  end
  local function addItem(id, effect, parameter, name)
    local effectName = ({
      [0] = "NONE",
      [1] = "RESTORE_HP",
      [22] = "EVASION_UP",
      [39] = "FOCUS_BAND",
      [43] = "LEFTOVERS",
    })[effect]
    raw[id] = {
      name = name or "ITEM " .. id,
      pocket = "ITEMS",
      holdEffect = effect,
      holdEffectParam = parameter or 0,
    }
    defs["ITEM_" .. id] = {
      index = id,
      name = raw[id].name,
      gen3HoldEffect = effect,
      holdEffect = effectName or effect,
      holdEffectParam = parameter or 0,
    }
  end
  for i = 0, 66 do
    addItem(1000 + i, i)
  end
  addItem(39, 0)
  addItem(43, 0)
  addItem(54, 0)
  addItem(139, 1, 10, "ORAN BERRY")
  addItem(196, 39, 10, "FOCUS BAND")
  addItem(200, 43, 10, "LEFTOVERS")
  addItem(0x1234, 43)
  if source then
    local Items = require("src.core.game3.items_data")
    patch(Items, "_byId", raw)
    patch(Items, "_byName", {})
    patch(Items, "_pack", { items = raw })
    patch(Adapter, "textSink", function(id)
      return id
    end)
    local Moves, Pokemon = require("src.core.game3.battle.moves"), require("src.core.game3.pokemon")
    local move = {
      [32] = { effect = 38, power = 0, type = 0, accuracy = 30, pp = 5, target = 0, priority = 0, flags = 2 },
      [33] = {
        effect = 0,
        power = 35,
        type = 0,
        accuracy = 100,
        pp = 35,
        target = 0,
        priority = 0,
        flags = 0,
      },
    }
    patch(Moves, "_rom", move)
    patch(Moves, "_romLoaded", true)
    patch(Moves, "_linkRows", nil)
    patch(Moves, "BY_NUM", { [32] = "HORN_DRILL", [33] = "TACKLE" })
    patch(Moves, "_numByName", { HORN_DRILL = 32, TACKLE = 33 })
    patch(Pokemon, "_moveNames", { [32] = "HORN DRILL", [33] = "TACKLE" })
    patch(Pokemon, "_romMoveNames", Pokemon._moveNames)
    patch(Pokemon, "_battleMoves", move)
  end
  local function fresh(roll)
    local b = {
      battlers = {},
      double = true,
      absent = {},
      over = false,
      turn = 1,
      playerSide = { hazards = {} },
      enemySide = { hazards = {} },
      trainer = { aiFlags = 1 },
      data = { items = defs, constants = {}, moves = { TEST = { index = 33, power = 35, type = "NORMAL" } } },
      queue = {},
      game = { save = { options = { animations = false } } },
    }
    for id = 0, 3 do
      b.battlers[id] = {
        id = id,
        position = id,
        side = id % 2 == 0 and "player" or "enemy",
        isPlayer = id % 2 == 0,
        name = "TEST",
        ability = 0,
        abilityOverride = false,
        type1 = 0,
        type2 = 0,
        curTypes = { "NORMAL" },
        stages = {},
        shownHP = 100,
        items = defs,
        item = 0,
        mon = {
          nickname = "TEST",
          hp = 100,
          maxHp = 100,
          level = 30,
          speed = 100 - id * 10,
          item = 0,
          ability = 0,
          moves = { 33 },
          pp = { 10 },
          stats = { hp = 100, speed = 100 - id * 10 },
        },
      }
    end
    b.player, b.enemy = b.battlers[0], b.battlers[1]
    b.playerParty, b.foeParty =
      { b.battlers[0].mon, b.battlers[2].mon }, { b.battlers[1].mon, b.battlers[3].mon }
    b.sides =
      { { battlers = { b.battlers[0], b.battlers[2] } }, { battlers = { b.battlers[1], b.battlers[3] } } }
    local draws = {}
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      return roll or 0
    end
    if not source then
      setmetatable(b, { __index = HostState })
    end
    return b, draws
  end
  local function item(b, id, value)
    local who = b.battlers[id]
    if source then
      who.item, who.mon.item = value, value
    else
      who.mon.item = value ~= 0 and "ITEM_" .. value or 0
    end
  end
  local function history(b)
    local h = b._aiHistory and b._aiHistory.itemEffects or {}
    return { h[0] or 0, h[1] or 0, h[2] or 0, h[3] or 0 }
  end
  local function heal(b, id, moveTurn)
    if source then
      return NativeHeld.normal(Adapter.new(b), b.battlers[id], moveTurn)
    end
    return b:holdItemTrigger(b.battlers[id], moveTurn and "action" or "turn")
  end
  local function hit(b, id, damage, substitute, endure)
    local target, user = b.battlers[id], b.battlers[id % 2 == 0 and 1 or 0]
    target.substituteHP = substitute
    if source then
      target.expEnduring = endure
      local M = require("src.core.game3.battle.engine").newContext(
        user,
        target,
        33,
        1,
        Adapter.new(b),
        b,
        {},
        { hits = {} },
        {}
      )
      require("src.core.game3.battle.effects.hit").applySetDamage(M, damage)
    else
      target.enduring = endure
      b:applyDamage(target, damage, true)
    end
  end
  local function query(b, which, value, getter, expected, label, targetId, userId)
    local user, target = b.battlers[userId or 1], b.battlers[targetId or 0]
    local scores = { 100 }
    if source then
      local ops = getter
          and {
            { op = "get_hold_effect", battler = which },
            { op = "if_equal", value = value, target = "bonus" },
            { op = "end" },
          }
        or { { op = "if_holds_item", battler = which, item = value, target = "bonus" }, { op = "end" } }
      local pack = { scripts = { main = ops, bonus = { { op = "score", delta = 5 }, { op = "end" } } } }
      VM.run(
        VM.new({
          pack = pack,
          st = b,
          user = user,
          target = target,
          scores = scores,
          movesetIndex = 1,
          rng = b.rng,
        }),
        "main"
      )
    else
      local code = getter
          and {
            { name = "get_hold_effect", args = { which }, next = 2 },
            { name = "if_equal", args = { value, 4 }, next = 3 },
            { name = "end", args = {} },
            { name = "score", args = { 5 }, next = 5 },
            { name = "end", args = {} },
          }
        or {
          { name = "if_holds_item", args = { which, value, 3 }, next = 2 },
          { name = "end", args = {} },
          { name = "score", args = { 5 }, next = 4 },
          { name = "end", args = {} },
        }
      local program = { entries = { [0] = 1 }, code = code }
      b.data.constants.gen3BattleAI = program
      T.eq(AI.runs(program, 1), true, label .. " whole program is supported")
      scores = AI.scoreMoves(b, user, target, { { id = "TEST", pp = 10 } })
    end
    T.eq(scores and scores[1], expected and 105 or 100, label .. " branch result")
    return scores and scores[1] or false
  end
  local rows = {}
  for effect = 0, 66 do
    local b, draws = fresh()
    item(b, 1, 1000 + effect)
    local result = query(b, 1, effect, true, true, "declared native effect " .. effect)
    T.eq(#draws, 0, "metadata query does not roll")
    T.eq(b._aiHistory, nil, "metadata query cannot reveal an item")
    rows[#rows + 1] = { name = "own-effect-" .. effect, score = result, rng = draws }
  end
  for _, userId in ipairs({ 1, 3 }) do
    for _, targetId in ipairs({ 0, 2 }) do
      for _, seen in ipairs({ false, true }) do
        for which = 0, 3 do
          local b, draws = fresh()
          for id = 0, 3 do
            item(b, id, 200)
          end
          if seen then
            b.battlers[targetId].mon.hp = 90
            T.eq(heal(b, targetId), true, "real Leftovers activates")
            T.eq(b.battlers[targetId].mon.hp, 96, "real Leftovers heals max HP / 16")
          end
          local own = which == 1
          local expected = own and 43 or seen and version == "firered" and 43 or 0
          local label = "roles/" .. userId .. "/" .. targetId .. "/" .. which .. "/" .. tostring(seen)
          local before = history(b)
          local score = query(b, which, expected, true, true, label, targetId, userId)
          T.same(history(b), before, "getter cannot learn/clear history")
          T.eq(#draws, 0, "getter and Leftovers consume no RNG")
          rows[#rows + 1] = { name = label, score = score, expected = expected, history = before }
        end
      end
    end
  end
  for _, spec in ipairs({
    { name = "leftovers-active", item = 200, hp = 90, active = true, known = 43, hpAfter = 96 },
    { name = "leftovers-at-full", item = 200, hp = 100, active = false, known = 0, hpAfter = 100 },
    {
      name = "leftovers-between-actions",
      item = 200,
      hp = 90,
      moveTurn = true,
      active = false,
      known = 0,
      hpAfter = 90,
    },
    { name = "visible-berry-is-not-recorded", item = 139, hp = 50, active = true, known = 0, hpAfter = 60 },
  }) do
    for id = 0, 3 do
      local b, draws = fresh()
      item(b, id, spec.item)
      b.battlers[id].mon.hp = spec.hp
      T.eq(heal(b, id, spec.moveTurn), spec.active, spec.name .. " actual activation")
      T.eq(b.battlers[id].mon.hp, spec.hpAfter, spec.name .. " HP")
      local h = history(b)
      local slot = version == "firered" and 1 or id + 1
      local known = version == "firered" and id % 2 == 1 and 0 or spec.known
      T.eq(h[slot], known, spec.name .. " profile history")
      if known == 0 then
        T.eq(b._aiHistory, nil, "non-recording events do not create history")
      end
      T.eq(#draws, 0, "normal item phase adds no random calls")
      rows[#rows + 1] = { name = spec.name .. "/" .. id, hp = b.battlers[id].mon.hp, history = h }
    end
  end
  for _, spec in ipairs({
    { name = "lethal-success", damage = 120, roll = 0, hp = 1, known = 39 },
    { name = "lethal-failure", damage = 120, roll = 10, hp = 0, known = 0 },
    { name = "nonlethal-success", damage = 10, roll = 0, hp = 90, known = 39 },
    { name = "nonlethal-failure", damage = 10, roll = 99, hp = 90, known = 0 },
    { name = "substitute-success", damage = 120, roll = 0, sub = 25, hp = 100, known = 39 },
    { name = "endure-success", damage = 120, roll = 0, endure = true, hp = 1, known = 39 },
    { name = "endure-failure", damage = 120, roll = 99, endure = true, hp = 1, known = 0 },
  }) do
    for id = 0, 3 do
      local b, draws = fresh(spec.roll)
      item(b, id, 196)
      hit(b, id, spec.damage, spec.sub, spec.endure)
      local h = history(b)
      local slot = version == "firered" and 1 or id + 1
      local known = version == "firered" and id % 2 == 1 and 0 or spec.known
      T.eq(b.battlers[id].mon.hp, spec.hp, spec.name .. " actual adjusted HP")
      T.eq(h[slot], known, spec.name .. " actual Focus Band observation")
      T.same(draws, { { 0, 99 } }, spec.name .. " native adjustment roll even without lethal damage")
      rows[#rows + 1] = {
        name = spec.name .. "/" .. id,
        hp = b.battlers[id].mon.hp,
        sub = b.battlers[id].substituteHP or 0,
        history = h,
        rng = draws,
      }
    end
  end
  -- Real attack-canceller paths must record self-hit procs as well.
  for _, spec in ipairs({
    { name = "self-hit-low-variance", confusion = 0, variance = 85, band = 0, hp = 89, known = 39 },
    { name = "self-hit-high-variance", confusion = 0, variance = 100, band = 0, hp = 87, known = 39 },
    { name = "self-hit-failed-band", confusion = 0, variance = 100, band = 99, hp = 87, known = 0 },
    { name = "self-hit-substitute", confusion = 0, variance = 100, band = 0, sub = 25, hp = 87, known = 39 },
    { name = "self-hit-lethal-band", confusion = 0, variance = 100, band = 0, start = 1, hp = 1, known = 39 },
    { name = "confused-but-moves", confusion = 1, hp = 100, known = 0 },
  }) do
    local b, draws = fresh()
    local user, target = b.player, b.enemy
    item(b, 0, 196)
    user.mon.hp = spec.start or 100
    user.substituteHP = spec.sub
    user.mon.attack, user.mon.defense, user.mon.spAtk, user.mon.spDef = 50, 50, 50, 50
    user.mon.stats.attack, user.mon.stats.defense, user.mon.stats.special = 50, 50, 50
    user.mon.stats.spatk, user.mon.stats.spdef = 50, 50
    user.curStats, user.curTypes, user.abilityOverride = user.mon.stats, { "NORMAL" }, false
    user.def = { types = { "NORMAL" }, baseStats = { speed = 100 } }
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      if lo == 0 and hi == 1 then
        return spec.confusion
      end
      if lo == 85 and hi == 100 then
        return spec.variance
      end
      if lo == 0 and hi == 99 then
        return spec.band
      end
      return lo -- unexpected ranges remain visible in the complete trace
    end
    local ok, spent = pcall(function()
      if source then
        user.confusionTurns = 3
        local Engine = require("src.core.game3.battle.engine")
        local M = Engine.newContext(user, target, 33, 1, Adapter.new(b), b, {}, { hits = {} }, {})
        return Engine.canceller(M) == false
      end
      user.confusedTurns = 3
      b.ruleset = require("src.battle.rulesets.gen3_emerald")
      return b:statusInterrupt(user, target)
    end)
    T.eq(ok, true, spec.name .. " real canceller completes")
    if not ok then
      spent = false
    end
    local h = history(b)
    T.eq(spent, spec.confusion == 0, spec.name .. " real canceller result")
    T.eq(user.mon.hp, spec.hp, spec.name .. " real self-hit HP")
    T.eq(user.substituteHP or 0, spec.sub or 0, spec.name .. " self-hit bypasses Substitute")
    T.eq(h[1], spec.known, spec.name .. " held proc observation")
    local expectedDraws = spec.confusion == 0 and { { 0, 1 }, { 85, 100 }, { 0, 99 } } or { { 0, 1 } }
    T.same(draws, expectedDraws, spec.name .. " complete canceller RNG")
    rows[#rows + 1] = {
      name = spec.name,
      hp = user.mon.hp,
      sub = user.substituteHP or 0,
      spent = spent,
      history = h,
      rng = draws,
    }
  end
  do
    local b, draws = fresh()
    item(b, 0, 196)
    if source then
      Adapter.new(b):applyHpLoss(b.player, 10)
    else
      b:applyDamage(b.player, 10, false)
    end
    T.eq(b.player.mon.hp, 90, "non-move HP loss remains ordinary damage")
    T.eq(b._aiHistory, nil, "non-move HP loss cannot reveal Focus Band")
    T.eq(#draws, 0, "non-move HP loss does not roll Focus Band")
    rows[#rows + 1] = { name = "non-move-damage", hp = b.player.mon.hp, history = history(b), rng = draws }
  end
  -- The real OHKO effect path must observe its roll before Sturdy and
  -- chance/level failure, and must not roll a second time on a landed hit.
  if not source then
    require("src.battle.TypeChart").load({
      type_chart = {
        types = {},
        matchups = {
          { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
          { attacker = "GROUND", defender = "FLYING", multiplier = 0 },
        },
      },
    })
  end
  for _, spec in ipairs({
    { name = "ohko-landed-band", hp = 1, known = 39 },
    { name = "ohko-faster-target", speed = 200, hp = 1, known = 39 },
    { name = "ohko-band-before-sturdy", ability = "STURDY", hp = 100, known = 39, noHitRoll = true },
    { name = "ohko-band-before-level", level = 20, hp = 100, known = 39 },
    { name = "ohko-band-before-miss", hitRoll = 30, hp = 100, known = 39 },
    { name = "ohko-failed-band-miss", band = 99, hitRoll = 99, hp = 100, known = 0 },
    { name = "ohko-endure-failed-band", band = 99, endure = true, hp = 1, known = 0 },
    { name = "ohko-substitute-band", sub = 25, hp = 100, known = 39 },
    { name = "ohko-immune-before-band", ghost = true, hp = 100, known = 0, noRoll = true },
    { name = "ohko-protect-before-band", protect = true, hp = 100, known = 0, noRoll = true },
    { name = "ohko-semi-invulnerable", hidden = true, hp = 100, known = 0, noRoll = true },
    { name = "ohko-lock-on", hidden = true, lock = true, hp = 1, known = 39, noHitRoll = true },
  }) do
    local b, draws = fresh()
    local user, target = b.enemy, b.player
    item(b, 0, 196)
    user.mon.level = spec.level or 30
    target.mon.speed, target.mon.stats.speed = spec.speed or 90, spec.speed or 90
    target.substituteHP = spec.sub
    target.expProtected, target.protecting = spec.protect, spec.protect
    target.expEnduring, target.enduring = spec.endure, spec.endure
    target.semiInvulnerable, target.invulnerable = spec.hidden and "air" or nil, spec.hidden
    if spec.ghost then
      target.type1, target.type2, target.curTypes = 7, 7, { "GHOST" }
    end
    if spec.ability then
      target.ability, target.abilityOverride = 5, spec.ability
    end
    if spec.lock then
      target.expLockedOn, target.expLockedOnById = 1, 1
      user.lockedOn = target
    end
    b.rng = function(lo, hi)
      draws[#draws + 1] = { lo, hi }
      if lo == 0 and hi == 99 then
        return spec.band or 0
      end
      if lo == 1 and hi == 100 then
        return spec.hitRoll or 1
      end
      return lo
    end
    local ok, err = pcall(function()
      if source then
        user.mon.moves[1] = 32
        require("src.core.game3.battle.engine").resolveMove(user, target, 32, 1, Adapter.new(b), b, {}, {})
      else
        b.ruleset = require("src.battle.rulesets.gen3_emerald")
        local move = {
          id = "OHKO",
          index = 32,
          power = 0,
          type = "NORMAL",
          accuracy = 30,
          effect = "OHKO_EFFECT",
          gen3Effect = 38,
          protectAffected = true,
        }
        b.data.moves.OHKO = move
        local Registry = require("src.battle.EffectRegistry")
        local ctx = Registry.makeCtx(b, user, target, move, { id = "OHKO", pp = 5 }, false)
        Registry.runDamaging(b, ctx, b:effectRecord("OHKO_EFFECT"))
      end
    end)
    T.eq(ok, true, spec.name .. " actual effect path completes")
    if not ok then
      print("OHKO_ERROR " .. tostring(err))
    end
    local expected = {}
    if not spec.noRoll then
      expected[1] = { 0, 99 }
      if not spec.noHitRoll then
        expected[2] = { 1, 100 }
      end
    end
    T.eq(target.mon.hp, spec.hp, spec.name .. " HP")
    T.eq(history(b)[1], spec.known, spec.name .. " observation")
    T.same(draws, expected, spec.name .. " full effect RNG")
    rows[#rows + 1] = {
      name = spec.name,
      ok = ok,
      hp = target.mon.hp,
      sub = target.substituteHP or 0,
      history = history(b),
      rng = draws,
    }
  end
  -- A zero-percent Focus Band still spends the native adjustment draw.
  raw[196].holdEffectParam, defs.ITEM_196.holdEffectParam = 0, 0
  do
    local b, draws = fresh()
    item(b, 0, 196)
    hit(b, 0, 10)
    T.eq(b.battlers[0].mon.hp, 90, "zero-percent item cannot endure")
    T.eq(b._aiHistory, nil, "failed zero-percent item cannot reveal")
    T.same(draws, { { 0, 99 } }, "zero-percent native item spends its roll")
    rows[#rows + 1] = { name = "zero-percent-band", history = history(b), rng = draws }
  end
  raw[196].holdEffectParam, defs.ITEM_196.holdEffectParam = 10, 10
  for _, spec in ipairs({
    { name = "own-physical-item", which = 1, value = 200, expected = true },
    { name = "own-partner-item", which = 3, value = 200, expected = true },
    { name = "unseen-target-item", which = 0, value = 200, expected = false },
    { name = "unseen-target-partner", which = 2, value = 200, expected = false },
    { name = "unseen-target-zero", which = 0, value = 0, expected = true },
    { name = "observed-byte-not-item", which = 0, value = 200, expected = false, seen = true },
    { name = "observed-byte-compares", which = 0, value = 43, expected = true, seen = true },
    { name = "own-word-fold", which = 1, value = 0x1234, own = 54, expected = true },
    { name = "own-unfolded-word", which = 1, value = 0x1234, own = 0x1234, expected = false },
  }) do
    local b, draws = fresh()
    for id = 0, 3 do
      item(b, id, 200)
    end
    if spec.own then
      item(b, 1, spec.own)
    end
    if spec.seen then
      b.player.mon.hp = 90
      heal(b, 0)
    end
    local score = query(b, spec.which, spec.value, false, spec.expected, spec.name)
    T.eq(#draws, 0, "membership query adds no RNG")
    rows[#rows + 1] = { name = spec.name, score = score, history = history(b) }
  end
  -- Named legacy metadata and live writes must agree with the numeric ABI.
  for _, row in ipairs({
    { "RESTORE_HP", 1 },
    { "EVASION_UP", 22 },
    { "FOCUS_BAND", 39 },
    { "LEFTOVERS", 43 },
  }) do
    local id, name, effect = 1200 + row[2], row[1], row[2]
    addItem(id, effect)
    defs["ITEM_" .. id].gen3HoldEffect = nil
    defs["ITEM_" .. id].holdEffect = name
    local b, draws = fresh()
    item(b, 1, id)
    local score = query(b, 1, effect, true, true, "named-metadata-" .. name)
    T.eq(#draws, 0, "named metadata query adds no random calls")
    rows[#rows + 1] = { name = "named-metadata-" .. name, score = score }
  end
  -- Clearing a physical item's live metadata must defeat the legacy table.
  raw[200].holdEffect, defs.ITEM_200.gen3HoldEffect, defs.ITEM_200.holdEffect = 0, 0, "NONE"
  do
    local b = fresh()
    item(b, 0, 200)
    item(b, 1, 200)
    b.player.mon.hp = 90
    T.eq(heal(b, 0), false, "explicit NONE metadata disables the native trigger")
    local score = query(b, 1, 0, true, true, "live-metadata-cleared")
    T.eq(b._aiHistory, nil, "cleared effect cannot reveal an item")
    rows[#rows + 1] = { name = "live-metadata-cleared", score = score, hp = b.player.mon.hp }
  end
  raw[200].holdEffect, defs.ITEM_200.gen3HoldEffect, defs.ITEM_200.holdEffect = 43, 43, "LEFTOVERS"
  do
    local b, draws = fresh()
    item(b, 0, 200)
    b.player.mon.hp = 90
    heal(b, 0)
    item(b, 0, 196) -- A changed current item is not a new observation.
    local expected = version == "firered" and 43 or 0
    local score = query(b, 0, expected, true, true, "cached-effect-does-not-peek")
    local freshBattle = fresh()
    local unknown = query(freshBattle, 0, 0, true, true, "fresh-battle-isolation")
    T.eq(#draws, 0, "cached query is read-only")
    rows[#rows + 1] =
      { name = "cached-effect-does-not-peek", score = score, fresh = unknown, history = history(b) }
  end
  -- FireRed shares the player-side byte; Emerald's slots remain separate.
  do
    local b, draws = fresh()
    item(b, 0, 200)
    b.player.mon.hp = 90
    heal(b, 0)
    item(b, 2, 196)
    hit(b, 2, 10)
    local h = history(b)
    T.same(
      h,
      version == "firered" and { 39, 0, 0, 0 } or { 43, 0, 39, 0 },
      "native double-slot history ownership"
    )
    T.same(draws, { { 0, 99 } }, "only the actual Focus Band trigger rolls")
    rows[#rows + 1] = { name = "double-history-ownership", history = h, rng = draws }
  end
  do
    local b, draws = fresh()
    item(b, 0, 196)
    if source then
      NativeHeld.of(b.player, "check", b)
    else
      require("src.battle.HoldItems").effectOf(b.player, "check")
    end
    T.eq(b._aiHistory, nil, "pure held-item reads do not reveal effects")
    T.eq(#draws, 0, "pure held-item reads do not roll")
    rows[#rows + 1] = { name = "pure-held-read", history = history(b), rng = draws }
  end
  do
    local b, draws = fresh()
    b.battlers[3], b.sides[2].battlers[2] = nil, nil
    local score = query(b, 3, 0, false, true, "absent-partner-zero")
    T.eq(b._aiHistory, nil, "absent partner cannot create knowledge")
    T.eq(#draws, 0, "absent partner adds no RNG")
    rows[#rows + 1] = { name = "absent-partner-zero", score = score }
  end
  -- Emerald's second ITEM lookup must read current metadata, not fake zero.
  raw[43].holdEffect, defs.ITEM_43.gen3HoldEffect, defs.ITEM_43.holdEffect = 22, 22, "EVASION_UP"
  do
    local b = fresh()
    item(b, 0, 200)
    b.player.mon.hp = 90
    heal(b, 0)
    local expected = version == "emerald" and 22 or 43
    local score = query(b, 0, expected, true, true, "cached-byte-item-lookup")
    rows[#rows + 1] = { name = "cached-byte-item-lookup", score = score, expected = expected }
  end
  raw[43].holdEffect, defs.ITEM_43.gen3HoldEffect, defs.ITEM_43.holdEffect = 0, 0, "NONE"
  for i = #restores, 1, -1 do
    restores[i]()
  end
  return rows
end
return C
