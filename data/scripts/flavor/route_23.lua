-- Route 23's badge-gate guards (pokered scripts/Route23.asm).  Each
-- guard/swimmer stands beside the staircase to Victory Road and, when
-- talked to, checks whether the player holds the badge matching that
-- step; the automatic walk-into-the-guard blocking script
-- (Route23DefaultScript / Route23CheckForBadgeScript) is not ported
-- here -- only the talk-triggered text_asm bodies, which share that
-- same subroutine (Route23CheckForBadgeScript) and text
-- (Route23YouDontHaveTheBadgeYetText / Route23OhThatIsTheBadgeText,
-- pokered/text/Route23.asm _Route23YouDontHaveTheBadgeYetText /
-- _Route23OhThatIsTheBadgeText).  Once shown the badge, pokered sets
-- EVENT_PASSED_<BADGE>_CHECK so the walk-through gate (when ported)
-- won't re-ask; we mirror that with set_flag for fidelity even though
-- no onStep gate currently reads it.

local M = {}

-- rows: check_item(badge) -> have it? show "Oh! That is the X!" and
-- set EVENT_PASSED_X_CHECK : show "You don't have the X yet!"
local function badgeGuard(badge, passFlag)
  local subs = { RAM = badge }
  return {
    { "check_item", badge },                                        -- 1
    { "jump_if_true", 5 },                                          -- 2
    { "show_text", "_Route23YouDontHaveTheBadgeYetText", subs },     -- 3
    { "jump", 7 },                                                  -- 4 (end)
    { "show_text", "_Route23OhThatIsTheBadgeText", subs },          -- 5
    { "set_flag", passFlag },                                       -- 6
  }
end

-- Route23SetVictoryRoadBoulders (pokered scripts/Route23.asm:8): every entry
-- to Route 23 resets the Victory Road boulder puzzle behind you.  The 2F/3F
-- switch events clear (so those barriers are closed again on the next floor
-- load) and the boulder that fell through 3F's hole goes back upstairs:
-- ShowObject TOGGLE_VICTORY_ROAD_3F_BOULDER / HideObject
-- TOGGLE_VICTORY_ROAD_2F_BOULDER, which are VICTORYROAD3F_BOULDER4 and
-- VICTORYROAD2F_BOULDER3 (data/maps/toggleable_objects.asm).  1F's event is
-- reset by the Indigo Plateau lobby and by Victory Road 2F, not here.  This
-- is what makes the puzzle "completely reset" on a return trip (#258).
-- onEnter is the port's BIT_CUR_MAP_LOADED_2 equivalent: setMap runs it on
-- every map entry, connection crossings included, like EnterMap.
M.ROUTE_23 = {
  onEnter = function(game, ow)
    local f = game.save.flags
    f.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH1 = nil
    f.EVENT_VICTORY_ROAD_2_BOULDER_ON_SWITCH2 = nil
    f.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH1 = nil
    f.EVENT_VICTORY_ROAD_3_BOULDER_ON_SWITCH2 = nil
    local Commands = require("src.script.Commands")
    local ctx = { save = game.save, overworld = ow, game = game }
    Commands.show_object(ctx, "VICTORY_ROAD_3F", "VICTORYROAD3F_BOULDER4")
    Commands.hide_object(ctx, "VICTORY_ROAD_2F", "VICTORYROAD2F_BOULDER3")
  end,
  talk = {
    -- Route23Guard1Text: EventFlagBit ..., EVENT_PASSED_EARTHBADGE_CHECK
    -- -> wWhichBadge = EARTHBADGE
    TEXT_ROUTE23_GUARD1 = badgeGuard("EARTHBADGE", "EVENT_PASSED_EARTHBADGE_CHECK"),
    -- Route23Guard2Text: EVENT_PASSED_VOLCANOBADGE_CHECK
    TEXT_ROUTE23_GUARD2 = badgeGuard("VOLCANOBADGE", "EVENT_PASSED_VOLCANOBADGE_CHECK"),
    -- Route23Guard3Text: EVENT_PASSED_RAINBOWBADGE_CHECK
    TEXT_ROUTE23_GUARD3 = badgeGuard("RAINBOWBADGE", "EVENT_PASSED_RAINBOWBADGE_CHECK"),
    -- Route23Guard4Text: EVENT_PASSED_THUNDERBADGE_CHECK
    TEXT_ROUTE23_GUARD4 = badgeGuard("THUNDERBADGE", "EVENT_PASSED_THUNDERBADGE_CHECK"),
    -- Route23Guard5Text: EVENT_PASSED_CASCADEBADGE_CHECK
    TEXT_ROUTE23_GUARD5 = badgeGuard("CASCADEBADGE", "EVENT_PASSED_CASCADEBADGE_CHECK"),
    -- Route23Swimmer1Text: EVENT_PASSED_MARSHBADGE_CHECK
    TEXT_ROUTE23_SWIMMER1 = badgeGuard("MARSHBADGE", "EVENT_PASSED_MARSHBADGE_CHECK"),
    -- Route23Swimmer2Text: EVENT_PASSED_SOULBADGE_CHECK
    TEXT_ROUTE23_SWIMMER2 = badgeGuard("SOULBADGE", "EVENT_PASSED_SOULBADGE_CHECK"),
  },
}

return M
