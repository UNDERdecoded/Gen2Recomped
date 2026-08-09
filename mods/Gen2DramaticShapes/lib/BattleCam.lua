-- Overworld battles: the over-the-shoulder camera and its parallax drift.
--
-- The two mons are PINNED to their cells: each pic is drawn wherever its
-- patch of ground projects to, not at a fixed screen slot. So the camera is
-- not decoration -- it is the thing that decides where the fight appears,
-- and it has to put those two patches of ground exactly where the battle
-- screen wants its two pics:
--
--     the player's mon   (26, 96)    back pic, feet on the text box, well left
--     the enemy's mon   (124, 56)    front pic, bottom of the 7x7 slot
--
-- Four screen coordinates, so four equations. The rig below is the solution:
-- SIDE / BACK / HEIGHT place the eye relative to the arena's midpoint, LOOK
-- aims it, and FRAME_H sets the lens, and together they land both marks
-- within a thousandth of a pixel of the targets. They are not hand-picked
-- numbers that looked about right -- they came out of a solver, and the
-- suite reprojects them so a future edit either still lands or says so.
--
-- East is what decides which mon is on which side. The arena axis runs north
-- (the enemy) to south (the player's mon), and a camera east of that axis
-- sees the near end swing LEFT and the far end RIGHT -- the layout arrived
-- at by standing in the right place rather than by mirroring anything.
--
-- ------- and two more equations, from the pixels
--
-- The pics are pixel art and their size on screen is not something the mod
-- gets to choose: 56 pixels for a front pic, 64 for a back one. And a mon has
-- to stand in ONE OVERWORLD SQUARE, or it towers over the houses and gives
-- away that the world behind it is a picture. Together those say the square
-- each mon stands on must project to about the width of its own pic, which is
-- two more equations for the same six unknowns -- and they are what set the
-- distance.
--
-- The answer is a LONG LENS FROM A LOW STANCE: twelve degrees above the
-- floor, twelve degrees wide, from five blocks back. Not a stylistic choice
-- -- it is what a 56-pixel sprite standing on a 16-pixel tile forces on a
-- 160-pixel screen. Roughly three tiles fit across the frame, so the camera
-- has to be far away and zoomed in rather than near and wide. That is the
-- DEFAULT rig, and every map that can take it gets it.
--
-- ------- the exception: rooms too small to stand back from
--
-- Five blocks back is further than some rooms are wide. A gym is about ten
-- cells across, so on one the eye lands OUTSIDE the map, where the border
-- ring the engine draws round every map -- extruded into a cliff by this mode
-- -- crosses the near Pokemon wherever it stands. Three gyms could not be
-- staged anywhere at all for that reason.
--
-- So there is a second rig, and an arena asks for it by name (cam = "wide"
-- in data/battle_arenas.lua). It comes in to about four cells with the lens
-- opened up to match: an ordinary 44-degree shot that fits inside the room.
-- The mons render smaller for it -- a bit over half a tile rather than a
-- whole one -- which is the price. Both rigs are solved against the SAME four
-- anchors, so the composition is identical either way; only the lens and the
-- distance differ, which is what makes it safe to pick per map.
--
-- Rooms too small for the long lens are the reason it exists, but it is not
-- only for them: an area that simply reads better with more of itself in
-- shot can ask for it too.
--
-- Purely presentational, like everything else in this mod: the camera looks
-- at the map, and nothing it does reaches collision, movement or scripts.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleCam = {}

-- ------- the rig, in world pixels (a map cell is 16, a block 32)
--
-- Solved against the four anchors and two spans above, with the two mons 48
-- world pixels (three cells) apart -- BattleArena.SHAPES is where that gap is
-- set, and changing it invalidates these.

-- `frameH` is how much world the frame is tall enough to hold at the aim
-- distance, which together with that distance is the lens.
-- Named for the LENS, because that is what an author is choosing between
-- when they look at a shot and decide it wants more room in it.
BattleCam.RIGS = {
  -- the default: a long 11.5-degree lens from five blocks back, which is
  -- what makes one tile big enough to stand a 56-pixel mon on
  tele = {
    side = 78.79, back = 144.96, height = 37.88,
    lookX = -0.26, lookY = 0.34, frameH = 34.11,
  },
  -- 44 degrees from four cells: fits inside a room the long lens cannot
  -- stand back from, and shows more of anywhere else, at the cost of a
  -- smaller pair
  wide = {
    side = 41.98, back = 41.16, height = 28.48,
    lookX = -3.24, lookY = -1.35, frameH = 55.62,
  },
}

BattleCam.DEFAULT_RIG = "tele"

-- The rig an arena asks for, falling back to the default for anything that
-- does not ask (and for a name that is not one of the two).
function BattleCam.rigFor(arena)
  local want = arena and arena.cam
  return BattleCam.RIGS[want] or BattleCam.RIGS[BattleCam.DEFAULT_RIG]
end

-- ------- the drift
--
-- A slow orbit about the arena's vertical axis. Rotating about a point
-- BETWEEN the two mons is what makes it parallax rather than a pan: the mons
-- are pinned to the ground, so the near one slides one way across the frame
-- and the far one slides the OTHER, by the amount their difference in
-- distance implies. Over a full swing that is about eight pixels of relative
-- movement -- plainly visible as depth, far too slow to fight the fight.
-- The angle is small because the lens is long: two degrees of orbit is seven
-- pixels of travel through an eleven-degree field of view.
--
-- Under it, a much smaller breath in and out along the same line, on an
-- unrelated period, so the pair never returns to the same pose on any cycle
-- a battle is long enough to show. A DOLLY rather than a pan of the aim:
-- moving the aim point would slide both mons the same way, which with pinned
-- pics is just the whole picture walking sideways. Changing the DISTANCE
-- moves them apart and back together about the frame's centre, which is the
-- same depth cue the orbit gives, from the other axis.
BattleCam.PAN_YAW = math.rad(2)   -- half-angle of the orbit
BattleCam.PAN_PERIOD = 26         -- seconds for one there-and-back
BattleCam.PAN_DOLLY = 0.02        -- how far the eye breathes, as a fraction
BattleCam.DOLLY_PERIOD = 37

-- ------- the player's own orbit
--
-- The drift above is the shot breathing. THIS is the player steering it:
-- a right stick, a drag across the screen or the mouse walks the eye
-- around the arena's axis, and it stops at both ends.
--
-- 0 is the shot the rig was solved for and the LEFT stop, because there is
-- nothing to the left of it -- the composition below is what the whole
-- module exists to land, and past it the two mons start swapping sides.
--
-- 1 is SIDE-ON: the eye swung round until it is square to the arena's
-- north-south axis, where the two mons stand at the same distance instead
-- of one behind the other. That is as far as the picture stays a battle
-- rather than a diorama with two Pokemon in it, and it is a different angle
-- for each rig -- the tele lens starts 28 degrees off the axis and the wide
-- one 45 -- so the stop is COMPUTED from the rig rather than written down,
-- and retuning either moves its own stop with it.
--
-- The input is deliberately not 1:1 with the pixels: it accumulates into
-- `orbitGoal` and the live angle eases after it, so a flick reads as the
-- camera being pushed rather than as the camera being dragged.
BattleCam.ORBIT_TIME = 0.22       -- seconds for the eye to catch its goal
BattleCam.ORBIT_DRAG = 1.15       -- fraction of the range per screen width
BattleCam.ORBIT_STICK = 0.9       -- fraction of the range per second, full tilt
BattleCam.ORBIT_MOUSE = 0.0011    -- fraction of the range per mouse count
BattleCam.STICK_DEAD = 0.2

-- ------- and the height it is watched from
--
-- The same steering on the other axis, with the same shape of stop at each
-- end: 0 is the rig's own stance -- the low, near-floor seat the whole
-- composition is solved around, and the DOWN stop, because below it the
-- camera starts looking up the arena's nose -- and 1 is 45 degrees above
-- it, which is high enough to read the ground the fight is standing on
-- without becoming the diorama's own top-down.
--
-- Raised about the FOCUS rather than about the eye, so the aim stays on
-- the two mons and only the seat climbs; and at a constant radius, so
-- climbing never changes how big anything is -- that is the zoom's job.
BattleCam.PITCH_RANGE = math.rad(45)
BattleCam.PITCH_TIME = 0.22
BattleCam.PITCH_DRAG = 1.6        -- fraction of the range per screen HEIGHT
BattleCam.PITCH_STICK = 0.9
BattleCam.PITCH_MOUSE = 0.0016

-- ------- and the player's own zoom
--
-- How much world the frame holds, as a multiple of the rig's own frameH:
-- BELOW one is zoomed in. It has to be the LENS rather than the distance,
-- because the rig derives its field of view from frameH and the distance
-- together -- so moving the eye alone changes the perspective and not the
-- framing, which is exactly what the dolly breath above is for.
BattleCam.ZOOM_MIN = 0.45         -- the pair filling the frame
BattleCam.ZOOM_MAX = 2.0          -- the fight in its own landscape
BattleCam.ZOOM_STEP = 1.15
BattleCam.ZOOM_TIME = 0.18

BattleCam.orbit = 0
BattleCam.orbitGoal = 0
BattleCam.pitch = 0
BattleCam.pitchGoal = 0
BattleCam.zoom = 1
BattleCam.zoomGoal = 1

-- Whether the player may steer at all. BACK SPRITES clears it: that
-- setting pins the player's own mon to the GB's own slot on the menu
-- (OverworldBattle.backPinned) instead of standing it out on the map, so
-- half the picture is nailed to the frame and half of it is geometry. Swing
-- the camera under that and the two halves come apart -- the foe walks
-- around an arena its opponent is not standing in, and the move animations
-- that reach between them stretch across the gap. There is no angle that
-- composition survives, so the answer is not to allow one.
--
-- Only the STEER is withheld: the slow drift stays, because it was always
-- there under BACK SPRITES and two degrees is not a composition problem.
BattleCam.steerable = true

-- Hold the rig perfectly still (VR sets this while a session runs). The
-- drift exists to give a FLAT screen the depth cue the picture cannot
-- have; a headset gets real parallax from the player's own head, and a
-- picture that sways on its own inside VR reads as the world lurching --
-- on the floating panel especially, where the battle screen is watched
-- from a fixed seat.
BattleCam.still = false

BattleCam.t = 0

-- Only the DRIFT's phase, so every fight opens on the same breath. Where
-- the player last put the camera is deliberately NOT reset: an angle and a
-- lens they chose are how they want to watch battles, not a thing about
-- this battle, and having to re-find them every encounter would make them
-- not worth setting. They are session state -- a fresh run opens on the
-- rig's own shot, which is the one the composition is solved for.
function BattleCam.reset()
  BattleCam.t = 0
end

-- Back to the solved shot, for anything that wants the composition as
-- authored rather than as steered.
function BattleCam.recentre()
  BattleCam.orbit, BattleCam.orbitGoal = 0, 0
  BattleCam.pitch, BattleCam.pitchGoal = 0, 0
  BattleCam.zoom, BattleCam.zoomGoal = 1, 1
end

-- How far the eye may swing, in radians, before it is square to the arena's
-- axis. The rig's own stance decides it: `side` and `back` are the offset
-- it starts at, so the bearing it starts on is atan2(side, back) and what
-- is left to a quarter turn is the room the player has.
function BattleCam.orbitRange(arena)
  local R = BattleCam.rigFor(arena)
  return math.max(0, math.pi / 2 - math.atan2(R.side, R.back))
end

-- ------- what the player's inputs reach
--
-- All four take a signed amount and clamp; positive is RIGHTWARD, toward
-- the side-on stop. Returning whether the goal actually moved lets a
-- caller tell "steered" from "already against the stop".

-- Both axes go through here, so the "nothing while BACK SPRITES holds the
-- composition" rule and the two stops live in one place each.
local function setAxis(key, goal)
  if not BattleCam.steerable then return false end
  local was = BattleCam[key]
  BattleCam[key] = math.max(0, math.min(1, goal))
  return BattleCam[key] ~= was
end

-- A drag, in fractions of the screen's width (orbit) or height (pitch).
function BattleCam.dragOrbit(fraction)
  return setAxis("orbitGoal",
                 BattleCam.orbitGoal + (fraction or 0) * BattleCam.ORBIT_DRAG)
end

function BattleCam.dragPitch(fraction)
  return setAxis("pitchGoal",
                 BattleCam.pitchGoal + (fraction or 0) * BattleCam.PITCH_DRAG)
end

-- Relative mouse motion, in counts.
function BattleCam.mouseOrbit(dx)
  return setAxis("orbitGoal",
                 BattleCam.orbitGoal + (dx or 0) * BattleCam.ORBIT_MOUSE)
end

function BattleCam.mousePitch(dy)
  return setAxis("pitchGoal",
                 BattleCam.pitchGoal + (dy or 0) * BattleCam.PITCH_MOUSE)
end

-- A stick held for `dt` seconds, as a rate with a squared response -- the
-- first half of the throw aims and the rest travels, the same curve the
-- free-roam look uses.
local function curve(v)
  local a = math.abs(v or 0)
  if a < BattleCam.STICK_DEAD then return 0 end
  a = (a - BattleCam.STICK_DEAD) / (1 - BattleCam.STICK_DEAD)
  return ((v < 0) and -1 or 1) * a * a
end

function BattleCam.stickOrbit(x, dt)
  local v = curve(x)
  if v == 0 then return false end
  return setAxis("orbitGoal",
                 BattleCam.orbitGoal + v * BattleCam.ORBIT_STICK * (dt or 0))
end

function BattleCam.stickPitch(y, dt)
  local v = curve(y)
  if v == 0 then return false end
  return setAxis("pitchGoal",
                 BattleCam.pitchGoal + v * BattleCam.PITCH_STICK * (dt or 0))
end

-- The zoom, in notches (positive pulls OUT, like every other zoom here).
function BattleCam.stepZoom(notches)
  if not BattleCam.steerable then return false end
  local was = BattleCam.zoomGoal
  BattleCam.zoomGoal = math.max(BattleCam.ZOOM_MIN,
                        math.min(BattleCam.ZOOM_MAX,
                                 was * (BattleCam.ZOOM_STEP ^ (notches or 0))))
  return BattleCam.zoomGoal ~= was
end

-- How far apart the two mons READ from the current orbit, as a multiple of
-- how far apart they read from the solved shot.
--
-- The arena's axis runs from one mon to the other, and the solved shot
-- looks along it at a shallow 28 degrees, which foreshortens that gap to
-- less than half its length. Swing round to square-on and the
-- foreshortening is gone: the same two cells now read at their full
-- separation, better than twice as wide. Left alone, that threw the pair
-- out to the edges of the frame -- half of each mon off-screen at the
-- side-on stop, which made the whole far end of the range unusable.
--
-- Climbing does the same thing on the other axis -- a raised camera looks
-- less along the ground and more across it, which un-foreshortens the gap
-- again -- so the correction has to answer to both.
--
-- What it measures is how much of the arena's axis survives projection:
-- the axis runs due north-south, the view line points back at the arena at
-- plan bearing `beta` and elevation `elev`, and the part of a unit axis
-- that lands across the frame rather than along the view is the sine of
-- the angle between them. The ratio of that to the solved shot's own is
-- the factor the lens opens by -- 1 at the solved shot by construction,
-- about 1.9 at side-on, about 1.7 fully raised.
--
-- Analytic rather than measured off the built rig, so nothing has to
-- reason about a camera to ask the question, and so the sun's box (which
-- asks through frameH) gets the identical number the lens does.
--
-- Measured off the STEER alone, deliberately: the drift's own two degrees
-- moved this before and must keep moving it by exactly as much, or every
-- battle shot that has ever been taken shifts.
local function axisSpan(beta, elev)
  local c = math.cos(elev)
  local s = math.sin(beta) * c
  local v = math.sin(elev)
  return math.sqrt(s * s + v * v)
