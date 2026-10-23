package.path = "./?.lua;./?/init.lua;" .. package.path
local T = require("tests.modkit")
local V = require("src.core.GameVersion")
local W = require("src.render.PortableWorld")
local P = require("src.render.Pipelines")
V.set("firered")
local g = love.graphics
g.setDepthMode = function() end
local function canvas(w, h)
  return {
    getDimensions = function()
      return w, h
    end,
    getWidth = function()
      return w
    end,
    getHeight = function()
      return h
    end,
    typeOf = function(_, kind)
      return kind == "Canvas"
    end,
  }
end
local raw = {
  state = { map = { id = "TEST" } },
  cam = { x = -8.5, y = 20 },
  vw = 240,
  vh = 160,
  width = 800,
  height = 600,
  pixelWidth = 800,
  pixelHeight = 600,
  unitWidth = 400,
  unitHeight = 200,
  level = 1,
  drawFx = function()
    error("native closure")
  end,
}
local public = assert(W.context(raw))
T.eq(public.version, 1, "version negotiated by pipeline format")
T.eq(public.dpiX, 2, "horizontal physical scale")
T.eq(public.dpiY, 3, "vertical physical scale")
T.eq(public.camera.x, -8.5, "fractional native camera coordinates")
T.eq(public.state, nil, "no native state")
T.eq(public.drawFx, nil, "no native draw closures")
public.camera.x = 99
T.eq(raw.cam.x, -8.5, "camera observation is detached")
local originalViewport = package.loaded["src.render.GameViewport"]
package.loaded["src.render.GameViewport"] = {
  active = function()
    return true
  end,
  pixelDimensions = function()
    return 600, 360
  end,
  dimensions = function()
    return 300, 120
  end,
}
T.eq(assert(W.context(raw)).pixelWidth, 600, "capture respects the game viewport")
T.eq(assert(W.context(raw)).unitHeight, 120, "viewport logical height")
package.loaded["src.render.GameViewport"] = originalViewport
for _, version in ipairs({ "red", "gold", "platinum" }) do
  V.set(version)
  T.eq(W.context(raw), nil, "Gen3-only context")
end
V.set("firered")
for _, bad in ipairs({ 0, -1, 0 / 0, 1 / 0, "800" }) do
  raw.pixelWidth = bad
  T.eq(W.context(raw), nil, "invalid physical metric rejected")
end
raw.pixelWidth = 800
local target, out = canvas(10, 10), canvas(800, 600)
g.setCanvas(target)
g.setColor(0.1, 0.2, 0.3, 1)
g.setShader("caller")
g.setBlendMode("replace")
local def = {
  label = "Test",
  worldFormat = "renderData.v1",
  drawWorld = function(ctx)
    T.eq(ctx.mapId, "TEST", "public pipeline invocation")
    T.eq(g.getShader(), nil, "identity shader on entry")
    T.eq(g.getBlendMode(), "alpha", "known blending on entry")
    g.push("all")
    g.setCanvas(out)
    g.setShader("foreign")
    return out
  end,
}
P.install({ render_pipelines = { probe = def } })
P.setLevel("probe", 1)
T.eq(P.worldPipeline(), "probe", "portable pipeline selected")
T.eq(P.drawWorld("probe", raw), out, "canvas ownership")
T.eq(g.getCanvas(), target, "borrowed target restored after leaked push")
T.eq(g.getShader(), "caller", "caller shader restored")
T.eq(g.getBlendMode(), "replace", "caller blend restored")
for _, result in ipairs({
  true,
  1,
  "image",
  {
    getWidth = function()
      return 1
    end,
    getHeight = function()
      return 1
    end,
  },
}) do
  def.drawWorld = function()
    return result
  end
  T.eq(P.drawWorld("probe", raw), nil, "invalid return means native fallback")
end
def.drawWorld = function()
  return {
    typeOf = function()
      return false
    end,
    getDimensions = function()
      return 1, 1
    end,
  }
end
T.eq(P.drawWorld("probe", raw), nil, "images cannot claim a world canvas")
def.drawWorld = function()
  return {
    getDimensions = function()
      error("released")
    end,
    getWidth = function() end,
    getHeight = function() end,
  }
end
T.eq(P.drawWorld("probe", raw), nil, "released canvas rejected")
def.drawWorld = function()
  g.setCanvas(out)
  g.pop()
  return out
end
T.eq(P.drawWorld("probe", raw), nil, "over-pop becomes a recoverable callback failure")
T.eq(g.getCanvas(), target, "target restored after over-pop")
def.drawWorld = function()
  g.setCanvas(out)
  error("GPU callback")
end
for _ = 1, 10 do
  T.eq(P.drawWorld("probe", raw), nil, "throw falls back")
end
T.eq(P.worldPipeline(), nil, "repeated failures retire the pipeline")
-- A legacy callback retains exactly the original context.
P.install({
  render_pipelines = {
    legacy = {
      label = "Legacy",
      drawWorld = function(ctx)
        T.eq(ctx, raw, "legacy ctx unchanged")
        return out
      end,
    },
  },
})
T.eq(P.drawWorld("legacy", raw), out, "legacy rendering unchanged")
local modern = {
  isCanvas = function()
    return true
  end,
  typeOf = function()
    return false
  end,
  getWidth = function()
    return 16
  end,
  getHeight = function()
    return 16
  end,
  getDimensions = function()
    return 16, 16
  end,
}
T.check(W.isCanvas(modern), "LÖVE 12 renderable Texture is accepted")
modern.isCanvas = function()
  return false
end
T.eq(W.isCanvas(modern), false, "LÖVE 12 ordinary Texture is rejected")
P.install({
  render_pipelines = {
    post = {
      label = "Post",
      worldFormat = "renderData.v1",
      worldPresent = function(input, ctx)
        T.eq(input, out, "world post-process receives borrowed canvas")
        T.eq(ctx.state, nil, "portable post-process context")
        g.setCanvas(out)
        g.push("all")
        return input
      end,
      invalidate = function()
        g.push("all")
        g.setCanvas(out)
      end,
    },
  },
})
P.setLevel("post", 1)
T.eq(P.worldPresent(out, raw), out, "portable post-process result")
T.eq(g.getCanvas(), target, "world post-process restores target")
P.invalidate()
T.eq(g.getCanvas(), target, "invalidation restores target after a leaked push")
T.finish("Portable world pipeline boundary")
