-- Round 19: Mt. Crenel's enemies on their own decomp code.
--
-- TEKTITE ($26, enemy/tektite.c):
--   init (sub_0802F210): action 1, timer gUnk_080CDEF8[rand & 3] (24 / 40 /
--     56 / 72) + (rand & $1F); gravity unk_80 = Q_8_8(24) (type 0) /
--     Q_8_8(40); jump speed unk_82 << 4 = 2.5 / 3.0 px a frame; animation 0.
--   action 1 (sub_0802F284): animation at double speed while timer > $60;
--     timer runs out -> animation 1 with subtimer 64 when the frame ends;
--     its end -> action 2: timer 16, subtimer = type, zVelocity, the
--     direction (sub_0802F45C), animation 2.
--   action 2 (sub_0802F300): ProcessMovement0, BounceUpdate(unk_80); the
--     bounce (BOUNCE_INIT_NEXT) -> action 3 (timer 192 for type != 0 or
--     rand & $F == 0, else gUnk_080CDEF8[rand & 3] + rand), animation 3;
--     a wall: sub_0800417E (bounce off it); every 16 frames while subtimer
--     re-aims; animation 4 once it starts falling.
--   action 3 (sub_0802F3F4): animation end -> odd types jump again (twice),
--     else action 1 / animation 0.
--   sub_0802F45C: outside its home (sub_08049FA0) -> toward its middle
--     (sub_08049EE4); Link in its home (sub_08049FDC) -> at him (sub_08049F84);
--     else direction + (rand & $F) + $18.
-- FALLING_BOULDER ($21, enemy/fallingBoulder.c):
--   init (sub_0802C258): zVelocity 2.0, z -16, unk_7a = rand & $70 (+$100
--     type 1, +$200 type 2), home = its spawn point, hidden, no collision.
--   action 1: unk_7a counts down -> action 2.
--   action 2 (sub_0802C334): shown once Link is more than $38 px below the
--     room's top; BounceUpdate(unk_84): a bounce -> SFX $14C, collision on
--     for 12 frames, a new speed / direction / gravity (sub_0802C4B0, from
--     the tile under it: $1AB..$1AF faster, $1C4 middle); type2 != 0 and
--     outside its home 8 frames after a bounce -> two FX_ROCK2 and back to
--     its start; near the room's bottom edge it runs on (LinearMoveUpdate)
--     until z - y > $38, then back to its start after (rand & $7F) | $80
--     frames (type 3: stops, action 3).
-- SMALL_PESTO ($2D, enemy/smallPesto.c): z -12 / -13 flicker, flies
--   (LinearMoveUpdate) at its speed; every (rand & $F) + 16 frames a new
--   heading: outside its home on odd timers homeward, else direction + 24 +
--   (rand & $E); animation by direction ((dir + 2) & $1C) >> 2.  gustJarFlags
--   1 (swallowed by the Gust Jar: GustJar.lua handles the grab).
-- BounceUpdate (code_080043E8.s): z -= zVelocity; when z >= 0: z = 1, the
--   new zVelocity = 0.625 * -(zVelocity - g); >= $C000 -> bounce (1), else 0
--   (done).  Positions here keep the cartridge's z (negative up, 16.16); the
--   port's e.z (positive up) follows it.
-- NOT PORTED: Tektite_OnCollision's hurt-type $14 reset and $E / $15
--   instant kill (the port's hit path handles damage); FX_ROCK2 is drawn as
--   SPECIAL_FX $15; the sprite priority swaps while airborne.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Drops = require("src.zelda.tmc.Drops")

local C = {}

C.TEKTITE, C.FALLING_BOULDER, C.SMALL_PESTO = 0x26, 0x21, 0x2D
local HANDLED = { [0x26] = true, [0x21] = true, [0x2D] = true }

local function R(f) return Drops.random(Drops.rngOf(f)) end
local function dirVec(d)
  local a = (d % 32) / 32 * 2 * math.pi
  return math.sin(a), -math.cos(a)
end
local function dirTo(ax, ay, bx, by)
  local a = math.atan2(bx - ax, -(by - ay))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
local function inHome(e, x, y)
  return x - e.homeX >= 0 and x - e.homeX <= e.rangeW and y - e.homeY >= 0 and y - e.homeY <= e.rangeH
end
local function homeDir(e) return dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function syncZ(e) e.z = -(e.cz or 0) / 65536 end

-- BounceUpdate: 2 airborne, 1 bounce, 0 done
function C.bounce(e, g)
  local z = (e.cz or 0) - (e.czv or 0)
  if z < 0 then
    e.cz = z
    e.czv = (e.czv or 0) - g
    return 2
  end
  e.cz = 1
  local v = -((e.czv or 0) - g)
  v = math.floor(v / 2)
  v = v + math.floor(v / 4)
  if math.floor(v / 4096) >= 0xC then e.czv = v return 1 end
  e.czv = 0
  return 0
end

-- LinearMoveUpdate: speed (8.8) along the direction, no collision
local function linear(e, speed)
  local vx, vy = dirVec(e.dir or 0)
  local s = (speed or e.spd or 0) / 256
  e.x, e.y = e.x + vx * s, e.y + vy * s
end

function C.handles(e) return HANDLED[e.id] == true or require("src.zelda.tmc.EnemyBeetle").handles(e) or require("src.zelda.tmc.EnemyBobomb").handles(e) end -- round 21: + Spiny Beetle, Rollobite

-- ===========================================================================
-- TEKTITE
-- ===========================================================================
local TEK_T = { [0] = 0x18, 0x28, 0x38, 0x48 } -- gUnk_080CDEF8

local function tekAim(E, e)
  local f = E.field
  local tgt = require("src.zelda.tmc.EnemyDeepwood").target(f)
  if not inHome(e, e.x, e.y) then e.dir = homeDir(e)
  elseif tgt and inHome(e, tgt.x, tgt.y) then e.dir = dirTo(e.x, e.y, tgt.x, tgt.y)
  else e.dir = band(e.dir + band(R(f), 0xF) + 0x18, 0x1F) end
end

local function tekJump(E, e)
  e.action = 2
  e.timer = 16
  e.subtimer = e.form or 0
  e.czv = e.jumpV
  tekAim(E, e)
  setAnim(E, e, 2)
  e.subAction = 0
end

function C.tektite(E, e)
  local f = E.field
  local ty = e.form or 0
  if e.action == 0 then
    e.action, e.subAction = 1, 0
    e.timer = TEK_T[band(R(f), 3)] + band(R(f), 0x1F)
    e.subtimer, e.hops = 0, 0
    e.grav = ty == 0 and 0x1800 or 0x2800
    e.jumpV = ty == 0 and 0x28000 or 0x30000
    e.cz, e.czv, e.dir = 0, 0, e.dir or 0
    setAnim(E, e, 0)
  elseif e.action == 1 then
    e.anim:update(e.timer > 0x60 and 2 or 1)
    if e.timer ~= 0 then e.timer = e.timer - 1
    elseif e.subtimer ~= 0 then
      if e.anim.done then tekJump(E, e) end
    elseif e.anim.done then
      e.subtimer = 64
      setAnim(E, e, 1)
    end
  elseif e.action == 2 then
    e.anim:update(1)
    local hx, hy = require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.dir, e.speed ~= 0 and e.speed or 0x100)
    local before = e.cz
    local rnd = band(R(f), 0xF)
    if C.bounce(e, e.grav) == 1 then
      e.action, e.subAction = 3, 0
      if ty ~= 0 then rnd = 0 end
      e.timer = rnd == 0 and 192 or TEK_T[band(rnd, 3)] + rnd
      e.subtimer = 0
      setAnim(E, e, 3)
      syncZ(e)
      return
    elseif hx or hy then
      local d = e.dir
      if hx then d = 0x20 - d end
      if hy then d = 0x10 - d end
      e.dir = band(d, 0x1F)
    end
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.timer = 16
      if e.subtimer ~= 0 then e.subtimer = e.subtimer - 1; tekAim(E, e) end
    end
    if e.subAction == 0 and before < e.cz then setAnim(E, e, 4); e.subAction = 1 end
  elseif e.action == 3 then
    e.anim:update(1)
    if e.anim.done then
      if e.hops < 2 and ty % 2 ~= 0 then
        e.hops = e.hops + 1
        tekJump(E, e)
      else
        e.action, e.hops = 1, 0
        setAnim(E, e, 0)
      end
    end
  end
  syncZ(e)
