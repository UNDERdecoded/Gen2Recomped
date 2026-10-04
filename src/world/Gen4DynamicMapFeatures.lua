-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PERSISTED MAP FEATURES -- one save slot, eleven tenants, and the var
-- that was not a boolean.
--
-- This was the biggest remaining subject in the declined census: 53 ranked
-- sites over twelve stub rows, which the ranking called "nine separate
-- implementations" and therefore the most expensive thing left. Measuring it
-- says both halves of that were wrong.
--
-- IT IS NOT NINE IMPLEMENTATIONS, IT IS ONE SLOT. The cartridge keeps exactly
-- `PersistedMapFeatures { int id; u8 buffer[32]; }` in the misc save block.
-- One id says which feature the save is currently holding state for, and the
-- 32 bytes are reinterpreted per feature -- `PersistedMapFeatures_GetBuffer`
-- GF_ASSERTs that the id you ask for is the id that is there. So the nine
-- `initpersistedmapfeaturesfor*` rows are nine CONSTRUCTORS over one union,
-- not nine systems, and the thing to build first is the slot.
--
-- (The union is exactly big enough and no bigger: `DistWorldPersistedData` is
-- `u32 valid:1 + hiddenGhostPropGroups:24 + currentFloatingPlatformIndex:4 +
-- padding:3` -- 4 bytes -- plus four u16, a u32 and `u8 dummy10[16]`, which is
-- 4 + 8 + 4 + 16 = 32. `PERSISTED_MAP_FEATURES_BUFFER_SIZE` is 32. The
-- largest tenant fills the slot to the byte, which is what says the slot was
-- sized FOR these structures rather than rounded up.)
--
-- AND THE CENSUS UNDER-COUNTED THE SUBJECT BY A THIRD, because of how the
-- census works. Walking the cartridge for this family finds 82 sites across
-- nineteen commands, and 24 of them -- six commands -- had NO LOWERING AT ALL:
--
--     setplayerheightcalculationenabled           12   unlowered (all in member 497)
--     checkgreatmarshtramlocation                  6   unlowered
--     movegreatmarshtram                           2   unlowered
--     movehearthomegymdplift                       2   unlowered
--     initgreatmarshtram                           1   unlowered
--     initpersistedmapfeaturesforvilla             1   unlowered
--
-- The census ranks DECLARED stubs: it reads the subject prose out of
-- `g4_noop` / `g4_no_feature` rows. A command with no lowering emits no row
-- and names no subject, so it is invisible to the ranking -- the tool that
-- exists to stop a subject hiding has a blind spot shaped exactly like the
-- worst case. 53 was the lowered part of 82.
--
-- WHICH MATTERS BECAUSE ONE OF THE SIX IS A LIE, not an absence.
-- `checkgreatmarshtramlocation <location>, <destVar>` is the Great Marsh
-- tram's own test, and every one of its six sites reads:
--
--     checkgreatmarshtramlocation 0, 0x8004
--     setvarfromvalue             0x8005, 0
--     comparevartovalue           0x8004, 6        <-- SIX
--     callif                      1, +0x464        --> movegreatmarshtram
--
-- `GREAT_MARSH_TRAM_AT_LOCATION` is **5** and `NOT_AT_LOCATION` is **6**.
-- They are not 1 and 0, and the script compares against the literal 6. An
-- unlowered command leaves 0x8004 holding whatever the last script put there,
-- so the compare is against stale data: the branch that fetches the tram
-- fires or does not fire by accident. A port that "obviously" wrote a boolean
-- here would have been wrong at all six sites in the same direction -- the
-- tram would never be called -- and the symptom would be a player standing at
-- a stop that never answers.
--
-- WHAT THIS FILE IS AND IS NOT.  It is the slot, the eleven ids, the nine
-- constructors with the cartridge's own initial buffers, and the readers and
-- writers the SCRIPTS use. It is NOT the collision resolvers; see
-- `COLLISION_IS_A_HEIGHT_PROBLEM` below, which is the measurement that says
-- why they cannot be bolted on and what has to exist first.

local Gen4DynamicMapFeatures = {}

-- ---------------------------------------------------------------------------
-- The ids -- enum DynamicMapFeatureID, constants/field/dynamic_map_features.h
-- ---------------------------------------------------------------------------

