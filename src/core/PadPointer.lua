-- THE DS LOWER TOUCH SCREEN, FOR A PLAYER WITH ONLY A CONTROLLER.
--
-- Everything the DS asks you to touch -- the Pokétch's drawing pad and
-- dowsing machine, the battle bag, the Underground, contest dress-up, the
-- touch keyboard -- is written against pointer events (touchpressed /
-- touchmoved / touchreleased in the screen's own state).  Rather than give
-- every one of those screens a second control scheme, this module is a
-- virtual finger: a cursor in the bottom screen's 256x192 space, moved by
-- the sticks and the D-pad, with A as the fingertip.  It speaks to the game
-- through the same Game:touchpressed path a mouse click uses (mapped through
-- SecondScreen.fromLocal, the inverse of the mapping every screen already
-- applies), so no screen learns anything new and keyboard / touch / mouse
-- behaviour is untouched.
--
--   TOUCH action (default: right trigger, rebindable in CONTROLS) toggles it.
--   While on:  left stick / D-pad move the cursor (they no longer walk or
--              move menu cursors), A presses and drags (hold A, move), and
--              every other button -- B, X, Y, START, SELECT, L, R -- keeps
--              doing its normal job, so B still backs out of a screen.
--   It switches itself off when the top screen changes, so a forgotten
--   cursor can never leave the player unable to walk.
--
-- Dual-screen games only (Gen 4 / HGSS / Gen 5); inert elsewhere.

local PadPointer = {}

PadPointer.active = false
PadPointer.x, PadPointer.y = 128, 96
PadPointer.ID = "padcursor"
PadPointer.STICK_SPEED = 240      -- 256x192 px/s at full deflection
PadPointer.DPAD_SPEED = 110
PadPointer.DEADZONE = 0.22

local W, H = 256, 192

local axes = { leftx = 0, lefty = 0 }
local dpad = {}                    -- dpup/dpdown/dpleft/dpright -> true
local touchButton = nil            -- the pad button currently acting as A
local touching = false
local activeTop = nil

local DPAD = { dpup = true, dpdown = true, dpleft = true, dpright = true }

local function input(game) return game and game.input or require("src.core.Input") end

local function SS() return require("src.ui.SecondScreen") end

local function topOf(game)
  local st = game and game.stack
  return st and st.top and st:top() or nil
end

function PadPointer.available(game)
  local ok, yes = pcall(function() return SS().available(game) end)
  return ok and yes and true or false
end

-- Send one pointer event for the virtual finger.
local function dispatch(game, method)
  local ss = SS()
  local ok, took
  if ss.mode(game) == "display" then
    return ss.injectTouch(game, method, PadPointer.ID, PadPointer.x, PadPointer.y, true)
  end
  local px, py = ss.fromLocal(game, PadPointer.x, PadPointer.y)
  if not px then return false end
  ok, took = pcall(game[method], game, PadPointer.ID, px, py)
  return ok
end

local function liftFinger(game)
  if touching then
    touching = false
    dispatch(game, "touchreleased")
  end
  touchButton = nil
end

function PadPointer.setActive(game, on)
  on = on and true or false
  if on == PadPointer.active then return on end
  if on then
    if not PadPointer.available(game) then return false end
    -- With the field on top and no lower screen showing (swap mode) there is
    -- nothing to point at, and taking the stick off the player for it would
    -- only strand them.
    local top = topOf(game)
    if top ~= nil and top == game.overworld and not game.secondScreenPointerOwner then
      return false
    end
    PadPointer.active = true
    activeTop = top
    axes.leftx, axes.lefty = 0, 0
    dpad = {}
    -- whatever the pad was holding when the cursor took over stops now
    local inp = input(game)
    if inp.releasePadDirections then inp:releasePadDirections() end
    return true
  end
  liftFinger(game)
  PadPointer.active = false
  activeTop = nil
  dpad = {}
  -- hand a still-held stick back to the game
  local inp = input(game)
  local lx, ly = axes.leftx, axes.lefty
  axes.leftx, axes.lefty = 0, 0
  if inp.gamepadaxis then
    if lx ~= 0 then inp:gamepadaxis(nil, "leftx", lx) end
    if ly ~= 0 then inp:gamepadaxis(nil, "lefty", ly) end
  end
  return false
end

function PadPointer.toggle(game)
  return PadPointer.setActive(game, not PadPointer.active)
end

-- A pad button (or trigger / right-stick pseudo-button) went down.  True when
-- the cursor consumed it and the game must not see it.
function PadPointer.gamepadpressed(game, joystick, button)
  local inp = input(game)
  local action = inp.padBindings and inp.padBindings[button]
  if action == "touch" then
    PadPointer.toggle(game)
    return true
  end
  if not PadPointer.active then return false end
  if DPAD[button] then
    dpad[button] = true
    return true
  end
  if action == "a" and not touching then
    touchButton = button
    touching = true
    dispatch(game, "touchpressed")
    return true
  end
  return false
end

function PadPointer.gamepadreleased(game, joystick, button)
  local inp = input(game)
  local action = inp.padBindings and inp.padBindings[button]
  if action == "touch" then return true end
  if DPAD[button] then dpad[button] = nil end
  if touching and button == touchButton then
    touching = false
    touchButton = nil
    dispatch(game, "touchreleased")
    return true
  end
  return false
end

-- True when the cursor owns this axis (the game must not see it).
function PadPointer.gamepadaxis(game, joystick, axis, value)
  if axis ~= "leftx" and axis ~= "lefty" then return false end
  axes[axis] = value
  return PadPointer.active
end

local function radial(v)
  local a = math.abs(v)
  local dz = PadPointer.DEADZONE
  if a <= dz then return 0 end
  local m = (a - dz) / (1 - dz)
  return (v < 0 and -1 or 1) * m * m
end

function PadPointer.update(game, dt)
  if not PadPointer.active then return end
  local top = topOf(game)
  if top ~= activeTop or not PadPointer.available(game) then
    PadPointer.setActive(game, false)
    return
  end
  dt = dt or 0
  local dx = radial(axes.leftx) * PadPointer.STICK_SPEED
  local dy = radial(axes.lefty) * PadPointer.STICK_SPEED
  if dpad.dpleft then dx = dx - PadPointer.DPAD_SPEED end
  if dpad.dpright then dx = dx + PadPointer.DPAD_SPEED end
  if dpad.dpup then dy = dy - PadPointer.DPAD_SPEED end
  if dpad.dpdown then dy = dy + PadPointer.DPAD_SPEED end
  if dx == 0 and dy == 0 then return end
  local nx = math.max(0, math.min(W - 1, PadPointer.x + dx * dt))
  local ny = math.max(0, math.min(H - 1, PadPointer.y + dy * dt))
  if nx == PadPointer.x and ny == PadPointer.y then return end
  PadPointer.x, PadPointer.y = nx, ny
  if touching then dispatch(game, "touchmoved") end
end

-- The crosshair, in the bottom screen's own 256x192 space.
function PadPointer.drawLocal(game)
  local g = love.graphics
  if not (g and g.line) then return end
  game.padPointerDrawn = true
  local x, y = PadPointer.x, PadPointer.y
  g.push("all")
  if g.setShader then g.setShader() end
  if g.setScissor then g.setScissor() end
  local c = touching and 1 or 0
  g.setColor(0, 0, 0, 1)
  g.setLineWidth(3)
  g.line(x - 7, y, x + 7, y); g.line(x, y - 7, x, y + 7)
  g.setColor(1, 1 - c * 0.6, 1 - c * 0.8, 1)
  g.setLineWidth(1)
  g.line(x - 6, y, x + 6, y); g.line(x, y - 6, x, y + 6)
  g.circle("line", x, y, touching and 4 or 2)
  g.pop()
end

-- For a screen that draws its lower half without SecondScreen.draw: put the
-- cursor on the window directly.
function PadPointer.drawFallback(game)
  if not PadPointer.active or game.padPointerDrawn then return end
  local g = love.graphics
  if not (g and g.line) then return end
  local px, py = SS().fromLocal(game, PadPointer.x, PadPointer.y)
  if not px then return end
  g.push("all")
  g.origin()
  if g.setShader then g.setShader() end
  if g.setScissor then g.setScissor() end
  g.setColor(0, 0, 0, 1); g.setLineWidth(4)
  g.line(px - 12, py, px + 12, py); g.line(px, py - 12, px, py + 12)
  g.setColor(1, 1, 1, 1); g.setLineWidth(2)
  g.line(px - 10, py, px + 10, py); g.line(px, py - 10, px, py + 10)
  g.pop()
end

function PadPointer.isTouching() return touching end

-- A controller was unplugged: nothing is held any more.
function PadPointer.padRemoved(game)
  axes.leftx, axes.lefty = 0, 0
  dpad = {}
  liftFinger(game)
end

function PadPointer.reset()
  PadPointer.active, touching, touchButton, activeTop = false, false, nil, nil
  axes.leftx, axes.lefty = 0, 0
  dpad = {}
  PadPointer.x, PadPointer.y = 128, 96
end

return PadPointer
