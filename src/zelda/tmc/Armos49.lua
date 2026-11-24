-- Round 49: the Armos interiors' round trip (an R27A module).
--
-- CARTRIDGE BEHAVIOUR (src/enemy/armos.c, src/roomInit.c,
-- src/manager/armosInteriorManager.c, src/game.c):
--   * gRoomTransition.armos_data: per Armos slot (unk_80 = its timer) the
--     place and one bit (field_0xac); field_0xae = the slot whose Minish
--     entrance Link took ($FF = none).  Every Armos writes its place / bit
--     each frame (sub_08030150); Init reads them back when the place is
--     non-zero, else the bit is (0x47D >> slot) & 1.
--   * sub_080300C4 (GameMain_ChangeRoom, after the new room's first
--     frames): field_0xae == $FF -> the bits and places are cleared.  So the
--     data only survives a trip through an Armos' Minish entrance.
--   * A slot whose bit is 0 never wakes (sub_0803030C); the way to set the
--     bit is the switch inside its interior: ArmosInteriors_<n>'s state
--     change Armos_SetFlagFromTransition(n) copies bit n into local flag
--     AMOS_00_00 + n (FLAG_BANK_3, $67 + n); ARMOS_INTERIOR_MANAGER copies
--     the flag back into bit n every frame (the switch sets the flag).
--   * sub_080300E8 (state change of $05:00 Ruins_Entrance, $05:04
--     FortressEntrance, $05:05 Ruins_Armos, FoW $58:02 EastKeyLever / $58:04
--     WestKeyLever): field_0xae != $FF -> Link is put at that slot's place
--     + (0, $C) and field_0xae = $FF.  Back out, that Armos reads its saved
--     bit (now 1) and wakes when Link touches it.
-- The port keeps armos_data in EnemyFoW.armosData(f) (f._fowArmos: mask,
-- data, enter); before round 49 it was never cleared, the interiors never
-- copied the bit and Link came back at the room exit's spot -- an Armos
-- like $05:00's second one (slot 1, bit 0 in $47D) could never wake.
local bit = require("bit")
local band, bor, bnot, lshift, rshift = bit.band, bit.bor, bit.bnot, bit.lshift, bit.rshift

local M = {}
M.AREA_INTERIORS = 0x2C
M.FLAG0, M.BANK = 0x67, 3 -- AMOS_00_00, FLAG_BANK_3
M.PLACE_ROOMS = { [0x0500] = true, [0x0504] = true, [0x0505] = true, [0x5802] = true, [0x5804] = true }

local function ad(f) return require("src.zelda.tmc.EnemyFoW").armosData(f) end
local function bankBase(f)
  local B = f.BANK_OFFSET or require("src.zelda.tmc.Field").BANK_OFFSET
  return B and B[M.BANK + 1] or 0x300 -- gLocalFlagBanks is indexed by LOCAL_BANK_n (G = 0): FLAG_BANK_3 is entry 4
end
M.bankBase = bankBase

-- ClearArmosData
function M.clear(f)
  local d = ad(f)
  d.mask, d.data, d.enter = 0, {}, 0xFF
end

function M.roomInit(f)
  local r = f.room
  if not r then return end
  local d = ad(f)
  local key = (r.area or 0) * 256 + (r.room or 0)
  if (d.enter or 0xFF) == 0xFF then
    -- sub_080300C4: no Minish entrance pending -> the bits and places go
    -- (the cartridge clears after the new room's Armos have read them;
    -- slots are unique per Armos, so nothing in this room is lost)
    d.mask, d.data = 0, {}
    return
  end
  if (r.area or 0) == M.AREA_INTERIORS then
    -- Armos_SetFlagFromTransition(room)
    local n = r.room or 0
    f:setFlag("bank", M.FLAG0 + n, band(rshift(d.mask or 0, n), 1) ~= 0, bankBase(f))
  elseif M.PLACE_ROOMS[key] then
    -- sub_080300E8
    local pos = d.data[d.enter]
    if pos and f.player then f.player.x, f.player.y = pos[1], pos[2] + 0xC end
    d.enter = 0xFF
  end
end

-- ARMOS_INTERIOR_MANAGER_Main's tail: bit `type` follows the flag
function M.frame(f)
  local s = f.armos37
  if not s or s.room ~= f.room then return false end
  local d = ad(f)
  local n = s.type or 0
  local on = f:flag("bank", M.FLAG0 + n, bankBase(f))
  if on then d.mask = bor(d.mask or 0, lshift(1, n)) else d.mask = band(d.mask or 0, bnot(lshift(1, n))) end
  return false
end

return M