Gen4DynamicMapFeatures.NONE               = 0
Gen4DynamicMapFeatures.PASTORIA_GYM       = 1
Gen4DynamicMapFeatures.HEARTHOME_GYM      = 2
Gen4DynamicMapFeatures.CANALAVE_GYM       = 3
Gen4DynamicMapFeatures.VEILSTONE_GYM      = 4
Gen4DynamicMapFeatures.SUNYSHORE_GYM      = 5
Gen4DynamicMapFeatures.GREAT_MARSH        = 6
Gen4DynamicMapFeatures.PLATFORM_LIFT_ROOM = 7
Gen4DynamicMapFeatures.ETERNA_GYM         = 8
Gen4DynamicMapFeatures.DISTORTION_WORLD   = 9
Gen4DynamicMapFeatures.VILLA              = 10
Gen4DynamicMapFeatures.COUNT              = 11

Gen4DynamicMapFeatures.BUFFER_BYTES = 32

-- THE CARTRIDGE'S THREE DISPATCH TABLES, recorded as shape rather than as
-- prose, because the shape is the surprise: the three tables in
-- `dynamic_map_features.c` are NOT the same set.  Every feature has an init;
-- three have no free; three have no collision -- and they are not the same
-- three.  A port that assumed "a feature has all three" would invent a
-- Hearthome collision function that the cartridge does not have, and would
-- then have to decide what it does.
Gen4DynamicMapFeatures.HAS_INIT = {
  [1] = true, [2] = true, [3] = true, [4] = true, [5] = true,
  [6] = true, [7] = true, [8] = true, [9] = true, [10] = true,
}
Gen4DynamicMapFeatures.HAS_FREE = {
  [2] = true, [3] = true, [4] = true, [5] = true,
  [8] = true, [9] = true, [10] = true,
}
Gen4DynamicMapFeatures.HAS_COLLISION = {
  [1] = true, [3] = true, [4] = true, [5] = true,
  [8] = true, [9] = true, [10] = true,
}

-- ---------------------------------------------------------------------------
-- The slot
-- ---------------------------------------------------------------------------

function Gen4DynamicMapFeatures.store(save)
  if type(save) ~= "table" then return nil end
  save.gen4MapFeature = save.gen4MapFeature
    or { id = Gen4DynamicMapFeatures.NONE, buffer = {} }
  return save.gen4MapFeature
end

function Gen4DynamicMapFeatures.id(save)
  local slot = Gen4DynamicMapFeatures.store(save)
  return slot and slot.id or Gen4DynamicMapFeatures.NONE
end

function Gen4DynamicMapFeatures.isCurrent(save, id)
  return Gen4DynamicMapFeatures.id(save) == (tonumber(id) or -1)
end

-- `PersistedMapFeatures_InitWithID`: clear the WHOLE record, then stamp the
-- id.  The clear is not decoration -- it is what makes a second feature's
-- read of a stale buffer impossible -- so the buffer is replaced rather than
-- emptied in place, and nothing that held a reference to the old one can
-- write through it.
function Gen4DynamicMapFeatures.initWithId(save, id)
  local slot = Gen4DynamicMapFeatures.store(save)
  if not slot then return nil end
  slot.id = tonumber(id) or Gen4DynamicMapFeatures.NONE
  slot.buffer = {}
  return slot.buffer
end

-- `PersistedMapFeatures_GetBuffer` GF_ASSERTs `id == persisted->id` and then
-- hands the buffer over regardless, because a GF_ASSERT is not a return on
-- retail hardware.  This answers NIL on a mismatch instead, which is the
-- difference between "the feature you asked about is not the one loaded" and
-- "here are another feature's bytes reinterpreted as yours".  Every caller
-- below therefore has to say what it does when the slot holds someone else.
function Gen4DynamicMapFeatures.buffer(save, id)
  local slot = Gen4DynamicMapFeatures.store(save)
  if not slot then return nil end
  if slot.id ~= (tonumber(id) or -1) then return nil end
  return slot.buffer
end

-- ---------------------------------------------------------------------------
-- Pastoria Gym -- the water level
-- ---------------------------------------------------------------------------

-- `enum PastoriaGymPressedButton`.
Gen4DynamicMapFeatures.PASTORIA_ORANGE_PRESSED = 0
Gen4DynamicMapFeatures.PASTORIA_GREEN_PRESSED  = 1
Gen4DynamicMapFeatures.PASTORIA_BLUE_PRESSED   = 2

