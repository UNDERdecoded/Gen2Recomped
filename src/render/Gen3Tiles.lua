-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen3 metatile compositing.
--
-- A Gen 1 or Gen 2 block is 4x4 tiles out of one tileset with one palette map
-- and no flipping, so the renderer can bake a single atlas once and blit 8x8
-- quads out of it.  A Gen 3 metatile is none of those things:
--
--   * it is 16x16 -- 2x2 tiles, not 4x4 -- so a metatile is the engine's CELL,
--     not its block;
--   * it has TWO LAYERS of those 2x2 tiles, and the player walks between them,
--     which is what puts a sprite behind a treetop;
--   * every one of the eight tile entries carries its own PALETTE and its own
--     horizontal and vertical flip;
--   * and it draws out of TWO tilesets at once -- the map's primary and its
--     secondary -- with a separate bank boundary for tiles, for metatiles and
--     for palettes.
--
-- Those three boundaries are the trap.  They are plain constants with nothing
-- in the cartridge header to announce them, and the palette one fails
-- silently: palette slot 6 read out of the primary bank is sixteen zero words,
-- so a wrong boundary renders every wall in Littleroot solid black while the
-- roofs directly above them stay perfect.  tools/gen3_discover.py derives all
-- three from the cartridge -- a primary tileset is by definition the one whose
-- metatiles never reach into the other bank, and 14 secondaries independently
-- begin their palettes at exactly slot 6 -- and this module reads them from
-- the manifest rather than restating them.
--
-- Index 0 is transparent on BOTH layers.  What shows through is the backdrop,
-- which is palette 0 colour 0.

local Gen3Tiles = {}
Gen3Tiles.__index = Gen3Tiles

-- Defaults matching Emerald, overridden from the manifest's layout block.
local DEFAULTS = {
  tilesInPrimary = 512,
  metatilesInPrimary = 512,
  palettesInPrimary = 6,
  metatileLayers = 2,
}

local byte = string.byte

-- pair = { primary = <tileset record>, secondary = <tileset record or nil> }
-- layout = the manifest's layout table (optional; defaults above are Emerald's)
function Gen3Tiles.new(pair, layout)
  layout = layout or {}
  local self = setmetatable({
    primary = pair.primary,
    secondary = pair.secondary,
    tilesInPrimary = tonumber(layout.tilesInPrimary) or DEFAULTS.tilesInPrimary,
    metatilesInPrimary = tonumber(layout.metatilesInPrimary)
      or DEFAULTS.metatilesInPrimary,
    palettesInPrimary = tonumber(layout.palettesInPrimary)
      or DEFAULTS.palettesInPrimary,
    layers = tonumber(layout.metatileLayers) or DEFAULTS.metatileLayers,
    tileCache = {},
  }, Gen3Tiles)
  return self
end

-- Which record owns a given tile / metatile / palette index, and its index
-- within that record.  One place, because getting any of the three wrong is
-- the failure this module exists to prevent.
function Gen3Tiles:tileBank(index)
  if index < self.tilesInPrimary then return self.primary, index end
  return self.secondary or self.primary, index - self.tilesInPrimary
end

function Gen3Tiles:metatileBank(index)
  if index < self.metatilesInPrimary then return self.primary, index end
  return self.secondary or self.primary, index - self.metatilesInPrimary
end

function Gen3Tiles:paletteBank(index)
  if index < self.palettesInPrimary then return self.primary, index end
  return self.secondary or self.primary, index
end

