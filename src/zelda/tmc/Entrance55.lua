-- Round 55: MINISH_SIZED_ENTRANCE_MANAGER ($21, src/manager/minishSizedEntranceManager.c)
-- -- the Minish-sized holes of Hyrule Town (its only user: Entities_HyruleTown_0_1, paramA $E).
--
-- CARTRIDGE BEHAVIOUR:
--   * Main: the room property `type` is a list of MinishEntranceSpawnData {u16 x, u16 y, u16 cond,
--     u16 timer} (room coordinates) ending at x == 0, at most 32.  Each frame, for each entry:
--     CheckRectOnScreen(x, y, 4, 4) ($0800290E: x - (scroll_x - origin_x - 4) < 248 and
--     y - (scroll_y - origin_y - 4) < 168, unsigned) -> if its bit in field_0x20 is clear and
--     sub_0805B8CC(cond) (4: global TATEKAKE_HOUSE; 5 / 6: never; else always) ->
--     CreateObject(MINISH_SIZED_ENTRANCE, 1, 0) with timer = entry.timer (the exit's room
--     property), subtimer = the entry's index, at (x, y), parent = the manager,
--     ResolveCollisionLayer, and the bit is set.  Off screen -> the bit is cleared.
--   * The object (type 1, minishSizedEntrance.c Action1) deletes itself once its bit in the
--     parent's field_0x20 is clear; otherwise Minish Link within 4 px at z 0 holding UP
--     (type2 0) runs DoExitTransition(GetCurrentRoomProperty(timer)) (FoWObjects.spawnEntrance).
--   * Hyrule Town's first entry (292, 80) by the library yard's stairs leads (property $20,
--     INSTANT_MINISH) to Library 2F (0x48, 0x8E): the Minish way into the library, whose
--     SPECIAL_WARP region (0x48, 0x34) then takes Minish Link into the bookshelf ($2D:10).
-- The lists are read from the player's ROM (the room's entity region) at run time.
local bit = require("bit")
local band, bor, bnot, lshift = bit.band, bit.bor, bit.bnot, bit.lshift

local M = {}
M.MGR_ID, M.OBJ_ID, M.TATEKAKE_HOUSE = 0x21, 0x4E, 0x18

local function u16(b, o) return (b:byte(o + 1) or 0) + (b:byte(o + 2) or 0) * 256 end

local function u32(b, o) return u16(b, o) + u16(b, o + 2) * 65536 end

-- The importer keeps room properties 8 .. 31 (Extract.lua); Hyrule Town's room header runs to $2F+
-- (its Minish-hole exits are properties $20 .. $2C).  GetCurrentRoomProperty(k) reads word k of the
-- room header: find the header in the player's ROM (the entity region holds it) by its words 8 .. 15
-- and read the words past 31 from there.
function M.extendProps(f)
  local h = f.room and f.room.maps and f.room.maps.header
  local props = h and h.props
  if not props or h._ext55 ~= nil then return end
  h._ext55 = false
  local A = f.assets
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  local b, reg = A.entityBlob, A.manifest.entityRegion
  if not reg then return end
  local parts = {}
  for k = 8, 15 do
    local v = props[k]
    if not v then return end
    parts[#parts + 1] = string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  local at = b:find(table.concat(parts), 1, true)
  if not at then return end
  local hdr = at - 1 - 32
  if hdr < 0 then return end
  for k = 32, 63 do
    local q = hdr + 4 * k
    if q + 4 > #b then break end
    local v = u32(b, q)
    if v < 0x08000000 or v >= 0x0A000000 then break end
    props[k] = v
  end
  h._ext55 = reg.base + hdr
end

-- the room property's spawn list
function M.list(f, k)
  M.extendProps(f)
  local props = f.room and f.room.maps and f.room.maps.header and f.room.maps.header.props
  local addr = props and props[k]
  if not addr then return nil end
  local A = f.assets
  A.entityBlob = A.entityBlob or A.store:read("entities.bin") or ""
  local b, reg = A.entityBlob, A.manifest.entityRegion
  if not reg then return nil end
  local o = addr - reg.base
  local out = {}
  for i = 0, 31 do
    local q = o + 8 * i
    if q < 0 or q + 8 > #b then break end
    local x = u16(b, q)
    if x == 0 then break end
    out[#out + 1] = { x = x, y = u16(b, q + 2), cond = u16(b, q + 4), timer = u16(b, q + 6) }
  end
  return out
end

-- sub_0805B8CC
function M.cond(f, c)
  if c == 4 then return f:flag("global", M.TATEKAKE_HOUSE) and true or false end
  if c < 5 then return true end
  if c > 6 then return true end
  return false
end

-- CheckRectOnScreen (room coordinates; camX / camY = scroll - origin)
function M.rectOnScreen(f, x, y, w, h)
  local cx, cy = math.floor(f.camX or 0), math.floor(f.camY or 0)
  local dx = x - (cx - w)
  local dy = y - (cy - h)
  return dx >= 0 and dx < 2 * w + 240 and dy >= 0 and dy < 2 * h + 160
end

local function spawnOne(f, m, i, s)
  local e = f:spawn({ kind = 6, id = M.OBJ_ID, paramA = 1, paramB = band(s.timer, 0xFF) * 256, paramC = 0,
                      pool = 0, x = s.x, y = s.y, collision = 0 })
  if not e then return nil end
  e.mse55, e.mse55bit = m, i
  local up = e.extUpdate
  e.extUpdate = function(dd, me, input)
    -- Action1 (type 1): the parent's bit gone -> DeleteThisEntity
    if band(m.f20 or 0, lshift(1, me.mse55bit)) == 0 then me.deleted = true; me.hidden = true return end
    if up then return up(dd, me, input) end
  end
  return e
end

function M.tick(f, m)
  if not m.list then m.list = M.list(f, m.type) or {} end
  m.f20 = m.f20 or 0
  for i, s in ipairs(m.list) do
    local b = lshift(1, i - 1)
    if M.rectOnScreen(f, s.x, s.y, 4, 4) then
      if band(m.f20, b) == 0 and M.cond(f, s.cond) then
        if spawnOne(f, m, i - 1, s) then m.f20 = bor(m.f20, b) end
      end
    else
      m.f20 = band(m.f20, bnot(b))
    end
  end
end

-- R37 interface
function M.spawnManager(d, m)
  if m.id ~= M.MGR_ID then return nil end
  m.f20 = 0
  require("src.zelda.tmc.R26").ticker(d, function(dd, me) if not me.deleted then M.tick(dd.field, me) end end, m)
  return true
end

return M
