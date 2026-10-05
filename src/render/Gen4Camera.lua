-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PLATINUM'S FIELD CAMERA, transcribed.
--
-- Reported from play: "The map is rendering in flat 2d ... continue with the
-- tiled perspective camera make sure you match the platinum rom code".  This
-- is the cartridge's own table, out of `overlay005/field_camera.c`, and the
-- arithmetic that turns it into something this engine can draw with.
--
-- SEVENTEEN CAMERAS, one per `CAMERA_TYPE_*`, and the map header picks which:
-- `MapHeader.cameraType` is the byte at offset 21 (`map_header.h`), which
-- `Gen4MapHeaders` has always parsed and nothing has ever read.  Counted over
-- all 593 headers in this cartridge:
--
--   DEFAULT               189      SPEAR_PILLAR             4
--   INTERIOR_ORTHOGRAPHIC 300      SLIGHTLY_ZOOMED_OUT      3
--   CAVE                   60      OREBURGH_GYM             2
--   ZOOMED_IN              19      HALL_OF_ORIGIN           2
--   IRON_ISLAND_CAVE        6      LAKE_ACUITY              2
--                                  six others, one each
--
-- So THREE HUNDRED of the 593 headers -- every ordinary room, the player's
-- bedroom included -- are ORTHOGRAPHIC on the cartridge.  "Flat" was never
-- the mistake; flat and STRAIGHT DOWN was.  Every one of the seventeen is
-- tilted, between 40.6 and 78.4 degrees.
--
-- ONE WORLD UNIT IS ONE SCREEN PIXEL, and that is the cartridge's own number
-- rather than this port's convenience.  `Camera_ComputeProjectionMatrix`
-- builds the orthographic box as `top = tan(fovY) * distance`, and for
-- INTERIOR_ORTHOGRAPHIC that is tan(3.5211181640625) * 1563.537841796875 =
-- 96.209 -- half of the DS's 192-row screen.  Run the same product over the
-- perspective types and they all land in 94.8..96.2.  `fovY` is therefore the
-- HALF vertical field of view, and the scale is 1:1 at the target plane.
--
-- The angle is `CameraAngle.x`, stored NEGATED in the table; `Camera_Adjust-
-- PositionAroundTarget` puts the camera at
--
--   position = target + ( sin(y)*d*cos(x), sin(-x)*d, cos(y)*d*cos(x) )
--
-- and `y` is zero for all seventeen, so the camera is always due SOUTH of its
-- target and above it: for DEFAULT, 571.97 up and 342.98 south.

local Gen4Camera = {}

local floor, rad, tan, sin, cos = math.floor, math.rad, math.tan, math.sin, math.cos

-- The DS screen the numbers above are measured against.
Gen4Camera.SCREEN_W, Gen4Camera.SCREEN_H = 256, 192
Gen4Camera.ASPECT = 4 / 3

