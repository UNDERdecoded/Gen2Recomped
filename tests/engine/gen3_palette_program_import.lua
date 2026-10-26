package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.modkit")
local F=require("tests.palette_programs.fixture")
local M=require("src.import.Gen3PalettePrograms")
local Extractor=require("src.import.RomExtractorGen3")
local Verify=require("src.import.RomVerification")
local Writer=require("src.import.LuaWriter")
local Copy=require("src.mods.Merge").deepCopy
for _,game in ipairs({"emerald","firered"}) do
  local f=F.new(game)
  local original=f.rom.data
  local report=M.extract(f.rom,f.sets,f.manifest,f.manifest.romSha1)
  T.eq(report.animated,game=="emerald" and 1 or 0,"Smaragd palette program versus FireRed tile-only callbacks")
  T.eq(report.static,game=="emerald" and 21 or 8,"all known tile-only/null programs positively classified")
  T.eq(report.unavailable,1,"unknown runtime remains explicitly incomplete")
  T.eq(f.sets.unknown.paletteCycles,nil,"no invented static array for unknown program")
  for id,record in pairs(f.sets) do
    if id~="unknown" then
      T.check(type(record.paletteCycles)=="table","each supported source explicitly declares cycles")
      T.eq(record.paletteProgram.romSha1,f.manifest.romSha1,"per-record provenance pins identity")
    end
  end
  if game=="emerald" then
    local run=f.sets["battle-dome-floor"].paletteCycles[1]
    T.eq(run.first,128,"BG palette 8 absolute destination")
    T.eq(run.count,16,"complete 16-colour palette copied")
    T.eq(run.step,4,"source callback cadence")
    T.eq(#run.frames,4,"four palette pointers, not inferred from tile VRAM")
    T.same(run.frames,f.frames,"all colours use exact independent BGR555 floor decoding")
    T.eq(#run.sourceFrames,4,"source palette words retained for every picture")
    for frame=0,3 do
      local at=f.rom:u32(f.program.table+frame*4)-0x08000000
      local raw=f.rom:bytes(at,32)
      for color=0,15 do
        local lo,hi=run.sourceFrames[frame+1]:byte(color*2+1,color*2+2)
        T.eq(lo+hi*256,raw[color*2+1]+raw[color*2+2]*256,
          "original BGR555 words survive independently of RGB rounding")
      end
    end
  end
  T.eq(f.rom.data,original,"analysis cannot modify cartridge bytes")
  -- Exercise the actual automatic stage, real ROM reader and real Lua cache
  -- serializer; only hash and file destination are injected for synthetic ROMs.
  local stages,writes,hashes=0,0,0
  local stage=setmetatable({rom=f.rom,manifest=f.manifest,_tilesets=Copy(f.sets)}, {__index=Extractor})
  stage.beginStage=function(_,name) stages=stages+1;T.eq(name,"Gen3 tileset palette programs","automatic stage name") end
  stage.write=function(_,name,value)
    writes=writes+1;T.eq(name,"map_tilesets","uses existing cache namespace")
    stage.serialized=Writer.encode(value)
  end
  local hash=Verify.sha1
  Verify.sha1=function(bytes) hashes=hashes+1;T.eq(bytes,f.rom.data,"authenticates the actual stage ROM bytes");return f.manifest.romSha1 end
  local rand,gpu=math.random,love.graphics.newImage
  math.random=function() error("import cannot consume gameplay RNG") end
  love.graphics.newImage=function() error("data import cannot allocate graphics") end
  local before=package.loaded["src.core.Game"]
  stage:extractTilesetPalettePrograms()
  math.random,love.graphics.newImage=rand,gpu
  Verify.sha1=hash
  T.eq(stages,1,"stage runs once");T.eq(writes,1,"one cache write after complete analysis");T.eq(hashes,1,"digest once per stage")
  T.eq(package.loaded["src.core.Game"],before,"import never bootstraps player Game")
  local loaded=assert(loadstring(stage.serialized))()
  T.same(loaded._romInfo.palettePrograms,report,"persisted summary matches all callback classifications")
  T.same(loaded[game=="emerald" and "battle-dome-floor" or "general"].paletteCycles,
    f.sets[game=="emerald" and "battle-dome-floor" or "general"].paletteCycles,"binary palette frames survive actual cache serialization")
  local tileStage,paletteStage
  for i,name in ipairs(Extractor.DATA_STAGES) do
    if name=="extractTilesetAnimations" then tileStage=i end
    if name=="extractTilesetPalettePrograms" then paletteStage=i end
  end
  T.eq(paletteStage,tileStage+1,"normal import automatically reads palette programs after tile animations")
  -- Import actual synthetic Tileset headers too. FireRed swaps the callback
  -- and attribute pointers relative to Emerald; this catches a program
  -- reader which works with hand-built records but loses real header data.
  local headerRom=F.new(game)
  for i,name in ipairs({"general",game=="emerald" and "battle-dome-floor" or "celadon"}) do
    local at=i*0x100
    local gfx=0x8000+(i-1)*0x8000
    local pals=gfx+0x4000
    local meta=gfx+0x5000
    local callback=headerRom.sets[name].callback
    local attrs=0x08000000+meta+48
    headerRom.change(at,string.char(0,i-1,0,0)..F.le(0x08000000+gfx,4)..F.le(0x08000000+pals,4)
      ..F.le(0x08000000+meta,4)..F.le(game=="emerald" and attrs or callback,4)
      ..F.le(game=="emerald" and callback or attrs,4))
  end
  local captured={}
  local headers=setmetatable({rom=headerRom.rom,manifest=headerRom.manifest,layout=headerRom.manifest.layout,
    stage=0,_tilesetAddresses={[0x100]=true,[0x200]=true},_layoutRecords={}}, {__index=Extractor})
  headers.write=function(_,name,value) captured[name]=value end
  headers.saveImage=function() end;headers.tilesetSheet=function() return {} end
  -- These independent behaviour derivations need full map/script datasets;
  -- they are outside this header/palette test and remain covered elsewhere.
  for _,name in ipairs({"counterBehaviour","pcBehaviour","wallBehaviours","warpBehaviours","diveTerrain",
    "waterfallTerrain","iceBehaviours","bikeBehaviours","escalatorBehaviours","currentBehaviours",
    "forcedMovementBehaviours","lavaridgeWarps","noRunBehaviours","checkBehaviourNames"}) do
    headers[name]=function() end
  end
  headers:extractTilesets()
  local primary,secondary=headers._tilesets.TILESET_0000100,headers._tilesets.TILESET_0000200
  T.check(primary~=nil and secondary~=nil,"real header stage imports both source banks")
  for _,record in ipairs({primary,secondary})do
    T.eq(#record.sourcePaletteBytes,512,"complete original palette bank retained")
    local raw=headerRom.rom:bytes(assert(headerRom.rom:pointer(record.address+8)),512)
    for i=1,512 do T.eq(record.sourcePaletteBytes:byte(i),raw[i],"header-selected palette bytes preserved")end
  end
  T.eq(primary.callback,headerRom.sets.general.callback,"primary callback comes from title-specific header slot")
  T.eq(secondary.callback,headerRom.sets[game=="emerald" and "battle-dome-floor" or "celadon"].callback,
    "secondary callback comes from title-specific header slot")
  local oldHash=Verify.sha1
  Verify.sha1=function(b) T.eq(b,headerRom.rom.data,"header-import palette stage verifies same bytes");return headerRom.manifest.romSha1 end
  headers:extractTilesetPalettePrograms();Verify.sha1=oldHash
  T.eq(captured.map_tilesets._romInfo.palettePrograms.unavailable,0,"actual header-to-program path is complete")
  T.eq(primary.paletteProgram.status,"static","imported primary tile-only program classified")
  T.eq(secondary.paletteProgram.status,game=="emerald" and "animated" or "static","imported secondary classified")
  if game=="emerald" then T.same(secondary.paletteCycles[1].frames,headerRom.frames,"header path reads all frame bytes correctly") end
end
T.finish("Automatic Gen3 ROM palette program data import")
