-- Round 25: Gleerok ($24), src/enemy/gleerok.c ported (replaces round 8's
-- simplified BossGleerok.lua as the one the room spawns; BossGleerok.simple
-- brings the old model back), with gleerokProjectile.c and the parts of
-- gleerokParticle.c the fight needs.
--
-- PARTS.  The body (type 0, in the lava, animations $4C / $4D / $4E) owns a
--   heap: per joint i = 0..5 a direction word f[i] (its high byte the
--   32-step facing) and an elevation word g[i]; the joint lengths u30[i]
--   (0..10 px); unk_2c is g[5] (the struct's filler2[5]: the head's
--   elevation, its reach by Link's distance); the five neck segments (type 1,
--   ents[0..4], animation $24 / by angle) and the head (type 2, ents[5] =
--   ent2).  sub_0802E518 lays the chain out every frame: ents[0] is the
--   body's position moved along f[0] by ((r ^ $F) + $12) px, each next
--   joint the one before + (u30 * sin g * sin f, -u30 * cos g) (gSineTable
--   math kept); the segments' animations follow their angles (state * 1.5
--   / 4 + g / 3 * 12, or $48 + f >> 3 while it lies on the platform), the
--   head's ent2.timer selects its set ($18 + ... while it breathes, $28 /
--   $2F lying down).  sub_0802E7E4 orders the sprites front / back by the
--   head's frame bit $40.  sub_0802E768 / sub_0802EA88 / sub_0802EB08
--   relax each joint one step toward the next (the snake-like follow).
-- THE FIGHT (body action 1 = sub_0802D86C, by subAction):
--   0 turn the head toward Link (speed by phase $30 / $40 / $50), 1 track
--   him with a small sway, the head's reach following his distance
--   (sub_0802E9B0); both count unk_74 down and then (sub_0802EBC4, weights
--   gUnk_080CD86C / 878 by phase) pick 2 (a breath: the neck segments pulse
--   one by one, then GLEEROK_PROJECTILE type 0 at him, twice) or 3 (a
--   sweep: type 1 lobs -- or type 2 low fire in phase 2+ -- while the neck
--   swings +-4 / 6 / 12 steps).
--   4 knocked out (the plug): type2 0 the neck straightens and waits for
--   the plug to land (unk_7b) -> collision on; 1 / 2 the neck comes down
--   onto the platform (sub_0802E034, gUnk_080CD840 = 4 / 8 / 16 / 8 by
--   facing quarter), then unk_80 1: Link can walk on it (field_0x14,
--   spriteOffsetY -4 per segment within 8 px); 3 (sub_0802E0B8) the core
--   can be hit for $168 frames (shaking under $78); health at or under
--   gUnk_080CD844[phase] ends the phase (unk_79 + 1, health $FF) -- the
--   third time it dies; 4 (sub_0802E1D0) it sinks (animation $4E: each
--   frame bit $40 takes a joint, FX_LAVA_SPLASH, SFX_124), the last one ->
--   240 frames of shake (or, after a phase change, the four lava
--   particles and the BG blend), type2 5 (sub_0802E300): fireballs rain
--   (type 3 every 16 frames) until unk_7c runs out, then 5.
--   5 rise again (sub_0802E448 joints back out with splashes + SFX_PLY_LAND,
--   sub_0802E4C0 the body's animation), unk_74 0 -> the next attack.
-- THE PLUG (types 5 -> 6 -> 3 -> 4): grows on the body after each rise;
--   type 3 turns its frame with f[0], its palette steps by gUnk_080CD884;
--   the Cane's bolt (contact $1D, once the steps are over) knocks it out
--   (zVelocity 3.0, the body's subAction 4, SFX_BUTTON_PRESS); at the top
--   it becomes type 4 (animation $2C) which falls (24/256), sets the body's
--   unk_7b, bursts into 8 GLEEROK_PARTICLE type 0 and SFX_150.
-- THE INTRO (body action 2): Link looks round ($96 frames: left, right,
--   '!', up), the camera goes to the boss, 90 frames, shake 150, 90
--   frames, the plug grows, the body rises (sub_0802D77C every other
--   frame) and runs the scripted moves gUnk_080CD7F8 (SFX_BOSS_HIT each),
--   then BGM_BOSS_THEME and Link's control.
-- THE DEATH (Gleerok_OnDeath type 0, by action): fade, Link put on the
--   platform at origin + ($98, $D8) facing up, the neck pulled straight,
--   GLEEROK_PARTICLE type 2 holds the camera $168 frames; $B4 frames of
--   thrashing (gUnk_080CD774), SFX_BOSS_DIE every 32 frames, explosions
--   every 16; it sinks (sub_0802E1D0); then the segments go (the last one's
--   GenericDeath) and the head's OnDeath blends BG1 away (alphaBlend $10 ->
--   $1000, a step every 16 frames, SFX_EVAPORATE, SFX_APPARATE at 60).
-- PROJECTILES (gleerokProjectile.c): types 0 / 1 start 16 px out from the
--   head along the joint's facing at the head's height over the neck base
--   (z = head.y - ents[0].y), animation $51, SFX_1B5; they fall linearly
--   (zVelocity = z / (distance << 8) << $D, distance clamped $20..$400 --
--   type 1 +-rand $1FF) and turn toward Link one step every 30 frames;
--   type 2 falls at z / 1.5; landed: animation $52 (type 2: $54, 15 frames
--   sliding on); then $53 and gone.  Contact with Link (not $1E) ends them
--   ($53).  Type 3 (the rain): z -160 at a random spot round the body
--   (gUnk_08129978 / 80 / 88), gravity 24/256, FX_ROCK where it lands.
-- SIMPLIFIED: the BG blends are the port's topAlpha; the lava particles of
--   a phase change (GLEEROK_PARTICLE type 1, affine) are not drawn and do
--   not restore tiles; FX are the port's addFx; the per-segment iframes
--   copy is only the palette flash.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local G = {}
G.__index = G
G.ID = 0x24
G.PROJ = 0x0A

local SFX = { BOSS_HIT = 0x127, BOSS_DIE = 0x128, EVAPORATE = 0xF6, APPARATE = 0xF7, S124 = 0x124, S150 = 0x150,
              S1B5 = 0x1B5, BUTTON = 0x10C, LAND = 0x7D }
local BGM_BOSS_THEME = 0x2E
local SPECIAL_FX, FX_LAVA_SPLASH, FX_GIANT_EXPLOSION3, FX_ROCK = 0x0F, 0x0C, 0x48, 0x04
local LV2_CLEAR = 0x03

-- gSineTable (256 steps a turn, $100 = 1)
local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
G.SIN = SIN

local THRASH = { 24, 3, 16, 0, 32, 1, 16, 2, 16, 3, 24, 0, 24, 1, 4, 3, 4, 2, 24, 0, 4, 3, 24, 1, 4, 2, 24, 0, 24, 1, 24, 0, 24,
  1, 24, 0, 24, 1, 4, 3, 4, 2, 24, 0, 24, 1, 4, 3, 4, 2, 24, 0, 24, 1, 4, 3, 4, 2, 4, 3, 4, 2, 24, 0, 24, 1, 255, 0 } -- gUnk_080CD774
G.THRASH = THRASH
local RAIN_A = { [0] = 80, 0, 0, 80, -96, 0, 0, -96 }                                   -- gUnk_08129978
local RAIN_B = { [0] = 0, 16, -16, 0, 16, -16, 16, -16 }                                 -- gUnk_08129980
local RAIN_C = { [0] = 0, -16, -32, -48, -64, -80, -96, -112, 0, 16, 32, 48, 64, 80, 96, 112 } -- gUnk_08129988

local function s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end
local function hi(w) return band(rshift(w, 8), 0xFF) end
local function setHi(w, v) return bor(band(w, 0xFF), lshift(band(v, 0xFF), 8)) end

-- ---------------------------------------------------------------------------
-- the ROM tables (manifest.r25)
-- ---------------------------------------------------------------------------
local function tables(f)
  local T = require("src.zelda.tmc.ExtractR25").gleerokTables(f.assets.manifest)
  return T
end
function G.introMoves(T) -- gUnk_080CD7F8 (24 bytes: timer, direction pairs, $FF ends)
  local t = {}
  for i = 0, 23 do t[i] = T and T.u8(0x080CD7F8 + i) or 0xFF end
  return t
end
G.ADDR = { PRIO = 0x080CD7C4, INTRO = 0x080CD7F8, LOWER = 0x080CD840, HEALTH = 0x080CD844, W850 = 0x080CD850,
           W854 = 0x080CD854, PHASE_W = { 0x080CD858, 0x080CD85E, 0x080CD864 }, PHASE_N = { 0x080CD85B, 0x080CD861, 0x080CD867 },
           PLUG = 0x080CD884 }

-- GetRandomByWeight: a u8 weight list (sum 256), the index the random byte falls in
local function byWeight(self, addr, n)
  local r = band(self:rand(), 0xFF)
  local acc = 0
  for i = 0, (n or 4) - 1 do
    acc = acc + self.T.u8(addr + i)
    if r < acc then return i end
  end
  return (n or 4) - 1
end

function G.new(field, enemies)
  return setmetatable({ field = field, en = enemies, A = field.assets }, G)
end
function G:rand() local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(self.field)) end
function G:sfx(id) self.field:sound(id) end

