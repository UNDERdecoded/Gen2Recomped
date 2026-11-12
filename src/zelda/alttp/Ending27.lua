-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CRYSTALS, THE BLIND MAIDEN AND THE ENDING (round 27, team B): the
-- SNES routines the GBA keeps (zelda3 names), loaded by Dungeons26.lua.
-- Every table is the GBA's, read at import (file offsets in OFF, found by
-- value with r27b/f/find1.py / find3.py; the GBA's ending tables by its
-- code, cited below); the texts are decoded at import (never in the repo).
--
-- 1. THE CRYSTAL (a Dark World palace's prize):
--   RoomTag_GetHeartForPrize (Palace.roomTags) drops the prize 0xEB; for a
--   palace whose kBossFinishedFallingItem -> kFallingItem_Type is 0x20 (the
--   crystal; DesertPalace.prizeOf) this module runs it instead of Palace:
--   Ancilla29_MilestoneItemReceipt: 128 frames (byte_7E04C2) before it
--   moves, then from kFallingItem_Z[6] (GBA 0x16E5DB) at z speed -48, a
--   bounce at z speed 0x18 (gravity 1 a frame), at rest after the second
--   landing; Link takes it while z < 24 (Link_ReceiveItem 0x20). Ancilla22 /
--   ItemReceipt_TransmuteToRisingCrystal / Ancilla_RisingCrystal: the
--   crystal rises (y speed -1 a frame down to -16, 1/16 px) until its screen
--   y is under 0x49; then link_has_crystals |= kDungeonCrystalPendantBit
--   (DesertPalace's tb.crystalBit, GBA 0x14CADC) and Module07_18_
--   RescuedMaiden -> CrystalCutscene_Initialize / _SpawnMaiden: every
--   sprite gone, the maiden 0xAB at the quadrant's (0x78, 0x7C), D 1, oam
--   flags 0x0B (Turtle Rock, palace 24: Zelda, flags 9, follower 1's
--   tiles; else follower 6's).
--   Sprite_AB_CrystalMaiden / CrystalMaiden_RunCutscene: states 0 / 1
--   (subscreen), 2 (poly_config1 156 -> < 6 by 3 a frame, the sparkles
--   while >= 64), 3 / 4 (PaletteFilter_SP5F every other frame: she fades
--   in), 5: Link held facing up, the palace's message
--   kCrystalMaiden_Msgs[(palace - 10) >> 1] (GBA 0x17A9EC, GBA numbers =
--   SNES + 3; the Palace of Darkness sets the map icons to 7; Turtle Rock
--   without all 7 crystals says 0x13C; all 7 -> map icons 8), 6: 0x13A "Do
--   you understand?", 7: "Not at all" -> state 5 again, else 0x139, 8:
--   PrepareDungeonExitFromBossFight (game:leaveRoom). The same cutscene for
--   every maiden (Skull Woods, Ice Palace, Misery Mire...). CrystalMaiden_
--   Draw: kCrystalMaiden_SpriteData (Sprites.lua's info.maiden, GBA
--   0x1795B0) with kCrystalMaiden_Dma (GBA 0x179630) on the follower sheet.
--   Read and checked, not drawn: kCrystalMaiden_Pal (GBA 0x18096C, the
--   crystal BG's colours) and kCrystal_Tab0 (GBA 0x14CDA0, where the crystal
--   BG goes by boss room).
--
-- 2. THE BLIND MAIDEN 0xB7 (room 0x45): SpritePrep_BlindMaiden (gone once
--   Blind is beaten -- room 0xAC's boss bit -- or while she follows);
--   Sprite_B7_BlindMaiden: her head turns to Link
--   (Sprite_DirectionToFaceLink ^ 3), Sprite_ShowMessageOnContact 0x122,
--   then Sprite_BecomeFollower: follower 6 (game.progress.follower), the
--   trail from her spot (x + 1, y - 6) towards Link at 24
--   (Follower_MoveTowardsLink). Follower_BasicMover: Link's steps in a
--   20-entry ring while he moves (Follower_CheckGameMode), she walks 15
--   behind; Follower_HandleTrigger: the GBA's kTagalong_IndoorInfos (the old
--   man's import, OldMan.lua) entries for follower 6 (rooms 0xDB / 0xAB,
--   message 0x124) once each; in room 0xAC with the light let in (room
--   0x65's light, RoomObjects.lua) Follower_CheckBlindTrigger at her spot ->
--   ThievesTown.maidenTrigger (Blind_SpawnFromMaiden), follower 0, the
--   trapdoors close (dung_flag_trapdoors_down: game:closeShutters).
--
-- 3. THE ENDING:
--   RoomTag_GanonDoor + Module07_1A_RoomDraw_OpenTriforceDoor: with Ganon
--   beaten (Ganon.lua: progress.ganonBeaten, game.endingPending) and no
--   sprite left, every 4th frame one of kOpenGanonDoor_Tab's 4 pictures
--   (kPredefinedTileData + 0x2556 / 0x2596 / 0x25D6 / 0x2616, GBA 0x164520)
--   at map cells (44..51, 3..6); at the 16th frame the door's attributes
--   (2 at (44, 5..6) / (51, 5..6), floor at 45..50 x 0..6). Walking off the
--   top of room 0 (Dungeon's quadrant transition up) -> Module19_TriforceRoom:
--   the fade, Link at (120, 236) walking up to y < 192, the mosaic, message
--   0x173 (TriforceRoom_PrepGFXSlotForPoly), TriforceRoom_LinkApproachTriforce
--   (up to y < 152, speed setting 0x14 under 169, 64 frames, the pose), R16
--   0x80 frames, PaletteFilter_BlindingWhiteTriforce, INIDISP 15 -> 0.
--   Module1A_Credits (kEndSequence_Funcs, GBA 0x1709AC: 16 scenes, each a
--   load + scroll pair, overworld or dungeon by its handler -- GBA
--   0x080BDBC1 / 0x080BDC09): each scene fades in (INIDISP + 1 every 2nd
--   frame), lasts the GBA's kEnding1_3_Tab0 (0x170950: 0x330, 0x300...;
--   the SNES's are shorter) and fades out the same way. Its text
--   (Credits_AddEndingSequenceText: the GBA reads per-language pointer
--   tables, English at 0x1965D4, read at 0x080BB15C) is [map pos u16][byte
--   count - 1 u16][map words] records up to 0xFFFF; the words are decoded
--   here to letters (the ending font's tile numbers: lower case 0x87.. pal
--   8 / 9 / 11, capitals 0xC001.. two rows high, bit 0x10 the lower row).
--   EndSequence_32 -> Credits_BrightenTriangles (INIDISP + 1 every 16
--   frames) -> Credits_FadeColorAndBeginAnimating (the roll: BG3 + 1 every
--   4th frame, line R18 written as BG3 reaches R18 * 8 -- it enters at the
--   screen's bottom; the GBA's line table 0x197320 (u32 pointers, records
--   [col][count - 1][words], 0xFFFF empty; read at 0x080BB424), lines from
--   the count on are not written -- the table's rows 392.. are the quest
--   history's reference rows -- and the roll ends at the line count (u32
--   at 0x1979A4) * 8, read at 0x080B8EF8) ->
--   Credits_StopCreditsScroll (128) -> Credits_FadeAndDisperseTriangles
--   (192) -> Credits_FadeInTheEnd (a filter step every 8th frame) ->
--   Credits_HangForever ("THE END": the GBA's 4 OAM entries at 0x17099C,
--   y 120, x 160..208).
--   Read and checked: kEnding_Tab1 (0x17064C), kEnding1_TargetScrollY /
--   X (0x170820 / 0x17086C, GBA values), kEnding1_Yvel / Xvel (0x1708B8 /
--   0x170904, read at 0x080B8846 / 0x080B8864).
--
-- OURS: no sound / music. The crystal is a drawn diamond (the receipt
-- sprite sheet, kReceiveItemGfx, is not ported), its sparkles are only
-- counted, the polyhedral 3D crystal is a translucent outline round the
-- maiden and the BG crystal tiles (kCrystal_Tab0) are not drawn; the
-- Module07_18 palette steps are one 32-frame darkening; the rising
-- crystal's 0x49 is zelda3's constant (the GBA's copy is not traced); Link
-- holds it up without the receipt's hold (apui00 is 0 here: no music);
-- the crystal byte of the item menu is progress.inv[0x5A] (the pendants'
-- 0x54 + the SNES's 6: the same 0x20 shift, not traced). The follower is
-- drawn with the crystal maiden's pictures (Tagalong_Draw's per-follower
-- tables are not ported), under Link; the trail restarts at Link when a
-- room / area loads. The Ganon door's hold (R16) is not timed. The
-- Triforce room (special area 0x189) and the ending's overworld / dungeon
-- scenes need cinematics this engine lacks: the Triforce room is black
-- with three drawn golden triangles (the polyhedral Triforce); a credits
-- overworld scene shows the Light World map at the scene's target scroll
-- (the start scroll comes from the exit tables, LoadOverworldFromDungeon,
-- not ported -- so no pan), the scene's people / animals
-- (Credits_PrepAndLoadSprites, Credits_SpriteDraw_*) are not drawn, and
-- the dungeon (Sanctuary, wishing well, smithy) and special-area (Zora's
-- waterfall, the Master Sword grove) scenes are black under their text;
-- the texts and the staff roll are drawn with the message font (the
-- ending font's tiles are not decoded) and fixed colours, on a black field
-- with the three triangles; the death counts of the quest history
-- (kEnding_Digits) and "THE END"'s OBJ tiles are not drawn (the words are);
-- the mosaic is a fade; the screen's row of a scene text is its map row - 5
-- (the GBA's BG offset there is not traced). The ending never returns to
-- the title (Credits_HangForever, as the cartridge).
--
-- Hooks: M.startTriforce(game) (the ending from anywhere), M.takeCrystal /
-- M.crystalFall (the prize), M.becomeFollower(game, x, y) (follower 6),
-- M.followerSpot(game). No shared file is edited: Palace.update / draw /
-- takePrize, Interior.loadRoom and Game update / draw / drawRoom /
-- drawLink / escapeRoomFrame / startRoomScroll are wrapped in M.install.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "ending27" }

M.OFF = {
  maidenMsgs = 0x17A9EC,   -- kCrystalMaiden_Msgs (9 u16, GBA numbers)
  maidenPal = 0x18096C,    -- kCrystalMaiden_Pal (8 u16)
  crystalTab0 = 0x14CDA0,  -- kCrystal_Tab0 (7 u16)
  maidenDmd = 0x1795B0,    -- kCrystalMaiden_SpriteData (16)
  maidenDma = 0x179630,    -- kCrystalMaiden_Dma (16)
  fallZ = 0x16E5DB,        -- kFallingItem_Z (7)
  fallG = 0x16E5FE,        -- kFallingItem_G (7)
  endTab1 = 0x17064C,      -- kEnding_Tab1 (16 u16)
  endTargetY = 0x170820,   -- kEnding1_TargetScrollY (16, GBA values)
  endTargetX = 0x17086C,   -- kEnding1_TargetScrollX (16)
  endYvel = 0x1708B8,      -- kEnding1_Yvel (16 s16)
  endXvel = 0x170904,      -- kEnding1_Xvel (16 s16)
  endDur = 0x170950,       -- kEnding1_3_Tab0 (16, GBA values)
  endFuncs = 0x1709AC,     -- kEndSequence_Funcs (39 code pointers)
  theEnd = 0x17099C,       -- Credits_HangForever's OAM (4 x { yx, flags char })
  sceneText = 0x1965D4,    -- the ending's scene texts, English (16 pointers)
  creditLines = 0x197320,  -- the staff roll's lines, English (pointers)
  creditCount = 0x1979A4,  -- the roll's line count (u32)
}
M.DOOR_TAB = { 0x2556, 0x2596, 0x25D6, 0x2616 }   -- kOpenGanonDoor_Tab (SrcPtr byte offsets)

M.MAIDEN, M.BLIND_MAIDEN = 0xAB, 0xB7
M.TYPES = { [0xAB] = true, [0xB7] = true }
M.FIGHTS = {}
M.FOLLOWER = 6
M.CRYSTAL = 0x20
M.CRYSTAL_BYTE = 0x5A
M.MSG_BLIND_MAIDEN = 0x122
M.MSG_UNDERSTAND, M.MSG_WAY = 0x13A, 0x139
M.MSG_TRIFORCE = 0x173
M.RISE_TOP = 0x49
M.CELL_ROOM, M.BLIND_ROOM, M.GANON_ROOM = 0x45, 0xAC, 0x00

local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
local function bmg(n) return require("src.zelda.alttp.Text").bmgIndex(n) end

-- ------------------------------------------------------------ the ending font
-- the ending's tile numbers -> letters (lower case: low byte; capitals: two
-- rows, bit 0x10 = the lower half)
local SMALL = { [0x96] = ".", [0x97] = "j", [0xA5] = ",", [0xB0] = "x", [0xB1] = "y", [0xB2] = "z",
                [0xB3] = "-", [0xB4] = ".", [0xB5] = "'" }
for i = 0, 8 do SMALL[0x87 + i] = string.char(97 + i) end          -- a..i
for i = 0, 12 do SMALL[0x98 + i] = string.char(107 + i) end        -- k..w
local BIG = { [0x81] = "!", [0x82] = "I", [0x83] = "'", [0x85] = "-" }
for i = 1, 15 do BIG[i] = string.char(64 + i) end                   -- A..O
for i = 0, 10 do BIG[0x20 + i] = string.char(80 + i) end            -- P..Z
for i = 0, 9 do BIG[0xA6 + i] = tostring(i) end                     -- digits
M.SMALL, M.BIG = SMALL, BIG

-- a run of map words -> { big = the capitals' upper row (or nil), small =
-- the lower-case run (or nil), bottom = only capitals' lower rows, pal }
local function decodeWords(ws)
  local bigT, smallT = {}, {}
  local nBig, nSmall, nBottom, pal = 0, 0, 0, nil
  for _, w in ipairs(ws) do
    local b, sm = " ", " "
    if w ~= 0 then
      local lo, hi = band(w, 0xFF), rshift(w, 8)
      if hi == 0xC0 then
        if band(lo, 0x10) ~= 0 and BIG[band(lo, 0xEF)] then nBottom = nBottom + 1
        else b = BIG[lo] or " "; nBig = nBig + 1 end
      else
        pal = pal or rshift(hi, 4)
        sm = SMALL[lo] or " "
        nSmall = nSmall + 1
      end
    end
    bigT[#bigT + 1], smallT[#smallT + 1] = b, sm
  end
  local l = { pal = pal or 0xC, letters = nBig + nSmall }
  if nBig > 0 then l.big = table.concat(bigT) end
  if nSmall > 0 then l.small = table.concat(smallT) end
  l.bottom = nBottom > 0 and l.letters == 0
  l.kind = nBig > 0 and "big" or (nSmall > 0 and "small" or (l.bottom and "big" or "none"))
  l.text = l.big or l.small or ""
  return l
end
M.decodeWords = decodeWords

local function words(rom, o, n)
  local t = {}
  for i = 0, n - 1 do t[i + 1] = rom:u16(o + i * 2) end
  return t
end

-- ------------------------------------------------------------ import
function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local t = {
    maidenMsgs = rom:bytesU16(O.maidenMsgs, 9), maidenPal = rom:bytesU16(O.maidenPal, 8),
    crystalTab0 = rom:bytesU16(O.crystalTab0, 7), maidenDma = u8(O.maidenDma, 16),
    fallZ = u8(O.fallZ, 7), fallG = u8(O.fallG, 7),
    endTab1 = rom:bytesU16(O.endTab1, 16),
    endTargetY = rom:bytesU16(O.endTargetY, 16), endTargetX = rom:bytesU16(O.endTargetX, 16),
    endYvel = s16(rom:bytesU16(O.endYvel, 16)), endXvel = s16(rom:bytesU16(O.endXvel, 16)),
    endDur = rom:bytesU16(O.endDur, 16),
    theEnd = {}, scenes = {}, sceneKind = {}, credits = {}, door = {},
  }
  t.maidenDmd = D.dmd(rom, O.maidenDmd, 16)
  check(t.maidenMsgs[2] == t.maidenMsgs[6] and t.maidenMsgs[1] == t.maidenMsgs[2] + 1 and t.maidenMsgs[9] > t.maidenMsgs[8]
        and t.maidenDmd[1][5] == 2 and t.maidenDma[1] ~= t.maidenDma[2], "crystal maiden tables (messages, picture)")
  check(t.maidenPal[1] == 0 and t.maidenPal[8] > t.maidenPal[2] and t.crystalTab0[5] < t.crystalTab0[1]
        and t.fallZ[7] == 0x80 and t.fallZ[1] == 0x60 and t.fallG[6] == 0xFF, "crystal cutscene / falling prize tables")
  -- the scene kinds: kEndSequence_Funcs pairs (load, scroll); entry 0 is
  -- the overworld loader, entry 2 the dungeon one
  local f0, f2 = rom:u32(O.endFuncs), rom:u32(O.endFuncs + 8)
  for k = 0, 15 do
    local f = rom:u32(O.endFuncs + k * 8)
    t.sceneKind[k] = (f == f0) and "ow" or ((f == f2) and "dungeon" or "?")
  end
  for i = 0, 3 do
    local yx, cf = rom:u16(O.theEnd + i * 4), rom:u16(O.theEnd + i * 4 + 2)
    t.theEnd[i + 1] = { x = band(yx, 0xFF), y = rshift(yx, 8), char = band(cf, 0xFF), flags = rshift(cf, 8) }
  end
  check(t.endYvel[1] == -1 and t.endXvel[3] == -1 and t.endXvel[7] == 1 and t.endTargetX[16] == 0
        and t.sceneKind[1] == "dungeon" and t.sceneKind[0] == "ow" and t.sceneKind[10] == "dungeon"
        and t.theEnd[2].x == t.theEnd[1].x + 16, "ending scene tables (kEnding1_*, kEndSequence_Funcs)")
  local okDur = true
  for k = 1, 16 do if t.endDur[k] < 0x200 or t.endDur[k] > 0x600 then okDur = false end end
  check(okDur, "kEnding1_3_Tab0 (the GBA's scene lengths)")
  -- the scene texts: [map pos][byte count - 1][words] .. 0xFFFF
  for k = 0, 15 do
    local p = rom:ptr(O.sceneText + k * 4)
    local list = {}
    for _ = 1, 16 do
      if not p or rom:u16(p) == 0xFFFF then break end
      local pos, n = rom:u16(p), rom:u16(p + 2)
      local m = rshift(n + 1, 1)
      local l = decodeWords(words(rom, p + 4, m))
      l.row, l.col = band(rshift(pos, 5), 31), band(pos, 31)
      list[#list + 1] = l
      p = p + 4 + m * 2
    end
    t.scenes[k] = list
  end
  check(#t.scenes[0] == 3 and t.scenes[0][2].kind == "big" and t.scenes[0][3].bottom and #t.scenes[15] >= 3,
        "the ending's scene texts (GBA 0x1965D4)")
  -- the staff roll: [col][byte count - 1][words], 0xFFFF = empty
  t.creditCount = rom:u32(O.creditCount)
  local nl = 0
  for i = 0, 511 do
    local p = rom:ptr(O.creditLines + i * 4)
    if not p then break end
    nl = i + 1
    if rom:u16(p) ~= 0xFFFF then
      local col, n = rom:u16(p), rom:u16(p + 2)
      local m = rshift(n + 1, 1)
      local l = decodeWords(words(rom, p + 4, m))
      l.col = col
      t.credits[i] = l
    end
  end
  t.creditLines = nl
  check(t.creditCount > 300 and t.creditCount < nl and nl < 512 and t.credits[0] and t.credits[0].kind == "big"
        and t.credits[1] and t.credits[1].bottom and not t.credits[2], "the staff roll (GBA 0x197320)")
  -- the Ganon door's pictures (kPredefinedTileData, Dungeons26's OFF.pred)
  for k = 1, 4 do t.door[k] = rom:bytesU16(D.OFF.pred + M.DOOR_TAB[k], 32) end
  check(t.door[1][1] ~= 0 and t.door[4][1] ~= t.door[1][1], "kOpenGanonDoor_Tab's pictures")
  return t
end

local function T(game)
  local d = game.data.t and game.data.t.d26
  return d and d[M.NAME]
end
M.tabs = T
local function P() return require("src.zelda.alttp.Palace") end
local function DPm() return require("src.zelda.alttp.DesertPalace") end
local function OMm() return require("src.zelda.alttp.OldMan") end

-- ------------------------------------------------------------ drawing helpers
local function rgba(c)
  return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31
end
-- follower 6's 16 x 16 tiles at DMA offset var (the follower sheet:
-- 0x65 + v >> 11 for followers 2-8, GBA 0x0812F9A8, as OldMan.lua)
local function followerImage(spr, var, palRow)
  local key = "e27:" .. var .. ":" .. palRow
  local im = spr.cache[key]
  if im ~= nil then return im or nil end
  local v = spr.info.follower[M.FOLLOWER + 1] or 0
  local base = (0x65 + rshift(v, 11)) * 4096 + band(v, 0x7FF) + var * 2
  local img = love.image.newImageData(16, 16)
  local src, pal = spr.data.spr, spr.pal[palRow] or {}
  for ty = 0, 1 do
    for tx = 0, 1 do
      local off = base + ty * 0x200 + tx * 32
      for y = 0, 7 do
        for xb = 0, 3 do
          local b = src:byte(off + y * 4 + xb + 1) or 0
          local lo, hi = b % 16, math.floor(b / 16)
          if lo ~= 0 and pal[lo] then local r, g, bb = rgba(pal[lo]) img:setPixel(tx * 8 + xb * 2, ty * 8 + y, r, g, bb, 1) end
          if hi ~= 0 and pal[hi] then local r, g, bb = rgba(pal[hi]) img:setPixel(tx * 8 + xb * 2 + 1, ty * 8 + y, r, g, bb, 1) end
        end
      end
    end
  end
  im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  spr.cache[key] = im
  return im
end

-- CrystalMaiden_Draw: kCrystalMaiden_SpriteData by D * 2 + gfx, the head
-- (dma_var6) above the body (dma_var7); zelda = follower 1's tiles
function M.drawMaiden(spr, zelda, D, gfx, x, y, flags, alpha)
  local info = spr.info
  if not (info and info.maiden and love and love.graphics) then return end
  local j = band(D or 1, 3) * 2 + (gfx or 0)
  if alpha then love.graphics.setColor(1, 1, 1, alpha) end
  for part = 1, 0, -1 do
    local e = info.maiden[j * 2 + part + 1]
    local var = info.maidenDma[j * 2 + part + 1] or 0
    if e then
      local fl = bxor(e[4], flags or 0x0B)
      local row = band(rshift(fl, 1), 7)
      local im = zelda and spr:followerImage(var, row) or followerImage(spr, var, row)
      if im then
        local hf = band(fl, 0x40) ~= 0
        love.graphics.draw(im, x + e[1] + (hf and 16 or 0), y + e[2], 0, hf and -1 or 1, 1)
      end
    end
  end
  if alpha then love.graphics.setColor(1, 1, 1, 1) end
end

-- OURS: the crystal (a diamond)
local function drawCrystal(x, y, alpha)
  if not (love and love.graphics) then return end
  local lg = love.graphics
  lg.setColor(0.55, 0.85, 1.0, alpha or 1)
  lg.polygon("fill", x + 4, y, x + 8, y + 6, x + 4, y + 14, x, y + 6)
  lg.setColor(1, 1, 1, alpha or 1)
  lg.polygon("line", x + 4, y, x + 8, y + 6, x + 4, y + 14, x, y + 6)
  lg.setColor(1, 1, 1, 1)
end
M.drawCrystal = drawCrystal

-- ------------------------------------------------------------ 1. the crystal
function M.isCrystalPalace(game)
  local pid = P().palaceId(game)
  local pbit, item = DPm().prizeOf(game, pid)
  return item == M.CRYSTAL, pbit, pid
end

-- Ancilla29_MilestoneItemReceipt for the crystal (the prize actor 0xEB)
function M.crystalFall(self, a, lk)
  local game = self.game
  local tb = T(game)
  if not a.c27 then
    a.c27, a.crystal = true, true
    a.wait, a.step, a.zs = 128, 0, 0                 -- byte_7E04C2
    a.z, a.vz = tb and tb.fallZ[7] or 0x80, -48
    self.game.crystalFalls = (self.game.crystalFalls or 0) + 1
  end
  if (a.wait or 0) > 0 then a.wait = a.wait - 1 return end
  if a.z < 24 and P()._h.touchLink(self, a, lk) and not game.textBox then
    a.dead = true
    return M.takeCrystal(game, a)
  end
  if a.step ~= 2 then
    if a.step ~= 0 then a.vz = a.vz - 1 end
    local zz = a.z * 16 + a.zs + a.vz
    a.z, a.zs = math.floor(zz / 16), zz % 16
    if a.z < 0 then a.step, a.vz, a.z, a.zs = a.step + 1, 0x18, 0, 0 end
  end
end

-- Link_ReceiveItem(0x20): held up, then the rising crystal
function M.takeCrystal(game, a)
  local p = game.progress
  local _, pbit, pid = M.isCrystalPalace(game)
  p.prizes = p.prizes or {}
  p.prizes[pid] = true
  local lk = game.link
  game.crystal27 = { phase = "held", x = lk.x + 4, y = lk.y - 14, vy = 0, sub = 0, t = 0, pid = pid, bit = pbit or 0 }
  game.crystalsTaken = (game.crystalsTaken or 0) + 1
  game.holdItem = { item = M.CRYSTAL, t = 0 }
  local msg = game.receiptMessage and game:receiptMessage(M.CRYSTAL)
  if msg and game:showMessage(msg) then
    local prev = game.onTextDone
    game.onTextDone = function(g)
      if prev then prev(g) end
      if g.crystal27 then g.crystal27.phase = "rise" end
    end
  else
    game.crystal27.phase = "rise"
  end
end

local function setCrystalBit(game, c)
  local p = game.progress
  p.crystals = bor(p.crystals or 0, c.bit)
  p.inv = p.inv or {}
  p.inv[M.CRYSTAL_BYTE] = p.crystals
end
function M.crystalCount(game)
  local n, v = 0, game.progress.crystals or 0
  for i = 0, 6 do if band(v, bit.lshift(1, i)) ~= 0 then n = n + 1 end end
  return n
end

-- CrystalCutscene_SpawnMaiden
local function spawnMaiden(game, c)
  local acts = game.actors
  for _, a in ipairs(acts.list) do a.dead = true end
  local lk = game.link
  local qx, qy = math.floor(lk.x / 256) * 256, math.floor(lk.y / 256) * 256
  local a = P()._h.spawn(acts, M.MAIDEN, qx + 0x78, qy + 0x7C, false)
  a.D, a.ai, a.E, a.poly, a.fade = 1, 0, 0, 156, 0
  a.zelda = (c.pid == 24)
  a.oamFl = a.zelda and 9 or 0x0B
  a.noTouch, a.untouchable = true, true
  c.maiden = a
  game.maidensSpawned = (game.maidensSpawned or 0) + 1
  return a
end

-- one frame of the crystal's give-out (Link held); true = frame used
function M.crystalFrame(game)
  local c = game.crystal27
  if not c then return false end
  c.t = c.t + 1
  local lk = game.link
  lk.moving, lk.steps = false, 0
  if c.phase == "held" then return true end
  local inside = game.interior
  if c.phase == "rise" then
    game.holdItem = nil
    -- Ancilla_RisingCrystal
    c.vy = math.max(c.vy - 1, -16)
    local yy = c.y * 16 + c.sub + c.vy
    c.y, c.sub = math.floor(yy / 16), yy % 16
    local _, cy = 0, 0
    if inside and inside.camera then _, cy = inside:camera(lk.x, lk.y, 240, 160) end
    if c.y - cy < M.RISE_TOP then
      c.y = cy + M.RISE_TOP
      setCrystalBit(game, c)
      c.phase, c.t = "dark", 0
    end
    return true
  end
  if c.phase == "dark" then
    -- Module07_18_RescuedMaiden (OURS: one 32-frame darkening)
    if c.t >= 32 then
      spawnMaiden(game, c)
      c.phase, c.t = "maiden", 0
    end
    return true
  end
  if c.phase == "maiden" then
    game.actors:update()
    return true
  end
  return true
end

-- Sprite_AB_CrystalMaiden / CrystalMaiden_RunCutscene
local function crystalMaiden(self, a, lk)
  local game = self.game
  local tb = T(game)
  local c = game.crystal27
  a.E = (a.E or 0) + 1
  local s = a.ai
  if s == 0 or s == 1 then
    a.ai = s + 1
  elseif s == 2 then
    if a.poly < 6 then a.poly, a.ai = 0, 3
    else
      a.poly = a.poly - 3
      if a.poly >= 64 then game.maidenSparkles = (game.maidenSparkles or 0) + 1 end
    end
  elseif s == 3 or s == 4 then
    a.ai = 4
    if band(a.E, 1) == 0 then
      a.fade = a.fade + 1
      if a.fade >= 31 then
        a.ai = 5
        lk.facing, lk.steps, lk.moving = 0, 0, false
      end
    end
  elseif s == 5 then
    local p = game.progress
    local pid = (c and c.pid) or P().palaceId(game)
    local j = pid - 10
    if j == 2 and (p.mapIcons or 0) < 7 then p.mapIcons = 7 end
    if j == 14 and band(p.crystals or 0, 0x7F) ~= 0x7F then j = 16 end
    j = math.max(0, math.min(16, j))
    local v = tb and tb.maidenMsgs[rshift(j, 1) + 1]
    if v then game:showMessage(bmg(v)) end
    game.maidenMsg = v and bmg(v)
    a.ai = 6
    if band(p.crystals or 0, 0x7F) == 0x7F then p.mapIcons = 8 end
  elseif s == 6 then
    game:showMessage(M.MSG_UNDERSTAND)
    a.ai = 7
  elseif s == 7 then
    if (game.lastChoice or 0) ~= 0 then a.ai = 5
    else
      game:showMessage(M.MSG_WAY)
      a.ai = 8
    end
  elseif s == 8 then
    a.dead = true
    game.crystal27 = nil
    game.maidenDone = (game.maidenDone or 0) + 1
    if game.interior and game.leaveRoom then game:leaveRoom() end
  end
end

-- ------------------------------------------------------------ 2. the blind maiden
local function blindBeaten(game)
  local p = game.progress
  return p.bossBeaten ~= nil and p.bossBeaten[M.BLIND_ROOM] == true
end

function M.prep(self, a)
  a.game = self.game
  a.noTouch, a.untouchable = true, true
  if a.type == M.BLIND_MAIDEN then
    -- SpritePrep_BlindMaiden
    if blindBeaten(self.game) or (self.game.progress.follower or 0) == M.FOLLOWER then a.dead = true return end
    a.D, a.head, a.ai = 2, 2, 0
  end
end

-- Follower_MoveTowardsLink / Sprite_BecomeFollower
local function initTrail(game, x, y, facing)
  local tr = {}
  for i = 0, 19 do tr[i] = { x, y, facing or 2, 0 } end
  game.maidenTrail = { t = tr, v1 = 0, v2 = 0, key = game.omKey and game:omKey(), walkT = 0, flags = 0 }
  return game.maidenTrail
end
function M.becomeFollower(game, x, y)
  local p = game.progress
  p.follower = M.FOLLOWER
  local lk = game.link
  local tr = initTrail(game, x + 1, y - 6, 2)
  local fx, fy = x + 1, y - 6
  local A = require("src.zelda.alttp.Actors")
  for _ = 1, 18 do
    local vx, vy = A.project(fx, fy, lk.x, lk.y, 24)
    fx, fy = fx + vx / 16, fy + vy / 16
    if math.abs(fx - lk.x) < 2 and math.abs(fy - lk.y) < 2 then break end
    tr.v1 = tr.v1 + 1
    if tr.v1 == 18 then break end
    tr.t[tr.v1] = { math.floor(fx), math.floor(fy), 2, 0 }
  end
  game.maidenFollowed = (game.maidenFollowed or 0) + 1
end

local function blindMaiden(self, a, lk)
  local game = self.game
  if game.textBox then return end
  -- Sprite_DirectionToFaceLink ^ 3 (as OldMan.lua)
  local dx, dy = lk.x - a.x, lk.y + 8 - a.y
  local d
  if math.abs(dx) >= math.abs(dy) then d = dx < 0 and 1 or 0 else d = dy < 0 and 3 or 2 end
  a.head = bxor(d, 3)
  a.D = a.head                                  -- Sprite_TrackBodyToHead (OURS: at once)
  if a.ai == 0 then
    local A = require("src.zelda.alttp.Actors")
    local cb = game.data.roomIdx.combat
    local hx, hy, hw, hh = A.hitbox(cb, a)
    local lx, ly, lw, lh = A.linkBox(lk)
    if A.overlapCart(lx, ly, lw, lh, hx, hy, hw, hh) then
      game:showMessage(M.MSG_BLIND_MAIDEN)
      a.ai = 1
    end
  else
    a.dead = true
    M.becomeFollower(game, a.x, a.y)
  end
end

function M.update(self, a, lk)
  if a.type == M.BLIND_MAIDEN then return blindMaiden(self, a, lk) end
  if a.type == M.MAIDEN then return crystalMaiden(self, a, lk) end
end

function M.draw(spr, a, x, y, frame, game)
  if a.type == M.MAIDEN then
    if (a.ai or 0) < 3 then return true end
    M.drawMaiden(spr, a.zelda, a.D or 1, 0, x, y, a.oamFl, math.min(1, (a.fade or 0) / 31))
    return true
  end
  if a.type == M.BLIND_MAIDEN then
    local f = band(spr.info.flags3 and spr.info.flags3[M.BLIND_MAIDEN + 1] or 0x0B, 0x0F)
    M.drawMaiden(spr, false, a.D or 2, 0, x, y, f)
    return true
  end
  return false
end

function M.swordImmune() return true end

-- Follower_HandleTrigger for follower 6 (the GBA's kTagalong_IndoorInfos)
local function followerTrigger(game)
  local tb = OMm().tabs(game)
  if not (tb and game.state == "room" and game.interior) then return end
  local ix
  for j, r in ipairs(tb.inRooms) do if r == game.interior.room then ix = j - 1 break end end
  if not ix then return end
  local lk = game.link
  local r = game.interior.room
  local lx, ly = (r % 16) * 512 + lk.x, math.floor(r / 16) * 512 + lk.y
  local tr = game.maidenTrail
  for i = tb.inOffs[ix + 1] + 1, tb.inOffs[ix + 2] do
    local e = tb.inInfos[i]
    if e and e.follower == M.FOLLOWER then
      local dx, dy = math.abs(lx + 12 - (e.x + 8)), math.abs(ly + 12 - (e.y + 8))
      if dx < 24 and dy < 28 and band(e.bit, tr.flags or 0) == 0 then
        tr.flags = bor(tr.flags or 0, e.bit)
        game:showMessage(bmg(e.msg))
        game.maidenTalks = (game.maidenTalks or 0) + 1
        return
      end
    end
  end
end

-- Follower_BasicMover (follower 6), one frame
function M.followerFrame(game)
  local p = game.progress
  if (p.follower or 0) ~= M.FOLLOWER then return end
  local lk = game.link
  local key = game.omKey and game:omKey()
  local tr = game.maidenTrail
  if not tr or tr.key ~= key then tr = initTrail(game, lk.x, lk.y, lk.facing) end
  local moved = tr.lx ~= nil and (tr.lx ~= lk.x or tr.ly ~= lk.y)
  tr.lx, tr.ly = lk.x, lk.y
  if moved then
    tr.v1 = (tr.v1 + 1) % 20
    tr.t[tr.v1] = { lk.x, lk.y - (lk.z or 0), lk.facing, lk.z or 0 }
  end
  if not game.textBox then followerTrigger(game) end
  -- Follower_CheckBlindTrigger -> Blind_SpawnFromMaiden
  if game.state == "room" and game.interior and game.interior.room == M.BLIND_ROOM then
    local mem = game.roomMemory and game.roomMemory[0x65]
    local light = mem and mem.light
    local q = tr.t[tr.v2]
    local TT = require("src.zelda.alttp.ThievesTown")
    local acts = game.actors
    if light and acts and acts.inside and TT.maidenTrigger(acts, q[1], q[2], q[4] or 0, true) then
      p.follower = 0
      game.maidenTrail = nil
      if game.closeShutters then game:closeShutters() end
      game.blindFromMaiden = (game.blindFromMaiden or 0) + 1
      return
    end
  end
  if moved then
    local t = (tr.v1 - 15) % 20
    if t == tr.v2 then tr.v2 = (tr.v2 + 1) % 20; tr.walkT = tr.walkT + 1 end
  end
end

-- the follower's spot (tests, the trigger)
function M.followerSpot(game)
  local tr = game.maidenTrail
  if not tr then return nil end
  local q = tr.t[tr.v2]
  return q[1], q[2], q[3]
end

-- ------------------------------------------------------------ 3a. the Ganon door
local function setAttr(inside, cell, v)
  inside.attrs[cell] = v; inside.grid[cell] = (v ~= 0)
  if inside.attrsLo and inside.attrsLo ~= inside.attrs then inside.attrsLo[cell] = v; inside.gridLo[cell] = (v ~= 0) end
end
local function doorPicture(game, k)
  local tb = T(game)
  local inside = game.interior
  if not (tb and inside) then return end
  local src = tb.door[k]
  for i = 0, 7 do
    for r = 0, 3 do inside.patch[(3 + r) * 64 + 44 + i] = src[i * 4 + r + 1] end
  end
  game.roomImages = nil
end
local function doorAttrs(inside)
  for _, r in ipairs({ 5, 6 }) do setAttr(inside, r * 64 + 44, 2); setAttr(inside, r * 64 + 51, 2) end
  for r = 0, 6 do for c = 45, 50 do setAttr(inside, r * 64 + c, 0) end end
end
-- RoomTag_GanonDoor + Module07_1A (in room 0, Ganon beaten)
function M.ganonDoorFrame(game)
  local inside = game.interior
  if not (inside and inside.room == M.GANON_ROOM and game.progress.ganonBeaten) or inside.mem.ganonDoor then return false end
  local d = game.ganonDoor27
  if not d then
    for _, a in ipairs(game.actors.list) do if not a.dead then return false end end
    if game.pitFall then return false end
    d = { sub = 0 }
    game.ganonDoor27 = d
  end
  d.sub = d.sub + 1
  if band(d.sub, 3) == 0 then
    doorPicture(game, rshift(d.sub - 4, 2) + 1)
    if d.sub == 16 then
      doorAttrs(inside)
      inside.mem.ganonDoor = true
      game.ganonDoor27 = nil
      game.ganonDoorOpened = (game.ganonDoorOpened or 0) + 1
    end
  end
  return false
end

-- ------------------------------------------------------------ 3b. the ending
local function newPhase(e, ph) e.phase, e.t = ph, 0 end

-- Module19_TriforceRoom from room 0's top
function M.startTriforce(game)
  local lk = game.link
  game.ending27 = { phase = "fadeout", t = 0, bright = 1 }
  game.endingPending = nil
  game.roomScroll = nil
  lk.moving, lk.steps, lk.facing = false, 0, 0
  game.triforceRooms = (game.triforceRooms or 0) + 1
end

local function walk(lk, up)
  lk:update({ up = up }, function() return 0 end)
end

local SCENES = 16
function M.endingUpdate(game)
  game.frame = (game.frame or 0) + 1
  if game.textBox then return game:updateText() end
  local e = game.ending27
  local lk = game.link
  local tb = T(game)
  e.t = e.t + 1
  local ph = e.phase
  if ph == "fadeout" then
    e.bright = math.max(0, 1 - e.t / 32)
    if e.t >= 32 then
      game.state = "ending"
      game.interior, game.roomImages = nil, nil
      lk.x, lk.y, lk.facing, lk.z = 120, 236, 0, 0
      game.cam = { x = 0, y = 96 }
      newPhase(e, "walkin")
    end
  elseif ph == "walkin" then
    e.bright = math.min(1, e.t / 31)
    walk(lk, true)
    if lk.y < 192 then lk.moving, lk.steps = false, 0; newPhase(e, "mosaic") end
  elseif ph == "mosaic" then
    e.bright = 1
    if e.t >= 31 then newPhase(e, "text") end
  elseif ph == "text" then
    game:showMessage(M.MSG_TRIFORCE)
    game.triforceText = (game.triforceText or 0) + 1
    newPhase(e, "approach")
  elseif ph == "approach" then
    -- TriforceRoom_LinkApproachTriforce
    if lk.y < 152 then
      lk.moving, lk.steps = false, 0
      e.hold = (e.hold or 64) - 1
      if e.hold <= 0 then e.pose = 2; newPhase(e, "hold") end
    else
      if lk.y < 169 then lk.speedSetting = 0x14 end
      walk(lk, true)
    end
  elseif ph == "hold" then
    if e.t >= 0x80 then newPhase(e, "white") end
  elseif ph == "white" then
    e.white = math.min(1, e.t / 32)
    if e.t >= 32 then newPhase(e, "off") end
  elseif ph == "off" then
    e.bright, e.white = 0, math.max(0, 1 - e.t / 15)
    if e.t >= 15 then
      e.white = nil
      lk.speedSetting = 0
      game.progress.ended = true
      e.scene, e.R, e.ini = 0, 0, 0
      newPhase(e, "scene")
      game.endingScenes = 1
    end
  elseif ph == "scene" then
    -- Credits_ScrollScene_* + Credits_HandleSceneFade
    local k = e.scene
    local dur = tb and tb.endDur[k + 1] or 0x300
    if e.R >= dur then
      if band(e.R, 1) == 0 then e.ini = e.ini - 1 end
      if e.ini <= 0 then
        e.ini = 0
        e.scene = e.scene + 1
        e.R = 0
        if e.scene >= SCENES then
          newPhase(e, "brighten")
          e.ini, e.scroll = 0, 0
        else
          game.endingScenes = e.scene + 1
        end
        return
      end
      e.R = e.R + 1
    else
      if band(e.R, 1) == 0 and e.ini ~= 15 then e.ini = e.ini + 1 end
      e.R = e.R + 1
    end
    e.bright = e.ini / 15
  elseif ph == "brighten" then
    -- Credits_BrightenTriangles
    if band(game.frame, 15) == 0 then e.ini = e.ini + 1 end
    e.bright = e.ini / 15
    if e.ini >= 15 then newPhase(e, "roll") end
  elseif ph == "roll" then
    -- Credits_FadeColorAndBeginAnimating: BG3 + 1 every 4th frame
    e.bright = 1
    if band(game.frame, 3) == 0 then
      local stop = (tb and tb.creditCount or 392) * 8
      if e.scroll >= stop then newPhase(e, "stop")
      else e.scroll = e.scroll + 1 end
    end
  elseif ph == "stop" then
    if e.t >= 0x80 then newPhase(e, "disperse") end
  elseif ph == "disperse" then
    e.bright = math.max(0, 1 - e.t / 32)
    if e.t >= 0xC0 then newPhase(e, "theend") end
  elseif ph == "theend" then
    -- Credits_FadeInTheEnd: a filter step every 8th frame
    e.bright = math.min(1, e.t / (31 * 8))
    if e.t >= 31 * 8 then newPhase(e, "hang"); game.theEnd = true end
  end
end

-- the message font as a line of text (cached Images)
local fontCache = {}
local function textImage(data, s, col)
  local key = s .. "|" .. table.concat(col, ",")
  local im = fontCache[key]
  if im then return im end
  local font, widths = data.font, data.ui and data.ui.textWidths
  if not (font and widths) then return nil end
  local W = 8 * #s + 8
  local img = love.image.newImageData(W, 16)
  local x = 0
  for i = 1, #s do
    local c = s:byte(i) + 0x100
    local tile = math.floor(c / 16) * 32 + (c % 16)
    local w = widths[c + 1] or 6
    local ox = x + math.floor((8 - math.min(8, w)) / 2)
    for half = 0, 1 do
      local o = (tile + half * 16) * 32
      for y = 0, 7 do
        for xb = 0, 3 do
          local b = font:byte(o + y * 4 + xb + 1) or 0
          for nib = 0, 1 do
            local v = (nib == 0) and band(b, 15) or rshift(b, 4)
            local px = ox + xb * 2 + nib
            if v ~= 0 and px < W then
              local k = (v == 1 or v == 2) and 0.25 or 1
              img:setPixel(px, half * 8 + y, col[1] * k, col[2] * k, col[3] * k, 1)
            end
          end
        end
      end
    end
    x = x + 8
  end
  im = love.graphics.newImage(img)
  im:setFilter("nearest", "nearest")
  fontCache[key] = im
  return im
end
local PALCOL = { [0x8] = { 0.6, 0.85, 1 }, [0x9] = { 1, 0.85, 0.45 }, [0xB] = { 0.75, 1, 0.65 }, [0xC] = { 1, 1, 1 } }
local function drawLine(data, l, x, y)
  if l.big then
    local im = textImage(data, l.big, PALCOL[0xC])
    if im then love.graphics.draw(im, x, y) end
  end
  if l.small then
    local im = textImage(data, l.small, PALCOL[l.pal] or PALCOL[0xC])
    if im then love.graphics.draw(im, x, y - 4) end
  end
end

local function drawTriforce(cx, cy, s, alpha)
  local lg = love.graphics
  lg.setColor(1, 0.85, 0.2, alpha or 1)
  local h = s * 0.866
  lg.polygon("fill", cx, cy, cx + s / 2, cy + h, cx - s / 2, cy + h)
  lg.polygon("fill", cx - s / 2, cy + h, cx, cy + 2 * h, cx - s, cy + 2 * h)
  lg.polygon("fill", cx + s / 2, cy + h, cx + s, cy + 2 * h, cx, cy + 2 * h)
  lg.setColor(1, 1, 1, 1)
end

function M.endingDraw(game)
  if game.headless or not (love and love.graphics) then return end
  local lg = love.graphics
  local e = game.ending27
  local tb = T(game)
  lg.clear(0, 0, 0, 1)
  local ph = e.phase
  if ph == "fadeout" then
    -- the room fades (the mosaic / ApplyPaletteFilter_bounce)
    local saved = game.ending27
    game.ending27 = nil
    if game.state == "room" and game.interior then game:drawRoom() end
    game.ending27 = saved
  elseif e.scene == nil then
    -- the Triforce room (OURS: black, the drawn Triforce)
    drawTriforce(120, 8, 24, 1)
    game.cam = game.cam or { x = 0, y = 96 }
    game:drawLink(game.link)
  elseif ph == "scene" then
    local k = e.scene
    if tb and tb.sceneKind[k] == "ow" and k ~= 6 and k ~= 15 and game.view then
      local cx, cy = tb.endTargetX[k + 1], tb.endTargetY[k + 1]
      for sy = math.floor(cy / 512), math.floor((cy + 159) / 512) do
        for sx = math.floor(cx / 512), math.floor((cx + 239) / 512) do
          if sx >= 0 and sx < 8 and sy >= 0 and sy < 8 then
            local s = sy * 8 + sx
            local v = game.view:screen(s)
            lg.draw(v.bg2, sx * 512 - cx, sy * 512 - cy)
            lg.draw(v.bg1, sx * 512 - cx, sy * 512 - cy)
          end
        end
      end
    end
    for _, l in ipairs(tb and tb.scenes[k] or {}) do drawLine(game.data, l, l.col * 8, (l.row - 5) * 8) end
  else
    drawTriforce(120, 50, 30, 0.8)
    if ph ~= "theend" and ph ~= "hang" then
      -- line i enters at the bottom when BG3 reaches i * 8; lines from
      -- the count on are not written (R18 < the count)
      local first = math.floor((e.scroll or 0) / 8) - 21
      local nmax = tb and tb.creditCount or 0
      for i = math.max(0, first), math.min(nmax - 1, first + 22) do
        local l = tb and tb.credits[i]
        if l then drawLine(game.data, l, l.col * 8, i * 8 - (e.scroll or 0) + 160) end
      end
    else
      local te = tb and tb.theEnd[1]
      local im = textImage(game.data, "THE END", PALCOL[0xC])
      if im and te then lg.draw(im, te.x, te.y) end
    end
  end
  if (e.bright or 1) < 1 then
    lg.setColor(0, 0, 0, 1 - e.bright)
    lg.rectangle("fill", 0, 0, 240, 160)
  end
  if e.white then
    lg.setColor(1, 1, 1, e.white)
    lg.rectangle("fill", 0, 0, 240, 160)
  end
  lg.setColor(1, 1, 1, 1)
  if game.textBox and game.drawText then game:drawText() end
end

-- ------------------------------------------------------------ install
function M.install(G, D)
  local Pal = P()
  -- the crystal prize (Palace.update / takePrize / draw are table fields)
  local pu = Pal.update
  function Pal.update(self, a, lk)
    if a.type == 0xEB and T(self.game) and M.isCrystalPalace(self.game) then return M.crystalFall(self, a, lk) end
    return pu(self, a, lk)
  end
  local tp = Pal.takePrize
  function Pal.takePrize(game, a)
    if T(game) and M.isCrystalPalace(game) then return M.takeCrystal(game, a) end
    return tp(game, a)
  end
  local pd = Pal.draw
  function Pal.draw(spr, a, x, y, frame)
    if a.type == 0xEB and a.crystal then
      drawCrystal(x + 4, y - (a.z or 0))
      return true
    end
    return pd(spr, a, x, y, frame)
  end
  -- the room: the crystal's give-out holds Link; the Ganon door; the way
  -- up out of room 0
  local erf = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if self.crystal27 then
      if self.actors.room ~= self.interior.room or self.actors.inside ~= self.interior then
        self.actors:enterRoom(self.interior)
      end
      return M.crystalFrame(self)
    end
    if self.interior and self.interior.room == M.GANON_ROOM and self.progress.ganonBeaten and T(self) then
      M.ganonDoorFrame(self)
      if self.link.y < 4 and not self.ending27 then M.startTriforce(self) return true end
    end
    return erf(self, inp)
  end
  local srs = G.startRoomScroll
  function G:startRoomScroll(dir, leaves, stairRoom)
    if dir == "up" and leaves and self.interior and self.interior.room == M.GANON_ROOM and self.progress.ganonBeaten
       and T(self) then
      return M.startTriforce(self)
    end
    return srs(self, dir, leaves, stairRoom)
  end
  local I = require("src.zelda.alttp.Interior")
  local lr = I.loadRoom
  function I:loadRoom(room, main)
    local r = lr(self, room, main)
    if room == M.GANON_ROOM and self.mem and self.mem.ganonDoor and self.data.t and self.data.t.d26
       and self.data.t.d26[M.NAME] then
      local tb = self.data.t.d26[M.NAME]
      for i = 0, 7 do for rr = 0, 3 do self.patch[(3 + rr) * 64 + 44 + i] = tb.door[4][i * 4 + rr + 1] end end
      doorAttrs(self)
    end
    return r
  end
  -- the ending runs instead of the game; the follower each frame
  local up0 = G.update
  function G:update(dt)
    if self.ending27 then return M.endingUpdate(self) end
    local r = up0(self, dt)
    if (self.state == "play" or self.state == "room") and T(self) and not self.roomScroll and not self.scroll
       and not self.textBox and not self.crystal27 then
      M.followerFrame(self)
    end
    return r
  end
  local dr0 = G.draw
  function G:draw()
    if self.ending27 then return M.endingDraw(self) end
    return dr0(self)
  end
  -- the crystal scene's darkness and the crystal over the room
  local drr = G.drawRoom
  function G:drawRoom()
    local r = drr(self)
    local c = self.crystal27
    if c and not self.headless and love and love.graphics then
      local cam = self.roomCam or { x = 0, y = 0 }
      local lg = love.graphics
      if c.phase == "dark" or c.phase == "maiden" then
        lg.setColor(0, 0, 0.08, c.phase == "dark" and math.min(0.7, c.t / 32 * 0.7) or 0.7)
        lg.rectangle("fill", 0, 0, 240, 160)
        lg.setColor(1, 1, 1, 1)
        if not self.zoomOverlay then self:drawHud() end
      end
      if c.phase == "held" or c.phase == "rise" then drawCrystal(c.x - cam.x, c.y - cam.y) end
      local a = c.maiden
      if c.phase == "maiden" and a and not a.dead then
        local sx, sy = a.x - cam.x, a.y - cam.y
        -- OURS: the polyhedral crystal as an outline round her
        lg.setColor(0.6, 0.9, 1, 0.5)
        lg.polygon("line", sx + 8, sy - 22, sx + 26, sy - 2, sx + 8, sy + 26, sx - 10, sy - 2)
        lg.setColor(1, 1, 1, 1)
        local spr = self:shadowSprites()
        if spr and a.ai >= 3 then M.drawMaiden(spr, a.zelda, a.D or 1, 0, sx, sy, a.oamFl, math.min(1, a.fade / 31)) end
        local saved = self.cam
        self.cam = cam
        self:drawLink(self.link)
        self.cam = saved
      end
    end
    return r
  end
  -- the follower drawn under Link
  local dl0 = G.drawLink
  function G:drawLink(lk, tint)
    if lk == self.link and not tint and (self.progress.follower or 0) == M.FOLLOWER and self.maidenTrail and T(self) then
      local spr = self:shadowSprites()
      if spr then
        local tr = self.maidenTrail
        local q = tr.t[tr.v2]
        local SD = { [0] = 3, 2, 1, 0 }              -- facing >> 1 (up, down, left, right) -> sprite D
        local moving = tr.v1 ~= tr.v2
        M.drawMaiden(spr, false, SD[math.floor((q[3] or 2) / 2)] or 2,
                     moving and band(rshift(tr.walkT or 0, 2), 1) or 0, q[1] - self.cam.x, q[2] - self.cam.y,
                     band(spr.info.flags3 and spr.info.flags3[M.BLIND_MAIDEN + 1] or 0x0B, 0x0F))
      end
    end
    return dl0(self, lk, tint)
  end
end

return M
