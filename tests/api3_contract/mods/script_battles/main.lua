local mod = ...
local done, success = 0
mod.exports.queue = function(rows)
  return mod.world:queueScript(rows, {
    onDone = function(ok)
      done, success = done + 1, ok
    end,
  })
end
mod.exports.result = function()
  return { done = done, success = success }
end
mod.exports.get = function(name)
  return mod.world:getFlag(name)
end
