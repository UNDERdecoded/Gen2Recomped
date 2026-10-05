-- Builds runtime Map objects (and their tile SpriteBatches) from generated
-- data, cached by map id.  The cache is keyed so a mod that patches one
-- map record after boot (or the dev-mode hot reload) can drop just that
-- entry instead of every map's SpriteBatches.
--
-- The resident set is trimmed LRU (trim) so exploring a large world never
-- holds every visited map's GPU objects at once.  Maps are built on demand
-- and cheaply: a map's tile layer draws windowed to the camera (see
-- TileRenderer), so there is no per-map batch to construct up front and thus
-- nothing to stream -- OverworldState:rebuildNeighbors just loads each
-- neighbor directly.

local Assets = require("src.render.Assets")
local Map = require("src.world.Map")
local TileRenderer = require("src.render.TileRenderer")

local MapLoader = {}

local cache = {}
-- mapId -> monotonic access stamp, for LRU eviction
local lru = {}
local accessSeq = 0
-- max map renderers kept resident.  Comfortably above the largest
-- current+neighbor set (~15 in dense overworld), so protected maps are
-- never the ones evicted; this only caps the lingering trail behind you.
local RESIDENT_CAP = 32

local TILESET_FALLBACKS = {
  TilesetPlayersHouse = { "TilesetHouse", "TilesetTraditionalHouse" },
  TilesetPlayersRoom = { "TilesetPlayersRoom", "TilesetPlayersHouse", "TilesetHouse", "TilesetTraditionalHouse" },
  HOUSE = { "TilesetTraditionalHouse", "TilesetHouse", "TilesetPlayersHouse" },
}

local function touch(mapId)
  accessSeq = accessSeq + 1
  lru[mapId] = accessSeq
end

-- The tileset a map def actually resolves to, fallback chain included, plus
-- the id it landed on.
--
-- This chain used to live only inside `build`, which meant anything else that
-- had to pair a def with a tileset -- a tool, an offline pass that meshes a
-- map without loading it -- either duplicated the table or quietly disagreed
-- with what the game would load. Disagreeing is the expensive kind of wrong:
-- work keyed on the tileset (a cached mesh, a baked atlas) is then filed
-- under a tileset the running game never asks for.
--
-- Returns nil when nothing in the chain exists, so a caller that wants to
-- skip such a map can, and `build` can keep raising.
function MapLoader.tilesetFor(data, def)
  local wanted = def and def.tileset
  local tilesets = data and data.tilesets
  if not tilesets then return nil end
  local ts = wanted and tilesets[wanted]
  if ts then return ts, wanted end
  for _, fallbackId in ipairs(TILESET_FALLBACKS[wanted] or {}) do
    ts = tilesets[fallbackId]
    if ts then return ts, fallbackId end
  end
  return nil
end