-- ---------------------------------------------------------------------------
-- parts
-- ---------------------------------------------------------------------------
function G:part(type, x, y)
  local d = self.en:def(G.ID, type) or {}
  local pt = { type = type, type2 = 0, x = x, y = y, z = 0, zv = 0, sprite = d.sprite, def = d, anim = Anim.new(),
               gfx = Assets.gfxSource("enemy", d.gfx or 0), palId = d.palette or 0xC9, draw = true, prio = 4,
               timer = 0, subtimer = 0, iframes = 0, health = d.health or 0, animationState = 0, direction = 0, speed = 0,
               hitbox = d.hitbox or { x = 0, y = 0, w = 8, h = 8 }, hitType = d.damageType or 0x5E }
  pt.palette = self.A:objPalette(pt.palId, self.field.room.atlas and self.field.room.atlas.palettes)
  return pt
end
function G:anim(pt, idx, force)
  if not force and pt.animIndex == idx then return end
  pt.animIndex = idx
  pt.flagKey = nil
  if pt.sprite then pt.anim:set(self.A:sprite(pt.sprite), idx, true) end
end
local function fflags(pt)
  if pt.flagKey == pt.anim.key then return band(pt.anim.flags or 0, 0x80) end
  return pt.anim.flags or 0
end
local function take(pt) pt.flagKey = pt.anim.key end
local function adone(pt) return band(fflags(pt), 0x80) ~= 0 end
local function step(pt) if not adone(pt) then pt.anim:update(1) end end -- UpdateAnimationSingleFrame
function G:pal(pt, id)
  if pt.palNow == id then return end
  pt.palNow = id
  pt.palette = self.A:objPalette(id, self.field.room.atlas and self.field.room.atlas.palettes)
end

function G:spawn(dat, def)
  local f = self.field
  if f:flag("global", LV2_CLEAR) then return nil end -- sub_0802D3B8: LV2_CLEAR
  self.T = tables(f)
  if not self.T then return require("src.zelda.tmc.BossGleerok").new(f, self.en):spawn(dat, def) end -- an old cache: round 8's model
  local e = {
    kind = 3, id = dat.id, form = 0, x = dat.x, y = dat.y, z = 0, boss = true, enemy = true, impl = self,
    health = 0xFF, hitType = def and def.damageType or 0x5E, hitbox = def and def.hitbox or { x = 0, y = 0, w = 12, h = 12 },
    def = def or {}, anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0, iframes = 0,
    layer = 1, gleerok2 = true,
  }
  local b = self:part(0, dat.x, dat.y)
  e.body = b
  b.action, b.subAction = 2, 0
  b.collide = false
  b.prio = 7
  b.u74, b.u75, b.u76, b.u77, b.u78, b.u79, b.u7a, b.u7b, b.u80, b.u82 = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
  b.u7c = 0x96
  self:pickWait(b)
  local h = { f = {}, g = {}, u30 = {}, ents = {} } -- (unk_2c = g[5])
  for i = 0, 5 do h.f[i], h.g[i], h.u30[i] = 0, 0, 0 end
  e.h = h
  for i = 0, 4 do
    local s = self:part(1, dat.x, dat.y + (i + 1) * 12)
    s.type2 = i + 1
    s.parent = b
    if s.type2 == 1 then s.collide = true end
    s.prio = self.T.u8(G.ADDR.PRIO + 4 * s.type2 + 1)
    self:anim(s, 0x24)
    h.ents[i] = s
    h.f[i] = setHi(h.f[i], 0x10)
    h.g[i] = setHi(h.g[i], 0)
  end
  local hd = self:part(2, dat.x, dat.y + 6 * 12)
  hd.parent = b
  hd.prio = 0
  self:anim(hd, 0, true)
  h.ents[5] = hd
  h.f[5] = setHi(h.f[5], 0x10)
  b.parent = nil
  self:anim(b, 0x4C)
  e.sprite = hd.sprite
  -- gPlayerState.controlMode = CONTROL_DISABLED (until the intro ends)
  local p = f.player
  p.state, p.extUpdate = "ext", function() end
  e.lockLink = true
  return e
end

-- sub_0802EB9C
function G:pickWait(b)
  b.u74 = self.T.u8(G.ADDR.W854 + byWeight(self, G.ADDR.W850, 4))
  b.u75 = band(b.u75 + 1, 0xFF)
end

-- ---------------------------------------------------------------------------
-- the chain's helpers
-- ---------------------------------------------------------------------------
local function rotF(h, i, sp, d) if d == 1 then sp = -sp end h.f[i] = band(h.f[i] + sp, 0x1FFF) end -- sub_0802EA48
local function rotG(h, i, sp, d) if d == 2 then sp = -sp end h.g[i] = band(h.g[i] + sp, 0x1FFF) end -- sub_0802EA68
G.rotF, G.rotG = rotF, rotG

local function relax(h) -- sub_0802E768
  for i = 0, 4 do
    local b3 = hi(h.f[i])
    local d = band(b3 - hi(h.f[i + 1]), 0x1F)
    if d > 0x10 then if d <= 0x1E then b3 = band(b3 + 1, 0x1F) end
    elseif d > 1 then b3 = band(b3 - 1, 0x1F) end
    h.f[i] = setHi(h.f[i], b3)
    b3 = hi(h.g[i])
    d = band(b3 - hi(h.g[i + 1]), 0x1F)
    if d > 0x10 then if d <= 0x1D then b3 = band(b3 + 1, 0x1F) end
    elseif d > 2 then b3 = band(b3 - 1, 0x1F) end
    h.g[i] = setHi(h.g[i], b3)
  end
end
G.relax = relax

local function followF(h) -- sub_0802EA88
  local moved = false
  for i = 0, 4 do
    if hi(h.f[i]) ~= hi(h.f[i + 1]) then
      moved = true
      rotF(h, i + 1, 0x20, band(hi(h.f[i + 1]) - hi(h.f[i]), 0x1F) > 0x10 and 0 or 1)
      break
    end
  end
  for i = 0, 4 do
    local b4 = hi(h.f[i + 1])
    local d = band(b4 - hi(h.f[i]), 0x1F)
    local v = b4
    if d >= 0x11 then if d < 0x1F then v = band(v + 1, 0x1F) end
    elseif d > 1 then v = band(v - 1, 0x1F) end
    h.f[i + 1] = setHi(h.f[i + 1], v)
  end
  return moved
end
G.followF = followF

