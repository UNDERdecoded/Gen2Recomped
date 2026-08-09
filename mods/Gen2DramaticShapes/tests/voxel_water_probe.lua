-- Driver: WHY is the terrain animation not moving?
--
-- Water and flowers animate by rewriting their slots in a private copy of
-- the tileset atlas once per step. That chain has several links and every
-- one of them fails quietly -- the mode just keeps drawing a still atlas.
-- This walks the chain in the LIVE game and prints where it stops, for the
-- palette mode currently active.
--
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/voxel_water_probe.lua lovec .
--
-- knobs (env):
--   WATER_MAP    map id                      (default PALLET_TOWN)
--   WATER_SPOT   "x,y[,facing]"              (default 5,6,down)
--   WATER_MODE   palette mode to force       (default: leave as-is)
--   WATER_LEVEL  voxel rung                  (default 3)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")
  local TileRenderer = require("src.render.TileRenderer")
  local PaletteFX = require("src.render.PaletteFX")

  local mapId = os.getenv("WATER_MAP") or "PALLET_TOWN"
  local level = math.floor(tonumber(os.getenv("WATER_LEVEL")) or 3)
  local sx, sy, facing = (os.getenv("WATER_SPOT") or "5,6,down")
    :match("^%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%a*)")
  facing = (facing ~= "" and facing) or "down"

  local function say(...) print("[water] " .. string.format(...)) end

  if os.getenv("WATER_MODE") then PaletteFX.setMode(os.getenv("WATER_MODE")) end

  U.teleport(game, mapId, tonumber(sx), tonumber(sy), facing)
  U.wait(20)
  Pipelines.setLevel("voxel", level)
  U.wait(30)                       -- outlast the camera tween

  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  if not V then return say("mod exports unreachable -- is it enabled?") end
  local TerrainAtlas = V.require("TerrainAtlas")

  local ow = game.overworld
  local map = ow and ow.map
  if not map then return say("no live map") end

  say("mode=%s (%s)", tostring(PaletteFX.mode),
      tostring(PaletteFX.modeLabel()))
  say("map=%s tileset=%s animation=%s", tostring(map.id),
      tostring(map.tileset.id), tostring(map.tileset.animation))

  -- 1. does the engine think this tileset animates at all?
  local specs = TileRenderer.defaultAnimatedTiles(map.tileset)
  say("engine animated specs: %d", specs and #specs or 0)
  if not specs or #specs == 0 then
    return say("STOP: this tileset declares no animated tiles")
  end

  -- 2. is the clock advancing? this is the seam the engine does not export
  local clock = TerrainAtlas._animFrame
  if not clock then return say("STOP: no clock accessor on TerrainAtlas") end
  local t0 = clock()
  U.wait(30)
  local t1 = clock()
  say("clock: %s -> %s (%s)", tostring(t0), tostring(t1),
      (t1 > t0) and "advancing" or "FROZEN")
  if t1 <= t0 then
    return say("STOP: the tile clock is not advancing -- animFrame seam lost")
  end

  -- 3. which pixel source is in play, and is an animated copy being made?
  local gbc = map.renderer and map.renderer.gbcAtlas
  say("renderer.gbcAtlas=%s renderer.data=%s",
      tostring(gbc and true or false),
      tostring(map.renderer and map.renderer.data ~= nil))
  if gbc then
    local groups = PaletteFX.worldGroupColors(map.renderer.data,
                                              map.tileset.id, map.id, nil)
    say("worldGroupColors: %s", groups and "present (CPU rebuild can run)"
        or "MISSING (CPU rebuild cannot run)")
  end

  local colors = nil
  local VoxelScene = V.require("VoxelScene")
  if VoxelScene._modeColors then
    colors = VoxelScene._modeColors(function(m)
      return PaletteFX.pal(game.data, ow:paletteNameFor(m or map))
    end, map)
  end
  say("colours for the bake: %s", colors and "present" or "nil (art as-is)")

  local img = TerrainAtlas.forMap(map, colors)
  local isCopy = img ~= nil and img ~= map.renderer.image
  say("forMap -> %s", img == nil and "NIL"
      or (isCopy and "an ANIMATED copy" or "the STATIC atlas (no animation)"))
  if not isCopy then
    return say("STOP: no animated copy -- the entry could not be built")
  end

  -- 4. does the copy actually change as the clock turns over?
  local seen, order = {}, {}
  for i = 1, 6 do
    local before = clock()
    U.wait(25)                     -- more than one 20-frame period
    local step = math.floor(clock() / 20) % 8
    if not seen[step] then seen[step] = true; order[#order + 1] = step end
    say("  sample %d: clock %s -> %s, water step %d",
        i, tostring(before), tostring(clock()), step)
  end
  say("distinct water steps seen: %d", #order)
  if #order <= 1 then
    say("STOP: the step is not turning over -- clock is moving but the")
    say("      period maths is not reaching a new step")
  else
    say("OK: the atlas is being repatched; if the WATER still looks still,")
    say("    the animated tiles are not in the terrain quads -- run")
    say("    voxel_anim_probe.lua, which dumps the atlas and counts where")
    say("    tile $14 ended up in the geometry")
  end
end
