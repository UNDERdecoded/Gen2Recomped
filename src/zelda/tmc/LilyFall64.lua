-- Round 64: the large lily pad over the Temple of Droplets' falls
-- (lilypadLarge.c LilypadLarge_Action2 / LilypadLarge_Init).
--
-- CARTRIDGE BEHAVIOUR (ported; gArea.locationIndex 27 = the Temple of
-- Droplets):
--   * sub_08085A44: to the current's middle at $200 (west while the act
--     tile at (+16, +24) is not ACT_TILE_17, east while (-16, +24) is not),
--     then south (subAction 1).
--   * sub_08085A98: south at $200 until the act tile at (0, +24) is not
--     ACT_TILE_17; then in the temple y += $D0, z = -$D0 (the falls are
--     $D0 high, elsewhere $40), unk_82 = $46 (elsewhere $0F) and
--     SetLocalFlag($73) (LilypadWestB2's own pad, type2 $73, is there from
--     now on); SFX_12D.
--   * sub_08085B40: the pad falls with GravityUpdate(32.0) carrying Link;
--     landed, ResetCollisionLayer; on ACT_TILE_13 (a pit) the pad goes
--     (LilypadLarge_Action4) and Link is moved a pixel toward it -- he is
--     no longer on a pad and falls (in West Waterfall South-west: its hole
--     manager -> LilypadWestB2).  Link stays held until unk_82 runs out,
--     then lands (ResetCollisionLayer) and is free.
--   * LilypadLarge_Init: in the temple a pad of a type other than 0 whose
--     local flag (type2) is clear is deleted (elsewhere it waits, Action5).
-- SIMPLIFIED: LILYPAD_LARGE_FALLING (the pad's copy drawn at the top of the
-- falls, growing as it drops) and the pad's growing fade on a pit
-- (Action4's scale steps) are not drawn: the pad is deleted on landing.
local L = {}
L.LOC_TOD = 27
L.ACT_CURRENT, L.ACT_PIT = 0x11, 0x0D
L.FLAG_FALLEN = 0x73
L.DROP, L.HOLD = 0xD0, 0x46
L.SPEED = 0x200 / 256
L.GRAVITY = 32 / 256
L.SFX_12D = 0x12D

function L.inTemple(f)
  local r = f and f.room
  return r and r.areaInfo and r.areaInfo.location == L.LOC_TOD or false
end

-- LilypadLarge_Init (LilyRide.init): true when the pad is deleted
function L.initDeletes(f, e)
  return L.inTemple(f) and e.form ~= 0 and e.form ~= 0xFF and not f:flag("local", e.type2)
end

-- Dungeon:lilyDrop for the temple; returns true when it handled the frame
function L.drop(d, e, p)
  local f = d.field
  if not L.inTemple(f) then return false end
  local s = e.drop
  if s.phase == 0 then
    if d:actAt(e.x + 0x10, e.y + 0x18, e.layer) ~= L.ACT_CURRENT then e.x = e.x - L.SPEED
    elseif d:actAt(e.x - 0x10, e.y + 0x18, e.layer) ~= L.ACT_CURRENT then e.x = e.x + L.SPEED
    else s.phase = 1 end
  elseif s.phase == 1 then
    e.y = e.y + L.SPEED
    if d:actAt(e.x, e.y + 0x18, e.layer) ~= L.ACT_CURRENT then
      s.phase = 2
      e.y, e.z, e.zv, s.hold = e.y + L.DROP, L.DROP, 0, L.HOLD
      f:setFlag("local", L.FLAG_FALLEN, true)
      f:sound(L.SFX_12D)
    end
  else
    if (e.z or 0) > 0 then
      e.zv = (e.zv or 0) + L.GRAVITY
      e.z = math.max(0, e.z - e.zv)
      if e.z == 0 then
        e.layer = 1 -- ResetCollisionLayer
        if d:actAt(e.x, e.y, 1) == L.ACT_PIT then s.pit = true end
      end
    end
    if s.hold > 0 then s.hold = s.hold - 1
    elseif e.z == 0 then
      e.drop, e.zv = nil, nil
      p.state, p.extUpdate = "normal", nil
      p.layer = 1
      p.x, p.y, p.z = e.x + s.ox, e.y + s.oy, 0
      if s.pit then
        e.deleted = true -- LilypadLarge_Action4
        local dx, dy = e.x - p.x, e.y - p.y
        local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        p.x, p.y = p.x + dx / dd, p.y + dy / dd
      end
      return true
    end
  end
  p.x, p.y = e.x + s.ox, e.y + s.oy
  p.z = s.phase == 2 and math.max(0, e.z or 0) or 0
  return true
end

return L
