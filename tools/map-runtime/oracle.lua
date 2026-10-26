-- Run only in the clean pinned source reference, with own hash-verified ROM.
package.path='./?.lua;./?/init.lua;'..package.path
local root,edition,path,sha,out=arg[1],arg[2],arg[3],arg[4],arg[5]
local V=require('src.core.GameVersion');V.set(edition)
local Versions=require('src.import.gba.versions');Versions.select(sha)
local version=assert(Versions.lookup(sha))
local f=assert(io.open(path,'rb'));local raw=f:read('*a');f:close()
local rom=setmetatable({_raw=raw,size=#raw,sha1=sha},require('src.import.gba.rom'))
local Tree=require('src.import.gba.map_tree');local Catalog=require('src.import.gba.map_catalog')
local census=assert(Tree.walk(rom,version));local order,byId=Catalog.allOrder(census)
local registered=Catalog.registerOrder(rom,version,order,byId)
-- Run the real source header writer. Its binary/art writes are discarded;
-- the real Dataset then reads only the resulting in-memory source metadata.
local memory={}
local cache={write=function(_,rel,bytes)if rel:match('/header%.json$')then memory[rel]=bytes end;return true end}
assert(require('src.import.gba.map_tree_extract').run(rom,cache,{version=version}))
local connections,warps={},{}
for _,id in ipairs(registered)do
 local e=byId[id];connections[id]={};warps[id]=e.events.warps
 for _,c in ipairs(e.connections or{})do connections[id][#connections[id]+1]={dir=c.dir,map=Catalog.mapIdFor(c.mapGroup,c.mapNum),offset=c.offset}end
end
local Writer=require('src.import.LuaWriter')
memory['data/generated/gba/connections.lua']=Writer.encode(connections)
memory['data/generated/gba/warps.lua']=Writer.encode(warps)
_G.love={filesystem={read=function()return nil end}}
local Fs=require('src.import.CacheFs');Fs.readAt=function(rel)
 local prefix=V.cachePrefix();if prefix~=''and rel:sub(1,#prefix)==prefix then rel=rel:sub(#prefix+1)end
 return memory[rel]
end
local maps=require('src.core.game3.dataset').buildMaps(warps)
local observe=assert(loadfile(root..'/tools/map-runtime/projection.lua'))();local results={}
for _,id in ipairs(registered)do results[id]=observe(assert(maps[id]))end
local file=assert(io.open(out,'w'));file:write(require('src.link.Json').encode(results));file:close()
print('SOURCE_MAP_DEFINITIONS',edition,#registered)
