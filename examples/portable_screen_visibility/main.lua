-- A companion can mirror a native menu while its original state keeps input.
-- Keep the predicate pure: composition may ask about a state repeatedly.
local mod = ...
local hidden, seen = {}, { calls = 0 }
mod.exports.api, mod.exports.seen = mod, seen
function mod.exports.hide(screenId, value)
  hidden[screenId] = value == true
end
mod.exports.stop = mod.hooks:wrap("screen.render_visible", function(next, state, ...)
  seen.calls = seen.calls + 1
  seen.state, seen.extra = state, select("#", ...)
  if hidden[state.screenId] then
    return false
  end
  return next(state)
end)
