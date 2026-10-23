-- Hide levels per surface while leaving the native screen and input active.
-- Rendering can query a predicate repeatedly; keep the decision deterministic.
local mod = ...
local hidden, seen = {}, { calls = 0 }
mod.exports.api, mod.exports.seen = mod, seen
function mod.exports.hide(where, value)
  hidden[where] = value == true
end
mod.exports.stop = mod.hooks:wrap("pokemon.level_visible", function(next, mon, context)
  seen.calls = seen.calls + 1
  seen.mon, seen.context = mon, context
  if hidden[context.where] then
    return false
  end
  return next(mon, context)
end)
