-- PLATINUM'S SUMMARY SCREEN ART (src/applications/pokemon_summary_screen/
-- {main,window,sprites,subscreen}.c), from /graphic/pl_pst_gra.narc, the
-- battle type icons in /battle/graphic/pl_batt_obj.narc and the "Lv" glyph in
-- pl_font.narc's font_special_chars.
--
-- The PAGES themselves (page_<name>, move_info) are gen4_graphics' screens --
-- tiles_main.NCGR / tiles_main.NCLR under each NSCR -- and are not repeated
-- here.  This module is everything the cartridge draws ON them:
--
-- SPRITES (pokemon_summary_screen.json + sprites.c), every one with the
-- EXPLICIT palette its template gives it: SpriteSystem_NewSpriteFromResource-
-- Header calls Sprite_SetExplicitPalette(sprite, plttIdx), which REPLACES the
-- cell's own OAM palette.  The palette resources land in OBJ rows in load
-- order -- sprites.NCLR 0..2, type_icons/shared.NCLR 3..5, status_icons.NCLR
-- 6, ribbons.NCLR 7..11, balls_N.NCLR 12 -- so a template's plttIdx is an
-- absolute row, and for the shared sheet it is the row of sprites.NCLR:
--
--   tab_<s>            tabs sequence s (0..7 page, +8 focused); row 1 for
--                      info / memo / skills / condition, row 2 for battle
--                      moves / contest moves / ribbons / exit
--   tab_arrow_<s>      tab_arrow 0 left, 1 right; row 1
--   move_cursor_<s>    move_cursor 0 the cursor, 1 the "swap from" marker; row 2
--   marking_<name>_<s> markings_anim s (0 off, 1 on) over marking_<name>; row 0
--   shiny / pokerus_cured   shiny_and_pokerus_cured_icon, markings_anim 0 / 1; row 2
--   a_button           a_button over condition_arrow's cell; row 0
--   sheen_<f>          sheen_anim sequence 0, frame f; row 2
--   ribbon_cursor      row 2;  ribbon_arrow_<s> (0 down, 1 up) row 1
--   pokerus_icon       row 1
--   contest_dot_<s>    contest_stat_dot sequence s in its template's row
--   status_<s>         status_icons sequence s (1 PAR .. 5 BRN, 6 FNT), status_icons.NCLR
--   ball_<id>          the caught ball, balls_<sBallIDToPaletteNum>.NCLR row 0
--   type_<name>        type_icons/<name> with TypeIcon_GetPltt's row of shared.NCLR
--                      (the 17 types, mystery, and the five contest types)
--   category_<name>    physical / special / status, CategoryIcon_GetPltt's row
--
-- every sprite carries originX/originY: the cell's top-left relative to the
-- sprite's position, so `draw(img, x + originX, y + originY)` is the OAM.
--
-- BACKGROUND PIECES the cartridge writes into the page tilemap at run time:
--   hp_green / hp_yellow / hp_red   tiles 0xC0 / 0xE0 / 0x100 + 0..8 in palette
--                      10, 72 x 8 (tile n is a bar n pixels full) -- DrawHealthBar
--   exp_bar            tiles 0xAC + 0..8, palette 0 -- DrawExperienceProgressBar
--   heart_filled / heart_empty   the 2x2 appeal hearts 0x12C / 0x12E in the
--                      palette move_info's own heart row uses -- DrawAppealHeart
--   lv                 font_special_chars tiles 11-12 in the summary's black
-- BOTTOM SCREEN (subscreen.c):
--   sub_backdrop       tiles_sub.NSCR over tiles_sub, tiles_sub.NCLR
--   sub_button_<p>_<a> sub_buttons 5x5 for page p (0..7), anim a (0 up, 1 lit,
--                      2 pressed), in the button's palette from sSubscreenButtons
--   tap_<f>            the tap circle a pressed button shows, frame f
--                      (pl_bag_gra's button_shockwave in pl_plist_gra 23)
--
-- `data(rom)` is tiles_main.NCLR row 15 -- the window palette every summary
-- string is printed in: black 1/2, blue 3/4, red 5/6, white 15/14.
--
-- Written to assets/generated/gen4/summary_art/<key>.png, indexed in the cache
-- module `gen4_summary_art`; the colours in `gen4_summary_ink`.

local Gen4SummaryArt = {}

Gen4SummaryArt.PATH = "/graphic/pl_pst_gra.narc"
Gen4SummaryArt.BATTLE_PATH = "/battle/graphic/pl_batt_obj.narc"
Gen4SummaryArt.FONT_PATH = "/graphic/pl_font.narc"

-- sprites.c's templates: the shared-sheet row each one is drawn in
Gen4SummaryArt.TAB_ROW = { [0] = 1, 1, 1, 2, 1, 2, 2, 2 }
Gen4SummaryArt.MARKINGS = { "circle", "triangle", "square", "heart", "star", "diamond" }
-- SUMMARY_SPRITE_CONTEST_STAT_DOT_*: anim -> plttIdx
Gen4SummaryArt.DOT_ROW = { [0] = 2, 1, 1, 2, 0 }

-- type_icon.c sMoveTypeIconPaletteIndex / sMoveCategoryIconPaletteIndex
Gen4SummaryArt.TYPE_ROW = {
  normal = 0, fighting = 0, flying = 1, poison = 1, ground = 0, rock = 0,
  bug = 2, ghost = 1, steel = 0, mystery = 2, fire = 0, water = 1, grass = 2,
  electric = 0, psychic = 1, ice = 1, dragon = 2, dark = 0,
  cool = 0, beauty = 1, cute = 1, smart = 2, tough = 0,
}
Gen4SummaryArt.CATEGORY_ROW = { physical = 0, special = 1, status = 0 }

-- sprites.c sBallIDToPaletteNum, by item id 1..16
Gen4SummaryArt.BALLS = { "master", "ultra", "great", "poke", "safari", "net", "dive", "nest",
  "repeat", "timer", "luxury", "premier", "dusk", "heal", "quick", "cherish" }
Gen4SummaryArt.BALL_PALETTE = { 0, 2, 2, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 2, 0 }

-- main.c's run-time tiles
Gen4SummaryArt.HP_TILES = { green = 0xC0, yellow = 0xE0, red = 0x100 }
Gen4SummaryArt.HP_PALETTE = 10
Gen4SummaryArt.EXP_TILE = 0xAC
Gen4SummaryArt.HEART_FILLED, Gen4SummaryArt.HEART_EMPTY = 0x12C, 0x12E
Gen4SummaryArt.HEART_ROW, Gen4SummaryArt.HEART_COL = 47, 2

-- subscreen.c sSubscreenButtons_Normal: page -> palette
Gen4SummaryArt.BUTTON_PALETTE = { [0] = 1, 1, 2, 3, 2, 3, 4, 4 }

-- the tap circle's resources (data/pst_chr.resdat 16, pst_cell 9, pst_canm 9,
-- pst_pal 4): NARC_INDEX_GRAPHIC__PL_BAG_GRA 36 / 35 / 34 and
-- NARC_INDEX_GRAPHIC__PL_PLIST_GRA 23.  Its animation is 3 + 2 frames, and
-- HideButtonTapCircle drops it on the third.
Gen4SummaryArt.TAP_PATH = "/graphic/pl_bag_gra.narc"
Gen4SummaryArt.TAP_PALETTE_PATH = "/graphic/pl_plist_gra.narc"
Gen4SummaryArt.TAP_MEMBERS = { char = 36, cell = 35, anim = 34, palette = 23 }

