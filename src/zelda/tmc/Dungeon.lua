-- Dungeon machinery for The Minish Cap: the flag graph that ties a room's
-- doors, switches, chests and enemies together, as the cartridge's own
-- room data wires it.
--
-- FLAG SPECS (src/flags.c CheckFlags / SetFlag): index = spec & $3FF, count
-- = ((spec >> 10) & $F) + 1 consecutive bits that must all be set, type =
-- spec >> 14 (0 local, 1 global, 2 room).  $FFFF / 0 = none.
--
-- OBJECTS (EntityData paramC low/high are the entity's fields $84/$86):
--   LOCKED_DOOR $08 (lockedDoor.c): type & 3 side, (type >> 2) & 3 kind --
--     0 opens when its flag is set (0x10: starts open, shuts once Link is
--     through), 1 shuts when the flag is set, 2 a small-key lock (uses a
--     key, sets the flag); paramC low = "already gone" flags.
--   BOSS_DOOR $39 (bossDoor.c): opens with the big key, sets its flag.
--   BUTTON $03 (button.c): type 0 latches, type 1 is held; pressed by Link
--     (not Minish) inside 5x6 or by a statue / pot on its tile.
--   CHEST_SPAWNER $0C (chestSpawner.c): types 0/1/6/7 make a small chest
--     tile ($73) appear when the flag is set; types 2-5 are big chests
--     (type 4 always there) whose item is the BIG_CHEST tile entity with
--     localFlag = type2, opened facing north.
--   PUSHABLE_STATUE $27, LILYPAD_LARGE $14, HEART_CONTAINER $47.
--   SPIDER_WEB / REMOVABLE_DUST (projectiles $15 / $14): blockers the Gust
--     Jar removes -- a web is grabbed facing it and torn by walking back
--     (SpiderWeb_OnGrabbed / PL_STATE_PULL), dust is sucked away.
-- MANAGERS (fields $34-$3F = EntityData bytes 4-15):
--   REGION_TRIGGER $1E, FIGHT $0B, TILE_CHANGE_OBSERVE $0D, BRIDGE $05,
--   FLAG_AND_OPERATOR $11, SECRET $2E, ENTITY_SPAWN $0E, FALLING_ITEM $17.

local bit = require("bit")
local band, rshift, bor, bnot = bit.band, bit.rshift, bit.bor, bit.bnot
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local Dungeon = {}
Dungeon.__index = Dungeon

local OBJ = { BUTTON = 0x03, LOCKED_DOOR = 0x08, CHEST_SPAWNER = 0x0C, LILYPAD = 0x14, PUSHABLE_STATUE = 0x27,
              WARP_POINT = 0x34, BOSS_DOOR = 0x39, HEART_CONTAINER = 0x47, FOUR_ELEMENTS = 0xAC }
local MGR = { EZLO_HINT = 0x0A, BRIDGE = 0x05, FIGHT = 0x0B, TILE_CHANGE = 0x0D, ENTITY_SPAWN = 0x0E, FLAG_AND = 0x11,
              FALLING_ITEM = 0x17, REGION = 0x1E, MOVEABLE = 0x20, SECRET = 0x2E, CAMERA = 0x35 }
local PROJ = { DUST = 0x14, WEB = 0x15 }
Dungeon.OBJ, Dungeon.MGR, Dungeon.PROJ = OBJ, MGR, PROJ
local ITEM = { DUNGEON_MAP = 0x50, COMPASS = 0x51, BIG_KEY = 0x52, SMALL_KEY = 0x53 }
Dungeon.ITEM = ITEM
local ACT_WATER, ACT_HOLE = 0x10, 0x19
local TT = { BUTTON_UP = 119, BUTTON_HELD = 120, BUTTON_DOWN = 122, SMALL_CHEST = 0x73 }
local SFX = { DOOR = 0x10B, SECRET = 0x72, BUTTON = 0x10C, BOSS_DOOR = 0x185, CHEST = 0x11B }

-- door art per area (lockedDoor.c sub_080837B0: gUnk_0811F690[area - $40])
local DOOR_GFX = { [0x48] = 0x15, [0x49] = 0x15 }

function Dungeon.new(field)
  local self = setmetatable({ field = field, A = field.assets, m = field.assets.manifest }, Dungeon)
  self:reset()
  return self
end

function Dungeon:reset()
  self.objs, self.mgrs, self.blocks = {}, {}, {}
  self.safe = nil
end

-- ---------------------------------------------------------------------------
-- flag specs and the dungeon's inventory
-- ---------------------------------------------------------------------------
function Dungeon:check(spec)
  local f = self.field
  if not spec or spec == 0xFFFF then return false end
  local index, count, kind = band(spec, 0x3FF), band(rshift(spec, 10), 0xF) + 1, rshift(spec, 14)
  for i = index, index + count - 1 do
    local set
    if kind == 0 then set = f:flag("local", i)
    elseif kind == 1 then set = f:flag("global", i)
    elseif kind == 2 then set = f:flag("room", i)
    else return false end
    if not set then return false end
  end
  return true
end

function Dungeon:set(spec, value)
  local f = self.field
  if not spec or spec == 0 or spec == 0xFFFF then return end
  local index, kind = band(spec, 0x3FF), rshift(spec, 14)
  if value == nil then value = true end
  if kind == 0 then f:setFlag("local", index, value)
  elseif kind == 1 then f:setFlag("global", index, value)
  elseif kind == 2 then f:setFlag("room", index, value) end
end

-- per dungeon (by area location): keys, big key, map, compass
function Dungeon:state()
  local f = self.field
  local loc = f.room.areaInfo and f.room.areaInfo.location or 0
  f.save.dungeons = f.save.dungeons or {}
  local d = f.save.dungeons[loc]
  if not d then d = { keys = 0 }; f.save.dungeons[loc] = d end
  return d
end

-- HasDungeonSmallKey / BigKey / Compass / Map, and giving them
function Dungeon:inventory(item)
  local d = self:state()
  if item == ITEM.SMALL_KEY then return d.keys or 0 end
  if item == ITEM.BIG_KEY then return d.bigKey and 1 or 0 end
  if item == ITEM.COMPASS then return d.compass and 1 or 0 end
  if item == ITEM.DUNGEON_MAP then return d.map and 1 or 0 end
  return nil
end

function Dungeon:give(item)
  local d = self:state()
  if item == ITEM.SMALL_KEY then d.keys = (d.keys or 0) + 1 return true end
  if item == ITEM.BIG_KEY then d.bigKey = true return true end
  if item == ITEM.COMPASS then d.compass = true return true end
  if item == ITEM.DUNGEON_MAP then d.map = true return true end
  return false
end

-- ---------------------------------------------------------------------------
-- tile blockers (SPECIAL_TILE_34 under closed doors, webs, statues)
-- ---------------------------------------------------------------------------
function Dungeon:block(tx, ty, layer, on)
  local r = self.field.room
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return end
  layer = layer or 1
  local i = ty * r.tw + tx
  local key = layer * 65536 + i
  if on then
    if not self.blocks[key] then
      self.blocks[key] = { count = 0, orig = r.coll[layer][i] }
    end
    self.blocks[key].count = self.blocks[key].count + 1
    r.coll[layer][i] = 0x0F
  else
    local b = self.blocks[key]
    if not b then return end
    b.count = b.count - 1
    if b.count <= 0 then
      r.coll[layer][i] = b.orig
      self.blocks[key] = nil
    end
  end
end

local function tileOf(x, y) return math.floor(x / 16), math.floor(y / 16) end

function Dungeon:dress(e, sprite, palette, gfxSrc, anim)
  e.sprite = sprite
  e.palette = self.A:objPalette(palette or 0, self.field.room.atlas and self.field.room.atlas.palettes)
  e.gfx = gfxSrc
  e.anim = e.anim or Anim.new()
  e.literalAnim = true
  e.objAnim = anim or 0
end

-- ---------------------------------------------------------------------------
-- spawning
-- ---------------------------------------------------------------------------
-- returns the entity (added by Field) or false when not a dungeon object
function Dungeon:spawnObject(d)
  local id = d.id
  local e = { kind = 6, id = id, form = d.paramA, type2 = band(d.paramB, 0xFF), timer0 = band(rshift(d.paramB, 8), 0xFF),
              x = d.x, y = d.y, z = 0, animationState = 0, field80 = 0, field82 = 0, interactType = 0,
              flags = band(d.paramC, 0xFFFF), flag = rshift(d.paramC, 16), dungeon = true, data = d,
              layer = (band(rshift(d.collision or 0, 0), 3) == 2) and 2 or 1 }
  if id == OBJ.LOCKED_DOOR then return self:doorInit(e)
  elseif id == OBJ.BOSS_DOOR then return self:bossDoorInit(e)
  elseif id == OBJ.BUTTON then return self:buttonInit(e)
  elseif id == OBJ.CHEST_SPAWNER then return self:chestInit(e)
  elseif id == OBJ.PUSHABLE_STATUE then return self:statueInit(e)
  elseif id == OBJ.LILYPAD then return self:lilyInit(e)
  elseif id == OBJ.HEART_CONTAINER then
    -- heartContainer.c: gone once its flag is set; appears when flag2 is
    -- set; touching it is the ITEM_HEART_CONTAINER item get
    if self:check(e.flags) then return nil end
    local def = self.field:objects():def(0, 0x62)
    if def then self.field:objects():dress(e, def, 0x62) end
    e.objAnim = 0x62
    e.hidden = true
    e.heart = true
    self:track(e)
    return e
  elseif id == OBJ.FOUR_ELEMENTS then
    -- fourElements.c: comes down from z = 192, touching it gives the
    -- element (item = its type), then room flag 0 is set
    local def = self.field:objects():def(OBJ.FOUR_ELEMENTS, e.form)
    if def then self.field:objects():dress(e, def, 0) end
    e.objAnim = 0
    e.element = true
    e.z = 192
    self:track(e)
    return e
  elseif id == OBJ.WARP_POINT then
    -- warpPoint.c: active once its flag is set; type 2 leaves the dungeon
    local def = self.field:objects():def(OBJ.WARP_POINT, 0)
    if def then self.field:objects():dress(e, def, 0) end
    e.objAnim = 0
    e.warp = true
    e.hidden = not self:check(e.flag)
    self:track(e)
    return e
  end
  return false
end

-- where a dungeon's warp point (type 2, after the boss) leads: the area
-- outside its entrance (Deepwood Shrine -> Deepwood Shrine Entry)
local WARP_OUT = { [0x49] = { area = 0x4A, room = 0, x = 120, y = 136 } }

function Dungeon:updateSpecial(e)
  local f = self.field
  local p = f.player
  if e.heart then
    if e.hidden and self:check(e.flag) then e.hidden = false f:sound(0x11F) end
    if not e.hidden and not p.minish and math.abs(p.x - e.x) < 10 and math.abs(p.y - e.y) < 12 then
      self:set(e.flags)
      e.deleted = true
      f:giveItem(0x62, 0)
    end
  elseif e.element then
    if e.z > 8 then e.z = e.z - 1 return end
    if not e.got and math.abs(p.x - e.x) < 12 and math.abs(p.y - e.y) < 14 then
      e.got = true
      e.hidden = true
      f:sound(0xF8)
      f:giveItem(e.form, 0)
    elseif e.got and not f:messageActive() then
      f:setFlag("room", 0, true)
      e.deleted = true
    end
  elseif e.warp then
    if e.hidden and self:check(e.flag) then e.hidden = false end
    if not e.hidden and math.abs(p.x - e.x) < 8 and math.abs(p.y - e.y) < 8 and p.state == "normal" then
      local to = WARP_OUT[f.room.area]
      if to then
        f:startTransition({ warpType = 1, area = to.area, room = to.room, endX = to.x, endY = to.y, facing = 4, kind = 0 })
      end
    end
  end
end

function Dungeon:spawnProjectile(d)
  if d.id ~= PROJ.WEB and d.id ~= PROJ.DUST then return false end
  local def = self.m.projectileDefs and self.m.projectileDefs[d.id]
  if def and def.multi then def = def.forms[d.paramA] or def.forms[0] end
  local e = { kind = 4, id = d.id, form = d.paramA, x = d.x, y = d.y, z = 0, flag = rshift(d.paramC, 16),
              animationState = 0, field82 = 0, interactType = 0, dungeon = true, layer = 1 }
  if self:check(e.flag) then return nil end
  if def then self:dress(e, def.sprite, def.palette, Assets.gfxSource("enemy", def.gfx), d.paramA) end
  e.web = d.id == PROJ.WEB
  e.dust = d.id == PROJ.DUST
  e.tx, e.ty = tileOf(e.x, e.y)
  self:block(e.tx, e.ty, 1, true)
  e.blocked = true
  self:track(e)
  return e
end

function Dungeon:spawnManager(d)
  local id = d.id
  local m = { id = id, type = d.paramA, type2 = band(d.paramB, 0xFF), b1 = band(rshift(d.paramB, 8), 0xFF),
              b16 = band(d.paramB, 0xFFFF), b32 = rshift(d.paramB, 16), x = d.x, y = d.y,
              c0 = band(d.paramC, 0xFFFF), c1 = rshift(d.paramC, 16), action = 0, timer = 0 }
  if id == MGR.REGION or id == MGR.FIGHT or id == MGR.TILE_CHANGE or id == MGR.BRIDGE or id == MGR.FLAG_AND
     or id == MGR.SECRET or id == MGR.ENTITY_SPAWN or id == MGR.FALLING_ITEM or id == MGR.CAMERA
     or id == MGR.EZLO_HINT then
    self.mgrs[#self.mgrs + 1] = m
    return true
  end
  if id == MGR.MOVEABLE then
    -- MoveableObjectManager: object b1 at its moved place when the flag
    -- (paramC high) is set, else at x, y
    local x, y = d.x, d.y
    if self:check(m.c1) then
      x = bor(band(m.b32, 0xFF), band(rshift(m.b32, 8), 0xF) * 256)
      y = band(m.c0, 0xFFF)
    end
    self.field:spawn({ kind = 6, id = m.b1, paramA = m.type, paramB = m.type2, paramC = m.c1 * 65536,
                       pool = 0x0F, x = x, y = y, collision = 1 })
    return true
  end
  if false then
    self.mgrs[#self.mgrs + 1] = m
    return true
  end
  return false
end

function Dungeon:track(e) self.objs[#self.objs + 1] = e end

-- ---------------------------------------------------------------------------
-- LOCKED_DOOR / BOSS_DOOR
-- ---------------------------------------------------------------------------
function Dungeon:doorClose(e)
  if e.closed then return end
  e.closed = true
  e.hidden = false
  self:block(e.tx, e.ty, e.layer, true)
end

function Dungeon:doorOpen(e, sound)
  if not e.closed then return end
  e.closed = false
  e.hidden = true
  self:block(e.tx, e.ty, e.layer, false)
  if sound ~= false then self.field:sound(SFX.DOOR) end
end

function Dungeon:doorInit(e)
  if e.flags ~= 0xFFFF and self:check(e.flags) then return nil end
  local t = e.form
  e.dir = band(t, 3)
  e.kind2 = band(rshift(t, 2), 3)
  e.tx, e.ty = tileOf(e.x, e.y)
  local gfx = DOOR_GFX[self.field.room.area] or 0x0A
  self:dress(e, 477, 10, gfx, 0)
  e.staticFrame = band(t, 3)
  e.door = true
  self:track(e)
  if e.kind2 == 0 then
    if not self:check(e.flag) then
      if band(t, 0x10) ~= 0 then e.waitPass = true; e.hidden = true
      else self:doorClose(e) end
    else
      e.hidden = true
    end
  elseif e.kind2 == 1 then
    if self:check(e.flag) then self:doorClose(e) else e.hidden = true end
  elseif e.kind2 == 2 then
    if self:check(e.flag) then return nil end
    e.staticFrame = bor(band(t, 3), 4)
    e.keyLock = true
    self:doorClose(e)
  else
    return nil
  end
  return e
end

-- sub_08083734: has Link passed the doorway (into the room)?
local function passed(e, p)
  if e.dir == 0 then return e.y + 13 - p.y < 0 end
  if e.dir == 1 then return p.x - (e.x - 11) < 0 end
  if e.dir == 2 then return p.y - (e.y - 8) < 0 end
  return e.x + 10 - p.x < 0
end

function Dungeon:updateDoor(e)
  local p = self.field.player
  if e.waitPass then
    if passed(e, p) then
      e.waitPass = false
      self:doorClose(e)
      self.field:sound(SFX.DOOR)
    end
    return
  end
  if e.keyLock then return end
  if e.kind2 == 0 then
    if e.closed and self:check(e.flag) then self:doorOpen(e) end
  elseif e.kind2 == 1 then
    if not e.closed and self:check(e.flag) and passed(e, p) then self:doorClose(e) end
  end
end

function Dungeon:bossDoorInit(e)
  if e.flags ~= 0xFFFF and self:check(e.flags) then return nil end
  if e.flag ~= 0 and self:check(e.flag) then return nil end
  e.dir = band(e.form, 3)
  e.kind2 = rshift(e.form, 2)
  e.tx, e.ty = tileOf(e.x, e.y)
  self:dress(e, 203, 4, 65, band(e.form, 0x1F))
  e.door = true
  e.bossDoor = true
  self:track(e)
  if e.kind2 == 1 then e.hidden = true return e end
  -- three tiles across the doorway
  local dx, dy = (e.dir == 0 or e.dir == 2) and 1 or 0, (e.dir == 1 or e.dir == 3) and 1 or 0
  e.span = { { e.tx - dx, e.ty - dy }, { e.tx, e.ty }, { e.tx + dx, e.ty + dy } }
  for _, t in ipairs(e.span) do self:block(t[1], t[2], e.layer, true) end
  e.closed = true
  return e
end

-- R / bumping into a door with the key it needs
function Dungeon:tryDoor(p)
  local fx, fy = p:frontPoint(10)
  for _, e in ipairs(self.objs) do
    if e.closed and (e.keyLock or (e.bossDoor and e.kind2 ~= 2)) and not e.deleted
       and math.abs(e.x - fx) < 16 and math.abs(e.y - fy) < 16 then
      local st = self:state()
      if e.keyLock and (st.keys or 0) > 0 then
        st.keys = st.keys - 1
        self:set(e.flag)
        self:doorOpen(e)
        e.deleted = true
        return true
      elseif e.bossDoor and st.bigKey then
        self:set(e.flag)
        for _, t in ipairs(e.span) do self:block(t[1], t[2], e.layer, false) end
        e.closed = false
        e.deleted = true
        self.field:sound(SFX.BOSS_DOOR)
        return true
      end
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- BUTTON
-- ---------------------------------------------------------------------------
function Dungeon:buttonInit(e)
  e.tx, e.ty = tileOf(e.x, e.y + 1)
  e.button = true
  e.hidden = true
  e.latch = e.form == 0
  if e.latch and self:check(e.flag) then
    e.pressed = true
    self.field:objects():setTileType(e.layer, e.tx, e.ty, TT.BUTTON_DOWN)
  end
  self:track(e)
  return e
end

function Dungeon:somethingOn(tx, ty, who)
  local p = self.field.player
  if not p.minish and (p.z or 0) == 0 and math.abs(p.x - (tx * 16 + 8)) <= 5 + 4 and math.abs(p.y - (ty * 16 + 9)) <= 6 + 2 then
    return true
  end
  for _, o in ipairs(self.objs) do
    if o ~= who and o.statue and not o.deleted then
      local ox, oy = tileOf(o.x, o.y)
      if ox == tx and oy == ty then return true end
    end
  end
  for _, o in ipairs(self.field.entities) do
    if o.liftable and not o.deleted then
      local ox, oy = tileOf(o.x, o.y)
      if ox == tx and oy == ty then return true end
    end
  end
  return false
end

function Dungeon:updateButton(e)
  local on = self:somethingOn(e.tx, e.ty, e)
  if e.latch then
    if not e.pressed and on then
      e.pressed = true
      self:set(e.flag)
      self.field:objects():setTileType(e.layer, e.tx, e.ty, TT.BUTTON_DOWN)
      self.field:sound(SFX.BUTTON)
    end
  else
    if on and not e.pressed then
      e.pressed = true
      self:set(e.flag)
      self.field:objects():setTileType(e.layer, e.tx, e.ty, TT.BUTTON_HELD)
      self.field:sound(SFX.BUTTON)
    elseif not on and e.pressed then
      e.pressed = false
      self:set(e.flag, false)
      self.field:objects():setTileType(e.layer, e.tx, e.ty, TT.BUTTON_UP)
      self.field:sound(SFX.BUTTON)
    end
  end
end

-- ---------------------------------------------------------------------------
-- CHEST_SPAWNER (small chests appearing, and big chests)
-- ---------------------------------------------------------------------------
function Dungeon:chestInit(e)
  local t = e.form
  e.tx, e.ty = tileOf(e.x, e.y)
  if t == 0 or t == 1 or t == 6 or t == 7 then
    e.small = true
    e.hidden = true
    if self:check(e.flag) then
      self.field:objects():setTileType(e.layer, e.tx, e.ty, TT.SMALL_CHEST)
      if band(t, 1) == 0 then return nil end
      e.shown = true
    end
    self:track(e)
    return e
  end
  -- a big chest
  e.big = true
  self:dress(e, 184, 1, 25, 0)
  if self.field:flag("local", e.type2) then
    e.opened = true
    e.objAnim = 1
    e.shown = true
  elseif self:check(e.flag) or t == 4 then
    e.shown = true
  else
    e.hidden = true
  end
  if e.shown then e.solid = true end
  self:track(e)
  return e
end

function Dungeon:updateChest(e)
  if e.shown then return end
  if self:check(e.flag) then
    e.shown = true
    self.field:sound(SFX.SECRET)
    if e.small then
      self.field:objects():setTileType(e.layer, e.tx, e.ty, TT.SMALL_CHEST)
    else
      e.hidden = false
      e.solid = true
    end
  end
end

-- open a big chest Link faces from the south
function Dungeon:tryBigChest(p)
  if p.animationState ~= 0 then return false end
  local fx, fy = p:frontPoint(10)
  for _, e in ipairs(self.objs) do
    if e.big and e.shown and not e.opened and math.abs(e.x - fx) < 14 and math.abs(e.y - fy) < 12 then
      e.opened = true
      e.objAnim = 1
      self.field:sound(SFX.CHEST)
      self.field:setFlag("local", e.type2, true)
      for _, te in ipairs(self.field.room.tileEntities or {}) do
        if te.type == 3 and te.flag == e.type2 then
          self.field:giveItem(te.a, te.b)
          return true
        end
      end
      return true
    end
  end
  return false
end

-- ---------------------------------------------------------------------------
-- PUSHABLE_STATUE: pushing into it for 16 frames slides it a tile
-- ---------------------------------------------------------------------------
function Dungeon:statueInit(e)
  local def = self.field:objects():def(OBJ.PUSHABLE_STATUE, 0)
  if def then self.field:objects():dress(e, def, 0) end
  e.objAnim = 0
  e.statue = true
  e.tx, e.ty = tileOf(e.x, e.y)
  self:block(e.tx, e.ty, e.layer, true)
  e.push = 0
  self:track(e)
  return e
end

function Dungeon:updateStatue(e, input)
  local p = self.field.player
  if e.moving then
    local step = 1
    e.x = e.x + e.mdx * step
    e.y = e.y + e.mdy * step
    e.moving = e.moving - 1
    if e.moving <= 0 then
      e.moving = nil
      e.tx, e.ty = tileOf(e.x, e.y)
      self:block(e.tx, e.ty, e.layer, true)
    end
    return
  end
  local fx, fy = p:frontPoint(8)
  local ftx, fty = tileOf(fx, fy)
  local s = p.animationState
  local held = (s == 0 and input.down("up")) or (s == 4 and input.down("down")) or (s == 2 and input.down("right")) or (s == 6 and input.down("left"))
  if ftx == e.tx and fty == e.ty and held and not p.minish then
    e.push = e.push + 1
    if e.push >= 16 then
      e.push = 0
      local dx = (s == 2 and 1) or (s == 6 and -1) or 0
      local dy = (s == 4 and 1) or (s == 0 and -1) or 0
      local r = self.field.room
      self:block(e.tx, e.ty, e.layer, false)
      if not r:isSolid((e.tx + dx) * 16 + 8, (e.ty + dy) * 16 + 8, e.layer) then
        e.mdx, e.mdy, e.moving = dx, dy, 16
        self.field:sound(0x11E)
      else
        self:block(e.tx, e.ty, e.layer, true)
      end
    end
  else
    e.push = 0
  end
end

-- ---------------------------------------------------------------------------
-- LILYPAD_LARGE: Link rides it; the Gust Jar blowing from it pushes it the
-- other way across water (lilypadLarge.c, simplified)
-- ---------------------------------------------------------------------------
function Dungeon:lilyInit(e)
  self:dress(e, 167, 2, 13, 0)
  e.lily = true
  self:track(e)
  return e
end

function Dungeon:onLily(p)
  for _, e in ipairs(self.objs) do
    if e.lily and not e.deleted and math.abs(p.x - e.x) <= 14 and math.abs(p.y - e.y) <= 12 then return e end
  end
  return nil
end

function Dungeon:actAt(x, y, layer)
  local r = self.field.room
  local tx, ty = tileOf(x, y)
  local t = r:tileType(layer or 1, tx, ty)
  if not t or t >= 0x4000 then return nil end
  return self.A.actTile[t]
end

function Dungeon:updateLily(e)
  local p = self.field.player
  if p.state == "gust" and self:onLily(p) == e then
    local s = p.animationState
    local dx = (s == 2 and -1) or (s == 6 and 1) or 0
    local dy = (s == 4 and -1) or (s == 0 and 1) or 0
    local nx, ny = e.x + dx * 0.75, e.y + dy * 0.75
    local a = self:actAt(nx + dx * 12, ny + dy * 12)
    if a == ACT_WATER then
      e.x, e.y = nx, ny
      p.x, p.y = p.x + dx * 0.75, p.y + dy * 0.75
    end
  end
end

-- ---------------------------------------------------------------------------
-- webs and dust: the Gust Jar
-- ---------------------------------------------------------------------------
function Dungeon:removeBlocker(e)
  if e.blocked then self:block(e.tx, e.ty, 1, false) e.blocked = false end
  e.deleted = true
  self:set(e.flag)
  self.field:sound(0x100) -- SFX_100 (the web tears)
end

function Dungeon:updateBlocker(e)
  local p = self.field.player
  local reach = e.grab and 48 or 28
  local near = math.abs(p.x - e.x) < reach and math.abs(p.y - e.y) < reach
  if p.state ~= "gust" or not near then
    if e.grab then e.grab = nil end
    e.suck = 0
    return
  end
  if e.dust then
    e.suck = (e.suck or 0) + 1
    if e.suck > 40 then self:removeBlocker(e) end
    return
  end
  -- a web: grabbed facing it (animationState >> 1 == type), torn by
  -- walking back 12 px while holding on
  if not e.grab then
    if rshift(p.animationState, 1) == e.form then e.grab = { x = p.x, y = p.y } end
  else
    local d = math.abs(p.x - e.grab.x) + math.abs(p.y - e.grab.y)
    if d >= 12 then self:removeBlocker(e) end
  end
end

-- ---------------------------------------------------------------------------
-- falling into water / holes (no flippers, not on a lily pad)
-- ---------------------------------------------------------------------------
function Dungeon:checkFall()
  local f = self.field
  local p = f.player
  if p.state ~= "normal" and p.state ~= "gust" and p.state ~= "shield" then return end
  if (p.z or 0) > 0 or self:onLily(p) then return end
  local a = self:actAt(p.x, p.y - 1, p.layer)
  -- no safe spot yet (just arrived): the arrival point counts as one
  if not self.safe then self.safe = { x = p.x, y = p.y } return end
  if a == ACT_HOLE or (a == ACT_WATER and f:inventory(0x10) == 0 and not p.minish) then -- ITEM_FLIPPERS
    f:sound(a == ACT_HOLE and 0x82 or 0x24)
    f:modStat("health", -2)
    -- back to the last tile he stood on safely (RespawnPlayer)
    local st = self.safe or f.entry
    p.x, p.y = st.x, st.y
    p.invuln = 60
  else
    self.safe = { x = p.x, y = p.y }
  end
end

-- ---------------------------------------------------------------------------
-- managers
-- ---------------------------------------------------------------------------
function Dungeon:propList(k)
  local props = self.field.room.maps.header.props
  local addr = props and props[k]
  if not addr then return nil end
  return self.field:entityListAt(addr)
end

function Dungeon:updateManager(m)
  local f = self.field
  local p = f.player
  if m.done then return end
  if m.id == MGR.REGION then
    -- radius = paramB halves, centred (RegionTriggerManager_Init)
    if m.action == 0 then
      m.action = 1
      m.rx, m.ry = rshift(band(m.b16, 0xFFFF), 1), rshift(m.b32, 1)
      m.cx, m.cy = m.x + m.rx, m.y + m.ry
      if m.type == 0 and self:check(m.c1) then m.done = true return end
    end
    if math.abs(p.x - m.cx) < m.rx and math.abs(p.y - m.cy) < m.ry then
      self:set(m.c1)
      if m.type == 0 then m.done = true end
    else
      self:set(m.c1, false)
    end
  elseif m.id == MGR.FIGHT then
    if m.action == 0 then
      if self:check(m.c1) then m.done = true return end
      m.action = 1
    end
    if m.action == 1 and (m.c0 == 0 or self:check(m.c0)) then
      m.action = 2
      m.enemies = {}
      for _, d in ipairs(self:propList(m.type2) or {}) do
        local e = f:spawn(d)
        if e and (e.enemy or e.boss) then m.enemies[#m.enemies + 1] = e end
      end
    elseif m.action == 2 then
      for _, e in ipairs(m.enemies) do
        if not e.deleted then return end
      end
      self:set(m.c1)
      m.done = true
    end
  elseif m.id == MGR.TILE_CHANGE then
    -- tile = x (a tile position), layer = y
    if m.action == 0 then
      if self:check(m.c1) then m.done = true return end
      m.action = 1
      m.layerName = m.y == 2 and "top" or "bottom"
      m.initial = f.room.maps[m.layerName][m.x % 64 + math.floor(m.x / 64) * f.room.tw]
    elseif m.action == 1 then
      local now = f.room.maps[m.layerName][m.x % 64 + math.floor(m.x / 64) * f.room.tw]
      if now ~= m.initial then m.action = 2 m.timer = 15 end
    else
      m.timer = m.timer - 1
      if m.timer <= 0 then
        self:set(m.c1)
        if m.type ~= 0 then for _, d in ipairs(self:propList(m.type) or {}) do f:spawn(d) end end
        m.done = true
      end
    end
  elseif m.id == MGR.BRIDGE then
    if m.action == 0 then
      m.action = 1
      local dir = band(m.type2, 3)
      local DX = { [0] = 0, 1, 0, -1 }
      local DY = { [0] = -1, 0, 1, 0 }
      m.dx, m.dy = DX[dir], DY[dir]
      m.tile = (m.b1 == 1) and 0x323 or ((band(dir * 2, 2) ~= 0) and 0x37 or 0x36)
      m.len = band(rshift(m.type2, 2), 0xF) + 1
      m.built = 0
      m.cx, m.cy = m.x, m.y
      m.timer = 28
      m.layer = m.c0 == 2 and 2 or 1
      if band(m.type2, 0x80) ~= 0 and self:check(m.c1) then
        for _ = 1, m.len do
          m.cx, m.cy = m.cx + m.dx, m.cy + m.dy
          f:objects():setTileType(m.layer, m.cx, m.cy, m.tile)
        end
        m.done = true
      end
      return
    end
    m.timer = m.timer - 1
    if m.timer > 0 then return end
    m.timer = 8
    if self:check(m.c1) and m.built < m.len then
      m.cx, m.cy = m.cx + m.dx, m.cy + m.dy
      f:objects():setTileType(m.layer, m.cx, m.cy, m.tile)
      m.built = m.built + 1
      f:sound(0x71)
      if m.built == m.len and band(m.type2, 0x80) ~= 0 then f:sound(SFX.SECRET) m.done = true end
    end
  elseif m.id == MGR.FLAG_AND then
    if m.action == 0 then
      m.action = 1
      if self:check(m.c0) then m.done = true end
    elseif self:check(m.c1) then
      self:set(m.c0)
      m.done = true
    end
  elseif m.id == MGR.SECRET then
    if m.action == 0 then
      if m.type == 0 and self:check(m.c0) then m.done = true return end
      m.action = 1
      m.delay = m.b1 ~= 0 and m.b1 or 30
    elseif m.action == 1 then
      if self:check(m.c1) then m.action = 2 m.timer = m.delay end
    else
      m.timer = m.timer - 1
      if m.timer <= 0 then
        f:sound(m.x ~= 0 and m.x or SFX.SECRET)
        self:set(m.c0)
        if m.type == 0 then m.done = true else m.action = 1 end
      end
    end
  elseif m.id == MGR.ENTITY_SPAWN then
    if m.action == 0 then
      m.action = 1
      if self:check(m.c1) then m.done = true return end
      m.timer = m.y
    end
    if self:check(m.c1) then
      if m.timer <= 0 then
        if m.x ~= 0 then f:sound(m.x) end
        for _, d in ipairs(self:propList(m.type) or {}) do f:spawn(d) end
        m.done = true
      else
        m.timer = m.timer - 1
      end
    end
  elseif m.id == MGR.CAMERA then
    -- CameraTargetManager: when the flag (c1) is set the camera goes to
    -- x, y for b1 frames (default 30), then c0 is set and it comes back
    if m.action == 0 then
      if self:check(m.c0) then m.done = true return end
      if self:check(m.c1) then self:set(m.c0) m.done = true return end
      m.action = 1
    elseif m.action == 1 then
      if self:check(m.c1) then
        m.action = 2
        m.timer = m.b1 ~= 0 and m.b1 or 30
        f:panCamera(m.x, m.y, m.timer + 30)
      end
    elseif m.action == 2 then
      m.timer = m.timer - 1
      if m.timer <= 0 then self:set(m.c0) m.done = true end
    end
  elseif m.id == MGR.EZLO_HINT then
    -- ezloHintManager.c: region = (x low byte, x high byte) tiles plus
    -- (y low, y high) * 8 half sizes; message = paramB >> 16; flag1 =
    -- done, flag2 = needed first.  Types 0/2: Ezlo speaks once when Link
    -- (with the cap) walks in; type 3 only sets the SELECT hint.
    if m.action == 0 then
      if self:check(m.c0) then m.done = true return end
      m.rx, m.ry = band(m.y, 0xFF) * 8, rshift(m.y, 8) * 8
      m.cx, m.cy = m.rx + band(m.x, 0xFF) * 16, m.ry + rshift(m.x, 8) * 16
      m.msg = m.b32
      m.action = 1
    end
    if m.c1 ~= 0 and not self:check(m.c1) then return end
    if not p.hasCap then return end
    if math.abs(p.x - m.cx) < m.rx and math.abs(p.y - m.cy) < m.ry then
      if m.type == 3 then f.areaHint = m.msg
      elseif m.type == 1 then return
      elseif not f:messageActive() and p.state == "normal" then
        f:message(m.msg, nil, nil, "ezlo")
        self:set(m.c0)
        m.done = true
      end
    end
  elseif m.id == MGR.FALLING_ITEM then
    if m.action == 0 then
      m.action = 1
      if self:check(m.c0) then m.done = true return end
    end
    if self:check(m.c1) then
      local g = f:objects():groundItem(m.type, m.type2, m.x, m.y, { drop = true })
      if g then g.z, g.zv, g.life, g.flagSpec = 48, 0, nil, m.c0 end
      m.done = true
    end
  end
end

-- ---------------------------------------------------------------------------
-- frame
-- ---------------------------------------------------------------------------
function Dungeon:update(input)
  for _, m in ipairs(self.mgrs) do self:updateManager(m) end
  for _, e in ipairs(self.objs) do
    if not e.deleted then
      if e.door then if not e.bossDoor then self:updateDoor(e) end
      elseif e.button then self:updateButton(e)
      elseif e.small or e.big then self:updateChest(e)
      elseif e.statue then self:updateStatue(e, input)
      elseif e.lily then self:updateLily(e)
      elseif e.web or e.dust then self:updateBlocker(e)
      elseif e.heart or e.element or e.warp then self:updateSpecial(e) end
    end
  end
  self:checkFall()
end

-- R: big chests and doors that take a key
function Dungeon:tryAction(p)
  return self:tryBigChest(p) or self:tryDoor(p)
end

return Dungeon
