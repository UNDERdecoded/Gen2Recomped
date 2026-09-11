-- Voxel world mode: the free-roam camera -- the 1ST and 3RD rungs.
--
-- Every other rung is the same camera at a different pitch: an orbit over
-- the view centre, described by one number. 1ST is a different rig
-- entirely: the eye stands in the player's own head, the view direction is
-- the player's to steer -- mouse, right stick or a touch drag -- and the
-- rig rides the placed-camera seam (Voxel3D.camera) that the staged battle
-- already proved out. Everything downstream of that seam -- the shader
-- uniforms, project(), the sky's vanishing line, the water's lean -- reads
-- eye and focus the same way it always has.
--
-- 3RD is that same rig with the eye pulled back onto a boom behind the
-- player's shoulder (lib/ThirdPerson.lua). Everything in this file is
-- already general over where the eye stands -- the attitude, the look
-- inputs, the move intent, the cards that turn to face the eye -- so the
-- third-person rung is one number applied at the very end of frame(),
-- rather than a second camera to keep in step with this one.
--
-- What this module owns:
--
--   the ATTITUDE   yaw and pitch, fed by whichever look input speaks:
--                  relative mouse motion, the right stick's rate, or a
--                  touch dragged across open screen. All three drive the
--                  same two numbers, so they compose instead of fighting.
--
--   the BLEND      easing between the orbit and the head. Stepping onto
--                  the rung dives the camera from wherever the orbit was
--                  into the player's eyes over half a second; stepping off
--                  flies it back out. Mid-blend the rig is a straight lerp
--                  of the two cameras -- eye, focus, fov, up -- through
--                  the same placed-camera record.
--
--   the MOVE INTENT   the analog vector FreeMove walks the player by,
--                  gathered here because it is made of the same devices:
--                  the left stick's raw axes, the touch d-pad's true
--                  deflection, or the held keys, rotated by this camera's
--                  yaw so "forward" means "where I am looking".
--
-- Deliberately NOT here: movement itself (lib/FreeMove.lua, which owns the
-- collision walk and the grid the game logic still lives on), and the
-- billboard math that faces cards at this eye (VoxelScene, which owns
-- every other card matrix too).
--
-- Everything the module reaches -- the mouse's relative mode, the wrapped
-- love handlers, the touch overlay's hit test -- is pcall-guarded the same
-- way the 3D pass is: headless runs and drivers without a mouse simply
-- never see the input, and the rung falls back to holding the 75-degree
-- orbit.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Mat4 = V.require("Mat4")
local Voxel = V.require("VoxelState")
local Voxel3D = V.require("Voxel3D")
local WorldCurve = V.require("WorldCurve")
local ThirdPerson = V.require("ThirdPerson")

local FirstPerson = {}

-- ------- the rig's numbers
--
-- EYE_HEIGHT stands the eye near the top of the 16px sprite -- the head,
-- not the hat tip -- above the same ground-plus-lift the character card
-- stands on, so surfing bobs and ledge hops carry the view with them.
--
-- FOV is wider than the diorama's ~53 degrees: inside the world, the
-- diorama's lens reads as a keyhole. 65 vertical is the modern-shooter
-- middle ground.
--
-- FOCUS_DIST is short on purpose: the placed-camera branch derives its
-- near plane from |eye - focus| (dist * 0.05), and the eye walks within
-- 2-3 world pixels of a wall face when sliding along it -- a far focus
-- would push the near plane through the wall and clip a hole in it.
FirstPerson.EYE_HEIGHT = 13
FirstPerson.FOV = math.rad(65)
FirstPerson.FOCUS_DIST = 24

-- Pitch limits, in radians below horizontal (positive looks DOWN). The
-- world has no ceiling and the sky's bands sit low, so looking far up
-- shows the void above the gradient; the up-range is clamped tighter than
-- the down-range for that reason, not a technical one.
FirstPerson.PITCH_DOWN = math.rad(70)
FirstPerson.PITCH_UP = -math.rad(50)
FirstPerson.PITCH_DEFAULT = math.rad(10)

-- how long the dive into (and out of) the head takes, in seconds
FirstPerson.BLEND_TIME = 0.45

-- ------- look input tuning
--
-- MOUSE_SENS is radians per relative-mode count -- about 0.18 degrees per
-- count, the conventional shooter default. STICK rates are radians per
-- second at full deflection, with a squared response curve so small
-- deflections aim and full ones turn. TOUCH_TURN is what one full screen
-- width of drag turns, mobile-shooter convention.
FirstPerson.MOUSE_SENS = 0.0032
FirstPerson.STICK_YAW = 3.5
FirstPerson.STICK_PITCH = 2.4
FirstPerson.STICK_DEAD = 0.18
FirstPerson.TOUCH_TURN = 2.2 * math.pi
FirstPerson.MOVE_DEAD = 0.25