end

function BattleCam.spread(arena)
  local R = BattleCam.rigFor(arena)
  local beta = math.atan2(R.side, R.back)
  local elev = math.atan2(R.height - R.lookY,
                          math.sqrt((R.side - R.lookX) ^ 2 + R.back ^ 2))
  local home = axisSpan(beta, elev)
  if home < 1e-6 then return 1 end
  return axisSpan(beta + BattleCam.orbit * BattleCam.orbitRange(arena),
                  elev + BattleCam.pitch * BattleCam.PITCH_RANGE) / home
end

-- How much world the frame holds right now: the rig's own reach at the
-- player's zoom and at whatever the orbit has done to the pair's spacing,
-- or the rig's own alone whenever both are being withheld (VR's fixed
-- seat, BACK SPRITES' pinned composition). The sun's box is fitted to this
-- too, so a zoomed shot lights exactly the ground it shows -- which is why
-- BattleScene asks this rather than multiplying for itself.
function BattleCam.frameH(arena)
  local base = BattleCam.rigFor(arena).frameH
  if BattleCam.still or not BattleCam.steerable then return base end
  return base * BattleCam.zoom * BattleCam.spread(arena)
end

local function chase(now, goal, dt, time)
  if now == goal then return goal end
  local v = now + (goal - now) * math.min(1, (dt or 0) / time)
  return (math.abs(goal - v) < 1e-4) and goal or v
