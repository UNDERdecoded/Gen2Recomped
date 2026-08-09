-- Scratch driver: HORDE MODE, from the code to the card.
--
-- Enters the konami code the way a player does -- as Game Boy button
-- edges on the fixed step, which is the same path the pad, the touch
-- overlay and the VR controllers take -- then photographs the intro
-- banner, the darkened sky, the gun at the hip and down the sights, a
-- wave mid-chase, the muzzle flash, the reload, a run through a door with
-- the crowd behind, and the GAME OVER card. Finishes by pressing A and
-- checking that everything the mode changed came back.
--
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/horde_shots.lua \
--   SHOT_DIR=.scratchpad/horde lovec.exe .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pipelines = require("src.render.Pipelines")

  local ROOT = (os.getenv("SHOT_DIR") or "shots/horde")

  local handle = game.mods.exports["DRAMATIC_SHAPE"]
  if not (handle and handle.lib) then
    print("[horde] DRAMATIC_SHAPE mod not loaded")
    return love.event.quit()
  end
  local V = handle.lib
  local Horde = V.require("Horde")
  local Mobs = V.require("HordeMobs")
  local Gun = V.require("HordeGun")
  local FirstPerson = V.require("FirstPerson")
  local ChunkMesher = V.require("ChunkMesher")
  local Voxel = V.require("VoxelState")

  pcall(os.execute, 'mkdir -p "' .. ROOT .. '" 2>/dev/null')
  pcall(os.execute, 'mkdir "' .. ROOT:gsub("/", "\\") .. '" 2>nul')

  local TileRenderer = require("src.render.TileRenderer")
  TileRenderer.tick = function() end
  TileRenderer.animFrame = function() return 0 end

  local shots = 0
  local function shot(name)
    if U.shot(game, ("%s/%s.png"):format(ROOT, name)) then
      shots = shots + 1
    end
  end

  local function settle(frames)
    for _ = 1, 900 do
      if ChunkMesher.pending() == 0 then break end
      U.wait(1)
    end
    U.wait(frames or 30)
  end

  -- ------- the code, entered as edges
  --
  -- One button per fixed step, exactly as a device delivers them: the
  -- driver writes the queue Input:step is about to drain, which is the
  -- same array a keypress lands in.
  --
  -- Each one is RELEASED after. A synthetic inject has no source behind
  -- it, so Input:step latches it held (see the branch there) and nothing
  -- ever lets go -- which leaves all four directions down for the rest of
  -- the run and the player walking into a wall forever. U.tap does the
  -- same clear for the same reason.
  local function pressCode()
    local KONAMI = { "up", "up", "down", "down",
                     "left", "right", "left", "right", "b", "a" }
    for _, btn in ipairs(KONAMI) do
      table.insert(game.input.pressQueue, btn)
      U.wait(2)
      game.input.state[btn] = false
    end
  end

  -- ------- before
  U.teleport(game, "PALLET_TOWN", 13, 14, "down")
  Pipelines.setLevel("voxel", 3)          -- the 35-degree diorama
  Pipelines.setLevel("tiltshift", 0)
  settle(40)
  local ow = game.stack:top()
  local p = ow.player
  local was = {
    map = ow.map.id, cellX = p.cellX, cellY = p.cellY, facing = p.facing,
    level = Pipelines.level("voxel"),
    npcs = #ow.npcs,
  }
  shot("00_before")
  print(("[horde] before: %s (%d,%d) rung %d, %d npcs")
        :format(was.map, was.cellX, was.cellY, was.level, was.npcs))

  -- ------- the code lands
  pressCode()
  U.wait(4)
  print("[horde] active: " .. tostring(Horde.active)
        .. "  state: " .. tostring(Horde.state))
  if not Horde.active then
    print("[horde] the code did not take -- nothing else here can run")
    return love.event.quit()
  end
  U.wait(20)
  shot("01_darkness_approaches")          -- the banner, over the darkening

  -- and the same announcement at the zoom that used to run it off both
  -- edges of the screen: it has to wrap (or shrink) rather than overflow
  local Zoom = require("src.render.Zoom")
  pcall(function()
    game.save.options.zoom = 3
    Zoom.applyOptions(game.save.options)
  end)
  Horde.banner("A DARKNESS APPROACHES", 2.6)
  U.wait(30)
  shot("01b_banner_zoomed")
  pcall(function()
    game.save.options.zoom = 0
    Zoom.applyOptions(game.save.options)
  end)
  U.wait(10)
  print(("[horde] rung is now %d (%s)"):format(Pipelines.level("voxel"),
        Pipelines.levelLabel("voxel")))

  -- the rung must be locked: the key, SELECT and the VR click all call the
  -- one function this refuses through
  local Game = require("src.core.Game")
  Game.keypressed(game, "3")
  print(("[horde] after pressing 3 the rung is %d -- locked: %s")
        :format(Pipelines.level("voxel"),
                tostring(Pipelines.level("voxel") == Voxel.FP_LEVEL)))

  -- ------- the first wave
  for _ = 1, 900 do
    if Horde.state == "active" and #Horde.session.mobs >= 5 then break end
    U.wait(1)
  end
  FirstPerson.yaw = math.pi                -- look north up the street
  U.wait(30)
  shot("02_wave_hip")
  print(("[horde] wave %d, %d mobs standing")
        :format(Horde.session.wave, #Horde.session.mobs))

  -- ------- START asks the way out
  --
  -- The same GB button the pad's START, the keyboard's ESCAPE and the
  -- touch overlay all press, so this one tap covers every device except
  -- the VR stick click (which calls the same Horde.askExit).
  U.tap(game, "start")
  U.wait(10)
  local prompt = game.stack:top()
  print(("[horde] START opened a prompt: %s (still active: %s)")
        :format(tostring(prompt ~= game.overworld), tostring(Horde.active)))
  shot("02b_exit_prompt")
  -- NO, and back to the fight
  U.tap(game, "b")
  U.wait(10)
  print(("[horde] answered NO: back on the overworld %s, active %s")
        :format(tostring(game.stack:top() == game.overworld),
                tostring(Horde.active)))

  -- ------- the sights
  Gun.setAds(true)
  U.wait(20)
  shot("03_ads")
  Gun.setAds(false)
  U.wait(14)

  -- ------- the shot
  --
  -- Aimed deliberately at the nearest mob rather than fired into the
  -- street: what is being checked is that the ray finds a body, that the
  -- body dies, and that the kill is worth something.
  local function aimAtNearest()
    local best, bestD
    for _, e in ipairs(Horde.session.mobs) do
      local dx = (e.npc.px + 8) - (p.px + 8)
      local dz = (e.npc.py + 8) - (p.py + 8)
      local d = dx * dx + dz * dz
      if not bestD or d < bestD then best, bestD = e, d end
    end
    if not best then return nil end
    local dx = (best.npc.px + 8) - (p.px + 8)
    local dz = (best.npc.py + 8) - (p.py + 8)
    FirstPerson.yaw = math.atan2(dx, dz)
    FirstPerson.pitch = 0
    return best, math.sqrt(bestD)
  end

  local scoreWas, killsWas = Horde.session.score, Horde.session.kills
  local target, range = aimAtNearest()
  print(("[horde] aiming at a mob %s px away, yaw %.2f")
        :format(range and ("%.0f"):format(range) or "?", FirstPerson.yaw))
  U.wait(6)
  Gun.fire()
  U.wait(1)
  shot("04_muzzle_flash")
  -- a mob takes more than one round as the waves stack; keep firing at
  -- whatever is nearest until something dies or the magazine is out
  for _ = 1, 7 do
    if Horde.session.kills > killsWas then break end
    U.wait(16)
    aimAtNearest()
    Gun.fire()
  end
  U.wait(20)
  print(("[horde] fired: ammo %d, score %d -> %d, kills %d -> %d")
        :format(select(1, Gun.ammo()), scoreWas, Horde.session.score,
                killsWas, Horde.session.kills))

  -- ------- the reload, caught mid-dip
  for _ = 1, 8 do
    Gun.fire()
    U.wait(12)
  end
  Gun.reload()
  U.wait(45)
  shot("05_reloading")
  print("[horde] reloading: " .. tostring(select(3, Gun.ammo())))
  for _ = 1, 200 do
    if not select(3, Gun.ammo()) then break end
    U.wait(1)
  end
  print(("[horde] reloaded to %d"):format(select(1, Gun.ammo())))

  -- ------- through a door, with the crowd behind
  local before = #Horde.session.mobs
  U.teleport(game, "REDS_HOUSE_1F", 3, 6, "down")
  settle(60)
  for _ = 1, 400 do
    if #Horde.session.mobs > 0 then break end
    U.wait(1)
  end
  U.wait(60)
  shot("06_indoors_followed")
  print(("[horde] indoors: %d mobs followed (was %d outside)")
        :format(#Horde.session.mobs, before))

  -- ------- the end
  --
  -- Drained rather than played out, so the driver finishes in seconds and
  -- the card is photographed from the same path a real death takes.
  Horde.session.hp = 1
  Horde.session.hurtCooldown = 0
  Horde.damage(50)
  for _ = 1, 400 do
    if Horde.state == "gameover" then break end
    U.wait(1)
  end
  U.wait(40)
  shot("07_game_over")
  print(("[horde] game over at score %d, wave %d, %d kills")
        :format(Horde.session and Horde.session.score or -1,
                Horde.session and Horde.session.wave or -1,
                Horde.session and Horde.session.kills or -1))

  -- ------- and back
  U.tap(game, "a")
  for _ = 1, 600 do
    if not Horde.active and not game.stack:top().transitioning then break end
    U.wait(1)
  end
  settle(60)
  local now = game.stack:top()
  local np = now.player
  print(("[horde] restored: %s (%d,%d) facing %s, rung %d, %d npcs")
        :format(now.map.id, np.cellX, np.cellY, np.facing,
                Pipelines.level("voxel"), #now.npcs))
  print(("[horde] matches start: map %s cell %s facing %s rung %s npcs %s")
        :format(tostring(now.map.id == was.map),
                tostring(np.cellX == was.cellX and np.cellY == was.cellY),
                tostring(np.facing == was.facing),
                tostring(Pipelines.level("voxel") == was.level),
                tostring(#now.npcs == was.npcs)))
  -- nothing of the mode may be left on any map
  local left = 0
  for _, def in pairs(game.data.maps) do
    for _, obj in ipairs(def.objects or {}) do
      if obj.hordeMob then left = left + 1 end
    end
  end
  print(("[horde] horde objects left behind: %d"):format(left))
  shot("08_after")

  -- ------- and out the other door
  --
  -- The same restore, reached the other way: enter the code again and
  -- leave through START -> YES rather than by dying. This is the path a
  -- player who just wants their game back actually takes.
  pressCode()
  U.wait(6)
  if not Horde.active then
    print("[horde] second activation refused -- the exit path is untested")
    print(("[horde] %d shots into %s"):format(shots, ROOT))
    return love.event.quit()
  end
  for _ = 1, 400 do
    if Horde.state == "active" then break end
    U.wait(1)
  end
  U.tap(game, "start")
  U.wait(10)
  U.tap(game, "up")            -- NO -> YES
  U.wait(6)
  shot("09_exit_yes")
  U.tap(game, "a")
  for _ = 1, 600 do
    if not Horde.active and not game.stack:top().transitioning then break end
    U.wait(1)
  end
  settle(60)
  local out = game.stack:top()
  local op = out.player
  print(("[horde] exited via START/YES: active %s, %s (%d,%d) facing %s, rung %d")
        :format(tostring(Horde.active), out.map.id, op.cellX, op.cellY,
                op.facing, Pipelines.level("voxel")))
  print(("[horde] matches start: map %s cell %s facing %s rung %s npcs %s")
        :format(tostring(out.map.id == was.map),
                tostring(op.cellX == was.cellX and op.cellY == was.cellY),
                tostring(op.facing == was.facing),
                tostring(Pipelines.level("voxel") == was.level),
                tostring(#out.npcs == was.npcs)))
  local left2 = 0
  for _, def in pairs(game.data.maps) do
    for _, obj in ipairs(def.objects or {}) do
      if obj.hordeMob then left2 = left2 + 1 end
    end
  end
  print(("[horde] horde objects left behind: %d"):format(left2))

  print(("[horde] %d shots into %s"):format(shots, ROOT))
  love.event.quit()
end