end

-- ===========================================================================
-- FALLING_BOULDER
-- ===========================================================================
local FB_SPEED = { [0] = 0x80, 0x100, 0x180, 0x200, 0x80, 0x100, 0x180, 0x200, 0x100, 0x200, 0x300, 0x400 } -- gUnk_080CD568
local FB_DIR = { [0] = 10, 14, 18, 22, 10, 14, 18, 22, 10, 14, 18, 22 }                                     -- gUnk_080CD580
local FB_GRAV = { [0] = 0x1800, 0x2000, 0x2800, 0x3000, 0x1800, 0x2000, 0x2800, 0x3000, 0x1800, 0x2000, 0x2800, 0x3000 } -- gUnk_080CD58C
local SFX_14C, FX_ROCK2 = 0x14C, 0x15
local FX_STARS_C = 0x1C -- FX_STARS

local function fbPick(E, e)
  local f = E.field
  local tt = f.room:tileType(1, math.floor(e.x / 16), math.floor(e.y / 16)) or 0
  local off = 0
  if tt >= 0x1AB and tt <= 0x1AF then off = 8 elseif tt == 0x1C4 then off = 4 end
  local r = band(R(f), 7)
  if band(r, 4) ~= 0 then e.spd = FB_SPEED[off + (band(r, 3) ~= 0 and 2 or 0)]
  else e.spd = FB_SPEED[off + (band(r, 3) ~= 0 and 1 or 3)] end
  r = band(R(f), 7)
  if band(r, 4) ~= 0 then
    if e.timer ~= 0 then e.timer = 0; setAnim(E, e, 0) end
    e.dir = FB_DIR[off + (band(r, 3) ~= 0 and 1 or 0)]
  else
    if e.timer ~= 1 then e.timer = 1; setAnim(E, e, 1) end
    e.dir = FB_DIR[off + (band(r, 3) ~= 0 and 2 or 3)]
  end
  r = band(R(f), 7)
  e.czv = 0x20000
  if band(r, 4) ~= 0 then e.gravB = FB_GRAV[off + (band(r, 3) ~= 0 and 1 or 3)]
  else e.gravB = FB_GRAV[off + (band(r, 3) ~= 0 and 2 or 0)] end
