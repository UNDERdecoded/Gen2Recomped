-- PLATINUM'S TOWN MAP, the data half (pokeplatinum src/applications/town_map).
--
-- The two top-screen backgrounds are already composed by the graphics stage
-- (`town_map/top_screen_region_bg.png`, the land and its frame, and
-- `top_screen_region_map.png`, the orange route layer over it). What was
-- missing is everything that moves:
--
--   * the OBJs -- cursor, player icon, the fly-destination blocks -- as palette
--     INDICES, because the blocks change sub-palette by state (locked /
--     unlocked / blinking, `Sprite_SetExplicitPalette(5 + palette + unlocked)`)
--     and a pre-coloured picture cannot;
--   * `top_screen_sprites.NCLR`, those sub-palettes;
--   * `/data/tmap_block.dat` -- the 182 grid cells that have a name to show
--     (`TownMap_GetMapBlockAtPosition`; a cell with no block shows nothing);
--   * `sFlyLocations` (fly_locations.c) -- where each of the twenty town blocks
--     sits and what shape it is. Code, not a file, so it is carried here as
--     data, header ids resolved from generated/map_headers.txt.
--
-- Written to the cache module `gen4_town_map`.

local Gen4TownMap = {}

Gen4TownMap.PATH = "/graphic/tmap_gra.narc"
Gen4TownMap.BLOCKS = "/data/tmap_block.dat"

-- TOWN_MAP_GRID_SPACING / _X_OFFSET / _Y_OFFSET (applications/town_map/defs.h)
Gen4TownMap.GRID, Gen4TownMap.OX, Gen4TownMap.OY = 7, 25, -34

-- sFlyLocations, in order. shape is the cell-animation index (1x1, vertical,
-- 2x2, top-left angle, top-right angle, horizontal, small rectangle); palette
-- 0 is blue (towns), 1 red/green (cities). x/y are pixels before the grid
-- offset.
Gen4TownMap.FLY_LOCATIONS = {
  { header = 411, shape = 0, palette = 0, x = 21,  y = 189 }, -- Twinleaf Town
  { header = 418, shape = 0, palette = 0, x = 35,  y = 182 }, -- Sandgem Town
  { header = 426, shape = 1, palette = 0, x = 35,  y = 136 }, -- Floaroma Town
  { header = 433, shape = 5, palette = 0, x = 122, y = 140 }, -- Solaceon Town
  { header = 442, shape = 0, palette = 0, x = 98,  y = 112 }, -- Celestic Town
  { header = 450, shape = 0, palette = 0, x = 140, y = 70 },  -- Survival Area
  { header = 457, shape = 0, palette = 0, x = 175, y = 98 },  -- Resort Area
  { header = 3,   shape = 2, palette = 1, x = 31,  y = 164 }, -- Jubilife City
  { header = 33,  shape = 1, palette = 1, x = 7,   y = 157 }, -- Canalave City
  { header = 45,  shape = 4, palette = 1, x = 60,  y = 164 }, -- Oreburgh City
  { header = 65,  shape = 3, palette = 1, x = 66,  y = 115 }, -- Eterna City
  { header = 86,  shape = 2, palette = 1, x = 101, y = 150 }, -- Hearthome City
  { header = 120, shape = 2, palette = 1, x = 129, y = 178 }, -- Pastoria City
  { header = 132, shape = 2, palette = 1, x = 150, y = 129 }, -- Veilstone City
  { header = 150, shape = 2, palette = 1, x = 185, y = 164 }, -- Sunyshore City
  { header = 165, shape = 1, palette = 1, x = 77,  y = 45 },  -- Snowpoint City
  { header = 188, shape = 5, palette = 1, x = 137, y = 91 },  -- Fight Area
  { header = 392, shape = 6, palette = 1, x = 63,  y = 196, special = "palPark", cell = { 9, 28 } },
  { header = 172, shape = 6, palette = 1, x = 182, y = 126, special = "victoryRoad", cell = { 26, 18 } },
  { header = 172, shape = 0, palette = 1, x = 182, y = 119, special = "league", cell = { 26, 17 } },
}

