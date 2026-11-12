-- Round 26 (team B): VAATI_ARM ($52), src/enemy/vaatiArm.c, for Vaati's
-- Wrath (BossVaati3.lua owns the fight; this is one arm's code).
--
-- PARTS.  Five entities per arm (VaatiArm_HeapStruct): ents[0] the hand
--   (type 0, the arm's own code, animations by gUnk_080D1286 / 13B7 / ...),
--   ents[1..3] the forearm segments, ents[4] the shoulder / the core.  The
--   heap's s1[0..4] hold per joint a yaw word u00 (its high byte a 256-step
--   heading, 0 north), a pitch word u04 (high byte: 0 straight up, $40
--   level, $80 down), the speeds u08 / u0a, the length u0c and two timers.
--   sub_0804393C lays entity t at entity t+1 (ents[4]: at Vaati) plus
--   (sin yaw * sin pitch, -cos yaw * sin pitch) * len, z - cos pitch * len,
--   the hand's wobble (gUnk_080D1362, after a Cane hit) added to len;
--   sub_08043B08 keeps each joint within gUnk_080D13B2 of the one before.
--   sub_08043A10 lays out the whole chain from Vaati (actions 1-4, 6),
--   sub_08043A78 only 2..0 (action 5: the hand comes out of the floor at
--   ents[3]), sub_08043ABC 3..0 from ents[4] (action 7: the core).
-- ACTIONS (gUnk_080D125C):
--   0 init (sub_080425B4): the heap, the parts; back from an arm (field_0x38
--     bit 0) the arm Link was in lies open (sub_08043EB8: action 7/4 while
--     its macro lives, else 8), the other one waits (action 2).
--   1 the arm grows out (sub_08042654: the joints 2 px a frame to $C / $E /
--     $10 / $1C, SFX_15E each), 90 frames, collision on.
--   2 sways (sub_08042818: yaw by u08, $78 frames a way; pitch by u0a, $50).
--   3 the sweep (gUnk_080D1290): swings back to gUnk_080D12B0, 30 frames,
--     then round at -3x speed (hitType $3B, SFX_153) past $7C to
--     gUnk_080D12B2, 60 frames, back at -speed/6 to gUnk_080D12B6.
--   4 the slam (gUnk_080D12B8): turns to gUnk_080D12C8, lowers, 30 frames,
--     hitType $3D, animation $E, then dives into the floor (segments hidden
--     at z >= -10, SFX_161, VAATI3_ARM 0 (the hole) and 2 (a puff)) and the
--     shoulder sinks; -> 5.
--   5 under the floor (gUnk_080D12D0): comes up at Link (gUnk_080D12F8,
--     kept inside the room and off Vaati's spot), VAATI3_ARM 1, rises (z -2
--     a frame to -5, puffs and SFX_166 as each part shows), sways; 3 times:
--     slides (speed of ents[3]) toward the room's middle +-gUnk_080D1304
--     (away from Vaati), then a punch (animation $F, SFX_19B,
--     V3_HAND_PROJECTILE on frame flag 1) or, Link within $50, a spin
--     (pitch to $50, hitType $3B, 40 frames) ; then sinks (z +3) and comes
--     back up at Vaati (action 6).  A Cane bolt on ents[2] / [3] (contact
--     $1D) here flips the hand (sub_08043D08: action 7, the core on the
--     hand, FX_GIANT_EXPLOSION4, field_0x38 bit 1).
--   6 rises at Vaati's side (gUnk_080D1314) and reports to him (his
--     subAction 2) -> 2.
--   7 open (gUnk_080D1320): the joints fold up, animation $10; the core
--     rises (z -2 a frame, hitType $3A, gUnk_080FD450), hops (zVelocity 1.5,
--     gravity 26/256) to z -6; 900 frames in which Minish Link on the hand
--     (CheckPlayerInRegion(ents[3], 3, 3)) goes in (sub_08043DB0:
--     DoExitTransition to VAATIS_ARMS room 0 -- room 1 once an arm is gone --
--     field_0x3c / 3d / 40-4a); then the core sinks, 60 frames, action 6.
--   8 dying (gUnk_080D1348): 60 frames, the segments explode one by one
--     (20 frames apart, FX_GIANT_EXPLOSION4), then Vaati's heap forgets the
--     arm, field_0x39 loses its bit, the shoulder dies (health 0 ->
--     GenericDeath) and the hole object closes.
--   A Cane bolt anywhere on the arm (sub_08043CD4) wobbles it for $78 frames.
-- SIMPLIFIED: EnemyDetachFX (the burning / frozen FX) is a no-op; ProcessMovement0
--   for ents[3] stops at solid tiles only.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local A = {}

