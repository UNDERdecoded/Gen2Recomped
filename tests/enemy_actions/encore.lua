local M = {}
function M.fixture(root, backend, version)
  local native = backend == "gen1"
  return dofile(root .. "/tests/enemy_actions/fixture.lua").new(
    root,
    backend,
    version,
    3,
    "unified",
    function(data, _, ids, rom, names)
      for _, row in ipairs({ { 227, "ENCORE", 90 }, { 119, "MIRROR_MOVE", 9 }, { 700, "MOD_CUSTOM", 0 } }) do
        local number, name, effect = unpack(row)
        local id = native and name or ("MOVE_%03d"):format(number)
        ids[name], names[number] = id, name
        if native then
          local def = {
            effect = effect,
            power = 0,
            type = 0,
            accuracy = 100,
            pp = 10,
            target = 0,
            flags = 2,
            secondaryChance = 0,
            priority = 0,
          }
          data.gen3Moves._rom[number], rom[number], data.gen3Pokemon._moveNames[number] = def, def, name
          data.gen3Pokemon._types[4], data.gen3Pokemon._abilities[4] = { 0, 0 }, { 0, 0 }
        else
          data.moves[id] = {
            id = id,
            index = number,
            name = name,
            effect = name .. "_EFFECT",
            gen3Effect = effect,
            power = 0,
            type = "NORMAL",
            accuracy = 100,
            pp = 10,
            target = 0,
            flags = 2,
            protectAffected = true,
          }
          if name == "MOD_CUSTOM" then
            data.moves[id].index = nil
          end
          data.pokemon.CHARMANDER.types, data.pokemon.CHARMANDER.abilities = { "NORMAL" }, {}
        end
      end
    end
  )
