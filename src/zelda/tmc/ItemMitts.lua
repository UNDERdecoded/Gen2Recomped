-- Round 26A: the Mole Mitts (ITEM_MOLE_MITTS $13), src/item/itemMoleMitts.c
-- with the player-side helpers of playerUtils.c and object1F.c.
--
-- PORTED (decomp):
--   ItemMoleMitts state 0 (sub_08077130): not while jumping; sub_080774A0
--     looks at the tile ahead (gUnk_0811BE1E: north (0,-13), east (13,0),
--     south (0,16), west (-13,0)): collision data $0F..$16 is a wall ->
--     ANIM_MOLEMITTS_DIG ($50C + facing), state 2 (an ACT_TILE_86 soft wall
--     also lines Link up: y = tile + 6 facing east/west, x = tile + 8
--     facing north/south); anything else -> ANIM_MOLEMITTS_FLOOR ($508),
--     state 1.
--   state 1 (sub_080771C8): frame flag $10 -> DoItemTileInteraction filter
--     $0D (the tile-interaction table, Objects:tileInteraction: the dirt
--     tile is replaced); nothing -> ANIM_MOLEMITTS_MISS ($520), state 3,
--     SFX_ITEM_GLOVES_AIR; else SFX_108 and, unless the entry's byte 5 is
--     $FF, the clod OBJECT_1F (object1F.c: thrown behind Link from
--     gUnk_08120A20, zVelocity 2.75, gravity 40/256, speed $100, a delay of
--     gUnk_08120A18[n].unk2 frames while the mitts dig) that lands as the
--     entry's object (byte 2) with its type (byte 3): SPECIAL_FX with type2
--     $80 (the FX variant and its drop roll), another object as is; on
--     collision data $21 / $25 / $24 / $30 it is FX_FALL_DOWN /
--     FX_LAVA_SPLASH / FX_WATER_SPLASH instead.  DoTileInteraction itself
--     only makes the object for filter $0D when it is FX_GRASS_CUT.
--   state 2 (sub_080772A8): the speed is gUnk_0811BE16[frame & 7] (0, $C0,
--     $100, $180; doubled with ITEM_DIG_BUTTERFLY except index 3, the
--     animation then runs at 2x) forward; flag 8 with the button pressed
--     again keeps digging; flag $60 -> sub_0807B5B0 (sub_0807B600 at
--     gUnk_0811C456): an ACT_TILE_86 tile is dug (SFX_108), else
--     ANIM_MOLEMITTS_CLANG ($51C), two FX_STARS_STRIKE,
--     SFX_ITEM_GLOVES_KNOCKBACK, state 3 with the push back; flag $10 ends
--     (or digs on when asked and the wall is still there).
--   state 3 (sub_08077448): pushed back at $100 on frames with flag 1
--     (after the clang only) until flag $80.
--   sub_0807B600: the soft wall -> TILE_TYPE_756 (754 under a top tile,
--     756 where collision data 3 is above / below), the ACT_TILE_86 top tile
--     above cleared; the three big rocks (618/615, 634/631, 650/647) as
--     sub_0807B820 / sub_0807B8A8 / sub_0807B930 (a 3 x 2 block: base + 0,
--     +1, +2 above with top +7, +8, +9; +3, +4, +6 on the row).
--   Buried ground items (kind 7) come out by themselves once the tile under
--     them changes (Objects:updateGround = ItemOnGround_Burried_Action2).
-- SIMPLIFIED: DoItemTileInteraction's own offsets (gUnk_08007DF4, a ROM
--   blob) are taken as sub_080774A0's (gUnk_0811BE1E); the edge-blending
--   passes of sub_0807B600 (sub_0807B55C / sub_0807B480 with
--   gUnk_0811C2AC / 2CC / 2EC) are not ported; MOLE_MITTS_PARTICLE is not
--   drawn; frame flags come from Link's animation keyframes (byte 4), read
--   once per keyframe; a sprite without animation data (tests) runs a fixed
--   fallback timeline.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.ITEM = 0x13
M.ITEM_DIG_BUTTERFLY = 0x71
M.ANIM = { floor = 0x508, dig = 0x50C, clang = 0x51C, miss = 0x520 }
M.SFX = { AIR = 0x107, DIG = 0x108, KNOCKBACK = 0x119 }
M.FX = { STARS = 0x1D, FALL = 0x00, LAVA = 0x0C, WATER = 0x0B, GRASS_CUT = 0x17 }
M.ACT_SOFT = 0x56 -- ACT_TILE_86
M.PROBE = { [0] = { 0, -13 }, [2] = { 13, 0 }, [4] = { 0, 16 }, [6] = { -13, 0 } } -- gUnk_0811BE1E / gUnk_0811C456
M.SPEED = { [0] = 0, 0xC0, 0x100, 0x180 }                                         -- gUnk_0811BE16 (index & 7, 4..7 unused)
M.CLOD_OFF = { [0] = { 0, -18 }, [2] = { 16, 0 }, [4] = { 0, 12 }, [6] = { -16, 0 } } -- gUnk_08120A20
M.CLOD = { [0] = { anim = 0, pal = 2, delay = 0x0A }, [1] = { anim = 0, pal = 5, delay = 0x20 } } -- gUnk_08120A18
M.TT = { WALL_754 = 754, WALL_756 = 756 }
M.BIG = { [618] = { 0, 620 }, [615] = { 1, 620 }, [634] = { 0, 636 }, [631] = { 1, 636 }, [650] = { 0, 652 }, [647] = { 1, 652 } }
local SPECIAL_FX, OBJECT_1F = 0x0F, 0x1F

