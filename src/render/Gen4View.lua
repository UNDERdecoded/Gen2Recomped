-- Gen4View: a real camera, for the first- and third-person modes.
--
-- WHY THIS IS A NEW FILE AND NOT A FLAG ON THE OLD MATRIX.
--
-- `Gen4Ground:screenMatrix` is an OBLIQUE projection: it maps ground depth by
-- `sin(pitch)` and height by `cos(pitch)` and has no notion of yaw at all --
-- the camera is always due south of its target, exactly as the cartridge's own
-- seventeen rows are.  Two things follow.  It cannot look in an arbitrary
-- direction, which is the whole of first person; and its two axes are scaled
-- by DIFFERENT amounts, which is a deliberate squash for the field view and
-- would be a defect anywhere else.
--
-- Reported as the requirement: *"implement first person and third person to
-- work with the 3d models if possible without stretching the textures or
-- models of the house"*.  A true perspective camera is the thing that
-- guarantees that rather than merely avoiding it: `Gen4Model.perspective`
-- divides x by the ASPECT RATIO and leaves y alone, so a square in the world
-- is a square on the screen at every window size, and a texture on a wall
-- keeps its proportions however the wall is turned.  The field view's squash
-- is the exception in this engine, not the rule.
--
-- ---------------------------------------------------------------------------
-- THE SPACE
-- ---------------------------------------------------------------------------
--
-- The same one every other Gen 4 surface uses, and it is worth stating because
-- two of the three axes are not what a fresh reader assumes:
--
--   +x  EAST        +y  UP        +z  SOUTH
--
-- Distances are world units, one per map pixel, sixteen to a tile. Positions
-- are ABSOLUTE MATRIX coordinates -- the same ones `Gen4Ground:draw` builds as
-- `camX + offsetX` -- so a camera does not need to know which map it is on,
-- which matters precisely because a Sinnoh view spans several.
--
-- `yaw` is 0 looking NORTH and grows clockwise (east at a quarter turn), which
-- is the order the cartridge's own four facings are numbered in.
-- `pitch` is 0 at the horizon and POSITIVE LOOKING DOWN, matching
-- `Gen4Camera`'s rows, where the field camera's 59.05 is a steep downward look.

local Gen4Model = require("src.render.Gen4Model")

local Gen4View = {}
Gen4View.__index = Gen4View

local sin, cos, rad, max, min = math.sin, math.cos, math.rad, math.max, math.min
local deg = math.deg

-- The modes, in the order a control cycles them.
Gen4View.MODES = { "field", "third", "first" }

-- WHERE THE EYE SITS IN FIRST PERSON.
--
-- Reported from play: *"first person also has the camera too low should be
-- head height on the player"*.  It was 22, on a comment claiming the player
-- model "stands about 24 tall" -- a number nothing in this port had measured,
-- and one that disagrees with `ORBIT_PIVOT_Y`'s own comment three screens
-- down, which calls 16 the player's CHEST.  Both cannot be right: a chest at
-- 16 puts the crown near 32, not 24.
--
-- MEASURED INSTEAD, off the cartridge's own human-scale object -- a doorway,
-- which is built to clear a head and is the one prop whose height states what
-- a person is.  Decoded from `build_model.narc`:
--
--     door_pc01   30.50 units tall, standing from y = 0
--     door_wi01   30.50
--     door01      27.21
--     t1_h01 (a Twinleaf house)   71.00
--
-- So a doorway is 30.5 and the eye goes just under it: 26 is 0.85 of the
-- door, which leaves head clearance rather than putting the eye level with
-- the lintel.  It also squares with the pivot -- 16 against 26 is chest
-- against eye.  This is OUR number, not the cartridge's: Platinum has a fixed
-- camera and no first person, so nothing in the ROM states an eye height.
-- What the ROM states is the scale, and that is what 26 is taken from.
Gen4View.EYE_HEIGHT = 26

-- ...AND WHERE IT SITS IN THIRD PERSON.
--
-- Far enough back that the player occupies about a sixth of the frame height,
-- which is roughly what the field view gives them, and raised by a third of
-- that so the camera looks slightly down -- the angle a player reads as
-- "behind and above" rather than "lying on the floor behind".
Gen4View.FOLLOW_DISTANCE = 96
Gen4View.FOLLOW_HEIGHT = 40
Gen4View.FOLLOW_PITCH = 18

