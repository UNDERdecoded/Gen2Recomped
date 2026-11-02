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
  local backdrop = palettes[1]
  local cells = math.floor(#map / 2)
  -- BUILT AS BYTES, EIGHT PIXELS AT A TIME, and handed to LOVE in one call.
  -- A setPixel per pixel made the title and Birch's platform cost most of a
  -- second each interpreted, and love-android runs LuaJIT with the JIT off.
  -- Each tile row is made once per (map entry, row) and the same strings are
  -- reused wherever the tile repeats; the bytes are what setPixel stored.
  local char, floor = string.char, math.floor
  local function rgba(c, a)
    local function q(v)
      v = (tonumber(v) or 0) / 255
      if v < 0 then v = 0 elseif v > 1 then v = 1 end
      return floor(v * 255 + 0.5)
    end
    return char(q(c[1]), q(c[2]), q(c[3]), a)
  end
  local clear = char(0, 0, 0, 0)
  local back = (opaque and backdrop) and rgba(backdrop, 255) or clear
  local slotBytes, rowSeg = {}, {}
  local blank = clear:rep(8)
  local out = {}
  for y = 0, height - 1 do out[y] = {} end
  local used = math.min(cells, cols * rows)
  for cell = 0, cols * rows - 1 do
    local col, cy = cell % cols, floor(cell / cols) * 8
    if cell < used then
      local lo, hi = map:byte(cell * 2 + 1), map:byte(cell * 2 + 2)
      local entry = lo + hi * 256
      local tileId = entry % 1024
      local flipX = floor(entry / 1024) % 2 == 1
      local flipY = floor(entry / 2048) % 2 == 1
      local bank = floor(entry / 4096) % 16
      local base = tileId * 32
      for y = 0, 7 do
        local key = entry * 8 + y
        local seg = rowSeg[key]
        if not seg then
          local sy = flipY and (7 - y) or y
          local parts = {}
          for x = 0, 7 do
            local sx = flipX and (7 - x) or x
            local byte = tiles:byte(base + sy * 4 + floor(sx / 2) + 1)
            local index = 0
            if byte then
              -- the LOW nibble is the LEFT pixel; this cartridge is consistent
              -- about that everywhere except its font
              index = (sx % 2 == 0) and (byte % 16) or floor(byte / 16)
            end
            local slot = bank * 16 + index + 1
            local colour = index ~= 0 and palettes[slot] or nil
            if colour then
              local b = slotBytes[slot]
              if not b then b = rgba(colour, 255); slotBytes[slot] = b end
              parts[x + 1] = b
            else
              parts[x + 1] = back
            end
          end
          seg = table.concat(parts)
          rowSeg[key] = seg
        end
        out[cy + y][col + 1] = seg
      end
    else
      for y = 0, 7 do out[cy + y][col + 1] = blank end
    end
  end
  local lines = {}
  for y = 0, height - 1 do lines[y + 1] = table.concat(out[y]) end
  local image = love.image.newImageData(width, height, "rgba8", table.concat(lines))
  return love.graphics.newImage(image), image
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
  local ok, image, pixels = pcall(build, scene, opaque)
  if not ok then
    Logger.warn("gen3 scene %s could not be built: %s", tostring(id),
                tostring(image))
    image = nil
  end
  cache[key] = image or false
  -- the pixels are kept alongside, because a screen wider than the cartridge's
  -- has to be able to ASK what colour the sky is on a given row (skyColumn)
  cache[key .. "#data"] = pixels or false
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

-- One PIECE of a strip sheet: the importer cuts a linear tile run at its own
-- blank tiles and writes each piece out as the single row of tiles it is (see
-- RomExtractorGen3:stripPieces), which is how Emerald's title gets PRESS
-- START and its copyright line as pictures rather than as engine text.
function Gen3Scene.pieceImage(data, role, sheetIndex, pieceIndex)
  local record = overlayRecord(data, role)
  local sheet = record and record.sheets and record.sheets[sheetIndex]
  local entry = sheet and sheet.pieces and sheet.pieces[pieceIndex]
  if type(entry) ~= "table" or type(entry.image) ~= "string" then return nil end
  local key = ("piece:%s:%d:%d"):format(tostring(role), sheetIndex, pieceIndex)
  local hit = cache[key]
  if hit ~= nil then return hit or nil, entry end
  local ok, image = pcall(Assets.image, entry.image)
  if not ok then
    Logger.warn("gen3 overlay %s sheet %d piece %d: %s", tostring(role),
                sheetIndex, pieceIndex, tostring(image))
    image = nil
  end
  cache[key] = image or false
  return image, entry
end

-- EVERY PIXEL THAT USES ONE PALETTE ENTRY, as a white stencil.
--
-- THE GLOW ON RAYQUAZA IS A PALETTE ENTRY, NOT A PICTURE.
--
-- Reported from play: "Rayquaza is missing the yellow glow in our main menu as
-- well".  He is, and the reason is that there is nothing to draw: the markings
-- are already on screen, in a colour that is identical to the body they sit
-- on, and the cartridge makes them appear by REWRITING that palette entry
-- several times a second.  Bake the scene once, as this file does, and the
-- markings bake with it -- invisible.
--
-- The data says so on its own.  Palette bank 14 of the title backdrop holds
-- 004A62 TWICE, at index 11 and at index 15, and no artist spends a slot of a
-- sixteen-colour palette on a duplicate.  Index 11 is 8824 pixels spanning the
-- whole silhouette; index 15 is 1149 pixels sitting INSIDE it, between y 60
-- and the bottom of the screen -- which is the marking pattern.  Index 14 of
-- the same bank is FF0000 and no tile uses it at all, which is the shape of a
-- slot kept for something written at run time.
--
-- So the stencil is those 1149 pixels, white and opaque, and the screen tints
-- and fades it over the backdrop.  Nothing here decides what colour or how
-- fast; that belongs to the screen drawing it.
function Gen3Scene.maskImage(data, id, bank, index)
  local key = ("mask:%s:%d:%d"):format(tostring(id), bank, index)
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  cache[key] = false
  local scene = (data and data.scenes or {})[id]
  if type(scene) ~= "table" then return nil end
  local ok, result = pcall(function()
    local tiles, map = scene.tiles, scene.map
    if type(tiles) ~= "string" or type(map) ~= "string" then return nil end
    local cols = math.floor(tonumber(scene.mapWidth) or 32)
    local rows = math.floor(tonumber(scene.mapHeight) or 32)
    local out = love.image.newImageData(cols * 8, rows * 8)
    local found = 0
    for cell = 0, math.min(math.floor(#map / 2), cols * rows) - 1 do
      local lo, hi = map:byte(cell * 2 + 1), map:byte(cell * 2 + 2)
      local entry = lo + hi * 256
      if math.floor(entry / 4096) % 16 == bank then
        local tileId = entry % 1024
        local flipX = math.floor(entry / 1024) % 2 == 1
        local flipY = math.floor(entry / 2048) % 2 == 1
        local cx, cy = (cell % cols) * 8, math.floor(cell / cols) * 8
        for y = 0, 7 do
          local sy = flipY and (7 - y) or y
          for x = 0, 7 do
            local sx = flipX and (7 - x) or x
            local byte = tiles:byte(tileId * 32 + sy * 4 + math.floor(sx / 2) + 1)
            local at = 0
            if byte then
              at = (sx % 2 == 0) and (byte % 16) or math.floor(byte / 16)
            end
            if at == index then
              out:setPixel(cx + x, cy + y, 1, 1, 1, 1)
              found = found + 1
            end
          end
        end
      end
    end
    if found == 0 then return nil end
    return love.graphics.newImage(out)
  end)
  if not ok then
    Logger.warn("gen3 scene %s: no mask for bank %d index %d (%s)",
                tostring(id), bank, index, tostring(result))
    return nil
  end
  cache[key] = result or false
  return result
end

-- WHICH PALETTE ENTRY OF A SCENE IS THE ANIMATED ONE, found rather than named.
--
-- The tell is the duplicate described above: a bank that holds one colour at
-- two different indices, where the higher of the two is used by FEWER pixels
-- than the lower.  That is a detail drawn in the same colour as the thing it
-- is drawn on, which is only worth doing to something that is about to be
-- recoloured.  Returns bank, index, or nil when no bank looks like that --
-- in which case a screen simply draws no glow, which is what it did before.
function Gen3Scene.animatedEntry(data, id)
  local key = "anim:" .. tostring(id)
  local hit = cache[key]
  if hit ~= nil then
    if hit == false then return nil end
    return hit[1], hit[2]
  end
  cache[key] = false
  local scene = (data and data.scenes or {})[id]
  local pal = type(scene) == "table" and scene.palettes or nil
  local map = type(scene) == "table" and scene.map or nil
  if type(pal) ~= "table" or type(map) ~= "string" then return nil end
  -- how many pixels each (bank, index) covers, so "fewer" can be tested
  local used = {}
  local cols = math.floor(tonumber(scene.mapWidth) or 32)
  local tiles = scene.tiles
  if type(tiles) ~= "string" then return nil end
  for cell = 0, math.floor(#map / 2) - 1 do
    local lo, hi = map:byte(cell * 2 + 1), map:byte(cell * 2 + 2)
    local entry = lo + hi * 256
    local bank = math.floor(entry / 4096) % 16
    local tileId = entry % 1024
    for i = 0, 31 do
      local byte = tiles:byte(tileId * 32 + i + 1)
      if byte then
        local a, b = byte % 16, math.floor(byte / 16)
        used[bank * 16 + a] = (used[bank * 16 + a] or 0) + 1
        used[bank * 16 + b] = (used[bank * 16 + b] or 0) + 1
      end
    end
  end
  local bestBank, bestIndex, bestCount = nil, nil, nil
  for bank = 0, math.floor(#pal / 16) - 1 do
    for i = 15, 1, -1 do
      local c = pal[bank * 16 + i + 1]
      local n = used[bank * 16 + i]
      if c and n and n > 0 then
        for j = 0, i - 1 do
          local d = pal[bank * 16 + j + 1]
          local m = used[bank * 16 + j]
          if d and m and m > n
             and c[1] == d[1] and c[2] == d[2] and c[3] == d[3] then
            if not bestCount or n > bestCount then
              bestBank, bestIndex, bestCount = bank, i, n
            end
            break
          end
        end
      end
    end
  end
  if not bestBank then return nil end
  cache[key] = { bestBank, bestIndex }
  Logger.info("gen3 scene %s: palette %d entry %d is drawn in its own "
                .. "background colour over %d pixels -- taking it as the "
                .. "animated one", tostring(id), bestBank, bestIndex, bestCount)
  return bestBank, bestIndex
end

-- THE SKY, ROW BY ROW, so a screen wider than the cartridge's can continue it.
--
-- Emerald's title backdrop is a VERTICAL gradient: every row of it is one flat
-- colour from edge to edge, with Rayquaza's silhouette cut out of the middle.
-- That is what makes widening this screen possible without inventing art --
-- the sky either side of the picture is not a guess, it is the same colour the
-- row already is, and repeating it is exact rather than a stretch.
--
-- Taken as each row's MOST COMMON colour rather than its edge pixel, because
-- Rayquaza's coils reach the edge on eighteen of the hundred and sixty rows
-- and an edge sample would drag the silhouette sideways -- which is the smear
-- this is here to avoid.  The result is an eight-step gradient, which is what
-- the cartridge's palette holds.
--
-- Returns a 1 x height image to be drawn stretched across a side bar: one
-- pixel wide, so stretching it horizontally can only ever repeat a colour that
-- is already the whole row.
function Gen3Scene.skyColumn(data, id, width, height)
  local key = ("sky:%s:%d:%d"):format(tostring(id), width or 0, height or 0)
  local hit = cache[key]
  if hit ~= nil then return hit or nil end
  cache[key] = false
  Gen3Scene.image(data, id, true)          -- makes sure the pixels exist
  local pixels = cache[tostring(id) .. "!#data"]
  if not pixels then return nil end
  local ok, result = pcall(function()
    local iw, ih = pixels:getDimensions()
    local w = math.min(width or iw, iw)
    local h = math.min(height or ih, ih)
    local out = love.image.newImageData(1, h)
    for y = 0, h - 1 do
      local counts, best, bestN = {}, nil, -1
      for x = 0, w - 1 do
        local r, g, b, a = pixels:getPixel(x, y)
        local k = ("%d,%d,%d,%d"):format(r * 255, g * 255, b * 255, a * 255)
        local n = (counts[k] or 0) + 1
        counts[k] = n
        if n > bestN then best, bestN = { r, g, b, a }, n end
      end
      if best then out:setPixel(0, y, best[1], best[2], best[3], best[4]) end
    end
    return love.graphics.newImage(out)
  end)
  if not ok then
    Logger.warn("gen3 scene %s: no sky column (%s)", tostring(id),
                tostring(result))
    return nil
  end
  cache[key] = result
  return result
end

function Gen3Scene.invalidate() cache = {} end

Assets.register(Gen3Scene.invalidate)

return Gen3Scene