end

-- Real frame time, like every other presentational tween in this mod: a
-- fast-forwarded battle must not spin the camera.
function BattleCam.update(dt)
  BattleCam.t = BattleCam.t + (dt or 0)
  -- keep the phase small forever rather than letting a long session lose
  -- float precision in the sines below
  local wrap = BattleCam.PAN_PERIOD * BattleCam.DOLLY_PERIOD
  if BattleCam.t > wrap then BattleCam.t = BattleCam.t - wrap end
  -- and the steered three easing after whatever the player last asked for,
  -- which is what keeps a flick of the stick from being a cut
  BattleCam.orbit = chase(BattleCam.orbit, BattleCam.orbitGoal, dt,
                          BattleCam.ORBIT_TIME)
  BattleCam.pitch = chase(BattleCam.pitch, BattleCam.pitchGoal, dt,
                          BattleCam.PITCH_TIME)
  BattleCam.zoom = chase(BattleCam.zoom, BattleCam.zoomGoal, dt,
                         BattleCam.ZOOM_TIME)
end

local function phase(t, period)
  return math.sin(2 * math.pi * t / period)
end

-- The camera for `arena` this instant: the record Voxel3D.camera takes, plus
-- the pitch the pull and the sun frustum want (measured from straight down,
-- the same convention Voxel.angle uses).
--
-- `fov` here frames the GB's 160x144. A caller rendering at window
-- resolution widens it for the extra picture around that frame -- see
-- BattleScene.letterboxFov, which is what keeps the pins exact at any window
-- size.
--
-- `groundY` is the height of the arena floor, so a fight staged on a ledge
-- or a raised walkway is shot from above THAT rather than from inside it.
-- `canonical` asks for the shot the rig was SOLVED for -- no drift, no
-- breath, no steer, no zoom -- from a caller that is reasoning about the
-- arena rather than drawing it. BattleArena's clearance test is the one
-- that needs it: whether a fight can be staged somewhere is a fact about
-- the ground, and answering it through whatever angle the player happened
-- to leave the last battle on would pick a different arena depending on
-- where they had swung the camera an hour ago.
function BattleCam.rig(arena, groundY, canonical)
  groundY = groundY or 0
  local R = BattleCam.rigFor(arena)
  local mx, mz = arena.mid[1], arena.mid[2]
  -- VR asks for the same stillness for its own reason (see BattleCam.still)
  local fixed = BattleCam.still or canonical
  -- and the steer is withheld a second way, on its own: BACK SPRITES holds
  -- the composition and the DRIFT still runs under it (see steerable)
  local steered = (not fixed) and BattleCam.steerable

  -- The drift, plus wherever the player has steered to. The steer is
  -- NEGATIVE because the rotation below runs the other way from the bearing
  -- it turns: rotating (side, back) by +yaw carries the eye back toward the
  -- arena's own axis, and the room the player has is all on the far side of
  -- that -- out toward square-on. (orbitRange measures exactly that room.)
  local steer = steered and -BattleCam.orbit * BattleCam.orbitRange(arena) or 0
  local yaw = steer + (fixed and 0
              or BattleCam.PAN_YAW * phase(BattleCam.t, BattleCam.PAN_PERIOD))
  local c, s = math.cos(yaw), math.sin(yaw)
  -- the breath scales the whole offset, height included, so the eye moves
  -- along its own line to the arena and the pitch of the shot never changes
  local k = fixed and 1
            or 1 + BattleCam.PAN_DOLLY
                   * phase(BattleCam.t, BattleCam.DOLLY_PERIOD)
  local dx = (R.side * c - R.back * s) * k
  local dz = (R.side * s + R.back * c) * k

  local eye = { mx + dx, groundY + R.height * k, mz + dz }
  local focus = { mx + R.lookX, groundY + R.lookY, mz }

  -- and the climb: the eye swung UP about the focus, at a constant radius.
  -- About the focus so the aim stays nailed to the two mons and only the
  -- seat moves, and at a constant radius so climbing never changes how big
  -- anything is -- that is the lens's job below, and a rig that did both at
  -- once would have no way to do either on purpose.
  local lift = steered and BattleCam.pitch * BattleCam.PITCH_RANGE or 0
  if lift > 0 then
    local vx, vy, vz = eye[1] - focus[1], eye[2] - focus[2], eye[3] - focus[3]
    local flat = math.sqrt(vx * vx + vz * vz)
    local r = math.sqrt(flat * flat + vy * vy)
    if flat > 1e-6 and r > 1e-6 then
      local a = math.atan2(vy, flat) + lift
      -- short of straight down, always: the placed camera's up vector is
      -- world up, which degenerates against a view looking exactly along it
      a = math.min(a, math.rad(85))
      local nf = r * math.cos(a)
      eye[1] = focus[1] + vx / flat * nf
      eye[3] = focus[3] + vz / flat * nf
      eye[2] = focus[2] + r * math.sin(a)
    end
  end

  local ex = eye[1] - focus[1]
  local ey = eye[2] - focus[2]
  local ez = eye[3] - focus[3]
  local dist = math.max(1, math.sqrt(ex * ex + ey * ey + ez * ez))
  local horiz = math.sqrt(ex * ex + ez * ez)

  -- The lens carries the player's zoom: how much world the frame holds is
  -- the one thing that actually changes the framing here, because the field
  -- of view is DERIVED from that reach and the distance. Moving the eye
  -- instead would leave the picture the same size and only change its
  -- perspective -- which is what the dolly breath above is deliberately
  -- for, and is not what "zoom" means to anyone holding a wheel.
  local frameH = fixed and R.frameH or BattleCam.frameH(arena)
  return {
    eye = eye,
    focus = focus,
    fov = 2 * math.atan((frameH / 2) / dist),
    -- the world curve is a free-roam flourish that bends the horizon away
    -- from the player; a fixed camera on a staged shot has no player to bend
    -- around, and the bend would tip the arena floor out from under the mons
    -- the pics are pinned to
    curve = 0,
  }, math.atan2(horiz, math.max(1e-3, ey))
end

return BattleCam
