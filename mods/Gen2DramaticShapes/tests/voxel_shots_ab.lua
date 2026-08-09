-- Driver: the pixel-identity gate for performance work.
--
-- Every optimization in this mod's performance pass claims the frame comes
-- out the same. This driver is what makes that claim checkable rather than
-- asserted: it renders a fixed set of scenes -- several maps, indoors and
-- out, at every camera rung, in every display mode -- and writes one PNG
-- per scene. Run it before a change and after it, hash the two directories,
-- and any file whose hash moved is a scene the change altered.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/voxel_shots_ab.lua \
--   SHOT_DIR=<dir> AB_TAG=before lovec.exe .
--
-- knobs (env):
--   SHOT_DIR   output directory (created if missing)   (default "shots/ab")
--   AB_TAG     subdirectory under SHOT_DIR             (default "before")
--   AB_MODES   display modes to sweep, comma list      (default all four)
--
-- DETERMINISM is the whole game here, because a shot that differs for a
-- reason other than the change under test makes the gate useless:
--
--   * the day/night clock is PINNED (an unpinned sky is a different sky
--     every second, and it drives the sun angle and the shadow frustum);
--   * the animated tile slots ride the engine's 60Hz counter, so every
--     scene is reached after the SAME number of frames from the same
--     starting state, and the water is at the same point in its roll;
--   * levels are set through Pipelines.setLevel, never the hotkey, so the
--     run cannot write the player's options;
--   * encounters are stubbed off -- a wild battle would replace the scene
--     the shot is named for.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")
  local OverworldState = require("src.world.OverworldController")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/ab")
    .. "/" .. (os.getenv("AB_TAG") or "before")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[ab] DRAMATIC_SHAPE mod not loaded -- nothing to compare")
    return
  end
  local V = handle.lib
  local DayNight = V.require("DayNight")

  OverworldState.rollEncounter = function() return nil end

  -- NPCs roam on a random timer (src/world/NPC.lua), and LOVE's RNG is
  -- seeded differently every launch -- so two runs of this driver put the
  -- same townsfolk in different places and every shot with a person in it
  -- differs for a reason that has nothing to do with the change under
  -- test. Freeze them: `frozen` is the flag the NPC's own update already
  -- honours, and an NPC mid-step still finishes it, so the settle below
  -- lands on a still scene. They are still POSED and still drawn, so the
  -- billboard, its lean and its shadow are all still under test.
  local NPC = require("src.world.NPC")
  if not NPC.dramaticShapeAbFreeze then
    local inner = NPC.update
    function NPC:update(...)
      self.frozen = true
      return inner(self, ...)
    end
    NPC.dramaticShapeAbFreeze = true
  end
  pcall(love.math.setRandomSeed, 20260730)

  -- Freeze the tile-animation clock, on BOTH routes to it.
  --
  -- TileRenderer.tick consumes WALL-CLOCK dt (so the water rolls at the
  -- same speed on a 60Hz and a 144Hz panel), which means the step a shot
  -- catches depends on how fast the machine got there rather than on
  -- anything the run did. Stubbing tick pins the counter the flat tile
  -- layer reads.
  --
  -- The mod reads the SAME counter but through its own chain
  -- (TerrainAtlas.animFrame): TileRenderer.animFrame if the build exports
  -- one, else the local off tick's upvalues, else -- and this is the trap
  -- -- wall-clock time. A stubbed tick has no upvalues, so stubbing it
  -- ALONE knocks the mod onto the wall-clock fallback and makes the
  -- flowers drift between two otherwise identical runs. Exporting a
  -- constant animFrame takes the first branch and pins that route too.
  local TileRenderer = require("src.render.TileRenderer")
  TileRenderer.tick = function() end
  TileRenderer.animFrame = function() return 0 end

  -- The scenes. Chosen for what each one can BREAK, not for looks:
  --   ROUTE_1          open ground, grass billboards, a long view north --
  --                    the case a shadow-frustum or culling change moves
  --   VIRIDIAN_CITY    buildings, window panes (the glass mask), signs
  --   PALLET_TOWN      the seam with Route 1: neighbour meshes and ring
  --   VIRIDIAN_FOREST  dense round-tree hulls, heavy occlusion
  --   REDS_HOUSE_1F    indoors: no sky, no sun, authored figures
  --   PEWTER_CITY      a second tileset with its own atlas bake
  local SCENES = {
    { id = "ROUTE_1", x = 10, y = 20, face = "up", label = "open" },
    { id = "VIRIDIAN_CITY", x = 20, y = 26, face = "up", label = "town" },
    { id = "PALLET_TOWN", x = 10, y = 2, face = "up", label = "seam" },
    { id = "VIRIDIAN_FOREST", x = 16, y = 24, face = "up", label = "trees" },
    { id = "REDS_HOUSE_1F", x = 4, y = 4, face = "up", label = "indoor" },
    { id = "PEWTER_CITY", x = 16, y = 20, face = "down", label = "pewter" },
  }

  -- OFF is in the list deliberately: a change that speeds the 3D path up
  -- must not have touched the flat one either. Then the three camera
  -- rungs, 75 last because it is the low camera this performance work is
  -- aimed at.
  --
  -- FULL (rung 1) is NOT here, and cannot usefully be. It is a settings
  -- PRESET, not a render path: it sets tilt-shift to maximum, flattens the
  -- world curve, fits the zoom, switches 3D battles on -- and pins DAYTIME
  -- to SYNC and HOLDS it there (main.lua's applyFull / DayNight.forceSync),
  -- which overrides this driver's pinned clock and makes every shot after
  -- it depend on the wall clock. It also persists all of that, so one run's
  -- FULL changes the options the NEXT run starts from. What FULL renders is
  -- 35 degrees with the blur at 3, which rung 3 plus AB_TSHIFT=3 covers
  -- exactly.
  local RUNGS = {}
  for n in (os.getenv("AB_RUNGS") or "0,2,3,5"):gmatch("%d+") do
    RUNGS[#RUNGS + 1] = tonumber(n)
  end

  local TSHIFT = math.floor(tonumber(os.getenv("AB_TSHIFT")) or 0)

  -- AB_SHADOW=0 renders with the sun pass's contribution turned off
  -- (SHADOW_ALPHA 0 short-circuits the lookup in the scene shader). A
  -- bisection tool: when a set of shots will not reproduce, this says
  -- whether what is moving is in the shadow map or somewhere else.
  if os.getenv("AB_SHADOW") == "0" then
    V.require("Voxel3D").SHADOW_ALPHA = 0
  end

  -- PaletteFX.MODES, minus the inverted novelties: `ogred` and `classic`
  -- are the SGB paths this mod bakes an atlas for, `gbc` is the shared
  -- default, and `redpp` is the one that rebakes an atlas PER MAP -- four
  -- genuinely different routes through TerrainAtlas.
  local MODES = {}
  for m in (os.getenv("AB_MODES") or "ogred,classic,gbc,redpp"):gmatch("[^,]+") do
    MODES[#MODES + 1] = m
  end

  -- Two times of day, because half the shader only runs in one of them:
  -- the window lamps, the moon disc and the night tint are all dark-only,
  -- and the glint sweep and the sun disc are day-only.
  local TIMES = { "day", "night" }

  local shots, missed = 0, 0

  -- U.shot's own mkdir is the POSIX one, which cmd.exe does not
  -- understand, and a missing directory makes every capture vanish
  -- silently. Try both spellings once, up front.
  pcall(os.execute, 'mkdir -p "' .. ROOT .. '" 2>/dev/null')
  pcall(os.execute, 'mkdir "' .. ROOT:gsub("/", "\\") .. '" 2>nul')

  -- A capture that always costs the SAME number of frames.
  --
  -- U.shot spins up to 120 frames waiting for the capture to land, which
  -- is right for a screenshot and wrong for this: the animated tile slots
  -- (water rolling, flowers opening) ride the engine's frames-since-boot
  -- counter, so a scene reached after a different number of frames renders
  -- its water at a different point in the roll and the shot differs for a
  -- reason no change caused. A driver resume and a rendered frame are 1:1
  -- here, so the capture lands on the next draw and a fixed budget is both
  -- enough and constant.
  local CAPTURE_FRAMES = 4

  local ChunkMesher = V.require("ChunkMesher")
  local Voxel = V.require("VoxelState")
  local ShadowMap = V.require("ShadowMap")

  -- Wait for the scene to actually BE the scene the shot is named for.
  -- Two things are still in motion after a teleport, and both are timed in
  -- wall-clock seconds rather than frames, so "wait N frames" settles them
  -- by a different amount on every machine and every run:
  --
  --   the build queue -- meshes are built on a per-frame time budget, so a
  --   slower run captures a half-built neighbour;
  --   the camera tween -- Voxel.t runs on dt over TWEEN_TIME, so a shot
  --     taken before it lands is at some arbitrary intermediate pitch.
  --
  -- Both are waited on by their own completion flag, then a short fixed
  -- settle. The variable wait is harmless now that the animation clock is
  -- frozen above -- otherwise it would move the water instead.
  -- and the CAMERA, which is the subtle one. It eases toward the player
  -- over wall-clock dt, so after a fixed wait it has covered a distance
  -- that depends on how fast the machine ran -- and the sun pass is only
  -- redrawn when the camera crosses a quarter-world-pixel (VoxelScene's
  -- shadow signature), so a frame caught mid-ease carries a shadow map
  -- fitted for a slightly different camera than the one it is drawn with.
  -- That is a real and deliberate tolerance in the mod, but it makes the
  -- gate compare two arbitrary points inside it. Waiting for the camera
  -- to stop moving entirely puts every shot at the same steady state.
  local function cameraStill()
    local o = game.overworld
    local c = o and o.camera
    if not c then return true end
    local lx, ly, held = nil, nil, 0
    for _ = 1, 300 do
      if c.x == lx and c.y == ly then
        held = held + 1
        if held >= 10 then return true end
      else
        held = 0
        lx, ly = c.x, c.y
      end
      U.wait(1)
    end
    return false
  end

  local function settleBuild()
    for _ = 1, 900 do
      if ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    for _ = 1, 300 do
      if Voxel.t >= 1 and Voxel.ready and ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    cameraStill()
    -- and then force one final sun pass at the settled camera. The map is
    -- only redrawn when the camera crosses a quarter world pixel, so a
    -- still camera holds whatever was drawn at the moment it last did --
    -- correct to within that tolerance, but fitted from a position that
    -- depends on where the easing happened to be, which differs by a few
    -- hundredths of a pixel between runs and moves every shadow edge by a
    -- shade or two. Forgetting the stamp redraws from the state the shot
    -- is actually taken in, and two runs then agree exactly.
    -- guarded so this driver can also be pointed at a build that predates
    -- the seam, which is exactly what capturing a "before" reference means
    if ShadowMap.forget then ShadowMap.forget() end
    U.wait(20)
  end

  -- AB_TRACE=1 prints the state each shot was taken in. When two runs of
  -- this driver disagree, this is what says which input moved.
  local TRACE = os.getenv("AB_TRACE") == "1"

  local function trace(name)
    if not TRACE then return end
    local o = game.overworld
    local e = ShadowMap.extent or {}
    print(("[ab] %-28s cam=(%.4f,%.4f) player=(%.3f,%.3f) res=%d extent=(%.3f,%.3f,%.3f) KX=%.6f KZ=%.6f angle=%.6f pend=%d")
      :format(name,
              o and o.camera and o.camera.x or -1,
              o and o.camera and o.camera.y or -1,
              o and o.player and o.player.px or -1,
              o and o.player and o.player.py or -1,
              ShadowMap.res or 0,
              e[1] or 0, e[2] or 0, e[3] or 0,
              ShadowMap.KX or 0, ShadowMap.KZ or 0,
              Voxel.angle or 0,
              ChunkMesher.pending()))
  end

  -- AB_SHADOWDUMP=1 also writes the packed depth map itself, into the save
  -- directory. When the scene differs but every input to the sun pass is
  -- identical, the map is the only place left to look.
  local DUMP = os.getenv("AB_SHADOWDUMP") == "1"

  local function dumpShadow(name)
    if not DUMP then return end
    local tex = ShadowMap.texture()
    if not (tex and tex.newImageData) then return end
    pcall(function()
      love.filesystem.createDirectory("ab_shadow")
      tex:newImageData():encode("png", "ab_shadow/" .. name .. ".png")
    end)
  end

  local function capture(name)
    trace(name)
    dumpShadow(name)
    local path = ("%s/%s.png"):format(ROOT, name)
    game.capturePath = path
    U.wait(CAPTURE_FRAMES)
    local f = io.open(path, "rb")
    if f then
      f:close()
      shots = shots + 1
    else
      missed = missed + 1
      print("[ab] capture did not reach disk: " .. path)
    end
  end

  local PaletteFX = require("src.render.PaletteFX")

  local function setMode(mode)
    local known = false
    for _, m in ipairs(PaletteFX.MODES) do
      if m == mode then known = true break end
    end
    if not known then return false end
    return (pcall(PaletteFX.setMode, mode))
  end

  -- A fixed zoom, so the view size every shot is composed at is the same
  -- one. Zoom is persisted, so without this a session that ever ran the
  -- FULL preset (which fits the zoom to the window) leaves a different
  -- view size behind for every later run.
  local Zoom = require("src.render.Zoom")
  pcall(function()
    game.save.options.zoom = 1
    Zoom.applyOptions(game.save.options)
  end)

  for _, mode in ipairs(MODES) do
    if setMode(mode) then
      for _, when in ipairs(TIMES) do
        DayNight.setting:sync(when)
        for _, s in ipairs(SCENES) do
          for _, rung in ipairs(RUNGS) do
            U.teleport(game, s.id, s.x, s.y, s.face)
            Pipelines.setLevel("voxel", rung)
            -- pinned AFTER the voxel rung, because FULL is a preset that
            -- reaches over and sets this row itself (main.lua's applyFull)
            -- and persists it -- so without this, one run's FULL leaks a
            -- blur level into the NEXT run's options.lua and every shot
            -- differs for a reason no code change caused. Sharp by
            -- default: a gaussian smears a one-pixel geometry difference
            -- across the whole frame, which is exactly what a gate meant
            -- to localise differences must not do. AB_TSHIFT=3 runs the
            -- blur path deliberately.
            Pipelines.setLevel("tiltshift", TSHIFT)
            -- Wait for the build queue to drain rather than for a fixed
            -- number of frames. Meshes are built on a per-frame time
            -- budget, so how much of a map exists after N frames is a
            -- property of the MACHINE -- a slower run captures a
            -- half-built neighbour and the shot differs for no reason the
            -- change caused. Draining first, then settling a fixed 40
            -- frames for the camera tween, makes the scene the same
            -- scene everywhere. (Safe now that the animation clock above
            -- is frozen: a variable wait no longer moves the water.)
            settleBuild()
            capture(("%s_%s_%s_v%d"):format(mode, when, s.label, rung))
          end
        end
      end
    else
      print("[ab] display mode " .. mode .. " unavailable, skipped")
    end
  end

  print(("[ab] %d shots into %s (%d failed to reach disk)")
    :format(shots, ROOT, missed))
end
