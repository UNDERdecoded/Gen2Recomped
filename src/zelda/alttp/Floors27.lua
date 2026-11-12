-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- FLOORS THAT MOVE (round 27, team B): the crumbling floors, the tile
-- rooms, Turtle Rock's pipes and the Cane of Somaria's platforms -- the SNES
-- routines the GBA keeps (zelda3 names), run by Palace.lua through
-- Dungeons26.lua's registry. GBA file offsets in M.OFF (found by value with
-- r27b/py/tabfind.py / dmd26.py, the code read with tdis.py):
--
--   * overlords 0x0A-0x10 (Overlord0A_FallingSquare, GBA 0x080CCB58; the
--     GBA's overlord table 0x172978 sends all seven to it -- 0x0A directly,
--     0x0B-0x10 through thunks -- the GBA has a 7th path, room 0x79's
--     0x10): Dungeon_LoadSingleOverlord (GBA 0x080CB7FC) gives 0x0A, 0x0B
--     and 0x10 a 160-frame wait (literal at 0x080CB888) that counts once
--     the overlord has been on screen (gen3); then every 16 frames
--     SpawnFallingTile (0x080CCCDC: Garnish 3 at (x, y + 16), 31 frames)
--     and the overlord steps 16 px along its path (the GBA's path pointers
--     0x172B1C, path lengths 0x172B14 -- tiles per path, kCrumbleTilePath_X
--     / _Y as lo / hi byte pairs 0x172B04 / 0x172B08 / 0x172B0C /
--     0x172B10); the last tile ends it. Garnish03_FallingTile (GBA
--     kCrumbleTile_Char / Flags / Ext / XY 0x172E0F / 0x172E14 / 0x172E19 /
--     0x172E1E): at countdown 30 Dungeon_UpdateTileMapWithCommonTile(x, y -
--     16, 4) puts the hole (kPrepSpriteInducedDma_Srcs[2], the GBA's
--     pointer table 0x152A70; attribute = attributes_for_tile[word 4]) --
--     the pit attribute that Dungeons26.lua's pits make Link fall through.
--   * Ganon_SpawnFallingTilesOverlord: M.ganonFloor (Ganon.lua calls it at
--     the landing): overlords kGanon_Ov_Type 0x0C-0x0F at kGanon_Ov_X / Y
--     (Ganon.lua's tables) in Link's 256-px quadrant, no wait.
--   * overlord 0x15 (Overlord14_TileRoom, GBA 0x080CC988; its on-screen
--     test is the GBA's: (x + 8 - cam x) & 0xFF00 == 0 and y + 0x50 - cam y
--     <= 0x17F): gen2 counts down to 0x80, then TileRoom_SpawnTile
--     (0x080CCA5C) a 0x94 with sprite_E 1 at kSpawnFlyingTile_X / Y
--     (0x172A54 / 0x172A6A; y - 8), 0xE0 between tiles, 22 tiles.
--   * 0x94 with E = 1 (Sprite_94_Tile): ai 0 erases the floor under it
--     (common tile 6 = kPrepSpriteInducedDma_Srcs[3]), ai 1 rises 128
--     frames (z speed 4 while delay >= 0x40), ai 2 flies at Link (32,
--     re-aimed every 4th frame of its 16), Sprite_CheckDamageToAndFromLink
--     / a wall / a hit -> it shatters (Garnish 0x16 with sprite_C 0x80:
--     the debris pieces of Drops.lua's tables with char 0xF2, literal at
--     0x080CD868). FlyingTile_Draw: kFlyingTile_Dmd (GBA 0x175778, chars
--     0xB3 / 0x93) + the shadow.
--   * 0xAE-0xB1 (Sprite_AE_Pipe_Down): locates the track
--     (SomariaPlatform_LocatePath), runs to its endpoint (0xBE), waits for
--     Link (Sprite_CheckDamageToLink_ignore_layer; Pipe_ValidateEntry:
--     not while carrying / thrown back), walks him in (4 frames), carries
--     him hidden at 3 px a frame (Link pulled 1 px a step to (x - 8, y -
--     14)) to the other endpoint and walks him out (24 frames).
--   * 0xED / 0xEF-0xF1 (Sprite_ED_SomariaPlatform): LocatePath, then while
--     Link stands on it (player_on_somaria_platform 2) it rides the track
--     (kSomariaPlatform_Xvel / Yvel 0x17D484 / 0x17D48B), every 8 frames
--     the tile under it (SomariaPlatform_HandleJunctions: kSomariaPlatform_
--     TransitDir 0x17D4B8, Keys1-6 0x17D4BC.., the d-pad picks the way),
--     dragging Link (kSomariaPlatform_DragX / Y 0x17D498 / 0x17D49F,
--     SomariaPlatform_HandleDrag / DragLink); stopped at a transit tile /
--     an endpoint (player_on_somaria_platform 1) Link can walk off; room
--     0x24 holds it still. Pits do not take Link while he is on it
--     (TileBehavior_Pit). SomariaPlatform_Draw: kSomariaPlatform_Dmd (GBA
--     0x17D510, char 0xCC) by delay_aux4 & 12 (it grows in).
--   * the Cane of Somaria's side (team A's item calls these):
--     M.somariaBlock(game, x, y, lower) = Ancilla2C_SomariaBlock's test in
--     a cane-ride room (dung_unk6: the room draws object 0xF83 / 0xF8E,
--     LoadType1ObjectSubtype3 3 / 0x0E -- read from the room objects): the
--     block's points kSomarianBlock_Coll_X / Y (s16, GBA 0x17FA84 /
--     0x17FA6C) on a 0xB6 / 0xBC tile -> the poof (true: the block is
--     gone); M.somariaBlockCreated(game, x, y, lower) =
--     SomariaBlock_CheckForTransitTile (kSomariaTransitLine_X / Y 0x17FA08 /
--     0x17F9F0); M.somariaPoof(game, x, y, lower) =
--     AncillaAdd_SomariaPlatformPoof (the old platform goes, 8 frames
--     later) M.somariaPlatform(game, x, y, lower) = Ancilla39's spawn: a
--     0xED at (x & ~7 | 4, y & ~7 | 4), its direction by the track around
--     (kSomarianPlatformPoof_Tab0, GBA 0x17FC2E; the GBA's code 0x0811F8D4).
--
-- OURS: no sound; the platform's superficial bomb blast (0x4A) is only
-- counted (game.platformPoofs); Link's walking / pipe animation poses are
-- the normal walk; the pipe's Link_ResetProperties_A / flag_is_link_
-- immobilized stop only his walking and damage (not the sword / items); the
-- hookshot / spin-attack exceptions of the platform are not checked; drag
-- is applied to Link's position in Doors.move (Link_HandleVelocityAndSand-
-- Drag) on the next frame; the flying tile counts as an enemy for the
-- room's kill tags (FIGHTS) only through its type; the sprite limits
-- (16 sprites, 8 overlords, 30 garnishes) are not modelled; the falling
-- tile garnish is drawn at the sprites' priority of Link's level.

