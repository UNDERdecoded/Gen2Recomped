-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source field presentation over the admitted native world. No second map,
-- actor simulation, effect clock or save is constructed by this interface.
local Session=require('src.compat.gen1.NativeSession')
local Flash=require('src.world.Gen3Flash')
local Scope=require('src.render.GraphicsScope')
local Map=require('src.core.game3.map')
local Native=require('src.core.game3.tileset_native')
local M={cameraPanX=0,cameraPanY=0,_nativeDirty=true}
local tiles=require('src.compat.gen1.FieldTiles').new(M)
local cohort,active,manualRadius,palette,spanCache
local function currentOwner()
  local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  return host and host.currentMod or facade and facade._callbackOwner and facade._callbackOwner()
end
local function release()
  tiles:release()
  if palette then Native.resetSlotPalette(palette.ts,palette.slot)end
  cohort,manualRadius,palette,spanCache=nil,nil,nil,nil
  M.cameraPanX,M.cameraPanY=0,0
  M._nativeDirty=true;M._nativeLayout=nil;M._viewW,M._viewH=nil,nil
end
local function bind(value)
  local game,world,player=Session.resolve(value)
  if not game then release();return nil,world end
  if game~=package.loaded['src.core.Game']then return nil,'field drawing belongs to the current native Game'end
  if not cohort or cohort.game~=game or cohort.data~=game.data or cohort.save~=game.save
      or cohort.loader~=game.mods or cohort.world~=world then
    release();cohort={game=game,data=game.data,save=game.save,loader=game.mods,world=world,map=world.map,users={}}
  elseif cohort.map~=world.map then
    tiles:release();manualRadius=nil;cohort.map=world.map
    if palette then Native.resetSlotPalette(palette.ts,palette.slot);palette=nil end
  end
  local who=currentOwner();if who then cohort.users[who]=true end
  return game,world,player
end
local function record()
  local game,why=bind();if not game then return nil,why end
  local r=Flash.record(game.data);if not r then return nil,'imported Flash radii unavailable'end
  return r
end
function M.flashRadii()
  local r,why=record();if not r then return nil,why end
  local out={};for i,value in ipairs(r.radii)do out[i-1]=value end;return out
end
function M.maxFlashLevel()local r,why=record();return r and r.maxLevel or nil,why end
function M.radiusForLevel(level)
  local r,why=record();if not r then return nil,why end
  level=tonumber(level)or 0
  return r.radii[level+1]or r.radii[1]
end
function M.setFlashLevel(level)
  local game,why=bind();if not game then return false,why end
  manualRadius=nil;return Flash.setLevel(game,level)
end
function M.getFlashLevel()local game=bind();return game and Flash.level(game)or 0 end
function M.setFlashRadius(radius)
  local game,why=bind();if not game then return false,why end
  radius=tonumber(radius)
  if radius and(radius~=radius or math.abs(radius)==math.huge)then return false,'invalid Flash radius'end
  manualRadius=radius;return true
end
M.setPyramidLightRadius=M.setFlashRadius
function M.animateFlashLevel(fromLevel,toLevel)
  local game,why=bind();if not game then return false,why end
  manualRadius=nil;Flash.setLevel(game,fromLevel);Flash.animateTo(game,toLevel)
  -- The native update owns the one-pixel steps and its existing script wait.
end
function M.flashRadius()
  local game=bind();if not game then return nil end
  if manualRadius~=nil then return manualRadius end
  if require('src.core.GameVersion').get()=='emerald'then
    local pyramid=package.loaded['src.script.Gen3BattlePyramid']
    local radius=pyramid and pyramid.lightRadius(game)
    if radius then return radius end
  end
  if Flash.level(game)==0 then return nil end
  return tonumber(game.save.gen3FlashRadius)or Flash.radiusOf(game.data,Flash.level(game))