-- The vertical field of view.
--
-- NOT the cartridge's 16.2 degrees: that is a long lens chosen to make the
-- field view 1:1 with the DS screen at the target plane, and through it a
-- first-person view would feel like looking down a tube.  50 is the ordinary
-- choice for a first-person camera and it is a MODE setting rather than a
-- cartridge fact, so it is named here instead of being derived from something
-- that does not govern it.
Gen4View.FOV_Y = 50

-- Near plane close enough to stand against a wall without it vanishing; far
-- plane past the visible chunk span (three 512-unit chunks plus slack).
Gen4View.NEAR = 4
Gen4View.FAR = 4096

-- WHERE THE PLAYER LEFT THE CAMERA, kept in the MODULE and not on the view.
--
-- Reported from play: *"when changing from a town or route or map chunk its
-- resetting my camera"*.  A `Gen4Ground` is built per map, and `applyCamera`
-- builds it a fresh `Gen4View` -- so the orbit and the zoom lived on an object
-- that died at every doorway and every route boundary.  Walking north and back
-- put the camera behind the player again.
--
-- Held here for the same reason `Gen4Camera` holds the tilt choice in its
-- module: the thing that needs it is rebuilt by the map loader, which is never
-- handed a game and has no business carrying a camera across for it.  A look
-- the player set is a PREFERENCE, and it should outlive the map the way the
-- tilt rung and the zoom level already do.
--
-- `heading` is separate from `yaw` and both are needed.  `yaw` is the ORBIT's
-- angle and exists only while the player is orbiting; `heading` is the
-- direction the camera actually ended up looking on the last frame, whether
-- that came from an orbit, from the player's facing, or from its own previous
-- value.  Keeping only the first is what made a map change spin the view:
-- reported from play, *"camera flipping on route/chunk/city change, when i
-- walk into a new area its rotating my camera 180 degrees"* -- a player who
-- had never touched the orbit controls had `yaw = nil` kept, so the rebuilt
-- camera started at 0 (north) and anyone walking SOUTH was turned exactly
-- about.  Measured before the fix: 180.00 degrees across the boundary when
-- the player had never orbited, 0.00 when they had.
Gen4View.look = { orbiting = nil, yaw = nil, rise = nil, zoom = nil, heading = nil }

function Gen4View.new(mode)
  local self = setmetatable({}, Gen4View)
  self.mode = mode or "field"
  self.x, self.y, self.z = 0, 0, 0
  self.yaw, self.pitch = 0, 0
  self.fovY = Gen4View.FOV_Y
  -- ...and pick up where the last one left off.
  local kept = Gen4View.look
  self.orbiting, self.userYaw = kept.orbiting, kept.yaw
  self.userRise, self.zoom = kept.rise, kept.zoom
  -- The orbit's angle outranks the kept heading, because a player who IS
  -- orbiting has said where to look; the heading is what the camera fell back
  -- to for everyone else, and it is the whole reason a boundary no longer
  -- spins the view.
  self.yaw = self.userYaw or kept.heading or 0
  return self
end

-- Every control writes through to the kept state, so the next map inherits it.
function Gen4View:remember()
  local kept = Gen4View.look
  kept.orbiting, kept.yaw = self.orbiting, self.userYaw
  kept.rise, kept.zoom = self.userRise, self.zoom
end

-- IS THIS A 3D VIEW? -- which is a question about RENDERING.
function Gen4View:isFree()
  return self.mode == "third" or self.mode == "first"
      or self.mode == "field3d"
end

-- ...AND IS IT ONE THE PLAYER DRIVES? -- which is a question about CONTROLS,
-- and is a different question.
--
-- Reported from play: *"fix the camera being orbital and movement being free
-- when not in 3rd or 1st person"*.  Making the tilt rungs a real camera made
-- them free in BOTH senses at once, because one predicate was answering both
-- questions -- so stepping onto a tilt rung handed the player off-grid walking
-- and a mouse orbit as well as the 3D view they asked for.
--
-- A tilt rung is the CARTRIDGE'S camera at a different angle.  The cartridge
-- does not let you spin it, and the overworld it belongs to walks on a grid.
function Gen4View:isOrbital()
  return self.mode == "third" or self.mode == "first"