local bit = require("bit")
local band, bor, bxor, rshift, lshift, bnot = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift, bit.bnot

local M = { NAME = "floors27" }

M.OFF = {
  ovFuncs = 0x172978,                     -- the GBA overlord table (type 1 first)
  fsLen = 0x172B14, fsPtr = 0x172B1C,     -- 7 path lengths / 7 path pointers
  fsXlo = 0x172B04, fsXhi = 0x172B08, fsYlo = 0x172B0C, fsYhi = 0x172B10,
  fsDelay = 0x0CB888,                     -- movs r1, #0xA0 (Dungeon_LoadSingleOverlord)
  crChar = 0x172E0F, crFlags = 0x172E14, crExt = 0x172E19, crXY = 0x172E1E,
  dmaSrcs = 0x152A70,                     -- kPrepSpriteInducedDma_Srcs (10 pointers)
  tileX = 0x172A54, tileY = 0x172A6A,     -- kSpawnFlyingTile_X / Y (22)
  tileDmd = 0x175778,                     -- kFlyingTile_Dmd (8)
  debrisChar = 0x0CD868,                  -- movs r4, #0xF2 (Garnish16, sprite_C >= 0x80)
  platDmd = 0x17D510,                     -- kSomariaPlatform_Dmd (16)
  platXv = 0x17D484, platYv = 0x17D48B, dragX = 0x17D498, dragY = 0x17D49F,
  transit = 0x17D4B8, keys = 0x17D4BC,    -- TransitDir (4), Keys1..6 (4 each)
  poof = 0x17FC2E,                        -- kSomarianPlatformPoof_Tab0 (4)
  collX = 0x17FA84, collY = 0x17FA6C,     -- kSomarianBlock_Coll_X / Y (12 s16)
  lineX = 0x17FA08, lineY = 0x17F9F0,     -- kSomariaTransitLine_X / Y (12 s16)
}
M.FS_FIRST, M.FS_LAST, M.TILEROOM = 0x0A, 0x10, 0x15
M.TILE, M.PLATFORM = 0x94, 0xED
M.PIPE_DIRS = { [0] = 8, 4, 2, 1 }      -- kPipe_Dirs: the joypad bits of up / down / left / right
M.TYPES = { [0x94] = true, [0xAE] = true, [0xAF] = true, [0xB0] = true, [0xB1] = true,
            [0xED] = true, [0xEF] = true, [0xF0] = true, [0xF1] = true }
M.FIGHTS = { [0x94] = true }

-- the room objects that make a room a cane-ride room (dung_unk6):
-- type-1 subtype-3 objects 0x03 / 0x0E (b2 >= 0xF8, not b0 & 0xFC == 0xFC)
local function caneRooms(rom, R)
  local out = {}
  for r = 0, (R.roomCount or 296) - 1 do
    local p = rom:ptr(R.roomObjects + r * 4)
    if p then
      local o, n = p + 2, 0
      for _ = 1, 3 do
        for _ = 1, 2000 do
          local b0, b1, b2 = rom:u8(o), rom:u8(o + 1), rom:u8(o + 2)
          if b0 == 0xFF and b1 == 0xFF then o = o + 2 break end
          if b0 == 0xF0 and b1 == 0xFF then
            o = o + 2
            for _ = 1, 200 do
              if rom:u8(o) == 0xFF and rom:u8(o + 1) == 0xFF then break end
              o = o + 2
            end
            o = o + 2
            break
          end
          if band(b0, 0xFC) ~= 0xFC and b2 >= 0xF8 then
            local idx = bor(lshift(band(b2, 7), 4), lshift(band(b1, 3), 2), band(b0, 3))
            if idx == 0x03 or idx == 0x0E then n = n + 1 end
          end
          o = o + 3
        end
      end
      if n > 0 then out[r] = n end
    end
  end
  return out
