-- Real move producers, repeated accuracy commands, residual sweeps and switches.
local M = {}
function M.fixture(root, backend, version)
  local native = backend == "gen1"
  local function configure(data, _, ids, rom, names)
    for _, row in ipairs({ { 199, "LOCK_ON", 94 }, { 170, "MIND_READER", 94 }, { 90, "FISSURE", 38 } }) do
      local n, name, effect = unpack(row)
      local id = native and name or ("MOVE_%03d"):format(n)
      ids[name], names[n] = id, name
      if native then
        local d = {
          effect = effect,
          type = n == 90 and 4 or 0,
          accuracy = n == 90 and 30 or 100,
          power = 0,
          pp = 20,
          target = 0,
          flags = 2,
          priority = 0,
          secondaryChance = 0,
        }
        data.gen3Moves._rom[n], rom[n], data.gen3Pokemon._moveNames[n] = d, d, name
      else
        data.moves[id] = {
          id = id,
          index = n,
          name = name,
          gen3Effect = effect,
          power = 0,
          type = n == 90 and "GROUND" or "NORMAL",
          accuracy = n == 90 and 30 or 100,
          pp = 20,
          target = 0,
          protectAffected = true,
          effect = n == 90 and "OHKO_EFFECT" or "LOCK_ON_EFFECT",
        }
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  return f
end
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local T, Copy, rows = f.T, require("src.mods.Merge").deepCopy, {}
  local calls, draws, moves, policy = {}, {}, {}, "delegate"
  local damageCalls = 0
  local stopDamage = f.e.api.hooks:wrap("battle.damage", function(nextDamage, ...)
    damageCalls = damageCalls + 1
    return nextDamage(...)
  end)
  local stop = f.e.api.hooks:wrap("battle.accuracy", function(nextAccuracy, c)
    calls[#calls + 1] = {
      move = c.moveId,
      number = c.moveNum,
      user = c.user.mon.nickname,
      target = c.target.mon.nickname,
      accuracy = c.accuracy,
    }
    if policy == "deny" then
      return false
    end
    if policy == "force" then
      return true
    end
    return nextAccuracy(c)
  end)
  local stopCrit = f.e.api.hooks:wrap("battle.crit", function()
    return false
  end)
  local stopMoves = f.e.api.events:on("battle.move_used", function(e)
    moves[#moves + 1] = { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
  end)
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  local function actor(mon, id)
    if native then
      return require("src.core.game3.battle.state").makeBattler(
        mon,
        id % 2 == 0 and "player" or "enemy",
        { id = id }
      )
    end
    return require("src.battle.BattleState").makeBattler(f.data, mon, id % 2 == 0)
  end
  local function put(b, id, a)
    if native then
      b.battlers[id] = a
    else
      b:placeBattler(id, a)
    end
  end
  local function fresh(double)
    damageCalls = 0
    local b = f.fresh("TACKLE", { enemy = true }).battle
    b.double = double
    if double then
      put(b, 2, actor(Copy(b.player.mon), 2))
      put(b, 3, actor(Copy(b.enemy.mon), 3))
    end
    if not native then
      b:syncSides()
    end
    for id = 0, double and 3 or 1 do
      local a = at(b, id)
      a.mon.nickname, a.mon.hp = "P" .. id, 400
      local ns = { 199, 170, 33, 90 }
      if native then
        a.mon.moves, a.mon.pp, a.mon.maxPp = ns, { 20, 20, 20, 20 }, { 20, 20, 20, 20 }
        a.ability, a.mon.ability, a.mon.speed = 0, 0, 400 - id * 50
        a.mon.item, a.item = 0, 0
        a.type1, a.type2 = 0, nil
      else
        a.curMoves = {
          { id = f.ids.LOCK_ON, pp = 20 },
          { id = f.ids.MIND_READER, pp = 20 },
          { id = f.ids.TACKLE, pp = 20 },
          { id = f.ids.FISSURE, pp = 20 },
        }
        a.mon.moves, a.abilityOverride = a.curMoves, false
        a.curStats.speed = 400 - id * 50
        a.mon.stats.hp = 400
        a.curTypes = { "NORMAL" }
        for _, k in ipairs({ "attack", "defense", "spatk", "spdef", "special" }) do
          a.curStats[k] = 50
        end
      end
    end
    if native then
      b.playerParty = { at(b, 0).mon, Copy(at(b, 0).mon) }
      b.foeParty = { at(b, 1).mon, Copy(at(b, 1).mon) }
      b.playerParty[2].nickname, b.foeParty[2].nickname = "BENCH_P", "BENCH_E"
    else
      b.game.save.party = { at(b, 0).mon, Copy(at(b, 0).mon) }
      b.enemyParty = { at(b, 1).mon, Copy(at(b, 1).mon) }
      b.game.save.party[2].nickname, b.enemyParty[2].nickname = "BENCH_P", "BENCH_E"
    end
    if double then
      if native then
        b.playerParty = { at(b, 0).mon, at(b, 2).mon, Copy(at(b, 0).mon) }
        b.foeParty = { at(b, 1).mon, at(b, 3).mon, Copy(at(b, 1).mon) }
        at(b, 2).partyIndex, at(b, 3).partyIndex = 2, 2
        b.playerParty[3].nickname, b.foeParty[3].nickname = "BENCH_P", "BENCH_E"
      else
        b.game.save.party = { at(b, 0).mon, at(b, 2).mon, Copy(at(b, 0).mon) }
        b.enemyParty = { at(b, 1).mon, at(b, 3).mon, Copy(at(b, 1).mon) }
        b.game.save.party[3].nickname, b.enemyParty[3].nickname = "BENCH_P", "BENCH_E"
      end
    end
    b.rng = function(lo, hi)
      local value = hi
      draws[#draws + 1] = { lo = lo, hi = hi, value = value }
      return value
    end
    return b
  end
  local function cast(b, from, to, slot)
    local user, target = at(b, from), at(b, to)
    if native then
      require("src.core.game3.battle.engine").resolveMove(
        from,
        to,
        user.mon.moves[slot],
        slot,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      b:executeAction(user, target, user.curMoves[slot])
    end
  end
  local function check(b, from, to, kind)
    local user, target = at(b, from), at(b, to)
    if native then
      local context = require("src.core.game3.battle.engine").newContext(
        user,
        target,
        33,
        3,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {},
        {}
      )
      context.move.accuracy = 0
      return context:accuracyCheck(kind or "normal", false)
    end
    local move = Copy(f.data.moves[f.ids.TACKLE])
    move.accuracy = 0
    return b:accuracyRoll(move, user, target)
  end
  local function tick(b)
    if native then
      require("src.core.game3.battle.engine").collectResidualEvents(
        b,
        require("src.core.game3.battle.adapter").new(b)
      )
    else
      b:endOfTurn()
    end
  end
  local function timer(b, id)
    local a = at(b, id)
    return native and a.expLockedOn or a.lockOnTurns
  end
  local function switch(b, id, pass)
    local old = at(b, id)
    local slot = b.double and 3 or 2
    if id == 3 then
      old.mon.hp = 0
    end
    if native then
      return require("src.core.game3.battle.engine").performSwitch(
        b,
        require("src.core.game3.battle.adapter").new(b),
        id,
        slot,
        { batonPass = pass, reason = "switch" }
      )
    elseif id % 2 == 0 then
      if pass then
        old.batonPass = {}
      end
      b:switchPlayerInto(id, b.game.save.party[slot])
    elseif id == 1 then
      b:executeAction(old, at(b, 0), { special = "aiSwitch", index = slot })
    else
      b:placeBattler(id, nil)
      b.pendingReplacements = { id }
      b:fillEmptySlots()
    end
    return at(b, id)
  end
  local function snapshot(b, label, extra)
    local all = {}
    for id = 0, b.double and 3 or 1 do
      local a = at(b, id)
      if a then
        local side = native and a.expLockedOnBy or a.lockOnBy
        if not native then
          if a.lockOnBy == true then
            side = "player"
          elseif a.lockOnBy == false then
            side = "enemy"
          else
            side = nil
          end
        end
        all[#all + 1] = {
          id = id,
          name = a.mon.nickname,
          hp = a.mon.hp,
          turns = native and a.expLockedOn or a.lockOnTurns,
          ownerSide = side,
          ownerId = native and a.expLockedOnById or a.lockOnByPos,
          pp = native and a.mon.pp
            or { a.curMoves[1].pp, a.curMoves[2].pp, a.curMoves[3].pp, a.curMoves[4].pp },
        }
      end
    end
    rows[#rows + 1] = {
      label = label,
      actors = all,
      calls = Copy(calls),
      draws = Copy(draws),
      moves = Copy(moves),
      damageCalls = damageCalls,
      extra = extra,
    }
  end
  for _, double in ipairs({ false, true }) do
    for owner = 0, double and 3 or 1 do
      for _, slot in ipairs({ 1, 2 }) do
        for _, mode in ipairs({ "delegate", "deny", "force" }) do
          policy = mode
          calls, draws, moves = {}, {}, {}
          local b = fresh(double)
          local victim = owner % 2 == 0 and 1 or 0
          cast(b, owner, victim, slot)
          T.eq(timer(b, victim), mode ~= "deny" and 2 or nil, "producer stores two residual phases")
          local label = table.concat({ double and "double" or "single", owner, slot, mode }, "/")
          snapshot(b, label .. "/cast")
          local a = check(b, owner, victim)
          local c = check(b, owner, victim)
          T.eq(a, c, "native guarantee is not consumed by an accuracy query")
          T.eq(a, mode ~= "deny", "only successful native producers guarantee their owner")
          snapshot(b, label .. "/repeated", { a, c })
          if double then
            snapshot(b, label .. "/partner", { check(b, (owner + 2) % 4, victim) })
          end
          tick(b)
          T.eq(timer(b, victim), mode ~= "deny" and 1 or nil, "first residual leaves one phase")
          snapshot(b, label .. "/first-residual", { check(b, owner, victim) })
          tick(b)
          T.eq(timer(b, victim), nil, "second residual expires target-owned binding")
          snapshot(b, label .. "/second-residual", { check(b, owner, victim) })
        end
      end
    end
  end
  policy = "delegate"
  for _, double in ipairs({ false, true }) do
    for owner = 0, double and 3 or 1 do
      for _, kind in
        ipairs(
          double and { "owner", "target", "partner", "baton-target" } or { "owner", "target", "baton-target" }
        )
      do
        if kind ~= "baton-target" or owner % 2 == 1 then
          calls, draws, moves = {}, {}, {}
          local b = fresh(double)
          local victim = owner % 2 == 0 and 1 or 0
          cast(b, owner, victim, 1)
          local id = kind == "owner" and owner or kind == "partner" and (owner + 2) % 4 or victim
          T.check(switch(b, id, kind == "baton-target") ~= nil, "real switch installs a replacement")
          local hit = check(b, owner, victim)
          T.eq(hit, kind == "partner" or kind == "baton-target", "ownership follows native switch policy")
          snapshot(b, "switch/" .. tostring(double) .. "/" .. owner .. "/" .. kind, { hit })
        end
      end
    end
  end
  for owner = 0, 3 do
    calls, draws, moves = {}, {}, {}
    local b = fresh(true)
    local victim = owner % 2 == 0 and 1 or 0
    cast(b, owner, victim, 1)
    tick(b)
    cast(b, owner, victim, 2)
    T.eq(timer(b, victim), 2, "same owner refreshes the duration")
    cast(b, (owner + 2) % 4, victim, 1)
    T.eq(check(b, owner, victim), false, "reapplication transfers ownership from the old owner")
    T.eq(check(b, (owner + 2) % 4, victim), true, "new owner receives the guarantee")
    snapshot(b, "refresh/" .. owner)
  end
  for _, kind in ipairs({
    "locked",
    "ordinary",
    "expired",
    "wrong-owner",
    "protect",
    "air",
    "lower-level",
    "sturdy",
  }) do
    calls, draws, moves = {}, {}, {}
    local b = fresh(true)
    local user, target = at(b, 1), at(b, 0)
    if kind ~= "ordinary" then
      cast(b, kind == "wrong-owner" and 3 or 1, 0, 1)
    end
    if kind == "expired" then
      tick(b)
      tick(b)
    end
    if kind == "protect" then
      if native then
        target.expProtected = true
      else
        target.protecting = true
      end
    end
    if kind == "air" then
      if native then
        target.semiInvulnerable = "ON_AIR"
      else
        target.invulnerable, target.hiddenAs = true, "air"
      end
    end
    if kind == "lower-level" then
      target.mon.level = user.mon.level + 1
    end
    if kind == "sturdy" then
      if native then
        target.ability, target.mon.ability = 5, 5
      else
        target.abilityOverride = "STURDY"
      end
    end
    cast(b, 1, 0, 4)
    snapshot(b, "ohko/" .. kind, { hp = target.mon.hp })
  end
  for owner = 0, 3 do
    for _, protected in ipairs({ false, true }) do
      calls, draws, moves = {}, {}, {}
      local b = fresh(true)
      local victim = owner % 2 == 0 and 1 or 0
      cast(b, owner, victim, 1)
      if native then
        at(b, victim).expProtected = protected
      else
        at(b, victim).protecting = protected
      end
      cast(b, owner, victim, 3)
      cast(b, owner, victim, 3)
      T.eq(timer(b, victim), 2, "two real damaging moves do not consume the timed state")
      T.eq(damageCalls, protected and 0 or 2, "real damage hooks respect Protect before native guarantee")
      snapshot(b, "damaging/" .. owner .. "/" .. tostring(protected))
    end
  end
  for _, guard in ipairs({ "substitute", "substitute-zero", "protect", "air", "underground", "underwater" }) do
    policy = "delegate"
    calls, draws, moves = {}, {}, {}
    local b = fresh(true)
    local target = at(b, 0)
    target.substituteHP = guard == "substitute" and 40 or guard == "substitute-zero" and 0 or nil
    if native then
      target.expProtected = guard == "protect" or nil
      target.semiInvulnerable = ({ air = "ON_AIR", underground = "UNDERGROUND", underwater = "UNDERWATER" })[guard]
    else
      target.protecting = guard == "protect" or nil
      target.hiddenAs = ({ air = "air", underground = "underground", underwater = "underwater" })[guard]
      target.invulnerable = target.hiddenAs ~= nil
    end
    cast(b, 1, 0, 1)
    snapshot(b, "guard/" .. guard)
  end
  stopMoves()
  stopDamage()
  stopCrit()
  stop()
  f.close()
  return rows
end
return M
