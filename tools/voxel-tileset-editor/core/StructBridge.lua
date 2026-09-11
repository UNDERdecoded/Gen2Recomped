-- Running the mod's OWN structure detector.
--
-- WHY THIS EXISTS, AND IT IS THE GEN 3 STORY IN ONE PARAGRAPH.  TileShape
-- says what a tile IS; it does not measure anything.  On Gen 1 and Gen 2 that
-- is most of the answer, because the profile pins the drawings that matter.
-- On Gen 3 it is almost none of it: Emerald writes MB_NORMAL on the trees,
-- the houses, the roofs, the fences and the signs alike, so the behaviour
-- byte resolves the whole of Hoenn to wall, ground and water.  Everything
-- that makes a tree a tree there is `lib/Structures.lua` reading the ART --
-- and an editor that skips it shows Littleroot as a flat green plane with
-- some blobs on it, which is exactly what it did.
--
-- So load it.  Its engine surface turns out to be five functions wide:
-- `Assets.imageData`, `Assets.register`, `Map.isOutdoor`, and TileRenderer's
-- `borderBlockFor`, `voidFill` and `defaultAnimatedTiles`.  Everything else
-- it needs is a sibling in the mod's own lib/, which V.require already loads.
--
-- NOTHING HERE IS LOAD-BEARING.  Structures may be absent, may raise, or may
-- want a seam this harness has not got; any of those must leave the editor
-- drawing TileShape's own answer rather than nothing at all.  The reason is
-- kept in `StructBridge.lastError` and shown in the viewport, because "the
-- world is boxy" and "the world is boxy AND the detector did not load" are
-- different bug reports.

local Fs = require("core.Fs")

local StructBridge = {}

StructBridge.lastError = nil
StructBridge.live = false

local cacheRef = nil
local imageCache = {}

function StructBridge.setCache(cache)
  if cacheRef ~= cache then imageCache = {} end
  cacheRef = cache
end

-- The engine's asset seam, over the ROM cache this editor already reads.
-- Structures asks for one thing through it -- the tileset atlas as pixels --
-- and answers nil rather than raising when it cannot have them, which is why
-- every pixel pass in that file is gated on `if data then`.
local function imageData(path)
  if type(path) ~= "string" then return nil end
  local hit = imageCache[path]
  if hit ~= nil then return hit or nil end
  imageCache[path] = false
  if not (cacheRef and love and love.image and love.filesystem) then return nil end
  local bytes = Fs.read(Fs.join(cacheRef.root, path))
  if not bytes then return nil end
  local ok, data = pcall(function()
    local fd = love.filesystem.newFileData(bytes, Fs.basename(path))
    return love.image.newImageData(fd)
  end)
  if not ok then return nil end
  imageCache[path] = data
  return data
end

-- IS THIS MAP OUTDOORS.  The engine reads three Gen 1/Gen 2 def fields and a
-- Gen 3 def carries none of them -- but Gen 3 states the answer outright, and
-- Structures asks its own context first anyway, so this only has to be right
-- for Gen 1 and Gen 2.
local OUTDOOR_TILESETS = {
  OVERWORLD = true, FOREST = true, PLATEAU = true, SHIP_PORT = true,
  CEMETERY = true,
}
local function isOutdoor(def)
  if type(def) ~= "table" then return false end
  if type(def.outdoor) == "boolean" then return def.outdoor end
  if def.tileset and OUTDOOR_TILESETS[def.tileset] then return true end
  if def.tileset and tostring(def.tileset):find("Johto") then return true end
  if def.tileset and tostring(def.tileset):find("Kanto") then return true end
  -- environment 0 is the outdoor town/route class in the Gen 2 extraction
  return tonumber(def.environment) == 0
end

function StructBridge.install(cache, bridge)
  StructBridge.setCache(cache)

  local Assets = package.loaded["src.render.Assets"]
  if type(Assets) ~= "table" then Assets = {} end
  Assets.imageData = imageData
  Assets.image = Assets.image or function() return nil end
  Assets.register = function() end
  Assets.resolve = function(p) return p end
  Assets.exists = function() return false end
  package.loaded["src.render.Assets"] = Assets

  local Map = package.loaded["src.world.Map"]
  if type(Map) ~= "table" then Map = {} end
  Map.isOutdoor = isOutdoor
  package.loaded["src.world.Map"] = Map

  local TR = package.loaded["src.render.TileRenderer"]
  if type(TR) ~= "table" then TR = {} end
  -- BLACK VOID, NOT AN INVENTED APRON.  The engine's borderBlockFor answers
  -- with the solid tree WALL on an outdoor map rather than the map's own
  -- borderBlock -- a route's borderBlock is the grass block, and meshing that
  -- grew a twelve-tile apron of tall grass past every route edge.  This
  -- editor does not know which block that tree wall is, and guessing would
  -- put the wrong forest around every map.  `false` is the engine's own way
  -- of saying "the surround is black", which is honest: the ring is empty
  -- rather than wrong.
  TR.borderBlockFor = TR.borderBlockFor or function() return false end
  TR.voidFill = TR.voidFill or "black"
  TR.defaultAnimatedTiles = TR.defaultAnimatedTiles or function() return nil end
  package.loaded["src.render.TileRenderer"] = TR

  StructBridge.installed = true
  return true