-- `pitch` is degrees BELOW HORIZONTAL, which is -CameraAngle.x; `halfFov` is
-- `verticalFov`, which is half the vertical field of view (see above).
-- `near`/`far` are the clip planes in world units.  Names are the cartridge's.
Gen4Camera.TYPES = {
  [0]  = { id = "default",        distance = 666.922119140625,  pitch = 59.051513671875,   projection = "perspective",  halfFov = 8.0914306640625,  near = 150, far = 900 },
  [1]  = { id = "pastoria_gym",   distance = 666.922119140625,  pitch = 68.367919921875,   projection = "perspective",  halfFov = 8.0914306640625,  near = 150, far = 900 },
  [2]  = { id = "zoomed_in",      distance = 515.4560546875,    pitch = 54.656982421875,   projection = "perspective",  halfFov = 10.458984375,     near = 150, far = 900 },
  [3]  = { id = "canalave_gym",   distance = 666.922119140625,  pitch = 59.051513671875,   projection = "perspective",  halfFov = 8.0914306640625,  near = 150, far = 900 },
  [4]  = { id = "interior",       distance = 1563.537841796875, pitch = 50.086669921875,   projection = "orthographic", halfFov = 3.5211181640625,  near = 150, far = 1735 },
  [5]  = { id = "spear_pillar",   distance = 316.501220703125,  pitch = 59.0460205078125,  projection = "perspective",  halfFov = 16.8804931640625, near = 10,  far = 1008 },
  [6]  = { id = "coronet_south",  distance = 866.554443359375,  pitch = 73.1085205078125,  projection = "perspective",  halfFov = 6.3336181640625,  near = 115, far = 1221 },
  [7]  = { id = "coronet_north",  distance = 666.922119140625,  pitch = 59.0460205078125,  projection = "perspective",  halfFov = 8.0914306640625,  near = 153, far = 1031 },
  [8]  = { id = "stark_room2",    distance = 662.922119140625,  pitch = 70.4718017578125,  projection = "perspective",  halfFov = 9.8492431640625,  near = 150, far = 1034 },
  [9]  = { id = "oreburgh_gym",   distance = 357.6044921875,    pitch = 40.5889892578125,  projection = "perspective",  halfFov = 15.029296875,     near = 150, far = 900 },
  [10] = { id = "veilstone_gym",  distance = 1202.355712890625, pitch = 60.8038330078125,  projection = "perspective",  halfFov = 4.5758056640625,  near = 150, far = 1746 },
  [11] = { id = "zoomed_out",     distance = 675.833251953125,  pitch = 57.8155517578125,  projection = "perspective",  halfFov = 8.0914306640625,  near = 230, far = 1127 },
  [12] = { id = "cave",           distance = 574.577880859375,  pitch = 63.2647705078125,  projection = "perspective",  halfFov = 9.4976806640625,  near = 150, far = 900 },
  [13] = { id = "iron_island",    distance = 515.4560546875,    pitch = 47.7960205078125,  projection = "perspective",  halfFov = 10.458984375,     near = 150, far = 900 },
  [14] = { id = "hall_of_origin", distance = 169.462158203125,  pitch = 78.37646484375,    projection = "perspective",  halfFov = 29.5367431640625, near = 10,  far = 1008 },
  [15] = { id = "lake_acuity",    distance = 653.929443359375,  pitch = 54.656982421875,   projection = "perspective",  halfFov = 8.349609375,      near = 150, far = 900 },
  [16] = { id = "unused_16",      distance = 330.921875,        pitch = 59.051513671875,   projection = "perspective",  halfFov = 15.4742431640625, near = 150, far = 900 },
}

Gen4Camera.DEFAULT_TYPE = 0

function Gen4Camera.forType(id)
  return Gen4Camera.TYPES[tonumber(id) or -1] or Gen4Camera.TYPES[Gen4Camera.DEFAULT_TYPE]
end

-- Half the screen height in WORLD UNITS at the target plane: tan(fovY) * d.
function Gen4Camera.halfHeight(config)
  return tan(rad(config.halfFov)) * config.distance
end

-- ...and therefore the pixels-per-unit the cartridge is working at.
--
-- FIFTEEN OF THE SEVENTEEN, NOT ALL OF THEM. This comment used to say "every one
-- of the seventeen" and it was wrong -- it was written from the four rows quoted
-- further down, and checking all of them found two that miss:
--
--     [8]  stark_room2   half = 115.09   +19.89%
--     [16] unused_16     half =  91.61    -4.57%
--
-- Both were re-read from `sCameraTypes` in pret and both MATCH: the distances,
-- pitches and FOVs above are the cartridge's. So this is not an extraction
-- error -- Stark Mountain's second room really does render about 1.2x wider than
-- one unit per pixel, and a renderer that assumes 1:1 everywhere draws that map
-- at the wrong scale. `unused_16` is named for being unreachable, so its miss
-- costs nothing; camera 8 is used by a real map.
function Gen4Camera.pixelsPerUnit(config)
  local half = Gen4Camera.halfHeight(config)
  if half <= 0 then return 1 end
  return (Gen4Camera.SCREEN_H / 2) / half
end

