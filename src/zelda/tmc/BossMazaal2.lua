-- Round 26 (team B): Mazaal's hands -- src/enemy/mazaalBracelet.c
-- (MAZAAL_BRACELET $44) and src/enemy/mazaalHand.c (MAZAAL_HAND $38).
-- Required by BossMazaal.lua (install), not by the dispatcher.
--
-- BRACELET types 0 / 1 (the arms, gUnk_080CFC3C: 51 actions, all ported):
--   0 Init (MAZAAL_HAND child, bracelet type 2/3 = the glow, MAZAAL_OBJECT
--   1/2 = the shadow; x = head +-16, y + 32); f38 set -> 3 (collision on),
--   else the intro (1, by subAction: the glow, the hand blends in, home,
--   the clench animations 5 / 8 / 6 / 4 twice, then collision).
--   2 hover (sub_0803B5C0: animation $C..$14 by Link's direction), 3 home
--   -> 2 and the head's unk_7d bit (sub_0803B59C).
--   SLAM (4..$E): 5 the fist, rise to z -$50, chase Link's head (speed $280,
--   sub_0803B63C: turning 1 a frame, straight after 180), 10 frames, drop
--   +4 a frame (hitType $16 falling, $13 down; shake 10, SFX_158), unk_7c
--   slams, then home.  SWIPE ($F..$17): north 30 frames, the arc
--   (sub_08004596 every 4 frames) round to the other side, the grab
--   (hitType $15: CollisionMazaalShrink... sub_08017F40 captures Link ->
--   $18), past Link's x (unk_80) -> the open hand ($13), home.
--   HOLD ($18..$1A): Link carried home (sub_0803B824), lifted to -$20 and
--   slammed twice (4 damage each, sub_0803B804), then thrown south
--   (sub_0803B798).  $1B..$1D hidden while the other hand works; $1E..$27
--   both hands: rise, fall, 240 frames of shake and up to 3 BEETLEs
--   (sub_0803B724).  KNOCKED ($28..$2B): an arrow ($15, or the charged $0E;
--   sub_08018250: only one flying north gives iframes) in MazaalBracelet_
--   OnCollision -> the hand jumps (zVelocity 1.25) and falls open (hitbox
--   gUnk_080FD364 / 374, hitType $14), then hitType $18 with health $FF for
--   600 frames: under $F5 -> destroyed ($32: FX_GIANT_EXPLOSION4, a
--   GROUND_ITEM $5E, smoke every 32 frames; both destroyed -> the head's
--   action $B); else back up ($2C..$31: hitType $13 -> $17).
-- BRACELET types 2 / 3 (the glow, gUnk_080CFD20): the palette cycle
--   sub_0803BA8C (gUnk_080CFD30 / 44, $DB..$E6; knocked $E5 / $E6, destroyed
--   $E7 / $E8) shared with the hand and the head's half; the intro's
--   speeding pulse (SFX_1A9) that tells the head to rise.
-- HAND: frameIndex picks the hitbox (gUnk_080CEF34 / 58); its animations
--   are run by the bracelet (sub_0803B55C), its frame flag $10 sets the
--   glow's animation.
-- SIMPLIFIED: Link's capture / hold / throw are position overrides (state
--   "ext"); the BEETLE count is the live beetles (beetle.c's parent
--   bookkeeping is not here); bombs / arrows need M.hit (see BossMazaal).
local bit = require("bit")
local band, bor, bnot, rshift = bit.band, bit.bor, bit.bnot, bit.rshift

local B = {}
B.SEL = { [0] = 0x14, 0x13, 0x13, 0x12, 0x12, 0x11, 0x10, 0x0F, 0x0F, 0x0E, 0x0E, 0x0D, 0x0C } -- gUnk_080CFD0C
B.SMOKE_X = { [0] = 10, -10 }                                                                 -- gUnk_080CFD08
B.HOME_X = { [0] = 0x30, -0x30 }                                                              -- gUnk_080CFD0A
B.LINK_X = { [0] = 0x10, -0x10 }                                                              -- gUnk_080CFD19
B.BEETLE_X = { [0] = -0x38, 0x38 }                                                            -- gUnk_080CFD1B
B.HOLD_X = { [0] = -0x11, 0x11 }                                                              -- gUnk_080CFD1D
B.PAL2 = { [0] = 0xDB, 0xDD, 0xDF, 0xE1, 0xDF, 0xDD, 0xDB, 0xE3, 0xE5, 0xE3 }                -- gUnk_080CFD30
B.PAL3 = { [0] = 0xDC, 0xDE, 0xE0, 0xE2, 0xE0, 0xDE, 0xDC, 0xE4, 0xE6, 0xE4 }                -- gUnk_080CFD44
B.PAL_KNOCK = { [0] = 0xE5, 0xE6 }                                                            -- gUnk_080CFD58
B.PAL_GONE = { [0] = 0xE7, 0xE8 }                                                             -- gUnk_080CFD5C