local function followG(h, sp, lim) -- sub_0802EB08
  local moved = false
  for i = 0, 4 do
    if hi(h.g[i]) ~= hi(h.g[i + 1]) then
      moved = true
      rotG(h, i + 1, sp, band(hi(h.g[i + 1]) - hi(h.g[i]), 0x1F) > 0x10 and 3 or 2)
      break
    end
  end
  for i = 0, 4 do
    local b4 = hi(h.g[i + 1])
    local d = band(b4 - hi(h.g[i]), 0x1F)
    local v = b4
    if d >= 0x11 then if band(-lim, 0x1F) > d then v = band(v + 1, 0x1F) end
    elseif lim < d then v = band(v - 1, 0x1F) end
    h.g[i + 1] = setHi(h.g[i + 1], v)
  end
  return moved
end
G.followG = followG

local function closeTo(a0, a1, n) -- sub_0802EA18: FALSE when within n steps
  local r1 = band(a1 + 0x1000 - a0, 0x1FFF)
  n = n * 256
  if r1 >= 0x1000 - n and r1 <= 0x1000 + n then return false end
  return true
end
G.closeTo = closeTo

-- GetFacingDirection (0..31)
local function facing(ax, ay, bx, by)
  local a = math.atan2(bx - ax, -(by - ay))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
-- sub_080041DC: the distance * 16
local function dist16(ax, ay, bx, by)
  local dx, dy = math.floor(bx) - math.floor(ax), math.floor(by) - math.floor(ay)
  return math.floor(math.sqrt((dx * dx + dy * dy) * 256))
end

-- sub_0802E518: the chain's layout and the animations
function G:layout(e)
  local b, h = e.body, e.h
  local e0 = h.ents[0]
  e0.x, e0.y = b.x, b.y
  local r6 = hi(h.f[0])
  e0.direction = r6
  if r6 > 0x10 then r6 = bxor(r6, 0xF); r6 = band(r6 + 1, 0xF) end
  if r6 == 0x10 then r6 = 0xF end
  local spd = (bxor(r6, 0xF) + 0x12) * 256
  local a = (e0.direction % 32) / 32 * 2 * math.pi
  e0.x, e0.y = e0.x + math.sin(a) * spd / 256, e0.y - math.cos(a) * spd / 256
  for i = 0, 4 do
    local cur, nxt = h.ents[i], h.ents[i + 1]
    nxt.x, nxt.y = cur.x, cur.y
    local gi, fi = hi(h.g[i + 1]) * 8, hi(h.f[i + 1]) * 8
    local r = math.floor(SIN[gi % 256] * h.u30[i])                  -- FixedMul(sin g, u30 << 8) / FixedDiv
    r = math.floor(SIN[fi % 256] * r / 256)                        -- FixedMul(sin f, r)
    nxt.x = nxt.x + r / 256
    local ry = math.floor(SIN[(gi + 0x40) % 256] * h.u30[i])
    nxt.y = nxt.y - ry / 256
  end
  local hd = h.ents[5]
  local r7
  if hd.timer == 24 then
    r7 = lshift(rshift(hi(h.f[5]), 3), 2)
    if hi(h.g[5]) > 0xC then r7 = r7 + 3 else r7 = r7 + rshift(hi(h.g[5]), 2) end
    if hd.animIndex ~= r7 + 0x18 then self:anim(hd, r7 + 0x18, true) end
  else
    if b.u80 == 0 then
      hd.animationState = hi(h.f[5])
      r7 = rshift(hd.animationState + rshift(hd.animationState, 1), 2) + hd.timer
    else
      if b.iframes == 0 then
        if b.animIndex ~= rshift(hi(h.f[5]), 3) + 0x2F then r7 = rshift(hi(h.f[5]), 3) + 0x28
        elseif adone(b) then r7 = rshift(hi(h.f[5]), 3) + 0x28
        else r7 = b.animIndex end
      else r7 = rshift(hi(h.f[5]), 3) + 0x2F end
    end
    if hd.animIndex ~= r7 then self:anim(hd, r7, true) else step(hd) end
  end
  for i = 0, 4 do
    local s = h.ents[i]
    if b.u80 == 0 then
      s.animationState = hi(h.f[i])
      r7 = rshift(s.animationState + rshift(s.animationState, 1), 2) + math.floor(hi(h.g[i + 1]) / 3) * 12
    else
      r7 = rshift(hi(h.f[i]), 3) + 0x48
    end
    if s.animIndex ~= r7 then self:anim(s, r7) end
  end
end

-- sub_0802E7E4: draw order / visibility
function G:order(e)
  local h = e.h
  local hd = h.ents[5]
  if band(fflags(hd), 0x40) ~= 0 then
    local v = 0
    for i = 0, 5 do h.ents[i].prio = v; v = v + 1; h.ents[i].draw = h.u30[i] ~= 0 end
    for i = 0, 4 do
      if band(hi(h.f[i]) - 8, 0xFF) < 0x11 then h.ents[i].prio, h.ents[i + 1].prio = h.ents[i + 1].prio, h.ents[i].prio end
    end
    if h.entity1 then h.entity1.prio = 0 end
  else
    local v = 5
    for i = 0, 5 do h.ents[i].prio = v; v = v - 1; h.ents[i].draw = h.u30[i] ~= 0 end
    for i = 0, 4 do
      if 0x10 < band(hi(h.f[i]) - 8, 0xFF) then h.ents[i].prio, h.ents[i + 1].prio = h.ents[i + 1].prio, h.ents[i].prio end
    end
    if h.entity1 then h.entity1.prio = 6 end
  end
end

-- sub_0802E9B0: the head's reach follows Link's distance
function G:reach(e)
  local b, h = e.body, e.h
  local p = self.field.player
  local d = rshift(dist16(b.x, b.y, p.x, p.y), 4)
  local want
  if d < 0x60 then want = 10
  else
    want = 10 - rshift(d - 0x60, 2)
    if want < 4 then want = 4 end
  end
  if want ~= hi(h.g[5]) then
    if want > hi(h.g[5]) then h.g[5] = band(h.g[5] + 0x20, 0x1FFF) else h.g[5] = band(h.g[5] - 0x20, 0x1FFF) end
  end
end

-- sub_0802EBC4: the next attack
function G:nextAttack(b)
  if b.u74 == 0 then
    local ph = math.min(b.u79, 2) + 1
    local k = byWeight(self, G.ADDR.PHASE_W[ph], 3)
    if self.T.u8(G.ADDR.PHASE_N[ph] + k) < b.u75 then
      b.u75 = 0
      if b.u79 == 0 then b.u76, b.u77 = 0, 3
      else
        local r = band(self:rand(), 1)
        if r ~= b.u76 then b.u76, b.u77 = r, 1
        else
          b.u77 = b.u77 + 1
          if b.u77 > 2 then r = bxor(r, 1); b.u77 = 1 end
          b.u76 = r
        end
      end
      b.subAction, b.type2 = 3, 0
    else
      b.subAction = 2
    end
  else
    b.u74 = b.u74 - 1
  end
end

