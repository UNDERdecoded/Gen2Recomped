-- Round 27 (team A, group T2): the Great Fairy (src/object/greatFairy.c) and
-- the natives of her fountains' scripts (script_GreatFairyArrows / Bombs /
-- Rupees run on a CUTSCENE_ORCHESTRATOR; the fairy object itself sets the
-- second sync flag $4 they wait for).  Required by Story27Town2.lua.
--
-- CARTRIDGE BEHAVIOUR (ported): GreatFairy (object $1B), type2 = type % 11
-- picks the part, CreateObject(GREAT_FAIRY, (type / 11) * 11 + part, param)
-- makes the others:
--   0 the fairy: Init (anim, unk_84 = 290); Dormant: waits for room flag 0,
--     counts unk_84 down, ripples (part 6) at 289/210/170/150/130 placed by
--     GreatFairy_RippleOffsets, at 0 -> the big ripple (part 7, +8 y);
--     Spawning: roomVars.animFlags & 1 -> the wake (part 2), SetFade(white,
--     instant, 4), SFX_145, drawn, 60 frames; Mini: then the wings (part 1,
--     -20 y), 120 frames; Final: then part 9 at -76 y.  Every frame the camera
--     follows her while Link is above y 168 (scroll speed 2), else Link.
--   1 wings: affine x scale 1024 -> 256 (-32 a frame), blended 9/8; done ->
--     animFlags |= $20, gActiveScriptInfo.syncFlags |= 4.
--   2 wake, 6 ripple (gone on animFlags & 2), 8 energy / 5 droplet (gone on
--     ANIM_DONE; the droplet plays SFX_140).
--   3 the small fairy rising: creates part 4 (its stretching copy), z -0.5 a
--     frame; at z -10 the droplet (+4 y), at z -20 SFX_HEART_CONTAINER_SPAWN,
--     then energy rings (part 8) every 48 frames until animFlags & 1.
--   4 the stretch: follows part 3; from z -20, 90 frames of y scale
--     256 -> (4096 - 24n) >> 4, then animFlags |= 1 and it is deleted.
--   7 the big ripple: SFX_TELEPORTER, 120 frames, then part 3 (-8 y) and
--     animFlags |= 2.
--   9 sub_08087150 + Form2Behaviors (speed $80, direction down).
-- Natives: sub_08087424 (ResetPlayerAnimationAndAction, THUNDERBOLT on Link,
-- arrows (0) / bombs (1) = 0), sub_080873FC (SFX_APPARATE, camera target off,
-- every GREAT_FAIRY deleted), sub_0808747C (FindEntity(OBJECT, SPECIAL_FX,
-- type FX_WATER_SPLASH)).
--
-- SFX (SoundReq): SFX_145 ($145), SFX_HEART_CONTAINER_SPAWN ($141), SFX_140
--   ($140), SFX_TELEPORTER ($F9), SFX_APPARATE ($F7).
--
-- SIMPLIFIED:
--   * part 9's sub_080871F8 walks to its child's position, but nothing in
--     greatFairy.c gives it a child: it stays where it was made.  Part 10
--     (sub_080872AC / sub_080872F8) is never created by these scripts and
--     is not ported; nor is part 9's palette (gUnk_0812079C, ROM data).
--   * the BLDALPHA blends are sprite alpha (EVA / 16); the affine parts are
--     drawn scaled about their centre (no rotation is used here).
local bit = require("bit")
local band, bor = bit.band, bit.bor

local Native = require("src.zelda.tmc.Native")
local N = Native.N

local F = {}
F.P = {}
local function reg(addr, name, fn)
  F.P[name] = fn
  if not N[addr] then N[addr] = fn end
end

