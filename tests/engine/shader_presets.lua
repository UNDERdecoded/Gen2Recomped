package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local Presets = require("src.render.ShaderPresets")
local Json = require("src.link.Json")
local Menu = require("src.ui.ShaderPresetMenu")
local SaveData = require("src.core.SaveData")
local GenOptions = require("src.core.GenOptions")
local StateStack = require("src.core.StateStack")
local source =
  "extern number amount; vec4 effect(vec4 c, Image t, vec2 u, vec2 p) { return Texel(t,u)*amount*c; }"
local metadata = {
  format = 1,
  name = "LOCAL EFFECT",
  shader = "probe.glsl",
  parameters = {
    { id = "amount", name = "AMOUNT", min = 0, max = 1, step = 0.1, default = 0.5 },
  },
}
local function clone(t)
  if type(t) ~= "table" then
    return t
  end
  local out = {}
  for k, v in pairs(t) do
    out[k] = clone(v)
  end
  return out
end
local function fixture()
  local files =
    { ["shader-presets/probe.json"] = Json.encode(metadata), ["shader-presets/probe.glsl"] = source }
  local reads = 0
  local fs = {
    getDirectoryItems = function()
      return { "probe.json", "ignored.lua", "../escape.json" }
    end,
    getInfo = function(p)
      if files[p] then
        return { type = "file", size = #files[p] }
      end
    end,
    read = function(p)
      reads = reads + 1
      return files[p]
    end,
  }
  local state =
    { canvas = "original", shader = "old", color = "old", blend = "old", depth = "old", transform = "old" }
  local stack = {}
  local count = { shader = 0, canvas = 0, released = 0, draw = 0 }
  local faults = {}
  local function texture(w, h, dpi)
    local t = { w = w, h = h, dpi = dpi or 1 }
    function t:getDimensions()
      return self.w, self.h
    end
    function t:getWidth()
      return self.w
    end
    function t:getHeight()
      return self.h
    end
    function t:getDPIScale()
      return self.dpi
    end
    function t:getPixelDimensions()
      return self.w * self.dpi, self.h * self.dpi
    end
    function t:setFilter() end
    function t:release()
      T.check(not self.released, "GPU object released once")
      self.released = true
      count.released = count.released + 1
    end
    return t
  end
  local g = {
    newShader = function(s)
      count.shader = count.shader + 1
      if faults.compile then
        error("compile failed")
      end
      local sh = { uniforms = {} }
      function sh:hasUniform(id)
        return not faults.uniform and s:find(id, 1, true) ~= nil
      end
      function sh:send(id, v)
        if faults.send then
          error("uniform failed")
        end
        self.uniforms[id] = v
      end
      function sh:release()
        T.check(not self.released, "shader released once")
        self.released = true
        count.released = count.released + 1
      end
      return sh
    end,
    newCanvas = function(w, h, opts)
      if faults.canvas then
        error("allocation failed")
      end
      count.canvas = count.canvas + 1
      return texture(w, h, opts.dpiscale)
    end,
    push = function()
      if faults.push then
        error("stack full")
      end
      stack[#stack + 1] = clone(state)
    end,
    pop = function()
      state = table.remove(stack)
    end,
    setCanvas = function(v)
      state.canvas = v
    end,
    setShader = function(v)
      state.shader = v
    end,
    setColor = function()
      state.color = "changed"
    end,
    setBlendMode = function()
      state.blend = "changed"
    end,
    origin = function()
      state.transform = "changed"
    end,
    setScissor = function()
      state.scissor = "changed"
    end,
    setStencilTest = function()
      state.stencil = "changed"
    end,
    setDepthMode = function()
      state.depth = "changed"
    end,
    setColorMask = function()
      state.mask = "changed"
    end,
    draw = function(t)
      count.draw = count.draw + 1
      T.check(not t.released, "input remains valid")
      if faults.draw then
        error("draw failed")
      end
    end,
  }
  local p = Presets.new({ fs = fs, graphics = g })
  return p,
    files,
    fs,
    g,
    faults,
    count,
    texture,
    function()
      return reads
    end,
    function()
      return state, #stack
    end
end
-- OFF is a no-I/O/no-GPU identity path, including old save files.
do
  local p, files, fs, g, faults, count, texture, reads = fixture()
  local input = texture(10, 8)
  T.check(p:applyOptions({}), "old options accepted")
  T.eq(p:apply(input), input, "OFF exact identity")
  T.eq(count.shader, 0, "OFF never compiles")
  T.eq(count.canvas, 0, "OFF never allocates")
  T.eq(reads(), 0, "OFF never reads files")
  T.eq(p.scanned, nil, "OFF does not enumerate")
  T.check(p:applyOptions({ shaderPreset = "off" }), "explicit OFF accepted")
end
-- Real catalogue: bundled records, local JSON, isolated errors, no Lua loader.
do
  local p, files = fixture()
  local records = p:refresh()
  T.eq(#records, 3, "two builtins and one local preset")
  T.eq(records[3].id, "local:probe", "stable namespace")
  T.eq(records[3].parameters[1].default, 0.5, "parameters copied")
  files["shader-presets/probe.json"] = "not JSON"
  p:refresh()
  T.check(p.byId["local:probe"].error, "malformed metadata shown as invalid")
  for _, field in ipairs({ "shader", "name", "format", "parameters" }) do
    local raw = clone(metadata)
    raw[field] = ({ shader = "../escape.glsl", name = string.rep("a", 49), format = 2, parameters = "bad" })[field]
    files["shader-presets/probe.json"] = Json.encode(raw)
    p:refresh()
    T.check(p.byId["local:probe"].error, "invalid " .. field)
  end
  for _, change in ipairs({
    { id = "sourceSize" },
    { id = "love_bad" },
    { step = 0 },
    { step = 1e-300 },
    { max = 0 },
    { min = -1e308, max = 1e308 },
    { default = 2 },
  }) do
    local raw = clone(metadata)
    for k, v in pairs(change) do
      raw.parameters[1][k] = v
    end
    files["shader-presets/probe.json"] = Json.encode(raw)
    p:refresh()
    T.check(p.byId["local:probe"].error, "invalid parameter definition")
  end
end
-- An off-grid metadata default is normalized once, so reset and first use
-- agree instead of silently producing different uniform values.
do
  local p, files = fixture()
  local raw = clone(metadata)
  raw.parameters[1].default = 0.35
  raw.parameters[1].step = 0.2
  files["shader-presets/probe.json"] = Json.encode(raw)
  p:activate("local:probe")
  T.eq(p.values.amount, 0.4, "default snapped to step grid")
  local menu = Menu.parameters({ save = { options = {} } }, p)
  p:setParameter({}, "amount", 1)
  menu.rows[1].reset()
  T.eq(p.values.amount, 0.4, "reset agrees with normalized default")
end
-- Parameter normalization, saved identity, graphics state and target lifetime.
do
  local p, files, fs, g, faults, count, texture, reads, state = fixture()
  local opts = { shaderPresetParams = { ["local:probe"] = { amount = 0.72, unknown = 5 } } }
  T.check(p:select(opts, "local:probe"), "local selection compiles")
  T.eq(opts.shaderPreset, "local:probe", "selected ID persisted")
  T.check(math.abs(p.values.amount - 0.7) < 1e-9, "restored value snaps to step")
  local input = texture(100, 75, 2)
  local out = p:apply(input, 6)
  T.neq(out, input, "active effect allocates output")
  T.eq(out:getDPIScale(), 2, "DPI preserved")
  T.eq(out:getWidth(), 100, "units preserved")
  T.eq(count.canvas, 1, "one allocation")
  T.eq(p:apply(input, 6), out, "target reused")
  T.same(
    state(),
    { canvas = "original", shader = "old", color = "old", blend = "old", depth = "old", transform = "old" },
    "graphics state restored"
  )
  local _, depth = state()
  T.eq(depth, 0, "graphics stack balanced")
  p:setParameter(opts, "amount", 0.21)
  p:apply(input, 6)
  T.check(math.abs(p.shader.uniforms.amount - 0.2) < 1e-9, "new parameter sent")
  T.eq(count.shader, 1, "parameter edit never recompiles")
  T.eq(p:setParameter(opts, "missing", 1), nil, "unknown parameter refused")
  p:setParameter(opts, "amount", math.huge)
  T.eq(p.values.amount, 0.5, "non-finite parameter default")
  p:setParameter(opts, "amount", -3)
  T.eq(p.values.amount, 0, "parameter clamp")
  local resized = p:apply(texture(100, 75, 1), 3)
  T.check(out.released, "DPI change releases old target")
  T.eq(resized:getDPIScale(), 1, "DPI change reallocates")
  local released = count.released
  p:select(opts, "off")
  T.eq(count.released, released + 2, "OFF releases shader and canvas")
  T.eq(p:active(), false, "OFF inactive")
  T.eq(opts.shaderPresetParams["local:probe"].amount, 0, "OFF retains parameter settings")
end
for _, kind in ipairs({ "compile", "uniform", "send", "canvas", "push", "draw" }) do
  local p, files, fs, g, faults, count, texture, reads, state = fixture()
  local opts = { shaderPreset = "off" }
  local startup = kind == "compile" or kind == "uniform" or kind == "send"
  if startup then
    faults[kind] = true
  end
  local selected = p:select(opts, "local:probe")
  if startup then
    T.eq(selected, nil, kind .. " rejected")
    T.eq(opts.shaderPreset, "off", kind .. " not saved")
    T.eq(p:active(), false, kind .. " stays OFF")
  else
    T.check(selected, kind .. " setup")
    faults[kind] = true
    local input = texture(10, 8)
    T.eq(p:apply(input, 1), input, kind .. " exact fallback")
    T.eq(p:active(), false, kind .. " retired")
    local _, depth = state()
    T.eq(depth, 0, kind .. " balanced stack")
    T.eq(p:apply(input, 1), input, kind .. " no repeated failing work")
  end
  T.check(p.error and p.error ~= "", kind .. " records error")
  faults[kind] = nil
  T.check(p:select(opts, "local:probe"), kind .. " explicit retry")
end
-- Failed switches preserve the last working effect; missing saved files fall
-- back to OFF without changing a stored choice or touching gameplay data.
do
  local p, files, fs, g, faults, count, texture = fixture()
  local opts = { shaderPreset = "builtin:warm" }
  T.check(p:applyOptions(opts), "working saved preset")
  local sh = p.shader
  faults.compile = true
  T.eq(p:select(opts, "local:probe"), nil, "broken switch rejected")
  T.eq(p.shader, sh, "working shader retained")
  T.eq(opts.shaderPreset, "builtin:warm", "working saved choice retained")
  faults.compile = nil
  opts.shaderPreset = "local:deleted"
  local before = clone(opts)
  T.eq(p:applyOptions(opts), nil, "missing saved preset refused")
  T.eq(p:active(), false, "missing saved preset clears previous game shader")
  T.same(opts, before, "restore does not rewrite options")
  files["shader-presets/probe.glsl"] = string.rep("x", 65537)
  T.eq(p:activate("local:probe"), nil, "oversized source refused")
end
-- Selection, parameter controls/reset, error page, scrolling and back use the
-- real state stack; controls bypass the selected shader so they stay readable.
do
  local p = fixture()
  local key, writes = nil, 0
  local game = {
    save = { options = {} },
    stack = setmetatable({ states = {} }, { __index = StateStack }),
    input = {
      wasPressed = function(_, k)
        return k == key
      end,
    },
    writeOptions = function()
      writes = writes + 1
    end,
  }
  local menu = Menu.new(game, p)
  game.stack:push(menu)
  T.eq(menu.shaderPresetBypass, true, "shader picker readable")
  local function press(k)
    key = k
    game.stack:top():update()
    key = nil
  end
  press("down")
  press("a")
  T.eq(game.save.options.shaderPreset, "builtin:warm", "A selects preset")
  press("select")
  local params = game.stack:top()
  T.eq(params.isParameters, true, "SELECT opens parameters")
  press("right")
  T.check(p.values.strength > 0.4, "RIGHT edits")
  press("select")
  T.eq(p.values.strength, 0.4, "SELECT resets parameter")
  press("b")
  T.eq(game.stack:top(), menu, "back from parameters")
  press("up")
  press("a")
  T.eq(game.save.options.shaderPreset, "off", "OFF selection")
  press("up")
  press("a")
  T.eq(game.stack:top(), nil, "fixed BACK row exits")
  T.check(writes >= 4, "changes persist immediately")
  local msg = Menu.message(game, string.rep("long compile error ", 30))
  T.eq(#msg.rows, 4, "error page bounded")
  for _, row in ipairs(msg.rows) do
    T.check(#row.label <= 17 and #row.value() <= 17, "error text fits")
  end
end
-- Normal save serialization and per-generation option folds preserve both keys.
do
  local options =
    { shaderPreset = "local:probe", shaderPresetParams = { ["local:probe"] = { amount = 0.8 } } }
  local round = SaveData.mergeOptions(SaveData.decode(SaveData.encode(options)))
  T.same(round.shaderPresetParams, options.shaderPresetParams, "parameter save round trip")
  local base = { shaderPreset = "off", shaderPresetParams = {}, perGeneration = { [2] = options } }
  local resolved = GenOptions.resolve(base, 2)
  T.eq(resolved.shaderPreset, "local:probe", "generation-specific preset")
  resolved.shaderPreset = "builtin:warm"
  local folded = GenOptions.fold(base, resolved, 2)
  T.eq(folded.shaderPreset, "off", "shared setting unchanged")
  T.eq(folded.perGeneration[2].shaderPreset, "builtin:warm", "scoped write retained")
end
-- Options routing and emergency reset through the actual game entry point.
do
  local Game = require("src.core.Game")
  local rows = require("src.ui.OptionsMenu").buildRows({ save = { options = {} } })
  local row
  for _, r in ipairs(rows) do
    if r.id == "shaderPreset" then
      row = r
    end
  end
  T.check(row and row.activate, "shared shader options row")
  Presets.entry = { name = string.rep("X", 48) }
  T.check(128 + #row.value({}) * 8 <= 232, "preset value fits GBA value column with margin")
  Presets.entry = nil
  T.eq(require("src.ui.OptionsMenu").shaderPresetBypass, true, "GB options bypass")
  T.eq(require("src.ui.Gen3Options").shaderPresetBypass, true, "GBA options bypass")
  T.eq(require("src.ui.Gen4Options").shaderPresetBypass, true, "DS options bypass")
  for _, spec in ipairs({ { "emerald", "src.ui.Gen3Options" }, { "platinum", "src.ui.Gen4Options" } }) do
    local GV = require("src.core.GameVersion")
    local before = GV.get()
    GV.set(spec[1])
    local screen = require(spec[2]).new({ data = { constants = {} }, save = { options = {} } })
    local found = false
    for _, r in ipairs(screen.rows) do
      if r.key == "shaderPreset" and r.engine and r.engine.activate then
        found = true
      end
    end
    T.check(found, spec[1] .. " shader option reachable")
    GV.set(before)
  end
  local writes = 0
  local game = {
    save = { options = { shaderPreset = "local:bad" } },
    writeOptions = function()
      writes = writes + 1
    end,
    stack = {
      top = function()
        return {
          onKeyPressed = function()
            error("F8 was captured")
          end,
        }
      end,
    },
  }
  Game.keypressed(game, "f8")
  T.eq(game.save.options.shaderPreset, "off", "F8 saves OFF")
  T.eq(writes, 1, "F8 writes once before screen capture")
  local p = fixture()
  p:activate("builtin:warm")
  local menu = Menu.parameters(game, p)
  p:off()
  T.eq(menu.rows[1].value(), "OFF", "stale parameter page stays readable after reset")
  menu.rows[1].step(game, 1)
  menu.rows[1].reset()
end
Presets:off()
T.finish("shader presets")