local T1280 = { [0] = 0x140, -0x140 }                                   -- gUnk_080D1280
local T1284 = { [0] = 0x40, 0xC0 }                                      -- gUnk_080D1284 (s8 -$40)
local T1286 = { [0] = 2, 3, 5, 6, 0xc, 0xb, 9, 8, 0, 0 }                -- gUnk_080D1286
local T12AC = { [0] = -0x200, 0x200 }                                   -- gUnk_080D12AC
local T12B0 = { [0] = 8, 0xF8 }                                         -- gUnk_080D12B0 (u8 -8)
local T12B2 = { [0] = 0xB0, 0x50 }                                      -- gUnk_080D12B2 (u8 -$50)
local T12B4 = { [0] = -0x20, 0x20 }                                     -- gUnk_080D12B4
local T12B6 = { [0] = 0x70, 0x90 }                                      -- gUnk_080D12B6 (u8 -$70)
local T12C8 = { [0] = 0x60, 0xA0 }                                      -- gUnk_080D12C8 (u8 -$60)
local T12CA = { [0] = 0x280, 0xFD80 }                                   -- gUnk_080D12CA (u16 -$280)
local T12F8 = { [0] = -0x10, 0, 0, -0x10, 0x10, 0, 0, 0x10 }            -- gUnk_080D12F8
local T1300 = { [0] = 0xC0, -0xC0 }                                     -- gUnk_080D1300
local T1304 = { [0] = 0, -1, -2, -3, 0, 1, 2, 3 }                       -- gUnk_080D1304
local T130C = { [0] = 0x5000, 0xB000 }                                  -- gUnk_080D130C (s16 -$5000)
local T1310 = { [0] = 0xA0, -0xA0 }                                     -- gUnk_080D1310
local T131C = { [0] = 0x70, 0x90 }                                      -- gUnk_080D131C (u8 -$70)
local T1338 = { [0] = 0x4000, 0xC000 }                                  -- gUnk_080D1338 (s16 -$4000)
local T133C = { [0] = 0xA0, -0xA0 }                                     -- gUnk_080D133C
local T1340 = { [0] = 0, 0x12, 0x12, 0x11, 0x11, 0, 0, 0 }              -- gUnk_080D1340
local T135C = { [0] = 0x4000, 0xC000, 0x8000 }                          -- gUnk_080D135C
local T1362 = { [0] =
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2,
  3, 4, 4, 4, 4, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 4, 4, 4, 4, 4, 4, 0, 0, 0, 1, 2, 3,
  4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 1, 2, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4 }    -- gUnk_080D1362
local T13B2 = { [0] = 0, 12, 9, 6, 3 }                                  -- gUnk_080D13B2
local T13B7 = { [0] = 1, 1, 2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 6, 6, 6, 7, 7, 7, 8, 8, 8, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12, 1, 0 } -- gUnk_080D13B7
local T13D8 = { [0] = { -0x60, 0x80 }, { 0x60, -0x80 } }                -- gUnk_080D13D8
local T13E0 = { [0] = 0xc, 0xe, 0x10, 8, 9, 10, 4, 4, 5 }               -- gUnk_080D13E0 / gUnk_080D13E3 (contiguous)
local T13E9 = { [0] = -8, 8 }                                           -- gUnk_080D13E9
local T1400 = { [0] = { [0] = 0x8000, 0x7000, 0x6000, 0x5000, 0x4000 }, { [0] = 0x8000, 0x9000, 0xA000, 0xB000, 0xC000 } } -- gUnk_080D1400
local T1414 = { [0] = 0, 0xc, 0xe, 0x10, 0x1c }                         -- gUnk_080D1414
local T1419 = { [0] = 0, 0xa, 0xa, 0xa, 0x1c }                          -- gUnk_080D1419
A.T = { T1286 = T1286, T1362 = T1362, T13B7 = T13B7, T1414 = T1414, T1419 = T1419, T12F8 = T12F8 }
local HB_450 = { x = 0, y = -3, w = 4, h = 4 }                          -- gUnk_080FD450
local HB_538 = { x = 0, y = -4, w = 6, h = 6 }                          -- gUnk_080FD538 (depth 10)

local function hi(w) return band(rshift(w, 8), 0xFF) end
local function setHi(w, v) return bor(band(w, 0xFF), lshift(band(v, 0xFF), 8)) end
local function w16(v) return band(v, 0xFFFF) end
local function s16(v) v = band(v, 0xFFFF) if v >= 0x8000 then return v - 0x10000 end return v end
local function u32(v) return v % 4294967296 end
local function hx(v) return math.floor(v) end
A.hi, A.setHi = hi, setHi

-- CreateEnemy(VAATI_ARM, 0) from VaatiWrath's sub_08041F74
function A.create(V, e, k)
  local t0 = e.t0
  local def = V:edef(V.ARM, 0)
  local e0 = V:part(def, "enemy", { type = 0, type2 = k, spritePriority = 5, depth = 10, hitbox = HB_538 })
  V.copyPos(t0, e0)
  local arm = { k = k, ents = { [0] = e0 }, s1 = {}, parent = t0, e0 = e0, wr = e }
  e0.arm = arm
  return arm
end

-- sub_080437DC: the other four parts and the joints
local function makeHeap(V, arm)
  local e0 = arm.e0
  e0.spritePriority = 5
  for t = 1, 4 do
    local d = V:edef(V.ARM, t)
    local pt = V:part(d, "enemy", { type = t, spritePriority = 5, depth = 10, hitbox = HB_538, arm = arm })
    V.copyPos(e0, pt)
    arm.ents[t] = pt
  end
  local w = T135C[arm.k]
  for i = 0, 4 do arm.s1[i] = { u00 = w, u04 = 0x4000, u08 = 0, u0a = 0, u0c = 0, u0d = 0, u0e = 0 } end
  return true
end

