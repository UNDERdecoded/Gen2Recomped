-- Source-facing transition phases over the real native StateStack admission.
local Runtime=require('src.compat.gen1.TransitionRuntime')
local Catalog=require('src.compat.gen1.TransitionCatalog')
local Version=require('src.core.GameVersion')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local runtime=Runtime.new()
local T={}
local function selectionOptions(edition,opts)
  if Catalog.family(edition)~='rse'then return opts end
  local out=Runtime.copy(opts or{})
  local game,world,player=require('src.compat.gen1.NativeSession').resolve()
  if game and out.mapType==nil then
    local types={NONE=0,TOWN=1,CITY=2,ROUTE=3,UNDERGROUND=4,UNDERWATER=5,OCEAN_ROUTE=6,UNKNOWN=7,INDOOR=8,SECRET_BASE=9}
    out.mapType=types[world.map.def.mapType]or tonumber(world.map.def.mapType)
  end
  local behavior=out.mapBehavior
  if game and behavior==nil then
    local collision=package.loaded['src.core.game3.collision']
    if collision then behavior=collision.behavior(player.cellX,player.cellY)end
  end
  if behavior~=nil then
    local env=package.loaded['src.core.game3.battle.env_rse']
    if env and env.isSurfable then out._surfable=env.isSurfable(behavior)
    elseif game then
      local record=game.data.constants and game.data.constants.gen3SourceBehaviorFlags
      local converter=require('src.compat.gen1.MetatileBehavior').translator(edition)
      local raw=converter and converter.raw(behavior)
      local bits=record and type(record.raw)=='string'and raw and record.raw:byte(raw+1)
      out._surfable=bits~=nil and math.floor(bits/2)%2==1
    end
  end
  return out
end
local function methodOwner(name)
  local seams=package.loaded['src.mods.ModSeams']
  for i=#(seams and seams._journal or{}),1,-1 do
    local change=seams._journal[i]
    if change.tbl==T and change.key==name and change.after==T[name]then return change.owner end
  end
end
local function call(name,...)
  local facade=package.loaded['src.core.Game3']
  if facade and facade._withCallbackOwner then return facade._withCallbackOwner(methodOwner(name)or facade._callbackOwner(),T[name],...)end
  return T[name](...)
end
function T.family()return Catalog.family(Version.get())end
function T.ids(family)
  local edition=Version.get()
  if family then assert(family=='frlg'or family=='rse','unknown transition family');if family~=T.family()then edition=family=='frlg'and'firered'or'emerald'end end
  local c=Catalog.new(edition)
  function c.getTerrainByMap(opts)return Catalog.terrain(edition,selectionOptions(edition,opts))end
  function c.pickWild(opts)return Catalog.pick(edition,selectionOptions(edition,opts),false)end
  function c.pickTrainer(opts)return Catalog.pick(edition,selectionOptions(edition,opts),true)end
  if c.family=='rse'then function c.pickSpecial(group,opts)return Catalog.special(edition,group,opts)end end
  return c
end
function T.getTerrainByMap(opts)return T.ids().getTerrainByMap(opts)end
function T.pickWild(opts)return T.ids().pickWild(opts)end
function T.pickTrainer(opts)return T.ids().pickTrainer(opts)end
function T.pick(opts)opts=opts or{};if opts.transitionId then return opts.transitionId end;return Catalog.pick(Version.get(),selectionOptions(Version.get(),opts),not opts.wild)end
function T.defs()
  local defs={};local catalogue=Catalog.new(Version.get())
  local native=require('src.render.BattleTransition')
  local c=runtime:current();local data=c and c.data
  for id,style in pairs(catalogue.styles)do
    local def=data and data.transitions and data.transitions[style]or native.STYLES[style]
    if def then defs[id]={id=id,nativeStyle=style,frames=def.frames,kind=def.kind,flash=def.flash}end
  end
  return defs
