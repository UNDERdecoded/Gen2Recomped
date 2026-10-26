-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Optional native conveniences follow their contributing mod's live options.
local Host=require('src.mods.Runtime')
local M={}
local providers={}
local function release(p)
 p.config=nil
 for i=#providers,1,-1 do if providers[i]==p then table.remove(providers,i)end end
end
function M.attach(config)
 assert(type(config)=='table'and type(config.active)=='function'and type(config.option)=='function','feature options need active/option callbacks')
 local facade=require('src.core.Game3');local who=Host.currentMod or facade._callbackOwner()
 assert(who,'feature options need a mod owner')
 local c={};for _,key in ipairs{'active','option','time','outdoors','language'}do
  assert(config[key]==nil or type(config[key])=='function','invalid feature callback');c[key]=config[key]
 end
 local p={who=who,config=c,hooks=Host.hooks,events=Host.events,errors={}}
 providers[#providers+1]=p
 return function()release(p)end
end
local function call(p,key,...)
 local fn=p.config and p.config[key];if not fn then return nil end
 local result={pcall(require('src.core.Game3')._withCallbackOwner,p.who,fn,...)}
 if not result[1]then
  if not p.errors[key]then Host.reportError(p.who,'feature '..key..': '..tostring(result[2]));p.errors[key]=true end
  return nil
 end
 return result[2]
end
function M.provider(key)
 for i=#providers,1,-1 do
  local p=providers[i]
  if p.hooks~=Host.hooks or p.events~=Host.events then release(p)
  else
   local game=require('src.compat.gen1.NativeSession').game()
   local mod=game and game.mods and game.mods.mods and game.mods.mods[p.who]
   if(not game or mod and mod.enabled~=false and not mod.failed)and call(p,'active')==true and call(p,'option',key)==true then return p end
  end
 end
end
function M.enabled(key)return M.provider(key)~=nil end
M.call=call
function M.releaseOwner(_,who)
 for i=#providers,1,-1 do if providers[i].who==who then release(providers[i])end end
end
function M.release()for i=#providers,1,-1 do release(providers[i])end end
require('src.core.game3.asset_stream').register(M)
return M
