package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Polished Crystal audio')
local Synth=require('src.core.ChipSynth')
local WorkerFs=require('src.core.WorkerFs');local read=WorkerFs.read
local blobs={};WorkerFs.read=function(_,path) return assert(blobs[path],path) end
local function bytes(values) local out={};for i,v in ipairs(values) do out[i]=string.char(v) end;return table.concat(out) end
local function fixture(id,stream,polished)
  local bank=string.rep('\0',0x4000)
  local function put(at,s) bank=bank:sub(1,at-0x4000)..s..bank:sub(at-0x4000+#s+1) end
  put(0x4000,bytes({0,0,0x41}));put(0x4100,bytes(stream));blobs[id]=bank
  return Synth.newEngine({audio={programFile=id,bankOrder={1},gen2Dialect=polished and 'polishedcrystal' or nil,waveBanks={gen2={bank=1,address=0x4200,count=1}}}},{bank=1,address=0x4000,engine='gen2'},{allowLoops=false})
end
-- Equivalent real dialect programs must produce identical event and PCM output.
local vanilla={0xDA,0,140,0xDB,2,0xD8,12,0xA2,0xD4,0xE1,2,0x34,0xE6,0,1,0x13,0x23,0x03,0xFF}
local polished={0xDE,140,0,0xDA,0xDC,12,0xA2,0xD4,0xE4,2,0x34,0xE7,1,0,0x13,0x23,0x03,0xFF}
local a,b=fixture('vanilla',vanilla),fixture('polished',polished,true)
for i=1,4 do
  local x,y=a.channels[1]:nextEvent(),b.channels[1]:nextEvent()
  T.same(y,x,'Polished command alignment yields same event as standard Crystal')
end
T.eq(a.tempo,140,'standard Crystal big-endian tempo retained')
T.eq(b.tempo,140,'Polished little-endian tempo')
a,b=fixture('vanilla-pcm',vanilla),fixture('polished-pcm',polished,true)
for i=1,44100 do local x,y=a:sample(),b:sample();if x~=y then error('dialect PCM differs at sample '..i) end end
T.check(true,'one second equivalent PCM matches bit for bit')
for _,case in ipairs({{0xED,true,false},{0xEE,false,true},{0xEF,true,true}}) do
  local e=fixture('pan'..case[1],{case[1],0xDC,1,0xF0,0x10,0xFF},true)
  local event=e.channels[1]:nextEvent()
  T.eq(event.panLeft,case[2],'packed Polished left panning')
  T.eq(event.panRight,case[3],'packed Polished right panning')
  T.eq(e.channels[1].address,0x4105,'panning consumes no operand or note')
end
-- Parse actual music, effects and cries from the supported ROM, using its symbols.
local function file(path) local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
local manifest=require('src.link.Json').decode(file('tools/rom_manifest_polishedcrystal.json'))
local raw=file('polishedcrystal-3.2.3 (1).gbc')
local Ex=require('src.import.RomExtractorGen2').new(raw,'polishedcrystal',manifest)
local banks={};local songs=Ex:gen2AudioTable('Music','Music_',banks)
local effects=Ex:gen2AudioTable('SFX','Sfx_',banks)
local cries=Ex:gen2AudioTable('Cries','Cry',banks)
local kits=Ex:gen2Drumkits(banks);local waves=Ex:symbol('WaveSamples');banks[waves.bank]=true
local order,parts={},{}
for n=0,127 do if banks[n] then order[#order+1]=n;parts[#parts+1]=raw:sub(n*0x4000+1,(n+1)*0x4000) end end
blobs.actual=table.concat(parts)
local data={audio={programFile='actual',bankOrder=order,gen2Dialect='polishedcrystal',waveBanks={gen2={bank=waves.bank,address=waves.address,count=13}},drumkits={gen2=kits}}}
for kit=0,6 do
  T.check(kits[tostring(kit)]~=nil,'all seven native drumkits extracted')
  for drum=0,12 do
    local pointer=kits[tostring(kit)][tostring(drum)]
    T.check(pointer.address>=0x4000 and pointer.address<0x8000,'relative drum pointer in bank')
  end
end
local counts={0,0,0}
for group,defs in ipairs({songs,effects,cries}) do
  for name,header in pairs(defs) do
    local ok,err=pcall(function()
      local engine=Synth.newEngine(data,header,{allowLoops=true})
      for _,channel in ipairs(engine.channels) do
        for event=1,256 do if not channel:nextEvent() then break end end
      end
    end)
    T.check(ok,name..' native stream decodes: '..tostring(err));counts[group]=counts[group]+1
  end
end
T.check(counts[1]>150,'native song roster covered')
T.check(counts[2]>150,'native effect roster covered')
T.check(counts[3]>40,'native cry roster covered')
print(('Native roster: %d songs, %d effects, %d cries'):format(unpack(counts)))
local engine=Synth.newEngine(data,songs.Music_NewBarkTown,{allowLoops=true})
T.eq(#engine.waves,13,'all thirteen native wave instruments loaded')
for i=1,88200 do local sample=engine:sample();assert(sample==sample and math.abs(sample)<=1,'invalid audio sample') end
T.check(true,'two seconds native New Bark Town PCM renders within range')
local Audio=require('src.core.ChipAudio')
local slim
for i=1,50 do local name,value=debug.getupvalue(Audio.playMusic,i);if name=='slimAudio' then slim=value;break end end
T.check(type(slim)=='function','worker audio packet builder found')
local packet=slim(data)
T.eq(packet.gen2Dialect,'polishedcrystal','worker preserves selected dialect')
T.eq(packet.drumkits,data.audio.drumkits,'worker receives native Polished drumkits')
local workerEngine=Synth.newEngine({audio=packet},songs.Music_NewBarkTown,{allowLoops=true})
T.eq(workerEngine.channels[1].polished,true,'worker constructs Polished decoder')
local extracted
local CacheFs=require('src.import.CacheFs');local write=CacheFs.write
CacheFs.write=function() return true end
Ex.beginStage=function() end;Ex.tick=function() end
Ex.constants=function() return {speciesOrder={}} end
Ex.gen2MapIndex=function() return {},{} end
Ex.readSourceTable=function() return {} end
Ex.write=function(_,name,value) if name=='audio' then extracted=value end end
Ex:extractAudio();CacheFs.write=write
T.eq(extracted.gen2Dialect,'polishedcrystal','fresh import stamps dialect')
T.eq(extracted.waveBanks.gen2.count,13,'fresh import stamps native instrument count')
T.check(extracted.drumkits.gen2['6']~=nil,'fresh import includes seventh kit')
-- Exercise the untouched vanilla dialect with each retail Gen2 music roster.
for _,case in ipairs({
  {'gold','Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc'},
  {'silver','Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc'},
  {'crystal','Pokemon - Crystal Version (USA, Europe) (Rev 1).gbc'},
}) do
  local version,path=unpack(case)
  local m=require('src.link.Json').decode(file('tools/rom_manifest_'..version..'.json'))
  local rom=file(path);local ex=require('src.import.RomExtractorGen2').new(rom,version,m)
  local used={};local defs=ex:gen2AudioTable('Music','Music_',used)
  local wave=ex:symbol('WaveSamples');used[wave.bank]=true
  local drums=ex:gen2Drumkits(used);local order,parts={},{}
  for n=0,127 do if used[n] then order[#order+1]=n;parts[#parts+1]=rom:sub(n*0x4000+1,(n+1)*0x4000) end end
  blobs[version]=table.concat(parts)
  local other={audio={programFile=version,bankOrder=order,waveBanks={gen2={bank=wave.bank,address=wave.address,count=10}},drumkits={gen2=drums}}}
  T.eq(slim(other).gen2Dialect,nil,version..' worker packet does not select Polished')
  local total=0
  for name,header in pairs(defs) do
    local ok,err=pcall(function()
      local e=Synth.newEngine(other,header,{allowLoops=true})
      assert(not e.channels[1].polished,'Polished decoder leaked')
      for _,c in ipairs(e.channels) do for i=1,128 do if not c:nextEvent() then break end end end
    end)
    T.check(ok,version..' '..name..' standard stream: '..tostring(err));total=total+1
  end
  T.check(total>80,version..' native music roster tested')
end
WorkerFs.read=read;Synth.invalidateBanks();T.finish()
