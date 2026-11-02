-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S SECOND BYTECODE: what an NPC does while a script watches.
--
-- `applymovement <localID> <offset>` is 3,025 rows across this cartridge --
-- every cutscene walk, every turn-to-face, every "!" over somebody's head --
-- and the port lowered all of them to "make the object face the player",
-- because the movement data itself was never read.
--
-- IT IS NOT IN AN ARCHIVE.  `ScrCmd_ApplyMovement` (scrcmd.c) does
--
--     MapObject_StartAnimation(object, (MapObjectAnimCmd *)(ctx->scriptPtr + movementOffset))
--
-- so the commands sit INSIDE THE SCRIPT MEMBER, at an offset from the byte
-- after the instruction -- the same way a `goto` target does.  That is why
-- there is no archive to find: it was always a few bytes further down the file
-- the script was already in.
--
-- A COMMAND IS FOUR BYTES, `{ u16 movementAction, u16 count }`
-- (`map_object_anim_cmd.h`), and a list ends at `MOVEMENT_ACTION_END`, which
-- `generated/movement_actions.txt` gives explicitly as **254** -- the only
-- entry in that file with a value written beside it, everything else being its
-- own line number minus one.
--
-- MEASURED over all 1,124 members of scr_seq, following `goto` targets as well
-- as entry points: **3,025 applymovement sites, 1,881 distinct lists, and all
-- 3,025 decode to a list that ends at 254** -- no refusals anywhere, 7,028
-- steps between them, 58 distinct actions, lists of 1 to 24 commands, repeat
-- counts from 1 to 38.  A format that terminates cleanly three thousand times
-- out of three thousand is being read correctly; the 162 members that contain
-- any of it are the cutscene members.
--
-- THE COMMONEST ACTIONS, which is what says the table below is pointed at the
-- right things: WALK_FAST_SOUTH (723), WALK_FAST_EAST (656), WALK_FAST_NORTH
-- (641), DELAY_8 (568), WALK_FAST_WEST (543), WALK_ON_SPOT_NORMAL_SOUTH (413),
-- WALK_ON_SPOT_NORMAL_EAST (367), WALK_ON_SPOT_NORMAL_NORTH (351).  Walking,
-- turning on the spot, and waiting -- which is what a cutscene is.
--
-- FOUR ACTIONS IN THE WHOLE CARTRIDGE HAVE NO NAME HERE: 106 (3 steps), 107
-- (2), 117 (11) and 153 (4), twenty steps out of 7,028.  They sit in the
-- unnamed stretch between the player's hand-out animation and the Distortion
-- World's jumps.  `action()` answers nil for them and the executor skips the
-- step, which is the one honest thing to do with an animation nobody decoded.
-- (All four are decoded now from pokeplatinum's step tables -- 106 / 107 the
-- Distortion World wall walks, 117 its jump, 153 the "!" -- see below.)

local Gen4Movement = {}

Gen4Movement.END = 254
Gen4Movement.BYTES = 4

-- Every direction group in this file runs NORTH, SOUTH, WEST, EAST.
local DIR = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
Gen4Movement.DIR = DIR

-- action -> { kind, dir, n }
--   walk   n tiles in dir              spot   face dir and mark time n frames
--   face   turn to dir                 wait   n frames
--   hide / show / emote / none
local ACTIONS = {}

