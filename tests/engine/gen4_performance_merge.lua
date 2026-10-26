-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- New native fog and poison-step bands must survive the draw-path merge.
local T = require("tests.harness")
love = require("tests.love_stub")
local Version = require("src.core.GameVersion")
local Performance = require("src.core.Performance")
local Fixture = require("tests.world_draw.fixture")
local GymFx = require("src.world.Gen4GymFx")
Version.set("platinum")
local originalFog = GymFx.spriteFog
for _, enabled in ipairs({ false, true }) do
  Performance.worldDrawHoist = enabled
  local scene = Fixture.new(9)
  scene.world.map.def = { gen4DepthFog = {} }
  local fogBuilds, drawn = 0, 0
  GymFx.spriteFog = function()
    fogBuilds = fogBuilds + 1
    return function() return 0.25 end
  end
  for _, entity in ipairs(scene.world.entities) do
    entity.draw = function()
      drawn = drawn + 1
      local r, g, b, a = love.graphics.getColor()
      T.same({ r, g, b, a }, { 0.25, 0.25, 0.25, 1 }, "native fog reaches each ordinary and top-layer sprite")
    end
  end
  scene.world:drawWorld()
  T.eq(fogBuilds, 1, "native fog provider is evaluated once per world pass")
  T.eq(drawn, 9, "all native sprites retain their draw")
  T.same({ love.graphics.getColor() }, { 1, 1, 1, 1 }, "sprite tint is restored after fog")
end
GymFx.spriteFog = originalFog
local Renderer = require("src.render.Renderer")
Renderer:init()
local originalBlit = Renderer.blitCanvas
for _, enabled in ipairs({ false, true }) do
  Performance.hotPathHoist = enabled
  Renderer:beginFrame()
  Renderer:beginWorldPass()
  Renderer:endWorldPass()
  Renderer.worldWobble = 2
  local bands, positive, negative = 0, false, false
  local firstX
  Renderer.blitCanvas = function(self, canvas, sx, sy, zones, zsx, zsy, ox, oy, cx, cy, cw, ch, dpiX, dpiY)
    if canvas ~= Renderer.worldCanvas then
      return originalBlit(self, canvas, sx, sy, zones, zsx, zsy, ox, oy, cx, cy, cw, ch, dpiX, dpiY)
    end
    T.eq(self, Renderer, "native bands keep the renderer receiver")
    T.eq(canvas, Renderer.worldCanvas, "native bands keep the world canvas")
    T.check(type(dpiX) == "number" and type(dpiY) == "number", "band calls keep both DPI arguments")
    T.check(type(cy) == "number" and ch > 0, "band calls retain a nonempty clipped region")
    bands = bands + 1
    firstX = firstX or ox
    if ox > firstX then positive = true end
    if ox < firstX then negative = true end
    return originalBlit(self, canvas, sx, sy, zones, zsx, zsy, ox, oy, cx, cy, cw, ch, dpiX, dpiY)
  end
  Renderer:endFrame()
  T.check(bands > 2, "native poison wobble retains multiple world bands")
  T.check(positive or negative, "native bands alternate their horizontal displacement")
  T.eq(Renderer.worldWobble, nil, "native poison wobble remains a one-frame effect")
end
Renderer.blitCanvas = originalBlit
T.finish("current native Gen4 render integration")
