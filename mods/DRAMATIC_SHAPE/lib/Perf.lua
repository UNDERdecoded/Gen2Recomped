-- Voxel world mode: the instrumentation core.
--
-- Ships DARK. Every entry point is one boolean test away from doing
-- nothing, and the boolean is false unless a run explicitly asks for
-- measurement (DS_PERF in the environment, or a ds_perf.flag file in the
-- save directory for a device that has no environment to set). A mod that
-- measures itself in every player's session is a mod that costs every
-- player the measurement, so the default has to be off and the off path
-- has to be free.
--
-- What it measures, and why those three things:
--
--   * LABELS -- named spans (a bake, a mesh build, a shader compile),
--     accumulated as {n, total, max}. `max` is the one that matters: a
--     bake that costs 40ms ONCE is a visible hitch, and an average hides
--     it completely.
--   * FRAMES -- a ring of the last N whole-frame times, stamped once per
--     rendered frame. Frame time is the only number the player actually
--     experiences; every label total is a hypothesis about which frames.
--   * COUNTERS -- plain integers a caller bumps (sun-pass redraws, atlas
--     rebakes). Cheaper than a span when the question is "how often",
--     not "how long".
--
-- Spans are wall time, and on a GPU that means submission time, not
-- completion time -- the driver is free to finish the work later. So a
-- GPU-side saving shows up in the FRAME numbers rather than in the label
-- for the pass that caused it, and both are reported.

local Perf = {}

local clock = (love and love.timer and love.timer.getTime) or os.clock

-- Read through pcall: the loader's sandbox does not hand a mod `os`, and
-- instrumentation must never be the reason the mod fails to load. Same
-- shape as OverworldBattle's DS_BATTLE_DEBUG probe.
local function envFlag(name)
  local ok, value = pcall(function() return os.getenv(name) end)
  if not ok then return nil end
  if value == nil or value == "" or value == "0" then return nil end
  return value
end

local function flagFile()
  if not (love and love.filesystem and love.filesystem.getInfo) then
    return false
  end
  local ok, info = pcall(love.filesystem.getInfo, "ds_perf.flag")
  return ok and info ~= nil
end

Perf.enabled = (envFlag("DS_PERF") ~= nil) or flagFile()

Perf.labels = {}      -- label -> { n, total, max }
Perf.order = {}       -- insertion order, so a report reads chronologically
Perf.counters = {}    -- name -> integer
Perf.frames = {}      -- ring of frame times, seconds
Perf.frameCount = 0
Perf.RING = 4096

-- The segment a frame belongs to ("map:ROUTE_1:first"). A benchmark
-- names the phase it is driving; every frame and every label span
-- recorded while that name is set is attributed to it, which is what
-- turns "the walk was slow" into "the walk was slow ONLY on the frames
-- right after ROUTE_1 came into view".
Perf.segment = nil
Perf.segments = {}    -- name -> { frames = {}, labels = {}, order = {} }

