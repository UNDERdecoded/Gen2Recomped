-- Round 26 (team B): Vaati Transfigured -- the second Vaati fight (area $8C
-- VAATI_2 room 0) -- and the Vaati's-arms pieces the third fight's rooms
-- use (VAATI_EYES_MACRO in area $8A, the VAATI3 managers), from the decomp.
-- Same model as BossVaati.lua (its helpers, M.H): every part is a regular
-- enemy entity, health biased, COLLISION_OFF = mask + noTouch.
--
-- VAATI_TRANSFIGURED ($4F, src/enemy/vaatiTransfigured.c):
--   type 0 (the body; animationState = the phase 0..2):
--     every frame (action > 0) unk_78..7e keep the last two positions and
--     sub_080409B0 runs the eye puzzle: unk_75 = the real eyes (bit mask,
--     sub_080408EC: $F0 in phase 0, then gUnk_080D0B74 at random, never the
--     same twice), unk_76 = the eyes done.  unk_81 0: all real eyes shot
--     (arrows, contact $0E / $15) -> 1; 1: the first real eye struck -> 2
--     with 16 frames to strike the rest (else SFX_155, back to 1); all of
--     them -> action 3, unk_81 3, hitType $36, zVelocity 1.5, SFX_164.
--     Knockback1 while unk_81 < 3; a hit after that: shake 12 + SFX_BOSS_HIT
--     (a charged spin, contact $8A with chargeState 5, sets health $C0).
--   action 0: waits for room flag 0 (script_CutsceneOrchestratorV2Intro),
--     then the parts (types 1-5, type2 0) and the eight eyes, anim 0.
--   1 (float): unk_80 $FF 48 frames, 0 -> speed $180 20 frames, $C0 12, 0
--     (animationState < 2: 64..191 frames, else 8) with the shake
--     (sub_08040AD4, SFX_1A9), then sub_08040934 picks 1 (action 4), 2 (5),
--     3 (6) or another float (unk_80 4 -> sub_08040670: a new target from
--     gUnk_080D0B58 (phase 0) / gUnk_080D0B64 (the corners, unk_87 laps));
--     a VAATI2_PARTICLE every 4 frames; ProcessMovement0.
--   3 (down): bounce (BounceUpdate 40/256) -> collision on, SFX_14C, shake
--     20; 192 frames hittable (hitType $36); health under gUnk_080D0ABC
--     [phase] ($F0 / $D0 / $C0) -> the next phase (the third: action 7,
--     224 frames); then the eye's hurt look (child unk_74 $10) and up again
--     (64 frames, zVelocity 3.5, SFX_1B0 / SFX_149, landing SFX_14C + shake
--     30, health $FF, new eyes) or (no phase change) 80 frames of
--     particles (SFX_124), then action 1.
--   4 (stomp): 0 -> zVelocity 2.25 + SFX_12B, landing SFX_14C + shake 30,
--     128 frames of V2_PROJECTILE every 8 (type subtimer: 0 crawling
--     flames, 1 falling rocks; phase 2+ rocks first), gUnk_080D0ABF waits.
--   5 / 6 (fireballs): type 2 V2_PROJECTILE every 16 (5, random way) / 32 (6,
--     at Link, 32 px up), half speed once unk_81 is set; phase 2+ starts
--     with 128 frames of rocks; type 4 / 5 parts glow (SFX_149 every 10).
--   7 (death): PausePlayer, FX_AURA_BASE + SFX_16E every 8 frames for 224
--     frames, room flag 2, 8 frames, health 0, GenericDeath.
--   type 1 (the after-image at the position two frames back; anim 1 from
--     action 5 on), type 2 type2 0 (the face: blinks (anim 8), hurt look
--     anim 7 on unk_74 $10), type2 1 / 2 (the pupils, gUnk_080D0B18 by
--     Link's bearing, only on the body's frame 2), type 3 (anim 0), type 4
--     (shown in action 5), type 5 (action 6: type2 1 sparks).  All follow
--     the body (CopyPosition) and go when its health is 0.
-- VAATI_TRANSFIGURED_EYE ($5A, src/enemy/vaatiTransfiguredEye.c): type 0
--   the socket at gUnk_080D18B4[type2] (+3), type 1 the eye (hitType $33)
--   on it; they open after $30 frames (anim type << 3 | 1 -> type << 3);
--   an arrow ($0E / $15) shuts one (anim timer + 2; real eye SFX_17A and
--   unk_76 bit, else SFX_ITEM_GLOVES_KNOCKBACK; hitType $31 / $32); a
--   struck eye (health off $FF) with unk_81 set marks unk_76 (anim 6);
--   the body's fall (action 3, unk_80 1) closes them (anim 4 / 5) until
--   it is up again.  The palette cycles with the frame bits $70 (sub_
--   08045A28: $13B / $13E / $13F).
-- V2_PROJECTILE (projectile $1F): type 0 crawling flame (ProcessMovement3,
--   48..111 frames, anim 1 burns out), type 1 falling rock (z -160,
--   gravity 24/256, a random tile of the room's two side strips, FX_ROCK),
--   type 2 fireball (96 frames, offscreen -> gone; type2 1 aimed at Link,
--   palette $13F).  Contact: 0 / 1 ModHealth(-2), type 2 ModHealth(-4) +
--   death FX; type 2 is also broken by contact 3 / $14 (boomerang).
-- VAATI2_PARTICLE (object $9B, src/object/vaati2Particle.c): anim = type,
--   type2 != $FF placed at gUnk_081242D8[type2] round the parent; gone when
--   the animation ends (the port's fx entity).
-- VAATI_EYES_MACRO ($25, src/enemy/vaatiEyesMacro.c; inside Vaati's arms,
--   area $8A rooms 0 / 1 -- the third fight): type 0 the real eye (health
--   from gRoomTransition.field_0x3a / 3b per room), seven type 1 decoys
--   (health always $FF, SFX_BUTTON_DEPRESS), type 2 the pupil (frameIndex
--   gUnk_080CDE70 by Link's bearing), type 3 the shadow (frame $11); they
--   bob (gUnk_080CDE90) and walk the tile grid (sub_0802F04C, speeds
--   gUnk_080CDE98, a new way at each tile centre after 1..4 tiles).  The
--   eye's death clears bit (field_0x3c + 2) of field_0x39 (the arm is
--   beaten).  It makes VAATI3_INSIDE_ARM_MANAGER ($34): field_0x3d * 60
--   frames (capped $12D once the eye is gone), shakes at $12C / $D2 / $78,
--   SFX_126 faster and faster, then out to Vaati's room as Minish
--   (gUnk_0813AC48).
-- VAATI3_START_MANAGER ($37) and VAATI3_BACKGROUND_MANAGER ($2F) belong to
--   the THIRD fight (Vaati's Wrath); they are ported here as the round's
--   task says (BossVaati3 can take them over: M.OWNS_VAATI3_MANAGERS there
--   makes this module leave them).  $37 type 0 (the garden, $89:01; local
--   $7B): sets gRoomTransition ($38 0, $39 $0F, $3A / $3B $20, the save's
--   vaati timer $1194); Link within $30 of (+$88, +$40): paused, a
--   THUNDERBOLT, '!', BGM_VAATI_WRATH; 120 frames on the ground; TEXT_VAATI2
--   $4F; 30 frames; white fade + SFX_EVAPORATE; ZELDA_CHASE cleared and
--   the exit to Vaati's room (gUnk_0813AC34).  Type 1 ($8B:00): VAATI_WRATH
--   at (+$B0, +$48) (only when BossVaati3 is loaded), Link locked, white
--   fade-in + SFX_APPARATE, then its subAction 1.  $2F: bg3OffsetX -= $4000,
--   Y -= $2000 a frame (kept in gRoomTransition-like state).
-- gRoomTransition.field_0x38..3d live in M.rt(f) (f.game.tmcVaatiRT), shared
--   with BossVaati3.
-- SIMPLIFIED: the BG3 picture of $2F (gfx group $4C) is not drawn (only the
--   offsets run); V2_PROJECTILE's tile changes (TILE_TYPE_109 / 110) and
--   OnGrabbed (Gust Jar) are not done; the spin attack ($8A + chargeState)
--   does not exist here; DeleteClones has no clones; confused stars and
--   EnemySetFXOffset of the eyes macro are not drawn.
local bit = require("bit")
local band, bor, bnot, rshift, lshift = bit.band, bit.bor, bit.bnot, bit.rshift, bit.lshift
local V1 = require("src.zelda.tmc.BossVaati")
local H = V1.H

local M = {}
M.TRANSFIGURED, M.EYE, M.MACRO = 0x4F, 0x5A, 0x25
M.P_V2 = 0x1F
M.VAATI2_PARTICLE = 0x9B
M.MGR_START, M.MGR_BG, M.MGR_ARM = 0x37, 0x2F, 0x34
M.VAATI_WRATH = 0x51

local SFX = { S14C = 0x14C, S1B0 = 0x1B0, S149 = 0x149, S12B = 0x12B, S16E = 0x16E, S155 = 0x155, S164 = 0x164,
              S1A9 = 0x1A9, S124 = 0x124, S17A = 0x17A, S14B = 0x14B, S12D = 0x12D, S193 = 0x193, BOSS_HIT = 0x127,
              GLOVES = 0x119, BUTTON_DEPRESS = 0xE5, S126 = 0x126, EVAPORATE = 0xF6, APPARATE = 0xF7 }
M.SFX = SFX
local BGM_VAATI_WRATH = 0x32
local FX_DEATH, FX_ROCK, FX_AURA_BASE = 0x02, 0x04, 0x55
local ZELDA_CHASE = 0x1C

-- vaatiTransfigured.c tables
local PHASE_HP = { [0] = 0xF0, 0xD0, 0xC0 }                     -- gUnk_080D0ABC (USA)
local WAITS = { [0] = 0x3C, 0x3C, 0x1E, 0x14, 0x14, 0x14, 0, 0, 0 } -- gUnk_080D0ABF
local PUPIL = { [0] = { 0, -2 }, { 1, -2 }, { 1, -2 }, { 2, -2 }, { 2, -2 }, { 3, -2 }, { 3, -2 }, { 4, -2 }, { 4, -1 }, { 3, -1 },
  { 3, 0 }, { 2, 0 }, { 2, 0 }, { 1, 0 }, { 1, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 }, { -1, 0 }, { -1, 0 },
  { -2, 0 }, { -2, 0 }, { -3, 0 }, { -3, -1 }, { -4, -1 }, { -4, -2 }, { -3, -2 }, { -3, -2 }, { -2, -2 }, { -2, -2 },
  { -1, -2 }, { -1, -2 } }                                        -- gUnk_080D0B18
local TGT0 = { [0] = 0xB0, 0x70, 0x110, 0x40, 0x50, 0x40 }        -- gUnk_080D0B58
local TGT1 = { [0] = 0xB0, 0x40, 0x110, 0xA0, 0xB0, 0xC0, 0x50, 0xA0 } -- gUnk_080D0B64
local EYESETS = { [0] = 0xF0, 0xC3, 0xF0, 0x3C, 0xC3, 0x3C, 0x3C, 0xF0, 0x0F, 0x3C, 0xC3, 0xF0, 0xF0, 0xC3, 0x3C, 0xC3 } -- gUnk_080D0B74
local ATTACKS = { [0] = 1, 0, 1, 2, 0, 1, 2, 0, 1, 0, 2, 1, 2, 1, 0, 2, 1, 2, 0, 1, 2, 1, 2, 0, 2, 1, 0, 1, 1, 0, 2, 0 } -- gUnk_080D0B84
-- vaatiTransfiguredEye.c
local EYE_POS = { [0] = { -24, -10 }, { -10, -24 }, { 10, -24 }, { 24, -10 }, { 24, 10 }, { 10, 24 }, { -10, 24 }, { -24, 10 } } -- gUnk_080D18B4
-- vaati2Particle.c
local PART_POS = { [0] = { 0, -24 }, { 16, -16 }, { 24, 0 }, { 16, 16 }, { 0, 24 }, { -16, 16 }, { -24, 0 }, { -16, -16 } } -- gUnk_081242D8
-- vaatiEyesMacro.c
local MACRO_DIRS = { [0] = 0, 8, 0x18, 0 }                          -- gUnk_080CDE6C
local MACRO_FRAMES = { [0] = 9, 9, 8, 9, 8, 8, 8, 7, 7, 7, 6, 7, 6, 6, 6, 5, 5, 5, 12, 5, 12, 12, 12, 11, 11, 11, 10, 11, 10, 10, 10, 9 } -- gUnk_080CDE70
local MACRO_BOB = { [0] = -2, -3, -4, -5, -6, -5, -4, -3 }        -- gUnk_080CDE90
local MACRO_SPEED = { [0] = 0xC0, 0x100, 0x140, 0x180 }           -- gUnk_080CDE98
M.T = { PHASE_HP = PHASE_HP, WAITS = WAITS, PUPIL = PUPIL, TGT0 = TGT0, TGT1 = TGT1, EYESETS = EYESETS, ATTACKS = ATTACKS,
        EYE_POS = EYE_POS, PART_POS = PART_POS, MACRO_DIRS = MACRO_DIRS, MACRO_FRAMES = MACRO_FRAMES, MACRO_BOB = MACRO_BOB,
        MACRO_SPEED = MACRO_SPEED }

-- the s16 tile offsets per direction quarter (data/const/beanstalkSubtask.s, an .incbin)
M.ROM_RANGES = { vaati2_tileofs = { 0x080B4488, 0x080B4490 } } -- gUnk_080B4488

local START_EXIT = { area = 0x8B, room = 0, endX = 0xB0, endY = 0x88, layer = 1, kind = 0, facing = 0 } -- gUnk_0813AC34
local ARM_EXIT = { area = 0x8B, room = 0, endX = 0xB0, endY = 0x88, layer = 1, kind = 1, facing = 4 }   -- gUnk_0813AC48
M.START_EXIT, M.ARM_EXIT = START_EXIT, ARM_EXIT

-- gRoomTransition.field_0x38 .. 3d (they outlive the room)
function M.rt(f)
  local v3 = package.loaded["src.zelda.tmc.BossVaati3"] -- BossVaati3 keeps the same block (V.RT): share it
  if type(v3) == "table" and v3.V and v3.V.rt then return v3.V.rt(f) end
  local g = f.game or f
  g.tmcVaatiRT = g.tmcVaatiRT or { f38 = 0, f39 = 0, f3a = 0, f3b = 0, f3c = 0, f3d = 0, bg3x = 0, bg3y = 0 }
  return g.tmcVaatiRT
end

local function R(E) return H.R(E.field) end
local function anim(E, e, i) H.setAnim(E, e, i) end
local function dead(pa) return not H.alive(pa) or H.hp(pa) == 0 end -- (parent->health == 0)
local function pause(f, e) -- PausePlayer
  local p = f.player
  if p.state ~= "dead" and (p.state ~= "ext" or p.vaatiHold ~= e) then
    e.holdFn = e.holdFn or function() end
    p.state, p.extUpdate, p.vaatiHold = "ext", e.holdFn, e
  end
end

-- ===========================================================================
-- VAATI_TRANSFIGURED
-- ===========================================================================
local function part(E, e, type, type2) -- sub_08040648
  local c = H.enemy(E, M, M.TRANSFIGURED, type, e.x, e.y, e)
  c.type2 = type2
  if type == 2 and type2 == 0 then e.child = c end
  return c
end
local function particle(E, e, type, type2, x, y, prio) -- CreateObject(VAATI2_PARTICLE, type, type2)
  local f = E.field
  local O = f:objects()
  local d = O and O.def and O:def(M.VAATI2_PARTICLE, type)
  local p = { kind = 6, id = M.VAATI2_PARTICLE, form = type, type2 = type2, x = x or e.x, y = y or e.y, z = e.z or 0,
              fx = true, animationState = 0, field82 = 0, interactType = 0, anim = require("src.zelda.tmc.Anim").new(),
              spritePriority = prio, parent = e, vaatiParticle = true }
  if type2 ~= 0xFF then local o = PART_POS[type2] or PART_POS[0]; p.x, p.y = e.x + o[1], e.y + o[2] end -- Vaati2Particle_Init
  if d and O.dress then O:dress(p, d, type); p.objAnim = type end
  f.entities[#f.entities + 1] = p
  return p
end
M.particle = particle

function M.newEyes(E, e) -- sub_080408EC
  local tmp
  if e.animationState == 0 then tmp = 0xF0
  else
    repeat
      tmp = EYESETS[rshift(band(R(E), 0x3C), 2)]
      if tmp == e.u75 then tmp = 0xFF end
    until tmp ~= 0xFF
  end
  e.u75, e.u76 = tmp, 0
end

function M.retarget(E, e) -- sub_08040670
  e.action, e.u80, e.speed, e.timer = 1, 0, 0x100, 12
  if e.animationState == 0 then M.target0(E, e) else M.target1(E, e) end
end
function M.target0(E, e) -- sub_080406A0
  local r2 = band(R(E), 0x30)
  local i = e.u86
  local tx, ty = TGT0[i * 2], TGT0[i * 2 + 1]
  if H.within(e, tx, ty, 0x1C) then
    if i ~= 0 then i = 0 else i = band(R(E), 1) + 1 end
    tx, ty = TGT0[i * 2], TGT0[i * 2 + 1]
  end
  e.direction = H.dirTo(e.x, e.y, tx, ty)
  if band(r2, 0x20) ~= 0 then e.direction = e.direction + (band(r2, 0x10) ~= 0 and 1 or 0x1F) end
  e.direction = band(e.direction, 0x1F)
  e.u86 = i
end
function M.target1(E, e) -- sub_08040770
  local t = band(R(E), 0x38)
  local i = e.u86
  local tx, ty = TGT1[i * 2], TGT1[i * 2 + 1]
  if H.within(e, tx, ty, 0x1C) then
    if e.animationState ~= 2 then
      i = i + (band(t, 8) ~= 0 and 1 or 3)
      i = band(i, 3)
      if e.u81 ~= 0 then
        if e.u75 == 0x0F and i == 0 then i = 2
        elseif e.u75 == 0x3C and i == 1 then i = 3
        elseif e.u75 == 0xF0 and i == 2 then i = 0
        elseif e.u75 == 0xC3 and i == 3 then i = 1 end
      end
    else
      if band(e.u87, 0x7F) ~= 0 then
        i = i + (band(e.u87, 0x80) ~= 0 and 1 or 3)
        e.u87 = band(e.u87 - 1, 0xFF)
      else
        local n = band(R(E), 7) + 4
        if band(R(E), 0x20) == 0 then n = bor(n, 0x80) end
        e.u87 = n
        i = i + (band(n, 0x80) ~= 0 and 1 or 3)
      end
      i = band(i, 3)
    end
    tx, ty = TGT1[i * 2], TGT1[i * 2 + 1]
  end
  e.direction = H.dirTo(e.x, e.y, tx, ty)
  if band(t, 0x20) ~= 0 then e.direction = e.direction + (band(t, 0x10) ~= 0 and 1 or 0x1F) end
  e.direction = band(e.direction, 0x1F)
  e.u86 = i
end

function M.pickAttack(E, e) -- sub_08040934
  local t = band(R(E), 0x3E)
  local r2 = t < 0x2F and 1 or 0
  if band(e.u87, 0x7F) ~= 0 then r2 = 0 end
  if e.u84 ~= 9 then
    if r2 ~= 0 then
      e.u84 = (e.u84 + 1) % 5
      r2 = ATTACKS[rshift(band(R(E), 0xF8), 3)]
      if e.u84 == 3 or e.u84 == 4 then if r2 == 0 then r2 = 1 end
      elseif e.u84 == 1 then r2 = (r2 ~= 0) and 3 or 1 end
    end
  else
    e.u84, r2 = 0, 1
  end
  return r2
end

local function shake(E, e) -- sub_08040AD4
  local t = band(e.timer, 0x3F)
  if band(t, 0x1F) == 0 then E.field:sound(SFX.S1A9) end
  if band(t, 3) == 0 then
    t = rshift(t, 2)
    e.x = e.x + (band(t + 4, 8) ~= 0 and -1 or 1)
    e.y = e.y + (band(t + 2, 4) ~= 0 and -1 or 1)
  end
end

local function eyePuzzle(E, e) -- sub_080409B0
  local f = E.field
  local s = e.u81
  if s == 0 then
    if e.u75 == e.u76 then e.u81, e.u76 = 1, 0 end
  elseif s == 1 then
    if e.u76 ~= 0 then e.u81, e.u77 = 2, 0x10 end
  elseif s == 2 then
    e.u77 = band(e.u77 - 1, 0xFF)
    if e.u77 == 0 then
      if e.u75 ~= band(e.u75, e.u76) then
        e.u81, e.u76 = 1, 0
        f:sound(SFX.S155)
      else
        e.action, e.u80, e.u81 = 3, 0, 3
        H.colOff(e)
        e.hitType = 0x36
        e.czv = 1.5
        f:sound(SFX.S164)
      end
    end
  end
  if e.u81 < 3 then
    if (e.myKbt or 0) > 0 then -- Knockback1
      e.myKbt = e.myKbt - 1
      local nx, ny = e.x + (e.myKbx or 0), e.y + (e.myKby or 0)
      if not f.room:isSolid(nx, ny, e.layer or 1) then e.x, e.y = nx, ny end
    end
  else
    e.myKbt = 0
    if e.cflags and band(e.cflags, 0x80) ~= 0 and e.iframes > 0 then
      f:shake(12, 1)
      f:sound(SFX.BOSS_HIT)
    end
    if e.cflags == 0x8A and e.spinAttack then H.setHp(e, 0xC0) end -- (no spin attack in the port)
  end
end
local function bodyCol(E, e, fl) -- the knockback is ours (Knockback1 above)
  e.myKbx, e.myKby, e.myKbt = e.kbx, e.kby, e.kbt
  e.kbt = 0
end

local tf0 = {}
tf0[0] = function(E, e)
  local f = E.field
  if f:flag("room", 0) then
    e.action = 1
    H.draw(e, true)
    e.spritePriority = 5
    e.u6d = bor(e.u6d, 1)
    e.direction = band(R(E), 0x17) + 4
    e.timer, e.subtimer = 48, 12
    e.u82, e.u80, e.u74, e.u77, e.u84 = 4, 0xFF, 0, 0, 9
    e.animationState, e.u86, e.u87 = 0, 0, 0
    e.u78, e.u7a, e.u7c, e.u7e = e.x, e.x, e.y, e.y
    e.kids = {}
    for i = 1, 5 do e.kids[#e.kids + 1] = part(E, e, i, 0) end
    R(E)
    M.newEyes(E, e)
    for i = 0, 7 do
      local c = H.enemy(E, M, M.EYE, 0, e.x, e.y, e)
      c.type2 = i
      c.timer = band(rshift(e.u75, i), 1)
      c.hidden = true -- (no frame until its Action0 runs: it waits out an open message)
      e.kids[#e.kids + 1] = c
    end
    anim(E, e, 0)
  end
end
tf0[1] = function(E, e)
  local s = e.u80
  if s == 0xFF then
    e.timer = e.timer - 1
    if e.timer == 0 then e.u80, e.timer = 0, 11 end
  elseif s == 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.u80, e.speed, e.timer = 1, 0x180, 20 end
  elseif s == 1 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.u80, e.speed, e.timer = 2, 0xC0, 12 end
  elseif s == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u80, e.speed = 3, 0
      if e.animationState < 2 then e.timer = band(R(E), 0x7F) + 64 else e.timer = 8 end
    end
  elseif s == 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.cz, e.u80 = 0, 0
      e.timer = WAITS[e.animationState * 2]
      local k = M.pickAttack(E, e)
      if k == 1 then e.action, e.u74 = 4, 1
      elseif k == 2 then e.action = 5
      elseif k == 3 then e.action = 6
      else e.u80 = 4 end
    else
      shake(E, e)
    end
  elseif s == 4 then
    M.retarget(E, e)
  end
  e.u82 = band(e.u82 - 1, 0xFF)
  if e.u82 == 0 then
    e.u82 = 4
    particle(E, e, 0, rshift(band(e.direction + 0x12, 0x1C), 2), nil, nil, 6)
    -- (the +-7 jitter is overwritten by Vaati2Particle_Init's PositionRelative)
    R(E); R(E)
  end
  if e.u80 ~= 0xFF then H.move0(E, e) end
  H.step(e)
end
tf0[2] = function(E, e) H.step(e) end
tf0[3] = function(E, e)
  local f = E.field
  local s = e.u80
  if s == 0 then
    if H.bounce(e, 40 / 256) == 1 then
      e.u80, e.timer = 1, 192
      H.colOn(e)
      f:sound(SFX.S14C)
      f:shake(20, 4)
    end
  elseif s == 1 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.u80, e.hitType, e.spriteOX = 2, 0x35, 0 end
    local adv = false
    if H.hp(e) < PHASE_HP[e.animationState] then adv = true; e.timer = 1 end
    if adv then
      e.u80, e.hitType, e.spriteOX = 2, 0x35, 0
      e.animationState = e.animationState + 1
      if e.animationState > 2 then
        e.action, e.timer = 7, 224
        f:sound(SFX.BOSS_HIT)
        return
      end
    end
  elseif s == 2 then
    if e.child then e.child.u74 = 0x10 end
    if e.timer ~= 0 then e.u80, e.timer = 3, 64
    else e.u80, e.timer = 4, 80 end
  elseif s == 3 then
    if e.timer ~= 0 then
      e.timer = e.timer - 1
      if e.timer == 0 then H.colOff(e); e.czv = 3.5; e.subtimer = 16 end
    else
      if not H.gravity(e, 40 / 256) then
        e.u80, e.timer = 5, 16
        H.colOn(e)
        H.setHp(e, 0xFF)
        e.u86 = 0
        M.newEyes(E, e)
        f:sound(SFX.S14C)
        f:shake(30, 4)
      elseif e.subtimer ~= 0 then
        e.subtimer = e.subtimer - 1
        if e.subtimer == 0 then f:sound(SFX.S1B0)
        elseif band(e.subtimer, 7) == 0 then f:sound(SFX.S149) end
      end
    end
  elseif s == 4 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u80, e.timer, e.u86 = 5, 16, 0
      M.newEyes(E, e)
    elseif band(e.timer, 1) ~= 0 then
      local px = e.x + band(R(E), 0xF) - 7
      local py = e.y + band(R(E), 0xF) - 7
      particle(E, e, 1, 0xFF, px, py, 4)
      f:sound(SFX.S124)
    end
  elseif s == 5 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.u80, e.u81, e.u76 = 1, 0, 0, 0
      M.retarget(E, e)
    end
  end
  if e.u80 > 2 then e.spriteOX = band(e.timer, 1) end
  H.step(e)
end
local function v2(E, e, type) -- EnemyCreateProjectile(super, V2_PROJECTILE, type)
  local p = H.projectile(E, M, M.P_V2, type, e)
  p.type = type
  return p
end
M.v2 = v2
tf0[4] = function(E, e)
  local f = E.field
  local s = e.u80
  if s == 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u80, e.u74, e.timer, e.subtimer = 1, 0, 128, 0
      e.czv = 2.25
      f:sound(SFX.S12B)
    end
  elseif s == 1 then
    if not H.gravity(e, 40 / 256) then
      e.u80 = 2
      if e.u84 == 1 or e.u84 == 3 then e.subtimer = 1
      elseif e.u84 == 0 or e.u84 == 2 then e.subtimer = 0
      else e.subtimer = rshift(band(R(E), 0x20), 5) end
      if e.animationState > 1 then e.subtimer = 1 end
      f:sound(SFX.S14C)
      f:shake(30, 4)
    end
  elseif s == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u80 = 3
      e.timer = WAITS[e.animationState * 2 + 1]
    else
      if band(e.timer, 7) == 0 then v2(E, e, e.subtimer) end
      if e.subtimer ~= 0 and e.animationState > 1 and e.timer < 6 then e.timer, e.subtimer = 128, 0 end
    end
  elseif s == 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.u80, e.cz = 1, 0, 0
      M.retarget(E, e)
    else shake(E, e) end
  end
  H.step(e)
end
local function fireballs(E, e, every, aimed)
  e.timer = e.timer - 1
  if e.timer == 0 then
    e.u80 = 2
    e.timer = WAITS[e.animationState * 2 + 1]
  elseif e.subtimer ~= 0 then
    if band(e.timer, 7) == 0 then v2(E, e, e.subtimer) end
    if e.timer < 6 then e.timer, e.subtimer = aimed and 128 or 64, 0 end
  else
    if band(e.timer, every - 1) == 0 then
      local p = v2(E, e, 2)
      p.type2 = aimed and 1 or 0
      if aimed then p.y = p.y - 0x20 end
      if e.u81 ~= 0 then p.speed = rshift(p.speed, 1) end
    end
  end
end
tf0[5] = function(E, e)
  local s = e.u80
  if s == 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u80, e.timer = 1, 64
      if e.animationState > 1 then e.timer, e.subtimer = 128, 1 end
    end
  elseif s == 1 then fireballs(E, e, 16, false)
  elseif s == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.u80 = 1, 0; M.retarget(E, e) else shake(E, e) end
  end
  H.step(e)
end
tf0[6] = function(E, e)
  local s = e.u80
  if s == 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u80, e.timer = 1, 128
      if e.animationState > 1 then e.subtimer = 1 end
    end
  elseif s == 1 then fireballs(E, e, 32, true)
  elseif s == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.u80 = 1, 0; M.retarget(E, e) else shake(E, e) end
  end
  H.step(e)
end
tf0[7] = function(E, e)
  local f = E.field
  pause(f, e)
  if e.timer ~= 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      f:setFlag("room", 2, true)
      e.subtimer = 8
      H.step(e)
      return
    end
  else
    if e.subtimer ~= 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then H.setHp(e, 0); H.draw(e, false) end
    else
      -- GenericDeath
      e.defeated = true
      H.release(f, e)
      E:kill(e)
    end
    H.step(e)
    return
  end
  e.subtimer = band(e.subtimer + 1, 7)
  if e.subtimer == 0 then
    local t = band(R(E), 0x3F3F)
    H.fx(f, e.x + band(t, 0xFF) - 0x20, e.y + band(rshift(t, 8), 0xFF) - 0x20, FX_AURA_BASE)
    f:sound(SFX.S16E)
  end
  H.step(e)
end

-- the parts (types 1-5)
local function gone(e) e.u6d = bor(e.u6d or 0, 2); H.delete(e) end
local tf = { [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {} }
tf[1][0] = function(E, e)
  e.action, e.timer, e.u80, e.spritePriority = 1, 0, 0, 6
  anim(E, e, e.timer)
end
tf[1][1] = function(E, e)
  local pa = e.parent
  if dead(pa) then gone(e) return end
  e.x, e.y = pa.u7a, pa.u7e
  if pa.u74 == 0 then H.step(e) else H.step(e); H.step(e) end -- sub_080042BA(e, 2)
  if pa.action >= 5 then
    if e.timer == 0 then e.timer = 1; anim(E, e, 1) end
  else
    if e.timer ~= 0 then e.timer = 0; anim(E, e, 0) end
  end
  if pa.action ~= 3 then e.cz = pa.cz end
end
tf[2][0] = function(E, e)
  if e.type2 ~= 0 then
    e.action = 1
    e.spritePriority = e.type2 + 1
    anim(E, e, e.type2 + 4)
  else
    e.spritePriority = 4
    e.kids = { part(E, e, 2, 1), part(E, e, 2, 2) }
    e.action, e.timer = 1, 0
    e.subtimer = band(R(E), 0x7F) + 23
    e.u74 = 0
    anim(E, e, 0)
  end
end
tf[2][1] = function(E, e)
  local f = E.field
  local pa = e.parent
  if dead(pa) then gone(e) return end
  H.posRel(pa, e)
  if e.type2 == 2 or e.type2 == 1 then
    if e.type2 == 2 then
      local p = f.player
      local t = PUPIL[H.dirTo(e.x, e.y, p.x, p.y)]
      e.x, e.y = e.x + t[1], e.y + t[2]
    end
    if H.frameIndex(pa) ~= 2 then e.action = 2; H.draw(e, false) end
  else
    local s = e.u74
    if s == 0 then
      e.subtimer = band(e.subtimer - 1, 0xFF)
      if e.subtimer == 0 then
        e.subtimer = band(R(E), 0x7F) + 39
        if band(e.subtimer, 1) ~= 0 then e.u74 = 1; anim(E, e, 8) end
      end
    elseif s == 1 then
      if H.done(e) then e.u74 = 0; e.subtimer = band(R(E), 0x7F) + 23; anim(E, e, 0) end
    elseif s == 0x10 then
      anim(E, e, 7)
      e.u74, e.subtimer = 0x11, 80
    elseif s == 0x11 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then e.u74, e.subtimer = 1, 48; anim(E, e, 8) end
    end
  end
  H.step(e)
end
tf[2][2] = function(E, e)
  local pa = e.parent
  if dead(pa) then gone(e) return end
  H.posRel(pa, e)
  if H.frameIndex(pa) == 2 then e.action = 1; H.draw(e, true) end
end
tf[3][0] = function(E, e) e.action, e.spritePriority = 1, 4; anim(E, e, 0) end
tf[3][1] = function(E, e)
  local pa = e.parent
  if dead(pa) then gone(e) return end
  H.posRel(pa, e)
  H.step(e)
end
tf[4][0] = function(E, e)
  e.action, e.u80, e.timer, e.spritePriority = 1, 0, 10, 7
  H.draw(e, false)
  anim(E, e, 0)
end
tf[4][1] = function(E, e)
  local pa = e.parent
  if dead(pa) then gone(e) return end
  if pa.action ~= 5 then
    if e.u80 ~= 0 then e.u80 = 0; H.draw(e, false) end
  else
    if e.u80 == 0 then e.u80 = 1; H.draw(e, true) end
    e.timer = e.timer - 1
    if e.timer == 0 then e.timer = 10; E.field:sound(SFX.S149) end
  end
  H.posRel(pa, e)
  H.step(e)
end
tf[5][0] = function(E, e)
  if e.type2 ~= 0 then
    e.action, e.timer, e.spritePriority = 2, 10, 3
    anim(E, e, 2)
  else
    e.action = 1
    H.draw(e, false)
    e.spritePriority = 4
  end
end
tf[5][1] = function(E, e)
  local pa = e.parent
  if dead(pa) then gone(e) return end
  if e.u80 == 0 then
    if pa.action ~= 6 then return end
    e.u80 = 1
    H.draw(e, true)
    anim(E, e, 1)
  elseif e.u80 == 1 then
    if pa.action ~= 6 then e.u80 = 0; H.draw(e, false)
    else
      if H.done(e) then H.clearFlag(e, 0x80); part(E, e, e.type, 1) end
      e.timer = e.timer - 1
      if e.timer == 0 then e.timer = 10; E.field:sound(SFX.S149) end
      H.step(e)
    end
  end
  H.posRel(pa, e)
end
tf[5][2] = function(E, e)
  local pa = e.parent
  if dead(pa) then gone(e) return end
  if e.u80 == 0 then
    if pa.parent and pa.parent.action ~= 6 and H.done(e) then e.u80 = 1; anim(E, e, 3) end
  else
    if H.done(e) then H.delete(e) return end
  end
  H.posRel(pa, e)
  H.step(e)
end

function M.transfigured(E, e)
  local t = e.type
  if t == 0 then
    if e.action ~= 0 then
      e.u7a, e.u78 = e.u78, e.x
      e.u7e, e.u7c = e.u7c, e.y
      eyePuzzle(E, e)
    end
    tf0[e.action](E, e)
  elseif tf[t] and tf[t][e.action] then
    tf[t][e.action](E, e)
  end
end

-- ===========================================================================
-- VAATI_TRANSFIGURED_EYE
-- ===========================================================================
local function vaatiOf(e) if e.type ~= 0 then return e.parent and e.parent.parent end return e.parent end
local function eyeAnims(E, e, n) -- InitializeAnimation(self and the socket)
  anim(E, e, bor(lshift(e.type, 3), n))
  if e.type ~= 0 and e.parent then anim(E, e.parent, bor(lshift(e.parent.type, 3), n)) end
end
local function eyePal(E, e) -- sub_08045A28
  if e.u82 == 0 then H.step(e) end
  local fr = band(H.flags(e), 0x70)
  local function pal(st, id) e.u83 = st; H.palette(E, e, id) end
  if e.type == 0 then
    local o = EYE_POS[e.type2] or EYE_POS[0]
    H.posRel(e.parent, e, o[1], o[2] + 3)
    local s = e.u83
    if s == 0 then
      if fr == 0x20 then pal(1, 0x13E) elseif fr == 0 or fr == 0x40 then pal(2, 0x13F) end
    elseif s == 1 then
      if fr == 0x10 then pal(0, 0x13B) elseif fr == 0 then pal(2, 0x13F) end
    elseif s == 2 then
      if fr == 0x20 then pal(1, 0x13E) elseif fr == 0x10 then pal(0, 0x13B) elseif fr == 0x40 then pal(2, 0x13F) end
    elseif s == 3 then
      if fr == 0 then pal(2, 0x13F) end
    end
  else
    H.posRel(e.parent, e, 0, -1)
    local s = e.u83
    if s == 0 then
      if fr == 0x10 then pal(2, 0x13B) elseif fr == 0x20 then pal(1, 0x13E) end
    elseif s == 1 then
      if fr == 0 then pal(0, 0x13F) elseif fr == 0x10 then pal(2, 0x13B) end
    elseif s == 2 then
      if fr == 0 then pal(0, 0x13F) end
    end
  end
end
local function eyeCol(E, e, fl) -- VaatiTransfiguredEye_OnCollision
  local f = E.field
  if e.type == 0 or band(fl, 0x80) == 0 then return end
  local v = vaatiOf(e)
  local k = band(fl, 0x3F)
  if k == 0x0E or k == 0x15 then
    if e.u81 == 0 then
      e.action = 3
      e.u81 = 1
      eyeAnims(E, e, e.timer + 2)
    end
    f:sound(e.timer ~= 0 and SFX.S17A or SFX.GLOVES)
  else
    if H.hp(e) ~= 0xFF then
      H.setHp(e, 0xFF)
      if e.timer ~= 0 and v and v.u81 ~= 0 then
        v.u76 = bor(v.u76, lshift(1, e.type2))
        if e.u85 == 0 then e.u85 = 1; eyeAnims(E, e, 6) end
      end
    end
  end
end
M.eyeCol = eyeCol
local eyeActs = {}
eyeActs[0] = function(E, e)
  local f = E.field
  if f:messageActive() then return end
  e.action = 1
  H.draw(e, false)
  e.u80, e.u81, e.u85, e.subtimer, e.u82, e.u83 = 0, 0, 0, 0, 0x30, 0
  if e.type == 0 then
    local o = EYE_POS[e.type2] or EYE_POS[0]
    H.posRel(e.parent, e, o[1], o[2] + 3)
    local c = H.enemy(E, M, M.EYE, 1, e.x, e.y, e)
    c.timer, c.type2 = e.timer, e.type2
    e.child = c
  else
    e.spriteOY = 1
  end
  e.onCol = eyeCol
  anim(E, e, bor(lshift(e.type, 3), 1))
end
eyeActs[1] = function(E, e)
  eyePal(E, e)
  if e.u82 == 0 then
    if H.done(e) then
      if e.type ~= 0 then H.colOn(e) end
      e.action = 2
      anim(E, e, lshift(e.type, 3))
    end
  else
    e.u82 = e.u82 - 1
    if e.u82 == 0 then H.draw(e, true) end
  end
end
eyeActs[2] = function(E, e)
  eyePal(E, e)
  local v = vaatiOf(e)
  if v and v.action == 3 and v.u80 == 1 then
    e.action, e.subtimer = 4, 0
    if e.type ~= 0 then
      H.colOff(e)
      eyeAnims(E, e, e.timer ~= 0 and 5 or 4)
    end
  end
end
eyeActs[3] = function(E, e)
  eyePal(E, e)
  if H.done(e) then
    e.action = 2
    if e.type ~= 0 then
      if e.timer == 0 then e.hitType = 0x32
      else
        local v = vaatiOf(e)
        if v then v.u76 = bor(v.u76, lshift(1, e.type2)) end
        e.hitType = 0x31
      end
    end
  end
end
eyeActs[4] = function(E, e)
  eyePal(E, e)
  if e.subtimer == 0 then
    if H.done(e) then e.subtimer = 32 end
  else
    local v = vaatiOf(e)
    if v and v.animationState < 3 and v.action ~= 3 then
      e.action, e.subtimer, e.u81, e.u85 = 1, 0, 0, 0
      if e.type ~= 0 then e.hitType = 0x33 end
      e.timer = band(rshift(v.u75, e.type2), 1)
      anim(E, e, bor(lshift(e.type, 3), 1))
    end
  end
end
function M.eye(E, e)
  local v = vaatiOf(e)
  if not H.alive(v) or (e.type ~= 0 and not H.alive(e.parent)) then H.delete(e) return end
  eyeActs[e.action](E, e)
end

-- ===========================================================================
-- V2_PROJECTILE
-- ===========================================================================
local function onScreen(f, e)
  local cx, cy = f.camX or 0, f.camY or 0
  return e.x >= cx - 16 and e.x <= cx + 256 and e.y >= cy - 16 and e.y <= cy + 176
end
local function v2Col(E, e, fl) -- V2Projectile_OnCollision
  local f = E.field
  if band(fl, 0x80) == 0 then return end
  local k = band(fl, 0x3F)
  if e.type == 2 then
    if k == 0 then H.modHealth(f, -4) end
    if k == 0 or k == 3 or k == 0x14 then H.fx(f, e.x, e.y, FX_DEATH); H.delete(e) end
  elseif k == 0 then
    H.modHealth(f, -2)
    H.delete(e)
  end
end
M.v2Col = v2Col
function M.v2Update(E, e)
  local f = E.field
  local t, a = e.type, e.action
  if t == 0 then
    if a == 0 then
      e.action = 1
      e.timer = band(R(E), 0x3F) + 48
      e.subtimer = 0
      e.direction = band(R(E), 0x1F)
      e.spritePriority = 2
      e.onCol = v2Col
      anim(E, e, 0)
      f:sound(SFX.S14B)
    elseif a == 1 then
      e.timer = e.timer - 1
      if e.timer == 0 then e.action = 2; anim(E, e, 1) end
      H.move0(E, e) -- ProcessMovement3
      H.step(e)
    elseif a == 2 then
      H.step(e)
      if band(H.flags(e), 0x10) ~= 0 then H.clearFlag(e, 0x10); e.speed = 0 end
      if H.done(e) then H.delete(e) end
    end
  elseif t == 1 then
    if a == 0 then
      local rn = band(R(E), 0xFF)
      e.action = 1
      e.czv = -1
      e.cz = e.cz - 0xA0
      local x = 8 + (band(rn, 0x10) ~= 0 and 0x10 or 0xC0) + rshift(band(rn, 0xE0), 1)
      local y = 8 + lshift(band(rn, 0xF), 4)
      e.x, e.y = math.floor(x / 16) * 16 + 8, math.floor(y / 16) * 16 + 8 -- SnapToTile
      e.onCol = v2Col
      anim(E, e, 0)
      f:sound(SFX.S12D)
    elseif a == 1 then
      if not H.gravity(e, 24 / 256) then H.fx(f, e.x, e.y, FX_ROCK); H.delete(e) end
    end
  else
    if a == 0 then
      e.action, e.timer, e.spritePriority = 1, 96, 2
      if e.type2 == 0 then e.direction = lshift(band(R(E), 0xF), 1)
      else
        local tg = H.target(f)
        e.direction = tg and H.dirTo(e.x, e.y, tg.x, tg.y) or 0xFF
        H.palette(E, e, 0x13F)
      end
      e.onCol = v2Col
      anim(E, e, 0)
      f:sound(SFX.S193)
    elseif a == 1 then
      if not onScreen(f, e) then H.delete(e) return end
      H.linMove(e)
      H.step(e)
    end
  end
end

-- ===========================================================================
-- VAATI_EYES_MACRO (inside Vaati's arms)
-- ===========================================================================
local function tileOfs(f, q) -- gUnk_080B4488[q] -> dx, dy (in tiles)
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "vaati2_tileofs")
  local o = T and T.s16(0x080B4488 + q * 2)
  if not o then o = ({ [0] = -64, 1, 64, -1 })[q] end -- (an old cache: the 64-wide map's neighbours)
  local dy = math.floor((o + 32) / 64)
  return o - dy * 64, dy
end
M.tileOfs = tileOfs
function M.macroPick(E, e) -- sub_0802EFB8
  local f = E.field
  local rn = R(E)
  local u
  if band(rshift(rn, 16), 3) ~= 0 then u = band(rn, 0x18)
  else
    local p = f.player
    u = band(H.dirTo(p.x, p.y, e.x, e.y) + 4, 0x18)
  end
  local dx, dy = tileOfs(f, rshift(u, 3))
  local tx, ty = math.floor(e.x / 16) + dx, math.floor(e.y / 16) + dy
  if f.room:isSolid(tx * 16 + 8, ty * 16 + 8, 1) then
    e.direction = 0xFF
  else
    e.timer = band(rn, 3) + 1
    e.direction = band(u, 0x18)
    e.speed = MACRO_SPEED[band(rshift(rn, 24), 3)]
  end
end
function M.macroWalk(E, e) -- sub_0802F04C
  local ox, oy = math.floor(e.x), math.floor(e.y)
  if not H.move0(E, e) then M.macroPick(E, e) return end
  local q = rshift(e.direction, 3)
  local nx, ny = math.floor(e.x), math.floor(e.y)
  if q == 0 then
    if band(oy, 0xF) > 8 and band(ny, 0xF) < 9 then e.timer = e.timer - 1; oy = band(ny, 0xFFF0) + 8 end
  elseif q == 1 then
    if band(ox, 0xF) < 8 and band(nx, 0xF) >= 8 then e.timer = e.timer - 1; ox = band(nx, 0xFFF0) + 8 end
  elseif q == 2 then
    if band(oy, 0xF) < 8 and band(ny, 0xF) >= 8 then e.timer = e.timer - 1; oy = band(ny, 0xFFF0) + 8 end
  else
    if band(ox, 0xF) >= 9 and band(nx, 0xF) < 9 then e.timer = e.timer - 1; ox = band(nx, 0xFFF0) + 8 end
  end
  if e.timer ~= 0 then return end
  e.x, e.y = ox, oy
  M.macroPick(E, e)
end
local function macroCol(E, e, fl) -- VaatiEyesMacro_OnCollision
  local f = E.field
  if e.type == 0 then
    local rt = M.rt(f)
    local hp = H.hp(e)
    if hp == 0 then rt.f39 = band(rt.f39, bnot(lshift(1, rt.f3c + 2))) end
    if f.room.room == 0 then rt.f3a = hp else rt.f3b = hp end
    if e.u79 ~= hp then f:sound(SFX.S17A) end
    e.u79 = hp
  elseif e.type == 1 then
    if e.iframes > 0 then e.iframes = 0 end -- (iframes *= -1: no blink, no hit lock)
    if H.hp(e) ~= 0xFF then f:sound(SFX.BUTTON_DEPRESS) end
    H.setHp(e, 0xFF)
  end
end
M.macroCol = macroCol
local function armManager(E, eye) -- VAATI3_INSIDE_ARM_MANAGER
  local f = E.field
  local d = f._dungeon
  local rt = M.rt(f)
  local m = { id = M.MGR_ARM, action = 1, f20 = band((rt.f3d or 0) * 0x3C, 0xFFFF), parent = eye }
  local function tick(_, t)
    if t.action == 1 and dead(t.parent) then
      t.action = 2
      if t.f20 > 0x12D then t.f20 = 0x12D end
    end
    t.f20 = band(t.f20 - 1, 0xFFFF) -- sub_0805DBF0
    if t.f20 == 0 then
      if not t.exited then t.exited = true; f:startTransition(ARM_EXIT) end
    else
      if t.f20 == 0x78 then f:shake(120, 2)
      elseif t.f20 == 0xD2 then f:shake(90, 1)
      elseif t.f20 == 0x12C then f:shake(90, 0) end
      if t.f20 < 0x78 then if band(t.f20, 0xF) == 0 then f:sound(SFX.S126) end
      elseif t.f20 <= 0xD1 then if band(t.f20, 0x1F) == 0 then f:sound(SFX.S126) end
      elseif t.f20 <= 199 then if band(t.f20, 0x3F) == 0 then f:sound(SFX.S126) end end
    end
  end
  if d and d.track then
    return require("src.zelda.tmc.R26").ticker(d, tick, m)
  end
  m.extUpdate = tick
  return m
end
M.armManager = armManager
function M.macro(E, e)
  local f = E.field
  local t = e.type
  if t == 0 then
    if e.action == 0 then
      e.mgr = armManager(E, e)
      local c = H.enemy(E, M, M.MACRO, 2, e.x, e.y, e)
      e.child = c
      e.action = 1
      local rt = M.rt(f)
      H.setHp(e, f.room.room == 0 and rt.f3a or rt.f3b)
      e.u79 = H.hp(e)
      e.u78 = band(R(E), 0xFF)
      e.onCol = macroCol
      e.keepKb = true -- GenericKnockback
      M.macroPick(E, e)
      anim(E, e, 0)
      for i = 0, 6 do -- sub_0802EF58
        local d = H.enemy(E, M, M.MACRO, 1, e.x, e.y, e)
        d.type2, d.layer = i, 1
      end
    else
      if H.hp(e) == 0 then -- GenericDeath
        E:kill(e)
        return
      end
      M.macroWalk(E, e)
      H.step(e)
    end
  elseif t == 1 then
    if e.action == 0 then
      local c = H.enemy(E, M, M.MACRO, 3, e.x, e.y, e)
      e.child = c
      e.action = 1
      local rn = R(E)
      e.timer = band(rn, 3) + 1
      e.u78 = band(rshift(R(E), 8), 0xFF)
      e.direction = MACRO_DIRS[band(rshift(rn, 16), 3)]
      e.onCol = macroCol
      e.keepKb = true
      anim(E, e, 1)
    else
      if not H.alive(e.parent) then H.colOff(e); H.setHp(e, 0); E:kill(e) return end
      M.macroWalk(E, e)
      H.step(e)
    end
  elseif t == 2 then
    local pa = e.parent
    if not H.alive(pa) then H.delete(e) return end
    if e.action == 0 then e.action, e.animationState = 1, 0xFF end
    H.posRel(pa, e); e.spriteOX, e.spriteOY = pa.spriteOX, pa.spriteOY
    local p = f.player
    local u = band(H.dirTo(e.x, e.y, p.x, p.y) + 1, 0x1E)
    local fx, fy = MACRO_FRAMES[u], MACRO_FRAMES[u + 1]
    local fi = e.staticFrame or -1
    if fx ~= fi and fy ~= fi then e.staticFrame = fx end
    e.y = e.y + 1
    e.spriteOY = (e.spriteOY or 0) - 1
  elseif t == 3 then
    local pa = e.parent
    if not H.alive(pa) then H.delete(e) return end
    if e.action == 0 then e.action, e.staticFrame, e.spritePriority = 1, 0x11, 6 end
    H.posRel(pa, e); e.spriteOX, e.spriteOY = pa.spriteOX, pa.spriteOY
    e.cz = 0
  end
  if t < 2 and not e.deleted and not e.dying then -- sub_0802EF90
    e.cz = MACRO_BOB[band(rshift(e.u78, 3), 7)]
    e.u78 = band(e.u78 + 1, 0xFF)
  end
end

-- ===========================================================================
-- the VAATI3 managers (third fight; see the header)
-- ===========================================================================
local function vaati3Owns()
  for _, m in ipairs(require("src.zelda.tmc.R26").mods()) do
    if m ~= M and (m.OWNS_VAATI3_MANAGERS or (m.V and m.V.M_START == M.MGR_START and m.spawnManager)) then return true end
  end
  return false
end
local function vaati3Loaded()
  local ok = package.loaded["src.zelda.tmc.BossVaati3"]
  return type(ok) == "table"
end
function M.startManager(d, m)
  local f = d.field
  local rt = M.rt(f)
  local function tick(_, t)
    local p = f.player
    if t.type == 0 then
      if t.action == 1 then
        local dx, dy = math.floor(p.x) - 0x88, math.floor(p.y) - 0x40
        if dx * dx + dy * dy < 0x901 then
          t.action, t.subAction, t.timer = 2, 0, 120
          pause(f, t)
          f:spawn({ kind = 6, id = 0x64, paramA = 0, paramB = 0, paramC = 0, pool = 0, x = 0x88, y = 0x48, collision = 1 }) -- THUNDERBOLT
          f:bubble(p, 0, 8, -16)
          f:bgm(BGM_VAATI_WRATH)
        end
      elseif t.action == 2 then
        pause(f, t)
        p.animationState = 0
        if (p.z or 0) ~= 0 then
          if p.y < 0x48 then p.y = 0x48 end
        else
          t.timer = t.timer - 1
          if t.timer == 0 then
            t.action, t.timer = 3, 30
            f:message(0x164F, nil) -- TEXT_INDEX(TEXT_VAATI2, $4F)
          end
        end
      elseif t.action == 3 then
        if not f:messageActive() then
          if t.timer ~= 0 then t.timer = t.timer - 1
          else
            t.action = 4
            f.fadeLevel, f.fadeWhite = 0, true
            f:fade("out", true, 4)
            f:sound(SFX.EVAPORATE)
          end
        end
      elseif t.action == 4 then
        if not f:fadeActive() and not t.exited then
          t.exited = true
          f:setFlag("global", ZELDA_CHASE, false)
          H.release(f, t)
          f:startTransition(START_EXIT)
          t.deleted = true
        end
      end
    else
      if t.action == 1 and not f:fadeActive() then
        if t.child then t.child.subAction = 1 end
        t.deleted = true
      end
    end
  end
  local t = { id = M.MGR_START, type = m.type, action = 1, timer = 0 }
  if m.type == 0 then -- Vaati3StartManager_Type0_Init
    if not f:flag("local", 0x7B) then return true end
    rt.f38, rt.f39, rt.f3a, rt.f3b = 0, 0x0F, 0x20, 0x20
    f.save.vaatiTimer = 0x1194
  else -- Type1_Init
    if not vaati3Loaded() then return true end -- (VAATI_WRATH is BossVaati3's)
    local en = f:spawn({ kind = 3, id = M.VAATI_WRATH, paramA = 0, paramB = 0, paramC = 0, pool = 0, x = 0xB0, y = 0x48, collision = 1 })
    if band(rt.f38, 1) ~= 0 then return true end
    if not en then return true end
    t.child = en -- (SetPlayerControl(3): BossVaati3's fight takes Link's control)
    f:bgm(nil)
    f.fadeLevel, f.fadeWhite = 1, true
    f:fade("in", true, 4)
    f:sound(SFX.APPARATE)
  end
  return require("src.zelda.tmc.R26").ticker(d, tick, t)
end
function M.backgroundManager(d, m) -- Vaati3BackgroundManager_Main
  local f = d.field
  local rt = M.rt(f)
  return require("src.zelda.tmc.R26").ticker(d, function()
    rt.bg3x = (rt.bg3x or 0) - 0x4000 / 65536
    rt.bg3y = (rt.bg3y or 0) - 0x2000 / 65536
    f.vaatiBg3 = { x = (f.camX or 0) + math.floor(rt.bg3x), y = (f.camY or 0) + math.floor(rt.bg3y) }
  end, { id = M.MGR_BG })
end

-- ===========================================================================
-- R26 hooks
-- ===========================================================================
local function zero(e)
  for _, k in ipairs({ "u6d", "u74", "u75", "u76", "u77", "u78", "u79", "u7a", "u7c", "u7e", "u80", "u81", "u82", "u83",
                       "u84", "u85", "u86", "u87" }) do
    if e[k] == nil then e[k] = 0 end
  end
end
function M.spawnEnemy(E, dat, def)
  local id = dat.id
  if id == M.TRANSFIGURED and (dat.paramA or 0) == 0 then
    local e = H.enemy(E, M, id, 0, dat.x, dat.y, nil, true)
    H.home(E, e, dat)
    zero(e)
    e.onCol = bodyCol
    e.keepKb = true -- (bodyCol keeps it for Knockback1)
    e.boss2 = true
    return e
  elseif id == M.MACRO and (dat.paramA or 0) == 0 then
    local e = H.enemy(E, M, id, 0, dat.x, dat.y, nil, true)
    zero(e)
    return e
  end
  return nil
end
function M.spawnManager(d, m, dat)
  if (m.id == M.MGR_START or m.id == M.MGR_BG) and vaati3Owns() then return nil end
  if m.id == M.MGR_START then return M.startManager(d, m) and true end
  if m.id == M.MGR_BG then return M.backgroundManager(d, m) and true end
  return nil
end
function M.handles(e) return e.r26 == M end
function M.update(E, e)
  if e.deleted then return end
  zero(e)
  if e.vproj then
    if e.projId == M.P_V2 then M.v2Update(E, e) end
  elseif e.id == M.TRANSFIGURED then M.transfigured(E, e)
  elseif e.id == M.EYE then M.eye(E, e)
  elseif e.id == M.MACRO then M.macro(E, e) end
  e.cflags = nil
  H.syncZ(e)
end

return M
