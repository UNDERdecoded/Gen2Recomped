-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The title and intro backgrounds a GBA cartridge draws, turned into images.
--
-- A Gen 3 "scene" is not a picture in the ROM.  It is a 4bpp tile sheet, a
-- 32-cell-wide tilemap naming which tile goes in which cell (with its own flip
-- bits and its own palette per cell), and a BANK of palettes -- the title
-- screen loads fifteen of them in one call and its tilemap picks between them
-- cell by cell.  The import replays the loader's palette calls and ships all
-- three (RomExtractorGen3:extractScenes); this is the other half, and it is
-- the only thing in the engine that reads data.scenes.
--
-- Index 0 is TRANSPARENT, which is what makes a scene a LAYER: the title
-- screen is Rayquaza with clouds drifting over him, two scenes drawn one on
-- top of the other, and painting index 0 would hide the first behind the
-- second's empty sky.  `opaque` asks for the backdrop instead, for the layer
-- at the bottom of the stack that has nothing behind it.

local Assets = require("src.render.Assets")
local Logger = require("src.core.Logger")

local Gen3Scene = {}

local cache = {}

local function build(scene, opaque)
  local tiles, map, palettes = scene.tiles, scene.map, scene.palettes
  if type(tiles) ~= "string" or type(map) ~= "string"
     or type(palettes) ~= "table" then
    return nil
  end
  local cols = math.floor(tonumber(scene.mapWidth) or 32)
  local rows = math.floor(tonumber(scene.mapHeight) or 32)
  if cols < 1 or rows < 1 then return nil end
  local width, height = cols * 8, rows * 8
  local image = love.image.newImageData(width, height)
  local backdrop = palettes[1]
  local cells = math.floor(#map / 2)
  for cell = 0, math.min(cells, cols * rows) - 1 do
    local lo, hi = map:byte(cell * 2 + 1), map:byte(cell * 2 + 2)
    local entry = lo + hi * 256
    local tileId = entry % 1024
    local flipX = math.floor(entry / 1024) % 2 == 1
    local flipY = math.floor(entry / 2048) % 2 == 1
    local bank = math.floor(entry / 4096) % 16
    local cx, cy = (cell % cols) * 8, math.floor(cell / cols) * 8
    local base = tileId * 32
    for y = 0, 7 do
      local sy = flipY and (7 - y) or y
      for x = 0, 7 do
        local sx = flipX and (7 - x) or x
        local byte = tiles:byte(base + sy * 4 + math.floor(sx / 2) + 1)
        local index = 0
        if byte then
          -- the LOW nibble is the LEFT pixel; this cartridge is consistent
          -- about that everywhere except its font
          index = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
        end
        local colour = index ~= 0 and palettes[bank * 16 + index + 1] or nil
        if colour then
          image:setPixel(cx + x, cy + y,
                         colour[1] / 255, colour[2] / 255, colour[3] / 255, 1)
        elseif opaque and backdrop then
          image:setPixel(cx + x, cy + y, backdrop[1] / 255, backdrop[2] / 255,
                         backdrop[3] / 255, 1)
        else
          image:setPixel(cx + x, cy + y, 0, 0, 0, 0)
        end
      end
    end
  end
  return love.graphics.newImage(image)
end

-- The scene with this id as a LOVE image, or nil when the dataset has no such
-- scene (every Gen 1 and Gen 2 dataset, and a Gen 3 one whose scene stage
-- dropped that layer because a pixel of it used a colour the loader never
-- loads).  Cached, and dropped with the rest of the asset caches.
function Gen3Scene.image(data, id, opaque)
  local key = tostring(id) .. (opaque and "!" or "")
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  local scenes = data and data.scenes
  local scene = scenes and scenes[id]
  if type(scene) ~= "table" then
    cache[key] = false
    return nil
  end
  local ok, image = pcall(build, scene, opaque)
  if not ok then
    Logger.warn("gen3 scene %s could not be built: %s", tostring(id),
                tostring(image))
    image = nil
  end
  cache[key] = image or false
  return image
end

-- The layers of a named screen, back to front: "title" is Rayquaza and then
-- the clouds over him, "birchSpeech" is the grass platform.
--
-- Empty for any dataset that has no such role -- every Gen 1 and Gen 2 one,
-- and a Gen 3 one whose layers all failed to decode -- so a caller that gets
-- nothing back is looking at a screen with no backdrop, not at an error.
function Gen3Scene.layersOf(data, role)
  local scenes = (data and data.scenes) or {}
  local out = {}
  for _, id in ipairs((scenes._roles or {})[role] or {}) do
    out[#out + 1] = id
  end
  return out
end

-- The whole role drawn in order, at (x, y), scaled by `scale`, clipped to
-- `w` x `h` of the source.  Returns false when the role has no layers.
function Gen3Scene.drawRole(data, role, x, y, scale, w, h)
  local ids = Gen3Scene.layersOf(data, role)
  if not ids[1] then return false end
  love.graphics.setColor(1, 1, 1, 1)
  for i, id in ipairs(ids) do
    local image = Gen3Scene.image(data, id, i == 1)
    if image then
      local iw, ih = image:getDimensions()
      local quad = love.graphics.newQuad(0, 0, math.min(w or iw, iw),
                                         math.min(h or ih, ih), iw, ih)
      love.graphics.draw(image, quad, x, y, 0, scale or 1, scale or 1)
    end
  end
  return true
end

-- THE OVERLAYS.
--
-- A scene is a tiled background.  A screen's logo is not: Emerald's POKeMON
-- logo is a 256-colour BITMAP and its EMERALD VERSION wordmark is a sprite
-- sheet, and neither can be expressed as (sheet, tilemap, bank).  The import
-- composes them straight to PNG (see extractScenes' overlay pass), so here
-- they are already pictures and only need loading.
--
-- Returns a table of `{ image, width, height }` records, or nil.  `bitmaps`
-- are backgrounds in front-to-back order; `sheets` are sprite art, and a
-- sheet whose layout could not be derived is marked `layout = "strip"` --
-- a screen should draw those only if it knows what it is looking at.
local function overlayRecord(data, role)
  local scenes = (data and data.scenes) or {}
  local all = scenes._overlays
  return type(all) == "table" and all[role] or nil
end

function Gen3Scene.overlays(data, role)
  return overlayRecord(data, role)
end

-- One overlay picture, loaded and cached like a scene.  `kind` is "bitmaps"
-- or "sheets" and `n` is its index in that list.
function Gen3Scene.overlayImage(data, role, kind, n)
  local record = overlayRecord(data, role)
  local entry = record and record[kind] and record[kind][n]
  if type(entry) ~= "table" or type(entry.image) ~= "string" then return nil end
  local key = "overlay:" .. tostring(role) .. ":" .. kind .. ":" .. n
  local hit = cache[key]
  if hit ~= nil then return hit or nil, entry end
  local ok, image = pcall(Assets.image, entry.image)
  if not ok then
    Logger.warn("gen3 overlay %s %s %d: %s", tostring(role), kind, n,
                tostring(image))
    image = nil
  end
  cache[key] = image or false
  return image, entry
end

function Gen3Scene.invalidate() cache = {} end

Assets.register(Gen3Scene.invalidate)

return Gen3Scene
