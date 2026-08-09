-- Driver: Fighting Dojo Karate Master gate (#495).
--
-- Run:
--   POKEPORT_DRIVER=tests/drivers/fighting_dojo_gate_bug495_test.lua \
--     POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
--
-- The scene starts one tile north of the only trigger tile.  The reported
-- behaviour is an interaction timing and position question for a human to
-- observe, not an assertion this driver can decide.
return function(game)
  local U = dofile("tests/drivers/util.lua")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  U.teleport(game, "FIGHTING_DOJO", 4, 2, "down")
  local ow = game.stack:top()
  local master
  for _, npc in ipairs(ow.npcs) do
    if npc.def and npc.def.name == "FIGHTINGDOJO_KARATE_MASTER" then
      master = npc
      break
    end
  end

  -- Fixture checks only: the room, player, and Master must be in the layout
  -- that makes the reported tile meaningful.
  check("Fighting Dojo is loaded", ow.map.id == "FIGHTING_DOJO")
  check("player starts north of the trigger tile",
        ow.player.cellX == 4 and ow.player.cellY == 2)
  check("Karate Master is at (5,3)",
        master and master.cellX == 5 and master.cellY == 3)

  U.log("Issue #495: Karate Master gate")
  U.log("Do this: press Down once, onto the tile left of the Master.")
  U.log("Right: he turns left and starts his challenge on that tile only.")
  U.log("Wrong: nothing happens here, while standing below him triggers a battle.")

  while true do
    coroutine.yield()
  end
end
