-- Round 94: the KEATON_DAGGER against Link's shield (src/projectile/keatonDagger.c,
-- src/playerItem/playerItemShield.c, src/enemy/keaton.c).
--
-- CARTRIDGE BEHAVIOUR:
--   * The charging Keaton's dagger is its own projectile entity (KEATON_DAGGER,
--     hitbox gUnk_08129998[animationState]) that hurts Link through the
--     collision matrix.
--   * While Link holds the shield, PLAYER_ITEM_SHIELD is an entity of its own
--     with a hitbox in front of him (gUnk_08127240 by facing); a hit on it is
--     taken by the shield (PlayerItemShield_Action1 hands the shield's iframes
--     / knockback to Link, no damage) -- a dagger coming at Link's front meets
--     the shield, not Link.
--   * The Keaton's body meeting the shield during the charge gives
--     Keaton_OnCollision the shield's contact ($CC) -> sub_0803275C: the
--     charge stops (action 5, 45 frames).
-- The port tested the dagger against Link's body only and always hurt him
-- (and stole rupees): two hits in $88:32 (round 93) while Link shielded toward
-- the Keatons.  Now a dagger touch from Link's shielded front is blocked:
-- SFX $118 (the shield's clank), the charge stops, no damage, no theft.
-- SIMPLIFIED: "from the front" is Player:blocksFrom (the port's shield cone,
-- the same test the body contact uses), not the shield entity's own hitbox.
local M = {}

-- true (and the block played) when Link's shield takes Keaton e's dagger
function M.shielded(E, e)
  local f = E and E.field
  local p = f and f.player
  if not (p and p.blocksFrom) then return false end
  if not p:blocksFrom(e.x, e.y) then return false end
  if f.sound then f:sound(0x118) end
  return true
end

return M
