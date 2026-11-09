-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE OVERWORLD PALETTE, built the way the GBA cartridge builds it.
--
-- The GBA keeps the SNES palette *selection* (kOwBgPalInfo, the per-screen
-- palette set, the overworld "mode"), but the colours live in one 4096-entry
-- blob laid out as 16 pages of 16x16, and each loader copies 8-colour rows out
-- of it. This is a port of the GBA routines:
--
--   OWBGMain (0x081305E0)  mode row  + 0xD00, 5 rows -> colours 0x20,0x30..0x60
--   OWBG1    (0x0813068C)  aux1 row  + 0xE00, 3 rows -> 0x28,0x38,0x48
--   OWBG2    (0x0813076C)  aux2 row  + 0xE00, 3 rows -> 0x58,0x68,0x78
--   OWBG3    (inline)      aux3 row  + 0xC00, 1 row  -> 0x70
--
-- with the row step every one of them shares: after 8 colours, a source that
-- lands on a page boundary stays, one that lands on column 0xF8 wraps to column
-- 8 of the same page, anything else skips the other half of the 16-wide row.
-- Entry 8 of palettes 2..7 and colour 0 are the backdrop (grass) colour, which
-- the cartridge picks per world (0x08130A24).

local bit = require("bit")
local band, bor = bit.band, bit.bor

local P = {}

local function rows(data, start, nrows, dst, pal)
  local r3 = start
  for row = 0, nrows - 1 do
    for i = 0, 7 do
      pal[dst + row * 16 + i] = data:blobColor(r3)
      r3 = band(r3 + 1, 0xFFFF)
    end
    if band(r3, 0xFF) == 0 then
      -- page boundary: keep
    elseif band(r3, 0xF8) == 0xF8 then
      r3 = band(r3, 0xFF08)
    else
      r3 = r3 + 8
    end
  end
end
P._rows = rows

-- The palette selection for a screen (0..127): bg set, mode, aux1..3.
function P.selection(data, screen, phase)
  local t = data.t
  phase = math.max(0, math.min(3, phase or 0))
  local bg
  if screen < 64 then
    bg = t.owBgPalLW[phase + 1][screen + 1]
  else
    bg = t.owBgPalDW[screen - 64 + 1]
  end
  local sc = band(screen, 0x3F)
  local mode = ((sc == 3 or sc == 5 or sc == 7) and 2 or 0) + (band(screen, 0x40) ~= 0 and 1 or 0)
  local info = t.owBgPalInfo[bg + 1]
  -- Overworld_LoadAllPalettes' defaults, overridden where the set says so
  local aux1, aux2, aux3 = 3, 3, 0
  if info[1] ~= 0xFF then aux1 = info[1] end
  if info[2] ~= 0xFF then aux2 = info[2] end
  if info[3] ~= 0xFF then aux3 = info[3] end
  return { bg = bg, mode = mode, aux1 = aux1, aux2 = aux2, aux3 = aux3 }
end

function P.backdrop(data, screen)
  local b = data.t.backdrop
  local sc = band(screen, 0x3F)
  if band(screen, 0x40) ~= 0 then return b.dw end
  if sc == 3 or sc == 5 or sc == 7 then return b.dm end
  return b.lw
end

-- 256 BGR555 words, 0-based, for the BG of an overworld screen.
function P.overworld(data, screen, phase)
  local t = data.t
  local sel = P.selection(data, screen, phase)
  local pal = {}
  for i = 0, 255 do pal[i] = 0 end
  rows(data, t.palIndexMain[sel.mode + 1] + 0xD00, 5, 0x20, pal)
  rows(data, t.palIndexAux12[sel.aux1 + 1] + 0xE00, 3, 0x28, pal)
  rows(data, t.palIndexAux12[sel.aux2 + 1] + 0xE00, 3, 0x58, pal)
  local r3 = t.palIndexAux3[sel.aux3 + 1] + 0xC00
  for i = 0, 7 do pal[0x70 + i] = data:blobColor(r3 + i) end
  local bd = P.backdrop(data, screen)
  pal[0] = bd
  for p = 2, 7 do pal[p * 16 + 8] = bd end
  return pal, sel
end

-- Link's green-mail sprite palette: 16 colours from the blob's sprite page.
P.LINK_ROW = 0xB0
function P.link(data)
  local pal = {}
  for i = 0, 15 do pal[i] = data:blobColor(P.LINK_ROW + i) end
  return pal
end

-- BGR555 -> r, g, b in 0..1 (x * 255 / 31, like RomGba)
function P.rgb(c)
  local r = band(c, 31)
  local g = band(math.floor(c / 32), 31)
  local b = band(math.floor(c / 1024), 31)
  return r / 31, g / 31, b / 31
end

P._bor = bor
return P