-- ---------------------------------------------------------------------------
-- HOW THIS PORT DRAWS IT, and where it differs
-- ---------------------------------------------------------------------------
--
-- The engine's world is a grid of 16-pixel tiles and EVERYTHING else in it --
-- collision, warps, sprites, the tile window, the encounter grid -- is laid
-- out in those pixels.  A true perspective camera moves the ground relative to
-- that grid, so adopting one means projecting every sprite through it as a
-- billboard in the same pass.  That is the right end state and it is not this
-- change.
--
-- What this does instead is an OBLIQUE projection at the cartridge's own
-- pitch:
--
--   screenX = x
--   screenY = z - y * cot(pitch)
--
-- The ground plane (y = 0) maps ONE TO ONE, so the tile grid, the collision
-- and every sprite stay exactly where they are and nothing above this file
-- changes.  HEIGHT leans up the screen, which is the whole point: a house
-- shows its front, a cliff shows its face, a bridge stands off the path under
-- it.  At pitch 90 the lean is zero and this is the straight-down bake that
-- came before, which is why the OPTIONS row can offer that as one of its
-- values without a second code path.
--
-- HOW FAR OFF THE CARTRIDGE IS, measured rather than waved at.  The cartridge
-- scales ground depth by sin(pitch) and height by cos(pitch); this scales them
-- by 1 and cos/sin.  That is the cartridge's own picture stretched vertically
-- by 1/sin(pitch) -- 16.7% for DEFAULT -- and the stretch is the price of
-- keeping a tile 16 pixels tall.  The remaining difference is the perspective
-- itself, and on this cartridge that is SMALL: a half-FOV of 8.09 degrees at
-- 666.9 units is a very long lens.  Ray-traced against the ground plane, the
-- DEFAULT camera sees from 101.87 units in front of the target to 120.86
-- behind it -- 222.73 units of ground over 192 rows, against 223.87 for an
-- orthographic camera at the same scale.  That is 0.51% on the total, and
-- +9.9% / -7.4% on the two halves.  It is the near and far EDGES of the screen
-- that are wrong, by about a tenth, and the centre that is right.
--
-- For the 300 INTERIOR_ORTHOGRAPHIC headers there is no difference at all
-- beyond the 1/sin stretch: the cartridge is orthographic there too.

-- ---------------------------------------------------------------------------
-- THE CARTRIDGE'S OWN PROJECTION, derived rather than approximated
-- ---------------------------------------------------------------------------
--
-- Everything above describes the OBLIQUE stand-in this port draws with.  What
-- follows is the real thing, read out of `camera.c` and `field_camera.c`, so
-- that the renderer has something exact to move to and so the size of the gap
-- is a number rather than an impression.
--
-- `Camera_AdjustPositionAroundTarget` puts the eye at
--
--     eye = target + ( sin(yaw)*d*cos(ax), sin(-ax)*d, cos(yaw)*d*cos(ax) )
--
-- with `ax = -pitch` and `yaw = 0` for all seventeen types, so
--
--     eye = target + ( 0, d*sin(pitch), d*cos(pitch) )
--
-- -- above the target and due SOUTH of it.  `up` is +Y.  The screen axes that
-- fall out of that are
--
--     right = ( 1, 0, 0 )
--     up    = ( 0, cos(pitch), -sin(pitch) )
--
-- and so, for a point offset from the target by (dx, dy, dz):
--
--     screenX =  dx
--     screenY = -dz * sin(pitch) - dy * cos(pitch)      (screen Y grows down)
--
-- GROUND DEPTH SCALES BY sin(pitch) AND HEIGHT BY cos(pitch).  At pitch 90 --
-- straight down -- that is ground 1:1 and no height at all, which is the flat
-- bake; at DEFAULT's 59.05 degrees it is 0.8576 and 0.5143.
--
-- THE SCALE IS ONE WORLD UNIT TO ONE SCREEN PIXEL, and that is the
-- cartridge's number, not this port's convenience: `tan(halfFov) * distance`
-- is 94.82 for DEFAULT, 96.21 for INTERIOR, 96.13 for CAVE, 95.15 for
-- ZOOMED_IN -- all of them half of the DS's 192-row screen, to within 1.3%.
--
-- WHAT THE OBLIQUE COSTS, exactly.  It scales ground by 1 and height by
-- cot(pitch); the cartridge scales them by sin and cos.  Since
-- cot = cos/sin, the oblique is the cartridge's picture STRETCHED VERTICALLY
-- BY 1/sin(pitch) -- 16.6% at DEFAULT, 30.4% at INTERIOR's 50.09 degrees.
-- Shapes are right; the world is too tall.
--
-- AND WHAT PERSPECTIVE WOULD ADD ON TOP, measured on the ground plane rather
-- than guessed: at the top and bottom edges of the screen the scale differs
-- from the orthographic one by 14.2% (DEFAULT), 16.7% (CAVE) and 18.5%
-- (ZOOMED_IN), and by 6.2% for INTERIOR -- which is moot, because INTERIOR is
-- orthographic on the cartridge and so are 300 of the 593 headers.  An earlier
-- note in this file put that figure at "about a tenth"; it was measured on the
-- depth the screen covers rather than on the scale at its edges, and the
-- number above is the one that describes what a player sees.

