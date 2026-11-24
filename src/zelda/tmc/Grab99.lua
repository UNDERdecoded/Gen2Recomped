-- Round 99: the grab collision (collision.c sub_08018168, gCollisionHandlers[15]) and WALL_MASTER ($1A, wallMaster.c)
-- as the cartridge runs them.
--
-- PORT GAP (round 98's note): a Wall Master touching Link in its last falling frames hurt him for 2 and knocked him back,
-- where the cartridge grabs him.  The port's generic contact took gCollisionMtx's $FF entries (special handlers) it does
-- not know as DEFAULT_TOUCH (2 damage); hitType $74 (WALL_MASTER, WALL_MASTER_2) and $0E (VAATI_PROJECTILE) against
-- Link's body (hurtType 0) are handler 15.  The Wall Master also grabbed by its own box test in actions 3 / 4 only (also
-- while rising, where the cartridge never grabs), and its two timers ran differently.
--
-- CARTRIDGE BEHAVIOUR (zeldaret/tmc)
--   * sub_08018168 (Link = org, the enemy = tgt): when the enemy is not confused and PlayerCanBeMoved() and Link is not
--     Minish / rolling / swimming: Link is held (mobility / field_0xa |= $80, PL_DISABLE_ITEMS, jump_status 0,
--     COLLISION_OFF, iframes $FF, PutAwayItems) and RESULT_COLLISION -> the enemy's OnCollision (contactFlags = $80 |
--     hurtType).  Otherwise no collision at all: no damage, no knockback.  A confused enemy only pushes Link out.
--   * IsColliding's z test: |dz| <= 5 + 5 for two flat hitboxes.
--   * WALL_MASTER: sub_0802A4E4 (init): unk_7a = type2 * 60, unk_78 = timer * 60, unk_7c = timer.
--     sub_0802A78C, every frame before the action (action != 0): Link targetable (sub_08049DF4(1)) and inside the home
--     rectangle (sub_08049FDC) -> unk_7a-- once unk_78 is 0; otherwise unk_7a = type2 * 60 + 1.
--     action 1: unk_78 -> 0 first; then with unk_7a 0 and a target: appear over it (action 2, timer 90, COLLISION_ON,
--     z -$80, animation 2).  action 2: the timer, then SFX_12D + animation 0; z += 3 until >= 0 -> action 3 (animation
--     1).  action 3: GetNextFrame; done -> action 4 (timer 30); a keyframe with bit 0 -> hitType $75.  action 4: z -= 2
--     until < -$A0 -> action 1, COLLISION_OFF, hitType $74, unk_78 = unk_7c * 60 (unk_7a is NOT reset: it counts
--     again only while Link is out of the home rectangle / not targetable).
--     WallMaster_OnCollision: hitType != $75 and contactFlags & $7F == 0 or $1E -> action 5 (Link's x / y / z kept,
--     COLLISION_OFF, animation 1).  hitType $75 against Link is handler 16 (push out only).
--   SIMPLIFIED: Link's iframes $FF are 2 frames here (the holder's own code keeps him: state "ext"); the enemy's
--   iframes -8 are not set.
--
-- Hooks: Enemies.lua's contact calls M.contact for handler 15 (one anchored line) and reads e.zTouch99 for the z test;
-- EnemyTraps.update's WALL_MASTER goes to M.wallMaster (wrapped here, guard EnemyTraps.grab99Installed).  Listed in
-- R27A.MODULES.  No game data here: the breathe table and the exit transitions are EnemyTraps' ROM tables.
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}
M.HANDLER = 15
M.HIT_GRAB, M.HIT_LANDED = 0x74, 0x75
M.ZDEPTH = 10 -- IsColliding: 5 + 5
M.SFX_12D = 0x12D

-- sub_08018168's test: PlayerCanBeMoved() and not Minish / rolling / swimming
local NOT_MOVABLE = { dead = true, ext = true, itemget = true, fall = true, portal = true, climb = true, cart = true,
                      hole = true, drown = true, roll = true }
function M.canGrab(p)
  if not p or NOT_MOVABLE[p.state or "normal"] then return false end
  if p.minish or p.swimming or p.hidden or p.inCart or p.ledge or p.portalMode then return false end
  if p.inHole42 and not p.hop42 then return false end
  if p.fling and (p.fling.phase or 0) < 3 then return false end
  return true
end

-- the generic contact's handler 15: returns true (the touch is consumed: never damage)
function M.contact(E, e, hurtType)
  local p = E.field.player
  if (e.confused or 0) > 0 then return true end
  if not M.canGrab(p) then return true end
  p.invuln = math.max(p.invuln or 0, 2)
  p.moving = false
  if e.onCollision then e.onCollision(E, e, 0x80 + (hurtType or 0)) end
  return true
end

-- sub_08049DF4(1) (sub_08049E4C): full-size Link, not busy
-- (a held Link -- state "ext": PL_CAPTURED / PL_DISABLE_ITEMS -- is no target)
local function target(f)
  local t = require("src.zelda.tmc.EnemyDeepwood").target(f)
  if t and t.state == "ext" then return nil end
  return t
end
M.target = target
local function inHome(e, x, y)
  return x - e.homeX >= 0 and x - e.homeX <= e.rangeW and y - e.homeY >= 0 and y - e.homeY <= e.rangeH
