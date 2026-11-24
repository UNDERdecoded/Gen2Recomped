-- Round 67: the Pesto's contact height (src/enemy/pesto.c, asm/src/intr.s arm_CalcCollision).
--
-- CARTRIDGE BEHAVIOUR:
--   * Pesto_Init (sub_080240B8) sets collisionFlags |= $10: its hitbox is a Hitbox3D (gEnemyDefinitions' PESTO rows
--     point at gUnk_080FD22C) whose depth byte (offset 8) is used by arm_CalcCollision's height test.
--   * arm_CalcCollision: each side's depth is 5, or its Hitbox3D depth when its collisionFlags has $10; the two are
--     added (D) and the entities overlap in height only when |z1 - z2| <= D.  Link has no $10: 5.
--   * So a Pesto touches Link (and is touched) from its hover height (z -16, bobbing to -14), but not a type-1 Pesto
--     hovering at -48 with its dirt ball, nor one risen to -60 after a pick-up.
-- The port (EnemyToD round 26) let a Pesto at any height >= 8 touch Link.  M.reaches(e, p) is the test; the depth is
-- read from the ROM at import (RomTables "Pesto67.HB3D").  Without the table (no cache) it keeps the old behaviour.
local M = {}
M.LINK_DEPTH = 5 -- arm_CalcCollision: mov r2, #5 / mov r3, #5 when collisionFlags & $10 is clear

local HB = require("src.zelda.tmc.RomTables").t("Pesto67.HB3D") -- gUnk_080FD22C

-- the Pesto's Hitbox3D depth, nil without the cache
function M.depth()
  local ok, r = pcall(function() return HB[0] end)
  if not ok or not r then return nil end
  return r.d
end

-- the Pesto e (z = height above the ground, positive up) and Link p overlap in height
function M.reaches(e, p)
  local d = M.depth()
  if not d then return true end
  return math.abs((e.z or 0) - (p.z or 0)) <= d + M.LINK_DEPTH
end

return M
