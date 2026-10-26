-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Current native palette/warp fades and owned field fades share native clocks.
local Native=require('src.compat.gen1.NativeSession')
local Layer=require('src.render.FieldFade')
local Transition=require('src.render.Transition')
local Flow=require('src.compat.gen1.UiFlow')
local G=require('src.core.Game3')
local F={MODE={FROM_BLACK=0,TO_BLACK=1,FROM_WHITE=2,TO_WHITE=3}}
local current
local function retire()
 local c=current;current=nil
 if c then
  local state=c.state;state.ramp=nil;state:releaseVeil();c.flow:retire()
  state.sourceRetired=true;state.game,state.ow=nil,nil;c.state,c.flow=nil,nil
 end
end
local function observed()
 if current and not current.flow:valid()then retire()end
 local g=Native.game();if not(g and g.stack)then return end
 for i=#(g.stack.states or{}),1,-1 do
  local state=g.stack.states[i]
  local alpha,white,direction,active,locked=Layer.describe(state)
  if alpha==nil then alpha,white,direction,active,locked=Transition.describe(state)end
  if alpha~=nil then return alpha,white,direction,active,locked,state end
 end
end
function F.isActive()local _,_,_,active=observed();return active==true end
local function owner()
 local host=package.loaded['src.mods.Runtime'];return host and host.currentMod or G._callbackOwner()
end
function F.clear()
 if not current or current.who~=owner()then return false end
 retire();return true
end
function F.begin(mode,speed,done)
 assert(type(mode)=='number'and mode%1==0 and mode>=0 and mode<=3,'invalid native fade mode')
 speed=speed or 1;assert(type(speed)=='number'and speed%1==0 and speed>=1 and speed<=600,'invalid native fade speed')
 assert(done==nil or type(done)=='function','invalid fade continuation')
 local g=Native.resolve();if not g then return false,'field fade requires an admitted native world'end
 observed()
 if current then
  if current.who~=owner()then return false,'fade belongs to another mod'end
  retire()
 end
 local _,_,_,_,_,foreign=observed();if foreign then return false,'native fade already owns presentation'end
 local flow,why=Flow.new();if not flow then return false,why end
 local outward=mode==1 or mode==3
 local state=Layer.new(g,nil,mode>=2 and'white'or'black',{ownedHold=true})
 state.alpha=outward and 0 or 1;state.sourceFadeDirection=outward and 1 or -1
 local record={game=g,flow=flow,state=state,who=owner()};current=record
 state.ramp={from=state.alpha,to=outward and 1 or 0,frames=16*speed,steps=16,stepFrames=speed,t=0,
  onDone=function()
   if current~=record or not flow:valid()then return end
   local callback=done;done=nil
   if not outward then retire()end
   if callback then G._withCallbackOwner(record.who,callback)end
  end}
 flow:push(state);return true
end
F._service={release=retire,poll=function()if current then observed()end end,
 releaseOwner=function(_,who)if current and current.who==who then retire()end end}
require('src.core.game3.asset_stream').register(F._service)
return setmetatable(F,{__index=function(_,key)
 local alpha,white,direction,active,locked=observed()
 if key=='active'then return active==true end
 if key=='t'then return math.floor(math.max(0,math.min(1,alpha or 0))*16+.5)end
 if key=='mode'then return(white and 2 or 0)+(direction==1 and 1 or 0)end
 if key=='_dir'then return direction or 0 end
 if key=='lockInput'then return locked==true end
end,__newindex=function(t,key,value)
 if key=='t'or key=='mode'or key=='_dir'or key=='active'or key=='lockInput'then
  error('native fade observation '..tostring(key)..' is read-only',2)
 end
 rawset(t,key,value)
end})
