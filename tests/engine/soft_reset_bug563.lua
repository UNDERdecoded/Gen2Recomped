-- Soft reset: A+B+SELECT+START held together drops the game back to the
-- title from anywhere, mid-battle included (#563).  _Joypad
-- (engine/joypad.asm:6) tests the raw read with `cp PAD_BUTTONS` -- an
-- equality, so a d-pad direction in the mix cancels it -- and does so ahead
-- of the wJoyIgnore / BIT_DISABLE_JOYPAD masking further down, which is why
-- the combo still works where ordinary input is being thrown away.
-- TrySoftReset then decrements hSoftReset, seeded with 16 by Init
-- (home/init.asm:81), one poll at a time.  The on-screen overlay's half is
-- here too: one finger only ever claims one control.
--   luajit tests/engine/soft_reset_bug563.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Input = require("src.core.Input")
local TouchControls = require("src.core.TouchControls")
local Game = require("src.core.Game")

-- pokered's 16 polls; the port counts fixed steps, which are the same 60Hz
local HOLD_STEPS = 16

-- The keys the hand-off tells a player to press.  Pinned because the combo
-- is only reachable if all four GB buttons have a key, and because the
-- letter A is bound to LEFT here -- a player reaching for "A" on the
-- keyboard adds a direction and cancels the chord instead of arming it.
Input:init()
eq(Input.keyBindings["z"], "a", "Z is the A button")
eq(Input.keyBindings["x"], "b", "X is the B button")
eq(Input.keyBindings["escape"], "start", "Escape is START")
eq(Input.keyBindings["tab"], "select", "Tab is SELECT")
eq(Input.keyBindings["a"], "left", "the letter A is LEFT, not the A button")

-- ---- the chord itself --------------------------------------------------

local function holdKeys(...)
  Input:init()
  for _, key in ipairs({ ... }) do Input:keypressed(key) end
end

holdKeys("z", "x", "escape", "tab")
check(Input:softResetHeld(), "all four buttons down arms the combo")

for _, missing in ipairs({ "z", "x", "escape", "tab" }) do
  local keys = {}
  for _, key in ipairs({ "z", "x", "escape", "tab" }) do
    if key ~= missing then keys[#keys + 1] = key end
  end
  holdKeys(unpack(keys))
  check(not Input:softResetHeld(),
        "three of the four is not the combo (without " .. missing .. ")")
end

-- `cp PAD_BUTTONS` is an equality: any direction held alongside the four
-- takes the raw read off PAD_BUTTONS and TrySoftReset is never reached.
for _, dir in ipairs({ "up", "down", "left", "right" }) do
  holdKeys("z", "x", "escape", "tab", dir)
  check(not Input:softResetHeld(), dir .. " held alongside cancels the combo")
end

-- ---- the 16-step countdown ---------------------------------------------

-- one Game:step's worth of the chord; returns whether the reset fired
local function stepChord()
  Input:step()
  return Input:softResetStep()
end

holdKeys("z", "x", "escape", "tab")
for i = 1, HOLD_STEPS - 1 do
  check(not stepChord(), "step " .. i .. " of the hold does not reset yet")
end
check(stepChord(), "the " .. HOLD_STEPS .. "th consecutive step resets")

-- hSoftReset is never re-seeded on release in the original, so its count
-- leaks across a session; the port re-arms instead, or a session's worth of
-- stray four-button presses would eventually add up to a reset.
holdKeys("z", "x", "escape", "tab")
for _ = 1, HOLD_STEPS - 1 do stepChord() end
Input:keyreleased("tab")
check(not stepChord(), "lifting SELECT one step short cancels")
Input:keypressed("tab")
for i = 1, HOLD_STEPS - 1 do
  check(not stepChord(),
        "re-pressing it restarts the count from 16, not from 1 (step " .. i .. ")")
end
check(stepChord(), "and a full fresh hold resets")

-- same re-arm for the direction case: a thumb brushing the d-pad mid-hold
holdKeys("z", "x", "escape", "tab")
for _ = 1, HOLD_STEPS - 1 do stepChord() end
Input:keypressed("up")
check(not stepChord(), "a direction one step short cancels")
Input:keyreleased("up")
for _ = 1, HOLD_STEPS - 1 do
  check(not stepChord(), "and the count starts over")
end
check(stepChord(), "reaching 16 again from the restart")

-- ---- Game:step routes it above the state stack --------------------------

-- Doubles for the two services Game:step touches on the reset path.  The
-- real stack is not needed: what is being pinned is that the combo is read
-- before stack:update, so it fires from a battle, a menu or a cutscene and
-- not just from the overworld (#563).
local function fakeGame()
  local game = { input = Input, save = {}, returned = 0 }
  game.stack = {
    updates = 0,
    update = function(self) self.updates = self.updates + 1 end,
  }
  function game:returnToTitle() self.returned = self.returned + 1 end
  return game
end

local game = fakeGame()
holdKeys("z", "x", "escape", "tab")
for _ = 1, HOLD_STEPS do Game.step(game, 1 / 60) end
eq(game.returned, 1, "Game:step falls back to the title on the 16th step")
eq(game.stack.updates, HOLD_STEPS - 1,
   "and the state on top never gets that step, whatever it was")
check(not Input:isDown("a"),
      "the still-physically-held A is cleared, so the title screen does not "
      .. "read it as a menu choice on its first frame")

-- A tool mod may hand Game a stand-in input; Game guards on the method
-- existing rather than assuming it, so those simply never soft reset.
local bare = fakeGame()
bare.input = { step = function() end, isDown = function() return false end }
for _ = 1, HOLD_STEPS * 2 do Game.step(bare, 1 / 60) end
eq(bare.returned, 0, "an input with no chord bookkeeping never resets")

-- ---- the on-screen overlay ---------------------------------------------

-- Force the overlay live the way a phone would have it.  img is only ever
-- tested for truthiness on the input path (drawing is what reads it), so a
-- placeholder keeps this suite off love.graphics.newImage.
Input:init()
TouchControls:init()
TouchControls.active, TouchControls.enabled = true, true
TouchControls.img = { stub = true }
local L = TouchControls:layout()

-- One finger, one control: touchpressed returns on its first hit, so no
-- single touch can ever arm more than a quarter of the chord however the
-- layout editor has moved the controls around.
for _, btn in ipairs({ "a", "b", "start", "select" }) do
  Input:init()
  TouchControls:reset()
  TouchControls:touchpressed(1, L[btn].cx, L[btn].cy)
  local held = 0
  for _ in pairs(TouchControls.held) do held = held + 1 end
  eq(held, 1, "a finger on " .. btn:upper() .. " presses that button alone")
  check(not Input:softResetHeld(), "...which is not the combo")
end

-- Four fingers on four controls is the only way there, and it still has to
-- survive the same 16 steps -- better than a quarter second of everything
-- staying put.
Input:init()
TouchControls:reset()
local ids = { a = 1, b = 2, start = 3, select = 4 }
for btn, id in pairs(ids) do
  TouchControls:touchpressed(id, L[btn].cx, L[btn].cy)
end
check(Input:softResetHeld(), "four fingers on A, B, START and SELECT arm it")
for i = 1, HOLD_STEPS - 1 do
  check(not stepChord(), "the overlay holds the same countdown (step " .. i .. ")")
end
check(stepChord(), "and resets on the 16th")

-- the accidental version: one finger slips off part way through
Input:init()
TouchControls:reset()
for btn, id in pairs(ids) do
  TouchControls:touchpressed(id, L[btn].cx, L[btn].cy)
end
for _ = 1, HOLD_STEPS - 1 do stepChord() end
TouchControls:touchreleased(ids.select, L.select.cx, L.select.cy)
check(not stepChord(), "a finger leaving SELECT one step short cancels")
check(not Input:softResetHeld(), "and the chord is no longer armed")

-- the fifth finger a real two-handed grip has on the d-pad
Input:init()
TouchControls:reset()
for btn, id in pairs(ids) do
  TouchControls:touchpressed(id, L[btn].cx, L[btn].cy)
end
TouchControls:touchpressed(5, L.dpad.cx, L.dpad.cy - L.dpad.w * 0.4)
check(not Input:softResetHeld(),
      "a thumb on the d-pad cancels it the same way a keyboard direction does")

Input:init()
TouchControls:reset()
T.finish("soft_reset_bug563")