-- `MAP_OBJECT_TILE_SIZE`, which is what a "tile" is worth in the units the
-- height system speaks.  Confirmed independently by this port's own terrain
-- work: `Gen4Maps.TERRAIN_TILE_UNITS` is 16 and a chunk is 512 over 32 tiles.
Gen4DynamicMapFeatures.TILE_UNITS = 16

Gen4DynamicMapFeatures.PASTORIA_WATER_LOW    = 0
Gen4DynamicMapFeatures.PASTORIA_WATER_MIDDLE = 2 * 16
Gen4DynamicMapFeatures.PASTORIA_WATER_HIGH   = 4 * 16

Gen4DynamicMapFeatures.PASTORIA_WATER_FOR_BUTTON = {
  [0] = 0,        -- orange -> LOW
  [1] = 2 * 16,   -- green  -> MIDDLE
  [2] = 4 * 16,   -- blue   -> HIGH
}

-- The water plate: `DynamicTerrainHeightManager_SetPlate(idx, 1, 2, 25, 38, 0)`
-- -- start tile (1, 2), size 25 x 38.  Kept because it is the region in which
-- a cell's height can come from the water instead of the floor, which is the
-- whole of the puzzle.
Gen4DynamicMapFeatures.PASTORIA_PLATE_X = 1
Gen4DynamicMapFeatures.PASTORIA_PLATE_Z = 2
Gen4DynamicMapFeatures.PASTORIA_PLATE_W = 25
Gen4DynamicMapFeatures.PASTORIA_PLATE_H = 38

-- THE GATE BEHAVIOURS, AND THE INVERSION THAT HAS TO BE COPIED RATHER THAN
-- REASONED.
--
-- `PastoriaGym_DynamicMapFeaturesCheckCollision` blocks a HIGH-ground tile
-- unless the height is `PASTORIA_WATER_HEIGHT_LOW`, a MIDDLE-ground tile
-- unless MIDDLE, and a LOW-ground tile unless HIGH.  High pairs with low and
-- low pairs with high; only the middle one agrees with its name.  Transcribed
-- in that order on purpose: a reader who "fixed" the apparent mix-up would
-- shut the gates the cartridge opens and open the ones it shuts.
Gen4DynamicMapFeatures.BEHAVIOUR_PASTORIA_H_GROUND = 0x56
Gen4DynamicMapFeatures.BEHAVIOUR_PASTORIA_M_GROUND = 0x57
Gen4DynamicMapFeatures.BEHAVIOUR_PASTORIA_L_GROUND = 0x58
Gen4DynamicMapFeatures.BEHAVIOUR_DYNAMIC_HEIGHT    = 0x59

Gen4DynamicMapFeatures.PASTORIA_GATE_OPENS_AT = {
  [0x56] = 0,       -- H_GROUND <-> WATER_HEIGHT_LOW
  [0x57] = 2 * 16,  -- M_GROUND <-> WATER_HEIGHT_MIDDLE
  [0x58] = 4 * 16,  -- L_GROUND <-> WATER_HEIGHT_HIGH
}

function Gen4DynamicMapFeatures.initForPastoriaGym(save)
  local b = Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.PASTORIA_GYM)
  if not b then return nil end
  -- `PersistedMapFeatures_InitForPastoriaGym` sets GREEN, which is the MIDDLE
  -- water level and not the zero one.  The zero value of the enum is ORANGE,
  -- so a buffer that was merely cleared would come up at LOW -- a different
  -- gym from the one the cartridge opens.
  b.pressedButton = Gen4DynamicMapFeatures.PASTORIA_GREEN_PRESSED
  return b
end

function Gen4DynamicMapFeatures.pastoriaWaterHeight(save)
  local b = Gen4DynamicMapFeatures.buffer(save,
    Gen4DynamicMapFeatures.PASTORIA_GYM)
  if not b then return nil end
  return Gen4DynamicMapFeatures.PASTORIA_WATER_FOR_BUTTON[b.pressedButton]
end

