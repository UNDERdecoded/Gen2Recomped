-- Identical mod entry on both loaders; no engine imports or backend branches.
local mod = ...
local r = assert(mod.renderData)
mod.exports.handle = r
function mod.exports.observe(mapId, query)
  if not r:supports(1) then
    return nil, "unsupported generation"
  end
  local grid, err = r:snapshot(1, mapId, query)
  if not grid then
    return nil, err
  end
  local graphics, why = r:tileset(1, mapId, query and query.mapId)
  if not graphics then
    return nil, why
  end
  return { grid = grid, graphics = graphics }
end
