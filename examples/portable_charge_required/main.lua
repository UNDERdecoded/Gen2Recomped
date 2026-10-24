local mod = ...
local state = { calls = 0, mode = "native" }
mod.exports.api, mod.exports.state = mod, state
local stop
if not mod.supports or mod:supports("hooks", "battle.charge_required") then
  stop = mod.hooks:wrap("battle.charge_required", function(next, ctx)
    state.calls = state.calls + 1
    state.charge, state.isCalled = ctx.charge, ctx.isCalled
    state.move = ctx.move and ctx.move.id
    state.battle, state.user, state.target = ctx.battle, ctx.user, ctx.target
    if state.mode == "bypass" then
      return false
    end
    if state.mode == "nil" then
      return nil
    end
    if state.mode == "truthy" then
      return 0
    end
    if state.mode == "edit" then
      ctx.charge = false
    end
    local required = next(ctx)
    state.nextResult = required
    return required
  end)
end
mod.exports.stop = function()
  if stop then
    stop()
  end
end
