-- Round 25: the Cave of Flames' Rupee Like and the red ChuChu, from the decomp.
--
-- RUPEE_LIKE ($17, src/enemy/rupeeLike.c):
--   type2 0 is the body; at Init (sub_0802940C) it makes its child (type2
--   1, the second sprite part, which follows it: sub_080293DC copies the
--   parent's position, y + 1, z - 1) and becomes a rupee (sub_080297F0):
--   action 1, timer 120, hit type $8E, sprite 0x143 (the rupee), palette
--   gUnk_080CCC47[type] (2 / 1 / 0), animation $54.
--   Action 1 (sub_0802944C): once unk_81 is set (after the first time) and
--     Link is in its home (sub_08049FDC) it shows itself.  Any contact
--     while a rupee (hit type $8E, RupeeLike_OnCollision) also does:
--     sub_08029770 -> action 2, collision off, its own sprite ($D1, gfx
--     $73), hit type $8D, animation 2, the child shown with animation 6.
--   Action 2 (sub_08029474): animation done -> action 3, timer 8, facing
--     Link (animation state = direction >> 4: 0 / 1 = south / north), the
--     body animation = state, the child state + 4; frame 1 -> collision on.
--   Action 3 (sub_080294D4): Link in the home: every 8 frames turn toward
--     him (sub_08004596), ProcessMovement0; else action 6 (collision off,
--     animations 3 / 7) -> its animation done: rupee again (sub_080297F0)
--     with unk_81 set.
--   Contact with Link's body (contactedEntity kind 1): action 4, timer 60,
--     subtimer 0, unk_83 $41, SFX_PLACE_OBJ -- Link is held inside it
--     (sub_0802953C: mobility locked, his position = its own + (0, 1)); each
--     new press counts; more than $2D presses or no rupees left, and its
--     timer out -> sub_080296D8: Link jumps out (jump_status $41, zVelocity
--     1.5, iframes $A6, speed $140 the way he faces), action 5 (60 frames,
--     then action 3).  While held, every $41 frames ModRupees(gUnk_080CCC44
--     [type]: -1 / -5 / -20) and unk_84 1.  Hit while holding: released.
--   OnDeath: EnemyCreateDeathFX(.., gUnk_080CCC34[unk_84 * 3 + type]): an
--     ITEM_RUPEE1 / 5 / 20 drop ($54-$56), one size up once it has drained
--     him ($55-$57).
-- CHUCHU type 1 (the red one, src/enemy/chuchu.c, gUnk_080CA25C):
--   Init (sub_0801F428): action 1 (a puddle, hidden), timer random; type2
--     set: straight to action 3 (subtimer 30, collision on, drawn, anim 2).
--   sub_0801F764 every tick: Link in the home and (seen once or within $48)
--     -> action 1 -> 2: drawn, animation 0 (rising); Link out of the home:
--     action 4 -> sub_0801F730 (sinks: action 7, collision off, anim 5);
--     action 8 -> 9 (animation 7).
--   2 (sub_0801F494): risen -> action 3: subtimer 30, facing Link, collision
--     on, animation 2.  3: subtimer -> action 4.
--   4 (sub_0801F508): every 8th frame with Link within $38: half the time
--     a jump at him (action 5: speed $180, zVelocity 2.0, animation 3), else
--     unk_83 120 and sink (action 7); frame 4 of 8 re-aims; ProcessMovement0.
--   5 (sub_0801F584): frame bit $10 = in the air (frame bit 1 once: hit type
--     91, SFX_12B; ProcessMovement2, GravityUpdate(64/256)); done -> action
--     6 (subtimer 60, speed $20, hit type 92, animation 2) -> back to 4.
--   7 (sub_0801F638): sunk -> action 8 (subtimer 30, animation 1): it slides
--     under the floor toward Link while unk_83 counts (ProcessMovement5),
--     then sub_0801F748: up again (action 2, animation 4).
--   9 (sub_0801F6CC): animation done -> action 1 hidden.  10 (sub_0801F6F8,
--     hit): GravityUpdate(24/256) and animation, done -> action 4, speed $20,
--     animation 2.  OnCollision: health lost / contact $94 -> action 10
--     (collision on, drawn), animation 6; health 0 -> animation 9.
-- SIMPLIFIED: ProcessMovement2 / 5 move like ProcessMovement0 here; the
--   death FX / drops are the port's generic ones; Link's sprite offset
--   inside the Rupee Like (the sprite sub-entry offsets) is not applied.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local C = {}
C.CHUCHU, C.RUPEE_LIKE = 0x01, 0x17
local SFX_PLACE_OBJ, SFX_12B, SFX_RUPEE_GET = 0x104, 0x12B, 0x6F
local RL_PAL = { [0] = 2, 1, 0 }       -- gUnk_080CCC47
local RL_DRAIN = { [0] = -1, -5, -20 } -- gUnk_080CCC44
local RL_DROP = { [0] = 0x54, 0x55, 0x56, 0x55, 0x56, 0x57 } -- gUnk_080CCC34
C.RL_PAL, C.RL_DRAIN, C.RL_DROP = RL_PAL, RL_DRAIN, RL_DROP

local function DW() return require("src.zelda.tmc.EnemyDeepwood") end
local function R(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i); e.flagKey = nil end
local function fflags(e)
  if e.flagKey == e.anim.key then return band(e.anim.flags or 0, 0x80) end
  return e.anim.flags or 0
end
local function take(e) e.flagKey = e.anim.key end
local function done(e) return band(fflags(e), 0x80) ~= 0 or e.anim.done end
local function target(f) return DW().target(f) end
local function dirToLink(f, e) local t = target(f) if not t then return nil end return DW().dirTo(e.x, e.y, t.x, t.y) end
local function inHome(f, e) -- sub_08049FDC(e, 1)
  local t = target(f)
  if not t then return false end
  local dx, dy = math.floor(t.x) - e.homeX, math.floor(t.y) - e.homeY
  return dx >= 0 and dx <= e.rangeW and dy >= 0 and dy <= e.rangeH
end
local function inRange(f, e, d) -- PlayerInRange(e, 1, d)
  local t = target(f)
  if not t or band(t.layer or 1, e.layer or 1) == 0 then return false end
  return (math.floor(t.x) - math.floor(e.x)) ^ 2 + (math.floor(t.y) - math.floor(e.y)) ^ 2 <= d * d
end
local function move0(E, e, dir, spd) if dir and dir ~= 0xFF then DW().move0(E, e, dir, spd) end end

function C.handles(e)
  return (e.id == C.CHUCHU and e.form == 1) or e.id == C.RUPEE_LIKE
end

-- ===========================================================================
-- RUPEE_LIKE
-- ===========================================================================
local function asRupee(E, e) -- sub_080297F0
  local f = E.field
  e.action, e.timer = 1, 120
  e.noTouch, e.hidden = nil, false
  e.hitType = 0x8E
  e.disguised = true
  e.collideOn = true -- COLLISION_ON (its definition starts without collision)
  local O = f:objects()
  local d = O:def(0x00, 0x54 + (e.form or 0)) -- GROUND_ITEM: the ground rupee's sprite and palette (ITEM_RUPEE1 + type)
  if d then
    e.rlSprite, e.rlGfx = d.sprite, require("src.zelda.tmc.Assets").gfxSource(d.gfxType, d.gfx)
    e.rlPalette = f.assets:objPalette(d.palette, f.room.atlas and f.room.atlas.palettes)
  end
  e.rlAnim = e.rlAnim or require("src.zelda.tmc.Anim").new()
  if e.rlSprite then e.rlAnim:set(f.assets:sprite(e.rlSprite), 0x54 + (e.form or 0), true) end
  e.childShown = false
end

local function reveal(E, e) -- sub_08029770
  e.action = 2
  e.noTouch = true
  e.disguised = false
  e.hitType = 0x8D
  e.sprite, e.gfx = 0xD1, 0x73 -- spriteIndex $D1, LoadFixedGFX($73); its palette stays unk_82 (the definition's)
  setAnim(E, e, 2)
  e.childShown = true
  e.childAnim = e.childAnim or require("src.zelda.tmc.Anim").new()
  e.childAnim:set(E.A:sprite(e.sprite), 6, true)
  E.field:addFx(e.x, e.y, 0x0F, 0x02) -- CreateDeathFx
end

local function childAnim(E, e, i)
  e.childAnim = e.childAnim or require("src.zelda.tmc.Anim").new()
  e.childAnim:set(E.A:sprite(e.sprite), i, true)
end
local function frames(e) e.anim:update(1); if e.childAnim then e.childAnim:update(1) end end -- sub_080296C8

local function release(E, e) -- sub_080296D8
  local f = E.field
  local p = f.player
  if p.rupeeLike == e then
    p.rupeeLike = nil
    p.state, p.extUpdate, p.animId, p.hidden = "normal", nil, -1, nil
    local DV = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }
    local v = DV[p.animationState] or DV[4]
    p.z, p.zv = 2, 1.5
    p.jumping = true
    p.invuln = 0xA6
    p.kbx, p.kby, p.timer = v[1] * 0x140 / 256, v[2] * 0x140 / 256, 12
  end
  e.action, e.subtimer = 5, 60
  e.noTouch = nil -- collisionMask |= 3
  if (e.iframes or 0) == 0 then e.iframes = 12 end -- (s8)$F4: 12 frames
end

local function hold(E, e) -- sub_0802953C
  local f = E.field
  local p = f.player
  frames(e); frames(e)
  if f.rlPress then e.subtimer = e.subtimer + 1; f.rlPress = nil end
  if e.timer ~= 0 then e.timer = e.timer - 1 end
  if (e.subtimer > 0x2D or (f.save.stats.rupees or 0) == 0) and e.timer == 0 then
    release(E, e)
    return
  end
  -- ResetActiveItems; gPlayerState.mobility |= $80: Link stays held (a hurt / swing state is cut short)
  if p.state ~= "ext" or p.extUpdate ~= e.holdFn then p.state, p.extUpdate = "ext", e.holdFn end
  p.x, p.y = e.x, e.y + 1
  e.u83 = e.u83 - 1
  if e.u83 == 0 then
    e.u83 = 0x41
    if (f.save.stats.rupees or 0) ~= 0 then
      f:modStat("rupees", RL_DRAIN[e.form or 0] or -1)
      e.u84 = 1
    end
  end
end

function C.rupeeCollision(E, e, fl)
  local f = E.field
  if e.hitType == 0x8E then reveal(E, e) return end
  if e.action == 4 then release(E, e) end
  local k = band(fl, 0x7F)
  if k == 0 or k == 1 then -- contactedEntity is the player
    if e.action == 2 then setAnim(E, e, 0); childAnim(E, e, 4) end
    e.action, e.timer, e.subtimer, e.u83 = 4, 60, 0, 0x41
    e.noTouch = true -- collisionMask &= $FC
    local p = f.player
    p.rupeeLike = e
    p.state = "ext"
    e.holdFn = function(pp, input) -- PlayerInputPressed: any new press counts
      for _, b in ipairs({ "a", "b", "r", "l", "up", "down", "left", "right" }) do
        if input.pressed and input.pressed(b) then f.rlPress = true end
      end
    end
    p.extUpdate = e.holdFn
    f:sound(SFX_PLACE_OBJ)
  end
end

function C.rupeeLike(E, e)
  local f = E.field
  local a = e.action
  e.onCollision = C.rupeeCollision
  if a == 0 then -- sub_0802940C
    e.u81, e.u84 = 0, 0
    asRupee(E, e)
  elseif a == 1 then -- sub_0802944C
    if e.rlAnim then e.rlAnim:update(1) end
    if (e.u81 or 0) ~= 0 and inHome(f, e) then reveal(E, e) end
  elseif a == 2 then -- sub_08029474
    frames(e)
    if band(fflags(e), 0x7F) == 1 then take(e); e.noTouch = nil end -- super->frame == 1: COLLISION_ON
    if done(e) then
      e.action, e.timer = 3, 8
      local dir = dirToLink(f, e) or 16
      e.dir = dir
      e.animationState = rshift(band(dir, 0xFF), 4)
      setAnim(E, e, e.animationState); childAnim(E, e, e.animationState + 4)
    end
  elseif a == 3 then -- sub_080294D4
    if inHome(f, e) then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.timer = 8
        local d = dirToLink(f, e)
        if d then e.dir = d end
        local s = rshift(band(e.dir or 0, 0x1F), 4)
        if band(e.dir or 0, 0x0F) ~= 0 or true then
          if s ~= e.animationState then e.animationState = s; setAnim(E, e, s); childAnim(E, e, s + 4) end
        end
      end
      move0(E, e, e.dir, e.speed ~= 0 and e.speed or 0x80)
      frames(e)
    else
      e.action, e.noTouch = 6, true
      setAnim(E, e, 3); childAnim(E, e, 7)
    end
  elseif a == 4 then hold(E, e)
  elseif a == 5 then -- sub_08029610
    e.subtimer = e.subtimer - 1
    if e.subtimer <= 0 then e.action, e.timer = 3, 1 end
    frames(e)
  elseif a == 6 then -- sub_08029630
    frames(e)
    if done(e) then e.u81 = 1; asRupee(E, e) end
  end
end

-- the two parts (or the rupee)
function C.drawRupeeLike(e, f, camX, camY)
  local A = f.assets
  local x, y = math.floor(e.x - camX), math.floor(e.y - camY - (e.z or 0))
  local function part(spr, an, pal, gfx, key, dy)
    local fr = an and an.frame
    if not spr or not fr or fr == 0xFF then return end
    local img, ox, oy = A:spriteFrame(spr, fr, pal, key, gfx)
    if not img then return end
    if an:hflip() then love.graphics.draw(img, x - ox, y + dy + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + dy + oy) end
  end
  if e.iframes > 0 and e.iframes % 4 < 2 then return end
  if e.disguised then part(e.rlSprite, e.rlAnim, e.rlPalette, e.rlGfx, "rl_rupee", 0) return end
  part(e.sprite, e.anim, e.palette, e.gfx, "rl_body", 0)
  if e.childShown then part(e.sprite, e.childAnim, e.palette, e.gfx, "rl_body", 1) end
end

-- ===========================================================================
-- CHUCHU type 1 (red)
-- ===========================================================================
local function waterTile(E, e) -- CheckWaterTile: ACT_TILE_16
  local f = E.field
  local tt = f.room:tileType(e.layer or 1, math.floor(e.x / 16), math.floor(e.y / 16))
  return tt and tt < 0x4000 and f.assets.actTile and f.assets.actTile[tt] == 0x10
end
local function sink(E, e) e.action, e.noTouch, e.noHit = 7, true, true; setAnim(E, e, 5) end -- sub_0801F730
local function rise(E, e) e.action, e.hidden = 2, false; setAnim(E, e, 4) end            -- sub_0801F748
local function jumpAt(E, e) -- Chuchu_JumpAtPlayer
  e.spd, e.zv = 0x180, 2.0
  e.dir = dirToLink(E.field, e) or e.dir
  setAnim(E, e, 3)
end

function C.redCollision(E, e, fl)
  if e.health > 0 then
    if fl == 0x94 or (e.u80 or e.health) ~= e.health then
      e.action, e.noTouch, e.noHit, e.hidden = 10, nil, nil, false -- sub_0801FB68 (type 1)
      e.zv = 0
      setAnim(E, e, 6)
    end
  else
    e.zv = 0
    setAnim(E, e, 9)
  end
  e.u80 = e.health
end

local function redWatch(E, e) -- sub_0801F764
  local f = E.field
  local a = e.action
  if a == 10 or a == 0 then return end
  if inHome(f, e) then
    if a == 1 and ((e.u82 or 0) ~= 0 or inRange(f, e, 0x48)) then
      e.action, e.hidden, e.u82 = 2, false, 1
      setAnim(E, e, 0)
    end
  elseif a == 4 then sink(E, e)
  elseif a == 8 then e.action = 9; setAnim(E, e, 7) end
end

function C.red(E, e)
  local f = E.field
  e.onCollision = C.redCollision
  redWatch(E, e)
  local a = e.action
  if a == 0 then -- sub_0801F428
    e.action, e.timer = 1, band(R(f), 0xFF)
    e.u80, e.u82 = e.health, 0
    e.hidden, e.noTouch, e.noHit = true, true, true
    if band(e.spawnB or 0, 0xFF) ~= 0 then
      e.action, e.subtimer = 3, 30
      e.hidden, e.noTouch, e.noHit = false, nil, nil
      setAnim(E, e, 2)
    end
  elseif a == 1 then -- sub_0801F48C: GetNextFrame (hidden puddle)
    e.anim:update(1)
  elseif a == 2 then -- sub_0801F494
    e.anim:update(1)
    if done(e) then
      e.action, e.subtimer = 3, 30
      e.dir = dirToLink(f, e) or e.dir
      e.noTouch, e.noHit = nil, nil
      setAnim(E, e, 2)
    end
  elseif a == 3 then -- sub_0801F4EC
    e.anim:update(1)
    e.subtimer = e.subtimer - 1
    if e.subtimer <= 0 then e.action = 4 end
  elseif a == 4 then -- sub_0801F508
    if waterTile(E, e) then e.u83 = 0; sink(E, e)
    else
      e.timer = band((e.timer or 0) + 1, 0xFF)
      local t = band(e.timer, 7)
      if t == 0 and inRange(f, e, 0x38) then
        if band(R(f), 1) ~= 0 then e.action = 5; jumpAt(E, e)
        else e.u83 = 120; sink(E, e) end
      else
        if t == 4 then e.dir = dirToLink(f, e) or e.dir end
        move0(E, e, e.dir, e.spd or e.speed)
        e.anim:update(1)
      end
    end
  elseif a == 5 then -- sub_0801F584
    local fl = fflags(e)
    if band(fl, 0x10) ~= 0 then
      if band(fl, 1) ~= 0 then take(e); e.hitType = 91; f:sound(SFX_12B) end
      move0(E, e, e.dir, e.spd)
      if not DW().gravity(e, 0.25) then e.anim:update(1) end
    else e.anim:update(1) end
    if done(e) then
      if waterTile(E, e) then e.u83 = 0; sink(E, e)
      else
        e.action, e.subtimer, e.spd, e.hitType = 6, 60, 0x20, 92
        setAnim(E, e, 2)
      end
    end
  elseif a == 6 then -- sub_0801F61C
    e.subtimer = e.subtimer - 1
    if e.subtimer <= 0 then e.action = 4 end
    e.anim:update(1)
  elseif a == 7 then -- sub_0801F638
    e.anim:update(1)
    if done(e) then
      e.action, e.subtimer = 8, 30
      e.dir = dirToLink(f, e) or e.dir
      e.hidden = false
      setAnim(E, e, 1)
    end
  elseif a == 8 then -- sub_0801F688
    if (e.u83 or 0) ~= 0 then e.u83 = e.u83 - 1 end
    if waterTile(E, e) or (e.u83 or 0) ~= 0 then
      e.dir = dirToLink(f, e) or e.dir
      move0(E, e, e.dir, e.spd or e.speed)
      e.anim:update(1)
    else rise(E, e) end
  elseif a == 9 then -- sub_0801F6CC
    e.anim:update(1)
    if done(e) then e.action, e.hidden = 1, true; setAnim(E, e, 4) end
  elseif a == 10 then -- sub_0801F6F8
    DW().gravity(e, 24 / 256)
    e.anim:update(1)
    if done(e) then e.action, e.spd = 4, 0x20; setAnim(E, e, 2) end
  end
end

function C.update(E, e)
  if e.id == C.RUPEE_LIKE then
    if not e.drawGhost then e.drawGhost = function(me, f, cx, cy) C.drawRupeeLike(me, f, cx, cy) end end
    return C.rupeeLike(E, e)
  end
  return C.red(E, e)
end

return C
