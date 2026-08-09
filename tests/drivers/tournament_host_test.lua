-- Driver: hosts a real 2-player tournament against a real running
-- pokeserver, paired with tournament_guest_test.lua running in a second
-- LOVE process. Coordinates over a shared code file (TOURNEY_CODE_FILE)
-- since the two processes have no other way to talk before the code
-- exists. The default tournament rule is exactly 3 Pokemon, so this
-- overwrites whatever party the identity actually has with 3 fixed mons
-- -- a tournament match never touches the real save (clamped copies, same
-- as any other link battle), so clobbering it here for the test is safe.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots_tourney"
  local CODE_FILE = os.getenv("TOURNEY_CODE_FILE") or "/tmp/tourney_code.txt"
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")

  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 50),
    Pokemon.new(game.data, "PIKACHU", 30),
    Pokemon.new(game.data, "SNORLAX", 40),
  }
  game.save.player.name = "RED"

  local Tournament = require("src.link.Tournament")
  local t = Tournament.new(game)
  game.stack:push(t)
  U.wait(3)

  U.shot(game, DIR .. "/host_0_menu.png")
  U.tap(game, "a"); U.wait(3) -- HOST -> hostSettings
  U.shot(game, DIR .. "/host_1_settings.png")
  U.tap(game, "start"); U.wait(30) -- create with defaults (3 mons, any/any, 6s)
  U.shot(game, DIR .. "/host_2_hosting.png")
  U.log("host code:", t.code, "error:", t.net and t.net.error)

  local f = io.open(CODE_FILE, "w")
  if f then f:write(t.code or ""); f:close() end

  local waited = 0
  while #t.roster < 2 and waited < 1800 do
    U.wait(1)
    waited = waited + 1
  end
  U.log("host roster:", table.concat(t.roster, ","))
  U.shot(game, DIR .. "/host_3_roster.png")

  U.tap(game, "a"); U.wait(1) -- start_tournament
  U.shot(game, DIR .. "/host_4_bracket.png")

  local doneWait = 0
  while t.stage ~= "done" and doneWait < 5400 do
    U.tap(game, "a")
    U.wait(2)
    doneWait = doneWait + 1
  end
  U.shot(game, DIR .. "/host_5_done.png")
  U.log("TOURNAMENT_HOST_DRIVER: champion=", t.champion, "stage=", t.stage)
end
