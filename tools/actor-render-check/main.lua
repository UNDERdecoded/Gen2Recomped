-- Real public mod loader + PNG reader + billboard resources against native draw.
local root = assert(os.getenv("ACTOR_RENDER_ROOT"), "set ACTOR_RENDER_ROOT")
local backend = os.getenv("ACTOR_RENDER_BACKEND") or "gen2"
local version = os.getenv("ACTOR_RENDER_VERSION") or "firered"
local api = tonumber(os.getenv("ACTOR_RENDER_API")) or 2
package.path = "./?.lua;./?/init.lua;" .. package.path
local f, pass, native, portable, Renderer, Ow, Objects, Player
local checks, phase = 0, 1
local total = backend == "gen2" and 25 or 16
local function check(ok, why)
  checks = checks + 1
  assert(ok, why)
end
function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n" .. debug.traceback() .. "\n")
  return function()
    return 1
  end
end
local function pixels(canvas)
  return love.graphics.readbackTexture and love.graphics.readbackTexture(canvas) or canvas:newImageData()
end
local fixtureNames = { "gen1.png", "gen2.png", "fixed.png", "pose.png" }
function love.load()
  -- LÖVE's virtual filesystem cannot mount arbitrary external worktrees on
  -- every supported runtime. Stage only synthetic PNGs in this tool's own
  -- QA identity, so native newImage/newFile exercise the real filesystem.
  love.filesystem.createDirectory("tests/actor_render/assets")
  for _, name in ipairs(fixtureNames) do
    local path = "tests/actor_render/assets/" .. name
    local file = assert(io.open(root .. "/" .. path, "rb"))
    assert(love.filesystem.write(path, file:read("*a")))
    file:close()
  end
  love.graphics.setDefaultFilter("nearest", "nearest")
  if backend == "gen2" then
    f = dofile(root .. "/tests/actor_render/fixture.lua").new(root, version, api)
    f.result.loader.fs.newFile = love.filesystem.newFile
    f.result.loader.fs.openFile = love.filesystem.openFile
    function f.setPose(direction, p, step)
      f.player.facing = direction
      f.player.animClock = (p == 1 and 8 or 0) + (step and 16 or 0)
    end
  else
    f = dofile(root .. "/tests/actor_render/gen1_fixture.lua").new(root, version, api)
    Ow = require("src.core.game3.ow_sprites")
    Objects = require("src.core.game3.objects")
    Player = require("src.core.game3.player")
    local file = assert(io.open(root .. "/tests/actor_render/assets/gen1.png", "rb"))
    local fd = love.filesystem.newFileData(file:read("*a"), "fixture.png")
    file:close()
    local data = love.image.newImageData(fd)
    fd:release()
    local image = love.graphics.newImage(data)
    data:release()
    image:setFilter("nearest", "nearest")
    local sprite = f.sprites[1]
    sprite.image = image
    sprite.quads = {}
    for index = 0, 8 do
      sprite.quads[index] = love.graphics.newQuad(0, index * 32, 16, 32, 16, 288)
    end
    Ow._loaded[1] = sprite
  end
  local data = f.data or f.result.loader.apis.actor_reference.renderData
  pass = assert(f.result.loader.exports.actor_reference.new(data))
  local w, h = love.graphics.getPixelDimensions()
  native = love.graphics.newCanvas(w, h, { dpiscale = 1 })
  portable = love.graphics.newCanvas(w, h, { dpiscale = 1 })
  Renderer = require("src.render.Renderer")
  Renderer:init()
  Renderer:setUISize(240, 160)
end
local function drawNative(camera)
  if backend == "gen2" then
    for _, g in ipairs(f.world.ghosts) do
      g.npc:draw(camera.x - g.ox, camera.y - g.oy)
    end
    f.other:draw(camera.x, camera.y)
    if not f.player.hidden then
      -- Body-sprite oracle: isolate native draw-side clocks and omit the
      -- separately documented field-effect composites (surf mount/shadow).
      local copy = {}
      for k, v in pairs(f.player) do
        copy[k] = v
      end
      setmetatable(copy, getmetatable(f.player))
      copy.isUnderwater = function()
        return f.world.map.def.mapType == "UNDERWATER"
      end
      copy.drawSurfBlob = function() end
      copy:draw(camera.x, camera.y)
    end
    f.npc:draw(camera.x, camera.y)
  else
    for _, g in ipairs(f.neighbors) do
      for _, e in ipairs(Objects.poolForDraw(g.pool)) do
        Ow.draw(
          e.graphicsId,
          e.px + g.x,
          e.py + g.y,
          camera.x,
          camera.y,
          e.facing,
          e.moving and e.animClock % 16 < 8 and 1 or 0,
          e.stepFlip
        )
      end
    end
    -- Native fixtures deliberately have no overlapping equal-depth actors.
    for _, e in ipairs(Objects.poolForDraw(Objects.snapshotPool())) do
      Ow.draw(
        e.graphicsId,
        e.px,
        e.py,
        camera.x,
        camera.y,
        e.facing,
        e.moving and e.animClock % 16 < 8 and 1 or 0,
        e.stepFlip
      )
    end
    if not Player.hidden then
      Ow.draw(
        Player.graphicsId,
        Player.px,
        Player.py,
        camera.x,
        camera.y,
        Player.facing,
        Player.animCmd % 2 == 0 and 1 or 0,
        Player.animCmd <= 1
      )
    end
  end
