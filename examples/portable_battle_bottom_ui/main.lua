-- A custom battle UI can hide the native bottom layer without pausing input.
-- Decide from state properties; composition may query the predicate repeatedly.
local mod = ...
local hidden, seen = false, { calls = 0 }
mod.exports.api, mod.exports.seen = mod, seen
function mod.exports.hide(value)
  hidden = value == true
end
mod.exports.stop = mod.hooks:wrap("battle.bottom_ui_visible", function(next, state, ...)
  seen.calls = seen.calls + 1
  seen.state, seen.extra = state, select("#", ...)
  if hidden then
    return false
  end
  return next(state)
end)
