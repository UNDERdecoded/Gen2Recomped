-- Driver: prove out the voxel sun pass.
--
-- Reports whether the shadow map can run, dumps the map itself as a PNG
-- (the packed depth reads as a red/green gradient -- what matters is that
-- it is populated and the right way up), and screenshots a stand point at
-- every camera pitch so the cast shadows can be eyeballed against the flat
-- ground truth.
--
--   POKEPORT_DRIVER=mods/DRAMATIC_SHAPE/tests/voxel_shadow_probe.lua lovec .
--
-- knobs (env):
--   SHADOW_MAP    map id                        (default PALLET_TOWN)
--   SHADOW_SPOT   "x,y[,facing]"                (default 5,6,down)
--   SHOT_DIR      output directory, must exist  (default "shots")
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local SPEED = math.max(1,
    math.floor(tonumber(os.getenv("POKEPORT_SPEED")) or 1))
  local function wait(n) U.wait(n * SPEED) end

  local DIR = os.getenv("SHOT_DIR") or "shots"
  local mapId = os.getenv("SHADOW_MAP") or "PALLET_TOWN"
  local sx, sy, facing = (os.getenv("SHADOW_SPOT") or "5,6,down")
    :match("^%s*(%d+)%s*,%s*(%d+)%s*,?%s*(%a*)")
  facing = (facing ~= "" and facing) or "down"

  -- reach the mod's lib namespace the way a companion mod would
  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  local V = handle and handle.lib
  assert(V, "DRAMATIC_SHAPE exports not reachable")
  local ShadowMap = V.require("ShadowMap")
  local Voxel3D = V.require("Voxel3D")
  local VoxelGrid = V.require("VoxelGrid")

  -- SHADOW_GRID=1 forces the voxel wireframe on for the run, and
  -- SHADOW_CURVE=n the curved-world rung -- neither touches the player's
  -- persisted setting
  if os.getenv("SHADOW_GRID") == "1" then
    VoxelGrid.sync(true)
    print("[shadow] voxel grid forced on; shader built="
          .. tostring(Voxel3D.shader(true) ~= nil))
  end
  local WorldCurve = V.require("WorldCurve")
  local curve = math.floor(tonumber(os.getenv("SHADOW_CURVE")) or 0)
  if curve > 0 then
    WorldCurve.sync(curve)
    print(("[shadow] world curve rung %d (amount %.2f)")
      :format(curve, WorldCurve.AMOUNTS[curve + 1] or 0))
  end

  -- SHADOW_SUN="kx,kz" retunes the bearing for one run, so a sun can be
  -- compared against another without an edit-rebuild cycle
  local skx, skz = (os.getenv("SHADOW_SUN") or ""):match("^(-?[%d.]+),(-?[%d.]+)$")
  if skx then
    ShadowMap.KX, ShadowMap.KZ = tonumber(skx), tonumber(skz)
    Voxel3D.SHADOW_KX, Voxel3D.SHADOW_KZ = ShadowMap.KX, ShadowMap.KZ
  end

  print(("[shadow] sun shear kx=%.2f kz=%.2f  alpha=%.2f  res=%d")
    :format(ShadowMap.KX, ShadowMap.KZ, Voxel3D.SHADOW_ALPHA, ShadowMap.res))

  -- pin the zoom: the world view size drives the light frustum, and a run
  -- that inherits whatever the player left in options.lua is not
  -- comparable with the one before it
  local Zoom = require("src.render.Zoom")
  Zoom.reset()
  local steps = math.floor(tonumber(os.getenv("SHADOW_ZOOM")) or 0)
  for _ = 1, math.abs(steps) do
    Zoom.step(steps > 0 and 1 or -1, game.renderer and game.renderer:fitScale())
  end

  Pipelines.setLevel("tiltshift", 0)
  U.teleport(game, mapId, tonumber(sx), tonumber(sy), facing)
  wait(20)
  do
    local vw, vh = game.renderer:worldViewSize()
    print(("[shadow] world view %dx%d px, zoom offset %d")
      :format(vw, vh, Zoom.offset))
  end

  Pipelines.setLevel("voxel", 0)
  wait(25)
  game.capturePath = ("%s/shadow_%s_flat.png"):format(DIR, mapId)
  wait(3)

  print("[shadow] available=" .. tostring(ShadowMap.available()))

  for level = 1, Pipelines.maxLevel("voxel") do
    Pipelines.setLevel("voxel", level)
    wait(30)                      -- outlast the 0.25s camera tween
    local label = Pipelines.levelLabel("voxel", level) or level
    game.capturePath = ("%s/shadow_%s_v%s.png"):format(DIR, mapId, label)
    wait(3)
    local e = ShadowMap.extent or { 0, 0, 0 }
    print(("[shadow] level %s active=%s bias=%.6f frustum=%.0fx%.0f deep %.0f"
           .. " (%.2f world px/texel)")
      :format(label, tostring(ShadowMap.active()), ShadowMap.bias,
              e[1], e[2], e[3], e[1] / ShadowMap.res))
  end

  -- the map itself: packed depth, so red is the high byte of "how far the
  -- sun got". A blank (all-white) dump means nothing was drawn into it.
  local canvas = ShadowMap.texture()
  if canvas and canvas.newImageData then
    local ok, err = pcall(function()
      local data = canvas:newImageData()
      local w, h = data:getDimensions()
      local hit = 0
      for y = 0, h - 1, 8 do
        for x = 0, w - 1, 8 do
          local r = data:getPixel(x, y)
          if r < 0.999 then hit = hit + 1 end
        end
      end
      print(("[shadow] map %dx%d, %d/%d sampled texels written")
        :format(w, h, hit, (w / 8) * (h / 8)))
      data:encode("png", "shadowmap.png")
    end)
    print("[shadow] dump " .. (ok and "ok (save dir/shadowmap.png)"
                               or tostring(err)))
  end

  Pipelines.setLevel("voxel", 0)
  wait(5)
  print("[shadow] done")
end