end
function M.setCameraPanning(x,y)
  local game,why=bind();if not game then return false,why end
  x,y=tonumber(x)or 0,tonumber(y)or 0
  if x~=x or y~=y or math.abs(x)==math.huge or math.abs(y)==math.huge then return false,'invalid camera pan'end
  M.cameraPanX,M.cameraPanY=x,y;return true
end
function M.defaultFlashLevel(value,mapId)
  local game,why=bind(value);if not game then return nil,why end
  local maps=Map.definitions(game);local def=maps and maps[mapId or Map.current]
  local r=Flash.record(game.data);if not r then return nil,'imported Flash radii unavailable'end
  if not def or tonumber(def.cave)==0 or def.cave==nil then return 0 end
  return Flash.lit(game)and r.lit or r.dark
end
function M.setDefaultFlashLevel(value,mapId)
  local level,why=M.defaultFlashLevel(value,mapId)
  if level==nil then return false,why end
  return M.setFlashLevel(level)
end
function M.setBgPaletteOverride(slot,words)
  local game,why=bind();if not game then return false,why end
  if palette and(words==nil or palette.slot~=slot)then
    Native.resetSlotPalette(palette.ts,palette.slot);palette=nil
  end
  if words==nil then return true end
  local def=Map.currentDef();local pair=def and(def.pair or def.midLayout.pair)
  local ts=pair and Native.get(pair)
  if not ts or not Native.setSlotPalette(ts,slot,words)then return false,'native palette unavailable'end
  if palette and palette.ts~=ts then Native.resetSlotPalette(palette.ts,palette.slot)end
  local copy={};for i=1,16 do copy[i]=words[i]or 0 end
  palette={ts=ts,pair=pair,slot=slot,words=copy};return true
end
function M.flashSpans(radius,w,h,cx,cy)
  return Flash.spans(radius,tonumber(w)or 240,tonumber(h)or 160,cx,cy)
end
function M.flashSpansFor(radius,w,h,cx,cy)
  if not spanCache or spanCache.r~=radius or spanCache.w~=w or spanCache.h~=h or spanCache.cx~=cx or spanCache.cy~=cy then
    spanCache={r=radius,w=w,h=h,cx=cx,cy=cy,spans=M.flashSpans(radius,w,h,cx,cy)}
  end
  return spanCache.spans
end
function M.invalidateCell()M._nativeDirty=true end
function M.invalidateLayoutCell()M._nativeDirty=true end
function M.trimNative(atlas,map,pair,visible)
  local keep,busy={},{}
  if pair then keep[pair]=true end
  for key in pairs(visible or{})do keep[key]=true end
  for key in pairs(tiles.atlases)do keep[key]=true end
  for _,store in ipairs{tiles.under,tiles.over}do
    for _,batch in pairs(store)do busy[batch:getTexture()]=true end
  end
  local x0,y0,x1,y1=map.warmRect()
  for _,edge in ipairs(map.world or{})do
    if not map.warmNear or map.warmNear(edge,x0,y0,x1,y1)then
      local p=edge.def and(edge.def.pair or edge.def.midLayout.pair);if p then keep[p]=true end
    end
  end
  return atlas.trim(keep,atlas.RESIDENT_MAX,busy)
end
function M.invalidate()
  tiles:release();M._nativeDirty=true;M._nativeLayout=nil;spanCache=nil
  Native.invalidate()
  if palette then palette.ts=nil end
end
M.release=release
local function dimensions(value,default)
  value=tonumber(value)or default
  assert(value>0 and value<math.huge,'invalid field viewport')
  return math.max(1,math.floor(value))
