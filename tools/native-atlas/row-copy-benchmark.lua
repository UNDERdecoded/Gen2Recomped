-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Owned QA CPU comparison; never a game FPS benchmark.
local ffi=require('ffi')
local old=assert(loadfile(assert(arg[1])))()
local current=require('src.compat.gen1.AtlasUpload')
local frames={}
for f=1,32 do
 local bytes={};for i=1,1024 do bytes[i]=string.char((f*19+i*31)%256)end
 frames[f]=table.concat(bytes)
end
local function resource()
 local memory=ffi.new('uint8_t[?]',256*256*4)
 return memory,{getWidth=function()return 256 end,getFormat=function()return'rgba8'end,
  getFFIPointer=function()return memory end}
end
for _,module in ipairs{old,current}do
 local keep,data=resource();for i=1,2000 do module.patch(data,16,i%256,frames[i%32+1],false)end
end
local expected,times
times={}
for leg,on in ipairs{false,true,true,false}do
 local module=on and current or old
 local memory,data=resource()
 collectgarbage('collect')
 local start=os.clock()
 for i=1,30000 do module.patch(data,16,i%256,frames[i%32+1],false)end
 times[leg]=os.clock()-start
 local bytes=ffi.string(memory,256*256*4)
 if expected then assert(bytes==expected,'atlas row CPU comparison changed final bytes')else expected=bytes end
 print('ATLAS_ROW_COPY_CPU_LEG',leg,on,times[leg])
end
local ratio=(times[1]+times[4])/(times[2]+times[3])
print('ATLAS_ROW_COPY_CPU_RATIO',ratio)
print('MICROBENCHMARK_ONLY_NOT_GAME_FPS')
assert(ratio>=1,'candidate did not reduce isolated row-copy CPU time')
