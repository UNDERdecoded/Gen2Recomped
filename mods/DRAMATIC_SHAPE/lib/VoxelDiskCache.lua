-- Persistent terrain-mesh cache for the Dramatic Shape voxel renderer.
--
-- OPEN WORLD is expensive the first time because every connected map has to be
-- analysed by Structures and expanded into hundreds of thousands of voxel
-- vertices. The in-memory ChunkMesher cache avoids repeating that work during
-- one session, but historically all of it disappeared when the game closed.
--
-- This module stores the FINAL unindexed six-float vertex stream produced by
-- ChunkMesher's fast FFI sink. On a later run the map can skip Structures and
-- runGeometry entirely: the cached bytes are uploaded straight into a LOVE
-- Mesh, while small auxiliary meshes (grass / flowers / furniture figures)
-- warm in the background. That makes the visible terrain arrive much sooner on
-- low-end Android hardware without changing collision or map data.
--
-- Cache validity is conservative. A lightweight signature covers the map body,
-- dimensions, tileset/border identity and the full-mesh seam masks. GEOM_REV is
-- bumped whenever this mod changes the binary vertex meaning or core meshing
-- rules. Texture/palette changes do not invalidate geometry because terrain
-- meshes sample TerrainAtlas separately at draw time.
--
-- THAT LAST SENTENCE HAS A LIMIT, AND IT COST AN AFTERNOON. A stored vertex
-- carries its UV, so what must not change is not the atlas's COLOURS but its
-- LAYOUT. Recolour a sheet and every cached mesh is still right; move where
-- tile 37 sits on it and every cached mesh now samples somewhere else. Gen 3
-- did exactly that -- a pair used to bake as a grid of 16x16 metatile cells
-- (256x656) and now bakes as an ordinary 8px tile sheet in synthetic-tile-id
-- order (128x2336) -- so every mesh written before the change draws the right
-- shape wearing a stranger's texture: rainbow banding outdoors, black
-- indoors. And it kept doing it across restarts and across three rounds of
-- fixes to the live code, because a cache is precisely the thing a rebuild
-- does not fix.
--
-- So the Gen 3 sheet geometry is part of the signature now. A layout change
-- is a cache MISS from here on and nobody has to remember to bump anything.

local V = ...
local Voxel3D = V.require("Voxel3D")
local Budget = V.require("BuildBudget")
local Gen3 = V.require("Gen3")

local Cache = {
  hits = 0,
  misses = 0,
  writes = 0,
  errors = 0,
  bytesLoaded = 0,
  bytesWritten = 0,
  lastError = nil,
}

-- r2: the Gen 3 atlas was relaid from 16x16 metatile cells to 8px tiles, which
-- changes the meaning of every stored UV. Bumped so the r1 directory is
-- ignored outright rather than half-trusted; it can be deleted at leisure.
local GEOM_REV = "dsvx-160-r3"
local DIR = "dramatic_shape_voxel_cache/" .. GEOM_REV
local FLOATS_PER_VERTEX = 6
local BYTES_PER_VERTEX = FLOATS_PER_VERTEX * 4
local CHUNK_VERTS = 65536
local writeCounter = 0

-- The recovery release disabled this module outright because a cached mesh
-- could outlive the rules that produced it: the signature below covered the
-- map BODY (tiles, size, tileset, atlas, seam masks) and nothing else, so a
-- change to how a tile is SHAPED left the old vertices on disk and the world
-- came back stale -- most visibly a tile re-pinned in the editor's voxel tab
-- still meshing as whatever it used to be.
--
-- What closes that hole is `rulesSignature`: everything outside the map body
-- that geometry depends on -- the per-tile class pins the editor writes, the
-- companion mod's live config, and a tag the host can bump for anything else
-- -- now hashes into the same key. A rules change is a cache MISS, which
-- rebuilds; it can no longer be a silent stale hit.
--
-- `RECOVERY_DISABLED` stays as a one-line kill switch: flip it back to true
-- and every path below turns into the in-memory-only behaviour of the
-- recovery release, with no other edit required.
local RECOVERY_DISABLED = false

local function optionEnabled()
  local mod = V.mod
  local options = mod and mod.options
  if not (options and type(options.get) == "function") then return true end
  local ok, value = pcall(options.get, options, "voxelDiskCache")
  if not ok or value == nil then return true end
  return not (value == false or value == 0 or value == "0"
    or value == "false" or value == "off")
end

function Cache.enabled()
  return (not RECOVERY_DISABLED) and optionEnabled()
end

