-- Optional game rectangle inside the OS window. No canvas on the default path.
local Runtime = require("src.mods.Runtime")
local Scope = require("src.render.GraphicsScope")
local Logger = require("src.core.Logger")
local V = {}
local function finite(v)
  return type(v) == "number" and v == v and math.abs(v) < math.huge
end
local function release()
  if V.canvas then
    if love and love.graphics and love.graphics.getCanvas and love.graphics.getCanvas() == V.canvas then
      love.graphics.setCanvas()
    end
    if V.canvas.release then
      pcall(V.canvas.release, V.canvas)
    end
  end
  V.canvas = nil
end
function V.reset()
  if V.inFrame then
    V.retiring = true
    return
  end
  release()
  V.skinFill = false
  V.rect = nil
  V.full = nil
  V.generation = nil
  V.frameActive = false
  V.retiring = nil
  V.failedSize = nil
end
local function rect(value, w, h)
  if type(value) ~= "table" or getmetatable(value) ~= nil then
    value = {}
  end
  local function field(k, default)
    local v = rawget(value, k)
    return finite(v) and math.floor(v) or default
  end
  local x, y = field("x", 0), field("y", 0)
  x = math.max(0, math.min(x, w - 1))
  y = math.max(0, math.min(y, h - 1))
  return {
    x = x,
    y = y,
    width = math.max(1, math.min(field("width", w), w - x)),
    height = math.max(1, math.min(field("height", h), h - y)),
  },
    rawget(value, "capture") == true
end
function V.begin(generation, allowed)
  -- A previous frame can have been interrupted by a state error or launcher exit.
  V.inFrame = false
  if V.retiring then
    V.reset()
  end
  local G = love.graphics
  local w, h = G.getDimensions()
  w = finite(w) and math.max(1, w) or 1
  h = finite(h) and math.max(1, h) or 1
  local pw, ph = w, h
  if G.getPixelDimensions then
    pw, ph = G.getPixelDimensions()
  end
  pw = finite(pw) and math.max(1, pw) or w
  ph = finite(ph) and math.max(1, ph) or h
  local context =
    { width = w, height = h, pixelWidth = pw, pixelHeight = ph, dpiX = pw / w, dpiY = ph / h, generation = generation }
  local requested, skinFill
  if allowed ~= false then
    local Skin = require("src.core.TouchSkin")
    local ok, x, y, sw, sh, fill = pcall(Skin.viewport, w, h)
    if ok and finite(x) and finite(y) and finite(sw) and finite(sh) and sw > 0 and sh > 0 then
      requested = { x = x, y = y, width = sw, height = sh }
      skinFill = fill == true
    end
  end
  local skinRequest = requested
  if allowed ~= false and Runtime.wantsHook("render.viewport") then
    local ok, value = Scope.call(function()
      return Runtime.call("render.viewport", function()
        return skinRequest or { x = 0, y = 0, width = w, height = h }
      end, context)
    end)
    if ok then
      requested = value
    else
      Logger.warn("render viewport failed: %s", tostring(value))
    end
  end
  -- Retain real metrics independently of mutations to the hook argument.
  V.full =
    { width = w, height = h, pixelWidth = pw, pixelHeight = ph, dpiX = pw / w, dpiY = ph / h, generation = generation }
  local r, capture = rect(requested, w, h)
  local active = capture or r.x ~= 0 or r.y ~= 0 or r.width ~= w or r.height ~= h
  V.rect, V.generation, V.frameActive = r, generation, active
  V.skinFill = skinFill == true and requested == skinRequest
  if active then
    local key = table.concat({ r.width, r.height, pw / w, ph / h }, ":")
    if V.failedSize ~= key then
      V.failedSize = nil
    end
    if V.failedSize == key then
      active = false
    elseif
      not V.canvas
      or V.canvas:getWidth() ~= r.width
      or V.canvas:getHeight() ~= r.height
      or V.canvasDpiX ~= pw / w
      or V.canvasDpiY ~= ph / h
    then
      release()
      local ok, canvas = pcall(G.newCanvas, r.width, r.height)
      if ok and canvas then
        V.canvas = canvas
        canvas:setFilter("nearest", "nearest")
        V.canvasDpiX, V.canvasDpiY = pw / w, ph / h
      else
        V.failedSize = key
        active = false
        Logger.warn("render viewport unavailable: %s", tostring(canvas))
      end
    end
  else
    release()
    V.failedSize = nil
  end
  if not active then
    V.frameActive = false
    V.skinFill = false
    V.rect = { x = 0, y = 0, width = w, height = h }
  end
  V.inFrame = true
  return V.rect