end

function M.extract(rom, R, check, D)
  local O = M.OFF
  local s8, s16 = D.s8, D.s16
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local function u32(o) return rom:u16(o) + rom:u16(o + 2) * 65536 end
  local t = { lens = u8(O.fsLen, 7), paths = {}, fsDelay = rom:u8(O.fsDelay) }
  for j = 1, 7 do
    local p = rom:ptr(O.fsPtr + (j - 1) * 4)
    t.paths[j] = p and u8(p, t.lens[j]) or {}
  end
  t.mvX, t.mvY = {}, {}
  for i = 1, 4 do
    t.mvX[i] = s16({ rom:u8(O.fsXlo + i - 1) + rom:u8(O.fsXhi + i - 1) * 256 })[1]
    t.mvY[i] = s16({ rom:u8(O.fsYlo + i - 1) + rom:u8(O.fsYhi + i - 1) * 256 })[1]
  end
  check(u32(O.ovFuncs + (M.FS_FIRST - 1) * 4) == 0x080CCB59 and u32(O.ovFuncs + (M.TILEROOM - 1) * 4) == 0x080CC989
        and t.fsDelay == 0xA0, "overlord table: falling squares / tile room")
  check(t.lens[1] == 26 and t.lens[2] == 42 and t.lens[7] == 25 and #t.paths[7] == 25 and t.paths[1][1] == 2
        and t.paths[1][7] == 1 and t.paths[7][3] == 0 and t.mvX[1] == 16 and t.mvX[2] == -16 and t.mvY[3] == 16
        and t.mvY[4] == -16 and t.mvX[3] == 0, "crumble tile paths (kCrumbleTilePathData, 7 paths)")
  t.crChar, t.crFlags, t.crExt, t.crXY = u8(O.crChar, 5), u8(O.crFlags, 5), u8(O.crExt, 5), u8(O.crXY, 5)
  check(t.crFlags[1] == 0x30 and t.crFlags[2] == 0x31 and t.crExt[1] == 0 and t.crExt[2] == 2 and t.crXY[1] == 4
        and t.crXY[2] == 0, "kCrumbleTile_* (GBA chars)")
  t.dma = {}
  for k = 0, 9 do
    local p = rom:ptr(O.dmaSrcs + k * 4)
    t.dma[k] = p and rom:bytesU16(p, 4) or { 0, 0, 0, 0 }
  end
  check(t.dma[2][1] == 0x1E9 and t.dma[2][4] == 0x1E9 and t.dma[0][1] == 0x1EC, "kPrepSpriteInducedDma_Srcs")
  t.tileX, t.tileY = u8(O.tileX, 22), u8(O.tileY, 22)
  check(t.tileX[1] == 0x70 and t.tileX[22] == 0x70 and t.tileY[1] == 0x80 and t.tileY[12] == 0xB0, "kSpawnFlyingTile_X / Y")
  t.tileDmd = D.dmd(rom, O.tileDmd, 8)
  t.debrisChar = rom:u8(O.debrisChar)
  check(t.tileDmd[2][1] == 8 and t.tileDmd[3][2] == 8 and t.tileDmd[2][4] == 0x40 and t.tileDmd[4][4] == 0xC0
        and t.debrisChar == 0xF2, "kFlyingTile_Dmd / debris char")
  t.platDmd = D.dmd(rom, O.platDmd, 16)
  check(t.platDmd[1][1] == -16 and t.platDmd[1][5] == 2 and t.platDmd[5][1] == -13 and t.platDmd[13][2] == -8
        and t.platDmd[4][4] == 0xC0, "kSomariaPlatform_Dmd")
  t.xv, t.yv = s8(u8(O.platXv, 8)), s8(u8(O.platYv, 8))
  t.dragX, t.dragY = s8(u8(O.dragX, 8)), s8(u8(O.dragY, 8))
  t.transit = u8(O.transit, 4)
  t.keys = {}
  for k = 1, 6 do t.keys[k] = u8(O.keys + (k - 1) * 4, 4) end
  t.poof = u8(O.poof, 4)
  t.collX, t.collY = s16(rom:bytesU16(O.collX, 12)), s16(rom:bytesU16(O.collY, 12))
  t.lineX, t.lineY = s16(rom:bytesU16(O.lineX, 12)), s16(rom:bytesU16(O.lineY, 12))
  check(t.xv[3] == -16 and t.yv[1] == -16 and t.yv[2] == 16 and t.dragX[3] == -1 and t.dragY[1] == -1
        and t.transit[1] == 4 and t.keys[1][1] == 3 and t.keys[6][3] == 3 and t.poof[1] == 1 and t.poof[3] == 3,
        "Somaria platform tables")
  check(t.collX[3] == -8 and t.collY[1] == -8 and t.lineX[7] == -16 and t.lineY[1] == -16 and t.lineY[12] == 8,
        "Somaria block tables")
  t.caneRooms = caneRooms(rom, R)
  check(t.caneRooms[0x24] == 1 and t.caneRooms[0xB5] == 6 and t.caneRooms[0xC6] == 8 and not t.caneRooms[0x14],
        "cane-ride rooms (objects 0xF83 / 0xF8E)")
  return t
end

local function DG() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = DG().tabs(game); return d and d.floors27 end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function A() return require("src.zelda.alttp.Actors") end
local function u8(v) return band(v, 0xFF) end
local function i8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

