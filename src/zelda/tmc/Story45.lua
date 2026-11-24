-- Round 45: the story rooms between the Elemental Sanctuary and Castor Wilds
-- (an R27A module: roomInit + script natives).
--
-- PORTED (src/roomInit.c, src/cutscene.c):
--   * sub_StateChange_HyruleField_WesternWoodsNorth ($03:08): LV2_CLEAR, the
--     Red Sword and not SOUGEN_08_TORITSUKI -> gUnk_080F82E0 (the
--     CUTSCENE_ORCHESTRATOR with script_CutsceneOrchestratorTakeover: Link in
--     the region (352, 32) stops, script_PlayerAtTakeover (Ezlo's search,
--     TEXT_VAATI $18), the castle scene, Ezlo's TEXT_VAATI $1F, local
--     SOUGEN_08_TORITSUKI).
--   * sub_StateChange_CastorWilds_Main ($04:00): SetGlobalFlag(DASHBOOTS);
--     KINSTONE_5B fused -> gUnk_080D9CC8; WINDCREST_CASTOR_WILDS not active
--     -> gUnk_080D9CE8; no Pegasus Boots -> gUnk_080D9C38.
-- SIMPLIFIED: sub_08053BE8 (sub_080A71C4(5, 2, ..): the aux-room cutscene of
--   King Daltus taken over by Vaati, gUnk_080FCDE0 / gUnk_080FCE30, its own
--   scripts) is not modelled: the screen fades out and back as the
--   orchestrator's script goes on (as the intro's aux scenes, Native.lua
--   $080536A8 / $080536B8).
local Native = require("src.zelda.tmc.Native")
local N = Native.N

local M = {}

local G_LV2_CLEAR, G_DASHBOOTS = 0x03, 0x1E
local SOUGEN_08_TORITSUKI = 0x9C
local ITEM_RED_SWORD, ITEM_PEGASUS_BOOTS = 0x03, 0x15
local KINSTONE_5B, WINDCREST_CASTOR_WILDS = 0x5B, 29

local ROOMS = {}
M.ROOMS = ROOMS
ROOMS[0x0308] = function(f)
  if f:flag("global", G_LV2_CLEAR) and (f:inventory(ITEM_RED_SWORD) or 0) ~= 0 and not f:flag("local", SOUGEN_08_TORITSUKI) then
    f:loadEntityList(0x080F82E0)
  end
end
ROOMS[0x0400] = function(f)
  f:setFlag("global", G_DASHBOOTS, true)
  if f:kinstoneFused(KINSTONE_5B) then f:loadEntityList(0x080D9CC8) end
  if not require("src.zelda.tmc.Crenel").windcrest(f, WINDCREST_CASTOR_WILDS) then f:loadEntityList(0x080D9CE8) end
  if (f:inventory(ITEM_PEGASUS_BOOTS) or 0) == 0 then f:loadEntityList(0x080D9C38) end
end

-- sub_StateChange_TownMinishHoles_RemShoeShop ($2D:12): the Town Minish under
-- Rem's shop (script_RemTownMinish) and its floor
local ITEM_QST_MUSHROOM, KINSTONE_14 = 0x38, 0x14
local SPECIAL_TILE_114 = 0x4072
ROOMS[0x2D12] = function(f)
  if not f:flag("local", 0x60) then f:loadEntityList(0x080DBB50) end -- KOBITO_DOUKUTU_00_T0
  if (f:inventory(ITEM_PEGASUS_BOOTS) or 0) == 1 then
    f:loadEntityList(0x080DBB70); f:loadEntityList(0x080DBB10)
  else
    f:loadEntityList(0x080DBAD0)
  end
  if not f:flag("local", 0x62) and f.room.setTile then -- KOBITO_DOUKUTU_05_T0: TILE_POS(0, 5) + 0..18
    for i = 0, 18 do f.room:setTile(1, i, 5, SPECIAL_TILE_114) end
  end
end
-- sub_StateChange_HouseInteriors3_RemShoeShop ($23:02, not EU)
ROOMS[0x2302] = function(f)
  if (f:inventory(ITEM_QST_MUSHROOM) or 0) == 1 then f:loadEntityList(0x080F5B3C) end
end
-- sub_StateChange_TreeInteriors_WitchHut ($24:00): the Wake-Up Mushroom on sale
ROOMS[0x2400] = function(f)
  if f:kinstoneFused(KINSTONE_14) then f:loadEntityList(0x080F9FA8) end
  if (f:inventory(ITEM_QST_MUSHROOM) or 0) == 0 then f:loadEntityList(0x080F9F88) end
end

function M.roomInit(f)
  local r = f.room
  if not r then return end
  local fn = ROOMS[(r.area or 0) * 256 + (r.room or 0)]
  if fn then fn(f) end
end

-- sub_08053BE8: sub_080A71C4(5, 2, FADE_IN_OUT | FADE_INSTANT, $100) + SetFade(FADE_IN_OUT | FADE_INSTANT, $100)
if not N[0x08053BE8] then N[0x08053BE8] = function(f) f:fade("out", false, 256) end end

return M
