-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native GBA weather identifiers; presentation reads the world's current byte.
local W={SUNNY=2,RAIN=3,get=require('src.core.game3.field_weather').getWeather}
return setmetatable(W,{__index=function(_,key)
 local game=require('src.compat.gen1.NativeSession').game()
 for id,name in pairs(game and game.data.constants and game.data.constants.gen3WeatherNames or{})do
  if name==key or name=='WEATHER_'..key then return id end
 end
end})
