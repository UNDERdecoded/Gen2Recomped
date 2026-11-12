-- Round 26 (team B): the Palace of Winds boss, the Gyorg Pair (area $71,
-- room $71:00 = PALACE_OF_WINDS_BOSS, its list holds GYORG_BOSS_OBJECT
-- $BA).  Ported from src/object/gyorgBossObject.c, src/enemy/gyorgFemale.c,
-- gyorgFemaleEye.c, gyorgFemaleMouth.c, gyorgMale.c, gyorgMaleEye.c,
-- gyorgChild.c, src/projectile/gyorgTail.c and gyorgMaleEnergyProjectile.c.
--
-- WIRING.  The object ($BA, M.spawnObject) is the fight's manager
--   (GyorgBossObject: a hidden entity in d.objs, extUpdate).  Every other
--   part is an enemy entity in f.entities with boss = true and impl = the
--   fight (G), so Enemies:update calls G:update(part), Field draws it with
--   G:draw (its oamPrio = the cartridge's spriteRendering.b3, so a part at
--   b3 2 / 3 is under the female, who is BG1 at priority 1) and the sword
--   reaches it through G:swordHit.  e.gy names the part: "female" (no
--   sprite: she is BG2), "feye" ($61 x8), "mouth" ($63),
--   "male" ($5D x2), "meye" ($62), "tail" (projectile $16, a chain per
--   Gyorg), "energy" (projectile $17).  The children (GYORG_CHILD $60) are
--   ordinary enemies (M.handles / M.update; the sword and Enemies' touch
--   code apply), made by M.spawnEnemy for a room list or by
--   GyorgBossObject_SpawnChildren.
--
-- THE FIGHT (gyorgBossObject.c).  SetupStart: unless local flag $7B, the
--   female and the two males (type 0 at origin + ($200, $330), type 1 at
--   ($260, $310)), BG3 control $1E07 (the clouds), the scroll speed $C0,
--   field_0x39 (the children live), PL_GYORG_FIGHT (a fall respawns at
--   gPlayerState.startPos: Dungeon.safe here), BGM stopped.  Setup: 600
--   frames, then female phase 1 (unk_6c 8, her health 8); each phase ends
--   when its Gyorg's health is 0: male phase 1 (unk_6c 1, male1 12 hp,
--   SFX_BOSS_DIE, shake 150), female phase 2 (unk_6c $10, health 24) once
--   male1 is gone and Link is back on her (sub_080A20B8: male.unk_7c 0,
--   field_0x14), male phase 2 (unk_6c 2, male2 12), female phase 3 ($20,
--   24), male phase 3 ($104: male2 12 again, she spawns children every 360
--   frames), female phase 4 ($40, 12); at 0: shake 45, the scroll to $600,
--   field_0x39 0 (the children die) and FightEnd: the camera on the object
--   at Link's place, Link's control off, 420 frames (SFX_BOSS_DIE + shake 75
--   at 300, SFX_BOSS_DIE + shake 720 at 180, FX_GIANT_EXPLOSION4 every 32
--   frames under 180), then it drifts north ($60) for 240 frames (the white
--   fade at 60), SetFlag($7B) and the exit (gUnk_0813ABD0: Palace of Winds
--   room 0 = GYORG_TORNADO at ($1D8, $D8)).  startPos is the female's centre
--   ($200, $210), the riding male's place during the male phases.
--   sub_080A1C9C: BG3 drifts along unk_74 at speed unk_76, which eases to
--   unk_78 (8 a frame, $C while turning: sub_080A1D70 brakes to 0, takes
--   the new heading, then speeds back up).  sub_080A1DCC: the mouth and the
--   female's tail collide unless Link rides male1 (male2 once male1 is
--   gone) while it is at b3 2.  sub_080A1FF0: explosions round the centre
--   for the last $20 frames of the object's timer, and (unk_7b) Link within
--   $100 of the centre starts 120 frames of it, a 30-frame shake at $23.
-- THE FEMALE ($5C, gyorgFemale.c): gMapDataBottomSpecial (BG2's 8x8
--   screen map: her body, 32x32 entries at origin + ($180, $190), drawn
--   here as Room.specialImg in the bottom pass; any non-zero cell under
--   Link sets field_0x14) and the room's top map (only her pit / floor
--   collision: metatiles $10 / $11 / $12).  Setup makes the tail (type 0),
--   the mouth and eyes 0-7, Link's layer 2, sub_0804660C(0) and
--   GyorgFemale_Reset (gGyorgMapping0..3 by animationState >> 6: the mask
--   and the top map, read from the ROM).  Action1: a pending turn (unk_79
--   $80 from the male's dive: animationState = (unk_79 & 3) << 6, her
--   position from gUnk_080D1A84, the next frame the maps), the phase bits
--   (unk_6c & $38 -> Action2, & $40 -> Action3), children every 360 frames
--   while unk_6c & $100.  Action2 / Action3: the eye cycle (eyeTimer: 120
--   ChooseEyePattern gUnk_080D1AF8 = $16 / $92 / $94 / $86, 1320 all shut,
--   1440 again; a hit pattern (sub_08000E62(eyesHit) > 2 = three eyes in
--   one window) takes a point (12 at most a cycle), SFX_BOSS_HIT, shake 8;
--   fewer when timer (4 frames from the first eye) runs out: those eyes
--   are marked (unk_80) and Link is thrown back (knockbackDirection unk_3c,
--   iframes $F4, duration $A) with FX_REFECT3 between him and the eye);
--   Action3 also spawns children every 360 frames (gUnk_080D1AF4 / Random &
--   7 sets).  Health 0 in Action3 -> Action1 + SFX_BOSS_DIE.
-- EYES ($61, gyorgFemaleEye.c): fixed spots by her facing (gUnk_080D1F90),
--   gUnk_080D2010 / 2030 animations; open (Action2, then hitType $1E with
--   collision) while their bit is in eyesVulnerable, close (Action4) when
--   it leaves; a marked eye plays its block animation ($14 + facing,
--   hitType $89, SFX_ITEM_GLOVES_KNOCKBACK); all hit ($FF): the hurt
--   animations $10 + facing.  Shown while sub_08048D70 (she has health, or
--   the current male has none), FX_DEATH when they reappear.  Only sword
--   contacts (4-6, 8-13, 16-18, 24-26) are thrown back.
-- MOUTH ($63): at gUnk_080D28CC by facing, animation facing >> 1, the
--   hitbox gUnk_080D28AC on Link's side of it.
-- THE MALES ($5D, gyorgMale.c, all of actions 0-7 and their subActions):
--   1 the opening (type 0 waits for Link on its back -- unk_7c -- then
--   swims north under her, BGM_BOSS_THEME, round and south; type 1 swims
--   east), 2 circling her by the waypoints gUnk_080D1C50 / 60 (Link can
--   board: unk_7c -> 6), 3 circling with GYORG_MALE_ENERGY_PROJECTILE shots
--   (gUnk_080D1B60, speed gUnk_080D1B74), 4 the type-1 loop (gUnk_080D1BBC
--   turns, a shot every $78 frames), 5 phase 3's zig-zag (eyes every $F0 /
--   $3C frames), 6 Link on board: off to a corner ($A8 / $348, $348; too far
--   from Link ($80) -> 2), the turn to a cardinal facing (sets her turn
--   unk_79 and the scroll), then the eyes (GYORG_MALE_EYE every $F0), the
--   tail's whip (unk_72 every $B4 / $168) and children at $F0; at 0 health
--   (and the tail at rest) back to her (gUnk_080D1C.. drop points); 7 the
--   death (120 frames of shaking, the tail segments burst at 90 / 60 / 30,
--   explosions, it sinks and shrinks: affine scale $AA -> $800).
--   sub_08047D88 / DF0 / E48 / E58 / EA4 / F68 / 08048004: field_0x14
--   within $20 (surfaced, animIndex 0), unk_7c's bit history, Link carried
--   by the male's motion and turned with it (gSineTable, the isqrt table
--   gUnk_080D1C04), pushed out to 36 px when he walks into it (it has to be
--   jumped on), kept on it while it is under her unless he landed there.
-- MALE EYES ($62): at gUnk_080D2300 offsets for the male's facing + type,
--   gUnk_080D2348 animations; open 45 frames with collision; a sword hit
--   takes (255 - its health) from the male (SFX_BOSS_HIT, or SFX_BOSS_DIE +
--   shake 40 at 0) and copies its iframes to the male's tail.
-- TAILS (gyorgTail.c): type 0 (hers: 4 segments of $11 / $12 / $14 px +
--   the type2 4 hit point) and type 1 (a male's: $F / $10 / $20); the tip
--   sweeps +-24 (20) round the facing ^ $80 at 64 a frame (GyorgTail_Action1
--   with its u8 / s16 arithmetic), the segments follow within 8
--   (sub_080AC760), frames by direction (sub_080AC6F0 / gUnk_0812A9C0, the
--   others gUnk_0812A9BA); Action2 (the male's unk_72): 60 frames, hitType
--   $1C + SFX_116, the whip $300 a frame for 86 frames.  Type 1 collides
--   unless its male is under her with nobody on it.
-- ENERGY PROJECTILE ($17): 60 frames 40 px ahead of the male, then at Link
--   (GetFacingDirection, SFX_12E), 256 frames or off screen; Link's body
--   deletes it, other contacts (the sword) fizzle it (animation 1, half
--   speed).
-- CHILDREN ($60, gyorgChild.c): GyorgBossObject_SpawnChildren's sets
--   (gUnk_08124EF8 / F08..FDC, from the female: type 0, swim out of her
--   mouth's side with a curve from gUnk_080D1EA0, then 90 frames hidden;
--   from the male: type 1, straight to the attack), Action2 places them
--   at the screen edge relative to Link (attackOffset, attackSpeed) on layer
--   2 (SFX_198 for the first), Action3 across and gone off screen.  Without
--   field_0x39 they die.
-- AFTER: room $70:00 (sub_StateChange_PalaceOfWinds_GyorgTornado, in
--   M.roomInit): local $7B -> LV5_CLEAR and, without the Wind Element,
--   gUnk_additional_8 (FOUR_ELEMENTS + the list manager that brings
--   gUnk_additional_9: warp point + heart container); before it,
--   gUnk_080E72C4 (the BIG_VORTEX to the boss).
-- ROM DATA (M.ROM_RANGES, read through ExtractR26): gyorgMapping_0..3_bottom
--   (the masks) and gAreaRoomMap_PalaceOfWindsBoss_0_top / gyorgRoomMap_1..3
--   _top (LZ77, decoded here).  Small tables written in the .c files are
--   copied below with their symbols.
-- SIMPLIFIED: the male's affine sprite is drawn rotated / scaled with
--   love.graphics (SetAffineInfo's rotation $10000 a turn, scale $100 /
--   param); BG3 is the room's $F000 screen map scrolled by the object's
--   unk_70 / unk_72 (Bg3.lua's offsets hook); CalculateDirectionFromOffsets
--   is atan2; the Gust Jar's grab of the children (GyorgChild_OnGrabbed) is
--   not ported (the jar only stuns them, Enemies:gustPull); only the sword
--   reaches the eyes / tails (e.mask keeps Enemies:hit off the parts);
--   Link's throw-back from a wrong eye pattern is the port's "hurt" push;
--   without the ROM tables (an old cache) the female keeps one facing and
--   her mask is her top-map tiles; SetPlayerControl(3) in the tornado room
--   is not ported; the top layer (her collision) is not drawn (hideTop:
--   the port's atlas showed its metatiles as blocks); FX_DEATH's flipped splash at her mouth is a plain FX.
local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift
local Anim = require("src.zelda.tmc.Anim")
local Assets = require("src.zelda.tmc.Assets")

local M = {}
local G = {}
G.__index = G
M.G = G

M.AREA, M.OBJ = 0x71, 0xBA
local ID = { FEMALE = 0x5C, MALE = 0x5D, CHILD = 0x60, FEYE = 0x61, MEYE = 0x62, MOUTH = 0x63 }
M.ID = ID
local PROJ_TAIL, PROJ_ENERGY = 0x16, 0x17
local FLAG_DONE = 0x7B                       -- SetFlag($7B): local (bank 9)
local LV5_CLEAR, ITEM_WIND_ELEMENT = 0x06, 0x43
local SFX = { BOSS_HIT = 0x127, BOSS_DIE = 0x128, APPARATE = 0xF7, S116 = 0x116, KNOCK = 0x119, S12D = 0x12D,
              S12E = 0x12E, S198 = 0x198, S1B5 = 0x1B5 }
M.SFX = SFX
local BGM_BOSS_THEME = 0x2E
local SPECIAL_FX, FX_DEATH, FX_REFECT3, FX_GIANT_EXPLOSION4 = 0x0F, 0x02, 0x2C, 0x51
local HURT_SWORD = 4

-- ROM data (USA bus addresses = $08000000 + the file offsets in assets/map.json)
local MASK_ADDR = { [0] = 0x08000000 + 5540844, 0x08000000 + 5539948, 0x08000000 + 5538132, 0x08000000 + 5539048 }
local TOP_ADDR = { [0] = 0x08000000 + 5578140, 0x08000000 + 5579112, 0x08000000 + 5580080, 0x08000000 + 5581048 }
M.ROM_RANGES = {
  gyorg_masks = { 0x08000000 + 5538132, 0x08000000 + 5541760 }, -- gyorgMapping_2/3/1/0_bottom.bin.lz (data/map/map_data.s)
  gyorg_tops = { 0x08000000 + 5578140, 0x08000000 + 5582016 },  -- gAreaRoomMap_PalaceOfWindsBoss_0_top, gyorgRoomMap_1..3_top.bin.lz
}

-- gSineTable (256 steps a turn, $100 = 1)
local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
M.SIN = SIN
local function sinT(a) return SIN[band(a, 0xFF)] end
local function cosT(a) return SIN[band(a + 0x40, 0xFF)] end

-- the .c files' constant tables
local FEMALE_POS = { [0] = 0x200, 0x258, 0x1B8, 0x210, 0x200, 0x1C8, 0x248, 0x210 }    -- gUnk_080D1A84
local CHILD_SETS_F = { [0] = 2, 3, 6, 7 }                                                -- gUnk_080D1AF4
local EYE_PATTERNS = { [0] = 0x16, 0x92, 0x94, 0x86 }                                    -- gUnk_080D1AF8
local EYE_POS = { [0] = { 0x1e8, 0x1d8 }, { 0x1f8, 0x1d8 }, { 0x208, 0x1d8 }, { 0x218, 0x1d8 }, { 0x1e8, 0x1e8 }, { 0x1f8, 0x1e8 },
  { 0x208, 0x1e8 }, { 0x218, 0x1e8 }, { 0x238, 0x1f8 }, { 0x238, 0x208 }, { 0x238, 0x218 }, { 0x238, 0x228 },
  { 0x228, 0x1f8 }, { 0x228, 0x208 }, { 0x228, 0x218 }, { 0x228, 0x228 }, { 0x218, 0x248 }, { 0x208, 0x248 },
  { 0x1f8, 0x248 }, { 0x1e8, 0x248 }, { 0x218, 0x238 }, { 0x208, 0x238 }, { 0x1f8, 0x238 }, { 0x1e8, 0x238 },
  { 0x1c8, 0x228 }, { 0x1c8, 0x218 }, { 0x1c8, 0x208 }, { 0x1c8, 0x1f8 }, { 0x1d8, 0x228 }, { 0x1d8, 0x218 },
  { 0x1d8, 0x208 }, { 0x1d8, 0x1f8 } }                                                    -- gUnk_080D1F90
local EYE_A = { [0] = 0, 0, 1, 1, 0, 0, 1, 1, 4, 4, 5, 5, 4, 4, 5, 5, 9, 9, 8, 8, 9, 9, 8, 8, 13, 13, 12, 12, 13, 13, 12, 12 } -- gUnk_080D2010
local EYE_B = { [0] = 2, 2, 3, 3, 2, 2, 3, 3, 6, 6, 7, 7, 6, 6, 7, 7, 11, 11, 10, 10, 11, 11, 10, 10, 15, 15, 14, 14, 15, 15, 14, 14 } -- gUnk_080D2030
local MOUTH_POS = { [0] = 0x200, 0x1C8, 0x248, 0x210, 0x200, 0x258, 0x1b8, 0x210 }     -- gUnk_080D28CC
local MOUTH_HB = { [0] = { -32, -12, 8, 10 }, { 32, -12, 8, 10 }, { 12, -32, 10, 8 }, { 12, 32, 10, 8 },
  { -32, 12, 8, 10 }, { 32, 12, 8, 10 }, { -12, -32, 10, 8 }, { -12, 32, 10, 8 } }      -- gUnk_080D28DC..2914 (x, y, w, h)
local B60 = { [0] = 0x200, 0x184, 0x28C, 0x210, 0x200, 0x29C, 0x174, 0x210 }            -- gUnk_080D1B60
local B70 = { [0] = 0x40, -0x40 }                                                         -- gUnk_080D1B70
local B74 = { [0] = 0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0, 0x100, 0x100, 0xE0, 0xC0, 0xA0, 0x80, 0x60, 0x40, 0x20 } -- gUnk_080D1B74
local BBC = { [0] = 0x1A0, 0xE0 }                                                         -- gUnk_080D1BBC
local BF0 = { [0] = 0x80, -0x80 }                                                         -- gUnk_080D1BF0
local C00 = { [0] = 0x40, 0xC0, 0xC0, 0x40 }                                              -- gUnk_080D1C00 (s8 as u8)
local C04 = { [0] = 0, 1, 4, 9, 16, 25, 36, 49, 64, 81, 100, 121, 144, 169, 196, 225,
  256, 289, 324, 361, 400, 441, 484, 529, 576, 625, 676, 729, 784, 841, 900, 961 }       -- gUnk_080D1C04
local C44 = { [0] = 0, 2, 6, 0, 2, 4, 2, 4, 6, 0, 4, 6 }                                 -- gUnk_080D1C44
local C50 = { [0] = 0x200, 0x180, 0x2C0, 0x210, 0x200, 0x2A0, 0x140, 0x210 }            -- gUnk_080D1C50
local C60 = { [0] = 0x200, 0x150, 0x290, 0x210, 0x200, 0x2D0, 0x170, 0x210 }            -- gUnk_080D1C60
local MEYE_OFF = { [0] = 240, 240, 17, 240, 17, 16, 240, 16, 0, 232, 24, 0, 0, 24, 232, 0, 16, 240, 16, 17, 240, 17, 240, 240, 24,
  0, 0, 24, 232, 0, 0, 232, 16, 16, 239, 16, 239, 240, 16, 240, 0, 24, 232, 0, 0, 232, 24, 0, 240, 16,
  240, 239, 16, 239, 16, 16, 232, 0, 0, 232, 24, 0, 0, 24, 240, 240, 17, 240, 17, 16, 240, 16 } -- gUnk_080D2300 (s8)
local MEYE_ANIM = { [0] = 0, 1, 2, 3, 8, 9, 10, 11, 16, 17, 18, 19, 24, 25, 26, 27,
  32, 33, 34, 35, 40, 41, 42, 43, 48, 49, 50, 51, 56, 57, 58, 59 }                       -- gUnk_080D2348
local TAIL_SWEEP = { [0] = 24, 20 }                                                       -- gUnk_0812A9B8
local TAIL_SPEED = { [0] = -64, 64 }                                                      -- gUnk_0812A9B4
local TAIL_FRAMES = { [0] = 24, 25, 25, 24, 24, 24 }                                      -- gUnk_0812A9BA
local TAIL_DIRF = { [0] = 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 } -- gUnk_0812A9C0
local CHILD_CURVE = { [0] = 80, 1, 64, 1, 48, 1, 32, 1, 16, 1, 0, 0, 16, -1, 32, -1, 48, -1, 64, -1, 80, -1 } -- gUnk_080D1EA0
local SPAWN_XY = { [0] = 0x200, 0x1C0, 0x250, 0x210, 0x200, 0x260, 0x1B0, 0x210 }       -- gUnk_08124EF8
local SPAWN_SETS = { [0] =                                                                -- gUnk_08124FF0 -> F08..FDC
  { -80, 48, 320, -40, 32, 320, 0, 16, 320, 40, 32, 320, 80, 48, 320 },
  { -80, 16, 448, -40, 48, 448, 0, 16, 448, 40, 48, 448, 80, 16, 448 },
  { -80, 16, 320, -40, 48, 576, 0, 16, 320, 40, 48, 576, 80, 16, 320 },
  { -80, 16, 320, -40, 32, 448, 0, 48, 576, 40, 32, 448, 80, 16, 320 },
  { -80, 32, 320, -40, 48, 320, 0, 32, 320, 40, 16, 320, 80, 32, 320 },
  { -80, 32, 576, -40, 32, 448, 0, 32, 320, 40, 32, 448, 80, 32, 576 },
  { -80, 32, 320, 0, 16, 320, 80, 32, 320 },
  { -80, 16, 448, 0, 48, 448, 80, 16, 448 } }
M.SPAWN_SETS = SPAWN_SETS
local HB = { h0 = { x = 0, y = -3, w = 6, h = 6 }, h1 = { x = 0, y = 0, w = 6, h = 6 }, h20 = { x = 0, y = 0, w = 4, h = 4 },
             h21 = { x = 0, y = 0, w = 1, h = 1 }, h22 = { x = 0, y = 0, w = 2, h = 2 }, h28 = { x = 0, y = 0, w = 16, h = 16 } } -- src/data/hitbox.c

local function s8(v) v = band(v, 0xFF) if v >= 128 then return v - 256 end return v end
local function s16(v) v = band(v, 0xFFFF) if v >= 0x8000 then return v - 0x10000 end return v end
local function u16(v) return band(v, 0xFFFF) end
local function u8(v) return band(v, 0xFF) end
local function fl(v) return math.floor(v) end
local function popcount(v) local n = 0 while v ~= 0 do n = n + band(v, 1); v = rshift(v, 1) end return n end -- sub_08000E62
local function cdiv(a, b) if a >= 0 then return fl(a / b) end return -fl(-a / b) end

-- CalculateDirectionFromOffsets: 0..255, 0 up, $40 right
local function calcDir(dx, dy)
  if dx == 0 and dy == 0 then return 0 end
  return band(fl(math.atan2(dx, -dy) / (2 * math.pi) * 256 + 0.5), 0xFF)
end
M.calcDir = calcDir
-- EntityWithinDistance / PointInsideRadius (HALF.HI positions)
local function within(e, x, y, d)
  local dx, dy = fl(e.x) - fl(x), fl(e.y) - fl(y)
  return d * d >= dx * dx + dy * dy
end
M.within = within
-- LinearMoveAngle (direction 0..255, speed 8.8 px a frame)
local function moveAngle(e, speed, dir)
  e.x = e.x + sinT(dir) * speed / 65536
  e.y = e.y - cosT(dir) * speed / 65536
end
-- a 32-step direction (LinearMoveUpdate / ProcessMovement3 without tiles)
local function move32(e, speed, dir) moveAngle(e, speed, band(dir, 0x1F) * 8) end

-- GBA LZ77 (type $10) through a reader -> byte list (1-based)
local function lz77(T, addr)
  local get = T.u8
  if get(addr) ~= 0x10 then return nil end
  local n = get(addr + 1) + get(addr + 2) * 256 + get(addr + 3) * 65536
  local out, o, len = {}, addr + 4, 0
  while len < n do
    local flg = get(o); o = o + 1
    for b = 7, 0, -1 do
      if len >= n then break end
      if band(flg, lshift(1, b)) ~= 0 then
        local b1, b2 = get(o), get(o + 1); o = o + 2
        local disp = bor(lshift(band(b1, 0xF), 8), b2) + 1
        for _ = 1, rshift(b1, 4) + 3 do len = len + 1; out[len] = out[len - disp] or 0 end
      else
        len = len + 1; out[len] = get(o); o = o + 1
      end
    end
  end
  return out
end
M.lz77 = lz77

local function rand(f) local D = require("src.zelda.tmc.Drops") return D.random(D.rngOf(f)) end

-- ---------------------------------------------------------------------------
-- the fight: creation
-- ---------------------------------------------------------------------------
function G.new(d)
  local f = d.field
  return setmetatable({ field = f, d = d, en = f._enemies, A = f.assets, f14frame = -10 }, G)
end
function G:rand() return rand(self.field) end
function G:sfx(id) self.field:sound(id) end
function G:fx(x, y, id) self.field:addFx(x, y, SPECIAL_FX, id) end
function G:player() return self.field.player end
function G:frame() return self.field.frame or 0 end

-- field_0x14 (Link stands on a Gyorg): set this frame, read by the next
function G:setF14() self.f14frame = self:frame() end
function G:f14() return self:frame() - self.f14frame <= 1 end
function G:f14now() return self.f14frame == self:frame() end -- already set during this frame

-- PlayerCanBeMoved
function G:canMove()
  local p = self:player()
  return p.state ~= "ext" and p.state ~= "dead" and p.state ~= "itemget" and not p.falling
end

local function pdef(f, id)
  local d = f.assets.manifest.projectileDefs and f.assets.manifest.projectileDefs[id]
  if d and d.multi then d = d.forms[0] end
  return d
end
local function copyHb(h) if not h then return nil end return { x = h.x or 0, y = h.y or 0, w = h.w or 4, h = h.h or 4 } end

function G:newPart(gy, id, typ, x, y, proj)
  local f = self.field
  local d = (proj and pdef(f, id) or self.en:def(id, typ)) or {}
  local spr = (d.sprite and d.sprite ~= 0) and d.sprite or nil
  local pt = { kind = proj and 4 or 3, id = id, form = typ, type = typ, type2 = 0, gy = gy, x = x or 0, y = y or 0, z = 0,
               boss = true, enemy = true, impl = self, mask = true, def = d, anim = Anim.new(), literalAnim = true,
               field82 = 0, interactType = 0, sprite = spr, health = d.health or 0, hitType = d.damageType or 0,
               hitbox = copyHb(d.hitbox) or { x = 0, y = 0, w = 4, h = 4 }, iframes = 0, kbt = 0, kbx = 0, kby = 0,
               action = 0, subAction = 0, timer = 0, subtimer = 0, direction = 0, speed = d.speed or 0x100,
               animationState = 0, layer = 2, b3 = 2, oamPrio = 2, spritePriority = 4, draw = 1, collide = false }
  pt.gfx = Assets.gfxSource("enemy", d.gfx or 0)
  pt.palId = d.palette or 0
  pt.palette = self.A:objPalette(pt.palId, f.room.atlas and f.room.atlas.palettes)
  f.entities[#f.entities + 1] = pt
  return pt
end
function G:setB3(pt, v) pt.b3 = v; pt.oamPrio = v end
function G:anim(pt, idx, force)
  if not force and pt.animIndex == idx then return end
  pt.animIndex = idx
  if pt.sprite then pt.anim:set(self.A:sprite(pt.sprite), idx, true) end
end
local function adone(pt) return pt.anim.done or band(pt.anim.flags or 0, 0x80) ~= 0 end
local function step1(pt) if not pt.anim.done then pt.anim:update(1) end end -- UpdateAnimationSingleFrame
local function nextFrame(pt) pt.anim:update(1) end                       -- GetNextFrame
local function kill(pt) pt.deleted = true end

-- GyorgBossObject_SetupStart
function G:setupStart(o)
  local f = self.field
  self.obj = o
  o.hidden, o.gyObj = true, true
  o.action, o.t16, o.u6c, o.timer, o.subtimer = 1, 600, 0, 0, 0
  local heap = { boss = o, unk18 = {}, rx = 0, ry = 0, u3c = 0 }
  self.heap = heap
  heap.female = self:makeFemale()
  heap.male1 = self:makeMale(0, 0x200, 0x330)
  heap.male2 = self:makeMale(1, 0x260, 0x310)
  o.u70, o.u72, o.u74, o.u75, o.u7a, o.u7b, o.u7c = 0, 0, 0, 0, 0, 0, 0
  o.u76, o.u78 = 0xC0, 0xC0
  self.alive39 = true                     -- gRoomTransition.field_0x39
  self.gyorgFlag = true                   -- PL_GYORG_FIGHT
  self:startPos(0x200, 0x210)
  f:bgm(nil)                              -- SONG_STOP_BGM
  self:setupBg3()
  -- BG1 holds only her pit / floor metatiles ($10-$12, no picture on the
  -- cartridge); the port's top atlas draws them as stray blocks: hidden
  f.room.hideTop = true
  o.extUpdate = function(_, me) self:objUpdate(me) end
  self.d:track(o)
  f.bossSupport = function() return self:f14() end
  f.gyorg = self
  return o
end

-- gPlayerState.startPosX / Y (PL_GYORG_FIGHT: where a fall comes back)
function G:startPos(x, y)
  self.sx, self.sy = x, y
  if self.gyorgFlag then self.d.safe = { x = x, y = y } end
end

-- BG3 (control $1E07): the room's screen map, scrolled by unk_70 / unk_72
function G:setupBg3()
  local r = self.field.room
  local B = require("src.zelda.tmc.Bg3")
  if not r.bg3 then
    local ok, img = pcall(B.build, r, B.ANIMATED, 0)
    if ok and img then r.bg3 = { img = img, kind = B.ANIMATED, type = 0, off = 0 } end
  end
  if r.bg3 then
    local o = self.obj
    r.bg3.offsetsFn = function() return rshift(u16(o.u70), 8), rshift(u16(o.u72), 8) end
  end
end

-- ---------------------------------------------------------------------------
-- ROM maps: the female's facing (GyorgFemale_Reset)
-- ---------------------------------------------------------------------------
function G:romTables(name)
  local X = require("src.zelda.tmc.ExtractR26")
  return X.tables(self.field, name)
end
function G:loadFacing(k)
  local f = self.field
  local r = f.room
  self.cache = self.cache or {}
  local mt = self:romTables("gyorg_masks")
  local tt = self:romTables("gyorg_tops")
  local mask = mt and (self.cache["m" .. k] or lz77(mt, MASK_ADDR[k]))
  local top = tt and (self.cache["t" .. k] or lz77(tt, TOP_ADDR[k]))
  if mask then self.cache["m" .. k] = mask end
  if top then self.cache["t" .. k] = top end
  if top and #top >= r.tw * r.th * 2 then
    for i = 0, r.tw * r.th - 1 do r.maps.top[i] = top[i * 2 + 1] + top[i * 2 + 2] * 256 end
    r:buildCollision()
    r.dirty = true
  end
  self.mask = {}
  if mask and #mask >= 2048 then
    for i = 0, 1023 do self.mask[i] = mask[i * 2 + 1] + mask[i * 2 + 2] * 256 end
    self:femaleImage(k)
  else
    -- (an old cache) her top-map tiles
    for cy = 0, 31 do
      for cx = 0, 31 do
        local px, py = 0x180 + cx * 8 + 4, 0x190 + cy * 8 + 4
        local t = r:tileType(2, rshift(px, 4), rshift(py, 4))
        self.mask[cy * 32 + cx] = (t and t ~= 0x323) and 1 or 0
      end
    end
  end
end
-- her body: gMapDataBottomSpecial is BG2's 8x8 screen map (RenderMapLayerToSubTileMap);
-- the 32x32 entries at cell (48, 50) drawn from the room's characters (BG2
-- control $1C42: char base 0) and palettes, as Room.specialImg (the bottom pass)
function G:femaleImage(k)
  local r = self.field.room
  if not self.mask or not love.graphics or not love.graphics.newImage then return end
  self.imgs = self.imgs or {}
  if self.imgs[k] == nil then
    local A = self.A
    local ok, img = pcall(function()
      local h = r.maps.header
      local info = A:area(r.area)
      local ts = info and info.tilesets and info.tilesets[h.ts]
      if not ts then return false end
      local vram = A.store:read(ts.file) or ""
      local pals = r.atlas and r.atlas.palettes or A:areaPalettes(r.area, h.ts)
      local W, Hh = 0x180 + 256, 0x190 + 256
      local px, ptr = A.newPixels(W, Hh)
      for ty = 0, 31 do
        for tx = 0, 31 do
          local se = self.mask[ty * 32 + tx] or 0
          if se ~= 0 then
            local tile, hf, vf = band(se, 0x3FF), band(se, 0x400) ~= 0, band(se, 0x800) ~= 0
            local pal = pals and pals[rshift(se, 12)]
            for py = 0, 7 do
              local sy = vf and (7 - py) or py
              for qx = 0, 7 do
                local sx = hf and (7 - qx) or qx
                local byte = vram:byte(tile * 32 + sy * 4 + rshift(sx, 1) + 1) or 0
                local ci = (sx % 2 == 0) and band(byte, 15) or rshift(byte, 4)
                local c = ci ~= 0 and pal and pal[ci]
                if c then A.putPixel(px, ptr, W, 0x180 + tx * 8 + qx, 0x190 + ty * 8 + py, c[1], c[2], c[3], 255) end
              end
            end
          end
        end
      end
      local im = love.graphics.newImage(px)
      im:setFilter("nearest", "nearest")
      return im
    end)
    self.imgs[k] = ok and img or false
    if not ok then self.field.game:log("gyorg body: " .. tostring(img)) end
  end
  r.specialImg = self.imgs[k] or nil
end

-- gMapDataBottomSpecial[(y >> 3 << 7) + (x >> 3)] (the mask sits at cell (48, 50))
function G:onMask(x, y)
  if not self.mask then return false end
  local cx, cy = rshift(fl(x), 3) - 48, rshift(fl(y), 3) - 50
  if cx < 0 or cy < 0 or cx > 31 or cy > 31 then return false end
  return (self.mask[cy * 32 + cx] or 0) ~= 0
end

-- ---------------------------------------------------------------------------
-- touching Link (the parts' collision with the matrix, as Enemies:update)
-- ---------------------------------------------------------------------------
function G:touch(pt, onContact)
  local f = self.field
  local p = f.player
  if not pt.collide or pt.deleted or p.state == "dead" or (p.z or 0) > 8 then return false end
  local HBm = require("src.zelda.tmc.Hitboxes")
  local touch = HBm.touches(f, p, pt)
  local hb = pt.hitbox
  if touch == nil then touch = math.abs((pt.x + hb.x) - p.x) < hb.w + 5 and math.abs((pt.y + hb.y) - (p.y - 3)) < hb.h + 6 end
  if not touch then return false end
  local hurt = HBm.data(f) and HBm.hurtType(p) or 0
  local handler = HBm.data(f) and HBm.handler(self.en.mtx, pt.hitType or 0, hurt)
  if handler == 1 or handler == 2 then return false end
  if handler == 16 then HBm.pushOut(f, pt, hb) return false end
  if onContact then onContact(0x80 + hurt) end
  if p.invuln > 0 then return true end
  local s = self.en:settings(pt.hitType or 0, hurt) or { tgtDmg = 2, orgIfr = 30, orgKbDur = 8, orgKbSpd = 24 }
  if (s.tgtDmg or 0) > 0 or (s.orgKbDur or 0) > 0 then
    if p:hurt(math.max(s.tgtDmg or 0, 1), pt.x, pt.y) then
      p.invuln = math.max(s.orgIfr or 30, 30)
      p.timer = math.max(s.orgKbDur or 8, 4)
      local ks = ((s.orgKbSpd or 24) * 16) / 256
      local dx, dy = p.x - pt.x, p.y - pt.y
      local dd = math.max(0.01, math.sqrt(dx * dx + dy * dy))
      p.kbx, p.kby = dx / dd * ks, dy / dd * ks
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- the boss object (GyorgBossObject)
-- ---------------------------------------------------------------------------
function G:objUpdate(o)
  local h = self.heap
  local a = o.action
  if a == 1 then self:objSetup(o)
  elseif a == 2 then self:femalePhase(o, 8, 3, 1, 0x400, h.male1, 12, true)
  elseif a == 3 then self:malePhase(o, h.male1, 4, 0x10, 24)
  elseif a == 4 then self:femalePhase(o, 0x10, 5, 2, 0x400, h.male1, 12, true)
  elseif a == 5 then self:malePhase(o, h.male2, 6, 0x20, 24)
  elseif a == 6 then self:femalePhase(o, 0x20, 7, 0x104, 0x400, h.male2, 12, false)
  elseif a == 7 then self:malePhase(o, h.male2, 8, 0x40, 12, true)
  elseif a == 8 then self:femalePhase4(o)
  elseif a == 9 then self:fightEnd(o) end
  self:collisionToggle(o)   -- sub_080A1DCC
  self:bgScroll(o)          -- sub_080A1C9C
end

function G:objSetup(o) -- GyorgBossObject_Setup
  o.t16 = o.t16 - 1
  if o.t16 == 0 then
    o.action, o.u6c = 2, 8
    self.heap.female.health = 8
  end
  self:startPos(0x200, 0x210)
end

-- GyorgBossObject_FemalePhase1 / 2 / 3: her health 0 -> the next male phase
-- (Phase1 refills male1 before; 2 / 3 after -- the same values)
function G:femalePhase(o, _, nextA, u6c, scroll, male, hp, setB)
  local fe = self.heap.female
  if fe.health == 0 then
    o.action, o.timer, o.u6c, o.u78 = nextA, 35, u6c, scroll
    if setB then o.u7b = 1 end
    if male then male.health = hp end
    self:sfx(SFX.BOSS_DIE)
    self.field:shake(150, 1)
  end
  self:startPos(0x200, 0x210)
end

-- GyorgBossObject_MalePhase1 / 2 / 3
function G:malePhase(o, male, nextA, u6c, hp, last)
  local fe = self.heap.female
  self:explosionsMid(o) -- sub_080A1FF0
  local cur = male
  if cur == nil or cur.health == 0 then
    if self:maleDone(cur) then
      o.action, o.u6c, o.u78 = nextA, u6c, 0xC0
      if not last then self:scrollTurn(o, fe.animationState) end
      fe.health = hp
    end
    if not last then self:startPos(0x200, 0x210) end
  elseif not last then
    self:startPos(fl(cur.x), fl(cur.y))
  end
  if last then self:startPos(0x200, 0x210) end
end

-- sub_080A20B8
function G:maleDone(other)
  if other == nil then return true end
  local p = self:player()
  if self:canMove() and (p.z or 0) == 0 then return other.u7c == 0 and self:f14() end
  return false
end

function G:femalePhase4(o) -- GyorgBossObject_FemalePhase4
  local fe = self.heap.female
  local p = self:player()
  if fe.health == 0 then
    if o.u6c ~= 0 then
      self.field:shake(45, 1)
      self:sfx(SFX.BOSS_DIE)
      o.u78 = 0x600
    end
    o.u6c = 0
    self.alive39 = false
    if self:canMove() and (p.z or 0) == 0 then
      o.action, o.timer, o.subtimer, o.t16 = 9, 0, 240, 420
      o.direction, o.speed = 0, 0x60
      self.gyorgFlag = false
      o.x, o.y = p.x, p.y
      self.field.cameraTarget = o
      p.state, p.extUpdate = "ext", function() end -- SetPlayerControl(2)
    end
  end
  self:startPos(0x200, 0x210)
end

function G:fightEnd(o) -- GyorgBossObject_FightEnd
  local f = self.field
  if o.t16 == 0 then
    move32(o, o.speed, o.direction)
    self:explosionsEnd(o)
    o.subtimer = o.subtimer - 1
    if o.subtimer == 0 then
      f:setFlag("local", FLAG_DONE, true)
      local p = self:player()
      p.state, p.extUpdate = "normal", nil
      f.cameraTarget = nil
      f.bossSupport = nil
      self.ended = true
      f:startTransition({ warpType = 1, area = 0x70, room = 0x00, endX = 0x1D8, endY = 0xD8, layer = 2, kind = 2, facing = 4, sfx = 0 }) -- gUnk_0813ABD0
      return
    end
    if o.subtimer == 0x3C then f:fade("out", true, 4) end -- SetFade(FADE_IN_OUT | FADE_BLACK_WHITE | FADE_INSTANT, 4)
    return
  end
  o.t16 = o.t16 - 1
  if o.t16 < 0xB4 then self:explosionsEnd(o) return end
  if o.t16 == 0xB4 then self:sfx(SFX.BOSS_DIE); f:shake(720, 2)
  elseif o.t16 == 0x12C then self:sfx(SFX.BOSS_DIE); f:shake(75, 1) end
end

function G:explosionsEnd(o) -- sub_080A1E54
  o.timer = u8(o.timer + 1)
  if band(o.timer, 0x1F) == 0 then
    local r = self:rand()
    self:fx(0x200 + band(r, 0xF0) - 0x78, 0x210 + band(rshift(r, 8), 0x70) - 0x38, FX_GIANT_EXPLOSION4)
  end
end

function G:explosionsMid(o) -- sub_080A1FF0
  local p = self:player()
  if o.timer ~= 0 then
    o.timer = o.timer - 1
    if o.timer <= 0x20 and band(o.timer, 0xF) == 0 then
      local r = self:rand()
      self:fx(0x200 + band(r, 0x78) - 0x3C, 0x210 + band(r, 0x78) - 0x3C, FX_GIANT_EXPLOSION4)
    end
  end
  if o.u7b ~= 0 then
    if within(p, 0x200, 0x210, 0x100) then
      if o.timer == 0 then o.timer = 120
      elseif o.timer == 0x23 then self.field:shake(30, 0) end
    else
      o.u7b = 0
    end
  end
end

-- sub_080A1DCC: the mouth and her tail collide unless Link rides the male at b3 2
function G:collisionToggle(o)
  local h = self.heap
  local m = h.male1 or h.male2
  local off = m ~= nil and band(m.u7c or 0, 0xFF) ~= 0 and m.b3 == 2
  local on = not off
  if h.mouth then h.mouth.collide = on end
  local t = h.tail
  for _ = 1, 4 do if not t then break end; t.collide = on; t = t.child end
end

-- sub_080A1C9C / sub_080A1D8C / sub_080A1D70
local function ease(o, n)
  if o.u78 ~= o.u76 then
    if o.u78 > o.u76 then
      if n < o.u78 - o.u76 then o.u76 = o.u76 + n else o.u76 = o.u78 end
    else
      if n < o.u76 - o.u78 then o.u76 = o.u76 - n else o.u76 = o.u78 end
    end
  end
end
function G:bgScroll(o)
  if o.u7a ~= 0 then
    if o.u74 ~= o.u75 then
      o.u78 = 0
      ease(o, 0xC)
      if o.u76 == 0 then o.u74 = o.u75; o.u78 = o.u7c end
    else
      ease(o, 0xC)
      if o.u78 == o.u76 then o.u7a = 0 end
    end
  else
    ease(o, 8)
  end
  o.u70 = u16(o.u70 + cdiv(sinT(o.u74) * o.u76, 0x100))
  o.u72 = u16(o.u72 - cdiv(cosT(o.u74) * o.u76, 0x100))
end
function G:scrollTurn(o, dir) o.u75 = u8(dir); o.u7a = 1; o.u7c = o.u78 end
M.ease = ease

-- ---------------------------------------------------------------------------
-- the female (gyorgFemale.c)
-- ---------------------------------------------------------------------------
function G:makeFemale()
  local fe = self:newPart("female", ID.FEMALE, 0, 0x200, 0x258)
  fe.sprite = nil
  fe.u79, fe.eyesVuln, fe.eyeTimer, fe.hitFrame, fe.eyesHit, fe.u7f, fe.u80, fe.dmgCycle, fe.spawnT = 0, 0, 0, 0, 0, 0, 0, 0, 60
  fe.health = 0
  return fe
end

function G:femaleSetup(fe) -- GyorgFemale_Setup
  local h = self.heap
  local t = self:newPart("tail", PROJ_TAIL, 0, fe.x, fe.y, true)
  t.parent = fe
  h.tail = t
  local mo = self:newPart("mouth", ID.MOUTH, 0, fe.x, fe.y)
  mo.parent = fe
  h.mouth = mo
  h.eyes = {}
  for i = 0, 7 do
    local e = self:newPart("feye", ID.FEYE, i, fe.x, fe.y)
    e.parent = fe
    h.eyes[i] = e
  end
  fe.action = 1
  self:setB3(fe, 2)
  fe.layer = 2
  fe.eyesVuln, fe.u79, fe.spawnT = 0, 0, 60
  self:femaleTurn(fe, 0)  -- sub_0804660C(this, 0)
  self:femaleReset(fe)
  local p = self:player()
  p.layer = 2
end

function G:femaleTurn(fe, v) -- sub_0804660C
  fe.animationState = v
  local i = rshift(v, 5)
  fe.x, fe.y = FEMALE_POS[i], FEMALE_POS[i + 1]
end
function G:femaleReset(fe) self:loadFacing(rshift(fe.animationState, 6)) end -- GyorgFemale_Reset

function G:femaleSupport() -- sub_080465C8
  local p = self:player()
  if self:onMask(p.x, p.y) then self:setF14() end
end

function G:femaleUpdate(fe)
  local o = self.obj
  local a = fe.action
  if a == 0 then return self:femaleSetup(fe) end
  if a == 1 then
    if band(fe.u79, 0x80) ~= 0 then
      fe.u79 = bor(band(fe.u79, 0x7F), 0x40)
      self:femaleTurn(fe, lshift(band(fe.u79, 3), 6))
    elseif band(fe.u79, 0x40) ~= 0 then
      fe.u79 = band(fe.u79, bit.bnot(0x40))
      self:femaleReset(fe)
    end
    self:femaleSupport()
    if band(o.u6c, 0x38) ~= 0 then
      fe.action, fe.timer, fe.eyeTimer, fe.hitFrame, fe.eyesHit, fe.spawnT, fe.u80 = 2, 0, 0, 0, 0, 60, 0
      return
    end
    if band(o.u6c, 0x40) ~= 0 then
      fe.action, fe.spawnT, fe.timer, fe.eyeTimer, fe.hitFrame, fe.eyesHit, fe.u80 = 3, 60, 0, 0, 0, 0, 0
      return
    end
    if band(o.u6c, 0x100) ~= 0 then
      fe.spawnT = fe.spawnT - 1
      if fe.spawnT == 0 then fe.spawnT = 360; self:femaleChildren(fe, true) end
    end
  elseif a == 2 then
    self:femaleSupport()
    self:eyeHits(fe)
    self:eyeCycle(fe)
    if band(o.u6c, 0x80) ~= 0 then
      fe.spawnT = fe.spawnT - 1
      if fe.spawnT == 0 then fe.spawnT = 360; self:femaleChildren(fe, false) end
    end
    if band(o.u6c, 0x38) == 0 then
      fe.action, fe.spawnT, fe.eyesVuln, fe.u80 = 1, 60, 0, 0
    end
  elseif a == 3 then
    self:femaleSupport()
    fe.spawnT = fe.spawnT - 1
    if fe.spawnT == 0 then fe.spawnT = 360; self:femaleChildren(fe, true) end
    self:eyeHits(fe)
    self:eyeCycle(fe)
    if fe.health == 0 then
      fe.action, fe.spawnT, fe.eyesVuln, fe.u80 = 1, 60, 0, 0
      self:sfx(SFX.BOSS_DIE)
    end
  end
end

function G:eyeCycle(fe)
  fe.eyeTimer = fe.eyeTimer + 1
  if fe.eyeTimer >= 1440 then
    fe.eyeTimer, fe.hitFrame, fe.eyesHit, fe.u80 = 0, 0, 0, 0
  elseif fe.eyeTimer == 120 then
    self:choosePattern(fe)
  elseif fe.eyeTimer == 1320 then
    fe.eyesVuln, fe.eyesHit, fe.u7f = 0, 0, 0
  end
end

function G:choosePattern(fe) -- GyorgFemale_ChooseEyePattern
  if fe.health == 0 then return end
  if fe.eyesVuln == 0xFF then return end
  fe.eyesVuln = EYE_PATTERNS[band(self:rand(), 3)]
  fe.u7f, fe.dmgCycle = 0, 0
  self.heap.unk18 = {}
end

function G:eyeHits(fe) -- GyorgFemale_ProcessEyeHit
  local h = self.heap
  if fe.hitFrame ~= 0 then
    fe.eyesHit = bor(fe.eyesHit, fe.hitFrame)
    if fe.timer == 0 and fe.eyesVuln ~= 0xFF then fe.timer = 4 end
    if popcount(fe.eyesHit) > 2 then
      fe.timer, fe.eyesHit, fe.eyesVuln = 0, 0, 0xFF
      self:sfx(SFX.BOSS_HIT)
      if fe.health ~= 0 then
        self.field:shake(8, 0)
        fe.dmgCycle = fe.dmgCycle + 1
        if fe.dmgCycle <= 12 then fe.health = fe.health - 1 end
        if fe.health == 0 then
          fe.eyesVuln, fe.eyeTimer = 0, 1320
        elseif fe.u7f == 0 then
          fe.u7f, fe.eyeTimer = 1, 1080
        end
      end
      h.unk18 = {}
    end
  end
  if fe.timer ~= 0 and fe.eyesVuln ~= 0xFF then
    fe.timer = fe.timer - 1
    if fe.timer == 0 then
      fe.u80 = bor(fe.u80, fe.eyesHit)
      fe.eyesHit = 0
      h.unk18 = {}
      if h.u3c ~= 0xFF then
        -- Link thrown back (knockbackDirection unk_3c, duration $A) and FX_REFECT3
        local p = self:player()
        if p.state ~= "dead" and p.state ~= "ext" then
          local dir = band(h.u3c, 0x1F) * 8
          p.state, p.timer = "hurt", 0xA
          p.kbx, p.kby = sinT(dir) / 256 * 2, -cosT(dir) / 256 * 2
          p.invuln = math.max(p.invuln or 0, 12)
        end
        self:fx(h.rx, h.ry, FX_REFECT3)
      end
    end
  end
  fe.hitFrame = 0
end

function G:femaleChildren(fe, unlimited) -- GyorgFemale_SpawnChildren
  local set = unlimited and band(self:rand(), 7) or CHILD_SETS_F[band(self:rand(), 3)]
  local st = rshift(fe.animationState, 3)
  if st > 3 then st = rshift(fe.animationState, 6) end -- (>> 3 only stays in the table at facing 0)
  self:spawnChildren(set, false, st)
end

-- ---------------------------------------------------------------------------
-- the female's eyes and mouth
-- ---------------------------------------------------------------------------
function G:eyePlace(e) -- sub_08048D20
  local fe = e.parent
  local k = rshift(fe.animationState, 6)
  if k ~= e.animationState then
    e.animationState = k
    local p = EYE_POS[e.type + k * 8]
    e.x, e.y = p[1], p[2]
    self:anim(e, EYE_A[e.type + k * 8], true)
  end
end
local function shown(self, fe) -- sub_08048D70
  if fe.health ~= 0 then return true end
  local m = self.heap.male1 or self.heap.male2
  if m and m.health ~= 0 then return false end
  return true
end
function G:eyeUpdate(e)
  local fe = e.parent
  if not fe or fe.deleted then return kill(e) end
  if e.iframes > 0 then e.iframes = e.iframes - 1 elseif e.iframes < 0 then e.iframes = e.iframes + 1 end
  local a = e.action
  local bitOn = band(rshift(fe.eyesVuln, e.type), 1) ~= 0
  if a == 0 then
    e.action, e.animationState = 1, 0xFF
    self:setB3(e, 2); e.spritePriority, e.layer = 7, 2
    self:eyePlace(e)
  elseif a == 1 then
    self:eyePlace(e)
    if shown(self, fe) then
      if e.draw == 0 then self:fx(e.x, e.y, FX_DEATH) end
      e.draw = 1
    else
      e.draw = 0
    end
    if bitOn then e.action = 2 end
  elseif a == 2 then
    nextFrame(e)
    if adone(e) then e.action, e.collide, e.hitType = 3, true, 0x1E end
  elseif a == 3 then
    if not bitOn then
      if fe.health ~= 0 then
        e.action, e.collide = 4, false
        self:anim(e, EYE_B[e.animationState * 8 + e.type], true)
      else
        e.action, e.collide, e.draw = 1, false, 0
        self:anim(e, EYE_A[e.animationState * 8 + e.type], true)
        self:fx(e.x, e.y, FX_DEATH)
      end
    elseif band(rshift(fe.u80, e.type), 1) ~= 0 then
      if e.animIndex <= 0x13 then
        e.iframes, e.hitType = -12, 0x89
        self:anim(e, rshift(fe.animationState, 6) + 0x14, true)
        self:sfx(SFX.KNOCK)
      end
      nextFrame(e)
      if adone(e) then
        e.hitType = 0x1E
        self:anim(e, EYE_A[e.animationState * 8 + e.type], true)
        e.anim:update(7)
        fe.u80 = band(fe.u80, bit.bnot(lshift(1, e.type)))
      end
    elseif fe.eyesVuln == 0xFF then
      local t = e.animIndex
      if t < 0x10 or t > 0x13 then
        self:anim(e, e.animationState + 0x10, true)
        e.anim:update(band(self:rand(), 0x1C))
      end
      nextFrame(e)
    end
  elseif a == 4 then
    nextFrame(e)
    if adone(e) then e.action = 1; self:anim(e, EYE_A[e.animationState * 8 + e.type], true) end
  end
end

-- GyorgFemaleEye_OnCollision (contact = the hurtType that hit it)
function G:eyeCollision(e, contact, fromX, fromY)
  local fe = e.parent
  local h = self.heap
  if e.health ~= 0xFF and band(rshift(fe.eyesVuln, e.type), 1) ~= 0 then
    fe.hitFrame = bor(fe.hitFrame, lshift(1, e.type))
    local c = band(contact, 0x7F)
    if (c >= 4 and c <= 6) or (c >= 8 and c <= 13) or (c >= 16 and c <= 18) or (c >= 24 and c <= 26) then
      local p = self:player()
      h.unk18[e.type] = p
      h.rx, h.ry = fl((p.x + e.x) / 2), fl((p.y + e.y) / 2)
      -- knockbackDirection: from the attacker to the eye; ^ $10 points back at Link
      local kd = rshift(calcDir(fl(e.x) - fl(fromX or p.x), fl(e.y) - fl(fromY or p.y)) + 4, 3)
      h.u3c = bxor(band(kd, 0x1F), 0x10)
    else
      h.u3c = 0xFF
    end
  end
  e.health = 0xFF
end

function G:mouthUpdate(mo)
  local fe = mo.parent
  if not fe or fe.deleted then return kill(mo) end
  local p = self:player()
  if mo.action == 0 then
    mo.action = 1
    self:setB3(mo, 2); mo.spritePriority, mo.layer = 7, 2
    mo.animationState = 0xFF
  end
  local t = rshift(fe.animationState, 5)
  if t ~= mo.animationState then
    mo.animationState = t
    mo.x, mo.y = MOUTH_POS[t], MOUTH_POS[t + 1]
    self:anim(mo, rshift(t, 1), true)
  else
    nextFrame(mo)
  end
  if band(t, 2) ~= 0 then
    if mo.y < p.y then t = t + 1 end
  else
    if mo.x < p.x then t = t + 1 end
  end
  local hb = MOUTH_HB[t] or MOUTH_HB[0]
  mo.hitbox = { x = hb[1], y = hb[2], w = hb[3], h = hb[4] }
  self:touch(mo)
end

-- ---------------------------------------------------------------------------
-- the tails (gyorgTail.c)
-- ---------------------------------------------------------------------------
function G:tailChain(t) -- sub_080AC5E4
  local function seg(type2, len)
    local s = self:newPart("tail", PROJ_TAIL, t.type, t.x, t.y, true)
    s.type2, s.parent, s.u79 = type2, t.parent, len
    return s
  end
  if t.type == 0 then
    t.u79 = 0x11
    local e1 = seg(1, 0x12); t.child = e1
    local e2 = seg(2, 0x14); e1.child = e2
    local e3 = seg(3, 0); e2.child = e3
    local e4 = seg(4, 0x14); e4.child = t
  else
    t.u79 = 0xF
    local e1 = seg(1, 0x10); t.child = e1
    local e2 = seg(2, 0x20); e1.child = e2
    local e4 = seg(4, 0x10); e4.child = t
  end
  return true
end

function G:tailFrame(e) -- sub_080AC6F0
  local dir = e.direction
  local u4 = band(dir, 0x1F)
  local u1 = rshift(dir, 5)
  local i3 = u1 * 3
  local tmp = (TAIL_DIRF[e.animationState] or 0) - i3
  if tmp >= 0 and tmp <= 3 then
    if tmp == 0 then if u4 < 7 then return end
    elseif tmp == 1 then if u4 >= 5 and u4 - 5 < 0xD then return end
    elseif tmp == 2 then if u4 >= 0xF and u4 - 0xF < 0xD then return end
    else if u4 > 0x19 then return end end
  end
  local i2 = i3 + 3
  if u4 < 0x1B then
    i2 = i3 + 2
    if u4 < 0x11 then
      i2 = i3
      if 5 < u4 then i2 = i3 + 1 end
    end
  end
  e.animationState = i2 % 24
  e.frameIndex = TAIL_DIRF[i2 % 24]
end

function G:tailFollow(e) -- sub_080AC760
  local e1 = e.child
  local tmp = band(e1.direction - e.direction, 0xFF)
  if band(tmp + 8, 0xFF) > 0x10 then
    if tmp > 0x80 then e1.direction = u8(e.direction - 8) else e1.direction = u8(e.direction + 8) end
  end
  local e2 = e1.child
  if e2.child == nil then
    e2.direction = bxor(e.parent.animationState, 0x80)
  else
    tmp = band(e2.direction - e1.direction, 0xFF)
    if band(tmp + 8, 0xFF) <= 0x10 then return end
    if tmp > 0x80 then e2.direction = u8(e1.direction - 8) else e2.direction = u8(e1.direction + 8) end
  end
end

local function rel(src, dst, len, dir) -- PositionRelative(src, dst, sin * len << 8, -cos * len << 8)
  dst.x = src.x + sinT(dir) * len / 256
  dst.y = src.y - cosT(dir) * len / 256
  dst.z = src.z or 0
end
function G:tailLayout(e) -- sub_080AC7C4
  local e1 = e.child
  local e2 = e1.child
  local e3 = e2.child
  if e3 then e3.x, e3.y, e3.z = e.parent.x, e.parent.y, e.parent.z or 0 else e3 = e.parent end
  rel(e3, e2, e2.u79, e2.direction)
  rel(e2, e1, e1.u79, e1.direction)
  rel(e1, e, e.u79, e.direction)
end

function G:tailWhip(e) -- sub_080AC884
  local par = e.parent
  if (par.u72 or 0) ~= 0 then
    par.u72 = 0
    e.action, e.timer, e.subtimer = 2, 60, 86
  end
end

function G:tailSweep(e) -- GyorgTail_Action1
  local u5 = TAIL_SWEEP[e.type]
  local pa = bxor(e.parent.animationState, 0x80)
  local i3 = pa - rshift(e.u7c, 8)
  if s16(e.u7a) < 0 then
    if band(i3 - u5, 0xFF) <= 0x7F then
      e.u7a = u16(-s16(e.u7a))
      e.u7c = u16(lshift(band(pa - u5, 0xFF), 8))
      self:tailWhip(e)
    else
      e.u7c = u16(e.u7c + s16(e.u7a))
      if band(i3 + u5, 0xFF) >= 0x81 then e.u7c = bor(lshift(band(pa + u5, 0xFF), 8), 0x80) end
    end
  else
    if band(i3 + u5, 0xFF) >= 0x81 then
      e.u7a = u16(-s16(e.u7a))
      e.u7c = u16(lshift(band(pa + u5, 0xFF), 8))
      self:tailWhip(e)
    else
      e.u7c = u16(e.u7c + s16(e.u7a))
      local v = band(i3 - u5, 0xFF)
      if v >= 1 and v - 1 <= 0x7E then e.u7c = bor(lshift(band(pa - u5, 0xFF), 8), 0x80) end
    end
  end
  e.direction = rshift(e.u7c, 8)
  self:tailFrame(e); self:tailFollow(e); self:tailLayout(e)
end

function G:tailUpdate(e)
  local par = e.parent
  if not par or par.deleted then return kill(e) end
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  local t2 = e.type2
  if t2 == 0 then
    if e.action == 0 then -- GyorgTail_Init
      if self:tailChain(e) then
        e.action, e.frameIndex, e.draw = 1, 0xC, 1
        e.u7a = u16(TAIL_SPEED[band(self:rand(), 1)])
        e.u7c = e.u7c or 0
        e.layer = 2
        self:tailSweep(e)
      end
    elseif e.action == 1 then self:tailSweep(e)
    elseif e.action == 2 then -- GyorgTail_Action2
      if e.timer ~= 0 then
        if par.health == 0 then e.action, e.hitType = 1, 0x1D
        else
          e.timer = e.timer - 1
          if e.timer == 0 then e.hitType = 0x1C; self:sfx(SFX.S116) end
        end
      else
        e.subtimer = e.subtimer - 1
        if e.subtimer == 0 then e.action, e.hitType = 1, 0x1D end
        e.u7c = u16(e.u7c + (s16(e.u7a) >= 1 and 0x300 or -0x300))
        e.direction = rshift(e.u7c, 8)
        self:tailFrame(e); self:tailFollow(e); self:tailLayout(e)
      end
    end
  elseif t2 >= 1 and t2 <= 3 then -- sub_080AC510
    if e.action == 0 then
      e.action = 1
      e.frameIndex = TAIL_FRAMES[e.type * 3 + t2 - 1]
      e.draw, e.layer = 1, 2
      if e.type == 0 and t2 == 3 then e.hitbox = copyHb(HB.h21) end
    end
  elseif t2 == 4 then -- sub_080AC560
    local c = e.child
    if not c or c.deleted then return kill(e) end
    if e.action == 0 then
      e.action, e.layer = 1, 2
      e.hitbox = copyHb(e.type == 0 and HB.h1 or HB.h20)
      e.frameIndex, e.draw = 0xFF, 1
    end
    e.x = c.x + sinT(c.direction) * e.u79 / 256
    e.y = c.y - cosT(c.direction) * e.u79 / 256
  end
  -- the wrapper (GyorgTail)
  if e.type == 0 then
    self:setB3(e, 3); e.spritePriority = 1
  else
    self:setB3(e, par.b3 or 2); e.spritePriority = (par.spritePriority or 3) - 2
    e.collide = not (par.b3 == 3 and band(par.u7c or 0, 0xFF) == 0)
  end
  if e.action ~= 0 then self:touch(e) end
end

-- ---------------------------------------------------------------------------
-- the males (gyorgMale.c)
-- ---------------------------------------------------------------------------
function G:makeMale(typ, x, y)
  local m = self:newPart("male", ID.MALE, typ, x, y)
  m.u70, m.u72, m.u74, m.u76, m.u78, m.u7a, m.u7c, m.u7d, m.u7e, m.u80, m.u82, m.u84, m.u86 = 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0
  m.affScale = 0xAA
  m.hitbox = copyHb(HB.h28)
  return m
end

function G:maleD88(m) -- sub_08047D88
  m.u7c = bor(band(lshift(m.u7c, 1), 0x7F), band(m.u7c, 0x80))
  if m.b3 == 3 and self:f14now() then return end
  if m.animIndex == 1 then return end
  local p = self:player()
  if not within(m, p.x, p.y, 0x20) then return end
  self:setF14()
  if (p.z or 0) ~= 0 then return end
  m.u7c = bor(m.u7c, 1)
end
function G:maleCarry(m, ox, oy)
  if band(m.u7c, 1) ~= 0 and self:canMove() then
    local p = self:player()
    p.x = p.x + (fl(m.x) - ox)
    p.y = p.y + (fl(m.y) - oy)
  end
end
function G:maleE58(m) -- sub_08047E58
  local ox, oy = fl(m.x), fl(m.y)
  moveAngle(m, m.speed, m.direction)
  self:maleCarry(m, ox, oy)
end
function G:maleE48(m) self:maleD88(m); self:maleE58(m) end -- sub_08047E48
function G:maleDF0(m, v) -- sub_08047DF0
  self:maleD88(m)
  self:maleEA4(m, v)
  self:maleE58(m)
end
local function facingArg(d) return lshift(band(0x100 - d, 0xFF), 8) end -- ((0x100 - direction) & 0xFF) << 8

-- sub_08047F68: sqrt of the distance to Link, by the table
function G:maleDist(m)
  local p = self:player()
  local dx, dy = fl(p.x) - fl(m.x), fl(p.y) - fl(m.y)
  local d2 = dx * dx + dy * dy
  if d2 == 0x400 then return 0x20 end
  local a = d2 < C04[0x10] and 8 or 0x18
  if d2 < C04[a] then a = a - 4 else a = a + 4 end
  if d2 < C04[a] then a = a - 2 else a = a + 2 end
  if d2 < C04[a] then a = a - 1 else a = a + 1 end
  if a > 31 then a = 31 end
  if d2 < C04[a] and a > 0 then
    local t = C04[a - 1]
    t = t + fl((C04[a] - t) / 2)
    if d2 <= t then a = a - 1 end
  end
  return a
end

function G:maleEA4(m, v) -- sub_08047EA4: the male turns; Link on it turns round it
  m.u78 = u16(v)
  local tmp = m.u78 - m.u7a
  if tmp + 0x100 >= 0 and tmp + 0x100 < 0x200 then return end
  if band(m.u7c, 1) ~= 0 then
    local p = self:player()
    local d = self:maleDist(m)
    local dir = calcDir(fl(p.x) - fl(m.x), fl(p.y) - fl(m.y))
    local t = band(dir - cdiv(tmp, 256), 0xFF)
    p.x = p.x + (sinT(t) - sinT(dir)) * d / 256
    p.y = p.y - (cosT(t) - cosT(dir)) * d / 256
  end
  m.u7a = m.u78
end

function G:maleTurnTo(m, tmp) -- the turn toward tmp by unk_76 steps; true when facing it
  if tmp ~= m.direction then
    if band(tmp - m.direction, 0xFF) > 0x80 then m.u76 = u16(m.u76 - 0x100) else m.u76 = u16(m.u76 + 0x100) end
    m.direction = rshift(m.u76, 8)
    return false
  end
  return true
end

function G:maleTargets(m, i) -- sub_08048178
  local fe = self.heap.female
  local tb = band(rshift(fe.animationState, 6), 1) ~= 0 and C60 or C50
  m.u80, m.u82 = tb[i], tb[i + 1]
end

function G:maleEye(m)
  local e = self:newPart("meye", ID.MEYE, band(self:rand(), 3), m.x, m.y)
  e.parent = m
  return e
end
function G:energy(m)
  local s = self:newPart("energy", PROJ_ENERGY, 0, m.x, m.y, true)
  s.parent, s.layer = m, 2
  return s
end

function G:maleUpdate(m)
  local f = self.field
  local p = self:player()
  if m.iframes > 0 then m.iframes = m.iframes - 1 end
  if m.action ~= 0 then m.draw = m.u7d end
  local a = m.action
  if a == 0 then self:maleInit(m)
  elseif a == 1 then self:maleA1(m)
  elseif a == 2 then self:maleA2(m)
  elseif a == 3 then self:maleA3(m)
  elseif a == 4 then self:maleA4(m)
  elseif a == 5 then self:maleA5(m)
  elseif a == 6 then self:maleA6(m)
  elseif a == 7 then self:maleA7(m) end
  if m.deleted then return end
  if m.action ~= 7 then m.affScale = 0xAA end
  m.animationState = band(-rshift(m.u78, 8), 0xFF)
  self:male004(m)
  m.u7d = m.draw
  local sy = fl(m.y) - fl(f.camY or 0) + 0x30
  if m.draw == 1 and (sy < 0 or sy > 0x100) then m.draw = 0 end
  m.u84, m.u86 = fl(p.x), fl(p.y)
  if m.collide then self:touch(m) end
end

function G:maleInit(m) -- sub_08046898
  local t = self:newPart("tail", PROJ_TAIL, 1, m.x, m.y, true)
  t.parent = m
  m.child = t
  m.action, m.subAction = 1, 0
  m.spritePriority, m.draw = 3, 1
  self:setB3(m, 2)
  m.layer = 2
  m.u7c, m.u78, m.u7a, m.u72 = 0, 0, 0, 0
  self:anim(m, 0, true)
end

function G:maleA1(m)
  local o = self.obj
  local s = m.subAction
  if s == 0 then -- sub_08046930
    if m.type ~= 0 then m.subAction, m.direction, m.speed = 5, 0x20, 0x280 end
    self:maleD88(m)
    if m.u7c ~= 0 then
      m.subAction, m.timer, m.animationState, m.direction, m.speed = 1, 1, 0, 0, 0x280
    end
  elseif s == 1 then -- sub_0804696C
    self:maleE48(m)
    if 0x130 > fl(m.y) then
      m.subAction, m.direction, m.speed = 2, 0x80, 0x100
      self:setB3(m, 3)
      self.field:bgm(BGM_BOSS_THEME)
    end
    if m.timer ~= 0 and 0x258 > fl(m.y) then m.timer = 0; self:sfx(SFX.APPARATE) end
  elseif s == 2 then -- sub_080469CC
    self:maleE48(m)
    if 0x210 < fl(m.y) then m.subAction, m.direction = 3, 0x90 end
  elseif s == 3 then -- sub_080469F4
    self:maleE48(m)
    if 0x290 < fl(m.y) then m.subAction = 4; self:setB3(m, 2) end
  elseif s == 4 then -- sub_08046A30
    self:maleD88(m)
    if band(o.u6c, 1) ~= 0 then m.action, m.subAction = 2, 0 end
  elseif s == 5 then -- sub_08046A54
    self:maleE48(m)
    if 0x380 < fl(m.x) then m.subAction = 6 end
  elseif s == 6 then -- sub_08046A78
    self:maleD88(m)
    if band(o.u6c, 0x10) ~= 0 then m.action, m.subAction = 3, 0 end
  end
  step1(m)
end

function G:maleA2(m) -- sub_08046A9C: circling her
  if m.animIndex == 1 and m.anim.flags == 1 then self:anim(m, 0, true) end
  local s = m.subAction
  if s == 0 then -- sub_08046AE8
    m.subAction, m.speed = 1, 0x180
    self:maleTargets(m, rshift(self.heap.female.animationState, 5))
    m.u76 = lshift(m.direction, 8)
    self:maleD88(m)
  elseif s == 1 or s == 3 then -- sub_08046B18 / sub_08046C04
    local tmp = calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))
    if self:maleTurnTo(m, tmp) then
      if s == 1 then m.subAction = 2
      else m.subAction = 4; m.u70 = rshift(band(tmp + 0x20, 0xC0), 6) end
    end
    self:maleD88(m)
    self:maleEA4(m, facingArg(m.direction))
  elseif s == 2 then -- sub_08046B8C
    if within(m, m.u80, m.u82, 4) then
      m.subAction, m.u76 = 3, lshift(m.direction, 8)
      m.u80, m.u82 = 0x200, 0x210
      self:maleD88(m)
    else
      m.direction = calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))
      self:maleDF0(m, facingArg(m.direction))
    end
  elseif s == 4 then -- sub_08046C88
    if within(m, m.u80, m.u82, 4) then
      m.subAction = 1
      self:maleTargets(m, C44[m.u70 * 3 + self:rand() % 3]) -- sub_08048158
      self:maleD88(m)
    else
      m.direction = calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))
      self:maleDF0(m, facingArg(m.direction))
    end
  end
  step1(m)
  if m.u7c ~= 0 then m.action, m.subAction = 6, 0 end
