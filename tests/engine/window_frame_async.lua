-- Deferred OpenGL recovery must preserve frame order, current-frame captures
-- and resource ownership even when async submission/completion fails.
package.path="./?.lua;./?/init.lua;"..package.path
local T=require("tests.harness")
local eq,check=T.eq,T.check
local w,h=320,240
local target,window
local activeRequests,activeData=0,0
local reads,queues,waits,presents=0,0,0,0
local failQueue,failWait,failPresent=false,false,false
local throwWait=false
local backend="OpenGL"
local g={}
g.getDimensions=function()return w,h end
g.getPixelDimensions=function()return w*2,h*2 end
g.getRendererInfo=function()return backend end
g.setCanvas=function(c)target=type(c)=="table" and c[1] or c end
g.newCanvas=function(cw,ch)
  local c={w=cw*2,h=ch*2}
  function c:getPixelWidth()return self.w end
  function c:getPixelHeight()return self.h end
  function c:setFilter()end
  function c:release()eq(activeRequests,0,"texture retired after pending requests")end
  return c
end
g.clear=function(pixels)target.pixels=pixels end
local function image(pixels)
  activeData=activeData+1
  local d={pixels=pixels}
  function d:release()
    check(not self.released,"image released only once")
    eq(activeRequests,0,"destination released after pending requests")
    self.released=true;activeData=activeData-1
  end
  return d
end
g.readbackTexture=function(c,...)
  reads=reads+1
  local dest=select(7,...)
  if dest then check(not dest.released,"sync destination alive");dest.pixels=c.pixels;return dest end
  return image(c.pixels)
end
g.readbackTextureAsync=function(c,...)
  queues=queues+1
  if failQueue then error("submission failed") end
  activeRequests=activeRequests+1
  eq(activeRequests,1,"only one request may be in flight")
  local provided=select(7,...)
  local dest=provided or image(nil)
  local pixels=c.pixels
  local request={}
  function request:wait()
    waits=waits+1
    check(not self.released,"request alive while waiting")
    check(not dest.released,"destination alive while writing")
    if throwWait then error("completion threw") end
    if failWait then self.failed=true;return end
    dest.pixels=pixels
  end
  function request:hasError()return self.failed end
  function request:getImageData()self.adopted=true;return dest end
  function request:release()
    check(not self.released,"request released only once")
    self.released=true;activeRequests=activeRequests-1
    if not provided and not self.adopted then dest:release() end
  end
  return request
end
local warnings=0
package.loaded["src.core.Logger"]={warn=function()warnings=warnings+1 end}
package.loaded["src.render.MacWindowSurface"]={createIfUndefined=function()
  return {present=function(_,data,ww,wh)
    if failPresent then error("present failed") end
    check(not data.released,"presented image alive")
    eq(ww,w,"current window width");eq(wh,h,"current window height")
    window=data.pixels;presents=presents+1
  end,close=function()end}
end}
love={graphics=g,system={getOS=function()return "OS X"end}}
local Frame=require("src.render.WindowFrame")
local function draw(value,capture)Frame.draw(function()g.clear(value)end,capture)end

draw(1);eq(window,1,"bootstrap immediately presents complete frame")
eq(Frame.info().latencyFrames,0,"bootstrap latency zero")
for i=2,120 do
  draw(i);eq(window,i-1,"steady stream presents ordered previous frame")
  eq(Frame.info().latencyFrames,1,"latency bounded to one frame")
  eq(Frame.info().pendingReadbacks,1,"one queued readback")
end
eq(reads,0,"steady pipeline avoids synchronous readback")
eq(queues,120,"one async readback per frame")
eq(activeData,1,"only one retained image destination")

draw(121,function(d)eq(d.pixels,121,"capture is current, not deferred")end)
eq(window,121,"capture also presents current frame")
eq(activeRequests,0,"capture drains deferred request")
eq(Frame.info().latencyFrames,0,"capture reports no latency")
eq(activeData,1,"capture image released separately")
Frame.observe(function(d)eq(d.pixels,122,"observer sees current image")end)
draw(122);eq(window,122,"observer also presents current frame")
Frame.observe(nil)
draw(123);eq(window,123,"pipeline restarts with current complete image")
draw(124);eq(window,123,"one startup repetition on restart")
draw(125);eq(window,124,"then progresses every frame")
w,h=400,300
draw(126);eq(window,126,"resize drains old size and bootstraps new size")
draw(127);eq(window,126,"new size keeps bounded latency")
Frame.shutdown();eq(activeRequests,0,"shutdown drains requests")
eq(activeData,0,"shutdown releases destination")
eq(Frame.info().latencyFrames,0,"shutdown clears latency")

-- Submission failure: current-frame repair, then no further async attempts.
draw(130);failQueue=true
draw(131);eq(window,131,"queue failure repairs current frame")
eq(Frame.info().latencyFrames,0,"failed queue returns to current frames")
local q=queues
draw(132);eq(window,132,"fallback continues with current frame")
eq(queues,q,"failed async remains disabled")
failQueue=false
w=w+1;draw(133);eq(window,133,"resize can retry async")
check(queues>q,"async resumed after resource replacement")

-- Completion failure must not display stale/incomplete destination bytes.
failWait=true
draw(134);eq(window,134,"completion failure repairs current frame")
eq(activeRequests,0,"failed completion request released")
failWait=false
draw(135);eq(window,135,"completion failure retains synchronous fallback")
Frame.shutdown();eq(activeData,0,"failure cleanup retains no images")

-- Failed native presentation propagates; no pending GPU work survives it.
draw(140);failPresent=true
local ok=pcall(draw,141)
check(not ok,"presentation error propagates")
eq(activeRequests,0,"presentation error discards request")
failPresent=false
Frame.shutdown();eq(activeData,0,"native error shutdown releases destination")

-- Unsupported async runtimes keep the original reusable synchronous path.
local async=g.readbackTextureAsync;g.readbackTextureAsync=nil
draw(150);draw(151);eq(window,151,"old runtime presents current frame")
eq(Frame.info().latencyFrames,0,"old runtime latency unchanged")
Frame.shutdown();g.readbackTextureAsync=async

failQueue=true
draw(160);eq(window,160,"initial submission failure uses current pixels")
failQueue=false
Frame.shutdown();eq(activeData,0,"initial submission failure releases image")
failWait=true
draw(161);eq(window,161,"initial completion error uses current pixels")
failWait=false
Frame.shutdown();eq(activeData,0,"initial completion error releases both images")
throwWait=true
draw(162);eq(window,162,"throwing completion uses current pixels")
throwWait=false
Frame.shutdown();eq(activeData,0,"throwing completion releases both images")

draw(170)
ok=pcall(Frame.draw,function()error("body failed")end)
check(not ok,"body error propagates")
eq(target,nil,"body error restores physical target")
Frame.shutdown();eq(activeData,0,"shutdown drains after body error")
draw(171)
ok=pcall(draw,172,function()error("capture callback failed")end)
check(not ok,"capture callback error propagates")
eq(activeRequests,0,"failed capture leaves no pending request")
Frame.shutdown();eq(activeData,0,"failed capture releases all images")
T.finish()
