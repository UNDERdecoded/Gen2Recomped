local mod = ...
local world = mod.world
assert(mod:supports("world", "queueScript"))
local done, success = 0
mod.exports.queue = function(rows)
  return world:queueScript(rows, {
    onDone = function(ok)
      done, success = done + 1, ok
    end,
  })
end
mod.exports.set = function(name, value)
  return world:setFlag(name, value)
end
mod.exports.get = function(name)
  return world:getFlag(name)
end
mod.exports.result = function()
  return { done = done, success = success }
end
