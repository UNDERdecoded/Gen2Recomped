-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum): the KEYBOARD's own art and geometry.
--
-- Reported from play, twice: the naming screen "is falling back to gen1", and
-- then, after it had a Gen 4 screen of its own, that it "still needs a lot of
-- work before it matches the platinum rom".  It did.  The layout was right --
-- six rows of thirteen, the repeated home-row buttons, the three English pages
-- -- because that much was read out of `NamingScreen_LoadKeyboardLayout`.
-- Everything a player actually LOOKS at was this port's own invention, because
-- `/data/namein.narc` had never been opened.
--
-- THIS ARCHIVE HAS NO NAME TABLE EITHER, so every index below is arithmetic,
-- and arithmetic is what this project has been burned by most.  None of it is
-- inferred: the order is `res/graphics/naming_screen/naming_screen.order` in
-- pokeplatinum -- the file its build feeds to the archiver, which reproduces
-- this cartridge byte for byte -- and every index is then cross-checked
-- against the symbol the app's own loader uses for it in
-- `NamingScreen_LoadGraphicsFromNarc`.  Two independent statements of the same
-- fact, which is the only kind of check worth having here.
--
--    0  naming_screen.NCLR              the background palette
--    1  naming_screen_sprites.NCLR
--    2  naming_screen_main_tiles.NCGR   the tiles BOTH backgrounds are drawn from
--    3  naming_screen_dummy_0.NCGR
--    4  naming_screen_bg.NSCR           the full-screen backdrop
--    5  naming_screen_dummy_1.NSCR
--    6  naming_screen_chars_bg_0.NSCR   the keyboard panel, page 0 (UPPER)
--    7  naming_screen_chars_bg_1.NSCR   page 1 (lower)
--    8  naming_screen_chars_bg_2.NSCR   page 2 (OTHERS)
--    9  naming_screen_chars_bg_3.NSCR   page 3 (the Japanese fourth page)
--   10  naming_screen_sprites.NCGR      the buttons and the cursor
--   12  naming_screen_sprites_cell.NCER
--   14  naming_screen_sprites_anim.NANR
--
-- THE SPRITES ARE NOT EXTRACTED HERE and that is said plainly rather than
-- quietly skipped: members 10/12/14 are a cell bank and its animations, and
-- composing one is a different job from composing a tilemap.  The home row's
-- buttons and the cursor are therefore still drawn in the engine's own frame.
-- The panel behind them, the backdrop, and the colours the keyboard is painted
-- in are the cartridge's.

local Gen4Naming = {}

Gen4Naming.PATH = "/data/namein.narc"

Gen4Naming.PALETTE = 0
Gen4Naming.TILES = 2
Gen4Naming.BACKGROUND_MAP = 4
-- One panel per page, in page order: `naming_screen_chars_bg_0_NSCR_lz +
-- currentCharsIdx` is exactly how the app indexes them when the page changes.
Gen4Naming.PANEL_MAPS = { 6, 7, 8, 9 }

-- ---------------------------------------------------------------------------
-- Where it all sits
-- ---------------------------------------------------------------------------

-- THE PANEL'S RESTING POSITION, and it is a background offset rather than a
-- coordinate.  `NamingScreen_InitializeCharsPosition` parks the active layer at
-- (-11, -80) and the one sliding in at (238, -80); the hardware SCROLLS the
-- view, so an offset of -11 puts the picture eleven pixels to the RIGHT.
Gen4Naming.PANEL_X, Gen4Naming.PANEL_Y = 11, 80

-- ...and the character window inside it: `Window_Add(..., BG_LAYER_MAIN_1, 2,
-- 1, 26, 12, 1, ...)` -- tile (2, 1), twenty-six by twelve tiles, palette row
-- one.  Twenty-six tiles is 208 pixels, which is thirteen columns of sixteen;
-- twelve tiles is 96, which is five rows of nineteen with a pixel to spare.
-- The port had thirteen by SIX at sixteen square and had to guess where to put
-- it; this is the cartridge's own rectangle.
Gen4Naming.WINDOW_TILE_X, Gen4Naming.WINDOW_TILE_Y = 2, 1
Gen4Naming.WINDOW_TILES_W, Gen4Naming.WINDOW_TILES_H = 26, 12
Gen4Naming.WINDOW_PALETTE_ROW = 1

