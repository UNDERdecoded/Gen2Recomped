-- Round 26 (team B): Vaati's Wrath, the final boss (AREA_VAATI_3 $8B room 0),
-- ported from src/enemy/vaatiWrath.c, vaatiWrathEye.c, src/projectile/
-- v3ElectricProjectile.c / v3TennisBallProjectile.c / v3HandProjectile.c,
-- src/object/vaati3Arm.c / vaati3Death.c / vaati3PlayerObject.c /
-- thunderbolt.c (the start's bolt), src/manager/vaati3StartManager.c /
-- vaati3BackgroundManager.c, sub_StateChange_Vaati3_Main (roomInit.c) and the
-- ending's dungeon side (script_Npc4EV3Defeated's natives, the garden's
-- ENDING entity list).  VAATI_ARM ($52) is BossVaati3Arm.lua; VAATI_EYES_MACRO
-- ($25, inside the arms), VAATI3_INSIDE_ARM_MANAGER and ENEMY_4D ($4D, the
-- DHC bridge) are BossVaati3Extra.lua (this module forwards to both).
--
-- THE MODEL.  One boss entity (the controller, kind 3, e.boss, e.impl = W,
-- no sprite) carries the cartridge's VaatiWrathHeapStruct: type0 (the body,
-- W.t0 -- the controller's own fields are mirrored onto it), type1 / type2 /
-- type3 (the overlays), arms[0..1] (BossVaati3Arm), eyes[0..3], object5b
-- (the camera object).  Every visible piece is a "ghost" entity in
-- f.entities (sprite + drawGhost + spritePriority + y), so Field sorts it
-- against Link like an OAM entry; the controller ticks them in the
-- cartridge's order.  Projectiles are tracked objects (extUpdate).
--   gRoomTransition.field_0x38 .. 0x4a (the state that survives the trips
--   into the arms) is V.RT: f38 bit 0 = the intro has run, bit 1 = the Ezlo
--   hint is spent; f39 bits 0/1 = arm 0 / 1 alive, bits 2/3 = its eye (the
--   macro inside) alive; f3a / f3b = the two macros' health; f3c = the arm
--   Link went into; f3d = his seconds in there; f40.. = Vaati's / the
--   arms' positions.  Vaati3StartManager type 0 (the garden) sets it up;
--   entering room $8B:00 without it (a scene) takes the same values.
-- TYPE 0 (VaatiWrathType0Action0..D):
--   0 init: the heap and types 1 / 2 (sub_08041ED4); back from an arm
--     (f38 bit 0): arms per f39, the eyes, action 5/1 (both macros dead) or
--     2, Vaati where he was (f40/f42); else action 1, z -80, the camera on him.
--   1 the intro: waits for the start manager's fade (subAction 1), sinks
--     0.5 px a frame to z -6 (SFX_1A9 every 64 px and at the end), then
--     arm 0 (120 frames), arm 1 (60), the eyes (at timer < $3D), 30 more
--     frames with the camera back on Link and CONTROL_1.
--   2 hover 60 frames (sub_08042004: z by gUnk_080D0EA0, a step every 16
--     frames), then 1-2 moves (sub_08042028: action 3 for gUnk_080D0EA8[r]
--     frames at speed $40 up to $100, -8 a frame in the last 30, turning one
--     step every 4 frames toward sub_0804207C: away from an arm hand within
--     $30 of his chest, else toward Link (y - $28, or the top row); y kept in
--     $40..$90), action 4 (8 frames) between them, then action 5: one arm
--     (Random) in action 2 slams (arm action 4), the other way he moves
--     again.  Actions 3 and 5 run sub_0804212C (Link within the box under an
--     arm: that arm's sweep (action 3) on a coin flip, $2D0 frames apart,
--     else every $3C) and sub_080421AC (phase 1's lightning: when either
--     macro lives, a coin flip every $1E frames after $78: animations 1 /
--     $D / $13, the type1 overlay's frame flag 1 fires V3_ELECTRIC_PROJECTILE
--     type 0 (one bolt at Link), flag 4 -> animation 3; done -> $168 frames).
--   5 waits for the arm (subAction 2): both arms gone (f39 & 3 == 0) ->
--     VAATI3_PLAYER_OBJECT (the camera 40 px over Link), action 6.
--   6 the change: type1 animation $E; flag 1 -> body animation 4; flag 2 ->
--     type 3 (animation $1C), type2 $14; done -> sub_0804235C (action 7).
--   7 back to y $48 at 1 px a frame, 120 frames; 8 drifts (speed $20 up to
--     $200, -$C a frame in the last 30) sideways for gUnk_080D0EAC[r] frames,
--     bouncing at x $20 / $140; 9 60 frames: Link within $40 in x -> A (the
--     eyes serve), else 7.  7 / 8 / 9 run sub_08042214 (phase 2's
--     lightning: 3 in 4 every $1E frames after $B4/$F0: animation 2, type1
--     flag 2 -> V3_ELECTRIC_PROJECTILE type 1 (the ring)).
--   A waits on the eyes: unk_7b $0F (every eye missed) -> 7; $F0 (all four
--     hit) -> B: palette $16B, animation 5, he falls (north at speed $100,
--     zVelocity 1.125, gravity 32/256), lands: 240 frames hitType $38 with 8
--     health -- each time it runs out (Vaati's main: contact + health 0)
--     unk_84 goes down, the third time action D; then 60 frames shaking
--     (gUnk_080D0E64), C: rises to z -4, 120 frames, south to y $48, the
--     overlays' animations $11 / $19 / $1F, type1 flag 1 -> body 9, done ->
--     action 7.
--   D the death (gUnk_080D0E68): once Link can move: type1 / type3 / the
--     camera object / the eyes go, type2 takes gfx $1F5, palette $16B,
--     animation $1A; body animation $A; 120 frames; TEXT_VAATI2 $51; then two
--     VAATI3_DEATH objects, SFX_1C4, 150 frames, the palettes
--     gUnk_080D0E80 every 8 frames from $B8, a white fade at $E6, explosions
--     (FX_GIANT_EXPLOSION4 at gUnk_080D0EA0 offsets every 16, shake 4); body
--     palette $173 animation $B; the fade, 90 frames, ENDING, gone.
--   PreAction (USA): gSave.vaati_timer ($1194 frames) then, Link idle with
--     no item, TEXT_EZLO $70 once (f38 bit 1).
-- TYPES 1 / 2 / 3: the overlays at the body's spot (y +1 / -1 / -1, the
--   sprite offset back), type1's animation $C idling with a random
--   (Random & $78) + $78 hold; type2 animation $12 leans by gUnk_080D0EB0
--   toward Link.
-- EYES (vaatiWrathEye.c): open (animation 0, SFX_166) on the body
--   (gUnk_080D1D70); once both arms are gone fly (speed $80) to
--   gUnk_080D1D98 and bob (gUnk_080D1D78); serve on the body's call: 120 /
--   60 frames, animation 6, flag 1 -> V3_TENNIS_BALL_PROJECTILE 12 px below;
--   the ball back on the eye (sub_080ACB90: same x, at or above it) -> hit
--   (FX_REFLECT2, hidden 60 frames, unk_7b |= $10 << type); 120 frames
--   without -> unk_7b |= 1 << type; back (action 9) -> unk_7b & $F | bit.
-- PROJECTILES: the tennis ball falls south (speed from its definition),
--   SFX_199; the sword (contact 6 / $A / $B / $C / $1A) sends it back north
--   at +$100 (another ball hit by the same swing: its knockback direction),
--   SFX_ITEM_SWORD_CHARGE_FINISH; anything else ends it.  Lightning type 0
--   rides the body (z - $14) until its frame flag 1, then flies at Link
--   (speed $180, a step toward him every 8 frames for 30 frames, z rising 3
--   a frame to -6); type 1 rises 0.5 a frame for 16 frames, then fires
--   gUnk_0812A982[r] type 2 bolts 16 frames apart, the direction from
--   projectileDirections by unk_84 (3 / 2: -n and +3 a shot, speed 352 /
--   480; 1: -n/2, +2, 480).  The hand (arm's fist) flies at Link.
-- SIMPLIFIED: Vaati3BackgroundManager's BG3 (gfx group $4C, scrolling -0.25 /
--   -0.125 px a frame) is not drawn (the room's own layers show); the
--   collision depth of 3D hitboxes is 10 (gUnk_080FD538) else 5, Link's
--   z is his height; FX come from Field:addFx; "PlayerCanBeMoved" is Link
--   not in a text box / transition; TRANSITION_7 is the engine's fade warp;
--   Minish Link has no sword hitbox in this engine (Items.lua), so inside
--   the arms the macro is hit by the engine's E:hit in scenes only.
local bit = require("bit")
local band, bor, bxor, bnot, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.lshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local V = {}
V.__index = V

V.WRATH, V.ARM, V.EYE, V.MACRO, V.E4D = 0x51, 0x52, 0x5F, 0x25, 0x4D
V.P_BALLCHAIN, V.P_HAND, V.P_ELECTRIC, V.P_TENNIS = 0x19, 0x20, 0x21, 0x24
V.O_THUNDER, V.O_ARM, V.O_PLAYER, V.O_DEATH, V.O_MISC = 0x64, 0xAF, 0xB5, 0xB6, 0x6A
V.M_BG, V.M_INSIDE, V.M_START = 0x2F, 0x34, 0x37
V.AREA_ARMS, V.AREA_V3, V.AREA_DHC_OUT, V.AREA_BRIDGE = 0x8A, 0x8B, 0x89, 0x8D
V.FLAG_ENDING, V.FLAG_ZELDA_CHASE = 0x51, 0x1C

local SFX = { S1A9 = 0x1A9, BOSS_HIT = 0x127, BOSS_DIE = 0x128, S1C4 = 0x1C4, S166 = 0x166, S19B = 0x19B, S199 = 0x199,
              S149 = 0x149, S193 = 0x193, CHARGE = 0xD8, GLOVES = 0x119, HIT = 0xFE, EVAPORATE = 0xF6, APPARATE = 0xF7,
              THUNDER = 0xF4 }
V.SFX = SFX
local BGM_VAATI_WRATH = 0x32
local SPECIAL_FX, FX_REFLECT2, FX_GIANT_EXPLOSION4 = 0x0F, 0x1F, 0x51
V.FX = { SPECIAL = SPECIAL_FX, REFLECT2 = FX_REFLECT2, EXPLOSION4 = FX_GIANT_EXPLOSION4, STARS = 0x1C, DEATH = 2 }
local TEXT_EZLO_70, TEXT_V2_4F, TEXT_V2_51 = 0x0B70, 0x164F, 0x1651

-- gSineTable (256 steps a turn, $100 = 1), 320 entries
local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
V.SIN = SIN

-- the small tables written out in vaatiWrath.c / vaatiWrathEye.c / v3*.c
local T_E64 = { [0] = 0, -1, 0, 1 }                                                             -- gUnk_080D0E64
local T_E80 = { [0] = 0x16c, 0x16d, 0x16e, 0x16f, 0x170, 0x171, 0x172, 0x173 }                  -- gUnk_080D0E80
local T_E90 = { [0] = 0, -16, -8, -26, -1, 0, 14, -31, 2, -12, -15, 2, 4, -20, -10, -8 }        -- gUnk_080D0E90
local T_EA0 = { [0] = -4, -5, -6, -7, -6, -5, -4, -3 }                                          -- gUnk_080D0EA0
local T_EA8 = { [0] = 0x78, 0xa0, 0xc8, 0xf0 }                                                  -- gUnk_080D0EA8
local T_EAC = { [0] = 0x3c, 0x50, 0x64, 0x78 }                                                  -- gUnk_080D0EAC
local T_EB0 = { [0] = 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 1, 1, 0, 0, 0, -1, -1, -2, -2, -3, -3, -3, -3, -3, -3, -3, -3, -3, -3 } -- gUnk_080D0EB0
local EYE_A = { [0] = -18, 1, -6, 4, 6, 4, 19, 1 }                                              -- gUnk_080D1D70
local EYE_Z = { [0] = -3, -4, -5, -6, -7, -6, -5, -4, -4, -3, -4, -5, -6, -7, -6, -5, -5, -4, -3, -4, -5, -6, -7, -6,
                -6, -5, -4, -3, -4, -5, -6, -7 }                                                -- gUnk_080D1D78
local EYE_B = { [0] = -24, 4, -8, 8, 8, 8, 24, 4 }                                              -- gUnk_080D1D98
local EL_SPEED = { [0] = 352, 480, 480 }                                                        -- projectileSpeeds
local EL_COUNT = { [0] = 5, 6, 7, 8, 5, 6, 7, 6 }                                               -- gUnk_0812A982
local EL_DIR = { [0] = 6, 9, 9, 12, 6, 9, 9, 9, 0, 0 }                                         -- projectileDirections
V.T = { E64 = T_E64, E80 = T_E80, E90 = T_E90, EA0 = T_EA0, EA8 = T_EA8, EAC = T_EAC, EB0 = T_EB0, EYE_A = EYE_A,
        EYE_Z = EYE_Z, EYE_B = EYE_B, EL_SPEED = EL_SPEED, EL_COUNT = EL_COUNT, EL_DIR = EL_DIR }

local function s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end
local function s16(v) v = band(v, 0xFFFF) if v >= 0x8000 then return v - 0x10000 end return v end
V.s8, V.s16 = s8, s16

-- ---------------------------------------------------------------------------
-- gRoomTransition's Vaati fields
-- ---------------------------------------------------------------------------
V.RT = nil
-- Vaati3StartManager_Type0_Init's values
function V.rtInit(f)
  V.RT = { f38 = 0, f39 = 0x0F, f3a = 0x20, f3b = 0x20, f3c = 0, f3d = 0, f40 = 0, f42 = 0, f44 = 0, f46 = 0, f48 = 0, f4a = 0 }
  if f and f.save then f.save.vaatiTimer = 0x1194 end -- gSave.vaati_timer
  return V.RT
end
function V.rt(f) return V.RT or V.rtInit(f) end

-- ---------------------------------------------------------------------------
-- math / movement helpers
-- ---------------------------------------------------------------------------
-- CalculateDirectionTo (0..31, 0 north clockwise)
local function dirTo(ax, ay, bx, by)
  local a = math.atan2(bx - ax, -(by - ay))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
V.dirTo = dirTo
local function hx(v) return math.floor(v) end -- x.HALF.HI
V.hx = hx
-- sub_08004596: one step toward
local function turnTo(e, want)
  local d = band(want - e.direction, 0x1F)
  if d ~= 0 then
    if d > 0x10 then e.direction = band(e.direction - 1, 0x1F) else e.direction = band(e.direction + 1, 0x1F) end
  end
end
V.turnTo = turnTo
-- LinearMoveUpdate (speed $100 = 1 px a frame); DIR_NONE ($FF) stays
local function linear(e, speed, dir)
  dir = dir or e.direction
  if dir == nil or band(dir, 0x80) ~= 0 then return end
  local a = (dir % 32) / 32 * 2 * math.pi
  local s = (speed or e.speed or 0) / 256
  e.x, e.y = e.x + math.sin(a) * s, e.y - math.cos(a) * s
end
V.linear = linear
-- EntityWithinDistance
local function within(e, x, y, d)
  local dx, dy = hx(e.x) - hx(x), hx(e.y) - hx(y)
  return d * d >= dx * dx + dy * dy
end
V.within = within
-- GravityUpdate (z negative = up; zVelocity positive = up, both px)
local function gravity(e, g)
  e.z = e.z - e.zv
  if e.z < 0 then e.zv = e.zv - g return e.z end
  e.z, e.zv = 0, 0
  return 0
end
V.gravity = gravity
-- sub_0806FA90 / PositionRelative: position, z, sprite offsets
local function relate(src, dst, ox, oy)
  dst.spriteOX, dst.spriteOY = src.spriteOX or 0, src.spriteOY or 0
  dst.x, dst.y, dst.z = src.x + (ox or 0), src.y + (oy or 0), src.z or 0
end
V.relate = relate
local function copyPos(src, dst) dst.x, dst.y, dst.z = src.x, src.y, src.z or 0 end
V.copyPos = copyPos

-- the Field's room box and its walls
function V:solid(x, y) local r = self.field.room return r and r.isSolid and r:isSolid(x, y, 1) end

function V.new(field, enemies)
  return setmetatable({ field = field, en = enemies, A = field.assets }, V)
end
function V:rand() local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(self.field)) end
function V:sfx(id) self.field:sound(id) end
function V:fx(x, y, kind) self.field:addFx(x, y, SPECIAL_FX, kind) end

