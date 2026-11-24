-- Round 70: the Big Octorok (octorokBoss.c) -- its parts' contact with Link and the Lantern's flame on the tail end,
-- as the cartridge's collision loop does it (collision.c CollisionDefault, intr.s arm_CalcCollision).
--
-- CARTRIDGE BEHAVIOUR
--   * A part touches Link when the boxes overlap: |dx| <= wA + wB and |dy| <= hA + hB, positions plus hitbox offsets
--     (Link's gPlayerHitbox: offset 0,-3, half size 6 x 6; the parts' boxes come from their enemy definitions).
--   * gCollisionMtx[hitType * 34 + Link's hurtType] decides: the handlers 1 / 2 (CollisionNoOp) do nothing, 16
--     (sub_08018228) only pushes Link out.  CollisionDefault hurts Link only when tgtDamage != 0 (`if
--     (settings->tgtDamage != 0) org->health = CalculateDamage(...)`): a part with tgtDamage 0 (the legs, hit type
--     $60) only knocks him back (orgKnockbackDuration / Speed) with its iframes (s8: 240 = -16, no damage).
--   * Swallowed by the vacuum (unk_80 != 0) and while spat out (ExecuteAttackVacuum clears ENT_COLLIDE before
--     sub_080792BC) Link is not collidable: the mouth does not hurt him on the way out.
--   * The shield held toward a part (PL_ITEM_SHIELD meets it first) keeps the hit off Link.
--   * The Lantern (playerItemLantern.c: collisionFlags 7, a 4 x 4 box at Link + offsets[animationState]) lights
--     the frozen tail end on contact: (contactFlags & $7F) == 7 when the boxes overlap -- the tail end's own
--     definition box, not a fixed 16 px square.
-- (The port's old test hurt Link for 1 on a tgtDamage-0 part, used +5 / +6 for Link's box, ignored the shield, and
-- took the flame within 16 px of the tail end's centre.)
local bit = require("bit")

local O = {}

local function s8(v) v = bit.band(v or 0, 0xFF) if v >= 128 then return v - 256 end return v end
O.s8 = s8

-- the box test (|d| <= wA + wB on both axes)
function O.overlap(ax, ay, aw, ah, bx, by, bw, bh)
  return math.abs(ax - bx) <= aw + bw and math.abs(ay - by) <= ah + bh
end

-- what a part's contact does to Link: "none", "push", "block", "knock" or "hurt" (pure: tests feed stand-ins)
--   s: ColSettings (or nil), handler: the matrix handler id (or nil), blocked: the shield faces the part
function O.verdict(s, handler, blocked)
  if handler == 1 or handler == 2 then return "none" end
  if handler == 16 then return "push" end
  if blocked then return "block" end
  if not s then return "hurt" end
  if (s.tgtDmg or 0) ~= 0 then return "hurt" end
  if (s.orgKbDur or 0) > 0 then return "knock" end
  return "none"
end

-- B:touchLink(x, y, hb, hitType, z): true when the part met Link (or his shield)
function O.touchLink(self, x, y, hb, hitType, z)
  local f = self.field
  local p = f.player
  if p.hidden or p.state == "dead" or (p.invuln or 0) > 0 or (z or 0) > 12 then return false end
  -- swallowed (Action1_Attack: unk_80 != 0) or spat out (the vacuum's flags &= ~ENT_COLLIDE before sub_080792BC):
  -- Link is not collidable
  if self.fling or (self.e70 and (self.e70.u80 or 0) ~= 0) then return false end
  local HBm = require("src.zelda.tmc.Hitboxes")
  local pb = HBm.player(f, p) or { x = 0, y = -3, w = 6, h = 6 }
  hb = hb or { x = 0, y = 0, w = 4, h = 4 }
  if not O.overlap(math.floor(p.x) + (pb.x or 0), math.floor(p.y) + (pb.y or 0), pb.w, pb.h,
                   math.floor(x) + (hb.x or 0), math.floor(y) + (hb.y or 0), hb.w or 4, hb.h or 4) then return false end
  local hurtType = HBm.hurtType(p)
  local handler = HBm.data(f) and HBm.handler(self.en.mtx, hitType or 0, hurtType)
  local s = self.en:settings(hitType or 0, hurtType)
  local v = O.verdict(s, handler, p:blocksFrom(x, y))
  if v == "none" then return false end
  if v == "push" then HBm.pushOut(f, { x = x, y = y }, hb) return false end
  if v == "block" then
    if not self.block70 or (f.frame or 0) - self.block70 > 8 then f:sound(0x118) end
    self.block70 = f.frame or 0
    return true
  end
  s = s or { tgtDmg = 2, orgIfr = 30, orgKbDur = 8, orgKbSpd = 24 }
  local ks = ((s.orgKbSpd or 24) * 16) / 256
  local dx, dy = p.x - x, p.y - y
  local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
  local ifr = math.abs(s8(s.orgIfr or 30))
  if v == "hurt" then
    if p:hurt(s.tgtDmg or 2, x, y) then
      p.invuln = math.max(ifr, 30)
      p.timer = math.max(s.orgKbDur or 8, 4)
      p.kbx, p.kby = dx / dd * ks, dy / dd * ks
    end
    return true
  end
  -- knockback only (tgtDamage 0)
  if p.state == "normal" or p.state == "shield" or p.state == "sword" then
    p.state, p.timer = "hurt", s.orgKbDur
    p.kbx, p.kby = dx / dd * ks, dy / dd * ks
    p.invuln = math.max(p.invuln or 0, ifr)
  end
  return true
end

-- B:flameNear(te): the Lantern's flame box against the tail end's box
function O.flameNear(self, te)
  local hb = te.hitbox or { x = 0, y = 0, w = 16, h = 16 }
  for _, o in ipairs(self.field.entities) do
    if not o.deleted and (o.hurtType == 7 or o.lanternFlame) then
      local ow, oh = o.w or o.hitW or 4, o.h or o.hitH or 4
      if O.overlap(o.x, o.y, ow, oh, te.x + (hb.x or 0), te.y + (hb.y or 0), hb.w or 16, hb.h or 16) then return true end
    end
  end
  return false
end

function O.install(B)
  if B.octo70 then return end
  B.octo70 = true
  B.touchLink = O.touchLink
  B.flameNear = O.flameNear
  local up0 = B.update
  B.update = function(self, e) self.e70 = e return up0(self, e) end
end

return O
