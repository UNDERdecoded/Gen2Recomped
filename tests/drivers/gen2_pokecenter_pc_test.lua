-- The Pokemon Center PC.  GSC lists its PCs nowhere: COLL_PC ($93) is the
-- PC, and CheckFacingTileForStdScript dispatches TileCollisionStdScripts'
-- PCScript off the collision class alone.  The port only carried R/B's
-- hand-listed field.hiddenExtras.pcTiles, so facing the Center's PC did
-- nothing at all.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, what)
    if cond then pass = pass + 1 else
      fail = fail + 1
      U.log("FAIL " .. what)
    end
  end

  U.newGame(game)
  U.wait(20)

  U.teleport(game, "AZALEA_POKECENTER1_F", 9, 2)
  U.wait(20)
  local ow = game.stack:top()
  ok(ow.map and ow.map.id == "AZALEA_POKECENTER1_F", "in the Azalea Center")
  ok(ow.map:cellTile(9, 1) == 0x93, "the PC cell is COLL_PC ($93)")

  ow.player.cellX, ow.player.cellY = 9, 2
  ow.player.facing = "up"
  local before = game.stack:top()
  ow:interact()
  U.wait(10)
  local top = game.stack:top()
  ok(top ~= before, "facing the PC and pressing A opened something")

  -- the PC menu is a Menu with BILL'S/SOMEONE'S PC, the player's PC and
  -- LOG OFF; check the labels rather than the class so a mod's ui.pc.items
  -- hook does not fail the test outright
  local labels = {}
  for _, item in ipairs((top and top.items) or {}) do
    labels[#labels + 1] = tostring(item.label or item)
  end
  local joined = table.concat(labels, "|")
  ok(joined:find("PC", 1, true) ~= nil,
     "the PC menu listed its accounts (" .. joined .. ")")
  ok(joined:upper():find("LOG OFF", 1, true) ~= nil, "LOG OFF is there")

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
  return fail == 0
end