-- sub_0804393C: entity t placed from entity t+1 (or Vaati)
local function place(V, arm, t)
  local e0 = arm.e0
  local pt = arm.ents[t]
  if not pt then return end
  local src = (t == 4) and arm.parent or arm.ents[t + 1]
  if not src then return end
  local w = 0
  if (e0.unk7c or 0) ~= 0 and (e0.unk7d or 0) <= t then w = T1362[t * 16 + band(rshift(e0.unk7c, 3), 0xF)] end
  local hs = arm.s1[t]
  local len = (w + hs.u0c) * 256
  local ph, yh = hi(hs.u04), hi(hs.u00)
  local zo = -V.SIN[ph + 0x40] * len                         -- 16.16
  local r = V.SIN[band(ph, 0x7F)] * len
  r = (r >= 0) and math.floor(r / 256) or -math.floor(-r / 256)
  local xo = V.SIN[yh] * r
  local yo = -V.SIN[yh + 0x40] * r
  pt.x, pt.y, pt.z = src.x + xo / 65536, src.y + yo / 65536, (src.z or 0) + zo / 65536
  pt.spriteOY = src.spriteOY or 0
  pt.spriteOX = src.spriteOX or 0
end
A.place = place

local function V_s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end
-- sub_08043B08: joint t kept within gUnk_080D13B2[t] of t-1
local function follow(arm, t)
  local h1, h2 = arm.s1[t - 1], arm.s1[t]
  local b = T13B2[t]
  local d
  if arm.k == 0 then
    d = V_s8(hi(h1.u00) - hi(h2.u00))
    if d < 0 or b < d then
      if d <= 0 then h2.u00 = setHi(h2.u00, hi(h1.u00)) else h2.u00 = setHi(h2.u00, hi(h1.u00) - b) end
    end
  else
    d = V_s8(hi(h2.u00) - hi(h1.u00))
    if d < 0 or b < d then
      if d < 0 then h2.u00 = setHi(h2.u00, hi(h1.u00)) else h2.u00 = setHi(h2.u00, hi(h1.u00) + b) end
    end
  end
  d = hi(h1.u04) - hi(h2.u04)
  if u32(d + b) > b * 2 then
    if d > 0 then h2.u04 = setHi(h2.u04, hi(h1.u04) - b) else h2.u04 = setHi(h2.u04, hi(h1.u04) + b) end
  end
end
local function followAll(arm) follow(arm, 1); follow(arm, 2); follow(arm, 3) end -- sub_08043B7C

-- sub_08043A10 / sub_08043A78 / sub_08043ABC
local function layoutAll(V, arm)
  followAll(arm)
  place(V, arm, 4)
  local e4 = arm.ents[4]
  e4.y, e4.z = e4.y - 8, e4.z - 8
  place(V, arm, 3); place(V, arm, 2); place(V, arm, 1); place(V, arm, 0)
  local e0 = arm.e0
  e0.y, e0.spriteOY = e0.y + 1, e0.spriteOY - 1
  if (e0.unk7c or 0) ~= 0 then e0.unk7c = e0.unk7c - 1 end
end
local function layout210(V, arm)
  arm.e0.unk7c = 0
  followAll(arm)
  place(V, arm, 2); place(V, arm, 1); place(V, arm, 0)
  local e0 = arm.e0
  e0.y, e0.spriteOY = e0.y + 1, e0.spriteOY - 1
end
local function layout3210(V, arm)
  arm.e0.unk7c = 0
  followAll(arm)
  place(V, arm, 3); place(V, arm, 2); place(V, arm, 1); place(V, arm, 0)
  local e0 = arm.e0
  e0.y, e0.spriteOY = e0.y + 1, e0.spriteOY - 1
end
A.layoutAll, A.layout210, A.layout3210 = layoutAll, layout210, layout3210

-- sub_08043B9C: the hand's animation by the yaw
local function yawAnim(V, arm, pt)
  pt = pt or arm.e0
  local idx = rshift(band(hi(arm.s1[0].u00) + 4, 0xFF), 3)
  if T13B7[idx] ~= (pt.anim.frame or 0) - 1 then V:anim(pt, T13B7[idx]) end
end
-- sub_08043BC8
local function toSway(arm)
  local e0 = arm.e0
  e0.action = 2
  local c = T13D8[arm.k]
  local s = arm.s1[0]
  s.u08, s.u0a, s.u0d, s.u0e = c[1], c[2], 0x5A, 0x28
end
-- sub_08043BF0: the sweep's hand animations
local function sweepAnim(V, arm)
  local b = hi(arm.s1[0].u00)
  local n
  if arm.k == 0 then
    if b <= 0x2F then n = 6 elseif b <= 0x5F then n = 7 elseif b < 0x90 then n = 8 else n = 9 end
  else
    if b >= 0xD1 then n = 8 elseif b >= 0xA1 then n = 7 elseif b <= 0x70 then n = 5 else n = 6 end
  end
  if arm.e0.animIndex ~= n then V:anim(arm.e0, n) end
end
-- sub_08043C40: the segment lengths while diving
local function diveLen(arm, s)
  local p = hi(s.u04)
  local base
  if p < 0x20 then base = 0 elseif p < 0x30 then base = 3 elseif p < 0x78 then base = 6 else base = 0 end
  for i = 0, 2 do
    local hs = arm.s1[i + 1]
    local want = T13E0[base + i]
    if want ~= hs.u0c then
      if want < hs.u0c then hs.u0c = hs.u0c - 1 else hs.u0c = hs.u0c + 1 end
    end
  end
