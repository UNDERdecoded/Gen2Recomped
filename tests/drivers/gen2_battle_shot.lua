-- Driver: one Gen 2 wild battle under DRAMATIC_SHAPE's overworld battle, shot
-- at the command menu so the HUD panels and the battle menu can be looked at.
--
--   POKEPORT_VERSION=gold SHOT_DIR=.scratchpad \
--     POKEPORT_DRIVER=tests/drivers/gen2_battle_shot.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  U.newGame(game)
  U.wait(30)
  game.save.party = { Pokemon.new(game.data, "SPECIES_155", 5) }
  -- part-way to level 6, so the exp bar has something to draw
  local mon = game.save.party[1]
  local Growth = require("src.pokemon.Growth")
  local rate = game.data.pokemon[mon.species].growthRate
  local lo = Growth.expForLevel(rate, 5)
  local hi = Growth.expForLevel(rate, 6)
  mon.exp = math.floor(lo + (hi - lo) * 0.55)

  U.teleport(game, "ROUTE_29", 10, 8, "down")
  U.wait(90)

  local battle = BattleState.newWild(game, "SPECIES_019", 4)
  battle.onFinish = function() end
  game.overworld:pushBattle(battle)

  U.wait(70)
  for _ = 1, 200 do
    if battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(6)
  end
  U.wait(30)
  U.log("phase", tostring(battle.phase))
  U.shot(game, DIR .. "/gen2_battle_menu.png")

  local Battles
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if lib then Battles = lib.require("OverworldBattle") end
  if Battles then
    local shot = Battles.shot()
    if shot then
      U.log(("shot scale=%s lx=%s ly=%s pw=%s ph=%s"):format(
        tostring(shot.scale), tostring(shot.lx), tostring(shot.ly),
        tostring(shot.pw), tostring(shot.ph)))
    else
      U.log("no shot")
    end
  else
    U.log("DRAMATIC_SHAPE not loaded")
  end

  U.log("done -- " .. DIR)
  love.event.quit()
end