-- `PastoriaGym_PressButton` identifies the button by the MODEL under the
-- player -- `FieldSystem_FindCollidingLoadedMapPropByModelIDs` over a 1x1
-- hitbox at the player's own tile -- and does nothing at all when there is no
-- button there.  So this takes the model id the caller found rather than a
-- colour, and refuses an id that is not one of the three: the cartridge's
-- else-arm is `GF_ASSERT(FALSE)`, which is "this cannot happen", not "pick
-- one".
Gen4DynamicMapFeatures.PASTORIA_BUTTON_MODELS = {
  [239] = 2,  -- pastoria_gym_blue_button   -> BLUE_PRESSED
  [240] = 1,  -- pastoria_gym_green_button  -> GREEN_PRESSED
  [241] = 0,  -- pastoria_gym_orange_button -> ORANGE_PRESSED
}

function Gen4DynamicMapFeatures.pressPastoriaButton(save, modelId)
  local pressed = Gen4DynamicMapFeatures.PASTORIA_BUTTON_MODELS[tonumber(modelId) or -1]
  if pressed == nil then return false end
  local b = Gen4DynamicMapFeatures.buffer(save,
    Gen4DynamicMapFeatures.PASTORIA_GYM)
  if not b then return false end
  b.pressedButton = pressed
  return true
end

-- ---------------------------------------------------------------------------
-- Canalave Gym -- the sliding floor
-- ---------------------------------------------------------------------------

Gen4DynamicMapFeatures.CANALAVE_NUM_PLATFORMS = 24

-- `sCanalaveGymPlatformsStartInPositionB`, as the bit positions that are set.
-- Kept as the LIST rather than the packed integer so the count is a fact the
-- check can test: `SetCanalaveGymPlatformInitialState` writes bit `index`,
-- which makes the packed value 0x00AD0DC0.
Gen4DynamicMapFeatures.CANALAVE_STARTS_IN_B = { 6, 7, 8, 10, 11, 16, 18, 19, 21, 23 }

function Gen4DynamicMapFeatures.canalavePlatformStates()
  local states = 0
  for _, index in ipairs(Gen4DynamicMapFeatures.CANALAVE_STARTS_IN_B) do
    states = states + 2 ^ index
  end
  return states
end

function Gen4DynamicMapFeatures.initForCanalaveGym(save)
  local b = Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.CANALAVE_GYM)
  if not b then return nil end
  b.platformStates = Gen4DynamicMapFeatures.canalavePlatformStates()
  return b
end

function Gen4DynamicMapFeatures.canalavePlatformInB(save, index)
  local b = Gen4DynamicMapFeatures.buffer(save,
    Gen4DynamicMapFeatures.CANALAVE_GYM)
  if not b or not b.platformStates then return nil end
  index = tonumber(index)
  if not index or index < 0 or index >= Gen4DynamicMapFeatures.CANALAVE_NUM_PLATFORMS then
    return nil
  end
  return math.floor(b.platformStates / 2 ^ index) % 2 == 1
end

-- ---------------------------------------------------------------------------
-- Sunyshore Gym -- the gears
-- ---------------------------------------------------------------------------

Gen4DynamicMapFeatures.SUNYSHORE_NUM_ROOMS = 3

-- `PersistedMapFeatures_InitForSunyshoreGym(fieldSystem, roomID)`: a rotation
-- per room, AND an override.  The rooms start at 2, 1 and 0 -- descending, so
-- the gears are already part-turned when you walk in from the gym proper --
-- but if the player's own z equals the room's entrance z the rotation is
-- forced back to 0.  That is a ROOM-ENTRY test, not a constant, and dropping
-- it would leave a room pre-solved for a player who arrived the other way.
Gen4DynamicMapFeatures.SUNYSHORE_ROOM_ROTATION = { [0] = 2, [1] = 1, [2] = 0 }
Gen4DynamicMapFeatures.SUNYSHORE_ROOM_ENTRANCE_Z = { [0] = 14, [1] = 21, [2] = 25 }

function Gen4DynamicMapFeatures.initForSunyshoreGym(save, roomId, playerZ)
  roomId = tonumber(roomId)
  if not roomId or roomId < 0
     or roomId >= Gen4DynamicMapFeatures.SUNYSHORE_NUM_ROOMS then
    -- `GF_ASSERT(roomID < SUNYSHORE_GYM_NUM_ROOMS)` precedes the write, so a
    -- bad room must not be allowed to stamp the slot.
    return nil
  end
  local b = Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.SUNYSHORE_GYM)
  if not b then return nil end
  b.roomID = roomId
  b.rotationState = Gen4DynamicMapFeatures.SUNYSHORE_ROOM_ROTATION[roomId]
  if tonumber(playerZ) == Gen4DynamicMapFeatures.SUNYSHORE_ROOM_ENTRANCE_Z[roomId] then
    b.rotationState = 0
  end
  return b
