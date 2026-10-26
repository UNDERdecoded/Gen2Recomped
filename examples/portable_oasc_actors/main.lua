-- Reusable public-only module plus a ROM-free contract consumer.
local mod = ...
local chunk = assert((loadstring or load)(assert(mod:read("Actors.lua")), "@portable_actors/Actors"))
mod.exports.new = chunk().new
mod.exports.observe = function(mapId)
  local data = mod.renderData
  if not data or not data.supportsActors or not data:supportsActors(1) then
    return nil, "actor render data v1 unavailable"
  end
  local scene, why = data:actors(1, mapId)
  if not scene then
    return nil, why
  end
  local sheets = {}
  for _, actor in ipairs(scene.actors) do
    if not sheets[actor.sheetId] then
      local source, err = data:actorSheet(1, mapId, actor.sheetId)
      if not source then
        return nil, err
      end
      sheets[actor.sheetId] = source
    end
  end
  return { scene = scene, sheets = sheets }
end
