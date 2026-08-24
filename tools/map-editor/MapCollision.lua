-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Where the player can and cannot walk, as something you can look at and change.
--
-- WHAT COLLISION ACTUALLY IS HERE, because every decision below follows from
-- it and it is not what most map formats do. There is no collision LAYER. A
-- Gen 2 map stores one block id per 32x32 block; a block carries four
-- COLLISION CLASSES, one per 16px quadrant, in its tileset -- and the tileset
-- also carries the set of classes that count as walkable. So "can the player
-- stand here" is answered three tables away from the map:
--
--   def.blocks[by * w + bx + 1]              -> a block id
--   ts.collision[blockId * 4 + q + 1]        -> that quadrant's class
--   ts.walkable[class]                       -> yes or no
--
-- (`Map:isWalkableCell` is exactly this, plus the border-block heuristic for
-- an import whose walkable list came out empty.)
--
-- WHICH MEANS EDITING ONE CELL EDITS THE TILESET, AND THE TILESET IS SHARED.
-- Thirty maps draw from TilesetJohto. Writing a new class into
-- `ts.collision[blockId * 4 + q]` would open or wall that quadrant of that
-- block on every one of them -- a fence in Violet City becoming walkable
-- because somebody opened a gap in Azalea.
--
-- So a collision edit MINTS A BLOCK, exactly as the cell art stepper and the
-- 16px tile brush do: copy the block that is there, replace one quadrant's
-- class, append it, and point the cell at the new id. The art is untouched, so
-- the map looks identical and behaves differently -- which is the whole point.
-- Three neighbours sharing the old block keep it.
--
-- WHICH CLASS TO WRITE is the only genuinely uncertain part, and it is chosen
-- from the tileset rather than invented. See `walkClass` and `blockClass`.

local MapEdits = require("tools.map-editor.MapEdits")

local MapCollision = {}

-- ---------------------------------------------------------------------------
-- reading
-- ---------------------------------------------------------------------------

function MapCollision.tilesetOf(S, def)
  def = def or (S and S.data and S.data.maps and S.data.maps[S.mapId or ""])
  local ts = def and S and S.data and S.data.tilesets
    and S.data.tilesets[def.tileset]
  return ts, def
end

-- The walkable CLASSES of a tileset, as a set.
--
-- Mirrors `Map`'s own `walkableSet`, including the awkward case it exists for:
-- a Gen 2 extraction may ship `walkable` as an indexed collision table -- one
-- byte per tile id, hundreds long, a handful of distinct values -- in which
-- case the passable entries are the INDICES whose value is zero, not the
-- values themselves. Reading it the other way marks a dozen arbitrary classes
-- walkable and the map becomes a sieve.
function MapCollision.walkableSet(ts)
  if type(ts) ~= "table" then return {} end
  local list = ts.walkable
  if type(list) ~= "table" then return {} end
  local set, count, unique = {}, 0, {}
  for _, v in ipairs(list) do
    count = count + 1
    unique[v] = true
  end
  local uniqueCount = 0
  for _ in pairs(unique) do uniqueCount = uniqueCount + 1 end
  if not ts.collision and count >= 128 and uniqueCount <= 32 then
    for i, cls in ipairs(list) do
      if cls == 0 then set[i - 1] = true end
    end
  else
    for _, t in ipairs(list) do set[t] = true end
  end
  return set
end

-- The block under a cell, and which of its four quadrants the cell is.
-- Quadrants are numbered 1..4 in NW, NE, SW, SE order, which is the order the
-- flat collision array stores them in.
function MapCollision.blockAt(def, cx, cy)
  if not (def and def.blocks and def.width and def.height) then return nil end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  local q = (cx % 2) + (cy % 2) * 2 + 1
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then
    return def.borderBlock or 0, q, bx, by, true
  end
  return def.blocks[by * def.width + bx + 1] or 0, q, bx, by, false
end

-- The collision class of one cell, read the way Map:cellTile reads it.
function MapCollision.classAt(S, cx, cy, def, ts)
  local t, d = MapCollision.tilesetOf(S, def)
  ts, def = ts or t, def or d
  if not (ts and ts.collision and def) then return nil end
  local id, q = MapCollision.blockAt(def, cx, cy)
  if id == nil then return nil end
  return ts.collision[id * 4 + q], id, q
