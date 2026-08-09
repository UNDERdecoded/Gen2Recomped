-- Probe: one overworld battle, held on the menu beat, shot large.
--
--   SHOT_DIR=... POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/monline_probe.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  love.math.setRandomSeed(20260727)

  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 45),
    Pokemon.new(game.data, "PIKACHU", 40),
  }
  game.save.player.name = "RED"

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  U.log("DRAMATIC_SHAPE lib:", tostring(lib))
  local Battles = lib and lib.require("OverworldBattle")
  U.log("OverworldBattle:", tostring(Battles))

  U.teleport(game, "ROUTE_1", 5, 8, "down")
  U.wait(120)

  local classes = {}
  for id, rec in pairs(game.data.trainers) do
    if type(id) == "string" and id:sub(1, 1) ~= "_"
       and type(rec) == "table" and rec.parties and rec.parties[1] then
      classes[#classes + 1] = id
    end
  end
  table.sort(classes)
  U.log("class:", classes[1])
  local battle = BattleState.newTrainer(game, classes[1], 1)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)

  U.wait(70)
  for _ = 1, 14 do U.tap(game, "a"); U.wait(8) end
  local arena = Battles and Battles.arena()
  U.log("arena:", arena and arena.shape or "none")
  U.shot(game, DIR .. "/probe_menu.png")
  for _ = 1, 20 do U.tap(game, "a"); U.wait(8) end
  U.wait(90)
  U.shot(game, DIR .. "/probe_menu2.png")
  U.log("done -- " .. DIR)
  love.event.quit()
end
