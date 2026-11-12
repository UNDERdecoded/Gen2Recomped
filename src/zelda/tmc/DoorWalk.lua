-- Round 14: walking into and out of doors as the cartridge does.
--
-- CARTRIDGE BEHAVIOUR:
-- * ACT_TILE_40 (act $28: house doors, stairs; beanstalkSubtask.c, the
--   player's tile-in-front handler): not Minish, pushing in the facing
--   direction, the tile solid (COLLISION_DATA_15) and Link blocked on that
--   side (sub_08079778), and an area transition at Link + gUnk_080B4478
--   [facing] ((0,-15) (12,-3) (0,12) (-12,-3)): Link is lined up with the
--   transition (x = startX, or y = startY + 6 facing east / west) and
--   sub_08078AC0(4, 0, 1) queues PLAYER_ROOM_EXIT: 5 frames of walking at
--   $140 (1.25 px) with collision off and LinearMoveUpdate, so he steps
--   into the doorway, where the transition rectangle starts the warp.
-- * ACT_TILE_41 (act $29: the threshold of a doorway) is a walkable tile;
--   on arrival (PlayerRoomTransition, sub_080724DC / sub_0807258C) a Link
--   standing on one walks on in his facing direction while the tile in
--   front is still $29 and he is not blocked, then takes control.
local DW = {}

local ENTER = { [0] = { 0, -15 }, [2] = { 12, -3 }, [4] = { 0, 12 }, [6] = { -12, -3 } } -- gUnk_080B4478
local FRONT = { [0] = { 0, -15 }, [2] = { 12, -3 }, [4] = { 0, 9 }, [6] = { -12, -3 } }  -- gUnk_080B4468
local STEP = { [0] = { 0, -1 }, [2] = { 1, 0 }, [4] = { 0, 1 }, [6] = { -1, 0 } }
DW.SPEED = 1.25 -- $140

local function actAt(f, x, y, layer)
  local r = f.room
  local tt = r:tileType(layer == 2 and 2 or 1, math.floor(x / 16), math.floor(y / 16))
  if not tt or tt >= 0x4000 then return nil end
  return f.assets.actTile[tt]
end
DW.actAt = actAt

-- the area transition the cartridge would take from a $28 door ahead
function DW.enterTransition(f, p)
  local o = ENTER[p.animationState] or ENTER[0]
  return f.room:areaExitAt(math.floor(p.x) + o[1], math.floor(p.y) + o[2]), o
end

-- PLAYER_ROOM_EXIT: line up, then 5 frames forward through anything
function DW.startEnter(f, p, tr)
  local s = p.animationState
  if s == 2 or s == 6 then p.y = tr.startY + 6 else p.x = tr.startX end
  local d = STEP[s] or STEP[0]
  p.state = "ext"
  p.doorWalk = 5
  p:setAnim(p:animFor("walk"))
  p.extUpdate = function(pl)
    pl.x, pl.y = pl.x + d[1] * DW.SPEED, pl.y + d[2] * DW.SPEED
    pl.moving = true
    pl.anim:update(1)
    pl.doorWalk = pl.doorWalk - 1
    if pl.doorWalk <= 0 then pl.state, pl.extUpdate, pl.doorWalk = "normal", nil, nil end
  end
end

-- after a room change: a Link left on a $29 threshold walks out of it
function DW.arrive(f)
  local p = f.player
  if not p then return false end
  if actAt(f, p.x, p.y, p.layer) ~= 0x29 then return false end
  local s = p.animationState
  local d = STEP[s] or STEP[0]
  local o = FRONT[s] or FRONT[0]
  p.state = "ext"
  p:setAnim(p:animFor("walk"))
  p.doorWalk = 120 -- (a guard; the walk ends on its own)
  p.extUpdate = function(pl)
    local done = actAt(f, pl.x + o[1], pl.y + o[2], pl.layer) ~= 0x29
    if not done then
      local x0, y0 = pl.x, pl.y
      pl:moveBy(d[1] * DW.SPEED, d[2] * DW.SPEED)
      done = (pl.x == x0 and pl.y == y0) -- sub_080797C4: blocked ahead
      pl.moving = true
      pl.anim:update(1)
    end
    pl.doorWalk = pl.doorWalk - 1
    if done or pl.doorWalk <= 0 then pl.state, pl.extUpdate, pl.doorWalk, pl.animId = "normal", nil, nil, -1 end
  end
  return true
end

return DW
