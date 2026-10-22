-- Run from the checkout: love tools/shader-preset-check
-- Synthetic pixels and the ROM-free font fixture; writes no game settings.
local root = love.filesystem.getSource():match("^(.*)/tools/shader%-preset%-check$")
  or love.filesystem.getWorkingDirectory()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
love.filesystem.mount(root, "", true)
local Presets = require("src.render.ShaderPresets")
local Json = require("src.link.Json")
local Renderer = require("src.render.Renderer")
local Pipelines = require("src.render.Pipelines")
local GBCFX = require("src.render.GBCFX")
local Correction = package.loaded["src.render.GbcColorCorrection"]
local Menu = require("src.ui.ShaderPresetMenu")
local Font = require("src.render.Font")
local Palette = require("src.render.PaletteFX")
local Version = require("src.core.GameVersion")
local checks = 0
local function check(ok, message)
  checks = checks + 1
  assert(ok, message)
end
local function near(a, b)
  return math.abs(a - b) < 1.1 / 255
end
local function equal(a, b, label)
  check(a:getWidth() == b:getWidth() and a:getHeight() == b:getHeight(), label .. " dimensions")
  for y = 0, a:getHeight() - 1 do
    for x = 0, a:getWidth() - 1 do
      local av, bv = { a:getPixel(x, y) }, { b:getPixel(x, y) }
      for i = 1, 4 do
        check(near(av[i], bv[i]), label .. " pixel " .. x .. "," .. y .. " channel " .. i)
      end
    end
  end
