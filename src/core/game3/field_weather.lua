-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Observe the native resolved field weather, including the native cycle stage.
local Native=require('src.compat.gen1.NativeSession')
local Weather=require('src.world.Gen3Weather')
local M={}
function M.getWeather()
 local game,world=Native.resolve()
 if not game then return nil end
 local name=world:fieldWeather()
 local resolved=name and Weather.resolve(name,world.weatherFrame or 0,game.save.gen3WeatherStage or 0)
 local names=game.data.constants and game.data.constants.gen3WeatherNames or require('src.core.Gen3WeatherIds').names
 for id,value in pairs(names or{})do
  if value==resolved and type(id)=='number'and id%1==0 and id>=0 then return id end
 end
end
return M
