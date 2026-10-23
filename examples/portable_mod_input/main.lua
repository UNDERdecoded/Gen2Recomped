-- Logical buttons, not keyboard aliases; unchanged across both engines.
local mod = ...
local game
mod.exports.input = mod.input
mod.events:on("game.ready", function(event)
  game = event.game
end)
function mod.exports.tap(button)
  return mod.input:tap(game, button)
end
function mod.exports.press(button)
  return mod.input:press(game, button)
end
function mod.exports.release(token)
  return mod.input:release(token)
end
