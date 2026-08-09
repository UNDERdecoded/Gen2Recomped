-- The rival's name.  ResetWRAM's InitializeNPCNames seeds wRivalName with
-- "???" (which is why the Cherrygrove rival's line spells it out), and the
-- Elm's Lab officer's `special NameRival` -- SpecialsPointers row $24 -- is
-- where the player types the real one.  The special was a warn-once stub, so
-- no prompt ever appeared and the name stayed whatever the save started with.
local U = require("tests.drivers.util")

return function(game)
  local pass, fail = 0, 0
  local function ok(cond, name)
    if cond then pass = pass + 1 else fail = fail + 1; U.log("FAIL " .. name) end
  end

  U.newGame(game)
  U.wait(10)

  -- U.newGame lands on CONTINUE when a save already exists, so check the
  -- seed the way SaveData does rather than whatever save happens to be loaded
  local fresh = require("src.core.SaveData").newGame(game.data.field.boot)
  ok(fresh.player.rival == "???",
     "a new game starts with the rival unnamed (" ..
     tostring(fresh.player.rival) .. ")")

  -- the battle screen reads the same field (GetTrainerName_ copies wRivalName
  -- into wTrainerName for RIVAL1/2/3), so it must agree with his own dialogue
  local BattleState = require("src.battle.BattleState")
  game.save.player.rival = "???"
  local battle = BattleState.newTrainer(game, "OPP_RIVAL1", 1)
  ok(battle.trainer.name == "???", "the battle names him from wRivalName")

  -- the officer's script has to lower to the command, not the stub
  local VM = require("src.script.Gen2ScriptVM")
  local lowered = 0
  for label in pairs((game.data.map_scripts or {}).scripts or {}) do
    local rows = VM.compile(game.data, label)
    for _, row in ipairs(rows or {}) do
      if row[1] == "g2_name_rival" then lowered = lowered + 1 end
    end
  end
  ok(lowered > 0, "`special NameRival` lowers to g2_name_rival (" ..
     lowered .. " rows)")

  -- the naming screen is map-independent, and ELMS_LAB's opening scene script
  -- owns the runner on a fresh save -- drive the command from a quiet route
  U.teleport(game, "ROUTE_34", 15, 21)
  U.wait(20)
  local ow = game.overworld
  ow.runner:run({ { "g2_name_rival" } }, {})
  U.wait(10)
  local screen = game.stack:top()
  ok(screen ~= ow and screen.glyphs ~= nil, "the naming screen opened")
  if screen and screen.glyphs then
    U.tap(game, "a") -- row 1, col 1 is "A"
    U.wait(4)
    U.tap(game, "start")
    U.wait(10)
    ok(game.save.player.rival == "A",
       "the typed name is stored (" .. tostring(game.save.player.rival) .. ")")
  end

  -- confirming an empty grid must not leave him nameless
  ow = game.stack:top()
  ow.runner:run({ { "g2_name_rival" } }, {})
  U.wait(10)
  if game.stack:top() ~= ow then
    U.tap(game, "start")
    U.wait(10)
    ok(game.save.player.rival == "SILVER",
       "an empty entry falls back to SILVER (" ..
       tostring(game.save.player.rival) .. ")")
  else
    ok(false, "the naming screen reopened")
  end

  U.log(("RESULT %s (%d pass, %d fail)")
    :format(fail == 0 and "PASS" or "FAIL", pass, fail))
  return fail == 0
end