-- ------- state
--
-- Yaw is a world bearing: 0 faces south (+Z, the way a resting sprite
-- faces), pi/2 east -- the same convention VoxelScene.YAW uses, so a
-- facing converts to a yaw by table lookup.
FirstPerson.yaw = 0
FirstPerson.pitch = FirstPerson.PITCH_DEFAULT
FirstPerson.blend = 0

-- A multiplier on the first-person field of view, for anything that wants
-- to narrow the lens without owning the rig: 1 is the ordinary 65
-- degrees, and horde mode's iron sights ease it down toward 40 while the
-- player is looking down them (lib/HordeGun). Kept here rather than in
-- the caller because the fov is folded into the orbit blend below, and
-- because signature() has to know -- a lens that narrows while the player
-- stands still still has to re-fit the shadow box.
FirstPerson.fovScale = 1

local wasEngaged = false
local stick = { x = 0, y = 0 }        -- right stick, latest event values
local mouseDX, mouseDY = 0, 0         -- relative counts since last update
local lookTouch = nil                 -- { id, x, y } of the claimed finger
local touchMove = nil                 -- the touch d-pad's analog deflection
local captured = false                -- mouse relative mode engaged by us

-- the placed-camera record this module last handed to Voxel3D, so passes
-- that key behaviour off "is the first-person rig the one drawing" (the
-- billboard yaw, the frame remap) can ask by identity rather than by mode
-- -- the battle's own placed camera must never read as first person
local rig = nil

local FACING_ANGLE = {
  down = 0,
  right = math.pi / 2,
  up = math.pi,
  left = -math.pi / 2,
}
local FACING_ORDER = { "down", "right", "up", "left" }

