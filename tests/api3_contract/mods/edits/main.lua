-- Identical source on both engines; native layout stays in the driver.
local mod = ...
local world = mod.world
assert(mod:supports("world", "toggleObject"))
assert(mod:supports("world", "replaceBlock"))
local ok, why = world:toggleObject("HOME", "NPC", false)
assert(ok == nil and why == "no game")
ok, why = world:replaceBlock(0, 0, 7)
assert(ok == nil and why == "no game")
local events, reenter, nested = {}, false, nil
mod.events:on("world.object_toggled", function(ev)
  events[#events + 1] = { kind = "object", mapId = ev.mapId, ref = ev.objName, visible = ev.visible }
  if reenter then
    nested = { world:replaceBlock(0, 0, 7) }
  end
end)
mod.events:on("world.block_replaced", function(ev)
  events[#events + 1] = { kind = "block", mapId = ev.mapId, x = ev.bx, y = ev.by, block = ev.block }
end)
mod.exports.toggle = function(...)
  return world:toggleObject(...)
end
mod.exports.replace = function(...)
  return world:replaceBlock(...)
end
mod.exports.read = function(...)
  return world:activeBlockAt(...)
end
mod.exports.events = function()
  return events
end
mod.exports.reenter = function(value)
  reenter = value
end
mod.exports.nested = function()
  return nested
end
