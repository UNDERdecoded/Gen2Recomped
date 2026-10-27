package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local F=require('tools.map-views.fixture')
local Class=require('src.compat.gen1.CollisionClass')
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 local f=F.new(edition);local originalBlocks=f.map.def.blocks
 local singleton=Class.impl('rse');local previous=singleton._tileBits
 local sentinel={[0]=2};singleton.setTileBits(sentinel)
 local view,why=f.views:current();T.check(view~=nil,tostring(why));assert(view,why)
 T.eq(view.id,f.mapId);T.eq(view.nativeId,f.map.id)
 T.eq(view.midLayout.width,4,'odd width padded');T.eq(view.midLayout.trueWidth,3,'native extent retained')
 T.eq(view.midLayout.height,2)
 T.eq(view.midLayout:collAt(0,0),7,'blocking bits remain blocked after category classification')
 T.eq(view.midLayout:midAt(1,0),f.split,'secondary-bank source grid')
 T.eq(view.midLayout:collAt(3,0),255,'padding never becomes native floor')
 T.eq(view.midLayout:midAt(-1,-1),2,'negative border tiling uses actual one-by-two source dimensions')
 T.eq(#view.connections,2,'parallel connections retained');T.eq(view.connections[1].map,f.neighborId)
 T.eq(view.connections[1].offset,-1);T.eq(view.connections[2].offset,3)
 T.eq(view.warps[1].destMap,f.neighborId,'warp observation uses semantic destination')
 T.eq(singleton._tileBits,sentinel,'view classification cannot replace another owner flags')
 T.eq(f.views:current(),view,'same native revision retains owned view identity')
 collectgarbage('collect');T.eq(f.views:current(),view,'held view survives GC without losing identity')
 T.eq(f.views:isCurrent(view),true)
 local oldMid=view.midLayout:midAt(0,0)
 T.eq(f.map:setGen3Cells({{x=0,y=0,mid=1,coll=0,elev=3}}),1)
 local changed=assert(f.views:current())
 T.check(changed~=view,'native write publishes new complete view');T.eq(changed.midLayout:midAt(0,0),1)
 T.eq(changed.midLayout:collAt(0,0),0x29,'real source water flag reaches classified layout')
 T.eq(changed.midLayout:elevAt(0,0),3)
 T.eq(view.midLayout:midAt(0,0),oldMid,'previous snapshot remains unchanged')
 T.eq(f.views:isCurrent(view),false)
 changed.midLayout:applyOverride(0,0,2,0,0)
 T.eq(f.map:blockAt(0,0),1,'owned compatibility overrides never write native cells')
 T.eq(f.map.def.blocks,originalBlocks,'no shared base-grid writes')
 f.map:clearBlockPatches();T.eq(f.views:current().midLayout:midAt(0,0),oldMid,'native restore reflected')
 local neighbor=assert(f.views:map(f.neighborId))
 f.neighbor:setGen3Cells({{x=0,y=0,mid=1,coll=0,elev=3}})
 T.check(f.views:map(f.neighborId)~=neighbor,'resident neighbor revision reflected')
 f.game.stack.states={{isTitle=true}};T.eq(f.views:current(),nil,'title retires active map context')
 T.eq(f.views:isCurrent(changed),false)
 f.game.stack.states={f.world};local restored=assert(f.views:current());T.check(restored~=view)
 local data=f.game.data;f.game.data={maps=data.maps,tilesets=data.tilesets,map_tilesets=data.map_tilesets,constants=data.constants}
 T.check(f.views:current()~=restored,'new dataset owner retires snapshots')
 local activeMap=f.world.map
 f.world.map=f.neighbor
 T.eq(f.views:current().id,f.neighborId,'actual map owner switch is visible')
 f.world.map=activeMap
 f.game.data.maps.ALIAS_A=f.map.def;f.map.id='ALIAS_A'
 T.eq(f.map:setGen3Cells({{x=0,y=0,mid=1,coll=0,elev=3}}),1)
 T.eq(f.views:current().midLayout:midAt(0,0),1,'same-record alias retains live native patches')
 f.map.id='NATIVE_A';f.game.data.maps.ALIAS_A=nil;f.map:clearBlockPatches()
 local stale=f.map.def.sourceBorder;f.map.def.sourceBorder=nil
 T.eq(f.views:current(),nil,'old cache lacks proven border dimensions');f.map.def.sourceBorder=stale
 local strong=assert(f.views:current());f.views:release();T.eq(f.views:current(),nil);T.eq(f.views:isCurrent(strong),false)
 T.eq(f.map.def.blocks,originalBlocks)
 singleton.setTileBits(previous)
end
do
 local f=F.new('emerald');local V=require('src.core.GameVersion');local info=V.VERSIONS.emerald
 V.VERSIONS.emerald=nil
 local view,why=f.views:current();T.eq(view,nil,'unregistered edition has no native session')
 T.eq(why,'no native GBA session','unregistered edition fails before reading metadata')
 V.VERSIONS.emerald=info;T.check(f.views:current()~=nil,'registered session can resume')
 f.views:release()
end
-- Weak ownership: retained observations contain no map/renderer objects.
do
 local f=F.new('firered');local view=assert(f.views:current())
 local weak=setmetatable({f.map,f.map.renderer},{__mode='v'})
 f.views:release();f.map=nil;f.neighbor=nil;f.world=nil;f.game=nil;f.getGame=nil
 f=nil;collectgarbage('collect');collectgarbage('collect')
 T.eq(weak[1],nil,'snapshot does not retain native map');T.eq(weak[2],nil,'snapshot does not retain native renderer')
 T.eq(view.midLayout:midAt(0,0),0,'owned snapshot remains readable after owner retirement')
end
T.finish('native-backed compatibility map observations')
