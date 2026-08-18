-- Minimal logger; warnings are collected so debug overlays can show them.
--
-- ...and, since 0.7.6, written to log.txt in the save directory.
--
-- Every diagnostic this engine and every mod produces went to stdout and
-- nowhere else.  On Windows that is a console window the launcher hides, and
-- on Android and the Switch there is no console at all -- so when a large mod
-- reported exactly why it had not installed its renderer, or which optional
-- bridge it had skipped, NOBODY COULD READ IT.  "The mod doesn't work" was as
-- much detail as anyone could give, because the mod's own explanation was
-- being printed into a void.
--
-- The file is truncated once per boot and the previous run is kept beside it,
-- because the interesting run is usually the one that just ended badly.

local Logger = { history = {} }

local PATH, PREVIOUS = "log.txt", "log_previous.txt"
-- a runaway warn in an update loop must not fill the player's disk
local MAX_LINES = 20000
-- ...and must not cost a frame either.  A mod that warns once per spawn per
-- frame produced 17,000 lines and 2 MB in one session, and the FIRST version
-- of this file flushed every one of them to disk immediately because they
-- were not info -- so turning the log on made the very lag it was meant to
-- diagnose measurably worse.  A message that has already been said 20 times
-- says nothing the 21st time: count it and stop writing it.
local REPEAT_LIMIT = 20
local FLUSH_AT = 64

local buffer, buffered = {}, 0
local started, lines, stopped = false, 0, false
local counts, suppressed, distinct = {}, 0, 0

local function fs()
  return love and love.filesystem
end

-- Logger is required during boot, before love.filesystem is mounted, so the
-- first lines are held until there is somewhere to put them.
local function start(f)
  started = true
  if f.getInfo and f.getInfo(PATH, "file") then
    local old = f.read(PATH)
    if old then pcall(f.write, PREVIOUS, old) end
  end
  local ok = pcall(f.write, PATH, "")
  if not ok then stopped = true end
end

local function flush(f)
  if buffered == 0 then return end
  local chunk = table.concat(buffer, "\n") .. "\n"
  buffer, buffered = {}, 0
  local ok = pcall(f.append or f.write, PATH, chunk)
  if not ok then stopped = true end
end

-- Buffered rather than one append per line: a boot is a few hundred lines and
-- an import is thousands, and a filesystem round trip each would show up in
-- the frame time of the very thing being diagnosed.
-- Has this exact line been said enough times already?  Returns the text to
-- write, or nil to drop it.  The 20th occurrence carries the notice, so the
-- log says plainly that it stopped rather than appearing to end.
local MAX_DISTINCT = 2000

-- Count by SHAPE, not by exact text.
--
-- The first cut of this counted whole lines, which caught
--
--   [warn] occupancy conflict at 19,16 ...
--
-- and completely missed
--
--   [info] spawned water SPECIES_129 Lv 10 WATER_WANDER ... at (23,17)
--
-- because every one of those 2,897 lines carried a different species, level
-- and coordinate and so was, textually, unique.  One spawn loop, 4,800 lines,
-- and the rate limiter had nothing to hold on to.  Numbers and pointers are
-- exactly the part that varies while the MESSAGE stays the same, so they are
-- what the counter ignores.
local function shapeOf(line)
  local shape = line:gsub("0x%x+", "P"):gsub("%d+", "#")
  return shape
end

local function rateLimit(raw)
  local line = shapeOf(raw)
  local n = (counts[line] or 0) + 1
  if n == 1 then
    distinct = distinct + 1
    -- Lines that embed a pointer or a coordinate are all distinct, so the
    -- counter table is itself unbounded.  Start over rather than grow: the
    -- limit exists to stop a spam loop, and a spam loop re-earns its count in
    -- moments.
    if distinct > MAX_DISTINCT then counts, distinct, n = { }, 1, 1 end
  end
  counts[line] = n
  if n < REPEAT_LIMIT then return raw end
  if n == REPEAT_LIMIT then
    return raw .. "  (repeated " .. REPEAT_LIMIT
      .. " times; further lines of this shape suppressed)"
  end
  suppressed = suppressed + 1
  return nil
end

local function record(raw)
  if stopped or lines >= MAX_LINES then return end
  local line = rateLimit(raw)
  if not line then return end
  lines = lines + 1
  buffer[buffered + 1] = line
  buffered = buffered + 1
  if lines == MAX_LINES then
    buffer[buffered + 1] = "[warn] log truncated at " .. MAX_LINES .. " lines"
    buffered = buffered + 1
  end
  local f = fs()
  if not (f and (f.append or f.write)) then return end
  if not started then start(f) end
  -- ERRORS land immediately -- a crash right after one must not take the
  -- reason for it with it -- and everything else rides the buffer.  A warn is
  -- not worth a filesystem round trip inside an update loop; Logger.flush()
  -- and the next error both drain it, and the crash handler calls flush.
  if buffered >= FLUSH_AT or line:sub(1, 7) == "[error]" then flush(f) end
end

-- Called at a clean stopping point (quit, crash handler) so a partial buffer
-- is not lost.  Safe to call when nothing is pending.
function Logger.flush()
  local f = fs()
  if not (f and started and not stopped) then return end
  if suppressed > 0 then
    buffer[buffered + 1] = ("[info] %d further repeated line(s) suppressed")
      :format(suppressed)
    buffered = buffered + 1
    suppressed = 0
  end
  flush(f)
end

-- How many times a line has been seen, and how many were dropped.  The
-- duplicate COUNT is the interesting number when a mod is spamming: 485
-- identical warnings is a spawn loop, not 485 problems.
function Logger.repeats(line)
  return counts[shapeOf(line)] or 0
end

function Logger.suppressedCount()
  return suppressed
end

function Logger.path()
  local f = fs()
  local dir = f and f.getSaveDirectory and f.getSaveDirectory()
  return dir and (dir .. "/" .. PATH) or PATH
end

local function emit(level, fmt, ...)
  local ok, msg = true, fmt
  if select("#", ...) > 0 then
    ok, msg = pcall(string.format, fmt, ...)
    if not ok then msg = tostring(fmt) end
  end
  local line = string.format("[%s] %s", level, tostring(msg))
  -- print() to a Windows console is a synchronous write; the same spam that
  -- filled the file was also stalling the frame here, before any of this
  -- reached disk.  One counter governs both sinks.
  if (counts[shapeOf(line)] or 0) < REPEAT_LIMIT then print(line) end
  table.insert(Logger.history, line)
  if #Logger.history > 200 then
    table.remove(Logger.history, 1)
  end
  record(line)
end

function Logger.info(fmt, ...) emit("info", fmt, ...) end
function Logger.warn(fmt, ...) emit("warn", fmt, ...) end
function Logger.error(fmt, ...) emit("error", fmt, ...) end

return Logger
