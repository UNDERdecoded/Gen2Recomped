-- Round 63: Link's shield against the Temple of Droplets' own contact code (EnemyToD's T.touch: the flying pots, the
-- Scissors Beetles' jaws, the Big Blue ChuChu's drops, ...).
--
-- CARTRIDGE BEHAVIOUR (collision.c CollisionDefault, sub_08017EB0):
--   * While Link holds the shield, the shield is its own PLAYER_ITEM (PL_ITEM_SHIELD) in front of him; an enemy
--     touching that side collides with the shield, not with Link: the shield entity takes the knockback / damage
--     (org = the shield), Link only gets gPlayerEntity.iframes = $80 and loses no health.  The enemy's OnCollision
--     still runs (a flying pot in the air shatters: FlyingPot_OnCollision with z != 0).
--   * The generic contact code (Enemies.lua) already models this with Player:blocksFrom (shield held, the toucher
--     in front: SFX $118, no damage).  EnemyToD's T.touch hurt Link without asking -- a shielded Link facing a flying
--     pot was hurt.  This module is that same test for T.touch.
-- SIMPLIFIED: as in Enemies.lua, the shield's own knockback (8 frames at $180) and the per-hitType matrix row of the
--   shield are not modelled: any front contact is blocked.
local M = {}
M.SFX_SHIELD = 0x118

-- the toucher s is caught by Link's shield: the touch counts (OnCollision runs), no damage
function M.blocked(f, p, s)
  if not (p and p.blocksFrom and p:blocksFrom(s.x, s.y)) then return false end
  if f and f.sound then f:sound(M.SFX_SHIELD) end
  return true
end

return M
