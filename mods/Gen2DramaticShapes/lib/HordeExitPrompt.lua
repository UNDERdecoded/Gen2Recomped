-- HORDE MODE: the way out.
--
-- START (the pad's, the keyboard's ESCAPE, the touch overlay's) and the
-- VR left stick click all land here: a plain yes/no over the frozen
-- world, asking whether to leave. YES hands over to Horde.finish, which
-- is the same restore the GAME OVER card runs -- the map, the cell, the
-- facing, the camera rung, the hour, the music and every NPC put back
-- exactly as they were. NO drops the player straight back into the
-- firefight.
--
-- Pushing a state is what pauses the mode, and it is the only thing that
-- can: horde mode rides the pipeline's update hook rather than the state
-- stack precisely so that nothing on the stack stops it, but the combat
-- inside Horde.update is gated on the overworld actually being the live
-- state, so this prompt freezes the crowd and the gun for as long as it
-- is up. That is the correct behaviour for a confirmation and it is why
-- "no pausing" does not extend to this one.
--
-- Drawn the way the game draws a yes/no: a white bordered box with black
-- text and the filled arrow beside the row (see Theme.choiceBox, which
-- is where the original's own YES_NO_MENU sits). Black on white because
-- that is what the font IS -- the sheets are black glyphs on transparent
-- and no colour can lighten one.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Horde = V.require("Horde")

local HordeExitPrompt = {}
HordeExitPrompt.__index = HordeExitPrompt

-- the question's box, and the choice box under it, in 8px tiles
local ASK = { tx = 1, ty = 6, tw = 18, th = 4 }
local PICK = { tx = 13, ty = 10, tw = 6, th = 6 }

function HordeExitPrompt.new(game)
  local self = setmetatable({}, HordeExitPrompt)
  self.game = game
  -- NOT opaque: the horde is still standing out there behind this, which
  -- is most of what makes the question feel like a decision
  self.isOpaque = false
  self.index = 2          -- NO, the way every dangerous prompt starts
  self.done = false
  return self
end

local function sfx(game, name)
  pcall(function()
    require("src.core.Sound").play(game.data, name)
  end)
end

function HordeExitPrompt:update()
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end

  if input:wasPressed("up") or input:wasPressed("down") then
    self.index = self.index == 1 and 2 or 1
  elseif input:wasPressed("a") then
    self.done = true
    sfx(self.game, "Press_AB")
    self.game.stack:pop()
    if self.index == 1 then pcall(Horde.finish, self.game) end
  elseif input:wasPressed("b") or input:wasPressed("start") then
    -- B and START both mean "no": the button that opened this closes it,
    -- which is the one thing a player who opened it by accident will try
    self.done = true
    sfx(self.game, "Press_AB")
    self.game.stack:pop()
  end
end

function HordeExitPrompt:draw()
  local ok, Font = pcall(require, "src.render.Font")
  if not ok then return end
  local okT, Theme = pcall(require, "src.ui.Theme")

  Font.drawBox(ASK.tx, ASK.ty, ASK.tw, ASK.th)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw("EXIT MINI GAME?", (ASK.tx + 2) * 8, (ASK.ty + 2) * 8)

  Font.drawBox(PICK.tx, PICK.ty, PICK.tw, PICK.th)
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw("YES", (PICK.tx + 2) * 8, (PICK.ty + 2) * 8)
  Font.draw("NO", (PICK.tx + 2) * 8, (PICK.ty + 4) * 8)
  local cursor = okT and Theme.cursor or 0xED
  Font.drawCode(cursor, (PICK.tx + 1) * 8,
                (PICK.ty + 2 + (self.index - 1) * 2) * 8)
  love.graphics.setColor(1, 1, 1, 1)
end

return HordeExitPrompt
