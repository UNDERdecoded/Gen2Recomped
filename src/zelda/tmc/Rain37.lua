-- Round 37: RAINFALL_MANAGER $1C (src/manager/rainfallManager.c), the
-- WATER_DROP enemy $19 (src/enemy/waterDrop.c) and its WATER_DROP_OBJECT
-- $66 shadow (src/object/waterDropObject.c): the rain in the Crenel Minish
-- path $12:02, where the drops are dodged under the leaves.
--
-- CARTRIDGE BEHAVIOUR:
--   * The manager: every 15 frames (the first at once) CreateEnemy(
--     WATER_DROP, 0) at scroll_x + $78 + gUnk_08108C6C[rand & 7], scroll_y +
--     $50 + gUnk_08108C7C[rand & 3], z -200.
--   * WATER_DROP init: action 1, zVelocity -3.0, speed gUnk_080CD03C[rand &
--     3], direction gUnk_080CD040[rand & 3] + $18, collision layer 2,
--     animation 0, the WATER_DROP_OBJECT child.
--   * Action 1: GravityUpdate(Q_8_8(40)) -- landed: action 2, sprite
--     priority 7, SFX_WATER_SPLASH; else LinearMoveUpdate.  sub_0802A39C:
--     collision off while the BG1 entry over Link's head (Link - 10 px, in
--     the horizontal path BG1's screen) is not empty -- he is under a leaf --
--     else on.  Below z -8 sub_0802A334: layer 2 over a BG1 entry, else 1.
--   * Action 2: the splash animation; its end deletes it, frames with flag
--     bit 1 have no collision, the others the leaf check.
--   * WATER_DROP_OBJECT: animation 1 at the drop's x / y while it is in the
--     air (sprite priority 6, y offset 5), its flipY / OAM priority; affine
--     scale (0x100, 0x200) below z -64, else (0x100 - 2 (z + 64), 0x200 - 4
--     (z + 64)) (an inverse matrix: the shadow grows as the drop falls).
-- SIMPLIFIED: the drop touches Link only near the ground (the port's
--   contact rule, z < 8); the affine shadow is drawn with love's scale.
local bit = require("bit")
local band = bit.band

local M = {}
M.MANAGER, M.WATER_DROP, M.WATER_DROP_OBJECT = 0x1C, 0x19, 0x66
M.SFX_WATER_SPLASH = 0x84 -- include/sound.h
local DROP_X = require("src.zelda.tmc.RomTables").t("Rain37.DROP_X")         -- gUnk_08108C6C
local DROP_Y = require("src.zelda.tmc.RomTables").t("Rain37.DROP_Y")         -- gUnk_08108C7C
local DROP_SPEED = require("src.zelda.tmc.RomTables").t("Rain37.DROP_SPEED") -- gUnk_080CD03C
local DROP_DIR = require("src.zelda.tmc.RomTables").t("Rain37.DROP_DIR")     -- gUnk_080CD040
M.DROP_X, M.DROP_Y, M.DROP_SPEED, M.DROP_DIR = DROP_X, DROP_Y, DROP_SPEED, DROP_DIR
M.GRAVITY = 0x2800

local function rnd(f)
  local D = require("src.zelda.tmc.Drops")
  return D.random(D.rngOf(f))
end

function M.spawnManager(d, m)
  if m.id ~= M.MANAGER then return nil end
  d.field.rain37 = { room = d.field.room, timer = 1 }
  return true
end

function M.spawnDrop(f, x, y)
  local e = f:spawn({ kind = 3, id = M.WATER_DROP, paramA = 0, paramB = 0, paramC = 0, x = x, y = y, pool = 0, collision = 2 })
  if e then
    e.cz = -200 * 65536
    e.z = 200
  end
  return e
end

