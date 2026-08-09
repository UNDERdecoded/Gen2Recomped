-- Minimal love API stub so game logic can run headless under plain Lua
-- (lua5.4 tests/run_tests.lua).  Graphics calls are no-ops that record
-- enough state for assertions.

local stub = {}

local function noop() end

local Image = {}
Image.__index = Image
function Image:getDimensions() return self.w, self.h end
function Image:getWidth() return self.w end
function Image:getHeight() return self.h end

-- read PNG dimensions from the file header (no decoder needed)
local function pngSize(path)
  local f = io.open(path, "rb")
  if not f then return 8, 8 end
  local header = f:read(24)
  f:close()
  if not header or #header < 24 then return 8, 8 end
  local function be32(s, i)
    local a, b, c, d = s:byte(i, i + 3)
    return ((a * 256 + b) * 256 + c) * 256 + d
  end
  return be32(header, 17), be32(header, 21)
end

local files = {} -- in-memory love.filesystem

-- Minimal graphics-state tracking so push("all")/pop actually save and
-- restore, and getShader/getCanvas/etc can be read back.  The render-pipeline
-- fold fences each mod callback between push("all")/pop so a callback that
-- dirties state cannot leak into the engine composite; mod_render_tests
-- asserts exactly that, which needs the stub to model the save/restore rather
-- than no-op it.  Plain push()/pop() (the tilt upright pass) ride the same
-- stack and restore the same fields, which for those call sites is a no-op.
local gstate = { shader = nil, canvas = nil, blend = "alpha",
                 color = { 1, 1, 1, 1 } }
local gstack = {}

stub.graphics = {
  newImage = function(path)
    local w, h = pngSize(path)
    return setmetatable({ w = w, h = h, path = path }, Image)
  end,
  newQuad = function(x, y, w, h) return { x = x, y = y, w = w, h = h } end,
  newCanvas = function(w, h)
    return setmetatable({ w = w, h = h, setFilter = noop }, Image)
  end,
  newSpriteBatch = function(image, size)
    local batch = { image = image, sprites = {} }
    function batch:add(quad, x, y) table.insert(self.sprites, { quad, x, y }) end
    function batch:clear() self.sprites = {} end
    function batch:setTexture(tex) self.texture = tex end
    return batch
  end,
  draw = noop, rectangle = noop, clear = noop,
  setDefaultFilter = noop, print = noop, printf = noop,
  line = noop, circle = noop, setLineWidth = noop,
  -- Fonts: the save editor lays itself out from font metrics, so a headless
  -- draw needs measurable text.  A fixed 6px advance / 12px line is enough
  -- for the layout to be exercised (tests assert state, never pixels).
  -- newMesh / stencil stay absent on purpose: tools/save-editor/Theme.lua
  -- probes for them and falls back to flat fills, which is the path a
  -- headless run should take.
  newFont = function(size)
    local px = size or 12
    return {
      getWidth = function(_, text) return #tostring(text) * math.max(1, px * 0.5) end,
      getHeight = function() return px end,
    }
  end,
  setFont = function(f) gstate.font = f end,
  getFont = function() return gstate.font end,
  setColor = function(r, g, b, a) gstate.color = { r, g, b, a } end,
  getColor = function()
    local c = gstate.color
    return c[1], c[2], c[3], c[4]
  end,
  setCanvas = function(c) gstate.canvas = c or nil end,
  getCanvas = function() return gstate.canvas end,
  setShader = function(s) gstate.shader = s or nil end,
  getShader = function() return gstate.shader end,
  setBlendMode = function(m) gstate.blend = m or "alpha" end,
  getBlendMode = function() return gstate.blend end,
  -- coordinate-transform + state stack used by the tilt-mode upright pass
  -- (billboards) and the render-pipeline fold; push snapshots the tracked
  -- state, pop restores it (tests that need to observe the transforms swap
  -- in their own recorders, e.g. tests/parity_tilt.lua)
  push = function()
    gstack[#gstack + 1] = { shader = gstate.shader, canvas = gstate.canvas,
                            blend = gstate.blend, color = gstate.color }
  end,
  pop = function()
    local s = gstack[#gstack]
    if s then
      gstack[#gstack] = nil
      gstate.shader, gstate.canvas = s.shader, s.canvas
      gstate.blend, gstate.color = s.blend, s.color
    end
  end,
  translate = noop, scale = noop,
  rotate = noop, origin = noop, setScissor = noop,
  getDimensions = function() return 640, 576 end,
  -- dpi=1 desktop default; issue #87 tests override these for Android density
  getPixelDimensions = function() return 640, 576 end,
  getDPIScale = function() return 1 end,
}

stub.math = {
  random = function(a, b)
    if a == nil then return math.random() end
    if b == nil then return math.random(a) end
    return math.random(a, b)
  end,
}

stub.filesystem = {
  write = function(name, content) files[name] = content return true end,
  read = function(name) return files[name] end,
  remove = function(name) files[name] = nil return true end,
  -- directories are implied by key prefixes ("mods/x/manifest.json")
  getInfo = function(name)
    if files[name] then return { type = "file" } end
    local prefix = name .. "/"
    for key in pairs(files) do
      if key:sub(1, #prefix) == prefix then return { type = "directory" } end
    end
    return nil
  end,
  load = function(name)
    if not files[name] then return nil, "no file" end
    return load(files[name], name)
  end,
  getDirectoryItems = function(name)
    local seen, items = {}, {}
    name = name or ""
    -- "" / "/" = save-dir root (RomImporter Android ROM scan)
    if name == "" or name == "/" then
      for key in pairs(files) do
        local child = key:match("^[^/]+")
        if child and not seen[child] then
          seen[child] = true
          items[#items + 1] = child
        end
      end
    else
      local prefix = name .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
    end
    table.sort(items)
    return items
  end,
}

-- table-backed SoundData so ChipAudio's offline render seam
-- (_renderMusicForTest) runs headless; modkit bounce writes WAVs from it
local SoundData = {}
SoundData.__index = SoundData
local function slot(self, index, channel)
  return index * self.channels + (channel - 1) + 1
end
function SoundData:setSample(index, a, b)
  if b == nil then
    self.data[slot(self, index, 1)] = a
  else
    self.data[slot(self, index, a)] = b
  end
end
function SoundData:getSample(index, channel)
  return self.data[slot(self, index, channel or 1)] or 0
end
function SoundData:getSampleCount() return self.samples end
function SoundData:getSampleRate() return self.rate end
function SoundData:getBitDepth() return self.bits end
function SoundData:getChannelCount() return self.channels end
function SoundData:getDuration() return self.samples / self.rate end

stub.sound = {
  newSoundData = function(samples, rate, bits, channels)
    return setmetatable({ samples = samples, rate = rate or 44100,
      bits = bits or 16, channels = channels or 1, data = {} }, SoundData)
  end,
}

stub.keyboard = { isDown = function() return false end }

stub.mouse = {
  getPosition = function() return 0, 0 end,
  isCursorSupported = function() return false end,
  getSystemCursor = function(name) return name end,
  setCursor = function() end,
}

stub.timer = { getTime = function() return 0 end }

-- Desktop / headless: full-window safe area (matches LÖVE's fallback).
stub.window = {
  getSafeArea = function()
    local ww, wh = stub.graphics.getDimensions()
    return 0, 0, ww, wh
  end,
}

return stub
