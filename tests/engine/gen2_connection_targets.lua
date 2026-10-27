-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native Gen1Recomp Gen2 World connections name the destination in mapId.
-- Exercise the shared planner, strip selection and actual seam controller;
-- replacing only map/renderer materialization leaves the movement owner real.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local Map = require("src.world.Map")
local W = require("src.world.OverworldController")
local Player = require("src.world.Player")
local Merge = require("src.mods.Merge")
local original = V.get()
local gameSlot, oldGame
for i=1,100 do
  local name,value=debug.getupvalue(W.crossConnection,i)
  if not name then break end
  if name=="Game" then gameSlot,oldGame=i,value;break end
end
assert(gameSlot)
local function safe(label,fn,...)
  local ok,a,b,c,d,e=pcall(fn,...)
  T.check(ok,label.." does not raise: "..tostring(a))
  if ok then return a,b,c,d,e end
end
local dirs={up="north",down="south",left="west",right="east"}
local function fixture(version,dir,kind,offset)
  V.set(version)
  local data=T.fixtures.fresh()
  local ts={id="TARGET_TILES",collision={},walkable={0},blocks={}}
  for i=1,100 do ts.collision[i]=0 end
  local from={id="TARGET_FROM",tileset=ts.id,width=3,height=3,blocks={1,2,3,4,5,6,7,8,9},connections={}}
  local dest={id="TARGET_TO",tileset=ts.id,width=3,height=3,blocks={10,11,12,13,14,15,16,17,18},connections={}}
  local edge={offset=offset}
  if kind=="native" then edge.mapId=dest.id
  elseif kind=="metadata" then edge.mapId,edge.map=dest.id,7
  elseif kind=="native-precedence" then edge.mapId,edge.map=dest.id,"UNKNOWN"
  else edge.map=dest.id end
  from.connections[dirs[dir]]=edge
  data.maps[from.id],data.maps[dest.id],data.tilesets[ts.id]=from,dest,ts
  local shift=(offset or 0)*2
  local along=math.max(0,shift)+1
  local cx,cy=along,dir=="up"and 0 or 5
  if dir=="left"or dir=="right"then cx,cy=dir=="left"and 0 or 5,along end
  local p=setmetatable({cellX=cx,cellY=cy,px=cx*16,py=cy*16,facing=dir,moving=false,progress=0,stepFrames=16},{__index=Player})
  local w=setmetatable({map=Map.new(from,ts),player=p,npcs={},entities={p},ghosts={},scriptMoves={},mapChanges=0},{__index=W})
  local game={data=data,save={onBike=false,flags={},party={}},overworld=w}
  debug.setupvalue(W.crossConnection,gameSlot,game)
  function w:setMap(id,x,y,facing)
    self.mapChanges=self.mapChanges+1
    self.map=Map.new(assert(data.maps[id],"actual destination must be registered"),ts)
    p.cellX,p.cellY,p.px,p.py,p.facing=x,y,x*16,y*16,facing
  end
  function w:followCamera()end
  local tx,ty=cx-shift,dir=="up"and 5 or 0
  if dir=="left"or dir=="right"then tx,ty=dir=="left"and 5 or 0,cy-shift end
  return w,game,from,dest,edge,tx,ty
end
for _,version in ipairs({"gold","silver","crystal","prism"})do
  for dir,compass in pairs(dirs)do
    for _,kind in ipairs({"native","metadata","native-precedence","shared"})do
      for _,offset in ipairs({-1,0,1})do
        local w,game,from,dest,edge,tx,ty=fixture(version,dir,kind,offset)
        local before=Merge.deepCopy(edge)
        local list=safe(version.." "..kind.." planner",W.computeNeighbors,game.data.maps,from.id,1)
        T.eq(list and #list,1,"native destination is resident exactly once")
        if list and list[1]then
          local row=list[1]
          T.eq(row.id,dest.id,"planner publishes actual destination identity")
          local ox,oy=offset*32,-96
          if dir=="down"then oy=96 elseif dir=="left"then ox,oy=-96,offset*32 elseif dir=="right"then ox,oy=96,offset*32 end
          T.eq(row.ox,ox,"planner keeps native strip X offset")
          T.eq(row.oy,oy,"planner keeps native strip Y offset")
        end
        local def,tiles,x,y,selected=safe("native landing",w.connectionLanding,w,dir)
        T.eq(def,dest,"landing resolves the same destination as residency")
        T.eq(tiles,game.data.tilesets[dest.tileset],"landing keeps destination collision owner")
        T.eq(x,tx,"landing X keeps block-to-cell conversion")
        T.eq(y,ty,"landing Y keeps block-to-cell conversion")
        T.eq(selected,edge,"landing retains the original connection record")
        T.eq(safe("actual native crossing",w.crossConnection,w,dir,edge),true,"same seam admits actual native interpolation")
        T.eq(w.mapChanges,1,"one map materialization per crossing")
        T.eq(w.map.id,dest.id,"actual native map owner changes")
        T.eq(w.player.targetX,tx,"native mover targets the selected destination X")
        T.eq(w.player.targetY,ty,"native mover targets the selected destination Y")
        T.eq(w.player.moving,true,"native mover owns crossing frames")
        T.eq(w.pendingSeamMusic,dest.id,"deferred music names the same loaded map")
        T.eq(edge.map,before.map,"numeric source metadata is never overwritten")
        T.eq(edge.mapId,before.mapId,"native source target is never rewritten")
        T.eq(edge.offset,before.offset,"strip offsets are never rescaled in place")
      end
    end
  end
  -- The reference treats an omitted native strip offset as zero.
  local w,game,from,dest,edge=fixture(version,"right","native",nil)
  local rows=safe("omitted offset planner",W.computeNeighbors,game.data.maps,from.id,1)
  T.eq(rows and rows[1]and rows[1].ox,96,"omitted offset retains adjacency")
  local target=safe("omitted offset landing",w.connectionLanding,w,"right")
  T.eq(target,dest,"omitted offset does not reject native landing")
  T.eq(edge.offset,nil,"default offset does not mutate source record")
  -- A missing first destination must not conceal a later usable strip.
  from.connections.east={list={{mapId="MISSING",offset=0},edge}}
  local got=safe("available later strip",w.connectionLanding,w,"right")
  T.eq(got,dest,"strip search skips unavailable destinations")
  local absent=safe("unknown planner root",W.computeNeighbors,game.data.maps,"UNKNOWN",2)
  T.eq(absent and #absent,0,"unknown root returns an empty resident set")
end
-- Shared/native map naming remains scoped: other generations keep map.
for _,version in ipairs({"red","emerald","firered","platinum"})do
  local w,game,from,dest=fixture(version,"right","shared",0)
  from.connections.east.mapId="UNRELATED_GEN2_METADATA"
  local rows=safe(version.." unchanged target",W.computeNeighbors,game.data.maps,from.id,1)
  T.eq(rows and rows[1]and rows[1].id,dest.id,"other generations keep shared destination naming")
  T.eq(safe(version.." unchanged landing",w.connectionLanding,w,"right"),dest,"other generation seam retains its destination")
  T.eq(safe(version.." unchanged crossing",w.crossConnection,w,"right",from.connections.east),true,"other generations retain native seam interpolation")
  T.eq(w.mapChanges,1,"other generations materialize one destination")
  T.eq(w.map.id,dest.id,"other generation crossing ignores unrelated Gen2 metadata")
end
debug.setupvalue(W.crossConnection,gameSlot,oldGame)
V.set(original)
T.finish("native Gen2 connection targets, residency and seam ownership")
