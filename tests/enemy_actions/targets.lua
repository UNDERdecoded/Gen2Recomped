local M = {}
function M.run(root, backend, version)
  local function configure(data, engine, ids, rom, names)
    for _, row in ipairs({
      { "TARGET_BOTH", 600, 8 },
      { "TARGET_ALL", 601, 32 },
      { "TARGET_SELF", 602, 16 },
      { "TARGET_FIELD", 603, 64 },
      { "THUNDERSHOCK", 84, 0 },
    }) do
      local name, number, target = unpack(row)
      local key = engine == "gen1" and name or ("MOVE_%03d"):format(number)
      local electric = name == "THUNDERSHOCK"
      ids[name], names[number] = key, name
      if engine == "gen1" then
        local def = {
          effect = 0,
          power = target == 64 and 0 or 40,
          type = electric and 13 or 0,
          accuracy = 100,
          pp = 20,
          secondaryChance = 0,
          target = target,
          priority = 0,
          flags = 51,
        }
        data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = def, def, name
      else
        data.moves[key] = {
          id = key,
          name = name,
          index = number,
          power = target == 64 and 0 or 40,
          type = electric and "ELECTRIC" or "NORMAL",
          pp = 20,
          accuracy = 100,
          accuracyRaw = 255,
          target = target,
          effect = "NO_ADDITIONAL_EFFECT",
        }
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  local T, observations, events, damages = f.T, {}, {}, {}
  local stopEvent = f.e.api.events:on("battle.move_used", function(e)
    events[#events + 1] = { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
  end)
  local stopDamage = f.e.api.events:on("battle.damage_dealt", function(e)
    damages[#damages + 1] = e.target.mon.nickname
  end)
  local function at(b, id)
    return backend == "gen1" and b.battlers[id] or b:battlerAt(id)
  end
  local function fresh(moveName)
    local c = f.fresh("TACKLE", { enemy = true })
    local b, copy = c.battle, require("src.mods.Merge").deepCopy
    b.double = true
    if backend == "gen1" then
      local S = require("src.core.game3.battle.state")
      b.battlers[2] = S.makeBattler(copy(b.player.mon), "player", { id = 2 })
      b.battlers[3] = S.makeBattler(copy(b.enemy.mon), "enemy", { id = 3 })
    else
      local S = require("src.battle.BattleState")
      b:placeBattler(2, S.makeBattler(f.data, copy(b.player.mon), true))
      b:placeBattler(3, S.makeBattler(f.data, copy(b.enemy.mon), false))
      b:syncSides()
    end
    local number = ({
      TACKLE = 33,
      TARGET_BOTH = 600,
      TARGET_ALL = 601,
      TARGET_SELF = 602,
      TARGET_FIELD = 603,
      THUNDERSHOCK = 84,
    })[moveName]
    for id = 0, 3 do
      local a = at(b, id)
      a.mon.nickname = "P" .. id
      a.mon.hp = 400
      if backend == "gen1" then
        a.mon.moves, a.mon.pp = { number }, { 20 }
        a.mon.speed, a.mon.ability, a.ability = 400 - id * 50, 0, 0
      else
        a.curMoves = { { id = f.ids[moveName], pp = 20 } }
        a.mon.moves = a.curMoves
        a.curStats.speed, a.abilityOverride = 400 - id * 50, false
      end
    end
    return b
  end
  local function ability(b, id, name)
    local a = at(b, id)
    if backend == "gen1" then
      a.ability, a.mon.ability = name == "PRESSURE" and 46 or 31, name == "PRESSURE" and 46 or 31
    else
      a.abilityOverride = name
    end
  end
  local function pp(a)
    return backend == "gen1" and a.mon.pp[1] or a.curMoves[1].pp
  end
  local function choose(b, id)
    if backend == "gen1" then
      return require("src.core.game3.battle.commands").enemyAction(b, id)
    end
    return b:enemyAction(at(b, id))
  end
  local function execute(b, id, action)
    if backend == "gen1" then
      local Engine, Adapter =
        require("src.core.game3.battle.engine"), require("src.core.game3.battle.adapter")
      local ad = Adapter.new(b)
      local chosen = {
        [0] = { kind = "watch" },
        [1] = { kind = "watch" },
        [2] = { kind = "watch" },
        [3] = { kind = "watch" },
      }
      chosen[id] = action
      local rows = Engine.planTurnActions(b, ad, chosen)
      for _, row in ipairs(rows) do
        if row.kind == "move" then
          Engine.resolveMove(row.user, row.target, row.move, row.slot, ad, b, {})
        end
      end
    else
      b:executeAction(at(b, id), at(b, 0), action)
    end
  end
  local specs = {}
  for _, user in ipairs({ 1, 3 }) do
    for target = 0, 3 do
      specs[#specs + 1] = {
        name = "selected-" .. target,
        move = "TACKLE",
        user = user,
        target = target,
        victims = { "P" .. target },
        cost = 1,
      }
    end
    specs[#specs + 1] = {
      name = "both-right-first",
      move = "TARGET_BOTH",
      user = user,
      target = 2,
      victims = { "P2", "P0" },
      cost = 1,
    }
    specs[#specs + 1] = {
      name = "all",
      move = "TARGET_ALL",
      user = user,
      target = 2,
      victims = user == 1 and { "P0", "P2", "P3" } or { "P0", "P1", "P2" },
      cost = 1,
    }
    specs[#specs + 1] = {
      name = "self",
      move = "TARGET_SELF",
      user = user,
      target = user,
      victims = { "P" .. user },
      cost = 1,
    }
  end
  for _, spec in ipairs({
    {
      name = "cached-target",
      move = "TACKLE",
      user = 1,
      target = 2,
      cached = true,
      victims = { "P2" },
      cost = 1,
    },
    {
      name = "pressure-selected",
      move = "TACKLE",
      user = 1,
      target = 2,
      pressure = { 2 },
      victims = { "P2" },
      cost = 2,
    },
    {
      name = "pressure-both",
      move = "TARGET_BOTH",
      user = 1,
      target = 2,
      pressure = { 0, 2 },
      victims = { "P2", "P0" },
      cost = 3,
    },
    {
      name = "pressure-all",
      move = "TARGET_ALL",
      user = 3,
      target = 2,
      pressure = { 0, 1, 2, 3 },
      victims = { "P0", "P1", "P2" },
      cost = 4,
    },
    {
      name = "pressure-self",
      move = "TARGET_SELF",
      user = 1,
      target = 1,
      pressure = { 1 },
      victims = { "P1" },
      cost = 1,
    },
    {
      name = "field",
      move = "TARGET_FIELD",
      user = 1,
      target = 2,
      pressure = { 0, 2 },
      victims = { "P2" },
      cost = 3,
    },
    {
      name = "lightning-rod",
      move = "THUNDERSHOCK",
      user = 1,
      target = 0,
      rod = { 2 },
      victims = { "P2" },
      cost = 1,
    },
  }) do
    specs[#specs + 1] = spec
  end
  for _, spec in ipairs(specs) do
    for _, mode in ipairs({ "replace", "delegate" }) do
      local b = fresh(spec.move)
      if spec.cached then
        if backend == "gen1" then
          b.moveTarget = { [1] = 0 }
        else
          b.chosenTargets = { [1] = at(b, 0) }
        end
      end
      for _, id in ipairs(spec.pressure or {}) do
        ability(b, id, "PRESSURE")
      end
      for _, id in ipairs(spec.rod or {}) do
        ability(b, id, "LIGHTNING_ROD")
      end
      f.e.choose(function(nextAction, ...)
        if mode == "delegate" then
          local a = nextAction(...)
          a.target = spec.target
          return a
        end
        return { kind = "move", move = spec.move, target = spec.target }
      end)
      events, damages = {}, {}
      local action = choose(b, spec.user)
      T.eq(action.target, spec.target, "target remains positional until execution")
      execute(b, spec.user, action)
      local targets = {}
      for _, e in ipairs(events) do
        targets[#targets + 1] = e.target
      end
      local label = backend .. "/" .. version .. "/" .. spec.name .. "/" .. spec.user .. "/" .. mode
      T.same(
        targets,
        { spec.victims[1] },
        label .. " emits one native move event for the actual first target"
      )
      T.same(
        damages,
        spec.move == "TARGET_FIELD" and {} or spec.victims,
        label .. " actual native damage events use selected targets/order"
      )
      T.eq(pp(at(b, spec.user)), 20 - spec.cost, label .. " spends native PP cost exactly once")
      observations[#observations + 1] = {
        case = spec.name,
        user = spec.user,
        mode = mode,
        target = action.target,
        events = events,
        damages = damages,
        pp = pp(at(b, spec.user)),
      }
    end
  end
  -- A new occupant must be resolved after the choice has already been made.
  for _, remove in ipairs({ false, true }) do
    local b = fresh("TACKLE")
    f.e.choose(function()
      return { move = "TACKLE", target = 0 }
    end)
    local action = choose(b, 1)
    if remove then
      if backend == "gen1" then
        b.absent[0] = true
        b.battlers[0] = nil
      else
        b:placeBattler(0, nil)
      end
    else
      local copy = require("src.mods.Merge").deepCopy(b.player.mon)
      copy.nickname = "P0_NEXT"
      if backend == "gen1" then
        b.battlers[0] = require("src.core.game3.battle.state").makeBattler(copy, "player", { id = 0 })
      else
        b:placeBattler(0, require("src.battle.BattleState").makeBattler(f.data, copy, true))
      end
    end
    events, damages = {}, {}
    execute(b, 1, action)
    local expected = remove and "P2" or "P0_NEXT"
    T.eq(events[1] and events[1].target, expected, "selected slot resolves the living current occupant")
    T.same(damages, { expected }, "switched/absent slot reaches native actual damage")
    T.eq(pp(at(b, 1)), 19, "late resolution spends one owned PP")
    observations[#observations + 1] = {
      case = remove and "absent" or "replacement",
      events = events,
      damages = damages,
      pp = pp(at(b, 1)),
    }
  end

  -- Both engines' own planner/executor path, with actual host queue draining.
  for _, lightning in ipairs({ false, true }) do
    local b = fresh(lightning and "THUNDERSHOCK" or "TACKLE")
    if lightning then
      ability(b, 0, "LIGHTNING_ROD")
      ability(b, 2, "LIGHTNING_ROD")
      if backend == "gen1" then
        b.player.mon.speed, at(b, 2).mon.speed = 700, 800
      else
        b.player.curStats.speed, at(b, 2).curStats.speed = 700, 800
      end
    end
    f.e.choose(function(_, _, id)
      return {
        move = lightning and "THUNDERSHOCK" or "TACKLE",
        target = lightning and (id == 1 and 3 or 1) or (id == 1 and 2 or 0),
      }
    end)
    events, damages = {}, {}
    if backend == "gen1" then
      local E, A = require("src.core.game3.battle.engine"), require("src.core.game3.battle.adapter")
      local ad = A.new(b)
      local rows = E.planTurnActions(
        b,
        ad,
        { [0] = { kind = "watch" }, [2] = { kind = "watch" }, [1] = choose(b, 1), [3] = choose(b, 3) }
      )
      for _, row in ipairs(rows) do
        if row.kind == "move" then
          E.resolveMove(row.user, row.target, row.move, row.slot, ad, b, {})
        end
      end
    else
      b.queue, b.pendingActions = {}, { [2] = { special = "recharge" } }
      b:resolveTurn({ special = "recharge" })
      local count = 0
      while b.queue[1] and count < 1000 do
        count = count + 1
        local row = table.remove(b.queue, 1)
        if row.fn then
          b.nextInsert = 0
          row.fn()
        end
      end
      T.check(count < 1000, "actual native turn queue drains")
    end
    local expected = lightning and { "P2", "P2" } or { "P2", "P0" }
    local usedTargets = {}
    for _, e in ipairs(events) do
      usedTargets[#usedTargets + 1] = e.target
    end
    T.same(
      usedTargets,
      expected,
      "actual double planner honors both selected targets and Lightning Rod order"
    )
    T.same(damages, expected, "actual double planner reaches both native damage targets")
    T.eq(pp(at(b, 1)), 19, "left enemy queue action spends its own PP once")
    T.eq(pp(at(b, 3)), 19, "right enemy queue action spends its own PP once")
    observations[#observations + 1] = {
      case = lightning and "queue-lightning-order" or "queue-selected",
      events = events,
      damages = damages,
      pp = { pp(at(b, 1)), pp(at(b, 3)) },
    }
  end
  stopDamage()
  stopEvent()
  f.close()
  return observations
end
return M