-- ---------------------------------------------------------------------------
-- projectiles
-- ---------------------------------------------------------------------------
function G:projectile(e, type)
  local f = self.field
  local h = e.h
  local d = f.assets.manifest.projectileDefs and f.assets.manifest.projectileDefs[G.PROJ]
  if d and d.multi then d = d.forms[0] end
  d = d or {}
  local hd, e0 = h.ents[5], h.ents[0]
  local s = { kind = 4, id = G.PROJ, type = type, x = hd.x, y = hd.y, z = 0, zv = 0, sprite = d.sprite,
              gfx = Assets.gfxSource("enemy", d.gfx or 0), anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0,
              layer = 1, speed = d.speed or 0x200, hitType = d.damageType or 0, hitbox = d.hitbox or { x = 0, y = 0, w = 4, h = 4 },
              action = 1, gproj = true, parent = hd, child = e0, subtimer = 0 }
  s.palette = self.A:objPalette(d.palette or 0xC9, f.room.atlas and f.room.atlas.palettes)
  if (d.gfx or 0) == 0 then s.gfx, s.palette = hd.gfx, hd.palette end
  local p = f.player
  if type ~= 3 then
    s.direction = hi(h.f[5])
    local a = (s.direction % 32) / 32 * 2 * math.pi
    s.x, s.y = s.x + math.sin(a) * 16, s.y - math.cos(a) * 16          -- LinearMoveDirection($1000)
    local zw = (hd.y - e0.y)                                           -- z = parent.y - child.y (negative: up)
    s.cz = zw                                                          -- the cartridge's z (negative = up)
    s.y = s.y - zw
    self:panim(s, 0x51)
    self:sfx(SFX.S1B5)
  else
    s.cz = -160
    local u = band(self:rand(), 3) * 2
    s.x, s.y = e.body.x + RAIN_A[u], e.body.y + RAIN_A[u + 1]
    if band(u, 2) ~= 0 then
      s.x = s.x + RAIN_C[band(self:rand(), 0xF)]; s.y = s.y + RAIN_B[band(self:rand(), 7)]
    else
      s.x = s.x + RAIN_B[band(self:rand(), 7)]; s.y = s.y + RAIN_C[band(self:rand(), 0xF)]
    end
    s.x, s.y = math.floor(s.x / 16) * 16 + 8, math.floor(s.y / 16) * 16 + 8 -- SnapToTile
    self:panim(s, 0)
  end
  if type == 0 or type == 1 then
    local iv = dist16(s.x, s.y, p.x, p.y)
    if type == 1 then
      local u = band(self:rand(), 0x1FF)
      if band(f.frame or 0, 1) == 0 then iv = iv + u else iv = iv - u end
    end
    if iv < 0x20 then iv = 0x20 elseif iv > 0x400 then iv = 0x400 end
    s.czv = s.cz * 0x2000 / (iv * 256) -- z / (dist << 8) << $D (px a frame, negative)
    s.subtimer = 30
  elseif type == 2 then
    s.czv = s.cz / 1.5 / 16
  end
  s.z = -s.cz
  s.extUpdate = function(_, me) self:projUpdate(me) end
  s.drawGhost = function(me, _, camX, camY) self:drawPart(me, camX, camY) end
  f.entities[#f.entities + 1] = s
  f._dungeon:track(s)
  return s
end
function G:panim(s, idx) s.animIndex = idx; s.flagKey = nil; if s.sprite then s.anim:set(self.A:sprite(s.sprite), idx, true) end end

function G:touchLink(x, y, hb, hitType, z)
  local f = self.field
  local p = f.player
  if p.state == "dead" or p.invuln > 0 or (z or 0) > 12 then return false end
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

function G:projUpdate(s)
  local f = self.field
  local p = f.player
  if s.action ~= 3 and s.type ~= 3 and s.action ~= 0 and self:touchLink(s.x, s.y, s.hitbox, s.hitType, s.z) then
    s.action = 3
    self:panim(s, 0x53)
  end
  if s.action == 1 then
    if s.type == 3 then
      s.cz = s.cz + (s.czv or 0); s.czv = (s.czv or 0) + 24 / 256 * 16 / 16
      if s.cz >= 0 then
        s.cz = 0
        f:addFx(s.x, s.y, SPECIAL_FX, FX_ROCK)
        if math.abs(p.x - s.x) < 10 and math.abs(p.y - s.y) < 10 and p.invuln == 0 then self:touchLink(s.x, s.y, s.hitbox, s.hitType, 0) end
        s.deleted = true
      end
    else
      s.anim:update(1)
      local a = (s.direction % 32) / 32 * 2 * math.pi
      s.x, s.y = s.x + math.sin(a) * s.speed / 256, s.y - math.cos(a) * s.speed / 256
      if s.type ~= 2 then
        if s.subtimer == 0 then
          s.subtimer = 30
          local want = facing(s.x, s.y, p.x, p.y) -- sub_08004596: one step toward
          local dd = band(want - s.direction, 0x1F)
          if dd ~= 0 then s.direction = band(s.direction + (dd < 0x10 and 1 or -1), 0x1F) end
        else s.subtimer = s.subtimer - 1 end
      end
      s.cz = s.cz - (s.czv or 0) -- GravityUpdate(.., 0): z -= zVelocity (zVelocity negative: down)
      if s.cz >= 0 then
        s.cz = 0
        s.action = 2
        if s.type == 2 then s.timer = 15; self:panim(s, 0x54) else self:panim(s, 0x52) end
      end
    end
  elseif s.action == 2 then
    s.anim:update(1)
    if s.type == 2 then
      if s.timer == 0 then s.action = 3; self:panim(s, 0x55)
      else
        s.timer = s.timer - 1
        local a = (s.direction % 32) / 32 * 2 * math.pi
        s.x, s.y = s.x + math.sin(a) * s.speed / 256, s.y - math.cos(a) * s.speed / 256
      end
    elseif adone(s) then s.action = 3; self:panim(s, 0x53) end
  elseif s.action == 3 then
    s.anim:update(1)
    if adone(s) or s.anim.done then s.deleted = true end
  end
  s.z = -s.cz
end

-- ---------------------------------------------------------------------------
-- the parts' own frames (sub_0802D86C by type)
-- ---------------------------------------------------------------------------
function G:partTick(e, pt)
  local f = self.field
  local b, h = e.body, e.h
  local p = f.player
  local t = pt.type
  if t == 1 or t == 2 then
    if t == 1 and pt.type2 == 1 then pt.collide = (b.u80 == 0 and pt.draw) end
    if not pt.draw then return end
    pt.iframes = b.iframes
    if pt.iframes == 0 then
      if pt.subtimer == 0 then self:pal(pt, 0xC9) else pt.subtimer = pt.subtimer - 1; self:pal(pt, 0xCA) end
    end
    if b.u80 == 0 then return end
    if math.abs(pt.x - p.x) <= 8 and math.abs(pt.y - p.y) <= 8 then
      e.field14 = true
      e.linkOY = -4
    end
  elseif t == 4 then
    if band(fflags(pt), 0xFF) == 0 and not pt.started then pt.anim:update(1); if (pt.anim.flags or 0) == 0 then return end end
    pt.started = true
    pt.z = pt.z + pt.zv; pt.zv = pt.zv - 24 / 256
    if pt.z > 0 then return end
    pt.z = 0
    b.u7b = 1
    for i = 0, 7 do self:burst(e, pt, i) end
    self:sfx(SFX.S150)
    pt.deleted = true
    h.entity1 = nil
  elseif t == 5 or t == 6 then
    if band(f.frame or 0, 1) ~= 0 and b.action == 2 then return end
    if t == 5 then step(pt) else pt.anim:update(1) end
    if not adone(pt) then return end
    local n = self:part(t == 5 and 6 or 3, b.x, b.y)
    n.parent = b
    n.prio = 6
    if t == 5 then self:anim(n, 0x50)
    else
      n.timer = hi(h.f[0])
      n.u74, n.u75 = self.T.u8(G.ADDR.PLUG), 0
      self:anim(n, 0x4F)
      n.frameIndex = nil
    end
    pt.deleted = true
    h.entity1 = n
  elseif t == 3 then
    if pt.u74 ~= 0 then
      pt.u74 = pt.u74 - 1
      if pt.u74 == 0 then
        pt.u75 = pt.u75 + 2
        pt.u74 = self.T.u8(G.ADDR.PLUG + pt.u75)
        if pt.u74 ~= 0 then self:pal(pt, self.T.u8(G.ADDR.PLUG + pt.u75 + 1)) end
      end
    end
    if pt.caned and pt.u74 == 0 and (pt.zv or 0) <= 0 then
      pt.zv = 3.0
      b.subAction, b.type2, b.u7b = 4, 0, 0
      self:sfx(SFX.BUTTON)
    elseif pt.timer ~= hi(h.f[0]) then
      local fr = pt.frameIndex or 0x28
      if band(pt.timer - hi(h.f[0]), 0x1F) > 0x10 then fr = fr + 1; if fr >= 0x31 then fr = 0x28 end
      else fr = fr - 1; if fr <= 0x27 then fr = 0x30 end end
      pt.frameIndex = fr
      pt.timer = hi(h.f[0])
    end
    pt.caned = nil
    if (pt.zv or 0) <= 0 then return end
    pt.z = pt.z + pt.zv; pt.zv = pt.zv - 24 / 256
    if pt.zv > 0 then return end
    local n = self:part(4, pt.x, pt.y)
    n.parent = b
    n.z, n.zv = pt.z, 0
    n.prio = pt.prio
    self:anim(n, 0x2C, true)
    pt.deleted = true
    h.entity1 = n
  end
end

-- GLEEROK_PARTICLE type 0: the plug's pieces (gUnk_081229D0)
local BURST = { [0] = { 0, 12, 8, 8 }, { 0x40, 0x14, -8, 8 }, { 0x80, 4, 8, -8 }, { 0xC0, 0x1C, -8, -8 },
                { 0, 12, 0, 0 }, { 0x40, 0x14, 0, 0 }, { 0x80, 4, 0, 0 }, { 0xC0, 0x1C, 0, 0 } }
function G:burst(e, src, i)
  local f = self.field
  local d = f:objects():def(0x67, 0) -- GLEEROK_PARTICLE's definition (object $67)
  local B = BURST[i]
  local s = { kind = 6, x = src.x + B[3], y = src.y + B[4], z = 0, anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0,
              layer = 1, direction = i < 4 and B[2] or bor(B[2], band(self:rand(), 3)), speed = 0x100,
              zv = i < 4 and (bor(band(self:rand(), 0x1FFFF), 0x28000) / 65536) or 2.5,
              flipX = band(B[1], 0x40) ~= 0, flipY = band(B[1], 0x80) ~= 0 }
  if d then f:objects():dress(s, d, 0) end
  s.objAnim = i < 4 and 0x56 or 0x57
  s.extUpdate = function(_, me)
    me.anim:update(1)
    local a = (me.direction % 32) / 32 * 2 * math.pi
    me.x, me.y = me.x + math.sin(a), me.y - math.cos(a)
    me.z = me.z + me.zv; me.zv = me.zv - 0.25
    if me.z <= 0 then
      if i < 4 then f:addFx(me.x, me.y, SPECIAL_FX, FX_LAVA_SPLASH) end
      me.deleted = true
    end
  end
  f.entities[#f.entities + 1] = s
  f._dungeon:track(s)
end

-- ---------------------------------------------------------------------------
-- the body's fight (gUnk_080CD810 by subAction)
-- ---------------------------------------------------------------------------
function G:fight(e)
  local f = self.field
  local b, h = e.body, e.h
  local p = f.player
  local sa = b.subAction
  if sa == 0 then -- sub_0802DB84
    b.direction = facing(b.x, b.y, p.x, p.y)
    if hi(h.f[0]) == b.direction then b.subAction, b.u78 = 1, 0 return end
    local d
    if band(hi(h.f[0]) - b.direction, 0x1F) > 0x10 then d = 0; b.timer = band(b.timer, 0xFE) else d = 1; b.timer = 1 end
    b.speed = ({ [0] = 0x30, 0x40, 0x50 })[band(b.u79, 0x7F)] or 0x50
    rotF(h, 5, b.speed, d)
    relax(h); self:layout(e); self:nextAttack(b)
  elseif sa == 1 then -- sub_0802DC1C
    local diff = band(hi(h.f[0]) - facing(b.x, b.y, p.x, p.y), 0x1F)
    if (diff > 0x10 and diff <= 0x1D) or (diff <= 0x10 and diff >= 3) then
      b.subAction = 0; h.ents[5].timer = 0 return
    end
    if b.u78 ~= 0 then b.u78 = b.u78 - 1
    else
      rotF(h, 5, 0x20, b.timer == 1 and 1 or 0)
      if closeTo(h.f[0], h.f[5], 4) then
        if b.timer == 1 then h.f[5] = bor(lshift(band(hi(h.f[0]) - 4, 0x1F), 8), 0xFF)
        else h.f[5] = lshift(band(hi(h.f[0]) + 4, 0x1F), 8) end
        b.timer = bxor(b.timer, 1)
        b.u78 = 0xC
      end
    end
    self:reach(e); relax(h); self:layout(e); self:nextAttack(b)
  elseif sa == 2 then -- sub_0802DCE0
    local hd = h.ents[5]
    if hd.timer ~= 12 then
      b.direction = facing(b.x, b.y, p.x, p.y)
      if hi(h.f[5]) == b.direction then hd.timer, b.u82, b.subtimer = 12, 4, 0
      else
        rotF(h, 5, 0x20, band(hi(h.f[5]) - b.direction, 0x1F) > 0x10 and 0 or 1)
        relax(h)
      end
    else
      if b.subtimer < 6 then
        if b.u82 == 0 then
          b.u82 = 4
          h.ents[b.subtimer].subtimer = 4
          b.subtimer = b.subtimer + 1
        else b.u82 = b.u82 - 1 end
      elseif hd.subtimer == 0 then
        self:projectile(e, 0)
        hd.timer = 0
        if b.u74 == 0 then b.u74 = 1
        else b.subAction = 0; self:pickWait(b) end
      end
    end
    self:layout(e)
  elseif sa == 3 then -- sub_0802DDD8
    local n = 4
    if b.u76 ~= 0 then n = 6; if b.u79 == 2 and band(self:rand(), 1) == 0 then n = 0xC end end
    if b.type2 == 0 then
      if not followF(h) then
        b.type2, b.subtimer = 1, 0
        if band(self:rand(), 1) == 0 then b.direction = 0; b.u7a = band(hi(h.f[0]) + n, 0x1F)
        else b.direction = 1; b.u7a = band(hi(h.f[0]) - n, 0x1F) end
      end
    else
      if b.type2 ~= 1 then
        local r2, r8, r4
        if b.u76 == 0 then r2, r8, r4 = 1, 2, 1 else r2, r8, r4 = 2, 6, 0 end
        if h.ents[5].subtimer == 1 then self:projectile(e, r2) end
        if b.u74 == 0 then
          b.u74 = r4
          h.ents[b.subtimer].subtimer = r8
          b.subtimer = b.subtimer + 1
          if b.subtimer > 5 then b.subtimer = 0 end
        else b.u74 = b.u74 - 1 end
      end
      if b.type2 == 1 then rotF(h, 5, 0x40, b.direction)
      elseif b.u76 == 0 then rotF(h, 5, 0x20, b.direction)
      else rotF(h, 5, 0x10, b.direction) end
      relax(h)
      if b.u7a == hi(h.f[5]) then
        if b.type2 == 1 then
          b.type2 = 2
          b.direction = bxor(b.direction, 1)
          if b.direction == 1 then b.u7a = band(b.u7a - n * 2, 0x1F); b.timer = 1
          else b.u7a = band(b.u7a + n * 2, 0x1F); b.timer = band(b.timer, 0xFE) end
          h.ents[5].timer = 12
        else
          b.subAction = 0
          h.ents[5].timer = 0
          self:pickWait(b)
        end
      end
    end
    self:layout(e)
  elseif sa == 4 then -- sub_0802DFA8
    local t2 = b.type2
    if t2 == 0 then self:knocked(e)
    elseif t2 == 1 or t2 == 2 then self:lower(e)
    elseif t2 == 3 then self:open(e)
    elseif t2 == 4 then self:sink(e)
    elseif t2 == 5 then self:recover(e) end
  elseif sa == 5 then self:rise(e) end -- sub_0802E430
end

function G:knocked(e) -- sub_0802DFC0
  local b, h = e.body, e.h
  local v = band(hi(h.f[0]), 7)
  if v ~= 0 then
    b.direction = v > 4 and 0 or 1
    rotF(h, 0, 0x20, b.direction)
    followF(h)
  elseif not followF(h) and b.u7b ~= 0 then
    b.collide = true
    b.type2 = 1
    h.ents[5].timer = 24
    self:sfx(SFX.BOSS_HIT)
  end
  self:layout(e)
end

function G:lower(e) -- sub_0802E034
  local b, h = e.body, e.h
  local val
  if b.type2 == 1 then b.direction = 2; val = 0
  else b.direction = 3; val = self.T.u8(G.ADDR.LOWER + rshift(hi(h.f[0]), 3)) end
  if val ~= hi(h.g[0]) then
    rotG(h, 0, 0x40, b.direction)
    followG(h, 0x40, 2)
  elseif not followG(h, 0x80, 2) then
    if b.type2 == 2 then
      b.u7c = 0x168
      b.u80 = 1
      h.ents[5].timer = 0
    end
    b.type2 = b.type2 + 1
    h.g[0] = setHi(h.g[0], 1)
  end
  self:layout(e)
end

function G:open(e) -- sub_0802E0B8
  local f = self.field
  local b = e.body
  local p = f.player
  local v = band(b.anim.frame and fflags(b) or 0, 0x3F)
  if v ~= 0 and dist16(b.x, b.y, p.x, p.y) <= v * 16 then e.field14 = true; e.linkOY = -6 end
  if self.T.u8(G.ADDR.HEALTH + band(b.u79, 0x7F)) >= e.health then
    if b.u79 > 1 then
      e.health = 0
      b.action = 0
      e.dyingG = true
      b.dAction = 0
      self:sfx(SFX.BOSS_DIE)
      return
    else
      b.collide = false
      b.u79 = bor(b.u79 + 1, 0x80)
      e.health = 0xFF
      if b.u7c > 0x78 then b.u7c = 0x78 end
    end
  end
  b.u7c = b.u7c - 1
  if b.u7c < 0 then
    b.collide = false
    b.spriteOX = 0
    b.type2 = 4
    self:anim(b, 0x4E, true)
  elseif b.u7c < 0x78 then
    b.spriteOX = bxor(b.spriteOX or 0, 1)
  end
  self:layout(e)
end

function G:sink(e) -- sub_0802E1D0
  local f = self.field
  local b, h = e.body, e.h
  local p = f.player
  if not adone(b) then b.anim:update(1) end
  local fl = fflags(b)
  local v = band(fl, 0x3F)
  if v ~= 0 and dist16(b.x, b.y, p.x, p.y) <= v * 16 then e.field14 = true; e.linkOY = -6 end
  if band(fl, 0x40) ~= 0 then -- (the frame byte keeps its bits for the whole keyframe: a joint a frame)
    for i = 0, 5 do
      if h.u30[i] ~= 0 then
        h.u30[i] = h.u30[i] - 1
        if h.u30[i] == 0 then
          f:addFx(h.ents[0].x, h.ents[0].y, SPECIAL_FX, FX_LAVA_SPLASH)
          self:sfx(SFX.S124)
          if i == 5 then
            if band(b.u79, 0x80) == 0 then
              b.u7c = 0xF0
              f:shake(240, 0)
            else
              for k = 0, 3 do self:lavaParticle(e, k) end
              b.u7c = 0xB
              b.u74, b.u75 = 0, 0x10
              f:shake(30, 0)
            end
            b.type2 = 5
          end
        end
        break
      end
    end
  end
  self:layout(e)
end

function G:recover(e) -- sub_0802E300
  local f = self.field
  local b, h = e.body, e.h
  local p = f.player
  if band(b.u79, 0x80) == 0 then b.u7c = b.u7c - 1
  elseif b.u74 ~= 0x10 and b.u7c ~= 0 then
    b.u7c = b.u7c - 1
    if b.u7c == 0 then b.u7c = 0xB; b.u75 = b.u75 - 1; b.u74 = b.u74 + 1 end
  end
  if b.u7c == 0 then
    if band(b.u79, 0x80) ~= 0 and b.u75 ~= 0x10 then
      b.u7c = 0xB; b.u75 = b.u75 + 1; b.u74 = b.u74 - 1
      return
    end
    b.u79 = band(b.u79, 0x7F)
    local dir = lshift(rshift(band(facing(b.x, b.y, p.x, p.y) + 4, 0x1F), 3), 3) -- GetAnimationStateForDirection4 << 3
    for i = 0, 5 do h.g[i] = 0; h.f[i] = setHi(h.f[i], dir) end
    b.subAction, b.type2, b.u80 = 5, 0, 0
    self:anim(b, 0x4D, true)
    local n = self:part(5, b.x, b.y)
    n.parent = b
    n.prio = 6
    self:anim(n, 0x2D, true)
    h.entity1 = n
    h.ents[5].timer = 24
  elseif band(f.frame or 0, 0xF) == 0 then
    self:projectile(e, 3)
  end
  self:layout(e)
end

function G:rise(e) -- sub_0802E430 -> gUnk_080CD848[type2]
  local f = self.field
  local b, h = e.body, e.h
  if b.type2 == 0 then -- sub_0802E448
    for i = 5, 0, -1 do
      if h.u30[i] == 0 then
        f:addFx(h.ents[0].x, h.ents[0].y, SPECIAL_FX, FX_LAVA_SPLASH)
        self:sfx(SFX.LAND)
      end
      if h.u30[i] ~= 10 then
        h.u30[i] = h.u30[i] + 1
        if h.u30[i] == 10 and i == 0 then b.type2 = 1 end
        break
      end
    end
    if hi(h.g[5]) <= 9 then rotG(h, 5, 0x40, 3) end
    b.anim:update(1)
    relax(h); self:layout(e)
  else -- sub_0802E4C0
    b.anim:update(1)
    if adone(b) then
      if b.action ~= 2 then
        b.u74, b.u75 = 0, 8
        if b.u79 ~= 0 then b.u76, b.u77 = 0, 3 end
        self:nextAttack(b)
      else
        b.type2 = b.type2 + 1
      end
    end
    self:layout(e)
  end
end

-- GLEEROK_PARTICLE type 1 (type2 0..3): the four lava pools of a phase
-- change.  gUnk_081229F0: offset, x / y anchor modes, flips; frameIndex 75,
-- hit type $7A on layer 2.  Action1 $CE frames; Action2 600 frames: both
-- scales (8.8 in the high half, $100 = 1x, smaller = bigger) shrink by
-- speed ($7000, -$100 a frame down to $2000), the anchored offsets by
-- sub_0806FCF4(scale, $20, mode), the hitbox $10000 / scale >> 3; Action3
-- $78 frames; Action4 the scales back by 1 a frame to $100, 2 more frames,
-- then the body's unk_7c = 0 (and gone once the body's bit 7 is clear).
local POOLS = { [0] = { -32, -40, 1, 2, 0 }, { 0x1F, -40, 3, 2, 0x40 }, { -32, 0x17, 1, 0, 0x80 }, { 0x1F, 0x17, 3, 0, 0xC0 } }
local function anchor(scale, mode) -- sub_0806FCF4(.., $20, mode)
  local v = math.abs(scale)
  v = math.floor(0x10000 / v)
  local r2 = 0x20 - math.floor(0x20 * v / 256)
  if mode == 0 or mode == 3 then r2 = -r2 end
  return r2
end
G.anchor = anchor
function G:lavaParticle(e, k)
  local b = e.body
  local P = POOLS[k]
  local pt = { type = 7, x = b.x + P[1], y = b.y + P[2], xmode = P[3], ymode = P[4], u7c = 0xCE, action = 1, speed = 0x7000,
               sx = band(P[5], 0x40) ~= 0 and -0x100 * 65536 or 0x100 * 65536, sy = band(P[5], 0x80) ~= 0 and -0x100 * 65536 or 0x100 * 65536,
               ox = 0, oy = 0, hw = 32, hh = 32, hitType = 0x7A }
  local d = self.field:objects():def(0x67, 1)
  if d then
    pt.sprite, pt.gfx = d.sprite, Assets.gfxSource(d.gfxType, d.gfx)
    pt.palette = self.A:objPalette(d.palette, self.field.room.atlas and self.field.room.atlas.palettes)
  end
  e.pools = e.pools or {}
  e.pools[#e.pools + 1] = pt
end
local function hiS(w) return math.floor(w / 65536) end
function G:poolTick(e, pt)
  local b = e.body
  local u2, u5
  if pt.action == 1 then
    pt.u7c = pt.u7c - 1
    if pt.u7c == -1 then pt.u7c, pt.action = 600, 2 end
  elseif pt.action == 2 then
    if pt.sx < 0 then pt.sx = pt.sx + pt.speed; u2 = -hiS(pt.sx) else pt.sx = pt.sx - pt.speed; u2 = hiS(pt.sx) end
    if pt.sy < 0 then pt.sy = pt.sy + pt.speed; u5 = -hiS(pt.sy) else pt.sy = pt.sy - pt.speed; u5 = hiS(pt.sy) end
    if pt.speed > 0x2000 then pt.speed = pt.speed - 0x100 end
    pt.u7c = pt.u7c - 1
    if pt.u7c == -1 then
      pt.sx, pt.sy = hiS(pt.sx) * 65536, hiS(pt.sy) * 65536
      pt.action, pt.u7c = 3, 0x78
    else
      local o1, o2 = anchor(hiS(pt.sx), pt.xmode), anchor(hiS(pt.sy), pt.ymode)
      if pt.xmode == 0 or pt.xmode == 2 then pt.oy = o1 else pt.ox = o1 end
      if pt.ymode == 0 or pt.ymode == 2 then pt.oy = o2 else pt.ox = o2 end
    end
    pt.hw, pt.hh = rshift(math.floor(0x10000 / math.max(1, u2)), 3), rshift(math.floor(0x10000 / math.max(1, u5)), 3)
  elseif pt.action == 3 then
    pt.u7c = pt.u7c - 1
    if pt.u7c == -1 then pt.action, pt.u7c = 4, 2 end
  elseif pt.action == 4 then
    local hx = hiS(pt.sx)
    if hx == 0x100 or hx == -0x100 then
      if pt.u7c == 0 then
        b.u7c = 0
        if band(b.u79, 0x80) == 0 then pt.deleted = true end
      else pt.u7c = pt.u7c - 1 end
    else
      if pt.sx < 0 then pt.sx = pt.sx - 65536 else pt.sx = pt.sx + 65536 end
      if pt.sy < 0 then pt.sy = pt.sy - 65536 else pt.sy = pt.sy + 65536 end
      u2, u5 = math.abs(hiS(pt.sx)), math.abs(hiS(pt.sy))
      local o1, o2 = anchor(hiS(pt.sx), pt.xmode), anchor(hiS(pt.sy), pt.ymode)
      if pt.xmode == 0 or pt.xmode == 2 then pt.oy = o1 else pt.ox = o1 end
      if pt.ymode == 0 or pt.ymode == 2 then pt.oy = o2 else pt.ox = o2 end
      pt.hw, pt.hh = rshift(math.floor(0x10000 / math.max(1, u2)), 3), rshift(math.floor(0x10000 / math.max(1, u5)), 3)
    end
  end
  if not pt.deleted then self:touchLink(pt.x + pt.ox, pt.y + pt.oy, { x = 0, y = 0, w = pt.hw, h = pt.hh }, pt.hitType, 0) end
end
function G:drawPool(pt, camX, camY)
  if not pt.sprite then return end
  local img, ox, oy = self.field.assets:spriteFrame(pt.sprite, 75, pt.palette, "gleerokpool", pt.gfx)
  if not img then return end
  local kx, ky = 256 / hiS(pt.sx), 256 / hiS(pt.sy)
  local x, y = math.floor(pt.x + pt.ox - camX), math.floor(pt.y + pt.oy - camY)
  love.graphics.setColor(1, 1, 1, 0.75)
  love.graphics.draw(img, x + ox * kx, y + oy * ky, 0, kx, ky)
  love.graphics.setColor(1, 1, 1, 1)
end

-- ---------------------------------------------------------------------------
-- the intro (gUnk_080CD7E4 by subAction)
-- ---------------------------------------------------------------------------
function G:intro(e)
  local f = self.field
  local b, h = e.body, e.h
  local p = f.player
  local sa = b.subAction
  if sa == 0 then -- sub_0802D674
    if (p.z or 0) ~= 0 then return end
    if b.u7c == 0x96 then self:sfx(SFX.BOSS_HIT) end
    b.u7c = b.u7c - 1
    local v = b.u7c
    if v == -1 then
      b.subAction, b.u7c = 1, 0x5A
      e.camOnBoss = true
      self:sfx(SFX.BOSS_HIT)
    elseif v <= 0x3C then
      if v == 0x3C then p.bubble = "!" end
      p.animationState = 0
    elseif v <= 0x59 then p.animationState = 2
    elseif v <= 0x77 then p.animationState = 6 end
  elseif sa == 1 then -- sub_0802D6F0
    b.u7c = b.u7c - 1
    if b.u7c == -1 then b.subAction, b.u7c = 2, 0x5A; f:shake(150, 0) end
  elseif sa == 2 then -- sub_0802D714
    b.u7c = b.u7c - 1
    if b.u7c ~= -1 then return end
    for i = 0, 5 do h.g[i] = 0; h.f[i] = setHi(h.f[i], 0x10) end
    b.subAction, b.type2 = 3, 0
    b.draw = true
    self:anim(b, 0x4D, true)
    local n = self:part(5, b.x, b.y)
    n.parent = b
    n.prio = 6
    self:anim(n, 0x2D, true)
    h.entity1 = n
    h.ents[5].timer = 24
  elseif sa == 3 then -- sub_0802D77C
    if band(f.frame or 0, 1) ~= 0 then return end
    self:rise(e)
    if b.type2 ~= 2 then return end
    b.subtimer, b.timer, b.subAction = 0, 0, 4
    h.ents[5].timer = 12
  elseif sa == 4 then -- sub_0802D7B4
    local M = self.moves or G.introMoves(self.T)
    self.moves = M
    if b.timer == 0 then
      if (M[b.subtimer] or 0xFF) == 0xFF then
        b.subtimer, b.timer, b.action, b.subAction = 0, 0, 1, 0
        h.ents[5].timer = 24
        e.camOnBoss = nil
        p.state, p.extUpdate, p.animId = "normal", nil, -1
        e.lockLink = nil
        f:bgm(BGM_BOSS_THEME)
        return
      end
      b.timer = M[b.subtimer]
      b.direction = M[b.subtimer + 1]
      b.subtimer = b.subtimer + 2
      self:sfx(SFX.BOSS_HIT)
    else b.timer = b.timer - 1 end
    if b.direction <= 1 then rotF(h, 5, 0x40, b.direction)
    elseif b.direction ~= 0xFF then rotG(h, 5, 0x40, b.direction) end
    relax(h); self:layout(e)
  end
end

-- ---------------------------------------------------------------------------
-- the death (Gleerok_OnDeath type 0 by action, then the parts')
-- ---------------------------------------------------------------------------
function G:death(e)
  local f = self.field
  local b, h = e.body, e.h
  local p = f.player
  e.field14 = true -- gPlayerState.field_0x14 = 1
  local v = band(fflags(b), 0x3F)
  if v ~= 0 and dist16(b.x, b.y, p.x, p.y) <= v * 16 then e.linkOY = -6 end
  p.state, p.extUpdate = "ext", function() end -- PausePlayer
  local a = b.dAction
  if a == 0 then b.dAction = 1; e.fade = 8
  elseif a == 1 or a == 2 then
    if (e.fade or 0) > 0 then e.fade = e.fade - 1 return end
    if a == 1 then
      h.f[0] = setHi(h.f[0], 0x10)
      h.g[0] = setHi(h.g[0], 0x10)
      if not followG(h, 0x40, 2) and not followF(h) then
        b.dAction = 2
        local r = f.room
        p.x, p.y = 0x98, 0xD8
        p.animationState = 0
        e.camOnBoss = true
        e.fade = 8
      end
    else
      b.dAction = 3
      b.u80 = 0
      h.ents[5].timer = 24
      h.g[0] = setHi(h.g[0], 0)
    end
  elseif a == 3 then -- sub_0802D218
    if followG(h, 0x40, 2) then self:layout(e); self:order(e) return end
    b.dAction, b.timer, b.subtimer = 4, 0, 0
    b.u7c = 0xB4
    h.ents[5].timer = 12
    e.camHold = 0x168 -- GLEEROK_PARTICLE type 2
  elseif a == 4 then -- sub_0802D258
    if b.u7c == 0 then
      self:sink(e)
      if b.type2 == 5 then b.dAction = 5 return end
    else
      b.u7c = b.u7c - 1
      if b.u7c == 0 then self:anim(b, 0x4E, true); b.type2 = 4 end
    end
    if b.timer == 0 then
      b.timer = THRASH[b.subtimer + 1]
      b.direction = THRASH[b.subtimer + 2]
      b.subtimer = band(b.subtimer, 0x3F) + 2
    else b.timer = b.timer - 1 end
    if b.direction <= 1 then rotF(h, 5, 0x40, b.direction)
    elseif b.direction ~= 0xFF then rotG(h, 5, 0x40, b.direction) end
    if band(f.frame or 0, 0x1F) == 0 then self:sfx(SFX.BOSS_DIE) end
    if band(f.frame or 0, 0xF) == 0 then
      local k = band(self:rand(), 5)
      local s = h.ents[k]
      if s then f:addFx(s.x, s.y, SPECIAL_FX, FX_GIANT_EXPLOSION3) end
    end
    relax(h)
  elseif a == 5 then -- sub_0802D33C: the segments go, the head evaporates
    for i = 0, 3 do h.ents[i].gone = true end
    h.ents[4].dieT = 18
    self:sfx(SFX.BOSS_DIE)
    h.ents[5].draw = false
    b.dAction = 6
    b.evap = 0
    b.draw = false
    if h.entity1 then h.entity1.deleted = true; h.entity1 = nil end
    self:sfx(SFX.EVAPORATE)
  elseif a == 6 then -- the head's OnDeath (type 2): BG1 blends away, a step every 16 frames
    b.evap = b.evap + 1
    if h.ents[4].dieT then h.ents[4].dieT = h.ents[4].dieT - 1; if h.ents[4].dieT <= 0 then h.ents[4].gone = true; h.ents[4].dieT = nil end end
    if b.evap == 60 then self:sfx(SFX.APPARATE) end
    local steps = math.floor(b.evap / 16)
    f.room.topAlpha = math.max(0, (16 - steps) / 16)
    if steps >= 16 then
      f.room.topUnder, f.room.hideTop, f.room.topAlpha = nil, true, nil
      p.state, p.extUpdate, p.animId = "normal", nil, -1
      e.camOnBoss = nil
      if e.ownsCam then f.cameraTarget = nil; e.ownsCam = nil end
      e.dyingG = nil
      f.bossSupport = nil
      e.dead = true
      self.en:kill(e)
    end
    return
  end
  self:layout(e); self:order(e)
end

-- ---------------------------------------------------------------------------
-- the frame
-- ---------------------------------------------------------------------------
function G:update(e)
  local f = self.field
  local b, h = e.body, e.h
  local p = f.player
  if e.dead then return end
  e.field14, e.linkOY = nil, nil
  if b.iframes > 0 then b.iframes = b.iframes - 1 end
  e.iframes = b.iframes
  if e.dyingG then
    self:death(e)
  elseif b.action == 2 then
    self:intro(e); self:order(e)
  elseif b.action == 1 then
    self:fight(e); self:order(e)
  end
  -- the other parts, in creation order
  for i = 0, 5 do local s = h.ents[i]; if not s.gone then self:partTick(e, s) end end
  if h.entity1 and not h.entity1.deleted then self:partTick(e, h.entity1) end
  if e.pools then
    for i = #e.pools, 1, -1 do local pt = e.pools[i]; self:poolTick(e, pt); if pt.deleted then table.remove(e.pools, i) end end
  end
  if e.camHold then e.camHold = e.camHold - 1; if e.camHold < 0 then e.camHold = nil end end
  -- the body's core: the sword (Enemies:swordHits -> swordHit) and touching Link
  if b.collide and not e.dyingG then self:touchLink(b.x, b.y, b.hitbox, b.hitType, 0) end
  local s1 = h.ents[0]
  if s1.collide and not e.dyingG and not s1.gone then self:touchLink(s1.x, s1.y, s1.hitbox, s1.hitType, 0) end
  -- Link held up by the neck / the shell (field_0x14): the lava does not burn
  f.bossSupport = function() return e.field14 == true end
  if e.linkOY then f.player.spriteOY, f.player.spriteOYFrame = e.linkOY, f.frame end
  -- the camera on the boss (gRoomControls.camera_target)
  if e.camOnBoss or e.camHold then f.cameraTarget = b; e.ownsCam = true
  elseif e.ownsCam then f.cameraTarget = nil; e.ownsCam = nil end
  -- the Cane's bolt on the plug (contact $1D)
  local plug = h.entity1
  if plug and plug.type == 3 then
    for _, o in ipairs(f.entities) do
      if o.bolt and not o.deleted and o.action == 1 and math.abs(o.x - plug.x) < 10 and math.abs(o.y - (plug.y - (plug.z or 0))) < 12 then
        plug.caned = true
        o.life = 0
      end
    end
  end
  e.x, e.y = h.ents[5].x, h.ents[5].y
end

-- the sword: the core (the body, while its collision is on)
function G:swordHit(e, box)
  local b = e.body
  if not b.collide or e.dyingG or b.iframes > 0 then return false end
  local hb = b.hitbox
  if math.abs((b.x + (hb.x or 0)) - box.x) < (hb.w or 8) + box.w and math.abs((b.y + (hb.y or 0)) - box.y) < (hb.h or 8) + box.h then
    local s = self.en:settings(b.hitType or 0, 4) or { orgDmg = 2, tgtIfr = 12 }
    local dmg = math.max(s.orgDmg or 2, 1)
    e.health = e.health - dmg
    b.iframes = (s.tgtIfr and s.tgtIfr > 0) and s.tgtIfr or 12
    self:sfx(SFX.BOSS_HIT)
    for i = 0, 5 do e.h.ents[i].subtimer = 0 end
    return true
  end
  return false
end

function G:drawPart(pt, camX, camY)
  local f = self.field
  local frame = pt.frameIndex or pt.anim.frame
  if not pt.sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = f.assets:spriteFrame(pt.sprite, frame, pt.palette, "gleerok" .. pt.sprite .. ":" .. tostring(pt.palNow or pt.palId), pt.gfx)
  if not img then return end
  local x, y = math.floor(pt.x - camX + (pt.spriteOX or 0)), math.floor(pt.y - camY - (pt.z or 0))
  local hf = pt.anim:hflip() ~= (pt.flipX or false)
  if hf then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
end

function G:draw(e, camX, camY)
  if e.dead then return end
  local b, h = e.body, e.h
  local list = {}
  if b.draw ~= false then list[#list + 1] = b end
  for i = 0, 5 do local s = h.ents[i]; if s.draw and not s.gone then list[#list + 1] = s end end
  if h.entity1 and not h.entity1.deleted then list[#list + 1] = h.entity1 end
  for i, pt in ipairs(list) do pt._seq = i end
  table.sort(list, function(a, c) if a.prio ~= c.prio then return a.prio > c.prio end return a._seq < c._seq end)
  for _, pt in ipairs(e.pools or {}) do self:drawPool(pt, camX, camY) end
  for _, pt in ipairs(list) do
    if not (pt.iframes and pt.iframes > 0 and pt.iframes % 4 < 2 and pt == b) then self:drawPart(pt, camX, camY) end
  end
end

return G
