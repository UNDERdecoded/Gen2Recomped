-- Room code: the per-room C functions the cartridge runs when a room loads
-- (gAreaTable room properties [4..7]: sub_unk*, sub_StateChange_*, in
-- src/roomInit.c).  They are native code, so they cannot be read from the
-- ROM the way scripts are; each one we need is ported by hand here, keyed
-- area * 256 + room, and receives the Field.  Rooms without a port load
-- only their base entity lists ([0], [1], and [2] once TABIDACHI is set).

local RoomCode = {}

local ports = {}

-- Field helpers used by the ports: f:flag(kind, idx[, bank]), f:loadEntityList(addr),
-- f:kinstoneFused(id), f:inventory(item), f.save.progress (gSave.global_progress)

function RoomCode.table()
  return ports
end

-- ids used below (include/flags.h, include/item.h)
local START, OUTDOOR = 0x13, 0x49            -- global: met Zelda / left Link's house
local FLAG_BANK_2 = 0x200
local ITEM_GUST_JAR, ITEM_JABBERNUT = 0x11, 0x5B
local FLAG_BANK_2 = 0x200
local M_PRIEST_TALK, M_ELDER_TALK2ND, KOBITO_MORI_1ST = 0x80, 0x83, 0x8D

local function reg(area, room, fn) ports[area * 256 + room] = fn end

-- sub_StateChange_HouseInteriors2_LinksHouseEntrance
reg(0x22, 0x10, function(f)
  if not f:flag("global", START) then f:loadEntityList(0x080F2E2C) end
end)

-- sub_StateChange_HouseInteriors2_LinksHouseSmith
reg(0x22, 0x11, function(f)
  if not f:flag("global", START) then f:loadEntityList(0x080F2E94)
  else f:loadEntityList(0x080F2EC4) end
end)

-- sub_StateChange_HouseInteriors2_LinksHouseBedroom: Ezlo's list once Link
-- wears the cap (the PL_NO_CAP player flag clears when Ezlo joins).  The
-- intro wake-up (script_PlayerIntro) is not ported: the file starts awake.
-- A new file (neither START nor local flag $46) wakes up here:
-- sub_080751E8(0, 6, &script_PlayerIntro) puts Link in bed (PLAYER_SLEEP,
-- PL_NO_CAP) and runs script_PlayerIntro, which sets local flag $46,
-- shows the wake-up message (TEXT_PROLOGUE 5) and hands control back.
local SCRIPT_PLAYER_INTRO = 0x08009B30
reg(0x22, 0x15, function(f)
  if not f:flag("global", START) and not f:flag("local", 0x46) then
    f:startIntro(SCRIPT_PLAYER_INTRO)
  end
  if f.player and f.player.hasCap then f:loadEntityList(0x080F31D8) end
end)

