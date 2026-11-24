-- Round 51: WALL_MASTER_2 ($23), src/enemy/wallMaster2.c -- the blue Wallmasters that glide over
-- the floor (FoW $58:13 / $58:1A).  Before round 51 the port ran them through WALL_MASTER's ($1A,
-- wallMaster.c) ceiling-hand code: they waited, then hung over Link at z $80 and never came down
-- in reach of the sword, so $58:13's FIGHT_MANAGER never set local 42 (no Minish portal).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Init (sub_0802CCE0): action 1, timer 60, z -2 (2 px up), collision layer 3 (both), shadow;
--     unk_7a = R, unk_7b = (R >> 8) & $60, unk_7c = 0; sub_0802CF64 picks a heading:
--     inside its home rectangle a random 8-way direction, outside the way home (rounded up).
--   * Action 1 (sub_0802CD54, wander): when unk_7c is 0 (or counts down to 0) and Link is in the
--     home rectangle (sub_08049FDC): unk_7b > 0 -> unk_7b - 1, else action 2, timer = R >> 16,
--     speed $C0, unk_78 = gUnk_080CD728[R & 3] (frames, read from the ROM), unk_7b re-rolled.
--     timer - 1 -> 0: timer 60, a new heading.  LinearMoveUpdate (no tile collision).
--   * Action 2 (sub_0802CDE8, chase): while --unk_78 and Link in the home: every 4th frame the
--     heading turns one step toward Link (sub_08004596), LinearMoveUpdate; else action 1, timer
--     60, speed $60, unk_7c = (R & $38) + $96.
--   * OnCollision with Link's body (contactFlags & $7F = 0 / 1 / $1E): action 3, collision off,
--     animation 1; Link held (mobility / PL_DISABLE_ITEMS).  Action 3 (sub_0802CE68): moves onto
--     Link (unless within 4 px); frame flag 1 hides Link; ANIM_DONE -> action 4, timer 30.
--   * Action 4 (sub_0802CEF4): rises 2 px a frame; timer 0 -> DoExitTransition(
--     gWallMasterScreenTransitions[dungeon]) (EnemyTraps.WM, read from the ROM).
--   * Damage, knockback and death are the generic handlers (Enemies:hit).
-- SIMPLIFIED: the affine wobble (sub_0802CFD8 / gUnk_080CD730 / 740) only steers animationState;
--   the speed before the first chase is $60 (the definition's own speed is not read).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}
M.ID = 0x23
M.CHASE = require("src.zelda.tmc.RomTables").t("WallMaster51.CHASE") -- gUnk_080CD728 (read from the ROM)

local function R() return math.random(0, 0xFFFF) end
local function dirVec(d) local a = (d % 32) / 32 * 2 * math.pi return math.sin(a), -math.cos(a) end
local function dirTo(x, y, tx, ty)
  local a = math.atan2(tx - x, -(ty - y))
  return band(math.floor(a / (2 * math.pi) * 32 + 0.5), 31)
end
local function round8(d) return (math.floor(d / 4) % 8 * 4 + (d % 4 ~= 0 and 4 or 0)) % 32 end -- Direction8RoundUp
local function linear(e)
  local vx, vy = dirVec(e.direction or 0)
  local s = (e.speed or 0) / 256
  e.x, e.y = e.x + vx * s, e.y + vy * s
end
local function inHome(e, x, y) return x - e.homeX >= 0 and x - e.homeX <= e.rangeW and y - e.homeY >= 0 and y - e.homeY <= e.rangeH end
local function heading(e) -- sub_0802CF64
  if inHome(e, e.x, e.y) then e.direction = band(R(), 7) * 4
  else e.direction = round8(dirTo(e.x, e.y, e.homeX + e.rangeW / 2, e.homeY + e.rangeH / 2)) end
  e.animationState = band(rshift(e.direction + 4, 3), 3) * 2
end
local function linkIn(E, e)
  local p = E.field.player
  if p.state == "dead" or p.minish or p.hidden or p.state == "fall" then return false end
  return inHome(e, p.x, p.y)
end

function M.onCollision(E, e, flags)
  local c = band(flags or 0, 0x7F)
  if e.action ~= 1 and e.action ~= 2 then return end
  if c == 0 or c == 1 or c == 0x1E then
    local p = E.field.player
    e.action = 3
    e.noTouch = true
    E:setAnim(e, 1)
    e.anim:set(E.A:sprite(e.sprite), 1, true)
    p.state, p.extUpdate = "ext", function() end
    p.moving = false
    p.invuln = math.max(p.invuln or 0, 2) -- the grab, not a hit (the touch that follows in Enemies:update)
    e.held51 = true
  end
end

function M.update(E, e)
  local f = E.field
  local p = f.player
  if e.action == 0 then
    e.action, e.timer = 1, 60
    e.hidden, e.noTouch, e.collideOn = false, false, true
    e.z = 2
    e.u7b = band(rshift(R(), 8), 0x60)
    e.u7c = 0
    e.speed = 0x60
    e.onCollision = M.onCollision
    E:setAnim(e, 0)
    heading(e)
    return
  end
  if e.action == 1 then
    if (e.u7c == 0 or (function() e.u7c = e.u7c - 1 return e.u7c == 0 end)()) and linkIn(E, e) then
      if e.u7b > 0 then e.u7b = e.u7b - 1
      else
        local t = R()
        e.action, e.timer, e.speed = 2, 0, 0xC0
        e.u78 = M.CHASE[band(R(), 3)]
        e.u7b = band(rshift(t, 8), 0x60)
        e.anim:update(1)
        return
      end
    end
    e.timer = e.timer - 1
    if e.timer <= 0 then e.timer = 60 heading(e) end
    linear(e)
    e.anim:update(1)
  elseif e.action == 2 then
    e.u78 = e.u78 - 1
    if e.u78 > 0 and linkIn(E, e) then
      if band(e.timer, 3) == 0 then
        local want = dirTo(e.x, e.y, p.x, p.y)
        local d = (want - e.direction) % 32
        if d ~= 0 then e.direction = (e.direction + (d < 16 and 1 or -1)) % 32 end
        e.animationState = band(rshift(e.direction + 4, 3), 3) * 2
      end
      e.timer = e.timer + 1
      linear(e)
    else
      e.action, e.timer, e.speed = 1, 60, 0x60
      e.u7c = band(R(), 0x38) + 0x96
    end
    e.anim:update(1)
  elseif e.action == 3 then
    if math.abs(e.x - p.x) > 4 or math.abs(e.y - p.y) > 4 then
      e.direction = dirTo(e.x, e.y, p.x, p.y)
      linear(e)
    end
    e.anim:update(1)
    if band(e.anim.flags or 0, 1) ~= 0 then p.hidden = true end
    if e.anim.done then e.action, e.timer = 4, 30 end
  elseif e.action == 4 then
    e.timer = e.timer - 1
    e.z = (e.z or 0) + 2
    if e.timer <= 0 then
      e.action = 5
      p.hidden = nil; p.state = "normal"; p.extUpdate = nil
      local WM = require("src.zelda.tmc.RomTables").t("EnemyTraps.WM")
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
end

return M
