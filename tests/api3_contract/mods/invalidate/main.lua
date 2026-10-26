local mod = ...
local world = mod.world
assert(mod:supports("world", "invalidateMap"))
local value, why = world:invalidateMap("HOME")
assert(value == nil and why == "no game")
local events = {}
mod.events:on("map.reloaded", function(ev)
  events[#events + 1] = { mapId = ev.mapId, reason = ev.reason }
end)
mod.exports.request = function(...)
  return world:invalidateMap(...)
end
mod.exports.events = function()
  return events
end
