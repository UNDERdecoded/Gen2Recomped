-- Round 24: more Cave of Flames enemies, from the decomp.
--
-- CHASER ($1D, src/enemy/chaser.c): a spiked block.
--   Action 0: action 1, animation 0.
--   Action 1: waits out its timer; then lined up with Link
--     (sub_0804A024(.., 1, $0C)) -> action 2, speed $40, that direction.
--   Action 2: GetNextFrame; touching anything (CONTACT_NOW) -> speed $40;
--     ProcessMovement12 moves it: free -> animation 1, speed + 4 up to
--     $220; blocked -> action 3, animation 2 (the bump).
--   Action 3: animation done -> action 1, timer 30, animation 0.
--   It cannot be hurt (its definition's hit type); knockback / death are the
--   generic ones.
-- SPINY_CHUCHU ($0B, src/enemy/spinyChuchu.c):
--   Init (sub_080225EC): home rectangle, unk_80 = health, unk_81 $5A;
--     timer 0 -> action 2, animation 0; else action 1 (falls from the
--     ceiling: subtimer 60, z 128, animation 6).
--   Action 1: subtimer -> SFX_12D, animation 0, GravityUpdate(24) until it
--     lands (animation 5, SFX_PLY_LAND), then its timer -> action 3, hitType
--     $65, animation 2 (spikes out).
--   Action 2: Link in its home: subtimer 0 and Link within $28 -> action 3;
--     else unk_81 0 and within $40 -> action 6 (a hop at Link: zVelocity
--     1.125, speed $140, hitType $5A, animation 4); else every 8 frames a
--     new direction at Link (sub_08049F84), ProcessMovement0.
--   Action 3: animation done -> action 4, animation 3, SFX_194.
--   Action 4: frame bit 0 -> hitbox 32 else 23; frame bit 1 -> hitType $5C;
--     done -> action 2, subtimer gUnk_080CBA60[Random & 3] (10/20/30/20).
--   Action 5 (stunned): GravityUpdate(24); animation done -> action 2, speed
--     $20, animation 0.
--   Action 6: on frame bit 0 ProcessMovement2 + GravityUpdate(24); landed ->
--     action 7, hitType $5C, animation 5, SFX_PLY_LAND.
--   Action 7: animation done -> action 2, speed $20, unk_81 $78.
--   OnCollision: spikes out (hitType $65): the shield (2/3) -> action 2,
--     subtimer 60, hitType $5C; the sword etc. (8-$C, $16, $18-$1A) ->
--     stars, action 5, hitType $5C, animation 1.  Bomb blast ($14) -> action
--     5.  Health lost -> action 5, hitType $5C, animation 1; else in action 3
--     -> action 4.
-- SIMPLIFIED: FX_STARS / the death squash (frame bit 0 GenericDeath) are
--   not drawn; the shared generic knockback is the port's.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local C = {}
C.SPINY_CHUCHU, C.CHASER, C.RUPEE_LIKE = 0x0B, 0x1D, 0x17
local SFX_12D, SFX_194, SFX_PLY_LAND = 0x12D, 0x194, 0x7D
local SPINY_WAIT = { [0] = 10, 20, 30, 20 } -- gUnk_080CBA60

local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function D() return require("src.zelda.tmc.Drops") end
local function R(f) return D().random(D().rngOf(f)) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function move(E, e, dir, spd) local hx, hy = DW().move0(E, e, dir, spd) return not (hx or hy) end
local function dirTo(ax, ay, bx, by) return DW().dirTo(ax, ay, bx, by) end
local function syncZ(e) e.z = -(e.cz or 0) / 65536 end
local function gravity(e, g)
  local z = (e.cz or 0) - (e.czv or 0)
  if z < 0 then e.cz = z; e.czv = (e.czv or 0) - g; syncZ(e) return true end
  e.cz, e.czv = 0, 0; syncZ(e)
  return false
end
local function flags(e) return e.anim and e.anim.flags or 0 end
local function done(e) return e.anim and e.anim.done end
local function targetHome(E, e)
  local t = DW().target(E.field)
  if not t then return nil end
  local dx, dy = math.floor(t.x) - e.homeX, math.floor(t.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH and t or nil
end
-- PlayerInRange(ent, 1, d): same layer, distance <= d
local function inRange(E, e, d)
  local t = DW().target(E.field)
  if not t or band(t.layer or 1, e.layer or 1) == 0 then return false end
  return (math.floor(t.x) - math.floor(e.x)) ^ 2 + (math.floor(t.y) - math.floor(e.y)) ^ 2 <= d * d
end
local function lined(E, e, w) return require("src.zelda.tmc.EnemyBeetle").linedUp(E, e, w) end

function C.handles(e) return e.id == C.SPINY_CHUCHU or e.id == C.CHASER end

-- ===========================================================================
-- CHASER
-- ===========================================================================
function C.chaserCollision(E, e, fl)
  if e.action == 2 then e.spd = 0x40 end
end
function C.chaser(E, e)
  if e.action == 0 then
    e.action = 1
    e.timer = band(rshift(e.spawnB or 0, 8), 0xFF)
    e.onCollision = C.chaserCollision
    setAnim(E, e, 0)
  elseif e.action == 1 then
    if (e.timer or 0) ~= 0 then e.timer = e.timer - 1
    else
      local dir = lined(E, e, 0x0C)
      if dir then e.action, e.spd, e.dir = 2, 0x40, dir end
    end
  elseif e.action == 2 then
    e.anim:update(1)
    if move(E, e, e.dir, e.spd) then
      if e.animIndex ~= 1 then setAnim(E, e, 1) end
      if e.spd < 0x220 then e.spd = e.spd + 4 end
    else
      e.action = 3
      setAnim(E, e, 2)
    end
  elseif e.action == 3 then
    e.anim:update(1)
    if done(e) then e.action, e.timer = 1, 30; setAnim(E, e, 0) end
  end
end

-- ===========================================================================
-- SPINY_CHUCHU
-- ===========================================================================
local HB23, HB32 -- gHitbox_23 / gHitbox_32 (the definition's box / the spiked one)
function C.spinyCollision(E, e, fl)
  local k = band(fl, 0x7F)
  if e.health > 0 then
    if e.hitType == 0x65 then
      if k == 2 or k == 3 then
        e.action, e.subtimer, e.hitType = 2, 60, 0x5C
        e.hitbox = e.box23
        setAnim(E, e, 0)
      elseif (k >= 8 and k <= 0xC) or k == 0x16 or (k >= 0x18 and k <= 0x1A) then
        e.action, e.hitType = 5, 0x5C
        setAnim(E, e, 1)
      end
    elseif fl == 0x80 + 0x14 then
      e.action = 5
      setAnim(E, e, 1)
    end
    if e.u80 ~= e.health then
      e.action, e.hitType = 5, 0x5C
      setAnim(E, e, 1)
    elseif e.action == 3 then
      e.action = 4
      setAnim(E, e, 3)
      E.field:sound(SFX_194)
    end
  else
    setAnim(E, e, 1)
  end
  e.u80 = e.health
end

function C.spiny(E, e)
  local f = E.field
  local a = e.action
  if a == 0 then
    e.u80, e.u81 = e.health, 0x5A
    e.box23 = e.hitbox
    e.onCollision = C.spinyCollision
    e.timer = band(rshift(e.spawnB or 0, 8), 0xFF)
    e.cz, e.czv = 0, 0
    if e.timer == 0 then
      e.action = 2
      setAnim(E, e, 0)
    else
      e.action, e.subtimer, e.sub = 1, 60, 0
      e.cz = -128 * 65536; syncZ(e)
      e.noTouch = true
      setAnim(E, e, 6)
    end
  elseif a == 1 then
    if e.sub == 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer ~= 0 then return end
      e.sub = 1
      f:sound(SFX_12D)
      setAnim(E, e, 0)
    end
    if e.sub == 1 then
      if gravity(e, 0x1800) then return end
      e.sub = 2
      e.noTouch = nil
      setAnim(E, e, 5)
      f:sound(SFX_PLY_LAND)
    end
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.action, e.hitType = 3, 0x65
      setAnim(E, e, 2)
    end
  elseif a == 2 then
    if targetHome(E, e) then
      local st = e.subtimer or 0
      local near40
      if st == 0 then
        if inRange(E, e, 0x28) then
          e.action, e.hitType = 3, 0x65
          setAnim(E, e, 2)
          return
        end
      else e.subtimer = st - 1 end
      if (e.u81 or 0) == 0 then near40 = inRange(E, e, 0x40) else e.u81 = e.u81 - 1 end
      if near40 then
        local t = DW().target(f)
        e.action, e.czv, e.spd = 6, 0x12000, 0x140
        e.dir = dirTo(e.x, e.y, t.x, t.y)
        e.hitType = 0x5A
        setAnim(E, e, 4)
        return
      end
      e.timer = (e.timer or 0) + 1
      if band(e.timer - 1, 7) == 0 then
        local t = DW().target(f)
        if t then e.dir = dirTo(e.x, e.y, t.x, t.y) end
      end
      if e.dir then move(E, e, e.dir, e.spd or 0x20) end
    end
    e.anim:update(1)
  elseif a == 3 then
    e.anim:update(1)
    if done(e) then e.action = 4; setAnim(E, e, 3); f:sound(SFX_194) end
  elseif a == 4 then
    e.anim:update(1)
    local fl = flags(e)
    if band(fl, 1) ~= 0 then
      local b = e.box23 or { x = 0, y = 0, w = 6, h = 6 }
      e.hitbox = { x = b.x, y = b.y, w = b.w + 4, h = b.h + 4 } -- gHitbox_32 (the spikes out)
    else e.hitbox = e.box23 end
    if band(fl, 2) ~= 0 then e.hitType = 0x5C end
    if done(e) then
      e.action = 2
      e.subtimer = SPINY_WAIT[band(R(f), 3)]
      e.hitbox = e.box23
      setAnim(E, e, 0)
    end
  elseif a == 5 then
    gravity(e, 0x1800)
    e.anim:update(1)
    if done(e) then e.action, e.spd = 2, 0x20; setAnim(E, e, 0) end
  elseif a == 6 then
    e.anim:update(1)
    if band(flags(e), 1) ~= 0 then
      move(E, e, e.dir, e.spd)
      if not gravity(e, 0x1800) then
        e.action, e.hitType = 7, 0x5C
        setAnim(E, e, 5)
        f:sound(SFX_PLY_LAND)
      end
    end
  elseif a == 7 then
    e.anim:update(1)
    if done(e) then e.action, e.spd, e.u81 = 2, 0x20, 0x78; setAnim(E, e, 0) end
  end
end

function C.update(E, e)
  if e.id == C.CHASER then return C.chaser(E, e) end
  return C.spiny(E, e)
end

return C
