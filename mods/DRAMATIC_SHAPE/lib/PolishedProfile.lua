-- Isolate Polished's rearranged artwork from the GSC numeric tile profiles.
-- Geometry/material defaults and collision meanings remain shared; all tile
-- pins and building grids come from the verified Polished index roster.
local Profile = {}
local function clone(value)
  if type(value)~='table'then return value end
  local out={};for k,v in pairs(value)do out[k]=clone(v)end;return out
end
function Profile.apply(base, indices, furniture)
  assert(type(indices) == 'table' and type(indices.tilesets) == 'table',
         'Polished Crystal voxel indices are missing')
  local out = {}
  for key, value in pairs(base) do out[key] = value end
  out.tilesets = {}
  local Game=require('src.core.Game')
  for id, entry in pairs(indices.tilesets) do
    local copy = clone(entry)
    out.tilesets[id] = copy
  end
  for id, overrides in pairs(furniture or {}) do
    local entry = out.tilesets[id] or {}; out.tilesets[id] = entry
    -- A complete object supersedes partial exact-art pins, including any
    -- former class for its changed or unchanged component tiles.
    local replaced = {}
    for key, tiles in pairs(overrides) do
      if key ~= 'heights' and not key:match('^when_') then
        for _, tile in ipairs(tiles) do replaced[tile] = true end
      end
    end
    local ts=Game.data and Game.data.tilesets and Game.data.tilesets[id]
    for tile,variant in pairs(ts and ts.tileVariants or {})do
      if replaced[variant.base] then replaced[tile]=true end
    end
    for key, tiles in pairs(entry) do
      if type(tiles) == 'table' and #tiles > 0 and type(tiles[1]) == 'number' then
        local kept={};for _,tile in ipairs(tiles)do if not replaced[tile]then kept[#kept+1]=tile end end
        entry[key]=kept
      end
    end
    for key,value in pairs(overrides)do entry[key]=clone(value)end
  end
  out.buildings = indices.buildings or {}
  for id,entry in pairs(out.tilesets)do
    local ts=Game.data and Game.data.tilesets and Game.data.tilesets[id]
    local assigned={}
    for class,tiles in pairs(entry)do
      if type(tiles)=='table' and #tiles>0 and type(tiles[1])=='number'then
        for _,tile in ipairs(tiles)do assigned[tile]=class end
      end
    end
    for tile,variant in pairs(ts and ts.tileVariants or {})do
      for class,tiles in pairs(entry)do
        if not assigned[tile] and type(tiles)=='table' and #tiles>0 and type(tiles[1])=='number' then
          for _,base in ipairs(tiles)do if base==variant.base then tiles[#tiles+1]=tile;assigned[tile]=class;break end end
        end
      end
      for _,kind in ipairs({'when_above','when_below','when_cell'})do
        local rules=entry[kind]
        if rules and rules[variant.base] and not rules[tile]then rules[tile]=clone(rules[variant.base])end
      end
    end
  end
  return out
end
return Profile
