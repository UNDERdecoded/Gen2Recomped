package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Contract = require("tests.api3_contract.viewport")
local Runtime = require("src.mods.Runtime")
local Version = require("src.core.GameVersion")
local V = require("src.render.GameViewport")
local Game = require("src.core.Game")
local Touch = require("src.core.TouchControls")
local Safe = require("src.core.SafeArea")
local saved = { Version.get(), Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod, love }
for _, v in ipairs({ "red", "blue", "yellow", "gold", "silver", "crystal", "firered", "emerald" }) do
  local ok, why = pcall(Contract.run, "tests/api3_contract", "gen2", v)
  T.check(ok, v .. " shared viewport/window contract: " .. tostring(why))
end
local G = love.graphics
local dimensions, pixels = G.getDimensions, G.getPixelDimensions
G.getDimensions = function()
  return 640, 480
end
G.getPixelDimensions = function()
  return 1280, 960
end
local function fixture()
  V.finish({})
  V.reset()
  local f = Contract.fixture("tests/api3_contract", "gen2", "red")
  return f
end
local function begin(f, value)
  f.exports.request(value)
  local r = V.begin(1)
  f.exports.canvas(V.target())
  return r
end
for _, value in ipairs({
  { x = -20, y = -40, width = 10000, height = 10000 },
  { x = 1 / 0, y = 0 / 0, width = -3, height = 0 },
  { x = 639.9, y = 479.9, width = 320, height = 288 },
  setmetatable({}, {
    __index = function()
      error("metatable must not execute")
    end,
  }),
}) do
  local f = fixture()
  local r = begin(f, value)
  T.check(r.x >= 0 and r.y >= 0 and r.width >= 1 and r.height >= 1, "clamped viewport bounds")
  T.check(r.x + r.width <= 640 and r.y + r.height <= 480, "viewport stays inside window")
  V.finish(f.game)
end
do
  local f = fixture()
  local creates, releases = 0, 0
  local oldNew = G.newCanvas
  G.newCanvas = function(...)
    creates = creates + 1
    local c = oldNew(...)
    c.release = function()
      releases = releases + 1
    end
    return c
  end
  begin(f, { x = 10, y = 20, width = 320, height = 288 })
  V.finish(f.game)
  begin(f, { x = 11, y = 21, width = 320, height = 288 })
  V.finish(f.game)
  T.eq(creates, 1, "moving rectangle reuses same-size canvas")
  begin(f, { width = 321, height = 288 })
  V.finish(f.game)
  T.eq(creates, 2, "resize allocates matching canvas")
  T.eq(releases, 1, "resize releases old target")
  begin(f, nil)
  V.finish(f.game)
  T.eq(releases, 2, "disabling releases viewport target")
  G.newCanvas = oldNew
end
do
  local f = fixture()
  local oldNew = G.newCanvas
  local attempts = 0
  G.newCanvas = function()
    attempts = attempts + 1
    error("injected allocation failure")
  end
  local r = begin(f, { x = 10, y = 20, width = 100, height = 80 })
  T.eq(V.active(), false, "allocation failure keeps ordinary rendering")
  T.eq(r.width, 640, "failed viewport falls back to full width")
  V.finish(f.game)
  begin(f, { x = 10, y = 20, width = 100, height = 80 })
  V.finish(f.game)
  T.eq(attempts, 1, "failed size does not retry every frame")
  G.newCanvas = oldNew
  begin(f, { width = 101, height = 80 })
  V.finish(f.game)
  T.eq(V.active(), true, "changed request retries successfully")
  begin(f, { width = 100, height = 80 })
  V.finish(f.game)
  T.eq(V.active(), true, "former failed size can recover after request change")
