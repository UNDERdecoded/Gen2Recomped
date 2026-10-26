-- Optional single-pass LÖVE shaders over the completed primary game view.
-- Metadata is JSON, never executable Lua. OFF does no discovery or GPU work.
local Json = require("src.link.Json")
local Logger = require("src.core.Logger")
local Presets = {}
Presets.__index = Presets
local ROOT, MAX_JSON, MAX_SOURCE = "shader-presets", 16384, 65536
local function finite(n)
  return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function label(s)
  return type(s) == "string" and #s > 0 and #s <= 48 and not s:find("[^ -~]")
end
local function filename(s, ext)
  return type(s) == "string" and #s <= 64 and s:match("^[%w_-]+%." .. ext .. "$") ~= nil
end
local function release(resource)
  if resource and resource.release then
    pcall(resource.release, resource)
  end
end
local function value(p, n)
  if not finite(n) then
    return p.default
  end
  local steps = math.floor((math.max(p.min, math.min(p.max, n)) - p.min) / p.step + 0.5)
  return math.max(p.min, math.min(p.max, p.min + steps * p.step))
end
local function validate(raw, id)
  if type(raw) ~= "table" or raw.format ~= 1 or not label(raw.name) then
    return nil, "invalid preset metadata"
  end
  if not filename(raw.shader, "glsl") and not raw.builtinSource then
    return nil, "invalid shader filename"
  end
  local out = { id = id, name = raw.name, shader = raw.shader, source = raw.builtinSource, parameters = {} }
  local params = raw.parameters or {}
  if type(params) ~= "table" or #params > 8 then
    return nil, "invalid parameter list"
  end
  local seen = { sourceSize = true, pixelScale = true }
  for k in pairs(params) do
    if type(k) ~= "number" or k < 1 or k > #params or k ~= math.floor(k) then
      return nil, "invalid parameter list"
    end
  end
  for _, p in ipairs(params) do
    if
      type(p) ~= "table"
      or type(p.id) ~= "string"
      or #p.id > 32
      or not p.id:match("^[%a_][%w_]*$")
      or seen[p.id]
      or p.id:match("^love_")
      or not label(p.name)
      or not finite(p.min)
      or not finite(p.max)
      or p.min >= p.max
      or not finite(p.max - p.min)
      or not finite(p.step)
      or p.step <= 0
      or p.step > p.max - p.min
      or (p.max - p.min) / p.step > 1000000
      or not finite(p.default)
      or p.default < p.min
      or p.default > p.max
    then
      return nil, "invalid parameter definition"
    end
    seen[p.id] = true
    out.parameters[#out.parameters + 1] =
      { id = p.id, name = p.name, min = p.min, max = p.max, step = p.step, default = value(p, p.default) }
  end
  return out
end
local BUILTINS = {
  {
    id = "builtin:warm",
    format = 1,
    name = "WARM DISPLAY",
    parameters = {
      { id = "strength", name = "STRENGTH", min = 0, max = 1, step = 0.05, default = 0.4 },
    },
    builtinSource = [[
extern number strength;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
  vec4 c = Texel(tex, uv) * color;
  return vec4(c.rgb * mix(vec3(1.0), vec3(1.0, 0.94, 0.80), strength), c.a);
}]],
  },
  {
    id = "builtin:soft-lcd",
    format = 1,
    name = "SOFT LCD",
    parameters = {
      { id = "strength", name = "STRENGTH", min = 0, max = 0.5, step = 0.05, default = 0.15 },
    },
    builtinSource = [[
extern number strength;
extern number pixelScale;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 pixel) {
  vec4 c = Texel(tex, uv) * color;
  float row = mod(floor(pixel.y / max(1.0, pixelScale)), 2.0);
  return vec4(c.rgb * (1.0 - strength * row), c.a);
}]],
  },
}
function Presets.new(opts)
  opts = opts or {}
  return setmetatable({ fs = opts.fs, graphics = opts.graphics, entries = {}, byId = {} }, Presets)
end
function Presets:_fs()
  return self.fs or (love and love.filesystem and require("src.import.CacheFs").dataFs())
end
function Presets:_graphics()
  return self.graphics or (love and love.graphics)
end
local function read(fs, path, limit)
  if not fs or not fs.read or not fs.getInfo then
    return nil, "filesystem unavailable"
  end
  local ok, info = pcall(fs.getInfo, path)
  if not ok or not info or info.type ~= "file" or (info.size and info.size > limit) then
    return nil, "missing or oversized file: " .. path
  end
  local success, text = pcall(fs.read, path, limit + 1)
  if not success or type(text) ~= "string" or #text > limit then
    return nil, "cannot read file: " .. path
  end
  return text
