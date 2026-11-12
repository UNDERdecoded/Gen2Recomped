-- Round 12: Deepwood Shrine's enemies, ported from the decomp's own code
-- (src/enemy/puffstool.c, src/enemy/sluggula.c).  Enemies.lua dispatches
-- PUFFSTOOL ($12) and SLUGGULA ($10) here.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Random() is the cartridge's (Drops.random on the shared seed);
--     directions are 0-31 (0 north, clockwise), DirectionRound = & $18;
--     GravityUpdate: z += zVelocity while airborne, zVelocity -= gravity,
--     landing clears both; the home rectangle is sub_0804A720's.
--   * Enemy target (sub_08049DF4(1) -> sub_08049E4C): full-size Link only,
--     not while he is busy / falling / in a portal / Minish.
--
--   PUFFSTOOL (health 1, spored hitType $82, bare $83):
--     action 0 sub_080251FC: spores (unk_82) 240, direction Random & $1C,
--       sub_080256B4 (wander: timer (R & 3) + 4, subtimer 30, direction +7 +
--       (R % 7) * 4 & $1C, unk_78 = gUnk_080CC000[R & 15], unk_7a =
--       (R % 24) * 2), animation 0;
--     action 1 sub_08025230: moves only on keyframes whose flag bit 0 is
--       clear (sub_08025C44); every timer: sub_08025C60 (outside home 1/2:
--       homeward, else direction + gUnk_080CC0C2[R & 7]); against a wall
--       for 30 frames: bounce (sub_0800417E: mirror on the blocked axis);
--       when unk_78 runs out, sub_0802571C looks for a free 2x2 tile corner
--       in gUnk_080CC020 (4 tries from unk_7a; no TILE_TYPE_786, no
--       ACT_TILE_22, no collision) -> action 2;
--     action 2 sub_080252E0: walk to the corner (240 frames a tile at most),
--       there action 3 (timer 30, zVelocity 1.5, animation 1);
--     actions 3-6: the double hop: wait, crouch, rise until zVelocity <
--       1/8 (animation 2), fall (gravity 32/256), land (animation 3), hop
--       again at zVelocity 2.0; the second landing (action 6) withers the
--       grass under its four corners (ACT_TILE_10 -> tile $61, sub_0807B7D8)
--       and puffs FX_BROWN_SMOKE + FX_BROWN_SMOKE_LARGE, then 30 frames and
--       back to wandering;
--     actions 9-11 (sub_08025514 / 08025554 / 080255AC, the flee / spot
--       jump near Link) are only reachable from each other in the decomp;
--       they are ported as written;
--     action 12 sub_0802563C: bare (after the Gust Jar): stands, palette
--       $7C, unk_84 = $294 frames, blinking (gUnk_080CBFF8) in the last 120,
--       then spored again (palette $28, hitType $82, spores 240);
--     OnGrabbed (Gust Jar): faces away from the jar (animation state + 4),
--       loses 3 spores a frame (a DIRT_PARTICLE every 4th), below 4: bare
--       (hitType $83, palette $7C, unk_84 $294); let go: action 8
--       (animation 8, gravity), landed: action 12 when bare (FX_STARS) or
--       wandering again.
--     Collisions (gCollisionMtx): spored $82 hurts Link (2) and shrugs off
--       the sword (no damage, knockback, SFX_186); bare $83 only pushes Link
--       (handler 16) and takes the sword's 2: one hit kills it.
--   SLUGGULA:
--     type 0 (sub_08023CE0): hangs at z 128, drawn off, until full-size Link
--       is within $20 (PlayerInRange); then 8 frames, SFX_12D, animation 4,
--       falls (gravity 24/256), SFX_WATER_SPLASH; the landing animation's
--       frame flags 1-3 move it down 1 / 2 / 6 px; done: it becomes a type 1
--       (CreateEnemy + EnemyCopyParams);
--     type 1 (sub_08023C5C / sub_08023C8C): crawls (ProcessMovement0 at its
--       definition's speed), every 28 frames leaves a type 2 slime
--       (gUnk_080CBDF7 offsets); every (R & $30) + 180 frames (re-checked
--       each 8 while the keyframe flag is not 1) sub_08023E9C turns it:
--       outside home 1/2 homeward (DirectionRoundUp), Link in home and
--       R & 6: 8 toward him when he is more than 45 degrees off, else
--       gUnk_080CBDFF[(R >> 4) % 3];
--     type 2: the slime trail, animation 5 until done (no collision).
-- NOT EXACT: ProcessMovement0's wall slide is per axis here; the Gust
-- Jar's grab test is the port's cone (Items.lua); FX_STARS / dirt
-- particles are drawn as SPECIAL_FX.

local bit = require("bit")
local band, bor, rshift, bxor = bit.band, bit.bor, bit.rshift, bit.bxor
local Drops = require("src.zelda.tmc.Drops")

local D = {}

local SFX_186, SFX_12D, SFX_WATER_SPLASH = 0x186, 0x12D, 0x12B
local FX_STARS, FX_BROWN_SMOKE, FX_BROWN_SMOKE_LARGE = 0x1C, 0x22, 0x23
local SPECIAL_FX = 0x0F
local HIT_SPORED, HIT_BARE = 0x82, 0x83
local PAL_SPORED, PAL_BARE = 0x28, 0x7C

local function R(f) return Drops.random(Drops.rngOf(f)) end
D.R = R

local function dirVec(d)
  local a = (d % 32) / 32 * 2 * math.pi
  return math.sin(a), -math.cos(a)
end
-- CalculateDirectionTo / GetFacingDirection (0-31)
local function dirTo(ax, ay, bx, by)
  local a = math.atan2(bx - ax, -(by - ay))
  return math.floor(a / (2 * math.pi) * 32 + 0.5) % 32
end
D.dirTo = dirTo

-- sub_08049E4C: the enemy target (full-size Link, not busy)
local BUSY = { fall = true, portal = true, dead = true, climb = true, cart = true, hole = true, drown = true, itemget = true }
function D.target(f)
  local p = f.player
  if p.minish or BUSY[p.state or "normal"] or p.portalMode or p.hidden or p.control == false then return nil end
  return p
end

local function inHome(e, x, y)
  return x - e.homeX >= 0 and x - e.homeX <= e.rangeW and y - e.homeY >= 0 and y - e.homeY <= e.rangeH
end
local function homeDir(e) return dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2) end

