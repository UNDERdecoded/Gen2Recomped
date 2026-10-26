-- Exercise the native bridge's real control flow without loading macOS APIs.
-- Function-pointer casts must stay bounded for long OpenGL sessions.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require('tests.harness');local casts=0;local images,cfCopies,released=0,0,0
local function msg(object,selector,...)
 if object==nil then return nil end
 if selector=='currentContext' then return 'context' end
 if selector=='view' then return 'view' end
 if selector=='window' then return 'window' end
 if selector=='windowNumber' then return 99 end
 if selector=='sharedApplication' then return 'application' end
 if selector=='layer' then return object=='CALayer' and 'owned-layer' or 'view-layer' end
 if selector=='retain' then return object end
 if selector=='stringWithUTF8String:' then return 'nearest' end
 if selector=='setContents:' then images=images+1 end
end
local objc={objc_msgSend=msg,sel_registerName=function(s)return s end,objc_getClass=function(s)return s end}
local cf={CFDataCreate=function()cfCopies=cfCopies+1;return 'cfdata'end,CFRelease=function()released=released+1 end,
 CFDataGetBytePtr=function()return 'old-bytes'end}
local cg={CGDataProviderCreateWithCFData=function()return 'provider'end,CGColorSpaceCreateDeviceRGB=function()return 'space'end,
 CGImageCreate=function()return 'image'end,CGImageRelease=function()end,CGColorSpaceRelease=function()end,CGDataProviderRelease=function()end}
love={data={newByteData=function(size)return {getSize=function()return size end,
 getFFIPointer=function()return 'bgra'end,release=function()end}end}}
local comparison=1
local ffi={C={memcmp=function()return comparison end},cdef=function()end,new=function(kind,value)if kind=='int[1]'then return {[0]=0}end;if kind=='G2SurfaceImageBuffer'then return {data=value[1],height=value[2],width=value[3],rowBytes=value[4]}end;return value end,
 cast=function(_,fn)casts=casts+1;return fn end,
 load=function(path)
  if path:find('Accelerate',1,true)then return {vImagePermuteChannels_ARGB8888=function()return 0 end}end
  if path:find('libobjc',1,true)then return objc end
  if path:find('CoreGraphics',1,true)then return cg end
  if path:find('CoreFoundation',1,true)then return cf end
  if path:find('OpenGL',1,true)then return {glGetIntegerv=function(_,p)p[0]=0 end,glCheckFramebufferStatus=function()return 0x8219 end}end
  return {}
 end}
package.loaded.ffi=ffi
local M=require('src.render.MacWindowSurface');local surface=assert(M.createIfUndefined());local bound=casts
local data={getDimensions=function()return 4,4 end,getSize=function()return 64 end,getFormat=function()return 'rgba8'end,getFFIPointer=function()return 'pixels'end}
for i=1,12000 do surface:present(data,4,4)end
T.eq(casts,bound,'twelve thousand presents create no new function pointer CTypes')
T.eq(images,12000,'every current frame still handed to owned native layer')
T.eq(cfCopies,12000,'asynchronous presenter owns a fresh immutable byte copy each frame')
T.eq(released,11999,'one immutable comparison snapshot retained')
comparison=0
for i=1,1000 do surface:present(data,4,4)end
T.eq(images,12000,'identical bytes need no repeated layer commit')
T.eq(cfCopies,12000,'identical bytes need no repeated copy')
for i=1,100 do T.eq(M.windowNumber(),99,'window queries retain current-process selection')end
surface:close()
T.eq(released,12000,'final comparison snapshot released at shutdown')
T.eq(casts,bound,'window lookup and shutdown also reuse bound ABI functions')
T.finish('Mac window bridge function pointer lifetime')
