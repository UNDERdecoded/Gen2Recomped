-- Unchanged legacy callback handles and learned records survive a native
-- wild target selection; private planning fields still drive actual execution.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
for _, version in ipairs({ "firered", "emerald" }) do
  for _, mode in ipairs({ { 1, "native" }, { 2, "native" }, { 2, "unified" }, { 3, "unified" } }) do
    local f = dofile("tests/enemy_actions/choice_band.lua").fixture(
      ".",
      "gen2",
      version,
      { api = mode[1], format = mode[2] }
    )
    local b = f.field(true)
    local user, right = b.enemy, b:battlerAt(2)
    b.rng = function(lo, hi)
      return hi == 65535 and 2 or lo
    end
    local before = require("src.mods.Merge").deepCopy(user.curMoves[1])
    f.e.choose(function(nextAction, ...)
      return nextAction(...)
    end)
    f.e.api.hooks:wrap("battle.crit", function()
      return false
    end)
    local action = b:enemyAction(user)
    if mode[1] < 3 then
      T.eq(action, user.curMoves[1], "forwarding retains the actual legacy learned-slot handle")
    else
      T.neq(action, user.curMoves[1], "API-3 retains its separate native action and positional target")
      T.eq(action.target, 2, "API-3 exposes the positional target before execution")
    end
    T.same(user.curMoves[1], before, "native target/scores never enter party move records")
    local planned = require("src.battle.Gen3ChoiceBand").plan(b, user, action)
    T.eq(planned.target, 2, "private native target survives forwarding and planning")
    T.eq(planned.slot, 1, "private native slot survives forwarding and planning")
    T.same(planned.scores, { 0, 0, 0, 0 }, "native wild scores survive forwarding")
    b:executeAction(user, b.player, planned)
    T.check(right.mon.hp < 400, "actual execution hits the selected opposite right flank")
    T.eq(b.player.mon.hp, 400, "actual execution preserves the unselected left flank")
    T.eq(user.curMoves[1].pp, 9, "actual execution spends the original learned PP")
    T.eq(user.curMoves[1].target, nil, "consuming the private target preserves party shape")
    T.eq(#f.result.errors, 0, "every callback level forwards without errors")
    f.close()
  end
  do
    local f = dofile("tests/enemy_actions/choice_band.lua").fixture(".", "gen2", version)
    local b = f.field(false)
    b.ruleset = require("src.mods.Merge").deepCopy(b.ruleset)
    b.ruleset.enemyUnlimitedPP = true
    f.hold(b.enemy, 186)
    b.enemy.choicedMove = 33
    for _, slot in ipairs(b.enemy.curMoves) do
      slot.pp = 0
    end
    b.rng = function(lo)
      return lo
    end
    T.eq(
      b:vanillaEnemyAction(b.enemy).id,
      f.ids.TACKLE,
      "explicit unlimited enemy policy admits dry learned moves"
    )
    local planned = require("src.battle.Gen3ChoiceBand").plan(b, b.enemy, b.enemy.curMoves[2])
    T.eq(planned.id, f.ids.TACKLE, "explicit unlimited enemy policy retains the choice lock")
    b:executeAction(b.enemy, b.player, planned)
    T.check(b.player.mon.hp < 400, "explicit unlimited enemy policy executes the dry selected move")
    T.eq(b.enemy.curMoves[1].pp, 0, "explicit unlimited enemy policy preserves dry PP")
    f.close()
  end
  do
    local f = dofile("tests/enemy_actions/choice_band.lua").fixture(".", "gen2", version)
    local b, checks, trace = f.field(true), {}, {}
    for _, actor in b:activeBattlers() do
      f.hold(actor, 186)
      actor.choicedMove = 33
    end
    b.pendingActions = { [2] = b:battlerAt(2).curMoves[1] }
    f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
      trace[#trace + 1] = {
        holder = ctx.mon.nickname,
        trigger = ctx.trigger,
        item = ctx.item,
        effect = ctx.effect,
        parameter = ctx.parameter,
      }
      if ctx.trigger == "check" then
        checks[#checks + 1] = ctx.mon.nickname
      end
      return nextRead(ctx)
    end)
    b:resolveTurn(b.player.curMoves[1])
    -- AI masks for the two enemy actors precede one planner query per slot.
    T.same(
      checks,
      { "P1", "P3", "P0", "P1", "P2", "P3" },
      "actual doubles plans each actor once in native slot order"
    )
    print(
      "CHOICE_DOUBLE_PLANNING_READS " .. require("src.link.Json").encode({ version = version, trace = trace })
    )
    T.eq(#f.result.errors, 0, "actual double planning callbacks remain error-free")
    f.close()
  end
end
T.finish("native GBA choice planning retains legacy handles and targets")