end

-- THE CARTRIDGE'S OWN CAMERA FOR THIS MAP, and the angle the ladder asks for.
--
-- `config` is a row of `Gen4Camera.TYPES` -- the distance, half-fov, near/far
-- and projection kind Platinum uses for this map's `cameraType`.  `pitchDeg`
-- is what the tilt ladder selected, which REPLACES the row's own pitch; that
-- substitution is the whole of the tilt now being a camera angle rather than a
-- vertical stretch.
function Gen4View:useConfig(config, pitchDeg)
  self.config = config
  self.fieldPitch = tonumber(pitchDeg)
    or (config and tonumber(config.pitch)) or 60
  -- `fovY` IS DELIBERATELY NOT TOUCHED HERE.
  --
  -- The first version wrote the row's `halfFov * 2` into it, and `applyCamera`
  -- hands the row to whichever view is up -- so stepping onto a tilt rung and
  -- back into third person left the third-person camera on the cartridge's
  -- 16.2-degree field instead of its own 50.  Caught by a masking check whose
  -- CONTROL painted nothing: the marker was outside a frustum a third as wide,
  -- and a control that paints nothing is the signal that something upstream
  -- moved, not a result.
  --
  -- Nothing needs the stored value anyway: `effectiveFovY` derives the field
  -- camera's fov from the row's DISTANCE and the target height, so that a unit
  -- stays a pixel, and every other mode keeps `Gen4View.FOV_Y`.
end

-- follow(x, z, facing) -- put the camera where the mode says, given where the
-- player is standing and which way they face.
--
-- `facing` is in RADIANS and is the direction the player is walking, so the
-- camera inherits it rather than owning a second heading that has to be kept
-- in step. A free-look control can overwrite `self.yaw` afterwards; this is
-- the default the mode falls back to.
-- WHAT AN ORBIT TURNS AROUND.
--
-- Roughly the player's chest at 16 units -- a tile -- rather than their feet,
-- because a camera swung about the feet rises and falls as it goes round and
-- reads as a pivot rather than a look.
Gen4View.ORBIT_PIVOT_Y = 16

-- A press of the orbit controls, in degrees.  Yaw in twenty-fourths of a turn
-- so four presses make a quarter and the cartridge's four facings are all
-- reachable exactly; elevation finer, because it has a much smaller range.
Gen4View.ORBIT_YAW_STEP = 15
Gen4View.ORBIT_RISE_STEP = 6
-- Below the pivot the camera looks up at the player through the ground, and
-- above 78 it is overhead and the third-person view has become the field one.
-- -12 rather than -20, and the number is geometry rather than taste.
--
-- Reported from play: *"the camera doesnt collide with the ground so im able to
-- see under the map"*.  The eye sits at `PIVOT_Y + sin(elevation) * radius` and
-- the base elevation is 14.04 degrees, so a rise of -14.04 puts it exactly ON
-- the pivot plane and anything below drives it underground.  -12 leaves about
-- two degrees of clearance at every zoom -- 3.5 units at the near stop, 9 at the
-- far one -- which is the shallowest look the sphere can offer without digging.
--
-- This stops the camera burying itself in FLAT ground.  Terrain that rises
-- between the eye and the player is a separate problem, and `Gen4Ground` holds
-- it up there because that is where the heights live.
Gen4View.ORBIT_RISE_MIN, Gen4View.ORBIT_RISE_MAX = -12, 60

-- THE ORBIT IS DERIVED FROM THE PLACEMENT THAT WAS ALREADY THERE, so that at
-- rest it reproduces it EXACTLY rather than approximately.
--
-- Today the eye sits `FOLLOW_DISTANCE` behind the player and `FOLLOW_HEIGHT`
-- above the ground.  Read as an orbit about the pivot that is a radius and an
-- elevation, and writing them this way round means the default framing is
-- untouched -- a player who never touches the controls sees the same picture,
-- and the check for that is arithmetic rather than a promise.
local ORBIT_RISE = Gen4View.FOLLOW_HEIGHT - Gen4View.ORBIT_PIVOT_Y
local ORBIT_RADIUS = math.sqrt(ORBIT_RISE * ORBIT_RISE
                               + Gen4View.FOLLOW_DISTANCE * Gen4View.FOLLOW_DISTANCE)