end
do
  local f = fixture()
  local n = #f.exports.trace().viewport
  V.begin(4, false)
  V.finish(f.game)
  T.eq(V.active(), false, "unsupported/native combined layout stays direct")
  T.eq(#f.exports.trace().viewport, n, "unsupported layout does not dispatch viewport request")
  begin(f, { x = 100, y = 20, width = 320, height = 288 })
  local x, y, w, h = Safe.rect()
  T.eq(x, 0, "safe area mapped to local x")
  T.eq(y, 0, "safe area mapped to local y")
  T.eq(w, 320, "safe area clipped to game width")
  T.eq(h, 288, "safe area clipped to game height")
  local ox, oy, ow, oh = Safe.windowRect()
  T.eq(ow, 640, "OS chrome keeps full window width")
  T.eq(oh, 480, "OS chrome keeps full window height")
  V.finish(f.game)
end
for _, phase in ipairs({ "viewport", "window", "window_context" }) do
  local f = fixture()
  local shader, foreign = {}, {}
  G.setShader(shader)
  G.setColor(0.2, 0.3, 0.4, 0.5)
  local mod = f.loader.apis.viewport
  if phase == "viewport" then
    mod.hooks:wrap("render.viewport", function(next, ctx)
      G.setShader({})
      G.setCanvas(foreign)
      G.push("all")
      ctx.width = 0
      error("injected viewport hook error")
    end, 100)
  elseif phase == "window" then
    f.exports.window(function()
      G.setShader({})
      G.setCanvas(foreign)
      G.push("all")
      error("injected window hook error")
    end)
  else
    f.exports.window(function(next, g)
      return next(g, { canvas = false, x = 0, y = 0 })
    end)
  end
  begin(f, { x = 100, y = 20, width = 320, height = 288 })
  V.finish(f.game)
  T.eq(G.getCanvas(), nil, "window target restored after " .. phase .. " failure")
  T.eq(G.getShader(), shader, "shader restored after " .. phase .. " failure")
  T.eq(select(1, G.getColor()), 0.2, "color restored after " .. phase .. " failure")
end
do
  local f = fixture()
  local resetInside = false
  begin(f, { capture = true })
  local canvas = V.target()
  canvas.release = function()
    resetInside = true
  end
  f.exports.window(function(next, game, ctx)
    V.reset()
    T.eq(resetInside, false, "reset inside render callback defers canvas release")
    return next(game, ctx)
  end)
  V.finish(f.game)
  T.eq(resetInside, true, "retired target released after composition")
  T.eq(V.active(), false, "deferred reset clears viewport state")
end
-- Actual native touch dispatch preserves pad and screen capture ownership.
do
  local f = fixture()
  begin(f, { x = 100, y = 20, width = 320, height = 288 })
  V.finish(f.game)
  local old = {
    Touch.visible,
    Touch.hitTest,
    Touch.touchpressed,
    Touch.touchmoved,
    Touch.touchreleased,
    Touch.draw,
    Touch.touches,
  }
  local pad, screen = {}, {}
  Touch.touches = {}
  Touch.visible = function()
    return true
  end
  Touch.hitTest = function(_, x, y)
    return x == 10 and y == 10
  end
  Touch.touchpressed = function(_, id, x, y)
    pad[#pad + 1] = { "pressed", id, x, y }
    if id == "pad" then
      Touch.touches[id] = true
    end
  end
  Touch.touchmoved = function(_, id, x, y)
    pad[#pad + 1] = { "moved", id, x, y }
  end
  Touch.touchreleased = function(_, id, x, y)
    pad[#pad + 1] = { "released", id, x, y }
    Touch.touches[id] = nil
  end
  local top = {}
  for _, name in ipairs({ "touchpressed", "touchmoved", "touchreleased" }) do
    top[name] = function(_, id, x, y)
      screen[#screen + 1] = { name, id, x, y }
      return true
    end
  end
  local game = setmetatable(
    { stack = {
      top = function()
        return top
      end,
    }, save = { options = {} } },
    { __index = Game }
  )
  local mod = f.loader.apis.viewport
  mod.hooks:wrap("render.window", function(next, g, ctx)
    return next(g, ctx)
  end, -100)
  mod.hooks:wrap("input.pointer", function(next, g, ctx)
    if ctx.id == "mod" or ctx.id == "native" and ctx.phase ~= "pressed" then
      return true
    end
    return next(g, ctx)
  end, 100)
  game:touchpressed("pad", 10, 10)
  game:touchmoved("pad", 20, 20)
  game:touchreleased("pad", 20, 20)
  T.eq(#f.exports.trace().pointer, 0, "virtual pad gesture never reaches mod pointer hook")
  T.eq(#pad, 3, "virtual pad keeps entire gesture")
  game:touchpressed("native", 132, 52, nil, nil, 0.5)
  game:touchmoved("native", 149, 63)
  game:touchreleased("native", 160, 64)
  T.eq(#screen, 3, "native screen retains gesture after mod later claims movement")
  T.eq(screen[1][3], 32, "native screen receives game-local x")
  T.eq(screen[1][4], 32, "native screen receives game-local y")
  T.eq(game.pointerOwners.native, nil, "native capture released")
  game:touchpressed("mod", 132, 52)
  game:touchmoved("mod", 149, 63)
  game:touchreleased("mod", 160, 64)
  T.eq(#screen, 3, "claimed mod gesture does not leak to native screen")
  T.eq(game.modPointers.mod, nil, "mod pointer released")
  game:touchpressed("outside", 99, 19)
  T.eq(#screen, 3, "outside viewport does not activate native screen")
  local last = pad[#pad]
  T.eq(last[3], 99, "pad fallback keeps physical x")
  T.eq(last[4], 19, "pad fallback keeps physical y")
  Touch.visible, Touch.hitTest, Touch.touchpressed, Touch.touchmoved, Touch.touchreleased, Touch.draw, Touch.touches =
    unpack(old)
end
V.finish({})
V.reset()
G.getDimensions, G.getPixelDimensions = dimensions, pixels
Version.set(saved[1])
Runtime.events, Runtime.hooks, Runtime.errors, Runtime.currentMod = saved[2], saved[3], saved[4], saved[5]
love = saved[6]
T.finish()
