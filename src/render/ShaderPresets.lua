-- Optional bounded LÖVE shaders over the completed primary game view.
-- Metadata is JSON, never executable Lua. OFF does no discovery or GPU work.
local Json = require("src.link.Json")
local Graph = require("src.render.ShaderGraph")
local Logger = require("src.core.Logger")
local Performance = require("src.core.Performance")
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
  if
    type(raw) ~= "table"
    or (raw.format ~= 1 and raw.format ~= 2 and raw.format ~= 3)
    or not label(raw.name)
  then
    return nil, "invalid preset metadata"
  end
  if raw.format ~= 3 and not filename(raw.shader, "glsl") and not raw.builtinSource then
    return nil, "invalid shader filename"
  end
  local out = { id = id, name = raw.name, shader = raw.shader, source = raw.builtinSource, parameters = {} }
  if raw.format == 3 then
    local graph, why = Graph.validate(raw)
    if not graph or raw.builtinSource then
      return nil, why or "invalid graph"
    end
    out.graph, out.imported = graph, true
  elseif raw.format == 2 then
    if
      raw.builtinSource
      or not filename(raw.vertex, "glsl")
      or not filename(raw.esShader, "glsl")
      or not filename(raw.esVertex, "glsl")
      or (raw.filter ~= "nearest" and raw.filter ~= "linear")
      or not ({ clampzero = true, clamp = true, ["repeat"] = true, mirroredrepeat = true })[raw.wrap]
    then
      return nil, "invalid imported preset metadata"
    end
    out.imported, out.vertex, out.esShader, out.esVertex = true, raw.vertex, raw.esShader, raw.esVertex
    out.filter, out.wrap = raw.filter, raw.wrap
  end
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
      or (out.imported and p.id:match("^g2_"))
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
  return setmetatable(
    { fs = opts.fs, graphics = opts.graphics, entries = {}, byId = {}, fileData = opts.fileData },
    Presets
  )
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
  if self.graph then
    self.graph:release()
    self.graph = nil
  end
  release(self.shader)
  release(self.output)
  release(self.importInput)
  self.importInput = nil
  self.shader, self.output, self.entry, self.values = nil, nil, nil, nil
  self.error = nil
