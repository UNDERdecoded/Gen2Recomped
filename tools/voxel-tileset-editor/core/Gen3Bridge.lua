-- Emerald.
--
-- A GEN 3 TILESET RECORD HAS NO ART IN IT.  No `image`, no `imageWidth`, no
-- `tilesPerRow`, no `blocks` -- it names a PAIR (`primaryKey`, `secondaryKey`)
-- whose halves live in `map_tilesets.lua` as raw 4bpp tile data, palettes and
-- metatile entries.  A Gen 1 sheet is 128x48; a Gen 3 pair composites to
-- 128x2336.  That is not a bigger version of the same thing, it is a
-- different thing, and an editor that fell back to the Gen 1 constants would
-- show 96 tiles of a 3,500-tile space and call it a tileset.
--
-- SO ASK THE MOD, AGAIN.  `lib/Gen3.lua` already re-lays a pair as an
-- ordinary 8px tile sheet -- metatile `m` quadrant `q` at synthetic tile id
-- `4m + q` -- precisely so that every pixel pass in the mod can keep reading
-- `(t % perRow) * 8`.  This file's whole job is to give that module the two
-- things it reaches for and cannot find outside the game:
--
--   1. `Game.data`.  Gen3 reads it through `require("src.core.Game")` and
--      falls back to `_G.Game` -- and says so in as many words: "a harness
--      that supplies its own is" an answer.  This is that harness.
--   2. `TileRenderer.gen3SheetsFor`.  A thin wrapper over the engine's own
--      `src/render/Gen3Tiles.lua`, which is a pure module with no requires of
--      its own -- so it is loaded from the game folder and used as-is rather
--      than reimplemented.  Compositing a pair means getting three separate
--      bank boundaries right, and palette slot 6 read from the wrong bank is
--      sixteen zero words: every wall in Littleroot black while the roofs
--      above them stay perfect.  That is not a rule to have two copies of.

local Fs = require("core.Fs")

local Gen3Bridge = {}

function Gen3Bridge.isGen3Record(ts)
  return type(ts) == "table"
     and tonumber(ts.blockTiles) == 2
     and tonumber(ts.blockCells) == 1
end