local OBJ_GREAT_FAIRY, OBJ_THUNDERBOLT, OBJ_SPECIAL_FX, FX_WATER_SPLASH = 0x1B, 0x64, 0x0F, 0x0B
F.SFX = { S145 = 0x145, HEART_CONTAINER_SPAWN = 0x141, S140 = 0x140, TELEPORTER = 0xF9, APPARATE = 0xF7 }
local PART = { BEHAVIORS = 0, WINGS = 1, WAKE = 2, MINI = 3, MINIAFFINE = 4, DROPLET = 5, RIPPLE = 6,
               BIGRIPPLE = 7, ENERGY = 8, FORM9 = 9, FORM10 = 10 }
F.PART = PART
F.RIPPLE_OFFSETS = { [0] = 0, 0, -32, -8, 16, 20, 24, -12, -16, 24 } -- GreatFairy_RippleOffsets

local function rv(f)
  f.r27rv = f.r27rv or { animFlags = 0 }
  return f.r27rv
end
local function flags(f) return rv(f).animFlags or 0 end
local function setFlags(f, v) rv(f).animFlags = bor(flags(f), v) end
local function hi(cz) return math.floor(cz) end -- z.HALF.HI

local function setZ(e, cz) e.cz = cz; e.z = -cz end
local function anim(e) if e.anim and e.anim.keys then e.anim:update(1) end end
local function initAnim(e) -- GreatFairy_InitializeAnimation
  e.action = 1
  e.r27part = e.r27type % 11
  e.layer = 2
  e.objAnim = e.r27part
  e.animIndex = nil
end

-- the draw: alpha (BLDALPHA EVA / 16) and the affine scale (SetAffineInfo:
-- 256 / value), about the sprite's centre
local function draw(me, field, camX, camY)
  if me.hidden then return end
  local lg = love and love.graphics
  if not lg then return end
  local a = me.r27alpha or 1
  local r, g, b, aa = lg.getColor()
  lg.setColor(r, g, b, (aa or 1) * a)
  if not me.r27aff then
    local fn = me.drawGhost
    me.drawGhost = nil
    field:drawSpriteList({ me })
    me.drawGhost = fn
  else
    local A = field.assets
    local frame = me.anim and me.anim.frame
    if frame and frame ~= 0xFF then
      local img, ox, oy = A:spriteFrame(me.sprite, frame, me.palette,
        "e" .. tostring(me.def and me.def.palette) .. ":" .. tostring(me.kind), me.gfx)
      if img then
        local w, h = img:getDimensions()
        local x = math.floor(me.x - camX)
        local y = math.floor(me.y - camY - (me.z or 0))
        local sx, sy = 256 / me.r27aff[1], 256 / me.r27aff[2]
        local flip = me.anim:hflip()
        local cx = flip and (x - ox - w / 2) or (x + ox + w / 2)
        lg.draw(img, cx, y + oy + h / 2, 0, flip and -sx or sx, sy, w / 2, h / 2)
      end
    end
  end
  lg.setColor(r, g, b, aa)
end
F.draw = draw

-- CreateObject(GREAT_FAIRY, (type / 11) * 11 + part, param) at the given spot
local function create(f, e, part, param, dx, dy)
  local t = math.floor(e.r27type / 11) * 11 + part
  local o = f:spawn({ kind = 6, id = OBJ_GREAT_FAIRY, paramA = t, paramB = param or 0, x = e.x + (dx or 0),
                      y = e.y + (dy or 0), pool = 0, paramC = 0, collision = 2 })
  if o and o.r27fairy then setZ(o, e.cz or 0); o.layer = e.layer end
  return o
end
F.create = create

-- Dungeon:spawnObject (through R27A): every GREAT_FAIRY part
function F.spawnObject(d, e)
  if e.id ~= OBJ_GREAT_FAIRY then return nil end
  local f = d.field
  e.r27fairy = true
  e.r27type = e.form or 0
  e.r27part = e.r27type % 11
  e.action = 0
  e.timer, e.subtimer = 0, 0
  setZ(e, 0)
  local O = f:objects()
  local def = O.def and O:def(OBJ_GREAT_FAIRY, e.r27type)
  if def then O:dress(e, def, e.r27part) end
  e.literalAnim = true
  e.objAnim = e.r27part
  e.hidden = true -- spriteSettings.draw = 0 until the part's init
  e.solid, e.talkable = false, false
  e.drawGhost = draw
  return e
