-- Complete-frame ordering, transparent screen routing, failure cleanup and
-- resource lifetime. Real OpenGL/Metal/window pixels are checked separately.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness")
local check,eq=T.check,T.eq
local osName,backend="Linux","OpenGL"
local w,h,dpi=320,240,1
local target,window,pending
local allocations,releases,reads,dataReleases=0,0,0,0
local calls={}
local g={}
local function setCanvas(c) target=type(c)=="table" and c[1] or c end
g.setCanvas=setCanvas
g.getDimensions=function()return w,h end
g.getPixelDimensions=function()return w*dpi,h*dpi end
g.getRendererInfo=function()return backend end
g.newCanvas=function(cw,ch,settings)
  allocations=allocations+1
  local c={w=cw*settings.dpiscale,h=ch*settings.dpiscale}
  function c:getPixelWidth()return self.w end
  function c:getPixelHeight()return self.h end
  function c:release()releases=releases+1 end
  function c:setFilter()end
  function c:newImageData()
    reads=reads+1
    local d={pixels=self.pixels}
    function d:release()dataReleases=dataReleases+1 end
    return d
  end
  return c
end
g.clear=function(value)
  if target then target.pixels=value else window=value end
end
g.draw=function(image) window=image.pixels end
g.captureScreenshot=function(callback) calls[#calls+1]="request";pending=callback end
g.getBackgroundColor=function()return "background" end
for _,name in ipairs({"push","pop","origin","setShader","setScissor","setColor",
  "setColorMask","setStencilTest","setDepthMode","setBlendMode"}) do g[name]=function()end end
love={graphics=g,system={getOS=function()return osName end}}
local discoveries,presents,closes=0,0,0
local broken,failPresent=false,false
package.loaded["src.render.MacWindowSurface"]={createIfUndefined=function()
  discoveries=discoveries+1
  if not broken then return nil end
  return {present=function(_,data,ww,wh)
    if failPresent then error("native presentation failed") end
    presents=presents+1;window=data.pixels
    eq(ww,w,"Cocoa frame width in points");eq(wh,h,"Cocoa frame height in points")
  end,close=function()closes=closes+1 end}
end}
package.loaded["src.core.Logger"]={warn=function()end}
local Frame=require("src.render.WindowFrame")

Frame.draw(function()calls[#calls+1]="draw";g.clear("first")end,function(data)
  eq(data.pixels,"first","direct capture belongs to current frame")
end)
eq(calls[1],"request","native capture scheduled before any drawing")
eq(calls[2],"draw","drawing follows capture scheduling")
pending({pixels=window});pending=nil
eq(allocations,0,"healthy direct backend allocates no final texture")
eq(discoveries,0,"non-macOS never loads Cocoa bridge")

osName,backend,dpi="OS X","Metal",2
for frame=1,120 do
  local want="metal-frame-"..frame
  Frame.draw(function()
    g.setCanvas();check(target~=nil,"logical screen routes to owned final target")
    g.clear(want)
    local nested={pixels="nested"}
    g.setCanvas(nested);eq(target,nested,"explicit offscreen target preserved")
    g.setCanvas();g.clear(want)
  end,function(data)eq(data.pixels,want,"current complete frame captured")end)
  eq(window,want,"same complete frame reaches physical window")
  eq(g.setCanvas,setCanvas,"graphics function restored after each frame")
  eq(target,nil,"physical target restored before native present")
end
eq(allocations,1,"steady-state final target reused")
eq(discoveries,0,"Metal never attempts OpenGL recovery")
eq(reads,dataReleases,"every capture image released")
eq(Frame.info().mode,"metal-frame","Metal uses owned complete frames")
w,h=400,300
local beforeResizeReads=reads
Frame.draw(function()g.clear("resize")end)
eq(reads,beforeResizeReads,"ordinary Metal frames require no CPU readback")
eq(allocations,2,"resize allocates one replacement")
eq(releases,1,"resize releases previous target")
eq(window,"resize","Retina resize presents current image")
local ok=pcall(Frame.draw,function()error("draw failed")end)
check(not ok,"draw failure propagated")
eq(g.setCanvas,setCanvas,"draw error restores function")
eq(target,nil,"draw error restores physical target")
local before=dataReleases
ok=pcall(Frame.draw,function()g.clear("callback-error")end,function()error("callback failed")end)
check(not ok,"capture failure propagated")
eq(dataReleases,before+1,"capture failure releases image")
Frame.shutdown();eq(releases,2,"shutdown releases retained final target")

backend,broken="OpenGL",false
Frame.draw(function()g.clear("healthy-gl")end)
eq(Frame.info().mode,"direct","valid macOS OpenGL keeps native path")
eq(discoveries,1,"macOS OpenGL probes its own framebuffer")
broken=true
for frame=1,60 do
  local want="gl-frame-"..frame
  Frame.draw(function()g.setCanvas();g.clear(want)end,function(data)
    eq(data.pixels,want,"OpenGL capture contains current frame")
  end)
  eq(window,want,"Cocoa presentation contains same OpenGL frame")
end
eq(Frame.info().mode,"opengl-cocoa-frame","undefined framebuffer enables recovery")
eq(discoveries,2,"bridge retained without repeated probing")
eq(presents,60,"all frames delivered, no stale-frame fallback")
before=dataReleases;failPresent=true
ok=pcall(Frame.draw,function()g.clear("native-error")end)
check(not ok,"native failure propagated instead of reporting a successful frame")
eq(dataReleases,before+1,"native failure releases readback")
eq(g.setCanvas,setCanvas,"native failure leaves graphics function restored")
eq(target,nil,"native failure leaves physical target restored")
Frame.shutdown();eq(closes,1,"shutdown removes only owned Cocoa layer")
eq(reads,dataReleases,"no retained readback images after failures/shutdown")

-- LÖVE 12 can fill an existing destination. Ordinary GL frames reuse exactly
-- one CPU buffer; externally observed/captured images remain independent.
failPresent=false
local allocated,reused=0,0
g.readbackTexture=function(c,...)
  reads=reads+1
  local args={...};local dest=args[7]
  if dest then
    reused=reused+1;dest.pixels=c.pixels;return dest
  end
  allocated=allocated+1
  local d={pixels=c.pixels}
  function d:release()dataReleases=dataReleases+1 end
  return d
end
local startReleases=dataReleases
for i=1,60 do Frame.draw(function()g.clear("reused-"..i)end) end
eq(allocated,1,"ordinary GL allocates one readback destination")
eq(reused,59,"later GL frames fill existing destination")
eq(window,"reused-60","buffer reuse presents current pixels")
eq(dataReleases,startReleases,"retained readback remains valid between frames")
Frame.draw(function()g.clear("independent-capture")end,function(d)
  eq(d.pixels,"independent-capture","capture gets current independent pixels")
end)
eq(allocated,2,"capture does not expose mutable shared buffer")
eq(dataReleases,startReleases+1,"independent capture released immediately")
Frame.observe(function(d)eq(d.pixels,"observer","observer has current pixels")end)
Frame.draw(function()g.clear("observer")end)
Frame.observe(nil)
eq(allocated,3,"observer does not expose shared buffer")
w=w+1
Frame.draw(function()g.clear("resized-buffer")end)
eq(allocated,4,"resize allocates compatible readback destination")
eq(dataReleases,startReleases+3,"resize releases previous readback")
failPresent=true
ok=pcall(Frame.draw,function()g.clear("reuse-error")end)
check(not ok,"reused readback presentation error propagates")
Frame.shutdown()
eq(dataReleases,startReleases+4,"shutdown releases retained buffer after native failure")
local beforeMetal=allocated
backend="Metal"
Frame.draw(function()g.clear("metal-no-readback")end)
eq(allocated,beforeMetal,"Metal does not allocate readback buffers")
Frame.shutdown()
-- Queued public requests use the same final target as the actual window,
-- coalesce into one independent readback and never call a stale frame.
local delivered={}
local nextRequest
local beforeQueued=allocated
check(Frame.capture(function(d,info)
  delivered[#delivered+1]=d.pixels
  eq(info.mode,"metal-frame","queued capture reports actual completed backend")
  nextRequest=Frame.capture(function(later)delivered[#delivered+1]=later.pixels end)
end),"first queued capture accepted")
check(Frame.capture(function(d)delivered[#delivered+1]=d.pixels end),"second queued capture accepted")
Frame.draw(function()g.clear("queued-current-rgba")end)
eq(#delivered,2,"all requests before draw see one completed frame")
eq(delivered[1],"queued-current-rgba","queued capture gets current upright final pixels")
eq(delivered[2],delivered[1],"same-frame captures share the current image")
eq(allocated,beforeQueued+1,"queued requests coalesce one independent readback")
check(nextRequest,"callback may schedule a later capture")
Frame.draw(function()g.clear("queued-following-frame")end)
eq(delivered[3],"queued-following-frame","callback request waits for next frame")
for i=1,16 do check(Frame.capture(function()end),"bounded queue admits request "..i)end
local admitted,reason=Frame.capture(function()error("overflow callback ran")end)
check(not admitted and type(reason)=="string","queue refuses excess without retaining callback")
Frame.shutdown()
Frame.draw(function()g.clear("after-shutdown")end)
eq(#delivered,3,"shutdown cancels pending capture callbacks")
local beforeFailure=dataReleases
Frame.capture(function()error("queued callback failed")end)
check(not pcall(Frame.draw,function()g.clear("queued-failure")end),"queued failure propagates")
eq(dataReleases,beforeFailure+1,"queued failure releases independent image")
Frame.shutdown()
osName,backend="Linux","OpenGL"
Frame.capture(function(d)eq(d.pixels,"queued-direct","direct backend gives its own current frame")end)
local startCalls=#calls
Frame.draw(function()calls[#calls+1]="draw-queued";g.clear("queued-direct")end)
eq(calls[startCalls+1],"request","queued direct capture scheduled before any draw")
eq(calls[startCalls+2],"draw-queued","queued direct capture retains native ordering")
pending({pixels=window});pending=nil
Frame.shutdown()
T.finish()
