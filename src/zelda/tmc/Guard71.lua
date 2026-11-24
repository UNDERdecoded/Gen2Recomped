-- Round 71: the castle garden's patrolling guards (guard.c, NPC GUARD_1 $15 without a script, types 0 .. 3) and
-- their GUARD_LINE_OF_SIGHT (projectile/guardLineOfSight.c).  The port left these guards standing where the room's
-- entity list put them: the maze's guard at the west entrance stood in the way and nobody ever saw Link.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * sub_08063D44 (init): sub_0806EE04(this, gUnk_0810F6BC[type], 0) -- the patrol program (child), hitType 0,
--     knockbackSpeed 0, carryFlags 0, collisionFlags 0; types 0 .. 3 make a GUARD_LINE_OF_SIGHT (type 0, parent the
--     guard, subtimer 60); InitializeAnimation(4); action 1, type 0.
--   * sub_08063DC8 (action 1): type $FF (seen Link) -> action 2, timer 30, faces Link (animation state + 4); else
--     sub_0806EE20 (the program step), the animation follows knockbackDirection (animation state + 4).
--   * sub_08063E54 (action 2): --timer == 0 -> SetRoomFlag($F) (the garden's scripts take it from there).
--   * sub_0806EE20 / sub_0806EF88 (npcUtils.c): the program is u16 words, the op in the low byte:
--       0 restart (hitType 0); 1 x y: walk to the room point (carryFlags 1: every 9th frame the direction is aimed
--       again (CalculateDirectionTo), knockbackDirection = its 4-way state unless collisionFlags bit 0;
--       LinearMoveUpdate; there when |speed| / 8 > distance * 16 (sub_080041DC) -> hitType + 3); 2 n: wait n frames
--       (carryFlags 2); 3: collisionFlags bit 0 = !(hi byte); 4 n: speed n; 5: knockbackDirection = hi byte;
--       6: wait for the animation's end (carryFlags 3); 7: the program goes on from the next word (child = a2 + 1,
--       hitType 0); 8: carryFlags 0, hitType + 1, returns the hi byte.
--   * GuardLineOfSight type 0: on the guard (CopyPosition), timer = Random(); after subtimer 60, while the guard is on
--     screen (sub_080644C8), every 4th frame ((timer++ & 3) == 0) a type-1 ray: direction =
--     (gUnk_081299C8[(timer >> 2) & 7] + knockbackDirection * 8) & $1F.  Type 1: 18 frames, speed $800
--     (LinearMoveUpdate), hitbox gUnk_080FD1E4, gone on a solid tile (IsTileCollision(gMapBottom, x, y, 2)); touching
--     Link (CONTACT_NOW) sets the guard's type to $FF.
-- The programs, the ray directions and the ray's hitbox are read from the player's ROM (RomTables "Guard71.*").
-- SIMPLIFIED: the rays are not entities (they are never drawn: spriteSettings.draw 0); the ray meets Link by the box
-- test (|dx| <= wA + wB) on the frame it moves; the tile test is the room's solid test on the bottom layer; talking
-- to these guards (action 3, sub_08064428) is not ported.
local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = {}
M.ID = 0x15
M.LOS_SUBTIMER, M.RAY_TIME, M.RAY_SPEED = 60, 18, 0x800
M.CAUGHT_FLAG = 0x0F

local RT = require("src.zelda.tmc.RomTables")
local PATHS = RT.t("Guard71.PATHS")     -- gUnk_0810F6BC: per guard type a list of u16 words
local LOS_DIRS = RT.t("Guard71.LOS_DIRS") -- gUnk_081299C8 (s8[8])
local RAY_HB = RT.t("Guard71.RAY_HB")     -- gUnk_080FD1E4 (Hitbox)
M.tables = { PATHS = PATHS, LOS_DIRS = LOS_DIRS, RAY_HB = RAY_HB }

local SIN = {}
for i = 0, 255 + 64 do SIN[i] = math.floor(math.sin((i % 256) * math.pi / 128) * 256 + 0.5) end
-- LinearMoveUpdate: speed (1/256 px) along direction (0 .. 31, 0 north, clockwise)
local function linear(o, dir, speed)
  local m = band(dir, 0x1F) * 8
  o.x = o.x + SIN[m] * speed / 65536
  o.y = o.y - SIN[m + 64] * speed / 65536