end
local function draw(value,w,h,opts)
  local game,world,player=bind(value);if not game then return false,world end
  w,h=dimensions(w,240),dimensions(h,160);opts=opts or{}
  assert(type(opts)=='table','invalid field draw options')
  local cam={x=math.floor(player.px+8-w/2)+(M.cameraPanX or 0),
    y=math.floor(player.py+8-h/2)+(M.cameraPanY or 0)}
  if world.g3Shake or world.g3Orb then
    local x,y=require('src.world.Gen3ScreenFx').pan(world)
    if x then cam.x,cam.y=cam.x+x,cam.y+y end
  end
  M._viewW,M._viewH=w,h
  local field={camera=cam,width=w,height=h,actorsOnly=opts.actorsOnly==true,
    skipActors=opts.skipActors or M.hideActors,billboard=opts.billboard,
    endUnderActors=opts.endUnderActors,tiles=tiles}
  if not field.actorsOnly then
    if palette then
      local ts=Native.get(palette.pair)
      if ts and ts~=palette.ts and Native.setSlotPalette(ts,palette.slot,palette.words)then palette.ts=ts end
    end
    local ok,why=tiles:prepare(game,cam,w,h);if not ok then return false,why end
  end
  -- A base draw is usable for native fallback and offscreen captures alike;
  -- invoking it never enters the mod callback again or advances native logic.
  local ok,why=Scope.call(world._drawFieldView,world,field)
  if not ok then error(why,0)end
  return true
end
M.draw=draw
function M._nativeDraw(game,world,body)
  if active then return body(world,true)end
  if M.draw==draw and not palette and manualRadius==nil and not M.hideActors
      and(M.cameraPanX or 0)==0 and(M.cameraPanY or 0)==0 then return body(world)end
  local owner,admitted=bind(game)
  if not owner or admitted~=world then return body(world)end
  local facade=require('src.core.Game3');local view=assert(facade.forNative(game))
  local seams=package.loaded['src.mods.ModSeams'];local who=facade._callbackOwner()
  for i=#(seams and seams._journal or{}),1,-1 do
    local change=seams._journal[i]
    if change.tbl==M and change.key=='draw'and change.after==M.draw then who=change.owner;break end
  end
  -- Native tile cadence continues even when a mod replaces every field pixel.
  local TR=require('src.render.TileRenderer');TR.tick();TR.setSpinning(world.player.spinning)
  local w,h=game.renderer:worldViewSize();M._viewW,M._viewH=w,h
  local renderer=game.renderer
  local canvas,override,mirrored=renderer.worldCanvas,renderer.worldOverride,renderer.worldOverrideMirrored
  active=true
  local ok,result,why=Scope.call(facade._withCallbackOwner,who,M.draw,view,w,h)
  active=nil
  if not ok then
    renderer.worldCanvas,renderer.worldOverride,renderer.worldOverrideMirrored=canvas,override,mirrored
    error(result,0)
  end
  if result==false then
    if cohort and cohort.fallbackReason~=why then
      require('src.core.Logger').warn('source field unavailable: %s',tostring(why));cohort.fallbackReason=why
    end
    return body(world,true)
  end
  return result
end
-- Native drawing uses the same imported radii, but can also serve a mod's
-- explicit radius (e.g. a temporary outdoor pool of light) without a save edit.
function M._drawFlash(world,field)
  local radius=M.flashRadius()
  if radius~=nil then Flash.drawMask(radius,field.width,field.height,field.width/2,field.height/2)end
end
local service={release=release,releaseOwner=function(_,who)
  if cohort and cohort.users[who]then
    cohort.users[who]=nil
    if not next(cohort.users)then release()end
  end
end,poll=function()
  if cohort then bind(cohort.game)end
end}
M._service=service
require('src.core.game3.asset_stream').register(service)
local Assets=require('src.render.Assets')
Assets.register(function()
  local current=package.loaded['src.core.game3.field_view']
  if current then current.invalidate()end
end)
setmetatable(M,{__index=function(_,key)
  if key=='flashLevel'then return M.getFlashLevel()end
  if key=='MAX_FLASH_LEVEL'then return M.maxFlashLevel()end
end,__newindex=function(t,key,value)
  if key=='flashLevel'then M.setFlashLevel(value)else rawset(t,key,value)end
end})
return M
