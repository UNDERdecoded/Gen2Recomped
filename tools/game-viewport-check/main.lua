-- Real Game:draw, Renderer, public API-3 mod and screenshot readback.
function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n" .. debug.traceback() .. "\n")
  return function()
    love.event.quit(1)
  end
end
local root = love.filesystem.getSource():match("^(.*)/tools/game%-viewport%-check$")
  or love.filesystem.getWorkingDirectory()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
love.filesystem.mount(root, "", true)
local Contract = require("tests.api3_contract.viewport")
local Renderer = require("src.render.Renderer")
local V = require("src.render.GameViewport")
local Game = require("src.core.Game")
local Touch = require("src.core.TouchControls")
local Palette = require("src.render.PaletteFX")
local GBC = require("src.render.GBCFX")
local versions = { "red", "gold", "firered" }
local index, phase, checks, waiting = 1, 1, 0, false
local fixture, game, baseline, foreign, shader
local function check(ok, message)
  checks = checks + 1
  assert(ok, message .. " (" .. versions[index] .. "/" .. phase .. ")")
end
local function near(a, b)
  return math.abs(a - b) < 1.1 / 255
end
local function scene(self)
  Renderer:setUISize(160, 144)
  Renderer:beginFrame()
  local G = love.graphics
  G.clear(1, 1, 1, 1)
  G.setColor(0.2, 0.2, 0.2, 1)
  G.rectangle("fill", 0, 0, 80, 72)
  G.setColor(0.7, 0.7, 0.7, 1)
  G.rectangle("fill", 80, 72, 80, 72)
  G.setColor(1, 1, 1, 1)
  Renderer:endFrame()
  fixture.exports.canvas(V.target())
end
local function start()
  V.reset()
  Renderer:init()
  Palette.setMode("dmg")
  GBC.setLevel(0)
  fixture = Contract.fixture(root .. "/tests/api3_contract", "gen2", versions[index])
  game = fixture.game
  setmetatable(game, { __index = Game })
  game._draw = scene
  game.save.options = {}
end
function love.load()
  local ok, why = xpcall(function()
    shader =
      love.graphics.newShader([[vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){return vec4(1.0,0.0,0.0,1.0);}]])
    foreign = love.graphics.newCanvas(4, 4)
    Touch.draw = function()
      if phase > 1 then
        local G = love.graphics
        G.setColor(0, 1, 0, 1)
        G.rectangle("fill", 0, 0, 12, 12)
        G.setColor(1, 1, 1, 1)
      end
    end
    start()
  end, debug.traceback)
  if not ok then
    error(why)
  end
end
local function expected(pixels, rectangle, blue)
  local pw, ph = pixels:getDimensions()
  local dx, dy = pw / 320, ph / 288
  for y = 0, ph - 1 do
    for x = 0, pw - 1 do
      local target
      if x < 12 * dx and y < 12 * dy then
        target = { 0, 1, 0, 1 }
      elseif
        rectangle
        and (
          x < rectangle.x * dx
          or y < rectangle.y * dy
          or x >= (rectangle.x + rectangle.width) * dx
          or y >= (rectangle.y + rectangle.height) * dy
        )
      then
        target = blue and { 0, 0, 1, 1 } or { 0, 0, 0, 1 }
      else
        local bx, by = x, y
        if rectangle then
          bx = math.floor((x - rectangle.x * dx) * baseline:getWidth() / (rectangle.width * dx))
          by = math.floor((y - rectangle.y * dy) * baseline:getHeight() / (rectangle.height * dy))
        end
        target = { baseline:getPixel(bx, by) }
      end
      local got = { pixels:getPixel(x, y) }
      for channel = 1, 4 do
        check(near(got[channel], target[channel]), "frame pixel " .. x .. "," .. y .. " channel " .. channel)
      end
    end
  end
end
function love.draw()
  if waiting then
    return
  end
  waiting = true
  local ok, why = xpcall(function()
    fixture.exports.window(nil)
    local rectangle
    if phase >= 2 and phase <= 5 then
      rectangle = { x = 80, y = 72, width = 160, height = 144 }
    elseif phase == 7 then
      rectangle = { x = 0, y = 0, width = 320, height = 288, capture = true }
    elseif phase == 8 then
      rectangle = { x = 0, y = 0, width = 160, height = 144 }
    elseif phase == 9 then
      rectangle = { x = 20, y = 20, width = 161, height = 144 }
    end
    fixture.exports.request(rectangle)
    if phase == 3 then
      fixture.exports.window(function(next, g, ctx)
        love.graphics.setColor(0, 0, 1, 1)
        love.graphics.rectangle("fill", 0, 0, ctx.windowWidth, ctx.windowHeight)
        return next(g, ctx)
      end)
    end
    if phase == 4 then
      fixture.exports.window(function()
        local G = love.graphics
        G.push("all")
        G.setCanvas(foreign)
        G.setShader(shader)
        G.translate(50, 70)
        error("injected window compositor failure")
      end)
    end
    if phase == 5 then
      fixture.exports.window(function(next, g, ctx)
        V.reset()
        return next(g, ctx)
      end)
    end
    local G = love.graphics
    local oldNew = G.newCanvas
    if phase == 9 then
      G.newCanvas = function()
        error("injected viewport allocation failure")
      end
    end
    local depth = G.getStackDepth()
    local drawn, err = xpcall(function()
      Game.draw(game)
    end, debug.traceback)
    G.newCanvas = oldNew
    if not drawn then
      error(err)
    end
    check(G.getCanvas() == nil, "OS window is final target")
    check(G.getShader() == nil, "window compositor cannot leak shader")
    check(G.getStackDepth() == depth, "graphics stack balanced")
    local x, y = G.transformPoint(0, 0)
    check(x == 0 and y == 0, "window transform restored")
    if phase == 1 then
      check(not V.active() and V.target() == nil, "default path has no viewport target")
    end
    if phase == 5 or phase == 9 then
      check(not V.active(), "retirement/allocation failure clears capture")
    end
    G.captureScreenshot(function(pixels)
      local good, problem = xpcall(function()
        if phase == 1 then
          baseline = pixels
        else
          local expectedRectangle = rectangle
          if phase == 9 then
            expectedRectangle = nil
          end
          expected(pixels, expectedRectangle, phase == 3)
          pixels:release()
        end
        phase = phase + 1
        if phase == 10 then
          baseline:release()
          index = index + 1
          phase = 1
          if index > #versions then
            print("GAME VIEWPORT GPU: " .. checks .. " checks passed across Red/Gold/FireRed")
            local a, b, c, d = G.getRendererInfo()
            print(table.concat({ a, b, c, d }, " | "))
            love.event.quit(0)
            return
          end
          start()
        end
        waiting = false
      end, debug.traceback)
      if not good then
        io.stderr:write(problem .. "\n")
        love.event.quit(1)
      end
    end)
  end, debug.traceback)
  if not ok then
    io.stderr:write(why .. "\n")
    love.event.quit(1)
  end
end