-- `atan2` is a 5.1/LuaJIT name that later Lua folds into a two-argument
-- `atan`.  This engine ships on LuaJIT, but a console build that did not
-- would fail here at LOAD time, taking the whole file with it.
local atan2 = math.atan2 or math.atan
local ORBIT_BASE = atan2(ORBIT_RISE, Gen4View.FOLLOW_DISTANCE)

-- HOW FAR BACK THE THIRD-PERSON CAMERA SITS, as a multiple of its own radius.
--
-- Requested: *"add the zoom in and out feature to the third person"*.
--
-- MULTIPLICATIVE PER NOTCH, not additive: a fixed number of units per notch
-- crawls when you are far out and lurches when you are close in, because what
-- the eye reads is the RATIO between one step and the last.  1.15 gives about
-- five notches between the stops in each direction.
--
-- The radius carries the height above the pivot with it, so zooming dollies
-- along the view line and the framing angle does not change -- which is what
-- stops a zoom from sliding into the ground or over the roof.
Gen4View.ZOOM_STEP = 1.15
Gen4View.ZOOM_MIN = 0.08
Gen4View.ZOOM_MAX = 2.60

-- zoomBy(notches) -> zoom.  Positive pulls back, negative moves in.
--
-- Inert in FIRST person by construction rather than by a test: the eye is at
-- the player there and `follow` never consults the radius, so there is nothing
-- for a zoom to scale.
function Gen4View:zoomBy(notches)
  local z = (self.zoom or 1) * (Gen4View.ZOOM_STEP ^ (tonumber(notches) or 0))
  if z < Gen4View.ZOOM_MIN then z = Gen4View.ZOOM_MIN end
  if z > Gen4View.ZOOM_MAX then z = Gen4View.ZOOM_MAX end
  self.zoom = z
  self:remember()
  return z
end

-- orbit(dYawDegrees, dRiseDegrees) -> yawDegrees, riseDegrees
--
-- Requested: *"theres no free movement or orbital camera"*.  Until this, the
-- free camera was pinned to the player's own facing -- it could only ever look
-- the way they were walking, so there was no way to look AT them, or round a
-- building, or up at a roof.
--
-- Once orbited the camera keeps ITS OWN yaw and stops taking the player's
-- facing, which is what makes it a camera rather than a chase view. `recentre`
-- gives the player's heading back.
function Gen4View:orbit(dYaw, dRise)
  self.orbiting = true
  self.userYaw = (self.userYaw or self.yaw or 0) + rad(tonumber(dYaw) or 0)
  local rise = (self.userRise or 0) + (tonumber(dRise) or 0)
  if rise < Gen4View.ORBIT_RISE_MIN then rise = Gen4View.ORBIT_RISE_MIN end
  if rise > Gen4View.ORBIT_RISE_MAX then rise = Gen4View.ORBIT_RISE_MAX end
  self.userRise = rise
  self:remember()
  return math.deg(self.userYaw) % 360, rise
end

-- Hand the camera back to the player's heading and the default elevation.
function Gen4View:recentre()
  self.orbiting, self.userYaw, self.userRise = nil, nil, nil
  self.zoom = nil
  self:remember()
end