-- another module's sprite of this type (the Pirogusu shares 0x94)
local function other(t)
  for _, m in ipairs(require("src.zelda.alttp.Palace").EXT) do
    if m ~= M and m.TYPES[t] then return m end
  end
end
local function mine(a) return a.type ~= 0x94 or a.flyTile end

-- ------------------------------------------------------------ tiles
-- the room's attributes_for_tile (Interior.attributes)
local function attrTable(inside)
  if not inside.f27attr then
    inside.f27attr = require("src.zelda.alttp.Interior").attributes(inside.data.roomIdx, inside.aux)
  end
  return inside.f27attr
end

-- Dungeon_PrepSpriteInducedDma(x, y, v): four BG2 words and their attribute
function M.commonTile(game, x, y, v)
  local inside = game.interior
  local tb = T(game)
  if not inside or not tb then return end
  local w = tb.dma[rshift(v, 1)]
  local pos = lshift(band(y + 1, 0x1F8), 3) + rshift(band(x, 0x1F8), 3)
  local cells = { pos, pos + 64, pos + 1, pos + 65 }
  local at = attrTable(inside)[band(w[4], 0x3FF)] or 0
  local W = require("src.zelda.alttp.Interior").WALKABLE
  for i, c in ipairs(cells) do
    if c >= 0 and c < 4096 then
      inside.patch[c] = w[i]
      inside.attrs[c] = at
      inside.grid[c] = not W[at]
    end
  end
  game.roomImages = nil
  game.commonTiles = (game.commonTiles or 0) + 1
  return at
end

