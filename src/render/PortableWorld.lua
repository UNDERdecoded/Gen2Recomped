-- The renderData.v1 world pipeline boundary. Native pipeline contexts stay
-- private; only detached frame metrics cross into a portable world renderer.
local Version = require("src.core.GameVersion")
local W = {}
local unpack = table.unpack or unpack
local function pack(...)
  return { n = select("#", ...), ... }
end
local function finite(n)
  return type(n) == "number" and n == n and math.abs(n) < math.huge
end
local function positive(n)
  return finite(n) and n > 0
end

function W.context(ctx)
  if Version.generation() ~= 3 or type(ctx) ~= "table" then
    return nil
  end
  local state, camera = ctx.state, ctx.cam
  local mapId = state and state.map and state.map.id
  if type(mapId) ~= "string" or #mapId == 0 or #mapId > 160 then
    return nil
  end
  local pw, ph, uw, uh =
    ctx.pixelWidth or ctx.width, ctx.pixelHeight or ctx.height, ctx.unitWidth, ctx.unitHeight
  -- The viewport extension is optional. Observe it only when it is already
  -- loaded; do not bootstrap a game/viewport on an otherwise native host.
  local viewport = package.loaded["src.render.GameViewport"]
  if type(viewport) == "table" and viewport.active() then
    pw, ph = viewport.pixelDimensions()
    uw, uh = viewport.dimensions()
  end
  if
    not (
      positive(pw)
      and positive(ph)
      and positive(uw)
      and positive(uh)
      and positive(ctx.vw)
      and positive(ctx.vh)
      and camera
      and finite(camera.x)
      and finite(camera.y)
      and finite(ctx.level or 0)
    )
  then
    return nil
  end
  return {
    version = 1,
    generation = 3,
    mapId = mapId,
    width = pw,
    height = ph,
    pixelWidth = pw,
    pixelHeight = ph,
    unitWidth = uw,
    unitHeight = uh,
    dpiX = pw / uw,
    dpiY = ph / uh,
    viewWidth = ctx.vw,
    viewHeight = ctx.vh,
    level = ctx.level or 0,
    camera = { x = camera.x, y = camera.y },
  }
end

function W.isCanvas(value)
  if type(value) ~= "userdata" and type(value) ~= "table" then
    return false
  end
  local ok, w, h = pcall(function()
    if value.isCanvas then
      if not value:isCanvas() then
        return nil
      end
    elseif value.typeOf and not value:typeOf("Canvas") then
      return nil
    end
    if not value.getDimensions or not value.getWidth or not value.getHeight then
      return nil
    end
    return value:getDimensions()
  end)
  return ok and positive(w) and positive(h)
end

-- Invoked inside Pipelines.guard (error attribution/retirement), independently
-- of the legacy graphics fence. A portable callback cannot pop its caller's
-- state; leaked pushes and redirected targets are restored even on failure.
local function scoped(callback, ...)
  local args = pack(...)
  local g = love.graphics
  local target, push, pop = pack(g.getCanvas()), g.push, g.pop
  local before = g.getStackDepth and g.getStackDepth()
  push("all")
  local depth = 0
  g.push = function(...)
    local out = pack(push(...))
    depth = depth + 1
    return unpack(out, 1, out.n)
  end
  g.pop = function(...)
    if depth <= 0 then
      error("portable world callback cannot pop caller state", 0)
    end
    local out = pack(pop(...))
    depth = depth - 1
    return unpack(out, 1, out.n)
  end
  local ok, result = pcall(callback, unpack(args, 1, args.n))
  g.push, g.pop = push, pop
  if before and g.getStackDepth then
    local current = g.getStackDepth()
    if current < before + 1 then
      g.setCanvas(unpack(target, 1, target.n))
      error("portable world callback removed its graphics guard", 0)
    end
    depth = current - before - 1
  end
  for _ = 1, depth do
    pcall(pop)
  end
  local restored, why = pcall(pop)
  g.setCanvas(unpack(target, 1, target.n))
  if not restored then
    error(why, 0)
  end
  if not ok then
    error(result, 0)
  end
  return result
end
function W.draw(callback, native, canvas)
  local context = W.context(native)
  if not context then
    return nil
  end
  local result = scoped(function()
    local g = love.graphics
    g.origin()
    g.setShader()
    g.setScissor()
    g.setDepthMode()
    g.setColor(1, 1, 1, 1)
    g.setBlendMode("alpha", "alphamultiply")
    if canvas ~= nil then
      return callback(canvas, context)
    end
    return callback(context)
  end)
  return W.isCanvas(result) and result or nil
end
function W.invalidate(callback)
  return scoped(callback)
end
return W