-- `baseY` is the height of the GROUND the player is standing on, and leaving
-- it out is what made the camera sit low outdoors.
--
-- Reported from play: *"outdoors the height of the camera is lower but the
-- indoor height seems to be fine"*.  Every height here -- `EYE_HEIGHT`,
-- `ORBIT_PIVOT_Y` -- is a height ABOVE THE PLAYER'S FEET, and they were being
-- used as absolute world y.  That is only right where the floor happens to be
-- at zero, which is exactly the interiors that looked fine; Twinleaf's ground
-- is at y = 16, so outdoors the eye sat a whole tile into the player's shins.
-- The caller knows the floor height because it owns the height map, so it
-- passes it and the numbers here stay what they say they are.
function Gen4View:follow(x, z, facing, baseY)
  baseY = tonumber(baseY) or 0
  -- AN ORBIT OUTRANKS THE PLAYER'S FACING, and that is the point of it.
  -- ADOPTED EVERY FRAME, not just at construction -- and THIS is the flip.
  --
  -- Reported three times, and the first two fixes were aimed at the wrong
  -- thing: *"the camera in 3rd person is still flipping 90-180 degrees when i
  -- leave twinleaftown to the route, go in buildings, or even move to a
  -- different chunk"*, and *"the camera should always stay the same when
  -- transitioning between routes, chunks cities etc"*.
  --
  -- Every map owns a renderer, every renderer owns a `Gen4Ground`, and every
  -- ground built its own `Gen4View`.  At a boundary BOTH maps are loaded --
  -- the log alternates `map: R201` / `map: T01` for a dozen frames -- so there
  -- are two cameras alive, and the frame is drawn through whichever map is
  -- current.  Restoring the kept look in `new` only syncs a view at the moment
  -- it is BUILT: a neighbour loaded before the player touched the mouse keeps
  -- the old angle for ever, and stepping across the border swaps which camera
  -- you are looking through.
  --
  -- Measured: build both maps' grounds, orbit through one, then draw through
  -- the other -- the two disagree by **84.0 degrees**, which is the same -84.0
  -- that appears in the reported log.
  --
  -- So the kept look is re-read HERE, every frame, by every view. The look is
  -- the one shared thing; a `Gen4View` is only a lens onto it, and two lenses
  -- can no longer disagree. `heading` is written back for the same reason it
  -- always was: `remember` is only called by the orbit controls, and a player
  -- who never touches them still has a heading worth carrying.
  local kept = Gen4View.look
  self.orbiting, self.userYaw = kept.orbiting, kept.yaw
  self.userRise, self.zoom = kept.rise, kept.zoom
  self.yaw = (self.orbiting and self.userYaw) or facing or kept.heading
             or self.yaw or 0
  kept.heading = self.yaw
  local rise = (self.orbiting and self.userRise) or 0
  if self.mode == "field3d" then
    -- WHERE THE CARTRIDGE PUTS IT: `Camera_AdjustPositionAroundTarget` swings
    -- the eye around the target at the row's own distance, at the angle the
    -- ladder chose.  No orbit radius and no zoom -- those belong to the
    -- third-person camera, and a tilt rung is asking for the map's framing at
    -- a different angle, not for a different framing.
    local cfg = self.config
    local d = ((cfg and tonumber(cfg.distance)) or 512)*(self.zoom or 1)
    local e = rad(self.fieldPitch or 60)
    local horizontal = cos(e) * d
    -- FIXED HEADING.  The cartridge's field camera does not turn, and a tilt
    -- rung is that camera at a different angle -- so it does not inherit the
    -- heading the third-person camera was left on.  Keeping it at zero is also
    -- what keeps `screenToWorld` an identity, so a direction key means the
    -- same world direction it always did.
    self.yaw = 0
    self.x = x - sin(self.yaw) * horizontal
    self.z = z + cos(self.yaw) * horizontal
    self.y = baseY + sin(e) * d
    -- Looking AT the target, for the reason third person does: a camera that
    -- sits at one angle and aims along another does not point at the thing it
    -- is turning around.
    self.pitch = deg(e)
  elseif self.mode == "first" then
    self.x, self.y, self.z = x, baseY + Gen4View.EYE_HEIGHT, z
    -- In first person there is nothing to orbit AROUND -- the eye is already at
    -- the player -- so the elevation is simply where they are looking.
    self.pitch = rise
  else
    -- Behind the player along their own heading, which is the negation of the
    -- direction they are looking, swung up or down about the pivot.
    local f = self.yaw
    local e = ORBIT_BASE + rad(rise)
    local radius = ORBIT_RADIUS * (self.zoom or 1)
    local horizontal = cos(e) * radius
    -- WHAT THE ORBIT TURNS AROUND RISES AS YOU ZOOM IN.
    --
    -- Reported from play: *"when zooming in in third person it should zoom
    -- into the eye level on my player"*.  The pivot was pinned at the chest,
    -- so winding the zoom all the way in ended nose to nose with the player's
    -- chest and the head filled the top of the frame -- and stepping from
    -- there into first person jumped the eye up ten units.
    --
    -- The pivot now travels from the chest to the eye as the zoom closes, so
    -- the two modes meet instead of stepping.  ANCHORED AT ZOOM 1: `t` is 0
    -- there, so the default framing every other pass was measured against is
    -- arithmetically unchanged -- only a player who has actually zoomed in
    -- sees any of this.
    local zoom = self.zoom or 1
    local t = (1 - zoom) / (1 - Gen4View.ZOOM_MIN)
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local pivotY = Gen4View.ORBIT_PIVOT_Y
                 + (Gen4View.EYE_HEIGHT - Gen4View.ORBIT_PIVOT_Y) * t
    self.x = x - sin(f) * horizontal
    self.z = z + cos(f) * horizontal
    self.y = baseY + pivotY + sin(e) * radius
    -- LOOK AT THE PIVOT, which is what puts the player in the middle.
    --
    -- Reported from play: *"players not centered on the screen in third
    -- person"*.  The eye was placed on a sphere at elevation `e` and then
    -- aimed along a SEPARATE angle, `FOLLOW_PITCH + rise` -- 18 degrees
    -- against an elevation of 14.04 at rest.  A camera that sits at one
    -- angle and looks along another is not pointing at the thing it is
    -- orbiting, and the four-degree gap is exactly how far above centre the
    -- player sat.  On a sphere the two are the SAME ANGLE by definition.
    self.pitch = deg(e)
  end
