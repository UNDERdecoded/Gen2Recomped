io.stdout:setvbuf('no')
local root=assert(os.getenv('MAPRUNTIME_ENGINE'));package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(e)print(debug.traceback(tostring(e),2));return function()return 1 end end
function love.load()
 local J=require('src.link.Json');local X=require('src.import.RomExtractorGen3');local V=require('src.core.GameVersion')
 local Map=require('src.world.Map');local Runtime=require('src.compat.gen1.MapRuntime')
 local observe=require('tools.map-runtime.projection');local digest=require('tools.map-views.digest')
 local out=assert(os.getenv('MAPRUNTIME_OUT'));local oracle=assert(os.getenv('MAPRUNTIME_ORACLE'))
 local layouts=assert(os.getenv('MAPRUNTIME_LAYOUT_ORACLE'))
 local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
 local function same(a,b)
  if type(a)~=type(b)then return false end
  if type(a)~='table'then return a==b end
  for key,v in pairs(a)do if not same(v,b[key])then return false end end
  for key in pairs(b)do if a[key]==nil then return false end end
  return true
 end
 local inputs=J.decode(read(oracle..'/inputs.json'));local report={editions={},fullCompatibility=false,playerProfilesUsed=false,gpu=false}
 for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  V.set(edition)
  local manifest=J.decode(read(root..'/tools/rom_manifest_'..edition..'.json'))
  local raw=read(inputs[edition]);local hash=love.data.hash('sha1',raw):gsub('.',function(c)return('%02x'):format(c:byte())end)
  assert(hash==manifest.romSha1,'cartridge identity mismatch')
  local x=X.new(raw,V.info(edition),manifest)
  local generated={};x.write=function(_,name,value)generated[name]=value end
  x.tilesetSheet=function()return{}end;x.saveImage=function()end
  x:extractMapLayouts();x:extractMaps();x:extractTilesets()
  local data={maps=generated.maps,tilesets=generated.tilesets,map_tilesets=generated.map_tilesets,constants=generated.constants}
  local keys={};for key,def in pairs(data.maps)do if type(def)=='table'and def.id then keys[#keys+1]=key end end;table.sort(keys)
  local active=Map.new(data.maps[keys[1]],assert(data.tilesets[data.maps[keys[1]].tileset]))
  local game={data=data,stack={states={{isOverworld=true,map=active,neighbors={}}}}}
  local runtime=Runtime.new(function()return game end,function()return edition end)
  local expected=J.decode(read(oracle..'/'..edition..'.json'))
  local expectedLayouts=J.decode(read(layouts..'/'..edition..'.json'))
  local counts={maps=0,cells=0,metadataDifferent={},layoutDifferent={}}
  local defs=assert(runtime:definitions())
  for id,prior in pairs(expected)do
   local def,why=runtime:definition(id);assert(def,why)
   local actual=observe(def)
   if not same(actual,prior)then
    local fields={};for key,value in pairs(prior)do if not same(value,actual[key])then fields[#fields+1]={key=key,source=value,native=actual[key]}end end
    counts.metadataDifferent[#counts.metadataDifferent+1]={id=id,fields=fields}
   end
   local layout=assert(runtime:layout(id,def));assert(layout.pair==def.pair,'semantic layout pair unavailable')
   local measured=digest(layout,def.kind,def.environment,def.connections,def.warps)
   local source=assert(expectedLayouts[id]);if not same(measured,source)then counts.layoutDifferent[#counts.layoutDifferent+1]={id=id,actual=measured,source=source}end
   counts.maps=counts.maps+1;counts.cells=counts.cells+measured.cells
  end
  assert(counts.maps==#keys,'map inventories differ')
  runtime:release();report.editions[edition]=counts
  local f=assert(io.open(out..'/progress.json','w'));f:write(J.encode(report));f:close()
  print('NATIVE_MAP_RUNTIME',edition,counts.maps,counts.cells,#counts.metadataDifferent,#counts.layoutDifferent)
  assert(#counts.metadataDifferent==0 and #counts.layoutDifferent==0,'owned map runtime differs from original source pipeline')
 end
 report.status='pass';local f=assert(io.open(out..'/result.json','w'));f:write(J.encode(report));f:close()
 love.event.quit(0)
end
