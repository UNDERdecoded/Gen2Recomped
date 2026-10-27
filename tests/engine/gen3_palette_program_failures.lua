package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.modkit")
local F=require("tests.palette_programs.fixture")
local M=require("src.import.Gen3PalettePrograms")
local Copy=require("src.mods.Merge").deepCopy
local Verify=require("src.import.RomVerification")
local Extractor=require("src.import.RomExtractorGen3")
for _,game in ipairs({"emerald","firered"}) do
  local f=F.new(game)
  local original=Copy(f.sets)
  local manifest=Copy(f.manifest)
  local bytes=f.rom.data
  local function reset()
    f.sets=Copy(original);f.manifest=Copy(manifest)
    f.rom=require("src.import.RomGba").new(bytes)
  end
  local first
  for k,v in pairs(original) do if v.callback~=0 and k~="unknown" and k~="null_callback" then first=k;break end end
  local function reject(change)
    reset();change(f.sets[first],f)
    f.sets[first].paletteCycles={{stale=true}}
    local ok,report=pcall(M.extract,f.rom,f.sets,f.manifest,f.manifest.romSha1)
    T.eq(ok,true,"bad program cannot abort the import")
    T.check(report and report.unavailable>0,"bad program explicitly counted unavailable")
    T.eq(f.sets[first].paletteCycles,nil,"bad program cannot retain previous successful cycles")
    T.eq(f.sets[first].paletteProgram.status,"unavailable","record contains failure diagnostic")
  end
  for _,bad in ipairs({false,"1",-1,0.5,math.huge,0/0,0x08000000,0x08002000,0x0A000001}) do
    reject(function(r) r.callback=bad end)
  end
  reject(function(r) r.callback=nil end)
  reject(function(r) r.secondary=nil end)
  reject(function(r) r.secondary=not r.secondary end)
  for _,h in ipairs({0xE000,0xD000,0xF000,0xDF00,0xB500,0xFFFF,0x6000,0x4770,0x46FF}) do
    reject(function(r,f) f.change(r.callback-0x08000001,F.le(h,2)) end)
  end
  reject(function(r,f) f.change(r.callback-0x08000001,string.rep(F.le(0x46C0,2),64)) end)
  reject(function(r,f) f.change(r.callback-0x08000001+44,F.le(0x08100000,4)) end)
  reject(function(r,f) f.change(r.callback-0x08000001+40,F.le(0x06000000,4)) end)
  reject(function(r,f) f.change(r.callback-0x08000001+40,F.le(0x03000021,4)) end)
  reject(function(r,f) f.change(r.callback-0x08000001+32,F.le(0x08000000,4)) end)
  reject(function(r,f) f.change(r.callback-0x08000001+20,F.le(0x6008,2)..F.le(0x4770,2)) end)
  reset()
  local calls=0
  local oldRead=f.rom.u16
  f.rom.u16=function(...) calls=calls+1;return oldRead(...) end
  for _,digest in ipairs({false,"",string.rep("0",40),"f3ae088181bf583e55daf962a92bb46f4f1d07b7x"}) do
    for _,r in pairs(f.sets) do r.paletteCycles={{stale=true}} end
    local report=M.extract(f.rom,f.sets,f.manifest,digest)
    T.eq(report.animated,0,"unknown revision cannot authorize palette reads")
    T.eq(report.static,0,"identity failure cannot certify static programs")
    T.eq(calls,0,"no initializer reads before actual identity matches")
    for _,r in pairs(f.sets) do T.eq(r.paletteCycles,nil,"identity failure removes all stale metadata") end
  end
  reset()
  f.manifest.terrainPalettePrograms=nil
  T.eq(M.extract(f.rom,f.sets,f.manifest,manifest.romSha1).animated,0,"legacy manifest declines safely")
  reset();f.manifest.terrainPalettePrograms.version=2
  T.eq(M.extract(f.rom,f.sets,f.manifest,manifest.romSha1).static,0,"unknown profile version declines")
  -- Hashing is a stage requirement. Digest failure never silently falls back
  -- to trusting the launcher's selected game name or the manifest's hash.
  reset()
  local stage=setmetatable({rom=f.rom,manifest=f.manifest,_tilesets=f.sets},{__index=Extractor})
  stage.beginStage=function() end;stage.write=function() end
  local hash=Verify.sha1;Verify.sha1=function() error("hash unavailable") end
  stage:extractTilesetPalettePrograms();Verify.sha1=hash
  T.eq(f.sets[first].paletteProgram.status,"unavailable","hash failure persists useful status")
  T.eq(f.sets[first].paletteCycles,nil,"hash failure cannot retain plausible cycles")
end
do
  local f=F.new("emerald")
  local original=f.rom.data
  local function reject(change)
    local probe=F.new("emerald");change(probe)
    local report=M.extract(probe.rom,probe.sets,probe.manifest,probe.manifest.romSha1)
    T.eq(report.animated,0,"malformed palette recipe/data never partially succeeds")
    T.eq(probe.sets["battle-dome-floor"].paletteCycles,nil,"no partially read frames published")
  end
  for _,field in ipairs({"first","count","frames","step","phase","table"}) do
    for _,bad in ipairs({false,"1",-1,0.5,math.huge,0/0}) do reject(function(p) p.program[field]=bad end) end
  end
  reject(function(p) p.program.step=0 end)
  reject(function(p) p.program.frames=1 end)
  reject(function(p) p.program.frames=257 end)
  reject(function(p) p.program.count=0 end)
  reject(function(p) p.program.first=95 end)
  reject(function(p) p.program.first=250 end)
  reject(function(p) p.program.table=p.rom.size-8 end)
  reject(function(p) p.program.table=p.program.table+1 end)
  reject(function(p) p.change(p.program.table,F.le(0x02000000,4)) end)
  reject(function(p) p.change(p.program.table,F.le(0x08000000+p.rom.size-16,4)) end)
  reject(function(p) p.change(p.program.table,F.le(0x08006001,4)) end)
  reject(function(p) p.change(0x6000,F.le(0x8000,2)) end)
  reject(function(p) p.change(p.program.table+12,F.le(0,4)) end)
  T.eq(f.rom.data,original,"all malformed probes leave independent fixture intact")
end
T.finish("ROM palette program identity, bounds and unsupported callbacks")