end

-- The unit vector the camera is looking along.
function Gen4View:forward()
  local p = rad(self.pitch or 0)
  local cp = cos(p)
  -- yaw 0 is NORTH, which is -z.
  return sin(self.yaw or 0) * cp, -sin(p), -cos(self.yaw or 0) * cp
end

-- matrix(vw, vh) -> world-to-clip, row-major, for a vw x vh target.
--
-- THE ASPECT GOES IN HERE AND NOWHERE ELSE, which is what keeps a wall's
-- texture square: `perspective` puts `f / aspect` on x and `f` on y, so
-- widening the window widens the FIELD OF VIEW rather than stretching what is
-- already in it.
--
-- The Y FLIP is the same one `screenMatrix` needed and for the same reason: a
-- LOVE canvas counts rows downward while a GL projection counts NDC upward, so
-- a matrix that is right in a textbook renders the world upside down here. It
-- is applied to the projection rather than to `up` because flipping `up`
-- silently reverses the winding as well, and this engine draws with culling
-- off -- which would have hidden that until something turned it on.
function Gen4View:matrix(vw, vh)
  vw, vh = max(tonumber(vw) or 1, 1), max(tonumber(vh) or 1, 1)
  local fx, fy, fz = self:forward()
  local eye = { self.x, self.y, self.z }
  local target = { self.x + fx, self.y + fy, self.z + fz }
  local view = Gen4Model.lookAt(eye, target, { 0, 1, 0 })
  -- THE PROJECTION KIND IS THE MAP'S, not this camera's preference.
  --
  -- 300 of the 593 headers are CAMERA_TYPE_INTERIOR_ORTHOGRAPHIC and the
  -- cartridge really builds an orthographic box for them.  Drawing those with
  -- a perspective matrix is not a near-miss, it is the wrong picture: an
  -- orthographic camera has no parallax at all, which is the point of it
  -- indoors.  The half-height is `vh / 2` so one world unit stays one screen
  -- pixel -- the scale the rest of this engine is built at, and the
  -- cartridge's own (`tan(fovY) * distance` is 96.2 against a 192-row screen).
  -- ...AND ONLY A FIELD CAMERA HONOURS IT.
  --
  -- `applyCamera` hands the map's row to whichever view is up, so first and
  -- third person hold one too -- and without this gate a player who walked
  -- into a house in third person would silently get an ORTHOGRAPHIC camera,
  -- because 300 of the headers ask for one.  The cartridge's projection kind
  -- describes the cartridge's own field camera; first and third person are
  -- this port's cameras and are always perspective.
  local cfg = (self.mode == "field3d") and self.config or nil
  local proj
  if cfg and cfg.projection == "orthographic" then
    -- Dolly alone cannot magnify an orthographic map. Keep its visible box
    -- in step with the dolly so tilted indoor views zoom like outdoor views.
    proj = Gen4Model.orthographic(vh / 2 * (self.zoom or 1), vw / vh,
                                  tonumber(cfg.near) or Gen4View.NEAR,
                                  tonumber(cfg.far) or Gen4View.FAR)
  else
    proj = Gen4Model.perspective(rad(self:effectiveFovY(vh)), vw / vh,
                                 Gen4View.NEAR, Gen4View.FAR)
  end
  -- negate the clip-space y
  proj[5], proj[6], proj[7], proj[8] = -proj[5], -proj[6], -proj[7], -proj[8]
  return Gen4Model.multiply(proj, view)
