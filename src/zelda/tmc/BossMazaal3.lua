-- Round 26 (team B): inside Mazaal (AREA_INNER_MAZAAL $5A, rooms 0 / 1) --
-- src/enemy/mazaalMacro.c (MAZAAL_MACRO $37) and src/enemy/vaatiProjectile.c
-- (VAATI_PROJECTILE $4B, only ever made here).  Required by BossMazaal.lua.
--
-- MACRO type 0 (the room's entity): sub_08035084 picks the vulnerable
--   pillar (Random % 6, not the last one: f38 >> 4) of gUnk_080CEECC's six,
--   makes the other five (type 1) and moves there; each pillar: health =
--   f39, phase type2 by f39 ($3D+ / $1F+ / less), SPECIAL_TILE_34 under it,
--   a type 2 child (the core, layer 2, animation 2).  Type 0 then sends a
--   VAATI_PROJECTILE from the top every $4B0 / 600 frames (at most 8 alive,
--   else $78), type 1 waits for f39 = 0 (FX_GIANT_EXPLOSION4, its tile
--   back).  The sword (hitType $0F, 2 a hit, iframes 16; the core flashes,
--   shake 12) takes f39 down; under $3C / $1E (sub_08035050) the pillar
--   quits (health 0, collision off) and a VAATI_PROJECTILE type2 1 drops on
--   Link to carry him out; at 0 the boss dies (EnemyCreateDeathFX, progress,
--   SONG_STOP_BGM), the other pillars burst and the core (type 2, action 1)
--   runs script_MazaalMacroDefeated + script_PlayerDefeatedMazaal (120
--   frames, explosions every 16 frames over the screen, Link looks round)
--   -> gUnk_0813ABA8 ($58:16 at ($B8, $78)).
-- VAATI_PROJECTILE type 0: a child type 1 (its shadow ring, animation 1);
--   type2 0 floats at z -$18 toward Link (one turn step a frame, speed
--   $100 -> $180 after $4B1 frames), over him (8 px) it drops (10 frames,
--   z + 1 a frame), rises again, waits 15..30 and repeats; type2 1 (the
--   phase end) comes down from z -$80 on Link.  Touching full-size Link
--   (hitType $0E: sub_08018168) it takes him (control off), rises to -$18,
--   20 frames, then carries him south at $300 to the room's bottom ->
--   gUnk_0813AB94 ($58:16 at ($B8, $5C), Link Minish).  It dies when f39 is
--   0 or its parent is gone (the parent's subtimer counts it down).
-- SIMPLIFIED: sub_08035120 (the rubble tiles round the core, sub_0807B600)
--   and sub_0803E4D8 (leaf tiles under the carried Link) are not done; the
--   boss DEATH_FX is FX_GIANT_EXPLOSION4.
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local X = {}
X.PILLARS = { [0] = 0x58, 0x68, 0x88, 0x68, 0xB8, 0x68, 0x58, 0xA8, 0x88, 0xA8, 0xB8, 0xA8 } -- gUnk_080CEECC
X.EXPL = { [0] = 0x46, 0x46, 0x47, 0x48 }                                                  -- gUnk_080CEEC8

local M, C

function X.install(m, c)
  M, C = m, c
  C.TICK.macro = X.tick
  C.TICK.vproj = X.vprojTick
  C.SETUP.macro = function(e)
    e.u78, e.bossFlag = 0, true
    e.onCollision = X.onCollision
  end
  C.SETUP.vproj = function(e)
    e.u78 = 0
    e.knockable = true
    e.onCollision = X.vprojCollision
  end
end

local function tileOf(e) return math.floor(e.x / 16), math.floor(e.y / 16) end
local function block(f, e, on)
  local d = f._dungeon
  if not d or not d.block then return end
  local tx, ty = tileOf(e)
  if on then
    if e.blockAt then return end
    e.blockAt = { tx, ty, math.min(e.layer or 1, 2) }
    d:block(tx, ty, e.blockAt[3], true)
  elseif e.blockAt then
    d:block(e.blockAt[1], e.blockAt[2], e.blockAt[3], false) -- RestorePrevTileEntity
    e.blockAt = nil
  end
end
X.block = block

-- sub_08035084
function X.layout(f, e)
  if e.type ~= 0 then return true end
  local T = C.state(f)
  local v
  repeat v = C.rand(f) % 6 until v ~= rshift(T.f38, 4)
  T.f38 = bor(band(T.f38, 0xF), v * 16)
  for i = 0, 5 do
    local pt = (i == v) and e or C.new(f, 3, M.ID.MACRO, 1, e.x, e.y, "macro")
    pt.x, pt.y = X.PILLARS[i * 2], X.PILLARS[i * 2 + 1]
    pt.layer = 1
  end
  return true
end

function X.phase(f, e) -- sub_08034F70
  local T = C.state(f)
  e.health = T.f39
  if T.f39 >= 0x3D then e.type2 = 0 elseif T.f39 >= 0x1F then e.type2 = 1 else e.type2 = 2 end
end

-- sub_08035050: the phase is over, Link is fetched
function X.quit(f, e)
  e.collide = false
  e.health = 0
  local v = C.new(f, 3, M.ID.VPROJ, 0, e.x, e.y, "vproj")
  v.type2 = 1
  v.layer = 2
  v.parent = nil
  return v
end

-- MazaalMacro_OnCollision -> sub_08034FA0
function X.onCollision(f, E, e, cf)
  local T = C.state(f)
  if e.iframes > 0 then
    if e.child then e.child.iframes = e.iframes end
    C.shake(f, 12, 1)
  end
  if e.type2 == 0 then
    if e.health < 0x3C then T.f39 = 0x3C; X.quit(f, e) return end
  elseif e.type2 == 1 then
    if e.health < 0x1E then T.f39 = 0x1E; X.quit(f, e) return end
  else
    if e.health == 0 then block(f, e, false) end
  end
  T.f39 = e.health
end

local function core(f, e) -- type 2 (gUnk_080CEEB0)
  local a = e.action
  local par = e.parent
  if a == 0 then -- sub_08034E30
    e.action = par.type + 1
    e.layer = 2
    e.spritePriority = 7
    e.drawOn = true
    C.anim(e, 2)
  elseif a == 1 then -- sub_08034E68
    if C.gone(par) then
      if e.drawOn then e.drawOn = false end -- (+ sub_08035120)
      local T = C.state(f)
      if T.f39 == 0 then
        local p = f.player
        if p.state == "normal" or p.state == "sword" or p.state == "shield" then
          e.action = 3
          e.mzScript = { t = 0, phase = 0 }
          C.freeze(f) -- SetPlayerIdle
        end
      else
        C.delete(e)
      end
    end
  elseif a == 2 then -- sub_08034EC0
    if C.gone(par) then C.delete(e) end
  elseif a == 3 or a == 4 then -- sub_08034ED8 / sub_08034EE4 + the scripts
    if a == 4 then
      e.timer = band(e.timer + 1, 0xFF)
      if band(e.timer, 0xF) == 0 then
        local r = C.rand(f)
        local x = band(rshift(r, 2), 0x77) * 2 + 1 + (f.camX or 0)
        local y = band(rshift(r, 9), 0x7E) + 1 + (f.camY or 0)
        C.fx(f, x, y, X.EXPL[band(r, 3)])
      end
    end
    X.defeatScript(f, e)
  elseif a == 5 then -- sub_08034F58: gUnk_0813ABA8
    C.exit(f, C.AREA_FOW, C.ROOM_MAZAAL, 0xB8, 0x78, 0, "normal")
    C.delete(e)
  end
end

-- script_MazaalMacroDefeated (the core) + script_PlayerDefeatedMazaal (Link)
local LOOKS = { { 0x3C, nil }, { 0xF, 4 }, { 0x12, 2 }, { 0xC, 6 }, { 0x15, 0 }, { 8, 4 } }
function X.defeatScript(f, e)
  local s = e.mzScript
  local p = f.player
  s.t = s.t + 1
  if s.phase == 0 then -- Wait $78, SetAction 4, StartPlayerScript
    if s.t >= 0x78 then s.phase, s.t, s.look = 1, 0, 1; e.action = 4 end
  elseif s.phase == 1 then -- Link: Wait $3C, then the looks round, SetSyncFlag 2
    local L = LOOKS[s.look]
    if s.t >= L[1] then
      s.t = 0
      s.look = s.look + 1
      local nx = LOOKS[s.look]
      if nx then if nx[2] then p.animationState = nx[2] end
      else s.phase = 2; s.walk = true end
      if L == LOOKS[1] then p.animationState = 4 end
    end
  elseif s.phase == 2 then -- WaitForSyncFlagAndClear 2, Wait $C, SetAction 5
    if s.t >= 0xC then e.action = 5 end
  end
  if s.walk then -- MoveTo($88, $158) at $140
    local dx, dy = 0x88 - p.x, 0x158 - p.y
    local d = math.sqrt(dx * dx + dy * dy)
    local sp = 0x140 / 256
    if d > sp then p.x, p.y = p.x + dx / d * sp, p.y + dy / d * sp end
  end
end

function X.tick(f, E, e)
  if e.type == 2 then return core(f, e) end
  if e.health == 0 and e.action ~= 0 then -- GenericDeath
    local T = C.state(f)
    if e.type == 0 then
      if T.f39 ~= 0 then C.delete(e) return end -- EnemyCreateDeathFX: id $37 with f39 set
      C.bossDeath(f, e)
      return
    end
  end
  local a = e.action
  if a == 0 then -- sub_08034CC4
    if X.layout(f, e) then
      e.action = e.type + 1
      e.subtimer = 0
      e.bossFlag = true
      e.u78 = 0x4B0
      X.phase(f, e)
      e.drawOn = true
      C.anim(e, e.type)
      block(f, e, true)
      local c = C.new(f, 3, M.ID.MACRO, 2, e.x, e.y, "macro")
      e.child = c
      c.parent = e
      C.copyPos(e, c)
    end
  elseif a == 1 then -- sub_08034D4C
    C.next(e)
    e.u78 = e.u78 - 1
    if e.u78 == 0 then
      local alive = 0
      for _, v in ipairs(f.entities) do if v.mz == "vproj" and v.type == 0 and v.parent == e and not v.deleted then alive = alive + 1 end end
      e.subtimer = alive
      if e.subtimer < 8 then
        local v = C.new(f, 3, M.ID.VPROJ, 0, e.x, e.y, "vproj")
        v.direction = C.rand(f) % 5 + 0xC
        v.x = math.floor((f.room and f.room.width or 0x110) / 2)
        v.y = 8
        v.layer = 2
        v.parent = e
        e.u78 = 600
        e.subtimer = e.subtimer + 1
      else
        e.u78 = 0x78
      end
    end
  elseif a == 2 then -- sub_08034DC8
    if C.state(f).f39 == 0 then
      C.fx(f, e.x, e.y, C.FX.GIANT4)
      block(f, e, false)
      C.delete(e)
    end
  end
end

-- ---------------------------------------------------------------------------
-- VAATI_PROJECTILE ($4B)
-- ---------------------------------------------------------------------------
local function dead(f, v) -- sub_0803E4A0
  local T = C.state(f)
  if T.f39 == 0 then return true end
  if v.parent == nil then return false end
  return v.parent.health == 0 or C.gone(v.parent)
end

local function carry(f, v) -- sub_0803E444: Link under it
  local p = f.player
  if p.state == "dead" then return end
  p.mazaalHeld = v
  p.state = "ext"
  p.extUpdate = p.extUpdate or function() end
  p.x, p.y = v.x, v.y - 2
  p.z = 0 -- (the carried height is drawn as a sprite offset: no z left over after the room change)
  p.spriteOY, p.spriteOYFrame = 0xE + math.floor(v.cz or 0), f.frame
end

function X.vprojCollision(f, E, v, cf)
  -- the sword: GenericKnockback2 only (contactFlags != CONTACT_NOW)
end

local function grab(f, v) -- VaatiProjectile_OnCollision (contact with Link, hurtType 0)
  local p = f.player
  if v.health ~= 0 then
    v.action = 5
    v.collide = false
    carry(f, v)
    if v.parent then v.parent.collide = false end
  end
end

local VA = {}
X.VA = VA
VA[0] = function(f, v)
  if v.type == 0 then
    local c = C.new(f, 3, M.ID.VPROJ, 1, v.x, v.y, "vproj")
    c.parent = v
    v.child = c
    if v.type2 == 0 then v.action = 1; v.cz = -0x18
    else v.action = 9; v.cz = -0x80 end
    v.drawOn = true
    C.anim(v, 0)
  else
    v.action = 8
    v.collide = false
    v.spriteOY = 1
    v.drawOn = true
    C.rel(v.parent, v, 0, -1)
    C.anim(v, 1)
  end
end
VA[1] = function(f, v)
  if v.u78 >= 0x4B1 then v.speed = 0x180 else v.u78 = v.u78 + 1 end -- sub_0803E480
  local p = f.player
  if C.within(v, p.x, p.y, 8) then -- PlayerInRange(.., 0, 8)
    v.action, v.timer = 2, 10
    C.anim(v.child, 2)
  else
    C.turn(v, C.facing(v, p))
    C.move(v)
  end
  C.next(v)
end
VA[2] = function(f, v)
  if v.timer ~= 0 then v.timer = v.timer - 1
  else
    v.cz = v.cz + 1
    if v.cz >= 0 then v.cz = 0; v.action = 3 end
  end
  C.next(v)
end
VA[3] = function(f, v)
  if C.done(v.child) then
    v.cz = v.cz - 1
    if v.cz <= -0x18 then
      v.action = 4
      v.timer = band(C.rand(f), 0xF) + 15
      C.anim(v.child, 1)
    end
    C.next(v)
  end
end
VA[4] = function(f, v)
  v.timer = v.timer - 1
  if v.timer == 0 then v.action = 1; v.direction = C.facing(v, f.player) end
  C.next(v)
end
VA[5] = function(f, v)
  carry(f, v)
  if v.timer ~= 0 then v.timer = v.timer - 1
  else
    v.cz = v.cz - 1
    if -0x18 < v.cz then return end
    v.action, v.timer = 6, 20
  end
end
VA[6] = function(f, v)
  v.timer = v.timer - 1
  if v.timer == 0 then v.action = 7; v.direction = 0x10; v.speed = 0x300 end
  carry(f, v)
end
VA[7] = function(f, v)
  carry(f, v)
  C.move(v)
  local h = f.room and f.room.height or 0x100
  if v.y >= h - 0x10 and not f.transition then
    C.exit(f, C.AREA_FOW, C.ROOM_MAZAAL, 0xB8, 0x5C, 4, "minish") -- gUnk_0813AB94
    v.exited = true
  end
end
VA[8] = function(f, v)
  if C.gone(v.parent) then C.delete(v) return end
  C.rel(v.parent, v, 0, -1)
  C.next(v)
end
VA[9] = function(f, v)
  local p = f.player
  v.x, v.y = p.x, p.y
  if v.cz < -8 then
    if v.animIndex ~= 2 then v.timer = 0; C.anim(v.child, 2) end
    VA[2](f, v)
  else
    v.cz = v.cz + 8
  end
end

function X.vprojTick(f, E, v)
  if v.type == 0 and dead(f, v) then
    v.collide = false
    v.health = 0
    v.parent = nil
  end
  if v.health == 0 then -- VaatiProjectile_OnDeath -> GenericDeath
    if f.player.mazaalHeld == v then C.release(f); f.player.mazaalHeld = nil; f.player.state = "normal"; f.player.extUpdate = nil end
    C.fx(f, v.x, v.y + (v.cz or 0), C.FX.DEATH)
    f:sound(0x1BC)
    C.delete(v)
    return
  end
  local fn = VA[v.action]
  if fn then fn(f, v) end
  if v.deleted or v.type ~= 0 then return end
  -- hitType $0E against Link: sub_08018168 (full size only)
  if v.collide and (v.action == 1 or v.action == 2 or v.action == 3 or v.action == 4 or v.action == 9) then
    local r = C.touch(f, v)
    if r == 15 then grab(f, v) end
  end
end

return X
