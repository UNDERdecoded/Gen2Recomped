-- Hand-ported from pokegold maps/PlayersHouse1F.asm.
-- Mom stops the player on the way back downstairs once Elm has handed over
-- a partner and gives the POKéGEAR.  The GEAR is not a bag item in Gen2 --
-- it is a menu feature gated on EVENT_GOT_POKEGEAR (src/ui/PokegearMenu.lua,
-- surfaced as the POKéGEAR row in the START menu) -- so giving "ITEM_005"
-- here was handing out a POKé BALL instead.

local Errand = require("data.scripts.mr_pokemons_house")

return {
  onEnter = function(game, ow, fromMapId)
    local save = game.save
    if save.flags.EVENT_GOT_POKEGEAR then return end
    -- PlayersHouse1F_MapScripts arms SCENE_PLAYERSHOUSE1F_MEET_MOM as scene 0
    -- and swaps to the noop scene afterwards, so the hand-off fires the first
    -- time the player walks down the stairs -- before Elm's errand, not after
    -- coming back with a partner.  Gating on #save.party meant the GEAR only
    -- appeared if you left the house and re-entered.
    ow:queueScript({
      { "show_text", "MomDeterminedText" },
      { "set_flag", "EVENT_GOT_POKEGEAR" },
      -- the GEAR arrives with MOM's number already in it
      { "play_sound", "Get_Key_Item" },
      { "show_text", "MomGivesPokegearText" },
    }, { onDone = function()
      Errand.registerPhone(save, "MOM",
        "Don't push yourself\ntoo hard out there!")
    end })
  end,

  talk = {
    TEXT_PLAYERS_HOUSE1_F_OBJ_001 = {
      { "face_player" },
      { "check_flag", "EVENT_GOT_POKEGEAR" },
      { "jump_if_true", "after" },
      { "show_text", "MomDeterminedText" },
      { "jump", "end" },

      { "label", "after" },
      { "show_text", "MomImportantToSaveText" },
    },
  },
}
