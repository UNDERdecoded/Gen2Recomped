local mod = ...
local state = { critical = true, calls = 0 }
mod.exports.state = state
mod.exports.available = mod:supports("hooks", "battle.crit")
if mod.exports.available then
  mod.hooks:wrap("battle.crit", function()
    state.calls = state.calls + 1
    return state.critical
  end)
end