-- ---------------------------------------------------------------------------
-- ANIMATED TILES
--
-- THE SEA OUTSIDE DEWFORD, THE FLOWER BEDS ON ROUTE 104, THE SHORE RIPPLE
-- ALONG PETALBURG'S BEACH -- all frozen, in 2D and in 3D alike, because the
-- cartridge animates them by a mechanism nothing in this port had a shape for.
--
-- A Game Boy tileset animates by declaring a TILE SLOT and a set of frames:
-- water tile $14 is rotated a pixel a step, flower tile $03 is swapped between
-- three little images.  TileRenderer models that directly, and the model is
-- "the atlas cell at id N shows image F this step".
--
-- Emerald does not have an atlas.  Each tileset carries an animation CALLBACK
-- that, on a timer, DMAs a run of raw 4bpp tiles into VRAM -- `general` writes
-- 30 tiles at index 432 (the sea and its shore), 10 at 464 (the sand/water
-- edge) and 2 at 508 (the flowers), each with its own frame count.  So the
-- unit is not a cell in a sheet, it is a RUN OF TILE GRAPHICS, and every
-- metatile that happens to reference one of those tiles changes with it.  The
-- sea's thirty tiles alone are referenced by 147 metatiles of the 862 in the
-- Route 104 pair; all three runs together reach 148.
--
-- Hence a second declaration rather than a second reading of the first.  A
-- tileset HALF (the record in data/generated/map_tilesets.lua, which is where
-- the tile pixels live) carries:
--
--   tileAnims = { { first = 432,    -- first tile index, BANK-LOCAL
--                   count = 30,     -- consecutive 4bpp tiles rewritten
--                   period = 16,    -- engine frames per step
--                   frames = { "<count*32 bytes>", ... } }, ... }
--
-- `frames` are raw 4bpp INDEX bytes, exactly like the record's own `tiles`
-- string, and deliberately not a pre-coloured PNG: the same tile is drawn
-- under different palettes in different metatiles, so a strip with one palette
-- already applied would be wrong wherever it is reused.
--
-- Every method below is a no-op on a record that carries no `tileAnims`, and
-- every `step` argument defaults to NIL, which means "the static tileset" --
-- so a tileset without the key, and every caller written before this existed,
-- composites byte-for-byte what it composites today.
-- ---------------------------------------------------------------------------

local function gcd(a, b) while b ~= 0 do a, b = b, a % b end return a end

-- The entries of both banks, with `first` lifted into the pair's GLOBAL tile
-- numbering so a caller never has to know which half an index came from.
function Gen3Tiles:animEntries()
  if self._animEntries then return self._animEntries end
  local out = {}
  local function collect(record, base)
    if not (record and type(record.tileAnims) == "table") then return end
    for _, a in ipairs(record.tileAnims) do
      local count = tonumber(a and a.count) or 0
      local frames = a and a.frames
      if count > 0 and type(frames) == "table" and #frames > 0 then
        -- a frame short of its declared run would read past the end of the
        -- string and paint the tail black; drop the entry instead
        local ok = true
        for _, f in ipairs(frames) do
          if type(f) ~= "string" or #f < count * 32 then ok = false end
        end
        if ok then
          out[#out + 1] = {
            first = base + (tonumber(a.first) or 0),
            count = count,
            period = math.max(1, tonumber(a.period) or 16),
            frames = frames,
          }
        end
      end
    end
  end
  collect(self.primary, 0)
  -- the secondary's own tile 0 is the pair's tile `tilesInPrimary`; the
  -- cartridge's DMA index is absolute, so the extractor stores it bank-local
  -- and the shift happens here, in the one place that owns the split
  if self.secondary then collect(self.secondary, self.tilesInPrimary) end
  self._animEntries = out
  return out
end

-- global tile index -> the entry that rewrites it
function Gen3Tiles:animTileMap()
  if self._animTiles then return self._animTiles end
  local out = {}
  for _, e in ipairs(self:animEntries()) do
    for i = 0, e.count - 1 do out[e.first + i] = e end
  end
  self._animTiles = out
  return out
end

-- How many distinct STEPS the pair has before it repeats.
--
-- Entries need not share a frame count or a period -- `general` runs an
-- eight-frame water cycle beside a shorter flower one -- so the pair's cycle
-- is the least common multiple of each entry's own, measured in units of the
-- shortest period.  Capped, because an lcm is free to explode and a hundred
-- baked sheets is a memory leak with a nice explanation.
local MAX_STEPS = 64

