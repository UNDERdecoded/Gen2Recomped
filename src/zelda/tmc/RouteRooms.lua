-- Round 10: room code (src/roomInit.c sub_StateChange_*) for rooms on the
-- new-game route after the castle.  Registered into RoomCode's table by
-- RoomCode.lua itself (require("src.zelda.tmc.RouteRooms")(RoomCode)).
local ITEM_JABBERNUT = 0x5B
local bit = require("bit")

return function(RoomCode)
  -- sub_StateChange_MinishHouseInteriors_BarrelMinish (area $20 room 9):
  -- the Jabber Nut on the floor until Link has it, the barrel Minish after.
  -- Round 38: the DRUG_* lists (the Pico Blooms of the side beds and the
  -- top row): uVar1 by the DRUG flags; DRUG_COUNT with sub_08060354 (kills
  -- since the Minish took the bottle >= 5 / 10 / 15) sets room flag 0 and
  -- shows the next bloom growing (the Minish's script, ForestMinish10).
  local DRUG_1, DRUG_2, DRUG_3, DRUG_COUNT = 0x3B, 0x3C, 0x3D, 0x54
  local function drugReady(f) -- sub_08060354
    local n = ((f.save.stats and f.save.stats.kills) or 0) - (f.save.drugKillCount or 0)
    if not f:flag("global", DRUG_1) then return n > 4 end
    if not f:flag("global", DRUG_2) then return n > 9 end
    if not f:flag("global", DRUG_3) then return n > 14 end
    return false
  end
  RoomCode.drugReady = drugReady
  local LISTS = { { 0x8000, 0x080DAB84 }, { 0x4000, 0x080DAC54 }, { 0x2000, 0x080DAD24 }, { 0x1000, 0x080DABC4 },
    { 0x800, 0x080DAC94 }, { 0x400, 0x080DAD64 }, { 0x200, 0x080DAC04 }, { 0x100, 0x080DACD4 }, { 0x80, 0x080DADA4 } }
  RoomCode.register(0x20, 0x09, function(f)
    if f:inventory(ITEM_JABBERNUT) == 0 then f:loadEntityList(0x080DAB44)
    else f:loadEntityList(0x080DAB64) end
    local g = function(n) return f:flag("global", n) end
    local u
    if g(DRUG_COUNT) and drugReady(f) then
      f:setFlag("room", 0, true)
      if not g(DRUG_1) then u = 0x3200 elseif not g(DRUG_2) then u = 0x4600 else u = 0x4880 end
    elseif g(DRUG_3) then u = 0x4900
    elseif g(DRUG_2) then u = 0x4A00
    elseif g(DRUG_1) then u = 0x5200
    else u = 0x9200 end
    for _, l in ipairs(LISTS) do
      if bit.band(u, l[1]) ~= 0 then f:loadEntityList(l[2]) end
    end
  end)
end
