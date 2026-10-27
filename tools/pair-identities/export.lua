-- Semantic identifiers and source addresses only; no cartridge content.
-- Run from the clean pinned reference with your locally owned cartridge.
local edition,path,sha,out=arg[1],arg[2],arg[3],arg[4]
require('src.core.GameVersion').set(edition)
local Versions=require('src.import.gba.versions');Versions.select(sha)
local version=assert(Versions.lookup(sha))
local f=assert(io.open(path,'rb'));local raw=f:read('*a');f:close()
local rom=setmetatable({_raw=raw,size=#raw,sha1=sha},require('src.import.gba.rom'))
local Tree=require('src.import.gba.map_tree');local Catalog=require('src.import.gba.map_catalog')
local census=assert(Tree.walk(rom,version));local order,byId=Catalog.allOrder(census)
local registered=Catalog.registerOrder(rom,version,order,byId)
local rows={}
for _,id in ipairs(registered)do
 local e=byId[id];local spec=assert(Versions.MAPS[id]);local pair=assert(Versions.TILESET_PAIRS[spec.pair])
 local primary=assert(rom:ptrOffset(e.layout.primaryTilesetPtr));local secondary=assert(rom:ptrOffset(e.layout.secondaryTilesetPtr))
 rows[#rows+1]={id=id,primary=primary,secondary=secondary,pair=spec.pair,primaryName=pair.primary,secondaryName=pair.secondary,tileset=Versions.PAIR_TILESET[spec.pair]}
end
local file=assert(io.open(out,'w'));file:write(require('src.link.Json').encode(rows));file:close()
print('PAIR_IDENTITIES',edition,#rows)
