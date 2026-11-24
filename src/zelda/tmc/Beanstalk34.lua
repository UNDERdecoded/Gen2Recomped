-- Round 34: the beanstalk in the field (src/object/beanstalk.c types 7 / 8
-- / 9) and the cloud tops' BACKGROUND_CLOUD ($4A, backgroundCloud.c).  In
-- R34.MODULES (spawnObject); the objects run from Dungeon:update
-- (extUpdate).  Round 33 ported types 0-6 (the growth) for the world-event
-- view (Fusion32.lua).
--
-- Where they stand (room data): type 7 type2 0 in the field rooms $03:00,
-- $03:03, $05:01, $06:00, $0B:01 (timer = the fused Kinstone's local flag)
-- and in the climb rooms $0D:10-$14 (timer 0); type 8 in the cloud tops
-- $0D:00-$04; type 9 is made by type 8.  The rooms' exit lists (already
-- read by Field) join them: field -> climb room -> top ($0D:0n), the top's
-- area warp at ($58, $88) back down.
--
-- CARTRIDGE BEHAVIOUR:
--   * Beanstalk_Init type 7: type2 0 with timer != 0 waits (Init again next
--     frame) until CheckLocalFlag(timer); animation gUnk_08120E3C[type2]
--     {anim, spritePriority}: {1,6} {2,6} {4,3} {7,5} {10,7}.  type2 0
--     builds the stalk: unk_6c = $10; repeat { a BEANSTALK 7/1 (a stalk
--     section) at (x, y - unk_6c); three leaves BEANSTALK 7/(type - 2) of
--     gUnk_08120DFC[timer++ % 6] at (x + dx, y - unk_6c - dy), flipX;
--     unk_6c += $38 } while y - unk_6c >= origin_y; timer = 1.  type2 2 /
--     3: spriteRendering.b3 = 1; 2..4: collision layer 3.
--   * Action1Type7: type2 0, timer 1: SPECIAL_TILE_23 (a ladder) on both
--     layers in the column x from origin_y down to y (and not past the
--     room), timer 0.  type2 1: nothing.  type2 2..4 (leaves): Link on a
--     ladder (SURFACE_LADDER) inside EntityInRectRadius(0, 8) and the
--     animation at (type2 - 1) * 3 + 1 -> the next one (the leaf shakes);
--     GetNextFrame; at its end animation (type2 - 1) * 3 + 1 again.
--   * Type 8 (Init: animation 0, spritePriority 4): flipY 2; SPECIAL_TILE_23
--     at its tile (bottom layer); CHUCHU_BOSS_PARTICLE type 1 at y + $38
--     with the beanstalk's sprite, animation 2, spritePriority 6, timer 128
--     (negative as s8: never deleted; type 1 never steps) -- the stalk
--     under the cloud; a BEANSTALK type 9.
--   * Type 9 (animation 12, spritePriority 6): first frame y += $28 and the
--     tile type at (x, y - 24) kept; Link on a ladder: spritePriority 0 and
--     SPECIAL_TILE_20 (a ladder) at (x, y - 24); else spritePriority 5 and
--     the kept tile back.
--   * BackgroundCloud_Init: spritePriority = frameIndex = type, direction 8
--     (east), speed gUnk_08121EB0[type] ($30 / $28 / $20), bounds origin_x
--     - $60 .. origin_x + width + $60, x += (Random & $F) << 4.  Action1:
--     LinearMoveUpdate; outside the bounds -> Action2: wait ((Random & 7) <<
--     3) + 31 frames at the left bound (type 2: y = gUnk_08121EB3[type2 * 2
--     + (Random & 1)] of {8, $28, $48, $98}), then move again.
-- SIMPLIFIED: OAM priority bits (spriteOrientation.flipY / spriteRendering.b3)
--   are not modelled beyond the sort priority; Random is love's.
local bit = require("bit")
local band = bit.band

