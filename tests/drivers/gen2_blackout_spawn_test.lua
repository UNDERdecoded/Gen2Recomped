-- Driver: the Gen 2 blackout spawn.
--
-- Gold never sets the blackout point from the nurse.  EnterMapWarp.SetSpawn
-- (home/map.asm) records it when the player steps OUT of a Pokemon Center
-- (TILESET_POKECENTER) into a TOWN or ROUTE map, and GetWhiteoutSpawn reads
-- the arrival cell out of SpawnPoints; `blackoutmod` overrides it for the
-- handful of scripted spawns (Olivine, Vermilion, Cherrygrove, the S.S. Aqua).
-- With neither half ported, every blackout fell through to the ROM's own
-- fallback -- spawn 0, the bedroom in New Bark Town -- however far the story
-- had got, which is what the player saw.
--
--   POKEPORT_VERSION=gold \
--     POKEPORT_DRIVER=tests/drivers/gen2_blackout_spawn_test.lua love .
return function(game)
  local U = require("tests.drivers.util")
  local pass, fail = 0, 0
  local function ck(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
  end

  local function settle(ow, limit)
    for _ = 1, limit or 300 do
      if not ow.transitioning then break end
      U.wait(1)
    end
    U.wait(10)
  end

  local spawns = game.data.map_scripts and game.data.map_scripts.spawns
  ck("map_scripts carries the extracted SpawnPoints table", spawns ~= nil)
  if not spawns then
    U.log("RESULT FAIL (no spawn table -- re-import the ROM)")
    love.event.quit()
    return
  end
  ck("Cherrygrove City has a spawn row", spawns.points.CHERRYGROVE_CITY ~= nil)
  ck("the Cherrygrove Pokemon Center is flagged as one",
     spawns.centers.CHERRYGROVE_POKECENTER1_F == true)
  ck("an ordinary shop is not", spawns.centers.CHERRYGROVE_MART == nil)

  U.newGame(game)
  U.wait(30)

  -- the ROM's own fallback, before any centre has been visited
  local start = game.save.lastHeal
  ck("a new game blacks out to the bedroom, like spawn 0",
     start ~= nil and start.map == "PLAYERS_HOUSE2_F")

  U.teleport(game, "CHERRYGROVE_POKECENTER1_F", 4, 6, "down")
  U.wait(20)
  local ow = game.overworld
  ow:startWarpTo("CHERRYGROVE_CITY", 29, 4, "down")
  settle(ow)
  local heal = game.save.lastHeal
  U.log("after leaving the centre:", heal and heal.map, heal and heal.x,
        heal and heal.y)
  ck("leaving the centre moves the spawn to the town's SpawnPoints cell",
     heal ~= nil and heal.map == "CHERRYGROVE_CITY"
     and heal.x == 29 and heal.y == 4)

  -- SetSpawn gates on the tileset, so any other building must be inert
  U.teleport(game, "CHERRYGROVE_MART", 3, 7, "down")
  U.wait(20)
  ow = game.overworld
  ow:startWarpTo("CHERRYGROVE_CITY", 21, 10, "down")
  settle(ow)
  ck("leaving the mart leaves the spawn alone",
     game.save.lastHeal.map == "CHERRYGROVE_CITY"
     and game.save.lastHeal.x == 29)

  -- and the warp a wipe-out actually takes
  U.teleport(game, "ROUTE_30", 6, 10, "down")
  U.wait(20)
  ow = game.overworld
  ow:warpToHealPoint()
  for _ = 1, 400 do
    if ow.map.id == "CHERRYGROVE_CITY" and not ow.transitioning then break end
    U.wait(1)
  end
  U.log("blacked out to:", ow.map.id, ow.player.cellX, ow.player.cellY)
  ck("a blackout lands on the Cherrygrove spawn, not the bedroom",
     ow.map.id == "CHERRYGROVE_CITY" and ow.player.cellX == 29
     and ow.player.cellY == 4)

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit()
end