-- GravityUpdate (z positive up here); returns true while airborne
local function gravity(e, g)
  local nz = (e.z or 0) + (e.zv or 0)
  if nz > 0 then e.z = nz; e.zv = (e.zv or 0) - g; return true end
  e.z, e.zv = 0, 0
  return false
end
D.gravity = gravity

-- ProcessMovement0 (per axis); returns hitX, hitY (wall on that axis)
local function solidBox(E, e, x, y)
  local room = E.field.room
  local hb = e.hitbox
  local hw, hh = math.max(2, hb.w), math.max(2, hb.h)
  local cx, cy = x + hb.x, y + hb.y
  local L = (e.layer == 2) and 2 or 1 -- round 23: the entity's own collision layer (gCollisionDataPtrs[layer]; the Cave of Flames is all top layer)
  return room:isSolid(cx - hw, cy - hh, L) or room:isSolid(cx + hw - 1, cy - hh, L)
      or room:isSolid(cx - hw, cy + hh - 1, L) or room:isSolid(cx + hw - 1, cy + hh - 1, L)
end
function D.move0(E, e, dir, speed)
  local vx, vy = dirVec(dir)
  local s = (speed or 0) / 256
  local hitX, hitY = false, false
  if vx ~= 0 then
    local nx = e.x + vx * s
    if solidBox(E, e, nx, e.y) then hitX = true else e.x = nx end
  end
  if vy ~= 0 then
    local ny = e.y + vy * s
    if solidBox(E, e, e.x, ny) then hitY = true else e.y = ny end
  end
  if math.abs(vx) < 1e-6 then hitX = false end
  if math.abs(vy) < 1e-6 then hitY = false end
  return hitX, hitY
end

-- sub_0800417E: bounce off the wall that stopped it
local function bounce(e, hitX, hitY)
  local d = e.dir
  if hitX then d = 0x20 - d end
  if hitY then d = 0x10 - d end
  e.dir = band(d, 0x1F)
end

local function setAnim(E, e, i) e.animIndex = nil; E:setAnim(e, i) end

-- ChangeObjPalette: a per-entity definition copy so the sprite cache key
-- follows the palette
local function setPalette(E, e, pal)
  if e.palId == pal then return end
  e.palId = pal
  e.palette = E.A:objPalette(pal, E.field.room.atlas and E.field.room.atlas.palettes)
  e.def = setmetatable({ palette = pal }, { __index = e.baseDef or e.def })
end

local function frameFlags(e) return e.anim.flags or 0 end

-- ===========================================================================
-- PUFFSTOOL
-- ===========================================================================
local P = {}
D.puff = P

local T_WANDER = { 30, 30, 90, 90, 180, 180, 180, 180, 180, 240, 240, 240, 240, 240, 300, 300 } -- gUnk_080CC000
local T_SPOTS = { -0x20, -0x20, -0x20, -0x10, -0x20, 0x00, -0x20, 0x10, -0x20, 0x20, -0x10, -0x20,
                  -0x10, -0x10, -0x10, 0x00, -0x10, 0x10, -0x10, 0x20, 0x00, -0x20, 0x00, -0x10,
                  0x00, 0x10, 0x00, 0x20, 0x10, -0x20, 0x10, -0x10, 0x10, 0x00, 0x10, 0x10,
                  0x10, 0x20, 0x20, -0x20, 0x20, -0x10, 0x20, 0x00, 0x20, 0x10, 0x20, 0x20 } -- gUnk_080CC020
