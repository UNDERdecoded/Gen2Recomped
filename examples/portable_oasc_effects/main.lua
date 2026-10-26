-- Reusable public-only module plus a ROM-free contract consumer.
local mod = ...
local chunk = assert((loadstring or load)(assert(mod:read("Effects.lua")), "@portable_effects/Effects"))
mod.exports.new = chunk().new
mod.exports.observe = function(mapId)
  local data = mod.renderData
  if not data or not data.supportsFieldEffects or not data:supportsFieldEffects(1) then
    return nil, "effect render data v1 unavailable"
  end
  local scene, why = data:fieldEffects(1, mapId)
  if not scene then
    return nil, why
  end
  local sheets = {}
  for _, effect in ipairs(scene.effects) do
    if not sheets[effect.sheetId] then
      local source, err = data:fieldEffectSheet(1, mapId, effect.sheetId)
      if not source then
        return nil, err
      end
      sheets[effect.sheetId] = source
    end
  end
  return { scene = scene, sheets = sheets }
end
