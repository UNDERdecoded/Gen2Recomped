-- Round 37: small objects and managers the round 34 survey found unhandled.
--
-- CARTRIDGE BEHAVIOUR:
--   * GIANT_BOOK_LADDER $46 (giantBookLadder.c, the Minish hole $2D:10):
--     drawn when type2 is 0, frame = type, collision layer 1, OAM priority /
--     sprite priority spriteDefs[type] (ROM); OnEnterRoom puts the ladder
--     tiles: types 0 / 2: SPECIAL_TILE_143 at (-1, -4) and (0, -4),
--     SPECIAL_TILE_108 at (-2, -4), SPECIAL_TILE_109 at (1, -4) (type 2 also
--     SPECIAL_TILE_114 at (-1..0, 1..2)), then SPECIAL_TILE_142 pairs on the
--     6 (type 0) / 4 (type 2) rows below (-1..0, -3..); type 1: SPECIAL_TILE_142
--     at (-1, 0), (0, 0) and the 2 rows below.  (Offsets from its tile.)
--   * HOUSE_DOOR_INT $5D (houseDoorInterior.c): deleted when its flags
--     (paramC) are set; frame / type2 from HouseDoorInteriorFrameIndices[type]
--     ($FF: frame = type2); the closed door pushes Link out (sub_0800445C,
--     HouseDoorInteriorHitbox); Link within gUnk_081227CC[type2]'s rect
--     radius, facing its animationState and holding its key for 8 frames
--     (timer == 0; unk7d = the EntityData timer must be 0) -> PLAYER_ROOM_EXIT
--     (sub_08078AC0(8, 0, 0)), SFX_111; its flag set later -> gone, SFX_111.
--   * LILYPAD_SMALL $73 (lilypadSmall.c): rides the room property rail
--     (type2), frame (rand >> 16) & 3 turning every 90 frames, affine scale
--     gUnk_08123318[(subtimer >> 5) & 7]; Minish Link within 8 px (and
--     PlayerCanBeMoved) is carried (SyncPlayerToPlatform) and held up
--     (gPlayerState.field_0x14).  Type2 >= $80: the rail is
--     gRoomVars.entityRails[type2 & 7] = gLilypadRails[..] (a fused Kinstone's
--     world event type 11, kinstone.c sub_0801876C).
--   * PINWHEEL $BE (pinwheel.c): flag = gPinwheelFlags[type2] (local); set ->
--     action 2 (animation 0 runs), else action 1 (still) until it is set
--     (CreateDeathFx then).
--   * WIND_TRIBE_FLAG $94: collision layer 2, flipX for type != 0,
--     animation 0 running; a frame duration of $FF gets (rand & $F) + $10.
--   * HOUSE_SIGN_MANAGER $13 (houseSignManager.c): HOUSE_SIGN objects $1C
--     (type, frame, layer 2) at the table's positions (gUnk_08108530 in the
--     festival town $15, else gUnk_081084C8), made while their 16x16 rect is
--     on screen, deleted off screen.
--   * HYRULE_TOWN_TILESET_MANAGER $12 / MINISH_VILLAGE_MANAGER $07: the
--     graphics swaps are Field.updateTileSwap (round 14 / 15, ExtractR
--     tileSwaps); the managers are only claimed here.
-- SIMPLIFIED: house signs are made for every table row at once (they are
--   static pictures; the cartridge only saves OAM by culling); the pinwheel's
--   gUnk_020342F8 bit check (entity health) is not modelled (health 0).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local RT = require("src.zelda.tmc.RomTables")

local M = {}
M.GIANT_BOOK_LADDER, M.HOUSE_DOOR_INT, M.LILYPAD_SMALL, M.PINWHEEL, M.WIND_TRIBE_FLAG, M.HOUSE_SIGN =
  0x46, 0x5D, 0x73, 0xBE, 0x94, 0x1C