end
-- sub_08043CD4: a Cane bolt anywhere wobbles it
local function caneWobble(arm)
  for i = 0, 4 do
    local pt = arm.ents[i]
    if pt and pt.contact == 0x80 + 0x1D then arm.e0.unk7c, arm.e0.unk7d = 0x78, i return end
  end
end
-- sub_08043D08: the hand flips open
local function flip(V, arm)
  local e0 = arm.e0
  e0.action, e0.subAction = 7, 0
  V:anim(e0, 0xD)
  local e4 = arm.ents[4]
  e4.collide = false
  V:show(e4, false)
  V:anim(e4, 0x13)
  V:fx(e4.x + T13E9[arm.k], e4.y - 6 + (e4.z or 0), V.FX.EXPLOSION4)
  V.copyPos(arm.ents[3], e4)
  e4.z = e4.z + arm.s1[3].u0c
  for i = 0, 4 do if arm.ents[i] then arm.ents[i].hitType = 0x39 end end
  V:sfx(V.SFX.HIT)
end
-- sub_08043C98 (USA): a Cane bolt on ents[2] / [3]
local function caneFlip(V, arm)
  local c2, c3 = arm.ents[2] and arm.ents[2].contact, arm.ents[3] and arm.ents[3].contact
  if c2 == 0x80 + 0x1D or c3 == 0x80 + 0x1D then
    flip(V, arm)
    local RT = V.rt(V.field)
    RT.f38 = bor(RT.f38, 2)
    return true
  end
  return false
end
A.caneFlip = caneFlip

-- sub_08043DB0: Minish Link on the open hand goes in
local function enter(V, arm)
  local f = V.field
  local p = f.player
  if not p.minish or f.transition then return end
  local e3 = arm.ents[3]
  local cx, cy = hx(e3.x), hx(e3.y) + 2
  local dx, dy = cx - (hx(p.x) - 3), cy - (hx(p.y) - 3)
  if not (dx >= 0 and dx < 6 and dy >= 0 and dy < 6) then return end
  local RT = V.rt(f)
  local room = 0
  if band(RT.f39, 3) ~= 3 then room = 1 end
  RT.f3d = 0x1E - math.floor(arm.e0.unk7a / 0x3C)
  RT.f3c = arm.k
  local wr = arm.parent
  RT.f40, RT.f42 = hx(wr.x), hx(wr.y)
  local h = wr.heap
  local a0, a1 = h.arms[0], h.arms[1]
  if a0 then RT.f44, RT.f46 = hx(a0.e0.x), hx(a0.e0.y) else RT.f44, RT.f46 = 0x110, 0x60 end
  if a1 then RT.f48, RT.f4a = hx(a1.e0.x), hx(a1.e0.y) else RT.f48, RT.f4a = 0x110, 0x60 end
  A.lastEnter = { room = room, f3d = RT.f3d, f3c = RT.f3c }
  -- gUnk_080D13EC: AREA_VAATIS_ARMS (0x98, 0xb8), layer 1
  f:startTransition({ warpType = 1, area = V.AREA_ARMS, room = room, endX = 0x98, endY = 0xB8, facing = 0, kind = 0, layer = 1 })
end
A.enter = enter

-- sub_08043EB8: the arm Link came out of lies open
local function lieOpen(V, arm)
  local RT = V.rt(V.field)
  local e0 = arm.e0
  e0.collide = true
  e0.spritePriority = 4
  V:anim(e0, 0xD)
  local E = arm.ents
  E[1].collide, E[1].spritePriority = true, 4
  E[2].collide, E[2].spritePriority = true, 4
  E[3].collide = false; V:show(E[3], true); E[3].spritePriority = 4
  local e4 = E[4]
  e4.collide = true; V:show(e4, true); e4.spritePriority = 4
  if arm.k == 0 then e4.x, e4.y = RT.f44, RT.f46 else e4.x, e4.y = RT.f48, RT.f4a end
  e4.z = 0
  e4.depth, e4.hitType, e4.hitbox = 5, 0x3A, HB_450
  local o = V:armObj(0, E[3], arm)
  e0.unk68 = o
  for i = 0, 4 do arm.s1[i].u00, arm.s1[i].u04, arm.s1[i].u0c = 0x8000, 0, T1419[i] end
end
-- sub_08044000: the other arm, already out
local function already(V, arm)
  local P = T1400[arm.k]
  for i = 0, 4 do
    local pt = arm.ents[i]
    pt.collide = true
    pt.spritePriority = 4
    local hs = arm.s1[i]
    hs.u00, hs.u04, hs.u0c = P[i], 0x4000, T1414[i]
  end
  V:anim(arm.e0, 7)
  V.copyPos(arm.parent, arm.ents[4])
end

-- ---------------------------------------------------------------------------
-- the actions
-- ---------------------------------------------------------------------------
local function grow(V, arm) -- sub_08042654
  local e0 = arm.e0
  local s = arm.s1[0]
  local idx = arm.k * 4
  local sa = e0.subAction
  if sa == 0 then
    e0.subAction = 1
    s.u00 = setHi(s.u00, T1284[arm.k])
    V:anim(e0, T1286[idx])
    V:sfx(0x15E)
  elseif sa >= 1 and sa <= 4 then
    s.u00 = w16(s.u00 + s.u08)
    local lim = ({ 0xC, 0xE, 0x10, 0x1C })[sa]
    local hs = arm.s1[sa]
    hs.u0c = hs.u0c + 2
    if hs.u0c >= lim then
      if sa < 4 then
        e0.subAction = sa + 1
        V:anim(e0, T1286[idx + sa])
      else
        e0.subAction, e0.timer = 5, 90
        for i = 0, 4 do arm.ents[i].collide = true; arm.ents[i].spritePriority = 4 end
        V:anim(e0, 7)
      end
      V:sfx(0x15E)
    end
  else
    e0.timer = e0.timer - 1
    if e0.timer == 0 then toSway(arm) end
  end
  layoutAll(V, arm)
