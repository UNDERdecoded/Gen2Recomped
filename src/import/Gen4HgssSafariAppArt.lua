-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- HEARTGOLD / SOULSILVER'S SAFARI ZONE APPS' ART (overlay 108; pokeheartgold
-- asm/overlay_108.s and asm/overlay_108_021E8850.s, undecompiled) ->
-- `gen4_hgss_safari_apps`, drawn by src/ui/HgssSafariCustomizer.lua and
-- src/ui/HgssSafariDecoration.lua.
--
-- THE AREA CUSTOMIZER (ScrCmd_716): NARC_a_1_6_6 (/a/1/6/6, NARC id 0xA6).
-- POWCNT bit 15 cleared (ov108_021E6C68): the main engine is the BOTTOM
-- (touch) screen, the sub engine the top. ov108_021E6D80 loads:
--   6  NCGR -> main BG3 / sub BG0     1  NCGR -> sub BG3
--   5  NCLR -> main BG                0  NCLR -> sub BG
--   10 NSCR -> main BG2: the arrangement board (slots at 24 + 72 col,
--               24 + 72 row, the ov108_021EA760 hitboxes)
--   7  NSCR -> main BG3: the area picker's page (slots at 16 + 80 col,
--               ov108_021EA7D0)
--   4  NSCR -> sub BG2: the top board, over
--   2 / 3 NSCR -> sub BG3: the objects page (2, five count rows) when
--               Baoba's unlock level is above 0, else the plain page (3)
--   8  NSCR kept: the message frames ov108_021E767C copies to main BG0
--               (rows 0..2 one line, 3..8 two lines, 24 tiles wide)
--   18 + area NCGR (8bpp, 64 tiles): the area's picture, loaded by
--               ov108_021E7B74 to sub BG1 at tile 1 + 64 slot and laid out
--               by ov108_021E7ADC 8 x 8 at tile (3 + 9 col, 3 + 9 row)
--   11 / 12 / 13 / 14  NCLR / NCGR / NCER / NANR: the cursors and buttons
--               (ov108_021E78F4: sequence 0 the 80 x 80 slot cursor, 1 the
--               Quit cursor, 2 the sort marker, 3 the flashing sort cursor,
--               4 / 5 the page arrows, 6 / 7 their pressed frames)
-- THE DECORATION APP (ScrCmd_717): NARC_a_2_2_3 (/a/2/2/3, NARC id 0xE1).
-- POWCNT bit 15 set (ov108_021E9850): main (3D, BG0) on TOP, sub below.
-- ov108_021E9A60 loads:
--   1  NCGR -> main BG3     5  NCGR -> sub BG3
--   0  NCLR -> main BG      4  NCLR -> sub BG
--   2  NSCR -> main BG3: the preview frame;  3 NSCR -> main BG2: the text bar
--   6  NSCR -> sub BG3: the six slots;  8 / 6 / 7 kept: the button plates,
--               the list page and the confirm page
--   9 / 10 / 11 / 12  NCLR / NCGR / NCER / NANR: the cursors, page arrows
--               and the Return button
-- THE YES / NO BUTTONS (YesNoPrompt, src/yes_no_prompt.c):
-- NARC_system_touch_subwindow (/a/1/5/2): palette 0, tiles 1, the button
-- screens 2 + j + 2 i (i 0 YES / 1 NO, j 0 / 1 its two looks), 6 x 4 tiles.
-- THE ACTION MENU (ov108_021E6A58 -> TouchscreenListMenu_Create):
-- NARC_data_sbox_gra (/a/1/6/5), its tiles kept as one row of 8 x 8 tiles
-- in the order the menu indexes them (charOffset + 0..23: top / side /
-- separator / bottom, + 12 the selected look, + 18 the separator under a
-- selected button) and its palette's inks (MAKE_TEXT_COLOR(1, 2, 3) idle,
-- (4, 5, 6) selected).
-- THE AREA PICTURES' OBJ PALETTE: the bottom board's and picker's pictures
-- are 64 x 64 sprites whose characters ov108_021E84F8 replaces with member
-- 18 + area (ReplaceCharResObjFromNarc); their palette is member 15.
-- THE INK: LoadFontPal1 (NARC_graphic_font member 8, /a/0/1/6).

