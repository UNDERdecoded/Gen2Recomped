-- "Without voxel mod water is gray".
--
-- Gen2 maps bake a pre-colored atlas from the tileset's own palMap/palColors
-- (LoadTilesetPalette's packed tile->palette nibbles at 02:$40C7 for
-- TilesetJohto, 48 bytes = 96 tiles; PAL_BG_WATER is index 3).  The surf
-- shimmer (TILEANIM_WATER -> an `hshift` entry on tile $14) OVERDRAWS that
-- atlas every frame, and it used to be built straight off the raw grayscale
-- sheet because buildAnim only knew how to look up RED++'s eight world
-- groups.  Tile $14 is the bulk of open water, so the sea went grey while the
-- un-animated wave crests ($58, same palette) stayed blue.
local U = dofile("tests/drivers/util.lua")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL " .. name) end
end

local WATER_TILE, WAVE_TILE = 0x14, 0x58

return function(game)
  local TileRenderer = require("src.render.TileRenderer")

  U.newGame(game)
  U.wait(20)
  U.teleport(game, "ROUTE41", 22, 13)
  U.wait(30)
  local ow = game.stack:top()
  local ts = ow.map.tileset
  check("on Route 41", ow.map and ow.map.id == "ROUTE41")
  check("TilesetJohto", ts.id == "TilesetJohto")
  check("palMap extracted", ts.palMap and #ts.palMap == 96)
  check("7 BG palettes", ts.palColors and #ts.palColors == 7)
  check("water animation declared", ts.animation == "TILEANIM_WATER")

  -- PAL_BG_WATER: white, then two blues, then the shared dark shade.
  local water = TileRenderer.gen2TileColors(ts.palMap, ts.palColors, WATER_TILE)
  check("water tile has a palette", water ~= nil)
  if water then
    check("PAL_BG_WATER shade 0 is white",
          water[1][1] == 255 and water[1][2] == 255 and water[1][3] == 255)
    check("PAL_BG_WATER shade 1 is blue", water[2][3] > water[2][1] + 100)
    check("PAL_BG_WATER shade 2 is blue", water[3][3] > water[3][1] + 100)
  end
  local wave = TileRenderer.gen2TileColors(ts.palMap, ts.palColors, WAVE_TILE)
  check("wave crests share the water palette", wave == water)

  -- the grey fallback is palette 0, which is what tile $14 used to get
  local grey = TileRenderer.gen2TileColors(ts.palMap, ts.palColors, 0x59)
  check("palette 0 really is the grey one",
        grey and grey[2][1] == grey[2][2] and grey[2][2] == grey[2][3])
  check("water is NOT the grey palette", water ~= grey)

  -- out-of-range tiles must not crash the lookup
  check("tile past the palMap falls back", TileRenderer.gen2TileColors(
          ts.palMap, ts.palColors, 4096) == ts.palColors[1])
  check("no palMap -> no colors",
        TileRenderer.gen2TileColors(nil, ts.palColors, WATER_TILE) == nil)

  -- the renderer must have baked the atlas AND built the shimmer
  local r = ow.map.renderer
  check("Gen2 atlas baked (trueColor)", r.trueColor == true)
  check("one animated entry", r.anims and #r.anims == 1)
  local anim = r.anims and r.anims[1]
  check("it claims the water tile", anim and anim.tiles[1] == WATER_TILE)
  check("8 shift variants", anim and anim.textures and #anim.textures == 8)
  check("the water tile is claimed", r.claimedBy and r.claimedBy[WATER_TILE] ~= nil)

  -- ...and the shade->color mapping the shimmer's variants are built through
  -- has to turn the sheet's greys into that palette's blues.
  local rs = TileRenderer.recolorSample
  local function sample(shade)
    local r, g, b = rs(shade, shade, shade, 1, water)
    return math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
           math.floor(b * 255 + 0.5)
  end
  local r1, g1, b1 = sample(0.66) -- the sheet's light grey
  check("light grey recolors to blue", b1 > r1 + 100 and b1 > g1 + 100)
  local r2, g2, b2 = sample(0.33) -- the sheet's dark grey
  check("dark grey recolors to blue", b2 > r2 + 100 and b2 > g2 + 100)
  local ur, ug, ub = rs(0.66, 0.66, 0.66, 1, nil)
  check("no palette leaves it grey", ur == ug and ug == ub)

  U.log(("RESULT %s (%d pass, %d fail)"):format(fail == 0 and "PASS" or "FAIL",
                                                pass, fail))
end
