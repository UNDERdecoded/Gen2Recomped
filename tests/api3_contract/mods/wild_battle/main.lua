local mod = ...
local world = mod.world
assert(mod:supports("world", "startWildBattle"))
local ok, why = world:startWildBattle("MEW", 5)
assert(ok == nil and why == "no game")
local calls, args = 0
mod.exports.request = function(...)
  return world:startWildBattle(...)
end
mod.exports.notify = function(...)
  calls = calls + 1
  args = { n = select("#", ...), first = (...), third = select(3, ...) }
end
mod.exports.result = function()
  return { calls = calls, args = args }
end
