-- A few tiles standing next to each other.
--
-- A tileset editor has no map, and half of what makes a tile look right is
-- what is beside it: a face is drawn only where the neighbour is lower, a
-- ledge lip reads its drop off the neighbouring cell, a conditional pin asks
-- what is drawn one row north.  So the editor builds a SNIPPET -- a small
-- patch of tiles it controls -- and hands it to the resolver as a map.
--
-- Two ways to fill one: from a real map in the ROM cache (so a counter is
-- judged against the actual Pokemon Center around it), or by hand (a 3x3 of
-- one tile surrounded by ground, which is the honest default).
--
-- `asMap` returns something TileShape.at will answer for.  It answers the
-- questions that file actually asks and nothing more: tileAt, the two cell
-- predicates, cellTile, and the def.  widthCells/heightCells are LEFT OUT
-- deliberately -- with them, sealedCells floods a 3-cell patch and decides
-- the middle is a sealed pocket, which on a real map it would not be.

local Grid = {}
Grid.__index = Grid

-- w, h in TILES (8px).  Cells are 2x2 tiles.
-- TILE COORDINATES ARE THE MAP'S, NOT THE WINDOW'S.
--
-- A window onto a map is a few dozen cells out of a hundred, and everything
-- downstream asks its questions in MAP coordinates: TileShape's conditional
-- rules read the tile two rows north, its hop lips read the neighbouring
-- cell, and on Gen 3 the whole per-cell answer -- elevation, behaviour,
-- collision -- is indexed by the map's own cell number.  A grid that
-- renumbered from zero would answer all of those about the wrong place, and
-- would do it consistently enough to look right until you compared it with
-- the game.
--
-- So the grid stores a rectangle and remembers where it starts.
function Grid.new(w, h, fill, ox, oy)
  local g = setmetatable({ w = w, h = h, ox = ox or 0, oy = oy or 0,
                           tiles = {}, water = {}, walk = {},
                           coll = {} }, Grid)
  for y = 0, h - 1 do
    for x = 0, w - 1 do g.tiles[y * w + x] = fill or 0 end
  end
  return g
end

function Grid:set(x, y, tile)
  if x < 0 or y < 0 or x >= self.w or y >= self.h then return end
  self.tiles[y * self.w + x] = tile
end

-- BORDER-EXTEND, never nil.  TileShape's conditional rules ask for the tile
-- one or two rows away and treat nil as "no match" -- so a grid that
-- returned nil off its edge would make every `when_above` rule on the top
-- row silently never fire, and the tile would resolve one way in the editor
-- and the other way in the game.
function Grid:tileAt(x, y)
  x = x - self.ox
  y = y - self.oy
  if x < 0 then x = 0 elseif x >= self.w then x = self.w - 1 end
  if y < 0 then y = 0 elseif y >= self.h then y = self.h - 1 end
  return self.tiles[y * self.w + x]
end

-- The absolute tile range this grid answers for.
function Grid:bounds()
  return self.ox, self.oy, self.ox + self.w - 1, self.oy + self.h - 1
end

function Grid:setCellWalkable(cx, cy, v) self.walk[cx .. "," .. cy] = v and true or false end
function Grid:setCellWater(cx, cy, v) self.water[cx .. "," .. cy] = v and true or false end
function Grid:setCellCollision(cx, cy, v) self.coll[cx .. "," .. cy] = v end

-- A WINDOW ONTO A REAL MAP.
--
-- Not the whole map: a Hoenn route is 100x100 blocks, which is 160,000 tiles,
-- and meshing all of it to look at one counter is not a preview, it is a
-- build.  So the viewport holds a window -- a few dozen cells around a cursor
-- -- and pans it.  Everything outside is not "hidden", it was never meshed.
--
-- THE BLOCK -> TILE STEP IS PER GENERATION and there is no sane default.  Gen
-- 1 and 2 store a 4x4 tile block table on the tileset and a block covers four
-- cells; Gen 3 has no block table at all -- the block ID IS THE METATILE, and
-- the tile id is synthesised as `metatile * 4 + quadrant`, which is the same
-- arithmetic the mod's own Gen3.tileId does.  Indexing a Gen 3 tileset's
-- absent `blocks` table is what makes a Hoenn map throw inside a mesh build,
-- cache the failure, and stay flat for the rest of the session.
-- HOW A MAP STORES ITS GRID, WHICH IS THREE DIFFERENT WAYS.
--
-- Gen 1 and Gen 2 write a flat array of block ids (and a few caches write an
-- array of rows).  Gen 3 writes a BINARY STRING, two bytes per cell, little
-- endian, with the metatile in the low ten bits and collision and elevation
-- packed into the top six -- verified against the extractor's own
-- `collisionCells` and `elevationCells` arrays, which it also ships and which
-- match `(v >> 10) % 4` and `(v >> 12) % 16` exactly.
--
-- Reading that string as if it were an array is what made every Hoenn map
-- come out EMPTY WITH A BORDER: an in-range lookup answered nil, so every
-- cell fell back to tile 0, while the out-of-range one still answered with
-- the border block -- so the only thing that drew was a ring of border trees
-- around a hole where the town should be.  Exactly the shape of "trees on the
-- border but no actual map", and a good reminder that a blank world is a
-- reader that answered nil, not a mesher that failed.
function Grid.blockReader(def, ts)
  local rows = def.blocks or def.map
  local mapW = tonumber(def.width) or 0
  local mapH = tonumber(def.height) or 0
  local byte = string.byte

  if type(rows) == "string" then
    local n = #rows
    return function(bx, by)
      if bx < 0 or by < 0 or bx >= mapW or by >= mapH then return nil end
      local i = (by * mapW + bx) * 2
      if i + 2 > n then return nil end
      local v = byte(rows, i + 1) + byte(rows, i + 2) * 256
      return v % 1024, math.floor(v / 1024) % 4, math.floor(v / 4096) % 16
    end
  end

  if type(rows) ~= "table" then
    return function() return nil end
  end
  return function(bx, by)
    if bx < 0 or by < 0 or bx >= mapW or by >= mapH then return nil end
    local row = rows[by + 1]
    if type(row) == "table" then return row[bx + 1] end
    return rows[by * mapW + bx + 1]
  end
