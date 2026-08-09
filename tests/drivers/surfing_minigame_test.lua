-- Driver: Summer Beach House gate + Surfing Pikachu minigame
-- (data/scripts/yellow_beach_house.lua, src/ui/SurfingMinigame.lua).
--   POKEPORT_VERSION=yellow POKEPORT_DRIVER=tests/drivers/surfing_minigame_test.lua love .
-- Talks to the Surfin' Dude without a surfing Pikachu (burger line),
-- then with one: plays a run -- paddle, jump, spin, land -- rides to
-- the results card, and checks the high score persisted; finally pokes
-- the printer for the hi-score print offer.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 50) }

  U.teleport(game, "SUMMER_BEACH_HOUSE", 2, 2, "up")
  local ow = game.overworld
  -- dude is at (2,3); stand at (2,2)... face down instead
  ow.player.facing = "down"
  U.wait(5)

  U.tap(game, "a")
  U.wait(30)
  U.shot(game, DIR .. "/surf_0_no_surf.png")
  -- close the burger line fully
  for _ = 1, 40 do
    if game.stack:top() == ow then break end
    U.tap(game, "a")
    U.wait(4)
  end
  U.log("gate without SURF done")

  -- now teach SURF and retry: mash A through pitch + YES into the game
  game.save.party[1].moves = { { id = "SURF", pp = 15 } }
  local offerShot = false
  for _ = 1, 300 do
    local top = game.stack:top()
    if top and top.seaY then break end
    if not offerShot and top ~= ow and top and top.pages then
      U.shot(game, DIR .. "/surf_1_offer.png")
      offerShot = true
    end
    U.tap(game, "a")
    U.wait(4)
  end
  local mg = game.stack:top()
  U.log("minigame running:", tostring(mg and mg.seaY ~= nil))
  if mg and mg.seaY then
    for _ = 1, 8 do U.tap(game, "a") U.wait(3) end -- paddle
    U.shot(game, DIR .. "/surf_2_ride.png")
    U.tap(game, "up")                              -- launch
    U.hold(game, "right", 30)                      -- spin
    U.shot(game, DIR .. "/surf_3_air.png")
    -- let it land and ride out the rest of the run
    for _ = 1, 4000 do
      if mg.phase == "results" then break end
      if mg.phase == "ride" and (U.frame() % 4) == 0 then
        U.tap(game, "a")
      end
      U.wait(1)
    end
    U.shot(game, DIR .. "/surf_4_results.png")
    U.log("phase:", mg.phase, "score:", mg.score,
          "hi:", tostring(game.save.surfingHighScore))
    U.tap(game, "a") -- dismiss results
    U.wait(20)
  end

  -- printer: should offer the hi-score print after surfing this visit
  U.teleport(game, "SUMMER_BEACH_HOUSE", 6, 2, "up")
  ow = game.overworld
  ow.surfedThisVisit = true
  U.wait(5)
  -- printer is a bg event on the top wall; poke the talk script directly
  local MapScripts = require("data.scripts.init")
  local handler = MapScripts.talkScript("SUMMER_BEACH_HOUSE",
                                        "TEXT_SUMMERBEACHHOUSE_PRINTER")
  U.log("printer handler:", type(handler))
  if type(handler) == "function" then
    local finished = false
    handler(game, ow, nil, function() finished = true end)
    for _ = 1, 200 do
      if finished then break end
      U.tap(game, "a")
      U.wait(4)
    end
    U.shot(game, DIR .. "/surf_5_printer.png")
    U.log("printer flow finished:", tostring(finished))
  end

  U.log("DONE")
  love.event.quit()
end
