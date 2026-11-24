-- Round 64: a diving Link is out of most things' reach (playerUtils.c / intr.s).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * PlayerSwimming (playerUtils.c $0807x): while swim_state bit $80 is set
--     (ToggleDiving, B) Link's collisionFlags |= 4, else &= $FB; Link's
--     base collisionFlags is 0 (player.c PlayerInit), so his collision type
--     (collisionFlags & 7) is 0 at the surface and 4 under it.
--   * The collision loop (asm/src/intr.s, next_other): a pair is tested only
--     when other.collisionMask & (1 << (this.collisionFlags & 7)) -- a
--     toucher whose mask lacks bit $10 (from its ROM definition:
--     gEnemyDefinitions / gProjectileDefinitions byte 15) never meets a
--     diving Link: the spiked rollers, octoroks' rocks, enemies' bodies.
-- The port's contact code (Enemies.lua, EnemyToD.T.touch, the FoW / ToD
-- projectiles' touchLink) asks D.skips first.
local bit = require("bit")
local band = bit.band

local D = {}
D.DIVE_BIT = 0x10 -- 1 << (0 | 4)

-- the toucher's collisionMask: its own field, else its ROM definition's
function D.mask(e)
  if not e then return nil end
  if e.collisionMask then return e.collisionMask end
  if e.def and e.def.collisionMask then return e.def.collisionMask end
  return nil
end

-- true when `e` cannot touch Link because he is under the water
function D.skips(f, e)
  local p = f and f.player
  if not p or not p.diving then return false end
  local m = D.mask(e)
  if m == nil then return true end -- no definition: the common masks (1, 3, 5, ...) lack bit $10
  return band(m, D.DIVE_BIT) == 0
end

return D
