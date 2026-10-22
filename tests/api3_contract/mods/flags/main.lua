local mod = ...
local world = mod.world
local value, why = world:getFlag(1)
assert(value == nil and why == "no game")
local events = {}
mod.events:on("flag.changed", function(ev)
  events[#events + 1] = { name = ev.id or ev.name, value = ev.value }
end)
mod.exports.get = function(name)
  return world:getFlag(name)
end
mod.exports.set = function(name, value)
  return world:setFlag(name, value)
end
mod.exports.events = function()
  return events
end