end

function G:maleA3(m) -- sub_08046CEC: circling with energy shots
  if m.animIndex == 0 and m.anim.flags == 1 then self:anim(m, 1, true) end
  local fe = self.heap.female
  local s = m.subAction
  if s == 0 then -- sub_08046D44
    m.subAction, m.speed = 1, 0x200
    local i = rshift(fe.animationState, 5)
    m.u80, m.u82 = B60[i], B60[i + 1]
    m.u76 = lshift(m.direction, 8)
    self:maleD88(m)
  elseif s == 1 then -- sub_08046D98
    if self:maleTurnTo(m, calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))) then m.subAction = 2 end
    self:maleD88(m)
    self:maleEA4(m, facingArg(m.direction))
  elseif s == 2 then -- sub_08046E0C
    if within(m, m.u80, m.u82, 4) then
      m.subAction, m.u76 = 3, lshift(m.direction, 8)
      self:maleD88(m)
    else
      m.direction = calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))
      self:maleDF0(m, facingArg(m.direction))
    end
  elseif s == 3 then -- sub_08046E68
    local tmp = bxor(fe.animationState, 0x80)
    if not self:maleTurnTo(m, tmp) then
      self:maleD88(m)
      self:maleEA4(m, facingArg(m.direction))
    else
      m.subAction, m.timer, m.subtimer = 4, 63, 1
      m.direction = band(B70[band(self:rand(), 1)] + tmp, 0xC0)
      self:maleD88(m)
    end
  elseif s == 4 then -- sub_08046EF4
    m.timer = m.timer - 1
    if m.timer == 0 then m.timer = 127; m.direction = bxor(m.direction, 0x80) end
    m.speed = B74[band(rshift(m.timer, 3), 0xF)]
    m.subtimer = m.subtimer - 1
    if m.subtimer == 0 then
      m.subtimer = band(self:rand(), 0x38) + 120
      self:energy(m)
    end
    self:maleE48(m)
  end
  step1(m)
  if band(self.obj.u6c, 2) ~= 0 then
    m.action, m.subAction = 2, 0
    m.animationState = band(m.speed, 0xFF)
  end
