-- Original contributions (c) 2026 Roxas2712; offered to UNDERdecoded under
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Indexed image drawing, separate from the LCD post-process in GBCFX.
-- Palette resolution uses the native display/register state in PaletteFX.
local Palettes = require("src.render.PaletteFX")
local Version = require("src.core.GameVersion")
local M = {}
-- Consumers use this view to leave already-coloured pictures untouched.
-- Gen2 currently resolves native ROM colours regardless of the Gen1 mode.
-- Do not invent a second mutable display setting for the external renderer.
setmetatable(M, {__index = function(_, key)
  if key == "mode" then
    if Version.isGen2() then return "gbc" end
    if Palettes.mode == "og" or Palettes.mode == "og_inv" then return "dmg" end
    return Palettes.mode == "classic" and "classic" or "gbc"
  end
end})
local compiler, shaders, failed = nil, {}, {}
local sent = setmetatable({}, {__mode = "k"})
local names = {"pal0", "pal1", "pal2", "pal3"}
local source = [[
extern vec3 pal0; extern vec3 pal1; extern vec3 pal2; extern vec3 pal3;
vec4 effect(vec4 tint, Image image, vec2 uv, vec2 screen) {
  vec4 pixel = Texel(image, uv);
  float shade = floor((1.0 - pixel.r) * 3.0 + 0.5);
  vec3 rgb = shade < 0.5 ? pal0 : (shade < 1.5 ? pal1 : (shade < 2.5 ? pal2 : pal3));
  return vec4(rgb, ALPHA) * tint;
}
]]

local function graphics() return love and love.graphics end
local function shader(keyed)
  local g = graphics()
  local newShader = g and g.newShader
  if type(newShader) ~= "function" then return nil end
  if compiler ~= newShader then
    compiler, shaders, failed = newShader, {}, {}
  end
  local key = keyed and "keyed" or "normal"
  if failed[key] then return nil end
  if not shaders[key] then
    local alpha = keyed and "(shade < 0.5 ? 0.0 : pixel.a)" or "pixel.a"
    local ok, value = pcall(newShader, (source:gsub("ALPHA", alpha)))
    if not ok or not value then failed[key] = true; return nil end
    shaders[key] = value
  end
  return shaders[key]
end
function M.shader() return shader(false) end
function M.keyedShader() return shader(true) end
function M.available() return M.shader() ~= nil end

local function copy(colors)
  if type(colors) ~= "table" then return nil end
  local out = {}
  for i = 1, 4 do
    local color = colors[i]
    if type(color) ~= "table" then return nil end
    local row = {}
    for c = 1, 3 do
      local n = color[c]
      if type(n) ~= "number" or n ~= n or n < 0 or n > 255 then return nil end
      row[c] = n
    end
    out[i] = row
  end
  return out
end
function M.resolve(colors) return Palettes.effectiveColors(colors) end
function M.color(colors, index)
  local palette = M.resolve(colors)
  return palette and palette[index] or nil
end

local function upload(sh, colors)
  -- Public shader objects can be edited externally. Upload every public call;
  -- a cached last-send comparison could otherwise trust foreign uniforms.
  sent[sh] = nil
  for i = 1, 4 do
    local row = colors[i]
    sh:send(names[i], {row[1]/255, row[2]/255, row[3]/255})
  end
  sent[sh] = colors
end
local function use(colors, keyed, raw)
  local g = graphics()
  if not (g and g.setShader) then return false end
  colors = copy(raw and colors or M.resolve(colors))
  if not colors then return false end
  local sh = shader(keyed)
  if not sh then return false end
  upload(sh, colors)
  g.setShader(sh)
  return true
end
function M.use(colors) return use(colors, false, false) end
function M.useRaw(colors) return use(colors, false, true) end
function M.useKeyed(colors) return use(colors, true, false) end
function M.clear()
  local g = graphics()
  if g and g.setShader then g.setShader() end
end

local function scoped(colors, body, apply)
  local g = graphics()
  local previous = g and g.getShader and g.getShader() or nil
  -- Restoring only the shader object is insufficient: nested calls reuse it
  -- and change its uniforms. Save the palette values as well as its identity.
  local previousColors = previous and sent[previous]
  local ok, applied = pcall(function()
    local active = apply(colors)
    body()
    return active
  end)
  local restored, why = pcall(function()
    if previousColors then upload(previous, previousColors) end
    if g and g.setShader then g.setShader(previous) end
  end)
  if not ok then error(applied, 0) end
  if not restored then error(why, 0) end
  return applied
end
function M.with(colors, body) return scoped(colors, body, M.use) end
function M.withRaw(colors, body) return scoped(colors, body, M.useRaw) end
function M.keyedWith(colors, body) return scoped(colors, body, M.useKeyed) end
return M
