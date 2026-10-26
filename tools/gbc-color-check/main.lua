-- Run from the repo root: love tools/gbc-color-check
-- Synthetic RGB data only. Optional GBC_COLOR_CHECK_SHOT=/absolute/path.png
-- writes the final three-panel comparison; no game assets or saves are read.
local root = love.filesystem.getSource():match("^(.*)/tools/gbc%-color%-check$")
  or love.filesystem.getWorkingDirectory()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local C = require("src.render.GbcColorCorrection")
local Version = require("src.core.GameVersion")
local Palette = require("src.render.PaletteFX")
local Renderer = require("src.render.Renderer")
local Pipelines = require("src.render.Pipelines")
local FX = require("src.render.GBCFX")
local checks, failed, phase, capturing = 0, false, 1, false
local pictures = {}
local function check(ok, message)
  checks = checks + 1
  assert(ok, message)
end

local function canvasOf(data, dpi)
  local image = love.graphics.newImage(data)
  image:setFilter("nearest", "nearest")
  local target = love.graphics.newCanvas(data:getWidth(), data:getHeight(), { dpiscale = dpi or 1 })
  love.graphics.push("all")
  love.graphics.setCanvas(target)
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image)
  love.graphics.pop()
  image:release()
  return target
end

local function interpolate(r, g, b, mode)
  local p, base, f = { r * 31, g * 31, b * 31 }, {}, {}
  for i = 1, 3 do base[i] = math.floor(p[i]); f[i] = p[i] - base[i] end
  local out = { 0, 0, 0 }
  for dz = 0, 1 do for dy = 0, 1 do for dx = 0, 1 do
    local value = { C.convert5(math.min(31, base[1] + dx),
      math.min(31, base[2] + dy), math.min(31, base[3] + dz), mode) }
    local weight = (dx == 0 and 1 - f[1] or f[1])
      * (dy == 0 and 1 - f[2] or f[2]) * (dz == 0 and 1 - f[3] or f[3])
    for i = 1, 3 do out[i] = out[i] + value[i] * weight / 255 end
  end end end
  return out
end

local function near(actual, expected, tolerance)
  return math.abs(actual - expected) <= tolerance
end