end
local files = {}
local fs = {
  getDirectoryItems = function()
    return { "identity.json", "bad.json", "sizes.json" }
  end,
  getInfo = function(p)
    if files[p] then
      return { type = "file", size = #files[p] }
    end
  end,
  read = function(p)
    return files[p]
  end,
}
local identity = "vec4 effect(vec4 c, Image t, vec2 u, vec2 p) { return Texel(t,u)*c; }"
files["shader-presets/identity.json"] =
  Json.encode({ format = 1, name = "IDENTITY", shader = "identity.glsl" })
files["shader-presets/identity.glsl"] = identity
files["shader-presets/bad.json"] = Json.encode({ format = 1, name = "BAD SHADER", shader = "bad.glsl" })
files["shader-presets/bad.glsl"] = "THIS IS NOT GLSL"
files["shader-presets/sizes.json"] = Json.encode({ format = 1, name = "DIMENSIONS", shader = "sizes.glsl" })
files["shader-presets/sizes.glsl"] = [[
extern vec2 sourceSize;
extern number pixelScale;
vec4 effect(vec4 c, Image t, vec2 u, vec2 p) { return vec4(sourceSize / 1024.0,pixelScale / 16.0,1.0); }
]]
Presets.fs = fs
local panels = {}
local function inputCanvas(w, h, dpi)
  local pw, ph = math.floor(w * dpi + 0.5), math.floor(h * dpi + 0.5)
  local pixels = love.image.newImageData(pw, ph)
  for y = 0, ph - 1 do
    for x = 0, pw - 1 do
      pixels:setPixel(x, y, x / (pw - 1), y / (ph - 1), 0.4, (x % 3 + 1) / 3)
    end
  end
  local image = love.graphics.newImage(pixels)
  local canvas = love.graphics.newCanvas(w, h, { dpiscale = dpi })
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(image, 0, 0, 0, 1 / dpi, 1 / dpi)
  love.graphics.pop()
  image:release()
  return canvas, pixels
end
local function run()
  -- Exercise the actual mounted game-data filesystem, not only injected fs.
  local dir = "shader-presets"
  love.filesystem.createDirectory(dir)
  local descriptor = dir .. "/qa_disk_roundtrip.json"
  local fragment = dir .. "/qa_disk_roundtrip.glsl"
  assert(
    love.filesystem.write(
      descriptor,
      Json.encode({ format = 1, name = "DISK CHECK", shader = "qa_disk_roundtrip.glsl" })
    )
  )
  assert(love.filesystem.write(fragment, identity))
  local disk = Presets.new()
  disk:refresh()
  check(disk.byId["local:qa_disk_roundtrip"] ~= nil, "real filesystem discovery")
  check(disk:activate("local:qa_disk_roundtrip"), "real filesystem source read and compile")
  disk:off()
  love.filesystem.remove(descriptor)
  love.filesystem.remove(fragment)

  for _, entry in ipairs(Presets:refresh()) do
    if entry.source then
      for _, gles in ipairs({ false, true }) do
        local ok, why = love.graphics.validateShader(gles, entry.source)
        check(ok, "GL/GLES shader validation " .. entry.id .. ": " .. tostring(why))
      end
    end
  end
  for _, dpi in ipairs({ 1, 2, 2.75 }) do
    local input, original = inputCanvas(32, 24, dpi)
    Presets:off()
    check(Presets:apply(input, 4) == input, "OFF returns exact input")
    check(Presets.output == nil, "OFF no target")
    assert(Presets:activate("local:identity"))
    local pixels = Presets:apply(input, 4):newImageData()
    equal(pixels, original, "identity DPI " .. dpi)
    pixels:release()
    local opts = {}
    assert(Presets:select(opts, "builtin:warm"))
    for _, strength in ipairs({ 0, 0.4, 1 }) do
      assert(Presets:setParameter(opts, "strength", strength))
      local out = Presets:apply(input, 4)
      check(out:getDPIScale() == input:getDPIScale(), "preserves DPI")
      pixels = out:newImageData()
      for y = 0, pixels:getHeight() - 1 do
        for x = 0, pixels:getWidth() - 1 do
          local r, g, b, a = original:getPixel(x, y)
          local actual = { pixels:getPixel(x, y) }
          local expected = { r, g * (1 - 0.06 * strength), b * (1 - 0.2 * strength), a }
          for i = 1, 4 do
            check(near(actual[i], expected[i]), "warm RGB/alpha at DPI " .. dpi)
          end
        end
      end
      pixels:release()
    end
    assert(Presets:select(opts, "builtin:soft-lcd"))
    assert(Presets:setParameter(opts, "strength", 0.5))
    pixels = Presets:apply(input, 4):newImageData()
    for y = 0, pixels:getHeight() - 1 do
      for x = 0, pixels:getWidth() - 1 do
        local expected = { original:getPixel(x, y) }
        local scale = 1 - 0.5 * (math.floor((y + 0.5) / 4) % 2)
        local actual = { pixels:getPixel(x, y) }
        for i = 1, 3 do
          check(near(actual[i], expected[i] * scale), "LCD grid pixel scale at DPI " .. dpi)
        end
        check(near(actual[4], expected[4]), "LCD alpha preserved")
      end
    end
    pixels:release()
    assert(Presets:activate("local:sizes"))
    pixels = Presets:apply(input, 6):newImageData()
    local r, g, b = pixels:getPixel(0, 0)
    check(
      near(r, original:getWidth() / 1024) and near(g, original:getHeight() / 1024) and near(b, 6 / 16),
      "physical source size uniforms"
    )
    pixels:release()
    original:release()
    input:release()
  end
  -- Real graphics state is restored, even when a draw throws after setup.
  local input, original = inputCanvas(12, 8, 1)
  assert(Presets:activate("builtin:warm"))
  local previous = love.graphics.newCanvas(4, 4)
  local shader = love.graphics.newShader(identity)
  love.graphics.setCanvas(previous)
  love.graphics.setShader(shader)
  love.graphics.translate(3, 5)
  love.graphics.setColor(0.2, 0.3, 0.4, 0.5)
  love.graphics.setScissor(1, 2, 2, 1)
  love.graphics.setBlendMode("add", "premultiplied")
  local depth = love.graphics.getStackDepth()
  local realDraw = love.graphics.draw
  love.graphics.draw = function()
    error("injected GPU draw failure")
  end
  check(Presets:apply(input, 2) == input, "draw failure identity fallback")
  love.graphics.draw = realDraw
  check(not Presets:active(), "broken effect retired")
  check(
    love.graphics.getCanvas() == previous and love.graphics.getShader() == shader,
    "canvas/shader restored"
  )
  check(love.graphics.getStackDepth() == depth, "stack restored")
  local r, g, b, a = love.graphics.getColor()
  check(near(r, 0.2) and near(g, 0.3) and near(b, 0.4) and near(a, 0.5), "color restored")
  local x, y = love.graphics.transformPoint(0, 0)
  check(x == 3 and y == 5, "transform restored")
  local blend, alpha = love.graphics.getBlendMode()
  check(blend == "add" and alpha == "premultiplied", "blend restored")
  local sx, sy, sw, sh = love.graphics.getScissor()
  check(sx == 1 and sy == 2 and sw == 2 and sh == 1, "scissor restored")
  love.graphics.setCanvas()
  love.graphics.setShader()
  love.graphics.origin()
  love.graphics.setScissor()
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  previous:release()
  shader:release()
  input:release()
  original:release()
  local opts = { shaderPreset = "builtin:warm" }
  assert(Presets:applyOptions(opts))
  local old = Presets.shader
  check(not Presets:select(opts, "local:bad"), "real compile error rejected")
  check(
    Presets.shader == old and opts.shaderPreset == "builtin:warm",
    "bad selection retains last working effect"
  )
  Presets:off()
  GBCFX.setLevel(0)
  Palette.setMode("dmg")
  Version.set("red")
  local fixture = require("tests.modkit.fixtures").fresh()
  fixture.font.source = "Gen2 scaffold"
  Font.load(fixture)
  Renderer:init()
end
local phase, capturing, baseline = 1, false, nil
local resizeBaseline
function love.load()
  local ok, err = xpcall(run, debug.traceback)
  if not ok then
    io.stderr:write(err .. "\n")
    love.event.quit(1)
  end
end
local function drawScene()
  Renderer:setUISize(
    phase >= 9 and 256 or phase >= 7 and 240 or 160,
    phase >= 9 and 192 or phase >= 7 and 160 or 144
  )
  Renderer:beginFrame()
  love.graphics.clear(1, 1, 1, 1)
  love.graphics.setColor(0.15, 0.35, 0.7, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 72)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw("SHADER PRESET TEST", 8, 88)
  Font.draw("WORLD + DIALOGUE", 8, 104)
  love.graphics.setColor(1, 1, 1, 1)
end
function love.draw()
  if phase == 11 then
    love.graphics.clear(0.2, 0.2, 0.2, 1)
    love.graphics.setColor(1, 1, 1, 1)
    for i, image in ipairs(panels) do
      love.graphics.draw(
        image,
        ((i - 1) % 3) * 320,
        math.floor((i - 1) / 3) * 288,
        0,
        320 / image:getWidth(),
        288 / image:getHeight()
      )
    end
    if not capturing then
      capturing = true
      love.graphics.captureScreenshot(function(pixels)
        local path = os.getenv("SHADER_PRESET_CHECK_SHOT")
        if path then
          local png = pixels:encode("png")
          local f = assert(io.open(path, "wb"))
          f:write(png:getString())
          f:close()
          png:release()
        end
        pixels:release()
        print(("SHADER PRESETS GPU: %d checks passed"):format(checks))
        love.event.quit(0)
      end)
    end
    return
  end
  if capturing then
    return
  end
  local ok, err = xpcall(function()
    local trace = {}
    if phase == 1 or phase == 4 or phase == 7 or phase == 9 then
      Presets:off()
    elseif phase == 2 or phase == 8 or phase == 10 then
      assert(Presets:activate("local:identity"))
    elseif phase == 3 then
      assert(Presets:activate("builtin:warm", { strength = 1 }))
    elseif phase == 5 then
      assert(Presets:activate("builtin:soft-lcd", { strength = 0.3 }))
    end
    drawScene()
    local oldP, oldS, oldF = Pipelines.present, Presets.apply, GBCFX.present
    local oldC = Correction and Correction.apply
    if Correction then
      if phase == 5 then
        Version.set("gold")
      elseif phase == 6 then
        Version.set("red")
      end
      Palette.setMode(phase == 5 and "gbc" or "dmg")
      Correction.setMode(phase == 5 and "accurate" or "off")
      if phase == 5 then
        check(Correction.active(), "colour correction and preset active together")
      end
      Correction.apply = function(...)
        trace[#trace + 1] = "correction"
        return oldC(...)
      end
    end
    Pipelines.present = function(...)
      trace[#trace + 1] = "pipeline"
      return oldP(...)
    end
    Presets.apply = function(...)
      trace[#trace + 1] = "preset"
      return oldS(...)
    end
    GBCFX.present = function(...)
      trace[#trace + 1] = "gbc"
      return oldF(...)
    end
    GBCFX.setLevel(phase == 5 and 1 or 0)
    Renderer.shaderPresetBypass = phase == 6
    if phase == 6 then
      local game = {
        data = require("tests.modkit.fixtures").fresh(),
        save = { options = { shaderPreset = "builtin:soft-lcd" } },
        stack = {},
      }
      Menu.new(game):draw()
    end
    Renderer:endFrame()
    Pipelines.present, Presets.apply, GBCFX.present = oldP, oldS, oldF
    if Correction then
      Correction.apply = oldC
    end
    if phase == 5 then
      check(
        table.concat(trace, ",") == (Correction and "correction,pipeline,preset,gbc" or "pipeline,preset,gbc"),
        "final stage ordering"
      )
    end
    if phase == 6 then
      check(not table.concat(trace, ","):find("preset", 1, true), "shader controls bypass preset")
    end
    capturing = true
    love.graphics.captureScreenshot(function(pixels)
      local captured, why = xpcall(function()
        if phase == 1 then
          baseline = pixels:clone()
        elseif phase == 2 or phase == 4 then
          equal(pixels, baseline, "Renderer identity/OFF")
        elseif phase == 3 then
          local changed = false
          for y = 0, pixels:getHeight() - 1, 8 do
            for x = 0, pixels:getWidth() - 1, 8 do
              local _, g, b = pixels:getPixel(x, y)
              local _, bg, bb = baseline:getPixel(x, y)
              if math.abs(g - bg) > 0.01 or math.abs(b - bb) > 0.01 then
                changed = true
              end
            end
          end
          check(changed, "Renderer active preset changes final frame")
        end
        if phase == 7 or phase == 9 then
          if resizeBaseline then
            resizeBaseline:release()
          end
          resizeBaseline = pixels:clone()
        elseif phase == 8 or phase == 10 then
          equal(pixels, resizeBaseline, "Renderer resized native surface identity")
        end
        if phase <= 6 then
          local image = love.graphics.newImage(pixels)
          image:setFilter("nearest", "nearest")
          panels[#panels + 1] = image
        end
        pixels:release()
        phase = phase + 1
        capturing = false
        if phase == 7 then
          Version.set("emerald")
          love.window.setMode(480, 432, { highdpi = true })
        elseif phase == 9 then
          Version.set("platinum")
          love.window.setMode(800, 600, { highdpi = true })
        elseif phase == 11 then
          love.window.setMode(960, 576, { resizable = false })
        end
      end, debug.traceback)
      if not captured then
        io.stderr:write(why .. "\n")
        love.event.quit(1)
      end
    end)
  end, debug.traceback)
  if not ok then
    io.stderr:write(err .. "\n")
    love.event.quit(1)
  end
end
