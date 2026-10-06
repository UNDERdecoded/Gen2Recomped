-- PLATINUM'S TRAINER CASE ART (src/applications/trainer_case/{main,sprites}.c),
-- from /graphic/trainer_case.narc, composed IN THE PALETTES THE CARTRIDGE
-- ACTUALLY ENDS UP WITH -- which is the one thing the generic screen composer
-- (`gen4_graphics`' `trainer_card/*`) gets wrong, and gets wrong everywhere.
--
-- THE CASE IS PLATINUM-GOLD, NOT DIAMOND-BLUE.  `TrainerCase_DrawTrainerCard`
-- loads the palettes in four steps, and the last one is the visible one:
--
--   1. trainer_card_normal.NCLR over the whole sub (top screen) BG palette,
--      256 colours -- the 8bpp card, the trainer and the backdrop all use it;
--   2. `TrainerCase_LoadCardPalette`: rows 1-3 and 15 from the card-level
--      NCLR (normal / cobalt / bronze / silver / gold / black, or normal_no_dex
--      before the Pokedex) -- that is what paints the star rating;
--   3. badge_case_lid_tiles.NCLR over the whole main (touch screen) BG palette;
--   4. `TrainerCase_LoadCasePalette(gameVersion)`: the version's case NCLR,
--      SIXTEEN colours, over row 0 of BOTH -- case_platinum on a Platinum
--      cartridge.
--
-- Row 0 of trainer_card_normal is byte-for-byte case_diamond's: light blue.
-- Composing against the file instead of against step 4 is how the port's case
-- came out as Diamond's blue frame around Platinum's card.  case_platinum's
-- row 0 is cream and gold (255 255 230, 238 230 156, 230 213 148 ...).
--
-- PICTURES (all at the screen's own (0, 0)):
--
--   case_top                 case_top_screen.NSCR, SUB_1 (priority 3) -- the
--                            case around the card
--   front_<level>            trainer_card_front.NSCR, SUB_2 (affine, 8bpp)
--   back_<level>             trainer_card_back.NSCR
--                            level: normal cobalt bronze silver gold black no_dex
--   lucas / dawn             the trainer, SUB_3 over player_tiles
--   badge_case               badge_case.NSCR, MAIN_2 -- the open case
--   badge_case_lid           badge_case_lid.NSCR, MAIN_3 (priority 0) -- the
--                            lid, which is what the touch screen shows until
--                            the button opens it
--
-- SPRITES (SpriteList_AddAffine: the cell's own OAM palette is ADDED to the
-- resource's base, so the cells' palettes are honoured):
--
--   badge_<i>_<dirt>         badge i (0 Coal .. 7 Beacon), animation i, with
--                            `TrainerCase_DrawBadgeDirt`'s palette row `dirt`
--                            of <name>_badge.NCLR over that badge's slot.  The
--                            screen picks dirt = 3 - polish level for levels
--                            0..3 (filthy 3, dirty 2, normal 1, two sparkles
--                            0) and 0 for four sparkles; anchored at
--                            sBadgeCoordinates[i]
--   badge_<i>                = badge_<i>_0, kept for older readers
--   two_sparkles_<f>         BADGE_CASE_ANIM_TWO_SPARKLES (8): cells 8..11,
--                            eight frames each, looping; at sSparkleCoordinates
--   four_sparkles_<f>        BADGE_CASE_ANIM_FOUR_SPARKLES (9): cells 12..15,
--                            four frames each, looping (origin x -8)
--   button_effect_<f>        BADGE_CASE_ANIM_BUTTON_PRESS_EFFECT (10): cells
--                            16..18, two frames each, once (cell 19 is empty);
--                            at (96, 136), OBJ priority 0 -- over the lid
--
-- AND ONE PIECE OF MAIN_2 REDRAWN:
--
--   case_button_<idx>        the open/close button, 32x32, idx 0 not pressed,
--                            1 half, 2 fully (`TrainerCase_RedrawBadgeCaseButton`);
--                            originX/originY = its screen position (112, 152)
--
-- Written to assets/generated/gen4/trainer_card_art/<key>.png, indexed in the
-- cache module `gen4_trainer_card_art`.

local Gen4TrainerCardArt = {}

Gen4TrainerCardArt.PATH = "/graphic/trainer_case.narc"

-- the level faces, in TRAINER_CARD_LEVEL order, then the no-dex face
Gen4TrainerCardArt.LEVELS = { "normal", "cobalt", "bronze", "silver", "gold", "black" }
Gen4TrainerCardArt.NO_DEX = "no_dex"

-- which case palette a version gets; the port only ever runs Platinum
Gen4TrainerCardArt.CASE = "case_platinum"

Gen4TrainerCardArt.BADGES = { "coal", "forest", "cobble", "fen", "relic", "mine", "icicle", "beacon" }

-- sBadgeCoordinates (sprites.c)
Gen4TrainerCardArt.BADGE_AT = {
  { 24, 40 }, { 80, 40 }, { 136, 40 }, { 192, 40 },
  { 24, 72 }, { 80, 72 }, { 136, 72 }, { 192, 72 },
}

-- the button's 4x4 tiles sit at tile (14, 19) of MAIN_2
Gen4TrainerCardArt.BUTTON_AT = { 14 * 8, 19 * 8 }

-- the animated sprites, { key prefix, NANR sequence }: BADGE_CASE_ANIM_TWO_
-- SPARKLES (8), _FOUR_SPARKLES (9), _BUTTON_PRESS_EFFECT (10).  The press
-- effect's fourth cell (19) is empty -- the one-shot ends on nothing -- so
-- it has three pictures.
Gen4TrainerCardArt.SPRITE_ANIMS = {
  { "two_sparkles", 8 }, { "four_sparkles", 9 }, { "button_effect", 10 },
}

-- a picture with every transparent pixel filled with `colour`
function Gen4TrainerCardArt.opaque(pic, colour)
  colour = colour or { 0, 0, 0 }
  -- `Gen4Graphics.palette` colours are 0..255
  local function b(v) return string.char(math.max(0, math.min(255, math.floor((v or 0) + 0.5)))) end
  local fill = b(colour[1]) .. b(colour[2]) .. b(colour[3]) .. "\255"
  local parts = {}
  for i = 1, #pic.rgba, 4 do
    local px = pic.rgba:sub(i, i + 3)
    parts[#parts + 1] = (px:byte(4) == 0) and fill or px
  end
  pic.rgba = table.concat(parts)
  return pic
end

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

local function copy(colours)
  local out = {}
  for i = 1, 256 do out[i] = colours and colours[i] or { 0, 0, 0 } end
  return out
end

local function putRows(into, from, first, count)
  for i = first * 16 + 1, (first + count) * 16 do
    if from[i] then into[i] = from[i] end
  end
end

-- the sub (top screen) BG palette for one face: normal, the level's rows 1-3
-- and 15, and the case's sixteen over row 0
function Gen4TrainerCardArt.subPalette(normal, level, case)
  local pal = copy(normal)
  if level then
    putRows(pal, level, 1, 3)
    putRows(pal, level, 15, 1)
  end
  if case then putRows(pal, case, 0, 1) end
  return pal
end

-- the main (touch screen) BG palette: the lid's, with the case over row 0
function Gen4TrainerCardArt.mainPalette(lid, case)
  local pal = copy(lid)
  if case then putRows(pal, case, 0, 1) end
  return pal
end

function Gen4TrainerCardArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local member = opener(rom, Gen4TrainerCardArt.PATH)
  if not member then return nil, "trainer_case missing" end
  local out = {}

  local normal = G.palette(member("trainer_card_normal.NCLR"))
  local case = G.palette(member(Gen4TrainerCardArt.CASE .. ".NCLR"))
  if not (normal and case) then return nil, "trainer_case palettes unreadable" end

  local cardSheet = G.tiles(member("trainer_card_tiles.NCGR"))
  local front = G.tilemap(member("trainer_card_front.NSCR"))
  local back = G.tilemap(member("trainer_card_back.NSCR"))
  local faces = {}
  for _, name in ipairs(Gen4TrainerCardArt.LEVELS) do faces[#faces + 1] = { name, "trainer_card_" .. name } end
  faces[#faces + 1] = { Gen4TrainerCardArt.NO_DEX, "trainer_card_normal_no_dex" }
  for _, f in ipairs(faces) do
    local level = G.palette(member(f[2] .. ".NCLR"))
    local pal = Gen4TrainerCardArt.subPalette(normal, level, case)
    if cardSheet and front then out["front_" .. f[1]] = G.compose(front, cardSheet, pal) end
    if cardSheet and back then out["back_" .. f[1]] = G.compose(back, cardSheet, pal) end
  end

  -- the case around the card, and the trainer: rows 0 and 4-5 only, which
  -- no level changes, so one compose each
  local sub = Gen4TrainerCardArt.subPalette(normal, nil, case)
  local caseSheet, caseMap = G.tiles(member("case_top_screen_tiles.NCGR")), G.tilemap(member("case_top_screen.NSCR"))
  if caseSheet and caseMap then out.case_top = G.compose(caseMap, caseSheet, sub) end
  local player = G.tiles(member("player_tiles.NCGR"))
  for _, who in ipairs({ "lucas", "dawn" }) do
    local map = G.tilemap(member(who .. ".NSCR"))
    if player and map then out[who] = G.compose(map, player, sub) end
  end

  -- the touch screen
  local lid = G.palette(member("badge_case_lid_tiles.NCLR"))
  if lid then
    local main = Gen4TrainerCardArt.mainPalette(lid, case)
    local s, m = G.tiles(member("badge_case_tiles.NCGR")), G.tilemap(member("badge_case.NSCR"))
    if s and m then out.badge_case = G.compose(m, s, main) end
    s, m = G.tiles(member("badge_case_lid_tiles.NCGR")), G.tilemap(member("badge_case_lid.NSCR"))
    if s and m then out.badge_case_lid = G.compose(m, s, main) end

    -- the button, `TrainerCase_RedrawBadgeCaseButton`: four by four tiles
    -- of the case's own sheet from tile 4*32 + 4*idx, at tile (14, 19) of
    -- MAIN_2, sub-palette 0.  MAIN_2 is the bottom layer, so a pixel of
    -- colour 0 shows the backdrop -- which is that same colour 0.
    s = G.tiles(member("badge_case_tiles.NCGR"))
    if s then
      for idx = 0, 2 do
        local cells = {}
        for y = 0, 3 do
          for x = 0, 3 do
            cells[y * 4 + x + 1] = { tile = 4 * 32 + 4 * idx + y * 32 + x, palette = 0 }
          end
        end
        local pic = G.compose({ width = 32, height = 32, cells = cells }, s, main)
        if pic then
          pic = Gen4TrainerCardArt.opaque(pic, main[1])
          pic.originX, pic.originY = Gen4TrainerCardArt.BUTTON_AT[1], Gen4TrainerCardArt.BUTTON_AT[2]
          out["case_button_" .. idx] = pic
        end
      end
    end
  end

  -- the sprites: badges, sparkles, the button's press effect
  local bs = G.tiles(member("badge_case_sprites.NCGR"))
  local bpal = G.palette(member("badge_case_sprites.NCLR"))
  local bank = Cells.parse(member("badge_case_sprites_cell.NCER"), G)
  local anim = Anim.parse(member("badge_case_sprites_anim.NANR"), G)
  if bs and bpal and bank then
    local function basePalette()
      local pal = {}
      for k = 1, 256 do pal[k] = bpal[k] or { 0, 0, 0 } end
      return pal
    end
    local function put(key, cell, pal)
      local pic = cell and Cells.assemble(cell, bs, pal, bank, G)
      if pic then
        pic.originX, pic.originY = Cells.extent(cell)
        out[key] = pic
      end
    end
    for i, name in ipairs(Gen4TrainerCardArt.BADGES) do
      local frames = anim and Anim.frames(anim, i - 1)
      local cell = frames and frames[1] and bank.cells[frames[1].cell + 1] or bank.cells[i]
      if cell then
        -- `TrainerCase_DrawBadgeDirt` writes the badge's own palette (row
        -- `dirt`: 0 clean, 1..3 dirtier) over slot base + badgeID
        local own = G.palette(member(name .. "_badge.NCLR"))
        local slot = cell.oam[1] and cell.oam[1].palette or (i - 1)
        for dirt = 0, 3 do
          local pal = basePalette()
          if own then
            for k = 1, 16 do
              local c = own[dirt * 16 + k]
              if c then pal[slot * 16 + k] = c end
            end
          end
          put(("badge_%d_%d"):format(i - 1, dirt), cell, pal)
        end
        out["badge_" .. (i - 1)] = out[("badge_%d_0"):format(i - 1)]
      end
    end
    -- the animated sprites, one picture per frame of their sequences
    for _, seq in ipairs(Gen4TrainerCardArt.SPRITE_ANIMS) do
      local frames = anim and Anim.frames(anim, seq[2]) or {}
      for f, fr in ipairs(frames) do
        local cell = bank.cells[fr.cell + 1]
        if cell and #cell.oam > 0 then put(("%s_%d"):format(seq[1], f - 1), cell, basePalette()) end
      end
    end
  end

  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

return Gen4TrainerCardArt