end
M.linear = linear

local function S27() return require("src.zelda.tmc.Story27Town") end
local function rand(f) if M.random then return M.random(f) end return S27().rand(f) end
local function ix(v) return math.floor(v) end

-- the program word at the guard's cursor
local function word(g, k)
  local list = g.list
  return list and list[g.base + g.hitType + (k or 0)] or 0
end

local stepOps
-- sub_0806EF88: run program ops until one waits; returns the op 8 value (or 0)
local function runOps(g, e, f)
  for _ = 1, 64 do
    local w = word(g, 0)
    local op, hi = band(w, 0xFF), rshift(w, 8)
    if op == 0 then g.hitType = 0
    elseif op == 1 then g.carry = 1; g.kbSpeed = 8; return 0
    elseif op == 2 then g.carry = 2; g.kbSpeed = word(g, 1); return 0
    elseif op == 3 then
      if hi ~= 0 then g.cflags = band(g.cflags, 0xFE) else g.cflags = bor(g.cflags, 1) end
      g.hitType = g.hitType + 1
    elseif op == 4 then e.speed = word(g, 1); if e.speed >= 0x8000 then e.speed = e.speed - 0x10000 end; g.hitType = g.hitType + 2
    elseif op == 5 then g.kbd = hi; g.hitType = g.hitType + 1
    elseif op == 6 then g.carry = 3; return 0
    elseif op == 7 then g.base = g.base + g.hitType + 1; g.hitType = 0
    elseif op == 8 then g.carry = 0; g.hitType = g.hitType + 1; return hi
    else return 0 end
  end
  return 0
end
M.runOps = runOps

local function target(g, f)
  local r = f.room
  return (word(g, 1)), (word(g, 2))
end

