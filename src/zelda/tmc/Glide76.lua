-- Round 76: PLAYER_PARACHUTE details for Cloud Tops (player.c / playerUtils.c), hooked from Whirlwind.lua.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * sub_08073584 (the glide): super->speed = 0x100 when gArea.locationIndex == 16 (AREA_CLOUD_TOPS' location),
--     else 0x80.  The port glided at 0x80 everywhere: Cloud Tops' glides were half the cartridge's speed (half the
--     distance per whirlwind).
--   * sub_0807A2F8 (the hop up a ledge face while gliding) returns 0 at once when gRoomControls.area == 8 (Cloud
--     Tops): no hop there.
--   * the fall at the glide's end (DoJump with jump_status $40 -> sub_080739EC -> sub_08073AD4) keeps Link's
--     collision layer; the whirlwind set it to 1 (Whirlwind_Action1).  The port's landing took the top map's layer
--     (ResolveCollisionLayer): in Cloud Tops' middle tier a landing on a hard cloud's rim put Link on layer 2, where
--     the room has no collision at all (he walked over the void).  In area 8 the layer is kept.
--   SIMPLIFIED / not changed: outside Cloud Tops the landing still resolves the layer (round 20 / 43's glides on
--   Mt. Crenel and in the Fortress of Winds were verified with it).
local M = {}

M.LOC_CLOUD_TOPS = 16
M.AREA_CLOUD_TOPS = 8
M.SPEED, M.SPEED_CLOUD_TOPS = 0x80, 0x100

local function location(f)
  if not f then return 0 end
  if f.curLocation and f.curLocation ~= 0 then return f.curLocation end
  local r = f.room
  return (r and r.areaInfo and r.areaInfo.location) or 0
end
M.location = location

function M.speed(f)
  return location(f) == M.LOC_CLOUD_TOPS and M.SPEED_CLOUD_TOPS or M.SPEED
end

function M.noHop(f)
  return f and f.room and f.room.area == M.AREA_CLOUD_TOPS or false
end

function M.keepLayer(f)
  return M.noHop(f)
end

return M
