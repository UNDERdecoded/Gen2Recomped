local mod = ...
local world = mod.world
local done, success = 0
local events = {}
mod.events:on("world.object_toggled", function(ev)
  events[#events + 1] = { kind = "object", mapId = ev.mapId, ref = ev.objName, visible = ev.visible }
end)
mod.events:on("world.block_replaced", function(ev)
  events[#events + 1] = { kind = "block", mapId = ev.mapId, x = ev.bx, y = ev.by, value = ev.block }
end)
mod.exports.queue = function(rows)
  return world:queueScript(rows, {
    onDone = function(ok)
      done, success = done + 1, ok
    end,
  })
end
mod.exports.result = function()
  return { done = done, success = success, events = events }
end
mod.exports.get = function(name)
  return world:getFlag(name)
end
mod.exports.read = function(...)
  return world:activeBlockAt(...)
end
