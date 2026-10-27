-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local old=V.get()
local E=require('src.import.RomExtractorGen2');local Importer=require('src.import.RomImporter')
local markerFor
for i=1,100 do local name,value=debug.getupvalue(Importer.readyReport,i);if name=='markerFor'then markerFor=value;break end;if not name then break end end
assert(markerFor)
local function fixture(version,edit)
 local raw=string.rep('\0',0x8000)
 local function put(at,bytes)raw=raw:sub(1,at)..bytes..raw:sub(at+#bytes+1)end
 local symbols={MomItems_1={1,0x4000},['MomItems_1.End']={1,0x4010},MomItems_2={1,0x4010},['MomItems_2.End']={1,0x4028},
  ['CheckBalance_MomItem2.check_have_2300']={1,0x4100},hMoneyTemp={0,0xff80},
  ['Mom_GetScriptPointer.ItemScript']={1,0x4200},['Mom_GetScriptPointer.DollScript']={1,0x4201},
  PhoneContacts={1,0x4400},SpecialPhoneCallList={1,0x4418},NonTrainerCallerNames={1,0x4500},
  GotMoneyForWinningText={1,0x4300},SentSomeToMomText={1,0x4301},SentHalfToMomText={1,0x4302},SentAllToMomText={1,0x4303}}
 put(0x4000,string.char(0,0,0,0,0,3,1,17,0,0,0,0,0,5,1,18,
  0,0,100,0,0,20,1,17,0,0,200,0,0,70,2,14,0,1,244,0,0,30,1,18))
 put(0x4100,string.char(0x21,0x80,0xff,0x36,0,0x23,0x36,0,0x23,0x36,17))
 put(0x4200,string.char(0x91,0x91))
 put(0x440c,string.char(0,1));put(0x4502,string.char(0x10,0x45));put(0x4510,string.char(128,0x50))
 if edit then edit(symbols,put)end
 local e=E.new(raw,version,{symbols=symbols});e._gen2ScriptTexts={}
 function e:readSourceTable(key)assert(key=='charmap');return{['128']='Q'}end
 return e
end
local function pool()return{scripts={},queue={},movements={},instructions=0,desyncs=0,failures=0}end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version);local e=fixture(version);local q=pool();local rows=e:gen2MomShopping(q)
 T.eq(rows.complete,true,version..' actual Mom importer accepts bounded native tables')
 local phone=e:gen2PhoneContacts(nil)
 T.eq(phone[1].contactNumber,1,version..' actual non-trainer contact identity survives localized name extraction')
 T.eq(phone[1].class,0,version..' actual imported Mom contact retains native non-trainer class')
 T.eq(#rows.random,2,version..' random count comes from its end symbol')
 T.eq(#rows.ladder,3,version..' ladder count comes from its end symbol')
 T.eq(rows.ladder[3].trigger,500,version..' money trigger is a big-endian triple')
 T.eq(rows.ladder[2].kind,2,version..' kind distinguishes real DECO byte from native item')
 T.eq(rows.ladder[2].item,14,version..' row retains actual byte rather than a guessed species')
 T.eq(rows.step,17,version..' random threshold is read from actual instructions, not a retail literal')
 T.eq(#q.queue,2,version..' both original phone scripts enter native decode queue')
 T.check(e._gen2ScriptTexts[rows.rewardTexts[1]]~=nil,version..' native reward prose reaches shared text importer')
 e:gen2MomShopping(q);T.eq(#q.queue,2,version..' repeated import queues each script once')
 for _,job in ipairs(q.queue)do e:gen2DecodeScript(job[1],job[2],job[3],q)end
 T.eq(q.desyncs,0,version..' native queued scripts decode without desync')
 T.check(markerFor(version):find('gen2%-mom%-shopping%-native%-v1:')~=nil,version..' new cache requires purchase data')
 for _,edit in ipairs({
  function(s)s.MomItems_1=nil end,
  function(s)s['MomItems_2.End']=nil end,
  function(s)s['MomItems_1.End'][2]=0x4011 end,
  function(s)s['MomItems_1.End'][1]=2 end,
  function(s)s['MomItems_2.End'][2]=0x400f end,
  function(s,put)put(0x4000,string.char(255,255,255))end,
  function(s,put)put(0x4003,string.char(255,255,255))end,
  function(s,put)put(0x4006,string.char(3))end,
  function(s,put)put(0x4007,string.char(0))end,
  function(s,put)put(0x4104,string.char(0))put(0x4107,string.char(0))put(0x410a,string.char(0))end,
  function(s)s.hMoneyTemp[2]=0xff81 end,
  function(s)s['CheckBalance_MomItem2.check_have_2300']=nil end,
  function(s)s['Mom_GetScriptPointer.DollScript']=nil end,
  function(s)s['Mom_GetScriptPointer.ItemScript'][2]=0x100 end,
 })do
  local bad=fixture(version,edit);local q=pool();local result=bad:gen2MomShopping(q)
  T.eq(result.complete,false,version..' malformed or incomplete input cannot claim a native purchase binding')
  T.eq(result.random,nil,version..' malformed binding publishes no partial retail table')
  T.eq(#q.queue,0,version..' invalid binding does not partially mutate script queue')
 end
end
for _,version in ipairs({'red','emerald','prism','polishedcrystal'})do
 local q=pool();T.eq(fixture(version):gen2MomShopping(q),nil,version..' unreviewed layout has no inferred retail shopping')
 T.eq(#q.queue,0,version..' unrelated script queue stays unchanged')
 T.check(not markerFor(version):find('gen2%-mom%-shopping%-native%-v1:'),version..' unrelated cache remains unchanged')
end
local Service=require('src.world.Gen2PhoneService');local Writer=require('src.import.LuaWriter')
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
end
V.set(old);T.finish('native Mom table boundaries, threshold instruction operands, script queues and cache revision')