local T_FLEE = { 90, 120, 120, 90, 180, 180, 180, 180 } -- gUnk_080CC050 (8 entries; R & 15 reads past it in the ROM)
local T_JUMPS = { -- gUnk_080CC090
  [0] = { 0x00, 0x00, 0x00, -0x10, -0x10, 0x00, 0x10, 0x00, 0x00, 0x10 },
  { 0x00, 0x20, 0x10, 0x10, 0x20, 0x00, 0x10, -0x10, 0x00, -0x20, -0x10, -0x10, -0x20, 0x00, -0x10, 0x10 },
  { -0x20, -0x10, -0x10, -0x20, 0x10, -0x20, 0x20, -0x10, 0x20, 0x10, 0x10, 0x20, -0x10, 0x20, -0x20, 0x10 },
  { 0x20, 0x20, 0x20, -0x20, -0x20, -0x02, -0x20, 0x20 },
}
local T_CORNERS = { -0x8, -0x8, -0x8, 0x8, 0x8, -0x8, 0x8, 0x8 } -- gUnk_080CC0A0
local T_BLINK = { [0] = 1, 1, 1, 3, 3, 3, 7, 7 } -- gUnk_080CBFF8
local T_TURN = { [0] = -1, 1, -2, 2, -3, 3, -4, 4 } -- gUnk_080CC0C2
local T_DIRT = { [0] = { 0x00, -0x10 }, { 0x13, 0x00 }, { 0x00, 0x14 }, { -0x13, 0x00 } } -- gUnk_080CC0BA
P.T_SPOTS, P.T_JUMPS, P.T_WANDER = T_SPOTS, T_JUMPS, T_WANDER

local function tileFree(E, e, x, y, viaType)
  local f = E.field
  local room = f.room
  local L = e.layer or 1
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  if tx < 0 or ty < 0 or tx >= (room.tw or 0) or ty >= (room.th or 0) then return false end
  local coll = room.coll and room.coll[L] and room.coll[L][ty * room.tw + tx] or 0
  if coll ~= 0 then return false end
  if viaType then
    local tt = room:tileType(L, tx, ty)
    if tt == 786 then return false end
    local act = tt and tt < 0x4000 and f.assets.actTile[tt] or 0
    if act == 0x16 then return false end
  end
  return true
end

-- sub_080256B4
function P.wander(E, e)
  local f = E.field
  e.action = 1
  e.timer = band(R(f), 3) + 4
  e.subtimer = 30
  e.dir = band(e.dir + 7 + (R(f) % 7) * 4, 0x1C)
  e.unk78 = T_WANDER[band(R(f), 15) + 1]
  e.unk7a = (R(f) % 0x18) * 2
  e.unk7b = 0
end

-- sub_0802571C
function P.findSpot(E, e)
  local rx, ry = band(math.floor(e.x) + 8, -16), band(math.floor(e.y) + 8, -16)
  local u = e.unk7a
  for _ = 1, 4 do
    local x, y = rx + T_SPOTS[u + 1], ry + T_SPOTS[u + 2]
    -- sub_080257EC: any of the four tiles around the corner free
    if tileFree(E, e, x, y, true) or tileFree(E, e, x - 16, y, true) or tileFree(E, e, x, y - 16, true) or tileFree(E, e, x - 16, y - 16, true) then
      e.unk7c, e.unk7e = x, y
      return true
    end
    u = u + 2
    if u > 0x2F then u = 0 end
  end
  e.unk7a = u
  e.unk7b = e.unk7b + 1
  return false
end

-- sub_0802594C
function P.jumpSpot(E, e, n)
  local list = T_JUMPS[n]
  if not list then return false end
  local rx, ry = band(math.floor(e.x) + 8, -16), band(math.floor(e.y) + 8, -16)
  for i = 1, #list, 2 do
    local x, y = rx + list[i], ry + list[i + 1]
    if tileFree(E, e, x, y) and tileFree(E, e, x - 16, y) and tileFree(E, e, x, y - 16) and tileFree(E, e, x - 16, y - 16) then
      e.unk7c, e.unk7e = x, y
      return true
    end
  end
  return false
end

-- sub_080258C4
function P.nearLink(E, e)
  local t = D.target(E.field)
  if not t then return false end
  local dx, dy = math.floor(t.x) - math.floor(e.x), math.floor(t.y) - math.floor(e.y)
  local d2 = dx * dx + dy * dy
  if e.unk84 == 0 and e.unk81 == 0 and d2 <= 0x400 then
    e.action, e.timer = 9, 0
    return true
  elseif d2 <= 0x900 then
    e.action, e.timer = 11, 1
    e.unk78 = T_FLEE[band(R(E.field), 15) + 1] or 180
    return true
  end
  return false
end

-- sub_08025C44: move on keyframes with flag bit 0 clear
local function step(E, e)
  if band(frameFlags(e), 1) == 0 then return D.move0(E, e, e.dir, e.speed) end
  return false, false
end

