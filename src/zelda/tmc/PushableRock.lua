-- Round 22: PUSHABLE_ROCK ($2E), src/object/pushableRock.c, and the push that
-- starts it (beanstalkSubtask.c UpdatePlayerCollision, case SPECIAL_TILE_27;
-- player.c PlayerPush with type 1).  The round boulders of Mt. Crenel's
-- summit and its caves; MOVEABLE_OBJECT_MANAGER ($20) places them at their
-- solved spot once their flag is set (Dungeon.lua).
--
-- CARTRIDGE BEHAVIOUR:
--   * Init / sub_0808A644: its tile (COORD_TO_TILE) remembered; over a hole
--     (ACT_TILE_25 or ACT_TILE_240) it puts SPECIAL_TILE_21 there and sits
--     in it (action 3): first time SetFlag(its flag field $86) +
--     SFX_TASK_COMPLETE + animation 5 (dropping in), else animation 6;
--     elsewhere its tile becomes SPECIAL_TILE_27 (COLLISION_DATA_15, solid).
--   * Link pushing (PL_STATE_PUSH, on a push-animation frame with bit 0,
--     moving the way he faces) a SPECIAL_TILE_27 in front with the tile
--     beyond free (sub_0801A2B0: not act $26/$27/$29/$74, collision not $28
--     and not solid for type $B): that tile becomes SPECIAL_TILE_28 + facing
--     / 2 and Link goes PLAYER_PUSH type 1: sPushFrames (5 still, 1 at
--     2 x kPushSpeed, 5, 1, 2, 1, 2, 1, 3, 1, then 8 + 8 + 8 frames at 3/4
--     and 8 at 1/2 of kPushSpeed $80) = 16 px.
--   * Action1 sees SPECIAL_TILE_28-31 under it: animationState = (type -
--     $1C) * 2, direction * 8, flipX for east, the remembered tile put back,
--     animation state / 2 + 1, SFX_10F; Action2 moves at
--     PushableRock_Speeds[frame & $F] (0, $100, $60, $40) pushing Link out
--     (sub_0800445C) until the animation is done, then Init again.
local bit = require("bit")
local band = bit.band

local R = {}

local OBJ = 0x2E
local SP27, SP21 = 0x401B, 0x4015
local ACT_HOLE, ACT_240 = 0x19, 0xF0
local SFX_10F, SFX_TASK_COMPLETE = 0x10F, 0xCD
local SPEEDS = { [0] = 0, 0x100, 0x60, 0x40 }
local DV = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }
local K = 0x80 -- kPushSpeed
local PUSH_FRAMES = { { 5, 0 }, { 1, K * 2 }, { 5, 0 }, { 1, K * 2 }, { 2, 0 }, { 1, K * 2 }, { 2, 0 }, { 1, K * 2 },
                      { 3, 0 }, { 1, K * 2 }, { 8, K * 3 / 4 }, { 8, K * 3 / 4 }, { 8, K * 3 / 4 }, { 8, K / 2 } }
R.PUSH_FRAMES, R.SPEEDS = PUSH_FRAMES, SPEEDS
R.SFX_TASK_COMPLETE = SFX_TASK_COMPLETE

local function setAnim(d, e, a)
  e.objAnim, e.animIndex = a, a
  if e.sprite then e.anim:set(d.field.assets:sprite(e.sprite), a, true) end
end

local function mapName(layer) return layer == 2 and "top" or "bottom" end

local function actAt(f, layer, tx, ty)
  local tt = f.room:tileType(layer or 1, tx, ty)
  if not tt or tt >= 0x4000 then return tt end
  return f.assets.actTile and f.assets.actTile[tt]
end

-- sub_0808A644
local function settle(d, e)
  local f = d.field
  local r = f.room
  e.tx, e.ty = math.floor(e.x / 16), math.floor(e.y / 16)
  e.tileIndex = r.maps[mapName(e.layer)][e.ty * r.tw + e.tx]
  local act = actAt(f, e.layer, e.tx, e.ty)
  if act == ACT_HOLE or act == ACT_240 then
    r:setTile(e.layer, e.tx, e.ty, SP21)
    e.action = 3
    e.inHole = true
    if not d:check(e.pushedFlag) then
      d:set(e.pushedFlag)
      f:sound(SFX_TASK_COMPLETE)
      setAnim(d, e, 5)
    else
      setAnim(d, e, 6)
    end
  else
    r:setTile(e.layer, e.tx, e.ty, SP27)
    e.action = 1
  end
end