local function run()
  for _, gles in ipairs({ false, true }) do
    local ok, reason = love.graphics.validateShader(gles, C.SHADER_SRC)
    check(ok, "shader validation: " .. tostring(reason))
  end
  Version.set("gold")
  Palette.setMode("gbc")
  local source = love.image.newImageData(256, 128)
  for n = 0, 32767 do
    local r, g, b = n % 32, math.floor(n / 32) % 32, math.floor(n / 1024)
    source:setPixel(n % 256, math.floor(n / 256),
      (r * 8 + math.floor(r / 4)) / 255,
      (g * 8 + math.floor(g / 4)) / 255,
      (b * 8 + math.floor(b / 4)) / 255, 1)
  end
  local input = canvasOf(source)
  source:release()
  C.setMode("off")
  check(C.apply(input) == input, "OFF must preserve the exact canvas")
  for _, mode in ipairs({ "accurate", "harsh" }) do
    C.setMode(mode)
    local corrected = C.apply(input)
    check(corrected ~= input, mode .. " did not run on the GPU")
    local pixels = corrected:newImageData()
    local maxError = 0
    for n = 0, 32767 do
      local expected = { C.convert5(n % 32, math.floor(n / 32) % 32, math.floor(n / 1024), mode) }
      local actual = { pixels:getPixel(n % 256, math.floor(n / 256)) }
      for i = 1, 3 do maxError = math.max(maxError, math.abs(actual[i] * 255 - expected[i])) end
    end
    pixels:release()
    check(maxError < 1.01, mode .. " RGB555 GPU error exceeds one RGB888 unit: " .. maxError)
    print(mode .. " GPU gamut max error: " .. maxError)
  end
  input:release()

  local gradient = love.image.newImageData(32, 1)
  for i = 0, 31 do gradient:setPixel(i, 0, (80 + i) / 255, 63 / 255, 143 / 255, 128 / 255) end
  input = canvasOf(gradient)
  gradient:release()
  C.setMode("accurate")
  local previous = love.graphics.newCanvas(4, 4)
  local oldShader = love.graphics.newShader("vec4 effect(vec4 c, Image t, vec2 u, vec2 p) { return Texel(t,u)*c; }")
  love.graphics.setCanvas(previous)
  love.graphics.setShader(oldShader)
  love.graphics.setColor(0.2, 0.3, 0.4, 0.5)
  love.graphics.setScissor(1, 2, 3, 4)
  love.graphics.setBlendMode("add", "premultiplied")
  love.graphics.setColorMask(false, true, false, true)
  love.graphics.translate(7, 9)
  local corrected = C.apply(input)
  check(love.graphics.getCanvas() == previous, "caller canvas was not restored")
  check(love.graphics.getShader() == oldShader, "caller shader was not restored")
  check(near(select(1, love.graphics.getColor()), 0.2, 1e-6), "caller colour was not restored")
  check(love.graphics.getScissor() == 1, "caller scissor was not restored")
  check(love.graphics.getBlendMode() == "add", "caller blend mode was not restored")
  check(love.graphics.getColorMask() == false, "caller colour mask was not restored")
  local x, y = love.graphics.transformPoint(0, 0)
  check(x == 7 and y == 9, "caller transform was not restored")
  love.graphics.setCanvas()
  love.graphics.setShader()
  love.graphics.setScissor()
  love.graphics.setBlendMode("alpha")
  love.graphics.setColorMask(true, true, true, true)
  love.graphics.origin()
  love.graphics.setColor(1, 1, 1, 1)
  local pixels = corrected:newImageData()
  local first, last
  for i = 0, 31 do
    local r, g, b, a = pixels:getPixel(i, 0)
    local expected = interpolate((80 + i) / 255, 63 / 255, 143 / 255, "accurate")
    check(near(r, expected[1], 1.01 / 255) and near(g, expected[2], 1.01 / 255)
      and near(b, expected[3], 1.01 / 255), "fractional RGB interpolation mismatch")
    check(near(a, 128 / 255, 0.01 / 255), "alpha changed")
    first, last = first or r, r
  end
  check(last > first, "true-colour gradient collapsed")
  pixels:release()
  input:release()
  oldShader:release()
  previous:release()
  for _, size in ipairs({ { 4, 4, 2 }, { 9, 7, 1 } }) do
    input = love.graphics.newCanvas(size[1], size[2], { dpiscale = size[3] })
    corrected = C.apply(input)
    check(corrected:getWidth() == size[1] and corrected:getHeight() == size[2], "resize lost dimensions")
    check(corrected:getDPIScale() == size[3], "DPI scale changed")
    input:release()
  end

  input = love.graphics.newCanvas(7, 3)
  local draw = love.graphics.draw
  love.graphics.draw = function() error("injected GPU draw failure") end
  check(C.apply(input) == input, "draw failure did not fall back to the source")
  love.graphics.draw = draw
  check(love.graphics.getCanvas() == nil and love.graphics.getShader() == nil,
    "draw failure leaked render state")
  check(not C.active(), "failed target should not retry every frame")
  C.setMode("accurate")
  check(C.active(), "changing the setting must allow a target retry")
  input:release()
  input = love.graphics.newCanvas(7, 5)
  local allocate = love.graphics.newCanvas
  love.graphics.newCanvas = function() error("injected allocation failure") end
  check(C.apply(input) == input, "allocation failure did not preserve the source")
  love.graphics.newCanvas = allocate
  check(not C.active(), "failed allocation should not retry every frame")
  input:release()
  C.setMode("accurate")

  -- Immutable copies for the synthetic, ROM-free visual comparison.
  for _, mode in ipairs({ "off", "accurate", "harsh" }) do
    source = love.image.newImageData(160, 144)
    for yy = 0, 143 do for xx = 0, 159 do
      local r, g, b
      if yy < 72 then
        r, g, b = xx / 159, yy / 71, 0.65
      else
        local shade = math.floor(xx / 20) / 7
        r, g, b = 0.35 * shade, 0.25 * shade, 0.7 * shade
      end
      source:setPixel(xx, yy, r, g, b, 1)
    end end
    input = canvasOf(source)
    source:release()
    C.setMode(mode)
    pixels = C.apply(input):newImageData()
    pictures[mode] = love.graphics.newImage(pixels)
    pictures[mode]:setFilter("nearest", "nearest")
    pixels:release()
    input:release()
  end
  C.setMode("off")
  Renderer:init()
