-- Driver: Gen 2 trainer prize money, POKeGEAR call scripts, specialphonecall.
--
-- ComputeTrainerReward (0E:$58D4) sets wBattleReward = the class's base reward
-- byte times the last party mon's level, but WinTrainerBattle (0F:$4F46) then
-- pays that out FOUR times -- b quarters to Mom, the rest to the wallet -- so
-- the port's single helping was a quarter of the real payout.
--
-- The same window wires the two `dba`s on every PhoneContacts row (the script
-- that runs when you ring a contact and the one that runs when they ring you)
-- and SpecialPhoneCallList, the table `specialphonecall` indexes -- which is
-- what makes Elm ring about the egg once Falkner is beaten.
--
--   POKEPORT_VERSION=gold \
--     POKEPORT_DRIVER=tests/drivers/gen2_prize_call_test.lua love .
return function(game)
  local U = require("tests.drivers.util")
  local Gen2Commands = require("src.script.Gen2Commands")
  local Commands = require("src.script.Commands")
  local pass, fail = 0, 0
  local function ck(label, ok, got)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label, got ~= nil and tostring(got) or "")
  end

  U.newGame(game)
  U.wait(30)

  -- ---------------------------------------------------------------- prizes
  local sage = game.data.trainers.OPP_SAGE
  ck("SAGE carries TrainerClassAttributes' base reward of 8",
     sage and sage.baseMoney == 8, sage and sage.baseMoney)
  -- Sprout Tower: CHOW/NICO/EDMOND field level 3 Bellsprouts, JIN and NEAL a
  -- single level 6, and ELDER LI closes on a level 10 Hoothoot.
  local levels = {}
  for i, party in ipairs(sage.parties or {}) do
    levels[i] = party[#party] and party[#party].level
  end
  ck("NICO's last mon is level 3", levels[2] == 3, levels[2])
  ck("JIN's last mon is level 6", levels[3] == 6, levels[3])
  ck("LI's last mon is level 10", levels[9] == 10, levels[9])

  -- ------------------------------------------------------------ call scripts
  local pool = game.data.map_scripts
  local elmCall = Gen2Commands.phoneCallScript(game.data, 4)
  local elmRing = Gen2Commands.phoneReceiveScript(game.data, 4)
  ck("PROF.ELM has a script for the call you place",
     type(elmCall) == "table" and #elmCall > 0)
  ck("PROF.ELM has a script for the call he places",
     type(elmRing) == "table" and #elmRing > 0)
  ck("the two are not the same script", elmCall ~= elmRing)
  ck("MOM has a script for the call you place",
     type(Gen2Commands.phoneCallScript(game.data, 1)) == "table")
  -- pokecrystal's phone_contact macro puts the callee script first, so the
  -- SECOND dba is the caller script SpecialPhoneCallList also points at
  ck("ELM's caller script is the one SpecialPhoneCallList fires",
     pool.phone[4].receive == pool.specialCalls[1].script,
     tostring(pool.phone[4].receive))

  -- ----------------------------------------------------------- special calls
  ck("SpecialPhoneCallList was extracted", type(pool.specialCalls) == "table")
  ck("SPECIALCALL_NONE leaves no row 0", pool.specialCalls[0] == nil)
  ck("call 1 (post-Falkner) is PROF.ELM, outdoors only",
     pool.specialCalls[1] and pool.specialCalls[1].caller == 4
       and pool.specialCalls[1].outside == true)
  ck("call 6 is the BIKE SHOP", pool.specialCalls[6]
       and pool.specialCalls[6].caller == 2,
     pool.specialCalls[6] and pool.specialCalls[6].caller)
  ck("call 7 is MOM", pool.specialCalls[7]
       and pool.specialCalls[7].caller == 1,
     pool.specialCalls[7] and pool.specialCalls[7].caller)

  local ctx = { save = game.save, game = game }
  Commands.g2_special_call(ctx, 1)
  ck("specialphonecall arms the call", game.save.g2SpecialCall == 1)
  local caller, script = Gen2Commands.pendingSpecialCall(game.data, game.save,
    false)
  ck("an outdoors-only call is held back indoors", caller == nil)
  caller, script = Gen2Commands.pendingSpecialCall(game.data, game.save, true)
  ck("and rings once you are outside",
     caller == 4 and type(script) == "table" and #script > 0)
  Commands.g2_special_call(ctx, 0)
  ck("SPECIALCALL_NONE cancels it", game.save.g2SpecialCall == nil)

  U.log(("RESULT %s (%d pass, %d fail)"):format(
    fail == 0 and "PASS" or "FAIL", pass, fail))
  love.event.quit()
end
