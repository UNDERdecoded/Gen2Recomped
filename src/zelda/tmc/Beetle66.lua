-- Round 66: the Temple of Droplets' Scissors Beetles' jaws (EnemyToD T.jaws) checked against the cartridge.
--
-- CARTRIDGE BEHAVIOUR (mandiblesProjectile.c, scissorsBeetle.c, collision.c CollisionDefault, intr.s arm_CalcCollision):
--   * Contact is arm_CalcCollision's box test: |dx| <= wA + wB and |dy| <= hA + hB with both entities' hitboxes
--     (Link's own ROM hitbox, the jaws' gUnk_08129CF4[state] while attached, gHitbox_0 once they fly: action 3 -> 4
--     sets super->hitbox = &gHitbox_0).  The round-26 port gave the flying jaws a 1 x 1 box at the centre and an
--     approximate Link box (T.touch), so they were much easier to dodge than on the cartridge.
--   * MandiblesProjectile_OnCollision, case 4 (flying): ANY contact (Link, his shield, his sword) -> subtimer 0
--     (they turn home at once) and ModHealth(-2) -- on top of the matrix's damage when the contact was Link himself.
--     A shield block or a sword swing at flying jaws still costs Link 2.
--   * A shield block (CollisionDefault with org = PL_ITEM_SHIELD): Link loses nothing from the matrix and gets
--     gPlayerEntity.iframes = $80.
--   * Default case (attached jaws, actions 1 / 2): the body copies iframes / knockback; in action 1 the touch makes them
--     snap (sub_080AA320) -- Link walking into idle jaws starts the bite.
--   * sub_080AA2E0 (Link seen): Direction8Round(dir + 4) == Direction8Round(state * 4 + 4) and within $40;
--     sub_080AA320 (the snap): the jaws' state = Direction8Round(dir + 4) >> 2, the body's = DirectionRound(that) >> 2.
--     The round-26 port added 2 to both (the cone and the bite turned 22.5 degrees off the cartridge's).
-- SIMPLIFIED: the sword's own recoil from the jaws (orgKnockback 40 / 12, iframes 240) is not modelled.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}
M.SFX_SHIELD = 0x118
M.SHIELD_IFRAMES = 0x80
M.EXTRA = 2 -- ModHealth(-2) (an argument in the code)

local FLY = require("src.zelda.tmc.RomTables").t("Beetle66.FLY_HB") -- gHitbox_0

-- the flying jaws' box (gHitbox_0), nil without the cache
function M.flyBox()
  local ok, r = pcall(function() return FLY[0] end)
  if not ok or not r then return nil end
  return { x = r.x, y = r.y, w = r.w, h = r.h }
end

-- sub_080AA2E0's facing test
function M.sees(dir, state)
  return band(dir + 4, 0x1C) == band(state * 4 + 4, 0x1C)
end

-- sub_080AA320's states: jaws (8-way), body (4-way, as an 8-way state)
function M.snapStates(dir)
  local u = band(dir + 4, 0x1C)
  return rshift(u, 2), rshift(band(u, 0x18), 2)
end

-- arm_CalcCollision's box test
function M.over(pb, px, py, hb, x, y)
  local dx = (math.floor(px) + pb.x) - (math.floor(x) + (hb.x or 0))
  local dy = (math.floor(py) + pb.y) - (math.floor(y) + (hb.y or 0))
  return math.abs(dx) <= pb.w + (hb.w or 0) and math.abs(dy) <= pb.h + (hb.h or 0)
end

local function modHealth(f, d)
  if f.modStat then f:modStat("health", d) else f.save.stats.health = math.max(0, (f.save.stats.health or 0) + d) end
end

-- the jaws m touching Link this frame (T.touch's replacement for the jaws); returns true on a contact.
-- onSnap(m) is T's sub_080AA320 (action-1 contact).
function M.touch(E, m, onSnap)
  local f = E.field
  local p = f.player
  local HB = require("src.zelda.tmc.Hitboxes")
  local pb = HB.player(f, p)
  if not pb then return nil end -- no ROM hitbox data: the caller's old test
  if p.hidden or p.state == "dead" or (p.invuln or 0) > 0 or (m.z or 0) > 12 then return false end
  if not M.over(pb, p.x, p.y, m.hitbox or {}, m.x, m.y) then return false end
  if require("src.zelda.tmc.Dive64").skips(f, m) then return false end
  local fly = m.action == 4
  if p.blocksFrom and p:blocksFrom(m.x, m.y) then
    f:sound(M.SFX_SHIELD)
    p.invuln = math.max(p.invuln or 0, M.SHIELD_IFRAMES)
  else
    local st = E.settings and E:settings(m.hitType or 3, HB.data(f) and HB.hurtType(p) or 0) or nil
    local dmg = st and st.tgtDmg or 2
    if dmg > 0 and p:hurt(dmg, m.x, m.y) and st then
      p.invuln = math.max(st.orgIfr or 0, 30)
      p.timer = math.max(st.orgKbDur or 0, 4)
      local ks = ((st.orgKbSpd or 0) * 16) / 256
      local dx, dy = p.x - m.x, p.y - m.y
      local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.kbx, p.kby = dx / d * ks, dy / d * ks
    end
  end
  if fly then
    m.subtimer = 0
    modHealth(f, -M.EXTRA)
  elseif m.action == 1 and onSnap then
    onSnap(m)
  end
  return true
end

-- the sword meeting flying jaws (OnCollision case 4): they turn home, Link loses 2.  True when it touched.
function M.swordFly(E, m, box)
  if m.deleted or m.action ~= 4 then return false end
  local hb = m.hitbox or {}
  if math.abs((m.x + (hb.x or 0)) - box.x) <= (hb.w or 0) + box.w and math.abs((m.y + (hb.y or 0)) - box.y) <= (hb.h or 0) + box.h then
    if (m.swordT66 or -100) + 12 > (E.field.frame or 0) then return false end
    m.swordT66 = E.field.frame or 0
    m.subtimer = 0
    modHealth(E.field, -M.EXTRA)
    E.field:sound(M.SFX_SHIELD)
    return true
  end
  return false
end

return M