M.MGR_MINISH_VILLAGE, M.MGR_TOWN_TILESET, M.MGR_HOUSE_SIGN = 0x07, 0x12, 0x13
M.SFX_111 = 0x111
local BOOK_DEFS = RT.t("Objects37.BOOK_DEFS")           -- spriteDefs
local DOOR_FRAMES = RT.t("Objects37.DOOR_FRAMES")       -- HouseDoorInteriorFrameIndices
local DOOR_DIRS = RT.t("Objects37.DOOR_DIRS")           -- gUnk_081227CC
local DOOR_HB = RT.t("Objects37.DOOR_HB")               -- HouseDoorInteriorHitbox
local LILY_SCALE = RT.t("Objects37.LILY_SCALE")         -- gUnk_08123318
local PINWHEEL_FLAGS = RT.t("Objects37.PINWHEEL_FLAGS") -- gPinwheelFlags
local SIGNS = RT.t("Objects37.SIGNS")                   -- gUnk_081084C8
local SIGNS_FESTIVAL = RT.t("Objects37.SIGNS_FESTIVAL") -- gUnk_08108530
local LILY_RAILS = RT.t("Objects37.LILY_RAILS")         -- gLilypadRails
M.LILY_RAILS = LILY_RAILS
M.WE11_LIST = 0x080FED58 -- gUnk_080FED58: the type-11 world events' lily pads
M.BOOK_DEFS, M.DOOR_FRAMES, M.DOOR_DIRS, M.DOOR_HB, M.LILY_SCALE, M.PINWHEEL_FLAGS, M.SIGNS, M.SIGNS_FESTIVAL =
  BOOK_DEFS, DOOR_FRAMES, DOOR_DIRS, DOOR_HB, LILY_SCALE, PINWHEEL_FLAGS, SIGNS, SIGNS_FESTIVAL
local SP108, SP109, SP114, SP142, SP143 = 0x406C, 0x406D, 0x4072, 0x408E, 0x408F
-- the input bit -> key (gPlayerState.playerInput.heldInput: $10 right, $20 left, $40 up, $80 down -- as
-- KEY bits << 0; gUnk_081227CC uses $400 / $100 / $800 / $200, the INPUT_ bits of the d-pad)
local KEY_OF = { [0x100] = "right", [0x200] = "left", [0x400] = "up", [0x800] = "down" }

local function rnd(f)
  local D = require("src.zelda.tmc.Drops")
  return D.random(D.rngOf(f))
end

local function dress(f, e, anim)
  local O = f:objects()
  local def = O and O:def(e.id, e.form or 0)
  if def then O:dress(e, def, anim or 0); e.objAnim = anim or 0 end
  return def ~= nil
end

local function setTile(f, layer, tx, ty, t)
  local r = f.room
  if tx >= 0 and ty >= 0 and tx < r.tw and ty < r.th then r:setTile(layer, tx, ty, t) end
end

-- GiantBookLadder_OnEnterRoom
function M.bookTiles(f, e)
  local tx, ty = math.floor(e.x / 16), math.floor(e.y / 16)
  local L = 1
  local t = e.form or 0
  local rx, ry, rows
  if t == 0 or t == 2 then
    rx, ry = tx - 1, ty - 4
    setTile(f, L, tx - 1, ty - 4, SP143); setTile(f, L, tx, ty - 4, SP143)
    setTile(f, L, tx - 2, ty - 4, SP108); setTile(f, L, tx + 1, ty - 4, SP109)
    rows = 6
    if t ~= 0 then
      rows = 4
      for _, o in ipairs({ { -1, 1 }, { 0, 1 }, { -1, 2 }, { 0, 2 } }) do setTile(f, L, tx + o[1], ty + o[2], SP114) end
    end
  elseif t == 1 then
    rx, ry = tx - 1, ty
    setTile(f, L, tx - 1, ty, SP142); setTile(f, L, tx, ty, SP142)
    rows = 2
  else
    return
  end
  for _ = 1, rows do
    ry = ry + 1
    setTile(f, L, rx, ry, SP142); setTile(f, L, rx + 1, ry, SP142)
  end
