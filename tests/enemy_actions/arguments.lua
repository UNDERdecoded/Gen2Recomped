local M = {}
function M.run(root, backend, version)
  local f = dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified")
  local T, observations = f.T, {}
  local function setup(double)
    local c = f.fresh("TACKLE", { enemy = true })
    local b = c.battle
    b.double = double
    if backend == "gen1" then
      if double then
        local State = require("src.core.game3.battle.state")
        b.battlers[2] =
          State.makeBattler(require("src.mods.Merge").deepCopy(b.player.mon), "player", { id = 2 })
        b.battlers[3] =
          State.makeBattler(require("src.mods.Merge").deepCopy(b.enemy.mon), "enemy", { id = 3 })
      end
    elseif double then
      local Battle = require("src.battle.BattleState")
      b:placeBattler(2, Battle.makeBattler(f.data, require("src.mods.Merge").deepCopy(b.player.mon), true))
      b:placeBattler(3, Battle.makeBattler(f.data, require("src.mods.Merge").deepCopy(b.enemy.mon), false))
    end
    if backend == "gen2" then
      b:syncSides()
    end
    for id = 0, double and 3 or 1 do
      local actor = backend == "gen1" and b.battlers[id] or b:battlerAt(id)
      if backend == "gen1" then
        actor.mon.moves, actor.mon.pp = { 33, 10 }, { 10, 7 }
      else
        actor.curMoves = { { id = f.ids.TACKLE, pp = 10 }, { id = f.ids.SCRATCH, pp = 7 } }
        actor.mon.moves = actor.curMoves
      end
    end
    return c, b
  end
  local function actorAt(b, id)
    return backend == "gen1" and b.battlers[id] or b:battlerAt(id)
  end
  local function choose(b, id)
    if backend == "gen1" then
      return require("src.core.game3.battle.commands").enemyAction(b, id)
    end
    return b:enemyAction(id ~= nil and actorAt(b, id) or nil)
  end
  local function number(a)
    if backend == "gen1" then
      return require("src.mods.Gen3Compat").moveId(a.move)
    end
    return f.data.moves[a.id].index
  end
  local function pp(actor)
    if backend == "gen1" then
      return { unpack(actor.mon.pp) }
    end
    local out = {}
    for i, move in ipairs(actor.curMoves) do
      out[i] = move.pp
    end
    return out
  end
  local function execute(b, id, a)
    local actor, target = actorAt(b, id), actorAt(b, 0)
    if backend == "gen1" then
      require("src.core.game3.battle.engine").resolveMove(
        actor,
        target,
        a.move,
        a.slot,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      b:executeAction(actor, target, a)
    end
  end
  for _, double in ipairs({ false, true }) do
    for _, spec in ipairs({
      { name = "default" },
      { name = "explicit-left", id = 1 },
      { name = "explicit-right", id = 3 },
    }) do
      if double or spec.id ~= 3 then
        for _, forwarding in ipairs({ "replace", "by-position", "forward", "zero-next", "omit-battler" }) do
          local c, b = setup(double)
          local seen = {}
          f.e.choose(function(nextAction, battle, id, ...)
            T.eq(select("#", ...), 0, "native hook arity is preserved")
            T.eq(battle, b, "opaque battle handle is preserved")
            seen[#seen + 1] = id == nil and "nil" or type(id) == "number" and id or type(id)
            if forwarding == "forward" then
              return nextAction(battle, id)
            end
            if forwarding == "zero-next" then
              return nextAction()
            end
            if forwarding == "omit-battler" then
              return nextAction(battle)
            end
            return { move = forwarding == "by-position" and id ~= 3 and "TACKLE" or "SCRATCH" }
          end)
          local action = choose(b, spec.id)
          local label = backend
            .. "/"
            .. version
            .. "/"
            .. tostring(double)
            .. "/"
            .. spec.name
            .. "/"
            .. forwarding
          T.same(seen, { spec.id == nil and "nil" or spec.id }, label .. " publishes numeric/nil request")
          local scratch = forwarding == "replace" or (forwarding == "by-position" and spec.id == 3)
          T.eq(number(action), scratch and 10 or 33, label .. " returns actual choice")
          local id = spec.id or 1
          execute(b, id, action)
          local expected = scratch and { 10, 6 } or { 9, 7 }
          T.same(pp(actorAt(b, id)), expected, label .. " spends caller PP")
          local other = double and actorAt(b, id == 1 and 3 or 1)
          if other then
            T.same(pp(other), { 10, 7 }, label .. " preserves other flank PP")
          end
          observations[#observations + 1] = {
            double = double,
            case = spec.name,
            forwarding = forwarding,
            seen = seen,
            move = number(action),
            pp = pp(actorAt(b, id)),
            other = other and pp(other) or nil,
          }
        end
      end
    end
  end
  for _, spec in ipairs({
    { name = "explicit-left", initial = 3, forwarded = 1 },
    { name = "explicit-right", initial = 1, forwarded = 3 },
    { name = "omit", initial = 3 },
    { name = "explicit-from-default", forwarded = 1 },
  }) do
    local _, b = setup(true)
    local trace = {}
    f.e.choose(function(_, battle, id)
      T.eq(battle, b, "downstream public callback retains opaque handle")
      trace[#trace + 1] = id == nil and "nil" or id
      return { move = id == 3 and "SCRATCH" or "TACKLE" }
    end)
    local stop = f.e.api.hooks:wrap("battle.enemy_action", function(nextAction, battle, id)
      trace[#trace + 1] = id == nil and "nil" or id
      return nextAction(battle, spec.forwarded)
    end, 100)
    local action = choose(b, spec.initial)
    stop()
    T.same(
      trace,
      { spec.initial == nil and "nil" or spec.initial, spec.forwarded == nil and "nil" or spec.forwarded },
      "nested next preserves explicit/default selector"
    )
    local scratch = spec.forwarded == 3
    T.eq(number(action), scratch and 10 or 33, "nested numeric selector affects actual move")
    execute(b, spec.initial or 1, action)
    T.same(
      pp(actorAt(b, spec.initial or 1)),
      scratch and { 10, 6 } or { 9, 7 },
      "forwarded choice spends the caller's actual PP"
    )
    observations[#observations + 1] = {
      case = "nested-" .. spec.name,
      seen = trace,
      move = number(action),
      pp = pp(actorAt(b, spec.initial or 1)),
    }
  end
  -- Query native AI for the other flank, then execute as the original caller.
  -- Native source planning keeps the caller while using the delegated slot.
  local _, foreign = setup(true)
  local right = actorAt(foreign, 3)
  if backend == "gen1" then
    right.mon.moves, right.mon.pp = { 10 }, { 5 }
  else
    right.curMoves = { { id = f.ids.SCRATCH, pp = 5 } }
    right.mon.moves = right.curMoves
  end
  f.e.choose(function(nextAction, battle)
    return nextAction(battle, 3)
  end)
  local choice = choose(foreign, 1)
  T.eq(number(choice), 10, "forwarded native AI selects the right flank's actual move")
  execute(foreign, 1, choice)
  T.same(pp(actorAt(foreign, 1)), { 9, 7 }, "delegated native slot spends caller PP")
  T.same(pp(right), { 5 }, "delegated native query does not spend queried actor PP")
  observations[#observations + 1] =
    { case = "foreign-native", move = number(choice), pp = pp(actorAt(foreign, 1)), other = pp(right) }

  local _, reentrant = setup(true)
  local trace, active = {}, false
  f.e.choose(function(nextAction, battle, id)
    trace[#trace + 1] = id == nil and "nil" or id
    if not active then
      active = true
      local inner = choose(battle, 3)
      T.eq(number(inner), 33, "reentrant request completes native selection")
      active = false
    end
    return nextAction(battle, id)
  end)
  local result = choose(reentrant)
  T.same(trace, { "nil", 3 }, "reentrant native requests preserve both public selectors")
  execute(reentrant, 1, result)
  T.same(pp(actorAt(reentrant, 1)), { 9, 7 }, "outer request retains caller PP after reentry")
  T.same(pp(actorAt(reentrant, 3)), { 10, 7 }, "nested query is read-only until execution")
  observations[#observations + 1] =
    { case = "reentry", seen = trace, pp = pp(actorAt(reentrant, 1)), other = pp(actorAt(reentrant, 3)) }
  f.close()
  return observations
end
return M
