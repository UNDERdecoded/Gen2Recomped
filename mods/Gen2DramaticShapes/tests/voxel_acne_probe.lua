-- Driver: isolate the diagonal banding on flat lit geometry.
--
-- Shoots the SAME stand point four ways in ONE launch, so palette, camera
-- and framing are identical and the only variable is the sun pass:
--
--   _on     shadows as shipped
--   _off    SHADOW_ALPHA = 0 -- the sun pass still runs, nothing reads it
--   _flatN  a CONSTANT bias of N world px, i.e. SLOPE switched off
--
-- and prints, from the frustum the run actually fitted, how much depth
-- slack each face orientation NEEDS against the slack it is given. A face
-- whose need exceeds the slack shadows itself in a moire -- acne -- which
-- reads as diagonal banding, since the ramp it aliases against runs along
-- the light's frame and the sun sits southeast.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/voxel_acne_probe.lua lovec .
--
-- knobs (env):
--   ACNE_MAP     map id                   (default VIRIDIAN_CITY)
--   ACNE_SPOT    "x,y[,facing]"           (default 32,9,up -- the gym wall)
--   ACNE_LEVELS  comma list of voxel levels (default "3")
--   ACNE_FLAT    comma list of constant-bias values to compare against
--                (default "1" -- what shipped before SLOPE existed)
--   SHOT_DIR     output directory, must exist  (default "shots")
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local SPEED = math.max(1,
    math.floor(tonumber(os.getenv("POKEPORT_SPEED")) or 1))
  local function wait(n) U.wait(n * SPEED) end

  local DIR = os.getenv("SHOT_DIR") or "shots"
  local mapId = os.getenv("ACNE_MAP") or "VIRIDIAN_CITY"
  local sx, sy, facing = (os.getenv("ACNE_SPOT") or "32,9,up")
    :match("^%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%a*)")
  facing = (facing ~= "" and facing) or "up"

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  local V = assert(handle and handle.lib, "DRAMATIC_SHAPE exports missing")
  local ShadowMap = V.require("ShadowMap")
  local Voxel3D = V.require("Voxel3D")
  local Mat4 = V.require("Mat4")

  local levels = {}
  for n in (os.getenv("ACNE_LEVELS") or "3"):gmatch("%d+") do
    levels[#levels + 1] = tonumber(n)
  end
  local flats = {}
  for n in (os.getenv("ACNE_FLAT") or "1"):gmatch("[%d.]+") do
    flats[#flats + 1] = tonumber(n)
  end

  -- ---- what the frustum this run fitted asks of the bias, per face
  local FACES = {
    { "top    +Y", 0, 1, 0 },
    { "south  +Z", 0, 0, 1 },
    { "east   +X", 1, 0, 0 },
    { "west   -X", -1, 0, 0 },
    { "north  -Z", 0, 0, -1 },
    { "roof 45 N", 0, 0.7071, -0.7071 },
    { "roof 45 S", 0, 0.7071, 0.7071 },
  }

  local function report(tag)
    local e = ShadowMap.extent
    if not e then print("[acne] " .. tag .. ": no frustum yet") return end
    local res = ShadowMap.res
    local texX, texY, depth = e[1] / res, e[2] / res, e[3]
    local d = ShadowMap.sunDir()
    local view = Mat4.lookAt({ 0, 0, 0 }, d, { 0, 0, -1 })
    local R = { view[1], view[2], view[3] }
    local Up = { view[5], view[6], view[7] }
    local F = { -view[9], -view[10], -view[11] }
    print(("[acne] %s: res %d  frustum %.0fx%.0f deep %.0f"
           .. "  texel %.2fx%.2f world px  slack %.2f px (stored %.6f)")
      :format(tag, res, e[1], e[2], depth, texX, texY,
              ShadowMap.slack, ShadowMap.bias))
    for _, fc in ipairs(FACES) do
      local n = { fc[2], fc[3], fc[4] }
      local nr = n[1]*R[1] + n[2]*R[2] + n[3]*R[3]
      local nu = n[1]*Up[1] + n[2]*Up[2] + n[3]*Up[3]
      local nf = n[1]*F[1] + n[2]*F[2] + n[3]*F[3]
      -- a face the sun cannot see never samples its own depth, so it
      -- cannot alias -- FACE_SHADE darkens those and the map is moot
      if nf < 0 then
        -- the plane's depth gradient in light space, times the half-texel
        -- the 2x2 filter reaches out on each axis
        local need = 0.5 * (math.abs(nr / nf) * texX
                            + math.abs(nu / nf) * texY)
        print(("[acne]    %s  cos %.3f  slope %.2f  needs %.2f px  %s")
          :format(fc[1], math.abs(nf),
                  math.sqrt((nr/nf)^2 + (nu/nf)^2), need,
                  need > ShadowMap.slack and "<-- ACNE" or "ok"))
      else
        print(("[acne]    %s  unlit (sun behind it)"):format(fc[1]))
      end
    end
  end

  local Zoom = require("src.render.Zoom")
  Zoom.reset()
  local steps = math.floor(tonumber(os.getenv("ACNE_ZOOM")) or 0)
  for _ = 1, math.abs(steps) do
    Zoom.step(steps > 0 and 1 or -1, game.renderer and game.renderer:fitScale())
  end

  Pipelines.setLevel("tiltshift", 0)
  U.teleport(game, mapId, tonumber(sx), tonumber(sy), facing)
  wait(20)
  do
    local vw, vh = game.renderer:worldViewSize()
    print(("[acne] map %s at (%s,%s,%s)  world view %dx%d px  zoom %d")
      :format(mapId, sx, sy, facing, vw, vh, Zoom.offset))
  end

  local shipped = Voxel3D.SHADOW_ALPHA
  local shippedBias, shippedSlope = ShadowMap.BIAS, ShadowMap.SLOPE

  -- ACNE_MATRIX=1: the four corners of (shadows on/off) x (voxel grid
  -- on/off), so a band can be attributed to one of them rather than
  -- guessed at. The grid is the other thing in this pass that draws
  -- regular lines, and at a grazing angle it moires.
  local VoxelGrid = V.require("VoxelGrid")
  local matrix = os.getenv("ACNE_MATRIX") == "1"

  local function shoot(name)
    game.capturePath = ("%s/acne_%s.png"):format(DIR, name)
    wait(4)
  end

  for _, level in ipairs(levels) do
    Pipelines.setLevel("voxel", level)
    wait(30)                      -- outlast the camera tween
    local label = Pipelines.levelLabel("voxel", level) or level
    print(("[acne] --- level %s  shadowsActive=%s")
      :format(label, tostring(Voxel3D.shadowsActive())))
    report("as shipped")
    shoot(("%s_v%s_on"):format(mapId, label))

    if matrix then
      for _, grid in ipairs({ true, false }) do
        VoxelGrid.sync(grid)
        for _, sun in ipairs({ true, false }) do
          Voxel3D.SHADOW_ALPHA = sun and shipped or 0
          wait(8)
          shoot(("%s_v%s_grid%s_sun%s"):format(mapId, label,
            grid and "1" or "0", sun and "1" or "0"))
        end
      end
      Voxel3D.SHADOW_ALPHA = shipped
    end

    -- the sun pass still runs; the main pass simply stops reading it
    Voxel3D.SHADOW_ALPHA = 0
    wait(6)
    shoot(("%s_v%s_off"):format(mapId, label))
    Voxel3D.SHADOW_ALPHA = shipped

    for _, b in ipairs(flats) do
      ShadowMap.BIAS, ShadowMap.SLOPE = b, 0
      ShadowMap.invalidate()      -- force fit() to recompute ShadowMap.bias
      wait(8)
      report(("flat %.1f"):format(b))
      shoot(("%s_v%s_flat%s"):format(mapId, label, tostring(b):gsub("%.", "p")))
    end
    ShadowMap.BIAS, ShadowMap.SLOPE = shippedBias, shippedSlope
    ShadowMap.invalidate()
    wait(6)
  end

  Pipelines.setLevel("voxel", 0)
  wait(5)
  print("[acne] done")
end
