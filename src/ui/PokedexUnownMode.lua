-- The Pokédex's UNOWN MODE (engine/pokedex/pokedex.asm Pokedex_UnownMode
-- and Pokedex_UnownModeDescription).
--
-- The Ruins of Alph scientist's dex upgrade (`setflag ENGINE_UNOWN_DEX`) is
-- what puts this page on the option screen: "I added an optional #DEX to
-- store UNOWN data.  It records them in the sequence that they were caught."
-- That sequence is wUnownDex, which UpdateUnownDex appends to the first time
-- each letter is caught and never reorders -- save.pokedex.unownDex here.
--
-- The letters are printed with UnownFont, the 8x8 glyph strip
-- extractUnownDex rips (already inverted, so the glyph is opaque black on a
-- transparent field).  A on a letter opens the description page: that
-- letter's frontpic plus PrintUnownWord's entry out of UnownWords.
--
-- Deviation: the original scatters the 26 letter cells around the frame with
-- UnownModeLetterAndCursorCoords.  This lays them out on a plain 7-wide
-- grid, which reads the same and does not depend on a coordinate table that
-- is not in the cache.

local Font = require("src.render.Font")
local Sound = require("src.core.Sound")
local Assets = require("src.render.Assets")
local Strings = require("src.core.Strings")

local PokedexUnownMode = {}
PokedexUnownMode.__index = PokedexUnownMode
PokedexUnownMode.isOpaque = true

local NUM_UNOWN = 26
local COLS = 7
local CELL = 18
local GRID_X, GRID_Y = 14, 34

-- SGB/CGB: the same PREDEFPAL_POKEDEX screen palette the listing uses
-- (_CGB_Pokedex_Init loads it into BG palette 0).
local PAL = {
  { 255, 255, 255 }, { 255, 165, 82 }, { 214, 82, 49 }, { 0, 0, 0 },
}

function PokedexUnownMode:sgbPalettes()
  return { require("src.render.PaletteFX").whole(PAL) }
end

-- The species record for UNOWN, found by name so the port does not have to
-- know what the cache calls species 201.
local function unownDef(data)
  for _, def in pairs((data and data.pokemon) or {}) do
    if def.name == "UNOWN" then return def end
  end
  return nil
end

