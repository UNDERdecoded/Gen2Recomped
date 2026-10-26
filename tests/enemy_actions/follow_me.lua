local M = {}
function M.run(root, backend, version)
  local function configure(data, engine, ids, rom, names)
    for _, row in ipairs({
      { "FOLLOW_ME", 266, 172, 0, 16, 3 },
      { "THUNDERSHOCK", 84, 0, 40, 0, 0 },
      { "TARGET_BOTH", 600, 0, 40, 8, 0 },
    }) do
      local name, number, effect, power, target, priority = unpack(row)
      local key = engine == "gen1" and name or ("MOVE_%03d"):format(number)
      ids[name], names[number] = key, name
      if engine == "gen1" then
        local def = {
          effect = effect,
          power = power,
          target = target,
          priority = priority,
          type = number == 84 and 13 or 0,
          accuracy = 100,
          pp = 20,
          flags = 0,
          secondaryChance = 0,
        }
        data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = def, def, name
      else
        data.moves[key] = {
          id = key,
          name = name,
          index = number,
          gen3Effect = effect,
          protectAffected = false,
          effect = number == 266 and "FOLLOW_ME_EFFECT" or "NO_ADDITIONAL_EFFECT",
          power = power,
          target = target,
          priority = priority,
          type = number == 84 and "ELECTRIC" or "NORMAL",
          accuracy = 100,
          accuracyRaw = 255,
          pp = 20,
        }
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  local T, rows, moves, hits = f.T, {}, {}, {}
  local stopMove = f.e.api.events:on("battle.move_used", function(e)
    moves[#moves + 1] = { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
  end)
  local stopHit = f.e.api.events:on("battle.damage_dealt", function(e)
    hits[#hits + 1] = e.target.mon.nickname
  end)
  local function at(b, id)
    return backend == "gen1" and b.battlers[id] or b:battlerAt(id)
  end
  local function actor(mon, id)
    if backend == "gen1" then
      return require("src.core.game3.battle.state").makeBattler(
        mon,
        id % 2 == 0 and "player" or "enemy",
        { id = id }
      )
    end
    return require("src.battle.BattleState").makeBattler(f.data, mon, id % 2 == 0)
  end
  local function put(b, id, who)
    if backend == "gen1" then
      b.battlers[id] = who
    else
      b:placeBattler(id, who)
    end
  end
  local function fresh(double)
    local b, copy = f.fresh("TACKLE", { enemy = true }).battle, require("src.mods.Merge").deepCopy
    b.double = double
    if double then
      put(b, 2, actor(copy(b.player.mon), 2))
      put(b, 3, actor(copy(b.enemy.mon), 3))
    end
    if backend == "gen2" then
      b:syncSides()
    end
    for id = 0, double and 3 or 1 do
      local a = at(b, id)
      a.mon.nickname, a.mon.hp = "P" .. id, 400
      if backend == "gen1" then
        a.mon.moves, a.mon.pp, a.mon.maxPp = { 266, 33, 84, 600 }, { 20, 10, 10, 10 }, { 20, 10, 10, 10 }
        a.ability, a.mon.ability, a.mon.speed = 0, 0, 400 - id * 50
      else
        a.curMoves = {
          { id = f.ids.FOLLOW_ME, pp = 20 },
          { id = f.ids.TACKLE, pp = 10 },
          { id = f.ids.THUNDERSHOCK, pp = 10 },
          { id = f.ids.TARGET_BOTH, pp = 10 },
        }
        a.mon.moves, a.abilityOverride = a.curMoves, false
        a.curStats.speed = 400 - id * 50
      end
    end
    return b
  end
  local function pp(b, id, slot)
    local a = at(b, id)
    return backend == "gen1" and a.mon.pp[slot] or a.curMoves[slot].pp
  end
  local function rod(b, id)
    local a = at(b, id)
    if backend == "gen1" then
      a.ability, a.mon.ability = 31, 31
    else
      a.abilityOverride = "LIGHTNING_ROD"
    end
  end
  local function cast(b, id)
    if backend == "gen1" then
      require("src.core.game3.battle.engine").resolveMove(
        id,
        id,
        266,
        1,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      b:executeAction(at(b, id), at(b, id), at(b, id).curMoves[1])
    end
  end
  local function attack(b, id, target, name)
    name = name or "TACKLE"
    local slot = name == "FOLLOW_ME" and 1 or name == "THUNDERSHOCK" and 3 or name == "TARGET_BOTH" and 4 or 2
    f.e.choose(function()
      return { move = name, target = target }
    end)
    if backend == "gen1" then
      local C = require("src.core.game3.battle.commands")
      local action = id % 2 == 0 and C.playerAction(b, 1, slot, id, target) or C.enemyAction(b, id)
      require("src.core.game3.battle.engine").resolveMove(
        id,
        action.target,
        action.move,
        action.slot,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      local action = id % 2 == 0 and at(b, id).curMoves[slot] or b:enemyAction(at(b, id))
      if id % 2 == 0 then
        b.chosenTargets = { [id] = target and at(b, target) }
      end
      b:executeAction(at(b, id), at(b, target or (id % 2 == 0 and 1 or 0)), action)
    end
  end
  local specs = {
    { name = "left", casts = { 0 }, user = 1, target = 2, expected = "P0" },
    { name = "right", casts = { 2 }, user = 1, target = 0, expected = "P2" },
    { name = "right-attacker", casts = { 0 }, user = 3, target = 2, expected = "P0" },
    { name = "default-target", casts = { 2 }, user = 1, expected = "P2" },
    { name = "last-caster", casts = { 0, 2 }, user = 1, target = 0, expected = "P2" },
    { name = "last-caster-reversed", casts = { 2, 0 }, user = 1, target = 2, expected = "P0" },
    {
      name = "lightning-priority",
      casts = { 0 },
      user = 1,
      target = 2,
      move = "THUNDERSHOCK",
      rod = 2,
      expected = "P0",
    },
    { name = "enemy-center-left", casts = { 1 }, user = 0, target = 3, expected = "P1" },
    { name = "enemy-center-right", casts = { 3 }, user = 2, target = 1, expected = "P3" },
    {
      name = "self-not-redirected",
      casts = { 0 },
      user = 1,
      target = 1,
      move = "FOLLOW_ME",
      expected = "P1",
      status = true,
    },
    { name = "both-sides", casts = { 0, 3 }, user = 1, target = 2, expected = "P0" },
    { name = "fainted-caster", casts = { 0 }, user = 1, target = 2, faint = 0, expected = "P2" },
    {
      name = "fainted-timer-before-rod",
      casts = { 0 },
      user = 1,
      target = 3,
      faint = 0,
      move = "THUNDERSHOCK",
      rod = 2,
      expected = "P3",
    },
    { name = "replaced-caster-slot", casts = { 0 }, user = 1, target = 2, replace = 0, expected = "P0_NEXT" },
    {
      name = "spread-not-redirected",
      casts = { 0 },
      user = 1,
      target = 2,
      move = "TARGET_BOTH",
      expected = "P2",
      spread = true,
    },
    { name = "sleep-refusal", casts = { 0 }, user = 1, target = 2, expected = "P2", sleep = true },
    { name = "substitute-protect", casts = { 0 }, user = 1, target = 2, expected = "P0", protected = true },
    { name = "single", casts = { 0 }, user = 1, target = 0, expected = "P0", single = true },
  }
  for _, spec in ipairs(specs) do
    local b = fresh(not spec.single)
    moves, hits = {}, {}
    if spec.sleep then
      b.player.mon.status, b.player.sleepTurns = "SLP", 5
    end
    if spec.protected then
      b.player.substituteHP, b.player.protecting = 40, true
      b.enemy.protecting = true
    end
    for _, id in ipairs(spec.casts) do
      cast(b, id)
      T.eq(
        pp(b, id, 1),
        spec.sleep and 20 or 19,
        backend .. "/" .. spec.name .. " actual Follow Me PP follows move execution"
      )
    end
    if spec.protected then
      b.player.substituteHP, b.player.protecting, b.enemy.protecting = nil, nil, nil
    end
    if spec.rod then
      rod(b, spec.rod)
    end
    if spec.faint then
      at(b, spec.faint).mon.hp = 0
      if backend == "gen1" then
        b.absent[spec.faint] = true
      end
    end
    if spec.replace then
      local mon = require("src.mods.Merge").deepCopy(at(b, spec.replace).mon)
      mon.nickname = "P0_NEXT"
      put(b, spec.replace, actor(mon, spec.replace))
    end
    moves, hits = {}, {}
    attack(b, spec.user, spec.target, spec.move)
    local label = backend .. "/" .. version .. "/" .. spec.name
    T.eq(moves[1] and moves[1].target, spec.expected, label .. " native target honors Follow Me")
    T.same(
      hits,
      spec.status and {} or spec.spread and { "P2", "P0" } or { spec.expected },
      label .. " actual damage reaches native targets"
    )
    local slot = spec.move == "FOLLOW_ME" and 1 or spec.move == "THUNDERSHOCK" and 3 or spec.spread and 4 or 2
    T.eq(
      pp(b, spec.user, slot),
      spec.move == "FOLLOW_ME" and 19 or 9,
      label .. " actual attack spends own PP once"
    )
    rows[#rows + 1] = { case = spec.name, moves = moves, hits = hits, pp = pp(b, spec.user, slot) }
  end
  for _, residual in ipairs({ false, true }) do
    local b = fresh(true)
    moves, hits = {}, {}
    cast(b, 0)
    if residual then
      if backend == "gen1" then
        require("src.core.game3.battle.engine").collectResidualEvents(
          b,
          require("src.core.game3.battle.adapter").new(b)
        )
      else
        b:endOfTurn()
      end
    end
    moves, hits = {}, {}
    attack(b, 1, 2)
    T.same(hits, { "P0" }, "Follow Me remains active through the current round's residuals")
    local first = moves
    if backend == "gen1" then
      require("src.core.game3.battle.engine").planTurnActions(
        b,
        require("src.core.game3.battle.adapter").new(b),
        {
          [0] = { kind = "watch" },
          [1] = { kind = "watch" },
          [2] = { kind = "watch" },
          [3] = { kind = "watch" },
        }
      )
    else
      f.e.choose(function(_, _, id)
        return { move = "TACKLE", target = id == 1 and 2 or 0 }
      end)
      b.queue, b.pendingActions = {}, { [2] = b:battlerAt(2).curMoves[2] }
      b:resolveTurn(b.player.curMoves[2])
    end
    moves, hits = {}, {}
    attack(b, 1, 2)
    T.same(hits, { "P2" }, "native next-turn planning clears the expired Follow Me position")
    T.eq(pp(b, 1, 2), 8, "two real attacks consume two PP across round boundaries")
    rows[#rows + 1] = {
      case = residual and "residual-expiry" or "turn-expiry",
      before = first,
      after = moves,
      hits = hits,
      pp = pp(b, 1, 2),
    }
  end

  local b = fresh(true)
  moves, hits = {}, {}
  if backend == "gen1" then
    b.player.mon.speed, b.enemy.mon.speed, at(b, 3).mon.speed = 50, 900, 800
  else
    b.player.curStats.speed, b.enemy.curStats.speed, at(b, 3).curStats.speed = 50, 900, 800
  end
  f.e.choose(function()
    return { move = "TACKLE", target = 2 }
  end)
  moves, hits = {}, {}
  if backend == "gen1" then
    local C, E, A =
      require("src.core.game3.battle.commands"),
      require("src.core.game3.battle.engine"),
      require("src.core.game3.battle.adapter")
    local ad = A.new(b)
    local actions = E.planTurnActions(b, ad, {
      [0] = C.playerAction(b, 1, 1, 0, 0),
      [2] = { kind = "watch" },
      [1] = C.enemyAction(b, 1),
      [3] = C.enemyAction(b, 3),
    })
    for _, a in ipairs(actions) do
      if a.kind == "move" then
        E.resolveMove(a.user, a.target, a.move, a.slot, ad, b, {})
      end
    end
  else
    b.queue, b.pendingActions = {}, { [2] = { special = "recharge" } }
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
    T.check(count < 1000, "real Follow Me turn queue completes")
  end
  T.same(hits, { "P0", "P0" }, "native Follow Me priority beats both faster foes")
  T.eq(moves[1] and moves[1].move, "FOLLOW_ME", "native priority executes the real Follow Me producer first")
  T.eq(pp(b, 0, 1), 19, "queued Follow Me spends one caster PP")
  T.same({ pp(b, 1, 2), pp(b, 3, 2) }, { 9, 9 }, "both redirected queued attacks spend owned PP")
  rows[#rows + 1] =
    { case = "priority-queue", moves = moves, hits = hits, pp = { pp(b, 0, 1), pp(b, 1, 2), pp(b, 3, 2) } }
  stopHit()
  stopMove()
  f.close()
  return rows
end
return M
