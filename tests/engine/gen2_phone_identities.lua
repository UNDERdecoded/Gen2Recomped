-- Copyright (c) 2026 Roxas2712. See offered PR contribution permission.
-- Synthetic native ROM rows distinguish contact numbers from map numbers.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Ids=require('src.import.Gen2PhoneIdentities')
local Extractor=require('src.import.RomExtractorGen2')
local V=require('src.core.GameVersion');local initial=V.get()
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 local ids=Ids.forVersion(version)
 T.eq(#ids.phoneContactOrder,version=='crystal' and 38 or 37,version..' retail row bound includes holes')
 T.eq(ids.phoneContactOrder[9],'PHONE_UNUSED',version..' reserved contact hole is explicit')
 T.eq(ids.phoneContactOrder[2],'PHONE_MOM',version..' contact identity is numeric-order metadata')
 T.eq(ids.phoneContactOrder[3],'PHONE_OAK',version..' retain reference spelling without renaming native slot2')
 ids.phoneContactOrder[2]='LEAK';ids.trainerClassMembers.FALKNER[1]='LEAK'
 T.eq(Ids.forVersion(version).phoneContactOrder[2],'PHONE_MOM',version..' contact metadata detached')
 T.neq(Ids.forVersion(version).trainerClassMembers.FALKNER[1],'LEAK',version..' nested trainer metadata detached')
 local bytes={};for i=1,0x8000 do bytes[i]=0 end
 local function put(at,values)for i,v in ipairs(values)do bytes[at+i]=v end end
 -- Four rows: unused0, non-trainer1, trainer2 and a reserved unused3.
 put(0x4000+12,{0,2,9,42,7,1,0x00,0x50,2,1,0x10,0x50})
 put(0x4000+24,{12,3,5,6,1,1,0x20,0x50,4,1,0x30,0x50})
 -- Pointer slot2 names the actual imported display string; it is deliberately
 -- unrelated to the legacy PHONE_OAK compatibility identifier at index2.
 put(0x4204,{0x00,0x43});put(0x4300,{0x81,0x88,0x8A,0x84,0x7F,0x92,0x87,0x8E,0x8F,0x50})
 -- Crystal's late non-trainer record at native index37 names slot5. Earlier
 -- code read only names1..4 and silently discarded this entire native row.
 put(0x4000+37*12,{0,5,3,77,7,1,0x40,0x50,7,1,0x50,0x50})
 put(0x420a,{0x10,0x43});put(0x4310,{0x81,0x94,0x84,0x8d,0x80,0x50})
 local chunks={};for i=1,#bytes,256 do chunks[#chunks+1]=string.char(unpack(bytes,i,math.min(i+255,#bytes)))end
 local e=Extractor.new(table.concat(chunks),version,{symbols={PhoneContacts={1,0x4000},SpecialPhoneCallList={1,0x4030},NonTrainerCallerNames={1,0x4200}}})
 function e:readSourceTable()return {}end
 local queued={}
 function e:gen2QueueScript(bank,address)
  local id=string.format('S%02X_%04X',bank,address);queued[#queued+1]=id;return id
 end
 local rows,info=e:gen2PhoneContacts({})
 T.eq(info.size,4,version..' imported full native bound retains unused slots')
 T.eq(info.rowsRead,4,version..' actual imported row count is explicit')
 T.eq(rows[0],nil,version..' unused0 is not invented as a callable contact')
 T.eq(rows[3],nil,version..' reserved hole is retained by bound, not a fake contact')
 T.eq(rows[1].contactNumber,2,version..' actual non-trainer identity retained')
 T.eq(rows[1].number,42,version..' actual map number remains separate')
 T.eq(rows[1].group,9,version..' actual map group remains native')
 T.eq(rows[1].name,'BIKE SHOP',version..' native display text remains authoritative')
 T.eq(info.nonTrainerNames[2],'BIKE SHOP',version..' imported non-trainer lookup retained')
 T.eq(rows[1].call,'S01_5000',version..' callee pointer remains outgoing')
 T.eq(rows[1].callTime,7,version..' callee time remains outgoing')
 T.eq(rows[1].receive,'S01_5010',version..' caller pointer remains incoming')
 T.eq(rows[1].receiveTime,2,version..' caller time remains incoming')
 T.eq(rows[2].class,12,version..' native trainer class is numeric and unchanged')
 T.eq(rows[2].trainer,3,version..' native roster member is unchanged')
 T.eq(rows[2].contactNumber,nil,version..' trainer member is not a non-trainer contact number')
 T.eq(rows[2].number,6,version..' trainer map number is not replaced by member')
 T.eq(#queued,4,version..' both native phone directions are queued')
 local constants=e:constants()
 T.eq(constants.phoneContactOrder[2],'PHONE_MOM',version..' actual constants producer installs phone identities')
 T.eq(constants.generation,2,version..' new metadata preserves native generation')
  local empty=Extractor.new(string.rep('\0',0x8000),version,{symbols={PhoneContacts={1,0x4000},SpecialPhoneCallList={1,0x4030}}})
  local none,bounds=empty:gen2PhoneContacts({})
  T.eq(none,nil,version..' empty native book has no fake callable records')
  T.eq(bounds.size,4,version..' empty native book still reserves its complete row range')
 local buena=Extractor.new(table.concat(chunks),version,{symbols={PhoneContacts={1,0x4000},SpecialPhoneCallList={1,0x41c8},NonTrainerCallerNames={1,0x4200}}})
 local book,meta=buena:gen2PhoneContacts({scripts={},queue={}})
 T.eq(book[37] and book[37].name,'BUENA',version..' referenced name5 retains the complete native contact')
 T.eq(book[37] and book[37].contactNumber,5,version..' late non-trainer keeps its own identity')
 T.eq(book[37] and book[37].number,77,version..' late non-trainer map number remains independent')
 T.eq(meta.size,38,version..' full native row range remains reserved')
 local data=T.fixtures.fresh();data.map_scripts={phone=book,scripts={S01_5040={{'setval',41},{'end'}},S01_5050={{'setval',42},{'end'}}}}
 local C=require('src.script.Gen2Commands')
 T.eq(C.phoneName(data,37),'BUENA',version..' real native phone-name consumer can resolve the restored contact')
 local game={data=data,save={},overworld={}}
 for _,direction in ipairs({'call','receive'})do
  local rows=direction=='call' and C.phoneCallScript(data,37) or C.phoneReceiveScript(data,37)
  T.check(rows~=nil,version..' restored '..direction..' script is actually compiled')
  local runner=require('src.script.ScriptRunner').new(game,game.overworld);runner:run(rows or {})
  T.eq(runner.ctx.g2Var,direction=='call' and 41 or 42,version..' real native '..direction..' executes correct script')
  T.eq(runner:isRunning(),false,version..' native '..direction..' finishes')
 end
end
for _,version in ipairs({'red','firered','emerald','prism','polishedcrystal'})do
 T.eq(Ids.forVersion(version),nil,version..' does not receive guessed retail identities')
end
local authored={phoneContactOrder={'CUSTOM'},trainerClassOrder={'CUSTOM_CLASS'},trainerClassMembers={CUSTOM_CLASS={'ONE'}}}
local manifest={constants=authored};local mounted={}
Ids.install(mounted,manifest,'prism')
T.eq(mounted.phoneContactOrder[1],'CUSTOM','manifest explicitly describes an alternative cartridge')
authored.trainerClassMembers.CUSTOM_CLASS[1]='LEAK'
T.eq(mounted.trainerClassMembers.CUSTOM_CLASS[1],'ONE','manifest roster metadata is detached')
local original={phoneContactOrder={'NATIVE'}};Ids.install(original,manifest,'gold')
T.eq(original.phoneContactOrder[1],'NATIVE','existing authored constants remain authoritative')
local custom={trainerClassOrder={'CUSTOM'}};Ids.install(custom,nil,'gold')
T.eq(custom.trainerClassMembers,nil,'partial authored roster cannot inherit unrelated retail members')
T.eq(custom.phoneContactOrder,nil,'partial authored identity set cannot guess retail contact names')
local Importer=require('src.import.RomImporter');local marker
for i=1,100 do local name,value=debug.getupvalue(Importer.readyReport,i);if not name then break end;if name=='markerFor'then marker=value;break end end
assert(marker)
for _,version in ipairs({'gold','silver','crystal'})do
 local current=marker(version)
 T.check(current:find('gen2-phone-identities-v1:',1,true)~=nil,version..' existing native import must rebuild once')
 local old=current:gsub('gen2%-phone%-identities%-v1:','')
 local V=require('src.core.GameVersion');local previous=V.get();V.set(version)
 love.filesystem.write(V.cachePrefix(version)..'rom-cache.complete',old)
 T.eq(Importer.readyReport(version).ok,false,version..' real readiness gate rejects missing phone metadata')
 V.set(previous)
end
for _,version in ipairs({'red','firered','emerald','prism','polishedcrystal'})do
 T.check(not marker(version):find('gen2-phone-identities-v1:',1,true),version..' unrelated cache marker is unchanged')
end
V.set(initial)
T.finish('native phone/trainer identities and reserved-row import metadata')
