-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S UNOWN REPORT (key item 469, fieldUseFunc 25 ->
-- UnownReport_LaunchApp, overlay 113 -- undecompiled, pokeheartgold
-- asm/overlay_113.s). The art is NARC_a_2_3_9 (/a/2/3/9, NARC id 0xF1 that
-- ov113_021E650C opens):
--
--   0       NCLR, the buttons (main OBJ; resdat 7)
--   1..3    NCGR / NCER / NANR, the CANCEL button and the two page arrows
--           (resdat 6 / 5 / 4; header 0x49): sequences 0 / 1 CANCEL idle /
--           pressed, 2 / 3 / 4 up idle / pressed / off, 5 / 6 / 7 down
--   4       NCLR, the top screen (sub BG)
--   5       NCLR, the bottom screen (main BG)
--   6 / 8   NCGR / NSCR, the top screen's paper (sub BG7, priority 3)
--   7 / 9   NCGR / NSCR, the bottom screen's paper (main BG3)
--   10 / 11 NSCR, the cover page, top (BG6 over 6's tiles) / bottom (BG2)
--   12 / 13 NSCR, an UNOWN list page, top / bottom
--   14 / 15 NSCR, a report page, top / bottom
--
-- The list pages' glyphs are the Pokemon icons (NARC_poketool_icongra_poke_
-- icon, the cache's `icons`, GetMonIconNaixEx(SPECIES_UNOWN, 0, form)) in the
-- icon archive's 32 x 32 cell bank 2 / animation bank 1, sequence 0 -- the
-- bounce, read here. The report pages (ov113_021E6BD0, read out of the
-- overlay: six spreads of two u16, start:6 / count:2 / level:8 into msg_0001)
-- open with VAR_UNOWN_REPORT_LEVEL. The text is msg_0001 (src/ui/
-- HgssUnownReport.lua prints it) on LoadFontPal1 -- NARC_graphic_font member 8.

local Gen4Graphics = require("src.import.Gen4Graphics")

local A = { PATH = "/a/2/3/9", ICON_PATH = "/a/0/2/0", FONT_PATH = "/a/0/1/6", FONT_PALETTE = 8,
            OVERLAY = 113 }

-- ov113_021E6BD0 as the asm has it: the fallback when the overlay scan finds
-- nothing (a ROM whose overlay 113 is laid out differently)
A.SPREADS = { 0x0146, 0x0147, 0x0248, 0x0349, 0x044A, 0x044B,
              0x054C, 0x064D, 0x07CE, 0x0751, 0x0852, 0x0853 }

local function member(arc, i)
  local b = arc and arc:get(i)
  if b and Gen4Graphics.isCompressed(b) then b = Gen4Graphics.decompress(b) end
  return b
end

function A.decodeSpread(v)
  return { start = v % 64, count = math.floor(v / 64) % 4, level = math.floor(v / 256) % 256 }
end

-- twelve u16 in a row, each a (start, count >= 1, level) whose starts climb
-- by the previous count (6, 7, 8, ...), levels never falling: the only run of
-- that shape in the overlay is the spread table
local function isSpreads(s, at)
  local nextStart, lastLevel = nil, 0
  for i = 0, 11 do
    local lo, hi = s:byte(at + i * 2, at + i * 2 + 1)
    if not hi then return false end
    local r = A.decodeSpread(lo + hi * 256)
    if r.count == 0 or r.level == 0 or r.level < lastLevel or r.level > 32 then return false end
    if nextStart and r.start ~= nextStart then return false end
    if not nextStart and r.start == 0 then return false end
    nextStart, lastLevel = r.start + r.count, r.level
  end
  return true
end

function A.spreads(rom)
  local ok, ov = pcall(function() return rom:overlay(A.OVERLAY) end)
  if ok and type(ov) == "string" then
    for at = 1, #ov - 23, 4 do
      if isSpreads(ov, at) then
        local out = {}
        for i = 0, 11 do
          local lo, hi = ov:byte(at + i * 2, at + i * 2 + 1)
          out[i + 1] = lo + hi * 256
        end
        return out, ("overlay %d +0x%X"):format(A.OVERLAY, at - 1)
      end
    end
  end
  return A.SPREADS, "asm/overlay_113.s ov113_021E6BD0 (transcribed)"
end

local function sprites(x, arc, colours, sheetIndex, cellIndex, animIndex, prefix)
  local Gen4Cells = require("src.import.Gen4Cells")
  local Gen4CellAnim = require("src.import.Gen4CellAnim")
  local sheet = Gen4Graphics.tiles(member(arc, sheetIndex))
  local cellBytes = member(arc, cellIndex)
  local bank = cellBytes and Gen4Cells.parse(cellBytes, Gen4Graphics)
  local animBytes = member(arc, animIndex)
  local anim = animBytes and Gen4CellAnim.parse(animBytes, Gen4Graphics)
  if not (sheet and bank and anim) then return nil end
  local rec = { cells = {}, anims = {} }
  for i, cell in ipairs(bank.cells) do
    local image = Gen4Cells.assemble(cell, sheet, colours, bank, Gen4Graphics)
    if image then
      local minX, minY = Gen4Cells.extent(cell)
      local entry = x:saveImage(("unown_report/%s_cell_%d"):format(prefix, i - 1), image)
      if entry then entry.ox, entry.oy = -(minX or 0), -(minY or 0) end
      rec.cells[i] = entry or false
    else
      rec.cells[i] = false
    end
  end
  for s, seq in ipairs(anim.sequences or {}) do
    local frames = {}
    for _, f in ipairs(Gen4CellAnim.frames(anim, s - 1) or {}) do
      frames[#frames + 1] = { cell = f.cell, duration = f.duration }
    end
    rec.anims[s] = { frames = frames, mode = seq.playbackMode }
  end
  return rec
end

function A.build(x)
  local Narc = require("src.import.NarcArchive")
  local arc = assert(Narc.parse(assert(x.rom:read(A.PATH))))
  local topPal = Gen4Graphics.palette(member(arc, 4))
  local botPal = Gen4Graphics.palette(member(arc, 5))
  local topTiles = Gen4Graphics.tiles(member(arc, 6))
  local botTiles = Gen4Graphics.tiles(member(arc, 7))
  assert(topPal and botPal and topTiles and botTiles, "unown report: palettes 4 / 5 or tiles 6 / 7 did not decode")
  local out = { source = "ROM:" .. A.PATH .. " (overlay 113, ov113_021E650C)" }
  local function screen(n, tiles, pal, name)
    local map = Gen4Graphics.tilemap(member(arc, n))
    local img = map and Gen4Graphics.compose(map, tiles, pal)
    return img and x:saveImage("unown_report/" .. name, img) or nil
  end
  out.top = { base = screen(8, topTiles, topPal, "top_base"),
              cover = screen(10, topTiles, topPal, "top_cover"),
              list = screen(12, topTiles, topPal, "top_list"),
              report = screen(14, topTiles, topPal, "top_report") }
  out.bottom = { base = screen(9, botTiles, botPal, "bottom_base"),
                 cover = screen(11, botTiles, botPal, "bottom_cover"),
                 list = screen(13, botTiles, botPal, "bottom_list"),
                 report = screen(15, botTiles, botPal, "bottom_report") }
  assert(out.top.base and out.bottom.base, "unown report: the base screens did not compose")
  local function backdrop(p) local c = p and p[1]; return c and { c[1], c[2], c[3] } or nil end
  out.top.backdrop, out.bottom.backdrop = backdrop(topPal), backdrop(botPal)
  local objPal = Gen4Graphics.palette(member(arc, 0))
  out.buttons = objPal and sprites(x, arc, objPal, 1, 2, 3, "buttons") or nil
  -- the report spreads
  local raw, from = A.spreads(x.rom)
  out.spreads, out.spreadSource = {}, from
  for i = 1, #raw, 2 do
    out.spreads[#out.spreads + 1] = { left = A.decodeSpread(raw[i]), right = A.decodeSpread(raw[i + 1]) }
  end
  -- the icons' bounce: icongra NANR 1, sequence 0 (cells of bank 2: frame n
  -- of the 32 x 64 sheet is cell n)
  local okI, icon = pcall(function() return Narc.parse(assert(x.rom:read(A.ICON_PATH))) end)
  if okI and icon then
    local okA, anim = pcall(function()
      local Gen4CellAnim = require("src.import.Gen4CellAnim")
      local a = Gen4CellAnim.parse(member(icon, 1), Gen4Graphics)
      return a and Gen4CellAnim.frames(a, 0)
    end)
    if okA and type(anim) == "table" then
      out.iconFrames = {}
      for _, f in ipairs(anim) do out.iconFrames[#out.iconFrames + 1] = { cell = f.cell, duration = f.duration } end
    end
  end
  -- THE INKS: LoadFontPal1 on line 12 of both screens; MAKE_TEXT_COLOR(1, 2, 0)
  -- for the pages, (15, 2, 0) for the page number, (7, 15, 0) for CANCEL
  local okF, font = pcall(function() return Narc.parse(assert(x.rom:read(A.FONT_PATH))) end)
  local fp = okF and font and Gen4Graphics.palette(member(font, A.FONT_PALETTE))
  if fp then
    local function c(i) local v = fp[i + 1]; return v and { v[1], v[2], v[3] } or nil end
    out.inks = { text = { c(1), c(2) }, page = { c(15), c(2) }, cancel = { c(7), c(15) } }
  end
  return out
end

return A
