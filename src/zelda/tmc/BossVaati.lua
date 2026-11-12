-- Round 26 (team B): Vaati Reborn -- the first Vaati fight (Dark Hyrule
-- Castle, area $88 room 6), from the decomp, plus VAATI_PROJECTILE ($4B,
-- the shrink-ray hand Mazaal's macro creates).
--
-- MODEL: every part is a regular enemy entity in f.entities (kind 3,
--   e.enemy, e.r26 = this module) so Field draws it from its sprite /
--   animation and Enemies does contact (the collision matrix + OnCollision
--   = e.onCollision(E, e, hurtType | $80)) and hits (Enemies:hit / the
--   sword).  The projectiles are entities too (e.vproj, id $1000 + the
--   projectile id so no enemy module claims them).  COLLISION_OFF is
--   e.mask + e.noTouch (Enemies:hit ignores a masked enemy silently).
--   Health is kept biased (H.BIAS + the u8 health) so Enemies:hit never
--   runs its own kill: each part runs its decomp OnDeath / GenericDeath.
--   z: e.cz is the cartridge z in pixels (negative = up), e.czv its
--   zVelocity (px / frame, positive = up); e.z = -e.cz for drawing.
--
-- VAATI_REBORN_ENEMY ($4A, src/enemy/vaatiRebornEnemy.c):
--   type 0 (the body).  Action 0 waits for room flag 0 (the intro script
--     script_Vaati1Intro sets it; local flag $7B deletes him), then: action
--     3 (unk_74 $FF), drawn, unk_80 2, unk_85 $30, and creates type 1 (the
--     eye, child), six VAATI_BALL type 0 (unk_79 = i), four type 3 (timer =
--     i) and two VAATI_BALL type 1 at +-16, -43 (gUnk_080D04A8, flipX).
--   PreAction (VaatiRebornEnemyType0PreAction): unk_78 / unk_7c = x / y
--     (the balls follow his motion), the home rectangle turn (sub_08049FA0
--     / sub_08049EE4: back east / west toward its centre, unk_76 16), and
--     with no balls left (unk_80 0) the wobble (spriteOffsetX gUnk_080D04D3).
--   1 (float): timer -> sub_0803DD78 picks the next move by phase (unk_86)
--     and step (unk_83): unk_75 (1 teleport, 2 teleport onto Link) and
--     unk_77 (frames to the next attack, $50 or 1); unk_74 & $70 (set by
--     the eye when hit) -> action 3.  unk_77 out -> sub_0803DEE0 picks
--     0 fire (action 4), 1 dark magic (6), 3 summon (5) or 2 drift; the y
--     bob by unk_85, ProcessMovement1.
--   2 (teleport): anim 3 + SFX_19B, hidden, a spot gUnk_080D04AC (unk_81 +=
--     1..4, % 5) or above Link (sub_0803E028), anim 4 + SFX_F5, repeat
--     unk_77 times.
--   3 (gather): $FF: rises to z -4 until both type-1 balls arrive (timer
--     2) -> $FE; 0 -> 1: timer $14 / $20, unk_80 = ((unk_86+1) >> 1) * 2 + 2
--     balls; 1 -> anim 1 (+ SFX_1B0); 2 anim done -> 3 -> action 1.
--   4 (fire): anim 1, every frame flag $10 one V1_FIRE_PROJECTILE (type
--     gUnk_080D04C0[Direction8RoundUp(to Link) >> 2], subtimer 0..15), 160
--     frames, then turned round.
--   5 (summon): anim 1, frame $10 -> SFX_SUMMON, 64..127 frames (phase 2+:
--     up to 4 drifts toward Link), 48 frames, action 1; no balls -> 1.
--   6 (dark magic): waits for the balls (timer), 112 frames (SFX_196 at
--     $40), SFX_150 + V1_DARK_MAGIC_PROJECTILE 16 px above; its death sets
--     unk_74 3 -> SFX_14F, back to 1.
--   7 (death): 128 frames of FX_DEATH every 8 (random +-32), then room flag
--     1 (script_CutsceneOrchestratorV1Defeated takes over).
--   type 1 (the eye, hitType $2F; $30 once unk_80 is 0 = all balls gone):
--     PreAction: a hit (contactFlags, iframes > 0) -> SFX_BOSS_HIT, shake
--     12, 72 frames; health under gUnk_080D04D0[unk_86] (-24 / -40 / -48)
--     -> the next phase (unk_74 $70, health $FF) or, the third time, the
--     death (action 7, BGM stopped).  Action 1 follows the body (y + 1),
--     its animation (0 closed, 1 opening, 2 open), the body's contact
--     copied to it, collision off while the body teleports.
--   type 2 (the cloak, child of the eye) / type 3 (four parts at
--     gUnk_080D04C8): follow, animation = direction >> 3 while he moves.
-- VAATI_BALL ($54, src/enemy/vaatiBall.c): type 0 the six balls (actions
--   1 circle, 2 teleport, 3 gather / sub_08044DEC spread, 5 the eye-laser
--   dance, 6 the dark-magic dance), type 1 the two side balls flying into
--   him at the start; health under $FD -> gone (unk_80 - 1, SFX_1C3);
--   contact with Link in action 6 ModHealth(-2); phase 3 ($86 > 1) a ball
--   carries a V1_DARK_MAGIC_PROJECTILE type2 1 (hitType 0 until it is
--   broken).  sub_08044E74 resets the circle.
-- V1_DARK_MAGIC_PROJECTILE (projectile $18): type 0 homes on Link (a turn
--   every 4 frames, 300 frames); touching Link grabs him (action 2:
--   mobility locked, ModHealth(-4) every 30 frames after 60, each new
--   button press +1..2, 49 frees him with iframes $F0); its death sets the
--   parent's unk_74 3.  Type 1 is the overlay copy.  type2 1 sits on a
--   ball (hitType $2C) and its death gives the ball back hitType $2B.
-- V1_FIRE_PROJECTILE ($1A): falls from the body's height to a target from
--   gUnk_0812A4EC[type << 5 | subtimer << 1] (distance +-rand $1FF),
--   anims $51 / $54 / $53, SFX_1B5; contact -> $53 + ModHealth(-4).
-- V1_EYE_LASER ($1C): type 0 on a ball (anim 0 -> 1), then the beam
--   segments down to y $D4 (sub_080AB758: 62 / 30 / 14 / 6 px pieces, anims
--   4 / 3 / 2 / 1 / 6) with their hitboxes (gUnk_0812A5F4 cycle), following
--   the ball's x; gone when the ball's subtimer is 0.
-- VAATI_PROJECTILE ($4B, src/enemy/vaatiProjectile.c, created by Mazaal's
--   macro): type 0 hovers (z -24) homing on Link (speed $180 after $4B1
--   frames), over him (PlayerInRange 8) it drops (action 2/3, the child
--   type 1's anim 2) and rises again; touching Link grabs him (action 5-7:
--   carried south at $300, Link's sprite +14) and at the room's bottom
--   edge the exit to Mazaal's room as Minish (gUnk_0813AB94).  type2 1
--   starts at z -128 over Link.  Dropped when its parent is gone.
-- SIMPLIFIED: ProcessMovement1 is the port's move0 (tile collision);
--   sub_0807B7D8 / SPECIAL_TILE_116 tile writes of the fire / the hand are
--   not done; FX are the port's addFx; SortEntityAbove / OAM ordering is
--   the draw sort; gArea.bgm after the death is just the BGM stop.  The
--   dark magic's OnGrabbed (the Gust Jar strips it off a ball in phase 3)
--   runs through GustJar.grabbedUpdate's onGrabbed / onJarLost / onJarPull
--   hooks; GustJar's own grabbable() (not boss, z <= 8, matrix handler 4)
--   decides the contact.
local bit = require("bit")
local band, bor, bxor, bnot, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local M = {}
M.REBORN, M.VPROJ, M.BALL = 0x4A, 0x4B, 0x54
M.P_DARK, M.P_FIRE, M.P_LASER = 0x18, 0x1A, 0x1C
local PID = 0x1000 -- projectile entities: id = PID + projectile id

local SFX = { S19B = 0x19B, F5 = 0xF5, S1B0 = 0x1B0, SUMMON = 0xF4, S150 = 0x150, S196 = 0x196, S14F = 0x14F,
              BOSS_HIT = 0x127, S1C3 = 0x1C3, GLOVES = 0x119, VO6 = 0x7A, S1B5 = 0x1B5, S198 = 0x198 }
M.SFX = SFX
local SPECIAL_FX, FX_DEATH = 0x0F, 0x02

-- vaatiRebornEnemy.c tables
local SIDE_BALLS = { [0] = { 16, -43 }, { -16, -43 } }                                         -- gUnk_080D04A8
local SPOTS = { [0] = { 0x58, 0x60 }, { 0x58, 0x90 }, { 0x98, 0x78 }, { 0xD8, 0x60 }, { 0xD8, 0x90 } } -- gUnk_080D04AC
local FIRE_TYPE = { [0] = 2, 0, 0, 2, 2, 2, 4, 4 }                                             -- gUnk_080D04C0
local PARTS3 = { [0] = { 10, -29 }, { -10, -29 }, { 15, -21 }, { -15, -21 } }                  -- gUnk_080D04C8
local PHASE_HP = { [0] = 232, 216, 208 }                                                         -- gUnk_080D04D0 (-24, -40, -48; USA)
local WOBBLE = { [0] = 0, 1, 0, -1 }                                                             -- gUnk_080D04D3
-- vaatiBall.c tables
local BALL_START = { [0] = { -48, 0 }, { 0, -48 }, { 48, 0 }, { 0, 48 } }                       -- gUnk_080D1620
local BALL_DIRS = { [0] = { [0] = 16, 24, 0, 8 }, { [0] = 8, 24, 0, 16 }, { [0] = 0, 11, 21, 16 }, { [0] = 16, 24, 0, 8 } } -- gUnk_080D1628
-- v1FireProjectile.c gUnk_0812A4EC (s8 x, y pairs; index type << 5 | subtimer << 1)
local FIRE_TGT = { [0] = 16, 0, 64, -48, 80, -32, 80, 0, 80, 32, 64, 48, 32, 16, 48, 0, 32, -16,
  80, -64, 80, -64, 32, 0, 48, -32, 64, -16, 64, 16, 48, 32, 16, 16, 64, 16,
  64, 32, 48, 48, 32, 64, 16, 64, 16, 32, 32, 16, 80, 16, 80, 48, 64, 64,
  48, 80, 16, 80, 16, 48, 32, 32, 48, 16, 0, 16, -48, 48, -32, 64, 32, 64,
  48, 48, 80, 80, 0, 80, -80, 80, 0, 32, 64, 64, 48, 80, -48, 80, -64, 64,
  -16, 16, 0, 48, 16, 16, -16, 16, -64, 16, -64, 32, -48, 48, -32, 64, -16, 64,
  -16, 32, -32, 16, -80, 16, -80, 48, -64, 64, -48, 80, -16, 80, -16, 48, -32, 32,
  -48, 16, -16, 0, -64, -48, -80, -32, -80, 0, -80, 32, -64, 48, -32, 16, -48, 0,
  -32, -16, -80, -64, -80, -64, -32, 0, -48, -32, -64, -16, -64, 16, -48, 32 }
-- v1EyeLaser.c hitboxes ({x, y, w, h})
local HB_614 = { x = 0, y = 4, w = 1, h = 3 }
local HB_61C = { x = 0, y = 8, w = 1, h = 6 }
local HB_624 = { x = 0, y = 24, w = 1, h = 6 }
local HB_62C = { x = 0, y = 40, w = 1, h = 6 }
local HB_634 = { x = 0, y = 56, w = 1, h = 6 }
local LASER_HB = { [0] = HB_61C, HB_61C, HB_624, HB_61C, HB_62C, HB_624, HB_634, HB_624 } -- gUnk_0812A5F4
M.T = { SIDE_BALLS = SIDE_BALLS, SPOTS = SPOTS, FIRE_TYPE = FIRE_TYPE, PARTS3 = PARTS3, PHASE_HP = PHASE_HP, WOBBLE = WOBBLE,
        BALL_START = BALL_START, BALL_DIRS = BALL_DIRS, FIRE_TGT = FIRE_TGT, LASER_HB = LASER_HB }

-- ===========================================================================
-- shared helpers (BossVaati2 uses them too: M.H)
-- ===========================================================================
local H = {}
M.H = H
H.BIAS = 0x1000
function H.hp(e) return math.max(0, math.min(255, (e.health or 0) - H.BIAS)) end
function H.setHp(e, v) e.health = H.BIAS + band(v, 0xFF) end
function H.R(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end
local SIN = {}
for i = 0, 255 + 64 do SIN[i] = math.floor(math.sin((i % 256) * math.pi / 128) * 256 + 0.5) end -- gSineTable ($100 = 1)
H.SIN = SIN
-- CalculateDirectionTo / GetFacingDirection (0-31)
function H.dirTo(ax, ay, bx, by)
  local a = math.atan2(bx - ax, -(by - ay))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
-- LinearMoveDirection(e, speed, dir): no move when dir & $80
function H.moveDir(e, speed, dir)
  if band(dir or 0xFF, 0x80) ~= 0 then return end
  local m = band(dir, 0x1F) * 8
  e.x = e.x + SIN[m] * speed / 65536
  e.y = e.y - SIN[m + 64] * speed / 65536
end
function H.linMove(e) H.moveDir(e, e.speed or 0, e.direction) end -- LinearMoveUpdate
-- sub_08004596: one step of direction toward `want`
function H.turnTo(e, want)
  local d = band(want - (e.direction or 0), 0x1F)
  if d ~= 0 then e.direction = band((e.direction or 0) + (d < 0x10 and 1 or -1), 0x1F) end
end
-- PositionRelative: x, y, z (and layer) from the source
function H.posRel(src, dst, dx, dy)
  dst.x, dst.y = src.x + (dx or 0), src.y + (dy or 0)
  dst.cz = src.cz or 0
  dst.layer = src.layer
end
function H.within(e, x, y, d) local dx, dy = math.floor(e.x) - math.floor(x), math.floor(e.y) - math.floor(y) return dx * dx + dy * dy <= d * d end -- EntityWithinDistance
-- GravityUpdate (cz px, negative up; czv px/frame, positive up): false on landing
function H.gravity(e, acc)
  local nz = (e.cz or 0) - (e.czv or 0)
  if nz >= 0 then e.cz, e.czv = 0, 0 return false end
  e.cz, e.czv = nz, (e.czv or 0) - acc
  return true
end
-- BounceUpdate: 2 in the air, 1 bounced, 0 stopped
function H.bounce(e, acc)
  local nz = (e.cz or 0) - (e.czv or 0)
  if nz < 0 then e.cz, e.czv = nz, (e.czv or 0) - acc return 2 end
  e.cz = 0
  local v = -((e.czv or 0) - acc)
  v = v / 2 + v / 8
  if v >= 0.75 then e.czv = v return 1 end
  e.czv = 0
  return 0
end
function H.syncZ(e) e.z = -(e.cz or 0) end
-- the animation: InitializeAnimation (force), the frame flags with the
-- bits the code cleared on this keyframe, ANIM_DONE
function H.setAnim(E, e, i)
  e.animIndex = i
  e.fmask = 0
  if e.sprite then e.anim:set(E.A:sprite(e.sprite), i, true) end
end
function H.step(e) -- UpdateAnimationSingleFrame / GetNextFrame
  local a = e.anim
  local k0, t0 = a.key, a.timer
  a:update(1)
  if a.key ~= k0 or a.timer >= t0 then e.fmask = 0 end
end
function H.flags(e) return band(e.anim.flags or 0, bnot(e.fmask or 0)) end
function H.clearFlag(e, m) e.fmask = bor(e.fmask or 0, m) end
function H.done(e) return band(H.flags(e), 0x80) ~= 0 end
function H.frameIndex(e) return e.staticFrame or e.anim.frame end
-- ChangeObjPalette
function H.palette(E, e, id)
  local f = E.field
  rawset(e.def, "palette", id)
  e.palette = E.A:objPalette(id, f.room.atlas and f.room.atlas.palettes)
end
function H.colOn(e) e.mask, e.noTouch = nil, nil e.collide = true end
function H.colOff(e) e.mask, e.noTouch = true, true e.collide = false end
function H.draw(e, on) e.hidden = not on end
function H.drawn(e) return not e.hidden end
-- ModHealth(n) (no knockback / hurt state)
function H.modHealth(f, n)
  f:modStat("health", n)
  local p = f.player
  if n < 0 and (f.save.stats.health or 0) <= 0 and p.state ~= "dead" then
    p.state, p.timer = "dead", 90
    f:sound(0x87)
  end
end
function H.fx(f, x, y, id) f:addFx(x, y, SPECIAL_FX, id) end
function H.target(f) return require("src.zelda.tmc.EnemyDeepwood").target(f) end
function H.alive(e) return e ~= nil and not e.deleted and not e.dying end -- (parent->next != NULL)
function H.delete(e) e.deleted = true end

local function onCollision(E, e, fl)
  e.cflags = fl
  if not e.keepKb then e.kbt = 0 end
  if e.onCol then e.onCol(E, e, fl) end
end
H.onCollision = onCollision

-- a part: an enemy entity from gEnemyDefinitions[id] (form)
function H.enemy(E, owner, id, form, x, y, parent, noAppend)
  local f = E.field
  local d = E:def(id, form) or {}
  local e = {
    kind = 3, id = id, form = form, type = form, type2 = 0, x = x, y = y, z = 0, zv = 0, cz = 0, czv = 0,
    speed = d.speed or 0, hitType = d.damageType or 0, hitbox = d.hitbox or { x = 0, y = 0, w = 6, h = 6 },
    sprite = d.sprite, gfx = Assets.gfxSource("enemy", d.gfx or 0), anim = Anim.new(),
    animationState = 0, action = 0, subAction = 0, timer = 0, subtimer = 0, iframes = 0, kbt = 0,
    enemy = true, literalAnim = true, field82 = 0, interactType = 0, direction = 0, spritePriority = 4,
    def = setmetatable({}, { __index = d }), collideOn = true, parent = parent, r26 = owner,
    homeX = x, homeY = y, rangeW = 0, rangeH = 0, layer = parent and parent.layer or 1, fmask = 0,
  }
  e.palette = E.A:objPalette(d.palette or 0, f.room.atlas and f.room.atlas.palettes)
  H.setHp(e, d.health or 0xFF)
  e.maxHealth = e.health
  e.hidden = (d.draw == 0)
  if d.collision == 0 then H.colOff(e) else e.collide = true end
  e.onCollision = onCollision
  if parent then H.posRel(parent, e) end
  if not noAppend then f.entities[#f.entities + 1] = e end
  return e
end
-- a projectile: gProjectileDefinitions[id] (form = type); EnemyCreateProjectile copies the parent's position
function H.projectile(E, owner, id, form, parent)
  local f = E.field
  local d = f.assets.manifest.projectileDefs and f.assets.manifest.projectileDefs[id]
  if d and d.multi then d = d.forms[form or 0] or d.forms[0] end
  d = d or {}
  local e = {
    kind = 4, id = PID + id, projId = id, form = form, type = form or 0, type2 = 0, x = 0, y = 0, z = 0, zv = 0, cz = 0, czv = 0,
    speed = d.speed or 0, hitType = d.damageType or 0, hitbox = d.hitbox or { x = 0, y = 0, w = 4, h = 4 },
    sprite = d.sprite, gfx = Assets.gfxSource("enemy", d.gfx or 0), anim = Anim.new(),
    animationState = 0, action = 0, subAction = 0, timer = 0, subtimer = 0, iframes = 0, kbt = 0,
    enemy = true, vproj = true, literalAnim = true, field82 = 0, interactType = 0, direction = 0, spritePriority = 4,
    def = setmetatable({}, { __index = d }), collideOn = true, collide = true, parent = parent, r26 = owner, fmask = 0,
    homeX = 0, homeY = 0, rangeW = 0, rangeH = 0, layer = parent and parent.layer or 1,
  }
  e.palette = E.A:objPalette(d.palette or 0, f.room.atlas and f.room.atlas.palettes)
  if (d.gfx or 0) == 0 and parent then e.gfx, e.palette = parent.gfx, parent.palette end
  H.setHp(e, 0xFF)
  e.onCollision = onCollision
  if parent then H.posRel(parent, e) end
  f.entities[#f.entities + 1] = e
  return e
end
-- the home rectangle as Enemies:spawn makes it (sub_0804A720)
function H.home(E, e, dat)
  local m = E.m
  local r = m.enemyRanges and m.enemyRanges[dat.id] or { 64, 64 }
  local rx = band(rshift(dat.paramB or 0, 16), 0xFF); if rx == 0 then rx = r[1] end
  local ry = band(rshift(dat.paramB or 0, 24), 0xFF); if ry == 0 then ry = r[2] end
  local pc = dat.paramC or 0
  e.homeX = band(pc, 0xFFFF) ~= 0 and band(pc, 0xFFFF) or math.max(0, e.x - 4 * rx)
  e.homeY = rshift(pc, 16) ~= 0 and rshift(pc, 16) or math.max(0, e.y - 4 * ry)
  e.rangeW, e.rangeH = 8 * rx, 8 * ry
end
function H.inHome(e) -- sub_08049FA0 (unsigned compares)
  local dx, dy = math.floor(e.x) - e.homeX, math.floor(e.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH
end
function H.homeDir(e) return H.dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) end -- sub_08049EE4
-- ProcessMovement0 / 1 (tile collision)
function H.move0(E, e)
  if band(e.direction or 0xFF, 0x80) ~= 0 then return false end
  local hx, hy = require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.direction, e.speed or 0)
  return not (hx or hy)
end
-- Link held by a projectile (ResetActiveItems; mobility |= $80)
function H.hold(f, e, onPress)
  local p = f.player
  if p.state ~= "ext" or p.extUpdate ~= e.holdFn then
    e.holdFn = e.holdFn or function(pp, input)
      if not input or not input.pressed then return end
      for _, b in ipairs({ "a", "b", "r", "l", "up", "down", "left", "right" }) do
        if input.pressed(b) then if onPress then onPress() end; break end
      end
    end
    p.state, p.extUpdate = "ext", e.holdFn
    p.vaatiHold = e
  end
end
function H.release(f, e)
  local p = f.player
  if p.vaatiHold == e then
    p.vaatiHold = nil
    if p.state == "ext" then p.state, p.extUpdate, p.animId = "normal", nil, -1 end
  end
end

-- ===========================================================================
-- VAATI_REBORN_ENEMY
-- ===========================================================================
local function anim(E, e, i) H.setAnim(E, e, i) end
local function R(E) return H.R(E.field) end
local function parentOf(e) return e.parent end

local function rebornWobble(e)
  if e.u80 == 0 then
    e.animationState = band(e.animationState + 1, 3)
    e.spriteOX = WOBBLE[e.animationState]
  end
end
function M.rebornPre(E, e) -- VaatiRebornEnemyType0PreAction
  if e.action ~= 0 then e.u78, e.u7c = e.x, e.y end
  if e.u76 == 0 then
    if e.direction == 0xFF or H.inHome(e) then rebornWobble(e) return end
    e.direction = bor(band(H.homeDir(e), 0x10), 8)
    e.u76 = 0x10
  else
    e.u76 = e.u76 - 1
  end
  rebornWobble(e)
end

function M.pickMove(E, e) -- sub_0803DD78
  local rn = rshift(band(R(E), 0x7C), 2)
  local p86, s = e.u86, e.u83
  if p86 == 0 then
    if e.u80 == 0 then e.u75, e.u77 = 0, 0x50
    elseif s == 0 or s == 2 or s == 4 then e.u75, e.u77 = 0, 0x50
    elseif s == 1 or s == 3 or s == 5 then e.u75, e.u77 = 0, 1 end
  elseif p86 == 1 then
    if s == 1 or s == 3 or s == 5 then e.u75, e.u77 = 0, 1
    elseif s == 2 then
      if band(rn, 8) ~= 0 then e.u75, e.u77 = 0, 1 else e.u75, e.u77 = 0, 0x50 end
    elseif s == 4 and band(rn, 8) ~= 0 then e.u75, e.u77 = 0, 0x50
    elseif s == 4 or s == 0 then e.u75, e.u77 = 1, 1 end
  elseif p86 == 2 then
    if s == 2 then
      if band(rn, 0xF) < 3 then e.u75, e.u77 = 0, 1 else e.u75, e.u77 = 1, 1 end
    elseif s == 0 then e.u75, e.u77 = 1, 1
    elseif s == 4 and rn > 9 then e.u75, e.u77 = 2, band(R(E), 1) + 2
    elseif s == 4 or s == 1 or s == 3 or s == 5 then e.u75, e.u77 = 0, 1 end
  end
  e.u83 = (e.u83 + 1) % 6
end

function M.pickAttack(E, e) -- sub_0803DEE0
  local ret = 2
  local rv = rshift(band(R(E), 0xF8), 3)
  if e.u80 ~= 0 then
    if e.u86 == 0 then
      ret = band(e.u82, 1)
      e.u82 = band(e.u82 + 1, 3)
    elseif e.u86 == 1 then
      local s = e.u82
      if s == 0 or s == 2 then ret = 3
      elseif s == 1 or s == 3 then ret = 1
      elseif s == 4 then ret = band(rv, 8) ~= 0 and 3 or 0 end
      e.u82 = (e.u82 + 1) % 5
    elseif e.u86 == 2 then
      local s = e.u82
      if s == 0 or s == 3 then ret = 3
      elseif s == 1 then ret = rv > 5 and 3 or 0
      elseif s == 2 then ret = rv < 10 and 3 or 0
      elseif s == 4 then ret = 0
      else ret = 2 end
      e.u82 = (e.u82 + 1) % 5
    end
  end
  return ret
end

local function teleportOntoLink(E, e) -- sub_0803E028 (its x / y mix kept)
  if e.u75 ~= 2 and band(R(E), 1) ~= 0 then return 0 end
  if e.u77 ~= 1 then return 0 end
  local p = E.field.player
  local px = math.floor(p.x)
  if 0x58 > px then return 0 end
  if 0x58 > px then return 0 end
  if 0xF8 >= px then e.u81 = e.u81 + 5 return 1 end
  return 0
end

local function driftDir(E, e)
  if e.u86 ~= 0 or e.u80 ~= 0 then return bor(rshift(band(R(E), 0x80), 3), 8) end
  return 0xFF
end

local reborn0 = {}
reborn0[0] = function(E, e)
  local f = E.field
  if f:flag("local", 0x7B) then H.delete(e) return end
  if f:flag("room", 0) then
    f:setFlag("room", 0, false)
    e.action, e.u74, e.timer, e.u76 = 3, 0xFF, 0, 0
    H.draw(e, true)
    e.direction, e.spritePriority, e.cz = 0xFF, 4, 0
    e.u80, e.u86, e.u85, e.u84, e.u87, e.u82, e.u83 = 2, 0, 0x30, 0xFF, 0, 0, 0
    e.u78, e.u7c = e.x, e.y
    local eye = H.enemy(E, M, M.REBORN, 1, e.x, e.y, e)
    e.child = eye
    e.kids = { eye }
    for i = 0, 5 do
      local b = H.enemy(E, M, M.BALL, 0, e.x, e.y, e)
      b.u79 = i
      e.kids[#e.kids + 1] = b
    end
    for i = 0, 3 do
      local t = H.enemy(E, M, M.REBORN, 3, e.x, e.y, e)
      t.timer = i
      e.kids[#e.kids + 1] = t
    end
    for i = 0, 1 do
      local b = H.enemy(E, M, M.BALL, 1, e.x, e.y, e)
      b.flipX = i == 1
      H.posRel(e, b, SIDE_BALLS[i][1], SIDE_BALLS[i][2])
      e.kids[#e.kids + 1] = b
    end
    anim(E, e, 0)
  end
end
reborn0[1] = function(E, e)
  if e.timer ~= 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      if band(e.u74, 0x70) == 0 then
        if (e.child.timer or 0) == 0 then
          M.pickMove(E, e)
          if e.u75 ~= 0 then
            e.action, e.u74, e.timer, e.direction = 2, 0, 16, 0xFF
          else
            e.direction = driftDir(E, e)
          end
        else
          e.timer = 2
        end
      else
        e.action = 3
        e.u75 = band(e.u74, 0x80)
        e.u74, e.timer, e.direction = 0, 192, 0xFF
        H.draw(e, true)
        anim(E, e, 0)
      end
    end
  else
    e.u77 = band(e.u77 - 1, 0xFF)
    if e.u77 == 0 then
      local k = M.pickAttack(E, e)
      if k == 0 then
        e.action, e.timer, e.direction, e.u84 = 4, 160, 0xFF, 0xFF
        anim(E, e, 1)
      elseif k == 1 then
        e.action, e.u74, e.timer, e.direction = 6, 0, 0, 0xFF
      elseif k == 3 then
        e.action, e.u74, e.subtimer, e.direction = 5, 0, 32, 0xFF
      else
        e.u74, e.timer = 0, 32
        e.direction = driftDir(E, e)
      end
    end
    if (e.child.timer or 0) == 0 then
      e.u85 = band(e.u85 + 1, 0xFF)
      if band(e.u85, 3) == 0 then
        local q = band(e.u85, 0x30)
        if q == 0 or q == 0x30 then e.y = e.y + 1 else e.y = e.y - 1 end
      end
      H.move0(E, e) -- ProcessMovement1
    end
  end
  H.step(e)
end
reborn0[2] = function(E, e)
  local f = E.field
  if e.u74 == 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u74, e.timer = 1, 32
      anim(E, e, 3)
      f:sound(SFX.S19B)
    end
  elseif e.u74 == 1 then
    if H.done(e) then e.u74, e.timer = 2, 16; H.draw(e, false) end
  elseif e.u74 == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u74 = 3
      if teleportOntoLink(E, e) == 0 then
        e.u81 = (e.u81 + 1 + band(R(E), 3)) % 5
        local s = SPOTS[e.u81]
        e.x, e.y = s[1] + 0x10, s[2] + 0x10
      end
      H.draw(e, true)
      e.timer = 32
      anim(E, e, 4)
      f:sound(SFX.F5)
    end
  elseif e.u74 == 3 then
    if H.done(e) then
      H.draw(e, true)
      if e.u81 > 4 then
        local p = f.player
        e.x, e.y = math.floor(p.x), math.floor(p.y) - 0x18
      end
      e.u77 = band(e.u77 - 1, 0xFF)
      if e.u77 == 0 then e.action, e.timer = 1, 1
      else e.u74, e.timer = 0, 16 end
      anim(E, e, 0)
    end
  end
  H.step(e)
end
reborn0[3] = function(E, e)
  local f = E.field
  local s = e.u74
  if s == 0xFE then e.u74, e.timer = 0, 1
  elseif s == 0xFF then
    if math.floor(e.cz) ~= -4 then e.cz = e.cz - 0.125 end
    if e.timer == 2 then e.u74 = 0xFE end
  elseif s == 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u74 = 1
      e.timer = band(e.u75, 0x80) ~= 0 and 0x14 or 0x20
      e.u80 = rshift(e.u86 + 1, 1) * 2 + 2
    end
  elseif s == 1 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u74 = 2
      if band(e.u75, 0x80) == 0 then f:sound(SFX.S1B0) end
      anim(E, e, 1)
    end
  elseif s == 2 then
    if H.done(e) then e.u74 = 3; anim(E, e, 0) end
  elseif s == 3 then
    e.action, e.u74, e.timer = 1, 0, 1
  end
  H.step(e)
end
reborn0[4] = function(E, e)
  local f = E.field
  e.timer = e.timer - 1
  if e.timer == 0 then
    e.action, e.u84, e.timer = 1, 0xFF, 1
    e.direction = band(e.direction + 0x10, 0x1F) -- (DIR_NONE + $10) & $1F
    anim(E, e, 0)
  elseif band(H.flags(e), 0x10) ~= 0 then
    H.clearFlag(e, 0x10)
    if e.u84 == 0xFF then
      local p = f.player
      local idx = band(H.dirTo(e.x, e.y, p.x, p.y) + 2, 0x1C) -- Direction8RoundUp
      e.u84 = FIRE_TYPE[rshift(idx, 2)]
      e.subtimer = 0
    end
    if e.subtimer < 0x10 then
      local pr = M.fire(E, e, e.u84, e.subtimer)
      if pr then e.subtimer = e.subtimer + 1 end
    end
  end
  H.step(e)
end
reborn0[5] = function(E, e)
  local f = E.field
  if e.u80 == 0 then
    e.action, e.timer, e.direction = 1, 1, 0xFF
    anim(E, e, 0)
    return
  end
  local s = e.u74
  if s == 0 then
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then e.u74 = 1; anim(E, e, 1) end
  elseif s == 1 then
    if band(H.flags(e), 0x10) ~= 0 then
      e.u74 = 2
      e.subtimer = band(R(E), 0x3F) + 64
      f:sound(SFX.SUMMON)
    end
  elseif s == 2 then
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then
      if not (e.u86 < 2 or 3 < e.u87) and band(R(E), 0x10) ~= 0 then
        e.u87 = e.u87 + 1
        e.subtimer = band(R(E), 0x3F) + 64
        local p = f.player
        e.direction = bor(band(H.dirTo(e.x, e.y, p.x, p.y), 0x10), 8)
      else
        e.u74, e.u87, e.subtimer = 3, 0, 48
        anim(E, e, 0)
      end
    end
  elseif s == 3 then
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then e.action, e.u74, e.timer, e.direction = 1, 0, 1, 0xFF end
  end
  if e.u87 ~= 0 then H.move0(E, e) end
  H.step(e)
end
reborn0[6] = function(E, e)
  local f = E.field
  if e.u80 == 0 then e.action, e.timer = 1, 1 return end
  local s = e.u74
  if s == 0 then
    if e.timer ~= 0 then e.u74, e.timer = 1, 112 end
  elseif s == 1 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.u74 = 2
      f:sound(SFX.S150)
      local t = M.darkMagic(E, e, 0, 0)
      if t then H.posRel(e, t, 0, -16) end
    elseif e.timer == 0x40 then
      f:sound(SFX.S196)
    end
  elseif s == 2 then
    if e.subtimer ~= 0 then e.subtimer = 0 end
  elseif s == 3 then
    if e.subtimer == 0 then e.subtimer = 1; f:sound(SFX.S14F) end
    if e.timer ~= 0 then e.action, e.u74, e.timer = 1, 0, 1 end
  end
  H.step(e)
end
reborn0[7] = function(E, e)
  local f = E.field
  if e.timer ~= 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      f:setFlag("room", 1, true)
      e.defeated = true
    elseif band(e.timer, 7) == 0 then
      local t = band(R(E), 0x3F3F)
      H.fx(f, e.x + band(t, 0xFF) - 0x20, e.y + band(rshift(t, 8), 0xFF) - 0x20, FX_DEATH)
    end
  end
end

-- type 1 (the eye)
local function eyePre(E, e) -- VaatiRebornEnemyType1PreAction
  local f = E.field
  if e.hitType ~= 0x30 then return end
  local pa = e.parent
  e.u77 = 0
  if e.cflags and band(e.cflags, 0x80) ~= 0 then
    if PHASE_HP[pa.u86] > H.hp(e) then
      pa.u86 = pa.u86 + 1
      if pa.u86 > 2 then
        H.colOff(e)
        pa.action = 7
        H.colOff(pa)
        pa.timer, pa.spriteOX, pa.direction = 128, 0, 0xFF
        e.timer = 0
        f:bgm(nil) -- SONG_STOP_BGM
        return
      end
      e.timer = 1
      e.u77 = 0xFF
    end
    if e.iframes > 0 then
      f:sound(SFX.BOSS_HIT)
      f:shake(12, 1)
      if e.timer == 0 then e.timer = 72 end
    end
  end
  if e.timer ~= 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.hitType = 0x2F
      e.u74 = 1
      if e.u77 == 0 then pa.u74 = 0xF0
      else pa.u74 = 0x70; H.setHp(e, 0xFF) end
      pa.action, pa.timer = 1, 1
      anim(E, e, 0)
    end
  end
end
local reborn1 = {}
reborn1[0] = function(E, e)
  e.action, e.u74, e.u75, e.timer = 1, 0, 1, 0
  e.spriteOY = -1
  H.posRel(e.parent, e, 0, 1)
  local c = H.enemy(E, M, M.REBORN, 2, e.x, e.y, e)
  c.child = e.parent
  e.child = c
  anim(E, e, e.u74)
end
reborn1[1] = function(E, e)
  local pa = e.parent
  if e.u74 == 0 then
    if pa.u80 == 0 then e.u74 = 1; e.hitType = 0x30; anim(E, e, 1) end
  else
    if pa.u80 ~= 0 then e.u74 = 0; e.hitType = 0x2F; anim(E, e, 0)
    else
      if e.cflags and band(e.cflags, 0x80) ~= 0 and e.iframes > 0 then
        pa.iframes = e.iframes
        pa.cflags = e.cflags
      end
      if band(H.flags(e), 0x40) ~= 0 then anim(E, e, 2) end
    end
  end
  if e.u75 == 0 then
    if pa.action ~= 2 then e.u75 = 1; H.colOn(e) end
  else
    if pa.action == 2 then e.u75 = 0; H.colOff(e) end
  end
  H.draw(e, H.drawn(pa))
  e.spriteOX = pa.spriteOX
  H.posRel(pa, e, 0, 1)
  H.step(e)
end
local reborn2 = {}
reborn2[0] = function(E, e)
  local src = e.parent.parent
  e.action, e.u74, e.u75, e.direction = 1, 1, 0, 0xFF
  e.spriteOY = -2
  H.posRel(src, e, 0, 2)
  anim(E, e, 2)
end
reborn2[1] = function(E, e)
  local pa = e.parent
  if pa.u74 == 0 then
    if e.u74 ~= 0 then e.u74 = 0 end
    local pd = pa.parent.direction
    if pd ~= 0xFF then
      if e.u75 == 0 then e.u75 = 1 end
      if pd ~= e.direction then e.direction = pd; anim(E, e, rshift(pd, 3)) end
    else
      if e.u75 ~= 0 then e.u75 = 0; anim(E, e, 0) end
    end
  else
    if e.u74 == 0 then e.u74 = 1; anim(E, e, 2) end
  end
  H.draw(e, H.drawn(pa))
  e.spriteOX = pa.spriteOX
  H.posRel(pa.parent, e, 0, 2)
  H.step(e)
end
local function follow3(E, e) -- sub_0803DC0C
  local pa = e.parent
  local t = PARTS3[e.timer]
  H.draw(e, H.drawn(pa))
  e.spriteOX = pa.spriteOX
  H.posRel(pa, e, t[1], t[2] + 1)
  H.step(e)
end
local reborn3 = {}
reborn3[0] = function(E, e)
  e.action, e.u74, e.direction = 1, 0, 0xFF
  e.spriteOY = -1
  anim(E, e, e.u74)
  follow3(E, e)
end
reborn3[1] = function(E, e)
  local pa = e.parent
  if pa.direction ~= 0xFF then
    if e.u74 == 0 then e.u74 = 1 end
    if pa.direction ~= e.direction then e.direction = pa.direction; anim(E, e, rshift(e.direction, 3)) end
  else
    if e.u74 ~= 0 then e.u74, e.direction = 0, 0xFF; anim(E, e, 2) end
  end
  follow3(E, e)
end

function M.reborn(E, e)
  local t = e.type
  if t == 0 then
    M.rebornPre(E, e)
    reborn0[e.action](E, e)
  elseif t == 1 then
    eyePre(E, e)
    reborn1[e.action](E, e)
  elseif t == 2 then reborn2[e.action](E, e)
  elseif t == 3 then reborn3[e.action](E, e) end
end

-- ===========================================================================
-- VAATI_BALL
-- ===========================================================================
local ballActs = {}
local function ballReset(E, e, state) -- sub_08044E74
  e.action, e.u74 = 1, 0
  if state == 2 then
    e.action = 2
    e.direction = band(e.direction + 0x18, 0x1F)
    H.posRel(e.parent, e, 0, -16)
    e.speed = 12288
    H.linMove(e)
    e.direction = band(e.direction + 8, 0x1F)
    e.speed = 1280
    H.linMove(e)
  elseif state == 1 then
    e.direction = band(e.direction + 8, 0x1F)
  else
    if e.u78 ~= 0 then
      if e.timer == 3 or e.timer == 4 then
        repeat H.linMove(e); local t = e.timer; e.timer = e.timer - 1 until t == 3
      elseif e.timer == 1 then
        e.direction = band(e.direction + 0x10, 0x1F); H.linMove(e); e.direction = band(e.direction + 0x10, 0x1F)
      end
    elseif e.timer == 2 then
      H.linMove(e)
    end
  end
  e.timer, e.u78, e.speed = 1, 0, 0x500
end
local function ballSpread(E, e) -- sub_08044DEC
  local pa = e.parent
  if pa.u80 > e.u79 then H.draw(e, true); H.setHp(e, 0xFF) else H.draw(e, false) end
  H.colOff(e)
  e.u78, e.speed = 0, 0x300
  local off = band(pa.u80 - 1, 0xFF)
  local row = BALL_DIRS[off] or BALL_DIRS[0]
  e.direction = row[e.u79] or 0
  H.posRel(pa, e, 0, -16)
end
ballActs[0] = function(E, e) -- sub_0804468C
  e.layer = 3
  e.spritePriority = 5
  e.u84 = 0
  if e.type == 0 then
    e.action, e.timer = 1, 1
    e.direction = band(e.u79 * 8, 0x1F)
    e.u78, e.u83 = 0, 0
    H.draw(e, false)
    local o = BALL_START[band(e.u79, 3)]
    H.posRel(e.parent, e, o[1], o[2] - 0x10)
    e.cz = e.parent.cz
    anim(E, e, 0)
  else
    e.action, e.u74, e.u83 = 3, 0, 1
    H.draw(e, true)
    anim(E, e, 1)
  end
end
local function ballCircle(E, e) -- sub_0804474C (actions 1 and 4)
  local pa = e.parent
  local a = pa.action
  if a == 3 then e.action, e.u74, e.timer = 3, 0, 0
  elseif a == 5 then e.action, e.u74, e.subtimer = 5, 0, 1
  elseif a == 6 then e.action, e.u74, e.subtimer = 6, 0, 32
  elseif a == 2 then e.action, e.u74, e.hitType = 2, 0, 0 end
  if e.action ~= 1 then H.step(e)
  else
    e.timer = e.timer - 1
    if e.timer == 0 then e.timer = 2; e.direction = band(e.direction + 1, 0x1F) end
    H.linMove(e)
    H.step(e)
  end
end
ballActs[1] = ballCircle
ballActs[4] = ballCircle
ballActs[2] = function(E, e) -- sub_080447E0
  local pa = e.parent
  if pa.action == 1 then
    e.action, e.hitType = 1, 43
    ballReset(E, e, 0)
    if e.collide then H.draw(e, true) end
  else
    e.u77 = band((e.u77 or 0) + 1, 7)
    if e.collide then H.draw(e, band(e.u77, 1) ~= 0) end
    if pa.u74 == 2 then ballReset(E, e, 2) end
  end
end
ballActs[3] = function(E, e) -- sub_08044868
  local pa = e.parent
  local s = pa.u74
  if s == 0xFE then
    if e.u83 ~= 0 and e.u74 == 2 then H.delete(e) return end
  elseif s == 0xFF then
    if e.u83 ~= 0 then
      if e.u74 == 0 then
        if H.done(e) then
          e.u74 = 1
          e.direction = H.dirTo(e.x, e.y, pa.x, pa.y - 0x10)
          e.speed = 0x180
        end
      elseif e.u74 == 1 then
        H.linMove(e)
        if H.within(e, pa.x, pa.y - 0x10, 0xC) then
          e.u74 = 2
          e.x, e.y = math.floor(pa.x), math.floor(pa.y) - 0x10
          pa.timer = pa.timer + 1
        else
          e.direction = H.dirTo(e.x, e.y, pa.x, pa.y - 0x10)
        end
      end
    end
  elseif s == 1 then
    if e.u83 == 0 then e.u83 = 1; H.draw(e, true) end
    ballSpread(E, e)
    if pa.u86 > 1 and H.drawn(e) and e.u84 == 0 then
      local m = M.darkMagic(E, e, 0, 1)
      if m then e.u84 = 1; e.hitType = 0 end
    end
    e.timer = 32
  elseif s == 2 then
    if e.timer ~= 0 then
      e.timer = e.timer - 1
      if e.timer < 0x11 then H.linMove(e) end
    end
  elseif s == 3 then
    ballReset(E, e, 1)
    if H.drawn(e) then H.colOn(e) else H.colOff(e) end
  end
  H.step(e)
end
ballActs[5] = function(E, e) -- sub_080449F8 (the eye-laser dance)
  local pa = e.parent
  H.step(e)
  if pa.action == 1 then ballReset(E, e, 0) return end
  local s = pa.u74
  if s == 0 then
    H.linMove(e)
    e.timer = e.timer - 1
    if e.timer ~= 0 then return end
    if e.u78 == 0 then e.u78 = 1; e.speed = 640 end
    e.timer = 4
    e.direction = band(e.direction + 1, 0x1F)
    if pa.u80 == 0 then pa.u74 = 1 end
  elseif s == 1 then
    local t = e.timer
    if t == 2 then
      if pa.u80 == 0 then e.subtimer = 0; ballReset(E, e, 0) end
    elseif t == 1 then
      e.direction = band(e.direction + 0x10, 0x1F); H.linMove(e); e.direction = band(e.direction + 0x10, 0x1F)
      e.timer = 2
    elseif t == 3 then H.linMove(e); e.timer = 2
    elseif t == 4 then H.linMove(e); H.linMove(e); e.timer = 2 end
  elseif s == 2 then
    if e.u74 == 0 then
      e.u74 = 1
      if H.drawn(e) then
        local l = M.laser(E, e)
        if l then l.y = l.y + 4; e.child = l end
      end
    end
  elseif s == 3 then
    if e.subtimer ~= 0 then e.subtimer = 0 end
  end
end
ballActs[6] = function(E, e) -- sub_08044B04 (the dark-magic dance)
  local f = E.field
  local pa = e.parent
  H.step(e)
  if pa.action == 1 then ballReset(E, e, 0); e.timer = 32 return end
  local s = pa.u74
  if s == 0 then
    H.linMove(e)
    if e.u74 == 0 then
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.timer = e.u78 ~= 0 and 4 or 2
        e.direction = band(e.direction + 1, 0x1F)
      end
      e.subtimer = band(e.subtimer - 1, 0xFF)
      if e.subtimer == 0 then
        if e.timer ~= 2 then e.subtimer = 1
        else
          e.u78 = e.u78 + 1
          if e.u78 > 2 then
            e.u74, e.u78, e.timer, e.subtimer = 1, 1, 4, 0
          else
            e.subtimer = 32
          end
          e.speed = e.u78 ~= 0 and 640 or 1280
        end
      end
    elseif e.u74 == 1 then
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.timer = 6
        e.direction = band(e.direction + 1, 0x1F)
        e.subtimer = band(e.subtimer + 1, 0xFF)
        if e.subtimer == 0x30 then
          local d = H.dirTo(e.x, e.y, pa.x, pa.y - 0x10)
          e.speed = 0
          e.direction = band(d + 16, 0x1F)
          e.timer, e.subtimer = 16, 16
          e.u74 = e.u74 + 1
        end
      end
    elseif e.u74 == 2 then
      if e.subtimer == 0 then
        e.timer = e.timer - 1
        if e.timer == 12 then e.speed = 1280
        elseif e.timer == 0 then
          e.u74 = e.u74 + 1
          e.direction = H.dirTo(e.x, e.y, pa.x, pa.y - 0x10)
          e.speed, e.timer, e.subtimer = 0, 4, 16
        elseif e.timer == 4 then e.speed = 640 end
      else
        e.subtimer = e.subtimer - 1
        if e.subtimer == 0 then e.speed = 640 end
      end
    elseif e.u74 == 3 then
      if e.subtimer ~= 0 then
        e.subtimer = e.subtimer - 1
        if e.subtimer == 0 then e.speed = 640 end
      else
        if e.timer ~= 0 then
          e.timer = e.timer - 1
          if e.timer == 0 then e.speed = 1280; f:sound(SFX.S14F) end
        end
        if e.u79 == 3 and H.within(e, pa.x, pa.y - 0x10, 0xC) then pa.timer = pa.timer + 1 end
        e.direction = H.dirTo(e.x, e.y, pa.x, pa.y - 0x10)
        return
      end
    end
  elseif s == 1 then
    if e.u74 == 3 then
      e.u74, e.timer = 1, 80
      H.colOff(e)
      H.posRel(pa, e, 0, -16)
      if e.subtimer ~= 0 then H.draw(e, false) end
    elseif e.u74 == 1 then
      e.timer = e.timer - 1
      if e.timer == 0 then e.u74, e.timer, e.subtimer = 0, 32, 4 end
    end
  elseif s == 3 then
    if e.u74 == 0 then
      if e.subtimer ~= 0 then
        e.subtimer = e.subtimer - 1
        if e.subtimer == 0 then ballSpread(E, e); e.u74, e.timer = 1, 16 end
      end
    elseif e.u74 == 1 then
      H.linMove(e)
      e.timer = e.timer - 1
      if e.timer == 0 then e.u74 = e.u74 + 1 end
    elseif e.u74 == 2 then
      ballReset(E, e, 1)
      if H.drawn(e) then H.colOn(e) else H.colOff(e) end
      pa.timer = pa.timer + 1
    end
  end
end

function M.ball(E, e) -- VaatiBall
  local f = E.field
  local pa = e.parent
  if not H.alive(pa) then H.delete(e) return end
  if e.action ~= 0 and e.action ~= 3 then
    e.x = e.x + (pa.x - (pa.u78 or pa.x))
    e.y = e.y + (pa.y - (pa.u7c or pa.y))
  end
  ballActs[e.action](E, e)
  if e.deleted then return end
  if e.u84 ~= 0 then H.setHp(e, 0xFF) end
  if e.cflags and band(e.cflags, 0x80) ~= 0 then
    if band(e.cflags, 0x3F) == 0 and e.action == 6 then H.modHealth(f, -2) end
    if H.hp(e) < 0xFD then
      H.draw(e, false)
      H.colOff(e)
      H.setHp(e, 0xFF)
      pa.u80 = band(pa.u80 - 1, 0xFF)
      H.fx(f, e.x, e.y, FX_DEATH) -- CreateDeathFx
      f:sound(SFX.S1C3)
    end
  end
end

-- ===========================================================================
-- V1_DARK_MAGIC_PROJECTILE
-- ===========================================================================
-- V1DarkMagicProjectile_OnGrabbed through GustJar.grabbedUpdate's hooks:
-- subAction 0 -> 2 at once (no wiggle); sub_0806F520 false (the gust lost)
-- -> health 0; sub_0806F3E4 (pulled into the mouth, 4x4) -> health 0
local function darkGrabbed(E, e) e.jarSub, e.jarKb = 2, 0 end
local function darkJarLost(E, e) H.setHp(e, 0) end
local function darkJarPull(E, e)
  local GJ = require("src.zelda.tmc.GustJar")
  local mx, my = GJ.mouth(E.field.player)
  if math.abs(e.x - mx) < 4 and math.abs(e.y - my) < 4 then H.setHp(e, 0) return true end
  return false
end
M.darkGrab = { grabbed = darkGrabbed, lost = darkJarLost, pull = darkJarPull }
function M.darkMagic(E, parent, type, type2)
  local e = H.projectile(E, M, M.P_DARK, type, parent)
  e.type, e.type2 = type, type2
  e.onGrabbed, e.onJarLost, e.onJarPull = darkGrabbed, darkJarLost, darkJarPull
  return e
end
local function darkFrame(E, e) -- sub_080AB034: the palette by the frame's settings bit
  H.step(e)
  local pal = band(e.anim.flip or 0, 1) ~= 0 and 0 or 0x139
  if e.palNow ~= pal then e.palNow = pal; H.palette(E, e, pal) end
end
local function darkDeath(E, e) -- V1DarkMagicProjectile_OnDeath
  local f = E.field
  if e.type ~= 0 and e.type2 ~= 0 then H.delete(e) return end
  if H.drawn(e) then H.draw(e, false); e.u86 = 1; H.fx(f, e.x, e.y, FX_DEATH) end
  local pa = e.parent
  if pa then
    if e.type2 == 0 then
      pa.u74 = 3
      pa.u80 = band((pa.u80 or 0) + rshift(e.u81 or 0, 1), 0xFF)
      if pa.u80 > 8 then pa.u80 = 8 elseif pa.u80 == 0 then pa.u80 = 1 end
    else
      pa.u84 = 0
      pa.hitType = 0x2B
    end
  end
  if e.u86 == 0 then H.fx(f, e.x, e.y, FX_DEATH) end
  H.release(f, e)
  H.delete(e)
end
local function darkHeld(E, e) -- sub_080AAF74
  local f = E.field
  local p = f.player
  if e.pressed then e.u80 = e.u80 + band(R(E), 1) + 1; e.pressed = nil end
  e.timer = e.timer + 1
  if e.timer == 0x3C then
    e.timer = 30
    p.invuln = 8
    H.modHealth(f, -4)
    f:sound(SFX.VO6)
    if (f.save.stats.health or 0) <= 0 then H.setHp(e, 0) end
  end
  if not (e.u80 < 0x31 and e.u81 ~= 0x10) then
    e.action, e.u80 = 1, 0
    p.invuln = 0xF0
    H.release(f, e)
    H.setHp(e, 0)
  else
    H.hold(f, e, function() e.pressed = true end)
    H.posRel(p, e)
    e.cz = -(p.z or 0) - 4
  end
end
local function darkCol(E, e, fl) -- V1DarkMagicProjectile_OnCollision
  local f = E.field
  if band(fl, 0x80) == 0 then return end
  if e.type2 == 0 then
    if band(fl, 0x3F) == 0 and e.action ~= 2 then
      e.action = 2
      H.colOff(e)
      e.spritePriority = 3 -- SortEntityAbove(Link)
      H.hold(f, e, function() e.pressed = true end)
    end
    if (f.save.stats.health or 0) <= 0 then H.setHp(e, 0) end
  else
    f:sound(SFX.GLOVES)
    if e.parent then H.posRel(e.parent, e) end
  end
end
function M.dark(E, e)
  local f = E.field
  if e.action ~= 0 and H.hp(e) == 0 and e.type == 0 then darkDeath(E, e) return end
  if e.action ~= 0 and e.type ~= 0 and e.type2 ~= 0 and H.hp(e) == 0 then H.delete(e) return end
  if e.action == 0 then -- V1DarkMagicProjectile_Init
    if e.type2 == 0 then e.action = 1
    else e.action = 3; e.hitType = 0x2C; e.spritePriority = math.max(0, (e.parent.spritePriority or 4) - 1) end
    if e.type == 0 then
      e.timer, e.subtimer, e.u80, e.u81 = 0, 4, 0, 0
      H.setHp(e, 0x10)
      e.cz = e.cz + 4
      e.flipY = true
      e.spritePriority = 4
      local p = f.player
      e.direction = H.dirTo(e.x, e.y, p.x, p.y)
      e.u86, e.u84 = 0, 300
      local o = M.darkMagic(E, e, 1, e.type2)
      o.parent = e
      e.child = o
    else
      H.colOff(e)
      H.posRel(e.parent, e)
    end
    e.onCol = darkCol
    H.setAnim(E, e, e.type)
  elseif e.action == 1 then
    if e.type == 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then
        e.subtimer = 4
        local p = f.player
        H.turnTo(e, H.dirTo(e.x, e.y, p.x, p.y))
      end
      H.linMove(e)
    else
      if not H.alive(e.parent) or not H.drawn(e.parent) then H.delete(e) return end
      H.posRel(e.parent, e)
    end
    darkFrame(E, e)
  elseif e.action == 2 then
    darkHeld(E, e)
    darkFrame(E, e)
  elseif e.action == 3 then
    if not H.alive(e.parent) then H.delete(e) return end
    H.posRel(e.parent, e)
    darkFrame(E, e)
    H.draw(e, H.drawn(e.parent))
    if e.type ~= 0 then e.health = e.parent.health end
    if e.parent.action == 2 then if e.collide then H.colOff(e) end
    else if not e.collide then H.colOn(e) end end
  end
  if e.type2 == 0 and e.type == 0 and not e.deleted then
    e.u84 = e.u84 - 1
    if e.u84 == 0 then H.setHp(e, 0) end
  end
end

-- ===========================================================================
-- V1_FIRE_PROJECTILE
-- ===========================================================================
function M.fire(E, parent, type, sub)
  local e = H.projectile(E, M, M.P_FIRE, type, parent)
  e.type, e.subtimer = type, sub or 0
  e.cz = parent.cz or 0
  return e
end
function M.fireUpdate(E, e)
  local f = E.field
  if e.action == 0 then -- V1FireProjectile_Init
    e.action = 1
    e.czv = -1
    e.tx, e.ty = math.floor(e.x / 16), math.floor(e.y / 16)
    H.posRel(e.parent, e)
    H.moveDir(e, 0x1000, e.direction)
    e.spritePriority = 1
    e.cz = e.parent.cz or 0
    H.setAnim(E, e, 0x51)
    f:sound(SFX.S1B5)
    local i = bor(lshift(e.type, 5), lshift(e.subtimer, 1))
    local x, y = math.floor(e.x) + (FIRE_TGT[i] or 0), math.floor(e.y) + (FIRE_TGT[i + 1] or 0)
    local dx, dy = x - math.floor(e.x), y - math.floor(e.y)
    local iv = math.floor(math.sqrt((dx * dx + dy * dy) * 256)) -- sub_080041DC
    local rn = band(R(E), 0x1FF)
    if band(f.frame or 0, 1) ~= 0 then iv = math.min(iv + rn, 0x400) else iv = math.max(iv - rn, 0x20) end
    e.czv = e.cz * 32 / iv -- (z / (dist << 8)) << $D
    e.direction = H.dirTo(e.x, e.y, x, y)
    e.onCol = function(E2, me, fl)
      if band(fl, 0x80) ~= 0 then
        me.action = 3
        H.colOff(me)
        H.setAnim(E2, me, 0x53)
        if band(fl, 0x7F) == 0 then H.modHealth(E2.field, -4) end
      end
    end
  elseif e.action == 1 then
    H.step(e)
    H.linMove(e)
    if not H.gravity(e, 0) then
      e.action, e.timer = 2, 15
      H.setAnim(E, e, 0x54)
    else
      e.timer = e.timer + 1
      if e.timer > 0xE0 then H.delete(e) end
    end
  elseif e.action == 2 then
    H.step(e)
    if H.done(e) then e.action = 3; H.colOff(e); H.setAnim(E, e, 0x53) end
  elseif e.action == 3 then
    H.step(e)
    if H.done(e) then H.delete(e) end
  end
end

-- ===========================================================================
-- V1_EYE_LASER
-- ===========================================================================
function M.laser(E, ball)
  local e = H.projectile(E, M, M.P_LASER, 0, ball)
  return e
end
local function laserSeg(E, src, a, dy) -- sub_080AB844
  local e = H.projectile(E, M, M.P_LASER, 1, src.parent)
  e.type, e.timer = 1, a
  H.posRel(src, e, 0, dy)
  e.hitbox = (a ~= 1) and HB_61C or HB_614
  return e
end
function M.laserSegments(E, e) -- sub_080AB758
  local r6, r7, index = 6, 0, 0
  local lim = 0xD4
  local n = 0
  while math.floor(e.y) + r7 + index * 8 <= lim and n < 256 do
    if index == 7 then laserSeg(E, e, 4, r6); r6 = r6 + 0x3E; r7 = r7 + 0x3E end
    index = band(index + 1, 7); n = n + 1
  end
  index = 0
  while math.floor(e.y) + r7 + index * 8 <= lim and n < 512 do
    if index == 3 then laserSeg(E, e, 3, r6); r6 = r6 + 0x1E; r7 = r7 + 0x1E end
    index = band(index + 1, 3); n = n + 1
  end
  if band(index, 2) ~= 0 then laserSeg(E, e, 2, r6); r6 = r6 + 0xE
  elseif band(index, 1) ~= 0 then laserSeg(E, e, 1, r6); r6 = r6 + 6 end
  laserSeg(E, e, 6, r6)
end
function M.laserUpdate(E, e)
  local pa = e.parent
  if not H.alive(pa) or not H.drawn(pa) then H.delete(e) return end
  if e.action == 0 then
    e.u74 = pa.x
    if e.type == 0 then
      e.action = 1
      H.colOff(e)
      e.hitbox = HB_614
      H.setAnim(E, e, 0)
    else
      e.action, e.subtimer = 2, 4
      H.setAnim(E, e, e.timer)
    end
  elseif e.action == 1 then
    H.step(e)
    if H.done(e) then e.action = 2; H.setAnim(E, e, 1); M.laserSegments(E, e) end
  elseif e.action == 2 then
    H.step(e)
    e.x = e.x + (pa.x - e.u74)
    e.u74 = pa.x
    e.subtimer = e.subtimer - 1 -- sub_080AB888
    if e.timer == 3 or e.timer == 4 then e.hitbox = LASER_HB[e.subtimer * 2 + (e.timer == 3 and 1 or 0)] or e.hitbox end
    if e.subtimer == 0 then e.subtimer = 4 end
    if pa.subtimer == 0 then H.delete(e) end
  end
end

-- ===========================================================================
-- VAATI_PROJECTILE ($4B)
-- ===========================================================================
local MAZAAL_EXIT = { area = 0x58, room = 0x16, endX = 0xB8, endY = 0x5C, layer = 1, kind = 1, facing = 4 } -- gUnk_0813AB94
M.MAZAAL_EXIT = MAZAAL_EXIT
local function vpCarry(E, e) -- sub_0803E444
  local f = E.field
  local p = f.player
  H.hold(f, e)
  p.x, p.y = e.x, e.y - 2 -- sub_0806FA90(.., 0, -2)
  p.z = e.z
  p.spriteOY, p.spriteOYFrame = 14, f.frame -- spriteOffsetY += $E
end
local function vpCol(E, e, fl) -- VaatiProjectile_OnCollision
  local f = E.field
  if fl == 0x80 then -- contactFlags == CONTACT_NOW (Link's body, hurtType 0)
    if H.hp(e) ~= 0 then
      e.action = 5
      H.colOff(e)
      vpCarry(E, e)
      if e.parent then H.colOff(e.parent) end
    else
      H.release(f, e)
    end
  end
end
function M.vproj(E, e) -- VaatiProjectile
  local f = E.field
  local pa = e.parent
  -- sub_0803E4A0 (gRoomTransition.field_0x39 set: the fight is on)
  if e.vpParent and (not H.alive(e.vpParent) or H.hp(e.vpParent) == 0) then
    H.colOff(e); H.setHp(e, 0); e.vpParent = nil
    e.parent = nil -- (super->parent = NULL)
    pa = nil
  end
  if e.action ~= 0 and e.type == 0 and H.hp(e) == 0 and e.action ~= 5 and e.action ~= 6 and e.action ~= 7 then -- OnDeath
    if pa and pa.subtimer then pa.subtimer = pa.subtimer - 1 end
    H.release(f, e)
    H.fx(f, e.x, e.y, FX_DEATH)
    H.delete(e)
    return
  end
  local a = e.action
  if a == 0 then
    if e.type == 0 then
      local c = H.enemy(E, M, M.VPROJ, 1, e.x, e.y, e)
      e.child = c
      if e.type2 == 0 then e.action, e.cz = 1, -0x18
      else e.action, e.cz = 9, -0x80 end
      e.onCol = vpCol
      H.setAnim(E, e, 0)
    else
      e.action = 8
      H.colOff(e)
      e.spriteOY = 1
      H.posRel(e.parent, e, 0, -1)
      H.setAnim(E, e, 1)
    end
  elseif a == 1 then
    if (e.u78 or 0) >= 0x4B1 then e.speed = 0x180 else e.u78 = (e.u78 or 0) + 1 end
    local p = f.player
    if math.abs(p.x - e.x) <= 8 and math.abs(p.y - e.y) <= 8 and (p.x - e.x) ^ 2 + (p.y - e.y) ^ 2 <= 64 then -- PlayerInRange(e, 0, 8)
      e.action, e.timer = 2, 10
      if e.child then H.setAnim(E, e.child, 2) end
    else
      local t = H.target(f)
      if t then H.turnTo(e, H.dirTo(e.x, e.y, t.x, t.y)); H.linMove(e) end
    end
    H.step(e)
  elseif a == 2 then
    if e.timer ~= 0 then e.timer = e.timer - 1
    else
      e.cz = math.floor(e.cz) + 1
      if e.cz == 0 then e.action = 3 end
    end
    H.step(e)
  elseif a == 3 then
    if e.child and H.done(e.child) then
      e.cz = math.floor(e.cz) - 1
      if e.cz <= -0x18 then
        e.action = 4
        e.timer = band(R(E), 0xF) + 15
        H.setAnim(E, e.child, 1)
      end
      H.step(e)
    end
  elseif a == 4 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action = 1
      local p = f.player
      e.direction = H.dirTo(e.x, e.y, p.x, p.y)
    end
    H.step(e)
  elseif a == 5 then
    vpCarry(E, e)
    if e.timer ~= 0 then e.timer = e.timer - 1
    else
      e.cz = math.floor(e.cz) - 1
      if -0x18 < e.cz then H.syncZ(e) return end
      e.action, e.timer = 6, 20
    end
  elseif a == 6 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.direction, e.speed = 7, 0x10, 0x300 end
    vpCarry(E, e)
  elseif a == 7 then
    vpCarry(E, e)
    H.linMove(e)
    if f.room.height - 0x10 <= math.floor(e.y) and not e.exited then
      e.exited = true
      H.release(f, e)
      f:startTransition(MAZAAL_EXIT)
    end
  elseif a == 8 then
    if not H.alive(e.parent) then H.delete(e) return end
    H.posRel(e.parent, e, 0, -1)
    H.step(e)
  elseif a == 9 then
    local p = f.player
    e.x, e.y = math.floor(p.x), math.floor(p.y)
    if e.cz < -8 then
      if e.child and e.child.animIndex ~= 2 then e.timer = 0; H.setAnim(E, e.child, 2) end
      if e.timer ~= 0 then e.timer = e.timer - 1
      else e.cz = math.floor(e.cz) + 1; if e.cz == 0 then e.action = 3 end end
      H.step(e)
    else
      e.cz = e.cz + 8
    end
  end
  H.syncZ(e)
end
-- Mazaal's macro (another module) makes one with this
function M.createVaatiProjectile(E, parent, type2, x, y)
  local e = H.enemy(E, M, M.VPROJ, 0, x or parent.x, y or parent.y, nil)
  e.parent, e.vpParent, e.type2 = parent, parent, type2 or 0
  e.layer = parent and parent.layer or 1
  return e
end

-- ===========================================================================
-- R26 hooks
-- ===========================================================================
function M.spawnEnemy(E, dat, def)
  if dat.id == M.REBORN and (dat.paramA or 0) == 0 then
    local e = H.enemy(E, M, M.REBORN, 0, dat.x, dat.y, nil, true)
    H.home(E, e, dat)
    e.u74, e.u75, e.u76, e.u77, e.u80, e.u81, e.u82, e.u83, e.u84, e.u85, e.u86, e.u87 = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    e.boss1 = true
    return e
  elseif dat.id == M.VPROJ then
    local e = H.enemy(E, M, M.VPROJ, dat.paramA or 0, dat.x, dat.y, nil, true)
    e.type2 = band(dat.paramB or 0, 0xFF)
    return e
  end
  return nil
end

function M.handles(e) return e.r26 == M end

local function zero(e)
  for _, k in ipairs({ "u74", "u75", "u76", "u77", "u78", "u79", "u80", "u81", "u82", "u83", "u84", "u85", "u86", "u87" }) do
    if e[k] == nil then e[k] = 0 end
  end
end
function M.update(E, e)
  if e.deleted then return end
  zero(e)
  if e.vproj then
    local id = e.projId
    if id == M.P_DARK then M.dark(E, e)
    elseif id == M.P_FIRE then M.fireUpdate(E, e)
    elseif id == M.P_LASER then M.laserUpdate(E, e) end
  elseif e.id == M.REBORN then
    if e.type ~= 0 and not H.alive(e.parent) then H.delete(e) return end
    M.reborn(E, e)
  elseif e.id == M.BALL then M.ball(E, e)
  elseif e.id == M.VPROJ then M.vproj(E, e) end
  e.cflags = nil
  H.syncZ(e)
end

return M
