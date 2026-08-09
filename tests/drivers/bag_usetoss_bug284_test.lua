-- Eye check on the bag's USE/TOSS submenu box (#284).
-- pokered data/text_boxes.asm: USE_TOSS_MENU_TEMPLATE covers tiles
-- (13,10)-(19,14) with "USE" at (15,11), and start_sub_menus.asm puts the
-- cursor at wTopMenuItemY/X 11/14.  The port opened it one column wider and
-- one row taller, which stranded the labels near the top edge.
--   POKEPORT_DRIVER=tests/drivers/bag_usetoss_bug284_test.lua POKEPORT_IDENTITY=bug284 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- an empty bag, or an item whose branch skips the submenu, leaves no box on
  -- screen at all, which looks the same as a broken one
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.player.name = "bryan"
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.POTION = 3
  check("a usable, tossable item is in the bag",
        (game.save.inventory.POTION or 0) > 0)

  -- BICYCLE short-circuits straight past the submenu in the original
  -- (start_sub_menus.asm `cp BICYCLE / jp z, .useOrTossItem`), and the port
  -- mirrors that, so the first item must not be the bike.
  check("POTION is not a submenu-skipping item",
        game.data.items.POTION ~= nil and not game.data.items.POTION.keyItem)

  check("renderer is up", game.renderer ~= nil)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)

  Screens.push(game, "BagMenu")
  U.wait(30)
  U.shot(game, "bug284_bag_list.png")

  U.tap(game, "a")
  U.wait(30)
  U.shot(game, "bug284_usetoss.png")

  U.log("USE/TOSS is open over the bag list; shot in bug284_usetoss.png.")
  U.log("It should run tiles (13,10)-(19,14) with the cursor one column left")
  U.log("of the labels and a single border row under TOSS, no blank gap (#284).")
  U.log("Up/down moves between USE and TOSS.")

  while true do
    coroutine.yield()
  end
end