-- sub_0806EE20 (no interaction: the port's guards are not talked to here)
function M.step(f, e)
  local g = e.guard71
  if not g.list then return 0 end
  if g.carry == 0 then return runOps(g, e, f)
  elseif g.carry == 1 then -- sub_0806EE70
    g.kbSpeed = g.kbSpeed + 1
    local tx, ty = target(g, f)
    if g.kbSpeed > 8 then
      g.kbSpeed = 0
      e.direction = S27().dir32(ix(e.x), ix(e.y), tx, ty)
      if band(g.cflags, 1) == 0 then g.kbd = S27().state4(e.direction) end
    end
    linear(e, e.direction or 0, e.speed or 0)
    local dx, dy = ix(e.x) - tx, ix(e.y) - ty
    local d16 = math.floor(math.sqrt((dx * dx + dy * dy) * 256))
    local sp = math.abs(e.speed or 0)
    if math.floor(sp / 8) <= d16 then return 0 end
    g.hitType = g.hitType + 3
    return runOps(g, e, f)
  elseif g.carry == 2 then -- sub_0806EED0
    g.kbSpeed = band(g.kbSpeed - 1, 0xFF)
    if g.kbSpeed == 0 then g.hitType = g.hitType + 2; return runOps(g, e, f) end
    return 0
  elseif g.carry == 3 then -- sub_0806EEF4
    if not e.anim or band(e.anim.flags or 0, 0x80) ~= 0 then g.hitType = g.hitType + 1; return runOps(g, e, f) end
    return 0
  end
  return 0
end

local function setAnim(f, e, i)
  if e.guard71.animIdx == i then return end
  e.guard71.animIdx = i
  pcall(S27().anim, e, i)
end

-- sub_080644C8: the guard on screen
local function onScreen(f, e)
  local cx, cy = f.camX or 0, f.camY or 0
  local x, y = ix(e.x) - ix(cx), ix(e.y) - ix(cy)
  if x + 8 < 0 or x - 8 > 240 then return false end
  if y < 0 or y - 0x18 > 160 then return false end
  return true
end
M.onScreen = onScreen

-- the ray against Link (the box test with gPlayerHitbox)
local function rayHits(f, ray)
  local p = f.player
  if not p or p.hidden or p.state == "dead" then return false end
  local HB = require("src.zelda.tmc.Hitboxes")
  local pb = (HB.player and HB.player(f, p)) or { x = 0, y = -3, w = 6, h = 6 }
  local hb = RAY_HB
  return math.abs((ix(p.x) + (pb.x or 0)) - (ix(ray.x) + (hb.x or 0))) <= (pb.w or 6) + (hb.w or 4)
     and math.abs((ix(p.y) + (pb.y or 0)) - (ix(ray.y) + (hb.y or 0))) <= (pb.h or 6) + (hb.h or 4)
end
M.rayHits = rayHits

-- GuardLineOfSight, both types, for one guard
function M.sight(f, e)
  local g = e.guard71
  local los = g.los
  if los then
    if g.seen then g.los = nil
    else
      los.x, los.y = e.x, e.y
      if los.subtimer > 0 then los.subtimer = los.subtimer - 1
      elseif onScreen(f, e) then
        local t = los.timer
        los.timer = band(t + 1, 0xFF)
        if band(t, 3) == 0 then
          local off = LOS_DIRS[band(rshift(los.timer, 2), 7)] or 0
          g.rays[#g.rays + 1] = { x = e.x, y = e.y, dir = band(off + g.kbd * 8, 0x1F), timer = M.RAY_TIME }
        end
      end
    end
  end
  for i = #g.rays, 1, -1 do
    local r = g.rays[i]
    r.timer = r.timer - 1
    local gone = r.timer <= 0
    if not gone then
      linear(r, r.dir, M.RAY_SPEED)
      if f.room and f.room.isSolid and f.room:isSolid(r.x, r.y, 1) then gone = true
      elseif M.rayHits(f, r) then g.seen = true; gone = true end
    end
    if gone then table.remove(g.rays, i) end
  end
end

-- script_GuardGarden7 (the garden's NPC4E): CheckRoomFlag $F -> TEXT_VAATI $21, MAENIWA_00_WARP,
-- NPC4E_DoScreenTransition 3 = gNpc4ETransitions[3] (gUnk_0813ABF8, TRANSITION_FADE_BLACK_SLOW): the port's
-- NPC4E transition list (BossVaati3.NPC4E_TRANSITIONS) had no index 3, so a caught Link stayed in the garden
function M.registerTransition()
  local ok, V3 = pcall(require, "src.zelda.tmc.BossVaati3")
  if ok and type(V3) == "table" and V3.NPC4E_TRANSITIONS then
    V3.NPC4E_TRANSITIONS[3] = V3.NPC4E_TRANSITIONS[3] or RT.fresh("Guard71.TR_ABF8")
    return V3.NPC4E_TRANSITIONS[3]
  end
end

function M.init(f, e)
  if not M._tr then M._tr = true; M.registerTransition() end
  local t = e.form or 0
  local g = { base = 0, hitType = 0, kbSpeed = 0, carry = 0, cflags = 0, kbd = e.animationState or 0, rays = {} }
  e.guard71 = g
  g.list = PATHS[t]
  if t <= 3 then g.los = { subtimer = M.LOS_SUBTIMER, timer = band(rand(f), 0xFF), x = e.x, y = e.y } end
  e.action = 1
  e.animationState = g.kbd
  setAnim(f, e, 4 + g.kbd)
end

function M.update(f, e)
  if not e.guard71 then M.init(f, e) end
  local g = e.guard71
  if e.action == 1 then
    if g.seen then
      e.action, g.timer = 2, 30
      e.animationState = S27().state4(S27().dir32(ix(e.x), ix(e.y), ix(f.player.x), ix(f.player.y)))
      setAnim(f, e, e.animationState + 4)
    else
      M.step(f, e)
      if g.kbd ~= e.animationState then e.animationState = g.kbd end
      setAnim(f, e, e.animationState + 4)
    end
  elseif e.action == 2 then
    g.timer = band(g.timer - 1, 0xFF)
    if g.timer == 0 then f:setFlag("room", M.CAUGHT_FLAG, true) end
  end
  M.sight(f, e)
end

return M