end
function love.draw()
  if phase > total then
    return
  end
  local g = love.graphics
  local dirs = { "down", "up", "left", "right" }
  local n = phase - 1
  if phase <= 16 then
    f.setPose(dirs[math.floor(n / 4) + 1], math.floor(n / 2) % 2, n % 2 == 1)
  elseif phase == 17 then
    f.player.running = true
  elseif phase == 18 then
    f.player.running = nil
    f.player.onBike = true
  elseif phase == 19 then
    f.player.onBike = nil
    f.player.surfing = true
    f.player.bobTimer = 15
  elseif phase == 20 then
    f.player.surfing = nil
    f.player.hopFrames = 16
    f.player.hopTotal = 32
  elseif phase == 21 then
    f.player.hopFrames = nil
    f.npc.fixedFrame = 2
  elseif phase == 22 then
    f.npc.fixedFrame = nil
    f.player.fieldMove = true
    f.player.fieldMovePose = 3
  elseif phase == 23 then
    f.player.fieldMove = nil
    f.player.hidden = true
  elseif phase == 24 then
    f.player.hidden = nil
    f.player.underwaterSprite = f.bike
    f.world.map.def.mapType = "UNDERWATER"
  elseif phase == 25 then
    f.npc.sprite = require("src.render.SpriteRenderer").new({
      id = "STILL",
      image = "tests/actor_render/assets/fixed.png",
      trueColor = true,
      gen3ObjectEvent = true,
      frameWidth = 16,
      frameHeight = 32,
      frames = 1,
    })
  end
  local w, h = g.getPixelDimensions()
  local frame = { mapId = "A", camera = { x = -64, y = 0 }, viewWidth = 192, viewHeight = 128 }
  local actors = assert(pass:prepare(frame))
  local before = f.player.bobTimer
  check(#actors == (phase == 23 and 3 or 4), "visible actor count")
  for _, canvas in ipairs({ native, portable }) do
    g.setCanvas(canvas)
    g.origin()
    g.setShader()
    g.setColor(1, 1, 1, 1)
    g.clear(0.15, 0.2, 0.25, 1)
    g.scale(w / 192, h / 128)
    if canvas == native then
      drawNative(frame.camera)
    else
      g.translate(-frame.camera.x, -frame.camera.y)
      pass:draw(actors)
    end
  end
  g.setCanvas()
  g.origin()
  g.setShader()
  local a, b = pixels(native), pixels(portable)
  check(a:getString() == b:getString(), "native/public complete actor pixels match")
  a:release()
  b:release()
  check(f.player.bobTimer == before, "read does not advance player clock")
  Renderer:beginFrame(true)
  Renderer:setWorldOverride(portable)
  g.setColor(0, 1, 0, 1)
  g.rectangle("fill", 0, 0, 8, 8)
  g.setColor(1, 1, 1, 1)
  Renderer:endFrame(nil, nil, nil)
  if phase == total then
    if backend == "gen2" then
      local fs = f.result.loader.fs
      local method = fs.openFile and "openFile" or "newFile"
      local original = fs[method]
      local input = assert(io.open("tests/actor_render/assets/gen2.png", "rb"))
      local header = input:read(33)
      input:close()
      fs[method] = function(path, ...)
        if not path:find("gen2.png", 1, true) then
          return original(path, ...)
        end
        return {
          open = function()
            return true
          end,
          getSize = function()
            return #header
          end,
          read = function()
            return header
          end,
          close = function() end,
        }
      end
      local declined, decodeReason = pass:prepare(frame)
      check(
        declined == nil and type(decodeReason) == "string" and decodeReason ~= "actor image unavailable",
        "full PNG decode failure declines"
      )
      check(next(pass.sheets) == nil, "decode failure releases existing GPU resources")
      fs[method] = original
      check(pass:prepare(frame) ~= nil, "valid source recovers after decode failure")
    end
    local output = {
      backend = backend,
      version = version,
      api = api,
      scenarios = phase,
      checks = checks,
      productionStreaming = backend == "gen2",
      renderer = { g.getRendererInfo() },
    }
    local encoded = require("src.link.Json").encode(output)
    local report = os.getenv("ACTOR_RENDER_REPORT")
    if report then
      local file = assert(io.open(report, "w"))
      file:write(encoded .. "\n")
      file:close()
    end
    local shot = os.getenv("ACTOR_RENDER_SHOT")
    g.captureScreenshot(function(image)
      if shot then
        local bytes = image:encode("png")
        local file = assert(io.open(shot, "wb"))
        file:write(bytes:getString())
        file:close()
        bytes:release()
      end
      image:release()
      pass:invalidate()
      native:release()
      portable:release()
      for _, name in ipairs(fixtureNames) do
        love.filesystem.remove("tests/actor_render/assets/" .. name)
      end
      print("ACTOR_RENDER_GPU " .. encoded)
      love.event.quit(0)
    end)
  end
  phase = phase + 1
end
