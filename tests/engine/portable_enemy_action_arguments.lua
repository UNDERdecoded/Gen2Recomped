package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  require("tests.enemy_actions.arguments").run(".", "gen2", version)
end
local function setup(f, double)
  local c = f.fresh("TACKLE", { enemy = true })
  local b = c.battle
  b.double = double
  if double then
    local Battle, Merge = require("src.battle.BattleState"), require("src.mods.Merge")
    b:placeBattler(2, Battle.makeBattler(f.data, Merge.deepCopy(b.player.mon), true))
    b:placeBattler(3, Battle.makeBattler(f.data, Merge.deepCopy(b.enemy.mon), false))
  end
  b:syncSides()
  return b
end
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" } }) do
    local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, mode[1], mode[2])
    local b = setup(f, true)
    for _, actor in ipairs({ b.enemy, b:battlerAt(3) }) do
      local seen
      f.e.choose(function(nextAction, battle, who)
        T.eq(battle, b, "legacy opaque battle remains identical")
        seen = who
        if mode[2] == "native" then
          T.eq(who, actor, "API-1/2 native actor identity is preserved")
        else
          T.neq(who, actor, "API-2 unified actor remains detached")
          T.eq(who.side, "enemy", "API-2 unified actor keeps side")
          T.eq(who.mon.species, "CHARMANDER", "API-2 unified actor keeps canonical Pokemon")
        end
        return nextAction(battle, who)
      end)
      local action = b:enemyAction(actor)
      T.eq(type(seen), "table", "existing API-1/2 argument contract stays a record")
      T.eq(action, actor.curMoves[1], "legacy native choice handle is preserved")
    end
    f.close()
  end
  for _, double in ipairs({ false, true }) do
    local f = require("tests.enemy_actions.fixture").new(".", "gen2", version, 3, "unified")
    local b, seen, native = setup(f, double), {}, {}
    f.e.choose(function(nextAction, battle, id)
      seen[#seen + 1] = id == nil and "nil" or id
      return nextAction(battle, id)
    end)
    local stop = f.result.loader.hooks:wrap("battle.enemy_action", function(nextAction, battle, actor, ...)
      T.eq(select("#", ...), 0, "mixed native callback retains arity")
      T.eq(battle, b, "mixed native callback retains battle")
      T.check(actor == b.enemy or actor == b:battlerAt(3), "mixed native callback receives actual actor")
      native[#native + 1] = actor
      return nextAction(battle, actor)
    end, -100, "native-argument-fixture")
    if double then
      b.pendingActions = { [2] = b:battlerAt(2).curMoves[1] }
    end
    b.queue = {}
    b:resolveTurn(b.player.curMoves[1])
    local count = 0
    while b.queue[1] and count < 1000 do
      count = count + 1
      local row = table.remove(b.queue, 1)
      if row.fn then
        b.nextInsert = 0
        row.fn()
      end
    end
    T.check(count < 1000, "actual native turn queue completes")
    T.same(
      seen,
      double and { 1, 3 } or { "nil" },
      "actual controller publishes shared single/double selectors"
    )
    T.eq(#native, double and 2 or 1, "each native enemy choice runs once")
    T.eq(native[1], b.enemy, "mixed native callback retains left actor identity")
    if double then
      T.eq(native[2], b:battlerAt(3), "mixed native callback retains right actor identity")
    end
    for _, actor in b:activeBattlers() do
      T.eq(actor.curMoves[1].pp, 9, "actual controller spends each actor's PP exactly once")
    end
    stop()
    if not double then
      local entered = 0
      b.kind, b.trainer =
        "trainer", {
          brain = function()
            entered = entered + 1
            error("intentional native brain failure")
          end,
        }
      local ok = pcall(b.enemyAction, b)
      T.check(not ok, "native AI failure reaches the caller")
      T.eq(entered, 1, "native AI failure is not retried")
      b.kind, b.trainer = "wild", nil
      local later
      f.e.choose(function(_, battle, id)
        later = id
        return "SCRATCH"
      end)
      local result = f.result.loader.hooks:call("battle.enemy_action", function()
        error("must not delegate")
      end, b, b.enemy)
      T.eq(later, 1, "failed request leaves no stale default-selector scope")
      T.eq(result, "SCRATCH", "independent native hook invocation still completes")
    end
    f.close()
  end
end
T.finish("portable enemy action arguments")
