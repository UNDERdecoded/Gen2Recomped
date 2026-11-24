-- Round 34: DIGGING_CAVE_ENTRANCE_MANAGER ($04,
-- src/manager/diggingCaveEntranceManager.c) and the dig-cave room change
-- (scroll.c Scroll5, sub_0807C810, sub_08080368, entity.c sub_0805E248).
-- The round 27 survey listed the manager in 17 rooms; the port never made
-- it, so a hole dug with the Mole Mitts led nowhere.  In R34.MODULES
-- (spawnManager / frame).
--
-- CARTRIDGE BEHAVIOUR:
--   * diggingCaveEntrances[area] (the table below, from the .c source):
--     {sourceTilePos, sourceRoom, type, targetArea, targetRoom,
--     targetTilePos}; a tile position is x + y * 64.
--   * UpdateIsDiggingCave: the dig-cave areas $0C $0F $13 $14 $16 $17 $19.
--   * Init, in a dig cave: SPECIAL_TILE_128 at the row under every entrance
--     of the room (x - 1 .. x + 1, y + 1, bottom layer).
--   * Action1 (CheckEnterEntrance), outside a cave: Link's tile is the
--     entrance's and Link's y < the tile's top + 6.  In a cave: dx = Link x
--     - (tile x * 16 + 8), Y2 = tile y * 16 + $18; enters when |dx| <= $18
--     and |y - Y2| <= 8, unless y < Y2 and |dx| <= $C.
--   * EnterEntrance: offsetX = Link x - tile x * 16, offsetY = Link y - tile
--     y * 16 (both from the room's origin); the scroll action 5: Link faces
--     north (south when leaving a cave), the window closes in steps of 6
--     round the camera target; sub_0807C810 puts Link at the target tile +
--     the offsets; sub_08080368 puts back the tiles the field had changed
--     (dug walls) when Link comes back to the area he left; sub_0805E248
--     draws the hole at the target tile (TILE_TYPE_620..629, Veil Falls
--     636..645); the window opens again.
-- SIMPLIFIED: the window is the field's iris (a circle, 6 a frame) instead
--   of WIN1's ellipse; the cave border map data (gCaveBorderMapData) is not
--   loaded (the room's own map is drawn).
local bit = require("bit")
local band = bit.band

local M = {}
M.MANAGER = 0x04
M.SPECIAL_TILE_128 = 0x4080
local function TP(x, y) return x + y * 64 end

-- diggingCaveEntrances (diggingCaveEntranceManager.c)
-- { source tile, source room, target area, target room, target tile }
M.ENTRANCES = require("src.zelda.tmc.RomTables").t("DigCave34.ENTRANCES")
M.CAVE_AREAS = { [0x0C] = true, [0x0F] = true, [0x13] = true, [0x14] = true, [0x16] = true, [0x17] = true,
                 [0x19] = true }
local HOLE = { { -1, -1, 1, 620 }, { -1, -1, 2, 627 }, { 0, -1, 1, 621 }, { 0, -1, 2, 628 }, { 1, -1, 1, 622 },
               { 1, -1, 2, 629 }, { -1, 0, 1, 623 }, { 0, 0, 1, 624 }, { 1, 0, 1, 626 } }       -- sub_0805E248
local HOLE_VEIL = { { -1, -1, 1, 636 }, { -1, -1, 2, 643 }, { 0, -1, 1, 637 }, { 0, -1, 2, 644 }, { 1, -1, 1, 638 },
                    { 1, -1, 2, 645 }, { -1, 0, 1, 639 }, { 0, 0, 1, 640 }, { 1, 0, 1, 642 } }
M.HOLE, M.HOLE_VEIL = HOLE, HOLE_VEIL
M.STEP = 6

local function tileXY(pos) return band(pos, 0x3F), math.floor(band(pos, 0xFC0) / 64) end
M.tileXY = tileXY

-- the room's entrances
function M.forRoom(area, room)
  local out = {}
  for _, en in ipairs(M.ENTRANCES[area] or {}) do if en[2] == room then out[#out + 1] = en end end
  return out
end

-- CheckEnterEntrance
function M.check(px, py, en, inCave)
  local tx, ty = tileXY(en[1])
  px, py = math.floor(px), math.floor(py)
  if inCave then
    local dx = px - (tx * 16 + 8)
    local y2 = ty * 16 + 0x18
    if dx + 0x18 > 0x30 or dx + 0x18 < 0 then return false end
    local dy = py - y2 + 8
    if dy > 0x10 or dy < 0 then return false end
    if py < y2 and dx + 0xC <= 0x18 and dx + 0xC >= 0 then return false end
    return true
  end
  if math.floor(px / 16) ~= tx or math.floor(py / 16) ~= ty then return false end
  return py < ty * 16 + 6
end

-- the tiles the room changed from its ROM map (sub_08080278's list)
local function diffs(f)
  local r = f.room
  local orig = f.assets:roomMaps(r.area, r.room)
  local out = {}
  if not orig then return out end
  for li, name in ipairs({ "bottom", "top" }) do
    local o, c = orig[name] or {}, r.maps[name] or {}
    for i = 0, r.tw * r.th - 1 do
      if c[i] ~= o[i] and c[i] then out[#out + 1] = { li, i, c[i] } end
    end
  end
  return out
end
M.diffs = diffs

function M.spawnManager(d, m)
  if m.id ~= M.MANAGER then return nil end
  local f = d.field
  local r = f.room
  local cave = M.CAVE_AREAS[r.area] or false
  local s = { room = r, cave = cave, list = M.forRoom(r.area, r.room) }
  if cave then
    for _, en in ipairs(s.list) do
      local tx, ty = tileXY(en[1])
      for dx = -1, 1 do
        local x, y = tx + dx, ty + 1
        if x >= 0 and y >= 0 and x < r.tw and y < r.th then r:setTile(1, x, y, M.SPECIAL_TILE_128) end
      end
    end
  end
  f.dig34 = s
  return true
end

local function enter(f, en)
  local p = f.player
  local tx, ty = tileXY(en[1])
  local g = f.digState34 or {}
  g.previousArea = g.currentArea
  g.currentArea = f.room.area
  g.saved = { area = f.room.area, room = f.room.room, list = diffs(f) }
  f.digState34 = g
  f.digT34 = { en = en, offX = p.x - tx * 16, offY = p.y - ty * 16, leaving = f.dig34 and f.dig34.cave,
               phase = "close" }
  p.animationState = f.digT34.leaving and 4 or 0
  p.moving = false
  f:fadeIris(true, M.STEP)
end

local function arrive(f, t)
  local en = t.en
  local tx, ty = tileXY(en[5])
  local x, y = tx * 16 + t.offX, ty * 16 + t.offY
  f:enterRoom(en[3], en[4], x, y, t.leaving and 4 or 0)
  local r = f.room
  -- sub_08080368: back to the area left before -> its changed tiles
  local g = f.digState34 or {}
  local sv = g.saved
  if sv and sv.area == r.area and sv.room == r.room then
    for _, c in ipairs(sv.list) do
      local i = c[2]
      r:setTile(c[1], i % r.tw, math.floor(i / r.tw), c[3])
    end
  end
  -- sub_0805E248
  local O = f:objects()
  local hole = (r.area == 0x0A or r.area == 0x16) and HOLE_VEIL or HOLE
  for _, h in ipairs(hole) do
    local x2, y2 = tx + h[1], ty + h[2]
    if x2 >= 0 and y2 >= 0 and x2 < r.tw and y2 < r.th then O:setTileType(h[3], x2, y2, h[4]) end
  end
  f:fadeIris(false, M.STEP)
end
M.arrive = arrive

function M.frame(f)
  local t = f.digT34
  if t then
    if t.phase == "close" then
      if not (f.iris and f.iris.active) then t.phase = "open"; arrive(f, t) end
      return true
    end
    if not (f.iris and f.iris.active) then f.digT34 = nil end
    return false
  end
  local s = f.dig34
  if not s then return false end
  if s.room ~= f.room then f.dig34 = nil return false end
  local p = f.player
  if not p or p.state ~= "normal" or f.transition or f.textbox then return false end
  for _, en in ipairs(s.list) do
    if M.check(p.x, p.y, en, s.cave) then enter(f, en) return true end
  end
  return false
end

return M
