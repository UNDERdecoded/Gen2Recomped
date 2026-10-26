local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/choice_band.lua").fixture(root, backend, version)
  local T, Copy, rows = f.T, require("src.mods.Merge").deepCopy, {}
  local function at(b, id)
    return native and b.battlers[id] or b:battlerAt(id)
  end
  local function fresh(double)
    local b = f.fresh("TACKLE").battle
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
      local user = at(b, id)
      user.mon.nickname, user.mon.hp = "P" .. id, 400
      f.moves(user, { "TACKLE", "SCRATCH", "SLEEP_TALK", "STRUGGLE" })
      f.hold(user, nil)
    end
    b.phase, b.queue, b.current = "moveSelect", {}, nil
    return b
  end
  local function pp(user, slot, value)
    if native then
      user.mon.pp[slot] = value
    else
      user.curMoves[slot].pp = value
    end
  end
  for _, double in ipairs({ false, true }) do
    for id = 0, double and 3 or 1 do
      for _, kind in ipairs({
        "unbound",
        "bound",
        "effect_only_item",
        "empty_override",
        "suppressed",
        "metadata_cleared",
        "locked_pp_empty",
        "all_pp_empty",
        "missing_locked_move",
        "disabled_locked",
        "encore_other",
        "taunted_status_lock",
        "tormented_lock",
        "tormented_struggle",
        "imprisoned_lock",
      }) do
        local b = fresh(double)
        local user, foe = at(b, id), at(b, id % 2 == 0 and id + 1 or id - 1)
        f.hold(user, kind == "effect_only_item" and 529 or kind ~= "empty_override" and 186 or nil)
        user.choicedMove = kind ~= "unbound" and 33 or nil
        if native then
          f.data.gen3Items._byId[186].holdEffect = kind == "metadata_cleared" and 0 or 29
        else
          f.data.items.ITEM_186.holdEffect = kind == "metadata_cleared" and "NONE" or "CHOICE_BAND"
        end
        if kind == "locked_pp_empty" then
          pp(user, 1, 0)
        end
        if kind == "all_pp_empty" then
          for slot = 1, 4 do
            pp(user, slot, 0)
          end
        end
        if kind == "missing_locked_move" then
          f.moves(user, { "SCRATCH", "SLEEP_TALK", "BATON_PASS", "STRUGGLE" })
        end
        if kind == "disabled_locked" then
          user[native and "expDisabledMove" or "disabledMove"] = f.moveId("TACKLE")
          user[native and "expDisableTurns" or "disabledTurns"] = 3
          if not native then
            user.disabledSlot = 1
          end
        end
        if kind == "encore_other" then
          user[native and "expEncoreMove" or "encoreMove"] = f.moveId("SCRATCH")
          user[native and "expEncoreTurns" or "encoreTurns"] = 3
          user[native and "expEncoreSlot" or "encoreSlot"] = 2
        end
        if kind == "taunted_status_lock" then
          user.choicedMove = 214
          user[native and "expTauntedTurns" or "tauntTurns"] = 2
        end
        if kind == "tormented_lock" or kind == "tormented_struggle" then
          user[native and "expTormented" or "tormented"] = true
          user[native and "lastMoveId" or "lastMove"] =
            f.moveId(kind == "tormented_struggle" and "STRUGGLE" or "TACKLE")
          if kind == "tormented_struggle" then
            user.choicedMove = 165
            f.hold(user, 529)
          end
        end
        if kind == "imprisoned_lock" then
          foe[native and "expImprison" or "imprison"] = true
          f.moves(foe, { "TACKLE" })
        end
        local trace, draws = {}, {}
        local off = f.e.api.hooks:wrap("held_item.trigger", function(nextRead, ctx)
          trace[#trace + 1] = {
            holder = ctx.mon.nickname,
            item = ctx.item,
            definition = ctx.def and ctx.def.id,
            effect = ctx.effect,
            parameter = ctx.parameter,
            trigger = ctx.trigger,
            actualBattle = ctx.battle == b,
          }
          if ctx.mon.nickname == user.mon.nickname then
            if kind == "empty_override" then
              return "HELD_CHOICE_BAND", 0
            end
            if kind == "suppressed" then
              return nil, 0
            end
          end
          return nextRead(ctx)
        end)
        b.rng = function(lo, hi)
          draws[#draws + 1] = { lo, hi, hi }
          return hi
        end
        local mask
        if native then
          mask = require("src.core.game3.battle.engine").moveLimitations(
            user,
            require("src.core.game3.battle.adapter").new(b)
          )
        else
          mask = require("src.battle.Gen3MoveSelection").aiMask(b, user)
        end
        local aiAllowed, manualAllowed = {}, {}
        for slot = 1, 4 do
          aiAllowed[slot] = not mask[slot]
          if native then
            manualAllowed[slot] = require("src.core.game3.battle.commands").moveUsable(b, slot, id)
          else
            manualAllowed[slot] = require("src.battle.Gen3MoveSelection").manualReason(
              b,
              user,
              user.curMoves[slot],
              slot
            ) == nil
          end
        end
        off()
        T.eq(#trace, 1, "AI limitations read the holder once; manual admission does not read the held effect")
        T.eq(#draws, 0, "read-only native limitations consume no RNG")
        T.eq(#f.result.errors, 0, "complete held query has no swallowed callback failures")
        if kind == "tormented_struggle" then
          T.eq(manualAllowed[4], true, "manual Torment keeps its Struggle exception")
        end
        rows[#rows + 1] = {
          case = kind,
          double = double,
          actor = id,
          aiAllowed = aiAllowed,
          manualAllowed = manualAllowed,
          choice = user.choicedMove,
          trace = trace,
          draws = draws,
          hp = user.mon.hp,
          foeHp = foe.mon.hp,
        }
      end
    end
  end
  f.close()
  return rows
end
return M