end

function G:maleA4(m) -- sub_08046F64: the type-1 loop
  if m.animIndex == 0 and m.anim.flags == 1 then self:anim(m, 1, true) end
  local s = m.subAction
  if s == 0 then -- sub_08046FE8
    m.subAction, m.speed, m.u7e = 1, 0x1C0, 0x1E
    m.u80, m.u82 = 0x290, 0x190
    self:maleD88(m)
  elseif s == 1 then -- sub_0804702C
    local tmp = calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))
    if band(m.direction - tmp + 2, 0xFF) > 4 then
      if band(tmp - m.direction, 0x80) ~= 0 then m.direction = u8(m.direction - 1) else m.direction = u8(m.direction + 1) end
    end
    self:maleDF0(m, facingArg(m.direction))
    if within(m, m.u80, m.u82, rshift(m.speed, 16) + 0x10) then
      m.subAction, m.u76, m.speed = 2, lshift(m.direction, 8), 0x280
    end
  elseif s == 2 then -- sub_080470B4
    if not self:maleTurnTo(m, 0x40) then
      self:maleD88(m)
      self:maleEA4(m, facingArg(m.direction))
    else
      m.subAction, m.speed = 3, 0x200
      m.u76 = lshift(m.direction, 8)
      m.u74 = BBC[band(self:rand(), 1)]
      self:maleD88(m)
    end
  elseif s == 3 then -- sub_08047140
    m.u76 = u16(m.u76 + m.u74)
    m.direction = rshift(m.u76, 8)
    if m.direction > 0xBF then m.direction, m.subAction = 0xC0, 4 end
    self:maleDF0(m, facingArg(m.direction))
  elseif s == 4 then -- sub_0804717C
    if m.speed < 0x280 then m.speed = m.speed + 8 end
    self:maleDF0(m, facingArg(m.direction))
    if 0x200 > fl(m.x) then m.subAction = 5 end
  elseif s == 5 then -- sub_080471C8
    if m.speed > 0x180 then m.speed = m.speed - 0x10 end
    if m.direction < 0xE0 then m.direction = m.direction + 1 end
    self:maleDF0(m, facingArg(m.direction))
    if 0x190 > fl(m.y) then
      if m.u74 > 0x100 and band(self:rand(), 1) ~= 0 then m.subAction = 6 else m.subAction = 0 end
    end
  elseif s == 6 then -- sub_0804723C
    m.direction = u8(m.direction - 2)
    if m.direction < 0xC0 then m.subAction, m.speed, m.direction, m.u76 = 7, 0x200, 0xC0, 0xC000 end
    self:maleD88(m)
    self:maleEA4(m, facingArg(m.direction))
  elseif s == 7 then -- sub_08047284
    m.u76 = u16(m.u76 - 0xE0)
    m.direction = rshift(m.u76, 8)
    if m.direction < 0x40 then m.direction, m.subAction = 0x40, 8 end
    self:maleDF0(m, facingArg(m.direction))
  elseif s == 8 then -- sub_080472BC
    if m.speed < 0x300 then m.speed = m.speed + 8 end
    self:maleDF0(m, facingArg(m.direction))
    if 0x2B0 < fl(m.x) then m.subAction, m.u76 = 9, lshift(m.direction, 8) end
  elseif s == 9 then -- sub_08047310
    if m.speed < 0x180 then m.speed = u16(m.speed - 0x10) end
    m.u76 = u16(m.u76 - 0x1D0)
    m.direction = rshift(m.u76, 8)
    if band(m.direction + 0x7F, 0xFF) < 0x40 then m.direction, m.subAction = 0xC0, 4 end
    self:maleDF0(m, facingArg(m.direction))
  end
  step1(m)
  m.u7e = u16(m.u7e - 1)
  if m.u7e == 0 then m.u7e = 0x78; self:energy(m) end
  if band(self.obj.u6c, 4) ~= 0 then m.action, m.subAction = 5, 0 end
