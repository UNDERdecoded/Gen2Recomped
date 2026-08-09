-- The player's own camera controls: zoom everywhere, and the battle's orbit.
--
-- This mod has four cameras, and by the time a wheel notch arrives they all
-- want it. So one module owns the INPUTS and answers the only question that
-- matters -- which camera is this aimed at -- rather than each camera
-- growing its own wheel handler and racing the others for the event:
--
--   a staged battle      the camera the fight is shot with (BattleCam): the
--                        wheel and Q/E work its lens, and the right stick,
--                        a drag or the mouse walk it around the arena.
--
--   the 3RD rung         the boom behind the player's shoulder
--                        (ThirdPerson): the wheel, Q/E and a pinch let it
--                        out and pull it in.
--
--   an orbit rung        the engine's own survey zoom, which the wheel has
--                        always driven -- so here the module mostly gets
--                        out of the way, and only ADDS the two keys and the
--                        pinch that the engine has no handler for.
--
--   the 1ST rung         nothing. The eye is in the player's head; there is
--                        no distance to change, and a pinch there would
--                        silently wind the survey zoom for whenever they
--                        stepped back out. Inputs pass through untouched.
--
-- Every claim is answered by a GATE rather than by a mode flag, and every
-- wrap forwards whatever it does not claim -- so with voxel mode off, and
-- on every screen that is not the overworld or a battle, each byte flows
-- exactly where it always did.
--
-- Installed AFTER FirstPerson (see main.lua), which makes these wraps the
-- outer ones: a battle's controls get first refusal on the mouse and the
-- touch screen, which is right, because while a fight is staged the
-- free-roam look is not driving anyway.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Voxel = V.require("VoxelState")
local Voxel3D = V.require("Voxel3D")
local FirstPerson = V.require("FirstPerson")
local ThirdPerson = V.require("ThirdPerson")
local BattleCam = V.require("BattleCam")

local CamControl = {}

-- ------- tuning
--
-- PINCH_SLACK is how far apart two fingers must travel, as a ratio of
-- their starting gap, before the gesture counts as a pinch at all -- below
-- it a two-finger tap wobbles rather than zooms.
--
-- SURVEY_PINCH is how many of the engine's integer survey steps one
-- doubling of the finger gap is worth. The survey ladder is coarse (whole
-- pixels per world pixel), so a pinch has to be geared down or the first
-- centimetre of travel crosses the whole range.
CamControl.PINCH_SLACK = 0.02
CamControl.SURVEY_PINCH = 2.2

-- ------- gates

-- A fight staged on the map, drawn and on screen. Asked of the shot rather
-- than of the battle state, because the shot is exactly "there is a 3D
-- battle in front of the player right now" -- with 3D-BTL off, or on a map
-- with no arena, the engine's own flat battle screen is up and its camera
-- is not ours to steer.
-- BACK SPRITES also closes it, through BattleCam.steerable: that setting
-- nails the player's own mon to the GB's slot on the menu while the foe
-- stands out on the map, and no camera angle holds a composition that is
-- half frame and half world (see BattleCam.steerable, which is where the
-- reasoning lives and which the RIG answers to as well -- so a stored
-- angle from before the setting was switched on stands down with it).
local function battleLive()
  local ok, shot = pcall(function()
    return V.require("OverworldBattle").shot()
  end)
  return (ok and shot and BattleCam.steerable) and true or false
end

CamControl.battleLive = battleLive

-- The free-roam overworld, with the 3D pass carrying it: the gate every
-- zoom that is not a battle's answers to.
local function roaming()
  return Voxel.active() and Voxel3D.available() and FirstPerson.onTop()
end

-- Which camera a zoom is aimed at: "battle", "boom", "survey", or nil for
-- nothing that zooms (1ST, or a screen with no camera of ours behind it).
function CamControl.zoomTarget()
  if battleLive() then return "battle" end
  if not roaming() then return nil end
  if Voxel.isThirdPerson(Voxel.level) then return "boom" end
  if Voxel.isFirstPerson(Voxel.level) then return nil end
  return "survey"
end

-- ------- zoom
--
-- `notches` is signed the way every zoom in this file is: POSITIVE pulls
-- the camera OUT. The engine's own survey step runs the other way, and is
-- negated at the one place it is called rather than everywhere else being
-- bent to match it.
--
-- Returns true when the input was ours, which is what tells a wrap to stop
-- rather than forward.

local function surveyStep(notches)
  local ok = pcall(function()
    local Game = require("src.core.Game")
    Game:zoomStep(notches > 0 and -1 or 1)
  end)
  return ok
end

function CamControl.zoomBy(notches)
  if not notches or notches == 0 then return false end
  local target = CamControl.zoomTarget()
  if target == "battle" then
    BattleCam.stepZoom(notches)
    return true
  elseif target == "boom" then
    ThirdPerson.stepZoom(notches)
    return true
  elseif target == "survey" then
    -- one call per notch: the engine's ladder is integer rungs, and a
    -- wheel spun hard should climb them all rather than one
    for _ = 1, math.min(8, math.abs(notches)) do surveyStep(notches) end
    return true
  end
  return false
