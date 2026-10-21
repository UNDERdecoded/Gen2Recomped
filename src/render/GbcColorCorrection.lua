-- GBC display response adapted from SameBoy's GB_convert_rgb15 (CGB model,
-- neutral light temperature), revision 26a56bd6a122a6318a456abd80558408742d5adf.
-- Copyright (c) 2015-2026 Lior Halphon. Expat license: licenses/SameBoy.txt.
-- This is separate from GBCFX's grid/glare and never alters imported palettes.
local GameVersion = require("src.core.GameVersion")
local PaletteFX = require("src.render.PaletteFX")
local Logger = require("src.core.Logger")

local Correction = { mode = "off" }
Correction.MODES = { "off", "accurate", "harsh" }
Correction.LABELS = { off = "OFF", accurate = "ACCURATE", harsh = "HARSH" }

local CURVE = { 0,6,12,20,28,36,45,56,66,76,88,100,113,125,137,149,
  161,172,182,192,202,210,218,225,232,238,243,247,250,252,254,255 }
local floor = math.floor
local shader, output, failedTarget
local textures = {}

function Correction.normalize(mode)
  return (mode == "accurate" or mode == "harsh") and mode or "off"
end

function Correction.setMode(mode)
  Correction.mode = Correction.normalize(mode)
  failedTarget = nil
  if Correction.mode == "off" and output then
    output:release()
    output = nil
  end
end

function Correction.applyOptions(opts)
  Correction.setMode(opts and opts.gbcColorCorrection)
end

function Correction.cycle(mode, dir)
  mode = Correction.normalize(mode)
  for i, value in ipairs(Correction.MODES) do
    if value == mode then return Correction.MODES[(i - 1 + dir) % #Correction.MODES + 1] end
  end
end

-- Pure RGB555 -> RGB888 reference. Integer truncations in HARSH are deliberate
-- (SameBoy's uint8_t arithmetic); changing their order changes the palette.
function Correction.convert5(r, g, b, mode)
  mode = Correction.normalize(mode)
  if mode == "off" then
    return r * 8 + floor(r / 4), g * 8 + floor(g / 4), b * 8 + floor(b / 4)
  end
  r, g, b = CURVE[r + 1], CURVE[g + 1], CURVE[b + 1]
  if g ~= b then
    g = floor((((g / 255)^2.2 * 3 + (b / 255)^2.2) / 4)^(1 / 2.2) * 255 + 0.5)
  end
  if mode == "harsh" then
    local nr = floor(r * 15 / 16) + floor((g + b) / 32)
    local ng = floor(g * 15 / 16) + floor((r + b) / 32)
    local nb = floor(b * 15 / 16) + floor((r + g) / 32)
    return floor(nr * 117 / 255) + 45, floor(ng * 126 / 255) + 41,
      floor(nb * 119 / 255) + 38
  end
  return r, g, b
end

-- 32 blue slices, eight columns of 32x32 red/green tiles. Bilinear red/green
-- sampling plus blue interpolation preserves smooth gradients in mod art;
-- there is no per-frame quantization of the scene back down to five bits.
Correction.SHADER_SRC = [[
extern Image correctionLut;
vec2 lutCoord(vec2 rg, float blue) {
    vec2 tile = vec2(mod(blue, 8.0), floor(blue / 8.0));
    return (tile * 32.0 + rg + vec2(0.5)) / vec2(256.0, 128.0);
}
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
    vec4 pixel = Texel(texture, uv);
    vec3 rgb = clamp(pixel.rgb, 0.0, 1.0) * 31.0;
    float low = floor(rgb.b);
    vec3 a = Texel(correctionLut, lutCoord(rgb.rg, low)).rgb;
    vec3 b = Texel(correctionLut, lutCoord(rgb.rg, min(low + 1.0, 31.0))).rgb;
    return vec4(mix(a, b, fract(rgb.b)), pixel.a) * color;
}
]]

local function resources()
  if shader == false or textures[Correction.mode] == false then return false end
  local pixels
  local ok, err = pcall(function()
    if not shader then shader = love.graphics.newShader(Correction.SHADER_SRC) end
    if not textures[Correction.mode] then
      pixels = love.image.newImageData(256, 128)
      for b = 0, 31 do
        for g = 0, 31 do
          for r = 0, 31 do
            local nr, ng, nb = Correction.convert5(r, g, b, Correction.mode)
            pixels:setPixel((b % 8) * 32 + r, floor(b / 8) * 32 + g,
              nr / 255, ng / 255, nb / 255, 1)
          end
        end
      end
      local texture = love.graphics.newImage(pixels)
      texture:setFilter("linear", "linear")
      texture:setWrap("clamp", "clamp")
      textures[Correction.mode] = texture
    end
  end)
  if pixels then pixels:release() end
  if not ok then
    if not shader then shader = false end
    textures[Correction.mode] = false
    Logger.warn("GBC color correction unavailable: %s", tostring(err))
  end
  return ok
end

function Correction.active()
  if failedTarget or Correction.mode == "off" or not GameVersion.isGen2()
      or PaletteFX.monoMode() then return false end
  return resources()
end

-- Colour the native finished frame before mod post-processing and LCD FX.
-- OFF/unsupported returns the original surface without allocating a canvas.
function Correction.apply(canvas)
  if not Correction.active() then return canvas end
  local width, height = canvas:getDimensions()
  local dpi = canvas.getDPIScale and canvas:getDPIScale() or 1
  local ok, err = pcall(function()
    if not output or output:getWidth() ~= width or output:getHeight() ~= height
        or output:getDPIScale() ~= dpi then
      if output then output:release(); output = nil end
      output = love.graphics.newCanvas(width, height, { dpiscale = dpi })
      output:setFilter("nearest", "nearest")
    end
  end)
  if not ok then
    failedTarget = true
    Logger.warn("GBC color correction target unavailable: %s", tostring(err))
    return canvas
  end
  love.graphics.push("all")
  local rendered, drawError = pcall(function()
    love.graphics.setCanvas(output)
    love.graphics.origin()
    love.graphics.setScissor()
    love.graphics.setStencilTest()
    love.graphics.setDepthMode()
    love.graphics.setColorMask(true, true, true, true)
    love.graphics.setBlendMode("replace", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    shader:send("correctionLut", textures[Correction.mode])
    love.graphics.setShader(shader)
    love.graphics.draw(canvas, 0, 0)
  end)
  love.graphics.pop()
  if not rendered then
    failedTarget = true
    Logger.warn("GBC color correction draw failed: %s", tostring(drawError))
    return canvas
  end
  return output
end

return Correction
