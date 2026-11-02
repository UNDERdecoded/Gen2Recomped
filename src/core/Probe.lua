-- A DIAGNOSTIC THAT ACTUALLY REACHES THE DISK.
--
-- Every attempt to diagnose a field-time draw bug from log.txt came back with
-- an EMPTY FILE, repeatedly, and the reason is in src/core/Logger.lua: it
-- buffers and only writes once 64 lines have piled up (FLUSH_AT), or on an
-- [error] line -- and it truncates log.txt on boot, rotating the previous run
-- aside.  A handful of diagnostic lines produced while walking around is
-- always fewer than 64, so they sat in the buffer until the game closed and
-- the next boot threw them away.  That is exactly the right trade for a
-- logger (a per-line filesystem round trip in an update loop is the very lag
-- it would be used to diagnose) and exactly the wrong one for this.
--
-- So: its own file, one line at a time, written and closed immediately, and
-- capped per tag so a call in a draw loop cannot fill a disk.  It is for
-- answering a specific question once, not for logging.
local Probe = { counts = {}, total = 0 }

local PATH = "probe.txt"
local PER_TAG = 12     -- a tag says its piece and then shuts up
local TOTAL = 500      -- ...and the file has a ceiling regardless
local started = false

local function fs()
  return love and love.filesystem
end

function Probe.say(tag, fmt, ...)
  local f = fs()
  if not f then return end
  local n = Probe.counts[tag] or 0
  if n >= PER_TAG or Probe.total >= TOTAL then return end
  Probe.counts[tag] = n + 1
  Probe.total = Probe.total + 1
  if not started then
    started = true
    pcall(f.write, PATH, "")
  end
  local ok, line = pcall(string.format, fmt, ...)
  if not ok then line = tostring(fmt) end
  pcall(f.append or f.write, PATH, "[" .. tag .. "] " .. line .. "\n")
end

-- Would a line under this tag still be written? For a caller whose line costs
-- real work to build (a decode, a pixel count), so it stops once the cap is hit.
function Probe.wants(tag)
  return (Probe.counts[tag] or 0) < PER_TAG and Probe.total < TOTAL
end

-- Say something once, ever, under this tag.
function Probe.once(tag, fmt, ...)
  if Probe.counts[tag] then return end
  Probe.say(tag, fmt, ...)
end

return Probe
