-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.harness")
love = require("tests.love_stub")
local P = require("src.core.Performance")
local originalLove, originalJit = love, jit
local function device(os, arch, cores, w, h)
  love = {
    system = {
      getOS = function()
        return os
      end,
      getProcessorCount = function()
        return cores
      end,
    },
    graphics = {
      getPixelDimensions = function()
        return w, h
      end,
    },
  }
  jit = { arch = arch }
end
device("OS X", "arm64", 8, 3024, 1964)
T.eq(P.detect(), "high", "desktop ARM keeps native Retina policy")
device("Windows", "x64", 8, 3840, 2160)
T.eq(P.detect(), "balanced", "4K desktop fill receives a budget")
device("Android", "arm64", 8, 2560, 1440)
T.eq(P.detect(), "low", "large physical mobile frame receives LOW")
P.lowTierBudget = false
T.eq(P.detect(), "balanced", "rollback restores old mobile AUTO")
P.lowTierBudget = true
device("Windows", "x64", 2, 1920, 1080)
T.eq(P.detect(), "low", "large dual-core display receives LOW")
device("Windows", "x64", 2, 640, 480)
T.eq(P.detect(), "balanced", "small dual-core display keeps previous tier")
device("OS X", "arm64", 8, 0 / 0, 480)
T.eq(P.detect(), "high", "invalid pixel dimensions fall back")
love, jit = originalLove, originalJit
P.tier = "low"
for _, key in ipairs({ "shaderPresets", "colorCorrection", "reflections", "discordPresence" }) do
  T.eq(P.extraCap(key), false, "LOW applies " .. key)
end
for tick = 0, 31 do
  T.eq(P.paletteTick(tick), math.floor(tick / 4) * 4, "quarter palette holds sampled tick")
end
P.lowTierBudget = false
T.eq(P.extraCap("reflections"), nil, "rollback removes added live caps")
T.eq(P.paletteTick(7), 7, "rollback restores full palette ticks")
P.lowTierBudget = true
local Presets = require("src.render.ShaderPresets").new()
local input = {}
Presets.shader = {}
Presets.entry = { id = "owned" }
T.eq(Presets:active(), false, "LOW masks shader activity")
T.eq(Presets:apply(input, 1), input, "LOW returns untouched preset input")
T.eq(Presets.entry.id, "owned", "mask keeps selected preset")
P.tier = "high"
T.check(Presets:active(), "raising tier restores selected shader")
local C = require("src.render.GbcColorCorrection")
C.setMode("accurate")
P.tier = "low"
T.eq(C.active(), false, "LOW avoids correction resources")
T.eq(C.apply(input), input, "LOW returns original correction input")
T.eq(C.mode, "accurate", "LOW keeps selected correction mode")
local TR = require("src.render.TileRenderer")
local ticks, recolors = {}, 0
local tiles = {
  primary = { paletteCycles = {} },
  setPaletteTicks = function(_, tick)
    ticks[#ticks + 1] = tick
    return true
  end,
}
local renderer =
  setmetatable({ gen3 = {
    tiles = tiles,
    recolor = function()
      recolors = recolors + 1
    end,
  } }, TR)
for _ = 1, 12 do
  TR.tick(1 / 60)
  renderer:syncGen3Palettes()
end
T.same(ticks, { 0, 4, 8, 12 }, "actual sheet refresh samples held native clock without slowing it")
T.eq(recolors, 4, "quarter refresh does not recolor every tick")
T.eq(TR.animFrame(), 12, "native tile animation clock is unchanged")
P.tier = "high"
TR.tick(1 / 60)
renderer:syncGen3Palettes()
T.eq(ticks[#ticks], 13, "raising tier resumes current full-rate palette")
P.tier = "low"
P.lowTierBudget = false
TR.tick(1 / 60)
renderer:syncGen3Palettes()
T.eq(ticks[#ticks], 14, "rollback restores full palette refresh at LOW")
P.lowTierBudget = true
local Version = require("src.core.GameVersion")
Version.set("emerald")
local f = require("tests.world_draw.fixture").new(8)
P.tier = "high"
f.world:drawWorld()
local high = f.trace()
f.reset()
P.tier = "low"
f.world:drawWorld()
local function essentials(trace)
  local rows = {}
  for _, row in ipairs(trace) do
    if not row:match("^reflection:") and not row:match("^drawReflectionCover:") then
      rows[#rows + 1] = row
    end
  end
  return rows
end
T.same(essentials(f.trace()), essentials(high), "LOW preserves entity, terrain, ripple and FX order/coordinates")
for _, row in ipairs(f.trace()) do
  T.check(not row:match("^reflection:"), "LOW skips native actor reflections")
end
f.reset()
P.tier = "high"
f.world:drawWorld()
T.same(f.trace(), high, "raising tier restores full world reflection trace")
local Discord = require("src.core.DiscordPresence")
local state
for i = 1, 100 do
  local name, value = debug.getupvalue(Discord.update, i)
  if name == "state" then
    state = value
    break
  end
end
T.check(state ~= nil, "presence state seam exists")
state.enabled = true
state.connected = true
state.socket = nil
P.tier = "low"
Discord.update(0)
T.eq(state.connected, false, "LOW retires connected IPC without polling")
local allocations, viewports = 0, {}
love.graphics.newQuad = function(x, y, w, h, iw, ih)
  allocations = allocations + 1
  local q = {}
  function q:setViewport(...)
    self.viewport = { ... }
    viewports[#viewports + 1] = self.viewport
  end
  q:setViewport(x, y, w, h, iw, ih)
  return q
end
local Ui = require("src.render.UiQuad")
local a, b = {}, {}
local qa = Ui.get(a, "slot", nil, 0, 0, 8, 8, 64, 64)
T.eq(Ui.get(a, "slot", nil, 8, 0, 16, 8, 128, 64), qa, "owner slot reuses its quad")
T.same(qa.viewport, { 8, 0, 16, 8, 128, 64 }, "viewport tracks geometry and source extent")
T.check(Ui.get(b, "slot", nil, 0, 0, 8, 8, 64, 64) ~= qa, "owners do not share scratch quads")
T.check(Ui.get(a, "other", nil, 0, 0, 8, 8, 64, 64) ~= qa, "draw sites do not share scratch quads")
T.eq(allocations, 3, "stable owner/site has bounded quad allocation")
P.lowTierBudget = false
T.check(Ui.get(a, "slot", nil, 0, 0, 8, 8, 64, 64) ~= qa, "rollback restores fresh native quads")
P.lowTierBudget = true
P.tier = "high"
T.finish("LOW presentation caps, pixel policy and private UI quads")
