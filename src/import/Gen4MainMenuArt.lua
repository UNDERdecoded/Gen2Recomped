-- PLATINUM'S MAIN MENU WINDOWS (src/main_menu/main_menu.c), from
-- /graphic/pl_winframe.narc and /graphic/mystery.narc.
--
-- THE TWO FRAMES ARE TWO DIFFERENT WINDOWS, NOT ONE WITH A CURSOR.
-- LoadMainMenuGraphics loads
--
--     LoadStandardWindowGraphics(BG0, UNFOCUSED_..., palette 2, STANDARD_WINDOW_SYSTEM)
--     LoadStandardWindowGraphics(BG0, FOCUSED_...,   palette 3, STANDARD_WINDOW_FIELD)
--     *HW_BG_A_PLTT_COLOR(2, 1) = UNFOCUSED_OPTION_BG_COLOR   -- GX_RGB(26, 26, 26)
--     *HW_BG_A_PLTT_COLOR(1, 15) = UNFOCUSED_OPTION_BG_COLOR
--
-- and RenderOptionsFrames draws the focused option in the FIELD frame over
-- palette 0 (the text palette, white paper) and every other option in the
-- SYSTEM frame over palette 1 (the same text palette with its paper turned
-- grey).  There is no cursor glyph anywhere on this screen.
--
--   frame_unfocused     standard_system's nine tiles, 24 x 24, in
--                       standard_system.NCLR with colour 1 made grey
--   frame_focused       standard_field's nine tiles in standard_system.NCLR
--                       with colour 6 left OUT -- DoColorCycleStep rewrites
--                       BG palette (3, 6) every frame...
--   frame_focused_glow  ...so colour 6's pixels are their own white mask, for
--                       the screen to tint with the cycle colour
--   scroll_up / scroll_down   main_menu_scroll_arrows sequences 0 and 1
--                       (LoadScrollArrowsSprites; SpriteList_AddAffine, so the
--                       cell's own OAM palette rows)
--
-- `data(rom)` (gen4_main_menu_ink) carries the colours: the font palette's
-- ink pairs, the two papers, the backdrop and the border cycle.
--
-- Written to assets/generated/gen4/main_menu/<key>.png, indexed in
-- `gen4_main_menu_art`.

local Gen4MainMenuArt = {}

Gen4MainMenuArt.WINFRAME = "/graphic/pl_winframe.narc"
Gen4MainMenuArt.MYSTERY = "/graphic/mystery.narc"
Gen4MainMenuArt.FONT = "/graphic/pl_font.narc"
Gen4MainMenuArt.FONT_PALETTE = 6          -- pl_font.narc font.NCLR

-- BACKGROUND_COLOR, UNFOCUSED_OPTION_BG_COLOR and sFocusedOptionBorderColors,
-- GX_RGB components (0..31).
Gen4MainMenuArt.BACKGROUND = { 12, 12, 31 }
Gen4MainMenuArt.UNFOCUSED = { 26, 26, 26 }
Gen4MainMenuArt.BORDER_CYCLE = {}
do
  local up = { 3, 5, 7, 9, 11, 13, 15, 17, 19, 21, 23, 25, 27, 29, 31,
               29, 27, 25, 23, 21, 19, 17, 15, 13, 11, 9, 7, 5 }
  for i, r in ipairs(up) do Gen4MainMenuArt.BORDER_CYCLE[i] = { r, 28, 20 } end
end

local function opener(rom, path)
  local G = require("src.import.Gen4Graphics")
  local A = require("src.import.Gen4Archives")
  local bytes = rom:read(path)
  if not bytes then return nil end
  local narc = require("src.import.NarcArchive").parse(bytes)
  return function(name)
    local i = type(name) == "number" and name or A.find(path, name)
    local b = i and narc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
end

local function five(c) return { math.floor(c[1] * 255 / 31 + 0.5), math.floor(c[2] * 255 / 31 + 0.5), math.floor(c[3] * 255 / 31 + 0.5) } end

function Gen4MainMenuArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local win = opener(rom, Gen4MainMenuArt.WINFRAME)
  if not win then return nil, "pl_winframe missing" end
  local system, field = G.tiles(win("standard_system.NCGR")), G.tiles(win("standard_field.NCGR"))
  local pal = G.palette(win("standard_system.NCLR"))
  if not (system and field and pal) then return nil, "pl_winframe frames unreadable" end
  local base = {}
  for i = 1, 16 do base[i] = pal[i] or { 0, 0, 0 } end
  local function nine(sheet, colours)
    local cells = {}
    for t = 0, 8 do cells[t + 1] = (t == 4) and { tile = 99, palette = 0 } or { tile = t, palette = 0 } end
    return G.compose({ width = 24, height = 24, cells = cells }, sheet, colours)
  end
  local out = {}
  local grey = {}
  for i = 1, 16 do grey[i] = base[i] end
  grey[2] = five(Gen4MainMenuArt.UNFOCUSED)
  out.frame_unfocused = nine(system, grey)
  -- colour 6 out of the frame, and on its own as a white mask (compose leaves
  -- a pixel clear when its palette has no entry for the index)
  local without = {}
  for i = 1, 16 do without[i] = base[i] end
  without[7] = nil
  out.frame_focused = nine(field, without)
  out.frame_focused_glow = nine(field, { [7] = { 255, 255, 255 } })

  local mys = opener(rom, Gen4MainMenuArt.MYSTERY)
  if mys then
    local s = G.tiles(mys("main_menu_scroll_arrows.NCGR.lz"))
    local bank = Cells.parse(mys("main_menu_scroll_arrows_cell.NCER.lz"), G)
    local anim = Anim.parse(mys("main_menu_scroll_arrows_anim.NANR.lz"), G)
    local colours = G.palette(mys("main_menu_scroll_arrows.NCLR"))
    if s and bank and anim and colours then
      for seq, key in pairs({ [0] = "scroll_up", [1] = "scroll_down" }) do
        local frames = Anim.frames(anim, seq)
        local cell = frames and frames[1] and bank.cells[frames[1].cell + 1]
        local pic = cell and Cells.assemble(cell, s, colours, bank, G)
        if pic then pic.originX, pic.originY = Cells.extent(cell); out[key] = pic end
      end
    end
  end
  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

-- The colours, as 0..255 triples.
function Gen4MainMenuArt.data(rom)
  local G = require("src.import.Gen4Graphics")
  local font = opener(rom, Gen4MainMenuArt.FONT)
  local pal = font and G.palette(font(Gen4MainMenuArt.FONT_PALETTE))
  local function at(i, fallback)
    local c = pal and pal[i + 1]
    return c and { c[1], c[2], c[3] } or fallback
  end
  local cycle = {}
  for i, c in ipairs(Gen4MainMenuArt.BORDER_CYCLE) do cycle[i] = five(c) end
  return {
    -- MainMenuUtil_InitWindow: TEXT_COLOR(1, 2, 15)
    text = { at(1, { 90, 90, 82 }), at(2, { 173, 189, 189 }) },
    -- RenderContinueOption: TEXT_COLOR(7, 8, 15) for a boy, (3, 4, 15) a girl
    male = { at(7, { 0, 115, 255 }), at(8, { 123, 189, 239 }) },
    female = { at(3, { 239, 33, 16 }), at(4, { 255, 173, 189 }) },
    paper = at(15, { 255, 255, 255 }),
    paperUnfocused = five(Gen4MainMenuArt.UNFOCUSED),
    background = five(Gen4MainMenuArt.BACKGROUND),
    borderCycle = cycle,
  }
end

return Gen4MainMenuArt
