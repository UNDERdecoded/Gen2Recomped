-- A failed native Mirror Move returns before its move-end script. Observe
-- its complete held sequence, rather than accepting only unchanged HP.
local M = {}
function M.run(root, backend, version)
  local native = backend == "gen1"
  local f = dofile(root .. "/tests/enemy_actions/choice_band.lua").fixture(root, backend, version)
  if native then
    local row = {
      effect = 9,
      power = 0,
      type = 0,
      accuracy = 100,
      pp = 10,
      target = 0,
      flags = 0,
      priority = 0,
      secondaryChance = 0,
    }
    local moves = require("src.core.game3.battle.moves")
    moves._rom[119], moves.BY_NUM[119], moves._numByName.MIRROR_MOVE = row, "MIRROR_MOVE", 119
    f.data.gen3Moves._rom[119], f.data.gen3Pokemon._moveNames[119] = row, "MIRROR_MOVE"
  else
    f.data.moves.MOVE_119 = {
      id = "MOVE_119",
      index = 119,
      name = "MIRROR_MOVE",
      gen3Effect = 9,
      effect = "MIRROR_MOVE_EFFECT",
      power = 0,
      type = "NORMAL",
      accuracy = 100,
      pp = 10,
      target = 0,
      flags = 0,
      mirrorMoveAffected = false,
    }
  end
  local rows = {}
  for _, double in ipairs({ false, true }) do
    for id = 0, double and 3 or 1 do
      for _, bound in ipairs({ false, true }) do
        local b = f.field(double)
        local user, target = f.at(b, id), f.at(b, id % 2 == 0 and id + 1 or id - 1)
        f.hold(user, 186)
        user.choicedMove = bound and 33 or nil
        if native then
          user.mon.moves, user.mon.pp, user.mon.maxPp = { 119, 33 }, { 10, 10 }, { 10, 10 }
        else
          user.mon.moves = { { id = "MOVE_119", pp = 10 }, { id = f.ids.TACKLE, pp = 10 } }
          user.curMoves = user.mon.moves
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
          return nextRead(ctx)
        end)
        local stop = f.e.api.events:on("battle.move_used", function(e)
          events[#events + 1] = {
            user = e.user.mon.nickname,
            target = e.target.mon.nickname,
            move = e.move.id,
            called = e.isCalled or false,
          }
        end)
        b.rng = function(lo, hi)
          draws[#draws + 1] = { lo, hi, hi }
          return hi
        end
        if native then
          require("src.core.game3.battle.engine").resolveMove(
            id,
            id % 2 == 0 and id + 1 or id - 1,
            119,
            1,
            require("src.core.game3.battle.adapter").new(b),
            b,
            {}
          )
        else
          b:executeAction(user, target, user.curMoves[1])
        end
        off()
        stop()
        f.T.eq(
          user.choicedMove,
          bound and 33 or nil,
          "failed native caller does not enter the choice command"
        )
        f.T.eq(#trace, double and 4 or 2, "only the separate after-action item sweep remains")
        f.T.eq(#draws, 0, "failed native caller consumes no selection or damage RNG")
        f.T.eq(#f.result.errors, 0, "failed caller callbacks remain error-free")
        rows[#rows + 1] = {
          double = double,
          actor = id,
          bound = bound,
          choice = user.choicedMove,
          pp = native and user.mon.pp[1] or user.curMoves[1].pp,
          userHp = user.mon.hp,
          targetHp = target.mon.hp,
          trace = trace,
          draws = draws,
          events = events,
        }
      end
    end
  end
  f.close()
  return rows
end
return M
