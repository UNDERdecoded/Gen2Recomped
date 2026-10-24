local mod = ...
local state = { mode = "native", calls = 0 }
mod.exports.api, mod.exports.state = mod, state
local stop
if not mod.supports or mod:supports("hooks", "item.use") then
  stop = mod.hooks:wrap("item.use", function(next, game, battle, item, target, list, moveIndex, picker)
    state.calls = state.calls + 1
    state.game, state.battle, state.item, state.target = game, battle, item, target
    state.list, state.moveIndex, state.picker = list, moveIndex, picker
    if state.mode == "block" then
      return
    end
    if state.mode == "redirect" then
      item = state.redirect
    end
    return next(game, battle, item, target, list, moveIndex, picker)
  end)
end
mod.exports.stop = function()
  if stop then
    stop()
  end
end
