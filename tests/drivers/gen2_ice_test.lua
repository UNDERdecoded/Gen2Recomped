-- Mahogany Gym's floor is ice.  CheckIceTile (00:$1749) is
-- `cp $23 / ret z / cp $2B / ret z / scf / ret`, and DoPlayerMovement.TryStep
-- turns any step that lands on one of those collision classes into STEP_ICE:
-- the walk repeats in the same direction, ignoring the d-pad, until the player
-- leaves the ice or the next cell is blocked.  The port used to treat ice as
-- ordinary floor, so the whole puzzle was walkable one tile at a time.
local U = require("tests.drivers.util")

local function settle(ow)
  local p = ow.player
  for _ = 1, 400 do
    U.wait(1)
    if not p.moving and not ow.iceSlide then return end
  end
end

return function(game)
  local pass, fail = 0, 0
  local function check(name, ok)
    if ok then pass = pass + 1 else fail = fail + 1; U.log("FAIL " .. name) end
  end

  U.newGame(game)
  U.wait(10)
  U.teleport(game, "MAHOGANY_GYM", 4, 14, "up")
  U.wait(20)
  local ow = game.stack:top()
  local p = ow.player
  check("in Mahogany Gym", ow.map and ow.map.id == "MAHOGANY_GYM")

  local ice = 0
  for y = 0, 17 do
    for x = 0, 9 do
      if ow:gen2IsIce(x, y) then ice = ice + 1 end
    end
  end
  check("the gym floor carries ice collision (" .. ice .. " cells)", ice > 80)
  check("the entrance corridor is bare floor", not ow:gen2IsIce(4, 14))
  check("the sheet starts one cell north", ow:gen2IsIce(4, 13))

  -- one press onto the sheet slides all the way to the far side
  U.hold(game, "up", 8)
  settle(ow)
  check("one press slid the player up the sheet (14 -> " .. p.cellY .. ")",
        p.cellX == 4 and p.cellY == 7)
  check("the slide ended off the ice", not ow:gen2IsIce(p.cellX, p.cellY))
  check("the slide released the player", ow.iceSlide == nil and not p.moving)

  -- and a slide into a wall stops on the last ice cell instead of clipping
  U.teleport(game, "MAHOGANY_GYM", 5, 11, "left")
  U.wait(20)
  ow = game.stack:top()
  p = ow.player
  check("x=1 on that row is solid", not ow.map:isWalkableCell(1, 11))
  U.hold(game, "left", 8)
  settle(ow)
  check("the slide stops against the wall (x=" .. p.cellX .. ")",
        p.cellX == 2 and p.cellY == 11)
  check("...still on a walkable cell",
        ow.map:isWalkableCell(p.cellX, p.cellY))
  check("...and lets go of the player", ow.iceSlide == nil)

  -- a single step that never lands on ice must stay a single step
  U.teleport(game, "MAHOGANY_GYM", 4, 16, "up")
  U.wait(20)
  ow = game.stack:top()
  p = ow.player
  U.hold(game, "up", 8)
  settle(ow)
  check("bare floor still walks one cell at a time",
        p.cellX == 4 and p.cellY == 15)

  -- surfing never slides (DoPlayerMovement.TrySurf bypasses .TryStep)
  U.teleport(game, "MAHOGANY_GYM", 4, 13, "up")
  U.wait(20)
  ow = game.stack:top()
  ow.player.surfing = true
  check("ice never arms while surfing", ow:checkGen2Ice() == false)
  ow.player.surfing = false

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
end
