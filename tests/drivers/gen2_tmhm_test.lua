-- Driver: Gen2 TMs and HMs teach their move.
--
-- TMHMMoves (4:$5A66) maps machine slot -> move and the 8-byte bitfield that
-- closes every BaseData row says who may learn it (CanLearnTMHMMove).  The
-- Gen2 extractor emitted neither, so every TM/HM in the bag did nothing.
--
--   POKEPORT_VERSION=gold POKEPORT_DRIVER=tests/drivers/gen2_tmhm_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local ItemEffects = require("src.inventory.ItemEffects")

  local pass, fail = 0, 0
  local function check(ok, what)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log((ok and "PASS " or "FAIL ") .. what)
  end

  U.newGame(game)
  U.wait(20)

  local items = game.data.items
  local function byKey(key)
    for id, def in pairs(items) do
      if def.key == key then return id, def end
    end
  end

  local machines = 0
  for _, def in pairs(items) do
    if def.machine and def.machine.move then machines = machines + 1 end
  end
  check(machines == 57, "57 machine items (got " .. machines .. ")")

  local tm01, tm01def = byKey("TM_01")
  check(tm01def and tm01def.machine
    and tm01def.machine.move == "DYNAMICPUNCH", "TM01 teaches DYNAMICPUNCH")
  local hm01, hm01def = byKey("HM_01")
  check(hm01def and hm01def.machine and hm01def.machine.kind == "HM"
    and hm01def.machine.move == "CUT", "HM01 teaches CUT")
  local hm06, hm06def = byKey("HM_06")
  check(hm06def and hm06def.machine
    and hm06def.machine.move == "WHIRLPOOL", "HM06 teaches WHIRLPOOL")

  local learnsets = 0
  for _, def in pairs(game.data.pokemon) do
    if type(def.tmhm) == "table" and #def.tmhm > 0 then
      learnsets = learnsets + 1
    end
  end
  check(learnsets > 200, "species carry tmhm lists (" .. learnsets .. ")")

  -- SPECIES_001 = BULBASAUR: learns CUT (HM01), never DYNAMICPUNCH (TM01)
  local bulba = game.data.pokemon.SPECIES_001
  local function knows(list, move)
    for _, m in ipairs(list or {}) do if m == move then return true end end
    return false
  end
  check(knows(bulba.tmhm, "CUT"), "BULBASAUR can learn CUT")
  check(not knows(bulba.tmhm, "DYNAMICPUNCH"),
    "BULBASAUR cannot learn DYNAMICPUNCH")

  local mon = Pokemon.new(game.data, "SPECIES_001", 20)
  mon.moves = { mon.moves[1] }
  local result, payload = ItemEffects.use(game.data, game.save, hm01, mon)
  check(result == "learnkept" and payload == "CUT",
    "HM01 on BULBASAUR returns learnkept CUT (got " .. tostring(result) .. ")")

  local badResult = ItemEffects.use(game.data, game.save, tm01, mon)
  check(badResult == "failed", "TM01 on BULBASAUR refuses (got "
    .. tostring(badResult) .. ")")

  -- SPECIES_095 = ONIX learns STRENGTH (HM04)
  local hm04 = byKey("HM_04")
  local onix = Pokemon.new(game.data, "SPECIES_095", 20)
  onix.moves = { onix.moves[1] }
  local r4, p4 = ItemEffects.use(game.data, game.save, hm04, onix)
  check(r4 == "learnkept" and p4 == "STRENGTH",
    "HM04 on ONIX returns learnkept STRENGTH (got " .. tostring(r4) .. ")")

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit()
end
