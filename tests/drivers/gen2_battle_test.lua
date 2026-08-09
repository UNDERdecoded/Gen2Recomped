-- Driver: force a Gen2 wild battle and step through a move.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local starter = Pokemon.new(game.data, "SPECIES_155", 12) -- Cyndaquil
  table.insert(game.save.party, starter)
  U.log("party mon", starter.species, "moves:")
  for _, m in ipairs(starter.moves or {}) do
    local d = game.data.moves[m.id]
    U.log("  ", m.id, d and d.power, d and d.type, d and d.effect)
  end

  local battle = BattleState.newWild(game, "SPECIES_016", 8) -- Pidgey
  battle.onFinish = function(r) U.log("battle finished:", tostring(r)) end
  game.stack:push(battle)

  for _ = 1, 20 do U.tap(game, "a"); U.wait(6) end
  U.log("phase", tostring(battle.phase))
  U.tap(game, "a"); U.wait(10)
  U.tap(game, "a"); U.wait(60)
  U.log("enemy hp", tostring(battle.enemy and battle.enemy.mon.hp))
  U.log("player hp", tostring(battle.player and battle.player.mon.hp))
  U.log("DONE")
  love.event.quit()
end
