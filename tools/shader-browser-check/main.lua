function love.errorhandler(message)
  io.stderr:write(tostring(message) .. "\n")
  return function()
    return 1
  end
end
local root = love.filesystem.getSource():match("^(.*)/tools/shader%-browser%-check$")
  or love.filesystem.getWorkingDirectory()
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path
local Browser = require("src.render.ShaderBrowser")
local Presets = require("src.render.ShaderPresets")
local Json = require("src.link.Json")
local g = love.graphics
local b, active, old, stage, started, checks, presetPath, descriptor
local function check(v, why)
  checks = checks + 1
  assert(v, why)
end
local function step()
  check(active.shader == old, "old active effect remains selected throughout acquisition")
  b:poll()
  assert(not b.error, b.error)
  if b.busy then
    return
  end
  if stage == "catalog" then
    check(#b.entries > 20, "real pinned catalog")
    for _, e in ipairs(b.entries) do
      if e.path == "handheld/lcd3x.slangp" then
        presetPath = e.path
      end
    end
    check(presetPath ~= nil, "LCD3x available")
    check(b:start("install", presetPath), "native install starts")
    stage = "install"
  elseif stage == "install" then
    check(b.result == "installed", "GPU approved publication")
    local id = b.installed[presetPath]
    check(id ~= nil, "receipt")
    active:refresh()
    check(active:activate(id), active.error or "installed selection")
    check(active.shader ~= old, "explicit activation replaces old")
    old = active.shader
    descriptor = assert(love.filesystem.read("shader-presets/" .. id:sub(7) .. ".json"))
    local input = g.newCanvas(32, 24)
    local output = active:apply(input, 2)
    check(output ~= input and active:active(), "installed render executes")
    local pixels = output:newImageData()
    check(pixels:getWidth() == 32, "readback")
    pixels:release()
    input:release()
    check(b:start("install", presetPath), "repeat install starts")
    stage = "repeat"
  elseif stage == "repeat" then
    check(b.result == "installed", "repeat reuses exact existing files")
    local id = b.installed[presetPath]
    check(
      love.filesystem.read("shader-presets/" .. id:sub(7) .. ".json") == descriptor,
      "repeat preserves descriptor"
    )
    check(b:start("install", presetPath), "cancel starts")
    b:cancel()
    stage = "cancel"
    started = love.timer.getTime()
  elseif stage == "cancel" then
    if b.thread:isRunning() then
      return
    end
    check(not b.fs.getInfo(b.relative .. "/approve"), "cancel has no approval")
    check(b.installed[presetPath] ~= nil, "old installed receipt retained")
    active:off()
    print(
      "shader browser native HTTPS/worker/GPU/install/repeat/cancel PASS "
        .. checks
        .. " checks | "
        .. table.concat({ g.getRendererInfo() }, " | ")
    )
    love.event.quit(0)
    stage = "done"
  end
end
function love.load()
  checks = 0
  started = love.timer.getTime()
  stage = "catalog"
  local ok, why = pcall(function()
    active = Presets.new({ fs = love.filesystem })
    assert(active:activate("builtin:warm"))
    old = active.shader
    b = Browser.new({
      root = love.filesystem.getSaveDirectory(),
      fs = love.filesystem,
      helper = assert(os.getenv("SHADER_BROWSER_HELPER"), "SHADER_BROWSER_HELPER required"),
      start = function(job)
        local channel = love.thread.getChannel("browser.probe." .. job.relative)
        channel:clear()
        local file = assert(io.open(root .. "/src/render/shader_browser_worker.lua", "rb"))
        local code = file:read("*a")
        file:close()
        local thread = love.thread.newThread(
          love.filesystem.newFileData(
            "package.path=" .. string.format("%q", package.path) .. ";\n" .. code,
            "worker.lua"
          )
        )
        thread:start(Json.encode({
          helper = job.helper,
          root = job.root,
          relative = job.relative,
          channel = "browser.probe." .. job.relative,
        }))
        return channel, thread
      end,
    })
    assert(b:start("catalog"))
  end)
  if not ok then
    io.stderr:write(tostring(why) .. "\n")
    love.event.quit(1)
    stage = "done"
  end
end
function love.update()
  if stage == "done" then
    return
  end
  local ok, why = pcall(function()
    assert(love.timer.getTime() - started < 120, "browser probe timeout")
    step()
  end)
  if not ok then
    if b then
      b:cancel()
    end
    io.stderr:write(tostring(why) .. "\n")
    love.event.quit(1)
    stage = "done"
  end
  love.timer.sleep(0.01)
end
