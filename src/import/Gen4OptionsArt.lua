-- PLATINUM'S OPTIONS SCREEN ART (src/applications/options_menu.c LoadBgTiles),
-- from /graphic/config_gra.narc: tiles.NCGR, tiles.NCLR and tilemap.bin.
--
--   options_bg      BG_LAYER_MAIN_2 (and SUB_0) filled with tile 1, palette 0,
--                   32 x 32 -- the screen's backdrop pattern (priority 3)
--   options_cursor  BG_LAYER_MAIN_0: the tilemap's first two rows (32 x 2
--                   tiles), scrolled down to cursor x 16 + 24 -- the row
--                   highlight, drawn OVER the windows (priority 1 to their 2)
--
-- Written to assets/generated/gen4/options/<key>.png, indexed in the cache
-- module `gen4_options_art`.

local Gen4OptionsArt = {}

Gen4OptionsArt.PATH = "/graphic/config_gra.narc"

function Gen4OptionsArt.images(rom)
  local G = require("src.import.Gen4Graphics")
  local N = require("src.import.NarcArchive")
  local A = require("src.import.Gen4Archives")
  local bytes = rom:read(Gen4OptionsArt.PATH)
  if not bytes then return nil, "config_gra missing" end
  local narc = N.parse(bytes)
  local function member(name)
    local b = narc:get(A.find(Gen4OptionsArt.PATH, name))
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local sheet, pal, map = G.tiles(member("tiles.NCGR")), G.palette(member("tiles.NCLR")), G.tilemap(member("tilemap.bin"))
  if not (sheet and pal and map) then return nil, "config_gra unreadable" end
  local out = {}
  -- the backdrop: tile 1 everywhere
  local cells = {}
  for i = 1, 32 * 24 do cells[i] = { tile = 1, palette = 0 } end
  out.options_bg = G.compose({ width = 256, height = 192, cells = cells }, sheet, pal)
  -- the cursor: the map's first two rows
  local bar = {}
  for row = 0, 1 do
    for col = 0, 31 do
      local c = map.cells[row * math.floor((map.width or 256) / 8) + col + 1]
      bar[#bar + 1] = c and { tile = c.tile, flipX = c.flipX, flipY = c.flipY, palette = c.palette } or { tile = 0, palette = 0 }
    end
  end
  out.options_cursor = G.compose({ width = 256, height = 16, cells = bar }, sheet, pal)
  return out
end

return Gen4OptionsArt