end

-- The module, loaded once through the mod's own namespace.
function StructBridge.module(bridge)
  if StructBridge._mod ~= nil then
    return StructBridge._mod or nil
  end
  StructBridge._mod = false
  if not (bridge and bridge.live and bridge.V) then
    StructBridge.lastError = "no voxel mod loaded"
    return nil
  end
  local ok, S = pcall(bridge.V.require, "Structures")
  if not (ok and type(S) == "table" and type(S.forMap) == "function") then
    StructBridge.lastError = ok and "lib/Structures.lua is not a detector"
        or tostring(S)
    return nil
  end
  StructBridge._mod = S
  return S
end

-- Analyse one map.  Returns the S record, or nil plus the reason.
--
-- Structures memoises per map id itself, so this is a table lookup after the
-- first call -- but the FIRST call walks the whole map, which on a Hoenn
-- route is forty thousand cells.  That is a real pause and the caller says so
-- before it happens rather than after.
function StructBridge.forMap(bridge, map)
  local mod = StructBridge.module(bridge)
  if not mod then return nil, StructBridge.lastError end
  local ok, S = pcall(mod.forMap, map)
  if not (ok and type(S) == "table") then
    StructBridge.lastError = tostring(S)
    StructBridge.live = false
    return nil, StructBridge.lastError
  end
  StructBridge.live = true
  StructBridge.lastError = nil
  return S
end

function StructBridge.invalidate(bridge, mapId)
  local mod = StructBridge._mod
  if mod and mod.invalidate then pcall(mod.invalidate, mapId) end
end

-- The key Structures and ChunkMesher both index their per-tile tables by.
-- Stated here rather than assumed, because the two files agree on it
-- exactly and a third spelling would be a silent miss on every lookup.
function StructBridge.keyOf(tx, ty)
  return (ty + 64) * 4096 + (tx + 64)
end

-- WHAT ACTUALLY LOADED, said out loud.
--
-- "The structures do not seem to be loading" is not a thing anybody can
-- debug, and neither is a silent success.  Every module the detector needs,
-- every table it produced and every number it measured is reported here, so
-- the difference between "Buildings never loaded", "Buildings loaded and
-- placed nothing" and "Buildings placed forty and they are off screen" is
-- one glance instead of an afternoon.
local MODULES = { "TileShape", "Gen3", "BuildBudget", "Buildings",
                  "Structures", "ChunkMesher" }

local function count(t)
  if type(t) ~= "table" then return nil end
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

function StructBridge.report(bridge, S, extra)
  local rows = {}
  local function add(label, value, kind)
    rows[#rows + 1] = { label = label, value = tostring(value), kind = kind }
  end

  if not (bridge and bridge.live) then
    add("voxel mod", "not loaded", "bad")
    for _, w in ipairs((bridge and bridge.warnings) or {}) do
      add("", w, "warn")
    end
    return rows
  end

  add("install", tostring((bridge.roots or {})[1] or "?"))
  add("version", tostring(bridge.version or "?"))

  for _, name in ipairs(MODULES) do
    local ok, m = pcall(bridge.V.require, name)
    local got = ok and type(m) == "table"
    add("lib/" .. name, got and "loaded" or ("MISSING" ..
        ((not ok) and (" -- " .. tostring(m)) or "")),
        got and "good" or "bad")
  end

  local profile = bridge.profile
  local tsId = extra and extra.tsId
  local b = profile and profile.buildings and tsId and profile.buildings[tsId]
  add("building templates for " .. tostring(tsId),
      b and (#b .. " in the profile") or "none in the profile",
      b and "good" or "warn")

  if StructBridge.lastError then
    add("last error", StructBridge.lastError, "bad")
  end

  if not S then
    add("detector", "has not run on this map", "warn")
    return rows
  end

  add("detector", "ran", "good")
  add("resolved squares", count(S.shapeAt) or 0)
  add("measured volumes", count(S.runs) or 0,
      (count(S.runs) or 0) > 0 and "good" or "warn")
  add("object cells", count(S.skip) or 0)
  add("object quads", #(S.objectQuads or {}))
  add("round hulls", #(S.roundStamps or {}))
  add("grass quads", #(S.grassQuads or {}))
  add("flower quads", #(S.flowerQuads or {}))
  add("figures", #(S.figures or {}))
  add("gen 3", S.isGen3 and "yes" or "no")

  local okB, Buildings = pcall(bridge.V.require, "Buildings")
  if okB and type(Buildings) == "table" and Buildings.stats then
    local okS, st = pcall(Buildings.stats)
    if okS and type(st) == "table" then
      local parts = {}
      for k, v in pairs(st) do
        parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
      end
      table.sort(parts)
      add("Buildings.stats", table.concat(parts, "  "),
          #parts > 0 and "good" or "warn")
    end
  end

  return rows
end

return StructBridge