end
function V.active()
  return V.frameActive == true and V.canvas ~= nil
end
function V.dimensions()
  if V.active() then
    return V.rect.width, V.rect.height
  end
  return love.graphics.getDimensions()
end
function V.pixelDimensions()
  if V.active() then
    if V.canvas.getPixelDimensions then
      return V.canvas:getPixelDimensions()
    end
    return math.max(1, math.floor(V.rect.width * V.full.dpiX)),
      math.max(1, math.floor(V.rect.height * V.full.dpiY))
  end
  if love.graphics.getPixelDimensions then
    return love.graphics.getPixelDimensions()
  end
  return love.graphics.getDimensions()
end
function V.fullDimensions()
  if V.full then
    return V.full.width, V.full.height
  end
  return love.graphics.getDimensions()
end
function V.target()
  return V.active() and V.canvas or nil
end
function V.setTarget()
  love.graphics.setCanvas(V.target())
end
function V.toLocal(x, y)
  local r = V.rect
  if not r then
    return x, y, true
  end
  local lx, ly = x - r.x, y - r.y
  return lx, ly, lx >= 0 and ly >= 0 and lx < r.width and ly < r.height
end
function V.localSafeRect(x, y, w, h)
  if not V.active() then
    return x, y, w, h
  end
  local r = V.rect
  local x1, y1 = math.max(x, r.x), math.max(y, r.y)
  local x2, y2 = math.min(x + w, r.x + r.width), math.min(y + h, r.y + r.height)
  if x2 <= x1 or y2 <= y1 then
    return 0, 0, r.width, r.height
  end
  return x1 - r.x, y1 - r.y, x2 - x1, y2 - y1
end
local function prepare()
  local G = love.graphics
  G.setCanvas()
  G.origin()
  G.setScissor()
  G.setShader()
  G.setBlendMode("alpha")
  G.setColor(1, 1, 1, 1)
end
function V.finish(game)
  if V.active() then
    local G = love.graphics
    local r, full = V.rect, V.full
    local context = {
      canvas = V.canvas,
      x = r.x,
      y = r.y,
      width = r.width,
      height = r.height,
      windowWidth = full.width,
      windowHeight = full.height,
      dpiX = full.dpiX,
      dpiY = full.dpiY,
      generation = V.generation,
    }
    G.setCanvas()
    local function vanilla(_, ctx)
      -- A failing outer link must not taint the default draw reached by next.
      local canvas = type(ctx) == "table" and rawget(ctx, "canvas")
      local x = type(ctx) == "table" and rawget(ctx, "x")
      local y = type(ctx) == "table" and rawget(ctx, "y")
      if not canvas or not finite(x) or not finite(y) then
        error("invalid render.window context", 0)
      end
      local ok, why = Scope.call(function()
        prepare()
        G.draw(canvas, x, y)
      end)
      if not ok then
        error(why, 0)
      end
    end
    local ok, why = Scope.call(function()
      prepare()
      G.clear(0, 0, 0, 1)
      return Runtime.call("render.window", vanilla, game, context)
    end)
    if not ok then
      Logger.warn("render window failed: %s", tostring(why))
      Scope.call(function()
        prepare()
        G.clear(0, 0, 0, 1)
        G.draw(V.canvas, r.x, r.y)
      end)
    end
  end
  V.inFrame = false
  if V.retiring then
    V.reset()
  end
end
return V
