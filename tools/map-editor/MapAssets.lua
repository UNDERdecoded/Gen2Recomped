-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Save a piece of a map and stamp it down somewhere else.
--
-- WHY THIS EXISTS. A Gen 2 building is not an object in this engine -- it is a
-- patch of block art that the voxel mod's detector reads as a solid and models
-- into a house. Making one by hand means painting twenty cells of facade,
-- roof, door and eaves, and then shaping the heights on top of that, and then
-- doing the whole thing again for the second house. The building already
-- exists on the map next door.
--
-- So an asset is a RECIPE FOR A REGION, not a picture of one: which block and
-- which quadrant of it every cell held, plus the voxel overrides, the objects
-- and the doors that were standing in it. Stamped down, it reproduces all of
-- that at a new origin.
--
-- KEYED RELATIVE TO THE SELECTION'S CORNER, and sparse. Only the cells that
-- were selected are in it, so an L-shaped terrace saves as an L and not as its
-- bounding box with the corner filled in -- and stamping it does not overwrite
-- the ground either side of the L.
--
-- THE TILESET TRAVELS AS A NAME, not as art. Two maps that share a tileset
-- share their block ids, so the common case -- a house from one Johto town
-- onto another -- is a straight copy of numbers. When the destination uses a
-- DIFFERENT tileset those numbers mean different drawings, so the blocks are
-- borrowed across through `MapEdits.borrowBlock`, which appends the source
-- tiles to the destination's atlas and mints blocks that name them. That is
-- the same machinery the tile painter's cross-tileset copy uses.
--
-- WHAT IS NOT IN AN ASSET: scripts and dialogue. An object comes across with
-- its sprite, its position and how it moves; what it SAYS is a text constant
-- belonging to the map it came from, and copying the pointer would make the
-- new NPC recite whatever that constant resolves to on the new map.

local MapEdits = require("tools.map-editor.MapEdits")

local MapAssets = {}

-- ---------------------------------------------------------------------------
-- the store
-- ---------------------------------------------------------------------------

local function bucket(store, game, create)
  if type(store) ~= "table" or not game then return nil end
  if create then
    store.games = store.games or {}
    store.games[game] = store.games[game] or { maps = {} }
    store.games[game].assets = store.games[game].assets or {}
  end
  local g = store.games and store.games[game]
  return g and g.assets or nil
end