end

local function zig(self, m, edgeX, nextSub, pos)
  -- sub_08047508 (pos) / sub_0804763C (not pos)
  if (pos and 0x1A0 < fl(m.x)) or (not pos and 0x1F0 > fl(m.x)) then
    if m.direction == 0 then
      if 0x208 >= fl(m.y) then
        m.u74 = u16(-s16(m.u74))
        m.u76 = u16(m.u76 + s16(m.u74))
        m.direction = rshift(m.u76, 8)
      end
    else
      local tmp = s16(m.u74)
      if pos then
        if tmp < 0 then
          m.u76 = u16(m.u76 + tmp); m.direction = rshift(m.u76, 8)
          if band(m.direction, 0x80) ~= 0 then m.direction, m.u76 = 0, 0 end
        elseif m.direction < 0x40 then
          m.u76 = u16(m.u76 + tmp); m.direction = rshift(m.u76, 8)
          if m.direction >= 0x40 then m.direction = 0x40 end
        end
      else
        if tmp > 0 then
          m.u76 = u16(m.u76 + tmp); m.direction = rshift(m.u76, 8)
          if band(m.direction, 0x80) == 0 then m.direction, m.u76 = 0, 0 end
        elseif m.direction > 0xC0 then
          m.u76 = u16(m.u76 + tmp); m.direction = rshift(m.u76, 8)
          if m.direction <= 0xC0 then m.direction = 0xC0 end
        end
      end
    end
  end
  self:maleE48(m)
  if (pos and edgeX < fl(m.x)) or (not pos and edgeX > fl(m.x)) then
    m.subAction, m.speed, m.animationState = nextSub, 0x200, m.direction
    m.u76 = lshift(m.direction, 8)
  end
  m.u7e = u16(m.u7e - 1)
  if m.u7e == 0 then self:maleEye(m) end
