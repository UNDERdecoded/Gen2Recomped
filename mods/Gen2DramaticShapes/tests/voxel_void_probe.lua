-- Driver: does voxel mode survive every VOID FILL mode?
--
-- The ring around a map's body is baked into the terrain mesh, and which
-- block it is made of comes from the same TileRenderer.borderBlockFor the
-- 2D path uses -- including the BLACK mode, which is not a block at all.
-- This walks the three modes on an outdoor map, reports whether the mesh
-- built and whether the scene actually took the 3D path, and shoots each.
--
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/voxel_void_probe.lua lovec .
--
-- knobs (env):
--   VOID_MAP    map id                        (default PALLET_TOWN)
--   VOID_SPOT   "x,y[,facing]"                (default 5,6,down)
--   VOID_LEVEL  voxel rung                    (default 3)
--   SHOT_DIR    output directory, must exist  (default "shots")
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")
  local TileRenderer = require("src.render.TileRenderer")

  local SPEED = math.max(1,
    math.floor(tonumber(os.getenv("POKEPORT_SPEED")) or 1))
  local function wait(n) U.wait(n * SPEED) end

  local DIR = os.getenv("SHOT_DIR") or "shots"
  local mapId = os.getenv("VOID_MAP") or "PALLET_TOWN"
  local level = math.floor(tonumber(os.getenv("VOID_LEVEL")) or 3)
  local sx, sy, facing = (os.getenv("VOID_SPOT") or "5,6,down")
    :match("^%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%a*)")
  facing = (facing ~= "" and facing) or "down"

  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  assert(V, "DRAMATIC_SHAPE exports not reachable")
  local Voxel = V.require("VoxelState")
  local ChunkMesher = V.require("ChunkMesher")

  local Zoom = require("src.render.Zoom")
  Zoom.reset()
  Pipelines.setLevel("tiltshift", 0)
  U.teleport(game, mapId, tonumber(sx), tonumber(sy), facing)
  wait(20)
  Pipelines.setLevel("voxel", level)
  wait(30)

  for _, mode in ipairs(TileRenderer.VOID_FILLS) do
    -- Set it the way the options row does and NOTHING else: the ring is
    -- baked into the mesh, so the mod has to notice the change and drop
    -- the cache itself. Invalidating here would hide exactly the bug this
    -- driver exists to catch.
    TileRenderer.setVoidFill(mode)
    wait(40)
    local ow = game.overworld
    local border = TileRenderer.borderBlockFor(ow.map)
    local ok, mesh = pcall(ChunkMesher.peek, ow.map, false)
    print(("[void] %-6s border=%-5s mesh=%s ready=%s pending=%d")
      :format(mode, tostring(border),
              tostring(ok and mesh ~= nil), tostring(Voxel.ready),
              ChunkMesher.pending()))
    game.capturePath = ("%s/void_%s_%s.png"):format(DIR, mapId, mode)
    wait(4)
  end

  TileRenderer.setVoidFill("trees")
  Pipelines.setLevel("voxel", 0)
  wait(5)
  print("[void] done")
end
