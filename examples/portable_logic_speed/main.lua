-- A speed overlay can choose a multiplier or restore the host's saved option.
-- Link/fixed-speed locks and explicit launch overrides remain the host's choice.
local mod = ...
local override, seen = nil, { calls = 0 }
mod.exports.api, mod.exports.seen = mod, seen
function mod.exports.setSpeed(value)
  override = value
end
mod.exports.stop = mod.hooks:wrap("core.logic_speed", function(next, game, ...)
  seen.calls = seen.calls + 1
  seen.game, seen.extra = game, select("#", ...)
  if override ~= nil then
    return override
  end
  seen.vanilla = next(game)
  return seen.vanilla
end)
