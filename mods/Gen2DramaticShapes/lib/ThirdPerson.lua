-- Voxel world mode: the third-person camera -- the 3RD rung.
--
-- 3RD is 1ST with the eye pulled off the back of the head. Everything that
-- makes the first-person rung work -- the steered attitude, the placed
-- camera on Voxel3D's seam, the cards that turn to face the eye, the
-- continuous camera-relative walk -- is already general over WHERE the eye
-- stands, so this module adds exactly one thing to it: a BOOM.
--
-- What the boom owns:
--
--   the LENGTH    how far behind the pivot the eye sits, eased in and out
--                 so stepping between 1ST and 3RD slides rather than cuts,
--                 and clamped every frame by what the world will allow.
--
--   the COLLISION a march back along the boom line through the terrain
--                 height field and the map's own walkability, so backing
--                 into a wall walks the camera in toward the player's
--                 shoulders instead of through the wall into the void.
--                 The recovery is deliberately slower than the intrusion:
--                 a camera must never be a frame late leaving geometry,
--                 and must never snap back out the instant a corner clears.
--
--   the SHOULDER  the small lateral rail offset that keeps the character
--                 off dead centre, faded out with the boom so a camera
--                 jammed against a wall does not also slide sideways into
--                 it.
--
-- Deliberately NOT here: the attitude, the look inputs, the blend, the
-- move intent (all lib/FirstPerson.lua, which drives this module and reads
-- its answer while building the frame's rig), and movement itself
-- (lib/FreeMove.lua, unchanged -- the walk is camera-relative either way,
-- and the camera's yaw is the same number on both rungs).
--
-- Nothing here is required for the rung to draw: with no overworld to ask
-- (a headless run, the test suite) every query answers "clear" and the boom
-- extends to its full length over an empty world.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Voxel = V.require("VoxelState")

local ThirdPerson = {}

-- ------- the boom's numbers
--
-- BOOM is world pixels behind the pivot at full extension. A cell is 16 and
-- a character card is 16 tall, so 48 stands the camera three cells back:
-- with the first-person lens (65 degrees vertical) that frames the player
-- at roughly a quarter of the frame height -- the modern action-game
-- middle ground, close enough to read the four-frame sprite and far enough
-- to see the cell you are about to walk into.
--
-- PIVOT_LIFT raises the orbit point above the first-person eye, so the
-- boom looks slightly DOWN across the player's shoulder rather than
-- straight through the back of their head.
--
-- SHOULDER is the lateral rail offset, in world pixels, positive to the
-- camera's right -- which puts the player left of centre, leaving the
-- larger half of the frame in front of them.
ThirdPerson.BOOM = 48
ThirdPerson.PIVOT_LIFT = 4
ThirdPerson.SHOULDER = 4

-- how long the eye takes to slide out to the boom (and back into the head
-- when 1ST is picked), in seconds -- the same order as FirstPerson's own
-- dive so stepping 75 -> 1ST -> 3RD reads as one continuous camera
ThirdPerson.BOOM_TIME = 0.35

-- ------- the player's own zoom
--
-- A multiplier on BOOM, stepped by the wheel, Q/E or a pinch (see
-- CamControl, which owns every one of those and decides which camera a
-- given input is aimed at). The range is deliberately wider IN than OUT:
-- close is the shot people reach for, and far enough out the character is
-- a few pixels and the rung may as well be an orbit rung.
--
-- Stepped in fractions rather than world pixels so a notch feels the same
-- at both ends -- the near end of a linear step would crawl and the far
-- end would leap.
ThirdPerson.ZOOM_MIN = 0.45           -- ~22px: over the shoulder, close
ThirdPerson.ZOOM_MAX = 2.4            -- ~115px: the character in a landscape
ThirdPerson.ZOOM_STEP = 1.18          -- one wheel notch / key press
ThirdPerson.ZOOM_TIME = 0.18          -- how fast the eye eases to a new one

ThirdPerson.zoom = 1                  -- eased, what place() actually uses
ThirdPerson.zoomGoal = 1              -- what the input asked for

-- Step the zoom by `notches` (positive pulls the camera OUT). Returns true
-- when the goal actually moved, so a caller can tell "zoomed" from "already
-- at the stop" and let the input fall through.
function ThirdPerson.stepZoom(notches)
  local was = ThirdPerson.zoomGoal
  local goal = was * (ThirdPerson.ZOOM_STEP ^ (notches or 0))
  ThirdPerson.zoomGoal = math.max(ThirdPerson.ZOOM_MIN,
                          math.min(ThirdPerson.ZOOM_MAX, goal))
  return ThirdPerson.zoomGoal ~= was
end

-- Scale the zoom by a continuous factor -- what a pinch hands over, where
-- the gesture's own scale IS the answer and there are no notches.
function ThirdPerson.scaleZoom(factor)
  if not (factor and factor > 0) then return false end
  return ThirdPerson.stepZoom(math.log(factor) / math.log(ThirdPerson.ZOOM_STEP))
end

-- ------- the collision's numbers
--
-- STEP is how far apart the samples along the boom line are, in world
-- pixels, and REFINE how many bisections narrow the first blocked one --
-- four halvings of a 4px step lands the eye within a quarter pixel of the
-- face, which is finer than the boom ever needs to be.
--
-- PAD is the clearance kept between the eye and whatever stopped it. It
-- has to beat the placed camera's near plane (|eye - focus| * 0.05, which
-- at full extension is about 3.6 world pixels -- see Voxel3D) or the near
-- plane clips a hole in the very wall the boom stopped at.
--
-- CLEAR is how high above a cell's ground the eye must be to pass OVER
-- something unwalkable rather than being stopped by it: a fence, a kerb or
-- a plant pot should not shove the camera in, a building should. Roughly
-- head height, so the eye clears the props and never the walls.
ThirdPerson.STEP = 4
ThirdPerson.REFINE = 4
ThirdPerson.PAD = 5
ThirdPerson.CLEAR = 20

-- How fast the boom is allowed to grow BACK once whatever shortened it is
-- out of the way, in world pixels per second. Shortening is instant (a
-- camera inside a wall is a hole in the frame); lengthening is rationed,
-- so rounding a corner eases the eye back out instead of snapping it.
ThirdPerson.RETURN = 150

-- ------- state
--
-- `out` is the eased extension, 0 in the head and 1 fully boomed -- the
-- number that carries 1ST into 3RD. `len` is the boom's actual length in
-- world pixels after the world has had its say, which is what place()
-- stands the eye at and update() eases back toward `want`.
ThirdPerson.out = 0
ThirdPerson.len = 0
ThirdPerson.want = 0

local function ease(t)
  return t * t * (3 - 2 * t)
end

-- ------- gates

-- Whether the 3RD rung is the one selected. Not "is the boom out" -- that
-- is extended() below, which stays true through the ease after the rung is
-- left, the same way FirstPerson.blend outlives its own rung.
--
-- A live headset declines the boom outright: VR builds its own eye cameras
-- from the tracked pose and never asks place() where to stand, and a
-- headset that seats its wearer three cells behind their own body is a
-- well-known way to make people ill. Answering false here is what keeps
-- everything ELSE the extension decides -- the player's own card, the body
-- that turns as it walks -- honest about the head VR actually puts you in.
-- Required lazily and guarded: VR reaches this module through FirstPerson,
-- and a headless run has no VR module worth loading at all.
local function headset()
  local ok, on = pcall(function() return V.require("VR").active() end)
  return ok and on or false
end

function ThirdPerson.selected()
  return Voxel.isThirdPerson(Voxel.level) and not headset()
end

-- The eased extension, 0 at the head and 1 at the full boom.
function ThirdPerson.extension()
  return ease(ThirdPerson.out)
end

-- Whether the boom is out far enough to be a third-person camera at all --
-- read off the TARGET extension rather than the live length, so it is
-- steady while the world shoves the eye about. What the body reads to
-- decide whether it turns along its own travel.
function ThirdPerson.extended()
  return ThirdPerson.extension() > 0.5
end

-- How far back the eye must ACTUALLY be, in world pixels, for the player's
-- own card to be worth drawing: a shade under a cell, which is the point
-- where a 16-pixel card stops being a character and starts being a wall of
-- pixels across the lens.
ThirdPerson.SHOW_AT = 14

-- Whether the player's own card belongs in the frame. Not the same
-- question as extended(): back into a fence and the boom collapses into
-- the head whatever the rung says, and a card drawn there fills the lens
-- from inside exactly as it would in first person -- so it comes out, and
-- the rung reads as first person for as long as the world insists on it.
function ThirdPerson.showsPlayer()
  return ThirdPerson.extension() > 0 and ThirdPerson.len >= ThirdPerson.SHOW_AT
end

-- ------- the world the boom has to fit through
--
-- Everything below asks the live overworld and pcall-guards the asking:
-- with no map (headless, the suite, a frame mid-warp) the boom simply
-- extends to its full length, which is the right answer for a world with
-- nothing in it.

local function overworld()
  local ok, ow = pcall(function()
    return require("src.core.Game").overworld
  end)
  if not ok or not ow or not ow.map then return nil end
  return ow
end

-- Which map, and which of its cells, covers a world point. The player's own
-- map first, then the neighbours the scene streams in around it (same ox/oy
-- offsets VoxelScene draws them at) -- without that pass the boom would
-- shorten against "off the map" every time the player walked within three
-- cells of a route connection, which is most of the time.
--
-- nil means no map covers it: genuinely off the world, where the border
-- ring is drawn and the camera has no business going.
local function cellAt(ow, wx, wz)
  local map = ow.map
  local cx, cy = math.floor(wx / 16), math.floor(wz / 16)
  if map:inBounds(cx, cy) then return map, cx, cy end
  for _, nb in ipairs(ow.neighbors or {}) do
    if nb.map then
      local nx = math.floor((wx - (nb.ox or 0)) / 16)
      local ny = math.floor((wz - (nb.oy or 0)) / 16)
      if nb.map:inBounds(nx, ny) then return nb.map, nx, ny end
    end
  end
  return nil
end

-- Whether the eye may not stand at this world point. Two refusals, and
-- they are different questions:
--
--   the GROUND is the terrain height field the mesh is actually built from
--   (VoxelScene.groundAt -- the same answer a character stands on), so a
--   ledge, a raised bank or a cliff stops the boom exactly where it stops
--   the geometry, at any pitch.
--
--   the WALKABILITY is the map's own, and stands in for everything built
--   ON the ground that the height field does not describe: house walls,
--   trees, signs, counters. Held to CLEAR above that cell's ground so the
--   short furniture of the world is passed over rather than bumped into.
local function occupied(ow, wx, y, wz)
  local map, cx, cy = cellAt(ow, wx, wz)
  if not map then return true end
  local VoxelScene = V.require("VoxelScene")
  local okG, gh = pcall(VoxelScene.groundAt, map, cx, cy)
  gh = (okG and gh) or 0
  if y < gh + ThirdPerson.PAD then return true end
  local okW, walkable = pcall(function() return map:isWalkableCell(cx, cy) end)
  if okW and not walkable and y < gh + ThirdPerson.CLEAR then return true end
  return false
end

ThirdPerson._occupied = occupied       -- named for the suite

-- How far back along (bx, by, bz) from `pivot` the eye can stand, up to
-- `want`. March at STEP, and when a sample refuses, bisect back into the
-- gap between it and the last clear one -- so the answer is the face's own
-- position rather than the sampling grid's, and walking toward a wall
-- draws the camera in smoothly instead of in four-pixel jerks. PAD comes
-- off whatever survives.
function ThirdPerson.reach(ow, pivot, bx, by, bz, want)
  if not ow or want <= 0 then return math.max(0, want) end
  local function clear(t)
    return not occupied(ow, pivot[1] + bx * t, pivot[2] + by * t,
                        pivot[3] + bz * t)
  end
  local lo = 0
  local steps = math.ceil(want / ThirdPerson.STEP)
  local hi = nil
  for i = 1, steps do
    local t = math.min(want, i * ThirdPerson.STEP)
    if clear(t) then
      lo = t
    else
      hi = t
      break
    end
  end
  if not hi then return want end
  for _ = 1, ThirdPerson.REFINE do
    local mid = (lo + hi) / 2
    if clear(mid) then lo = mid else hi = mid end
  end
  return math.max(0, lo - ThirdPerson.PAD)
end

-- ------- the tick
--
-- Rides FirstPerson.update, which is itself on the pipeline's own update
-- hook, so this runs every frame whatever the rung -- the extension has to
-- keep easing back in after 3RD is left. `blend` is FirstPerson's dive into
-- the head: while it is fully out (the diorama), the extension SNAPS to its
-- target rather than easing, so picking 3RD from an orbit rung is one
-- motion (the dive) rather than two (a dive, then a slide backwards).
function ThirdPerson.update(dt, blend)
  -- the player's own zoom FIRST, so everything below measures itself
  -- against the boom length this frame actually wants. A step is a request
  -- rather than a jump: three notches of wheel should read as one glide.
  local zg = ThirdPerson.zoomGoal
  if ThirdPerson.zoom ~= zg then
    local k = math.min(1, dt / ThirdPerson.ZOOM_TIME)
    local z = ThirdPerson.zoom + (zg - ThirdPerson.zoom) * k
    ThirdPerson.zoom = (math.abs(zg - z) < 1e-4) and zg or z
  end

  local target = ThirdPerson.selected() and 1 or 0
  if (blend or 0) <= 0 then
    ThirdPerson.out = target
    ThirdPerson.len = ThirdPerson.reachFor() * target
    -- and the wanted length with it: place() is what normally maintains it
    -- and it does not run at all while the rig is out of the frame, so a
    -- stale want left here would have the recovery below creeping the boom
    -- back out over a camera that is not on screen
    ThirdPerson.want = ThirdPerson.len
  else
    local step = dt / ThirdPerson.BOOM_TIME
    if ThirdPerson.out < target then
      ThirdPerson.out = math.min(target, ThirdPerson.out + step)
    elseif ThirdPerson.out > target then
      ThirdPerson.out = math.max(target, ThirdPerson.out - step)
    end
  end

  -- the rationed recovery: place() already pulled `len` in to whatever the
  -- world allowed this frame, and this is the only thing that lets it back
  -- out again
  if ThirdPerson.len < ThirdPerson.want then
    ThirdPerson.len = math.min(ThirdPerson.want,
                               ThirdPerson.len + ThirdPerson.RETURN * dt)
  end
end

-- The boom's full length right now, before the world has its say: BOOM at
-- the player's own zoom. Named so the collision march and the shoulder
-- fade measure themselves against the same number.
function ThirdPerson.reachFor()
  return ThirdPerson.BOOM * ThirdPerson.zoom
end

-- ------- the eye
--
-- Where the camera stands, given the pivot the first-person rig would have
-- put the eye at and the unit look direction it would have looked along.
-- Returns the eye and the focus: both slide by the shoulder offset, so the
-- view direction is untouched and only the frame's contents shift.
--
-- With the boom fully in this is exactly the first-person answer, to the
-- pixel -- which is what makes 1ST and 3RD one rig with a number between
-- them rather than two cameras to keep in sync.
function ThirdPerson.place(pivot, lx, ly, lz, focus)
  local e = ThirdPerson.extension()
  if e <= 0 then
    ThirdPerson.want, ThirdPerson.len = 0, 0
    return pivot, focus
  end

  local up = ThirdPerson.PIVOT_LIFT * e
  local orbit = { pivot[1], pivot[2] + up, pivot[3] }

  local want = ThirdPerson.reachFor() * e
  ThirdPerson.want = want
  local room = ThirdPerson.reach(overworld(), orbit, -lx, -ly, -lz, want)
  -- in instantly, out only as fast as update() allows
  ThirdPerson.len = math.min(ThirdPerson.len, room)
  local len = ThirdPerson.len

  -- the rail offset, faded with how much boom actually survived: a camera
  -- squeezed against a wall gives up its shoulder before it gives up its
  -- distance. Right of the look, flat: cross(look, worldUp) normalized,
  -- which for a look of (sin y, *, cos y) is (-cos y, 0, sin y) -- the same
  -- right hand FirstPerson.moveWorld strafes along.
  -- The rail rides the ZOOM as well, so it stays the same fraction of the
  -- frame at every distance: a fixed four pixels would swamp the close shot
  -- and vanish from the wide one.
  local flat = math.sqrt(lx * lx + lz * lz)
  local sx, sz = 0, 0
  if flat > 1e-6 then
    local s = ThirdPerson.SHOULDER * ThirdPerson.zoom * e
              * (len / math.max(want, 1e-6))
    sx, sz = -lz / flat * s, lx / flat * s
  end

  local eye = { orbit[1] - lx * len + sx,
                orbit[2] - ly * len,
                orbit[3] - lz * len + sz }
  local aim = focus and { focus[1] + sx, focus[2] + up, focus[3] + sz }
              or nil
  return eye, aim
end

-- What a shadow signature has to include about the boom: the sun's box is
-- fitted around this camera, so sliding the eye back (or having a wall
-- shove it in) re-fits it even standing still.
function ThirdPerson.signature()
  if ThirdPerson.extension() <= 0 then return "" end
  return math.floor(ThirdPerson.len) .. "/" ..
         math.floor(ThirdPerson.extension() * 64)
end

return ThirdPerson
