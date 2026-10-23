local mod = ...
local events, stops = {}, {}
for _, phase in ipairs({ "preparing", "updated" }) do
  local label = phase
  local name = "world.live_maps_" .. phase
  if not mod.supports or mod:supports("events", name) then
    stops[#stops + 1] = mod.events:on(name, function(payload)
      events[#events + 1] = { phase = label, mapId = payload.mapId, maps = payload.maps }
    end)
  end
end
mod.exports.api = mod
mod.exports.events = events
mod.exports.maps = function()
  return mod.world:liveMaps()
end
mod.exports.stop = function()
  for _, stop in ipairs(stops) do
    stop()
  end
end
