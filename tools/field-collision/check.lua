package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local C=require('src.core.game3.collision')
local Map=require('src.core.game3.map')
local Native=require('src.world.Collision')
local Tiles=require('src.render.Gen3Tiles')
local Behavior=require('src.compat.gen1.MetatileBehavior')
T.eq(package.loaded['src.core.Game'],nil,'collision import does not bootstrap a game')
T.eq(C.behavior(0,0),nil);T.eq(C.canEnter(nil,0,0),false)
local previous=package.loaded['src.core.Game']
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  local f=require('tools.map-runtime.fixture').new(edition)
  local g,w,field=f.game,f.world,f.map
  w.player={cellX=0,cellY=0,px=0,py=0,elevation=6,surfing=false}
  w.entities={w.player};g.save={player={},flags={}}
  package.loaded['src.core.Game']=g
  local def=assert(Map.currentDef())
  T.eq(C._mapId,def.id);T.eq(C._mapDef,def);T.eq(C._widthCells,4);T.eq(C._heightCells,2)
  T.eq(C.inBounds(3,0),false,'art padding is not native walkable space')
  T.eq(C.cell(3,0),255);T.eq(C.elevationAt(3,0),nil)
  T.eq(C._grid,C._grid,'classified array is cached by owned layout revision')
  local sets=g.data.map_tilesets;local pair=g.data.tilesets[field.def.tileset]
  local tiles=Tiles.new({primary=sets[pair.primaryKey],secondary=sets[pair.secondaryKey]},g.data.constants.gen3Layout)
  for y=0,1 do for x=0,2 do
    local raw=tiles:sourceBehavior(field:blockAt(x,y))
    T.eq(C.behavior(x,y),Behavior.fromRaw(edition,raw),'source behavior stays distinct from native numbering')
    T.eq(C.elevationAt(x,y),field:cellElevation(x,y))
    for _,dir in ipairs({'up','down','left','right'})do
      local actual,why=C.canEnter(g,x,y,{dir=dir})
      local expected,reason=Native.mayEnter(field,w.entities,w.player,x,y,dir)
      T.eq(actual,expected);T.eq(why,reason)
    end
  end end
  T.eq(C.warpAt(0,1),nil,'header-only warps on ordinary ground remain inactive')
  local bank=sets[pair.primaryKey]
  local key=bank.sourceAttributeBytes==4 and 'sourceAttributes'or'attributes'
  local originalBytes=bank[key];local offset=bank.sourceAttributeBytes*2
  bank[key]=originalBytes:sub(1,offset)..string.char(105)..originalBytes:sub(offset+2)
  local warp=assert(C.warpAt(0,1))
  T.eq(warp.destMap,f.neighborId,'active observations preserve canonical warp destinations')
  T.eq(C._warps[1024],warp)
  bank[key]=originalBytes;T.eq(C.warpAt(0,1),nil,'behavior changes retire a formerly live warp observation')
  local old=C._grid;field:setGen3Cells({{x=0,y=0,mid=1,coll=0,elev=3}})
  T.eq(C.elevationAt(0,0),3);T.check(C._grid~=old,'native terrain edits invalidate classified observations')
  T.eq(C.behavior(0,0),Behavior.fromRaw(edition,tiles:sourceBehavior(1)))
  local mid,pairId=Map.worldMidAt(3,0,def)
  local neighbor=Map.neighborList[1].def
  T.eq(pairId,neighbor.pair)
  T.eq(C.worldBehavior(3,0),C.behaviorOn(neighbor,0,1),'connected behavior follows native extent and offset')
  T.eq(C.worldBehavior(-1,-1),C.behaviorOn(def,-1,-1)or C.behaviorOn(def,0,1),
    'border observations use the current source bank')
  local actor=w.player;local x,y,elev,surf=actor.cellX,actor.cellY,actor.elevation,actor.surfing
  C.canEnter(g,0,1,{fromX=1,fromY=1,elevation=3,surfing=true,dir='left'})
  T.eq(actor.cellX,x);T.eq(actor.cellY,y);T.eq(actor.elevation,elev);T.eq(actor.surfing,surf)
  T.eq(C.canEnter(g,0/0,0),false);T.eq(C.canEnter(g,1.5,0),false)
  T.eq(C.behavior(0/0,0),nil)
  -- Observed layout edits remain detached from native collision permissions.
  local layout=Map.currentDef().midLayout
  local nativeAllowed=Native.mayEnter(field,w.entities,actor,0,1,'down')
  layout:applyOverride(0,1,0,7,0)
  T.eq(C.cell(0,1),7)
  T.eq(C.canEnter(g,0,1,{dir='down'}),nativeAllowed,'observational overrides cannot rewrite native permissions')
  T.eq(C._grid[5],7,'classified array tracks owned override revisions')
  -- A live native actor must not collide with itself when the request asks
  -- about a hypothetical origin/surf/elevation instead of its current one.
  local allowed,reason=C.canEnter(g,0,1,{fromX=1,fromY=1,elevation=6,surfing=true,dir='left'})
  local hypothetical={cellX=1,cellY=1,elevation=6,surfing=true}
  local expected,why=Native.mayEnter(field,{},hypothetical,0,1,'left')
  T.eq(allowed,expected);T.eq(reason,why)
  -- Source readers see replaced bank records, not old renderer/cached bytes.
  local original=sets[pair.primaryKey];local replacement={}
  for k,v in pairs(original)do replacement[k]=v end
  replacement.attributes=string.rep('\0',#original.attributes)
  if replacement.sourceAttributes then replacement.sourceAttributes=string.rep('\0',#replacement.sourceAttributes)end
  sets[pair.primaryKey]=replacement
  T.eq(C.behavior(0,0),Behavior.fromRaw(edition,0))
  local activeDef=g.data.maps[field.id];g.data.maps[field.id]={}
  T.eq(C.canEnter(g,0,1),false,'a world from a retired dataset cannot grant movement')
  T.eq(C.elevationAt(0,0),nil)
  g.data.maps[field.id]=activeDef
  w.player={cellX=0,cellY=0,elevation=3};w.entities={w.player}
  g.stack.states={{isTitle=true}}
  T.eq(C._mapDef,nil);T.eq(C.behavior(0,0),nil);T.eq(C.canEnter(g,0,1),false)
  C.release();Map.release();f.views:release()
end
do
 local f=require('tools.map-runtime.fixture').new('firered')
 f.world.player={cellX=0,cellY=0,elevation=6};f.world.entities={f.world.player}
 package.loaded['src.core.Game']=f.game
 local held=C._grid;C.behavior(0,0)
 local weak=setmetatable({f.map,f.game.data.map_tilesets.P},{__mode='v'})
 require('src.mods.Loader').teardown()
 f.views:release();f=nil;package.loaded['src.core.Game']=nil
 collectgarbage('collect');collectgarbage('collect')
 T.eq(weak[1],nil,'held classified cells cannot retain a native map after teardown')
 T.eq(weak[2],nil,'retired behavior readers cannot retain a native source bank')
 T.check(type(held[1])=='number','detached observations remain readable after retirement')
end
package.loaded['src.core.Game']=previous
T.finish('native field collision interface')
