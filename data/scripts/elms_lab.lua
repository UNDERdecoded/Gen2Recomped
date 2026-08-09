-- Hand-ported from pokegold maps/ElmsLab.asm.  Text ids are the ROM's own
-- labels, extracted into data/generated/text.lua.
--
-- Object order comes straight from the ROM's MapEvents block:
--   1 ELM, 2 AIDE, 3 CYNDAQUIL ball, 4 TOTODILE ball, 5 CHIKORITA ball, 6 COP.
-- The three ball objects carry event flags $640-$642; setting one removes
-- that ball from the table (see the event-flag handling in
-- OverworldController.objectVisible).

local GOT_STARTER = "EVENT_G2_GOT_STARTER"
local Errand = require("data.scripts.mr_pokemons_house")

-- ElmsLabCyndaquilPokeBallScript and friends: ask, hand over the mon at
-- level 5, retire the ball, then Elm's approving line.
local function starterBall(askText, species, ballFlag)
  return {
    { "check_flag", GOT_STARTER },
    { "jump_if_true", "already" },
    { "ask", askText },
    { "jump_if_false", "declined" },
    { "give_pokemon", species, 5 },
    { "set_flag", GOT_STARTER },
    { "set_flag", ballFlag },
    { "show_text", "ChoseStarterText" },
    { "jump", "end" },

    { "label", "declined" },
    { "show_text", "DidntChooseStarterText" },
    { "jump", "end" },

    { "label", "already" },
    { "show_text", "ChoseStarterText" },
  }
end

return {
  talk = {
    -- ProfElmScript: the ask-a-favour speech, then the errand directions
    -- once the player has a partner (ElmDirectionsScript), and finally the
    -- hand-over once MR.POKéMON's EGG is in the bag (ElmAfterTheftScript).
    TEXT_ELMS_LAB_OBJ_001 = function(game, ow, npc, done)
      local flags = game.save.flags
      local rows = { { "face_player" } }

      if flags[Errand.DELIVERED] then
        rows[#rows + 1] = { "show_text", "ElmStudyingEggText" }
      elseif flags[Errand.GOT_EGG] then
        -- ElmAfterTheftScript: ELM takes the EGG off the player's hands
        rows[#rows + 1] = { "show_text", "ElmAfterTheftText1" }
        rows[#rows + 1] = { "take_item", Errand.EGG_ITEM, 1 }
        rows[#rows + 1] = { "set_flag", Errand.DELIVERED }
        rows[#rows + 1] = { "show_text", "ElmAfterTheftText2" }
        rows[#rows + 1] = { "show_text", "ElmAfterTheftText3" }
        rows[#rows + 1] = { "show_text", "ElmsLabMonEggText" }
      elseif flags[GOT_STARTER] then
        rows[#rows + 1] = { "show_text", "ElmDirectionsText1" }
        rows[#rows + 1] = { "show_text", "ElmDirectionsText2" }
        rows[#rows + 1] = { "show_text", "ElmDirectionsText3" }
        rows[#rows + 1] = { "show_text", "ElmDescribesMrPokemonText" }
      else
        rows[#rows + 1] = { "show_text", "ElmText_Intro" }
      end

      ow.runner:run(rows, { npc = npc, onDone = function()
        -- ElmText_CallYou: the errand is what puts ELM on the POKéGEAR
        if flags[GOT_STARTER] then
          Errand.registerPhone(game.save, "PROF.ELM",
            "How is that #MON\nof yours doing?")
        end
        if done then done() end
      end })
    end,

    TEXT_ELMS_LAB_OBJ_003 =
      starterBall("TakeCyndaquilText", "SPECIES_155", "EVENT_G2_1600"),
    TEXT_ELMS_LAB_OBJ_004 =
      starterBall("TakeTotodileText", "SPECIES_158", "EVENT_G2_1601"),
    TEXT_ELMS_LAB_OBJ_005 =
      starterBall("TakeChikoritaText", "SPECIES_152", "EVENT_G2_1602"),
  },
}