local Gen4Graphics = require("src.import.Gen4Graphics")

local A = {
  CUSTOMIZER = "/a/1/6/6", DECORATION = "/a/2/2/3", YESNO = "/a/1/5/2",
  -- NARC_data_sbox_gra (id 165): the TouchscreenListMenu's buttons
  -- (touchscreen_list_menu.c: member 0 NCLR, 1 NCGR)
  SBOX = "/a/1/6/5",
  FONT_PATH = "/a/0/1/6", FONT_PALETTE = 8,
}

local function member(arc, i)
  local b = arc and arc:get(i)
  if b and Gen4Graphics.isCompressed(b) then b = Gen4Graphics.decompress(b) end
  return b
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
      local entry = x:saveImage(("safari_apps/%s_cell_%d"):format(prefix, i - 1), image)
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

local function screen(x, arc, mapIndex, tiles, pal, name)
  local map = Gen4Graphics.tilemap(member(arc, mapIndex))
  local img = map and Gen4Graphics.compose(map, tiles, pal)
  return img and x:saveImage("safari_apps/" .. name, img) or nil
end

local function colour(p, line, i)
  local v = p and p[line * 16 + i + 1]
  return v and { v[1], v[2], v[3] } or nil
end

function A.build(x)
  local Narc = require("src.import.NarcArchive")
  local out = { source = "ROM:" .. A.CUSTOMIZER .. " / " .. A.DECORATION .. " (overlay 108)" }

  -- the customizer
  local cz = assert(Narc.parse(assert(x.rom:read(A.CUSTOMIZER))))
  local mainTiles, subTiles = Gen4Graphics.tiles(member(cz, 6)), Gen4Graphics.tiles(member(cz, 1))
  local mainPal, subPal = Gen4Graphics.palette(member(cz, 5)), Gen4Graphics.palette(member(cz, 0))
  assert(mainTiles and subTiles and mainPal and subPal, "safari customizer: tiles 6 / 1 or palettes 5 / 0 did not decode")
  local c = {}
  c.board = screen(x, cz, 10, mainTiles, mainPal, "cz_board")
  c.picker = screen(x, cz, 7, mainTiles, mainPal, "cz_picker")
  c.frames = screen(x, cz, 8, mainTiles, mainPal, "cz_frames")
  c.topBoard = screen(x, cz, 4, subTiles, subPal, "cz_top_board")
  c.topObjects = screen(x, cz, 2, subTiles, subPal, "cz_top_objects")
  c.topPlain = screen(x, cz, 3, subTiles, subPal, "cz_top_plain")
  assert(c.board and c.picker and c.topBoard, "safari customizer: the screens did not compose")
  c.areas = {}
  for area = 0, 11 do
    local sheet = Gen4Graphics.tiles(member(cz, 18 + area))
    if sheet then
      local cells = {}
      for i = 0, 63 do cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = 0 } end
      local img = Gen4Graphics.compose({ width = 64, height = 64, cells = cells }, sheet, subPal)
      c.areas[area] = img and x:saveImage(("safari_apps/cz_area_%d"):format(area), img) or false
      -- the same picture as the OBJ sprite wears it (palette member 15)
      local objPal15 = Gen4Graphics.palette(member(cz, 15))
      local oimg = objPal15 and Gen4Graphics.compose({ width = 64, height = 64, cells = cells }, sheet, objPal15)
      c.areaSprites = c.areaSprites or {}
      c.areaSprites[area] = oimg and x:saveImage(("safari_apps/cz_area_obj_%d"):format(area), oimg) or false
    end
  end
  local objPal = Gen4Graphics.palette(member(cz, 11))
  c.sprites = objPal and sprites(x, cz, objPal, 12, 13, 14, "cz") or nil
  -- the windows' inks (ov108_021E7700 / ov108_021E7CD8: MAKE_TEXT_COLOR)
  c.inks = {
    message = { colour(mainPal, 4, 0xD), colour(mainPal, 4, 0xC), colour(mainPal, 4, 0xE) },  -- 0x000D0C0E, pal 4
    button = { colour(mainPal, 12, 3), colour(mainPal, 12, 1) },                              -- 0x00030102, pal 12
    area = { colour(subPal, 5, 8), colour(subPal, 5, 0xB) },                                  -- 0x00080B0C, pal 5
  }
  out.customizer = c

  -- the decoration app
  local dc = assert(Narc.parse(assert(x.rom:read(A.DECORATION))))
  local topTiles, botTiles = Gen4Graphics.tiles(member(dc, 1)), Gen4Graphics.tiles(member(dc, 5))
  local topPal, botPal = Gen4Graphics.palette(member(dc, 0)), Gen4Graphics.palette(member(dc, 4))
  assert(topTiles and botTiles and topPal and botPal, "safari decoration: tiles 1 / 5 or palettes 0 / 4 did not decode")
  local d = {}
  d.topFrame = screen(x, dc, 2, topTiles, topPal, "dc_top_frame")
  d.topBar = screen(x, dc, 3, topTiles, topPal, "dc_top_bar")
  d.list = screen(x, dc, 6, botTiles, botPal, "dc_list")
  d.confirm = screen(x, dc, 7, botTiles, botPal, "dc_confirm")
  d.plates = screen(x, dc, 8, botTiles, botPal, "dc_plates")
  assert(d.topFrame and d.list and d.plates, "safari decoration: the screens did not compose")
  local dPal = Gen4Graphics.palette(member(dc, 9))
  d.sprites = dPal and sprites(x, dc, dPal, 10, 11, 12, "dc") or nil
  out.decoration = d

  -- Yes / No (touch_subwindow)
  local okY, yn = pcall(function() return Narc.parse(assert(x.rom:read(A.YESNO))) end)
  if okY and yn then
    local t, p = Gen4Graphics.tiles(member(yn, 1)), Gen4Graphics.palette(member(yn, 0))
    if t and p then
      out.yesNo = {}
      for i = 0, 1 do
        out.yesNo[i] = {}
        for j = 0, 1 do
          -- each button's two looks; its palette line is the template's slot + i
          -- (YesNoPrompt_InitButtonsFromTemplate) -- composed with the file's own
          out.yesNo[i][j] = screen(x, yn, 2 + j + i * 2, t, p, ("yesno_%d_%d"):format(i, j)) or false
        end
      end
    end
  end

  -- the TouchscreenListMenu's buttons (sbox_gra)
  local okS, sb = pcall(function() return Narc.parse(assert(x.rom:read(A.SBOX))) end)
  if okS and sb then
    local t, p = Gen4Graphics.tiles(member(sb, 1)), Gen4Graphics.palette(member(sb, 0))
    if t and p then
      local n = math.min(t.count or 0, 32)
      local cells = {}
      for i = 0, n - 1 do cells[i + 1] = { tile = i, flipX = false, flipY = false, palette = 0 } end
      local img = Gen4Graphics.compose({ width = n * 8, height = 8, cells = cells }, t, p)
      out.listMenu = {
        tiles = img and x:saveImage("safari_apps/sbox_tiles", img, { count = n }) or nil,
        colours = {},
      }
      for i = 0, 15 do out.listMenu.colours[i] = colour(p, 0, i) end
    end
  end

  -- LoadFontPal1: the system font's palette (text 1, shadow 2)
  local okF, font = pcall(function() return Narc.parse(assert(x.rom:read(A.FONT_PATH))) end)
  local fp = okF and font and Gen4Graphics.palette(member(font, A.FONT_PALETTE))
  if fp then
    out.fontInk = { colour(fp, 0, 1), colour(fp, 0, 2), colour(fp, 0, 15) }
    -- every colour of the line, for the windows that name other indices
    -- (the decoration's page number: MAKE_TEXT_COLOR(3, 4, 0))
    out.fontColours = {}
    for i = 0, 15 do out.fontColours[i] = colour(fp, 0, i) end
  end
  return out
end

return A
