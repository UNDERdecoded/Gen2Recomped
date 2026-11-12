-- Round 23: the Cave of Flames' enemies: SPIKED_BEETLE ($1E, src/enemy/
-- spikedBeetle.c) and HELMASAUR ($20, src/enemy/helmasaur.c, both types).
--
-- SPIKED_BEETLE
--   Init (sub_0802B72C): home rectangle, timer 1, animationState $FF, then
--     sub_0802B7A4.  sub_0802B7A4 (action 2's wait): at 0 -> action 1, timer
--     gUnk_080CD314[Random & 3] ($30/$48/$60/$78), speed $60, a direction
--     from sub_0802B960 (Link in the home rectangle: 1 in 8 straight at him
--     (DirectionRoundUp); outside its home: 1 in 4 back home; else a random
--     DirectionRound), animation direction >> 3 when it changed.
--   Action 1 (sub_0802B744): GetNextFrame; Link in the home rectangle and
--     lined up (sub_0804A024(.., 1, $0C): within 6 px on an axis, an open
--     line) -> action 3 (timer 30, that direction, animation 8: the wind-up);
--     else the timer -> action 2 (30); a wall (ProcessMovement0 false) ends
--     the walk at once.
--   Action 3: GetNextFrame; at 0 -> action 4 (timer 120, speed $1C0).
--   Action 4 (sub_0802B820): ProcessMovement2 (a wall -> timer 1); at 0 or
--     Link out of the home rectangle -> sub_0802B9B4 (action 5, timer 60,
--     animation state + 4: skidding); every 16 frames one step toward Link
--     (sub_08004596).
--   Action 5: at 0 -> action 2 (timer 60), animation by direction.
--   OnCollision: Link's body / the sword (0, 4-6, 8-$C) while charging ->
--     timer 1; the shield (2 / 3), $16, $18-$1A (spin), $1D (the Cane) ->
--     flipped (action 6: zVelocity 1.5, speed $C0, the knockback
--     direction, no knockback, hitType 100, animation 9).
--   Action 6: ProcessMovement2 + BounceUpdate(24) (SFX_12B on each bounce);
--     done -> action 7, timer 150 (on its back, hitType 100: the sword
--     hurts).  Action 7: the last 60 frames shake (spriteOffsetX +-1); at 0
--     -> action 8 (zVelocity 1.0, speed $60, hitType 99, SFX_12B), and when
--     it lands, action 1 / timer 1.
-- HELMASAUR (type 0)
--   Init (sub_0802BD54): home rectangle, unk_78 Random, tolerance 60,
--     unk_79 $FF, a random DirectionRound, animation dir >> 3.
--   Action 1: the timer, then (Link in the home rectangle and lined up
--     (sub_0804A024(.., 1, $10)) in a new direction) or sub_0802C020 (a
--     random DirectionRound inside its home or 1 in 2, else toward home
--     + 0 / 4) -> action 2 when it differs from the current one.
--   Action 2 (sub_0802BDE0): 8 steps of 8 px ahead clear of IsTileCollision
--     type 0 (sub_0802C06C) -> action 3 (timer 60: pawing, animation
--     frames twice); else back to action 1 (timer 15-30, that direction
--     remembered as unk_79).
--   Action 3 -> action 4 (timer 30, speed $300): the charge; a wall
--     (ProcessMovement2) -> sub_0802C218 (action 6: speed $E0, zVelocity
--     1.5) and a screen shake (8); timer out or a wall 6 px ahead -> action
--     5: speed - $20 a frame, at 0 action 1 (timer 60).
--   Action 6: moves backwards, BounceUpdate($2000), done -> action 1.
--   OnCollision (masked, hitType != $19): Link's body or the shield while
--     charging -> knockback 0, sub_0802C218.
--   OnGrabbed (masked): subaction 0 faces Link (AnimationStateFlip90),
--     tolerance 60; 1 wiggles; 2 (sub_0802BCA8) the mask comes off: action
--     7 (timer 90, zVelocity 1.5), hitType $19, gustJarFlags $12, a
--     HELMASAUR type 1 (the mask) at its place, animation state + 4.
--   Action 7: every 32 frames it turns half round; then GravityUpdate(28)
--     -> action 8: speed $120, ProcessMovement0, a new sub_0802C020
--     direction every 30 frames (animation + 4).
-- HELMASAUR type 1 (the mask): gustJarFlags 1 (swallowed), animation state
--   + 8; pulled into the jar while the gust holds it (sub_0806F3E4), else
--   it blinks 30 frames and is deleted.
-- SIMPLIFIED: ProcessMovement2 is the port's ProcessMovement0 box test;
--   the FX_DASH puffs (sub_0802C18C) and the charge's tile interaction
--   (DoTileInteraction filter 9) are not ported; the mask's pull is a
--   straight pull at the jar's growing speed.
local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local C = {}
C.SPIKED_BEETLE, C.HELMASAUR = 0x1E, 0x20
local SFX_12B, SFX_EF = 0x12B, 0xEF
local BEETLE_WALK = { [0] = 0x30, 0x48, 0x60, 0x78 } -- gUnk_080CD314
local SHAKE = { [0] = 1, -1, -1, 1 }                 -- gUnk_080CD318
local AHEAD = { [0] = { 0, -8 }, [8] = { 8, 0 }, [16] = { 0, 8 }, [24] = { -8, 0 } } -- gUnk_080CD45C

local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function D() return require("src.zelda.tmc.Drops") end
local function R(f) return D().random(D().rngOf(f)) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function round(d) return band(d + 4, 0x18) end            -- DirectionRound
local function roundUp(d) return band(d + 4, 0x18) end          -- DirectionRoundUp (same rounding for 8-way picks)
local function move(E, e, dir, spd)                              -- ProcessMovement0 / 2: true when it moved freely
  local hx, hy = DW().move0(E, e, dir, spd)
  return not (hx or hy)
end
local function dirTo(ax, ay, bx, by) return DW().dirTo(ax, ay, bx, by) end
local function syncZ(e) e.z = -(e.cz or 0) / 65536 end
-- GravityUpdate (16.16 z, negative up): true while airborne
local function gravity(e, g)
  local z = (e.cz or 0) - (e.czv or 0)
  if z < 0 then e.cz = z; e.czv = (e.czv or 0) - g; syncZ(e) return true end
  e.cz, e.czv = 0, 0; syncZ(e)
  return false
end
local function bounce(e, g) local r = require("src.zelda.tmc.EnemyCrenel").bounce(e, g); syncZ(e) return r end

-- sub_08049FDC: the target inside the home rectangle; sub_08049FA0: the enemy
local function targetHome(E, e)
  local t = DW().target(E.field)
  if not t then return nil end
  local dx, dy = math.floor(t.x) - e.homeX, math.floor(t.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH and t or nil
end
local function selfHome(e)
  local dx, dy = math.floor(e.x) - e.homeX, math.floor(e.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH
end
-- sub_08049EE4: toward the home rectangle's middle
local function homeDir(e) return dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) end
local function lined(E, e, w) return require("src.zelda.tmc.EnemyBeetle").linedUp(E, e, w) end

function C.handles(e) return e.id == C.SPIKED_BEETLE or e.id == C.HELMASAUR end

-- ===========================================================================
-- SPIKED_BEETLE
-- ===========================================================================
local function beetlePick(E, e) -- sub_0802B960
  local f = E.field
  local t = targetHome(E, e)
  if t then
    if band(R(f), 7) == 0 then e.dir = roundUp(dirTo(e.x, e.y, t.x, t.y)) return end
  elseif not selfHome(e) then
    if band(R(f), 3) == 0 then e.dir = roundUp(homeDir(e)) return end
  end
  e.dir = round(R(f))
end

local function beetleWait(E, e) -- sub_0802B7A4
  e.timer = e.timer - 1
  if e.timer == 0 then
    e.action = 1
    e.timer = BEETLE_WALK[band(R(E.field), 3)]
    e.spd = 0x60
    beetlePick(E, e)
    local a = rshift(e.dir, 3)
    if a ~= e.animState then e.animState = band(a, 3); setAnim(E, e, a) end
  end
end

local function beetleSkid(E, e) -- sub_0802B9B4
  e.action, e.timer = 5, 60
  e.animState = band(rshift(e.dir, 3), 3)
  setAnim(E, e, e.animState + 4)
end

function C.beetleCollision(E, e, flags)
  local k = band(flags, 0x7F)
  if k == 0 or (k >= 4 and k <= 6) or (k >= 8 and k <= 0xC) then
    if e.action == 4 then e.timer = 1 end
  elseif k == 2 or k == 3 or k == 0x16 or k == 0x18 or k == 0x19 or k == 0x1A or k == 0x1D then
    if e.action < 6 then
      local p = E.field.player
      e.action = 6
      e.czv, e.cz = 0x18000, e.cz or 0
      e.spd = 0xC0
      e.dir = round(dirTo(p.x, p.y, e.x, e.y)) -- knockbackDirection
      e.kbt = 0
      e.iframes = 0
      e.hitType = 100
      setAnim(E, e, 9)
    end
  end
end

function C.beetle(E, e)
  local f = E.field
  if e.action == 0 then
    e.timer, e.animState = 1, 0xFF
    e.onCollision = C.beetleCollision
    e.cz, e.czv = 0, 0
    return beetleWait(E, e)
  elseif e.action == 1 then
    e.anim:update(1)
    local dir = targetHome(E, e) and lined(E, e, 0x0C)
    if dir then
      e.action, e.timer, e.dir = 3, 30, round(dir)
      setAnim(E, e, 8)
    else
      e.timer = e.timer - 1
      if e.timer == 0 then e.action, e.timer = 2, 30
      elseif not move(E, e, e.dir, e.spd) then e.timer = 1 end
    end
  elseif e.action == 2 then
    beetleWait(E, e)
  elseif e.action == 3 then
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.timer, e.spd = 4, 120, 0x1C0 end
  elseif e.action == 4 then
    if not move(E, e, e.dir, e.spd) then e.timer = 1 end
    e.anim:update(1)
    e.timer = e.timer - 1
    local t = targetHome(E, e)
    if e.timer == 0 or not t then beetleSkid(E, e)
    elseif band(e.timer, 0xF) == 0 then
      -- sub_08004596: one step (of 32) toward the facing direction
      local want = dirTo(e.x, e.y, t.x, t.y)
      local d = band(want - e.dir, 0x1F)
      if d ~= 0 then e.dir = band(e.dir + (d < 16 and 1 or -1), 0x1F) end
    end
  elseif e.action == 5 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.timer = 2, 60
      e.animState = band(rshift(e.dir + 4, 3), 3) -- DirectionToAnimationState
      setAnim(E, e, e.animState)
    end
  elseif e.action == 6 then
    move(E, e, e.dir, e.spd)
    local r = bounce(e, 0x1800)
    if r == 0 then e.action, e.timer = 7, 150; f:sound(SFX_12B)
    elseif r == 1 then f:sound(SFX_12B) end
  elseif e.action == 7 then
    e.timer = e.timer - 1
    if e.timer > 0 then
      if e.timer < 0x3C and band(e.timer, 1) == 1 then e.spriteOX = (e.spriteOX or 0) + SHAKE[band(rshift(e.timer, 1), 3)] end
    else
      e.spriteOX = nil
      e.action = 8
      e.czv = 0x10000
      e.spd = 0x60
      e.hitType = 99
      setAnim(E, e, band(e.animState or 0, 3))
      f:sound(SFX_12B)
    end
  elseif e.action == 8 then
    if not gravity(e, 0x1800) then e.action, e.timer = 1, 1 end
  end
end

-- ===========================================================================
-- HELMASAUR
-- ===========================================================================
local function helmPick(E, e) -- sub_0802C020
  local r = R(E.field)
  if selfHome(e) or band(r, 1) == 1 then return round(r) end
  return band(homeDir(e) + band(rshift(r, 16), 1) * 4, 0x18)
end
local function helmFace(E, e, dir) -- sub_0802C058
  e.action, e.dir = 2, dir
  e.animState = rshift(dir, 3)
  setAnim(E, e, e.animState)
end
local function hitPoint(e) local hb = e.hitbox or { x = 0, y = 0 } return math.floor(e.x) + (hb.x or 0), math.floor(e.y) + (hb.y or 0) end
local function tileSolid0(f, x, y, layer) -- IsTileCollision(.., 0)
  return f.room:isSolid(x, y, layer == 2 and 2 or 1)
end
local function clearAhead(E, e) -- sub_0802C06C
  local x, y = hitPoint(e)
  local o = AHEAD[band(e.dir, 0x18)]
  for _ = 1, 8 do
    x, y = x + o[1], y + o[2]
    if tileSolid0(E.field, x, y, e.layer) then return false end
  end
  return true
end
local function chargeEnds(E, e) -- sub_0802C0E8
  e.timer = e.timer - 1
  if e.timer == 0 then return true end
  local x, y = hitPoint(e)
  local o = AHEAD[band(e.dir, 0x18)]
  -- gUnk_080CD45C[dir >> 2] * 6: 48 px ahead (sub_0806FC24's tile filter 9 not ported)
  return tileSolid0(E.field, x + o[1] * 6, y + o[2] * 6, e.layer)
end
local function helmRecoil(e) -- sub_0802C218
  e.action, e.spd = 6, 0xE0
  e.czv = 0x18000
end

function C.helmCollision(E, e, flags)
  if e.hitType == 0x19 then return end
  local k = band(flags, 0x7F)
  if (k == 0 or k == 2 or k == 3) and e.action == 4 then e.kbt = 0; helmRecoil(e) end
end

-- OnGrabbed subaction 0 (sub_0802BC74): it turns to face Link
function C.helmGrabbed(E, e)
  if e.hitType == 0x19 then return end
  local p = E.field.player
  e.action, e.timer = 1, 30
  e.animState = band(rshift(p.animationState or 0, 1) + 2, 3) -- AnimationStateFlip90 of Link's facing
  setAnim(E, e, e.animState)
end

-- OnGrabbed subaction 2 (sub_0802BCA8): the mask comes off instead of the pull
function C.helmJarPull(E, e)
  if e.hitType == 0x19 then return false end
  local f = E.field
  e.action, e.timer = 7, 90
  e.czv, e.cz = 0x18000, 0
  e.hitType = 0x19
  e.gustJarFlags = 0x12
  local m = { kind = 3, id = C.HELMASAUR, form = 1, x = e.x, y = e.y, z = 0, layer = e.layer,
              health = 1, maxHealth = 1, hitType = 0, hitbox = e.hitbox, sprite = e.sprite, palette = e.palette,
              gfx = e.gfx, anim = require("src.zelda.tmc.Anim").new(), animationState = e.animState,
              action = 0, timer = 30, iframes = 0, kbt = 0, enemy = true, literalAnim = true, field82 = 0,
              interactType = 0, def = e.def, noTouch = true, mask = true, animState = e.animState,
              homeX = e.homeX, homeY = e.homeY, rangeW = e.rangeW, rangeH = e.rangeH }
  f.entities[#f.entities + 1] = m
  setAnim(E, e, e.animState + 4)
  return true
end

local function maskUpdate(E, e)
  local f = E.field
  if e.action == 0 then -- sub_0802BF78
    e.action = 1
    e.dir = (e.animState or 0) * 8
    e.pull = 0
    setAnim(E, e, (e.animState or 0) + 8)
    return
  end
  local p = f.player
  local j = p.jar
  if e.action == 1 and j and j.state == "suck" then
    local GJ = require("src.zelda.tmc.GustJar")
    local mx, my = GJ.mouth(p)
    e.pull = math.min(0x500, e.pull + 64 * (j.charge or 1))
    local dx, dy = mx - e.x, my - e.y
    local d = math.sqrt(dx * dx + dy * dy)
    local sp = e.pull / 256
    if d <= sp then e.x, e.y = mx, my else e.x, e.y = e.x + dx / d * sp, e.y + dy / d * sp end
    if math.abs(e.x - mx) < 4 and math.abs(e.y - my) < 4 then f:sound(SFX_EF); e.deleted = true end
    return
  end
  -- sub_0802BFF4: let go -> it blinks 30 frames and is gone
  e.action = 2
  e.hidden = not e.hidden
  e.timer = e.timer - 1
  if e.timer <= 0 then e.deleted = true end
end

function C.helmasaur(E, e)
  local f = E.field
  if e.mask then return maskUpdate(E, e) end
  if e.action == 0 then
    e.action = 1
    e.u78 = R(f)
    e.u79 = 0xFF
    e.timer = 0
    e.dir = round(R(f))
    e.animState = rshift(e.dir, 3)
    e.onCollision = C.helmCollision
    e.onGrabbed = C.helmGrabbed
    e.onJarPull = C.helmJarPull
    e.cz, e.czv = 0, 0
    setAnim(E, e, e.animState)
  elseif e.action == 1 then
    if e.timer > 0 then e.timer = e.timer - 1 return end
    if targetHome(E, e) then
      local d = lined(E, e, 0x10)
      if d and d ~= e.u79 then return helmFace(E, e, d) end
    end
    local d = helmPick(E, e)
    if d ~= e.dir then helmFace(E, e, d) end
  elseif e.action == 2 then
    if clearAhead(E, e) then e.action, e.timer, e.u79 = 3, 60, 0xFF
    else e.action, e.timer, e.u79 = 1, band(R(f), 0xF) + 15, e.dir end
  elseif e.action == 3 then
    e.anim:update(2)
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.timer, e.spd = 4, 30, 0x300 end
  elseif e.action == 4 then
    if not move(E, e, e.dir, e.spd) then
      helmRecoil(e)
      f:shake(8, 0)
    else
      e.anim:update(1)
      if chargeEnds(E, e) then e.action = 5 end
    end
  elseif e.action == 5 then
    e.spd = e.spd - 0x20
    if e.spd > 0 then move(E, e, e.dir, e.spd)
    else e.action, e.timer = 1, 60 end
  elseif e.action == 6 then
    move(E, e, bxor(e.dir, 0x10), e.spd)
    if bounce(e, 0x2000) == 0 then e.action, e.timer = 1, 30 end
  elseif e.action == 7 then
    if e.timer > 0 then
      e.timer = e.timer - 1
      if band(e.timer, 0x1F) == 0 then
        e.animState = bxor(e.animState, 2)
        e.dir = e.animState * 8
        setAnim(E, e, e.animState + 4)
      end
    elseif not gravity(e, 0x1C00) then
      e.action, e.timer, e.spd = 8, 30, 0x120
    end
  elseif e.action == 8 then
    move(E, e, e.dir, e.spd)
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.timer = 30
      e.dir = helmPick(E, e)
      local a = rshift(e.dir, 3)
      if a ~= e.animState then e.animState = a; setAnim(E, e, a + 4) end
    end
  end
end

function C.update(E, e)
  if e.id == C.SPIKED_BEETLE then return C.beetle(E, e) end
  return C.helmasaur(E, e)
end

return C
