-- Asking what a tile IS.
--
-- Every answer in this file comes from the mod's own TileShape.  The
-- editor's contribution is to MERGE its authoring into the profile and hand
-- the merged table back through the same seam the mod reads its own file
-- through -- so the reader's pins are applied by the resolver's rules, in
-- the resolver's order, and a pin that would not resolve in game does not
-- resolve here either.  That is the difference between a preview and a
-- promise.
--
-- The one thing done locally is the COORDINATE OVERRIDE branch: a fold or a
-- sculpt the reader has painted onto a tile.  That is not a profile concept
-- -- the profile pins classes, not per-texel heights -- and TileShape
-- reaches it through map.def.voxelTileEdits instead.  It is applied here in
-- the same shape and the same order TileShape.at applies it, and the export
-- writes it as exactly that override.

local Classes = require("core.Classes")
local Cache = require("core.Cache")
local Grid = require("core.Grid")
local Doc = require("core.Doc")

local Shape = {}

-- Shallow-copy a table one level, so merging never writes into the mod's
-- own profile.  The values below the first level are shared and never
-- mutated: the merge only ever REPLACES a key.
local function copy(t)
  local out = {}
  if type(t) == "table" then for k, v in pairs(t) do out[k] = v end end
  return out
end

-- ------------------------------------------------------------- the merge

-- Which classes are real, for this install.  A pin naming a class the mod
-- has never heard of does not resolve and falls through -- silently, by
-- design -- so the editor asks the vocabulary rather than a hardcoded list.
function Shape.vocabulary(bridge)
  return (bridge and bridge.classInfo) or Classes.FALLBACK
end

