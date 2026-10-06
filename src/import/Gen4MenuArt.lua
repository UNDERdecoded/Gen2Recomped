-- THE FIELD MENUS' SPRITES IN THEIR RIGHT COLOURS, from /graphic/menu_gra.narc.
--
-- The generic planner composes `menu/cursor` with menu.NCLR row 0, where
-- entry 15 is grey; the start menu (start_menu.c) and the Underground menu
-- (underground/menus.c) both give the cursor palette ROW 1, whose entry 15
-- is the orange edge.
--
--   cursor          cursor.NCGR / cursor_cell.NCER, menu.NCLR row 1 -- the
--                   field start menu's (96x32, origin -48,-16)
--   ug_cursor       the same cell, underground_menu.NCLR row 1 -- the
--                   Underground menu's
--   ug_icon_<i>_grey / ug_icon_<i>_colour
--                   underground_icons.NCGR / _cell.NCER cell i (option i's
--                   first frame, animations option*3 + {0,1,2}),
--                   underground_menu.NCLR row 0 (unselected) / row 1
--                   (selected) -- 32x32, origin -16,-16
--
-- Written to assets/generated/gen4/menu_art/<key>.png, indexed in the cache
-- module `gen4_menu_art`.

local Gen4MenuArt = {}

Gen4MenuArt.PATH = "/graphic/menu_gra.narc"
Gen4MenuArt.UG_OPTIONS = 7

function Gen4MenuArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local A = require("src.import.Gen4Archives")
  local Cells = require("src.import.Gen4Cells")
  local bytes = rom:read(Gen4MenuArt.PATH)
  if not bytes then return nil, "menu_gra missing" end
  local narc = N.parse(bytes)
  local function member(name)
    local b = narc:get(A.find(Gen4MenuArt.PATH, name))
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local menuPal = G.palette(member("menu.NCLR"))
  local ugPal = G.palette(member("underground_menu.NCLR"))
  if not (menuPal and ugPal) then return nil, "menu_gra palettes unreadable" end
  local function row(all, r)
    local colours = {}
    for i = r * 16 + 1, r * 16 + 16 do colours[#colours + 1] = all[i] or { 0, 0, 0 } end
    return colours
  end
  -- an explicit palette row: the template's, replacing the OAM's (all 0 here)
  local function flat(cell)
    local copy = { oam = {} }
    for k, v in pairs(cell) do if k ~= "oam" then copy[k] = v end end
    for i, o in ipairs(cell.oam) do
      local c = {}
      for k, v in pairs(o) do c[k] = v end
      c.palette = 0
      copy.oam[i] = c
    end
    return copy
  end
  local out = {}
  local function sprite(key, ncgr, ncer, n, colours)
    local sheet = G.tiles(member(ncgr))
    local bank = Cells.parse(member(ncer), G)
    local cell = bank and bank.cells[n + 1]
    if not (sheet and cell) then return end
    cell = flat(cell)
    local pic = Cells.assemble(cell, sheet, colours, bank, G)
    if pic then
      pic.originX, pic.originY = Cells.extent(cell)
      out[key] = pic
    end
  end
  sprite("cursor", "cursor.NCGR", "cursor_cell.NCER", 0, row(menuPal, 1))
  sprite("ug_cursor", "cursor.NCGR", "cursor_cell.NCER", 0, row(ugPal, 1))
  for i = 0, Gen4MenuArt.UG_OPTIONS - 1 do
    sprite(("ug_icon_%d_grey"):format(i), "underground_icons.NCGR", "underground_icons_cell.NCER", i, row(ugPal, 0))
    sprite(("ug_icon_%d_colour"):format(i), "underground_icons.NCGR", "underground_icons_cell.NCER", i, row(ugPal, 1))
  end
  return out
end

return Gen4MenuArt
