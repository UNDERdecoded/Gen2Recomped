-- Driver: opening the START menu while the bike force-rolls down Cycling
-- Road (#525).  src/world/OverworldController.lua handleInput() used to
-- drop A/START outright while self.player.moving, so a press that landed
-- mid-step and was still held when the step completed vanished -- on
-- Cycling Road's forced roll, where a step re-arms on the single idle
-- frame between steps, that made START a coin flip.  The fix latches a
-- still-held press and acts on it on the landing frame instead
-- (see tests/parity_midstep_buttons.lua for the mechanical half).
--
--   POKEPORT_DRIVER=tests/drivers/cycling_road_menu_bug525_test.lua \
--     POKEPORT_IDENTITY=bug525 POKEPORT_TOUCH=0 POKEPORT_VERSION=red \
--     SHOT_DIR=/tmp/shots love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- Same clear stretch bug255 uses: x=2 is open road from y=8 past y=34.
  local MAP, START_X, START_Y = "ROUTE_17", 2, 20

  game.save.onBike = true
  U.teleport(game, MAP, START_X, START_Y, "down")
  U.wait(15)
  local ow = game.overworld
  check("standing on Cycling Road, on the bike",
        ow.map.id == MAP and game.save.onBike)

  -- hands off the pad: the slope pulls the bike south on its own
  -- (field.forcedMovement.slopeMaps, same mechanism bug255 proved)
  U.wait(20)
  check("the roll is already under way", ow.player.moving == true
        or ow.player.cellY > START_Y)
  U.shot(game, DIR .. "/bug525_1_rolling.png")

  -- press START mid-step and keep it held through the landing frame, the
  -- exact shape a real thumb makes reaching for the menu while rolling
  local pressedMidStep = false
  local guard = 0
  while guard < 60 do
    guard = guard + 1
    if ow.player.moving and ow.player.progress
       and ow.player.progress > 2 and not pressedMidStep then
      table.insert(game.input.pressQueue, "start")
      game.input.state.start = true
      pressedMidStep = true
      U.log("pressed START mid-step at progress", ow.player.progress)
    end
    coroutine.yield()
    if getmetatable(game.stack:top()) ~= nil
       and game.stack:top() ~= ow and pressedMidStep then
      break
    end
  end
  U.wait(2)
  game.input.state.start = false

  local top = game.stack:top()
  U.shot(game, DIR .. "/bug525_2_after_start.png")
  check("START held through the landing opened the start menu",
        top ~= ow and top ~= nil)
  check("the player is not frozen mid-tile (px/py land on a 16px cell)",
        ow.player.px % 16 == 0 and ow.player.py % 16 == 0)

  -- close it and let the roll continue, proving the pull did not get
  -- eaten along with the buffered button
  if top ~= ow then
    while game.stack:top() ~= ow do
      U.tap(game, "b")
      U.wait(10)
    end
  end
  local yBeforeResume = ow.player.cellY
  U.wait(48)
  check("the roll resumes south after closing the menu",
        ow.player.cellY > yBeforeResume)
  U.shot(game, DIR .. "/bug525_3_resumed.png")

  -- park with road left to roll, on the bike, before handing over
  U.teleport(game, MAP, START_X, START_Y, "down")
  U.wait(10)
  game.save.onBike = true

  U.log("On the bike on Cycling Road at (" .. START_X .. "," .. START_Y ..
        "), rolling south hands-off.")
  U.log("Press START right as you see a step land, and again mid-step")
  U.log("while releasing before it lands.  Right: a START you keep pressed")
  U.log("into the landing opens the menu every time, one you let go of")
  U.log("mid-step does nothing (same as standing still).  #525 was the")
  U.log("held case sometimes doing nothing at all, a coin flip on this hill.")

  while true do
    coroutine.yield()
  end
end
