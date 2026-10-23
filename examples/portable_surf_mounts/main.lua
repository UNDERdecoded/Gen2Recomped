-- Reusable public-only module plus a ROM-free contract consumer.
local mod = ...
local chunk = assert((loadstring or load)(assert(mod:read("Mounts.lua")), "@portable_mounts/Mounts"))
mod.exports.new = chunk().new
mod.exports.observe = function(mapId)
  local data = mod.renderData
  if not data or not data.supportsSurfMounts or not data:supportsSurfMounts(1) then
    return nil, "mount render data v1 unavailable"
  end
  local scene, why = data:surfMounts(1, mapId)
  if not scene then
    return nil, why
  end
  local sheets = {}
  for _, mount in ipairs(scene.mounts) do
    if not sheets[mount.sheetId] then
      local source, err = data:surfMountSheet(1, mapId, mount.sheetId)
      if not source then
        return nil, err
      end
      sheets[mount.sheetId] = source
    end
  end
  return { scene = scene, sheets = sheets }
end
