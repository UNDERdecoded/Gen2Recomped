-- Boot breadcrumbs for platforms where you cannot watch the app die.
--
-- On desktop a crash is self-explanatory: the blue error screen names the file
-- and the line.  On Android and the Switch it is not.  The window is up for
-- about a second and then the process is gone, and the two things that would
-- normally tell you why are both unavailable -- logcat needs a cable and adb,
-- and love.errorhandler's crash.txt only ever fires for a LUA error.  A native
-- abort (an OOM kill, a JNI check failure, a driver fault) reaches no Lua
-- handler at all, so it leaves crash.txt completely empty and the absence
-- looks identical to "nothing went wrong".
--
-- This closes that gap from the other side: instead of recording the failure,
-- record the PROGRESS, so the last line written is the stage the process did
-- not survive.  Every mark is an open-write-close, never a buffered handle, so
-- the file on disk is current even when the next instruction kills us.
--
-- The player can read it with a file manager, no cable:
--   Android  Android/data/<package>/files/boot_trace.txt
--   Switch   <SD>/switch/gen2recomp/Gen2Recomp/boot_trace.txt
--   desktop  the LOVE save folder, beside save.lua
--
-- Deliberately cheap and deliberately always-on: a dozen short lines per
-- launch, truncated at the start of each run, so it can never grow without
-- bound and there is never a "turn it on and reproduce it" round trip -- the
-- run that failed has already written it.

local BootTrace = {}

local PATH = "boot_trace.txt"

local started = false
local t0 = nil

-- The PREVIOUS launch's trace, captured before this launch truncates the file,
-- and whether it ended with "clean exit".
--
-- This exists because on Android the file is written somewhere the player
-- cannot open.  t.externalstorage puts the save directory under
-- Android/data/<package>/files/, and since Android 11 that path is off limits
-- to every third-party file manager -- the app can write it, nobody can read
-- it without adb.  So the trace has to come back to the player through the one
-- channel that always works: the app's own screen, on the next launch.
local previousText = nil
local previousClean = nil

local function now()
  if love and love.timer and love.timer.getTime then
    return love.timer.getTime()
  end
  return os.time()
end

-- Everything here runs inside pcall.  A tracer that can raise is worse than no
-- tracer at all: it would turn a clean boot into the very crash it exists to
-- explain, on exactly the platforms that cannot show the error.
local function write(line, append)
  pcall(function()
    if not (love and love.filesystem) then return end
    if append and love.filesystem.append then
      love.filesystem.append(PATH, line .. "\n")
    else
      love.filesystem.write(PATH, line .. "\n")
    end
  end)
end

