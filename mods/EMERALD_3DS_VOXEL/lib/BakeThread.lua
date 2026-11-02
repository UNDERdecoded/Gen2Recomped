-- The in-game bake's love.thread body (started by lib/BakeJob.lua).
--
-- Runs lib/bake's Bake.run on the player's ROM away from the frame: the
-- whole bake is minutes of CPU and up to a gigabyte or more of Lua heap, and
-- none of it touches love.graphics.  What it does, in order:
--
--   1. the six tree pictures and the two generator assets, fetched from
--      Emerald 3DS's repository at their pinned commits (cache first, in the
--      save directory's e3ds_voxel/cache/, so a re-bake needs no network)
--   2. Bake.run -> the four .bin files and layouts.lua, streamed as they
--      are made into e3ds_voxel/<name>.part (buildings.bin is never one
--      35 MB string: lib/bake/ARCHITECTURE.md "Memory")
--   3. once the whole bake succeeded: the stamp removed, incomplete.txt
--      written, the tree pictures written and every .part renamed over its
--      output, then the stamp, then incomplete.txt removed (lib/BakeJob.lua
--      only trusts a folder whose stamp matches and that has no
--      incomplete.txt).  A failed bake deletes its .part files and leaves
--      the outputs as they were.
--
-- Talks over three channels (names from BakeJob):
--   in    the job: cfg table, then the ROM, the recipe, the sources table
--   out   { kind = "progress", f, label } | { kind = "http", url, dest }
--         | { kind = "log", text } | { kind = "done", rom } | { kind = "error", message, code }
--   http  the main thread's answer to a "http" request: { ok, err }
--
-- Fresh love threads have no `src.*` searcher and none of the mod's V, so
-- this builds its own V over the source table the main thread sent (the mod
-- may live in a zip or a mounted folder the thread cannot address itself).

require("love.filesystem")
require("love.data")
require("love.timer")
pcall(require, "love.system")

local IN, OUT, HTTP = ...
local inCh = love.thread.getChannel(IN)
local outCh = love.thread.getChannel(OUT)
local httpCh = love.thread.getChannel(HTTP)

local cfg = inCh:demand()
local rom = inCh:demand()
local recipeBlob = inCh:demand()
local sources = inCh:demand()

-- The JIT as the main thread has it (off on phones), and never on ARM64
-- whatever it says: FMA fusion there changes the float rounding the bake
-- reproduces bit for bit (lib/bake/ARCHITECTURE.md).
if jit then
  if cfg.jit == false or jit.arch == "arm64" then jit.off() else jit.on() end
end

local function fail(code, message)
  outCh:push({ kind = "error", code = code, message = tostring(message) })
end

local function log(fmt, ...)
  local ok, text = pcall(string.format, fmt, ...)
  outCh:push({ kind = "log", text = ok and text or tostring(fmt) })
end

-- ── V: the mod's module table, over the sources we were handed ──────────
local V = { path = cfg.modPath, log = log }
local loaded = {}
function V.read(rel) return sources[rel] end
function V.require(name)
  local hit = loaded[name]
  if hit ~= nil then return hit end
  local rel = "lib/" .. name .. ".lua"
  local src = sources[rel]
  if not src then error("EMERALD_3DS_VOXEL: " .. rel .. " is missing -- reinstall the mod", 0) end
  local chunk, err = loadstring(src, "@" .. tostring(cfg.modPath) .. "/" .. rel)
  if not chunk then error(err, 0) end
  local value = chunk(V)
  loaded[name] = value
  return value
end

-- ── HTTP through the engine's transport ─────────────────────────────────
-- "curl": HostShell's own curl call, from this thread (as the self-updater's
-- worker does).  "bridge": Android's love.system.httpDownload is a JNI call
-- the main thread makes (src/update/check_worker.lua explains why), so ask
-- it and wait.  Anything else has no HTTPS client (iOS, consoles): only the
-- cache can serve those.
local HostShell
if cfg.transport == "curl" then
  local ok, chunk = pcall(love.filesystem.load, "src/core/HostShell.lua")
  if ok and chunk then
    local okRun, mod = pcall(chunk)
    if okRun then HostShell = mod end
  end
  -- an unpacked engine run from its folder (tools, harnesses) has src/ on
  -- package.path rather than in the LOVE source
  if not HostShell then
    local okReq, mod = pcall(require, "src.core.HostShell")
    if okReq then HostShell = mod end
  end
end

