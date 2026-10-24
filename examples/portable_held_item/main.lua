local mod = ...
local state = { mode = "delegate", calls = 0, seen = {}, views = {}, requiresItem = true }
mod.exports.api, mod.exports.state = mod, state
mod.exports.stop = mod.hooks:wrap("held_item.trigger", function(next, context)
  state.calls = state.calls + 1
  state.last = context
  state.seen[context.trigger] = (state.seen[context.trigger] or 0) + 1
  state.views[context.trigger] = context
  if
    (not state.trigger or state.trigger == context.trigger)
    and (not state.holder or state.holder == context.mon.nickname)
    and (not state.requiresItem or context.def ~= nil)
  then
    state.selected = context
    if state.mode == "suppress" then
      return nil
    end
    if state.mode == "override" then
      return state.effect, state.parameter
    end
    if state.mode == "mutate" then
      context.effect, context.parameter = state.effect, state.parameter
    end
  end
  return next(context)
end)
