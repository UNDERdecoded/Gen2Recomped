-- Driver: party list must not sit under the bottom message box (#262).
--   Gen1 (pokered engine/menus/party_menu.asm RedrawPartyMenu_) places the
--   first name at hlcoord 3, 0 and advances each entry by 2*SCREEN_WIDTH.
--   The recomp used y = (i-1)*16 + 12, which shoved a full party down so
--   slot 6 was clipped by the "Choose a POKéMON." text box (tile row 12).
--   This driver opens a 6-mon party menu, screenshots it, and asserts
--   PartyMenu.entryY keeps slot 6's HP row above y=96.
--   POKEPORT_DRIVER=tests/drivers/party_bug262_offset_test.lua \
--     POKEPORT_IDENTITY=bug262 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1; U.log("PASS", label)
    else fail = fail + 1; U.log("FAIL", label) end
  end

  game.save.party = {
    Pokemon.new(game.data, "CHARMANDER", 12),
    Pokemon.new(game.data, "PARAS", 10),
    Pokemon.new(game.data, "DIGLETT", 15),
    Pokemon.new(game.data, "FARFETCHD", 5),
    Pokemon.new(game.data, "GASTLY", 20),
    Pokemon.new(game.data, "SANDSHREW", 22),
  }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  Screens.push(game, "PartyMenu")
  U.wait(8)
  U.shot(game, DIR .. "/party_bug262_offset.png")

  local pm = game.stack:top()
  check("top is PartyMenu", getmetatable(pm) == PartyMenu)
  check("entryY(1) == 0", PartyMenu.entryY(1) == 0)
  check("entryY(6) == 80", PartyMenu.entryY(6) == 80)
  check("slot 6 HP row < message box y=96", PartyMenu.entryY(6) + 8 < 96)
  check("field message == 'Choose a POKéMON.'",
        pm and pm.bottomMessage and pm:bottomMessage() == "Choose a POKéMON.")

  U.log(("RESULT pass=%d fail=%d"):format(pass, fail))
end
