-- Round 52: the item a FALLING_ITEM manager drops (src/manager/fallingItemManager.c,
-- src/object/itemOnGround.c).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * FallingItemManager_Action1: once flag field_0x3e is set it creates
--     GROUND_ITEM(type, type2) with timer = field_0x35 (the ItemOnGround
--     kind), collisionLayer = field_0x36, its x / y and flag = field_0x3c,
--     then deletes itself.
--   * The kind picks the init / action-2 pair (sItemOnGround_Init_Kinds /
--     gUnk_0811E814):
--       kind 2 (Kind2_Init): action 2 at once, collision on, z = -$80 (128 px
--         up), SFX_12D; Kind2_Action2 = sub_0808153C only: it never times
--         out.
--       kind 3: as kind 2 with unk_6c = 600 + 80 frames, then
--         sub_080814C0 counts it down (blinking under 90) and it goes.
--       kind 4: action 2, collision on, nothing more (the item just lies).
--       kinds 0 / 1 / 5 / 6 / 10: the port's existing paths (Objects).
--   * sub_0808153C: unk_68 0: GravityUpdate(Q_8_8(16)) until it reaches
--     the ground, then zVelocity 1.875, the item's bounce sound, unk_68 1;
--     unk_68 1: GravityUpdate(Q_8_8(40)) until it lands again, the sound,
--     unk_68 2 (still).
-- The port spawned every falling item as a kind-0 drop from z 48: it
-- bounced and timed out after 600 frames, so $18:04's small key (kind 2)
-- was gone ten seconds after the button.
-- SIMPLIFIED: sub_0800442E (an item landing on a pit / water / lava / swamp
-- tile is lost with its fx) is not ported; FALLING_ITEM drop points are floor.
local M = {}

M.KIND2_Z = 0x80         -- Kind2_Init: z.HALF.HI = -0x80
M.G_FALL = 16 * 256      -- Q_8_8(16.0) in Q16
M.G_BOUNCE = 40 * 256    -- Q_8_8(40.0)
M.BOUNCE_V = math.floor(1.875 * 65536)
M.SFX_12D = 0x12D

-- the manager's ground item (Dungeon's FALLING_ITEM); returns the entity
function M.spawn(f, m)
  local kind = m.b1 or 0
  local objs = f:objects()
  if kind ~= 2 and kind ~= 3 then
    local g = objs:groundItem(m.type, m.type2, m.x, m.y, { drop = kind ~= 4, kind = kind })
    if g then
      g.flagSpec = m.c0
      if kind ~= 4 then g.z, g.zv, g.life = 48, 0, nil end -- the old drop path for the other kinds
      if m.b32 and m.b32 ~= 0 then g.layer = m.b32 end
    end
    return g
  end
  local g = objs:groundItem(m.type, m.type2, m.x, m.y, { kind = kind })
  if not g then return nil end
  g.flagSpec = m.c0
  if m.b32 and m.b32 ~= 0 then g.layer = m.b32 end
  g.act, g.static = 2, true
  g.cz, g.czv = -M.KIND2_Z * 65536, 0
  g.z = M.KIND2_Z
  g.fall52 = 0
  if kind == 3 then g.t52 = 600 + 80 end
  f:sound(M.SFX_12D)
  return g
end

-- each frame before the ground item's own update; true = the item is gone
function M.update(objs, e)
  local f = objs.field
  if e.t52 and not (f.textbox or f.playerScript or f:inputLocked()) then
    e.t52 = e.t52 - 1
    if e.t52 <= 0 then e.deleted = true return true end
    if e.t52 < 90 then e.hidden = not e.hidden end
  end
  if e.fall52 >= 2 then return false end
  local g = e.fall52 == 0 and M.G_FALL or M.G_BOUNCE
  local nz = e.cz - e.czv
  if nz >= 0 then
    e.cz, e.czv = 0, 0
    if e.fall52 == 0 then e.fall52, e.czv = 1, M.BOUNCE_V else e.fall52 = 2 end
    local sfx = objs.m.drops and objs.m.drops.itemSfx and objs.m.drops.itemSfx[e.item]
    if sfx and sfx ~= 0 then f:sound(sfx) end
  else
    e.cz, e.czv = nz, e.czv - g
  end
  e.z = -e.cz / 65536
  return false
end

return M
