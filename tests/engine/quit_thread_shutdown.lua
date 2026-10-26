-- Quitting has to end the process (#339).  Both background love.thread
-- workers idle in loops that only a { cmd = "quit" } command breaks
-- (src/core/chip_worker.lua, src/update/check_worker.lua) and LOVE joins
-- every live thread before the process exits, so with no shutdown the window
-- closed while the process kept spinning: on Android the relaunched task
-- re-entered an activity whose native main had already returned.  Purely a
-- port lifecycle concern, so no pokered citation.
-- ROM-free: a ChipAsm blob plus a fake love.thread.
--   luajit tests/engine/quit_thread_shutdown.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

love = require("tests.love_stub")

-- ------- audio + thread stubs

local Source = {}
Source.__index = Source
function Source:play() self.playing = true end
function Source:stop() self.playing = false end
function Source:isPlaying() return self.playing end
function Source:getFreeBufferCount() return self.free end
function Source:queue() self.free = math.max(0, self.free - 1) end

local ChipSynth = require("src.core.ChipSynth")

love.audio = {
  newQueueableSource = function()
    return setmetatable({ free = ChipSynth.MUSIC_BUFFER_COUNT }, Source)
  end,
}

local channels, threads = {}, {}

local Channel = {}
Channel.__index = Channel
function Channel:push(msg) self.log[#self.log + 1] = msg end
function Channel:pop() return table.remove(self.log, 1) end
function Channel:clear() self.log = {} end
function Channel:getCount() return #self.log end

-- the command channels are read back after shutdown, so keep every command
-- pushed on them rather than letting pop/clear consume the history
local Recorder = setmetatable({}, { __index = Channel })
Recorder.__index = Recorder
function Recorder:pop() return nil end
function Recorder:clear() end

local function channel(name)
  if not channels[name] then
    local mt = name:find("cmd", 1, true) and Recorder or Channel
    channels[name] = setmetatable({ log = {} }, mt)
  end
  return channels[name]
end

local function commands(name)
  local out = {}
  for _, msg in ipairs(channel(name).log) do
    out[#out + 1] = type(msg) == "table" and msg.cmd or tostring(msg)
  end
  return out
end

local function counted(list, want)
  local n = 0
  for _, cmd in ipairs(list) do
    if cmd == want then n = n + 1 end
  end
  return n
end

love.thread = {
  newThread = function(path)
    local th = { path = path, waited = 0, started = false }
    th.start = function() th.started = true end
    th.getError = function() return nil end
    th.wait = function() th.waited = th.waited + 1 end
    threads[#threads + 1] = th
    return th
  end,
  getChannel = channel,
}

local function threadFor(path)
  for _, th in ipairs(threads) do
    if th.path == path then return th end
  end
  return nil
end

-- ------- chip audio worker

local ChipAsm = require("src.audio.ChipAsm")

local song = ChipAsm.song{
  channels = { { hw = 1, program = {
    { notetype = { speed = 12, volume = 12, fade = 0 } },
    { octave = 4 },
    { note = "C", len = 8 },
    { loop = { count = 0, to = 1 } },
  } } },
}
local data = { audio = { songs = { Music_PalletTown = song } } }

-- absent before the fix; called through this so the rest of the report still
-- runs instead of erroring out on the first missing entry point
local function shutdown(mod)
  if type(mod.shutdown) == "function" then mod.shutdown() end
end

local ChipAudio = require("src.core.ChipAudio")
check(type(ChipAudio.shutdown) == "function", "ChipAudio exposes shutdown")

check(ChipAudio.playMusic(data, song, true) ~= nil,
      "threaded playMusic starts the chip worker")
local chipThread = threadFor("src/core/chip_worker.lua")
check(chipThread ~= nil and chipThread.started, "the chip worker is running")
eq(counted(commands("chipaudio_cmd"), "quit"), 0,
   "nothing tells the chip worker to quit during play")

shutdown(ChipAudio)
local chipCmds = commands("chipaudio_cmd")
eq(chipCmds[#chipCmds], "quit", "shutdown pushes the chip worker's quit command")
eq(chipThread.waited, 1, "shutdown joins the chip worker instead of leaving it live")

-- a second call must not push onto a channel whose worker is already gone,
-- and neither must the normal playback calls that survive teardown
shutdown(ChipAudio)
ChipAudio.stopMusic()
ChipAudio.invalidate()
eq(counted(commands("chipaudio_cmd"), "quit"), 1,
   "shutdown is idempotent and post-shutdown calls stay quiet")
eq(chipThread.waited, 1, "the joined worker is not waited on twice")

-- ------- update check worker

local Check = require("src.update.Check")
check(type(Check.shutdown) == "function", "Check exposes shutdown")

Check.start()
local checkThread = threadFor("src/update/check_worker.lua")
check(checkThread ~= nil and checkThread.started, "the update worker is running")
eq(commands("update_check_cmd")[1], "check", "start pushes the check command")

shutdown(Check)
local upCmds = commands("update_check_cmd")
eq(upCmds[#upCmds], "quit", "shutdown pushes the update worker's quit command")
eq(checkThread.waited, 1, "shutdown joins the update worker")

shutdown(Check)
Check.download()
eq(counted(commands("update_check_cmd"), "quit"), 1,
   "shutdown is idempotent and post-shutdown calls stay quiet")
eq(Check.state().status ~= nil, true, "state() still answers after shutdown")

-- ------- the worker loops still break on that command

local function source(path)
  local f = io.open(path, "rb")
  check(f ~= nil, path .. " is readable")
  local text = f and f:read("*a") or ""
  if f then f:close() end
  return text
end

local chipSrc = source("src/core/chip_worker.lua")
check(chipSrc:match('cmd%.cmd == "quit"%s*then%s*\n%s*return true') ~= nil,
      "chip_worker leaves its command loop on quit")
local checkSrc = source("src/update/check_worker.lua")
check(checkSrc:match('cmd%.cmd == "quit"%s*then%s*\n%s*break') ~= nil,
      "check_worker leaves its demand loop on quit")

-- ------- main.lua wiring
-- love.quit is the established teardown hook (DiscordPresence already rides
-- it) and reaches the modules through package.loaded, so a session that never
-- touched audio or the launcher pays nothing.

local mainSrc = source("main.lua")
local quitHook = mainSrc:match("\nfunction love%.quit%(%).-\nend\n")
check(quitHook ~= nil, "love.quit is still a single top-level function")
quitHook = quitHook or ""
check(quitHook:find('package.loaded["src.core.ChipAudio"].shutdown', 1, true) ~= nil,
      "love.quit shuts the chip worker down")
check(quitHook:find('package.loaded["src.update.Check"].shutdown', 1, true) ~= nil,
      "love.quit shuts the update worker down")

-- The Android half: LOVE keeps the JVM process after the native main returns,
-- so the quit event exits the process outright.  It has to sit after the
-- love.quit() veto test, or the editor's abort-quit path would die on a quit
-- it refused.
-- Execute the actual run-loop function in an isolated environment. Scanning
-- nested `end`s or counting os.exit in comments cannot prove veto behavior.
local runAt = assert(mainSrc:find("\nfunction love.run()", 1, true))
local runSource = mainSrc:sub(runAt + 1)
local function quitFrame(platform, answer, code, noCallback)
  local calls, exits = {}, {}
  local function record(name) calls[#calls + 1] = name end
  local env = setmetatable({
    BootTrace = { mark = function() end, frame = function() record("frame") end },
    Frames = { tick = function() record("tick") end },
    FrameProfile = { section = function() return function() end end },
    pacingEnabled = function() return false end,
    os = { exit = function(value) record("exit"); exits[#exits + 1] = value end },
    love = {
      handlers = { quit = function() record("dispatch") end },
      update = function() record("update") end,
      event = {
        pump = function() end,
        poll = function()
          local sent = false
          return function()
            if not sent then sent = true; return "quit", code end
          end
        end,
      },
    },
  }, { __index = _G })
  if platform then env.love.system = { getOS = function() return platform end } end
  if not noCallback then
    env.love.quit = function() record("quit"); return answer end
  end
  local compile = loadstring or load
  local chunk
  if setfenv then
    chunk = assert(compile(runSource, "@main.lua:love.run"))
    setfenv(chunk, env)
  else
    chunk = assert(load(runSource, "@main.lua:love.run", "t", env))
  end
  chunk()
  local result = env.love.run()()
  return result, table.concat(calls, ","), exits
end

for _, platform in ipairs({ "Android", "Windows", "OS X", "Linux", "NX", false }) do
  local label = tostring(platform)
  for _, code in ipairs({ 0, 7, false }) do
    -- false is a table-friendly sentinel for an omitted exit status.
    local expected = code or 0
    for _, noCallback in ipairs({ false, true }) do
      for _, answer in ipairs({ false, "nil" }) do
        local callbackAnswer = answer
        if answer == "nil" then callbackAnswer = nil end
        local result, order, exits = quitFrame(platform, callbackAnswer, code or nil, noCallback)
        local prefix = noCallback and "" or "quit"
        eq(result, expected, label .. ": accepted quit returns its exit status")
        if platform == "Android" then
          eq(#exits, 1, "Android exits exactly once after accepting quit")
          eq(exits[1], expected, "Android forwards the requested exit status")
          eq(order, prefix == "" and "exit" or "quit,exit", "shutdown precedes process exit")
        else
          eq(#exits, 0, label .. ": accepted quit does not force a process exit")
          eq(order, prefix, label .. ": no further frame work after accepted quit")
        end
      end
    end
  end
  local result, order, exits = quitFrame(platform, true, 7)
  eq(result, nil, label .. ": veto keeps the frame running")
  eq(#exits, 0, label .. ": veto never exits the process")
  eq(order, "quit,dispatch,update,frame,tick", label .. ": veto resumes event and frame processing")
end

T.finish("quit thread shutdown")
