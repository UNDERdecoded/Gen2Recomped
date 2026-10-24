-- Imported-data smoke: real constructors, summary screens and forced wild.
return function(game)
  local U, V = require("tests.drivers.util"), require("src.core.GameVersion")
  assert(love.filesystem.getIdentity() ~= "Gen2Recomp", "use isolated identity")
  assert(os.getenv("POKEPORT_SKIP_LEGACY_MIGRATION") == "1", "disable migration")
  assert(os.getenv("POKEPORT_ISOLATED_TESTING") == "1", "use isolated wrapper")
  assert(V.get() == os.getenv("POKEPORT_VERSION"), "wrong imported version")
  local gen = V.generation()
  assert(gen == 2 or gen == 3, "identity hook smoke requires Gen 2/3")
  local title
  for _ = 1, 120 do
    local top = game.stack:top()
    if top and type(top.onNewGame) == "function" then
      title = top
      break
    end
    U.tap(game, "start")
    U.wait(5)
  end
  assert(title, "native title missing")
  title.onNewGame()
  U.wait(60)
  local world = assert(game.overworld, "native New Game missing")
  local e = assert(game.mods.exports.portable_pokemon_rolls, "install public identity example")
  assert(e.available, "identity hooks unavailable")
  local P, DayCare = require("src.pokemon.Pokemon"), require("src.pokemon.DayCare")
  local Copy = require("src.mods.Merge").deepCopy
  local species
  for id, def in pairs(game.data.pokemon) do
    if def.name == "CHARMANDER" then
      species = id
      break
    end
  end
  assert(species, "imported Charmander missing")
  game.save.options.shinyOdds = false
  e.mode = "force"
  local sequence = { 15, 0, 0, 0, 1, 255 }
  local i = 0
  local mon = P.new(game.data, species, 5, function(lo)
    i = i + 1
    return sequence[i] or lo or 0
  end)
  if gen == 3 then
    mon.otId, mon.otSecretId = 0, 0
  end
  local genes = { dvs = Copy(mon.dvs), ivs = Copy(mon.ivs), pid = mon.personality, stats = Copy(mon.stats) }
  game.save.party = { mon }
  assert(P.isShiny(mon), "native shiny reader ignored hook")
  assert(P.genderOf(game.data, mon) == "female", "native birth gender ignored hook")
  assert(e.observations["gender.roll"].species == "CHARMANDER", "species did not cross API-3 boundary")
  assert(e.observations["gender.roll"].defId == "CHARMANDER", "definition ID is not portable")
  local Screens = require("src.ui.Screens")
  game.stack.states = { world }
  Screens.push(game, "SummaryMenu", mon, {})
  U.wait(15)
  assert(game.stack:top() ~= world, "native summary did not open")
  assert(P.isShiny(mon), "summary lost shiny result")
  assert(P.genderOf(game.data, mon) == "female", "summary lost birth gender")
  U.tap(game, "b")
  U.wait(10)
  e.mode = "suppress"
  if gen == 2 then
    game.stack.states = { world }
    Screens.push(game, "SummaryMenu", mon, {})
    U.wait(15)
    assert(mon.gender == "male", "Gen-2 summary did not refresh gender")
    assert(P.isShiny(mon), "Gen-2 summary lost authoritative true shiny")
    U.tap(game, "b")
    U.wait(10)
  else
    assert(P.genderOf(game.data, mon) == "female", "GBA display lost native birth cache")
    assert(DayCare.gender(game.data, mon) == "male", "GBA native query did not evaluate hook")
    assert(not P.isShiny(mon), "GBA native shiny query did not suppress")
  end
  local actual = { dvs = mon.dvs, ivs = mon.ivs, pid = mon.personality, stats = mon.stats }
  local function equal(a, b)
    if a == b then
      return true
    end
    if type(a) ~= "table" or type(b) ~= "table" then
      return false
    end
    for k, v in pairs(a) do
      if not equal(v, b[k]) then
        return false
      end
    end
    for k in pairs(b) do
      if a[k] == nil then
        return false
      end
    end
    return true
  end
  assert(equal(actual, genes), "plain overrides/summary changed genetics or stats")
  local explicit = mon.isShiny
  if gen == 3 then
    mon.isShiny = true
  end
  local before = e.calls["shiny.roll"] or 0
  local battle = require("src.battle.BattleState").newWild(game, species, 5, { shiny = true })
  assert(P.isShiny(battle.enemy.mon), "native forced wild lost shiny precedence")
  assert((e.calls["shiny.roll"] or 0) == before, "forced wild invoked ordinary shiny callback")
  mon.isShiny = explicit
  e.stopShiny()
  e.stopGender()
  local calls = Copy(e.calls)
  if gen == 2 then
    P.syncIdentity(game.data, mon)
  end
  P.isShiny(mon)
  DayCare.gender(game.data, mon)
  assert(equal(calls, e.calls), "retired native hooks still dispatched")
  print("PORTABILITY_POKEMON_ROLL_PASS " .. V.get())
  love.event.quit(0)
end