-- sub_StateChange_MinishWoods_Main (windcrests are not tracked yet: the
-- windcrest's list always loads, as on a file that has not activated it)
local EZERO_1ST, MORI_ENTRANCE_1ST, MORI_00_KOBITO = 0x14, 65, 62
reg(0x00, 0x00, function(f)
  if not f:flag("global", EZERO_1ST) then f:loadEntityList(0x080F4D50) end
  if not f:flag("local", MORI_ENTRANCE_1ST) then
    if not f:flag("local", MORI_00_KOBITO) then f:loadEntityList(0x080F4DB0)
    else f:loadEntityList(0x080F4DD0) end
    f:loadEntityList(0x080F4DF0)
  end
  if f:kinstoneFused(0x4E) then f:loadEntityList(0x080F4F10) end
  f:loadEntityList(0x080F4E10)
end)

-- sub_unk3 / sub_StateChange_HyruleField_SouthHyruleField
local SOUGEN_01_ZELDA, ZELDA_CHASE, TABIDACHI = 112, 28, 0x15
reg(0x03, 0x01, function(f)
  f:setFlag("global", OUTDOOR, true)
  if not f:flag("local", SOUGEN_01_ZELDA) then
    f:loadEntityList(0x080F70A8)
    f:setFlag("global", ZELDA_CHASE, false)
  end
  if not f:flag("global", TABIDACHI) then f.queuedBgm = 0x10 end -- BGM_FESTIVAL_APPROACH
  f:loadEntityList(0x080F70D8)
  if (f.save.progress or 1) > 3 then f:loadEntityList(0x080F7088) end
end)

-- sub_StateChange_HyruleTown_0 -- Hyrule Town (area 2) and, at progress 1,
-- the festival (area $15 uses the same room code): the festival only
-- recolours; the town loads its lists by story stage
local KINSTONE_BAG = 0x67
local LV1_CLEAR, MACHI_MACHIHOKORI, INLOCK, MIZUKAKI_START = 2, 18, 29, 41
local NEW_DIN, NEW_NAYRU, NEW_FARORE, RENT_DIN, RENT_NAYRU, RENT_FARORE, TATEKAKE = 46, 47, 48, 43, 44, 45, 24
local MHOUSE04_DANRO, MHOUSE06_DANRO, MACHI_07_BELL, ROCS_CAPE = 132, 133, 207, 0x14
local function hyruleTown(f)
  local g = function(i) return f:flag("global", i) end
  if (f.save.progress or 1) == 1 then return end
  if not f:flag("bank", MHOUSE04_DANRO, FLAG_BANK_2) then f:loadEntityList(0x080EEB6C) end
  if not f:flag("bank", MHOUSE06_DANRO, FLAG_BANK_2) then f:loadEntityList(0x080EEB8C) end
  if f:inventory(KINSTONE_BAG) == 0 and g(LV1_CLEAR) then f:loadEntityList(0x080EE88C) end
  if not f:kinstoneFused(0x28) then f:loadEntityList(0x080EE8FC) end
  if f:kinstoneFused(0x33) then f:loadEntityList(0x080EE91C) end
  if g(MACHI_MACHIHOKORI) then f:loadEntityList(0x080EE93C) else f:loadEntityList(0x080EECBC) end
  if f:kinstoneFused(0x1B) and f.save.progress > 3 then
    if not (g(NEW_DIN) or g(NEW_NAYRU) or g(NEW_FARORE)) then
      if not (g(RENT_DIN) or g(RENT_NAYRU) or g(RENT_FARORE)) then f:loadEntityList(0x080EE95C)
      elseif not g(TATEKAKE) then f:loadEntityList(0x080EE97C)
      else f:loadEntityList(0x080EE9BC) end
    else
      f:loadEntityList(0x080EE99C)
    end
  end
  if g(RENT_DIN) then f:loadEntityList(0x080EE9FC)
  elseif g(RENT_NAYRU) then f:loadEntityList(0x080EEA1C)
  elseif g(RENT_FARORE) then f:loadEntityList(0x080EEA3C)
  else f:loadEntityList(0x080EE9DC) end
  if f.save.progress > 4 and not f:kinstoneFused(0x0B) and (g(RENT_DIN) or g(RENT_NAYRU) or g(RENT_FARORE)) then
    f:loadEntityList(0x080EEA5C)
  end
  if not f:flag("local", MACHI_07_BELL) and f:inventory(ROCS_CAPE) ~= 0 then f:loadEntityList(0x080EEABC) end
  if f.save.progress > 3 and g(INLOCK) then f:loadEntityList(0x080EEA7C) end
  if f.save.progress < 6 and not g(MIZUKAKI_START) then f:loadEntityList(0x080EEA9C) end
  f:loadEntityList(0x080EEBAC) -- the windcrest (not tracked: never activated)
end
reg(0x02, 0x00, hyruleTown)
reg(0x15, 0x00, hyruleTown)

-- Deepwood Shrine (src/roomInit.c sub_StateChange_DeepwoodShrine_*).  The
-- rooms not listed have empty state-change code; their puzzles run on the
-- managers and objects in their lists (Dungeon.lua).
local LV1_CLEAR_G = 2
local function stt(f, ttype, x, y, layer) f:objects():setTileType(layer or 1, x, y, ttype) end
-- _Madderpillar: the list loads when Link comes in through the upper half
reg(0x48, 0x00, function(f)
  if f.player.y < f.room.height / 2 and not f:flag("local", 0x17) then f:loadEntityList(0x080DE4C8) end
end)
-- _StairsToB1
reg(0x48, 0x02, function(f)
  if not f:flag("local", 0x4B) then f:loadEntityList(0x080DE814)
  elseif not f:flag("local", 0x4C) then
    local props = f.room.maps.header.props
    if props and props[8] then f:loadEntityList(props[8]) end -- gUnk_additional_8_DeepwoodShrine_StairsToB1
    stt(f, 121, 5, 10)
  else
    stt(f, 122, 5, 10)
    if not f:flag("local", 0x24) then stt(f, 115, 5, 8) end
  end
end)
-- _Barrel: gSave.dws_barrel_state picks which ends of the barrel are open
reg(0x48, 0x06, function(f)
  local st = f.save.dwsBarrelState or 0
  if st == 2 then stt(f, 144, 17, 8); stt(f, 144, 11, 16)
  else stt(f, 144, 11, 8); stt(f, 144, 17, 16) end
  if f:flag("local", 0x15) then stt(f, 118, 4, 12, 2) end
  if f:flag("local", 0x16) then stt(f, 118, 24, 12, 2) end
end)
-- DeepwoodShrineBoss_Main: cleared, the room loads its "after" list
reg(0x49, 0x00, function(f)
  if f:flag("global", LV1_CLEAR_G) then
    local props = f.room.maps.header.props
    if props and props[10] then f:loadEntityList(props[10]) end -- gUnk_additional_a
  end
end)

-- sub_StateChange_MinishVillage_Main (the tileset manager part is not ported)
reg(0x01, 0x00, function(f)
  if f:inventory(ITEM_JABBERNUT) == 0 then
    f:loadEntityList(0x080DC390)
    if not f:flag("bank", M_PRIEST_TALK, FLAG_BANK_2) then f:loadEntityList(0x080DC3F0) end
  else
    f:loadEntityList(0x080DC430)
    if f:inventory(ITEM_GUST_JAR) == 0 then f:loadEntityList(0x080DC530) end
  end
  if not f:flag("bank", M_ELDER_TALK2ND, FLAG_BANK_2) and f:inventory(ITEM_GUST_JAR) ~= 0 then
    f:loadEntityList(0x080DC470)
  end
  if not f:flag("local", KOBITO_MORI_1ST) then f:loadEntityList(0x080DC4C0) end
end)

function RoomCode.register(area, room, fn)
  ports[area * 256 + room] = fn
end

return RoomCode
