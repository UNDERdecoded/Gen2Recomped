-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MAP PROP ANIMATIONS -- the join that was missing, not the format.
--
-- Pass 178 built the door SOUNDS and wrote, in two files, that the animation
-- was out of reach: "this port reads NSBMD without NSBCA and bakes a chunk's
-- props into a flat canvas". Both halves of that are now false, and had been
-- for a while:
--
--   * NSBCA IS read. `Gen4Anim.parse` handles BCA0/BTA0/BTP0/BMA0/BVA0 and
--     `Gen4Anim.jointMatrices` produces per-frame joint matrices; the title
--     sequence and the starter models already wear them.
--   * PROPS ARE NOT BAKED. The land chunk is baked, but `Gen4Ground` draws
--     every building and prop as a live model each frame
--     (`building:draw(Gen4Model.multiply(view, placement(object)))`), and
--     `Gen4Model:draw(viewProjection, pose, ...)` takes a pose as its SECOND
--     argument, defaulting to the rest pose.
--
-- So a stale decline hid the real blocker, which was neither reading nor
-- drawing: it was WHICH ANIMATION BELONGS TO WHICH PROP.
--
-- `/arc/bm_anime.narc` holds 98 animations and NO models. The extractor pairs
-- an animation with a model by node count WITHIN ONE ARCHIVE, so every one of
-- those 98 came out `unworn` -- correctly, by that rule, because there is
-- nothing in that archive to wear them. The pairing lives in a third file.
--
-- THE INDIRECTION, from pokeplatinum's own map-format graph:
--
--     area_build      --> bm_anime_list : mapPropModelIDs
--     bm_anime_list   --> bm_anime      : animeArchiveIDs
--
-- `/arc/bm_anime_list.narc` has 590 members, one per `build_model.narc` model,
-- so member N of the list describes prop model N. No node-count guessing is
-- needed and none should be used.
--
-- Place at: src/import/Gen4PropAnim.lua

local Gen4PropAnim = {}
-- bm_anime_list flags=3: PC on/off and healing displays are loaded by
-- interactions, not by the ambient animation clock.
Gen4PropAnim.INTERACTION_ANIMATIONS={31,32,41,42}

-- ---------------------------------------------------------------------------
-- the record
-- ---------------------------------------------------------------------------
--
-- pokeplatinum's `docs/maps/file_format_specifications.md` gives:
--
--     hasAnimations   0x0000  1       bool
--     flags           0x0001  1       u8
--     isBicycleSlope  0x0002  1       bool
--     animeArchiveIDs 0x0003  4 * 4   u32[]
--
-- and that last offset is WRONG BY ONE. The records are 20 bytes, not 19, and
-- the byte at 0x03 is 0x00 in all 590 of them: it is padding, and the id array
-- starts at 0x04.
--
-- This is not a reading of the prose, it is a measurement that could have come
-- out the other way. Reading the array at the documented 0x03 puts 264 ids
-- outside the 98-member archive; reading it at 0x04 puts ZERO outside it, with
-- 166 real ids and 282 `0xFFFFFFFF` holes. The check re-runs both offsets and
-- compares them, so the correction is re-derived rather than remembered.
--
-- (The off-by-one is also self-consistent with the symptom: at 0x03 every id
-- reads as `real << 8`, because it swallows the pad byte as its low byte.)
Gen4PropAnim.RECORD_BYTES = 20
Gen4PropAnim.PAD_AT = 3          -- 0-based, always 0x00
Gen4PropAnim.IDS_AT = 4          -- 0-based; the doc says 3
Gen4PropAnim.MAX_ANIMATIONS = 4
Gen4PropAnim.NONE = 0xFFFFFFFF

-- `hasAnimations` is 0xFF rather than 0x00 when a prop has none -- the doc
-- calls this an oversight in the tool that built the archive, and `flags` is
-- 0xFF then too. So the test is `== 1`, never `~= 0`.
Gen4PropAnim.HAS = 1

-- flags, from the same doc. Bit 0 is the one the doors use.
Gen4PropAnim.DEFERRED_LOAD = 0x01  -- load the animation when needed (doors)
Gen4PropAnim.DEFERRED_ADD  = 0x02  -- attach it later (honey trees shaking)

