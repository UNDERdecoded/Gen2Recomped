local mod = ...
local mode, seen = "native", { calls = 0 }
mod.exports.api, mod.exports.seen = mod, seen
function mod.exports.mode(value)
  mode = value
end
mod.exports.stop = mod.hooks:wrap("battle.move_grid_navigation", function(next, battle)
  seen.calls, seen.battle = seen.calls + 1, battle
  if mode == "grid" then
    return true
  end
  if mode == "list" then
    return false
  end
  return next(battle)
end)
