-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE HUD, as the GBA cartridge builds it (round 4b). Pure logic: turns the
-- player's stats into the 6x32 map words the cartridge keeps at RAM
-- 0x0200B180, then into colour indices; the renderer makes the image.
--
-- Ported routines (RomMap.ui):
--   0x080A797C  copy the template (magic meter, counter icons, item box)
--   0x080A7588  hearts: capacity with heartCap, then (health+3)&~3 with
--               heartCur, through 0x080A7830 = the SNES
--               Hud_UpdateHearts_Inner (10 a row, full >= 5/8, half below)
--   0x080A75FC  magic column: hudMagic[(magic+7)>>3], four rows down
--   0x080A78A8  counters: hundreds/tens/ones, tile 0x90 + digit; a counter
--               at its maximum ORs palette 8 (0x8000) into its digits
--   0x080A77C4  keys: 0xFF (outside dungeons) blanks the digit and the icon
-- The HUD layer scrolls 8 px left, so template columns 1-30 fill the 240 px
-- screen; it sits at the top of the screen (rows 0-5).

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local H = {}

H.COLS, H.ROWS = 32, 6
H.SCROLL_X = 8
H.BLANK = 0x7F

-- the new-game stats of the cartridge (3 hearts, empty counters)
function H.newStats()
  return { health = 24, healthMax = 24, magic = 0, rupees = 0, bombs = 0,
           arrows = 0, keys = 0xFF, bombLevel = 0, arrowLevel = 0 }
end

local function digits(v, n)
  v = math.max(0, math.floor(v or 0))
  local out = {}
  local h = math.floor(v / 100) % 10
  local t = math.floor(v / 10) % 10
  local o = v % 10
  if n == 3 then out = { h, t, o } elseif n == 2 then out = { t, o } else out = { o } end
  return out
end

-- stats -> 192 map words (1-based array)
function H.words(ui, st)
  local w = {}
  for i = 1, H.COLS * H.ROWS do w[i] = ui.template[i] end
  local at = ui.at
  local function put(i, v) w[i + 1] = v end
  -- hearts
  for pass = 1, 2 do
    local n = pass == 1 and (st.healthMax or 24) or band((st.health or 0) + 3, 0xFFFC)
    local tab = pass == 1 and ui.heartCap or ui.heartCur
    local x, dst = 0, at.hearts
    while n > 0 do
      if x >= 10 then dst = dst + 32; x = 0 end
      put(dst + x, tab[n >= 5 and 3 or 2])
      x = x + 1
      n = n - 8
    end
  end
  -- magic meter
  local m = rshift(math.max(0, math.min(128, st.magic or 0)) + 7, 3)
  for k = 0, 3 do put(at.magic + k * 32, ui.magic[m * 4 + k + 1]) end
  -- counters
  local function counter(pos, v, n, full)
    for i, dg in ipairs(digits(v, n)) do
      put(pos + i - 1, bor(0x90 + dg, full and 0x8000 or 0))
    end
  end
  counter(at.rupees, st.rupees, 3, (st.rupees or 0) >= 999)
  local mb = ui.maxBombs and ui.maxBombs[(st.bombLevel or 0) + 1]
  local ma = ui.maxArrows and ui.maxArrows[(st.arrowLevel or 0) + 1]
  counter(at.bombs, st.bombs, 2, mb and (st.bombs or 0) == mb)
  counter(at.arrows, st.arrows, 2, ma and (st.arrows or 0) == ma)
  if (st.keys or 0xFF) == 0xFF then
    put(at.keys, H.BLANK)
    put(at.keyIcon, H.BLANK)
  else
    put(at.keys, 0x90 + (st.keys % 10))
  end
  return w
end

-- 256-colour BG palette of the HUD layer: palettes 0/1 from the blob
-- (0x08130384), 8-15 from the cartridge's fixed HUD colours
function H.palette(data, mode)
  local ui = data.ui
  local pal = {}
  for i = 0, 255 do pal[i] = 0 end
  local base = ui.pal0Blob + (ui.pal0Index[(mode or 0) + 1] or 0)
  for row = 0, 7 do
    for k = 0, 3 do pal[row * 4 + k] = data:blobColor(base + row * 16 + k) end
  end
  for i = 0, 127 do pal[128 + i] = ui.palHi[i + 1] end
  return pal
end

-- 4bpp tile t (0..0x17F) of the HUD charblock -> 64 indices
local function tilePixels(chr, t, cache)
  local hit = cache[t]
  if hit then return hit end
  hit = {}
  local o = t * 32
  for i = 0, 31 do
    local b = chr:byte(o + i + 1) or 0
    hit[i * 2 + 1] = band(b, 15)
    hit[i * 2 + 2] = rshift(b, 4)
  end
  cache[t] = hit
  return hit
end
H.tilePixels = tilePixels

-- words (cols x rows, 1-based) -> flat 0-based colour indices (0 = clear)
function H.decode(chr, words, cols, rows, cache)
  cache = cache or {}
  local W = cols * 8
  local out = {}
  for ty = 0, rows - 1 do
    for tx = 0, cols - 1 do
      local wd = words[ty * cols + tx + 1] or H.BLANK
      local px = tilePixels(chr, band(wd, 0x3FF) % 0x180, cache)
      local hf, vf = band(wd, 0x400) ~= 0, band(wd, 0x800) ~= 0
      local pal = rshift(wd, 12) * 16
      for y = 0, 7 do
        local sy = vf and (7 - y) or y
        local row = (ty * 8 + y) * W + tx * 8
        for x = 0, 7 do
          local c = px[sy * 8 + (hf and (7 - x) or x) + 1]
          out[row + x] = (c ~= 0) and (pal + c) or 0
        end
      end
    end
  end
  return out, W, rows * 8
end

-- The cartridge's menu letters in the HUD charblock (sheet 3 of the
-- language set: A-P at 0x150, Q-Z at 0x160, digits are the HUD's 0x90).
function H.textWords(str, palBits)
  local w = {}
  -- the letters use colours 2/3: palette 8 gives white on a black shadow
  palBits = palBits or 0x8000
  str = str:upper()
  for i = 1, #str do
    local ch = str:sub(i, i)
    local b = ch:byte()
    local t = H.BLANK
    if b >= 65 and b <= 80 then t = 0x150 + (b - 65)
    elseif b >= 81 and b <= 90 then t = 0x160 + (b - 81)
    elseif b >= 48 and b <= 57 then t = 0x90 + (b - 48)
    elseif ch == "-" then t = 0x16B
    end
    w[i] = (t == H.BLANK) and t or bor(t, palBits)
  end
  return w
end

return H