-- sub_08025A54 / sub_08025AB8: grass under the four corners withers
function P.wither(E, e)
  local f = E.field
  local L = e.layer or 1
  for i = 1, #T_CORNERS, 2 do
    local tx, ty = math.floor((e.x + T_CORNERS[i]) / 16), math.floor((e.y + T_CORNERS[i + 1]) / 16)
    local room = f.room
    local coll = room.coll and room.coll[L] and room.coll[L][ty * room.tw + tx] or 1
    local tt = room:tileType(L, tx, ty)
    local act = tt and tt < 0x4000 and f.assets.actTile[tt] or 0
    if coll == 0 and act == 0x10 then f:objects():setTileType(L, tx, ty, 0x61) end
  end
end

function P.dirt(E, e)
  if (e.unk82 or 0) ~= 0 and band(frameFlags(e), 1) == 0 then
    local o = T_DIRT[e.animationState or 0] or T_DIRT[0]
    E.field:addFx(e.x + o[1], e.y + o[2] - 10, SPECIAL_FX, FX_BROWN_SMOKE)
  end
end

local function bare(E, e)
  e.unk84 = 0x294
  e.hitType = HIT_BARE
  e.unk82 = 0
  setPalette(E, e, PAL_BARE)
end

function P.update(E, e)
  local f = E.field
  if e.puffInit == nil then
    e.puffInit = true
    e.baseDef = e.def
    e.unk78, e.unk7a, e.unk7b, e.unk7c, e.unk7e, e.unk80, e.unk81, e.unk82, e.unk84 = 0, 0, 0, 0, 0, 0, 0, 240, 0
    e.subtimer = 0
    e.hitType = HIT_SPORED
  end
  -- OnGrabbed: the Gust Jar has it (Items.lua sets e.gusted each frame)
  if e.gusted then
    e.gusted = nil
    gravity(e, 0.125)
    if e.grabSub == nil then
      -- sub_08025180
      e.grabSub = 1
      e.timer = band(R(f), 0xFF)
      e.animationState = rshift(bxor(e.gustDir or 0, 0x10), 3)
      setAnim(E, e, e.animationState + 4)
    else
      -- sub_080251AC
      if e.unk82 >= 4 then
        e.unk82 = e.unk82 - 3
        e.timer = band(e.timer - 1, 0xFF)
        if band(e.timer, 3) == 0 then P.dirt(E, e) end
      elseif e.hitType ~= HIT_BARE then
        bare(E, e)
      end
      e.anim:update(1)
    end
    e.wasGusted = true
    return
  elseif e.wasGusted then
    -- let go (sub_0806F520 false): sub_08025C2C
    e.wasGusted, e.grabSub = nil, nil
    e.action = 8; e.unk80 = 0
    setAnim(E, e, 8)
  end
  local a = e.action
  if a == 0 then
    -- sub_080251FC
    e.unk82 = 240
    e.dir = band(R(f), 0x1C)
    e.unk80 = 0
    P.wander(E, e)
    setAnim(E, e, 0)
  elseif a == 1 then
    -- sub_08025230
    if e.unk81 > 0 then e.unk81 = e.unk81 - 1 end
    local hx, hy = step(E, e)
    e.anim:update(1)
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.timer = band(R(f), 3) + 4
      -- sub_08025C60
      if not inHome(e, e.x, e.y) and band(R(f), 1) ~= 0 then e.dir = homeDir(e)
      else e.dir = band(T_TURN[band(R(f), 7)] + e.dir, 0x1F) end
    end
    if hx or hy then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then bounce(e, hx, hy) end
    else
      e.subtimer = 30
    end
    if e.unk78 == 0 then
      if P.findSpot(E, e) then
        e.action, e.timer = 2, 240
        e.tilePos = math.floor(e.x / 16) + 64 * math.floor(e.y / 16)
      end
    else
      e.unk78 = e.unk78 - 1
    end
  elseif a == 2 then
    -- sub_080252E0
    e.dir = dirTo(e.x, e.y, e.unk7c, e.unk7e)
    -- the last fraction of a pixel lands on the corner (HALF.HI compare)
    local dx, dy = e.unk7c - e.x, e.unk7e - e.y
    if math.abs(dx) <= (e.speed or 64) / 256 and math.abs(dy) <= (e.speed or 64) / 256 then
      if band(frameFlags(e), 1) == 0 then e.x, e.y = e.unk7c, e.unk7e end
    else
      step(E, e)
    end
    e.anim:update(1)
    local tp = math.floor(e.x / 16) + 64 * math.floor(e.y / 16)
    if tp == e.tilePos then
      e.timer = e.timer - 1
      if e.timer == 0 then P.wander(E, e) end
    else
      e.tilePos = tp
      e.timer = 240
    end
    if math.floor(e.x) == e.unk7c and math.floor(e.y) == e.unk7e then
      e.action, e.timer, e.subtimer = 3, 30, 0
      e.zv = 1.5
      setAnim(E, e, 1)
    end
  elseif a == 3 then
    -- sub_0802538C
    if e.timer > 0 then e.timer = e.timer - 1
    elseif frameFlags(e) == 0 then e.anim:update(1)
    else
      gravity(e, 0.125)
      if e.zv < 0.125 then e.action = 4; setAnim(E, e, 2) end
    end
  elseif a == 4 then
    -- sub_080253D4
    e.anim:update(1)
    if not gravity(e, 0.125) then
      if e.subtimer == 0 then
        e.action = 5; setAnim(E, e, 3)
      else
        e.action, e.timer = 6, 30
        setAnim(E, e, 3)
        P.wither(E, e)
        f:addFx(e.x, e.y - 1, SPECIAL_FX, FX_BROWN_SMOKE)
        f:addFx(e.x, e.y + 1, SPECIAL_FX, FX_BROWN_SMOKE_LARGE)
      end
    end
  elseif a == 5 then
    -- sub_0802541C
    e.anim:update(1)
    if e.anim.done then
      e.action, e.subtimer = 3, 1
      e.zv = 2.0
      setAnim(E, e, 1)
    end
  elseif a == 6 then
    -- sub_0802544C
    if frameFlags(e) == 0 then e.anim:update(1)
    else
      e.timer = e.timer - 1
      if e.timer == 0 then P.wander(E, e); setAnim(E, e, 0) end
    end
  elseif a == 7 then
    -- sub_0802547C (blown by a Gust Jar shot)
    gravity(e, 0.125)
    e.anim:update(1)
    if band(e.timer, 7) == 0 then P.dirt(E, e) end
    e.timer = e.timer - 1
    if e.timer == 0 then e.action = 8; e.unk80 = 0; setAnim(E, e, 8) end
  elseif a == 8 then
    -- sub_080254B4
    gravity(e, 0.125)
    if e.anim.done then
      if (e.z or 0) == 0 then
        if e.unk84 == 0 then
          e.hitType = HIT_SPORED
          e.unk82 = 240 -- (u8)-0x10
          P.wander(E, e)
        else
          e.action = 12
          f:addFx(e.x, e.y - 12, SPECIAL_FX, FX_STARS)
        end
        setAnim(E, e, 0)
      end
    else
      e.anim:update(1)
    end
  elseif a == 9 then
    -- sub_08025514
    e.anim:update(1)
    local n = e.timer; e.timer = e.timer + 1
    if P.jumpSpot(E, e, n) then
      e.action, e.timer, e.unk81 = 2, 240, 120
      e.tilePos = math.floor(e.x / 16) + 64 * math.floor(e.y / 16)
    elseif e.timer > 3 then
      e.action, e.timer = 10, 32
    end
  elseif a == 10 then
    -- sub_08025554
    local t = D.target(f)
    if not t then P.wander(E, e) else
      if band(e.timer, 3) == 0 then e.dir = dirTo(t.x, t.y, e.x, e.y) end
      step(E, e)
      e.anim:update(1)
      if e.timer > 0 then e.timer = e.timer - 1
      elseif not P.nearLink(E, e) then P.wander(E, e) end
    end
  elseif a == 11 then
    -- sub_080255AC
    local t = D.target(f)
    if not t then P.wander(E, e) else
      if e.unk81 > 0 then e.unk81 = e.unk81 - 1 end
      e.timer = e.timer - 1
      if e.timer == 0 then
        e.timer = band(R(f), 3) + 4
        local r = band(R(f), 0xF)
        if r < 8 then r = r - 1 end
        r = r - 7
        e.dir = band(dirTo(t.x, t.y, e.x, e.y) + r, 0x1F)
      end
      if e.unk78 == 0 then
        if not P.nearLink(E, e) then P.wander(E, e) end
      else
        e.unk78 = e.unk78 - 1
      end
      step(E, e)
      e.anim:update(1)
    end
  elseif a == 12 then
    -- sub_0802563C
    e.anim:update(1)
    e.unk84 = e.unk84 - 1
    if e.unk84 == 0 then
      setPalette(E, e, PAL_SPORED)
      e.hitType = HIT_SPORED
      e.unk82 = 240
      P.wander(E, e)
    elseif e.unk84 < 120 then
      local m = T_BLINK[rshift(e.unk84, 4)]
      if band(e.unk84, m) == 0 then
        setPalette(E, e, band(e.unk84, m + 1) ~= 0 and PAL_BARE or PAL_SPORED)
      end
    end
  end
