-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Borrowed tiles and minted blocks: the shared applier.
--
-- WHY THIS IS IN src/ AND NOT WITH THE MAP EDITOR, which is where it was
-- written and where its only caller lived.
--
-- Painting a tree from another tileset does not put a tree in the map. It
-- BORROWS THE PIXELS: the source tiles are appended to the destination
-- tileset's atlas, a new block is minted pointing at where they landed, and
-- the map stores that block's ID. Everything visible about the edit is in the
-- tileset; the map holds a number.
--
-- So an exported map pack that carries only maps carries nothing. The receiving
-- machine has the cartridge's tileset, block 212 does not exist in it, and
-- `Map:tileAt` falls back to the border block -- the reported "the trees I
-- added come out as something else", and, for a map built entirely out of
-- minted blocks, "the map is not there at all".
--
-- The fix cannot be to ship the extended atlas: that is cartridge art, and the
-- same rule the repository applies to itself applies to anything one player
-- hands another. So the pack carries the RECIPE -- which tileset each tile came
-- from and which block was minted out of them -- and the receiving machine
-- rebuilds the identical result from its OWN extraction. Which means this code
-- has to be reachable from a running mod, and `tools/` is not in a player
-- build. Exactly the argument that put AdoptedTileset here; see its header.
--
-- MapEdits keeps the store and the editing; this owns the applying, and both
-- callers get the same one.

local BorrowedTiles = {}

BorrowedTiles.MINT_PREFIX = "MINT:"

function BorrowedTiles.mintKey(tilesetId, n)
  return string.format("%s%s:%d", BorrowedTiles.MINT_PREFIX,
                       tostring(tilesetId), n)
end

local function tileCapacity(ts)
  local w = math.floor((ts.imageWidth or 128) / 8)
  local h = math.floor((ts.imageHeight or 128) / 8)
  return math.max(0, w * h), math.max(1, w)
end

BorrowedTiles.tileCapacity = tileCapacity

-- Where the borrowed tiles land, and how much taller the atlas has to be.
--
-- Pure arithmetic, separated from the image work so it can be tested without a
-- GPU or a filesystem -- which is the half that has been wrong before.
function BorrowedTiles.borrowLayout(ts, count)
  local base, perRow = tileCapacity(ts)
  local rows = math.ceil((count or 0) / perRow)
  return base, perRow, rows, (ts.imageHeight or 128) + rows * 8
end

-- Resolve a minted block's negative slots against a live tileset.
function BorrowedTiles.resolveBorrowed(tiles, base)
  local out = {}
  for i = 1, 16 do
    local v = tiles[i] or 0
    out[i] = (v < 0) and (base + (-v) - 1) or v
  end
  return out
end

