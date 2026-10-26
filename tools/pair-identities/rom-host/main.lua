io.stdout:setvbuf('no')
local root=assert(os.getenv('PAIRS_ENGINE'));package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(e)print(debug.traceback(tostring(e),2));return function()return 1 end end
function love.load()
 local J=require('src.link.Json');local X=require('src.import.RomExtractorGen3');local V=require('src.core.GameVersion')
 local Identity=require('src.compat.gen1.MapIdentity');local Pairs=require('src.compat.gen1.PairIdentity')
 local out=assert(os.getenv('PAIRS_OUT'));local oracle=assert(os.getenv('PAIRS_ORACLE'))
 local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
 local inputs=J.decode(read(oracle..'/inputs.json'));local report={editions={},gpu=false,fullCompatibility=false,playerProfilesUsed=false}
 for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  V.set(edition)
  local manifest=J.decode(read(root..'/tools/rom_manifest_'..edition..'.json'))
  local raw=read(inputs[edition]);local hash=love.data.hash('sha1',raw):gsub('.',function(c)return('%02x'):format(c:byte())end)
  assert(hash==manifest.romSha1,'cartridge identity mismatch')
  local x=X.new(raw,V.info(edition),manifest)
  local data={};x.write=function(_,name,value)data[name]=value end
  x.tilesetSheet=function()return{}end;x.saveImage=function()end
  x:extractMapLayouts();x:extractMaps();x:extractTilesets()
  local maps=Identity.bind(data.maps,edition);local binding=Pairs.bind(data.tilesets,data.map_tilesets,edition)
  local expected=J.decode(read(oracle..'/'..edition..'.json'));local count,seen=0,{}
  for _,row in ipairs(expected)do
   local native,def=maps:nativeId(row.id);assert(native,def)
   local descriptor,why=binding:descriptor(def.tileset);assert(descriptor,why)
   assert(descriptor.id==row.pair and descriptor.primary==row.primaryName and descriptor.secondary==row.secondaryName and descriptor.tileset==row.tileset,'semantic pair differs')
   assert(binding:nativeId(row.pair)==def.tileset,'semantic pair does not resolve exact native owner')
   local p,s=data.map_tilesets[descriptor.primaryKey],data.map_tilesets[descriptor.secondaryKey]
   assert(p.address==row.primary and s.address==row.secondary,'wrong physical source pair')
   count=count+1;seen[def.tileset]=true
  end
  local nativeMaps=0;for _,def in pairs(data.maps)do if type(def)=='table'and def.id then nativeMaps=nativeMaps+1 end end
  assert(nativeMaps==count,'map inventories differ')
  local pairCount=0;for _ in pairs(seen)do pairCount=pairCount+1 end
  binding:release();report.editions[edition]={maps=count,pairs=pairCount}
  print('NATIVE_PAIR_IDENTITIES',edition,count,pairCount)
 end
 report.status='pass';local f=assert(io.open(out..'/result.json','w'));f:write(J.encode(report));f:close()
 love.event.quit(0)
end
