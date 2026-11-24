-- Round 73: the lit Lantern's hitbox against enemies.  Round 26A kept PlayerItemLantern's 4 x 4 hitbox as a hidden
-- entity (hurtType 7) that only the Big Octorok and the Temple of Droplets' objects read; the cartridge's collision
-- pass (CollisionMain over the player-item list against the enemies) tests it against every enemy as well, so an
-- enemy's OnCollision sees contactFlags $87 and the collision matrix row (hitType, hurtType 7) applies.  This is how
-- a Gibdo's wrappings are burnt (gibdo.c Gibdo_OnCollision: $87 -> action 8, Gibdo_CreateObjects, a Stalfos 60
-- frames later) -- the Royal Crypt's Gibdos.
--
-- CARTRIDGE BEHAVIOUR (ported): the item's hitbox ({6,-6} {7,-3} {-5,2} {-7,-3} by facing, 4 x 4 half sizes; the
-- entity ItemLantern keeps) against each enemy's hitbox, same collision layer; matrix handlers 1 / 2
-- (CollisionNoOp) skip; else the generic hit (Enemies:hit with hurtType 7: the matrix's damage / knockback /
-- iframes, OnCollision with $87).
-- SIMPLIFIED: the z test uses the flat 5 + 5 depth, as Enemies' contact with Link does.
local M = {}

M.HURT_TYPE = 7

local function overlaps(e, le)
  local hb = e.hitbox or { x = 0, y = 0, w = 6, h = 6 }
  return math.abs((e.x + (hb.x or 0)) - le.x) < (hb.w or 6) + (le.w or 4)
     and math.abs((e.y + (hb.y or 0)) - le.y) < (hb.h or 6) + (le.h or 4)
end
M.overlaps = overlaps

-- one line in ItemLantern's frame (after the hitbox entity is placed)
function M.contact(f, le)
  if not le or le.deleted then return 0 end
  local E = f.enemies and f:enemies()
  if not E then return 0 end
  local HB = require("src.zelda.tmc.Hitboxes")
  local n = 0
  for _, e in ipairs(f.entities or {}) do
    if e.enemy and not e.dying and not e.deleted and not e.hidden and not e.noHit and not e.boss and not e.projectile
        and (e.iframes or 0) <= 0 and (e.layer or 1) == (le.layer or 1) and math.abs(e.z or 0) <= 10 and overlaps(e, le) then
      local h = HB.data(f) and E.mtx and E.mtx ~= "" and HB.handler(E.mtx, e.hitType or 0, M.HURT_TYPE)
      if h ~= 1 and h ~= 2 then
        local p = f.player
        E:hit(e, M.HURT_TYPE, p.x, p.y)
        n = n + 1
      end
    end
  end
  return n
end

return M
