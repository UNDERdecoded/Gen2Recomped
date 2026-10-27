io.stdout:setvbuf('no')
local root=assert(os.getenv('MAPVIEWS_ENGINE'));package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(e)print(debug.traceback(tostring(e),2));return function()return 1 end end
function love.load()
 local J=require('src.link.Json');local X=require('src.import.RomExtractorGen3');local V=require('src.core.GameVersion')
 local Map=require('src.world.Map');local Views=require('src.compat.gen1.MapViews')
 local digest=require('tools.map-views.digest')
 local out=assert(os.getenv('MAPVIEWS_OUT'));local oracle=assert(os.getenv('MAPVIEWS_ORACLE'))
 local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
 local inputs=J.decode(read(oracle..'/inputs.json'));local report={editions={},fullCompatibility=false,playerProfilesUsed=false}
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
  local world={isOverworld=true,map=active,neighbors={}}
  local game={data=data,stack={states={world}}}
  local views=Views.new(function()return game end,function()return edition end)
  local expected=J.decode(read(oracle..'/'..edition..'.json'))
  local counts={maps=0,cells=0,missing={},different={}}
  for _,nativeId in ipairs(keys)do
   local view,why=views:map(nativeId)
   if not view then counts.missing[#counts.missing+1]={native=nativeId,reason=why}
   else
    local actual=digest(view.midLayout,view.kind,view.environment,view.connections,view.warps)
    local prior=expected[view.id]
    if not prior then counts.different[#counts.different+1]={id=view.id,reason='no oracle'}
    elseif actual.hashA~=prior.hashA or actual.hashB~=prior.hashB or actual.cells~=prior.cells then
     counts.different[#counts.different+1]={id=view.id,actual=actual,expected=prior}
    end
    counts.maps=counts.maps+1;counts.cells=counts.cells+actual.cells
   end
  end
  local expectedCount=0;for _ in pairs(expected)do expectedCount=expectedCount+1 end
  assert(counts.maps==expectedCount,'native and original map inventories differ')
  views:release();report.editions[edition]=counts
  local f=assert(io.open(out..'/progress.json','w'));f:write(J.encode(report));f:close()
  print('NATIVE_MAP_VIEWS',edition,counts.maps,counts.cells,#counts.missing,#counts.different)
  assert(#counts.missing==0 and #counts.different==0,'native map observations differ from original source pipeline')
 end
 report.status='pass';local f=assert(io.open(out..'/result.json','w'));f:write(J.encode(report));f:close()
 love.event.quit(0)
end
