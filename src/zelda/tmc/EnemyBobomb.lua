-- Round 22: BOBOMB ($22), src/enemy/bobomb.c (the Cave of Flames).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Init (sub_0802C8D8): action 1, timer 60, direction (Random & $18) |
--     DIR_DIAGONAL, gustJarFlags $12, unlit; animation direction >> 4.
--   * Walk (sub_0802C91C): GetNextFrame + ProcessMovement0; a wall bounces
--     it (sub_0800417E).  Unlit: every 60 frames it turns ((dir + 8) & $1C).
--     Lit: animation | 2, the fuse SFX_14D every 28 frames, a dash puff every
--     16 frames (not drawn here), and when the timer runs out it blows up.
--   * OnCollision (contactFlags | CONTACT_NOW): Link's body (0 / 1) while lit
--     only pushes Link back (knockback 4); $0E / $14 / $15 / $16 (arrows,
--     blasts) blow it up at once; anything else lights it: the first hit
--     (unk_82 1, sub_0802CB68) -- lit walking at speed $200 for 200 frames,
--     SFX_14D; the second hit -- action 3, hitType $6E, a hop (zVelocity
--     1.5), stopped, animation (dir >> 4) | 6: it lies there to be lifted.
--   * Action 3 (sub_0802CAF8): the fuse runs out -> sub_0802CBC4; it bounces
--     (BounceUpdate 40), it can be lifted (RegisterCarryEntity); carried it
--     keeps ticking and goes off in Link's hands (PlayerDropHeldObject);
--     thrown (sub_0802CA94) it lands, bounces and goes off where it is.
--   * sub_0802CBC4: action 4, invisible, health 0, a SMOKE_PARTICLE (the
--     bomb blast, Bombs.smoke) at its place.
-- SIMPLIFIED: the Gust Jar's grab (Bobomb_OnGrabbed) is not ported (it is
-- treated like any other foe there); the dash puffs are not drawn.
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local B = {}
B.ID = 0x22
local SFX_14D, SFX_PLACE_OBJ, SFX_THROW = 0x14D, 0x104, 0x7C
local EXPLODE_NOW = { [0x0E] = true, [0x14] = true, [0x15] = true, [0x16] = true }

local function D() return require("src.zelda.tmc.Drops") end
local function R(f) return D().random(D().rngOf(f)) end
local function move0(E, e, dir, spd) return require("src.zelda.tmc.EnemyDeepwood").move0(E, e, dir, spd) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function bounceOff(e, hx, hy)
  local d = e.dir
  if hx then d = 0x20 - d end
  if hy then d = 0x10 - d end
  e.dir = band(d, 0x1F)
end

function B.handles(e) return e.id == B.ID end

-- sub_0802CC18: the fuse sound
local function fuse(f, e)
  e.u80 = (e.u80 or 28) - 1
  if e.u80 <= 0 then e.u80 = 28; f:sound(SFX_14D) end
end

-- sub_0802CBC4: it goes off
function B.explode(E, e)
  local f = E.field
  e.action = 4
  e.hidden = true
  e.noTouch = true
  e.health = 0
  e.liftable = nil
  local p = f.player
  if e.carriedBy and p and p.carried and p.carried.ent == e then
    p.carried = nil
    if p.state == "carry" then p.state = "normal" end
  end
  e.carriedBy = nil
  require("src.zelda.tmc.Bombs").smoke(f, e.x, e.y, e.layer or 1)
  e.deleted = true
end

-- sub_0802CB68: walking again (lit after the first hit)
local function walk(E, e)
  local f = E.field
  e.action = 1
  e.dir = bor(band(R(f), 0x18), 4)
  e.noTouch = nil
  if (e.u82 or 0) ~= 0 then
    e.timer, e.speed = 200, 0x200
    setAnim(E, e, bor(rshift(e.dir, 4), 2))
  else
    e.timer, e.speed = 60, 0x80
    setAnim(E, e, rshift(e.dir, 4))
  end
end

function B.collision(E, e, flags)
  local f = E.field
  if band(flags, 0x80) == 0 then return end
  local k = band(flags, 0x7F)
  if k == 0 or k == 1 then
    if (e.u82 or 0) ~= 0 then e.kbt = 0 end
    return
  end
  if EXPLODE_NOW[k] then e.kbt = 0; B.explode(E, e) return end
  e.u82 = (e.u82 or 0) + 1
  e.u80 = 28
  if e.u82 == 1 then
    walk(E, e)
    f:sound(SFX_14D)
  elseif e.u82 == 2 then
    e.action, e.hitType = 3, 0x6E
    e.subtimer = 1
    e.czv, e.cz = 0x18000, 0
    e.speed = 0
    e.u81 = 1
    if not e.timer or e.timer <= 0 then e.timer = 120 end
    setAnim(E, e, bor(rshift(e.dir or 0, 4), 6))
  end
