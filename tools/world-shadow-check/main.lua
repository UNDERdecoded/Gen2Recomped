-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local root = assert(os.getenv("WORLD_SHADOW_QA_ROOT"))
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Profile = require("src.core.FrameProfile")
local Json = require("src.link.Json")
require("src.core.GameVersion").set("crystal")
require("src.core.Performance").tier = "high"
local V, libs = { sharedHulls = true }, {}
V.require = function(name)
  if not libs[name] then
    libs[name] = assert(loadfile(root .. "/mods/DRAMATIC_SHAPE/lib/" .. name .. ".lua"))(V)
  end
  return libs[name]
end
V.data = function(name)
  return assert(loadfile(root .. "/mods/DRAMATIC_SHAPE/data/" .. name .. ".lua"))()
end
-- Geometry is owned. Resource/mesher seams supply it; actual scene casting,
-- shadow shaders, matrices, canvases and the lit scene shader stay native.
libs.ChunkMesher = {
  flowers = function(map)
    return map.flowers
  end,
  figures = function(map)
    return map.figures
  end,
}
local Mat = V.require("Mat4")
local Shadow = V.require("ShadowMap")
local Voxel = V.require("VoxelState")
local G = V.require("Voxel3D")
local Perf = V.require("Perf")
Perf.enabled = true
local Scene = V.require("VoxelScene")
local function up(fn, name)
  for i = 1, 100 do
    local key, value = debug.getupvalue(fn, i)
    if key == name then
      return value
    end
    if not key then
      break
    end
  end
  error("missing scene producer " .. name)
end
local cast = up(Scene.render, "castShadows")
local tex, terrain, poses, state, atlas
local results = {}
local phase, frame, total, frameTotal, submitTotal = 1, 0, 0, 0, 0
local checks = 0
local function check(ok, message)
  assert(ok, message)
  checks = checks + 1