end

-- What is drawn off the edge of the map.  Never "nothing": a window that
-- answered nil at the rim would show a cliff of empty cells around every map
-- and would make the rim tiles emit side faces into a void the game fills in.
-- Gen 3 states a 2x2 border PATTERN as its own little binary string; Gen 1
-- and Gen 2 state one block.
function Grid.borderReader(def)
  local b = def.border
  local byte = string.byte
  if type(b) == "string" and #b >= 8 then
    return function(bx, by)
      local i = ((by % 2) * 2 + (bx % 2)) * 2
      local v = byte(b, i + 1) + byte(b, i + 2) * 256
      return v % 1024
    end
  end
  local single = def.borderBlock
  if type(single) == "table" then single = single[1] end
  return function() return single end
end

-- THE WHOLE MAP, AS TILES.
--
-- The window is what gets MESHED; it is not what gets ASKED.  TileShape's
-- conditional rules read the tile two rows away, its hop lips read the
-- neighbouring cell, and `Structures.forMap` walks the entire map to measure
-- volumes -- so a reader that clamped at the window's edge would answer all
-- of those with whatever happened to be on the rim, consistently enough to
-- look plausible and be wrong.  One reader, over the whole map, and the
-- window only decides what is drawn.
function Grid.mapReader(def, ts, gen3)
  local blockTiles = ts.blockTiles or 4
  local cellsPerBlock = blockTiles / 2
  local blocks = ts.blocks or {}
  local coll = ts.collision
  local readBlock = Grid.blockReader(def, ts)
  local readBorder = Grid.borderReader(def)

  local function blockAt(bx, by)
    local b, packed = readBlock(bx, by)
    if b == nil then return readBorder(bx, by), nil end
    return b, packed
  end

  local R = { blockAt = blockAt, cellsPerBlock = cellsPerBlock }

  function R.tileAt(tx, ty)
    local cx, cy = math.floor(tx / 2), math.floor(ty / 2)
    local b = blockAt(math.floor(cx / cellsPerBlock), math.floor(cy / cellsPerBlock))
    if gen3 then
      return (b or 0) * 4 + (ty % 2) * 2 + (tx % 2)
    end
    local blk = b and blocks[b + 1]
    if not blk then return 0 end
    local sx = (cx % cellsPerBlock) * 2 + (tx % 2)
    local sy = (cy % cellsPerBlock) * 2 + (ty % 2)
    return blk[sy * blockTiles + sx + 1] or 0
  end

  function R.metatileAt(cx, cy)
    local b = blockAt(math.floor(cx / cellsPerBlock), math.floor(cy / cellsPerBlock))
    return b or 0
  end

  function R.cellCollision(cx, cy)
    local b, packed = blockAt(math.floor(cx / cellsPerBlock),
                              math.floor(cy / cellsPerBlock))
    if gen3 then return packed end
    if not (coll and b) then return nil end
    local q = 0
    if cellsPerBlock > 1 then
      q = (cy % cellsPerBlock) * 2 + (cx % cellsPerBlock)
    end
    return coll[b * 4 + q + 1]
  end

  return R
end

