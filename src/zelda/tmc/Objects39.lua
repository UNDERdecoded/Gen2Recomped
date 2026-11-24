-- Round 39: the last MISC_MANAGER ($0F) types and the darkness of the rooms
-- outside the Temple of Droplets / Royal Crypt / Palace of Winds / DHC.
-- Listed in R37.MODULES.
--
-- CARTRIDGE BEHAVIOUR (src/manager/miscManager.c, src/room.c,
-- src/manager/lightManager.c):
--   * Type7 (Royal Valley): every frame gRoomVars.lightLevel = 0, then for
--     each gUnk_08108354 record {x, y, w, h, level} (to x = $FFFF) whose
--     region holds Link (CheckPlayerInRegion: x - w < px <= x + w, the same
--     for y; room coordinates) lightLevel = its level; the first frame
--     also sets gArea.lightLevel (no fade).  LerpLightLevel moves the shown
--     level 4 a frame toward it.
--   * TypeA (Western Woods North): flag1 == gTextRender.curToken.textIndex
--     (the last message rendered) -> SetFlag(flag2), gone.
--   * TypeD (Deepwood's Madderpillar room, DHC's Darknut rooms): flag2
--     clear -> SetPlayerControl(3); once the room has finished loading,
--     StartPlayerScript(gUnk_08108380[direction]) -- direction = the
--     scroll direction when Link scrolled in, else animationState >> 1 --
--     the walk into the fight; gone.
--   * DARKNESS tile entity (type 9, LoadDarknessTile -> sub_0805BB00(_3, 1)):
--     gArea.lightType 1, gRoomVars.lightLevel = the entity's level byte, a
--     LIGHT_MANAGER; the room is drawn dark (UpdateLightAlpha) with Link's
--     light circle.  It is in Royal Valley, its forest maze, the Minish
--     rafters (cafe / Stockwell), Lake Hylia's north Minish cave, Deepwood's
--     torch room, the Grimblade dojo, Lon Lon Ranch's secret cave and Veil
--     Falls' caves, apart from the areas ToDObjects.DARK_AREAS already
--     covers (ToDObjects.darkRoomInit does the same there).
-- SIMPLIFIED: TypeD uses Link's facing (the port's seamless scroll leaves
-- Link facing the way he walked in, which is the scroll direction).
local RT = require("src.zelda.tmc.RomTables")

local M = {}
M.MISC_MANAGER = 0x0F
local LIGHT_REGIONS = RT.t("Objects39.LIGHT_REGIONS") -- gUnk_08108354
local WALKIN = RT.t("Objects39.WALKIN") -- gUnk_08108380 (4 player scripts)

local function ToD() return require("src.zelda.tmc.ToDObjects") end

-- CheckPlayerInRegion (0x0800293E): x - w < px <= x + w (unsigned compares)
local function inRegion(p, x, y, w, h)
  local px, py = math.floor(p.x), math.floor(p.y)
  return px > x - w and px <= x + w and py > y - h and py <= y + h
end
M.inRegion = inRegion

-- the light ticker (LerpLightLevel), once per room
local function lightTicker(f)
  if f._light39 == f.room then return end
  f._light39 = f.room
  require("src.zelda.tmc.R26").ticker(f._dungeon, function(dd) ToD().lightUpdate(dd.field) end)
end

local function type7(f, m)
  local level = 0
  for i = 0, 15 do
    local r = LIGHT_REGIONS and LIGHT_REGIONS[i]
    if not r or r.x == 0xFFFF then break end
    if inRegion(f.player, r.x, r.y, r.w, r.h) then level = r.level end
  end
  local T = ToD()
  T.install()
  local l = T.light(f)
  l.area = f.room.area
  if l.type == 0 then l.type = 1 end
  l.target = level
  if (m.action or 0) == 0 then
    m.action = 1
    l.level = level
    f.lightLevel = level
  end
  lightTicker(f)
end

local function typeA(d, f, m)
  m.action = 1
  if f._textIndex39 ~= nil and (m.c0 or 0) == f._textIndex39 then
    d:set(m.c1, true)
    m.deleted = true
  end
end

local function typeD(d, f, m)
  if not d:check(m.c1) then
    f.player.control = false -- SetPlayerControl(3)
    if f.transition or f.xfade then return end -- gRoomControls.reload_flags
    local dir = math.floor((f.player.animationState or 4) / 2) % 4
    local ptr = WALKIN and WALKIN[dir]
    if ptr then f:startPlayerScript(ptr) end
  end
  m.deleted = true
end

local function tick(d, m)
  if m.deleted then return end
  local f = d.field
  if m.type == 7 then type7(f, m)
  elseif m.type == 0xA then typeA(d, f, m)
  elseif m.type == 0xD then typeD(d, f, m) end
end
M.tick = tick

local installed
local function install()
  if installed then return end
  installed = true
  -- gTextRender.curToken.textIndex: the last message started
  local Field = require("src.zelda.tmc.Field")
  local message = Field.message
  Field.message = function(self, index, ...)
    self._textIndex39 = index
    return message(self, index, ...)
  end
end
M.install = install

function M.spawnManager(d, m)
  if m.id ~= M.MISC_MANAGER or not (m.type == 7 or m.type == 0xA or m.type == 0xD) then return nil end
  install()
  m.action = 0
  require("src.zelda.tmc.R26").ticker(d, function(dd, me) tick(dd, me) end, m)
  return true
end

-- the DARKNESS tile entity outside ToDObjects.DARK_AREAS
function M.roomInit(f)
  if not (f.room and f.room.area) then return end
  local T = ToD()
  -- ToDObjects.roomInit (R26, before this) already ticks the light when
  -- Link came from a dark room
  if f._todLight and f._todLight.type ~= 0 and f._todLight.area == f.room.area then f._light39 = f.room end
  if T.DARK_AREAS[f.room.area] then return end
  local te9
  for _, te in ipairs(f.room.tileEntities or {}) do if te.type == 9 then te9 = te end end
  local l = f._todLight
  if not te9 then
    -- a lit room: ToDObjects.darkRoomInit already set the level to 256
    -- when Link came from a dark room of the same area
    return
  end
  T.install()
  l = T.light(f)
  if l.area ~= f.room.area then l.type, l.level, l.target, l.radius = 0, 256, 256, 0x11 end
  l.area = f.room.area
  l.type = 1
  l.target = te9.b or 0
  l.level = l.target -- sub_0805BB74(-1)
  f.lightLevel = l.level
  lightTicker(f)
end

return M
