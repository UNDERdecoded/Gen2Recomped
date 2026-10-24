-- Real BattleState constructors, selection, planning, action queue and EOT.
-- A registered enemy-action consumer supplies legal fixture choices; no owned
-- engine functions are replaced. Metadata cases inspect the planner's actual
-- queued entries (not full trainer item/switch controller behavior).
local M = {}
function M.run(version)
  local T = require("tests.modkit")
  local Version = require("src.core.GameVersion")
  local Battle = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local Save = require("src.core.SaveData")
  local Runtime = require("src.mods.Runtime")
  local Order = require("src.battle.Gen3AIOrder")
  local Events, Hooks = require("src.mods.Events"), require("src.mods.Hooks")
  local events, hooks = Events.new(), Hooks.new()
  local oldEvents, oldHooks, oldErrors = Runtime.events, Runtime.hooks, Runtime.errors
  Runtime.install(events, hooks)
  Version.set(version)
  local function setup(double, words, tie)
    local data = T.fixtures.fresh()
    data.constants.gen = 3
    data.constants.gen3BadgeFlags = { 0x820, 0x821, 0x822 }
    data.moves.ORDER_HIGH = require("src.mods.Merge").deepCopy(data.moves.FIX_TACKLE)
    data.moves.ORDER_HIGH.id, data.moves.ORDER_HIGH.priority = "ORDER_HIGH", 1
    data.items.ORDER_CLAW =
      { index = 217, holdEffect = "QUICK_CLAW", gen3HoldEffect = 26, holdEffectParam = 20 }
    local save = Save.newGame()
    save.party = { Pokemon.new(data, "FIXMON_A", 30) }
    local game = { data = data, save = save, stack = { top = function() end, push = function() end } }
    local b = Battle.newWild(game, "FIXMON_C", 30)
    b.double = double
    if double then
      b:placeBattler(2, Battle.makeBattler(data, Pokemon.new(data, "FIXMON_A", 30), true, save))
      b:placeBattler(3, Battle.makeBattler(data, Pokemon.new(data, "FIXMON_C", 30), false))
    end
    b:syncSides()
    b.queue, b.testChoices, b.testDraws, b.testWords, b.testComparisons, b.testMoves = {}, {}, {}, {}, {}, {}
    for _, actor in b:activeBattlers() do
      actor.mon.hp, actor.mon.stats.hp, actor.curStats.hp = 1000, 1000, 1000
      actor.mon.status, actor.mon.item, actor.abilityOverride = nil, nil, false
      actor.curStats.speed, actor.mon.stats.speed = 100, 100
      actor.curMoves = { { id = "FIX_TACKLE", pp = 100 } }
      actor.mon.moves = actor.curMoves
    end
    local wordIndex = 0
    b.rng = function(lo, hi)
      b.testDraws[#b.testDraws + 1] = { lo, hi }
      if lo == 0 and hi == 65535 then
        wordIndex = wordIndex + 1
        return words[wordIndex] or words[#words]
      end
      if lo == 0 and hi == 1 then
        return tie or 0
      end
      return lo
    end
    return b
  end
  hooks:wrap("battle.enemy_action", function(_, b, actor)
    T.eq(b._nativeOrderReady, true, "turn word prepared before public enemy-action consumer")
    b.testWords[#b.testWords + 1] = { actor.position, b.randomTurnNumber, b.turnCount or 0 }
    return b.testChoices[actor.position] or actor.curMoves[1]
  end, 0, "order-fixture")
  hooks:wrap("battle.turn_order", function(next, a, am, b, bm, ctx)
    local battle = ctx.battle
    T.eq(a, battle:battlerAt(a.position), "turn-order hook keeps native first actor")
    T.eq(b, battle:battlerAt(b.position), "turn-order hook keeps native second actor")
    battle.testComparisons[#battle.testComparisons + 1] = { a.position, b.position }
    return next(a, am, b, bm, ctx)
  end, 0, "order-fixture")
  events:on("battle.move_used", function(e)
    e.battle.testMoves[#e.battle.testMoves + 1] = e.user.position
  end, 0, "order-fixture")
  local function pump(b)
    local guard = 0
    while b.queue[1] and guard < 1000 do
      guard = guard + 1
      local row = table.remove(b.queue, 1)
      if row.fn then
        b.nextInsert = 0
        row.fn()
      end
    end
    T.check(guard < 1000, "real action queue drains")
  end
  local function scheduled(b)
    local ids = {}
    for _, row in ipairs(b.queue) do
      if row.fn then
        local n = 1
        while true do
          local name, entry = debug.getupvalue(row.fn, n)
          if not name then
            break
          end
          if name == "entry" then
            ids[#ids + 1] = entry[1].position
          end
          n = n + 1
        end
      end
    end
    return ids
  end
  local b = setup(false, { 0, 65535 })
  b.player.curStats.speed, b.enemy.curStats.speed = 10, 200
  b.player.mon.item = "ORDER_CLAW"
  T.eq(b:enemyAction(b.enemy), b.enemy.curMoves[1], "choice keeps native move handle")
  b:enemyAction(b.enemy)
  T.same(b.testDraws, { { 0, 65535 } }, "repeated selection shares one turn word")
  b:resolveTurn(b.player.curMoves[1])
  T.same(b.testDraws, { { 0, 65535 } }, "planner reuses selection word without separate claw roll")
  T.same(scheduled(b), { 0, 1 }, "successful claw is used by actual planner")
  pump(b)
  T.same(b.testMoves, { 0, 1 }, "successful claw reaches actual move execution")
  T.eq(b._nativeOrderReady, false, "EOT releases selection word")
  b.testMoves = {}
  b:resolveTurn(b.player.curMoves[1])
  T.eq(b.randomTurnNumber, 65535, "next actual turn samples fresh word")
  T.same(scheduled(b), { 1, 0 }, "failed claw follows physical speed")
  pump(b)
  T.same(b.testMoves, { 1, 0 }, "failed claw reaches actual move execution")

  local priority = setup(false, { 0 })
  priority.player.mon.item = "ORDER_CLAW"
  priority.testChoices[1] = { id = "ORDER_HIGH", pp = 10 }
  priority:resolveTurn(priority.player.curMoves[1])
  T.same(scheduled(priority), { 1, 0 }, "Quick Claw cannot override greater move priority")
  T.same(priority.testDraws, { { 0, 65535 } }, "unequal priorities do not draw a tie")

  local both = setup(false, { 0 }, 1)
  both.player.mon.item, both.enemy.mon.item = "ORDER_CLAW", "ORDER_CLAW"
  both:resolveTurn(both.player.curMoves[1])
  T.same(scheduled(both), { 1, 0 }, "two successful claws use native tie result")
  T.same(both.testDraws, { { 0, 65535 }, { 0, 1 } }, "shared claw word followed by one actual tie draw")

  local doubles = setup(true, { 0 }, 1)
  doubles.pendingActions = { [2] = doubles:battlerAt(2).curMoves[1] }
  doubles:resolveTurn(doubles.player.curMoves[1])
  T.same(scheduled(doubles), { 3, 2, 1, 0 }, "real double planner follows nested native comparisons")
  T.eq(#doubles.testComparisons, 6, "double planner invokes six actual comparison hooks")
  T.eq(#doubles.testDraws, 7, "double planner uses one word plus six tie draws")
  T.same(doubles.testWords, { { 1, 0, 0 }, { 3, 0, 0 } }, "both enemy choices precede new-turn flag reset")
  pump(doubles)
  T.same(doubles.testMoves, { 3, 2, 1, 0 }, "double order reaches actual action execution")

  local forwarded = setup(true, { 0 }, 1)
  forwarded.pendingActions = { [2] = forwarded:battlerAt(2).curMoves[1] }
  local undo = hooks:wrap("battle.turn_order", function(next, a, am, b, bm, ctx)
    if a == forwarded.player then
      local changed = require("src.mods.Merge").deepCopy(am)
      changed.priority = 7
      return next(a, changed, b, bm, ctx)
    end
    return next(a, am, b, bm, ctx)
  end, 10, "forwarding-fixture")
  forwarded:resolveTurn(forwarded.player.curMoves[1])
  T.same(scheduled(forwarded), { 0, 3, 2, 1 }, "double comparator honors forwarded hook arguments")
  T.eq(#forwarded.testDraws, 4, "forwarded priority suppresses only its own tie draws")
  undo()

  local meta = setup(true, { 0 }, 1)
  meta.testChoices[1] = { special = "aiItem", item = "POTION" }
  meta.pendingActions = { [2] = { special = "playerSwitch", mon = meta.player.mon } }
  meta:resolveTurn(meta.player.curMoves[1])
  T.same(scheduled(meta), { 1, 2, 3, 0 }, "item/switch stable prefix is preserved before move sorting")
  T.eq(#meta.testComparisons, 1, "metadata actions are never speed-compared")
  T.eq(#meta.testDraws, 2, "metadata actions consume no extra tie draws")

  local weather = setup(true, { 0 })
  weather.weather = "RAIN"
  weather.enemy.abilityOverride, weather.enemy.curStats.speed = "SWIFT_SWIM", 75
  weather:battlerAt(2).abilityOverride = "CLOUD_NINE"
  T.eq(Order.speed(weather.enemy, weather), 75, "real right-flank living ability suppresses weather")
  weather:battlerAt(2).mon.hp = 0
  T.eq(Order.speed(weather.enemy, weather), 150, "fainted right-flank ability does not suppress weather")
  weather.double = false
  weather:battlerAt(2).mon.hp = 1000
  T.eq(Order.speed(weather.enemy, weather), 150, "unused right-flank storage is ignored in singles")
  weather.game.save.flags = { FLAG_G3_0822 = true }
  T.eq(Order.speed(weather.player, weather), 110, "real save flag grants native third-badge boost")
  weather.gen3Frontier = true
  T.eq(
    Order.speed(weather.player, weather),
    version == "emerald" and 100 or 110,
    "actual frontier flag has profile-specific badge policy"
  )

  local planless = setup(false, { 10, 20 })
  planless:enemyAction(planless.enemy)
  planless:endOfTurn()
  planless:enemyAction(planless.enemy)
  T.eq(planless.randomTurnNumber, 20, "planless EOT releases word without relying on turn counters")
  Runtime.install(oldEvents, oldHooks, oldErrors)
end
return M