end

-- ---------------------------------------------------------------- parts
local U = {}
U[PART.BEHAVIORS] = function(f, e)
  if e.action == 0 then
    initAnim(e)
    e.timer = 0
    e.unk84 = 290
  elseif e.action == 1 then
    if f:flag("room", 0) then
      if e.unk84 ~= 0 then e.unk84 = e.unk84 - 1 end
      local c = e.unk84
      if c == 0 then
        e.action = 2
      elseif c == 130 or c == 150 or c == 170 or c == 210 or c == 289 then
        local o = create(f, e, PART.RIPPLE, 0, F.RIPPLE_OFFSETS[e.timer], F.RIPPLE_OFFSETS[e.timer + 1])
        if o then e.timer = e.timer + 2 end
      end
    end
  elseif e.action == 2 then
    if create(f, e, PART.BIGRIPPLE, 0, 0, 8) then e.action = 3 end
  elseif e.action == 3 then
    if band(flags(f), 1) ~= 0 then
      if create(f, e, PART.WAKE, 0) then
        f:fade("in", true, 4) -- SetFade(FADE_BLACK_WHITE | FADE_INSTANT, 4)
        f:sound(F.SFX.S145)
        e.action = 4
        e.timer = 60
        e.hidden = false
      end
    end
  elseif e.action == 4 then
    anim(e)
    if e.timer ~= 0 then e.timer = e.timer - 1
    elseif create(f, e, PART.WINGS, 0, 0, -20) then
      e.action, e.timer, e.subtimer = 5, 120, 0
    end
  elseif e.action == 5 then
    if e.timer ~= 0 then e.timer = e.timer - 1
    elseif e.subtimer == 0 then
      local o = create(f, e, PART.FORM9, 0, 0, -76)
      if o then o.parent = e; e.subtimer = 1 end
    end
    anim(e)
  end
  -- GreatFairy_CallBehavior: the camera
  if f.player and f.player.y < 168 then f.cameraTarget = e else f.cameraTarget = nil end
  f.scrollSpeed = 2
end
U[PART.WINGS] = function(f, e)
  if e.action == 0 then
    initAnim(e)
    e.hidden = false
    e.r27alpha = 9 / 16 -- BLDALPHA_BLEND(9, 8)
    e.speed = 1024
    e.r27aff = { 1024, 256 }
  elseif e.action == 1 then
    e.speed = e.speed - 32
    if e.speed == 256 then
      e.action = 2
      e.r27aff = nil -- sub_0805EC60
      setFlags(f, 32)
      local S = require("src.zelda.tmc.Script").active
      S.syncFlags = bor(S.syncFlags or 0, 4)
    else
      e.r27aff = { e.speed, 256 }
    end
  end
end
U[PART.WAKE] = function(f, e)
  if e.action == 0 then initAnim(e); e.hidden = false else anim(e) end
end
U[PART.MINI] = function(f, e)
  if e.action == 0 then
    local o = create(f, e, PART.MINIAFFINE, 0)
    if o then
      o.parent = e
      initAnim(e)
      e.hidden = false
      e.subtimer = 0
    end
  elseif e.action == 1 then
    anim(e)
    setZ(e, e.cz - 0.5)
    if hi(e.cz) == -20 then
      e.action = 2
      f:sound(F.SFX.HEART_CONTAINER_SPAWN)
    elseif hi(e.cz) == -10 and e.subtimer == 0 then
      if create(f, e, PART.DROPLET, 0, 0, 4) then e.subtimer = 1 end
    end
  elseif e.action == 2 then
    anim(e)
    -- sub_080873D0: an energy ring every 48 frames
    if e.timer ~= 0 then e.timer = e.timer - 1
    elseif create(f, e, PART.ENERGY, 0) then e.timer = 48 end
    if band(flags(f), 1) ~= 0 then e.deleted = true end
  end