local M = {}
M.BEANSTALK, M.BACKGROUND_CLOUD, M.CHUCHU_BOSS_PARTICLE = 0x2C, 0x4A, 0x1C
local SP23, SP20 = 0x4017, 0x4014                       -- SPECIAL_TILE_23 / 20 (tiles.h)
M.SP23, M.SP20 = SP23, SP20
local E3C = require("src.zelda.tmc.RomTables").t("Beanstalk34.E3C")  -- gUnk_08120E3C
local E14 = require("src.zelda.tmc.RomTables").t("Beanstalk34.E14") -- gUnk_08120E14 {animation, priority} by type
local DFC = require("src.zelda.tmc.RomTables").t("Beanstalk34.DFC")                    -- gUnk_08120DFC {type, x, y, flipX}
local CLOUD_SPEED = require("src.zelda.tmc.RomTables").t("Beanstalk34.CLOUD_SPEED")                           -- gUnk_08121EB0
local CLOUD_Y = require("src.zelda.tmc.RomTables").t("Beanstalk34.CLOUD_Y")                      -- gUnk_08121EB3
M.E3C, M.DFC = E3C, DFC

local function rnd() return love and love.math and love.math.random(0, 0x7FFF) or math.random(0, 0x7FFF) end
M.rnd = rnd

local function lastKey(e) return e.anim and (band(e.anim.flags or 0, 0x80) ~= 0 or e.anim.done) end

local function setAnim(f, e, n)
  e.objAnim = n
  e.animIndex = n
  if e.anim and e.sprite then e.anim:set(f.assets:sprite(e.sprite), n, true) end
end

-- an object entity drawn with the def of (id, form)
local function newObj(f, id, form, x, y, anim)
  local e = { kind = 6, id = id, form = form, x = x, y = y, z = 0, animationState = 0, field80 = 0, field82 = 0,
              interactType = 0, layer = 1 }
  local O = f:objects()
  local def = O and O:def(id, form)
  if def then O:dress(e, def, anim or 0); e.objAnim = anim or 0 end
  return e
end