end

-- ---------------------------------------------------------------------------
-- Eterna Gym -- the flower clock
-- ---------------------------------------------------------------------------

Gen4DynamicMapFeatures.ETERNA_CLOCK_INITIAL                  = 0
Gen4DynamicMapFeatures.ETERNA_CLOCK_DEFEATED_FIRST_TRAINER   = 1
Gen4DynamicMapFeatures.ETERNA_CLOCK_DEFEATED_SECOND_TRAINER  = 2
Gen4DynamicMapFeatures.ETERNA_CLOCK_DEFEATED_THIRD_TRAINER   = 3
Gen4DynamicMapFeatures.ETERNA_CLOCK_DEFEATED_GYM_LEADER      = 4

-- `VAR_ETERNA_GYM_FLOWER_CLOCK_STATE`, from the same enum walk over
-- generated/vars_flags.txt that this port's other var ids come from (the
-- walk's three anchors -- VAR_OBJ_GFX_ID_0 at 0x4020, VAR_LAST_TALKED at
-- 0x800D, VAR_POKEMON_NEWS_PRESS_REQUESTED_POKEMON at 0x40E5 -- all hold).
Gen4DynamicMapFeatures.ETERNA_CLOCK_VAR = 0x404B

-- AND NOT ONE SCRIPT IN THE CARTRIDGE READS IT.  Worth writing down, because
-- it is what decides the severity of leaving the clock alone: scanning all
-- 1,124 members of scr_seq for the id finds ZERO sites, so the clock state is
-- engine-private -- `EternaGym_DynamicMapFeaturesInit` reads it back to pose
-- the hands, and nothing else. The declined row is an honest "no" rather than
-- a lie: no branch anywhere takes a wrong arm because of it.
Gen4DynamicMapFeatures.ETERNA_CLOCK_VAR_SCRIPT_SITES = 0

function Gen4DynamicMapFeatures.initForEternaGym(save)
  local b = Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.ETERNA_GYM)
  if not b then return nil end
  -- `memset(data, 0, ...)`; the state is re-read from the var on load.
  b.state = Gen4DynamicMapFeatures.ETERNA_CLOCK_INITIAL
  return b
end

-- `EternaGym_AdvanceClockState`: refuse once the leader is beaten, otherwise
-- increment and mirror into the var.  The refusal is the interesting half --
-- without it the state walks past the end of `sEternaGymClockTimes`.
function Gen4DynamicMapFeatures.advanceEternaClock(save)
  local b = Gen4DynamicMapFeatures.buffer(save,
    Gen4DynamicMapFeatures.ETERNA_GYM)
  if not b then return false end
  local state = tonumber(b.state) or 0
  if state >= Gen4DynamicMapFeatures.ETERNA_CLOCK_DEFEATED_GYM_LEADER then
    return false
  end
  b.state = state + 1
  return true, b.state
end

-- ---------------------------------------------------------------------------
-- The Great Marsh tram
-- ---------------------------------------------------------------------------

Gen4DynamicMapFeatures.MARSH_AREA_1_2 = 0
Gen4DynamicMapFeatures.MARSH_AREA_3_4 = 1
Gen4DynamicMapFeatures.MARSH_AREA_5_6 = 2
Gen4DynamicMapFeatures.MARSH_MOVEMENT_CALL = 3
Gen4DynamicMapFeatures.MARSH_MOVEMENT_RIDE = 4
-- THE TWO VALUES THE SCRIPT ACTUALLY COMPARES.  Five and six, not one and
-- zero.  See the header.
Gen4DynamicMapFeatures.MARSH_AT_LOCATION     = 5
Gen4DynamicMapFeatures.MARSH_NOT_AT_LOCATION = 6

