local mod = ...
local state = { mode = "native", calls = 0 }
mod.exports.state, mod.exports.api = state, mod
local stop = mod.hooks:wrap("battle.caught_marker_visible", function(next, battle)
  state.calls, state.battle = state.calls + 1, battle
  if state.mode == "show" then
    return true
  end
  if state.mode == "hide" then
    return false
  end
  if state.mode == "nil" then
    return nil
  end
  if state.mode == "zero" then
    return 0
  end
  return next(battle)
end)
mod.exports.stop = stop
