-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local root = assert(os.getenv("RENDER_BUDGET_QA_ROOT"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Json = require("src.link.Json")
local Profile = require("src.core.FrameProfile")
local Performance = require("src.core.Performance")
Performance.tier = "high"
require("src.core.GameVersion").set("crystal")
local V, libs = { sharedHulls = true }, {}
V.mod = { log = {
  warn = function(_, fmt, ...)
    print(fmt:format(...))
  end,
} }
V.require = function(name)
  if not libs[name] then
    libs[name] = assert(loadfile(root .. "/mods/DRAMATIC_SHAPE/lib/" .. name .. ".lua"))(V)
  end
  return libs[name]
end
V.data = function(name)
  return assert(loadfile(root .. "/mods/DRAMATIC_SHAPE/data/" .. name .. ".lua"))()
end
local phase, frame, total, fenced = 1, 0, 0, 0
libs.TerrainAtlas = {
  _animFrame = function()
    return frame
  end,
}
local Scale = V.require("RenderScale")
local Budget = V.require("WaterBudget")
local Water = V.require("Water")
local G = V.require("Voxel3D")
local Voxel = V.require("VoxelState")
local Scene = V.require("VoxelScene")
local State = V.require("ShaderState")
local Mat = V.require("Mat4")
local checks = 0
local function check(ok, message)
  assert(ok, message)
  checks = checks + 1
end
local function up(fn, name)
  for i = 1, 100 do
    local n, v = debug.getupvalue(fn, i)
    if n == name then
      return v
    end
    if not n then
      break
    end
  end
  error("missing upvalue " .. name)
end
local function solid(r, g, b)
  local d = love.image.newImageData(2, 2)
  d:mapPixel(function()
    return r, g, b, 1
  end)
  local image = love.graphics.newImage(d)
  d:release()
  return image
end
local function quad(x0, z0, x1, z1, y)
  return love.graphics.newMesh(G.FORMAT, {
    { x0, y, z0, 0, 0, 1 },
    { x1, y, z0, 1, 0, 1 },
    { x1, y, z1, 1, 1, 1 },
    { x0, y, z0, 0, 0, 1 },
    { x1, y, z1, 1, 1, 1 },
    {
      x0,
      y,
      z1,
      0,
      1,
      1,
    },
  }, "triangles", "static")
end
local water, wall, blue, red
local function draw(read)
  check(G.beginScene(640, 480, 400, 400, 160, 144), "scene unavailable")
  G.draw(wall, red)
  local before
  if read then
    G.endScene()
    before = G.canvas():newImageData()
    assert(G.beginScene(640, 480, 400, 400, 160, 144))
    G.draw(wall, red)
  end
  Scene.drawWater({ { water, blue, nil } })
  G.endScene()
  if read then
    local after = G.canvas():newImageData()
    local count = 0
    for y = 0, 479, 4 do
      for x = 0, 639, 4 do
        local r, g, b, a = before:getPixel(x, y)
        if r > 0.1 and r > g * 2 and r > b * 2 then
          local rr, gg, bb = after:getPixel(x, y)
          check(r == rr and g == gg and b == bb, "half water covered foreground geometry")
          count = count + 1
        end
      end
    end
    check(count > 100, "foreground negative control had no pixels")
    local f = assert(
      io.open(
        assert(os.getenv("RENDER_BUDGET_QA_OUT")) .. "/" .. (V.renderBudget and "budget" or "legacy") .. ".png",
        "wb"
      )
    )
    f:write(after:encode("png"):getString())
    f:close()
    before:release()
    local bytes = after:getString()
    after:release()
    return bytes
  end
end
local function qualify()
  local osName = love.system.getOS
  love.system.getOS = function()
    return "Android"
  end
  check(Scale.factor() == 2, "mobile AUTO is not 2X")
  check(Budget.defaultLevel() == 1, "mobile default is not SKY")
  love.system.getOS = osName
  check(Scale.factor() == 1, "desktop AUTO changed native scale")
  Scale.setting:sync(3)
  local w, h = Scale.size(641, 481)
  check(w == 214 and h == 161, "render scale rounding changed")
  V.renderBudget = false
  check(Scale.factor() == 1, "P8 rollback still scales")
  V.renderBudget = true
  Scale.setting:sync("auto")
  local source = solid(0.2, 0.6, 0.8)
  local out = Scale.present(source, 8, 8)
  local d = out:newImageData()
  local r, g, b = d:getPixel(7, 7)
  check(
    math.abs(r - 0.2) < 0.005 and math.abs(g - 0.6) < 0.005 and math.abs(b - 0.8) < 0.005,
    "nearest upscale lost extent/color"
  )
  d:release()
  source:release()
  local calls = 0
  local shader = {
    send = function(_, name)
      calls = calls + 1
      if name == "missing" then
        error("unknown uniform")
      end
    end,
  }
  local v = { 1, 2, 3 }
  State.send(shader, "v", v)
  State.send(shader, "v", v)
  v[2] = 4
  State.send(shader, "v", v)
  check(calls == 2, "uniform vector mutation/reuse changed")
  State.send(shader, "missing", 1)
  State.send(shader, "missing", 2)
  check(calls == 3, "unknown uniform was retried")
  V.renderBudget = false
  State.send(shader, "v", v)
  V.renderBudget = true
  State.send(shader, "v", v)
  check(calls == 5, "flag changes retained stale uniform state")
  local create, info = love.graphics.newCanvas, love.graphics.getRendererInfo
  local depthFormat
  love.graphics.getRendererInfo = function()
    return "OpenGL ES", "OpenGL ES 3.0"
  end
  love.graphics.newCanvas = function(w, h, opts)
    if opts and opts.format and opts.format:find("depth", 1, true) and not depthFormat then
      depthFormat = opts.format
    end
    return create(w, h, opts)
  end
  check(G.beginScene(32, 32, 0, 0, 160, 144, nil, "gles-policy"), "depth policy target unavailable")
  G.endScene()
  love.graphics.newCanvas, love.graphics.getRendererInfo = create, info
  check(depthFormat == "depth16", "GLES depth16 preference changed")
  local neighbor = up(Scene.render, "neighborMatrix")
  local nb = { ox = 3, oy = 4 }
  local a = neighbor(nb)
  check(neighbor(nb) == a, "neighbor matrix was reallocated")
  nb.ox = 5
  check(neighbor(nb) ~= a, "edited neighbor offset stayed stale")
  Water.setting:sync("auto")
  Performance.tier = "balanced"
  check(Water.level() == 1, "BALANCED default/cap changed")
  Performance.tier = "high"
  check(Water.level() == 2, "desktop HIGH default is not FULL")
  for _, budget in ipairs({ false, true }) do
    V.renderBudget = budget
    check(Water.shader(false) ~= nil, "water shader did not compile")
    check(Water.shader(true) ~= nil, "water grid shader did not compile")
    if love.getVersion() < 12 then
      local ok, err = love.graphics.validateShader(true, Water._source(false))
      check(ok, "GLES water validation failed: " .. tostring(err))
    end
  end
  V.renderBudget = true
  local field = assert(Budget.waveTexture(0, Water._waveBakeSource()))
  check(field:getFormat() == "r8", "wave field is not R8")
  local first = field:newImageData():getString()
  check(Budget.waveTexture(0, Water._waveBakeSource()) == field, "stable wave phase reallocated")
  Budget.waveTexture(1, Water._waveBakeSource())
  check(field:newImageData():getString() ~= first, "wave phase did not update")
  check(Budget.begin(641, 481), "half-resolution layer unavailable")
  local c = love.graphics.getCanvas()
  check(c:getWidth() == 321 and c:getHeight() == 241, "half layer dimensions changed")
  Budget.finish()
  Voxel.angle = math.rad(35)
  water, wall = quad(144, 144, 656, 656, 0), quad(384, 384, 416, 416, 24)
  blue, red = solid(0.1, 0.35, 0.7), solid(0.9, 0.05, 0.03)
  assert(G.beginScene(640, 480, 400, 400, 160, 144))
  G.draw(wall, red)
  G.draw(water, blue)
  G.endScene()
  local flat = G.canvas():newImageData():getString()
  for _, budget in ipairs({ false, true }) do
    V.renderBudget = budget
    check(draw(true) ~= flat, "reflective water silently used only the flat fallback")
  end
  -- Failure must retain a complete full-resolution reflective pass.
  Budget.invalidate()
  local Pixel = V.require("PixelCanvas")
  local make = Pixel.new
  Pixel.new = function()
    return false, "owned allocation failure"
  end
  check(not Budget.begin(640, 480), "failed half target was accepted")
  Pixel.new = make
  check(draw(true) ~= flat, "failed half target lost the full reflective fallback")
  Budget.invalidate()
  local send = State.send
  local rays, planarOn
  State.send = function(shader, name, ...)
    if name == "rays" then
      rays = select(1, ...)
    elseif name == "planarOn" then
      planarOn = select(1, ...)
    end
    return send(shader, name, ...)
  end
  check(
    Water.begin({ reflect = blue, depth = blue, planar = blue, vp = Mat.identity(), eye = { 0, 0, 0 }, curve = { 0, 0, 0 }, screen = {
      640,
      480,
    } }),
    "planar budget did not begin"
  )
  Water.finish()
  love.graphics.setShader()
  State.send = send
  check(rays == 0 and planarOn == 1, "planar and ray march ran together")
  Budget.invalidate()
  local newCanvas = love.graphics.newCanvas
  love.graphics.newCanvas = function(w, h, opts)
    if opts and opts.format == "r8" then
      error("owned R8 refusal")
    end
    return newCanvas(w, h, opts)
  end
  check(not Budget.waveTexture(0, Water._waveBakeSource()), "unsupported R8 was accepted")
  love.graphics.newCanvas = newCanvas
  check(draw(true) ~= flat, "failed R8 target lost reflective water")
  Budget.invalidate()
end
local results = {}
function love.errorhandler(message)
  print(debug.traceback(tostring(message), 2))
  return function()
    return 1
  end
end
function love.run()
  qualify()
  return function()
    love.event.pump()
    for event in love.event.poll() do
      if event == "quit" then
        return 1
      end
    end
    V.renderBudget = phase == 2
    if frame == 120 then
      Profile.setEnabled(true)
    end
    local close = Profile.section("voxel.water submit (owned geometry)")
    local t = love.timer.getTime()
    draw(false)
    local submitted = love.timer.getTime() - t
    close()
    -- Equal completion fence outside the CPU-submission section.
    local fence = G.canvas():newImageData(1, 1, 0, 0, 1, 1)
    fence:release()
    if frame >= 120 then
      total = total + submitted
      fenced = fenced + love.timer.getTime() - t
      Profile.frame()
    end
    frame = frame + 1
    if frame == 240 then
      results[phase] = {
        mode = phase == 1 and "legacy" or "budget",
        frames = 120,
        warmupFrames = 120,
        meanSubmitMs = total / 120 * 1000,
        meanFencedMs = fenced / 120 * 1000,
      }
      if phase == 2 then
        print("RENDER_BUDGET_RESULT " .. Json.encode({
          checks = checks,
          phases = results,
          renderer = love.graphics.getRendererInfo(),
          scope = "Owned water/foreground geometry, native shader/targets/scene producer; CPU submission and pass completion with equal one-pixel GPU fences, no ROM or game FPS",
        }))
        return 0
      end
      Profile.setEnabled(false)
      phase, frame, total, fenced = 2, 0, 0, 0
    end
  end
end
