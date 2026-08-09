-- Unit coverage for the render.compose seam (D14: a public-API test names
-- the hook, gate_hooks supplies the no-mod parity, docs/modding.md documents
-- it).  render.compose lets a mod take over window composition: a wrap that
-- returns true without calling next owns the whole window; a wrap that calls
-- next lets the engine's normal single-window composite run and decorates it.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")

local savedEvents, savedHooks = Runtime.events, Runtime.hooks
local bus = Hooks.new()
Runtime.hooks = bus

-- the shape Renderer:endFrame hands the hook
local function fakeCtx()
  return {
    renderer = {}, worldCanvas = {}, uiCanvas = {},
    worldActive = true, zones = {}, worldZones = nil,
    ww = 480, wh = 432, ox = 0, oy = 12, scale = 3,
    dpiX = 1, dpiY = 1, secondScreen = {},
  }
end

-- takeover: a mod drawing its own layout returns true and never calls next,
-- so the engine's vanilla composite is skipped entirely
do
  local vanillaRan, gotCtx = false, nil
  bus:wrap("render.compose", function(next, renderer, ctx)
    gotCtx = ctx
    return true
  end, 0, "ds-mod")
  local handled = Runtime.call("render.compose",
    function() vanillaRan = true; return false end,
    { tag = "renderer" }, fakeCtx())
  T.eq(handled, true, "a mod returning true signals full window takeover")
  T.eq(vanillaRan, false, "takeover skips the engine composite (vanilla not run)")
  T.check(gotCtx ~= nil and gotCtx.ww == 480 and gotCtx.secondScreen ~= nil,
    "the hook receives the frame ctx (metrics, canvases, secondScreen)")
  bus.chains["render.compose"] = nil
end

-- decorate: a mod calling next lets the engine composite run, and the
-- engine's not-handled return (false) flows back through the chain
do
  local vanillaRan = false
  bus:wrap("render.compose", function(next, renderer, ctx)
    return next()
  end, 0, "ds-mod")
  local handled = Runtime.call("render.compose",
    function() vanillaRan = true; return false end,
    { tag = "renderer" }, fakeCtx())
  T.eq(vanillaRan, true, "calling next runs the engine composite")
  T.eq(handled, false, "the engine's not-handled return flows back through next")
  bus.chains["render.compose"] = nil
end

Runtime.events, Runtime.hooks = savedEvents, savedHooks

T.finish("render_compose_seam")
