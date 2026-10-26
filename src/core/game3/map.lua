-- Read-side compatibility entry point over the real native GBA map owner.
-- Simulation loads, player/script ownership and resource warmers are not
-- implemented by aliases to differently shaped native functions.
local Runtime=require('src.compat.gen1.MapRuntime')
local Graph=require('src.compat.gen1.MapGraph')
local Version=require('src.core.GameVersion')
local Map={WORLD_HOPS=2,WARM_MARGIN_SCREENS=1}
local context,gameOwner,edition,cache
local function rawGame(game)
  local facade=package.loaded['src.core.Game3']
  return type(facade)=='table'and facade.native and facade.native(game)or game
end
local function currentGame()
  local game=package.loaded['src.core.Game']
  return type(game)=='table'and game or nil
end
local function getContext(game)
  game=rawGame(game or currentGame() or gameOwner)
  local id=Version.get();local info=Version.info(id)
  if not game or not info or info.generation~=3 then
    if context then context:release()end
    context,gameOwner,edition,cache=nil,nil,nil,nil
    return nil,'no native GBA session'
  end
  if game~=gameOwner or id~=edition then
    if context then context:release()end
    gameOwner,edition,cache=game,id,nil
    context=Runtime.new(function()return gameOwner end,function()return edition end)
  end
  return context
end
function Map.currentDef()
  local runtime,why=getContext();if not runtime then return nil,why end
  return runtime:current()
end
function Map.ensureMidLayout(game,id,def)
  local runtime,why=getContext(game);if not runtime then return nil,why end
  if def and not runtime:isOwned(def)then return nil,'native or foreign map definitions are not writable compatibility views' end
  return runtime:layout(id,def)
end
function Map.definitions(game)
  local runtime,why=getContext(game);if not runtime then return nil,why end
  return runtime:definitions()
end
function Map.loadNeighborsDepth1(game,def)
  local runtime,why=getContext(game);if not runtime then return {},{},why end
  return runtime:neighbors(def)
end
function Map.computeWorld(maps,root,hops,reachW,reachH,ensure)
  -- Custom definitions follow the established public dimensions. Native
  -- source grids retain authored padding but connect at their true extent.
  local runtime=context
  local C=require('src.core.game3.connections')
  local function size(def)
    if runtime and runtime:isOwned(def)then return def.width,def.height end
    return C.sizeOf(def)
  end
  return Graph.compute(maps,root,hops,reachW,reachH,ensure,size)
end
function Map.refreshWorld(game,reachW,reachH,root)
  local runtime=getContext(game);if not runtime then cache=nil;return {}end
  local def=runtime:current();root=root or(def and def.id)
  local maps=runtime:definitions()
  if not(root and maps and maps[root])then cache=nil;return {}end
  reachW,reachH=math.floor(tonumber(reachW)or 0),math.floor(tonumber(reachH)or 0)
  if cache and cache.root==root and cache.reachW==reachW and cache.reachH==reachH
      and cache.def==maps[root] and cache.hops==Map.WORLD_HOPS then return cache.world end
  local world=Map.computeWorld(maps,root,Map.WORLD_HOPS,reachW,reachH,function(id,owned)
    runtime:layout(id,owned)
  end)
  cache={root=root,reachW=reachW,reachH=reachH,def=maps[root],hops=Map.WORLD_HOPS,world=world}
  return world
end
function Map.worldMidAt(x,y,def)
  def=def or Map.currentDef()
  local runtime=getContext()
  local function extent(target)
    if runtime and runtime:isOwned(target)then return target.width,target.height end
    local l=target and target.midLayout;return l and l.width or 0,l and l.height or 0
  end
  return Graph.midAt(x,y,def,Map.neighborList,Map.world,extent)
end
function Map.loadedLayoutCount()
  local runtime=getContext();return runtime and runtime:loadedCount()or 0
end
function Map.overscanSlices()
  local out={}
  for _,row in ipairs(Map.neighborList)do out[#out+1]={dir=row.dir,mapId=row.map or row.mapId,offset=row.offset}end
  return out
end
function Map.warmRect(margin)
  local game=gameOwner or currentGame();local states=game and game.stack and game.stack.states
  local ow
  if states then for i=#states,1,-1 do if states[i].isOverworld then ow=states[i];break end end
  elseif game then ow=game.overworld end
  local p=ow and ow.player;if not(p and tonumber(p.cellX)and tonumber(p.cellY))then return nil end
  local field=package.loaded['src.core.game3.field_view'];local display=package.loaded['src.core.game3.display']
  local cols=math.ceil(((field and field._viewW)or(display and display.W)or 240)/16)
  local rows=math.ceil(((field and field._viewH)or(display and display.H)or 160)/16)
  margin=margin or Map.WARM_MARGIN_SCREENS
  local mx,my=math.ceil(cols/2)+1+cols*margin,math.ceil(rows/2)+1+rows*margin
  return p.cellX-mx,p.cellY-my,p.cellX+mx,p.cellY+my
end
Map.warmNear=Graph.near
function Map.release()
  if context then context:release()end
  context,gameOwner,edition,cache=nil,nil,nil,nil
end
-- Internal typed boundary used by the distinct Game3 facade.
function Map._context(game)return getContext(game)end
setmetatable(Map,{__index=function(_,key)
  if key=='current'then local def=Map.currentDef();return def and def.id end
  if key=='_def'or key=='_currentDef'then return Map.currentDef()end
  if key=='neighbors'or key=='neighborList'then
    local runtime=getContext();if not runtime then return {}end
    local dirs,list=runtime:neighbors();return key=='neighbors'and dirs or list
  end
  if key=='world'or key=='_worldRoot'or key=='_worldReachW'or key=='_worldReachH'then
    local def=Map.currentDef()
    if not def then cache=nil;return key=='world'and{}or nil end
    if not cache or cache.def~=def then Map.refreshWorld(nil,0,0)end
    if key=='world'then return cache and cache.world or{}end
    if key=='_worldRoot'then return cache and cache.root end
    if key=='_worldReachW'then return cache and cache.reachW end
    return cache and cache.reachH
  end
  if key=='_loadedLayouts'then local runtime=getContext();return runtime and runtime:loadedLayouts()or{}end
end})
return Map
