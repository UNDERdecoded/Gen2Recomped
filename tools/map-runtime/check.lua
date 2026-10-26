package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local F=require('tools.map-runtime.fixture')
local M=require('src.compat.gen1.MapRuntime')
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 local f=F.new(edition)
 local runtime=M.new(f.getGame,function()return edition end)
 local native=f.map.def;local def=assert(runtime:current())
 T.eq(def.id,f.mapId);T.eq(def.nativeId,'NATIVE_A');T.eq(def.nativePair,native.tileset)
 T.eq(def.pair,f.pair);T.eq(def.midLayout.pair,f.pair)
 T.eq(def.width,3);T.eq(def.midLayout.width,4);T.eq(def.midLayout.trueWidth,3)
 T.eq(def.mapType,3);T.eq(def.environment,'ROUTE');T.eq(def.kind,'route')
 T.eq(def.connections[1].map,f.neighborId);T.eq(def.warps[1].destMap,f.neighborId)
 T.eq(native.midLayout,nil,'compatibility layout is never attached to native definition')
 T.check(def~=native);T.eq(runtime:current(),def,'owned definition identity remains stable')
 local old=def.midLayout;local initial=old:midAt(0,0)
 f.map:setGen3Cells({{x=0,y=0,mid=1,coll=0,elev=3}})
 T.check(def.midLayout~=old);T.eq(old:midAt(0,0),initial);T.eq(def.midLayout:midAt(0,0),1)
 T.check(def.midLayout._revision>old._revision,'native patches publish a newer presentation revision')
 T.eq(runtime:layout(f.mapId,native),nil,'foreign definitions are rejected')
 local dirs,list=runtime:neighbors(def);T.eq(#list,2);T.eq(dirs.east,list[1]);T.eq(list[2].offset,3)
 T.eq(list[1].def.pair,f.neighborPair);T.eq(runtime:loadedCount(),2)
 local all=assert(runtime:definitions());T.eq(all[f.mapId],def);T.eq(all[f.neighborId],list[1].def)
 def.connections[1].offset=55;T.eq(native.sourceConnections[1].offset,-1,'owned metadata edits stay local')
 local layout=def.midLayout;layout:applyOverride(0,0,2,0,0)
 T.eq(f.map:blockAt(0,0),1,'compatibility override cannot move native terrain')
 runtime:invalidate(f.mapId);T.check(def.midLayout~=layout);T.check(def.midLayout._revision>layout._revision)
 f.game.stack.states={{isTitle=true}};T.eq(runtime:current(),nil)
 f.game.stack.states={f.world};T.eq(runtime:current(),def)
 runtime:invalidate();T.eq(runtime:isOwned(def),false,'explicit dataset invalidation retires borrowed views')
 local current=assert(runtime:current());T.check(current~=def)
 local replacement={};for key,value in pairs(native)do replacement[key]=value end;replacement.weather=9
 f.game.data.maps.NATIVE_A=replacement;f.map.def=replacement
 runtime:invalidate();local replaced=assert(runtime:current())
 T.eq(replaced.weather,9,'full invalidation rebinds replaced native definitions in the same table')
 T.eq(current.midLayout,nil,'previous metadata epoch cannot borrow a replacement layout')
 current=replaced
 runtime:release();T.eq(runtime:current(),nil);T.eq(current.midLayout,nil,'retired lazy definition cannot resolve another owner')
 f.views:release()
end
-- The public entry resolves only a loaded native Game, never bootstraps it.
do
 local key='src.core.Game';local previous=package.loaded[key];package.loaded[key]=nil
 local Map=require('src.core.game3.map');Map.release()
 T.check(Map~=require('src.world.Map'),'compatibility module is a distinct interface')
 T.eq(Map.load,nil,'unimplemented simulation load is not aliased to a different contract')
 T.eq(Map.current,nil);T.eq(package.loaded[key],nil,'requiring map does not load Game')
 local f=F.new('firered');f.world.player={cellX=1,cellY=1};package.loaded[key]=f.game
 T.eq(Map.current,f.mapId);local def=assert(Map.currentDef())
 T.eq(Map.ensureMidLayout(f.game,f.mapId,f.map.def),nil,'public boundary refuses shared native writes')
 T.eq(Map.ensureMidLayout(f.game,f.mapId,def),def.midLayout)
 T.eq(#Map.neighborList,2);T.eq(Map.neighbors.east.map,f.neighborId)
 local world=Map.refreshWorld(f.game,0,0)
 T.eq(#world,1);T.eq(world[1].ox,3,'native connections use the true 3-cell extent, preserving 4-cell art padding')
 T.eq(Map.world,world);T.eq(Map._worldRoot,f.mapId)
 T.eq(Map.worldMidAt(0,0,def),def.midLayout:midAt(0,0))
 local mid,pair=Map.worldMidAt(3,0,def)
 T.eq(mid,Map.neighborList[1].def.midLayout:midAt(0,1),'first neighbour column is not hidden by source padding')
 T.eq(pair,f.neighborPair)
 T.eq(#Map.overscanSlices(),2)
 local x0,y0,x1,y1=Map.warmRect(0);T.eq(x0,-8);T.eq(y0,-5);T.eq(x1,10);T.eq(y1,7)
 T.eq(Map.loadedLayoutCount(),2)
 f.game.stack.states={{isTitle=true}};T.eq(Map.current,nil);T.eq(#Map.world,0);T.eq(#Map.neighborList,0)
 f.game.stack.states={f.world};local held=assert(Map.currentDef())
 local original=Map.currentDef
 local seams=require('src.mods.ModSeams')
 seams.run('map_lifecycle_probe',function()Map.currentDef=function(...)return original(...)end end)
 require('src.mods.Loader').teardown()
 T.eq(Map.currentDef,original,'real loader teardown restores compatibility wrappers')
 T.eq(held.midLayout,nil,'real loader teardown retires held lazy observations')
 T.check(Map.currentDef()~=held,'the same native owner creates fresh observations after teardown')
 Map.release();package.loaded[key]=nil
 local explicit=Map.refreshWorld(f.game,0,0)
 T.eq(#explicit,1,'explicit native owner does not require bootstrapping Game')
 T.eq(explicit[1].ox,3,'explicit owner keeps true grid geometry during graph traversal')
 T.eq(package.loaded[key],nil)
 Map.release();f.views:release();package.loaded[key]=previous
end
do
 local f=F.new('firered');local runtime=M.new(f.getGame,function()return 'firered'end)
 local held=assert(runtime:current());local weak=setmetatable({f.map,f.map.renderer},{__mode='v'})
 runtime:release();f.views:release();f=nil;collectgarbage('collect');collectgarbage('collect')
 T.eq(weak[1],nil,'held definition cannot retain native map after release')
 T.eq(weak[2],nil,'held definition cannot retain a native renderer')
 T.eq(held.midLayout,nil)
end
do
 local rows=require('src.compat.gen1.PairNames').firered;local aliases={}
 for i,row in ipairs(rows)do aliases[i]=row[6];row[6]=nil end
 local f=F.new('firered');local runtime=M.new(f.getGame,function()return 'firered'end)
 local def,why=runtime:current();T.eq(def,nil,'old pair metadata cannot silently publish a missing tileset alias')
 T.eq(why,'source tileset pair identity unavailable')
 runtime:release();f.views:release()
 for i,row in ipairs(rows)do row[6]=aliases[i]end
end
T.finish('native compatibility map runtime')
