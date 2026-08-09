-- Driver: screenshot an overworld battle against eight random trainers.
--
-- The mode's whole claim is that a fight reads as happening on the map, so
-- what has to be looked at is a spread of maps: open route, town, forest,
-- cave, gym floor. Each one gets the same three beats -- the menu (both HUD
-- panels up over whatever ground they landed on), a move animation, and the
-- frame a few seconds later, which is where the parallax drift shows.
--
-- The eight are drawn with a fixed seed, so a re-run after a tweak produces
-- the same eight battles and the shots compare directly.
--
--   SHOT_DIR=.scratchpad POKEPORT_DRIVER=mods/DramaticShapeVoxelMod/tests/battle_shots.lua love .
--
-- SHOT_DIR must already exist: the capture writes with io.open, which does
-- not create directories.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or ".scratchpad"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local SEED = tonumber(os.getenv("SHOT_SEED") or "") or 20260727
  love.math.setRandomSeed(SEED)

  -- Somebody to fight with. Two very different back pics, so a pin that is
  -- wrong for one silhouette and right for another cannot hide.
  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 45),
    Pokemon.new(game.data, "PIKACHU", 40),
  }
  game.save.player.name = "RED"

  -- Where to stage them: outdoor, wooded, urban, underground, indoor. Any id
  -- the merged dataset does not have is dropped rather than guessed at.
  local PLACES = {
    { "ROUTE_1", 5, 8 },
    { "VIRIDIAN_FOREST", 12, 20 },
    { "PALLET_TOWN", 5, 6 },
    { "MT_MOON_1F", 12, 12 },
    { "CERULEAN_CITY", 10, 12 },
    { "ROUTE_25", 12, 5 },
    { "PEWTER_GYM", 4, 8 },
    { "ROUTE_4", 10, 5 },
    { "VIRIDIAN_CITY", 20, 20 },
    { "ROUTE_3", 10, 5 },
  }
  local places = {}
  for _, p in ipairs(PLACES) do
    if game.data.maps[p[1]] then places[#places + 1] = p end
  end

  -- every trainer class the merged data carries, in a stable order so the
  -- seed picks the same ones every run
  local classes = {}
  for id, rec in pairs(game.data.trainers) do
    if type(id) == "string" and id:sub(1, 1) ~= "_"
       and type(rec) == "table" and rec.parties and rec.parties[1] then
      classes[#classes + 1] = id
    end
  end
  table.sort(classes)
  U.log(("%d trainer classes, %d places, seed %d")
        :format(#classes, #places, SEED))

  local Battles = nil
  local exports = game.mods and game.mods.exports
  local lib = exports and exports.DRAMATIC_SHAPE and exports.DRAMATIC_SHAPE.lib
  if lib then Battles = lib.require("OverworldBattle") end
  if not Battles then
    U.log("DRAMATIC_SHAPE is not loaded -- enable it and run again")
  end

  local function label(place, class)
    local arena = Battles and Battles.arena()
    if not arena then
      return ("%s / %s -- NO ARENA (plain battle screen)")
             :format(place[1], class)
    end
    return ("%s / %s -- %s arena at cell %d,%d; enemy %d,%d player %d,%d")
           :format(place[1], class, arena.shape, arena.x, arena.y,
                   arena.enemyCell[1], arena.enemyCell[2],
                   arena.playerCell[1], arena.playerCell[2])
  end

  for i = 1, 8 do
    -- the TRAINERS are the random part; the places are walked in order, so
    -- one run covers open route, town, forest, cave and gym floor rather
    -- than landing on the same meadow eight times
    local place = places[(i - 1) % #places + 1]
    local class = classes[love.math.random(#classes)]
    local rec = game.data.trainers[class]
    local partyIndex = love.math.random(#rec.parties)
    local tag = ("%02d_%s_%s"):format(i, place[1]:lower(), class:lower())

    U.teleport(game, place[1], place[2], place[3], "down")
    -- let the neighbourhood's meshes land before the fight starts, so the
    -- first battle frame is not the flat fallback
    U.wait(90)

    local battle = BattleState.newTrainer(game, class, partyIndex)
    battle.onFinish = function() end
    game.overworld:pushBattle(battle)

    -- the wipe, then the send-out chatter
    U.wait(70)
    for _ = 1, 14 do U.tap(game, "a"); U.wait(8) end
    U.log(label(place, class))
    U.shot(game, ("%s/%s_1_menu.png"):format(DIR, tag))

    -- FIGHT -> first move -> the animation
    U.tap(game, "a")
    U.wait(12)
    U.tap(game, "a")
    U.wait(24)
    U.shot(game, ("%s/%s_2_anim.png"):format(DIR, tag))

    -- and a while later, where the drift has moved the world under them
    U.wait(240)
    U.shot(game, ("%s/%s_3_drift.png"):format(DIR, tag))

    -- out of the battle and on to the next: pop whatever is above the
    -- overworld rather than trying to play the fight to its end
    while game.stack:top() and game.stack:top() ~= game.overworld do
      game.stack:pop()
    end
    U.wait(10)
  end

  U.log("done -- " .. DIR)
end
