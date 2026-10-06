-- PLATINUM'S POKE MART COUNTER ART (src/overlay007/shop_menu.c), from
-- /graphic/shop_gra.narc.
--
--   counter          BG1: tiles.NCGR + tilemap.NSCR in default.NCLR
--                    (Shop_LoadGraphics, MART_TYPE_NORMAL / FRONTIER) -- the
--                    list plate, the description band and the icon well, with
--                    the top-left left transparent for the field to show through
--   counter_no_item  the same over tilemap_no_item.NSCR (the decoration and
--                    seal counters, which have no item icon)
--   counter_frontier the normal map in frontier.NCLR (the Battle Frontier's)
--
-- SPRITES (SpriteResourceManager: an explicit palette, the template's plttIdx
-- row of sprites.NCLR, replacing the cell's own):
--
--   cursor_0 / cursor_1   the list highlight, cursor.NCGR/_cell/_anim
--                         sequence 0, in row 0 -- and in row 1 once an item
--                         is chosen (Shop_SetCursorSpritePalette ->
--                         Sprite_SetExplicitPalette2(cursor, selected))
--   scroll_up / scroll_down   scroll_arrow sequences 0 and 1
--
-- Written to assets/generated/gen4/shop_art/<key>.png and indexed in the cache
-- module `gen4_shop_art`.

local Gen4ShopArt = {}

Gen4ShopArt.PATH = "/graphic/shop_gra.narc"

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

local function row(colours, r)
  local out = {}
  for i = 1, 16 do out[i] = colours[r * 16 + i] or { 0, 0, 0 } end
  return out
end

function Gen4ShopArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local Anim = require("src.import.Gen4CellAnim")
  local member = opener(rom, Gen4ShopArt.PATH)
  if not member then return nil, "shop_gra missing" end
  local out = {}
  local sheet = G.tiles(member("tiles.NCGR"))
  local pal, frontier = G.palette(member("default.NCLR")), G.palette(member("frontier.NCLR"))
  local map, noItem = G.tilemap(member("tilemap.NSCR")), G.tilemap(member("tilemap_no_item.NSCR"))
  if not (sheet and pal and map) then return nil, "shop_gra counter unreadable" end
  out.counter = G.compose(map, sheet, pal)
  if noItem then out.counter_no_item = G.compose(noItem, sheet, pal) end
  if frontier then out.counter_frontier = G.compose(map, sheet, frontier) end

  local sprites = G.palette(member("sprites.NCLR"))
  local function sprite(prefix, sequence, r)
    local s = G.tiles(member(prefix .. ".NCGR"))
    local bank = Cells.parse(member(prefix .. "_cell.NCER"), G)
    local anim = Anim.parse(member(prefix .. "_anim.NANR"), G)
    if not (s and bank and anim and sprites) then return nil end
    local frames = Anim.frames(anim, sequence)
    local cell = frames and frames[1] and bank.cells[frames[1].cell + 1]
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
    local pic = Cells.assemble(flat, s, row(sprites, r), bank, G)
    if pic then pic.originX, pic.originY = Cells.extent(flat) end
    return pic
  end
  out.cursor_0 = sprite("cursor", 0, 0)
  out.cursor_1 = sprite("cursor", 0, 1)
  out.scroll_up = sprite("scroll_arrow", 0, 0)
  out.scroll_down = sprite("scroll_arrow", 1, 0)

  -- `special`: font_special_chars' 23 tiles (0-9, "/", "Lv.", "No.", ...) in
  -- FontSpecialChars_Init(1, 2, 0) over the field text palette (pl_font
  -- font.NCLR) -- the "No.01" a TM counter prints before the move name
  local font = opener(rom, "/graphic/pl_font.narc")
  local chars = font and G.tiles(font(require("src.import.Gen4SpecialChars").MEMBER))
  local fontPal = font and G.palette(font(6))
  if chars and fontPal then
    local cells = {}
    for t = 0, 22 do cells[t + 1] = { tile = t, palette = 0 } end
    out.special = G.compose({ width = 23 * 8, height = 8, cells = cells }, chars,
      { { 0, 0, 0 }, fontPal[2], fontPal[3] })
  end

  for k, v in pairs(out) do if not v then out[k] = nil end end
  return out
end

return Gen4ShopArt
