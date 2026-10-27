-- Compatibility reads over owned map views; permissions use the live native
-- collision owner and never mutate it or run player/warp/script events.
local Session=require('src.compat.gen1.NativeSession')
local Map=require('src.core.game3.map')
local MB=require('src.compat.gen1.MetatileBehavior')
local runtime=require('src.compat.gen1.CollisionRuntime').new()
local Collision={}
local warpBehaviors={}
for _,name in ipairs({'WATER_DOOR','DEEP_SOUTH_WARP','LAVARIDGE_GYM_B1F_WARP','LAVARIDGE_GYM_1F_WARP',
  'AQUA_HIDEOUT_WARP','MT_PYRE_HOLE','MOSSDEEP_GYM_WARP','BRIDGE_OVER_OCEAN',
  'WATER_SOUTH_ARROW_WARP','SHOAL_CAVE_ENTRANCE','STAIRS_OUTSIDE_ABANDONED_SHIP'})do
  warpBehaviors[MB.require(name)]=true
end
local function integer(v)return type(v)=='number'and v==v and math.abs(v)<math.huge and v%1==0 end
local function current()return runtime:current()end
function Collision.inBounds(x,y)
  local g,w=Session.resolve()
  return g~=nil and integer(x)and integer(y)and w.map:inBounds(x,y)or false
end
function Collision.behaviorOn(def,x,y)return runtime:behavior(def,x,y)end
function Collision.behavior(x,y)return Collision.behaviorOn(current(),x,y)end
function Collision.worldBehavior(x,y)
  if not(integer(x)and integer(y))then return nil end
  local def=current();if not def then return nil end
  local mid,pair=Map.worldMidAt(x,y,def)
  if pair==def.pair then return runtime:behaviorMid(def,mid)end
  for _,entries in ipairs({Map.neighborList,Map.world})do
    for _,row in ipairs(entries)do
      local target=row.def
      if target and target.pair==pair then return runtime:behaviorMid(target,mid)end
    end
  end
end
function Collision.cell(x,y)
  local def=current();local layout=def and def.midLayout
  return layout and integer(x)and integer(y)and Collision.inBounds(x,y)and layout:collAt(x,y)or 255
end
function Collision.elevationOn(def,x,y)
  local layout=def and def.midLayout
  if not(layout and integer(x)and integer(y))or x<0 or y<0 or x>=layout.width or y>=layout.height then return nil end
  return layout:elevAt(x,y)
end
function Collision.elevationAt(x,y)
  local g,w=Session.resolve()
  if g and integer(x)and integer(y)and w.map:inBounds(x,y)then return w.map:cellElevation(x,y)end
end
function Collision.canEnter(game,x,y,opts)return runtime:canEnter(game,x,y,opts)end
function Collision.isWalkable(x,y)
  local g,w=Session.resolve()
  return g~=nil and integer(x)and integer(y)and w.map:inBounds(x,y)and w.map:isWalkableCell(x,y)or false
end
function Collision.isWater(x,y)
  local g,w=Session.resolve()
  return g~=nil and integer(x)and integer(y)and w.map:inBounds(x,y)and w.map:isWaterCell(x,y)or false
end
function Collision.isGrass(x,y)
  local g,w=Session.resolve()
  return g~=nil and integer(x)and integer(y)and w.map:inBounds(x,y)and w.map:isGrassCell(x,y)or false
end
function Collision.nextElevation(def,at,x,y,px,py)
  local g=Session.resolve();local maps=g and Map._context(g)
  if not(maps and maps:isOwned(def)and maps:definition(def.id)==def and integer(x)and integer(y))then
    return at,nil
  end
  return require('src.world.Map').elevationTransition(at,
    Collision.elevationOn(def,x,y),Collision.elevationOn(def,px,py))
end
function Collision.ledgeLanding(game,x,y,dir)
  local g,w=Session.resolve(game)
  if not(g and integer(x)and integer(y)and w.map:inBounds(x,y))then return nil end
  local _,fx,fy,distance=require('src.world.Ledge').approach(w.map,g.data,x,y,dir)
  if not fx then return nil end
  local delta=require('src.world.Collision').DELTA[dir]
  local lx,ly=x+delta[1]*(distance or 2),y+delta[2]*(distance or 2)
  if w.map:inBounds(lx,ly)then return lx,ly end
end
function Collision.isWarpMetatileBehavior(behavior)
  return type(behavior)=='number'and((behavior>=0x60 and behavior<=0x6f)or behavior==0x71 or warpBehaviors[behavior]==true)or false
end
function Collision.warpAt(x,y)
  local def=current();if not(def and Collision.inBounds(x,y))then return nil end
  local cell=Collision.cell(x,y);local behavior=Collision.behaviorOn(def,x,y)
  if not((cell>=0x60 and cell<=0x7f)or warpBehaviors[behavior])then return nil end
  for _,warp in ipairs(def.warps or{})do if warp.x==x and warp.y==y then return warp end end
end
function Collision.resolveWarpDestination(game,warp)
  local g,w=Session.resolve(game)
  if not g or type(warp)~='table'then return nil,'no admitted native warp observation'end
  local maps=Map._context(g);local found
  local definitions,why=maps:definitions()
  if not definitions then return nil,why end
  for _,def in pairs(definitions)do
    for _,row in ipairs(def.warps or{})do if row==warp then found=true;break end end
    if found then break end
  end
  if not found then return nil,'foreign or retired warp observation'end
  local native={};for k,v in pairs(warp)do native[k]=v end
  native.destMap=warp.nativeDestination or warp.destMap
  if not g.data.maps[native.destMap]then
    local id=require('src.compat.gen1.MapIdentity').bind(g.data.maps,require('src.core.GameVersion').get()):nativeId(native.destMap)
    if id then native.destMap=id end
  end
  local id,x,y=require('src.world.Warp').observeDestination(g.data,native,w.lastOutdoor,w.backupWarp,g.save)
  if not id then return nil end
  local def=maps:definition(id)
  if not def then return nil,'warp destination is not an admitted source map'end
  return def.id,x,y
end
function Collision.clear()runtime:release()end
Collision.release=Collision.clear
setmetatable(Collision,{__index=function(_,key)
  if key=='_grid'then return runtime:grid()end
  local def=current();if not def then return nil end
  if key=='_mapDef'then return def end
  if key=='_mapId'then return def.id end
  local layout=def.midLayout
  if key=='_widthCells'then return layout and layout.width or 0 end
  if key=='_heightCells'then return layout and layout.height or 0 end
  if key=='_warps'then
    local out={};for _,warp in ipairs(def.warps or{})do
      local active=Collision.warpAt(warp.x,warp.y);if active then out[warp.y*1024+warp.x]=active end
    end
    return out
  end
end})
return Collision