-- the fallback frame flags when Link's sprite has no animation data
local FALLBACK = {
  floor = { [8] = 0x10, [14] = 0x80 },
  dig = { [1] = 0x01, [5] = 0x42, [9] = 0x09, [12] = 0x10 },
  clang = { [1] = 0x01, [8] = 0x80 },
  miss = { [8] = 0x80 },
}

local function tileAt(p)
  local o = M.PROBE[band(p.animationState or 4, 6)]
  return math.floor((p.x + o[1]) / 16), math.floor((p.y + o[2]) / 16)
end
M.tileAt = tileAt

local function coll(room, layer, tx, ty)
  local c = room.coll and room.coll[layer == 2 and 2 or 1]
  return c and c[ty * room.tw + tx] or 0
end

local function actOf(f, layer, tx, ty)
  local tt = f.room:tileType(layer == 2 and 2 or 1, tx, ty)
  if not tt or tt >= 0x4000 then return nil, tt end
  return f.assets.actTile and f.assets.actTile[tt], tt
end

-- sub_080774A0: 0 floor, 1 a wall, $56 a soft wall
function M.wallAhead(p)
  local f = p.field
  local tx, ty = tileAt(p)
  local r = f.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return 0 end
  local c = coll(r, p.layer, tx, ty)
  if c > 0x16 or c < 0x0F then return 0 end
  if actOf(f, p.layer, tx, ty) ~= M.ACT_SOFT then return 1 end
  return 0x56
end

local function setType(f, layer, tx, ty, t)
  local r = f.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return end
  f:objects():setTileType(layer, tx, ty, t)
end

-- sub_0807B600 at tile (tx, ty)
function M.digWall(f, tx, ty)
  local r = f.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return false end
  local a, tt = actOf(f, 1, tx, ty)
  if a ~= M.ACT_SOFT then return false end
  local big = M.BIG[tt]
  if big then
    local x, y, b = tx, ty + big[1], big[2]
    setType(f, 1, x - 1, y - 1, b); setType(f, 2, x - 1, y - 1, b + 7)
    setType(f, 1, x, y - 1, b + 1); setType(f, 2, x, y - 1, b + 8)
    setType(f, 1, x + 1, y - 1, b + 2); setType(f, 2, x + 1, y - 1, b + 9)
    setType(f, 1, x - 1, y, b + 3); setType(f, 1, x, y, b + 4); setType(f, 1, x + 1, y, b + 6)
    return true
  end
  local top = r:tileType(2, tx, ty)
  if (top or 0) ~= 0 then
    setType(f, 1, tx, ty, M.TT.WALL_754)
    if ty > 0 and coll(r, 1, tx, ty - 1) == 3 then setType(f, 1, tx, ty - 1, M.TT.WALL_756) end
    if coll(r, 1, tx, ty + 1) == 3 then setType(f, 1, tx, ty, M.TT.WALL_756) end
  else
    setType(f, 1, tx, ty, M.TT.WALL_756)
  end
  if ty > 0 and actOf(f, 2, tx, ty - 1) == M.ACT_SOFT then
    setType(f, 2, tx, ty - 1, 0)
    if r:tileType(1, tx, ty - 1) == M.TT.WALL_754 then setType(f, 1, tx, ty - 1, M.TT.WALL_756) end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- frame flags