end
local function setup()
  local pixels = love.image.newImageData(16, 96)
  pixels:mapPixel(function(x, y)
    return 0.3, 0.7, 0.4, (x > 2 and x < 13) and 1 or 0
  end)
  tex = love.graphics.newImage(pixels)
  local verts = {}
  -- Many visible ground triangles exercise the repeated static pass.
  for z = -16, 31 do
    for x = -16, 31 do
      local a, b = x * 16, z * 16
      for _, p in ipairs({
        { a, 0, b },
        { a + 16, 0, b },
        { a + 16, 0, b + 16 },
        { a, 0, b },
        { a + 16, 0, b + 16 },
        {
          a,
          0,
          b + 16,
        },
      }) do
        verts[#verts + 1] = { p[1], p[2], p[3], 0.5, 0.5, 1 }
      end
    end
  end
  terrain = love.graphics.newMesh(G.FORMAT, verts, "triangles", "static")
  state = { map = { id = "OWN_SHADOW_MAP", tileset = {} }, neighbors = {} }
  local def =
    { image = "owned-sprite", billboardTexture = tex, frameWidth = 16, frameHeight = 16, frames = 6, walker = true }
  poses = {
    {
      sprite = {
        def = def,
        resolveImage = function()
          return tex
        end,
      },
      px = 400,
      py = 400,
      gh = 0,
      facing = "down",
      phase = 0,
      flip = false,
    },
  }
  atlas = function()
    return tex
  end
  Voxel.angle = math.rad(35)
  check(G.shader(false) ~= nil, "lit scene shader did not compile")
  check(G.shader(false, true) ~= nil, "instanced lit scene shader did not compile")
  check(Shadow.available() and Shadow.dynamicAvailable(), "native shadow targets unavailable")
end
local function castAt(cx, cy)
  cast(state, terrain, {}, poses, cx, cy, 160, 144, atlas, nil, nil, nil, nil)
end
local function qualify()
  local Card = V.require("WorldShadows")
  local box = Card.bounds(-1, 257, -257, 1)
  check(box[1] == -256 and box[2] == 512 and box[3] == -512 and box[4] == 256, "negative world snapping changed")
  V.shadowWorldAnchor = true
  castAt(400, 400)
  local first = Shadow.texture():newImageData():getString()
  local vp = Json.encode(Shadow.clipVP)
  poses[1].px = 412
  poses[1].phase = 1
  castAt(401, 401)
  check(Shadow.texture():newImageData():getString() == first, "walking redrew/changed static texture")
  check(Json.encode(Shadow.clipVP) == vp, "walking moved the anchored light matrix")
  check(Shadow.dynamicTexture():getWidth() == 256, "moving target is not 256 square")
  local moving = Shadow.dynamicTexture():newImageData():getString()
  poses[1].px = 448
  castAt(401, 401)
  check(Shadow.dynamicTexture():newImageData():getString() ~= moving, "moving actor shadow stayed stale")
  local before = Perf.counters["shadow.static.cast"] or 0
  castAt(801, 400)
  check(
    (Perf.counters["shadow.static.cast"] or 0) == before + 1,
    "visible tile-set change did not redraw static shadows"
  )
  before = Perf.counters["shadow.static.cast"] or 0
  state.map.flowers = terrain
  castAt(801, 400)
  check((Perf.counters["shadow.static.cast"] or 0) == before + 1, "arriving geometry did not redraw static shadows")
  state.map.flowers = nil
  V.shadowWorldAnchor = false
  castAt(400, 400)
  check(not Shadow.dynamicActive() and not Shadow.isAnchored(), "P7 disable did not restore legacy map")
  V.shadowWorldAnchor = true
  poses[1].px = 400
  castAt(400, 400)
  local function litFloor()
    check(G.beginScene(320, 240, 400, 400, 160, 120), "native lit scene did not begin")
    G.draw(terrain, tex)
    G.endScene()
    local image = G.canvas():newImageData()
    local tag = Shadow.dynamicActive() and "with-actor" or "without-actor"
    local f = assert(io.open(assert(os.getenv("WORLD_SHADOW_QA_OUT")) .. "/" .. tag .. ".png", "wb"))
    f:write(image:encode("png"):getString())
    f:close()
    local bytes = image:getString()
    image:release()
    return bytes
  end
  local withActor = litFloor()
  V.shadowWorldAnchor = false
  check(litFloor() ~= withActor, "lit shader did not sample the dynamic shadow texture")
  V.shadowWorldAnchor = true
  castAt(400, 400)
  local staticBefore = Perf.counters["shadow.static.cast"] or 0
  local movingBefore = Perf.counters["shadow.dynamic.cast"] or 0
  castAt(400, 400)
  check(
    (Perf.counters["shadow.static.cast"] or 0) == staticBefore
      and (Perf.counters["shadow.dynamic.cast"] or 0) == movingBefore,
    "idle layers were redrawn"
  )
  local kx = Shadow.KX
  Shadow.KX = kx + 0.1
  castAt(400, 400)
  check((Perf.counters["shadow.static.cast"] or 0) == staticBefore + 1, "sun change left static shadows stale")
  Shadow.KX = kx
  castAt(400, 400)
  staticBefore = Perf.counters["shadow.static.cast"] or 0
  state.neighbors = { { map = { tileset = {} }, ox = 16, oy = 0 } }
  castAt(400, 400)
  state.neighbors[1].ox = 32
  castAt(400, 400)
  check((Perf.counters["shadow.static.cast"] or 0) == staticBefore + 2, "neighbor arrival/offset was not invalidated")
  state.neighbors = {}
  require("src.core.Performance").tier = "balanced"
  castAt(400, 400)
  check(Shadow.res <= 1024, "existing balanced resolution cap changed")
  movingBefore = Perf.counters["shadow.dynamic.cast"] or 0
  for i = 1, 6 do
    poses[1].px = 400 + i
    castAt(400, 400)
  end
  local casts = (Perf.counters["shadow.dynamic.cast"] or 0) - movingBefore
  check(casts == 2, "existing balanced moving-shadow cadence changed")
  require("src.core.Performance").tier = "high"
  -- An unavailable secondary target must retain the complete legacy pass.
  Shadow.invalidate()
  V.shadowWorldAnchor = true
  local Pixel = V.require("PixelCanvas")
  local make = Pixel.new
  local denied = 0
  Pixel.new = function(w, h)
    if w == 256 and h == 256 then
      denied = denied + 1
      return false, "owned failure"
    end
    return make(w, h)
  end
  castAt(400, 400)
  poses[1].phase = 1 - poses[1].phase
  castAt(401, 400)
  check(
    not Shadow.isAnchored() and not Shadow.dynamicActive() and Shadow.active(),
    "missing secondary target lost legacy shadows"
  )
  check(denied == 1, "failed secondary target was retried every frame")
  Pixel.new = make
  Shadow.invalidate()
  Perf.counters = {}
end
function love.errorhandler(message)
  print(debug.traceback(tostring(message), 2))
  return function()
    return 1
  end
end
function love.run()
  setup()
  qualify()
  return function()
    local frameBegan = love.timer.getTime()
    love.event.pump()
    for event in love.event.poll() do
      if event == "quit" then
        return 1
      end
    end
    V.shadowWorldAnchor = phase == 2
    poses[1].px = 400 + math.sin(frame * 0.07) * 16
    poses[1].phase = frame % 2
    if frame == 120 then
      Profile.setEnabled(true)
      Perf.counters = {}
    end
    local close = Profile.section("voxel.sun submit (owned geometry)")
    local t = love.timer.getTime()
    castAt(400 + frame % 60 / 4, 400)
    local submitted = love.timer.getTime() - t
    close()
    local closeFence = Profile.section("voxel.sun GPU fence (owned geometry)")
    -- Complete this offscreen pass before timing it. Avoid drawable/present
    -- throttling; one pixel is read in both modes and no full-frame copy is timed.
    local target = Shadow.dynamicActive() and Shadow.dynamicTexture() or Shadow.texture()
    local fence = target:newImageData(1, 1, 0, 0, 1, 1)
    fence:release()
    if frame >= 120 then
      total = total + love.timer.getTime() - t
      submitTotal = submitTotal + submitted
    end
    closeFence()
    if frame >= 120 then
      frameTotal = frameTotal + love.timer.getTime() - frameBegan
      Profile.frame()
    end
    frame = frame + 1
    if frame == 240 then
      results[phase] = {
        mode = phase == 1 and "legacy" or "world anchored",
        frames = 120,
        meanMs = total / 120 * 1000,
        meanSubmitMs = submitTotal / 120 * 1000,
        meanFrameMs = frameTotal / 120 * 1000,
        warmupFrames = 120,
        staticPasses = Perf.counters["shadow.static.cast"] or 0,
        dynamicPasses = Perf.counters["shadow.dynamic.cast"] or 0,
        legacyPasses = Perf.counters["shadow.cast"] or 0,
      }
      if phase == 2 then
        check(results[2].staticPasses < results[1].legacyPasses, "static pass was not reused")
        print("WORLD_SHADOW_RESULT " .. Json.encode({
          phases = results,
          checks = checks,
          renderer = love.graphics.getRendererInfo(),
          scope = "Offscreen owned geometry, actual scene casting/shaders/targets, one-pixel GPU completion fence; no presentation, ROM or full-game FPS",
        }))
        return 0
      end
      Profile.setEnabled(false)
      Shadow.invalidate()
      Perf.counters = {}
      phase, frame, total, frameTotal, submitTotal = 2, 0, 0, 0, 0
    end
  end
end