-- Both transports download to a FILE and read it back: HostShell.httpGet
-- pipes curl's output through a text-mode popen, which on Windows turns the
-- PNG signature's CR LF into LF.  A file is byte-exact everywhere.
local seq = 0
local function http(url)
  seq = seq + 1
  local dest = ("e3ds_voxel/cache/fetch_%d.tmp"):format(seq)
  love.filesystem.createDirectory("e3ds_voxel/cache")
  love.filesystem.remove(dest)
  if cfg.transport == "curl" then
    if not HostShell then return nil, "the engine's HostShell could not be loaded in the bake thread" end
    local okD, why = HostShell.httpDownload(url, cfg.saveDir .. "/" .. dest, cfg.userAgent)
    if not okD then love.filesystem.remove(dest); return nil, why end
  elseif cfg.transport == "bridge" then
    httpCh:clear()
    outCh:push({ kind = "http", url = url, dest = dest })
    local res = httpCh:demand(180)
    if type(res) ~= "table" then return nil, "the download did not answer in time" end
    if not res.ok then love.filesystem.remove(dest); return nil, res.err or "download failed" end
  else
    return nil, cfg.transportWhy or "no network transport on this platform"
  end
  local body = love.filesystem.read(dest)
  love.filesystem.remove(dest)
  if not body or body == "" then return nil, "empty response from " .. url end
  return body
end

local CACHE = "e3ds_voxel/cache/"
local function cachePath(key) return CACHE .. key end
local function cacheRead(key)
  local p = cachePath(key)
  if love.filesystem.getInfo(p, "file") then return love.filesystem.read(p) end
  return nil
end
local function cacheWrite(key, bytes)
  local p = cachePath(key)
  love.filesystem.createDirectory(p:match("^(.*)/[^/]*$"))
  love.filesystem.write(p, bytes)
end

-- ── progress: Bake.run's even split, re-weighted by what each part costs ──
-- Bake.run reports 0..0.1 for the input tree and then an equal share per
-- step; the relief and the buildings are nearly all of the time (about 70 s
-- and 150 s against a couple of seconds for the rest, desktop JIT).
-- (JIT off -- phones -- the relief is relatively dearer: about 225 s and
-- 305 s here.)  Both steps report through their parts (ARCHITECTURE.md
-- "Progress"), so the bar moves all the way through.
local WEIGHT = (jit and jit.status()) and
  { gen_voxel_regions = 1, gen_voxel_sign_masks = 1, gen_voxel_relief = 30, gen_voxel_buildings = 62 } or
  { gen_voxel_regions = 1, gen_voxel_sign_masks = 1, gen_voxel_relief = 42, gen_voxel_buildings = 57 }
local lastPush, lastLabel, lastF = 0, nil, -1
local function progress(f, label)
  local now = love.timer.getTime()
  if label == lastLabel and f - lastF < 0.002 and now - lastPush < 0.5 then return end
  lastPush, lastLabel, lastF = now, label, f
  outCh:push({ kind = "progress", f = f, label = label })
end