-- Merge one tileset entry.  Everything the base entry carries that this
-- editor does not model -- figures, mounted, rail_face, bookcase_relief,
-- can_*, column_foot, buildings -- is carried through untouched, because
-- an exporter that round-trips only the keys it understands is an exporter
-- that silently deletes the rest.
function Shape.mergeEntry(base, e, vocab)
  local out = copy(base)
  if not e then return out end

  -- 1. remove every tile this document has an opinion about from the base
  --    class lists, so a re-pin moves a tile rather than listing it twice
  local claimed = {}
  for tile in pairs(e.pins or {}) do claimed[tile] = true end
  if next(claimed) then
    for class, list in pairs(out) do
      if vocab[class] and type(list) == "table" then
        local kept, changed = {}, false
        for _, t in ipairs(list) do
          if claimed[t] then changed = true else kept[#kept + 1] = t end
        end
        if changed then out[class] = (#kept > 0) and kept or nil end
      end
    end
  end

  -- 2. add this document's pins
  local byClass = {}
  for tile, class in pairs(e.pins or {}) do
    if vocab[class] then
      byClass[class] = byClass[class] or {}
      table.insert(byClass[class], tile)
    end
  end
  for class, list in pairs(byClass) do
    local merged = {}
    for _, t in ipairs(out[class] or {}) do merged[#merged + 1] = t end
    for _, t in ipairs(list) do merged[#merged + 1] = t end
    table.sort(merged)
    out[class] = merged
  end

  -- 3. per-tileset class heights
  if next(e.heights or {}) then
    local h = copy(out.heights)
    for class, v in pairs(e.heights) do
      if type(v) == "number" then h[class] = v end
    end
    out.heights = h
  end

  -- 3b. MULTI-TILE OBJECTS BECOME CONDITIONAL PINS.
  --
  -- This is what makes "these four tiles are one tree" mean something the
  -- runtime can act on.  A plain pin says "tile $2E is a canopy" everywhere
  -- it is drawn, which is wrong the moment those tiles are reused for
  -- anything else.  What the reader actually said is "tile $2E is a canopy
  -- WHEN $1E is drawn above it" -- and that is a conditional pin, which
  -- TileShape already reads, ranks above the flat pins, and applies on every
  -- map in the game without being told where to look.
  --
  -- So an object emits one rule per tile, keyed on the tile the arrangement
  -- puts next to it.  A single-row object has no neighbour to key on and
  -- falls back to a plain pin, which is the honest degradation: it is a
  -- statement about the drawing and nothing more was said.
  local gAbove, gBelow, gPins
  for _, grp in ipairs(e.groups or {}) do
    local gw, gh = tonumber(grp.w) or 0, tonumber(grp.h) or 0
    local list = grp.tiles
    if vocab[grp.class] and type(list) == "table" and #list == gw * gh
       and gw > 0 and gh > 0 then
      for j = 0, gh - 1 do
        for i = 0, gw - 1 do
          local tile = list[j * gw + i + 1]
          if type(tile) == "number" then
            if j > 0 then
              local up = list[(j - 1) * gw + i + 1]
              gAbove = gAbove or copy(out.when_above)
              gAbove[tile] = gAbove[tile] or {}
              table.insert(gAbove[tile],
                           { above = { up }, rows = 1, class = grp.class })
            elseif gh > 1 then
              local down = list[(j + 1) * gw + i + 1]
              gBelow = gBelow or copy(out.when_below)
              gBelow[tile] = gBelow[tile] or {}
              table.insert(gBelow[tile],
                           { below = { down }, rows = 1, class = grp.class })
            else
              gPins = gPins or {}
              gPins[grp.class] = gPins[grp.class] or {}
              table.insert(gPins[grp.class], tile)
            end
          end
        end
      end
    end
  end
  if gAbove then out.when_above = gAbove end
  if gBelow then out.when_below = gBelow end
  if gPins then
    for class, list in pairs(gPins) do
      local merged = {}
      for _, t in ipairs(out[class] or {}) do merged[#merged + 1] = t end
      for _, t in ipairs(list) do merged[#merged + 1] = t end
      table.sort(merged)
      out[class] = merged
    end
  end

  -- 4. conditional pins, in the profile's own spelling
  local above, below, cell
  for tile, list in pairs(e.cond or {}) do
    for _, rule in ipairs(list) do
      if vocab[rule.class] then
        if rule.side == "cell" and type(rule.walkable) == "boolean" then
          cell = cell or copy(out.when_cell)
          cell[tile] = cell[tile] or {}
          table.insert(cell[tile], { walkable = rule.walkable, class = rule.class })
        elseif rule.side == "below" and type(rule.ids) == "table" then
          below = below or copy(out.when_below)
          below[tile] = below[tile] or {}
          table.insert(below[tile], { below = rule.ids, rows = rule.rows or 1,
                                      class = rule.class })
        elseif type(rule.ids) == "table" then
          above = above or copy(out.when_above)
          above[tile] = above[tile] or {}
          table.insert(above[tile], { above = rule.ids, rows = rule.rows or 1,
                                      class = rule.class })
        end
      end
    end
  end
  if above then out.when_above = above end
  if below then out.when_below = below end
  if cell then out.when_cell = cell end

  -- 5. side tables
  if next(e.prop_ground or {}) then
    local pg = copy(out.prop_ground)
    for k, v in pairs(e.prop_ground) do pg[k] = v end
    out.prop_ground = pg
  end
  if #(e.prop_bg or {}) > 0 then
    local bg = {}
    for _, v in ipairs(out.prop_bg or {}) do bg[#bg + 1] = v end
    for _, v in ipairs(e.prop_bg) do bg[#bg + 1] = v end
    out.prop_bg = bg
  end

  -- 6. ANYTHING ELSE THE READER TOUCHED, last, so authored wins.
  --
  -- The keys above are the ones this editor models by hand.  `extra` is
  -- every OTHER key in the profile -- the ones that used to be round-tripped
  -- and untouchable.  It is written whole rather than merged field by field,
  -- because `core/Doc.lua` seeds each edit from the profile's own value and
  -- so already holds the complete answer for that key.
  --
  -- It goes last deliberately.  If the reader has said something about
  -- `when_above` through the generic path AND through the conditionals path,
  -- the generic one is the more recent statement and it stands.
  for key, value in pairs(e.extra or {}) do
    out[key] = value
  end

  return out
end

-- BUILDING TEMPLATES, merged by id.
--
-- The profile's `buildings[tilesetId]` is an ordered list of hand-authored
-- claims that `lib/Buildings.lua` stamps wherever their tile arrangement
-- occurs.  A document patch names one by id and changes the fields it
-- mentions; everything it does not mention -- the `parts` list, the `desk`,
-- the panes -- carries through exactly, because those are measurements of a
-- specific drawing and nothing in this editor is entitled to guess at them.
local function mergeBuildings(baseList, patches)
  if not next(patches or {}) then return baseList end
  local out, byId = {}, {}
  for i, t in ipairs(baseList or {}) do
    local copyT = copy(t)
    out[i] = copyT
    if t.id then byId[t.id] = copyT end
  end
  local added = {}
  for id, patch in pairs(patches) do
    local target = byId[id]
    if target then
      for k, v in pairs(patch) do
        if k ~= "id" then target[k] = v end
      end
    elseif type(patch.tiles) == "table" then
      added[#added + 1] = copy(patch)
    end
  end
  -- new templates are appended in a stable order, so two exports of the same
  -- authoring are the same file
  table.sort(added, function(a, b) return tostring(a.id) < tostring(b.id) end)
  for _, t in ipairs(added) do out[#out + 1] = t end
  return out
end

-- The whole profile, merged.  `doc` may be nil, which yields the mod's own
-- profile unchanged -- the baseline every round-trip test compares against.
function Shape.mergeProfile(bridge, doc)
  local base = (bridge and bridge.profile) or {}
  local vocab = Shape.vocabulary(bridge)
  local out = copy(base)
  out.tilesets = copy(base.tilesets)
  out.buildings = copy(base.buildings)
  if doc then
    for id, e in pairs(doc.tilesets or {}) do
      if not Doc.isEmpty(e) then
        out.tilesets[id] = Shape.mergeEntry(base.tilesets and base.tilesets[id],
                                            e, vocab)
        if next(e.buildings or {}) then
          out.buildings[id] = mergeBuildings(out.buildings[id], e.buildings)
        end
      end
    end
  end
  return out
end

-- ------------------------------------------------------------- the resolver

-- The smallest map TileShape.forMap will answer for.  It reads the tileset
-- record and, on Gen 1, the map's own water and walkable sets -- so those
-- come off the tileset record too, which is where the extractor put them.
local function baseSets(ts, tsId)
  local water, walk = {}, {}
  for _, t in ipairs(ts.waterTiles or {}) do water[t] = true end
  for _, t in ipairs(ts.walkable or {}) do walk[t] = true end
  return { id = "__editor__" .. tostring(tsId), tileset = ts,
           waterTiles = water, walkable = walk }
end

local Resolver = {}
Resolver.__index = Resolver

function Shape.newResolver(bridge, ts, tsId, doc)
  local r = setmetatable({
    bridge = bridge, ts = ts, tsId = tsId, doc = doc,
    geom = Cache.tileGeometry(ts),
    vocab = Shape.vocabulary(bridge),
    rev = doc and doc._profileRev or 0,
    warnings = {},
  }, Resolver)
  r.base = baseSets(ts, tsId)
  r.map = {
    id = r.base.id, def = {}, tileset = ts,
    waterTiles = r.base.waterTiles, walkable = r.base.walkable,
  }
  r:rebuild()
  return r
end

function Resolver:rebuild()
  local b = self.bridge
  self.shapes = nil
  if not (b and b.live and b.V and b.TileShape) then return end

  local merged = Shape.mergeProfile(b, self.doc)
  local ok, err = pcall(function()
    b.V.setData("voxel_heights", merged)
    b.TileShape.invalidate()
    self.shapes = b.TileShape.forMap(self.map)
  end)
  if not ok then
    self.warnings[#self.warnings + 1] = "forMap failed: " .. tostring(err)
    self.shapes = nil
  end
  self.mergedProfile = merged
end

-- Only a PROFILE change costs a rebuild.  A fold or a sculpt is applied by
-- `applyOverrides` on the way out, so it needs the caller's shape cache
-- dropped and nothing more -- see Doc.touch.
function Resolver:syncTo(doc)
  self.doc = doc
  if doc and (doc._profileRev or 0) ~= self.rev then
    self.rev = doc._profileRev or 0
    self:rebuild()
    return true
  end
  return false
end

-- The fallback answer, used only when no mod is installed.  It is the
-- profile's resolution order with the parts that need a map left out, and
-- it is deliberately worse than the real thing -- an editor that guessed
-- convincingly would be an editor you could not tell was guessing.
function Resolver:fallbackTile(tile)
  local e = self.doc and self.doc.tilesets[self.tsId]
  local class = e and e.pins and e.pins[tile]
  if not class then
    local ts = self.ts
    for _, t in ipairs(ts.waterTiles or {}) do
      if t == tile then class = "water" break end
    end
  end
  if not class then
    for _, t in ipairs(self.ts.walkable or {}) do
      if t == tile then class = "ground" break end
    end
  end
  class = class or "wall"
  local info = self.vocab[class] or Classes.FALLBACK[class] or { h = 16, art = "upright" }
  local h = info.h
  if e and e.heights and e.heights[class] then h = e.heights[class] end
  return { class = class, h = h, art = info.art, flat = info.art == "flat",
           authored = (e and e.pins and e.pins[tile]) ~= nil, guessed = true }
end

-- Apply the reader's coordinate-style overrides -- a fold, a sculpt -- in
-- the same shape and order TileShape.at does.  A fold changes HOW the art
-- is worn without changing what the square is; `flat` follows the fold when
-- one is stated, because a shape claiming to be flat while folding upright
-- is two answers to one question.
function Resolver:applyOverrides(rec, tile)
  local e = self.doc and self.doc.tilesets[self.tsId]
  if not e then return rec end
  local fold = e.folds and e.folds[tile]
  local sculpt = e.sculpt and e.sculpt[tile]
  if not (fold or sculpt) then return rec end
  local out = {
    class = rec.class, h = rec.h, art = fold or rec.art,
    flat = fold and (fold == "flat") or (not fold and rec.flat) or false,
    authored = true,
    override = fold ~= nil or nil,
    sub = sculpt and { res = sculpt.res, h = sculpt.h } or nil,
    source = rec.source,
  }
  if fold then out.source = "editor fold" end
  if sculpt then out.source = (out.source or rec.source or "") .. " + sculpt" end
  return out
end

-- What this tile is, with NO map around it.  This is the honest answer for
-- a tileset editor and it is not the whole story: a volume's height is
-- measured across a whole connected region, and one tile has no region.  The
-- UI says so rather than pretending.
function Resolver:tile(tile)
  local rec
  if self.shapes then
    rec = self.shapes[tile]
    if rec then
      rec = { class = rec.class, h = rec.h, art = rec.art, flat = rec.flat,
              authored = rec.authored,
              source = rec.authored and "profile pin" or "derived default" }
    end
  end
  if not rec then rec = self:fallbackTile(tile) end
  return self:applyOverrides(rec, tile)
end

-- The full answer, for a tile sitting in a grid.  `grid` supplies the
-- neighbours; everything else TileShape.at reaches for is answered by the
-- synthetic map.  This is the path the context view uses, and it is where
-- conditional pins and the walkable/water cell rules actually fire.
-- A PLACE EDIT OUTRANKS EVERYTHING, which is the runtime's own order: in
-- TileShape.at a coordinate override is read before the tile-id pins, before
-- the conditionals and before the cell rules, because it is somebody pointing
-- at one square and saying what it is.  Applied here in the same shape and
-- the same order, so what the editor shows is what a pack carrying these
-- edits will draw.
function Resolver:placeEdit(grid, tx, ty)
  if not (self.doc and grid and grid.mapId) then return nil end
  local m = self.doc.maps and self.doc.maps[grid.mapId]
  if not m then return nil end
  return m.tiles and m.tiles[tx .. "," .. ty] or nil
end

function Resolver:applyPlace(rec, o)
  if not o then return rec end
  local vocab = self.vocab
  local base = o.art and vocab[o.art]
  return {
    class = o.art or (rec and rec.class) or "wall",
    h = o.h or (base and base.h) or (rec and rec.h) or 0,
    art = o.fold or (base and base.art) or (rec and rec.art) or "upright",
    flat = (o.fold ~= nil) and (o.fold == "flat")
           or ((o.fold == nil) and ((base and base.art == "flat")
                                    or (rec and rec.flat) or false)),
    authored = true,
    override = true,
    sub = (type(o.sub) == "table" and o.sub.res and o.sub.h) and o.sub or nil,
    source = "place override",
  }
end

-- DID *THIS DOCUMENT* SAY SOMETHING ABOUT THIS DRAWING?
--
-- Not the same question as `authored`, which is true of any pin in the MERGED
-- profile -- and the merged profile contains the mod's own `voxel_heights`
-- pins, which cover most of a tileset.  Answering "should the editor's word
-- beat the detector here" with `authored` would mean the detector never wins
-- anywhere, and a town of measured houses collapses back into per-tile slabs.
-- This is only what the reader has stated in this session's document.
-- The band art the reader has named for this drawing, if any.  Kept off the
-- shape record itself: a shape is what a square IS, and band art is what its
-- exposed faces WEAR -- the mesher takes it as a separate argument and the
-- resolver has no opinion about it.
function Resolver:bandsFor(tile)
  local e = self.doc and self.tsId and self.doc.tilesets[self.tsId]
  return e and e.bands and e.bands[tile] or nil
end

function Resolver:edited(tile)
  local e = self.doc and self.tsId and self.doc.tilesets[self.tsId]
  if not e or tile == nil then return false end
  if e.pins and e.pins[tile] ~= nil then return true end
  if e.folds and e.folds[tile] ~= nil then return true end
  if e.sculpt and e.sculpt[tile] ~= nil then return true end
  if e.bands and e.bands[tile] ~= nil then return true end
  return false
end

-- BIND THE GRID, AND KEEP ONE MAP OBJECT PER MAP.
--
-- Two reasons, and both are Gen 3's.  First, `TileShape.forMap` and
-- `Gen3.forMap` both want the REAL map def -- Gen 3 answers per cell out of
-- the def's own elevation and collision arrays, and against the empty def a
-- tileset-only stub carries, every one of those answers is nil and the whole
-- of Hoenn resolves to flat ground.  Second, `Gen3.forMap` memoises its
-- context by the map TABLE, so handing it a fresh table per window pan would
-- rebuild that context on every keypress and leak the old ones.
--
-- So: one proxy per map, reading whichever grid is current.
function Resolver:setGrid(grid)
  self.grid = grid
  local def = grid and grid.def or nil
  local mapId = grid and grid.mapId or nil
  if self.map and self.boundDef == def and self.boundMapId == mapId then
    return self.map
  end
  self.boundDef, self.boundMapId = def, mapId

  local base = self.base
  local me = self
  local gen3 = Cache.generationOf(self.ts) == 3
  local reader = def and Grid.mapReader(def, self.ts, gen3) or nil
  local map = {
    id = mapId or ("__editor__" .. tostring(self.tsId)),
    def = def or {},
    tileset = self.ts,
    doorTiles = self.ts.doorTiles,
    waterTiles = base.waterTiles,
    walkable = base.walkable,
    widthCells = def and (tonumber(def.width) or 0)
                 * ((self.ts.blockTiles or 4) / 2) or nil,
    heightCells = def and (tonumber(def.height) or 0)
                  * ((self.ts.blockTiles or 4) / 2) or nil,
  }
  function map:tileAt(x, y)
    if reader then return reader.tileAt(x, y) end
    return me.grid and me.grid:tileAt(x, y) or 0
  end
  function map:blockAt(cx, cy)
    if reader then return reader.metatileAt(cx, cy) end
    local t = me.grid and me.grid:tileAt(cx * 2, cy * 2)
    return t and math.floor(t / 4) or 0
  end
  function map:isWalkableCell(cx, cy)
    local t = self:tileAt(cx * 2, cy * 2 + 1)
    return base.walkable[t] and true or false
  end
  function map:isWaterCell(cx, cy)
    local t = self:tileAt(cx * 2, cy * 2 + 1)
    return base.waterTiles[t] and true or false
  end
  function map:cellTile(cx, cy)
    if reader then return reader.cellCollision(cx, cy) end
    local g = me.grid
    return g and g.coll[cx .. "," .. cy] or nil
  end
  function map:isGrassCell() return false end
  function map:warpAtCell() return false end

  self.map = map
  -- the shape table is per TILESET, but it carries the Gen 3 id space, so it
  -- is rebuilt against the map that will be asked
  self:rebuild()
  return map
end

-- The reader's own overrides, applied on top of a shape somebody else
-- resolved.  Used when the detector has already answered: its `shapeAt` is
-- TileShape's answer plus everything Structures measured, so re-deriving it
-- here would be slower AND could disagree.
function Resolver:overlay(grid, tx, ty, rec)
  if not rec then return nil end
  local tile = grid and grid:tileAt(tx, ty)
  local out = rec
  if tile then out = self:applyOverrides(rec, tile) end
  local place = self:placeEdit(grid, tx, ty)
  if place then out = self:applyPlace(out, place) end
  return out
end

function Resolver:atGrid(grid, tx, ty)
  local tile = grid:tileAt(tx, ty)
  if tile == nil then return nil end
  local place = self:placeEdit(grid, tx, ty)
  self:setGrid(grid)
  local b = self.bridge
  if not (self.shapes and b and b.live) then
    local rec = self:applyOverrides(self:fallbackTile(tile), tile)
    return place and self:applyPlace(rec, place) or rec
  end
  local ok, rec = pcall(b.TileShape.at, self.map, self.shapes, tile, tx, ty)
  if not ok or not rec then
    local f = self:applyOverrides(self:fallbackTile(tile), tile)
    return place and self:applyPlace(f, place) or f
  end
  local out = { class = rec.class, h = rec.h, art = rec.art, flat = rec.flat,
                authored = rec.authored, override = rec.override,
                sub = rec.sub,
                source = rec.override and "coordinate override"
                      or rec.authored and "pin" or "cell rule" }
  out = self:applyOverrides(out, tile)
  return place and self:applyPlace(out, place) or out
end

return Shape