local function u32(s, at)
  local a, b, c, d = s:byte(at, at + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216
end

-- parse(record) -> { has, flags, slope, ids = {...}, count }
--
-- `ids` holds only the real ones, in order, so `count` is what pokeplatinum
-- calls `animationCount` and what its two `== 2` / `== 4` arms switch on.
function Gen4PropAnim.parse(record)
  if type(record) ~= "string" or #record < Gen4PropAnim.RECORD_BYTES then
    return nil
  end
  local has = record:byte(1)
  local out = {
    has = has == Gen4PropAnim.HAS,
    flags = record:byte(2),
    slope = record:byte(3) == 1,
    ids = {},
  }
  if not out.has then out.count = 0; return out end
  for k = 0, Gen4PropAnim.MAX_ANIMATIONS - 1 do
    local v = u32(record, Gen4PropAnim.IDS_AT + 1 + k * 4)
    if v and v ~= Gen4PropAnim.NONE then out.ids[#out.ids + 1] = v end
  end
  out.count = #out.ids
  return out
end

function Gen4PropAnim.deferredLoad(entry)
  return entry ~= nil and entry.flags ~= nil
     and (entry.flags % 2) == 1
end

-- ---------------------------------------------------------------------------
-- the door animations, derived
-- ---------------------------------------------------------------------------
--
-- `Gen4Archives` is a names-and-metadata layer, not a bytes reader, so the
-- port cannot open `bm_anime_list.narc` at run time the way the check can.
-- These are therefore written down -- and the check re-derives every row from
-- the cartridge on every run, which is the same arrangement pass 178 used for
-- the twenty model names themselves.
--
-- `build_model` member is included because that is what the join is ON: the
-- list is indexed by prop model, and two doors with the same animations are
-- still two different props.
Gen4PropAnim.DOORS = {
  { name = "door01",                         member =  66, ids = { 7, 8, 9, 10 }, modelName = "door01" },
  { name = "brown_wooden_door",              member =  67, ids = { 7, 8, 9, 10 }, modelName = "t1_door1" },
  { name = "green_wooden_door",              member =  68, ids = { 7, 8, 9, 10 }, modelName = "t2_door1" },
  { name = "iron_door",                      member =  69, ids = { 7, 8, 9, 10 }, modelName = "t2_door2" },
  { name = "jubilife_city_building_door",    member = 246, ids = { 7, 8, 9, 10 }, modelName = "c1_door1" },
  { name = "pokecenter_door",                member =  70, ids = { 5, 6 }, modelName = "p_door" },
  { name = "pokecenter_inside_door",         member = 427, ids = { 5, 6 }, modelName = "door_pc01" },
  { name = "gts_inside_door",                member = 456, ids = { 5, 6 }, modelName = "door_wi01" },
  { name = "hearthome_gym_inside_door",      member = 260, ids = { 7, 8, 9, 10 }, modelName = "gym_door01" },
  { name = "blue_door",                      member = 312, ids = { 7, 8, 9, 10 }, modelName = "c3_door1" },
  { name = "iron_door_2",                    member = 313, ids = { 7, 8, 9, 10 }, modelName = "c3_door2" },
  { name = "yellow_wooden_door",             member = 438, ids = { 7, 8, 9, 10 }, modelName = "t3_door1" },
  { name = "blue_wooden_door",               member = 444, ids = { 7, 8, 9, 10 }, modelName = "c4_door1" },
  { name = "mansion_door",                   member = 441, ids = { 29, 30 }, modelName = "d3_door1" },
  { name = "veilstone_dpt_store_door",       member = 442, ids = { 29, 30 }, modelName = "c5_door_s" },
  { name = "gym_door",                       member = 298, ids = { 27, 28 }, modelName = "gym_door00" },
  { name = "card_door",                      member = 484, ids = { 27, 28 }, modelName = "card_door01" },
  { name = "pokecenter_inside_counter_door", member = 128, ids = { 33, 34 }, modelName = "counter_pc04" },
  { name = "hotel_grand_lake_door",          member = 527, ids = { 7, 8, 9, 10 }, modelName = "l2_door1" },
  { name = "elevator_door",                  member =  75, ids = { 51, 52 }, modelName = "ele_door1" },
}

-- THE KIND IS NOT UNIFORM, and that is the surprise worth carrying forward.
-- Nineteen of the twenty doors animate with BCA0 -- joints moving, which needs
-- `Gen4Model:posed`. `elevator_door` animates with BTP0, a texture-pattern
-- flipbook, which `Gen4TexAnim` has rendered since before any of this.
--
-- THE NOTE THAT USED TO SIT HERE SAID THAT MADE IT THE ONE DOOR THAT COULD
-- "MOVE TODAY", and pass 190 measured that and it was false in three separate
-- places at once -- an eighth instance of the pattern this project keeps
-- finding, and the first where the stale claim was a prediction rather than a
-- blocker:
--
--   * `Gen4Ground:oneShotProps` gated one-shot capability on `record.tracks`,
--     which a BTP0 record does not have, so `ele_door1` was handed to the
--     STATIC bake -- where the draw never asks for a pose at all;
--   * `Gen4Ground:animationsFor` joined an animation to a prop by NAME, and
--     the animations are `ele_door1_op` / `ele_door1_cl` while the model is
--     `ele_door1`, so that route answered nil too;
--   * the extractor decoded a BTP0's alternate frames only for a model whose
--     name an animation shared, so `ele_door1`'s four `ele_door.*` pictures
--     were never written and there was nothing to flip through.
--
-- All three are closed in pass 190. The remaining dependency is a re-import,
-- because two of the three read cache fields that an older import does not
-- carry.
Gen4PropAnim.TEXTURE_PATTERN_DOORS = { elevator_door = true }

-- COUNT AND SOUND ARE INDEPENDENT AXES, which is the other surprise.
--
-- `DoorAnimation_GetSoundEffectType` classifies by MODEL ID: the Veilstone
-- chime alone, six sliding doors, everything else hinged. The animation count
-- comes from a different file entirely, and the two do not line up:
--
--   * 11 hinged doors have 4 animations
--   * `mansion_door` and `pokecenter_inside_counter_door` are hinged and have 2
--   * every sliding door and the chime have 2
--
-- so a reader who assumed "hinged means four" would be wrong about two of the
-- thirteen, and one who assumed the count predicts the sound would be wrong
-- about `mansion_door`, which shares its animation pair (29, 30) with the
-- chime door while playing the hinged sounds. Pass 178's sound table is right
-- and this is simply a second, orthogonal fact.
--
-- pokeplatinum asserts on any other count:
--
--     if (animationCount == 2)      animationIndex = 0;   /* open  */
--     else if (animationCount == 4) animationIndex = 0;
--     else { GF_ASSERT(FALSE); animationIndex = 0; }
--
--     if (animationCount == 2)      animationIndex = 1;   /* close */
--     else if (animationCount == 4) animationIndex = 1;
--     else { GF_ASSERT(FALSE); animationIndex = 1; }
Gen4PropAnim.VALID_COUNTS = { [2] = true, [4] = true }

-- BOTH ARMS COLLAPSE TO THE SAME INDEX, in both functions, which is easy to
-- misread as dead code and is not: a four-animation door LOADS all four and
-- the door path plays only 0 and 1. Indices 2 and 3 exist, are loaded by
-- `MapPropOneShotAnimationManager_LoadPropAnimations(..., animationCount, ...)`
-- and are never reached from open or close. Recording that here so a later
-- pass does not "fix" the port by playing index 2 for something.
Gen4PropAnim.OPEN_INDEX = 0
Gen4PropAnim.CLOSE_INDEX = 1

-- THE FRAME COUNTS, derived, because a one-shot needs a duration before the
-- cache has been rebuilt to carry one.
--
-- Measured from `bm_anime.narc` with `Gen4Anim.parse`. Two regularities hold
-- and the check asserts both, because either one breaking would mean the ids
-- have moved:
--
--   * open and close ALWAYS have the same length as each other (5/6 are both
--     15 frames, 7/8 both 8, 27/28 both 10, 29/30 both 9, 33/34 both 10,
--     51/52 both 8);
--   * a four-animation door's unplayed pair is a DIFFERENT, shorter animation
--     -- ids 7/8 are 8 frames and 9/10 are 6 -- which is a second reason not
--     to assume indices 2 and 3 are spares of 0 and 1.
--
-- These are short: six to fifteen frames. A door is open in a quarter of a
-- second, which is worth knowing before anyone builds a wait around it.
Gen4PropAnim.FRAMES = {
  [5] = 15, [6] = 15,
  [7] = 8,  [8] = 8,
  [9] = 6,  [10] = 6,
  [27] = 10, [28] = 10,
  [29] = 9,  [30] = 9,
  [33] = 10, [34] = 10,
  [51] = 8,  [52] = 8,
}

function Gen4PropAnim.framesFor(id)
  return Gen4PropAnim.FRAMES[math.floor(tonumber(id) or -1)]
end

-- TWO NAMESPACES FOR ONE DOOR, and they disagree for nineteen of the twenty.
--
-- This is the recurring bug in its purest form -- the same thing spelled
-- differently in two tables that never meet -- and it was sitting between
-- `Gen4Doors` and the model cache the whole time:
--
--   * pokeplatinum's `doorModelIDs[]` names the FILE: `brown_wooden_door`,
--     which is what `Gen4Archives.find(MODEL_PATH, name .. ".nsbmd")` resolves
--     and what `Gen4Doors.MODELS` has held since pass 178;
--   * the cache names the MODEL INSIDE the file: `t1_door1`, which is what the
--     extractor reads out of the NSBMD and what `Gen4Ground.animsByName` and
--     `animationsFor` key on.
--
--     door01                         -> door01        (the only one that agrees)
--     brown_wooden_door              -> t1_door1
--     green_wooden_door              -> t2_door1
--     iron_door                      -> t2_door2
--     pokecenter_door                -> p_door
--     elevator_door                  -> ele_door1
--     pokecenter_inside_counter_door -> counter_pc04
--     jubilife_city_building_door    -> c1_door1
--     hearthome_gym_inside_door      -> gym_door01
--     gym_door                       -> gym_door00
--     ...
--
-- Note `gym_door` -> `gym_door00` and `hearthome_gym_inside_door` ->
-- `gym_door01`: the internal names are close enough to each other to look like
-- a typo, and swapping them would pick the wrong door silently.
--
-- NOTHING HAD JOINED THEM because nothing had needed to. `door01` agreeing is
-- exactly the kind of coincidence that makes a one-row spot-check pass: a
-- reader who verified one door would have concluded the two namespaces were
-- the same.
--
-- Pass 185's `oneShotPose` keys on the `bm_anime` MEMBER rather than on a
-- name, so it is right by construction -- but the bake split that has to come
-- next decides per prop whether it is baked, and doing that by name would have
-- been wrong for nineteen doors out of twenty.
function Gen4PropAnim.internalName(fileName)
  local row = Gen4PropAnim.doorRow(fileName)
  return row and row.modelName or nil
end

function Gen4PropAnim.fileNameOf(internal)
  for _, row in ipairs(Gen4PropAnim.DOORS) do
    if row.modelName == internal then return row.name end
  end
  return nil
end

-- HOW A DOOR ACTUALLY MOVES, from the extracted joint matrices.
--
-- Measured, not assumed, and the two kinds are genuinely different motions --
-- a reader who pictured all twenty swinging would be wrong about six of them:
--
--   hinged (anim 7/8, 9/10, 27/28, 29/30, 33/34)
--       a 90-degree rotation about Y.  frame 0 is the IDENTITY and the last
--       frame is [0 0 -1 | 0 1 0 | 1 0 0] -- or its mirror for anim 33/34,
--       which swings the other way.
--
--   sliding (anim 5/6, the Pokemon Centre family)
--       an X SCALE from 1.00 to 0.20.  The door does not rotate at all; it
--       squashes into the frame, which is what a sliding door looks like on a
--       flat-shaded DS prop.
--
-- AND THE MOVING JOINT IS NOT ALWAYS THE FIRST ONE. Animations 27/28 and
-- 29/30 carry THREE joints and joint 1 is static at both ends -- the motion is
-- in a later joint. A spot-check of `tracks[1]` on animation 7 passes and says
-- nothing about those four, which is exactly the hole pass 188's check closed.
Gen4PropAnim.ROTATE_DOORS = {
  [7] = true, [8] = true, [9] = true, [10] = true,
  [27] = true, [28] = true, [29] = true, [30] = true,
  [33] = true, [34] = true,
}
Gen4PropAnim.SCALE_DOORS = { [5] = true, [6] = true }

-- OPEN AND CLOSE ARE EXACT MIRRORS, which is the data confirming pret's index
-- rule rather than only its source: open's LAST frame equals close's FIRST,
-- and open's first equals close's last.  So `close` is its own animation
-- running open-to-shut forwards, not the open animation played in reverse --
-- the engine has a `reversed` flag and the doors do not use it.
--
-- THE LAST FRAME IS HELD, and the cartridge does it this way too:
--
--     if (animation->paused || animation->looping == FALSE) continue;
--     MapPropAnimation_AdvanceFrame(animation);
--     if (loopCount != -1 && IsOnLastFrame(animation)) {
--         if (currentLoop + 1 >= loopCount) animation->looping = FALSE;
--     }
--
-- Once `looping` goes false the animation is never advanced again, so the prop
-- sits on its final frame until the slot is released --
-- `IsAnimationLoopFinished` is literally `looping == FALSE`.  That is what
-- `Gen4PropOneShot.advance`'s clamp reproduces, and why a finished one-shot is
-- kept rather than cleared.

function Gen4PropAnim.doorRow(name)
  for _, row in ipairs(Gen4PropAnim.DOORS) do
    if row.name == name then return row end
  end
  return nil
end

-- animationFor(name, action) -> bm_anime member id, or nil
--
-- `action` is "open" or "close", the same two words `g4_door_anim` carries.
function Gen4PropAnim.animationFor(name, action)
  local row = Gen4PropAnim.doorRow(name)
  if not row then return nil end
  local index
  if action == "open" then index = Gen4PropAnim.OPEN_INDEX
  elseif action == "close" then index = Gen4PropAnim.CLOSE_INDEX
  else return nil end
  return row.ids[index + 1]
end

function Gen4PropAnim.countFor(name)
  local row = Gen4PropAnim.doorRow(name)
  return row and #row.ids or nil
end

function Gen4PropAnim.isTexturePattern(name)
  return Gen4PropAnim.TEXTURE_PATTERN_DOORS[name] == true
end

return Gen4PropAnim