local M, C

function B.install(m, c)
  M, C = m, c
  local HB = C.HB
  B.HAND0 = { [0] = HB.H394, HB.H394, HB.H394, HB.H39C, HB.H3A4, HB.H3AC, HB.H3AC, HB.H3AC, HB.H3AC } -- gUnk_080CEF34
  B.HAND1 = { [0] = HB.H3B4, HB.H3B4, HB.H3B4, HB.H3BC, HB.H3A4, HB.H3C4, HB.H3C4, HB.H3C4, HB.H3C4 } -- gUnk_080CEF58
  C.TICK.bracelet = B.tick
  C.TICK.hand = B.handTick
  C.SETUP.bracelet = function(b)
    b.u74, b.u75, b.u78, b.u7c, b.u7e, b.u80, b.u84 = nil, 0, nil, 0, 0, 0, 0
    if b.type < 2 then
      b.hitbox = b.type == 0 and { x = 11, y = 2, w = 9, h = 8 } or { x = -11, y = 2, w = 9, h = 8 }
      b.onCollision = B.onCollision
    else
      b.u74 = 0
      b.hitbox = b.type == 2 and { x = -2, y = -6, w = 4, h = 5 } or { x = 2, y = -6, w = 4, h = 5 }
    end
  end
end

local ID_HAND, ID_BRACELET, ID_OBJ = 0x38, 0x44, 0x7E

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
local function zbob(b) -- ptr[((parent.subtimer >> 4) + 3 + type * 2) & 7] + 4
  return M.BOB[band(rshift(b.parent.subtimer, 4) + 3 + b.type * 2, 7)] + 4
end
B.zbob = zbob
local function bitOf(b) return b.type == 0 and 1 or 2 end

function B.home(b) -- sub_0803B4E4
  local x, y = b.parent.x + B.HOME_X[b.type], b.parent.y + 0x10
  if C.within(b, x, y, 2) then
    b.x, b.y = math.floor(x), math.floor(y)
    return true
  end
  b.direction = C.dirTo(b.x, b.y, x, y)
  return false
end
function B.place(b) -- sub_0803B538
  if b.child then C.rel(b, b.child, 0, -1) end
  if b.u74 then C.rel(b, b.u74, 0, -2) end
end
function B.handStep(b) -- sub_0803B55C
  local hand, glow = b.child, b.u74
  C.next(hand)
  if band(C.fflags(hand), 0x10) ~= 0 then
    if glow.animIndex ~= 1 then C.anim(glow, 1) end
  elseif glow.animIndex ~= 0 then C.anim(glow, 0) end
end
function B.back(b) -- sub_0803B59C
  b.action = 2
  b.parent.u7d = bor(b.parent.u7d, bitOf(b))
end
function B.pose(f, b) -- sub_0803B5C0
  local d = C.facing(b, f.player)
  if d < 10 then d = 10 end
  if d > 0x16 then d = 0x16 end
  local t = b.type == 0 and B.SEL[d - 10] or B.SEL[0x16 - d]
  if C.fflags(b) ~= t then C.anim(b, t) end
end
function B.overLink(f, b) -- sub_0803B610
  local p = f.player
  return C.within(b, p.x + B.LINK_X[b.type], p.y - 0xC, 8)
end
function B.chase(f, b) -- sub_0803B63C
  local p = f.player
  local x, y = p.x + B.LINK_X[b.type], p.y - 0xC
  local t = b.timer
  b.timer = band(t + 1, 0xFF)
  if t > 180 then b.direction = C.dirTo(b.x, b.y, x, y)
  else C.turn(b, C.dirTo(b.x, b.y, x, y)) end
end
function B.regrow(b) -- sub_0803B6A4
  b.action = 0x2C
  b.hitType = 0x14
  local h = b.parent
  h.u80 = bor(h.u80, b.type == 0 and 0x10 or 0x20)
  h.u80 = band(h.u80, b.type == 0 and bnot(4) or bnot(8))
  C.anim(b, 0x17)
end
function B.passed(b) -- sub_0803B6F4
  if b.type == 0 then return b.u80 > b.x end
  return b.u80 < b.x
