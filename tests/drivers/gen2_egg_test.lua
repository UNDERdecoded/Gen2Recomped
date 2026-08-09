-- Driver: Gen2 eggs are eggs, not battle-ready party members.
--
-- `giveegg` (Elm's aide, post-Falkner) hands over a party slot with the
-- is_egg bit set; CheckFirstMonIsEgg (01:$728B) keeps it out of battle and
-- DayCareStep.check_egg (01:$73A2) walks its hatch counter down.
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_egg_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Party = require("src.pokemon.Party")
  local Commands = require("src.script.Commands")

  local pass, fail = 0, 0
  local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "PASS " or "FAIL ") .. what)
  end

  U.newGame(game)
  U.wait(20)

  local save = game.save
  save.party = { Pokemon.new(game.data, "SPECIES_155", 20) }
  Commands.g2_give_egg({ game = game, save = save }, "SPECIES_175", 5)

  local egg = save.party[2]
  check(egg ~= nil and egg.isEgg == true, "giveegg adds an EGG slot")
  check(egg and egg.nickname == "EGG", "the slot is named EGG")
  check(Party.isEgg(egg), "Party.isEgg recognises it")

  local lead = Party.firstHealthy(save.party)
  check(lead == save.party[1], "firstHealthy skips the EGG")

  save.party = { egg }
  check(Party.firstHealthy(save.party) == nil,
    "a party of only EGGs has nothing healthy")

  -- walk it out: every completed step decrements the hatch counter
  save.party = { Pokemon.new(game.data, "SPECIES_155", 20), egg }
  egg.eggSteps = 3
  local ow = game.overworld
  local before = egg.eggSteps
  for _ = 1, 6 do
    ow:onStepComplete()
    if not egg.isEgg then break end
  end
  check(egg.eggSteps ~= before, "steps decrement the hatch counter")
  check(egg.isEgg == nil, "the EGG hatched")
  check(egg.nickname == nil, "the hatchling drops the EGG name")
  check(egg.species == "SPECIES_175", "it hatched into the stored species")
  check(Party.firstHealthy({ egg }) == egg, "the hatchling can battle")

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit()
end
