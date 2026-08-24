-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- The tile painter: change the ground itself, by dragging on the map.
--
-- WHAT A MAP IS MADE OF, and why this is a block palette rather than a tile
-- one. A Gen 2 map stores ONE BLOCK ID per 32x32 block -- there is no per-tile
-- layer anywhere in the format -- and a block is a 4x4 grid of 8px tiles with
-- four collision classes attached. So the thing you paint with is a block, and
-- the palette is the tileset's own block list: exactly the pieces the
-- cartridge built its towns out of.
--
-- Finer than that is still reachable and still costs a block: repainting one
-- 16px CELL means minting a block that differs from its neighbour in one
-- quadrant, which is what Preview's cell art stepper does. This panel is the
-- coarse tool -- lay a road, fill a room, run a wall -- and the two share the
-- same mint store, so a cell edited one way and a block painted the other do
-- not fight.
--
-- BORROWING FROM ANOTHER TILESET is a different operation and is named
-- differently for that reason. A block's sixteen numbers are indices into ITS
-- tileset's atlas, and the thirty-eight tilesets in a Gen 2 import have
-- thirty-seven different atlases between them -- so the same numbers in
-- another tileset draw whatever happens to be at those indices there, which is
-- not the same picture, it is noise. Bringing art across means copying the
-- PIXELS; see MapEdits.borrowBlock.

local Theme = require("Theme")
local PAL = Theme.PAL
local MapEdits = require("tools.map-editor.MapEdits")

local Tiles = {}

-- THIS PANEL FILLS THE RECTANGLE IT IS GIVEN; it does not flow down a page.
-- The palette below sizes its rows, its page and its own scroll rail from the
-- height handed in, so a drawer must hand it the height that is actually
-- visible -- see the note on `fillsBody` in Sidebar.lua.
Tiles.fillsBody = true

local BLOCK = 32          -- world pixels per block, and per palette swatch

local function store(S)
  if not S.mapEdits then S.mapEdits = (MapEdits.load()) end
  return S.mapEdits
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

local function markEdited(S)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
end

local function mapDef(S)
  return S.data and S.data.maps and S.data.maps[S.mapId or ""] or nil
end

local function tilesetOf(S, id)
  local sets = S.data and S.data.tilesets or {}
  if id then return sets[id], id end
  local def = mapDef(S)
  local tid = def and def.tileset
  return tid and sets[tid] or nil, tid
end