end

-- the carry system (RegisterCarryEntity / PlayerItemHeldObject)
local carryHook = {}
function carryHook.lift(f, p, e)
  e.carriedBy, e.hidden, e.noTouch, e.liftable = p, true, true, nil
  e.action = 2
  f:objects():lift(p, { obj = e.id, form = e.animIndex or 6, ent = e, hook = carryHook,
    def = { sprite = e.sprite, palette = e.def and e.def.palette, gfxType = "enemy", gfx = e.def and e.def.gfx } })
  return true
end
local function release(f, p, c, vx, vy, z)
  local e = c.ent
  p.carried = nil
  e.carriedBy, e.hidden = nil, false
  e.x, e.y = p.x, p.y
  e.thrownV = { vx, vy }
  e.cz, e.czv = -(z or 14) * 65536, 0x18000 -- sub_0802CA94: zVelocity 1.5
  e.action, e.subtimer, e.u81 = 3, 1, 0
  e.noTouch = true
end
function carryHook.throw(f, p, c)
  local s = p.animationState
  release(f, p, c, (s == 2 and 1 or s == 6 and -1 or 0) * 2, (s == 4 and 1 or s == 0 and -1 or 0) * 2, 14)
  f:sound(SFX_THROW)
end
function carryHook.drop(f, p, c) release(f, p, c, 0, 0, 4) end
B.carryHook = carryHook

function B.update(E, e)
  local f = E.field
  if e.action == 0 then
    e.timer, e.subtimer = 60, 0
    e.dir = bor(band(R(f), 0x18), 4)
    e.gustJarFlags = 0x12
    e.u82, e.u83, e.u80, e.u81 = 0, 0, 0, 0
    e.action = 1
    e.speed = e.speed or 0x80
    e.onCollision = B.collision
    e.carryHook = function(ff, p, x) if x.action == 3 then return carryHook.lift(ff, p, x) end return false end
    setAnim(E, e, rshift(e.dir, 4))
    return
  end
  if e.action == 1 then
    e.anim:update(1)
    local hx, hy = move0(E, e, e.dir, e.speed or 0x80)
    if (e.u82 or 0) ~= 0 then
      if hx or hy then bounceOff(e, hx, hy); setAnim(E, e, bor(rshift(e.dir, 4), 2)) end
      e.timer = e.timer - 1
      if e.timer <= 0 then return B.explode(E, e) end
      fuse(f, e)
    else
      if hx or hy then bounceOff(e, hx, hy); setAnim(E, e, rshift(e.dir, 4)) end
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.timer = 60
        e.dir = band(e.dir + 8, 0x1C)
        setAnim(E, e, rshift(e.dir, 4))
      end
    end
  elseif e.action == 2 then
    -- carried (sub_0802CA10): it keeps ticking in Link's hands
    e.timer = (e.timer or 1) - 1
    if e.timer <= 0 then return B.explode(E, e) end
    fuse(f, e)
    e.anim:update(1)
    local p = f.player
    if p and p.carried and p.carried.ent == e then e.x, e.y = p.x, p.y end
  elseif e.action == 3 then
    e.timer = (e.timer or 1) - 1
    if e.timer <= 0 then return B.explode(E, e) end
    if e.thrownV then
      e.x, e.y = e.x + e.thrownV[1], e.y + e.thrownV[2]
      if f.room:isSolid(e.x, e.y, 1) then e.x, e.y = e.x - e.thrownV[1], e.y - e.thrownV[2]; e.thrownV = nil end
    end
    if (e.u81 or 0) ~= 0 or e.thrownV or (e.cz or 0) < 0 then
      local r = require("src.zelda.tmc.EnemyCrenel").bounce(e, 0x2800)
      if r == 1 then f:sound(SFX_PLACE_OBJ); e.thrownV = nil end
      if r == 0 then e.thrownV = nil; e.u81 = 0 end
    end
    fuse(f, e)
    e.liftable = (e.cz or 0) >= 0
    if (e.subtimer or 0) ~= 0 and (e.cz or 0) >= 0 then
      e.subtimer = 0
      e.noTouch = nil
      e.hitType = 0x6E
    end
    e.anim:update(1)
  end
  e.z = -(e.cz or 0) / 65536
end

return B