end

-- Can the player stand on this cell?
--
-- THE BORDER-BLOCK HEURISTIC IS PART OF THE ANSWER, not a detail. An import
-- whose tileset carries no walkable list at all -- which several do -- would
-- otherwise report every cell blocked, and a collision overlay that paints a
-- whole map red says nothing about the map and everything about the import.
-- `Map` falls back to "any block that is not the border block is walkable"
-- there, and so must this, or the editor and the game disagree about the
-- ground the player is standing on.
function MapCollision.isWalkable(S, cx, cy, def, ts)
  local t, d = MapCollision.tilesetOf(S, def)
  ts, def = ts or t, def or d
  if not def then return false end
  local set = MapCollision.walkableSet(ts)
  if next(set) ~= nil then
    local cls = MapCollision.classAt(S, cx, cy, def, ts)
    return (cls ~= nil and set[cls]) and true or false
  end
  local id = MapCollision.blockAt(def, cx, cy)
  if def.borderBlock ~= nil then return id ~= def.borderBlock end
  return true
end

-- Is this map's walkability decided by classes, or by the border-block
-- fallback? The panel says which, because "paint this cell blocked" means two
-- different things and only one of them is per-cell.
function MapCollision.hasClasses(S, def)
  local ts = MapCollision.tilesetOf(S, def)
  return next(MapCollision.walkableSet(ts)) ~= nil
end

-- ---------------------------------------------------------------------------
-- which class to write
-- ---------------------------------------------------------------------------

-- CHOSEN FROM THE TILESET, NEVER INVENTED.
--
-- A collision class is an index into meaning this editor does not have: 0x00
-- is floor in most Gen 2 tilesets and there is no rule that says it must be,
-- and the classes that carry ledges, water, counters and doorways are all
-- "not walkable" while meaning entirely different things. Writing a number
-- from first principles is how a cell becomes a ledge nobody asked for.
--
-- So the walkable class is one the tileset already calls walkable, preferring
-- the one it uses MOST -- which is its ordinary floor by construction, since
-- floor is what a map is mostly made of.
function MapCollision.walkClass(S, def, ts)
  local t, d = MapCollision.tilesetOf(S, def)
  ts, def = ts or t, def or d
  local set = MapCollision.walkableSet(ts)
  if next(set) == nil then return nil end
  local tally = {}
  for _, cls in ipairs((ts and ts.collision) or {}) do
    if set[cls] then tally[cls] = (tally[cls] or 0) + 1 end
  end
  local best, bestN = nil, -1
  for cls, n in pairs(tally) do
    if n > bestN or (n == bestN and cls < best) then best, bestN = cls, n end
  end
  if best then return best end
  -- nothing in the collision table is walkable (a tileset of solid rock):
  -- fall back to the lowest class the set names, which is stable rather than
  -- arbitrary
  local low = nil
  for cls in pairs(set) do if low == nil or cls < low then low = cls end end
  return low
end

-- And the same argument for the wall: the class this tileset uses most among
-- the ones it does NOT call walkable. That is its ordinary wall, not a ledge
-- and not a doorway.
function MapCollision.blockClass(S, def, ts)
  local t, d = MapCollision.tilesetOf(S, def)
  ts, def = ts or t, def or d
  local set = MapCollision.walkableSet(ts)
  local tally = {}
  for _, cls in ipairs((ts and ts.collision) or {}) do
    if not set[cls] then tally[cls] = (tally[cls] or 0) + 1 end
  end
  local best, bestN = nil, -1
  for cls, n in pairs(tally) do
    if n > bestN or (n == bestN and cls < best) then best, bestN = cls, n end
  end
  return best
end

-- ---------------------------------------------------------------------------
-- writing
-- ---------------------------------------------------------------------------

