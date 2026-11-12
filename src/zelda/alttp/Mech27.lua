-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DUNGEON MECHANICS (round 27, team B, group d): the Swamp Palace's water,
-- conveyors and the moving floor, spike floors, bombable floors and
-- Kholdstare's shell -- the SNES routines the GBA keeps (zelda3 names), run
-- through Dungeons26.lua's registry and install wraps. GBA tables are read
-- at import (OFF, found by value: r27b/py/tabfind.py; code read with
-- r27b/py/tdis.py):
--
-- WATER (Swamp Palace)
--   0x21 Sprite_21_WaterSwitch (rooms 0x35, 0x37, 0x76): PushSwitch_Draw's
--        five OBJs per frame sprite_D (kPushSwitch_Oam, GBA 0x17CAD0: the
--        GBA's chars 0xBC / 0xBD / 0x9A... differ from the SNES), wiggling
--        by (sprite_B >> 2) & 3 while pushed; Link's box against the
--        kPushSwitch_WH box (0x17CB70) at kPushSwitch_Oam[D * 4] (the
--        cartridge's own index), Link right of it (y + 19) facing left ->
--        sprite_C. Ai 0: pushed 48 frames (sprite_B); ai 1: ten steps of
--        kPushSwitch_Delay / kPushSwitch_Dir (0x17CABC / 0x17CAC6), then
--        dung_flag_statechange_waterpuzzle (game.waterFlag).
--   The tag routines (kDungTagroutines, GBA table 0x152AC4): 0x18
--        RoomTag_WaterOff (0x0807A784, room 0x76) -> submodule 0x0C on the
--        GBA (SNES 11, Module07_0B_DrainSwampPool), 0x19 RoomTag_WaterOn
--        (0x0807A870, rooms 0x35 / 0x37; sets the counter at +0xACA to 1)
--        -> submodule 0x0D (SNES 12, Module07_0C_FloodSwampWater), 0x1A
--        RoomTag_WaterGate (0x0807A8EC, the dam room 0x10B) -> SNES 13
--        Module07_0D_FloodDam; 0x1B (room 0x28) is empty. All set
--        dung_savegame_state_bits 0x800 (our mem.water) and clear tag 1.
--   Flood: four frames (WaterFlood_BuildOneQuadrantForVRAM), five steps of
--        Dungeon_AdjustWaterVomit (kPredefinedTileData +0x1664, 1..5 rows
--        under the water face, every 4 frames), the stream (window x =
--        var0 +- var3 - 1 with kTurnOnWater_Tab0 / Tab1, its bottom growing
--        by var5 until var5 >= 0x688 - BG2VOFS - 0x24), then the pool
--        (var2 / var3 + 1 every 8 frames up to var4; the last vomit rows
--        +0x168C / +0x16B4), dung_hdr_bg2_properties 7 and
--        Dungeon_SetAttrForActivatedWater (the stair attributes). Window
--        values from the 0xDA object (RoomDraw: var0 = x * 8 + w * 16,
--        var1 = y * 8 + h * 16 - 8, var3 = w * 16 - 24, var4 = h * 16 - 8,
--        w / h = size + 2).
--   Drain: the plug (DrawWaterThing, +0x1438) on BG2, the window shrinks
--        (var2 / var3 - 1 every 8 frames down to var4), then
--        Dungeon_SetAttrForActivatedWaterOff (stairs 0x1D), the lower map
--        filled with +0x1E0 and four more frames.
--   Dam (0x10B): kWatergateLayout (GBA 0x16341C, six
--        entries on the GBA, five in zelda3) floods the lower map
--        (RoomTag_OperateWaterFlooring, +0x110 blocks), FloodDam_Expand
--        redraws the gate every 16 frames (+0x12F8 / 0x1348 / 0x1398 /
--        0x13E8, 10 x 4), FloodDam_Fill grows the water until it reaches
--        line 225. It sets save_dung_info[0x28] |= 0x100 (our
--        memory[0x28].dam, progress.swampDam).
--   Room load: the 0xDA rooms without 0x800 have dung_hdr_bg2_properties 0
--        (the water layer under BG2), the 0xD8 room with it is drained
--        (plug drawn, no water), 0x28 (tag 1 = 0x1B) without the dam has
--        properties 0, its water face closed, its submerged stairs dry and
--        its ladder inactive; the water face (subtype-3 0x00) is open
--        (RoomDraw_WaterHoldingObject, +0x162C, 5 rows) when tag 1 is 0x19
--        and 0x800, or 0x1B and the dam. Stair attributes as
--        Dungeon_LoadObjectAttribute writes them (subtype-2 0x33 / 0x35 /
--        0x36, subtype-3 0x33: dry 0x1D1D / 0x3D3D stairs, wet 0x03 / 0x0A
--        / 0x08 ladders).
-- CONVEYORS AND THE MOVING FLOOR
--   TileBehavior_Conveyor 0x68-0x6B: Link_ApplyConveyor (kMovePosDirFlag /
--        kMovingBeltY / X, GBA 0x167DDE / 0x167DE2 / 0x167DE6: 8 << 4
--        sub-pixels a frame), not in the air, recoiling or dashing that
--        way at full speed; sprites (Sprite_CheckTileProperty(k, 0x68):
--        x + 8, y + 12) one pixel every other frame (Sprite_ApplyConveyor).
--   Overlord 0x07 Overlord07_MovingFloor (rooms 0x29, 0x3E): 32 frames
--        still, then (rnd & (x_lo ? 3 : 1)) * 2 for rnd & 127 + 128 frames;
--        stops when slot 0 explodes. LayerEffect_Scroll (header effect 2):
--        0x80 sub-pixels a frame, flags & 2 negative, < 4 horizontal,
--        BG1 (our "bg3") scrolled by dung_floor_x / y_offs;
--        Link_HandleMovingFloor carries Link (header collision != 0, on the
--        ground, the upper table 0x1C and the shifted lower table 0x0C).
-- SPIKES
--   TileBehavior_SpikeFloor 0x0D under (x + 8, y + 20): 8 damage, no
--        recoil, unless the cape, a Byrna spark or the blink; the moon
--        pearl ends a bunny (flags: M.spikeFlags). TileBehavior_Spike
--        0x44 in the movement probes (on the y & 4 rule): 8 damage and
--        LinkApplyTileRebound (kDashTab6Y / X, GBA 0x167E6F / 0x167E73;
--        incapacitated 24, z speed 36). Neither once the room is beaten
--        (0x8000). No spike-floor trap tag exists in kDungTagroutines.
-- BOMB FLOORS
--   Bomb_CheckForDestructibles: attribute 0x62 in the 3 x 3 cells (step
--        2) round the bomb -> ThievesAttic_DrawLightenedHole: the four
--        bomb-floor segments get kPredefinedTileData +0x5BA (the hole); in
--        room 0x65 dung_savegame_state_bits 0x1000 (memory[0x65].light,
--        RoomObjects' Blind light) and the hole stays.
-- KHOLDSTARE
--   Kholdstare Shell - BG2 (subtype-3 0x15, room 0xDE, 10 x 8 words on the
--        lower map): KholdstareShell_PaletteFiltering ends with TS_copy 0;
--        when the shell is gone its cells are the GBA's blank word
--        (RoomObjects' blankWord), and it is not drawn once the boss is
--        beaten; the floor shake (dung_floor_x_offs +-1) moves that map.
--
-- OURS: no sound, no palette fades; the HDMA windows are rectangles in
-- room pixels (love scissor) and the screen-line limits (0x688 - BG2VOFS -
-- 0x24, line 225) use the room camera; the flood shows the water layer
-- blended at property 7 from the stream on; the dam's window is its column
-- only; the drained room's (0xD8 with 0x800) lower map is filled as
-- Module07_0B fills it; the conveyor uses one probe (x + 8, y + 16) and the
-- moving floor (x + 8, y + 20); sprites do not ride the moving floor; the
-- water switch has no barrier (the GBA's PushSwitch_Draw 0x0810B2D2..
-- 0x0810B40E checks the boxes, then only NullifyHookshotDrag,
-- link_speed_setting 0 and Sprite_RepelDash): Link must stay 48 frames in
-- the handle's box facing left; the
-- kTurnOnWater / kTurnOffWater / kConveyorAdjustment constants are the
-- SNES code's (their GBA copies are not unique by value); Link does not
-- swim indoors (Swim.lua is outdoors): deep water 0x08 stays solid to him.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = { NAME = "mech27" }

M.OFF = {
  tagRoutines = 0x152AC4,   -- kDungTagroutines (64 Thumb pointers)
  pushOam = 0x17CAD0,       -- kPushSwitch_Oam (40 x {x, y, char, flags})
  pushDelay = 0x17CABC,     -- kPushSwitch_Delay (10)
  pushDir = 0x17CAC6,       -- kPushSwitch_Dir (10)
  pushWH = 0x17CB70,        -- kPushSwitch_WH (16)
  gateLayout = 0x16341C,    -- kWatergateLayout (17)
  beltFlag = 0x167DDE, beltY = 0x167DE2, beltX = 0x167DE6,   -- Link_ApplyConveyor
  reboundY = 0x167E6F, reboundX = 0x167E73,                  -- LinkApplyTileRebound kDashTab6Y / X
  flags2 = 0x2275A4,        -- kSpriteInit_Flags2 (243; 0x80 = harmless contact)
}
-- kPredefinedTileData byte offsets (Dungeons26 D.OFF.pred)
M.PRED = { water = 0x110, blank = 0x1E0, plug = 0x1438, face = 0x162C, vomit = 0x1664, vomit2 = 0x168C,
           vomit3 = 0x16B4, gate = { 0x12F8, 0x1348, 0x1398, 0x13E8 }, hole = 0x5BA }
M.TAG = { off = 0x18, on = 0x19, gate = 0x1A, dam = 0x1B }
M.SWITCH = 0x21
M.TYPES = { [0x21] = true }
M.FIGHTS = {}

-- code constants (zelda3)
M.TURN_ON0 = { [0] = 1, -1, 1, -1 }     -- kTurnOnWater_Tab0
M.TURN_ON1 = { [0] = 1, 2, 1, -1 }      -- kTurnOnWater_Tab1
M.TURN_ON2 = { [0] = 1, 1, 1, -1 }      -- kTurnOnWater_Tab2
M.TURN_OFF = { [0] = -1, -1, -1, 1 }    -- kTurnOffWater_Tab0 (period 4)
M.CONVEY = { [0x68] = { 0, -1 }, [0x69] = { 0, 1 }, [0x6A] = { -1, 0 }, [0x6B] = { 1, 0 } }   -- kConveyorAdjustment
M.SPIKE_FLOOR, M.SPIKE = 0x0D, 0x44
M.BOMB_FLOOR = 0x62
M.MOVING_FLOOR = 0x07

local function s8(v) return v >= 128 and v - 256 or v end

-- ------------------------------------------------------------ import
-- the objects of a room this module needs (the room object list as
-- Extract.roomSpecials walks it, with the subtype-1 water objects too)
local function roomObjects(rom, p)
  local out = {}
  if not p then return out end
  local o = p + 2
  for layer = 1, 3 do
    for _ = 1, 400 do
      local b0, b1, b2 = rom:u8(o), rom:u8(o + 1), rom:u8(o + 2)
      if (b0 == 0xF0 or b0 == 0xFF) and b1 == 0xFF then o = o + 2 break end
      o = o + 3
      local e
      if band(b0, 0xFC) == 0xFC then
        local id = band(b2, 0x3F)
        if id == 0x33 or id == 0x35 or id == 0x36 or id == 0x37 then
          e = { s = 2, id = id, x = lshift(band(b0, 3), 4) + rshift(b1, 4), y = lshift(band(b1, 15), 2) + rshift(b2, 6) }
        end
      elseif b2 >= 0xF8 then
        local id = lshift(band(b2, 7), 4) + lshift(band(b1, 3), 2) + band(b0, 3)
        if id == 0x00 or id == 0x33 or id == 0x15 then e = { s = 3, id = id, x = rshift(b0, 2), y = rshift(b1, 2) } end
      elseif b2 == 0xD8 or b2 == 0xDA then
        e = { s = 1, id = b2, x = rshift(b0, 2), y = rshift(b1, 2), w = band(b0, 3), h = band(b1, 3) }
      end
      if e then e.layer = layer; out[#out + 1] = e end
    end
    for _ = 1, 64 do
      local w = rom:u16(o)
      o = o + 2
      if w == 0xFFFF then break end
    end
  end
  return out
end

function M.extract(rom, R, check, D)
  local O = M.OFF
  local t = { pushOam = {}, pushDelay = rom:bytesU8(O.pushDelay, 10), pushDir = rom:bytesU8(O.pushDir, 10),
              pushWH = rom:bytesU8(O.pushWH, 16), gateLayout = {},
              beltFlag = rom:bytesU8(O.beltFlag, 4), beltY = D.s8(rom:bytesU8(O.beltY, 4)),
              beltX = D.s8(rom:bytesU8(O.beltX, 4)), reboundY = D.s8(rom:bytesU8(O.reboundY, 4)),
              reboundX = D.s8(rom:bytesU8(O.reboundX, 4)), pred = {}, rooms = {}, tags = {} }
  t.switchFlags2 = rom:u8(O.flags2 + M.SWITCH)
  check(rom:u8(O.flags2) == 1 and rom:u8(O.flags2 + 3) == 0x82 and t.switchFlags2 == 0xA5, "kSpriteInit_Flags2")
  for i = 0, 39 do
    local p = O.pushOam + i * 4
    t.pushOam[i] = { s8(rom:u8(p)), s8(rom:u8(p + 1)), rom:u8(p + 2), rom:u8(p + 3) }
  end
  check(t.pushDelay[1] == 40 and t.pushDelay[10] == 12 and t.pushDir[10] == 6 and t.pushWH[1] == 8 and t.pushWH[14] == 3
        and t.pushOam[0][1] == 4 and t.pushOam[0][2] == 20 and t.pushOam[10][1] == -8 and t.pushOam[4][4] == 0x20,
        "kPushSwitch_Oam / Delay / Dir / WH")
  -- kWatergateLayout: 3-byte entries to 0xFFFF (the GBA's has six; zelda3's five)
  for i = 0, 63 do
    local p = O.gateLayout + i * 3
    if rom:u16(p) == 0xFFFF then break end
    local e = t.gateLayout
    e[#e + 1], e[#e + 2], e[#e + 3] = rom:u8(p), rom:u8(p + 1), rom:u8(p + 2)
  end
  check(#t.gateLayout == 18 and t.gateLayout[1] == 0x1B and t.gateLayout[2] == 0xA1 and t.gateLayout[17] == 0x72,
        "kWatergateLayout")
  check(t.beltFlag[1] == 8 and t.beltY[1] == -8 and t.beltY[2] == 8 and t.beltX[3] == -8 and t.beltX[4] == 8
        and t.reboundY[1] == 24 and t.reboundY[2] == -24 and t.reboundX[3] == 24, "kMovingBelt / kDashTab6")
  -- kDungTagroutines: 0x18-0x1A are code pointers (Thumb)
  for i = 0x18, 0x1B do t.tags[i] = rom:u32(O.tagRoutines + i * 4) end
  check(t.tags[0x18] == 0x0807A785 and t.tags[0x19] == 0x0807A871 and t.tags[0x1A] == 0x0807A8ED
        and rom:u32(O.tagRoutines + 1 * 4) == rom:u32(O.tagRoutines + 11 * 4), "kDungTagroutines (water tags)")
  -- kPredefinedTileData words
  local P = D.OFF.pred
  local function words(off, n) local w = {} for i = 1, n do w[i] = rom:u16(P + off + (i - 1) * 2) end return w end
  local Pd = M.PRED
  t.pred.water = words(Pd.water, 8)
  t.pred.blank = rom:u16(P + Pd.blank)
  t.pred.plug = words(Pd.plug, 16)
  t.pred.face = words(Pd.face, 20)
  t.pred.vomit = words(Pd.vomit, 20)
  t.pred.vomit2 = words(Pd.vomit2, 20)
  t.pred.vomit3 = words(Pd.vomit3, 20)
  t.pred.gate = {}
  for i, off in ipairs(Pd.gate) do t.pred.gate[i] = words(off, 40) end
  t.pred.hole = words(Pd.hole, 16)
  check(t.pred.water[1] == t.pred.water[3] and t.pred.water[2] == t.pred.water[1] + 1 and band(t.pred.water[5], 0x3FF) < 0x200
        and t.pred.gate[1][1] ~= t.pred.gate[4][1] and t.pred.vomit2[1] == t.pred.vomit3[1], "kPredefinedTileData water words")
  -- the rooms' water / stair / shell objects
  local n = 0
  for r = 0, (R.roomCount or 296) - 1 do
    local list = roomObjects(rom, rom:ptr(R.roomObjects + r * 4))
    if #list > 0 then
      local e = {}
      for _, o in ipairs(list) do
        local key
        if o.s == 1 then key = (o.id == 0xDA) and "flood" or "drain"
        elseif o.s == 3 and o.id == 0x00 then key = "face"
        elseif o.s == 3 and o.id == 0x15 then key = "shell"
        elseif o.s == 3 and o.id == 0x33 then key = "south"
        elseif o.s == 2 and o.id == 0x33 then key = "north"
        elseif o.s == 2 and o.id == 0x35 then key = "ladder"
        elseif o.s == 2 and o.id == 0x36 then key = "ladderOff"
        elseif o.s == 2 and o.id == 0x37 then key = "gate" end
        if key then e[key] = e[key] or {}; table.insert(e[key], o); n = n + 1 end
      end
      if next(e) then t.rooms[r] = e end
    end
  end
  local r35, r76, r10B, rDE = t.rooms[0x35], t.rooms[0x76], t.rooms[0x10B], t.rooms[0xDE]
  check(r35 and r35.flood and r35.flood[1].x == 28 and r35.face and r76 and r76.drain and r76.drain[1].w == 2
        and r10B and r10B.gate and rDE and rDE.shell and rDE.shell[1].x == 43, "the water / gate / shell objects")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game) return d and d.mech27 end
M.T = T

-- ------------------------------------------------------------ map words and attributes
local function attrOf(inside, w)
  local tab = inside.m27attr
  if not tab then
    tab = require("src.zelda.alttp.Interior").attributes(inside.data.roomIdx, inside.aux)
    inside.m27attr = tab
  end
  local v = tab[band(w, 0x3FF)] or 0
  if v >= 0x10 and v < 0x1C then v = bor(v, rshift(band(w, 0xC00), 10)) end
  return v
end

-- a map word on the upper (bg2) or lower (bg3) map, its attribute rebuilt
-- (Dungeon_LoadBasicAttribute's rule) unless the room is still loading
local function setWord(inside, lower, cell, w)
  if cell < 0 or cell > 4095 then return end
  if lower then
    if not inside.bg3 then return end
    inside.patch3[cell] = w
  else
    inside.patch[cell] = w
  end
  if inside.loading or not inside.attrs then return end
  local v = attrOf(inside, w)
  local W = require("src.zelda.alttp.Interior").WALKABLE
  if lower then inside.attrsLo[cell] = v; inside.gridLo[cell] = not W[v]
  else inside.attrs[cell] = v; inside.grid[cell] = not W[v] end
end
M.setWord = setWord

-- WriteAttr1 / WriteAttr2: a word = two cells (low byte first)
local function writeAttr(inside, lower, cell, word)
  local at, gr = inside.attrs, inside.grid
  if lower then at, gr = inside.attrsLo, inside.gridLo end
  if not at then return end
  local W = require("src.zelda.alttp.Interior").WALKABLE
  for i, v in ipairs({ band(word, 0xFF), rshift(word, 8) }) do
    local c = cell + i - 1
    if c >= 0 and c <= 4095 then at[c] = v; gr[c] = not W[v] end
  end
end
local function XY(x, y) return y * 64 + x end

-- ------------------------------------------------------------ water state
local function roomInfo(game, room) local t = T(game) return t and t.rooms[room] end
local function hdrTag1(inside) return (inside.hdrOrig or inside.hdr or {})[7] or 0 end

-- is there water in the room now (the stairs' / face's state)
function M.watered(game, inside)
  local info = roomInfo(game, inside.room)
  if not info then return false end
  local mem = inside.mem or {}
  if info.flood then return mem.water == true end
  if info.drain then return mem.water ~= true end
  if hdrTag1(inside) == M.TAG.dam then return M.damOpen(game) end
  return false
end

function M.damOpen(game)
  local rm = game.roomMemory
  return (rm and rm[0x28] and rm[0x28].dam == true) or (game.progress and game.progress.swampDam == true) or false
end

-- the dam's indoor side (save_dung_info[0x28] |= 0x100): for the lead /
-- team A's outdoor dam
function M.setFlooded(game, on)
  game.roomMemory = game.roomMemory or {}
  local m = game.roomMemory[0x28] or { doors = {}, chests = {} }
  game.roomMemory[0x28] = m
  m.dam = on and true or nil
  game.progress.swampDam = on and true or nil
  local inside = game.interior
  if inside and inside.room == 0x28 and game.state == "room" then
    inside:loadRoom(0x28, inside.main)
    game.roomImages = nil
  end
end

-- the stair attributes (Dungeon_LoadObjectAttribute's water / dry lists)
local function stairsAtLoad(inside, info, wet)
  for _, o in ipairs(info.north or {}) do
    local j = XY(o.x, o.y)
    if wet then
      writeAttr(inside, false, j, 0x003); writeAttr(inside, false, j + 2, 0x300)
      writeAttr(inside, true, j, 0xA03); writeAttr(inside, true, j + 2, 0x30A)
      writeAttr(inside, false, j + XY(0, 1), 0x808); writeAttr(inside, false, j + XY(2, 1), 0x808)
    else
      -- dung_num_interpseudo_upnorth_stairs, attr 0x1D1D (type 2)
      writeAttr(inside, false, j, 0x02); writeAttr(inside, true, j + XY(0, 3), 0x02)
      writeAttr(inside, false, j + 2, 0x200); writeAttr(inside, true, j + XY(2, 3), 0x200)
      writeAttr(inside, false, j + XY(0, 1), 0x01); writeAttr(inside, true, j + XY(0, 2), 0x01)
      writeAttr(inside, false, j + XY(2, 1), 0x100); writeAttr(inside, true, j + XY(2, 2), 0x100)
      for _, r in ipairs({ 1, 2 }) do
        writeAttr(inside, false, j + XY(1, r), 0x1D1D); writeAttr(inside, true, j + XY(1, r), 0x1D1D)
      end
    end
  end
  for _, o in ipairs(info.south or {}) do
    local j = XY(o.x, o.y)
    if wet then
      writeAttr(inside, true, j + XY(0, 3), 0xA03); writeAttr(inside, true, j + XY(2, 3), 0x30A)
      writeAttr(inside, false, j + XY(0, 3), 0x003); writeAttr(inside, false, j + XY(2, 3), 0x300)
      writeAttr(inside, false, j + XY(0, 2), 0x808); writeAttr(inside, false, j + XY(2, 2), 0x808)
    else
      -- dung_num_stairs_wet, attr 0x3D3D
      writeAttr(inside, true, j, 0x02); writeAttr(inside, false, j + XY(0, 3), 0x02)
      writeAttr(inside, true, j + XY(0, 1), 0x01); writeAttr(inside, false, j + XY(0, 2), 0x01)
      writeAttr(inside, true, j + 2, 0x200); writeAttr(inside, false, j + XY(2, 3), 0x200)
      writeAttr(inside, true, j + XY(2, 1), 0x100); writeAttr(inside, false, j + XY(2, 2), 0x100)
      for _, r in ipairs({ 1, 2 }) do
        writeAttr(inside, true, j + XY(1, r), 0x3D3D); writeAttr(inside, false, j + XY(1, r), 0x3D3D)
      end
    end
  end
  local function inactive(o)
    local j = XY(o.x, o.y)
    for _, lo in ipairs({ false, true }) do writeAttr(inside, lo, j, 0xA03); writeAttr(inside, lo, j + 2, 0x30A) end
    writeAttr(inside, false, j + XY(0, 1), 0x803); writeAttr(inside, false, j + XY(2, 1), 0x308)
  end
  for _, o in ipairs(info.ladder or {}) do
    if wet then
      local j = XY(o.x, o.y)
      writeAttr(inside, false, j, 0x003); writeAttr(inside, false, j + 2, 0x300)
      writeAttr(inside, true, j, 0xA03); writeAttr(inside, true, j + 2, 0x30A)
    else
      inactive(o)
    end
  end
  for _, o in ipairs(info.ladderOff or {}) do inactive(o) end
end

-- Dungeon_SetAttrForActivatedWater (the flood's end)
local function stairsFlooded(inside, info)
  for _, o in ipairs(info.north or {}) do
    local j = XY(o.x, o.y)
    writeAttr(inside, false, j, 0x003); writeAttr(inside, false, j + 2, 0x300)
    writeAttr(inside, true, j, 0xA03); writeAttr(inside, true, j + 2, 0x30A)
    writeAttr(inside, false, j + XY(0, 1), 0x808); writeAttr(inside, false, j + XY(2, 1), 0x808)
    for r = 1, 3 do writeAttr(inside, true, j + XY(0, r), 0x808); writeAttr(inside, true, j + XY(2, r), 0x808) end
  end
  for _, o in ipairs(info.south or {}) do
    local j = XY(o.x, o.y)
    writeAttr(inside, false, j + XY(0, 3), 0x003); writeAttr(inside, false, j + XY(2, 3), 0x300)
    writeAttr(inside, true, j + XY(0, 3), 0xA03); writeAttr(inside, true, j + XY(2, 3), 0x30A)
    writeAttr(inside, false, j + XY(0, 2), 0x808); writeAttr(inside, false, j + XY(2, 2), 0x808)
    for r = 0, 2 do writeAttr(inside, true, j + XY(0, r), 0x808); writeAttr(inside, true, j + XY(2, r), 0x808) end
  end
end

-- Dungeon_SetAttrForActivatedWaterOff (the drain's end)
local function stairsDrained(inside, info)
  for _, k in ipairs({ "north", "south" }) do
    for _, o in ipairs(info[k] or {}) do
      local j = XY(o.x, o.y)
      writeAttr(inside, false, j + XY(1, 1), 0x1D1D); writeAttr(inside, false, j + XY(1, 2), 0x1D1D)
    end
  end
end

-- the room's own copy of its header (the cartridge changes its RAM copy:
-- dung_hdr_tag[1] = 0, dung_hdr_bg2_properties)
local function ownHdr(inside)
  if not inside.hdrOrig then
    local c = {}
    for k, v in pairs(inside.hdr) do c[k] = v end
    inside.hdrOrig = inside.hdr
    inside.hdr = c
  end
  return inside.hdr
end
M.ownHdr = ownHdr
local function clearTag1(inside) ownHdr(inside)[7] = 0 end
-- dung_hdr_bg2_properties
local function setProp(inside, prop)
  local h = ownHdr(inside)
  h[1] = bor(band(h[1] or 0, 0x1F), lshift(prop, 5))
end
M.setProp = setProp

-- the water picture parameters of the 0xDA / 0xD8 object (RoomDraw cases
-- 0xDA / 0xD8)
local function windowOf(o)
  local w, h = o.w + 2, o.h + 2
  if o.id == 0xDA then
    local var4 = h * 16 - 8
    return { var0 = o.x * 8 + w * 16, var1 = o.y * 8 + h * 16 - 8, var2 = var4 - 24, var3 = w * 16 - 24, var4 = var4, var5 = 0 }
  end
  local var2 = h * 16
  return { var0 = o.x * 8 + w * 16, var1 = o.y * 8 + h * 16, var2 = var2, var3 = w * 16, var4 = var2 - 24, var5 = 0 }
end
M.windowOf = windowOf

-- words onto a map: rows of `n` words from `src` (RoomDraw_WaterHoldingObject /
-- DrawWaterThing: 4 a row, row by row)
local function drawRows(inside, lower, cell, src, rows, n)
  n = n or 4
  for r = 0, rows - 1 do
    for c = 0, n - 1 do
      local w = src[r * n + c + 1]
      if w then setWord(inside, lower, cell + r * 64 + c, w) end
    end
  end
end
-- RoomDraw_Object_Nx4: n columns of 4 words
local function drawCols(inside, lower, cell, src, cols)
  for c = 0, cols - 1 do
    for r = 0, 3 do
      local w = src[c * 4 + r + 1]
      if w then setWord(inside, lower, cell + r * 64 + c, w) end
    end
  end
end

-- RoomTag_OperateWaterFlooring: kWatergateLayout's water blocks on the lower map
local function operateFlooring(inside, t)
  local L = t.gateLayout
  local src = t.pred.water
  local i = 1
  while i + 1 <= #L do
    local tw = L[i] + L[i + 1] * 256
    local wi, hi = band(tw, 3) + 1, band(rshift(tw, 8), 3) + 1
    local d2 = bor(rshift(band(tw, 0xFC), 2), lshift(rshift(tw, 10), 6))
    for _ = 1, hi do
      local d = d2
      for _ = 1, wi do
        for _ = 1, 2 do
          for k = 0, 3 do setWord(inside, true, d + k, src[k + 1]); setWord(inside, true, d + 64 + k, src[k + 5]) end
          d = d + 128
        end
        d = d + 4 - 256
      end
      d2 = d2 + 256
    end
    i = i + 3
  end
end

-- the room's objects drawn by state, before the attribute tables (the GBA
-- draws them over its pre-rendered maps; RoomObjects.load)
local function gameOf(inside) return inside.m27game or M.curGame end
local function loadWords(inside)
  local game = gameOf(inside)
  if not game then return end
  local t = T(game)
  if not t then return end
  local info = t.rooms[inside.room]
  local mem = inside.mem or {}
  local tag1 = (inside.hdr or {})[7] or 0
  if info then
    -- the water face (subtype-3 0x00)
    for _, o in ipairs(info.face or {}) do
      local open = (tag1 == M.TAG.dam and M.damOpen(game)) or (tag1 == M.TAG.on and mem.water == true)
      if open then drawRows(inside, o.layer == 2, XY(o.x, o.y), t.pred.face, 5) end
    end
    -- the drained pool: the plug on BG2, the water gone (OURS: as the drain fills it)
    for _, o in ipairs(info.drain or {}) do
      if mem.water then
        local w, h = o.w + 2, o.h + 2
        drawRows(inside, false, XY(o.x, o.y) + (w - 1) * 2 + (h - 1) * 128, t.pred.plug, 4)
        if inside.bg3 then for c = 0, 4095 do inside.patch3[c] = t.pred.blank end end
      end
    end
    -- the dam's gate (subtype-2 0x37): open with the flooring
    for _, o in ipairs(info.gate or {}) do
      if mem.water then
        drawCols(inside, false, XY(o.x, o.y), t.pred.gate[4], 10)
        operateFlooring(inside, t)
      end
    end
    -- Kholdstare's shell (subtype-3 0x15): not drawn once the boss is beaten
    for _, o in ipairs(info.shell or {}) do
      local p = game.progress
      if p.bossBeaten and p.bossBeaten[inside.room] then M.clearShell(inside, o) end
    end
  end
  -- the attic's bombed floor (room 0x65, dung_savegame_state_bits 0x1000)
  if inside.room == 0x65 and mem.light then M.drawHole(inside, t) end
end

function M.clearShell(inside, o)
  local ro = inside.data.roomIdx.roomObj
  local blank = ro and ro.blankWord or 0x1EC
  for r = 0, 7 do for c = 0, 9 do setWord(inside, true, XY(o.x + c, o.y + r), blank) end end
  inside.shellGone = true
end

-- ThievesAttic_DrawLightenedHole: the bomb floor's segments -> +0x5BA
function M.drawHole(inside, t)
  local n = 0
  for _, m in ipairs(inside.misc or {}) do
    if m.kind == "bomb" then
      local w = t.pred.hole
      local k = n * 4
      setWord(inside, m.lower, m.cell, w[k + 1]); setWord(inside, m.lower, m.cell + 64, w[k + 2])
      setWord(inside, m.lower, m.cell + 1, w[k + 3]); setWord(inside, m.lower, m.cell + 65, w[k + 4])
      n = n + 1
      m.bombed = true
    end
  end
  return n
end

-- after the attribute tables: stairs, the BG2 property, the room's state
local function afterLoad(inside)
  local game = gameOf(inside)
  inside.waterWin, inside.m27attr = nil, nil
  if not game then return end
  local t = T(game)
  if not t then return end
  local info = t.rooms[inside.room]
  if not info then return end
  local mem = inside.mem or {}
  local tag1 = (inside.hdr or {})[7] or 0
  local wet = M.watered(game, inside)
  local relevant = info.flood or info.drain or tag1 == M.TAG.dam
  if relevant then
    stairsAtLoad(inside, info, wet)
    if not wet then setProp(inside, 0) end
    -- RoomDraw 0xDA / 0xD8 with 0x800: dung_hdr_tag[1] = 0
    if (info.flood or info.drain) and mem.water then clearTag1(inside) end
  end
  if info.gate and mem.water then clearTag1(inside) end
end

-- ------------------------------------------------------------ the water switch (0x21)
function M.prep(self, a)
  if a.type ~= M.SWITCH then return end
  a.ai, a.A, a.B, a.C, a.D = 0, 0, 48, 0, 0
  a.untouchable, a.noTouch = true, true
end

-- PushSwitch_Draw's Link check: sprite_C when Link pushes it from the right
local function pushCheck(self, a, lk, t)
  local game = self.game
  a.C = 0
  -- r28: link_x / y_coord_prev (OURS: the sprites run before Link moves,
  -- so it is where Link stood at this point last frame)
  local px, py = a.lkX or lk.x, a.lkY or lk.y
  a.lkX, a.lkY = lk.x, lk.y
  if (a.lower or false) ~= (self.inside.lower or false) then return end
  local d = a.D or 0
  local e = t.pushOam[d * 4] or t.pushOam[0]
  local x, y = a.x + e[1], a.y + e[2]
  local w, h = t.pushWH[d * 2 + 1], t.pushWH[d * 2 + 2]
  local A = D().A()
  local lx, ly, lw, lh = A.linkBox(lk)
  if A.overlapCart(lx, ly, lw, lh, x, y, w, h) then
    -- Sprite_DirectionToFaceLink with y + 19
    local dx = band(lk.x - a.x, 0xFF)
    local dy = band(lk.y + 8 - (a.y + 19), 0xFF)
    local xm = dx >= 128 and 256 - dx or dx
    local ym = dy >= 128 and 256 - dy or dy
    local dir
    if xm >= ym then dir = (lk.x - a.x < 0) and 1 or 0 else dir = ((dy >= 128) and 1 or 0) + 2 end
    if dir == 0 and lk.facing == 4 then a.C = 1 end
  elseif not D().contact(self, a, lk, { harmless = band(t.switchFlags2 or 0, 0x80) ~= 0 }) then
    return
  end
  -- r28: Sprite_NullifyHookshotDrag puts Link back on link_x / y_coord_prev
  -- (the handle is a wall to him), then link_speed_setting 0, RepelDash
  if lk == game.link then
    lk.x, lk.y = px, py
    a.lkX, a.lkY = px, py
    game.switchRepels = (game.switchRepels or 0) + 1
  end
  game.dashStop = true
end

function M.update(self, a, lk)
  if a.type ~= M.SWITCH then return end
  local t = T(self.game)
  if not t then return end
  pushCheck(self, a, lk, t)
  if a.ai == 0 then
    if (a.C or 0) ~= 0 then
      a.B = (a.B or 48) - 1
      if a.B <= 0 then a.B = 0; a.ai = 1 end
    else
      a.B = 48
    end
  elseif a.ai == 1 then
    if (a.delay or 0) == 0 then
      a.A = (a.A or 0) + 1
      local j = a.A
      if j == 10 then
        a.ai = 2
        self.game.waterFlag = (self.game.waterFlag or 0) + 1
        self.game.waterSwitches = (self.game.waterSwitches or 0) + 1
      else
        a.delay = t.pushDelay[j + 1]
        a.D = t.pushDir[j + 1]
      end
    end
  end
end

function M.draw(spr, a, x, y, frame, game)
  if a.type ~= M.SWITCH then return true end
  local t = game and T(game)
  if not t then return true end
  local f = band(spr.info.flags3[a.type + 1] or 0, 0x0F)
  local r1 = band(rshift(a.B or 0, 2), 3)
  local base = (a.D or 0) * 5
  for i = 4, 0, -1 do
    local e = t.pushOam[base + i]
    if e then
      local ox, oy = e[1], e[2]
      if i < 4 then ox, oy = ox - r1, oy - rshift(r1, 1) end
      spr:oam(x + ox, y + oy, e[3], bor(e[4], f), i == 4 and 2 or 0)
    end
  end
  return true
end
function M.swordImmune() return false end

-- ------------------------------------------------------------ the water tags
local function camY(game)
  local inside, lk = game.interior, game.link
  local _, cy = inside:camera(lk.x, lk.y, 240, 160)
  return cy or 0
end

-- RoomTag_WaterOn -> Module07_0C (GBA submodule 0x0D)
function M.startFlood(game)
  local inside = game.interior
  local info = roomInfo(game, inside.room)
  local o = info and info.flood and info.flood[1]
  if not o then return false end
  local w = windowOf(o)
  w.kind, w.sub, w.ctr = "flood", 0, 1
  local face = info.face and info.face[1]
  w.face = face and XY(face.x, face.y)
  game.waterAnim = w
  clearTag1(inside)
  inside.mem.water = true
  game.waterFlag = 0
  game.floods = (game.floods or 0) + 1
  return true
end

-- RoomTag_WaterOff -> Module07_0B (GBA submodule 0x0C)
function M.startDrain(game)
  local inside = game.interior
  local t = T(game)
  local info = roomInfo(game, inside.room)
  local o = info and info.drain and info.drain[1]
  if not o then return false end
  local w = windowOf(o)
  w.kind, w.sub, w.ctr = "drain", 0, 1
  -- DrawWaterThing at ((var1 - 16) / 8, (var0 - 16) / 8)
  drawRows(inside, false, XY(math.floor((w.var0 - 16) / 8), math.floor((w.var1 - 16) / 8)), t.pred.plug, 4)
  game.roomImages = nil
  game.waterAnim = w
  clearTag1(inside)
  inside.mem.water = true
  game.waterFlag = 0
  inside.waterWin = { w.var0 - (w.var3 - 1), w.var1 - w.var2, w.var0 + w.var3 - 1, w.var1 + w.var2 }
  game.drains = (game.drains or 0) + 1
  return true
end

-- RoomTag_WaterGate -> Module07_0D (FloodDam)
function M.startDam(game)
  local inside = game.interior
  local t = T(game)
  local info = roomInfo(game, inside.room)
  local o = info and info.gate and info.gate[1]
  if not o or inside.mem.water then return false end
  local pos = XY(o.x, o.y)
  inside.mem.water = true
  clearTag1(inside)
  operateFlooring(inside, t)
  game.roomImages = nil
  game.waterAnim = { kind = "dam", sub = 0, gv1 = 0x0F, var2 = 0, var4s = 0, var3 = 0, pos = pos,
                     var0 = o.x * 8 + 40, yUpper = o.y * 8 }
  M.setFlooded(game, true)
  game.waterFlag = 0
  game.dams = (game.dams or 0) + 1
  return true
end

-- one frame of the water submodules (the game waits meanwhile)
function M.waterFrame(game)
  local w = game.waterAnim
  local inside = game.interior
  local t = T(game)
  local info = roomInfo(game, inside.room) or {}
  if w.kind == "flood" then
    local s = w.sub
    if s <= 3 then
      w.sub = s + 1
    elseif s <= 8 then
      w.ctr = band(w.ctr - 1, 0xFF)
      if w.ctr == 0 then
        w.ctr = 4
        w.sub = s + 1
        local depth = w.sub - 4
        w.var3, w.var5, w.var2 = 8, 0, 0x30
        if w.face then drawRows(inside, false, w.face + XY(0, 2), t.pred.vomit, depth); game.roomImages = nil end
      end
    else
      if s == 9 then
        w.ctr, w.sub, s = 0, 10, 10
        setProp(inside, 7)    -- OURS: the water layer shows (blended) from the stream on
      end
      if s == 10 then
        local k = band(w.ctr, 3)
        local r0 = w.var1 - camY(game) - 0x24
        w.var3 = w.var3 + M.TURN_ON0[k]
        w.var5 = w.var5 + M.TURN_ON1[k]
        if w.var5 >= r0 then setProp(inside, 7); w.sub = 11 end
        w.ctr = w.ctr + 1
        local top = w.var1 - w.var2
        inside.waterWin = { w.var0 - (w.var3 - 1), top, w.var0 + w.var3 - 1, top + w.var5 }
      else
        if band(w.ctr, 7) == 0 then
          local k = band(rshift(w.ctr, 2), 3)
          if w.var2 == w.var4 then
            stairsFlooded(inside, info)
            inside.waterWin = nil
            game.waterAnim = nil
            game.floodsDone = (game.floodsDone or 0) + 1
            return
          end
          w.var2 = w.var2 + M.TURN_ON2[k]
          w.var3 = w.var3 + M.TURN_ON2[k]
          local a = w.var4 - w.var2
          if (a == 0 or a == 8) and w.face then
            drawRows(inside, false, w.face + XY(0, 2), a == 0 and t.pred.vomit3 or t.pred.vomit2, 5)
            game.roomImages = nil
          end
        end
        w.ctr = w.ctr + 1
        inside.waterWin = { w.var0 - (w.var3 - 1), w.var1 - w.var2, w.var0 + w.var3 - 1, w.var1 + w.var2 }
      end
    end
  elseif w.kind == "drain" then
    if w.sub == 0 then
      if band(w.ctr, 7) == 0 then
        local k = band(rshift(w.ctr, 2), 3)
        if w.var2 == w.var4 then
          stairsDrained(inside, info)
          setProp(inside, 0)
          w.sub = 1
          return
        end
        w.var2 = w.var2 + M.TURN_OFF[k]
        w.var3 = w.var3 + M.TURN_OFF[k]
      end
      w.ctr = w.ctr + 1
      inside.waterWin = { w.var0 - (w.var3 - 1), w.var1 - w.var2, w.var0 + w.var3 - 1, w.var1 + w.var2 }
    elseif w.sub == 1 then
      -- dung_bg1 filled with kPredefinedTileData +0x1E0
      for c = 0, 4095 do setWord(inside, true, c, t.pred.blank) end
      inside.waterWin = nil
      game.roomImages = nil
      w.sub = 2
    else
      w.sub = w.sub + 1
      if w.sub == 6 then game.waterAnim = nil; game.drainsDone = (game.drainsDone or 0) + 1 end
    end
  elseif w.kind == "dam" then
    if w.sub <= 3 then
      w.sub = w.sub + 1
    elseif w.sub == 4 then
      -- FloodDam_Expand
      w.gv1 = w.gv1 + 1
      w.var3 = rshift(w.gv1, 1)
      w.var4s = w.var4s + 1
      w.var2 = w.var4s + (w.var3 - 8)
      if band(w.gv1, 0xF) == 0 then
        if w.gv1 == 64 then w.sub = 5 end
        drawCols(inside, false, w.pos, t.pred.gate[rshift(w.gv1, 4)], 10)
        game.roomImages = nil
      end
      inside.waterWin = { w.var0 - w.var3, w.yUpper, w.var0 + w.var3, w.yUpper + math.max(0, w.var2) }
    else
      -- FloodDam_Fill
      w.var2 = w.var2 + 1
      inside.waterWin = { w.var0 - w.var3, w.yUpper, w.var0 + w.var3, w.yUpper + w.var2 }
      if w.var2 + (w.yUpper - camY(game)) >= 225 then
        inside.waterWin = nil
        game.waterAnim = nil
        game.damsDone = (game.damsDone or 0) + 1
      end
    end
  end
end

-- the water tags of the room, one frame (Dung_TagRoutine dispatch)
function M.waterTags(game)
  local inside = game.interior
  if (game.waterFlag or 0) == 0 then return end
  local hdr = inside.hdr or {}
  for _, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
    if tag == M.TAG.on then if M.startFlood(game) then return end
    elseif tag == M.TAG.off then if M.startDrain(game) then return end
    elseif tag == M.TAG.gate then if M.startDam(game) then return end end
  end
end

-- the pull switches of the dam room set the water flag (PullSwitch_FacingUp:
-- type != 6)
local function pullSwitches(game)
  local acts = game.actors
  for _, a in ipairs(acts and acts.list or {}) do
    if a.type == 0x04 and a.pulled and not a.m27 then
      a.m27 = true
      game.waterFlag = (game.waterFlag or 0) + 1
    end
  end
end

-- ------------------------------------------------------------ the moving floor
function M.overlord(self, o, camx, camy)
  if o.type ~= M.MOVING_FLOOR then return false end
  local game = self.game
  if o.done then return true end
  -- sprite_state[0] == 4: the boss explodes
  for _, a in ipairs(self.list) do
    if (a.k or -1) == 0 and a.exploding then o.done = true; game.floorFlags = 1; return true end
  end
  if (o.gen1 or 0) == 0 then
    o.gen2 = (o.gen2 or 0) + 1
    if o.gen2 == 32 then
      local xlo = band(o.x or 0, 0xFF)
      game.floorFlags = band(D().rnd(self), xlo ~= 0 and 3 or 1) * 2
      o.gen2 = band(D().rnd(self), 127) + 128
      o.gen1 = 1
    else
      game.floorFlags = 1
    end
  else
    o.gen2 = o.gen2 - 1
    if o.gen2 <= 0 then o.gen1 = 0; o.gen2 = 0 end
  end
  return true
end

-- LayerEffect_Scroll (header effect 2)
function M.layerScroll(game)
  local inside = game.interior
  local f = game.floor
  f.vx, f.vy = 0, 0
  local p = game.progress
  if p.bossBeaten and p.bossBeaten[inside.room] then return end
  local flags = game.floorFlags or 0
  if band(flags, 1) ~= 0 then return end
  f.sub = (f.sub or 0) + 0x80
  local v = rshift(f.sub, 8)
  f.sub = band(f.sub, 0xFF)
  if band(flags, 2) ~= 0 then v = -v end
  if flags < 4 then f.vx = v; f.x = f.x - v else f.vy = v; f.y = f.y - v end
end

-- ------------------------------------------------------------ Link on the floors
local function free(inside, x, y)
  for _, pt in ipairs({ { 1, 8 }, { 14, 8 }, { 1, 23 }, { 14, 23 } }) do
    if inside:blocked(x + pt[1], y + pt[2]) then return false end
  end
  return true
end
local function grounded(game)
  local lk = game.link
  return not (game.recoil or game.pitFall or game.roomScroll or game.climb or lk.hop or lk.swim or lk.waterHop
              or (lk.z or 0) ~= 0 or game.hookshot)
end

-- Link_ApplyConveyor
function M.conveyLink(game)
  local inside, lk = game.interior, game.link
  local a = inside:attrAt(lk.x + 8, lk.y + 16)
  local v = M.CONVEY[a or -1]
  if not v or not grounded(game) then game.belt = nil return end
  local t = T(game)
  local j = (a or 0x68) - 0x68
  game.belt = j + 1
  local dirs = { [0] = 0, 2, 4, 6 }   -- facing that runs with the belt
  if game.dash and (game.dash.ctr or 0) == 32 and game.dash.facing == dirs[j] then return end
  local s = game.beltSub or { 0, 0 }
  game.beltSub = s
  local by, bx = t.beltY[j + 1] * 16, t.beltX[j + 1] * 16
  s[1] = s[1] + by; s[2] = s[2] + bx
  local my = (s[1] >= 0) and math.floor(s[1] / 256) or -math.floor(-s[1] / 256)
  local mx = (s[2] >= 0) and math.floor(s[2] / 256) or -math.floor(-s[2] / 256)
  s[1], s[2] = s[1] - my * 256, s[2] - mx * 256
  if (mx ~= 0 or my ~= 0) and free(inside, lk.x + mx, lk.y + my) then
    lk.x, lk.y = lk.x + mx, lk.y + my
    game.beltMoves = (game.beltMoves or 0) + 1
  end
end

-- Link_HandleMovingFloor
function M.floorLink(game)
  local inside, lk = game.interior, game.link
  local f = game.floor
  if band(rshift((inside.hdrOrig or inside.hdr)[1] or 0, 2), 7) == 0 then return end
  if not grounded(game) or (f.vx == 0 and f.vy == 0) then return end
  local x, y = lk.x + 8, lk.y + 20
  local up = inside.attrs[math.floor(y / 8) * 64 + math.floor(x / 8)]
  local lx, ly = (x + f.x) % 512, (y + f.y) % 512
  local lo = inside.attrsLo[math.floor(ly / 8) * 64 + math.floor(lx / 8)]
  if up ~= 0x1C or lo ~= 0x0C then return end
  if free(inside, lk.x + f.vx, lk.y + f.vy) then
    lk.x, lk.y = lk.x + f.vx, lk.y + f.vy
    game.floorRides = (game.floorRides or 0) + 1
  end
end

-- the cape / Byrna / moon pearl exceptions (flags for team A's items)
function M.spikeFlags(game)
  local byrna = game.byrnaOn == true
  local ok, I27 = pcall(require, "src.zelda.alttp.Items27")
  if ok and I27 and I27.byrnaSpark then byrna = byrna or (I27.byrnaSpark(game) and true or false) end
  local inv = game.progress.inv or {}
  local pearl = (inv[0x3B] or 0) ~= 0
  return { cape = game.cape ~= nil, byrna = byrna, pearl = pearl }
end

local function roomBeaten(game)
  local p = game.progress
  return p.bossBeaten ~= nil and p.bossBeaten[game.interior.room] == true
end

-- TileBehavior_SpikeFloor under (x + 8, y + 20)
function M.spikeFloor(game)
  local inside, lk = game.interior, game.link
  if roomBeaten(game) or (lk.z or 0) ~= 0 then return false end
  if inside:attrAt(lk.x + 8, lk.y + 20) ~= M.SPIKE_FLOOR then return false end
  local fl = M.spikeFlags(game)
  M.lastSpike = fl
  if fl.cape or fl.byrna or (game.blink or 0) > 0 then return false end
  if game.isBunny and game:isBunny() and fl.pearl then game.spikeUnbunny = (game.spikeUnbunny or 0) + 1 end
  local h0 = game.stats.health
  game:hurtLink(8, lk.x + 8, lk.y + 12)
  game.recoil = nil
  if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
  if game.stats.health < h0 then game.spikeHits = (game.spikeHits or 0) + 1 end
  return true
end

-- TileBehavior_Spike 0x44 in the movement probes + LinkApplyTileRebound
local PROBES = {
  [0] = function(lk) return { { lk.x, lk.y + 7 }, { lk.x + 8, lk.y + 7 }, { lk.x + 15, lk.y + 7 } } end,
  [1] = function(lk) return { { lk.x, lk.y + 24 }, { lk.x + 8, lk.y + 24 }, { lk.x + 15, lk.y + 24 } } end,
  [2] = function(lk) return { { lk.x - 1, lk.y + 8 }, { lk.x - 1, lk.y + 16 }, { lk.x - 1, lk.y + 23 } } end,
  [3] = function(lk) return { { lk.x + 16, lk.y + 8 }, { lk.x + 16, lk.y + 16 }, { lk.x + 16, lk.y + 23 } } end,
}
function M.spikeTiles(game, inp)
  local inside, lk = game.interior, game.link
  if roomBeaten(game) or game.recoil or (game.blink or 0) > 0 or game.cape then return false end
  local dirs = { { "up", 0 }, { "down", 1 }, { "left", 2 }, { "right", 3 } }
  for _, d in ipairs(dirs) do
    if inp[d[1]] then
      for _, p in ipairs(PROBES[d[2]](lk)) do
        if inside:attrAt(p[1], p[2]) == M.SPIKE then
          -- (link_last_direction_moved_towards == 0) ? !(y & 4) : (y & 4)
          local y4 = band(lk.y, 4) ~= 0
          if (d[2] == 0 and not y4) or (d[2] ~= 0 and y4) then
            local t = T(game)
            game:hurtLink(8, lk.x + 8, lk.y + 12)
            if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
            game.recoil = { vx = t.reboundX[d[2] + 1], vy = t.reboundY[d[2] + 1], t = 24, sx = 0, sy = 0, vz = 18 }
            game.spikeRebounds = (game.spikeRebounds or 0) + 1
            return true
          end
          return false
        end
      end
    end
  end
  return false
end

-- sprites on conveyors (Sprite_ApplyConveyor, every other frame)
function M.conveySprites(actors)
  local game, inside = actors.game, actors.inside
  if not inside or not inside.m27belts or band(game.frame or 0, 1) == 0 then return end
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  local f5 = cb and cb.flags5 or {}
  for _, a in ipairs(actors.list) do
    -- Sprite_CheckTileCollision: not a flier (flags5 & 0x80) or in the air
    if not a.dead and (a.z or 0) == 0 and not a.held and (f5[a.type + 1] or 0) < 0x80 then
      local at = (a.lower and inside.attrsLo or inside.attrs)
      local c = math.floor((a.y + 12) / 8) * 64 + math.floor((a.x + 8) / 8)
      local v = M.CONVEY[at[c] or -1]
      if v then a.x, a.y = a.x + v[1], a.y + v[2]; a.belted = (a.belted or 0) + 1 end
    end
  end
end

-- ------------------------------------------------------------ bombs
-- Bomb_CheckForDestructibles' attribute 0x62 (the 3 x 3 cells, step 2)
function M.bombFloor(game, x, y)
  local inside = game.interior
  local t = T(game)
  if not inside or not t then return false end
  local k = math.floor(band(y, 0x1F8) / 8) * 64 + math.floor(band(x, 0x1F8) / 8) - 0x82
  for r = 0, 2 do
    for c = 0, 2 do
      if inside.attrs[k + r * 128 + c * 2] == M.BOMB_FLOOR then
        if inside.room == 0x65 then inside.mem.light = true end
        local n = M.drawHole(inside, t)
        game.roomImages = nil
        game.floorsBombed = (game.floorsBombed or 0) + 1
        return n > 0
      end
    end
  end
  return false
end

-- ------------------------------------------------------------ install
function M.install(G, Dm)
  local I = require("src.zelda.alttp.Interior")
  local RO = require("src.zelda.alttp.RoomObjects")
  -- the conveyors and the bomb floor are floor to Link (TileBehavior_Conveyor
  -- sets only tiledetect_var4; 0x62 is TileBehavior_NothingOW)
  for v = 0x68, 0x6B do I.WALKABLE[v] = true end
  I.WALKABLE[M.BOMB_FLOOR] = true
  -- the state objects are drawn before the attribute tables
  local roLoad0 = RO.load
  function RO.load(self)
    local r = roLoad0(self)
    local ok, err = pcall(loadWords, self)
    if not ok then print("Mech27.loadWords: " .. tostring(err)) end
    return r
  end
  local load0 = I.loadRoom
  function I:loadRoom(room, main)
    self.hdrOrig, self.m27attr, self.shellGone, self.waterWin = nil, nil, nil, nil
    local r = load0(self, room, main)
    afterLoad(self)
    local belts = false
    for c = 0, 4095 do
      local v = self.attrs[c]
      if v and v >= 0x68 and v <= 0x6B then belts = true break end
    end
    self.m27belts = belts
    local g = gameOf(self)
    if g and g.interior == self then
      g.floor = { x = 0, y = 0, vx = 0, vy = 0, sub = 0 }
      g.floorFlags = 0
    end
    return r
  end
  -- the game the rooms load for (the entrance's first room loads inside
  -- Interior.new, before the game holds the interior)
  local enter0 = G.enterRoom
  function G:enterRoom(e)
    self.waterAnim, self.waterFlag = nil, 0
    M.curGame = self
    return enter0(self, e)
  end
  local start0 = G.enterStart
  if start0 then
    function G:enterStart(i, ent)
      self.waterAnim, self.waterFlag = nil, 0
      M.curGame = self
      return start0(self, i, ent)
    end
  end
  -- one room frame
  local esc0 = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    local inside = self.interior
    if inside and not inside.m27game then inside.m27game = self end
    M.curGame = self
    if self.waterAnim and inside then M.waterFrame(self); return true end
    local r = esc0(self, inp)
    inside = self.interior
    if inside and inside.attrs and not self.roomScroll and not self.pitFall and T(self) then
      if not self.floor then self.floor = { x = 0, y = 0, vx = 0, vy = 0, sub = 0 } end
      if inside.room == 0x10B then pullSwitches(self) end
      M.waterTags(self)
      if (inside.hdrOrig or inside.hdr)[5] == 2 then M.layerScroll(self); M.floorLink(self) end
      if inside.m27belts then M.conveyLink(self) end
      M.spikeFloor(self)
      M.spikeTiles(self, inp)
    end
    return r
  end
  -- the lower map: the water windows, the moving floor's / the shake's offset
  local dbl0 = G.drawBgLayer
  function G:drawBgLayer(im, x, y, blend)
    local inside, ri = self.interior, self.roomImages
    if not (inside and ri and im == ri.bg3 and self.state == "room") then return dbl0(self, im, x, y, blend) end
    local ox, oy = 0, 0
    if self.floor and (inside.hdrOrig or inside.hdr)[5] == 2 then ox, oy = self.floor.x % 512, self.floor.y % 512 end
    if inside.room == 0xDE and (self.floorShake or 0) ~= 0 then ox = self.floorShake end
    local lg = love.graphics
    local win = inside.waterWin
    if win and lg.transformPoint and lg.intersectScissor then
      local x1, y1 = lg.transformPoint(x + win[1], y + win[2])
      local x2, y2 = lg.transformPoint(x + win[3] + 1, y + win[4] + 1)
      if x2 <= x1 or y2 <= y1 then return end
      lg.push("all")
      lg.intersectScissor(x1, y1, x2 - x1, y2 - y1)
      dbl0(self, im, x, y, blend)
      lg.pop()
      return
    end
    if ox == 0 and oy == 0 then return dbl0(self, im, x, y, blend) end
    -- BG1 = BG2 + dung_floor_offs (the map wraps at 512)
    for _, dx in ipairs({ 0, 512 }) do
      for _, dy in ipairs({ 0, 512 }) do
        if (dx == 0 or ox ~= 0) and (dy == 0 or oy ~= 0) then dbl0(self, im, x - ox + dx, y - oy + dy, blend) end
      end
    end
  end
  -- sprites on conveyors
  local Act = Dm.A()
  local up0 = Act.update
  function Act:update()
    local r = up0(self)
    M.conveySprites(self)
    return r
  end
  -- a bomb on a bomb floor
  local bd0 = G.bombDestroy
  if bd0 then
    function G:bombDestroy(a)
      if self.interior and M.bombFloor(self, a.x, a.y) then return end
      return bd0(self, a)
    end
  end
  -- Kholdstare's shell: gone with the melt (TS_copy 0)
  local ice = Dm.loaded and Dm.loaded.IcePalace
  if ice and ice.update then
    local iu0 = ice.update
    ice.update = function(self, a, lk)
      local r = iu0(self, a, lk)
      if a.type == 0xA3 and a.dead and not self.inside.shellGone then
        local info = roomInfo(self.game, self.inside.room)
        for _, o in ipairs(info and info.shell or {}) do M.clearShell(self.inside, o) end
        self.game.roomImages = nil
        self.game.shellsCleared = (self.game.shellsCleared or 0) + 1
      end
      return r
    end
  end
end

return M