end

function G:maleA5(m) -- sub_0804736C: phase 3
  if m.animIndex == 1 and m.anim.flags == 1 then self:anim(m, 0, true) end
  local s = m.subAction
  if s == 0 then -- sub_080473B8
    m.subAction, m.speed, m.u80, m.u82 = 1, 0x120, 0x200, 0x1D0
    self:maleD88(m)
  elseif s == 1 then -- sub_080473F0
    local tmp = calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))
    if band(m.direction - tmp + 2, 0xFF) > 4 then
      local t2 = tmp - m.direction
      if band(t2, 0x80) ~= 0 then
        if t2 < -1 then m.direction = u8(m.direction - 2) else m.direction = u8(m.direction - 1) end
      else
        if t2 > 1 then m.direction = u8(m.direction + 2) else m.direction = u8(m.direction + 1) end
      end
    end
    self:maleDF0(m, facingArg(m.direction))
    if within(m, m.u80, m.u82, 8) then m.subAction, m.u76, m.speed = 2, lshift(m.direction, 8), 0x180 end
  elseif s == 2 then -- sub_08047484
    if not self:maleTurnTo(m, 0x40) then
      self:maleD88(m)
      self:maleEA4(m, facingArg(m.direction))
    else
      m.subAction, m.speed, m.direction, m.u76, m.u74, m.u7e = 3, 0x200, 0x40, 0x4000, 0x180, 0xF0
      self:maleD88(m)
    end
  elseif s == 3 then zig(self, m, 0x280, 4, true)
  elseif s == 4 then -- sub_080475F4
    m.u76 = u16(m.u76 + 0x180)
    m.direction = rshift(m.u76, 8)
    if m.direction >= 0xC0 then m.direction, m.subAction, m.speed, m.u7e = 0xC0, 5, 0x200, 0x3C end
    self:maleDF0(m, facingArg(m.direction))
  elseif s == 5 then zig(self, m, 0x180, 6, false)
  elseif s == 6 then -- sub_0804772C
    m.u76 = u16(m.u76 - 0x180)
    m.direction = rshift(m.u76, 8)
    if m.direction <= 0x40 then m.direction, m.subAction, m.speed, m.u7e = 0x40, 3, 0x200, 0x1E end
    self:maleDF0(m, facingArg(m.direction))
  end
  step1(m)
  if m.health == 0 then m.action, m.subAction = 7, 0 end