local function wrapPi(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

local function ease(t)
  return t * t * (3 - 2 * t)
end

-- ------- gates

-- Whether a free-roam rung -- 1ST or 3RD -- is selected and the 3D pass can
-- carry it. Both stand the camera with the player, so both read the look
-- inputs, both walk free, and both turn the cards; how far behind the head
-- the eye ends up is ThirdPerson's business alone.
function FirstPerson.engaged()
  return Voxel.isFreeCam(Voxel.level) and Voxel3D.available()
end

-- Whether the overworld is what the player is looking at: nothing pushed
-- over it, so the buttons are free-roam's. Shared with everything else in
-- the mod that asks the same question of the same stack (CamControl's
-- zooms above all), rather than each restating the pcall.
function FirstPerson.onTop()
  local ok, top, ow = pcall(function()
    local Game = require("src.core.Game")
    return Game.stack and Game.stack:top(), Game.overworld
  end)
  return ok and top ~= nil and top == ow
end

-- Whether first person should be READING the player's inputs right now:
-- engaged, with the overworld on top of the stack (a menu, a dialog or a
-- battle above it owns the buttons, exactly as it does for grid walking).
function FirstPerson.driving()
  return FirstPerson.engaged() and FirstPerson.onTop()
end

-- The right stick's live X, for a camera that is not this one: while a
-- battle is staged the free-roam look is not driving, but the axes are
-- still arriving on the wrap below (which records whatever the rung), and
-- the battle's orbit wants them. Reading them here rather than wrapping
-- the same seam twice.
function FirstPerson.stickX()
  return stick.x or 0
end

function FirstPerson.stickY()
  return stick.y or 0
end

-- ------- lending the look finger out
--
-- A pinch needs both fingers on the screen, and one of them is very likely
-- the finger this module claimed as the look drag. Rather than have the
-- pinch fight for it, CamControl asks for it: dropLook while the gesture
-- runs, reseatLook on whichever finger survives it. Re-seating rather than
-- simply releasing is what stops the view snapping by however far the
-- pinch travelled -- the finger carries on as the look drag from where it
-- now is, which is what it looks like it should do.
function FirstPerson.dropLook()
  lookTouch = nil
end

function FirstPerson.reseatLook(id, x, y)
  if id == nil then lookTouch = nil return end
  lookTouch = { id = id, x = x, y = y }
end

-- The eased blend, 0 at the orbit and 1 in the head.
function FirstPerson.blendEased()
  return ease(FirstPerson.blend)
end

-- The blend, but only while the free-roam pass's own rig is the placed
-- camera. The battle scene places a camera of its own through the same
-- seam, and its cards must keep their stage lean rather than yawing at a
-- first-person eye that is not looking at them.
function FirstPerson.cardBlend()
  if not rig or Voxel3D.camera ~= rig then return 0 end
  return ease(FirstPerson.blend)
end

-- A VR eye stepping into the rig's shoes: the VR pass builds its own
-- placed cameras (one per eye) and hands each one here as it draws, so
-- everything keyed to "the first-person rig is drawing" -- the billboard
-- yaw, the frame remap, the hidden player card -- answers for that eye.
-- In the diorama (blend 0) adoption is inert: cardBlend still reports
-- zero and the cards keep their lean.
function FirstPerson.adoptVReye(record)
  rig = record
end

-- Whether the player's own card should be left out of the camera draw:
-- deep enough into the blend that the card would fill the lens from
-- inside. The sun pass keeps drawing it either way -- a first-person
-- player still throws a shadow on the ground ahead.
--
-- Never while 3RD's boom is genuinely out, whatever the blend: the whole
-- point of a boom is that the character it is booming away from is on
-- screen. (Nor the silhouette that rides the same answer -- seeing your own
-- outline through the building you just walked behind is what a
-- third-person camera owes the player.) A boom SQUEEZED into the head by a
-- wall answers false there and the card comes out again, because at that
-- range it is the first-person problem word for word.
function FirstPerson.hidePlayer()
  if ThirdPerson.showsPlayer() then return false end
  return FirstPerson.cardBlend() > 0.9
end

-- ------- attitude

-- Apply a look delta, in radians. Everything that turns the head funnels
-- through here, so the clamps live once.
function FirstPerson.lookBy(dyaw, dpitch)
  FirstPerson.yaw = wrapPi(FirstPerson.yaw + dyaw)
  FirstPerson.pitch = math.max(FirstPerson.PITCH_UP,
                       math.min(FirstPerson.PITCH_DOWN,
                                FirstPerson.pitch + dpitch))
end

-- A bearing as one of the grid's four directions -- the 45-degree
-- quantisation every facing in this file is made with, in one place so the
-- compass, the body and the card frames can never disagree about where a
-- boundary is.
local function facingOf(a)
  local s, c = math.sin(a), math.cos(a)
  if math.abs(s) > math.abs(c) then
    return s > 0 and "right" or "left"
  end
  return c > 0 and "down" or "up"
end

-- The view direction's flat compass facing, for everything that still
-- thinks in the grid's four directions: the cell A interacts with, the
-- sprite the sun sees, the direction a blocked slide bonks in.
function FirstPerson.compassFacing()
  return facingOf(FirstPerson.yaw)
end

-- Which way the BODY points, as a continuous world bearing, given the
-- world-space direction it is walking (0, 0 while standing). In the head,
-- the body is the head: you face what you look at. On the boom you can see
-- yourself, and a character sliding sideways while facing the lens reads as
-- a bug rather than as a strafe -- so a walking body turns to face its own
-- travel, and a standing one comes back round to the camera's bearing,
-- which is the one A talks along.
function FirstPerson.bodyBearing(wx, wz)
  if ThirdPerson.extended() and wx and wz and (wx ~= 0 or wz ~= 0) then
    return math.atan2(wx, wz)
  end
  return FirstPerson.yaw
end

-- The same answer as one of the four facings, which is what the grid game
-- (and the sprite sheet) reasons in.
function FirstPerson.bodyFacing(wx, wz)
  return facingOf(FirstPerson.bodyBearing(wx, wz))
end

-- ------- the body's live bearing
--
-- The bearing the player's own body is actually pointing along RIGHT NOW,
-- or nil whenever the free walk is not the thing pointing it (a scripted
-- move, a cutscene, the grid walk with the rung off). FreeMove maintains
-- it; only the player's own card reads it.
--
-- It exists because the card's frame is chosen by the angle BETWEEN the
-- body and the eye, and quantising the body to a compass direction first
-- throws away exactly the precision that choice needs. A standing body is
-- pointed along the camera's own yaw, so the true angle between them is a
-- flat 180 degrees and the card should show its back and nothing else --
-- but snap the body to one of four directions on the game tick, then
-- measure it against an eye that has kept turning since, and the pair can
-- read as 135 degrees and pick the PROFILE frame instead. Spin the camera
-- fast and the character flicks to a mirrored side view for a frame or
-- two. Keeping the bearing continuous gives the measurement a full 45
-- degrees of slack before it can cross a boundary, which no frame's worth
-- of turning comes close to spending.
FirstPerson.bodyYaw = nil

-- Point the body along the direction it is walking (or, standing, along
-- the camera): records the continuous bearing and hands back the compass
-- facing the caller wants for p.facing.
function FirstPerson.pointBody(wx, wz)
  FirstPerson.bodyYaw = FirstPerson.bodyBearing(wx, wz)
  return facingOf(FirstPerson.bodyYaw)
end

-- Hand the body back to whatever else is turning it.
function FirstPerson.releaseBody()
  FirstPerson.bodyYaw = nil
end

-- The unit look direction, and its flat (ground-plane) part.
local function lookDir()
  local cp = math.cos(FirstPerson.pitch)
  return math.sin(FirstPerson.yaw) * cp,
         -math.sin(FirstPerson.pitch),
         math.cos(FirstPerson.yaw) * cp
end

function FirstPerson.lookFlat()
  return math.sin(FirstPerson.yaw), math.cos(FirstPerson.yaw)
end

-- ------- billboards seen from inside the world
--
-- The diorama's cards face south and lean back by the camera's pitch --
-- correct for a camera that always stands south. An eye that can stand
-- ANYWHERE sees a south-facing card edge-on from the east, so in first
-- person every card yaws about its feet to face the eye (cylindrical
-- billboarding: upright, never tipping). VoxelScene blends its matrices
-- between the two by cardBlend.

-- The yaw that turns a card's south-facing normal toward the eye.
function FirstPerson.cardYaw(wx, wz)
  local eye = rig and rig.eye
  if not eye then return 0 end
  local dx, dz = eye[1] - wx, eye[3] - wz
  if dx * dx + dz * dz < 1e-9 then return 0 end
  return math.atan2(dx, dz)
end

-- Which of the four sprite frames a body at world bearing `phi` shows an
-- eye looking at (wx, wz): the bearing rotated into the viewer's own frame,
-- quantised. nil when there is no rig to be seen from.
local function frameFor(phi, wx, wz)
  local eye = rig and rig.eye
  if not (eye and phi) then return nil end
  local dx, dz = eye[1] - wx, eye[3] - wz
  if dx * dx + dz * dz < 1e-9 then return nil end
  local rel = wrapPi(phi - math.atan2(dx, dz))
  local idx = math.floor((rel + math.pi / 4) / (math.pi / 2)) % 4
  return FACING_ORDER[idx + 1]
end

-- Which of the four sprite frames an entity shows THIS eye: its facing
-- rotated into the viewer's own frame, quantised. The flat game's frames
-- are "how this pose looks from the south", so the apparent facing is the
-- pose rotated by where the viewer actually stands -- walk behind an NPC
-- and you see their back, circle to their flank and you see the profile,
-- exactly as the four frames Gen 1 drew intend.
--
-- An NPC's facing IS one of the four and nothing finer, so this is the
-- whole story for everyone in the world except the one body the camera is
-- attached to -- see playerFacing.
function FirstPerson.apparentFacing(facing, wx, wz)
  return frameFor(FACING_ANGLE[facing], wx, wz) or facing
end

-- The PLAYER's own card, which is the one case where the body's bearing is
-- known to better than a compass point (bodyYaw, above) -- and the one case
-- where it matters, because the eye is derived FROM that bearing rather
-- than independent of it. Measured continuously, a standing body reads as
-- a flat 180 degrees from its own camera and shows its back, steadily,
-- however fast the camera is spun. Falls back to the four-direction answer
-- whenever something other than the free walk is turning the body.
function FirstPerson.playerFacing(facing, wx, wz)
  return frameFor(FirstPerson.bodyYaw, wx, wz)
         or FirstPerson.apparentFacing(facing, wx, wz)
end

-- ------- the move intent
--
-- The analog vector FreeMove walks by, in CAMERA space: mx strafes (+
-- right), mz advances (+ forward). Whichever device is actually deflected
-- answers -- the left stick's raw axes first (the engine quantises them to
-- a d-pad; the raw pair is the analog truth), then a touch d-pad finger,
-- then the held keys. Magnitude caps at 1.
function FirstPerson.moveVector()
  local ok, Game = pcall(require, "src.core.Game")
  local input = ok and Game.input or nil

  local ax = input and input.stickAxis or nil
  if ax then
    local mag = math.sqrt(ax.x * ax.x + ax.y * ax.y)
    if mag > FirstPerson.MOVE_DEAD then
      local t = math.min(1, (mag - FirstPerson.MOVE_DEAD)
                            / (1 - FirstPerson.MOVE_DEAD))
      return ax.x / mag * t, -ax.y / mag * t
    end
  end

  if touchMove then
    local mag = math.sqrt(touchMove.x * touchMove.x
                          + touchMove.y * touchMove.y)
    if mag > FirstPerson.MOVE_DEAD then
      local t = math.min(1, mag)
      return touchMove.x / mag * t, -touchMove.y / mag * t
    end
  end

  if input then
    local mx = (input:isDown("right") and 1 or 0)
               - (input:isDown("left") and 1 or 0)
    local mz = (input:isDown("up") and 1 or 0)
               - (input:isDown("down") and 1 or 0)
    if mx ~= 0 or mz ~= 0 then
      local mag = math.sqrt(mx * mx + mz * mz)
      return mx / mag, mz / mag
    end
  end
  return 0, 0
