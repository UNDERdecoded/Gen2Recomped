-- THE GEN 4 TERRAIN PALETTE -- what there is to paint with on a map that has
-- no tileset.
--
-- Reported: *"the map painter tiles arent working at all for platinum nothing
-- shows"*, and then *"since gen4 doesnt have a tileset we need a way to paint
-- terrain textures too"*.
--
-- The empty palette was CORRECT, and that is the interesting part.
-- `Tiles.blockCount` answers 0 for a map whose tileset is `standIn`, and the
-- comment there says why: the stand-in reports `metatileCount = 256` and has no
-- `blocks` table at all, so the palette used to offer 256 swatches of
-- synthesised checkerboard. Painting one would have written a block id into a
-- map whose picture is an NSBMD mesh that never reads block ids -- a palette
-- full of brushes that do nothing. Answering 0 was the honest fix for that.
--
-- But 0 is not the honest answer to "what can I paint on a Sinnoh map". The
-- answer is the BEHAVIOUR byte: grass, water, a ledge, a cave floor, a bike
-- slope. It is per cell, the engine already reads it (`Map:behaviourAt`), the
-- cartridge's own names for all 256 values are extracted, and the editor's
-- stand-in artwork is ALREADY keyed on it -- `Gen4Tileset.classOf` gives every
-- behaviour a terrain class and every class a colour. So the palette, the
-- swatches and the labels all exist; nothing was wired to them.
--
-- WHAT THIS MODULE IS. The catalogue and the reader. The writer is
-- `MapEdits.writeTerrainCell`, which is deliberately elsewhere: it has to keep
-- two arrays agreeing and that is a store concern, not a palette concern.
--
-- MEASURED, not assumed (593 maps in the Platinum cache, 813,056 cells):
--   * 108 of the 256 behaviour names are real; the other 148 are `UNUSED_xNN`
--     and are not offered, because a palette entry nobody can explain is a
--     brush nobody should reach for.
--   * 94 distinct behaviours actually occur on the cartridge. The 14 offered
--     but unused are real named behaviours on maps Platinum does not use them
--     on, so they stay: a map maker may want a puddle where Sinnoh has none.
--   * `Gen4Maps.COLLISION` (0x8000) is set on exactly ZERO of those cells.

local Gen4Terrain = {}

local Behaviors = require("src.import.Gen4Behaviors")
local Tileset = require("src.import.Gen4Tileset")

-- A behaviour the cartridge does not name is not offered. `UNUSED_xNN` is the
-- extractor's own placeholder for a slot with no name in the ROM, so the test
-- is the prefix and not a hand-kept list -- 148 entries is far too many to
-- keep by hand, and a list would go stale the moment the extractor named one.
function Gen4Terrain.offers(behaviour)
  local name = Behaviors.name(behaviour)
  if type(name) ~= "string" or name == "" then return false end
  return not name:match("^UNUSED")
end

-- The label, which is the cartridge's own name with the underscores softened.
-- Kept close to the original on purpose: a map maker who looks up
-- `MUD_WITH_GRASS` in pokeplatinum has to find the same string.
function Gen4Terrain.label(behaviour)
  local name = Behaviors.name(behaviour)
  if type(name) ~= "string" or name == "" then
    return string.format("0x%02X", tonumber(behaviour) or 0)
  end
  return name
end

-- The class colour, as the three floats love.graphics wants. This is the SAME
-- colour the stand-in artwork draws the cell in, which is the whole point: the
-- swatch you pick and the square that appears are the same colour by
-- construction rather than by two tables agreeing.
function Gen4Terrain.colorOf(behaviour)
  local class = Tileset.classOf(behaviour)
  local c = (class and class.color) or { 226, 64, 200 }
  return c[1] / 255, c[2] / 255, c[3] / 255
end

function Gen4Terrain.classOf(behaviour)
  return Tileset.classOf(behaviour)
end

