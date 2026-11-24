-- Round 72: the crows that take the Graveyard Key (KEY_STEALING_TAKKURI $97, src/object/keyStealingTakkuri.c) and
-- the key they drop (GRAVEYARD_KEY $96, src/object/graveyardKey.c).  Round 27A ported the crow scene's script
-- natives (sub_0809E0A0 / sub_0809E0D4) and the dropped key's bounce (type 5); the crows in the valley's trees
-- (type 3 and the key they hold, type 1) and GRAVEYARD_KEY were not ported, and the scene's first crow stopped on
-- a missing native (sub_0807FBD4).  The type-5 key also stood still while the scene's player script ran (the
-- port's tracked objects wait while a player script runs; the cartridge's do not), so the scene never ended.
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * Type3_Init: action 1, layer 2, timer 10, subtimer 0, speed 0, direction gUnk_0812412D[type2], position =
--     room + gUnk_08124132[type2] (y + $40, z -64), animation gUnk_08124128[type2]; a type-1 child (the key in its
--     beak) at the crow + (0, 8), x - 16 when the direction is $18 else + 16.
--   * Type3_Action1 / sub_0809E2C4: Link inside one of gUnk_08124158's four boxes around room + gUnk_08124178[type2]:
--     with the box's facing and PLAYER_BOUNCE (the Pegasus Boots' bonk) -> 1: action 3, timer 255, animation + 2,
--     SFX_123, GRAVEYARD_KEY type type2 + 2 where the child was (the child goes); else 2: --timer, at 0 -> action 2,
--     animation + 2, SFX_123 + SFX_1F3.  Outside the boxes the timer goes back to 10.
--   * Type3_Action2: the crow flies (sub_0809E1F0: speed + $40 up to $400, LinearMoveUpdate); once it passes its key
--     (the x sign against the direction) -> action 3, subtimer 1 (the key follows), SFX_102.
--   * Type3_Action3: off screen -> the child is let go; timer bit 7 (rammed) -> gone, else action 0 at the next tree
--     gUnk_08124146[(Random() & 1) + type2 * 2].
--   * Type1_Action1: no parent / parent gone -> gone; parent subtimer != 0 -> at the parent + (0, 8); drawn with it.
--   * GRAVEYARD_KEY types 2 .. 6 (gUnk_08123FB0 rows): Init (layer 2, zVelocity, direction, speed, y - row.y,
--     timer), Action1 (y + row.y, z - row.y), Action2 (LinearMoveUpdate + BounceUpdate(row.bounce); a landing with
--     timer left bounces again at bounce << 3; else action 3, Link's layer, FX_DASH + SFX_SECRET; SFX_RUPEE_BOUNCE
--     every landing), Action3 (touching Link: CreateItemEntity(row.type, type2), SetFlag(row.flag) = HAKA_KEY_FOUND,
--     gone).  Drawn as the item (sub_08080CB4).
--   * script.c sub_0807FBD4: LinearMoveAngle(speed, direction); the command repeats while the entity is on screen.
-- Tables from the player's ROM (RomTables "Takkuri72.*").
-- SIMPLIFIED: Type0 / Type2 (unused by the valley's lists) are not ported; the key's ground frame is the item's
-- ground-item animation; FX_DASH is the dust effect at the key.
local bit = require("bit")
local band, bxor, lshift = bit.band, bit.bxor, bit.lshift

local M = {}
M.ID, M.KEY_ID = 0x97, 0x96
M.SFX_123, M.SFX_1F3, M.SFX_102, M.SFX_SECRET, M.SFX_RUPEE_BOUNCE = 0x123, 0x1F3, 0x102, 0x73, 0x6E
M.FX_DASH = 0x0E

local RT = require("src.zelda.tmc.RomTables")
local ANIM = RT.t("Takkuri72.ANIM") -- gUnk_08124128
local DIR = RT.t("Takkuri72.DIR")   -- gUnk_0812412D
local POS = RT.t("Takkuri72.POS")   -- gUnk_08124132 (x, y pairs)
local NEXT = RT.t("Takkuri72.NEXT") -- gUnk_08124146
local BOX = RT.t("Takkuri72.BOX")   -- gUnk_08124158
local HOME = RT.t("Takkuri72.HOME") -- gUnk_08124178 (x, y pairs)
local GKEY = RT.t("Takkuri72.GKEY") -- gUnk_08123FB0
M.tables = { ANIM = ANIM, DIR = DIR, POS = POS, NEXT = NEXT, BOX = BOX, HOME = HOME, GKEY = GKEY }

local SIN = {}
for i = 0, 255 + 64 do SIN[i] = math.floor(math.sin((i % 256) * math.pi / 128) * 256 + 0.5) end
local function moveDir(e, speed, dir) -- LinearMoveUpdate (direction 0 .. $1F)
  local m = band(dir or 0, 0x1F) * 8
  e.x = e.x + SIN[m] * speed / 65536
  e.y = e.y - SIN[m + 64] * speed / 65536
end
M.moveDir = moveDir

local function ix(v) return math.floor(v or 0) end
local function onScreen(f, e) -- CheckOnScreen
  local x = ix(e.x) - ix(f.camX) + 0x3F
  local y = ix(e.y) - ix(f.camY) - ix(e.z) + 0x3F
  return x >= 0 and x < 0x16E and y >= 0 and y < 0x11E
end
M.onScreen = onScreen

local function rnd(f)
  if M.random then return M.random() end -- tests
  local D = require("src.zelda.tmc.Drops")
  return D.random(D.rngOf(f))
end

local function setAnim(f, e, idx)
  e.objAnim, e.forceAnim, e.animIndex = idx, idx, idx
  if e.anim and e.sprite then e.anim:set(f.assets:sprite(e.sprite), idx, true) end
end

local function newObj(f, id, form, x, y)
  local O = f:objects()
  local e = { kind = 6, id = id, form = form, x = x, y = y, z = 0, animationState = 0, field80 = 0, field82 = 0,
              interactType = 0, action = 0, anim = require("src.zelda.tmc.Anim").new() }
  local def = O and O:def(id, form)
  if def then O:dress(e, def, 0) end
  f.entities[#f.entities + 1] = e
  return e
end

-- the key in the crow's beak (type 1)
local function child(f, e)
  local par = e.parent
  if not par or par.deleted then e.deleted = true return end
  if (par.subtimer or 0) ~= 0 then e.x, e.y, e.z = par.x, par.y + 8, par.z end
  e.hidden = par.hidden
end

-- sub_0809E2C4: 0 away, 1 rammed (PLAYER_BOUNCE with the box's facing), 2 near
local function near(f, t2)
  local p = f.player
  local hx, hy = M.tables.HOME[t2 * 2 + 1], M.tables.HOME[t2 * 2 + 2]
  local rx, ry = ix(p.x) - hx, ix(p.y) - hy
  for i = 1, 4 do
    local b = M.tables.BOX[i]
    if band(rx - b.x + b.w, 0xFFFF) < b.w * 2 and band(ry - b.y + b.h, 0xFFFF) < b.h * 2 then
      if b.facing == p.animationState and p.bounce then return 1 end
      return 2
    end
  end
  return 0
end
M.near = near

local function type3(f, e)
  if e.type2 == nil then e.type2 = band(e.param or 0, 0xFF) end -- the entity data's paramB (type2)
  if e.action == 0 or e.action == nil then
    local t2 = e.type2 or 0
    e.action, e.layer, e.timer, e.subtimer, e.speed = 1, 2, 10, 0, 0
    e.direction = M.tables.DIR[t2 + 1]
    e.x, e.y = M.tables.POS[t2 * 2 + 1], M.tables.POS[t2 * 2 + 2] + 0x40
    e.z = 64
    e.animBase = M.tables.ANIM[t2 + 1]
    setAnim(f, e, e.animBase)
    local c = newObj(f, M.ID, 1, e.x, e.y + 8)
    c.parent, c.layer, c.z = e, 2, e.z
    setAnim(f, c, 0x3C)
    c.x = c.x + (e.direction == 0x18 and -16 or 16)
    e.child = c
  elseif e.action == 1 then
    local t2 = e.type2 or 0
    local r = near(f, t2)
    if r == 1 then
      e.action, e.timer = 3, 255
      setAnim(f, e, e.animBase + 2)
      f:sound(M.SFX_123)
      local c = e.child
      if c and not c.deleted then
        M.dropKey(f, t2 + 2, c.x, c.y, c.z)
        c.deleted = true
      end
      e.child = nil
    elseif r == 2 then
      if e.timer == 0 then
        e.action = 2
        setAnim(f, e, e.animBase + 2)
        f:sound(M.SFX_123); f:sound(M.SFX_1F3)
      else e.timer = e.timer - 1 end
    else e.timer = 10 end
  elseif e.action == 2 or e.action == 3 then
    if e.action == 2 then
      local c = e.child
      if c and not c.deleted and band(bxor(ix(c.x) - ix(e.x), lshift(e.direction or 0, 11)), 0x8000) ~= 0 then
        e.action, e.subtimer = 3, 1
        f:sound(M.SFX_102)
      end
    end
    if not onScreen(f, e) then
      if e.child then e.child.parent = nil; e.child = nil end
      if band(e.timer or 0, 0x80) ~= 0 then e.deleted = true return end
      e.action = 0
      e.type2 = M.tables.NEXT[band(rnd(f), 1) + (e.type2 or 0) * 2 + 1]
      return
    end
    e.speed = math.min((e.speed or 0) + 0x40, 0x400) -- sub_0809E1F0
    moveDir(e, e.speed, e.direction)
  end
  if e.anim then e.anim:update(1) end
end

-- GRAVEYARD_KEY (graveyardKey.c): a key falling from the crow
function M.dropKey(f, form, x, y, z)
  local row = M.tables.GKEY[form]
  if not row then return nil end
  local k = { kind = 6, id = M.KEY_ID, form = form, x = x, y = y, z = 0, animationState = 0, field80 = 0, field82 = 0,
              interactType = 0, action = 0, type2 = 0, anim = require("src.zelda.tmc.Anim").new() }
  local O = f:objects()
  local d = O and O:def(0x00, row.type) -- sub_08080CB4: drawn as the ground item
  if d then O:dress(k, d, row.type) end
  f.entities[#f.entities + 1] = k
  return k
end

local function bounce(e, accel) -- BounceUpdate: 2 airborne, 1 bounced, 0 down
  local nz = (e.cz or 0) - (e.czv or 0)
  if nz < 0 then e.cz, e.czv = nz, (e.czv or 0) - accel; return 2 end
  e.cz = 0
  local v = -((e.czv or 0) - accel)
  v = v / 2 + v / 8
  if v >= 0.75 then e.czv = v; return 1 end
  e.czv = 0
  return 0
end

local function key(f, k)
  local row = M.tables.GKEY[k.form]
  if not row then k.deleted = true return end
  if k.action == 0 then
    k.action, k.layer = 1, 2
    k.czv = row.zv / 65536
    k.direction, k.speed = row.dir, row.speed
    k.y = k.y - row.y
    k.cz, k.timer = 0, row.timer
  end
  if k.action == 1 then
    k.action = 2
    k.y = k.y + row.y
    k.cz = (k.cz or 0) - row.y
  elseif k.action == 2 then
    if band(k.direction or 0, 0x80) == 0 then moveDir(k, k.speed or 0, k.direction) end
    if bounce(k, row.bounce / 65536) < 2 then
      if (k.timer or 0) ~= 0 then
        k.timer = k.timer - 1
        k.czv = row.bounce * 8 / 65536
      else
        k.action = 3
        k.layer = f.player.layer or 1
        if f.addFx then f:addFx(k.x, k.y, M.FX_DASH, 0) end
        f:sound(M.SFX_SECRET)
      end
      f:sound(M.SFX_RUPEE_BOUNCE)
    end
  elseif k.action == 3 then
    local p = f.player
    if not p.minish and math.abs(p.x - k.x) < 12 and math.abs(p.y - k.y) < 12 and p.state ~= "itemget" then
      f:giveItem(row.type, k.type2 or 0, 0)
      if row.flag ~= 0 then
        local ty, idx = band(row.flag, 0xC000) / 0x4000, band(row.flag, 0x3FF)
        f:setFlag(ty == 1 and "global" or ty == 2 and "room" or "local", idx, true)
      end
      k.deleted = true
      return
    end
  end
  k.z = -(k.cz or 0)
end

-- one line in Field's entity loop (kind 6, ids $97 / $96)
function M.update(f, e)
  if e.deleted then return end
  if e.id == M.KEY_ID then return key(f, e) end
  local t = e.form
  if t == 3 then return type3(f, e)
  elseif t == 1 then return child(f, e)
  elseif t == 5 and f.playerScript and e.extUpdate then
    -- the scene's dropped key: the port's tracked objects wait while a player script runs (Dungeon:update), the
    -- cartridge's entities do not
    return e.extUpdate(f:dungeon(), e)
  end
end

-- CalculateDirectionFromOffsets: the 8-bit angle (0 north, $40 east)
function M.dir256(x0, y0, x1, y1)
  local ang = math.atan2(x1 - x0, -(y1 - y0))
  return math.floor(ang / (2 * math.pi) * 256 + 0.5) % 256
end

-- script.c sub_0807FBD4
local Native = require("src.zelda.tmc.Native")
if not Native.N[0x0807FBD4] then
  Native.N[0x0807FBD4] = function(f, e, ctx, a)
    local m = e.dir256 or band(e.direction or 0, 0x1F) * 8 -- LinearMoveAngle(speed, direction) (the 8-bit angle)
    e.x = e.x + SIN[m] * (e.speed or 0) / 65536
    e.y = e.y - SIN[m + 64] * (e.speed or 0) / 65536
    if onScreen(f, e) and a then a.commandSize = 0 end
  end
end

return M