-- HOW FAR THE HEIGHT SCALE MAY BE PUSHED.
--
-- `Gen4Ground` sizes a chunk's canvas as `chunkPx * ground + height * MAX_RISE`
-- with MAX_RISE 384, so the height scale is what decides how tall a bake is:
-- 1.5 puts a 512-wide chunk on a 1,015-row canvas, and sixteen of those with
-- their depth buffers is about the most this cache should hold.  A rung
-- steeper than the ladder below would exceed it, so the clamp is here rather
-- than in the ladder -- a number that cannot be reached is not a limit.
local MAX_HEIGHT_SCALE = 1.5

-- cot(pitch), guarded at both ends: zero at 90 (straight down, no lean at all)
-- and floored at 5 degrees so a bad value cannot divide by nothing.
local function cot(pitch)
  pitch = tonumber(pitch) or 90
  if pitch >= 89.999 then return 0 end
  if pitch < 5 then pitch = 5 end
  return cos(rad(pitch)) / sin(rad(pitch))
end

-- THE GROUND SCALE AND THE HEIGHT SCALE, AND WHY THEY ARE NO LONGER ONE ANGLE.
--
-- On the cartridge they are: one pitch gives `sin` for ground depth and `cos`
-- for height, and a player who wanted more lean could only get it by tilting
-- the camera -- which SQUASHES THE MAP at the same time.  At 40 degrees a tree
-- rises twice as far and the whole of Sinnoh loses a quarter of its depth, so
-- the control traded one kind of wrong for another and the picture did not
-- obviously improve.
--
-- Reported from play: *"make the tilt work with the 3d of the world so the 3d
-- becomes more visible when used"*.  That is a request for a HEIGHT control,
-- not a camera angle, so the two are separated here:
--
--     ground = sin(mapPitch)                    -- never moves
--     height = sin(mapPitch) * cot(heightPitch) -- the OPTIONS row
--
-- `heightPitch` defaults to the map's own pitch, and there the identity
-- `sin * cos/sin = cos` gives back EXACTLY the cartridge's pair -- so
-- "CARTRIDGE" is bit-for-bit what it always was and every other rung raises
-- the height alone, leaving the map's footprint where it is.
--
-- `Gen4Ground.projection` already takes the two as an independent pair and
-- derives its lean and its depth row from them, so nothing downstream needed
-- to learn about this.
function Gen4Camera.scales(config)
  local pitch = rad((config and config.pitch) or 90)
  local ground = sin(pitch)
  local height = ground * cot((config and config.heightPitch) or (config and config.pitch) or 90)
  if height > MAX_HEIGHT_SCALE then height = MAX_HEIGHT_SCALE end
  return ground, height
end

-- Project a point given as an offset from the camera's TARGET, in world units,
-- to an offset in screen pixels.  `y` is height; `z` is south.  Screen Y grows
-- downwards, which is how every other surface in this engine counts.
--
-- This is the orthographic form, which is exact for the 300 INTERIOR headers
-- and within the percentages above for the rest.
function Gen4Camera.project(config, x, y, z)
  local s, c = Gen4Camera.scales(config)
  return x, z * s - y * c
end

-- The inverse on the GROUND PLANE (y = 0), which is what a renderer needs to
-- turn a screen row back into a tile row.
function Gen4Camera.unprojectGround(config, screenX, screenY)
  local s = Gen4Camera.scales(config)
  if s < 1e-6 then return screenX, 0 end
  return screenX, screenY / s
