-- Scratch probe: how long do a building model's merged quads get?
--
-- A quad's longest world-space edge is what decides how far its CHORD
-- falls below the world curve's parabola, so this is the number that says
-- whether the bend can crack the mesh open.
--
--   BUILD_MAP=CERULEAN_CITY POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/roof_span_probe.lua lovec .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local mapId = os.getenv("BUILD_MAP") or "CERULEAN_CITY"
  U.teleport(game, mapId, tonumber(os.getenv("BUILD_X") or "30"),
             tonumber(os.getenv("BUILD_Y") or "20"), "up")
  U.wait(30)

  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  local Structures = V and V.require("Structures")
  local ow = game.overworld
  if not (Structures and ow and ow.map) then
    print("[span] mod or map unavailable")
    love.event.quit()
    return
  end
  local S = Structures.forMap(ow.map)
  local hist, worst = {}, 0
  for _, q in ipairs(S.objectQuads) do
    local dx = math.max(q[1][1], q[2][1], q[3][1], q[4][1])
             - math.min(q[1][1], q[2][1], q[3][1], q[4][1])
    local dz = math.max(q[1][3], q[2][3], q[3][3], q[4][3])
             - math.min(q[1][3], q[2][3], q[3][3], q[4][3])
    local dy = math.max(q[1][2], q[2][2], q[3][2], q[4][2])
             - math.min(q[1][2], q[2][2], q[3][2], q[4][2])
    local span = math.max(dx, dz, dy)
    local bucket = span <= 8 and "<=8" or (span <= 16 and "<=16"
                  or (span <= 32 and "<=32" or (span <= 64 and "<=64" or ">64")))
    bucket = bucket .. (q.own and " bld" or " prop")
    hist[bucket] = (hist[bucket] or 0) + 1
    if span > worst then worst = span end
  end
  print(("[span] %d object quads, longest edge %d px"):format(#S.objectQuads, worst))
  for _, b in ipairs({ "<=8", "<=16", "<=32", "<=64", ">64" }) do
    for _, kind in ipairs({ " bld", " prop" }) do
      print(("[span]   %-10s %d"):format(b .. kind, hist[b .. kind] or 0))
    end
  end
  love.event.quit()
end
