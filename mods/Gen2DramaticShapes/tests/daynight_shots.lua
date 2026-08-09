-- Driver: screenshot the day/night cycle.
--
-- One vantage (Pallet Town, VOXEL 75) through every pinned phase, two
-- mid-blend moments of the running cycle, a battle staged under the night
-- sky, and a room at midnight -- which must look exactly like a room at
-- noon, because indoors the clock does not reach.
--
--   SHOT_DIR=.scratchpad/daynightcycle POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/daynight_shots.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad/daynightcycle"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if not lib then
    U.log("DRAMATIC_SHAPE is not loaded -- enable it and run again")
    return
  end
  local DayNight = lib.require("DayNight")

  local function setTime(value, clock)
    DayNight.setting:sync(value)
    if clock then DayNight.clock = clock end
    DayNight.update(0)
  end

  U.teleport(game, "PALLET_TOWN", 12, 10, "up")
  -- straight to the top rung, whatever the persisted options say: pressing
  -- the key would walk the ladder RELATIVE to wherever a previous run left it
  local Pipelines = require("src.render.Pipelines")
  Pipelines.setLevel("voxel", 5)
  U.wait(150)                 -- let the camera ease over and the meshes land

  -- ------- the four pins, one vantage
  for _, phase in ipairs({ "day", "dawn", "dusk", "night" }) do
    setTime(phase)
    U.wait(30)                -- a couple of rig steps + palette settle
    U.shot(game, ("%s/10_pin_%s.png"):format(DIR, phase))
  end

  -- ------- the running cycle, mid-blend
  setTime("cycle", 560)       -- day leaning into dusk
  U.wait(10)
  U.shot(game, DIR .. "/20_cycle_day_into_dusk.png")
  setTime("cycle", 645)       -- dusk falling into night
  U.wait(10)
  U.shot(game, DIR .. "/21_cycle_dusk_into_night.png")

  -- ------- golden hour on open ground, long shadows
  U.teleport(game, "ROUTE_1", 8, 12, "up")
  U.wait(120)
  setTime("cycle", 555)       -- low western sun, shadows long and eastward
  U.wait(30)
  U.shot(game, DIR .. "/30_route1_low_sun.png")

  -- ------- a fight staged under the night sky
  setTime("night")
  game.save.party = game.save.party or {}
  if #game.save.party == 0 then
    game.save.party[1] = Pokemon.new(game.data, "CHARIZARD", 45)
  end
  -- any real trainer class: the dataset's ids vary by merge, so take the
  -- first one in stable order rather than guessing a name
  local classes = {}
  for id, rec in pairs(game.data.trainers) do
    if type(id) == "string" and id:sub(1, 1) ~= "_"
       and type(rec) == "table" and rec.parties and rec.parties[1] then
      classes[#classes + 1] = id
    end
  end
  table.sort(classes)
  local battle = classes[1] and BattleState.newTrainer(game, classes[1], 1)
  if battle then
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)
    U.wait(70)
    for _ = 1, 14 do U.tap(game, "a"); U.wait(8) end
    U.shot(game, DIR .. "/40_night_battle.png")
    while game.stack:top() and game.stack:top() ~= game.overworld do
      game.stack:pop()
    end
    U.wait(10)
  end

  -- ------- and a room, where midnight must change nothing
  setTime("night")
  if game.data.maps.REDS_HOUSE_1F then
    U.teleport(game, "REDS_HOUSE_1F", 4, 4, "down")
    U.wait(90)
    U.shot(game, DIR .. "/50_indoor_at_night.png")
  end

  -- ------- the forest, where only the TINT of it reaches: night falls
  -- through the canopy, but there is no sky and the noon light stays put
  setTime("night")
  if game.data.maps.VIRIDIAN_FOREST then
    U.teleport(game, "VIRIDIAN_FOREST", 17, 20, "up")
    U.wait(120)
    U.shot(game, DIR .. "/51_forest_night.png")
    setTime("day")
    U.wait(30)
    U.shot(game, DIR .. "/52_forest_day.png")
  end

  setTime("day")
  U.log("done -- " .. DIR)
end
