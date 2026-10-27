-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Live cartridge-numbered offsets; changing datasets never keeps an old row.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local P={}
for _,kind in ipairs{'front','back','elev'}do
 P[kind]=setmetatable({},{__index=function(_,id)
  local g=Native.game();if not g then return nil end
  local key=Ids.new(g.data):native('pokemon',id);local row=key and g.data.pokemon[key]
  if not row then return nil end
  if kind=='elev'then return g.data.constants.gen3Elevation and g.data.constants.gen3Elevation[key]or 0 end
  local coords=kind=='front'and row.frontPicCoords or row.backPicCoords
  return coords and coords.yOffset
 end,__newindex=function()error('native picture coordinates are read-only',2)end})
end
return P
