-- Detached residency snapshots. Offsets are world pixels, as in Gen1Recomp.
local Runtime = require("src.mods.Runtime")
local M = {}
function M.snapshot(world)
  local out = {}
  if not (world and world.map) then
    return out
  end
  out[1] = { mapId = world.map.id, ox = 0, oy = 0, active = true }
  for _, neighbor in ipairs(world.neighbors or {}) do
    out[#out + 1] = {
      mapId = neighbor.map and neighbor.map.id or neighbor.id,
      ox = neighbor.ox or (neighbor.cx or 0) * 16,
      oy = neighbor.oy or (neighbor.cy or 0) * 16,
      active = false,
    }
  end
  return out
end
function M.preparing(world)
  if not world.map or world.preparingLiveMaps or not Runtime.wants("world.live_maps_preparing") then
    return
  end
  local previous = world.preparingLiveMaps
  world.preparingLiveMaps = true
  Runtime.emit("world.live_maps_preparing", { mapId = world.map.id, maps = M.snapshot(world) })
  world.preparingLiveMaps = previous
end
function M.updated(world)
  if not world.map or world.preparingLiveMaps or not Runtime.wants("world.live_maps_updated") then
    return
  end
  Runtime.emit("world.live_maps_updated", { mapId = world.map.id, maps = M.snapshot(world) })
end
return M
