-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ANIMATED BG TILES (round 15; user report "scrambled tiles"). The cartridge
-- keeps 32 animated tiles (water, lava, conveyor, torches...) in VRAM and
-- swaps them every 9 frames; before round 15 the port drew the static sheet
-- that lies under them (main tileset slot 7), which looks scrambled.
--
--   overworld: 0x0812FD88(sheet): sheet (0x58 for Death Mountain areas 3/5/7
--     and 0x43/0x45/0x47, else 0x5A) tiles 0-63 + sheet+1 tiles 0-31 ->
--     EWRAM 0x02009A00 = frames 0, 1, 2 of 32 tiles; VRAM tile 0x1C0.
--   dungeons:  0x0812FCDC(a), a = RomMap.dungAnimTiles[main tileset]: frame f
--     = sheet a tiles 16f..16f+15, then sheet 0x5C tiles 16f..16f+15; VRAM
--     tile 0x1B0.
--   clock: 0x0812D1A0 steps the frame offset (0, 0x400, 0x800) every 9
--     frames; the VBlank routine 0x080A7048 copies it.
-- OURS: the SNES's 0x17-frame step for overlays 0xB5 / 0xBC is not ported
-- (the port has no overlay index); every animation steps every 9 frames.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local A = {}
A.COUNT = 32
A.OW_BASE = 0x1C0
A.DUNG_BASE = 0x1B0
A.PERIOD = 9

local okFfi, ffi = pcall(require, "ffi")

local function tilePixels(raw, t)
  local px = {}
  local o = t * 32
  for i = 0, 31 do
    local b = raw:byte(o + i + 1) or 0
    px[i * 2 + 1] = band(b, 15)
    px[i * 2 + 2] = rshift(b, 4)
  end
  return px
end

-- the overworld animation sheet of an area (its parent screen)
function A.owSheet(parent)
  local sc = band(parent, 0xBF)
  return (sc == 3 or sc == 5 or sc == 7) and 0x58 or 0x5A
end

-- frames[f][k] (f 0..2, k 0..31): 64 palette indices of each animated tile
local cache = setmetatable({}, { __mode = "k" })
local function frameSet(data, key, build)
  local per = cache[data]
  if not per then per = {}; cache[data] = per end
  local hit = per[key]
  if not hit then hit = build(); per[key] = hit end
  return hit
end

function A.owFrames(data, parent)
  local s = A.owSheet(parent)
  return frameSet(data, "ow" .. s, function()
    local a, b = data:sheet(s), data:sheet(s + 1)
    local fr = { [0] = {}, {}, {} }
    for k = 0, 31 do
      fr[0][k] = tilePixels(a, k)
      fr[1][k] = tilePixels(a, 32 + k)
      fr[2][k] = tilePixels(b, k)
    end
    return fr
  end)
end

function A.dungSheet(data, main)
  local t = data.t and data.t.dungAnim
  return (t and t[(main or 0) + 1]) or 0x5D
end

function A.dungFrames(data, main)
  local s = A.dungSheet(data, main)
  return frameSet(data, "dung" .. s, function()
    local a, b = data:sheet(s), data:sheet(0x5C)
    local fr = { [0] = {}, {}, {} }
    for f = 0, 2 do
      for k = 0, 15 do
        fr[f][k] = tilePixels(a, f * 16 + k)
        fr[f][16 + k] = tilePixels(b, f * 16 + k)
      end
    end
    return fr
  end)
end

-- the animation frame (0..2) for a frame counter
function A.frameAt(counter)
  return math.floor((counter or 0) / A.PERIOD) % 3
end

-- ------------------------------------------------------------ live images
-- Images decoded with animated cells register here; A.tick rewrites those
-- cells (only) when the frame changes and re-uploads the Image.
A.live = setmetatable({}, { __mode = "k" })

-- im: Image; img: its ImageData (kept); cells: { tx, ty, word, ... } flat
-- triples (word = the map word); frames: A.*Frames; base: first anim tile;
-- pal: 256 BGR555; opaque0: colour for index 0 or nil
function A.register(im, img, cells, frames, base, pal, opaque0)
  if not (im and img and cells and #cells > 0) then return end
  local lut = {}
  for i = 0, 255 do
    local c = pal[i]
    if c then
      lut[i] = { math.floor(band(c, 31) * 255 / 31 + 0.5), math.floor(band(rshift(c, 5), 31) * 255 / 31 + 0.5),
                 math.floor(band(rshift(c, 10), 31) * 255 / 31 + 0.5) }
    end
  end
  local bg
  if opaque0 then
    bg = { math.floor(band(opaque0, 31) * 255 / 31 + 0.5), math.floor(band(rshift(opaque0, 5), 31) * 255 / 31 + 0.5),
           math.floor(band(rshift(opaque0, 10), 31) * 255 / 31 + 0.5) }
  end
  A.live[im] = { img = img, cells = cells, frames = frames, base = base, lut = lut, bg = bg, frame = 0 }
end

local function patch(e, f)
  local img, cells, tiles = e.img, e.cells, e.frames[f]
  local w = img:getWidth()
  local p = okFfi and img.getPointer and ffi.cast("uint8_t*", img:getPointer()) or nil
  for i = 1, #cells, 3 do
    local tx, ty, word = cells[i], cells[i + 1], cells[i + 2]
    local px = tiles[band(word, 0x3FF) - e.base]
    if px then
      local hf, vf = band(word, 0x400) ~= 0, band(word, 0x800) ~= 0
      local pl = rshift(word, 12) * 16
      for y = 0, 7 do
        local sy = vf and (7 - y) or y
        for x = 0, 7 do
          local c = px[sy * 8 + (hf and (7 - x) or x) + 1] or 0
          local col = (c ~= 0) and e.lut[pl + c] or e.bg
          local X, Y = tx * 8 + x, ty * 8 + y
          if p then
            local o = (Y * w + X) * 4
            if col then p[o], p[o + 1], p[o + 2], p[o + 3] = col[1], col[2], col[3], 255
            else p[o], p[o + 1], p[o + 2], p[o + 3] = 0, 0, 0, 0 end
          elseif col then
            img:setPixel(X, Y, col[1] / 255, col[2] / 255, col[3] / 255, 1)
          else
            img:setPixel(X, Y, 0, 0, 0, 0)
          end
        end
      end
    end
  end
end
A._patch = patch

-- advance every registered image to the frame of `counter`
function A.tick(counter)
  local f = A.frameAt(counter)
  for im, e in pairs(A.live) do
    if e.frame ~= f then
      e.frame = f
      patch(e, f)
      if not pcall(im.replacePixels, im, e.img) then A.live[im] = nil end
    end
  end
end

return A