end
function B.beetle(f, b) -- sub_0803B724
  local alive = 0
  for _, e in ipairs(f.entities) do if e.mzBeetleOf == b and not e.deleted and not e.dying then alive = alive + 1 end end
  b.subtimer = alive
  if b.subtimer < 3 and b.u84 ~= 0 then
    local r = C.rand(f)
    local x = band(r, 0x70) + B.BEETLE_X[b.type]
    local y = band(rshift(r, 16), 7) * 10 + 0x5C
    local e = f.spawn and f:spawn({ kind = 3, id = 0x07, paramA = 1, paramB = 1, paramC = 0, x = x, y = y, pool = 0, collision = 0 })
    if e then
      e.type2 = 1
      e.mzBeetleOf = b
      b.subtimer = b.subtimer + 1
      b.u84 = b.u84 - 1
    end
  end
end
function B.throw(f) -- sub_0803B798: Link jumps off south
  local p = f.player
  p.mazaalHeld = nil
  p.z = 10
  local zv = 1.5
  p.animationState = 4
  p.invuln = 0
  p.mazaalNoHit = 30 -- iframes -$1E
  p.state = "ext"
  p.extUpdate = function(pl)
    pl.y = pl.y + 0x140 / 256
    pl.z = pl.z + zv
    zv = zv - 32 / 256
    if pl.z <= 0 then
      pl.z = 0
      pl.state, pl.extUpdate = "normal", nil
      pl.animId = -1
    end
  end
end
function B.squeeze(f) -- sub_0803B804
  f.player.invuln = 30
  C.modHealth(f, 4)
end
function B.hold(f, b) -- sub_0803B824
  local p = f.player
  if p.state == "dead" then return end
  p.mazaalHeld = b
  p.state = "ext"
  p.extUpdate = p.extUpdate or function() end
  p.x, p.y = b.x + B.HOLD_X[b.type], b.y + 1
  p.z = 0
  p.spriteOY, p.spriteOYFrame = -6 + (b.spriteOY or 0) + math.floor(b.cz or 0), f.frame
end
function B.grabbed(f, b) -- sub_0803B870
  local hand = b.child
  local p = f.player
  if hand.contactNow and p.mazaalHeld == hand then
    hand.contactNow = nil
    b.action, b.timer = 0x18, 68
    b.drawOn = false
    p.invuln = 0
    B.hold(f, b)
    hand.hitType = 0x13
    C.anim(hand, 7)
    f:sound(C.SFX.S16E)
    return true
  end
  hand.contactNow = nil
  hand.hitType = 0x15
  return false
end
function B.hits(b, v) b.child.hitType = v; b.u74.hitType = v end -- sub_0803B8E8

-- MazaalBracelet_OnCollision (types 0 / 1)
function B.onCollision(f, E, b, cf)
  if b.type >= 2 then return end
  if b.action ~= 0x2B then
    if b.iframes > 0 and (cf == 0x95 or cf == 0x8E) then
      b.action = 0x28
      b.collide = false
      local h = b.parent
      h.u7d = bor(h.u7d, bitOf(b))
      h.u80 = bor(h.u80, bitOf(b))
      b.child.iframes = b.iframes
      b.u74.iframes = b.iframes
      f:sound(C.SFX.BOSS_HIT)
    end
  else
    b.child.iframes = b.iframes
    b.u74.iframes = b.iframes
    C.anim(b, 0x18)
    C.anim(b.child, 9)
    f:sound(C.SFX.BOSS_HIT)
  end
end

-- ---------------------------------------------------------------------------
-- types 0 / 1 by action (gUnk_080CFC3C)
-- ---------------------------------------------------------------------------
local A = {}
B.A = A
A[0x00] = function(f, b) -- sub_0803A274
  local T = C.state(f)
  local h = C.new(f, 3, ID_HAND, b.type, b.x, b.y, "hand")
  h.parent = b
  b.child = h
  local g = C.new(f, 3, ID_BRACELET, b.type + 2, b.x, b.y, "bracelet")
  g.parent = b
  b.u74 = g
  local sh = C.new(f, 6, ID_OBJ, b.type + 1, b.x, b.y, "mobj")
  sh.parent = b
  sh.child = h
  if b.type == 0 then C.rel(b.parent, b, 16, 32)
  else b.flipX = true; C.rel(b.parent, b, -16, 32) end
  if T.f38 ~= 0 then
    b.action = 3
    b.collide = true
    b.drawOn = true
    h.drawOn = true
    C.anim(b, 0x10)
  else
    b.action = 1
    C.anim(b, 4)
  end
