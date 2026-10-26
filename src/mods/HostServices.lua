-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local DateTime=require('src.core.DateTime')
local S={}
local STATES={unknown=true,battery=true,nobattery=true,charging=true,charged=true}
function S.install(loader,mod,api)
  api.datetime={}
  for _,name in ipairs({'date','time','dateTime'}) do
    api.datetime[name]=function(_,game,timestamp)return DateTime[name](game,timestamp)end
  end
  api.device={powerInfo=function()
    local system=love and love.system
    if not (system and type(system.getPowerInfo)=='function') then return 'unknown',nil end
    local ok,state,percent=pcall(system.getPowerInfo)
    if not ok then return 'unknown',nil end
    if not STATES[state] then state='unknown' end
    if type(percent)~='number' or percent~=percent or percent<0 or percent>100 then percent=nil
    else percent=math.floor(percent) end
    return state,percent
  end}
end
return S
