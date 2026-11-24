-- Round 84: the Cane of Pacci's hole spring as the cartridge decides it.
--
-- CARTRIDGE BEHAVIOUR (src/player.c sub_08072B5C, src/playerUtils.c
-- sub_0807A2F8, asm/src/code_080043E8.s sub_08004542):
--   * After the 40 frames in the charged hole: SPECIAL_TILE_33, then
--     n = sub_0807A2F8(1) -- the ledge scan Roc's whirlwind glide uses
--     (Whirlwind.ledgeUp), without its "blocked facing the ledge" test
--     (param 1): from Link's hitbox sides, one or two tiles of the facing's
--     ledge-face act tiles (gUnk_0811C1D8), then open floor; in a dungeon the
--     tile after that must have no LAYER_TOP collision.  0 in area 8.
--   * n = 0: the small hop out (zVelocity 3.5625, speed $40, Link stays).
--   * n > 0: outside the overworld sub_08004542 puts Link on layer 2 at once;
--     zVelocity ((n << 4) - 4) << 12 = n - 0.25 px, speed kJumpSpeedForward
--     (1 px), the jump under kGravityRate.
-- Before round 84 the port counted any solid tiles ahead (n + 1 px, the
-- layer kept): $70:1A's spring over the corridor wall flew 4 px further.
local M = {}

M.AREA_8 = 8 -- gRoomControls.area == 8: no spring (sub_0807A2F8's first test)

-- the spring's n (0 = the small hop); `fallback(f, p)` is the old scan, used only when the cartridge's cannot run
function M.spring(f, p, fallback)
  if f and f.room and f.room.area == M.AREA_8 then return 0 end
  local ok, n = pcall(require("src.zelda.tmc.Whirlwind").ledgeUp, p, true)
  if ok then return n or 0 end
  local m = fallback and (fallback(f, p)) or 0
  return m > 0 and m + 1 or 0
end

-- sub_08004542 (not in the overworld): collisionLayer 2
function M.layer(f, p)
  if not require("src.zelda.tmc.MapMenu").isOverworld(f) then p.layer = 2 end
end

return M
