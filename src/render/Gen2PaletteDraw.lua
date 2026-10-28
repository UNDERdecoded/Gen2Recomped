-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Indexed image drawing, separate from the LCD post-process in GBCFX.
-- Palette resolution uses the native display/register state in PaletteFX.
local Palettes = require("src.render.PaletteFX")
local Version = require("src.core.GameVersion")
local M = {}
-- Display state belongs to the same owner as the native map/OBJ/pic bakes.
setmetatable(M, {__index = function(_, key)
  if key == "mode" then
    if Version.isGen2() and Palettes.mode == "custom" then return "custom" end
    if Palettes.mode == "og" or Palettes.mode == "og_inv" then return "dmg" end
    return Palettes.mode == "classic" and "classic" or "gbc"
  end
  if key == "bgp" then return Palettes.bgp() end
  if key == "customRamp" then return Palettes.customRamp() end
end, __newindex = function(self, key, value)
  if key == "bgp" then Palettes.setBgp(value)
  elseif key == "mode" then M.setMode(value)
  elseif key == "customRamp" then Palettes.setCustomRamp(value)
  else rawset(self, key, value) end
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

-- A composited CGB frame has lost its palette indices. Match only colours
-- present in its BG/OBJ tables; unrelated RGB art must keep its own colour.
-- Constant loop bounds also work on GLSL ES uniform-array implementations.
M.REMAP_MAX = 64
M.REMAP_TOLERANCE = (3 / 255) ^ 2
local remapSource = [[
extern int remapCount;
extern float remapTol;
extern vec3 remapSrc[64];
extern vec3 remapDst[64];
vec4 effect(vec4 tint, Image image, vec2 uv, vec2 screen) {
  vec4 pixel = Texel(image, uv);
  vec3 rgb = pixel.rgb;
  float closest = remapTol;
  for (int i = 0; i < 64; i++) {
    if (i >= remapCount) break;
    vec3 delta = pixel.rgb - remapSrc[i];
    float distanceSquared = dot(delta, delta);
    if (distanceSquared < closest) {
      closest = distanceSquared;
      rgb = remapDst[i];
    }
  }
  return vec4(rgb, pixel.a) * tint;
}
]]

local function graphics() return love and love.graphics end
local function compile(key, code, keyed)
  local g = graphics()
  local newShader = g and g.newShader
  if type(newShader) ~= "function" then return nil end
  if compiler ~= newShader then
    compiler, shaders, failed = newShader, {}, {}
  end
  if failed[key] then return nil end
  if not shaders[key] then
    if key ~= "remap" then
      local alpha = keyed and "(shade < 0.5 ? 0.0 : pixel.a)" or "pixel.a"
      code = (code:gsub("ALPHA", alpha))
    end
    local ok, value = pcall(newShader, code)
    if not ok or not value then failed[key] = true; return nil end
    shaders[key] = value
  end
  return shaders[key]
end
local function shader(keyed)
  return compile(keyed and "keyed" or "normal", source, keyed)
end
function M.shader() return shader(false) end
function M.keyedShader() return shader(true) end
function M.remapShader() return compile("remap", remapSource) end
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
M.BGP_IDENTITY = Palettes.BGP_IDENTITY
M.bgpShades = Palettes.bgpShades
M.remap = Palettes.remap
M.setBgp = Palettes.setBgp
M.MODES = {"gbc", "dmg", "classic"}
M.MODE_LABELS = {gbc="GEN 2", dmg="DMG", classic="CLASSIC", custom="CUSTOM"}
M.CUSTOM_MODE = "custom"
M.setCustomRamp = Palettes.setCustomRamp
M.presentColors = Palettes.presentColors
function M.setMode(mode)
  if mode~="gbc" and mode~="dmg" and mode~="classic" and mode~="custom" then mode="gbc" end
  Palettes.setMode(mode)
  return M.mode
end
function M.cycle(delta) Palettes.cycleMode(delta); return M.mode end
function M.applyOptions(opts) Palettes.applyOptions(opts); return M.mode end
function M.modeLabel(mode) return M.MODE_LABELS[mode or M.mode] or "GEN 2" end
function M.resolve(colors) return Palettes.displayColors(colors) end
function M.color(colors, index)
  local palette = Palettes.effectiveColors(colors or Palettes.GRAYS)
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
  colors = copy(raw and colors or Palettes.effectiveColors(colors))
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

-- The first BG slot wins when the same RGB value has different meanings.
-- Report those collisions rather than pretending an RGB frame retains its
-- original indices. OBJ rows normally map to themselves, protecting sprites.
function M.remapTable(bgPalettes, byte, objPalettes, ramp, objRamped)
  local src, dst, seen, ambiguous = {}, {}, {}, 0
  local function key(c)
    return math.floor(c[1]) .. "," .. math.floor(c[2]) .. "," .. math.floor(c[3])
  end
  local function add(colors, mapped)
    colors, mapped = copy(colors), copy(mapped)
    if not (colors and mapped) then return end
    for i = 1, 4 do
      local from, to = colors[i], mapped[i]
      local k = key(from)
      local at = seen[k]
      if at then
        if key(dst[at]) ~= key(to) then ambiguous = ambiguous + 1 end
      elseif #src < M.REMAP_MAX then
        src[#src + 1], dst[#dst + 1] = from, to
        seen[k] = #src
      end
    end
  end
  local forced = ramp and M.resolve(copy(ramp))
  local forcedBg = forced and M.remap(forced, byte)
  for _, colors in ipairs(bgPalettes or {}) do
    local resolved = M.resolve(copy(colors))
    add(resolved, forcedBg or M.remap(resolved, byte))
  end
  if forced then add(forced, forcedBg) end
  for i, colors in ipairs(objPalettes or {}) do
    local resolved = M.resolve(copy(colors))
    add(resolved, forced and objRamped and objRamped[i] and forced or resolved)
  end
  local count = #src
  for i = count + 1, M.REMAP_MAX do
    src[i] = src[1] and {unpack(src[1])} or {0, 0, 0}
    dst[i] = dst[1] and {unpack(dst[1])} or {0, 0, 0}
  end
  return src, dst, count, ambiguous
end
function M.remapUniforms(bgPalettes, byte, objPalettes, ramp, objRamped)
  local src, dst, count, ambiguous = M.remapTable(bgPalettes, byte, objPalettes, ramp, objRamped)
  if count == 0 then return nil end
  for i = 1, M.REMAP_MAX do
    for c = 1, 3 do src[i][c], dst[i][c] = src[i][c]/255, dst[i][c]/255 end
  end
  return {src=src, dst=dst, count=count, ambiguous=ambiguous}
end
local remapSent = setmetatable({}, {__mode = "k"})
local function uploadRemap(sh, uniforms)
  remapSent[sh] = nil
  sh:send("remapCount", uniforms.count)
  sh:send("remapTol", M.REMAP_TOLERANCE)
  sh:send("remapSrc", unpack(uniforms.src))
  sh:send("remapDst", unpack(uniforms.dst))
  remapSent[sh] = uniforms
end
local function copyUniforms(uniforms)
  if type(uniforms) ~= "table" or type(uniforms.count) ~= "number"
      or uniforms.count < 1 or uniforms.count > M.REMAP_MAX
      or uniforms.count % 1 ~= 0 then return nil end
  local result = {count=uniforms.count, ambiguous=uniforms.ambiguous, src={}, dst={}}
  for _, name in ipairs({"src", "dst"}) do
    if type(uniforms[name]) ~= "table" then return nil end
    for i = 1, M.REMAP_MAX do
      local row = uniforms[name][i]
      if type(row) ~= "table" then return nil end
      result[name][i] = {}
      for c = 1, 3 do
        local n = row[c]
        if type(n) ~= "number" or n ~= n or n < 0 or n > 1 then return nil end
        result[name][i][c] = n
      end
    end
  end
  return result
end
function M.useRemapUniforms(uniforms)
  local g = graphics()
  if not (g and g.setShader) then return false end
  local sh = M.remapShader()
  uniforms = copyUniforms(uniforms)
  if not (sh and uniforms) then return false end
  local previous = remapSent[sh]
  if not pcall(uploadRemap, sh, uniforms) then
    if previous then pcall(uploadRemap, sh, previous) end
    failed.remap, shaders.remap = true, nil
    return false
  end
  g.setShader(sh)
  return true, uniforms.ambiguous
end
function M.useRemap(bgPalettes, byte, objPalettes, ramp, objRamped)
  return M.useRemapUniforms(M.remapUniforms(bgPalettes, byte, objPalettes, ramp, objRamped))
end

local function scoped(colors, body, apply)
  local g = graphics()
  local previous = g and g.getShader and g.getShader() or nil
  -- Restoring only the shader object is insufficient: nested calls reuse it
  -- and change its uniforms. Save the palette values as well as its identity.
  local previousColors = previous and sent[previous]
  local previousRemap = previous and remapSent[previous]
  local ok, applied = pcall(function()
    local active = apply(colors)
    body()
    return active
  end)
  local restored, why = pcall(function()
    if previousColors then upload(previous, previousColors) end
    if previousRemap then uploadRemap(previous, previousRemap) end
    if g and g.setShader then g.setShader(previous) end
  end)
  if not ok then error(applied, 0) end
  if not restored then error(why, 0) end
  return applied
end
function M.with(colors, body) return scoped(colors, body, M.use) end
function M.withRaw(colors, body) return scoped(colors, body, M.useRaw) end
function M.keyedWith(colors, body) return scoped(colors, body, M.useKeyed) end
-- Graphics push/pop retains a shader object, not its mutable uniforms. An
-- OAM pass selects several palettes itself, so preserve the outer indexed
-- palette without imposing an extra palette on the first object.
function M.preserving(body) return scoped(nil, body, function()return false end) end
return M