local function update(d, e)
  local f = d.field
  local r = f.room
  if e.action == 0 then
    e.spritePriority = 4
    settle(d, e)
  elseif e.action == 1 then
    local tt = r:tileType(e.layer, e.tx, e.ty)
    if tt and tt >= 0x401C and tt <= 0x401F then
      local s = (tt - 0x401C) * 2
      e.animationState = s
      e.direction = s * 4
      e.flipX = s == 2
      if e.tileIndex then r:setTile(e.layer, e.tx, e.ty, e.tileIndex) end
      e.action = 2
      setAnim(d, e, s / 2 + 1)
      f:sound(SFX_10F)
    elseif (e.animIndex or 0) ~= 0 then
      setAnim(d, e, 0)
    end
  elseif e.action == 2 then
    require("src.zelda.tmc.Hitboxes").pushOut(f, e, { x = 0, y = 0, w = 6, h = 6 })
    local v = DV[e.animationState] or DV[4]
    local sp = SPEEDS[band(e.anim.flags or 0, 0xF)] or 0
    e.x, e.y = e.x + v[1] * sp / 256, e.y + v[2] * sp / 256
    e.anim:update(1)
    if e.anim.done then
      e.x, e.y = math.floor(e.x / 16) * 16 + 8, math.floor(e.y / 16) * 16 + 8
      e.action = 0
    end
  elseif e.action == 3 then
    if not e.anim.done then e.anim:update(1) else e.spritePriority = 7 end
  end
end
R.update = update

function R.spawn(d, e)
  if e.id ~= OBJ then return nil end
  local f = d.field
  local def = f:objects():def(OBJ, e.form or 0)
  if def then f:objects():dress(e, def, 0) end
  e.forceAnim = nil
  e.pushedFlag = e.flag -- field $86 (MoveableObjectManager: its flags)
  e.rock = true
  e.action = 0
  setAnim(d, e, 0)
  update(d, e)
  e.extUpdate = function(dd, me) update(dd, me) end
  d:track(e)
  return e
end

-- sub_0801A2B0(.., collisionType $B): the tile beyond takes the rock --
-- act $52 / $26 / $27 / $29 / $74 never; collision $28 never; else
-- IsTileCollision type $B: free for 0, $20, $22, $2A and $50-$5F (holes
-- are $20), solid for 1-$1F, the rest of $21-$6F and above $6F
local FREE_B = { [0] = true, [0x20] = true, [0x22] = true, [0x2A] = true }
function R.collisionFreeB(v)
  if FREE_B[v] then return true end
  return v >= 0x50 and v <= 0x5F
end
function R.beyondFree(f, layer, tx, ty)
  local r = f.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return false end
  local act = actAt(f, layer, tx, ty)
  if act == 0x52 or act == 0x26 or act == 0x27 or act == 0x29 or act == 0x74 then return false end
  local v = r.coll[(layer == 2) and 2 or 1][ty * r.tw + tx] or 0xFF
  if v == 0x28 then return false end
  return R.collisionFreeB(v)
end

-- PlayerPush type 1 (Link's side of the push)
local function pushUpdate(p, input)
  local ps = p.rockPush
  p.anim:update(1)
  ps.left = ps.left - 1
  if ps.left <= 0 then
    ps.i = ps.i + 1
    local fr = PUSH_FRAMES[ps.i]
    if not fr then
      p.rockPush = nil
      p.extUpdate = nil
      p.state = "normal"
      return
    end
    ps.left, ps.speed = fr[1], fr[2]
  end
  local v = DV[p.animationState] or DV[4]
  if ps.speed > 0 then p:moveBy(v[1] * ps.speed / 256, v[2] * ps.speed / 256) end
end

-- UpdatePlayerCollision's SPECIAL_TILE_27 case (PushAnim.update, on a push frame)
function R.tryPush(p)
  local f = p.field
  if p.minish or p.state ~= "normal" or not p.probe or not (f.room and f.room.tileType) then return false end
  local v = DV[p.animationState]
  if not v then return false end
  local fx, fy = p:probe()
  local tx, ty = math.floor(fx / 16), math.floor(fy / 16)
  local layer = p.layer or 1
  if f.room:tileType(layer, tx, ty) ~= SP27 then return false end
  if not R.beyondFree(f, layer, tx + v[1], ty + v[2]) then return false end
  f.room:setTile(layer, tx, ty, 0x401C + p.animationState / 2)
  p.state = "ext"
  p.x, p.y = math.floor(p.x), math.floor(p.y)
  p.rockPush = { i = 1, left = PUSH_FRAMES[1][1], speed = PUSH_FRAMES[1][2] }
  p.extUpdate = pushUpdate
  return true
end

return R
