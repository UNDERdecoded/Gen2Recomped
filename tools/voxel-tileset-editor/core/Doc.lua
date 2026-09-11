-- The authoring document: everything the reader has decided, and nothing
-- else.
--
-- KEPT SEPARATE FROM THE PROFILE ON PURPOSE.  The mod's own
-- data/voxel_heights.lua is 8,700 lines of someone else's decisions; the
-- document is only what THIS reader changed.  Export merges the two, and
-- keeping them apart is what makes "revert this tile" mean anything and
-- what keeps a diff of two exports about the pins rather than about
-- whitespace in a file nobody edited.
--
-- One entry per tileset id.  Every field is optional; an empty entry is
-- indistinguishable from no entry and is dropped on save.

local Serialize = require("core.Serialize")

local Doc = {}
Doc.VERSION = 1

local function entry(doc, tsId)
  local e = doc.tilesets[tsId]
  if not e then
    e = { pins = {}, folds = {}, heights = {}, cond = {}, sculpt = {},
          bands = {}, extra = {},
          groups = {}, prop_ground = {}, prop_bg = {}, buildings = {},
          notes = {} }
    doc.tilesets[tsId] = e
  end
  return e
end
Doc.entry = entry

function Doc.new()
  return {
    version = Doc.VERSION,
    name = "My Voxel Profile",
    id = "MY_VOXEL_PROFILE",
    author = "",
    modVersion = "1.0.0",
    tilesets = {},
    -- PLACE EDITS, kept apart from tile edits because they are a different
    -- kind of statement.  A tileset pin says what a DRAWING is and changes
    -- every square drawn with it; a map edit names ONE SQUARE and says how
    -- tall that is.  The runtime already ranks them that way -- a coordinate
    -- override outranks every pin in TileShape.at -- and so does this file.
    maps = {},
  }
end

local function mapEntry(doc, mapId)
  local m = doc.maps[mapId]
  if not m then
    m = { tiles = {} }
    doc.maps[mapId] = m
  end
  return m
end
Doc.mapEntry = mapEntry

-- ---------------------------------------------------------------- pins

function Doc.pin(doc, tsId, tile, class)
  local e = entry(doc, tsId)
  e.pins[tile] = class
  Doc.touch(doc)
end

function Doc.unpin(doc, tsId, tile)
  local e = entry(doc, tsId)
  e.pins[tile] = nil
  e.folds[tile] = nil
  Doc.touch(doc)
end

function Doc.setFold(doc, tsId, tile, fold)
  entry(doc, tsId).folds[tile] = fold
  Doc.touch(doc, "local")
end

-- A CLASS height: every tile of that class, everywhere it is drawn.  This is
-- the widest edit in the tool and it is easy to make by accident -- setting
-- four bridge tiles to 68 by way of `ground` moves every patch of ground on
-- the map.  `Doc.classReach` is what lets the UI say so first.
function Doc.setHeight(doc, tsId, class, h)
  local e = entry(doc, tsId)
  e.heights[class] = h
  Doc.touch(doc)
end

-- A HEIGHT FOR ONE DRAWING, without touching its class.
--
-- Expressed as a 1x1 sculpt, which is not a trick: a sculpt is already a
-- res*res field of world-pixel heights for one tile, the mesher already
-- builds a box per sub-column, and res 1 is one column covering the tile.
-- So this rides the path that already exists -- resolver overlay, sidecar,
-- pack expansion, undo -- rather than inventing a second kind of height that
-- all of those would have to learn.
--
-- It is deliberately a `local` touch: a per-tile height changes no class and
-- no pin, so nothing downstream of the PROFILE has to be rebuilt and the
-- detector does not have to measure the map again.
function Doc.setTileHeight(doc, tsId, tile, h)
  local e = entry(doc, tsId)
  if h == nil then
    e.sculpt[tile] = nil
  else
    local s = e.sculpt[tile]
    if s and s.res and s.res > 1 and s.h then
      -- keep the resolution someone sculpted at; "the whole tile is 68" is
      -- a legitimate thing to say about an 8x8 field
      for i = 1, s.res * s.res do s.h[i] = h end
    else
      e.sculpt[tile] = { res = 1, h = { h } }
    end
  end
  Doc.touch(doc, "local")
end

