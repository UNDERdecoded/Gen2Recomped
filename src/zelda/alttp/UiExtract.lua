-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MENU / HUD / TITLE IMPORT (round 4b). Reads the cartridge's own HUD
-- charblock, HUD tilemap tables and palettes, and the title screen's tiles,
-- maps and palettes, the way the routines listed in RomMap.ui load them.
-- Writes:
--
--   assets/generated/alttp/ui_chr.bin    the HUD charblock (VRAM 0x06004000):
--        3 x 4096 bytes, tiles 0x000-0x17F, 4bpp, for the cartridge language
--   assets/generated/alttp/title.bin     the title screen:
--        0x0000 charblock 0 (0x4000 bytes, 4bpp)
--        0x4000 BG1 map (logo, 32x32 words, subtitle strips applied)
--        0x4800 BG2 map (scenery, 32x32 words)
--   data/generated/alttp_ui.lua          HUD tables (template, magic, heart
--        tiles), HUD palettes, title palettes and scroll
--
-- Nothing is invented: every word comes from the tables named in RomMap.ui.

local R = require("src.zelda.alttp.RomMap")

local U = {}

local function check(c, fmt, ...)
  if not c then error("ALttP import (menus): " .. fmt:format(...), 0) end
end

U.FILES = {
  chr   = "assets/generated/alttp/ui_chr.bin",
  title = "assets/generated/alttp/title.bin",
  info  = "data/generated/alttp_ui.lua",
  text  = "assets/generated/alttp/text.bin",   -- BMG DAT1, unscrambled
  font  = "assets/generated/alttp/font.bin",   -- dialogue font, 4bpp
}

-- 0x08129E0C: byte `off` of a scrambled file at `base`
local bit = require("bit")
local bxor, band = bit.bxor, bit.band
function U.unscramble(rom, base, off, key)
  local k, j = band(off, 0xFF), band(off, 15)
  local v = bxor(k - key[16 - j], rom:u8(base + off))
  if off > 0x2A then v = v - rom:u8(base + off - 0x2B) end
  v = bxor(v - k, key[j + 1])
  return band(v, 0xFF)
end

