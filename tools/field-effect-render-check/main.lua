-- Native GPU oracle against the unchanged public-only example consumer.
local root = assert(os.getenv("FIELD_RENDER_ROOT"), "set FIELD_RENDER_ROOT")
local backend = os.getenv("FIELD_RENDER_BACKEND") or "gen2"
local version = os.getenv("FIELD_RENDER_VERSION") or "firered"
local api = tonumber(os.getenv("FIELD_RENDER_API")) or 2
package.path = "./?.lua;./?/init.lua;" .. package.path
local f, pass, native, portable
local clocks = { 0, 3, 4, 5, 8, 9, 10, 14, 15, 16, 49 }
local phase, checks = 1, 0
local function check(value, why)
  checks = checks + 1
  assert(value, why)
end
local function readback(canvas)
  return love.graphics.readbackTexture and love.graphics.readbackTexture(canvas) or canvas:newImageData()
end
function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n" .. debug.traceback() .. "\n")
  return function()
    return 1
  end
end
local function write(path, bytes)
  local file = assert(io.open(path, "wb"))
  file:write(bytes)
  file:close()
end
function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  -- Dedicated QA identity; no game cache, imported asset, ROM or save touched.
  love.filesystem.createDirectory("tests/field_effect_render/assets")
  for _, kind in ipairs({ "grass", "ripple", "sparkle" }) do
    local path = "tests/field_effect_render/assets/" .. kind .. ".png"
    local file = assert(io.open(root .. "/" .. path, "rb"))
    assert(love.filesystem.write(path, file:read("*a")))
    file:close()
  end
  f = dofile(
    root .. "/tests/field_effect_render/" .. (backend == "gen1" and "gen1_fixture" or "fixture") .. ".lua"
  ).new(root, version, api)
  if backend == "gen2" then
    f.result.loader.fs = love.filesystem
    dofile(root .. "/tests/field_effect_render/native.lua").attach(f)
  end
  local data = f.data or f.result.loader.apis.effect_reference.renderData
  pass = assert(f.result.loader.exports.effect_reference.new(data))
  native = love.graphics.newCanvas(192, 128, { dpiscale = 1 })
  portable = love.graphics.newCanvas(192, 128, { dpiscale = 1 })
end
function love.draw()
  local clock = clocks[phase]
  f.setClock(clock)
  local frame = {
    mapId = "A",
    camera = { x = clock % 2 == 1 and 13.25 or 0, y = clock % 2 == 1 and 7.75 or 0 },
    viewWidth = 192,
    viewHeight = 128,
  }
  local rows = assert(pass:prepare(frame))
  for _, layer in ipairs({ "ground", "actorCover", "front" }) do
    for _, target in ipairs({ native, portable }) do
      love.graphics.push("all")
      love.graphics.setCanvas(target)
      love.graphics.origin()
      love.graphics.clear(0, 0, 0, 0)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.setShader()
      love.graphics.setBlendMode("alpha", "alphamultiply")
      if target == native then
        f.drawNative(layer, frame.camera)
      else
        love.graphics.translate(-frame.camera.x, -frame.camera.y)
        if layer == "actorCover" then
          assert(pass:draw(rows, layer, "player"))
          if backend == "gen2" then
            assert(pass:draw(rows, layer, "npc:1:A:7:0:0"))
          end
        else
          assert(pass:draw(rows, layer))
        end
      end
      love.graphics.pop()
    end
    local a, b = readback(native), readback(portable)
    check(
      a:getString() == b:getString(),
      backend .. "/" .. version .. " clock=" .. clock .. " layer=" .. layer .. " native/public pixels"
    )
    a:release()
    b:release()
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(portable, 0, 0)
  phase = phase + 1
  if phase > #clocks then
    local report = {
      backend = backend,
      version = version,
      api = api,
      checks = checks,
      scenarios = #clocks,
      renderer = { love.graphics.getRendererInfo() },
      productionStreaming = backend == "gen2",
    }
    local encoded = require("src.link.Json").encode(report)
    print("FIELD_GPU " .. encoded)
    local path = os.getenv("FIELD_RENDER_REPORT")
    if path then
      write(path, encoded .. "\n")
    end
    local shot = os.getenv("FIELD_RENDER_SHOT")
    if shot then
      local data = readback(native)
      local png = data:encode("png")
      write(shot, png:getString())
      png:release()
      data:release()
    end
    pass:invalidate()
    native:release()
    portable:release()
    if f.sources then
      for _, s in pairs(f.sources) do
        for _, q in pairs(s.quads) do
          q:release()
        end
        for _, q in pairs(s.quadsFront) do
          q:release()
        end
        s.image:release()
      end
    end
    for _, kind in ipairs({ "grass", "ripple", "sparkle" }) do
      love.filesystem.remove("tests/field_effect_render/assets/" .. kind .. ".png")
    end
    love.event.quit(0)
  end
end
