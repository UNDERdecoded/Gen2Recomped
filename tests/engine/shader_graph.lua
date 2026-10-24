package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Graph = require("src.render.ShaderGraph")
local Presets = require("src.render.ShaderPresets")
local Json = require("src.link.Json")
local function fixture()
  local spec = {
    format = 3,
    name = "GRAPH",
    parameters = { { id = "gain", name = "GAIN", min = 0, max = 1, step = 0.1, default = 0.5 } },
    passes = {},
    textures = { { id = "Tint", image = "t.png", filter = "linear", wrap = "repeat" } },
  }
  for i = 1, 3 do
    spec.passes[i] = {
      shader = "f.glsl",
      vertex = "v.glsl",
      esShader = "ef.glsl",
      esVertex = "ev.glsl",
      filter = "nearest",
      wrap = "clamp",
      scaleX = { type = i == 3 and "viewport" or "source", value = i == 2 and 2 or 1 },
      scaleY = { type = i == 3 and "viewport" or "original", value = 1 },
    }
  end
  local files = {
    ["f.glsl"] = "f",
    ["v.glsl"] = "v",
    ["ef.glsl"] = "ef",
    ["ev.glsl"] = "ev",
    ["t.png"] = "\137PNG\13\10\26\10\0\0\0\13IHDR\0\0\0\2\0\0\0\1\8\6" .. string.rep("\0", 7),
  }
  local objects, faults, uniforms, compiled = {}, {}, {}, {}
  local current, stack, draws = nil, 0, 0
  local function resource(w, h, dpi)
    local o = { w = w, h = h, dpi = dpi or 1 }
    objects[#objects + 1] = o
    function o:getWidth()
      return self.w
    end
    function o:getHeight()
      return self.h
    end
    function o:getDimensions()
      return self.w, self.h
    end
    function o:getPixelDimensions()
      return self.w * self.dpi, self.h * self.dpi
    end
    function o:getDPIScale()
      return self.dpi
    end
    function o:setFilter(...)
      self.filter = { ... }
    end
    function o:setWrap(...)
      self.wrap = { ... }
      return not faults.wrap
    end
    function o:release()
      T.check(not self.released, "release once")
      self.released = true
    end
    function o:newImageData()
      if faults.readback then
        error("readback")
      end
      return resource(0, 0)
    end
    function o:hasUniform()
      return true
    end
    function o:send(k, v)
      if faults.send then
        error("uniform")
      end
      self.uniforms = self.uniforms or {}
      self.uniforms[k] = v
      uniforms[k] = v
    end
    return o
  end
  local g = {
    getRendererInfo = function()
      return faults.es and "OpenGL ES" or "OpenGL", "2.0"
    end,
    getSystemLimits = function()
      return { texturesize = 8192 }
    end,
    validateShader = function(es, f, v)
      compiled[#compiled + 1] = { es, f, v }
      return not faults.validate, "bad dialect"
    end,
    newShader = function(f, v)
      if faults.compile then
        error("compile")
      end
      local o = resource(0, 0)
      o.pair = { f, v }
      return o
    end,
    newCanvas = function(w, h, opts)
      if faults.allocate then
        error("allocation")
      end
      return resource(w, h, opts.dpiscale)
    end,
    newImage = function()
      if faults.decode then
        error("decode")
      end
      return resource(2, 1)
    end,
    getCanvas = function()
      return current
    end,
    setCanvas = function(c)
      current = c
    end,
    push = function()
      stack = stack + 1
    end,
    pop = function()
      stack = stack - 1
    end,
    draw = function(image)
      if faults.draw then
        error("draw")
      end
      T.neq(image, current, "no render feedback")
      draws = draws + 1
    end,
  }
  for _, k in ipairs({
    "origin",
    "setScissor",
    "setStencilTest",
    "setDepthMode",
    "setColorMask",
    "setColor",
    "setBlendMode",
    "setShader",
    "clear",
  }) do
    g[k] = function() end
  end
  local fs = {
    getDirectoryItems = function()
      return { "graph.json" }
    end,
    getInfo = function(path)
      local name = path:match("[^/]+$")
      local text = name == "graph.json" and Json.encode(spec) or files[name]
      return text and { type = "file", size = #text }
    end,
    read = function(path)
      local name = path:match("[^/]+$")
      return name == "graph.json" and Json.encode(spec) or files[name]
    end,
  }
  return Presets.new({
    graphics = g,
    fs = fs,
    fileData = function()
      return resource(0, 0)
    end,
  }),
    spec,
    files,
    faults,
    uniforms,
    objects,
    resource,
    g,
    function()
      return stack, current, draws
    end,
    compiled
end
for i, mutate in ipairs({
  function(s)
    s.passes = {}
  end,
  function(s)
    for n = 4, 9 do
      s.passes[n] = s.passes[1]
    end
  end,
  function(s)
    s.passes[1].shader = "../bad.glsl"
  end,
  function(s)
    s.passes[1].filter = "cubic"
  end,
  function(s)
    s.passes[1].wrap = "bad"
  end,
  function(s)
    s.passes[1].scaleX.value = 9
  end,
  function(s)
    s.passes[1].scaleY = { type = "absolute", value = 1.5 }
  end,
  function(s)
    s.passes[1].scaleX = { type = "bad", value = 1 }
  end,
  function(s)
    s.passes[1].scaleX.extra = true
  end,
  function(s)
    s.passes[1].extra = true
  end,
  function(s)
    s.textures[1].image = "../t.png"
  end,
  function(s)
    s.textures[1].filter = "cubic"
  end,
  function(s)
    s.textures[1].id = "bad id"
  end,
  function(s)
    s.textures[1].extra = true
  end,
  function(s)
    s.parameters[1].id = "g2_Lut0"
  end,
}) do
  local p, s = fixture()
  mutate(s)
  T.check(not p:activate("local:graph"), "invalid graph refused " .. i)
end
for _, fault in ipairs({ "validate", "compile", "allocate", "wrap", "decode", "send", "readback", "draw" }) do
  local p, s, files, faults, u, objects = fixture()
  T.check(p:activate("builtin:warm"), "working fallback")
  local old = p.shader
  faults[fault] = true
  T.check(not p:activate("local:graph"), fault .. " preflight refuses")
  T.eq(p.shader, old, "old preserved")
  T.check(p:active(), "still active")
  for _, o in ipairs(objects) do
    if o ~= old then
      T.check(o.released, "failed candidate releases partial resources")
    end
  end
  p:off()
end
do
  local p, s, files, f, u, objects, resource, g, state, compiled = fixture()
  f.es = true
  T.check(p:activate("local:graph"), "activate graph")
  T.eq(#compiled, 6, "both dialects every pass")
  T.same(p.graph.shaders[1].pair, { "ef", "ev" }, "current dialect pair")
  local input = resource(40, 30, 2)
  local sentinel = resource(1, 1)
  g.setCanvas(sentinel)
  local output = p:apply(input, 5)
  T.neq(output, input, "graph output")
  T.eq(output:getDPIScale(), 2, "DPI retained")
  T.same(u.g2_OriginalSize, { 16, 12, 1 / 16, 1 / 12 }, "original native grid")
  T.same(u.g2_SourceSize, { 32, 12, 1 / 32, 1 / 12 }, "source prior pass grid")
  T.same(u.g2_Pass0Size, { 16, 12, 1 / 16, 1 / 12 }, "earlier grid")
  T.same(u.g2_Lut0Size, { 2, 1, 0.5, 1 }, "LUT dimensions")
  T.same(u.g2_OutputSize, { 80, 60, 1 / 80, 1 / 60 }, "viewport physical grid")
  T.eq(u.g2_Original, p.graph.original, "original sampler")
  T.eq(u.g2_Pass0, p.graph.targets[1], "earlier sampler")
  T.same(p.graph.images[1].filter, { "linear", "linear" }, "LUT filter retained")
  T.same(p.graph.images[1].wrap, { "repeat", "repeat" }, "LUT wrap retained")
  T.eq(input.filter, nil, "borrowed filter untouched")
  local stack, current = state()
  T.eq(stack, 0, "balanced state")
  T.eq(current, sentinel, "canvas restored")
  local n = #objects
  p:apply(input, 5)
  T.eq(#objects, n, "stable graph reuses resources")
  T.eq(p:apply(output, 5), output, "output feedback guard")
  local old = p.graph.original
  p:apply(input, 2.5)
  T.check(old.released, "scale retires grid")
  local opts = {}
  p:setParameter(opts, "gain", 0.8)
  p:apply(input, 2.5)
  T.eq(u.g2_p_gain, 0.8, "live parameter shared across passes")
  f.draw = true
  T.eq(p:apply(input, 2.5), input, "render failure identity")
  T.check(not p:active(), "render failure disables graph")
  T.check(not input.released, "input owned by caller")
  stack, current = state()
  T.eq(stack, 0, "failure balances state")
  T.eq(current, sentinel, "failure restores canvas")
end
do
  local p, s, files, f, u, objects, resource = fixture()
  T.check(p:activate("local:graph"), "budget candidate")
  local input = resource(8192, 8192)
  T.eq(p:apply(input, 1), input, "pixel budget identity")
  T.check(not p:active(), "over budget retired")
end
for _, bad in ipairs({ "not png", "\137PNG\13\10\26\10" .. string.rep("\0", 30) }) do
  local p, s, files = fixture()
  files["t.png"] = bad
  T.check(not p:activate("local:graph"), "PNG header checked before decoder")
end
T.finish("shader graph")