end

-- What one world unit is worth on screen at a given distance, which is the
-- number a caller needs to size a billboard.  Published rather than left for
-- each caller to re-derive from the fov, because deriving it twice is how two
-- of them end up disagreeing.
-- The four facings in the order a clockwise turn visits them, which is the
-- order the cartridge numbers them in and the order a yaw grows through.
local CLOCKWISE = { "up", "right", "down", "left" }
local CLOCK_INDEX = { up = 1, right = 2, down = 3, left = 4 }

-- screenToWorld(dir) -> dir
--
-- Which WORLD direction a press of a screen direction means under this camera.
--
-- Requested: *"theres no free movement"*.  Once the camera has been swung round
-- a building, "up" still walked NORTH -- so the controls were relative to a
-- camera that was no longer there, which is the half of "free movement" that
-- actually bites.  Pressing up now walks AWAY FROM THE EYE.
--
-- QUANTISED TO QUARTER TURNS, and grid movement is exactly why.  Collision,
-- encounters, scripts, ledges and warps in this engine are all answered per
-- CELL and per FACING -- there are four of them and the cartridge has no notion
-- of a fifth.  Walking off the grid would not be "free movement", it would be
-- every one of those systems silently answering about the wrong tile.  So the
-- step stays on the grid and only which of the four it means is rotated.
--
-- ONLY WHILE ORBITING.  Unorbited, the camera takes the player's own facing, so
-- "away from the eye" would always be "forward" -- tank controls, and a change
-- to how the game plays for someone who only wanted a camera angle.
function Gen4View:screenToWorld(dir)
  if not (self.orbiting and CLOCK_INDEX[dir]) then return dir end
  -- Yaw is 0 north and grows clockwise, so the number of quarter turns the
  -- camera has taken is the number the input takes with it.
  local quarters = math.floor((self.yaw or 0) / (math.pi / 2) + 0.5) % 4
  return CLOCKWISE[((CLOCK_INDEX[dir] - 1 + quarters) % 4) + 1]
end

-- worldToScreen(dir) -> dir : the INVERSE of `screenToWorld`.
--
-- Which way a character should be DRAWN facing, given the way they are facing
-- in the world.  Reported from play: *"when i orbit the camera 180 degrees if i
-- walk left it looks like hes walking right"* -- and both halves of that are
-- this pair of functions. `screenToWorld` sends the PRESS the right way round
-- the world; this sends the resulting world facing back into the camera's frame
-- so the sprite shown is the one the player is looking at.
--
-- Turning the input one way and the artwork the other is not a coincidence:
-- they are inverses because the camera sits between them.
function Gen4View:worldToScreen(dir)
  if not (self.orbiting and CLOCK_INDEX[dir]) then return dir end
  local quarters = math.floor((self.yaw or 0) / (math.pi / 2) + 0.5) % 4
  return CLOCKWISE[((CLOCK_INDEX[dir] - 1 - quarters) % 4) + 1]
end

