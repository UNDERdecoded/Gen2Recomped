-- The Mahogany Rocket base boss cutscene (RocketBaseBossFScript, 45:$4C67)
-- toggles Lance's own event flag ($06D6 -> EVENT_G2_1750) in the middle of
-- the scene.  pokecrystal's setevent/clearevent only decide whether
-- LoadMapObjects spawns an object on the NEXT map load, so the live map must
-- not move anything; the port used to respawn the object at its object_event
-- cell, snapping Lance back to (5,13) and sending every following
-- applymovement through the walls.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function check(name, ok)
    if ok then pass = pass + 1 else fail = fail + 1; U.log("FAIL " .. name) end
  end

  U.newGame(game)
  U.wait(10)
  U.teleport(game, "TEAM_ROCKET_BASE_B2F", 14, 15)
  U.wait(20)
  local ow = game.stack:top()
  check("on TeamRocketBaseB2F", ow.map and ow.map.id == "TEAM_ROCKET_BASE_B2F")

  -- object_event coordinates come straight from TeamRocketBaseB2F_MapEvents
  local expect = { [3] = { 5, 13 }, [5] = { 7, 5 }, [6] = { 7, 7 },
                   [7] = { 7, 9 }, [8] = { 22, 5 }, [9] = { 22, 7 },
                   [10] = { 22, 9 }, [11] = { 25, 13 }, [14] = { 3, 10 } }
  for slot, xy in pairs(expect) do
    local n = ow:npcByIndex(slot)
    check(("slot %d spawned at (%d,%d)"):format(slot, xy[1], xy[2]),
          n and n.cellX == xy[1] and n.cellY == xy[2])
  end

  local lance = ow:npcByIndex(3)
  check("slot 3 is Lance", lance ~= nil and lance.def ~= nil)
  local flag = lance and lance.def and lance.def.eventFlag
  check("Lance carries an event flag", type(flag) == "string")

  -- walk him somewhere the script would, then round-trip his flag
  lance.cellX, lance.cellY = 10, 13
  lance.px, lance.py = 160, 208
  lance.facing = "left"

  local Commands = require("src.script.Commands")
  local ctx = { game = game, save = game.save, overworld = ow }
  Commands.set_flag(ctx, flag)
  Commands.clear_flag(ctx, flag)

  local after = ow:npcByIndex(3)
  check("Lance survives a set_flag/clear_flag round trip", after ~= nil)
  check("...without snapping back to his object_event cell",
        after and after.cellX == 10 and after.cellY == 13)
  check("...keeping the facing the cutscene left him with",
        after and after.facing == "left")

  -- an explicit disappear/appear is the ROM's HideObject/ShowObject, which
  -- DOES re-init from the object_event, so that path must still reset
  local ball = ow:npcByIndex(14)
  check("slot 14 is the Poke Ball", ball ~= nil)
  local ballName = ball and ball.def and ball.def.name
  ball.cellX, ball.cellY = 12, 12
  Commands.hide_object(ctx, "TEAM_ROCKET_BASE_B2F", ballName)
  check("disappear removes it", ow:npcByIndex(14) == nil)
  Commands.show_object(ctx, "TEAM_ROCKET_BASE_B2F", ballName)
  local back = ow:npcByIndex(14)
  check("appear brings it back", back ~= nil)
  check("appear re-inits it at the object_event cell",
        back and back.cellX == 3 and back.cellY == 10)

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
end