function M.frame(f)
  local r = f.rain37
  if not r then return false end
  if r.room ~= f.room then f.rain37 = nil return false end
  if f.transition then return false end
  r.timer = r.timer - 1
  if r.timer <= 0 then
    r.timer = 15
    local cx, cy = math.floor(f.camX or 0), math.floor(f.camY or 0)
    local x = cx + 0x78 + (DROP_X[band(rnd(f), 7)] or 0)
    local y = cy + 0x50 + (DROP_Y[band(rnd(f), 3)] or 0)
    M.spawnDrop(f, x, y)
  end
  return false
end

function M.handles(e) return e.id == M.WATER_DROP and e.kind == 3 end

-- the BG1 entry over (x, y) of the path's BG1 screen (PathBg37), 0 = empty
local function covered(f, x, y)
  return require("src.zelda.tmc.PathBg37").bg1At(f, x, y) ~= 0
end
M.covered = covered

local function leafCheck(f, e) -- sub_0802A39C
  local p = f.player
  e.noTouch = covered(f, math.floor(p.x), math.floor(p.y) - 10) or nil
end

local function layerCheck(f, e) -- sub_0802A334
  e.layer = covered(f, math.floor(e.x), math.floor(e.y)) and 2 or 1
end

local function shadow(f, e)
  local s = { kind = 6, id = M.WATER_DROP_OBJECT, form = 0, x = e.x, y = e.y, z = 0, animationState = 0,
              field80 = 0, field82 = 0, interactType = 0, layer = e.layer, parent = e }
  local O = f:objects()
  local def = O and O:def(M.WATER_DROP_OBJECT, 0)
  if not def then return nil end
  O:dress(s, def, 1)
  s.objAnim, s.spritePriority, s.spriteOY = 1, 6, 5
  s.extUpdate = function(_, me)
    local pz = me.parent.cz and math.floor(me.parent.cz / 65536) or 0
    if me.parent.deleted or pz == 0 then me.deleted = true return end
    me.x, me.y, me.layer = me.parent.x, me.parent.y, me.parent.layer
    local sx, sy
    if pz > -0x40 then sx, sy = 0x100, 0x200
    else sx, sy = 0x100 - 2 * (pz + 0x40), 0x200 - 4 * (pz + 0x40) end
    me.affine = { s = 0x100 / sx, sy = 0x100 / sy, r = 0 }
    if me.anim then me.anim:update(1) end
  end
  f.entities[#f.entities + 1] = s
  f._dungeon:track(s)
  return s
end

function M.update(E, e)
  local f = E.field
  if e.action == 0 then
    e.action, e.timer = 1, 0
    e.czv = -3 * 65536
    e.cz = e.cz or 0
    e.speed = DROP_SPEED[band(rnd(f), 3)] or 0x80
    e.dir = band((DROP_DIR[band(rnd(f), 3)] or 0) + 0x18, 0x1F)
    e.layer = 2
    E:setAnim(e, 0)
    e.shadow37 = shadow(f, e)
  end
  if e.action == 1 then
    e.cz = e.cz - e.czv
    e.czv = e.czv - M.GRAVITY
    if e.cz >= 0 then
      e.cz, e.czv = 0, 0
      e.action, e.spritePriority = 2, 7
      f:sound(M.SFX_WATER_SPLASH)
    else
      local a = (e.dir % 32) / 32 * 2 * math.pi
      e.x, e.y = e.x + math.sin(a) * e.speed / 256, e.y - math.cos(a) * e.speed / 256
    end
    e.z = -math.floor(e.cz / 65536)
    leafCheck(f, e)
    if math.floor(e.cz / 65536) > -8 then layerCheck(f, e) end
  else
    if e.anim then e.anim:update(1) end
    local fl = e.anim and e.anim.flags or 0
    if band(fl, 0x80) ~= 0 or (e.anim and e.anim.done) then e.deleted = true return end
    if band(fl, 1) ~= 0 then e.noTouch = true else leafCheck(f, e) end
  end
end

return M
