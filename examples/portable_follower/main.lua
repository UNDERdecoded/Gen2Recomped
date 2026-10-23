local mod = ...
local state = { mode = "native", calls = 0 }
mod.exports.api, mod.exports.state = mod, state
local stop
if not mod.supports or mod:supports("hooks", "world.follower.spawn") then
  stop = mod.hooks:wrap("world.follower.spawn", function(next, game, world)
    state.calls, state.game, state.world = state.calls + 1, game, world
    if state.mode == "native" then
      return next(game, world)
    end
    return state.mode == "allow"
  end)
end
mod.exports.stop = function()
  if stop then
    stop()
  end
end