-- The cells, from `NamingScreen_InitializeCharsGraphics` and the
-- `NamingScreen_PrintChars` call inside it: sixteen wide, nineteen tall, five
-- rows, and a glyph sits four pixels down from its cell's top.
Gen4Naming.CELL_W, Gen4Naming.CELL_H = 16, 19
Gen4Naming.CHAR_ROWS, Gen4Naming.COLS = 5, 13
Gen4Naming.GLYPH_INSET = 4

-- THE KEYBOARD IS A CHECKERBOARD, not a flat panel, and it is painted by code
-- rather than stored in the tilemap -- which is why opening the archive alone
-- would not have produced it.  Two colours per page, as palette indices into
-- the window's own row:
--
--   `Window_FillTilemap(window, bgColor)` fills with sCharsBgColor[page], and
--   then two loops fill 16x19 rectangles with sCharsAltBgColor[page]: the odd
--   columns of rows 0, 2 and 4, and the even columns of rows 1 and 3.
--
-- The fourth entry of the alt table is duplicated because the Japanese screen
-- has a fifth page; the English screen never reads past index 2.
Gen4Naming.BG_COLOUR = { 4, 7, 13, 10 }
Gen4Naming.ALT_COLOUR = { 3, 6, 12, 9, 9 }

-- THE HOME ROW IS SPRITES, at their own screen coordinates -- they are not in
-- the panel and not affected by its offset.  `sSpriteAnimations` puts six of
-- them at y = 0x44 and x = 4, 36, 68, 101, 136 and 176.
--
-- Those six are the six buttons the navigation model already has, and their
-- spacing CONFIRMS that model rather than merely being consistent with it: the
-- buttons span 2, 2, 2, 2, 3 and 2 cells of the keyboard's own sixteen-pixel
-- pitch, so laid out from x = 4 they would start at 4, 36, 68, 100, 132 and
-- 180.  Against the cartridge's 4, 36, 68, 101, 136, 176 that is exact on
-- three and within five pixels on the rest -- the difference being that a
-- sprite's x is its art's anchor and not its cell's edge.
--
-- So the row is drawn on the cell pitch from this origin, which is the
-- cartridge's arrangement to within the width of the art that is not extracted.
Gen4Naming.HOME_X = 4
Gen4Naming.HOME_Y = 0x44
Gen4Naming.HOME_SPRITE_X = { 4, 36, 68, 101, 136, 176 }
-- ...BUT THOSE SIX ARE CHILDREN OF THE OVERLAY SPRITE, which sits at x 22: a
-- per-frame task sets child.x = overlay.x + table.x (naming_screen.c
-- 1984-1995). So the buttons are at 26, 58, 90 (the tabs), 158 (BACK) and 198
-- (OK) on screen, and the home-row cursor at sHomeRowCursorXCoords.
Gen4Naming.PARENT_X = 22
Gen4Naming.TAB_X = { 26, 58, 90 }
Gen4Naming.BACK_X, Gen4Naming.OK_X = 158, 198
Gen4Naming.HOME_CURSOR_X = { 25, 57, 89, 97, 122, 158, 198 }

-- ---------------------------------------------------------------------------
-- THE SPRITES (members 1 / 10 / 12 / 14). Every label -- UPPER, lower,
-- Others, BACK, OK, the overlay's SELECT / B BUTTON / START hints -- is baked
-- into these cells; no text bank is involved. The naming screen adds its
-- sprites with SpriteList_AddAffine and no explicit palette, so a cell's own
-- OAM palette picks the row; every cell below has one palette, given here.
-- Cells are taken by INDEX, not "first frame of sequence n": the sequence ->
-- cell mapping is not one to one (sequence 17 shows cell 51).
-- ---------------------------------------------------------------------------
Gen4Naming.SPRITE_PALETTE, Gen4Naming.SPRITE_TILES = 1, 10
Gen4Naming.SPRITE_CELLS, Gen4Naming.SPRITE_ANIMS = 12, 14

