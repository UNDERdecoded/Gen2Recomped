-- Round 26 (team B): Big Octo, OCTOROK_BOSS ($39), src/enemy/octorokBoss.c
-- ported whole (room $60:0E, Temple of Droplets: enemy list 8, spawned by the
-- room's fight manager), with octorokBossProjectile.c ($0F) and
-- octorokBossObject.c ($87).
--
-- PARTS (OctorokBoss_Init type 0 makes the others; heap = OctorokBossHeap):
--   the whole (type 0, animation 0, affine x / y scales unk_76 / unk_74, $A0
--   = 1.6x, angle word angle.HWORD: facing = (u8)(-angle.HI) ^ $80), four
--   legs (types 1-4, animation 1, sub_08036914 at -(angle.HI +
--   {40, 80, 176, 216}) at radius ((($10000 / unk_76) << 5) - $2000) / 2 +
--   $2200, own angle = angle.HI + {128, 0, 0, 128} + the wiggle timer),
--   the mouth (type 5, animation 2, at -(angle.HI + $80), radius ($10000 /
--   unk_74) * timer (28 .. 32 while it spits)), the tail end (type 6,
--   sprite of its own, animation 1 / 2 frozen) and four tail segments (type
--   7, animation 3).  The base segment (type2 = tailCount - 2) sits at
--   -angle.HI, radius ($10000 / unk_74) << 5; the chain (sub_080369D0 /
--   sub_08036AF0) hangs from it in steps of tailRadius (the tail end's
--   currentAttack, $80 = 8 px), each joint's angle within 4 ($10 frozen) of
--   the next; unfrozen it curls toward the front (angle ^ $80) and the tail
--   end wiggles (sub_08036998), frozen it sticks out stiffly behind.
--   sub_08036F60: the breathing (both scales +-1 between $9C and $A4).
-- THE FIGHT (bossPhase 0 / 2 / 4 unfrozen, 1 / 3 frozen; IS_FROZEN = bit 0):
--   Action1 subActions: 0 AimTowardsPlayer (turn by angularSpeed until Link
--   is 0..7 (frozen 0..31) steps right of the facing -- the u8 cast makes
--   the window one-sided -- then attack / WaitAnotherTurn), 1 WaitForTurn
--   (walk forward at $C0 for 70-100 frames; phase 0 / frozen: straight on),
--   2 ChargeAttack (phase 4: 60 frames, then $200 forward until a wall:
--   knockback $20 / $200, falling stones +60 frames, shake, SFX_158 /
--   SFX_14C), 3 WaitForAttack, 4 Attack (type2 0 start / 1 inhale (unk_74 to
--   $C0) / 2 exhale (back to unk_76) / 3 the attack, the mouth throbbing):
--     SPITROCK: OCTOROK_BOSS_PROJECTILE type 0 at the facing;
--     VACUUM: Link in a +-$10 cone within $F0 is pulled $280 a frame; within
--       $48 he is swallowed (unk_80 1: hidden, held $3800 out, SFX_ED), the
--       boss turns to face the room's centre, exhales and spits him out
--       (sub_080792BC: $400 for $30 frames, SFX_EF); suck particles (object
--       type 2) every 4 frames;
--     SMOKE: 255 frames darkening (ChangeLightLevel -1), smoke (object type
--       3) every 4 frames, SFX_124 every 8; object type 4 brings the light
--       back after $30C frames; while dark it attacks constantly;
--     FREEZE (frozen phases): projectile type 2 every 4 frames.
--   Patterns: phase 0 rocks only; unfrozen VACUUM ROCK VACUUM ROCK ROCK;
--   frozen VACUUM FREEZE VACUUM FREEZE VACUUM; phase 4: 1 in 4 (or dark) a
--   charge, else one of four phase-4 patterns (not the previous one).
--   Health per phase 3 / 1 / 3 / 1 / 3: only the rock knocked back with the
--   sword (or the shield) hurts it (health - 1, iframes $1E, knocked back
--   from phase 1 on); frozen, the Lantern's flame on the tail end (contact
--   7) lights a fuse (object type 0) that burns down the tail (object type 1
--   flames following it) and sets it BURNING: it races about at $200 for 120
--   frames, bouncing off walls (stones, shake), then health 0.
--   Health 0 -> OnDeath -> HIT: unfrozen it walks to the room's centre
--   ($108, $88), ice crystals (object type 5), 60 frames, phase + 1, frozen
--   graphics ($109, palette $F0 / parts $F3, hit type $61), the floor turns
--   to ice (object type 8: a growing diamond of gUnk_081238A0 tiles,
--   SFX_1A3); frozen (after the fire) the tail loses a segment (down to 3),
--   steam (object type 6), 120 frames, unfrozen graphics ($108, $EF, hit
--   type $5F), the ice melts back (RestorePrevTileEntity, SFX_WIND2).  The
--   tail regrows to $80, 150 frames, the next phase.
-- THE INTRO (action 3): Link hidden at (x, y - $A0), the camera on the boss;
--   60 frames, it turns round ($100 a frame) to face him, SFX_159, 60
--   frames, the camera back (scroll 1), Link walks in $1E frames, '!' at 30,
--   looks up, then down, BGM_BOSS_THEME, the fight.
-- THE DEATH (phase 4, health 0): object type 9 holds the camera $1E0
--   frames; it spins (angle.HI - 4 a frame) and shakes (sine offsets) for
--   120 frames, then explosions every 16 frames (centre and a leg), at 121
--   more the mouth's health 1 (legs grow, tail goes), SFX_BOSS_DIE, death.
--   The room's fight manager then sets its flag (the heart container /
--   the Water Element come from the room's lists, not from here).
-- SIMPLIFIED: the darkness is the field's fade level (not the cartridge's
--   BG / OBJ blend); Link frozen by the frost breath (PL_FROZEN) is not
--   ported (the breath only hurts him by the collision matrix); the Lantern
--   is another team's item: anything in the room with hurtType 7 (or
--   lanternFlame) touching the tail end, or B:lanternHit(e), lights it;
--   the ice floor's slipperiness is whatever the restored / ice tile types
--   give the port; draw order inside the boss is fixed (legs, mouth, body,
--   tail, tail end); the GenericKnockback slide uses the port's movement.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local B = {}
B.__index = B
B.ID, B.PROJ, B.OBJ = 0x39, 0x0F, 0x87
local WHOLE, MOUTH, TAIL_END, TAIL = 0, 5, 6, 7
local INIT, ACTION1, HIT, INTRO, BURNING = 0, 1, 2, 3, 4
local ATK_ROCK, ATK_VACUUM, ATK_SMOKE, ATK_FREEZE, NO_ATTACK, END_PAT = 0, 1, 2, 3, 4, 5
local ROT_CW, ROT_CCW, NO_ROT = 0, 1, 0xFF