end

-- A pinch's own scale: > 1 is fingers spreading, which means zoom IN
-- (pull the world closer), which is a NEGATIVE notch count.
function CamControl.pinchBy(factor)
  if not (factor and factor > 0) then return false end
  local target = CamControl.zoomTarget()
  if target == "boom" then
    return ThirdPerson.scaleZoom(1 / factor)
  elseif target == "battle" then
    -- battles take a pinch too: the wheel and the keys reach this camera
    -- and a phone has neither, so without it the lens would be the one
    -- control a touch screen could not work
    return BattleCam.stepZoom(math.log(1 / factor)
                              / math.log(BattleCam.ZOOM_STEP))
  elseif target == "survey" then
    CamControl.surveyAccum = (CamControl.surveyAccum or 0)
      + math.log(factor) / math.log(2) * CamControl.SURVEY_PINCH
    local moved = false
    while CamControl.surveyAccum >= 1 do
      CamControl.surveyAccum = CamControl.surveyAccum - 1
      surveyStep(-1)
      moved = true
    end
    while CamControl.surveyAccum <= -1 do
      CamControl.surveyAccum = CamControl.surveyAccum + 1
      surveyStep(1)
      moved = true
    end
    return moved
  end
  return false
end

CamControl.surveyAccum = 0

-- ------- the battle's orbit
--
-- Only ever the battle's: the free-roam rungs already steer their own look
-- through FirstPerson, and these wraps sit outside it precisely so a fight
-- can borrow the same devices without either of them growing a mode check.

-- The right stick, read as a rate off the axes FirstPerson's own wrap is
-- already recording (it records whatever the rung, so a battle can read
-- them without a second wrap on the same seam). Ticked from
-- OverworldBattle.update, which runs whatever is on top of the stack.
--
-- X walks the shot round the arena, Y raises the seat. The Y is NEGATED:
-- a stick pushed forward reads as negative on SDL's axis, and pushing
-- forward should send the camera UP and over -- the same "push the camera
-- where you want it" the drag and the mouse below use.
function CamControl.tick(dt)
  if not battleLive() then return end
  local x, y = FirstPerson.stickX(), FirstPerson.stickY()
  if x ~= 0 then BattleCam.stickOrbit(x, dt) end
  if y ~= 0 then BattleCam.stickPitch(-y, dt) end
end

-- ------- the wraps

local installed = false