-- ---------------------------------------------------------------------------
-- parts ("ghost" entities drawn by Field, ticked by the controller)
-- ---------------------------------------------------------------------------
function V:palette(id) return self.A:objPalette(id, self.field.room.atlas and self.field.room.atlas.palettes) end

-- spec: def (enemy / object / projectile definition), gfxKind ("enemy" or the
-- object's gfxType), and any fields
function V:part(def, gfxKind, t)
  local f = self.field
  t = t or {}
  def = def or {}
  t.kind, t.id = t.kind or 0x7F, t.id or -1
  t.v3part = true
  t.x, t.y, t.z, t.zv = t.x or 0, t.y or 0, t.z or 0, t.zv or 0
  t.spriteOX, t.spriteOY = t.spriteOX or 0, t.spriteOY or 0
  t.sprite = def.sprite
  t.gfx = Assets.gfxSource(gfxKind or "enemy", def.gfx or 0)
  t.palId = def.palette or 0
  t.palette = self:palette(t.palId)
  t.anim = Anim.new()
  t.cleared = 0
  t.drawOn = t.drawOn ~= false
  t.spritePriority = t.spritePriority or 4
  t.layer = 1
  t.action, t.subAction, t.timer, t.subtimer = t.action or 0, t.subAction or 0, t.timer or 0, t.subtimer or 0
  t.iframes, t.health = 0, t.health or def.health or 0xFF
  t.hitType = t.hitType or def.damageType or 0
  t.hitbox = t.hitbox or def.hitbox or { x = 0, y = 0, w = 6, h = 6 }
  t.depth = t.depth or 5
  t.direction, t.speed = t.direction or 0, t.speed or def.speed or 0
  t.literalAnim, t.field82, t.interactType = true, 0, 0
  t.objAnim = t.objAnim or 0
  local me = self
  t.drawGhost = function(p, _, camX, camY) me:drawPart(p, camX, camY) end
  t.hidden = not t.drawOn
  f.entities[#f.entities + 1] = t
  return t
end
function V:setPal(pt, id) if pt.palId ~= id then pt.palId = id; pt.palette = self:palette(id) end end
function V:setGfx(pt, gfxKind, gfx) pt.gfx = Assets.gfxSource(gfxKind or "enemy", gfx) end
-- InitializeAnimation / InitAnimationForceUpdate
function V:anim(pt, idx)
  pt.animIndex = idx
  pt.objAnim = idx -- (Field's literalAnim pass keeps a ghost on objAnim)
  pt.cleared = 0
  pt.frameIndex = nil
  if pt.sprite then pt.anim:set(self.A:sprite(pt.sprite), idx, true) end
end
-- GetNextFrame / UpdateAnimationSingleFrame: one frame; a new keyframe
-- brings its flags back (the cleared bits are per keyframe)
function V.step(pt)
  local a = pt.anim
  if not a.keys then return end
  local k0, t0 = a.key, a.timer
  a:update(1)
  if a.key ~= k0 or a.timer ~= t0 - 1 then pt.cleared = 0 end
end
-- the entity's frame byte (keyframe flags minus what the code cleared)
function V.frame(pt) return band(pt.anim.flags or 0, bnot(pt.cleared or 0)) end
function V.clear(pt, m) pt.cleared = bor(pt.cleared or 0, m) end
function V.done(pt) return band(V.frame(pt), 0x80) ~= 0 end
function V:show(pt, on) pt.drawOn = on and true or false; pt.hidden = not pt.drawOn or pt.deleted end
function V:kill(pt) if pt then pt.deleted = true; pt.collide = false; pt.hidden = true end end
local function alive(pt) return pt ~= nil and not pt.deleted end
V.alive = alive

function V:drawPart(pt, camX, camY)
  if pt.deleted or not pt.drawOn then return end
  if pt.iframes and pt.iframes > 0 and pt.iframes % 4 < 2 and pt.blink then return end
  local frame = pt.frameIndex or pt.anim.frame
  if not pt.sprite or not frame or frame == 0xFF then return end
  local img, ox, oy = self.A:spriteFrame(pt.sprite, frame, pt.palette, "v3" .. pt.sprite .. ":" .. tostring(pt.palId), pt.gfx)
  if not img then return end
  local x = math.floor(pt.x - camX + (pt.spriteOX or 0))
  local y = math.floor(pt.y - camY + (pt.z or 0) + (pt.spriteOY or 0))
  local hf = (pt.frameIndex == nil and pt.anim:hflip() or false) ~= (pt.flipX or false)
  if hf then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
end

-- ---------------------------------------------------------------------------
-- collisions with Link
-- ---------------------------------------------------------------------------
-- the hitboxes overlap (IsColliding: x / y half sizes, z within the depths)
function V.overlap(a, b)
  local ha, hb = a.hitbox or { x = 0, y = 0, w = 4, h = 4 }, b.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  local sw = (ha.w or 4) + (hb.w or 4)
  if math.abs((hx(a.x) + (ha.x or 0)) - (hx(b.x) + (hb.x or 0))) > sw then return false end
  local sh = (ha.h or 4) + (hb.h or 4)
  if math.abs((hx(a.y) + (ha.y or 0)) - (hx(b.y) + (hb.y or 0))) > sh then return false end
  local d = (a.depth or 5) + (b.depth or 5)
  return math.abs(hx(a.z or 0) - hx(b.z or 0)) <= d
end
-- Link as a collision box (z: the cartridge's sign)
function V:linkBox()
  local p = self.field.player
  local HBm = require("src.zelda.tmc.Hitboxes")
  local hb = HBm.player(self.field, p) or (p.minish and { x = 0, y = -1, w = 2, h = 2 } or { x = 0, y = -3, w = 6, h = 6 })
  return { x = p.x, y = p.y, z = -(p.z or 0), hitbox = hb, depth = 5 }
end
function V:playerCanBeMoved()
  local f = self.field
  local p = f.player
  return p.state ~= "dead" and not f.textbox and not f.transition
end
-- a part touching Link: the matrix (hitType vs Link's hurtType) damages and
-- knocks him back; returns true when they touched
function V:touchLink(pt)
  local f = self.field
  local p = f.player
  if p.state == "dead" or p.invuln > 0 or not self:playerCanBeMoved() then return false end
  if not V.overlap(pt, self:linkBox()) then return false end
  local HBm = require("src.zelda.tmc.Hitboxes")
  local hurt = HBm.hurtType(p)
  if self.en.mtx ~= "" then
    local h = HBm.handler(self.en.mtx, pt.hitType or 0, hurt)
    if h == 1 or h == 2 then return false end
  end
  local s = self.en:settings(pt.hitType or 0, hurt) or { tgtDmg = 2, orgIfr = 30, orgKbDur = 8, orgKbSpd = 24 }
  if pt.onTouch then pt.onTouch(pt, 0x80 + hurt) end
  if (s.tgtDmg or 0) > 0 or (s.orgKbDur or 0) > 0 then
    if p:hurt(math.max(s.tgtDmg or 0, 1), pt.x, pt.y) then
      p.invuln = math.max(s.orgIfr or 30, 30)
      p.timer = math.max(s.orgKbDur or 8, 4)
      local ks = ((s.orgKbSpd or 24) * 16) / 256
      local dx, dy = p.x - pt.x, p.y - pt.y
      local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.kbx, p.kby = dx / dd * ks, dy / dd * ks
    end
  end
  return true
end
-- the sword on a part: the matrix's damage (hurtType 4); contactFlags
function V:swordOn(pt, box)
  if not pt.collide or pt.deleted or (pt.iframes or 0) > 0 then return false end
  local b = { x = box.x, y = box.y, z = -(self.field.player.z or 0), hitbox = { x = 0, y = 0, w = box.w, h = box.h }, depth = 5 }
  if not V.overlap(pt, b) then return false end
  local s = self.en:settings(pt.hitType or 0, 4)
  pt.contact = 0x80 + 4
  pt.contactBox = box
  if pt.onSword then return pt.onSword(pt, box, s) end
  local dmg = s and s.orgDmg or 0
  if dmg > 0 then
    pt.health = math.max(0, (pt.health or 0) - dmg)
    pt.iframes = (s.tgtIfr and s.tgtIfr > 0) and s.tgtIfr or 12
    self:sfx(SFX.HIT)
  else
    self:sfx(0x118) -- SFX_ITEM_SHIELD_BOUNCE (no damage)
    pt.iframes = 8
  end
  return true
end
-- the Cane of Pacci's bolt (contact $1D) on any collidable part in `list`
function V:boltCheck(list)
  local f = self.field
  for _, o in ipairs(f.entities) do
    if o.bolt and not o.deleted and o.action == 1 and (o.life or 0) >= 0 then
      local b = { x = o.x, y = o.y, z = 0, hitbox = { x = 0, y = 0, w = 4, h = 4 }, depth = 5 }
      for _, pt in ipairs(list) do
        if alive(pt) and pt.collide and V.overlap(pt, b) then
          pt.contact = 0x80 + 0x1D
          o.life = -1 -- used up (Pacci.updateBolt ends it)
          break
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- definitions
-- ---------------------------------------------------------------------------
function V:edef(id, form) return self.en:def(id, form) or {} end
function V:pdef(id)
  local d = self.A.manifest.projectileDefs and self.A.manifest.projectileDefs[id]
  if d and d.multi then d = d.forms[0] end
  return d or {}
end
function V:odef(id, t) return self.field:objects():def(id, t) or {} end

-- ---------------------------------------------------------------------------
-- type 0 and its heap
-- ---------------------------------------------------------------------------
function V:spawnWrath(x, y)
  local f = self.field
  local def = self:edef(V.WRATH, 0)
  local e = { kind = 3, id = V.WRATH, form = 0, x = x, y = y, z = 0, boss = true, enemy = true, impl = self, mask = true,
              health = 0xFF, hitType = def.damageType or 0x39, hitbox = { x = 0, y = 0, w = 1, h = 1 }, def = def,
              anim = Anim.new(), literalAnim = true, field82 = 0, interactType = 0, iframes = 0, layer = 1, vaati3 = true }
  local t0 = self:part(def, "enemy", { x = x, y = y, type = 0, spritePriority = 4, drawOn = false, health = 0xFF,
                                       collide = (def.collision or 1) ~= 0, blink = true })
  t0.unk78, t0.unk79, t0.unk7b, t0.unk7c, t0.unk7e, t0.unk84 = 0, 0, 0, 0, 0, 0
  t0.hitbox = def.hitbox or { x = 0, y = -20, w = 16, h = 16 }
  e.t0 = t0
  e.heap = { arms = {}, eyes = {} }
  t0.heap = e.heap
  t0.ctl = e
  self.e = e
  return e
end

-- sub_08041ED4: the heap with types 1 and 2
function V:makeHeap(e)
  local h = e.heap
  h.t0 = e.t0
  h.t3, h.arms[0], h.arms[1] = nil, nil, nil
  h.t1 = self:part(self:edef(V.WRATH, 1), "enemy", { type = 1, spritePriority = 4 })
  h.t2 = self:part(self:edef(V.WRATH, 2), "enemy", { type = 2, spritePriority = 4 })
  return true
end
-- sub_08041F1C: the four eyes
function V:makeEyes(e)
  local def = self:edef(V.EYE, 0)
  for i = 0, 3 do
    local ey = self:part(def, "enemy", { type = i, parent = e.t0, spritePriority = 4, collide = false })
    ey.hitbox = def.hitbox or { x = 0, y = 0, w = 4, h = 4 }
    e.heap.eyes[i] = ey
  end
  return true
end
-- sub_08041F74: arm `k` when f39 bit k is set
function V:makeArm(e, k)
  local RT = V.rt(self.field)
  local arm
  if band(rshift(RT.f39, k), 1) ~= 0 then
    arm = require("src.zelda.tmc.BossVaati3Arm").create(self, e, k)
  end
  e.heap.arms[k] = arm
  return true
end

-- sub_08042004: the hover
function V:hover(t0)
  t0.unk78 = band(t0.unk78 + 1, 0xFF)
  t0.z = T_EA0[band(rshift(t0.unk78, 4), 7)]
end
-- sub_08042028
function V:move(t0)
  t0.action = 3
  t0.timer = T_EA8[band(self:rand(), 3)]
  t0.speed = 0x40
  t0.direction = self:moveDir(t0)
end
-- sub_08042050
function V:drift(t0)
  t0.action = 8
  local r = self:rand()
  t0.timer = T_EAC[band(r, 3)]
  t0.speed = 0x20
  t0.direction = band(rshift(r, 8), 0x10) + 8
end
-- sub_0804207C
function V:moveDir(t0)
  local p = self.field.player
  local x, y = hx(t0.x), hx(t0.y) - 0x10
  local h = t0.heap
  for k = 0, 1 do
    local arm = h.arms[k]
    if arm and alive(arm.e0) and arm.e0.action >= 5 and within(arm.e0, x, y, 0x30) then
      return dirTo(hx(arm.e0.x), hx(arm.e0.y), x, y)
    end
  end
  local ty = (p.y < 0x40) and 0x18 or (hx(p.y) - 0x28)
  return dirTo(hx(t0.x), hx(t0.y), hx(p.x), ty)
end
-- sub_0804212C: an arm's sweep when Link is under it
function V:armTrigger(t0)
  if t0.unk7c ~= 0 then t0.unk7c = t0.unk7c - 1 return end
  local p = self.field.player
  local arm
  local y = hx(t0.y) - 0x44
  if band(hx(p.y) - y, 0xFFFFFFFF) < 0x61 then
    local x = hx(t0.x) - 0x38
    if band(hx(p.x) - x, 0xFFFFFFFF) < 0x39 then arm = t0.heap.arms[1]
    elseif band(hx(p.x) - hx(t0.x), 0xFFFFFFFF) < 0x39 then arm = t0.heap.arms[0] end
  end
  if arm then
    if arm.e0.action ~= 2 then return end
    if band(self:rand(), 1) == 0 then return end
    arm.e0.action, arm.e0.subAction = 3, 0
    t0.unk7c = 0x2D0
  else
    t0.unk7c = 0x3C
  end
end
-- sub_080421AC: phase 1's lightning
function V:zap1(t0)
  local RT = V.rt(self.field)
  if t0.unk7e ~= 0 then t0.unk7e = t0.unk7e - 1 return end
  if t0.unk79 == 0 then
    if band(self:rand(), 1) ~= 0 and band(RT.f39, 0xC) ~= 0 then
      self:charge(t0, false)
      t0.unk79 = 1
      return
    end
    t0.unk7e = 0x1E
    return
  end
  if not self:zapFire(t0, 0) then return end
  t0.unk79 = 0
  t0.unk7e = 0x168
end
-- sub_08042214: phase 2's
function V:zap2(t0)
  if t0.unk7e ~= 0 then t0.unk7e = t0.unk7e - 1 return end
  if t0.unk79 == 0 then
    if band(self:rand(), 3) ~= 0 then
      self:charge(t0, true)
      t0.unk79 = 1
      return
    end
    t0.unk7e = 0x1E
  else
    if not self:zapFire(t0, 1) then return end
    t0.unk79 = 0
    t0.unk7e = 0xB4
  end
end
-- sub_08042264 / sub_0804228C
function V:charge(t0, two)
  local h = t0.heap
  self:anim(t0, two and 2 or 1)
  h.t1.subAction = 1
  self:anim(h.t1, 0xD)
  self:anim(h.t2, 0x13)
  if two and h.t3 then self:anim(h.t3, 0x1D) end
end
-- sub_080422C0
function V:zapFire(t0, k)
  local h = t0.heap
  V.step(t0)
  V.step(h.t2)
  local t1 = h.t1
  V.step(t1)
  local fr = V.frame(t1)
  if k + 1 == fr then
    self:electric(k, t0)
    V.clear(t1, fr)
  elseif fr == 4 then
    V.clear(t1, 4)
    self:anim(t0, 3)
  elseif band(fr, 0x80) ~= 0 then
    self:anim(t0, 0)
    t1.subAction = 0
    self:anim(t1, 0xC)
    self:anim(h.t2, 0x12)
    if k == 1 and h.t3 then self:anim(h.t3, 0x1B) end
    return true
  end
  return false
end
-- sub_0804235C
function V:toPhase2(t0)
  local h = t0.heap
  t0.action, t0.timer = 7, 120
  t0.unk79, t0.unk7e = 0, 0xF0
  self:anim(t0, 0)
  h.t1.subAction = 0
  self:anim(h.t1, 0xC)
  self:anim(h.t2, 0x12)
  if h.t3 then self:anim(h.t3, 0x1B) end
end
-- sub_08041E78
function V:explode(t0)
  if band(t0.subtimer, 0xF) == 0 then
    local i = band(rshift(t0.subtimer, 3), 0xE)
    self:fx(t0.x + T_E90[i], t0.y + T_E90[i + 1], FX_GIANT_EXPLOSION4)
    self.field:shake(4, 0)
  end
end

-- VaatiWrathType0PreAction (USA): the Ezlo hint
function V:preAction(t0)
  local f = self.field
  local RT = V.rt(f)
  if band(RT.f38, 2) ~= 0 then return end
  local st = f.save
  if (st.vaatiTimer or 0) ~= 0 then st.vaatiTimer = st.vaatiTimer - 1 return end
  local p = f.player
  if (p.state == "normal" or p.state == nil) and not p.item and not f.textbox and (p.z or 0) <= 0 then
    f:message(TEXT_EZLO_70, nil)
    RT.f38 = bor(RT.f38, 2)
  end
end

-- the actions
function V:type0(e)
  local f = self.field
  local t0 = e.t0
  local h = e.heap
  local p = f.player
  local RT = V.rt(f)
  local a = t0.action
  if a ~= 0 then self:preAction(t0) end
  if a == 0 then
    if band(RT.f38, 1) ~= 0 then
      self:makeHeap(e); self:makeArm(e, 0); self:makeArm(e, 1); self:makeEyes(e)
      if band(RT.f39, 0xC) == 0 then t0.action, t0.subAction = 5, 1
      else t0.action, t0.timer = 2, 60 end
      t0.x, t0.y = RT.f40, RT.f42
      self:hover(t0)
    else
      self:makeHeap(e)
      t0.action, t0.subAction, t0.timer = 1, 0, 120
      t0.z = -80
      e.camOn = t0
    end
    self:show(t0, true)
    t0.unk79, t0.unk7c, t0.unk7e, t0.unk84 = 0, 0x3C, 0x78, 3
    self:anim(t0, 0)
  elseif a == 1 then
    V.step(t0)
    local sa = t0.subAction
    if sa == 1 then
      t0.z = t0.z + 0.5
      if band(hx(t0.z), 0x3F) == 0 then self:sfx(SFX.S1A9) end
      if hx(t0.z) > -6 then t0.subAction = 2; self:sfx(SFX.S1A9) end
    elseif sa == 2 then
      self:hover(t0)
      if t0.timer ~= 0 then t0.timer = t0.timer - 1
      elseif self:makeArm(e, 0) then t0.subAction, t0.timer = 3, 60 end
    elseif sa == 3 then
      self:hover(t0)
      if t0.timer ~= 0 then t0.timer = t0.timer - 1
      elseif self:makeArm(e, 1) then t0.subAction, t0.timer, t0.subtimer = 4, 120, 0 end
    elseif sa == 4 then
      self:hover(t0)
      t0.timer = t0.timer - 1
      if t0.timer == 0 then t0.subAction = 5
      elseif t0.timer < 0x3D and t0.subtimer == 0 then
        if self:makeEyes(e) then t0.subtimer = 1 end
      end
    elseif sa == 5 then
      self:hover(t0)
      t0.subAction, t0.timer = 6, 30
      RT.f38 = bor(RT.f38, 1)
      e.camOn = nil
      self:control(true)
    elseif sa >= 6 then
      self:hover(t0)
      t0.timer = t0.timer - 1
      if t0.timer == 0 then t0.action, t0.timer = 2, 60 end
    end
  elseif a == 2 then
    self:hover(t0)
    V.step(t0)
    t0.timer = t0.timer - 1
    if t0.timer == 0 then
      t0.subtimer = band(self:rand(), 1) + 1
      self:move(t0)
    end
  elseif a == 3 then
    self:hover(t0)
    V.step(t0)
    linear(t0) -- ProcessMovement0 (he floats over the arena; its walls are outside the clamp)
    if t0.y > 0x90 then t0.y = 0x90 elseif t0.y < 0x40 then t0.y = 0x40 end
    t0.timer = t0.timer - 1
    if t0.timer == 0 then t0.action, t0.timer = 4, 8
    else
      if t0.timer < 0x1E then t0.speed = t0.speed - 8
      elseif t0.speed < 0x100 then t0.speed = t0.speed + 6 end
      if band(t0.timer, 3) == 0 then turnTo(t0, self:moveDir(t0)) end
    end
    self:armTrigger(t0)
    self:zap1(t0)
  elseif a == 4 then
    self:hover(t0)
    V.step(t0)
    t0.timer = t0.timer - 1
    if t0.timer == 0 then
      t0.subtimer = t0.subtimer - 1
      if t0.subtimer == 0 then t0.action, t0.subAction = 5, 0 else self:move(t0) end
    end
  elseif a == 5 then
    self:hover(t0)
    V.step(t0)
    self:armTrigger(t0)
    self:zap1(t0)
    if t0.subAction == 0 then
      t0.subAction = 1
      local arm
      if band(self:rand(), 1) ~= 0 then arm = h.arms[0] or h.arms[1] else arm = h.arms[1] or h.arms[0] end
      if arm and arm.e0.action == 2 then
        arm.e0.action, arm.e0.subAction = 4, 0
      else
        t0.subtimer = band(self:rand(), 1) + 1
        self:move(t0)
      end
    elseif t0.unk79 == 0 and t0.subAction == 2 then
      if band(RT.f39, 3) == 0 then
        local o = self:playerObject(t0)
        h.obj5b = o
        e.camOn = o
        t0.action, t0.timer = 6, 30
        h.t1.subAction = 1
        self:anim(h.t1, 0xE)
      else
        t0.action, t0.timer = 2, 60
      end
    end
  elseif a == 6 then
    if t0.timer == 0 then
      local t1 = h.t1
      V.step(t1)
      local fr = V.frame(t1)
      if fr == 1 then
        V.clear(t1, 1)
        self:anim(t0, 4)
      elseif fr == 2 then
        local t3 = self:part(self:edef(V.WRATH, 3), "enemy", { type = 3, spritePriority = 4 })
        h.t3 = t3
        self:anim(h.t2, 0x14)
        V.clear(t1, 2)
      elseif band(fr, 0x80) ~= 0 then
        self:toPhase2(t0)
      end
    else
      t0.timer = t0.timer - 1
    end
    self:hover(t0)
    V.step(t0)
  elseif a == 7 then
    self:zap2(t0)
    self:hover(t0)
    V.step(t0)
    if hx(t0.y) ~= 0x48 then
      t0.speed = 0x100
      t0.direction = (0x48 >= hx(t0.y)) and 0x10 or 0
      linear(t0)
    else
      t0.timer = t0.timer - 1
      if t0.timer == 0 then self:drift(t0) end
    end
  elseif a == 8 then
    self:hover(t0)
    V.step(t0)
    linear(t0)
    if (0x20 > hx(t0.x) or 0x140 < hx(t0.x)) and 0x3F < t0.speed then t0.direction = bxor(t0.direction, 0x10) end
    t0.timer = t0.timer - 1
    if t0.timer == 0 then t0.action, t0.timer = 9, 60
    elseif t0.timer < 0x1E then t0.speed = t0.speed - 0xC
    elseif 0x1FF >= t0.speed then t0.speed = t0.speed + 0x10 end
    self:zap2(t0)
  elseif a == 9 then
    self:hover(t0)
    V.step(t0)
    if t0.unk79 ~= 0 then self:zap2(t0)
    else
      t0.timer = t0.timer - 1
      if t0.timer == 0 then
        if band(hx(p.x) - hx(t0.x) + 0x40, 0xFFFFFFFF) < 0x81 then
          t0.action, t0.unk7b = 10, 0
          for i = 0, 3 do if h.eyes[i] then h.eyes[i].timer = 1 end end
        else
          t0.action, t0.timer, t0.unk79 = 7, 30, 0
        end
      end
    end
  elseif a == 10 then
    self:hover(t0)
    V.step(t0)
    if t0.unk7b == 0x0F then
      t0.action, t0.timer, t0.unk79 = 7, 120, 0
    elseif t0.unk7b == 0xF0 then
      t0.action, t0.subAction = 0xB, 0
      t0.direction, t0.speed, t0.zv = 0, 0x100, 1.125
      self:setPal(t0, 0x16B)
      self:anim(t0, 5)
      h.t1.subAction = 1
      self:anim(h.t1, 0xF)
      self:anim(h.t2, 0x15)
      if h.t3 then self:anim(h.t3, 0x1E) end
      self:sfx(SFX.BOSS_HIT)
    end
  elseif a == 0xB then
    local sa = t0.subAction
    if sa == 0 then
      linear(t0)
      V.step(t0); V.step(h.t1); V.step(h.t2)
      if gravity(t0, 32 / 256) == 0 then
        t0.subAction, t0.timer = 1, 240
        t0.health, t0.hitType = 8, 0x38
        f:shake(20, 0)
        self:anim(t0, 6)
        self:anim(h.t2, 0x16)
      end
    elseif sa == 1 then
      V.step(t0); V.step(h.t2)
      t0.timer = t0.timer - 1
      if t0.timer == 0 then t0.subAction, t0.timer, t0.hitType, t0.health = 2, 60, 0x39, 0xFF end
    else
      t0.timer = t0.timer - 1
      t0.spriteOX = T_E64[band(t0.timer, 3)]
      if t0.timer == 0 then
        t0.action, t0.subAction = 0xC, 0
        self:setPal(t0, 0x140)
        self:anim(t0, 8)
        self:anim(h.t1, 0x10)
        self:anim(h.t2, 0x18)
      end
    end
  elseif a == 0xC then
    V.step(t0); V.step(h.t2)
    if t0.subAction ~= 0 then V.step(h.t1) end
    local sa = t0.subAction
    if sa == 0 then
      t0.z = t0.z - 0.5
      if hx(t0.z) < -4 then t0.subAction, t0.timer, t0.direction, t0.speed = 1, 120, 0x10, 0x80 end
    elseif sa == 1 then
      self:hover(t0)
      if t0.timer ~= 0 then t0.timer = t0.timer - 1
      else
        linear(t0)
        if hx(t0.y) == 0x48 then
          t0.subAction = 2
          self:anim(h.t1, 0x11)
          self:anim(h.t2, 0x19)
          if h.t3 then self:anim(h.t3, 0x1F) end
        end
      end
    else
      self:hover(t0)
      local t1 = h.t1
      local fr = V.frame(t1)
      if band(fr, 1) ~= 0 then V.clear(t1, 1); self:anim(t0, 9)
      elseif band(fr, 0x80) ~= 0 then self:toPhase2(t0) end
    end
  elseif a == 0xD then
    self:death(e)
  end
end

-- gUnk_080D0E68: the death
function V:death(e)
  local f = self.field
  local t0, h = e.t0, e.heap
  local sa = t0.subAction
  if sa == 0 then -- sub_08041BE8
    if not self:playerCanBeMoved() then return end
    t0.subAction, t0.timer = 1, 120
    self:anim(t0, 10)
    self:kill(h.t1); h.t1 = nil
    local t2 = h.t2
    self:setGfx(t2, "enemy", 0x1F5) -- LoadFixedGFX(0x1f5)
    self:setPal(t2, 0x16B)
    self:anim(t2, 0x1A)
    self:kill(h.t3); h.t3 = nil
    self:kill(h.obj5b); h.obj5b = nil
    e.camOn = nil
    for i = 0, 3 do self:kill(h.eyes[i]); h.eyes[i] = nil end
    self:control(false) -- SetPlayerControl(2)
  elseif sa == 1 then -- sub_08041CD0
    V.step(h.t2)
    if V.done(t0) then
      if t0.timer ~= 0 then t0.timer = t0.timer - 1
      else t0.subAction, t0.timer = 2, 60; f:message(TEXT_V2_51, t0) end
    else V.step(t0) end
  elseif sa == 2 then -- sub_08041D14
    V.step(h.t2)
    if not f.textbox then
      if t0.timer ~= 0 then t0.timer = t0.timer - 1
      else
        local d0 = self:deathObj(t0, 0)
        t0.child = d0
        self:deathObj(t0, 1)
        t0.subAction, t0.timer, t0.subtimer = 3, 150, 0
        self:show(t0, false)
        self:sfx(SFX.S1C4)
      end
    end
  elseif sa == 3 then -- sub_08041D84
    V.step(h.t2)
    if t0.timer ~= 0 then t0.timer = t0.timer - 1
    else
      if t0.subtimer < 0xF0 then
        if 0xB7 < t0.subtimer and band(t0.subtimer, 7) == 0 then
          local pal = T_E80[rshift(t0.subtimer - 0xB8, 3)]
          self:setPal(h.t2, pal)
          if t0.child then self:setPal(t0.child, pal) end
        end
        if t0.subtimer == 0xE6 then f:fade("out", true, 4) end
      else
        t0.subAction = 4
        self:show(t0, true)
        self:setPal(t0, 0x173)
        self:anim(t0, 0xB)
      end
      t0.subtimer = t0.subtimer + 1
      self:explode(t0)
    end
  elseif sa == 4 then -- sub_08041E20
    t0.subtimer = t0.subtimer + 1
    self:explode(t0)
    V.step(h.t2)
    if not f:fadeActive() then t0.subAction, t0.timer = 5, 90; f.fadeStep = (f.fadeSpeed or 16) / 256 end
  elseif sa == 5 then -- sub_08041E50
    t0.timer = t0.timer - 1
    if t0.timer == 0 then
      f:setFlag("global", V.FLAG_ENDING, true)
      self:kill(h.t2); h.t2 = nil
      self:kill(t0)
      e.dead = true
      e.deleted = true
    end
  end
end

-- SetPlayerControl: false = CONTROL_DISABLED (PausePlayer), true = back
function V:control(on)
  local p = self.field.player
  if on then
    if p.state == "ext" and p.v3lock then p.state, p.extUpdate, p.animId = "normal", nil, -1 end
    p.v3lock = nil
  else
    p.state, p.extUpdate = "ext", function() end
    p.v3lock = true
  end
end

-- VaatiWrathType1 / 2 / 3
function V:overlay(e, pt)
  local t0 = e.t0
  if pt.type == 1 then
    if pt.action == 0 then pt.action, pt.subAction = 1, 0; self:anim(pt, 0xC) end
    if pt.subAction == 0 then V.step(pt) end
    if pt.animIndex == 0xC and pt.anim.timer >= 0x80 then -- (animIndex | frameDuration bit 7)
      self:anim(pt, 0xC)
      pt.anim.timer = band(self:rand(), 0x78) + 0x78
    end
    relate(t0, pt, 0, 1)
    pt.spriteOY = pt.spriteOY - 1
  elseif pt.type == 2 then
    if pt.action == 0 then pt.action = 1; self:anim(pt, 0x12) end
    relate(t0, pt, 0, -1)
    pt.spriteOY = pt.spriteOY + 1
    if pt.animIndex == 0x12 then
      local p = self.field.player
      pt.x = pt.x + T_EB0[dirTo(hx(pt.x), hx(pt.y), hx(p.x), hx(p.y))]
    end
  else
    if pt.action == 0 then pt.action = 1; self:anim(pt, 0x1C) end
    relate(t0, pt, 0, -1)
    pt.spriteOY = pt.spriteOY + 1
    V.step(pt)
  end
  pt.hidden = not pt.drawOn
end

-- ---------------------------------------------------------------------------
-- the eyes (vaatiWrathEye.c)
-- ---------------------------------------------------------------------------
local function eyeA(self, ey) relate(ey.parent, ey, EYE_A[ey.type * 2], EYE_A[ey.type * 2 + 1]) end -- sub_080485D8
local function eyeB(self, ey) -- sub_080485FC
  relate(ey.parent, ey, EYE_B[ey.type * 2], EYE_B[ey.type * 2 + 1])
  ey.z = EYE_Z[ey.type * 8 + band(rshift(ey.parent.unk78, 4), 7)]
end
function V:eye(e, ey)
  local RT = V.rt(self.field)
  local par = ey.parent
  local a = ey.action
  if a == 0 then
    if band(RT.f38, 1) ~= 0 then ey.action = 2; self:anim(ey, 1)
    else ey.action = 1; self:anim(ey, 0); self:sfx(SFX.S166) end
    eyeA(self, ey)
  elseif a == 1 then
    eyeA(self, ey)
    V.step(ey)
    if V.done(ey) then ey.action = 2; self:anim(ey, 1) end
  elseif a == 2 then
    eyeA(self, ey)
    if band(RT.f39, 3) == 0 then ey.action = 3; ey.collide = true; ey.speed = 0x80 end
  elseif a == 3 then
    if par.unk79 ~= 0 then eyeA(self, ey)
    else
      local x, y = hx(par.x) + EYE_B[ey.type * 2], hx(par.y) + EYE_B[ey.type * 2 + 1]
      ey.direction = dirTo(hx(ey.x), hx(ey.y), x, y)
      linear(ey)
      -- (sub-pixel drift: within half a pixel counts as there)
      if math.abs(ey.x - x) < 0.5 and math.abs(ey.y - y) < 0.5 then ey.x, ey.y = x, y end
      ey.z = par.z
      if hx(ey.x) == x and hx(ey.y) == y then ey.action, ey.timer = 4, 60 end
    end
  elseif a == 4 then
    eyeB(self, ey)
    if ey.timer ~= 0 then
      ey.timer = ey.timer - 1
      if ey.timer == 0 then self:anim(ey, 3) end
    else
      V.step(ey)
      if V.done(ey) then ey.action, ey.timer = 5, 0 end
    end
  elseif a == 5 then
    if ey.timer ~= 0 then
      ey.action = 6
      ey.timer = (par.health >= 0x15) and 120 or 60
      ey.child = nil
      self:anim(ey, 5)
      self:sfx(SFX.S19B)
    end
    eyeB(self, ey)
  elseif a == 6 then
    eyeB(self, ey)
    V.step(ey)
    if ey.timer ~= 0 then
      ey.timer = ey.timer - 1
      if ey.timer == 0 then self:anim(ey, 6) end
    elseif V.done(ey) then ey.action, ey.timer, ey.subtimer = 7, 120, 0
    elseif band(V.frame(ey), 1) ~= 0 then
      V.clear(ey, 1)
      local b = self:tennis(ey)
      ey.child = b
    end
  elseif a == 7 then
    eyeB(self, ey)
    V.step(ey)
    if ey.subtimer ~= 0 then
      ey.action, ey.timer = 8, 60
      ey.collide = false
      self:show(ey, false)
      self:fx(ey.x, ey.y + (ey.z or 0), FX_REFLECT2)
      par.unk7b = bor(par.unk7b, lshift(0x10, ey.type))
    else
      ey.timer = ey.timer - 1
      if ey.timer ~= 0 then return end
      ey.action, ey.timer = 5, 0
      par.unk7b = bor(par.unk7b, lshift(1, ey.type))
    end
  elseif a == 8 then
    if par.action == 0xB then ey.timer = 60
    else
      ey.timer = ey.timer - 1
      if ey.timer == 0 then
        ey.action = 9
        ey.collide = true
        self:show(ey, true)
        self:anim(ey, 0)
        eyeB(self, ey)
        self:sfx(SFX.S166)
      end
    end
  elseif a == 9 then
    eyeB(self, ey)
    V.step(ey)
    if V.done(ey) then
      ey.action, ey.timer = 4, 1
      par.unk7b = bor(band(par.unk7b, 0xF), lshift(1, ey.type))
    end
  end
end

-- ---------------------------------------------------------------------------
-- projectiles (tracked objects with extUpdate; drawn as ghosts)
-- ---------------------------------------------------------------------------
function V:proj(id, t)
  local d = self:pdef(id)
  t.kind, t.id = 4, id
  t.speed = t.speed or d.speed or 0x100
  t.hitType = t.hitType or d.damageType or 0
  t.hitbox = d.hitbox or { x = 0, y = -3, w = 6, h = 6 }
  local pt = self:part(d, "enemy", t)
  pt.kind = 0x7F -- (a ghost: Field's projectile code must not run it)
  pt.v3proj = id
  local me = self
  pt.extUpdate = function(_, s) if not s.deleted then me:projTick(s) end end
  self.field._dungeon:track(pt)
  self.projs = self.projs or {}
  self.projs[#self.projs + 1] = pt
  return pt
end
-- ProcessMovement3 (walls stop it: collisions)
function V:projMove(s)
  linear(s)
  if self:solid(s.x, s.y) then return true end
  return false
end
-- IsProjectileOffScreen: outside the room
function V:offRoom(s)
  local r = self.field.room
  return s.x < 0 or s.y < 0 or s.x > (r.width or 0x400) or s.y > (r.height or 0x400)
end

-- V3_TENNIS_BALL_PROJECTILE (at the eye, PositionRelative(eye, 0, 12))
function V:tennis(ey)
  local s = self:proj(V.P_TENNIS, { parent = ey, x = ey.x, y = ey.y + 12, z = ey.z, spritePriority = 4, collide = true })
  s.action = 0
  local me = self
  s.onSword = function(pt, box) return me:tennisHit(pt, box) end
  return s
end
-- V3TennisBallProjectile_OnCollision with the sword (contact 6 / $A-$C / $1A)
function V:tennisHit(s, box)
  if s.action ~= 1 then return false end
  local p = self.field.player
  s.action = 2
  s.collide = false
  s.speed = s.speed + 0x80 * 2
  s.child = p.swordProbed or p -- the contactedEntity: this swing's sword
  if self:tennisAlone(s) then s.direction = 0
  else s.direction = dirTo(hx(p.x), hx(p.y), hx(s.x), hx(s.y)) end -- knockbackDirection
  self:sfx(SFX.CHARGE)
  return true
end
-- sub_080ACB40: no other eye's ball was sent back by the same swing
function V:tennisAlone(s)
  local wr = s.parent and s.parent.parent
  local h = wr and wr.heap
  if not h then return true end
  for i = 0, 3 do
    local ey = h.eyes[i]
    local o = ey and ey.child
    if o and o ~= s and s.child == o.child then return false end
  end
  return true
end
function V:tennisTick(s)
  if s.action == 0 then -- V3TennisBallProjectile_Init
    s.action = 1
    s.direction = 0x10
    s.z = -4
    s.child = nil
    self:anim(s, 7)
    self:sfx(SFX.S199)
  elseif s.action == 1 then
    if self:projMove(s) then end -- (ProcessMovement3: Action1 ignores the walls)
    V.step(s)
    if self:offRoom(s) then self:kill(s) return end
    if s.collide and self:touchLink(s) then self:kill(s) return end -- any other contact: DeleteThisEntity
  elseif s.action == 2 then
    if self:projMove(s) then self:kill(s) return end
    V.step(s)
    local ey = s.parent -- sub_080ACB90
    if ey and hx(s.x) == hx(ey.x) and hx(s.y) <= hx(ey.y) then
      ey.subtimer = 1
      self:fx(s.x, s.y + (s.z or 0), FX_REFLECT2)
      self:sfx(SFX.GLOVES)
      self:kill(s)
      return
    end
    if self:offRoom(s) then self:kill(s) end
  end
end

-- V3_ELECTRIC_PROJECTILE type 0 / 1 from the body, type 2 the ring's bolts
function V:electric(k, t0, from)
  local s = self:proj(V.P_ELECTRIC, { type = k, parent = t0, spritePriority = 4, collide = true })
  s.action = 0
  if from then s.type2, s.direction = from.type2, from.direction; copyPos(from, s) end
  return s
end
function V:electricTick(s)
  local p = self.field.player
  local a = s.action
  if a == 0 then
    self:anim(s, s.type + 1)
    local snd
    if s.type == 0 then
      s.action, s.timer, s.subtimer, s.unk85 = 1, 0, 7, 0x18
      copyPos(s.parent, s); s.spriteOX, s.spriteOY = s.parent.spriteOX, s.parent.spriteOY
      s.z = s.z - 0x14
      snd = SFX.S149
    elseif s.type == 1 then
      s.action, s.collide, s.unk85 = 1, false, 0x18
      copyPos(s.parent, s); s.spriteOX, s.spriteOY = s.parent.spriteOX, s.parent.spriteOY
      s.z = s.z - 0x14
      snd = SFX.S149
    else
      s.action, s.timer, s.subtimer = 2, 0, 255
      s.speed = EL_SPEED[s.type2 or 0] or 480
      snd = SFX.S193
    end
    self:sfx(snd)
    return
  end
  if a == 1 then
    if not alive(s.parent) then self:kill(s) return end
    copyPos(s.parent, s); s.spriteOX, s.spriteOY = s.parent.spriteOX, s.parent.spriteOY
    s.z = s.z - 0x14
    if s.unk85 ~= 0 then
      s.unk85 = s.unk85 - 1
      if band(s.unk85, 7) == 0 then self:sfx(SFX.S149) end
    end
    V.step(s)
    if band(V.frame(s), 1) ~= 0 then
      if s.type == 0 then
        s.action = 2
        s.direction = dirTo(hx(s.x), hx(s.y), hx(p.x), hx(p.y))
        s.speed = 0x180
        self:sfx(SFX.S193)
      else
        s.action, s.timer = 3, 16
      end
      s.z = s.z - 0x28
    end
  elseif a == 2 then
    if s.z < -6 then s.z = s.z + 3 end
    if self:projMove(s) then self:kill(s) return end
    V.step(s)
    if self:offRoom(s) then self:kill(s) return end
    if s.timer < 0x1E then
      s.timer = s.timer + 1
      if band(s.timer, s.subtimer) == 0 then turnTo(s, dirTo(hx(s.x), hx(s.y), hx(p.x), hx(p.y))) end
    end
  elseif a == 3 then
    V.step(s)
    s.z = s.z - 0.5
    s.timer = s.timer - 1
    if s.timer == 0 then
      s.action, s.timer = 4, 4
      local r = band(self:rand(), 7)
      s.subtimer = EL_COUNT[r]
      local dir = dirTo(hx(s.x), hx(s.y), hx(p.x), hx(p.y))
      local n84 = s.parent.unk84
      if n84 == 3 then dir = dir - EL_DIR[r]; s.type2 = 0
      elseif n84 == 2 then dir = dir - EL_DIR[r]; s.type2 = 1
      else dir = dir - rshift(EL_DIR[r], 1); s.type2 = 2 end
      s.direction = band(dir, 0x1F)
    end
  elseif a == 4 then
    V.step(s)
    s.timer = s.timer - 1
    if s.timer ~= 0 then return end
    s.timer = 16
    self:electric(2, s.parent, s)
    s.subtimer = s.subtimer - 1
    if s.subtimer == 0 then self:kill(s) return end
    local n84 = s.parent.unk84
    if n84 == 3 or n84 == 2 then s.direction = band(s.direction + 3, 0x1F)
    else s.direction = band(s.direction + 2, 0x1F) end
  end
  if s.collide and not s.deleted and self:touchLink(s) then self:kill(s) end -- OnCollision: DeleteThisEntity
end

-- V3_HAND_PROJECTILE (the arm's shot)
function V:hand(src)
  local s = self:proj(V.P_HAND, { x = src.x, y = src.y, z = (src.z or 0) - 0x18, spritePriority = 4, collide = true })
  s.action = 0
  return s
end
function V:handTick(s)
  local p = self.field.player
  if s.action == 0 then
    s.action = 1
    s.direction = dirTo(hx(s.x), hx(s.y), hx(p.x), hx(p.y))
    self:anim(s, 0)
    self:sfx(SFX.S199)
  end
  if s.z < -6 then s.z = s.z + 2 end
  if self:projMove(s) then self:kill(s) return end
  V.step(s)
  if self:offRoom(s) then self:kill(s) return end
  if self:touchLink(s) then self:kill(s) end
end

function V:projTick(s)
  local id = s.v3proj
  if id == V.P_TENNIS then self:tennisTick(s)
  elseif id == V.P_ELECTRIC then self:electricTick(s)
  elseif id == V.P_HAND then self:handTick(s) end
  if s.deleted then s.hidden = true else s.hidden = not s.drawOn end
end

-- ---------------------------------------------------------------------------
-- objects
-- ---------------------------------------------------------------------------
-- VAATI3_PLAYER_OBJECT: the camera 40 px over Link
function V:playerObject(t0)
  local p = self.field.player
  local o = { kind = 6, id = V.O_PLAYER, x = p.x, y = p.y - 40, v3cam = true }
  local f = self.field
  o.extUpdate = function(_, me) local pl = f.player; me.x, me.y = pl.x, pl.y - 40 end
  f._dungeon:track(o)
  return o
end
-- VAATI3_DEATH type 0 / 1
function V:deathObj(t0, ty)
  local o = self:part(self:odef(V.O_DEATH, ty), self:odef(V.O_DEATH, ty).gfxType or 0, { type = ty, parent = t0, spritePriority = 4 })
  o.v3obj = V.O_DEATH
  self.objs = self.objs or {}
  self.objs[#self.objs + 1] = o
  return o
end
-- VAATI3_ARM type 0 (the hole at the shoulder) / 1 (where the hand comes
-- up) / 2 (a puff)
function V:armObj(ty, parent, armRef)
  local d = self:odef(V.O_ARM, ty)
  local o = self:part(d, d.gfxType or 0, { type = ty, parent = parent, arm = armRef, spritePriority = 4 })
  o.v3obj = V.O_ARM
  if ty == 2 and parent then copyPos(parent, o) end
  self.objs = self.objs or {}
  self.objs[#self.objs + 1] = o
  return o
end
function V:objTick(o)
  if o.v3obj == V.O_DEATH then
    local par = o.parent
    if par.subAction > 3 or par.deleted then self:kill(o) return end
    if o.action == 0 then o.action = 1; self:anim(o, o.type) end
    relate(par, o, 0, o.type)
    o.spriteOY = o.spriteOY - o.type
    V.step(o)
  elseif o.v3obj == V.O_ARM then
    local function place() -- sub_080A0640
      if o.type == 0 then
        local e4 = o.arm and o.arm.ents[4]
        if e4 then relate(e4, o, 0, 8) end
      else copyPos(o.parent, o) end
      o.z = 0
    end
    if o.action == 0 then
      if o.type ~= 2 then o.action, o.spritePriority = 1, 6; place(); self:anim(o, 1)
      else o.action = 2; o.y = o.y + 1; o.z = 0; o.spriteOY = o.spriteOY - 1; self:anim(o, 3) end
    elseif o.action == 1 then
      if o.parent == nil then o.action = 2; self:anim(o, 2)
      else
        if o.parent.deleted then self:kill(o) return end
        place()
        V.step(o)
      end
    else
      V.step(o)
      if V.done(o) then self:kill(o) return end
    end
  elseif o.v3obj == V.O_THUNDER then -- thunderbolt.c type 0 (SFX $F4), gone when its animation ends
    if o.action == 0 then o.action = 1; self:anim(o, 0); self:sfx(SFX.THUNDER) end
    V.step(o)
    if o.anim.done then self:kill(o) return end
  end
  o.hidden = not o.drawOn or o.deleted
end

-- ---------------------------------------------------------------------------
-- the frame
-- ---------------------------------------------------------------------------
function V:update(e)
  if e.dead then return end
  local f = self.field
  local t0, h = e.t0, e.heap
  e.iframes = 0
  if t0.iframes > 0 then t0.iframes = t0.iframes - 1 end
  -- Cane bolts on the arms (contact $1D)
  local AR = require("src.zelda.tmc.BossVaati3Arm")
  local list = {}
  for k = 0, 1 do local arm = h.arms[k]; if arm then for i = 0, 4 do list[#list + 1] = arm.ents[i] end end end
  self:boltCheck(list)
  -- VaatiWrath(): the body's contact with health 0
  if t0.contact and t0.health == 0 then
    t0.collide = true
    t0.health = 0xFF
    t0.unk84 = t0.unk84 - 1
    if t0.unk84 == 0 then
      t0.action, t0.subAction = 0xD, 0
      f:bgm(nil) -- SONG_STOP_ALL
      self:sfx(SFX.BOSS_DIE)
    end
  end
  self:type0(e)
  if e.dead then return end
  -- types 1..3 (deleted with type 0)
  if h.t1 and alive(h.t1) then self:overlay(e, h.t1) end
  if h.t2 and alive(h.t2) then self:overlay(e, h.t2) end
  if h.t3 and alive(h.t3) then self:overlay(e, h.t3) end
  -- the arms
  for k = 0, 1 do
    local arm = h.arms[k]
    if arm then
      AR.tick(self, e, arm)
      if arm.gone then h.arms[k] = nil end
    end
  end
  -- the eyes
  for i = 0, 3 do local ey = h.eyes[i]; if ey and alive(ey) then
    if ey.iframes > 0 then ey.iframes = ey.iframes - 1 end
    self:eye(e, ey); ey.hidden = not ey.drawOn
  end end
  -- objects
  if self.objs then
    for i = #self.objs, 1, -1 do local o = self.objs[i]; if not o.deleted then self:objTick(o) end; if o.deleted then table.remove(self.objs, i) end end
  end
  if self.projs then for i = #self.projs, 1, -1 do if self.projs[i].deleted then table.remove(self.projs, i) end end end
  -- touching Link: the body, the eyes
  if t0.collide and not t0.deleted and t0.drawOn then self:touchLink(t0) end
  for i = 0, 3 do local ey = h.eyes[i]; if ey and alive(ey) and ey.collide then self:touchLink(ey) end end
  -- contact flags last one frame
  t0.contact = nil
  for i = 0, 3 do local ey = h.eyes[i]; if ey then ey.contact = nil end end
  t0.hidden = not t0.drawOn or t0.deleted
  -- the camera (gRoomControls.camera_target)
  if e.camOn and not e.camOn.deleted then f.cameraTarget = e.camOn; e.ownsCam = true
  elseif e.ownsCam then f.cameraTarget = nil; e.ownsCam = nil end
  e.x, e.y, e.z = t0.x, t0.y, 0
end

-- the sword: the body (hitType $38 while he is down), the eyes, the arms,
-- the tennis balls
function V:swordHit(e, box)
  if e.dead then return false end
  local h = e.heap
  local hit = false
  if self.projs then
    for _, s in ipairs(self.projs) do if s.v3proj == V.P_TENNIS and alive(s) and self:swordOn(s, box) then hit = true end end
  end
  for i = 0, 3 do local ey = h.eyes[i]; if ey and alive(ey) and self:swordOn(ey, box) then hit = true end end
  for k = 0, 1 do
    local arm = h.arms[k]
    if arm then for i = 0, 4 do local pt = arm.ents[i]; if alive(pt) and self:swordOn(pt, box) then hit = true end end end
  end
  if alive(e.t0) and self:swordOn(e.t0, box) then hit = true end
  return hit
end

function V:draw(e, camX, camY) end -- every piece is its own ghost entity

-- ---------------------------------------------------------------------------
-- managers
-- ---------------------------------------------------------------------------
-- Vaati3StartManager type 1 (room $8B:00): Vaati appears
function V:startType1(d, m)
  local f = self.field
  local RT = V.RT
  if not RT then RT = V.rtInit(f) end -- (entered without the garden's start manager: its values)
  local e = self:spawnWrath(0xB0, 0x48)
  f.entities[#f.entities + 1] = e
  if band(RT.f38, 1) ~= 0 then return true end
  self:control(false) -- SetPlayerControl(3)
  f.queuedBgm = nil
  f:bgm(nil) -- gArea.queued_bgm = SONG_STOP_ALL
  f.fadeLevel, f.fadeWhite = 1, true
  f:fade("in", true, 4)
  self:sfx(SFX.APPARATE)
  local R26 = require("src.zelda.tmc.R26")
  R26.ticker(d, function(_, me)
    if me.done then return end
    if not f:fadeActive() then e.t0.subAction = 1; me.done = true; me.deleted = true; f.fadeStep = (f.fadeSpeed or 16) / 256 end -- (the engine's later fades keep fadeStep)
  end, { id = V.M_START, type = 1 })
  return true
end

-- Vaati3StartManager type 0 (the garden): the walk up, the bolt, the words,
-- the white fade into the fight
function V:startType0(d, m)
  local f = self.field
  if not f:flag("local", 0x7B) then return true end -- DeleteThisEntity
  V.rtInit(f)
  local st = { action = 1, timer = 0 }
  local me = self
  local R26 = require("src.zelda.tmc.R26")
  R26.ticker(d, function(_, t)
    local p = f.player
    if st.action == 1 then
      local dx, dy = p.x - 0x88, p.y - 0x40
      if dx * dx + dy * dy < 0x901 then
        st.action, st.timer = 2, 120
        me:control(false)
        local tb = me:part(me:odef(V.O_THUNDER, 0), me:odef(V.O_THUNDER, 0).gfxType or 0, { x = 0x88, y = 0x48, spritePriority = 4 })
        tb.v3obj = V.O_THUNDER
        me.objs = me.objs or {}
        me.objs[#me.objs + 1] = tb
        f:bubble(p, 0, 8, -16)
        f:bgm(BGM_VAATI_WRATH)
      end
    elseif st.action == 2 then
      p.animationState = 0
      if (p.z or 0) ~= 0 then
        if p.y < 0x48 then p.y = 0x48 end
      else
        st.timer = st.timer - 1
        if st.timer == 0 then st.action, st.timer = 3, 30; f:message(TEXT_V2_4F, nil) end
      end
    elseif st.action == 3 then
      if not f.textbox then
        if st.timer ~= 0 then st.timer = st.timer - 1
        else st.action = 4; f:fade("out", true, 4); me:sfx(SFX.EVAPORATE) end
      end
    elseif st.action == 4 then
      if not f:fadeActive() then
        f:setFlag("global", V.FLAG_ZELDA_CHASE, false)
        me:control(true)
        st.action = 5
        t.deleted = true
        f:startTransition({ warpType = 1, area = V.AREA_V3, room = 0, endX = 0xB0, endY = 0x88, facing = 0, kind = 0, layer = 1 })
      end
    end
    if me.objs then for i = #me.objs, 1, -1 do local o = me.objs[i]; if not o.deleted then me:objTick(o) end; if o.deleted then table.remove(me.objs, i) end end end
  end, { id = V.M_START, type = 0 })
  return true
end

-- ---------------------------------------------------------------------------
-- the module's hooks (R26)
-- ---------------------------------------------------------------------------
local M = {}
M.V = V
local function impl(f)
  local E = f:enemies()
  if not f._v3 or f._v3.field ~= f or f._v3.room ~= f.room then
    f._v3 = V.new(f, E)
    f._v3.room = f.room
  end
  return f._v3
end
M.impl = impl
local function X() return require("src.zelda.tmc.BossVaati3Extra") end

function M.spawnEnemy(E, dat, def)
  return X().spawnEnemy(E, dat, def)
end
function M.handles(e) return X().handles(e) end
function M.update(E, e) return X().update(E, e) end

function M.spawnManager(d, m, dat)
  local f = d.field
  local id = m.id or (dat and dat.id)
  local ty = m.type or (dat and dat.paramA) or 0
  if id == V.M_START then
    if ty == 1 then return impl(f):startType1(d, m) end
    return impl(f):startType0(d, m)
  end
  if id == V.M_BG then return true end -- Vaati3BackgroundManager: SIMPLIFIED (BG3 not drawn)
  return nil
end

-- sub_StateChange_Vaati3_Main: Link back from an arm stands by its hand;
-- the garden after the fight (sub_StateChange_DarkHyruleCastleOutside_
-- Garden's ENDING branch): the outro's list gUnk_080EAEC0 once (local flag
-- $7F), BGM_BEAT_VAATI
function M.roomInit(f)
  local r = f.room
  if not r then return end
  if r.area == V.AREA_V3 and r.room == 0 then
    local RT = V.RT
    if RT and band(RT.f38, 1) ~= 0 and RT.f39 ~= 0 then
      local p = f.player
      if RT.f3c == 1 then p.x, p.y = RT.f48, RT.f4a + 8
      elseif RT.f3c == 0 then p.x, p.y = RT.f44, RT.f46 + 8 end
    end
  elseif r.area == V.AREA_DHC_OUT and r.room == 1 and f:flag("global", V.FLAG_ENDING) then
    if not f:flag("local", 0x7F) then
      f:setFlag("local", 0x7F, true)
      f:loadEntityList(0x080EAEC0)
      f.queuedBgm = 0x11 -- BGM_BEAT_VAATI
      f:bgm(0x11)
    end
  end
end

-- the ending script's natives (script_Npc4EV3Defeated)
do
  local N = require("src.zelda.tmc.Native").N
  N[0x0807FBFC] = N[0x0807FBFC] or function(f) -- sub_0807FBFC: charms / picolytes off
    local s = f.save.stats
    s.charm, s.charmTimer, s.picolyteType, s.picolyteTimer, s.effect, s.effectTimer = 0, 0, 0, 0, 0, 0
  end
  N[0x08094AE8] = N[0x08094AE8] or function(f, e, ctx) -- sub_08094AE8: a CUTSCENE_MISC_OBJECT type 1 running the script
    f:spawn({ kind = 6, id = V.O_MISC, paramA = 1, paramB = 0, pool = 0x4F, x = 0, y = 0, paramC = ctx.intVariable })
  end
end
-- NPC4E_DoScreenTransition (gNpc4ETransitions / types): only index 6 (the
-- fight -> the garden, TRANSITION_CUT_FAST) is the dungeon's
M.NPC4E_TRANSITIONS = { [6] = { warpType = 1, area = V.AREA_DHC_OUT, room = 1, endX = 0xA8, endY = 0x88, facing = 6, kind = 0, layer = 1 } }
function M.npc4eTransition(f, idx)
  local t = M.NPC4E_TRANSITIONS[idx]
  if t then f:startTransition(t) return true end
  return false
end

do -- NPC4E_DoScreenTransition ($0806DA1C, read from script_Npc4EV3Defeated's CallWithArg)
  local N = require("src.zelda.tmc.Native").N
  N[0x0806DA1C] = N[0x0806DA1C] or function(f, e, ctx) M.npc4eTransition(f, ctx.intVariable) end
end

return M
