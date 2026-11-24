-- Round 79: the Four Sword clones' swords on objects (src/object/playerClone.c, collision.c).
--
-- CARTRIDGE BEHAVIOUR: each PLAYER_CLONE swings its own PLAYER_ITEM_SWORD (a child copying Link's sword frame at
-- the clone), a player item like Link's: collision.c resolves it on every entity through gCollisionMtx, objects
-- included -- a LIGHTABLE_SWITCH (hitType $28) is lit by a clone's sword or spin exactly as by Link's.  The Palace of
-- Winds' four-switch room ($70:22) needs it: the three Links stand between the four type-1 switches and one spin
-- attack lights all four inside their 16 frames (the FLAG_AND_OPERATOR_MANAGER latches them, the shutter opens).
-- Port gap fixed: FourSword copied Link's sword box to the clones for enemies only (Enemies:swordHits); the
-- switches saw Link's own box alone.  Here the same box copy, offset to each clone, counts as a switch contact.
local M = {}

-- the clones' sword boxes this frame: Link's box (f.swordBoxNow, stamped this frame) moved by each clone's offset
function M.boxes(f)
  local b = f.swordBoxNow
  local out = {}
  if not b or b.t ~= f.frame or b.fromClone then return out end
  local p = f.player
  local cl = rawget(f, "playerClones")
  if type(cl) ~= "table" or not p then return out end
  for _, c in ipairs(cl) do
    if c.action == 2 and not c.deleted then
      local dx, dy = c.x - math.floor(p.x), c.y - math.floor(p.y)
      out[#out + 1] = { x = b.x + dx, y = b.y + dy, w = b.w, h = b.h }
    end
  end
  return out
end

-- LightableSwitch.contact: one of the boxes overlaps the switch's half size h
function M.switchContact(f, e, h)
  for _, b in ipairs(M.boxes(f)) do
    if math.abs(b.x - e.x) < b.w + h and math.abs(b.y - e.y) < b.h + h then return true end
  end
  return false
end

return M
