-- HORDE MODE: the card at the end.
--
-- A stack state, unlike the mode itself -- and for the opposite reason.
-- Horde mode cannot be a pushed state because pushing one stops the
-- overworld ticking and the player could not walk; the GAME OVER card
-- WANTS exactly that. Pushed, it freezes the world underneath, takes the
-- buttons, and stands there until A.
--
-- It draws in the engine's own 160x144 UI canvas with the game's own
-- font, which is what makes it work in VR for free: with a headset live
-- and something other than the overworld on top of the stack, lib/VR
-- already puts the flat screen on the floating panel (or on the Pokedex
-- in the player's left hand). A card drawn the way the game draws cards
-- arrives there with no VR code at all.
--
-- A pops it and hands over to Horde.finish, which is what puts the world
-- back: the map, the cell, the facing, the camera rung, the hour, the
-- music, and every NPC the horde had turned into a mob.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Horde = V.require("Horde")

local W, H = 160, 144

local HordeGameOver = {}
HordeGameOver.__index = HordeGameOver

function HordeGameOver.new(game)
  local self = setmetatable({}, HordeGameOver)
  self.game = game
  self.isOpaque = true
  self.t = 0
  -- the session is read ONCE, here: Horde.finish clears it, and this card
  -- outlives that by a frame or two while the warp home fades
  local s = Horde.session or {}
  self.score = math.floor(s.score or 0)
  self.best = math.floor(s.best or 0)
  self.wave = math.max(1, s.wave or 1)
  self.kills = s.kills or 0
  self.done = false
  return self
end

function HordeGameOver:update(dt)
  self.t = self.t + (dt or 0)
  if self.done then return end
  -- a beat of dead air before the prompt takes input, so the button that
  -- was being mashed at the moment of death does not dismiss the card
  if self.t < 0.6 then return end
  local input = self.game and self.game.input
  if input and input:wasPressed("a") then
    self.done = true
    pcall(function()
      require("src.core.Sound").play(self.game.data, "Press_AB")
    end)
    self.game.stack:pop()
    pcall(Horde.finish, self.game)
  end
end

-- THE CARD IS DRAWN THE WAY THE GAME DRAWS CARDS: a bordered white box
-- with black text in it (Font.drawBox then setColor(0,0,0)), exactly as
-- HallOfFame and every menu do. That is not decoration -- the UI canvas
-- is a FOUR-SHADE Game Boy screen, and an arbitrary colour drawn into it
-- has nowhere to land. A first cut of this card painted a dark red on
-- near-black and composited as a rectangle of pure black, with the score
-- in it and invisible.
local function centred(Font, str, y, scale)
  scale = scale or 1
  local w = Font.width(str) * scale
  love.graphics.push()
  love.graphics.translate(math.floor((W - w) / 2), y)
  love.graphics.scale(scale, scale)
  Font.draw(str, 0, 0)
  love.graphics.pop()
end

function HordeGameOver:draw()
  local ok, Font = pcall(require, "src.render.Font")
  if not ok then return end

  -- the whole screen as one box: isOpaque keeps the stack from drawing
  -- the world under it, but the canvas still holds whatever was there
  Font.drawBox(0, 0, 20, 18)

  love.graphics.setColor(0, 0, 0, 1)
  centred(Font, "GAME OVER", 3 * 8, 2)

  centred(Font, ("SCORE  %d"):format(self.score), 8 * 8)
  centred(Font, ("WAVE %d"):format(self.wave), 10 * 8)
  centred(Font, ("KILLS %d"):format(self.kills), 11 * 8)

  if self.best > 0 then
    centred(Font, (self.score >= self.best) and "NEW BEST!"
                  or ("BEST  %d"):format(self.best), 13 * 8)
  end

  -- the prompt blinks the way every "press a button" in this game blinks
  if self.t > 0.6 and (self.t % 1.0) < 0.62 then
    centred(Font, "PRESS A", 15 * 8)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return HordeGameOver
