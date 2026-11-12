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

-- sub_StateChange_MinishWoods_Main (the windcrest's list loads until
-- gSave.windcrests has WINDCREST_MINISH_WOODS, Crenel.lua)
-- round 9: flag ids recounted for the USA build (include/flags.h has
-- EU/JP-only entries under #if; the scripts' SetLocalFlag bytes agree)
local EZERO_1ST, MORI_ENTRANCE_1ST, MORI_00_KOBITO = 0x14, 0x3E, 0x3B
reg(0x00, 0x00, function(f)
  if not f:flag("global", EZERO_1ST) then f:loadEntityList(0x080F4D50) end
  if not f:flag("local", MORI_ENTRANCE_1ST) then
    if not f:flag("local", MORI_00_KOBITO) then f:loadEntityList(0x080F4DB0)
    else f:loadEntityList(0x080F4DD0) end
    f:loadEntityList(0x080F4DF0)
  end
  if f:kinstoneFused(0x4E) then f:loadEntityList(0x080F4F10) end
  if not require("src.zelda.tmc.Crenel").windcrest(f, 31) then f:loadEntityList(0x080F4E10) end
end)

-- sub_unk3 / sub_StateChange_HyruleField_SouthHyruleField
-- round 9: SOUGEN_01_ZELDA is $6D (script_ZeldaOutsideLinksHouse sets local
-- $6D); 112 here kept reloading Zelda's list after she had left
local SOUGEN_01_ZELDA, ZELDA_CHASE, TABIDACHI = 0x6D, 28, 0x15
reg(0x03, 0x01, function(f)
  f:setFlag("global", OUTDOOR, true)
  if not f:flag("local", SOUGEN_01_ZELDA) then
    f:loadEntityList(0x080F70A8)
    f:setFlag("global", ZELDA_CHASE, false)
  end
  if not f:flag("global", TABIDACHI) then f.queuedBgm = 0x10 end -- BGM_FESTIVAL_APPROACH
  if not require("src.zelda.tmc.Crenel").windcrest(f, 30) then f:loadEntityList(0x080F70D8) end
  if (f.save.progress or 1) > 3 then f:loadEntityList(0x080F7088) end
end)

-- sub_StateChange_HyruleTown_0 -- Hyrule Town (area 2) and, at progress 1,
-- the festival (area $15 uses the same room code): the festival only
-- recolours; the town loads its lists by story stage
local KINSTONE_BAG = 0x67
local LV1_CLEAR, MACHI_MACHIHOKORI, INLOCK, MIZUKAKI_START = 2, 18, 29, 41
local NEW_DIN, NEW_NAYRU, NEW_FARORE, RENT_DIN, RENT_NAYRU, RENT_FARORE, TATEKAKE = 46, 47, 48, 43, 44, 45, 24
local MHOUSE04_DANRO, MHOUSE06_DANRO, MACHI_07_BELL, ROCS_CAPE = 132, 133, 0xD0, 0x14
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
  if not require("src.zelda.tmc.Crenel").windcrest(f, 27) then f:loadEntityList(0x080EEBAC) end -- the windcrest
end
-- round 15: sub_StateChange_HyruleTown_0 also sets TILE_TYPE_374 at
-- (43, 25) on the bottom layer (USA builds); the festival room has no such line
reg(0x02, 0x00, function(f) hyruleTown(f); stt(f, 374, 43, 25, 1) end)
reg(0x15, 0x00, hyruleTown)

-- round 9: sub_StateChange_CastleGarden_Main (src/roomInit.c).  The
-- ceremony's own lists (gUnk_080F06B0 / 080F06E0) come from the scripts.
local CASTLE_BGM, MAENIWA_00_WARP, SOUGEN_08_TORITSUKI = 0x64, 0x10, 0x9C
local ITEM_FOURSWORD, ITEM_WATER_ELEMENT = 0x06, 0x42
local SPECIAL_TILE_114 = 0x4072
reg(0x07, 0x00, function(f)
  if f:inventory(ITEM_FOURSWORD) ~= 0 then f:loadEntityList(0x080F09A0) end -- sub_unk3: properties[1]
  if not f:flag("global", TABIDACHI) then
    f:loadEntityList(0x080F0650)
    f.queuedBgm = 0x13 -- BGM_BEANSTALK
    f:setFlag("global", CASTLE_BGM, true)
  elseif f:flag("global", CASTLE_BGM) then
    f.queuedBgm = 0x1B -- BGM_HYRULE_CASTLE_NOINTRO
  end
  local function block(x, y) f.room:setTile(1, x, y, SPECIAL_TILE_114) end
  if not f:flag("local", SOUGEN_08_TORITSUKI) then
    f:loadEntityList(0x080F0800)
    block(24, 9); block(24, 10); block(38, 9); block(38, 10)
  else
    if f:inventory(ITEM_FOURSWORD) == 0 then
      f:loadEntityList(0x080F08F0)
      block(30, 2); block(31, 2); block(32, 2)
    end
    f:loadEntityList(0x080F0850)
    if f:inventory(ITEM_WATER_ELEMENT) == 0 then f:loadEntityList(0x080F0870) else f:loadEntityList(0x080F0890) end
    block(24, 9); block(24, 10)
    if f:flag("local", MAENIWA_00_WARP) then
      f:loadEntityList(0x080F0920)
      f:setFlag("local", MAENIWA_00_WARP, false)
    end
  end
end)

-- round 9: sub_unk3 / sub_StateChange_HyruleCastle_4: Link wakes up in the
-- castle after the ceremony (script_PlayerWakingUpInHyruleCastle), and
-- sub_StateChange_HyruleCastle_2: the assembly's list by story stage
local CASTLE_04_MEZAME, ENDING = 0x9F, 0x51
reg(0x80, 0x04, function(f)
  if not f:flag("local", CASTLE_04_MEZAME) then
    f:setFlag("global", ZELDA_CHASE, false)
    f.zeldaFollower = nil
    f:startIntro(0x08009E88, 0xB0, 0x40)
  end
  if f:flag("global", TABIDACHI) and f:flag("global", CASTLE_BGM) then f.queuedBgm = 0x1B end
end)
reg(0x80, 0x02, function(f)
  if f:flag("global", CASTLE_BGM) then f.queuedBgm = nil end
  if f:flag("global", ENDING) then f:loadEntityList(0x080D7618)
  elseif not f:flag("global", TABIDACHI) then f:loadEntityList(0x080D74C8); f.queuedBgm = 0x1B
  elseif not f:flag("global", LV1_CLEAR) then f:loadEntityList(0x080D7588)
  else f:loadEntityList(0x080D75D8) end
end)

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

-- round 16: sub_StateChange_DeepwoodShrineEntry_Main: out of the shrine
-- with the Earth Element (LV1_CLEAR) and Ezlo has not spoken yet
-- (LV1_CLEAR_MES, bank 1 flag 1): gUnk_080DFB78 (script_EzloTalkDWS)
reg(0x4A, 0x00, function(f)
  if f:flag("global", LV1_CLEAR_G) and not f:flag("bank", 1, 0x100) then f:loadEntityList(0x080DFB78) end
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

-- round 6: Mt. Crenel (roomInit.c sub_StateChange_MtCrenel_*)
local G_LV2_CLEAR, G_ENDING, G_WHITE_SWORD_END, ITEM_GREEN_SWORD = 0x03, 0x51, 0x56, 0x02
-- MountainTop: its list unless the ending plays there
reg(0x06, 0x00, function(f)
  if not f:flag("global", G_ENDING) then f:loadEntityList(0x080FACB8) end
end)
-- CaveOfFlamesEntrance: after the Cave of Flames (LV2_CLEAR, local LV1_CLEAR
-- clear) its list; the windcrest's list until WINDCREST_MT_CRENEL; the
-- green sword sets WHITE_SWORD_END
reg(0x06, 0x02, function(f)
  if f:flag("global", G_LV2_CLEAR) and not f:flag("local", 0x02) then f:loadEntityList(0x080FAFE4) end
  if not require("src.zelda.tmc.Crenel").windcrest(f, 24) then f:loadEntityList(0x080FB004) end
  if f:inventory(ITEM_GREEN_SWORD) ~= 0 then f:setFlag("global", G_WHITE_SWORD_END, true) end
end)
-- round 8: sub_StateChange_MelarisMine_Main: Melari and his list until
-- WHITE_SWORD_END, the Minish at the exit until YAMAKOBITO_OPEN (then the
-- moved one), KOBITO_YAMA_ENTER
reg(0x10, 0x00, function(f)
  if not f:flag("global", 0x56) then f:loadEntityList(0x080DD214) end
  if not f:flag("local", 0x7F) then f:loadEntityList(0x080DD274) else f:loadEntityList(0x080DD294) end
  f:setFlag("local", 0x8E, true)
end)
-- sub_StateChange_CrenelMinishPaths_MelarisMine: the white sword ends the
-- forge scene (WHITE_SWORD_END)
reg(0x12, 0x03, function(f)
  if (f:inventory(0x02) or 0) ~= 0 then f:setFlag("global", 0x56, true) end
end)
-- round 8: sub_StateChange_CaveOfFlamesBoss_Main: BG1 is the lava under the
-- sprites during the fight (gMapTop.bgSettings); after LV2_CLEAR it is
-- turned off and list a (warp point, heart container spot) loads
reg(0x51, 0x00, function(f)
  if f:flag("global", 0x03) then
    f.room.hideTop = true
    f:loadEntityList(0x080E1814)
  else
    f.room.topUnder = true
  end
end)
-- Entrance: TILE_TYPE_374 at (47, 25) on the bottom layer (USA)
reg(0x06, 0x04, function(f) stt(f, 374, 47, 25, 1) end)

function RoomCode.register(area, room, fn)
  ports[area * 256 + room] = fn
end

-- round 10: the route's rooms after the castle (RouteRooms.lua)
require("src.zelda.tmc.RouteRooms")(RoomCode)

return RoomCode
