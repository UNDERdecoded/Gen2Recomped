-- Round 82: the Four Sword clones' tile collisions on the cartridge's sensors (Collide80).
--
-- CARTRIDGE BEHAVIOUR (src/object/playerClone.c PlayerClone_Action2, asm/src/player.s sub_080085B0):
--   * Every frame the clone is put at Link + its offset (unk78 / unk7a), then sub_080085B0(clone) runs
--     sub_080085CC on the CLONE: the eight sensor points of its own hitbox (PlayerCloneHitbox, read from the
--     ROM) around its position, on its collision layer (copied from Link's by sub_08084B1C), through the same
--     state table as Link's (gPlayerState: swimming, jump / parachute, Minish, gust jar / held object, beetles,
--     else the normal one) -> clone.collisions.
--   * All of COL_NORTH_FULL | COL_SOUTH_FULL | COL_EAST_FULL | COL_WEST_FULL set -> the split ends at once;
--     one PlayerCloneCollisions pattern contained -> 30 blinking frames, then it ends; else the clone stays.
--     (FourSword.lua keeps that logic; this module only gives it the collisions.)
--   * The clones are never moved by their collisions: a clone walks through walls as long as no pattern holds;
--     a platform carrying Link carries them (their spot is Link's + the offset) and they do not fall into pits.
-- Port gap fixed: FourSword's cloneCollisions probed the port's old feet box (x - 4 .. x + 3, y - 5 .. y + 2) one
--   pixel outside each side, with the bits of the two side sensors swapped against the cartridge's sensor
--   geometry ($0200 / $2000 are the upper west / east sensors, $0400 / $4000 the lower ones).
-- With an older cache (no Clone82.HITBOX) FourSword's old probes stay.
local bit = require("bit")
local bor = bit.bor

local M = {}

local RT = require("src.zelda.tmc.RomTables")
local HB = RT.t("Clone82.HITBOX") -- PlayerCloneHitbox (playerClone.c)

-- stand-ins for tests: M.use(hb)
local override
function M.use(hb) override = hb end

local function hitbox()
  if override then return override end
  if not RT.attached() then return nil end
  local ok, ox = pcall(function() return HB.ox end)
  if not ok or ox == nil then return nil end
  return HB
end
M.hitbox = hitbox

-- clone.collisions at (x, y) on `layer`; p = Link (gPlayerState's table choice).  nil: no tables (old probes)
function M.collisions(room, x, y, layer, p)
  local hb = hitbox()
  if not hb or not room then return nil end
  local C = require("src.zelda.tmc.Collide80")
  local tab = p and C.tableFor(p) or 0
  local swimFull = p and p.swimming and not p.shallow and true or false
  local coll = 0
  for _, s in ipairs(C.sensors(hb, x, y)) do
    if C.pointSolid(room, s[1], s[2], layer or 1, tab, swimFull) then coll = bor(coll, s[3]) end
  end
  return coll
end

return M