-- THE ATLAS EXTENSION, done once per tileset before anything is minted.
--
-- Builds a taller copy of the tileset's atlas with the borrowed tiles appended
-- and points the tileset at it. Everything about this is guarded: it needs
-- love.image, it reads two files and writes a third, and on a headless run or
-- a read-only install any of that can fail -- in which case the borrow simply
-- does not resolve and is reported, rather than the map load dying.
--
-- WRITTEN TO ITS OWN PATH, never over the extractor's output: that tree is
-- rebuilt from the cartridge on every import, so an atlas written there would
-- be destroyed by the next one -- silently, which is the failure this whole
-- store exists to avoid.
local function extendAtlas(game, tilesetId, ts, borrowed, tilesets)
  if not (love and love.image and love.image.newImageData) then
    return nil, tilesetId .. ": no image support to copy borrowed art with"
  end

  local Assets = require("src.render.Assets")

  -- ALWAYS REBUILT FROM THE ORIGINAL ATLAS, NEVER FROM THE LAST EXTENSION.
  --
  -- This read `ts.image` -- which after one borrow is the extended atlas -- and
  -- appended to THAT, taking its base from the extended height. So every
  -- borrow copied all the previous borrows forward again and moved the base
  -- past them, the file grew by the whole set each time, and the rows the
  -- earlier mints were resolved against were left behind as orphans.
  --
  -- The original path and its tile capacity are stamped on the live tileset
  -- the first time through, so `base` is a fixed number for the life of this
  -- import and a minted block resolved last week still names the same row.
  if ts._borrowSrc == nil then
    ts._borrowSrc = ts.image
    ts._borrowSrcH = ts.imageHeight
  end
  local srcH = ts._borrowSrcH or ts.imageHeight
  local perRow = math.max(1, math.floor((ts.imageWidth or 128) / 8))
  local base = math.max(0, math.floor((ts.imageWidth or 128) / 8)
                            * math.floor((srcH or 128) / 8))
  local rows = math.ceil(#borrowed / perRow)
  if rows <= 0 then return base end
  local newH = (srcH or 128) + rows * 8

  local okSrc, atlas = pcall(Assets.imageData, ts._borrowSrc)
  if not (okSrc and atlas) then
    return nil, tilesetId .. ": its own atlas could not be read"
  end
  local w = atlas:getWidth()

  -- THE SOURCE HAS TO BE THE SOURCE, and `Assets.imageData` will not tell you
  -- when it is not.
  --
  -- A path it cannot open does not return nil -- it returns the PLACEHOLDER,
  -- which is 16x16. Every guard below is written against `w`, so a placeholder
  -- silently produced a 16-pixel-wide atlas: every paste failed its bounds
  -- check, nothing was copied, and the tileset was left claiming 128. The art
  -- was simply absent, which on screen is a black square.
  --
  -- The record knows how wide its own atlas is. If the decode disagrees, the
  -- decode is not this tileset and there is nothing to copy into.
  local claimW = tonumber(ts.imageWidth)
  if claimW and math.abs(atlas:getWidth() - claimW) > 0 then
    return nil, string.format(
      "%s: its atlas read back as %dx%d but the tileset says %dx%s - the "
      .. "image at %s could not be opened",
      tilesetId, atlas:getWidth(), atlas:getHeight(), claimW,
      tostring(ts._borrowSrcH or ts.imageHeight), tostring(ts._borrowSrc))
  end

  local okNew, out = pcall(love.image.newImageData, w, newH)
  if not (okNew and out) then
    return nil, tilesetId .. ": a taller atlas could not be made"
  end
  out:paste(atlas, 0, 0, 0, 0, w, atlas:getHeight())

  for i, e in ipairs(borrowed) do
    local from = tilesets[e.from]
    if from and from.image then
      local okF, fd = pcall(Assets.imageData, from.image)
      if okF and fd then
        local fw = math.floor(fd:getWidth() / 8)
        local sx = (e.tile % math.max(1, fw)) * 8
        local sy = math.floor(e.tile / math.max(1, fw)) * 8
        local idx = base + i - 1
        local dx = (idx % perRow) * 8
        local dy = math.floor(idx / perRow) * 8
        if sx + 8 <= fd:getWidth() and sy + 8 <= fd:getHeight()
           and dx + 8 <= w and dy + 8 <= newH then
          pcall(out.paste, out, fd, dx, dy, sx, sy, 8, 8)
        end
      end
    end
  end

  -- ------------------------------------------------------ AND THE PALETTE
  --
  -- THE PIXELS ARE ONLY HALF OF WHAT A TILE IS, and the missing half is why a
  -- borrowed block came out a black square with the art plainly in the file.
  --
  -- A Gen 2 atlas is 2bpp GREYSCALE. Colour arrives at bake time: `palMap`
  -- gives a palette row per tile graphic and `palColors` holds the rows, and
  -- `TileRenderer.gen2TileColors` reads `palMap[tile + 1] or 0`. A tile
  -- appended past the end of `palMap` therefore takes row **0** -- not no
  -- colour, row zero -- and row zero of a Gen 2 tileset is the dark grey the
  -- text box is drawn in. Forest art recoloured through Johto's row zero is a
  -- black square, exactly as reported, and nothing about it looks like a
  -- palette problem because the greyscale atlas underneath is perfect.
  --
  -- So the row comes across with the pixels. Not the row NUMBER -- palette
  -- rows are per tileset and Johto's row 3 is not Forest's row 3 -- the actual
  -- COLOURS, appended to this tileset's own list and pointed at by the new
  -- `palMap` entry.
  --
  -- EVERY TIME-OF-DAY TABLE MOVES IN STEP, because one `palMap` value has to
  -- name the same row in all of them: append to MORN and not to NITE and the
  -- tile is right until dusk.
  if type(ts.palMap) == "table" then
    -- Rebuilt from the stamp each time for the same reason the image is: a
    -- second borrow must not append the first borrow's rows again.
    if ts._borrowPalMap == nil then
      local copy = {}
      for k, v in pairs(ts.palMap) do copy[k] = v end
      ts._borrowPalMap = copy
      local rows = {}
      if type(ts.palColors) == "table" then
        rows.palColors = #ts.palColors
      end
      if type(ts.palColorsByTod) == "table" then
        rows.byTod = {}
        for tod, list in pairs(ts.palColorsByTod) do
          if type(list) == "table" then rows.byTod[tod] = #list end
        end
      end
      ts._borrowPalLen = rows
    end
    local palMap = {}
    for k, v in pairs(ts._borrowPalMap) do palMap[k] = v end
    local lens = ts._borrowPalLen or {}

    -- Truncate the colour lists back to what the tileset had before any
    -- borrowing, then append this round's rows.
    local function trim(list, n)
      if type(list) ~= "table" or n == nil then return list end
      for i = #list, n + 1, -1 do list[i] = nil end
      return list
    end
    trim(ts.palColors, lens.palColors)
    for tod, n in pairs(lens.byTod or {}) do
      trim(ts.palColorsByTod and ts.palColorsByTod[tod], n)
    end

    local palFailed = nil
    for i, e in ipairs(borrowed) do
      local from = tilesets[e.from]
      -- ROW ZERO IS NOT A NEUTRAL DEFAULT, IT IS THE GREY ONE.
      --
      -- Every fallback in this loop lands on row 0 of one tileset or the
      -- other, and in a Gen 2 tileset row 0 is the grey the text box is drawn
      -- in -- 222,255,222 / 172,172,172 / 106,106,106. So a source lookup that
      -- quietly missed did not produce "some wrong colour", it produced a tile
      -- in black and white, which is exactly the symptom that sent four rounds
      -- of this looking at the ART.
      --
      -- Counted and reported, so a miss says so instead of drawing greys.
      local srcRow = nil
      if type(from) == "table" and type(from.palMap) == "table" then
        srcRow = from.palMap[e.tile + 1]
      end
      if srcRow == nil then
        palFailed = palFailed or {}
        palFailed[#palFailed + 1] = string.format("%s tile %s",
          tostring(e.from), tostring(e.tile))
        srcRow = 0
      end
      -- The row index this tile will take here: the same in every list,
      -- because `palMap` carries one number for all of them.
      local at = nil
      if type(ts.palColors) == "table" then
        local src = type(from) == "table" and from.palColors or nil
        local row = src and src[math.min(srcRow, #src - 1) + 1] or nil
        ts.palColors[#ts.palColors + 1] = row or ts.palColors[1]
        at = #ts.palColors - 1
      end
      if type(ts.palColorsByTod) == "table" then
        for tod, list in pairs(ts.palColorsByTod) do
          if type(list) == "table" then
            local srcList = (type(from) == "table"
                             and type(from.palColorsByTod) == "table"
                             and from.palColorsByTod[tod])
              or (type(from) == "table" and from.palColors) or nil
            local row = srcList
              and srcList[math.min(srcRow, #srcList - 1) + 1] or nil
            list[#list + 1] = row or list[1]
            at = at or (#list - 1)
          end
        end
      end
      if at then palMap[base + i] = at end
    end

    -- THE PADDING AT THE END OF THE LAST ROW.
    --
    -- The atlas grows by whole 8-pixel ROWS -- 17 borrowed tiles is two rows,
    -- which is 32 slots -- so the tail of the last row is empty space with no
    -- palette entry behind it. `gen2TileColors` reads `palMap[tile + 1] or 0`,
    -- and row 0 of a Gen 2 tileset is the text-box grey, so those slots bake
    -- as grey squares. Nothing should ever reference them, and "should" is the
    -- word that has cost this bug five rounds.
    --
    -- Filled explicitly, to the full tile count of the image that was just
    -- written. It costs a handful of integers and it means no tile anywhere in
    -- this atlas can fall off the end of the map that colours it.
    local slots = math.max(0, math.floor(w / 8) * math.floor(newH / 8))
    for t = base + #borrowed, slots - 1 do
      if palMap[t + 1] == nil then palMap[t + 1] = 0 end
    end

    ts.palMap = palMap
    -- AND THE DERIVED COPY OF IT, which is a different table with a different
    -- reader.  `Data:publishGen2Palettes` builds `tileset.tilePalettes` --
    -- palMap plus one, so a reader can index it without knowing about the ROM
    -- nibble -- and it built it ONCE, at boot, guarded on `== nil`.  Growing
    -- palMap here left that copy at its old length, and the voxel path reads
    -- only the copy: every borrowed tile fell off the end, and a missing slot
    -- reads as slot 1, which is the TEXT palette.  Flat grey, in 3D only,
    -- while the same tile was correct in the flat view two feet away.
    --
    -- Dropped rather than extended in place: the publisher owns the shape of
    -- that table and now rebuilds whenever it is short, so the honest move is
    -- to say "this is stale" and let it be rebuilt from the one source of
    -- truth.
    ts.tilePalettes = nil
    pcall(function()
      local Data = require("src.core.Data")
      if type(Data.publishGen2Palettes) == "function" then
        Data:publishGen2Palettes()
      end
    end)
    if palFailed then
      pcall(function()
        require("src.core.Logger").warn(
          "borrow: %d of %d tiles had no palette row in their own tileset and "
          .. "fell back to grey (%s) - the source tileset was not reachable "
          .. "from this import", #palFailed, #borrowed, tilesetId,
          table.concat(palFailed, ", ", 1, math.min(4, #palFailed)))
      end)
    end
  end

  -- A NEW FILENAME FOR EVERY VERSION OF THE ATLAS, and this is not tidiness.
  --
  -- `Assets.image` caches by path and so does TileRenderer's own `imageCache`,
  -- and the baked atlases are keyed on the path underneath them. Writing every
  -- extension to the same filename meant the second borrow wrote taller pixels
  -- to a path every cache in the renderer had already answered for -- so the
  -- new block's tiles pointed at rows that existed in the FILE and not in the
  -- Image anyone was drawing from. Nothing is there to draw, so it comes out
  -- as a black square.
  --
  -- The count of borrowed tiles names the version: it only ever goes up, and
  -- it is exactly what changed.
  local path = string.format("editor/atlas/%s_%s_%d.png", tostring(game),
                             tostring(tilesetId), #borrowed)
  pcall(function()
    if love.filesystem and love.filesystem.createDirectory then
      love.filesystem.createDirectory("editor/atlas")
    end
  end)
  local okEnc, encErr = pcall(function() out:encode("png", path) end)
  if not okEnc then
    -- The REASON, not just the fact: "could not be written" is a read-only
    -- install, a full disk and a missing directory wearing one sentence, and
    -- only one of them is something the reader can do anything about.
    return nil, string.format("%s: the extended atlas could not be written to "
      .. "%s (%s)", tilesetId, path, tostring(encErr))
  end
  -- Only NOW is the tileset repointed: a half-written atlas that the renderer
  -- is already reading from is worse than the original one.
  ts.image = path
  ts.imageHeight = newH

  -- AND THE CACHES THAT ANSWERED FOR THIS TILESET A MOMENT AGO. The new path
  -- misses them by itself, which is the point of the name above -- but the map
  -- being edited holds a renderer built against the OLD one, and it will go on
  -- drawing from it until something says otherwise.
  pcall(function() require("src.render.TileRenderer").invalidate() end)

  -- AND THE VOXEL MOD'S SHAPE TABLE, which is the one that was still stale --
  -- and is why a borrowed tile was correct in the flat view and a black
  -- rectangle in the 3D one.
  --
  -- `TileShape.forMap` caches its resolved shapes by TILESET ID, and a borrow
  -- does not change the id: `TilesetJohtoModern` is still
  -- `TilesetJohtoModern`, sixteen tiles longer. So the mod went on answering
  -- from a table built when the atlas had 192 tiles, and the tile at 192 had
  -- no shape at all. `Structures` then floods its drawings from that table, so
  -- the new tile was in no structure either -- and what the mesher had left to
  -- draw was a quad with nothing behind it.
  --
  -- `invalidateAll` rather than `invalidate(mapId)`: the per-map call drops
  -- Structures and ChunkMesher, and TileShape's cache is not per map. This is
  -- exactly the case that function's own comment describes -- a change to the
  -- mod's data rather than to a map -- and a tileset growing is that.
  pcall(function()
    require("tools.map-editor.ModShapes").invalidateAll()
  end)
  -- WHAT THIS ACTUALLY WROTE, once, where the reader can see it. Five rounds
  -- of this bug were spent on "it should work": every link in the chain reads
  -- correctly in isolation and the picture still came out wrong, which means
  -- the model of what runs when is wrong somewhere source alone will not show.
  -- One line of fact from the running game beats another round of reasoning.
  pcall(function()
    require("src.core.Logger").info(
      "borrow: %s now %dx%d (%s), base tile %d, %d borrowed, palMap %d rows, "
      .. "palColors %d, first borrowed tile %d -> row %s = %s",
      tostring(tilesetId), w, newH, tostring(path), base,
      #borrowed, type(ts.palMap) == "table" and #ts.palMap or -1,
      type(ts.palColors) == "table" and #ts.palColors or -1,
      base,
      tostring(type(ts.palMap) == "table" and ts.palMap[base + 1] or "?"),
      (function()
        -- THE COLOURS THEMSELVES. "row 8" is not checkable by eye; three RGB
        -- triples are -- grey reads as grey at a glance, and that is the whole
        -- question.
        local pm = type(ts.palMap) == "table" and ts.palMap[base + 1]
        local pc = type(ts.palColors) == "table" and ts.palColors
        local row = pm and pc and pc[math.min(pm, #pc - 1) + 1]
        if type(row) ~= "table" then return "?" end
        local out = {}
        for k = 1, math.min(3, #row) do
          local c2 = row[k]
          out[#out + 1] = type(c2) == "table"
            and string.format("%d/%d/%d", c2[1] or 0, c2[2] or 0, c2[3] or 0)
            or tostring(c2)
        end
        return table.concat(out, " ")
      end)())
  end)
  -- The mod's terrain atlas registers itself with Assets, so this reaches it
  -- too; its key is the image path, which has changed, but a stale entry for
  -- the OLD path pins the previous texture alive for nothing.
  pcall(function() require("src.render.Assets").invalidate() end)
  return base
end

-- THE BASE A BORROWED SLOT RESOLVES AGAINST, asked outside an apply.
--
-- `extendAtlas` stamps the ORIGINAL atlas and its height on the live tileset
-- the first time it runs, so the base stays put however many times art is
-- borrowed afterwards. Anything keyed by resolved tile id -- a class pin on a
-- borrowed tree, say -- has to use that same number or it moves the moment
-- anything else is copied in. Before the first extension there is nothing
-- stamped and the current capacity IS the original.
function BorrowedTiles.baseFor(ts)
  if type(ts) ~= "table" then return 0 end
  local w = math.floor((ts.imageWidth or 128) / 8)
  local h = math.floor((ts._borrowSrcH or ts.imageHeight or 128) / 8)
  return math.max(0, w * h)
end

-- ---------------------------------------------------------------- applying
--
-- `spec` is one tileset's edits: { borrowed = { {from, tile}, ... },
-- blocks = { { tiles = {16}, coll = {4} }, ... }, baseBlocks = n }.
--
-- WHY `baseBlocks` IS CHECKED. A minted block's id is the position it lands at
-- when it is appended, so it is only the id the author saw if the tileset was
-- the same length here as it was there. Two machines that imported the same
-- cartridge agree; one that did not, does not -- and the maps in the pack are
-- full of ids that would then point at somebody else's blocks. That draws a
-- map made of wrong art, silently, which is worse than drawing nothing: this
-- refuses the tileset and says which one, and the maps fall back to the
-- cartridge's own blocks.
--
-- Absent on a pack exported before the field existed, and skipped then --
-- those packs were already being applied unchecked.
function BorrowedTiles.applyOne(game, tilesetId, ts, spec, tilesets)
  local ids, stale = {}, nil
  local function note(msg)
    stale = stale or {}
    stale[#stale + 1] = msg
  end
  if not ts or type(ts.blocks) ~= "table" then
    note(tilesetId .. ": tileset is not in this import")
    return ids, stale
  end
  if type(spec.baseBlocks) == "number" then
    -- The count BEFORE this session's mints, which is what the author's
    -- `baseBlocks` was measured against too.
    local mine = #ts.blocks
    for _ in pairs(ts._mintedAt or {}) do mine = mine - 1 end
    if mine ~= spec.baseBlocks then
      note(string.format(
        "%s: this cartridge's tileset has %d blocks and the pack was built "
        .. "against %d - its copied art was left out rather than drawn from "
        .. "the wrong rows", tilesetId, mine, spec.baseBlocks))
      return ids, stale
    end
  end

  -- BEFORE the blocks: a minted block may name a borrowed tile by slot,
  -- and the index that resolves to does not exist until the atlas has
  -- actually grown.
  local base, borrowFailed = nil, nil
  if spec.borrowed and #spec.borrowed > 0 then
    base, borrowFailed = extendAtlas(game, tilesetId, ts, spec.borrowed,
                                     tilesets)
    if not base then note(tostring(borrowFailed)) end
  end

  ts._mintedAt = ts._mintedAt or {}
  for i, minted in ipairs(spec.blocks or {}) do
    local needsBase = false
    for k = 1, 16 do
      if ((minted.tiles or {})[k] or 0) < 0 then needsBase = true break end
    end
    if needsBase and base == nil then
      note(string.format(
        "%s: a block using copied art was left out - the atlas could not "
        .. "be extended", tilesetId))
      goto continueMint
    end
    local copy = BorrowedTiles.resolveBorrowed(minted.tiles or {}, base or 0)
    local key = BorrowedTiles.mintKey(tilesetId, i)
    local id = ts._mintedAt[key]
    if id ~= nil and ts.blocks[id + 1] then
      ts.blocks[id + 1] = copy
    else
      ts.blocks[#ts.blocks + 1] = copy
      id = #ts.blocks - 1              -- block ids are 0-based
      ts._mintedAt[key] = id
    end
    ids[key] = id
    if type(ts.collision) == "table" then
      for q = 1, 4 do
        ts.collision[id * 4 + q] = (minted.coll and minted.coll[q]) or 0
      end
    end
    ::continueMint::
  end
  return ids, stale
end

-- The class pins one tileset's recipe carries, as { [tileId] = class }.
--
-- Separate from applyOne because they do not go onto the TILESET -- nothing
-- reads them there. TileShape is handed a map and resolves against
-- `def.voxelClassPins`, so the pins have to be laid on every map drawn with
-- this tileset, which only the caller knows.
function BorrowedTiles.pinsOf(spec)
  if type(spec) ~= "table" or type(spec.pins) ~= "table" then return nil end
  local out, any = {}, false
  for tile, cls in pairs(spec.pins) do
    local id = tonumber(tile)
    if id and type(cls) == "string" and cls ~= "" then
      out[id] = cls
      any = true
    end
  end
  return any and out or nil
end

-- Every tileset in `spec`, against the live `tilesets` table. Returns
-- key -> block id and a list of reasons, exactly as the editor's own applier
-- always has.
function BorrowedTiles.apply(game, spec, tilesets)
  local ids, stale = {}, nil
  if not (type(spec) == "table" and type(tilesets) == "table") then
    return ids, stale
  end
  local pins = nil
  for tilesetId, one in pairs(spec) do
    if type(one) == "table" then
      local got, why = BorrowedTiles.applyOne(game, tilesetId,
                                              tilesets[tilesetId], one, tilesets)
      for k, v in pairs(got) do ids[k] = v end
      if why then
        stale = stale or {}
        for _, m in ipairs(why) do stale[#stale + 1] = m end
      end
      local p = BorrowedTiles.pinsOf(one)
      if p then
        pins = pins or {}
        pins[tilesetId] = p
      end
    end
  end
  return ids, stale, pins
end

return BorrowedTiles
