-- Bounded, data-only RGBA8 pass graphs for converted RetroArch presets.
local Graph =
  { MAX_PASSES = 8, MAX_TEXTURES = 8, MAX_PIXELS = 32 * 1024 * 1024, MAX_LUT_PIXELS = 8 * 1024 * 1024 }
Graph.__index = Graph
local function finite(v)
  return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function filename(v, ext)
  return type(v) == "string" and #v <= 64 and v:match("^[%w_-]+%." .. ext .. "$") ~= nil
end
local filters = { nearest = true, linear = true }
local wraps = { clampzero = true, clamp = true, ["repeat"] = true, mirroredrepeat = true }
local function array(t, max)
  if type(t) ~= "table" or getmetatable(t) ~= nil or #t > max then
    return false
  end
  local n = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k < 1 or k > #t or k % 1 ~= 0 then
      return false
    end
    n = n + 1
  end
  return n == #t
end
local function scale(s)
  if type(s) ~= "table" or getmetatable(s) ~= nil then
    return nil
  end
  for k in pairs(s) do
    if k ~= "type" and k ~= "value" then
      return nil
    end
  end
  if not finite(s.value) then
    return nil
  end
  if s.type == "absolute" then
    if s.value % 1 ~= 0 or s.value < 1 or s.value > 8192 then
      return nil
    end
  elseif
    not ({ source = true, original = true, viewport = true })[s.type]
    or s.value < 1 / 64
    or s.value > 8
  then
    return nil
  end
  return { type = s.type, value = s.value }
