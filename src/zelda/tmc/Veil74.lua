-- Round 74: Veil Falls -- the Source of the Flow (npc4E.c type 11, script_NPC4ESourceOfTheFlow).
--
-- CARTRIDGE BEHAVIOUR (src/npc/npc4E.c, data/scripts/veilFalls/*):
--   * sub_0806DB84 (the NPC's first script call) creates two MINISH_VILLAGE_OBJECTs (types 4 / 5) 8 px left /
--     right of it; their scripts are the two words of the function's literal pool ($0806DBEC / $0806DBF0):
--     script_MinishVillageObjectLeftStoneOpening / ...RightStoneOpening.  Not fused: each waits for sync flag 1 / 2,
--     then walks 0x80 west / east at speed $20 and sets sync flag 8 / 4.  Fused: they jump to the opened stones.
--   * The King's Golden Kinstone fused (KINSTONE_SOURCE_FLOW) -> the NPC's script falls through into
--     script_NPC4ESouurceOfTheFlowOpening: SetSyncFlag 3, WaitForSyncFlagAndClear $C, the screen shake, SFX_SECRET,
--     Ezlo's TEXT_EZLO $1F.
-- Port gap fixed: Natives40's sub_0806DB84 read the literal pool through the script memory (scripts.bin), which
-- does not hold code: both stones got script 0, never moved, and the NPC waited on sync flag $C for ever (the
-- Veil Falls caves' door stayed shut after the fusion).  The two words are read from the player's ROM at import
-- (RomTables "Veil74.STONE_SCRIPTS").
--   * sub_StateChange_VeilFalls_Main (roomInit.c; sub_unk1_VeilFalls_Main the same): WINDCREST_VEIL_FALLS (bit 25)
--     clear -> LoadRoomEntityList(gUnk_080F9304) (the WINDCREST object, script_Windcrest).
-- Port gap fixed: Veil Falls had no room code -- its Wind Crest never appeared (one entry in R27B.MODULES).
local bit = require("bit")
local band, lshift = bit.band, bit.lshift

local M = {}

M.AREA, M.ROOM = 0x0A, 0x00
M.WINDCREST_VEIL_FALLS = 25
M.LIST_WINDCREST = 0x080F9304

function M.roomInit(f)
  local r = f.room
  if not r or r.area ~= M.AREA or r.room ~= M.ROOM then return end
  if band(f.save and f.save.windcrests or 0, lshift(1, M.WINDCREST_VEIL_FALLS)) == 0 then f:loadEntityList(M.LIST_WINDCREST) end
end

function M.stoneScript(i)
  local ok, t = pcall(require("src.zelda.tmc.RomTables").t, "Veil74.STONE_SCRIPTS")
  if not ok or not t then return 0 end
  local ok2, v = pcall(function() return t[i] end)
  return ok2 and v or 0
end

return M