end
A[0x01] = function(f, b) -- sub_0803A364: the intro
  b.cz = zbob(b)
  local s = band(b.subAction, 0x7F)
  if s == 0 or s == 2 then return
  elseif s == 1 then
    b.subAction = 2
    b.child.drawOn = true
    b.child.alphaBlend = true
  elseif s == 3 then
    b.subAction = 4
    b.drawOn = true
    b.child.alphaBlend = nil
  elseif s == 4 then
    C.next(b)
    if C.done(b) then b.subAction = 5 end
  elseif s == 5 then
    if not B.home(b) then C.move(b) return end
    b.type2 = 0
    b.subAction, b.timer = 6, 30
  elseif s == 6 then
    b.timer = b.timer - 1
    if b.timer == 0 then b.subAction = 7; C.anim(b, 5) end
  elseif s == 7 then
    C.next(b)
    if C.done(b) then
      b.subAction = 8
      b.drawOn = false
      C.anim(b.child, 8)
      f:sound(C.SFX.S16E)
    end
  elseif s == 8 then
    B.handStep(b)
    if not C.done(b.child) then return end
    b.subAction, b.timer = 9, 30
  elseif s == 9 then
    b.timer = b.timer - 1
    if b.timer == 0 then b.subAction = 10; C.anim(b.child, 6) end
  elseif s == 10 then
    B.handStep(b)
    if C.done(b.child) then b.subAction = 0xB; b.drawOn = true; C.anim(b, 4) end
  elseif s == 0xB then
    C.next(b)
    if not C.done(b) then return end
    if b.type2 ~= 0 then b.subAction, b.timer = 0xC, 30
    else b.type2 = 1; b.subAction, b.timer = 6, 10 end
  else
    b.timer = b.timer - 1
    if b.timer == 0 then
      b.collide = true
      b.action = 3; C.anim(b, 0x10) -- sub_0803B4D4
    end
  end
end
A[0x02] = function(f, b) -- sub_0803A548
  B.pose(f, b)
  C.next(b)
  b.cz = zbob(b)
  if not B.home(b) then C.move(b) end
end
A[0x03] = function(f, b) -- sub_0803A58C
  b.cz = zbob(b)
  if B.home(b) then B.back(b) else C.move(b) end
end
A[0x04] = function(f, b) -- sub_0803A5D0
  b.action = 5
  b.collide = false
  b.cz = zbob(b)
  C.anim(b, 5)
end
A[0x05] = function(f, b) -- sub_0803A60C
  b.cz = zbob(b)
  C.next(b)
  if C.done(b) then b.action = 6; b.drawOn = false; C.anim(b.child, 8) end
end
A[0x06] = function(f, b) -- sub_0803A660
  local hand = b.child
  if C.done(hand) then
    if b.cz > -0x50 then b.cz = b.cz - 2
    else
      b.action, b.timer = 7, 0
      b.direction = C.facing(b, f.player)
      b.speed = 0x280
    end
  else
    B.handStep(b)
    if C.done(hand) then f:sound(C.SFX.S157) end
    b.cz = zbob(b)
  end
end
A[0x07] = function(f, b) -- sub_0803A6E8
  if B.overLink(f, b) then b.action, b.timer = 8, 10
  else
    B.chase(f, b)
    C.move(b)
    local y = b.parent.y + 8
    if y > b.y then b.y = y end
  end
end
A[0x08] = function(f, b) -- sub_0803A720
  b.timer = b.timer - 1
  if b.timer == 0 then b.action = 9; B.hits(b, 0x16) end
end
A[0x09] = function(f, b) -- sub_0803A740
  b.cz = b.cz + 4
  if b.cz >= 0 then
    b.cz = 0
    b.action, b.timer = 10, 10
    b.parent.u7d = bor(b.parent.u7d, 0x40)
    B.hits(b, 0x13)
    C.shake(f, 10, 0)
    f:sound(C.SFX.S158)
  end
end
A[0x0A] = function(f, b) -- sub_0803A780
  b.timer = b.timer - 1
  if b.timer == 0 then
    b.u7c = band(b.u7c - 1, 0xFF)
    if b.u7c ~= 0 then b.action = 6 else b.action = 0xB end
  end
end
A[0x0B] = function(f, b) -- sub_0803A7AC
  if b.cz > -6 then b.cz = b.cz - 1 else b.action = 0xC end