-- How many tiles of this tileset resolve to `class` -- what a class-height
-- edit will actually move.  `shapeOf` is the caller's resolver, so this does
-- not need to know how a class is decided.
function Doc.classReach(shapeOf, count, class)
  local n = 0
  for t = 0, (count or 0) - 1 do
    local sp = shapeOf(t)
    if sp and sp.class == class then n = n + 1 end
  end
  return n
end

-- --------------------------------------------------------- conditionals

-- A conditional pin is the same tile answering differently depending on
-- what is drawn beside it -- the counter that is a wall base where a wall
-- stands over it.  Stored the way the profile spells it so the export is a
-- copy rather than a translation.
--   { side = "above"|"below", ids = { tileid... }, rows = n, class = name }
--   { side = "cell", walkable = true|false, class = name }
function Doc.addCondition(doc, tsId, tile, rule)
  local e = entry(doc, tsId)
  local list = e.cond[tile] or {}
  list[#list + 1] = rule
  e.cond[tile] = list
  Doc.touch(doc)
end

function Doc.removeCondition(doc, tsId, tile, index)
  local e = entry(doc, tsId)
  local list = e.cond[tile]
  if not list then return end
  table.remove(list, index)
  if #list == 0 then e.cond[tile] = nil end
  Doc.touch(doc)
end

-- ------------------------------------------------------------- sculpts

-- A per-texel height map for one tile.  `res` is 1..8 sub-columns per side
-- and `h` is res*res world-pixel heights indexed j*res + i + 1, row-major
-- from the tile's TOP-LEFT -- which is the shape ChunkMesher's sub-tile
-- branch already consumes, so this is not an invention, it is the existing
-- override written down per tile instead of per coordinate.
-- `seed` is the height the tile already stands at.  Seeding with it rather
-- than with zero is the difference between "raise this one texel" and
-- "flatten the tile and then raise one texel": a sculpt states EVERY
-- sub-column, so the ones nobody touched have to start where the tile was.
function Doc.sculpt(doc, tsId, tile, res, seed)
  local e = entry(doc, tsId)
  local s = e.sculpt[tile]
  if s and (not res or s.res == res) then return s end
  res = res or 8
  seed = tonumber(seed) or 0
  local base = {}
  for i = 1, res * res do base[i] = seed end
  if s and s.res and s.h then
    -- resampling rather than discarding: someone who sculpted at 4 and
    -- then asked for 8 wants their work at 8, not a cleared tile
    for j = 0, res - 1 do
      for i = 0, res - 1 do
        local si = math.floor(i * s.res / res)
        local sj = math.floor(j * s.res / res)
        base[j * res + i + 1] = s.h[sj * s.res + si + 1] or 0
      end
    end
  end
  s = { res = res, h = base }
  e.sculpt[tile] = s
  Doc.touch(doc, "local")
  return s
end

function Doc.clearSculpt(doc, tsId, tile)
  entry(doc, tsId).sculpt[tile] = nil
  Doc.touch(doc, "local")
end

-- A brush stroke writes into an existing sculpt table in place, so nothing
-- above sees it.  Say so.
function Doc.touchSculpt(doc)
  Doc.touch(doc, "local")
end

function Doc.hasSculpt(doc, tsId, tile)
  local e = doc.tilesets[tsId]
  return e and e.sculpt and e.sculpt[tile] or nil
end

-- --------------------------------------------------------- anything else

-- THE GENERIC STORE, for profile keys this editor has no opinion about.
--
-- `Shape.mergeEntry` has always round-tripped the keys it does not model --
-- `figures`, `mounted`, `rail_face`, `bookcase_relief`, the `can_*` family,
-- `column_foot` -- so that an export never silently deletes them.  That is
-- the right behaviour and it is not editing: the reader could see those keys
-- go out of the exporter and could not change one.
--
-- `extra[key]` is the reader's answer for any such key, merged over the
-- profile's own value last.  It is deliberately untyped here -- `core/Schema.lua`
-- decides what kind of thing a key holds by looking at it, so a fork that
-- invents a key gets an editor for it with nothing to update in either file.
function Doc.setExtra(doc, tsId, key, value)
  local e = entry(doc, tsId)
  if value == nil then e.extra[key] = nil else e.extra[key] = value end
  Doc.touch(doc)
end

function Doc.extra(doc, tsId, key)
  local e = doc.tilesets and doc.tilesets[tsId]
  return e and e.extra and e.extra[key] or nil
end

-- ONE MEMBER OF A LIST-SHAPED KEY.  A tile is in it or it is not, and this
-- toggles that without the caller having to hold the whole list.  `base` is
-- the profile's own value, so removing a tile the PROFILE listed is a real
-- edit and not a no-op against an empty table.
function Doc.setListMember(doc, tsId, key, base, tile, want)
  local cur = Doc.extra(doc, tsId, key)
  local list = {}
  local seen = {}
  for _, t in ipairs(cur or base or {}) do
    if not seen[t] then seen[t] = true list[#list + 1] = t end
  end
  local out = {}
  for _, t in ipairs(list) do if t ~= tile then out[#out + 1] = t end end
  if want then out[#out + 1] = tile end
  table.sort(out)
  Doc.setExtra(doc, tsId, key, out)
end

-- ONE ENTRY OF A MAP-SHAPED KEY, same idea: seeded from the profile so a
-- change is a change rather than a fresh table that drops everything else.
function Doc.setMapMember(doc, tsId, key, base, tile, value)
  local cur = Doc.extra(doc, tsId, key)
  local out = {}
  for k, v in pairs(cur or base or {}) do out[k] = v end
  out[tile] = value
  Doc.setExtra(doc, tsId, key, out)
end

-- ----------------------------------------------------------- vocabulary

-- WHAT A CLASS MEANS, per tileset.
--
-- A class's default height is `heights[class]`, which the profile already
-- carries per tileset and the mod already reads -- so this is a real export,
-- not a preview.  Its ART MODE is not: `TileShape.CLASS_INFO` is global and
-- lives in the mod's source, not in `voxel_heights.lua`.  So changing what a
-- class LOOKS like is offered as what it actually is -- a fold set on every
-- tile of that class -- which does export, rather than as a vocabulary edit
-- that would quietly do nothing.
function Doc.classHeight(doc, tsId, class)
  local e = doc.tilesets and doc.tilesets[tsId]
  return e and e.heights and e.heights[class] or nil
end

-- ------------------------------------------------------------- band art

-- WHICH DRAWING A SIDE FACE WEARS.
--
-- A face 8 pixels tall is one BAND, and a tile raised to 40px has five of
-- them.  With no measured volume and no upright fold, every one of those
-- bands wears the tile's own drawing -- so raising a patch of grass gives
-- five bands of grass standing on end.  That is the void: real geometry with
-- no art that belongs on it.
--
-- `bands[tile]` is a sparse map from band index to the tile whose drawing
-- that band should wear.  Band -1 is the fallback: "every band that has no
-- entry of its own", which is what fills a whole wall in one click.
function Doc.setBand(doc, tsId, tile, band, src)
  local e = entry(doc, tsId)
  local b = e.bands[tile]
  if src == nil then
    if b then
      b[band] = nil
      if not next(b) then e.bands[tile] = nil end
    end
  else
    if not b then b = {} e.bands[tile] = b end
    b[band] = src
  end
  Doc.touch(doc, "local")
end

function Doc.bands(doc, tsId, tile)
  local e = doc.tilesets and doc.tilesets[tsId]
  return e and e.bands and e.bands[tile] or nil
end

function Doc.clearBands(doc, tsId, tile)
  local e = entry(doc, tsId)
  if e.bands[tile] then
    e.bands[tile] = nil
    Doc.touch(doc, "local")
  end
end

-- ------------------------------------------------------- multi-tile objects

-- A tree, a house front, a statue: several tiles that are ONE thing.  The
-- repetition cap is the whole reason this is modelled rather than pinned
-- tile by tile -- a 40-row border forest is rows of 16px trees, not one
-- 320px monolith, and the cap is what says so.
function Doc.addGroup(doc, tsId, group)
  local e = entry(doc, tsId)
  e.groups[#e.groups + 1] = group
  Doc.touch(doc)
  return group
end

-- Where else this arrangement occurs.  Not needed to make an object work --
-- the conditional pins it becomes fire everywhere on their own -- but a
-- reader who just turned four tiles into a tree wants to know whether that
-- was four tiles or four hundred.
function Doc.groupOccurrences(group, tileAt, x0, y0, x1, y1)
  local gw, gh = group.w or 0, group.h or 0
  if gw <= 0 or gh <= 0 or type(group.tiles) ~= "table" then return 0 end
  local n = 0
  for ty = y0, y1 - gh + 1 do
    for tx = x0, x1 - gw + 1 do
      local match = true
      for j = 0, gh - 1 do
        for i = 0, gw - 1 do
          if tileAt(tx + i, ty + j) ~= group.tiles[j * gw + i + 1] then
            match = false
            break
          end
        end
        if not match then break end
      end
      if match then n = n + 1 end
    end
  end
  return n
end

function Doc.removeGroup(doc, tsId, index)
  local e = entry(doc, tsId)
  table.remove(e.groups, index)
  Doc.touch(doc)
end

-- ------------------------------------------------------------- buildings

-- BUILDING TEMPLATES ARE PATCHED, NOT REWRITTEN.
--
-- A shipped template is a hand-authored claim over a specific arrangement of
-- tiles -- its roof courses, its eave, its slab, and often a `parts` list
-- naming individual panels of the drawing.  Almost none of that is something
-- a slider should be allowed to invent, and all of it is something a reader
-- may reasonably want to nudge.  So the document stores a PATCH per template
-- id: the fields it changed, over the template as shipped, with everything it
-- did not mention carried through untouched.
--
-- A patch that carries `tiles` for an id the profile does not have is a NEW
-- template instead, which is how one gets made from a selection.
function Doc.setBuilding(doc, tsId, id, patch)
  local e = entry(doc, tsId)
  e.buildings = e.buildings or {}
  if patch == nil then
    e.buildings[id] = nil
  else
    local cur = e.buildings[id] or {}
    for k, v in pairs(patch) do
      if v == false then cur[k] = nil else cur[k] = v end
    end
    cur.id = id
    e.buildings[id] = cur
  end
  Doc.touch(doc)
end

function Doc.building(doc, tsId, id)
  local e = doc.tilesets[tsId]
  return e and e.buildings and e.buildings[id] or nil
end

-- ------------------------------------------------------------ map overrides

-- One square of one map.  `patch` carries any of `art` (a class), `h`, `fold`
-- and `sub`, which is the exact shape TileShape.at reads out of
-- `map.def.voxelTileEdits["tx,ty"]` -- so this is not a format of our own, it
-- is that record, written down.
function Doc.setMapEdit(doc, mapId, tx, ty, patch)
  local m = mapEntry(doc, mapId)
  local k = tx .. "," .. ty
  if patch == nil then
    m.tiles[k] = nil
  else
    local cur = m.tiles[k] or {}
    for field, v in pairs(patch) do
      if v == false then cur[field] = nil else cur[field] = v end
    end
    if next(cur) == nil then m.tiles[k] = nil else m.tiles[k] = cur end
  end
  if next(m.tiles) == nil then doc.maps[mapId] = nil end
  Doc.touch(doc, "local")
end

function Doc.mapEdit(doc, mapId, tx, ty)
  local m = doc.maps and doc.maps[mapId]
  return m and m.tiles and m.tiles[tx .. "," .. ty] or nil
end

function Doc.clearMap(doc, mapId)
  doc.maps[mapId] = nil
  Doc.touch(doc, "local")
end

-- ------------------------------------------------------------- bookkeeping

-- TWO REVISIONS, AND THE DIFFERENCE IS WHAT MAKES SCULPTING FEEL LIVE.
--
-- A pin, a class height or a conditional changes the PROFILE, so the mod's
-- resolver has to be handed a new one and asked to re-resolve the tileset --
-- which on a Gen 3 pair is thousands of tiles.  A fold or a sculpt does not:
-- those are coordinate-style overrides, applied on top of whatever the
-- resolver already said, so they cost a cache clear and nothing else.
--
-- Bumping one counter for both meant every brush stroke re-resolved the whole
-- tileset.  It worked and it was unusable.
function Doc.touch(doc, scope)
  doc._dirty = true
  doc._rev = (doc._rev or 0) + 1
  if scope ~= "local" then
    doc._profileRev = (doc._profileRev or 0) + 1
  end
end

function Doc.isEmpty(e)
  if not e then return true end
  if next(e.pins or {}) then return false end
  if next(e.folds or {}) then return false end
  if next(e.heights or {}) then return false end
  if next(e.cond or {}) then return false end
  if next(e.sculpt or {}) then return false end
  if next(e.bands or {}) then return false end
  if next(e.extra or {}) then return false end
  if #(e.groups or {}) > 0 then return false end
  if next(e.buildings or {}) then return false end
  if next(e.prop_ground or {}) then return false end
  if #(e.prop_bg or {}) > 0 then return false end
  return true
end

-- How many decisions this document holds, for the header line.  Counted
-- rather than tracked, because a count that is maintained separately is a
-- count that goes wrong.
function Doc.stats(doc)
  local s = { tilesets = 0, pins = 0, folds = 0, cond = 0, sculpt = 0,
              groups = 0, maps = 0, places = 0, buildings = 0, bands = 0,
              extra = 0 }
  for _, m in pairs(doc.maps or {}) do
    s.maps = s.maps + 1
    for _ in pairs(m.tiles or {}) do s.places = s.places + 1 end
  end
  for _, e in pairs(doc.tilesets) do
    if not Doc.isEmpty(e) then s.tilesets = s.tilesets + 1 end
    for _ in pairs(e.pins or {}) do s.pins = s.pins + 1 end
    for _ in pairs(e.folds or {}) do s.folds = s.folds + 1 end
    for _, list in pairs(e.cond or {}) do s.cond = s.cond + #list end
    for _ in pairs(e.sculpt or {}) do s.sculpt = s.sculpt + 1 end
    for _, b in pairs(e.bands or {}) do
      for _ in pairs(b) do s.bands = s.bands + 1 end
    end
    for _ in pairs(e.extra or {}) do s.extra = s.extra + 1 end
    s.groups = s.groups + #(e.groups or {})
    for _ in pairs(e.buildings or {}) do s.buildings = s.buildings + 1 end
  end
  return s
end

function Doc.serialise(doc)
  local clean = { version = Doc.VERSION, name = doc.name, id = doc.id,
                  author = doc.author, modVersion = doc.modVersion,
                  tilesets = {}, maps = {} }
  for id, m in pairs(doc.maps or {}) do
    if next(m.tiles or {}) then clean.maps[id] = { tiles = m.tiles } end
  end
  for id, e in pairs(doc.tilesets) do
    if not Doc.isEmpty(e) then
      local c = {}
      if next(e.pins or {}) then c.pins = e.pins end
      if next(e.folds or {}) then c.folds = e.folds end
      if next(e.heights or {}) then c.heights = e.heights end
      if next(e.cond or {}) then c.cond = e.cond end
      if next(e.sculpt or {}) then c.sculpt = e.sculpt end
      if next(e.bands or {}) then c.bands = e.bands end
      if next(e.extra or {}) then c.extra = e.extra end
      if #(e.groups or {}) > 0 then c.groups = e.groups end
      if next(e.buildings or {}) then c.buildings = e.buildings end
      if next(e.prop_ground or {}) then c.prop_ground = e.prop_ground end
      if #(e.prop_bg or {}) > 0 then c.prop_bg = e.prop_bg end
      clean.tilesets[id] = c
    end
  end
  return "-- Voxel Tileset Editor authoring document.  Presentation only.\n"
      .. "return " .. Serialize.value(clean) .. "\n"
end

function Doc.adopt(loaded)
  local doc = Doc.new()
  if type(loaded) ~= "table" then return doc end
  doc.name = loaded.name or doc.name
  doc.id = loaded.id or doc.id
  doc.author = loaded.author or doc.author
  doc.modVersion = loaded.modVersion or doc.modVersion
  for id, e in pairs(loaded.tilesets or {}) do
    local t = entry(doc, id)
    t.pins = e.pins or {}
    t.folds = e.folds or {}
    t.heights = e.heights or {}
    t.cond = e.cond or {}
    t.sculpt = e.sculpt or {}
    t.bands = e.bands or {}
    t.extra = e.extra or {}
    t.groups = e.groups or {}
    t.buildings = e.buildings or {}
    t.prop_ground = e.prop_ground or {}
    t.prop_bg = e.prop_bg or {}
  end
  for id, m in pairs(loaded.maps or {}) do
    if type(m) == "table" and type(m.tiles) == "table" then
      doc.maps[id] = { tiles = m.tiles }
    end
  end
  return doc
end

return Doc