-- `PersistedMapFeatures_InitForGreatMarsh` is the ONLY constructor of the
-- eleven that checks the id first: it initialises only when the slot is not
-- already the marsh's.  Every other feature stamps unconditionally.  That
-- asymmetry is the tram remembering where it is across the six Great Marsh
-- maps, which all run the same init script -- so a plain `initWithId` here
-- would send the tram back to area 5-6 every time you changed area, which is
-- precisely the state the six `checkgreatmarshtramlocation` sites test.
function Gen4DynamicMapFeatures.initForGreatMarsh(save)
  if Gen4DynamicMapFeatures.isCurrent(save,
       Gen4DynamicMapFeatures.GREAT_MARSH) then
    return Gen4DynamicMapFeatures.buffer(save,
      Gen4DynamicMapFeatures.GREAT_MARSH)
  end
  local b = Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.GREAT_MARSH)
  if not b then return nil end
  b.location = Gen4DynamicMapFeatures.MARSH_AREA_5_6
  return b
end

function Gen4DynamicMapFeatures.tramLocation(save)
  local b = Gen4DynamicMapFeatures.buffer(save,
    Gen4DynamicMapFeatures.GREAT_MARSH)
  return b and b.location or nil
end

-- `GreatMarshTram_CheckLocation`.
function Gen4DynamicMapFeatures.checkTramLocation(save, location)
  local at = Gen4DynamicMapFeatures.tramLocation(save)
  if at ~= nil and at == (tonumber(location) or -1) then
    return Gen4DynamicMapFeatures.MARSH_AT_LOCATION
  end
  return Gen4DynamicMapFeatures.MARSH_NOT_AT_LOCATION
end

-- `GreatMarshTram_MoveToLocation`, the state half.
--
-- TRANSCRIBED AS THREE ARMS WITH AN ELSE, NOT AS "GO TO THE DESTINATION",
-- because they are not the same function.  From area 1-2 the destination is
-- honoured only when it is 3-4; anything else lands at 5-6.  From 3-4 the
-- test is against 1-2.  From 5-6 it is against 1-2 again.  So asking to go
-- from 1-2 to 1-2 moves the tram to 5-6 -- a self-move is not a no-op -- and
-- a port that wrote `state.location = destination` would differ from the
-- cartridge on exactly that case.
function Gen4DynamicMapFeatures.moveTramToLocation(save, destination)
  local b = Gen4DynamicMapFeatures.buffer(save,
    Gen4DynamicMapFeatures.GREAT_MARSH)
  if not b then return nil end
  local M = Gen4DynamicMapFeatures
  destination = tonumber(destination)
  local at = b.location
  if at == M.MARSH_AREA_1_2 then
    b.location = (destination == M.MARSH_AREA_3_4) and M.MARSH_AREA_3_4
                                                    or M.MARSH_AREA_5_6
  elseif at == M.MARSH_AREA_3_4 then
    b.location = (destination == M.MARSH_AREA_1_2) and M.MARSH_AREA_1_2
                                                    or M.MARSH_AREA_5_6
  elseif at == M.MARSH_AREA_5_6 then
    b.location = (destination == M.MARSH_AREA_1_2) and M.MARSH_AREA_1_2
                                                    or M.MARSH_AREA_3_4
  else
    -- `GF_ASSERT(FALSE)` with no write.
    return nil
  end
  return b.location
end

-- ---------------------------------------------------------------------------
-- The remaining five constructors, which carry no state worth naming
-- ---------------------------------------------------------------------------

function Gen4DynamicMapFeatures.initForHearthomeGym(save)
  -- `HearthomeGymPersistedFeatures { s16 initialized, correctDoorID, clueX,
  -- clueZ }` -- and `PersistedMapFeatures_InitForHearthomeGym` writes NONE of
  -- them: it takes the buffer and returns.  The zeroing is the whole
  -- initialisation, which is why `initialized` reads false and the gym
  -- chooses its door on first entry rather than here.
  return Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.HEARTHOME_GYM)
end

function Gen4DynamicMapFeatures.initForVeilstoneGym(save)
  local b = Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.VEILSTONE_GYM)
  if b then b.initialized = false end
  return b
end

function Gen4DynamicMapFeatures.initForVilla(save)
  return Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.VILLA)
end

function Gen4DynamicMapFeatures.initForDistortionWorld(save)
  return Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.DISTORTION_WORLD)
end

function Gen4DynamicMapFeatures.initForPlatformLift(save)
  return Gen4DynamicMapFeatures.initWithId(save,
    Gen4DynamicMapFeatures.PLATFORM_LIFT_ROOM)
end