end
A[0x0C] = function(f, b) -- sub_0803A7CC
  b.cz = zbob(b)
  if B.home(b) then b.action = 0xD; C.anim(b.child, 6) else C.move(b) end
end
A[0x0D] = function(f, b) -- sub_0803A814
  b.cz = zbob(b)
  B.handStep(b)
  if C.done(b.child) then b.action = 0xE; b.drawOn = true; C.anim(b, 4) end
end
A[0x0E] = function(f, b) -- sub_0803A86C
  b.cz = zbob(b)
  C.next(b)
  if C.done(b) then b.collide = true; B.back(b) end
end
A[0x0F] = function(f, b) -- sub_0803A8B8: the swipe
  b.action, b.timer = 0x10, 30
  b.direction, b.speed = 0, 0x80
  b.cz = zbob(b)
  C.anim(b, 6)
  C.anim(b.child, 1)
  f:sound(C.SFX.S153)
end
A[0x10] = function(f, b) -- sub_0803A90C
  b.cz = zbob(b)
  C.next(b)
  B.handStep(b)
  C.move(b)
  b.timer = b.timer - 1
  if b.timer == 0 then
    b.action = 0x11
    b.direction = b.type * 0x10 + 8
    b.speed = 0x200
    C.anim(b, 7)
    C.anim(b.child, 2)
  end
end
A[0x11] = function(f, b) -- sub_0803A978
  b.cz = zbob(b)
  C.next(b)
  B.handStep(b)
  b.timer = band(b.timer + 1, 0xFF)
  if band(b.timer, 3) == 0 then C.turn(b, 0x10) end
  C.move(b)
  if b.direction == 0x10 then
    b.action, b.timer = 0x12, 3
    b.collide = false
    b.u74.collide = false
    C.anim(b, 8)
    C.anim(b.child, 3)
  end
end
A[0x12] = function(f, b) -- sub_0803AA00
  b.cz = zbob(b)
  if B.grabbed(f, b) then return end
  local dir = bit.bxor(b.type, 1) * 0x10 + 8
  b.timer = band(b.timer + 1, 0xFF)
  if band(b.timer, 3) == 0 then C.turn(b, dir) end
  C.move(b)
  if b.direction == dir or b.y >= f.player.y then
    b.action = 0x13
    b.drawOn = false
    b.direction = dir
    b.u80 = math.floor(f.player.x)
    C.anim(b.child, 4)
  end
end
A[0x13] = function(f, b) -- sub_0803AA98
  b.cz = zbob(b)
  if B.grabbed(f, b) then return end
  C.move(b)
  if B.passed(b) then
    b.action = 0x14
    b.speed = 0x40
    C.anim(b, 10)
    b.u74.collide = true
    b.child.hitType = 0x13
    C.anim(b.child, 5)
    f:sound(C.SFX.S16E)
  end
end
A[0x14] = function(f, b) -- sub_0803AB10
  b.cz = zbob(b)
  C.move(b)
  B.handStep(b)
  if C.done(b.child) then b.action, b.timer = 0x15, 15 end
end
A[0x15] = function(f, b) -- sub_0803AB5C
  b.cz = zbob(b)
  b.timer = b.timer - 1
  if b.timer == 0 then
    b.action = 0x16
    b.drawOn = true
    C.anim(b, 0xB)
    C.anim(b.child, 6)
  end
end
A[0x16] = function(f, b) -- sub_0803ABB4
  b.cz = zbob(b)
  C.next(b)
  B.handStep(b)
  if C.done(b.child) then
    b.action = 0x17
    b.collide = true
    b.speed = 0x180
    C.anim(b, 0x10)
    C.anim(b.child, 0)
  end
end
A[0x17] = function(f, b) -- sub_0803AC1C
  b.cz = zbob(b)
  if B.home(b) then B.back(b) else C.move(b) end
end
A[0x18] = function(f, b) -- sub_0803AC60: Link carried home
  b.cz = zbob(b)
  C.next(b)
  if b.timer == 0 then
    if B.home(b) then b.action, b.subAction, b.timer = 0x19, 0, 30
    else C.move(b) end
  else
    b.timer = b.timer - 1
  end
  B.hold(f, b)
