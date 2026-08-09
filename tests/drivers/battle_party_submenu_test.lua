-- Driver: mid-battle PKMN opens SWITCH / STATS / CANCEL (#180).
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/battle_party_submenu_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  game.save.party = {
    Pokemon.new(game.data, "CHARMANDER", 12),
    Pokemon.new(game.data, "SQUIRTLE", 10),
  }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld

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

  mashUntil(function() return battle.phase == "menu" end)
  U.shot(game, DIR .. "/battle_party_0_menu.png")

  -- FIGHT/PKMN/ITEM/RUN: right to PKMN, then A
  U.tap(game, "right"); U.wait(4)
  U.tap(game, "a"); U.wait(12)
  U.shot(game, DIR .. "/battle_party_1_list.png")

  local pm = game.stack:top()
  U.log("party open:", pm and pm.onSwitch ~= nil)
  U.tap(game, "a"); U.wait(8)
  pm = game.stack:top()
  U.shot(game, DIR .. "/battle_party_2_switch_stats.png")

  local labels = {}
  if pm and pm.submenu and pm.subItems then
    for _, e in ipairs(pm.subItems) do
      table.insert(labels, e.label)
    end
  end
  U.log("submenu:", table.concat(labels, "/"))
  U.log("order ok:", labels[1] == "SWITCH" and labels[2] == "STATS"
    and labels[3] == "CANCEL")

  -- STATS
  U.tap(game, "down"); U.wait(4)
  U.tap(game, "a"); U.wait(14)
  U.shot(game, DIR .. "/battle_party_3_stats.png")
  U.log("stats open:", game.stack:top() ~= pm)
end
