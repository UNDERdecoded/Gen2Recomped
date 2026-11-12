-- Round 10: room code (src/roomInit.c sub_StateChange_*) for rooms on the
-- new-game route after the castle.  Registered into RoomCode's table by
-- RoomCode.lua itself (require("src.zelda.tmc.RouteRooms")(RoomCode)).
local ITEM_JABBERNUT = 0x5B

return function(RoomCode)
  -- sub_StateChange_MinishHouseInteriors_BarrelMinish (area $20 room 9):
  -- the Jabber Nut on the floor until Link has it, the barrel Minish after.
  -- The DRUG_* (Picolyte) lists are not ported (they depend on the kill
  -- counter gSave.enemies_killed - drug_kill_count, Picolyte not ported).
  RoomCode.register(0x20, 0x09, function(f)
    if f:inventory(ITEM_JABBERNUT) == 0 then f:loadEntityList(0x080DAB44)
    else f:loadEntityList(0x080DAB64) end
  end)
end