end
A[0x19] = function(f, b) -- sub_0803ACC0: lifted, slammed twice
  local s = b.subAction
  if s == 1 then
    b.cz = b.cz - 1
    if b.cz < -0x20 then b.subAction = 2 end
  elseif s == 2 then
    b.cz = b.cz + 4
    if b.cz >= 0 then
      b.cz, b.timer, b.subAction = 0, 12, 3
      C.shake(f, 8, 0)
      f:sound(C.SFX.S158)
      B.squeeze(f)
    end
  elseif s == 3 then
    b.timer = b.timer - 1
    if b.timer == 0 then b.subAction = 4 end
  elseif s == 4 then
    b.cz = b.cz - 2
    if b.cz < -0x28 then b.subAction = 5 end
  elseif s == 5 then
    b.cz = b.cz + 4
    if b.cz >= 0 then
      b.cz = 0
      b.action, b.timer = 0x1A, 60
      C.shake(f, 30, 0)
      f:sound(C.SFX.S158)
      B.squeeze(f)
      return
    end
  else
    b.timer = b.timer - 1
    if b.timer == 0 then b.subAction = 1 end
  end
  B.hold(f, b)
end
A[0x1A] = function(f, b) -- sub_0803ADAC
  b.timer = b.timer - 1
  if b.timer == 0 then
    b.action = 0x16
    b.drawOn = true
    b.u74.collide = true
    C.anim(b, 0xB)
    C.anim(b.child, 6)
    B.throw(f)
  else
    B.hold(f, b)
  end
end
A[0x1B] = function(f, b) -- sub_0803ADF4
  b.cz = zbob(b)
  C.next(b) -- UpdateAnimationSingleFrame + GetNextFrame
  C.next(b)
  if C.done(b) then b.action, b.timer = 0x1C, 30; b.drawOn = false end
end
A[0x1C] = function(f, b) -- sub_0803AE48
  b.cz = zbob(b)
  C.next(b)
  local ready = b.timer == 0
  if not ready then b.timer = b.timer - 1; ready = b.timer == 0 end
  if ready and band(b.parent.u7d, 3) ~= 0 then
    b.action = 0x1D
    b.drawOn = true
    C.anim(b, 4)
  elseif not B.home(b) then
    C.move(b)
  end
end
A[0x1D] = function(f, b) -- sub_0803AEC4
  b.cz = zbob(b)
  C.next(b)
  C.next(b)
  if C.done(b) then b.collide = true; B.back(b) end
end
A[0x1E] = function(f, b) -- sub_0803AF18: both hands
  b.action = 0x1F
  b.collide = false
  C.anim(b, 5)
  b.cz = M.BOB[band(rshift(b.parent.subtimer, 4), 7)] + 4
end
A[0x1F] = function(f, b) -- sub_0803AF50
  C.next(b)
  if C.done(b) then b.action = 0x20; b.drawOn = false; C.anim(b.child, 8) end
end
A[0x20] = function(f, b) -- sub_0803AF7C
  B.handStep(b)
  if C.done(b.child) then b.action, b.timer = 0x21, 15 end
end
A[0x21] = function(f, b) -- sub_0803AF9C
  if b.timer ~= 0 then b.timer = b.timer - 1
  elseif -0x20 < b.cz then b.cz = b.cz - 2
  else b.action, b.timer = 0x22, 10 end
end
A[0x22] = function(f, b) -- sub_0803AFC8
  b.timer = b.timer - 1
  if b.timer == 0 then b.action = 0x23 end
end
A[0x23] = function(f, b) -- sub_0803AFE0
  if b.cz < 0 then b.cz = b.cz + 4
  else
    b.action, b.timer = 0x24, 240
    b.u84 = 3
    b.cz = 0
    C.shake(f, 160, 0)
    f:sound(C.SFX.S158)
  end
end
A[0x24] = function(f, b) -- sub_0803B01C
  b.timer = b.timer - 1
  if b.timer == 0 then b.action = 0x25
  elseif b.timer > 70 and band(b.timer, 0xF) == 0 then B.beetle(f, b) end
end
A[0x25] = function(f, b) -- sub_0803B04C
  if b.cz > -6 then b.cz = b.cz - 1 else b.action = 0x26; C.anim(b.child, 6) end
end
A[0x26] = function(f, b) -- sub_0803B074
  b.cz = zbob(b)
  B.handStep(b)
  if C.done(b.child) then
    b.action = 0x27
    b.drawOn = true
    C.anim(b, 4)
    C.anim(b.child, 0)
  end
end
A[0x27] = function(f, b) -- sub_0803B0D4
  C.next(b)
  C.next(b)
  if C.done(b) then b.collide = true; B.back(b) end
end
A[0x28] = function(f, b) -- sub_0803B100: knocked by an arrow
  b.action = 0x29
  b.zv = 1.25
  b.hitbox = b.type == 0 and { x = 12, y = 6, w = 9, h = 8 } or { x = -12, y = 6, w = 9, h = 8 }
  local g = b.u74
  g.action = 3
  g.u74 = 0x20
  C.anim(b.child, 9)
  f:sound(C.SFX.S14F)