B.ROM_RANGES = {
  octoIceTiles = { 0x081238A0, 0x081238A0 + 496 * 2 }, -- gUnk_081238A0 (octorokBossObject.c: the ice floor's metatiles, 31 x 16)
}

local SFX = { S159 = 0x159, S155 = 0x155, S158 = 0x158, S14C = 0x14C, S124 = 0x124, S1B5 = 0x1B5, S164 = 0x164,
              ED = 0xED, EF = 0xEF, HIT = 0x127, DIE = 0x128, DIVING = 0x163, ICE = 0x1B1, S1A3 = 0x1A3, WIND2 = 0xE8 }
B.SFX = SFX
local BGM_BOSS_THEME = 0x2E
local SPECIAL_FX, FX_ROCK, FX_GIANT_EXPLOSION3 = 0x0F, 0x04, 0x48

-- tables written out in octorokBoss.c / octorokBossObject.c
local PART_ANIM = { [0] = 0, 1, 1, 1, 1, 2, 1, 3 }             -- gUnk_080CF08C[type * 4]
local LEG_OFF = { 40, 80, 176, 216 }                           -- OctorokBoss_LegAngleOffset
local LEG_OFF2 = { 128, 0, 0, 128 }                            -- OctorokBoss_LegAngleOffset2
local HEALTH_PER_PHASE = { [0] = 3, 1, 3, 1, 3, 1, 3, 0 }       -- OctorokBoss_HealthPerPhase
local ATK_TIMER_W, ATK_TIMER_V = { 48, 96, 80, 32 }, { 5, 10, 15, 30 }
local TURN_W, TURN_V = { 48, 96, 80, 32 }, { 70, 80, 90, 100 }
local WAIT_W, WAIT_V = { 64, 128, 64 }, { 1, 2, 3 }
local P4 = { [0] = { 0, 4, 0, 2, 5 }, { 1, 4, 0, 2, 5 }, { 0, 4, 0, 4, 0, 5 }, { 1, 4, 0, 2, 5 } } -- OctorokBoss_Phase4AttackPatterns
local NORMAL_PAT = { [0] = 1, 0, 1, 0, 0 }                     -- OctorokBoss_NormalAttackPatterns
local FROZEN_PAT = { [0] = 1, 3, 1, 3, 1 }                     -- OctorokBoss_FrozenAttackPatterns
local FRAG_DIR = { [0] = 0, 224, 32 }                          -- gUnk_08129ADC
local FIRE_ORBIT = { [0] = 0, 4096, 16, 6144, 240, 7168, 32, 6144, 224, 5120, 48, 4096, 192, 4096, 208, 7168,
                     64, 4096, 192, 6144, 80, 7168, 176, 6144, 96, 5120, 160, 4096, 112, 4096, 144, 7168 } -- gUnk_0812384C
local CRYSTAL = { [0] = 0, 0, 32, 8192, 96, 8192, 160, 8704, 208, 8192 }                  -- gUnk_0812388C
B.PART_ANIM, B.HEALTH_PER_PHASE, B.P4, B.NORMAL_PAT, B.FROZEN_PAT = PART_ANIM, HEALTH_PER_PHASE, P4, NORMAL_PAT, FROZEN_PAT

-- gSineTable (256 steps a turn, $100 = 1)
local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
local function sin(a) return SIN[band(a, 0xFF)] end
local function cos(a) return SIN[band(a, 0xFF) + 0x40] end
local function u8(v) return band(v, 0xFF) end
local function s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end
local function s16(v) v = band(v, 0xFFFF) if v >= 32768 then return v - 65536 end return v end
local function hiA(w) return band(rshift(w, 8), 0xFF) end
local function setHi(w, v) return bor(band(w, 0xFF), lshift(band(v, 0xFF), 8)) end
local function trunc(v) if v < 0 then return -math.floor(-v) end return math.floor(v) end
B.sin, B.u8, B.s8 = sin, u8, s8

-- CalculateDirectionFromOffsets (0..255, 0 north, clockwise)
local function dir256(dx, dy)
  if dx == 0 and dy == 0 then return 0 end
  local a = math.atan2(dx, -dy)
  return band(math.floor(a / (2 * math.pi) * 256 + 0.5), 0xFF)
end
B.dir256 = dir256
local function dist(ax, ay, bx, by) -- sub_080041DC / 16
  local dx, dy = math.floor(bx) - math.floor(ax), math.floor(by) - math.floor(ay)
  return math.sqrt(dx * dx + dy * dy)
end

-- sub_08036914: place `pt` at angle / radius (8.8 px * 256) from `from`
local function polar(pt, from, angle, radius)
  local tx = s16(trunc(sin(angle) * radius / 256))
  local ty = s16(trunc(cos(angle) * radius / 256))
  pt.x = from.x + tx / 256
  pt.y = from.y - ty / 256
  pt.ox, pt.oy = from.ox or 0, from.oy or 0
end
B.polar = polar

-- GetRandomByWeight
local function byWeight(self, w)
  local r = band(self:rand(), 0xFF)
  for i = 1, #w do r = r - w[i]; if r < 0 then return i end end
  return #w
end

function B.new(field, enemies)
  return setmetatable({ field = field, en = enemies, A = field.assets }, B)
end
function B:rand() local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(self.field)) end
function B:sfx(id) self.field:sound(id) end
function B:frame() return self.field.frame or 0 end
function B:pal(id) return self.A:objPalette(id, self.field.room.atlas and self.field.room.atlas.palettes) end

-- ---------------------------------------------------------------------------
-- parts
-- ---------------------------------------------------------------------------
function B:part(type, x, y)
  local d = self.en:def(B.ID, type) or {}
  local pt = { type = type, type2 = 0, x = x, y = y, ox = 0, oy = 0, sprite = d.sprite, def = d, anim = Anim.new(),
               gfx = Assets.gfxSource("enemy", d.gfx or 0), palId = d.palette or 0xEF, draw = true,
               tm = 0, timer = 0, subtimer = 0, u74 = 0x100, u76 = 0x100, angle = 0, health = d.health or 3,
               hitbox = d.hitbox or { x = 0, y = 0, w = 8, h = 8 }, hitType = d.damageType or 0, collide = (d.collision or 0) ~= 0,
               iframes = 0 }
  pt.palette = self:pal(pt.palId)
  return pt
