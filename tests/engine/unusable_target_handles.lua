package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Targeting = require("src.battle.Targeting")
local Battle = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local Save = require("src.core.SaveData")
local Runtime = require("src.mods.Runtime")
local Events, Hooks = require("src.mods.Events"), require("src.mods.Hooks")
local oldEvents, oldHooks, oldErrors = Runtime.events, Runtime.hooks, Runtime.errors
local events, hooks = Events.new(), Hooks.new()
Runtime.install(events, hooks)
local values = {
  { name = "nil" },
  { name = "true", value = true },
  { name = "false", value = false },
  { name = "number", value = 3 },
  { name = "string", value = "enemy" },
  { name = "function", value = function() end },
}
local function setup(double)
  local data = T.fixtures.fresh()
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
  b.queue, b.testMoves, b.testRng = {}, {}, {}
  for _, who in b:activeBattlers() do
    who.mon.hp, who.mon.stats.hp, who.curStats.hp = 1000, 1000, 1000
    who.mon.status, who.abilityOverride, who.mon.item = nil, false, nil
    who.curStats.speed = 400 - who.position * 50
    who.curMoves = { { id = "FIX_TACKLE", pp = 100 } }
    who.mon.moves = who.curMoves
  end
  b.rng = function(lo, hi)
    b.testRng[#b.testRng + 1] = { lo, hi }
    return lo
  end
  return b
end
hooks:wrap("battle.enemy_action", function(_, _, actor)
  return actor.curMoves[1]
end, 0, "target-fixture")
events:on("battle.turn_started", function(e)
  if e.battle.testInvalidChoice then
    e.battle.chosenTargets = { [0] = e.battle.testInvalidChoice.value }
  end
end, 0, "target-fixture")
events:on("battle.move_used", function(e)
  e.battle.testMoves[#e.battle.testMoves + 1] = { e.user, e.target }
end, 0, "target-fixture")
local function protected(label, fn)
  local ok, result = pcall(fn)
  T.check(ok, label .. " completes without an indexing error: " .. tostring(ok and "ok" or result))
  return ok and result
end
local function run(version)
  require("src.core.GameVersion").set(version)
  for _, double in ipairs({ false, true }) do
    for _, spec in ipairs(values) do
      local b = setup(double)
      local targets = protected(spec.name .. " redirect", function()
        return Targeting.redirect(b, b.player, nil, spec.value)
      end)
      if targets then
        T.eq(targets[1], b.enemy, "unusable handle redirects to the first living foe")
      end
      T.eq(#b.testRng, 0, "redirection does not invent target RNG")
      targets = protected(spec.name .. " selected", function()
        return Targeting.resolve(b, b.player, {}, spec.value)
      end)
      if targets then
        T.eq(targets[1], b.enemy, "selected move follows ordinary missing-choice behavior")
      end
      b.player.thrashTarget = spec.value
      targets = protected(spec.name .. " random", function()
        return Targeting.resolve(b, b.player, { target = Targeting.RANDOM }, nil)
      end)
      if targets then
        T.eq(targets[1], b.enemy, "unusable rampage handle is replaced with a living foe")
        T.eq(b.player.thrashTarget, b.enemy, "new native rampage handle is retained")
      end
      local queued = setup(double)
      queued.testInvalidChoice = spec
      if double then
        queued.pendingActions = { [2] = queued:battlerAt(2).curMoves[1] }
      end
      protected(spec.name .. " actual move queue", function()
        queued:resolveTurn(queued.player.curMoves[1])
        local count = 0
        while queued.queue[1] and count < 1000 do
          count = count + 1
          local row = table.remove(queued.queue, 1)
          if row.fn then
            queued.nextInsert = 0
            row.fn()
          end
        end
        T.check(count < 1000, "ordinary turn queue drains")
        T.eq(#queued.testMoves, double and 4 or 2, "all native actions execute once")
        T.eq(queued.testMoves[1][1], queued.player, "native first actor is preserved")
        T.eq(queued.testMoves[1][2], queued.enemy, "actual attack uses the living fallback foe")
        T.eq(queued.player.curMoves[1].pp, 99, "actual move spends one PP")
      end)
    end
  end
  local live = setup(true)
  local partner, rightFoe = live:battlerAt(2), live:battlerAt(3)
  T.eq(
    Targeting.redirect(live, live.player, nil, partner)[1],
    partner,
    "valid ally keeps its exact native handle"
  )
  T.eq(
    Targeting.resolve(live, live.player, {}, rightFoe)[1],
    rightFoe,
    "valid selected foe keeps its native handle"
  )
  live.player.thrashTarget = rightFoe
  T.eq(
    Targeting.resolve(live, live.player, { target = Targeting.RANDOM })[1],
    rightFoe,
    "live rampage handle remains locked"
  )
  T.eq(#live.testRng, 0, "live rampage lock does not reroll")
  live.enemy.mon.hp = 0
  T.eq(
    Targeting.redirect(live, live.player, nil, live.enemy)[1],
    rightFoe,
    "fainted foe redirects to its living partner"
  )
  partner.mon.hp = 0
  T.eq(
    #Targeting.redirect(live, live.player, nil, partner),
    0,
    "fainted ally never redirects an ally action to an enemy"
  )
  rightFoe.mon.hp = 0
  T.eq(#Targeting.redirect(live, live.player, nil, true), 0, "empty opposing side has no fabricated target")
  T.eq(
    #Targeting.resolve(live, live.player, { target = Targeting.RANDOM }),
    0,
    "empty opposing side cannot reroll a rampage target"
  )
  T.eq(
    Targeting.resolve(live, live.player, { target = Targeting.USER }, true)[1],
    live.player,
    "self-target rule remains native"
  )
  T.eq(
    #Targeting.resolve(live, live.player, { target = Targeting.OPPONENTS_FIELD }, true),
    0,
    "field-target rule remains native"
  )
end
for _, version in ipairs({ "red", "gold", "firered", "emerald" }) do
  run(version)
end
Runtime.install(oldEvents, oldHooks, oldErrors)
T.finish("unusable target handles")
