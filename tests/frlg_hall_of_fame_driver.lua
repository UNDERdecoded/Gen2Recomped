-- Visible FireRed Hall of Fame ceremony. Save writes are vetoed so this can
-- exercise the native Gen 3 induction without changing the player's real save.
return function(game)
  local U = require("tests.drivers.util")
  local Pokemon = require("src.pokemon.Pokemon")
  game.writeSave = function() return false end
  local save = U.freshSave(game)
  save.party = { Pokemon.new(game.data, "MEWTWO", 100) }
  -- Champion's real warp lands here; the map's own ON_FRAME script walks the
  -- player to Oak, records the team and hands off to the credits.
  U.teleport(game, "MAP_G01_N80", 5, 12, "up")
  for frame = 1, 9000 do
    if frame % 8 == 1 then U.tap(game, "a") else U.wait(1) end
    if save.flags.FLAG_G3_082C and (tonumber(save.hallOfFame) or 0) >= 1 then
      U.log("PASS native FireRed Hall of Fame induction")
      love.event.quit(0)
      return
    end
  end
  error("Hall of Fame induction did not start")
end