-- Make one cell walkable or not. Returns true, or false and a reason.
--
-- MINTS RATHER THAN WRITES, for the reason in the header: the block belongs to
-- the tileset and the tileset belongs to thirty maps.
function MapCollision.set(S, cx, cy, walkable, cls)
  local ts, def = MapCollision.tilesetOf(S)
  if not (def and ts and type(ts.blocks) == "table") then
    return false, "this map has no tileset to edit"
  end
  if type(ts.collision) ~= "table" then
    return false, "this tileset carries no collision table"
  end
  local id, q, bx, by, outside = MapCollision.blockAt(def, cx, cy)
  if outside then return false, "that cell is outside the map" end
  local block = ts.blocks[id + 1]
  if not block then
    return false, "block " .. tostring(id) .. " is not in this tileset"
  end

  cls = cls or (walkable and MapCollision.walkClass(S, def, ts)
                or MapCollision.blockClass(S, def, ts))
  if cls == nil then
    return false, walkable
      and "this tileset names no walkable class to use"
      or "this tileset names no solid class to use"
  end

  local cur = ts.collision[id * 4 + q]
  if cur == cls then return false, "that cell is already like that" end

  -- The ART IS COPIED UNCHANGED. A collision edit that moved the drawing would
  -- be two edits, and the one nobody asked for is the one they would notice.
  local tiles, coll = {}, {}
  for i = 1, 16 do tiles[i] = block[i] or 0 end
  for i = 1, 4 do coll[i] = ts.collision[id * 4 + i] or 0 end
  coll[q] = cls

  local store = S.mapEdits or MapEdits.load()
  S.mapEdits = store
  local game = MapCollision.gameOf(S)
  local key = MapEdits.mintBlock(store, game, def.tileset, tiles, coll)
  if not key then return false, "could not mint a block for this cell" end
  MapEdits.setBlock(store, game, S.mapId, bx, by, key)

  -- LIVE, NOW, and deduped against a block that already says this. A stroke
  -- along a wall is fifty cells wanting the same block, and appending fifty
  -- identical ones would spend a tileset's whole id space on one fence.
  local liveId = nil
  for i, existing in ipairs(ts.blocks) do
    local same = true
    for k = 1, 16 do
      if existing[k] ~= tiles[k] then same = false break end
    end
    if same then
      for j = 1, 4 do
        if (ts.collision[(i - 1) * 4 + j] or 0) ~= (coll[j] or 0) then
          same = false
          break
        end
      end
    end
    if same then liveId = i - 1 break end
  end
  if not liveId then
    local copy = {}
    for i = 1, 16 do copy[i] = tiles[i] end
    ts.blocks[#ts.blocks + 1] = copy
    liveId = #ts.blocks - 1
    for j = 1, 4 do ts.collision[liveId * 4 + j] = coll[j] end
  end
  def.blocks[by * def.width + bx + 1] = liveId

  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  return true
end

function MapCollision.toggle(S, cx, cy)
  return MapCollision.set(S, cx, cy, not MapCollision.isWalkable(S, cx, cy))
end

function MapCollision.gameOf(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring((S and S.version) or v or "unknown")
end

-- ---------------------------------------------------------------------------
-- looking at it
-- ---------------------------------------------------------------------------

-- Everything the overlay needs, computed once per (map, edit stamp) rather
-- than per frame: a route is 40x36 cells and each answer is three table
-- lookups and a set test, which is cheap once and not cheap sixty times a
-- second while panning.
--
-- Returns { w, h, walk = { [cy * w + cx] = true } }, or nil.
function MapCollision.grid(S)
  if not (S and S.mapId) then return nil end
  local ts, def = MapCollision.tilesetOf(S)
  if not def then return nil end
  local key = string.format("%s|%s", tostring(S.mapId),
                            tostring(S.mapEditsStamp or 0))
  if S._collGrid and S._collGridFor == key then return S._collGrid end
  local w, h = (def.width or 0) * 2, (def.height or 0) * 2
  local walk = {}
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      if MapCollision.isWalkable(S, cx, cy, def, ts) then
        walk[cy * w + cx] = true
      end
    end
  end
  local grid = { w = w, h = h, walk = walk,
                 classes = MapCollision.hasClasses(S, def) }
  S._collGrid, S._collGridFor = grid, key
  return grid
end

-- Count of each, for a panel that wants to say what it is showing.
function MapCollision.tally(S)
  local g = MapCollision.grid(S)
  if not g then return 0, 0 end
  local open = 0
  for _ in pairs(g.walk) do open = open + 1 end
  return open, (g.w * g.h) - open
end

return MapCollision
