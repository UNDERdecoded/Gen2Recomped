local mod = ...
local enabled = false
local seen = { calls = 0 }
local stop = mod.hooks:wrap("ui.party.grid_navigation", function(next, menu)
  seen.calls, seen.menu = seen.calls + 1, menu
  if enabled then
    return true
  end
  return next(menu)
end)
mod.exports.api = mod
mod.exports.seen = seen
mod.exports.grid = function(value)
  enabled = value
end
mod.exports.stop = stop