function Gen3Tiles:animSteps()
  if self._animSteps then return self._animSteps end
  local entries = self:animEntries()
  local n = 0
  if #entries > 0 then
    local unit = nil
    for _, e in ipairs(entries) do
      unit = (unit == nil or e.period < unit) and e.period or unit
    end
    self._animUnit = unit
    n = 1
    for _, e in ipairs(entries) do
      -- this entry turns over every (period / unit) global steps and has
      -- #frames of them
      local own = #e.frames * math.max(1, math.floor(e.period / unit))
      n = n * own / gcd(n, own)
      if n > MAX_STEPS then n = MAX_STEPS break end
    end
    n = math.floor(n)
  end
  self._animSteps = n
  return n
end

-- engine frames per global step (nil when nothing animates)
function Gen3Tiles:animPeriod()
  self:animSteps()
  return self._animUnit
end

-- Which METATILES change between steps: the ones with an animated tile in any
-- of their eight entries.  This is the set the renderer re-bakes per step, and
-- on the Route 104 pair it is 148 of 862 -- so the overlay costs a sixth of a
-- static bake per step rather than a whole one.
function Gen3Tiles:animMetatiles()
  if self._animMetatiles then return self._animMetatiles end
  local tiles = self:animTileMap()
  local out, n = {}, 0
  if next(tiles) ~= nil then
    for m = 0, self:metatileCount() - 1 do
      for _, e in ipairs(self:entries(m)) do
        if tiles[e.tile] then out[m] = true n = n + 1 break end
      end
    end
  end
  self._animMetatiles = out
  self._animMetatileCount = n
  return out, n
end

function Gen3Tiles:animMetatileCount()
  local _, n = self:animMetatiles()
  return n
end

-- A tile's 64 palette indices.  4bpp, and the LOW nibble is the LEFT pixel --
-- reading the high nibble first mirrors every tile in the game.
--
-- `step` picks the animation frame for a tile some `tileAnims` entry rewrites.
-- NIL means "the static tileset", which is what every caller that predates
-- animation passes and what the base sheet is still baked from; a NUMBER --
-- including zero -- means "the animation", because step 0 is a real frame the
-- cartridge DMAs and not a synonym for the art that was sitting in VRAM
-- before it.  Every tile no entry claims ignores the argument entirely and
-- comes back off the tileset's own `tiles` string, out of the same cache it
-- always used.
function Gen3Tiles:tilePixels(index, step)
  local entry = nil
  if step then entry = self:animTileMap()[index] end
  if entry then return self:animPixels(index, entry, step) end
  local hit = self.tileCache[index]
  if hit then return hit end
  local record, local_ = self:tileBank(index)
  local data = record and record.tiles
  local out = {}
  local base = local_ * 32
  if data and base + 32 <= #data then
    local n = 0
    for row = 0, 7 do
      for half = 0, 3 do
        local b = byte(data, base + row * 4 + half + 1)
        out[n + 1] = b % 16
        out[n + 2] = math.floor(b / 16)
        n = n + 2
      end
    end
  else
    for i = 1, 64 do out[i] = 0 end
  end
  self.tileCache[index] = out
  return out
end