end

-- Puffstool_OnCollide's default case: a spored one shrugs off the sword
function P.shrug(E, e)
  E.field:sound(SFX_186)
  E.field:addFx(e.x, e.y - 6, SPECIAL_FX, FX_BROWN_SMOKE)
end

-- ===========================================================================
-- SLUGGULA
-- ===========================================================================
local S = {}
D.slug = S
local T_LAND = { 1, 2, 6 } -- gUnk_080CBDF4
local T_SLIME = { [0] = { 0, 2 }, { -2, 2 }, { 0, -2 }, { 2, 2 } } -- gUnk_080CBDF7
local T_TURNS = { [0] = 0, -8, 8 } -- gUnk_080CBDFF

-- sub_08023E9C
function S.turn(E, e)
  local f = E.field
  local r = R(f)
  local t = D.target(f)
  if not inHome(e, e.x, e.y) and band(r, 1) ~= 0 then
    e.dir = band(homeDir(e) + 4, 0x18)
  elseif t and inHome(e, t.x, t.y) and band(r, 6) ~= 0 then
    local d = dirTo(e.x, e.y, t.x, t.y) - e.dir
    if d ~= 0 and band(d + 4, 0x1F) > 8 then
      if band(d, 0x1F) < 0x10 then e.dir = band(e.dir + 8, 0x18) else e.dir = band(e.dir - 8, 0x18) end
    end
  else
    e.dir = band(e.dir + T_TURNS[rshift(r, 4) % 3], 0x18)
  end
