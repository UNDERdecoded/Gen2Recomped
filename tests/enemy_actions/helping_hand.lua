local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local extra = {
    { "HELPING_HAND", 270, 176, "HELPING_HAND_EFFECT", 0, 16, 5, "NORMAL", 0 },
    { "THUNDERSHOCK", 84, 0, "NO_ADDITIONAL_EFFECT", 40, 0, 0, "ELECTRIC", 13 },
    { "TARGET_BOTH", 600, 0, "NO_ADDITIONAL_EFFECT", 35, 8, 0, "NORMAL", 0 },
    { "DRAGON_RAGE", 82, 41, "SPECIAL_DAMAGE_EFFECT", 1, 0, 0, "DRAGON", 16 },
  }
  local function configure(data, engine, ids, rom, names)
    for _, row in ipairs(extra) do
      local name, number, effect, handler, power, target, priority, kind, typeId = unpack(row)
      local key = engine == "gen1" and name or ("MOVE_%03d"):format(number)
      ids[name], names[number] = key, name
      if engine == "gen1" then
        local def = {
          effect = effect,
          power = power,
          target = target,
          priority = priority,
          type = typeId,
          accuracy = 100,
          pp = 20,
          flags = power == 0 and 0 or 51,
          secondaryChance = 0,
        }
        data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = def, def, name
      else
        data.moves[key] = {
          id = key,
          index = number,
          name = name,
          gen3Effect = effect,
          effect = handler,
          power = power,
          target = target,
          priority = priority,
          type = kind,
          accuracy = 100,
          accuracyRaw = 255,
          pp = 20,
          protectAffected = power ~= 0,
          fixedDamage = name == "DRAGON_RAGE" and 40 or nil,
        }
      end
    end
    if engine == "gen2" then
      data.type_chart.types = {}
      data.type_chart.matchups = {
        { attacker = "NORMAL", defender = "STEEL", multiplier = 5 },
        { attacker = "NORMAL", defender = "GHOST", multiplier = 0 },
      }
      for name, id in pairs({ NORMAL = 0, GHOST = 7, STEEL = 8, FIRE = 10, ELECTRIC = 13, DRAGON = 16 }) do
        data.type_chart.types[name] =
          { id = name, index = id, category = id <= 8 and "physical" or "special" }
      end
    end
  end
  local f =
    dofile(root .. "/tests/enemy_actions/fixture.lua").new(root, backend, version, 3, "unified", configure)
  local T, rows, moves, hits, critical, roll = f.T, {}, {}, {}, false, 100
  local stopCrit = f.e.api.hooks:wrap("battle.crit", function()
    return critical
  end)
  local stopMove = f.e.api.events:on("battle.move_used", function(e)
    moves[#moves + 1] = { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
  end)
  local stopHit = f.e.api.events:on("battle.damage_dealt", function(e)
    hits[#hits + 1] = { target = e.target.mon.nickname, amount = e.damage }
  end)
  local function at(b, id)
    if native then
      return b.battlers[id]
    end
    return b:battlerAt(id)
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
  local function put(b, id, who)
    if native then
      b.battlers[id] = who
    else
      b:placeBattler(id, who)
    end
  end
  local function fresh(double)
    local b, copy = f.fresh("TACKLE", { enemy = true }).battle, require("src.mods.Merge").deepCopy
    b.double = double ~= false
    if b.double then
      put(b, 2, actor(copy(b.player.mon), 2))
      put(b, 3, actor(copy(b.enemy.mon), 3))
    end
    if not native then
      b:syncSides()
    end
    for id = 0, b.double and 3 or 1 do
      local a = at(b, id)
      a.mon.nickname, a.mon.hp, a.mon.level = "P" .. id, 10000, 30
      if native then
        a.mon.maxHp, a.mon.moves, a.mon.pp, a.mon.maxPp =
          10000, { 270, 33, 84, 600 }, { 20, 10, 10, 10 }, { 20, 10, 10, 10 }
        for _, key in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
          a.mon[key] = 50
        end
        a.ability, a.mon.ability, a.type1, a.type2 = 0, 0, 0, 0
      else
        a.curStats =
          { hp = 10000, attack = 50, defense = 50, speed = 50, special = 50, spatk = 50, spdef = 50 }
        a.mon.stats, a.curTypes, a.abilityOverride = a.curStats, { "NORMAL" }, false
        a.curMoves = {
          { id = f.ids.HELPING_HAND, pp = 20 },
          { id = f.ids.TACKLE, pp = 10 },
          { id = f.ids.THUNDERSHOCK, pp = 10 },
          { id = f.ids.TARGET_BOTH, pp = 10 },
        }
        a.mon.moves = a.curMoves
      end
    end
    b.rng = function(lo, hi)
      if lo == 85 and hi == 100 then
        return roll
      end
      return lo or 0
    end
    moves, hits = {}, {}
    return b
  end
  local function typed(a, kind)
    if native then
      a.type1, a.type2 =
        ({ NORMAL = 0, STEEL = 8, GHOST = 7, FIRE = 10, ELECTRIC = 13 })[kind],
        ({ NORMAL = 0, STEEL = 8, GHOST = 7, FIRE = 10, ELECTRIC = 13 })[kind]
    else
      a.curTypes = { kind }
    end
  end
  local function pp(b, id, slot)
    return native and at(b, id).mon.pp[slot] or at(b, id).curMoves[slot].pp
  end
  local function active(b, id)
    return native and at(b, id).expHelpingHand == true or not native and at(b, id)._gen3HelpingHand == true
  end
  local function cast(b, id)
    if native then
      require("src.core.game3.battle.engine").resolveMove(
        id,
        id,
        270,
        1,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {}
      )
    else
      b:executeAction(at(b, id), at(b, id), at(b, id).curMoves[1])
    end
  end
  local slots, numbers =
    { TACKLE = 2, THUNDERSHOCK = 3, TARGET_BOTH = 4, DRAGON_RAGE = 4 },
    { TACKLE = 33, THUNDERSHOCK = 84, TARGET_BOTH = 600, DRAGON_RAGE = 82 }
  local function attack(b, id, target, name)
    name = name or "TACKLE"
    if name == "DRAGON_RAGE" then
      if native then
        at(b, id).mon.moves[4] = 82
      else
        at(b, id).curMoves[4].id = f.ids.DRAGON_RAGE
      end
    end
    f.e.choose(function()
      return { move = name, target = target }
    end)
    if native then
      local C = require("src.core.game3.battle.commands")
      local action = id % 2 == 0 and C.playerAction(b, 1, slots[name], id, target) or C.enemyAction(b, id)
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
      local action = id % 2 == 0 and at(b, id).curMoves[slots[name]] or b:enemyAction(at(b, id))
      if id % 2 == 0 then
        b.chosenTargets = { [id] = at(b, target) }
      end
      b:executeAction(at(b, id), at(b, target), action)
    end
  end
  for caster = 0, 3 do
    local partner, target = (caster + 2) % 4, caster % 2 == 0 and 1 or 0
    for _, crit in ipairs({ false, true }) do
      critical = crit
      for _, stab in ipairs({ false, true }) do
        for _, kind in ipairs({ "NORMAL", "STEEL", "GHOST" }) do
          for _, variation in ipairs({ 85, 100 }) do
            roll = variation
            for _, name in ipairs({ "TACKLE", "THUNDERSHOCK", "TARGET_BOTH", "DRAGON_RAGE" }) do
              local amounts = {}
              for _, helped in ipairs({ false, true }) do
                local b = fresh()
                typed(at(b, partner), stab and (name == "THUNDERSHOCK" and "ELECTRIC" or "NORMAL") or "FIRE")
                typed(at(b, target), kind)
                if helped then
                  cast(b, caster)
                end
                T.eq(active(b, partner), helped, "actual native effect only supports the partner")
                local before = at(b, target).mon.hp
                moves, hits = {}, {}
                attack(b, partner, target, name)
                local amount = before - at(b, target).mon.hp
                T.eq(
                  pp(b, partner, slots[name]),
                  9,
                  "actual supported move spends owned PP once: " .. caster .. "/" .. name .. "/" .. kind
                )
                T.eq(pp(b, caster, 1), helped and 19 or 20, "actual helper spends PP only when cast")
                amounts[#amounts + 1] = amount
                rows[#rows + 1] = {
                  case = "damage",
                  caster = caster,
                  critical = crit,
                  stab = stab,
                  kind = kind,
                  roll = variation,
                  move = name,
                  helped = helped,
                  amount = amount,
                  moves = moves,
                  hits = hits,
                  pp = pp(b, partner, slots[name]),
                }
              end
              if name == "DRAGON_RAGE" then
                T.same(amounts, { 40, 40 }, "fixed damage is never boosted")
              elseif kind ~= "GHOST" or name == "THUNDERSHOCK" then
                T.check(amounts[2] >= amounts[1], "Helping Hand never reduces an ordinary hit")
              end
            end
          end
        end
      end
    end
  end
  critical, roll = false, 100
  for _, spec in ipairs({
    { name = "single", single = true },
    { name = "absent", absent = true },
    { name = "fainted", fainted = true },
    { name = "sleep", sleep = true },
    { name = "protected-substitute", protected = true, supported = true },
    { name = "repeat", repeatCast = true, supported = true },
    { name = "reverse", reverse = true, supported = true },
  }) do
    local b = fresh(not spec.single)
    if spec.absent then
      put(b, 2, nil)
      if native then
        b.absent[2] = true
      end
    end
    if spec.fainted then
      at(b, 2).mon.hp = 0
      if native then
        b.absent[2] = true
      end
    end
    if spec.sleep then
      b.player.mon.status, b.player.sleepTurns = "SLP", 5
    end
    if spec.protected then
      b.player.protecting, b.player.substituteHP, at(b, 2).protecting, at(b, 2).substituteHP =
        true, 40, true, 40
    end
    cast(b, 0)
    if spec.repeatCast then
      cast(b, 0)
    end
    if spec.reverse then
      cast(b, 2)
    end
    local flags = {}
    for id = 0, b.double and 3 or 1 do
      flags[#flags + 1] = at(b, id) and active(b, id) or false
    end
    T.eq(flags[3] or false, spec.supported or false, spec.name .. " native effect success gate")
    T.eq(flags[1], false, spec.name .. " never boosts the caster")
    T.eq(
      pp(b, 0, 1),
      spec.sleep and 20 or spec.repeatCast and 18 or 19,
      spec.name .. " native PP on refusal or repetition"
    )
    rows[#rows + 1] = { case = spec.name, flags = flags, helperPP = pp(b, 0, 1), moves = moves, hits = hits }
  end
  for _, residual in ipairs({ false, true }) do
    local b = fresh()
    cast(b, 0)
    if residual then
      if native then
        require("src.core.game3.battle.engine").collectResidualEvents(
          b,
          require("src.core.game3.battle.adapter").new(b)
        )
      else
        b:endOfTurn()
      end
    end
    T.eq(active(b, 2), true, "support remains through the round and residual collection")
    if native then
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
      f.e.choose(function()
        return { move = "TACKLE", target = 0 }
      end)
      b.queue, b.pendingActions = {}, { [2] = at(b, 2).curMoves[2] }
      b:resolveTurn(b.player.curMoves[2])
    end
    T.eq(active(b, 2), false, "next native planning clears support before execution")
    moves, hits = {}, {}
    attack(b, 2, 1)
    rows[#rows + 1] =
      { case = residual and "residual-expiry" or "turn-expiry", hits = hits, pp = pp(b, 2, 2) }
  end
  do
    local b = fresh()
    cast(b, 0)
    if native then
      at(b, 2).confusionTurns = 3
    else
      at(b, 2).confusedTurns = 3
    end
    local before = at(b, 2).mon.hp
    moves, hits = {}, {}
    attack(b, 2, 1)
    local amount = before - at(b, 2).mon.hp
    T.eq(amount, 13, "Helping Hand does not boost a native confusion self-hit")
    T.eq(pp(b, 2, 2), 10, "confusion refusal spends no move PP")
    rows[#rows + 1] = { case = "confusion", amount = amount, pp = pp(b, 2, 2), moves = moves, hits = hits }
  end
  do
    local b = fresh()
    cast(b, 0)
    moves, hits = {}, {}
    attack(b, 2, 1)
    attack(b, 2, 1)
    T.same(
      hits,
      { { target = "P1", amount = 24 }, { target = "P1", amount = 24 } },
      "support applies to every native attack until the next planning boundary"
    )
    T.eq(pp(b, 2, 2), 8, "two supported actions spend two PP")
    rows[#rows + 1] = { case = "two-actions", hits = hits, pp = pp(b, 2, 2) }
  end
  do
    local b = fresh()
    if native then
      b.player.mon.speed, b.enemy.mon.speed, at(b, 3).mon.speed = 1, 900, 800
    else
      b.player.curStats.speed, b.enemy.curStats.speed, at(b, 3).curStats.speed = 1, 900, 800
    end
    f.e.choose(function()
      return { move = "TACKLE", target = 0 }
    end)
    moves, hits = {}, {}
    if native then
      local C, E, A =
        require("src.core.game3.battle.commands"),
        require("src.core.game3.battle.engine"),
        require("src.core.game3.battle.adapter")
      local ad = A.new(b)
      local actions = E.planTurnActions(b, ad, {
        [0] = C.playerAction(b, 1, 1, 0, 0),
        [2] = C.playerAction(b, 1, 2, 2, 1),
        [1] = C.enemyAction(b, 1),
        [3] = C.enemyAction(b, 3),
      })
      for _, a in ipairs(actions) do
        if a.kind == "move" then
          E.resolveMove(a.user, a.target, a.move, a.slot, ad, b, {})
        end
      end
    else
      b.queue, b.pendingActions = {}, { [2] = at(b, 2).curMoves[2] }
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
      T.check(count < 1000, "actual native Helping Hand priority queue settles")
    end
    T.eq(
      moves[1] and moves[1].move,
      "HELPING_HAND",
      "priority five supports the partner before faster opponents"
    )
    T.same(
      hits,
      { { target = "P0", amount = 16 }, { target = "P0", amount = 16 }, { target = "P1", amount = 24 } },
      "real queue applies support exactly once at native damage calculation"
    )
    rows[#rows + 1] = { case = "priority-queue", moves = moves, hits = hits, pp = pp(b, 2, 2) }
  end
  local b = fresh()
  cast(b, 0)
  local mon = require("src.mods.Merge").deepCopy(at(b, 2).mon)
  put(b, 2, actor(mon, 2))
  T.eq(active(b, 2), false, "replacement battler does not inherit support")
  rows[#rows + 1] = { case = "replacement", active = active(b, 2) }
  stopHit()
  stopMove()
  stopCrit()
  f.close()
  return rows
end
return M
