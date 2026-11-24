-- Round 78: an arrow lights a LIGHTABLE_SWITCH ($9D), hooked from LightableSwitch.contact.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * lightableSwitch.c: the switch is COLLISION_ON with hitType $28 (collisionFlags 7, collisionMask 10,
--     gHitbox_0); its Action1 toggles flag2 on any CONTACT_NOW.
--   * collision.c: a player item (org) meets an object (tgt) through gCollisionMtx[tgt->hitType * 34 +
--     org->hurtType].  Row $28 at the arrow's hurtType $15 (and the light arrow's $0E) is a plain ColSettings entry
--     (CollisionDefault, flag COL_FLAG_8): the switch is hit and the arrow takes the contact
--     (PlayerItemBow_Action1: contactFlags & $80 -> gone).  The port's switch only counted the sword, a bomb's
--     blast and thrown objects, so an arrow flew through it -- $70:30 (the Palace of Winds' bridge room) has a
--     switch behind three blocks and others across the sky gaps that the cartridge lights with arrows.
--   * IsColliding: the boxes overlap when |dx| <= wA + wB and |dy| <= hA + hB (offsets 0), the layers share a bit
--     and |dz| <= 10; the arrow's box is gUnk_080B3E70 / 78 (4 x 6 flying north / south, 6 x 4 east / west, as
--     ItemBow.collide).
--   The entry is read from the player's ROM (colmtx.bin, gCollisionMtx): a special handler ($FF: CollisionNoOp
--   and the like) is no contact.
-- SIMPLIFIED: COL_FLAG_8's HIT_SWITCH spark (sub_08017A90) is not created.
local bit = require("bit")
local band = bit.band

local M = {}

M.SWITCH_HIT_TYPE = 0x28

-- the gCollisionMtx entry (hitType, hurtType) is a plain ColSettings (not a $FF handler)
function M.matrixHits(f, hitType, hurtType)
  local okE, en = pcall(function() return f:enemies() end)
  local mtx = okE and en and en.mtx
  if not mtx or #mtx == 0 then return hurtType == 0x15 or hurtType == 0x0E end -- no cache table: the two arrow types
  local o = (hitType * 34 + hurtType) * 12
  local b0 = mtx:byte(o + 1)
  return b0 ~= nil and b0 ~= 0xFF
end

-- an arrow in flight touching the switch e (half size h); the arrow takes the contact
function M.switchContact(f, e, h)
  for _, a in ipairs(f.entities) do
    if a.arrow and not a.deleted and a.action == 1 and a.collision
       and band(a.layer or 1, e.layer or 1) ~= 0 and math.abs((a.z or 0) - (e.z or 0)) <= 10 then
      local vert = band(a.dir or 0, 8) == 0
      local aw, ah = vert and 4 or 6, vert and 6 or 4
      if math.abs(a.x - e.x) <= aw + h and math.abs(a.y - e.y) <= ah + h
         and M.matrixHits(f, M.SWITCH_HIT_TYPE, a.hurtType or 0x15) then
        a.contact = true
        return true
      end
    end
  end
  return false
end

return M