-- A MAP THAT POINTS AT A SHARED GRID INSTEAD OF CARRYING ONE.
--
-- Gen 4 splits its collision the way Gen 3 splits its layouts: a grid is built
-- once per MATRIX and a map that does not own its matrix outright references
-- it, because the 30x30 Sinnoh overworld is 921,600 cells and inlining it once
-- per building standing on it took the extraction from 4 seconds to 22.
--
-- NOTHING EVER READ THE OTHER SIDE OF THAT SPLIT.  `map_layouts` is written by
-- the Gen 4 extractor and, at run time, is only ever touched by one Gen 3
-- script command.  `Map` reads `def.blocks` and nothing else -- so **291 of
-- the 593 Gen 4 maps had no collision data at all**, which is what "collisions
-- dont seem to be correct in the overworld" is: not a wrong grid, an absent
-- one.
--
-- Resolved here rather than in `Map` because this is the one place that has
-- both the def and the dataset, and written BACK ONTO THE DEF rather than onto
-- a copy: half the engine compares `map.def` against `data.maps[id]` by
-- identity, and a copy would quietly become a second map. Idempotent, so a
-- reload costs nothing.
function MapLoader.resolveBlocks(data, def)
  if not def then return def end
  local layout = data and data.map_layouts and data.map_layouts[def.layout]
  if layout and layout.behaviorCells and not def.behaviorCells then
    local rows = {}
    for y = 0, (def.height or layout.height) - 1 do
      local at = ((def.originY or 0) + y) * layout.width + (def.originX or 0) + 1
      rows[#rows + 1] = layout.behaviorCells:sub(at, at + (def.width or layout.width) - 1)
    end
    def.behaviorCells = table.concat(rows)
  end
  if type(def.blocks) == "string" then return def end
  local source = layout and layout.blocks
  if type(source) ~= "string" then return def end

  local stride = layout.width or def.width or 0
  local rows = layout.height or def.height or 0
  local w = def.width or stride
  local h = def.height or rows
  local ox, oy = def.originX or 0, def.originY or 0
  if ox == 0 and oy == 0 and w == stride and h == rows then
    def.blocks = source
  else
    -- A region of the shared grid: take its own rows out of it.
    local out = {}
    for y = 0, h - 1 do
      local at = ((oy + y) * stride + ox) * 2
      out[#out + 1] = source:sub(at + 1, at + w * 2)
    end
    def.blocks = table.concat(out)
  end
  if def.borderBlock == nil then def.borderBlock = layout.borderBlock end
  return def
end

local function build(data, mapId)
  local def = data.maps[mapId]
  assert(def, "unknown map: " .. tostring(mapId) ..
         " (not in the maps registry)")
  MapLoader.resolveBlocks(data, def)
  -- PLATINUM'S HIDDEN PATHS, on the collision -- see Gen4HiddenPaths. Applied
  -- on every build, as the cartridge does on every map change.
  if def.generation == 4 then
    MapLoader.applyHiddenPaths(data, def)
  end
  local tilesetDef = MapLoader.tilesetFor(data, def)
  assert(tilesetDef, ("map %s wants unknown tileset: %s (not in the " ..
         "tilesets registry)"):format(tostring(mapId), tostring(def.tileset)))

  -- warp tiles are stored per tileset macro name; the generated tilesets
  -- module carries them in the tileset entry itself
  -- the Sprout Tower pillar frames are read out of the ROM with the field
  -- data, and only MapLoader sees the dataset, so hand them over here
  TileRenderer.setTileAnim(data.field and data.field.gen2TileAnim)

  local map = Map.new(def, tilesetDef)
  map.renderer = TileRenderer.new(map, data)
  cache[mapId] = map
  touch(mapId)
  return map
end

-- The save the hidden paths are read from. `Game` is required lazily: the
-- loader is used by tools that have no game.
local function currentSave()
  local ok, Game = pcall(require, "src.core.Game")
  return ok and type(Game) == "table" and Game.save or nil
end

function MapLoader.applyHiddenPaths(data, def)
  local Gen4HiddenPaths = require("src.world.Gen4HiddenPaths")
  return Gen4HiddenPaths.applyToDef(data, def, currentSave())
end

function MapLoader.load(data, mapId)
  local m = cache[mapId]
  if m then
    -- A cached overworld map built before a hidden path was unlocked (or
    -- locked) is rebuilt, so the collision matches the save -- the cartridge
    -- re-applies the patches on every map change.
    local def = m.def
    if def and def.generation == 4 and def.gen4HiddenKey then
      local Gen4HiddenPaths = require("src.world.Gen4HiddenPaths")
      if def.gen4HiddenKey ~= Gen4HiddenPaths.key(currentSave()) then
        MapLoader.evict(mapId)
        return build(data, mapId)
      end
    end
    touch(mapId); return m
  end
  return build(data, mapId)
end

-- the live instance for a map id, or nil when it has not been loaded;
-- callers that must not build a map (invalidation, tests) use this
function MapLoader.cached(mapId)
  local m = cache[mapId]
  if m then touch(mapId) end
  return m
end

-- evict one resident map, releasing its renderer's GPU objects.  Callers
-- must ensure the map is not the current map and not drawn as a connected
-- strip (nothing live may hold its renderer) -- MapLoader.trim guarantees
-- this via its `protected` set.
function MapLoader.evict(mapId)
  local m = cache[mapId]
  if not m then return false end
  cache[mapId] = nil
  lru[mapId] = nil
  local r = m.renderer
  if r and r.release then pcall(r.release, r) end
  return true
end

-- keep the resident renderer set bounded.  `protected` (mapId -> true) is
-- never evicted (the current map and everything drawn as a connected
-- strip); the rest is trimmed least-recently-used down to RESIDENT_CAP.
function MapLoader.trim(protected)
  local n = 0
  for _ in pairs(cache) do n = n + 1 end
  if n <= RESIDENT_CAP then return end
  local ids = {}
  for id in pairs(cache) do
    if not (protected and protected[id]) then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b) return (lru[a] or 0) < (lru[b] or 0) end)
  local over = n - RESIDENT_CAP
  for _, id in ipairs(ids) do
    if over <= 0 then break end
    MapLoader.evict(id)
    over = over - 1
  end
end

-- drop one map so the next load re-reads its record and rebuilds its
-- renderer.  Deliberately does NOT release the old renderer: callers
-- holding the old instance keep drawing it until they re-point themselves
-- (OverworldState re-points self.map / self.neighbors via setMap /
-- rebuildNeighbors), so releasing here would free a batch still in use.
-- The orphaned instance is reclaimed by GC; MapLoader.evict is the path
-- that releases eagerly, and it only runs on maps nothing live holds.
function MapLoader.invalidate(mapId)
  local had = cache[mapId] ~= nil
  cache[mapId] = nil
  lru[mapId] = nil
  return had
end

function MapLoader.invalidateAll()
  cache = {}
  lru = {}
end

-- kept as the pre-v2 name
MapLoader.clearCache = MapLoader.invalidateAll

-- the cached Map objects own the per-map TileRenderer instances, so a flush
-- that skipped this one would leave live SpriteBatches built from the old
-- search path (14 cache-invalidation contract, rows 1 and 3)
Assets.register(MapLoader.invalidateAll)

return MapLoader
