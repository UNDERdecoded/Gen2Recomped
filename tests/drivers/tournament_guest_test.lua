-- Driver: joins the tournament tournament_host_test.lua creates, reading
-- the code from a shared file since the two LOVE processes otherwise
-- can't coordinate. Meant for a fresh throwaway POKEPORT_IDENTITY, so it
-- injects a test party directly (mirroring run_link_tests.lua's
-- makeFakeGame) rather than playing through a whole new-game intro.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots_tourney"
  local CODE_FILE = os.getenv("TOURNEY_CODE_FILE") or "/tmp/tourney_code.txt"
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")

  -- the default tournament rule is exactly 3 Pokemon; overwrite whatever
  -- this identity's party actually is (safe: a match uses clamped copies)
  local Pokemon = require("src.pokemon.Pokemon")
  game.save.party = {
    Pokemon.new(game.data, "BLASTOISE", 50),
    Pokemon.new(game.data, "GENGAR", 35),
    Pokemon.new(game.data, "ALAKAZAM", 45),
  }
  game.save.player.name = "BLUE"

  local CodeEntry = require("src.link.CodeEntry")
  local Tournament = require("src.link.Tournament")
  local t = Tournament.new(game)
  game.stack:push(t)
  U.wait(3)

  local code = nil
  local waited = 0
  while not code and waited < 1800 do
    local f = io.open(CODE_FILE, "r")
    if f then
      local c = f:read("*l")
      f:close()
      if c and #c == 6 then code = c end
    end
    U.wait(1)
    waited = waited + 1
  end
  U.log("guest read code:", code)
  if not code then
    U.log("TOURNAMENT_GUEST_DRIVER: never saw a code, aborting")
    return
  end

  U.tap(game, "down"); U.wait(2) -- JOIN row
  U.tap(game, "a"); U.wait(3) -- into codeEntry
  U.shot(game, DIR .. "/guest_0_code_entry.png")
  for i = 1, CodeEntry.LENGTH do
    local idx = CodeEntry.CHARSET:find(code:sub(i, i), 1, true)
    if idx then t.codeEntry.chars[i] = idx end
  end
  U.tap(game, "a"); U.wait(3) -- confirm -> startJoining
  U.shot(game, DIR .. "/guest_1_joining.png")

  waited = 0
  while #t.roster == 0 and t.stage ~= "done" and waited < 1800 do
    U.wait(1)
    waited = waited + 1
  end
  U.log("guest roster:", table.concat(t.roster or {}, ","))
  U.shot(game, DIR .. "/guest_2_roster.png")

  local doneWait = 0
  while t.stage ~= "done" and doneWait < 5400 do
    U.tap(game, "a")
    U.wait(2)
    doneWait = doneWait + 1
  end
  U.shot(game, DIR .. "/guest_3_done.png")
  U.log("TOURNAMENT_GUEST_DRIVER: champion=", t.champion, "stage=", t.stage)
end