-- The palette, grouped by terrain class and in `Gen4Tileset.CLASSES` order --
-- ground, grass, water, shallow, sand, snow, mud, ice, cave, door, ledge,
-- bridge, stairs, blocked, unknown. That order is roughly "most to least
-- ground-like", which is the order a painter reaches for them in, and it comes
-- from the art table rather than being re-stated here so the swatch order and
-- the colour order cannot drift apart.
--
-- Built once. 256 `classOf` calls each walk a name table, and this is read on
-- every frame the palette is open.
local groupsCache
function Gen4Terrain.groups()
  if groupsCache then return groupsCache end
  local byName, out = {}, {}
  for _, class in ipairs(Tileset.CLASSES) do
    local g = { class = class, name = class.name, entries = {} }
    byName[class.name] = g
    out[#out + 1] = g
  end
  for behaviour = 0, 255 do
    if Gen4Terrain.offers(behaviour) then
      local class = Tileset.classOf(behaviour)
      local g = class and byName[class.name]
      if g then
        g.entries[#g.entries + 1] =
          { behaviour = behaviour, label = Gen4Terrain.label(behaviour) }
      end
    end
  end
  -- A class with nothing in it is not drawn. None are empty today; the guard is
  -- here because an extractor that renames a family would empty one, and a
  -- heading over no swatches reads as a palette that failed to load.
  local kept = {}
  for _, g in ipairs(out) do
    if #g.entries > 0 then kept[#kept + 1] = g end
  end
  groupsCache = kept
  return kept
end

-- The flat ordered list, same order as the groups. For anything that wants
-- "the next brush" without caring which heading it sits under.
local flatCache
function Gen4Terrain.entries()
  if flatCache then return flatCache end
  local out = {}
  for _, g in ipairs(Gen4Terrain.groups()) do
    for _, e in ipairs(g.entries) do
      out[#out + 1] = { behaviour = e.behaviour, label = e.label, class = g.name }
    end
  end
  flatCache = out
  return out
end

-- Does this map paint terrain this way? Keyed on the behaviour array rather
-- than on the generation number, because that array is what the painter writes
-- and a cache imported before the terrain stage is a Gen 4 map WITHOUT one.
-- Asking the generation would offer a brush that cannot write.
function Gen4Terrain.appliesTo(def)
  return type(def) == "table"
     and type(def.behaviorCells) == "string"
     and type(def.blocks) == "string"
     and (def.width or 0) > 0 and (def.height or 0) > 0
     and #def.behaviorCells >= def.width * def.height
end

-- behaviour, blocked -- the two halves of a cell, read the way the cartridge
-- records them. See `MapEdits.writeTerrainCell` for the measured invariant.
function Gen4Terrain.readCell(def, cx, cy)
  if not Gen4Terrain.appliesTo(def) then return nil end
  cx, cy = math.floor(cx or -1), math.floor(cy or -1)
  if cx < 0 or cy < 0 or cx >= def.width or cy >= def.height then return nil end
  local i = cy * def.width + cx + 1
  local behaviour = def.behaviorCells:byte(i)
  local at = (i - 1) * 2 + 1
  local a, b = def.blocks:byte(at, at + 1)
  if not (behaviour and b) then return nil end
  return behaviour, (a + b * 256) % 1024 == 255
end

-- WHAT IS ALREADY ON THIS MAP, most-used first.
--
-- The palette is 108 entries and a given map uses a handful -- Twinleaf Town
-- uses five. A "on this map" row above the full list is the difference between
-- picking a brush and hunting for one, and it is one pass over an array the
-- editor has already loaded.
function Gen4Terrain.usedIn(def)
  if not Gen4Terrain.appliesTo(def) then return {} end
  local hist = {}
  for i = 1, def.width * def.height do
    local b = def.behaviorCells:byte(i)
    if b then hist[b] = (hist[b] or 0) + 1 end
  end
  local out = {}
  for b, n in pairs(hist) do
    -- Offered or not: a behaviour the cartridge PUT on this map is worth
    -- showing even when it has no name, because the map maker can see it and
    -- will want to know what it is. This is the one place an `UNUSED` entry
    -- earns a swatch -- it is not a brush being recommended, it is a report.
    out[#out + 1] = { behaviour = b, count = n, label = Gen4Terrain.label(b),
                      named = Gen4Terrain.offers(b) }
  end
  table.sort(out, function(p, q)
    if p.count ~= q.count then return p.count > q.count end
    return p.behaviour < q.behaviour
  end)
  return out
end

-- ---------------------------------------------------------------- TEXTURES
--
-- The pictures a cell's ground can be painted with.
--
-- `gen4_terrain.sets` is 74 texture sets holding 1,150 distinct textures, each
-- a record of `{ texture, path, width, height, palette? }` -- the path is what
-- `Gen4Model` loads and the width and height are what the decal's UVs are
-- measured in, so nothing here needs deriving.
--
-- THE MAP'S OWN SET COMES FIRST, and that is the whole ordering. A route is
-- painted out of the textures its own chunks already use far more often than
-- out of the other seventy-three sets, and a flat alphabetical list of 1,150
-- would bury them.
local function terrainOf(data)
  return data and data.gen4_terrain or nil
end

function Gen4Terrain.setIdFor(data, def)
  local terrain = terrainOf(data)
  if not (terrain and terrain.maps and def) then return nil end
  local record = terrain.maps[def.sourceId or def.id] or terrain.maps[def.id]
  return record and record.texture or nil
end

-- The order a texture name is resolved in: the map's own set, then every
-- other set by id. ONE ORDER for the palette, this lookup and the renderer
-- (`Gen4Ground:textureNamed`), because a name appears in several sets with
-- different palettes -- and the lookup used to walk `pairs`, whose order is
-- not even stable between runs, so a decal could preview in one set's colours
-- and draw in another's.
function Gen4Terrain.setOrder(sets, ownSet)
  local ids = {}
  for id in pairs(sets or {}) do
    if id ~= ownSet then ids[#ids + 1] = id end
  end
  table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
  if ownSet ~= nil and sets and sets[ownSet] then table.insert(ids, 1, ownSet) end
  return ids
end

-- One texture by name, searched across every set in `setOrder`. Returns the
-- record and the set it was found in. Pass the map's `def` so its own set wins,
-- exactly as it does in the palette.
function Gen4Terrain.textureRecord(data, name, def)
  local terrain = terrainOf(data)
  if not (terrain and terrain.sets and name) then return nil end
  local ownSet = def and Gen4Terrain.setIdFor(data, def) or nil
  for _, setId in ipairs(Gen4Terrain.setOrder(terrain.sets, ownSet)) do
    local set = terrain.sets[setId]
    local rec = set and set.textures and set.textures[name]
    if rec then return rec, setId end
  end
  return nil
end

-- The palette, as a list of { texture, path, width, height, set, own }.
-- `own` marks the map's own set; those come first, then the rest by set id so
-- the order is stable between sessions.
function Gen4Terrain.textures(data, def)
  local terrain = terrainOf(data)
  if not (terrain and terrain.sets) then return {} end
  local ownSet = Gen4Terrain.setIdFor(data, def)
  local ids = Gen4Terrain.setOrder(terrain.sets, nil)

  local out, seen = {}, {}
  local function add(id, own)
    local set = terrain.sets[id]
    local names = {}
    for name in pairs((set and set.textures) or {}) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
      -- A texture name can appear in more than one set. The first wins, and
      -- because the map's own set is added first that is the copy from the
      -- set this map actually draws with -- which is the one whose palette
      -- matches the ground around it.
      if not seen[name] then
        seen[name] = true
        local rec = set.textures[name]
        out[#out + 1] = { texture = name, path = rec.path,
                          width = rec.width, height = rec.height,
                          set = id, own = own or nil }
      end
    end
  end
  if ownSet ~= nil and terrain.sets[ownSet] then add(ownSet, true) end
  for _, id in ipairs(ids) do
    if id ~= ownSet then add(id, false) end
  end
  return out
end

-- The texture painted on a cell, or nil. Reads the live def, which is where
-- `applyToMap` puts the stored edits.
function Gen4Terrain.textureAt(def, cx, cy)
  local edits = def and def.gen4TextureEdits
  if type(edits) ~= "table" then return nil end
  local v = edits[math.floor(cx) .. "," .. math.floor(cy)]
  return type(v) == "string" and v or nil
end

return Gen4Terrain