end

local function fbReset(e)
  e.action = 1
  e.x, e.y = e.startX, e.startY
  e.hidden = true
  e.noTouch = true
  e.shown = false
end

function C.boulder(E, e)
  local f = E.field
  local r = f.room
  if e.action == 0 then
    e.czv, e.timer = 0x20000, 2
    e.wait = band(R(f), 0x70)
    if e.form == 1 then e.wait = e.wait + 0x100 elseif e.form == 2 then e.wait = e.wait + 0x200 end
    e.startX, e.startY = e.x, e.y
    e.cz = -0x100000
    e.layer = 3
    fbReset(e)
    fbPick(E, e)
  elseif e.action == 1 then
    e.wait = e.wait - 1
    if e.wait <= 0 then e.action, e.wait = 2, 0 end
  elseif e.action == 2 then
    if not e.shown then
      if f.player.y <= 0x38 then syncZ(e) return end
      e.shown = true
      e.hidden = false
    end
    e.anim:update(1)
    if C.bounce(e, e.gravB) == 1 then
      f:sound(SFX_14C)
      e.noTouch = nil
      e.wait = 12
      fbPick(E, e)
    else
      if e.wait ~= 0 then
        e.wait = e.wait - 1
        if e.wait == 0 then e.noTouch = true
        elseif e.wait == 8 and (e.type2 or 0) ~= 0 and not inHome(e, e.x, e.y) then
          for i = 0, 1 do f:addFx(e.x + 12 - i * 0x18, e.y, 0x0F, FX_ROCK2) end
          fbReset(e)
          e.wait = bit.bor(band(R(f), 0xFF), 0x100)
          syncZ(e)
          return
        end
      end
      local y = r.height - e.y
      linear(e, e.spd)
      if y < 5 and -(e.cz or 0) / 65536 - y > 0x38 then
        fbReset(e)
        e.wait = bit.bor(band(R(f), 0x7F), 0x80)
        if e.form == 3 then e.action = 3 end
      end
    end
  end
  syncZ(e)
end

-- ===========================================================================
-- SMALL_PESTO
-- ===========================================================================
local function spAnim(E, e)
  e.animationState = rshift(band(e.dir + 2, 0x1C), 2)
  setAnim(E, e, e.animationState)
end

