-- Same public-only mod on both engines. Native timing stays in the driver.
local mod = ...
local world = mod.world
for _, name in ipairs({ "spawnNpc", "removeNpc", "npc" }) do
  assert(mod:supports("world", name))
end
local ok, why = world:npc("HOME", 1)
assert(ok == nil and why == "no game")
local calls, args = 0, nil
mod.exports.spawn = function(...)
  return world:spawnNpc(...)
end
mod.exports.remove = function(...)
  return world:removeNpc(...)
end
mod.exports.npc = function(...)
  return world:npc(...)
end
mod.exports.toggle = function(...)
  return world:toggleObject(...)
end
mod.exports.done = function(...)
  calls = calls + 1
  args = { n = select("#", ...), first = (...), third = select(3, ...) }
end
mod.exports.result = function()
  return { calls = calls, args = args }
end
