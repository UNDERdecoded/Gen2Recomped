-- Round 16: a lily pad carrying Link from room to room (lilypadLarge.c).
--
-- CARTRIDGE BEHAVIOUR:
--   * LilypadLarge_Init: type $FF is deleted once Link has the Flippers
--     (then type 0); a pad of another type whose local flag (type2) is not
--     set waits in Action5 -- it is never drawn -- and when a pad with the
--     same id is in the room (EntityHasDuplicateID: one that came along
--     from the room before) it sets that flag and deletes itself; a pad
--     whose Init finds a duplicate is deleted (the carried pad wins).
--   * sub_08085D60 (each frame of Action1 with Link on the pad): the pad's
--     direction gives a horizontal side (East / West) and a vertical side
--     (North / South); the collision data 24 px ahead on that side
--     (gUnk_08120638) is COLLISION_DATA_255 at the room's edge; there, an
--     area transition (DoApplicableTransition) is taken, else the room
--     next on the map (sub_0807BD14) starts a scroll and sub_08085E74 puts
--     the pad in Action3: ENT_PERSIST, speed $120 north / $138 south /
--     $100 east and west, its push velocities cleared, the camera on it,
--     Link's item put away.
--   * LilypadLarge_Action3: through the scroll the pad moves on at that
--     speed (LinearMoveUpdate) and carries Link with it; when the scroll
--     ends (reload_flags 0) it is an ordinary pad (Action1) again.
-- The port's scroll (Seamless.lua) switches rooms at once; the pad then
-- moves on for the cartridge scroll's frames (Scroll2Sub2: $3C sideways,
-- $28 up / down) with Link held, as he is on the cartridge.
local bit = require("bit")
local band = bit.band

local L = {}
L.ITEM_FLIPPERS = 0x46
L.SPEED = { [0] = 0x120, [1] = 0x100, [2] = 0x138, [3] = 0x100 } -- sub_08085E74, per scroll direction
L.FRAMES = { [0] = 0x28, [1] = 0x3C, [2] = 0x28, [3] = 0x3C }   -- Scroll2Sub2
local AHEAD = 24                                                 -- gUnk_08120638

-- LilypadLarge_Init's type rules; returns false when the pad is not made
function L.init(d, e)
  local f = d.field
  if e.form == 0xFF then
    if (f:inventory(L.ITEM_FLIPPERS) or 0) > 0 then return false end
    e.form = 0
  end
  if e.form ~= 0 and e.form ~= 0xFF and not f:flag("local", e.type2) then
    e.lilyWait = true   -- Action5: not drawn, waits for a duplicate
    e.hidden = true
  end
  return true
end

-- COLLISION_DATA_255: outside the room's map (and any $FF cell)
local function edge(r, x, y, layer)
  x, y = math.floor(x), math.floor(y)
  if x < 0 or y < 0 or x >= r.width or y >= r.height then return true end
  local c = r.coll[layer == 2 and 2 or 1]
  return c and c[bit.rshift(y, 4) * r.tw + bit.rshift(x, 4)] == 0xFF
end

-- sub_08085D60: called from Dungeon:updateLily while Link rides `e`;
-- true when the pad left the room
function L.check(d, e, p)
  local f = d.field
  if f.transition or p.state == "dead" or (p.z or 0) ~= 0 then return false end
  if e.vx == 0 and e.vy == 0 then return false end
  local r = f.room
  local h = (e.vx > 0 and 1) or (e.vx < 0 and 3) or nil
  local v = (e.vy < 0 and 0) or (e.vy > 0 and 2) or nil
  local tries = {}
  if h then tries[#tries + 1] = { h, h == 1 and AHEAD or -AHEAD, 0 } end
  if v then tries[#tries + 1] = { v, 0, v == 2 and AHEAD or -AHEAD } end
  for _, t in ipairs(tries) do
    local dir, ox, oy = t[1], t[2], t[3]
    if edge(r, e.x + ox, e.y + oy, e.layer) then
      -- DoApplicableTransition (an area exit there) first
      local ax = r.areaExitAt and r:areaExitAt(math.floor(e.x + ox), math.floor(e.y + oy))
      if ax then f:startTransition(ax) return true end
      local exit = r:borderExit(dir, p.x, p.y) or f:adjacentRoom(dir)
      if exit then
        f.lilyRide = { ox = math.floor(p.x) - math.floor(e.x), oy = math.floor(p.y) - math.floor(e.y), dir = dir,
                       layer = e.layer, scale = e.lilyScale, rot = e.lilyRot, timer = e.lilyTimer, wob = e.lilyWob }
        e.vx, e.vy = 0, 0
        f:startTransition(exit, dir)
        return true
      end
    end
  end
  return false
end

-- Field:enterRoom (after the room's entities): the pad that came along
function L.onEnterRoom(f)
  local ride = f.lilyRide
  if not ride then return end
  f.lilyRide = nil
  local d = f._dungeon
  if not d then return end
  local p = f.player
  local e = d:spawnObject({ kind = 6, id = 0x14, paramA = 0, paramB = 0, paramC = 0, x = p.x - ride.ox, y = p.y - ride.oy,
                            collision = ride.layer == 2 and 2 or 1 })
  if not e then return end
  -- the room's own pads: EntityHasDuplicateID (Init / Action5)
  for _, o in ipairs(f.entities) do
    if o.lily and not o.deleted then
      if o.lilyWait then f:setFlag("local", o.type2, true) end
      o.deleted = true
    end
  end
  e.form = 0
  e.layer = ride.layer
  e.lilyScale, e.lilyRot, e.lilyTimer, e.lilyWob = ride.scale or e.lilyScale, ride.rot or e.lilyRot, ride.timer or 0, ride.wob
  e.lilySub = 1
  f.entities[#f.entities + 1] = e
  -- Action3 for the scroll's frames
  local V = ({ [0] = { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } })[ride.dir]
  local sp = L.SPEED[ride.dir] / 256
  e.ride = { frames = L.FRAMES[ride.dir], vx = V[1] * sp, vy = V[2] * sp, ox = ride.ox, oy = ride.oy }
  p.jar, p.jarKick = nil, nil -- ResetActiveItems
  p:setAnim(p:animFor("idle"), true)
  p.state = "ext"
  p.layer = ride.layer
  p.extUpdate = function() end
end

-- Dungeon:updateLily: Action3 (true while it runs)
function L.update(d, e, p)
  local r = e.ride
  if not r then return false end
  e.x, e.y = e.x + r.vx, e.y + r.vy
  p.x, p.y = math.floor(e.x) + r.ox, math.floor(e.y) + r.oy
  r.frames = r.frames - 1
  if r.frames <= 0 then
    e.ride = nil
    e.x, e.y = math.floor(e.x), math.floor(e.y)
    p.state, p.extUpdate = "normal", nil
  end
  d:lilyBob(e, true)
  return true
end

local _ = band
return L