end

-- sub_0800445C with the object's own hitbox (Push34.out reads the
-- definition's)
function M.pushOut(f, e, eb)
  local P = require("src.zelda.tmc.Push34")
  local HB = require("src.zelda.tmc.Hitboxes")
  local p = f.player
  if not p or not HB.data(f) then return false end
  if P.BUSY[p.state or "normal"] or p.portalMode or p.onPortal or (p.z or 0) > 0 or p.hidden or p.climbing then return false end
  local pb = HB.player(f, p)
  if not pb then return false end
  local mx, my = P.calc(p.x, p.y, pb, e.x, e.y, eb)
  if not mx then return false end
  if p.moveBy then p:moveBy(mx, my) else p.x, p.y = p.x + mx, p.y + my end
  return true
end

-- HOUSE_DOOR_INT: Link pushes into it (GetAnimationStateInRectRadius >= 0,
-- facing it, holding the key)
local function doorUpdate(d, e, input)
  local f = d.field
  if e.doorFlags ~= 0 and d:check(e.doorFlags) then
    e.deleted = true
    f:sound(M.SFX_111)
    return
  end
  local p = f.player
  local touching = M.pushOut(f, e, DOOR_HB)
  local dd = DOOR_DIRS[e.type2 or 0]
  if touching and (e.unk7d or 0) == 0 and dd then
    local near = math.abs(math.floor(p.x) - math.floor(e.x)) <= dd.x and math.abs(math.floor(p.y) - math.floor(e.y)) <= dd.y
    local key = KEY_OF[dd.keys]
    local held = key and input and input.down and input.down(key)
    if near and dd.state == p.animationState and held then e.timer = e.timer - 1 end
  else
    e.timer = 8
  end
  if e.timer <= 0 then
    e.deleted = true
    f:sound(M.SFX_111)
    require("src.zelda.tmc.HouseDoor").walkIn(f, p, 8) -- sub_08078AC0(8, 0, 0)
  end
end

local function lilyOn(f, e) -- CheckMovePlayer
  local p = f.player
  if not p.minish then return false end
  if math.abs(math.floor(p.x) - math.floor(e.x)) > 8 or math.abs(math.floor(p.y) - math.floor(e.y)) > 8 then return false end
  if not require("src.zelda.tmc.FoWObjects").playerCanBeMoved(p) then return false end
  e.field14 = true
  return (p.z or 0) == 0
end

local function lilyUpdate(d, e)
  local f = d.field
  local FW = require("src.zelda.tmc.FoWObjects")
  e.field14 = nil
  FW.syncPlayer(f, e, lilyOn(f, e))
  e.timer = e.timer - 1
  if e.timer <= 0 then
    e.timer = 90
    e.staticFrame = band((e.staticFrame or 0) + 1, 3)
  end
  e.subtimer = band((e.subtimer or 0) + 1, 0xFF)
  local s = LILY_SCALE[band(rshift(e.subtimer, 5), 7)] or 0x100
  e.affine = { s = 0x100 / s, r = 0 }
  e.unk70 = band((e.unk70 or 0) - 1, 0xFFFF)
  if e.unk70 == 0 then FW.railNext(f, e) end
end

-- field_0x14 from a small lily pad this frame (Dungeon:checkFall)
function M.supports(f)
  local d = f and f._dungeon
  if not d then return false end
  for _, e in ipairs(d.objs or {}) do
    if e.lily37 and not e.deleted and e.field14 then return true end
  end
  return false
end