end

local function sway(V, arm) -- sub_08042818
  caneWobble(arm)
  local s = arm.s1[0]
  s.u00 = w16(s.u00 + s.u08)
  s.u0d = band(s.u0d - 1, 0xFF)
  if s.u0d == 0 then s.u0d = 0x78; s.u08 = -s.u08 end
  s.u04 = w16(s.u04 + s.u0a)
  s.u0e = band(s.u0e - 1, 0xFF)
  if s.u0e == 0 then s.u0e = 0x50; s.u0a = -s.u0a end
  layoutAll(V, arm)
end

local function sweep(V, arm) -- sub_08042870 / gUnk_080D1290
  caneWobble(arm)
  local e0 = arm.e0
  local s = arm.s1[0]
  local sa = e0.subAction
  if sa == 0 then
    e0.subAction = 1
    s.u08 = T12AC[arm.k]
  elseif sa == 1 then
    local b = hi(s.u04)
    if b ~= 0x40 then if b >= 0x41 then s.u04 = w16(s.u04 - 0x80) else s.u04 = w16(s.u04 + 0x80) end end
    if u32(hi(s.u00) - T12B0[arm.k] + 1) > 2 then s.u00 = w16(s.u00 + s.u08)
    else e0.subAction, e0.timer = 2, 30 end
    sweepAnim(V, arm)
  elseif sa == 2 then
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      e0.subAction = 3
      s.u08 = s16(s.u08 * -3)
      V:sfx(0x153)
      for i = 0, 4 do arm.ents[i].hitType = 0x3B end
    end
  elseif sa == 3 then
    if u32(hi(s.u00) - 0x7C) >= 9 then s.u00 = w16(s.u00 + s.u08)
    else e0.subAction, e0.speed = 4, s.u08 end
    sweepAnim(V, arm)
  elseif sa == 4 then
    if u32(hi(s.u00) - T12B2[arm.k] + 2) >= 5 then
      s.u08 = s16(s.u08 + T12B4[arm.k])
      s.u00 = w16(s.u00 + s.u08)
    else
      e0.subAction, e0.timer = 5, 60
      for i = 0, 4 do arm.ents[i].hitType = 0x39 end
    end
    sweepAnim(V, arm)
  elseif sa == 5 then
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      e0.subAction = 6
      local sp = -e0.speed
      s.u08 = (sp >= 0) and math.floor(sp / 6) or -math.floor(-sp / 6)
    end
  else
    if u32(hi(s.u00) - T12B6[arm.k]) + 1 >= 3 then
      s.u00 = w16(s.u00 + s.u08)
      sweepAnim(V, arm)
    else
      toSway(arm)
      V:anim(e0, 7)
    end
  end
  layoutAll(V, arm)
end

local function slam(V, arm) -- sub_08042A3C / gUnk_080D12B8
  local e0 = arm.e0
  local s = arm.s1[0]
  local sa = e0.subAction
  if sa == 0 then
    e0.subAction, e0.unk78, e0.unk7e = 1, 0, 1
    s.u0a = 0x200
  elseif sa == 1 then
    local want = T12C8[arm.k]
    if want ~= hi(s.u00) then
      if want < hi(s.u00) then s.u00 = w16(s.u00 - 0x100) else s.u00 = w16(s.u00 + 0x100) end
    end
    if s.u0a < s.u04 then s.u04 = w16(s.u04 - s.u0a)
    else
      s.u04 = 0
      s.u08 = s16(T12CA[arm.k])
      e0.subAction, e0.timer = 2, 30
    end
  elseif sa == 2 then
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      e0.subAction, e0.timer = 3, 4
      e0.hitType = 0x3D
      V:anim(e0, 0xE)
      arm.ents[1].hitType = 0x3D
    end
  else
    if hi(s.u04) < 0x7B then s.u04 = w16(s.u04 + 0x500) else s.u04 = setHi(s.u04, 0x80) end
    if 0x30 < hi(s.u04) then s.u00 = w16(s.u00 + s.u08) end
    if arm.ents[3].drawOn then
      diveLen(arm, s)
      for i = 0, 3 do
        local pt = arm.ents[i]
        if -0xA <= hx(pt.z) and pt.drawOn then
          if i == 0 then
            local o = V:armObj(0, arm.ents[4], arm)
            arm.ents[4].unk68 = o
            V:armObj(2, arm.ents[4], arm)
          end
          pt.collide = false
          V:show(pt, false)
          V:sfx(0x161)
        end
      end
    else
      e0.unk78 = e0.unk78 + 2
      e0.timer = e0.timer - 1
      if e0.timer == 0 then
        e0.action, e0.subAction, e0.timer = 5, 0, 30
        e0.hitType = 0x39
        arm.ents[1].hitType = 0x39
      end
    end
  end
  layoutAll(V, arm)
  local e4 = arm.ents[4]
  e4.z = e4.z + e0.unk78
end