end

-- Rotate a camera-space move into world space: forward is the flat look
-- direction, strafe-right is its right hand. (cross(forward, up) with
-- forward = (sin y, 0, cos y) and up = +Y lands right on (-cos y, 0,
-- sin y): face south and your right hand points west.)
function FirstPerson.moveWorld(mx, mz)
  local s, c = math.sin(FirstPerson.yaw), math.cos(FirstPerson.yaw)
  return -c * mx + s * mz, s * mx + c * mz
end

-- ------- the tick

-- Runs from the pipeline's update hook, every frame whatever the level --
-- the same tick VoxelState eases the orbit on. Owns the blend, the mouse
-- capture lifecycle, and the frame's stick-rate look.
function FirstPerson.update(dt)
  local engagedNow = FirstPerson.engaged()

  -- entering the rung: the head starts looking the way the sprite faces,
  -- pitched gently down -- the reading pose of the flat game
  if engagedNow and not wasEngaged then
    local ok, facing = pcall(function()
      local Game = require("src.core.Game")
      return Game.overworld and Game.overworld.player
             and Game.overworld.player.facing
    end)
    FirstPerson.yaw = (ok and FACING_ANGLE[facing]) or 0
    FirstPerson.pitch = FirstPerson.PITCH_DEFAULT
  end
  wasEngaged = engagedNow

  -- the blend, held at flat until there is terrain to dive into -- the
  -- same wait Voxel.update keeps for the orbit tween, for the same reason
  local target = engagedNow and 1 or 0
  if target > FirstPerson.blend and FirstPerson.blend == 0
     and not Voxel.ready then
    target = 0
  end
  local step = dt / FirstPerson.BLEND_TIME
  if FirstPerson.blend < target then
    FirstPerson.blend = math.min(target, FirstPerson.blend + step)
  elseif FirstPerson.blend > target then
    FirstPerson.blend = math.max(target, FirstPerson.blend - step)
  end
  if FirstPerson.blend <= 0 and rig then
    -- fully out: let go of the placed camera (unless a battle already
    -- swapped its own in, which is not ours to clear)
    if Voxel3D.camera == rig then Voxel3D.camera = nil end
    rig = nil
  end

  -- the boom, on the same tick and for the same reason: it has to keep
  -- easing after 3RD is left, and it needs the blend to know whether a
  -- change of rung is a SLIDE (already inside the world, 1ST <-> 3RD) or
  -- part of the dive in from the orbit, which carries the eye anyway
  ThirdPerson.update(dt, FirstPerson.blend)

  -- mouse capture follows engagement: captured whenever the rung is on and
  -- the window has focus, released the moment either ends. Checked against
  -- the live mode rather than toggled on edges, so a capture lost to the
  -- OS (alt-tab) re-arms itself on the next focused frame.
  local wantCapture = engagedNow
  if wantCapture and love.window and love.window.hasFocus then
    local okF, focus = pcall(love.window.hasFocus)
    wantCapture = okF and focus or false
  end
  if love.mouse and love.mouse.setRelativeMode then
    local okM, isRel = pcall(love.mouse.getRelativeMode)
    if okM and isRel ~= wantCapture then
      pcall(love.mouse.setRelativeMode, wantCapture)
    end
    captured = wantCapture
  end

  local driving = FirstPerson.driving()

  -- The mouse's counts, accumulated by the wrapped handler since the last
  -- tick; dropped unread while something else owns the screen.
  --
  -- The yaw sign is NEGATED, here and in every look input below: yaw grows
  -- south -> east -> north (the world runs +X east, +Z south, and the
  -- direction is (sin yaw, cos yaw)), which seen from behind the eye is a
  -- LEFT turn -- so "move the mouse right, look right" means subtracting.
  local dx, dy = mouseDX, mouseDY
  mouseDX, mouseDY = 0, 0
  if driving and (dx ~= 0 or dy ~= 0) then
    FirstPerson.lookBy(-dx * FirstPerson.MOUSE_SENS,
                       dy * FirstPerson.MOUSE_SENS)
  end

  -- the right stick is a rate: radians per second, squared response so
  -- the first half of the throw aims and the rest turns
  if driving then
    local rx, ry = stick.x, stick.y
    local function curve(v)
      local a = math.abs(v)
      if a < FirstPerson.STICK_DEAD then return 0 end
      a = (a - FirstPerson.STICK_DEAD) / (1 - FirstPerson.STICK_DEAD)
      return (v < 0 and -1 or 1) * a * a
    end
    local cy, cp = curve(rx), curve(ry)
    if cy ~= 0 or cp ~= 0 then
      -- negated yaw for the same reason as the mouse above
      FirstPerson.lookBy(-cy * FirstPerson.STICK_YAW * dt,
                         cp * FirstPerson.STICK_PITCH * dt)
    end
  end
