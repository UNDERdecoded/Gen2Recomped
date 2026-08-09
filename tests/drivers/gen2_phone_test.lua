-- Driver: Gen 2 POKeGEAR phone book.
--
-- addcellnum / askforphonenumber register a PHONE_* id in wPhoneList, and the
-- POKeGEAR resolves each id through PhoneContacts (36:$443A) -- trainer class
-- plus trainer id for a trainer, NonTrainerCallerNames (36:$43CD) for MOM,
-- BIKE SHOP, BILL and PROF.ELM.  The port wrote save.g2Phone but the card only
-- ever read save.phone, so every playthrough showed MOM and nothing else.
--
--   POKEPORT_VERSION=gold \
--     POKEPORT_DRIVER=tests/drivers/gen2_phone_test.lua love .
return function(game)
  local U = require("tests.drivers.util")
  local Gen2Commands = require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  local PokegearMenu = require("src.ui.PokegearMenu")
  local pass, fail = 0, 0
  local function ck(label, ok, got)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label, got ~= nil and tostring(got) or "")
  end

  U.newGame(game)
  U.wait(30)

  local pool = game.data.map_scripts
  local phone = pool and pool.phone
  ck("PhoneContacts was extracted", type(phone) == "table")
  if not phone then
    U.log("RESULT FAIL (0 pass, 1 fail)")
    love.event.quit()
    return
  end

  ck("id 1 is MOM", Gen2Commands.phoneName(game.data, 1) == "MOM",
     Gen2Commands.phoneName(game.data, 1))
  ck("id 3 is BILL", Gen2Commands.phoneName(game.data, 3) == "BILL",
     Gen2Commands.phoneName(game.data, 3))
  ck("id 4 is PROF.ELM", Gen2Commands.phoneName(game.data, 4) == "PROF.ELM",
     Gen2Commands.phoneName(game.data, 4))
  -- row 5 is trainer class 23 (SCHOOLBOY), trainer 1
  local jack, jackClass = Gen2Commands.phoneName(game.data, 5)
  ck("id 5 resolves a trainer name out of the roster",
     type(jack) == "string" and jack ~= "" and jackClass == "SCHOOLBOY",
     tostring(jack) .. " / " .. tostring(jackClass))
  ck("the unused rows are dropped", phone[0] == nil and phone[8] == nil)

  -- addcellnum PHONE_ELM, exactly as the lab script issues it
  local ctx = { save = game.save, game = game }
  Commands.g2_cellnum(ctx, 4, true)
  ck("addcellnum registers the id", game.save.g2Phone[4] == true)

  local gear = PokegearMenu.new(game)
  local list = gear:contacts()
  local names = {}
  for _, entry in ipairs(list) do names[#names + 1] = entry.name end
  U.log("card shows:", table.concat(names, ", "))
  local hasElm = false
  for _, n in ipairs(names) do if n == "PROF.ELM" then hasElm = true end end
  ck("the card lists the registered number", hasElm)
  ck("no hard-coded MOM placeholder is left in the list",
     list[#list].text == nil)

  Commands.g2_cellnum(ctx, 1, true)
  Commands.g2_cellnum(ctx, 5, true)
  list = gear:contacts()
  ck("more numbers stack up, in id order", #list == 3
     and list[1].name == "MOM" and list[2].name == "PROF.ELM",
     #list)

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit()
end
