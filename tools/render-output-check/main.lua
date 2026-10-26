-- Actual Renderer, public API-3 mod, real GL draw/readback. No ROM or settings.
function love.errorhandler(message)
  io.stderr:write(tostring(message).."\n"..debug.traceback().."\n")
  return function() love.event.quit(1) end
end
local root = love.filesystem.getSource():match("^(.*)/tools/render%-output%-check$")
  or love.filesystem.getWorkingDirectory()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
love.filesystem.mount(root, "", true)
local Contract = require("tests.api3_contract.render_output")
local Renderer = require("src.render.Renderer")
local Palette = require("src.render.PaletteFX")
local GBCFX = require("src.render.GBCFX")
local checks, phase, waiting = 0, 1, false
local baseline, fixture, shader, foreign
local function check(ok, message)
  checks = checks + 1
  assert(ok, message)
end
local function near(a, b)
  return math.abs(a - b) < 1.1 / 255
end
local function compare(pixels, inverse, hud)
  check(
    pixels:getWidth() == baseline:getWidth() and pixels:getHeight() == baseline:getHeight(),
    "frame dimensions"
  )
  local pw, ph = pixels:getDimensions()
  for y = 0, ph - 1 do
    for x = 0, pw - 1 do
      local a, b = { pixels:getPixel(x, y) }, { baseline:getPixel(x, y) }
      if hud and x < 20 * (pw / 320) and y < 20 * (ph / 288) then
        b = { 0, 1, 0, 1 }
      elseif inverse then
        for i = 1, 3 do
          b[i] = 1 - b[i]
        end
      end
      for i = 1, 4 do
        check(near(a[i], b[i]), "GPU pixel " .. x .. "," .. y .. " channel " .. i .. " phase " .. phase)
      end
    end
  end
end
local function scene()
  Renderer:setUISize(160, 144)
  Renderer:beginFrame()
  local G = love.graphics
  G.clear(1, 1, 1, 1)
  G.setColor(0.2, 0.2, 0.2, 1)
  G.rectangle("fill", 0, 0, 80, 72)
  G.setColor(0.7, 0.7, 0.7, 1)
  G.rectangle("fill", 80, 72, 80, 72)
  G.setColor(1, 1, 1, 1)
end
function love.load()
  local ok, why = xpcall(function()
    Renderer:init()
    Palette.setMode("dmg")
    GBCFX.setLevel(0)
    fixture = Contract.fixture(root .. "/tests/api3_contract", "gen2", "red")
    shader = love.graphics.newShader(
      [[vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){vec4 s=Texel(t,uv);return vec4(vec3(1.0)-s.rgb,s.a)*c;}]]
    )
    foreign = love.graphics.newCanvas(4, 4)
  end, debug.traceback)
  if not ok then
    io.stderr:write(why .. "\n")
    love.event.quit(1)
  end
end
function love.draw()
  if waiting then
    return
  end
  waiting = true
  local ok, why = xpcall(function()
    fixture.exports.state(phase ~= 1 and phase ~= 7, true)
    fixture.exports.gate(nil)
    fixture.exports.callback(nil)
    if phase == 2 then
      fixture.exports.state(true, false)
    end
    if phase == 3 then
      fixture.exports.callback(function(ctx)
        love.graphics.draw(ctx.canvas)
        return true
      end)
    end
    if phase == 4 then
      fixture.exports.callback(function(ctx)
        local G = love.graphics
        G.setShader(shader)
        G.draw(ctx.canvas)
        G.push("all")
        G.translate(30, 40)
        G.setCanvas(foreign)
        G.setColor(1, 0, 0, 1)
        G.setBlendMode("add")
        return true
      end)
    end
    if phase == 5 then
      fixture.exports.callback(function()
        local G = love.graphics
        G.setCanvas(foreign)
        G.setShader(shader)
        G.translate(70, 90)
        error("injected output draw failure")
      end)
    end
    if phase == 6 then
      fixture.exports.gate(function()
        love.graphics.setShader(shader)
        love.graphics.setCanvas(foreign)
        return 1
      end)
    end
    if phase == 7 then
      fixture.loader:_rollback("render_output")
    end
    scene()
    local depth = love.graphics.getStackDepth()
    Renderer:endFrame()
    check(love.graphics.getCanvas() == nil, "frame target restored")
    check(love.graphics.getShader() == nil, "shader restored")
    check(love.graphics.getStackDepth() == depth, "graphics stack balanced")
    local x, y = love.graphics.transformPoint(0, 0)
    check(x == 0 and y == 0, "transform restored")
    if phase == 1 then
      check(Renderer.presentCanvas == nil, "disabled owner creates no present target")
    end
    if phase == 4 then
      love.graphics.setColor(0, 1, 0, 1)
      love.graphics.rectangle("fill", 0, 0, 20, 20)
      love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.captureScreenshot(function(pixels)
      local good, err = xpcall(function()
        if phase == 1 then
          baseline = pixels
        else
          compare(pixels, phase == 4, phase == 4)
          pixels:release()
        end
        phase = phase + 1
        if phase == 8 then
          print("RENDER OUTPUT GPU: " .. checks .. " checks passed")
          local a, b, c, d = love.graphics.getRendererInfo()
          print(table.concat({ a, b, c, d }, " | "))
          love.event.quit(0)
        end
        waiting = false
      end, debug.traceback)
      if not good then
        io.stderr:write(err .. "\n")
        love.event.quit(1)
      end
    end)
  end, debug.traceback)
  if not ok then
    io.stderr:write(why .. "\n")
    love.event.quit(1)
  end
end
