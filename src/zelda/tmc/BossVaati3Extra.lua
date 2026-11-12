-- Round 26 (team B): the rest of Vaati's Wrath's group --
--   VAATI_EYES_MACRO ($25, src/enemy/vaatiEyesMacro.c): the big eye inside
--     Vaati's arms (AREA_VAATIS_ARMS $8A rooms 0 / 1) and its seven guards.
--     Type 0 (health from field_0x3a / 0x3b, i.e. what was left the last
--     time): VAATI3_INSIDE_ARM_MANAGER, the pupil (type 2: its frame turns to
--     Link by gUnk_080CDE70) and the 7 type 1 guards (each with a type 3
--     shadow, frame $11); types 0 / 1 bob (gUnk_080CDE90) and walk the tile
--     grid (sub_0802EFB8: a random axis direction -- 1 in 4 away from Link --
--     for 1-4 tiles at gUnk_080CDE98 speed, none when the next tile is
--     solid; sub_0802F04C counts tile centres, a wall picks again).  Type 0's
--     OnCollision keeps field_0x3a/3b = its health (SFX_17A when it drops),
--     at 0 clears field_0x39 bit (field_0x3c + 2); type 1 cannot be hurt
--     (health back to $FF, SFX_BUTTON_DEPRESS, iframes negated).
--   VAATI3_INSIDE_ARM_MANAGER (vaati3InsideArmManager.c): field_0x3d seconds
--     (Link's time left on the open hand), the eye's death cuts it to $12D
--     frames; shakes at $12C / $D2 / $78, SFX_126 faster and faster; then
--     gUnk_0813AC48 (back to $8B:00 at $B0,$88).
--   ENEMY_4D ($4D, src/enemy/enemy4D.c, $8D:00 the DHC bridge): a ball and
--     chain soldier that keeps to its spot: the ball spins over its head
--     (unk_7c -$A a frame, chain $28); Link in its home box within $4E and
--     lined up (sub_0804A044 $12) for 30 frames -> wind-in (chain -4 a frame),
--     15 frames, the throw (chain +5 a frame while unk_7f climbs $F6 -> 0,
--     SFX_15B), shake 8, 30 frames, the pull-back (-2, the chain's collision
--     off under $13), 60 frames, regrow; Link's thrown things / Cane bolts
--     coming at it (sub_0803EF20) -> 180 frames of a fast short spin; off its
--     spot -> walks back.  BALL_AND_CHAIN (ballAndChain.c) types 0 (the ball
--     at sin / cos(unk_7c) * unk_7e, y -10 - unk_7f), 1-3 (the links between
--     the hand -- gUnk_0812A4A8 by the soldier's frame -- and the ball, their
--     collision on while it spins) and 4 (the throw's trail, 5 frames).
-- NOTE: BossVaati2.lua (the same round) also ports VAATI_EYES_MACRO and the
--   inside-arm manager on the same gRoomTransition block (V.RT via its
--   M.rt); it is earlier in R26.MODULES, so its handles() wins for $25 and
--   this copy only runs when BossVaati2 is absent.
-- SIMPLIFIED: Enemy4D's item check uses the engine's kind-8 entities (the
--   Cane bolt = PLAYER_ITEM_PACCI_CANE_PROJECTILE) with a straight line-up
--   test (no tile scan); gHitbox_22 for the links is a 3x3 box.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local X = {}
local function V3() return require("src.zelda.tmc.BossVaati3") end
local function impl(f) return V3().impl(f) end
local function hx(v) return math.floor(v) end
local function u32(v) return v % 4294967296 end
local function s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end

local MAC_DIR = { [0] = 0, 8, 0x18, 0 }                                                       -- gUnk_080CDE6C
local MAC_FRAME = { [0] = 9, 9, 8, 9, 8, 8, 8, 7, 7, 7, 6, 7, 6, 6, 6, 5, 5, 5, 12, 5, 12, 12, 12, 11, 11, 11, 10, 11, 10, 10, 10, 9 } -- gUnk_080CDE70
local MAC_Z = { [0] = -2, -3, -4, -5, -6, -5, -4, -3 }                                        -- gUnk_080CDE90
local MAC_SPEED = { [0] = 0xc0, 0x100, 0x140, 0x180 }                                         -- gUnk_080CDE98
local TILE_OFS = { [0] = { 0, -16 }, { 16, 0 }, { 0, 16 }, { -16, 0 } }                     -- gUnk_080B4488 (-$40, 1, $40, -1 tiles)
X.T = { MAC_FRAME = MAC_FRAME, MAC_Z = MAC_Z, MAC_SPEED = MAC_SPEED }

-- ---------------------------------------------------------------------------
-- VAATI_EYES_MACRO
-- ---------------------------------------------------------------------------
local function macroPick(E, e) -- sub_0802EFB8
  local f = E.field
  local V = impl(f)
  local p = f.player
  local r = V:rand()
  local u
  if band(rshift(r, 16), 3) ~= 0 then u = band(r, 0x18)
  else u = band(V.dirTo(hx(p.x), hx(p.y), hx(e.x), hx(e.y)) + 4, 0x18) end
  local o = TILE_OFS[rshift(u, 3)]
  local cx, cy = math.floor(e.x / 16) * 16 + 8 + o[1], math.floor(e.y / 16) * 16 + 8 + o[2]
  if f.room:isSolid(cx, cy, 1) then e.direction = 0xFF
  else
    e.timer = band(r, 3) + 1
    e.direction = band(u, 0x18)
    e.speed = MAC_SPEED[band(rshift(r, 24), 3)]
  end
end
local function macroMove(E, e) -- sub_0802F04C
  local f = E.field
  local ox, oy = hx(e.x), hx(e.y)
  local moved = false
  if e.direction ~= 0xFF then
    local a = (e.direction % 32) / 32 * 2 * math.pi
    local s = (e.speed or 0) / 256
    local nx, ny = e.x + math.sin(a) * s, e.y - math.cos(a) * s
    local hb = e.hitbox or { x = 0, y = 0, w = 6, h = 6 }
    local lx = nx + (e.direction == 8 and hb.w or e.direction == 0x18 and -hb.w or 0)
    local ly = ny + (e.direction == 0x10 and hb.h or e.direction == 0 and -hb.h or 0)
    if not f.room:isSolid(lx, ly, 1) then e.x, e.y = nx, ny; moved = true end
  end
  if not moved then macroPick(E, e) return end
  local d = rshift(e.direction, 3)
  local nxv, nyv = hx(e.x), hx(e.y)
  local sx, sy = ox, oy
  if d == 0 then
    if band(oy, 0xF) > 8 and band(nyv, 0xF) < 9 then e.timer = e.timer - 1; sy = band(nyv, 0xFFF0) + 8 end
  elseif d == 1 then
    if band(ox, 0xF) < 8 and band(nxv, 0xF) >= 8 then e.timer = e.timer - 1; sx = band(nxv, 0xFFF0) + 8 end
  elseif d == 2 then
    if band(oy, 0xF) < 8 and band(nyv, 0xF) >= 8 then e.timer = e.timer - 1; sy = band(nyv, 0xFFF0) + 8 end
  else
    if band(ox, 0xF) >= 9 and band(nxv, 0xF) < 9 then e.timer = e.timer - 1; sx = band(nxv, 0xFFF0) + 8 end
  end
  if e.timer == 0 then e.x, e.y = sx, sy; macroPick(E, e) end
end
X.macroPick, X.macroMove = macroPick, macroMove

local function macroGhost(V, e, ty)
  local d = V:edef(V.MACRO, ty)
  local g = V:part(d, "enemy", { type = ty, parent = e, spritePriority = ty == 3 and 6 or 4 })
  return g
end

local function macroInside(E, e)
  local f = E.field
  local V = impl(f)
  local RT = V.rt(f)
  local st = { action = 1, t = RT.f3d * 60 }
  X.lastInside = st
  require("src.zelda.tmc.R26").ticker(f._dungeon, function(_, me)
    if me.done then return end
    -- the eye's death (its OnCollision at health 0)
    if st.action == 1 and (e.deleted or e.dying) then
      st.action = 2
      RT.f39 = band(RT.f39, bxor(0xFF, lshift(1, RT.f3c + 2)))
      if f.room.room == 0 then RT.f3a = 0 else RT.f3b = 0 end
      if 0x12D < st.t then st.t = 0x12D end
    end
    st.t = st.t - 1 -- sub_0805DBF0
    if st.t <= 0 then
      me.done, me.deleted = true, true
      f:startTransition({ warpType = 1, area = V.AREA_V3, room = 0, endX = 0xB0, endY = 0x88, facing = 4, kind = 0, layer = 1 })
      return
    end
    if st.t == 0x78 then f:shake(120, 2) elseif st.t == 0xD2 then f:shake(90, 1) elseif st.t == 0x12C then f:shake(90, 0) end
    if st.t < 0x78 then if band(st.t, 0xF) == 0 then f:sound(0x126) end
    elseif 0xD1 >= st.t then if band(st.t, 0x1F) == 0 then f:sound(0x126) end
    elseif st.t <= 199 then if band(st.t, 0x3F) == 0 then f:sound(0x126) end end
  end, { id = V.M_INSIDE })
  return st
end

local function macroUpdate(E, e)
  local f = E.field
  local V = impl(f)
  local RT = V.rt(f)
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  if e.form == 0 then
    if e.action == 0 then
      macroInside(E, e)
      e.pupil = macroGhost(V, e, 2)
      e.action = 1
      e.health = (f.room.room == 0) and RT.f3a or RT.f3b
      e.unk79 = e.health
      e.unk78 = band(V:rand(), 0xFF)
      macroPick(E, e)
      E:setAnim(e, 0)
      for i = 0, 6 do -- sub_0802EF58
        local c = E:spawn({ kind = 3, id = V.MACRO, paramA = 1, paramB = 0, paramC = 0, x = e.x, y = e.y })
        if c then
          c.type2, c.parent, c.layer = i, e, 1
          f.entities[#f.entities + 1] = c
        end
      end
      e.onCollision = function(_, me) -- VaatiEyesMacro_OnCollision type 0 (health > 0)
        if f.room.room == 0 then RT.f3a = me.health else RT.f3b = me.health end
        if me.unk79 ~= me.health then f:sound(0x17A) end
        me.unk79 = me.health
      end
    else
      macroMove(E, e)
      e.anim:update(1)
    end
  elseif e.form == 1 then
    if e.action == 0 then
      e.shadow = macroGhost(V, e, 3)
      e.action = 1
      local r = V:rand()
      e.timer = band(r, 3) + 1
      e.unk78 = band(rshift(V:rand(), 8), 0xFF)
      e.direction = MAC_DIR[band(rshift(r, 16), 3)]
      e.speed = e.speed or 0x100
      E:setAnim(e, 1)
      e.onCollision = function(_, me) -- type 1: no damage
        if me.iframes > 0 then me.iframes = -me.iframes end
        if me.health ~= 0xFF then f:sound(0xE5) end
        me.health = 0xFF
      end
    elseif e.parent and (e.parent.deleted or e.parent.dying) then
      e.noTouch = true
      E:kill(e)
      return
    else
      macroMove(E, e)
      e.anim:update(1)
    end
  end
  if (e.form or 0) < 2 then -- sub_0802EF90 (engine z: up)
    e.unk78 = band((e.unk78 or 0) + 1, 0xFF)
    e.z = -MAC_Z[band(rshift(e.unk78 - 1, 3), 7)]
  end
  e.collideOn = true
  -- the followers (types 2 / 3)
  local p = f.player
  local g = e.pupil
  if g and not g.deleted then
    g.x, g.y, g.z = e.x, e.y, -(e.z or 0)
    local i = band(V.dirTo(hx(g.x), hx(g.y), hx(p.x), hx(p.y)) + 1, 0x1E)
    if MAC_FRAME[i] ~= g.frameIndex and MAC_FRAME[i + 1] ~= g.frameIndex then g.frameIndex = MAC_FRAME[i] end
    g.y, g.spriteOY = g.y + 1, -1
    g.hidden = false
  end
  local sh = e.shadow
  if sh and not sh.deleted then sh.x, sh.y, sh.z, sh.frameIndex, sh.hidden = e.x, e.y, 0, 0x11, false end
end

-- the followers go with their eye (ticked here even while it dies)
local function followers(E)
  local f = E.field
  for _, e in ipairs(f.entities) do
    if e.id == 0x25 and e.enemy and (e.dying or e.deleted) then
      if e.pupil then impl(f):kill(e.pupil); e.pupil = nil end
      if e.shadow then impl(f):kill(e.shadow); e.shadow = nil end
    end
  end
end
X.followers = followers

-- ---------------------------------------------------------------------------
-- ENEMY_4D and its BALL_AND_CHAIN
-- ---------------------------------------------------------------------------
local LINK_OFS = { [0] = { 6, -16 }, { 10, -14 }, { 10, -16 }, { 8, -16 }, { -4, -14 }, { -8, -14 }, { -4, -10 }, { 4, -10 },
                   { -6, -14 }, { -8, -16 }, { -10, -14 }, { -8, -12 }, { 4, -14 }, { 8, -14 }, { 4, -10 }, { -4, -10 } } -- gUnk_0812A4A8
local THROW_ANGLE = { [0] = 0, 68, 128, 188 }                                                -- gUnk_080D08C4
X.LINK_OFS = LINK_OFS

local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end
local function state4(dir) return rshift(band(dir + 4, 0x1F), 3) end -- DirectionToAnimationState
local function e94C(E, e, arg2) -- sub_0803E94C
  local st = state4(e.direction or 0)
  local ai = e.animIndex or 0
  if band(ai, 0x10) == arg2 then
    if band(e.direction or 0, 7) == 4 then
      if band(e.animationState - rshift(e.direction, 3), 3) <= 1 then return end
    end
    if st == e.animationState then return end
  end
  e.animationState = st
  setAnim(E, e, arg2 + band(ai, 3) + st * 4)
end
local function e9A4(E, e) -- sub_0803E9A4
  local v = rshift(band(e.unk7c + 0x20, 0xFF), 6)
  local ai = e.animIndex or 0
  if band(ai, 3) == v then return end
  setAnim(E, e, v + band(ai, 0xFC))
end
X.e94C, X.e9A4 = e94C, e9A4

local function toIdle(E, e) e.action = 1; e.unk7a = 0x1E; e94C(E, e, 0) end -- sub_0803EE8C
local function target(f) local p = f.player if p.minish or p.state == "dead" then return nil end return p end -- sub_08049E4C
local function inHome(e, t) -- sub_08049FDC
  return u32(hx(t.x) - e.homeX) <= e.rangeW and u32(hx(t.y) - e.homeY) <= e.rangeH
end
local function lined(E, e, w)
  local B = require("src.zelda.tmc.EnemyBeetle")
  return B.linedUp and B.linedUp(E, e, w) or nil
end
local function attack(E, e) -- sub_0803EEA4
  local f = E.field
  local t = target(f)
  if t and inHome(e, t) and impl(f).within(e, t.x, t.y - 4, 0x4E) then
    local d = lined(E, e, 0x12)
    if d ~= nil and d ~= 0xFF then
      e.unk7a = e.unk7a - 1
      if e.unk7a == 0 then
        e.action, e.direction = 5, d
        e94C(E, e, 0)
        return true
      end
      return false
    end
  end
  e.unk7a = 0x1E
  return false
end
local function itemsComing(E, e) -- sub_0803EF20 (PLAYER_ITEMs heading at it)
  local f = E.field
  for _, o in ipairs(f.entities) do
    if o.kind == 8 and not o.deleted and (o.action or 1) == 1 then
      local odir = o.bolt and (o.dir or 0) * 8 or o.direction
      if odir and math.abs(o.x - e.x) <= 0x50 and math.abs(o.y - e.y) <= 0x50 then
        local dx, dy = e.x - o.x, e.y - o.y
        local want
        if math.abs(dx) <= 0xE then want = dy > 0 and 0x10 or 0 elseif math.abs(dy) <= 0xE then want = dx > 0 and 8 or 0x18 end
        if want and want == odir then
          e.action, e.unk78, e.unk7b = 2, 0xB4, 1
          return true
        end
      end
    end
  end
  return false
end

local function chainMake(E, e)
  local f = E.field
  local V = impl(f)
  local d = V:pdef(V.P_BALLCHAIN)
  local parts = {}
  for ty = 0, 3 do
    local pt = V:part(d, "enemy", { type = ty, spritePriority = 3, collide = ty == 0, hitbox = ty == 0 and d.hitbox or { x = 0, y = 0, w = 3, h = 3 } })
    pt.frameIndex = (ty == 0) and 0 or 5
    pt.hitType = d.damageType or 0
    parts[ty] = pt
  end
  e.chain = parts
  require("src.zelda.tmc.R26").ticker(f._dungeon, function(_, me)
    if me.done then return end
    if e.deleted or e.dying then
      for ty = 0, 3 do V:kill(parts[ty]) end
      me.done, me.deleted = true, true
      return
    end
    X.chainTick(E, e)
  end, { id = V.P_BALLCHAIN })
end
function X.chainTick(E, e)
  local f = E.field
  local V = impl(f)
  local P = e.chain
  local b = P[0]
  local sz = -(e.z or 0)
  -- sub_080AB074: the ball
  b.x, b.y, b.z = e.x, e.y + (-10 - s8(e.unk7f)), sz
  b.x = b.x + V.SIN[band(e.unk7c, 0xFF)] * e.unk7e / 256
  b.y = b.y - V.SIN[band(e.unk7c, 0xFF) + 0x40] * e.unk7e / 256
  b.z = b.z + s8(e.unk7f)
  if e.unk7b ~= 0 then -- type 4: the trail
    local d = V:pdef(V.P_BALLCHAIN)
    local tr = V:part(d, "enemy", { x = b.x, y = b.y, z = b.z, spritePriority = 3 })
    tr.frameIndex, tr.timer = 0, 5
    V.trails = V.trails or {}
    V.trails[#V.trails + 1] = tr
  end
  -- sub_080AB170: the links
  for ty = 1, 3 do
    local L = P[ty]
    L.collide = (L.unk7c ~= e.unk7c)
    L.unk7c = e.unk7c
    local fl = e.anim.flags or 0
    local ox, oy
    if band(fl, 0x20) == 0 then local o = LINK_OFS[band(fl, 0x1F) % 16]; ox, oy = o[1], o[2] else ox, oy = 0, -10 end
    L.x, L.y, L.z = e.x + ox, e.y + oy, sz
    local function pull(a, c)
      local v = (math.floor(a) - math.floor(c)) * ty
      if v < 0 then v = v + 3 end
      return math.floor(v / 4)
    end
    L.x = math.floor(L.x) + pull(b.x, L.x)
    L.y = math.floor(L.y) + pull(b.y, L.y)
    L.z = math.floor(L.z) + pull(b.z, L.z)
  end
  if V.trails then
    for i = #V.trails, 1, -1 do
      local tr = V.trails[i]
      tr.timer = tr.timer - 1
      if tr.timer == 0 then V:kill(tr); table.remove(V.trails, i) else tr.frameIndex = tr.frameIndex + 1 end
    end
  end
  for ty = 0, 3 do
    local pt = P[ty]
    pt.hidden = false
    if pt.collide then V:touchLink(pt) end
  end
end

local function e4dUpdate(E, e)
  local f = E.field
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  if e.kbt and e.kbt > 0 then
    e.kbt = e.kbt - 1
    local nx, ny = e.x + e.kbx, e.y + e.kby
    if not f.room:isSolid(nx, ny, 1) then e.x, e.y = nx, ny end
  end
  local a = e.action
  if a == 0 then -- Enemy4D_Init
    chainMake(E, e)
    e.collideOn = true
    e.animationState = 1 -- IdleEast
    e.unk7b, e.unk7c, e.unk7e, e.unk7f = 0, 0, 0x28, 0xFE
    e.unk80, e.unk82 = hx(e.x), hx(e.y)
    e.direction = 8
    setAnim(E, e, e.animationState * 4)
    toIdle(E, e)
    return
  end
  if a == 1 then
    e.unk7c = band(e.unk7c - 0xA, 0xFF)
    local t = target(f)
    if t then
      e.direction = band(math.floor((impl(f).dirTo(hx(e.x), hx(e.y), hx(t.x), hx(t.y)) + 4) / 8) * 8, 0x1F) -- DirectionRoundUp
      e94C(E, e, 0)
    end
    e9A4(E, e)
    if not impl(f).within(e, e.unk80, e.unk82, 2) then
      e.action = 4
      e94C(E, e, 0x10)
    elseif not itemsComing(E, e) then
      attack(E, e)
    end
  elseif a == 2 then
    e.unk7c = band(e.unk7c - 0x10, 0xFF)
    e9A4(E, e)
    if e.unk7e > 0x1C then e.unk7e = e.unk7e - 1 end
    e.unk78 = e.unk78 - 1
    if e.unk78 == 0 then e.action, e.unk7b = 3, 0 end
  elseif a == 3 then
    e.unk7c = band(e.unk7c - 0xA, 0xFF)
    e9A4(E, e)
    if e.unk7e < 0x28 then e.unk7e = e.unk7e + 1 else toIdle(E, e) end
  elseif a == 4 then
    e.unk7c = band(e.unk7c - 0xA, 0xFF)
    e9A4(E, e)
    if impl(f).within(e, e.unk80, e.unk82, 1) then
      e.x, e.y = e.unk80, e.unk82
      toIdle(E, e)
      e94C(E, e, 0)
    elseif (e.kbt or 0) == 0 then
      e.direction = impl(f).dirTo(hx(e.x), hx(e.y), e.unk80, e.unk82)
      e94C(E, e, 0x10)
      require("src.zelda.tmc.EnemyDeepwood").move0(E, e, e.direction, e.speed)
    end
  elseif a == 5 then
    e.unk7c = band(e.unk7c - 0xC, 0xFF)
    e9A4(E, e)
    e.unk7e = e.unk7e - 4
    if e.unk7e < 1 then
      e.unk7e = 0
      e.action, e.timer = 6, 15
      setAnim(E, e, e.animationState + 0x20)
    end
  elseif a == 6 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.timer = 7, 1
      e.unk7c = THROW_ANGLE[e.animationState]
      e.unk7f = 0xF6
      f:sound(0x15B)
    end
  elseif a == 7 then
    if band(e.anim.flags or 0, 0x80) == 0 then e.anim:update(1)
    else
      e.timer = e.timer - 1
      if e.timer == 0 then e.timer = 2; e.unk7f = band(e.unk7f + 1, 0xFF) end
      if e.unk7f ~= 0 then e.unk7e = e.unk7e + 5
      else e.action, e.timer = 8, 30; f:shake(8, 0) end
    end
  elseif a == 8 then
    e.timer = e.timer - 1
    if e.timer == 0 then e.action = 9 end
  elseif a == 9 then
    e.unk7e = band(e.unk7e - 2, 0xFF)
    if e.unk7e < 0xB then
      e.action, e.timer = 10, 60
      e.direction = lshift(e.animationState, 3)
      e.unk7c, e.unk7f = 0, 0xFE
      e94C(E, e, 0x10)
    elseif e.unk7e < 0x13 then
      e.chain[0].collide = false
    end
  elseif a == 10 then
    if e.timer ~= 0 then
      e.timer = e.timer - 1
      if e.timer == 0 then e.chain[0].collide = true; e94C(E, e, 0) end
    else
      e.unk7c = band(e.unk7c - 0xA, 0xFF)
      e9A4(E, e)
      e.unk7e = e.unk7e + 1
      if e.unk7e > 0x27 then toIdle(E, e) end
    end
  end
end
X.e4dUpdate = e4dUpdate

-- ---------------------------------------------------------------------------
-- hooks (forwarded by BossVaati3)
-- ---------------------------------------------------------------------------
function X.spawnEnemy(E, dat, def) return nil end -- $25 / $4D: Enemies:spawn builds them
function X.handles(e) return e.id == 0x25 or e.id == 0x4D end
function X.update(E, e)
  followers(E)
  if e.id == 0x25 then return macroUpdate(E, e) end
  if e.id == 0x4D then return e4dUpdate(E, e) end
end

return X
