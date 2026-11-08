-- tools/trailer/online_launcher/main.lua -- records online_host_code: the
-- launcher's Online Hub page, HOST WITH FRIENDS, KEEP A HUB RUNNING, then the
-- hub's share code and QR. Run by tools/trailer/capture_online.py (cwd =
-- repo, ROOT = repo, RUN = scratch run folder, FFMPEG).
--
-- The hub runs in the launcher's own thread bound to 127.0.0.1 (the
-- POKEPORT_HUB_* env the script sets: no router mapping, beacon to
-- 127.0.0.1 only). News / update fetches and any curl are stubbed: nothing
-- leaves this machine.
function love.errorhandler(msg)
  print("LAUNCHER ERROR: " .. tostring(msg))
  print(debug.traceback())
  os.exit(1)
end
love.errhand = love.errorhandler
io.stdout:setvbuf("line")

local ROOT = (os.getenv("ROOT") or love.filesystem.getWorkingDirectory()):gsub("\\", "/")
local RUN = assert(os.getenv("RUN"), "RUN"):gsub("\\", "/") .. "/"
do
  local ffi = require("ffi")
  pcall(ffi.cdef, "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  for _, lib in ipairs({ function() return ffi.C end, function() return ffi.load("love") end }) do
    local ok, l = pcall(lib)
    if ok and l then
      local okf, fn = pcall(function() return l.PHYSFS_mount end)
      if okf and fn and fn(ROOT, "", 1) ~= 0 then break end
    end
  end
end

-- never the player's saves
do
  local sd = love.filesystem.getSaveDirectory():gsub("\\", "/")
  print("save dir: " .. sd)
  if not sd:find("scratch_claude", 1, true) then
    print("REFUSING: save dir is not under scratch_claude: " .. sd)
    os.exit(2)
  end
end

love.system.setClipboardText = function() end
love.system.getClipboardText = function() return "" end
love.system.openURL = function(u) print("OPENURL (blocked) " .. tostring(u)) return true end

-- no external hosts: news, update check, any curl / http
do
  local HS = require("src.core.HostShell")
  HS.canFetch = function() return false end
  HS.httpGet = function() error("offline trailer harness") end
  local okC, Check = pcall(require, "src.update.Check")
  if okC and type(Check) == "table" then Check.start = function() end end
  local popen = io.popen
  io.popen = function(cmd, ...)
    local c = tostring(cmd)
    if c:find("curl", 1, true) or c:find("http", 1, true) or c:find("wget", 1, true) then
      print("BLOCKED POPEN " .. c:sub(1, 60))
      return nil, "blocked"
    end
    return popen(cmd, ...)
  end
end

local FFMPEG = os.getenv("FFMPEG") or "ffmpeg"
local WRITER = [[
  local ch, ffmpeg = ...
  require("love.image")
  local pipe
  while true do
    local job = ch:demand()
    if job == "stop" then if pipe then pipe:close() end return end
    if not pipe then
      local w, h = job.img:getDimensions()
      local cmd = ('"%s" -y -loglevel error -f rawvideo -pix_fmt rgba -s %dx%d -r 30 -i - '
        .. '-c:v libx264 -preset veryfast -crf 12 -pix_fmt yuv420p "%s"'):format(ffmpeg, w, h, job.path)
      if package.config:sub(1, 1) == "\\" then cmd = '"' .. cmd .. '"' end
      pipe = io.popen(cmd, "wb")
    end
    pipe:write(job.img:getString())
    job.img:release()
  end
]]
local queue = love.thread.getChannel("trailer_launcher_frames")
local writer = love.thread.newThread(WRITER)
writer:start(queue, FFMPEG)

local events = assert(io.open(RUN .. "events.txt", "w"))
local rawFrames, recording = 0, false
local function event(name) events:write(("%d %s\n"):format(rawFrames, name)) events:flush() print("event " .. name) end

-- the frame clock: animation advances 1/60 per frame
local realGetTime = love.timer.getTime
local clock = realGetTime()
love.timer.getTime = function() return clock end

local Importer, LH, scr
local script

local function frame() coroutine.yield() end
local function wait(n) for _ = 1, n do frame() end end
local function run()
  LH = require("src.online.LauncherHub")
  local cfg = LH.load()
  cfg.name = "FRIENDS HUB"
  cfg.port = 47790
  cfg.portMap = false
  cfg.lanBeacon = false
  cfg.hostChoice = nil
  cfg.autoStart = false
  cfg.world = cfg.world or {}
  cfg.world.port = 47791
  LH.save(cfg)
  local RomImporter = require("src.import.RomImporter")
  Importer = RomImporter.new(function() end, { launcher = true })
  wait(30)
  Importer:_sbGo("hub")
  scr = Importer.hubScreen
  assert(scr, "no hub screen")
  wait(90)
  recording = true
  event("rec")
  wait(50)
  scr:hostWithFriends()
  event("host")
  wait(70)
  scr:chooseHost("hub")
  event("keep_hub")
  local t = 0
  while not LH.running() and t < 600 do t = t + 1 frame() end
  event(LH.running() and "running" or "hub_failed")
  print("share code " .. tostring(LH.shareCode()))
  wait(60 * 6)
  event("end")
  recording = false
  LH.shutdown(3)
end

function love.load()
  script = coroutine.create(run)
end

local paceStart, n = realGetTime(), 0
function love.update()
  clock = clock + 1 / 60
  if Importer then Importer:update(1 / 60) end
  if coroutine.status(script) ~= "dead" then
    local ok, err = coroutine.resume(script)
    if not ok then
      print("LAUNCHER ERROR: " .. tostring(err))
      print(debug.traceback(script))
      os.exit(1)
    end
  else
    events:close()
    queue:push("stop")
    writer:wait()
    local f = io.open(RUN .. "recorder_ok", "w") f:write("1") f:close()
    os.exit(0)
  end
  n = n + 1
  local due = paceStart + n / 60
  local now = realGetTime()
  if due > now then love.timer.sleep(due - now) end
end

function love.draw()
  if Importer then Importer:draw() end
  if recording and n % 2 == 0 then
    rawFrames = rawFrames + 1
    while queue:getCount() > 24 do
      local e = writer:getError()
      if e then print("WRITER ERROR: " .. tostring(e)) os.exit(1) end
      love.timer.sleep(0.004)
    end
    love.graphics.captureScreenshot(function(img) queue:push({ path = RUN .. "raw.mp4", img = img }) end)
  end
end