end

-- ------- the rig itself

-- The orbit camera's eye/focus/fov/up for the frame's centre -- the same
-- arithmetic Voxel3D.viewProjection runs, restated here because the blend
-- needs both ends as DATA. Kept textually tiny so the two cannot drift:
-- focus on the centre, eye FOCAL*vh away at the pitch, up perpendicular
-- in the YZ plane.
local function orbitRig(cx, cy, vh)
  local a = Voxel.angle
  local dist = Voxel.FOCAL * vh
  return { cx, dist * math.cos(a), cy + dist * math.sin(a) },
         { cx, 0, cy },
         2 * math.atan(1 / (2 * Voxel.FOCAL)),
         { 0, math.sin(a), -math.cos(a) }
end

local lastEye = nil                   -- frozen head pose for player-less frames

-- Build this frame's placed camera and hand it to Voxel3D, plus the scene
-- centre the curve and the depth reference should use. `me` is the
-- player's posed entry (px, py, gh, lift) or nil (a Fly animation), and
-- (cx, cy) the orbit's own view centre.
--
-- Returns nil with the blend fully out, which is the caller's signal to
-- leave the orbit in charge.
function FirstPerson.frame(me, cx, cy, vw, vh)
  local b = FirstPerson.blend
  if b <= 0 then
    if rig and Voxel3D.camera == rig then Voxel3D.camera = nil end
    rig = nil
    return nil
  end
  local e = ease(b)

  local head
  if me then
    head = { me.px + 8,
             (me.gh or 0) + (me.lift or 0) + FirstPerson.EYE_HEIGHT,
             me.py + 8 }
    lastEye = head
  else
    head = lastEye or { cx, FirstPerson.EYE_HEIGHT, cy }
  end
  local lx, ly, lz = lookDir()
  local fpFocus = { head[1] + lx * FirstPerson.FOCUS_DIST,
                    head[2] + ly * FirstPerson.FOCUS_DIST,
                    head[3] + lz * FirstPerson.FOCUS_DIST }

  -- 3RD: the eye walks back off the head along the very direction it looks,
  -- as far as the world allows. Fully in (1ST, and every frame of the
  -- diorama) this hands back the head and the focus untouched, so the two
  -- rungs are one rig with one number between them.
  local camEye, camFocus = ThirdPerson.place(head, lx, ly, lz, fpFocus)

  local oEye, oFocus, oFov, oUp = orbitRig(cx, cy, vh)
  local function mix(p, q)
    return { p[1] + (q[1] - p[1]) * e,
             p[2] + (q[2] - p[2]) * e,
             p[3] + (q[3] - p[3]) * e }
  end
  local up = mix(oUp, { 0, 1, 0 })
  local ul = math.sqrt(up[1] * up[1] + up[2] * up[2] + up[3] * up[3])
  if ul > 1e-6 then up[1], up[2], up[3] = up[1] / ul, up[2] / ul, up[3] / ul
  else up = { 0, 1, 0 } end

  -- the world curve eases out with the blend: standing inside the world,
  -- the bend that sells the diorama reads as the ground falling away. A
  -- true zero (curve declined) needs the field present -- nil would let
  -- Voxel3D fall back to the setting
  local k = WorldCurve.k(vh) * (1 - e)

  rig = {
    eye = mix(oEye, camEye),
    focus = mix(oFocus, camFocus),
    fov = oFov + (FirstPerson.FOV - oFov) * e,
    up = up,
    curve = k,
  }
  Voxel3D.camera = rig

  -- the scene centre walks from the orbit's view centre to the head, so
  -- the curve's focus, the depth reference and the glint's travel follow
  -- the camera that is actually in charge
  local sx = cx + (head[1] - cx) * e
  local sy = cy + (head[3] - cy) * e
  return rig, sx, sy
