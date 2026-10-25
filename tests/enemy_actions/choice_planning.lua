-- A one-action native plan isolates forced-move resolution without recreating
-- its formula or consuming the separate whole-turn ordering word.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/choice_band.lua").fixture(root, backend, version)
  local T, Copy, rows = f.T, require("src.mods.Merge").deepCopy, {}
  local function number(value)
    if native then
      return tonumber(value)
    end
    local def = f.data.moves[value]
    return def and tonumber(def.index or def.numId)
  end
  local function view(user)
    local pp, learned = {}, {}
    for slot = 1, 4 do
      if native then
        pp[slot] = user.mon.pp[slot]
        learned[slot] = number(user.mon.moves[slot])
      else
        local move = user.curMoves[slot]
        pp[slot] = move and move.pp
        learned[slot] = move and number(move.id)
      end
    end
    return {
      hp = user.mon.hp,
      choice = user.choicedMove,
      pp = pp,
      learned = learned,
      last = number(user[native and "lastMoveId" or "lastMove"]),
    }
  end
  for _, double in ipairs({ false, true }) do
    for id = 0, double and 3 or 1 do
      for _, kind in ipairs({
        "bound",
        "forced_status",
        "unbound",
        "same_move",
        "empty_item",
        "effect_only_item",
        "empty_override",
        "suppressed",
        "metadata_cleared",
        "struggle",
        "struggle_ghost",
        "struggle_rock",
        "first_duplicate_empty",
        "duplicate_selected",
        "missing_choice",
        "locked_pp_empty",
        "encore",
        "charging",
        "replace_moves",
        "replace_reordered_moves",
        "replace_removed_slot",
        "replace_moves_pressure",
        "replace_removed_slot_pressure",
      }) do
        local removedSlot = kind == "replace_removed_slot" or kind == "replace_removed_slot_pressure"
        local pressure = kind == "replace_moves_pressure" or kind == "replace_removed_slot_pressure"
        local b = f.field(double)
        local user, targetId = f.at(b, id), id % 2 == 0 and id + 1 or id - 1
        local target = f.at(b, targetId)
        if kind ~= "unbound" then
          user.choicedMove = kind == "forced_status" and 214 or 33
        end
        if removedSlot then
          user.choicedMove = 10
        end
        if pressure then
          if native then
            target.ability, target.mon.ability = 46, 46
          else
            target.abilityOverride = "PRESSURE"
          end
        end
        local item = 186
        if kind == "empty_item" or kind == "empty_override" then
          item = nil
        end
        if kind == "effect_only_item" then
          item = 529
        end
        f.hold(user, item)
        if native then
          f.data.gen3Items._byId[186].holdEffect = kind == "metadata_cleared" and 0 or 29
        else
          f.data.items.ITEM_186.holdEffect = kind == "metadata_cleared" and "NONE" or "CHOICE_BAND"
        end
        local struggle = kind:match("^struggle") ~= nil
        local selected = kind == "same_move" and 1 or struggle and 4 or 2
        if removedSlot then
          selected = 1
        end
        if kind == "struggle_ghost" or kind == "struggle_rock" then
          if native then
            target.type1 = kind == "struggle_ghost" and 7 or 5
            target.type2 = target.type1
          else
            target.curTypes = { kind == "struggle_ghost" and "GHOST" or "ROCK" }
          end
        end
        if kind == "first_duplicate_empty" or kind == "duplicate_selected" then
          f.moves(user, { "TACKLE", "SCRATCH", "TACKLE", "STRUGGLE" })
          if native then
            user.mon.pp[1] = 0
          else
            user.curMoves[1].pp = 0
          end
          if kind == "duplicate_selected" then
            selected = 3
          end
        end
        if kind == "locked_pp_empty" then
          if native then
            user.mon.pp[1] = 0
          else
            user.curMoves[1].pp = 0
          end
        end
        if kind == "missing_choice" then
          f.moves(user, { "SCRATCH", "SCRATCH", "SLEEP_TALK", "STRUGGLE" })
        end
        if kind == "encore" then
          user[native and "expEncoreMove" or "encoreMove"] = f.moveId("TACKLE")
          user[native and "expEncoreSlot" or "encoreSlot"] = 1
          user[native and "expEncoreTurns" or "encoreTurns"] = 3
        end
        if kind == "charging" then
          if native then
            user.expLockedMove = 19
          else
            user.charging = { id = f.ids.FLY, pp = 1 }
          end
        end
        local trace, draws, events = {}, {}, {}
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
          if kind == "suppressed" then
            return nil, 0
          end
          if kind == "empty_override" then
            return "HELD_CHOICE_BAND", 0
          end
          return nextRead(ctx)
        end)
        b.rng = function(lo, hi)
          draws[#draws + 1] = { lo, hi, hi }
          return hi
        end
        local plan, plannedMove, plannedSlot, targetType, plannedTarget
        if native then
          local action =
            { kind = "move", move = user.mon.moves[selected], slot = selected, target = targetId }
          local sourcePlan = require("src.core.game3.battle.engine").planTurnActions(
            b,
            require("src.core.game3.battle.adapter").new(b),
            { [id] = action }
          )
          plan = sourcePlan[1]
          plannedMove, plannedSlot, targetType, plannedTarget =
            plan.move, plan.slot, plan.targetType, plan.target
        else
          local slot = user.curMoves[selected]
          local action = require("src.battle.EnemyMoveChoice").withMove(slot, slot.id, slot, selected)
          action.kind, action.target = "move", targetId
          action.targetType = tonumber(b.data.moves[slot.id].target) or 0
          plan = require("src.battle.Gen3ChoiceBand").plan(b, user, action)
          plannedMove, plannedSlot, targetType, plannedTarget =
            plan.id, plan.slot, plan.targetType, plan.target
        end
        off()
        T.eq(#draws, 0, "one-action native forced planning consumes no whole-turn RNG")
        T.eq(
          #trace,
          (kind == "unbound" or kind == "encore" or kind == "charging") and 0 or 1,
          "only an applicable Choice Band planner performs the held check"
        )
        local plannerTrace = Copy(trace)
        local oldPP, oldSlot
        if kind == "replace_moves" or kind == "replace_reordered_moves" or removedSlot or pressure then
          oldSlot = native and user.mon.pp or user.curMoves
          oldPP = native and oldSlot[plannedSlot] or oldSlot[plannedSlot].pp
          f.moves(
            user,
            removedSlot and { "TACKLE" }
              or (kind == "replace_moves" or pressure) and { "TACKLE", "SCRATCH", "SLEEP_TALK", "STRUGGLE" }
              or { "SCRATCH", "TACKLE", "SLEEP_TALK", "STRUGGLE" },
            7
          )
        end
        -- Charging is a planner-only input here. Its actual release needs the
        -- real charge setup; all ordinary and Encore plans execute normally.
        if kind ~= "charging" then
          local noCrit = f.e.api.hooks:wrap("battle.crit", function()
            return false
          end)
          local stop = f.e.api.events:on("battle.move_used", function(e)
            events[#events + 1] =
              { user = e.user.mon.nickname, target = e.target.mon.nickname, move = e.move.id }
          end)
          if native then
            require("src.core.game3.battle.engine").resolveMove(
              id,
              targetId,
              plan.move,
              plan.slot,
              require("src.core.game3.battle.adapter").new(b),
              b,
              {},
              {}
            )
          else
            b:executeAction(user, target, plan)
          end
          stop()
          noCrit()
        end
        local retainedPP = oldSlot and (native and oldSlot[plannedSlot] or oldSlot[plannedSlot].pp)
        if oldSlot then
          T.eq(retainedPP, oldPP, "replaced learned records do not spend old PP")
        end
        if removedSlot then
          T.check(target.mon.hp < 400, "removing the PP slot does not cancel the already planned move")
          T.eq(
            native and user.mon.pp[1] or user.curMoves[1].pp,
            7,
            "removing the planned slot does not spend another current move's PP"
          )
        elseif pressure then
          T.eq(
            native and user.mon.pp[1] or user.curMoves[1].pp,
            5,
            "Pressure spends two PP from the replacement slot when it exists"
          )
        end
        T.eq(#f.result.errors, 0, "planner and actual move callbacks stay error-free")
        rows[#rows + 1] = {
          case = kind,
          double = double,
          actor = id,
          move = number(plannedMove),
          slot = plannedSlot,
          targetType = targetType,
          target = type(plannedTarget) == "table" and plannedTarget.id or plannedTarget,
          plannerTrace = plannerTrace,
          draws = draws,
          events = events,
          user = view(user),
          targetState = view(target),
          replacedOldPP = retainedPP,
        }
      end
    end
  end
  f.close()
  return rows
end
return M
