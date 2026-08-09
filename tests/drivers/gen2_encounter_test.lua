-- Driver: Gen2 wild encounters on bare cave/dungeon floor.
--
-- CanEncounterWildMon (37:$7B2E) skips the grass-tile test when the map
-- header's environment is CAVE(4) or DUNGEON(7).  Walk a lap in Union Cave
-- and Sprout Tower 2F and assert a battle eventually starts.
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_encounter_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")

  local pass, fail = 0, 0
  local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "PASS " or "FAIL ") .. what)
  end

  U.newGame(game)
  U.wait(20)
  game.save.party = { Pokemon.new(game.data, "SPECIES_155", 40) }

  -- environments come straight off the extracted map headers
  local maps = game.data.maps
  check(maps.UNION_CAVE1_F and maps.UNION_CAVE1_F.environment == 4,
    "UNION_CAVE1_F is CAVE")
  check(maps.SPROUT_TOWER2_F and maps.SPROUT_TOWER2_F.environment == 7,
    "SPROUT_TOWER2_F is DUNGEON")
  check(maps.NEW_BARK_TOWN and maps.NEW_BARK_TOWN.environment == 1,
    "NEW_BARK_TOWN is TOWN")

  local enc = game.data.encounters
  check(enc.UNION_CAVE1_F and enc.UNION_CAVE1_F.grass.rate > 0,
    "UNION_CAVE1_F has a grass table")
  check(enc.SPROUT_TOWER2_F and enc.SPROUT_TOWER2_F.grass.rate > 0,
    "SPROUT_TOWER2_F has a grass table")

  -- walk until a battle starts; the rate is 10/256 per step, so 200 steps
  -- misses with probability ~4e-4
  -- Force the map rate to certain so the test measures the encounter GATE and
  -- not the RNG: one step on bare cave floor must start a battle.
  local function lap(mapId)
    U.teleport(game, mapId, 1, 1, "down")
    U.wait(20)
    local ow = game.overworld
    local map = ow.map
    -- NPCs block a cell the collision map calls walkable, so a pair the
    -- player cannot actually step between would measure nothing
    local taken = {}
    for _, npc in ipairs(ow.npcs or {}) do
      taken[(npc.cellY or -1) * map.widthCells + (npc.cellX or -1)] = true
    end
    local sx, sy
    for y = 0, map.heightCells - 1 do
      for x = 0, map.widthCells - 2 do
        local i = y * map.widthCells + x
        if map:isWalkableCell(x, y) and map:isWalkableCell(x + 1, y)
           and not map.warpAt[i] and not map.warpAt[i + 1]
           and not taken[i] and not taken[i + 1] then
          sx, sy = x, y
          break
        end
      end
      if sx then break end
    end
    if not sx then U.log(mapId .. ": no walkable pair found") return nil end
    U.log(("%s: walkable pair at %d,%d"):format(mapId, sx, sy))
    U.teleport(game, mapId, sx, sy, "right")
    U.wait(20)
    ow = game.overworld
    -- force every time-of-day set: which one the roll reads depends on the
    -- host clock now that Gen2's GetTimeOfDay is modelled
    local grass = game.data.encounters[mapId].grass
    grass.rate = 255
    for _, alt in pairs(grass.byTime or {}) do alt.rate = 255 end
    for i = 1, 8 do
      U.hold(game, (i % 2 == 0) and "left" or "right", 20)
      U.wait(3)
      if game.stack:top() ~= ow then
        -- the encounter opens with the battle-intro wipe; let it resolve
        for _ = 1, 240 do
          local top = game.stack:top()
          if top and top.enemy then return top end
          U.wait(1)
        end
        U.log(mapId .. ": transition never became a battle")
        return nil
      end
    end
    U.log(("%s: walked from %d,%d to %d,%d without an encounter"):format(
      mapId, sx, sy, ow.player.cellX, ow.player.cellY))
    return nil
  end

  for _, mapId in ipairs({ "UNION_CAVE1_F", "SPROUT_TOWER2_F" }) do
    local top = lap(mapId)
    local isBattle = top ~= nil and top.enemy ~= nil
    check(isBattle, mapId .. " starts a wild battle on bare floor")
    if top then
      while game.stack:top() ~= game.overworld do game.stack:pop() end
      U.wait(5)
    end
  end

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit()
end