end

-- Where the shadow pass should centre its box: pushed along the flat look
-- so the fitted frustum -- built for an orbit that always looks north --
-- covers the ground THIS camera sees. The push is strongest looking
-- south (the direction the orbit's box barely reaches) and scales with
-- the blend.
function FirstPerson.shadowCenter(sx, sy, vh)
  local e = FirstPerson.cardBlend()
  if e <= 0 then return sx, sy end
  local fx, fz = FirstPerson.lookFlat()
  local ShadowMap = V.require("ShadowMap")
  local cap = (ShadowMap.FAR_CAP or 2.5) * vh
  return sx + fx * 0.6 * vh * e,
         sy + fz * (fz > 0 and (cap - vh * 0.5) or vh * 0.4) * e
end

-- The first-person facts a shadow signature has to include: the sun's
-- box is fitted around this camera, so turning the head or walking the
-- blend has to re-fit it even standing still.
function FirstPerson.signature()
  local b = FirstPerson.blend
  if b <= 0 then return "" end
  return table.concat({
    math.floor(b * 64),
    math.floor(FirstPerson.yaw * 64),
    math.floor(FirstPerson.pitch * 64),
    -- and how far back the boom stands the eye: a wall shortening it moves
    -- the camera the sun's box is fitted around, standing still or not
    ThirdPerson.signature(),
  }, ",")
end

-- ------- input capture
--
-- The seams: relative mouse motion has no Game handler at all (the
-- engine's love.mousemoved only feeds the mouse-as-touch debug path), the
-- right stick's axes are explicitly ignored by Input, and a touch
-- anywhere off the overlay's controls dies in TouchControls. Each wrap
-- forwards everything it does not claim, and claims only while first
-- person is actually driving -- so with the rung off, every byte flows
-- exactly where it always did.

local installed = false

function FirstPerson.install()
  if installed then return end
  installed = true

  local Game = require("src.core.Game")

  -- ------- right stick
  do
    local inner = Game.gamepadaxis
    function Game:gamepadaxis(joystick, axis, value)
      if axis == "rightx" then stick.x = value
      elseif axis == "righty" then stick.y = value end
      return inner(self, joystick, axis, value)
    end
  end
  -- generic (non-gamepad) sticks: axes 1/2 are the left stick by SDL
  -- convention and Input already claims them; 3/4 are the usual right
  -- pair on the same class of device. Real gamepads are excluded -- they
  -- already spoke through the mapped rightx/righty above, and their RAW
  -- axis 3 is as likely a trigger as a stick.
  --
  -- Two more exclusions, both learned the hard way on Android, where this
  -- wrap runs BEFORE the engine's own generic-joystick guards:
  --
  --   the accelerometer arrives as a joystick named for what it is, with
  --   gravity pinning an axis well past any deadzone -- the same device
  --   Game:joystickaxis refuses for movement (#459), refused here by the
  --   same name test, or the view spins on its own the moment 1ST opens.
  --
  --   and a raw axis is only BELIEVED after it has been seen near centre
  --   once. A stick at rest sits at zero, so a real one earns trust with
  --   its first touch; a gravity-pinned sensor axis or a trigger resting
  --   at an extreme never centres and so never steers the look.
  local function isAccelerometer(joystick)
    local ok, name = pcall(function() return joystick:getName() end)
    return ok and type(name) == "string"
           and name:lower():find("accelerometer", 1, true) ~= nil
  end
  local rawCentred = {}
  do
    local inner = Game.joystickaxis
    function Game:joystickaxis(joystick, axis, value)
      local mapped = joystick and joystick.isGamepad and joystick:isGamepad()
      if not mapped and (axis == 3 or axis == 4)
         and not isAccelerometer(joystick) then
        if math.abs(value) < 0.3 then rawCentred[axis] = true end
        if rawCentred[axis] then
          if axis == 3 then stick.x = value else stick.y = value end
        end
      end
      return inner(self, joystick, axis, value)
    end
  end

  -- ------- mouse
  --
  -- love.mousemoved rather than a Game method, because the engine has no
  -- Game:mousemoved to wrap -- the callback in the project's main.lua is
  -- the one place relative counts arrive. Claimed only while captured;
  -- pass-through otherwise, including the mouse-as-touch path.
  do
    local inner = love.mousemoved
    love.mousemoved = function(x, y, dx, dy, istouch)
      if captured and not istouch then
        mouseDX = mouseDX + (dx or 0)
        mouseDY = mouseDY + (dy or 0)
        return
      end
      if inner then return inner(x, y, dx, dy, istouch) end
    end
  end
  -- While the mouse is captured there is no cursor to click UI with, so
  -- the buttons become GB buttons: left is A, right is B -- through the
  -- overlay's own press path, which a rebind can never detach. What WE
  -- pressed is remembered per button, so the release always reaches the
  -- overlay even if the capture ended while the button was down --
  -- otherwise a click that outlives the rung strands A held forever.
  --
  -- HORDE MODE re-reads the same two buttons as a weapon: left fires,
  -- right holds the sights. Claimed BEFORE the A/B mapping below rather
  -- than on top of it, so a click during the mode never also lands as a
  -- GB button -- otherwise the A that ends the GAME OVER card would be
  -- spent by the shot that ended the run.
  local mouseHeld = {}
  local MOUSE_BTN = { [1] = "a", [2] = "b" }
  local function hordeMouse(button, down)
    local Horde = V.require("Horde")
    if not Horde.playing() then return false end
    if button == 1 then
      if down then V.require("HordeGun").fire() end
      return true
    elseif button == 2 then
      V.require("HordeGun").setAds(down)
      return true
    end
    return false
  end
  do
    local inner = love.mousepressed
    love.mousepressed = function(x, y, button, istouch, presses)
      if captured and not istouch and hordeMouse(button, true) then return end
      if captured and not istouch and MOUSE_BTN[button] then
        local Input = require("src.core.Input")
        mouseHeld[button] = true
        Input:overlayPressed(MOUSE_BTN[button])
        return
      end
      if inner then return inner(x, y, button, istouch, presses) end
    end
  end
  do
    local inner = love.mousereleased
    love.mousereleased = function(x, y, button, istouch, presses)
      -- a release always reaches whoever owns the press: the horde's
      -- aim-hold has to let go even if the mode ended mid-click
      if not mouseHeld[button] and hordeMouse(button, false) then return end
      if mouseHeld[button] then
        local Input = require("src.core.Input")
        mouseHeld[button] = nil
        Input:overlayReleased(MOUSE_BTN[button])
        return
      end
      if inner then return inner(x, y, button, istouch, presses) end
    end
  end

  -- ------- touch
  --
  -- A finger on open screen -- not on the overlay's d-pad or buttons --
  -- becomes the look drag. One finger owns the look at a time; every
  -- other touch flows to TouchControls untouched, so a thumb can drag the
  -- view while the other walks the d-pad. That d-pad finger is also read
  -- back ANALOG here: TouchControls quantises it to four directions for
  -- the grid game, but the deflection it quantised is exactly the move
  -- vector a free walk wants.
  local TouchControls = require("src.core.TouchControls")

  local function dpadVector(x, y)
    local ok, v = pcall(function()
      local L = TouchControls:layout()
      local dz = L.dpad
      local half = dz.w * 0.65
      return { x = math.max(-1, math.min(1, (x - dz.cx) / half)),
               y = math.max(-1, math.min(1, (y - dz.cy) / half)) }
    end)
    return ok and v or nil
  end

  do
    local inner = Game.touchpressed
    function Game:touchpressed(id, x, y)
      if FirstPerson.driving() then
        local onControl = nil
        pcall(function() onControl = TouchControls:hitTest(x, y) end)
        if not onControl and not lookTouch then
          -- HORDE MODE: a tap on open screen is a SHOT, fired on the press
          -- rather than on a release that turned out not to be a drag --
          -- a shooter that waits to find out whether you meant it is a
          -- shooter that misses. The same finger still becomes the look
          -- drag below, so aiming and firing are one gesture.
          if V.require("Horde").playing() then
            V.require("HordeGun").fire()
          end
          lookTouch = { id = id, x = x, y = y }
          return
        end
        inner(self, id, x, y)
        if onControl == "dpad" and TouchControls.dpadTouch == id then
          touchMove = dpadVector(x, y)
        end
        return
      end
      return inner(self, id, x, y)
    end
  end
  do
    local inner = Game.touchmoved
    function Game:touchmoved(id, x, y)
      if lookTouch and lookTouch.id == id then
        local w = 1280
        pcall(function() w = love.graphics.getWidth() end)
        local per = FirstPerson.TOUCH_TURN / math.max(320, w)
        if FirstPerson.driving() then
          -- negated yaw for the same reason as the mouse (see update):
          -- drag right, look right, the mobile-shooter convention
          FirstPerson.lookBy(-(x - lookTouch.x) * per,
                             (y - lookTouch.y) * per)
        end
        lookTouch.x, lookTouch.y = x, y
        return
      end
      if touchMove and TouchControls.dpadTouch == id then
        touchMove = dpadVector(x, y) or touchMove
      end
      return inner(self, id, x, y)
    end
  end
  do
    local inner = Game.touchreleased
    function Game:touchreleased(id, x, y)
      if lookTouch and lookTouch.id == id then
        lookTouch = nil
        return
      end
      if TouchControls.dpadTouch == id then touchMove = nil end
      return inner(self, id, x, y)
    end
  end

  -- a reset that drops held input state drops ours with it
  do
    local inner = Game.focus
    function Game:focus(f)
      lookTouch, touchMove = nil, nil
      stick.x, stick.y = 0, 0
      mouseDX, mouseDY = 0, 0
      return inner(self, f)
    end
  end
  -- a disconnected controller cannot send the centering event for whatever
  -- its stick last held -- the engine drops all input state here, and the
  -- look rate (plus the raw axes' earned trust) goes with it
  do
    local inner = Game.joystickremoved
    function Game:joystickremoved(joystick)
      stick.x, stick.y = 0, 0
      rawCentred[3], rawCentred[4] = nil, nil
      return inner(self, joystick)
    end
  end
end

return FirstPerson
