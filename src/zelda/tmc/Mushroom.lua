-- Round 11: PULLABLE_MUSHROOM ($32) and the fling it gives Link.
--
-- CARTRIDGE BEHAVIOUR (src/object/pullableMushroom.c, src/player.c
-- sub_08072C9C, src/item/itemTryPickupObject.c):
--   * Type 0 sits on its tile (SPECIAL_TILE_34, solid) and registers as a
--     carry entity: Link grabs it with R facing it (ANIM_GRAB).
--   * Grabbed (Action2 / sub_0808AEB0): the mushroom's state is the
--     opposite of Link's facing (AnimationStateFlip90 = ^2), its direction
--     state << 3; Link is lined up on its axis; it plays animation
--     state + 5 and makes its cap (type 1, at Link's hands) and stem
--     (type 2, scaled between them).  While the way away from it is held
--     (gUnk_081211E4: up / right / down / left by state) Link backs off at
--     speed $40 while the stretch is under $40 px (SFX_12F every 5
--     frames), playing ANIM_PULL.  Letting go of R puts it back
--     (sub_0808AFD4, SFX_130).
--   * Letting go of the direction after pulling queues PLAYER_08072C9C with
--     field_0x38 = the stretch, field_0x39 = the direction toward the
--     mushroom, field_0x3a = Link's distance from it:
--       1. Link flies back to it at speed $400 for (distance >> 2) + 1
--          frames (ANIM_GUSTJAR_524), collision off;
--       2. then he is launched: zVelocity = max(stretch, 8) << 12, speed
--          $200, ANIM_JUMP; 5 frames of straight movement, then movement
--          that stops at walls (UpdatePlayerMovement); gravity kGravityRate;
--       3. landing: ANIM_LAND, SFX_PLY_LAND, back to normal.
--   * The cap and stem spring back toward the mushroom at speed $400
--     (sub_0808ADA0), then the mushroom wobbles (animation state + 1, then
--     state + $D, SFX_12E) and is grabbable again.
-- The cap and stem are drawn from the mushroom's own sprite frames
-- ($0F/$10 sideways, $14/$15 up-down) with sub_0808ABC4's affine scales,
-- angle and offsets (round 14: the half turn for states 0 / 3, the stem
-- under the cap and body).  SIMPLIFIED: the ledge tiles $1AC-$1AF that
-- let a flight pass over a ledge are not checked (the 5 straight frames
-- are).
local bit = require("bit")
local band, bxor = bit.band, bit.bxor

local M = {}

local OBJ_MUSHROOM = 0x32
local ANIM_GRAB, ANIM_PULL, ANIM_JUMP, ANIM_LAND = 0x378, 0x340, 0x810, 0x820
local ANIM_PULL_NOCAP, ANIM_LAND_NOCAP, ANIM_GUST524 = 0x944, 0x424, 0x524
local SFX_12E, SFX_12F, SFX_130, SFX_PLY_LAND = 0x12E, 0x12F, 0x130, 0x7D
local AWAY_KEY = { [0] = "up", [1] = "right", [2] = "down", [3] = "left" }
local GRAV = 0.125

local SIN = {}
for i = 0, 255 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
local function linear(o, dir, speed)
  local a = (dir * 8) % 256
  return SIN[a] * speed / 65536, -SIN[(a + 64) % 256] * speed / 65536
end

-- sub_0808B1F0: distance along the mushroom's axis
local function axisDist(e, x, y)
  if band(e.st or 0, 1) ~= 0 then return math.abs(math.floor(e.x) - math.floor(x)) end
  return math.abs(math.floor(e.y) - math.floor(y))
end

local function setAnim(f, e, idx)
  if e.animIndex ~= idx then
    e.animIndex = idx
    e.objAnim = idx
    e.anim:set(f.assets:sprite(e.sprite), idx, true)
  end
end

-- ---------------------------------------------------------------------------
-- Link's side: holding on, then PLAYER_08072C9C
-- ---------------------------------------------------------------------------
local function endHold(p)
  p.state = "normal"
  p.extUpdate = nil
  p.holdMush = nil
  p:setAnim(p:animFor("idle"), true)
end

-- round 22: sub_08072D54 after the 5 straight frames: the tile ahead
-- (sub_0806F730: gPlayerHitbox offset (0, -3), + unk2 5 px the way Link
-- faces) is looked up in sTileTable[facing / 2] ($1AD up, $1AE right, $1AC
-- down, $1AF left).  subtimer 0: on such a tile -> straight (no collision)
-- and 1; 1: straight while on it, else 2; 2: the same with the OPPOSITE
-- facing's tile (the far edge) -> 3; 3: straight while on it, else 4.
local LEDGE_TILE = { [0] = 0x1AD, 0x1AE, 0x1AC, 0x1AF }
function M.ledgePass(p, fl)
  local f = p.field
  local s = p.animationState or 0
  local x, y = math.floor(p.x), math.floor(p.y) - 3
  if s == 0 then y = y - 5 elseif s == 4 then y = y + 5 elseif s == 2 then x = x + 5 elseif s == 6 then x = x - 5 end
  local tt = f.room and f.room:tileType(p.layer or 1, math.floor(x / 16), math.floor(y / 16))
  local function on(st) return tt == LEDGE_TILE[band(st, 7) / 2] end
  local sub = fl.ledgeSub or 0
  local pass = false
  if sub == 0 then if on(s) then pass = true; fl.ledgeSub = 1 end
  elseif sub == 1 then if on(s) then pass = true else fl.ledgeSub = 2 end
  elseif sub == 2 then if on(bxor(s, 4)) then pass = true; fl.ledgeSub = 3 end
  elseif sub == 3 then if on(bxor(s, 4)) then pass = true else fl.ledgeSub = 4 end end
  return pass
end

local function fling(p, input)
  local fl = p.fling
  local f = p.field
  if fl.phase == 1 then
    -- sub_08072CFC: back to the mushroom at $400
    if fl.t > 0 then
      fl.t = fl.t - 1
      local dx, dy = linear(p, fl.dir, 0x400)
      p.x, p.y = p.x + dx, p.y + dy
      p.anim:update(2)
      return
    end
    fl.phase = 2
    p.zv = math.max(fl.stretch, 8) * 4096 / 65536
    p.z = p.z or 0
    fl.t = 5
    p:setAnim(ANIM_JUMP, true)
    return
  end
  if fl.phase == 2 then
    p.anim:update(1)
    local dx, dy = linear(p, fl.dir, 0x200)
    if fl.t > 0 then
      fl.t = fl.t - 1
      p.x, p.y = p.x + dx, p.y + dy
    elseif M.ledgePass(p, fl) then -- round 22: sub_08072D54's ledge tiles $1AC-$1AF
      p.x, p.y = p.x + dx, p.y + dy
    else
      p:moveBy(dx, dy)
    end
    local nz = (p.z or 0) + p.zv
    if nz <= 0 then
      p.z, p.zv = 0, 0
      fl.phase = 3
      fl.t = 6
      p:setAnim(p.hasCap and ANIM_LAND or ANIM_LAND_NOCAP, true)
      f:sound(SFX_PLY_LAND)
    else
      p.z, p.zv = nz, p.zv - GRAV
    end
    return
  end
  -- sub_08072F14
  p.fling = nil
  p.jumping = nil
  endHold(p)
end

local function hold(p, input)
  local e = p.holdMush
  local f = p.field
  if not e or e.deleted then return endHold(p) end
  if not input.down("r") then
    -- R let go: sub_0808AFD4, the cap springs back
    e.mode = "return"
    f:sound(SFX_130)
    return endHold(p)
  end
  local key = AWAY_KEY[e.st]
  local stretch = axisDist(e, p.x, p.y)
  if input.down(key) then
    p:setAnim(p.hasCap and ANIM_PULL or ANIM_PULL_NOCAP)
    p.anim:update(1)
    if stretch < 0x40 then
      local dx, dy = linear(p, e.dir, 0x40)
      p:moveBy(dx, dy)
      e.sndT = (e.sndT or 1) - 1
      if e.sndT < 0 then e.sndT = 4; f:sound(SFX_12F) end
    end
    e.pulled = true
  elseif e.pulled then
    -- PLAYER_08072C9C
    e.mode = "return"
    f:sound(SFX_130)
    local toward = bxor(e.dir, 0x10)
    p.fling = { phase = 1, dir = toward, stretch = stretch, t = math.floor(axisDist(e, p.x, p.y) / 4) + 1 }
    p.holdMush = nil
    p.jumping = true
    p.extUpdate = fling
    p:setAnim(ANIM_GUST524, true)
  else
    p:setAnim(ANIM_GRAB)
    e.pulled = nil
  end
end

-- ---------------------------------------------------------------------------
-- the mushroom
-- ---------------------------------------------------------------------------
local function update(d, e, input)
  local f = d.field
  local p = f.player
  e.anim:update(1)
  if e.mode == "hold" then
    if p.holdMush ~= e then e.mode = "return" end
    e.cx, e.cy = p.x, p.y - 4
    return
  end
  if e.mode == "return" then
    -- sub_0808ADA0: the cap comes back at $400 until within 8 px
    local dx, dy = linear(e, bxor(e.dir, 0x10), 0x400)
    e.cx, e.cy = (e.cx or e.x) + dx, (e.cy or e.y) + dy
    if axisDist(e, e.cx, e.cy) < 8 then
      e.mode = "wobble"
      e.wob = 0
      e.cx, e.cy = nil, nil
      setAnim(f, e, band(e.st, 3) + 1)
      f:sound(SFX_12E)
    end
    return
  end
  if e.mode == "wobble" then
    if e.anim.done then
      if e.animIndex == band(e.st, 3) + 1 then setAnim(f, e, band(e.st, 3) + 0xD)
      else e.mode = nil; setAnim(f, e, 0) end
    end
    return
  end
  -- round 16: the Gust Jar (PullableMushroom_Action3)
  if e.mode == "jar" then return M.jarUpdate(f, e, p) end
  if not e.mode and p.jar and require("src.zelda.tmc.GustJar").touching(f, e.x, e.y, 8, 8) then return M.jarStart(f, e, p) end
  -- idle: R facing it grabs it
  if p.state ~= "normal" or p.minish or (p.z or 0) > 0 or not input.pressed("r") then return end
  local fx, fy = p:frontPoint(8)
  if math.floor(fx / 16) ~= e.tx or math.floor(fy / 16) ~= e.ty then return end
  e.st = bxor(math.floor(p.animationState / 2), 2)
  e.dir = e.st * 8
  e.mode = "hold"
  e.pulled = nil
  setAnim(f, e, e.st + 5)
  if band(e.st, 1) ~= 0 then p.y = e.y else p.x = e.x end
  p.state = "ext"
  p.extUpdate = hold
  p.holdMush = e
  p:setAnim(ANIM_GRAB, true)
  input.consume = true
end

-- Round 16: the Gust Jar on a mushroom (pullableMushroom.c Action1_Type0
-- case $13, PullableMushroom_Action3, sub_0808B05C / sub_0808B0BC):
--   * sucked (contactFlags $13), the mushroom turns to face Link
--     (AnimationStateFlip90 of his facing), plays animation state + 5 and
--     makes its cap (type 1, type2 1: itself sucked) and stem;
--   * each frame the cap creeps toward Link at speed $40 while the stretch
--     (its distance from the mushroom along the axis) is under $40; when
--     the jar's mouth (Link + gUnk_08126EE4) is within 7x7 of the cap, Link
--     is flung exactly as by a pull (PLAYER_08072C9C: field_0x38 = the
--     stretch, field_0x39 = toward the mushroom, field_0x3a = his distance);
--   * the jar stops sucking (or the gust leaves the cap) first: the cap
--     springs back (SFX_130).
function M.jarStart(f, e, p)
  local GJ = require("src.zelda.tmc.GustJar")
  e.st = bxor(math.floor((p.animationState or 4) / 2), 2)
  e.dir = e.st * 8
  e.mode = "jar"
  e.pulled = nil
  e.cx, e.cy = e.x, e.y
  setAnim(f, e, e.st + 5)
  local _ = GJ
end

function M.jarUpdate(f, e, p)
  local GJ = require("src.zelda.tmc.GustJar")
  local j = p.jar
  local stretch = axisDist(e, e.cx, e.cy)
  local sucking = j and j.state == "suck" and GJ.touching(f, e.cx, e.cy, 8, 8)
  if not sucking then
    e.mode = "return"
    f:sound(SFX_130)
    return
  end
  local mx, my = GJ.mouth(p)
  if math.abs(mx - e.cx) <= 7 and math.abs(my - e.cy) <= 7 then
    if p.state ~= "gust" and p.state ~= "normal" then return end
    -- PLAYER_08072C9C
    e.mode = "return"
    f:sound(SFX_130)
    p.jar, p.jarKick = nil, nil
    p.state = "ext"
    p.fling = { phase = 1, dir = bxor(e.dir, 0x10), stretch = stretch, t = math.floor(axisDist(e, p.x, p.y) / 4) + 1 }
    p.jumping = true
    p.extUpdate = fling
    p:setAnim(ANIM_GUST524, true)
    return
  end
  if stretch < 0x40 then
    local dx, dy = linear(e, e.dir, 0x40)
    e.cx, e.cy = e.cx + dx, e.cy + dy
  end
end

-- the stem between the mushroom and the cap (type 2, sub_0808ABC4)
local function drawStem(f, e, camX, camY)
  local A = f.assets
  if not e.cx then return end
  local tmp = axisDist(e, e.cx, e.cy)
  if tmp < 8 then tmp = 0 end
  local horiz = band(e.st, 1) ~= 0
  local sx, sy, frame, px, py
  -- gUnk_081211CC[state]: { u16 angle, x, y }: states 0 and 3 turn the
  -- stem half a turn ($8000)
  local off = ({ [0] = { 0, -6 }, [1] = { 5, -4 }, [2] = { 0, 0 }, [3] = { -5, -4 } })[e.st]
  local rot = (e.st == 0 or e.st == 3) and math.pi or 0
  if tmp < 0x20 then
    if tmp ~= 0 then tmp = tmp - 6 end
    px, py = e.x + off[1], e.y + off[2]
    if horiz then sx, sy, frame = 0x200 - tmp * 16, tmp * 8 + 0x120, 0x0F
    else sy, sx, frame = 0x200 - tmp * 16, tmp * 8 + 0x120, 0x14 end
  elseif horiz then
    sx, sy, frame = 0x100 - 4 * (tmp - 0x20), tmp * 8 + 0x140, 0x10
    px, py = e.x + ((band(e.st, 2) ~= 0) and -math.floor(tmp / 2) or math.floor(tmp / 2)), e.y + off[2]
  else
    sy, sx, frame = 0x100 - 4 * (tmp - 0x20), tmp * 8 + 0x140, 0x15
    px, py = e.x + off[1], e.y + ((band(e.st, 2) ~= 0) and math.floor(tmp / 2) or -math.floor(tmp / 2)) + off[2]
  end
  local img, ox, oy = A:spriteFrame(e.sprite, frame, e.palette, "mush", e.gfx)
  if not img then return end
  local w, h = img:getWidth(), img:getHeight()
  local cx, cy = math.floor(px - camX) + ox + w / 2, math.floor(py - camY) + oy + h / 2
  -- SetAffineInfo(x scale, y scale, angle): $100 = 1x (the matrix is the
  -- inverse), the double-size OBJ centred where the frame would sit
  love.graphics.draw(img, cx, cy, rot, 256 / math.max(sx, 16), 256 / math.max(sy, 16), w / 2, h / 2)
end

local function draw(e, f, camX, camY)
  local A = f.assets
  -- the stem (type 2) has spritePriority.b0 5: under the mushroom and cap (4)
  if e.cx and e.st then drawStem(f, e, camX, camY) end
  local frame = e.anim.frame
  if frame and frame ~= 0xFF then
    local img, ox, oy = A:spriteFrame(e.sprite, frame, e.palette, "mush", e.gfx)
    if img then
      local x, y = math.floor(e.x - camX), math.floor(e.y - camY) + 4 -- spriteOffsetY 4
      if e.anim:hflip() then love.graphics.draw(img, x - ox, y + oy, 0, -1, 1) else love.graphics.draw(img, x + ox, y + oy) end
    end
  end
  if e.cx and e.st then
    -- the cap (type 1): animation state + 9's first frame at the cap's place
    local spr = A:sprite(e.sprite)
    local keys = spr and spr.anims and spr.anims[e.st + 9]
    local cf = keys and keys[1] and keys[1][1]
    if cf then
      local img, ox, oy = A:spriteFrame(e.sprite, cf, e.palette, "mush", e.gfx)
      if img then love.graphics.draw(img, math.floor(e.cx - camX) + ox, math.floor(e.cy - camY) + oy) end
    end
  end
end

-- Dungeon:spawnObject hook: type 0 from a room list
function M.spawn(d, e)
  if e.id ~= OBJ_MUSHROOM or (e.form or 0) ~= 0 then return nil end
  local def = d.field:objects():def(OBJ_MUSHROOM, 0)
  if def then d.field:objects():dress(e, def, 0) end
  e.objAnim = 0
  e.animIndex = 0
  -- round 14 (user bug: invisible until pulled): the entity's frame is
  -- frame 0 from the start on the cartridge (a fresh entity; Action1's
  -- sub_0808ACEC keeps animation 0); the port's Anim starts blank ($FF)
  -- until set, and only the wobble after a pull ever set it
  local A = d.field.assets
  if A and A.sprite then e.anim:set(A:sprite(e.sprite), 0, true) end
  -- PullableMushroom_Init: ChangeObjPalette(super, 0) outside dungeons
  local a = d.field.room and d.field.room.area
  if a and A and A.objPalette and not (a >= 0x48 and a < 0x80) then
    e.palette = d.field.assets:objPalette(0, d.field.room.atlas and d.field.room.atlas.palettes)
  end
  e.mushroom = true
  e.tx, e.ty = math.floor(e.x / 16), math.floor(e.y / 16)
  d:block(e.tx, e.ty, e.layer, true)
  e.extUpdate = update
  e.drawGhost = draw
  e.st = 2
  d:track(e)
  return e
end

return M
