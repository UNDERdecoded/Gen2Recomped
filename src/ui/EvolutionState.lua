-- The evolution movie (engine/movie/evolution.asm): the mon's pic
-- flashes back and forth with the evolved form, speeding up, then the
-- new form appears with its cry and the congratulations text.

local Font = require("src.render.Font")
local Music = require("src.core.Music")
local Strings = require("src.core.Strings")

local EvolutionState = {}
EvolutionState.__index = EvolutionState
EvolutionState.isOpaque = true

-- SGB: SetPal_PokemonWholeScreen for the mon on display
function EvolutionState:sgbPalettes(game)
  local P = require("src.render.PaletteFX")
  -- Always prioritize rendering the mon palette so silhouettes don't crush the whole viewport
  local species = (self.done and not self.canceled) and self.newSpecies or self.mon.species
  local c = P.monPal(game.data, species)
  if c then return { P.whole(c) } end
  return P.wholeNamed(game.data, "MEWMON")
end

local FLASH_FRAMES = 220

local function frontSprite(game, species, mon)
  local path, trueColor = require("src.pokemon.Sprites").path(
    game.data, species, "front", { mon = mon, kind = "evolution" })
  if not path then return nil, false end
  local ok, img = pcall(love.graphics.newImage, path)
  return ok and img or nil, ok and trueColor or false
end

function EvolutionState.new(game, mon, newSpecies, onDone, via, evo)
  local self = setmetatable({}, EvolutionState)
  self.game = game
  self.mon = mon
  self.newSpecies = newSpecies
  self.onDone = onDone
  self.via = via
  self.evo = evo

  -- Trade and item evolutions without link cables should still be cancelable or display properly
  self.cancelable = (via ~= "TRADE" and via ~= "ITEM")
  self.oldName = mon.nickname or game.data.pokemon[mon.species].name
  self.oldSprite, self.oldSpriteTrueColor = frontSprite(game, mon.species, mon)
  self.newSprite, self.newSpriteTrueColor = frontSprite(game, newSpecies, mon)
  self.t = 0
  self.done = false
  self.canceled = false
  Music.play(game.data, Music.special(game.data, "evolution"))
  return self
end

function EvolutionState:update(dt)
  self.t = self.t + 1
  if self.done then return end
  local game = self.game

  if self.cancelable and game.input:isDown("b") then
    self.done = true
    self.canceled = true
    local TextBox = require("src.render.TextBox")
    game.stack:push(TextBox.new(game,
      Strings("Huh? %s\nstopped evolving!", self.oldName),
      function()
        Music.restoreMap(game.data)
        game.stack:pop()
        if self.onDone then self.onDone() end
      end))
    return
  end

  if self.t >= FLASH_FRAMES then
    self.done = true
    local Evolution = require("src.pokemon.Evolution")
    Evolution.apply(game, self.mon, self.newSpecies, self.via, self.evo)
    require("src.core.Sound").playCry(game.data, self.newSpecies)
    local TextBox = require("src.render.TextBox")
    local newName = game.data.pokemon[self.newSpecies].name
    game.stack:push(TextBox.new(game,
      Strings("Congratulations!\nYour %s\nevolved into\n%s!",
              self.oldName, newName),
      function()
        Music.restoreMap(game.data)
        game.stack:pop()
        Evolution.learnEvolutionMoves(game, self.mon, self.onDone)
      end))
  end
end

function EvolutionState:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)

  -- accelerating flash between the two forms
  local sprite, spriteTrueColor
  if self.done then
    if self.canceled then
      sprite, spriteTrueColor = self.oldSprite, self.oldSpriteTrueColor
    else
      sprite, spriteTrueColor = self.newSprite, self.newSpriteTrueColor
    end
  else
    local period = math.max(4, 28 - math.floor(self.t / 40) * 6)
    local showNew = math.floor(self.t / period) % 2 == 1
    if showNew then
      sprite, spriteTrueColor = self.newSprite or self.oldSprite, self.newSpriteTrueColor
    else
      sprite, spriteTrueColor = self.oldSprite, self.oldSpriteTrueColor
    end
  end

  if sprite then
    local x = math.floor((160 - sprite:getWidth()) / 2)
    local y = math.max(8, 64 - sprite:getHeight())
    love.graphics.draw(sprite, x, y)
    if spriteTrueColor then
      require("src.render.PaletteFX").markTrueColor(x, y, sprite:getDimensions())
    end
  end

  love.graphics.setColor(0, 0, 0, 1)
  if not self.done then
    Font.draw(Strings("What?"), 8, 104)
    Font.draw(self.oldName .. " is", 8, 114)
    Font.draw(Strings("evolving!"), 8, 124)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return EvolutionState