function Grid.fromMapWindow(def, ts, cellX0, cellY0, cellsW, cellsH, opts)
  opts = opts or {}
  local gen3 = opts.gen3
  local blockTiles = ts.blockTiles or 4
  local cellsPerBlock = blockTiles / 2          -- 2 on Gen 1/2, 1 on Gen 3
  local g = Grid.new(cellsW * 2, cellsH * 2, 0, cellX0 * 2, cellY0 * 2)
  g.fromMap = true
  g.def = def
  g.mapId = opts.mapId or def.id
  g.cellX0, g.cellY0 = cellX0, cellY0
  g.cellsW, g.cellsH = cellsW, cellsH

  local blocks = ts.blocks or {}
  local coll = ts.collision
  local readBlock = Grid.blockReader(def, ts)
  local readBorder = Grid.borderReader(def)

  for cy = 0, cellsH - 1 do
    for cx = 0, cellsW - 1 do
      local mcx, mcy = cellX0 + cx, cellY0 + cy
      local bx = math.floor(mcx / cellsPerBlock)
      local by = math.floor(mcy / cellsPerBlock)
      local b, packedColl = readBlock(bx, by)
      if b == nil then b = readBorder(bx, by) end

      if gen3 then
        -- the block ID IS the metatile; the tile id is synthesised the same
        -- way the mod's own Gen3.tileId does it
        local m = b or 0
        for ty = 0, 1 do
          for tx = 0, 1 do
            g:set(cx * 2 + tx, cy * 2 + ty, m * 4 + ty * 2 + tx)
          end
        end
        if packedColl then g:setCellCollision(mcx, mcy, packedColl) end
      else
        local blk = b and blocks[b + 1]
        local sx = (mcx % cellsPerBlock) * 2
        local sy = (mcy % cellsPerBlock) * 2
        for ty = 0, 1 do
          for tx = 0, 1 do
            local idx = (sy + ty) * blockTiles + (sx + tx) + 1
            g:set(cx * 2 + tx, cy * 2 + ty, (blk and blk[idx]) or 0)
          end
        end
        -- The Gen 2 collision class for this cell, which is what TileShape
        -- resolves a Gen 2 tile through.  Four bytes per block, NW NE SW SE.
        if coll and b then
          local q = 0
          if cellsPerBlock > 1 then
            q = (mcy % cellsPerBlock) * 2 + (mcx % cellsPerBlock)
          end
          g:setCellCollision(mcx, mcy, coll[b * 4 + q + 1])
        end
      end
    end
  end
  return g
end

-- Kept for the old callers: a window centred on a cell.
function Grid.fromMap(def, ts, centreCellX, centreCellY, cellsW, cellsH, opts)
  return Grid.fromMapWindow(def, ts,
    centreCellX - math.floor(cellsW / 2),
    centreCellY - math.floor(cellsH / 2),
    cellsW, cellsH, opts)
end

-- A grid with one tile (or one tile block) in the middle and flat ground
-- all around it.  The default context, and the one the preview uses.
-- The tile on a patch of ground.
--
-- IT IS PLACED AS A WHOLE CELL, not as one 8px tile.  A cell is 2x2 tiles and
-- that is the granularity collision has, so a wall tile drawn once among
-- ground is a column nothing in the game would ever draw; four of them is
-- what the map actually contains.  Cell-aligned, too -- the engine judges a
-- cell by its bottom-left tile, and a "cell" straddling two of them is not
-- one.
function Grid.around(tile, ground, w, h)
  w, h = w or 8, h or 8
  local g = Grid.new(w, h, ground or tile)
  local mx = math.floor(w / 4) * 2
  local my = math.floor(h / 4) * 2
  for j = 0, 1 do
    for i = 0, 1 do g:set(mx + i, my + j, tile) end
  end
  g.focus = { mx, my }
  return g
end

function Grid:asMap(base)
  -- One map object per grid, not one per lookup: `atGrid` is called for
  -- every tile and every neighbour of every tile, and a fresh table with
  -- six closures on it each time is the difference between a preview that
  -- rebuilds instantly and one that stutters.
  if self._map and self._mapBase == base then return self._map end
  local grid = self
  local map = {
    id = base and base.id or "__editor_grid__",
    -- THE REAL MAP DEF WHEN THERE IS ONE.  Gen 3 answers per cell out of the
    -- def's own elevation and collision arrays, and TileShape reads a
    -- reader's coordinate overrides off it too -- neither of which mean
    -- anything against an empty table.
    def = grid.def or (base and base.def) or {},
    tileset = base and base.tileset,
    waterTiles = base and base.waterTiles or {},
    walkable = base and base.walkable or {},
  }
  function map:tileAt(x, y) return grid:tileAt(x, y) end
  function map:isWalkableCell(cx, cy)
    local v = grid.walk[cx .. "," .. cy]
    if v ~= nil then return v end
    -- unstated: ask the tileset's own walkable list about the cell's
    -- bottom-left tile, which is the granularity collision actually has
    local t = grid:tileAt(cx * 2, cy * 2 + 1)
    return (base and base.walkable and base.walkable[t]) and true or false
  end
  function map:isWaterCell(cx, cy)
    local v = grid.water[cx .. "," .. cy]
    if v ~= nil then return v end
    local t = grid:tileAt(cx * 2, cy * 2 + 1)
    return (base and base.waterTiles and base.waterTiles[t]) and true or false
  end
  function map:cellTile(cx, cy) return grid.coll[cx .. "," .. cy] end
  function map:isGrassCell() return false end
  function map:warpAtCell() return false end
  self._map, self._mapBase = map, base
  return map
end

return Grid
