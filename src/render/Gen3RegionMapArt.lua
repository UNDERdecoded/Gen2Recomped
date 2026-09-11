-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HOENN AS THE CARTRIDGE PAINTS IT.
--
-- The import (RomExtractorGen3:regionMapArt) lifts four things out of the
-- ROM: a sheet of 8bpp tiles, a one-byte-per-cell tilemap, the two palette
-- rows the background inks with, and the sprites that go over it -- the
-- blinking corner cursor and the player's head.  This is the other half, and
-- it is the only thing in the engine that reads constants.gen3RegionMapArt.
--
-- 8BPP, NOT 4BPP.  A region map tile is sixty-four bytes, one byte per pixel,
-- and the byte is a palette index into the WHOLE 256-colour background
-- palette -- of which this screen loads two rows, starting at `paletteBase`.
-- So a pixel's colour is `palette[byte - paletteBase + 1]`, and index 0 is
-- transparent exactly as it is everywhere else.
--
-- THE CURSOR IS FOUR CORNERS.  The cartridge's cursor sprite is sixteen by
-- sixteen and its art is four corner brackets with nothing in the middle,
-- which is why it can sit around a section of any size: the brackets go to
-- the four corners of the rectangle and the middle was never drawn.  Two
-- frames, alternating, is the blink.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")

local Gen3RegionMapArt = {}

local cache = {}

local function canDraw()
  return love and love.image and love.image.newImageData
     and love.graphics and love.graphics.newImage
end

-- The record, or nil for every dataset that is not Emerald and for an Emerald
-- one whose import could not find the picture.
function Gen3RegionMapArt.of(data)
  local constants = data and data.constants
  local art = constants and constants.gen3RegionMapArt
  if type(art) ~= "table" then return nil end
  if type(art.tiles) ~= "string" or type(art.map) ~= "string" then return nil end
  return art
end

-- ---------------------------------------------------------------------------
-- THE BACKGROUND
-- ---------------------------------------------------------------------------
local function buildBackground(art, rows)
  local cols = math.floor(tonumber(art.width) or 32)
  local stride = math.floor(tonumber(art.mapStride) or cols)
  local base = math.floor(tonumber(art.paletteBase) or 0)
  local palette = art.palette or {}
  local tiles, map = art.tiles, art.map
  local image = love.image.newImageData(cols * 8, rows * 8)
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      -- PAST THE END OF THE MAP IS TILE ZERO, which is the open sea.  The
      -- cartridge's tilemap stops at its last inked row; the screen does not.
      local id = map:byte(r * stride + c + 1) or 0
      local at = id * 64
      for y = 0, 7 do
        for x = 0, 7 do
          local index = tiles:byte(at + y * 8 + x + 1) or 0
          local colour = index ~= 0 and palette[index - base + 1] or nil
          if colour then
            image:setPixel(c * 8 + x, r * 8 + y,
                           colour[1] / 255, colour[2] / 255, colour[3] / 255, 1)
          else
            image:setPixel(c * 8 + x, r * 8 + y, 0, 0, 0, 0)
          end
        end
      end
    end
  end
  return love.graphics.newImage(image)
end

-- Hoenn, tall enough to cover `rows` rows of screen.  nil when the dataset
-- has no picture, which is the caller's cue to draw the rectangles instead.
function Gen3RegionMapArt.background(data, rows)
  local art = Gen3RegionMapArt.of(data)
  if not (art and canDraw()) then return nil end
  rows = math.max(math.floor(tonumber(rows) or 0),
                  math.floor(tonumber(art.height) or 1))
  local key = "bg:" .. rows
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  local ok, image = pcall(buildBackground, art, rows)
  if not ok then
    Logger.warn("gen3 region map background could not be built: %s",
                tostring(image))
    image = nil
  end
  cache[key] = image or false
  return image
end

-- ---------------------------------------------------------------------------
-- THE SPRITES: 4bpp, sixteen colours, index 0 transparent.
-- ---------------------------------------------------------------------------
local function build4bpp(tiles, palette, cols, rows, firstTile)
  local image = love.image.newImageData(cols * 8, rows * 8)
  for t = 0, cols * rows - 1 do
    local at = (firstTile + t) * 32
    local ox, oy = (t % cols) * 8, math.floor(t / cols) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local byte = tiles:byte(at + y * 4 + math.floor(x / 2) + 1)
        local index = 0
        if byte then
          index = (x % 2 == 0) and (byte % 16) or math.floor(byte / 16)
        end
        local colour = index ~= 0 and palette[index + 1] or nil
        if colour then
          image:setPixel(ox + x, oy + y,
                         colour[1] / 255, colour[2] / 255, colour[3] / 255, 1)
        else
          image:setPixel(ox + x, oy + y, 0, 0, 0, 0)
        end
      end
    end
  end
  return love.graphics.newImage(image)
end

-- One frame of the cursor, as a 16x16 image whose four quarters are the four
-- corner brackets.  `frame` counts from 1 and wraps.
function Gen3RegionMapArt.cursor(data, frame)
  local art = Gen3RegionMapArt.of(data)
  local cursor = art and art.cursor
  if not (cursor and cursor.small and canDraw()) then return nil end
  local small = cursor.small
  local perFrame = (small.cols or 2) * (small.rows or 2)
  local frames = math.max(1, math.floor((small.tileCount or perFrame) / perFrame))
  local n = ((math.floor(tonumber(frame) or 1) - 1) % frames)
  local key = "cursor:" .. n
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  local ok, image = pcall(build4bpp, small.tiles, cursor.palette or {},
                          small.cols or 2, small.rows or 2, n * perFrame)
  if not ok then
    Logger.warn("gen3 region map cursor could not be built: %s", tostring(image))
    image = nil
  end
  cache[key] = image or false
  return image
end

function Gen3RegionMapArt.cursorFrames(data)
  local art = Gen3RegionMapArt.of(data)
  local small = art and art.cursor and art.cursor.small
  if not small then return 0 end
  local perFrame = (small.cols or 2) * (small.rows or 2)
  return math.max(1, math.floor((small.tileCount or perFrame) / perFrame))
end

-- The player's head, 16x16.  Icon 1 is the boy and icon 2 the girl, in the
-- order the cartridge stores them.
function Gen3RegionMapArt.playerIcon(data, n)
  local art = Gen3RegionMapArt.of(data)
  local icons = art and art.icons
  local icon = icons and icons[math.max(1, math.floor(tonumber(n) or 1))]
  if not (icon and canDraw()) then return nil end
  local key = "icon:" .. tostring(n)
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  local ok, image = pcall(build4bpp, icon.tiles, icon.palette or {},
                          icon.cols or 2, icon.rows or 2, 0)
  if not ok then
    Logger.warn("gen3 region map player icon could not be built: %s",
                tostring(image))
    image = nil
  end
  cache[key] = image or false
  return image
end

function Gen3RegionMapArt.invalidate() cache = {} end

Assets.register(Gen3RegionMapArt.invalidate)

return Gen3RegionMapArt
