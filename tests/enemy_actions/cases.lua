local M = {}
function M.run(root, backend, version, api, format)
  local f = dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, api, format)
  local T, observations = f.T, {}
  local function fresh()
    local c = f.fresh("TACKLE", { enemy = true })
    local u = c.battle.enemy
    if backend == "gen1" then
      u.mon.moves, u.mon.pp, u.mon.maxPp = { 33, 10, 10 }, { 10, 7, 5 }, { 10, 10, 10 }
    else
      u.curMoves = {
        { id = f.ids.TACKLE, pp = 10 },
        { id = f.ids.SCRATCH, pp = 7 },
        { id = f.ids.SCRATCH, pp = 5 },
      }
      u.mon.moves = u.curMoves
    end
    return c, u
  end
  local function pp(u)
    if backend == "gen1" then
      return { unpack(u.mon.pp) }
    end
    local out = {}
    for i, row in ipairs(u.curMoves) do
      out[i] = row.pp
    end
    return out
  end
  local function number(action)
    if backend == "gen1" then
      return require("src.mods.Gen3Compat").moveId(action.move)
    end
    local row = f.data.moves[action.id]
    return row and row.index
  end
  local function execute(b, a)
    if backend == "gen1" then
      require("src.core.game3.battle.engine").resolveMove(
        b.enemy,
        b.player,
        a.move,
        a.slot,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      b:executeAction(b.enemy, b.player, a)
    end
  end
  local function choose(b)
    if backend == "gen1" then
      return require("src.core.game3.battle.commands").enemyAction(b, 1)
    end
    return b:enemyAction(b.enemy)
  end
  local specs = {
    {
      "name",
      function()
        return "SCRATCH"
      end,
    },
    {
      "number",
      function()
        return 10
      end,
    },
    {
      "numeric-string",
      function()
        return "10"
      end,
    },
    {
      "move-record",
      function()
        return { kind = "move", move = "SCRATCH" }
      end,
    },
    {
      "numeric-record",
      function()
        return { move = 10 }
      end,
    },
    {
      "numeric-string-record",
      function()
        return { move = "10" }
      end,
    },
    {
      "lowercase-name",
      function()
        return "scratch"
      end,
    },
    {
      "lowercase-record",
      function()
        return { move = "scratch" }
      end,
    },
    {
      "numeric-id",
      function()
        return { id = 10 }
      end,
    },
    {
      "id-record",
      function()
        return { id = "SCRATCH" }
      end,
    },
    {
      "wrong-slot",
      function()
        return { move = "SCRATCH", slot = 1 }
      end,
    },
    {
      "duplicate-slot",
      function()
        return { move = "SCRATCH", slot = 3 }
      end,
      3,
    },
    {
      "fractional-slot",
      function()
        return { move = "SCRATCH", slot = 1.5 }
      end,
    },
    {
      "forged-pp",
      function()
        return { id = "SCRATCH", pp = 900 }
      end,
    },
    {
      "nil",
      function()
        return nil
      end,
      1,
    },
    {
      "false",
      function()
        return false
      end,
      1,
    },
    {
      "unknown",
      function()
        return "NO_SUCH_MOVE"
      end,
      1,
    },
    {
      "forward",
      function(nextAction, ...)
        return nextAction(...)
      end,
      1,
    },
    {
      "omitted-battler",
      function(nextAction, battle)
        return nextAction(battle)
      end,
      1,
    },
    {
      "delegate-nil",
      function(nextAction, ...)
        nextAction(...)
        return nil
      end,
      1,
    },
    {
      "delegate-false",
      function(nextAction, ...)
        nextAction(...)
        return false
      end,
      1,
    },
    {
      "delegate-move",
      function(nextAction, ...)
        local action = nextAction(...)
        action.move = "SCRATCH"
        return action
      end,
      1,
    },
  }
  for _, spec in ipairs(specs) do
    local label = backend .. "/" .. version .. "/" .. api .. "/" .. spec[1]
    local c, u = fresh()
    local oldHp = c.hp()
    f.e.choose(spec[2])
    local ok, action = pcall(choose, c.battle)
    T.check(ok and type(action) == "table", label .. " produces an executable record")
    if ok and type(action) == "table" then
      local slot = spec[3] or 2
      local expected = slot == 1 and spec[1] ~= "delegate-move" and 33 or 10
      T.eq(number(action), expected, label .. " selects the requested move rather than fallback")
      local ran, err = pcall(execute, c.battle, action)
      T.check(ran, label .. " executes: " .. tostring(err))
      T.check(c.hp() < oldHp, label .. " damages the real opponent")
      local want = { 10, 7, 5 }
      want[slot] = want[slot] - 1
      T.same(pp(u), want, label .. " decrements only the owned slot")
      local learned = backend == "gen1" and u.mon.moves[1] or f.data.moves[u.curMoves[1].id].index
      T.eq(learned, 33, label .. " does not rewrite learned moves")
      observations[#observations + 1] =
        { case = spec[1], move = number(action), pp = pp(u), hit = c.hp() < oldHp, learned = learned }
    end
  end
  -- Two hooks exercise translation of a scalar through next(), not only the final return.
  local c, u = fresh()
  f.e.choose(function()
    return 10
  end)
  local stop = f.e.api.hooks:wrap("battle.enemy_action", function(nextAction, ...)
    return nextAction(...)
  end, 100)
  local a = choose(c.battle)
  T.eq(number(a), 10, "nested hook retains numeric move choice")
  execute(c.battle, a)
  T.same(pp(u), { 10, 6, 5 }, "nested hook retains actual PP ownership")
  stop()
  local unlearned, actor = fresh()
  if backend == "gen1" then
    actor.mon.moves, actor.mon.pp = { 33 }, { 10 }
  else
    actor.curMoves = { actor.curMoves[1] }
    actor.mon.moves = actor.curMoves
  end
  f.e.choose(function()
    return { move = "SCRATCH" }
  end)
  local outside = choose(unlearned.battle)
  T.eq(number(outside), 10, "declared unlearned move is selected")
  execute(unlearned.battle, outside)
  T.eq(unlearned.pp(), 10, "unlearned move cannot consume a different learned slot")
  T.check(unlearned.hp() < 400, "unlearned declared move actually executes")
  observations[#observations + 1] = { case = "unlearned", pp = pp(actor), hit = unlearned.hp() < 400 }

  -- A hook-created charge action must survive the native continuation by identity.
  local charging = f.fresh("FLY", { enemy = true })
  f.e.choose(function()
    return { move = "FLY" }
  end)
  local first = choose(charging.battle)
  execute(charging.battle, first)
  T.check(charging.charging(), "public charge choice enters native charge state")
  T.eq(charging.pp(), 9, "charge spends owned PP once")
  T.eq(charging.hp(), 400, "charge turn does not damage the target")
  if backend == "gen2" then
    charging.battle.enemy.chargeReady = true
  end
  f.e.choose(nil)
  local second = choose(charging.battle)
  if backend == "gen2" then
    T.eq(first, second, "native charge continuation retains identity")
  end
  execute(charging.battle, second)
  T.check(not charging.charging(), "native continuation releases the charge")
  T.eq(charging.pp(), 9, "charge continuation does not spend PP twice")
  T.check(charging.hp() < 400, "native continuation lands the move")
  observations[#observations + 1] =
    { case = "charge", pp = charging.pp(), hit = charging.hp() < 400, charging = charging.charging() }
  local exhausted, exhaustedActor = fresh()
  if backend == "gen1" then
    exhaustedActor.mon.pp[2] = 0
  else
    exhaustedActor.curMoves[2].pp = 0
  end
  f.e.choose(function()
    return { move = "SCRATCH", slot = 2, pp = 100 }
  end)
  execute(exhausted.battle, choose(exhausted.battle))
  T.eq(exhausted.hp(), 400, "forged PP cannot execute an exhausted learned move")
  T.same(pp(exhaustedActor), { 10, 0, 5 }, "exhausted choice does not spend another slot")
  observations[#observations + 1] =
    { case = "exhausted", pp = pp(exhaustedActor), hit = exhausted.hp() < 400 }
  if backend == "gen2" then
    local pressure, actor = fresh()
    pressure.battle.player.abilityOverride = "PRESSURE"
    f.e.choose(function()
      return { move = "SCRATCH" }
    end)
    execute(pressure.battle, choose(pressure.battle))
    T.same(pp(actor), { 10, 5, 5 }, "Pressure charges the actual slot twice")

    local legacy, legacyActor = fresh()
    f.e.choose(function(nextAction, ...)
      local result = nextAction(...)
      result.id = format == "native" and f.ids.SCRATCH or "SCRATCH"
      return result
    end)
    execute(legacy.battle, choose(legacy.battle))
    T.same(pp(legacyActor), { 9, 7, 5 }, "legacy delegated id edit retains its selected PP slot")
    T.eq(legacyActor.curMoves[1].id, f.ids.TACKLE, "delegated id edit preserves learned move")

    local mimic, mimicActor = fresh()
    mimicActor.curMoves[3] = { id = f.ids.MIMIC, pp = 5 }
    f.e.choose(function()
      return { move = "MIMIC" }
    end)
    execute(mimic.battle, choose(mimic.battle))
    T.eq(mimicActor.curMoves[3].id, f.ids.TACKLE, "Mimic replaces the actual selected slot")
    T.eq(mimicActor.curMoves[3].pp, 4, "Mimic keeps PP on its actual slot")
    T.check(mimicActor.curMoves[3].mimic, "native Mimic marks its owned slot")
    T.eq(mimicActor.curMoves[1].mimic, nil, "Mimic does not overwrite the first slot")

    local double, left = fresh()
    local b = double.battle
    local Battle = require("src.battle.BattleState")
    local mon = require("src.mods.Merge").deepCopy(left.mon)
    local right = Battle.makeBattler(f.data, mon, false)
    b.double = true
    b:placeBattler(3, right)
    b:syncSides()
    f.e.choose(function()
      return { move = "SCRATCH" }
    end)
    local rightAction = b:enemyAction(right)
    b:executeAction(right, b.player, rightAction)
    T.same(pp(right), { 10, 6, 5 }, "right-flank choice owns right-flank PP")
    T.same(pp(left), { 10, 7, 5 }, "right-flank action leaves left-flank PP intact")
    if format == "native" then
      local raw = right.curMoves[2]
      f.e.choose(function()
        return raw
      end)
      T.eq(b:enemyAction(right), raw, "explicit native move handles retain identity")
    end
  end
  T.eq(#f.result.errors, 0, "public consumer completes without swallowed hook failures")
  f.close()
  return observations
end
return M