function C.smallPesto(E, e)
  local f = E.field
  if e.action == 0 then
    e.action = 1
    e.dir = band(R(f), 0x18)
    e.gustJarFlags = 1
    spAnim(E, e)
    e.timer, e.subtimer = 0, 32
  elseif e.action == 1 then
    e.cz = (band(R(f), 0x30) ~= 0 and -0xC or -0xD) * 65536
    linear(e, e.speed ~= 0 and e.speed or 0x40)
    e.anim:update(1)
    e.subtimer = e.subtimer - 1
    if e.subtimer <= 0 then
      e.subtimer = band(R(f), 0xF) + 16
      if not inHome(e, e.x, e.y) and band(e.subtimer, 1) ~= 0 then e.dir = homeDir(e)
      else e.dir = band(e.dir + 0x18 + band(R(f), 0xE), 0x1F) end
      spAnim(E, e)
    end
  end
  syncZ(e)
end

-- ===========================================================================
-- PEAHAT ($03, enemy/peahat.c) -- round 20
--   Initialize: action Fly, timer 16, subtimer random, direction rand & $1F,
--     gustJarFlags 18, directionDelta +-2, flying, bobbing (z -5/-6/-7/-6 by
--     (subtimer++ & $30) >> 4), animation 0.
--   Fly: flyTimer counts down; Link in its home rect (sub_08049FDC) with
--     flyTimer 0 and (subtimer & $F) == 0 and within $30 px
--     (sub_08049F1C) -> ChargeStart (timer 60, speed 160); every 16 frames
--     the direction: outside its home (3 in 4) home-ward, else + delta (a
--     new +-2 one time in 4); ProcessMovement2 at its speed.
--   ChargeStart: 60 frames of faster animation, then ChargeTarget: timer
--     120, speed 192, direction = facing Link +-4; ChargeTarget: speed + 4
--     every other frame while timer > 60, every 4th frame one step towards
--     Link (sub_08004596); 0 or Link out of its home -> ChargeEnd: 60 frames
--     slowing by 8 every other frame, then Fly (flyTimer 120).
--   Grabbed by the Gust Jar while flying (OnGrabbed subaction 0): the
--     broken propeller (animation 1), Stunned, hitType $71, no bobbing.
--   Stunned: BounceUpdate(Q_8_8(24)) down to the ground, then
--     RepairPropeller: 240 frames (stars after 10), Takeoff (zVelocity 1.5,
--     animation 5) -> flying again (hitType $70, animation 0).
-- SIMPLIFIED: (round 21: OnCollision's branches are ported, see
--   C.peahatCollision) the sliced propeller's PeahatPropeller child is a puff;
--   sub_0800442E (holes / water under it) is not run; ProcessMovement2 is
--   ProcessMovement0 (EnemyDeepwood.move0).
local PH_HEIGHTS = { [0] = 5, 6, 7, 6 }   -- gPeahatFlightHeights (negated)

local function phFace(e, tx, ty) return dirTo(e.x, e.y, tx, ty) end
local function phEndCharge(e) e.action, e.timer = 4, 60 end
local function phTurn(e, want)  -- sub_08004596: one step towards `want`
  local d = band(want - e.dir, 0x1F)
  if d == 0 then return end
  if d < 16 then e.dir = band(e.dir + 1, 0x1F) else e.dir = band(e.dir - 1, 0x1F) end
end

