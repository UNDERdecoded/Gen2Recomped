-- Xbox controller on Gen 4: buttons, stick, hotplug, and the lower-screen
-- cursor, driven by injecting love.gamepad* style events into the real Game,
-- Input, PadPointer and Gen4Poketch.  Pure Lua:
--   python tools/run_lua_check.py tools/gen4_xbox_pad_check.lua
package.path = './?.lua;' .. package.path
love = { math = { random = math.random }, graphics = {} }
local version = 'platinum'
local info = { family = 'platinum', generation = 4, id = 'platinum' }
package.loaded['src.render.Assets'] = { image = function() return nil end, register = function() end }
package.loaded['src.render.Font'] = { width = function(s) return #s * 6 end, draw = function() end }
package.loaded['src.core.GameVersion'] = {
  generation = function() return 4 end, get = function() return version end,
  isGen2 = function() return false end, isGen3 = function() return false end,
  isGen4 = function() return true end, isGen5 = function() return false end,
  isDualScreen = function() return true end, info = function() return info end,
  VERSIONS = {},
}
package.loaded['src.core.FrameProfile'] = { section = function() return function() end end, frame = function() end }
package.loaded['src.ui.SaveCompanion'] = { tick = function() end }
local overlay = 0
package.loaded['src.core.TouchControls'] = {
  touchpressed = function() overlay = overlay + 1 end, touchmoved = function() end,
  touchreleased = function() end, noteGamepad = function() end, reset = function() end,
  joystickremoved = function() end,
}
local Renderer = { uiPresentation = { x = 100, y = 50, w = 768, h = 576, scaleX = 3, scaleY = 3 } }
package.loaded['src.render.Renderer'] = Renderer

local passed, failed = 0, 0
local function check(ok, label)
  if ok then passed = passed + 1 else failed = failed + 1; print('FAIL ' .. label) end
end

local Input = require('src.core.Input')
local PadPointer = require('src.core.PadPointer')
local SS = require('src.ui.SecondScreen')
local Game = require('src.core.Game')
local Watch = require('src.ui.Gen4Poketch')

-- A display-less transport: no second panel, so the mode is `swap`.
SS._setTransport({ available = function() return false end })

Input:init()
local function step() Input:step() end
local function pressedThen(btn, fn) Input:gamepadpressed(nil, btn); step(); fn(); Input:gamepadreleased(nil, btn) end

-- ---- 1. the Xbox map -------------------------------------------------------
local MAP = { a = 'a', b = 'b', y = 'x', x = 'y', start = 'start', back = 'select',
              leftshoulder = 'l', rightshoulder = 'r',
              dpup = 'up', dpdown = 'down', dpleft = 'left', dpright = 'right' }
for pad, action in pairs(MAP) do
  Input:reset()
  Input:gamepadpressed(nil, pad); step()
  check(Input:wasPressed(action), 'Xbox ' .. pad .. ' -> ' .. action)
  check(Input:isDown(action), 'Xbox ' .. pad .. ' holds ' .. action)
  Input:gamepadreleased(nil, pad)
  check(not Input:isDown(action), 'Xbox ' .. pad .. ' releases ' .. action)
end
Input:reset(); Input:gamepadpressed(nil, 'y'); step()
check(Input:wasPressed('start'), 'Xbox Y is the Gen 4 field menu (DS X)')
Input:reset(); Input:gamepadpressed(nil, 'x'); step()
check(Input:wasPressed('select'), 'Xbox X is the registered key item (DS Y)')

-- ---- 2. the stick ----------------------------------------------------------
local function stick(x, y) Input:gamepadaxis(nil, 'leftx', x); Input:gamepadaxis(nil, 'lefty', y) end
Input:reset()
stick(0.15, -0.12)
check(Input.stickDir == nil, 'resting drift inside the deadzone does nothing')
stick(0.4, 0)
check(Input.stickDir == nil, 'between OFF and ON does not start a walk')
stick(0.9, 0.1); step()
check(Input.stickDir == 'right' and Input:wasPressed('right') and Input:isDown('right'), 'stick right walks right')
step(); check(Input:isDown('right') and not Input:wasPressed('right'), 'held stick is a held direction (menu repeat)')
-- diagonal jitter: hold right, wobble y around x
local flips = 0
local last = Input.stickDir
for _, y in ipairs({ 0.6, 0.75, 0.7, 0.85, 0.7, 0.8, 0.72 }) do
  stick(0.8, y)
  if Input.stickDir ~= last then flips = flips + 1; last = Input.stickDir end
end
check(flips == 0, 'near-diagonal wobble does not flip between right and down')
stick(0.4, 1.0)
check(Input.stickDir == 'down', 'a clearly vertical push switches to down')
stick(0.45, 0.4)
check(Input.stickDir == 'down', 'hysteresis band keeps the direction')
stick(0.1, 0.1); check(Input.stickDir == nil and not Input:isDown('down'), 'releasing the stick releases the direction')
-- run: B held while the stick walks
Input:reset()
Input:gamepadpressed(nil, 'b'); stick(-1, 0); step()
check(Input:isDown('b') and Input:isDown('left'), 'B-hold run with the stick')
Input:gamepadreleased(nil, 'b'); stick(0, 0)
-- the D-pad and the stick share a direction
Input:reset()
Input:gamepadpressed(nil, 'dpup'); stick(0, -1); stick(0, 0)
check(Input:isDown('up'), 'releasing the stick does not drop a held D-pad direction')
Input:gamepadreleased(nil, 'dpup'); check(not Input:isDown('up'), 'D-pad release')

-- ---- 3. two controllers ----------------------------------------------------
local padA = { getID = function() return 1 end, isGamepad = function() return true end }
local padB = { getID = function() return 2 end, isGamepad = function() return true end }
Input:reset()
Input:gamepadpressed(padA, 'a'); Input:gamepadpressed(padB, 'a'); step()
local edges = 0
for _, b in ipairs({ 'a' }) do if Input:wasPressed(b) then edges = edges + 1 end end
check(edges == 1 and Input:isDown('a'), 'two pads pressing A are one A edge')
Input:gamepadreleased(padA, 'a')
check(Input:isDown('a'), 'A stays held while the second pad still holds it')
Input:gamepadreleased(padB, 'a')
check(not Input:isDown('a'), 'A released when both pads let go')
Input:reset()
Input:gamepadaxis(padA, 'leftx', 1); Input:gamepadaxis(padB, 'leftx', 0)
check(Input.stickDir == 'right', 'a resting second pad does not cancel the first pad stick')
Input:gamepadaxis(padA, 'leftx', 0); check(Input.stickDir == nil, 'stick released')
-- gamepad + raw duplicate (bug620) still ignored
Input:reset(); Input:joystickpressed(padA, 1); step()
check(not Input:isDown('a'), 'mapped pad raw duplicate still ignored')

-- ---- 4. the lower-screen cursor, on the real Pokétch -----------------------
local apps = { { name = 'Counter' }, { name = 'Memo Pad' }, { name = 'Coin Toss' } }
local top = {}
local game = setmetatable({
  data = { isGen4Cache = true, gen4_menus = { poketch = { apps = apps } } },
  save = { options = {}, inventory = {}, poketch = { enabled = true } },
  stack = { top = function() return top end }, input = Input,
}, { __index = Game })
local watch = Watch.new(game)
top = watch
Input:init(); Input:reset(); PadPointer.reset()

local function use(name)
  for i, a in ipairs(watch.apps) do if a.name == name then watch.index = i end end
end
local function axisEvent(axis, v) game:gamepadaxis(nil, axis, v) end
local function tapRT() axisEvent('triggerright', 1); axisEvent('triggerright', 0) end
check(not PadPointer.active, 'cursor off by default')
tapRT()
check(PadPointer.active, 'RT turns the lower-screen cursor on')
use('Counter')
local lx, ly = 114, 128                       -- the Counter app's button
PadPointer.x, PadPointer.y = lx, ly
game:gamepadpressed(nil, 'a'); game:gamepadreleased(nil, 'a')
check(game.save.poketch.counter == 1, 'A taps the Counter button through the real Pokétch')
step(); check(not Input:wasPressed('a'), 'the tap did not also reach the game as an A press')
-- the stick moves the cursor and no longer walks
axisEvent('leftx', 1.0)
check(Input.stickDir == nil, 'stick does not walk while the cursor is up')
PadPointer.update(game, 0.5)
check(PadPointer.x > lx + 50, 'stick moves the cursor right')
axisEvent('leftx', 0)
PadPointer.x, PadPointer.y = 240, 120         -- the bezel's next-app button
local before = watch.index
game:gamepadpressed(nil, 'a'); game:gamepadreleased(nil, 'a')
check(watch.index ~= before, 'A on the bezel button changes Pokétch app')
-- D-pad moves too, slowly, and a drag works with A held (memo pad)
use('Memo Pad')
PadPointer.x, PadPointer.y = 30, 30
game:gamepadpressed(nil, 'a')
game:gamepadpressed(nil, 'dpright'); PadPointer.update(game, 0.3); game:gamepadreleased(nil, 'dpright')
game:gamepadreleased(nil, 'a')
check(PadPointer.x > 30 and PadPointer.x < 90, 'D-pad moves the cursor')
check(next(game.save.poketch.memo or {}) ~= nil, 'dragging with A held draws on the memo pad')
-- other buttons keep working: B reaches the game, X is Gen 4's menu key
game:gamepadpressed(nil, 'b'); step()
check(Input:wasPressed('b'), 'B still cancels while the cursor is up')
game:gamepadreleased(nil, 'b')
-- the cursor never strands the player: a new top screen switches it off
local newTop = {}
top = newTop; PadPointer.update(game, 0.016)
check(not PadPointer.active, 'cursor switches off when the top screen changes')
axisEvent('leftx', 1.0)
check(Input.stickDir == 'right', 'stick walks again afterwards')
axisEvent('leftx', 0)
-- a stick still held when the cursor leaves goes back to the game
top = watch; Input:reset(); PadPointer.reset()
tapRT(); axisEvent('leftx', 1.0); check(Input.stickDir == nil, 'stick owned by cursor')
tapRT(); check(not PadPointer.active and Input.stickDir == 'right', 'held stick handed back on toggle-off')
axisEvent('leftx', 0)
-- refuses to take the stick in the field when no lower screen is showing
top = {}; game.overworld = top; game.secondScreenPointerOwner = nil
Input:reset(); PadPointer.reset(); tapRT()
check(not PadPointer.active, 'cursor refuses to start over a field with no lower screen')
game.secondScreenPointerOwner = watch; tapRT()
check(PadPointer.active, 'but starts over the always-present Pokétch panel')
tapRT()
game.overworld = nil

-- disconnect mid-tap lifts the finger
top = watch; PadPointer.reset(); tapRT()
PadPointer.x, PadPointer.y = 114, 128
game:gamepadpressed(nil, 'a')
check(PadPointer.isTouching(), 'finger down')
game:joystickremoved(padA)
check(not PadPointer.isTouching(), 'unplugging lifts the virtual finger')
game:joystickadded(padA)
tapRT()

-- ---- 5. the other mapping modes -------------------------------------------
local function roundTrip(mode)
  game.save.options.secondScreenMode = mode
  local ok = true
  for _, p in ipairs({ { 10, 10 }, { 128, 96 }, { 250, 190 } }) do
    local px, py = SS.fromLocal(game, p[1], p[2])
    local bx, by = SS.toLocal(game, px, py)
    ok = ok and bx and math.abs(bx - p[1]) < 1e-6 and math.abs(by - p[2]) < 1e-6
  end
  return ok
end
check(roundTrip('swap'), 'fromLocal inverts toLocal in swap mode')
check(roundTrip('inset'), 'fromLocal inverts toLocal in inset mode')
game.save.options.secondScreenMode = 'swap'

-- display mode (a real second panel): events are injected in local space
SS._setTransport({ available = function() return true end, pollTouch = function() return {} end })
game.save.options.secondScreenMode = 'display'
check(SS.mode(game) == 'display', 'display mode active')
PadPointer.reset(); use('Counter'); game.save.poketch.counter = 0
top = watch; tapRT()
PadPointer.x, PadPointer.y = 114, 128
game:gamepadpressed(nil, 'a'); game:gamepadreleased(nil, 'a')
check(game.save.poketch.counter == 1, 'cursor taps reach the lower panel in display mode')
game.secondScreenNativePanel = true
game.secondScreenSurfaceWidth, game.secondScreenSurfaceHeight = 768, 576
game:gamepadpressed(nil, 'a'); game:gamepadreleased(nil, 'a')
check(game.save.poketch.counter == 2, 'native high-DPI panel does not rescale the cursor point')
game.secondScreenNativePanel = nil
tapRT()

-- ---- 6. Pokétch app shortcuts from the pad --------------------------------
SS._setTransport({ available = function() return false end })
game.save.options.secondScreenMode = 'swap'
Input:reset(); use('Counter'); PadPointer.reset()
local c0 = watch.index
Input:gamepadpressed(nil, 'rightshoulder'); step(); watch:update(1 / 60); Input:gamepadreleased(nil, 'rightshoulder')
check(watch.index == c0 % #watch.apps + 1, 'RB cycles Pokétch apps forward')
Input:gamepadpressed(nil, 'dpleft'); step(); watch:update(1 / 60); Input:gamepadreleased(nil, 'dpleft')
check(watch.index == c0, 'D-pad left cycles Pokétch apps back')
Input:gamepadpressed(nil, 'a'); step(); watch:update(1 / 60); Input:gamepadreleased(nil, 'a')
check(game.save.poketch.counter == 3, 'A presses the app main button (Counter)')

-- ---- 7. single-screen games are untouched ----------------------------------
local oldAvail = SS.available
SS.available = function() return false end
Input:reset(); PadPointer.reset()
local g2 = setmetatable({ save = { options = {} }, stack = { top = function() return {} end }, input = Input }, { __index = Game })
g2:gamepadaxis(nil, 'triggerright', 1)
check(not PadPointer.active, 'RT does nothing on a single-screen game')
g2:gamepadaxis(nil, 'triggerright', 0)
g2:gamepadaxis(nil, 'leftx', 1)
check(Input.stickDir == 'right', 'Gen 1-3 stick unchanged')
SS.available = oldAvail

print(string.format('Gen4 Xbox pad: %d/%d checks passed', passed, passed + failed))
os.exit(failed == 0 and 0 or 1)