end
function Presets:refresh()
  self.entries, self.byId = {}, {}
  local function add(entry)
    self.entries[#self.entries + 1] = entry
    self.byId[entry.id] = entry
  end
  for _, raw in ipairs(BUILTINS) do
    add(assert(validate(raw, raw.id)))
  end
  local fs = self:_fs()
  local ok, names = false, nil
  if fs and fs.getDirectoryItems then
    ok, names = pcall(fs.getDirectoryItems, ROOT)
  end
  if ok and type(names) == "table" then
    table.sort(names)
    for _, name in ipairs(names) do
      if filename(name, "json") then
        local id = "local:" .. name:sub(1, -6)
        local text, why = read(fs, ROOT .. "/" .. name, MAX_JSON)
        local parsed, raw = false, nil
        if text then
          parsed, raw = pcall(Json.decode, text)
        end
        local entry
        if parsed then
          -- Local metadata cannot inject a built-in source or use Lua loaders.
          if type(raw) == "table" then
            raw.builtinSource = nil
          end
          entry, why = validate(raw, id)
        end
        add(entry or { id = id, name = name:sub(1, -6), error = why or "invalid JSON" })
      end
    end
  end
  self.scanned = true
  return self.entries
end
function Presets:list()
  if not self.scanned then
    self:refresh()
  end
  return self.entries
end
function Presets:_fail(reason)
  self.error = tostring(reason):gsub("[\r\n]+", " "):sub(1, 240)
  return nil, self.error
end
function Presets:off()
  release(self.shader)
  release(self.output)
  self.shader, self.output, self.entry, self.values = nil, nil, nil, nil
  self.error = nil
end
function Presets:active()
  return self.shader ~= nil
end
function Presets:activate(id, params)
  if id == nil or id == "off" then
    self:off()
    return true
  end
  self:list()
  local entry = self.byId[id]
  if not entry then
    return self:_fail("preset not found")
  end
  if entry.error then
    return self:_fail(entry.error)
  end
  local source, why = entry.source
  if not source then
    source, why = read(self:_fs(), ROOT .. "/" .. entry.shader, MAX_SOURCE)
  end
  if not source then
    return self:_fail(why)
  end
  local g = self:_graphics()
  if not (g and g.newShader and g.newCanvas) then
    return self:_fail("shader graphics unavailable")
  end
  local shader
  local values = {}
  local ok, err = pcall(function()
    shader = g.newShader(source)
    for _, p in ipairs(entry.parameters) do
      assert(shader:hasUniform(p.id), "missing parameter uniform: " .. p.id)
      values[p.id] = value(p, type(params) == "table" and params[p.id] or nil)
      shader:send(p.id, values[p.id])
    end
  end)
  if not ok then
    release(shader)
    return self:_fail(err)
  end
  self:off()
  self.shader, self.entry, self.values = shader, entry, values
  return true
end
function Presets:applyOptions(opts)
  -- Reset the previous game's selection even when this save's preset is bad.
  self:off()
  local id = type(opts) == "table" and opts.shaderPreset
  if id == nil or id == "off" then
    return true
  end
  local all = type(opts.shaderPresetParams) == "table" and opts.shaderPresetParams
  return self:activate(id, all and all[id])
end
function Presets:select(opts, id)
  local all = type(opts.shaderPresetParams) == "table" and opts.shaderPresetParams
  local ok, why = self:activate(id, all and all[id])
  if ok then
    opts.shaderPreset = id or "off"
  end
  return ok, why
end
function Presets:setParameter(opts, id, n)
  if not self.entry then
    return nil, "no active preset"
  end
  for _, p in ipairs(self.entry.parameters) do
    if p.id == id then
      self.values[id] = value(p, n)
      if type(opts.shaderPresetParams) ~= "table" then
        opts.shaderPresetParams = {}
      end
      local key = self.entry.id
      if type(opts.shaderPresetParams[key]) ~= "table" then
        opts.shaderPresetParams[key] = {}
      end
      opts.shaderPresetParams[key][id] = self.values[id]
      return true
    end
  end
  return nil, "unknown parameter"
end
function Presets:apply(input, pixelScale)
  if not self:active() or input == self.output then
    return input
  end
  local g = self:_graphics()
  local ok, err = pcall(function()
    local w, h = input:getDimensions()
    local dpi = input.getDPIScale and input:getDPIScale() or 1
    if
      not self.output
      or self.output:getWidth() ~= w
      or self.output:getHeight() ~= h
      or self.output:getDPIScale() ~= dpi
    then
      release(self.output)
      self.output = nil
      self.output = g.newCanvas(w, h, { dpiscale = dpi })
      self.output:setFilter("nearest", "nearest")
    end
  end)
  if not ok then
    self:off()
    self:_fail(err)
    return input
  end
  local pushed, pushError = pcall(g.push, "all")
  if not pushed then
    self:off()
    self:_fail(pushError)
    return input
  end
  ok, err = pcall(function()
    g.setCanvas(self.output)
    g.origin()
    g.setScissor()
    g.setStencilTest()
    g.setDepthMode()
    g.setColorMask(true, true, true, true)
    g.setBlendMode("replace", "premultiplied")
    g.setColor(1, 1, 1, 1)
    for id, n in pairs(self.values) do
      self.shader:send(id, n)
    end
    if self.shader:hasUniform("sourceSize") then
      local w, h = input:getPixelDimensions()
      self.shader:send("sourceSize", { w, h })
    end
    if self.shader:hasUniform("pixelScale") then
      self.shader:send("pixelScale", finite(pixelScale) and math.max(1, pixelScale) or 1)
    end
    g.setShader(self.shader)
    g.draw(input, 0, 0)
  end)
  g.pop()
  if not ok then
    self:off()
    self:_fail(err)
    Logger.warn("shader preset disabled: %s", self.error)
    return input
  end
  return self.output
end
local default = Presets.new()
default.new = Presets.new
return default
