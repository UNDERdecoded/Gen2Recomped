-- A legacy 3D producer pre-flips its clip coordinates for LÖVE 11.
-- Exercise the real presentation and field-FX paths, not just the policy.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local Renderer = require("src.render.Renderer")
local Overworld = require("src.world.OverworldController")
local g = love.graphics
local major = 12
love.getVersion = function() return major, 0, 0 end
Renderer:init()
local world = g.newCanvas(320, 240)
local rows = {}
local draw = g.draw
g.draw = function(image, x, y, rotation, sx, sy)
  rows[#rows + 1] = { image = image, x = x, y = y, sx = sx, sy = sy }
end
local function present(version, pipeline, mirrored)
  V.set(version)
  Renderer:beginFrame()
  rows = {}
  Renderer:setWorldOverride(world, pipeline)
  T.eq(Renderer.worldOverrideMirrored, mirrored, version .. " image carries orientation")
  Renderer:endFrame()
  local found, ui
  for _, row in ipairs(rows) do
    if row.image == world then found = row end
    if row.image == Renderer.canvas then ui = row end
  end
  T.check(found ~= nil, "real compositor presented world")
  if found then
    T.eq(found.sy < 0, mirrored, "world is mirrored exactly once when required")
    T.eq(found.y, mirrored and select(2, g.getDimensions()) or 0, "mirror uses target height")
    T.eq(found.sx > 0, true, "left and right are preserved")
  end
  T.check(ui and ui.sy > 0, "UI stays upright independently of world")
  T.eq(Renderer.worldOverride, nil, "completed image is cleared")
  T.eq(Renderer.worldOverrideMirrored, nil, "completed orientation is cleared")
end
for _, version in ipairs({ "red", "gold", "firered", "emerald" }) do
  present(version, nil, false)
  present(version, { worldOrientation = "legacy" }, true)
  present(version, { worldOrientation = "native" }, false)
end
present("emerald", { worldFormat = "renderData.v1" }, false)
present("platinum", nil, false)
present("black", nil, false)
major = 11
present("red", nil, false)
present("red", { worldOrientation = "legacy" }, false)
major = 12
V.set("red")
Renderer:setWorldOverride(world)
Renderer:setWorldOverride(true)
T.eq(Renderer.worldOverride, nil, "invalid image rejected")
T.eq(Renderer.worldOverrideMirrored, false, "invalid image cannot leave stale mirror")
Renderer:setWorldOverride(world)
Renderer:beginFrame()
T.eq(Renderer.worldOverrideMirrored, nil, "next frame never inherits mirror")
-- Simulate a canvas released after the producer returns it.
Renderer:setWorldOverride(world)
local dimensions = world.getDimensions
world.getDimensions = function() error("released") end
T.check(pcall(Renderer.endFrame, Renderer), "released image falls back without crashing")
world.getDimensions = dimensions
-- Ordinary 2D effects enter at already-projected screen coordinates. They
-- must be mirrored into the legacy image so the final mirror restores both
-- their anchor and their asymmetric artwork.
local calls = {}
local push, pop, translate, scale = g.push, g.pop, g.translate, g.scale
g.push = function() calls[#calls + 1] = "push" end
g.pop = function() calls[#calls + 1] = "pop" end
g.translate = function(x, y) calls[#calls + 1] = { "translate", x, y } end
g.scale = function(x, y) calls[#calls + 1] = { "scale", x, y } end
local function fx() calls[#calls + 1] = "draw"; return "result" end
g.setCanvas(world)
Overworld.withOverrideMirror(fx, {worldOrientation = "legacy"})
T.same(calls, { "push", { "translate", 0, 240 }, { "scale", 1, -1 }, "draw", "pop" },
  "native FX counter-mirror uses bound image height")
for _, target in ipairs({ {world}, { {canvas = world} }, {canvas = world} }) do
  g.setCanvas(target); calls = {}
  Overworld.withOverrideMirror(fx, {worldOrientation = "legacy"})
  T.eq(#calls, 5, "MRT attachment forms use same height")
end
for _, pipeline in ipairs({ {}, {worldOrientation = "native"}, {worldFormat = "renderData.v1"} }) do
  calls = {}
  T.eq(Overworld.withOverrideMirror(fx, pipeline), "result", "native effect return preserved")
  T.same(calls, { "draw" }, "native effects need no inverse transform")
end
g.setCanvas(); calls = {}
Overworld.withOverrideMirror(fx, {worldOrientation = "legacy"})
T.same(calls, { "draw" }, "absent target does not transform screen")
g.draw, g.push, g.pop, g.translate, g.scale = draw, push, pop, translate, scale
T.finish("world override orientation")