local function weighted(Bake)
  local steps = Bake.STEPS
  local weights, total = { 1 }, 1
  for i, s in ipairs(steps) do
    weights[i + 1] = WEIGHT[s.module] or 10
    total = total + weights[i + 1]
  end
  return function(f, label)
    f = math.max(0, math.min(1, tonumber(f) or 0))
    local seg, inner
    if f <= 0.1 then
      seg, inner = 1, f / 0.1
    else
      local x = (f - 0.1) / 0.9 * #steps
      local i = math.min(#steps - 1, math.floor(x))
      seg, inner = i + 2, x - i
    end
    local before = 0
    for k = 1, seg - 1 do before = before + weights[k] end
    progress(0.02 + 0.97 * (before + weights[seg] * inner) / total, label)
  end
end

-- ── the job ──────────────────────────────────────────────────────────────
local function hex(digest)
  if type(digest) ~= "string" then digest = digest:getString() end
  return love.data.encode("string", "hex", digest)
end

-- ── the outputs: streamed to .part files, renamed once all are made ─────
local DIR = "e3ds_voxel/"
local PARTIAL = cfg.partialName or "incomplete.txt"
local parts = {}          -- name -> true for every .part this bake opened

local function partPath(name) return DIR .. name .. ".part" end

local function removeParts()
  for name in pairs(parts) do pcall(love.filesystem.remove, partPath(name)) end
end

-- Bake.run's opts.open: a love File in write mode, buffered, raising on a
-- failed write (a full disk must fail the bake, not truncate a file)
local function openPart(name)
  parts[name] = true
  local path = partPath(name)
  love.filesystem.remove(path)
  local file, why = love.filesystem.newFile(path, "w")
  if not file then error(("could not write %s (%s)"):format(path, tostring(why)), 0) end
  pcall(file.setBuffer, file, "full", 256 * 1024)
  return {
    write = function(_, chunk)
      local okW, whyW = file:write(chunk)
      if not okW then
        pcall(file.close, file)
        error(("could not write %s (%s)"):format(path, tostring(whyW)), 0)
      end
    end,
    close = function()
      local okF, whyF = file:flush()
      file:close()
      if okF == false then error(("could not write %s (%s)"):format(path, tostring(whyF)), 0) end
    end,
  }
end

-- e3ds_voxel/<name>.part -> e3ds_voxel/<name>: os.rename on the real path
-- (PhysFS has no rename), else a chunked copy through love.filesystem
local function commit(name)
  local from, to = partPath(name), DIR .. name
  love.filesystem.remove(to)
  local base = love.filesystem.getRealDirectory(from) or cfg.saveDir
  if base and os.rename and os.rename(base .. "/" .. from, base .. "/" .. to) then
    parts[name] = nil
    return
  end
  local src = assert(love.filesystem.newFile(from, "r"))
  local dst = assert(love.filesystem.newFile(to, "w"))
  while true do
    local chunk = src:read(1024 * 1024)
    if not chunk or chunk == "" then break end
    local okW, why = dst:write(chunk)
    if not okW then src:close(); dst:close(); error(("could not write %s (%s)"):format(to, tostring(why)), 0) end
  end
  src:close()
  dst:close()
  love.filesystem.remove(from)
  parts[name] = nil
end

local ok, err = xpcall(function()
  local Bake = V.require("bake/Bake")
  local fetch = Bake.fetcher({ http = http, cache_read = cacheRead, cache_write = cacheWrite })

  progress(0, "Fetching Emerald 3DS's tree art")
  local trees = {}
  for _, name in ipairs(Bake.TREES) do
    local bytes, why = fetch(Bake.TREE_DIR .. name, Bake.TREE_COMMIT)
    if not bytes then error({ code = "network", message = ("could not download %s (%s)"):format(name, tostring(why)) }) end
    trees[name] = bytes
  end
  progress(0.01, "Fetching Emerald 3DS's generator data")
  for _, rel in ipairs(Bake.ASSETS) do
    local bytes, why = fetch(rel, Bake.ASSET_COMMIT)
    if not bytes then error({ code = "network", message = ("could not download %s (%s)"):format(rel, tostring(why)) }) end
  end

  local sha1 = hex(love.data.hash("sha1", rom))
  local t0 = love.timer.getTime()
  -- leftovers of a bake that died without its error handler
  for name in tostring(cfg.outputs):gmatch("[^,]+") do love.filesystem.remove(partPath(name)) end
  local job = {
    rom = rom, recipe_blob = recipeBlob,
    inflate = function(bytes) return love.data.decompress("string", "zlib", bytes) end,
    fetch = fetch, progress = weighted(Bake), open = openPart,
  }
  rom, recipeBlob = nil, nil    -- memory: Bake.run drops job.rom once read
  local sizes = Bake.run(job)
  job = nil
  log("bake finished in %.0f s", love.timer.getTime() - t0)
  for name in tostring(cfg.outputs):gmatch("[^,]+") do
    if not sizes[name] then error("the bake did not produce " .. name, 0) end
  end

  -- every output is complete in its .part.  The stamp goes first (removed)
  -- and last (written), and incomplete.txt marks the window between: a
  -- folder caught there by a crash is baked again, never taken as it is
  love.filesystem.createDirectory("e3ds_voxel/trees")
  love.filesystem.remove(DIR .. cfg.stampName)
  assert(love.filesystem.write(DIR .. PARTIAL, "an in-game bake was writing this folder\n"))
  for name, bytes in pairs(trees) do
    assert(love.filesystem.write("e3ds_voxel/trees/" .. name, bytes))
  end
  for name in tostring(cfg.outputs):gmatch("[^,]+") do commit(name) end
  collectgarbage()
  local stamp = (cfg.stamp:gsub("{rom}", sha1))
  assert(love.filesystem.write(DIR .. cfg.stampName, stamp))
  love.filesystem.remove(DIR .. PARTIAL)
  progress(1, "done")
  outCh:push({ kind = "done", rom = sha1 })
end, function(e)
  if type(e) == "table" then return e end
  return { message = tostring(e), trace = debug.traceback("", 2) }
end)

if not ok then
  removeParts()
  local message = type(err) == "table" and err.message or tostring(err)
  local code = type(err) == "table" and err.code or nil
  if not code then
    -- recipe.build_entry checks every file the ROM yields by size and CRC;
    -- vtree raises BuilderError on a ROM whose tables are not where the
    -- recipe says.  Both mean the cartridge is not the one the recipe is for.
    if message:find("CRC", 1, true) or message:find("BuilderError", 1, true)
        or message:find("RecipeError", 1, true) or message:find("size", 1, true) then
      code = "rom"
    elseif message:find("could not fetch", 1, true) then
      code = "network"
    elseif message:find("not enough memory", 1, true) then
      code = "memory"
    end
  end
  if type(err) == "table" and err.trace then log("bake failed: %s%s", message, err.trace) end
  fail(code or "bake", message)
end