end

function G:maleA6(m) -- sub_08047778: Link on board
  local h = self.heap
  local p = self:player()
  local s = m.subAction
  if s == 0 then -- sub_08047798
    m.subAction, m.speed = 1, 0x80
    m.u80 = (fl(m.x) < 0x1F8) and 0xA8 or 0x348
    m.u82 = 0x348
    self:maleD88(m)
  elseif s == 1 then -- sub_080477F0
    if m.speed < 0x300 then m.speed = m.speed + 8 end
    m.direction = calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))
    self:maleE48(m)
    if not within(m, p.x, p.y, 0x80) then
      m.action, m.subAction = 2, 0
      self:setB3(m, 2)
      m.direction = m.animationState
      step1(m)
      return
    end
    if not within(m, 0x200, 0x210, 0x100) then self:setB3(m, 3) end
    if within(m, m.u80, m.u82, 4) then
      m.subAction = 2
      m.u76 = lshift(m.animationState, 8)
      m.u74 = u16(BF0[band(self:rand(), 1)])
      if band(self.obj.u6c, 1) ~= 0 then
        h.female.u79 = (0x200 > fl(m.x)) and 0x81 or 0x83
      else
        h.female.u79 = 0x80
      end
    end
  elseif s == 2 then -- sub_08047914
    self:maleD88(m)
    if band(m.animationState, 0x1F) ~= 0 then
      m.u76 = u16(m.u76 + s16(m.u74))
      m.animationState = rshift(m.u76, 8)
      self:maleEA4(m, facingArg(m.animationState))
    else
      m.subAction, m.u70 = 3, 0x3C
      m.u7e = m.type * 0xF * 4 + 0x78
      self:scrollTurn(self.obj, m.animationState)
    end
  elseif s == 3 then -- sub_08047978
    self:maleD88(m)
    if m.health ~= 0 then
      m.u70 = u16(m.u70 - 1)
      if m.u70 == 0 then
        m.u72 = 1
        m.u70 = m.type == 0 and 0xB4 or 0x168
      elseif m.u70 == 0xF0 then
        self:maleChildren(m)
      end
    else
      m.u72 = 0
    end
    m.u7e = u16(m.u7e - 1)
    if m.u7e == 0 then m.u7e = 0xF0; self:maleEye(m) end
    if not within(m, p.x, p.y, 0x80) then
      m.action, m.subAction = 2, 0
      self:setB3(m, 2)
      m.direction = m.animationState
    end
    if m.health == 0 and m.child and m.child.action == 1 then
      m.subAction = 4
      if m.type == 0 then
        if rshift(h.female.animationState, 6) == 1 then m.u80, m.u82 = 0x1C0, 0x250 else m.u80, m.u82 = 0x240, 0x250 end
      else
        m.u80 = (0x200 < fl(m.x)) and 0x190 or 0x270
        m.u82 = (0x210 < fl(m.y)) and 0x1A0 or 0x280
      end
    end
  elseif s == 4 then -- sub_08047B08
    self:maleD88(m)
    m.direction = calcDir(m.u80 - fl(m.x), m.u82 - fl(m.y))
    m.speed = 0x200
    self:maleE58(m)
    if within(m, m.u80, m.u82, 4) then
      if m.type == 0 then
        m.action, m.subAction = 7, 0
        m.direction = bxor(m.direction, 0x80)
      else
        m.action, m.subAction = 4, 0
        self:setB3(m, 2)
        m.direction = m.animationState
      end
    end
  end
  step1(m)