-- the BMG message file: { offsets = { [i] = byte offset in dat }, dat = string }
function U.readText(rom)
  local T = R.text
  local key = rom:bytesU8(T.key, 16)
  local base = T.textBmg
  local function b(off) return U.unscramble(rom, base, off, key) end
  local function str(off, n)
    local t = {}
    for i = 0, n - 1 do t[i + 1] = string.char(b(off + i)) end
    return table.concat(t)
  end
  local function be32(off) return ((b(off) * 256 + b(off + 1)) * 256 + b(off + 2)) * 256 + b(off + 3) end
  check(str(0, 8) == "MESGbmg1", "no message file at %06X", base)
  local nsec = be32(12)
  local o, inf, dat, datSize = 0x20, nil, nil, nil
  for _ = 1, nsec do
    local magic, size = str(o, 4), be32(o + 4)
    check(size > 0 and size < 0x40000, "message section size %X", size)
    if magic == "INF1" then inf = o elseif magic == "DAT1" then dat, datSize = o, size end
    o = o + size
  end
  check(inf and dat, "message file sections")
  local count = b(inf + 8) * 256 + b(inf + 9)
  local offsets = {}
  for i = 0, count - 1 do offsets[i + 1] = be32(inf + 0x10 + i * 4) end
  local parts = {}
  local n = datSize - 8
  for i = 0, n - 1, 4096 do
    local t = {}
    for k = 0, math.min(4095, n - 1 - i) do t[k + 1] = string.char(b(dat + 8 + i + k)) end
    parts[#parts + 1] = table.concat(t)
  end
  return { offsets = offsets, dat = table.concat(parts) }
end
U.CHR_BYTES = 3 * 4096
U.TITLE_BYTES = 0x4000 + 0x800 + 0x800


local function lz(rom, o, want)
  local data, why = rom:lz77(o)
  check(data, "LZ77 at %06X: %s", o, tostring(why))
  if want then check(#data == want, "LZ77 at %06X is %d bytes, expected %d", o, #data, want) end
  return data
end

local function colours(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local c = rom:u16(o + i * 2)
    check(c < 0x8000, "colour word at %06X", o + i * 2)
    t[i + 1] = c
  end
  return t
end

function U.run(rom, cache, tick)
  local S = require("src.zelda.alttp.Serialize")
  local u = R.ui
  -- HUD charblock for the cartridge language
  local parts = {}
  for k = 0, 2 do
    local p = rom:ptr(u.langSheets + (u.lang * 3 + k) * 4)
    check(p, "language %d sheet %d pointer", u.lang, k)
    parts[k + 1] = lz(rom, p, 4096)
  end
  local chr = table.concat(parts)
  if tick then tick(1, 4) end

  local info = {}
  info.template = rom:bytesU16(u.hudTemplate, 6 * 32)
  info.magic = rom:bytesU16(u.hudMagic, 17 * 4)
  info.heartCap = rom:bytesU16(u.hudHeartCap, 3)
  info.heartCur = rom:bytesU16(u.hudHeartCur, 3)
  -- structure checks: the template's blank tile is 0x7F; the full heart
  -- (0xA0) and the empty heart (0xA2) are what the tables name
  check(info.template[1] == 0x7F, "HUD template does not start with the blank tile")
  check(info.heartCur[3] == 0xA0 and info.heartCap[1] == 0xA2, "HUD heart tables")
  info.at = u.hudAt
  -- kMaxBombsForLevel / kMaxArrowsForLevel (read by 0x080A7700/0x080A7776)
  info.maxBombs = rom:bytesU8(u.maxBombs, 8)
  info.maxArrows = rom:bytesU8(u.maxArrows, 8)
  check(info.maxBombs[1] < info.maxBombs[8] and info.maxArrows[1] < info.maxArrows[8],
        "max bombs/arrows tables")
  -- HUD palette 0/1: 8 rows of 4 colours, blob colour 0x308 + index, stride 16
  info.pal0Index = rom:bytesU16(u.hudPal0Index, 4)
  info.pal0Blob = u.hudPal0Blob
  info.palHi = colours(rom, u.hudPalHi, 128)
  info.objPalHi = colours(rom, u.hudPalHi + 0x100, 128)
  if tick then tick(2, 4) end

  -- title screen
  local chr0 = lz(rom, u.titleChr)
  check(#chr0 <= 0x4000, "title tiles too large (%d)", #chr0)
  local vram = {}
  local block = chr0 .. string.rep("\0", 0x4000 - #chr0)
  local function poke(at, s)
    block = block:sub(1, at) .. s .. block:sub(at + #s + 1)
  end
  poke(0x3400, lz(rom, u.titleChr2))
  if u.lang ~= 0 then poke(0x2000, lz(rom, u.titleSub)) end
  vram.chr = block:sub(1, 0x4000)
  local bg1 = lz(rom, u.titleBg1, 0x800)
  local bg2 = lz(rom, u.titleBg2, 0x800)
  -- the subtitle strips (0x08068E7C) write into the BG1 map at 0x0600A000
  if u.lang ~= 0 then
    local o = u.titleStrips
    for _ = 1, 16 do
      local dst = rom:u16(o)
      if dst == 0xFFFF then break end
      local n = rom:u16(o + 2) % 0x4000
      o = o + 4
      local rel = dst - 0xA000
      check(rel >= 0 and rel + n * 2 <= 0x800, "title strip outside BG1 (%04X)", dst)
      bg1 = bg1:sub(1, rel) .. rom:sub(o, n * 2) .. bg1:sub(rel + n * 2 + 1)
      o = o + n * 2
    end
  end
  if tick then tick(3, 4) end
  info.titlePal = colours(rom, u.titlePal, 128)
  info.titlePal2 = colours(rom, u.titlePal2, 16)
  info.titleScroll = u.titleScroll

  -- dialogue: the BMG file, unscrambled, plus the font and its widths
  local text = U.readText(rom)
  info.textOffsets = text.offsets
  info.textWidths = rom:bytesU8(R.text.widths, 0x200)
  info.textBorder = rom:bytesU16(R.text.border, 9)
  info.textWindowPos = rom:bytesU16(R.text.windowPos, 2)
  info.textWaits = rom:bytesU16(R.text.waits, 16)
  check(info.textWaits[1] < info.textWaits[16], "text wait table")
  assert(cache:write(U.FILES.text, text.dat))
  assert(cache:write(U.FILES.font, rom:sub(R.text.font, R.text.fontBytes)))

  assert(cache:write(U.FILES.chr, chr))
  assert(cache:write(U.FILES.title, vram.chr .. bg1 .. bg2))
  assert(cache:write(U.FILES.info, S.encode(info)))
  if tick then tick(4, 4) end
end

function U.files()
  return { U.FILES.chr, U.FILES.title, U.FILES.info, U.FILES.text, U.FILES.font }
end

return U
