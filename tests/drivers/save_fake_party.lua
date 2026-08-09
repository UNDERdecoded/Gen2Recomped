-- One-shot: injects a fake 3-mon party and writes it to disk for the
-- current identity, then exits. Meant to be followed by a normal
-- (driver-free) `love .` launch, since POKEPORT_DRIVER disables Discord
-- presence for the run -- this is how to get a ready-made party AND a
-- fully interactive session with real Discord presence.
return function(game)
  local Pokemon = require("src.pokemon.Pokemon")
  local SaveData = require("src.core.SaveData")

  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 50),
    Pokemon.new(game.data, "PIKACHU", 30),
    Pokemon.new(game.data, "SNORLAX", 40),
  }
  game.save.player.name = "RED"

  local ok = SaveData.save(game.save)
  print("save_fake_party: saved =", ok)
end
