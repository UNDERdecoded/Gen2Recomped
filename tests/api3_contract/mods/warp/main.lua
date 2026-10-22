-- Identical public-only mod on both engines: the harness owns native timing.
local mod = ...
local world = mod.world
assert(mod:supports("world", "warpTo"))
local early, reason = world:warpTo("DEST", 0, 0)
assert(early == nil and reason == "no game")
local calls, args, events = 0, nil, {}
mod.events:on("map.entered", function(ev)
  events[#events + 1] = { mapId = ev.mapId, fromMapId = ev.fromMapId, via = ev.via }
end)
mod.exports.request = function(...)
  return world:warpTo(...)
end
mod.exports.notify = function(...)
  calls = calls + 1
  args = { n = select("#", ...), first = (...), third = select(3, ...) }
end
mod.exports.results = function()
  return { calls = calls, args = args, events = events }
end
mod.exports.current = function()
  return world:current()
end