-- sTownMapFlyLocationUnlockFlags (context.c), FIRST_ARRIVAL_* in the same
-- order (values from generated/first_arrival_to_zones.txt): the town map's own
-- idea of which block is open. Fight Area 17, Poke Park front gate 67, outside
-- Victory Road 16, Pokemon League 68.
Gen4TownMap.FIRST_ARRIVAL = {
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 17, 67, 16, 68,
}

-- LoadMapName's cells off the main matrix (graphics.c), x/z -> header
Gen4TownMap.OFF_MATRIX = {
  { 11, 19, 207 }, { 11, 20, 207 }, { 11, 21, 207 }, { 11, 22, 207 },  -- Mt. Coronet 1F south
  { 12, 12, 207 }, { 12, 13, 207 }, { 12, 14, 207 }, { 12, 15, 207 },
  { 12, 16, 207 }, { 12, 17, 207 }, { 12, 18, 207 }, { 12, 19, 207 },
  { 20, 12, 560 },                                                      -- Fight Area gate
}

local IDENTITY = {}
for i = 0, 255 do IDENTITY[i + 1] = { i, 0, 0 } end

local function hexOf(image)
  local out = {}
  local rgba = image.rgba
  for p = 0, image.width * image.height - 1 do
    local r, a = rgba:byte(p * 4 + 1), rgba:byte(p * 4 + 4)
    out[p + 1] = ("%02x"):format(a == 0 and 0 or (r % 16))
  end
  return table.concat(out)
end

function Gen4TownMap.parseBlocks(b)
  if type(b) ~= "string" or #b < 4 then return nil end
  local function u16(at) local a, c = b:byte(at + 1, at + 2) return a + c * 256 end
  local n = u16(0)
  local out = {}
  for i = 0, n - 1 do
    local o = 4 + i * 24
    if o + 24 > #b then break end
    out[#out + 1] = {
      x = u16(o), z = u16(o + 2),
      signpostType = u16(o + 4), signpost = u16(o + 6),
      areaDesc = u16(o + 8), landmarkDesc = u16(o + 10),
      hidden = u16(o + 20),
    }
  end
  return out
end

function Gen4TownMap.extract(rom)
  local Narc = require("src.import.NarcArchive")
  local G = require("src.import.Gen4Graphics")
  local Cells = require("src.import.Gen4Cells")
  local raw = rom:read(Gen4TownMap.PATH)
  local arc = raw and Narc.parse(raw)
  if not arc then return nil, "no " .. Gen4TownMap.PATH end
  local function member(i)
    local b = arc:get(i)
    if b and G.isCompressed(b) then b = G.decompress(b) end
    return b
  end
  local out = { images = {}, flyLocations = Gen4TownMap.FLY_LOCATIONS,
                firstArrival = Gen4TownMap.FIRST_ARRIVAL, offMatrix = Gen4TownMap.OFF_MATRIX,
                grid = { spacing = Gen4TownMap.GRID, ox = Gen4TownMap.OX, oy = Gen4TownMap.OY } }
  out.spritePalette = G.palette(member(2))
  local function obj(key, tiles, cell)
    local sheet = G.tiles(member(tiles))
    local bank = Cells.parse(member(cell), G)
    if not (sheet and bank) then return end
    local list = {}
    for i, c in ipairs(bank.cells) do
      local image = Cells.assemble(c, sheet, IDENTITY, bank, G)
      if image then
        local x, y = Cells.extent(c)
        -- the OAM palette bank the cell was authored against: the red
        -- channel of the identity-palette picture is bank * 16 + colour
        local bank = 0
        for p = 0, image.width * image.height - 1 do
          if image.rgba:byte(p * 4 + 4) ~= 0 then
            bank = math.floor(image.rgba:byte(p * 4 + 1) / 16)
            break
          end
        end
        list[i] = { w = image.width, h = image.height, x = x, y = y, bank = bank,
                    idx = hexOf(image) }
      end
    end
    out.images[key] = list
  end
  obj("cursor", 7, 8)
  obj("player", 10, 11)
  obj("historyDot", 13, 14)
  obj("flyBlocks", 16, 17)
  out.blocks = Gen4TownMap.parseBlocks(rom:read(Gen4TownMap.BLOCKS))
  return out
end

return Gen4TownMap
