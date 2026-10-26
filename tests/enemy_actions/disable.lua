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
      for _, row in ipairs({
        { 50, "DISABLE", 86 },
        { 114, "HAZE", 25 },
        { 144, "TRANSFORM", 57 },
        { 117, "BIDE", 26 },
        { 700, "MOD_CUSTOM", 0 },
      }) do
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
    end,
    entry
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
        a.mon.moves, a.mon.pp, a.mon.maxPp = { 33, 50, 10, 114 }, { 10, 10, 10, 10 }, { 10, 10, 10, 10 }
        a.mon.maxHp, a.ability, a.mon.ability, a.type1, a.type2 = 400, 0, 0, 0, 0
        a.mon.speed = 100 - id * 10
      else
        a.mon.moves = {
          { id = f.ids.TACKLE, pp = 10 },
          { id = f.ids.DISABLE, pp = 10 },
          { id = f.ids.SCRATCH, pp = 10 },
          { id = f.ids.HAZE, pp = 10 },
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
  local nums = {
    [33] = f.ids.TACKLE,
    [10] = f.ids.SCRATCH,
    [50] = f.ids.DISABLE,
    [114] = f.ids.HAZE,
    [144] = f.ids.TRANSFORM,
    [700] = f.ids.MOD_CUSTOM,
    [999] = "UNKNOWN",
    [117] = f.ids.BIDE,
  }
  local function number(id)
    if source then
      return tonumber(id)
    end
    for num, name in pairs(nums) do
      if name == id then
        return num
      end
    end
  end
  local function last(a, num)
    a[source and "lastMoveId" or "lastMove"] = source and num or nums[num]
  end
  local function setMove(a, slot, num)
    if source then
      a.mon.moves[slot] = num
    else
      a.curMoves[slot].id = nums[num]
    end
  end
  local function setDisabled(a, num, turns)
    a[source and "expDisabledMove" or "disabledMove"] = source and num or nums[num]
    a[source and "expDisableTurns" or "disabledTurns"] = turns
  end
  local function view(a)
    local pp, learned = {}, {}
    for i = 1, 4 do
      pp[i] = source and a.mon.pp[i] or a.curMoves[i].pp
      learned[i] = number(source and a.mon.moves[i] or a.curMoves[i].id)
    end
    return {
      turns = a[source and "expDisableTurns" or "disabledTurns"],
      move = number(a[source and "expDisabledMove" or "disabledMove"]),
      hp = a.mon.hp,
      pp = pp,
      learned = learned,
      last = number(a[source and "lastMoveId" or "lastMove"]),
      confusion = a[source and "confusionTurns" or "confusedTurns"],
      bideTurns = a.bideTurns,
      bideDamage = a.bideDamage,
    }
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
  local function record(b, label)
    local field = {}
    for id = 0, b.double and 3 or 1 do
      field[#field + 1] = view(at(b, id))
    end
    -- Compare the real read-only native admission checks, not a duplicate
    -- restriction formula or Gen1's snapshot (which omits disabled here).
    local admission, phase, choosing = {}, b.phase, b.choosingSlot
    b.phase, b.choosingSlot = "moveSelect", 0
    for slot = 1, 4 do
      if source then
        admission[slot] = require("src.core.game3.battle.commands").selectionError(b, slot, 0) == nil
      else
        admission[slot] = require("src.battle.BattleCommands").reason(b, { kind = "move", slot = slot })
          == nil
      end
    end
    b.phase, b.choosingSlot = phase, choosing
    rows[#rows + 1] =
      { label = label, field = field, admission = admission, draws = Copy(draws), events = Copy(events) }
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
          "protected",
          "substitute",
          "hidden",
          "custom",
          "duplicate",
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
          if kind == "empty_pp" then
            if source then
              target.mon.pp[1] = 0
            else
              target.curMoves[1].pp = 0
            end
          end
          if kind == "custom" then
            setMove(target, 1, 700)
            last(target, 700)
          end
          if kind == "duplicate" then
            setMove(target, 3, 33)
          end
          if kind == "already" or kind == "zero_counter" then
            setDisabled(target, 10, kind == "already" and 4 or 0)
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
          if kind == "ordinary" or kind == "substitute" or kind == "custom" or kind == "duplicate" then
            T.eq(
              target[source and "expDisableTurns" or "disabledTurns"],
              word + 2,
              "native Disable draws two to five residual phases"
            )
            T.eq(
              number(target[source and "expDisabledMove" or "disabledMove"]),
              kind == "custom" and 700 or 33,
              "Disable owns the last used learned move"
            )
          end
          record(b, (double and "double" or "single") .. "/" .. uid .. "/" .. word .. "/" .. kind)
        end
      end
      for _, kind in ipairs({
        "expiry",
        "pp_depletion",
        "removed",
        "swapped",
        "blocked",
        "confused",
        "different",
        "called",
        "duplicate_blocked",
        "haze",
        "transform",
        "bide",
        "locked",
      }) do
        draws, events = {}, {}
        local b = fresh(double, 3)
        local target = at(b, tid)
        last(target, 33)
        if kind == "bide" then
          setMove(target, 1, 117)
          last(target, 117)
          target.bideTurns, target.bideDamage = 2, 73
        end
        cast(b, uid, tid, 2)
        record(b, kind .. "/applied/" .. uid)
        if kind == "pp_depletion" then
          if source then
            target.mon.pp[1] = 0
          else
            target.curMoves[1].pp = 0
          end
        elseif kind == "removed" then
          setMove(target, 1, 10)
        elseif kind == "swapped" then
          if source then
            target.mon.moves[1], target.mon.moves[3] = target.mon.moves[3], target.mon.moves[1]
          else
            target.curMoves[1], target.curMoves[3] = target.curMoves[3], target.curMoves[1]
          end
        elseif kind == "haze" then
          cast(b, tid, uid, 4)
        elseif kind == "transform" then
          setMove(target, 4, 144)
          cast(b, tid, uid, 4)
        elseif kind == "bide" then
          if source then
            cast(b, tid, uid, 1)
          else
            b:executeAction(target, at(b, uid), { special = "bide" })
          end
        elseif
          kind == "blocked"
          or kind == "confused"
          or kind == "called"
          or kind == "different"
          or kind == "duplicate_blocked"
          or kind == "locked"
        then
          local slot = kind == "different" and 3 or 1
          if kind == "confused" then
            target[source and "confusionTurns" or "confusedTurns"] = 4
          end
          if kind == "duplicate_blocked" then
            setMove(target, 3, 33)
            slot = 3
          end
          if kind == "locked" then
            target.bideTurns, target.bideDamage = 2, 73
            if source then
              target.twoTurnMove, target.expRolloutTimer, target.expFuryCutter, target.expRampageTurns =
                33, 3, 4, 2
              target.expLockedMove, target.expLockedSlot, target.expUproarTurns, target.uproar =
                33, 1, 2, true
            else
              target.charging, target.rampMove, target.rampRun = target.curMoves[1], f.ids.TACKLE, 3
              target.thrashMove, target.thrashTurns, target.uproarTurns = target.curMoves[1], 2, 2
            end
          end
          cast(b, tid, uid, slot, kind == "called")
          if kind == "locked" then
            for _, key in
              ipairs(
                source
                    and {
                      "twoTurnMove",
                      "expRolloutTimer",
                      "expFuryCutter",
                      "expRampageTurns",
                      "expLockedMove",
                      "expLockedSlot",
                      "expUproarTurns",
                      "uproar",
                    }
                  or { "charging", "rampMove", "rampRun", "thrashMove", "thrashTurns", "uproarTurns" }
              )
            do
              T.eq(target[key], nil, "native disabled interruption cancels multi-turn state: " .. key)
            end
          end
        end
        record(b, kind .. "/executed/" .. uid)
        for step = 1, 5 do
          tick(b)
          record(b, kind .. "/residual/" .. step .. "/" .. uid)
        end
        T.eq(
          target[source and "expDisabledMove" or "disabledMove"],
          nil,
          "native Disable clears through actual lifecycle"
        )
        T.eq(
          target[source and "expDisableTurns" or "disabledTurns"],
          nil,
          "native Disable clears its timer too"
        )
      end
    end
  end
  stop()
  noCrit()
  f.close()
  return rows
end
return M