end

function G:maleA7(m) -- sub_08047B84: the death
  local s = m.subAction
  if s == 0 then -- sub_08047BA4
    m.subAction, m.timer, m.subtimer = 1, 120, 0
    m.u76 = (0x200 < fl(m.x)) and 0x78 or 0x88
    self:sfx(SFX.S1B5)
    s = 1
  end
  if s == 1 then -- sub_08047BF0
    m.direction = C00[band(m.timer, 3)]
    m.speed = 0x100
    self:maleE48(m)
    if m.timer == 0 then
      local st = m.subtimer
      m.subtimer = u8(m.subtimer + 1)
      if band(st, 0xF) == 0 then
        local r = self:rand()
        self:fx(fl(m.x) + band(r, 0x1E) - 15, fl(m.y) + band(rshift(r, 8), 0x1E) - 15, FX_GIANT_EXPLOSION4)
      end
      m.direction, m.speed = m.u76, 0x140
      self:maleE48(m)
      if fl(m.y) > 0x270 then
        m.subAction, m.u7e = 2, 0xAA
        self:sfx(SFX.S12D)
        self:anim(m, 1, true)
      end
    else
      m.timer = m.timer - 1
      local c = m.child
      if m.timer == 90 and c then c.draw = 0; self:fx(c.x, c.y, FX_GIANT_EXPLOSION4)
      elseif m.timer == 60 and c and c.child then c.child.draw = 0; self:fx(c.child.x, c.child.y, FX_GIANT_EXPLOSION4)
      elseif m.timer == 30 and c and c.child and c.child.child then
        local c3 = c.child.child
        c3.draw = 0; self:fx(c3.x, c3.y, FX_GIANT_EXPLOSION4)
      end
    end
    m.affScale = 0xAA
  elseif s == 2 then -- sub_08047D24
    m.u7e = m.u7e + 8
    if m.u7e > 0x800 then
      if m.type == 0 then self.heap.male1 = nil else self.heap.male2 = nil end
      kill(m)
    else
      if m.u7e < 0x200 then self:maleE48(m) else self:maleE58(m) end
      m.affScale = m.u7e
    end
  end
  if not m.deleted then step1(m) end
end

-- sub_08048004: standing on it / walking into it
function G:male004(m)
  if m.action == 0 then return end
  local p = self:player()
  if m.animIndex == 0 then
    m.collide = false
    if (p.z or 0) ~= 0 then return end
    if not self:canMove() then return end
    if band(m.u7c, 1) ~= 0 then
      if m.b3 == 3 and self:onMask(p.x, p.y) then
        if band(m.u7c, 2) == 0 then m.u7c = bor(m.u7c, 0x80) end
        if band(m.u7c, 0x80) ~= 0 then return end
        p.x, p.y = m.u84, m.u86
        return
      end
      m.u7c = band(m.u7c, bit.bnot(0x80))
    else
      if m.b3 ~= 3 and within(p, m.x, m.y, 0x24) and band(m.u7c, 2) == 0 then
        local t = calcDir(fl(p.x) - fl(m.x), fl(p.y) - fl(m.y))
        p.x = m.x + sinT(t) * 9216 / 65536
        p.y = m.y - cosT(t) * 9216 / 65536
      end
      m.u7c = 0
    end
  else
    m.collide = true
  end
end

function G:maleChildren(m) -- GyorgMale_SpawnChildren
  local r = self:rand()
  self:spawnChildren(band(r, 7), true, band(rshift(r, 8), 3))
end

-- the male's eyes (gyorgMaleEye.c)
function G:meyePlace(e) -- sub_08048F50 (sub_0806FA90: + the s8 offsets)
  local m = e.parent
  e.x = m.x + s8(MEYE_OFF[e.u78 * 2])
  e.y = m.y + s8(MEYE_OFF[e.u78 * 2 + 1])
  e.z = m.z or 0
end
function G:meyeUpdate(e)
  local m = e.parent
  if not m or m.deleted then return kill(e) end
  if e.iframes > 0 then e.iframes = e.iframes - 1 end
  local a = e.action
  if a == 0 then
    e.action = 1
    e.u78 = rshift(band(m.animationState, 0xE0), 3) + e.type
    self:meyePlace(e)
    self:anim(e, MEYE_ANIM[e.u78] or 0, true)
  elseif a == 1 then
    self:meyePlace(e)
    nextFrame(e)
    if adone(e) then e.action, e.collide, e.timer = 2, true, 45 end
  elseif a == 2 then
    self:meyePlace(e)
    e.timer = e.timer - 1
    if e.timer == 0 then e.action, e.collide = 3, false; self:anim(e, e.animIndex + 4, true) end
  elseif a == 3 then
    self:meyePlace(e)
    nextFrame(e)
    if adone(e) then return kill(e) end
  end
  self:setB3(e, m.b3); e.spritePriority = (m.spritePriority or 3) - 1
