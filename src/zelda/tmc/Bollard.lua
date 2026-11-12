-- Round 16: BOLLARD ($33), src/object/bollard.c.
--
-- CARTRIDGE BEHAVIOUR:
--   * type2 0 (Init: sub_0808B41C + sub_0808B3AC): raised -- animation 0,
--     spritePriority.b0 4, its tile saved and replaced by SPECIAL_TILE_11
--     (solid); Action1 waits for its flags (field $86, CheckFlags): then
--     animation 3 (going down), the saved tile put back, SFX_1A5; when the
--     animation is done (Action2) it lies lowered (Action3: animation 1,
--     spritePriority.b0 7).  Lowered, it comes back up (animation 2, the
--     tile solid again, SFX_1A5; Action4 then Action1 with animation 0) as
--     soon as the flags clear.
--   * type2 != 0 starts lowered and rises while the flags are SET (the same
--     actions with the test reversed).
-- Deepwood Shrine B1 room $15: four bollards across the channel up to the
-- compass room, lowered while room flag 0 (the button by the stairs) is set.
local B = {}
local OBJ = 0x33
local SFX_1A5 = 0x1A5

local function setAnim(d, e, a)
  e.objAnim, e.animIndex = a, a
  e.anim:set(d.field.assets:sprite(e.sprite), a, true)
end

local function raise(d, e)
  e.spritePriority = 4
  if not e.blocking then d:block(e.tx, e.ty, e.layer, true); e.blocking = true end
end

local function lower(d, e)
  if e.blocking then d:block(e.tx, e.ty, e.layer, false); e.blocking = false end
end

local function want(d, e)
  local set = d:check(e.flags86)
  if e.type2 == 0 then return set else return not set end -- true = lowered
end

local function update(d, e)
  local a = e.action
  if a == 1 then
    if want(d, e) then
      e.action = 2; setAnim(d, e, 3); lower(d, e); d.field:sound(SFX_1A5)
    end
  elseif a == 2 then
    e.anim:update(1)
    if e.anim.done then e.action = 3; e.spritePriority = 7; setAnim(d, e, 1) end
  elseif a == 3 then
    if not want(d, e) then
      e.action = 4; setAnim(d, e, 2); raise(d, e); d.field:sound(SFX_1A5)
    end
  elseif a == 4 then
    e.anim:update(1)
    if e.anim.done then e.action = 1; setAnim(d, e, 0) end
  end
end
B.update = update

function B.spawn(d, e)
  if e.id ~= OBJ then return nil end
  local f = d.field
  local def = f:objects():def(OBJ, e.form or 0)
  if def then f:objects():dress(e, def, 0) end
  e.forceAnim = nil
  e.flags86 = e.flag -- EntityData paramC >> 16 (field $86)
  e.tx, e.ty = math.floor(e.x / 16), math.floor(e.y / 16)
  e.bollard = true
  if e.type2 == 0 then
    e.action = 1; setAnim(d, e, 0); raise(d, e)
  else
    e.action = 3; e.spritePriority = 7; setAnim(d, e, 1)
  end
  e.extUpdate = function(dd, me) update(dd, me) end
  d:track(e)
  return e
end

return B