local function segmentEntry()
  local name = Perf.segment
  if not name then return nil end
  local s = Perf.segments[name]
  if not s then
    s = { name = name, frames = {}, labels = {}, order = {} }
    Perf.segments[name] = s
    Perf.segments[#Perf.segments + 1] = s   -- array half preserves order
  end
  return s
end

function Perf.setSegment(name)
  Perf.segment = name
  if name then segmentEntry() end
end

-- ---------------------------------------------------------------- spans
--
-- Call shape at the measured site:
--
--   local t0 = Perf.now()
--   ... the work ...
--   Perf.add("TerrainAtlas.staticAtlas", t0)
--
-- When disabled, now() returns nil and add() returns on the nil -- two
-- function calls and a branch, no table touched, no string built. Sites
-- that would run thousands of times a frame (per draw call, per vertex)
-- are still too hot for that and are deliberately NOT instrumented; the
-- frame ring covers them in aggregate.

function Perf.now()
  if not Perf.enabled then return nil end
  return clock()
end

local function bump(store, order, label, dt)
  local s = store[label]
  if not s then
    s = { n = 0, total = 0, max = 0 }
    store[label] = s
    order[#order + 1] = label
  end
  s.n = s.n + 1
  s.total = s.total + dt
  if dt > s.max then s.max = dt end
end

function Perf.add(label, t0)
  if t0 == nil then return end
  local dt = clock() - t0
  bump(Perf.labels, Perf.order, label, dt)
  local seg = segmentEntry()
  if seg then bump(seg.labels, seg.order, label, dt) end
end

-- Wrap a function in a table, in place. Used by drivers to instrument
-- module internals they do not own; the mod's own code calls now()/add()
-- directly so the label is visible at the site.
function Perf.wrap(tbl, name, label)
  local orig = tbl and tbl[name]
  if not orig then return false end
  tbl[name] = function(...)
    if not Perf.enabled then return orig(...) end
    local t0 = clock()
    local a, b, c, d = orig(...)
    Perf.add(label or name, t0)
    return a, b, c, d
  end
  return true
end

-- ------------------------------------------------------------- counters

function Perf.count(name, by)
  if not Perf.enabled then return end
  Perf.counters[name] = (Perf.counters[name] or 0) + (by or 1)
end

-- --------------------------------------------------------------- frames
--
-- Called once per RENDERED frame (the endFrame seam), not once per
-- logic update: a scripted run can step the game many times per render,
-- and a frame the player never saw cannot have hitched for them.

local lastFrame = nil

function Perf.frame()
  if not Perf.enabled then return end
  local t = clock()
  if lastFrame then
    local dt = t - lastFrame
    local n = Perf.frameCount + 1
    Perf.frameCount = n
    Perf.frames[(n - 1) % Perf.RING + 1] = dt
    local seg = segmentEntry()
    if seg then seg.frames[#seg.frames + 1] = dt end
  end
  lastFrame = t
end

-- Discard the pending frame stamp: after a long blocking operation the
-- next frame delta would include it and libel the renderer.
function Perf.resync()
  lastFrame = Perf.enabled and clock() or nil
end

-- ------------------------------------------------------------ reporting

local function percentile(sorted, p)
  local n = #sorted
  if n == 0 then return 0 end
  local i = math.ceil(p * n)
  if i < 1 then i = 1 end
  if i > n then i = n end
  return sorted[i]
end

-- Frame statistics in MILLISECONDS. p95/p99 rather than the average
-- because smoothness is a tail property: a run that averages 9ms and
-- spikes to 60ms four times reads as stuttering, and its average reads
-- as fine.
function Perf.frameStats(list)
  local src = list or Perf.frames
  local sorted = {}
  for i = 1, #src do sorted[i] = src[i] * 1000 end
  table.sort(sorted)
  local n = #sorted
  local total = 0
  for i = 1, n do total = total + sorted[i] end
  local over16, over33 = 0, 0
  for i = 1, n do
    if sorted[i] > 16.7 then over16 = over16 + 1 end
    if sorted[i] > 33.3 then over33 = over33 + 1 end
  end
  return {
    n = n,
    avg = n > 0 and total / n or 0,
    p50 = percentile(sorted, 0.50),
    p95 = percentile(sorted, 0.95),
    p99 = percentile(sorted, 0.99),
    worst = n > 0 and sorted[n] or 0,
    over16 = over16,
    over33 = over33,
  }
end

function Perf.reset()
  Perf.labels, Perf.order = {}, {}
  Perf.counters = {}
  Perf.frames, Perf.frameCount = {}, 0
  Perf.segments = {}
  Perf.segment = nil
  lastFrame = nil
end

local function sortedLabels(store, order)
  local out = {}
  for _, lbl in ipairs(order) do out[#out + 1] = lbl end
  table.sort(out, function(a, b) return store[a].total > store[b].total end)
  return out
end

function Perf.printReport(title)
  print(("[perf] ==== %s ===="):format(tostring(title or "report")))
  local f = Perf.frameStats()
  print(("[perf] frames n=%d avg=%.2fms p50=%.2f p95=%.2f p99=%.2f worst=%.2f  >16.7ms=%d  >33.3ms=%d")
    :format(f.n, f.avg, f.p50, f.p95, f.p99, f.worst, f.over16, f.over33))
  for _, seg in ipairs(Perf.segments) do
    local s = Perf.frameStats(seg.frames)
    print(("[perf] seg %-28s n=%4d avg=%6.2f p95=%6.2f p99=%6.2f worst=%7.2f >16.7=%3d >33.3=%3d")
      :format(seg.name, s.n, s.avg, s.p95, s.p99, s.worst, s.over16, s.over33))
  end
  print("[perf] ---- labels (ms, sorted by total) ----")
  for _, lbl in ipairs(sortedLabels(Perf.labels, Perf.order)) do
    local s = Perf.labels[lbl]
    print(("[perf] %-46s n=%6d total=%9.1f max=%8.2f")
      :format(lbl, s.n, s.total * 1000, s.max * 1000))
  end
  local names = {}
  for k in pairs(Perf.counters) do names[#names + 1] = k end
  table.sort(names)
  if #names > 0 then print("[perf] ---- counters ----") end
  for _, k in ipairs(names) do
    print(("[perf] %-46s %d"):format(k, Perf.counters[k]))
  end
end

-- ------------------------------------------------------------------ json
--
-- Hand-rolled rather than pulled from the engine: the report has to be
-- readable by a diff tool between two runs, and that means stable key
-- ORDER, which a generic serializer does not promise.

local function q(s)
  return '"' .. tostring(s):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    return ("\\u%04x"):format(c:byte())
  end) .. '"'
end

local function num(x)
  return ("%.4f"):format(x)
end

local function statsJson(f)
  return ("{\"n\":%d,\"avg\":%s,\"p50\":%s,\"p95\":%s,\"p99\":%s,\"worst\":%s,\"over16\":%d,\"over33\":%d}")
    :format(f.n, num(f.avg), num(f.p50), num(f.p95), num(f.p99),
            num(f.worst), f.over16, f.over33)
end

local function labelsJson(store, order)
  local parts = {}
  for _, lbl in ipairs(sortedLabels(store, order)) do
    local s = store[lbl]
    parts[#parts + 1] = ("%s:{\"n\":%d,\"total\":%s,\"max\":%s}")
      :format(q(lbl), s.n, num(s.total * 1000), num(s.max * 1000))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function Perf.toJson(meta)
  local parts = {}
  parts[#parts + 1] = "{"
  parts[#parts + 1] = "\"meta\":{"
  local m = {}
  for k, v in pairs(meta or {}) do
    m[#m + 1] = q(k) .. ":" .. (type(v) == "number" and num(v) or q(v))
  end
  table.sort(m)
  parts[#parts + 1] = table.concat(m, ",") .. "},"
  parts[#parts + 1] = "\"frames\":" .. statsJson(Perf.frameStats()) .. ","
  parts[#parts + 1] = "\"segments\":{"
  local segs = {}
  for _, seg in ipairs(Perf.segments) do
    segs[#segs + 1] = q(seg.name) .. ":{\"frames\":"
      .. statsJson(Perf.frameStats(seg.frames))
      .. ",\"labels\":" .. labelsJson(seg.labels, seg.order) .. "}"
  end
  parts[#parts + 1] = table.concat(segs, ",") .. "},"
  parts[#parts + 1] = "\"labels\":" .. labelsJson(Perf.labels, Perf.order) .. ","
  local cs = {}
  for k, v in pairs(Perf.counters) do cs[#cs + 1] = q(k) .. ":" .. v end
  table.sort(cs)
  parts[#parts + 1] = "\"counters\":{" .. table.concat(cs, ",") .. "}"
  parts[#parts + 1] = "}"
  return table.concat(parts, "")
end

-- Written through love.filesystem (the save directory) rather than io:
-- a driver run and an Android session both have one, and neither is
-- guaranteed a writable working directory.
function Perf.write(name, meta)
  local body = Perf.toJson(meta)
  if love and love.filesystem then
    pcall(love.filesystem.createDirectory, "ds_bench")
    local ok = pcall(love.filesystem.write, "ds_bench/" .. name .. ".json", body)
    if ok then
      print("[perf] wrote " .. tostring(love.filesystem.getSaveDirectory())
            .. "/ds_bench/" .. name .. ".json")
      return true
    end
  end
  print("[perf] JSON " .. name .. ": " .. body)
  return false
end

-- ----------------------------------------------------------- draw stats
--
-- love.graphics.getStats() resets per frame, so it is only meaningful
-- read at the END of a frame -- which is where Perf.frame() runs.

function Perf.drawStats()
  if not (love and love.graphics and love.graphics.getStats) then return end
  local s = love.graphics.getStats()
  Perf.count("stat.drawcalls", s.drawcalls or 0)
  Perf.count("stat.canvasswitches", s.canvasswitches or 0)
  Perf.count("stat.shaderswitches", s.shaderswitches or 0)
  Perf.count("stat.frames", 1)
  Perf.texturememory = s.texturememory
  Perf.canvases = s.canvases
  Perf.images = s.images
end

return Perf
