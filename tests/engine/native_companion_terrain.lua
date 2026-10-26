-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local C=require('src.core.game3.collision')
local E=require('src.core.game3.encounters')
local Map=require('src.core.game3.map')
local Ledge=require('src.world.Ledge')
local NativeMap=require('src.world.Map')
local previous=package.loaded['src.core.Game']
T.eq(previous,nil,'imports do not create a game')
T.eq(E.ensureLoaded(),false);T.eq(E.tableFor('unknown'),nil);T.eq(E.terrainAt(0,0),nil)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  local f=require('tools.map-runtime.fixture').new(edition)
  local g,w,m=f.game,f.world,f.map
  w.player={cellX=0,cellY=0,elevation=6};w.entities={w.player}
  g.save={player={},flags={},gen3Vars={}}
  package.loaded['src.core.Game']=g
  local def=assert(Map.currentDef())
  for _,from in ipairs{0,3,6,15}do for _,to in ipairs{0,1,3,6,15}do
    m.elevationPatch[1]=from;m.elevationPatch[2]=to;m:noteGridChange()
    local first,second=C.nextElevation(def,6,1,0,0,0)
    local keep=from==15 or to==15
    T.eq(first,keep and 6 or to,'height follows stairs and bridge transitions')
    local expected
    if not keep and to~=0 then expected=to end
    T.eq(second,expected,'secondary sprite elevation omits zero and bridge markers')
    T.eq(select('#',C.nextElevation(def,6,1,0,0,0)),2,'source query keeps both return slots')
    T.eq(m:elevationAfter(6,1,0,0,0),first,'native mover shares the transition')
    T.eq(select('#',m:elevationAfter(6,1,0,0,0)),1,'native method keeps its return arity')
  end end
  m.elevationPatch[2]=3;m:noteGridChange()
  T.eq(C.nextElevation(def,6,1,0),3,'an omitted previous cell still accepts the destination height')
  T.eq(C.nextElevation({},6,1,0,0,0),6,'foreign map is not admitted')
  T.eq(C.nextElevation(def,6,0/0,0,0,0),6)
  local directions={'right','left','up','down','up','up','down','down'}
  m.tileset.collision={};m.def.behaviorCells=nil
  local W=require('src.world.OverworldController')
  local gameSlot,oldGame
  for i=1,100 do
    local name,value=debug.getupvalue(W.checkLedgeHop,i)
    if name=='Game'then gameSlot,oldGame=i,value;break end
  end
  assert(gameSlot);debug.setupvalue(W.checkLedgeHop,gameSlot,g)
  local call
  w.startLedgeHop=function(_,...)call={n=select('#',...),...};return true end
  w.gen2LedgeAllows=function()return false end
  for n=1,8 do
    for _,dir in ipairs{'up','down','left','right'}do
      -- Center is (1,0); only horizontal hops fit this tiny real map.
      m.tileset.collision[m:blockAt(1,0)+1]=0x37+n
      local originX=dir=='left'and 2 or 0
      local lx,ly=C.ledgeLanding(g,originX,0,dir)
      local matching=(dir=='right'or dir=='left')and directions[n]==dir
      T.eq(lx,matching and (dir=='right'and 2 or 0)or nil,'ledge facing and landing bounds')
      T.eq(ly,matching and 0 or nil)
      w.player.cellX,w.player.cellY=originX,0
      call=nil
      T.eq(W.checkLedgeHop(w,dir),matching==true,'actual native input dispatch keeps its hop decision')
      if matching then
        T.eq(call[1],dir);T.eq(call[2],1);T.eq(call[3],0)
        T.eq(call.n,3,'ordinary native hop callback preserves its argument count')
      else T.eq(call,nil)end
    end
  end
  debug.setupvalue(W.checkLedgeHop,gameSlot,oldGame)
  m.tileset.ledgeBehaviours={[0x38]='west'}
  m.tileset.collision[m:blockAt(1,0)+1]=0x38
  T.eq(C.ledgeLanding(g,0,0,'right'),nil,'native dataset direction override wins')
  T.eq(C.ledgeLanding(g,2,0,'left'),0)
  T.eq(C.ledgeLanding(g,0,0,'bad'),nil)
  T.eq(C.ledgeLanding(g,0/0,0,'right'),nil)
  T.eq(C.ledgeLanding(g,1,0,'right'),nil,'never returns an off-map landing')
  -- Pure source observations include current native patches and grass differs
  -- from cave/desert encounter terrain. They do not execute movement hooks.
  m.tileset.ledgeBehaviours=nil
  m.grassTiles={[0]=true};m.encounterTiles={[0]=true,[1]=true}
  m.collisionPatch={};m.elevationPatch={}
  for y=0,1 do for x=0,2 do
    T.eq(C.isGrass(x,y),m:isGrassCell(x,y))
    local water=m:isWaterCell(x,y)
    local expected=water and 'water'or m:isEncounterCell(x,y)and 'land'or nil
    T.eq(E.terrainAt(x,y),expected)
  end end
  T.eq(C.isGrass(3,0),false);T.eq(E.terrainAt(3,0),nil)
  T.eq(E.terrainAt(math.huge,0),nil);T.eq(E.terrainAt(1.5,0),nil)
  m.tileset.collision[1],m.tileset.collision[2],m.tileset.collision[3]=2,3,0x15
  m.grassTiles={[2]=true};m.encounterTiles={[2]=true,[3]=true}
  m:setGen3Cells({{x=0,y=0,mid=0,coll=0,elev=3},{x=1,y=0,mid=1,coll=0,elev=3},
    {x=2,y=0,mid=2,coll=0,elev=1}})
  T.eq(C.isGrass(0,0),true);T.eq(C.isGrass(1,0),false)
  T.eq(E.terrainAt(0,0),'land');T.eq(E.terrainAt(1,0),'land','caves need encounters without grass cover')
  T.eq(E.terrainAt(2,0),'water')
  m:setGen3Cells({{x=0,y=0,coll=1}})
  T.eq(E.terrainAt(0,0),nil,'blocked grass is not encounter ground')
  m.def.mapType='UNDERWATER';m.tileset.collision[1]=0x2a
  m:setGen3Cells({{x=0,y=0,coll=0}})
  T.eq(E.terrainAt(0,0),'water','seaweed uses native underwater rules, even without surfing')
  m.tileset.collision[1]=0
  T.eq(E.terrainAt(0,0),nil,'bare sea floor has no encounter terrain')
  m.def.mapType='ROUTE'
  g.data.pokemon={COMMON={index=1},SPARSE={index=277,dex=252}}
  g.data.constants.speciesOrder={[1]='COMMON',[277]='SPARSE'}
  local base={grass={rate=21,slots={{species='SPARSE',min=2,max=9}}},
    water={rate=15,slots={{species='COMMON',level=12}}},
    rock={rate=10,slots={{species='COMMON',min=3,max=4}}},
    fish={rate=25,slots={{species='SPARSE',min=5,max=6}}}}
  local alternate={grass={rate=9,slots={{species='COMMON',min=7,max=8}}}}
  base.alternates={alternate}
  g.data.encounters={NATIVE_A=base}
  T.eq(E.ensureLoaded(),true)
  local view=assert(E.tableFor(f.mapId))
  T.eq(view.land.slots[1].species,277,'species uses cartridge slot, never National Dex')
  T.eq(view.land.slots[1].minLevel,2);T.eq(view.land.slots[1].maxLevel,9)
  T.eq(view.water.slots[1].level,12);T.eq(view.rocks.slots[1].minLevel,3)
  T.eq(view.fishing.slots[1].species,277)
  T.eq(E.tableFor('NATIVE_A').land.rate,21,'native map names resolve to the same owned map')
  T.eq(E.tableFor(m.def.group..':'..m.def.number).land.rate,21,'ROM map slot aliases resolve')
  T.eq(E.tableFor('unknown'),nil)
  view.land.slots[1].species=1;view.land.rate=0
  T.eq(base.grass.slots[1].species,'SPARSE');T.eq(base.grass.rate,21)
  local variable=({firered=0x4024,leafgreen=0x4024,emerald=0x403e})[edition]
  if variable then
    g.save.gen3Vars[variable]=1
    T.eq(E.tableFor(f.mapId).land.rate,9,'live script state selects alternate header')
    T.eq(require('src.world.Encounter').forMap(g.data,m.def,m.id,nil,g.save),alternate,
      'native wild encounters use the same effective table')
    for _,invalid in ipairs{-1,2,65535,0/0,math.huge,1.5}do
      g.save.gen3Vars[variable]=invalid
      T.eq(E.tableFor(f.mapId).land.rate,21,'invalid alternate resets to base')
    end
    g.save.gen3Vars[variable]=0
  end
  local oldRandom=love.math.random
  love.math.random=function()error('observation consumed native RNG')end
  T.check(pcall(function()E.ensureLoaded();E.tableFor(f.mapId);E.terrainAt(0,0)end))
  love.math.random=oldRandom
  base.grass.slots[1].species='MISSING'
  local missing,why=E.tableFor(f.mapId)
  T.eq(missing,nil);T.check(why and why:find('cartridge index',1,true)~=nil)
  g.data.encounters={NATIVE_A={grass={rate=3,slots={{species='COMMON',min=1,max=1}}}}}
  T.eq(E.tableFor(f.mapId).land.rate,3,'native table replacement is observed immediately')
  local raw=g.data.maps.NATIVE_A;g.data.maps.NATIVE_A={}
  T.eq(E.tableFor(f.mapId),nil,'retired map identity cannot expose old encounters')
  T.eq(C.nextElevation(def,6,1,0,0,0),6)
  g.data.maps.NATIVE_A=raw
  g.stack.states={{isTitle=true}}
  T.eq(C.isGrass(0,0),false);T.eq(E.terrainAt(0,0),nil)
  C.release();Map.release();f.views:release()
end
-- The native classifier still preserves pair rules, explicit overrides and
-- the later-edition Distortion World and BW behavior spaces.
do
  local map={def={},tileset={},inBounds=function()return true end,cellBehaviour=function()return 0x5a end}
  T.eq(Ledge.approach(map,{},0,0,'right'),false,'older pair rules retain native fallback')
  map.def.generation=4;map.tileset.ledgeBehaviours={[0x5a]='east'}
  local handled,x,y,distance,silent=Ledge.approach(map,{},0,0,'right')
  T.eq(handled,true);T.eq(x,1);T.eq(y,0);T.eq(distance,3);T.eq(silent,true)
  map.def.gen5=true;map.cellBehaviour=function()return 0x75 end
  local _,bx,by=Ledge.approach(map,{},0,0,'down')
  T.eq(bx,0);T.eq(by,1,'BW rules take precedence over imported stand-in tileset')
end
package.loaded['src.core.Game']=previous
T.finish('native companion terrain and encounter observations')