end
function B:anim(pt, idx, force)
  if not force and pt.animIndex == idx then return end
  pt.animIndex, pt.objAnim = idx, idx -- (objAnim: Field keeps a literalAnim entity's index)
  if pt.sprite then pt.anim:set(self.A:sprite(pt.sprite), idx, true) end
end
function B:setPal(pt, id)
  if pt.palId == id then return end
  pt.palId = id
  pt.palette = self:pal(id)
end

function B:spawn(dat, def)
  local f = self.field
  if (dat.paramA or 0) ~= 0 then return false end -- the parts are made by type 0
  self.T = require("src.zelda.tmc.ExtractR26").tables(f, "octoIceTiles")
  local e = {
    kind = 3, id = dat.id, form = 0, x = dat.x, y = dat.y, z = 0, boss = true, enemy = true, impl = self, octoBoss = true,
    health = (def and def.health) or 3, hitType = (def and def.damageType) or 0x5F, def = def or {},
    hitbox = (def and def.hitbox) or { x = 0, y = 0, w = 40, h = 40 }, anim = Anim.new(), literalAnim = true,
    field82 = 0, interactType = 0, iframes = 0, kbt = 0, noHit = true, layer = 1,
    sprite = def and def.sprite, gfx = Assets.gfxSource("enemy", (def and def.gfx) or 0x108), palId = (def and def.palette) or 0xEF,
    -- OctorokBossEntity
    action = INTRO, subAction = 0, type2 = 0, tm = 0x3C, timer = 1, subtimer = 0, u74 = 0xA0, u76 = 0xA0, angle = 0,
    phase = 0, attack = 0, nextIdx = 0, waitTurns = 0, u80 = 0, p4 = 0, angSpd = 0, speed = 0, direction = 0,
    kbDur = 0, kbSpd = 0, kbDir = 0, collide = true, ox = 0, oy = 0, light = 0x100,
  }
  e.palette = self:pal(e.palId)
  local h = { unk0 = 2, tailCount = 5, f2 = 0, target = 0, rot = NO_ROT, prevPat = 0, stones = 0, f7 = 0, tails = {}, legs = {} }
  e.h = h
  self:anim(e, PART_ANIM[0])
  for leg = 1, 4 do
    local l = self:part(leg, e.x, e.y)
    l.timer, l.tm = 0x10, 0
    l.subtimer = band(leg, 2) == 0 and 2 or -2
    l.u74 = 0x100
    l.u76 = band(leg, 1) == 0 and -0x100 or 0x100
    self:anim(l, PART_ANIM[leg])
    h.legs[leg] = l
  end
  local m = self:part(MOUTH, e.x, e.y)
  m.u74, m.u76, m.tm = 0x100, 0x100, 0x1C
  self:anim(m, PART_ANIM[MOUTH])
  h.mouth = m
  local te = self:part(TAIL_END, e.x, e.y)
  te.u74, te.u76, te.tm, te.timer, te.subtimer = 0x100, 0x100, 0, 0x10, 1
  te.radius = 0x80 -- GET_TAIL_RADIUS (currentAttack)
  self:anim(te, PART_ANIM[TAIL_END], true)
  h.tails[0] = te
  for t = 0, 3 do
    local s = self:part(TAIL, e.x, e.y)
    s.type2 = t
    self:anim(s, PART_ANIM[TAIL])
    h.tails[t + 1] = s
  end
  -- the intro: Link hidden above it, the camera on the boss
  local p = f.player
  p.x, p.y = e.x, e.y - 0xA0
  e.hideLink = true
  self.camTarget = e
  self:layout(e)
  return e
end

-- ---------------------------------------------------------------------------
-- Link (PausePlayer, hidden, carried)
-- ---------------------------------------------------------------------------
function B:pausePlayer() self.pauseReq = true end
function B:linkState(e)
  local f = self.field
  local p = f.player
  if self.pauseReq or self.walkIn or self.fling then
    if p.state ~= "ext" or not p.octoPause then
      p.state, p.octoPause = "ext", true
      p.jar = nil
    end
    local me = self
    p.extUpdate = function(pl) me:linkExt(pl) end
  elseif p.octoPause then
    p.octoPause = nil
    if p.state == "ext" then p.state, p.extUpdate, p.animId = "normal", nil, -1 end
  end
  local hide = (e.hideLink or e.u80 ~= 0) and not e.dead
  if hide then p.hidden, self.hidOwn = true, true
  elseif self.hidOwn then p.hidden, self.hidOwn = nil, nil end
  if e.u80 ~= 0 then p.invuln = math.max(p.invuln or 0, 2) end -- ENT_COLLIDE off while inside
  self.pauseReq = false
end
function B:linkExt(p)
  if self.walkIn and self.walkIn > 0 then -- sub_08078AC0($1E): PLAYER_ROOM_EXIT walks on
    self.walkIn = self.walkIn - 1
    local dx, dy = math.sin(p.direction * math.pi / 16), -math.cos(p.direction * math.pi / 16)
    p:moveBy(dx, dy)
    p:setAnim(p:animFor("walk"))
    p.anim:update(1)
    if self.walkIn == 0 then self.walkIn = nil end
    return
  end
  if self.fling then -- sub_080792BC: PLAYER_08072454 ($400 for $30 frames)
    local fl = self.fling
    fl.t = fl.t - 1
    p:moveBy(math.sin(fl.dir * math.pi / 16) * 4, -math.cos(fl.dir * math.pi / 16) * 4)
    if fl.t <= 0 then self.fling = nil end
    return
  end
  p:setAnim(p:animFor("idle"))
  p.anim:update(1)
end

-- ---------------------------------------------------------------------------
-- movement
-- ---------------------------------------------------------------------------
local function solidAt(room, x, y) return room:isSolid(x, y, 1) end
-- ProcessMovement0 with the hitbox; returns the collision flags {x, y}
function B:move(ent, dir32, speed)
  local room = self.field.room
  local a = (dir32 % 32) * math.pi / 16
  local vx, vy = math.sin(a) * speed / 256, -math.cos(a) * speed / 256
  local hb = ent.hitbox or { x = 0, y = 0, w = 8, h = 8 }
  local hw, hh = math.max(2, hb.w), math.max(2, hb.h)
  local function box(x, y)
    local cx, cy = x + (hb.x or 0), y + (hb.y or 0)
    return solidAt(room, cx - hw, cy - hh) or solidAt(room, cx + hw - 1, cy - hh) or solidAt(room, cx - hw, cy + hh - 1)
        or solidAt(room, cx + hw - 1, cy + hh - 1) or solidAt(room, cx, cy - hh) or solidAt(room, cx, cy + hh - 1)
        or solidAt(room, cx - hw, cy) or solidAt(room, cx + hw - 1, cy)
  end
  local cx, cy = false, false
  if math.abs(vx) > 1e-6 then
    if box(ent.x + vx, ent.y) then cx = true else ent.x = ent.x + vx end
  end
  if math.abs(vy) > 1e-6 then
    if box(ent.x, ent.y + vy) then cy = true else ent.y = ent.y + vy end
  end
  return cx, cy
end

-- ---------------------------------------------------------------------------
-- the parts each frame (OctorokBoss_Action1 by type)
-- ---------------------------------------------------------------------------
-- sub_08036998: the wiggle timer between +-timer
local function wiggle(pt)
  pt.tm = u8(pt.tm + pt.subtimer)
  if pt.subtimer < 0 then
    if s8(pt.tm) < -pt.timer then pt.subtimer = -pt.subtimer end
  elseif s8(pt.tm) > pt.timer then pt.subtimer = -pt.subtimer end
end
B.wiggle = wiggle

-- sub_080369D0: the tail chain, unfrozen
function B:tailChain(e, radius, spd)
  local h = e.h
  local T, n = h.tails, h.tailCount
  T[0].angHi = u8(T[n - 1].angHi + T[0].tm)
  for i = 0, n - 2 do
    if T[i].angHi ~= T[i + 1].angHi then
      local d = s8(T[i + 1].angHi - T[i].angHi)
      if d >= 1 then
        if d > spd then T[i + 1].angHi = u8(T[i].angHi + spd) end
      elseif d < -spd then T[i + 1].angHi = u8(T[i].angHi - spd) end
    end
  end
  for i = n - 1, 1, -1 do
    local a = bxor(T[i - 1].angHi, 0x80)
    local tx = trunc(sin(a) * radius * 16 / 256)
    local ty = trunc(cos(a) * radius * 16 / 256)
    T[i - 1].x = T[i].x + tx / 256
    T[i - 1].y = T[i].y - ty / 256
  end
end
-- sub_08036AF0: the tail chain, frozen (angleSpeed $10)
function B:tailChainFrozen(e, radius, spd)
  local h = e.h
  local T, n = h.tails, h.tailCount
  for i = n - 1, 1, -1 do
    if T[i - 1].angHi ~= T[i].angHi then
      local d = s8(T[i].angHi - T[i - 1].angHi)
      if d >= 1 then
        if d > spd then T[i - 1].angHi = u8(T[i].angHi - spd) end
      elseif d < -spd then T[i - 1].angHi = u8(T[i].angHi + spd) end
    end
    local a = T[i - 1].angHi
    local tx = s16(trunc(sin(a) * radius * 16 / 256))
    local ty = s16(trunc(cos(a) * radius * 16 / 256))
    T[i - 1].x = T[i].x + tx / 256
    T[i - 1].y = T[i].y - ty / 256
  end
end

local function frozen(e) return band(e.phase, 1) ~= 0 end
B.frozen = frozen

function B:legTick(e, l)
  local h = e.h
  l.iframes = e.iframes
  if h.mouth.health == 1 then
    if l.u76 < 0 then l.u76 = l.u76 - 4 else l.u76 = l.u76 + 4 end
    if l.u74 < 0 then l.u74 = l.u74 - 4 else l.u74 = l.u74 + 4 end
  end
  if h.f2 ~= 0 or e.action == INTRO or u8(e.subAction - 3) > 1 then
    if l.subtimer < 0 then l.subtimer = -h.unk0 else l.subtimer = h.unk0 end
    wiggle(l)
  end
  local radius = math.floor(0x10000 / e.u76)
  radius = rshift(lshift(radius, 0xD), 8)
  radius = radius - 0x2000
  if h.mouth.health == 1 then radius = radius + 0x2200 else radius = math.floor(radius / 2) + 0x2200 end
  local angle = u8(-(hiA(e.angle) + LEG_OFF[l.type]))
  polar(l, e, angle, radius)
  l.angle = setHi(l.angle, hiA(e.angle) + LEG_OFF2[l.type] + l.tm)
end

function B:mouthTick(e, m)
  m.iframes = e.iframes
  if m.health == 1 then m.health = 0; m.dead = true; return end
  if e.subAction ~= 4 and m.health ~= 1 then
    if m.tm > 0x1C then m.tm = m.tm - 1 end
    if m.u76 > 0x100 then m.u76 = m.u76 - 1 else m.u76 = 0x100 end
  end
  local radius = math.floor(0x10000 / e.u74) * m.tm
  local angle = u8(-(hiA(e.angle) + 0x80))
  polar(m, e, angle, radius)
  m.angle = setHi(m.angle, hiA(e.angle))
  self:staticPush(m)
end

function B:tailTick(e, s)
  local h = e.h
  s.iframes = e.iframes
  if h.mouth.health < 2 or h.tailCount - 2 < s.type2 then s.gone = true return end
  if h.tailCount - 2 == s.type2 then
    local radius = lshift(math.floor(0x10000 / e.u74), 5)
    polar(s, e, u8(-hiA(e.angle)), radius)
    s.angHi = u8(-hiA(e.angle))
  end
  if not frozen(e) then s.draw = true end
end

function B:tailEndTick(e, te)
  local h = e.h
  te.iframes = e.iframes
  if h.mouth.health < 2 then te.gone = true return end
  te.anim:update(1)
  if frozen(e) then
    self:tailChainFrozen(e, te.radius, 0x10)
    if te.collide and (te.contact == 7 or self:flameNear(te)) then -- (contactFlags & $7F) == 7: the Lantern
      te.collide = false
      self:object(0, 0, te.x, te.y, e)
    end
  else
    te.collide = true
    te.draw = true
    wiggle(te)
    self:tailChain(e, te.radius, 4)
  end
  te.contact = nil
end

-- the Lantern's flame near the tail end (another team's item: anything with
-- hurtType 7, or a lanternFlame flag)
function B:flameNear(te)
  for _, o in ipairs(self.field.entities) do
    if not o.deleted and (o.hurtType == 7 or o.lanternFlame) and math.abs(o.x - te.x) < 16 and math.abs(o.y - te.y) < 16 then return true end
  end
  return false
end
function B:lanternHit(e)
  local te = e.h.tails[0]
  if te then te.contact = 7 end
end

-- the angles of every tail joint start from the part's own angle.HI
local function initTailAngles(e)
  for i = 0, 4 do local t = e.h.tails[i]; if t then t.angHi = t.angHi or u8(-hiA(e.angle)) end end
end

function B:layout(e)
  initTailAngles(e)
  local h = e.h
  for leg = 1, 4 do self:legTickPos(e, h.legs[leg]) end
end
-- the legs' first placement (no wiggle)
function B:legTickPos(e, l)
  local radius = math.floor(0x10000 / e.u76)
  radius = rshift(lshift(radius, 0xD), 8) - 0x2000
  radius = math.floor(radius / 2) + 0x2200
  polar(l, e, u8(-(hiA(e.angle) + LEG_OFF[l.type])), radius)
end

-- ---------------------------------------------------------------------------
-- the whole
-- ---------------------------------------------------------------------------
-- sub_08036F60: the breathing
function B:breathe(e)
  if e.subAction ~= 4 and not frozen(e) then
    e.u76 = e.u76 + s8(e.timer)
    e.u74 = e.u74 + s8(e.timer)
    if e.u76 < 0x9C then e.timer = 1 elseif e.u76 > 0xA4 then e.timer = 255 end
  end
end
function B:stepSound(e, mask)
  if band(self:frame(), mask) == 0 then self:sfx(frozen(e) and SFX.ICE or SFX.DIVING) end
end
local function facing(e) return bxor(u8(-hiA(e.angle)), 0x80) end
B.facing = facing

function B:setAttackTimer(e) -- OctorokBoss_SetAttackTimer
  if e.phase == 4 and e.p4 ~= 0xFF then
    e.subAction, e.type2, e.u80 = 4, 0, 0
    local pat = P4[e.p4]
    e.attack = pat[e.nextIdx + 1] or END_PAT
    e.nextIdx = e.nextIdx + 1
    if e.attack ~= END_PAT then return end
    e.p4 = 0xFF
  end
  e.subAction = 3
  if frozen(e) then
    if e.phase == 1 then e.tm = 30 elseif e.phase == 3 then e.tm = 10 end
  elseif e.light ~= 0x100 then e.tm = 1
  else e.tm = ATK_TIMER_V[byWeight(self, ATK_TIMER_W)] end
