-- Driver: #187 S.S. Anne cabin door entry.  Entering a room from the
-- corridor should land one tile south of the door (pokered
-- PlayerStepOutFromDoor), not leave the player on the door tile.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- SS_ANNE_1F warp at (31,8) -> SS_ANNE_1F_ROOMS (rightmost cabin)
  U.teleport(game, "SS_ANNE_1F", 31, 9, "up")
  U.shot(game, DIR .. "/anne_0_before_enter.png")
  local ow = game.overworld
  U.log("before map:", ow.map.id, "pos:", ow.player.cellX, ow.player.cellY,
        "facing:", ow.player.facing)

  U.hold(game, "up", 20)
  for _ = 1, 90 do
    U.wait(1)
    if ow.map.id == "SS_ANNE_1F_ROOMS" and not ow.transitioning
       and #ow.scriptMoves == 0 and not ow.player.moving then
      break
    end
  end
  U.wait(8)
  U.shot(game, DIR .. "/anne_1_after_enter.png")
  U.log("after map:", ow.map.id, "pos:", ow.player.cellX, ow.player.cellY,
        "facing:", ow.player.facing,
        "onDoor:", tostring(ow.map:isWarpTileCell(ow.player.cellX, ow.player.cellY)))
end