end
A[0x29] = function(f, b) -- sub_0803B144
  C.next(b.child)
  if C.gravity(b, 32 / 256) == 0 then
    b.action = 0x2A
    C.anim(b, 0x16)
    B.hits(b, 0x14)
    C.shake(f, 8, 0)
  end
end
A[0x2A] = function(f, b) -- sub_0803B17C
  C.next(b)
  if C.done(b) then
    b.action = 0x2B
    b.collide = true
    b.hitType = 0x18
    b.health = 0xFF
    b.u7e = 600
  end
end
A[0x2B] = function(f, b) -- sub_0803B1B8: open to the sword
  if not C.done(b) then C.next(b); C.next(b.child) end
  if b.health < 0xF5 then
    b.action = 0x32
    b.u7e = 0x5DC
    b.drawOn = false
    b.hitType = 0x14
    C.fx(f, b.x + b.hitbox.x, b.y + b.hitbox.y, C.FX.GIANT4)
    local objs = f.objects and f:objects()
    if objs and objs.groundItem then pcall(objs.groundItem, objs, 0x5E, 0, b.x + b.hitbox.x, b.y + b.hitbox.y, {}) end
    b.u74.u74 = 0x40
    local h = b.parent
    h.u80 = bor(h.u80, b.type == 0 and 4 or 8)
    if band(h.u80, 0xC) == 0xC then
      h.action, h.timer, h.zv = 0xB, 120, 0
      h.u74.u7e = 0x708
      h.u78.u7e = 0x708
    end
  else
    b.u7e = b.u7e - 1
    if b.u7e == 0 then B.regrow(b) end
  end
end
A[0x2C] = function(f, b) -- sub_0803B2D0
  C.next(b)
  if C.done(b) then
    b.action = 0x2D
    b.drawOn = false
    local g = b.u74
    g.action = 2
    g.u74, g.u78 = 0, 0
    C.anim(g, 3)
  end
end
A[0x2D] = function(f, b) -- sub_0803B30C
  local g = b.u74
  if C.done(g) then
    b.action = 0x2E
    B.hits(b, 0x13)
    C.anim(g, 0)
  end
end
A[0x2E] = function(f, b) -- sub_0803B338
  if b.cz > -10 then b.cz = b.cz - 1 else b.action, b.timer = 0x2F, 15 end
end
A[0x2F] = function(f, b) -- sub_0803B35C
  b.cz = zbob(b)
  b.timer = b.timer - 1
  if b.timer == 0 then b.action = 0x30 end
end
A[0x30] = function(f, b) -- sub_0803B398
  b.cz = zbob(b)
  if B.home(b) then
    b.action = 0x31
    b.drawOn = true
    C.anim(b, 4)
    C.anim(b.child, 0)
  else
    C.move(b)
  end
end
A[0x31] = function(f, b) -- sub_0803B3F4
  b.cz = zbob(b)
  C.next(b)
  if C.done(b) then
    b.hitType = 0x17
    b.hitbox = b.type == 0 and { x = 11, y = 2, w = 9, h = 8 } or { x = -11, y = 2, w = 9, h = 8 }
    local h = b.parent
    h.u80 = band(h.u80, bnot(bor(b.type == 0 and 0x10 or 0x20, bitOf(b))))
    B.back(b)
  end
end
A[0x32] = function(f, b) -- sub_0803B480: destroyed, smoking
  if band(b.u7e, 0x1F) == 0 and f.spawn then
    pcall(f.spawn, f, { kind = 6, id = 0x2D, paramA = 1, paramB = 0, paramC = 0, x = b.x + B.SMOKE_X[b.type], y = b.y, pool = 0x0F, collision = 0 })
  end
  b.u7e = b.u7e - 1
  if b.u7e == 0 then B.regrow(b) end
end

