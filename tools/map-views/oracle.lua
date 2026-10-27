-- Runs only in the pinned clean public reference; supply a locally owned ROM.
package.path='./?.lua;./?/init.lua;'..package.path
local root,edition,path,sha,out=arg[1],arg[2],arg[3],arg[4],arg[5]
require('src.core.GameVersion').set(edition)
local Versions=require('src.import.gba.versions');Versions.select(sha)
local version=assert(Versions.lookup(sha))
local raw=assert(io.open(path,'rb')):read('*a')
local Rom=require('src.import.gba.rom');local rom=setmetatable({_raw=raw,size=#raw,sha1=sha},Rom)
local Tree=require('src.import.gba.map_tree');local Catalog=require('src.import.gba.map_catalog')
local Family=require('src.import.gba.family');local MB=require('src.core.game3.mb')
local Collision=require('src.core.game3.scripting.collision')
local census=assert(Tree.walk(rom,version));local order,byId=Catalog.allOrder(census)
local registered=Catalog.registerOrder(rom,version,order,byId)
local translator=MB.translator(edition)
if translator then Collision.impl().setTileBits(translator.tileBits(rom))end
local Tileset=require('src.import.gba.tileset');local Maps=require('src.import.gba.maps')
local pad=require('src.import.gba.extract_island1').padEven
local Pack=require('src.import.gba.native_pack')
local digest=assert(loadfile(root..'/tools/map-views/digest.lua'))()
local bundles,results={},{}
for _,id in ipairs(registered)do
 local spec=Versions.MAPS[id];local entry=byId[id]
 local pair=Versions.TILESET_PAIRS[spec.pair]
 if not bundles[spec.pair]then
  local function attrs(name)local set=Versions.TILESETS[name];return Tileset.loadAttributes(rom,set.attributes,set.attr_bytes)end
  bundles[spec.pair]={primaryAttr=attrs(pair.primary),secondaryAttr=attrs(pair.secondary)}
 end
 local grid=Maps.loadGrid(rom,version.layouts[spec.layout]);grid.kind,grid.environment=spec.kind,spec.environment
 local w,h=grid.width,grid.height;grid=pad(grid)
 local warps={};for _,warp in ipairs(entry.events.warps or{})do warps[warp.y*1024+warp.x]=true end
 for i,row in ipairs(grid.cells)do
  local behavior=Tileset.behaviorOf(bundles[spec.pair],row.mid)
  if translator then behavior=translator.canon(behavior)end
  local coll=Collision.fromCell(row.mid,row.coll,behavior,spec.kind)
  local x,y=(i-1)%grid.width,math.floor((i-1)/grid.width)
  row.coll=Pack.resolveLayoutColl(coll,row.coll,warps[y*1024+x])
 end
 local border=Tree.readBorderBytes(rom,entry.layout)
 grid.trueWidth,grid.trueHeight=w,h;grid.borderWidth,grid.borderHeight=entry.layout.borderWidth,entry.layout.borderHeight;grid.borderMids={}
 for i=1,#border/2 do grid.borderMids[i]=(border:byte(i*2-1)+border:byte(i*2)*256)%1024 end
 local connections={}
 for _,row in ipairs(entry.connections or{})do connections[#connections+1]={dir=row.dir,map=Catalog.mapIdFor(row.mapGroup,row.mapNum),offset=row.offset}end
 local observedWarps={}
 for _,row in ipairs(entry.events.warps or{})do
  local dest=Catalog.mapIdFor(row.mapGroup,row.mapNum)
  observedWarps[#observedWarps+1]={x=row.x,y=row.y,destMap=dest,destWarp=row.destWarp,mapGroup=not dest and row.mapGroup or nil,mapNum=not dest and row.mapNum or nil}
 end
 results[id]=digest(grid,spec.kind,spec.environment,connections,observedWarps)
end
local f=assert(io.open(out,'w'));f:write(require('src.link.Json').encode(results));f:close()
print('ORACLE_MAPS',edition,#registered)
