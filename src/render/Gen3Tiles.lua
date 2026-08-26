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

-- A tile's 64 palette indices.  4bpp, and the LOW nibble is the LEFT pixel --
-- reading the high nibble first mirrors every tile in the game.
function Gen3Tiles:tilePixels(index)
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
function Gen3Tiles:drawLayer(metatile, layer, ox, oy, plot)
  local entries = self:entries(metatile)
  local first = (layer - 1) * 4
  for q = 0, 3 do
    local e = entries[first + q + 1]
    if e then
      local pixels = self:tilePixels(e.tile)
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
function Gen3Tiles:draw(metatile, ox, oy, plot)
  for layer = 1, self.layers do
    self:drawLayer(metatile, layer, ox, oy, plot)
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

function Gen3Tiles:metatileCount()
  local n = (self.primary and self.primary.metatileCount or 0)
  if self.secondary then n = n + (self.secondary.metatileCount or 0) end
  return n
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
function Gen3Tiles:bakeLayer(layer, plot)
  local count = self:metatileCount()
  for id = 0, count - 1 do
    local ox, oy = self:sheetOrigin(id)
    self:drawLayer(id, layer, ox, oy, plot)
  end
  return count
end


return Gen3Tiles
