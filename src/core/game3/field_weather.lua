-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- The native world/script controller owns the weather byte and its clock.
local Native=require('src.compat.gen1.NativeSession')
local W={}
function W.getWeather()
 local game,world=Native.resolve()
 if not game then return nil,'no native field weather'end
 local id=game.save and game.save.gen3WeatherActive
 if id==nil then id=world.map.def.weather end
 return tonumber(id)or 0
end
return W
