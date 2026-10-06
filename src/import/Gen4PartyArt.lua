-- PLATINUM'S PARTY SCREEN ART (src/applications/party_menu/{main,windows,
-- sprites}.c), from /graphic/pl_plist_gra.narc, pl_pst_gra.narc's status
-- icons and pl_font.narc's special characters.
--
-- BACKGROUND (BG2, the part the port never drew): menu_panels.NSCR is a
-- 32-wide map holding three 16 x 6-tile templates -- rows 0-5 the LEAD panel,
-- rows 6-11 a BACK panel, rows 12-17 an empty slot.  The cartridge copies one
-- per slot and forces every cell's palette to 3 + v, where v is the state:
--
--   0 normal, 2 fainted, 4 cursor on it, 6 cursor + fainted, 7 switching
--
-- so each is one 128 x 48 picture over menu_tiles in menu.NCLR (colour 0
-- transparent, BG3 `party/menu` shows through):
--
--   panel_lead_<v> / panel_back_<v>          v in 0, 2, 4, 6, 7
--   panel_lead_egg_<v> / panel_back_egg_<v>  the same with tile 0x17 written
--                                            over cols 6..14 of row 3 (an egg
--                                            has no HP bar frame)
--   panel_none                               the empty template, palette 1
--
-- SPRITES, each with the explicit palette its template gives it (the cell's
-- own OAM palette is replaced, as SpriteSystem_NewSprite does):
--
--   ball_<c>          member_ball cell c (0 idle, 1 cursor), shared.NCLR row 0
--   cursor_<s>_<r>    cursor sequence s (0 back, 1 lead, 2/3 the switch
--                     source markers), shared.NCLR row r (0 orange, 1 grey
--                     while the submenu is open)
--   button_<s>        the CANCEL button sequences 0..3, shared.NCLR row 0
--   held_item / held_mail / held_seal   icons cells 0 / 1 / 2, icons.NCLR
--   status_<n>        pl_pst_gra status_icons sequence n (0 PKRS, 1 PAR,
--                     2 FRZ, 3 SLP, 4 PSN, 5 BRN, 6 FNT), status_icons.NCLR
--
-- TEXT THAT IS NOT TEXT: `digits` is font_special_chars tiles 0..12 in a row
-- (0-9, "/", the two-tile "Lv") in the party screen's colours, role 1 white
-- and role 2 the dark grey, 0 transparent.
--
-- BOTTOM SCREEN: the touch buttons `touch_ball_<n>` (touch_button.NCGR rows
-- 8 / 48 / 88, 40 x 40).  The backdrop is NOT here: gen4_graphics' screens
-- already carry `party/subscreen` at assets/generated/gen4/party/subscreen.png,
-- the same directory, so a key of that name here would overwrite its file.
--
-- Written to assets/generated/gen4/party/<key>.png and indexed in the cache
-- module `gen4_party_art`; `data(rom)` is the menu palette's colours the
-- screen draws with (`gen4_party_ink`).

local Gen4PartyArt = {}

Gen4PartyArt.PATH = "/graphic/pl_plist_gra.narc"
Gen4PartyArt.STATUS_PATH = "/graphic/pl_pst_gra.narc"
Gen4PartyArt.FONT_PATH = "/graphic/pl_font.narc"

Gen4PartyArt.VARIANTS = { 0, 2, 4, 6, 7 }
Gen4PartyArt.EGG_TILE = 0x17

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

