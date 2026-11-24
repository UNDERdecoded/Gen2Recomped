-- Round 54: JAR_PORTAL's flip (src/object/jarPortal.c), the part round 45
-- left out (Jar45.lua).
--
-- CARTRIDGE BEHAVIOUR:
--   * JarPortal_Action1 (lying) / Action3 (standing): a hit of type $1D
--     (contactFlags == CONTACT_NOW | $1D, sub_0808C128: the Cane of Pacci's
--     bolt) -> sub_0808C13C (subAction 0, zVelocity 2.5); lying: local flag
--     `type` set when unk_7c is 0, else cleared (standing: the other way);
--     sub_0808C148(FALSE): SPECIAL_TILE_146..149 on its four tiles.
--   * Action2 (lying -> standing) / Action4 (standing -> lying):
--     GravityUpdate(Q_8_8(32)); subAction 0 until zVelocity < 1.5 ->
--     animation 2 (Action4: 3); subAction 1 until z is 0 -> zVelocity 0.5;
--     subAction 2 until z is 0 again -> Action3 (animation 1) / Action1
--     (animation 0), subtimer 0, sub_0808C148(TRUE) (the tiles restored).
--   * Standing, sub_0808C01C(this, 1) makes it a portal (Jar45.lua).
-- SIMPLIFIED: SPECIAL_TILE_146..149 (the jar's tiles while it hops) are not
--   set; the jar has no hit box of its own beyond the bolt's 10 px test.
local M = {}

local GRAV = 32 / 256

local function setAnim(f, e, i)
  e.objAnim = i
  if e.sprite then
    local spr = f.assets:sprite(e.sprite)
    if spr and e.anim then e.anim:set(spr, i, true) end
  end
end

local function portalOn(f, e, on)
  f.portals = f.portals or {}
  for i = #f.portals, 1, -1 do if f.portals[i].jar == e then table.remove(f.portals, i) end end
  if on then f.portals[#f.portals + 1] = { x = e.x, y = e.y, exit = 2, type = 2, layer = e.layer or 1, jar = e } end
end

local function hop(d, e)
  local f = d.field
  local h = e.jar54
  e.z = (e.z or 0) + h.zv
  h.zv = h.zv - GRAV
  if e.z <= 0 then e.z = 0 end
  if h.sub == 0 then
    if h.zv < 1.5 then h.sub = 1; setAnim(f, e, h.toUpright and 2 or 3) end
  elseif h.sub == 1 then
    if e.anim then e.anim:update(1) end
    if e.z == 0 then h.sub = 2; h.zv = 0.5 end
  else
    if e.anim then e.anim:update(1) end
    if e.z == 0 then
      e.upright = h.toUpright
      setAnim(f, e, e.upright and 1 or 0)
      e.jar54, e.extUpdate = nil, nil
      portalOn(f, e, e.upright)
    end
  end
end

-- Pacci.lua's bolt: e.onPacciObj(f, e, bolt) -> true ends the bolt
function M.flip(f, e)
  if e.jar54 then return false end
  local u7c = (e.type2 or 0) ~= 0
  local flag = e.form or 0
  if e.upright then -- Action3
    f:setFlag("local", flag, u7c)
  else -- Action1
    f:setFlag("local", flag, not u7c)
  end
  e.jar54 = { zv = 2.5, sub = 0, toUpright = not e.upright }
  portalOn(f, e, false)
  e.extUpdate = hop
  return true
end

return M
