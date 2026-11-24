-- Round 46: Lon Lon Ranch's lost key (an R27A module: roomInit + script
-- natives).  The way east to Lake Hylia (and on to Syrup's hut in the Minish
-- Woods) goes through Talon's house: its two halves are joined by an inner
-- archway that a HOUSE_DOOR_INT keeps shut until INLOCK.
--
-- PORTED (src/roomInit.c, src/script.c):
--   * sub_StateChange_HyruleField_LonLonRanch ($03:05):
--     CheckLocalFlagByBank(FLAG_BANK_2, KHOUSE52_KINOKO) (the Town Minish
--     asked for the Wake-Up Mushroom) and not INLOCK -> gUnk_080F77C0
--     (script_TalonLostKey, script_MalonLostKey in front of the locked
--     house); else with ITEM_EARTH_ELEMENT -> gUnk_080F77F0 (Malon at the
--     ranch).  TABIDACHI and no Earth Element -> gUnk_080F7810.
--     KINSTONE_29 not fused -> gUnk_080F7860 and SetTile SPECIAL_TILE_114 /
--     SPECIAL_TILE_150 at TILE_POS(8, 54) / (8, 55) (the Goron cave's door
--     shut).  global_progress > 3 and TINGLE_TALK1ST -> gUnk_080F78A0.
--   * sub_StateChange_HouseInteriors4_RanchHouseWest ($28:02): not INLOCK ->
--     gUnk_080F36FC (the two HOUSE_DOOR_INTs: the archway to the east half
--     and the front door); else, global_progress < 4 -> gUnk_080F3604
--     (scriptMalonInside).
--   * sub_StateChange_HouseInteriors4_RanchHouseEast ($28:03): INLOCK ->
--     gUnk_080F37D0 (script_TalonInside2).
--   * sub_0807FBC4 / sub_0807FBCC (RequestPriorityOverPlayer /
--     RevokePriorityOverPlayer): script_TalonGotKey brackets its scene with
--     them; the port's scripts already run while Link is held
--     (SetPlayerIdle), so they only record the request.
-- SIMPLIFIED: CloudOverlayManager_Main(NULL) at the room change (the cloud
--   overlay's first frame) is left to the room's own CLOUD_OVERLAY_MANAGER.
local Native = require("src.zelda.tmc.Native")
local N = Native.N

local M = {}

local G_INLOCK, G_TABIDACHI, G_TINGLE_TALK1ST = 0x1D, 0x15, 0x5C
local FLAG_BANK_2, KHOUSE52_KINOKO = 0x200, 0x8F
local ITEM_EARTH_ELEMENT = 0x40 -- include/item.h
local KINSTONE_29 = 0x29
local SPECIAL_TILE_114, SPECIAL_TILE_150 = 0x4072, 0x4096
M.ITEM_EARTH_ELEMENT = ITEM_EARTH_ELEMENT

local ROOMS = {}
M.ROOMS = ROOMS
ROOMS[0x0305] = function(f)
  if f:flag("bank", KHOUSE52_KINOKO, FLAG_BANK_2) then
    if not f:flag("global", G_INLOCK) then f:loadEntityList(0x080F77C0) end
  elseif (f:inventory(ITEM_EARTH_ELEMENT) or 0) ~= 0 then
    f:loadEntityList(0x080F77F0)
  end
  if f:flag("global", G_TABIDACHI) and (f:inventory(ITEM_EARTH_ELEMENT) or 0) == 0 then f:loadEntityList(0x080F7810) end
  if not f:kinstoneFused(KINSTONE_29) then
    f:loadEntityList(0x080F7860)
    if f.room.setTile then
      f.room:setTile(1, 8, 54, SPECIAL_TILE_114)
      f.room:setTile(1, 8, 55, SPECIAL_TILE_150)
    end
  end
  if (f.save.progress or 1) > 3 and f:flag("global", G_TINGLE_TALK1ST) then f:loadEntityList(0x080F78A0) end
end
ROOMS[0x2802] = function(f)
  if not f:flag("global", G_INLOCK) then
    f:loadEntityList(0x080F36FC)
  elseif (f.save.progress or 1) < 4 then
    f:loadEntityList(0x080F3604)
  end
end
ROOMS[0x2803] = function(f)
  if f:flag("global", G_INLOCK) then f:loadEntityList(0x080F37D0) end
end

-- sub_StateChange_LakeHylia_Main ($0B:00): LV4_CLEAR and not local 4 ->
-- gUnk_080F3C64 (the hologram scene after the Temple of Droplets);
-- KINSTONE_12 fused -> gUnk_080F3C94; progress > 3 and TINGLE_TALK1ST ->
-- gUnk_080F3C44; SPECIAL_TILE_145 on the 5 x 5 ring TILE_POS(16..20,
-- 22..26) of the bottom layer (the walls round the frozen block)
local G_LV4_CLEAR, KINSTONE_12, SPECIAL_TILE_145 = 0x05, 0x12, 0x4091
local RING = { {16,22},{17,22},{18,22},{19,22},{20,22},{16,23},{16,24},{16,25},{20,23},{20,24},{20,25},
               {16,26},{17,26},{18,26},{19,26},{20,26} }
M.LAKE_RING = RING
ROOMS[0x0B00] = function(f)
  if f:flag("global", G_LV4_CLEAR) and not f:flag("local", 4) then f:loadEntityList(0x080F3C64) end
  if f:kinstoneFused(KINSTONE_12) then f:loadEntityList(0x080F3C94) end
  if (f.save.progress or 1) > 3 and f:flag("global", G_TINGLE_TALK1ST) then f:loadEntityList(0x080F3C44) end
  if f.room.setTile then
    for _, t in ipairs(RING) do f.room:setTile(1, t[1], t[2], SPECIAL_TILE_145) end
  end
end

function M.roomInit(f)
  local r = f.room
  if not r then return end
  local fn = ROOMS[(r.area or 0) * 256 + (r.room or 0)]
  if fn then fn(f) end
end

if not N[0x0807FBC4] then N[0x0807FBC4] = function(f, e) e.priorityOverPlayer = true end end
if not N[0x0807FBCC] then N[0x0807FBCC] = function(f, e) e.priorityOverPlayer = nil end end
-- PlayerSetNormalAndCollide (playerUtils.c): ENT_COLLIDE, drawn, the busy /
-- frozen / hole flags off, SetPlayerActionNormal (which also ends a player
-- script: it only runs in PLAYER_SLEEP).  script_MalonLostKey ends with it;
-- without it script_PlayerGiveKey (waiting for sync flag 2, which nothing
-- sets) kept Link held after Talon got his key.
if not N[0x0807921C] then
  N[0x0807921C] = function(f, e, ctx, a)
    local p = f.player
    p.hidden, p.frozen, p.busy = nil, nil, nil
    local normal = N[0x080791BC]
    if normal then normal(f, e, ctx, a) else p.state = "normal"; if f.playerScript then f.playerScript.stopped = true end end
  end
end
-- goron.c sub_080694EC: facing down, animation 2 once KINSTONE_2F is fused,
-- else 8 (the punching Goron at the ranch's cave)
if not N[0x080694EC] then
  N[0x080694EC] = function(f, e)
    e.animationState = 4
    local anim = f:kinstoneFused(0x2F) and 2 or 8
    e.field80, e.forceAnim, e.lookFrame = anim, anim, nil
    e.unk80 = anim
  end
end

return M
