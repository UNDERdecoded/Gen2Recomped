-- Round 65: the Madderpillar's ($18) contact with Link, from the cartridge's collision code.
--
-- CARTRIDGE BEHAVIOUR (madderpillar.c, collision.c / intr.s):
--   * Every part is its own enemy entity (CreateEnemy(MADDERPILLAR, 1 .. 6)), each with its own ROM definition
--     (gEnemyDefinitions by type): its own hitbox, so the parts' reach differs (the head is the widest, the tail
--     the narrowest); the open tail swaps to gUnk_080FD298, the closing tail to gUnk_080FD2A0.
--   * A part touches Link when |dx| <= wA + wB and |dy| <= hA + hB (arm_CalcCollision, Link's own ROM hitbox).
--   * The hit is the collision matrix's (hitType $6A / $6B / $6C against Link's hurtType): damage, Link's iframes,
--     his knockback (speed and duration) away from the part -- the same as for any enemy (Enemies.lua's contact).
--   * Link's shield caught in front: no damage (Player:blocksFrom, SFX $118).
--   * The dying pillar (the head's ENT_COLLIDE cleared, the parts blowing up) touches nobody.
-- The round-1 port tested a 12 px square round every part and gave no knockback: Link stayed inside the body and
-- was hit again each time his iframes ran out.  BossMadderpillar.update asks M.touch first.
-- SIMPLIFIED: the closing tail keeps its definition's box (gUnk_080FD2A0 is not read).
local M = {}

M.SFX_SHIELD = 0x118

-- the box of one part: the open tail's, else the part's ROM definition's
function M.box(impl, e, s)
  if s and s.open and s.openBox then return s.openBox end
  local t = s and s.type or 0
  local d = impl.en and impl.en.def and impl.en:def(e.id or 0x18, t)
  return d and d.hitbox or e.hitbox
end

-- arm_CalcCollision's box test (nil without Link's ROM hitbox)
function M.over(pb, px, py, hb, x, y)
  local dx = (math.floor(px) + pb.x) - (math.floor(x) + (hb.x or 0))
  local dy = (math.floor(py) + pb.y) - (math.floor(y) + (hb.y or 0))
  return math.abs(dx) <= pb.w + (hb.w or 0) and math.abs(dy) <= pb.h + (hb.h or 0)
end

-- the first part touching Link: head first, then segments 1 .. 6 (entity order)
function M.toucher(impl, e, p, pb)
  if e.dead then return nil end
  if M.over(pb, p.x, p.y, M.box(impl, e, nil), e.x, e.y) then return e end
  for _, s in ipairs(e.segs or {}) do
    if not s.gone and M.over(pb, p.x, p.y, M.box(impl, e, s), s.x, s.y) then return s end
  end
  return nil
end

-- the contact; returns true when it ran (false: no ROM hitbox data, the old test runs)
function M.touch(impl, e)
  local f = impl.field
  local p = f.player
  local HB = require("src.zelda.tmc.Hitboxes")
  local pb = HB.player(f, p)
  if not pb then return false end
  if p.state == "dead" or (p.invuln or 0) > 0 or math.abs((p.z or 0)) > 10 then return true end
  local hit = M.toucher(impl, e, p, pb)
  if not hit then return true end
  if require("src.zelda.tmc.Dive64").skips(f, e) then return true end
  if p.blocksFrom and p:blocksFrom(hit.x, hit.y) then f:sound(M.SFX_SHIELD) return true end
  local en = impl.en
  local st = en:settings(hit.hitType or 0x6A, HB.data(f) and HB.hurtType(p) or 0)
  local dmg = st and math.max(st.tgtDmg or 0, 1) or 4
  if p:hurt(dmg, hit.x, hit.y) and st then
    p.invuln = math.max(st.orgIfr or 0, 30)
    p.timer = math.max(st.orgKbDur or 0, 4)
    local ks = ((st.orgKbSpd or 0) * 16) / 256
    local dx, dy = p.x - hit.x, p.y - hit.y
    local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    p.kbx, p.kby = dx / d * ks, dy / d * ks
  end
  return true
end

return M
