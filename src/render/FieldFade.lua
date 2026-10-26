-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).
-- Shared native script-fade painter and fixed-step controller. Source callers
-- use this same controller; native scripts keep their original ramp and wait.
local Logger=require('src.core.Logger')
local FadeOverlay = {}
FadeOverlay.__index = FadeOverlay

function FadeOverlay.new(game, ow, color, opts)
  return setmetatable({
    game = game, ow = ow, alpha = 0, color = color or "black",
    ownedHold = opts and opts.ownedHold or false,
  }, FadeOverlay)
end

-- A FADE IS A PALETTE EFFECT, NOT A MODE -- the world keeps running under it.
--
-- The state stack only updates the state on TOP, so while this overlay is up
-- it is the only thing being ticked.  Ticking nothing but the script runner
-- starves the very thing most scripts do behind a fade: MOVE SOMEBODY.  The
-- move queue never steps, `waitmovement` never completes, the map's frame
-- table is never re-asked, and the player is left looking at black with a
-- script that can no longer finish -- which is exactly what Route 101's
-- rescue does (fadescreen, removeobject, setobjectxy, applymovement,
-- waitmovement) three commands after the screen goes dark.
--
-- So pump the field itself.  Only while something is actually driving it: with
-- no script and no queued move there is nothing to advance, and running the
-- field then would hand the player an input frame behind a black screen.
function FadeOverlay:update(dt)
  if self.sourceRetired then return end
  local ow = self.ow
  if ow then
    local runner = ow.runner
    local busy = (runner and runner.isRunning and runner:isRunning())
      or (ow.scriptMoves and #ow.scriptMoves > 0)
      or (ow.pendingScripts and ow.pendingScripts[1] ~= nil)
    if busy and ow.update then
      ow:update(dt or 1 / 60)
    elseif runner then
      runner:update()
    end
    -- THE WATCHDOG, because a screen stuck at black is the one failure a
    -- player cannot tell from a crash.
    --
    -- A fade is always meant to be undone by something: the script's own
    -- fade back, the `waitstate` that ends the scene, or the runner when the
    -- script finishes.  If all three miss it, the game is still running --
    -- input is even accepted -- behind a fully opaque rectangle, and the only
    -- report anybody can make is "it went black".  Two seconds of full black
    -- with nothing driving the field is not a beat in either cartridge, so
    -- bring the picture back and say why once.
    if not self.ownedHold and not self.ramp and (self.alpha or 0) >= 1 and not busy then
      self.idleFrames = (self.idleFrames or 0) + 1
      if self.idleFrames >= 120 then
        Logger.warn("the screen has been faded out for two seconds with no "
                      .. "script running -- fading back in; whatever darkened "
                      .. "it never undid it")
        self.ramp = { from = self.alpha, to = 0, frames = 12, t = 0 }
        self.idleFrames = nil
      end
    else
      self.idleFrames = nil
    end
  end
  local ramp = self.ramp
  if not ramp then return end
  ramp.t = ramp.t + 1
  local k = math.min(1, ramp.t / ramp.frames)
  if ramp.steps then k=math.min(1,math.floor(ramp.t/(ramp.stepFrames or 1))/ramp.steps)end
  self.alpha = ramp.from + (ramp.to - ramp.from) * k
  if ramp.t >= ramp.frames then
    self.ramp = nil
    if ramp.to <= 0 then
      -- a box may sit above the overlay; remove in place, not pop
      local states = self.game.stack.states
      for i = #states, 1, -1 do
        if states[i] == self then table.remove(states, i) break end
      end
      self:releaseVeil()
      if ow then ow.fadeOverlay = nil end
    end
    if ramp.onDone then ramp.onDone() end
  end
end

-- ...AND ON THE WHOLE SURFACE'S ORIGIN.  A state with no uiSize is centred as
-- Game Boy furniture (Game:draw's classicOffset), which slid the 240x160
-- rectangle 40 right and 8 down and left an unfaded L down the left and top
-- through Mom's heal.
function FadeOverlay:uiSize()
  return require("src.ui.Theme").uiSize()
end

function FadeOverlay:releaseVeil()
  local r = self.game and self.game.renderer
  if self.ownsVeil and r then r.screenVeil = nil end
  self.ownsVeil = nil
end

function FadeOverlay:draw()
  if self.sourceRetired then return end
  -- A PALETTE FADE HAS NO OUTSIDE.  When nothing is drawn over the fade it is
  -- painted as the renderer's whole-window veil, so the world bleeding past
  -- the 240x160 surface darkens with it; with a box above it, it stays a
  -- rectangle in the surface so the box remains readable.
  local r = self.game and self.game.renderer
  if r and self.game.stack:top() == self then
    r.screenVeil = { self.color == "white" and 1 or 0, self.alpha or 0 }
    self.ownsVeil = true
    return
  end
  self:releaseVeil()
  if self.color == "white" then
    love.graphics.setColor(1, 1, 1, self.alpha)
  else
    love.graphics.setColor(0, 0, 0, self.alpha)
  end
  -- THE WHOLE SCREEN, not the Game Boy's.  Fixed at 160x144 this covered the
  -- top-left five eighths of a GBA surface and left an unfaded L down the
  -- right and along the bottom, which is worse than no fade at all.
  local w, h = require("src.ui.Theme").uiSize()
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(1, 1, 1, 1)
end

function FadeOverlay:exit()
  self:releaseVeil()
  if self.ow and self.ow.fadeOverlay==self then self.ow.fadeOverlay=nil end
end
function FadeOverlay.describe(state)
  if getmetatable(state)~=FadeOverlay then return nil end
  local ramp=state.ramp
  local direction=ramp and(ramp.to>=ramp.from and 1 or -1)or state.sourceFadeDirection or 0
  return state.alpha or 0,state.color=='white',direction,ramp~=nil,true
end
return FadeOverlay