end
function B:reset0(e) -- OctorokBoss_ResetToSubAction0
  e.angSpd = 0x100
  e.h.unk0 = 2
  e.h.rot = NO_ROT
  e.subAction = 0
end
function B:waitAnotherTurn(e)
  e.subAction, e.speed = 1, 0xC0
  e.h.unk0 = 1
  e.tm = TURN_V[byWeight(self, TURN_W)]
end
function B:setWaitTurns(e)
  e.p4 = 0xFF
  if not frozen(e) then
    if e.light ~= 0x100 then e.waitTurns = 0 else e.waitTurns = WAIT_V[byWeight(self, WAIT_W)] end
  else e.waitTurns = 0 end
  self:reset0(e)
end
function B:startAttack(e) -- OctorokBoss_StartRegularAttack
  e.subAction, e.type2, e.p4, e.u80 = 4, 0, 0xFF, 0
  e.h.f2 = 0
  if e.phase == 0 then e.attack = ATK_ROCK return end
  if e.phase == 4 then
    if band(self:rand(), 3) == 0 or e.light ~= 0x100 then
      e.subAction, e.speed, e.tm = 2, 0x200, 60
      e.h.unk0 = 4
      self:sfx(SFX.S159)
      return
    end
    e.nextIdx = 0
    local r = band(self:rand(), 3)
    if e.h.prevPat ~= r then e.p4 = r else e.p4 = band(e.h.prevPat + 1, 3) end
    e.h.prevPat = e.p4
    self:setAttackTimer(e)
    return
  end
  local pat = frozen(e) and FROZEN_PAT or NORMAL_PAT
  e.attack = pat[e.nextIdx]
  e.nextIdx = e.nextIdx + 1
  if e.nextIdx > 4 then e.nextIdx = 0 end
end

function B:changePalette(e, id) -- OctorokBoss_ChangePalette
  local h = e.h
  self:setPal(h.mouth, id)
  for i = 1, 4 do self:setPal(h.legs[i], id) end
  for i = h.tailCount - 1, 1, -1 do self:setPal(h.tails[i], id) end
end

-- the subActions of Action1 (the whole)
function B:aim(e) -- OctorokBoss_Action1_AimTowardsPlayer
  local p = self.field.player
  local tmp1 = u8(dir256(p.x - e.x, p.y - e.y) - facing(e))
  local tmp2 = frozen(e) and 32 or 8
  if tmp1 > -tmp2 and tmp1 < tmp2 then
    if e.p4 ~= 0xFF then self:setAttackTimer(e) return end
    if e.waitTurns == 0 then self:startAttack(e) else self:waitAnotherTurn(e) end
  else
    if tmp1 > 0x80 then e.angle = band(e.angle + e.angSpd, 0xFFFF); e.h.rot = ROT_CW
    else e.angle = band(e.angle - e.angSpd, 0xFFFF); e.h.rot = ROT_CCW end
  end
  e.direction = rshift(facing(e), 3)
  if frozen(e) and e.angSpd < 0x280 then
    if e.phase == 1 then e.angSpd = e.angSpd + 1 elseif e.phase == 3 then e.angSpd = e.angSpd + 2 end
  end
  self:stepSound(e, 0x1F)
end
function B:waitTurn(e) -- OctorokBoss_Action1_WaitForTurn
  local was = e.tm
  e.tm = u8(e.tm - 1)
  if was == 0 or e.phase == 0 or frozen(e) then
    e.waitTurns = u8(e.waitTurns - 1)
    self:reset0(e)
  else
    local cx, cy = self:move(e, e.direction, e.speed)
    if cx or cy then e.tm = 0 end
  end
  self:stepSound(e, 0x1F)
end
function B:waitAttack(e)
  local was = e.tm
  e.tm = u8(e.tm - 1)
  if was == 0 then self:setWaitTurns(e) end
end
function B:charge(e) -- OctorokBoss_Action1_ChargeAttack
  if e.tm == 0 then
    local cx, cy = self:move(e, e.direction, e.speed)
    local kb = false
    if e.direction ~= 0 and e.direction ~= 0x10 then kb = cx end
    if e.direction ~= 0x18 and e.direction ~= 8 and cy then kb = true end
    if kb then
      e.kbDur, e.kbSpd, e.kbDir = 0x20, 0x200, bxor(e.direction, 0x10)
      e.h.stones = u8(e.h.stones + 60)
      self:setAttackTimer(e)
      self.field:shake(60, 0)
      self:sfx(SFX.S158); self:sfx(SFX.S14C)
    end
  else e.tm = e.tm - 1 end
  self:stepSound(e, 0xF)
end

function B:attackStep(e) -- OctorokBoss_Action1_Attack
  local h = e.h
  local t2 = e.type2
  if t2 == 0 then
    if e.attack == NO_ATTACK then self:reset0(e)
    else
      e.angSpd, e.type2 = 0x100, 1
      e.tm = frozen(e) and 0 or 22
      self:sfx(SFX.S155)
    end
  elseif t2 == 1 then
    if e.u74 < 0xC0 then e.u74 = e.u74 + 1
    else
      local was = e.tm
      e.tm = u8(e.tm - 1)
      if was == 0 then
        if e.attack == ATK_VACUUM then
          e.type2 = 3
          e.tm = frozen(e) and 60 or 120
          h.target = hiA(e.angle)
        else
          e.type2, e.tm = 2, 45
        end
        self:sfx(SFX.S155)
      end
    end
  elseif t2 == 2 then
    if e.tm == 0 then
      if e.u76 < e.u74 then e.u74 = e.u74 - 8
      else
        e.type2, e.u74 = 3, e.u76
        if e.attack ~= ATK_SMOKE then e.tm = 60
        else e.tm = 0; self:object(4, 0, e.x, e.y, e) end
      end
    else e.tm = e.tm - 1 end
  else
    local m = h.mouth
    if band(self:frame(), 2) ~= 0 then m.u76 = m.u76 - 8
    else m.u76 = m.u76 + 8; if m.u76 > 0x180 then m.u76 = 0x180 end end
    if e.attack ~= ATK_VACUUM and m.tm < 0x20 then m.tm = m.tm + 1; m.u76 = m.u76 + 8 end
    if e.attack == ATK_ROCK then self:spitRock(e)
    elseif e.attack == ATK_VACUUM then self:vacuum(e)
    elseif e.attack == ATK_SMOKE then self:smoke(e)
    elseif e.attack == ATK_FREEZE then self:freeze(e) end
  end
  -- sub_08036FE4: the frozen spin runs down
  if frozen(e) and e.u80 == 0 and e.angSpd ~= 0 then
    if h.rot ~= NO_ROT then
      if h.rot == ROT_CW then e.angle = band(e.angle + e.angSpd, 0xFFFF) else e.angle = band(e.angle - e.angSpd, 0xFFFF) end
    end
    if e.phase == 1 then e.angSpd = e.angSpd - 1 elseif e.phase == 3 then e.angSpd = e.angSpd - 2 end
    if e.angSpd < 0 then e.angSpd = 0 end
  end
  if e.u80 ~= 0 then -- Link inside: held at the mouth
    local p = self.field.player
    self:pausePlayer()
    p.layer = 2
    local tx = s16(trunc(sin(u8(-(hiA(e.angle) + 0x80))) * 0x3800 / 256))
    local ty = s16(trunc(cos(u8(-(hiA(e.angle) + 0x80))) * 0x3800 / 256))
    p.x, p.y = e.x + tx / 256, e.y - ty / 256
  end
end

function B:spitRock(e)
  self:projectile(e, 0, facing(e))
  e.h.mouth.tm = e.h.mouth.tm + 1
  self:setAttackTimer(e)
end

function B:vacuum(e) -- OctorokBoss_ExecuteAttackVacuum
  local f = self.field
  local p = f.player
  local h = e.h
  if e.u80 == 0 then
    e.direction = dir256(p.x - e.x, p.y - e.y)
    local tmp = math.abs(u8(-(hiA(e.angle) + 0x80)) - e.direction)
    if tmp < 0x10 and dist(e.x, e.y, p.x, p.y) <= 0xF0 then
      if p.octoFrozen then p.octoFrozen = nil -- PL_FROZEN (not ported)
      elseif p.state ~= "dead" and not p.hidden then
        local a = u8(-hiA(e.angle))
        p:moveBy(sin(a) * 0x280 / 256 / 256, -cos(a) * 0x280 / 256 / 256)
        if dist(e.x, e.y, p.x, p.y) <= 0x48 then
          e.u80, e.tm = 1, 2
          h.target = dir256(0x108 - e.x, 0x88 - e.y)
          h.target = u8(-(h.target + 0x80))
          if f.objects and f:objects().dropCarried and p.state == "carry" then f:objects():dropCarried(p) end
          self:sfx(SFX.ED)
        end
      end
    end
    if band(self:frame(), 3) == 0 then self:object(2, 0, e.x, e.y, e) end
  else
    if frozen(e) or h.target == hiA(e.angle) then
      if e.u80 == 1 then
        e.u80, e.type2, e.tm, e.angSpd = 2, 2, 45, 0x100
        h.f2 = 0
        return
      end
      e.u80, e.angSpd = 0, 0x100
      h.mouth.tm = h.mouth.tm + 1
      p.hidden, p.layer = nil, 1
      self.fling = { dir = rshift(u8(-(hiA(e.angle) + 0x80)), 3), t = 0x30 }
      self:setAttackTimer(e)
      self:sfx(SFX.EF)
      return
    end
    e.tm = 2
  end
  if e.tm == 0 then
    e.u74, e.type2 = e.u76, 0
    self:setAttackTimer(e)
  else
    e.tm = e.tm - 1
    if not frozen(e) then
      if h.target ~= hiA(e.angle) then
        h.f2 = 1
        if u8(h.target - hiA(e.angle)) > 0x80 then e.angle = band(e.angle - e.angSpd, 0xFFFF)
        else e.angle = band(e.angle + e.angSpd, 0xFFFF) end
      else h.f2 = 0 end
    end
  end
