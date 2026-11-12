-- Round 26 (team B): Mazaal, the Fortress of Winds boss.  Ported from the
-- decomp: src/object/mazaalBossObject.c (MAZAAL_BOSS_OBJECT $89, room $58:16
-- type 8), src/enemy/mazaalHead.c (MAZAAL_HEAD $36, types 0..4),
-- src/object/mazaalObject.c (MAZAAL_OBJECT $7E, the shadows),
-- src/projectile/mazaalEnergyBeam.c (MAZAAL_ENERGY_BEAM $0E),
-- src/roomInit.c (BeforeMazaal / Mazaal state changes).  The hands are in
-- BossMazaal2.lua (mazaalBracelet.c $44, mazaalHand.c $38), the fight inside
-- the head in BossMazaal3.lua (mazaalMacro.c $37, vaatiProjectile.c $4B).
--
-- EVERY decomp entity is its own engine entity ("part": kind 3 / 4 / 6,
-- boss = true, impl = this module, mask = true), drawn by Field from its
-- spritePriority / y and ticked by Enemies:update -> M.update.  Fields keep
-- the Entity names (action, subAction, timer, subtimer, type2, direction 0-31,
-- speed 8.8, health, iframes, hitType, hitbox, cz = z.HALF.HI (negative up),
-- zv = zVelocity in px) and the struct fields unk_74.. as u74...
-- gRoomTransition.field_0x38 / 0x39 live on the Field (f.r26mazaal.f38 /
-- f39): f39 is Mazaal's health across the rooms ($5A at the door, $3C / $1E
-- the phase ends, 0 dead), f38 the "intro seen" / last vulnerable pillar.
--
-- MAZAAL_BOSS_OBJECT: Action0 local flag $31 -> room lists [type] (+[type2]
--   with the Ocarina) and the ARCHWAY $22 at (+$B8, +8); else MAZAAL_HEAD 0.
--   f38 set: f39 set -> gone (the head carries on), f39 0 (the macro died) ->
--   Action7 (camera on it) -> head timer 1 -> Action8 (180, SFX_SECRET_BIG,
--   flag $31, the archway; 90, the lists; 120, Link's control).  f38 0: the
--   intro (script_MazaalBossObjectMazaal + script_PlayerAtMazaal: Link walks
--   to ($B8,$94) facing up), Action2 30 frames -> camera on the head, Action3
--   120 -> head subAction 1, Action4 (head subAction > 2) 90 -> Action5 the
--   statue blends out (16 steps of 8 frames) -> Action6 15 -> head
--   subAction 6, f38 = $F1.
-- MAZAAL_HEAD type 0 (gUnk_080CECB4 by action): 0 init (head type 1, the
--   shadow, bracelets 0 / 1, head type 4; f39 0 -> 13), 1 the intro by
--   subAction (bracelet glows, rise to z -10, the hands blend in, BGM),
--   2 back to (+$B8, +$48), 3 / 4 waits, the attack picks (sub_0803443C:
--   gUnk_080CED0C / 2C / 4C by phase, a step each) -> 5 / 6 follow Link's
--   x, 7 / 8 the swipes, 9 both hands slam, 10 the beam eyes; 11 both hands
--   gone: shake 120, fall (gravity 32), 12 lie $708 frames (the mouth, head
--   type 4, takes Minish Link inside), 13 the death (252 frames: shake,
--   explosions gUnk_080CECF4).  sub_0803499C bobs it by gUnk_080CED6C.
--   Type 1 = the right half (flipped copy), type 2 / 3 = the beam eyes
--   (animation type+1, 30 frames, 80 frames of MAZAAL_ENERGY_BEAM fanning
--   $A8 - t / $58 + t, animation type+3, then the head's unk_7e = $FF),
--   type 4 = the mouth (pushes Link out; Minish Link in its region (+0, +$D,
--   3 x 3) on the ground -> AREA_INNER_MAZAAL room 1 (f39 >= $3D) or 0).
-- MAZAAL_ENERGY_BEAM: 10 frames along gSineTable[direction] * $800 (z rising
--   1 a frame), then animation 1 (y + 6, collision off) to its end; SFX_149.
--   Type 0 ($10) against Link: sub_08017DD4 (4 damage, iframes 90); type 1
--   ($11): CollisionMazaalShrinkRay (Link becomes Minish); Minish Link: the
--   matrix (2 damage).
-- SIMPLIFIED: the BG blends are sprite alpha (T.eva); the boss DEATH_FX is
--   FX_GIANT_EXPLOSION4 + SFX_BOSS_EXPLODE; the shrink ray sets Link Minish
--   at once (no PLAYER_MINISH animation); sub_08079D84 (Link shocked) is a
--   plain hurt; UnloadOBJPalette and the palette flash on hits are a blink.
--   Arrows (hurtType $15 / $0E, the only thing that knocks a hand down) and
--   bombs reach the parts only through M.hit(E, part, hurtType, x, y, dir):
--   Enemies:hit is masked off (e.mask) because its default row would apply.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local M = {}
M.ROM_RANGES = {} -- every table used here is written out in the .c sources

local C = {}
M.C = C
M.ID = { HEAD = 0x36, MACRO = 0x37, HAND = 0x38, BRACELET = 0x44, VPROJ = 0x4B, BEAM = 0x0E,
         OBJ = 0x7E, BOSS_OBJ = 0x89, ARCHWAY = 0x4F, BEETLE = 0x07, SMOKE = 0x2D, GROUND_ITEM = 0 }
local ID = M.ID
C.SFX = { BOSS_HIT = 0x127, BOSS_DIE = 0x128, BOSS_EXPLODE = 0x129, SECRET_BIG = 0x73, PLY_VO6 = 0x7A,
          S115 = 0x115, S149 = 0x149, S14F = 0x14F, S151 = 0x151, S153 = 0x153, S157 = 0x157, S158 = 0x158,
          S16E = 0x16E, S1A1 = 0x1A1, S1A9 = 0x1A9 }
C.BGM_BOSS_THEME = 0x2E
C.FX = { GIANT1 = 0x46, GIANT2 = 0x47, GIANT3 = 0x48, GIANT4 = 0x51, BIG_EXPLOSION2 = 0x43, DEATH = 0x02 }
C.SPECIAL_FX = 0x0F
C.AREA_FOW, C.ROOM_MAZAAL, C.ROOM_BEFORE = 0x58, 0x16, 0x01
C.AREA_INNER = 0x5A
C.FLAG_DONE = 0x31 -- local flag (CheckFlags(0x31))
C.ITEM_OCARINA = 0x17

-- gSineTable (256 steps a turn, $100 = 1)
local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
C.SIN = SIN

-- src/data/hitbox.c ({x, y, w, h}, half sizes)
C.HB = {
  H354 = { x = 0, y = -2, w = 32, h = 10 }, H35C = { x = 11, y = 2, w = 9, h = 8 }, H364 = { x = 12, y = 6, w = 9, h = 8 },
  H36C = { x = -11, y = 2, w = 9, h = 8 }, H374 = { x = -12, y = 6, w = 9, h = 8 }, H37C = { x = -2, y = -6, w = 4, h = 5 },
  H384 = { x = 2, y = -6, w = 4, h = 5 }, H38C = { x = 0, y = 0, w = 16, h = 12 }, H394 = { x = 31, y = 2, w = 9, h = 8 },
  H39C = { x = 8, y = 12, w = 10, h = 10 }, H3A4 = { x = 0, y = 12, w = 6, h = 18 }, H3AC = { x = -18, y = 10, w = 12, h = 12 },
  H3B4 = { x = -31, y = 2, w = 9, h = 8 }, H3BC = { x = -8, y = 12, w = 10, h = 10 }, H3C4 = { x = 18, y = 10, w = 12, h = 12 },
  H0 = { x = 0, y = -3, w = 6, h = 6 },
}

-- mazaalHead.c tables
M.BOB = { [0] = -0xA, -0xB, -0xC, -0xB, -0xA, -0x9, -0x8, -0x9 }               -- gUnk_080CED6C
M.SHAKE_FALL = { [0] = -1, -2, -1, 0, 1, 2, 1, 0 }                              -- gUnk_080CECEC (u8 as s8)
M.DEATH_FX_OFF = { [0] = -2, 0x01, -8, -4, -0x14, 0x08, 0x0E, -0x10, -6, 0x0C, 0x12, -2, 0x00, 0x00 } -- gUnk_080CECF4
M.DEATH_FX = { [0] = C.FX.GIANT1, C.FX.GIANT1, C.FX.GIANT2, C.FX.GIANT3 }       -- gUnk_080CED02
M.SHAKE_DEATH = { [0] = -1, 0, 1, 0, 0, 0 }                                     -- gUnk_080CED06
M.BEAM_OFF = { [0] = 0x0D, 0x10, -0x0D, 0x10 }                                  -- gUnk_080CED84
-- the attack patterns by phase (gUnk_080CED0C / 2C / 4C)
M.PAT = {
  [0] = { [0] = "s34578", "s344E0", "s3451C", "s344E0", "s34558", "s344E0", "s3451C", "s346A0" },
  [1] = { [0] = "s34578", "s345D0", "s3451C", "s346A0", "s34558", "s345D0", "s34558", "s346A0" },
  [2] = { [0] = "s34578", "s345D0", "s346C8", "s346A0", "s34558", "s346C8", "s346A0", "s346C8" },
}

-- ---------------------------------------------------------------------------
-- the shared machinery
-- ---------------------------------------------------------------------------
-- gRoomTransition.field_0x38 / field_0x39 (+ the port's blend level)
function C.state(f)
  local T = f.r26mazaal
  if not T then T = { f38 = 0, f39 = 0x5A, eva = 16 }; f.r26mazaal = T end
  return T
end
M.state = C.state

function C.rand(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end
function C.s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end

-- the decomp's definitions (enemy.c gEnemyDefinition_36 / 37 / 38 / 44, $4B;
-- projectile.c $0E) when the cache has none: {collision, draw, health, damageType}
local FALLBACK = {
  [0x36] = { [0] = { 1, 0, 255, 0x12 }, { 1, 1, 255, 0 }, { 1, 1, 255, 0 }, { 1, 1, 255, 0 }, { 1, 1, 255, 0 } },
  [0x37] = { [0] = { 1, 1, 255, 0x0F }, { 0, 1, 255, 0x0F }, { 0, 1, 255, 0x0F } },
  [0x38] = { [0] = { 1, 0, 255, 0x13 }, { 1, 0, 255, 0x13 } },
  [0x44] = { [0] = { 0, 0, 255, 0x17 }, { 0, 0, 255, 0x17 }, { 1, 0, 255, 0 }, { 1, 0, 255, 0 } },
  [0x4B] = { [0] = { 1, 1, 255, 0x0E }, { 1, 1, 255, 0x0E } },
}
local PFALLBACK = { [0x0E] = { [0] = { 1, 1, 0, 0x10 }, { 1, 1, 0, 0x11 } } }
local function defOf(f, kind, id, type)
  local m = f.assets and f.assets.manifest or {}
  local t = (kind == 3 and m.enemyDefs) or (kind == 4 and m.projectileDefs) or (kind == 6 and m.objectDefs) or nil
  local d = t and t[id]
  if d and (d.multi or d.type == 2) then d = d.forms and (d.forms[type or 0] or d.forms[0]) end
  if not d then
    local fb = (kind == 3 and FALLBACK[id]) or (kind == 4 and PFALLBACK[id])
    local r = fb and fb[type or 0]
    if r then d = { collision = r[1], draw = r[2], health = r[3], damageType = r[4], speed = kind == 4 and 0x800 or 0x100 } end
  end
  return d
end
C.defOf = defOf

local Impl = {}
M.Impl = Impl
C.TICK = {}

-- a new part (CreateEnemy / CreateObject / CreateProjectile).  Added to
-- f.entities unless noAdd (a room entity the caller hands back to Field).
function C.new(f, kind, id, type, x, y, mz, noAdd)
  local d = defOf(f, kind, id, type) or {}
  local pal = d.palette or 0
  local pt = {
    kind = kind, id = id, type = type or 0, form = type or 0, type2 = 0, x = x or 0, y = y or 0, z = 0, cz = 0, zv = 0,
    action = 0, subAction = 0, timer = 0, subtimer = 0, direction = 0, speed = d.speed or 0x100,
    health = d.health or 0xFF, iframes = 0, kbt = 0, hitType = d.damageType or 0,
    hitbox = _G.type(d.hitbox) == "table" and { x = d.hitbox.x or 0, y = d.hitbox.y or 0, w = d.hitbox.w or 0, h = d.hitbox.h or 0 } or { x = 0, y = -3, w = 6, h = 6 },
    collide = (d.collision or 0) ~= 0, drawOn = (d.draw or 0) ~= 0, flipX = false, spriteOX = 0, spriteOY = 0,
    spritePriority = d.priority or 4, sprite = d.sprite, def = d, anim = Anim.new(), literalAnim = true,
    field82 = 0, interactType = 0, layer = 1, enemy = true, boss = true, impl = Impl, mask = true, mz = mz, f = f,
    palId = pal, animIndex = -1,
  }
  pt.gfx = d.gfx and Assets.gfxSource(kind == 6 and (d.gfxType or 0) or "enemy", d.gfx) or nil
  if f.assets and f.assets.objPalette and d.palette then
    pt.palette = f.assets:objPalette(pal, f.room and f.room.atlas and f.room.atlas.palettes)
  end
  if not noAdd then f.entities[#f.entities + 1] = pt end
  return pt
end

function C.setPal(pt, id) -- ChangeObjPalette
  if pt.palId == id and pt.palette then return end
  pt.palId = id
  local f = pt.f
  if f.assets and f.assets.objPalette then pt.palette = f.assets:objPalette(id, f.room and f.room.atlas and f.room.atlas.palettes) end
end

-- InitializeAnimation / InitAnimationForceUpdate
function C.anim(pt, idx)
  pt.animIndex = idx
  local spr = pt.sprite and pt.f.assets and pt.f.assets.sprite and pt.f.assets:sprite(pt.sprite)
  pt.anim:set(spr, idx, true)
  if not pt.anim.keys then pt.anim.flags = 0x80; pt.anim.frame = pt.anim.frame or 0xFF end -- no data: done at once
end
function C.next(pt) pt.anim:update(1) end -- GetNextFrame / UpdateAnimationSingleFrame
function C.done(pt) return band(pt.anim.flags or 0, 0x80) ~= 0 end -- frame & ANIM_DONE
function C.fflags(pt) return pt.anim.flags or 0 end
function C.frameIndex(pt) return pt.frameIndex or pt.anim.frame end

function C.rel(src, dst, dx, dy) -- PositionRelative (z copied)
  dst.x, dst.y, dst.cz = src.x + (dx or 0), src.y + (dy or 0), src.cz or 0
end
function C.copyPos(src, dst) dst.x, dst.y, dst.cz = src.x, src.y, src.cz or 0 end
function C.copyPosOff(src, dst) C.copyPos(src, dst); dst.spriteOX, dst.spriteOY = src.spriteOX or 0, src.spriteOY or 0 end

function C.move(pt) -- LinearMoveUpdate (direction 0-31, speed 8.8)
  local a = (pt.direction % 32) * 8
  pt.x = pt.x + SIN[a] * pt.speed / 65536
  pt.y = pt.y - SIN[(a + 64) % 256] * pt.speed / 65536
end
function C.dirTo(ax, ay, bx, by) -- CalculateDirectionTo (0-31)
  local a = math.atan2(bx - ax, -(by - ay))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
function C.facing(a, b) return C.dirTo(a.x, a.y, b.x, b.y) end -- GetFacingDirection
function C.turn(pt, want) -- sub_08004596: one step toward
  local dd = band(want - pt.direction, 0x1F)
  if dd ~= 0 then pt.direction = band(pt.direction + (dd < 0x10 and 1 or -1), 0x1F) end
end
function C.within(pt, x, y, d) -- EntityWithinDistance
  local dx, dy = math.floor(pt.x) - math.floor(x), math.floor(pt.y) - math.floor(y)
  return d * d >= dx * dx + dy * dy
end
-- GravityUpdate: 0 once on the ground
function C.gravity(pt, g)
  pt.cz = pt.cz - pt.zv
  pt.zv = pt.zv - g
  if pt.cz >= 0 then pt.cz, pt.zv = 0, 0 return 0 end
  return 1
end
function C.hi(v) return math.floor(v) end -- x.HALF.HI of a 16.16

function C.gone(pt) return pt == nil or pt.deleted end -- parent->next == NULL
function C.delete(pt) pt.deleted = true end

-- the camera (gRoomControls.camera_target)
function C.camera(f, pt)
  if pt == nil or pt == f.player then f.cameraTarget = nil else f.cameraTarget = pt end
end

-- Link's control (SetPlayerControl / DisablePlayerControl / CONTROL_1)
function C.freeze(f)
  local p = f.player
  if p.state == "dead" then return end
  p.state = "ext"
  p.extUpdate = p.extUpdate or function() end
  p.mazaalFrozen = true
end
function C.release(f)
  local p = f.player
  if p.mazaalFrozen then
    p.state, p.extUpdate, p.mazaalFrozen = "normal", nil, nil
    p.animId = -1
  end
end

-- the transition (DoExitTransition): `spawn` = what the cartridge's spawn type does to the size
function C.exit(f, area, room, x, y, facing, spawn)
  local T = C.state(f)
  T.spawn = spawn
  f:startTransition({ warpType = 1, area = area, room = room, endX = x, endY = y, facing = facing or 0, kind = 0, layer = 1 })
end

function C.fx(f, x, y, t) if f.addFx then f:addFx(x, y, C.SPECIAL_FX, t) end end
function C.shake(f, t, m) if f.shake then f:shake(t, m or 0) end end

-- ---------------------------------------------------------------------------
-- collisions
-- ---------------------------------------------------------------------------
local function mtxOf(f)
  local E = f._enemies or (f.enemies and f:enemies())
  return E, E and E.mtx or ""
end

-- Link touched by a part: the matrix row (hitType, Link's hurtType); returns
-- the special handler id when the row is one (the caller reacts) or "hit"
function C.touch(f, pt)
  local p = f.player
  if not pt.collide or pt.deleted or p.state == "dead" or p.mazaalHeld then return nil end
  if math.abs((pt.cz or 0) + (p.z or 0)) > 12 then return nil end
  local HB = require("src.zelda.tmc.Hitboxes")
  local hb = pt.hitbox
  local touch = HB.touches(f, p, pt)
  if touch == nil then
    touch = math.abs((pt.x + (hb.x or 0)) - p.x) < (hb.w or 4) + 5 and math.abs((pt.y + (hb.y or 0)) - (p.y - 3)) < (hb.h or 4) + 6
  end
  if not touch then return nil end
  local E, mtx = mtxOf(f)
  local hurt = HB.hurtType(p)
  local h = HB.handler(mtx, pt.hitType or 0, hurt)
  if h == 1 or h == 2 then return nil end
  if h == 16 then HB.pushOut(f, pt, hb) return 16 end
  if h then if p.invuln > 0 then return nil end return h end
  if p.invuln > 0 then return nil end
  local s = E and E:settings(pt.hitType or 0, hurt) or { tgtDmg = 2, orgIfr = 30, orgKbDur = 8, orgKbSpd = 24 }
  if (s.tgtDmg or 0) > 0 or (s.orgKbDur or 0) > 0 then C.hurtLink(f, s, pt.x, pt.y) end
  return "hit"
end

function C.hurtLink(f, s, x, y)
  local p = f.player
  if p:hurt(math.max(s.tgtDmg or 0, 1), x, y) then
    p.invuln = math.max(s.orgIfr or 30, 30)
    p.timer = math.max(s.orgKbDur or 8, 4)
    local ks = ((s.orgKbSpd or 24) * 16) / 256
    local dx, dy = p.x - x, p.y - y
    local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    p.kbx, p.kby = dx / dd * ks, dy / dd * ks
  end
end

-- ModHealth(-n) with no knockback (sub_0803B804 / CalculateDamage)
function C.modHealth(f, n)
  f:modStat("health", -n)
  f:sound(C.SFX.PLY_VO6)
  local p = f.player
  if (f.save.stats.health or 0) <= 0 and p.state ~= "dead" then
    p.state, p.timer, p.extUpdate, p.mazaalFrozen, p.mazaalHeld = "dead", 90, nil, nil, nil
    p.z = 0
    f:sound(0x87)
  end
end

-- a hit from Link's side on a part (the sword = hurtType 4); `dir` is the
-- attacker's direction (sub_08018250 wants an arrow flying north, 0)
function M.hit(E, pt, hurtType, fromX, fromY, dir)
  if pt.deleted or not pt.collide or pt.iframes ~= 0 then return false end
  local HB = require("src.zelda.tmc.Hitboxes")
  local h = HB.handler(E.mtx or "", pt.hitType or 0, hurtType)
  if h == 1 or h == 2 then return false end
  local f = pt.f
  if h == 17 then -- sub_08018250
    if (dir or 0) == 0 then pt.iframes = 16 else pt.iframes = -1 end
    pt.contactFlags = bor(0x80, hurtType)
    if pt.onCollision then pt.onCollision(f, E, pt, pt.contactFlags) end
    return true
  end
  if h then return false end -- other handlers: not reached by Link's items here
  local s = E:settings(pt.hitType or 0, hurtType)
  if not s then return false end
  local dmg = s.orgDmg or 0
  if dmg > 0 then
    pt.health = math.max(0, pt.health - dmg)
    f:sound(pt.kind == 3 and pt.bossFlag and C.SFX.BOSS_HIT or 0xFE)
  end
  if (s.tgtIfr or 0) ~= 0 then pt.iframes = s.tgtIfr elseif dmg > 0 then pt.iframes = 12 end
  if pt.knockable and (s.tgtKbDur or 0) > 0 then
    local dx, dy = pt.x - (fromX or pt.x), pt.y - (fromY or pt.y)
    local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    local ks = ((s.tgtKbSpd or 24) * 16) / 256
    pt.kbx, pt.kby, pt.kbt = dx / dd * ks, dy / dd * ks, s.tgtKbDur
  end
  pt.contactFlags = bor(0x80, hurtType)
  if pt.onCollision then pt.onCollision(f, E, pt, pt.contactFlags) end
  return true
end

-- ---------------------------------------------------------------------------
-- the engine's calls (Enemies:update / Field draw / Enemies:swordHits)
-- ---------------------------------------------------------------------------
function Impl:update(pt)
  if pt.deleted then return end
  local f = pt.f
  local E = f._enemies
  if pt.iframes > 0 then pt.iframes = pt.iframes - 1 elseif pt.iframes < 0 then pt.iframes = pt.iframes + 1 end
  if pt.kbt and pt.kbt > 0 then
    pt.kbt = pt.kbt - 1
    pt.x, pt.y = pt.x + (pt.kbx or 0), pt.y + (pt.kby or 0)
  end
  local fn = C.TICK[pt.mz]
  if fn then fn(f, E, pt) end
  pt.z = -(pt.cz or 0)
end

function Impl:swordHit(pt, box)
  if pt.deleted or not pt.collide or pt.iframes ~= 0 then return false end
  local hb = pt.hitbox
  if math.abs((pt.x + (hb.x or 0)) - box.x) < (hb.w or 0) + box.w and math.abs((pt.y + (hb.y or 0)) - box.y) < (hb.h or 0) + box.h then
    if math.abs(pt.cz or 0) > 16 then return false end
    local p = pt.f.player
    return M.hit(pt.f._enemies, pt, 4, p.x, p.y, (p.animationState or 0) * 4)
  end
  return false
end

function Impl:draw(pt, camX, camY)
  if pt.deleted or not pt.drawOn or not pt.sprite then return end
  local f = pt.f
  local fr = C.frameIndex(pt)
  if not fr or fr == 0xFF then return end
  if pt.iframes > 0 and pt.iframes % 4 < 2 and pt.kind == 3 then return end
  local img, ox, oy = f.assets:spriteFrame(pt.sprite, fr, pt.palette, "mz" .. pt.sprite .. ":" .. tostring(pt.palId), pt.gfx)
  if not img then return end
  local x = math.floor(pt.x - camX + (pt.spriteOX or 0))
  local y = math.floor(pt.y - camY + (pt.cz or 0) + (pt.spriteOY or 0))
  local a = 1
  if pt.alphaBlend then a = math.max(0, math.min(1, (C.state(f).eva or 16) / 16)) end
  if pt.alpha then a = a * pt.alpha end
  if a <= 0 then return end
  if a < 1 then love.graphics.setColor(1, 1, 1, a) end
  local hf = (pt.frameIndex == nil and pt.anim:hflip() or false) ~= (pt.flipX or false)
  if hf then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
  if a < 1 then love.graphics.setColor(1, 1, 1, 1) end
end

-- ---------------------------------------------------------------------------
-- MAZAAL_BOSS_OBJECT ($89)
-- ---------------------------------------------------------------------------
local function loadLists(f, pt) -- sub_0809AD68
  local d = f._dungeon
  if not d then return end
  for _, k in ipairs({ pt.type, (f:inventory(C.ITEM_OCARINA) or 0) ~= 0 and pt.type2 or nil }) do
    local list = d:propList(k)
    if list then f:loadEntityList(nil, list) end
  end
end
local function archway(f) -- sub_0809AD8C: ARCHWAY $22 at (+$B8, +8)
  if f.spawn then pcall(f.spawn, f, { kind = 6, id = ID.ARCHWAY, paramA = 0x22, paramB = 0, paramC = 0, x = 0xB8, y = 8, pool = 0x0F, collision = 0 }) end
end
M.loadLists, M.archway = loadLists, archway

-- the intro's two scripts: script_MazaalBossObjectMazaal + script_PlayerAtMazaal
local function introScript(f, pt)
  local s = pt.mzScript
  local p = f.player
  if s.phase == 0 then
    C.freeze(f) -- DisablePlayerControl
    s.phase, s.t = 1, 0x18
  elseif s.phase == 1 then
    s.t = s.t - 1
    if s.t <= 0 then
      s.phase = 2 -- SetPlayerIdle, StartPlayerScript: SetAnimationState 0, SetEntitySpeed $140, MoveTo($B8, $94)
      p.animationState = 0
    end
  elseif s.phase == 2 then
    local dx, dy = 0xB8 - p.x, 0x94 - p.y
    local d = math.sqrt(dx * dx + dy * dy)
    local sp = 0x140 / 256
    if d <= sp then
      p.x, p.y = 0xB8, 0x94
      s.phase, s.t = 3, 8 + 8 -- Wait 8, DoPostScriptAction 0, Wait 8
      pcall(function() p:setAnim(p:animFor("idle"), true) end)
      p.animationState = 0
    else
      p.x, p.y = p.x + dx / d * sp, p.y + dy / d * sp
      pcall(function() p:setAnim(p:animFor("walk")) end)
      p.anim:update(1)
    end
  elseif s.phase == 3 then
    s.t = s.t - 1
    if s.t <= 0 then s.phase = 4 end -- SetSyncFlag 1
  end
  if s.phase == 4 then pt.action = 2; pt.mzScript = nil end -- WaitForSyncFlagAndClear 1, SetAction 2
end

C.TICK.bossobj = function(f, E, pt)
  local T = C.state(f)
  local a = pt.action
  if a == 0 then
    if f._dungeon and f._dungeon:check(C.FLAG_DONE) then
      loadLists(f, pt); archway(f)
      C.delete(pt)
      return
    end
    local head = C.new(f, 3, ID.HEAD, 0, pt.x, pt.y, "head")
    C.copyPos(pt, head)
    pt.child = head
    if T.f38 ~= 0 then
      if T.f39 ~= 0 then C.delete(pt) return end
      pt.action = 7
      pt.drawOn = false
      C.camera(f, pt)
      C.freeze(f) -- sub_StateChange_FortressOfWinds_Mazaal: SetPlayerControl(3)
    else
      pt.action, pt.timer = 1, 30
      pt.frameIndex = T.f38
      pt.spritePriority = 7
      pt.spriteOY = 0x20
      pt.drawOn = true
      pt.mzScript = { phase = 0 }
      if f.bgm then f:bgm(nil) end -- SONG_STOP_BGM
    end
  elseif a == 1 then introScript(f, pt)
  elseif a == 2 then
    pt.timer = pt.timer - 1
    if pt.timer == 0 then pt.action, pt.timer = 3, 120; C.camera(f, pt.child) end
  elseif a == 3 then
    pt.timer = pt.timer - 1
    if pt.timer == 0 then pt.action, pt.timer = 4, 90; pt.child.subAction = 1 end
  elseif a == 4 then
    if pt.child.subAction > 2 then
      pt.timer = pt.timer - 1
      if pt.timer == 0 then
        pt.action, pt.timer, pt.subtimer = 5, 8, 0
        pt.alpha = 1 -- BLDALPHA_BLEND($10, 0)
      end
    end
  elseif a == 5 then
    pt.timer = pt.timer - 1
    if pt.timer == 0 then
      pt.timer = 8
      pt.subtimer = band(pt.subtimer + 1, 0xFF)
      pt.alpha = (16 - pt.subtimer) / 16
      if pt.subtimer > 15 then
        pt.alpha = nil
        pt.action, pt.timer = 6, 15
        pt.drawOn = false
      end
    end
  elseif a == 6 then
    pt.timer = pt.timer - 1
    if pt.timer == 0 then
      pt.child.subAction = 6
      T.f38 = 0xF1
      C.delete(pt)
    end
  elseif a == 7 then
    if pt.child.timer == 1 then pt.action, pt.subAction, pt.timer = 8, 0, 180 end
  elseif a == 8 then
    local s = pt.subAction
    if s == 1 then
      pt.timer = pt.timer - 1
      if pt.timer == 0 then pt.timer, pt.subAction = 120, 2; loadLists(f, pt) end
    elseif s == 2 then
      pt.timer = pt.timer - 1
      if pt.timer == 0 then
        C.camera(f, f.player)
        C.release(f)
        C.delete(pt)
      end
    else
      pt.timer = pt.timer - 1
      if pt.timer == 0 then
        pt.timer, pt.subAction = 90, 1
        f:sound(C.SFX.SECRET_BIG)
        if f._dungeon then f._dungeon:set(C.FLAG_DONE) end
        archway(f)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- MAZAAL_OBJECT ($7E): the shadows
-- ---------------------------------------------------------------------------
C.TICK.mobj = function(f, E, pt)
  if C.gone(pt.parent) then C.delete(pt) return end
  if pt.action == 0 then
    pt.action = 1
    pt.spritePriority = 7
    pt.frameIndex = 0x28
    if pt.type == 0 then pt.drawOn = true elseif pt.type == 2 then pt.flipX = true end
  end
  C.rel(pt.parent, pt, 0, 8)
  pt.cz = 0
  if pt.type ~= 0 and pt.child then
    pt.drawOn = pt.child.drawOn and not pt.child.deleted
    local fi = C.frameIndex(pt.child)
    pt.frameIndex = (fi and fi ~= 0xFF) and fi + 0x1F or 0xFF
  end
end

-- ---------------------------------------------------------------------------
-- MAZAAL_HEAD ($36)
-- ---------------------------------------------------------------------------
local H = {}
M.H = H

function H.s34420(e) e.action = 2; e.u7d = 3 end
function H.s3442C(e, t) e.action = 4; e.timer = t; e.u7d = 3 end
function H.s349D8(e) -- the hands asked are back
  local v = band(e.u7d, 3)
  if v == 3 then return true end
  if v == 1 then return band(e.u80, 10) ~= 0 end
  if v == 2 then return band(e.u80, 5) ~= 0 end
  return false
end
function H.s34A10(e)
  if band(e.u7d, 0x60) ~= 0x40 then
    if band(e.u7d, 0x10) ~= 0 then
      if band(e.u80, 5) ~= 0 then e.u7d = bor(e.u7d, 0x40) end
      if band(e.u80, 10) ~= 0 and band(e.u7d, 3) == 1 then return 1 end
    else
      if band(e.u80, 10) ~= 0 then e.u7d = bor(e.u7d, 0x40) end
      if band(e.u80, 5) == 0 then return 0 end
      if band(e.u7d, 3) == 2 then return 1 end
    end
  else
    return 1
  end
  return 0
end

-- sub_080348A4: order a bracelet (0 home, 1 three slams, 2 / 4 one slam, 3 / 5 the swipe, 6 both slam, 7 hide, 8 a beam eye)
function H.order(f, e, hand, unk)
  local bv
  if hand.type == 0 then bv = 5; e.u7d = bor(e.u7d, 0x10) else bv = 10 end
  if band(e.u80, bv) ~= 0 then
    e.u7d = bor(e.u7d, hand.type == 0 and 1 or 2)
    return 0
  end
  if unk == 0 then hand.action = 3
  elseif unk == 1 then hand.action = 4; hand.u7c = 3
  elseif unk == 2 or unk == 4 then hand.action = 4; hand.u7c = 1
  elseif unk == 3 then hand.action = 0xF; hand.u7e = 0xB4
  elseif unk == 5 then hand.action = 0xF; hand.u7e = 1
  elseif unk == 6 then hand.action = 0x1E
  elseif unk == 7 then hand.action = 0x1B; hand.collide = false; C.anim(hand, 5)
  elseif unk == 8 then
    local eye = C.new(f, 3, ID.HEAD, hand.type + 2, e.x, e.y, "head")
    eye.parent = e
  end
  return 1
end

local function r1(f) return band(C.rand(f), 1) ~= 0 end
function H.s34578(f, e) e.action = 3; e.u7d = 0; H.order(f, e, e.u74, 0); H.order(f, e, e.u78, 0) end
function H.s345A0(f, e) e.action = 5; e.u7d = 1; H.order(f, e, e.u78, 1) end
function H.s345B8(f, e) e.action = 5; e.u7d = 2; H.order(f, e, e.u74, 1) end
function H.s344E0(f, e)
  if band(e.u80, 5) ~= 0 then H.s345A0(f, e)
  elseif band(e.u80, 10) ~= 0 or r1(f) then H.s345B8(f, e)
  else H.s345A0(f, e) end
end
function H.s34618(f, e) e.action = 7; e.u7d = 1; e.u7e = 0xB4; H.order(f, e, e.u78, 3) end
function H.s34638(f, e) e.action = 7; e.u7d = 2; e.u7e = 0xB4; H.order(f, e, e.u74, 3) end
function H.s3451C(f, e)
  if band(e.u80, 5) ~= 0 then H.s34618(f, e)
  elseif band(e.u80, 10) ~= 0 then H.s34638(f, e)
  elseif r1(f) then H.s34618(f, e)
  else H.s34638(f, e) end
end
function H.s34658(f, e) e.action = 8; e.u7d = 0; if H.order(f, e, e.u78, 4) == 0 then e.u7d = bor(e.u7d, 0x40) end end
function H.s3467C(f, e) e.action = 8; e.u7d = 0; if H.order(f, e, e.u74, 4) == 0 then e.u7d = bor(e.u7d, 0x40) end end
function H.s34558(f, e) if r1(f) then H.s34658(f, e) else H.s3467C(f, e) end end
function H.s345D0(f, e)
  e.action = 6
  if r1(f) then
    if H.order(f, e, e.u74, 2) == 0 then H.order(f, e, e.u78, 2) end
  else
    if H.order(f, e, e.u78, 2) == 0 then H.order(f, e, e.u74, 2) end
  end
end
function H.s346A0(f, e) e.action = 9; e.u7d = 0; H.order(f, e, e.u74, 6); H.order(f, e, e.u78, 6) end
function H.s346C8(f, e)
  e.action = 10
  e.u7e = 0
  if r1(f) then
    if H.order(f, e, e.u74, 8) ~= 0 then H.order(f, e, e.u78, 7)
    else H.order(f, e, e.u74, 7); H.order(f, e, e.u78, 8) end
  else
    if H.order(f, e, e.u78, 8) ~= 0 then H.order(f, e, e.u74, 7)
    else H.order(f, e, e.u74, 8); H.order(f, e, e.u78, 7) end
  end
end
function H.s3443C(f, e) -- the next attack by phase
  local T = C.state(f)
  e.u7d = 0
  local ph = (T.f39 < 0x1F and 2) or (T.f39 < 0x3D and 1) or 0
  local fn = M.PAT[ph][e.u7c]
  H[fn](f, e)
  e.u7c = band(e.u7c + 1, 7)
end

-- follow Link's x (sub_080347B4; sub_0803473C keeps $60 to one side)
local function followX(f, e, px)
  if px - 4 > e.x then
    if 0xE0 < e.x then return end
    e.direction = 8
  else
    if px + 4 >= e.x then return end
    if 0x90 > e.x then return end
    e.direction = 0x18
  end
  C.move(e)
end
function H.s347B4(f, e) followX(f, e, f.player.x) end
function H.s3473C(f, e)
  local px
  if band(e.u7d, 0x10) ~= 0 then
    if e.u74.action > 0x28 then return end
    px = f.player.x - 0x60
  else
    if e.u78.action > 0x28 then return end
    px = f.player.x + 0x60
  end
  followX(f, e, px)
end
function H.s347FC(f, e)
  if band(e.u7d, 0x10) ~= 0 then H.order(f, e, e.u78, 5) else H.order(f, e, e.u74, 5) end
  e.u7d = bor(e.u7d, 0x20)
end
function H.s34830(f, e)
  if H.s349D8(e) then
    e.u7d = 0x80
    H.s345D0(f, e)
  elseif H.s34A10(e) ~= 0 then
    if band(e.u80, 0xF) ~= 0 then
      if H.s349D8(e) then H.s34420(e) end
    else
      e.u7d = bor(e.u7d, 0x20)
      if band(e.u7d, 0x10) ~= 0 then H.order(f, e, e.u78, 2) else H.order(f, e, e.u74, 2) end
    end
  end
end

-- type 0 by action (gUnk_080CECB4)
local HA = {}
HA[0] = function(f, E, e) -- sub_08033F3C
  local T = C.state(f)
  if T.f38 ~= 0 then H.s34420(e); e.u81 = 1 else e.action = 1 end
  e.drawOn = true
  e.bossFlag = true -- unk_6d |= 1
  e.u80 = 0
  C.anim(e, 0)
  local h1 = C.new(f, 3, ID.HEAD, 1, e.x, e.y, "head")
  h1.parent = e
  e.half = h1
  local sh = C.new(f, 6, ID.OBJ, 0, e.x, e.y, "mobj")
  sh.parent = e
  if T.f39 == 0 then
    e.action, e.subAction, e.timer = 0xD, 0, 252
    e.collide = false
  else
    local b0 = C.new(f, 3, ID.BRACELET, 0, e.x, e.y, "bracelet")
    b0.parent = e; b0.u78 = e; e.u74 = b0
    local b1 = C.new(f, 3, ID.BRACELET, 1, e.x, e.y, "bracelet")
    b1.parent = e; b1.u78 = h1; e.u78 = b1
    local h4 = C.new(f, 3, ID.HEAD, 4, e.x, e.y, "head")
    h4.parent = e
  end
end
HA[1] = function(f, E, e) -- sub_08033FFC: the intro
  local T = C.state(f)
  local s = e.subAction
  if s == 0 or s == 2 or s == 5 then return end
  if s == 1 then
    e.subAction, e.timer = 2, 30
    e.u74.u74.subAction = 1
    e.u78.u74.subAction = 1
  elseif s == 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.subAction = 4 end
  elseif s == 4 then
    e.cz = e.cz - 0.5
    if math.floor(e.cz) == -10 then e.subAction = 5; e.u81 = 1 end
  elseif s == 6 then
    e.subAction, e.timer = 7, 0
    e.u74.subAction = 1; e.u74.u74.subAction = 4
    e.u78.subAction = 1; e.u78.u74.subAction = 4
    T.eva = 0 -- layerFXControl $F40, alphaBlend $1000
  elseif s == 7 then
    e.timer = e.timer + 1
    T.eva = rshift(e.timer, 1)
    if e.timer > 31 then
      e.subAction = 8
      e.u74.subAction = 3; e.u74.u74.subAction = 6
      e.u78.subAction = 3; e.u78.u74.subAction = 6
      e.alphaBlend = nil
      T.eva = 16
    end
  else
    if e.u74.collide then
      C.camera(f, f.player)
      H.s34420(e)
      C.release(f) -- CONTROL_1, ResetPlayerAnimationAndAction
      if f.bgm then f:bgm(C.BGM_BOSS_THEME) end
    end
  end
end
HA[2] = function(f, E, e) -- sub_0803414C
  local x, y = 0xB8, 0x48
  if math.abs(math.floor(e.x) - x) <= 1 and math.abs(math.floor(e.y) - y) <= 1 then
    if H.s349D8(e) then
      if e.subAction ~= 0 then e.subAction = 0; H.s3442C(e, 0x1E) else H.s3442C(e, 0x5A) end
    end
  else
    e.direction = C.dirTo(e.x, e.y, x, y)
    C.move(e)
  end
end
HA[3] = function(f, E, e) if H.s349D8(e) then H.s3442C(e, 0x2D) end end
HA[4] = function(f, E, e)
  if band(e.u80, 3) ~= 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then H.s3443C(f, e) end
  end
end
HA[5] = function(f, E, e) H.s347B4(f, e); if H.s349D8(e) then H.s34420(e) end end
HA[6] = function(f, E, e)
  H.s347B4(f, e)
  if band(e.u7d, 0x80) ~= 0 and H.s349D8(e) then H.s34420(e) else H.s34830(f, e) end
end
HA[7] = function(f, E, e)
  if e.u7e ~= 0 then
    e.u7e = e.u7e - 1
    if e.u7e < 0x96 then H.s3473C(f, e) end
  end
  if H.s349D8(e) then H.s34420(e) end
end
HA[8] = function(f, E, e)
  if H.s349D8(e) then H.s34420(e)
  else
    H.s3473C(f, e)
    if H.s34A10(e) ~= 0 then H.s347FC(f, e) end
  end
end
HA[9] = function(f, E, e) if H.s349D8(e) then H.s34420(e) end end
HA[10] = function(f, E, e) if e.u7e == 0xFF then H.s34420(e) end end
HA[11] = function(f, E, e) -- sub_080342C8: both hands gone, it drops
  if e.timer ~= 0 then
    e.timer = e.timer - 1
    if e.timer == 0 then f:sound(C.SFX.S115) end
    e.spriteOX = M.SHAKE_FALL[band(rshift(e.timer, 1), 7)]
  else
    e.spriteOX = 0
    if C.gravity(e, 32 / 256) == 0 then
      e.action = 0xC
      e.u7e, e.u7d, e.u81 = 0x708, 0, 0
      C.shake(f, 30, 0)
      f:sound(C.SFX.S1A1)
    end
  end
end
HA[12] = function(f, E, e) -- sub_08034348: on the ground
  if e.u7e ~= 0 then e.u7e = e.u7e - 1
  elseif e.cz > -10 then e.cz = e.cz - 1
  elseif H.s349D8(e) then e.u81 = 1; H.s34420(e) end
end
HA[13] = function(f, E, e) -- sub_0803438C: the death
  if e.timer == 0 then
    e.health = 0
  else
    e.timer = e.timer - 1
    if e.timer > 192 then
      e.spriteOX = M.SHAKE_DEATH[band(e.timer, 3)]
    elseif band(e.timer, 0x1F) == 0 then
      local k = rshift(e.timer, 4)
      C.fx(f, e.x + (M.DEATH_FX_OFF[k] or 0), e.y + (M.DEATH_FX_OFF[k + 1] or 0), M.DEATH_FX[band(C.rand(f), 3)])
    end
  end
end
M.HA = HA

-- GenericDeath -> EnemyCreateDeathFX (a boss: DEATH_FX, UpdateGlobalProgress, SONG_STOP_BGM)
function C.bossDeath(f, e)
  C.fx(f, e.x, e.y, C.FX.GIANT4)
  f:sound(C.SFX.BOSS_EXPLODE)
  if f.updateProgress then f:updateProgress() end
  if f.bgm then f:bgm(nil) end
  C.delete(e)
end

local function headType0(f, E, e)
  if e.health == 0 then C.bossDeath(f, e) return end
  local fn = HA[e.action]
  if fn then fn(f, E, e) end
  -- sub_0803499C
  if band(e.u80, 0xC) ~= 0xC and e.u81 ~= 0 then
    e.subtimer = band(e.subtimer + 1, 0xFF)
    e.cz = M.BOB[band(rshift(e.subtimer, 4), 7)]
  end
  if C.touch(f, e) == 16 then end -- hitType $12: pushes Link out
end

local function headType1(f, E, e) -- sub_08034A84: the right half
  if C.gone(e.parent) then C.delete(e) return end
  if e.action == 0 then
    e.action = 1
    e.drawOn = true
    e.flipX = true
    C.anim(e, 0)
  end
  C.copyPosOff(e.parent, e)
end

-- types 2 / 3: the beam eyes (gUnk_080CED74)
local function headEye(f, E, e)
  if C.gone(e.parent) then C.delete(e) return end
  C.rel(e.parent, e, 0, 1)
  local a = e.action
  if a == 0 then
    e.action, e.timer = 1, 30
    e.drawOn = true
    C.anim(e, e.type + 1)
    f:sound(C.SFX.S151)
  elseif a == 1 then
    if e.timer ~= 0 then e.timer = e.timer - 1
    else
      C.next(e)
      if not C.done(e) then return end
      e.action, e.timer = 2, 80
    end
  elseif a == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action = 3
      C.anim(e, e.type + 3)
    else
      M.beam(f, e)
    end
  elseif a == 3 then
    C.next(e)
    if C.done(e) then
      e.parent.u7e = 0xFF
      C.delete(e)
    end
  end
end

local function headMouth(f, E, e) -- type 4 (sub_08034BC8)
  if C.gone(e.parent) then C.delete(e) return end
  if e.action == 0 then e.action = 1; C.anim(e, 1) end
  C.rel(e.parent, e, 0, 1) -- sub_0806FA90
  e.spriteOX, e.spriteOY = e.parent.spriteOX or 0, e.parent.spriteOY or 0
  -- sub_0800445C: Link is pushed out of it
  local HB = require("src.zelda.tmc.Hitboxes")
  if f.player.state ~= "dead" then HB.pushOut(f, e, e.hitbox) end
  if math.floor(e.cz) == 0 then M.mouthEnter(f, e) end
end
-- sub_08034C00
function M.mouthEnter(f, e)
  local p = f.player
  if not p.minish or f.transition then return false end
  if p.x > e.x - 3 and p.x <= e.x + 3 and p.y > e.y + 0xD - 3 and p.y <= e.y + 0xD + 3 then
    local T = C.state(f)
    C.exit(f, C.AREA_INNER, T.f39 >= 0x3D and 1 or 0, 0x88, 0xF8, 0, "normal")
    return true
  end
  return false
end

C.TICK.head = function(f, E, e)
  if e.type == 0 then headType0(f, E, e)
  elseif e.type == 1 then headType1(f, E, e)
  elseif e.type == 4 then headMouth(f, E, e)
  else headEye(f, E, e) end
end

function C.headInit(e) -- the struct's fields
  e.u74, e.u78, e.u7c, e.u7d, e.u7e, e.u80, e.u81 = nil, nil, 0, 0, 0, 0, 0
end

-- ---------------------------------------------------------------------------
-- MAZAAL_ENERGY_BEAM ($0E)
-- ---------------------------------------------------------------------------
function M.beam(f, eye) -- sub_08034B38's CreateProjectile
  local t = eye.type - 2
  local b = C.new(f, 4, ID.BEAM, t, eye.x, eye.y, "beam")
  b.projectile = nil
  if t == 0 then b.direction = band(0xA8 - eye.timer, 0xFF) else b.direction = band(eye.timer + 0x58, 0xFF) end
  C.rel(eye, b, M.BEAM_OFF[t * 2], M.BEAM_OFF[t * 2 + 1])
  b.speed = (b.def and b.def.speed) or 0x800
  if b.speed == 0 then b.speed = 0x800 end
  b.collide = true
  return b
end
C.TICK.beam = function(f, E, b)
  local a = b.action
  if a == 0 then
    b.action, b.timer = 1, 10
    b.cz = b.cz - 2
    b.y = b.y + 2
    b.drawOn = true
    C.anim(b, 0)
    f:sound(C.SFX.S149)
  elseif a == 1 then
    b.timer = b.timer - 1
    if b.timer == 0 then
      b.action = 2
      b.collide = false
      b.spritePriority = 7
      b.y = b.y + 6
      C.anim(b, 1)
    else
      if math.floor(b.cz) ~= 0 then b.cz = b.cz + 1 end
      local s = b.direction % 256
      b.x = b.x + SIN[s] * b.speed / 65536
      b.y = b.y - SIN[(s + 64) % 256] * b.speed / 65536
      C.next(b)
    end
  elseif a == 2 then
    C.next(b)
    if C.done(b) then C.delete(b) return end
  end
  local h = C.touch(f, b)
  if h == 9 then -- sub_08017DD4: 4 damage, Link shocked (iframes 90)
    C.hurtLink(f, { tgtDmg = 4, orgIfr = 90, orgKbDur = 8, orgKbSpd = 0 }, b.x, b.y)
    f.player.invuln = 90
  elseif h == 18 then -- CollisionMazaalShrinkRay -> PlayerShrinkByRay
    local p = f.player
    if not p.minish then
      C.fx(f, p.x, p.y + 1, C.FX.BIG_EXPLOSION2)
      p.minish = true
      if p.state ~= "dead" and not p.mazaalFrozen then p.state = "normal" end
      p.animId = -1
      p.carried = nil
    end
  end
end

-- ---------------------------------------------------------------------------
-- the dispatcher hooks (R26.lua)
-- ---------------------------------------------------------------------------
local function mzSetup(pt)
  if pt.mz == "head" then
    C.headInit(pt)
    if pt.type == 0 then pt.hitbox = { x = 0, y = -2, w = 32, h = 10 } end
    if pt.type == 4 then pt.hitbox = { x = 0, y = 0, w = 16, h = 12 } end
  end
end
local oldNew = C.new
function C.new(f, kind, id, type, x, y, mz, noAdd)
  local pt = oldNew(f, kind, id, type, x, y, mz, noAdd)
  mzSetup(pt)
  local sub = C.SETUP[mz]
  if sub then sub(pt) end
  return pt
end
C.SETUP = {}

local M2 = require("src.zelda.tmc.BossMazaal2")
local M3 = require("src.zelda.tmc.BossMazaal3")
M2.install(M, C)
M3.install(M, C)
M.M2, M.M3 = M2, M3

function M.spawnObject(d, e)
  if e.id ~= ID.BOSS_OBJ then return nil end
  local f = d.field
  local pt = C.new(f, 6, ID.BOSS_OBJ, e.form or 0, e.x, e.y, "bossobj", true)
  pt.type2 = e.type2 or 0
  pt.collide = false
  pt.drawOn = false
  pt.layer = e.layer or 1
  return pt
end

function M.spawnEnemy(E, dat, def)
  local f = E.field
  if dat.id == ID.MACRO and f.room and f.room.area == C.AREA_INNER then
    local pt = C.new(f, 3, ID.MACRO, dat.paramA or 0, dat.x, dat.y, "macro", true)
    return pt
  end
  return nil
end

function M.roomInit(f)
  local r = f.room
  if not r then return end
  local T = C.state(f)
  if r.area == C.AREA_FOW and r.room == C.ROOM_BEFORE then
    T.f38, T.f39 = 0, 0x5A -- sub_StateChange_FortressOfWinds_BeforeMazaal
  end
  -- the transition's spawn type: INSTANT_MINISH back out of the head, NORMAL into it
  if T.spawn then
    local p = f.player
    if T.spawn == "minish" then p.minish = true elseif T.spawn == "normal" then p.minish = false end
    if f.save and f.save.status then f.save.status.minish = p.minish or nil end
    p.mazaalHeld, p.mazaalFrozen, p.z = nil, nil, 0
    if p.state == "ext" then p.state, p.extUpdate = "normal", nil end
    T.spawn = nil
  end
end

-- the round-26 dispatcher only needs these; the parts tick through e.impl
function M.handles(e) return e.impl == Impl end
function M.update(E, e) return Impl.update(Impl, e) end

return M
