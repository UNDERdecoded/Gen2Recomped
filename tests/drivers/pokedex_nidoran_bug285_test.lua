-- Driver: Pokedex owned-ball alignment for NIDORAN (#285).  Eye check.
-- The ball goes one blank glyph past the name, but ListMenu measured that
-- gap with `#item.label` (bytes) and the charmap's gender symbols are
-- multi-byte UTF-8, so those two rows sat 16px right.  src/render/Font.lua
-- warns about `#text * 8`.  No POKEPORT_SPEED, rendering is real-time.
--   POKEPORT_DRIVER=tests/drivers/pokedex_nidoran_bug285_test.lua POKEPORT_IDENTITY=bug285 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Font = require("src.render.Font")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- an empty dex shows no balls at all, which looks the same as balls in
  -- the wrong place; the gender-free neighbours are the control column
  local dexRow = { "NIDORAN_F", "NIDORINA", "NIDOQUEEN",
                   "NIDORAN_M", "NIDORINO", "NIDOKING" }

  game.save.pokedex = game.save.pokedex or { seen = {}, owned = {} }
  for _, id in ipairs(dexRow) do
    game.save.pokedex.seen[id] = true
    game.save.pokedex.owned[id] = true
  end
  game.save.party = { Pokemon.new(game.data, "NIDORAN_M", 10) }
  game.save.player.name = "bryan"

  for _, id in ipairs(dexRow) do
    check("owned: " .. id, game.save.pokedex.owned[id] == true)
  end

  -- byte length and glyph width disagree for exactly these two rows
  local male = game.data.pokemon.NIDORAN_M.name
  local plain = game.data.pokemon.NIDORINO.name
  U.log("NIDORAN male name:", male, "bytes:", #male, "glyph width:", Font.width(male))
  check("gender name is multi-byte (this is the whole bug)",
        #male > Font.width(male) / 8)
  check("a plain neighbour agrees byte-for-glyph",
        #plain == Font.width(plain) / 8)

  check("renderer is up", game.renderer ~= nil)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)

  Screens.push(game, "PokedexMenu")
  U.wait(30)

  -- the list shows seven rows with the cursor on the last, so stop at dex
  -- 35: that puts 029-035 in view, both Nidoran rows plus their neighbours
  for _ = 1, 34 do
    U.tap(game, "down")
    U.wait(2)
  end
  U.wait(20)
  U.shot(game, "bug285_pokedex_nidoran.png")

  U.log("Pokedex is parked on the NIDORAN block; the shot is")
  U.log("bug285_pokedex_nidoran.png in the LOVE save dir.  Every ball should")
  U.log("sit exactly one space after its name, so the two NIDORAN rows line")
  U.log("up with their gender-free neighbours (#285 kicked them two right).")

  while true do
    coroutine.yield()
  end
end