function M.spawnObject(d, e)
  local f = d.field
  local id = e.id
  if id == M.GIANT_BOOK_LADDER then
    dress(f, e, 0)
    local def = BOOK_DEFS[e.form or 0] or BOOK_DEFS[0]
    e.hidden = (e.type2 or 0) ~= 0
    e.staticFrame, e.layer = e.form or 0, 1
    e.oamPrio, e.spritePriority = def.prio, def.sprio
    M.bookTiles(f, e)
    return e
  elseif id == M.HOUSE_DOOR_INT then
    e.doorFlags = e.flag or 0 -- +$86: paramC's high half
    if e.doorFlags ~= 0 and d:check(e.doorFlags) then e.deleted = true return e end
    dress(f, e, 0)
    e.unk7d = e.timer0 or 0
    e.spritePriority, e.timer = 7, 8
    local fi = DOOR_FRAMES[e.form or 0]
    if fi and fi.frame == 0xFF then e.staticFrame = e.type2 or 0
    elseif fi then e.staticFrame, e.type2 = fi.frame, fi.type2 end
    e.extUpdate = doorUpdate
    d:track(e)
    return e
  elseif id == M.LILYPAD_SMALL then
    dress(f, e, 0)
    local r = rnd(f) * 65536 + rnd(f)
    e.action, e.timer = 1, 90
    e.subtimer = band(r, 0xFF)
    e.staticFrame = band(rshift(r, 16), 3)
    e.spritePriority = 7
    e.lily37 = true
    e.speed = e.speed or 0
    local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
    local t2 = e.type2 or 0
    if t2 >= 0x80 then e.child = LILY_RAILS[band(t2, 7)] -- gRoomVars.entityRails (a fused type-11 event)
    else e.child = props and props[t2] or nil end -- GetCurrentRoomProperty(type2)
    e.direction = 0xFF
    require("src.zelda.tmc.FoWObjects").railNext(f, e)
    e.extUpdate = function(dd, me) lilyUpdate(dd, me) end
    d:track(e)
    return e
  elseif id == M.PINWHEEL then
    dress(f, e, 0)
    e.pinFlag = PINWHEEL_FLAGS[e.type2 or 0] or 0
    e.spritePriority = 7
    e.action = f:flag("local", e.pinFlag) and 2 or 1
    e.extUpdate = function(dd, me)
      if me.action == 1 then
        if f:flag("local", me.pinFlag) then
          me.action = 2
          if f.addFx then f:addFx(me.x, me.y, 0x0F, 0x02) end -- CreateDeathFx
        end
      elseif me.anim then
        me.anim:update(1)
      end
    end
    d:track(e)
    return e
  elseif id == M.WIND_TRIBE_FLAG then
    dress(f, e, 0)
    e.layer = 2
    e.flipX = (e.form or 0) ~= 0
    e.extUpdate = function(_, me) if me.anim then me.anim:update(1) end end
    d:track(e)
    return e
  end
  return nil
end

-- kinstone.c sub_0801876C WORLD_EVENT_TYPE_11, fused: LoadRoomEntity(
-- gUnk_080FED58[entity]) and entityRails[entity] = gLilypadRails[entity]
-- (Kinstone:applyWorldEvents)
function M.lilyEvent(f, we)
  local l = f:entityListAt(M.WE11_LIST + 16 * (we.entity or 0))
  return l and l[1] and f:spawn(l[1])
end

function M.spawnManager(d, m)
  if m.id == M.MGR_TOWN_TILESET or (m.id == M.MGR_MINISH_VILLAGE) then
    return true -- Field.updateTileSwap
  end
  if m.id ~= M.MGR_HOUSE_SIGN then return nil end
  local f = d.field
  local list = f.room.area == 0x15 and SIGNS_FESTIVAL or SIGNS
  local n = 0
  for i = 0, 31 do
    local s = list[i]
    if not s or s.x == 0 then break end
    local e = { kind = 6, id = M.HOUSE_SIGN, form = s.type, type2 = i, x = s.x, y = s.y, z = 0, animationState = 0,
                field80 = 0, field82 = 0, interactType = 0, layer = s.layer }
    if dress(f, e, 0) then
      e.staticFrame = s.frame
      f.entities[#f.entities + 1] = e
      n = n + 1
    end
  end
  return true
end

return M
