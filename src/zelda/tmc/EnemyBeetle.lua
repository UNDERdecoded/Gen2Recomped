-- Round 21: Spiny Beetle with its rock (enemy/spinyBeetle.c,
-- object/objectOnSpinyBeetle.c) and Rollobite (enemy/rollobite.c).
--
-- SPINY_BEETLE ($35)
--   Init: x / y snapped to the tile's middle (| 8), the tile under it saved
--     and replaced by SPECIAL_TILE_34 ($4022, solid), an OBJECT_ON_BEETLE
--     ($7D, type = the beetle's type: 0 bush, 1 rock) made as its child; a
--     rock beetle gets hitType $63 ($95 with the Rock Breaker skill).
--   Action 1 (sub_08033958): hidden under its tile.  The rock gone
--     (sub_08033DF0: no child, or the child lifted / pulled / flipped) ->
--     exposed (sub_08033E1C).  After a burrow it waits $78 frames.  Then
--     sub_0804A024(.., $10): Link lined up within 8 px on an axis with an
--     open line (collision) between -> that direction; within $30 px along
--     it (north only after the first pop) -> Action 2: shown, collision on,
--     y | $C, the tile put back, animation 2.
--   Action 2: animation 2 to its end -> Action 3 (timer 120, subtimer 32,
--     animation 3).  Action 3: GetNextFrame twice; subtimer, then timer;
--     each frame sub_08033D78 (one ProcessMovement0 step unless the tile
--     ahead is $1C4 / $1C5 or solid); at 0 -> Action 4 (timer 120,
--     animation 4, home = here).  Action 4: at 0 -> hidden again in the
--     first tile backwards that is not SPECIAL_TILE_34, which becomes one.
--   Action 5 (exposed, sub_08033C94): hitType $19, speed $100, the "!"
--     bubble; 48 frames, then away from Link (facing + $14, a quarter turn
--     either way one time in 4, & $18) for 120 frames, then new turns every
--     32..63 frames.
--   OnCollision: contact while it still has its rock and iframes -> exposed;
--     hurtType $14 -> Action 3 (timer 90, subtimer 16) towards Link.
-- OBJECT_ON_BEETLE ($7D)
--   Rides on the beetle (z = gUnk_08123558[frame & $F] - 8 while the beetle
--   collides, else on the ground 3 px lower).  Liftable (RegisterCarryEntity):
--   lifted = the beetle exposed; thrown it breaks (FX_BUSH + type: FX_ROCK
--   for a rock).  The Gust Jar (contact $13): tolerance $30, wiggle; at 0 it
--   leaves the beetle and is pulled to the jar's mouth: a bush is swallowed,
--   a rock (gustJarFlags 2) is held and shot (it breaks where the shot ends);
--   contact lost after it left -> it breaks.  A bomb's blast ($0F) or the
--   Cane ($1D) flips it off (zVelocity 2.625, gravity 32) and it breaks.
-- ROLLOBITE ($04)
--   Walk (animation by direction, a step of ProcessMovement0 on each key
--   frame with bit 1, the timer counted on bit $10), Turn (60 frames),
--   sub_08020A30's pick (gUnk_080CA6CC: 0 = a turn, at most twice) and
--   sub_08020A7C's direction (+-8 or straight, not back towards home when
--   out of it).  OnCollision with hitType 34: rolled up (zVelocity 2.0,
--   health $FF, hitType 35, animation + 8); a contact other than Link's body
--   -> rolled for 180 frames (animation + $10).  Rolled: BounceUpdate(40),
--   then liftable; unroll (animation + 12) -> walking again (hitType 34,
--   speed $100).  Rolled up on a hole tile ($71 / $72) it drops in
--   (animation + $14, SPECIAL_TILE_52 ($4034) fills the hole).  Carried
--   and thrown (the carry system) it lands rolled up; the Gust Jar
--   catches it (gustJarFlags 18) and shoots it; the shot's end rolls it up
--   (subaction 5: direction reversed, zVelocity 1.5, speed $80).
-- SIMPLIFIED: the line-of-sight test (sub_0804A168 / sub_0804A318) reads the
--   collision of the tiles between (any non-zero blocks); a bush beetle's
--   bush is not cut by the sword; the throw uses the port's carry arc.
local bit = require("bit")
local band, bor = bit.band, bit.bor

