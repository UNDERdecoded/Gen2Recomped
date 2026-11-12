-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- DUNGEON TRAPS (round 27, team B, group c): the traps and trap-like
-- sprites of the later palaces and the overlords that drop things on Link
-- -- the SNES routines the GBA keeps (zelda3 names), run by Palace.lua
-- through Dungeons26.lua's registry. GBA file offsets in M.OFF (found by
-- value with r27b/py/tabfind.py / dmd26.py, code read with tdis.py):
--
--   0xC5 Sprite_C5_Medusa (indoors): sprite_subtype2 counts; every 128th
--        frame, on Link's level, Sprite_SpawnFireball (0x55 at x + 4,
--        y + 4 - z, 0x20 towards Link, delay 20 / aux1 16 -- the 0x55 runs
--        in DesertPalace.lua) with bump damage 4. Not drawn (the wall's
--        face is BG).
--   0xC6 Sprite_C6_4WayShooter: at delay 0, while the B button runs
--        (button_b_frames: a swing / a held sword) on Link's level, delay
--        32; at 24 a fireball by the fireball's Sprite_DirectionToFaceLink:
--        kFireballJunction_X / Y (GBA 0x17CB94 / 0x17CB9C) and the GBA's
--        split kFireballJunction_XYvel (y 0x17CBA4, x 0x17CBA8; 40).
--   0x95-0x98 Sprite_95_LaserEyeLeft (SpritePrep_LaserEye_bounce: D =
--        type - 0x95, the x / y nudge and head_dir by position): ai 0
--        watches (head_dir 0: only while Link faces it, kLaserEye_Dirs
--        0x17BB90; Link within 16 px of its line), ai 1 opens 32 frames,
--        then LaserEye_FireBeam: a 0x95 with sprite_A (the beam) at
--        kLaserEye_SpawnX / Y (GBA split 0x17BB94 / 0x17BB98), speed
--        kLaserEye_SpawnXYVel (split x 0x17BBA4 / y 0x17BBA8; 112),
--        flags2 0x20, delay 5; delay_aux4 12 keeps the eye shut.
--        Sprite_LaserBeam: SingleSmall (graphics (D & 2) >> 1), MoveXY,
--        Sprite_CheckDamageToLink_same_layer, a wall (after delay) ends it.
--        LaserEye_Draw: kLaserEye_Dmd (GBA 0x17BBAC, chars 0x98 / 0xB8 /
--        0x99 / 0xB9).
--   0x38 Sprite_38_EyeStatue: an arrow (ancilla 9 -> sprite_unk2) with
--        Link below it (Sprite_DirectionToFaceLink 2) sets
--        dung_flag_statechange_waterpuzzle once (sprite_B).
--   0x7D Sprite_7D_BigSpike (SpritePrep_BigSpike: + 8 / + 8, home): Link
--        within 16 px of its row / column -> kSpikeTrap_Xvel / Yvel (GBA
--        0x17B764 / 0x17B76C; 32) for kSpikeTrap_Delay (0x17B774) or to a
--        wall, 96 frames, back at kSpikeTrap_Xvel2 / Yvel2 (0x17B768 /
--        0x17B770; 16) to its home. Contact hurts. SpikeTrap_Draw:
--        kSpikeTrap_Dmd (GBA 0x17B778, char 0x94).
--   0x5D-0x60 Sprite_5D_Roller_* (SpritePrep_Roller_*: D 2 / 3 / 0 / 1,
--        ai = the long roller by x / y bit 4, flags4 + 1 -- its hit box):
--        every 112 frames D ^= 1, speed by the GBA's split
--        kSpikeRoller_XYvel (x 0x17BDAC, y 0x17BDB0; 16). Contact hurts.
--        SpikeRoller_Draw: X / Y (u16, GBA 0x17BDB4 / 0x17BDF4), Char
--        (0x17BE34, the GBA's: 0x8E / 0xAE / 0x88 / 0x89), Flags
--        (0x17BE54); 4 or 8 pieces, the first one the end cap.
--   0xCA Sprite_CA_ChainChomp (SpritePrep_Chainchomp_bounce: the stake):
--        ai 0 rests (delay), every 4th rest a lunge (kChainChomp_Xvel /
--        Yvel 0x17BEA8 / 0x17BEB8 << 2, then 64 towards Link), else a
--        hop (z speed 16) in a random direction; out of 48 px of the stake
--        it is pulled back (16) / the lunge stops (ai 3, 48 frames).
--        ChainChomp_HandleLeash / ChainChomp_MoveChain: 6 links within 8 px
--        of each other, drawn to kChainChomp_Muls (GBA 0x17BEC8: the low
--        bytes of u16s, read at 0x08105C78 -- the 6th is 0) of the way. ChainChomp_Draw: kChainChomp_Gfx / OamFlags (0x17BED2 /
--        0x17BEE2) by its angle, the chain char 0x8B (GBA literal at
--        0x0810600C). Contact hurts.
--   0xC7 Sprite_C7_Pokey (SpritePrep_Pokey: 3 segments, spacing 8,
--        kHokbok_InitXvel / Yvel 0x17BE78 / 0x17BE7C): hops (z 16, -2),
--        bounces off walls; a sword hit (sprite_F 15) takes a segment:
--        F 6, z + spacing, a 0xC7 with sprite_C 1 (1 health) flies off at
--        the recoil speed and bursts after 3 wall bounces (sprite_G);
--        the last one leaves the head with 17 health. kHokbok_B
--        (0x17BE88) squashes the spacing while it rests. Hokbok_Draw:
--        chars 0xC0 / 0xC2 (head), - 0x40 when the spacing is below 7
--        (GBA literals at 0x08105558 / 0x08105560 / 0x08105574).
--   0x90 Sprite_90_Wallmaster (from Overlord09_WallmasterSpawner, GBA
--        overlord 0x09: every other frame gen2 counts down to 128, then a
--        0x90 at Link with z 208, gen2 127): descends (z speed -3 to -64),
--        63 frames on the floor (graphics by delay & 0x20), touching Link
--        grabs him (it hurts; sprite_A, flags3 64), rises (+2 to 64) with
--        Link held at (x, y - z + 3); Link off the top of the screen ->
--        WallMaster_SendPlayerToLastEntrance (back to the palace's
--        entrance). WallMaster_Draw: kWallMaster_Dmd (GBA 0x17AAF8).
--   0x1C Sprite_1C_Statue (SpritePrep_Statue: y + 7): Link pushing it
--        (Sprite_CheckDamageToLink_same_layer) for 13 frames (delay_aux1)
--        moves it at kMovableStatue_Xvel / Yvel (GBA 0x1759C0 / 0x1759C4;
--        16) away from him, Link held at his previous spot
--        (Sprite_NullifyHookshotDrag) and slowed (speed setting 8); Link
--        next to it facing it (kMovableStatue_Dir 0x1759C8), A held and
--        the d-pad away from it (kMovableStatue_Joypad 0x1759CC) pulls it
--        (Link_APress_StatueDrag: speed setting 20, his facing kept). Four
--        points (kMovableStatue_SwitchX / Y 0x1759D0 / 0x1759D4) on the
--        switch attributes 0x23 / 0x24 / 0x25 / 0x3B (the GBA's list
--        0x1759D8): dung_flag_statechange_waterpuzzle.
--        Statue_BlockSprites pushes sprites out (sprite_F 4, 32).
--        MovableStatue_Draw: kMovableStatue_Dmd (GBA 0x1759DC).
--   0x04 / 0x06 Sprite_PullSwitch (PullSwitch_FacingDown /
--        PullSwitch_HandleDownPulling): Link touching it from below with A
--        and down held pulls it: graphics 1..13 at kGoodPullSwitch_Tab1
--        (GBA 0x17CEBF) frames each, Link held at kGoodPullSwitch_YOffs
--        (0x17CED7) below it; at 13 the good one (0x04) sets
--        dung_flag_statechange_waterpuzzle, the bad one (0x06)
--        activate_bomb_trap_overlord. From above / the sides it is a
--        wall. GoodPullSwitch_Draw: kGoodPullSwitch_Tab2 (0x17CEE3), chars
--        0xDE / 0x9E (GBA literals at 0x0810D72C / 0x0810D75A).
--   overlords 0x06 / 0x1B (Overlord06_BadSwitchSnake; the GBA's 0x1B is
--        zelda3's 0x1A): once the bad switch is pulled, gen1 counts to
--        kSnakeTrapOverlord_Tab1[slot] (GBA 0x1729F0) and drops a 0x6E
--        rope from z 192 (z speed -2 to -64; it then runs as the shared
--        rope), 0x1B a bomb instead (Sprite_TransmuteToBomb, delay_aux1
--        112: it explodes when the fuse runs out, hit box 9 hurts Link).
--   overlord 0x18 (Overlord17_PotTrap, zelda3 0x17): Link within 32 px
--        -> byte_7E0B9E: the room's falling Stalfos (Palace.lua's
--        overlord 0x05) start.
--   overlord 0x19 (Overlord18_InvisibleStalfos, zelda3 0x18): Link within
--        24 px -> four 0xA7 around him (kRedStalfosTrap_X / Y / Delay,
--        GBA 0x1729F8 / 0x1729FC / 0x172A20), each unseen until its delay
--        runs out; one in a wall is removed, the others appear (64
--        frames).
--   0xD1 Sprite_BunnyBeam (indoors): waits until out of a wall, 128
--        frames, then flies at Link (16) on his level; touching him
--        (bump 0x30) sets link_timer_tempbunny 256 (game.tempBunny); a
--        wall ends it.
--   room tags reading dung_flag_statechange_waterpuzzle (Palace.roomTags
--        wrap): 0x14 RoomTag_RoomTrigger_BlockDoor (the shutters open),
--        0x16 RoomTag_SwitchTrigger_HoldDoor (open while a switch is held
--        or the flag is set), 0x1C-0x1F the moving wall (DesertPalace.lua's
--        wall starts: RoomTag_MovingWallTorchesCheck).
--
-- HOOKS (team A's items): M.arrowHit(actors, x, y, w, h, lower) -- an
-- arrow on the eye statue (installed on Actors:swordHit for arrows; for
-- Items.lua's arrow loop to reach it, Actors.fights answers true for 0x38
-- -- the other item loops that ask Actors.fights see it too);
-- M.somariaSwitch(game, on) -- dung_flag_somaria_block_switch for tag
-- 0x16; M.bunnyBeamHit(game) is what the beam does (game.tempBunny = 256:
-- Link's temporary bunny -- team A's DarkWorld.isBunny does not read it).
--
-- OURS: no sound; the fireball's mirror-shield block; the laser's trail
-- garnish (Garnish04_LaserTrail) is drawn with the beam's own char along
-- its last 16 positions; the big spike, rollers and the Chain Chomp do not
-- tink the sword (they are not counted as enemies for the room's kill
-- tags); Link's pull / push / grab poses are the walking ones; the bunny
-- beam is drawn with the anti-fairy's pictures (kRabbitBeam_Gfx was not
-- found in the GBA) and does not transform Link; the trap bomb falls at
-- z speed -2 a frame and its blast uses OwEnemies' explosion tables
-- (SpriteDraw_SpriteBombExplosion); the hidden Stalfos' poof is the death
-- puff; the statue-on-switch flag and the pull switch's latch are kept
-- apart (the SNES's one byte is reset by each statue every frame, its slot
-- order decides); room 0x58's tag 0x28 (RoomTag_PullSwitchExplodingWall)
-- and 0x10B's 0x1A (RoomTag_WaterGate) are not ported; pull switches 0x05
-- / 0x07 (facing up) are not in any room and are not ported. Sprites run
-- before Link walks here, so Sprite_NullifyHookshotDrag's "previous spot"
-- is Link's spot before the last frame's walk (only when that walk was the
-- frame just before).

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = { NAME = "traps27" }

M.OFF = {
  junX = 0x17CB94, junY = 0x17CB9C, junYv = 0x17CBA4, junXv = 0x17CBA8,
  leDirs = 0x17BB90, leSpX = 0x17BB94, leSpY = 0x17BB98, leXv = 0x17BBA4, leYv = 0x17BBA8, leDmd = 0x17BBAC,
  stXv = 0x1759C0, stYv = 0x1759C4, stDir = 0x1759C8, stJoy = 0x1759CC,
  stSwX = 0x1759D0, stSwY = 0x1759D4, stSwAttr = 0x1759D8, stDmd = 0x1759DC,
  spXv = 0x17B764, spXv2 = 0x17B768, spYv = 0x17B76C, spYv2 = 0x17B770, spDelay = 0x17B774, spDmd = 0x17B778,
  roXv = 0x17BDAC, roYv = 0x17BDB0, roX = 0x17BDB4, roY = 0x17BDF4, roChar = 0x17BE34, roFlags = 0x17BE54,
  hkXv = 0x17BE78, hkYv = 0x17BE7C, hkB = 0x17BE88,
  ccXv = 0x17BEA8, ccYv = 0x17BEB8, ccMul = 0x17BEC8, ccGfx = 0x17BED2, ccFlags = 0x17BEE2,
  wmDmd = 0x17AAF8,
  snake = 0x1729F0, rsX = 0x1729F8, rsY = 0x1729FC, rsDelay = 0x172A20,
  psTab1 = 0x17CEBF, psTab0 = 0x17CECB, psYOffs = 0x17CED7, psTab2 = 0x17CEE3,
  -- code literals (Thumb movs imm8 bytes)
  ccChain = 0x10600C, hkBody = 0x105558, hkHead = 0x105560, hkSmall = 0x105574,
  psTop = 0x10D72C, psBottom = 0x10D75A,
}

M.SNAKE, M.BOMB, M.HIDDEN = 0x1FC, 0x1FB, 0x1FA     -- (our pseudo types)
M.TYPES = { [0xC5] = true, [0xC6] = true, [0x95] = true, [0x96] = true, [0x97] = true, [0x98] = true,
            [0x38] = true, [0x7D] = true, [0x5D] = true, [0x5E] = true, [0x5F] = true, [0x60] = true,
            [0xCA] = true, [0xC7] = true, [0x90] = true, [0x1C] = true, [0x04] = true, [0x06] = true,
            [0xD1] = true, [M.SNAKE] = true, [M.BOMB] = true, [M.HIDDEN] = true }
M.FIGHTS = { [0xC7] = true, [0x90] = true }
M.OV_WALLMASTER, M.OV_SNAKE, M.OV_BOMB, M.OV_POT, M.OV_STALFOS = 0x09, 0x06, 0x1B, 0x18, 0x19
M.A_KEY = "r"   -- the SNES A button (joypad1L & 0x80) is our "r" (Game: action R, item A)

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8, s16 = D.s8, D.s16
  local t = {
    junX = s8(u8(O.junX, 4)), junY = s8(u8(O.junY, 4)), junXv = s8(u8(O.junXv, 4)), junYv = s8(u8(O.junYv, 4)),
    leDirs = u8(O.leDirs, 4), leSpX = s8(u8(O.leSpX, 4)), leSpY = s8(u8(O.leSpY, 4)),
    leXv = s8(u8(O.leXv, 4)), leYv = s8(u8(O.leYv, 4)), leDmd = D.dmd(rom, O.leDmd, 24),
    stXv = s8(u8(O.stXv, 4)), stYv = s8(u8(O.stYv, 4)), stDir = u8(O.stDir, 4), stJoy = u8(O.stJoy, 4),
    stSwX = s8(u8(O.stSwX, 4)), stSwY = s8(u8(O.stSwY, 4)), stSwAttr = u8(O.stSwAttr, 4), stDmd = D.dmd(rom, O.stDmd, 3),
    spXv = s8(u8(O.spXv, 4)), spXv2 = s8(u8(O.spXv2, 4)), spYv = s8(u8(O.spYv, 4)), spYv2 = s8(u8(O.spYv2, 4)),
    spDelay = u8(O.spDelay, 4), spDmd = D.dmd(rom, O.spDmd, 4),
    roXv = s8(u8(O.roXv, 4)), roYv = s8(u8(O.roYv, 4)), roX = s16(rom:bytesU16(O.roX, 32)), roY = s16(rom:bytesU16(O.roY, 32)),
    roChar = u8(O.roChar, 32), roFlags = u8(O.roFlags, 32),
    hkXv = s8(u8(O.hkXv, 4)), hkYv = s8(u8(O.hkYv, 4)), hkB = u8(O.hkB, 8),
    ccXv = s8(u8(O.ccXv, 16)), ccYv = s8(u8(O.ccYv, 16)), ccMul = rom:bytesU16(O.ccMul, 6),
    ccGfx = u8(O.ccGfx, 16), ccFlags = u8(O.ccFlags, 16),
    wmDmd = D.dmd(rom, O.wmDmd, 8),
    snake = u8(O.snake, 8), rsX = s8(u8(O.rsX, 4)), rsY = s8(u8(O.rsY, 4)), rsDelay = u8(O.rsDelay, 4),
    psTab1 = u8(O.psTab1, 12), psTab0 = u8(O.psTab0, 12), psYOffs = u8(O.psYOffs, 12), psTab2 = u8(O.psTab2, 14),
    ccChain = rom:u8(O.ccChain), hkBody = rom:u8(O.hkBody), hkHead = rom:u8(O.hkHead), hkSmall = rom:u8(O.hkSmall),
    psTop = rom:u8(O.psTop), psBottom = rom:u8(O.psBottom),
  }
  check(t.junX[1] == 12 and t.junY[4] == -12 and t.junXv[1] == 40 and t.junYv[4] == -40, "kFireballJunction tables")
  check(t.leDirs[1] == 2 and t.leSpX[1] == 12 and t.leSpY[3] == 12 and t.leXv[2] == -112 and t.leYv[3] == 112
        and t.leDmd[1][2] == -4 and t.leDmd[13][1] == -4 and #t.leDmd == 24, "laser eye tables / kLaserEye_Dmd")
  check(t.stXv[1] == -16 and t.stYv[4] == 16 and t.stDir[2] == 6 and t.stJoy[4] == 8 and t.stSwY[3] == 12
        and t.stSwAttr[4] == 0x3B and t.stDmd[3][5] == 2, "movable statue tables")
  check(t.spXv[1] == 32 and t.spXv2[1] == -16 and t.spYv[4] == -32 and t.spYv2[4] == 16 and t.spDelay[3] == 0x38
        and t.spDmd[4][1] == 8 and t.spDmd[1][5] == 2, "big spike tables")
  check(t.roXv[1] == -16 and t.roYv[4] == 16 and t.roX[18] == 0x10 and t.roY[2] == 0x10 and t.roFlags[4] == 0x80,
        "spike roller tables")
  check(t.hkXv[2] == -16 and t.hkYv[3] == -16 and t.hkB[1] == 8 and t.ccXv[5] == 16 and t.ccYv[1] == -16
        and t.ccMul[1] == 205 and t.ccMul[5] == 8 and t.ccGfx[4] == 3 and t.ccFlags[1] == 0x40, "Pokey / Chain Chomp tables")
  check(t.wmDmd[1][1] == -4 and t.wmDmd[2][1] == 12 and t.wmDmd[4][5] == 2, "kWallMaster_Dmd")
  check(t.snake[1] == 0x20 and t.snake[8] == 0x90 and t.rsX[3] == -48 and t.rsY[2] == 56 and t.rsDelay[4] == 0x90,
        "overlord tables (snake trap, red Stalfos trap)")
  check(t.psTab0[1] == 1 and t.psYOffs[12] == 14 and t.psTab2[14] == 7 and t.psTab1[1] == 5, "pull switch tables")
  check(t.ccChain == 0x8B and t.hkBody == 0xC0 and t.hkHead == 0xC2 and t.hkSmall == 0x40 and t.psTop == 0xDE
        and t.psBottom == 0x9E, "code literals (chain, Pokey, pull switch chars)")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.traps27 end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function P() return require("src.zelda.alttp.Palace") end
local function Act() return require("src.zelda.alttp.Actors") end
local function wrap8(v) v = v % 256 return v >= 128 and v - 256 or v end
local function sign8(v) return band(v, 0x80) ~= 0 end

-- Sprite_DirectionToFaceLink (0 right, 1 left, 2 down, 3 up) and its offsets
local function toLink(a, lk)
  local dx = wrap8(lk.x - a.x)
  local dy = wrap8(lk.y + 8 + (a.z or 0) - a.y)
  local d
  if math.abs(dx) >= math.abs(dy) then d = (dx < 0) and 1 or 0 else d = ((dy < 0) and 1 or 0) + 2 end
  return d, dx, dy
end
M.toLink = toLink

local function sameLevel(self, a) return (a.lower or false) == (self.inside.lower or false) end
local function held(game, k) local i = game.input; return i and i.isDown and i.isDown(k) end
-- button_b_frames: the sword swinging or held
local function bFrames(game) return game.swing ~= nil or (game.swordHeld or 0) > 0 end

-- dung_flag_statechange_waterpuzzle (OURS: the pull / eye latch and the
-- statues' per-frame flag apart)
local function st(self) local s = self.t27; return s ~= nil and (s.flag or s.statue or false) end
M.stateChange = st

local function spawnFireball(self, a, lk)
  -- Sprite_SpawnFireball
  local f = D().spawn(self, 0x55, a.x + 4, a.y + 4 - (a.z or 0), a.lower)
  f.fire, f.delay, f.aux1 = true, 20, 16
  f.vx, f.vy = H().towardsLink(f, lk, 0x20)
  f.bump = 4
  self.game.fireballs = (self.game.fireballs or 0) + 1
  return f
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  local t = a.type
  local tb = T(self.game)
  a.game = self.game
  local cb = D().cbOf(self)
  if t == 0xC5 or t == 0xC6 or t == 0x38 then
    a.untouchable, a.noTouch = true, true
    a.sub2 = 0
  elseif t >= 0x95 and t <= 0x98 then
    a.untouchable, a.noTouch = true, true
    if M._beam then a.beam = true return end
    -- SpritePrep_LaserEye_bounce
    a.D = t - 0x95
    if t >= 0x97 then
      a.x = a.x + 8
      a.head = bxor(band(a.x, 16), 16)
      if a.head == 0 then a.y = a.y + ((band(t, 1) ~= 0) and -8 or 8) end
    else
      a.head = band(a.y, 16)
      if a.head == 0 then a.x = a.x + ((band(t, 1) ~= 0) and -8 or 8) end
    end
  elseif t == 0x7D then
    a.x, a.y = a.x + 8, a.y + 8
    a.homeX, a.homeY = a.x, a.y
    a.untouchable, a.noTouch = true, true
  elseif t >= 0x5D and t <= 0x60 then
    -- SpritePrep_Roller_*
    local D0 = ({ [0x5D] = 2, [0x5E] = 3, [0x5F] = 0, [0x60] = 1 })[t]
    if t == 0x5D or t == 0x5E then a.ai = rshift(band(a.y, 16), 4)
    else a.ai = rshift(band(bit.bnot(a.x), 16), 4) end
    if a.ai ~= 0 and cb then a.hitIdx = band(cb.flags4[t + 1] or 0, 0x1F) + 1 end
    a.D = D0
    a.untouchable, a.noTouch = true, true
  elseif t == 0xCA then
    a.hist = {}
    for i = 0, 6 do a.hist[i] = { a.x, a.y } end
    a.homeX, a.homeY = a.x, a.y
    a.cd = 0
    a.untouchable, a.noTouch = true, true
  elseif t == 0xC7 then
    if M._seg then a.seg, a.hp, a.G = true, 1, 0 return end
    a.A, a.B = 3, 8
    local j = band(D().rnd(self), 3)
    a.vx, a.vy = tb and tb.hkXv[j + 1] or 16, tb and tb.hkYv[j + 1] or 16
  elseif t == 0x90 then
    a.noTouch = true
  elseif t == 0x1C then
    a.y = a.y + 7
    a.untouchable, a.noTouch = true, true
    a.statue = true
  elseif t == 0x04 or t == 0x06 then
    a.untouchable, a.noTouch = true, true
    a.pullSw, a.pullG = true, 0
  elseif t == 0xD1 then
    a.untouchable, a.noTouch = true, true
  elseif t == M.SNAKE or t == M.BOMB or t == M.HIDDEN then
    a.untouchable, a.noTouch = true, true
  end
end

-- ------------------------------------------------------------ the sprites
local function medusa(self, a, lk)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  if band(a.sub2, 0x7F) == 0 and sameLevel(self, a) then spawnFireball(self, a, lk) end
end

local function shooter(self, a, lk)
  local tb = T(self.game)
  if a.delay == 24 then
    local f = spawnFireball(self, a, lk)
    local i = toLink(f, lk)
    f.vx, f.vy = tb.junXv[i + 1], tb.junYv[i + 1]
    f.x, f.y = f.x + tb.junX[i + 1], f.y + tb.junY[i + 1]
    self.game.junctionShots = (self.game.junctionShots or 0) + 1
  elseif a.delay == 0 then
    if bFrames(self.game) and sameLevel(self, a) then a.delay = 32 end
  end
end

local function laserBeam(self, a, lk)
  a.trail = a.trail or {}
  table.insert(a.trail, 1, { a.x, a.y })
  if #a.trail > 16 then a.trail[17] = nil end
  H().moveXY(a)
  D().contact(self, a, lk, { always = true })
  if (a.delay or 0) == 0 then
    a.flags2 = 0x20
    if H().tileCollision(self, a) ~= 0 then a.dead = true end
  end
end

local function laserEye(self, a, lk)
  local tb = T(self.game)
  if a.beam then return laserBeam(self, a, lk) end
  if (a.head or 0) ~= 0 then a.gfx = ((a.aux4 or 0) == 0) and 1 or 0 end
  if a.ai == 0 then
    if (a.head or 0) == 0 and a.D ~= tb.leDirs[rshift(lk.facing or 0, 1) + 1] then
      a.gfx = 0
    else
      local j = (a.D < 2) and (lk.y - a.y) or (lk.x - a.x)
      if band(j + 16, 0xFFFF) < 32 then a.delay, a.ai = 32, 1 else a.gfx = 0 end
    end
  elseif a.ai == 1 then
    a.gfx = 1
    if a.delay == 0 then
      a.ai = 0
      -- LaserEye_FireBeam
      M._beam = true
      local b = D().spawn(self, 0x95, a.x, a.y, a.lower)
      M._beam = nil
      local i = a.D
      b.gfx = rshift(band(i, 2), 1)
      b.x, b.y = b.x + tb.leSpX[i + 1], b.y + tb.leSpY[i + 1]
      b.vx, b.vy = tb.leXv[i + 1], tb.leYv[i + 1]
      b.flags2, b.delay = 0x20, 5
      a.aux4 = 12
      self.game.laserShots = (self.game.laserShots or 0) + 1
    end
  end
end

local function eyeStatue(self, a, lk)
  if (a.B or 0) ~= 0 then return end
  if a.unk2 == 9 and toLink(a, lk) == 2 then
    a.B = 1
    self.t27.flag = true
    self.game.eyeStatueHits = (self.game.eyeStatueHits or 0) + 1
  end
  a.unk2 = nil
end

local function bigSpike(self, a, lk)
  local tb = T(self.game)
  D().contact(self, a, lk)
  if a.ai == 0 then
    local j, dx, dy = toLink(a, lk)
    a.D = j
    if band(dx + 16, 0xFF) < 32 or band(dy + 16, 0xFF) < 32 then
      a.delay, a.ai = tb.spDelay[j + 1], 1
      a.vx, a.vy = tb.spXv[j + 1], tb.spYv[j + 1]
    end
  elseif a.ai == 1 then
    if H().tileCollision(self, a) ~= 0 or a.delay == 0 then a.ai, a.delay = 2, 96 end
    H().moveXY(a)
  else
    if a.delay == 0 then
      local j = a.D
      a.vx, a.vy = tb.spXv2[j + 1], tb.spYv2[j + 1]
      H().moveXY(a)
      if band(a.x, 0xFF) == band(a.homeX, 0xFF) and band(a.y, 0xFF) == band(a.homeY, 0xFF) then a.ai = 0 end
    end
  end
end

local function roller(self, a, lk)
  local tb = T(self.game)
  a.gfx = bor(band(rshift(a.sub2 or 0, 1), 1), band(a.D, 2))
  D().contact(self, a, lk)
  if a.delay == 0 then a.delay = 112; a.D = bxor(a.D, 1) end
  local j = a.D
  a.vx, a.vy = tb.roXv[j + 1], tb.roYv[j + 1]
  H().moveXY(a)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
end

-- ChainChomp_OneMult: (int8) a * b >> 8 by its magnitude, ~ for negatives
local function oneMult(a, b)
  a = band(a, 0xFF)
  local neg = a >= 128
  local at = neg and (256 - a) % 256 or a
  local prod = band(rshift(at * b, 8), 0xFF)
  return neg and (-prod - 1) or prod
end
M.oneMult = oneMult

local function chompLeash(a)
  local h = a.hist
  h[0] = { a.x, a.y }
  for i = 0, 5 do
    local p, q = h[i], h[i + 1]
    local x = p[1] - q[1]
    if x >= 8 then q[1] = p[1] - 8 elseif x < -8 then q[1] = p[1] + 8 end
    local y = p[2] - q[2]
    if y >= 8 then q[2] = p[2] - 8 elseif y < -8 then q[2] = p[2] + 8 end
  end
end
local function chompChain(self, a)
  local tb = T(self.game)
  local h = a.hist
  local x2, y2 = h[0][1] - a.homeX, h[0][2] - a.homeY
  for pos = 1, 6 do
    local m = band(tb.ccMul[pos] or 0, 0xFF)   -- (the GBA reads the low bytes: the 6th is 0)
    local x3 = a.homeX + oneMult(x2, m)
    local y3 = a.homeY + oneMult(y2, m)
    local q = h[pos]
    if q[1] ~= x3 then q[1] = q[1] + ((q[1] - x3 < 0) and 1 or -1) end
    if q[2] ~= y3 then q[2] = q[2] + ((q[2] - y3 < 0) and 1 or -1) end
  end
end

local function chainChomp(self, a, lk)
  local tb = T(self.game)
  local d = D()
  d.contact(self, a, lk)
  chompLeash(a)
  if band(bxor(a.k or 0, self.frame), 3) == 0 and ((a.vx or 0) ~= 0 or (a.vy or 0) ~= 0) then
    a.cd = band(d.angle(self.game, a.vx, a.vy), 15)
  end
  H().moveXY(a); H().moveZ(a)
  a.vz = (a.vz or 0) - 2
  if a.z < 0 then a.z, a.vz, a.fz = 0, 0, 0 end
  local near = band(a.x - a.homeX + 48, 0xFFFF) < 96 and band(a.y - a.homeY + 48, 0xFFFF) < 96
  if a.ai == 0 then
    if a.delay == 0 then
      a.sub2 = (a.sub2 or 0) + 1
      if a.sub2 == 4 then
        a.sub2, a.ai = 0, 2
        local j = band(d.rnd(self), 15)
        a.vx, a.vy = tb.ccXv[j + 1] * 4, tb.ccYv[j + 1] * 4
        d.rnd(self)
        a.vx, a.vy = d.towardsLink(a, lk, 64)
        self.game.chompLunges = (self.game.chompLunges or 0) + 1
      else
        a.delay = band(d.rnd(self), 31) + 16
        local j = band(d.rnd(self), 15)
        a.vx, a.vy = tb.ccXv[j + 1], tb.ccYv[j + 1]
        a.ai = 1
      end
    else
      a.vx, a.vy = 0, 0
    end
  elseif a.ai == 1 then
    if a.delay == 0 then a.delay, a.ai = 32, 0 end
    if band(a.delay, 15) == 0 then chompChain(self, a) end
    if a.z == 0 then a.vz = 16 end
    if not near then
      a.vx, a.vy = Act().project(a.x, a.y, a.homeX, a.homeY, 16)
      H().moveXY(a)
      a.delay = 12
    end
  elseif a.ai == 2 then
    if not near then
      a.vx, a.vy = -a.vx, -a.vy
      H().moveXY(a)
      a.vx, a.vy = 0, 0
      a.ai, a.aux1 = 3, 48
    end
    chompChain(self, a); chompChain(self, a)
  elseif a.ai == 3 then
    if a.aux1 == 0 then a.ai, a.delay = 0, 48 end
    chompChain(self, a); chompChain(self, a)
  end
end

-- Sprite_BounceFromTileCollision
local function bounce(self, a)
  local w = H().tileCollision(self, a)
  if band(w, 3) ~= 0 then a.vx = -a.vx; a.G = (a.G or 0) + 1 end
  if band(w, 12) ~= 0 then a.vy = -a.vy; a.G = (a.G or 0) + 1 end
  return w
end

local function pokey(self, a, lk)
  local tb = T(self.game)
  if a.seg then
    a.recoil = nil
    H().moveXY(a); H().moveZ(a)
    a.vz = (a.vz or 0) - 2
    if a.z < 0 then a.vz, a.z, a.fz = 16, 0, 0 end
    bounce(self, a)
    if (a.G or 0) >= 3 then
      a.dead = true
      require("src.zelda.alttp.Effects").death(self.game, a)
      self.game.pokeySegsGone = (self.game.pokeySegsGone or 0) + 1
    end
    return
  end
  -- a hit (sprite_F 15) takes a segment
  if (a.A or 0) > 0 and a.recoil == 15 then
    a.recoil = 6
    a.z = (a.z or 0) + (a.B or 8)
    a.A = a.A - 1
    if a.A == 0 then a.hp = 17 end
    a.vx = a.vx + ((a.vx < 0) and -4 or 4)
    a.vy = a.vy + ((a.vy < 0) and -4 or 4)
    M._seg = true
    local s = D().spawn(self, 0xC7, a.x, a.y, a.lower)
    M._seg = nil
    s.z = a.z
    s.vx, s.vy = a.rvx or 0, a.rvy or 0
    self.game.pokeySegs = (self.game.pokeySegs or 0) + 1
  end
  if a.recoil and self:recoilStep(a) then return end
  if a.ai == 0 then
    if a.delay == 0 then a.ai, a.vz = 1, 16
    else a.B = tb.hkB[rshift(a.delay, 1) + 1] or 8 end
  elseif a.ai == 1 then
    H().moveXY(a); H().moveZ(a)
    a.vz = a.vz - 2
    if a.z < 0 then a.z, a.fz, a.ai, a.delay = 0, 0, 0, 15 end
    bounce(self, a)
  end
end

local function wallmaster(self, a, lk)
  local game = self.game
  if a.A then
    local inside = self.inside
    lk.x, lk.y = a.x, a.y - a.z + 3
    game.wmHold = a
    game.recoil = nil
    local _, camy = inside:camera(lk.x, lk.y, 240, 160)
    if band(lk.y - camy - 16, 0xFFFF) >= 0x100 then
      game.wmHold = nil
      game.wmSend = true
      game.wallmasterSends = (game.wallmasterSends or 0) + 1
      a.dead = true
      return
    end
  end
  a.recoil = nil   -- (Sprite_90 never calls Sprite_ReturnIfRecoiling)
  if a.ai == 0 then
    H().moveZ(a)
    if a.vz >= -64 then a.vz = a.vz - 3 end
    if a.z < 0 then a.ai, a.z, a.vz, a.fz, a.delay = 1, 0, 0, 0, 63 end
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai = 2 end
    a.gfx = (band(a.delay, 0x20) ~= 0) and 0 or 1
    if not a.A and not game.pitFall and D().contact(self, a, lk) then
      a.A, a.untouchable = true, true
      game.wallmasterGrabs = (game.wallmasterGrabs or 0) + 1
    end
  elseif a.ai == 2 then
    H().moveZ(a)
    if a.vz < 64 then a.vz = a.vz + 2 end
    if a.z >= 256 then
      a.dead = true
      if game.wmHold == a then game.wmHold = nil end
    end
  end
end

-- Statue_CheckForSwitch
local function statueOnSwitch(self, a)
  local tb = T(self.game)
  local inside = self.inside
  local tab = a.lower and inside.attrsLo or inside.attrs
  if not tab then return false end
  for j = 3, 0, -1 do
    local x, y = a.x + tb.stSwX[j + 1], a.y + tb.stSwY[j + 1]
    local v = tab[math.floor(y / 8) * 64 + math.floor(x / 8)]
    local ok = false
    for _, s in ipairs(tb.stSwAttr) do if v == s then ok = true end end
    if not ok then return false end
  end
  return true
end

local function statue(self, a, lk)
  local tb = T(self.game)
  local game = self.game
  if a.dragFlag then a.dragFlag = nil; lk.speedSetting = 0 end
  if (a.delay or 0) > 0 then a.dragFlag = true; lk.speedSetting = 8 end
  -- Statue_BlockSprites
  for _, b in ipairs(self.list) do
    if b ~= a and not b.dead and not b.statue and band(bxor(b.k or 0, self.frame), 1) == 0
       and Act().fights(b.type) then
      if band(a.x - b.x + 12, 0xFFFF) < 24 and band(a.y - b.y + 12, 0xFFFF) < 36 then
        local vx, vy = Act().project(a.x, a.y, b.x, b.y, 32)
        b.recoil, b.rvx, b.rvy, b.subx, b.suby = 4, vx, vy, 0, 0
      end
    end
  end
  local on = statueOnSwitch(self, a)
  self.t27.statue = on
  a.onSwitch = on
  H().moveXY(a)
  local cb = D().cbOf(self)
  a.flags2 = nil
  H().tileCollision(self, a)
  a.vx, a.vy = 0, 0
  local function nullify()
    local pv = game.t27prev
    if pv and pv[3] == (game.frame or 0) - 1 then lk.x, lk.y = pv[1], pv[2] end
  end
  local j
  if D().contact(self, a, lk, { harmless = true, always = true }) then
    a.delay = 7
    game.dashStop = true
    if (a.aux1 or 0) > 0 then nullify() return end
    j = toLink(a, lk)
    a.vx, a.vy = tb.stXv[j + 1], tb.stYv[j + 1]
    self.game.statuePushes = (self.game.statuePushes or 0) + 1
  else
    if a.delay == 0 then a.aux1 = 13 end
    j = toLink(a, lk)
    if band(a.x - lk.x + 16, 0xFFFF) < 35 and band(a.y - lk.y + 12, 0xFFFF) < 36
       and lk.facing == tb.stDir[j + 1] and not game.dash then
      a.A = 1
      game.t27near = a
      local grab = held(game, M.A_KEY)
      game.statueGrab = grab and a or nil
      local dirKey = ({ [1] = "right", [2] = "left", [4] = "down", [8] = "up" })[tb.stJoy[j + 1]]
      if not grab or not held(game, dirKey) or not lk.moving then return end
      j = bxor(j, 1)
      a.vx, a.vy = tb.stXv[j + 1], tb.stYv[j + 1]
      self.game.statuePulls = (self.game.statuePulls or 0) + 1
    else
      if a.A then
        a.A = nil
        lk.speedSetting = 0
        if game.statueGrab == a then game.statueGrab = nil end
      end
      return
    end
  end
  if game.statueGrab ~= a then nullify() end
end

local function pullSwitch(self, a, lk)
  local tb = T(self.game)
  local game = self.game
  -- PullSwitch_HandleDownPulling
  if D().contact(self, a, lk, { harmless = true, always = true }) then
    game.dashStop = true
    local y = band(lk.y - a.y, 0xFF)
    if not sign8(band(y - 2, 0xFF)) then
      if held(game, M.A_KEY) and not held(game, "left") and not held(game, "right") then
        if held(game, "down") and a.pullG == 0 then a.pullG, a.delay = 1, 12 end
      end
      lk.y = a.y + 9
    elseif sign8(band(y - 244, 0xFF)) then
      lk.y = a.y - 21
    else
      if sign8(band(lk.x - a.x, 0xFF)) then lk.x = a.x - 16 else lk.x = a.x + 14 end
    end
  end
  local j = a.pullG
  if j ~= 0 and j ~= 13 then
    lk.y = a.y + tb.psYOffs[j]
    lk.x = a.x
    game.pullHold = a
    if a.delay == 0 then
      j = j + 1
      a.pullG = j
      if j == 13 then
        game.pullHold = nil
        a.pulled = true
        if a.type == 0x06 then self.t27.bombTrap = true
        else self.t27.flag = true end
        game.switchesPulled = (game.switchesPulled or 0) + 1
      end
      a.delay = tb.psTab1[j - 1] or 5
    end
  end
end

local function bunnyBeam(self, a, lk)
  local game = self.game
  if a.ai == 0 then
    if H().tileCollision(self, a) == 0 then a.ai, a.delay = 1, 128 end
    return
  end
  if a.delay == 0 then
    a.bump = 0x30
    if D().contact(self, a, lk) then
      a.dead = true
      M.bunnyBeamHit(game)
      return
    end
    if sameLevel(self, a) then a.vx, a.vy = H().towardsLink(a, lk, 16) end
    H().moveXY(a)
    if H().tileCollision(self, a) ~= 0 then
      a.dead = true
      require("src.zelda.alttp.Effects").death(game, a)
    end
  end
end
function M.bunnyBeamHit(game)
  game.tempBunny = 256
  game.bunnyBeamHits = (game.bunnyBeamHits or 0) + 1
end

-- the snake trap's falling rope: then the shared rope (Actors' critter)
local function snakeDrop(self, a, lk)
  local oz = a.z or 0
  H().moveZ(a)
  if a.vz > -64 then a.vz = a.vz - 2 end
  if oz >= 0 and a.z < 0 then
    a.z, a.vz, a.fz = 0, 0, 0
    a.type, a.palace = 0x6E, nil
    a.untouchable, a.noTouch = nil, nil
    a.state, a.wait, a.dir = "wander", 32, 1
    a.hp = (D().cbOf(self).health[0x6E + 1]) or 1
    self.game.snakesLanded = (self.game.snakesLanded or 0) + 1
  end
end

-- the bomb trap (Sprite_TransmuteToBomb / SpriteBomb_ExplosionIncoming /
-- the explosion, Sprite_4A_BombGuard C 2)
local function trapBomb(self, a, lk)
  if a.boom then
    D().contact(self, a, lk, { box = { a.x - 8, a.y - 8, 32, 32 } })
    if (a.aux1 or 0) == 0 then a.dead = true end
    return
  end
  if (a.z or 0) > 0 or (a.vz or 0) ~= 0 then
    H().moveZ(a)
    a.vz = (a.vz or 0) - 2
    if a.z <= 0 then a.z, a.vz, a.fz = 0, 0, 0 end
  end
  if a.aux1 == 1 then
    a.boom, a.aux1 = true, 31
    self.game.trapBombs = (self.game.trapBombs or 0) + 1
  end
end

-- the invisible Stalfos (Sprite_A7_Stalfos with sprite_E)
local function hiddenStalfos(self, a, lk)
  if a.delay ~= 0 then return end
  a.vx, a.vy = 1, 1
  local w = H().tileCollision(self, a)
  a.vx, a.vy = 0, 0
  if w ~= 0 then a.dead = true return end
  require("src.zelda.alttp.Effects").death(self.game, { type = 0, x = a.x, y = a.y, z = 0, lower = a.lower })
  a.type = 0xA7
  a.untouchable, a.noTouch = nil, nil
  a.hp = D().cbOf(self).health[0xA7 + 1] or 4
  P().prep(self, a, a.k or 0)
  a.D, a.dir = 2, 1
  a.aux2, a.delay = 8, 64
  self.game.stalfosAppeared = (self.game.stalfosAppeared or 0) + 1
end

function M.update(self, a, lk)
  if not T(self.game) then return end
  self.t27 = self.t27 or {}
  local t = a.type
  if t == 0xC5 then return medusa(self, a, lk)
  elseif t == 0xC6 then return shooter(self, a, lk)
  elseif t >= 0x95 and t <= 0x98 then return laserEye(self, a, lk)
  elseif t == 0x38 then return eyeStatue(self, a, lk)
  elseif t == 0x7D then return bigSpike(self, a, lk)
  elseif t >= 0x5D and t <= 0x60 then return roller(self, a, lk)
  elseif t == 0xCA then return chainChomp(self, a, lk)
  elseif t == 0xC7 then return pokey(self, a, lk)
  elseif t == 0x90 then return wallmaster(self, a, lk)
  elseif t == 0x1C then return statue(self, a, lk)
  elseif t == 0x04 or t == 0x06 then return pullSwitch(self, a, lk)
  elseif t == 0xD1 then return bunnyBeam(self, a, lk)
  elseif t == M.SNAKE then return snakeDrop(self, a, lk)
  elseif t == M.BOMB then return trapBomb(self, a, lk)
  elseif t == M.HIDDEN then return hiddenStalfos(self, a, lk)
  end
end

function M.swordImmune(a, how)
  if a.type == 0x90 then return a.A ~= nil end
  return false
end

function M.died(self, a)
  if a.type == 0x90 and self.game.wmHold == a then self.game.wmHold = nil end
end

-- ------------------------------------------------------------ overlords
function M.enterRoom(self, inside)
  self.t27 = {}
  local g = self.game
  g.wmHold, g.pullHold, g.statueGrab, g.t27near = nil, nil, nil, nil
  for _, o in ipairs(self.overlords or {}) do
    -- (byte_7E0B9E is cleared with the room's sprites: Sprite_DisableAll)
    if o.type == M.OV_POT and inside.mem then inside.mem.bigChestOpened = nil end
  end
end

function M.overlord(self, o, camx, camy)
  local t = o.type
  local game = self.game
  local lk = game.link
  local tb = T(game)
  if not tb then return false end
  self.t27 = self.t27 or {}
  if o.done then return (t == M.OV_WALLMASTER or t == M.OV_SNAKE or t == M.OV_BOMB or t == M.OV_POT or t == M.OV_STALFOS) end
  if t == M.OV_WALLMASTER then
    -- Overlord09_WallmasterSpawner
    if o.gen2 ~= 128 then
      if band(self.frame, 1) == 0 then o.gen2 = band(o.gen2 - 1, 0xFF) end
      return true
    end
    o.gen2 = 127
    local w = D().spawn(self, 0x90, lk.x, lk.y, self.inside.lower or false)
    w.z, w.vz = 208, 0
    game.wallmasters = (game.wallmasters or 0) + 1
    return true
  elseif t == M.OV_SNAKE or t == M.OV_BOMB then
    -- Overlord06_BadSwitchSnake
    if o.gen1 == 0 then
      if self.t27.bombTrap then o.gen1 = 1 end
      return true
    end
    local a = o.gen1
    o.gen1 = a + 1
    if a ~= tb.snake[(o.k or 0) + 1] then return true end
    o.done = true
    local s = D().spawn(self, (t == M.OV_BOMB) and M.BOMB or M.SNAKE, o.x, o.y, o.lower)
    s.z, s.vz = 192, 0
    if t == M.OV_BOMB then s.aux1 = 112 end
    game.trapDrops = (game.trapDrops or 0) + 1
    return true
  elseif t == M.OV_POT then
    -- Overlord17_PotTrap
    if band(o.x - lk.x + 32, 0xFFFF) < 64 and band(o.y - lk.y + 32, 0xFFFF) < 64 then
      o.done = true
      self.inside.mem.bigChestOpened = true
      game.potTraps = (game.potTraps or 0) + 1
    end
    return true
  elseif t == M.OV_STALFOS then
    -- Overlord18_InvisibleStalfos
    if band(o.x - lk.x + 24, 0xFFFF) >= 48 or band(o.y - lk.y + 24, 0xFFFF) >= 48 then return true end
    o.done = true
    for i = 3, 0, -1 do
      local s = D().spawn(self, M.HIDDEN, lk.x + tb.rsX[i + 1], lk.y + tb.rsY[i + 1], o.lower)
      s.delay = tb.rsDelay[i + 1]
      s.flags2 = 3
    end
    game.stalfosTraps = (game.stalfosTraps or 0) + 1
    return true
  end
  return false
end

-- the somaria block on a switch (team A's cane): dung_flag_somaria_block_switch
function M.somariaSwitch(game, on) game.somariaOnSwitch = on and true or nil end

-- an arrow (ancilla 9) on the eye statue: sprite_unk2 = 9
function M.arrowHit(actors, x, y, w, h, lower)
  local n = 0
  local cb = D().cbOf(actors)
  for _, a in ipairs(actors.list or {}) do
    if a.type == 0x38 and not a.dead and not (lower ~= nil and (a.lower or false) ~= lower) then
      local hx, hy, hw, hh = Act().hitbox(cb, a)
      if Act().overlapCart(x, y, w, h, hx, hy, hw, hh) then a.unk2 = 9; n = n + 1 end
    end
  end
  return n
end

-- ------------------------------------------------------------ room tags
local PRESSED_SW = { [0x23] = true, [0x3A] = true, [0x3B] = true }
function M.roomTags(self, lk, rt0)
  local game, inside = self.game, self.inside
  local hdr = inside.hdr or {}
  self.t27 = self.t27 or {}
  local on = st(self)
  local s16 = (hdr[6] == 0x16) and 6 or ((hdr[7] == 0x16) and 7 or nil)
  inside.mem.tagDone = inside.mem.tagDone or {}
  if s16 and (on or game.somariaOnSwitch) then
    -- RoomTag_SwitchTrigger_HoldDoor: v = !somaria && !flag && !pressed
    local h2 = {}
    for k, v in pairs(hdr) do h2[k] = v end
    h2[s16] = 0
    inside.hdr = h2
    local ok, err = pcall(rt0, self, lk)
    inside.hdr = hdr
    if not ok then error(err) end
    if self.trapDown ~= false then
      self.trapDown = false
      game:openShutters()
      game.holdDoorOpens = (game.holdDoorOpens or 0) + 1
    end
  else
    rt0(self, lk)
  end
  if not on then return end
  for slot, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
    if tag == 0x14 and not self.t27.blockOpen then
      -- RoomTag_RoomTrigger_BlockDoor
      self.t27.blockOpen = true
      game:openShutters()
      game.blockDoorOpens = (game.blockDoorOpens or 0) + 1
    elseif tag >= 0x1C and tag < 0x20 then
      -- RoomTag_MovingWallTorchesCheck: the flag counts as the torches
      local w = inside.wall
      if w and not w.moved and not w.moving then
        w.moving = true
        game.wallHold = true
        game.wallStarted = (game.wallStarted or 0) + 1
      end
    end
  end
end
M.PRESSED_SW = PRESSED_SW

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end
local function singleChar(spr, t, g) return spr.info.single2[(spr.info.single1[t + 1] or 0) + (g or 0) + 1] end

function M.draw(spr, a, x, y, frame, game)
  local tb = (game and T(game)) or (spr.data.t and spr.data.t.d26 and spr.data.t.d26.traps27)
  if not tb then return false end
  local t = a.type
  local z = a.z or 0
  local f = (t < 0x100) and oamF(spr, t) or 0
  if t == 0xC5 or t == 0xC6 or t == 0x38 or t == M.HIDDEN then
    return true
  elseif t >= 0x95 and t <= 0x98 then
    if a.beam then
      local ch = singleChar(spr, 0x95, a.gfx)
      if ch then
        for i = #(a.trail or {}), 1, -1 do
          local p = a.trail[i]
          spr:oam(x + p[1] - a.x, y + p[2] - a.y, ch, 5, 0)
        end
        spr:oam(x, y, ch, 5, 0)
      end
    else
      spr:drawDmd(a, tb.leDmd, ((a.gfx or 0) + (a.D or 0) * 2) * 3, 3, x, y, f)
    end
  elseif t == 0x7D then
    spr:drawDmd(a, tb.spDmd, 0, 4, x, y, f)
  elseif t >= 0x5D and t <= 0x60 then
    local g = a.gfx or 0
    local n = ((a.ai or 0) ~= 0) and 7 or 3
    local chr = tb.roChar[g * 8 + 1]
    for i = n, 0, -1 do
      local j = g * 8 + i
      spr:oam(x + tb.roX[j + 1], y + tb.roY[j + 1], (chr ~= 0 and chr) or tb.roChar[j + 1], bor(tb.roFlags[j + 1], f), 2)
      chr = 0
    end
  elseif t == 0xCA then
    local j = a.cd or 0
    local fl = bor(band(f, 0x3F), tb.ccFlags[j + 1])
    local ch = singleChar(spr, t, tb.ccGfx[j + 1])
    local r8 = band(a.aux1 or 0, 1) + 4
    local ox, oy = x - a.x, y - a.y
    for i = 5, 0, -1 do
      local p = a.hist and a.hist[i]
      if p then spr:oam(p[1] + r8 + ox, p[2] + r8 + oy, tb.ccChain, bor(band(fl, 0xF0), 0x0D), 0) end
    end
    if ch then spr:oam(x, y - z, ch, fl, 2) end
  elseif t == 0xC7 then
    spr:drawShadow(x, y, t)
    if a.seg then
      local ch = singleChar(spr, t, 0)
      if ch then spr:oam(x, y - z, ch, f, 2) end
    else
      local d = a.B or 8
      local yy = y - z
      for i = (a.A or 0), 0, -1 do
        local ch = ((i == 0) and tb.hkHead or tb.hkBody) - ((d < 7) and tb.hkSmall or 0)
        spr:oam(x, yy, band(ch, 0xFF), f, 2)
        yy = yy - d
      end
    end
  elseif t == 0x90 then
    spr:drawShadow(x, y, t)
    spr:drawDmd(a, tb.wmDmd, (a.gfx or 0) * 4, 4, x, y - z, f)
  elseif t == 0x1C then
    spr:drawDmd(a, tb.stDmd, 0, 3, x, y, f)
  elseif t == 0x04 or t == 0x06 then
    local g = tb.psTab2[(a.pullG or 0) + 1] or 1
    spr:oam(x, y - 1 + g, tb.psBottom, f, 2)
    spr:oam(x, y - 1, tb.psTop, f, 2)
  elseif t == 0xD1 then
    if a.ai == 0 then return true end
    local pt = game and game.data.roomIdx and game.data.roomIdx.palace
    if pt then
      local g = math.floor(frame / 2) % 6
      spr:drawDmd(a, pt.fourAround, g * 5, 5, x, y, 2)
    end
  elseif t == M.SNAKE then
    spr:drawShadow(x, y, 0x6E)
    spr:drawRope({ type = 0x6E, dir = 1 }, x, y - z, frame)
  elseif t == M.BOMB then
    if a.boom then
      local ow = game and game.data.t and game.data.t.owe
      if ow and ow.bombX then
        local base = band(rshift(a.aux1 or 0, 1), 0x0C)
        for i = 3, 0, -1 do
          local j = base + i
          spr:oam(x + ow.bombX[j + 1], y + ow.bombY[j + 1], ow.bombChar[j + 1], bor(ow.bombFlags[j + 1], 8), 2)
        end
      end
    else
      local fl = band(oamF(spr, 0x4A), 0x31)
      fl = bor(fl, ((a.aux1 or 0) < 64) and band(rshift(a.aux1 or 0, 1), 0x0E) or 8)
      local ch = singleChar(spr, 0x4A, 0)
      if ch then spr:oam(x, y - z, ch, fl, 2) end
    end
  else
    return false
  end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G, Dm)
  local A = Act()
  -- a long roller's own hit box (flags4 + 1)
  local hb0 = A.hitbox
  function A.hitbox(cb, a)
    if a.hitIdx then
      local i = a.hitIdx + 1
      local xo = (cb.hitXLo[i] or 0) % 256 + (cb.hitXHi[i] or 0) * 256
      local yo = (cb.hitYLo[i] or 0) % 256 + (cb.hitYHi[i] or 0) * 256
      if xo >= 0x8000 then xo = xo - 0x10000 end
      if yo >= 0x8000 then yo = yo - 0x10000 end
      return a.x + xo, a.y + yo, cb.hitXSize[i] or 16, cb.hitYSize[i] or 16
    end
    return hb0(cb, a)
  end
  -- arrows reach the eye statue (Ancilla_CheckSpriteCollision); the
  -- arrow code asks Actors.fights before Actors:swordHit
  local f0 = A.fights
  function A.fights(t) return f0(t) or t == 0x38 end
  local sh0 = A.swordHit
  function A:swordHit(x, y, w, h, how)
    if how and how.arrow then M.arrowHit(self, x, y, w, h, how.lower) end
    return sh0(self, x, y, w, h, how)
  end
  -- the pull switches take A themselves (not the escape's "pulled" talk)
  local fc0 = A.facing
  function A:facing(px, py)
    local a = fc0(self, px, py)
    if a and a.pullSw and a.palace then return nil end
    return a
  end
  -- the room tags that read dung_flag_statechange_waterpuzzle
  local Pm = P()
  local rt0 = Pm.roomTags
  function Pm.roomTags(self, lk) return M.roomTags(self, lk, rt0) end
  -- Link: his previous spot (Sprite_NullifyHookshotDrag), held by the
  -- Wallmaster / a pull, the statue drag (his facing kept)
  local Doors = require("src.zelda.alttp.Doors")
  local move0 = Doors.move
  function Doors.move(g, inp)
    local lk = g.link
    g.t27prev = { lk.x, lk.y, g.frame or 0 }
    if g.wmHold or g.pullHold then lk.moving, lk.steps = false, 0; return end
    local grab = g.statueGrab
    if grab and not grab.dead and g.interior then
      local f, sp = lk.facing, lk.speedSetting
      lk.speedSetting = 20
      move0(g, inp)
      lk.facing, lk.speedSetting = f, sp
      return
    end
    return move0(g, inp)
  end
  -- WallMaster_SendPlayerToLastEntrance (between frames)
  local esc0 = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if self.wmSend then
      self.wmSend, self.wmHold = nil, nil
      if self.interior then self:enterRoom(self.interior.entranceId or 0) end
      return true
    end
    return esc0(self, inp)
  end
  -- the pull switch's pictures for the shared switch drawing
  local S = require("src.zelda.alttp.Sprites")
  local ds0 = S.drawSwitch
  function S:drawSwitch(a, x, y)
    if a.pullSw and a.palace then return M.draw(self, a, x, y, 0, a.game) end
    return ds0(self, a, x, y)
  end
end

return M
