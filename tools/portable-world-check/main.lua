-- Native GPU readback of the real mod, pipeline dispatcher and final Renderer.
local root = os.getenv("OASC_WORLD_ROOT")
  or love.filesystem.getSource():match("^(.*)/tools/portable%-world%-check$")
local backend = os.getenv("OASC_WORLD_BACKEND") or "gen2"
local version = os.getenv("OASC_WORLD_VERSION") or "firered"
local api = tonumber(os.getenv("OASC_WORLD_API")) or 2
package.path = "./?.lua;./?/init.lua;" .. package.path
love.filesystem.mount(love.filesystem.getWorkingDirectory(), "", true)
local fixture, Renderer, P, Palette, pass, raw, original, foreign, referenceTarget
local phase, waiting, checks = 1, false, 0
local function check(ok, why)
  checks = checks + 1
  assert(ok, why)
end
local function near(a, b)
  return math.abs(a - b) < 1.6 / 255
end
function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n" .. debug.traceback() .. "\n")
  return function()
    return 1
  end
end
function love.load()
  fixture = dofile(root .. "/tests/portable_world/fixture.lua").new(root, backend, version, api)
  Renderer = require("src.render.Renderer")
  P = require("src.render.Pipelines")
  Palette = require("src.render.PaletteFX")
  Renderer:init()
  Renderer:setUISize(240, 160)
  Palette.setMode("dmg")
  local ok, correction = pcall(require, "src.render.GBCFX")
  if ok then
    correction.setLevel(0)
  end
  pass = fixture.exports.pass
  P.install(fixture.run.data)
  P.setLevel("portable_oasc_world", 1)
  original = fixture.run.data.render_pipelines.portable_oasc_world.drawWorld
  foreign = love.graphics.newCanvas(4, 4, { dpiscale = 1 })
  raw =
    { state = { map = { id = fixture.state.mapId } }, cam = { x = -16, y = 0 }, vw = 144, vh = 96, level = 1 }
end
function love.draw()
  if waiting then
    return
  end
  waiting = true
  local g = love.graphics
  if phase == 4 then
    P.setLevel("portable_oasc_world", 0)
  end
  if phase == 5 then
    P.setLevel("portable_oasc_world", 1)
    fixture.run.data.render_pipelines.portable_oasc_world.drawWorld = function()
      g.setCanvas(foreign)
      g.setColor(1, 0, 0, 1)
      error("intentional world failure")
    end
  elseif phase == 6 then
    -- The pinned Gen1 host retires on its first exception, whereas Gen2
    -- tolerates transient failures. Reset dispatch before the next scenario.
    P.install(fixture.run.data)
    P.setLevel("portable_oasc_world", 1)
    fixture.run.data.render_pipelines.portable_oasc_world.drawWorld = function(frame)
      -- Only Gen2 implements the new leaked-push containment. The Gen1
      -- extension compares scene data/frames, not that additional guarantee.
      if backend == "gen2" then
        g.push("all")
      end
      return original(frame)
    end
  elseif phase == 7 then
    fixture.run.data.render_pipelines.portable_oasc_world.drawWorld = original
  end
  local uw, uh = g.getDimensions()
  local pw, ph = g.getPixelDimensions()
  raw.width, raw.height, raw.pixelWidth, raw.pixelHeight, raw.unitWidth, raw.unitHeight =
    pw, ph, pw, ph, uw, uh
  if phase == 3 then
    raw.pixelWidth, raw.pixelHeight = pw * 2, ph * 2
  end
  Renderer:beginFrame(true)
  Renderer:beginWorldPass()
  referenceTarget = g.getCanvas()
  local depth = g.getStackDepth and g.getStackDepth()
  local selected = P.worldPipeline()
  local out = selected and P.drawWorld(selected, raw)
  check(g.getCanvas() == referenceTarget, "world target restored")
  if depth then
    check(g.getStackDepth() == depth, "graphics stack restored")
  end
  if out then
    check(out.isCanvas and out:isCanvas() or out:typeOf("Canvas"), "world owns a real Canvas")
    local pixels = g.readbackTexture and g.readbackTexture(out) or out:newImageData()
    local x = math.floor(16 * raw.pixelWidth / raw.vw)
    local r, b, c, a = pixels:getPixel(x, 0)
    check(
      near(r, 16 / 255) and near(b, 16 / 255) and near(c, 8 / 255) and near(a, 1),
      "GPU texel matches public base palette and bank/flip decoding"
    )
    pixels:release()
  else
    check(
      phase == 4 or phase == 5 or phase == 7,
      "only expected native fallback phase "
        .. phase
        .. " selected="
        .. tostring(selected)
        .. " level="
        .. P.level("portable_oasc_world")
        .. ": "
        .. tostring(pass.lastError)
    )
    g.clear(0, 0, 1, 1)
  end
  Renderer:setWorldOverride(out)
  Renderer:endWorldPass()
  g.setColor(0, 1, 0, 1)
  g.rectangle("fill", 0, 0, 8, 8)
  g.setColor(1, 1, 1, 1)
  Renderer:endFrame(nil, nil, nil)
  g.captureScreenshot(function(image)
    local rects = Renderer.frameRects and Renderer:frameRects()
    local presentation = Renderer.uiPresentation or { x = rects.uox, y = rects.uoy }
    local dx, dy = pw / uw, ph / uh
    local x = math.floor(presentation.x * dx) + 1
    local y = math.floor(presentation.y * dy) + 1
    local r, b, c = image:getPixel(x, y)
    check(near(r, 0) and near(b, 1) and near(c, 0), "native HUD remains above portable world")
    if phase == 4 or phase == 5 or phase == 7 then
      local rr, gg, bb = image:getPixel(1, 1)
      check(near(rr, 0) and near(gg, 0) and near(bb, 1), "native fallback reaches final renderer")
    end
    local directory = os.getenv("OASC_WORLD_SHOTS")
    if directory then
      local bytes = image:encode("png")
      local f = assert(io.open(directory .. "/" .. backend .. "-" .. version .. "-" .. phase .. ".png", "wb"))
      f:write(bytes:getString())
      f:close()
    end
    image:release()
    if phase == 2 then
      fixture.state.patch(fixture.state.split + 2)
    end
    if phase == 6 then
      fixture.state.missing()
    end
    phase = phase + 1
    waiting = false
    if phase == 8 then
      P.invalidate()
      pass:invalidate()
      foreign:release()
      local report = {
        backend = backend,
        version = version,
        api = api,
        checks = checks,
        phases = 7,
        leakedPushContainment = backend == "gen2",
        renderer = {
          g.getRendererInfo(),
        },
      }
      local Json = require("src.link.Json")
      local output = Json.encode(report)
      print("PORTABLE_WORLD_GPU " .. output)
      local path = os.getenv("OASC_WORLD_REPORT")
      if path then
        local f = assert(io.open(path, "w"))
        f:write(output .. "\n")
        f:close()
      end
      love.event.quit(0)
    end
  end)
end
