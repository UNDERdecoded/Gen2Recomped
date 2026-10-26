-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MAP OBJECTS' MOVEMENT TYPES -- PLATINUM, HEARTGOLD / SOULSILVER, AND
-- BLACK / WHITE (whose table is the same table; see Gen5MovementTypes).
--
-- Every object event carries a movement type (ObjectEvent.movementType, the
-- u16 at +4 of the 32-byte record, Gen4Events.objectEvent) and a wander box
-- (movementRangeX / movementRangeZ, s16 at +20 / +22). Nothing in the engine
-- read the type, so every Sinnoh and Johto object stood still facing its
-- template direction: the wanderers never wandered (Goldenrod's warehouse
-- worker never reached y 15, so FLAG_097's west crates could not move), the
-- look-around and spinning guards never turned, and a LOOK_NORTH / LOOK_EAST
-- object kept the template facing even where its type names another.
--
-- ===========================================================================
-- READ FROM CODE
-- ===========================================================================
--
-- Platinum (pret/pokeplatinum): the type table is Unk_020EE3A8
-- (src/unk_020EDBAC.c, 68 rows of { id, init, move, delete, return }); the
-- callbacks are src/unk_0206450C.c; the collision bits src/map_object_move.c
-- (sub_02063E18 / MapObject_IsOutOfRange / sub_02063F00); the per-frame driver
-- MapObject_Move; the pause ScrCmd_LockAll / ScrCmd_LockLastTalked
-- (src/scrcmd.c) and FieldInput_Process (overlay005/field_control.c).
--
-- HeartGold / SoulSilver (pret/pokeheartgold): the table is _020FD1F4
-- (asm/unk_data_020FCBD8.s, 57 rows), the callbacks asm/unk_02061284.s
-- (sub_02061284 look, sub_020613D0 / sub_020613F8 wander, sub_02061648 fixed,
-- sub_020616C0 rotate, sub_0206197C back-and-forth, sub_02061B1C..DF0 routes)
-- and its rodata (the timer list _020FD7B8, the direction lists _020FD838,
-- the running-look list _020FD800). Row for row the same callbacks with the
-- same arguments as Platinum's 0..54 (47, the berry soil, is NULL there);
-- 55 / 56 are the walking Pokemon's own (HgssFollowMon), and routes 37..44
-- run the 21..36 callback (no trainer-type-10 branch).
--
--   type  name (pokeplatinum generated/movement_types.txt)     kind
--   ----  ---------------------------------------------------  -----------
--    0    NONE                                                 (not here)
--    1    PLAYER                                               (not here)
--    2    LOOK_AROUND                                          look  list 0
--    3    WANDER_AROUND                                        wander 11
--    4    WANDER_NORTH_AND_SOUTH                               wander 12
--    5    WANDER_WEST_AND_EAST                                 wander 13
--    6-13 LOOK_{NW,NE,SW,SE,NSW,NSE,NWE,SWE}                   look  1..8
--   14-17 LOOK_NORTH / SOUTH / WEST / EAST                     fixed 0..3
--   18    ROTATE_COUNTERCLOCKWISE  (up, left, down, right)     rotate
--   19    ROTATE_CLOCKWISE         (up, right, down, left)     rotate
--   20    WALK_BACK_AND_FORTH                                  backforth
--   21-44 WALK_<four directions>                               route 14..37
--   45    LOOK_NORTH_AND_SOUTH                                 look  9
--   46    LOOK_WEST_AND_EAST                                   look  10
--   47    BERRY_SOIL (Platinum; NULL on HGSS)                  (Gen4BerryPatches)
--   48    FOLLOW_PLAYER                                        (Gen4Follower)
--   49    VS_SEEKER_SPIN                                       (Gen4VsSeeker)
--   50    FOLLOW_PARTNER_TRAINER (template objects)            partner
--         (a script's SetMovementType 50 is Gen4Follower's)
--   51-54 DISGUISE_SNOW / SAND / ROCK / GRASS                  (buried trainers)
--   55-66 Platinum's unnamed gym types; HGSS 55/56 = walking   (not here)
--         Pokemon (HgssFollowMon)
--   67    WANDER west/east, only the RANGE stops it            wander 13 mode 2
--         (Platinum + BW; no object in any of the three uses it)
--
-- THE RULES, each from the callback named:
--
--   * TIMERS. One list, { 16, 32, 48, 64 } field frames (Unk_020EEA88 /
--     _020FD7B8 / BW 0x21D4FA4), drawn `list[LCRNG_Next() % 4]`
--     (sub_0206530C). LCRNG_Next is the field's global linear congruential
--     generator (x = x * 0x41C64E6D + 0x6073, result x >> 16); the same
--     generator draws the direction, `list[LCRNG_Next() % #list]`
--     (sub_02065330).
--   * LOOK (sub_020645C0): the timer counts down every frame and at zero is
--     redrawn and the object turns to a random direction of its list (the
--     one it already faces included). No step, no face action in between.
--   * WANDER (sub_02064690), a five-state machine: face where it already
--     faces (one frame) -> draw the timer -> count it down -> draw a direction
--     from the list, TURN TO IT, and only then test the step -> if anything
--     blocks it (bit set in sub_02063EBC) go back to the start facing the new
--     way, else walk one tile at WALK_NORMAL (8 field frames) -> the step
--     lands -> start. So a wanderer always turns, walks whenever it can, and
--     waits 16..64 frames (+1) between decisions. Type 67 walks unless the
--     RANGE bit is set (mode 2): terrain and objects do not stop it.
--   * RANGE (MapObject_IsOutOfRange), PER AXIS, measured from the object's
--     INITIAL cell (xInitial / zInitial, the template's): an axis whose range
--     is -1 is unlimited; any other value r allows initial - r .. initial + r.
--     So range 0 pins that axis -- the opposite of Gen 3, where 0 means
--     "unlimited" -- and a wanderer with 0 / 0 only turns on the spot.
--   * WHAT BLOCKS A STEP (sub_02063E18): the range; the terrain
--     (TerrainCollisionManager_WillMapObjectCollide -- a wall, a height change,
--     the null tile past the map's edge, the tile's own directional blocks);
--     and any other ACTIVE object standing on the cell or LEAVING it
--     (sub_02063F00 tests both the current and the previous cell) within two
--     half-tile heights -- the player is a map object and counts. Objects
--     carrying status 18 are skipped, which on HGSS is the walking Pokemon
--     (follow_mon.c sets it with MapObject_ClearFlag18(..., FALSE)); here that
--     is HgssFollowMon's `passable`.
--   * FIXED LOOK_* (sub_02064918): face the type's direction ONCE, on the
--     first frame the type runs, and never again -- a script that turns the
--     object later (talking to it) leaves it turned.
--   * ROTATE (sub_020649A8): face, then hold 24 frames, then the next
--     direction round the ring -- counter-clockwise up, left, down, right;
--     clockwise up, right, down, left.
--   * BACK AND FORTH (sub_02064C48): walk the template direction until the
--     next step would leave the box, then walk back; at the initial cell turn
--     round again. A step blocked by anything else is walked ON THE SPOT
--     (WALK_ON_SPOT_NORMAL, 8 frames) and tried again. No timer.
--   * ROUTES 21..44 (sub_02064EC8 / sub_020650DC): the four directions of
--     the list in turn -- leg 0 and leg 1 end when the next step would leave
--     the box, leg 2 when the object is back on its initial column (axis 0)
--     or row (axis 1), leg 3 when it is back on its initial cell. Blocked
--     steps are walked on the spot, as above. No timer. The lists are the
--     cartridge's, not the names: list 0x13 (type 26, "NORTH_WEST_EAST_SOUTH")
--     is { W, E, S, N } on all three cartridges.
--   * SPINNING TRAINERS WHO WALK (sub_0206553C, trainer type 7 / 8): before
--     every step of 20..44 the object turns one notch round the ring (type 7
--     counter-clockwise, 8 clockwise) and walks with its facing locked.
--   * PARTNER (sub_02069E1C, unk_02069BE0.c): the other object on the map
--     with the same trainer id is the leader; while the follower is not on
--     the leader's PREVIOUS cell it steps towards that cell
--     (GetDirectionBetweenPoints: x first, then z) unless the step would land
--     on the leader itself -- WALK_NORMAL, with no collision test at all.
--     Route 209's Beauty and Guitarist walk route 43 this way.
--   * RUNNING (sub_0206537C / sub_02065448): a look / rotate type
--     (_020FD800: 2, 6..13, 45, 46, 18, 19) on a trainer of type 1 or 2 turns
--     straight to a RUNNING player who is inside the square of its sight
--     range (data[0]) and on its height layer, choosing the side its list
--     allows.
--   * PAUSE (MapObject_Move): a paused object runs no type at all.
--     ScrCmd_LockAll / LockLastTalked pause every object
--     (MapObjectMan_PauseAllMovement), ReleaseAll unpauses; spotting a
--     trainer pauses all of them (FieldInput_Process); a battle tears the
--     field down. A movement action (ApplyMovement, status 4) replaces the
--     type while it runs.
--   * LOCK_DIR (MapObject_TryFace): a locked object does not turn; the
--     script's LockDir is `g4DirLocked` (Gen4Commands / Gen4Movement 71).
--   * TRAINERS' SIGHT follows the CURRENT facing (GetTrainerDistToPlayer reads
--     MapObject_GetFacingDir), and FieldInput_Process asks every frame the
--     player is free -- so a turning or walking trainer spots a player who is
--     standing still. OverworldController.checkTrainerSight already reads
--     `npc.facing` every free frame, so turning here is all it needs.
--
-- ===========================================================================
-- STAND-INS
-- ===========================================================================
--
--   * One field frame is two engine ticks (Gen4MoveExec.TICKS_PER_FRAME): the
--     machine advances on every other tick, and the engine's 16-tick step is
--     WALK_NORMAL's 8 frames.
--   * The LCRNG is the cartridge's formula on a state of its own, seeded once
--     from love.math.random: the cartridge's global state is advanced by
--     everything else on the field, which this engine does not reproduce.
--   * A pause lets a step that is under way land (the engine has no half-tile
--     resting place); the cartridge freezes it where it is.
--   * "Paused" is: a foreground script is running, a trainer is engaging, a
--     map transition is under way, the object is talked to (`frozen`) or is
--     walking a scripted movement (queued in `scriptMoves`). Gen 4's scripts
--     open with LockAll / LockLastTalked almost without exception, so "a
--     script runs" is "the field is locked".
--   * The running-look's height layer (sub_020630DC) is read as the two
--     bodies standing within one step height of each other (Gen4HeightRule).
--   * A moving trainer is not asked to spot (checkTrainerSight skips
--     `npc.moving`, unchanged): the cartridge asks it from the step's
--     destination; here it asks again the frame the step lands.
--   * Trainer type 10 on routes 37..44 (Platinum / BW only, sub_02065124):
--     hops on the spot instead of stepping while the player is in its sight
--     line. The hop's length (JUMP_ON_SPOT_FAST, 8 frames) is assumed.

local Collision = require("src.world.Collision")

local M = {}

M.TICKS_PER_FRAME = 2

local DIR = { [0] = "up", [1] = "down", [2] = "left", [3] = "right" }
local IDX = { up = 0, down = 1, left = 2, right = 3 }
local OPP = { [0] = 1, [1] = 0, [2] = 3, [3] = 2 }

-- Unk_020EEA88 / _020FD7B8: the one timer list every timed type draws from
M.TIMERS = { 16, 32, 48, 64 }
-- sub_02064A1C / sub_02064B5C: the rotate hold
M.ROTATE_HOLD = 24

-- Unk_020EEB08 / _020FD838 / BW 0x21D50F8: direction lists by id (0 up,
-- 1 down, 2 left, 3 right), identical on all three cartridges
M.LISTS = {
  [0] = { 0, 1, 2, 3 }, [1] = { 0, 2 }, [2] = { 0, 3 }, [3] = { 1, 2 },
  [4] = { 1, 3 }, [5] = { 0, 1, 2 }, [6] = { 0, 1, 3 }, [7] = { 0, 2, 3 },
  [8] = { 1, 2, 3 }, [9] = { 0, 1 }, [10] = { 2, 3 }, [11] = { 0, 1, 2, 3 },
  [12] = { 0, 1 }, [13] = { 2, 3 },
  [14] = { 0, 3, 2, 1 }, [15] = { 3, 2, 1, 0 }, [16] = { 1, 0, 3, 2 },
  [17] = { 2, 1, 0, 3 }, [18] = { 2, 3, 1, 0 }, [19] = { 2, 3, 1, 0 },
  [20] = { 1, 0, 2, 3 }, [21] = { 3, 1, 0, 2 }, [22] = { 2, 0, 1, 3 },
  [23] = { 0, 1, 3, 2 }, [24] = { 3, 2, 0, 1 }, [25] = { 1, 3, 2, 0 },
  [26] = { 3, 0, 1, 2 }, [27] = { 0, 1, 2, 3 }, [28] = { 2, 3, 0, 1 },
  [29] = { 1, 2, 3, 0 }, [30] = { 0, 2, 1, 3 }, [31] = { 1, 3, 0, 2 },
  [32] = { 2, 1, 3, 0 }, [33] = { 3, 0, 2, 1 }, [34] = { 0, 3, 1, 2 },
  [35] = { 1, 2, 0, 3 }, [36] = { 2, 0, 3, 1 }, [37] = { 3, 1, 2, 0 },
  [38] = { 0, 1, 2, 3 },
}

-- Unk_020EEAB0 / _020FD7E0: the rings (index 0 counter-clockwise, 1 clockwise)
M.RINGS = { [0] = { 0, 2, 1, 3 }, [1] = { 0, 3, 1, 2 } }

-- Unk_020EEAD0 / _020FD800: the types that turn to a running player
M.RUN_LOOK = { [2] = true, [6] = true, [7] = true, [8] = true, [9] = true,
  [10] = true, [11] = true, [12] = true, [13] = true, [45] = true,
  [46] = true, [18] = true, [19] = true }

-- THE TABLE, keyed by the cartridge's type id. `list` is the direction list
-- the init callback passes; `axis` / `list` for a route are its (param2,
-- param3); `mode` is the wander's third argument.
M.TYPES = {
  [2] = { kind = "look", list = 0 },
  [3] = { kind = "wander", list = 11, mode = 0 },
  [4] = { kind = "wander", list = 12, mode = 0 },
  [5] = { kind = "wander", list = 13, mode = 0 },
  [14] = { kind = "fixed", dir = 0 }, [15] = { kind = "fixed", dir = 1 },
  [16] = { kind = "fixed", dir = 2 }, [17] = { kind = "fixed", dir = 3 },
  [18] = { kind = "rotate", ring = 0 }, [19] = { kind = "rotate", ring = 1 },
  [20] = { kind = "backforth" },
  [45] = { kind = "look", list = 9 }, [46] = { kind = "look", list = 10 },
  [50] = { kind = "partner" },
  [67] = { kind = "wander", list = 13, mode = 2, family = { platinum = true, bw = true } },
}
for t = 6, 13 do M.TYPES[t] = { kind = "look", list = t - 5 } end
-- sub_02064DC8..EB8 / sub_0206505C..CC: (axis, list) per type
local ROUTE_AXIS = { 0, 0, 1, 1, 0, 0, 1, 1, 1, 1, 0, 0, 1, 1, 0, 0,   -- 21..36
                     1, 1, 0, 0, 1, 1, 0, 0 }                         -- 37..44
for t = 21, 44 do
  M.TYPES[t] = { kind = "route", axis = ROUTE_AXIS[t - 20], list = t - 7,
                 late = t >= 37 }
end

-- ---------------------------------------------------------------------------
-- the generator
-- ---------------------------------------------------------------------------
local seed
local function mul32(a, b)
  -- (a * b) mod 2^32 without leaving the doubles' exact range
  local alo, ahi = a % 65536, math.floor(a / 65536)
  local blo, bhi = b % 65536, math.floor(b / 65536)
  local mid = (ahi * blo + alo * bhi) % 65536
  return (mid * 65536 + alo * blo) % 4294967296
end
function M.lcrng()
  if not seed then
    seed = (love and love.math and love.math.random(0, 4294967295)) or os.time()
  end
  seed = (mul32(seed, 0x41C64E6D) + 0x6073) % 4294967296
  return math.floor(seed / 65536)
end
function M.setSeed(s) seed = s and (s % 4294967296) or nil end
local function pick(list) return list[(M.lcrng() % #list) + 1] end

-- ---------------------------------------------------------------------------
-- the frame's context (OverworldController hands it over before the NPCs)
-- ---------------------------------------------------------------------------
local frame = nil

function M.beginFrame(ow)
  local claimed = nil
  for _, mv in ipairs(ow.scriptMoves or {}) do
    if mv.entity then claimed = claimed or {} ; claimed[mv.entity] = true end
  end
  local runner = ow.runner
  frame = {
    ow = ow,
    player = ow.player,
    claimed = claimed,
    paused = (runner and runner.isRunning and runner:isRunning()) or ow.engaging
             or ow.transitioning or false,
  }
end

-- (for probes) the context the last beginFrame built
function M.frameState() return frame end

-- Private checkpoint lease: frame contains live objects and never enters data.
function M._checkpointSeed() return seed end
function M._checkpointState() return { seed=seed, frame=frame } end
function M._checkpointReset(value) seed,frame=value,nil end
function M._checkpointRollback(token) seed,frame=token.seed,token.frame end


-- ---------------------------------------------------------------------------
-- which objects run here
-- ---------------------------------------------------------------------------
local function familyOf()
  local GV = require("src.core.GameVersion")
  local gen = GV.generation()
  if gen == 5 then return "bw" end
  if gen ~= 4 then return nil end
  return GV.family() == "hgss" and "hgss" or "platinum"
end

-- the row for a type on this cartridge, or nil (stands as it spawned)
function M.row(typeId, family)
  family = family or familyOf()
  if not family then return nil end
  if family == "bw" then
    local B = require("src.world.Gen5MovementTypes")
    typeId = B.gen4Row(typeId)
    if not typeId then return nil end
  end
  local r = M.TYPES[tonumber(typeId) or -1]
  if not r then return nil end
  if r.family and not r.family[family] then return nil end
  return r
end

local function rangeOf(v)
  v = tonumber(v)
  if v == nil then return 0 end
  if v == 65535 or v < 0 then return -1 end
  return v
end

-- NPC.new's hook: the state this object's type runs on, or nil
function M.attach(npc, def)
  if not (def and def.movementType ~= nil and def.direction ~= nil) then return nil end
  if def.rail or def.gen5Blocker or def.gen5Gimmick then return nil end
  local family = familyOf()
  local row = M.row(def.movementType, family)
  if not row then return nil end
  local rx, ry = def.movementRangeX, def.movementRangeY
  if family == "bw" then
    rx, ry = require("src.world.Gen5MovementTypes").ranges(def)
  end
  return {
    type = tonumber(def.movementType), row = row, family = family,
    state = 0, timer = 0, sub = 0, counter = 0,
    originX = def.x, originY = def.y,
    rangeX = rangeOf(rx), rangeY = rangeOf(ry),
    initialDir = tonumber(def.direction) or 1,
    trainerType = tonumber(def.trainerType) or 0,
  }
end

-- MapObject_SwitchMovementType: a new type on the live object, from its
-- first state; the initial cell is the object's own and stays
function M.switch(npc, typeId)
  if not npc then return end
  local probe = setmetatable({ movementType = tonumber(typeId) }, { __index = npc.def or {} })
  local st = M.attach(npc, probe)
  if st and npc.g4Move then st.originX, st.originY = npc.g4Move.originX, npc.g4Move.originY end
  npc.g4Move = st
end

-- ---------------------------------------------------------------------------
-- the pieces every type shares
-- ---------------------------------------------------------------------------
local function tryFace(npc, d)
  if npc.g4DirLocked then return end
  npc.facing = DIR[d] or npc.facing
end

local function outOfRange(st, x, y)
  if st.rangeX ~= -1 and math.abs(x - st.originX) > st.rangeX then return true end
  if st.rangeY ~= -1 and math.abs(y - st.originY) > st.rangeY then return true end
  return false
end

-- sub_02063EBC: 0 when the step is free; bit 1 the range, bit 2 anything else
local function collision(st, npc, map, entities, d)
  local tx, ty = Collision.target(npc.cellX, npc.cellY, DIR[d])
  local bits = 0
  if outOfRange(st, tx, ty) then bits = bits + 1 end
  if not Collision.canMove(map, entities, npc, DIR[d]) then bits = bits + 2 end
  return bits, tx, ty
end

local function walk(npc, d, tx, ty, keepFacing)
  if not keepFacing then tryFace(npc, d) end
  npc.targetX, npc.targetY = tx, ty
  npc.moving, npc.progress = true, 0
end

-- WALK_ON_SPOT_NORMAL: the walk cycle, no translation, one step's length
local function walkOnSpot(npc, d, keepFacing)
  if not keepFacing then tryFace(npc, d) end
  npc.moving, npc.marching, npc.progress = true, true, 0
end

-- GetDirectionBetweenPoints (map_object_move.c): x decides first
function M.directionBetween(x1, y1, x2, y2)
  if x1 > x2 then return 2 end
  if x1 < x2 then return 3 end
  if y1 > y2 then return 0 end
  return 1
end

-- sub_0206537C: the direction to a running player this object may turn to
local function runningPlayer(st, npc, map)
  local tt = st.trainerType
  if tt ~= 1 and tt ~= 2 then return nil end
  local p = frame and frame.player
  if not (p and p.running and p.moving) then return nil end
  if not M.RUN_LOOK[st.type] then return nil end
  local r = tonumber(npc.def and npc.def.sightRange) or 0
  if math.abs(p.cellX - npc.cellX) > r or math.abs(p.cellY - npc.cellY) > r then return nil end
  local HR = require("src.world.Gen4HeightRule")
  if HR.applies and HR.applies(map) then
    local a, b = HR.standingY(map, npc), HR.standingY(map, p)
    if a and b and math.abs(a - b) >= (HR.MAX_STEP or 1) then return nil end
  end
  -- GetDirectionBetweenPoints, then sub_02065448's choice among the list
  local dx, dy = p.cellX - npc.cellX, p.cellY - npc.cellY
  if dx == 0 and dy == 0 then return nil end
  local h = dx < 0 and 2 or (dx > 0 and 3 or nil)
  local v = dy < 0 and 0 or (dy > 0 and 1 or nil)
  local main = M.directionBetween(npc.cellX, npc.cellY, p.cellX, p.cellY)
  local list = M.LISTS[st.row.list or 38]
  if #list == 1 then return nil end
  for _, d in ipairs(list) do if d == main then return d end end
  for _, d in ipairs(list) do
    if (h and d == h) or (v and d == v) then return d end
  end
  return nil
end

-- the spinning trainer's notch before a step (sub_02065568); returns true
-- when the walk must keep that facing
local function spinNotch(st, npc)
  if st.trainerType ~= 7 and st.trainerType ~= 8 then return false end
  local ring = M.RINGS[st.trainerType == 7 and 0 or 1]
  local cur = IDX[npc.facing] or 1
  local at = 1
  for i, d in ipairs(ring) do if d == cur then at = i end end
  tryFace(npc, ring[(at % 4) + 1])
  return true
end

-- ---------------------------------------------------------------------------
-- the kinds
-- ---------------------------------------------------------------------------
local K = {}

function K.look(st, npc, map)
  if not st.started then
    st.started = true
    st.timer = pick(M.TIMERS)
  end
  local run = runningPlayer(st, npc, map)
  if run then tryFace(npc, run) return end
  st.timer = st.timer - 1
  if st.timer <= 0 then
    st.timer = pick(M.TIMERS)
    tryFace(npc, pick(M.LISTS[st.row.list]))
  end
end

function K.fixed(st, npc)
  if st.done then return end
  st.done = true
  tryFace(npc, st.row.dir)
end

function K.wander(st, npc, map, entities)
  if st.state == 0 then
    -- the face action towards where it already faces: one frame
    st.state = 1
    return
  end
  if st.state == 1 then
    st.timer = pick(M.TIMERS)
    st.state = 2
  end
  if st.state == 2 then
    st.timer = st.timer - 1
    if st.timer > 0 then return end
    st.state = 3
  end
  -- 3: turn, then try the step
  local d = pick(M.LISTS[st.row.list])
  tryFace(npc, d)
  local bits, tx, ty = collision(st, npc, map, entities, d)
  if bits ~= 0 then
    if st.row.mode ~= 2 or bits % 2 == 1 then st.state = 0 return end
  end
  walk(npc, d, tx, ty)
  st.state = 0   -- 4 -> 0 once the step lands (NPC:update owns the step)
end

function K.rotate(st, npc, map)
  for _ = 1, 6 do
    if st.state == 0 then
      -- the face action (it completes the frame it is set), then the hold
      tryFace(npc, runningPlayer(st, npc, map) or IDX[npc.facing] or 1)
      st.counter, st.state = 0, 2
    elseif st.state == 2 then
      if st.counter > 0 and runningPlayer(st, npc, map) then
        st.state = 0
      else
        st.counter = st.counter + 1
        if st.counter < M.ROTATE_HOLD then return end
        st.state = 3
      end
    else
      local ring = M.RINGS[st.row.ring]
      local cur = IDX[npc.facing] or 1
      local at = 1
      for i, d in ipairs(ring) do if d == cur then at = i end end
      tryFace(npc, ring[(at % 4) + 1])
      st.state = 0
    end
  end
end

function K.backforth(st, npc, map, entities)
  -- state 0: the moving direction is the template's, or its opposite while
  -- walking back
  local moving = st.back and OPP[st.initialDir] or st.initialDir
  local spin = st.trainerType == 7 or st.trainerType == 8
  if not spin then tryFace(npc, moving) end
  -- state 1
  if st.back and npc.cellX == st.originX and npc.cellY == st.originY then
    moving = OPP[moving]
    if not spin then tryFace(npc, moving) end
    st.back = false
  end
  local bits, tx, ty = collision(st, npc, map, entities, moving)
  if bits % 2 == 1 then
    st.back = true
    moving = OPP[moving]
    bits, tx, ty = collision(st, npc, map, entities, moving)
  end
  local keep = spinNotch(st, npc)
  if bits ~= 0 then walkOnSpot(npc, moving, keep) else walk(npc, moving, tx, ty, keep) end
end

function K.route(st, npc, map, entities)
  st.leg = st.leg or 0
  local axisAtStart = (st.row.axis == 0) and (npc.cellX == st.originX)
                      or (st.row.axis == 1 and npc.cellY == st.originY)
  if st.leg == 2 and axisAtStart then st.leg = 3 end
  if st.leg == 3 and npc.cellX == st.originX and npc.cellY == st.originY then st.leg = 0 end
  -- trainer type 10 (Platinum / BW's late routes): hop while the player is
  -- in its sight line
  if st.row.late and st.trainerType == 10 and st.family ~= "hgss" then
    local p = frame and frame.player
    local d = IDX[npc.facing] or 1
    local r = tonumber(npc.def and npc.def.sightRange) or 0
    if p and r > 0 then
      local dx, dy = p.cellX - npc.cellX, p.cellY - npc.cellY
      local along = (d == 0 and dx == 0 and -dy) or (d == 1 and dx == 0 and dy)
                    or (d == 2 and dy == 0 and -dx) or (d == 3 and dy == 0 and dx) or 0
      if along >= 1 and along <= r
         and Collision.sightPathClear(map, entities, npc, DIR[d], along) then
        npc.hopFrames, npc.hopTotal = 8 * M.TICKS_PER_FRAME, 8 * M.TICKS_PER_FRAME
        walkOnSpot(npc, d, true)
        return
      end
    end
  end
  local list = M.LISTS[st.row.list]
  local d = list[(st.leg % 4) + 1]
  local spin = st.trainerType == 7 or st.trainerType == 8
  if not spin then tryFace(npc, d) end
  local bits, tx, ty = collision(st, npc, map, entities, d)
  if bits % 2 == 1 then
    st.leg = (st.leg + 1) % 4
    d = list[(st.leg % 4) + 1]
    if not spin then tryFace(npc, d) end
    bits, tx, ty = collision(st, npc, map, entities, d)
  end
  local keep = spinNotch(st, npc)
  if bits ~= 0 then walkOnSpot(npc, d, keep) else walk(npc, d, tx, ty, keep) end
end

-- the leader's cell as the cartridge holds it: a step under way already
-- stands on its destination (MapObject_UpdateCoords at the step's start)
local function cartCell(e)
  if e.moving and not e.marching and e.targetX then return e.targetX, e.targetY end
  return e.cellX, e.cellY
end

function K.partner(st, npc, map)
  local f = frame
  local leader = st.leader
  if not (leader and not leader.hidden) then
    leader = nil
    local id = type(npc.def and npc.def.trainer) == "table" and npc.def.trainer.id
    for _, o in ipairs((f and f.ow and f.ow.npcs) or {}) do
      if o ~= npc and not o.hidden and type(o.def and o.def.trainer) == "table"
         and o.def.trainer.id == id then leader = o break end
    end
    st.leader = leader
    if not leader then return end
    st.curX, st.curY = cartCell(leader)
    st.prevX, st.prevY = leader.cellX, leader.cellY
  end
  -- the leader's previous cell, kept by watching it
  local lx, ly = cartCell(leader)
  if lx ~= st.curX or ly ~= st.curY then
    st.prevX, st.prevY, st.curX, st.curY = st.curX, st.curY, lx, ly
  end
  if npc.cellX == st.prevX and npc.cellY == st.prevY then return end
  if npc.cellX == lx and npc.cellY == ly then return end
  local d = M.directionBetween(npc.cellX, npc.cellY, st.prevX, st.prevY)
  local tx, ty = Collision.target(npc.cellX, npc.cellY, DIR[d])
  if tx == lx and ty == ly then return end
  walk(npc, d, tx, ty)
end

-- ---------------------------------------------------------------------------
-- NPC:update's hook. Called only when the object is standing (NPC:update
-- lands a step first). Returns true: the type owns this object's idle frame.
-- ---------------------------------------------------------------------------
function M.update(npc, map, entities)
  local st = npc.g4Move
  if not st then return false end
  -- the Gen 4 partner (Gen4Follower) walks this object while it follows
  if npc.gen4Follower then return false end
  if npc.hidden and not npc.buried then return true end
  local f = frame
  if f and (f.paused or (f.claimed and f.claimed[npc])) then return true end
  -- one field frame every TICKS_PER_FRAME engine ticks
  st.sub = (st.sub + 1) % M.TICKS_PER_FRAME
  if st.sub ~= 0 then return true end
  local fn = K[st.row.kind]
  if fn then fn(st, npc, map, entities) end
  return true
end

return M