function CamControl.install()
  if installed then return end
  installed = true

  local Game = require("src.core.Game")

  -- ------- the wheel
  --
  -- The engine's own handler is the survey zoom, so the wrap only has to
  -- take the notch away when some OTHER camera wants it; "survey" falls
  -- through to exactly the code that always ran.
  do
    local inner = Game.wheelmoved
    function Game:wheelmoved(dx, dy)
      local target = CamControl.zoomTarget()
      if (target == "battle" or target == "boom") and dy and dy ~= 0 then
        CamControl.zoomBy(dy > 0 and -1 or 1)
        return
      end
      return inner(self, dx, dy)
    end
  end

  -- ------- the stick clicks
  --
  -- Q and E, on the pad: the left stick's click pulls the camera out and the
  -- right stick's pulls it in. A controller has no wheel and no number row,
  -- and the two clicks are the only buttons a Gen 1 pad layout leaves free
  -- (SELECT already walks the angle ladder).
  --
  -- Claimed for the two cameras a pad player can actually be looking at
  -- while pressing them -- the third-person boom and a staged battle's lens
  -- -- and forwarded untouched everywhere else, so a player who has rebound
  -- either click keeps it on every other screen, a rebind capture included.
  -- Not on the orbit rungs: the survey zoom has the OPTIONS row and the
  -- wheel already, and taking a pad button for it would be taking one from
  -- a player who never asked.
  local CLICK_ZOOMS = { boom = true, battle = true }
  do
    local inner = Game.gamepadpressed
    function Game:gamepadpressed(joystick, button)
      if (button == "leftstick" or button == "rightstick")
         and CLICK_ZOOMS[CamControl.zoomTarget() or ""] then
        CamControl.zoomBy(button == "leftstick" and 1 or -1)
        return
      end
      return inner(self, joystick, button)
    end
  end

  -- ------- the mouse
  --
  -- Battle only. The free-roam look already owns relative motion through
  -- FirstPerson's own wrap (this one is outside it, so what is claimed here
  -- never reaches it) and a fight is exactly when that look is not driving.
  --
  -- Bare motion, no button held: moving the mouse moves the shot.
  --
  -- Each event's contribution is CLAMPED, though, because not every motion
  -- event is a hand moving. The pointer entering the window, a warp back to
  -- centre, an alt-tab -- each arrives as ONE event carrying the whole
  -- distance from wherever the cursor was last seen, and in testing that
  -- was a couple of hundred counts: enough to swing the shot a quarter of
  -- the way to side-on before the player had touched anything. A real hand
  -- delivers its travel as a stream of small events and is unaffected; a
  -- teleport delivers it as one and is cut down to the size of a flick.
  local MOUSE_STEP = 40
  local function clamp(v)
    return math.max(-MOUSE_STEP, math.min(MOUSE_STEP, v or 0))
  end
  do
    local inner = love.mousemoved
    love.mousemoved = function(x, y, dx, dy, istouch)
      if battleLive() and not istouch then
        -- dy is NEGATED for the same reason the stick's is: moving the
        -- mouse away from you sends the camera up and over
        if dx and dx ~= 0 then BattleCam.mouseOrbit(clamp(dx)) end
        if dy and dy ~= 0 then BattleCam.mousePitch(-clamp(dy)) end
        -- forwarded anyway: the cursor still has UI to point at, and the
        -- steer is a read of the motion rather than a claim on it
      end
      if inner then return inner(x, y, dx, dy, istouch) end
    end
  end

  -- ------- the touch screen
  --
  -- Two gestures, told apart by how many fingers are down on OPEN screen
  -- (the overlay's own d-pad and buttons are never either):
  --
  --   one finger, in a battle    drags the shot around the arena
  --   two fingers               pinch to zoom, wherever zooming means
  --                             something -- and while they are down the
  --                             free-roam look stands aside, so a pinch in
  --                             3RD does not also spin the view
  local TouchControls = require("src.core.TouchControls")

  local free = {}          -- id -> {x, y} for every finger on open screen
  local pinch = nil        -- { a, b, gap } while two of them are pinching

  local function freeCount()
    local n = 0
    for _ in pairs(free) do n = n + 1 end
    return n
  end

  local function gapOf(a, b)
    local dx, dy = free[a].x - free[b].x, free[a].y - free[b].y
    return math.sqrt(dx * dx + dy * dy)
  end

  -- Two free fingers and a camera that zooms: start measuring. The look
  -- drag is dropped for the duration -- FirstPerson never sees the moves
  -- below -- and re-seated on whichever finger survives, so the view does
  -- not jump by however far the pinch travelled.
  local function startPinch()
    if pinch or freeCount() < 2 then return end
    local ids = {}
    for id in pairs(free) do ids[#ids + 1] = id end
    local gap = gapOf(ids[1], ids[2])
    if gap < 16 then return end
    pinch = { a = ids[1], b = ids[2], gap = gap }
    CamControl.surveyAccum = 0
    pcall(FirstPerson.dropLook)
  end

  local function endPinch(lifted)
    if not pinch then return end
    local survivor = nil
    for id in pairs(free) do
      if id ~= lifted then survivor = id break end
    end
    pinch = nil
    if survivor and free[survivor] then
      pcall(FirstPerson.reseatLook, survivor,
            free[survivor].x, free[survivor].y)
    end
  end

  local function onControl(x, y)
    local hit = nil
    pcall(function() hit = TouchControls:hitTest(x, y) end)
    return hit
  end

  -- Whether this module has any interest in touches at all this frame.
  -- Kept deliberately wide -- a battle, or anything that zooms -- because
  -- the wrap forwards everything it does not claim regardless.
  local function wantsTouch()
    return battleLive() or CamControl.zoomTarget() ~= nil
  end

  do
    local inner = Game.touchpressed
    function Game:touchpressed(id, x, y)
      if wantsTouch() and not onControl(x, y) then
        free[id] = { x = x, y = y }
        if CamControl.zoomTarget() then startPinch() end
        -- forwarded even so: a single free finger is the free-roam look's
        -- to claim (FirstPerson's wrap is inside this one), and in a
        -- battle it is nobody's until it MOVES
      end
      return inner(self, id, x, y)
    end
  end

  do
    local inner = Game.touchmoved
    function Game:touchmoved(id, x, y)
      local f = free[id]
      if f then
        local px, py = f.x, f.y
        f.x, f.y = x, y
        if pinch and (id == pinch.a or id == pinch.b) then
          local gap = gapOf(pinch.a, pinch.b)
          local factor = gap / math.max(1, pinch.gap)
          if math.abs(factor - 1) > CamControl.PINCH_SLACK then
            CamControl.pinchBy(factor)
            pinch.gap = gap
          end
          return                       -- claimed: never a look drag too
        end
        if battleLive() and not pinch then
          local w, h = 1280, 720
          pcall(function()
            w, h = love.graphics.getWidth(), love.graphics.getHeight()
          end)
          BattleCam.dragOrbit((x - px) / math.max(320, w))
          -- dragged UP sends the camera up and over, the same way the
          -- stick and the mouse do
          BattleCam.dragPitch(-(y - py) / math.max(240, h))
          return
        end
      end
      return inner(self, id, x, y)
    end
  end

  do
    local inner = Game.touchreleased
    function Game:touchreleased(id, x, y)
      if free[id] then
        if pinch and (id == pinch.a or id == pinch.b) then endPinch(id) end
        free[id] = nil
      end
      return inner(self, id, x, y)
    end
  end

  -- a reset that drops held input state drops ours with it, exactly as the
  -- free-roam look's does
  do
    local inner = Game.focus
    function Game:focus(f)
      free, pinch = {}, nil
      CamControl.surveyAccum = 0
      return inner(self, f)
    end
  end
end

return CamControl
