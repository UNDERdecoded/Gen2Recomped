-- Observe every interactive frame, including frames whose simulation is paused.
local mod = ...
local paused, polls, seen = false, 0, {}
mod.exports.api, mod.exports.seen = mod, seen
function mod.exports.pause(value)
  paused = value
end
function mod.exports.polls()
  return polls
end
mod.exports.stop = mod.hooks:wrap("core.update", function(next, game, dt)
  polls = polls + 1
  seen.game, seen.dt = game, dt
  if paused then
    return "paused"
  end
  return next(game, dt)
end)
