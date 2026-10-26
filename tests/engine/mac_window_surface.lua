-- Native-call contract without Cocoa/GPU: direct ImageData bytes must be
-- copied into CF-owned storage before a reusable LÖVE buffer can change.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness")
local eq,check=T.eq,T.check
local imageWidth,imageHeight=1,1
local failAllocation,failData,failImage=false,false,false
local view,context={layer={}},{ }
local counts={data=0,provider=0,space=0,image=0,layer=0,ptr=0,scratch=0,permutations=0,copies=0,commits=0,compares=0}
local classes={}
local objc={}
function objc.objc_getClass(name)classes[name]=classes[name] or {class=name};return classes[name]end
function objc.sel_registerName(name)return name end
function objc.objc_msgSend(object,selector,value)
  if selector=="currentContext" then return context end
  if selector=="view" then return view end
  if selector=="layer" then
    if object==view then return view.layer end
    return {kind="layer"}
  end
  if selector=="retain" then counts.layer=counts.layer+1;return object end
  if selector=="release" then counts.layer=counts.layer-1 end
  if selector=="addSublayer:" then object.child=value end
  if selector=="setContents:" then object.image=value;counts.commits=counts.commits+1 end
  if selector=="stringWithUTF8String:" then return value end
end
local cf={}
function cf.CFDataCreate(_,pointer,size)
  eq(size,imageWidth*imageHeight*4,"copy extent matches RGBA storage")
  if failData then return nil end
  counts.copies=counts.copies+1
  counts.data=counts.data+1
  return {bytes={unpack(pointer)}}
end
function cf.CFRelease(data)
  check(not data.released,"CF snapshot released only once")
  data.released=true;counts.data=counts.data-1
end
function cf.CFDataGetBytePtr(data)
  check(not data.released,"comparison snapshot remains alive")
  return data.bytes
end
local cg={}
function cg.CGColorSpaceCreateDeviceRGB()counts.space=counts.space+1;return {}end
function cg.CGColorSpaceRelease()counts.space=counts.space-1 end
function cg.CGDataProviderCreateWithCFData(data)counts.provider=counts.provider+1;return data end
function cg.CGDataProviderRelease()counts.provider=counts.provider-1 end
function cg.CGImageCreate(w,h,bits,pixelBits,stride,space,alpha,provider)
  eq(w,imageWidth,"image width");eq(h,imageHeight,"image height");eq(stride,imageWidth*4,"row stride")
  eq(alpha,0x2002,"CGImage describes little-endian premultiplied BGRA")
  if failImage then return nil end
  counts.image=counts.image+1;return {bytes=provider.bytes}
end
function cg.CGImageRelease()counts.image=counts.image-1 end
local ffi={cdef=function()end,cast=function(_,fn)return fn end,C={memcmp=function(a,b,size)
  counts.compares=counts.compares+1
  for i=1,size do if a[i]~=b[i] then return 1 end end
  return 0
end}}
function ffi.new(name,value)
  if name=="int[1]" then return {[0]=0} end
  if name=="G2SurfaceImageBuffer" then return {data=value[1],height=value[2],width=value[3],rowBytes=value[4]} end
  return value
end
love={data={newByteData=function(size)
  assert(not failAllocation,"scratch allocation failed")
  counts.scratch=counts.scratch+1;local pointer={}
  return {getSize=function()return size end,getFFIPointer=function()return pointer end,
    release=function()counts.scratch=counts.scratch-1 end}
end}}
local conversionError=0
local accelerate={vImagePermuteChannels_ARGB8888=function(input,output,map,flags)
  eq(flags,16,"byte shuffle does not schedule extra workers")
  eq(input.height,imageHeight,"source height");eq(input.width,imageWidth,"source width");eq(input.rowBytes,imageWidth*4,"source stride")
  eq(output.rowBytes,imageWidth*4,"destination stride")
  if conversionError~=0 then return conversionError end
  for p=0,input.width*input.height-1 do
    for i=1,4 do output.data[p*4+i]=input.data[p*4+map[i]+1] end
  end
  counts.permutations=counts.permutations+1;return 0
end}
function ffi.load(path)
  if path:find("Accelerate",1,true) then return accelerate end
  if path:find("libobjc",1,true) then return objc end
  if path:find("CoreGraphics",1,true) then return cg end
  if path:find("CoreFoundation",1,true) then return cf end
  if path:find("OpenGL",1,true) then
    return {glGetIntegerv=function(_,n)n[0]=0 end,glCheckFramebufferStatus=function()return 0x8219 end}
  end
  return {}
end
package.loaded.ffi=ffi
local Surface=require("src.render.MacWindowSurface")
local bridge=assert(Surface.createIfUndefined())
local pixels={10,20,30,255}
local data={getDimensions=function()return imageWidth,imageHeight end,getSize=function()return imageWidth*imageHeight*4 end,
  getFormat=function()return "rgba8" end,getFFIPointer=function()counts.ptr=counts.ptr+1;return pixels end,
  getString=function()error("full-frame Lua copy forbidden")end}
