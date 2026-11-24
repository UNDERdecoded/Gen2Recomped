-- Round 45: JAR_PORTAL ($38, src/object/jarPortal.c) -- the jar a Minish
-- portal sits in (Rem's Shoe Shop $23:02: the way to the Town Minish under
-- the shop).  An R27A module (spawnObject).
--
-- CARTRIDGE BEHAVIOUR:
--   * JarPortal_Init: its local flag = type; unk_7c = the EntityData's type2
--     byte (RegisterRoomEntity copies the data to +$78).  Flag clear: lying
--     (action 1, animation 0) when unk_7c is 0, else standing (action 3,
--     animation 1); a set flag swaps the two.
--   * Standing (sub_0808C01C(this, 1)): Link within its $30 x $30 box sets
--     gArea.portal_x / portal_y = the jar, portal_exit_dir 2, portal_type
--     PT_2 and portal_mode 2 (Link on it, PL_USE_PORTAL) / 3 (Minish,
--     PortalReadyForMinish), SFX_NEAR_PORTAL once: the portal works as the
--     stump ones (PortalJump.lua / Objects:tryPortal).
-- SIMPLIFIED: the flip (a hit of type $1D: contactFlags == CONTACT_NOW |
--   $1D -> the hop, the local flag toggled, SPECIAL_TILE_146..149 while it
--   moves) is not modelled; the magic sparkles are not drawn.
local M = {}

M.OBJ = 0x38

function M.spawnObject(d, e)
  if e.id ~= M.OBJ then return nil end
  local f = d.field
  local flag = f:flag("local", e.form or 0)
  local u7c = (e.type2 or 0) ~= 0
  local upright = (flag and not u7c) or (not flag and u7c)
  local def = f:objects():def(M.OBJ, 0)
  if def then f:objects():dress(e, def, 0) end
  e.objAnim = upright and 1 or 0
  e.jarPortal = true
  e.onPacciObj = function(f2, me) return require("src.zelda.tmc.Jar54").flip(f2, me) end -- round 54: the flip (jarPortal.c)
  e.upright = upright
  if upright then
    f.portals = f.portals or {}
    f.portals[#f.portals + 1] = { x = e.x, y = e.y, exit = 2, type = 2, layer = e.layer or 1, jar = e }
  end
  d:track(e)
  return e
end

return M