-- Every tileset the import carries, sorted -- the source list for borrowing.
local function tilesetNames(S)
  if S._tilesetNames then return S._tilesetNames end
  local out = {}
  for id in pairs((S.data and S.data.tilesets) or {}) do out[#out + 1] = id end
  table.sort(out)
  S._tilesetNames = out
  return out
end

-- THE COLOURED ATLAS, NOT THE RAW SHEET.
--
-- A Gen 2 tileset image is 2bpp greyscale; the colour is a palette byte per
-- TILE GRAPHIC (palMap into palColors) that the renderer bakes into an atlas
-- before it draws anything.  This palette drew from the raw sheet, so every
-- swatch was grey while the viewport two inches away was in colour -- and
-- picking ground by matching a grey drawing against a coloured world is
-- guesswork.
--
-- The map's OWN renderer is asked first: it has already baked exactly the
-- atlas the viewport is drawing from, so the palette and the map cannot
-- disagree.  A foreign tileset has no built renderer, so it gets its own bake
-- from the same function the renderer uses -- keyed and cached in there, so
-- flipping through tilesets does not re-bake one twice.
--
-- Falls back to the raw sheet whenever there is no palette to apply (a
-- pre-palette extraction, or COLORS set to a DMG mode), which is what this was
-- always showing.
local function atlasFor(S, ts, tsId)
  local own = S._pvMap
  if own and own.tileset and own.tileset.id == tsId and own.renderer
      and own.renderer.image then
    return own.renderer.image
  end
  local okC, coloured = pcall(function()
    return require("src.render.TileRenderer").gen2AtlasFor(ts)
  end)
  if okC and coloured then return coloured end

  -- GEN 1 COLOURS THE OTHER WAY, and needs the MAP to do it.
  --
  -- There is no palette byte on a Gen 1 tileset: colour is per palette GROUP,
  -- resolved per map, because the same tile graphic is grass on one route and
  -- a roof on another. So this bake takes a map id where the Gen 2 one takes
  -- only a tileset -- and without it every Gen 1 tileset came out grey beside
  -- a coloured viewport.
  local okG, gbc = pcall(function()
    return require("src.render.TileRenderer").gbcAtlasFor(ts, S.mapId, S.data)
  end)
  if okG and gbc then return gbc end
  if not (ts and ts.image) then return nil end
  local okI, img = pcall(function()
    return require("src.render.Assets").image(ts.image)
  end)
  return okI and img or nil
end

Tiles.atlasFor = atlasFor

-- ---------------------------------------------------------------------------
-- the tilesets this map paints from
-- ---------------------------------------------------------------------------
--
-- The map's own is implicit and is never in the stored list; see
-- `MapEdits.mapTilesets` for why the list is a record of PERMISSION rather
-- than a second tileset on the def.

function Tiles.mapTilesets(S)
  if not (S and S.mapId) then return {} end
  return MapEdits.mapTilesets(store(S), game(S), S.mapId)
end

function Tiles.usesTileset(S, id)
  if not (S and S.mapId) then return false end
  local _, ownId = tilesetOf(S)
  return MapEdits.mapUsesTileset(store(S), game(S), S.mapId, id, ownId)
end

-- ---------------------------------------------------------------------------
-- picking a block, from wherever it came from
-- ---------------------------------------------------------------------------

-- Make (`srcTsId`, `blockId`) the thing the brush lays down, copying the art
-- across first if it is from another tileset.
--
-- WHY THE COPY HAPPENS AT PICK TIME AND NOT AT PAINT TIME. Both are defensible
-- and one of them is a disaster: a stroke is fifty paints, and borrowing per
-- paint means fifty trips through `applyTilesets`, each of which rebuilds a
-- tileset atlas image. Pick happens once. By the time the pointer is on the
-- map the block is an ordinary local block id and every path below here --
-- cell paint, block paint, flood fill, the asset stamper -- works on it
-- unchanged, which is the other half of the reason.
--
-- MEMOISED, because picking the same block twice should not append the same
-- sixteen tiles twice. `borrowBlock` dedupes underneath as well, so the cache
-- is about the atlas rebuild rather than about correctness.
--
-- Returns the live block id, or nil and a reason.
function Tiles.usePick(S, srcTsId, blockId, q)
  local ownTs, ownId = tilesetOf(S)
  if not (ownTs and ownId) then return nil, "this map has no tileset" end
  if srcTsId == nil or srcTsId == ownId then
    S.tilePick, S.tilePickQ = blockId, q
    S.tilePickSrc = nil
    return blockId
  end

  -- The cache belongs to the DESTINATION: the same source block borrowed into
  -- two different tilesets lands on two different ids, and a cache that
  -- forgets which one it was for hands the second map the first one's number.
  if S._tileBorrowFor ~= ownId then
    S._tileBorrowFor, S._tileBorrowLive = ownId, {}
  end
  S._tileBorrowLive = S._tileBorrowLive or {}
  local ck = tostring(srcTsId) .. "/" .. tostring(blockId)
  local live = S._tileBorrowLive[ck]
  if live == nil then
    local got, why = MapEdits.borrowLive(store(S), game(S), ownId, srcTsId,
                                         blockId, S.data and S.data.tilesets)
    if not got then return nil, why end
    S._tileBorrowLive[ck] = got
    live = got
    markEdited(S)
    -- THE ART JUST MOVED. Borrowing rewrites this tileset's atlas -- taller,
    -- under a new name -- and everything holding the old one goes on drawing
    -- the old one: the built map keeps the renderer it was made with, and the
    -- palette prefers that renderer's image over a fresh bake. Without this
    -- the borrowed block draws as a black square, because its tiles name rows
    -- that exist in the file and not in the Image on screen.
    pcall(function() require("src.render.TileRenderer").invalidate() end)
    -- AND THE MOD'S SHAPE TABLE. It is keyed by tileset id and a borrow does
    -- not change the id, so without this the 3D view goes on answering from a
    -- table built before the tileset grew -- and the borrowed tile, having no
    -- shape, comes out as a black rectangle. See extendAtlas.
    pcall(function()
      require("tools.map-editor.ModShapes").invalidateAll()
    end)
    pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
    S.pv3D, S.pv3DKey = nil, nil
    S._pvCenteredFor = S.mapId
  end
  S.tilePick, S.tilePickQ = live, q
  -- WHAT THE PALETTE RINGS, which is not what the brush paints. The brush has
  -- a local block id now; the palette is showing the foreign tileset and has
  -- to ring the swatch that was clicked in IT. Two facts, two fields -- the
  -- version that kept one ringed whichever local block happened to share the
  -- borrowed id's number.
  S.tilePickSrc = { ts = srcTsId, block = blockId }
  return live
end

local function blockCount(ts)
  if not (ts and type(ts.blocks) == "table") then return 0 end
  return #ts.blocks
end

-- ---------------------------------------------------------------------------
-- drawing a block
-- ---------------------------------------------------------------------------

-- One 32x32 block, from the tileset's own atlas, at whatever zoom the palette
-- is at. Drawn tile by tile because a block is not contiguous in the atlas --
-- its sixteen tiles are sixteen separate places, which is the whole reason the
-- format has a block table at all.
local function drawBlock(ts, image, blockId, x, y, scale)
  if not (ts and image and ts.blocks) then return false end
  local block = ts.blocks[blockId + 1]
  if not block then return false end
  local iw, ih = image:getDimensions()
  local perRow = ts.tilesPerRow or math.max(1, math.floor(iw / 8))
  for i = 1, 16 do
    local tile = block[i] or 0
    local ax = (tile % perRow) * 8
    local ay = math.floor(tile / perRow) * 8
    if ax + 8 <= iw and ay + 8 <= ih then
      local ok, quad = pcall(love.graphics.newQuad, ax, ay, 8, 8, iw, ih)
      if ok then
        local col = (i - 1) % 4
        local row = math.floor((i - 1) / 4)
        love.graphics.draw(image, quad, x + col * 8 * scale,
                           y + row * 8 * scale, 0, scale, scale)
      end
    end
  end
  return true
end

Tiles.drawBlock = drawBlock

-- ---------------------------------------------------------------------------
-- painting
-- ---------------------------------------------------------------------------

-- Paint one block of the map. Writes the store AND the live def for the same
-- reason every other tool does: the live table is what the next frame draws,
-- and the store is what survives the session.
function Tiles.paint(S, bx, by, id)
  local def = mapDef(S)
  if not (def and def.blocks and bx >= 0 and by >= 0
          and bx < def.width and by < def.height) then
    return false
  end
  local at = by * def.width + bx + 1
  if def.blocks[at] == id then return false end   -- nothing to record
  MapEdits.setBlock(store(S), game(S), S.mapId, bx, by, id)
  def.blocks[at] = id
  markEdited(S)
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  S._pvCenteredFor = S.mapId
  return true
end

-- ---------------------------------------------------------------------------
-- painting ONE CELL
-- ---------------------------------------------------------------------------

-- A BLOCK IS FOUR CELLS, AND THAT IS WHY PAINTING FELT WRONG.
--
-- The palette holds blocks, so the first version painted a block -- and a
-- block is 32x32, four of the 16x16 cells everything else in this editor works
-- in. Two complaints fall straight out of that and they are the same bug: a
-- click painted a 2x2 area rather than the square under the pointer, and it
-- painted it aligned to the BLOCK grid, so clicking the cell at (5,3) repainted
-- cells (4..5, 2..3) -- up and to the left of where the pointer was. Nothing
-- was offset; the tool was simply working in a coarser unit than the one being
-- pointed at.
--
-- So a cell paint mints a block that is the one already there with a single
-- QUADRANT replaced -- the same trick the cell art stepper uses -- and takes
-- that quadrant from the MATCHING corner of the picked block, so painting all
-- four cells of a block by hand reproduces the block exactly.
--
-- The four tile slots of a cell's quadrant, and the collision slot with them.
-- A block is a 4x4 grid of tiles indexed `(ty % 4) * 4 + (tx % 4) + 1`, and its
-- four collision classes sit in NW/NE/SW/SE order.
local function cellSlots(cx, cy)
  local qx, qy = cx % 2, cy % 2
  local slots = {}
  for r = 0, 1 do
    for c = 0, 1 do
      slots[#slots + 1] = (qy * 2 + r) * 4 + (qx * 2 + c) + 1
    end
  end
  return slots, qx + qy * 2 + 1
end

Tiles.cellSlots = cellSlots

-- The four tile slots of ONE quadrant of a block, named by quadrant index
-- (0 = NW, 1 = NE, 2 = SW, 3 = SE) rather than by a map coordinate.  The
-- palette needs this to talk about "that 16px square of that block"; the
-- coordinate form above is the same arithmetic with the quadrant derived.
local function quadSlots(q)
  local qx, qy = q % 2, math.floor(q / 2)
  local slots = {}
  for r = 0, 1 do
    for c = 0, 1 do
      slots[#slots + 1] = (qy * 2 + r) * 4 + (qx * 2 + c) + 1
    end
  end
  return slots
end

Tiles.quadSlots = quadSlots

-- `srcQ` names WHICH 16px square of the source block to lay down, 0..3.
--
-- Without it the source quadrant was always the one MATCHING the destination
-- -- paint into a north-west cell and you got the block's north-west corner --
-- which is right for reproducing a whole block cell by cell and wrong for
-- everything else: the palette showed a 32px block, you clicked the piece of
-- it you wanted, and what landed was whichever piece happened to share the
-- destination's parity.  Half the time that is a different drawing entirely.
-- nil keeps the matching-corner behaviour, which is what BLOCK grain and the
-- older callers want.
function Tiles.paintCell(S, cx, cy, srcBlockId, srcTilesetId, srcQ)
  local def = mapDef(S)
  local ts, tsId = tilesetOf(S)
  if not (def and def.blocks and ts and type(ts.blocks) == "table") then
    return false
  end
  local bx, by = math.floor(cx / 2), math.floor(cy / 2)
  if bx < 0 or by < 0 or bx >= def.width or by >= def.height then return false end

  local cur = def.blocks[by * def.width + bx + 1] or 0
  local curBlock = ts.blocks[cur + 1]
  local src = ts.blocks[(srcBlockId or 0) + 1]
  if not (curBlock and src) then return false end

  local tiles, coll = {}, {}
  for i = 1, 16 do tiles[i] = curBlock[i] or 0 end
  for q = 1, 4 do
    coll[q] = (ts.collision and ts.collision[cur * 4 + q]) or 0
  end
  local slots, cq = cellSlots(cx, cy)
  -- The source slots are the picked quadrant's when one was picked, and the
  -- destination's own otherwise.
  local from = (srcQ ~= nil) and quadSlots(srcQ) or slots
  for n, i in ipairs(slots) do tiles[i] = src[from[n]] or 0 end
  -- THE COLLISION COMES WITH THE ART. A cell whose drawing says wall and whose
  -- class says floor is a wall you walk through, and the class is per quadrant
  -- exactly as the art is.
  local sq = (srcQ ~= nil) and (srcQ + 1) or cq
  coll[cq] = (ts.collision and ts.collision[(srcBlockId or 0) * 4 + sq]) or coll[cq]

  local key = MapEdits.mintBlock(store(S), game(S), tsId, tiles, coll)
  if not key then return false end
  MapEdits.setBlock(store(S), game(S), S.mapId, bx, by, key)

  -- The live def cannot hold the key -- it is a string, and the renderer
  -- indexes the block array with a number -- so the block has to exist in the
  -- LIVE tileset too. Apply does the same on the next load from the store;
  -- this is the copy the next FRAME draws from.
  --
  -- DEDUPED, and not as a nicety. The store's mint already dedupes, but this
  -- append did not: a fifty-cell stroke laying the same grass appended fifty
  -- identical blocks to the tileset, every one of them a permanent addition
  -- the renderer then carries. Painting a route could push a tileset past the
  -- 256 blocks a Gen 2 block id can even hold.
  local liveId = nil
  for i, existing in ipairs(ts.blocks) do
    local same = true
    for k = 1, 16 do
      if existing[k] ~= tiles[k] then same = false break end
    end
    if same and type(ts.collision) == "table" then
      for q = 1, 4 do
        if (ts.collision[(i - 1) * 4 + q] or 0) ~= (coll[q] or 0) then
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
    if type(ts.collision) == "table" then
      for q = 1, 4 do ts.collision[liveId * 4 + q] = coll[q] end
    end
  end
  def.blocks[by * def.width + bx + 1] = liveId
  markEdited(S)
  pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
  S._pvCenteredFor = S.mapId
  return true
end

-- FLOOD FILL, bounded by the map and by the block that was there.
--
-- Four-neighbour, iterative, and capped: a fill on a route is a few hundred
-- blocks, but a fill with a bad bound is every block on the map and then the
-- editor is gone. The cap is the map's own area, which no legitimate fill can
-- exceed -- so the limit can only be hit by a bug, and hitting it stops rather
-- than hanging.
function Tiles.fill(S, bx, by, id)
  local def = mapDef(S)
  if not (def and def.blocks and def.width and def.height) then return 0 end
  local w, h = def.width, def.height
  if bx < 0 or by < 0 or bx >= w or by >= h then return 0 end
  local from = def.blocks[by * w + bx + 1]
  if from == id then return 0 end

  local seen, stack, n = {}, { { bx, by } }, 0
  seen[by * w + bx] = true
  local cap = w * h
  while #stack > 0 and n < cap do
    local p = table.remove(stack)
    local px, py = p[1], p[2]
    if def.blocks[py * w + px + 1] == from then
      Tiles.paint(S, px, py, id)
      n = n + 1
      local nb = { { px + 1, py }, { px - 1, py }, { px, py + 1 }, { px, py - 1 } }
      for _, q in ipairs(nb) do
        local qx, qy = q[1], q[2]
        if qx >= 0 and qy >= 0 and qx < w and qy < h and not seen[qy * w + qx] then
          seen[qy * w + qx] = true
          stack[#stack + 1] = q
        end
      end
    end
  end
  return n
end

-- ---------------------------------------------------------------------------
-- the panel
-- ---------------------------------------------------------------------------

-- A CLICK IN THE PALETTE, routed by where the block came from.
--
-- Three cases and only three: the map's own tileset picks straight through; a
-- tileset the map has added borrows the art and picks the local block it
-- became; a tileset the map has NOT added stops and asks, because that is the
-- click that grows an atlas thirty other maps share.
local function pickFrom(S, srcId, idx, q, foreign, added)
  if not foreign or added then
    local live, why = Tiles.usePick(S, srcId, idx, q)
    if not live then S.tileNotice = tostring(why) end
    return
  end
  local okP, Prompt = pcall(require, "tools.map-editor.panels.TilesetPrompt")
  if okP and type(Prompt) == "table" and Prompt.ask then
    if Prompt.ask(S, srcId, idx, q) then return end
  end
  -- No prompt in this build: do the safe half of what it would have done --
  -- copy the one block -- rather than dropping the click on the floor.
  local live, why = Tiles.usePick(S, srcId, idx, q)
  if not live then S.tileNotice = tostring(why) end
end

function Tiles.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 16 * s

  if not S.mapId then
    Kit.emptyBox(x, y, w, h, "Pick a map first.")
    return
  end

  local def = mapDef(S)
  local ownTs, ownId = tilesetOf(S)
  S.tileSource = S.tileSource or ownId
  local srcTs, srcId = tilesetOf(S, S.tileSource)
  if not srcTs then
    S.tileSource = ownId
    srcTs, srcId = ownTs, ownId
  end

  Kit.caption(x, y, "TILES - " .. tostring(S.mapId))
  local fy = y + Kit.textHeight("caption") + 6 * s

  -- THE SOURCE TILESET. The map's own is the one you can paint straight from;
  -- any other is art you can COPY across, which is a different and more
  -- expensive thing and says so.
  local btnH = 28 * s
  Kit.text("small", "FROM", x, fy + 7 * s, PAL.muted)
  -- A LIST, NOT A CYCLE BUTTON. This stepped to the next tileset on each
  -- press, which is fine for the two or three you use and useless for the
  -- thirty-eight a Gen 2 import carries: reaching the last one is
  -- thirty-seven presses, and there is no way to see what is in the set or
  -- where in it you are.
  if Kit.button(x + 46 * s, fy, w - 46 * s - 84 * s, btnH,
                Kit.ellipsize("small", tostring(srcId or "-"),
                              w - 46 * s - 96 * s),
                { font = "small" }) then
    S.tileSourceOpen = not S.tileSourceOpen
    S.tileSourceQuery = ""
    S.tileSourceScroll = 0
  end
  if Kit.button(x + w - 80 * s, fy, 80 * s, btnH, "MINE",
                { font = "small", kind = (srcId == ownId) and "accent" or nil }) then
    S.tileSource = ownId
    S.tileScroll = 0
    S.tileSourceOpen = false
  end
  fy = fy + btnH + 6 * s

  if S.tileSourceOpen then
    S.tileSourceQuery = Kit.textfield("tile-src-q", x, fy, w, btnH,
      S.tileSourceQuery or "", "search tilesets...")
    fy = fy + btnH + 4 * s
    local all = tilesetNames(S)
    local hits = {}
    local q = (S.tileSourceQuery or ""):lower()
    for _, id in ipairs(all) do
      if q == "" or id:lower():find(q, 1, true) then hits[#hits + 1] = id end
    end
    local ROWS = 7
    local rowH = 24 * s
    local maxS = math.max(0, #hits - ROWS)
    S.tileSourceScroll = math.max(0, math.min(S.tileSourceScroll or 0, maxS))
    if #hits == 0 then
      Kit.text("small", "no tileset matches that", x, fy, PAL.muted)
      fy = fy + 18 * s
    end
    for i = S.tileSourceScroll + 1,
            math.min(#hits, S.tileSourceScroll + ROWS) do
      local id = hits[i]
      -- WHAT EACH ONE IS TO THIS MAP, on the row: its own, one it has already
      -- been given, or a stranger. Without it the list is thirty-eight names
      -- and no way to tell which two you have been working with.
      local tag = (id == ownId) and "  (this map's)"
        or (Tiles.usesTileset(S, id) and "  (added)" or "")
      if Kit.button(x, fy, w, rowH - 2 * s,
                    Kit.ellipsize("small", id .. tag, w - 16 * s),
                    { font = "small",
                      kind = (id == srcId) and "accent" or nil }) then
        S.tileSource = id
        S.tileScroll = 0
        S.tileSourceOpen = false
      end
      fy = fy + rowH
    end
    if maxS > 0 then
      Kit.text("small", string.format("%d of %d  -  scroll or search",
               math.min(#hits, (S.tileSourceScroll or 0) + ROWS), #hits),
               x, fy, PAL.muted)
      fy = fy + 16 * s
    end
    fy = fy + 4 * s
  end

  -- FOREIGN, AND WHETHER THIS MAP HAS SAID YES TO IT. Two different states
  -- that used to be one: everything that was not the map's own tileset was
  -- art you could only COPY one block at a time, through a button, with the
  -- cell brush disabled. A tileset the reader has added to the map is not that
  -- -- it is a second palette they are building with, and it paints exactly
  -- like the map's own does.
  local foreign = srcId ~= ownId
  local added = foreign and Tiles.usesTileset(S, srcId) or false
  if foreign then
    Kit.text("small", Kit.ellipsize("small", added
      and ("added to this map - painting copies its art into "
           .. tostring(ownId))
      or ("not on this map yet - picking a block will ask"),
      w), x, fy, added and PAL.muted or PAL.yellow)
    fy = fy + 16 * s
  end

  -- ------------------------------------------------------- THIS MAP'S LIST
  --
  -- Shown even when it is empty-but-for-the-map's-own, because "which
  -- tilesets is this map drawn from" is a question with an answer now and the
  -- answer used to be unaskable.
  do
    local list = Tiles.mapTilesets(S)
    if #list > 0 then
      Kit.text("small", "USES", x, fy + 5 * s, PAL.muted)
      local cx = x + 44 * s
      for _, id in ipairs(list) do
        local label = Kit.ellipsize("small", id, 108 * s)
        local bw = math.min(w - (cx - x) - 22 * s,
                            Kit.textWidth("small", label) + 16 * s)
        if bw > 24 * s then
          if Kit.chip(cx, fy, bw, 22 * s, label, srcId == id) then
            S.tileSource, S.tileScroll = id, 0
          end
          -- DROPPING ONE DOES NOT UNPAINT IT, and the notice says so rather
          -- than letting the reader find out by looking for art that is still
          -- there. The borrowed blocks are minted into this map's own tileset
          -- now; this list is permission, not ownership.
          if Kit.button(cx + bw, fy, 18 * s, 22 * s, "x",
                        { font = "small", radius = 5 * s }) then
            MapEdits.removeMapTileset(store(S), game(S), S.mapId, id)
            markEdited(S)
            S.tileNotice = id .. " dropped - art already painted stays"
          end
          cx = cx + bw + 20 * s
        end
      end
      fy = fy + 22 * s + 6 * s
    end
  end

  -- MODE. Paint is the default; fill is the same click with a flood behind it;
  -- pick is the eyedropper, which is how you match ground you can see rather
  -- than hunting the palette for it.
  local MODES = { { id = "paint", label = "PAINT" },
                  { id = "fill",  label = "FILL" },
                  { id = "pick",  label = "PICK" } }
  S.tileMode = S.tileMode or "paint"
  local mw = (w - 12 * s) / 3
  for i, m in ipairs(MODES) do
    if Kit.chip(x + (i - 1) * (mw + 6 * s), fy, mw, 26 * s, m.label,
                S.tileMode == m.id) then
      S.tileMode = m.id
    end
  end
  fy = fy + 26 * s + 6 * s

  -- HOW MUCH ONE CLICK PAINTS. A cell is the 16x16 square everything else in
  -- this editor works in and is what a click is pointing at; a block is the
  -- 32x32 unit the map is stored in, and painting one is four cells at once,
  -- snapped to the block grid. Cell is the default because it is what the
  -- pointer means -- block is there for laying ground in bulk.
  S.tileGrain = S.tileGrain or "cell"
  local gw = (w - 6 * s) / 2
  if Kit.chip(x, fy, gw, 24 * s, "CELL 16px", S.tileGrain == "cell") then
    S.tileGrain = "cell"
    -- A block picked at BLOCK grain carries no quadrant, and the palette
    -- highlights one as soon as the grain says cells.  Seeding it here keeps
    -- the ring and the brush saying the same thing on the first click after a
    -- switch, instead of highlighting the north-west corner while painting
    -- whichever corner the destination happened to match.
    S.tilePickQ = S.tilePickQ or 0
  end
  if Kit.chip(x + gw + 6 * s, fy, gw, 24 * s, "BLOCK 32px",
              S.tileGrain == "block") then
    S.tileGrain = "block"
  end
  fy = fy + 24 * s + 8 * s

  -- ----------------------------------------------------------- COLOURS
  --
  -- The same setting the launcher calls COLORS, reachable from where the
  -- colours are. Every mode bakes its own atlas -- the palette, the viewport
  -- and the game all read `PaletteFX.mode` -- so switching here is a real
  -- preview of what the map will look like, not an editor-only tint.
  --
  -- IT DROPS THE BAKES. `TileRenderer` caches an atlas per (image, mode) and
  -- the built Map holds the one it was given, so a mode changed without an
  -- evict is a setting that appears to do nothing until the next map switch.
  do
    local okP, PaletteFX = pcall(require, "src.render.PaletteFX")
    if okP and type(PaletteFX) == "table" and PaletteFX.MODES then
      local cur = PaletteFX.mode
      local label = (PaletteFX.MODE_LABELS or {})[cur] or tostring(cur)
      Kit.text("small", "COLOURS", x, fy + 7 * s, PAL.muted)
      if Kit.button(x + 66 * s, fy, w - 66 * s, btnH, label,
                    { font = "small" }) then
        local at = 1
        for i, m in ipairs(PaletteFX.MODES) do if m == cur then at = i end end
        PaletteFX.mode = PaletteFX.MODES[(at % #PaletteFX.MODES) + 1]
        -- every cache that holds a baked colour
        pcall(function() require("src.render.Assets").invalidate() end)
        pcall(function() require("src.world.MapLoader").evict(S.mapId) end)
        pcall(function()
          require("tools.map-editor.panels.Preview").forgetSprites()
        end)
        S.pv3DKey, S._pvCenteredFor = nil, S.mapId
        S.tileNotice = "colours: "
          .. ((PaletteFX.MODE_LABELS or {})[PaletteFX.mode] or PaletteFX.mode)
      end
      fy = fy + btnH + 6 * s
    end
  end

  local total = blockCount(srcTs)
  if total == 0 then
    Kit.text("small", "this tileset has no block table", x, fy)
    return
  end

  -- THE PALETTE. Sized so a swatch is readable rather than so the most fit:
  -- these are 32px drawings and at 1x they are thumbnails of thumbnails.
  local zoom = math.max(1, math.min(3, S.tileZoom or 2))
  S.tileZoom = zoom
  local sw = BLOCK * zoom * s
  local gap = 4 * s
  -- Recomputed below once the scroll rail's width is known: a rail drawn over
  -- the last column would make that column unclickable.
  local cols = math.max(1, math.floor((w + gap) / (sw + gap)))
  local rows = math.ceil(total / cols)

  local QNAME = { [0] = "NW", "NE", "SW", "SE" }
  Kit.text("small", (S.tileGrain == "cell" and S.tilePick and S.tilePickQ)
           and string.format("%d blocks  -  block %d, %s cell", total,
                 S.tilePick, QNAME[S.tilePickQ] or "?")
           or string.format("%d blocks  -  block %s", total,
                 tostring(S.tilePick or "none")), x, fy, PAL.muted)
  if Kit.button(x + w - 60 * s, fy - 6 * s, 26 * s, 22 * s, "-",
                { font = "small" }) then
    S.tileZoom = math.max(1, zoom - 1)
  end
  if Kit.button(x + w - 30 * s, fy - 6 * s, 26 * s, 22 * s, "+",
                { font = "small" }) then
    S.tileZoom = math.min(3, zoom + 1)
  end
  fy = fy + 18 * s

  -- THE FOOTER IS MEASURED BEFORE THE PALETTE, NOT DRAWN OVER IT.
  --
  -- The palette used to take the whole column -- `bodyH = (y + h) - fy` -- and
  -- then the ADD button and the notice were painted at `y + h - 30` and
  -- `y + h - 46`, on top of it. Kit has no z-order, so "on top" is "drawn
  -- last" and the button's hit test runs after the swatches': the bottom band
  -- of the palette was covered by a button and every click in it went to the
  -- button. The last row of blocks was visible and unselectable, which is
  -- exactly what "cut off at the bottom" looks like from outside.
  --
  -- So the footer's height comes out of the body's before either is drawn, and
  -- the two no longer overlap at all.
  local noticeH = S.tileNotice and (18 * s) or 0
  local addH = (foreign and not added) and (30 * s + 6 * s) or 0
  local railW = 6 * s
  local footerH = noticeH + addH
  local bodyH = (y + h) - fy - footerH
  -- A drawer can be short enough that nothing fits. One row is still better
  -- than a negative height, which clips to nothing and looks like a palette
  -- that failed to load.
  if bodyH < sw then bodyH = math.max(sw, (y + h) - fy - noticeH) end

  -- THE RAIL TAKES ITS WIDTH OUT OF THE COLUMN TOO, for the same reason: a
  -- rail drawn over the rightmost swatch makes that swatch unclickable in the
  -- same way the button did.
  local hasRail = rows * (sw + gap) - gap > bodyH
  local availW = hasRail and (w - railW - 4 * s) or w
  cols = math.max(1, math.floor((availW + gap) / (sw + gap)))
  rows = math.ceil(total / cols)

  local perPage = math.max(1, math.floor((bodyH + gap) / (sw + gap)))
  local maxRow = math.max(0, rows - perPage)
  S.tileScroll = math.max(0, math.min(S.tileScroll or 0, maxRow))

  local image = atlasFor(S, srcTs, srcId)

  Kit.pushClip(x, fy, availW, bodyH)
  for row = 0, perPage - 1 do
    for col = 0, cols - 1 do
      local idx = (row + S.tileScroll) * cols + col
      if idx < total then
        local bxp = x + col * (sw + gap)
        local byp = fy + row * (sw + gap)
        if image then
          love.graphics.setColor(1, 1, 1, 1)
          -- ONE scale, not two. A block is 32 world pixels and the swatch is
          -- `BLOCK * zoom * s`, so the pixel scale is `zoom * s` -- passing
          -- `4 * zoom * s` drew every block at four times its swatch, so each
          -- one covered the fifteen around it and the palette came out
          -- scrambled. The 4 was the block's width in TILES, which is not a
          -- scale factor, it is already in the loop that lays the tiles out.
          drawBlock(srcTs, image, idx, bxp, byp, zoom * s)
        else
          love.graphics.setColor(1, 1, 1, 0.08)
          love.graphics.rectangle("fill", bxp, byp, sw, sw)
        end
        -- WHAT IS SELECTED IS WHAT WILL BE PAINTED, and at CELL grain that
        -- is a 16px quadrant, not the 32px block around it.  The palette used
        -- to ring the whole block while a click painted one cell of it -- so
        -- the selection said 2x2 and the brush laid 1x1, and which quarter of
        -- the ring you actually got was decided by the destination's parity
        -- rather than by anything you pointed at.
        -- CELL GRAIN WORKS FROM AN ADDED TILESET TOO. It was disabled for
        -- anything foreign because foreign meant "you may copy one whole
        -- block through a button"; a tileset the map has added is a palette
        -- like any other and the 16px brush is the point of having one.
        local cellGrain = (S.tileGrain == "cell") and (added or not foreign)
        local selected
        if foreign then
          local ps = S.tilePickSrc
          selected = (ps ~= nil) and ps.ts == srcId and ps.block == idx
        else
          selected = (S.tilePickSrc == nil) and S.tilePick == idx
        end
        if selected and cellGrain then
          local q = S.tilePickQ or 0
          local hw = sw / 2
          local qx0 = bxp + (q % 2) * hw
          local qy0 = byp + math.floor(q / 2) * hw
          love.graphics.setColor(0.24, 0.88, 0.54, 0.22)
          love.graphics.rectangle("fill", qx0, qy0, hw, hw)
          love.graphics.setColor(0.24, 0.88, 0.54, 1)
          love.graphics.setLineWidth(2)
          love.graphics.rectangle("line", qx0, qy0, hw, hw)
          love.graphics.setLineWidth(1)
          -- and a faint ring on the block it came out of, so the drawing the
          -- quadrant belongs to is still findable in a wall of swatches
          love.graphics.setColor(0.24, 0.88, 0.54, 0.35)
          love.graphics.rectangle("line", bxp - 1, byp - 1, sw + 2, sw + 2)
        elseif selected then
          love.graphics.setColor(0.24, 0.88, 0.54, 1)
          love.graphics.setLineWidth(2)
          love.graphics.rectangle("line", bxp - 1, byp - 1, sw + 2, sw + 2)
          love.graphics.setLineWidth(1)
        end
        love.graphics.setColor(1, 1, 1, 1)
        if cellGrain then
          -- FOUR HIT TARGETS PER SWATCH.  One press test per quadrant, in the
          -- same order the slots are numbered, so the quadrant that lights up
          -- is the one under the pointer.
          local hw = sw / 2
          for q = 0, 3 do
            local qx0 = bxp + (q % 2) * hw
            local qy0 = byp + math.floor(q / 2) * hw
            if Kit.press(qx0, qy0, hw, hw) then
              pickFrom(S, srcId, idx, q, foreign, added)
            end
          end
        elseif Kit.press(bxp, byp, sw, sw) then
          -- BLOCK grain has no quadrant: clearing it is what makes a later
          -- switch back to CELL start from the block rather than from a corner
          -- nobody chose this time round.
          pickFrom(S, srcId, idx, nil, foreign, added)
        end
      end
    end
  end
  Kit.popClip()

  -- HOW MUCH MORE THERE IS, and where in it you are. Without this the only way
  -- to find out the palette scrolls is to try -- and a tileset of two hundred
  -- blocks shows a dozen, so "these are all of them" is the natural reading.
  if hasRail and maxRow > 0 then
    local rx = x + w - railW
    love.graphics.setColor(1, 1, 1, 0.10)
    love.graphics.rectangle("fill", rx, fy, railW, bodyH, railW / 2, railW / 2)
    local frac = perPage / rows
    local thumbH = math.max(20 * s, bodyH * frac)
    local at = (maxRow > 0) and (S.tileScroll / maxRow) or 0
    love.graphics.setColor(1, 1, 1, 0.34)
    love.graphics.rectangle("fill", rx, fy + at * (bodyH - thumbH), railW,
                            thumbH, railW / 2, railW / 2)
    love.graphics.setColor(1, 1, 1, 1)
  end
  local fyBottom = fy + bodyH + 4 * s

  -- ADDING THE WHOLE TILESET WITHOUT PICKING A BLOCK FIRST, for the reader who
  -- knows what they want before they have found it. The per-block question
  -- covers the discovery case; this covers the deliberate one, and both end at
  -- the same list.
  if foreign and not added then
    local bh = 30 * s
    local byy = fyBottom + noticeH
    if Kit.button(x, byy, w, bh,
                  "ADD " .. tostring(srcId) .. " TO THIS MAP",
                  { font = "small", kind = "accent" }) then
      local okAdd, why = MapEdits.addMapTileset(store(S), game(S), S.mapId,
                                                srcId, ownId)
      if okAdd then
        markEdited(S)
        S.tileNotice = tostring(srcId) .. " added - paint from it freely"
      else
        S.tileNotice = tostring(why)
      end
    end
  end

  if S.tileNotice then
    -- WRAPPED, NOT CLIPPED. The notices that matter here are the ones that
    -- explain why a borrow failed, and those name a path and a size -- an
    -- ellipsis two thirds of the way through turns the one sentence that could
    -- have been acted on into a shrug.
    local lines = Kit.wrap("small", S.tileNotice, w)
    for i = 1, math.min(3, #lines) do
      Kit.text("small", lines[i], x, fyBottom + (i - 1) * 14 * s, PAL.yellow)
    end
  end
end

function Tiles.wheelmoved(S, dy)
  -- AN OPEN LIST OWNS THE WHEEL. Scrolling the palette underneath while the
  -- tileset list is up moves the thing you are not looking at.
  if S.tileSourceOpen then
    S.tileSourceScroll = math.max(0, (S.tileSourceScroll or 0) - (dy or 0))
    return
  end
  S.tileScroll = math.max(0, (S.tileScroll or 0) - (dy or 0))
end

function Tiles.keypressed(S, key)
  if key == "b" then S.tileMode = "paint" end
  if key == "f" then S.tileMode = "fill" end
  if key == "i" then S.tileMode = "pick" end
end

return Tiles
