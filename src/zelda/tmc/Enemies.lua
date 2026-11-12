-- Enemies and combat for The Minish Cap's early areas.
--
-- COMMON (src/enemyUtils.c EnemyInit, src/collision.c, asm/src/intr.s):
--   * health, speed, hitbox, sprite, palette and graphics come from
--     gEnemyDefinitions[id] (multi-form by type); the hit type is the
--     definition's damageType, the hurt type $41;
--   * every contact is resolved through gCollisionMtx[hitType * 34 +
--     hurtType] (ColSettings): enemy -> Link uses Link's hurt type 0 and
--     deals tgtDamage (health units, 8 = a heart) with Link's knockback
--     speed/duration/invulnerability from the same entry; the Smith's
--     Sword (hurt type 4) deals orgDamage and knocks the enemy back by the
--     tgt fields.  Entries whose first byte is $FF go to special handlers
--     in the cartridge; those use the default enemy entry here;
--   * the home rectangle (sub_0804A720): gUnk_080D3D94 ranges unless the
--     room entry gives its own; enemies keep inside it;
--   * death (EnemyCreateDeathFX / DeathFx): a puff, then
--     CreateRandomItemDrop with DeathFx_EnemyDroptables[id].
--
-- BEHAVIOURS ported from src/enemy/*.c: Octorok (full: idle / walk /
-- turn / spit a rock when facing Link).  Round 12: Puffstool, Sluggula and
-- Mulldozer run their decomp code in EnemyDeepwood.lua (the old models
-- below for them are no longer called).  ChuChu, Sluggula, Pesto,
-- Puffstool, Mulldozer and Rope use a shared "hop / wander / charge"
-- model tuned to each one's speed and health -- simplified, see
-- docs/zelda/minishcap.md.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")
local Boss = require("src.zelda.tmc.Boss")

local Enemies = {}
Enemies.__index = Enemies

local ID = { OCTOROK = 0x00, CHUCHU = 0x01, PEAHAT = 0x03, KEESE = 0x08, SLUGGULA = 0x10, PESTO = 0x11,
             PUFFSTOOL = 0x12, ROPE = 0x2C, MULLDOZER = 0x32, SPINY_BEETLE = 0x35 }
Enemies.ID = ID
local HURT_ENEMY, HURT_PLAYER, HURT_SWORD = 0x41, 0, 4
local ROCK_HIT = 26
local SFX_HIT = 0xFE

-- direction (0-31, 0 north clockwise) -> unit vector
local function dirVec(d)
  local a = (d % 32) / 32 * 2 * math.pi
  return math.sin(a), -math.cos(a)
end
local function dirTo(ax, ay, bx, by)
  local a = math.atan2(bx - ax, -(by - ay))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
local function round8(d) return (math.floor((d + 4) / 8) * 8) % 32 end -- DirectionRoundUp

function Enemies.new(field)
  local self = setmetatable({ field = field, A = field.assets, m = field.assets.manifest }, Enemies)
  self.mtx = field.assets.store and field.assets.store:read("colmtx.bin") or ""
  self.boss = Boss.new(field, self)
  return self
end

-- ColSettings for (hitType, hurtType); nil when the entry is a special
-- handler ($FF) or missing
function Enemies:settings(hitType, hurtType)
  local o = (hitType * 34 + hurtType) * 12
  local b = { self.mtx:byte(o + 1, o + 12) }
  if #b < 12 or b[1] == 0xFF then return nil end
  return { orgKbSpd = b[1], orgIfr = b[2], orgKbDur = b[3], tgtDmg = b[4], orgConf = b[5],
           tgtKbSpd = b[6], tgtIfr = b[7] >= 128 and b[7] - 256 or b[7], tgtKbDur = b[8], orgDmg = b[9],
           tgtConf = b[10], flags = b[11] }
end
local DEFAULT_TOUCH = { orgKbSpd = 24, orgIfr = 30, orgKbDur = 8, tgtDmg = 2 }
local DEFAULT_SWORD = { orgDmg = 2, tgtKbSpd = 24, tgtIfr = 12, tgtKbDur = 12 }

function Enemies:def(id, form)
  local d = self.m.enemyDefs and self.m.enemyDefs[id]
  if d and d.multi then d = d.forms[form or 0] or d.forms[0] end
  return d
end

-- a room entry (kind 3) -> enemy entity, or nil when this id is not ported
function Enemies:spawn(dat)
  -- ids from $60 are boss parts and helpers (TREE_ITEM, GYORG_*...): not
  -- ported here.  (A definition with draw 0 is an enemy that appears later,
  -- like a ChuChu rising from its puddle.)
  do local x = require("src.zelda.tmc.R26").spawnEnemy(self, dat, self:def(dat.id, dat.paramA)) if x ~= nil then return x or nil end end -- round 26b: dungeon enemies / boss parts (R26.lua)
  do local x = require("src.zelda.tmc.R27A").spawnEnemy(self, dat, self:def(dat.id, dat.paramA)) if x ~= nil then return x or nil end end -- round 27A (R27A.lua)
  if dat.id >= 0x60 then return nil end
  local d = self:def(dat.id, dat.paramA)
  do local x = require("src.zelda.tmc.Crenel").spawnEnemy(self, dat, d) if x ~= nil then return x or nil end end -- round 5 (Crenel.lua)
  if dat.id == Boss.MADDERPILLAR or dat.id == Boss.CHUCHU_BOSS then return self.boss:spawn(dat, d) end
  if not d then return nil end
  local e = {
    kind = 3, id = dat.id, form = dat.paramA, x = dat.x, y = dat.y, z = 0, zv = 0,
    health = d.health, maxHealth = d.health, speed = d.speed, hitType = d.damageType,
    hitbox = d.hitbox or { x = 0, y = 0, w = 6, h = 6 },
    sprite = d.sprite, palette = self.A:objPalette(d.palette, self.field.room.atlas and self.field.room.atlas.palettes),
    gfx = Assets.gfxSource("enemy", d.gfx), anim = Anim.new(), animationState = 2,
    action = 0, timer = 1, iframes = 0, kbt = 0, enemy = true, literalAnim = true, field82 = 0, interactType = 0,
    def = d,
  }
  -- the home rectangle
  local r = self.m.enemyRanges and self.m.enemyRanges[dat.id] or { 64, 64 }
  local rx = band(rshift(dat.paramB, 16), 0xFF); if rx == 0 then rx = r[1] end
  local ry = band(rshift(dat.paramB, 24), 0xFF); if ry == 0 then ry = r[2] end
  e.homeX = band(dat.paramC, 0xFFFF) ~= 0 and band(dat.paramC, 0xFFFF) or math.max(0, e.x - 4 * rx)
  e.homeY = rshift(dat.paramC, 16) ~= 0 and rshift(dat.paramC, 16) or math.max(0, e.y - 4 * ry)
  e.rangeW, e.rangeH = 8 * rx, 8 * ry
  self:setAnim(e, 0)
  -- round 7: HANGING_SEED (hangingSeed.c) hangs with frameIndex = type and
  -- only waits to be cut
  if dat.id == 0x06 then e.staticFrame = dat.paramA or 0; e.inert = true end
  require("src.zelda.tmc.EnemyTraps").init(self, e, dat) -- round 17: blade / sensor traps, wall masters, torch traps
  e.spawnB, e.spawnC = dat.paramB or 0, dat.paramC or 0 -- round 24: EntityData paramB (type2, timer) / paramC for EnemyCoF2
  return e
end

function Enemies:setAnim(e, index)
  if e.animIndex == index then return end
  e.animIndex = index
  e.anim:set(self.A:sprite(e.sprite), index, true)
end

function Enemies:inHome(e, x, y)
  return x - e.homeX >= 0 and x - e.homeX <= e.rangeW and y - e.homeY >= 0 and y - e.homeY <= e.rangeH
end

-- ProcessMovement0-like: move with tile collision; false when blocked
function Enemies:move(e, dir, speed)
  local vx, vy = dirVec(dir)
  local s = (speed or e.speed or 0x80) / 256
  local nx, ny = e.x + vx * s, e.y + vy * s
  local room = self.field.room
  local hb = e.hitbox
  local hw, hh = math.max(2, hb.w), math.max(2, hb.h)
  local cx, cy = nx + hb.x, ny + hb.y
  if room:isSolid(cx - hw, cy - hh) or room:isSolid(cx + hw - 1, cy - hh)
     or room:isSolid(cx - hw, cy + hh - 1) or room:isSolid(cx + hw - 1, cy + hh - 1)
     or not self:inHome(e, nx, ny) then
    return false
  end
  e.x, e.y = nx, ny
  return true
end

-- ---------------------------------------------------------------------------
-- Octorok (src/enemy/octorok.c)
-- ---------------------------------------------------------------------------
local WALK = { 30, 60, 60, 90 }       -- gOctorokWalkDuration
local SPIT = { [0] = 1, 0 }           -- gOctorokSpitChanceModifier
local NUT = { [0] = { 0, -3 }, { 4, 0 }, { 0, 2 }, { -4, 0 } } -- gOctorokNutOffset

local function octoPause(e)
  e.action = 1
  e.timer = band(math.random(0, 0xFFFF), 0x38) + 24
end

function Enemies:octorokTurn(e)
  local p = self.field.player
  local inHome = self:inHome(e, e.x, e.y)
  if inHome then
    if e.form == 1 and math.random(0, 3) == 0 and self:inHome(e, p.x, p.y) then
      e.dir = round8(dirTo(e.x, e.y, p.x, p.y))
    else
      e.dir = round8(math.random(0, 31))
    end
  elseif math.random(0, 3) ~= 0 then
    e.dir = round8(dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) + (math.random(0, 1) == 0 and 4 or -4))
  else
    e.dir = round8(math.random(0, 31))
  end
  e.animationState = rshift(e.dir, 3)
  self:setAnim(e, e.animationState)
end

function Enemies:octorok(e)
  local p = self.field.player
  if e.action == 0 then
    e.animationState = e.form == 2 and 2 or math.random(0, 3)
    e.dir = e.animationState * 8
    octoPause(e)
    self:setAnim(e, e.animationState)
  elseif e.action == 1 then
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.action = 2
      e.timer = WALK[math.random(1, 4)]
      self:octorokTurn(e)
    end
    e.anim:update(1)
  elseif e.action == 2 then
    self:move(e, e.dir)
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then
      local facing = round8(dirTo(e.x, e.y, p.x, p.y)) == e.dir
      if facing and (SPIT[e.form] or 1) <= math.random(0, 3) then
        e.action = 3
        self:setAnim(e, e.animationState + 4)
        e.spat = false
      else
        octoPause(e)
      end
    end
  elseif e.action == 3 then
    e.anim:update(1)
    if band(e.anim.flags or 0, 1) ~= 0 and not e.spat then
      e.spat = true
      local o = NUT[e.dir / 8] or NUT[0]
      self:projectile(e.x + o[1], e.y + o[2], e.dir)
      self.field:sound(0x18D) -- SFX_18D
    end
    if e.anim.done then octoPause(e) end
  end
end

-- ROCK_PROJECTILE: speed 640, 48 frames then falls (gProjectileDefinitions[1])
function Enemies:projectile(x, y, dir)
  local e = { kind = 4, x = x, y = y, z = 3, dir = dir, speed = 640, timer = 48, hitType = ROCK_HIT,
              sprite = 176, palette = self.A:objPalette(1), gfx = 1, anim = Anim.new(), literalAnim = true,
              projectile = true, hitbox = { x = 0, y = 0, w = 3, h = 3 }, field82 = 0, interactType = 0 }
  e.anim:set(self.A:sprite(176), 0, true)
  self.field.entities[#self.field.entities + 1] = e
end

function Enemies:updateProjectile(e)
  local f = self.field
  local vx, vy = dirVec(e.dir)
  local s = e.speed / 256
  e.x, e.y = e.x + vx * s, e.y + vy * s
  e.anim:update(1)
  e.timer = e.timer - 1
  if e.timer <= 0 or f.room:isSolid(e.x, e.y, 1) then e.deleted = true return end
  local p = f.player
  if math.abs(p.x - e.x) < 6 and math.abs((p.y - 4) - e.y) < 8 then
    e.deleted = true
    if p:blocksFrom(e.x, e.y) then f:sound(0x118) return end -- SFX_ITEM_SHIELD_BOUNCE
    local s2 = self:settings(e.hitType, HURT_PLAYER) or DEFAULT_TOUCH
    p:hurt(s2.tgtDmg, e.x, e.y)
  end
end

-- ---------------------------------------------------------------------------
-- per-enemy state machines (src/enemy/*.c)
-- ---------------------------------------------------------------------------
local function rnd(n) return math.random(0, n - 1) end
local function playerNear(self, e, r)
  local p = self.field.player
  return math.abs(p.x - e.x) <= r and math.abs(p.y - e.y) <= r and self:inHome(e, p.x, p.y)
end
local function toward(self, e) local p = self.field.player return dirTo(e.x, e.y, p.x, p.y) end
local function homeDir(e) return dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) end

-- KEESE (keese.c): fly a random time (180-720), rest (30-75), sleep when
-- Link is beyond $70 px; heading random in its home, homeward outside
local KEESE_FLY = { 180, 180, 300, 300, 300, 300, 300, 300, 480, 480, 480, 480, 480, 480, 720, 720 }
local KEESE_REST = { 30, 30, 45, 45, 45, 45, 45, 45, 60, 60, 60, 60, 60, 60, 75, 75 }
function Enemies:keese(e)
  local p = self.field.player
  local near = math.abs(p.x - e.x) < 0x70 and math.abs(p.y - e.y) < 0x70
  if e.action == 0 then
    e.dir = rnd(32)
    e.action, e.fly, e.sleepT = 1, KEESE_FLY[rnd(16) + 1], 60
    self:setAnim(e, 0)
  elseif e.action == 1 then
    e.fly = math.max(0, e.fly - 1); e.sleepT = math.max(0, e.sleepT - 1)
    e.anim:update(1)
    if e.anim.done then
      if e.fly == 0 then e.action, e.timer = 2, KEESE_REST[rnd(16) + 1]; self:setAnim(e, 1)
      elseif e.sleepT == 0 and not near then e.action, e.timer = 3, 30; self:setAnim(e, 1)
      else
        e.dir = self:inHome(e, e.x, e.y) and rnd(32) or homeDir(e)
        e.anim:set(self.A:sprite(e.sprite), 0, true)
      end
    else
      local vx, vy = dirVec(e.dir)
      local s = (e.speed ~= 0 and e.speed or 0x100) / 256
      e.x, e.y = e.x + vx * s, e.y + vy * s -- ProcessMovement1: flies over tiles
    end
    e.z = 4
  elseif e.action == 2 then
    e.timer = e.timer - 1
    if e.timer <= 0 then e.action = 0 end
  else
    if e.timer > 0 then e.timer = e.timer - 1 elseif near then e.action = 0 end
  end
end

-- CHUCHU type 0 (chuchu.c): a puddle until Link comes within $48 in its
-- home; rises, hops towards him (re-aimed every 8 frames, 12-15 frame
-- legs), jumps at him inside $38, rests 60 frames; sinks back when he
-- leaves.  Not hittable while a puddle.
function Enemies:chuchu(e)
  local a = e.action
  if a == 0 then e.action = 1; e.hidden = true
  elseif a == 1 then
    if playerNear(self, e, 0x48) then e.action = 2; e.hidden = false; self:setAnim(e, 0) end
  elseif a == 2 then
    e.anim:update(1)
    if e.anim.done then e.action, e.timer, e.sub = 3, rnd(4) + 12, rnd(256); e.dir = toward(self, e); self:setAnim(e, 2) end
  elseif a == 3 then
    e.sub = e.sub + 1
    if e.sub % 8 == 0 then e.dir = toward(self, e) end
    self:move(e, e.dir, e.speed ~= 0 and e.speed or 0x40)
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then
      if playerNear(self, e, 0x38) then
        -- round 11: chuchu.c sub_0801F1B0: hitType 90 while it jumps (it
        -- hurts Link, Minish too), 92 again once down (contact only pushes)
        e.action = 4; e.zv = 2.0; e.dir = toward(self, e); self:setAnim(e, 3); e.chuBase = e.chuBase or e.hitType; e.hitType = 90
      elseif playerNear(self, e, 0x48) then e.timer = rnd(4) + 12
      else e.action = 6; self:setAnim(e, 5) end
    end
  elseif a == 4 then
    self:move(e, e.dir, 0x100)
    e.z = e.z + e.zv; e.zv = e.zv - 0.25
    if e.z <= 0 then e.z, e.zv = 0, 0; e.action, e.timer = 5, 60; self:setAnim(e, 2); e.hitType = e.chuBase or e.hitType end
  elseif a == 5 then
    self:move(e, e.dir, 0x20)
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then e.action = 3; e.timer = 12; e.dir = toward(self, e) end
  elseif a == 6 then
    e.anim:update(1)
    if e.anim.done then e.action = 1; e.hidden = true end
  end
end

-- SLUGGULA (sluggula.c): type 0 hangs on the ceiling and drops when Link
-- is within $20 (falls from z 128); landed, it crawls (frame-stepped)
-- leaving slime, turning every 180-228 frames: homeward when outside,
-- else towards Link (8 at a time), else -8 / 0 / +8
function Enemies:sluggula(e)
  local p = self.field.player
  if e.action == 0 then
    if e.form == 0 then e.action, e.z, e.hidden = 10, 128, true
    else e.action = 1 end
    e.timer = rnd(64) + 180
    e.dir = round8(rnd(32)); e.animationState = rshift(e.dir, 3); self:setAnim(e, e.animationState)
  elseif e.action == 10 then
    if math.abs(p.x - e.x) <= 0x20 and math.abs(p.y - e.y) <= 0x20 then e.action = 11; e.hidden = false; e.zv = 0 end
  elseif e.action == 11 then
    e.zv = e.zv - 24 / 256 * 4
    e.z = e.z + e.zv
    if e.z <= 0 then e.z = 0; e.action = 1; self.field:sound(0x7D) end
  else
    if not self:move(e, e.dir, e.speed ~= 0 and e.speed or 0x40) then e.dir = (e.dir + 16) % 32 end
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.timer = rnd(64) + 180
      if not self:inHome(e, e.x, e.y) and rnd(2) == 1 then e.dir = round8(homeDir(e))
      elseif self:inHome(e, p.x, p.y) and rnd(4) ~= 0 then
        local d = (toward(self, e) - e.dir) % 32
        if d ~= 0 and ((d + 4) % 32) > 8 then e.dir = round8(e.dir + (d < 16 and 8 or -8)) end
      else e.dir = round8(e.dir + ({ 0, -8, 8 })[rnd(3) + 1]) end
      e.animationState = rshift(e.dir % 32, 3); self:setAnim(e, e.animationState)
    end
  end
end

-- ROPE (rope.c): wanders at $80 for 60-108 frames in a random cardinal;
-- when Link lines up (within 12 px on an axis, in its home) it charges at
-- $1A0 for 30 frames, then waits 30 before it can charge again
function Enemies:rope(e)
  local p = self.field.player
  local function wander()
    e.action, e.timer, e.spd = 2, rnd(64) + 60, 0x80
    e.dir = band(rnd(32), 0x18)
    e.animationState = rshift(e.dir, 3); self:setAnim(e, e.animationState)
  end
  if e.action == 0 then e.cool = 0; wander()
  elseif e.action == 2 then
    e.anim:update(1)
    e.cool = math.max(0, e.cool - 1)
    if e.cool == 0 and self:inHome(e, p.x, p.y) then
      local dir
      if math.abs(p.x - e.x) < 12 then dir = p.y > e.y and 16 or 0
      elseif math.abs(p.y - e.y) < 12 then dir = p.x > e.x and 8 or 24 end
      if dir then
        e.action, e.timer, e.spd, e.dir = 3, 30, 0x1A0, dir
        e.animationState = rshift(dir, 3); self:setAnim(e, e.animationState + 4)
        return
      end
    end
    if not self:move(e, e.dir, e.spd) then wander() end
    e.timer = e.timer - 1
    if e.timer <= 0 then wander() end
  else
    e.anim:update(2)
    e.timer = e.timer - 1
    if e.timer <= 0 or not self:move(e, e.dir, e.spd) then e.cool = 30; wander() end
  end
end

-- PEAHAT (simplified from peahat.c): flies turning by +-2 a frame,
-- bobbing; every 180-300 frames it lands for 90 frames, and only then
-- does the sword hurt it (e.grounded)
function Enemies:peahat(e)
  if e.action == 0 then
    e.action, e.timer, e.dir, e.turn = 1, rnd(120) + 180, rnd(32), rnd(2) == 0 and 2 or -2
    self:setAnim(e, 0)
  elseif e.action == 1 then
    e.grounded = false
    e.dir = (e.dir + e.turn / 8) % 32
    if rnd(32) == 0 then e.turn = -e.turn end
    local vx, vy = dirVec(e.dir)
    local s = (e.speed ~= 0 and e.speed or 0x80) / 256
    local nx, ny = e.x + vx * s, e.y + vy * s
    if self:inHome(e, nx, ny) then e.x, e.y = nx, ny else e.dir = homeDir(e) end
    e.bob = (e.bob or 0) + 1
    e.z = 6 + ({ 0, 1, 2, 1 })[math.floor(e.bob / 16) % 4 + 1]
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then e.action, e.timer = 2, 90 end
  else
    e.z = math.max(0, e.z - 0.5)
    e.grounded = e.z == 0
    e.timer = e.timer - 1
    if e.timer <= 0 then e.action = 0 end
  end
end

-- MULLDOZER (simplified from mulldozer.c): turns towards Link and
-- charges in straight lines; a wall or a sword hit stops it
function Enemies:mulldozer(e)
  local p = self.field.player
  if e.action == 0 then
    e.action, e.timer = 1, rnd(30) + 20
  elseif e.action == 1 then
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer <= 0 then
      e.dir = round8(toward(self, e))
      e.animationState = rshift(e.dir, 3); self:setAnim(e, e.animationState)
      e.action, e.timer = 2, 40
    end
  else
    e.anim:update(2)
    e.timer = e.timer - 1
    if not self:move(e, e.dir, 0x140) or e.timer <= 0 then e.action, e.timer = 1, rnd(30) + 30 end
  end
end

-- PUFFSTOOL (simplified from puffstool.c): wanders; spore-covered it
-- shrugs off the sword until the Gust Jar has sucked its spores away
-- (30 frames), then it can be hurt for 180 frames
function Enemies:puffstool(e)
  local p = self.field.player
  if e.action == 0 then e.action, e.timer, e.dir = 1, 60, rnd(32) end
  if p.state == "gust" and math.abs(p.x - e.x) < 40 and math.abs(p.y - e.y) < 40 then
    e.sucked = (e.sucked or 0) + 1
    if e.sucked >= 30 then e.bare = 180 end
  end
  if e.bare then e.bare = e.bare - 1; if e.bare <= 0 then e.bare = nil; e.sucked = 0 end end
  if not self:move(e, e.dir, 0x60) then e.dir = rnd(32) end
  e.timer = e.timer - 1
  if e.timer <= 0 then e.timer, e.dir = 60, rnd(4) == 0 and toward(self, e) or rnd(32) end
  e.anim:update(1)
end

-- the hit rules those state machines add
function Enemies:hitAllowed(e)
  if e.noHit then return false end -- round 25: COLLISION_OFF (EnemyCoF3)
  if e.id == ID.CHUCHU and (e.action == 1 or e.hidden) then return false end
  if e.id == ID.SLUGGULA and e.form == 0 and (e.action or 0) < 3 then return false end -- round 12: still hanging / falling
  -- round 20: no Peahat rule -- the matrix decides (hitType $70 flying vs the sword: no damage, knocked back $18 frames; $71 on the ground: hurt; bombs hurt it flying)
  if e.id == ID.PUFFSTOOL and not e.puffInit and not e.bare then return false end -- round 12: puffstool.c uses the matrix ($82 / $83)
  return true
end

-- ---------------------------------------------------------------------------
-- the shared model for the others: wait, hop/crawl towards Link inside
-- the home rectangle, with per-enemy pace
-- ---------------------------------------------------------------------------
local STYLE = {
  [ID.CHUCHU] = { wait = 40, go = 40, chase = true, hop = true },
  [ID.SLUGGULA] = { wait = 60, go = 60, chase = false },
  [ID.PESTO] = { wait = 20, go = 50, chase = true, fly = true },
  [ID.PUFFSTOOL] = { wait = 50, go = 40, chase = true },
  [ID.MULLDOZER] = { wait = 30, go = 30, chase = true, charge = 2.0 },
  [ID.ROPE] = { wait = 40, go = 50, chase = false, charge = 2.0 },
  [ID.KEESE] = { wait = 30, go = 40, chase = true, fly = true },
  [ID.PEAHAT] = { wait = 30, go = 60, chase = true, fly = true },
  [ID.SPINY_BEETLE] = { wait = 50, go = 30, chase = true },
}

function Enemies:generic(e)
  local st = STYLE[e.id] or { wait = 40, go = 40, chase = false }
  local p = self.field.player
  e.timer = e.timer - 1
  if e.action == 0 then
    e.action = 1
    e.timer = st.wait
  elseif e.action == 1 then
    if e.timer <= 0 then
      e.action = 2
      e.timer = st.go
      if st.chase and self:inHome(e, p.x, p.y) then e.dir = dirTo(e.x, e.y, p.x, p.y)
      else e.dir = math.random(0, 31) end
      e.animationState = rshift(round8(e.dir), 3)
      if st.hop then e.zv = 1.5 end
    end
  elseif e.action == 2 then
    local speed = (e.speed ~= 0 and e.speed or 0x80) * (st.charge or 1)
    if not self:move(e, e.dir, speed) then e.dir = (e.dir + 16) % 32 end
    if e.timer <= 0 then e.action = 1; e.timer = st.wait end
  end
  if st.hop and (e.z > 0 or e.zv > 0) then
    e.z = e.z + e.zv
    e.zv = e.zv - 0.125
    if e.z <= 0 then e.z = 0; e.zv = 0 end
  end
  local idx = e.animationState
  local s = self.A:sprite(e.sprite)
  if not (s and s.anims and s.anims[idx]) then idx = 0 end
  self:setAnim(e, idx)
  e.anim:update(1)
end

-- ---------------------------------------------------------------------------
-- frame, contact, damage, death
-- ---------------------------------------------------------------------------
function Enemies:update(e)
  local f = self.field
  if e.projectile then return self:updateProjectile(e) end
  if e.dying then
    e.dying = e.dying - 1
    if e.dying <= 0 then
      e.deleted = true
      local tbl = self.m.drops and self.m.drops.enemyMap and self.m.drops.enemyMap[e.id] or 6
      if tbl ~= 0 then f:objects():randomDrop(e, tbl) end
    end
    return
  end
  if e.boss then return (e.impl or self.boss):update(e) end
  if e.jarSub and require("src.zelda.tmc.GustJar").grabbedUpdate(self, e) then return end -- round 13: in the Gust Jar's pull
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  if e.kbt > 0 then
    e.kbt = e.kbt - 1
    local nx, ny = e.x + e.kbx, e.y + e.kby
    if not f.room:isSolid(nx, ny, 1) then e.x, e.y = nx, ny end
  elseif e.stunned and e.stunned > 0 then
    e.stunned = e.stunned - 1
  elseif e.inert then -- round 7: HangingSeed_Hang does nothing
  elseif e.id == ID.OCTOROK then self:octorok(e)
  elseif e.id == ID.KEESE then self:keese(e)
  elseif e.id == ID.CHUCHU and e.form == 0 then self:chuchu(e)
  elseif e.id == ID.SLUGGULA then require("src.zelda.tmc.EnemyDeepwood").slug.update(self, e) -- round 12: sluggula.c
  elseif e.id == ID.ROPE then self:rope(e)
  elseif e.id == ID.PEAHAT then require("src.zelda.tmc.EnemyCrenel").peahat(self, e) -- round 20: peahat.c (the older model: Enemies:peahat)
  elseif e.id == ID.MULLDOZER then require("src.zelda.tmc.EnemyDeepwood").mull.update(self, e) -- round 12: mulldozer.c
  elseif e.id == ID.PUFFSTOOL then require("src.zelda.tmc.EnemyDeepwood").puff.update(self, e) -- round 12: puffstool.c
  elseif require("src.zelda.tmc.EnemyTraps").handles(e) then require("src.zelda.tmc.EnemyTraps").update(self, e) -- round 17
  elseif require("src.zelda.tmc.EnemyCrenel").handles(e) then require("src.zelda.tmc.EnemyCrenel").update(self, e) -- round 19: tektite.c, fallingBoulder.c, smallPesto.c
  elseif require("src.zelda.tmc.EnemyCoF").handles(e) then require("src.zelda.tmc.EnemyCoF").update(self, e) -- round 23: spikedBeetle.c, helmasaur.c
  elseif require("src.zelda.tmc.EnemyCoF2").handles(e) then require("src.zelda.tmc.EnemyCoF2").update(self, e) -- round 24: spinyChuchu.c, chaser.c, rupeeLike.c
  elseif require("src.zelda.tmc.EnemyCoF3").handles(e) then require("src.zelda.tmc.EnemyCoF3").update(self, e) -- round 25: rupeeLike.c, chuchu.c type 1
  elseif require("src.zelda.tmc.R26").handles(e) then require("src.zelda.tmc.R26").update(self, e) -- round 26b: dungeon enemies (R26.lua)
  elseif require("src.zelda.tmc.EnemyField").handles(e) then require("src.zelda.tmc.EnemyField").update(self, e) -- round 26A: overworld enemies (EnemyField1/2.lua)
  elseif require("src.zelda.tmc.R27A").handles(e) then require("src.zelda.tmc.R27A").update(self, e) -- round 27A: leftover overworld enemies (R27A.lua)
  else
    self:generic(e)
  end
  -- touching Link
  local p = f.player
  if p.state ~= "dead" and p.invuln == 0 and (e.z or 0) < 8 and not e.hidden and not e.inert and not e.noTouch and (e.def.collision ~= 0 or e.action >= 2 or e.collideOn) then -- round 25: collideOn = an Init's COLLISION_ON (EnemyCoF3)
    local hb = e.hitbox
    -- round 11: Link's own hitbox and hurtType (0, Minish 1) from the ROM
    -- (Hitboxes.lua); CollisionNoOp entries (handler 1 / 2) let him pass,
    -- handler 16 (sub_08018228) only pushes him out
    local HBm = require("src.zelda.tmc.Hitboxes")
    local touch = HBm.touches(f, p, e)
    local handler = HBm.data(f) and HBm.handler(self.mtx, e.hitType or 0, HBm.hurtType(p))
    if touch == nil then
      touch = math.abs((e.x + hb.x) - p.x) < hb.w + 5 and math.abs((e.y + hb.y) - (p.y - 3)) < hb.h + 6
    end
    if touch and (handler == 1 or handler == 2) then touch = false end
    if touch and handler == 16 then HBm.pushOut(f, e, hb); touch = false end
    if touch then
      if p:blocksFrom(e.x, e.y) then
        f:sound(0x118)
        self:knock(e, p.x, p.y, 24, 8)
        if e.id == ID.MULLDOZER then e.mullShield = true end -- round 12: Mulldozer_OnCollision case 2/3
        if e.onCollision and require("src.zelda.tmc.EnemyCoF").handles(e) then e.onCollision(self, e, 0x80 + 2) end -- round 23: the shield's contact (hurtType 2): Spiked Beetle flip, Helmasaur recoil
      else
        local s = self:settings(e.hitType, HBm.data(f) and HBm.hurtType(p) or HURT_PLAYER) or DEFAULT_TOUCH
        if e.onCollision then e.onCollision(self, e, 0x80 + HBm.hurtType(p)) end -- round 21: contactFlags = Link's hurtType | $80
        if s.tgtDmg > 0 or s.orgKbDur > 0 then
          if p:hurt(math.max(s.tgtDmg, 1), e.x, e.y) then
            p.invuln = math.max(s.orgIfr, 30)
            p.timer = math.max(s.orgKbDur, 4)
            local ks = (s.orgKbSpd * 16) / 256
            local dx, dy = p.x - e.x, p.y - e.y
            local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
            p.kbx, p.kby = dx / d * ks, dy / d * ks
          end
        end
      end
    end
  end
end

function Enemies:knock(e, fromX, fromY, spd, dur)
  local dx, dy = e.x - fromX, e.y - fromY
  local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
  local s = (spd * 16) / 256
  e.kbx, e.kby = dx / d * s, dy / d * s
  e.kbt = dur
end

-- a hit from Link's item (hurtType: 4 sword); returns true when it landed
function Enemies:hit(e, hurtType, fromX, fromY, extraDamage)
  if e.dying or e.iframes > 0 or e.projectile or e.mask then return false end -- round 23: + the Helmasaur's mask
  if e.r26hit then local r = e.r26hit(self, e, hurtType, fromX, fromY, extraDamage) if r ~= nil then return r end end -- round 26b: per-enemy hit handlers (EnemyDHC: Dark Nut shield, slash parry, door mimic death)
  if not self:hitAllowed(e) then self.field:sound(0x118) return false end
  local s = self:settings(e.hitType, hurtType) or DEFAULT_SWORD
  -- round 23: handler 10 (collision.c sub_080180E8, the masked Helmasaur): an
  -- enemy moving within +-$C of straight at the attacker blocks (both knocked
  -- back 12 frames, iframes 16); otherwise row $352 (hitType $19) applies
  if self.mtx ~= "" and require("src.zelda.tmc.Hitboxes").handler(self.mtx, e.hitType or 0, hurtType) == 10 then
    local v3 = band(dirTo(fromX or e.x, fromY or e.y, e.x, e.y) + 0x10 - 0xC, 0x1F)
    if band((e.dir or 0) - v3, 0x1F) <= 0x18 then
      self.field:sound(0x118)
      self:knock(e, fromX or e.x, fromY or e.y, 48, 12)
      e.iframes = 16 -- (Link's own 12-frame push back is not ported)
      return false
    end
    s = self:settings(0x19, hurtType) or DEFAULT_SWORD
  end
  -- round 12: a spored Puffstool ($82) shrugs the sword off (no damage)
  if e.id == ID.PUFFSTOOL and e.puffInit and e.hitType == 0x82 then extraDamage = 0; require("src.zelda.tmc.EnemyDeepwood").puff.shrug(self, e) end
  local dmg = (s.orgDmg or 0) + (extraDamage or 0)
  -- round 21: the enemy's OnCollision sees contactFlags = hurtType | $80 (after the matrix's iframes)
  if dmg <= 0 and (s.tgtKbDur or 0) <= 0 then if e.onCollision then e.onCollision(self, e, 0x80 + hurtType) end return false end
  e.health = e.health - dmg
  e.iframes = (s.tgtIfr and s.tgtIfr > 0) and s.tgtIfr or 12
  self:knock(e, fromX, fromY, s.tgtKbSpd or 24, s.tgtKbDur or 12)
  if e.onCollision and e.health > 0 then e.onCollision(self, e, 0x80 + hurtType) end
  self.field:sound(SFX_HIT)
  if e.id == ID.MULLDOZER then e.mullHit = true end -- round 12: Mulldozer_OnCollision default
  if e.health <= 0 then self:kill(e) end
  return true
end

function Enemies:kill(e)
  if e.dying then return end
  e.dying = 18
  e.kbt = 0
  self.field.save.stats.kills = (self.field.save.stats.kills or 0) + 1
  self.field:addFx(e.x, e.y - 4, 0x0F, 2) -- SPECIAL_FX, FX_DEATH
  self.field:sound(0x1BC)
end

-- a thrown pot meets an enemy
function Enemies:hitByObject(o)
  for _, e in ipairs(self.field.entities) do
    if e.enemy and not e.dying and math.abs(e.x - o.x) < 10 and math.abs(e.y - o.y) < 10 then
      self:hit(e, HURT_SWORD, o.x, o.y, 2)
      return true
    end
  end
  return false
end

-- the sword's hitbox this frame, in room pixels {x, y, w, h} (half sizes)
function Enemies:swordHits(box)
  local hits = 0
  local p = self.field.player
  for _, e in ipairs(self.field.entities) do
    if e.boss and not e.dying then
      if (e.impl or self.boss):swordHit(e, box) then hits = hits + 1 end
    elseif e.enemy and not e.dying then
      local hb = e.hitbox
      if math.abs((e.x + hb.x) - box.x) < hb.w + box.w and math.abs((e.y + hb.y) - box.y) < hb.h + box.h then
        if self:hit(e, HURT_SWORD, p.x, p.y) then hits = hits + 1 end
      end
    end
  end
  return hits
end

-- Gust Jar: pull enemies in the cone towards Link; small ones are caught
local GUSTABLE = { [ID.CHUCHU] = false, [ID.SLUGGULA] = true, [ID.PESTO] = true, [ID.PUFFSTOOL] = true,
                   [ID.KEESE] = true, [ID.PEAHAT] = true, [ID.OCTOROK] = true }
function Enemies:gustPull(p, cx, cy, reach)
  local caught
  for _, e in ipairs(self.field.entities) do
    if e.enemy and not e.dying and e.id == ID.PUFFSTOOL and e.puffInit and math.abs(e.x - cx) < reach and math.abs(e.y - cy) < reach then
      -- round 12: Puffstool_OnGrabbed: held in the gust, its spores drain
      e.gusted = true; e.gustDir = (p.animationState or 0) * 4
    elseif e.enemy and not e.dying and math.abs(e.x - cx) < reach and math.abs(e.y - cy) < reach then
      local dx, dy = p.x - e.x, (p.y - 4) - e.y
      local d = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      e.stunned = 30
      if GUSTABLE[e.id] then
        e.x, e.y = e.x + dx / d * 1.5, e.y + dy / d * 1.5
        if d < 10 and not caught then caught = e end
      end
    end
  end
  return caught
end

return Enemies