end
M.inHome = inHome

-- sub_0802A78C
function M.tick(f, e)
  if e.action == 0 then return end
  local t = target(f)
  if t and inHome(e, math.floor(t.x), math.floor(t.y)) then
    if e.waitOut == 0 and e.waitIn > 0 then e.waitIn = e.waitIn - 1 end
  else
    e.waitIn = e.type2 * 60 + 1
  end
end

-- WallMaster_OnCollision
function M.onCollision(E, e, flags)
  local c = band(flags or 0, 0x7F)
  if e.hitType ~= M.HIT_LANDED and (c == 0 or c == 0x1E) then
    local p = E.field.player
    e.action = 5
    e.noTouch = true
    e.grabX, e.grabY, e.grabZ = p.x, p.y, p.z or 0
    E:setAnim(e, 1)
    e.anim:set(E.A:sprite(e.sprite), 1, true)
  end
end

function M.wallMaster(E, e, T)
  local f = E.field
  local p = f.player
  local BREATHE, WM = T.BREATHE99, T.WM99
  e.breathe = (e.breathe or math.random(0, 255)) + 1
  local s = BREATHE[band(rshift(e.breathe, 3), 7)] + 0x100
  e.affine = { s = 256 / s, r = 0 }
  e.zTouch99 = M.ZDEPTH + 1
  e.onCollision = M.onCollision
  if e.action == 0 then
    e.action = 1
    e.waitIn = e.type2 * 60
    e.waitOut = e.timerByte * 60
    e.hitType = M.HIT_GRAB
    e.noTouch, e.hidden = true, true
    return
  end
  M.tick(f, e)
  if e.action == 1 then
    if e.waitOut > 0 then e.waitOut = e.waitOut - 1
    elseif e.waitIn == 0 then
      local t = target(f)
      if t then
        e.action, e.timer = 2, 90
        e.noTouch, e.hidden = false, false
        e.x, e.y, e.z = math.floor(t.x), math.floor(t.y), 0x80
        E:setAnim(e, 2)
      end
    end
  elseif e.action == 2 then
    if e.timer > 0 then
      e.timer = e.timer - 1
      if e.timer == 0 then f:sound(M.SFX_12D); E:setAnim(e, 0) end
    else
      e.z = e.z - 3
      if e.z <= 0 then e.z = 0; e.action = 3; E:setAnim(e, 1) end
    end
  elseif e.action == 3 then
    e.anim:update(1)
    if e.anim.done then e.action, e.timer = 4, 30
    elseif band(e.anim.flags or 0, 1) ~= 0 then e.hitType = M.HIT_LANDED end
  elseif e.action == 4 then
    e.z = e.z + 2
    if e.z > 0xA0 then
      e.action = 1
      e.noTouch, e.hidden = true, true
      e.hitType = M.HIT_GRAB
      e.waitOut = e.timerByte * 60
    end
  elseif e.action == 5 then
    -- sub_0802A69C: Link held at the grab spot, hidden on the hand's keyframe
    p.x, p.y = e.grabX, e.grabY
    p.state = "ext"; p.extUpdate = function() end
    p.invuln = math.max(p.invuln or 0, 2)
    e.anim:update(1)
    if e.anim.done then e.action, e.timer = 6, 30; p.hidden = true
    elseif band(e.anim.flags or 0, 1) ~= 0 then p.hidden = true end
  elseif e.action == 6 then
    e.z = e.z + 2
    e.timer = e.timer - 1
    p.invuln = math.max(p.invuln or 0, 2)
    if e.timer <= 0 then
      e.action = 7
      p.hidden = nil; p.state = "normal"; p.extUpdate = nil
      -- DoExitTransition(gWallMasterScreenTransitions[gArea.dungeon_idx]); outside a dungeon: field.entry
      local info = f.room.areaInfo
      local di = info and info.location and info.location - 23
      local wm = di and di >= 0 and WM[di]
      if wm then
        f:startTransition({ warpType = wm.warpType, area = wm.area, room = wm.room, endX = wm.endX, endY = wm.endY,
                            facing = wm.facing, kind = wm.kind })
      else
        local to = f.entry or {}
        f:startTransition({ warpType = 1, area = to.area or f.room.area, room = to.room or f.room.room,
                            endX = to.x or p.x, endY = to.y or p.y, facing = to.facing or 4, kind = 0 })
      end
    end
  end
  if e.action ~= 3 and e.action ~= 5 then e.anim:update(1) end
end

function M.install()
  local T = require("src.zelda.tmc.EnemyTraps")
  if T.grab99Installed then return end
  T.grab99Installed = true
  local RT = require("src.zelda.tmc.RomTables")
  T.BREATHE99 = T.BREATHE99 or RT.t("EnemyTraps.BREATHE") -- wallMaster.c gUnk_080CD0B0 (read from the ROM)
  T.WM99 = T.WM99 or RT.t("EnemyTraps.WM") -- gWallMasterScreenTransitions
  local up0 = T.update
  function T.update(E, e)
    if e.id == T.WALL_MASTER then return M.wallMaster(E, e, T) end
    return up0(E, e)
  end
end

M.install()

return M
