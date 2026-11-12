-- Round 16: Big Green ChuChu ($13), src/enemy/chuchuBoss.c ported.
--
-- PARTS (ChuchuBoss_Init, type 0 makes the others): the base (type 0) on
-- the ground, its lower body (type 3, "unk_68"), middle (type 2, the
-- base's parent) and head (type 1, the base's child).  Every part is an
-- affine sprite: x / y scales unk_74 / unk_78 ($100 = 1x, larger is
-- smaller: $A0 draws 1.6x), angle unk_7e = -(its swing angle).  The parts
-- hang one above the other: each sits `timer` px from the one below along
-- its swing angle unk_82 (sub_08027870 / sub_0802757C / LinearMoveAngle);
-- `timer` follows the head's height scale (squashed: shorter, stretched:
-- taller).  The swing of each part runs between +-unk_81 at unk_86 a frame
-- (tables gUnk_080CC27C head / gUnk_080CC29C middle / gUnk_080CC2BC
-- lower, sub_080276F4), the head waiting at each end until the middle has.
--
-- THE BASE (sub_08026110) runs the fight by subAction:
--   0 intro (sub_0802626C, unk_03 0..9): Link walks in and looks round,
--     goo drops fall (gUnk_080CC234 timings), the boss falls from z -192,
--     lands (shake, SFX_1A1), squashes and stands up, BGM_BOSS_THEME
--   1 idle (sub_08026580): bounces (its scale between unk_82.LO and unk_81
--     at unk_80), then 2 (sub_08026634): creeps after Link at $C0 ($100
--     in the third phase), counting bounces (gUnk_080CC24F), then 3
--     (sub_08026750) squash / stretch and 4 (sub_0802686C) the jump at
--     him: zVelocity 7.0, speed $180, gravity $4000; 5 (sub_080268C8) the
--     landing (shake, SFX_1A1), squash, back to 1.  The third phase jumps
--     up to four times in a row (unk_01 $81, unk_00).
--   The Gust Jar on the base (sub_08027AA4, contact $13; iframes 3): each
--     contact counts (unk_06); every third one swells it by 8 (unk_05,
--     added to its scale bounds); at $80 (48 contacts) it is about to
--     topple (unk_01 = $40, hit type 0): 10 (sub_08027064) it hops to the
--     room's middle (unk_0e = its start x), sways, and topples toward Link
--     (or after five sways): 6 (sub_0802694C) lean (15 frames), fall over
--     (the angles open to $20 / $44 / $40, shake $20, SFX_10B, a splash),
--     lie for gUnk_080CC278[rand & 3] frames (150..250) -- the head can be
--     hit then -- 7 (sub_08026C40) it rights itself, 8 (sub_08026E1C): if
--     the head's health fell under (u8)gUnk_080CC2DC[phase] (-7, -9, -7:
--     7 / 9 / 7 damage from $FF) the phase advances (unk_04) and the head
--     heals to $FF; 11 (sub_08026F1C) an angry double bounce; back to 1.
--   The head hit while it lies (sub_080272D4 case 6): SFX_BOSS_HIT; the
--     blow that ends the third phase: SFX_BOSS_DIE, 9 (sub_08026FA4) it
--     collapses; after phase 3 the base's health is 0: 12 (OnDeath) 120
--     frames of explosions (FX_GIANT_EXPLOSION3, denser near the end),
--     SFX_BOSS_DIE, the death.
-- SIMPLIFIED: the goo drops (CHUCHU_BOSS_START_PARTICLE, 331 lines) and the
-- landing splash (CHUCHU_BOSS_PARTICLE, sprite $C9) are drawn as simple
-- falling drops / the splash sprite; the hitbox proxy (type 8) is not a
-- separate entity (the head is hit directly); the Gust Jar's blow (contact
-- $1B) knocks nothing back; unk_08 (the swell's 180-frame hold) is never
-- counted down on the cartridge either -- the swell only goes after a fall.
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local C = {}
C.__index = C

local SFX = { S1A1 = 0x1A1, S1A2 = 0x1A2, S155 = 0x155, S10B = 0x10B, S19E = 0x19E, HIT = 0x127, DIE = 0x128,
              SPLASH = 0x84, JUMP = 0x7C }
local BGM_BOSS = 0x2E
local SPECIAL_FX, FX_GIANT_EXPLOSION3 = 0x0F, 0x48 -- round 17: was $49 (FX_GREEN_ORB); effects.h counts FX_GIANT_EXPLOSION3 = $48
-- gUnk_080CC234: the drops' timings ($FF ends)
local DROPS = { 0x3C, 0x1E, 0x1E, 0x1E, 0x1E, 0x0F, 0x0F, 0x0F, 0x04, 0x04, 0x04, 0x04, 0x04, 0x04, 0x0A, 0x0A,
                0x0A, 0x0F, 0x0F, 0x0F, 0x1E, 0x1E, 0x2D, 0x0A, 0x5A, 0x1E, 0xFF }
local BOUNCES = { [0] = 2, 2, 4, 4, 4, 6, 6, 8 }      -- gUnk_080CC24F
local LIE = { [0] = 150, 180, 210, 250 }               -- gUnk_080CC278
local NEED = { [0] = 249, 247, 249 }                  -- (u8)gUnk_080CC2DC
-- swing tables {step, amplitude}: head gUnk_080CC27C, middle gUnk_080CC29C, lower gUnk_080CC2BC
local T_HEAD = { [0] = { 0x80, 0x8 }, { 0x100, 0x6 }, { 0x80, 0x18 }, { 0x100, 0x8 }, { 0x180, 0x6 }, { 0x100, 0x10 }, { 0, 0 }, { 0xA0, 0x18 } }
local T_MID  = { [0] = { 0x80, 0x8 }, { 0x100, 0x4 }, { 0x80, 0xC }, { 0x80, 0x6 }, { 0x200, 0x6 }, { 0x100, 0xC }, { 0, 0 }, { 0xA0, 0x14 } }
local T_LOW  = { [0] = { 0x80, 0x8 }, { 0x100, 0x0 }, { 0x60, 0x2 }, { 0x80, 0x2 }, { 0x200, 0x6 }, { 0x100, 0x8 }, { 0, 0 }, { 0xA0, 0x10 } }

local function s8(v) v = band(math.floor(v), 0xFF); if v >= 128 then return v - 256 end return v end
local function u8(v) return band(math.floor(v), 0xFF) end
local function hiAng(p) return s8(rshift(band(p.ang16, 0xFFFF), 8)) end
local function addAng(p, d) p.ang16 = band(p.ang16 + d, 0xFFFF) end
local function setAng(p, v) p.ang16 = band(v, 0xFFFF) end
local function polar(len, ang)
  local a = ang * math.pi / 128
  return math.sin(a) * len, -math.cos(a) * len
end
local function vertical(dir) return band(dir, 0x10) ~= 0 end -- DirectionIsVertical
local function facing(ax, ay, bx, by)                         -- GetFacingDirection (0..31)
  local a = math.atan2(bx - ax, -(by - ay))
  return band(math.floor(a / (2 * math.pi) * 32 + 0.5), 31)
end

function C.new(field, enemies)
  return setmetatable({ field = field, en = enemies, A = field.assets }, C)
end

local function newPart(t, x, y)
  return { type = t, x = x, y = y, s74 = 0xA0, s78 = 0xA0, ang16 = 0, dir85 = 0, step = 0, amp = 0, wait = 0,
           f84 = 0, timer = 14, subtimer = 0, rot = 0, anim = Anim.new(), iframes = 0, health = 0xFF }
end

function C:partAnim(p, idx)
  if p.animIndex ~= idx then
    p.animIndex = idx
    p.anim:set(self.A:sprite(p.sprite), idx, true)
  end
end

function C:spawn(dat, def)
  local A = self.A
  local e = {
    kind = 3, id = dat.id, form = 0, x = dat.x, y = dat.y, z = 0, boss = true, enemy = true, impl = self, chuchuBoss = true,
    health = 0xFF, hitType = 0x7D, hitbox = { x = 0, y = 4, w = 22, h = 9 }, -- round 17: form 0's damageType $7D, gUnk_080FD238
    def = def or {}, anim = Anim.new(), iframes = 0, kbt = 0, kbx = 0, kby = 0, field82 = 0, interactType = 0,
    subAction = 0, sub = 0, s74 = 0xA0, s78 = 0xA0, minS = 0x90, maxS = 0xB0, rate = 0, btimer = 0,
    c7c = 0, c7d = 0, h00 = 0, h01 = 0x0F, h04 = 0, h05 = 0, h06 = 0, h08 = 0, h0c = 0, h0e = dat.x,
    type2 = 0, speed = 0, direction = 0, zv = 0, hgt = 0, visible = false, drops = {},
  }
  e.low = newPart(3, e.x, e.y - 14)
  e.mid = newPart(2, e.x, e.y - 32)
  e.head = newPart(1, e.x, e.y - 46)
  for _, p in ipairs({ e, e.low, e.mid, e.head }) do
    local t = p == e and 0 or p.type
    local d = self.en:def(dat.id, t) or def or {}
    p.sprite = d.sprite or (def and def.sprite)
    p.gfx = Assets.gfxSource("enemy", d.gfx or (def and def.gfx) or 0)
    p.palette = A:objPalette(d.palette or (def and def.palette) or 0, self.field.room.atlas and self.field.room.atlas.palettes)
  end
  self:partAnim(e, 0)
  self:partAnim(e.head, 0)
  self:partAnim(e.mid, 1)
  self:partAnim(e.low, 2)
  self:chain(e)
  return e
end

-- ---------------------------------------------------------------------------
-- the body's shape
-- ---------------------------------------------------------------------------
-- sub_080276F4: each part's swing from the tables
function C:swingSet(e, i, keep)
  local h, m, l = e.head, e.mid, e.low
  for _, p in ipairs({ h, m, l }) do p.f84 = 0; p.rot = 0 end
  m.wait, l.wait = 0, 0
  h.step, h.amp = T_HEAD[i][1], T_HEAD[i][2]
  l.step, l.amp = T_LOW[i][1], T_LOW[i][2]
  m.step, m.amp = T_MID[i][1], T_MID[i][2]
  if keep == 0 then
    for _, p in ipairs({ h, m, l }) do p.dir85 = 0; p.ang16 = 0 end
    h.wait = (m.step > 0) and (math.floor(m.amp * 128 / m.step) + 1) or 1
  end
end

-- sub_08027B98
local function scales(e, a, b, rate, t)
  e.minS, e.maxS, e.rate = a, b, rate
  e.btimer = (t ~= 0xFF) and t or 1
end

-- sub_08027870: hang the parts from the base along their angles
function C:chain(e)
  local h, m, l = e.head, e.mid, e.low
  m.s74, m.s78, l.s74, l.s78 = h.s74, h.s78, h.s74, h.s78
  for _, p in ipairs({ h, m, l }) do p.rot = -hiAng(p) end
  if l.s78 >= 0xA1 then l.timer = 14 else l.timer = rshift(0xA0 - math.floor(l.s78), 3) + 14 end
  if m.s78 >= 0xA1 then m.timer = 18 - rshift(math.floor(h.s78) - 0xA0, 4) else m.timer = rshift(0xA0 - math.floor(m.s78), 2) + 18 end
  if h.s78 >= 0xA1 then
    local v = u8(14 - rshift(math.floor(h.s78) - 0xA0, 2))
    h.timer = (band(v, 0x80) ~= 0) and 0 or v
  else
    local d = 0xA0 - math.floor(h.s78)
    h.timer = ((h.s78 < 0x80) and rshift(d, 2) or rshift(d, 1)) + 14
  end
  local dx, dy = polar(l.timer, hiAng(l)); l.x, l.y = e.x + dx, e.y + dy
  dx, dy = polar(m.timer, hiAng(m)); m.x, m.y = l.x + dx, l.y + dy
  dx, dy = polar(h.timer, hiAng(h)); h.x, h.y = m.x + dx, m.y + dy
end

-- sub_080277F8: straight up (no swing), heights from the head's squash
function C:stack(e)
  local h, m, l = e.head, e.mid, e.low
  l.x, l.timer, l.y = e.x, 14, e.y - 14
  m.x = e.x
  m.timer = 18 - rshift(math.floor(h.s78) - 0xA0, 4)
  m.y = l.y - m.timer
  h.x = e.x
  if h.s78 >= 0xA1 then
    local v = u8(14 - rshift(math.floor(h.s78) - 0xA0, 2))
    h.timer = (band(v, 0x80) ~= 0) and 0 or v
  else h.timer = 14 end
  h.y = m.y - h.timer
  m.s74, m.s78, l.s74, l.s78 = h.s74, h.s78, h.s74, h.s78
end

-- sub_0802757C: one part swings and hangs from the one below
function C:swing(e, p)
  local parent = (p == e.low) and e or (p == e.mid and e.low or e.mid)
  local child = (p == e.low) and e.mid or (p == e.mid and e.head or nil)
  if p.wait ~= 0 then
    if p.type ~= 1 then
      if child and child.wait ~= 0 then p.wait = 0 end
    else p.wait = p.wait - 1 end
  else
    local function rest()
      if p.type == 1 then
        local m = e.mid
        p.wait = (m.step > 0) and (math.floor(m.amp * 256 / m.step) + 1) or 1
      else p.wait = 1 end
    end
    if p.dir85 == 1 then
      addAng(p, p.step)
      if hiAng(p) >= s8(p.amp) then p.dir85 = 0; rest(); setAng(p, p.amp * 256) end
    else
      addAng(p, -p.step)
      if hiAng(p) <= -p.amp then p.dir85 = 1; rest(); setAng(p, -p.amp * 256) end
    end
  end
  local px, py = parent.x, parent.y
  local dx, dy = polar(p.timer, hiAng(p)); p.x, p.y = px + dx, py + dy
  if child then dx, dy = polar(child.timer, hiAng(child)); child.x, child.y = p.x + dx, p.y + dy end
  p.rot = -hiAng(p)
end

-- sub_080277B8: squash the head toward `target` height scale
function C:squash(e, target, step)
  local h = e.head
  if target > math.floor(h.s78) then
    h.s78 = h.s78 + step
    h.s74 = h.s74 - 1.5
  else
    h.s78 = target
    h.c7c = 8
    e.sub = e.sub + 1
  end
  self:stack(e)
end

-- sub_080279E8: back to $A0 by 4 (true when done)
function C:unsquash(e)
  local h = e.head
  if e.maxS == 0x80 then
    if math.floor(e.s74) - u8(e.h05) == 0x80 then scales(e, e.minS, 0xA0, 0x20, 1) end
    return false
  end
  h.s74 = (h.s74 >= 0xA1) and h.s74 - 4 or 0xA0
  h.s78 = (h.s78 >= 0xA1) and h.s78 - 4 or 0xA0
  return h.s74 == 0xA0 and h.s78 == 0xA0
end

-- sub_08027548
function C:toIdle(e, keep)
  e.subAction = 1
  scales(e, 0x90, 0xB0, 8, 0xFF)
  e.c7d = 0
  self:swingSet(e, 0, keep)
end

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------
function C:pause()
  local p = self.field.player
  self.pauseReq = true
  if p.state == "normal" or p.state == "gust" then
    p.jar = nil
    p.state = "ext"
    p.chuchuPause = true
    p.extUpdate = function(pl) pl.anim:update(1) end
  end
end

function C:sfx(id) self.field:sound(id) end

function C:move(e)
  -- ProcessMovement0: speed (8.8) along direction (0..31), stopped by walls
  local a = e.direction * 8 * math.pi / 128
  local sp = e.speed / 256
  local nx, ny = e.x + math.sin(a) * sp, e.y - math.cos(a) * sp
  local r = self.field.room
  if not r:isSolid(nx + (nx > e.x and 12 or -12), e.y, 1) and nx > 24 and nx < r.width - 24 then e.x = nx end
  if not r:isSolid(e.x, ny + (ny > e.y and 4 or -4), 1) and ny > 40 and ny < r.height - 16 then e.y = ny end
end

-- GravityUpdate(super, rate): the height above the ground; false on landing
local function gravity(e, rate)
  e.hgt = e.hgt + e.zv
  e.zv = e.zv - rate
  if e.hgt <= 0 then e.hgt, e.zv = 0, 0 return false end
  return true
end

function C:splash(e)
  -- sub_08027D20: CHUCHU_BOSS_PARTICLE (sprite $C9, fixed gfx $3E, palette $2B)
  local A = self.A
  e.splashes = e.splashes or {}
  local pt = { x = e.x, y = e.y + 1, anim = Anim.new(), sprite = 0xC9, gfx = { fixed = 0x3E },
               palette = A:objPalette(0x2B, self.field.room.atlas and self.field.room.atlas.palettes) }
  pt.anim:set(A:sprite(0xC9), 0, true)
  e.splashes[#e.splashes + 1] = pt
  return pt
end

-- sub_08027AA4: the Gust Jar on the base (true: it toppled / was hit)
function C:gust(e)
  if e.iframes > 0 then return false end
  local GJ = require("src.zelda.tmc.GustJar")
  local hb = e.hitbox
  if not GJ.touching(self.field, e.x, e.y + C.BASE_BOX_Y, hb.w, hb.h) then return false end -- round 17: gUnk_080FD238 (0, +4)
  self:sfx(SFX.SPLASH)
  self:sfx(SFX.S155)
  e.iframes = 3
  e.h06 = e.h06 + 1
  local v = band(math.floor(e.h06 / 3) * 8, 0xFF)
  if v ~= u8(e.h05) then e.h05 = v end
  e.h08 = 0xB4
  if s8(e.h05) >= 0 then return false end
  e.h01 = 0x40
  e.hitType = 0
  if e.subAction == 2 then self:topple(e) end
  self:splash(e)
  self:sfx(SFX.HIT)
  return true
end

-- sub_08027BBC: off to the room's middle to topple
function C:topple(e)
  e.subAction = 10
  e.h01 = 0
  self:swingSet(e, 7, 1)
  e.head.wait = 0
  e.speed = 0
  e.sub = 0
  local d85 = 1
  if e.x > e.h0e then e.direction = 0x18; d85 = 0 else e.direction = 8 end
  for _, p in ipairs({ e.low, e.mid, e.head }) do p.dir85 = d85 end
  local py = self.field.player.y
  if e.y ~= py then e.h0c = (e.y > py) and 0 or 0x10 end
end

function C:healthLow(e) return e.head.health < NEED[e.h04] end -- sub_08027C54

-- sub_08027C7C: explosions on the parts (one in mask + 1)
function C:explode(e, mask)
  for _, p in ipairs({ e.head, e.low, e.mid }) do
    if band(math.random(0, 0xFFFF), mask) == 0 then
      self.field:addFx(p.x + math.random(-14, 14), p.y - e.hgt + math.random(-8, 8), SPECIAL_FX, FX_GIANT_EXPLOSION3)
    end
  end
end

-- ---------------------------------------------------------------------------
-- the base's subActions
-- ---------------------------------------------------------------------------
local INTRO = {}
INTRO[0] = function(self, e) -- sub_080262A8
  e.minS, e.maxS, e.rate, e.btimer = 0x90, 0xB0, 8, 1
  self:swingSet(e, 6, 1)
  e.sub = 1
end
INTRO[1] = function(self, e) -- sub_08026328 (sub_08078AC0: Link walks in 10 frames)
  e.c7d = 0x78
  e.sub = 2
  self.walkIn = 10
end
INTRO[2] = function(self, e) -- sub_08026358: Link looks round
  local p = self.field.player
  if self.walkIn and self.walkIn > 0 then
    self.walkIn = self.walkIn - 1
    p.y = p.y - 1.25
    p.animationState = 0
    return
  end
  e.c7d = e.c7d - 1
  if e.c7d == 0 then
    e.c7c, e.c7d, e.sub = 0, 0x1E, 3
    p.animationState = 0
    self.field.cameraTarget = e
  elseif e.c7d < 0x61 then
    p.animationState = (e.c7d < 0x5C) and 4 or 2
  end
  p:setAnim(p:animFor("idle"), true)
end
INTRO[3] = function(self, e) -- sub_080263B4: the drops
  local was = e.c7d
  e.c7d = e.c7d - 1
  if was == 0 then
    e.c7c = e.c7c + 1
    local v = DROPS[e.c7c]
    e.c7d = v
    if v == 0xFF then
      e.c7c, e.sub = 0x78, 4
    else
      -- round 17: CHUCHU_BOSS_START_PARTICLE type 0 (+ its type 2 mark)
      local ox, oy = math.random(0, 63), math.random(0, 31)
      if math.random(0, 1) == 1 then ox = -ox end
      if math.random(0, 1) == 1 then oy = -oy end
      e.drops[#e.drops + 1] = { x = e.x + ox, y = e.y + oy, hgt = 0xC0, zv = 0, s74 = 0x240, s78 = 0x140, act = 1 }
    end
  end
end
INTRO[4] = function(self, e) -- sub_08026414
  local was = e.c7c
  e.c7c = e.c7c - 1
  if was == 0 then
    e.hgt, e.zv = 192, 0
    e.visible = true
    e.sub = 5
    self:sfx(SFX.S1A2)
  end
end
INTRO[5] = function(self, e) -- sub_0802647C
  if not gravity(e, 0.25) then
    self.field:shake(16, 0)
    self:sfx(SFX.S1A1)
    e.sub = 6
  end
end
INTRO[6] = function(self, e) -- sub_080264AC
  self:squash(e, 0xD0, 8)
  if e.sub ~= 6 then self:partAnim(e.head, 4); self:splash(e) end
end
INTRO[7] = function(self, e) -- sub_080264D4
  if self:unsquash(e) then
    e.sub = 8
    e.c7d = 0x3C
    self:swingSet(e, 5, 0)
    self.field:bgm(BGM_BOSS)
  end
  self:stack(e)
end
INTRO[8] = function(self, e) -- sub_0802650C
  if e.head.amp == 0 then
    e.sub = 9
    self.field.cameraTarget = nil
  end
  self:chain(e)
end
INTRO[9] = function(self, e) -- sub_0802653C
  scales(e, 0x90, 0xB0, 4, 0xFF)
  self:toIdle(e, 0)
  self:partAnim(e.head, 0)
end

local SA = {}
SA[0] = function(self, e) -- sub_0802626C
  INTRO[e.sub](self, e)
  self:pause()
end
SA[1] = function(self, e) -- sub_08026580
  self:gust(e)
  if e.h01 == 0x40 then self:topple(e) return end
  local was = e.c7d
  e.c7d = e.c7d - 1
  if was == 0 then
    e.speed = 0
    e.subAction = 2
    e.c7c = 0x3C
    local p = self.field.player
    e.direction = facing(e.x, e.y, p.x, p.y)
    if e.h04 == 2 then e.rate = 0x48; e.maxS = e.maxS + 16 else e.rate = 16 end
    if band(e.h01, 0xA0) ~= 0 then e.c7d, e.c7c = 0, 0
    else
      local c = BOUNCES[math.random(0, 7)] + 1
      e.c7d = (e.h04 == 2) and c * 2 or c
    end
  end
  self:chain(e)
end
SA[2] = function(self, e) -- sub_08026634
  if self:gust(e) then return end
  if e.c7d == 0 then
    local was = e.c7c
    e.c7c = e.c7c - 1
    if was ~= 0 then self:chain(e) return end
    if band(e.h01, 0x40) == 0 then
      if band(e.h01, 0x80) ~= 0 then
        e.h00 = e.h00 - 1
        if e.h00 == 0 then e.h01 = 1 end
      else
        e.h01 = 1
        if e.h04 == 2 and math.random(0, 3) ~= 0 then e.h00, e.h01 = 4, 0x81 end
      end
    end
    e.subAction = 3
    e.sub = 0
    scales(e, 0x90, 0x90, 0xC, 0)
    e.zvPending = 7
    e.speed = 0x180
  else
    local f = self.field
    if band(f.frame or 0, 0x7F) == 0 then local p = f.player; e.direction = facing(e.x, e.y, p.x, p.y) end
    e.speed = (e.h04 == 2) and 0x100 or 0xC0
    if e.btimer ~= 0 then
      if band(f.frame or 0, 7) == 0 then self:sfx(SFX.S19E) end
      self:move(e)
    end
    if math.floor(e.s74) == e.maxS then e.c7d = e.c7d - 1 end
  end
  self:chain(e)
end
SA[3] = function(self, e) -- sub_08026750
  self:gust(e)
  local h, m, l = e.head, e.mid, e.low
  if e.sub == 0 then -- sub_08026774
    if (hiAng(h) == 0 and hiAng(m) == 0 and hiAng(l) == 0) then
      local was = e.c7d
      e.c7d = e.c7d - 1
      if was ~= 0 then return end
      scales(e, 0x80, 0x80, 0x40, 0)
      e.sub = 1
      self:partAnim(h, 1)
    end
    self:stack(e)
  elseif e.sub == 1 then -- sub_080267D0
    self:squash(e, 0xF0, 8)
    if e.sub ~= 1 then scales(e, 0xE0, 0xC0, 0x20, 0xFF); self:partAnim(h, 2) end
  else -- sub_08026808
    if h.s74 < 0xC0 then h.s74 = h.s74 + 4 end
    if h.s78 > 0xB0 then h.s78 = h.s78 - 8
    else
      local p = self.field.player
      e.direction = facing(e.x, e.y, p.x, p.y)
      e.subAction = 4
      h.s78, m.s78, l.s78 = 0xA0, 0xA0, 0xA0
      self:swingSet(e, 1, 0)
      self:sfx(SFX.S1A2)
      e.zv = e.zvPending or 7
    end
    self:stack(e)
  end
end
SA[4] = function(self, e) -- sub_0802686C
  if gravity(e, 0.25) then self:move(e) self:chain(e)
  else
    self.field:shake(16, 0)
    e.subAction = 5
    e.sub = 0
    scales(e, 0x80, 0x80, 0x80, 0)
    self:chain(e)
    self:partAnim(e.head, 3)
    self:sfx(SFX.S1A1)
  end
end
SA[5] = function(self, e) -- sub_080268C8
  self:gust(e)
  if e.sub == 0 then
    self:squash(e, 0xD0, 8)
    if e.sub ~= 0 then self:partAnim(e.head, 4); self:splash(e) end
  else
    if self:unsquash(e) then
      scales(e, 0x90, 0xB0, 4, 0xFF)
      self:toIdle(e, 0)
      self:partAnim(e.head, 0)
    end
    self:stack(e)
  end
end
SA[6] = function(self, e) -- sub_0802694C: topple
  local h, m, l = e.head, e.mid, e.low
  if e.sub == 0 then -- sub_08026968: lean
    local was = e.c7d
    e.c7d = e.c7d - 1
    if was == 0 then e.sub = 1
    else
      local d = vertical(e.direction) and 0x100 or -0x100
      addAng(l, d); addAng(m, d); addAng(h, d)
    end
    self:chain(e)
  elseif e.sub == 1 then -- sub_080269CC: fall over
    local d = vertical(e.direction) and -0x300 or 0x300
    local done = 0
    if u8(hiAng(l) + 0x20) <= 0x3F then addAng(l, d) else done = done + 1 end
    if u8(hiAng(m) + 0x44) < 0x88 then addAng(m, d) else done = done + 1 end
    local t2 = hiAng(h) + 0x40
    if (t2 - 0x20) > 0x40 or (t2 - 0x20) < 0 then
      self:partAnim(h, vertical(e.direction) and 6 or 5)
    end
    if band(t2, 0xFF) < 0x80 then addAng(h, d) else done = done + 1 end
    if done == 3 then
      e.collide = false
      h.collide = true
      h.s74 = h.s74 + 3
      self.field:shake(0x20, 0)
      self:sfx(SFX.S10B)
      local pt = self:splash(e)
      pt.anim:set(self.A:sprite(0xC9), 1, true)
      pt.y = pt.y + 0x10
      pt.x = pt.x + (vertical(e.direction) and -0x38 or 0x38)
      l.f84, m.f84, h.f84 = 1, 1, 1
      m.s78, l.s78, h.s78 = 0x98, 0x98, 0x98
      e.c7c = LIE[math.random(0, 3)]
      e.sub = 2
    elseif h.s74 < 0xF0 then
      h.s74 = h.s74 + 4
      h.s78 = h.s78 - 0.5
    end
    self:chain(e)
  else -- sub_08026BE8: lying, the head open to the sword
    if e.c7c == 0 then
      e.subAction = 7
      e.sub = 0
      e.c7d = 0x2D
      h.collide = false
      self:sfx(SFX.S155)
    else e.c7c = e.c7c - 1 end
    self:chain(e)
  end
end
SA[7] = function(self, e) -- sub_08026C40: up again
  local h, m, l = e.head, e.mid, e.low
  if e.c7d ~= 0 then
    e.c7d = e.c7d - 1
    if e.c7d ~= 0 then
      if band(e.c7d, 8) ~= 0 then h.s74 = h.s74 + 2; h.s78 = h.s78 + 1
      else h.s74 = h.s74 - 2; h.s78 = h.s78 - 1 end
      return
    end
    self:partAnim(h, vertical(e.direction) and 8 or 7)
  end
  local v
  if e.c7c == 0 then v = vertical(e.direction) and 0x300 or -0x300
  else v = vertical(e.direction) and 0x480 or -0x480 end
  if u8(hiAng(l) + 6) >= 0xD then
    addAng(l, v * 2); addAng(m, v); addAng(h, v)
  else
    l.ang16 = 0
    if u8(hiAng(m) + 6) >= 0xD then addAng(m, v * 2); addAng(h, v)
    else
      m.ang16 = 0
      if u8(hiAng(h) + 6) >= 0xD then addAng(h, v * 2) else h.ang16 = 0 end
    end
  end
  if h.s74 >= 0xA1 then h.s74 = h.s74 - 4 else h.s74 = 0xA0 end
  if h.s78 < 0xA0 then h.s78 = h.s78 + 0.5
  else
    self:swingSet(e, 3, 0)
    h.wait = 0
    if vertical(e.direction) then m.dir85, l.dir85, h.dir85 = 1, 1, 1 end
    e.subAction = 8
    e.c7c = 4
    m.subtimer, l.subtimer, h.subtimer = 0, 0, 0
    scales(e, 0x90, 0xB0, 0x10, 0)
  end
  self:chain(e)
end
SA[8] = function(self, e) -- sub_08026E1C
  if e.c7c == 0 then
    if e.head.subtimer + e.mid.subtimer + e.low.subtimer > 10 then
      e.collide = true
      if self:healthLow(e) then
        e.h04 = e.h04 + 1
        e.head.health = 0xFF
      end
      if e.h04 == 3 then
        e.health = 0
        e.collide = false
        e.iframes = 60
        return
      end
      e.h00, e.h01 = 4, 0x81
      e.hitType = 0x7D
      e.subAction = 11
      e.sub = 0
      self:partAnim(e.head, 0)
      scales(e, 0x80, 0x80, 0x80, 0)
      e.h01 = 0x21
    end
  else
    e.c7c = e.c7c - 1
    e.h08, e.h06 = 0, 0
  end
  if self:healthLow(e) and e.h04 == 2 then
    self:explode(e, 0x3F)
    self:pause()
  end
end
SA[9] = function(self, e) -- sub_08026FA4: the last blow, it sinks
  self:pause()
  e.collide = false
  local h = e.head
  if e.c7c ~= 0 then e.c7c = 1 end
  if h.s78 < 0x98 then
    h.s78 = h.s78 + bit.lshift(1, e.c7c)
    h.s74 = h.s74 - 2 * bit.lshift(1, e.c7c)
  else
    e.subAction = 7
    h.collide = false
    e.sub = 0
    e.c7d = 0x2D
    self:sfx(SFX.S155)
    self:partAnim(h, vertical(e.direction) and 8 or 7)
  end
  self:chain(e)
end
SA[10] = function(self, e) -- sub_08027064: to the middle, swaying
  local h, m, l = e.head, e.mid, e.low
  local f = self.field
  e.speed = 0x60
  if h.animIndex ~= 10 and band(f.frame or 0, 0xF) == 0 then self:sfx(SFX.JUMP) end
  local p = f.player
  if e.sub ~= 0 and math.floor(e.y) ~= math.floor(p.y) then
    if band(f.frame or 0, 0xF) == 0 then e.h0c = (e.y > p.y) and 0 or 0x10 end
    e.direction = e.h0c
    self:move(e)
  end
  if h.dir85 == 1 then e.direction = (hiAng(h) < 1) and 24 or 8
  else e.direction = (hiAng(h) <= -1) and 24 or 8 end
  if e.sub == 0 then
    if math.abs(e.x - e.h0e) < 1 then
      e.x = e.h0e
      m.f84, l.f84, h.f84 = 1, 1, 1
      e.c7c = 0x1E
      e.sub = 1
    else
      e.direction = (e.x > e.h0e) and 24 or 8
      local sp = e.speed / 256
      if math.abs(e.x - e.h0e) <= sp then e.x = e.h0e else e.x = e.x + ((e.x > e.h0e) and -sp or sp) end
      e.direction = (h.dir85 == 1) and ((hiAng(h) < 1) and 24 or 8) or ((hiAng(h) <= -1) and 24 or 8)
    end
  elseif h.wait ~= 0 and l.wait ~= 0 and m.wait ~= 0 then
    local was = e.c7c
    e.c7c = e.c7c - 1
    if was == 0 then
      m.f84, l.f84, h.f84 = 1, 1, 1
      local want = 0
      if e.sub > 1 then want = (e.x > p.x) and 24 or 8 end
      if e.sub == 5 or e.direction == want then
        e.subAction = 6
        self:swingSet(e, 7, 1)
        e.sub = 0
        e.c7d = 0xF
      else e.sub = e.sub + 1 end
    end
  else
    e.c7c = (e.sub ~= 4) and 0x1E or 0x3C
  end
  self:chain(e)
end
SA[11] = function(self, e) -- sub_08026F1C: angry
  if band(e.c7c, 0x80) ~= 0 then
    if self:unsquash(e) then
      e.sub = 0
      e.c7c = band(e.c7c, 0xF)
      scales(e, 0x80, 0x80, 0x80, 0)
      if e.c7c == 2 then self:toIdle(e, 0) end
    end
    self:stack(e)
  else
    self:squash(e, 0xF0, 0x10)
    if e.sub ~= 0 then
      e.c7c = bor(e.c7c + 1, 0x80)
      scales(e, 0xC0, 0xC0, 0x20, 1)
    end
  end
end

-- the parts' own frames (sub_0802720C / sub_080272D4)
function C:partTick(e, p)
  local sa = e.subAction
  if p.type ~= 1 then
    if sa == 1 or sa == 2 or sa == 12 then p.s78, p.s74 = 0xA0, 0xA0; self:swing(e, p)
    elseif sa == 3 or sa == 5 then if hiAng(p) ~= 0 then p.wait = 0; self:swing(e, p) end
    elseif sa == 8 then
      if p.subtimer < 4 then self:swing(e, p); if hiAng(p) == 0 then p.subtimer = p.subtimer + 1 end end
    elseif sa == 10 then
      if p.wait == 0 then self:swing(e, p) elseif p.f84 ~= 0 then p.wait = 0; p.f84 = 0 end
    elseif sa == 4 or sa == 0 then self:swing(e, p) end
    return
  end
  -- the head
  if sa == 1 or sa == 2 or sa == 12 then p.s78, p.s74 = 0xA0, 0xA0; self:swing(e, p)
  elseif sa == 3 or sa == 5 then if hiAng(p) ~= 0 then self:swing(e, p) end
  elseif sa == 4 then self:swing(e, p)
  elseif sa == 8 then
    if p.subtimer < 3 then self:swing(e, p); if hiAng(p) == 0 then p.subtimer = p.subtimer + 1 end end
  elseif sa == 6 then
    -- sub_08027A60: the lying head's wobble
    if band(p.c7c or 0, 0x80) ~= 0 then p.s74 = p.s74 + 0.25 else p.s74 = p.s74 - 0.25 end
    p.c7c = (p.c7c or 0) + 1
    if band(p.c7c, 0x7F) == 0x28 then p.c7c = bit.bxor(band(p.c7c, 0x80), 0x80) end
  elseif sa == 10 then
    if p.wait == 0 then self:swing(e, p) elseif p.f84 ~= 0 then p.wait = 0; p.f84 = 0 end
    local t = u8(hiAng(p) + math.floor(p.amp / 2))
    if t > p.amp then self:partAnim(p, (hiAng(p) > 0) and 12 or 11)
    else self:partAnim(p, 10) end
  elseif sa == 0 then
    if e.sub == 8 then
      self:swing(e, p)
      if p.wait == 1 and p.amp ~= 0 then p.amp = math.max(0, p.amp - 4) end
    end
  end
  p.anim:update(1)
end

-- ---------------------------------------------------------------------------
-- the frame
-- ---------------------------------------------------------------------------
function C:update(e)
  local f = self.field
  self.pauseReq = false
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  if e.head.iframes > 0 then e.head.iframes = e.head.iframes - 1 end
  -- round 17: the intro's goo drops (chuchuBossStartParticle.c type 0):
  -- from z -$C0 under GravityUpdate($2000), SFX_WATER_SPLASH on landing,
  -- then spread (x scale -$20, y +$20 a frame) to y $200, then shrink
  -- (+$10 both) to $400, deleted
  for i = #e.drops, 1, -1 do
    local d = e.drops[i]
    if d.act == 1 then
      d.hgt = d.hgt - d.zv; d.zv = d.zv + 0.125
      if d.hgt <= 0 then d.hgt = 0; d.act = 2; self:sfx(SFX.SPLASH) end
    elseif d.act == 2 then
      d.s74 = d.s74 - 0x20; d.s78 = d.s78 + 0x20
      if d.s78 > 0x1FF then d.act = 3 end
    else
      d.s74 = d.s74 + 0x10; d.s78 = d.s78 + 0x10
      if d.s78 > 0x3FF then table.remove(e.drops, i) end
    end
  end
  for i = #(e.splashes or {}), 1, -1 do
    local s = e.splashes[i]
    s.anim:update(1)
    if s.anim.done then table.remove(e.splashes, i) end
  end
  -- round 17: GetNextFunction -> ChuchuBoss_OnKnockback while
  -- knockbackDuration runs (GenericKnockback, then sub_08027870): the
  -- subActions wait
  if (e.kbt or 0) > 0 and e.health > 0 then
    e.kbt = e.kbt - 1
    local sp = (e.kbs or 0) / 256
    local nx, ny = e.x + (e.kbdx or 0) * sp, e.y + (e.kbdy or 0) * sp
    local r = f.room
    if not r:isSolid(nx + (nx > e.x and 12 or -12), e.y, 1) and nx > 24 and nx < r.width - 24 then e.x = nx end
    if not r:isSolid(e.x, ny + (ny > e.y and 4 or -4), 1) and ny > 40 and ny < r.height - 16 then e.y = ny end
    self:chain(e)
    e.z = e.hgt
    self:touchLink(e)
    return
  end
  if e.health <= 0 then
    -- ChuchuBoss_OnDeath
    self:pause()
    if e.subAction ~= 12 then
      e.subAction = 12
      e.dsub = 0
      self:partAnim(e.head, 9)
    elseif e.dsub == 0 then
      self:explode(e, 0x3F)
      e.dsub, e.c7d = 1, 0x78
    elseif e.dsub == 1 then
      local was = e.c7d
      e.c7d = e.c7d - 1
      if was == 0 then
        e.dsub = 2
        self:sfx(SFX.DIE)
        self:release()
        self.en:kill(e)
        f:setFlag("local", 0x48, true)
      else
        self:explode(e, (e.c7d <= 0x50) and ((e.c7d > 0x1E) and 0x1F or 0xF) or 0x3F)
      end
    end
    self:chain(e)
    e.head.anim:update(1)
    return
  end
  SA[e.subAction](self, e)
  -- sub_08026110: the swell goes down once unk_08 is 0
  if e.h08 == 0 and u8(e.h05) ~= 0 then
    local v = s8(e.h05) - ((e.subAction == 8) and 0x40 or 0x20)
    e.h05 = (v < 0) and 0 or v
  end
  -- the base's bounce between its scale bounds
  if e.rate ~= 0 then
    local lo, hi = e.minS + u8(e.h05), e.maxS + u8(e.h05)
    if e.btimer == 0 then
      e.s74 = e.s74 - e.rate / 16; e.s78 = e.s78 - e.rate / 16
      if e.s74 <= lo then e.s74 = lo end
      if e.s78 <= lo then e.s78 = lo end
      if e.s74 <= lo and e.s78 <= lo then e.btimer = 1 end
    else
      e.s74 = e.s74 + e.rate / 16; e.s78 = e.s78 + e.rate / 16
      if e.s74 >= hi then e.s74 = hi end
      if e.s78 >= hi then e.s78 = hi end
      if e.s74 >= hi and e.s78 >= hi then e.btimer = 0 end
    end
  end
  e.hitbox.w = rshift(math.floor(0x10000 / math.max(1, e.s74)) * 7, 7)
  e.hitbox.h = rshift(math.floor(0x10000 / math.max(1, e.s78)) * 3, 7)
  -- the parts (entity order: lower, middle, head)
  self:partTick(e, e.low)
  self:partTick(e, e.mid)
  self:partTick(e, e.head)
  e.z = e.hgt
  self:touchLink(e)
  if not self.pauseReq then self:release() end
end

function C:release()
  local p = self.field.player
  if p.chuchuPause then
    p.chuchuPause = nil
    if p.state == "ext" then p.state, p.extUpdate = "normal", nil; p.animId = -1 end
  end
end

-- Link against the body.  Round 17, from the cartridge (round 16 had the
-- lower / middle parts hurt Link, the box 8 px too high and contact while
-- it rose):
--   * the base's own hit type is $7D (gEnemyDefinition_13 form 0), and
--     gCollisionMtx[$7D * 34 + 0] is CollisionNoOp: the base never hurts
--     Link itself.  The hitbox helper (type 8, sub_08026090) copies the
--     base's position, flags and hitbox with hit type $7C (or $7E):
--     [$7C][0] = Link knocked at 40*16 ($280 = 2.5 px a frame) for 6
--     frames, 60 iframes, 2 damage.  The box is gUnk_080FD238: offset
--     (0, +4), half sizes from sub_08026110 (e.hitbox.w / h).
--   * the head, middle and lower parts have the collision bit clear in
--     their definitions; the head is switched on only while it lies, with
--     collisionMask bit 0 cleared (Link's body ignores it) -- no part hurts
--     Link.
--   * collision is off from the fall (sub_080269CC) until the phase check
--     (sub_08026E1C) and during the last blow (sub_08026FA4): e.collide.
--   * arm_CalcCollision's height test: |dz| <= 5 + 5.
--   * on the ground the base (sub_08026110) and the lying head
--     (sub_080272D4 cases 6 / 9) are static solids: sub_0800445C ->
--     CalcCollisionStaticEntity pushes Link out (Hitboxes.pushOut).
C.BASE_BOX_Y = 4
C.HEAD_BOX_Y = 12 -- gUnk_080FD240
function C:baseBox(e) return { x = 0, y = C.BASE_BOX_Y, w = e.hitbox.w, h = e.hitbox.h } end
function C:headBox(e)
  local h = e.head
  return { x = 0, y = C.HEAD_BOX_Y, w = rshift(math.floor(0x10000 / math.max(1, h.s78)) * 9, 7),
           h = rshift(math.floor(0x10000 / math.max(1, h.s74)) * 5, 6) }
end
function C:touchLink(e)
  local f = self.field
  local p = f.player
  if not e.visible or e.health <= 0 then return end
  local HB = require("src.zelda.tmc.Hitboxes")
  -- static pushes (sub_0800445C: only while it stands on the ground)
  if e.hgt == 0 and (e.subAction ~= 0 or e.sub >= 6) then
    HB.pushOut(f, e, self:baseBox(e))
  end
  if (e.subAction == 6 and e.sub == 2) or e.subAction == 9 then
    HB.pushOut(f, { x = e.head.x, y = e.head.y }, self:headBox(e))
  end
  -- the helper's contact
  if p.state == "dead" or p.invuln > 0 or e.collide == false or e.subAction == 9 then return end
  if math.abs(e.hgt - (p.z or 0)) > 10 then return end
  local pb = HB.player(f, p) or { x = 0, y = -3, w = 6, h = 6 }
  local bb = self:baseBox(e)
  local dx = (math.floor(p.x) + pb.x) - (math.floor(e.x) + bb.x)
  local dy = (math.floor(p.y) + pb.y) - (math.floor(e.y) + bb.y)
  if math.abs(dx) > pb.w + bb.w or math.abs(dy) > pb.h + bb.h then return end
  local hitType = (e.hitType == 0x7E) and 0x7E or 0x7C
  local st = self.en:settings(hitType, HB.hurtType(p)) or { orgKbSpd = 40, orgIfr = 60, orgKbDur = 6, tgtDmg = 2 }
  if p:hurt(math.max(st.tgtDmg, 1), e.x, e.y + bb.y) then
    p.invuln = st.orgIfr > 0 and st.orgIfr or 1
    p.timer = math.max(st.orgKbDur, 1)
    local ks = st.orgKbSpd * 16 / 256
    local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    p.kbx, p.kby = dx / d * ks, dy / d * ks
  end
end

-- round 17: a Gust Jar puff (PLAYER_ITEM_GUST_BIG, hurtType $1B) on the
-- base: gCollisionMtx[$7D][$1B] is CollisionDefault, then sub_08027AA4
-- case 27: iframes -30, knocked back by the puff's size (type 0: $100 for
-- 16 frames, 1: $180 for 20, 2: $1C0 for 26) along the contact direction.
-- (The base's hit type is 0 once it is about to topple: [0][$1B] does not
-- push.)  True when the puff touched it.
function C:blow(e, sh)
  if e.health <= 0 or e.iframes > 0 or e.collide == false or e.hitType ~= 0x7D then return false end
  if math.abs(e.hgt) > 10 then return false end
  local bb = self:baseBox(e)
  if math.abs((e.x + bb.x) - sh.x) > bb.w + sh.half or math.abs((e.y + bb.y) - sh.y) > bb.h + sh.half then return false end
  local t = sh.type or 0
  e.iframes = 30
  e.kbt = ({ [0] = 16, 20, 26 })[t] or 16
  e.kbs = ({ [0] = 0x100, 0x180, 0x1C0 })[t] or 0x100
  e.kbdx, e.kbdy = sh.ux or 0, sh.uy or 0
  return true
end

-- the sword's box {x, y, w, h}: the lying head (sub_080272D4 case 6)
function C:swordHit(e, box)
  local f = self.field
  local h = e.head
  if e.health <= 0 then return false end
  local hb = self:headBox(e) -- round 17: offset (0, +12), gUnk_080FD240
  local hw, hh = hb.w, hb.h
  local hx, hy = h.x, h.y - e.hgt + hb.y
  if math.abs(hx - box.x) < hw + box.w and math.abs(hy - box.y) < hh + box.h then
    if not (h.collide and e.subAction == 6 and e.sub == 2) then
      f:sound(0x118) -- the shield bounce: not open to the sword now
      return false
    end
    if h.iframes > 0 then return false end
    local st = self.en:settings(0x7B, 4) -- round 17: the head is form 1, damageType $7B ([$7B][4]: 2 damage, iframes 30)
    local dmg = st and math.max(st.orgDmg or 2, 1) or 2
    h.health = math.max(0, h.health - dmg)
    h.iframes = (st and st.tgtIfr and st.tgtIfr > 0) and st.tgtIfr or 20
    e.iframes = h.iframes
    local pt = self:splash(e)
    pt.x, pt.y = hx + 1, h.y - e.hgt + 0x20
    if not self:healthLow(e) or e.h04 ~= 2 then
      f:sound(SFX.HIT)
    else
      self:pause()
      e.subAction = 9
      e.c7c = 0
      f:sound(SFX.DIE)
    end
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- drawing: the affine parts (scale $100 / unk_74, $100 / unk_78; angle -unk_82)
-- ---------------------------------------------------------------------------
function C:drawPart(p, x, y, sx, sy, rot, flick)
  local frame = p.anim.frame
  if not frame or frame == 0xFF or not p.sprite then return end
  local img, ox, oy = self.A:spriteFrame(p.sprite, frame, p.palette, "chuchu" .. (p.type or 0), p.gfx)
  if not img then return end
  local w, h = img:getWidth(), img:getHeight()
  local cx, cy = math.floor(x) + ox + w / 2, math.floor(y) + oy + h / 2
  local fx = p.anim:hflip() and -1 or 1
  love.graphics.draw(img, cx, cy, -rot * math.pi / 128, fx * 256 / math.max(16, sx), 256 / math.max(16, sy), w / 2, h / 2)
end

-- round 17: the drops with the particle object's own sprite (its object
-- definition, animation 3), affine-scaled; the type 2 mark under each sits
-- at y + 3 with x scale $200 - z, y scale $300 - 2z while it falls (the
-- drop's own scales once down); sub_0806FCF4 keeps the bottom on the floor
C.START_PARTICLE = 0x49
function C:dropArt()
  if self._dropArt == nil then
    local A = self.A
    local defs = A.manifest.objectDefs
    local d = defs and defs[C.START_PARTICLE]
    if d and d.type == 2 then d = d.forms and d.forms[0] end
    if d and d.sprite and d.type ~= 0 then
      local spr = A:sprite(d.sprite)
      local keys = spr and spr.anims and spr.anims[3]
      local fr = keys and keys[1] and keys[1][1]
      self._dropArt = fr and { sprite = d.sprite, frame = fr, palette = A:objPalette(d.palette, self.field.room.atlas and self.field.room.atlas.palettes),
                               gfx = Assets.gfxSource(d.gfxType, d.gfx) } or false
    else self._dropArt = false end
  end
  return self._dropArt
end
function C:drawDrops(e, camX, camY)
  local art = self:dropArt()
  local function blob(x, y, sx, sy)
    if art then
      local img, ox, oy = self.A:spriteFrame(art.sprite, art.frame, art.palette, "chuchuDrop", art.gfx)
      if img then
        local w, h = img:getWidth(), img:getHeight()
        local fx, fy = 256 / math.max(16, sx), 256 / math.max(16, sy)
        -- scale about the bottom centre of the frame
        love.graphics.draw(img, math.floor(x) + ox + w / 2, math.floor(y) + oy + h, 0, fx, fy, w / 2, h)
        return
      end
    end
    love.graphics.setColor(0.4, 0.85, 0.3, 1)
    love.graphics.ellipse("fill", math.floor(x), math.floor(y), 3 * 512 / sx, 3 * 256 / sy)
    love.graphics.setColor(1, 1, 1, 1)
  end
  for _, d in ipairs(e.drops) do
    if d.hgt > 0 then blob(d.x - camX, d.y + 3 - camY, 0x200 + d.hgt, 0x300 + 2 * d.hgt) end
    blob(d.x - camX, d.y - camY - d.hgt, d.s74, d.s78)
  end
end

function C:draw(e, camX, camY)
  if #e.drops > 0 then self:drawDrops(e, camX, camY) end
  for _, s in ipairs(e.splashes or {}) do
    local fr = s.anim.frame
    if fr and fr ~= 0xFF then
      local img, ox, oy = self.A:spriteFrame(s.sprite, fr, s.palette, "chuchuPt", s.gfx)
      if img then love.graphics.draw(img, math.floor(s.x - camX) + ox, math.floor(s.y - camY) + oy) end
    end
  end
  if not e.visible or e.dying then return end
  if e.iframes > 0 and e.subAction ~= 12 and e.iframes % 4 < 2 and e.head.iframes > 0 then return end
  local z = e.hgt
  -- the shadow while it is up
  if z > 0 then
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.ellipse("fill", math.floor(e.x - camX), math.floor(e.y - camY), 20, 6)
    love.graphics.setColor(1, 1, 1, 1)
  end
  self:drawPart(e, e.x - camX, e.y - camY - z, e.s74, e.s78, 0)
  for _, p in ipairs({ e.low, e.mid, e.head }) do
    self:drawPart(p, p.x - camX, p.y - camY - z, p.s74, p.s78, p.rot)
  end
end

return C