end
function M.run(root, backend, version)
  local source = backend == "gen1"
  local f = M.fixture(root, backend, version)
  local T, Copy, rows = f.T, require("src.mods.Merge").deepCopy, {}
  local draws, events = {}, {}
  local stop = f.e.api.events:on("battle.move_used", function(e)
    events[#events + 1] =
      { user = e.user.mon.nickname, target = e.target and e.target.mon.nickname, move = e.move.id }
  end)
  local noCrit = f.e.api.hooks:wrap("battle.crit", function()
    return false
  end)
  local function at(b, id)
    return source and b.battlers[id] or b:battlerAt(id)
  end
  local function fresh(double, word)
    local b = f.fresh("TACKLE", { enemy = true }).battle
    b.double = double
    if not source then
      b:syncSides()
    end
    if double then
      for id = 2, 3 do
        local mon = Copy(at(b, id % 2).mon)
        if source then
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
    if not source then
      b:syncSides()
    end
    for id = 0, double and 3 or 1 do
      local a = at(b, id)
      a.mon.nickname = "P" .. id
      if source then
        a.mon.moves, a.mon.pp, a.mon.maxPp = { 33, 227, 10, 119 }, { 10, 10, 10, 10 }, { 10, 10, 10, 10 }
        a.mon.maxHp, a.ability, a.mon.ability, a.type1, a.type2 = 400, 0, 0, 0, 0
        a.mon.speed = 100 - id * 10
      else
        a.mon.moves = {
          { id = f.ids.TACKLE, pp = 10 },
          { id = f.ids.ENCORE, pp = 10 },
          { id = f.ids.SCRATCH, pp = 10 },
          { id = f.ids.MIRROR_MOVE, pp = 10 },
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
      local value = lo == 0 and hi == 3 and word or hi
      draws[#draws + 1] = { lo = lo, hi = hi, value = value }
      return value
    end
    return b
  end
  local function number(id)
    if source then
      return tonumber(id)
    end
    return id == "UNKNOWN" and 999
      or id == f.ids.MOD_CUSTOM and 700
      or id and f.data.moves[id] and f.data.moves[id].index
  end
  local function view(a)
    local pp = {}
    for i = 1, 4 do
      pp[i] = source and a.mon.pp[i] or a.mon.moves[i].pp
    end
    return {
      turns = a[source and "expEncoreTurns" or "encoreTurns"],
      move = number(a[source and "expEncoreMove" or "encoreMove"]),
      slot = a[source and "expEncoreSlot" or "encoreSlot"],
      hp = a.mon.hp,
      pp = pp,
      last = number(a[source and "lastMoveId" or "lastMove"]),
    }
  end
  local function last(a, n)
    a[source and "lastMoveId" or "lastMove"] = source and n
      or n
        and ({
          [33] = f.ids.TACKLE,
          [10] = f.ids.SCRATCH,
          [227] = f.ids.ENCORE,
          [119] = f.ids.MIRROR_MOVE,
          [165] = f.ids.STRUGGLE,
          [999] = "UNKNOWN",
          [700] = f.ids.MOD_CUSTOM,
        })[n]
  end
  local function cast(b, uid, tid, slot, called)
    local user, target = at(b, uid), at(b, tid)
    if source then
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
  local function tick(b)
    if source then
      require("src.core.game3.battle.engine").collectResidualEvents(
        b,
        require("src.core.game3.battle.adapter").new(b)
      )
    else
      b:endOfTurn()
    end
  end
  local function record(b, label, uid, tid)
    local field = {}
    for id = 0, b.double and 3 or 1 do
      field[#field + 1] = { name = at(b, id).mon.nickname, hp = at(b, id).mon.hp }
    end
    rows[#rows + 1] = {
      label = label,
      user = view(at(b, uid)),
      target = view(at(b, tid)),
      draws = Copy(draws),
      events = Copy(events),
      field = field,
    }
  end
  for _, double in ipairs({ false, true }) do
    for uid = 0, double and 3 or 1 do
      local tid = uid % 2 == 0 and uid + 1 or uid - 1
      for word = 0, 3 do
        for _, kind in ipairs({
          "ordinary",
          "no_last",
          "unknown",
          "empty_pp",
          "already",
          "zero_counter",
          "mirror",
          "struggle",
          "encore",
          "protected",
          "substitute",
          "hidden",
          "custom",
        }) do
          draws, events = {}, {}
          local b = fresh(double, word)
          local target = at(b, tid)
          last(target, 33)
          if kind == "no_last" then
            last(target, nil)
          end
          if kind == "unknown" then
            last(target, 999)
          end
          if kind == "mirror" then
            last(target, 119)
          end
          if kind == "struggle" then
            last(target, 165)
          end
          if kind == "encore" then
            last(target, 227)
          end
          if kind == "empty_pp" then
            if source then
              target.mon.pp[1] = 0
            else
              target.curMoves[1].pp = 0
            end
          end
          if kind == "custom" then
            last(target, 700)
            if source then
              target.mon.moves[1] = 700
            else
              target.curMoves[1].id = f.ids.MOD_CUSTOM
            end
          end
          if kind == "already" or kind == "zero_counter" then
            target[source and "expEncoreTurns" or "encoreTurns"] = kind == "already" and 4 or 0
          end
          if kind == "protected" then
            target[source and "expProtected" or "protecting"] = true
          end
          if kind == "substitute" then
            target.substituteHP = 25
          end
          if kind == "hidden" then
            if source then
              target.semiInvulnerable = "ON_AIR"
            else
              target.invulnerable, target.hiddenAs = true, "air"
            end
          end
          cast(b, uid, tid, 2)
          if kind == "ordinary" or kind == "substitute" or kind == "zero_counter" or kind == "custom" then
            T.eq(
              target[source and "expEncoreTurns" or "encoreTurns"],
              word + 3,
              "native Encore duration consumes its own four-value roll"
            )
            T.eq(
              target[source and "expEncoreSlot" or "encoreSlot"],
              1,
              "Encore records the original move slot"
            )
          end
          record(b, (double and "double" or "single") .. "/" .. uid .. "/" .. word .. "/" .. kind, uid, tid)
        end
      end
      for _, kind in ipairs({ "expiry", "pp_depletion", "slot_replaced", "slot_swapped", "forced", "called" }) do
        draws, events = {}, {}
        local b = fresh(double, 3)
        local target = at(b, tid)
        last(target, 33)
        cast(b, uid, tid, 2)
        record(b, kind .. "/applied/" .. uid, uid, tid)
        if kind == "pp_depletion" then
          if source then
            target.mon.pp[1] = 0
          else
            target.curMoves[1].pp = 0
          end
        elseif kind == "slot_replaced" then
          if source then
            target.mon.moves[1] = 10
          else
            target.curMoves[1].id = f.ids.SCRATCH
          end
        elseif kind == "slot_swapped" then
          if source then
            target.mon.moves[1], target.mon.moves[3] = target.mon.moves[3], target.mon.moves[1]
          else
            target.curMoves[1], target.curMoves[3] = target.curMoves[3], target.curMoves[1]
          end
        elseif kind == "forced" or kind == "called" then
          cast(b, tid, uid, 3, kind == "called")
          record(b, kind .. "/executed/" .. uid, uid, tid)
        end
        for step = 1, 6 do
          tick(b)
          record(b, kind .. "/residual/" .. step .. "/" .. uid, uid, tid)
        end
        T.eq(
          target[source and "expEncoreTurns" or "encoreTurns"],
          nil,
          "Encore eventually clears through actual residuals"
        )
      end
    end
  end
  for uid = 0, 3 do
    for _, kind in ipairs({
      "selected",
      "follow_me",
      "lightning_rod",
      "self",
      "random",
      "chosen_random",
      "absent_left",
      "depends",
    }) do
      draws, events = {}, {}
      local b = fresh(true, 0)
      local foe = uid % 2 == 0 and uid + 1 or uid - 1
      local user = at(b, uid)
      last(user, 33)
      cast(b, foe, uid, 2)
      local tackle = source and f.data.gen3Moves._rom[33] or f.data.moves[f.ids.TACKLE]
      local scratch = source and f.data.gen3Moves._rom[10] or f.data.moves[f.ids.SCRATCH]
      local oldType, oldTarget, oldChosen = tackle.type, tackle.target, scratch.target
      tackle.target = kind == "self" and 16 or kind == "random" and 4 or kind == "depends" and 1 or 0
      if kind == "chosen_random" then
        scratch.target = 4
      end
      local opposite = uid % 2 == 0 and 1 or 0
      local right = opposite + 2
      if kind == "follow_me" then
        if source then
          (uid % 2 == 0 and b.enemySide or b.playerSide).expFollowMeId = right
        else
          b.sides[uid % 2 == 0 and 2 or 1]._gen3FollowMePosition = right
        end
      end
      if kind == "lightning_rod" then
        tackle.type = source and 13 or "ELECTRIC"
        local holder = at(b, right)
        if source then
          holder.ability, holder.mon.ability = 31, 31
        else
          holder.abilityOverride = "LIGHTNING_ROD"
        end
      end
      if kind == "absent_left" then
        at(b, opposite).mon.hp = 0
        b.absent = b.absent or {}
        b.absent[opposite] = true
      end
      local count = 0
      b.rng = function(lo, hi)
        local value = hi
        if lo == 0 and hi == 3 then
          count = count + 1
          value = count == 1 and uid or count == 2 and ((uid + 2) % 4) or right
        end
        draws[#draws + 1] = { lo = lo, hi = hi, value = value }
        return value
      end
      cast(b, uid, foe, 3)
      record(b, "retarget/" .. uid .. "/" .. kind, uid, foe)
      tackle.type, tackle.target, scratch.target = oldType, oldTarget, oldChosen
    end
  end
  for _, uid in ipairs({ 1, 3 }) do
    for _, state in ipairs({ "active", "cleared_after_planning" }) do
      draws, events = {}, {}
      local b = fresh(true, 3)
      last(at(b, uid), 33)
      cast(b, 0, uid, 2)
      -- This contract starts at the prepared selection boundary. The combined
      -- fork owns an earlier cartridge-faithful Quick Claw word; Gen1's standalone
      -- command does not prepare it. Give both engines the same explicit input.
      b.randomTurnNumber, b._nativeOrderReady = 65535, true
      local function cancel()
        if state == "cleared_after_planning" then
          local actor = at(b, uid)
          actor[source and "expEncoreTurns" or "encoreTurns"] = nil
          actor[source and "expEncoreMove" or "encoreMove"] = nil
          actor[source and "expEncoreSlot" or "encoreSlot"] = nil
        end
      end
      f.e.choose(function()
        return { move = "SCRATCH", slot = 3, target = 2 }
      end)
      if source then
        local action = require("src.core.game3.battle.commands").enemyAction(b, uid)
        T.eq(action.move, 10, "public mod supplies the requested alternative before native planning")
        local Engine = require("src.core.game3.battle.engine")
        local ad = require("src.core.game3.battle.adapter").new(b)
        local planned = Engine.planTurnActions(b, ad, { [uid] = action })
        cancel()
        for _, row in ipairs(planned) do
          if row.kind == "move" then
            Engine.resolveMove(row.user, row.target, row.move, row.slot, ad, b, {})
          end
        end
      else
        local action = b:enemyAction(at(b, uid))
        T.eq(action.id, f.ids.SCRATCH, "public mod supplies the requested alternative before native planning")
        action = require("src.battle.Gen3Encore").plan(at(b, uid), action)
        cancel()
        b:executeAction(at(b, uid), at(b, 0), action)
      end
      f.e.choose(nil)
      T.eq(events[#events].move, "TACKLE", "native planning enforces Encore after the public choice")
      T.eq(events[#events].target, "P2", "early Encore planning retains the explicitly chosen target")
      record(b, "planned_public/" .. state .. "/" .. uid, uid, 0)
      rows[#rows].preparedTurnWord = b.randomTurnNumber
    end
  end
  noCrit()
  stop()
  f.close()
  return rows
end
return M
