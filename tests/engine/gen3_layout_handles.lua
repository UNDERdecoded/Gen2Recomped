package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local L=require('src.core.game3.layout_native');local Map=require('src.world.Map')
local V=require('src.core.GameVersion');local prior=V.get()
for _,version in ipairs{'firered','emerald'}do
 V.set(version);dofile('tests/gba_layout/consumer.lua')(T,L)
 local def={id='NATIVE',tileset='PAIR',width=2,height=1,blocks=string.char(7,48,8,64),collisionCells={0,1},elevationCells={3,4},border=string.char(1,0,2,0,3,0,4,0)}
 local m=Map.new(def,{id='PAIR',blockCells=1,blockTiles=2,collision={[8]=0,[9]=0},walkable={0}})
 local l=m:gen3Layout();T.eq(l:nativeMap(),m,'layout owns actual native Map')
 T.eq(l,m:gen3Layout(),'native layout identity is stable');T.eq(l,L.fromMap(m),'all native accessors return same layout')
 T.eq(l.cells,l.cells,'native source-cell identity is stable for preview lifetime')
 T.eq(l.cells[1].mid,7,'native source-cell projection reads actual raw base')
 T.same({l.cells[1].mid,l.cells[1].coll,l.cells[1].elev},{7,0,3},'native source projection reads all three source components')
 T.eq(l:workerPacked(),nil,'GBA packed map words are not an SVML worker source')
 T.raises(function()l.cells[1].mid=99 end,'read-only','imported source row cannot replace shared native ROM data')
 local rev=m.gridRevision;m:setBlock(0,0,21,true)
 T.same(l:cellAt(0,0),{mid=21,coll=1,elev=3},'ordinary native script writes are visible in layout')
 T.eq(l._revision,m.gridRevision,'layout revision is actual native grid revision');T.eq(l._revision,rev+1,'ordinary native script advances once')
 T.same(l.overrides[0],{mid=21,coll=1,elev=3},'ordinary script updates same override projection')
 l:setMetatiles{{x=0,y=0,coll=0,elev=15}}
 T.eq(m:blockAt(0,0),21,'layout preserves existing native artwork');T.eq(m:cellCollision(0,0),0,'actual native collision follows layout write')
 T.eq(m:cellElevation(0,0),15,'actual native elevation follows layout write');T.eq(m:isUnderBridgeCell(0,0),true,'native bridge query agrees')
 T.eq(m.blocksDirty,true,'actual native renderer is invalidated')
 l:applyOverride(-1,0,31,255,0);T.eq(m:blockAt(-1,0),31,'authored border art uses actual native Map owner')
 T.eq(m:cellCollision(-1,0),255,'authored border blocking uses actual native Map owner')
 T.eq(m:cellElevation(-1,0),0,'authored border elevation uses actual native Map owner')
 T.eq(m:inBounds(-1,0),false,'authored border cannot extend actual movement bounds')
 m:clearBlock(0,0);T.same(l:cellAt(0,0),{mid=7,coll=0,elev=3},'native cell clear restores layout too')
 m:clearBlockPatches();T.eq(next(l.overrides),nil,'native map cleanup retires projected overrides')
 T.eq(l:midAt(-1,0),2,'native full cleanup restores actual 2x2 border')
 local same=l.overrides
 local n=m:setGen3Cells{{x=0,y=0,mid=22,coll=0,elev=15},{x=1,y=0,mid=23,coll=2,elev=0}}
 T.eq(n,2,'strict native cell batch edits actual map')
 T.same(l:cellAt(0,0),{mid=22,coll=0,elev=15},'layout observes actual native batch')
 T.same(same[1],{mid=23,coll=2,elev=0},'retained observation table follows native batch')
 T.eq(l._revision,m.gridRevision,'batch revision comes from actual native owner')
 local count=m:applyGen3Layout{width=2,height=1,blocks=def.blocks,collisionCells=def.collisionCells,elevationCells=def.elevationCells}
 T.eq(count,2,'native full layout restores edited cells')
 T.same(l:cellAt(0,0),{mid=7,coll=0,elev=3},'native layout restore is observed by handle')
 T.same(l.cells[1].mid,7,'runtime changes never change native source artwork')
 m:clearBlockPatches();T.eq(next(same),nil,'native clear empties retained observation table')
 m:setCellShut(1,0,true);T.eq(l:collAt(1,0),1,'native coordinate seal is observed')
 T.eq(l.overrides[1].coll,1,'native coordinate seal updates observation')
 m:clearBlockPatches()
 local cells=l.cells;def.blocks=string.char(9,48,10,64)
 T.eq(l:midAt(0,0),9,'native source replacement is read from current source')
 T.eq(cells,l.cells,'source projection keeps identity across equal-size native source replacement')
 T.eq(cells[1].mid,9,'retained source row reads replacement bytes')
 local old=m.gridRevision;local before=l:cellAt(0,0)
 T.raises(function()l:setMetatiles{{x=0,y=0,mid=12},{x=1.5,y=0,mid=13}}end,'invalid','malformed layout batch rejected before native writes')
 T.same(l:cellAt(0,0),before,'malformed batch cannot partially mutate native map');T.eq(m.gridRevision,old,'malformed batch cannot change actual revision')
 local a=L.fromDecoded{width=1,height=1,cells={{mid=2,coll=0,elev=3}}}
 a.cells[1].mid=19;T.eq(a:midAt(0,0),19,'authored base source mutation is live')
 T.eq(a:nativeMap():blockAt(0,0),19,'authored base mutation reaches actual native owner')
 local cropped=L.fromDecoded{width=2,height=1,trueWidth=1,cells={{mid=1,coll=0,elev=3},{mid=2,coll=1,elev=4}}}
 cropped:applyOverride(1,0,30,2,15)
 T.same(cropped:cellAt(1,0),{mid=30,coll=2,elev=15},'authored padded override retains complete triple')
 T.same(cropped.overrides[1],{mid=30,coll=2,elev=15},'padded observation preserves actual override height')
 T.eq(cropped:nativeMap():inBounds(1,0),false,'padded override cannot expand native walking crop')
 local resized=L.fromDecoded{width=2,height=2,cells={{mid=1,coll=0,elev=3},{mid=2,coll=1,elev=4},{mid=3,coll=0,elev=3},{mid=4,coll=1,elev=4}}}
 resized:applyOverride(1,1,31,2,15);resized:applyOverride(2,1,32,0,3)
 resized.width=3;resized.trueWidth=3
 T.same(resized:cellAt(1,1),{mid=31,coll=2,elev=15},'authored width change preserves coordinate of native patch')
 T.same(resized:cellAt(2,1),{mid=32,coll=0,elev=3},'authored width change admits prior border override at original coordinate')
 T.eq(resized:nativeMap():blockAt(1,1),31,'native owner agrees after authored width change')
 resized.width=1;resized.trueWidth=1
 T.same(resized:cellAt(1,1),{mid=31,coll=2,elev=15},'authored width shrink retains coordinate as border override')
 T.eq(resized:nativeMap():inBounds(1,1),false,'authored width shrink updates actual native walking bounds')
 local world=setmetatable({map=m},{__index=require('src.world.OverworldController')})
 T.eq(world:replaceBlocks{25,26},true,'actual native bulk block replacement runs')
 T.eq(l:midAt(0,0),25,'layout observes actual native bulk block replacement')
 T.eq(l.overrides[0].mid,25,'native bulk replacement updates retained observation')
 local revision=m.gridRevision;T.eq(world:replaceBlocks{25,26},false,'unchanged native bulk replacement is a no-op')
 T.eq(m.gridRevision,revision,'unchanged native replacement preserves revision')
 local weak=setmetatable({}, {__mode='v'})
 do
  local ephemeral=L.fromDecoded{width=1,height=1,cells={{mid=1,coll=0,elev=3}}}
  weak[1],weak[2]=ephemeral,ephemeral:nativeMap()
 end
 collectgarbage('collect');collectgarbage('collect')
 T.eq(weak[1],nil,'retired layout is collectable on LuaJIT')
 T.eq(weak[2],nil,'retired native map is not retained by layout registry')
end
V.set(prior);T.finish('native layout handles over the actual Map grid')
