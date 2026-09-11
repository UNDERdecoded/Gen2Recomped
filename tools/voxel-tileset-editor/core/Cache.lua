-- The ROM cache the game already wrote.
--
-- THIS EDITOR NEVER OPENS A CARTRIDGE.  It reads what the extractor put in
-- the player's own cache -- data/generated/tilesets.lua and the atlas PNGs
-- beside it -- which is the same thing the game reads and the reason a
-- profile exported from here contains no cartridge bytes at all.
--
-- A cache root is a directory holding data/generated/.  There is normally
-- more than one: the un-prefixed tree at the save root is the ACTIVE
-- cartridge, and crystal/, gold/, emerald/ beside it are ones extracted
-- before.  A tileset only exists in the cache of the cartridge it came from,
-- so all of them are offered and the tileset list is the union.

local Fs = require("core.Fs")

local Cache = {}

local function loadTable(path)
  local v, err = Fs.loadLua(path)
  if type(v) ~= "table" then return nil, err or (path .. " did not return a table") end
  return v
end

-- Open one cache root.  Returns a cache object, or nil + reason.
function Cache.open(root, version)
  local tsPath = Fs.join(root, "data/generated/tilesets.lua")
  local tilesets, err = loadTable(tsPath)
  if not tilesets then return nil, err end

  local c = {
    root = root,
    version = version or "active",
    tilesets = tilesets,
    _images = {},
    _maps = nil,
    warnings = {},
  }

  c.ids = {}
  for id in pairs(tilesets) do c.ids[#c.ids + 1] = id end
  table.sort(c.ids)

  return c
end

-- The generation a tileset record belongs to, decided by what the record
-- STATES rather than by its name.
--
-- Gen 2 stores a collision class per 16x16 cell and Gen 1 does not; Gen 3's
-- sheet is a different shape entirely (128x2336 is not a bigger 128x48, it
-- is a different sheet).  Guessing from the id string would be guessing:
-- "HOUSE" exists in both the Gen 1 and the Crystal cache.
-- ASKED OF THE RECORD, NEVER OF THE CACHE'S NAME.  The same string names
-- different things in different cartridges -- `HOUSE` is in both the Gen 1
-- and the Crystal cache -- so the test is what the record STATES.  A Gen 3
-- pair is the one that says a block is 2 tiles wide and holds a single cell;
-- a Gen 2 tileset is the one that ships a per-cell collision table; anything
-- else is Gen 1.  This is the same test the mod's own Gen3.isGen3 makes, and
-- the two must agree or the editor addresses a different sheet from the game.
function Cache.generationOf(ts)
  if type(ts) ~= "table" then return 0 end
  if tonumber(ts.blockTiles) == 2 and tonumber(ts.blockCells) == 1 then
    return 3
  end
  if ts.collision then return 2 end
  return 1
end

-- Tile geometry.  One texel is one world pixel; a tile is 8x8 of both.
function Cache.tileGeometry(ts)
  local perRow = ts.tilesPerRow or 16
  local w = ts.imageWidth or (perRow * 8)
  local h = ts.imageHeight or 48
  local rows = math.floor(h / 8)
  return {
    perRow = perRow,
    atlasW = w,
    atlasH = h,
    rows = rows,
    count = math.floor(w / 8) * rows,
  }
end

function Cache.tileOrigin(ts, tile)
  local g = Cache.tileGeometry(ts)
  return (tile % g.perRow) * 8, math.floor(tile / g.perRow) * 8
end

-- The atlas as love ImageData.  Read as BYTES and handed to love.image,
-- never as a path: the file is outside anything love.filesystem can see.
function Cache.imageData(c, ts)
  if not (ts and ts.image) then return nil, "tileset record names no image" end
  local hit = c._images[ts.image]
  if hit ~= nil then
    if hit == false then return nil, "image failed to load" end
    return hit
  end
  local path = Fs.join(c.root, ts.image)
  local bytes = Fs.read(path)
  if not bytes then
    -- the extractor writes every atlas beside the data, but a mod's
    -- overrides/ copy may be the one in use; report rather than guess
    c._images[ts.image] = false
    return nil, "missing atlas: " .. path
  end
  if not (love and love.image and love.filesystem) then
    c._images[ts.image] = false
    return nil, "no love.image"
  end
  local ok, data = pcall(function()
    local fd = love.filesystem.newFileData(bytes, Fs.basename(path))
    return love.image.newImageData(fd)
  end)
  if not ok then
    c._images[ts.image] = false
    return nil, "atlas did not decode: " .. tostring(data)
  end
  c._images[ts.image] = data
  return data
end

-- The maps table, loaded lazily -- it is the biggest file in the cache and
-- only the exporter and the context view need it.
function Cache.maps(c)
  if c._maps ~= nil then
    if c._maps == false then return nil end
    return c._maps
  end
  if not c.root then c._maps = false return nil end
  local m = loadTable(Fs.join(c.root, "data/generated/maps.lua"))
  c._maps = m or false
  if not m then
    c.warnings = c.warnings or {}
    c.warnings[#c.warnings + 1] =
      "maps.lua did not load; the map view and the map-patch export are off"
  end
  return m
end

-- Every map id drawn with this tileset, sorted.  The companion-mod export
-- needs it: a pin says what a DRAWING is, so it belongs to the tileset --
-- but the runtime reads pins off the MAP, so they have to be laid on each
-- one, and a pack that only carried the maps it happened to look at leaves
-- the same tree resolving as a wall everywhere else.
function Cache.mapsUsing(c, tilesetId)
  local maps = Cache.maps(c)
  if not maps then return {} end
  local out = {}
  for id, def in pairs(maps) do
    if type(def) == "table" and def.tileset == tilesetId then
      out[#out + 1] = id
    end
  end
  table.sort(out)
  return out
end

-- Every map in the cache, sorted, with the few fields a browser needs.
--
-- Built once and kept: maps.lua is the biggest file in a cache -- nine
-- megabytes on Emerald -- and walking it per frame to draw a list is how a
-- browser becomes the slowest thing in the program.
function Cache.mapList(c)
  if c._mapList then return c._mapList end
  local maps = Cache.maps(c)
  local out = {}
  if maps then
    for id, def in pairs(maps) do
      if type(def) == "table" and (def.width or def.blocks) then
        out[#out + 1] = {
          id = id,
          label = def.label or id,
          tileset = def.tileset,
          w = tonumber(def.width) or 0,
          h = tonumber(def.height) or 0,
          group = def.group,
          landmark = def.landmark,
        }
      end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
  end
  c._mapList = out
  return out
end

-- A map def by id, for the context view.
function Cache.map(c, id)
  local maps = Cache.maps(c)
  return maps and maps[id] or nil
end

-- The palette a tile is drawn with, when the cartridge states one.  Gen 2
-- records carry palMap (tile -> palette index) and palColors (a list of
-- four-colour palettes); Gen 1 has neither and every tile is the DMG four
-- greys.  The magic wand selects by whichever of the two this answers.
function Cache.tilePalette(ts, tile)
  if not (ts.palMap and ts.palColors) then return nil end
  local idx = ts.palMap[tile + 1] or ts.palMap[tile]
  if not idx then return nil end
  local pal = ts.palColors[idx + 1] or ts.palColors[idx]
  if type(pal) ~= "table" then return nil end
  return pal, idx
end

return Cache
