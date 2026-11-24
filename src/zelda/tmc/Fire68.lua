-- Round 68: the Winder's CollisionFire sets Link burning, and a burning Link
-- on the ice floor is moved by the ice alone.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc):
--   * src/projectile/winder.c: every segment's hitType reaches
--     gCollisionHandlers[11] = CollisionFire against Link's hurtType 0 / 1
--     (collision.c): Link not PL_BUSY / PL_MINISH / PL_BURNING /
--     PL_IN_MINECART -> LINK_FIRE type 1 and PL_BURNING, Link turned to the
--     fire; damage 4, knockback 12 frames at 384, 30 iframes.  The round-26
--     port (FoWObjects.fireTouch) gave the damage and knockback only; it now
--     goes through R31.contact, the same CollisionFire the enemies use.
--   * player.c PlayerNormal: on SURFACE_ICE sub_08008926 moves Link by the
--     ice velocity, which only the stick (gPlayerState.direction) feeds;
--     PL_BURNING then sets super->speed = kWalkSpeedBurning and, with the
--     stick released, super->direction = his facing -- but on the ice
--     v13 = 1, so UpdatePlayerMovement (the burning run) is not called.
--     A burning Link on the ice slides; off it he runs.
local M = {}

-- FoWObjects.fireTouch, after its touch test: CollisionFire
function M.fireTouch(f, e)
  local R31 = require("src.zelda.tmc.R31")
  return R31.contact({ field = f }, e, R31.HANDLER_FIRE)
end

-- R31.burnFrame with the stick released: true = Link stands on the ice
-- floor, where the burning run does not move him
function M.iceHold(p)
  local f = p.field
  if not f or not f.room or p.swimming or p.minish or (p.z or 0) ~= 0 then return false end
  local ok, T = pcall(require, "src.zelda.tmc.ToDObjects")
  if not ok or not T.onIce then return false end
  local ok2, r = pcall(T.onIce, f, p)
  return ok2 and r or false
end

return M
