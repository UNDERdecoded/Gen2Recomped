-- Driver: try a TM from the battle bag; Gen 1 refuses with Oak's
-- "This isn't the time to use that!" (ItemUseTMHM -> ItemUseNotTime).
--
--   SHOT_DIR=/tmp/tm_battle_shots POKEPORT_DRIVER=tests/drivers/tm_battle_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")
  local TextBox = require("src.render.TextBox")
  local ListMenu = require("src.ui.ListMenu")

  table.insert(game.save.party, Pokemon.new(game.data, "CHARMANDER", 12))
  Bag.add(game.save, "TM_TOXIC", 1)
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

  local BattleState = require("src.battle.BattleState")
  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  ow:pushBattle(battle)

  local function mashUntil(cond, max)
    for _ = 1, max or 80 do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(4)
    end
    return false
  end

  local function pageText(box)
    if not box or getmetatable(box) ~= TextBox then return "" end
    return table.concat(box.pages[box.pageIndex] or {}, "\n")
  end

  U.log("to menu:", mashUntil(function() return battle.phase == "menu" end))
  U.shot(game, DIR .. "/tm_battle_0_menu.png")

  -- FIGHT/PKMN / ITEM/RUN: down to ITEM, then A
  U.tap(game, "down"); U.wait(4)
  U.tap(game, "a"); U.wait(12)
  U.shot(game, DIR .. "/tm_battle_1_bag.png")
  U.log("bag open:", getmetatable(game.stack:top()) == ListMenu)

  U.tap(game, "a")
  mashUntil(function()
    local top = game.stack:top()
    return getmetatable(top) == TextBox and top.waiting
      and pageText(top):find("isn't the", 1, true)
  end, 40)
  U.shot(game, DIR .. "/tm_battle_2_reject.png")

  local top = game.stack:top()
  local text = pageText(top)
  U.log("reject TextBox:", getmetatable(top) == TextBox)
  U.log("oak text:", text:find("isn't the", 1, true) and "ok" or text)
  U.log("tm still in bag:", (game.save.inventory.TM_TOXIC or 0) >= 1)
  U.log("not booted:", not text:find("Booted", 1, true))
end
