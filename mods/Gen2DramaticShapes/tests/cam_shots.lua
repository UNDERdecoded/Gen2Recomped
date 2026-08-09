-- Scratch driver: the cameras the player steers -- the third-person boom's
-- zoom, and the battle shot's orbit, climb and lens, including the far
-- stops (side-on, 45 degrees up) and what BACK SPRITES takes away.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/cam_shots.lua \
--   SHOT_DIR=.scratchpad/camshots lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/cam")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[cam] DRAMATIC_SHAPE mod not loaded")
    return love.event.quit()
  end
  local V = handle.lib
  local FirstPerson = V.require("FirstPerson")
  local ThirdPerson = V.require("ThirdPerson")
  local BattleCam = V.require("BattleCam")
  local OverworldBattle = V.require("OverworldBattle")
  local ChunkMesher = V.require("ChunkMesher")
  local Voxel = V.require("VoxelState")
  local DayNight = V.require("DayNight")

  pcall(os.execute, 'mkdir -p "' .. ROOT .. '" 2>/dev/null')
  pcall(os.execute, 'mkdir "' .. ROOT:gsub("/", "\\") .. '" 2>nul')

  require("src.world.OverworldController").rollEncounter = function() return nil end
  local TileRenderer = require("src.render.TileRenderer")
  TileRenderer.tick = function() end
  -- The flower's animation frame, pinned per shot rather than left to the
  -- clock: the mesh spans the union of every frame and each one is cut back
  -- out in texture space, so a gap that only opens on frame 2 is invisible
  -- to a driver that always photographs frame 0 -- which is exactly how the
  -- first cut of the closed sides shipped looking correct.
  local ANIM = { frame = 0 }
  TileRenderer.animFrame = function() return ANIM.frame end
  DayNight.setting:sync("day")

  local function settle()
    for _ = 1, 900 do
      if ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    U.wait(40)
  end

  local shots = 0
  local function shot(name)
    if U.shot(game, ("%s/%s.png"):format(ROOT, name)) then
      shots = shots + 1
    end
  end

  -- ------- the boom's zoom
  U.teleport(game, "PALLET_TOWN", 13, 14, "down")
  Pipelines.setLevel("voxel", Voxel.TP_LEVEL)
  Pipelines.setLevel("tiltshift", 0)
  settle()
  for _ = 1, 200 do
    if FirstPerson.blend >= 1 then break end
    U.wait(1)
  end
  FirstPerson.yaw = math.pi
  U.wait(20)
  for _, z in ipairs({ "min", "default", "max" }) do
    ThirdPerson.zoomGoal = (z == "min" and ThirdPerson.ZOOM_MIN)
                           or (z == "max" and ThirdPerson.ZOOM_MAX) or 1
    for _ = 1, 90 do U.wait(1) end
    print(("[cam] boom %-8s zoom %.2f  len %.1f"):format(z, ThirdPerson.zoom,
                                                        ThirdPerson.len))
    shot("boom_" .. z)
  end
  ThirdPerson.zoomGoal = 1
  U.wait(60)

  -- ------- the standees' closed sides
  --
  -- Pallet's flower beds and Route 1's tall grass, from a low camera close
  -- in -- the angle that showed the slabs were open at the ends of every
  -- run and let you see straight through them.
  ThirdPerson.zoomGoal = ThirdPerson.ZOOM_MIN
  for _, s in ipairs({
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = math.pi,
      pitch = math.rad(6), label = "flowers_low" },
    { map = "PALLET_TOWN", x = 13, y = 14, yaw = 3 * math.pi / 4,
      pitch = math.rad(30), label = "flowers_angled" },
    { map = "ROUTE_1", x = 10, y = 28, yaw = math.pi,
      pitch = math.rad(8), label = "grass_low" },
  }) do
    U.teleport(game, s.map, s.x, s.y, "down")
    settle()
    FirstPerson.yaw, FirstPerson.pitch = s.yaw, s.pitch
    U.wait(60)
    -- EVERY animation frame, because a gap the union closed and a frame
    -- reopens is only visible on that frame
    for f = 0, 3 do
      ANIM.frame = f
      U.wait(6)
      shot(("%s_f%d"):format(s.label, f))
    end
    ANIM.frame = 0
  end
  ThirdPerson.zoomGoal = 1
  U.wait(60)

  -- ------- the battle shot
  --
  -- Staged the way the game stages one, then steered to each stop with the
  -- module's own entry points -- the same ones the wheel, the stick and a
  -- drag reach.
  Pipelines.setLevel("voxel", 4)
  U.wait(60)
  do
    -- Somebody to fight WITH: a fresh driver save has an empty party, and
    -- a trainer battle with nobody to send out ends on the frame it starts
    -- -- which is what made every steered shot below sample a dead session.
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = {
      Pokemon.new(game.data, "CHARIZARD", 45),
      Pokemon.new(game.data, "PIKACHU", 40),
    }
    game.save.player.name = "RED"
    local BattleState = require("src.battle.BattleState")
    local class = next(game.data.trainers)
    local battle = BattleState.newTrainer(game, class, 1)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
  end
  -- The wipe, then just enough of the send-out chatter to get both mons
  -- standing on the arena -- and NOT one tap more. A is also FIGHT and then
  -- the first move, so tapping past the intro starts an exchange and the
  -- fight can be over before the camera has been steered anywhere.
  U.wait(70)
  for _ = 1, 40 do
    if OverworldBattle.shot() then break end
    U.tap(game, "a")
    U.wait(10)
  end
  U.wait(60)
  print(("[cam] staged: arena %s  shot %s  top %s")
        :format(tostring(OverworldBattle.arena() ~= nil),
                tostring(OverworldBattle.shot() ~= nil),
                tostring(game.stack:top() ~= game.overworld)))
  if not OverworldBattle.shot() then
    print("[cam] no staged battle -- skipping the battle shots")
    print(("[cam] %d shots into %s"):format(shots, ROOT))
    return love.event.quit()
  end

  local function settleCam(label)
    for _ = 1, 120 do U.wait(1) end
    print(("[cam] battle %-20s orbit %.2f/%.2f  pitch %.2f/%.2f  "
           .. "zoom %.2f/%.2f  steerable %s  live %s")
          :format(label, BattleCam.orbit, BattleCam.orbitGoal,
                  BattleCam.pitch, BattleCam.pitchGoal,
                  BattleCam.zoom, BattleCam.zoomGoal,
                  tostring(BattleCam.steerable),
                  tostring(OverworldBattle.shot() ~= nil)))
    shot("battle_" .. label)
  end

  BattleCam.recentre()
  settleCam("home")

  -- right to the stop: this must land SQUARE to the arena's axis
  BattleCam.dragOrbit(10)
  settleCam("side_on")

  -- and there is nothing to the left of home
  BattleCam.recentre()
  BattleCam.dragOrbit(-10)
  settleCam("left_stop")

  -- up to the stop, and refusing to go below home
  BattleCam.recentre()
  BattleCam.dragPitch(10)
  settleCam("high")
  BattleCam.recentre()
  BattleCam.dragPitch(-10)
  settleCam("low_stop")

  -- the lens at both ends
  BattleCam.recentre()
  for _ = 1, 40 do BattleCam.stepZoom(-1) end
  settleCam("zoom_in")
  BattleCam.recentre()
  for _ = 1, 40 do BattleCam.stepZoom(1) end
  settleCam("zoom_out")

  -- everything at once, which is the shot a player would actually build
  BattleCam.recentre()
  BattleCam.dragOrbit(0.55)
  BattleCam.dragPitch(0.5)
  for _ = 1, 4 do BattleCam.stepZoom(-1) end
  settleCam("steered")

  -- What BACK SPRITES takes away is NOT shot here: the flag it works
  -- through is re-derived from the row every frame
  -- (OverworldBattle.update), so a driver cannot hold it down for the
  -- hundred-odd frames a settled shot needs, and a picture that claimed to
  -- show a locked camera while the camera was in fact free would be worse
  -- than no picture. The suite asserts it instead, on both axes and the
  -- lens, and on the RIG as well as on the inputs.
  BattleCam.recentre()

  print(("[cam] %d shots into %s"):format(shots, ROOT))
  love.event.quit()
end