local B = {}
B.SPINY, B.ROLLOBITE, B.OBJ_ON_BEETLE = 0x35, 0x04, 0x7D
local SPECIAL_TILE_34, SPECIAL_TILE_52 = 0x4022, 0x4034
local FX_BUSH, FX_STARS = 3, 0x1C
local ROCK_Z = { [0] = 1, 2, 2, 2, 0, -3, -3, -4, -3, -4, -3, -3, -3, 0, 0, 0 } -- gUnk_08123558
local AHEAD = { [0] = { 0, -8 }, [2] = { 8, 0 }, [4] = { 0, 8 }, [6] = { -8, 0 } } -- gUnk_080CEC1C
local RB_PICK = { [0] = 0, 6, 9, 0, 6, 6, 0, 7 }                                  -- gUnk_080CA6CC
local RB_TURN = { [0] = 8, -8, 0 }                                                  -- gUnk_080CA6D4
local SFX_PLACE_OBJ = 0x104

local function D() return require("src.zelda.tmc.Drops") end
local function R(f) return D().random(D().rngOf(f)) end
local function dirTo(ax, ay, bx, by)
  local a = math.atan2(bx - ax, -(by - ay))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
local function round8(d) return band(d + 4, 0x18) end -- DirectionRound
local function move0(E, e, dir, spd) return require("src.zelda.tmc.EnemyDeepwood").move0(E, e, dir, spd) end
local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function target(f) return require("src.zelda.tmc.EnemyDeepwood").target(f) end

function B.handles(e) return e.id == B.SPINY or e.id == B.ROLLOBITE end

-- ===========================================================================
-- the rock / bush (OBJECT_ON_BEETLE)
-- ===========================================================================
local function rockBreak(f, r)
  if r.deleted then return end
  r.deleted = true
  f:addFx(r.x, r.y - (r.z or 0), 0x0F, FX_BUSH + (r.form or 0))
  f:sound(0x11C)
  local par = r.parentBeetle
  if par and par.child == r then par.child = nil end
end
B.rockBreak = rockBreak