-- round 21: Peahat_OnCollision (contactFlags = the other side's hurtType | $80):
--   flying and $94 (hurtType $14): the sliced propeller (animation 2, a
--     PeahatPropeller child flies off) -> Stunned with speed $80, iframes -30;
--   flying and $9B (the Gust Jar's puff, PLAYER_ITEM_GUST_BIG $1B): the
--     broken propeller (animation 1) -> Stunned, speed $80, iframes -30;
--   flying and $80 (touching Link, hurtType 0) with the flying animation:
--     back to Fly with timer 30, speed $80, NO direction ($FF: it hovers in
--     place until the next 16-frame turn), flyTimer 120 (no charge for 120
--     frames) -- the window the cartridge gives to turn the Gust Jar on it.
-- round 22: PeahatPropeller (peahat.c, type 1): CopyPosition, z 8 px
-- higher; Initialize: 240 frames, a turn every 40, speed $20, direction
-- (Random & $10) + 8 (east or west), animation 3 (PeahatAnimation_
-- Propeller), no shadow; Fly: z rises $C000 a frame, LinearMoveUpdate,
-- blinking (draw ^= 1) in its last 60 frames, then deleted.  It does not
-- collide with anything.
function C.propeller(E, e)
  local f = E.field
  if not (f.assets and f.assets.sprite and f.entities) then return nil end
  local Anim = require("src.zelda.tmc.Anim")
  local function rnd() return require("src.zelda.tmc.Drops").random(require("src.zelda.tmc.Drops").rngOf(f)) end
  local pe = { kind = 6, id = 0x100, x = e.x, y = e.y, z = (e.z or 0) + 8, sprite = e.sprite, palette = e.palette, gfx = e.gfx,
               anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0, timer = 240, subtimer = 40,
               dir = band(rnd(), 0x10) + 8, propeller = true, layer = e.layer }
  pe.anim:set(f.assets:sprite(e.sprite), 3, true)
  pe.extUpdate = function(d, me)
    me.anim:update(1)
    me.timer = me.timer - 1
    if me.timer <= 0 then me.deleted = true return end
    if me.timer < 60 then me.staticFrame = (me.timer % 2 == 0) and 0xFF or nil end
    me.z = me.z + 0.75
    me.x = me.x + ((me.dir == 8) and 1 or -1) * 0x20 / 256
    me.subtimer = me.subtimer - 1
    if me.subtimer <= 0 then me.subtimer = 40; me.dir = band(rnd(), 0x10) + 8 end
  end
  f.entities[#f.entities + 1] = pe
  if f._dungeon then f._dungeon:track(pe) end
  return pe
end

function C.peahatCollision(E, e, flags)
  if not e.flying then return end
  if flags == 0x94 then
    C.propeller(E, e) -- round 22: CreateEnemy(PEAHAT, PeahatForm_Propeller) (was a puff)
    e.flying, e.bob = false, false
    e.phAnim, e.action, e.spd, e.iframes = 2, 5, 0x80, 30
    setAnim(E, e, 2)
  elseif flags == 0x9B then
    e.phAnim, e.action, e.spd, e.iframes, e.bob = 1, 5, 0x80, 30, false
    e.flying = false
    setAnim(E, e, 1)
  elseif flags == 0x80 and e.phAnim == 0 then
    e.action, e.timer, e.spd, e.dir, e.flyTimer = 1, 30, 0x80, 0xFF, 120
    e.anim:update(1)
  end
end

function C.peahatGrabbed(E, e)
  if e.phAnim == 0 then
    e.phAnim = 1
    e.action = 5
    e.hitType = 0x71
    e.bob = false
    e.flying = false
    e.grounded = true
    setAnim(E, e, 1)
  end
end

function C.peahat(E, e)
  local f = E.field
  local tgt = require("src.zelda.tmc.EnemyDeepwood").target(f)
  local function homeHas(t) return t and inHome(e, t.x, t.y) end
  if e.action == 0 then
    e.action, e.timer = 1, 16
    e.subtimer = band(R(f), 0xFF)
    e.dir = band(R(f), 0x1F)
    e.gustJarFlags = 18
    e.delta = band(R(f), 1) ~= 0 and 2 or -2
    e.bob, e.flying, e.grounded = true, true, false
    e.flyTimer = 0
    e.phAnim = 0
    e.hitType = e.hitType or 0x70
    e.onGrabbed = C.peahatGrabbed
    e.onCollision = C.peahatCollision -- round 21
    e.spd = 0x80
    e.cz, e.czv = -5 * 65536, 0
    setAnim(E, e, 0)
  elseif e.action == 1 then
    if e.flyTimer > 0 then e.flyTimer = e.flyTimer - 1 end
    if homeHas(tgt) and e.flyTimer == 0 and band(e.subtimer, 0xF) == 0 then
      local dx, dy = tgt.x - e.x, tgt.y - e.y
      if dx * dx + dy * dy <= 0x30 * 0x30 then
        e.action, e.subAction, e.timer, e.spd = 2, band(R(f), 3), 60, 160
      end
    end
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.timer = 16
      if not inHome(e, e.x, e.y) and band(R(f), 3) ~= 0 then e.dir = homeDir(e)
      else e.dir = band(e.dir + e.delta, 0x1F) end
      if band(R(f), 3) == 0 then e.delta = band(R(f), 1) ~= 0 and 2 or -2 end
    end
    -- round 21: direction $FF (after touching Link) = no movement
    if e.dir < 0x80 then require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.dir, e.spd) end
    e.anim:update(1)
  elseif e.action == 2 then
    if homeHas(tgt) then
      e.timer = e.timer - 1
      if e.timer ~= 0 then
        e.anim:update(4 - band(rshift(e.timer, 4), 3))
      else
        e.action, e.timer, e.spd = 3, 120, 192
        e.dir = band(phFace(e, tgt.x, tgt.y) + (band(R(f), 1) == 0 and 4 or -4), 0x1F)
        e.anim:update(4)
      end
    else
      phEndCharge(e); e.anim:update(4)
    end
  elseif e.action == 3 then
    if homeHas(tgt) then
      e.timer = e.timer - 1
      if e.timer == 0 then phEndCharge(e) end
      if e.timer > 60 then
        if band(e.timer, 1) ~= 0 then e.spd = e.spd + 4 end
        if band(f.frame or 0, 3) == 0 then phTurn(e, phFace(e, tgt.x, tgt.y)) end
      end
      require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.dir, e.spd)
    else
      phEndCharge(e)
    end
    e.anim:update(4)
  elseif e.action == 4 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.timer, e.spd, e.flyTimer = 1, 1, 128, 120
      e.anim:update(1)
    else
      if band(e.timer, 1) ~= 0 then e.spd = e.spd - 8 end
      require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.dir, e.spd)
      e.anim:update(4)
    end
  elseif e.action == 5 then
    if e.phAnim == 2 then
      -- round 21: the sliced propeller: GravityUpdate(28.0) to the ground, then Recover
      local z = (e.cz or 0) - (e.czv or 0)
      if z < 0 then e.cz, e.czv = z, (e.czv or 0) - 0x1C00 else e.cz, e.czv = 0, 0 end
      if e.cz == 0 then e.action, e.timer, e.subtimer, e.hitType = 7, 150, 10, 0x71 end
    else
      -- Stunned (broken propeller): bounce down
      if C.bounce(e, 0x1800) == 0 then
        e.action, e.timer, e.subtimer, e.hitType = 6, 240, 10, 0x71
      end
      -- round 21: ProcessMovement0 along its direction (none: the knockback's)
      if e.dir >= 0x80 then e.dir = dirTo(0, 0, e.kbx or 0, e.kby or 1) end
      require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.dir, e.spd or 0x80)
      e.anim:update(1)
    end
  elseif e.action == 6 then
    if e.subtimer ~= 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then f:addFx(e.x, e.y - 12, 0x0F, FX_STARS_C) end
    end
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action = 9
      e.czv = 0x18000
      e.dir = band(R(f), 0x1F)
      e.phAnim = 5
      setAnim(E, e, 5)
    end
  elseif e.action == 7 then
    -- round 21: Recover (after the sliced propeller): 150 frames, stars after 10, then Hop
    if e.subtimer ~= 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then f:addFx(e.x, e.y - 12, 0x0F, FX_STARS_C) end
    end
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.timer, e.dir = 8, 240, band(R(f), 0x1F) end
  elseif e.action == 8 then
    -- round 21: Hop: hops about (frame flag 2 = a new direction, flag 1 = on the spot) for 240 frames, then a new propeller
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer == 0 then
      if e.anim.done then
        e.action, e.czv, e.phAnim = 9, 0x18000, 4
        setAnim(E, e, 4)
      else e.timer = 1 end
    end
    local fl = e.anim.flags or 0
    if band(fl, 2) ~= 0 then e.dir = band(R(f), 0x1F) end
    if band(fl, 1) == 0 then require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.dir, e.spd or 0x80) end
  elseif e.action == 9 then
    -- Takeoff
    e.anim:update(1)
    if e.anim.done then
      e.action, e.hitType, e.flying, e.grounded, e.bob, e.phAnim = 1, 0x70, true, false, true, 0
      e.timer, e.flyTimer = 16, 0
      setAnim(E, e, 0)
    else
      local z = (e.cz or 0) - (e.czv or 0)
      if z < 0 then e.cz, e.czv = z, (e.czv or 0) - 0x1C00 else e.cz, e.czv = 0, 0 end
      require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.dir, 0x80)
    end
  end
  if e.bob then
    e.cz = -PH_HEIGHTS[rshift(band(e.subtimer, 0x30), 4)] * 65536
    e.subtimer = band(e.subtimer + 1, 0xFF)
  end
  syncZ(e)
end

function C.update(E, e)
  if e.id == C.TEKTITE then return C.tektite(E, e) end
  if e.id == C.FALLING_BOULDER then return C.boulder(E, e) end
  if e.id == C.SMALL_PESTO then return C.smallPesto(E, e) end
  if require("src.zelda.tmc.EnemyBeetle").handles(e) then return require("src.zelda.tmc.EnemyBeetle").update(E, e) end -- round 21
  if require("src.zelda.tmc.EnemyBobomb").handles(e) then return require("src.zelda.tmc.EnemyBobomb").update(E, e) end -- round 22: bobomb.c
end

return C
