package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local World=require('src.world.OverworldController')
local Map=require('src.world.Map')
local Loader=require('src.world.MapLoader')
local previous=Version.get()
local gameSlot,oldGame
for i=1,100 do
  local name,value=debug.getupvalue(World.rebuildNeighbors,i)
  if not name then break end
  if name=='Game'then gameSlot,oldGame=i,value;break end
end
assert(gameSlot,'actual native rebuild must have its game owner')
local oldLoad,oldTrim=Loader.load,Loader.trim
for _,edition in ipairs({'red','yellow','gold','crystal','emerald','firered'})do
  Version.set(edition)
  local pixel=Version.isGen3()and 16 or 32
  local data=T.fixtures.fresh();data.maps={}
  local ts={id='FIX_OUT',blockCells=pixel/16,blockTiles=pixel/8,blocks={},walkable={}}
  data.tilesets={FIX_OUT=ts}
  local maps={}
  for _,id in ipairs({'ROOT','EAST','NORTH'})do
    local def={id=id,width=2,height=2,blockPx=pixel,tileset='FIX_OUT',blocks={0,0,0,0},objects={},connections={}}
    data.maps[id]=def;maps[id]=Map.new(def,ts)
  end
  data.maps.ROOT.connections.east={map='EAST',offset=-1}
  data.maps.EAST.connections.north={map='NORTH',offset=-3}
  local game={data=data,save={flags={},party={}},renderer={worldViewSize=function()return 160,144 end}}
  debug.setupvalue(World.rebuildNeighbors,gameSlot,game)
  local loads=0
  Loader.load=function(actual,id)
    T.eq(actual,data,'loader receives the actual native dataset')
    loads=loads+1;return assert(maps[id])
  end
  Loader.trim=function(keep)
    T.check(keep.ROOT and keep.EAST and keep.NORTH,'resident set protects active and connected terrain')
  end
  local world=setmetatable({map=maps.ROOT,npcs={},entities={},npcPool={},neighbors={},ghosts={}}, {__index=World})
  world:rebuildNeighbors()
  T.eq(world.maps,data.maps,edition..' exposes the actual native map registry')
  T.eq(world.tilesets,data.tilesets,edition..' exposes the actual native tileset registry')
  T.eq(#world.neighbors,2,'native BFS admits direct and farther connected terrain')
  T.eq(loads,2,'source observation adds no parallel map loads')
  local native={}
  -- The source renderer's native-neighbor index, over actual loaded Maps.
  for _,neighbor in ipairs(world.neighbors)do
    native[neighbor.id]=neighbor
    T.eq(neighbor.id,neighbor.map.id,'source ID is the loaded map identity')
    T.eq(neighbor.ox,neighbor.cx*16,'pixel/cell X offsets agree')
    T.eq(neighbor.oy,neighbor.cy*16,'pixel/cell Y offsets agree')
    T.eq(world.maps[neighbor.id],neighbor.map.def,'renderer and loader see the same definition')
    T.eq(world.tilesets[neighbor.map.def.tileset],ts,'neighbor tileset remains native')
  end
  T.eq(native.EAST.map,world.neighbors[1].map,'source neighbor index finds actual east map')
  T.eq(native.EAST.ox,2*pixel,'Gen1/2 blocks and Gen3 metatiles preserve their own width')
  T.eq(native.EAST.oy,-pixel,'negative connection offset preserves native units')
  local defs,tilesets={},{}
  for key,value in pairs(data.maps)do defs[key]=value end
  for key,value in pairs(data.tilesets)do tilesets[key]=value end
  data.maps,data.tilesets=defs,tilesets
  world:rebuildNeighbors()
  T.eq(world.maps,defs,'registry replacement retires the prior map table')
  T.eq(world.tilesets,tilesets,'registry replacement retires the prior tileset table')
end
Loader.load,Loader.trim=oldLoad,oldTrim
 debug.setupvalue(World.rebuildNeighbors,gameSlot,oldGame)
Version.set(previous)
T.finish('native connected-map publication for Gen1 through Gen3 source renderers')
