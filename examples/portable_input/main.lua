-- The same entry chunk runs on both engines; no private engine imports.
local mod = ...
local events, captured = {}, false
mod.exports.events = events
mod.exports.api = mod
function mod.exports.capture(value)
  captured = value
end
local off = {}
for _, name in ipairs({ "input.key", "input.gamepad", "input.wheel" }) do
  off[#off + 1] = mod.hooks:wrap(name, function(next, game, event)
    events[#events + 1] = { name = name, game = game, event = event }
    -- An overlay owns both press and release while capture is active.
    if captured then
      return "captured"
    end
    return next(game, event)
  end)
end
function mod.exports.stop()
  for _, unsubscribe in ipairs(off) do
    unsubscribe()
  end
end