end

function S.slime(E, e)
  local f = E.field
  local o = T_SLIME[e.animationState or 0] or T_SLIME[0]
  local d = E:def(0x10, 2)
  if not d then return end
  local s = E:spawn({ id = 0x10, paramA = 2, paramB = 0, paramC = 0, x = e.x + o[1], y = e.y + o[2] })
  if s then
    s.slime = true; s.inert = true; s.layer = e.layer; s.spritePriority = 6
    E:setAnim(s, 5)
    f.entities[#f.entities + 1] = s
  end
end

function S.update(E, e)
  local f = E.field
  if e.slime then
    -- sub_08023E10
    e.anim:update(1)
    if e.anim.done then e.deleted = true end
    return
  end
  if e.form == 0 then
    local a = e.action
    if a == 0 then
      if e.type2 ~= 1 then e.timer = 0 end -- the entity's own timer (0 from the room data)
      e.action = (e.type2 == 1) and 2 or 1
      if e.action == 2 then if (e.timer or 0) == 0 then e.timer = 1 end; e.hidden = false else e.hidden = true end
      e.z, e.zv = 128, 0
      setAnim(E, e, 6)
    elseif a == 1 then
      -- PlayerInRange(this, 1, $20): same collision layer, distance <= $20
      local t = D.target(f)
      if t and band(t.layer or 1, e.layer or 1) ~= 0
         and (math.floor(t.x) - math.floor(e.x)) ^ 2 + (math.floor(t.y) - math.floor(e.y)) ^ 2 <= 0x20 * 0x20 then
        e.action = 2
        if (e.timer or 0) == 0 then e.timer = 8 end
        e.hidden = false
      end
    elseif a == 2 then
      if e.timer ~= 0 then
        e.timer = e.timer - 1
        if e.timer == 0 then f:sound(SFX_12D); setAnim(E, e, 4) end
      elseif not gravity(e, 24 / 256) then
        e.action = 3
        f:sound(SFX_WATER_SPLASH)
      end
    else
      e.anim:update(1)
      local fl = frameFlags(e)
      if fl ~= 0 then
        if band(fl, 0x80) ~= 0 then
          -- CreateEnemy(SLUGGULA, 1) + EnemyCopyParams, then this one goes
          local d = E:def(0x10, 1)
          if d then
            e.form = 1
            e.def, e.baseDef = d, nil
            e.health, e.maxHealth, e.speed, e.hitType = d.health, d.health, d.speed, d.damageType
            e.hitbox = d.hitbox or e.hitbox
            e.sprite = d.sprite
            e.palette = E.A:objPalette(d.palette, f.room.atlas and f.room.atlas.palettes)
            e.gfx = require("src.zelda.tmc.Assets").gfxSource("enemy", d.gfx)
            e.action = 0
            e.z, e.zv = 0, 0
          end
        else
          e.y = e.y + (T_LAND[fl] or 0)
          e.anim.flags = 0
        end
      end
    end
    return
  end
  -- type 1
  if e.action == 0 then
    -- sub_08023C5C
    e.action = 1
    e.timer = band(R(f), 0x30) + 180
    e.dir = band(R(f), 0x18)
    e.animationState = rshift(e.dir, 3)
    e.subtimer = 0
    setAnim(E, e, e.animationState)
  else
    -- sub_08023C8C
    D.move0(E, e, e.dir, e.speed)
    e.anim:update(1)
    -- sub_08023E54
    local st = e.subtimer or 0
    e.subtimer = st + 1
    if st > 27 then e.subtimer = 0; S.slime(E, e) end
    e.timer = e.timer - 1
    if e.timer == 0 then
      if frameFlags(e) ~= 1 then e.timer = 8
      else
        e.timer = band(R(f), 0x30) + 180
        S.turn(E, e)
        e.animationState = rshift(e.dir, 3)
        setAnim(E, e, e.animationState)
      end
    end
  end
end

-- ===========================================================================
-- MULLDOZER (mulldozer.c)
--   action 1 sub_08033058: stand/turn (timer gUnk_080CEA50[R & 3]; outside
--     home 3/4 homeward +-4, else R & $18); Link (full size) within $38 in
--     the rect and in front (Direction8RoundUp of the bearing == its 8-way
--     animation state; type 1: $48, any side) -> action 3;
--   action 2 sub_080330C0: walk $60 (type 0: (R & $38) + 24 frames);
--   action 3 sub_08033100: type 0 winds up 48 frames re-aiming at Link every
--     8 (sub_08033280), the last 16 with the fast animation; then
--   action 4: charge at $1E0 for 30/45/60/75 frames (sub_080331B4),
--     weaving 45 degrees left / right every 16 frames;
--   action 5 sub_08033174: slows ($A0, (R & $18) + 24 frames) turning one
--     step toward Link every 4 (sub_08004596), then sub_08033320 picks a
--     cardinal and walks again;
--   a hit sends it to action 5; walls bounce it (sub_0800417E); a dust puff
--   every 16 frames (8 while fast) off its back (gUnk_080CEA56).
-- ===========================================================================
local M = {}
D.mull = M
local T_STAND = { [0] = 30, 45, 60, 90 }
local T_DUST = { 0, 6, -3, 3, -6, 0, -3, -3, 0, -6, 3, -3, 6, 0, 3, 3 }

local function mAnim(E, e)
  if e.unk80 == 0 then setAnim(E, e, rshift(e.animationState, 1)) else setAnim(E, e, 4 + e.animationState) end
end
local function mFrames(E, e) if e.unk80 == 2 then e.anim:update(1) end; e.anim:update(1) end
local function mMove(E, e)
  local hx, hy = D.move0(E, e, e.dir, e.speed)
  return hx, hy
end
local function mWalk(E, e) -- sub_08032F64
  if e.hitX or e.hitY then
    bounce(e, e.hitX, e.hitY)
    e.animationState = rshift(e.dir, 2)
    mAnim(E, e)
  end
  mFrames(E, e)
  e.hitX, e.hitY = mMove(E, e)
end
local function mDust(E, e) -- sub_080331E8
  local fire, i = false, 0
  if e.action ~= 5 then
    e.unk83 = band(e.unk83 + 1, e.unk80 ~= 2 and 0xF or 0x7)
    if e.unk83 == 0 then fire = true; i = e.animationState * 2 end
  else
    e.unk83 = band(e.unk83 + 1, 0xF)
    if e.unk83 == 0 then fire = true; i = rshift(e.dir, 1) end
  end
  if fire then
    i = band(i, 0xE)
    E.field:addFx(e.x + T_DUST[i + 1], e.y + T_DUST[i + 2], SPECIAL_FX, 2)
  end
end
local function mStand(E, e) -- sub_08033058
  local f = E.field
  e.action, e.unk80 = 1, 1
  e.timer = T_STAND[band(R(f), 3)]
  if not inHome(e, e.x, e.y) and band(R(f), 3) ~= 0 then
    local h = homeDir(e)
    e.dir = band((band(R(f), 1) == 0 and 252 or 4) + h, 0x18)
  else
    e.dir = band(R(f), 0x18)
  end
  e.animationState = rshift(e.dir, 2)
  mAnim(E, e)
end
local function mWalkStart(E, e) -- sub_080330C0
  local f = E.field
  e.action, e.unk80 = 2, 0
  e.timer = (e.form == 0) and band(R(f), 0x38) + 24 or 6
  e.speed = 0x60
  e.dir = band(e.dir + 4, 0x18)
  e.animationState = rshift(e.dir, 2)
  mAnim(E, e)
end
local function chargeTime(E, e) -- sub_080331B4
  local r = band(R(E.field), 0xF0)
  local t = 30
  if band(r, 0x80) ~= 0 then t = 60 else
    if band(r, 0x40) ~= 0 then t = 45 end
    if band(r, 0x20) ~= 0 then t = 75 end
  end
  e.timer = t
end
local function bearing(E, e)
  local t = D.target(E.field)
  if not t then return 0xFF end
  return dirTo(e.x, e.y, t.x, t.y)
end
local function mSlow(E, e) -- sub_08033174
  e.unk80, e.unk81, e.unk82, e.unk83 = 1, e.dir, 0, 0
  e.timer = (e.form == 0) and band(R(E.field), 0x18) + 24 or 12
  e.speed = 0xA0
  mAnim(E, e)
end
local function mSees(E, e) -- sub_08033364
  local t = D.target(E.field)
  if not t then return false end
  local r = e.form ~= 0 and 0x48 or 0x38
  if math.abs(t.x - e.x) > r or math.abs(t.y - e.y) > r then return false end
  if e.form ~= 0 then return true end
  local d = rshift(band(dirTo(e.x, e.y, t.x, t.y) + 2, 0x1C), 2)
  return e.animationState == d
end

function M.update(E, e)
  local f = E.field
  if not e.mullInit then
    e.mullInit = true
    e.unk80, e.unk81, e.unk82, e.unk83 = 0, 0, 0, 0
    e.subtimer = 0
    mStand(E, e)
    return
  end
  -- a landed hit (Enemies:hit) -> Mulldozer_OnCollision default
  if e.mullShield then
    -- Mulldozer_OnCollision case 2/3: spins off (action 6)
    e.mullShield = nil
    e.action = 6
    e.timer = (e.form ~= 0) and 90 or 200
    e.subtimer, e.unk80, e.speed = 2, 3, 0
    local kd = dirTo(f.player.x, f.player.y, e.x, e.y)
    e.dir = band(kd + (band(R(f), 0x40) ~= 0 and 4 or 0x1C), 0x1F)
  end
  if e.mullHit then
    e.mullHit = nil
    e.action, e.subtimer = 5, 4
    mSlow(E, e)
  end
  local a = e.action
  if a == 1 then
    e.timer = e.timer - 1
    if e.timer == 0 then mWalkStart(E, e)
    elseif mSees(E, e) then
      -- sub_08033100
      e.action = 3
      if e.form == 0 then
        e.unk80, e.timer, e.subtimer, e.speed = 1, 48, 8, 0
        local b = bearing(E, e)
        e.dir = band(b + 2, 0x1C)
      else
        e.unk80 = 2; chargeTime(E, e); e.timer = e.timer + 16; e.subtimer = 4; e.speed = 0x160
      end
      e.unk83 = 0
      e.unk82 = band(R(f), 0x80)
      e.animationState = rshift(e.dir, 2)
      mAnim(E, e)
    end
    mWalk(E, e)
  elseif a == 2 then
    e.timer = e.timer - 1
    if e.timer == 0 then mStand(E, e) end
    mFrames(E, e)
  elseif a == 3 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.subtimer, e.speed = 4, 8, 0x1E0
      chargeTime(E, e)
      if band(e.unk82, 0x80) ~= 0 then e.dir = band(e.dir + 0x1C, 0x1C); e.unk82 = band(e.unk82, 0x7F)
      else e.dir = band(e.dir + 4, 0x1C); e.unk82 = bor(e.unk82, 0x80) end
      e.animationState = rshift(e.dir, 2)
      setAnim(E, e, e.animationState + 4)
    else
      -- sub_08032F90
      if e.form == 0 then
        if e.timer == 16 then e.unk80 = 2 end
        e.subtimer = e.subtimer - 1
        if e.subtimer == 0 then
          e.subtimer = 8
          local b = bearing(E, e)
          if b ~= 0xFF then
            e.dir = band(b + 2, 0x1C)
            local d = rshift(e.dir, 2)
            if d ~= e.animationState then e.animationState = d; setAnim(E, e, d + 4) end
          end
        end
      else
        e.subtimer = e.subtimer - 1
        if e.subtimer == 0 then
          e.subtimer = 4
          e.dir = band(e.dir + (band(e.unk82, 0x80) ~= 0 and 0x1C or 4), 0x1C)
          e.animationState = rshift(e.dir, 2); setAnim(E, e, e.animationState + 4)
        end
      end
      mDust(E, e); mWalk(E, e)
    end
  elseif a == 4 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.subtimer = 5, 4
      mSlow(E, e)
    else
      -- sub_08033000
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then
        e.subtimer = 16
        if band(e.unk82, 0x80) ~= 0 then e.dir = band(e.dir + 0x18, 0x1C); e.unk82 = band(e.unk82, 0x7F)
        else e.dir = band(e.dir + 8, 0x1C); e.unk82 = bor(e.unk82, 0x80) end
        e.animationState = rshift(e.dir, 2); setAnim(E, e, e.animationState + 4)
      end
      mDust(E, e); mWalk(E, e)
    end
  elseif a == 5 then
    e.timer = e.timer - 1
    if e.timer == 0 then
      -- sub_08033320 + sub_080330C0
      local b4 = e.animationState * 4
      if band(b4, 4) ~= 0 then
        local m = band(e.unk82, 3)
        local t = m == 1 and 4 or m == 2 and 0x1C or (band(R(f), 0x10) ~= 0 and 4 or 0x1C)
        e.dir = band(t + b4, 0x18)
      else
        e.dir = b4
      end
      mWalkStart(E, e)
    elseif e.form == 0 then
      e.subtimer = e.subtimer - 1
      if e.subtimer == 0 then
        e.subtimer = 4
        -- sub_080332A8: unk_81 turns one step toward Link (sub_08004596)
        local b = bearing(E, e)
        if b ~= 0xFF then
          local d = band(b - e.unk81, 0x1F)
          if d ~= 0 then e.unk81 = band(e.unk81 + (d < 0x10 and 1 or -1), 0x1F) end
        end
        local s = rshift(band(e.unk81 + 2, 0x1C), 2)
        if s ~= e.animationState then
          local t = s - e.animationState
          if t >= 1 then e.unk82 = t < 5 and 1 or 2 else e.unk82 = t < -4 and 1 or 2 end
          e.animationState = s
          setAnim(E, e, s + 4)
        end
      end
    end
    mDust(E, e)
    e.hitX, e.hitY = mMove(E, e)
  elseif a == 6 then
    e.hitX, e.hitY = mMove(E, e)
    mFrames(E, e)
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then
      e.subtimer = 2
      e.animationState = band(e.animationState + 1, 7)
      mAnim(E, e)
      mDust(E, e)
    end
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.subtimer = 5, 4; mSlow(E, e) end
  end
end

return D