end

function love.load()
  local ok, err = xpcall(run, debug.traceback)
  if not ok then failed = true; io.stderr:write(err .. "\n"); love.event.quit(1) end
end

-- Exercise the real endFrame path, not an isolated shader canvas: correction
-- alone, with LCD FX, and the original OFF path on separate rendered frames.
function love.draw()
  if failed or capturing then return end
  if phase <= 3 then
    local ok, err = xpcall(function()
      local trace = {}
      local oldApply, oldPresent, oldFX = C.apply, Pipelines.present, FX.present
      C.apply = function(canvas) trace[#trace + 1] = "correction"; return oldApply(canvas) end
      Pipelines.present = function(canvas, ctx) trace[#trace + 1] = "pipeline"; return oldPresent(canvas, ctx) end
      FX.present = function(canvas, scale) trace[#trace + 1] = "lcd"; return oldFX(canvas, scale) end
      C.setMode(phase < 3 and "accurate" or "off")
      FX.setLevel(phase == 2 and 4 or 0)
      Renderer:beginFrame()
      love.graphics.clear(0.35, 0.2, 0.7, 1)
      Renderer:endFrame()
      C.apply, Pipelines.present, FX.present = oldApply, oldPresent, oldFX
      local expected = phase == 1 and "correction,pipeline"
        or (phase == 2 and "correction,pipeline,lcd" or "")
      check(table.concat(trace, ",") == expected, "native pass order differs: " .. table.concat(trace, ","))
    end, debug.traceback)
    if not ok then failed = true; io.stderr:write(err .. "\n"); love.event.quit(1); return end
    local renderedPhase = phase
    capturing = true
    love.graphics.captureScreenshot(function(pixels)
      local verified, verifyError = xpcall(function()
        local r, g, b, a = pixels:getPixel(320, 288)
        check(near(a, 1, 1 / 255), "native frame alpha changed")
        if renderedPhase == 2 then
          check(math.max(r, g, b) > 0.02, "LCD combination presented a black frame")
        else
          local expected = renderedPhase == 1 and interpolate(0.35, 0.2, 0.7, "accurate")
            or { 0.35, 0.2, 0.7 }
          check(near(r, expected[1], 2.01 / 255) and near(g, expected[2], 2.01 / 255)
            and near(b, expected[3], 2.01 / 255), "native screen pixels do not match the selected profile")
        end
      end, debug.traceback)
      if not verified then failed = true; io.stderr:write(verifyError .. "\n"); love.event.quit(1) end
      phase, capturing = phase + 1, false
    end)
    return
  end
  love.graphics.clear(0.05, 0.05, 0.05, 1)
  love.graphics.setColor(1, 1, 1, 1)
  for i, mode in ipairs({ "off", "accurate", "harsh" }) do
    love.graphics.print(mode, 10 + (i - 1) * 210, 20)
    love.graphics.draw(pictures[mode], 10 + (i - 1) * 210, 50, 0, 1.25, 1.25)
  end
  print(checks .. " GPU checks passed (synthetic data)")
  capturing = true
  local path = os.getenv("GBC_COLOR_CHECK_SHOT")
  if path then
    love.graphics.captureScreenshot(function(data)
      local encoded = data:encode("png")
      local file = assert(io.open(path, "wb"))
      file:write(encoded:getString()); file:close()
      love.event.quit(0)
    end)
  else love.event.quit(0) end
end