end
U[PART.MINIAFFINE] = function(f, e)
  if e.action == 0 then
    initAnim(e)
    e.hidden = false
  elseif e.action == 1 then
    local p = e.parent
    if p then e.x, e.y, e.layer = p.x, p.y, p.layer; setZ(e, p.cz or 0) end
    if hi(e.cz) == -20 then
      e.action, e.timer, e.speed = 2, 90, 4096
      e.r27aff = { 256, 256 }
    end
  elseif e.action == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      setFlags(f, 1)
      e.action = 3
      e.r27aff = nil
    else
      e.speed = e.speed - 24
      e.r27aff = { 256, math.floor(e.speed / 16) }
    end
  else
    e.deleted = true -- DeleteEntity
  end
end
U[PART.DROPLET] = function(f, e)
  if e.action == 0 then
    initAnim(e)
    e.hidden = false
    setZ(e, 0)
    f:sound(F.SFX.S140)
  else
    anim(e)
    if e.anim and e.anim.done then e.deleted = true end
  end
end
U[PART.RIPPLE] = function(f, e)
  if e.action == 0 then initAnim(e); e.hidden = false
  elseif band(flags(f), 2) ~= 0 then e.deleted = true
  else anim(e) end
end
U[PART.BIGRIPPLE] = function(f, e)
  if e.action == 0 then
    initAnim(e)
    e.timer = 120
    e.hidden = false
    f:sound(F.SFX.TELEPORTER)
  else
    anim(e)
    if e.timer ~= 0 then e.timer = e.timer - 1
    elseif create(f, e, PART.MINI, 0, 0, -8) then
      setFlags(f, 2)
      e.deleted = true
    end
  end
end
U[PART.ENERGY] = function(f, e)
  if e.action == 0 then initAnim(e); e.hidden = false
  else
    anim(e)
    if e.anim and e.anim.done then e.deleted = true end
  end
end
U[PART.FORM9] = function(f, e)
  if e.action == 0 then -- sub_08087150
    initAnim(e)
    e.hidden = false
    e.speed, e.direction = 0x80, 0x10
  end
  anim(e) -- Form2: sub_080871F8 has no child to walk to (SIMPLIFIED)
end
F.U = U

function F.update(f, e)
  if e.deleted then return end
  if e.action == 0 then e.r27part = e.r27type % 11 end
  local fn = U[e.r27part]
  if fn then fn(f, e) end
end

function F.frame(f)
  local list = f.entities or {}
  local n = #list
  for i = 1, n do
    local e = list[i]
    if e and e.r27fairy and not e.deleted then F.update(f, e) end
  end
end

function F.roomInit(f) end

-- ---------------------------------------------------------------- natives
reg(0x08087424, "sub_08087424", function(f, e, ctx)
  local reset = N[0x080791D0]
  if reset then reset(f) end
  local p = f.player
  local o = f:spawn({ kind = 6, id = OBJ_THUNDERBOLT, paramA = 0, paramB = 0, x = p.x, y = p.y, pool = 0, paramC = 0 })
  if o then o.parent = p; o.x, o.y = p.x, p.y end
  local v = ctx.intVariable or 0
  if v == 0 then f.save.stats.arrowCount = 0
  elseif v == 1 then f.save.stats.bombCount = 0 end
end)
reg(0x080873FC, "sub_080873FC", function(f)
  f:sound(F.SFX.APPARATE)
  f.cameraTarget = nil
  for _, o in ipairs(f.entities or {}) do
    if o.kind == 6 and o.id == OBJ_GREAT_FAIRY then o.deleted = true end
  end
end)
reg(0x0808747C, "sub_0808747C", function(f, e, ctx)
  ctx.condition = 0
  for _, o in ipairs(f.entities or {}) do
    if o.kind == 6 and o.id == OBJ_SPECIAL_FX and o.form == FX_WATER_SPLASH and (o.type2 or 0) == 0 and not o.deleted then
      ctx.condition = 1
      break
    end
  end
end)

return F