local function under(V, arm) -- sub_08042C14 / gUnk_080D12D0
  local f = V.field
  local p = f.player
  local e0 = arm.e0
  local E = arm.ents
  local s = arm.s1[0]
  local sa = e0.subAction
  if sa == 0 then
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      e0.timer, e0.subtimer, e0.subAction = 60, 3, 1
      local r = band(V:rand(), 6)
      local x, y = hx(p.x) + T12F8[r], hx(p.y) + T12F8[r + 1]
      local rm = f.room
      local W, H = rm.width or 0x160, rm.height or 0xF0
      if 0x20 > x then x = 0x20 end
      if W - 0x20 < x then x = W - 0x20 end
      if 0x20 > y then y = 0x20 end
      if H - 0x40 < y then y = H - 0x40 end
      if u32(x - 0x90) < 0x41 and u32(y - 8) < 0x41 then x, y = 0xB0, 0x40 end
      for i = 0, 3 do
        local pt = E[i]
        pt.x, pt.y, pt.z = x, y, 0x32
        pt.hitType = 0x39
        local hs = arm.s1[i]
        hs.u00, hs.u04, hs.u0c = 0x80, 0, T1419[i]
        if i ~= 0 then V:anim(pt, 0x12) end
      end
    end
  elseif sa == 1 then
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      e0.subAction = 2
      e0.hitType = 0x3D
      E[1].hitType = 0x3D
      e0.unk68 = V:armObj(1, E[3], arm)
      V:anim(e0, 0xD)
    end
  elseif sa == 2 then
    for i = 0, 3 do
      local pt = E[i]
      if hx(pt.z) < 4 then
        if i ~= 2 then pt.collide = true end
        if not pt.drawOn then V:armObj(2, pt, arm); V:sfx(0x166) end
        V:show(pt, true)
      end
    end
    local e3 = E[3]
    if hx(e3.z) <= -3 then
      e3.z = -5
      s.u08, s.u0a = T1300[arm.k], 0xC0
      e0.subAction, e0.timer = 3, 30
      e0.hitType = 0x39
      e0.unk7f = 0x2D
      V:anim(e0, 0)
      E[1].hitType = 0x39
    else
      e3.z = e3.z - 2
    end
  elseif sa == 3 then
    local skip = false
    if e0.unk7f == 0 then if caneFlip(V, arm) then skip = true end
    else e0.unk7f = e0.unk7f - 1 end
    if not skip then
      e0.timer = e0.timer - 1
      if e0.timer == 0 then
        e0.subAction = 4
        e0.timer = band(V:rand(), 0x38) + 40
        e0.speed = 0x200
        e0.direction = rshift(hi(s.u00), 3)
        local d = V.dirTo(hx(e0.x), hx(e0.y), 0x110, 0x60)
        e0.unk79 = band(T1304[band(V:rand(), 7)] + d, 0x1F)
      end
      s.u00 = w16(s.u00 + s.u08)
      s.u04 = w16(s.u04 + s.u0a)
      if s.u0a >= 1 then
        if hi(s.u04) >= 0x19 then s.u0a = -s.u0a end
      elseif 3 >= hi(s.u04) then s.u0a = -s.u0a end
      V.step(e0)
    end
  elseif sa == 4 then
    V.step(e0)
    if not caneFlip(V, arm) then
      e0.timer = e0.timer - 1
      if e0.timer == 0 then
        if V.within(e0, p.x, p.y, 0x50) then e0.subAction, e0.timer = 6, 40
        else
          e0.subAction = 5
          V:anim(e0, 0xF)
          V:sfx(0x19B)
        end
      end
      if hi(s.u04) < 0x20 then s.u04 = w16(s.u04 + 0x100) end
      local wr = arm.parent
      local x, y = hx(wr.x), hx(wr.y) - 0x10
      if V.within(e0, x, y, 0x30) then
        local t = V.dirTo(hx(e0.x), hx(e0.y), x, y)
        if u32(e0.unk79 - t + 4) < 9 then e0.unk79 = bxor(t, 0x10) end
      end
      if e0.unk79 ~= e0.direction then
        V.turnTo(e0, e0.unk79)
        s.u00 = setHi(s.u00, lshift(e0.direction, 3))
      end
      local e3 = E[3]
      e3.direction = e0.direction
      local ox, oy = e3.x, e3.y
      V.linear(e3)
      if V:solid(e3.x, e3.y) then e3.x, e3.y = ox, oy end -- ProcessMovement0
    end
  elseif sa == 5 then
    V.step(e0)
    if not caneFlip(V, arm) then
      local fr = V.frame(e0)
      if band(fr, 1) ~= 0 then
        V:hand(e0)
        V.clear(e0, 0xFF) -- super->frame = 0
      elseif band(fr, 0x80) ~= 0 then
        e0.subtimer = e0.subtimer - 1
        if e0.subtimer == 0 then e0.subAction, e0.timer = 8, 60
        else e0.subAction, e0.timer = 3, 60; V:anim(e0, 0) end
      end
    end
  elseif sa == 6 then
    if not caneFlip(V, arm) then
      if hi(s.u04) < 0x50 then
        s.u04 = w16(s.u04 + 0x200)
        if 0x4F < hi(s.u04) then
          for i = 0, 4 do E[i].hitType = 0x3B end
          V:sfx(0x153)
        end
      else
        s.u00 = w16(s.u00 + s.u08 * 8)
        e0.timer = e0.timer - 1
        if e0.timer == 0 then
          e0.subAction = 7
          for i = 0, 4 do E[i].hitType = 0x39 end
        end
      end
      yawAnim(V, arm)
    end
  elseif sa == 7 then
    if not caneFlip(V, arm) then
      s.u00 = w16(s.u00 + s.u08)
      s.u04 = w16(s.u04 - 0x100)
      if hi(s.u04) < 0x18 then
        e0.subtimer = e0.subtimer - 1
        if e0.subtimer == 0 then e0.subAction, e0.timer = 8, 60
        else
          e0.subAction, e0.timer = 3, 60
          s.u0a = -0xC0
          V:anim(e0, 0)
        end
      end
    end
  elseif sa == 8 then
    if hi(s.u04) ~= 0 then
      if not caneFlip(V, arm) then
        s.u04 = setHi(s.u04, hi(s.u04) - 1)
        if hi(s.u04) == 0 then V:anim(e0, 0xD) end
      end
    elseif e0.timer ~= 0 then
      e0.timer = e0.timer - 1
      for i = 1, 3 do local hs = arm.s1[i]; if hi(hs.u04) ~= 0 then hs.u04 = setHi(hs.u04, hi(hs.u04) - 1) end end
    else
      E[3].z = E[3].z + 3
      for i = 0, 3 do
        local pt = E[i]
        if hx(pt.z) > -4 then
          pt.collide = false
          if pt.drawOn then V:sfx(0x161) end
          V:show(pt, false)
        end
      end
      if not e0.drawOn then e0.subAction, e0.timer = 9, 60 end
    end
  else -- 9
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      e0.action, e0.subAction = 6, 0
      for i = 0, 3 do
        local hs = arm.s1[i]
        hs.u00, hs.u04, hs.u0c = T130C[arm.k], 0x8000, T1414[i]
        if i == 3 then V:anim(E[3], 0x11) end
      end
      s.u08 = T1310[arm.k]
      V:anim(e0, 0xE)
    end
  end
  layout210(V, arm)
