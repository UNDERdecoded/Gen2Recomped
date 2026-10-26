local M = {}
function M.run(root, backend, version)
  local f = dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified")
  local T, observations = f.T, {}
  local used = {}
  local stopUsed = f.e.api.events:on("battle.move_used", function(event)
    used[#used + 1] = event.move.id
  end)
  local function actorAt(b, id)
    return backend == "gen1" and b.battlers[id] or b:battlerAt(id)
  end
  local function setup(double, move)
    local c = f.fresh(move or "TACKLE", { enemy = true })
    local b = c.battle
    b.double = double
    if double then
      if backend == "gen1" then
        local S, Copy = require("src.core.game3.battle.state"), require("src.mods.Merge").deepCopy
        b.battlers[2] = S.makeBattler(Copy(b.player.mon), "player", { id = 2 })
        b.battlers[3] = S.makeBattler(Copy(b.enemy.mon), "enemy", { id = 3 })
      else
        local S, Copy = require("src.battle.BattleState"), require("src.mods.Merge").deepCopy
        b:placeBattler(2, S.makeBattler(f.data, Copy(b.player.mon), true))
        b:placeBattler(3, S.makeBattler(f.data, Copy(b.enemy.mon), false))
      end
    end
    if backend == "gen2" then
      b:syncSides()
    end
    if not move then
      for id = 0, double and 3 or 1 do
        local actor = actorAt(b, id)
        if backend == "gen1" then
          actor.mon.moves, actor.mon.pp = { 33, 10 }, { 10, 7 }
        else
          actor.curMoves = { { id = f.ids.TACKLE, pp = 10 }, { id = f.ids.SCRATCH, pp = 7 } }
          actor.mon.moves = actor.curMoves
        end
      end
    end
    return c, b
  end
  local function choose(b, id)
    if backend == "gen1" then
      return require("src.core.game3.battle.commands").enemyAction(b, id)
    end
    return b:enemyAction(id and actorAt(b, id) or nil)
  end
  local function execute(b, id, action)
    local user, target = actorAt(b, id), actorAt(b, 0)
    if backend == "gen1" then
      require("src.core.game3.battle.engine").resolveMove(
        user,
        target,
        action.move,
        action.slot,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      b:executeAction(user, target, action)
    end
  end
  local function pp(actor)
    if backend == "gen1" then
      return { unpack(actor.mon.pp) }
    end
    local rows = {}
    for i, move in ipairs(actor.curMoves) do
      rows[i] = move.pp
    end
    return rows
  end
  local function snapshot(action)
    return {
      kind = action.kind,
      move = action.move,
      slot = action.slot,
      user = action.user,
      battler = action.battler,
      targetType = action.targetType,
    }
  end
  for _, double in ipairs({ false, true }) do
    for _, spec in ipairs({ { name = "default" }, { name = "left", id = 1 }, { name = "right", id = 3 } }) do
      if double or spec.id ~= 3 then
        for _, mode in ipairs({ "forward", "edit", "copy-edit", "slot" }) do
          local c, b = setup(double)
          local seen
          f.e.choose(function(nextAction, ...)
            local action = nextAction(...)
            seen = snapshot(action)
            if mode == "copy-edit" then
              local copied = snapshot(action)
              copied.move = 10
              return copied
            end
            if mode == "edit" and action.kind == "move" and action.move == 33 then
              action.move = 10
            end
            if mode == "slot" then
              action.slot = 2
            end
            return action
          end)
          local action = choose(b, spec.id)
          local expected = {
            kind = "move",
            move = 33,
            slot = 1,
            user = "enemy",
            battler = double and (spec.id or 1) or spec.id,
            targetType = double and 0 or nil,
          }
          local label = backend
            .. "/"
            .. version
            .. "/"
            .. tostring(double)
            .. "/"
            .. spec.name
            .. "/"
            .. mode
          T.same(seen, expected, label .. " exposes common native move fields")
          used = {}
          execute(b, spec.id or 1, action)
          T.eq(
            used[#used],
            (mode == "edit" or mode == "copy-edit") and "SCRATCH" or "TACKLE",
            label .. " executes the selected move through the public event producer"
          )
          local want = (mode == "copy-edit" or mode == "slot") and { 10, 6 } or { 9, 7 }
          T.same(pp(actorAt(b, spec.id or 1)), want, label .. " preserves native selected-slot PP semantics")
          T.check(c.hp() < 400, label .. " actually executes the action")
          observations[#observations + 1] = {
            double = double,
            case = spec.name,
            mode = mode,
            seen = seen,
            pp = pp(actorAt(b, spec.id or 1)),
            hit = c.hp() < 400,
            used = used[#used],
          }
        end
      end
    end
  end
  for _, row in ipairs({
    { field = "move", value = 10 },
    { field = "move", value = "SCRATCH" },
    { field = "id", value = 10 },
    { field = "id", value = "SCRATCH" },
  }) do
    local _, b = setup(false)
    f.e.choose(function()
      return { [row.field] = row.value }
    end)
    local seen
    local stop = f.e.api.hooks:wrap("battle.enemy_action", function(nextAction, ...)
      local action = nextAction(...)
      seen = { kind = action.kind, field = action[row.field], fieldType = type(action[row.field]) }
      return action
    end, 100)
    local action = choose(b, 1)
    stop()
    T.same(
      seen,
      { field = row.value, fieldType = type(row.value) },
      "nested authored record preserves reference form"
    )
    used = {}
    execute(b, 1, action)
    T.eq(used[#used], "SCRATCH", "nested authored record executes the requested move")
    T.same(pp(actorAt(b, 1)), { 10, 6 }, "nested authored record selects the actual learned slot")
    observations[#observations + 1] =
      { case = "authored-" .. row.field, value = row.value, seen = seen, pp = pp(actorAt(b, 1)) }
  end
  for _, value in ipairs({ 10, "SCRATCH" }) do
    local _, b = setup(false)
    f.e.choose(function(nextAction, ...)
      local action = nextAction(...)
      action.move = value
      return action
    end)
    local seen
    local stop = f.e.api.hooks:wrap("battle.enemy_action", function(nextAction, ...)
      local action = nextAction(...)
      seen = action.move
      return action
    end, 100)
    local action = choose(b, 1)
    stop()
    T.eq(seen, value, "nested native edit preserves the submitted move reference")
    used = {}
    execute(b, 1, action)
    T.eq(used[#used], "SCRATCH", "nested native edit executes the requested move")
    T.same(pp(actorAt(b, 1)), { 9, 7 }, "nested native edit retains the original selected PP slot")
    observations[#observations + 1] =
      { case = "native-edit", value = value, seen = seen, used = used[#used], pp = pp(actorAt(b, 1)) }
  end
  local _, paired = setup(false)
  f.e.choose(function()
    return { kind = "move", move = 10, id = "TACKLE" }
  end)
  local both
  local stopBoth = f.e.api.hooks:wrap("battle.enemy_action", function(nextAction, ...)
    local action = nextAction(...)
    both = { kind = action.kind, move = action.move, id = action.id }
    return action
  end, 100)
  local pairedChoice = choose(paired, 1)
  stopBoth()
  T.same(
    both,
    { kind = "move", move = 10, id = "TACKLE" },
    "both authored references retain independent forms"
  )
  used = {}
  execute(paired, 1, pairedChoice)
  T.eq(used[#used], "SCRATCH", "explicit move takes precedence over the legacy id alias")
  T.same(pp(paired.enemy), { 10, 6 }, "two-reference record charges the actual selected move slot")
  observations[#observations + 1] =
    { case = "both-references", seen = both, pp = pp(paired.enemy), used = used[#used] }
  local charging, b = setup(false, "FLY")
  local seen = {}
  f.e.choose(function(nextAction, ...)
    local action = nextAction(...)
    seen[#seen + 1] = snapshot(action)
    return action
  end)
  execute(b, 1, choose(b))
  if backend == "gen2" then
    b.enemy.chargeReady = true
  end
  execute(b, 1, choose(b))
  T.same(seen, {
    { kind = "move", move = 19, slot = 1, user = "enemy" },
    { kind = "move", move = 19, slot = 1, user = "enemy" },
  }, "charge continuation exposes common move fields")
  T.eq(charging.pp(), 9, "public charge record retains once-only PP ownership")
  T.check(charging.hp() < 400, "public charge record actually releases")
  observations[#observations + 1] =
    { case = "charge", seen = seen, pp = charging.pp(), hit = charging.hp() < 400 }
  local exhausted, exhaustedBattle = setup(false)
  if backend == "gen1" then
    exhaustedBattle.enemy.mon.pp = { 0, 0 }
  else
    for _, move in ipairs(exhaustedBattle.enemy.curMoves) do
      move.pp = 0
    end
  end
  local struggleView
  f.e.choose(function(nextAction, ...)
    local action = nextAction(...)
    struggleView = snapshot(action)
    return action
  end)
  local struggle = choose(exhaustedBattle)
  T.same(
    struggleView,
    { kind = "move", move = "STRUGGLE", user = "enemy" },
    "native exhausted fallback retains the reference's symbolic Struggle move"
  )
  used = {}
  execute(exhaustedBattle, 1, struggle)
  T.eq(used[#used], "STRUGGLE", "exhausted fallback executes actual Struggle")
  T.same(pp(exhaustedBattle.enemy), { 0, 0 }, "Struggle cannot spend exhausted party PP")
  T.check(exhausted.hp() < 400, "Struggle fallback actually hits")
  observations[#observations + 1] = {
    case = "struggle",
    seen = struggleView,
    pp = pp(exhaustedBattle.enemy),
    used = used[#used],
    hit = exhausted.hp() < 400,
  }
  stopUsed()
  f.close()
  return observations
end
return M
