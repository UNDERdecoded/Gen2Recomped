-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE BADGES ON EMERALD'S TRAINER CARD.
--
-- The import (RomExtractorGen3:trainerCardBadges) lifts a single 1024-byte
-- sheet and one palette; this cuts the eight badges out of it.
--
-- WHY A SIXTEEN-WIDE STRIP.  The cartridge does not draw these as sprites.
-- It writes four background tilemap cells per badge -- t and t+1 on one row,
-- t+16 and t+17 on the next -- so the sheet is sixteen tiles across and two
-- tiles down, with the eight badges side by side.  Badge n therefore lives at
-- tiles (2n-2, 2n-1) on the top row and the two directly beneath them, and
-- that arithmetic is the cartridge's own rather than a guess about layout.
--
-- ONE PALETTE FOR ALL EIGHT is also the cartridge's: they are drawn on BG
-- palette 3 and share it, which is why they come out embossed and grey rather
-- than each in its gym's colour.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")

local Gen3BadgeArt = {}

local cache = {}

local function canDraw()
  return love and love.image and love.image.newImageData
     and love.graphics and love.graphics.newImage
end

-- The record, or nil for a dataset whose import has no badge sheet.
function Gen3BadgeArt.of(data)
  local constants = data and data.constants
  local art = constants and constants.gen3TrainerCardBadges
  if type(art) ~= "table" or type(art.tiles) ~= "string" then return nil end
  return art
end

function Gen3BadgeArt.count(data)
  local art = Gen3BadgeArt.of(data)
  return art and (tonumber(art.count) or 8) or 0
end

local function build(art, index)
  local columns = math.floor(tonumber(art.columns) or 16)
  local palette = art.palette or {}
  local tiles = art.tiles
  local image = love.image.newImageData(16, 16)
  -- the four cells of this badge, in the order the cartridge writes them
  local first = (index - 1) * 2
  local quads = { { first, 0, 0 }, { first + 1, 8, 0 },
                  { first + columns, 0, 8 }, { first + columns + 1, 8, 8 } }
  for _, q in ipairs(quads) do
    local at = q[1] * 32
    for y = 0, 7 do
      for x = 0, 7 do
        local byte = tiles:byte(at + y * 4 + math.floor(x / 2) + 1)
        local idx = 0
        if byte then
          idx = (x % 2 == 0) and (byte % 16) or math.floor(byte / 16)
        end
        local colour = idx ~= 0 and palette[idx + 1] or nil
        if colour then
          image:setPixel(q[2] + x, q[3] + y,
                         colour[1] / 255, colour[2] / 255, colour[3] / 255, 1)
        else
          image:setPixel(q[2] + x, q[3] + y, 0, 0, 0, 0)
        end
      end
    end
  end
  return love.graphics.newImage(image)
end

-- Badge `index` (1-8) as a 16x16 image, or nil when this dataset has no sheet
-- or the renderer is headless.
function Gen3BadgeArt.image(data, index)
  local art = Gen3BadgeArt.of(data)
  index = math.floor(tonumber(index) or 0)
  if not (art and canDraw()) then return nil end
  if index < 1 or index > (tonumber(art.count) or 8) then return nil end
  local key = "badge:" .. index
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  local ok, image = pcall(build, art, index)
  if not ok then
    Logger.warn("gen3 badge %d could not be built: %s", index, tostring(image))
    image = nil
  end
  cache[key] = image or false
  return image
end

function Gen3BadgeArt.invalidate() cache = {} end

Assets.register(Gen3BadgeArt.invalidate)

return Gen3BadgeArt