end

function B:smoke(e) -- OctorokBoss_ExecuteAttackSmoke
  if e.tm == 0xFF then
    e.type2 = 0
    self:setAttackTimer(e)
    e.tm = 120
  else
    e.tm = e.tm + 1
    e.light = math.max(0, e.light - 1) -- ChangeLightLevel(-1)
    if band(self:frame(), 3) == 0 then
      if band(self:frame(), 7) == 0 then self:sfx(SFX.S124) end
      self:object(3, 0, e.x, e.y, e)
    end
  end
end

function B:freeze(e) -- OctorokBoss_ExecuteAttackFreeze
  if e.tm == 0 then
    e.h.f2 = 0
    self:setAttackTimer(e)
  else
    e.tm = e.tm - 1
    if band(self:frame(), 3) == 0 then self:projectile(e, 2, facing(e)) end
  end
end

function B:action1(e)
  local h = e.h
  self:staticPush(e)
  self:breathe(e)
  if h.stones ~= 0 then
    h.stones = h.stones - 1
    if band(self:frame(), 3) == 0 then self:projectile(e, 3, 0) end
  end
  local sa = e.subAction
  if sa == 0 then self:aim(e)
  elseif sa == 1 then self:waitTurn(e)
  elseif sa == 2 then self:charge(e)
  elseif sa == 3 then self:waitAttack(e)
  else self:attackStep(e) end
end

-- OctorokBoss_Burning
function B:burning(e)
  local h = e.h
  local sa = e.subAction
  if sa == 0 then
    e.subAction, e.speed = 1, 0x200
    e.direction = rshift(facing(e), 3)
    e.tm, e.angSpd = 120, 0x180
    h.unk0 = 4
    self:release(e)
    sa = 1
  end
  if sa == 1 then
    local cx, cy = self:move(e, e.direction, e.speed)
    if cx or cy then
      e.subAction = 2
      h.target = hiA(e.angle)
      if cx then h.target = u8(-h.target) end
      if cy then h.target = bxor(u8(-h.target), 0x80) end
      e.kbDur, e.kbSpd, e.kbDir = 0x18, 0x200, bxor(e.direction, 0x10)
      h.stones = u8(h.stones + 30)
      self.field:shake(30, 0)
      self:sfx(SFX.S158); self:sfx(SFX.S14C)
    end
    local was = e.tm
    e.tm = u8(e.tm - 1)
    if was == 0 then e.health = 0 end
    if band(self:frame(), 0x1F) == 0 then self:sfx(SFX.S159) end
  elseif sa == 2 then
    if u8(h.target - hiA(e.angle) + 7) < 0xF then
      e.subAction = 1
      e.direction = rshift(facing(e), 3)
      self:move(e, e.direction, e.speed)
    else
      if u8(h.target - hiA(e.angle)) > 0x80 then e.angle = band(e.angle - e.angSpd, 0xFFFF)
      else e.angle = band(e.angle + e.angSpd, 0xFFFF) end
    end
  end
  if h.stones ~= 0 then
    h.stones = h.stones - 1
    if band(self:frame(), 7) == 0 then self:projectile(e, 3, 0) end
  end
end

-- sub_080368D8: let Link go, scales back to $A0
function B:release(e)
  if e.u80 ~= 0 then
    local p = self.field.player
    p.hidden, p.layer = nil, 1
    e.u80 = 0
  end
  e.u76, e.u74 = 0xA0, 0xA0
end

-- ---------------------------------------------------------------------------
-- HIT (health 0)
-- ---------------------------------------------------------------------------
function B:onDeath(e) -- OctorokBoss_OnDeath (type 0)
  e.action, e.subAction = HIT, 0
  e.kbDur = 0
  e.health = 1
  e.collide = false
  self:release(e)