end
function Graph.validate(raw)
  if
    type(raw) ~= "table"
    or raw.format ~= 3
    or not array(raw.passes, Graph.MAX_PASSES)
    or #raw.passes < 1
    or not array(raw.textures or {}, Graph.MAX_TEXTURES)
  then
    return nil, "invalid shader graph"
  end
  local out = { passes = {}, textures = {} }
  for _, p in ipairs(raw.passes) do
    if type(p) ~= "table" or getmetatable(p) ~= nil then
      return nil, "invalid shader pass"
    end
    for key in pairs(p) do
      if
        not ({
          shader = true,
          vertex = true,
          esShader = true,
          esVertex = true,
          filter = true,
          wrap = true,
          scaleX = true,
          scaleY = true,
        })[key]
      then
        return nil, "unknown shader pass field"
      end
    end
    local x, y = scale(p.scaleX), scale(p.scaleY)
    if not x or not y or not filters[p.filter] or not wraps[p.wrap] then
      return nil, "invalid shader pass options"
    end
    local copy = { filter = p.filter, wrap = p.wrap, scaleX = x, scaleY = y }
    for _, k in ipairs({ "shader", "vertex", "esShader", "esVertex" }) do
      if not filename(p[k], "glsl") then
        return nil, "invalid shader graph filename"
      end
      copy[k] = p[k]
    end
    out.passes[#out.passes + 1] = copy
  end
  for _, t in ipairs(raw.textures or {}) do
    if type(t) ~= "table" or getmetatable(t) ~= nil then
      return nil, "invalid LUT"
    end
    for key in pairs(t) do
      if not ({ id = true, image = true, filter = true, wrap = true })[key] then
        return nil, "unknown LUT field"
      end
    end
    if
      not filename(t.image, "png")
      or not filters[t.filter]
      or not wraps[t.wrap]
      or type(t.id) ~= "string"
      or #t.id > 32
      or not t.id:match("^[%a_][%w_]*$")
    then
      return nil, "invalid LUT options"
    end
    out.textures[#out.textures + 1] = { id = t.id, image = t.image, filter = t.filter, wrap = t.wrap }
  end
  return out
end
local function png(bytes)
  if
    type(bytes) ~= "string"
    or #bytes < 33
    or #bytes > 8 * 1024 * 1024
    or bytes:sub(1, 8) ~= "\137PNG\13\10\26\10"
    or bytes:sub(9, 16) ~= "\0\0\0\13IHDR"
  then
    error("LUT must be a bounded PNG", 0)
  end
  local function word(p)
    local a, b, c, d = bytes:byte(p, p + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  local w, h = word(17), word(21)
  if
    w < 1
    or h < 1
    or w > 2048
    or h > 2048
    or bytes:byte(25) ~= 8
    or not ({ [0] = true, [2] = true, [3] = true, [4] = true, [6] = true })[bytes:byte(26)]
  then
    error("unsupported LUT dimensions/bit depth", 0)
  end
  return w, h
end
local function release(v)
  if v and v.release then
    pcall(v.release, v)
  end
end
function Graph:own(v)
  self.resources[v] = true
  return v
end
function Graph:drop(v)
  if v then
    self.resources[v] = nil
    release(v)
  end
end
function Graph:release()
  for v in pairs(self.resources) do
    release(v)
  end
  self.resources = {}
  self.targets = {}
  self.original = nil
  self.output = nil
end
local function send(shader, name, value)
  if shader:hasUniform(name) then
    shader:send(name, value)
  end
end
-- LÖVE 11 returns a boolean; LÖVE 12 returns no value. Observe the actual mode.
local function setWrap(image, mode)
  local result = image:setWrap(mode, mode)
  if result == false then
    error("unsupported graph wrapping", 0)
  end
  if image.getWrap then
    local x, y = image:getWrap()
    assert(x == mode and y == mode, "unsupported graph wrapping")
  else
    assert(result == true, "cannot verify graph wrapping")
  end
end
Graph.setWrap = setWrap
local function sizes(w, h)
  return { w, h, 1 / w, 1 / h }
end
local function dimensions(s, input, original, viewport)
  local n = s.type == "absolute" and s.value
    or s.value * ({ source = input, original = original, viewport = viewport })[s.type]
  return math.max(1, math.floor(n + 0.5))
end
function Graph:canvas(old, w, h, dpi)
  local g = self.g
  if
    old
    and old:getWidth() == w
    and old:getHeight() == h
    and (old.getDPIScale and old:getDPIScale() or 1) == dpi
  then
    return old
  end
  self:drop(old)
  local c = self:own(g.newCanvas(w, h, { dpiscale = dpi, format = "rgba8" }))
  c:setFilter("nearest", "nearest")
  return c
end
function Graph:owns(image)
  return self.resources[image] == true
end
function Graph:run(input, pixelScale)
  local g = self.g
  local pw, ph = input:getPixelDimensions()
  local w, h = input:getDimensions()
  local dpi = input.getDPIScale and input:getDPIScale() or 1
  local ratio = finite(pixelScale) and math.max(1, pixelScale) or 1
  local nw, nh = math.max(1, math.floor(pw / ratio + 0.5)), math.max(1, math.floor(ph / ratio + 0.5))
  local limit = g.getSystemLimits and g.getSystemLimits().texturesize or 4096
  limit = math.min(8192, limit)
  local total = nw * nh + pw * ph + self.lutPixels
  local resolved = {}
  local iw, ih = nw, nh
  for i, p in ipairs(self.spec.passes) do
    local ow = dimensions(p.scaleX, iw, nw, pw)
    local oh = dimensions(p.scaleY, ih, nh, ph)
    total = total + ow * oh
    if ow > limit or oh > limit or total > Graph.MAX_PIXELS then
      error("shader graph exceeds GPU size/pixel budget", 0)
    end
    resolved[i] = { ow, oh }
    iw, ih = ow, oh
  end
  if nw > limit or nh > limit or pw > limit or ph > limit or total > Graph.MAX_PIXELS then
    error("shader graph exceeds GPU size/pixel budget", 0)
  end
  self.original = self:canvas(self.original, nw, nh, 1)
  self.output = self:canvas(self.output, w, h, dpi)
  for i, size in ipairs(resolved) do
    self.targets[i] = self:canvas(self.targets[i], size[1], size[2], 1)
  end
  local saved = g.getCanvas()
  local pushed, why = pcall(g.push, "all")
  if not pushed then
    error(why, 0)
  end
  local ok, err = pcall(function()
    g.origin()
    g.setScissor()
    g.setStencilTest()
    g.setDepthMode()
    g.setColorMask(true, true, true, true)
    g.setColor(1, 1, 1, 1)
    g.setBlendMode("replace", "premultiplied")
    g.setCanvas(self.original)
    g.setShader()
    g.clear(0, 0, 0, 0)
    g.draw(input, 0, 0, 0, nw / w, nh / h)
    for i, p in ipairs(self.spec.passes) do
      local shader = self.shaders[i]
      local source = i == 1 and self.original or self.targets[i - 1]
      local sw, sh = source:getDimensions()
      local ow, oh = resolved[i][1], resolved[i][2]
      -- All rendered inputs are private. LUT samplers retain their own settings.
      for j = 0, i - 1 do
        local img = j == 0 and self.original or self.targets[j]
        img:setFilter(p.filter, p.filter)
        setWrap(img, p.wrap)
      end
      send(shader, "g2_Source", source)
      send(shader, "g2_Original", self.original)
      send(shader, "g2_SourceSize", sizes(sw, sh))
      send(shader, "g2_OriginalSize", sizes(nw, nh))
      send(shader, "g2_OutputSize", sizes(ow, oh))
      send(shader, "g2_FinalViewportSize", sizes(pw, ph))
      for j = 1, i - 1 do
        local image = self.targets[j]
        send(shader, "g2_Pass" .. (j - 1), image)
        send(shader, "g2_Pass" .. (j - 1) .. "Size", sizes(image:getDimensions()))
      end
      for j, img in ipairs(self.images) do
        send(shader, "g2_Lut" .. (j - 1), img)
        send(shader, "g2_Lut" .. (j - 1) .. "Size", sizes(img:getDimensions()))
      end
      for id, n in pairs(self.values) do
        send(shader, "g2_p_" .. id, n)
      end
      g.setCanvas(self.targets[i])
      g.clear(0, 0, 0, 0)
      g.setShader(shader)
      g.draw(source, 0, 0, 0, ow / sw, oh / sh)
    end
    local last = self.targets[#self.targets]
    last:setFilter("nearest", "nearest")
    g.setCanvas(self.output)
    g.setShader()
    g.clear(0, 0, 0, 0)
    g.draw(last, 0, 0, 0, w / last:getWidth(), h / last:getHeight())
  end)
  g.pop()
  g.setCanvas(saved)
  if not ok then
    error(err, 0)
  end
  return self.output
end
function Graph.new(spec, read, g, values, fileData)
  local self = setmetatable(
    {
      spec = spec,
      g = g,
      values = values,
      resources = {},
      targets = {},
      shaders = {},
      images = {},
      lutPixels = 0,
    },
    Graph
  )
  local probe
  local ok, why = pcall(function()
    local renderer, version = g.getRendererInfo()
    local es = (tostring(renderer) .. tostring(version)):find("OpenGL ES", 1, true) ~= nil
    for i, p in ipairs(spec.passes) do
      local source = {}
      for _, key in ipairs({ "shader", "vertex", "esShader", "esVertex" }) do
        source[key] = assert(read(p[key], 65536))
      end
      for _, mobile in ipairs({ false, true }) do
        local valid, message = g.validateShader(
          mobile,
          source[mobile and "esShader" or "shader"],
          source[mobile and "esVertex" or "vertex"]
        )
        assert(valid, tostring(message))
      end
      self.shaders[i] =
        self:own(g.newShader(source[es and "esShader" or "shader"], source[es and "esVertex" or "vertex"]))
    end
    for i, t in ipairs(spec.textures) do
      local bytes = assert(read(t.image, 8 * 1024 * 1024))
      local width, height = png(bytes)
      self.lutPixels = self.lutPixels + width * height
      assert(self.lutPixels <= Graph.MAX_LUT_PIXELS, "LUT pixel budget")
      local data = fileData(bytes, t.image)
      local loaded, img = pcall(g.newImage, data, { mipmaps = false, linear = true })
      release(data)
      if not loaded then
        error(img, 0)
      end
      self.images[i] = self:own(img)
      assert(img:getWidth() == width and img:getHeight() == height, "LUT decoder dimensions differ")
      img:setFilter(t.filter, t.filter)
      setWrap(img, t.wrap)
    end
    probe = g.newCanvas(3, 5, { dpiscale = 1, format = "rgba8" })
    local output = self:run(probe, 1)
    local pixels = output:newImageData()
    assert(pixels, "graph readback unavailable")
    release(pixels)
  end)
  release(probe)
  if not ok then
    self:release()
    return nil, why
  end
  return self
end
return Graph