-- Load the two extra tables a Gen 3 cache carries, lazily -- map_tilesets is
-- four megabytes and no Gen 1 cache has one.
local function auxData(cache)
  if cache._gen3aux ~= nil then
    return cache._gen3aux or nil
  end
  local mt = Fs.loadLua(Fs.join(cache.root, "data/generated/map_tilesets.lua"))
  if type(mt) ~= "table" then
    cache._gen3aux = false
    cache.warnings[#cache.warnings + 1] =
      "map_tilesets.lua did not load -- Gen 3 tilesets have no art to read"
    return nil
  end
  local consts = Fs.loadLua(Fs.join(cache.root, "data/generated/constants.lua"))
  cache._gen3aux = { map_tilesets = mt,
                     constants = type(consts) == "table" and consts or {} }
  return cache._gen3aux
end

-- The engine's own compositor, loaded from the game folder.  It requires
-- nothing, which is what makes borrowing it safe; if it is not there, Gen 3
-- degrades to "geometry, no texture" rather than to a broken editor.
local gen3TilesModule = nil
local function loadGen3Tiles(gameDir)
  if gen3TilesModule ~= nil then
    return gen3TilesModule or nil
  end
  if not gameDir then gen3TilesModule = false return nil end
  local m = Fs.loadLua(Fs.join(gameDir, "src/render/Gen3Tiles.lua"))
  gen3TilesModule = (type(m) == "table" and m.new) and m or false
  return gen3TilesModule or nil
end

-- Install the harness.  Idempotent, and scoped to one cache: switching
-- cartridges re-points `Game.data` rather than stacking a second one, which
-- is the mistake the engine's own CacheFs shim made once.
function Gen3Bridge.install(cache, gameDir, bridge)
  local aux = auxData(cache)
  if not aux then return false, "no map_tilesets.lua in this cache" end
  local Gen3Tiles = loadGen3Tiles(gameDir)
  if not Gen3Tiles then
    return false, "src/render/Gen3Tiles.lua not found beside the game"
  end

  local data = {
    tilesets = cache.tilesets,
    map_tilesets = aux.map_tilesets,
    constants = aux.constants,
  }
  -- maps is the biggest file in the cache; hand it over only if something
  -- has already paid to load it
  if cache._maps and cache._maps ~= false then data.maps = cache._maps end

  local existing = rawget(_G, "Game")
  if type(existing) == "table" then
    existing.data = data
  else
    rawset(_G, "Game", { data = data })
  end

  -- REGISTER THE REAL COMPOSITOR UNDER ITS ENGINE NAME.  Gen3's fallback path
  -- does `require("src.render.Gen3Tiles")` itself, and the stub searcher would
  -- hand it an empty table -- whose `.new` is nil, which fails inside a pcall
  -- and reports as "Gen3Tiles.new failed: nil", i.e. as a broken cartridge.
  package.loaded["src.render.Gen3Tiles"] = Gen3Tiles

  -- The one engine function Gen3 needs and the stub searcher cannot fake.
  -- Registered in package.loaded so the mod's own `require` finds it.
  local sheets = {}
  local TileRenderer = package.loaded["src.render.TileRenderer"]
  if type(TileRenderer) ~= "table" then TileRenderer = {} end
  TileRenderer.gen3SheetsFor = function(tilesetDef, d, layout)
    if not Gen3Bridge.isGen3Record(tilesetDef) then return nil end
    local key = tostring(tilesetDef.id)
    local hit = sheets[key]
    if hit ~= nil then return hit or nil end
    sheets[key] = false
    local store = (d and d.map_tilesets) or aux.map_tilesets
    local primary = store and store[tilesetDef.primaryKey]
    if not primary then return nil end
    local ok, tiles = pcall(Gen3Tiles.new, {
      primary = primary,
      secondary = tilesetDef.secondaryKey and store[tilesetDef.secondaryKey] or nil,
    }, layout or (aux.constants and aux.constants.gen3Layout))
    if not ok or not tiles then return nil end
    -- Gen3 reads only `.tiles` off this record; the two rendered sheets the
    -- engine also builds are for drawing the 2D world, which this tool does
    -- not do.
    local record = { tiles = tiles }
    sheets[key] = record
    return record
  end
  -- `defaultAnimatedTiles` is asked for by TileShape behind a pcall; answering
  -- nil is correct and keeps the pcall from being the thing that logs.
  TileRenderer.defaultAnimatedTiles = TileRenderer.defaultAnimatedTiles
      or function() return nil end
  package.loaded["src.render.TileRenderer"] = TileRenderer

  cache._gen3installed = true
  if bridge and bridge.V then
    local ok, Gen3 = pcall(bridge.V.require, "Gen3")
    if ok and type(Gen3) == "table" then
      Gen3Bridge.Gen3 = Gen3
      if Gen3.invalidate then pcall(Gen3.invalidate) end
    end
  end
  return true
end

-- The atlas geometry for a Gen 3 tileset, and the record filled in so every
-- reader that asks `tilesPerRow / imageWidth / imageHeight` -- which is all of
-- them -- gets the truth instead of the Gen 1 fallbacks.
function Gen3Bridge.geometry(ts)
  local Gen3 = Gen3Bridge.Gen3
  if not (Gen3 and Gen3.atlasInfoFor) then return nil end
  local ok, info = pcall(Gen3.atlasInfoFor, ts)
  if not (ok and type(info) == "table") then return nil end
  pcall(Gen3.describe, ts)
  return {
    perRow = info.perRow,
    atlasW = info.width,
    atlasH = info.height,
    rows = math.floor(info.height / 8),
    count = info.tiles,
    metatiles = info.metatiles,
  }
end

-- The composited sheet, as ImageData.  CPU-baked by Gen3 itself -- which
-- matters: building it through a canvas from inside a render pass runs it
-- through whatever shader is bound and yields a texture that is entirely
-- black while reporting success.
function Gen3Bridge.imageData(ts)
  local Gen3 = Gen3Bridge.Gen3
  if not (Gen3 and Gen3.atlasDataForTileset) then return nil, "Gen3 not loaded" end
  local ok, data = pcall(Gen3.atlasDataForTileset, ts)
  if not ok then return nil, tostring(data) end
  if not data then return nil, "the pair did not bake" end
  return data
end

-- The SHAPE surface: the same sheet with the ground cut out of it, so a
-- silhouette pass sees a real outline instead of a wall-to-wall opaque
-- rectangle that carves to nothing.  This is the difference between Hoenn
-- meshing as boxes and Hoenn meshing as trees and roofs.
function Gen3Bridge.shapeData(ts)
  local Gen3 = Gen3Bridge.Gen3
  if not (Gen3 and Gen3.shapeDataForTileset) then return nil end
  local ok, data = pcall(Gen3.shapeDataForTileset, ts)
  return ok and data or nil
end

-- A Gen 3 map's tile id at 8px coordinates.  A Gen 3 block IS the metatile
-- and there is no `blocks` table to index, so the id is synthesised the same
-- way the mod synthesises it -- `metatile * 4 + quadrant` -- and the two must
-- agree or the editor addresses a different sheet from the game.
function Gen3Bridge.tileId(metatile, tx, ty)
  local Gen3 = Gen3Bridge.Gen3
  if Gen3 and Gen3.tileId then return Gen3.tileId(metatile, tx, ty) end
  return (tonumber(metatile) or 0) * 4 + (ty % 2) * 2 + (tx % 2)
end

return Gen3Bridge