-- The same decode, against a frame string instead of the tileset's own tiles.
-- Cached per (step, index) for the same reason the static one is: a sheet bake
-- asks for the sea's thirty tiles once per metatile that uses them.
function Gen3Tiles:animPixels(index, entry, step)
  self._animCache = self._animCache or {}
  local per = self._animCache[step]
  if not per then per = {} self._animCache[step] = per end
  local hit = per[index]
  if hit then return hit end
  local unit = self:animPeriod() or entry.period
  -- how many of THIS entry's frames have gone by after `step` global steps
  local turns = math.max(1, math.floor(entry.period / math.max(1, unit)))
  local f = math.floor(step / turns) % #entry.frames
  local data = entry.frames[f + 1]
  local out = {}
  local base = (index - entry.first) * 32
  if data and base >= 0 and base + 32 <= #data then
    local n = 0
    for row = 0, 7 do
      for half = 0, 3 do
        local b = byte(data, base + row * 4 + half + 1)
        out[n + 1] = b % 16
        out[n + 2] = math.floor(b / 16)
        n = n + 2
      end
    end
  else
    for i = 1, 64 do out[i] = 0 end
  end
  per[index] = out
  return out
end

function Gen3Tiles:palette(index)
  local record = self:paletteBank(index)
  local pals = record and record.palettes
  return pals and pals[index + 1] or nil
end

-- The colour the backdrop shows where nothing is drawn: palette 0, colour 0.
function Gen3Tiles:backdrop()
  local p = self:palette(0)
  return p and p[1] or { 0, 0, 0 }
end