-- the garnishes (Garnish 3: the falling tile, 0x16: the flying tile's debris)
local function garnish(game, kind, x, y, extra)
  game.f27g = game.f27g or {}
  local g = { kind = kind, x = x, y = y, cd = 31, room = game.interior and game.interior.room,
              lower = game.interior and game.interior.lower or false }
  if extra then for k, v in pairs(extra) do g[k] = v end end
  game.f27g[#game.f27g + 1] = g
  return g
end

local function garnishFrame(game)
  local list = game.f27g
  if not list or #list == 0 then return end
  local here = game.interior and game.interior.room
  local keep = {}
  for _, g in ipairs(list) do
    g.cd = g.cd - 1
    if g.room == here and g.cd > 0 then
      keep[#keep + 1] = g
      if g.kind == 3 and g.cd == 30 then
        -- Dungeon_UpdateTileMapWithCommonTile(x, y - 16, 4): the hole
        M.commonTile(game, g.x, g.y - 16, 4)
        game.floorHoles = (game.floorHoles or 0) + 1
      end
    end
  end
  game.f27g = keep
end

-- ------------------------------------------------------------ overlords
-- Overlord0A_FallingSquare (types 0x0A-0x10)
local function fallingSquare(self, o, camx, camy)
  local game = self.game
  local tb = T(game)
  if not o.fsInit then
    o.fsInit = true
    o.gen1, o.gen3 = 0, 0
    o.gen2 = (o.type == 0x0A or o.type == 0x0B or o.type == 0x10) and tb.fsDelay or 0
  end
  if o.gen2 ~= 0 then
    if o.gen3 ~= 0 then o.gen2 = o.gen2 - 1 return end
    if band(o.x - camx, 0xFF00) == 0 and band(o.y - camy, 0xFF00) == 0 then o.gen3 = o.gen3 + 1 end
    return
  end
  o.gen2 = 16
  -- SpawnFallingTile
  garnish(game, 3, o.x, o.y + 16)
  game.fallingTiles = (game.fallingTiles or 0) + 1
  local j = o.type - M.FS_FIRST + 1
  o.gen1 = o.gen1 + 1
  if o.gen1 == tb.lens[j] then o.type, o.done = 0, true end
  local s = tb.paths[j][o.gen1]
  if s then
    o.x = o.x + (tb.mvX[s + 1] or 0)
    o.y = o.y + (tb.mvY[s + 1] or 0)
  end
end

-- Overlord14_TileRoom (GBA 0x15) / TileRoom_SpawnTile
local function tileRoom(self, o, camx, camy)
  local game = self.game
  local tb = T(game)
  if band(o.x + 8 - camx, 0xFF00) ~= 0 then return end
  if band(o.y + 0x50 - camy, 0xFFFF) > 0x17F then return end
  o.gen2 = u8((o.gen2 or 0) - 1)
  if o.gen2 ~= 0x80 then return end
  local i = o.gen1 or 0
  M._tile = true
  local a = DG().spawn(self, M.TILE, band(o.x, 0xFF00) + tb.tileX[i + 1], band(o.y, 0xFF00) + u8(tb.tileY[i + 1] - 8), o.lower)
  M._tile = nil
  if not a then o.gen2 = 0x81 return end
  game.flyTiles = (game.flyTiles or 0) + 1
  o.gen1 = i + 1
  if o.gen1 ~= 22 then o.gen2 = 0xE0 else o.type, o.done = 0, true end
end

function M.overlord(self, o, camx, camy)
  if not T(self.game) then return false end
  if o.type >= M.FS_FIRST and o.type <= M.FS_LAST then fallingSquare(self, o, camx, camy) return true end
  if o.type == M.TILEROOM then tileRoom(self, o, camx, camy) return true end
  return false
end

-- Ganon_SpawnFallingTilesOverlord: Ganon.lua's landing (t = the count
-- before it was raised, 0..3)
function M.ganonFloor(self, a, t)
  local game = self.game
  local g = require("src.zelda.alttp.Ganon").tabs(game)
  if not g or not T(game) or t < 0 or t > 3 then return end
  local lk = game.link
  self.overlords = self.overlords or {}
  local o = { type = g.ovType[t + 1], x = band(lk.x, 0xFF00) + g.ovX[t + 1], y = band(lk.y, 0xFF00) + g.ovY[t + 1],
              lower = a.lower, gen1 = 0, gen2 = 0, gen3 = 0, fsInit = true, k = #self.overlords }
  self.overlords[#self.overlords + 1] = o
  game.ganonFloors = (game.ganonFloors or 0) + 1
  return o
end

-- ------------------------------------------------------------ the track
local function tileAt(game, x, y)
  local at = game.interior.attrs
  return at[lshift(band(y, 0x1F8), 3) + rshift(band(x, 0x1F8), 3)] or 0
end
-- SomariaPlatformAndPipe_CheckTile (GetTileAttribute(0): the BG2 table)
local function checkTile(game, a) return tileAt(game, a.x, a.y) end

local function pad(game)
  local i = game.input
  local function h(k) return i and i.isDown and i.isDown(k) end
  if game.f27pad then return game.f27pad end
  return (h("up") and 8 or 0) + (h("down") and 4 or 0) + (h("left") and 2 or 0) + (h("right") and 1 or 0)
end
local function pick(t)
  if band(t, 8) ~= 0 then return 0 elseif band(t, 4) ~= 0 then return 1
  elseif band(t, 2) ~= 0 then return 2 elseif band(t, 1) ~= 0 then return 3 end
end

-- SomariaPlatform_HandleJunctions
local function junctions(game, a)
  local tb = T(game)
  local e, d = a.E or 0, a.D or 0
  local K = tb.keys
  if e == 0xB2 or e == 0xB5 then a.D = bxor(d, 3)
  elseif e == 0xB3 or e == 0xB4 then a.D = bxor(d, 2)
  elseif e == 0xB6 then
    a.ai = 1
    if band(pad(game), tb.transit[d + 1]) ~= 0 then a.ai, a.D = 0, bxor(d, 1) end
    game.onPlatform = 1
  elseif e >= 0xB7 and e <= 0xBA then
    local k = e - 0xB6
    local n = pick(band(pad(game), K[k][d + 1]))
    if n then a.D = n
    elseif e == 0xB7 and d == 0 then a.D = 2
    elseif e == 0xB8 and d == 1 then a.D = 2
    elseif e == 0xB9 and d == 2 then a.D = 0
    elseif e == 0xBA and d == 3 then a.D = 0 end
    a.ai = 0
  elseif e == 0xBB then
    local n = pick(band(pad(game), K[5][d + 1]))
    if n then a.D = n end
  elseif e == 0xBC then
    a.ai = 1
    local t = band(pad(game), K[6][d + 1])
    if t ~= 0 then a.D, a.ai = pick(t) or 3, 0 end
    game.onPlatform = 1
  elseif e == 0xBE then
    a.ai, a.D = 0, bxor(d, 1)
    game.onPlatform = 1
  end
end

-- SomariaPlatformAndPipe_HandleMovement
local function handleMovement(game, a)
  local tb = T(game)
  junctions(game, a)
  a.vx, a.vy = tb.xv[(a.D or 0) + 1], tb.yv[(a.D or 0) + 1]
end

-- SomariaPlatform_HandleDrag
local function handleDrag(game, a)
  if band(bxor(a.D or 0, a.headDir or 0), 2) ~= 0 then
    local nx = band(a.x, bnot(7)) + 4
    if nx ~= a.x then game.dragX = i8(nx - a.x); a.x, a.fx = nx, 0 end
    local ny = band(a.y, bnot(7)) + 4
    if ny ~= a.y then game.dragY = i8(ny - a.y); a.y, a.fy = ny, 0 end
  end
end

-- SomariaPlatform_LocatePath
local function locatePath(game, a)
  for _ = 1, 64 do
    local t = checkTile(game, a)
    a.E = t
    if t >= 0xB0 and t < 0xBF then break end
    a.x, a.y = a.x + 8, a.y + 8
  end
  a.x = band(a.x, bnot(7)) + 4
  a.y = band(a.y, bnot(7)) + 4
  a.fx, a.fy = 0, 0
  a.headDir = a.D
  handleMovement(game, a)
  a.G = (a.G or 0) + 1
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  a.game = self.game
  if a.type == 0x94 and not M._tile then
    local m = other(0x94)
    if m and m.prep then m.prep(self, a) end
    return
  end
  if not T(self.game) then return end
  local t = a.type
  a.G = 0
  if t == 0x94 then
    -- TileRoom_SpawnTile
    a.flyTile, a.E, a.hp, a.bump, a.flags2, a.oamF = true, 1, 0, 4, 4, 1
    a.noTouch, a.untouchable = true, true
    a.flags5, a.drop = 0, nil
  elseif t >= 0xAE and t <= 0xB1 then
    a.pipe, a.D = true, t - 0xAE
    a.noTouch, a.untouchable = true, true
  else
    a.platform = true
    a.noTouch, a.untouchable = true, true
  end
end

-- ------------------------------------------------------------ Sprite_94_Tile
local function breakTile(self, a)
  local game = self.game
  a.dead, a.pend, a.inv = true, nil, 0
  garnish(game, 0x16, a.x, a.y - (a.z or 0), { flags = a.oamF or 1, lower = a.lower })
  game.flyTileBreaks = (game.flyTileBreaks or 0) + 1
end

local function anim(a)
  a.sub2 = u8((a.sub2 or 0) + 1)
  a.gfx = band(rshift(a.sub2, 2), 1)
end

local function flyTile(self, a, lk)
  local game = self.game
  local h = H()
  if (a.inv or 0) > 0 or a.pend then breakTile(self, a) return end
  a.untouchable = true
  local ai = a.ai
  if ai == 0 then
    M.commonTile(game, a.x, band(a.y, 0xFF00) + u8(a.y + 8), 6)
    a.ai, a.delay = 1, 128
  elseif ai == 1 then
    if a.delay == 0 then
      a.ai, a.delay = 2, 16
      a.vx, a.vy = DG().towardsLink(a, lk, 32)
    else
      if a.delay >= 0x40 then a.vz = 4; h.moveZ(a) end
      anim(a)
    end
  elseif ai == 2 then
    a.untouchable = false
    if a.delay ~= 0 and band(a.delay, 3) == 0 then a.vx, a.vy = DG().towardsLink(a, lk, 32) end
    if DG().contact(self, a, lk) then breakTile(self, a) return end
    h.moveXY(a)
    if h.tileCollision(self, a) ~= 0 then breakTile(self, a) return end
    anim(a)
  end
end

-- ------------------------------------------------------------ Sprite_AE_Pipe_Down
local function onLink(self, a, lk)
  return DG().contact(self, a, lk, { harmless = true, anyLayer = true, always = true })
end

local function moveAxis(coord, sub, vel)
  local tmp = (sub or 0) + vel * 16 + coord * 256
  return math.floor(tmp / 256), tmp % 256
end
-- Pipe_HandlePlayerMovement: Link walks one frame in `dir` (joypad bits)
local function linkWalk(game, dir)
  local lk = game.link
  local L = require("src.zelda.alttp.Link")
  local dx = (band(dir, 1) ~= 0 and 1 or 0) - (band(dir, 2) ~= 0 and 1 or 0)
  local dy = (band(dir, 4) ~= 0 and 1 or 0) - (band(dir, 8) ~= 0 and 1 or 0)
  local t = lk.data and lk.data.t
  local vel = t and t.speedMod and t.speedMod[(lk.speedSetting or 0) + 1] or 24
  if dx ~= 0 then lk.x, lk.subX = moveAxis(lk.x, lk.subX, dx * vel) end
  if dy ~= 0 then lk.y, lk.subY = moveAxis(lk.y, lk.subY, dy * vel) end
  lk.facing = (dy < 0 and L.UP) or (dy > 0 and L.DOWN) or (dx < 0 and L.LEFT) or L.RIGHT
  lk.moving = true
end

local function pipe(self, a, lk)
  local game = self.game
  local g = a.G or 0
  if g == 0 then
    game.pipeOwner = nil
    locatePath(game, a)
  elseif g == 1 then
    local t = checkTile(game, a)
    if t == 0xBE then
      a.G = 2
      a.D = bxor(a.D, 1)
      t = a.D
    end
    a.E, a.headDir = t, a.D
    handleMovement(game, a)
    H().moveXY(a)
  elseif g == 2 then
    if game.pipeOwner == nil and onLink(self, a, lk) then
      -- Pipe_ValidateEntry: not while carrying or thrown back
      if not (game.carry or game.recoil) then
        a.G, a.aux1 = 3, 4
        game.pipeOwner = a
        game.pipeRides = (game.pipeRides or 0) + 1
        if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
      elseif game.dash then
        require("src.zelda.alttp.Dash").cancel(game)
      end
    end
  elseif g == 3 then
    if a.aux1 == 0 then a.G = 4; game.pipeHide = true
    else linkWalk(game, M.PIPE_DIRS[a.D]) end
  elseif g == 4 then
    for _ = 1, 3 do
      a.A = u8((a.A or 0) + 1)
      if band(a.A, 7) == 0 then
        local t = checkTile(game, a)
        if t ~= a.E then
          a.E = t
          if t == 0xBE then a.G, a.aux1 = 5, 24 end
          a.headDir = a.D
          handleMovement(game, a)
          handleDrag(game, a)
          game.dragX, game.dragY = 0, 0
        end
      end
      H().moveXY(a)
      local x, y = a.x - 8, a.y - 14
      if x ~= lk.x then lk.x = lk.x + ((x < lk.x) and -1 or 1) end
      if y ~= lk.y then lk.y = lk.y + ((y < lk.y) and -1 or 1) end
    end
    local L = require("src.zelda.alttp.Link")
    lk.facing = ({ [0] = L.UP, L.DOWN, L.LEFT, L.RIGHT })[a.D]
    if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
  elseif g == 5 then
    if a.aux1 == 0 then
      game.pipeOwner, game.pipeHide, game.onPlatform = nil, nil, 0
      a.G = 2
      game.pipeExits = (game.pipeExits or 0) + 1
    else
      linkWalk(game, M.PIPE_DIRS[bxor(a.D, 1)])
    end
  end
end

-- ------------------------------------------------------------ Sprite_ED_SomariaPlatform
local function platform(self, a, lk)
  local game = self.game
  local tb = T(game)
  if (a.G or 0) == 0 then
    locatePath(game, a)
    a.aux4 = 14
    game.onPlatform = 0
    game.platformPoofs = (game.platformPoofs or 0) + 1
    return
  end
  local curx, cury = a.x, a.y
  if (game.dragX or 0) == 0 and (game.dragY or 0) == 0 and not game.pitFall and onLink(self, a, lk) then
    a.C = 1
    if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
    if (a.ai or 0) ~= 0 then handleMovement(game, a) return end
    a.A = u8((a.A or 0) + 1)
    game.onPlatform = 2
    if band(a.A, 7) == 0 then
      local t = checkTile(game, a)
      if t ~= a.E then
        a.E, a.headDir = t, a.D
        handleMovement(game, a)
        handleDrag(game, a)
      end
    end
    if self.inside.room ~= 0x24 then
      local d = (a.D or 0) + 1
      game.dragX = (game.dragX or 0) + tb.dragX[d]
      game.dragY = (game.dragY or 0) + tb.dragY[d]
      H().moveXY(a)
      -- SomariaPlatform_DragLink
      local x, y = curx - 8 - lk.x, cury - 16 - lk.y
      if x ~= 0 then game.dragX = game.dragX + ((x < 0) and -1 or 1) end
      if y ~= 0 then game.dragY = game.dragY + ((y < 0) and -1 or 1) end
      game.platformSteps = (game.platformSteps or 0) + 1
    else
      game.onPlatform = 1
    end
    return
  end
  if (a.C or 0) ~= 0 then game.onPlatform, a.C = 0, 0 end
end

function M.update(self, a, lk)
  if not mine(a) then
    local m = other(a.type)
    if m and m.update then return m.update(self, a, lk) end
    return
  end
  if not T(self.game) then return end
  if a.flyTile then return flyTile(self, a, lk) end
  if a.pipe then return pipe(self, a, lk) end
  if a.platform then return platform(self, a, lk) end
end

function M.swordImmune(a, how)
  if not mine(a) then
    local m = other(a.type)
    return m and m.swordImmune and m.swordImmune(a, how) or false
  end
  return false
end

function M.died(self, a)
  if not mine(a) then
    local m = other(a.type)
    if m and m.died then m.died(self, a) end
  end
end

function M.enterRoom(self, inside)
  local game = self.game
  game.onPlatform, game.pipeOwner, game.pipeHide = 0, nil, nil
  game.dragX, game.dragY = 0, 0
  local tb = T(game)
  inside.caneRide = tb and tb.caneRooms[inside.room] or nil
  inside.f27attr = nil
end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

function M.draw(spr, a, x, y, frame, game)
  if not mine(a) then
    local m = other(a.type)
    if m and m.draw then return m.draw(spr, a, x, y, frame, game) end
    return false
  end
  local g = game or a.game
  local tb = g and T(g)
  if not tb then return true end
  if a.flyTile then
    -- FlyingTile_Draw + SpriteDraw_Shadow
    spr:drawDmd(a, tb.tileDmd, (a.gfx or 0) * 4, 4, x, y - (a.z or 0), a.oamF or 1)
    if not spr:hasShadow(0x94) then spr:drawShadow(x, y, 0x94) end
  elseif a.platform and (a.G or 0) >= 1 then
    spr:drawDmd(a, tb.platDmd, band(a.aux4 or 0, 12), 4, x, y, oamF(spr, 0xED))
  end
  return true
end

-- the garnishes over the sprites (Garnish03_FallingTile, Garnish16)
function M.drawGarnish(game, spr, cx, cy)
  local tb = T(game)
  local list = game.f27g
  if not tb or not list or #list == 0 then return end
  local here = game.interior and game.interior.room
  local dt = game.data.t and game.data.t.drops
  for _, g in ipairs(list) do
    if g.room == here then
      if g.kind == 3 then
        local j = rshift(g.cd, 3)
        local o = tb.crXY[j + 1] or 0
        spr:oam(g.x + o - cx, g.y + o - 16 - cy, tb.crChar[j + 1], tb.crFlags[j + 1], tb.crExt[j + 1])
      elseif g.kind == 0x16 and dt and dt.debrisX then
        local base = lshift(bxor(rshift(g.cd, 2), 7), 2)
        for i = 3, 0, -1 do
          local j = i + base
          spr:oam(g.x - cx + (dt.debrisX[j + 1] or 0), g.y - cy + (dt.debrisY[j + 1] or 0), tb.debrisChar,
                  bor(dt.debrisFlags[j + 1] or 0, g.flags or 1), 0)
        end
      end
    end
  end
end

-- ------------------------------------------------------------ the Cane of Somaria
-- (team A's cane calls these; x, y = the block's position)
local function anyAttr(game, x, y, lower)
  local inside = game.interior
  local t = (lower and inside.attrsLo) or inside.attrs
  return t[lshift(band(y, 0x1F8), 3) + rshift(band(x, 0x1F8), 3)] or 0
end

-- Ancilla39_SomariaPlatformPoof's spawn (the poof's end)
function M.somariaPlatform(game, x, y, lower)
  local actors = game.actors
  local tb = T(game)
  if not actors or not tb or not game.interior then return nil end
  local sx, sy = bor(band(x, bnot(7)), 4), bor(band(y, bnot(7)), 4)
  game.onPlatform = 0
  local a = DG().spawn(actors, M.PLATFORM, sx, sy, lower)
  if not a then return nil end
  local inside = game.interior
  local at = (lower and inside.attrsLo) or inside.attrs
  local pos = rshift(band(sx, 0x1F8), 3) + lshift(band(sy, 0x1F8), 3)
  local t = 0
  if band(at[pos - 64] or 0, 0xF0) ~= 0xB0 then
    t = 1
    if band(at[pos + 64] or 0, 0xF0) ~= 0xB0 then
      t = 2
      if band(at[pos - 1] or 0, 0xF0) ~= 0xB0 then t = 3 end
    end
  end
  a.D = tb.poof[t + 1]
  game.platformsMade = (game.platformsMade or 0) + 1
  return a
end

-- AncillaAdd_SomariaPlatformPoof: the old platform goes; the new one 8
-- frames later (ancilla_aux_timer 7 counting below 0)
function M.somariaPoof(game, x, y, lower)
  for _, b in ipairs(game.actors and game.actors.list or {}) do
    if b.type == M.PLATFORM and not b.dead then b.dead = true end
  end
  game.onPlatform = 0
  game.f27poof = { t = 8, x = x, y = y, lower = lower, room = game.interior and game.interior.room }
  return true
end

local function blockTest(game, x, y, lower, X, Y, list)
  local inside = game.interior
  local tb = T(game)
  if not inside or not tb or not inside.caneRide then return false end
  for _, j in ipairs(list) do
    local px, py = x + tb[X][j + 1], y + tb[Y][j + 1]
    local v = anyAttr(game, px, py, lower)
    if v == 0xB6 or v == 0xBC then return M.somariaPoof(game, px, py, lower) end
  end
  return false
end

-- Ancilla2C_SomariaBlock's test (a resting block in a cane-ride room)
function M.somariaBlock(game, x, y, lower, frame)
  local j = band(frame or game.frame or 0, 3)
  return blockTest(game, x, y, lower, "collX", "collY", { j, j + 4, j + 8 })
end

-- SomariaBlock_CheckForTransitTile (the block just made)
function M.somariaBlockCreated(game, x, y, lower)
  return blockTest(game, x, y, lower, "lineX", "lineY", { 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0 })
end

-- dung_unk6 for the cane
function M.caneRideRoom(game) return game.interior and game.interior.caneRide ~= nil end

-- ------------------------------------------------------------ per frame
local function frame(actors)
  local game = actors.game
  if not game or not game.interior or not T(game) then return end
  garnishFrame(game)
  local p = game.f27poof
  if p then
    if p.room ~= game.interior.room then game.f27poof = nil
    else
      p.t = p.t - 1
      if p.t <= 0 then game.f27poof = nil; M.somariaPlatform(game, p.x, p.y, p.lower) end
    end
  end
end

-- ------------------------------------------------------------ install
function M.install(G, D)
  local P = require("src.zelda.alttp.Palace")
  -- run before any other module that claims one of these types (0x94 is
  -- also the Pirogusu: the rest goes on to it)
  local ext = P.EXT
  local me, first
  for i, m in ipairs(ext) do
    if m == M then me = i end
  end
  for i, m in ipairs(ext) do
    if m ~= M and not first then
      for t in pairs(M.TYPES) do if m.TYPES[t] then first = i break end end
    end
  end
  if me and first and first < me then
    table.remove(ext, me)
    table.insert(ext, first, M)
  end
  -- pits do not take Link on a platform (TileBehavior_Pit)
  local pit0 = D.pitCheck
  function D.pitCheck(g)
    if (g.onPlatform or 0) ~= 0 or g.pipeOwner then return false end
    return pit0(g)
  end
  -- Link's walking: the pipe holds him, the platform drags him
  local Doors = require("src.zelda.alttp.Doors")
  local move0 = Doors.move
  function Doors.move(g, inp)
    if g.pipeOwner then
      g.dragX, g.dragY = 0, 0
      local lk = g.link
      lk.dirLast = 0
      return
    end
    local dx, dy = g.dragX or 0, g.dragY or 0
    g.dragX, g.dragY = 0, 0
    local lk = g.link
    if (g.onPlatform or 0) == 2 then
      lk.x, lk.y = lk.x + dx, lk.y + dy
      lk.dirLast, lk.moving = 0, false
      return
    end
    local r = move0(g, inp)
    lk.x, lk.y = lk.x + dx, lk.y + dy
    return r
  end
  -- link_disable_sprite_damage in the pipe; hidden (link_visibility_status 12)
  local hurt0 = G.hurtLink
  function G:hurtLink(dmg, fx, fy)
    if self.pipeOwner then return end
    return hurt0(self, dmg, fx, fy)
  end
  local dl0 = G.drawLink
  function G:drawLink(lk, tint)
    if self.pipeHide and lk == self.link then return end
    return dl0(self, lk, tint)
  end
  -- the garnishes and the cane's poof, one frame
  local Act = A()
  local up0 = Act.update
  function Act:update()
    local r = up0(self)
    frame(self)
    return r
  end
  local da0 = G.drawActors
  if da0 then
    function G:drawActors(cx, cy)
      local r = da0(self, cx, cy)
      if self.f27g and #self.f27g > 0 and self.spriteGfx then
        local spr = self:spriteGfx()
        local Layers = require("src.zelda.alttp.Layers")
        if spr and (not self.inPrioPass or self:inPrioPass(Layers.spritePrio(self.data, self.interior and self.interior.lower))) then
          love.graphics.setColor(1, 1, 1, 1)
          M.drawGarnish(self, spr, cx, cy)
        end
      end
      return r
    end
  end
end

return M
