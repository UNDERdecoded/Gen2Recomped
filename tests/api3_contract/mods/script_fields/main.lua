local mod = ...
local done, success, reason = 0
mod.exports.queue = function(rows)
  return mod.world:queueScript(rows, {
    onDone = function(ok, why)
      done, success, reason = done + 1, ok, why
    end,
  })
end
mod.exports.result = function()
  return { done = done, success = success, reason = reason }
end
mod.exports.get = function(name)
  return mod.world:getFlag(name)
end