-- ---------------------------------------------------------------------------
local function setAnim(p, m, kind)
  p:setAnim(M.ANIM[kind], true)
  m.kind, m.fresh, m.ft, m.cur = kind, true, 0, 0
  m.key = p.anim.key
end

-- one animation step: returns (flags of a keyframe just shown, current flags)
local function step(p, m)
  local a = p.anim
  if a.keys then
    if m.fresh then m.fresh = false; m.key = a.key; m.cur = a.flags or 0; return m.cur, m.cur end
    a:update(1)
    if a.key ~= m.key then m.key = a.key; m.cur = a.flags or 0; return m.cur, m.cur end
    return 0, m.cur
  end
  m.fresh = false
  m.ft = m.ft + 1
  local e = (FALLBACK[m.kind] or {})[m.ft]
  if e then m.cur = e; return e, e end
  return 0, m.cur
end

local function finish(p)
  p.mitts, p.moleMittsState = nil, nil
  if p.state == "ext" and p.extUpdate == M.update then p.state, p.extUpdate = "normal", nil end
  p.animId = -1
end

local function forward(p, s)
  local st = p.animationState
  local dx = (st == 2 and 1 or st == 6 and -1 or 0)
  local dy = (st == 4 and 1 or st == 0 and -1 or 0)
  if dx ~= 0 or dy ~= 0 then p:moveBy(dx * s, dy * s) end
end

-- ---------------------------------------------------------------------------
-- OBJECT_1F: the clod
-- ---------------------------------------------------------------------------
local function clodLand(f, e)
  local r = f.room
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  local c = (tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th) and coll(r, e.layer, tx, ty) or 0
  if c == 0x21 then f:addFx(e.x, e.y, SPECIAL_FX, M.FX.FALL)
  elseif c == 0x25 then f:addFx(e.x, e.y, SPECIAL_FX, M.FX.LAVA)
  elseif c == 0x24 or c == 0x30 then f:addFx(e.x, e.y, SPECIAL_FX, M.FX.WATER)
  elseif e.type2 ~= 0 then
    if e.type2 == SPECIAL_FX then
      local Drops = require("src.zelda.tmc.Drops")
      local t = Drops.fxVariant(f, e.objType)
      f:addFx(e.x, e.y, SPECIAL_FX, t)
      Drops.fxDrop(f, { x = e.x, y = e.y }, t, f:objects())
    else
      f:addFx(e.x, e.y, e.type2, e.objType)
    end
  end
  e.deleted = true
end
M.clodLand = clodLand

function M.clodUpdate(f, e)
  if e.deleted then return end
  if e.delay > 0 then
    e.delay = e.delay - 1
    if not f.player.mitts then clodLand(f, e) end
    return
  end
  e.x, e.y = e.x + e.vx, e.y + e.vy
  e.zv = e.zv - 40 / 256
  e.z = e.z + e.zv
  if e.z <= 0 then e.z = 0; clodLand(f, e) end
end