end

-- The height-to-screen lean, which is `height / ground` and therefore follows
-- the pair above rather than the raw pitch -- otherwise a raised height scale
-- would lean the geometry by one amount and place it by another, and a tree
-- would shear away from its own trunk.
function Gen4Camera.lean(config)
  local ground, height = Gen4Camera.scales(config)
  if ground <= 1e-6 then return 0 end
  return height / ground
end

-- ---------------------------------------------------------------------------
-- The OPTIONS row
-- ---------------------------------------------------------------------------
--
-- "CARTRIDGE" is the map header's own camera type, which is the answer this
-- file exists to give; the fixed angles are there because a player who wants a
-- different lean should not have to edit a file for it.
--
-- THE NUMERIC RUNGS STAY INSIDE THE PITCH RANGE THE CARTRIDGE ACTUALLY USES.
--
-- Reported from play, three times across three fixes: *"changing the tilt
-- seems to be stretching the buildings rather than changing the tilt of the
-- camera"*, then *"the tilted camera seems to be stretching things again"*,
-- and then *"the vertical stretching with the different camera angles when i
-- press 3 its stretiching things"*.
--
-- The first two were faults in how the rung reached the renderer -- `mode`
-- answering `field3d`, and `heightPitch` doing double duty -- and both are
-- fixed. The camera matrix is now exact at every rung: measured through
-- `Gen4View:project`, one world unit is 1.0000 screen pixels across the ground
-- and cos(pitch) up it, at every rung and on both projection kinds. So the
-- third report is not the renderer. It is the LADDER.
--
-- MEASURED over all 17 rows of `sCameraTypes[]`: Platinum's pitch runs from
-- 40.5890 degrees (row 9) to 78.3765 (row 14, HALL_OF_ORIGIN). The ladder
-- offered 90 and 80 -- both STEEPER than anything the cartridge draws -- and
-- 30, shallower than anything it draws.
--
-- That matters because the world's on-screen height is cos(pitch) while an
-- overworld character is a camera-facing BILLBOARD and is not foreshortened at
-- all. The billboard is ROM PARITY rather than a bug: the cartridge uses the
-- same unforeshortened sprite art across its whole 40.6..78.4 degree range, so
-- scaling sprites by pitch would BREAK parity, not restore it. What a rung
-- really moves is the sprite-to-world height ratio, and outside the
-- cartridge's range that ratio leaves every picture the ROM has behind:
--
--   rung 90 -> cos 0.0000 -- the world has ZERO height. Every building, tree
--              and sign collapses to nothing while a character stands full
--              size on top of it.
--   rung 80 -> cos 0.1736 -- below the ROM's own floor of 0.2015 (row 14).
--
-- And "3" CYCLES the ladder, so those two were the first two things a player
-- saw on pressing it, which is exactly when it was reported.
--
-- The RANGE is the ROM's, read off the rows rather than written out again. The
-- even spacing between the ends is the ladder's own, because a ladder should
-- step evenly -- so every rung lies inside a range the cartridge uses and the
-- two ends are exactly its own.
local function ladder(count)
  local steepest, shallowest
  for _, row in pairs(Gen4Camera.TYPES or {}) do
    local p = tonumber(row and row.pitch)
    if p then
      if not steepest or p > steepest then steepest = p end
      if not shallowest or p < shallowest then shallowest = p end
    end
  end
  -- A table this cannot read costs a LADDER, not a camera: the cartridge's own
  -- angle is still reachable on the CARTRIDGE rung either way.
  if not (count > 1 and steepest and shallowest and steepest > shallowest) then
    return { 78, 72, 66, 60, 53, 47, 41 }
  end
  local hi, lo = math.floor(steepest + 0.5), math.floor(shallowest + 0.5)
  local out = {}
  for i = 0, count - 1 do
    out[#out + 1] = math.floor(hi - (hi - lo) * i / (count - 1) + 0.5)
  end
  return out
end

-- ...AND THE TWO FREE MODES ON THE END OF THE SAME LADDER.
--
-- Requested: *"have first and third person as an option within the tilt"*.
-- They belong here rather than on a control of their own because they answer
-- the same question every other rung does -- how much of the world's height do
-- I want to see -- and a player who has walked the ladder down to its
-- shallowest rung is already asking for more of it.
--
-- A string rung carries no pitch, so `forMap` leaves the map header's own in
-- place and `Gen4Ground` reads the MODE instead; every consumer that asks this
-- table for a number still gets one for the seven numeric rungs.
--
-- SEVEN numeric rungs, unchanged in COUNT, and that is deliberate:
-- `save.options.gen4CameraTilt` stores the chosen INDEX, so a ladder of a
-- different length would silently move every saved choice onto another angle.
Gen4Camera.TILTS = (function()
  local t = { "cartridge" }
  for _, p in ipairs(ladder(7)) do t[#t + 1] = p end
  t[#t + 1] = "third"
  t[#t + 1] = "first"
  return t
end)()

-- THE CLOSEST THE CARTRIDGE EVER PUTS THE CAMERA: HALL_OF_ORIGIN, row 14 of
-- sCameraTypes[], distance 169.462158203125 at a 78.38 degree pitch.
--
-- It is here because the tilt ladder needs somewhere to interpolate the
-- PARALLAX towards, and a number this cartridge actually puts a player behind
-- is worth more than a round one I would have picked myself.  The far end of
-- the interpolation is the map header's own distance, so every value in the
-- range is a distance the ROM uses somewhere.
local NEAREST_DISTANCE = 169.462158203125

-- The shallowest numeric rung, taken FROM the ladder rather than written out
-- again, so adding a rung cannot leave the two disagreeing.
local SHALLOWEST = (function()
  local least
  for _, rung in ipairs(Gen4Camera.TILTS) do
    local n = tonumber(rung)
    if n and (least == nil or n < least) then least = n end
  end
  return least or 30
end)()

-- The steepest numeric rung, from the ladder for the same reason SHALLOWEST is
-- taken from it.
--
-- `forMap` used the LITERAL 90 as the top of the parallax interpolation, which
-- was the top of the ladder only while the ladder started at 90. Clamping the
-- rungs to the cartridge's range left `t` unable to reach 0, so the steepest
-- rung would have started with parallax the map header never asks for -- and an
-- orthographic room, whose whole point is that it has none, would have got some
-- on every rung.
local STEEPEST = (function()
  local most
  for _, rung in ipairs(Gen4Camera.TILTS) do
    local n = tonumber(rung)
    if n and (most == nil or n > most) then most = n end
  end
  return most or 90
end)()

-- Which rungs hand the frame to `Gen4View` rather than to the oblique matrix.
local FREE = { third = true, first = true }

-- modeFor(chosen) -> "third" | "first" | nil
--
-- Answered from the CHOSEN rung rather than from a second stored flag, so the
-- ladder stays the single source of truth about which view is up.
function Gen4Camera.mode()
  local chosen = Gen4Camera.externalTilt or Gen4Camera.TILTS[Gen4Camera.chosen]
  if FREE[chosen] then return chosen end
  -- A NUMERIC RUNG IS A CAMERA ANGLE, not a stretch.
  --
  -- Reported from play: *"changing the tilt seems to be stretching the
  -- buildings rather than changing the tilt of the camera"*, and later
  -- *"fixing the tilt in gen4 currently its stretching the buildings rather
  -- than changing the 3d view of the camera like first person and third
  -- person do"*.
  --
  -- It was doing exactly that, by construction: the ladder left the map's own
  -- `pitch` alone -- so the ground never moved -- and wrote the chosen angle
  -- into `heightPitch`, which only says HOW TALL to draw things.  Stepping the
  -- ladder therefore stretched every standing thing vertically and moved
  -- nothing.  That was a deliberate containment choice at the time, because
  -- the ground plane had to stay pixel-identical for the sprites and picks
  -- that are placed by it -- but the free camera has since solved all of that
  -- properly, with `freeEntity` placing sprites by projection.
  --
  -- So a numeric rung now selects a REAL camera at that pitch, through the
  -- same path first and third person use.  `cartridge` is unchanged and still
  -- answers nil, which keeps the oblique pass for the one rung that asks for
  -- the cartridge's own framing.
  if tonumber(chosen) then return "field3d" end
  return nil
end

-- HELD HERE RATHER THAN READ FROM THE SAVE, because the thing that needs it --
-- `Gen4Ground`, built by `MapLoader.load(data, mapId)` -- is never handed a
-- game.  That is the same reason `TileRenderer.setTileAnim` is a module-level
-- setter two lines above the call that builds the renderer, so this follows
-- the arrangement already there rather than threading a new argument through
-- four files.
--
-- `generation` ticks on every change.  A chunk is baked AT a pitch, so a new
-- pitch makes every bake stale; `Gen4Ground:draw` compares the counter and
-- drops them, which cannot be missed the way a hook can.
--
-- `sync` takes the saved choice up.  Two callers: the OPTIONS list as it is
-- built, and `OverworldState:enter`, which is the one place every path into
-- the world goes through -- boot, a warp, the map editor's Play.  The second
-- is what makes the choice survive a restart; without it the module would
-- start every session on the cartridge's own pitch whatever the save said.
Gen4Camera.chosen = 1
-- Presentation pipelines can temporarily choose a native view without
-- rewriting the player's saved camera preference.
function Gen4Camera.setExternalTilt(value)
  assert(value==nil or value=='cartridge' or value=='first' or value=='third'
    or (type(value)=='number' and value>0 and value<=90),'invalid native camera override')
  if value~=Gen4Camera.externalTilt then
    Gen4Camera.externalTilt=value
    Gen4Camera.generation=Gen4Camera.generation+1
  end
end
Gen4Camera.generation = 0

function Gen4Camera.setTilt(index)
  index = tonumber(index) or 1
  if index < 1 or index > #Gen4Camera.TILTS then index = 1 end
  if index ~= Gen4Camera.chosen then
    Gen4Camera.chosen = index
    Gen4Camera.generation = Gen4Camera.generation + 1
  end
  return Gen4Camera.TILTS[index], index
end

-- Take the saved choice, if this game has one.  Safe to call repeatedly.
function Gen4Camera.sync(game)
  local options = game and game.save and game.save.options
  if options and options.gen4CameraTilt then
    Gen4Camera.setTilt(options.gen4CameraTilt)
  end
  return Gen4Camera.TILTS[Gen4Camera.chosen], Gen4Camera.chosen
end

function Gen4Camera.tilt(game)
  if game then return Gen4Camera.sync(game) end
  return Gen4Camera.TILTS[Gen4Camera.chosen], Gen4Camera.chosen
end

-- The camera a map is drawn with: its header's type, with the OPTIONS row's
-- pitch substituted when the player has chosen one.
function Gen4Camera.forMap(def)
  local config = Gen4Camera.forType(def and def.cameraType)
  local chosen = Gen4Camera.externalTilt or Gen4Camera.TILTS[Gen4Camera.chosen]
  if chosen == "cartridge" then return config end
  local copy = {}
  for k, v in pairs(config) do copy[k] = v end
  -- `pitch` STAYS THE MAP'S OWN, and that is the change.
  --
  -- It used to be overwritten, which moved the ground and the height together
  -- and squashed the map to buy the lean.  The chosen angle now names the
  -- HEIGHT alone; everything that asks this config how deep the ground is --
  -- the blit, the sprite placement, `unprojectGround` turning a screen row
  -- back into a tile row -- still gets the map's own answer and needs no
  -- second thought about which pitch it is holding.
  -- THE RUNG'S ANGLE GOES IN ITS OWN FIELD, AND NOT IN `heightPitch`.
  --
  -- Reported from play, twice now: *"changing the tilt seems to be stretching
  -- the buildings rather than changing the tilt of the camera"*, and again
  -- after it was supposedly fixed: *"the tilted camera seems to be stretching
  -- things again"*.
  --
  -- It never stopped. The fix was made in `Gen4Camera.mode`, which now answers
  -- `field3d` for a numeric rung so the ladder selects a REAL camera at that
  -- angle -- and this line, the thing that did the stretching, was left as it
  -- was. So a rung did both: it built a 3D camera AND went on exaggerating
  -- `heightPitch`, which is the one number that says how tall to draw whatever
  -- stands on the ground. `scales()` reads it as `cot(heightPitch)`, so rung 30
  -- draws a 42-unit tree at nearly three times its height. The two halves of
  -- one decision were written in two files and never met.
  --
  -- It could not simply be deleted, because `heightPitch` was doing DOUBLE
  -- DUTY: `Gen4Ground:applyCamera` passes it to `Gen4View:useConfig` as the
  -- pitch for the 3D camera, so it was also the only way the rung's angle
  -- reached the view. One field meaning two things is why removing the stretch
  -- would have flattened the ladder instead -- every rung the same picture.
  --
  -- So the angle now travels as `rungPitch`, which nothing else reads, and
  -- `heightPitch` keeps the map header's own answer. The oblique pass draws
  -- heights exactly as the cartridge does at every rung; the ladder's angle
  -- reaches the camera that is actually drawing the frame.
  copy.rungPitch = tonumber(chosen) or nil
  copy.heightPitch = config.heightPitch or config.pitch
  copy.chosen = true

  -- AND HOW MUCH PARALLAX, which is the other half of *"make the tilt show 3d
  -- like the first and 3rd person do"*.
  --
  -- Measured before touching it: the spread is `cos(pitch)/distance` off the
  -- map header, so it read 0.0007711 per unit on EVERY rung of the ladder --
  -- 19.7% of the frame failing to cancel at rung 90 and 13.5% at rung 30, i.e.
  -- stepping the ladder never added any depth at all.  And for the 300
  -- INTERIOR_ORTHOGRAPHIC headers -- every ordinary room -- it was exactly
  -- 0.00% at every rung, 0 pixels of 184,320, because an orthographic
  -- projection has no parallax by construction.  The tilt could not show depth
  -- indoors however far it was stepped.
  --
  -- The spread is a fact about WHERE THE CAMERA SITS, so the honest way to make
  -- it larger is to bring the camera closer -- not to scale the term by a
  -- number chosen to look right.  The rung interpolates the eye's distance
  -- between the map header's own and `NEAREST_DISTANCE`, and the ROM supplies
  -- both ends.  (Reciprocally -- see below for why that is not a detail.)
  --
  -- THE GROUND PLANE IS UNTOUCHED, which is the whole containment argument:
  -- the shader's factor is `1 - y * spread`, exactly 1 at y = 0, so every
  -- sprite, pick and tile-row answer the overworld computes from `scales()` and
  -- `unprojectGround` reads the same as before.  `pitch`, `distance` and
  -- `projection` are all left alone for the same reason.
  local rung = tonumber(chosen)
  if rung then
    local span = STEEPEST - SHALLOWEST
    local t = span > 0 and (STEEPEST - rung) / span or 0
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    -- INTERPOLATE THE RECIPROCAL, because the spread IS proportional to 1 over
    -- the distance.  Two things follow, and both are the reason it is written
    -- this way round:
    --
    -- * An ORTHOGRAPHIC header starts at 1/D = 0, which is what orthographic
    --   MEANS -- a camera at infinity.  So rung 90 leaves those 300 rooms
    --   exactly as flat as the cartridge draws them, and the depth comes up
    --   from nothing as the player steps down the ladder.  Interpolating the
    --   distance itself instead handed rung 90 a spread of 0.0004104 and 12.13%
    --   parallax on the FLATTEST rung, which reads as a distortion rather than
    --   as depth: at rung 90 the height scale is 0, so nothing is raised and
    --   the splay has nothing to belong to.
    -- * Parallax then grows LINEARLY with the rung, which is the property a
    --   ladder should have.
    local nearest = 1 / NEAREST_DISTANCE
    local base = tonumber(config.distance)
    local invBase = (config.projection == "perspective" and base and base > 1)
                    and (1 / base) or 0
    local inv = invBase + t * (nearest - invBase)
    -- nil at rung 90 on an orthographic header, and `Gen4Ground` reads that as
    -- "no spread" -- the same answer it gave before this existed.
    copy.spreadDistance = inv > 0 and (1 / inv) or nil
    -- The angle stays the header's own PHYSICAL pitch: the rung moves how tall
    -- things are drawn and how close the eye is, never where the camera is.
    copy.spreadPitch = config.pitch
  end
  return copy
end

return Gen4Camera
