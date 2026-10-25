local M = {}
function M.fixture(root, backend, version, entry)
  local native = backend == "gen1"
  return dofile(root .. "/tests/enemy_actions/fixture.lua").new(
    root,
    backend,
    version,
    3,
    "unified",
    function(data, _, ids, rom, names)
      if not native then
        data.items.FOCUS_BAND = {
          index = 196,
          name = "FOCUS BAND",
          holdEffect = "FOCUS_BAND",
          gen3HoldEffect = 39,
          holdEffectParam = 10,
        }
        data.items.SCOPE_LENS = { index = 198, name = "SCOPE LENS", holdEffect = "SCOPE_LENS" }
        data.items.LUCKY_PUNCH = { index = 222, name = "LUCKY PUNCH", holdEffect = "LUCKY_PUNCH" }
        data.type_chart.matchups[#data.type_chart.matchups + 1] =
          { attacker = "NORMAL", defender = "GHOST", multiplier = 0 }
      end
      for _, row in ipairs({
        { 3, "DOUBLE_SLAP", 29, "TWO_TO_FIVE_ATTACKS_EFFECT" },
        { 24, "DOUBLE_KICK", 44, "ATTACK_TWICE_EFFECT" },
        { 41, "TWINEEDLE", 77, "TWINEEDLE_EFFECT" },
        { 99, "RAGE", 81, "RAGE_EFFECT" },
        { 700, "MOD_RAGE", 81, "RAGE_EFFECT" },
      }) do
        local number, name, effect, hostEffect = unpack(row)
        local id = native and name or ("MOVE_%03d"):format(number)
        ids[name], names[number] = id, name
        if native then
          local def = {
            effect = effect,
            power = 15,
            type = 0,
            accuracy = 100,
            pp = 10,
            target = 0,
            flags = 51,
            secondaryChance = 20,
            priority = 0,
          }
          data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = def, def, name
          data.gen3Pokemon._types[4], data.gen3Pokemon._abilities[4] = { 0, 0 }, { 0, 0 }
        else
          data.moves[id] = {
            id = id,
            index = number,
            name = name,
            effect = hostEffect,
            gen3Effect = effect,
            power = 15,
            type = "NORMAL",
            accuracy = 100,
            pp = 10,
            target = 0,
            flags = 51,
            protectAffected = true,
            secondaryChance = 20,
          }
          if number == 700 then
            data.moves[id].index = nil
          end
          data.pokemon.CHARMANDER.types, data.pokemon.CHARMANDER.abilities = { "NORMAL" }, {}
        end
      end
    end,
    entry
  )
end
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local T, Copy = f.T, require("src.mods.Merge").deepCopy
  local rows, draws, damage, used, accuracy = {}, {}, {}, {}, {}
  local owner, phase, currentKind, incomingHits
  local off = f.e.api.events:on("battle.damage_dealt", function(e)
    damage[#damage + 1] = {
      user = e.user.mon.nickname,
      target = e.target.mon.nickname,
      move = e.move.id,
      damage = e.damage,
      crit = e.crit or false,
      substitute = e.substitute or false,
      attack = owner and owner.stages.attack or 0,
      rage = owner and not not owner.rage or false,
    }
    if phase == "incoming" then
      incomingHits = incomingHits + 1
      if currentKind == "later_immunity" and incomingHits == 1 then
        if native then
          owner.type1, owner.type2 = 7, 7
        else
          owner.curTypes = { "GHOST" }
        end
      end
    end
  end)
  local offMove = f.e.api.events:on("battle.move_used", function(e)
    used[#used + 1] = { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
  end)
  local offAccuracy = f.e.api.hooks:wrap("battle.accuracy", function(nextAccuracy, ...)
    accuracy[#accuracy + 1] =
      { rage = owner and not not owner.rage or false, attack = owner and owner.stages.attack or 0 }
    return nextAccuracy(...)
  end)
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  local nums = {
    [99] = f.ids.RAGE,
    [3] = f.ids.DOUBLE_SLAP,
    [24] = f.ids.DOUBLE_KICK,
    [33] = f.ids.TACKLE,
    [700] = f.ids.MOD_RAGE,
  }
  local function num(id)
    if native then
      return tonumber(id)
    end
    for n, name in pairs(nums) do
      if name == id then
        return n
      end
    end
  end
  local function fresh(double)
    local b = f.fresh("TACKLE", { enemy = true }).battle
    b.double = double
    if not native then
      b:syncSides()
    end
    if double then
      for id = 2, 3 do
        local mon = Copy(at(b, id % 2).mon)
        if native then
          b.battlers[id] = require("src.core.game3.battle.state").makeBattler(
            mon,
            id % 2 == 0 and "player" or "enemy",
            { id = id, partyIndex = 2 }
          )
        else
          b:placeBattler(id, require("src.battle.BattleState").makeBattler(f.data, mon, id % 2 == 0))
        end
      end
    end
    if not native then
      b:syncSides()
    end
    for id = 0, double and 3 or 1 do
      local a = at(b, id)
      a.mon.nickname = "P" .. id
      if native then
        a.mon.moves, a.mon.pp, a.mon.maxPp = { 99, 3, 24, 33 }, { 10, 10, 10, 10 }, { 10, 10, 10, 10 }
        a.mon.maxHp, a.ability, a.mon.ability, a.type1, a.type2 = 400, 0, 0, 0, 0
        a.mon.speed = 100 - id * 10
      else
        a.mon.moves = {
          { id = f.ids.RAGE, pp = 10 },
          { id = f.ids.DOUBLE_SLAP, pp = 10 },
          { id = f.ids.DOUBLE_KICK, pp = 10 },
          { id = f.ids.TACKLE, pp = 10 },
        }
        a.curMoves, a.curTypes, a.abilityOverride = a.mon.moves, { "NORMAL" }, false
        a.mon.stats.hp = 400
        for _, stat in ipairs({ "attack", "defense", "spatk", "spdef" }) do
          a.curStats[stat] = 50
        end
        a.curStats.speed = 100 - id * 10
      end
      a.mon.hp = 400
    end
    b.rng = function(lo, hi)
      local v = hi
      if lo == 0 and hi == 1 and currentKind == "confused" then
        v = 0
      end
      draws[#draws + 1] = { lo = lo, hi = hi, value = v }
      return v
    end
    return b
  end
  local function cast(b, uid, tid, slot, called)
    local user, target = at(b, uid), at(b, tid)
    if native then
      local nativeSlot = slot
      if called then
        nativeSlot = nil
      end
      require("src.core.game3.battle.engine").resolveMove(
        uid,
        tid,
        user.mon.moves[slot],
        nativeSlot,
        require("src.core.game3.battle.adapter").new(b),
        b,
        {},
        { called = called }
      )
    elseif called then
      b:performMove(user, target, user.curMoves[slot], true)
    else
      b:executeAction(user, target, user.curMoves[slot])
    end
  end
  local function record(b, label)
    local field = {}
    for id = 0, b.double and 3 or 1 do
      local a = at(b, id)
      local pp = {}
      for slot = 1, 4 do
        pp[slot] = native and a.mon.pp[slot] or a.curMoves[slot].pp
      end
      field[#field + 1] = {
        hp = a.mon.hp,
        pp = pp,
        rage = not not a.rage,
        legacyLock = not not a.rageMove,
        attack = a.stages.attack or 0,
        last = num(native and a.lastMoveId or a.lastMove),
        sub = tonumber(a.substituteHP) or 0,
        status = a.mon.status,
      }
    end
    rows[#rows + 1] = {
      label = label,
      field = field,
      draws = Copy(draws),
      damage = Copy(damage),
      used = Copy(used),
      accuracy = Copy(accuracy),
    }
  end
  for _, double in ipairs({ false, true }) do
    for uid = 0, double and 3 or 1 do
      local tid = uid % 2 == 0 and uid + 1 or uid - 1
      for _, previous in ipairs({ false, true }) do
        for _, kind in ipairs({
          "ordinary",
          "repeated",
          "protected",
          "hidden",
          "immune",
          "substitute",
          "accuracy_miss",
          "disabled",
          "sleep",
          "confused",
          "called",
          "called_disabled",
          "custom",
          "absorbed",
        }) do
          currentKind = kind
          phase = "producer"
          draws, damage, used, accuracy = {}, {}, {}, {}
          local b = fresh(double)
          owner = at(b, uid)
          local foe = at(b, tid)
          owner.rage = previous or nil
          local raw = native and f.data.gen3Moves._rom[99] or f.data.moves[f.ids.RAGE]
          local accuracy, moveType = raw.accuracy, raw.type
          if kind == "protected" then
            foe[native and "expProtected" or "protecting"] = true
          end
          if kind == "hidden" then
            if native then
              foe.semiInvulnerable = "ON_AIR"
            else
              foe.invulnerable, foe.hiddenAs = true, "air"
            end
          end
          if kind == "immune" then
            if native then
              foe.type1, foe.type2 = 7, 7
            else
              foe.curTypes = { "GHOST" }
            end
          end
          if kind == "substitute" then
            foe.substituteHP = 100
          end
          if kind == "accuracy_miss" then
            raw.accuracy = 90
          end
          if kind == "disabled" or kind == "called_disabled" then
            owner[native and "expDisabledMove" or "disabledMove"] = native and 99 or f.ids.RAGE
          end
          if kind == "sleep" then
            owner.mon.status = "SLP"
            owner.sleepTurns = 2
          end
          if kind == "confused" then
            owner[native and "confusionTurns" or "confusedTurns"] = 4
          end
          if kind == "custom" then
            if native then
              owner.mon.moves[1] = 700
            else
              owner.curMoves[1].id = f.ids.MOD_RAGE
            end
          end
          if kind == "absorbed" then
            raw.type = native and 13 or "ELECTRIC"
            if native then
              foe.ability, foe.mon.ability = 10, 10
            else
              foe.abilityOverride = "VOLT_ABSORB"
            end
          end
          cast(b, uid, tid, 1, kind == "called" or kind == "called_disabled")
          if kind == "repeated" then
            cast(b, uid, tid, 1)
          end
          if
            kind == "ordinary"
            or kind == "repeated"
            or kind == "immune"
            or kind == "substitute"
            or kind == "called"
            or kind == "called_disabled"
            or kind == "custom"
          then
            T.eq(owner.rage, true, "native Rage activates independently of a legacy move lock")
            T.eq(owner.rageMove, nil, "native Rage never installs the free-PP legacy controller")
          end
          record(
            b,
            (double and "double" or "single") .. "/" .. uid .. "/" .. tostring(previous) .. "/" .. kind
          )
          raw.accuracy, raw.type = accuracy, moveType
        end
      end
      for _, kind in ipairs({
        "ordinary",
        "multi",
        "two",
        "sub_survive",
        "sub_break",
        "endure",
        "cap",
        "last_stage",
        "protected",
        "hidden",
        "immune",
        "ally",
        "self_called",
        "later_immunity",
        "residual",
      }) do
        if double or kind ~= "ally" then
          currentKind = kind
          phase = "producer"
          draws, damage, used, accuracy = {}, {}, {}, {}
          local b = fresh(double)
          owner = at(b, uid)
          cast(b, uid, tid, 1)
          record(b, "incoming/" .. kind .. "/activated/" .. uid .. "/" .. tostring(double))
          phase = "incoming"
          incomingHits = 0
          local attacker = kind == "ally" and (uid + 2) % 4 or tid
          local called = kind == "self_called"
          if called then
            attacker = uid
          end
          local slot = (kind == "multi" or kind == "later_immunity") and 2 or kind == "two" and 3 or 4
          if kind == "sub_survive" then
            owner.substituteHP = 400
          end
          if kind == "sub_break" then
            owner.substituteHP = 1
          end
          if kind == "endure" then
            owner.mon.hp = 1
            owner[native and "expEnduring" or "enduring"] = true
          end
          if kind == "cap" or kind == "last_stage" then
            owner.stages.attack = kind == "cap" and 6 or 5
          end
          if kind == "protected" then
            owner[native and "expProtected" or "protecting"] = true
          end
          if kind == "hidden" then
            if native then
              owner.semiInvulnerable = "ON_AIR"
            else
              owner.invulnerable, owner.hiddenAs = true, "air"
            end
          end
          if kind == "immune" then
            if native then
              owner.type1, owner.type2 = 7, 7
            else
              owner.curTypes = { "GHOST" }
            end
          end
          if kind == "residual" then
            owner.mon.status = "PSN"
            if native then
              require("src.core.game3.battle.engine").collectResidualEvents(
                b,
                require("src.core.game3.battle.adapter").new(b)
              )
            else
              b:endOfTurn()
            end
          else
            cast(b, attacker, uid, slot, called)
          end
          local expected = (
            kind == "ordinary"
            or kind == "multi"
            or kind == "two"
            or kind == "sub_survive"
            or kind == "sub_break"
            or kind == "endure"
          )
              and 1
            or (kind == "cap" or kind == "last_stage") and 6
            or 0
          T.eq(
            owner.stages.attack or 0,
            expected,
            "native Rage boost applies once at the completed move boundary"
          )
          record(b, "incoming/" .. kind .. "/finished/" .. uid .. "/" .. tostring(double))
        end
      end
    end
  end
  for _, double in ipairs({ false, true }) do
    for _, choice in ipairs({ "rage", "other", "custom", "encore_rage", "encore_other" }) do
      currentKind, phase = choice, "planning"
      draws, damage, used, accuracy = {}, {}, {}, {}
      local b = fresh(double)
      -- Compare actual turn-word preparation with fixed choices. Earlier
      -- selection/RNG orchestration remains a separate controller boundary.
      b.randomTurnNumber, b._nativeOrderReady = nil, false
      local chosen = (choice == "rage" or choice == "encore_other") and 99 or choice == "custom" and 700 or 33
      local slot = chosen == 99 and 1 or 4
      local actions = {}
      for id = 0, double and 3 or 1 do
        local a = at(b, id)
        a.rage = true
        if chosen == 700 then
          if native then
            a.mon.moves[4] = 700
          else
            a.curMoves[4].id = f.ids.MOD_RAGE
          end
        end
        if choice == "encore_rage" or choice == "encore_other" then
          a[native and "expEncoreMove" or "encoreMove"] = native and (choice == "encore_rage" and 99 or 33)
            or (choice == "encore_rage" and f.ids.RAGE or f.ids.TACKLE)
          a[native and "expEncoreSlot" or "encoreSlot"] = choice == "encore_rage" and 1 or 4
          a[native and "expEncoreTurns" or "encoreTurns"] = 4
        end
        actions[id] = {
          kind = "move",
          move = chosen,
          slot = slot,
          battler = id,
          target = id % 2 == 0 and id + 1 or id - 1,
        }
      end
      if native then
        require("src.core.game3.battle.engine").planTurnActions(
          b,
          require("src.core.game3.battle.adapter").new(b),
          actions
        )
      else
        b.pendingActions = { [0] = at(b, 0).curMoves[slot], [2] = double and at(b, 2).curMoves[slot] or nil }
        f.e.choose(function()
          return { move = chosen == 99 and "RAGE" or chosen == 700 and "MOD_RAGE" or "TACKLE" }
        end)
        b:resolveTurn(b.pendingActions[0])
      end
      for id = 0, double and 3 or 1 do
        T.eq(
          not not at(b, id).rage,
          choice == "rage" or choice == "encore_rage",
          "real planner clears Rage using the actual forced choice before actions"
        )
      end
      record(b, "planning/" .. choice .. "/" .. tostring(double))
      rows[#rows].preparedTurnWord = b.randomTurnNumber
    end
  end
  for _, kind in ipairs({ "item", "switch", "run" }) do
    currentKind, phase = kind, "nonmove"
    draws, damage, used, accuracy = {}, {}, {}, {}
    local b = fresh(false)
    owner = at(b, 0)
    at(b, 0).rage, at(b, 1).rage = true, true
    b.randomTurnNumber, b._nativeOrderReady = 65535, true
    if native then
      require("src.core.game3.battle.engine").planTurnFromActions(
        b,
        require("src.core.game3.battle.adapter").new(b),
        { kind = kind == "item" and "bag" or kind, user = "player" },
        { kind = "move", move = 33, slot = 4, user = "enemy" }
      )
    else
      f.e.choose(function()
        return { move = "TACKLE" }
      end)
      -- The host spends non-move turns through its actual queued reply.
      b:nonMoveAction()
    end
    T.eq(owner.rage, nil, "committed non-move action clears Rage")
    T.eq(at(b, 1).rage, nil, "the independently selected enemy move clears its Rage too")
    record(b, "nonmove/" .. kind)
    rows[#rows].preparedTurnWord = b.randomTurnNumber
  end
  off()
  offMove()
  offAccuracy()
  f.close()
  return rows
end
return M
