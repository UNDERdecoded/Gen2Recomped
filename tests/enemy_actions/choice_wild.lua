-- Exercise the actual ordinary-wild controller, including its deliberately
-- unfiltered nonempty-slot draw before forced-move planning.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/choice_band.lua").fixture(root, backend, version)
  local T, rows = f.T, {}
  local function number(id)
    if native then
      return require("src.mods.Gen3Compat").moveId(id)
    end
    local def = f.data.moves[id]
    return def and tonumber(def.index or def.numId)
  end
  for _, double in ipairs({ false, true }) do
    for id = 1, double and 3 or 1, 2 do
      for _, kind in ipairs({
        "bound",
        "unbound",
        "all_pp_empty",
        "locked_pp_empty",
        "effect_only_item",
        "empty_override",
        "suppressed",
        "encore",
        "taunt",
        "torment",
        "retry_empty",
        "bounded_empty_fallback",
      }) do
        for pick = 0, 3 do
          local b = f.field(double)
          local user = f.at(b, id)
          f.hold(user, kind == "effect_only_item" and 529 or 186)
          if kind == "empty_override" then
            f.hold(user, nil)
          end
          if kind ~= "unbound" then
            user.choicedMove = 33
          end
          local function setPP(slot, value)
            if native then
              user.mon.pp[slot] = value
            else
              user.curMoves[slot].pp = value
            end
          end
          if kind == "all_pp_empty" then
            for slot = 1, 4 do
              setPP(slot, 0)
            end
          elseif kind == "locked_pp_empty" then
            setPP(1, 0)
          end
          if kind == "encore" then
            user[native and "expEncoreMove" or "encoreMove"] = f.moveId("SCRATCH")
            user[native and "expEncoreSlot" or "encoreSlot"] = 2
            user[native and "expEncoreTurns" or "encoreTurns"] = 3
          elseif kind == "taunt" then
            user[native and "expTauntedTurns" or "tauntTurns"] = 3
          elseif kind == "torment" then
            user[native and "expTormented" or "tormented"] = true
            user[native and "lastMoveId" or "lastMove"] = f.moveId("TACKLE")
          elseif kind == "retry_empty" or kind == "bounded_empty_fallback" then
            if native then
              user.mon.moves[pick + 1] = 0
            else
              user.curMoves[pick + 1] = { id = 0, pp = 0 }
            end
            user.choicedMove = nil
          end
          local trace, draws, selections = {}, {}, 0
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
            local value = hi
            if lo == 0 and hi == 3 then
              selections = selections + 1
              value = pick
              if kind == "retry_empty" and selections > 1 then
                value = (pick + 1) % 4
              end
            end
            draws[#draws + 1] = { lo, hi, value }
            return value
          end
          local action
          if native then
            action = require("src.core.game3.battle.ai").chooseAction(b, id)
          else
            action = b:vanillaEnemyAction(user)
          end
          local selected = {
            move = number(native and action.move or action.id),
            slot = action.slot,
            target = action.target,
            scores = action.scores,
          }
          local plan
          if native then
            plan = require("src.core.game3.battle.engine").planTurnActions(
              b,
              require("src.core.game3.battle.adapter").new(b),
              { [id] = action }
            )[1]
          else
            plan = require("src.battle.Gen3ChoiceBand").plan(b, user, action)
          end
          off()
          T.eq(#f.result.errors, 0, "ordinary wild callbacks stay error-free")
          rows[#rows + 1] = {
            case = kind,
            double = double,
            actor = id,
            pick = pick,
            selected = selected,
            planned = {
              move = number(native and plan.move or plan.id),
              slot = plan.slot,
              target = plan.target,
            },
            trace = trace,
            draws = draws,
            hp = user.mon.hp,
            choice = user.choicedMove,
          }
        end
      end
    end
  end
  f.close()
  return rows
end
return M
