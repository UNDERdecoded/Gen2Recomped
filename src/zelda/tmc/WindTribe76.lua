-- Round 76: the Wind Tribe tower's room code (src/roomInit.c, AREA_WIND_TRIBE_TOWER $30 / _ROOF $31).
-- None of it was ported: the tower's entrance never set WARP_EVENT_END after the great whirlwind, its two door tiles
-- (SPECIAL_TILE_114) never closed the way before that, Gregal's and the Wind Tribe's extra lists (Floor2 / Floor4) and the
-- roof's static background, its post-Palace list and AR_ALLOWS_WARP were missing.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * sub_unk3_WindTribeTower_Entrance: global KUMOTATSUMAKI and bank-1 local KUMOUE_00_CAP_0 -> SetGlobalFlag
--     (WARP_EVENT_END).
--   * sub_StateChange_WindTribeTower_Entrance (room 0): bank-1 KUMOUE_00_CAP_0 -> SetLocalFlag($90);
--     CheckKinstoneFused(KINSTONE_F) -> LoadRoomEntityList(gUnk_080F61BC); WARP_EVENT_END clear ->
--     SetTileType(SPECIAL_TILE_114, TILE_POS(7, 19) and (7, 20), LAYER_BOTTOM); SetWorldMapPos(8, 0, $1E8, $158).
--   * _Floor2 (room 1): WARP_EVENT_END clear -> gUnk_080F62E4, else SORA_ELDER_RECOVER -> gUnk_080F6324.
--   * _Floor3 (room 2): nothing.
--   * _Floor4 (room 3): local $B1 clear -> gUnk_080F6564, else gUnk_080F6584.
--   * sub_StateChange_WindTribeTowerRoof_Main: LoadStaticBackground(5); LV5_CLEAR and bank-1 local 5 clear ->
--     gUnk_080F66AC; SetWorldMapPos(8, 0, $1E8, $158); (USA) gArea.areaMetadata |= AR_ALLOWS_WARP.
-- SIMPLIFIED: SetWorldMapPos (gRoomTransition.player_status.overworld_map_x / _y) has no port field -- the map menu
-- marks Link by the current room.
local bit = require("bit")
local band, bor = bit.band, bit.bor

local M = {}

M.AREA, M.AREA_ROOF = 0x30, 0x31
M.ROOM_ENTRANCE, M.ROOM_FLOOR2, M.ROOM_FLOOR3, M.ROOM_FLOOR4 = 0, 1, 2, 3
M.KUMOTATSUMAKI, M.WARP_EVENT_END, M.LV5_CLEAR = 0x24, 0x58, 0x06 -- global
M.FLAG_BANK_1 = 0x100
M.KUMOUE_00_CAP_0 = 0xDC                                           -- bank 1 (Cloud Tops' bank)
M.LOCAL_90, M.SORA_ELDER_RECOVER, M.LOCAL_B1, M.ROOF_BANK1_5 = 0x90, 0x63, 0xB1, 5
M.KINSTONE_F = 15
M.SPECIAL_TILE_114 = 0x4072
M.DOOR_TILES = { { 7, 19 }, { 7, 20 } }
M.LIST_ENTRANCE_F, M.LIST_FLOOR2_A, M.LIST_FLOOR2_B = 0x080F61BC, 0x080F62E4, 0x080F6324
M.LIST_FLOOR4_A, M.LIST_FLOOR4_B, M.LIST_ROOF = 0x080F6564, 0x080F6584, 0x080F66AC
M.STATIC_BG_ROOF = 5
M.AR_ALLOWS_WARP = 0x80

local function bank1(f, idx) return f:flag("bank", idx, M.FLAG_BANK_1) end

-- sub_unk3_WindTribeTower_Entrance (the room's property function, before its lists)
function M.unk3Entrance(f)
  if f:flag("global", M.KUMOTATSUMAKI) and bank1(f, M.KUMOUE_00_CAP_0) then f:setFlag("global", M.WARP_EVENT_END, true) end
end

function M.closeDoor(f)
  local r = f.room
  if not (r and r.setTile) then return 0 end
  for _, t in ipairs(M.DOOR_TILES) do r:setTile(1, t[1], t[2], M.SPECIAL_TILE_114) end
  return #M.DOOR_TILES
end

-- one entry of R27B.MODULES: R26.roomInit runs it after the room's lists
function M.roomInit(f)
  local r = f.room
  if not r then return end
  if r.area == M.AREA then
    if r.room == M.ROOM_ENTRANCE then
      M.unk3Entrance(f)
      if bank1(f, M.KUMOUE_00_CAP_0) then f:setFlag("local", M.LOCAL_90, true) end
      if f.kinstoneFused and f:kinstoneFused(M.KINSTONE_F) then f:loadEntityList(M.LIST_ENTRANCE_F) end
      if not f:flag("global", M.WARP_EVENT_END) then M.closeDoor(f) end
    elseif r.room == M.ROOM_FLOOR2 then
      if not f:flag("global", M.WARP_EVENT_END) then f:loadEntityList(M.LIST_FLOOR2_A)
      elseif f:flag("local", M.SORA_ELDER_RECOVER) then f:loadEntityList(M.LIST_FLOOR2_B) end
    elseif r.room == M.ROOM_FLOOR4 then
      if not f:flag("local", M.LOCAL_B1) then f:loadEntityList(M.LIST_FLOOR4_A) else f:loadEntityList(M.LIST_FLOOR4_B) end
    end
  elseif r.area == M.AREA_ROOF and r.room == 0 then
    pcall(function() require("src.zelda.tmc.Bg3").spawn(f, { id = require("src.zelda.tmc.Bg3").STATIC, type = M.STATIC_BG_ROOF }) end)
    if f:flag("global", M.LV5_CLEAR) and not bank1(f, M.ROOF_BANK1_5) then f:loadEntityList(M.LIST_ROOF) end
    local info = r.areaInfo
    if info then info.flags = bor(info.flags or 0, M.AR_ALLOWS_WARP) end
  end
end

return M