Gen4Naming.SPRITES = {
  tab_upper_on = { 0, 1 }, tab_upper_off = { 2, 1 }, tab_lower_on = { 4, 1 }, tab_lower_off = { 6, 1 },
  tab_others_on = { 8, 1 }, tab_others_off = { 10, 1 },
  back = { 19, 1 }, back_pressed = { 20, 1 }, ok = { 21, 1 }, ok_pressed = { 22, 1 },
  overlay = { 31, 2 },
  underscore = { 36, 2 },
  gender_male = { 39, 3 }, gender_female = { 40, 3 },
  icon_box_0 = { 41, 3 }, icon_box_1 = { 42, 3 }, icon_box_2 = { 43, 3 }, icon_box_3 = { 44, 3 },
  icon_male_0 = { 45, 4 }, icon_male_1 = { 46, 4 }, icon_male_2 = { 47, 4 },
  icon_female_0 = { 48, 5 }, icon_female_1 = { 49, 5 }, icon_female_2 = { 50, 5 },
  icon_rival_0 = { 54, 7 }, icon_rival_1 = { 55, 7 }, icon_rival_2 = { 56, 7 },
  icon_palpad = { 58, 8 }, icon_group = { 59, 8 }, icon_shaymin = { 60, 8 },
}
-- the cursor's cells, saved as WHITE MASKS: every opaque pixel is colour 13
-- of row 1, which the screen's glow rewrites every frame (ns.c 2629-2641)
Gen4Naming.CURSOR_SPRITES = {
  cursor_key_0 = 32, cursor_key_1 = 37, cursor_key_2 = 38, cursor_tab = 33, cursor_wide = 34,
  cursor_pop_0 = 65, cursor_pop_1 = 66, cursor_pop_2 = 67, cursor_pop_3 = 68, cursor_pop_4 = 69,
}

function Gen4Naming.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local Cells = require("src.import.Gen4Cells")
  local bytes = rom:read(Gen4Naming.PATH)
  if not bytes then return nil, "namein.narc missing" end
  local narc = N.parse(bytes)
  local function member(i)
    local b = narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local sheet = G.tiles(member(Gen4Naming.SPRITE_TILES))
  local bank = Cells.parse(member(Gen4Naming.SPRITE_CELLS), G)
  local all = G.palette(member(Gen4Naming.SPRITE_PALETTE))
  if not (sheet and bank and all) then return nil, "naming sprites unreadable" end
  local out = {}
  local function cell(key, index, row, mask)
    local c = bank.cells[index + 1]
    if not c then return end
    local flat = {}
    for k, v in pairs(c) do flat[k] = v end
    flat.oam = {}
    for i, o in ipairs(c.oam) do
      local copy = {}
      for k, v in pairs(o) do copy[k] = v end
      copy.palette = 0
      flat.oam[i] = copy
    end
    local colours = {}
    for i = row * 16 + 1, #all do colours[#colours + 1] = all[i] end
    local pic = Cells.assemble(flat, sheet, colours, bank, G)
    if not pic then return end
    if mask then
      local px = {}
      for p = 0, pic.width * pic.height - 1 do
        px[p + 1] = pic.rgba:byte(p * 4 + 4) ~= 0 and "\255\255\255\255" or "\0\0\0\0"
      end
      pic.rgba = table.concat(px)
    end
    pic.originX, pic.originY = Cells.extent(flat)
    out[key] = pic
  end
  for key, s in pairs(Gen4Naming.SPRITES) do cell(key, s[1], s[2]) end
  for key, index in pairs(Gen4Naming.CURSOR_SPRITES) do cell(key, index, 1, true) end
  return out
end

-- the entered name's colours, TEXT_COLOR(14, 15, 1) of background row 0
-- (ns.c 2416-2424), and the glow's base colour row
function Gen4Naming.data(rom)
  local G = require("src.import.Gen4Graphics")
  local bytes = rom:read(Gen4Naming.PATH)
  if not bytes then return {} end
  local b = require("src.import.NarcArchive").parse(bytes):get(Gen4Naming.PALETTE)
  if b and G.isCompressed(b) then b = G.decompress(b) end
  local pal = b and G.palette(b)
  if not pal then return {} end
  return { ink = pal[15], shadow = pal[16], fill = pal[2] }
end

return Gen4Naming
