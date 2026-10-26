-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native field weather observations use the same enum as the ROM importer.
local Field=require('src.core.game3.field_weather')
local M={}
for name,id in pairs(require('src.core.Gen3WeatherIds').byName)do M[name]=id end
M.FOG,M.ASH=M.FOG_HORIZONTAL,M.VOLCANIC_ASH
M.get=Field.getWeather
function M.isActive()
 local id=M.get();return id~=nil and id~=M.NONE and id~=M.SUNNY
end
return M
