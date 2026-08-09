-- Driver: teaching a TM must open the party menu in Gen 1's TM/HM mode,
-- showing ABLE / NOT ABLE per mon from its learnset (no HP bars) with the
-- "Use TM on which POKeMON?" prompt (engine/items/item_effects.asm
-- ItemUseTMHM -> engine/menus/party_menu.asm PrintPartyMenu TM/HM type). #210
--
-- Party CHARIZARD 50 / MAGIKARP 15 / SNORLAX 40 with TM_TOXIC: CHARIZARD
-- and SNORLAX learn TOXIC (ABLE); MAGIKARP has an empty tmhm (NOT ABLE).
--
--   SHOT_DIR=/tmp/bug210 POKEPORT_DRIVER=tests/drivers/tmhm_able_bug210_test.lua \
--     POKEPORT_IDENTITY=bug210 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local TextBox = require("src.render.TextBox")
  local PartyMenu = require("src.ui.PartyMenu")

  -- fresh party with mixed learnability
  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 50),
    Pokemon.new(game.data, "MAGIKARP", 15),
    Pokemon.new(game.data, "SNORLAX", 40),
  }
  Bag.add(game.save, "TM_TOXIC", 1)
  U.teleport(game, "PALLET_TOWN", 5, 5, "down")

  -- expected ABLE/NOT ABLE from the same learnset the teach reads
  -- (ItemEffects.use scans data.pokemon[species].tmhm for machine.move)
  local move = game.data.items.TM_TOXIC.machine.move
  for _, mon in ipairs(game.save.party) do
    local can = false
    for _, m in ipairs(game.data.pokemon[mon.species].tmhm or {}) do
      if m == move then can = true break end
    end
    U.log("expect", mon.species, can and "ABLE" or "NOT ABLE")
  end

  -- open the bag; BagMenu.new returns the ITEMS ListMenu
  local bag = require("src.ui.Screens").push(game, "BagMenu")
  U.wait(3)
  for i, it in ipairs(bag.items) do
    if it.value == "TM_TOXIC" then bag.index = i break end
  end
  U.log("bag index on TM_TOXIC:", bag.index, bag.items[bag.index].value)

  -- A -> USE / TOSS menu, then A on USE (index 1)
  U.tap(game, "a"); U.wait(6)
  U.tap(game, "a"); U.wait(6)

  local function pageText(box)
    if not box or getmetatable(box) ~= TextBox then return "" end
    return table.concat(box.pages[box.pageIndex] or {}, "\n")
  end

  -- mash through "Booted up a TM!" / "It contained TOXIC!" until the
  -- TM/HM party menu is on top; stop before tapping A on it (that would
  -- pick a mon)
  local function reachPartyMenu(max)
    for _ = 1, max or 120 do
      if getmetatable(game.stack:top()) == PartyMenu then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return false
  end

  local reached = reachPartyMenu()
  U.log("reached PartyMenu:", tostring(reached))
  U.wait(3)
  U.shot(game, DIR .. "/tmhm_bug210_partymenu.png")

  local top = game.stack:top()
  U.log("top is PartyMenu:", getmetatable(top) == PartyMenu)
  U.log("top.tmhm:", top.tmhm and ("move=" .. tostring(top.tmhm.move)
        .. " kind=" .. tostring(top.tmhm.kind)) or "nil")

  -- assertions: fail while the bug exists (no TM mode), pass once fixed
  assert(getmetatable(top) == PartyMenu, "did not reach the party menu")
  assert(top.tmhm, "party menu is not in TM/HM mode (opts.tmhm missing)")
  assert(top.tmhm.move == move,
         "TM/HM move mismatch: " .. tostring(top.tmhm.move))

  U.log("DONE")
  love.event.quit()
end
