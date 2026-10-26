-- Copyright (c) 2026 Roxas2712. See the PR contribution permission.
-- Synthetic ROM only: event metadata must not become NPC bytecode.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Extractor=require('src.import.RomExtractorGen2')
local Ops=require('src.import.Gen2ScriptOps')
for _,version in ipairs({'gold','silver','crystal'})do
  local codes={}
  for i,row in ipairs(Ops.commandsFor(version))do codes[row[1]]=i-1 end
  local bytes={};for i=1,0x8000 do bytes[i]=0 end
  local function put(address,values)
    for i,v in ipairs(values)do bytes[address+i]=v end
  end
  -- ROM0 map attributes, separate scene table in bank 1, then event table.
  put(0x0206,{1,0x00,0x40,0x00,0x50})
  put(0x4000,{1,0x00,0x41,0,0,0})
  put(0x4100,{codes.setval,33,codes['end']})
  put(0x5000,{0,0,0,0,0,2})
  local function object(address,target)
    put(address,{1,4,4,0,0,0,0,0,0,target%256,math.floor(target/256),0xff,0xff})
  end
  object(0x5006,0x5000) -- unused NPC points to its own event data
  object(0x5013,0x5020) -- real code immediately after that event table
  put(0x5020,{codes.setval,77,codes['end']})
  local chunks={}
  for i=1,#bytes,256 do chunks[#chunks+1]=string.char(unpack(bytes,i,math.min(i+255,#bytes)))end
  local e=Extractor.new(table.concat(chunks),version,{symbols={Fixture_MapAttributes={0,0x0200}}})
  local captured={}
  function e:write(name,value)captured[name]=value end
  function e:readSourceTable(name)
    if name=='maps' then return {FIXTURE={id='FIXTURE',source='SYMBOL:Fixture_MapAttributes'}} end
    return {}
  end
  local events=assert(e:gen2ReadMapEvents(0,0x0200))
  T.eq(events.bank,1,'event metadata retains its actual bank: '..version)
  T.eq(events.address,0x5000,'event metadata exposes its known data start: '..version)
  T.eq(#events.objects,2,'self-data pointer does not remove an object: '..version)
  e:extractMapScripts()
  local pool=assert(captured.map_scripts)
  local map=assert(pool.maps.FIXTURE)
  T.eq(map.objects[1],nil,'NPC data pointer is not bound to executable code: '..version)
  T.eq(map.objects[2],'S01_5020','neighboring real script remains bound: '..version)
  T.eq(pool.scripts.S01_5000,nil,'event bytes are never put in the script pool: '..version)
  T.eq(pool.scripts.S01_5020[1][1],'setval','adjacent real script is actually decoded: '..version)
  T.eq(pool.scripts.S01_5020[1][2],77,'adjacent real script retains its operand: '..version)
  T.eq(pool.scripts.S01_4100[1][2],33,'ordinary scene scripts remain decoded: '..version)
  T.eq(pool.info.mapCount,1,'map remains imported: '..version)
  T.eq(pool.info.objectCount,1,'only actual executable object script is counted: '..version)
  T.eq(pool.info.scriptCount,2,'exact scene and object scripts are retained: '..version)
  T.eq(pool.info.desyncCount,0,'known data does not generate a false bytecode desync: '..version)
end
-- Exercise the real cache-readiness gate as well as a fresh import: existing
-- imports must be rebuilt once to remove the false script binding.
local Importer=require('src.import.RomImporter')
local V=require('src.core.GameVersion')
local initial=V.get()
local markerFor
for i=1,100 do
  local name,value=debug.getupvalue(Importer.readyReport,i)
  if not name then break end
  if name=='markerFor' then markerFor=value;break end
end
assert(markerFor)
for _,version in ipairs({'gold','silver','crystal'})do
  V.set(version)
  local marker=markerFor(version)
  T.check(marker:find('gen2-event-targets-v1:',1,true)~=nil,'native cache includes event-target revision: '..version)
  local old=marker:gsub('gen2%-event%-targets%-v1:','')
  love.filesystem.write(V.cachePrefix(version)..'rom-cache.complete',old)
  local report=Importer.readyReport(version)
  T.eq(report.ok,false,'actual readiness gate rejects old object scripts: '..version)
  T.check(report.why:find('another version',1,true)~=nil,'reimport reason is old cache revision: '..version)
end
for _,version in ipairs({'red','blue','yellow','firered','emerald','prism','polishedcrystal'})do
  T.check(not markerFor(version):find('gen2-event-targets-v1:',1,true),'unrelated cache remains unchanged: '..version)
end
V.set(initial)
T.finish('native GSC object event-table pointers are data, not scripts')
