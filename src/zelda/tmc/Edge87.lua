-- Round 87: no room change in the middle of a jump (src/player.c PlayerNormal, src/scroll.c
-- UpdateDoorTransition, src/beanstalkSubtask.c UpdatePlayerCollision).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * PlayerNormal calls UpdatePlayerCollision -- the only place a walk into the room's border (collision $FF
--     ahead, sub_0807BDB8 / sub_0807BD14: the neighbouring room's scroll) or into a border / area exit of the
--     room's list (DoApplicableTransition) is taken -- only while gPlayerState.jump_status == 0.
--   * UpdateDoorTransition (the stairs / door act tiles' area exits) returns at once while jump_status != 0.
--   * CreateCollisionDataBorderAroundRoom sets the column / row just past the room to collision $FF on both
--     layers, so a Roc's Cape jump or glide that reaches the room's edge is stopped there and comes down in
--     this room ($70:0F's east island: a glide east off the 8-cloud stack does not carry Link into $70:10).
-- The port's jump (ItemCape / Trapdoor81: player.jump) stands for jump_status != 0.
-- SIMPLIFIED: the parachute (PlayerParachute) and the scripted moves keep the port's old rule.
local M = {}

-- true while Link is in a jump (jump_status != 0): Field:checkExits takes no edge / door / area exit
function M.airborne(f, p)
  return p ~= nil and p.jump ~= nil
end

return M
