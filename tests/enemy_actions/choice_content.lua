-- Same authored API-3 caller on both engines. This observes actual dispatch,
-- events, RNG, HP and choice/PP ownership, not the complete held-script trace.
local M = {}
function M.run(root, backend, version)
  local native, rows = backend == "gen1", {}
  local entry = [=[return function(mod)
    assert(mod.content.move_effects:register("PORTABLE_CHOOSER", {kind="primary",run=function(ctx)
      ctx.callMove("TACKLE");return {}
    end}))
    assert(mod.content.moves:register("PORTABLE_CALLER", {id="PORTABLE_CALLER",name="PORTABLE_CALLER",
      type="NORMAL",power=0,accuracy=100,pp=10,effect="PORTABLE_CHOOSER"}))
    mod.exports.api=mod
  end]=]
  for _, learned in ipairs({ false, true }) do
    local f = dofile(root .. "/tests/enemy_actions/choice_band.lua").fixture(
      root,
      backend,
      version,
      { entry = entry }
    )
    local number, registries, previousRegistryData
    if native then
      number = assert(require("src.mods.Gen3Compat").moveId("PORTABLE_CALLER"))
      local moves = require("src.core.game3.battle.moves")
      moves._rom[number] = assert(f.data.gen3Moves._rom[number])
      moves.BY_NUM[number], moves._numByName.PORTABLE_CALLER = "PORTABLE_CALLER", number
      registries = require("src.core.game3.battle.mod_registries")
      previousRegistryData = registries.data()
      registries.bind(f.data)
    end
    local function name(value)
      if not value then
        return nil
      end
      if native then
        return require("src.mods.Gen3Compat").moveName(value)
      end
      local def = f.data.moves[value]
      if def then
        return def.name
      end
      for _, row in pairs(f.data.moves) do
        if type(row) == "table" and tonumber(row.index) == value then
          return row.name
        end
      end
    end
    for id = 0, 1 do
      local b = f.field(false)
      local user, target = f.at(b, id), f.at(b, 1 - id)
      f.hold(user, 186)
      if native then
        user.mon.moves = { number, learned and 33 or 10 }
        user.mon.pp, user.mon.maxPp = { 10, 10 }, { 10, 10 }
      else
        user.mon.moves =
          { { id = "PORTABLE_CALLER", pp = 10 }, { id = learned and f.ids.TACKLE or f.ids.SCRATCH, pp = 10 } }
        user.curMoves = user.mon.moves
      end
      local draws, events = {}, {}
      b.rng = function(lo, hi)
        draws[#draws + 1] = { lo, hi, hi }
        return hi
      end
      local noCrit = f.e.api.hooks:wrap("battle.crit", function()
        return false
      end)
      local off = f.e.api.events:on("battle.move_used", function(e)
        events[#events + 1] = {
          user = e.user.mon.nickname,
          target = e.target.mon.nickname,
          move = e.move.id,
          called = e.isCalled or false,
        }
      end)
      if native then
        require("src.core.game3.battle.engine").resolveMove(
          id,
          1 - id,
          number,
          1,
          require("src.core.game3.battle.adapter").new(b),
          b,
          {}
        )
      else
        b:executeAction(user, target, user.curMoves[1])
      end
      off()
      noCrit()
      local pp = native and user.mon.pp or { user.curMoves[1].pp, user.curMoves[2].pp }
      f.T.eq(
        name(user.choicedMove),
        learned and "TACKLE" or "PORTABLE_CALLER",
        "custom ctx.callMove retains its own child/outer move-end boundaries"
      )
      f.T.same(pp, { 9, 10 }, "actual authored caller spends only its learned PP")
      f.T.eq(#events, 2, "actual authored caller and child both emit their public move event")
      f.T.eq(#f.result.errors, 0, "authored callback completes without swallowed errors")
      rows[#rows + 1] = {
        learned = learned,
        actor = id,
        choice = name(user.choicedMove),
        last = name(user[native and "lastMoveId" or "lastMove"]),
        pp = pp,
        userHp = user.mon.hp,
        targetHp = target.mon.hp,
        draws = draws,
        events = events,
      }
    end
    if registries then
      registries.bind(previousRegistryData)
    end
    f.close()
  end
  return rows
end
return M
