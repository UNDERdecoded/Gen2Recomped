-- Read-only, bounded analysis of Gen3 tileset initializers. Runtime program
-- recipes are source-pinned in the manifest and require an exact ROM digest.
-- This is not an ARM emulator: RAM is never read/written and no code runs.
local Rom = require("src.import.RomGba")
local M = {}
local BASE = 0x08000000
local function integer(n,lo,hi)
  return type(n)=="number" and n==math.floor(n) and n>=lo and n<=hi
end
local function ram(n,size)
  return type(n)=="number" and ((n>=0x02000000 and n+size<=0x02040000)
    or (n>=0x03000000 and n+size<=0x03008000)) and n%size==0
end
local function offset(rom,address,size)
  if not integer(address,BASE,BASE+rom.size-size) then error("ROM pointer out of bounds") end
  return address-BASE
end

-- These leaf initializers only assign counters and a callback pointer.
-- Unknown halfword loads remain unknown; their counter values are irrelevant
-- to classifying the installed callback. Unknown callback stores decline.
local function initializer(rom,address)
  if not integer(address,BASE+1,BASE+rom.size-2) or address%2~=1 then error("invalid initializer pointer") end
  local start=address-BASE-1
  local reg,stores={},{}
  for index=0,63 do
    local pc=start+index*2
    local h=rom:u16(pc)
    local d=h%8
    if h==0x4770 then
      if #stores~=1 then error("initializer must install exactly one callback") end
      return stores[1]
    elseif h>=0x4800 and h<0x5000 then
      local at=pc+4;at=at-at%4+(h%256)*4
      reg[math.floor(h/256)%8]=rom:u32(at)
    elseif h>=0x2000 and h<0x2800 then
      reg[math.floor(h/256)%8]=h%256
    elseif h<0x1000 then
      local src=reg[math.floor(h/8)%8]
      local shift=math.floor(h/64)%32
      if h<0x0800 then reg[d]=src and (src*2^shift)%4294967296
      else reg[d]=src and (shift==0 and 0 or math.floor(src/2^shift)) end
    elseif h>=0x1800 and h<0x2000 then
      local a=reg[math.floor(h/8)%8]
      local b=math.floor(h/64)%8
      if math.floor(h/1024)%2==0 then b=reg[b] end
      local subtract=math.floor(h/512)%2==1
      reg[d]=a and b and (a+(subtract and -b or b))%4294967296
    elseif h>=0x3000 and h<0x4000 then
      local rd=math.floor(h/256)%8
      reg[rd]=reg[rd] and (reg[rd]+(h<0x3800 and h%256 or -(h%256)))%4294967296
    elseif h>=0x4600 and h<0x4700 then
      local rd=d+math.floor(h/128)%2*8
      if rd>=13 then error("unsupported initializer register") end
      reg[rd]=reg[math.floor(h/8)%16]
    elseif h>=0x6000 and h<0x6800 then
      local base=reg[math.floor(h/8)%8]
      local dest=base and base+math.floor(h/64)%32*4
      if not ram(dest,4) or reg[d]==nil then error("unproven callback store") end
      stores[#stores+1]=reg[d]
    elseif h>=0x8000 and h<0x9000 then
      local base=reg[math.floor(h/8)%8]
      local dest=base and base+math.floor(h/64)%32*2
      if not ram(dest,2) then error("unproven counter access") end
      if h>=0x8800 then reg[d]=nil end
    else
      error(("unsupported initializer instruction %04x"):format(h))
    end
  end
  error("initializer instruction limit exceeded")
end

local function recipe(rom,record,profile,layout)
  if type(record.secondary)~="boolean" then error("tileset bank unavailable") end
  if record.callback==0 then return {},"no-callback" end
  local target=initializer(rom,record.callback)
  if target==0 then return {},"null-callback" end
  if not integer(target,BASE+1,BASE+rom.size-2) or target%2~=1 then error("invalid runtime callback") end
  local program=profile.programs[tostring(target-BASE-1)]
  if type(program)~="table" or program.secondary~=record.secondary then error("unknown runtime palette program") end
  if program.kind=="static" then return {},program.id end
  local split=type(layout)=="table" and layout.palettesInPrimary
  if not integer(split,1,15) or program.kind~="frames"
    or not integer(program.frames,2,256) or not integer(program.count,1,256)
    or not integer(program.first,0,255) or program.first+program.count>256
    or not integer(program.step,1,65535) or (program.phase~=nil and not integer(program.phase,0,65535))
    or not integer(program.table,0,rom.size-program.frames*4)
    or program.table%4~=0 or program.frames*program.count*3>262144 then error("invalid palette recipe") end
  local lo,hi=record.secondary and split*16 or 0,record.secondary and 256 or split*16
  if program.first<lo or program.first+program.count>hi then error("palette recipe crosses bank") end
  local frames,sourceFrames={},{}
  for frame=0,program.frames-1 do
    local at=offset(rom,rom:u32(program.table+frame*4),program.count*2)
    if at%2~=0 then error("unaligned palette frame") end
    local rgb,raw={},{}
    for color=0,program.count-1 do
      local word=rom:u16(at+color*2)
      if word>=0x8000 then error("invalid BGR555 palette frame") end
      rgb[#rgb+1]=string.char(Rom.bgr555(word))
      raw[#raw+1]=string.char(word%256,math.floor(word/256))
    end
    frames[#frames+1]=table.concat(rgb)
    sourceFrames[#sourceFrames+1]=table.concat(raw)
  end
  return {{kind="frames",first=program.first,count=program.count,step=program.step,
    phase=program.phase or 0,frames=frames,sourceFrames=sourceFrames}},program.id
end

function M.extract(rom,sets,manifest,actualSha1)
  local profile=manifest and manifest.terrainPalettePrograms
  local identity=type(profile)=="table" and getmetatable(profile)==nil and profile.version==1
    and type(actualSha1)=="string" and #actualSha1==40
    and actualSha1==manifest.romSha1 and actualSha1==profile.romSha1
    and type(profile.programs)=="table" and getmetatable(profile.programs)==nil
  local report={version=1,static=0,animated=0,unavailable=0}
  local keys={}
  for key,value in pairs(sets) do
    if key~="_romInfo" and type(value)=="table" then keys[#keys+1]=key end
  end
  table.sort(keys)
  for _,key in ipairs(keys) do
    local record=sets[key]
    -- A rerun after a source/profile change must never retain old success.
    record.paletteCycles=nil
    local ok,cycles,id
    if identity then ok,cycles,id=pcall(recipe,rom,record,profile,manifest.layout or {}) end
    if ok then
      record.paletteCycles=cycles
      local status=#cycles>0 and "animated" or "static"
      record.paletteProgram={version=1,status=status,id=id,romSha1=actualSha1}
      report[status]=report[status]+1
    else
      record.paletteProgram={version=1,status="unavailable",
        reason=identity and tostring(cycles) or "ROM palette program identity unavailable"}
      report.unavailable=report.unavailable+1
    end
  end
  return report
end
return M
