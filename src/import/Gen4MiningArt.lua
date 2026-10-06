-- PLATINUM'S MINING GAME ART (src/underground/mining.c), the pieces the
-- generic screen planner cannot give: the tool buttons' other states, the
-- sheets in the palette row the cartridge actually draws them with, and the
-- sprites.
--
-- From /data/ug_fossil.narc (interface_tiles.NCGR, interface_tiles.NCLR) and
-- /data/ug_parts.narc (dirt_tiles.NCGR):
--
--   interface_tiles_row2   the whole 54x8-tile interface sheet in palette row
--                          2 -- the wall crack (interface.NSCR rows 0-3 cols
--                          0-25 carry palette 2, and Mining_DrawWallCrack
--                          keeps those bits)
--   dirt_tiles_row2        the 16x2-tile dirt sheet in interface_tiles.NCLR
--                          row 2: Mining_DrawDirt writes TILEMAP_PALETTE_SHIFT(2)
--                          and dirt_tiles.NCLR is never loaded
--   hammer_btn_{up,mid,down}, pickaxe_btn_{up,mid,down}
--                          the 6x8-tile button blocks Mining_DrawButton copies
--                          onto BG1 (palette 0, the cleared buffer's): base
--                          tiles 18/24/30 and 36/42/48, a row every 54 tiles
--
-- From /data/ug_anim.narc, every cell with its origin (the OAM palette is
-- ADDED to the resource's base, which is the start of the file's colours):
--
--   anim_<n>        animations_cell cells 1..22, animations.NCLR row 0
--   crack_end_<n>   crack_end_cell cells 0..5, interface_tiles.NCLR row 2
--
-- Written to assets/generated/gen4/mining/<key>.png, indexed in the cache
-- module `gen4_mining_art`.

local Gen4MiningArt = {}

Gen4MiningArt.FOSSIL = "/data/ug_fossil.narc"
Gen4MiningArt.PARTS = "/data/ug_parts.narc"
Gen4MiningArt.ANIM = "/data/ug_anim.narc"

-- the button blocks' base tiles (MINING_BASE_TILE_*_BUTTON_*)
Gen4MiningArt.BUTTONS = {
  hammer_btn_up = 18, hammer_btn_mid = 24, hammer_btn_down = 30,
  pickaxe_btn_up = 36, pickaxe_btn_mid = 42, pickaxe_btn_down = 48,
}
Gen4MiningArt.SHEET_WIDTH = 54

function Gen4MiningArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local A = require("src.import.Gen4Archives")
  local Cells = require("src.import.Gen4Cells")
  local archives = {}
  local function member(path, name)
    if archives[path] == nil then
      local b = rom:read(path)
      archives[path] = b and N.parse(b) or false
    end
    local narc = archives[path]
    if not narc then return nil end
    local b = narc:get(A.find(path, name))
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local sheet = G.tiles(member(Gen4MiningArt.FOSSIL, "interface_tiles.NCGR"))
  local pal = G.palette(member(Gen4MiningArt.FOSSIL, "interface_tiles.NCLR"))
  if not (sheet and pal) then return nil, "ug_fossil unreadable" end
  local out = {}

  -- a whole sheet laid out at its declared width in one palette row
  local function whole(s, tilesX, row)
    local tilesY = math.floor(s.count / tilesX)
    local cells = {}
    for i = 0, tilesX * tilesY - 1 do cells[i + 1] = { tile = i, palette = row } end
    return G.compose({ width = tilesX * 8, height = tilesY * 8, cells = cells }, s, pal)
  end
  local W = sheet.tilesX or Gen4MiningArt.SHEET_WIDTH
  out.interface_tiles_row2 = whole(sheet, W, 2)
  local dirt = G.tiles(member(Gen4MiningArt.PARTS, "dirt_tiles.NCGR"))
  if dirt then out.dirt_tiles_row2 = whole(dirt, dirt.tilesX or 16, 2) end

  -- Mining_DrawButton: 6 tiles across, a row every `rowGapLength` (the sheet
  -- width) tiles
  for key, base in pairs(Gen4MiningArt.BUTTONS) do
    local cells = {}
    for row = 0, 7 do
      for col = 0, 5 do cells[#cells + 1] = { tile = base + row * W + col, palette = 0 } end
    end
    out[key] = G.compose({ width = 48, height = 64, cells = cells }, sheet, pal)
  end

  -- the sprites: every cell, its OAM palette kept (added to the base)
  local function cells(prefix, ncgr, ncer, colours, first, last)
    local s = G.tiles(member(Gen4MiningArt.ANIM, ncgr))
    local bank = Cells.parse(member(Gen4MiningArt.ANIM, ncer), G)
    if not (s and bank and colours) then return end
    for n = first, last do
      local cell = bank.cells[n + 1]
      local pic = cell and Cells.assemble(cell, s, colours, bank, G)
      if pic then
        pic.originX, pic.originY = Cells.extent(cell)
        out[prefix .. n] = pic
      end
    end
  end
  cells("anim_", "animations.NCGR", "animations_cell.NCER",
        G.palette(member(Gen4MiningArt.ANIM, "animations.NCLR")), 1, 22)
  cells("crack_end_", "crack_end.NCGR", "crack_end_cell.NCER", pal, 0, 5)
  return out
end

return Gen4MiningArt
