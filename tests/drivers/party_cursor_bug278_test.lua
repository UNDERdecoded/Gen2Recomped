-- Driver: party menu cursor alignment (#278).  Eye check, not pass/fail.
-- pokered home/pokemon.asm PartyMenuInit seeds wTopMenuItemY = 1 while
-- party_menu.asm RedrawPartyMenu_ starts the name column at hlcoord 3, 0,
-- so the cursor belongs on an entry's second row (level/HP), not its name
-- row.  No POKEPORT_SPEED: rendering runs on its own real-time clock.
--   POKEPORT_DRIVER=tests/drivers/party_cursor_bug278_test.lua POKEPORT_IDENTITY=bug278 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- the geometry the +8 depends on: 16px stride, name row at the top of
  -- each entry.  If entryY changes, the cursor offset has to be revisited.
  check("entryY stride is 16px", PartyMenu.entryY(2) - PartyMenu.entryY(1) == 16)
  check("slot 1 name row is y=0", PartyMenu.entryY(1) == 0)

  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 50),
    Pokemon.new(game.data, "PIKACHU", 30),
    Pokemon.new(game.data, "SNORLAX", 77),
    Pokemon.new(game.data, "BULBASAUR", 12),
  }
  game.save.player.name = "bryan"
  check("party has enough slots to judge the stride", #game.save.party >= 3)

  check("renderer is up", game.renderer ~= nil)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)

  Screens.push(game, "PartyMenu")
  U.wait(30)
  check("party menu is on top", game.stack:top() ~= nil)

  U.shot(game, "bug278_party_cursor_slot1.png")

  -- step down as well, so a stride bug cannot hide behind a correct slot 1
  U.tap(game, "down")
  U.wait(15)
  U.shot(game, "bug278_party_cursor_slot2.png")
  U.tap(game, "down")
  U.wait(15)
  U.shot(game, "bug278_party_cursor_slot3.png")

  U.log("Party menu is open; shots are in the LOVE save dir as")
  U.log("bug278_party_cursor_slot1/2/3.png.  The cursor should sit on the")
  U.log("lower row of each entry, level with LEVEL/HP, not up on the name")
  U.log("row (#278).  Up/down re-checks every slot, B closes the menu.")

  while true do
    coroutine.yield()
  end
end
