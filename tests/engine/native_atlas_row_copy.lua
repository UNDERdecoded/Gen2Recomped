-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local ffi=require('ffi')
local Upload=require('src.compat.gen1.AtlasUpload')
local checks=0
local function check(value,label)checks=checks+1;assert(value,label)end
local function pixels(seed)
 local bytes={};for i=1,1024 do bytes[i]=string.char((i*37+seed*53)%256)end
 return table.concat(bytes)
end
local n=0
for _,cols in ipairs{1,2,5,16}do for _,rows in ipairs{1,3}do
 local width,height=cols*16,rows*16;local total=width*height*4
 for slot=0,cols*rows-1 do
  n=n+1
  local memory=ffi.new('uint8_t[?]',total+64);ffi.fill(memory,total+64,193)
  local data={getWidth=function()return width end,getFormat=function()return'rgba8'end,
   getFFIPointer=function()return memory+32 end}
  local rgba=pixels(n)
  Upload.patch(data,cols,slot,rgba,false)
  -- Construct independent complete image rows, including both guard regions.
  local expected={string.rep(string.char(193),32)}
  local x,y=slot%cols*16,math.floor(slot/cols)*16
  for row=0,height-1 do
   if row>=y and row<y+16 then
    expected[#expected+1]=string.rep(string.char(193),x*4)..rgba:sub((row-y)*64+1,(row-y+1)*64)
     ..string.rep(string.char(193),(width-x-16)*4)
   else expected[#expected+1]=string.rep(string.char(193),width*4)end
  end
  expected[#expected+1]=string.rep(string.char(193),32)
  check(ffi.string(memory,total+64)==table.concat(expected),'row bytes, stride, placement or guard region changed')
  check(rgba==pixels(n),'immutable frame bytes changed')
 end
end end

-- Portable, null-pointer and non-RGBA resources keep the normal ImageData path.
local made,pasted,released=0,0,0
love={image={newImageData=function(w,h,format,rgba)
 made=made+1;check(w==16 and h==16 and format=='rgba8','portable patch dimensions')
 assert(#rgba==1024,'invalid ImageData payload')
 return{release=function()released=released+1 end}
end}}
for _,mode in ipairs{'portable','null','format'}do
 local data={getWidth=function()return 32 end,
  getFormat=function()return mode=='format'and'rgba16'or'rgba8'end,
  getFFIPointer=function()return mode=='null'and ffi.cast('void*',0)or error('unexpected pointer access')end,
  paste=function(_,_,x,y,sx,sy,w,h)
   pasted=pasted+1;check(x==16 and y==16 and sx==0 and sy==0 and w==16 and h==16,'portable placement')
  end}
 Upload.patch(data,2,3,pixels(3),mode=='portable')
end
check(made==3 and pasted==3 and released==3,'fallback resource ownership changed')
local pointerReads=0
local invalid={getFFIPointer=function()pointerReads=pointerReads+1;error('unsafe short read')end,
 getFormat=function()return'rgba8'end}
check(not pcall(Upload.patch,invalid,1,0,'short',false),'invalid payload accepted')
check(pointerReads==0,'invalid byte length reached raw pointer copy')
print(('%d/%d checks passed  (native atlas immutable row copy, independent full buffers, guards and portable fallbacks)'):format(checks,checks))
