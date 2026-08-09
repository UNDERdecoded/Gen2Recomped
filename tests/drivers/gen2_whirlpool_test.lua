-- Surfing into an uncleared whirlpool (issue: "Whirlpool tiles don't make you
-- spin and send you back in the direction you came").
--
-- DoPlayerMovement.CheckTile (04:$40B7) runs CheckWhirlpoolTile (00:$1751)
-- and returns PLAYERMOVEMENT_FORCE_TURN (3).  PlayerMovementPointers.force_turn
-- (25:$6A53) queues Script_ForcedMovement (04:$6904), whose four movement lists
-- (04:$692B, `4F 10 24 4F 10 00 47` and its three rotations) are
--
--   up    -> step_dig 16, turn_in_down,  step_dig 16, turn_head_down
--   down  -> step_dig 16, turn_in_up,    step_dig 16, turn_head_up
--   right -> step_dig 16, turn_in_left,  step_dig 16, turn_head_left
--   left  -> step_dig 16, turn_in_right, step_dig 16, turn_head_right
--
-- i.e. the player never changes cell: they whirl for two sixteen-frame beats
-- and are left facing back the way they came.  The port arms it off the tile
-- being surfed INTO -- $24/$2C read as plain water in CollisionPermissionTable
-- (3E:$74BE -> $11, low nibble $1), so letting the player stand on one would
-- make every direction hit .CheckTile forever.
local U = dofile("tests/drivers/util.lua")

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1 U.log("FAIL " .. name) end
end

return function(game)
  U.newGame(game)
  U.wait(20)

  -- Route 41's eddy is at cell 22,12 (collision $24); 22,13 is plain water.
  U.teleport(game, "ROUTE41", 22, 13)
  U.wait(20)
  local ow = game.stack:top()
  check("on Route 41", ow.map and ow.map.id == "ROUTE41")
  check("whirlpool collision at 22,12", ow.map:cellTile(22, 12) == 0x24)
  check("gen2IsWhirlpool agrees", ow:gen2IsWhirlpool(22, 12) == true)
  check("plain water is not an eddy", ow:gen2IsWhirlpool(22, 13) == false)

  local p = ow.player
  p.surfing = true

  local function standAt(cx, cy, facing)
    ow.whirlSpin, ow.whirlHold = nil, nil
    p.spinning, p.spinFrames, p.inputLocked = false, nil, false
    p.moving = false
    p.cellX, p.cellY = cx, cy
    p.px, p.py = cx * 16, cy * 16
    p.facing = facing
  end

  -- facing away from the eddy: ordinary water, no whirl ---------------------
  standAt(22, 13, "down")
  check("no whirl facing away", ow:checkGen2Whirlpool("down") == false)
  check("no whirlSpin queued", ow.whirlSpin == nil)

  -- surfing into it ---------------------------------------------------------
  standAt(22, 13, "up")
  check("whirl fires on the tile ahead", ow:checkGen2Whirlpool("up") == true)
  check("whirlSpin queued", ow.whirlSpin ~= nil)
  check("sprite spinning", p.spinning == true)
  check("input locked for the whirl", p.inputLocked == true)
  check("two step_dig beats = 32 frames", ow.whirlSpin.frames == 32)
  check("turns back to down", ow.whirlSpin.facing == "down")
  check("facing not flipped yet", p.facing == "up")

  -- a second poll while the whirl runs must not restart it
  local before = ow.whirlSpin.frames
  check("re-entrant poll keeps the whirl", ow:checkGen2Whirlpool("up") == true)
  check("re-entrant poll does not rearm", ow.whirlSpin.frames == before)

  U.wait(40)
  check("whirl finished", ow.whirlSpin == nil)
  check("spin cleared", p.spinning == false)
  check("input released", p.inputLocked == false)
  check("sent back the way it came", p.facing == "down")
  check("never entered the eddy", p.cellX == 22 and p.cellY == 13)
  check("a hold window follows the spin", (ow.whirlHold or 0) > 0)

  -- the other three approaches ---------------------------------------------
  local approaches = {
    { 22, 11, "down", "up" },
    { 21, 12, "right", "left" },
    { 23, 12, "left", "right" },
  }
  for _, a in ipairs(approaches) do
    local cx, cy, dir, want = a[1], a[2], a[3], a[4]
    standAt(cx, cy, dir)
    check("whirl fires surfing " .. dir, ow:checkGen2Whirlpool(dir) == true)
    check(dir .. " -> " .. want, ow.whirlSpin and ow.whirlSpin.facing == want)
    U.wait(40)
    check(dir .. " ends facing " .. want, p.facing == want)
    check(dir .. " stayed on " .. cx .. "," .. cy,
          p.cellX == cx and p.cellY == cy)
  end

  -- input is genuinely gated: holding a direction never gets you in ---------
  standAt(22, 13, "up")
  U.hold(game, "up", 10)
  check("held UP does not enter the eddy", p.cellX == 22 and p.cellY == 13)
  check("held UP started the whirl", ow.whirlSpin ~= nil)
  U.wait(24)
  check("whirl released the player", ow.whirlSpin == nil and p.facing == "down")
  -- ...and the hold window keeps a still-held direction from re-entering
  check("a hold window follows the spin", (ow.whirlHold or 0) > 0)
  check("the hold window swallows a held UP",
        ow:checkGen2Whirlpool("up") == true)
  check("...without rearming the spin", ow.whirlSpin == nil)
  check("still outside the eddy", p.cellX == 22 and p.cellY == 13)

  -- a save left standing on an eddy is still spun out -----------------------
  standAt(22, 12, "up")
  check("standing on the eddy whirls too", ow:checkGen2Whirlpool("up") == true)
  U.wait(40)
  check("...and turns the player around", p.facing == "down")

  -- clearing the eddy (DisappearWhirlpool) must stop the whirl --------------
  local row, bx, by = ow:gen2WhirlpoolSwap(22, 12)
  check("Route 41 eddy has a block swap", row ~= nil)
  if row then
    ow.map:setBlock(bx, by, row.after)
    ow.map.renderer:rebuild()
    standAt(22, 13, "up")
    check("cleared eddy is plain water", ow:gen2IsWhirlpool(22, 12) == false)
    check("cleared eddy no longer whirls", ow:checkGen2Whirlpool("up") == false)
  end

  U.log(("RESULT %s (%d pass, %d fail)"):format(fail == 0 and "PASS" or "FAIL",
                                                pass, fail))
end