-- HOW FAST, as a multiplier on the walker's own step duration.
--
-- A movement action names a SPEED as well as a direction, and the port used to
-- drop it -- the comment here said so outright: "the port has one walk speed".
-- The engine has carried `mv.rate` since the Gen 3 work (where dropping it was
-- what made Birch stroll through a rescue written entirely in walk_fast), so
-- nothing needed building; the value simply was not being read off the Gen 4
-- table.
--
-- One step is one tile.  A normal walk crosses it in the walker's own
-- `stepFrames`, so `rate` is that duration scaled: BIGGER IS SLOWER.  The DS
-- ladder is pixels per frame over a 16-pixel tile -- normal 1, fast 2, faster
-- 4, fastest 8, slow 1/2, slower 1/4 -- which inverts to the multipliers
-- below and matches the halving Gen 3 already uses (`Gen3Commands.MOVE_SPEED`
-- is slow 2.0, walk 1.0, fast 0.5, fastest 0.25).
--
-- THE TWO "SLIGHTLY" CLASSES ARE INTERPOLATED, not measured: they sit between
-- normal and fast in the cartridge's own ordering, and nothing in the frame
-- tables has been read to pin them exactly.  Said plainly here rather than
-- left to look like the rest.
local RATE = {
  slower = 4.0, slow = 2.0, normal = 1.0,
  slightlyFast = 0.75, fast = 0.5, slightlyFaster = 0.375,
  -- RUN is FOUR frames a cell, not two: MovementAction_RunNorth_Step0
  -- (pokeplatinum src/unk_020655F4.c) is InitWalk(FX32_CONST(4), 4,
  -- MAP_OBJ_UNK_A0_09) and HGSS's MapObjectMovementCmd088_Step0
  -- (asm/unk_02062108.s) passes 0x4000 x 4 -- the fast walk's pace on the
  -- running animation (Black's 0x58 is 4 frames too, Gen5Movement)
  faster = 0.25, fastest = 0.125, run = 0.5,
}

local function span(first, last, kind, tiles, rate)
  for a = first, last do
    ACTIONS[a] = { kind = kind, dir = DIR[(a - first) % 4], tiles = tiles,
                   rate = rate }
  end
end

span(0, 3, "face")
-- FIVE WALKING SPEEDS, four directions each, and the speed is kept now.  The
-- ids are the cartridge's own order, checked name by name against
-- `generated/movement_actions.txt`: 4 WALK_SLOWER, 8 WALK_SLOW, 12
-- WALK_NORMAL, 16 WALK_FAST, 20 WALK_FASTER, north/south/west/east in each.
span(4, 7, "walk", 1, RATE.slower)
span(8, 11, "walk", 1, RATE.slow)
span(12, 15, "walk", 1, RATE.normal)
span(16, 19, "walk", 1, RATE.fast)
span(20, 23, "walk", 1, RATE.faster)
-- On the spot: the sprite animates without moving, which a cutscene uses as a
-- pause with a facing.  Same five speeds, and the speed decides how long the
-- beat lasts rather than how far anything goes.
span(24, 27, "spot", nil, RATE.slower)
span(28, 31, "spot", nil, RATE.slow)
span(32, 35, "spot", nil, RATE.normal)
span(36, 39, "spot", nil, RATE.fast)
span(40, 43, "spot", nil, RATE.faster)
-- THE JUMPS ARE JUMPS, not walks: read as "walk" they slid the actor along
-- the ground with no hop, so the rival's shove outside Elm's lab (New Bark,
-- scr_seq_0842_T20 _0288: LockDir, two steps back, JumpFarSouth) and every
-- ledge-like scripted leap lost its arc. Frames per cell, field frames,
-- from the shared movement engine (Black's 0x219852C, the same actions --
-- src/import/Gen5Movement.lua): on the spot in 16 (slow) and 8 (fast), the
-- near jump one cell in 8, the far jump two cells at 8 each. `rate` is the
-- step's speed against a normal 8-frame walk, as the walks carry it.
span(44, 47, "hop", nil, 2)    -- jump on the spot, slow (16 frames)
span(48, 51, "hop", nil, 1)    -- jump on the spot, fast (8 frames)
span(52, 55, "jump", 1, 1)     -- jump to the near tile
span(56, 59, "jump", 2, 1)     -- jump two tiles
ACTIONS[60] = { kind = "wait", frames = 1 }
ACTIONS[61] = { kind = "wait", frames = 2 }
ACTIONS[62] = { kind = "wait", frames = 4 }
ACTIONS[63] = { kind = "wait", frames = 8 }
ACTIONS[64] = { kind = "wait", frames = 15 }
ACTIONS[65] = { kind = "wait", frames = 16 }
ACTIONS[66] = { kind = "wait", frames = 32 }
-- WarpOut / WarpIn (pokeplatinum src/unk_020655F4.c MovementAction_WarpOut /
-- _WarpIn; HGSS's are the same two step tables): the sprite's jump offset
-- rises 16 units a field frame until 320, or starts at 320 and falls 16 a
-- frame to 0 -- the drop onto Olivine Lighthouse's ledge, the Distortion
-- World guardians leaving (src/world/Gen4WarpMove.lua)
ACTIONS[67] = { kind = "warp", dir = "out" }
ACTIONS[68] = { kind = "warp", dir = "in" }
ACTIONS[69] = { kind = "hide" }
ACTIONS[70] = { kind = "show" }
-- LockDir / UnlockDir: MAPOBJECTFLAG_UNK7, which MapObject_SetFacingDirection
-- (map_object.c) checks before every turn -- a walk, a face, a mark-time.
-- Read as "none", Mahogany's shop grunt backed off from Dragonite's
-- Hyper Beam (LockDir, WalkFasterEast 2) turned round and walked away.
ACTIONS[71] = { kind = "lock" }   -- lock facing
ACTIONS[72] = { kind = "unlock" } -- unlock facing
-- PauseAnimation / ResumeAnimation: MAP_OBJ_STATUS_PAUSE_ANIMATION on and off
-- (MovementAction_PauseAnimation_Step0), which holds the sprite's frame --
-- the object GLIDES through the walks in between. Platinum's Old Chateau
-- leavers (the twin, the old man), HGSS D39R0101 _021C and scr_seq_0163.
-- The executor sets `sliding`, the hold NPC:pose / Player:pose read.
ACTIONS[73] = { kind = "pauseAnim" }
ACTIONS[74] = { kind = "resumeAnim" }
ACTIONS[75] = { kind = "emote", emote = "exclamation" }
-- 76 WALK_SLIGHTLY_FAST, 80 WALK_SLIGHTLY_FASTER, 84 WALK_FASTEST, 88 RUN.
span(76, 79, "walk", 1, RATE.slightlyFast)
span(80, 83, "walk", 1, RATE.slightlyFaster)
span(84, 87, "walk", 1, RATE.fastest)
span(88, 91, "walk", 1, RATE.run)
-- sideways jumps (Black 0x5C-0x5F, the same actions): one cell in 16
-- frames, and the farther jump three cells at 4 frames each
ACTIONS[92] = { kind = "jump", dir = "left",  tiles = 1, rate = 2 }   -- jump near slow
ACTIONS[93] = { kind = "jump", dir = "right", tiles = 1, rate = 2 }
ACTIONS[94] = { kind = "jump", dir = "left",  tiles = 3, rate = 0.5 } -- jump farther
ACTIONS[95] = { kind = "jump", dir = "right", tiles = 3, rate = 0.5 }
-- 96 WALK_EVER_SO_SLIGHTLY_FAST -- between normal and slightly fast.
span(96, 99, "walk", 1, 0.875)
-- 100..104, the same five step tables in both games (pokeplatinum
-- src/unk_020655F4.c; HGSS MapObjectMovementCmd100..104, asm/unk_02062108.s):
--   100 POKECENTER_NURSE_BOW: the bow pose (anim 9) for 8 frames, then
--       MapObject_TryFace(SOUTH) -- every heal's "We hope to see you again!"
--   101 REVEAL_TRAINER: a disguised trainer springing up -- a hop on the spot
--       on JUMP_HEIGHT_HIGH at two table rows a frame, so 8 frames, and no
--       take-off sound (it is not InitJump)
--   102 PLAYER_GIVE / 104 PLAYER_RECEIVE: anim 0 / 1 held for 21 frames
--       (PlayerGiveReceive_Step1, `++timer < 21`) -- the hand-over at the
--       Pokemon Center counter, which ran in no time at all
--   103 the emote of kind 1: fldeff `saisen_ef`, the "!!" (HGSS loads member
--       0x7D = 125 for it in ov01_022002AC -- the decomp's name
--       EmoteQuestionMark is a misnomer; it is the same "!!" as Platinum's
--       EMOTE_DOUBLE_EXCLAMATION_MARK)
ACTIONS[100] = { kind = "bow", frames = 8, dir = "down" }
ACTIONS[101] = { kind = "hop", rate = 1, silent = true, noLanding = true }
ACTIONS[102] = { kind = "wait", frames = 21 }
ACTIONS[103] = { kind = "emote", emote = "double_exclamation" }
ACTIONS[104] = { kind = "wait", frames = 21 }
-- PLATINUM'S 105..116 AND 121..152: the Distortion World's walks along a
-- wall or a ceiling (sub_02066824 + sub_020668EC, src/unk_020655F4.c): one
-- cell along the world axis `axis` (x east, z south, y up), `frames` frames,
-- the sprite facing `dir`. A move along x or z is a walk in the port's grid;
-- one along y has no cell to change and plays as a beat with the facing.
-- 133..144 are the same along an axis with a low hop (sub_02066F88: 8
-- frames, JUMP_HEIGHT_LOW, SUTYA2 on landing). Scripts use only 106 and 107
-- (Distortion World B2F, Cynthia), the rest are the field's own.
local AXIS_DIR = { x = { "left", "right" }, z = { "up", "down" } }
local FACE = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
local function axisWalk(id, axis, sign, frames, face, kind)
  local dir = AXIS_DIR[axis] and AXIS_DIR[axis][sign > 0 and 2 or 1]
  ACTIONS[id] = { kind = kind or "axis", axis = axis, sign = sign, frames = frames,
                  face = FACE[face], dir = dir, tiles = dir and 1 or nil,
                  rate = frames / 8 }
end
for id, r in pairs({
  [105] = { "y", 1, 8, 2 },  [106] = { "y", -1, 8, 3 }, [107] = { "z", 1, 8, 1 },
  [108] = { "z", -1, 8, 0 }, [109] = { "y", 1, 8, 3 },  [110] = { "y", -1, 8, 2 },
  [111] = { "z", -1, 8, 0 }, [112] = { "z", 1, 8, 1 },  [113] = { "z", 1, 8, 1 },
  [114] = { "z", -1, 8, 0 }, [115] = { "x", -1, 8, 3 }, [116] = { "x", 1, 8, 2 },
  [121] = { "y", 1, 4, 2 },  [122] = { "y", -1, 4, 3 }, [123] = { "z", 1, 4, 1 },
  [124] = { "z", -1, 4, 0 }, [125] = { "y", 1, 4, 3 },  [126] = { "y", -1, 4, 2 },
  [127] = { "z", -1, 4, 0 }, [128] = { "z", 1, 4, 1 },  [129] = { "z", 1, 4, 1 },
  [130] = { "z", -1, 4, 0 }, [131] = { "x", -1, 4, 3 }, [132] = { "x", 1, 4, 2 },
  [145] = { "z", 1, 4, 1 },  [146] = { "z", -1, 4, 0 }, [147] = { "x", -1, 4, 3 },
  [148] = { "x", 1, 4, 2 },  [149] = { "z", 1, 2, 1 },  [150] = { "z", -1, 2, 0 },
  [151] = { "x", -1, 2, 3 }, [152] = { "x", 1, 2, 2 },
}) do axisWalk(id, r[1], r[2], r[3], r[4]) end
for id, r in pairs({
  [133] = { "y", 1, 2 },  [134] = { "y", -1, 3 }, [135] = { "z", 1, 1 },
  [136] = { "z", -1, 0 }, [137] = { "y", 1, 3 },  [138] = { "y", -1, 2 },
  [139] = { "z", -1, 0 }, [140] = { "z", 1, 1 },  [141] = { "z", 1, 1 },
  [142] = { "z", -1, 0 }, [143] = { "x", -1, 3 }, [144] = { "x", 1, 2 },
}) do axisWalk(id, r[1], r[2], 8, r[3], "axisJump") end
-- THE DISTORTION WORLD'S JUMPS, 117..120 (MOVEMENT_ACTION_JUMP_DISTORTION_
-- WORLD_NORTH..EAST): InitJumpCustomSound(dir, FX32_CONST(2), 8 * 3, ...,
-- JUMP_HEIGHT_HIGH, 0xA0, SEQ_NONE) -- THREE cells in 24 frames under one
-- arc, silent at take-off and SUTYA2 on landing (the platforms' own hop is
-- three cells too, Gen4DistPlatforms `hop[1] * 3`). Read as a one-cell walk,
-- Cynthia's leap off B1F and the Giratina room's two leaps covered a third
-- of the distance, on the ground.
span(117, 120, "jump", 3, 1)
for a = 117, 120 do ACTIONS[a].silent = true end
-- 153: the "!" again (MovementAction_153_Step0 is sub_020664A0(mapObj, 0, 1):
-- kind 0, on the anim manager that follows its owner) -- Cheryl noticing
-- the player in Eterna Forest, three sites, skipped as unknown until now
ACTIONS[153] = { kind = "emote", emote = "exclamation" }

-- HEARTGOLD / SOULSILVER STOP AT 112 (gMovementCmdTable, asm/unk_data_
-- 020FCBD8.s, 113 entries), and their 105..112 are not Platinum's: they are
-- the legendary beasts' bounding exits -- MapObjectMovementCmd105..112
-- (asm/unk_020632B0.s), each a chain of LEAPS. sub_020632B0(obj, dx, dy,
-- dz, dir, frames, anim) carries the object (dx, dz) cells, dy height units,
-- straight-line over `frames` frames under 16 units of sine arc
-- (MapObjectMovementCmd108_Step1: GF_SinDeg(180 / frames * i) << 4), facing
-- `dir`, with SEQ_SE_DP_DANSA at take-off when visible. Burned Tower B1F
-- (scr_seq_0024 _0224.._0278: Raikou 105, Entei 106, Suicune 107..110),
-- Cianwood's Suicune (T24 _02F4 111, _0300 112), Route 42 / Ecruteak (112).
-- Each leap is { dx, dy, dz, dir, frames }.
local HGSS = {}
local function leaps(list) return { kind = "leaps", leaps = list } end
HGSS[105] = leaps({ { 0, 1, 5, 1, 15 }, { 4, 0, 0, 3, 12 }, { 0, 0, -5, 0, 15 },
                    { -2, 0, -3, 0, 9 }, { -4, 1, -4, 2, 12 } })
HGSS[106] = leaps({ { 2, 1, 0, 3, 6 }, { -1, 0, 5, 1, 12 }, { -3, 0, 0, 2, 6 },
                    { -3, 0, 0, 2, 9 } })
local L107 = { { 3, 1, -1, 3, 6 }, { 0, 0, 4, 1, 9 }, { -4, 0, 0, 2, 12 },
               { 0, -1, -4, 0, 6 }, { 1, 1, -3, 0, 9 }, { 3, 0, 0, 3, 9 } }
local function with(list, last)
  local out = {}
  for i, v in ipairs(list) do out[i] = v end
  out[#out + 1] = last
  return out
end
HGSS[107] = leaps(with(L107, { 0, 0, 4, 1, 12 }))
HGSS[108] = leaps({ { 2, 1, 5, 1, 9 }, { 1, 0, 5, 1, 12 } })
HGSS[109] = leaps(with(L107, { 0, 0, 5, 1, 12 }))
HGSS[110] = leaps({ { 2, 1, 4, 1, 9 }, { 1, 0, 5, 1, 12 } })
HGSS[111] = leaps({ { 0, 0, 2, 1, 6 }, { 2, 0, 0, 3, 6 }, { 3, 0, 0, 3, 9 },
                    { 0, 0, 2, 1, 6 }, { 0, 0, 2, 1, 6 }, { -3, 0, 0, 2, 9 },
                    { -3, 0, 0, 2, 9 }, { 0, 0, -2, 0, 6 }, { 0, 0, -3, 0, 9 },
                    { 3, 0, 1, 1, 9 } })
HGSS[112] = leaps({ { 4, 0, 0, 3, 9 }, { 4, 0, 0, 3, 9 }, { 4, 0, 0, 3, 9 } })
for id = 0, 104 do HGSS[id] = ACTIONS[id] end
Gen4Movement.HGSS_ACTIONS = HGSS

Gen4Movement.ACTIONS = ACTIONS

-- What one action does, or nil when it is one this port has no name for.
-- Unknown is answered rather than guessed: a movement list with an action
-- nobody decoded should skip that step, not invent a walk.
--
-- `family` picks the table: "hgss" reads HeartGold / SoulSilver's own
-- (HGSS_ACTIONS, which ends at 112 and has the beasts' leaps where Platinum
-- has its wall walks); anything else, Platinum's.
function Gen4Movement.action(id, family)
  local t = family == "hgss" and HGSS or ACTIONS
  return t[tonumber(id) or -1]
end

-- ---------------------------------------------------------------------------

local function u16(data, at)
  local a, b = data:byte(at), data:byte(at + 1)
  if not b then return nil end
  return a + b * 256
end

-- decode(data, at) -> { { action, count }, ... }, or nil plus a reason.
--
-- `at` is ONE-BASED, the way `Gen4Script` counts positions -- its own
-- `entries` refuses a target below 1, which is what says so.
--
-- A list that runs off the end of the member, or past `LIMIT` steps without
-- terminating, is refused rather than truncated: a movement list is read from
-- an offset, and an offset that is wrong produces a plausible-looking list of
-- nonsense.  The longest genuine one in this cartridge is well inside that.
Gen4Movement.LIMIT = 64

function Gen4Movement.decode(data, at)
  if type(data) ~= "string" or type(at) ~= "number" then return nil, "bad arguments" end
  if at < 1 or at + Gen4Movement.BYTES - 1 > #data then return nil, "out of range" end
  local out = {}
  local p = at
  while p + Gen4Movement.BYTES - 1 <= #data do
    local action = u16(data, p)
    local count = u16(data, p + 2)
    if action == nil then return nil, "truncated" end
    if action == Gen4Movement.END then return out end
    if #out >= Gen4Movement.LIMIT then return nil, "runaway" end
    out[#out + 1] = { action = action, count = count }
    p = p + Gen4Movement.BYTES
  end
  return nil, "unterminated"
end

-- WHERE an `applymovement`'s list is, given the decoded instruction and the
-- opcode's width.  The offset is measured from the byte AFTER the instruction,
-- which is `ctx->scriptPtr` at the moment the cartridge reads it, and it is a
-- SIGNED 32-bit displacement -- read unsigned, a backward one becomes four
-- billion and the list is looked for past the end of the file.
function Gen4Movement.addressOf(instruction, size)
  local rel = instruction and instruction.args and instruction.args[2]
  if not (rel and size) then return nil end
  if rel >= 0x80000000 then rel = rel - 0x100000000 end
  return instruction.at + size + rel
end

-- The object id an `applymovement` names.  0xFF is the player
-- (`LOCALID_PLAYER`, constants/scrcmd.h); everything else is an object
-- event's own `localID`.
Gen4Movement.PLAYER = 0xFF

-- ...AND TWO MORE THAT ARE NOT LOCAL IDS EITHER, out of the same three-line
-- block of constants/scrcmd.h:
--
--     #define LOCALID_CAMERA   0xF1
--     #define LOCALID_FOLLOWER 0xF2
--     #define LOCALID_PLAYER   0xFF
--
-- `GetLocalMapObjByIndex` (src/scrcmd.c) branches on all three before it
-- searches the object array at all: 0xF2 resolves to whichever live object is
-- wearing MOVEMENT_TYPE_FOLLOW_PLAYER and 0xF1 to the script camera.  Only
-- 0xFF was known here, so a movement applied to the follower searched for an
-- object with local id 242, found none, and dropped the movement -- with the
-- `waitmovement` behind it holding the input gate for ever.  That is the
-- whole of Verity Lakefront's arrival scene.
Gen4Movement.CAMERA = 0xF1
Gen4Movement.FOLLOWER = 0xF2

return Gen4Movement
