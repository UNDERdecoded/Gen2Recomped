-- PLATINUM'S BAG ART (src/applications/bag/{main,sprites,windows}.c), from
-- /graphic/pl_bag_gra.narc, the item icon archive and pl_font's special
-- characters -- the parts the generic screen composer (`gen4_graphics`, which
-- already carries `bag/bag_ui_main`, `bag/item_list_border` and the pocket
-- icon sheet) cannot give, because each of them needs a palette or a layout
-- that only the bag's own C code states.
--
-- SPRITES, each with the palette its ManagedSprite resolves to.  The bag's
-- OBJ palettes are loaded in order -- the bag's own NCLR (1 palette, slot 0),
-- ui_elements.NCLR (2, slots 1-2), the item icon (1, slot 3) ... -- and a
-- ManagedSprite's palette is its resource's slot plus the template's plttIdx,
-- REPLACING the cell's own OAM palette (SpriteSystem_NewSprite ->
-- Sprite_SetExplicitPalette).  `BagUI_SetHighlightSpritesPalette` later sets
-- 1 (choosing) or 2 (the action menu is up) absolutely:
--
--   bag_<male|female>_<p>    BAG_SPRITE_BAG, animation p (= the pocket type;
--                            8 + p is the wiggle), bag_sprite_<g>.NCLR row 0;
--                            anchored at (48, 50)
--   item_highlight_<r>       BAG_SPRITE_ITEM_HIGHLIGHT, ui_elements row r
--                            (0 red, 1 grey); anchored at (177, 24 + 16 * (pos - 1))
--   pocket_highlight_<r>     BAG_SPRITE_POCKET_HIGHLIGHT, ui_elements row r;
--                            anchored at (iconsX + spacing * i + 6, 97)
--   arrow_left / arrow_right pocket_selector_arrows animations 1 / 0,
--                            ui_elements row 0; anchored at (2, 96) / (98, 96)
--   item_return              the item icon CLOSE BAG shows (ITEM_RETURN_ID ->
--                            item_icon members 709 / 710)
--   moving_bar               BAG_SPRITE_MOVING_ITEM_POS_BAR, ui_elements row 0;
--                            anchored at (177, 16 + 16 * (pos - 1))
--   shockwave_<f>            BAG_SPRITE_PRESSED_BUTTON_SHOCKWAVE frame f (sub
--                            screen), button_shockwave.NCLR row 0; anchored on
--                            the pressed button's centre
--
-- Every sprite carries originX/originY: where its top-left sits relative to
-- the sprite's anchor, so `x + originX` is where it is drawn.
--
-- WINDOW BLITS (BG palette 3 of bag_ui_main.NCLR, colour 0 transparent):
--
--   entry_icons              item_entry_icons.NCGR as the 64x16 bitmap
--                            `DrawHMIcon` / `BagUI_DrawRegisteredIcon` blit
--                            from: x 0..39 the registered (SELECT) tag,
--                            x 40..63 the HM tag
--   special_chars            font_special_chars tiles 0..22 in a row, in the
--                            bag's FontSpecialChars_Init(1, 2, 0) colours --
--                            the digits (tiles 0..9) and "No." (tiles 13..14)
--                            the TM and Berry rows print with
--
-- THE BOTTOM SCREEN (sub engine; BG palette = pokeball_borders.NCLR with
-- buttons.NCLR's two palettes over slots 2 and 3):
--
--   sub_borders              pokeball_borders.NSCR, SUB_1
--   sub_dial                 pokeball_inside.NSCR, SUB_3 (affine, 256 colour),
--                            unrotated
--   pocket_button_<p>_<s>    `DrawPocketButton`: 5x5 tiles from
--                            (p / 2) * 150 + (p & 1) * 15 + 30 + s * 5,
--                            palette 2; s 0 idle, 1 / 2 pressed
--   dial_button_<s>          `DrawDialButton`: 6x6 tiles from 0x276 + 6 * s,
--                            palette 3, at tile (13, 7)
--
-- Written to assets/generated/gen4/bag_art/<key>.png and indexed in the cache
-- module `gen4_bag_art`.

local Gen4BagArt = {}

Gen4BagArt.PATH = "/graphic/pl_bag_gra.narc"
Gen4BagArt.ICON_PATH = "/itemtool/itemdata/item_icon.narc"
Gen4BagArt.FONT_PATH = "/graphic/pl_font.narc"

-- ITEM_RETURN_ID's icon and palette (Item_FileID: unused_709 / unused_710)
Gen4BagArt.RETURN_ICON, Gen4BagArt.RETURN_PALETTE = 709, 710
Gen4BagArt.POCKETS = 8

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

-- the sixteen colours of one row, as a palette starting at row 0
local function row(colours, r)
  local out = {}
  for i = 1, 16 do out[i] = colours[r * 16 + i] or { 0, 0, 0 } end
  return out
end
Gen4BagArt.row = row

-- one cell with every OAM entry on palette 0, assembled; origin = extent
local function assembleCell(cell, sheet, colours, bank)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  if not cell then return nil end
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
Gen4BagArt.assembleCell = assembleCell

-- the first frame's cell of animation `seq`
local function sequenceCell(anim, bank, seq)
  local Anim = require("src.import.Gen4CellAnim")
  local frames = anim and Anim.frames(anim, seq)
  local cell = frames and frames[1] and bank.cells[frames[1].cell + 1]
  return cell or bank.cells[seq + 1]
end
Gen4BagArt.sequenceCell = sequenceCell

-- a w x h block of tiles out of a sheet laid `stride` tiles wide, from `first`
local function block(G, sheet, colours, first, stride, w, h, palette)
  local cells = {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      cells[#cells + 1] = { tile = first + y * stride + x, palette = palette or 0 }
    end
  end
  return G.compose({ width = w * 8, height = h * 8, cells = cells }, sheet, colours)
end

function Gen4BagArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local member = opener(rom, Gen4BagArt.PATH)
  if not member then return nil, "pl_bag_gra missing" end
  local out = {}

  local function sprites(ncgr, ncer, nanr)
    local s = G.tiles(member(ncgr))
    local bank = Cells.parse(member(ncer), G)
    local anim = nanr and Anim.parse(member(nanr), G)
    return s, bank, anim
  end

  -- the bag itself, one picture per pocket and gender
  for _, gender in ipairs({ "male", "female" }) do
    local s = G.tiles(member("bag_sprite_" .. gender .. ".NCGR"))
    local pal = G.palette(member("bag_sprite_" .. gender .. ".NCLR"))
    local bank = Cells.parse(member("bag_sprite_cell.NCER"), G)
    local anim = Anim.parse(member("bag_sprite_anim.NANR"), G)
    if s and pal and bank then
      for p = 0, Gen4BagArt.POCKETS - 1 do
        out[("bag_%s_%d"):format(gender, p)] = assembleCell(sequenceCell(anim, bank, p), s, row(pal, 0), bank)
      end
    end
  end

  -- the highlights and the pocket arrows, over ui_elements
  local ui = G.palette(member("ui_elements.NCLR"))
  if ui then
    local s, bank, anim = sprites("item_highlight.NCGR", "item_highlight_cell.NCER", "item_highlight_anim.NANR")
    if s and bank then
      for r = 0, 1 do out["item_highlight_" .. r] = assembleCell(sequenceCell(anim, bank, 0), s, row(ui, r), bank) end
    end
    s, bank, anim = sprites("pocket_highlight.NCGR", "pocket_highlight_cell.NCER", "pocket_highlight_anim.NANR")
    if s and bank then
      for r = 0, 1 do out["pocket_highlight_" .. r] = assembleCell(sequenceCell(anim, bank, 0), s, row(ui, r), bank) end
    end
    s, bank, anim = sprites("pocket_selector_arrows.NCGR", "pocket_selector_arrows_cell.NCER", "pocket_selector_arrows_anim.NANR")
    if s and bank then
      out.arrow_right = assembleCell(sequenceCell(anim, bank, 0), s, row(ui, 0), bank)
      out.arrow_left = assembleCell(sequenceCell(anim, bank, 1), s, row(ui, 0), bank)
    end
    -- BAG_SPRITE_MOVING_ITEM_POS_BAR: plttIdx 0 over ui_elements' slot
    s, bank, anim = sprites("moving_item_pos_bar.NCGR", "moving_item_pos_bar_cell.NCER", "moving_item_pos_bar_anim.NANR")
    if s and bank then
      out.moving_bar = assembleCell(sequenceCell(anim, bank, 0), s, row(ui, 0), bank)
    end
  end

  -- BAG_SPRITE_PRESSED_BUTTON_SHOCKWAVE (sub screen): button_shockwave in its
  -- own NCLR, one picture per animation frame (3 + 2 frames, hidden on the
  -- third by BagUI_TickBtnShockwaveAnim)
  do
    local s, bank, anim = sprites("button_shockwave.NCGR", "button_shockwave_cell.NCER", "button_shockwave_anim.NANR")
    local pal = G.palette(member("button_shockwave.NCLR"))
    local frames = anim and Anim.frames(anim, 0) or {}
    if s and bank and pal then
      for f = 0, #frames - 1 do
        local cell = bank.cells[frames[f + 1].cell + 1]
        out["shockwave_" .. f] = assembleCell(cell, s, row(pal, 0), bank)
      end
    end
  end

  -- the window blits, in bag_ui_main's BG palette 3
  local mainPal = G.palette(member("bag_ui_main.NCLR"))
  local entry = G.tiles(member("item_entry_icons.NCGR"))
  if mainPal and entry then
    out.entry_icons = block(G, entry, mainPal, 0, 8, 8, 2, 3)
  end
  local font = opener(rom, Gen4BagArt.FONT_PATH)
  local special = font and G.tiles(font(require("src.import.Gen4SpecialChars").MEMBER))
  if mainPal and special then
    local ink = row(mainPal, 3)
    local cells = {}
    for t = 0, 22 do cells[t + 1] = { tile = t, palette = 0 } end
    out.special_chars = G.compose({ width = 23 * 8, height = 8, cells = cells }, special,
      { { 0, 0, 0 }, ink[2], ink[3] })
  end

  -- CLOSE BAG's icon
  local icons = opener(rom, Gen4BagArt.ICON_PATH)
  if icons then
    local s = G.tiles(icons(Gen4BagArt.RETURN_ICON))
    local pal = G.palette(icons(Gen4BagArt.RETURN_PALETTE))
    local bank = Cells.parse(icons(1), G)
    if s and pal then
      local cell = bank and bank.cells and bank.cells[1]
      out.item_return = (cell and assembleCell(cell, s, row(pal, 0), bank))
        or block(G, s, row(pal, 0), 0, 4, 4, 4, 0)
    end
  end

  -- the bottom screen
  local subPal = G.palette(member("pokeball_borders.NCLR"))
  local buttonPal = G.palette(member("buttons.NCLR"))
  if subPal then
    local pal = {}
    for i, c in pairs(subPal) do pal[i] = c end
    if buttonPal then
      for i = 1, 32 do if buttonPal[i] then pal[32 + i] = buttonPal[i] end end
    end
    for i = 1, 256 do pal[i] = pal[i] or { 0, 0, 0 } end
    local borderSheet = G.tiles(member("pokeball_borders_tileset.NCGR"))
    local borderMap = G.tilemap(member("pokeball_borders.NSCR"))
    if borderSheet and borderMap then out.sub_borders = G.compose(borderMap, borderSheet, pal) end
    local insideSheet = G.tiles(member("pokeball_inside.NCGR"))
    local insideMap = G.tilemap(member("pokeball_inside.NSCR"))
    if insideSheet and insideMap then out.sub_dial = G.compose(insideMap, insideSheet, pal) end
    local buttons = G.tiles(member("buttons.NCGR"))
    if buttons then
      for p = 0, Gen4BagArt.POCKETS - 1 do
        for s = 0, 2 do
          local first = floor(p / 2) * 150 + (p % 2) * 15 + 30 + s * 5
          out[("pocket_button_%d_%d"):format(p, s)] = block(G, buttons, pal, first, 30, 5, 5, 2)
        end
      end
      for s = 0, 2 do
        out["dial_button_" .. s] = block(G, buttons, pal, 0x276 + 6 * s, 30, 6, 6, 3)
      end
    end
  end

  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

return Gen4BagArt