function M.spawnClod(f, p, obj, objType, n)
  local st = band(p.animationState or 4, 6)
  local o = M.CLOD_OFF[st]
  local c = M.CLOD[n] or M.CLOD[0]
  local bx = (st == 2 and -1 or st == 6 and 1 or 0) -- direction: animationState << 2 ^ $10 (behind Link)
  local by = (st == 4 and -1 or st == 0 and 1 or 0)
  local e = { kind = 6, id = OBJECT_1F, form = 0, x = p.x + o[1], y = p.y + o[2], z = 0, zv = 2.75,
              vx = bx, vy = by, delay = c.delay, type2 = obj, objType = objType, layer = p.layer,
              animationState = st, field80 = 0, field82 = 0, interactType = 0, clod = true }
  local O = f:objects()
  local def = O and O.def and O:def(OBJECT_1F, 0)
  if def then O:dress(e, def, c.anim) end
  e.extUpdate = function(_, me) M.clodUpdate(f, me) end
  f.entities[#f.entities + 1] = e
  if f._dungeon and f._dungeon.track then f._dungeon:track(e) end
  return e
end

-- ---------------------------------------------------------------------------
-- the item
-- ---------------------------------------------------------------------------
function M.use(p, item, button, input)
  if item ~= M.ITEM or p.minish then return nil end
  if (p.z or 0) > 0 or p.jumping then return nil end -- jump_status
  local m = { button = button, timer = 0, sub = 0xFF }
  p.mitts, p.moleMittsState = m, 1
  p.state, p.extUpdate = "ext", M.update
  p.moving = false
  local w = M.wallAhead(p)
  if w ~= 0 then
    setAnim(p, m, "dig")
    m.st = 2
    if w == 0x56 then
      if band(p.animationState, 2) ~= 0 then p.y = math.floor(p.y / 16) * 16 + 6
      else p.x = math.floor(p.x / 16) * 16 + 8 end
    end
  else
    setAnim(p, m, "floor")
    m.st = 1
  end
  return true
end

function M.update(p, input)
  local f = p.field
  local m = p.mitts
  if not m then finish(p) return end
  if m.st == 1 then
    local edge = step(p, m)
    if band(edge, 0x80) ~= 0 then finish(p) return end
    if band(edge, 0x10) ~= 0 then
      local tx, ty = tileAt(p)
      local O = f:objects()
      local e, cx, cy = O:tileInteraction(0x0D, tx * 16 + 8, ty * 16 + 8, p.layer)
      if not e then
        setAnim(p, m, "miss")
        m.st = 3
        f:sound(M.SFX.AIR)
      else
        if e.obj == SPECIAL_FX and e.objType == M.FX.GRASS_CUT then
          local Drops = require("src.zelda.tmc.Drops")
          local t = Drops.fxVariant(f, e.objType)
          f:addFx(cx, cy, SPECIAL_FX, t)
          Drops.fxDrop(f, { x = cx, y = cy }, t, O)
        end
        m.sub = rshift(e.unk or 0xFF00, 8)
        if m.sub ~= 0xFF then
          M.spawnClod(f, p, e.obj, e.objType, m.sub)
        elseif e.obj == SPECIAL_FX and e.objType == M.FX.GRASS_CUT then
          m.sub = 0
        end
        f:sound(M.SFX.DIG)
        m.dug = (m.dug or 0) + 1
      end
    end
  elseif m.st == 2 then
    local bf = (f:inventory(M.ITEM_DIG_BUTTERFLY) or 0) > 0
    local edge, cur = step(p, m)
    local idx = band(cur, 7)
    local sp = M.SPEED[idx] or 0
    if bf and idx ~= 3 then
      local e2, c2 = step(p, m) -- sub_08077E3C(this, 2)
      edge, cur = bit.bor(edge, e2), c2
      sp = sp * 2
    end
    if band(edge, 8) ~= 0 and input and input.pressed(m.button or "b") then m.timer = 1 end
    if sp ~= 0 then forward(p, sp / 256) end
    if band(edge, 0x10) ~= 0 then
      if m.timer ~= 0 and M.wallAhead(p) ~= 0 then
        m.timer = 0
        if not p.anim.keys then m.ft = 0 end -- the fallback timeline digs on
        return
      end
      finish(p)
      return
    elseif band(edge, 0x60) ~= 0 then
      local tx, ty = tileAt(p)
      if M.digWall(f, tx, ty) then
        f:sound(M.SFX.DIG)
        m.dug = (m.dug or 0) + 1
      else
        setAnim(p, m, "clang")
        f:addFx(p.x, p.y, SPECIAL_FX, M.FX.STARS)
        f:addFx(p.x, p.y, SPECIAL_FX, M.FX.STARS)
        m.st, m.push = 3, true
        f:sound(M.SFX.KNOCKBACK)
        m.clanged = true
      end
    end
  elseif m.st == 3 then
    if band(m.cur or 0, 1) ~= 0 and m.push then forward(p, -1) end
    local edge = step(p, m)
    if band(edge, 0x80) ~= 0 then finish(p) return end
  end
end

return M
