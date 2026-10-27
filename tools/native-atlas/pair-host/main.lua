io.stdout:setvbuf('no')
local root=assert(os.getenv('ATLAS_PAIRS_ENGINE'))
local mode=assert(os.getenv('ATLAS_PAIRS_MODE'))
local code=mode=='source'and assert(os.getenv('ATLAS_PAIRS_REFERENCE'))or root
package.path=code..'/?.lua;'..code..'/?/init.lua;'..package.path
function love.errorhandler(e)print(debug.traceback(tostring(e),2));return function()return 1 end end
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local function le(n)return string.char(n%256,math.floor(n/256)%256)end
local function hash(parts)return love.data.hash('sha256',table.concat(parts)):gsub('.',function(c)return('%02x'):format(c:byte())end)end
function love.load()
 local J=require('src.link.Json');local V=require('src.core.GameVersion')
 local inputs=J.decode(read(assert(os.getenv('ATLAS_PAIRS_INPUTS'))))
 local names=assert(loadfile(root..'/src/compat/gen1/PairNames.lua'))()
 local out=assert(os.getenv('ATLAS_PAIRS_OUT'));local report={mode=mode,editions={},gpu=false,playerProfilesUsed=false,fullOriginalModAccepted=false}
 local expected=mode=='native'and J.decode(read(out..'/source.json'))or nil
 for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  V.set(edition)
  local manifest=J.decode(read(root..'/tools/rom_manifest_'..edition..'.json'))
  local raw=read(inputs[edition]);local sha=love.data.hash('sha1',raw):gsub('.',function(c)return('%02x'):format(c:byte())end)
  assert(sha==manifest.romSha1,'cartridge identity mismatch')
  local result={pairs={},count=0,metatiles=0,different={},missing={}}
  local sourceRom,version,Pack,Tileset,binding,generated
  if mode=='source'then
   local Versions=require('src.import.gba.versions');Versions.select(sha);version=assert(Versions.lookup(sha))
   sourceRom=setmetatable({_raw=raw,size=#raw,sha1=sha},require('src.import.gba.rom'))
   local catalog=require('src.import.gba.map_catalog')
   local census=assert(require('src.import.gba.map_tree').walk(sourceRom,version))
   local order,byId=catalog.allOrder(census);catalog.registerOrder(sourceRom,version,order,byId)
   Pack=require('src.import.gba.native_pack');Tileset=require('src.import.gba.tileset')
  else
   local x=require('src.import.RomExtractorGen3').new(raw,V.info(edition),manifest)
   generated={};x.write=function(_,key,value)generated[key]=value end
   x.tilesetSheet=function()return{}end;x.saveImage=function()end
   x:extractMapLayouts();x:extractMaps();x:extractTilesets()
   binding=require('src.compat.gen1.PairIdentity').bind(generated.tilesets,generated.map_tilesets,edition)
  end
  for _,row in ipairs(names[edition])do
   local name=row[3];local mids,indices,rgba,width,model
   if mode=='source'then
    local bundle=assert(Tileset.loadPair(sourceRom,version,name))
    mids=Pack.fullMidsForPair(bundle)
    local under,over=Pack.buildLayeredIdx(bundle,mids)
    indices={Pack.encodeIdx(under),Pack.encodeIdx(over)}
    local colors=Pack.palsToRgb8(bundle.mapPals)
    local u,w=Pack.bakeRgba(under,colors);local o=Pack.bakeRgba(over,colors,{transparentZero=true})
    rgba,width={u,o},w
   else
    local descriptor=assert(binding:descriptor(name));local banks=generated.map_tilesets
    model=require('src.compat.gen1.AtlasPixels').new({primary=banks[descriptor.primaryKey],secondary=banks[descriptor.secondaryKey]},generated.constants.gen3Layout)
    mids=assert(expected.editions[edition].pairs[name]).mids
   end
   local chunks={{},{},{},{}}
   for slot,mid in ipairs(mids)do
    if model and model.midToSlot[mid]==nil then result.missing[#result.missing+1]={pair=name,mid=mid}
    else
     local i=slot-1;local u,o,ru,ro
     if model then
      local s=model.midToSlot[mid];u,o=model.indexed[s][1],model.indexed[s][2];ru,ro=model.under[s],model.over[s]
     else
      local start=12+#mids*2+i*256+1
      u,o=indices[1]:sub(start,start+255),indices[2]:sub(start,start+255)
      local rowsU,rowsO={},{}
      for y=0,15 do
       local at=((math.floor(i/16)*16+y)*width+i%16*16)*4+1
       rowsU[#rowsU+1]=rgba[1]:sub(at,at+63);rowsO[#rowsO+1]=rgba[2]:sub(at,at+63)
      end
      ru,ro=table.concat(rowsU),table.concat(rowsO)
     end
     for n,value in ipairs({u,o,ru,ro})do chunks[n][#chunks[n]+1]=le(mid)..value end
    end
   end
   local current={mids=mids,underIdx=hash(chunks[1]),overIdx=hash(chunks[2]),underRgba=hash(chunks[3]),overRgba=hash(chunks[4])}
   result.pairs[name]=current;result.count=result.count+1;result.metatiles=result.metatiles+#mids
   if model then
    local prior=expected.editions[edition].pairs[name]
    for _,key in ipairs({'underIdx','overIdx','underRgba','overRgba'})do
     if prior[key]~=current[key]then result.different[#result.different+1]={pair=name,field=key,source=prior[key],native=current[key]}end
    end
   end
   if result.count%10==0 then print('ATLAS_PAIR_PROGRESS',mode,edition,result.count,#result.different,#result.missing)end
   collectgarbage('step',512)
  end
  if binding then binding:release()end
  report.editions[edition]=result
  local file=assert(io.open(out..'/'..mode..'.json','w'));file:write(J.encode(report));file:close()
  print('ATLAS_PAIR_EDITION',mode,edition,result.count,result.metatiles,#result.different,#result.missing)
  assert(#result.different==0 and#result.missing==0,'native atlas pixels differ from source cartridge projection')
 end
 report.status='pass';local file=assert(io.open(out..'/'..mode..'.json','w'));file:write(J.encode(report));file:close()
 love.event.quit(0)
end