end
function Presets:active()
  if Performance.extraCap("shaderPresets")==false then return false end
  return self.shader ~= nil or self.graph ~= nil
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
  local g = self:_graphics()
  if entry.graph then
    if not (g and g.newShader and g.newCanvas and g.validateShader) then
      return self:_fail("shader graph graphics unavailable")
    end
    local values = {}
    for _, p in ipairs(entry.parameters) do
      values[p.id] = value(p, type(params) == "table" and params[p.id] or nil)
    end
    local graph, why = Graph.new(entry.graph, function(name, limit)
      return read(self:_fs(), ROOT .. "/" .. name, limit)
    end, g, values, self.fileData or (love and love.filesystem and love.filesystem.newFileData))
    if not graph then
      return self:_fail(why)
    end
    self:off()
    self.graph, self.entry, self.values = graph, entry, values
    return true
  end
  local es = false
  if entry.imported and g and g.getRendererInfo then
    local name, version = g.getRendererInfo()
    es = (tostring(name) .. tostring(version)):find("OpenGL ES", 1, true) ~= nil
  end
  local source, why = entry.source
  if not source then
    source, why = read(self:_fs(), ROOT .. "/" .. (es and entry.esShader or entry.shader), MAX_SOURCE)
  end
  local vertex
  if entry.imported then
    vertex, why = read(self:_fs(), ROOT .. "/" .. (es and entry.esVertex or entry.vertex), MAX_SOURCE)
    if not vertex then
      return self:_fail(why)
    end
  end
  if not source then
    return self:_fail(why)
  end
  if not (g and g.newShader and g.newCanvas) then
    return self:_fail("shader graphics unavailable")
  end
  local shader, importInput
  local values = {}
  local ok, err = pcall(function()
    shader = vertex and g.newShader(source, vertex) or g.newShader(source)
    if entry.imported then
      -- Check NPOT wrapping and standardized uniform types before retiring the old effect.
      importInput = g.newCanvas(3, 5, { dpiscale = 1 })
      importInput:setFilter(entry.filter, entry.filter)
      Graph.setWrap(importInput, entry.wrap)
      for _, name in ipairs({ "SourceSize", "OriginalSize", "OutputSize", "FinalViewportSize" }) do
        if shader:hasUniform("g2_" .. name) then
          shader:send("g2_" .. name, { 3, 5, 1 / 3, 1 / 5 })
        end
      end
      if shader:hasUniform("g2_Source") then
        shader:send("g2_Source", importInput)
      end
    end
    for _, p in ipairs(entry.parameters) do
      local uniform = entry.imported and ("g2_p_" .. p.id) or p.id
      -- Slang declares parameters in both blocks even when optimized out.
      assert(entry.imported or shader:hasUniform(uniform), "missing parameter uniform: " .. uniform)
      values[p.id] = value(p, type(params) == "table" and params[p.id] or nil)
      if shader:hasUniform(uniform) then
        shader:send(uniform, values[p.id])
      end
    end
  end)
  if not ok then
    release(shader)
    release(importInput)
    return self:_fail(err)
  end
  self:off()
  self.shader, self.entry, self.values = shader, entry, values
  self.importInput = importInput
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
  if Performance.extraCap("shaderPresets")==false then return input end
  if self.graph then
    if self.graph:owns(input) then
      return input
    end
    local ok, output = pcall(self.graph.run, self.graph, input, pixelScale)
    if ok then
      return output
    end
    self:off()
    self:_fail(output)
    Logger.warn("shader graph disabled: %s", self.error)
    return input
  end
  if not self:active() or (input == self.output or input == self.importInput) then
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
    local sampled = input
    if self.entry.imported then
      local pw, ph = input:getPixelDimensions()
      local scale = finite(pixelScale) and math.max(1, pixelScale) or 1
      local nw, nh = math.max(1, math.floor(pw / scale + 0.5)), math.max(1, math.floor(ph / scale + 0.5))
      if not self.importInput or self.importInput:getWidth() ~= nw or self.importInput:getHeight() ~= nh then
        release(self.importInput)
        self.importInput = nil
        self.importInput = g.newCanvas(nw, nh, { dpiscale = 1 })
        self.importInput:setFilter(self.entry.filter, self.entry.filter)
        Graph.setWrap(self.importInput, self.entry.wrap)
      end
      -- Reconstruct the primary view's native-pixel grid in a private texture.
      -- Its filter/wrap never change a mod's or the renderer's input texture.
      g.setCanvas(self.importInput)
      g.setShader()
      local iw, ih = input:getDimensions()
      g.draw(input, 0, 0, 0, nw / iw, nh / ih)
      sampled = self.importInput
      g.setCanvas(self.output)
      local function send(id, v)
        if self.shader:hasUniform(id) then
          self.shader:send(id, v)
        end
      end
      local ow, oh = input:getPixelDimensions()
      local size = { nw, nh, 1 / nw, 1 / nh }
      send("g2_Source", sampled)
      send("g2_SourceSize", size)
      send("g2_OriginalSize", size)
      send("g2_OutputSize", { ow, oh, 1 / ow, 1 / oh })
      send("g2_FinalViewportSize", { ow, oh, 1 / ow, 1 / oh })
    end
    for id, n in pairs(self.values) do
      local uniform = self.entry.imported and ("g2_p_" .. id) or id
      if self.shader:hasUniform(uniform) then
        self.shader:send(uniform, n)
      end
    end
    if self.shader:hasUniform("sourceSize") then
      local w, h = input:getPixelDimensions()
      self.shader:send("sourceSize", { w, h })
    end
    if self.shader:hasUniform("pixelScale") then
      self.shader:send("pixelScale", finite(pixelScale) and math.max(1, pixelScale) or 1)
    end
    g.setShader(self.shader)
    if self.entry.imported then
      local w, h = input:getDimensions()
      g.draw(sampled, 0, 0, 0, w / sampled:getWidth(), h / sampled:getHeight())
    else
      g.draw(input, 0, 0)
    end
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
