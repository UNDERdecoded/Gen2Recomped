-- Round 24: the Cave of Flames' rail pieces (ported from the decomp).
--
-- MINECART_DOOR $6C (src/object/minecartDoor.c):
--   Init: the door art of LockedDoor (sub_080837B0: gUnk_0811F690[area -
--     $40], $52 in the Cave of Flames), frame = type (0 N, 1 E, 2 S, 3 W);
--     type & 4: a flag door (gone once its flag is set).  Shut: drawn,
--     SPECIAL_TILE_34 on its tile (Dungeon:block).
--   Action1 (shut): sub_08096CEC -- Link in a mine cart moving along the
--     door's axis ((type << 1) ^ animationState) & 2 == 0, within 8 px
--     across and $30 along -> Action2: the tile comes back, it slides into
--     the wall (direction type << 3, speed $300) for 7 frames, SFX_10B,
--     then hidden (Action3, timer 8).
--   Action3 (open): in a cart going the door's way (type * 2 ==
--     animationState) it stays until Link is through (sub_08083734); in a
--     cart going the other way it shuts after 8 frames; on foot it stays
--     open while Link is within 100 px of its inside (sub_08096D84), else
--     it shuts: sub_080836DC (SPECIAL_TILE_34, out of the wall at
--     gUnk_0811F688[type], 21 px, timer 7) -> Action4 slides back,
--     SFX_10B -> Action1.
-- RAILTRACK $13 (src/object/railtrack.c): a three-tile turning rail.
--   animationState = type2 & 2 (0 north-south, 2 east-west); type2 & 1
--   turns it the other way (unk_7c -1).  Its three tiles (centre and +-1
--   along it) become SPECIAL_TILE_24 (N-S, act 242) or 25 (E-W, act 243).
--   Type 3 follows its flag: flag set at Init -> already turned (state + 2,
--   Action3); Action3 turns (Action2: 8 frames per quarter, SFX_151, the
--   old tiles back during the turn) whenever the flag differs from the one
--   it last saw.  Types 0-2 wait for the flag in Action1 (type 1 clears it,
--   type 2 turns back when it clears).
-- HITTABLE_LEVER $2F (src/object/hittableLever.c): hitType $8F, hitbox
--   (0, 1, 4, 3); each new contact (wasHit until its iframes run out,
--   iframes -$18) flips type and toggles its flag, SFX_117; tile type $378
--   when type 1 else $377 (sub_0807B7D8).  Init: type 0 reads the flag,
--   type 1 sets it.
-- RAIL_INTERSECTION_MANAGER $1F (src/manager/railIntersectionManager.c):
--   the rail tile next to a turning rail: tile type gUnk_08108C9C[type * 2
--   + flag] (856, 857, 854, 858, 858, 855) at its tile (x >> 4, y >> 4),
--   layer paramB >> 16; follows its flag.
-- SIMPLIFIED: the levers take the sword (Field.swordBoxNow) and the Cane of
--   Pacci's projectile; the door's FX_DASH puffs are not drawn.
local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local R = {}
R.OBJ_MINECART_DOOR, R.OBJ_RAILTRACK, R.OBJ_HITTABLE_LEVER, R.MGR_RAIL_INTERSECTION = 0x6C, 0x13, 0x2F, 0x1F
local SFX_10B, SFX_151, SFX_117 = 0x10B, 0x151, 0x117
local SP24, SP25 = 0x4018, 0x4019
local VEC = { [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
local OUT21 = { [0] = { 0, -21 }, { 21, 0 }, { 0, 21 }, { -21, 0 } } -- gUnk_0811F688
-- special tiles' act tiles (gMapSpecialTileToActTile) the carts read
R.SPECIAL_ACT = { [0x4018] = 242, [0x4019] = 243, [0x4020] = 240 }

local function tileOf(x, y) return math.floor(x / 16), math.floor(y / 16) end
local function anim(d, e, a)
  e.objAnim, e.animIndex = a, a
  if e.anim and e.sprite then e.anim:set(d.field.assets:sprite(e.sprite), a, true) end
end

-- ---------------------------------------------------------------------------
-- MINECART_DOOR
-- ---------------------------------------------------------------------------
local function inCartNear(f, e)
  local p = f.player
  if e.flagDoor and f._dungeon:check(e.flag) then return true end
  if not p.inCart then return false end
  if band(bxor(e.type * 2, p.animationState or 0), 2) ~= 0 then return false end -- ((type << 1) ^ animationState) & 2
  local along, across
  if band(e.type, 1) ~= 0 then across, along = p.y - e.y, p.x - e.x else across, along = p.x - e.x, p.y - e.y end
  return across + 8 >= 0 and across + 8 < 0x11 and along + 0x30 >= 0 and along + 0x30 < 0x61
end
-- sub_08083734: Link is through the doorway
local function passed(e, p)
  if e.type == 0 then return e.y0 + 0xD - p.y < 0 end
  if e.type == 1 then return p.x - (e.x0 - 0xB) < 0 end
  if e.type == 2 then return p.y - (e.y0 - 8) < 0 end
  return e.x0 + 0xA - p.x < 0
end
-- sub_08096D84: on foot, near the door's inside
local function nearInside(e, p)
  local v
  if e.type == 0 then v = (e.y0 + 10) - p.y
  elseif e.type == 1 then v = p.x - (e.x0 - 10)
  elseif e.type == 2 then v = p.y - (e.y0 - 10)
  else v = (e.x0 + 10) - p.x end
  return v >= 0 and v < 0x65
end
local function doorUpdate(d, e)
  local f = d.field
  local p = f.player
  if e.action == 1 then
    if inCartNear(f, e) then
      e.action, e.timer = 2, 7
      d:block(e.tx, e.ty, e.layer, false)
      f:sound(SFX_10B)
    end
  elseif e.action == 2 then
    local v = VEC[e.type]
    e.x, e.y = e.x + v[1] * 3, e.y + v[2] * 3
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.timer = 3, 8
      e.hidden = true
      e.x, e.y = e.x0, e.y0
      if e.flagDoor then e.deleted = true end
    end
  elseif e.action == 3 then
    if e.flagDoor and d:check(e.flag) then return end
    local keep
    if p.inCart then
      if e.type * 2 == (p.animationState or 0) then
        if not passed(e, p) then return end
        keep = false
      else
        e.timer = e.timer - 1
        keep = e.timer > 0
      end
    else
      keep = nearInside(e, p)
    end
    if not keep then
      -- sub_080836DC
      e.action = 4
      d:block(e.tx, e.ty, e.layer, true)
      e.timer = 7
      e.hidden = false
      e.x, e.y = e.x0 + OUT21[e.type][1], e.y0 + OUT21[e.type][2]
    end
  elseif e.action == 4 then
    local v = VEC[e.type]
    e.x, e.y = e.x - v[1] * 3, e.y - v[2] * 3
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action = 1
      e.x, e.y = e.x0, e.y0
      f:sound(SFX_10B)
    end
  end
end

function R.spawnDoor(d, e)
  local f = d.field
  e.type = band(e.form or 0, 3)
  e.flagDoor = band(e.form or 0, 4) ~= 0
  e.x0, e.y0 = e.x, e.y
  e.tx, e.ty = tileOf(e.x, e.y)
  d:dress(e, 477, 10, require("src.zelda.tmc.Dungeon").DOOR_GFX[f.room.area] or 0x0A, 0)
  e.staticFrame = e.type
  e.spritePriority = 5
  e.mcDoor = true
  if inCartNear(f, e) then
    if e.flagDoor then return nil end
    e.action, e.timer, e.hidden = 3, 8, true
  else
    e.action = 1
    d:block(e.tx, e.ty, e.layer, true)
  end
  e.extUpdate = function(dd, me) doorUpdate(dd, me) end
  d:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- RAILTRACK
-- ---------------------------------------------------------------------------
local function along(e) -- the tile step along the rail: N-S (0) or E-W (2)
  if band(e.animationState, 2) == 0 then return 0, 1 end
  return 1, 0
end
local function placeTiles(d, e) -- sub_08085394
  local r = d.field.room
  local sx, sy = along(e)
  local sp = (band(e.animationState, 2) == 0) and SP24 or SP25
  e.saved = {}
  for k = -1, 1 do
    local tx, ty = e.tx + sx * k, e.ty + sy * k
    local name = e.layer == 2 and "top" or "bottom"
    e.saved[k] = { tx, ty, r.maps[name][ty * r.tw + tx] }
    r:setTile(e.layer, tx, ty, sp)
  end
end
local function restoreTiles(d, e) -- sub_0808543C
  local r = d.field.room
  for k = -1, 1 do
    local s = e.saved and e.saved[k]
    if s and s[3] then
      r:setTile(e.layer, s[1], s[2], s[3])
      if r.keepGfx then r.keepGfx[(e.layer == 2 and "top" or "bottom") .. (s[2] * r.tw + s[1])] = nil end
    end
  end
  e.saved = nil
end
local function intact(d, e) -- sub_080854A8 == 0: its three special tiles are still there
  local r = d.field.room
  local sx, sy = along(e)
  local sp = (band(e.animationState, 2) == 0) and SP24 or SP25
  local name = e.layer == 2 and "top" or "bottom"
  for k = -1, 1 do
    if r.maps[name][(e.ty + sy * k) * r.tw + e.tx + sx * k] ~= sp then return false end
  end
  return true
end
local function turnStep(d, e)
  e.animationState = band(e.animationState + e.turn, 3)
  anim(d, e, e.animationState)
end
local function trackUpdate(d, e)
  local f = d.field
  if e.action == 1 then
    if d:check(e.flag) then
      e.action, e.subtimer = 2, 8
      if e.type == 1 then d:set(e.flag, false) end
      turnStep(d, e)
      restoreTiles(d, e)
      f:sound(SFX_151)
    end
  elseif e.action == 2 then
    e.subtimer = e.subtimer - 1
    if e.subtimer == 0 then
      e.action = 3
      e.subtimer = e.timer0 or 0
      e.flagValue = d:check(e.flag)
      turnStep(d, e)
      placeTiles(d, e)
      f:sound(SFX_151)
    end
  elseif e.action == 3 then
    if intact(d, e) then
      if e.type == 2 then
        if not d:check(e.flag) then e.action = 1 return end
      elseif e.type == 3 then
        e.subtimer = (d:check(e.flag) == e.flagValue) and 255 or 1
      end
      e.subtimer = band((e.subtimer or 0) - 1, 0xFF)
      if e.subtimer == 0 then
        e.action, e.subtimer = 2, 8
        turnStep(d, e)
        restoreTiles(d, e)
        f:sound(SFX_151)
      end
    end
  end
end

function R.spawnTrack(d, e)
  local f = d.field
  e.type = e.form or 0
  e.tx, e.ty = tileOf(e.x, e.y)
  local def = f:objects():def(R.OBJ_RAILTRACK, e.type)
  if def then f:objects():dress(e, def, 0) end
  e.forceAnim = nil
  e.spritePriority = 7
  e.turn = band(e.type2 or 0, 1) ~= 0 and -1 or 1
  e.animationState = band(e.type2 or 0, 2)
  e.action = 1
  if e.type == 3 then
    e.flagValue = d:check(e.flag)
    if e.flagValue then e.animationState = band(e.animationState + 2, 3); e.action = 3 end
  end
  anim(d, e, e.animationState)
  placeTiles(d, e)
  e.railtrack = true
  e.extUpdate = function(dd, me) trackUpdate(dd, me) end
  d:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- HITTABLE_LEVER
-- ---------------------------------------------------------------------------
local function leverTile(d, e)
  d.field:objects():setTileType(e.layer, e.tx, e.ty, e.type ~= 0 and 0x378 or 0x377)
end
function R.hitLever(d, e)
  if e.wasHit then return false end
  e.wasHit = true
  e.type = bxor(e.type, 1)
  e.iframes = 0x18
  leverTile(d, e)
  d:set(e.flag, not d:check(e.flag))
  d.field:sound(SFX_117)
  return true
end
local function leverUpdate(d, e)
  local f = d.field
  if (e.iframes or 0) > 0 then e.iframes = e.iframes - 1 end
  if e.iframes == 0 then e.wasHit = false end
  local b = f.swordBoxNow
  -- HittableLever_Hitbox { 0, 1, 4, 3 }
  if b and b.t == f.frame and math.abs(b.x - e.x) < b.w + 4 and math.abs(b.y - (e.y + 1)) < b.h + 3 then
    R.hitLever(d, e)
  end
end

function R.spawnLever(d, e)
  e.type = e.form or 0
  e.tx, e.ty = tileOf(e.x, e.y)
  if e.type == 0 then
    e.type = d:check(e.flag) and 1 or 0
  else
    d:set(e.flag, true)
  end
  e.iframes = 0
  e.hidden = true -- the lever is its tile ($377 / $378)
  e.hittableLever = true
  leverTile(d, e)
  e.extUpdate = function(dd, me) leverUpdate(dd, me) end
  d:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- RAIL_INTERSECTION_MANAGER
-- ---------------------------------------------------------------------------
local INTERSECTION = { [0] = 856, 857, 854, 858, 858, 855 } -- gUnk_08108C9C
function R.spawnIntersection(d, m)
  local f = d.field
  m.layer = band(m.b32, 0xFF)
  m.tx, m.ty = band(rshift(m.x, 4), 0x3F), band(rshift(m.y, 4), 0x3F)
  m.flagSpec = m.c1
  m.type2 = d:check(m.flagSpec) and 1 or 0
  local function set()
    f:objects():setTileType(m.layer == 2 and 2 or 1, m.tx, m.ty, INTERSECTION[(m.type or 0) * 2 + m.type2])
  end
  set()
  local e = { kind = 9, id = R.MGR_RAIL_INTERSECTION, x = m.x, y = m.y, hidden = true, dungeon = true, manager = true }
  e.extUpdate = function(dd)
    local want = dd:check(m.flagSpec) and 1 or 0
    if want ~= m.type2 then m.type2 = want; set() end
  end
  d:track(e)
  return true
end

-- the object chain (Dungeon:spawnObject)
function R.spawn(d, e)
  if e.id == R.OBJ_MINECART_DOOR then return R.spawnDoor(d, e) end
  if e.id == R.OBJ_RAILTRACK then return R.spawnTrack(d, e) end
  if e.id == R.OBJ_HITTABLE_LEVER then return R.spawnLever(d, e) end
  return nil
end

return R
