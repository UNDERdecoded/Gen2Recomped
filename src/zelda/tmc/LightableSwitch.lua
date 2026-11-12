-- Round 22: LIGHTABLE_SWITCH ($9D), src/object/lightableSwitch.c.
--
-- CARTRIDGE BEHAVIOUR:
--   * Both types: COLLISION_ON, collisionFlags 7, hurtType $48, hitType
--     $28, collisionMask 10, gHitbox_0; type2 0: SPECIAL_TILE_80 on its tile
--     (solid), else it rides a rail from the room's property list (not used
--     on the route; not ported).
--   * type 0: frameIndex = (its flag field $86 set); each contact toggles
--     that flag (SFX_110).
--   * type 1: frameIndex 3 (unlit); already done (flag field $84 set):
--     frameIndex 2, action 3.  A contact: frameIndex 2, SetFlag($86),
--     SFX_110, 16 frames; then, unless $84 got set meanwhile (a
--     FLAG_AND_OPERATOR_MANAGER latches it), the flag clears again,
--     frameIndex 3, SFX_110.
--   The Crenel caves' bridge room ($26:02): a bomb thrown over the gap lights
--   it, BRIDGE_MANAGER lays the bridge.
-- What counts as a contact here: the sword's box (Items:swordFrame,
-- `f.swordBoxNow`), a bomb's blast box, a thrown object -- the matrix row
-- for hitType $28 hits for those.  SIMPLIFIED: the full collision matrix
-- is not consulted.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local L = {}
local OBJ = 0x9D
local SFX_110 = 0x110
local SP80 = 0x4050
L.HALF = 8 -- gHitbox_0: 8 x 8 half sizes around (0, 0)

local function contact(f, e)
  local h = L.HALF
  local sb = f.swordBoxNow
  if sb and sb.t == f.frame and math.abs(sb.x - e.x) < sb.w + h and math.abs(sb.y - e.y) < sb.h + h then return true end
  for _, t in ipairs(f.entities) do
    if not t.deleted and t ~= e then
      if t.hitW and t.hitList and math.abs(t.x - e.x) < t.hitW + h and math.abs(t.y - e.y) < t.hitW + h then return true end
      if (t.thrown or (t.bomb and t.action == 2 and t.carrySub == 2)) and math.abs(t.x - e.x) < 6 + h and math.abs(t.y - (t.z or 0) - e.y) < 6 + h then return true end
    end
  end
  return false
end
L.contact = contact

local function update(d, e)
  local f = d.field
  local hit = contact(f, e)
  if e.form == 0 then
    if hit and not e.wasHit then
      d:set(e.flag2, not d:check(e.flag2))
      f:sound(SFX_110)
    end
    e.staticFrame = d:check(e.flag2) and 1 or 0
  else
    if e.action == 1 then
      if hit then
        e.action, e.timer, e.staticFrame = 2, 16, 2
        d:set(e.flag2)
        f:sound(SFX_110)
      end
    elseif e.action == 2 then
      if d:check(e.flag1) then e.action = 3
      else
        e.timer = e.timer - 1
        if e.timer <= 0 then
          e.action, e.staticFrame = 1, 3
          d:set(e.flag2, false)
          f:sound(SFX_110)
        end
      end
    end
  end
  e.wasHit = hit
end
L.update = update

function L.spawn(d, e)
  if e.id ~= OBJ then return nil end
  local f = d.field
  local def = f:objects():def(OBJ, e.form or 0)
  if def then f:objects():dress(e, def, e.form or 0) end
  e.forceAnim = nil
  -- EntityData paramC: field $84 = the low half, $86 = the high half
  local pc = e.data and e.data.paramC or 0
  e.flag1, e.flag2 = band(pc, 0xFFFF), band(rshift(pc, 16), 0xFFFF)
  e.lightable = true
  if (e.type2 or 0) == 0 then
    local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
    f.room:setTile(e.layer or 1, tx, ty, SP80)
  end
  if (e.form or 0) == 0 then
    e.action = 1
    e.staticFrame = d:check(e.flag2) and 1 or 0
  else
    e.action, e.staticFrame = 1, 3
    if d:check(e.flag1) then e.action, e.staticFrame = 3, 2 end
  end
  e.extUpdate = function(dd, me) update(dd, me) end
  d:track(e)
  return e
end

return L