end

local function rise(V, arm) -- sub_0804325C / gUnk_080D1314
  caneWobble(arm)
  local e0 = arm.e0
  local E = arm.ents
  local s = arm.s1[0]
  if e0.subAction == 0 then -- sub_080432A8
    local n = 0
    for i = 3, 0, -1 do
      local hs = arm.s1[i]
      if hs.u0c > 2 then
        hs.u0c = hs.u0c - 1
        n = n + 1
        if n > 1 then break end
      end
    end
    s.u04 = setHi(s.u04, hi(s.u04) - 2)
    for i = 0, 3 do
      local pt = E[i]
      if hx(pt.z) < 4 then pt.collide = true; V:show(pt, true) end
    end
    if e0.drawOn and arm.s1[1].u0c < 3 then
      e0.subAction, e0.timer = 1, 0x1E
      s.u04 = 0x4000
    end
  else -- sub_0804334C
    local go = true
    if e0.timer ~= 0 then
      e0.timer = e0.timer - 1
      if e0.timer ~= 0 then go = false
      else for i = 0, 4 do E[i].collide = true; V:show(E[i], true) end end
    end
    if go then
      local b
      if u32(T131C[arm.k] - hi(s.u00) + 1) > 2 then s.u00 = w16(s.u00 + s.u08); b = false else b = true end
      yawAnim(V, arm)
      for i = 0, 4 do
        local hs = arm.s1[i]
        if T1414[i] > hs.u0c then
          hs.u0c = hs.u0c + 1
          if T1414[i] == hs.u0c then V:sfx(0x15E) end
          break
        end
        if b and i == 4 then
          toSway(arm)
          V:anim(e0, 7)
          if e0.unk7e ~= 0 then
            e0.unk7e = 0
            arm.parent.subAction = 2
          end
        end
      end
    end
  end
  layoutAll(V, arm)
  if e0.unk78 ~= 0 then
    if e0.unk78 >= 3 then
      e0.unk78 = e0.unk78 - 2
      E[4].z = E[4].z + e0.unk78
    else e0.unk78 = 0 end
  end
end

local function open(V, arm) -- sub_08043420 / gUnk_080D1320
  local e0 = arm.e0
  local E = arm.ents
  local sa = e0.subAction
  if sa == 0 then -- sub_08043440
    local n = 0
    for i = 0, 4 do
      local hs = arm.s1[i]
      if hi(hs.u04) >= 0x11 then hs.u04 = setHi(hs.u04, hi(hs.u04) - 0x10); n = n + 1
      else hs.u04 = 0 end
    end
    if n == 0 then
      for i = 0, 4 do arm.s1[i].u00 = 0x8000 end
      e0.subAction = 1
      V:anim(e0, 0x10)
    end
  elseif sa == 1 then -- sub_08043490
    local e4 = E[4]
    if hx(e4.z) < -4 then
      e4.zv = 1.5
      e0.subAction, e0.unk7e = 2, 0
      arm.parent.subAction = 2
    else
      e4.z = e4.z - 2
      if hx(e4.z) < 0 then
        e4.collide = true
        V:show(e4, true)
        e4.depth, e4.hitType, e4.hitbox = 5, 0x3A, HB_450
        E[2].collide = true
        E[3].collide = false
      end
    end
    V.step(e0)
  elseif sa == 2 then -- sub_08043520
    local e4 = E[4]
    V.gravity(e4, 26 / 256)
    if e4.zv < 0 and -6 < hx(e4.z) then
      e4.z = -6
      e0.subAction, e0.unk7a = 3, 900
    end
  elseif sa == 3 then -- sub_0804355C
    enter(V, arm)
    e0.unk7a = e0.unk7a - 1
    if e0.unk7a == 0 then e0.subAction = 4 end
    V.step(e0)
  elseif sa == 4 then -- sub_08043580
    E[4].z = E[4].z + 3
    for i = 0, 4 do
      local pt = E[i]
      if -4 < hx(pt.z) then pt.collide = false; V:show(pt, false) end
    end
    if not e0.drawOn then
      e0.subAction, e0.timer = 5, 60
      local e4 = E[4]
      e4.depth, e4.hitType, e4.hitbox = 10, 0x39, HB_538
    end
  else -- sub_080435F4
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      e0.action, e0.subAction, e0.timer = 6, 1, 1
      for i = 0, 4 do
        local hs = arm.s1[i]
        hs.u00, hs.u04, hs.u0c, hs.u08 = T1338[arm.k], 0x4000, 0, T133C[arm.k]
        if i == 0 then yawAnim(V, arm, E[0]) else V:anim(E[i], T1340[i]) end
      end
    end
  end
  layout3210(V, arm)