end
function B:hit(e)
  local f = self.field
  local h = e.h
  if e.phase == 0 then
    if e.subAction ~= 3 then
      self.camTarget = h.tails[0]
      h.f7 = 0x5A
      self:pausePlayer()
    end
  elseif h.f7 ~= 0 then
    h.f7 = h.f7 - 1
    self:pausePlayer()
  end
  local sa = e.subAction
  if sa == 0 then
    e.u76, e.u74 = 0xA0, 0xA0
    h.stones = 0
    if e.phase == 4 then
      e.subAction = 4
      self:pausePlayer()
      self:sfx(SFX.DIE)
    else
      if not frozen(e) then e.type2, e.tm = 0, 60
      else
        if h.tailCount > 3 then
          h.tailCount = h.tailCount - 1
          local gone = h.tails[h.tailCount]
          if gone then gone.gone = true end
        end
        h.tails[0].radius = 0
        e.tm = 120
      end
      e.subAction = 1
    end
  elseif sa == 1 then
    if not frozen(e) then
      if h.tails[0].radius ~= 0 then h.tails[0].radius = h.tails[0].radius - 1 end
      local dx = band(0x108 - math.floor(e.x) + 4, 0xFFFF)
      local dy = band(0x88 - math.floor(e.y) + 4, 0xFFFF) -- (origin_y - y + $8C)
      if dx > 8 or dy > 8 then
        h.f2 = 1
        e.direction = rshift(dir256(0x108 - math.floor(e.x), 0x88 - math.floor(e.y)), 3)
        e.speed = 0x100
        self:move(e, e.direction, e.speed)
      else
        if e.type2 == 0 then
          for i = 0, 4 do self:object(5, i, e.x, e.y, e) end
          e.type2 = 1
        end
        h.f2 = 0
        e.tm = e.tm - 1
      end
    else
      for i = h.tailCount - 1, 1, -1 do h.tails[i - 1].draw = true end
      if band(self:frame(), 2) ~= 0 then self:object(6, 0, e.x, e.y, e) end
      e.tm = e.tm - 1
    end
    if e.tm == 0 then
      e.subAction = 2
      e.phase = e.phase + 1
      if not frozen(e) then
        e.hitType = 0x5F
        e.gfx = Assets.gfxSource("enemy", 0x108)
        self:setPal(e, 0xEF)
        self:changePalette(e, 0xEF)
        self:anim(h.tails[0], 1, true)
      else
        e.hitType = 0x61
        e.gfx = Assets.gfxSource("enemy", 0x109)
        self:setPal(e, 0xF0)
        self:changePalette(e, 0xF3)
        self:anim(h.tails[0], 2, true)
      end
      self:object(8, 0, e.x, e.y, e)
    end
  elseif sa == 2 then
    if h.tails[0].radius ~= 0x80 then h.tails[0].radius = h.tails[0].radius + 1
    else
      e.subAction, e.tm = 3, 150
      self.camTarget = nil
    end
  elseif sa == 3 then
    local was = e.tm
    e.tm = e.tm - 1
    if was == 0 then
      e.health = HEALTH_PER_PHASE[e.phase] or 0
      e.collide = true
      e.action, e.subAction, e.nextIdx = ACTION1, 0, 0
      h.tails[0].collide = true
      self:setWaitTurns(e)
    end
  elseif sa == 4 then
    e.subAction = 5
    self:object(9, 0, e.x, e.y, e)
  elseif sa == 5 then
    e.subAction, e.tm, e.u80 = 6, 120, 0
    e.spinT = 0 -- angularSpeed.HALF.LO
  elseif sa == 6 then
    e.angle = setHi(e.angle, hiA(e.angle) - 4)
    e.p4 = u8(e.p4 + 8)
    if band(e.u80, 0x80) ~= 0 then
      e.u80 = u8(e.u80 - band(self:rand(), 3))
      if band(e.u80, 0x80) == 0 then e.u80 = 0 end
    else
      e.u80 = u8(e.u80 + band(self:rand(), 3))
      if e.u80 >= 0x19 then e.u80 = bor(e.u80, 0x80) end
    end
    local r = band(e.u80, 0x7F) * 256
    e.ox = math.floor(s16(trunc(sin(e.p4) * r / 256)) / 256)
    e.oy = -math.floor(s16(trunc(cos(e.p4) * r / 256)) / 256)
    if e.tm == 0 then
      if band(self:frame(), 0xF) == 0 then
        f:addFx(e.x, e.y, SPECIAL_FX, FX_GIANT_EXPLOSION3)
        local l = h.legs[1]
        f:addFx(l.x, l.y, SPECIAL_FX, FX_GIANT_EXPLOSION3)
      end
      e.spinT = e.spinT + 1
      if e.spinT == 0x79 then
        h.mouth.health = 1
        self:sfx(SFX.DIE)
        e.dead = true
        self.en:kill(e) -- GenericDeath
      end
    else e.tm = e.tm - 1 end
  end
  if e.subAction > 3 then self:pausePlayer() end
  -- (Hit's sub_0800445C)
  self:staticPush(e)
end

-- ---------------------------------------------------------------------------
-- the intro (OctorokBoss_Intro)
-- ---------------------------------------------------------------------------
function B:intro(e)
  local f = self.field
  local p = f.player
  local h = e.h
  self:pausePlayer()
  self:breathe(e)
  local sa = e.subAction
  if sa == 0 then
    local was = e.tm
    e.tm = u8(e.tm - 1)
    if was == 0 then e.subAction, e.angSpd = 1, 0x100; h.unk0 = 2 end
  elseif sa == 1 then
    if hiA(e.angle) == 0x80 then
      e.tm, e.subAction = 60, 2
      h.unk0 = 0
      self:sfx(SFX.S159)
    else e.angle = band(e.angle + e.angSpd, 0xFFFF) end
    self:stepSound(e, 0xF)
  elseif sa == 2 then
    local was = e.tm
    e.tm = u8(e.tm - 1)
    if was == 0 then
      e.subAction, e.tm = 3, 60
      e.hideLink = nil
      self.camTarget = nil
      f.scrollSpeed = 1
    end
  elseif sa == 3 then
    local was = e.tm
    e.tm = u8(e.tm - 1)
    if was == 0 then
      p.direction, p.animationState = 0x10, 4
      self.walkIn = 0x1E
      e.tm, e.subAction = 60, 4
    end
  elseif sa == 4 then
    local was = e.tm
    e.tm = u8(e.tm - 1)
    if was == 0 then e.subAction, e.tm = 5, 45; p.animationState = 0
    elseif e.tm == 0x1E then f:bubble(p, 0) end
  elseif sa == 5 then
    if p.animationState == 4 then
      local was = e.tm
      e.tm = u8(e.tm + 1)
      if was > 0x1E then
        e.action, e.subAction = ACTION1, 0
        f.scrollSpeed = nil -- gRoomControls.scrollSpeed = 4 (the port's default pace)
        self:setAttackTimer(e)
        f:bgm(BGM_BOSS_THEME)
      end
    else
      local was = e.tm
      e.tm = u8(e.tm - 1)
      if was == 0 then p.animationState = 4 end
    end
  end
end

-- ---------------------------------------------------------------------------
-- collisions with Link
-- ---------------------------------------------------------------------------
-- sub_0800445C: a solid entity pushes Link out
function B:staticPush(pt)
  local f = self.field
  local p = f.player
  if p.hidden or p.state == "dead" then return end
  local HBm = require("src.zelda.tmc.Hitboxes")
  if HBm.data(f) then HBm.pushOut(f, pt, pt.hitbox) end
end
function B:touchLink(x, y, hb, hitType, z)
  local f = self.field
  local p = f.player
  if p.hidden or p.state == "dead" or (p.invuln or 0) > 0 or (z or 0) > 12 then return false end
  if math.abs((x + (hb.x or 0)) - p.x) < (hb.w or 4) + 5 and math.abs((y + (hb.y or 0)) - (p.y - 3)) < (hb.h or 4) + 6 then
    local HBm = require("src.zelda.tmc.Hitboxes")
    local s = self.en:settings(hitType or 0, HBm.data(f) and HBm.hurtType(p) or 0) or { tgtDmg = 2, orgIfr = 30, orgKbDur = 8, orgKbSpd = 24 }
    if (s.tgtDmg or 0) > 0 or (s.orgKbDur or 0) > 0 then
      if p:hurt(math.max(s.tgtDmg or 0, 1), x, y) then
        p.invuln = math.max(s.orgIfr or 30, 30)
        p.timer = math.max(s.orgKbDur or 8, 4)
        local ks = ((s.orgKbSpd or 24) * 16) / 256
        local dx, dy = p.x - x, p.y - y
        local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
        p.kbx, p.kby = dx / dd * ks, dy / dd * ks
      end
    end
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- the frame
-- ---------------------------------------------------------------------------
function B:update(e)
  local f = self.field
  local h = e.h
  if e.dead then
    self:linkState(e)
    return
  end
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  -- GetNextFunction: death (health 0) / knockback / the tick
  if e.health == 0 and e.action ~= HIT then self:onDeath(e) end
  if e.action == HIT then self:hit(e)
  elseif e.kbDur > 0 then -- GenericKnockback
    e.kbDur = e.kbDur - 1
    self:move(e, e.kbDir, e.kbSpd)
  elseif e.action == INTRO then self:intro(e)
  elseif e.action == ACTION1 then self:action1(e)
  elseif e.action == BURNING then self:burning(e) end
  if e.dead then self:linkState(e) return end
  e.anim:update(1)
  -- the parts, in creation order
  for leg = 1, 4 do self:legTick(e, h.legs[leg]) end
  if not h.mouth.dead then self:mouthTick(e, h.mouth) end
  if not h.tails[0].gone then self:tailEndTick(e, h.tails[0]) end
  for t = 1, 4 do local s = h.tails[t]; if not s.gone then self:tailTick(e, s) end end
  for leg = 1, 4 do h.legs[leg].anim:update(1) end
  -- touching Link (each part's own hit type)
  if e.collide then self:touchLink(e.x, e.y, e.hitbox, e.hitType, 0) end
  for leg = 1, 4 do local l = h.legs[leg]; if l.collide then self:touchLink(l.x, l.y, l.hitbox, l.hitType, 0) end end
  if not h.mouth.dead then self:touchLink(h.mouth.x, h.mouth.y, h.mouth.hitbox, h.mouth.hitType, 0) end
  local te = h.tails[0]
  if not te.gone and te.collide and te.draw then self:touchLink(te.x, te.y, te.hitbox, te.hitType, 0) end
  -- the light (ChangeLightLevel): the field's fade level
  if e.light ~= 0x100 or self.darkOn then
    f.fadeLevel = (0x100 - e.light) / 0x100 * 0.8
    f.fadeWhite = false
    self.darkOn = e.light ~= 0x100 or nil
  end
  -- the camera (gRoomControls.camera_target)
  local ct = self.camTarget or self.camHold
  if ct then f.cameraTarget = ct; self.ownsCam = true
  elseif self.ownsCam then f.cameraTarget = nil; self.ownsCam = nil end
  self:linkState(e)
end

-- the sword: the rocks (see projSwordHit); the body only clinks (hit types
-- $5F / $61 take no damage from it)
function B:swordHit(e, box)
  if e.octoProj then return self:projSwordHit(e, box) end
  return false
end

-- ---------------------------------------------------------------------------
-- OCTOROK_BOSS_PROJECTILE ($0F)
-- ---------------------------------------------------------------------------
function B:projectile(e, type, direction)
  local f = self.field
  local defs = f.assets.manifest.projectileDefs
  local d = defs and defs[B.PROJ]
  if d and d.multi then d = d.forms[type] or d.forms[0] end
  d = d or {}
  local p = f.player
  local s = { kind = 4, id = B.PROJ, type = type, type2 = 0, x = e.x, y = e.y, z = 0, cz = 0, czv = 0, sprite = d.sprite,
              gfx = Assets.gfxSource("enemy", d.gfx or 0), anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0,
              layer = 1, speed = d.speed or 0x200, hitType = d.damageType or 0, hitbox = d.hitbox or { x = 0, y = 0, w = 6, h = 6 },
              action = 1, octoProj = true, boss = true, impl = self, parent = e, direction = direction or 0, timer = 0,
              subtimer = 0, draw = true, palId = d.palette or 0xF5 }
  s.palette = self:pal(s.palId)
  if type == 0 then
    self:linear(s, 0x4800, s.direction)
    s.speed, s.timer, s.subtimer, s.u78 = 0x200, 0, s.direction, 300
    self:anim(s, 0, true)
  elseif type == 1 then
    s.speed = band(self:rand(), 0x1FF) + 0x200
    s.czv = (band(self:rand(), 0x1FFF) + 0x18000) / 65536
    s.direction = u8(s.direction - (band(self:rand(), 7) - 4))
    s.u78 = 600
    self:linear(s, s.speed, s.direction)
    self:anim(s, 4, true)
  elseif type == 2 then
    if band(self:rand(), 1) ~= 0 then s.direction = u8(band(self:rand(), 7) + s.direction)
    else s.direction = u8(s.direction - band(self:rand(), 7)) end
    s.speed, s.timer = 0x200, 48
    self:linear(s, 0x5000, s.direction)
    self:anim(s, 5, true)
  else
    s.x, s.y = p.x, p.y
    s.cz = -160
    s.x = s.x + 0x60
    s.y = s.y + 0x40
    s.x = s.x - (self:rand() % 0xC0)
    s.y = s.y - band(self:rand(), 0x7F)
    self:anim(s, 0, true)
  end
  s.z = -s.cz
  self:sfx(SFX.S1B5)
  s.extUpdate = function(_, me) self:projUpdate(me) end
  s.drawGhost = function(me, _, camX, camY) self:drawPart(me, camX, camY) end
  f.entities[#f.entities + 1] = s
  f._dungeon:track(s)
  return s
end
-- LinearMoveAngle(speed 8.8, direction 0..255)
function B:linear(s, speed, dir)
  s.x = s.x + sin(dir) * speed / 65536
  s.y = s.y - cos(dir) * speed / 65536
end
local function projBurst(self, s) -- OctorokBossProjectile_Action2
  self.field:addFx(s.x, s.y, SPECIAL_FX, FX_ROCK)
  s.deleted = true
end
B.projBurst = projBurst

-- the rock's tile collisions (CalculateEntityTileCollisions): which side is in a wall
function B:tileCols(s)
  local room = self.field.room
  local hb = s.hitbox
  local hw, hh = math.max(2, hb.w), math.max(2, hb.h)
  local cx, cy = s.x + (hb.x or 0), s.y + (hb.y or 0)
  local ew = room:isSolid(cx + hw, cy, 1) or room:isSolid(cx - hw - 1, cy, 1)
  local ns = room:isSolid(cx, cy - hh - 1, 1) or room:isSolid(cx, cy + hh, 1)
  local east, west = room:isSolid(cx + hw, cy, 1), room:isSolid(cx - hw - 1, cy, 1)
  local north, south = room:isSolid(cx, cy - hh - 1, 1), room:isSolid(cx, cy + hh, 1)
  return ew, ns, east, west, north, south
end

function B:projSwordHit(s, box)
  if s.deleted or s.type ~= 0 or s.type2 ~= 0 then return false end
  local hb = s.hitbox
  if math.abs((s.x + (hb.x or 0)) - box.x) < (hb.w or 6) + box.w and math.abs((s.y + (hb.y or 0)) - box.y) < (hb.h or 6) + box.h then
    s.contact = 4
    return true
  end
  return false
end

function B:projUpdate(s)
  local f = self.field
  local p = f.player
  local e = s.parent
  if s.deleted then return end
  if s.type == 0 then
    if e.action == HIT or e.dead then s.deleted = true return end
    if s.type2 == 0 and not s.contact then
      if self:touchRock(s) then s.contact = 0 end
    end
    if s.type2 == 0 and s.contact then
      if s.contact == 0 then projBurst(self, s) return end
      -- knocked back: knockbackDirection << 3 (from the attacker)
      s.direction = lshift(rshift(dir256(s.x - p.x, s.y - p.y) + 4, 3) % 32, 3)
      s.speed, s.type2, s.timer = 0x400, 1, 0
      s.contact = nil
    end
    if dist(s.x, s.y, e.x, e.y) <= 0x40 then
      if s.type2 == 0 then
        s.direction, s.speed = bxor(s.direction, 0x80), 0x400
      else
        e.health = math.max(0, e.health - 1)
        e.iframes = 0x1E
        if e.phase ~= 0 then e.kbDur, e.kbSpd, e.kbDir = 0x18, 0x200, rshift(s.direction, 3) end
        self:sfx(SFX.HIT)
        projBurst(self, s)
        return
      end
    end
    s.anim:update(1)
    s.u78 = band(s.u78 - 1, 0xFFFF)
    self:linear(s, s.speed, s.direction)
    local ew, ns = self:tileCols(s)
    if ew then s.direction = u8(-s.direction) end
    if ns then s.direction = bxor(u8(-s.direction), 0x80) end
    if s.direction == s.subtimer then return end
    self:sfx(SFX.S164)
    if s.u78 == 0 then s.timer = 4 else s.timer = s.timer + 1 end
    s.subtimer = s.direction
    if s.timer < 2 then return end
    for i = 0, 2 do
      local c = self:projectile(e, 1, u8(s.direction + FRAG_DIR[i]))
      c.x, c.y = s.x, s.y
    end
    projBurst(self, s)
  elseif s.type == 1 then
    if e.action == HIT then projBurst(self, s) return end
    s.anim:update(1)
    -- GravityUpdate(24.0): z (negative up) += -zVelocity; zVelocity -= $1800
    local air = true
    s.cz = s.cz - s.czv
    s.czv = s.czv - 0x1800 / 65536
    if s.cz >= 0 then s.cz, s.czv, air = 0, 0, false end
    if air then
      local ew, ns = self:tileCols(s)
      if not ew and not ns then self:linear(s, s.speed, s.direction) else projBurst(self, s) return end
    end
    if s.u78 < 0x1E then s.draw = band(s.u78, 7) ~= 0 end
    s.u78 = s.u78 - 1
    if s.u78 == -1 then projBurst(self, s) return end
    s.z = -s.cz
    if self:touchLink(s.x, s.y, s.hitbox, s.hitType, s.z) then projBurst(self, s) return end
  elseif s.type == 2 then
    s.anim:update(1)
    local was = s.timer
    s.timer = s.timer - 1
    if was ~= 0 then
      self:linear(s, s.speed, s.direction)
      self:touchLink(s.x, s.y, s.hitbox, s.hitType, 0)
      return
    end
    s.deleted = true
  else
    s.cz = s.cz - s.czv
    s.czv = s.czv - 0x1800 / 65536
    s.z = -s.cz
    if s.cz < 0 then
      if s.z < 8 then self:touchLink(s.x, s.y, s.hitbox, s.hitType, s.z) end
      return
    end
    f:addFx(s.x, s.y, SPECIAL_FX, FX_ROCK)
    s.deleted = true
  end
  s.z = -(s.cz or 0)
end

-- the rock meets Link: his body bursts it (and he is hurt), the shield
-- knocks it back like the sword
function B:touchRock(s)
  local f = self.field
  local p = f.player
  if p.hidden or p.state == "dead" then return false end
  local hb = s.hitbox
  if math.abs((s.x + (hb.x or 0)) - p.x) < (hb.w or 6) + 5 and math.abs((s.y + (hb.y or 0)) - (p.y - 3)) < (hb.h or 6) + 6 then
    if p:blocksFrom(s.x, s.y) then s.contact = 2; self:sfx(0x118) return false end
    if (p.invuln or 0) > 0 then return false end
    self:touchLink(s.x, s.y, s.hitbox, s.hitType, 0)
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- OCTOROK_BOSS_OBJECT ($87)
-- ---------------------------------------------------------------------------
function B:object(type, type2, x, y, e)
  local f = self.field
  local d = f:objects():def(B.OBJ, type)
  local o = { kind = 6, id = B.OBJ, type = type, type2 = type2, x = x, y = y, z = 0, parent = e, anim = Anim.new(),
              literalAnim = true, field82 = 0, interactType = 0, layer = 1, action = 1, subAction = 0, speed = 0x200,
              timer = 0, subtimer = 0, direction = 0, u74 = 0x100, u76 = 0x100, draw = true, octoObj = true }
  if d and d.sprite and d.sprite ~= 0 then
    o.sprite = d.sprite
    o.gfx = Assets.gfxSource(d.gfxType, d.gfx)
    o.palId = d.palette or 0
    o.palette = self:pal(o.palId)
  else o.draw = false end
  local h = e.h
  if type == 0 then
    o.b1, o.timer, o.subtimer = 0x96, 0, 30
    self:anim(o, 0, true)
    self:sfx(SFX.S124)
  elseif type == 1 then
    self:anim(o, 0, true)
    self:sfx(SFX.S124)
  elseif type == 2 then
    o.direction = u8(-(hiA(e.angle) - 0x80))
    if band(self:rand(), 1) ~= 0 then
      local r = band(self:rand(), 3)
      o.direction = u8(o.direction + ({ [0] = -0x10, 0x10, -8, 8 })[r])
    end
    o.speed = 240 - band(self:rand(), 0x3F)
    self:linear(o, rshift(o.speed, 1) * 256, o.direction)
    self:linear(o, rshift(o.speed, 1) * 256, o.direction)
    self:anim(o, 5, true)
    self:sfx(SFX.S14C)
  elseif type == 3 then
    o.direction = u8(-(hiA(e.angle) - 0x80))
    self:linear(o, 0x4800, o.direction)
    if band(self:rand(), 1) ~= 0 then o.direction = u8(band(self:rand(), 0x3F) + o.direction)
    else o.direction = u8(o.direction - band(self:rand(), 0x3F)) end
    self:anim(o, 6, true)
  elseif type == 6 then
    self:linear(o, (0x30 - band(self:rand(), 0x2F)) * 0x100, band(self:rand(), 0xFF))
    if band(self:rand(), 1) ~= 0 then o.direction = u8(band(self:rand(), 0x3F) + o.direction)
    else o.direction = u8(o.direction - band(self:rand(), 0x3F)) end
    self:anim(o, 5, true)
  elseif type == 4 then
    o.u78 = 0x30C
    o.draw = false
  elseif type == 5 then
    o.u78, o.u76, o.u74, o.ang = 0x18, 0x400, 0x400, 0
    local C = CRYSTAL
    self:linear(o, u8(-hiA(e.angle)) + C[type2 * 2 + 1], C[type2 * 2])
    self:anim(o, 7, true)
  elseif type == 8 then
    o.type2 = e.phase
    o.timer, o.subtimer = 4, 0
    o.cx = band(math.floor(o.x), 0x1F0)
    o.cy = band(math.floor(o.y), 0x1F0)
    self:iceTile(o.cx, o.cy, o.type2)
    self:sfx(band(e.phase, 1) ~= 0 and SFX.S1A3 or SFX.WIND2)
    o.draw = false
  elseif type == 9 then
    o.u78 = 0x1E0
    o.draw = false
    self.camHold = o
  end
  o.extUpdate = function(_, me) self:objUpdate(me) end
  o.drawGhost = function(me, _, camX, camY) if me.draw then self:drawPart(me, camX, camY) end end
  if not o.sprite then o.animIndex, o.objAnim = 0, 0 end -- (Field's literalAnim pass)
  f.entities[#f.entities + 1] = o
  f._dungeon:track(o)
  return o
end

-- sub_0809A6F8: one cell of the ice floor (type2 odd: ice, even: back)
function B:iceTile(x, y, type2)
  if not (x >= 0x10 and x <= 0x1F0 and y >= 0 and y <= 0xF0) then return false end
  local idx = rshift(x - 0x10, 4) + rshift(y, 4) * 0x1F
  local tile = self.T and self.T.u16(0x081238A0 + idx * 2) or 0
  if tile ~= 0 then
    local room = self.field.room
    local tx, ty = band(rshift(x, 4), 0x3F), band(rshift(y, 4), 0x3F)
    if tx < room.tw and ty < room.th then
      self.iceSaved = self.iceSaved or {}
      local k = ty * 64 + tx
      if band(type2, 1) ~= 0 then
        if self.iceSaved[k] == nil then self.iceSaved[k] = room.maps.bottom[ty * room.tw + tx] end
        room:setTile(1, tx, ty, tile) -- SetTileByIndex(.., LAYER_BOTTOM)
      elseif self.iceSaved[k] ~= nil then
        room:setTile(1, tx, ty, self.iceSaved[k]) -- RestorePrevTileEntity
        self.iceSaved[k] = nil
      end
    end
  end
  return true
end

function B:objUpdate(o)
  local f = self.field
  local e = o.parent
  local h = e.h
  if o.deleted then return end
  if o.action == 2 then -- OctorokBossObject_Action2: the flames round the burning boss
    o.anim:update(1)
    local was = o.timer
    o.timer = o.timer - 1
    if was ~= 0 then
      local tmp = math.floor(0x10000 / e.u74)
      local radius = rshift(o.speed * tmp, 8)
      local a = u8(-hiA(e.angle) + o.direction)
      polar(o, e, a, radius)
    else o.deleted = true end
    return
  end
  if o.draw then o.anim:update(1) end
  local t = o.type
  if t == 0 and o.b1 ~= 0 then
    o.b1 = o.b1 - 1
    local was = o.subtimer
    o.subtimer = o.subtimer - 1
    if was == 0 then
      o.subtimer = 5
      self:object(1, o.type2, o.x, o.y, e)
      o.type2 = o.type2 + 1
    end
    o.x, o.y = h.tails[0].x, h.tails[0].y
    return
  end
  if t == 0 or t == 1 then
    local tgt = h.tails[o.timer]
    if not tgt then o.deleted = true return end
    o.direction = dir256(tgt.x - o.x, tgt.y - o.y)
    self:linear(o, o.speed, o.direction)
    if not (math.abs(o.x - tgt.x) <= 2 and math.abs(o.y - tgt.y) <= 2) then return end
    if t == 0 then tgt.draw = false end
    if o.timer == h.tailCount - 1 then
      o.action, o.timer = 2, 240
      local k = band(o.type2, 0xF) * 2
      o.direction = FIRE_ORBIT[k] + band(self:rand(), 0xF)
      o.speed = FIRE_ORBIT[k + 1] + band(self:rand(), 0x1FF)
      if t ~= 0 then return end
      e.action, e.subAction = BURNING, 0
      return
    end
    o.timer = o.timer + 1
  elseif t == 2 then
    if e.type2 == 3 then
      local m = h.mouth
      o.direction = dir256(m.x - o.x, m.y - o.y)
      self:linear(o, 0x280, o.direction)
      if dist(o.x, o.y, e.x, e.y) > 0x48 then return end
    end
    o.deleted = true
  elseif t == 3 or t == 6 then
    self:linear(o, 0x80, o.direction)
    if (o.anim.flags or 0) ~= 0 then o.deleted = true end
  elseif t == 4 then
    if o.u78 == 0 then
      if e.light ~= 0x100 then e.light = math.min(0x100, e.light + 8) return end -- ChangeLightLevel(8)
      o.deleted = true
    else
      if e.health == 0 then o.subAction, o.u78 = 1, 0 return end
      if o.subAction == 0 and e.type2 ~= 0 then return end
      o.subAction = 1
      o.u78 = o.u78 - 1
    end
  elseif t == 5 then
    if o.u78 == 0 then
      if o.u76 == 0x100 then
        if band(e.phase, 1) ~= 0 then o.deleted = true return end
      else o.u76, o.u74 = o.u76 - 0x20, o.u74 - 0x20 end
    else o.u78 = o.u78 - 1 end
    o.x, o.y = e.x, e.y
    local C = CRYSTAL
    self:linear(o, C[o.type2 * 2 + 1], u8(u8(-hiA(e.angle)) + C[o.type2 * 2]))
  elseif t == 8 then
    local was = o.timer
    o.timer = o.timer - 1
    if was ~= 0 then return end
    o.timer = 4
    o.subtimer = o.subtimer + 1
    local k = o.subtimer
    local any = false
    if self:iceTile(o.cx, o.cy - k * 16, o.type2) then any = true end
    for i = 1, k do
      if self:iceTile(o.cx - i * 16, o.cy - k * 16 + i * 16, o.type2) then any = true end
      if self:iceTile(o.cx + i * 16, o.cy - k * 16 + i * 16, o.type2) then any = true end
    end
    if self:iceTile(o.cx, o.cy + k * 16, o.type2) then any = true end
    for i = 1, k - 1 do
      if self:iceTile(o.cx - i * 16, o.cy + k * 16 - i * 16, o.type2) then any = true end
      if self:iceTile(o.cx + i * 16, o.cy + k * 16 - i * 16, o.type2) then any = true end
    end
    if not any then o.deleted = true end
  elseif t == 9 then
    local was = o.u78
    o.u78 = o.u78 - 1
    if was == 0 then
      self.camHold = nil
      o.deleted = true
      if e.dead then -- gRoomControls.camera_target = Link; Link moves again
        f.cameraTarget, self.ownsCam = nil, nil
        self:linkState(e)
      end
      return
    end
    self:pausePlayer() -- PausePlayer
    if e.dead then -- the boss is gone: this object keeps the camera and Link itself
      f.cameraTarget, self.ownsCam = o, true
      self:linkState(e)
    end
  end
end

-- ---------------------------------------------------------------------------
-- drawing (the affine parts)
-- ---------------------------------------------------------------------------
function B:drawAff(pt, camX, camY, sx, sy, angle, tag)
  local frame = pt.anim.frame
  if not pt.sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = self.A:spriteFrame(pt.sprite, frame, pt.palette, "octo" .. tostring(tag or pt.type) .. ":" .. tostring(pt.palId), pt.gfx)
  if not img then return end
  local x, y = math.floor(pt.x - camX + (pt.ox or 0)), math.floor(pt.y - camY - (pt.z or 0) + (pt.oy or 0))
  local kx, ky = 256 / (sx ~= 0 and sx or 256), 256 / (sy ~= 0 and sy or 256)
  if pt.anim:hflip() then kx = -kx end
  love.graphics.draw(img, x, y, -(angle or 0) / 0x10000 * 2 * math.pi, kx, ky, -ox, -oy)
end
function B:drawPart(pt, camX, camY)
  if pt.draw == false then return end
  if pt.octoObj and pt.type == 5 then return self:drawAff(pt, camX, camY, pt.u76, pt.u74, 0, "o5") end
  local frame = pt.anim.frame
  if not pt.sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = self.A:spriteFrame(pt.sprite, frame, pt.palette, "octop" .. tostring(pt.palId), pt.gfx)
  if not img then return end
  local x, y = math.floor(pt.x - camX), math.floor(pt.y - camY - (pt.z or 0))
  if pt.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
end

function B:draw(e, camX, camY)
  if e.dying and not e.dead then return end
  if e.dead and e.dying then return end
  local h = e.h
  local flick = e.iframes > 0 and e.iframes % 4 < 2
  for leg = 1, 4 do local l = h.legs[leg]; self:drawAff(l, camX, camY, s16(l.u76), s16(l.u74), l.angle, "leg") end
  if not h.mouth.dead then self:drawAff(h.mouth, camX, camY, h.mouth.u76, h.mouth.u74, h.mouth.angle, "mouth") end
  if not flick then self:drawAff(e, camX, camY, e.u76, e.u74, e.angle, "body") end
  for t = 4, 1, -1 do -- (the TAIL parts set no affine info: plain sprites)
    local s = h.tails[t]
    if s and not s.gone and s.draw then self:drawPart(s, camX, camY) end
  end
  local te = h.tails[0]
  if te and not te.gone and te.draw then self:drawAff(te, camX, camY, te.u76, te.u74, bxor(band(-setHi(0, te.angHi or 0), 0xFFFF), 0x8000), "tailEnd") end
end

-- the R26 hooks
local M = { ROM_RANGES = B.ROM_RANGES, B = B }
function M.spawnEnemy(E, dat, def)
  if dat.id ~= B.ID then return nil end
  return B.new(E.field, E):spawn(dat, def)
end
M.new = B.new
return M
