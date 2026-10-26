package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local initial=V.get()
local E=require('src.import.RomExtractorGen2');local Writer=require('src.import.LuaWriter')
local Service=require('src.world.Gen2PhoneService');local Calls=require('src.script.Gen2Commands')
local Importer=require('src.import.RomImporter')
local markerFor
for i=1,100 do local n,v=debug.getupvalue(Importer.readyReport,i);if not n then break end;if n=='markerFor'then markerFor=v;break end end
assert(markerFor)
local function extractor(version,palette,compact)
 local raw=string.rep('\0',0x8000)
 local function put(at,v)raw=raw:sub(1,at)..string.char(v)..raw:sub(at+2)end
 put(0x4000,2);put(0x4001,0x40)
 local header=compact and {1,2,0,0x50,1,1,palette}or{1,1,2,0,0x50,1,1,palette,0}
 for i,v in ipairs(header)do put(0x4001+i,v)end
 local layout=compact and {mapHeaderBytes=7,mapHeaderAttrAt=2,mapHeaderTilesetAt=0,mapHeaderEnvAt=1,mapHeaderLandmarkAt=4,mapHeaderMusicAt=5,mapHeaderPaletteAt=6,mapHeaderFishAt=-1,mapAttributesBank=2}or{}
 return E.new(raw,version,{symbols={MapGroupPointers={1,0x4000},Native_MapAttributes={compact and 2 or 1,0x5000}},layout=layout})
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 for raw=0,255 do
  local e=extractor(version,raw);local _,labels=e:gen2MapIndex();local header=assert(labels.Native)
  T.eq(header.palette,raw%16,'native header retains the unchanged palette nibble')
  T.eq(header.paletteBits,raw,'native header retains the complete real byte')
  T.eq(header.phoneService,raw<16,'native header decodes the actual no-service nibble')
  T.eq(Service.available({mapPalette=header.palette,mapPaletteBits=header.paletteBits,phoneService=header.phoneService}),raw<16,'runtime consumes the native imported no-service verdict')
 end
 for _,raw in ipairs({1,0x11,0xF4})do
  local e=extractor(version,raw);local maps={NATIVE={id='NATIVE',label='Native',width=1,height=1,warps={}}};local encoded
  -- Input table/file output are IO seams. Header lookup, map lowering and
  -- Lua serialization are the actual importer, including false booleans.
  function e:readSourceTable(name)return name=='maps'and maps or{}end
  function e:write(name,value)if name=='maps'then encoded=Writer.encode(value)end end
  e:extractMapsFromRom();local decoded=assert(loadstring(assert(encoded)))().NATIVE
  T.eq(decoded.mapPalette,raw%16,'full map lowering preserves the palette rule')
  T.eq(decoded.mapPaletteBits,raw,'full map lowering retains header bits')
  T.eq(decoded.phoneService,raw<16,'serialization does not lose an explicit no-service false')
 end
 local marker=markerFor(version)
 T.check(marker:find('gen2%-field%-encounters%-v9:')~=nil,'stock Gen2 cache requires phone-header reimport')
 love.filesystem.write(V.cachePrefix(version)..'rom-cache.complete',marker:gsub('gen2%-field%-encounters%-v9:','gen2-field-encounters-v8:'))
 local report=Importer.readyReport(version)
 T.eq(report.ok,false,'actual readiness gate rejects the old stock cache')
 T.check(report.why:find('another version',1,true)~=nil,'old cache is rejected for its actual format before missing-file checks')
end
local e=extractor('polishedcrystal',0x34,true);local _,labels=e:gen2MapIndex()
T.eq(labels.Native.palette,4,'compact manifest layout retains native dark palette')
T.eq(labels.Native.paletteBits,0x34,'compact manifest layout retains its complete palette byte')
T.eq(labels.Native.phoneService,false,'compact manifest layout reads its actual palette offset')
for _,version in ipairs({'red','blue','yellow','firered','emerald','prism','polishedcrystal'})do
 T.check(not markerFor(version):find('gen2%-field%-encounters%-v9:'),version..' cache marker is not given the stock Gen2 bump')
end
T.eq(Service.available({mapPalette=0,mapPaletteBits=0,phoneService=false}),false,'authored explicit no-service survives zero raw bits')
T.eq(Service.available({mapPalette=1,mapPaletteBits=0xF1,phoneService=true}),true,'explicit authored service override remains authoritative')
T.eq(Service.available({mapPalette=0x11}),false,'legacy authored complete palette byte keeps its service rule')
T.eq(Service.available({mapPalette=1}),true,'older cache without retained bits keeps its original rule until reimport')
T.eq(Service.available(nil),false,'missing native map cannot invent telephone service')
-- Actual incoming-call producer with its native receive program. RNG is
-- controlled to reach the service gate and select the sole eligible caller.
V.set('crystal');local oldRandom=math.random
math.random=function(a,b)if b then return a else return 1 end end
local data={map_scripts={source='RomExtractorGen2',scripts={RECEIVE={{'setval',44},{'end'}}},phone={[7]={receive='RECEIVE',receiveTime=2,group=2,number=1}}}}
local function save()return{g2LastCallMinute=0,g2Phone={[7]=true}}end
local id,rows=Calls.rollIncomingCall(data,save(),{group=1,number=1,mapPalette=1,phoneService=true},'DAY',30,false)
T.eq(id,7,'positive control: actual native caller is eligible with service')
T.check(type(rows)=='table'and #rows>0,'actual native receive program is compiled')
local game={data=data,save={}};local runner=require('src.script.ScriptRunner').new(game,{})
runner:run(rows);T.eq(runner.ctx.g2Var,44,'actual phone program really executes')
id=Calls.rollIncomingCall(data,save(),{group=1,number=1,mapPalette=1,mapPaletteBits=0x11,phoneService=false},'DAY',30,false)
T.eq(id,nil,'actual incoming-call producer respects imported no-service false')
math.random=oldRandom;V.set(initial)
T.finish('native Gen2 map phone-service import and consumption')
