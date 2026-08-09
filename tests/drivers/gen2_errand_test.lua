-- Driver: Gen2 POKéGEAR screen + the Mr. Pokémon mystery egg errand.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Bag = require("src.inventory.Bag")

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_G2_GOT_STARTER = true
  game.save.flags.EVENT_GOT_POKEGEAR = true
  game.save.flags.EVENT_GOT_MAP_CARD = true
  game.save.flags.EVENT_GOT_RADIO_CARD = true
  game.save.party[1] = Pokemon.new(game.data, "SPECIES_155", 5)

  -- POKéGEAR: every card draws
  local gear = Screens.push(game, "PokegearMenu")
  for i = 1, #gear.cards do
    U.wait(3)
    U.log("card", gear.cards[gear.index])
    U.tap(game, "right")
  end
  U.wait(3)
  U.tap(game, "b"); U.wait(3)

  -- START menu carries the POKéGEAR row
  local menu = Screens.push(game, "StartMenu")
  local labels = {}
  for _, it in ipairs(menu.items or {}) do labels[#labels + 1] = it.label end
  U.log("start menu:", table.concat(labels, ","))
  U.tap(game, "b"); U.wait(3)

  -- the errand
  U.teleport(game, "MR_POKEMONS_HOUSE", 3, 6, "up")
  U.wait(10)
  local ow = game.overworld
  U.log("npcs:", #ow.npcs)
  for _, npc in ipairs(ow.npcs) do
    U.log("  npc", npc.id, npc.def and npc.def.text)
  end
  ow:talkTo(ow.npcs[1])
  for _ = 1, 400 do U.tap(game, "a"); U.wait(4) end
  U.log("has egg:", tostring(Bag.count and Bag.count(game.save, "ITEM_069")
        or game.save.inventory.ITEM_069))
  U.log("flags:", tostring(game.save.flags.EVENT_G2_GOT_MYSTERY_EGG),
        tostring(game.save.flags.EVENT_GOT_POKEDEX))
  U.log("phone:", #(game.save.phone or {}))
  U.log("DONE")
  love.event.quit()
end
