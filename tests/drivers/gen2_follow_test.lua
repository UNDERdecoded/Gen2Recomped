-- Driver: Gen 2 `follow` spacing.
--
-- ApplyMovementToFollower (1:$5457) pushes every step the LEADER takes onto
-- wFollowMovementQueue, and GetFollowerNextMovementIndex (1:$5485) pops it
-- one beat later, so the follower retraces the leader's exact path one tile
-- behind.  The port used to walk both at once, in the same direction, which
-- put the player alongside the Cherrygrove guide instead of behind him.
--
--   POKEPORT_VERSION=gold \
--     POKEPORT_DRIVER=tests/drivers/gen2_follow_test.lua love .
return function(game)
  local U = require("tests.drivers.util")
  local pass, fail = 0, 0
  local function ck(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
  end

  U.newGame(game)
  U.wait(30)
  U.teleport(game, "CHERRYGROVE_CITY", 20, 10, "down")
  U.wait(30)

  local ow = game.overworld
  local leader = ow:npcByIndex(1)
  ck("Cherrygrove has an object to lead with", leader ~= nil)
  if not leader then
    U.log("RESULT FAIL (0 pass, 1 fail)")
    love.event.quit()
    return
  end

  -- stand the leader one tile west of the player, both idle
  leader.cellX, leader.cellY = 19, 10
  leader.px, leader.py = 19 * 16, 10 * 16
  leader.moving = false
  leader.targetX, leader.targetY = nil, nil

  game.data.map_scripts.movements._TEST_FOLLOW = {
    { "step_left" }, { "step_left" }, { "step_up" }, { "step_up" },
  }
  ow.runner:run({
    { "g2_follow", 2, 0 },              -- follow <object 2>, PLAYER
    { "g2_move", 2, "_TEST_FOLLOW" },
  })

  -- the pair must never come to rest on the same cell and never drift more
  -- than one tile apart while the walk runs (cells are sampled between
  -- steps: mid-step the two entities are both interpolating, and the
  -- follower retires its step a frame before the leader does)
  local sameCell, tooFar, sawMove = false, false, false
  for _ = 1, 200 do
    U.wait(1)
    local dx = math.abs(leader.cellX - ow.player.cellX)
    local dy = math.abs(leader.cellY - ow.player.cellY)
    if dx + dy == 0 and not leader.moving and not ow.player.moving then
      sameCell = true
    end
    if dx + dy > 1 then tooFar = true end
    if leader.cellX ~= 19 or leader.cellY ~= 10 then sawMove = true end
    if not ow.runner:isRunning() then break end
  end
  U.wait(20)

  ck("the leader actually walked", sawMove)
  ck("the two never share a cell", not sameCell)
  ck("the follower never falls more than one tile behind", not tooFar)
  U.log("final leader", leader.cellX, leader.cellY,
        "player", ow.player.cellX, ow.player.cellY)
  ck("the leader finished the whole four-step path",
     leader.cellX == 17 and leader.cellY == 8)
  -- one behind on the path, NOT alongside: alongside would be (17,8)+(18,8)
  ck("the player ends one tile behind, on the leader's last tile",
     ow.player.cellX == 17 and ow.player.cellY == 9)

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit()
end