function MapAssets.list(store, game)
  local a = bucket(store, game, false) or {}
  local out = {}
  for name in pairs(a) do out[#out + 1] = name end
  table.sort(out)
  return out
end

function MapAssets.get(store, game, name)
  local a = bucket(store, game, false)
  return a and a[name] or nil
end

function MapAssets.delete(store, game, name)
  local a = bucket(store, game, false)
  if a then a[name] = nil end
  return true
end

-- A free name from the one the reader typed. Not an id scheme: assets are
-- theirs, named by them, and two houses called "house" is their business --
-- but silently replacing the first one is not.
function MapAssets.freeName(store, game, wanted)
  local base = tostring(wanted or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if base == "" then base = "asset" end
  local a = bucket(store, game, false) or {}
  if not a[base] then return base end
  for n = 2, 999 do
    local alt = string.format("%s %d", base, n)
    if not a[alt] then return alt end
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- capture
-- ---------------------------------------------------------------------------

-- The block and quadrant a CELL is currently showing.
--
-- A block is 2x2 cells, so a cell is a quadrant of one: which block the map
-- points at there, and which quarter of it this cell is. Both are needed --
-- the block alone would stamp its north-west corner everywhere.
local function cellSource(def, ts, cx, cy)
  if not (def and def.blocks and def.width) then return nil end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  if bx < 0 or by < 0 or bx >= def.width or by >= (def.height or 0) then
    return nil
  end
  local block = def.blocks[by * def.width + bx + 1]
  if type(block) ~= "number" then return nil end
  return block, (cx % 2) + (cy % 2) * 2
end

-- Build an asset from a set of selected cells.
--
-- `cells` is a list of `{ cx = , cy = }` -- what `Preview.selection` returns,
-- which is also what the shift-click and ctrl-click selections produce. One
-- cell is a legitimate asset (a lamp post, a sign) and so is two hundred.
function MapAssets.capture(S, cells, name)
  if type(cells) ~= "table" or #cells == 0 then
    return nil, "select some cells on the map first"
  end
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  if not def then return nil, "no map open" end
  local ts = S.data.tilesets and S.data.tilesets[def.tileset or ""]
  if not ts then return nil, "this map's tileset is not in this import" end

  -- THE ORIGIN IS THE SELECTION'S TOP-LEFT, and everything is stored as an
  -- offset from it. Absolute coordinates would make an asset only stampable
  -- where it came from.
  local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
  for _, c in ipairs(cells) do
    minX, minY = math.min(minX, c.cx), math.min(minY, c.cy)
    maxX, maxY = math.max(maxX, c.cx), math.max(maxY, c.cy)
  end

  local store = S.mapEdits or MapEdits.load()
  S.mapEdits = store
  local game = MapAssets.gameOf(S)
  local m = MapEdits.bucket(store, game, S.mapId, false)

  local asset = {
    w = maxX - minX + 1, h = maxY - minY + 1,
    tileset = def.tileset,
    from = S.mapId,
    cells = {}, voxels = {}, tiles = {}, objects = {}, warps = {},
  }

  local inSel = {}
  for _, c in ipairs(cells) do
    local dx, dy = c.cx - minX, c.cy - minY
    inSel[c.cx .. "," .. c.cy] = true
    local block, q = cellSource(def, ts, c.cx, c.cy)
    if block then
      asset.cells[dx .. "," .. dy] = { block = block, q = q }
    end
    -- the reader's own overrides, which are the whole reason a saved building
    -- is a BUILDING and not a flat stamp of its facade
    local vo = m and m.voxels and m.voxels[c.cx .. "," .. c.cy]
    if vo then
      local copy = {}
      for k, v in pairs(vo) do copy[k] = v end
      asset.voxels[dx .. "," .. dy] = copy
    end
    for r = 0, 1 do
      for cc = 0, 1 do
        local tx, ty = c.cx * 2 + cc, c.cy * 2 + r
        local to = m and m.tiles and m.tiles[tx .. "," .. ty]
        if to then
          local copy = {}
          for k, v in pairs(to) do copy[k] = v end
          asset.tiles[(dx * 2 + cc) .. "," .. (dy * 2 + r)] = copy
        end
      end
    end
  end

  -- OBJECTS AND DOORS STANDING IN IT. Both are in the same cell space the
  -- selection is in, so "inside" is a set lookup rather than a rectangle test
  -- -- which matters for the L-shaped selection: an NPC in the notch of the L
  -- was never part of what was picked.
  for _, o in ipairs(def.objects or {}) do
    if o.x and o.y and inSel[o.x .. "," .. o.y] then
      asset.objects[#asset.objects + 1] = {
        sprite = o.sprite, dx = o.x - minX, dy = o.y - minY,
        movement = o.movement, range = o.range, item = o.item,
      }
    end
  end
  for _, wp in ipairs(def.warps or {}) do
    if wp.x and wp.y and inSel[wp.x .. "," .. wp.y] and not wp.removed then
      -- NO DESTINATION. A door that points at the map it was copied FROM is a
      -- door back to somewhere the new building has nothing to do with, and
      -- one pointing at a map that does not exist crashes on use. The warp
      -- editor already shows "no destination" and already lets you set one.
      asset.warps[#asset.warps + 1] = { dx = wp.x - minX, dy = wp.y - minY,
                                        destWarp = 1 }
    end
  end

  local final = MapAssets.freeName(store, game, name)
  if not final then return nil, "no free name left" end
  bucket(store, game, true)[final] = asset
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return final, asset
end

-- ---------------------------------------------------------------------------
-- placement
-- ---------------------------------------------------------------------------

-- Every distinct source block an asset names, so a cross-tileset stamp borrows
-- each one once rather than once per cell that uses it.
function MapAssets.blocksUsed(asset)
  local seen, out = {}, {}
  for _, rec in pairs((asset or {}).cells or {}) do
    if rec.block and not seen[rec.block] then
      seen[rec.block] = true
      out[#out + 1] = rec.block
    end
  end
  table.sort(out)
  return out
end

-- Stamp `asset` with its top-left corner at cell (cx, cy).
--
-- Returns a report, or nil and a reason.
function MapAssets.place(S, asset, cx, cy)
  if type(asset) ~= "table" then return nil, "no asset" end
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  if not def then return nil, "no map open" end
  local okT, Tiles = pcall(require, "tools.map-editor.panels.Tiles")
  if not (okT and type(Tiles) == "table" and Tiles.paintCell) then
    return nil, "the tile painter is not in this build"
  end

  local store = S.mapEdits or MapEdits.load()
  S.mapEdits = store
  local game = MapAssets.gameOf(S)
  local destTs = def.tileset
  local notes = {}

  -- ------------------------------------------------- the tileset it depends on
  --
  -- Two maps sharing a tileset share their block ids, so the common case needs
  -- no translation at all. When they differ, every distinct block is borrowed
  -- across ONCE and then resolved to a live id -- `applyTilesets` is what turns
  -- a mint key into the number the renderer can index, and until it has run
  -- there is nothing to paint with.
  local remap = nil
  if asset.tileset and destTs and asset.tileset ~= destTs then
    local srcTs = S.data.tilesets and S.data.tilesets[asset.tileset]
    if not srcTs then
      return nil, string.format(
        "this asset is drawn with %s, which is not in this import",
        tostring(asset.tileset))
    end
    remap = {}
    local keys = {}
    for _, block in ipairs(MapAssets.blocksUsed(asset)) do
      local key, why = MapEdits.borrowBlock(store, game, destTs, asset.tileset,
                                            block, S.data.tilesets)
      if not key then return nil, tostring(why) end
      keys[block] = key
    end
    local ids = MapEdits.applyTilesets(store, game, S.data.tilesets)
    for block, key in pairs(keys) do
      local live = ids and ids[key]
      if not live then
        return nil, "the borrowed art could not be resolved to a block id"
      end
      remap[block] = live
    end
    notes[#notes + 1] = string.format("%d block(s) copied from %s",
      #MapAssets.blocksUsed(asset), tostring(asset.tileset))
    -- AND THE TILESET GOES ON THE MAP'S LIST, because it is now one of the
    -- tilesets this map is drawn from -- the art is in its atlas either way,
    -- and the only question the list answers is whether the painter should
    -- keep asking about it. Not asked about here: a stamp is a deliberate
    -- act on a named asset, so the reader has already said what they want,
    -- and a dialog on top of it would be a second confirmation of the same
    -- decision.
    MapEdits.addMapTileset(store, game, S.mapId, asset.tileset, destTs)
  end

  local painted = 0
  for key, rec in pairs(asset.cells or {}) do
    local dx, dy = key:match("^(%-?%d+),(%-?%d+)$")
    if dx then
      local tx, ty = cx + tonumber(dx), cy + tonumber(dy)
      -- CLIPPED, not wrapped or refused. Stamping a five-cell house one cell
      -- from the edge should put four cells of house down and say so, rather
      -- than refusing the whole thing or writing off the end of the array.
      if tx >= 0 and ty >= 0 and tx < def.width * 2 and ty < def.height * 2 then
        local block = remap and remap[rec.block] or rec.block
        if Tiles.paintCell(S, tx, ty, block, nil, rec.q) then
          painted = painted + 1
        end
      end
    end
  end

  -- ------------------------------------------------------------- the shape
  local voxels, tiles = 0, 0
  for key, rec in pairs(asset.voxels or {}) do
    local dx, dy = key:match("^(%-?%d+),(%-?%d+)$")
    if dx then
      MapEdits.setVoxel(store, game, S.mapId, cx + tonumber(dx),
                        cy + tonumber(dy), rec)
      voxels = voxels + 1
    end
  end
  for key, rec in pairs(asset.tiles or {}) do
    local dx, dy = key:match("^(%-?%d+),(%-?%d+)$")
    if dx then
      -- tile coordinates, so the ORIGIN doubles too: an asset's tile (3,1) is
      -- three 8px tiles from its corner, and its corner is at cell (cx, cy),
      -- which is tile (cx*2, cy*2).
      MapEdits.setTileVoxel(store, game, S.mapId, cx * 2 + tonumber(dx),
                            cy * 2 + tonumber(dy), rec)
      tiles = tiles + 1
    end
  end

  -- ------------------------------------------------- what was standing in it
  local objects, warps = 0, 0
  for _, o in ipairs(asset.objects or {}) do
    MapEdits.addObject(store, game, S.mapId, {
      sprite = o.sprite, x = cx + (o.dx or 0), y = cy + (o.dy or 0),
      movement = o.movement, range = o.range, item = o.item,
    })
    objects = objects + 1
  end
  for _, wp in ipairs(asset.warps or {}) do
    MapEdits.addWarp(store, game, S.mapId, {
      x = cx + (wp.dx or 0), y = cy + (wp.dy or 0), destWarp = 1,
    })
    warps = warps + 1
  end
  if warps > 0 then
    notes[#notes + 1] = warps .. " door(s) placed with no destination"
  end
  if #(asset.objects or {}) > 0 then
    notes[#notes + 1] = "objects came without their dialogue"
  end

  MapEdits.applyAll(store, game, S.data.maps, S.data.tilesets, S.data.sprites)
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  pcall(function()
    require("tools.map-editor.ModShapes").invalidate(S.mapId)
  end)
  S._pvCenteredFor = S.mapId
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  return { cells = painted, voxels = voxels, tiles = tiles,
           objects = objects, warps = warps, notes = notes }
end

function MapAssets.gameOf(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring((S and S.version) or v or "unknown")
end

-- ---------------------------------------------------------------------------
-- the pointer state
-- ---------------------------------------------------------------------------
--
-- PICK, THEN CLICK -- which is what drag and drop is in an immediate-mode UI
-- with no drag channel. The picked asset follows the pointer as a ghost
-- footprint and lands where it is clicked; Escape or picking it again puts it
-- down. That is the same gesture the tile painter already uses, so there is one
-- thing to learn rather than two.

function MapAssets.arm(S, name)
  if S.assetPlacing == name then
    S.assetPlacing = nil
    return false
  end
  S.assetPlacing = name
  return true
end

function MapAssets.disarm(S)
  S.assetPlacing = nil
end

function MapAssets.armed(S)
  if not (S and S.assetPlacing) then return nil end
  return MapAssets.get(S.mapEdits, MapAssets.gameOf(S), S.assetPlacing),
         S.assetPlacing
end

return MapAssets
