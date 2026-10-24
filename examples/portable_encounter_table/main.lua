local mod = ...
local state = { mode = "pass", calls = 0 }
mod.exports.api, mod.exports.state = mod, state
local stop
if not mod.supports or mod:supports("hooks", "encounter.table") then
  stop = mod.hooks:wrap("encounter.table", function(next, dist, ctx)
    state.calls = state.calls + 1
    state.preview, state.mapId, state.terrain = ctx.preview, ctx.mapId, ctx.terrain
    state.opts = ctx.opts
    if state.mode == "replace" then
      return { MEW = 7 }
    end
    if state.mode == "empty" then
      return {}
    end
    if state.mode == "nil" then
      return nil
    end
    if state.mode == "scalar" then
      return false
    end
    if state.mode == "mutate" then
      for id in pairs(dist) do
        dist[id] = nil
      end
      dist.MEW = 13
    end
    local result = next(dist, ctx)
    if state.mode == "post" then
      result.MEW = 11
    end
    return result
  end)
end
mod.exports.preview = function(mapId, terrain, opts)
  return mod.world:effectiveEncounters(mapId, terrain, opts)
end
mod.exports.stop = function()
  if stop then
    stop()
  end
end