for i=1,40 do
  pixels[1]=i;bridge:present(data,100,100)
  eq(view.layer.child.image.bytes[3],i,"current copied frame presented")
  eq(view.layer.child.image.bytes[1],30,"blue channel is exact")
  eq(view.layer.child.image.bytes[2],20,"green channel is exact")
  eq(view.layer.child.image.bytes[4],255,"alpha channel is exact")
  eq(pixels[1],i,"original RGBA data remains unchanged for observers")
  pixels[1]=255
  eq(view.layer.child.image.bytes[3],i,"Core Animation does not borrow mutable readback storage")
  eq(counts.data,1,"one immutable comparison snapshot retained")
  eq(counts.provider+counts.space+counts.image,0,"temporary native objects released")
end
local oldImage=view.layer.child.image
imageWidth,imageHeight=2,1
pixels[5],pixels[6],pixels[7],pixels[8]=80,40,20,128
bridge:present(data,100,100)
eq(counts.scratch,1,"resize releases previous scratch buffer")
eq(bridge.pixels:getSize(),8,"resize uses exact complete-frame extent")
eq(view.layer.child.image.bytes[5],20,"second pixel blue")
eq(view.layer.child.image.bytes[7],80,"second pixel red")
eq(view.layer.child.image.bytes[8],128,"premultiplied alpha preserved")
eq(oldImage.bytes[3],40,"retained old CF image survives scratch reuse and resize")
imageWidth,imageHeight=1,2
bridge:present(data,100,100)
eq(counts.scratch,1,"equal-byte-size reshape reuses storage with current row geometry")
imageWidth,imageHeight=3,1;failAllocation=true
local currentImage=view.layer.child.image
check(not pcall(bridge.present,bridge,data,100,100),"failed replacement allocation propagates")
eq(bridge.pixels:getSize(),8,"failed replacement keeps previous buffer alive")
eq(counts.scratch,1,"failed replacement does not leak or release retained buffer")
eq(view.layer.child.image,currentImage,"failed frame never replaces current immutable CF image")
failAllocation=false;imageWidth,imageHeight=1,2
bridge:present(data,100,100)
eq(counts.ptr,44,"presenter reads native ImageData storage directly")
eq(counts.layer,1,"only one owned layer retained")
data.getFormat=function()return "rgba16f" end
check(not pcall(bridge.present,bridge,data,100,100),"non-RGBA8 buffer refused before native access")
eq(counts.ptr,44,"invalid format never read")
eq(counts.scratch,1,"one scratch buffer reused for all presents")
eq(counts.permutations,43,"every presented frame converted once")
data.getFormat=function()return "rgba8" end
conversionError=-1
check(not pcall(bridge.present,bridge,data,100,100),"failed conversion cannot present a partial/stale frame")
eq(counts.data,1,"failed conversion preserves previous successful snapshot")
eq(counts.provider+counts.space+counts.image,0,"failed conversion owns no temporary CF objects")
conversionError=0
local copies,commits=counts.copies,counts.commits
for i=1,60 do bridge:present(data,100,100) end
eq(counts.copies,copies,"identical complete bytes need no new CF copy")
eq(counts.commits,commits,"identical complete bytes need no new image commit")
check(counts.compares>=60,"repeat detection compares bytes, not buffer identity")
pixels[8]=127
bridge:present(data,100,100)
eq(counts.copies,copies+1,"last-byte change creates a complete new image")
eq(view.layer.child.image.bytes[8],127,"last-byte change is presented")
bridge:present(data,101,100)
eq(counts.copies,copies+2,"point-size change cannot skip presentation")
local snapshot=bridge.lastData
pixels[8]=126;failData=true
check(not pcall(bridge.present,bridge,data,101,100),"failed snapshot creation propagates")
eq(bridge.lastData,snapshot,"failed copy cannot replace successful snapshot")
failData=false;failImage=true
check(not pcall(bridge.present,bridge,data,101,100),"failed native image creation propagates")
eq(bridge.lastData,snapshot,"failed image cannot become comparison reference")
eq(counts.data,1,"failed image frees its new CFData")
failImage=false
bridge:present(data,101,100)
eq(view.layer.child.image.bytes[8],126,"same input is retried after failed creation")
local oldView=view
view={layer={}}
bridge:present(data,101,100)
check(view.layer.child~=oldView.layer.child,"view replacement installs a new owned layer")
eq(view.layer.child.image.bytes[8],126,"identical bytes still reach replacement view")
eq(counts.data,1,"view replacement retires old comparison reference")
bridge:close();eq(counts.scratch,0,"scratch buffer released at shutdown")
bridge:close();eq(counts.scratch,0,"closing twice cannot release scratch twice")
eq(counts.layer,0,"owned layer released at shutdown")
eq(counts.data,0,"comparison snapshot released at shutdown")
T.finish()
