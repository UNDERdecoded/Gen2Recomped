local mod = ...
local state = { calls = 0, mode = "none", requests = {}, faints = 0, awards = 0 }
mod.exports.api, mod.exports.state = mod, state
mod.events:on("battle.fainted", function()
  state.faints = state.faints + 1
end)
mod.events:on("battle.exp_gained", function()
  state.awards = state.awards + 1
end)
local stop = mod.hooks:wrap("battle.field_residual", function(next, context)
  state.calls, state.last = state.calls + 1, context
  if state.mode == "invalid" then
    return state.invalid
  end
  if state.mode == "mutate" then
    context.battlers.player.hp = 0
    context.battlers.player.types[1] = "FORGED"
    context.field.tokens[1].state.intensity = 999
  end
  local rows = next(context)
  for _, request in ipairs(state.requests) do
    rows[#rows + 1] = request
  end
  return rows
end)
mod.exports.stop = stop
