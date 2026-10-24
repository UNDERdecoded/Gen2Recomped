-- Set claim(true) when a custom auxiliary battle UI is available. Its opener
-- belongs in onOpen; return true only when taking ownership of this input.
local mod = ...
local claimed, seen = false, { calls = 0 }
mod.exports.api, mod.exports.seen = mod, seen
function mod.exports.claim(value)
  claimed = value == true
end
mod.exports.stop = mod.hooks:wrap("battle.menu_auxiliary", function(next, game, context)
  seen.calls, seen.game, seen.context = seen.calls + 1, game, context
  if claimed then
    if mod.exports.onOpen then
      mod.exports.onOpen(game, context)
    end
    return true
  end
  return next(game, context)
end)