end

local function die(V, arm) -- sub_08043680 / gUnk_080D1348
  local e0 = arm.e0
  local E = arm.ents
  local sa = e0.subAction
  if sa == 0 then
    e0.subAction, e0.timer = 1, 60
    for i = 0, 4 do if E[i] then E[i].collide = false end end
  elseif sa >= 1 and sa <= 3 then -- deleteThing
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      e0.timer, e0.subAction = 20, sa + 1
      if sa == 1 then V:show(e0, false) end
      local pt = E[sa]
      V:fx(pt.x, pt.y + (pt.z or 0), V.FX.EXPLOSION4)
      V:kill(pt)
      E[sa] = nil
    end
  else -- sub_08043770
    e0.timer = e0.timer - 1
    if e0.timer == 0 then
      local RT = V.rt(V.field)
      local wr = arm.parent
      if band(RT.f39, 0xC) == 0 then wr.subAction = 2 end
      if arm.k == 0 then RT.f39 = band(RT.f39, 0xFE) else RT.f39 = band(RT.f39, 0xFD) end
      arm.gone = true -- the heap's arms[k] = NULL
      local e4 = E[4]
      e4.health = 0
      if e0.unk68 then e0.unk68.parent = e4 end
      V:kill(e0)
      -- the shoulder: GetNextFunction -> GenericDeath
      V:fx(e4.x, e4.y + (e4.z or 0), V.FX.DEATH)
      V:sfx(0x1BC)
      V:kill(e4)
    end
  end
end

-- sub_080425B4
local function init(V, arm)
  if not makeHeap(V, arm) then return end
  local e0 = arm.e0
  local RT = V.rt(V.field)
  e0.unk7c, e0.unk7d = 0, 0
  e0.unk78, e0.unk79, e0.unk7a, e0.unk7e, e0.unk7f = 0, 0, 0, 0, 0
  if band(RT.f38, 1) ~= 0 then
    if RT.f3c == arm.k then
      lieOpen(V, arm)
      layout3210(V, arm)
      if band(rshift(RT.f39, arm.k + 2), 1) ~= 0 then e0.action, e0.subAction = 7, 4
      else e0.action, e0.subAction = 8, 0 end
      arm.inArm = true
    else
      already(V, arm)
      toSway(arm)
      layoutAll(V, arm)
    end
  else
    e0.action, e0.subAction = 1, 0
    arm.s1[0].u08 = T1280[arm.k]
    grow(V, arm)
  end
end

-- the segments' own OnTick (sub_08044078 / sub_080440CC)
local function segTick(V, arm, pt)
  if pt.action == 0 then
    pt.action = 1
    local RT = V.rt(V.field)
    local mine = band(RT.f38, 1) ~= 0 and arm.k == RT.f3c
    if pt.type == 4 then V:anim(pt, mine and 0x13 or 0x11)
    elseif pt.type ~= 3 or not mine then V:anim(pt, 0x12)
    else V:anim(pt, 0x11) end
  end
  V.step(pt)
end

function A.tick(V, e, arm)
  local e0 = arm.e0
  if e0.deleted and not arm.gone then return end
  if not arm.ents[1] and e0.action == 0 then init(V, arm)
  elseif not e0.deleted then
    if e0.iframes > 0 then e0.iframes = e0.iframes - 1 end
    local a = e0.action
    if a == 1 then grow(V, arm)
    elseif a == 2 then sway(V, arm)
    elseif a == 3 then sweep(V, arm)
    elseif a == 4 then slam(V, arm)
    elseif a == 5 then under(V, arm)
    elseif a == 6 then rise(V, arm)
    elseif a == 7 then open(V, arm)
    elseif a == 8 then die(V, arm) end
  end
  for t = 1, 4 do
    local pt = arm.ents[t]
    if pt and not pt.deleted then
      if pt.iframes > 0 then pt.iframes = pt.iframes - 1 end
      segTick(V, arm, pt)
    end
  end
  -- touching Link
  for t = 0, 4 do
    local pt = arm.ents[t]
    if pt and not pt.deleted then
      if pt.collide and pt.drawOn then V:touchLink(pt) end
      pt.contact = nil
      pt.hidden = not pt.drawOn
    end
  end
end

return A
