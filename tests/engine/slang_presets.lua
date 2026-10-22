package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Json = require("src.link.Json")
local Presets = require("src.render.ShaderPresets")
local function fixture()
  local meta = {
    format = 2,
    name = "IMPORTED",
    shader = "f.glsl",
    vertex = "v.glsl",
    esShader = "ef.glsl",
    esVertex = "ev.glsl",
    filter = "linear",
    wrap = "repeat",
    parameters = {
      { id = "gain", name = "GAIN", min = 0, max = 1, step = 0.1, default = 0.5 },
      { id = "unused", name = "UNUSED", min = 0, max = 1, step = 0.1, default = 0.5 },
    },
  }
  local files =
    { ["f.glsl"] = "fragment", ["v.glsl"] = "vertex", ["ef.glsl"] = "ES fragment", ["ev.glsl"] = "ES vertex" }
  local fs = {
    getDirectoryItems = function()
      return { "test.json" }
    end,
    getInfo = function(path)
      local name = path:match("[^/]+$")
      local s = name == "test.json" and Json.encode(meta) or files[name]
      if s then
        return { type = "file", size = #s }
      end
    end,
    read = function(path)
      local name = path:match("[^/]+$")
      return name == "test.json" and Json.encode(meta) or files[name]
    end,
  }
  local objects, draws, stack, compiled = {}, {}, 0, {}
  local current, faults = nil, {}
  local function texture(w, h, dpi)
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
    function o:getDPIScale()
      return self.dpi
    end
    function o:getPixelDimensions()
      return self.w * self.dpi, self.h * self.dpi
    end
    function o:setFilter(a, b)
      self.filter = { a, b }
    end
    function o:setWrap(a, b)
      if faults.wrap then
        error("unsupported wrap")
      end
      if faults.wrapFalse then
        return false
      end
      self.wrap = { a, b }
      return true
    end
    function o:release()
      T.check(not self.released, "resource released once")
      self.released = true
    end
    return o
  end
  local uniforms = {}
  local g = {
    getRendererInfo = function()
      return faults.es and "OpenGL ES" or "OpenGL", "2.0"
    end,
    newShader = function(f, v)
      if faults.compile then
        error("bad vertex")
      end
      compiled[#compiled + 1] = { f, v }
      local s = texture(0, 0)
      function s:hasUniform(id)
        return id ~= "g2_p_unused"
      end
      function s:send(id, value)
        uniforms[id] = value
      end
      return s
    end,
    newCanvas = function(w, h, opts)
      if faults.canvas then
        error("allocation failed")
      end
      return texture(w, h, opts.dpiscale)
    end,
    push = function()
      stack = stack + 1
    end,
    pop = function()
      stack = stack - 1
    end,
    setCanvas = function(c)
      current = c
    end,
    setShader = function() end,
    origin = function() end,
    setScissor = function() end,
    setStencilTest = function() end,
    setDepthMode = function() end,
    setColorMask = function() end,
    setBlendMode = function() end,
    setColor = function() end,
    draw = function(input, x, y, r, sx, sy)
      if faults.draw then
        error("draw failed")
      end
      T.check(input ~= current, "never samples current target")
      draws[#draws + 1] = { input, sx, sy }
    end,
  }
  return Presets.new({ fs = fs, graphics = g }),
    meta,
    files,
    faults,
    uniforms,
    objects,
    draws,
    compiled,
    texture,
    function()
      return stack
    end
end
-- Both stages must exist; rejected choices preserve the current effect and options.
do
  local p, meta, files, faults, uniforms, objects, draws, compiled = fixture()
  T.check(p:activate("builtin:warm"), "activate fallback")
  local old = p.shader
  local opts = { shaderPreset = "builtin:warm" }
  files["v.glsl"] = nil
  T.check(not p:select(opts, "local:test"), "missing vertex rejected")
  T.eq(p.shader, old, "missing vertex preserves working effect")
  T.eq(opts.shaderPreset, "builtin:warm", "missing vertex preserves save")
  files["v.glsl"] = "vertex"
  faults.compile = true
  T.check(not p:select(opts, "local:test"), "GPU compile failure rejected")
  T.eq(p.shader, old, "compile failure preserves working effect")
  faults.compile, faults.wrapFalse = nil, true
  T.check(not p:select(opts, "local:test"), "GPU wrapping rejection aborts selection")
  T.eq(p.shader, old, "unsupported wrapping preserves working effect")
  T.eq(opts.shaderPreset, "builtin:warm", "unsupported wrapping preserves save")
  faults.wrapFalse, faults.es = nil, true
  T.check(p:select(opts, "local:test"), "GLES import selected")
  T.same(compiled[#compiled], { "ES fragment", "ES vertex" }, "GLES selects matching pair")
  T.eq(uniforms.g2_p_gain, 0.5, "parameter alias sent")
  T.eq(uniforms.g2_p_unused, nil, "optimized-out parameter allowed")
  T.check(p:setParameter(opts, "gain", 0.79), "public parameter ID")
  T.check(math.abs(opts.shaderPresetParams["local:test"].gain - 0.8) < 0.001, "saved using public ID")
  p:off()
end
-- Imported metadata cannot inject paths, filtering modes or reserved parameter names.
for _, change in ipairs({
  function(m)
    m.vertex = "../escape.glsl"
  end,
  function(m)
    m.esShader = false
  end,
  function(m)
    m.esVertex = nil
  end,
  function(m)
    m.filter = "cubic"
  end,
  function(m)
    m.wrap = "unknown"
  end,
  function(m)
    m.parameters[1].id = "g2_Source"
  end,
}) do
  local p, meta = fixture()
  change(meta)
  T.check(p:list()[3].error ~= nil, "malformed imported descriptor remains INVALID")
  T.check(not p:activate("local:test"), "malformed imported descriptor cannot activate")
end
-- Physical input size, private filtering/wrapping, target lifetime and error recovery.
do
  local p, meta, files, faults, uniforms, objects, draws, compiled, texture, stack = fixture()
  local input = texture(80, 60, 2.75)
  T.check(p:activate("local:test"), "desktop import selected")
  T.same(compiled[1], { "fragment", "vertex" }, "desktop selects matching pair")
  local output = p:apply(input, 11)
  T.neq(output, input, "post-process returns output")
  T.eq(output:getDPIScale(), 2.75, "DPI preserved")
  T.same(uniforms.g2_SourceSize, { 20, 15, 1 / 20, 1 / 15 }, "physical native source size and reciprocals")
  T.same(uniforms.g2_OriginalSize, uniforms.g2_SourceSize, "original is source for first pass")
  T.same(uniforms.g2_OutputSize, { 220, 165, 1 / 220, 1 / 165 }, "physical output size and reciprocals")
  T.same(uniforms.g2_FinalViewportSize, uniforms.g2_OutputSize, "single-pass final viewport")
  local sampled = p.importInput
  T.eq(uniforms.g2_Source, sampled, "source sampler receives private texture")
  T.same(sampled.filter, { "linear", "linear" }, "preset filter only on private source")
  T.same(sampled.wrap, { "repeat", "repeat" }, "preset wrap only on private source")
  T.eq(input.filter, nil, "input texture untouched")
  T.eq(p:apply(output, 11), output, "output feedback guarded")
  T.eq(p:apply(sampled, 11), sampled, "private input feedback guarded")
  local n = #objects
  p:apply(input, 11)
  T.eq(#objects, n, "stable dimensions reuse targets")
  p:apply(input, 5.5)
  T.check(sampled.released, "old native grid released on scale change")
  T.eq(p.importInput:getWidth(), 40, "new native grid allocated")
  faults.draw = true
  T.eq(p:apply(input, 5.5), input, "draw error returns unfiltered input")
  T.eq(stack(), 0, "draw error restores graphics stack")
  T.check(not p:active() and p.importInput == nil, "draw error releases private resources")
  T.check(not input.released, "caller input never released")
end
for _, fault in ipairs({ "wrap", "canvas" }) do
  local p, meta, files, faults, uniforms, objects, draws, compiled, texture, stack = fixture()
  T.check(p:activate("local:test"), "activate before " .. fault .. " failure")
  faults[fault] = true
  local input = texture(32, 24)
  T.eq(p:apply(input, 2), input, fault .. " error returns input")
  T.check(not p:active() and p.importInput == nil and p.output == nil, fault .. " error releases resources")
  T.eq(stack(), 0, fault .. " error balances graphics stack")
end
T.finish("slang presets")