local function add(f, d, e)
  f.entities[#f.entities + 1] = e
  if d then d:track(e) end
  return e
end

local function onLadder(f)
  local p = f.player
  return p and p.climbing and true or false
end
M.onLadder = onLadder

-- ---------------------------------------------------------------------------
-- type 7
-- ---------------------------------------------------------------------------
local update7

local function init7(f, d, e)
  local t2 = e.type2 or 0
  if t2 == 0 and (e.timer or 0) ~= 0 then
    if not f:flag("local", e.timer) then return false end
  end
  setAnim(f, e, E3C[t2] and E3C[t2][1] or 1)
  e.spritePriority = E3C[t2] and E3C[t2][2] or 6
  e.hidden = false
  if t2 == 0 then
    local h = 0x10
    local k = 0
    repeat
      local s = newObj(f, M.BEANSTALK, 7, e.x, e.y - h, E3C[1][1])
      s.type2, s.spritePriority, s.bean34 = 1, E3C[1][2], true
      s.extUpdate = function(dd, me) update7(f, dd, me) end
      add(f, d, s)
      for _ = 1, 3 do
        local p = DFC[k]
        local l2 = p[1] - 2
        local l = newObj(f, M.BEANSTALK, 7, e.x + p[2], e.y - h - p[3], E3C[l2][1])
        l.type2, l.spritePriority, l.flipX, l.bean34 = l2, E3C[l2][2], p[4], true
        l.layer = 3
        l.extUpdate = function(dd, me) update7(f, dd, me) end
        add(f, d, l)
        k = k + 1
        if k > 5 then k = 0 end
      end
      h = h + 0x38
    until e.y - h < 0
    e.timer = 1
  elseif t2 >= 2 then
    e.layer = 3
  end
  e.inited = true
  return true
end
M.init7 = init7

function update7(f, d, e)
  if not e.inited then
    if not init7(f, d, e) then return end
  end
  local t2 = e.type2 or 0
  if t2 == 0 then
    if e.timer == 0 then return end
    local r = f.room
    local tx = math.floor(e.x / 16)
    local y = 0
    while true do
      local ty = math.floor(y / 16)
      if tx >= 0 and tx < r.tw and ty >= 0 and ty < r.th then
        r:setTile(2, tx, ty, SP23)
        r:setTile(1, tx, ty, SP23)
      end
      y = y + 0x10
      if y >= r.height then break end
      if y > e.y then break end
    end
    e.timer = 0
  elseif t2 >= 2 and t2 <= 4 then
    local base = (t2 - 1) * 3 + 1
    if onLadder(f) then
      local p = f.player
      if p.x - e.x == 0 and math.abs(p.y - e.y) <= 8 then
        if e.objAnim == base and (e.shake or 0) == 0 then e.shake = 1; setAnim(f, e, base + 1) end
      else e.shake = 0 end
    else e.shake = 0 end
    e.anim:update(1)
    if lastKey(e) then setAnim(f, e, base) end
  end
end

-- ---------------------------------------------------------------------------
-- types 8 / 9
-- ---------------------------------------------------------------------------
local function update9(f, d, e)
  local r = f.room
  if not e.sub then
    e.sub = 1
    e.y = e.y + 0x28
    e.ttx, e.tty = math.floor(e.x / 16), math.floor((e.y - 24) / 16)
    e.kept = r.maps.bottom[e.tty * r.tw + e.ttx]
  end
  local tx, ty = e.ttx, e.tty
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return end
  local cur = r.maps.bottom[ty * r.tw + tx]
  if onLadder(f) then
    e.spritePriority = 0
    if cur ~= SP20 then r:setTile(1, tx, ty, SP20) end
  else
    e.spritePriority = 5
    if e.kept and cur ~= e.kept then r:setTile(1, tx, ty, e.kept) end
  end
end
M.update9 = update9

local function init8(f, d, e)
  setAnim(f, e, E14[8][1])
  e.spritePriority = E14[8][2]
  local r = f.room
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  if tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th then r:setTile(1, tx, ty, SP23) end
  -- CHUCHU_BOSS_PARTICLE type 1: the beanstalk's sprite, animation 2, never steps
  local p = newObj(f, M.BEANSTALK, 8, e.x, e.y + 0x38, 2)
  p.spritePriority, p.bean34, p.particle = 6, true, true
  add(f, nil, p)
  local n = newObj(f, M.BEANSTALK, 9, e.x, e.y, E14[9][1])
  n.spritePriority, n.bean34 = E14[9][2], true
  n.extUpdate = function(dd, me) update9(f, dd, me) end
  add(f, d, n)
  e.inited = true
end
M.init8 = init8

-- ---------------------------------------------------------------------------
-- BACKGROUND_CLOUD
-- ---------------------------------------------------------------------------
local function cloudUpdate(f, d, e)
  if e.action == 1 then
    e.x = e.x + e.speed / 256 -- LinearMoveUpdate, direction 8
    if e.x < e.lo or e.x > e.hi then e.action, e.sub = 2, 0 end
  else
    if e.sub == 0 then
      e.sub = 1
      e.wait = band(rnd(), 7) * 8 + 31
      e.x = e.lo -- direction 8: (direction & $10) == 0
      if e.form == 2 then e.y = CLOUD_Y[band((e.type2 or 0) * 2 + band(rnd(), 1), 7)] or e.y end
    end
    e.wait = e.wait - 1
    if e.wait == 0 then e.action, e.sub = 1, 0 end
  end
end
M.cloudUpdate = cloudUpdate

local function cloudInit(f, d, e)
  local O = f:objects()
  local def = O and O:def(M.BACKGROUND_CLOUD, e.form or 0)
  if def then O:dress(e, def, 0) end
  local t = e.form or 0
  e.objAnim = 0
  e.staticFrame = t -- frameIndex = type
  e.spritePriority = t
  e.speed = CLOUD_SPEED[t] or 0x20
  e.lo, e.hi = -0x60, f.room.width + 0x60
  e.x = e.x + band(rnd(), 0xF) * 16
  e.action, e.sub = 1, 0
  e.cloud34 = true
  e.extUpdate = function(dd, me) cloudUpdate(f, dd, me) end
  d:track(e)
  return e
end
M.cloudInit = cloudInit

-- ---------------------------------------------------------------------------
-- R34 interface
-- ---------------------------------------------------------------------------
-- The climb rooms ($0D:05..) draw their picture from gMapDataTopSpecial
-- (map_top_special) and clear the bottom map.  The beanstalk's sections
-- (spriteRendering.b3 2) and Link (layer 1, OAM priority 2) are seen over
-- that picture on the cartridge, so it cannot sit at BG1's usual priority
-- 1 there; the port draws it at priority 3 (under every sprite).  (Inferred
-- from the objects' own OAM priorities; the BG control write itself was
-- not found in the decomp.)
function M.roomInit(f)
  local r = f.room
  if r and r.area == 0x0D and r.specialTop then r.bgPrio = { bottom = 2, top = 3 } end
end

-- The way up.  The climb rooms' exit lists lead down only (south border ->
-- the field room at the stalk, e.g. $0D:10 -> $06:00 at ($98, $18)); the
-- field rooms list no exit into area $0D (transitions.c), and no code found
-- in the decomp adds one.  The port takes the reverse of the climb room's
-- south exit: Link climbing a grown field stalk over the room's top edge
-- (on its ladder column) goes to that climb room's bottom edge at the
-- stalk (x $78).  (INFERRED: the cartridge's own mechanism was not found.)
M.CLIMB_ROOMS = { 0x10, 0x11, 0x12, 0x13, 0x14 }
function M.climbRoomFor(f, area, room)
  local A = f.assets
  for _, id in ipairs(M.CLIMB_ROOMS) do
    local ok, r = pcall(require("src.zelda.tmc.Room").load, A, 0x0D, id)
    if ok and r then
      for _, e in ipairs(r.exits or {}) do
        if e.area == area and e.room == room and (e.warpType == 0 or e.warpType == 2) then return id, r, e end
      end
    end
  end
  return nil
end

function M.frame(f, input)
  local p, r = f.player, f.room
  if not (p and r) or f.transition or r.area == 0x0D or not p.climbing then return false end
  if p.y > 8 or not (input and input.down and input.down("up")) then return false end
  local stalk
  for _, e in ipairs(f.entities) do
    if e.bean34 and e.form == 7 and (e.type2 or 0) == 0 and e.inited and math.floor(e.x / 16) == math.floor(p.x / 16) then
      stalk = e
    end
  end
  if not stalk then return false end
  local id, cr, back = M.climbRoomFor(f, r.area, r.room)
  if not id then return false end
  local ex = {}
  for k, v in pairs(back) do ex[k] = v end
  ex.area, ex.room, ex.endX, ex.endY = 0x0D, id, 0x78, cr.height - 8
  f.climbUp34 = id
  f:startTransition(ex, 0)
  return false
end

function M.spawnObject(d, e)
  local f = d.field
  if e.id == M.BACKGROUND_CLOUD then return cloudInit(f, d, e) end
  if e.id ~= M.BEANSTALK then return nil end
  local t = e.form or 0
  e.timer = e.timer0 or 0
  e.bean34 = true
  if t == 7 then
    local O = f:objects()
    local def = O and O:def(M.BEANSTALK, 7)
    if def then O:dress(e, def, 1) end
    e.hidden = true
    e.extUpdate = function(dd, me) update7(f, dd, me) end
    d:track(e)
    update7(f, d, e) -- Beanstalk_Init ends with Beanstalk_Action1
    return e
  elseif t == 8 then
    local O = f:objects()
    local def = O and O:def(M.BEANSTALK, 8)
    if def then O:dress(e, def, 0) end
    init8(f, d, e)
    d:track(e)
    return e
  elseif t == 9 then
    local O = f:objects()
    local def = O and O:def(M.BEANSTALK, 9)
    if def then O:dress(e, def, E14[9][1]) end
    e.extUpdate = function(dd, me) update9(f, dd, me) end
    d:track(e)
    return e
  end
  return nil
end

return M
