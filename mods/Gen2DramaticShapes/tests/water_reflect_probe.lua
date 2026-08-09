-- Driver: WHY is the water not reflecting anything?
--
-- The reflective pass has several links and every one of them fails quietly
-- back to flat water, which looks exactly like the row being off. This walks
-- the chain in the LIVE game and prints where it stops.
--
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/water_reflect_probe.lua lovec .
--
-- knobs (env):
--   REFL_MAP    map id                       (default PALLET_TOWN)
--   REFL_SPOT   "x,y[,facing]"               (default 5,6,down)
--   REFL_LEVEL  voxel rung                   (default 5, the 75-degree camera,
--                                             which is where a reflection is
--                                             most of what you can see)
--   REFL_TIME   daytime pin (day/dusk/...)   (default: leave as-is)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local mapId = os.getenv("REFL_MAP") or "PALLET_TOWN"
  local level = math.floor(tonumber(os.getenv("REFL_LEVEL")) or 5)
  local sx, sy, facing = (os.getenv("REFL_SPOT") or "5,6,down")
    :match("^%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%a*)")
  facing = (facing ~= "" and facing) or "down"

  local function say(...) print("[water-ssr] " .. string.format(...)) end

  U.teleport(game, mapId, tonumber(sx), tonumber(sy), facing)
  U.wait(20)
  Pipelines.setLevel("voxel", level)
  U.wait(40)                       -- outlast the camera tween and the build

  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  if not V then return say("mod exports unreachable -- is it enabled?") end

  local Water = V.require("Water")
  local Voxel3D = V.require("Voxel3D")
  local ChunkMesher = V.require("ChunkMesher")
  local Sky = V.require("Sky")
  local DayNight = V.require("DayNight")

  if os.getenv("REFL_TIME") then
    DayNight.setting:sync(os.getenv("REFL_TIME"))
    U.wait(5)
  end

  local ow = game.overworld
  local map = ow and ow.map
  if not map then return say("no live map") end

  -- 1. is the row on at all?
  say("row=%s level=%d", tostring(Water.setting:get()), Water.level())
  if not Water.enabled() then
    return say("STOP: WATER is OFF -- press 9, or set the row")
  end

  -- 2. is there any water on this map to reflect in?
  local terrain, water = ChunkMesher.pair(map, false)
  if not terrain then terrain, water = ChunkMesher.pair(map, true) end
  say("terrain mesh=%s water mesh=%s", tostring(terrain ~= nil),
      tostring(water ~= nil))
  if not terrain then
    return say("STOP: no terrain mesh yet -- the build is still cooking")
  end
  if not water then
    say("STOP: this map has no water surface. That is not a fault unless")
    say("      you can see a lake: check the tileset's water tiles reach")
    say("      TileShape (run voxel_survey.lua for the shape breakdown).")
    return
  end

  -- 3. did the driver give us a depth texture to read? This is the one
  --    hardware requirement the rest of the mode does not already have.
  say("depth canvas readable: %s", tostring(Voxel3D.depthReadable()))
  if not Voxel3D.depthReadable() then
    say("STOP: no readable depth canvas on this driver (tried depth24, ")
    say("      depth24stencil8, depth32f and depth16).")
    say("      The water falls back to the flat scene shader, which is")
    say("      exactly what it looked like before this feature existed.")
    return
  end

  -- 4. did the shader build? Both variants -- the wireframe one needs
  --    derivatives, which a driver may refuse on its own.
  say("shader plain=%s grid=%s",
      tostring(Water.shader(false) ~= nil), tostring(Water.shader(true) ~= nil))
  if not Water.shader(false) then
    return say("STOP: the water shader did not compile -- the mod log has "
               .. "the driver's own message")
  end

  -- 5. is there a sky to reflect, and something hanging in it?
  local ramp, count = Sky.ramp()
  say("sky ramp=%s bands=%s edge=%s", tostring(ramp ~= nil), tostring(count),
      tostring(Voxel3D.skyEdge))
  local body = DayNight.body()
  if body then
    local amt = DayNight.glow()
    local w, h = Voxel3D.size()
    local rpx = Sky.discRadius(h, Voxel3D.cell or 1,
                               { moon = body.moon, glowAmt = amt })
    local ang = rpx / ((h or 1) / math.max(1e-4, Voxel3D.fovY or 1))
    say("body=%s dir=(%.2f, %.2f, %.2f) disc=%.1fpx (%.2f deg)",
        body.moon and "moon" or "sun", body.dx, body.dy, body.dz, rpx,
        math.deg(ang))
  else
    say("body: none in the sky right now (set REFL_TIME=day or =night)")
  end
  if not ramp then
    say("NOTE: no band ramp -- indoors, or the ramp could not be built. The")
    say("      sky half of the reflection is off; the ray march still runs.")
  end

  -- 6. how much reflection this camera is actually asking for. Both numbers
  --    fall out of the rung, and between them they explain every "it only
  --    works at 75" report: Fresnel decides how much shows, and the lean
  --    decides whether what shows has anything in it.
  local f = Water.FRESNEL_FLOOR + (Water.FRESNEL_CEIL - Water.FRESNEL_FLOOR)
            * (1 - Voxel3D.descent) ^ Water.FRESNEL_POWER
  say("camera: descent %.3f -> fresnel about %.2f, horizon lean %.2f",
      Voxel3D.descent, f, Water.lean(Voxel3D.descent))
  say("waves: %d px columns, phase %.2f", Water.WAVE_HEIGHT, Water._waveTime())

  say("OK: every link is live. The effect is strongest at REFL_LEVEL=5 (the")
  say("    75-degree rung, where Fresnel is highest and the reflection is")
  say("    exact) and with a low sun (REFL_TIME=dusk).")
end