local function runtimeAvailable()
  if RECOVERY_DISABLED or not optionEnabled() then return false end
  local ok, fs, graphics, data = pcall(function()
    return love and love.filesystem, love and love.graphics, love and love.data
  end)
  if not ok then return false end
  return fs and graphics and data
    and type(fs.newFile) == "function"
    and type(fs.createDirectory) == "function"
    and type(graphics.newMesh) == "function"
    and type(data.newByteData) == "function"
end

local function sanitize(value)
  value = tostring(value or "map")
  value = value:gsub("[^%w_%-%.]", "_")
  if #value > 96 then value = value:sub(1, 96) end
  return value
end

-- A 31-bit rolling hash is exact in Lua's double-number integer range and is
-- intentionally arithmetic-only so LuaJIT 5.1 needs no bit library.
local MOD = 2147483647
local function hashAdd(h, value)
  if type(value) == "string" then
    for i = 1, #value do h = (h * 65599 + value:byte(i) + 1) % MOD end
    return h
  end
  local n = tonumber(value) or 0
  n = math.floor(n * 1000 + (n >= 0 and 0.5 or -0.5))
  return (h * 65599 + (n % MOD) + 1) % MOD
end

local signatureMemo = setmetatable({}, { __mode = "k" })
local function bodySignature(map)
  local memo = signatureMemo[map]
  if memo then return memo end
  local def = map and map.def or {}
  local tw = math.max(0, (tonumber(def.width) or 0) * 4)
  local th = math.max(0, (tonumber(def.height) or 0) * 4)
  local h = 146959
  h = hashAdd(h, GEOM_REV)
  h = hashAdd(h, map and map.id or "")
  h = hashAdd(h, def.tileset or (map and map.tileset and map.tileset.id) or "")
  h = hashAdd(h, def.width or 0)
  h = hashAdd(h, def.height or 0)
  h = hashAdd(h, def.borderBlock or def.border or 0)
  -- UVs are baked into the cached vertex stream, so atlas layout belongs in
  -- the signature too. This prevents a valid-position mesh from sampling the
  -- wrong tiles after an extracted-cache/tileset layout change -- a failure
  -- that looks exactly like collision paths becoming invisible under grass.
  local ts = map and map.tileset or {}
  h = hashAdd(h, ts.tilesPerRow or 16)
  h = hashAdd(h, ts.imageWidth or 0)
  h = hashAdd(h, ts.imageHeight or 0)
  if map and type(map.tileAt) == "function" then
    for y = 0, th - 1 do
      for x = 0, tw - 1 do
        h = hashAdd(h, Gen3.tileAt(map, x, y) or -1)
        if Budget and type(Budget.tick) == "function" then Budget.tick() end
      end
    end
  end
  memo = tostring(h)
  signatureMemo[map] = memo
  return memo
end

local function maskSignature(masks)
  -- Connection tables may be iterated with pairs() upstream, so mask order is
  -- not a stable cache key. Canonicalize the rectangles before hashing them.
  local rows = {}
  for _, m in ipairs(type(masks) == "table" and masks or {}) do
    rows[#rows + 1] = table.concat({
      tostring(tonumber(m[1]) or 0), tostring(tonumber(m[2]) or 0),
      tostring(tonumber(m[3]) or 0), tostring(tonumber(m[4]) or 0),
    }, ",")
  end
  table.sort(rows)
  local h = 8191
  for _, row in ipairs(rows) do h = hashAdd(h, row) end
  return tostring(h)
end

-- Everything OUTSIDE the map body that changes what the mesher emits.
--
-- `rulesTag` is the host's own lever: ChunkMesher sets it to a string that
-- names any geometry-affecting state this module cannot see for itself, and
-- bumping it invalidates every entry at once.
Cache.rulesTag = ""

function Cache.setRulesTag(tag)
  tag = tostring(tag or "")
  if tag ~= Cache.rulesTag then
    Cache.rulesTag = tag
    signatureMemo = setmetatable({}, { __mode = "k" })
  end
end