end
function T.start(id,opts,callback)
  if Boundary.active('transition.start')then
    local c=assert(runtime.starting,'native transition unavailable')
    if c.startConfigured then return true end
    local result=runtime:configure(c,id,opts,callback);c.startConfigured=true
    Boundary.invoke('transition.start');return result
  end
  return runtime:start(id,opts,callback)
end
function T.isActive()return runtime:current()~=nil end
function T.finish()
  if Boundary.active('transition.finish')then return Boundary.invoke('transition.finish')end
  return runtime:complete(runtime:current(),true)
end
function T.abort()return runtime:complete(runtime:current(),false)end
function T.tick()return Boundary.invoke('transition.tick')end
function T.draw()
  local c=runtime:current();if not c then return false end
  if c.worldDrawn then c.worldDrawn=false;return true end
  return Boundary.invoke('transition.draw')
end
function T.drawWorld(canvas,w,h)return runtime:drawWorld(runtime:current(),canvas,w,h)end
function T.blackSpans()return nil,'native scanline-mask observations are not available for every registered style'end
function T.screenCoverage()return nil,'native scanline-mask observations are not available for every registered style'end
function T.release()runtime:release()end
function T.cancelOwner(who)runtime:cancelOwner(who)end
function T._nativeStart(state)
  local c=runtime:bind(state);if not c then return end
  -- A direct source start has already passed through its wrappers. Only a
  -- native encounter needs the public start notification on stack entry.
  if c.sourceStarted then return runtime:configure(c,c.id,c.options,c.continue)end
  local previous=runtime.starting;runtime.starting=c
  local ok,result=pcall(runtime.phase,runtime,c,'start',function()return true end,function()
    return call('start',c.id,c.options,c.continue)
  end)
  runtime.starting=previous
  if not ok then error(result,0)end
  return result
end
function T._nativeTick(state,body)
  local c=runtime:bind(state);if not c then return body()end
  c.worldDrawn=false
  return runtime:phase(c,'tick',body,function()return call('tick')end)
end
function T._nativeDraw(state,body)
  local c=runtime:bind(state);if not c then return body()end
  return runtime:phase(c,'draw',body,function()return call('draw')end)
end
function T._nativeFinish(state,body)
  local c=runtime:bind(state);if not c then return body()end
  c.ending=true
  return runtime:phase(c,'finish',function()
    if c.game.stack:top()~=state then return false,'native transition is covered by another state'end
    runtime:notify(c,true);return body()
  end,function()return call('finish')end)
end
function T._nativeExit(state)runtime:exit(state)end
function T._compositeWorld(renderer)return runtime:composite(renderer,function(...)return call('drawWorld',...)end)end
setmetatable(T,{
  __index=function(_,key)
    if key=='ID'or key=='TERRAIN'then return T.ids()[key]end
    local c=runtime:observed()
    if not c then return key=='_active'and false or key=='_frame'and 0 or key=='_phase'and'idle'or nil end
    if key=='_active'then return not c.released and not c.state.finished end
    if key=='_phase'then
      if c.released then return c.state.phase=='done'and'done'or'idle'end
      if c.ending then return 'ending'end
      return(c.state.phase=='frlg_intro'or c.state.phase=='flash')and'intro'or'main'
    end
    if key=='_frame'then return c.state.frame end
    if key=='_opts'then return c.options end
    if key=='_transitionId'then return c.id end
    if key=='_worldDrawn'then return c.worldDrawn==true end
    if key=='_intro'and c.state.phase=='frlg_intro'then
      local p=(math.max(1,c.state.t)-1)%16
      return{blend=math.max(0,math.min(16,p<8 and(p+1)*2 or(15-p)*2))}
    end
  end,
  __newindex=function(t,key,value)
    if key=='_worldDrawn'then local c=runtime:current();if c then c.worldDrawn=value==true end
    elseif key:sub(1,1)=='_'then error('transition state belongs to its native owner: '..key,2)
    else rawset(t,key,value)end
  end,
})
return T
