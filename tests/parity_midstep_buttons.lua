-- Parity test: A/START are never handled mid-step (#286).
-- Self-contained: run via `luajit tests/parity_midstep_buttons.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
--
-- Oracle: home/overworld.asm OverworldLoop reads wWalkCounter and, when it
-- is nonzero ("the player sprite has not yet completed the walking
-- animation"), jumps straight to .moveAhead -- JoypadOverworld, and with
-- it the START check, the A check, and every direction initiation, only
-- ever runs while the player stands on a tile.
--
-- The port ran handleInput() every frame regardless of player.moving, so a
-- mid-step A/START press pushed its TextBox/StartMenu right there and
-- froze Red between tiles, mid-animation (#286: running up to Nurse Joy
-- and mashing A stops him half off the tile).
--
-- Second oracle, engine/joypad.asm _Joypad: hJoyPressed is
-- (hJoyLast ^ hJoyInput) & hJoyInput, and hJoyLast only advances on an
-- explicit `call Joypad`.  vblank's per-frame ReadJoypad writes hJoyInput
-- alone, and the mid-step path never calls Joypad, so hJoyLast is FROZEN
-- for the whole animation.  A button pressed mid-step and still held when
-- the step lands therefore reads as a fresh press at the next poll; one
-- released before the step lands is genuinely lost.  The port used to drop
-- both, which on the Cycling Road roll made START a coin flip (#525).
--
-- The invariant: while a step is in progress, A and START change nothing
-- (no TextBox, no StartMenu, the step completes).  On the landing frame a
-- still-held A or START is acted on, a released one is not.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity midstep buttons")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local Renderer = require("src.render.Renderer")
local SaveData = require("src.core.SaveData")
local OW = require("src.world.OverworldController")

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack
StateStack:init()

-- PALLET_TOWN (6,9) facing down: open grass, several free tiles south
Game.save = SaveData.newGame()
Game.stack:push(OW, "PALLET_TOWN", 6, 9, "down")
local ow = Game.stack:top()

local function step(pressedBtn)
  -- the real driver: Game:step promotes pressQueue edges via Input:step()
  -- (which also expires them) before stack:update
  if pressedBtn then table.insert(Input.pressQueue, pressedBtn) end
  Input:step()
  ow:update(1 / 60)
end

-- A synthetic pressQueue inject has no source entry, so Input:step sets
-- state[btn] = true and nothing ever clears it (src/core/Input.lua) -- the
-- harness models a HELD button.  Most cases below want a tap, so release it
-- explicitly; the held cases are called out where they matter.
local function tap(btn)
  step(btn)
  Input.state[btn] = false
end

-- start a step south (held direction, like hJoyHeld)
Input.state.down = true
step()
Input.state.down = false
check(ow.player.moving, "held direction starts a step")
local startY = ow.player.cellY

-- spy on interact(): a mid-step A press must not even reach it
local interactCalls = 0
local baseInteract = ow.interact
ow.interact = function(self, ...)
  interactCalls = interactCalls + 1
  return baseInteract(self, ...)
end

-- mid-step A press: nothing may happen (the original acts on nothing here)
tap("a")
eq(interactCalls, 0, "mid-step A never reaches interact()")
check(Game.stack:top() == ow, "mid-step A pushes no TextBox")
check(ow.player.moving, "mid-step A does not interrupt the step")

-- mid-step START press: no start menu either
tap("start")
check(Game.stack:top() == ow, "mid-step START opens no menu")
check(ow.player.moving, "mid-step START does not interrupt the step")

-- run the step out: the player lands on the next tile, unfrozen
local guard = 0
while ow.player.moving and guard < 60 do step(); guard = guard + 1 end
eq(ow.player.cellY, startY + 1, "the step completes onto the next tile")

-- the issue's actual repro ("press A quickly/early" running up to Nurse
-- Joy): start another step and press A on its FINAL mid-step frame, then
-- RELEASE it before the step lands.  hJoyLast is frozen through the
-- animation, so the next poll sees the button already up and computes no
-- edge (engine/joypad.asm) -- this press really is lost.
Input.state.down = true
step()
Input.state.down = false
check(ow.player.moving, "second step starts")
guard = 0
while ow.player.moving and guard < 60 do
  guard = guard + 1
  if guard == (ow.player.stepFramesCur or 16) - 1 then
    tap("a") -- the last frame before landing, released immediately
  else
    step()
  end
end
check(not ow.player.moving, "the second step completes")
step() -- the landing frame, where a still-held button would be polled
eq(interactCalls, 0, "a mid-step A released before landing is still lost")
check(Game.stack:top() == ow, "the released last-frame A pushes no TextBox")

-- ...but a mid-step A that is STILL HELD when the step lands is delivered
-- on the landing frame, because hJoyLast never advanced (#525).  Nothing
-- happens mid-step either way: the poll is deferred, not the action.
Input.state.down = true
step()
Input.state.down = false
check(ow.player.moving, "third step starts")
step("a") -- pressed mid-step and left held
eq(interactCalls, 0, "the held A still does nothing mid-step")
check(ow.player.moving, "the held A does not interrupt the step")
guard = 0
while ow.player.moving and guard < 60 do step(); guard = guard + 1 end
eq(interactCalls, 0, "still nothing while the step runs out")
step() -- landing frame
eq(interactCalls, 1, "a held mid-step A is polled on the landing frame")
Input.state.a = false

-- standing on the tile again, START and A work as always
interactCalls = 0
tap("start")
check(Game.stack:top() ~= ow, "START opens the start menu on a tile")
while Game.stack:top() do Game.stack:pop() end
Game.stack:push(OW, "PALLET_TOWN", 6, 9, "down")
ow = Game.stack:top()
interactCalls = 0 -- OW is a singleton: the spy survives the re-push
step("a")
eq(interactCalls, 1, "A on a tile runs interact() (the gate is movement-only)")

S.finish()