local function makeRock(E, e)
  local f = E.field
  local O = f:objects()
  local d = O:def(B.OBJ_ON_BEETLE, e.form or 0)
  local r = { kind = 6, id = B.OBJ_ON_BEETLE, form = e.form or 0, x = e.x, y = e.y, z = 0, layer = e.layer,
              field82 = 0, interactType = 0, animationState = 0, beetleRock = true, parentBeetle = e,
              liftable = true, rockAct = 1 }
  if d then O:dress(r, d, e.form or 0) else r.anim = require("src.zelda.tmc.Anim").new() end
  r.staticFrame = 0 -- no InitializeAnimation: frameIndex 0 (the def's palette tells bush from rock)
  r.onShotEnd = function(ff, x) x.jarSub = nil; rockBreak(ff, x) end
  f.entities[#f.entities + 1] = r
  return r
end

-- the rock's own frame (called from its beetle; once it has left the
-- beetle, from the beetle's update still while the beetle lives)
local function rockUpdate(E, e, r)
  local f = E.field
  if r.deleted then if e.child == r then e.child = nil end return end
  local p = f.player
  local j = p.jar
  local GJ = require("src.zelda.tmc.GustJar")
  if r.rockAct == 1 then
    -- sub_08098918: ride on the beetle
    r.x, r.y = e.x, e.y
    if not e.hidden then r.z = 8 - ROCK_Z[band(e.anim.flags or 0, 0xF)]; r.oy = 0
    else r.z = 0; r.oy = 3 end
    if e.action and e.action > 4 then return rockBreak(f, r) end
    -- a blast flips it off (contact $0F)
    for _, s in ipairs(f.entities) do
      if s.smoke and not s.deleted and math.abs(s.x - r.x) < 20 and math.abs(s.y - r.y) < 20 then
        r.rockAct, r.czv, r.cz, r.liftable = 4, 0x2A000, -(r.z or 0) * 65536, nil
        e.child = nil
        return
      end
    end
    -- the Gust Jar ($13): Action3
    if j and j.state == "suck" and GJ.touching(f, r.x, r.y - 2, 6, 6) then
      r.rockAct, r.tol, r.liftable = 3, 0x30, nil
    end
  elseif r.rockAct == 3 then
    local touching = j and j.state == "suck" and GJ.touching(f, r.x, r.y - 2, 6, 6)
    if not r.detached then
      if not touching then r.rockAct, r.ox, r.liftable = 1, nil, true return end
      r.ox = ({ [0] = 2, 0, -2, 0 })[band(r.tol, 3)] -- sub_0806F4E8
      r.tol = r.tol - (j.charge or 1)
      if r.tol <= 0 then r.detached, r.kb, r.ox, r.z = true, 0, nil, 2; if e.child == r then e.child = nil end end
    else
      if not touching and not r.held then return rockBreak(f, r) end
      -- sub_0806F3E4: pulled straight at the mouth
      r.kb = math.min(0x500, r.kb + 64 * (j.charge or 1))
      local mx, my = GJ.mouth(p)
      local dx, dy = mx - r.x, my - r.y
      local d = math.sqrt(dx * dx + dy * dy)
      local sp = r.kb / 256
      if d <= sp then r.x, r.y = mx, my else r.x, r.y = r.x + dx / d * sp, r.y + dy / d * sp end
      if math.abs(r.x - mx) < 4 and math.abs(r.y - my) < 4 then
        if (r.form or 0) == 0 then r.deleted = true; f:sound(0xEF) -- a bush is swallowed
        else
          r.rockAct, r.held, r.hidden, r.jarSub = 5, true, true, 3
          j.held, j.state = r, "attached"
          f:sound(0xED)
        end
      end
    end
  elseif r.rockAct == 4 then
    -- flipped off: GravityUpdate(32)
    local z = (r.cz or 0) - (r.czv or 0)
    r.flipY = (r.czv or 0) < 0
    if z < 0 then r.cz, r.czv = z, (r.czv or 0) - 0x2000; r.z = -z / 65536 else return rockBreak(f, r) end
  end
end

-- ===========================================================================
-- SPINY_BEETLE
-- ===========================================================================
local function tileOf(e) return math.floor(e.x / 16), math.floor(e.y / 16) end

local function rockGone(e)
  local c = e.child
  if not c or c.deleted then return true end
  return c.rockAct ~= 1
end

local function expose(E, e)
  local f = E.field
  e.action, e.u79 = 5, 0
  e.hidden, e.noTouch = false, nil
  e.y = math.floor(e.y / 16) * 16 + 0xC
  e.hitType = 0x19
  e.timer, e.subtimer, e.spd = 48, 0, 0x100
  e.child = nil
  setAnim(E, e, 3)
  f:bubble(e, 0, 10, -12) -- CreateSpeechBubbleExclamationMark
end

local function putTile(E, e)
  local f = E.field
  if e.savedTile then f.room:setTile(1, e.tpx, e.tpy, e.savedTile); e.savedTile = nil end
end

local function hideTile(E, e)
  local f = E.field
  e.tpx, e.tpy = tileOf(e)
  local name = "bottom"
  e.savedTile = f.room.maps[name][e.tpy * f.room.tw + e.tpx]
  f.room:setTile(1, e.tpx, e.tpy, SPECIAL_TILE_34)
end

-- round 22: sub_0804A4BC exactly -- the tiles from the first one up to
-- (not including) the target's: collision 0 is open, above $F blocks, a
-- partial tile (1-$F) blocks when it shares a quarter bit with the mask
local function tilesOpen(f, tx0, ty0, tx1, ty1, mask)
  local c = f.room.coll[1]
  local W = f.room.tw
  local sx = (tx1 > tx0 and 1) or (tx1 < tx0 and -1) or 0
  local sy = (ty1 > ty0 and 1) or (ty1 < ty0 and -1) or 0
  local tx, ty = tx0, ty0
  for _ = 1, 256 do
    if tx == tx1 and ty == ty1 then return true end
    local v = c[ty * W + tx] or 0
    if v ~= 0 then
      if v > 0xF then return false end
      if band(v, mask) ~= 0 then return false end
    end
    tx, ty = tx + sx, ty + sy
  end
  return true
end
local function T(v) return math.floor(v / 16) end

-- sub_0804A024(e, 1, $10) -> sub_0804A044: the direction Link is lined up
-- in, or nil.  |dx| <= 8 (flags 1) tries the column (sub_0804A168: x - 4
-- with mask 10 / 5 by its half-tile, then x + 4 with the other mask, from
-- y +/- 10 to Link's row), |dy| <= 8 (flags 4) the row (sub_0804A318: y - 4
-- with mask $C / 3, then y + 4); the nearer axis first; different layers
-- never see each other.
local function linedUp(E, e, w) -- round 23: w = sub_0804A024's arg2 (default $10)
  local f = E.field
  local t = target(f)
  if not t then return nil end
  if band(t.layer or 1, e.layer or 1) == 0 then return nil end
  local hb, th = e.hitbox or { x = 0, y = 0 }, t.hitbox or { x = 0, y = 0 }
  local dx = (t.x + (th.x or 0)) - (e.x + (hb.x or 0))
  local dy = (t.y + (th.y or 0)) - (e.y + (hb.y or 0))
  local hw = math.floor((w or 0x10) / 2)
  local vert = dx >= -hw and dx <= (w or 0x10) - hw   -- flags 1
  local horiz = dy >= -hw and dy <= (w or 0x10) - hw  -- flags 4
  if not (vert or horiz) then return nil end
  local ex, ey = math.floor(e.x), math.floor(e.y)
  local function v()
    if not vert then return nil end
    local yy = (t.y > ey) and (ey + 10) or (ey - 10)
    local x1 = ex - 4
    local m = (band(x1, 0xF) < 8) and 10 or 5
    if tilesOpen(f, T(x1), T(yy), T(x1), T(t.y), m) and tilesOpen(f, T(ex + 4), T(yy), T(ex + 4), T(t.y), bit.bxor(m, 0xF)) then
      return (t.y > ey) and 0x10 or 0
    end
  end
  local function h()
    if not horiz then return nil end
    local xx = (t.x > ex) and (ex + 10) or (ex - 10)
    local y1 = ey - 4
    local m = (band(y1, 0xF) < 8) and 0xC or 3
    if tilesOpen(f, T(xx), T(y1), T(t.x), T(y1), m) and tilesOpen(f, T(xx), T(ey + 4), T(t.x), T(ey + 4), bit.bxor(m, 0xF)) then
      return (t.x > ex) and 8 or 0x18
    end
  end
  local ax, ay = math.abs(dx), math.abs(dy)
  if ax < ay then return v() or h() end
  return h() or v()
end
B.linedUp = linedUp

-- sub_08033D78: a step unless the tile ahead is $1C4 / $1C5 or solid
local function beetleStep(E, e)
  local f = E.field
  local d = band(round8(e.dir or 0), 0x18) / 4
  local o = AHEAD[d]
  local tx, ty = math.floor((e.x + o[1]) / 16), math.floor((e.y + o[2]) / 16)
  local tt = f.room:tileType(1, tx, ty)
  if tt == 0x1C4 or tt == 0x1C5 then return end
  local c = f.room.coll[1][ty * f.room.tw + tx] or 0
  if c == 0 or c >= 0x40 then move0(E, e, e.dir, e.spd or e.speed or 0x80) end
end

function B.spinyCollision(E, e, flags)
  if e.iframes > 0 and e.child and not rockGone(e) then
    if e.child then e.child.rockAct = 0; rockBreak(E.field, e.child) end
    expose(E, e)
  end
  if band(flags, 0x3F) == 0x14 and e.action ~= 5 then
    e.action, e.timer, e.subtimer = 3, 90, 16
    local t = target(E.field)
    e.dir = round8(t and dirTo(e.x, e.y, t.x, t.y) or 0)
    beetleStep(E, e)
    setAnim(E, e, 3)
  end
end

function B.spiny(E, e)
  local f = E.field
  if e.action == 0 then
    e.action, e.timer, e.subtimer = 1, 0, 0
    e.x = math.floor(e.x / 16) * 16 + 8
    e.y = math.floor(e.y / 16) * 16 + 8
    e.hx, e.hy = e.x, e.y
    e.u78, e.u7b = 0, 0
    hideTile(E, e)
    e.child = makeRock(E, e)
    if (e.form or 0) == 1 then e.hitType = 0x63 end -- SpinyBeetle_SetHitType (no Rock Breaker yet)
    e.hidden, e.noTouch = true, true
    e.onCollision = B.spinyCollision
    e.spd = e.speed or 0x80
    setAnim(E, e, 0)
  elseif e.action == 1 then
    e.hidden, e.noTouch = true, true
    if rockGone(e) then putTile(E, e); expose(E, e)
    elseif e.u7b > 0 then e.u7b = e.u7b - 1
    else
      e.x, e.y = e.hx, e.hy
      local dir = linedUp(E, e)
      local p = f.player
      local ok = dir ~= nil
      if ok then
        if dir == 0 then ok = e.u78 ~= 0 and e.y - p.y <= 0x30
        elseif dir == 0x10 then ok = p.y - e.y <= 0x30
        elseif dir == 8 then ok = p.x - e.x <= 0x30
        else ok = e.x - p.x <= 0x30 end
      end
      if ok and e.child and e.child.rockAct == 3 then ok = false end -- sub_0806F520: in the jar's pull
      if ok then
        if e.u78 == 0 then e.u78 = 1 end
        e.action, e.dir = 2, dir
        e.hidden, e.noTouch = false, nil
        e.y = math.floor(e.y / 16) * 16 + 0xC
        putTile(E, e)
        setAnim(E, e, 2)
      end
    end
  elseif e.action == 2 then
    if rockGone(e) then expose(E, e)
    else
      e.anim:update(1)
      if e.anim.done then e.action, e.timer, e.subtimer = 3, 120, 32; setAnim(E, e, 3) end
    end
  elseif e.action == 3 then
    if rockGone(e) then expose(E, e)
    else
      e.anim:update(1); e.anim:update(1)
      if e.subtimer > 0 then e.subtimer = e.subtimer - 1
      else
        e.timer = e.timer - 1
        if e.timer == 0 then
          e.action, e.timer = 4, 120
          e.x = math.floor(e.x / 16) * 16 + 8
          e.y = math.floor(e.y / 16) * 16 + 0xC
          e.hx, e.hy = e.x, e.y
          setAnim(E, e, 4)
        else beetleStep(E, e) end
      end
    end
  elseif e.action == 4 then
    if rockGone(e) then expose(E, e)
    else
      e.anim:update(1)
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.action = 1
        e.hidden, e.noTouch = true, true
        local back = ({ [0] = { 0, 16 }, [8] = { -16, 0 }, [0x10] = { 0, -16 }, [0x18] = { 16, 0 } })[band(round8(e.dir or 0), 0x18)]
        for _ = 1, 40 do
          e.x = math.floor(e.x / 16) * 16 + 8
          e.y = math.floor(e.y / 16) * 16 + 8
          e.hx, e.hy, e.u7b = e.x, e.y, 0x78
          local tx, ty = tileOf(e)
          if f.room:tileType(1, tx, ty) ~= SPECIAL_TILE_34 then break end
          e.x, e.y = e.x + back[1], e.y + back[2]
        end
        hideTile(E, e)
        setAnim(E, e, 0)
      end
    end
  elseif e.action == 5 then
    -- sub_08033C94: UpdateAnimationVariableFrames(3)
    e.anim:update(3)
    if e.u79 == 0 then e.u79 = 1 end
    if e.u79 == 1 then
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.u79, e.timer = 2, 120
        local t = target(f)
        local d = (t and dirTo(e.x, e.y, t.x, t.y) or 0) + 0x14
        local r = band(R(f), 3)
        if r == 0 then d = d + 8 elseif r == 2 then d = d + 0x18 end
        e.dir = band(d, 0x18)
      end
    else
      if e.subtimer ~= 0 then e.subtimer = e.subtimer - 1 else beetleStep(E, e) end
      e.timer = e.timer - 1
      if e.timer <= 0 then
        e.timer = band(R(f), 0x1F) + 32
        local t = target(f)
        local d = (t and dirTo(e.x, e.y, t.x, t.y) or 0) + 0x14
        local r = band(R(f), 3)
        if r == 1 then d = d + 8 elseif r == 3 then d = d + 0x18 end
        e.dir = band(d, 0x18)
      end
    end
  end
  if e.child then rockUpdate(E, e, e.child) end
  -- a rock that left the beetle keeps its own frame (pulled / flipped)
  if e.looseRocks then
    for i = #e.looseRocks, 1, -1 do local r = e.looseRocks[i]; if r.deleted or r.held then table.remove(e.looseRocks, i) else rockUpdate(E, e, r) end end
  end
  if e.child and e.child.rockAct ~= 1 then
    e.looseRocks = e.looseRocks or {}
    table.insert(e.looseRocks, e.child)
  end
end

-- ===========================================================================
-- ROLLOBITE
-- ===========================================================================
local function rolled(e) local a = e.animIndex or 0 return a >= 16 and a <= 19 end
local function rbAnim(E, e, base) setAnim(E, e, (e.animationState or 0) + base) end

local function rbDir(E, e)  -- sub_08020A7C
  local f = E.field
  local st = round8((e.dir or 0) + RB_TURN[R(f) % 3])
  local function inHome() return e.x - e.homeX >= 0 and e.x - e.homeX <= e.rangeW and e.y - e.homeY >= 0 and e.y - e.homeY <= e.rangeH end
  if not inHome() then
    local h = band(dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) + 4, 0x18)
    if bit.bxor(st, 0x10) == h then st = bit.bxor(st, 0x10) end
  end
  e.dir = st
  e.animationState = st / 8
  rbAnim(E, e, 0)
end

local function rbPick(E, e)  -- sub_08020A30
  local f = E.field
  if e.u84 < 2 then
    e.timer = RB_PICK[band(R(f), 7)]
    if e.timer == 0 then e.action, e.timer, e.u84 = 3, 60, e.u84 + 1 return end
  end
  e.action, e.u84 = 1, 0
  rbDir(E, e)
end

local function rollUp(E, e, timer)
  e.action, e.dir = 4, 0xFF
  if timer then e.timer = timer end
  e.liftable = nil
  rbAnim(E, e, 0x10)
end

-- Rollobite_TryToHoleUp
local function holeUp(E, e)
  local f = E.field
  if not (rolled(e) and (e.cz or 0) == 0 and (e.z or 0) <= 0) then return false end
  local tx, ty = tileOf(e)
  local tt = f.room:tileType(1, tx, ty)
  if tt == 0x71 or tt == 0x72 then
    e.action, e.noTouch, e.liftable = 6, true, nil
    e.x = math.floor(e.x / 16) * 16 + 8
    e.y = math.floor(e.y / 16) * 16 + 13
    e.czv = 0x20000
    rbAnim(E, e, 0x14)
    f.room:setTile(1, tx, ty, SPECIAL_TILE_52)
    return true
  end
  return false
end
B.holeUp = holeUp

function B.rollobiteCollision(E, e, flags)
  if e.hitType == 34 and e.health ~= 0xFF then
    e.action, e.czv, e.dir = 4, 0x20000, 0xFF
    e.health, e.hitType = 0xFF, 35
    rbAnim(E, e, 8)
  end
  if flags ~= 0x80 and (e.action == 4 or e.action == 5) then rollUp(E, e, 180) end
end

-- the carry system: lifted while rolled up, thrown / dropped it lands rolled
local carryHook = {}
function carryHook.lift(f, p, e)
  e.carriedBy, e.hidden, e.noTouch, e.liftable = p, true, true, nil
  e.action = 2
  f:objects():lift(p, { obj = e.id, form = (e.animationState or 0) + 0x10, ent = e, hook = carryHook,
    def = { sprite = e.sprite, palette = e.def and e.def.palette, gfxType = "enemy", gfx = e.def and e.def.gfx } })
  return true
end
local function release(f, p, c, vx, vy, z)
  local e = c.ent
  p.carried = nil
  e.carriedBy, e.hidden = nil, false
  e.x, e.y = p.x, p.y
  e.thrownV = { vx, vy }
  e.cz, e.czv = -(z or 14) * 65536, 0x8000
  e.action = 4
  e.timer = 180
  rbAnim(f:enemies(), e, 0x10)
end
function carryHook.throw(f, p, c)
  local s = p.animationState
  release(f, p, c, (s == 2 and 1 or s == 6 and -1 or 0) * 2.5, (s == 4 and 1 or s == 0 and -1 or 0) * 2.5, 14)
  f:sound(0x7C)
end
function carryHook.drop(f, p, c) release(f, p, c, 0, 0, 4) end
B.carryHook = carryHook

function B.rollobite(E, e)
  local f = E.field
  if e.action == 0 then
    e.u84 = 0
    e.gustJarFlags = 18
    e.dir = round8(band(R(f), 0x1F))
    e.onCollision = B.rollobiteCollision
    e.carryHook = function(ff, p, x) return carryHook.lift(ff, p, x) end
    e.onJarLost = function(EE, x) if (x.jarSub or 0) < 3 then x.noTouch = nil; rollUp(EE, x) end end
    e.onShotEnd = function(ff, x)  -- OnGrabbed subaction 5 (sub_080207A8)
      x.jarSub, x.hidden, x.noTouch = nil, false, nil
      x.dir = bit.bxor(band(x.dir or 0, 0x1F), 0x10)
      x.czv, x.spd = 0x18000, 0x80
      rollUp(ff:enemies(), x)
    end
    rbPick(E, e)
    return
  end
  if e.action ~= 2 and holeUp(E, e) then return end
  if e.action == 1 then
    e.anim:update(1)
    local fl = e.anim.flags or 0
    if band(fl, 1) ~= 0 then
      e.anim.flags = band(fl, bit.bnot(1))
      local hx, hy = move0(E, e, e.dir, e.speed or 0x100)
      if hx or hy then e.timer = 1 end
    end
    if band(fl, 0x10) ~= 0 then
      e.anim.flags = band(e.anim.flags, bit.bnot(0x10))
      e.timer = e.timer - 1
      if e.timer <= 0 then e.action, e.timer = 3, 60 end
    end
  elseif e.action == 2 then
    -- carried (sub_08020874): drawn with Link
  elseif e.action == 3 then
    e.timer = e.timer - 1
    if e.timer <= 0 then rbPick(E, e) end
  elseif e.action == 4 then
    if not e.anim.done then e.anim:update(1) end
    if e.thrownV then
      e.x, e.y = e.x + e.thrownV[1], e.y + e.thrownV[2]
      if f.room:isSolid(e.x, e.y, 1) then e.x, e.y = e.x - e.thrownV[1], e.y - e.thrownV[2]; e.thrownV = nil end
    end
    local r = require("src.zelda.tmc.EnemyCrenel").bounce(e, 0x2800)
    if r == 0 then
      e.thrownV = nil
      e.cz, e.czv = 0, 0
      e.timer = (e.timer or 1) - 1
      if e.timer <= 0 then e.action = 5; e.liftable = nil; rbAnim(E, e, 12)
      else e.liftable = true end
    else
      if r == 1 then f:sound(SFX_PLACE_OBJ); e.thrownV = nil end
      if (e.dir or 0xFF) < 0x80 then move0(E, e, e.dir, e.spd or 0x80) end
    end
  elseif e.action == 5 then
    e.anim:update(1)
    if e.anim.done then
      e.noTouch, e.liftable = nil, nil
      e.speed, e.hitType = 0x100, 34
      rbPick(E, e)
      e.dir = (e.animationState or 0) * 8
      rbAnim(E, e, 0)
    else
      e.liftable = band(e.anim.flags or 0, 1) == 0
    end
  elseif e.action == 6 then
    local z = (e.cz or 0) - (e.czv or 0)
    if z < 0 then e.cz, e.czv = z, (e.czv or 0) - 0x1C00 else e.cz, e.czv = 0, 0; e.action = 7 end
    if (e.anim.frame or 0) == 0 then e.anim:update(1) end
  elseif e.action == 7 then
    e.anim:update(1)
  end
  e.z = -(e.cz or 0) / 65536
end

function B.update(E, e)
  if e.id == B.SPINY then return B.spiny(E, e) end
  if e.id == B.ROLLOBITE then return B.rollobite(E, e) end
end

return B
