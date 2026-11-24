-- PS5 runtime bring-up: video, shaders, canvas, pad, audio, save directory,
-- LuaJIT (JIT + FFI, including ffi.C.PHYSFS_*). Everything it finds is drawn
-- and printed (the launcher sends print to <data root>/love.log).

local lines = {}
local function note(fmt, ...)
  local s = string.format(fmt, ...)
  lines[#lines + 1] = s
  print("[test] " .. s)
end

local tone, shader, canvas, font
local pressed = {}
local frames, fpsShown = 0, 0
local axes = ""

function love.load()
  font = love.graphics.newFont(28)
  note("OS %s / love._os %s", love.system.getOS(), tostring(love._os))
  local name, version, vendor, device = love.graphics.getRendererInfo()
  note("renderer %s | %s | %s | %s", name, version, vendor, device)
  note("window %dx%d, dpi %.2f", love.graphics.getWidth(), love.graphics.getHeight(), love.graphics.getDPIScale())
  local lim = love.graphics.getSystemLimits()
  note("texturesize %d, canvasmsaa %d", lim.texturesize, lim.canvasmsaa)
  note("fused %s, source %s", tostring(love.filesystem.isFused()), love.filesystem.getSource())
  note("save dir %s", love.filesystem.getSaveDirectory())

  -- save directory
  note("user dir %s, appdata dir %s", love.filesystem.getUserDirectory(), love.filesystem.getAppdataDirectory())
  note("os.date %s, os.time %s", tostring(os.date()), tostring(os.time()))
  local okW, ok, err = pcall(love.filesystem.write, "hello.txt", "written at " .. os.date() .. "\n")
  note("write hello.txt: %s %s %s", tostring(okW), tostring(ok), tostring(err or ""))
  pcall(function()
    local ffi = require("ffi")
    ffi.cdef("int PHYSFS_getLastErrorCode(void); const char *PHYSFS_getErrorByCode(int code); const char *PHYSFS_getWriteDir(void);")
    local code = ffi.C.PHYSFS_getLastErrorCode()
    local wd = ffi.C.PHYSFS_getWriteDir()
    local function str(p) return p ~= nil and ffi.string(p) or "null" end
    note("PHYSFS last error %d (%s), write dir %s", code, str(ffi.C.PHYSFS_getErrorByCode(code)), str(wd))
  end)
  note("read back: %s", tostring(love.filesystem.read("hello.txt")):gsub("\n", ""))
  love.filesystem.createDirectory("imports")
  note("imports dir exists: %s", tostring(love.filesystem.getInfo("imports") ~= nil))

  -- LuaJIT
  if jit then
    note("LuaJIT %s, jit.status %s, arch %s, os %s", jit.version, tostring((jit.status())), jit.arch, jit.os)
    local t0 = love.timer.getTime()
    local acc = 0
    for i = 1, 20000000 do acc = acc + (i % 7) * 0.5 end
    note("20M-iteration loop: %.3f s (acc %.0f)", love.timer.getTime() - t0, acc)
  end
  local okffi, ffi = pcall(require, "ffi")
  if okffi then
    pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
    pcall(ffi.cdef, "char **PHYSFS_getSearchPath(void); void PHYSFS_freeList(void *listVar);")
    pcall(ffi.cdef, "int getpid(void);")
    local okS, list = pcall(function() return ffi.C.PHYSFS_getSearchPath() end)
    if okS and list ~= nil then
      local i, dirs = 0, {}
      while list[i] ~= nil do dirs[#dirs + 1] = ffi.string(list[i]); i = i + 1 end
      ffi.C.PHYSFS_freeList(list)
      note("ffi.C.PHYSFS_getSearchPath: %s", table.concat(dirs, ", "))
    else
      note("ffi.C.PHYSFS_getSearchPath FAILED: %s", tostring(list))
    end
    local okP, pid = pcall(function() return ffi.C.getpid() end)
    note("ffi.C.getpid: %s %s", tostring(okP), tostring(pid))
    local okL, e = pcall(ffi.load, "love")
    note("ffi.load('love') fails cleanly: %s (%s)", tostring(not okL), tostring(e))
  end

  -- C++ exception -> Lua error (love::Exception through luax_catchexcept,
  -- then LuaJIT's unwinder): needs working eh_frame/libunwind in the title
  -- and the static C++ runtime (scripts/ps5/build_runtime.sh, cxx_own).
  local okE, errE = pcall(love.graphics.newImage, "does/not/exist.png")
  note("C++ exception caught as Lua error: %s (%s)", tostring(not okE), tostring(errE):sub(1, 60))
  local okT, errT = pcall(function() error({code = 7}) end)
  note("Lua error with table value: %s", tostring(not okT and type(errT) == "table" and errT.code == 7))

  -- a love.thread worker
  local th = love.thread.newThread([[
    local ch = love.thread.getChannel("ps5test")
    local acc = 0
    for i = 1, 1000000 do acc = acc + i end
    ch:push(acc)
  ]])
  th:start()
  note("thread result: %s", tostring(love.thread.getChannel("ps5test"):demand(5)))

  -- shader + canvas
  local okSh, sh = pcall(love.graphics.newShader, [[
    extern number time;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      return vec4(0.5 + 0.5 * sin(time + tc.x * 6.0), 0.5 + 0.5 * sin(time * 1.3 + tc.y * 6.0), 0.8, 1.0) * color;
    }
  ]])
  note("shader: %s %s", tostring(okSh), okSh and "" or tostring(sh))
  if okSh then shader = sh end
  canvas = love.graphics.newCanvas(320, 180)

  -- audio: a 440 Hz tone, played on any pad button
  local rate, len = 48000, 0.25
  local sd = love.sound.newSoundData(math.floor(rate * len), rate, 16, 1)
  for i = 0, sd:getSampleCount() - 1 do
    local env = math.min(1, (sd:getSampleCount() - i) / 2000)
    sd:setSample(i, math.sin(2 * math.pi * 440 * i / rate) * 0.4 * env)
  end
  local okA, src = pcall(love.audio.newSource, sd)
  note("audio source: %s, active devices %s", tostring(okA), tostring(love.audio.getActiveSourceCount and love.audio.getActiveSourceCount()))
  if okA then tone = src; tone:play() end

  local js = love.joystick.getJoysticks()
  note("joysticks: %d", #js)
  for _, j in ipairs(js) do
    note("  %s guid %s gamepad %s", j:getName(), j:getGUID(), tostring(j:isGamepad()))
  end
end

function love.joystickadded(j)
  note("joystick added: %s gamepad %s", j:getName(), tostring(j:isGamepad()))
end

function love.gamepadpressed(j, b)
  pressed[#pressed + 1] = b
  if #pressed > 12 then table.remove(pressed, 1) end
  print("[test] gamepadpressed " .. b)
  if tone then tone:stop(); tone:play() end
end

function love.joystickpressed(j, b)
  if not j:isGamepad() then
    pressed[#pressed + 1] = "btn" .. b
    print("[test] joystickpressed " .. b)
    if tone then tone:stop(); tone:play() end
  end
end

local t = 0
function love.update(dt)
  t = t + dt
  frames = frames + 1
  local js = love.joystick.getJoysticks()[1]
  if js and js:isGamepad() then
    axes = string.format("LX %.2f LY %.2f RX %.2f RY %.2f L2 %.2f R2 %.2f",
      js:getGamepadAxis("leftx"), js:getGamepadAxis("lefty"),
      js:getGamepadAxis("rightx"), js:getGamepadAxis("righty"),
      js:getGamepadAxis("triggerleft"), js:getGamepadAxis("triggerright"))
  end
  if math.floor(t) ~= math.floor(t - dt) then
    fpsShown = love.timer.getFPS()
    if math.floor(t) % 10 == 0 then print(string.format("[test] t=%d fps=%d", math.floor(t), fpsShown)) end
  end
end

function love.draw()
  local w, h = love.graphics.getDimensions()
  love.graphics.clear(0.08, 0.1, 0.16)
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 1)
  if shader then shader:send("time", t); love.graphics.setShader(shader) end
  love.graphics.rectangle("fill", 0, 0, 320, 180)
  love.graphics.setShader()
  love.graphics.setCanvas()
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, w - 340, 20)
  for i = 0, 5 do
    love.graphics.setColor(0.5 + 0.5 * math.sin(t + i), 0.4, 0.9 - i * 0.1)
    love.graphics.circle("fill", w - 170 + math.cos(t * 2 + i) * 120, 360 + math.sin(t * 2 + i) * 120, 24)
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(font)
  local y = 20
  for _, s in ipairs(lines) do
    love.graphics.print(s, 20, y)
    y = y + 34
  end
  love.graphics.print(string.format("FPS %d   frames %d", fpsShown, frames), 20, h - 120)
  love.graphics.print("pad: " .. table.concat(pressed, " "), 20, h - 85)
  love.graphics.print(axes, 20, h - 50)
end
