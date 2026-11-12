-- Round 26 (team B): Dark Hyrule Castle objects, managers and room code,
-- from the decomp.  R26.lua dispatches here (spawnObject / spawnManager /
-- roomInit).
--
-- GURUGURU_BAR $98 (object/guruguruBar.c + projectile/guruguruBarProjectile.c):
--   Init: timer (paramB byte 1, at most 8) GURUGURU_BAR_PROJECTILEs, each
--   timer 14 + 12 * i (its radius), unk_76 = unk_7e (paramB byte 2) << 8,
--   animationState = unk_7e << 6; type != 0 rides the rail of room property
--   [type] (UpdateRailMovement).  Action1: unk_76 += type2 (the speed),
--   animationState = unk_76 >> 2; the rail's LinearMoveUpdate.  Each
--   fireball: its parent's position + gSineTable[state] * radius, -
--   gSineTable[state + $40] * radius, animation 0.  Hit type $73 against Link
--   is matrix handler 11 (CollisionFire): 4 health, 12 frames at $180,
--   iframes 30.
-- JAIL_BARS $B1 (object/jailBars.c): its flag (+$86) clear -> tiles
--   gUnk_08124960 (six SPECIAL_TILE_35 from -3 to +2), else open (animation
--   1, gUnk_0812497A: SPECIAL_TILE_136 / 135 in the middle); the flag set ->
--   SFX_10B, the open tiles, animation 0 to its end, then 1.
-- METAL_DOOR $B0 (object/metalDoor.c): flag1 (+$84) set -> gone.  Hidden
--   until Link is above y - 8 (sub_08083734 case 2), then it drops in from
--   $24 below at $300 north for 12 frames (SPECIAL_TILE_34 on its three
--   tiles, two FX_DASH, SFX_10B); flag2 (+$86) set -> it slides away south
--   (the tiles back, SFX_10B, 12 frames) and is gone.  Drawn flipped (flipY).
-- OBJECT_BLOCKING_STAIRS $5F (object/objectBlockingStairs.c; type 1 = the
--   throne in $88:$1F): gUnk_08122898 flags (bank 10 $6F / $70) put it 32 px
--   left / right (action 4, tiles gUnk_08122874 / 86); else locked until its
--   flag (+$86, the Dark Nut's) -- then it shakes $20 frames
--   (sub_080932A8) -- and becomes pushable: the 3x3 tiles gUnk_08122850, the
--   push tiles SPECIAL_TILE_44 / 61 / 45 on the side Link stands (switching
--   when he crosses 5 px); Link pushing a SPECIAL_TILE_43..45 sideways
--   (beanstalkSubtask.c: the tile beyond free) turns it into 48 + (state & 4)
--   / 4, PLAYER_PUSH $10 frames; the throne sees 48 / 49 beside it -> slides
--   64 frames at $80 the way Link faces (SFX_10F, FX_DASH every 4 frames),
--   then its bank flag (sub_08093308), the moved tiles, SFX_SECRET.  R grabs
--   it (carryFlags 1): pulling slides it toward Link the same way.
-- ANGRY_STATUE_MANAGER $2B (manager/angryStatueManager.c) + ANGRY_STATUE
--   $A0 (object/angryStatue.c) + CANNONBALL_PROJECTILE $1B
--   (projectile/cannonballProjectile.c): its flag (+$3E) set -> nothing.
--   Four statues from room property [type] ({x, y, type} u16 each; type2 =
--   0-3), SPECIAL_TILE_34 under each.  Every 180 frames (first after 60) the
--   statues fire (animation type + 4; frame bit 0: a cannonball of their
--   type at gUnk_08124684, SFX_EC).  A cannonball flies (type << 3, z -4,
--   ProcessMovement3; a wall -> FX_DEATH); the sword sends it back (contact
--   with iframes < -4: knockback direction, snapped to the way home within
--   +-1, $280); flying back it knocks out the statue it meets (action 3: 30
--   frames hidden, FX_WHITE_ROCK, then 15 blinking) -- all four knocked out at
--   once (their bits $F) -> SFX_SECRET, 8 frames, the flag, the statues gone
--   (the tiles back).
-- TILE_PUZZLE_MANAGER $30 (manager/tilePuzzleManager.c): stepping on a blue
--   tile (type $318) makes it red ($317, SFX_6B), on a red one fails
--   (SFX_MENU_ERROR); all `timer` tiles -> 64 frames, the flag at 32, then
--   SFX_SECRET; its reset flag (+$3E) clears itself and restores the
--   width x height tiles.
-- ROOM CODE (src/roomInit.c, AREA_DARK_HYRULE_CASTLE / _OUTSIDE / SANCTUARY):
--   sub_unk3 + sub_StateChange for 1FEntrance, 3FTripleDarknut, the four
--   2F Dark Nut rooms (local $86 and not their done flag), B1Entrance,
--   B1Left, B1Map, B2Prison, Outside ZeldaStatuePlatform / Garden, the
--   Sanctuary's Hall / Main / StainedGlass: LoadRoomEntityList, sub_0807BB98
--   (SPECIAL_TILE_114 rectangles), sub_0804D7EC, queued BGM; a property set
--   to 0 by sub_unk3 removes what that base list spawned.
-- FOUR SWORD CLONES (owned by another team): f.playerClones (a list of
--   entities with x, y) stand on buttons (Dungeon:somethingOn ->
--   DHCObjects.cloneOn); LightableSwitch already takes any entity with
--   hitW / hitList (a clone's sword box).
-- SIMPLIFIED: the fireballs do not set Link burning (LINK_FIRE); the
--   statue's and the metal door's ROM hitboxes are read (ROM_RANGES) or a
--   16 x 16 box; the cannonball's pit / water / lava check (sub_080AB5F4) is
--   not ported; the throne's pull uses StatuePull's grab (its 8-frame pull
--   count is StatuePull's keyframe test); PLAYER_PUSH is a $10-frame walk.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local O = {}
O.GURUGURU_BAR, O.JAIL_BARS, O.METAL_DOOR, O.BLOCKING_STAIRS, O.ANGRY_STATUE = 0x98, 0xB1, 0xB0, 0x5F, 0xA0
O.ANGRY_STATUE_MANAGER, O.TILE_PUZZLE_MANAGER = 0x2B, 0x30
local GURUGURU_PROJ, CANNONBALL = 0x17, 0x1B
local SFX_10B, SFX_10F, SFX_SECRET, SFX_6B, SFX_MENU_ERROR, SFX_EC = 0x10B, 0x10F, 0x72, 0x6B, 0x6D, 0xEC
local SPECIAL_FX, FX_DEATH, FX_DASH, FX_WHITE_ROCK = 0x0F, 2, 17, 69
local SP34, SP35, SP114 = 0x4022, 0x4023, 0x4072
local TT_RED, TT_BLUE = 0x317, 0x318

O.ROM_RANGES = {
  statueHitbox = { 0x080FD178, 0x080FD180 }, -- gUnk_080FD178 (hitbox.h, data): the angry statue's Hitbox
  pushProbe = { 0x080B4468, 0x080B4478 },    -- gUnk_080B4468 (data_080B4410/gUnk_080B4468.bin): s16 {x, y} by Link's state, UpdatePlayerCollision's tile
}

O.JAIL_SHUT = { 0x4023, -3, 0x4023, -2, 0x4023, -1, 0x4023, 0, 0x4023, 1, 0x4023, 2 } -- gUnk_08124960
O.JAIL_OPEN = { 0x4023, -3, 0x4023, -2, 0x4088, -1, 0x4087, 0, 0x4023, 1, 0x4023, 2 } -- gUnk_0812497A
O.STAIRS_TILES = { -- gUnk_08122850 / 62 / 74 / 86 (SPECIAL_TILE_n = $4000 + n)
  [0] = { 0x4027, 0x4023, 0x4028, 0x402C, 0x402B, 0x402D, 0x4029, 0x4026, 0x402A },
  { 0x4027, 0x4023, 0x4028, 0x4024, 0x4022, 0x4025, 0x4029, 0x4026, 0x402A },
  { 0x4027, 0x4023, 0x4023, 0x4024, 0x4022, 0x4022, 0x4029, 0x4026, 0x4026 },
  { 0x4023, 0x4023, 0x4028, 0x4022, 0x4022, 0x4025, 0x4026, 0x4026, 0x402A },
}
O.STAIRS_FLAGS = { [0] = { 0x200, 0xA1, 0xA2 }, { 0x8C0, 0x6F, 0x70 } } -- gUnk_08122898 {bank, left, right}
O.STATUE_SHOT = { [0] = { 0, 12 }, { 12, 2 }, { 0, 12 }, { -12, 2 } } -- gUnk_08124684

local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end -- gSineTable ($100 = 1)
O.SIN = SIN

local function H() return require("src.zelda.tmc.EnemyDHC").h end
local function fx(f, x, y, t) if f.addFx then f:addFx(x, y, SPECIAL_FX, t) end end
local function L(e) return e.layer == 2 and 2 or 1 end
local function tileXY(pos) return pos % 64, math.floor(pos / 64) end
local function getT(f, layer, pos)
  local r = f.room
  local tx, ty = tileXY(pos)
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return nil end
  return r.maps[layer == 2 and "top" or "bottom"][ty * r.tw + tx]
end
local function setT(f, layer, pos, mt)
  local r = f.room
  local tx, ty = tileXY(pos)
  if not mt or tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return end
  r:setTile(layer, tx, ty, mt)
end
local function ttype(f, layer, pos)
  local tx, ty = tileXY(pos)
  return f.room:tileType(layer, tx, ty)
end
local function tileOf(x, y) return math.floor(x / 16) + math.floor(y / 16) * 64 end
O._tile = { get = getT, set = setT, type = ttype }

-- SetTile with RestorePrevTileEntity: the old metatile kept per entity
local function putTile(f, e, layer, pos, mt)
  e.prev = e.prev or {}
  local k = layer * 65536 + pos
  if e.prev[k] == nil then e.prev[k] = getT(f, layer, pos) or false end
  setT(f, layer, pos, mt)
end
local function restoreTile(f, e, layer, pos)
  local k = layer * 65536 + pos
  local v = e.prev and e.prev[k]
  if v then setT(f, layer, pos, v) end
  if e.prev then e.prev[k] = nil end
end

local function dressObj(d, e, id, form)
  local O2 = d.field:objects()
  local def = O2:def(id, form or 0)
  if def then O2:dress(e, def, 0) end
  return def
end
local function anim(d, e, a)
  e.objAnim, e.animIndex = a, a
  if e.anim and e.sprite then e.anim:set(d.field.assets:sprite(e.sprite), a, true) end
  e.fkey = nil
end
local function linear(e, dir, spd) H().linear(e, dir, spd) end

-- ===========================================================================
-- GURUGURU_BAR
-- ===========================================================================
local function fireTouch(d, b)
  local f = d.field
  local h = H()
  local p = f.player
  if not h.canTouch(f, b) or (p.invuln or 0) > 0 or p.minish then return end
  if not h.touches(f, b, b.hitbox) then return end
  -- CollisionFire: 4 health, 12 frames at $180, iframes 30
  if p:hurt(4, b.x, b.y) then
    p.invuln, p.timer = 30, 12
    local dx, dy = p.x - b.x, p.y - b.y
    local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
    p.kbx, p.kby = dx / dd * 1.5, dy / dd * 1.5
  end
end
local function barUpdate(d, e)
  local f = d.field
  e.u76 = band(e.u76 + (e.type2 or 0), 0xFFFF)
  e.animationState = band(rshift(e.u76, 2), 0xFF)
  if (e.form or 0) ~= 0 then
    if band(e.direction or 0xFF, 0x80) == 0 then linear(e, e.direction, e.speed) end
    e.u74 = (e.u74 or 1) - 1
    if e.u74 <= 0 then e.u76r = nil; O.rail(f, e) end
  end
  for _, b in ipairs(e.balls) do -- sub_080AABB0
    local s = e.animationState
    b.x = e.x + SIN[s] * b.radius / 256
    b.y = e.y - SIN[s + 0x40] * b.radius / 256
    b.layer = e.layer
    if b.anim then b.anim:update(1) end
    fireTouch(d, b)
  end
end
function O.rail(f, e) -- UpdateRailMovement with unk_74 as the counter
  local C = require("src.zelda.tmc.CoFObjects")
  local saved = e.u76
  C.railNext(f, e)
  e.u74 = e.u76
  e.u76 = saved
end
function O.spawnBar(d, e)
  local f = d.field
  local raw = e.data and e.data.paramB or 0
  local n = math.min(8, band(rshift(raw, 8), 0xFF))
  local q = band(rshift(raw, 16), 0xFF) -- unk_7e
  e.hidden = true
  e.balls = {}
  local def = H().projDef(f, GURUGURU_PROJ, 0)
  for i = 0, n - 1 do
    local b = { kind = 4, id = GURUGURU_PROJ, x = e.x, y = e.y, z = 0, layer = e.layer, radius = 14 + 12 * i,
                hitbox = def and def.hitbox or { x = 0, y = 0, w = 4, h = 4 }, hitType = def and def.damageType or 0x73,
                animationState = 0, field82 = 0, interactType = 0, fireball = true }
    if def then
      d:dress(b, def.sprite, def.palette, require("src.zelda.tmc.Assets").gfxSource("enemy", def.gfx), 0)
      anim(d, b, 0)
    end
    e.balls[#e.balls + 1] = b
    f.entities[#f.entities + 1] = b
  end
  e.u76 = lshift(q, 8)
  e.animationState = band(lshift(q, 6), 0xFF)
  e.spritePriority = 0
  if (e.form or 0) ~= 0 then
    local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
    e.railPtr = props and props[e.form]
    e.direction, e.speed = 0xFF, 0
    O.rail(f, e)
  end
  e.guruguru = true
  e.extUpdate = function(dd, me) barUpdate(dd, me) end
  d:track(e)
  return e
end

-- ===========================================================================
-- JAIL_BARS
-- ===========================================================================
local function jailTiles(d, e, open)
  local f = d.field
  local list = open and O.JAIL_OPEN or O.JAIL_SHUT
  local base = tileOf(e.x, e.y)
  for i = 1, #list, 2 do setT(f, 1, base + list[i + 1], list[i]) end
end
function O.spawnJail(d, e)
  dressObj(d, e, O.JAIL_BARS, 0)
  e.layer = 1
  if not d:check(e.flag) then e.action = 1; jailTiles(d, e, false); anim(d, e, 0); e.staticFrame = nil
  else e.action = 3; anim(d, e, 1); jailTiles(d, e, true) end
  e.extUpdate = function(dd, me)
    if me.action == 1 then
      if dd:check(me.flag) then me.action = 2; jailTiles(dd, me, true); dd.field:sound(SFX_10B) end
    elseif me.action == 2 then
      me.anim:update(1)
      if H().done(me) then me.action = 3; anim(dd, me, 1) end
    end
  end
  d:track(e)
  return e
end

-- ===========================================================================
-- METAL_DOOR
-- ===========================================================================
local function doorTiles(d, e, on)
  local f = d.field
  for i = -1, 1 do
    if on then putTile(f, e, L(e), e.u74 + i, SP34) else restoreTile(f, e, L(e), e.u74 + i) end
  end
end
function O.spawnMetalDoor(d, e)
  if e.flags ~= 0xFFFF and d:check(e.flags) then return nil end
  dressObj(d, e, O.METAL_DOOR, 0)
  e.action, e.speed = 1, 0x300
  e.hidden, e.staticFrame, e.flipY = true, 0, true
  e.spritePriority = 5
  e.u70, e.u72, e.u74 = e.x, e.y, tileOf(e.x, e.y)
  e.extUpdate = function(dd, me)
    local f = dd.field
    local p = f.player
    if me.action == 1 then
      if math.floor(p.y) - (me.u72 - 8) < 0 then -- sub_08083734(this, 2)
        me.action, me.timer, me.hidden, me.direction = 2, 12, false, 0
        me.y = me.y + 0x24
        doorTiles(dd, me, true)
      end
    elseif me.action == 2 then
      linear(me, me.direction, me.speed)
      me.timer = me.timer - 1
      if me.timer <= 0 then
        me.action, me.x, me.y = 3, me.u70, me.u72
        fx(f, me.x + 12, me.y - 12, FX_DASH); fx(f, me.x - 12, me.y - 12, FX_DASH)
        f:sound(SFX_10B)
      end
    elseif me.action == 3 then
      if dd:check(me.flag) then
        me.action, me.timer, me.direction = 4, 12, 0x10
        me.y = me.y + 2
        doorTiles(dd, me, false)
        f:sound(SFX_10B)
      end
    elseif me.action == 4 then
      linear(me, me.direction, me.speed)
      me.timer = me.timer - 1
      if me.timer <= 0 then me.deleted = true end
    end
  end
  d:track(e)
  return e
end

-- ===========================================================================
-- OBJECT_BLOCKING_STAIRS (the throne)
-- ===========================================================================
local function stairsTiles(d, e, mode) -- sub_080931A4
  local f = d.field
  e.tilePos = tileOf(e.x, e.y)
  local t = O.STAIRS_TILES[mode] or O.STAIRS_TILES[0]
  local base, v = e.tilePos - 0x40, 0
  for i = 0, 8 do
    putTile(f, e, L(e), base + v + i - 1, t[i + 1])
    if i == 2 then v = 0x3D elseif i == 5 then v = 0x7A end
  end
end
local function stairsRestore(d, e) -- sub_08093248
  local f = d.field
  local base, v = e.tilePos - 0x40, 0
  for i = 0, 8 do
    restoreTile(f, e, L(e), base + v + i - 1)
    if i == 2 then v = 0x3D elseif i == 5 then v = 0x7A end
  end
end
local function stairsWhere(f, ty) -- sub_080932D8
  local s = O.STAIRS_FLAGS[ty] or O.STAIRS_FLAGS[0]
  if f:flag("bank", s[2], s[1]) then return 1 end
  if f:flag("bank", s[3], s[1]) then return 2 end
  return 0
end
local function stairsStart(d, e, dir)
  e.action, e.direction, e.speed, e.timer = 3, dir, 0x80, 64
  d.field:sound(SFX_10F)
  stairsRestore(d, e)
end
local function stairsStop(d, e) -- sub_08093334
  local f = d.field
  e.action = 4
  local u = band(e.direction, 0x10) ~= 0 and 1 or 2
  e.x = math.floor(e.x + 0.5)
  stairsTiles(d, e, u + 1)
  local s = O.STAIRS_FLAGS[e.form or 0] or O.STAIRS_FLAGS[0]
  f:setFlag("bank", u == 1 and s[2] or s[3], true, s[1])
  f:sound(SFX_SECRET)
end
-- Link's push against SPECIAL_TILE_43..45 (beanstalkSubtask.c, PLAYER_PUSH)
local DV = { [2] = { 1, 0 }, [6] = { -1, 0 } }
function O.tryStairsPush(f, p)
  if p.minish or p.state ~= "normal" or not p.pushFrame or not p.probe then return false end
  local v = DV[p.animationState]
  if not v then return false end -- sub_0801A370: sideways only
  -- the tile UpdatePlayerCollision tests: Link + gUnk_080B4468[state & 6] (ROM)
  local px, py
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "pushProbe")
  if T then
    local st = band(p.animationState, 6)
    px, py = math.floor(p.x) + T.s16(0x080B4468 + 2 * st), math.floor(p.y) + T.s16(0x080B4468 + 2 * st + 2)
  else px, py = p:probe() end
  local tx, ty = math.floor(px / 16), math.floor(py / 16)
  local layer = p.layer or 1
  local tt = f.room:tileType(layer, tx, ty)
  if not (tt == 0x402B or tt == 0x402C or tt == 0x402D) then return false end
  -- sub_0801A370: the tile beyond (past a SPECIAL_TILE_43); 44..47 -> yes;
  -- else no act tile $52 / $26 / $27 / $29 / $74 and its collision 0 (or a
  -- half wall open on that side: 5 / $45 pushing right, $A / $44 left)
  local bx = tx + v[1]
  local bt = f.room:tileType(layer, bx, ty)
  local ok
  if bt == 0x402B then bx = bx + v[1]
  elseif bt and bt >= 0x402C and bt <= 0x402F then ok = true end
  if not ok then
    local r = f.room
    if bx < 0 or bx >= r.tw then return false end
    local t2 = r:tileType(layer, bx, ty)
    local act = t2 and t2 < 0x4000 and f.assets.actTile and f.assets.actTile[t2] or 0
    if act == 0x52 or act == 0x26 or act == 0x27 or act == 0x29 or act == 0x74 then return false end
    local c = r.coll and r.coll[layer == 2 and 2 or 1]
    local cv = c and c[ty * r.tw + bx] or 0xFF
    ok = cv == 0 or ((cv == 5 or cv == 0x45) and v[1] == 1) or ((cv == 0xA or cv == 0x44) and v[1] == -1)
  end
  if not ok then return false end
  f.room:setTile(layer, tx, ty, 0x4030 + rshift(band(p.animationState, 4), 2))
  p.state = "ext"
  p.x, p.y = math.floor(p.x), math.floor(p.y)
  local left = 0x10
  p.extUpdate = function(pp)
    pp.anim:update(1)
    left = left - 1
    pp:moveBy(v[1] * 0.5, 0)
    if left <= 0 then pp.extUpdate = nil; pp.state = "normal" end
  end
  return true
end
local function stairsUpdate(d, e, input)
  local f = d.field
  local p = f.player
  if e.action == 1 then
    local xDist = math.floor(p.x) - math.floor(e.x)
    if e.flag and e.flag ~= 0 then
      if not d:check(e.flag) then return end
      if e.u7a ~= 0 then -- sub_080932A8
        e.u7a = e.u7a - 1
        local k = band(e.u7a, 3)
        e.spriteOX = k == 1 and 1 or (k == 3 and -1 or 0)
        return
      end
    end
    if band(e.u7b, 0x3F) == 0 then
      e.u7b = bor(e.u7b, 0xF)
      stairsTiles(d, e, 0)
      if xDist < 0 then e.u7b = bor(e.u7b, 0x40) end
    end
    local side = band(e.u7b, 0x40) ~= 0 and e.tilePos - 1 or e.tilePos + 1
    local tt = ttype(f, L(e), side)
    if tt == 0x4030 or tt == 0x4031 then
      stairsStart(d, e, lshift(p.animationState or 0, 2))
      return
    end
    O.tryStairsPush(f, p)
    if band(p.animationState or 0, 2) == 0 then return end
    -- RegisterCarryEntity: R grabs, pulling slides it (StatuePull)
    e.tx, e.ty = math.floor(e.x / 16), math.floor(e.y / 16)
    if e.moving and e.moving > 0 then stairsStart(d, e, lshift(bxor(p.animationState, 4), 2)); e.moving = nil return end
    require("src.zelda.tmc.StatuePull").update(d, e, input)
    if band(e.u7b, 0x80) ~= 0 then
      e.u7b = band(e.u7b, 0x7F)
      if band(e.u7b, 0x40) ~= 0 then setT(f, L(e), e.tilePos - 1, 0x402C); setT(f, L(e), e.tilePos + 1, 0x403D)
      else setT(f, L(e), e.tilePos - 1, 0x403D); setT(f, L(e), e.tilePos + 1, 0x402D) end
    elseif band(e.u7b, 0x40) ~= 0 then
      if xDist >= 5 then
        e.u7b = band(e.u7b, bit.bnot(0xC0))
        setT(f, L(e), e.tilePos - 1, 0x403D); setT(f, L(e), e.tilePos + 1, 0x402D)
      end
    elseif -xDist > 4 then
      e.u7b = bor(e.u7b, 0x40)
      setT(f, L(e), e.tilePos - 1, 0x402C); setT(f, L(e), e.tilePos + 1, 0x403D)
    end
  elseif e.action == 3 then
    require("src.zelda.tmc.Hitboxes").pushOut(f, e, { x = 0, y = 0, w = 24, h = 20 })
    linear(e, e.direction, e.speed)
    e.timer = e.timer - 1
    if band(e.timer, 3) == 0 then -- sub_08093364
      local dx = band(e.direction, 0x10) ~= 0 and 0x12 or -0x12
      fx(f, e.x + dx, e.y + (band(e.timer, 8) ~= 0 and 8 or -8), FX_DASH)
    end
    if e.timer <= 0 then stairsStop(d, e) end
  end
end
function O.spawnStairs(d, e)
  local f = d.field
  dressObj(d, e, O.BLOCKING_STAIRS, e.form or 0)
  e.staticFrame = 0
  local w = stairsWhere(f, e.form or 0)
  local mode
  if w == 1 then e.action, e.x, mode = 4, e.x - 0x20, 2
  elseif w == 2 then e.action, e.x, mode = 4, e.x + 0x20, 3
  else
    e.action, e.speed, e.carryFlags, e.timer, e.subtimer = 1, 0x80, 1, 0, 0
    e.u7a, e.u7b = 0x20, 0x80
    mode = 0
    if e.flag and e.flag ~= 0 and not d:check(e.flag) then mode = 1 end
  end
  stairsTiles(d, e, mode)
  e.statueLike = true
  e.extUpdate = function(dd, me, input) stairsUpdate(dd, me, input) end
  d:track(e)
  return e
end

-- ===========================================================================
-- ANGRY_STATUE_MANAGER / ANGRY_STATUE / CANNONBALL_PROJECTILE
-- ===========================================================================
local function statueBox(f)
  local T = require("src.zelda.tmc.ExtractR26").tables(f, "statueHitbox")
  if T then
    local a = 0x080FD178
    return { x = T.s8(a), y = T.s8(a + 1), w = T.u8(a + 6), h = T.u8(a + 7) }
  end
  return { x = 0, y = 0, w = 8, h = 8 }
end
local function overlap(a, ab, b, bb)
  return math.abs((a.x + ab.x) - (b.x + bb.x)) <= ab.w + bb.w and math.abs((a.y + ab.y) - (b.y + bb.y)) <= ab.h + bb.h
end
local function ballUpdate(d, c)
  local f = d.field
  local h = H()
  if c.deleted then return end
  c.anim:update(1)
  if c.action == 1 then
    if not h.pm0(f:enemies(), c, c.direction, c.speed) then fx(f, c.x, c.y, FX_DEATH); c.deleted = true return end
    -- the sword's contact: tgtIfr < -4 -> sent back (CannonballProjectile_OnCollision)
    local sb = f.swordBoxNow
    if sb and sb.t and sb.t >= (f.frame or 0) - 1 and sb.t ~= c.swordT
       and math.abs(sb.x - (c.x + c.hitbox.x)) < sb.w + c.hitbox.w and math.abs(sb.y - (c.y + c.hitbox.y)) < sb.h + c.hitbox.h then
      c.swordT = sb.t
      c.action = 2
      local p = f.player
      c.direction = h.dirTo(p.x, p.y, c.x, c.y)
      local home = lshift(bxor(c.form or 0, 2), 3)
      if band(c.direction - home + 1, 0x1F) < 3 then c.direction = home end
      c.speed = 0x280
      return
    end
    if h.canTouch(f, c) and (f.player.invuln or 0) == 0 and h.touches(f, c, c.hitbox) then
      if not f.player:blocksFrom(c.x, c.y) then h.hurtLink(f:enemies(), c, c.hitType) end
      fx(f, c.x, c.y, FX_DEATH); c.deleted = true
    end
  elseif c.action == 2 then
    local moved = h.pm0(f:enemies(), c, c.direction, c.speed)
    local m = c.parent
    for i = 0, 3 do -- sub_080AB634
      local s = m and m.statues[i]
      if s and not s.deleted and overlap(c, c.hitbox, s, s.hitbox) then
        if s.action < 3 then
          s.action, s.timer, s.hidden = 3, 30, true
          fx(f, s.x, s.y, FX_WHITE_ROCK)
        end
        c.deleted = true
        return
      end
    end
    if not moved then fx(f, c.x, c.y, FX_DEATH); c.deleted = true end
  end
end
local function fire(d, s)
  local f = d.field
  local def = H().projDef(f, CANNONBALL, s.form)
  local Anim = require("src.zelda.tmc.Anim")
  local o = O.STATUE_SHOT[s.form] or { 0, 0 }
  local c = { kind = 4, id = CANNONBALL, form = s.form, x = s.x + o[1], y = s.y + o[2], z = 4, layer = s.layer,
              action = 1, direction = lshift(s.form, 3), speed = def and def.speed or 0x200, parent = s.parent,
              hitbox = def and def.hitbox or { x = 0, y = 0, w = 6, h = 6 }, hitType = def and def.damageType or 158,
              animationState = 0, field82 = 0, interactType = 0, anim = Anim.new(), cannonball = true }
  if def then
    d:dress(c, def.sprite, def.palette, require("src.zelda.tmc.Assets").gfxSource("enemy", def.gfx), s.form)
    anim(d, c, s.form)
  end
  c.extUpdate = function(dd, me) ballUpdate(dd, me) end
  f.entities[#f.entities + 1] = c
  d:track(c)
  f:sound(SFX_EC)
end
local function statueUpdate(d, s)
  local f = d.field
  local m = s.parent
  if s.action == 1 then
    if m.subtimer == 1 then s.action = 2; anim(d, s, s.form + 4) end
  elseif s.action == 2 then
    s.anim:update(1)
    if band(H().fl(s), 1) ~= 0 then H().take(s, 1); fire(d, s)
    elseif H().done(s) then s.action = 1; anim(d, s, s.form) end
  elseif s.action == 3 then
    s.timer = s.timer - 1
    if s.timer <= 0 then s.action, s.timer = 4, 15; anim(d, s, s.form)
    else m.bits = bor(m.bits, lshift(1, s.type2)) end
  elseif s.action == 4 then
    s.hidden = not s.hidden
    s.timer = s.timer - 1
    if s.timer <= 0 then s.action, s.hidden = 1, false end
  end
end
function O.spawnStatueManager(d, m)
  local f = d.field
  if d:check(m.c1) and m.c1 ~= 0 then return true end
  local props = f.room.maps and f.room.maps.header and f.room.maps.header.props
  local addr = props and props[m.type]
  local rd = require("src.zelda.tmc.CoFObjects")._rd
  local Anim = require("src.zelda.tmc.Anim")
  local mg = { statues = {}, bits = 0, subtimer = 60, action = 1, flag = m.c1 }
  for i = 0, 3 do
    local x, y, ty = addr and rd.u16(f, addr + 6 * i), addr and rd.u16(f, addr + 6 * i + 2), addr and rd.u16(f, addr + 6 * i + 4)
    if x and y and ty then
      local s = { kind = 6, id = O.ANGRY_STATUE, form = ty, type2 = i, x = x, y = y, z = 0, layer = 1, parent = mg,
                  action = 1, timer = 0, animationState = 0, field82 = 0, interactType = 0, anim = Anim.new() }
      s.layer = require("src.zelda.tmc.Layers").resolve(f, s) or 1
      dressObj(d, s, O.ANGRY_STATUE, ty)
      s.hitbox = statueBox(f)
      putTile(f, s, L(s), tileOf(s.x, s.y), SP34)
      anim(d, s, ty)
      s.extUpdate = function(dd, me) if not me.deleted then statueUpdate(dd, me) end end
      f.entities[#f.entities + 1] = s
      d:track(s)
      mg.statues[i] = s
    end
  end
  require("src.zelda.tmc.R26").ticker(d, function(dd, t)
    if mg.action == 1 then
      mg.subtimer = mg.subtimer - 1
      if mg.subtimer == 0 then mg.subtimer = 180 end
      if mg.bits == 0xF then
        mg.action, mg.timer = 2, 8
        f:sound(SFX_SECRET)
        for i = 0, 3 do -- sub_0805D11C
          local s = mg.statues[i]
          if s then restoreTile(f, s, L(s), tileOf(s.x, s.y)); s.deleted = true; mg.statues[i] = nil end
        end
      end
      mg.bits = 0
    elseif mg.action == 2 then
      mg.timer = mg.timer - 1
      if mg.timer == 0 then dd:set(mg.flag); t.deleted = true end
    end
  end)
  O.lastStatueManager = mg
  return true
end

-- ===========================================================================
-- TILE_PUZZLE_MANAGER
-- ===========================================================================
function O.spawnTilePuzzle(d, m)
  local f = d.field
  local mg = { action = 0, timer = m.b1, layer = m.type2 == 2 and 2 or 1, width = band(m.b32, 0xFF),
               height = band(rshift(m.b32, 8), 0xFF), flagDone = m.c0, flagReset = m.c1 }
  mg.ownTile = band(rshift(m.x, 4), 0x3F) + lshift(band(rshift(m.y, 4), 0x3F), 6)
  mg.saved = {}
  for i = 0, mg.height - 1 do
    for j = 0, mg.width - 1 do
      local pos = mg.ownTile + lshift(i, 6) + j
      mg.saved[pos] = getT(f, mg.layer, pos)
    end
  end
  O.lastTilePuzzle = mg
  require("src.zelda.tmc.R26").ticker(d, function(dd) O.tilePuzzleStep(dd, mg) end)
  return true
end
function O.tilePuzzleStep(d, mg)
  local f = d.field
  local p = f.player
  local a = mg.action
  if a == 0 then
    mg.action, mg.subtimer = 1, mg.timer
    mg.prevTile = tileOf(p.x, p.y)
    return
  end
  if a == 1 then
    local cur = tileOf(p.x, p.y)
    if cur ~= mg.prevTile then
      mg.prevTile = cur
      local tt = ttype(f, mg.layer, cur)
      if tt == TT_RED then mg.action = 2; f:sound(SFX_MENU_ERROR)
      elseif tt == TT_BLUE then
        local tx, ty = tileXY(cur)
        f:objects():setTileType(mg.layer, tx, ty, TT_RED)
        f:sound(SFX_6B)
        mg.timer = mg.timer - 1
        if mg.timer == 0 then mg.action, mg.timer = 3, 64 end
      end
    end
  end
  if a == 1 or a == 2 then -- case 1 falls through to FAILED: the reset check
    if not mg.flagReset or mg.flagReset == 0 or not d:check(mg.flagReset) then return end
    d:set(mg.flagReset, false)
    mg.action, mg.timer = 1, mg.subtimer
    for pos, v in pairs(mg.saved) do if v then setT(f, mg.layer, pos, v) end end
  elseif a == 3 then
    if mg.timer == 0 then return end
    mg.timer = mg.timer - 1
    if mg.timer ~= 0 then
      if mg.timer == 0x20 then d:set(mg.flagDone) end
    else f:sound(SFX_SECRET) end
  end
end

-- ===========================================================================
-- dispatch
-- ===========================================================================
function O.spawnObject(d, e)
  local id = e.id
  if id == O.GURUGURU_BAR then return O.spawnBar(d, e)
  elseif id == O.JAIL_BARS then return O.spawnJail(d, e)
  elseif id == O.METAL_DOOR then return O.spawnMetalDoor(d, e) or false
  elseif id == O.BLOCKING_STAIRS and (e.form or 0) <= 1 then return O.spawnStairs(d, e) end
  return nil
end
function O.spawnManager(d, m)
  if m.id == O.ANGRY_STATUE_MANAGER then return O.spawnStatueManager(d, m) end
  if m.id == O.TILE_PUZZLE_MANAGER then return O.spawnTilePuzzle(d, m) end
  return nil
end

-- Four Sword clones on buttons (Dungeon:somethingOn)
function O.cloneOn(d, tx, ty)
  local cl = d.field.playerClones
  if type(cl) ~= "table" then return false end
  for _, c in ipairs(cl) do
    if c and not c.deleted and (c.z or 0) == 0 and math.abs(c.x - (tx * 16 + 8)) <= 9 and math.abs(c.y - (ty * 16 + 9)) <= 8 then
      return true
    end
  end
  return false
end

-- ===========================================================================
-- room code (src/roomInit.c)
-- ===========================================================================
-- a base list the room's sub_unk3 cleared: remove what it spawned
function O.dropList(f, list)
  if not list then return end
  local d = f._dungeon
  for _, dat in ipairs(list) do
    for _, e in ipairs(f.entities) do
      if not e.deleted and (e.data == dat or (e.enemy and e.id == dat.id and e.x == dat.x and e.y == dat.y and dat.kind == 3)) then
        e.deleted = true
        if e.blocked and d then d:block(e.tx, e.ty, e.layer or 1, false) end
      end
    end
    if d then
      for _, e in ipairs(d.objs) do if e.data == dat then e.deleted = true end end
      for i = #d.mgrs, 1, -1 do
        local m = d.mgrs[i]
        if m.id == dat.id and m.x == dat.x and m.y == dat.y and dat.kind == 9 then table.remove(d.mgrs, i) end
      end
    end
  end
end
local function fill114(f, base, layer, w, h) -- sub_0807BB98
  for y = 0, h - 1 do
    for x = 0, w - 1 do setT(f, layer, base + x, SP114) end
    base = base + 0x40
  end
end
O.fill114 = fill114
local function loc(f, i) return f:flag("local", i) end
local function glob(f, i) return f:flag("global", i) end
local ENDING, ZELDA_CHASE, SEIIKI_BGM = 0x51, 0x1C, 0x5D
local BGM_BEAT_VAATI, BGM_CASTLE_COLLAPSE = 17, 49
local ITEM_GREEN_SWORD, ITEM_RED_SWORD, ITEM_BLUE_SWORD, ITEM_FOURSWORD = 2, 3, 4, 6
local ITEM_EARTH, ITEM_FIRE, ITEM_WATER, ITEM_WIND = 0x40, 0x41, 0x42, 0x43 -- round 27b: the ROM's ids (script_CutsceneMiscObjectTextBoard checks $40 / $41; FOUR_ELEMENTS type = item), were 61..64

O.ROOMS = {}
local function reg(a, r, fn) O.ROOMS[a * 256 + r] = fn end
local function dhcEscape(f) -- sub_0804D9B0
  fill114(f, 0x797, 1, 5, 1); fill114(f, 0x357, 1, 5, 1); fill114(f, 0x55F, 1, 2, 1)
  f:loadEntityList(0x080EB684)
  f.queuedBgm = nil
end
reg(0x88, 0x00, function(f) -- 1FEntrance
  local lists = f.room.entities or {}
  if glob(f, ENDING) then
    O.dropList(f, lists[0]); O.dropList(f, lists[2])
    f:loadEntityList(0x080EB604)
    f.queuedBgm = BGM_BEAT_VAATI -- gArea.bgm = gArea.queued_bgm = BGM_BEAT_VAATI
  elseif loc(f, 0x79) then
    O.dropList(f, lists[0])
    if not loc(f, 0x7A) then
      f:setFlag("global", ZELDA_CHASE, true)
      f:loadEntityList(0x080EB5D4)
      O.dropList(f, lists[2])
    end
    dhcEscape(f)
  end
end)
reg(0x88, 0x06, function(f) -- 3FTripleDarknut
  local lists = f.room.entities or {}
  if not loc(f, 0x77) then
    O.dropList(f, lists[0]); O.dropList(f, lists[2])
    f:loadEntityList(0x080EB9F4)
  else
    if not loc(f, 0x78) then f:loadEntityList(0x080EBAA4); f:setFlag("local", 0x75, true) end
    if loc(f, 0x7B) then f:loadEntityList(0x080EBAF4); f:setFlag("local", 0x76, true) end
  end
end)
for _, r in ipairs({ { 0x0E, 0x4C, 0x080EC2CC }, { 0x10, 0x4D, 0x080EC4E8 }, { 0x13, 0x53, 0x080EC820 }, { 0x15, 0x56, 0x080ECA60 } }) do
  reg(0x88, r[1], function(f) if loc(f, 0x86) and not loc(f, r[2]) then f:loadEntityList(r[3]) end end)
end
reg(0x88, 0x1C, function(f) -- B1Entrance
  if loc(f, 0x79) then
    O.dropList(f, (f.room.entities or {})[2])
    fill114(f, 0x90, 1, 1, 5)
    f:loadEntityList(0x080ECFCC)
    f.queuedBgm = nil
  end
end)
reg(0x88, 0x1F, function(f) -- 1FThroneRoom
  if glob(f, ENDING) then
    local lists = f.room.entities or {}
    O.dropList(f, lists[0]); O.dropList(f, lists[2])
    f:loadEntityList(0x080ED1E4)
  end
end)
reg(0x88, 0x35, function(f) -- B1Left
  if loc(f, 0x79) then
    local lists = f.room.entities or {}
    O.dropList(f, lists[0]); O.dropList(f, lists[2])
    fill114(f, 3, 2, 5, 1)
    f:loadEntityList(0x080EE314)
    f.queuedBgm = nil
  end
end)
reg(0x88, 0x37, function(f) -- B1Map
  if loc(f, 0x79) then
    O.dropList(f, (f.room.entities or {})[2])
    fill114(f, 0x392, 2, 2, 5)
    f:loadEntityList(0x080EE5DC)
    f.queuedBgm = nil
  end
end)
reg(0x88, 0x39, function(f) if loc(f, 1) then f:loadEntityList(0x080EE71C) end end) -- B2Prison
reg(0x89, 0x00, function(f) -- Outside ZeldaStatuePlatform
  if not loc(f, 0x77) then f:loadEntityList(0x080EAD68)
  elseif not loc(f, 0x79) then
    f:loadEntityList(0x080EADB8)
    setT(f, 1, 5 + 5 * 64, SP114); setT(f, 1, 9 + 5 * 64, SP114)
    f.queuedBgm = 0
  end
end)
reg(0x89, 0x01, function(f) -- Outside Garden
  if glob(f, ENDING) then
    if not loc(f, 0x7F) then f:loadEntityList(0x080EAEC0); f:setFlag("local", 0x7F, true); f.queuedBgm = BGM_BEAT_VAATI
    else f:loadEntityList(0x080EAF20); f.queuedBgm = nil end
  else
    if loc(f, 0x79) then f.queuedBgm = nil end
    if not loc(f, 1) then f:loadEntityList(0x080EAE60) end
  end
  f:setFlag("global", SEIIKI_BGM, false)
end)
reg(0x78, 0x00, function(f) if glob(f, SEIIKI_BGM) then f.queuedBgm = BGM_CASTLE_COLLAPSE end end) -- Sanctuary Hall
reg(0x78, 0x01, function(f) -- Sanctuary Main
  local inv = function(i) return (f:inventory(i) or 0) ~= 0 end
  if not loc(f, 0x79) then f:loadEntityList(0x080F54E8) end
  if not loc(f, 0x7A) then
    if inv(ITEM_GREEN_SWORD) and not inv(ITEM_RED_SWORD) and inv(ITEM_EARTH) and inv(ITEM_FIRE) then f:loadEntityList(0x080F5508) end
  elseif not loc(f, 0x7B) then
    if inv(ITEM_RED_SWORD) and not inv(ITEM_BLUE_SWORD) and inv(ITEM_WATER) then f:loadEntityList(0x080F5558) end
  elseif not loc(f, 0x7C) then
    if not inv(ITEM_FOURSWORD) and inv(ITEM_WIND) then f:loadEntityList(0x080F5598) end
  else f:loadEntityList(0x080F55D8) end
  if loc(f, 0x7A) then f:loadEntityList(0x080F5528) end
  if loc(f, 0x7B) then f:loadEntityList(0x080F5578) end
  if loc(f, 0x7C) then f:loadEntityList(0x080F55B8) end
  if glob(f, SEIIKI_BGM) then f.queuedBgm = BGM_CASTLE_COLLAPSE end
end)
reg(0x78, 0x02, function(f) -- Sanctuary StainedGlass
  if not loc(f, 0x78) and loc(f, 0x7C) then f:loadEntityList(0x080F5660) end
  if glob(f, SEIIKI_BGM) then f.queuedBgm = BGM_CASTLE_COLLAPSE end
end)

function O.roomInit(f)
  local r = f.room
  if not r then return end
  local fn = O.ROOMS[(r.area or 0) * 256 + (r.room or 0)]
  if fn then fn(f) end
end

return O