-- The editor's per-tile class pins (`map.def.voxelClassPins`) are read live
-- by TileShape on every shape lookup, deliberately, so that re-pinning a tile
-- shows on the next frame. That is exactly why they have to be in the cache
-- key: nothing else about the map changes when a tree stops being a wall.
local function pinsSignature(map)
  local def = map and map.def
  local pins = def and def.voxelClassPins
  if type(pins) ~= "table" then return "0" end
  local rows = {}
  for tile, class in pairs(pins) do
    rows[#rows + 1] = tostring(tile) .. "=" .. tostring(class)
  end
  if #rows == 0 then return "0" end
  table.sort(rows)   -- pairs() order is not a cache key
  local h = 5381
  for _, row in ipairs(rows) do h = hashAdd(h, row) end
  return tostring(h)
end

-- The companion ceiling/flora mod publishes its live settings through this
-- global. Several of them (ceiling heights, fastchunks, flora density) change
-- geometry, so the whole table hashes in rather than a chosen few -- a config
-- key this module has not heard of must still miss rather than hit stale.
local function configSignature()
  local get = rawget(_G, "__ds_ceiling_config")
  if type(get) ~= "function" then return "0" end
  local ok, cfg = pcall(get)
  if not ok or type(cfg) ~= "table" then return "0" end
  local rows = {}
  for k, v in pairs(cfg) do
    if type(v) ~= "table" and type(v) ~= "function" then
      rows[#rows + 1] = tostring(k) .. "=" .. tostring(v)
    end
  end
  table.sort(rows)
  local h = 7919
  for _, row in ipairs(rows) do h = hashAdd(h, row) end
  return tostring(h)
end

-- The SHAPE RULES' own revision, read from lib/Structures.lua where it lives
-- beside the rules it describes. GEOM_REV below covers the binary format;
-- this covers what the geometry MEANS, and the difference cost several
-- rounds of "the fix did not land" -- it had landed, and the cache was
-- serving the world from before it.
local function shapeSignature()
  local ok, S = pcall(V.require, "Structures")
  if ok and type(S) == "table" and S.SHAPE_REV then
    return tostring(S.SHAPE_REV)
  end
  return "?"
end

local function rulesSignature(map)
  return table.concat({ pinsSignature(map), configSignature(),
    Cache.rulesTag or "", shapeSignature() }, ",")
end

-- Which slots are worth persisting, and how each one is keyed.
--
-- FULL is the mesh for a map drawn WITH its border ring: the ring is cut
-- where the bodies around it sit, so those rectangles belong in its key.
-- They used to be the maps loaded around the PLAYER, which made the key
-- depend on where the player was standing; since VoxelScene.masksFor they
-- are the map's own two-hop neighbourhood, so the key -- like the body's --
-- now depends on nothing but the map and the rules, and one entry answers
-- for the map whether it is under the player's feet or drawn beside them.
--
-- BODY is a map with no ring at all -- no masks, and therefore a key that
-- depends on nothing but the map and the rules. That stability is what makes
-- it worth prebaking: every map's body mesh can be written once, ahead of
-- time, and it is still valid when you walk in from a direction nobody
-- predicted. It is also the slot that was missing when a town stayed flat
-- until you had stood in it long enough to mesh it.
local CACHEABLE = { full = true, body = true }

-- THE ATLAS LAYOUT, for maps whose UVs depend on one this module cannot see.
-- Gen 1 and Gen 2 read their sheet off disk, and its layout is a property of
-- that file -- already covered, through the tileset id, by bodySignature. A
-- Gen 3 pair has no file: this mod bakes the sheet, and how it lays it out is
-- a decision that can change between versions while every other input stays
-- byte-identical. That is not a texture change, it is a change in what a
-- stored UV MEANS, and it belongs in the key.
local function atlasSignature(map)
  local tileset = map and map.tileset
  local ok3, G = pcall(V.require, "Gen3")
  if not (ok3 and G and tileset and G.isGen3(tileset)) then return "-" end
  local ok, info = pcall(G.describe, tileset)
  if not (ok and info) then return "g3?" end
  return table.concat({ "g3", tostring(info.perRow), tostring(info.width),
                        tostring(info.height) }, ":")
end

local function signature(map, slot, masks)
  return table.concat({ GEOM_REV, bodySignature(map), tostring(slot),
    slot == "body" and "-" or maskSignature(masks), rulesSignature(map),
    atlasSignature(map) }, "|")
end

local function paths(map, slot)
  local stem = DIR .. "/" .. sanitize(map and map.id) .. "_" .. sanitize(slot)
  return stem .. ".meta", stem .. ".terrain.bin", stem .. ".water.bin"
end

local function readAll(path)
  local ok, contents = pcall(love.filesystem.read, path)
  if not ok then return nil end
  return contents
end

local function parseMeta(text)
  if type(text) ~= "string" then return nil end
  local magic, sig, terrain, water = text:match("^(.-)\n(.-)\n(%d+)\n(%d+)\n?")
  if magic ~= "VXM2" then return nil end
  return sig, tonumber(terrain), tonumber(water)
end

local function fileSize(path)
  local ok, info = pcall(love.filesystem.getInfo, path)
  if ok and type(info) == "table" then return tonumber(info.size) or 0 end
  return 0
end

local function loadRawMesh(path, count)
  count = math.floor(tonumber(count) or 0)
  if count <= 0 then return nil, true end
  if fileSize(path) ~= count * BYTES_PER_VERTEX then
    return nil, false, "cached mesh byte count mismatch"
  end

  local okMesh, mesh = pcall(love.graphics.newMesh, Voxel3D.FORMAT, count,
    "triangles", "static")
  if not okMesh or not mesh then return nil, false, tostring(mesh) end

  local okFile, file = pcall(love.filesystem.newFile, path)
  if not okFile or not file then
    if mesh.release then pcall(mesh.release, mesh) end
    return nil, false, "could not open cached mesh"
  end
  local okOpen, opened = pcall(file.open, file, "r")
  if not okOpen or opened == false then
    if mesh.release then pcall(mesh.release, mesh) end
    return nil, false, "could not read cached mesh"
  end

  local at = 0
  local okay, err = pcall(function()
    while at < count do
      local verts = math.min(CHUNK_VERTS, count - at)
      local bytes = verts * BYTES_PER_VERTEX
      local chunk = file:read(bytes)
      if type(chunk) ~= "string" or #chunk ~= bytes then
        error("short cached mesh read")
      end
      local data = love.data.newByteData(chunk)
      mesh:setVertices(data, at + 1)
      if data.release then pcall(data.release, data) end
      at = at + verts
      if Budget and type(Budget.check) == "function" then Budget.check() end
    end
  end)
  pcall(file.close, file)
  if not okay then
    if mesh.release then pcall(mesh.release, mesh) end
    return nil, false, tostring(err)
  end
  return mesh, true
end

-- Is a VALID entry already on disk? Reads only the tiny meta file, so a
-- prebake can skip a map it has already baked without touching the vertex
-- streams -- and without the signature having to be recomputed twice, since
-- the body hash is memoised per map.
function Cache.has(map, slot, masks)
  if not runtimeAvailable() or not CACHEABLE[slot] then return false end
  local metaPath = (paths(map, slot))
  local meta = readAll(metaPath)
  if not meta then return false end
  local sig, terrainCount = parseMeta(meta)
  return sig == signature(map, slot, masks)
    and (tonumber(terrainCount) or 0) > 0
end

function Cache.load(map, slot, masks)
  if not runtimeAvailable() or not CACHEABLE[slot] then return false end
  local metaPath, terrainPath, waterPath = paths(map, slot)
  local meta = readAll(metaPath)
  if not meta then
    Cache.misses = Cache.misses + 1
    return false
  end
  local sig, terrainCount, waterCount = parseMeta(meta)
  if not sig or sig ~= signature(map, slot, masks) then
    Cache.misses = Cache.misses + 1
    return false
  end
  -- A map with no terrain vertices is never a useful cache hit. Treat a
  -- truncated/half-written entry as a miss and rebuild normally instead of
  -- letting collision continue over an invisible cached world.
  if not terrainCount or terrainCount <= 0 or waterCount == nil then
    Cache.misses = Cache.misses + 1
    return false
  end

  local terrain, okT, errT = loadRawMesh(terrainPath, terrainCount)
  if not okT then
    Cache.errors = Cache.errors + 1
    Cache.lastError = errT
    return false
  end
  local water, okW, errW = loadRawMesh(waterPath, waterCount)
  if not okW then
    if terrain and terrain.release then pcall(terrain.release, terrain) end
    Cache.errors = Cache.errors + 1
    Cache.lastError = errW
    return false
  end

  Cache.hits = Cache.hits + 1
  Cache.bytesLoaded = Cache.bytesLoaded
    + (terrainCount + waterCount) * BYTES_PER_VERTEX
  Cache.lastError = nil
  return true, terrain, water
end

local function writeText(path, text)
  local ok, result = pcall(love.filesystem.write, path, text)
  return ok and result ~= false
end

local function cacheCapBytes()
  local osName = love and love.system and love.system.getOS
    and love.system.getOS() or ""
  if osName == "Android" or osName == "iOS" then
    return 1024 * 1024 * 1024 -- 1 GiB on mobile
  end
  return 3 * 1024 * 1024 * 1024 -- 3 GiB desktop
end

-- Best-effort LRU-ish pruning using file modification time. It runs only every
-- eighth completed cache write; failure to list/stat/delete never affects the
-- renderer. Meta files are tiny, so pruning works in terrain/water pairs by
-- deleting the three files sharing a stem.
local function prune()
  if not (love.filesystem.getDirectoryItems and love.filesystem.getInfo
      and love.filesystem.remove) then return end
  local ok, items = pcall(love.filesystem.getDirectoryItems, DIR)
  if not ok or type(items) ~= "table" then return end
  local groups = {}
  local total = 0
  for _, name in ipairs(items) do
    local path = DIR .. "/" .. name
    local okInfo, info = pcall(love.filesystem.getInfo, path)
    if okInfo and info and info.type == "file" then
      local stem = name:gsub("%.terrain%.bin$", "")
                       :gsub("%.water%.bin$", "")
                       :gsub("%.meta$", "")
      local g = groups[stem] or { stem = stem, bytes = 0, time = math.huge }
      g.bytes = g.bytes + (tonumber(info.size) or 0)
      g.time = math.min(g.time, tonumber(info.modtime) or 0)
      groups[stem] = g
      total = total + (tonumber(info.size) or 0)
    end
  end
  local cap = cacheCapBytes()
  if total <= cap then return end
  local order = {}
  for _, g in pairs(groups) do order[#order + 1] = g end
  table.sort(order, function(a, b) return a.time < b.time end)
  for _, g in ipairs(order) do
    if total <= cap then break end
    for _, suffix in ipairs({ ".meta", ".terrain.bin", ".water.bin" }) do
      pcall(love.filesystem.remove, DIR .. "/" .. g.stem .. suffix)
    end
    total = total - g.bytes
  end
end

-- `terrainSink` / `waterSink` are ChunkMesher's FFI sinks. They expose
-- vertexCount() and writeRaw(path), allowing this module to stay independent
-- of FFI/cdata and keeping all native-buffer ownership inside ChunkMesher.
function Cache.store(map, slot, masks, terrainSink, waterSink)
  if not runtimeAvailable() or not CACHEABLE[slot] then return false end
  if not (terrainSink and type(terrainSink.vertexCount) == "function"
      and type(terrainSink.writeRaw) == "function") then return false end
  local terrainCount = tonumber(terrainSink:vertexCount()) or 0
  local waterCount = (waterSink and type(waterSink.vertexCount) == "function")
    and (tonumber(waterSink:vertexCount()) or 0) or 0

  local okDir = pcall(love.filesystem.createDirectory, DIR)
  if not okDir then return false end
  local metaPath, terrainPath, waterPath = paths(map, slot)
  local okT, errT = terrainSink:writeRaw(terrainPath)
  if not okT then
    Cache.errors = Cache.errors + 1
    Cache.lastError = tostring(errT)
    return false
  end
  if waterSink then
    local okW, errW = waterSink:writeRaw(waterPath)
    if not okW then
      Cache.errors = Cache.errors + 1
      Cache.lastError = tostring(errW)
      return false
    end
  elseif waterCount == 0 then
    -- Ensure a stale water file from an older geometry signature cannot be
    -- mistaken for this build; the meta count is authoritative, but removing
    -- it also keeps disk usage honest.
    pcall(love.filesystem.remove, waterPath)
  end

  local meta = table.concat({ "VXM2", signature(map, slot, masks),
    tostring(terrainCount), tostring(waterCount), "" }, "\n")
  if not writeText(metaPath, meta) then
    Cache.errors = Cache.errors + 1
    Cache.lastError = "could not write voxel cache metadata"
    return false
  end
  Cache.writes = Cache.writes + 1
  Cache.bytesWritten = Cache.bytesWritten
    + (terrainCount + waterCount) * BYTES_PER_VERTEX
  Cache.lastError = nil
  writeCounter = writeCounter + 1
  if writeCounter % 8 == 0 then pcall(prune) end
  return true
end

function Cache.clear()
  if not (love and love.filesystem and love.filesystem.getDirectoryItems
      and love.filesystem.remove) then return false end
  local ok, items = pcall(love.filesystem.getDirectoryItems, DIR)
  if not ok then return false end
  for _, name in ipairs(items or {}) do
    pcall(love.filesystem.remove, DIR .. "/" .. name)
  end
  return true
end

function Cache.status()
  return {
    enabled = Cache.enabled(),
    recoveryDisabled = RECOVERY_DISABLED,
    revision = GEOM_REV,
    hits = Cache.hits,
    misses = Cache.misses,
    writes = Cache.writes,
    errors = Cache.errors,
    bytesLoaded = Cache.bytesLoaded,
    bytesWritten = Cache.bytesWritten,
    lastError = Cache.lastError,
  }
end

return Cache
