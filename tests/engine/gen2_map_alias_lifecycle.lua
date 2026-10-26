package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local original=Version.get();Version.set('crystal')
local Names=require('src.core.Gen2MapNames');local Merge=require('src.mods.Merge')
local TileRenderer=require('src.render.TileRenderer');local originalNew=TileRenderer.new
local built,released=0,0
-- Only GPU resource allocation is replaced; native Map construction, cache
-- resolution, eviction, aliases and neighbor traversal all execute unchanged.
TileRenderer.new=function()built=built+1;return {release=function()released=released+1 end}end
local Loader=require('src.world.MapLoader');Loader.invalidateAll()
local data=T.fixtures.fresh();local rawId,publicId='PLAYERS_HOUSE1_F','PLAYERS_HOUSE_1F'
local raw={id=rawId,width=2,height=2,tileset='FIX_OUT',blocks={0,0,0,0},connections={}}
local alias=Merge.deepCopy(raw);alias.id=publicId;alias.sourceId=rawId
data.maps={[rawId]=raw,[publicId]=alias};Names.publish(data)
local public=Loader.load(data,publicId)
T.eq(public.id,publicId,'actual native Map has public identity')
T.eq(public.def,data.maps[rawId],'actual native Map uses shared registry record')
T.eq(Loader.cached(rawId),public,'unrequested native alias finds existing public resident')
T.eq(Loader.load(data,rawId),public,'raw request reuses same Map and GPU owner')
T.eq(built,1,'aliases allocate one renderer')
T.eq(Loader.invalidate(rawId),true,'native alias invalidates public resident')
T.eq(Loader.cached(publicId),nil,'public alias is no longer cached')
T.eq(released,0,'invalidation preserves renderer still held by live world')
local rebuilt=Loader.load(data,rawId)
T.check(rebuilt~=public,'rebuild creates one fresh Map')
T.eq(Loader.load(data,publicId),rebuilt,'other alias sees rebuilt Map')
T.eq(Loader.evict(publicId),true,'public eviction removes physical resident')
T.eq(Loader.cached(rawId),nil,'native alias has no stale resident after eviction')
T.eq(released,1,'eviction releases shared GPU owner once')
T.eq(Loader.evict(rawId),false,'second alias cannot double-release')
-- A route cycle must not return the starting map under its native spelling.
local W=require('src.world.OverworldController')
local route='ROUTE29';local routeAlias='ROUTE_29'
local r={id=route,width=3,height=2,tileset='FIX_OUT',blocks={},connections={west={map=rawId,offset=0}}}
local ra=Merge.deepCopy(r);ra.id=routeAlias;ra.sourceId=route
raw.connections.east={map=route,offset=0}
data.maps[route],data.maps[routeAlias]=r,ra
-- A new dataset publication includes both families; in-place authored additions
-- are intentionally not inferred by the post-mod reconciliation path.
data._gen2MapNames=nil;Names.publish(data)
local neighbors=W.computeNeighbors(data.maps,publicId,4)
T.eq(#neighbors,1,'native/public connection cycle visits each physical map once')
T.eq(neighbors[1].id,routeAlias,'neighbor exposes actual public identity')
T.eq(neighbors[1].ox,64,'connection placement is unchanged')
-- Fill beyond the resident cap, protecting the home via its native name.
Loader.invalidateAll();public=Loader.load(data,publicId)
for n=1,35 do
 local id='OTHER_'..n
 data.maps[id]={id=id,width=1,height=1,tileset='FIX_OUT',blocks={0}}
 Loader.load(data,id)
end
Loader.trim({[rawId]=true})
T.eq(Loader.cached(publicId),public,'native alias protection keeps live public Map resident')
Loader.invalidateAll();T.eq(Loader.cached(rawId),nil,'complete reset clears alias routing and residents')
local ok,err=pcall(Loader.load,data,nil)
T.eq(ok,false,'missing map ID still refuses to build')
T.check(tostring(err):find('unknown map: nil',1,true)~=nil,'native missing-map diagnostic preserved')
Version.set('red')
local legacyRaw=Merge.deepCopy(raw);legacyRaw.id=rawId;legacyRaw.sourceId=nil
local legacyPublic=Merge.deepCopy(legacyRaw);legacyPublic.id=publicId;legacyPublic.sourceId=rawId
data.maps={[rawId]=legacyRaw,[publicId]=legacyPublic}
local before=built
T.check(Loader.load(data,rawId)~=Loader.load(data,publicId),'other generations retain separate authored records')
T.eq(built-before,2,'other-generation cache address space unchanged')
Loader.invalidateAll()
TileRenderer.new=originalNew;Version.set(original)
T.finish('Gen2 physical map cache, lifecycle and connected-map traversal')
