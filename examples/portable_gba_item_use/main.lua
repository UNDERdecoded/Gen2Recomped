local mod = ...
local state = { mode = "native", calls = 0 }
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
mod.exports.api, mod.exports.state = mod, state
local stop
if not mod.supports or mod:supports("hooks", "item.use") then
  stop = mod.hooks:wrap("item.use", function(next, ...)
    local game, battle, id, slot, bag = ...
    state.calls, state.argCount = state.calls + 1, select("#", ...)
    state.game, state.battle, state.item, state.slot, state.bag = game, battle, id, slot, bag
    if state.mode == "block" then
      return false, "blocked", "PORTABLE BLOCK"
    end
    if state.mode == "redirect" then
      id = state.redirect
    end
    local result = pack(next(game, battle, id, slot, bag))
    state.returnCount, state.ok, state.kind, state.text = result.n, result[1], result[2], result[3]
    if state.mode == "message" then
      return result[1], result[2], "PORTABLE TEXT"
    end
    if state.mode == "silent" then
      return result[1], result[2], nil
    end
    return unpack(result, 1, result.n)
  end)
end
mod.exports.stop = function()
  if stop then
    stop()
  end
end
