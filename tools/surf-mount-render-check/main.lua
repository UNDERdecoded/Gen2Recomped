-- Same public consumer through both engines, compared with native GPU drawing.
local root = assert(os.getenv("SURF_RENDER_ROOT"), "set SURF_RENDER_ROOT")
local backend = os.getenv("SURF_RENDER_BACKEND") or "gen2"
local version = os.getenv("SURF_RENDER_VERSION") or "firered"
local api = tonumber(os.getenv("SURF_RENDER_API")) or 2
package.path = "./?.lua;./?/init.lua;" .. package.path
local f, pass, native, portable, cases, scenarios, bodyData, bodyPass
local phase, checks, composites = 1, 0, 0
local function check(v, why)
  checks = checks + 1
  assert(v, why)
end
local function readback(canvas)
  return love.graphics.readbackTexture and love.graphics.readbackTexture(canvas) or canvas:newImageData()
end
local function write(path, bytes)
  local file = assert(io.open(path, "wb"))
  file:write(bytes)
  file:close()
end
function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n" .. debug.traceback() .. "\n")
  return function()
    return 1
  end
end
local originalTime
function love.load()
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.filesystem.createDirectory("tests/surf_mount_render/assets")
  for _, name in ipairs({ "frlg.png", "rse.png", "rider.png" }) do
    local path = "tests/surf_mount_render/assets/" .. name
    local file = assert(io.open(root .. "/" .. path, "rb"))
    assert(love.filesystem.write(path, file:read("*a")))
    file:close()
  end
  originalTime = love.timer.getTime
  f = dofile(
    root .. "/tests/surf_mount_render/" .. (backend == "gen1" and "gen1_fixture" or "fixture") .. ".lua"
  ).new(root, version, api)
  if backend == "gen2" then
    f.result.loader.fs = love.filesystem
    dofile(root .. "/tests/surf_mount_render/native.lua").attach(f)
  end
  local data = f.data or f.result.loader.apis.surf_mount_reference.renderData
  pass = assert(f.result.loader.exports.surf_mount_reference.new(data))
  -- If the earlier actor proposal is present, verify the public owner picture
  -- and mount together. Main-only checks still verify the native body pose.
  if backend == "gen2" and data.supportsActors and data:supportsActors(1) then
    local file = assert(io.open(root .. "/examples/portable_oasc_actors/Actors.lua", "rb"))
    local chunk = assert((loadstring or load)(file:read("*a")))
    file:close()
    bodyData = data
    bodyPass = assert(chunk().new(data))
  end
  cases = dofile(root .. "/tests/surf_mount_render/cases.lua")
  scenarios = cases.all()
  native = love.graphics.newCanvas(192, 128, { dpiscale = 1 })
  portable = love.graphics.newCanvas(192, 128, { dpiscale = 1 })
end
local function target(canvas, draw)
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.setShader()
  love.graphics.setBlendMode("alpha", "alphamultiply")
  draw()
  love.graphics.pop()
end
local function compare(why)
  local a, b = readback(native), readback(portable)
  check(a:getString() == b:getString(), why)
  a:release()
  b:release()
end
function love.draw()
  local case = scenarios[phase]
  cases.apply(f, backend, case)
  local frame = {
    mapId = "A",
    camera = { x = case.tick % 2 == 1 and 13.25 or 0, y = case.tick % 2 == 1 and 7.75 or 0 },
    viewWidth = 192,
    viewHeight = 128,
  }
  local mounts = assert(pass:prepare(frame))
  target(native, function()
    f.drawNative(frame.camera)
  end)
  target(portable, function()
    love.graphics.translate(-frame.camera.x, -frame.camera.y)
    assert(pass:draw(mounts, "ground"))
    assert(pass:draw(mounts, "actorUnderlay", "player"))
  end)
  compare(backend .. "/" .. version .. "/" .. case.name .. " native mount pixels")
  if bodyData and not case.mode then
    -- Pixel-integral camera for the existing actor v1 floor-before-camera rule;
    -- mount-only checks above separately cover fractional camera rounding.
    local bodyFrame = { mapId = "A", camera = { x = 0, y = 0 }, viewWidth = 192, viewHeight = 128 }
    local actors = assert(bodyPass:prepare(bodyFrame))
    local rows = assert(pass:prepare(bodyFrame))
    target(native, function()
      f.drawNative(bodyFrame.camera)
      f.drawBody(bodyFrame.camera)
    end)
    target(portable, function()
      assert(pass:draw(rows, "ground"))
      assert(pass:draw(rows, "actorUnderlay", "player"))
      bodyPass:draw(actors)
    end)
    compare("public owner and mount compose exactly like native Player:draw")
    composites = composites + 1
  end
  local shot = os.getenv("SURF_RENDER_SHOT")
  if shot and phase == 36 then
    local pixels = readback(native)
    local png = pixels:encode("png")
    write(shot, png:getString())
    png:release()
    pixels:release()
  end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(portable, 0, 0)
  phase = phase + 1
  if phase > #scenarios then
    local report = {
      backend = backend,
      version = version,
      api = api,
      checks = checks,
      scenarios = #scenarios,
      ownerComposites = composites,
      renderer = { love.graphics.getRendererInfo() },
      productionStreaming = backend == "gen2",
    }
    local encoded = require("src.link.Json").encode(report)
    print("SURF_GPU " .. encoded)
    local path = os.getenv("SURF_RENDER_REPORT")
    if path then
      write(path, encoded .. "\n")
    end
    pass:invalidate()
    if bodyPass then
      bodyPass:invalidate()
    end
    native:release()
    portable:release()
    if f.sheet then
      for _, q in pairs(f.sheet.quads) do
        q:release()
      end
      f.image:release()
    end
    for _, name in ipairs({ "frlg.png", "rse.png", "rider.png" }) do
      love.filesystem.remove("tests/surf_mount_render/assets/" .. name)
    end
    love.timer.getTime = originalTime
    love.event.quit(0)
  end
end