-- ---------------------------------------------------------------------------
-- COLLISION_IS_A_HEIGHT_PROBLEM -- why there are no resolvers here yet
-- ---------------------------------------------------------------------------
--
-- The census's reason for ranking this subject was that three gyms put part
-- of their puzzle in the MAP, as behaviour 0x59
-- (`DYNAMIC_HEIGHT_COLLISION`), and this port turns every non-void cell into
-- collision 0 -- so those cells read as ordinary floor and the puzzle is
-- absent rather than impassable.
--
-- FIRST, THE CENSUS'S OWN NUMBERS WERE WRONG, and the error is visible once
-- you count rather than quote.  Over all 666 land chunks and their 681,984
-- permission words:
--
--     chunk 225           C02GYM0101   Canalave     293    (recorded: 293)
--     chunks 223, 224     C06GYM0101   Pastoria     445    (recorded: 356)
--     chunks 296-298      C08GYM0101-3 Sunyshore    411    (recorded: 293)
--                                      TOTAL      1,149    (recorded: 942)
--
-- Sunyshore's figure had been copied from Canalave's -- the same 293 twice --
-- and Pastoria's was short by 89.  The behaviour appears in those six chunks
-- and NOWHERE ELSE, which was the part worth checking and is still true, so
-- the conclusion survived its own arithmetic.  The H/M/L gate counts (10, 6,
-- 10) were right.
--
-- SECOND, THE OBVIOUS FIX IS A LOCKED GYM.  "0x59 means dynamic, so block it"
-- is the reading the behaviour's name invites, and measuring it from
-- Pastoria's own entrance warp -- (13, 42) in the stacked 32x64 map, which
-- the zone event data gives directly -- says:
--
--     0x59 walkable, gates ignored (today)      708 of 1,325 cells reachable
--     0x59 walkable, gates enforced per level   708   (all 10 buttons, all 26 gates)
--     0x59 BLOCKED                               57   (and ZERO of the 10 buttons)
--
-- Blocking it strands the player in the entrance passage with no button in
-- reach: not a harder gym, an unfinishable one.  So the cells ARE walkable
-- and the plain reading is wrong.
--
-- THIRD, AND THIS IS THE REASON THERE IS NO RESOLVER: the gates alone change
-- nothing.  708 either way.  Pastoria's 26 H/M/L cells are a detour, and the
-- thing that makes the gym a puzzle is the height arithmetic the gates sit
-- on. The cartridge's test is
--
--     *isColliding = TRUE  when  tile is H/M/L ground  and  height != its level
--
-- where `height` is the PLAYER'S OWN y, and the player's y at a cell is
-- whichever of the static BDHC height and the water plate's height is nearer
-- to the y they already have (`TerrainCollisionManager_GetHeight`), with a
-- step refused only once the two differ by 20 units or more.  Pastoria's BDHC
-- answers 0, 8, 24, 32, 40, 56 and 64 across its two chunks -- and the three
-- water levels are 0, 32 and 64, three of those exactly.  The gym is a
-- three-storey building and the water is the floor that moves between its
-- storeys.
--
-- This port's collision is two-dimensional (plus Gen 3's elevation bytes, which
-- Gen 4 maps do not carry: `Gen4Maps.mapDef` leaves elevation 0 and says so).
-- Giving the player a height is an engine change, not a gym feature, and it is
-- the honest next pass.  Implementing the gates without it would shut 26 cells
-- that the cartridge opens whenever the player's height does not happen to
-- match -- trading a missing puzzle for a wrong one, which is worse.
--
-- So the resolvers are DECLARED, with the cartridge's own shape recorded
-- above, and the slot they need is built and saved.  `checkCollision` exists
-- so the wiring is real and testable, and answers "not handled" for every
-- feature -- which is the truth, not a stub.
Gen4DynamicMapFeatures.RESOLVERS = {}

-- checkCollision(save, map, tileX, tileZ, height)
--   -> handled, isColliding
--
-- The cartridge's contract, kept exactly, because the two halves are not the
-- same thing and three features use the difference:
--
--   * handled = false      -- the feature has no opinion; ask the map
--   * handled, true        -- blocked, whatever the map says (Pastoria)
--   * handled, false       -- OPEN, whatever the map says (Canalave, whose
--                             resolver returns TRUE unconditionally and whose
--                             per-floor collision maps are the only authority
--                             in that gym)
--
-- A port that collapsed this to a boolean would lose Canalave entirely.
function Gen4DynamicMapFeatures.checkCollision(save, map, tileX, tileZ, height)
  local id = Gen4DynamicMapFeatures.id(save)
  if id == Gen4DynamicMapFeatures.NONE then return false end
  local resolver = Gen4DynamicMapFeatures.RESOLVERS[id]
  if not resolver then return false end
  return resolver(save, map, tileX, tileZ, height)