end
function G:meyeCollision(e) -- GyorgMaleEye_OnCollision
  local tmp = 0xFF - e.health
  if tmp ~= 0 then
    local m = e.parent
    if m.health > tmp then
      m.health = m.health - tmp
      self:sfx(SFX.BOSS_HIT)
    else
      m.health = 0
      self:sfx(SFX.BOSS_DIE)
      self.field:shake(40, 0)
    end
    if e.iframes > 0 then
      m.iframes = e.iframes
      local c = m.child
      for _ = 1, 3 do if not c then break end; c.iframes = e.iframes; c = c.child end
    end
    e.health = 0xFF
  end
end

-- the energy shot (gyorgMaleEnergyProjectile.c)
function G:energyUpdate(s)
  local f = self.field
  local p = self:player()
  local a = s.action
  if a == 0 then
    s.action, s.timer, s.layer = 1, 60, 2
    self:setB3(s, 1)
    self:anim(s, 0, true)
    a = 1
  end
  if a == 1 then
    local m = s.parent
    if not m or m.deleted then return kill(s) end
    local as = m.animationState
    s.x = m.x + sinT(as) * 0x2800 / 65536
    s.y = m.y - cosT(as) * 0x2800 / 65536
    nextFrame(s)
    s.timer = s.timer - 1
    if s.timer == 0 then
      s.action, s.collide = 2, true
      s.direction = rshift(calcDir(fl(p.x) - fl(s.x), fl(p.y) - fl(s.y)) + 4, 3) % 32 -- GetFacingDirection
      self:sfx(SFX.S12E)
    end
  elseif a == 2 then
    move32(s, s.speed, s.direction)
    nextFrame(s)
    local cx, cy = f.camX or 0, f.camY or 0
    if s.x < cx - 16 or s.x > cx + 256 or s.y < cy - 16 or s.y > cy + 176 then return kill(s) end -- IsProjectileOffScreen
    s.timer = u8(s.timer - 1)
    if s.timer == 0 then
      s.action, s.collide, s.speed = 3, false, rshift(s.speed, 1)
      self:anim(s, 1, true)
    end
  elseif a == 3 then
    move32(s, s.speed, s.direction)
    nextFrame(s)
    if adone(s) then return kill(s) end
  end
  if s.collide then
    self:touch(s, function(c)
      local k = s8(band(c, 0x7F))
      if k <= 3 or k == 0x1E or k == 0x1F then s.deleteAfter = true end
    end)
    if s.deleteAfter then kill(s) end
  end
end
function G:energyFizzle(s) -- OnCollision default: the sword
  if s.action ~= 3 then
    s.action, s.collide, s.speed = 3, false, rshift(s.speed, 1)
    self:anim(s, 1, true)
  end
end

-- ---------------------------------------------------------------------------
-- the children (gyorgChild.c): ordinary enemies
-- ---------------------------------------------------------------------------
-- GyorgBossObject_SpawnChildren
function G:spawnChildren(set, fromBlue, as)
  local x, y = SPAWN_XY[as * 2], SPAWN_XY[as * 2 + 1]
  local list = SPAWN_SETS[set]
  local i = 0
  for k = 1, #list, 3 do
    local ox, oy, sp = list[k], list[k + 1], list[k + 2]
    local c = M.makeChild(self.en, fromBlue and 1 or 0, x, y)
    if c then
      c.type2 = i; i = i + 1
      c.direction = as * 8
      c.attackDirection = bxor(as * 8, 0x10)
      c.attackSpeed = sp
      if as == 0 then c.attackX, c.attackY = ox, -oy
      elseif as == 1 then c.attackX, c.attackY = oy + 240, ox
      elseif as == 2 then c.attackX, c.attackY = ox, oy + 160
      else c.attackX, c.attackY = -oy, ox end
      self.field.entities[#self.field.entities + 1] = c
    end
  end
  if not fromBlue then self:fx(x, y, FX_DEATH) end
end

function M.makeChild(E, typ, x, y)
  local f = E.field
  local d = E:def(ID.CHILD, typ) or {}
  local e = {
    kind = 3, id = ID.CHILD, form = typ, type = typ, type2 = 0, x = x, y = y, z = 0, zv = 0,
    health = d.health or 3, maxHealth = d.health or 3, speed = d.speed or 0x200, hitType = d.damageType or 32,
    hitbox = copyHb(d.hitbox) or { x = 0, y = 0, w = 4, h = 4 }, sprite = d.sprite,
    palette = E.A:objPalette(d.palette or 0, f.room.atlas and f.room.atlas.palettes),
    gfx = Assets.gfxSource("enemy", d.gfx or 0), anim = Anim.new(), animationState = 0, direction = 0,
    action = 0, timer = 0, iframes = 0, kbt = 0, kbx = 0, kby = 0, enemy = true, literalAnim = true, field82 = 0,
    interactType = 0, def = d, gyChild = true, layer = 2, oamPrio = 3, spritePriority = 7, noTouch = true,
    attackX = 0, attackY = 0, attackSpeed = 0x140, attackDirection = 0,
  }
  return e
end

function M.childUpdate(E, e)
  local f = E.field
  local g = f.gyorg
  local p = f.player
  if g and not g.alive39 or (not g and f.room.area ~= M.AREA) then
    -- field_0x39 cleared: COLLISION_OFF, health 0 (GenericDeath)
    e.noTouch, e.health = true, 0
    return E:kill(e)
  end
  local cx, cy = f.camX or 0, f.camY or 0
  local a = e.action
  local function setA(idx) if e.animIndex ~= idx then e.animIndex = idx; e.anim:set(E.A:sprite(e.sprite), idx, true) end end
  if a == 0 then -- GyorgChild_Action0
    e.oamPrio, e.spritePriority = 3, 7
    e.animationState = rshift(band(e.direction, 0x1F), 2)
    if e.type == 0 then
      setA(e.animationState)
      e.action, e.noTouch = 1, false
      local r = rand(f) % 11
      e.direction = band(e.direction + r - 5, 0x1F)
      e.timer, e.u7b = CHILD_CURVE[r * 2], CHILD_CURVE[r * 2 + 1]
      e.speed = 0x200
    else
      e.action, e.timer, e.hidden = 2, 1, true
    end
  elseif a == 1 then -- GyorgChild_Action1
    move32(e, e.speed, e.direction)
    if e.timer ~= 0 then
      e.timer = e.timer - 1
      if band(e.timer, 0xF) == 0 then e.direction = band(e.direction + e.u7b, 0x1F) end
    end
    local q = rshift(e.animationState, 1)
    local stay
    if q == 0 then stay = fl(e.y) > cy - 0x18
    elseif q == 1 then stay = fl(e.x) < cx + 0x108
    elseif q == 2 then stay = fl(e.y) < cy + 0xB8
    else stay = fl(e.x) > cx - 0x18 end
    if not stay then e.action, e.timer, e.hidden, e.noTouch = 2, 90, true, true end
  elseif a == 2 then -- GyorgChild_Action2
    e.timer = e.timer - 1
    if e.timer == 0 then
      e.action, e.noTouch, e.hidden = 3, false, false
      rand(f)
      e.spritePriority, e.speed, e.layer, e.oamPrio = 4, e.attackSpeed, 2, 1
      e.direction = e.attackDirection
      e.animationState = rshift(e.direction, 2)
      setA(e.animationState)
      local q = rshift(e.animationState, 1)
      if q == 0 or q == 2 then e.x, e.y = fl(p.x) + e.attackX, cy + e.attackY
      else e.x, e.y = cx + e.attackX, fl(p.y) + e.attackY end
      if e.type2 == 0 then f:sound(SFX.S198) end
    end
  elseif a == 3 then -- GyorgChild_Action3
    move32(e, e.speed, e.direction)
    e.anim:update(1)
    local q = rshift(e.animationState, 1)
    local stay
    if q == 0 then stay = fl(e.y) > cy - 0x28
    elseif q == 1 then stay = fl(e.x) < cx + 0x118
    elseif q == 2 then stay = fl(e.y) < cy + 0xC8
    else stay = fl(e.x) > cx - 0x28 end
    if not stay then e.deleted = true end
  end
end

-- ---------------------------------------------------------------------------
-- the frame / draw / sword
-- ---------------------------------------------------------------------------
function G:update(pt)
  if pt.deleted or self.ended then
    if self.ended then pt.deleted = true end
    return
  end
  local gy = pt.gy
  if gy == "female" then self:femaleUpdate(pt)
  elseif gy == "feye" then self:eyeUpdate(pt)
  elseif gy == "mouth" then self:mouthUpdate(pt)
  elseif gy == "tail" then self:tailUpdate(pt)
  elseif gy == "male" then self:maleUpdate(pt)
  elseif gy == "meye" then self:meyeUpdate(pt)
  elseif gy == "energy" then self:energyUpdate(pt) end
end

local function boxHit(pt, box)
  local hb = pt.hitbox
  return math.abs((pt.x + (hb.x or 0)) - box.x) < (hb.w or 4) + box.w and math.abs((pt.y + (hb.y or 0)) - box.y) < (hb.h or 4) + box.h
end

-- the sword's box against one part (Enemies:swordHits)
function G:swordHit(pt, box)
  if pt.deleted or not pt.collide or pt.iframes ~= 0 then return false end
  if pt.gy == "female" or pt.gy == "mouth" then return false end
  if not boxHit(pt, box) then return false end
  local p = self:player()
  if pt.gy == "feye" or pt.gy == "meye" then
    local s = self.en:settings(pt.hitType or 0, HURT_SWORD)
    local dmg = s and s.orgDmg or 0
    if dmg > 0 then
      pt.health = math.max(0, pt.health - dmg)
      pt.iframes = (s.tgtIfr and s.tgtIfr > 0) and s.tgtIfr or 12
    end
    if pt.gy == "feye" then self:eyeCollision(pt, 0x80 + HURT_SWORD, p.x, p.y) else self:meyeCollision(pt) end
    return dmg > 0
  elseif pt.gy == "energy" then
    self:energyFizzle(pt)
    return true
  end
  return false
end

function G:draw(pt, camX, camY)
  if pt.deleted or not pt.sprite or pt.draw == 0 then return end
  local f = self.field
  local frame = pt.frameIndex or pt.anim.frame
  if not frame or frame == 0xFF then return end
  local img, ox, oy = f.assets:spriteFrame(pt.sprite, frame, pt.palette, "gyorg" .. pt.sprite .. ":" .. tostring(pt.palId), pt.gfx)
  if not img then return end
  local x, y = fl(pt.x - camX), fl(pt.y - camY - (pt.z or 0))
  local hf = pt.anim:hflip()
  if pt.gy == "male" then
    -- SetAffineInfo(scale, scale, unk_78): $100 / scale, rotation $10000 a turn (counter-clockwise)
    local s = 256 / math.max(1, pt.affScale or 0xAA)
    local rot = -(pt.u78 or 0) / 65536 * 2 * math.pi
    love.graphics.draw(img, x, y, rot, hf and -s or s, s, -ox, -oy)
  elseif hf then
    love.graphics.draw(img, x - ox, y + oy, 0, -1, 1)
  else
    love.graphics.draw(img, x + ox, y + oy)
  end
end

-- ---------------------------------------------------------------------------
-- R26 hooks
-- ---------------------------------------------------------------------------
function M.spawnObject(d, e)
  if e.id ~= M.OBJ then return nil end
  local f = d.field
  if f:flag("local", FLAG_DONE) then -- CheckFlags($7B): DeleteThisEntity
    e.hidden, e.deleted = true, true
    return e
  end
  return G.new(d):setupStart(e)
end

function M.spawnEnemy(E, dat, def)
  if dat.id == ID.CHILD then
    local c = M.makeChild(E, dat.paramA or 0, dat.x, dat.y)
    c.direction = 0
    return c
  end
  return nil
end

function M.handles(e) return e.gyChild == true end
function M.update(E, e)
  if e.gyChild then
    if e.iframes > 0 then e.iframes = e.iframes - 1 end
    return M.childUpdate(E, e)
  end
end

-- sub_StateChange_PalaceOfWinds_GyorgTornado ($70:00): the way in and the exit
function M.roomInit(f)
  local r = f.room
  if not r or r.area ~= 0x70 or r.room ~= 0x00 then return end
  local props = r.maps and r.maps.header and r.maps.header.props
  if f:flag("global", LV5_CLEAR) and props and props[9] then f:loadEntityList(props[9]) end -- gUnk_additional_9
  if not f:flag("local", FLAG_DONE) then
    f:loadEntityList(0x080E72C4) -- gUnk_080E72C4: the BIG_VORTEX to the boss
  else
    f:setFlag("global", LV5_CLEAR, true)
    if (f:inventory(ITEM_WIND_ELEMENT) or 0) == 0 then
      if props and props[8] then f:loadEntityList(props[8]) end -- gUnk_additional_8: FOUR_ELEMENTS + its list manager
      f:bgm(nil)
    end
  end
end

return M