-- One header per launch, and the truncation that keeps the file to one launch.
-- The header is the part that makes a returned trace diagnosable on its own:
-- which build, which platform, fused or loose.
local function begin()
  started = true
  t0 = now()
  -- Read the last run out before the header below overwrites it.  A run that
  -- ended without "clean exit" is one that died, and that is what the caller
  -- puts on screen.
  pcall(function()
    if not (love and love.filesystem and love.filesystem.read) then return end
    local prior = love.filesystem.read(PATH)
    if type(prior) == "string" and prior ~= "" then
      previousText = prior
      -- "Nothing to report" is either an orderly exit OR a run that got past
      -- boot without raising -- see BootTrace.booted.  An "ERROR" mark
      -- overrides both: love.errorhandler writes one, so a real Lua error is
      -- always worth showing no matter how late it happened.
      local booted = prior:find("clean exit", 1, true) ~= nil
        or prior:find("\n%s*%d+ ms  booted") ~= nil
      previousClean = booted and prior:find("ms  ERROR ", 1, true) == nil
    end
  end)
  local parts = {}
  local ok, Version = pcall(require, "src.core.Version")
  parts[#parts + 1] = "engine " .. ((ok and Version and tostring(Version.engine)) or "?")
  pcall(function()
    parts[#parts + 1] = "os " .. tostring(love.system and love.system.getOS
      and love.system.getOS() or love._os or "?")
  end)
  pcall(function()
    parts[#parts + 1] = "fused " .. tostring(love.filesystem.isFused
      and love.filesystem.isFused())
  end)
  pcall(function()
    parts[#parts + 1] = "date " .. tostring(os.date("%Y-%m-%d %H:%M:%S"))
  end)
  write("---- boot " .. table.concat(parts, "  ") .. " ----", false)
end

-- BootTrace.mark(stage) -- record that execution reached `stage`.
--
-- Read the result as "the last line is where it died": if the file ends at
-- "launcher: images loaded" then the launcher's constructor got that far and
-- no further, which is a far tighter answer than any amount of reading the
-- source can give you.
function BootTrace.mark(stage)
  pcall(function()
    if not started then begin() end
    local ms = math.floor((now() - (t0 or now())) * 1000 + 0.5)
    write(("%6d ms  %s"):format(ms, tostring(stage)), true)
  end)
end

-- Frame counter, so the trace shows whether the loop ran at all and for how
-- long.  Marks the first few frames and then thins out to powers of ten: a
-- process that dies "about a second in" is somewhere between frame 1 and frame
-- 60, and that range is what needs the resolution.
local frames = 0
local NOTABLE = { [1] = true, [2] = true, [3] = true, [10] = true,
                  [30] = true, [60] = true, [120] = true, [300] = true,
                  [600] = true }

function BootTrace.frame()
  frames = frames + 1
  if NOTABLE[frames] then
    BootTrace.mark("frame " .. frames)
  end
end

-- Called from love.quit, so an orderly exit is distinguishable from a
-- disappearance.  A trace with no "clean exit" line and no crash.txt beside it
-- is the signature of a native abort.
function BootTrace.finish()
  BootTrace.mark("clean exit")
end

-- The boot succeeded: the launcher is up, or the game has loaded.
--
-- Without this, "did the last run end cleanly?" is the wrong question to gate
-- the on-screen report on, because the answer is no far more often than a
-- crash happens.  Swiping the app away, Android reclaiming it in the
-- background, pulling the USB cable mid-session -- none of them reach
-- love.quit, so none of them write "clean exit", and every subsequent launch
-- would open with a failure report for a session that was fine.  The report
-- is about failing to BOOT; once we are past that, a later disappearance is
-- not this file's business (a real error still lands in crash.txt and is
-- marked below, so genuine mid-session crashes are still reported).
function BootTrace.booted()
  BootTrace.mark("booted")
end

function BootTrace.path()
  return PATH
end

-- BootTrace.previousRun() -> text|nil, endedCleanly|nil
--
-- nil text means this is a first launch (or the file was unreadable), which is
-- NOT a failure -- do not report anything in that case.
function BootTrace.previousRun()
  if not started then begin() end
  return previousText, previousClean
end

-- The report the player sees on screen after a launch that died: last run's
-- breadcrumbs, plus the tail of crash.txt when a Lua error was caught (that
-- file holds the actual traceback; the trace only holds the stage).  Returns
-- nil when the previous launch ended cleanly or never happened.
function BootTrace.previousFailureReport()
  local text, clean = BootTrace.previousRun()
  if not text or clean then return nil end
  local out = { "PREVIOUS LAUNCH DID NOT FINISH", "", text }
  pcall(function()
    local crash = love.filesystem.read("crash.txt")
    if type(crash) == "string" and crash ~= "" then
      -- Tail only: crash.txt is appended to across runs and the newest entry
      -- is the one that matters on a phone screen.
      if #crash > 1800 then crash = "..." .. crash:sub(-1800) end
      out[#out + 1] = ""
      out[#out + 1] = "---- crash.txt (tail) ----"
      out[#out + 1] = crash
    end
  end)
  return table.concat(out, "\n")
end

return BootTrace