function Gen4PartyArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local member = opener(rom, Gen4PartyArt.PATH)
  if not member then return nil, "pl_plist_gra missing" end
  local out = {}

  -- the panels
  local sheet, menuPal, panels = G.tiles(member("menu_tiles.NCGR")), G.palette(member("menu.NCLR")),
    G.tilemap(member("menu_panels.NSCR"))
  if not (sheet and menuPal and panels) then return nil, "pl_plist_gra panels unreadable" end
  local cols = floor((panels.width or 256) / 8)
  local function template(top, palette, egg)
    local cells = {}
    for r = 0, 5 do
      for c = 0, 15 do
        local src = panels.cells[(top + r) * cols + c + 1] or { tile = 0 }
        local cell = { tile = src.tile, flipX = src.flipX, flipY = src.flipY, palette = palette }
        if egg and r == 3 and c >= 6 and c <= 14 then
          cell = { tile = Gen4PartyArt.EGG_TILE, palette = palette }
        end
        cells[#cells + 1] = cell
      end
    end
    return G.compose({ width = 128, height = 48, cells = cells }, sheet, menuPal)
  end
  for _, v in ipairs(Gen4PartyArt.VARIANTS) do
    out["panel_lead_" .. v] = template(0, 3 + v)
    out["panel_back_" .. v] = template(6, 3 + v)
    out["panel_lead_egg_" .. v] = template(0, 3 + v, true)
    out["panel_back_egg_" .. v] = template(6, 3 + v, true)
  end
  out.panel_none = template(12, 1)

  -- sprites over shared.NCLR / icons.NCLR
  local shared = G.palette(member("shared.NCLR"))
  local function sprites(ncgr, ncer, nanr)
    local s = G.tiles(member(ncgr))
    local bank = Cells.parse(member(ncer), G)
    local anim = nanr and Anim.parse(member(nanr), G)
    return s, bank, anim
  end
  local function bySequence(anim, bank, seq)
    local frames = anim and Anim.frames(anim, seq)
    return frames and frames[1] and bank.cells[frames[1].cell + 1]
  end
  if shared then
    local s, bank = sprites("member_ball.NCGR", "member_ball_cell.NCER")
    if s and bank then
      for c = 0, 1 do out["ball_" .. c] = assembleCell(bank.cells[c + 1], s, row(shared, 0), bank) end
    end
    local cs, cbank, canim = sprites("cursor.NCGR", "cursor_cell.NCER", "cursor_anim.NANR")
    if cs and cbank then
      for seq = 0, 3 do
        local cell = bySequence(canim, cbank, seq) or cbank.cells[seq + 1]
        for r = 0, 1 do out[("cursor_%d_%d"):format(seq, r)] = assembleCell(cell, cs, row(shared, r), cbank) end
      end
    end
    local bs, bbank, banim = sprites("button.NCGR", "button_cell.NCER", "button_anim.NANR")
    if bs and bbank then
      for seq = 0, 3 do
        out["button_" .. seq] = assembleCell(bySequence(banim, bbank, seq) or bbank.cells[seq + 1], bs, row(shared, 0), bbank)
      end
    end
  end
  local iconPal = G.palette(member("icons.NCLR"))
  if iconPal then
    local s, bank = sprites("icons.NCGR", "icons_cell.NCER")
    if s and bank then
      local names = { [0] = "held_item", "held_mail", "held_seal" }
      for c = 0, 2 do out[names[c]] = assembleCell(bank.cells[c + 1], s, row(iconPal, 0), bank) end
    end
  end

  -- the status icons, pl_pst_gra
  local pst = opener(rom, Gen4PartyArt.STATUS_PATH)
  if pst then
    local s = G.tiles(pst("status_icons.NCGR"))
    local bank = Cells.parse(pst("status_icons_cell.NCER"), G)
    local anim = Anim.parse(pst("status_icons_anim.NANR"), G)
    local pal = G.palette(pst("status_icons.NCLR"))
    if s and bank and anim and pal then
      for seq = 0, 6 do
        out["status_" .. seq] = assembleCell(bySequence(anim, bank, seq), s, row(pal, 0), bank)
      end
    end
  end

  -- the digits, "/" and "Lv": font_special_chars in white over dark grey
  local font = opener(rom, Gen4PartyArt.FONT_PATH)
  local special = font and G.tiles(font(require("src.import.Gen4SpecialChars").MEMBER))
  if special then
    local ink = Gen4PartyArt.ink(menuPal)
    local cells = {}
    for t = 0, 12 do cells[t + 1] = { tile = t, palette = 0 } end
    out.digits = G.compose({ width = 13 * 8, height = 8, cells = cells }, special,
      { { 0, 0, 0 }, ink.text, ink.shadow })
  end

  -- the bottom screen's touch buttons (the backdrop is gen4_graphics'
  -- `party/subscreen`, which already composes tiles 12 / map 14 / pal 13)
  local touchSheet, touchPal = G.tiles(member("touch_button.NCGR")), G.palette(member("touch_button.NCLR"))
  if touchSheet and touchPal then
    local cells = {}
    for t = 0, 5 * 16 - 1 do cells[t + 1] = { tile = t, palette = 0 } end
    local full = G.compose({ width = 40, height = 128, cells = cells }, touchSheet, row(touchPal, 0))
    if full then
      local Contest = require("src.import.Gen4ContestArt")
      for n, y in ipairs({ 8, 48, 88 }) do out["touch_ball_" .. (n - 1)] = Contest.crop(full, 0, y, 40, 40) end
    end
  end

  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

-- menu.NCLR's colours the screen draws with, as 0..255 triples.  Row 0 is the
-- text palette (15 white ink, 14 shadow, 3/4 the blue the field moves and the
-- male symbol use, 5/6 the female symbol's red); rows 3, 4 and 5 carry the HP
-- bar's green, yellow and red at 9 (light) and 10 (dark).
function Gen4PartyArt.ink(pal)
  local function at(r, i) local c = pal and pal[r * 16 + i + 1] return c and { c[1], c[2], c[3] } end
  return {
    text = at(0, 15) or { 255, 255, 255 }, shadow = at(0, 14) or { 41, 41, 41 },
    blue = at(0, 3) or { 0, 115, 255 }, blueShadow = at(0, 4) or { 123, 189, 238 },
    red = at(0, 5) or { 238, 32, 16 }, redShadow = at(0, 6) or { 255, 172, 189 },
    hpGreen = { at(3, 9) or { 98, 255, 98 }, at(3, 10) or { 24, 197, 32 } },
    hpYellow = { at(4, 9) or { 255, 222, 0 }, at(4, 10) or { 238, 172, 0 } },
    hpRed = { at(5, 9) or { 255, 156, 156 }, at(5, 10) or { 255, 74, 57 } },
  }
end

function Gen4PartyArt.data(rom)
  local member = opener(rom, Gen4PartyArt.PATH)
  local G = require("src.import.Gen4Graphics")
  local pal = member and G.palette(member("menu.NCLR"))
  if not pal then return {} end
  return Gen4PartyArt.ink(pal)
end

return Gen4PartyArt