-- wUnownDex, in catch order.  Saves written before the ordered list existed
-- only have the unownForms set, so fall back to alphabetical for those
-- rather than showing an empty page.
local function caughtLetters(save)
  local dex = save and save.pokedex
  if not dex then return {} end
  local ordered = dex.unownDex
  if type(ordered) == "table" and #ordered > 0 then
    local out = {}
    for _, letter in ipairs(ordered) do
      if type(letter) == "number" and letter >= 1 and letter <= NUM_UNOWN then
        out[#out + 1] = letter
      end
    end
    return out
  end
  local out = {}
  for letter = 1, NUM_UNOWN do
    if dex.unownForms and dex.unownForms[letter] then out[#out + 1] = letter end
  end
  return out
end

function PokedexUnownMode.new(game, opts)
  opts = opts or {}
  local self = setmetatable({
    game = game,
    def = (game.data and game.data.unown_dex) or nil,
    mon = unownDef(game.data),
    letters = caughtLetters(game.save),
    index = 1,
    describing = false,
    onCancel = opts.onCancel,
    pics = {},
  }, PokedexUnownMode)
  return self
end

function PokedexUnownMode:letter()
  return self.letters[self.index]
end

function PokedexUnownMode:update()
  local input = self.game.input
  if input:wasPressed("b") then
    if self.describing then
      self.describing = false
      return
    end
    self.game.stack:pop()
    if self.onCancel then self.onCancel() end
    return
  end
  if #self.letters == 0 then return end
  if input:wasPressed("a") then
    self.describing = not self.describing
    Sound.play(self.game.data, "Press_AB")
    return
  end
  local moved = self.index
  if input:wasPressed("left") then moved = moved - 1 end
  if input:wasPressed("right") then moved = moved + 1 end
  if input:wasPressed("up") then moved = moved - COLS end
  if input:wasPressed("down") then moved = moved + COLS end
  if moved ~= self.index and moved >= 1 and moved <= #self.letters then
    self.index = moved
  end
end

-- ------- art

function PokedexUnownMode:font()
  if self._font ~= nil then return self._font or nil end
  local path = self.def and self.def.font
  local img = false
  if path and Assets.exists(path) then
    local ok, loaded = pcall(love.graphics.newImage, Assets.resolve(path))
    if ok then img = loaded end
  end
  self._font = img
  return img or nil
end

function PokedexUnownMode:pic(letter)
  if self.pics[letter] ~= nil then return self.pics[letter] or nil end
  local form = self.mon and self.mon.forms and self.mon.forms[letter]
  local path = form and form.spriteFront
  local img = false
  if path then
    local ok, loaded = pcall(love.graphics.newImage, path)
    if ok then img = loaded end
  end
  self.pics[letter] = img
  return img or nil
end

function PokedexUnownMode:drawGlyph(letter, x, y)
  local img = self:font()
  if not img then
    -- no UnownFont in the cache (imported before v39): Roman letters keep
    -- the page readable
    love.graphics.setColor(0, 0, 0, 1)
    Font.draw(string.char(64 + letter), x, y)
    return
  end
  local quad = love.graphics.newQuad(
    (letter - 1) * 8, 0, 8, 8, img:getDimensions())
  love.graphics.draw(img, quad, x, y)
end

-- ------- draw

local function frame()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(0, 0, 0, 1)
  love.graphics.rectangle("line", 4.5, 4.5, 151, 135)
end

function PokedexUnownMode:drawGrid()
  frame()
  Font.draw(Strings("UNOWN MODE"), 12, 12)
  if #self.letters == 0 then
    -- UnownDexVacantString's stand-in: nothing has been caught yet
    Font.draw(Strings("NO UNOWN DATA"), 12, GRID_Y)
    Font.draw(Strings("B:EXIT"), 12, 126)
    return
  end
  for i, letter in ipairs(self.letters) do
    local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
    local x, y = GRID_X + col * CELL, GRID_Y + row * CELL
    if i == self.index then
      love.graphics.setColor(0, 0, 0, 1)
      love.graphics.rectangle("line", x - 3.5, y - 3.5, 15, 15)
    end
    love.graphics.setColor(1, 1, 1, 1)
    self:drawGlyph(letter, x, y)
  end
  love.graphics.setColor(0, 0, 0, 1)
  Font.draw(Strings("%d/%d CAUGHT", #self.letters, NUM_UNOWN), 12, 112)
  Font.draw(Strings("A:VIEW  B:EXIT"), 12, 126)
end

function PokedexUnownMode:drawDescription()
  frame()
  local letter = self:letter()
  Font.draw(Strings("UNOWN MODE"), 12, 12)
  local pic = letter and self:pic(letter)
  if pic then
    local w, h = pic:getDimensions()
    local x, y = (160 - w) / 2, 32
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(pic, x, y)
    if self.mon and self.mon.trueColor then
      require("src.render.PaletteFX").markTrueColor(x, y, w, h)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  if letter then self:drawGlyph(letter, 76, 96) end
  love.graphics.setColor(0, 0, 0, 1)
  -- PrintUnownWord: the letter's word, centred on the bottom row
  local words = self.def and self.def.words
  local word = letter and words and words[letter]
  if word and word ~= "" then
    Font.draw(word, math.max(8, (160 - #word * 8) / 2), 112)
  end
  Font.draw(Strings("B:BACK"), 12, 126)
end

function PokedexUnownMode:draw()
  if self.describing then self:drawDescription() else self:drawGrid() end
  love.graphics.setColor(1, 1, 1, 1)
end

return PokedexUnownMode
