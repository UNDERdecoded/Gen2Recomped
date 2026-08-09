-- Driver: what did the detector decide over a rectangle of tiles?
--
-- Prints, for every tile of MOUND_RECT on MOUND_MAP, the resolved shape
-- class and the volume run height Structures gave it -- the ground truth
-- for diagnosing cliff/mound columns that extrude to the wrong height
-- (Diglett's Cave entrance ridge, bug of 2026-07-27). Then a shot.
--
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/voxel_mound_probe.lua lovec .
--
-- knobs (env):
--   MOUND_MAP    map id                       (default ROUTE_2)
--   MOUND_RECT   "tx0,ty0,tx1,ty1" in tiles   (default 16,12,35,23)
--   MOUND_SPOT   "x,y[,facing]" player cell   (default 12,12,up)
--   SHOT_DIR     output directory, must exist (default "shots")
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local DIR = os.getenv("SHOT_DIR") or "shots"
  local mapId = os.getenv("MOUND_MAP") or "ROUTE_2"
  local rx0, ry0, rx1, ry1 = (os.getenv("MOUND_RECT") or "16,12,35,23")
    :match("^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
  rx0, ry0, rx1, ry1 = tonumber(rx0), tonumber(ry0), tonumber(rx1), tonumber(ry1)
  local sx, sy, facing = (os.getenv("MOUND_SPOT") or "12,12,up")
    :match("^%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%a*)")
  facing = (facing ~= "" and facing) or "up"

  local Zoom = require("src.render.Zoom")
  Zoom.reset()
  Pipelines.setLevel("tiltshift", 0)
  U.teleport(game, mapId, tonumber(sx), tonumber(sy), facing)
  U.wait(20)
  Pipelines.setLevel("voxel",
    math.floor(tonumber(os.getenv("MOUND_LEVEL")) or 3))
  U.wait(30)

  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  local Structures = V and V.require("Structures")
  local ow = game.overworld
  if Structures and ow and ow.map then
    local S = Structures.forMap(ow.map)
    local function keyOf(tx, ty) return (ty + 64) * 4096 + (tx + 64) end
    print(("[mound] %s tiles (%d,%d)-(%d,%d): tile/class/h per column")
      :format(mapId, rx0, ry0, rx1, ry1))
    for ty = ry0, ry1 do
      local row = {}
      for tx = rx0, rx1 do
        local k = keyOf(tx, ty)
        local s = S.shapeAt[k]
        local run = S.runs[k]
        local h = run and run.h or (s and s.h) or 0
        if S.skip[k] then h = 0 end
        row[#row + 1] = ("%02X%s%02d"):format(S.tileAt[k] or 0xFF,
          s and s.class:sub(1, 1) or "?", h)
      end
      print("[mound] " .. table.concat(row, " "))
    end
  end

  game.capturePath = ("%s/mound_%s.png"):format(DIR, mapId)
  U.wait(5)
  Pipelines.setLevel("voxel", 0)
  U.wait(5)
  print("[mound] done")
end
