-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Public source Game2 geometry must agree with the actual native classic
-- compositor, retain logical/pixel units and remain a passive query.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Game = require('src.core.Game')
local Renderer = require('src.render.Renderer')
local Version = require('src.core.GameVersion')
local Viewport = require('src.render.GameViewport')
local initial = Version.get()
local available = type(Game.frameFit)=='function' and type(Game.viewport)=='function'
T.check(available, 'native Game2 owner exposes frameFit and viewport queries')
if not available then T.finish('source Game2 frame queries are absent') end
local graphics, window = love.graphics, love.window
local dimensions, pixels, gdpi = graphics.getDimensions, graphics.getPixelDimensions, graphics.getDPIScale
local wdpi = window.getDPIScale
local oldUIW, oldUIH = Renderer.uiWidth, Renderer.uiHeight
local oldFill, oldSplit, oldSkin = Renderer.uiFill, Renderer.splitViewport, Viewport.skinFill
Renderer.uiWidth, Renderer.uiHeight = 160, 144
Renderer.uiFill, Renderer.splitViewport, Viewport.skinFill = false, false, false
Renderer:init()
local game = setmetatable({}, {__index=Game})

for _, edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'}) do
  Version.set(edition)
  local data = T.fixtures.fresh(); data.constants.gen = 2
  local run = T.sdk.loadMods({'mods/frame_probe'}, {data=data, fs=T.sdk.memfs({
    ['mods/frame_probe/manifest.json']='{"id":"frame_probe","name":"Frame probe","version":"1.0.0","api":2,"entry":"main.lua"}',
    ['mods/frame_probe/main.lua']=[[
      local mod=...
      local Game2=require('src.core.Game2')
      mod.exports.fit=function(game,w,h)return Game2.frameFit(game,w,h)end
      mod.exports.viewport=function(game,w,h)return Game2.viewport(game,w,h)end
    ]],
  })})
  T.eq(#run.errors, 0, edition .. ' actual SDK Game2 geometry consumer loads')
  local probe = assert(run.loader.exports.frame_probe)
  for _, size in ipairs({{160,144},{320,240},{640,576},{1024,768},{1280,960},{720,1280}}) do
    local w, h = size[1], size[2]
    for _, dpi in ipairs({1,1.25,1.5,2,3}) do
      graphics.getDimensions = function() return w,h end
      graphics.getPixelDimensions = function() return w*dpi,h*dpi end
      graphics.getDPIScale, window.getDPIScale = function() return dpi end, function() return dpi end
      local before = Renderer:endFrame()
      local scale,x,y,d,pw,ph = probe.fit(game,w,h)
      local view = probe.viewport(game,w,h)
      T.eq(scale, (before.gameWidth/160), 'source scale agrees with actual native logical draw scale')
      T.eq(x, before.gameX, 'source horizontal origin agrees with native composition')
      T.eq(y, before.gameY, 'source vertical origin agrees with native composition')
      T.eq(d, dpi, 'source query reports the actual window DPI')
      T.eq(pw, w*dpi, 'source query retains drawable pixel width')
      T.eq(ph, h*dpi, 'source query retains drawable pixel height')
      T.eq(view.width, w, 'public viewport retains logical window width')
      T.eq(view.height, h, 'public viewport retains logical window height')
      T.eq(view.gameWidth, before.gameWidth, 'public playfield width matches native composition')
      T.eq(view.gameHeight, before.gameHeight, 'public playfield height matches native composition')
      T.eq(view.gameX, before.gameX, 'public playfield horizontal origin matches native composition')
      T.eq(view.gameY, before.gameY, 'public playfield vertical origin matches native composition')
      T.eq(view.scale, scale, 'source viewport uses its LOVE-unit scale')
      T.eq(view.dpiX, dpi, 'source viewport retains DPI X')
      T.eq(view.dpiY, dpi, 'source viewport retains DPI Y')
      T.check(math.abs(x*dpi-math.floor(x*dpi+.5))<1e-8, 'horizontal origin lands on a physical pixel')
      T.check(math.abs(y*dpi-math.floor(y*dpi+.5))<1e-8, 'vertical origin lands on a physical pixel')
      -- Unchanged battle scenes pass drawable dimensions instead of window
      -- dimensions. Those queries must use pixel coordinates exactly once.
      local ps,px,py,pd,qpw,qph = probe.fit(game,w*dpi,h*dpi)
      local pview = probe.viewport(game,w*dpi,h*dpi)
      T.eq(ps, before.scale, 'drawable query uses actual integer framebuffer scale')
      T.check(math.abs(px-before.gameX*dpi)<1e-8, 'drawable query matches native pixel origin X')
      T.check(math.abs(py-before.gameY*dpi)<1e-8, 'drawable query matches native pixel origin Y')
      T.eq(pd, dpi, 'drawable query retains actual DPI metadata')
      T.eq(qpw, w*dpi, 'drawable query retains actual pixel width')
      T.eq(qph, h*dpi, 'drawable query retains actual pixel height')
      T.check(math.abs(pview.gameWidth-before.gameWidth*dpi)<1e-8, 'drawable viewport width matches native pixels')
      T.check(math.abs(pview.gameHeight-before.gameHeight*dpi)<1e-8, 'drawable viewport height matches native pixels')
      if edition=='crystal' and w==1024 and h==768 and dpi==2 then
        -- Independent real Metal observation: native scale10/origin224,48;
        -- the rejected API candidate instead returned10.5/origin184,12.
        T.eq(ps, 10, 'actual Retina regression scale')
        T.eq(px, 224, 'actual Retina regression horizontal origin')
        T.eq(py, 48, 'actual Retina regression vertical origin')
      end
      view.gameX = -1000; view.scale = -1
      local again = probe.viewport(game,w,h)
      T.eq(again.gameX, before.gameX, 'returned view cannot mutate the next query')
      T.eq(again.scale, (before.gameWidth/160), 'returned scale cannot mutate the next query')
      T.same(Renderer:endFrame(), before, 'public queries do not mutate native frame fitting')
      T.eq(Version.get(), edition, 'public query does not change active cartridge')
    end
  end
  for _,size in ipairs({{801,601,1.25},{1001,751,2},{1137,803,1.5}}) do
    local w,h,dpi = size[1],size[2],size[3]
    local pw,ph = math.floor(w*dpi),math.floor(h*dpi)
    graphics.getDimensions = function() return w,h end
    graphics.getPixelDimensions = function() return pw,ph end
    graphics.getDPIScale, window.getDPIScale = function() return dpi end, function() return dpi end
    local native = Renderer:endFrame()
    local scale,x,y = probe.fit(game,pw,ph)
    T.eq(scale, native.scale, 'odd drawable size retains actual native pixel scale')
    T.check(math.abs(x-native.gameX*native.dpiX)<1e-8, 'odd drawable size retains native pixel origin X')
    T.check(math.abs(y-native.gameY*native.dpiY)<1e-8, 'odd drawable size retains native pixel origin Y')
    T.eq(x%1, 0, 'odd drawable horizontal origin is a complete pixel')
    T.eq(y%1, 0, 'odd drawable vertical origin is a complete pixel')
  end
  graphics.getDimensions = function() return 1024,768 end
  graphics.getPixelDimensions = function() return 2048,1536 end
  graphics.getDPIScale, window.getDPIScale = function() return 2 end, function() return 2 end
  local nativeFit = Renderer.fitScale
  Renderer.fitScale = function() return 3 end
  local native = Renderer:endFrame()
  local scale,x,y = probe.fit(game,2048,1536)
  T.eq(scale, native.scale, 'drawable query observes actual decorated native fit')
  T.eq(x, native.gameX*2, 'decorated native horizontal origin remains authoritative')
  T.eq(y, native.gameY*2, 'decorated native vertical origin remains authoritative')
  Renderer.fitScale = nativeFit
  T.eq(#run.errors, 0, 'actual SDK query did not swallow an engine error')
  run.release()
end
graphics.getDimensions, graphics.getPixelDimensions, graphics.getDPIScale = dimensions, pixels, gdpi
window.getDPIScale = wdpi
Renderer.uiWidth, Renderer.uiHeight = oldUIW, oldUIH
Renderer.uiFill, Renderer.splitViewport, Viewport.skinFill = oldFill, oldSplit, oldSkin
Version.set(initial)
T.finish('source Game2 frame queries through the SDK and actual native compositor')