-- project(x, y, z, vw, vh) -> screenX, screenY, pixelsPerUnit, depth
--
-- Where a WORLD point lands on the screen this camera is drawing, and how big
-- one world unit is there.  Returns nil when the point is behind the eye or
-- nearer than the near plane, which a caller must check: a point behind the
-- camera still produces finite numbers after the divide, and they are mirrored
-- through the origin -- it would draw a character standing behind you in front
-- of you, which is worse than not drawing them.
--
-- THE SCALE NEEDS NO INVENTION.  The cartridge's field camera is 1:1 -- one
-- world unit is one screen pixel at the target plane, which is what
-- `tan(fovY) * distance = 96.209 = half of the DS's 192 rows` says -- so a
-- sprite's PIXEL dimensions are its WORLD dimensions, and the only thing left
-- to do is ask how many pixels a unit is worth at this depth.
--
-- The Y SIGN HERE WAS MEASURED, not reasoned about.  `matrix` negates the
-- projection's clip-space y for this canvas, and getting the follow-on sign
-- wrong is what rendered the whole map upside down the first time the ground
-- matrix was written.  A marker drawn at a known building's own coordinates
-- lands on that building with the form below.
function Gen4View:project(x, y, z, vw, vh)
  vw, vh = max(tonumber(vw) or 1, 1), max(tonumber(vh) or 1, 1)
  local m = self:matrix(vw, vh)
  local w = m[13] * x + m[14] * y + m[15] * z + m[16]
  -- AN ORTHOGRAPHIC CAMERA HAS NO PERSPECTIVE DIVIDE, and both tests below
  -- assume there is one.
  --
  -- Its matrix ends in (0, 0, 0, 1), so `w` is 1 for every point in the world
  -- -- and 1 is less than `NEAR`, which is 4.  Left alone, the guard would
  -- reject EVERY point on the 300 orthographic maps and no sprite, pick or
  -- billboard would place at all.  There the depth test belongs on the clip
  -- z, which is what says whether a point is in front of the eye.
  local ortho = self.mode == "field3d" and self.config
                and self.config.projection == "orthographic"
  local cz = m[9] * x + m[10] * y + m[11] * z + m[12]
  if ortho then
    if not w or w == 0 then return nil end
    local ndc = cz / w
    if ndc < -1 or ndc > 1 then return nil end
  elseif not (w and w > Gen4View.NEAR) then
    return nil
  end
  local cx = m[1] * x + m[2]  * y + m[3]  * z + m[4]
  local cy = m[5] * x + m[6]  * y + m[7]  * z + m[8]
  return (cx / w + 1) * 0.5 * vw,
         (cy / w + 1) * 0.5 * vh,
         -- One world unit is one screen pixel under the orthographic box this
         -- view builds, at every distance -- which is the whole difference
         -- between the two projections and the number a billboard needs.
         ortho and 1 / (self.zoom or 1) or self:pixelsPerUnitAt(w, vh),
         cz / w
end

-- THE FIELD OF VIEW THIS CAMERA ACTUALLY DRAWS WITH, for a vh-tall target.
--
-- The cartridge's `halfFov` is written for the DS's 192-row screen, where it
-- makes one world unit exactly one screen pixel at the target plane
-- (`tan(fovY) * distance` is 94.8..96.2 across the seventeen rows).  This
-- engine renders into a viewport that is not 192 rows, and a unit is a pixel
-- everywhere else in it -- the tiles, the sprites, the collision picks and the
-- oblique pass all count that way.
--
-- Taking the cartridge's ANGLE on a 384-row target magnifies everything 2x and
-- shows half as much world, which would make stepping onto a tilt rung read as
-- a zoom.  So what is kept from the row is the thing that is a fact about the
-- camera -- WHERE IT SITS, its distance and its pitch -- and the fov is the
-- one that preserves the engine's scale.  At `distance` this gives exactly one
-- pixel per unit, which is the cartridge's own relationship, just stated for
-- the screen we have.
--
-- The orthographic branch in `matrix` does the same thing by construction with
-- `halfHeight = vh / 2`, so the two projections agree about scale.
function Gen4View:effectiveFovY(vh)
  local cfg = self.config
  local d = cfg and tonumber(cfg.distance)
  if self.mode == "field3d" and d and d > 1e-6 then
    return deg(2 * math.atan((max(tonumber(vh) or 1, 1) / 2) / d))
  end
  return self.fovY
end

function Gen4View:pixelsPerUnitAt(distance, vh)
  local d = max(tonumber(distance) or 1, 1e-3)
  local halfH = math.tan(rad(self:effectiveFovY(vh)) / 2) * d
  return (max(tonumber(vh) or 1, 1) / 2) / halfH
end

return Gen4View
