-- A tap on the d-pad turns in place; only a held direction steps (#415).
-- home/overworld.asm .handleDirectionButtonPress reaches the turn only while
-- wCheckFor180DegreeTurn is set, and .noDirectionButtonsPressed -- the poll
-- that finds nothing held -- is the one place that sets it.  So the turn
-- delay is spent once per press, not at every facing change: a direction
-- swapped mid-walk keeps stepping.  Player.turnArmed is that flag and
-- Player:turnWindow is how long the fresh turn holds the step off.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Collision = require("src.world.Collision")
local FieldDefaults = require("src.world.FieldDefaults")
local Input = require("src.core.Input")
local Player = require("src.world.Player")

Collision.load(Data)

-- the fixture dataset ships one player sheet under its own id; Player.new
-- builds a SpriteRenderer off whatever field.playerSprites names
Data.field.playerSprites = { walk = "SPRITE_FIX_PLAYER" }

-- Collision.canMove only ever asks a map these four things, so open floor
-- is cheaper to state directly than to stand a real MapLoader up (that
-- pulls the tileset atlas in, which is the asset pipeline, not this).
local map = {
  def = { tileset = "FIX_OUT" },
  inBounds = function(_, x, y) return x >= 0 and y >= 0 and x < 20 and y < 20 end,
  isWalkableCell = function() return true end,
  isWaterCell = function() return false end,
  cellTile = function() return 0 end,
}

local function newPlayer(facing)
  local p = Player.new(Data, 5, 5, facing or "down")
  Input:init()
  local Game = require("src.core.Game")
  Game.input = Input
  return p
end

-- One fixed step of the overworld's input half: OverworldState:handleInput
-- polls the held direction and re-arms turnArmed when it finds none, then
-- Player:update ticks turnTimer down.  `dir` nil is a released d-pad.
local function step(p, dir)
  local result
  if dir then
    result = p:tryMove(dir, map, {})
  else
    p.turnArmed = true
  end
  p:update()
  return result
end

-- Hold `dir` from a standstill until the step it starts lands, and stop on
-- the landing poll: one more held poll would chain straight into the next
-- tile, which is the walk this suite is not measuring.
local function walkOneTile(p, dir)
  local fromX, fromY = p.cellX, p.cellY
  for _ = 1, 120 do
    step(p, dir)
    if not p.moving and (p.cellX ~= fromX or p.cellY ~= fromY) then
      return true
    end
  end
  return false
end

-- ---- the tap: one poll with the direction down, then nothing -------------

do
  local p = newPlayer("down")
  T.eq(step(p, "up"), "turned", "the first poll of a fresh press turns")
  T.eq(p.facing, "up", "and the facing lands on the tapped direction")
  for _ = 1, 20 do step(p, nil) end
  T.eq(p.cellY, 5, "a released d-pad never commits the step")
  T.eq(p.cellX, 5, "and never drifts sideways either")
  T.eq(p.facing, "up", "the turn survives the release")
end

-- ---- the hold: the same press kept down steps once the window closes -----

do
  local window = FieldDefaults.world(Data, "turnFrames")
  T.eq(window, 4, "the dataset's turn window is 4 fixed steps")

  -- one short of the window: still turning, still on the tile
  local short = newPlayer("down")
  T.eq(step(short, "up"), "turned", "hold: the first poll turns")
  for _ = 1, window - 1 do
    T.eq(step(short, "up"), nil, "a hold inside the window takes no step")
  end
  T.eq(short.cellY, 5, "so the tile is unchanged after " .. window .. " polls")

  -- the poll after the window closes is the one that moves
  T.eq(step(short, "up"), "moved", "the poll past the window commits the step")
  T.check(short.moving, "and the step animation is running")
end

-- ---- the corner: a direction swapped without ever letting go -------------
--
-- This is what turnArmed buys.  Walking a corner never lifts the d-pad, so
-- .noDirectionButtonsPressed never runs and the original charges no turn
-- delay for the new facing; gating on the timer alone stalled every corner.

do
  local p = newPlayer("down")
  T.check(walkOneTile(p, "up"), "the held direction walks a whole tile")
  T.eq(p.cellY, 4, "one tile north")

  local turned = step(p, "right")     -- swap without a release in between
  T.eq(p.facing, "right", "the swap changes the facing")
  T.eq(turned, "moved", "and steps straight away: no second turn delay")
  T.eq(p.turnTimer, 0, "the corner charges no turn window")
end

-- ---- re-arming: the flag only comes back from a standstill ---------------

do
  local p = newPlayer("down")
  T.eq(p.turnArmed, true, "a fresh player starts armed")
  step(p, "left")
  T.eq(p.turnArmed, false, "the turn spends the arm")
  step(p, "left")
  T.eq(p.turnArmed, false, "a still-held direction does not re-arm it")
  step(p, nil)
  T.eq(p.turnArmed, true, "the poll that finds nothing held re-arms it")
end

-- ---- the on-screen d-pad gets the longer window -------------------------
--
-- A finger cannot produce a 4-frame press, so Player:turnWindow widens it
-- for the overlay only.  Keyed on the live source (Input:isTouchDown), not
-- on whether the overlay is visible, so a phone with a pad plugged in keeps
-- the physical window.

do
  local p = newPlayer("down")
  p.facing = "up"
  T.eq(p:turnWindow(), 4, "keyboard and pad presses get the short window")

  Input:overlayPressed("up")
  Input:step()
  T.check(Input:isTouchDown("up"), "the overlay registers as a touch source")
  T.eq(p:turnWindow(), 8, "an overlay press gets the long window")

  Input:keypressed("up")
  Input:overlayReleased("up")
  Input:step()
  T.check(Input:isDown("up"), "the keyboard still holds the direction")
  T.check(not Input:isTouchDown("up"), "but the touch source is gone")
  T.eq(p:turnWindow(), 4, "so the window drops back to the short one")
end

T.finish("turn in place")