end

-- ---------------------------------------------------------------------------
-- Finding the button you are standing on
-- ---------------------------------------------------------------------------
--
-- `PastoriaGym_PressButton` does not take a colour.  It builds a hitbox at
-- the player's own tile and asks the terrain which of three MODELS is under
-- it, and if none is it returns having done nothing.  So the button is a
-- property of where you are standing, not of which script ran -- all three
-- `presspastoriagymbutton` sites are the same row.
--
-- AND THE HITBOX IS NOT THE DOOR SEARCH'S HITBOX.  `Gen4Doors.modelAt` looks
-- three tiles wide starting one tile west (`TerrainCollisionHitbox_Init(x, z,
-- -1, 0, 3, 1, ...)` in `ScrCmd_LoadDoorAnimation`), because a doorway is
-- wider than the tile the script names.  This one is
-- `TerrainCollisionHitbox_Init(playerX, playerY, 0, 0, 1, 1, ...)` -- exactly
-- one tile, no offset.  The two are deliberately different and the check
-- asserts both, because borrowing the door's three-wide window here would
-- press a button the player is standing beside.
Gen4DynamicMapFeatures.BUTTON_HITBOX_OFFSET_X = 0
Gen4DynamicMapFeatures.BUTTON_HITBOX_SIZE_X = 1
Gen4DynamicMapFeatures.BUTTON_HITBOX_SIZE_Z = 1

-- propModelAt(data, def, mapX, mapZ, tileX, tileZ, wanted)
--   -> model id, nil | nil, reason
--
-- `wanted` is a set of model ids.  The chunk, the origin and the unit all
-- come out of the SAME `gen4_terrain` fields the door search reads
-- (`chunkUnits`, `tileUnits`, `matrices[def.layout].land`), rather than from
-- literals here -- a second copy of those numbers is the one bug this
-- codebase keeps making, and a chunk that is 512 units in one file and 512
-- units in another is two facts that can drift apart.
function Gen4DynamicMapFeatures.propModelAt(data, def, mapX, mapZ, tileX, tileZ, wanted)
  local terrain = data and data.gen4_terrain
  if type(terrain) ~= "table" then return nil, "this cache has no gen4_terrain" end
  local grid = terrain.matrices and def and terrain.matrices[def.layout]
  if type(grid) ~= "table" or type(grid.land) ~= "table" then
    return nil, ("map %s names matrix %s, which this cache has no grid for")
                  :format(tostring(def and def.id), tostring(def and def.layout))
  end
  local w, h = grid.width or 0, grid.height or 0
  if mapX < 0 or mapZ < 0 or mapX >= w or mapZ >= h then
    return nil, ("matrix cell %d,%d is outside the %dx%d grid"):format(mapX, mapZ, w, h)
  end
  local land = grid.land[mapZ * w + mapX + 1]
  local record = land and terrain.chunks and terrain.chunks[land]
  if type(record) ~= "table" then
    return nil, ("matrix cell %d,%d names chunk %s, which has no record")
                  :format(mapX, mapZ, tostring(land))
  end
  local half = (terrain.chunkUnits or 512) / 2
  local unit = terrain.tileUnits or 16
  local x0 = tileX + Gen4DynamicMapFeatures.BUTTON_HITBOX_OFFSET_X
  local z0 = tileZ
  for _, o in ipairs(record.objects or {}) do
    if wanted[o.model] then
      local px = ((tonumber(o.x) or 0) + half) / unit
      local pz = ((tonumber(o.z) or 0) + half) / unit
      if px >= x0 and px < x0 + Gen4DynamicMapFeatures.BUTTON_HITBOX_SIZE_X
         and pz >= z0 and pz < z0 + Gen4DynamicMapFeatures.BUTTON_HITBOX_SIZE_Z then
        return o.model, nil, { object = o, land = land }
      end
    end
  end
  return nil, ("no wanted prop in the 1x1 hitbox at matrix %d,%d tile %d,%d (chunk %s)")
                :format(mapX, mapZ, tileX, tileZ, tostring(land))
end

return Gen4DynamicMapFeatures
