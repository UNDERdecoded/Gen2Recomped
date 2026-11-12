-- Round 26 (team B, group "pow"): the Palace of Winds' objects, managers and
-- cloud floors, from the decomp.
--
-- FAN $9F (src/object/fan.c): type = the side it faces (direction (type ^ 2)
--   << 3: type 0 blows south); paramB = type2 | timer << 8 | unk_7e << 16 |
--   unk_7f << 24 (the EntityData copy at +$78), paramC = fanFlags | unk_86 << 16.
--   Init: action 1 (unk_74 = timer * 4), its wind box (sub_0809EFB0: tiles
--   from the fan until a collision-type-9 tile; 32 px wide), animation type.
--   1: fanFlags clear or set, and (type2 != 1 or unk_74 run out) -> 2 (unk_74
--   = unk_7f * 4, animation type).  2: wind; unk_86 != 0 -> stops (3) on its
--   flag (fanFlags == unk_86: when it clears; else when it is set); type2 1 ->
--   stops when unk_74 runs out.  3: wind, animation type + 4 spinning down;
--   done -> 1.  The wind (sub_0809EE44): speed = unk_7e << (frame & 7); a
--   non-zero frame value pushes Link (PlayerCanBeMoved) inside the box the way
--   it blows (sub_08079E58).  sub_0809F08C: GetNextFrame; frame bit $20
--   (cleared) or bit $10 every 20 frames (toggled) -> a FAN_WIND ($B2, type
--   type ^ 2) at gUnk typeOffsets and SFX_183.
-- FAN_WIND $B2 (src/object/fanWind.c): direction type << 3, animation type,
--   the fan's speed every frame, LinearMoveUpdate; a type-9 collision tile
--   ends it; at speed <= $40 it blinks for 16 frames and goes.
-- AMBIENT_CLOUDS $29 (src/object/ambientClouds.c): the cloud floors.
--   type $80: a flat cloud floor (action 3): Link inside 15 px is held up
--   (field_0x14: no fall).  Else the room entry (type2 0) makes a ground
--   cloud (type2 $FF: layer 1, palette $15, priority 7, BG priority 3) and a
--   stack of `type` clouds (type2 = height 1..type, z = -$24 per step; the
--   top one animation 0, the rest 1; each one's child is the one below) and
--   is gone.  A stack cloud (action 1) waits for Link on the cloud below (or
--   the floor for the first): jumping higher than $24 (z < -$24) over it
--   (inside 15 px of its spot raised by (height - 1) * $24) he lands on it:
--   action 2, y - $24, z + $24, collision layer 2 (sub_0807AA80), four
--   FX_DEATH puffs when he was not already that high last frame.  Action 2
--   holds him up while he stays within 15 px of its top (y - height * $24);
--   stepping off: action 1, z - height * $24 and y + height * $24 (he drops
--   to the floor below), layer 1.  Every frame the animation steps 1 or 2
--   frames (Random & 1).
-- PALACE_ARCHWAY $A1 (src/object/palaceArchway.c): frameIndex = type2, BG
--   priority 3, priority 7, SPECIAL_TILE_105 (a loading zone, ACT_TILE_40) on
--   its tile.
-- FLOATING_BLOCK $AE (src/object/floatingBlock.c): frameIndex = type,
--   priority $E, collision layer 1 (a decoration).
-- FLOATING_PLATFORM $16 (src/object/floatingPlatform.c): frameIndex = type,
--   priority 7, the rail of room property type2 (UpdateRailMovement); Link
--   inside gUnk_08120658[type] (rx, ry) and movable -> held up (field_0x14);
--   on the ground on it he is carried (SyncPlayerToPlatform).  Made by a
--   FLOATING_PLATFORM_MANAGER (timer 255, the manager as parent) only one
--   platform a frame may carry him (the manager's timer).
-- FLOATING_PLATFORM_MANAGER $38 (src/manager/floatingPlatformManager.c):
--   loads the EntityData list of room property [type] (parent = itself,
--   timer 255); its timer goes back to 0 every frame.
-- CLOUD_STAIRCASE_TRANSITION_MANAGER $2C (src/manager/cloudStaircase-
--   TransitionManager.c): Link inside (x +- $14, y 0 +- $40), his sprite above
--   the room's top (y + z < 0) with the camera at the top: the room change
--   (PL_SPAWN_PARACHUTE_UP) to area type2, room timer, at (paramC low, high),
--   start_anim paramB >> 24, layer paramB >> 16 & $FF.
-- ROOM INIT (src/roomInit.c, AREA_PALACE_OF_WINDS): ROC_CAPE ($2C) loads
--   gUnk_080EA09C (the region trigger and fight managers) until local flag
--   $70.  The PowBackgroundManager calls of the other rooms are the BG3 the
--   room lists' POW_BACKGROUND_MANAGER already sets up (Bg3.lua).
-- Falling through the cloud floor's gaps is the HOLE_MANAGER pits of each
--   room (Holes.lua); support (field_0x14) from a platform / cloud stops
--   Dungeon:checkFall for that frame (installed hook, like CoFObjects).
-- SIMPLIFIED: the fan's push of Link's items (bombs, arrows, boomerang...)
--   is not modelled; IsTileCollision(.., 9) is the room's solid test; the
--   parachute arrival animation of the staircase transition is the port's
--   default arrival; Roc's Cape (another team) gives the jump over a cloud --
--   the stack only reacts to Link's z.
local bit = require("bit")
local band, bor, bxor, rshift, lshift, bnot = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift, bit.bnot

local P = {}
P.FLOATING_PLATFORM, P.AMBIENT_CLOUDS, P.FAN, P.PALACE_ARCHWAY, P.FLOATING_BLOCK, P.FAN_WIND = 0x16, 0x29, 0x9F, 0xA1, 0xAE, 0xB2
P.MGR_CLOUD_STAIRCASE, P.MGR_FLOATING_PLATFORM = 0x2C, 0x38
local SFX_183 = 0x183
local SPECIAL_FX, FX_DEATH = 0x0F, 0x02
local SPECIAL_TILE_105 = 0x4069
local CLOUD_STEP = 0x24
P.FAN_TILE_STEP = { [0] = 0, 16, -16, 0, 0, -16, 16, 0 } -- tileTypeOffsets (fan.c sub_0809EFB0)
P.FAN_WIND_AT = { [0] = 0, 12, -12, 0, 0, -12, 12, 0 }   -- typeOffsets (fan.c sub_0809F0E4)
P.PLATFORM_RECT = { [0] = 0x12, 0xA, 0xA, 0x12, 0x12, 0x12, 0x1A, 0x1A } -- gUnk_08120658

local function sfx(f, id) if f.sound then f:sound(id) end end
local function dirVec(d) local a = (d % 32) / 32 * 2 * math.pi return math.sin(a), -math.cos(a) end
local function anim(d, e, a)
  e.objAnim, e.animIndex = a, a
  if e.anim and e.sprite and d.field.assets and d.field.assets.sprite then e.anim:set(d.field.assets:sprite(e.sprite), a, true) end
  e.clr, e.clrKey = 0, nil
end
-- the frame byte with the bits the object cleared (super->frame &= ~x) off
local function frameByte(e)
  if not e.anim then return 0 end
  local v = e.anim.flags or 0
  if e.clrKey == e.anim.key then v = band(v, bnot(e.clr or 0)) end
  return v
end
local function clear(e, bits)
  if not e.anim then return end
  if e.clrKey ~= e.anim.key then e.clrKey, e.clr = e.anim.key, 0 end
  e.clr = bor(e.clr, bits)
end
local function toggle(e, bits) -- frame ^= bits (only bits that are set are toggled off here)
  clear(e, bits)
end
P._frame = { byte = frameByte, clear = clear }
local function dress(d, e, id, form)
  local O = d.field.objects and d.field:objects()
  local def = O and O.def and O:def(id, form or 0)
  if def then O:dress(e, def, 0) end
  return def
end
local function canBeMoved(p) -- PlayerCanBeMoved
  if not p or p.state == "dead" then return false end
  return p.state == "normal" or p.state == "shield" or p.state == "gust"
end
local function inRect(a, b, rx, ry) -- EntityInRectRadius
  if band(a.layer or 1, b.layer or 1) == 0 then return false end
  return math.abs(math.floor(a.x) - math.floor(b.x)) <= rx and math.abs(math.floor(a.y) - math.floor(b.y)) <= ry
end
-- field_0x14 for this frame: the floor under Link does not count
function P.support(f) f.powSupport = f.frame or 0 end
function P.supported(f) return f.powSupport ~= nil and f.powSupport == (f.frame or 0) end
local function solid9(f, x, y, layer) -- IsTileCollision(collisionData, x, y, 9)
  local r = f.room
  if not r or not r.isSolid then return true end
  return r:isSolid(x, y, layer or 1)
end

-- ---------------------------------------------------------------------------
-- FAN and FAN_WIND
-- ---------------------------------------------------------------------------
function P.fanBox(f, e) -- sub_0809EFB0
  local cx, cy = P.FAN_TILE_STEP[e.form * 2], P.FAN_TILE_STEP[e.form * 2 + 1]
  local x, y = math.floor(e.x), math.floor(e.y)
  local n = 0
  repeat
    n = n + 1
    x, y = x + cx, y + cy
  until solid9(f, x, y, 1) or n > 64
  local len = (n - 1) * 16
  local t = e.form
  if t == 0 then e.u6c, e.u6e, e.u70, e.u72 = math.floor(e.x) - 0x10, math.floor(e.y) + 8, 0x20, len
  elseif t == 1 then e.u6c, e.u6e, e.u70, e.u72 = math.floor(e.x) - (len + 8), math.floor(e.y) - 0x10, len, 0x20
  elseif t == 2 then e.u6c, e.u6e, e.u70, e.u72 = math.floor(e.x) - 0x10, math.floor(e.y) - (len + 8), 0x20, len
  else e.u6c, e.u6e, e.u70, e.u72 = math.floor(e.x) + 8, math.floor(e.y) - 0x10, len, 0x20 end
  return len
end
function P.inFanBox(e, x, y) -- sub_0809EF78
  local dx, dy = math.floor(x) - e.u6c, math.floor(y) - e.u6e
  return dx >= 0 and dx <= e.u70 and dy >= 0 and dy <= e.u72
end

local function fanOn(d, e) e.action = 2; e.u74 = lshift(e.u7f, 2); anim(d, e, e.form) end -- sub_0809EE08
local function fanStop(d, e) e.action = 3; anim(d, e, e.form + 4) end                       -- sub_0809EE24
local function fanIdle(d, e) e.action = 1; e.u74 = lshift(e.timer0 or 0, 2) end             -- sub_0809EE34

local function windUpdate(d, w)
  local f = d.field
  local par = w.parent
  if w.action == 0 then
    w.action, w.timer = 1, 16
    w.direction = lshift(w.form, 3)
    anim(d, w, w.form)
  end
  w.speed = par and par.speed or 0
  local vx, vy = dirVec(w.direction)
  w.x, w.y = w.x + vx * w.speed / 256, w.y + vy * w.speed / 256
  if solid9(f, w.x, w.y, w.layer) then w.deleted = true return end
  if w.speed < 0x41 then
    w.hidden = not w.hidden
    w.timer = w.timer - 1
    if w.timer == 0 then w.deleted = true return end
  end
  if w.anim then w.anim:update(1) end
end

local function fanWind(d, e) -- sub_0809F0E4
  local f = d.field
  sfx(f, SFX_183)
  local o = { P.FAN_WIND_AT[e.form * 2], P.FAN_WIND_AT[e.form * 2 + 1] }
  local w = { kind = 6, id = P.FAN_WIND, form = bxor(e.form, 2), x = e.x + o[1], y = e.y + o[2], z = 0, parent = e,
              layer = e.layer, animationState = 0, field80 = 0, field82 = 0, interactType = 0, action = 0, fanWind = true }
  dress(d, w, P.FAN_WIND, w.form)
  w.anim = w.anim or require("src.zelda.tmc.Anim").new()
  w.extUpdate = windUpdate
  f.entities[#f.entities + 1] = w
  d:track(w)
  return w
end
P.fanWind = fanWind

local function fanFrames(d, e) -- sub_0809F08C
  if (e.subtimer or 0) ~= 0 then e.subtimer = e.subtimer - 1 end
  if e.anim then e.anim:update(1) end
  local fb = frameByte(e)
  if band(fb, 0x20) ~= 0 then
    clear(e, 0x20)
    e.subtimer = 20
    fanWind(d, e)
  elseif band(fb, 0x10) ~= 0 and e.subtimer == 0 then
    e.subtimer = 20
    toggle(e, 0x10)
    fanWind(d, e)
  end
end

local function fanPush(d, e) -- sub_0809EE44
  local f = d.field
  local k = band(frameByte(e), 7)
  e.speed = lshift(e.u7e, k)
  if k ~= 0 then
    local p = f.player
    if p and P.inFanBox(e, p.x, p.y) and canBeMoved(p) then
      local vx, vy = dirVec(e.direction)
      local s = e.speed / 256
      if p.moveBy then p:moveBy(vx * s, vy * s) else p.x, p.y = p.x + vx * s, p.y + vy * s end -- sub_08079E58
      e.pushed = (e.pushed or 0) + 1
    end
  end
end

function P.fanUpdate(d, e)
  local a = e.action
  if a == 1 then
    if (e.flags == 0 or d:check(e.flags)) then
      if e.type2 ~= 1 then fanOn(d, e)
      else
        e.u74 = band(e.u74 - 1, 0xFFFF)
        if e.u74 == 0 then fanOn(d, e) end
      end
    end
  elseif a == 2 then
    fanFrames(d, e)
    fanPush(d, e)
    if (e.flag or 0) ~= 0 then
      if e.flags == e.flag then
        if d:check(e.flags) then return end
      elseif not d:check(e.flags) then return end
      fanStop(d, e)
    elseif e.type2 == 1 then
      e.u74 = band(e.u74 - 1, 0xFFFF)
      if e.u74 == 0 then fanStop(d, e) end
    end
  elseif a == 3 then
    fanFrames(d, e)
    fanPush(d, e)
    if e.anim and e.anim.done then fanIdle(d, e) end
  end
end

function P.spawnFan(d, e)
  local f = d.field
  dress(d, e, P.FAN, e.form)
  e.anim = e.anim or require("src.zelda.tmc.Anim").new()
  local pb = e.data and e.data.paramB or 0
  e.u7e, e.u7f = band(rshift(pb, 16), 0xFF), band(rshift(pb, 24), 0xFF)
  e.direction = lshift(bxor(e.form, 2), 3)
  e.speed, e.subtimer = 0, 0
  fanIdle(d, e)
  P.fanBox(f, e)
  anim(d, e, e.form)
  e.fan = true
  e.solid = true
  e.extUpdate = function(dd, me) P.fanUpdate(dd, me) end
  d:track(e)
  return e
end

-- ---------------------------------------------------------------------------
-- AMBIENT_CLOUDS
-- ---------------------------------------------------------------------------
local function puffs(f, p)
  if not f.addFx then return end
  f:addFx(p.x + 8, p.y, SPECIAL_FX, FX_DEATH); f:addFx(p.x - 8, p.y, SPECIAL_FX, FX_DEATH)
  f:addFx(p.x, p.y + 8, SPECIAL_FX, FX_DEATH); f:addFx(p.x, p.y - 8, SPECIAL_FX, FX_DEATH)
end

function P.cloudUpdate(d, e)
  local f = d.field
  local p = f.player
  local a = e.action
  if a == 1 then -- AmbientClouds_Action1
    if e.type2 == 0xFF then
      e.spritePriority, e.oamPrio = 7, 3
    else
      e.oamPrio = 0
      if e.type2 == 1 or (e.child and e.child.action == 2) then
        e.timer = ((p.z or 0) > CLOUD_STEP) and 1 or 0
        local probe = { x = e.x, y = e.y - (e.type2 - 1) * CLOUD_STEP, layer = 3 }
        if inRect(probe, p, 15, 15) and e.timer ~= 0 then
          e.action = 2
          e.oamPrio = 3
          if e.type2 ~= 1 and e.child then e.child.action = 1 end
          P.support(f)
          p.y = p.y - CLOUD_STEP
          p.z = (p.z or 0) - CLOUD_STEP
          p.layer = 2 -- sub_0807AA80
          f.powDrop = nil
          if (e.subtimer or 0) == 0 then puffs(f, p) end
        end
        e.subtimer = e.timer
      end
    end
  elseif a == 2 then -- AmbientClouds_Action2
    local probe = { x = e.x, y = e.y - e.type2 * CLOUD_STEP, layer = 3 }
    if inRect(probe, p, 15, 15) then
      P.support(f)
      p.layer = 2
    else
      e.action = 1
      p.z = (p.z or 0) + e.type2 * CLOUD_STEP
      p.y = p.y + e.type2 * CLOUD_STEP
      p.layer = 1
      f.powDrop = { zv = 0 } -- he falls back down (the player's own gravity on the cartridge)
    end
  elseif a == 3 then -- AmbientClouds_Action3
    if inRect({ x = e.x, y = e.y, layer = 3 }, p, 15, 15) then P.support(f) end
  end
  -- UpdateAnimationVariableFrames(this, (Random() & 1) + 1)
  if e.anim then
    local D = require("src.zelda.tmc.Drops")
    local r = (f.assets and f.save) and D.random(D.rngOf(f)) or 0
    e.anim:update(band(r, 1) + 1)
  end
end

local function cloudPiece(d, src, type2, parent)
  local f = d.field
  local c = { kind = 6, id = P.AMBIENT_CLOUDS, form = 0, type2 = type2, x = src.x, y = src.y, z = 0, layer = 3,
              animationState = 0, field80 = 0, field82 = 0, interactType = 0, action = 1, cloud = true, parent = parent,
              timer = 0, subtimer = 0 }
  dress(d, c, P.AMBIENT_CLOUDS, 0)
  c.anim = c.anim or require("src.zelda.tmc.Anim").new()
  anim(d, c, parent == nil and 0 or 1)
  if type2 == 0xFF then
    c.layer = 1
    if f.room and f.room.isSolid then
      local ok, L = pcall(require, "src.zelda.tmc.Layers")
      if ok and L.resolve then local okr, l = pcall(L.resolve, f, c) if okr and l then c.layer = l end end
    end
    if f.assets and f.assets.objPalette then c.palette = f.assets:objPalette(0x15, f.room.atlas and f.room.atlas.palettes) end -- ChangeObjPalette($15)
    c.def = setmetatable({ palette = 0x15 }, { __index = c.def or {} })
  else
    c.z = type2 * CLOUD_STEP
  end
  c.extUpdate = function(dd, me) P.cloudUpdate(dd, me) end
  f.entities[#f.entities + 1] = c
  d:track(c)
  return c
end

function P.spawnClouds(d, e)
  local f = d.field
  if (e.type2 or 0) ~= 0 then return false end
  if e.form == 0x80 then
    dress(d, e, P.AMBIENT_CLOUDS, 0)
    e.anim = e.anim or require("src.zelda.tmc.Anim").new()
    e.layer = 3
    e.action, e.oamPrio = 3, 3
    e.cloud = true
    anim(d, e, 0)
    e.extUpdate = function(dd, me) P.cloudUpdate(dd, me) end
    d:track(e)
    P.cloudUpdate(d, e)
    return e
  end
  -- the spawner: a ground cloud, then the stack from the top down
  local made = {}
  made[#made + 1] = cloudPiece(d, e, 0xFF, e)
  local above = nil
  for t = e.form, 1, -1 do
    local c = cloudPiece(d, e, t, above)
    if above then above.child = c end
    above = c
    made[#made + 1] = c
  end
  e.stack = made
  return nil -- DeleteThisEntity
end

-- ---------------------------------------------------------------------------
-- PALACE_ARCHWAY, FLOATING_BLOCK
-- ---------------------------------------------------------------------------
function P.spawnArchway(d, e)
  local f = d.field
  dress(d, e, P.PALACE_ARCHWAY, e.form)
  e.action = 1
  e.staticFrame = e.type2 or 0
  e.oamPrio, e.spritePriority = 3, 7
  local r = f.room
  if r and r.setTile then
    local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
    e.tileWas = r.tileType and r:tileType(e.layer or 1, tx, ty)
    r:setTile(e.layer or 1, tx, ty, SPECIAL_TILE_105)
  end
  return e
end

function P.spawnBlock(d, e)
  dress(d, e, P.FLOATING_BLOCK, e.form)
  e.action = 1
  e.staticFrame = e.form or 0
  e.spritePriority = band(0xE, 7)
  e.layer = 1
  return e
end

-- ---------------------------------------------------------------------------
-- FLOATING_PLATFORM and its manager
-- ---------------------------------------------------------------------------
local function platOn(d, e) -- sub_08086168
  local f = d.field
  local p = f.player
  local i = (e.form or 0) * 2
  local rx, ry = P.PLATFORM_RECT[i] or 0x12, P.PLATFORM_RECT[i + 1] or 0xA
  if p and inRect(e, p, rx, ry) and canBeMoved(p) then
    P.support(f)
    e.field14 = true
    return (p.z or 0) == 0
  end
  return false
end
P.platOn = platOn

local function sync(d, e, carry) -- SyncPlayerToPlatform
  local f = d.field
  local dir = e.direction or 0xFF
  if band(dir, 0x80) ~= 0 then return end
  local ox, oy = e.x, e.y
  local vx, vy = dirVec(dir)
  e.x, e.y = e.x + vx * (e.speed or 0) / 256, e.y + vy * (e.speed or 0) / 256
  local dx, dy = math.floor(e.x) - math.floor(ox), math.floor(e.y) - math.floor(oy)
  if carry and (dx ~= 0 or dy ~= 0) then
    local p = f.player
    if p.moveBy then p:moveBy(dx, dy) else p.x, p.y = p.x + dx, p.y + dy end
  end
end

function P.platformUpdate(d, e)
  local f = d.field
  e.field14 = nil
  local on = platOn(d, e)
  local par = e.parent
  if (e.timer or 0) ~= 0 and par and (par.timer or 0) == 0 then
    if on then par.timer = (par.timer or 0) + 1 end
    sync(d, e, on)
  elseif (e.timer or 0) == 0 then sync(d, e, on)
  else sync(d, e, false) end
  e.u70 = band((e.u70 or 0) - 1, 0xFFFF)
  if e.u70 == 0 then P.railNext(f, e) end
end

function P.railNext(f, e)
  local CO = require("src.zelda.tmc.CoFObjects")
  CO.railNext(f, e)
  e.u70 = e.u76 or 0
end

function P.spawnPlatform(d, e, parent)
  local f = d.field
  dress(d, e, P.FLOATING_PLATFORM, e.form)
  e.anim = e.anim or require("src.zelda.tmc.Anim").new()
  e.action = 1
  e.speed = 0x100
  e.hidden = false
  e.staticFrame = e.form or 0
  e.spritePriority = 7
  e.parent = parent
  e.timer = parent and 255 or (e.timer0 or 0)
  local props = f.room and f.room.maps and f.room.maps.header and f.room.maps.header.props
  e.railPtr = props and props[e.type2 or 0]
  e.direction = 0xFF
  P.railNext(f, e)
  e.floatingPlatform = true
  e.extUpdate = function(dd, me) P.platformUpdate(dd, me) end
  d:track(e)
  return e
end

function P.spawnPlatformManager(d, m)
  local f = d.field
  local t = require("src.zelda.tmc.R26").ticker(d, function(dd, me) me.timer = 0 end, { id = P.MGR_FLOATING_PLATFORM, timer = 0 })
  local list = d.propList and d:propList(m.type)
  if not list then return true end -- no list: DeleteThisEntity
  for _, ed in ipairs(list) do
    if ed.kind == 6 and ed.id == P.FLOATING_PLATFORM then
      local e = { kind = 6, id = ed.id, form = ed.paramA, type2 = band(ed.paramB or 0, 0xFF), timer0 = band(rshift(ed.paramB or 0, 8), 0xFF),
                  x = ed.x, y = ed.y, z = 0, animationState = 0, field80 = 0, field82 = 0, interactType = 0, dungeon = true, data = ed,
                  layer = (band(ed.collision or 0, 3) == 2) and 2 or 1 }
      P.spawnPlatform(d, e, t)
      f.entities[#f.entities + 1] = e
    elseif f.spawn then
      f:spawn(ed)
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- CLOUD_STAIRCASE_TRANSITION_MANAGER
-- ---------------------------------------------------------------------------
local function inRegion(px, py, cx, cy, hw, hh) -- CheckPlayerInRegion
  local a = cx - (math.floor(px) - hw)
  local b = cy - (math.floor(py) - hh)
  return a >= 0 and a < 2 * hw and b >= 0 and b < 2 * hh
end
P.inRegion = inRegion

function P.staircaseUpdate(d, t)
  local f = d.field
  local p = f.player
  if t.fired or not p then return end
  if inRegion(p.x, p.y, t.x, t.y, 0x14, 0x40) and (math.floor(p.y) - math.floor(p.z or 0)) < 0 and (f.camY or 0) <= 0 then
    t.fired = true
    local ex = { area = t.area, room = t.room, endX = t.sx, endY = t.sy, facing = t.anim, layer = t.layer, kind = 11 } -- PL_SPAWN_PARACHUTE_UP
    f.powStaircase = ex
    if f.startTransition then f:startTransition(ex) end
  end
end

function P.spawnStaircase(d, m)
  local fields = { id = P.MGR_CLOUD_STAIRCASE, x = m.x, y = 0, area = m.type2, room = m.b1,
                   layer = band(m.b32 or 0, 0xFF), anim = band(rshift(m.b32 or 0, 8), 0xFF), sx = m.c0, sy = m.c1 }
  require("src.zelda.tmc.R26").ticker(d, function(dd, me) P.staircaseUpdate(dd, me) end, fields)
  return true
end

-- ---------------------------------------------------------------------------
-- Link dropping off a cloud stack (the player's gravity on the cartridge),
-- and support from clouds / platforms (field_0x14) for checkFall
-- ---------------------------------------------------------------------------
function P.dropTick(f)
  local dr = f.powDrop
  local p = f.player
  if not dr or not p then return end
  if (p.z or 0) <= 0 then f.powDrop = nil; p.z = 0 return end
  dr.zv = dr.zv - 0.125 -- kGravity ($2000)
  p.z = p.z + dr.zv
  if p.z <= 0 then p.z = 0; f.powDrop = nil end
end

function P.install()
  if P._installed then return end
  P._installed = true
  local Dungeon = require("src.zelda.tmc.Dungeon")
  local checkFall = Dungeon.checkFall
  Dungeon.checkFall = function(self, ...)
    local f = self.field
    if f.powDrop then P.dropTick(f) end
    if P.supported(f) then return end -- field_0x14: on a cloud / floating platform
    return checkFall(self, ...)
  end
end

-- ---------------------------------------------------------------------------
-- R26 hooks
-- ---------------------------------------------------------------------------
function P.spawnObject(d, e)
  local id = e.id
  if id == P.FAN then P.install(); return P.spawnFan(d, e) end
  if id == P.AMBIENT_CLOUDS then P.install(); return P.spawnClouds(d, e) end
  if id == P.PALACE_ARCHWAY then return P.spawnArchway(d, e) end
  if id == P.FLOATING_BLOCK then return P.spawnBlock(d, e) end
  if id == P.FLOATING_PLATFORM then P.install(); return P.spawnPlatform(d, e, nil) end
  return nil
end

function P.spawnManager(d, m, dat)
  if m.id == P.MGR_FLOATING_PLATFORM then P.install(); return P.spawnPlatformManager(d, m) end
  if m.id == P.MGR_CLOUD_STAIRCASE then P.install(); return P.spawnStaircase(d, m) end
  return nil
end

P.ROC_CAPE_LIST = 0x080EA09C -- gUnk_080EA09C (data/map/entity_headers.s)
function P.roomInit(f)
  local r = f.room
  if not r or r.area ~= 0x70 then return end
  f.powDrop = nil
  if r.room == 0x2C and not f:flag("local", 0x70) then f:loadEntityList(P.ROC_CAPE_LIST) end -- sub_StateChange_PalaceOfWinds_RocCape
end

return P