-- One metatile's eight tile entries, as { tile, flipX, flipY, palette }.
function Gen3Tiles:entries(metatile)
  local record, local_ = self:metatileBank(metatile)
  local data = record and record.metatiles
  local out = {}
  local base = local_ * 16
  if not (data and base + 16 <= #data) then return out end
  for k = 0, 7 do
    local lo = byte(data, base + k * 2 + 1)
    local hi = byte(data, base + k * 2 + 2)
    local word = lo + hi * 256
    out[k + 1] = {
      tile = word % 1024,
      flipX = math.floor(word / 1024) % 2 == 1,
      flipY = math.floor(word / 2048) % 2 == 1,
      palette = math.floor(word / 4096) % 16,
    }
  end
  return out
end

-- The metatile's behaviour byte and layer type, out of the attributes word.
function Gen3Tiles:attributes(metatile)
  local record, local_ = self:metatileBank(metatile)
  local data = record and record.attributes
  local base = local_ * 2
  if not (data and base + 2 <= #data) then return 0, 0 end
  local word = byte(data, base + 1) + byte(data, base + 2) * 256
  return word % 256, math.floor(word / 4096) % 16
end

-- Draw one metatile's layer into `plot(x, y, r, g, b)` at (ox, oy).  Layer 1
-- is what the player walks in front of and layer 2 what they walk behind, so
-- the caller draws them either side of the sprites rather than flattening the
-- two -- flattening is what puts a character on top of a treetop they should
-- disappear behind.
function Gen3Tiles:drawLayer(metatile, layer, ox, oy, plot, step)
  local entries = self:entries(metatile)
  local first = (layer - 1) * 4
  for q = 0, 3 do
    local e = entries[first + q + 1]
    if e then
      local pixels = self:tilePixels(e.tile, step)
      local pal = self:palette(e.palette)
      local tx = ox + (q % 2) * 8
      local ty = oy + math.floor(q / 2) * 8
      for y = 0, 7 do
        local sy = e.flipY and (7 - y) or y
        for x = 0, 7 do
          local sx = e.flipX and (7 - x) or x
          local v = pixels[sy * 8 + sx + 1]
          -- index 0 is transparent on BOTH layers; the backdrop shows through
          if v ~= 0 and pal then
            local c = pal[v + 1]
            if c then plot(tx + x, ty + y, c[1], c[2], c[3]) end
          end
        end
      end
    end
  end
end

-- Whole metatile, both layers, bottom first.
function Gen3Tiles:draw(metatile, ox, oy, plot, step)
  for layer = 1, self.layers do
    self:drawLayer(metatile, layer, ox, oy, plot, step)
  end
end

-- ---------------------------------------------------------------------------
-- Sheet baking
--
-- The renderer wants one quad per cell, not eight tile draws with a palette
-- swap between each, so a pair's metatiles are composited once into two
-- sheets -- bottom layer and top layer -- and the map then blits 16x16 quads
-- out of them.  Two sheets rather than one flattened image is the whole point:
-- the player walks BETWEEN them, which is what puts a character behind a
-- treetop and in front of the grass under it.
--
-- Baking is deferred and cached per pair because it is the expensive part
-- (a 656-metatile pair is about 336,000 pixels across the two sheets) and
-- because 441 layouts share only 76 pairs.
-- ---------------------------------------------------------------------------

Gen3Tiles.SHEET_COLS = 16

-- HOW LONG THE SHEET IS -- which is the size of the metatile ID SPACE, not
-- the number of metatiles anybody defined.
--
-- metatileBank splits at metatilesInPrimary: id 511 is the primary's last
-- slot and id 512 is the SECONDARY's first, whatever the primary actually
-- filled in. A pair's sheet is indexed by the id itself, so it has to be that
-- long or the secondary's metatiles have nowhere to sit.
--
-- Summing the two counts instead looks right and is right exactly when the
-- primary defines all 512 -- which the OUTDOOR primary does, so Littleroot
-- and the moving truck drew perfectly. Emerald's indoor primary defines
-- EIGHT. Every room in the game asks for ids 513 and up, the sheet was 204
-- metatiles long, every lookup past 203 came back nil, and the inside of the
-- house was white while the town outside it was not.
--
-- The blank stretch this leaves (504 undefined ids on an indoor pair) costs
-- loop iterations and no pixels: `entries` returns nothing for an id its bank
-- never defined, so nothing is plotted and the sheet rows stay transparent.
function Gen3Tiles:metatileCount()
  if self.secondary then
    return self.metatilesInPrimary + (self.secondary.metatileCount or 0)
  end
  return (self.primary and self.primary.metatileCount) or 0
end

function Gen3Tiles:sheetLayout()
  local count = self:metatileCount()
  local cols = Gen3Tiles.SHEET_COLS
  local rows = math.ceil(count / cols)
  return cols, rows, cols * 16, rows * 16
end

-- Where a metatile sits on the sheet, in pixels.
function Gen3Tiles:sheetOrigin(metatile)
  local cols = Gen3Tiles.SHEET_COLS
  return (metatile % cols) * 16, math.floor(metatile / cols) * 16
end

-- Composite one layer of every metatile into `plot(x, y, r, g, b)`.  The
-- caller supplies the surface, so this is the same code path the headless
-- tests exercise and the one that fills a love ImageData.
-- WHICH SIDE OF THE PLAYER A METATILE'S TOP HALF IS ON.
--
-- Not every metatile's second layer is scenery to walk behind. The
-- attributes word carries a layer type, and it decides which background the
-- top half is drawn to -- which is to say whether the player passes in front
-- of it or behind it.
--
-- The cartridge answers this with its own map data, on the first map of the
-- game. In Littleroot:
--
--   * the cell directly in front of EVERY door -- metatile 513, the one you
--     stand on the moment you step out of a house -- is layer type 1, and it
--     has 138 of its 256 pixels in the TOP layer. Drawn above the player,
--     that buries him to the chest every time he leaves a building.
--   * every tree and roof cell -- 528, 529, 530, up to 256 pixels of top
--     layer, all of them impassable -- is layer type 0. Those are precisely
--     the things you walk behind.
--
-- So type 1's top half is a second layer of GROUND (a carpet over a floor, a
-- path over grass) and belongs under the sprites; type 0's is cover and
-- belongs over them. Type 2 is rare -- 392 cells in the whole game, 98% of
-- them with a top layer and 85% walkable -- and behaves like type 0: it is
-- the tall grass you stand IN, whose blades draw across your feet.
--
-- Baking everything above the sprites, which is what this did, put a
-- character under the floor he was standing on 29% of the time.
local COVERED = 1

function Gen3Tiles:topIsAbovePlayer(metatile)
  local _, layerType = self:attributes(metatile)
  return layerType ~= COVERED
end

-- ONE metatile into one layer of a sheet, at (ox, oy).  Lifted out of
-- bakeLayer unchanged so the animated overlay below composites by exactly the
-- same rule -- which half of a metatile belongs above the player and which
-- below is the single most visible thing this file decides, and having it
-- written twice is how the two sheets drift apart.
function Gen3Tiles:bakeCell(id, layer, ox, oy, plot, step)
  if layer == 1 then
    self:drawLayer(id, 1, ox, oy, plot, step)
    -- a covered metatile's top half is ground too, so it is composited
    -- into the SAME sheet, over its own bottom half and under everything
    if not self:topIsAbovePlayer(id) then
      self:drawLayer(id, 2, ox, oy, plot, step)
    end
  elseif self:topIsAbovePlayer(id) then
    self:drawLayer(id, layer, ox, oy, plot, step)
  end
end

function Gen3Tiles:bakeLayer(layer, plot)
  local count = self:metatileCount()
  for id = 0, count - 1 do
    local ox, oy = self:sheetOrigin(id)
    self:bakeCell(id, layer, ox, oy, plot)
  end
  return count
end

-- ---------------------------------------------------------------------------
-- THE ANIMATED OVERLAY SHEET, and why it is PACKED rather than sheet-shaped.
--
-- The obvious overlay is another sheet the same size as the static one, blank
-- except at the animated metatiles, so the window batch's existing quads stay
-- valid.  On the Route 104 pair that is 256x864 per step per layer: sixteen
-- textures of 221,000 pixels, 14 MB of them, for a pair whose static sheets
-- cost 1.8.  A trek across Hoenn touches dozens of pairs and none of this is
-- evicted, so the obvious overlay is a gigabyte.
--
-- Only 148 of the pair's 862 metatiles move, so the overlay is packed to just
-- those, sixteen to a row, and the caller keeps a second quad table indexed by
-- metatile id.  256x160 per step per layer instead of 256x864 -- about 2.6 MB
-- for the pair, a fifth of the naive shape, and no other cost: a quad lookup
-- is a quad lookup.
-- ---------------------------------------------------------------------------

Gen3Tiles.ANIM_COLS = 16

-- the animated metatile ids in ascending order, and their slot in the packed
-- sheet.  Ascending because a bake has to be reproducible: the same pair on
-- two runs must lay its overlay out identically or a cached quad table would
-- point at the wrong art.
function Gen3Tiles:animOrder()
  if self._animOrder then return self._animOrder, self._animSlot end
  local cells = self:animMetatiles()
  local order, slot = {}, {}
  for m in pairs(cells) do order[#order + 1] = m end
  table.sort(order)
  for i, m in ipairs(order) do slot[m] = i - 1 end
  self._animOrder, self._animSlot = order, slot
  return order, slot
end

-- width, height of the packed overlay sheet in pixels (0, 0 when nothing
-- animates)
function Gen3Tiles:animSheetLayout()
  local order = self:animOrder()
  if #order == 0 then return 0, 0 end
  local cols = Gen3Tiles.ANIM_COLS
  return cols * 16, math.ceil(#order / cols) * 16
end

-- where metatile `m` sits in the packed sheet, in pixels
function Gen3Tiles:animOrigin(m)
  local _, slot = self:animOrder()
  local k = slot[m]
  if k == nil then return nil end
  local cols = Gen3Tiles.ANIM_COLS
  return (k % cols) * 16, math.floor(k / cols) * 16
end

function Gen3Tiles:bakeAnimLayer(layer, plot, step)
  local order = self:animOrder()
  local cols = Gen3Tiles.ANIM_COLS
  for i, m in ipairs(order) do
    local k = i - 1
    self:bakeCell(m, layer, (k % cols) * 16, math.floor(k / cols) * 16, plot, step)
  end
  return #order
end


return Gen3Tiles
