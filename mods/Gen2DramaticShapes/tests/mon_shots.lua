-- Driver: one overworld-battle screenshot per species, the mon fighting
-- ITSELF -- its back pic on the player's mark and its front pic on the
-- enemy's, so a single frame shows both sprites the 3D mode draws for it.
--
-- The point is a visual sweep for pic glitches (holes the paper-fill missed,
-- a silhouette cut wrong, a pin that leaves the mon floating), so every shot
-- is staged identically: same map, same cells, same beat -- the battle menu,
-- both HUD panels up. Whatever differs between two shots is the mon.
--
--   SHOT_DIR=.scratchpad/mon_shots \
--   POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/mon_shots.lua love .
--
-- Files land as NNN_species.png in dex order.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad/mon_shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  -- every real species the merged data carries, walked in dex order
  local species = {}
  for id, def in pairs(game.data.pokemon) do
    if type(id) == "string" and type(def) == "table"
       and def.dex and def.dex >= 1 and def.dex <= 151 then
      species[#species + 1] = { id = id, dex = def.dex }
    end
  end
  table.sort(species, function(a, b) return a.dex < b.dex end)
  U.log(("%d species"):format(#species))

  game.save.player.name = "RED"

  for _, s in ipairs(species) do
    -- level 50 both sides: high enough that nothing about the staging is
    -- species-specific, and a wild battle never awards exp off a menu shot
    game.save.party = { Pokemon.new(game.data, s.id, 50) }

    U.teleport(game, "ROUTE_1", 5, 8, "down")
    -- let the neighbourhood's meshes land so the first battle frame is the
    -- real arena rather than the flat fallback
    U.wait(60)

    local battle = BattleState.newWild(game, s.id, 50)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)

    -- the wipe, then tap through "Wild X appeared!" and the send-out until
    -- the battle MENU is actually up -- a fixed tap count lands on whatever
    -- beat the intro happened to be on, which is how a shot ends up with the
    -- trainer still standing where the mon should be
    U.wait(70)
    for _ = 1, 200 do
      if battle.phase == "menu" then break end
      U.tap(game, "a")
      U.wait(6)
    end
    if battle.phase ~= "menu" then
      U.log(("STUCK before menu: %s (phase %s)"):format(s.id, tostring(battle.phase)))
    end
    -- let the send-out slide/ball beat finish so the mon is standing still
    U.wait(40)
    U.shot(game, ("%s/%03d_%s.png"):format(DIR, s.dex, s.id:lower()))

    while game.stack:top() and game.stack:top() ~= game.overworld do
      game.stack:pop()
    end
    U.wait(10)
  end

  U.log("done -- " .. DIR)
end