local floor = math.floor

local function opener(rom, path)
  local G = require("src.import.Gen4Graphics")
  local A = require("src.import.Gen4Archives")
  local bytes = rom:read(path)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  return function(nameOrIndex)
    local i = type(nameOrIndex) == "number" and nameOrIndex or A.find(path, nameOrIndex)
    local b = i and narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

local function row(colours, r)
  local out = {}
  for i = 1, 16 do out[i] = colours and colours[r * 16 + i] or { 0, 0, 0 } end
  return out
end

-- one cell with every OAM entry forced to palette 0 (the explicit palette),
-- assembled; origin = the cell's extent
local function assembleCell(cell, sheet, colours, bank)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  if not (cell and sheet and colours) then return nil end
  local flat = {}
  for k, v in pairs(cell) do flat[k] = v end
  flat.oam = {}
  for i, o in ipairs(cell.oam) do
    local c = {}
    for k, v in pairs(o) do c[k] = v end
    c.palette = 0
    flat.oam[i] = c
  end
  local pic = Cells.assemble(flat, sheet, colours, bank, G)
  if pic then pic.originX, pic.originY = Cells.extent(flat) end
  return pic
end

function Gen4SummaryArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local member = opener(rom, Gen4SummaryArt.PATH)
  if not member then return nil, "pl_pst_gra missing" end
  local out = {}
  local shared = G.palette(member("sprites.NCLR"))

  local function parts(ncgr, ncer, nanr)
    return G.tiles(member(ncgr)), Cells.parse(member(ncer), G), nanr and Anim.parse(member(nanr), G)
  end
  local function cellOf(anim, bank, seq, frame)
    local frames = anim and Anim.frames(anim, seq)
    local f = frames and frames[(frame or 0) + 1]
    return f and bank and bank.cells[f.cell + 1]
  end
  local function seqCount(anim) return anim and anim.sequences and #anim.sequences or 0 end

  if shared then
    local s, bank, anim = parts("tabs.NCGR", "tabs_cell.NCER", "tabs_anim.NANR")
    for seq = 0, 15 do
      out[("tab_%02d"):format(seq)] = assembleCell(cellOf(anim, bank, seq), s,
        row(shared, Gen4SummaryArt.TAB_ROW[seq % 8]), bank)
    end
    s, bank, anim = parts("tab_arrow.NCGR", "tab_arrow_cell.NCER", "tab_arrow_anim.NANR")
    for seq = 0, 1 do out["tab_arrow_" .. seq] = assembleCell(cellOf(anim, bank, seq), s, row(shared, 1), bank) end
    s, bank, anim = parts("move_cursor.NCGR", "move_cursor_cell.NCER", "move_cursor_anim.NANR")
    for seq = 0, 1 do out["move_cursor_" .. seq] = assembleCell(cellOf(anim, bank, seq), s, row(shared, 2), bank) end
    local _, mbank, manim = parts("marking_circle.NCGR", "markings_cell.NCER", "markings_anim.NANR")
    for _, name in ipairs(Gen4SummaryArt.MARKINGS) do
      local ms = G.tiles(member("marking_" .. name .. ".NCGR"))
      for seq = 0, 1 do
        out[("marking_%s_%d"):format(name, seq)] = assembleCell(cellOf(manim, mbank, seq), ms, row(shared, 0), mbank)
      end
    end
    local ss = G.tiles(member("shiny_and_pokerus_cured_icon.NCGR"))
    out.shiny = assembleCell(cellOf(manim, mbank, 0), ss, row(shared, 2), mbank)
    out.pokerus_cured = assembleCell(cellOf(manim, mbank, 1), ss, row(shared, 2), mbank)
    local _, abank, aanim = parts("condition_arrow.NCGR", "condition_arrow_cell.NCER", "condition_arrow_anim.NANR")
    out.a_button = assembleCell(cellOf(aanim, abank, 0), G.tiles(member("a_button.NCGR")), row(shared, 0), abank)
    s, bank, anim = parts("sheen.NCGR", "sheen_cell.NCER", "sheen_anim.NANR")
    local frames = anim and Anim.frames(anim, 0) or {}
    for f = 0, #frames - 1 do out["sheen_" .. f] = assembleCell(cellOf(anim, bank, 0, f), s, row(shared, 2), bank) end
    s, bank, anim = parts("ribbon_cursor.NCGR", "ribbon_cursor_cell.NCER", "ribbon_cursor_anim.NANR")
    out.ribbon_cursor = assembleCell(cellOf(anim, bank, 0), s, row(shared, 2), bank)
    s, bank, anim = parts("ribbon_arrow.NCGR", "ribbon_arrow_cell.NCER", "ribbon_arrow_anim.NANR")
    for seq = 0, 1 do out["ribbon_arrow_" .. seq] = assembleCell(cellOf(anim, bank, seq), s, row(shared, 1), bank) end
    s, bank, anim = parts("pokerus_icon.NCGR", "pokerus_icon_cell.NCER", "pokerus_icon_anim.NANR")
    out.pokerus_icon = assembleCell(cellOf(anim, bank, 0), s, row(shared, 1), bank)
    s, bank, anim = parts("contest_stat_dot.NCGR", "contest_stat_dot_cell.NCER", "contest_stat_dot_anim.NANR")
    for seq = 0, math.min(4, seqCount(anim) - 1) do
      out["contest_dot_" .. seq] = assembleCell(cellOf(anim, bank, seq), s, row(shared, Gen4SummaryArt.DOT_ROW[seq]), bank)
    end
    s, bank, anim = parts("condition_flash.NCGR", "condition_flash_cell.NCER", "condition_flash_anim.NANR")
    frames = anim and Anim.frames(anim, 0) or {}
    for f = 0, #frames - 1 do out["condition_flash_" .. f] = assembleCell(cellOf(anim, bank, 0, f), s, row(shared, 2), bank) end
  end

  -- status icons: their own palette, row 0
  do
    local s, bank, anim = parts("status_icons.NCGR", "status_icons_cell.NCER", "status_icons_anim.NANR")
    local pal = G.palette(member("status_icons.NCLR"))
    for seq = 0, seqCount(anim) - 1 do
      out["status_" .. seq] = assembleCell(cellOf(anim, bank, seq), s, row(pal, 0), bank)
    end
  end

  -- the caught ball: condition_flash's cell over the ball's own tiles
  do
    local bank = Cells.parse(member("condition_flash_cell.NCER"), G)
    local anim = Anim.parse(member("condition_flash_anim.NANR"), G)
    local cell = cellOf(anim, bank, 0)
    for id, name in ipairs(Gen4SummaryArt.BALLS) do
      local pal = G.palette(member(("balls_%d.NCLR"):format(Gen4SummaryArt.BALL_PALETTE[id])))
      out[("ball_%02d"):format(id)] = assembleCell(cell, G.tiles(member(name .. "_ball.NCGR")), row(pal, 0), bank)
    end
  end

  -- type and category icons
  local batt = opener(rom, Gen4SummaryArt.BATTLE_PATH)
  if batt then
    local pal = G.palette(batt("type_icons/shared.NCLR"))
    local bank = Cells.parse(batt("type_icons/cell.NCER.lz") or batt("type_icons/cell.NCER"), G)
    local cell = bank and bank.cells[1]
    local function icon(name, r)
      local sheet = G.tiles(batt("type_icons/" .. name .. ".NCGR.lz") or batt("type_icons/" .. name .. ".NCGR"))
      return sheet and assembleCell(cell, sheet, row(pal, r), bank)
    end
    if pal and cell then
      for name, r in pairs(Gen4SummaryArt.TYPE_ROW) do out["type_" .. name] = icon(name, r) end
      for name, r in pairs(Gen4SummaryArt.CATEGORY_ROW) do out["category_" .. name] = icon(name, r) end
    end
  end

  -- the run-time background tiles, over tiles_main
  local sheet, mainPal = G.tiles(member("tiles_main.NCGR")), G.palette(member("tiles_main.NCLR"))
  if sheet and mainPal then
    local function strip(base, palette, count)
      local cells = {}
      for n = 0, count - 1 do cells[n + 1] = { tile = base + n, palette = palette } end
      return G.compose({ width = count * 8, height = 8, cells = cells }, sheet, mainPal)
    end
    for name, base in pairs(Gen4SummaryArt.HP_TILES) do out["hp_" .. name] = strip(base, Gen4SummaryArt.HP_PALETTE, 9) end
    local info = G.tilemap(member("page_info.NSCR"))
    local expCell = info and info.cells[23 * 32 + 23 + 1]
    out.exp_bar = strip(Gen4SummaryArt.EXP_TILE, expCell and expCell.palette or 0, 9)
    -- the heart's palette is whatever move_info already has at the heart row
    local mi = G.tilemap(member("move_info.NSCR"))
    local hy, hx = Gen4SummaryArt.HEART_ROW, Gen4SummaryArt.HEART_COL
    -- 512 x 512: four 32x32 blocks; (hx, hy) is in block 2 (bottom-left)
    local hc = mi and mi.cells[2 * 1024 + (hy - 32) * 32 + hx + 1]
    local hpal = hc and hc.palette or 0
    local function heart(base)
      return G.compose({ width = 16, height = 16, cells = {
        { tile = base, palette = hpal }, { tile = base + 1, palette = hpal },
        { tile = base + 32, palette = hpal }, { tile = base + 33, palette = hpal } } }, sheet, mainPal)
    end
    out.heart_filled = heart(Gen4SummaryArt.HEART_FILLED)
    out.heart_empty = heart(Gen4SummaryArt.HEART_EMPTY)
    -- "Lv" in black (1) over its shadow (2)
    local font = opener(rom, Gen4SummaryArt.FONT_PATH)
    local special = font and G.tiles(font(require("src.import.Gen4SpecialChars").MEMBER))
    if special then
      local ink = row(mainPal, 15)
      out.lv = G.compose({ width = 16, height = 8, cells = { { tile = 11, palette = 0 }, { tile = 12, palette = 0 } } },
        special, { { 0, 0, 0 }, ink[2], ink[3] })
    end
  end

  -- the bottom screen
  local subSheet, subPal = G.tiles(member("tiles_sub.NCGR")), G.palette(member("tiles_sub.NCLR"))
  local subMap = G.tilemap(member("tiles_sub.NSCR"))
  if subSheet and subPal and subMap then
    local back = G.compose(subMap, subSheet, subPal)
    out.sub_backdrop = back and back.height > 192 and require("src.import.Gen4ContestArt").crop(back, 0, 0, 256, 192) or back
  end
  local buttons = G.tiles(member("sub_buttons.NCGR"))
  if buttons and subPal then
    for page = 0, 7 do
      for a = 0, 2 do
        local base = (page % 2) * 15 + floor(page / 2) * 150 + a * 5 + 30
        local cells = {}
        for y = 0, 4 do
          for x = 0, 4 do
            cells[#cells + 1] = { tile = base + y * 30 + x, palette = Gen4SummaryArt.BUTTON_PALETTE[page] }
          end
        end
        out[("sub_button_%d_%d"):format(page, a)] = G.compose({ width = 40, height = 40, cells = cells }, buttons, subPal)
      end
    end
  end

  -- the tap circle (SUMMARY_SPRITE_BUTTON_TAP_CIRCLE): pst_h.cldat template
  -- 15 names pst_chr 16 / pst_cell 9 / pst_canm 9, all pl_bag_gra's
  -- button_shockwave, and pst_pal 4, pl_plist_gra member 23 -- the bag's
  -- shockwave in the party screen's blue
  local bagGra, plist = opener(rom, Gen4SummaryArt.TAP_PATH), opener(rom, Gen4SummaryArt.TAP_PALETTE_PATH)
  if bagGra and plist then
    local s = G.tiles(bagGra(Gen4SummaryArt.TAP_MEMBERS.char))
    local bank = Cells.parse(bagGra(Gen4SummaryArt.TAP_MEMBERS.cell), G)
    local anim = Anim.parse(bagGra(Gen4SummaryArt.TAP_MEMBERS.anim), G)
    local pal = G.palette(plist(Gen4SummaryArt.TAP_MEMBERS.palette))
    local frames = anim and Anim.frames(anim, 0) or {}
    for f = 0, #frames - 1 do
      out["tap_" .. f] = assembleCell(cellOf(anim, bank, 0, f), s, row(pal, 0), bank)
    end
  end

  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

-- tiles_main.NCLR row 15, as 0..255 triples
function Gen4SummaryArt.ink(pal)
  local function at(i) local c = pal and pal[15 * 16 + i + 1] return c and { c[1], c[2], c[3] } end
  return {
    black = at(1) or { 82, 82, 90 }, blackShadow = at(2) or { 173, 189, 189 },
    blue = at(3) or { 0, 115, 255 }, blueShadow = at(4) or { 123, 189, 238 },
    red = at(5) or { 238, 32, 16 }, redShadow = at(6) or { 255, 172, 189 },
    white = at(15) or { 255, 255, 255 }, whiteShadow = at(14) or { 82, 82, 90 },
  }
end

function Gen4SummaryArt.data(rom)
  local member = opener(rom, Gen4SummaryArt.PATH)
  local pal = member and require("src.import.Gen4Graphics").palette(member("tiles_main.NCLR"))
  if not pal then return {} end
  return Gen4SummaryArt.ink(pal)
end

return Gen4SummaryArt
