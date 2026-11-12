-- Round 20: WHIRLWIND ($5E, object/whirlwind.c), PLAYER_PARACHUTE (player.c
-- PlayerParachute, sub_08073468 .. sub_08073884) and EZLO_CAP_FLYING ($61,
-- object/ezloCapFlying.c).  Mt. Crenel's base is crossed this way: a ledge
-- jump through a whirlwind opens Ezlo's cap, Link glides, and pressed against
-- a ledge face he hops up onto the cliff top (sub_0807A2F8).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   Whirlwind_Init: action 1, animationState = type, animation 1; type2 1
--     (Cloud Tops) on the ground, else z = -24 (in the air).
--   Whirlwind_Action1 (GetNextFrame each frame): Link caught when not
--     Minish, within 12 x 12 px (sub_0800419C, x / y only) and
--       - neither parachuting nor jumping: only type2 1, or z <= -16;
--       - parachuting or in PLAYER_JUMP: only off the ground (z != 0).
--     Caught: Link at the whirlwind's x / y, layer 1, PLAYER_PARACHUTE
--     queued (field_0x38 = type2), PutAwayItems, SFX_153 + SFX_PLY_VO5; the
--     whirlwind waits (Action2) until Link is out of its 12 x 12 box.
--   PlayerParachute:
--     0 ANIM_PARACHUTE_ACTIVATE, zVelocity -1.0, timer 480, direction from
--       the facing; the first time PL_PARACHUTE + EZLO_CAP_FLYING.
--     1 GravityUpdate(-gravity / 2) until zVelocity > 0: then 4.5625.
--     2 GravityUpdate(rising: gravity * 2, falling: gravity / 4); falling
--       below z -32: ANIM_PARACHUTE, the glide (3).
--     3 R / iframes / the flag gone: fall (jump_status $40, ANIM_PARACHUTE_FALL).
--       sub_0807A2F8(0) (blocked facing a ledge face whose 1 - 2 tiles are
--       act tiles gUnk_0811C1D8[facing] and the tile past them open): 4.
--       Speed $80, the 32-way direction turns $20 / 256 a frame towards the
--       pad, UpdatePlayerMovement; the facing follows the direction (7 / 32
--       hysteresis, 20 frames of TURN2 animations after a change); 481
--       frames, z = -8 - timer / 20; then the fall.
--     4 up to z -32, 1 px a frame;  5 LinearMoveUpdate (no collision) in the
--       facing's cardinal direction, z += 0.296875 a frame, until the moving
--       axis' coordinate & $F == 8 over an open tile: the fall.
--     (6 / 7 are type2 1's Cloud Tops room change: not used on Mt. Crenel.)
--   The fall (DoJump, jump_status $40): straight down with kGravityRate,
--     ANIM_LAND + SFX_PLY_LAND, normal when the animation ends.
--   EzloCapFlying type 0: affine scales unk_6e (x) / unk_72 (y) ($100 = 1),
--     opening in subAction 1 / 2 (sizes $180 -> $80 / $120 -> $100), then
--     the breathing of sub_080936C8 around $138 - timer / 4; frame 0 facing
--     north / south, 1 east / west (x mirrored facing east).
--   Round 21: the type-1 child (its strings): frame ((direction + direction / 2)
--     >> 2) + 2, at Link with spriteOffsetY = $18 - ($18 * ($10000 / unk_72) >> 8)
--     (sub_0806FCF4 negated), drawn under the cap (Link's child-sprite slot 0
--     vs the cap's slot 1).  The camera target is the cap (type 0), but the
--     cap copies Link's x / y every frame (CopyPosition), so following the cap
--     is following Link -- the port keeps following Link.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local W = {}

W.OBJ = 0x5E
W.CAP = 0x61
local GRAV = 0.125                       -- kGravityRate Q_8_8(32)
local A_ACTIVATE, A_PARA, A_FALL = 0x700, 0x708, 0x730
local A_TURN = { [0] = 0x708, 0x71C, 0x718, 0x714 }   -- sAnims1: none, left, opposite, right
local A_TURN2 = { [0] = 0x708, 0x728, 0x724, 0x720 }  -- sAnims2
local A_LAND, A_LAND_NOCAP = 0x820, 0x424
local SFX_153, SFX_VO5, SFX_124, SFX_LAND = 0x153, 0x79, 0x124, 0x7D
-- gUnk_0811C1D8: the ledge-face act tiles per facing (N, E, S, W)
W.FACE = { [0] = { 42, 38 }, { 45, 39 }, { 43, 38 }, { 44, 39 } }

local SIN = {}
for i = 0, 255 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
local function vec(dir, speed) -- 32-way direction, speed in Q8.8 px
  local a = (dir * 8) % 256
  return SIN[a] * speed / 65536, -SIN[(a + 64) % 256] * speed / 65536
end

local function gravity(p, g) -- GravityUpdate, port z up
  local nz = (p.z or 0) + (p.zv or 0)
  if nz <= 0 then p.z, p.zv = 0, 0 return 0 end
  p.z, p.zv = nz, p.zv - g
  return nz
end

-- ---------------------------------------------------------------------------
-- the whirlwind
-- ---------------------------------------------------------------------------
local function setAnim(d, e, a)
  e.objAnim, e.animIndex = a, a
  e.anim:set(d.field.assets:sprite(e.sprite), a, true)
end

local function near(e, p) return math.abs(e.x - p.x) < 12 and math.abs(e.y - p.y) < 12 end

local function update(d, e)
  local f = d.field
  local p = f.player
  e.anim:update(1)
  if e.action == 1 then
    if p.minish or p.state == "dead" or not near(e, p) then return end
    local jumping = p.state == "ext" and p.ledge ~= nil
    local para = p.para ~= nil
    if not para and not jumping then
      if e.type2 ~= 1 and (p.z or 0) < 16 then return end
    elseif (p.z or 0) == 0 then return end
    p.x, p.y = e.x, e.y
    p.layer = 1
    e.action = 2
    W.start(p, e.type2)
    f:sound(SFX_153); f:sound(SFX_VO5)
  elseif not near(e, p) then
    e.action = 1
  end
end
W.update = update

function W.spawn(d, e)
  if e.id ~= W.OBJ then return nil end
  local f = d.field
  local def = f:objects():def(W.OBJ, e.form or 0)
  if not def then return false end
  f:objects():dress(e, def, 1)
  e.forceAnim = nil
  e.animationState = band(e.form or 0, 7)
  e.action = 1
  e.whirl = true
  if e.type2 ~= 1 then e.z = 24 end
  setAnim(d, e, 1)
  e.extUpdate = function(dd, me) update(dd, me) end
  d:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- PLAYER_PARACHUTE
-- ---------------------------------------------------------------------------
function W.start(p, type2)
  if p.carried then p.field:objects():dropCarried(p) end
  p.ledge = nil
  p.state = "ext"
  p.extUpdate = W.player
  p.para = { sub = 0, type2 = type2 or 0 }
  p.jumping = nil
  p.paraAnim = nil
end

local function clear(p)
  p.para, p.fall, p.cap, p.drawOver, p.paraAnim = nil, nil, nil, nil, nil
end

local function face(p) return band(p.animationState or 4, 6) end

-- sub_0807A2F8(0): blocked facing a ledge face Link can glide up onto;
-- returns the number of tiles (2 or 3) or nil
function W.ledgeUp(p)
  local f = p.field
  local r = f.room
  local s = face(p)
  local hb = require("src.zelda.tmc.Hitboxes").player(f, p)
  local u = hb and hb.u or { 5, 5, 5, 5 }
  local ox = hb and hb.ox or 0
  local oy = hb and hb.oy or 0
  -- sub_08079778: Link's collisions on the facing side
  local d = ({ [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } })[s / 2]
  if not p:blocked(p.x + d[1], p.y + d[2]) then return nil end
  local x, y = math.floor(p.x), math.floor(p.y)
  local ax, ay, bx, by
  if band(s, 2) ~= 0 then ax, ay, bx, by = x, y - u[4], x, y + u[4]
  else ax, ay, bx, by = x - u[1], y, x + u[1], y end
  local at, bt = { math.floor(ax / 16), math.floor(ay / 16) }, { math.floor(bx / 16), math.floor(by / 16) }
  local list = W.FACE[s / 2]
  local coll = r.coll and r.coll[1] or {}
  local function collAt(t) return coll[t[2] * r.tw + t[1]] or 0 end
  local function open(t) return collAt(t) == 0 or not r:isSolidPlayer(t[1] * 16 + 8, t[2] * 16 + 8, 1, 0) end
  local function face(t)
    local tt = r:tileType(p.layer or 1, t[1], t[2])
    local act = tt and tt < 0x4000 and f.assets.actTile[tt] or nil
    if not act and tt and tt >= 0x4000 then act = nil end
    return act == list[1] or act == list[2]
  end
  local n = 0
  for i = 0, 1 do
    at[1], at[2], bt[1], bt[2] = at[1] + d[1], at[2] + d[2], bt[1] + d[1], bt[2] + d[2]
    local free = 0
    if collAt(at) ~= 0 and not open(at) then if not face(at) then break end else free = free + 1 end
    if collAt(bt) ~= 0 and not open(bt) then if not face(bt) then break end else free = free + 1 end
    if free == 2 then
      if i ~= 0 then break end
      return nil
    end
    n = i + 1
  end
  if n == 0 then return nil end
  if n == 2 then
    at[1], at[2], bt[1], bt[2] = at[1] + d[1], at[2] + d[2], bt[1] + d[1], bt[2] + d[2]
  end
  if open(at) and open(bt) then return n + 1 end
  return nil
end

local function dirInput(input)
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  if dx == 0 and dy == 0 then return nil end
  -- the 32-way direction of the pad (DIR_NORTH 0 .. DIR_NORTH_WEST 28)
  local t = { [-1] = { [-1] = 28, [0] = 24, [1] = 20 }, [0] = { [-1] = 0, [1] = 16 }, [1] = { [-1] = 4, [0] = 8, [1] = 12 } }
  return t[dx][dy]
end

local function release(p, cancel)
  p.para = nil
  p.fall = { sub = 1, cancel = cancel }
  if cancel then p:setAnim(A_FALL, true) end
  p.zv = 0
end

local function fallUpdate(p)
  local fl = p.fall
  local f = p.field
  if fl.sub == 1 then
    p.anim:update(1)
    if gravity(p, GRAV) > 0 then return end
    local Lay = require("src.zelda.tmc.Layers")
    p.layer = Lay.resolve(f, p)
    Lay.update(f, p)
    fl.sub, fl.timer = 2, 6
    p:setAnim(p.hasCap and A_LAND or A_LAND_NOCAP, true)
    f:sound(SFX_LAND)
  else
    p.anim:update(1)
    fl.timer = fl.timer - 1
    if p.anim.done or fl.timer <= 0 then
      p.x, p.y = math.floor(p.x), math.floor(p.y)
      clear(p)
      p.state = "normal"
      p.extUpdate = nil
    end
  end
end

-- Player:hurt while gliding / falling: the iframes end the glide (sub_08073584)
-- and Link falls where he is; false when the hit kills him (normal path)
function W.hurt(p)
  if (p.field.save.stats.health or 0) <= 0 then
    clear(p); p.z, p.zv = 0, 0; p.extUpdate = nil
    return false
  end
  p.invuln = 60
  if p.para then release(p, true) end
  return true
end

function W.player(p, input)
  if p.fall then return fallUpdate(p) end
  local pa = p.para
  local f = p.field
  if not pa then p.state = "normal"; p.extUpdate = nil return end
  local s = pa.sub
  if s == 0 then
    p:setAnim(A_ACTIVATE, true)
    p.zv = -1.0
    pa.sub = 1
    pa.timer = 480
    pa.dir = (p.animationState or 4) * 4
    if not p.cap then W.capNew(p) end
  elseif s == 1 then
    gravity(p, -GRAV / 2)
    if p.zv > 0 then p.zv = 4.5625; pa.sub = 2 end
  elseif s == 2 then
    gravity(p, p.zv < 0 and GRAV / 4 or GRAV * 2)
    if p.zv < 0 and p.z < 32 then
      pa.sub = 3
      pa.d80 = pa.dir * 256
      pa.b3, pa.b2 = 0, 0
      p:setAnim(A_PARA, true)
    end
    p.anim:update(1)
  elseif s == 3 then
    if input.pressed("r") or (p.invuln or 0) > 0 then release(p, true) return end
    local n = W.ledgeUp(p)
    if n then
      pa.sub = 4
      pa.dir = face(p) * 4
      return
    end
    local want = dirInput(input)
    if want and want ~= pa.dir then
      if band(pa.dir - want, 0x1F) < 16 then pa.d80 = pa.d80 - 0x20 else pa.d80 = pa.d80 + 0x20 end
      pa.d80 = pa.d80 % 0x2000
    end
    pa.dir = band(rshift(pa.d80, 8), 0x1F)
    local vx, vy = vec(pa.dir, 0x80)
    p:moveBy(vx, vy)
    -- the facing follows the direction
    local st, dir = 4 * p.animationState, pa.dir
    if p.animationState == 0 then st = band(st + 8, 0x1F); dir = band(dir + 8, 0x1F) end
    local ns
    if st - 7 > dir then ns = band(p.animationState - 2, 7)
    elseif st + 7 < dir then ns = band(p.animationState + 2, 7)
    else ns = p.animationState end
    if ns ~= p.animationState then pa.b3 = 20 end
    p.animationState = ns
    local inState = want and rshift(want, 2)
    local idx = 0
    if pa.b3 == 0 or (want and p.animationState ~= inState) then
      if want and p.animationState ~= inState then
        if p.animationState == bit.bxor(inState, 4) then idx = 2
        elseif p.animationState == band(band(inState, 6) + 2, 7) then idx = 1
        else idx = 3 end
      end
      if p.paraAnim == A_TURN[idx] then p.anim:update(1) else p:setAnim(A_TURN[idx], true); p.paraAnim = A_TURN[idx] end
      pa.b2 = idx
    else
      pa.b3 = pa.b3 - 1
      local a = A_TURN2[pa.b2]
      if p.paraAnim == a then p.anim:update(1) else p:setAnim(a, true); p.paraAnim = a end
    end
    pa.timer = pa.timer - 1
    if pa.timer == -1 then release(p, false) return end
    p.z = 8 + math.floor(pa.timer / 20)
    require("src.zelda.tmc.Layers").update(f, p)
  elseif s == 4 then
    if p.z < 32 then p.z = p.z + 1 else pa.sub = 5 end
  elseif s == 5 then
    p.anim:update(1)
    local vx, vy = vec(pa.dir, 0x80)
    p.x, p.y = p.x + vx, p.y + vy
    p.z = p.z - 0.296875
    local pos = band(pa.dir, 8) ~= 0 and math.floor(p.x) or math.floor(p.y)
    if band(pos, 0xF) == 8 and not f.room:isSolidPlayer(p.x, p.y, p.layer or 1, 0) then release(p, false) end
  end
  if p.cap then W.capUpdate(p) end
end

-- ---------------------------------------------------------------------------
-- EZLO_CAP_FLYING (type 0)
-- ---------------------------------------------------------------------------
function W.capNew(p)
  local f = p.field
  local def = f:objects():def(W.CAP, 0)
  p.cap = { s6e = 0x180, s72 = 0x180, sub = 0, timer = 0, def = def }
  p.drawOver = W.capDraw
end

function W.capUpdate(p)
  local c, pa = p.cap, p.para
  if not pa then return end
  local s = pa.sub
  if c.s6e < 0 then c.s6e = -c.s6e end
  if s == 1 then c.s72 = c.s72 - 4
  elseif s == 2 then
    if c.sub == 0 then
      if c.s72 > 0x80 then c.s72 = c.s72 - 0x20 else c.sub = 1; p.field:sound(SFX_124) end
      if c.s6e < 0x120 then c.s6e = c.s6e + 0x40 end
    elseif c.sub ~= 0xFF then
      c.s72 = math.min(0x100, c.s72 + 0x20)
      c.s6e = c.s6e > 0x100 and c.s6e - 0x20 or 0x100
      if c.s6e == 0x100 then c.sub = 0xFF end
    else W.breathe(p) end
  else W.breathe(p) end
end

-- sub_080936C8
function W.breathe(p)
  local c, pa = p.cap, p.para
  local t = math.max(0, pa.timer or 0)
  local u76 = 0x138 - rshift(t, 2)
  if c.timer == 0 then
    if u76 < c.s6e then c.s6e = c.s6e - 8; c.s72 = c.s72 + 8
    else c.timer = 1; c.s6e = u76; c.s72 = u76 + 0x30 end
  else
    if u76 + 0x30 > c.s6e then c.s6e = c.s6e + 8; c.s72 = c.s72 - 8
    else c.timer = 0; c.s6e = u76 + 0x30; c.s72 = u76 end
  end
end

function W.capDraw(p, x, y)
  local c = p.cap
  if not c or not c.def or not p.para then return end
  local f = p.field
  local A = f.assets
  local frame = band(p.animationState or 4, 2) ~= 0 and 1 or 0
  -- round 21: EzloCapFlying_Action1Type1, the strings
  do
    local d = band(p.para.dir or 0, 0x1F)
    local sf = rshift(d + rshift(d, 1), 2) + 2
    local simg, sox, soy = A:spriteFrame(c.def.sprite, sf, A:objPalette(0x16), "link")
    if simg then
      local p2 = rshift(0x18 * math.floor(0x10000 / math.max(0x40, math.abs(c.s72))), 8)
      love.graphics.draw(simg, x + sox, y + soy + (0x18 - p2))
    end
  end
  local img, ox, oy = A:spriteFrame(c.def.sprite, frame, A:objPalette(0x16), "link")
  if not img then return end
  -- an affine OBJ: the scale ($100 = 1, larger = smaller) about the frame's
  -- middle; sub_0806FCF4(cap, unk_72, 10, 2) keeps its bottom on Link's head
  local sx, sy = 256 / math.max(0x40, math.abs(c.s6e)), 256 / math.max(0x40, c.s72)
  if p.animationState == 2 then sx = -sx end
  local w, h = img:getDimensions()
  local offY = 10 - math.floor(10 * math.floor(0x10000 / math.max(0x40, c.s72)) / 256)
  love.graphics.draw(img, x + ox + w / 2, y + oy + h / 2 + offY, 0, sx, sy, w / 2, h / 2)
end

return W
