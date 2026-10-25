package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
local Map=require('src.world.Map');local W=require('src.world.OverworldController')
for _,version in ipairs({'gold','silver','crystal','prism'})do
 V.set(version)
 local ts={id='TERRAIN',blockCells=2,collision={255,255,255,255,0x23,0x18,0x72,0x21,0x21,0x10,0x7A,0},walkable={0,0x18,0x23,0x10},grassTiles={0x18,0x10},waterTiles={0x21}}
 local def={id='TERRAIN_MAP',generation=2,width=1,height=1,blocks={1}}
 local w=setmetatable({map=Map.new(def,ts),player={cellX=0,cellY=0,collision=255}},{__index=W})
 T.eq(w:playerCollision(),0x23,version..' player terrain reads actual native ice class rather than a cached actor value')
 w.player.cellX=1;T.eq(w:playerCollision(),0x18,'native grass class stays a collision code')
 T.eq(w:grassAt(1,0),true,'grass query uses native map classification')
 T.eq(w:grassAt(0,0),false,'ice is not grass')
 T.eq(w:grassAt(-1,0),false,'border filler is not standable grass')
 T.eq(w:grassAt(2,0),false,'outside the actual map is not grass')
 w.player.cellX=0;w.player.cellY=1;T.eq(w:playerCollision(),0x72,'native staircase is not a Gen3 blocking bit')
 w.map:setBlock(0,0,2)
 T.eq(w:playerCollision(),0x7A,'player terrain observes actual live block patch')
 T.eq(w:grassAt(1,0),true,'grass observes actual replacement block')
 w.player.cellX=1;w.player.cellY=1;T.eq(w:playerCollision(),0,'patched ordinary floor is read immediately')
 w.player=nil;T.eq(w:playerCollision(),nil,'missing player has no fabricated collision')
 w.map=nil;T.eq(w:grassAt(0,0),false,'missing active map has no grass')
end
V.set('emerald')
local map=Map.new({id='GBA',generation=3,width=2,height=1,blocks={0,1},collisionCells={1,0}},
 {id='GBA',blockCells=1,collision={8,9},walkable={8,9},blocks={}})
local w=setmetatable({map=map,player={cellX=0,cellY=0}},{__index=W})
T.eq(w:playerCollision(),1,'other-generation actual blocking bit is retained')
w.player.cellX=1;T.eq(w:playerCollision(),0,'other-generation unblocked cell retains its native bit')
w.map=nil;T.eq(w:playerCollision(),nil,'missing map has no fabricated terrain')
V.set(original)
T.finish('live native player collision and grass queries')
