-- Round 17: objects that were blank -- FAIRY ($40) and LADDER_HOLE ($65).
-- Dungeon:spawnObject offers every object here (any area).
--
-- CARTRIDGE BEHAVIOUR
--   * FAIRY (src/object/fairy.c + scroll.c sub_08080CB4): the object's
--     animation is its type (InitAnimationForceUpdate(this, type): $60, the
--     fairy item's animation), so the port's "animation 0" drew nothing.
--     Fairy_Init: hit type 7, hurt type $49, home = the spawn point, SFX_136;
--     type2 0 rises (zVelocity 1.875) and times out (600 frames, blinking
--     the last 120), other types (the fountains' $26 rooms) stay.  Action 1
--     rises 0.875 a frame until the animation's first keyframe; action 2:
--     every 32 frames a speed ($80 or $60, R >> 8 & 1) and a direction (R &
--     $1F within $30 of home, else toward it), flipX when it turns left /
--     right; a sparkle (FX_SPARKLE) every (R & $1F) + 10 frames.  Touching
--     Link (CollisionDefault, contact 0): sub_0808DAD0 -- it circles him
--     (Action4: x = sin * $A, y = -cos * 5, timer += 8) rising one px each
--     6 frames to -$16, then ItemOnGround_SetFlagAndDelete: the fairy item
--     (six hearts back).
--   * LADDER_HOLE (ladderHoleInBookshelf.c): no animation -- a zeroed
--     entity's frameIndex 0 -- on layer 2 (over Link) until Link comes
--     within $1C px across; then it drops to layer 1 (priority 5) unless
--     he is climbing / using the entrance (then back to layer 2, priority 1).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local B = {}
B.FAIRY, B.LADDER_HOLE = 0x40, 0x65
local SFX_136, FX_SPARKLE, SPECIAL_FX = 0x136, 0x07, 0x0F
local ITEM_FAIRY = 0x60

local function rnd() return math.random(0, 0xFFFF) end

local function fairyUpdate(d, e)
  local f = d.field
  local p = f.player
  e.anim:update(1)
  if e.circling then
    e.ct = (e.ct + 8) % 256
    local a = e.ct / 256 * 2 * math.pi
    e.x, e.y = p.x + math.sin(a) * 10, p.y - math.cos(a) * 5
    e.z = (p.z or 0)
    e.sub6 = e.sub6 - 1
    if e.sub6 <= 0 then
      e.sub6 = 6
      e.spriteOY = (e.spriteOY or -5) - 1
      if e.spriteOY < -0x16 then
        e.deleted = true
        f:giveItem(ITEM_FAIRY, 0)
      end
    end
    return
  end
  if e.action == 1 then
    e.z = e.z + 0.875
    if e.anim.frame and e.anim.frame ~= 0xFF and (e.age or 0) > 0 then e.action, e.sub = 2, 1; e.speed = 0x80 end
    e.age = (e.age or 0) + 1
    return
  end
  -- action 2
  e.sub = e.sub - 1
  if e.sub <= 0 then
    local r = rnd()
    e.sub = 32
    e.speed = ({ [0] = 128, 96 })[band(rshift(r, 8), 1)]
    if math.abs(e.x - e.homeX) <= 0x30 and math.abs(e.y - e.homeY) <= 0x30 then e.direction = band(r, 0x1F)
    else
      local a = math.atan2(e.homeX - e.x, -(e.homeY - e.y))
      e.direction = band(math.floor(a / (2 * math.pi) * 32 + 0.5), 31)
    end
    if band(e.direction, 0xF) ~= 0 then e.flipX = band(rshift(e.direction, 4), 1) == 0 end
  end
  local a = e.direction / 32 * 2 * math.pi
  local nx, ny = e.x + math.sin(a) * e.speed / 256, e.y - math.cos(a) * e.speed / 256
  if not f.room:isSolid(nx, ny, 1) then e.x, e.y = nx, ny end
  -- the sparkle
  e.spark = (e.spark or 0) - 1
  if e.spark <= 0 then
    e.spark = band(rnd(), 0x1F) + 10
    if f.addFx then f:addFx(e.x, e.y - (e.z or 0), SPECIAL_FX, FX_SPARKLE) end
  end
  if e.timeout then
    e.timeout = e.timeout - 1
    e.hidden = e.timeout < 0x78 and band(e.timeout, 1) == 1
    if e.timeout <= 0 then e.deleted = true end
  end
  -- caught by Link
  if not p.minish and p.state ~= "dead" and math.abs(p.x - e.x) < 10 and math.abs((p.y - 3) - (e.y - (e.z or 0))) < 12 then
    e.circling, e.ct, e.sub6, e.spriteOY, e.hidden = true, 0, 6, -5, false
  end
end

local function ladderUpdate(d, e)
  local p = d.field.player
  local near = p.x - e.x + 0x1C >= 0 and p.x - e.x + 0x1C < 0x39
  if not near then return end
  local climbing = p.state == "climb" or p.climbing
  if e.layer == 2 then
    if not climbing then e.layer, e.spritePriority = 1, 5 end
  elseif climbing then e.layer, e.spritePriority = 2, 1 end
end

-- nil: not ours
function B.spawn(d, e)
  local O = d.field:objects()
  if e.id == B.FAIRY then
    local def = O:def(B.FAIRY, e.form)
    if not def then return nil end
    O:dress(e, def, e.form)
    e.objAnim = e.form -- sub_08080CB4: the animation is the type
    e.homeX, e.homeY = e.x, e.y
    e.action, e.sub = 1, 1
    e.layer = 3
    if (e.type2 or 0) == 0 then e.z = 8; e.timeout = 600 end
    e.extUpdate = fairyUpdate
    d.field:sound(SFX_136)
    d:track(e)
    return e
  elseif e.id == B.LADDER_HOLE then
    local def = O:def(B.LADDER_HOLE, e.form)
    if not def then return nil end
    O:dress(e, def, 0)
    e.staticFrame = 0
    e.layer, e.spritePriority = 2, 1
    e.extUpdate = ladderUpdate
    d:track(e)
    return e
  end
  return nil
end

return B
