-- Round 15: HOUSE_DOOR_EXT ($19, src/object/houseDoorExterior.c), the
-- doors of the houses out in the field (Minish Woods, Hyrule Field, Lake
-- Hylia, Royal Valley...).  Before this the doors were not drawn at all.
--
-- CARTRIDGE BEHAVIOUR:
-- * type2 0 is the manager.  Its timer (EntityData type2 >> 8) picks a room
--   property: a list of door records (ExtractR15.houseDoors, read from the
--   player's ROM).  Each frame, a record whose condition holds (0 / not 2:
--   always, 2: TATEKAKE_HOUSE) and whose 32x32 region is on screen
--   (CheckRegionOnScreen) gets a door: CreateObject(HOUSE_DOOR_EXT,
--   record.type, record.type2) at (x + 16, y + 32), the record's layer;
--   subAction = the condition.
-- * type2 1: deleted again once its region is off screen (then type 2).
-- * type2 2: frame 0 (closed; frame 1 when subAction is 1).  A closed door
--   is solid (sub_0800445C).  Link touching it, within 6 / 20 px
--   (GetAnimationStateInRectRadius), facing up, holding only UP, not
--   jumping, for 8 frames: frame 1 (open), sub_08078AC0(16, 0, 1) -- he
--   walks 16 frames into the doorway -- and SFX $111.
-- * type2 3 (and scripted doors): run a script.  NOT ported: those doors
--   are drawn closed and open like type 2.
local bit = require("bit")
local band = bit.band

local HD = {}

local function onScreen(f, rx, ry)
  local x = f.camX - rx + 240
  local y = f.camY - ry + 160
  return x >= 0 and x < 32 + 240 and y >= 0 and y < 32 + 160
end

local function condOk(f, c)
  if c ~= 2 then return true end
  return f:flag("global", 0x18) -- TATEKAKE_HOUSE
end

-- Dungeon:spawnObject hook; returns the entity (tracked) or nil
function HD.spawn(dg, e)
  local f = dg.field
  if e.type2 ~= 0 then
    -- a door placed by the room's entity data (type2 1-3): its own door
    HD.door(dg, nil, nil, { x = e.x - 16, y = e.y - 32, layer = e.layer, cond = 0, type2 = e.type2, type = e.form })
    return nil
  end
  local r15 = f.assets.manifest.r15
  local rooms = r15 and r15.houseDoors and r15.houseDoors[f.room.area * 256 + f.room.room]
  e.mgrList = rooms and rooms[e.timer0] or {}
  e.spawned = {}
  e.hidden = true
  e.extUpdate = HD.updateManager
  dg:track(e)
  return nil
end

function HD.updateManager(dg, m)
  local f = dg.field
  for i, rec in ipairs(m.mgrList) do
    if not m.spawned[i] and condOk(f, rec.cond) and onScreen(f, rec.x, rec.y) then
      m.spawned[i] = HD.door(dg, m, i, rec)
    end
  end
end

function HD.door(dg, m, i, rec)
  local f = dg.field
  local O = f:objects()
  local e = { kind = 6, id = 0x19, form = rec.type, type2 = rec.type2, x = rec.x + 16, y = rec.y + 32, z = 0,
              animationState = 0, field80 = 0, field82 = 0, interactType = 0, layer = rec.layer == 2 and 2 or 1,
              subAction = rec.cond, mgr = m, index = i, rec = rec, houseDoor = true, timer = 8 }
  local def = O:def(0x19, rec.type)
  if not def then return false end
  O:dress(e, def, 0)
  e.staticFrame = (rec.cond == 1) and 1 or 0
  e.extUpdate = HD.update
  require("src.zelda.tmc.Story27Town").scriptedDoor(dg, e, rec) -- round 27A: a door record with a script (ENT_SCRIPTED)
  dg:track(e)
  f.entities[#f.entities + 1] = e
  if e.staticFrame == 0 then HD.setSolid(dg, e, true) end
  return true
end

-- the closed door's hitbox (gUnk_081206AC: 0, -5, 10 x 4 half sizes) on
-- its tile
function HD.setSolid(dg, e, on)
  local tx, ty = math.floor(e.x / 16), math.floor((e.y - 5) / 16)
  dg:block(tx, ty, e.layer, on)
  e.blocking = on or nil
end

function HD.update(dg, e, input)
  local f = dg.field
  if e.type2 == 1 and e.mgr and not onScreen(f, e.rec.x, e.rec.y) then
    if e.blocking then HD.setSolid(dg, e, false) end
    e.deleted = true
    e.mgr.spawned[e.index] = nil
    return
  end
  if e.staticFrame ~= 0 then return end
  local p = f.player
  local near = math.abs(p.x - e.x) <= 6 and math.abs(p.y - e.y) <= 20
  local touching = math.abs(p.x - e.x) < 10 + 6 and p.y >= e.y - 5 and p.y <= e.y + 12
  local upOnly = input and input.down and input.down("up") and not (input.down("left") or input.down("right") or input.down("down"))
  if near and touching and p.animationState == 0 and upOnly and not p.jumping and (p.z or 0) == 0 then
    e.timer = e.timer - 1
  else
    e.timer = 8
  end
  if e.timer <= 0 then
    e.staticFrame = 1
    HD.setSolid(dg, e, false)
    f:sound(0x111)
    HD.walkIn(f, p, 16)
  end
end

-- sub_08078AC0(16, 0, 1): Link walks on for 16 frames, collision off
function HD.walkIn(f, p, frames)
  p.state = "ext"
  p:setAnim(p:animFor("walk"))
  p.doorWalk = frames
  p.extUpdate = function(pl)
    pl.y = pl.y - 1.25
    pl.moving = true
    pl.anim:update(1)
    pl.doorWalk = pl.doorWalk - 1
    if pl.doorWalk <= 0 then pl.state, pl.extUpdate, pl.doorWalk, pl.animId = "normal", nil, nil, -1 end
  end
end

return HD
