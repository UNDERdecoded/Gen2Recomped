-- Round 86: arm_CalcCollision's z test for the projectiles FoWObjects' touchLink checks (SPIKED_ROLLERS, the Winder,
-- the fire bars).
--
-- CARTRIDGE BEHAVIOUR (asm/src/intr.s arm_CalcCollision, src/collision.c IsColliding): after the x / y box test,
--   depth = (collisionFlags & $10 ? the Hitbox3D's depth : 5) for each side, summed; the pair only collides when
--   |z_this - z_other| <= that sum.  gPlayerHitbox and the rollers' gUnk_080FD4B8 are flat hitboxes: 5 + 5 = 10.
--   So Link in a Roc's Cape jump more than 10 px up passes over a spiked roller ($70:2B SPIKE_BAR_SMALL_KEY).
-- Port gap fixed: FoWObjects' touchLink had no z test (Enemies' contact has had it since round 43).
-- SIMPLIFIED (as Enemies): Hitbox3D depths are not read; both sides count 5.
local M = {}

M.DEPTH = 5 + 5

-- true when Link and the entity are too far apart in z to collide
function M.overZ(p, e)
  return math.abs((p.z or 0) - (e.z or 0)) > M.DEPTH
end

return M
