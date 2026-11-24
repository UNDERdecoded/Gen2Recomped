-- Round 47: Castor Wilds' caves and the Wind Ruins (an R27A module:
-- roomInit).  Each rule below was read from the room property table's code
-- pointers ([6] sub_unk3, [7] sub_StateChange) in the player's ROM
-- (gAreaTable $080D50FC; callees: $0807CBD0 CheckLocalFlag, $0807CC30
-- CheckGlobalFlag, $0807CCB4 SetLocalFlag, $0807CA84 GetInventoryValue,
-- $0801E7F4 CheckKinstoneFused, $0804ADDC LoadRoomEntityList);
-- only addresses, flags and logic live here.
--
-- PORTED (src/roomInit.c):
--   * sub_unk3_CastorDarknut_Main ($2B:00, $0804C3CC): not CheckLocalFlag($39)
--     -> gRoomVars' list 0 becomes gUnk_080DA230 (an OBJECT_69 running
--     script $0800B17C -- the Darknut fight -- and the CHEST_SPAWNER that
--     drops the Gold Kinstone chest once flag $39 is set) in place of
--     gUnk_080DA210 (the chest spawner alone).
--   * $27:06's state change ($0804C99C, the Bow's Minish crack): no
--     ITEM_BOW (GetInventoryValue(9)) -> gUnk_080DCB10.
--   * $05:00's state change ($0804CAF8, the Wind Ruins' entrance): SetLocalFlag($24).
--   * $05:02 ($0804CB14): KINSTONE_41 fused
--     (CheckKinstoneFused) -> gUnk_080DDE88.
--   * $05:04 ($0804CB50): CheckGlobalFlag(4) and not CheckLocalFlag(3) ->
--     gUnk_080DE008 (an OBJECT_69 with script $0800AF8C).
--   * $05:05 ($0804CB7C): not local $30 -> gUnk_080DE1E0; not local $31 ->
--     gUnk_080DE200.
-- sub_080300E8 (the Wind Ruins' rooms start with it: armos_data's pending
--   Minish entrance puts Link under that Armos) is Armos49.lua (round 49);
--   $25:05's state change (sub_0805BC4C and two tile-index SetTile calls) is
--   not ported (off the route).
local M = {}

local ITEM_BOW = 0x09

local ROOMS = {}
M.ROOMS = ROOMS

local function dropList(f, list)
  local ok, D = pcall(require, "src.zelda.tmc.DHCObjects")
  if ok and D.dropList then return D.dropList(f, list) end
  for _, dat in ipairs(list or {}) do
    for _, e in ipairs(f.entities) do if e.data == dat then e.deleted = true end end
  end
end

ROOMS[0x2B00] = function(f)
  if not f:flag("local", 0x39) then
    local lists = f.room.entities or {}
    dropList(f, lists[0])
    f:loadEntityList(0x080DA230)
  end
end
ROOMS[0x2706] = function(f)
  if (f:inventory(ITEM_BOW) or 0) == 0 then f:loadEntityList(0x080DCB10) end
end
ROOMS[0x0500] = function(f) f:setFlag("local", 0x24, true) end
ROOMS[0x0502] = function(f)
  if f:kinstoneFused(0x41) then f:loadEntityList(0x080DDE88) end
end
ROOMS[0x0504] = function(f)
  if f:flag("global", 4) and not f:flag("local", 3) then f:loadEntityList(0x080DE008) end
end
ROOMS[0x0505] = function(f)
  if not f:flag("local", 0x30) then f:loadEntityList(0x080DE1E0) end
  if not f:flag("local", 0x31) then f:loadEntityList(0x080DE200) end
end

function M.roomInit(f)
  local r = f.room
  if not r then return end
  local fn = ROOMS[(r.area or 0) * 256 + (r.room or 0)]
  if fn then fn(f) end
end

return M