-- ---------------------------------------------------------------------------
-- types 2 / 3: the glow (gUnk_080CFD20)
-- ---------------------------------------------------------------------------
function B.palette(f, g, unk) -- sub_0803BA8C
  local pal = 0
  local tmp = band(g.u74, 0xE0)
  if tmp == 0 then
    if g.u74 == 0 then
      g.u75 = g.u75 + 1
      if 9 < g.u75 then g.u75 = 0 end
      pal = g.type == 2 and B.PAL2[g.u75] or B.PAL3[g.u75]
    end
    g.u74 = g.u74 + 1
    if unk <= g.u74 then g.u74 = 0 end
  elseif band(tmp, 0x80) == 0 then
    g.u74 = bor(g.u74, 0x80)
    if band(tmp, 0x20) ~= 0 then pal = B.PAL_KNOCK[g.type - 2] else pal = B.PAL_GONE[g.type - 2] end
  end
  if pal ~= 0 then
    C.setPal(g, pal)
    local br = g.parent
    if br.u78 then C.setPal(br.u78, pal) end
    if br.child then C.setPal(br.child, pal) end
  end
  return pal
end
local GA = {}
B.GA = GA
GA[0] = function(f, g) -- sub_0803B910
  local T = C.state(f)
  if T.f38 ~= 0 then
    g.action = 2
    g.drawOn = true
    g.u74 = 0
    B.palette(f, g, 10)
  else
    g.action = 1
    g.u74 = 0x80
  end
  g.flipX = g.type == 3
  C.anim(g, 0)
  C.copyPosOff(g.parent, g)
end
GA[1] = function(f, g) -- sub_0803B978: the intro's pulse
  local s = g.subAction
  if s == 0 then return end
  if s == 1 then
    g.subAction, g.timer, g.subtimer = 2, 2, 30
    g.u74 = 0
    f:sound(C.SFX.S1A9)
    s = 2
  end
  if s == 2 then
    B.palette(f, g, g.subtimer)
    if bor(g.u75, g.u74) == 0 then f:sound(C.SFX.S1A9) end
    if g.u74 ~= 0 then return end
    g.timer = g.timer - 1
    if g.timer ~= 0 then return end
    g.timer = 2
    g.subtimer = g.subtimer - 4
    if g.subtimer ~= 10 then return end
    g.parent.parent.subAction = 3
    g.subAction = 3
    return
  end
  if s == 4 then
    g.subAction = 5
    g.drawOn = true
    g.alphaBlend = true
  elseif s ~= 3 then
    if s ~= 5 then g.action = 2; g.alphaBlend = nil end
    C.next(g)
  end
  B.palette(f, g, 0x10)
  if bor(g.u75, g.u74) == 0 then f:sound(C.SFX.S1A9) end
end
GA[2] = function(f, g) B.palette(f, g, 10); C.next(g) end -- sub_0803BA6C
GA[3] = function(f, g) B.palette(f, g, 10) end            -- sub_0803BA80

-- ---------------------------------------------------------------------------
-- the frame
-- ---------------------------------------------------------------------------
function B.tick(f, E, b)
  if C.gone(b.parent) then C.delete(b) return end
  if b.type >= 2 then
    local fn = GA[b.action]
    if fn then fn(f, b) end
    return
  end
  local fn = A[b.action]
  if fn then fn(f, b) end
  if b.deleted then return end
  B.place(b)
  -- the collision pass for the arm, the hand and the glow
  C.touch(f, b) -- $17 / $18 / $14: Link pushed out
  local hand, g = b.child, b.u74
  if hand and not hand.deleted then B.handHitbox(hand); B.handTouch(f, b, hand) end
  if g and not g.deleted then B.handTouch(f, b, g) end
  if f.player.mazaalNoHit then
    f.player.mazaalNoHit = f.player.mazaalNoHit - 1
    if f.player.mazaalNoHit <= 0 then f.player.mazaalNoHit = nil end
  end
end

function B.handHitbox(h) -- sub_08035194
  local fi = C.frameIndex(h)
  local t = h.type == 0 and B.HAND0 or B.HAND1
  local hb = fi and t[fi]
  if hb then h.hitbox = { x = hb.x, y = hb.y, w = hb.w, h = hb.h } end
end

function B.handTouch(f, b, part)
  if f.player.mazaalNoHit then return end
  local r = C.touch(f, part)
  if r == 7 then -- sub_08017F40: captured (Link full size, free to move)
    local p = f.player
    if not p.minish and (p.state == "normal" or p.state == "sword" or p.state == "shield" or p.state == "hurt") then
      p.mazaalHeld = part
      p.state = "ext"
      p.extUpdate = function() end
      p.x, p.y = part.x, part.y + 1
      part.contactNow = true
      part.iframes = -8
    end
  end
end

function B.handTick(f, E, h) -- MazaalHand
  if C.gone(h.parent) then C.delete(h) return end
  if h.action == 0 then
    h.action = 1
    h.flipX = h.type == 1
    C.anim(h, 0)
  end
  B.handHitbox(h)
end

return B
